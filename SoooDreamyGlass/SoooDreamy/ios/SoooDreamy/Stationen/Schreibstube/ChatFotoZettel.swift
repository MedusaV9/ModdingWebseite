import SwiftUI
import UIKit

// Zone „Spindel" — der Foto-Zettel und sein Vollbild-Betrachter.
// Reiner Struktur-Umzug aus ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

// MARK: - Photo bubble

/// A shared gallery photo in the chat (`message.photoId`). Tries the photo's
/// small grid thumbnail first and falls back to the full image when there is
/// none; tapping opens a fullscreen viewer. The referenced photo has its own
/// lifetime — if it was deleted from the gallery, the media 404s and the
/// bubble shows an error placeholder.
struct ChatPhotoBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    var group = ChatGroupPosition()
    let onReact: (String) -> Void
    var onDelete: (() -> Void)? = nil

    /// Set when the thumbnail fails (e.g. none was ever uploaded) —
    /// switches the bubble to the full-resolution URL.
    @State private var thumbFailed = false
    @State private var showViewer = false

    private var side: CGFloat { LayoutMetrics.s(210) }

    private var imagePath: String? {
        guard let photoId = message.photoId else { return nil }
        return thumbFailed ? "/api/photos/\(photoId)/raw" : "/api/photos/\(photoId)/thumb/raw"
    }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            photoArea
            if let caption = message.text, !caption.isEmpty {
                Text(caption)
                    .font(.system(.callout, design: .rounded))
                    // Same rule as the text bubble: both sides are paper
                    // Zettel (R1-A) — captions read in dark ink.
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
            }
            if group.isEnd {
                ChatTimestampText(date: message.createdAt, isMine: isMine,
                                  read: chatReadReceipt(for: message, isMine: isMine,
                                                        partner: appState.partner))
            }
        }
        .padding(LayoutMetrics.s(8))
        .background(ChatBubbleBackground(isMine: isMine,
                                         groupedTop: !group.isStart,
                                         groupedBottom: !group.isEnd))
        .contentShape(RoundedRectangle(cornerRadius: ChatBubbleBackground.radius(isMine: isMine),
                                       style: .continuous))
        .onTapGesture(count: 2) {
            onReact(ChatReactions.quick)
        }
        .onTapGesture {
            Haptics.shared.tap()
            showViewer = true
        }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            if let photoId = message.photoId {
                // W6-Rest: the bubble is a WINDOW into the gallery — this
                // opens the real thing (lightbox on exactly this photo).
                Button {
                    appState.openGalleryPhoto(photoId)
                } label: {
                    Label(L10n.t("chat.photoShowInAlbum"),
                          systemImage: "photo.on.rectangle.angled")
                }
            }
            ChatPinButton(message: message)
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
        .accessibilityLabel(L10n.t("chat.photoMessage"))
        .fullScreenCover(isPresented: $showViewer) {
            ChatPhotoViewer(message: message)
        }
    }

    @ViewBuilder private var photoArea: some View {
        let area = Group {
            if let path = imagePath {
                AuthenticatedAsyncImage(api: appState.api, path: path) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        if thumbFailed {
                            photoPlaceholder(icon: "photo.badge.exclamationmark")
                        } else {
                            // No thumbnail on the server — retry with the full image.
                            photoPlaceholder(icon: nil)
                                .onAppear { thumbFailed = true }
                        }
                    default:
                        photoPlaceholder(icon: nil)
                    }
                }
            } else {
                photoPlaceholder(icon: "photo")
            }
        }
        .frame(width: side, height: side)
        // Concentric with the bubble corner: photo radius = bubble radius
        // minus the bubble's own padding, so both corners share one center —
        // both Zettel cut at Radius.papier since R1-A, so their photos do too.
        .clipShape(RoundedRectangle(
            cornerRadius: Radius.concentric(parent: ChatBubbleBackground.radius(isMine: isMine),
                                            padding: Space.s),
            style: .continuous))
        if let photoId = message.photoId {
            // Drag-OUT (roadmap 19): the photo leaves the chat as a full-res
            // JPEG — the drag arms on the press-and-hold lift, so tap
            // (viewer), double-tap (react) and the context menu keep theirs.
            area.draggable(PhotoDragPayload(
                api: appState.api, path: "/api/photos/\(photoId)/raw"))
        } else {
            area
        }
    }

    /// Loading state is a skeleton in the shape of the coming photo (the
    /// slow light sweep says "almost here"); only real failures show an icon.
    /// Both bubbles are paper Zettel (R1-A): the well is the paper inner
    /// fill with tertiary ink, and waiting uses the PAPER skeleton — the
    /// night-era glass wash is invisible on brief/polaroid.
    @ViewBuilder private func photoPlaceholder(icon: String?) -> some View {
        if let icon {
            ZStack {
                Rectangle().fill(Papier.innenFill)
                Image(systemName: icon)
                    .font(.system(.title, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
        } else {
            PaperSkeleton(kind: .tile(height: 210))
        }
    }
}

/// Fullscreen viewer for one photo message — same MediaLightbox pieces as the
/// gallery pager and the vault viewer, so pinch-zoom, double-tap and
/// drag-down-dismiss feel identical in every context (B-31).
struct ChatPhotoViewer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let message: Message

    @State private var zoomed = false
    @State private var chromeVisible = true

    var body: some View {
        MediaLightboxShell(dragDismissEnabled: !zoomed,
                           onDismiss: { dismiss() }) {
            imageArea
        } chrome: {
            if chromeVisible {
                chrome
            }
        }
    }

    private var chrome: some View {
        VStack {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, LayoutMetrics.s(16))
            .padding(.top, 8)
            Spacer()
            if let caption = message.text, !caption.isEmpty {
                Text(caption)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                    .padding(LayoutMetrics.s(14))
                    // The caption FLOATS over the black lightbox — that is
                    // chrome, not content: real glass instead of the retired
                    // surface card (deliberate glass exception, like the
                    // close button above).
                    .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.control,
                                                         style: .continuous))
                    .padding(.horizontal, LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(24))
            }
        }
    }

    @ViewBuilder private var imageArea: some View {
        if let photoId = message.photoId {
            // Thumb-first: the bubble already decoded the /thumb/raw image at
            // the shared budget, so the viewer opens on it instantly and the
            // full resolution sharpens in place.
            MediaLightboxImage(api: appState.api,
                               path: "/api/photos/\(photoId)/raw",
                               thumbPath: "/api/photos/\(photoId)/thumb/raw",
                               onZoomedChange: { zoomed = $0 },
                               onSingleTap: {
                                   withAnimation(Theme.Motion.settle) { chromeVisible.toggle() }
                               })
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(L10n.t("chat.photoFailed"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.shared.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                // Viewer chrome rides real chrome glass, like every other
                // floating control — not a hand-painted white disc.
                .glass(.chrome, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.readerClose"))
    }
}
