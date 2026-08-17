import SwiftUI
import UIKit

// The ONE media lightbox of the app (K-01): every fullscreen viewer —
// gallery pager, chat photo, vault photo — composes the same three pieces,
// so pinch-zoom, double-tap and drag-down-dismiss feel identical everywhere.
//
//   ZoomableImageView   UIScrollView-backed pinch zoom (1–4×), double-tap
//                       to the tapped point, single-tap chrome toggle.
//   MediaLightboxImage  authenticated thumb-first loading: the grid's cached
//                       thumbnail appears instantly (softly blurred), the
//                       full resolution crossfades in over it.
//   MediaLightboxShell  black backdrop + drag-down dismiss with physics
//                       (content follows the finger, shrinks, corners round,
//                       backdrop clears) + chrome that fades while dragging.

// MARK: - Zoomable image (UIScrollView wrapper)

/// Native UIScrollView zooming — 120 Hz, bounce and deceleration for free,
/// exactly like Apple Photos. SwiftUI's MagnifyGesture cannot match that.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Reports `true` while zoomed beyond 1× (hosts disable page-swipe
    /// conflicts and drag-dismiss while zoomed).
    var onZoomedChange: ((Bool) -> Void)?
    /// Single tap (after double-tap disambiguation) — chrome toggle.
    var onSingleTap: (() -> Void)?

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = ZoomHostScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.alwaysBounceVertical = false
        scroll.alwaysBounceHorizontal = false
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scroll.bounds
        imageView.autoresizingMask = []
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        scroll.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        let singleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleSingleTap(_:)))
        singleTap.require(toFail: doubleTap)
        imageView.addGestureRecognizer(singleTap)

        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.parent = self
        guard let host = scroll as? ZoomHostScrollView else { return }
        if host.imageView?.image !== image {
            host.imageView?.image = image
            scroll.setZoomScale(1, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Keeps the image view glued to the scroll view's bounds at 1× (layout
    /// passes, rotation) without fighting an active zoom.
    final class ZoomHostScrollView: UIScrollView {
        weak var imageView: UIImageView?

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let imageView, zoomScale == minimumZoomScale,
                  imageView.frame.size != bounds.size else { return }
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableImageView
        weak var scrollView: UIScrollView?
        private var reportedZoomed = false

        init(parent: ZoomableImageView) {
            self.parent = parent
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ZoomHostScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            if zoomed != reportedZoomed {
                reportedZoomed = zoomed
                parent.onZoomedChange?(zoomed)
            }
        }

        /// Aspect-fit content stays optically centered while smaller than
        /// the viewport during a zoom bounce.
        private func centerContent(_ scrollView: UIScrollView) {
            let dx = max(0, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
            let dy = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        /// Double tap: zoom to 2.5× AT the tapped point; a second double
        /// tap returns to 1× — the standard UIKit way, like Apple Photos.
        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let target: CGFloat = 2.5
                let point = recognizer.location(in: viewForZooming(in: scrollView))
                let size = CGSize(width: scrollView.bounds.width / target,
                                  height: scrollView.bounds.height / target)
                let rect = CGRect(x: point.x - size.width / 2,
                                  y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            parent.onSingleTap?()
        }
    }
}

// MARK: - Authenticated, thumb-first lightbox image

/// Loads the full-resolution image through the shared ImagePipeline while
/// instantly showing the thumbnail the grid already decoded — no spinner
/// staring, the photo sharpens in place.
struct MediaLightboxImage: View {
    let api: API?
    /// Full-resolution media path.
    let path: String
    /// Grid thumbnail path (same budget as the grid so its cache hits).
    var thumbPath: String?
    var onZoomedChange: ((Bool) -> Void)?
    var onSingleTap: (() -> Void)?

    @State private var full: UIImage?
    @State private var thumb: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let full {
                ZoomableImageView(image: full,
                                  onZoomedChange: onZoomedChange,
                                  onSingleTap: onSingleTap)
                    .transition(.opacity)
            } else if let thumb {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .blur(radius: 8)
                    .accessibilityHidden(true)
            } else if failed {
                failurePlaceholder
            } else {
                GlassSkeleton(kind: .tile(height: 220))
                    .padding(.horizontal, Space.xl)
            }
        }
        .animation(Theme.Motion.arrive, value: full == nil)
        .contentShape(Rectangle())
        .onTapGesture { onSingleTap?() }
        .task(id: path) { await load() }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            Text(L10n.t("chat.photoFailed"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func load() async {
        guard let api else { return }
        // The grid decodes thumbs at the shared default budget — peeking with
        // the same budget makes this a guaranteed synchronous cache hit right
        // after tapping a cell.
        if full == nil, let thumbPath,
           let cached = ImagePipeline.shared.cachedImage(baseURL: api.baseURL,
                                                         path: thumbPath,
                                                         maxPixelSize: 2_048) {
            thumb = cached
        }
        do {
            full = try await ImagePipeline.shared.image(api: api, path: path,
                                                        maxPixelSize: 2_048)
        } catch {
            // Full resolution failed — fall back to fetching the thumb so the
            // viewer still shows the moment instead of an error glyph.
            if thumb == nil, let thumbPath {
                do {
                    thumb = try await ImagePipeline.shared.image(api: api, path: thumbPath,
                                                                 maxPixelSize: 2_048)
                } catch {
                    failed = true
                }
            }
            failed = thumb == nil
        }
    }
}

// MARK: - Shell (backdrop + drag-down dismiss + chrome fade)

/// Fullscreen scaffold shared by every viewer: black backdrop, drag-down
/// dismiss with physics, chrome that fades while dragging. Horizontal drags
/// stay untouched (they belong to pagers), and hosts disable the gesture
/// entirely while zoomed in.
struct MediaLightboxShell<Content: View, Chrome: View>: View {
    /// Off while the current page is zoomed (the scroll view owns pans then).
    var dragDismissEnabled = true
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var chrome: () -> Chrome

    @State private var dragOffset: CGFloat = 0
    /// Set once per gesture when the first movement is clearly horizontal —
    /// the whole drag then stays with the pager.
    @State private var horizontalLock = false

    /// 0 (resting) … 1 (far enough to dismiss).
    private var progress: CGFloat {
        min(abs(dragOffset) / 320, 1)
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(1 - Double(progress) * 0.75)
                .ignoresSafeArea()
            content()
                .offset(y: dragOffset)
                .scaleEffect(1 - progress * 0.3)
                .clipShape(RoundedRectangle(cornerRadius: progress * 36, style: .continuous))
            chrome()
                .opacity(1 - Double(min(progress * 2.5, 1)))
        }
        .gesture(dragGesture, including: dragDismissEnabled ? .all : .subviews)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if dragOffset == 0 && !horizontalLock,
                   abs(value.translation.width) > abs(value.translation.height) {
                    horizontalLock = true
                }
                guard !horizontalLock else { return }
                // Follow downward pulls 1:1; resist upward ones.
                let dy = value.translation.height
                dragOffset = dy > 0 ? dy : dy / 3
            }
            .onEnded { value in
                defer { horizontalLock = false }
                guard !horizontalLock else { return }
                let projected = value.predictedEndTranslation.height
                if dragOffset > 140 || projected > 320 {
                    Haptics.shared.tap()
                    onDismiss()
                    // Reset after the cover animation so a reused shell
                    // (fullScreenCover identity) starts clean.
                    dragOffset = 0
                } else {
                    withAnimation(Theme.Motion.settle) {
                        dragOffset = 0
                    }
                }
            }
    }
}
