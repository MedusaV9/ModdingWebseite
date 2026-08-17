import SwiftUI
import UIKit

// The gallery's fullscreen pager (W9A component split from GalleryView):
// pages through the active filter slice, edits captions, favorites,
// saves and deletes — all on the shared MediaLightbox pieces.

struct PhotoPagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var photos: [Photo]
    let startId: String
    let filter: GalleryFilter
    /// Reported back to the grid so dismissing restores the scroll position
    /// to whatever the pager last showed.
    @Binding var lastViewedId: String?

    @State private var currentId = ""
    /// Last known position of `currentId` within the visible slice — used to
    /// clamp to a neighbor when the current photo drops out of the slice.
    @State private var lastVisibleIndex = 0
    @State private var confirmDelete = false
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var busy = false
    /// Pages currently pinch-zoomed beyond 1× — while the visible page is in
    /// here, the shell's drag-down dismiss stays out of the scroll view's way.
    @State private var zoomedIds = Set<String>()
    /// Single tap toggles the chrome (controls + caption) like Apple Photos.
    @State private var chromeVisible = true

    var body: some View {
        MediaLightboxShell(dragDismissEnabled: !zoomedIds.contains(currentId),
                           onDismiss: { dismiss() }) {
            pager
        } chrome: {
            if chromeVisible {
                overlayControls
                captionOverlay
            }
        }
        .onAppear {
            currentId = startId
            lastVisibleIndex = visiblePhotos.firstIndex { $0.id == startId } ?? 0
            preloadNeighbors()
        }
        .onChange(of: currentId) { _, newId in
            if let idx = visiblePhotos.firstIndex(where: { $0.id == newId }) {
                lastVisibleIndex = idx
            }
            lastViewedId = newId
            preloadNeighbors()
        }
        .onChange(of: visibleIds) { _, ids in
            guard !ids.contains(currentId) else { return }
            guard !ids.isEmpty else {
                dismiss()
                return
            }
            currentId = ids[min(lastVisibleIndex, ids.count - 1)]
        }
        .confirmationDialog(L10n.t("memories.gallery.deleteConfirm"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteCurrent() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("memories.gallery.editCaption"), isPresented: $editingCaption) {
            TextField(L10n.t("memories.gallery.captionPlaceholder"), text: $captionDraft)
            Button(L10n.t("common.save")) { saveCaption() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
    }

    /// The slice the pager pages over — mirrors the grid filter. Derived from
    /// the master array so mutations (favorites, deletes) flow straight back.
    private var visiblePhotos: [Photo] {
        photos.filter { filter.matches($0) }
    }

    private var visibleIds: [String] {
        visiblePhotos.map(\.id)
    }

    private var currentPhoto: Photo? {
        photos.first { $0.id == currentId }
    }

    private var pager: some View {
        TabView(selection: $currentId) {
            ForEach(visiblePhotos) { photo in
                pageContent(photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }

    private func pageContent(_ photo: Photo) -> some View {
        MediaLightboxImage(api: appState.api, path: photo.url, thumbPath: photo.thumbUrl,
                           onZoomedChange: { zoomed in
                               if zoomed {
                                   zoomedIds.insert(photo.id)
                               } else {
                                   zoomedIds.remove(photo.id)
                               }
                           },
                           onSingleTap: {
                               withAnimation(Theme.Motion.settle) { chromeVisible.toggle() }
                           })
        // Roadmap 19, drag-OUT (iPad): long-press-drag lifts the photo out
        // of the lightbox as a real JPEG — pinch/pan/dismiss keep their own
        // immediate gestures, the drag only arms on the press-and-hold lift.
        .draggable(PhotoDragPayload(api: appState.api, path: photo.url))
    }

    /// Warms the pipeline cache for the neighboring pages so a swipe lands on
    /// an already-decoded image instead of a skeleton.
    private func preloadNeighbors() {
        guard let api = appState.api,
              let idx = visiblePhotos.firstIndex(where: { $0.id == currentId }) else { return }
        for offset in [-1, 1] {
            let neighbor = idx + offset
            guard visiblePhotos.indices.contains(neighbor) else { continue }
            let path = visiblePhotos[neighbor].url
            Task.detached(priority: .utility) {
                // Best-effort cache warm — a miss only means the page loads
                // thumb-first on arrival, exactly like today.
                do {
                    _ = try await ImagePipeline.shared.image(api: api, path: path,
                                                             maxPixelSize: 2_048)
                } catch {}
            }
        }
    }

    /// Caption card pinned to the bottom, part of the chrome layer — it fades
    /// with the drag-dismiss and toggles with the single tap.
    @ViewBuilder
    private var captionOverlay: some View {
        if let photo = currentPhoto {
            VStack {
                Spacer()
                captionBar(photo)
            }
        }
    }

    /// The polaroid's handwriting strip: the caption is the couple's own
    /// voice (serif, dark ink) on polaroid paper, the author signs with an
    /// ink dot in their member color and the date line is a postmark.
    /// The viewer around it deliberately stays dark and immersive — this
    /// Zettel is the one piece of paper in the lightbox.
    private func captionBar(_ photo: Photo) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            EmojiAvatarView(emoji: uploader(of: photo)?.avatar,
                            colorHex: uploader(of: photo)?.color,
                            size: LayoutMetrics.s(40))
            VStack(alignment: .leading, spacing: 2) {
                if let caption = photo.caption, !caption.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                        Circle()
                            .fill(authorInk(of: photo))
                            .frame(width: LayoutMetrics.s(6), height: LayoutMetrics.s(6))
                            .accessibilityHidden(true)
                        Text(caption)
                            .font(Typo.voice)
                            .foregroundStyle(Tinte.dunkel)
                            .lineLimit(3)
                    }
                }
                Text(uploadInfo(photo))
                    .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .foregroundStyle(Tinte.sekundaer)
                if let album = photo.album, !album.isEmpty {
                    Label(album, systemImage: "folder")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.tertiaer)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .paperCard(.polaroid, padding: .compact)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.xl)
    }

    /// The author's member color as readable ink on the polaroid strip
    /// (inkOnPaper ladder — ≥ 4.5:1 on every paper tone, pinned).
    private func authorInk(of photo: Photo) -> Color {
        guard let hex = uploader(of: photo)?.color else { return coupleTint.tinte }
        return Color(hex: CouplePaletteRules.inkOnPaper(hex))
    }

    /// "3 von 24" — replaces the page dots (which get lost beyond a dozen
    /// photos) with an honest position readout.
    @ViewBuilder
    private var pagerCounter: some View {
        if visiblePhotos.count > 1, lastVisibleIndex < visiblePhotos.count {
            Text(L10n.t("memories.pager.counter",
                        ["n": String(lastVisibleIndex + 1),
                         "total": String(visiblePhotos.count)]))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var overlayControls: some View {
        VStack {
            HStack(spacing: Space.l) {
                circleButton(icon: "xmark") { dismiss() }
                Spacer()
                pagerCounter
                Spacer()
                if busy {
                    BusySpinner()
                        .padding(10)
                } else {
                    favoriteButton
                    circleButton(icon: "pencil") {
                        captionDraft = currentPhoto?.caption ?? ""
                        editingCaption = true
                    }
                    circleButton(icon: "square.and.arrow.down") { saveCurrent() }
                    if currentPhoto?.uploaderId == appState.memberId {
                        circleButton(icon: "trash") { confirmDelete = true }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var currentIsFavorite: Bool {
        currentPhoto?.isFavorite(of: appState.memberId) ?? false
    }

    private var favoriteButton: some View {
        circleButton(icon: currentIsFavorite ? "heart.fill" : "heart",
                     tint: currentIsFavorite ? coupleTint.blend : .white) {
            toggleFavorite()
        }
        .accessibilityLabel(L10n.t("memories.gallery.favorite"))
    }

    private func circleButton(icon: String, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                // Scrim circle, not glass: viewer chrome floats over bright
                // photos, where a dark scrim reads better than refraction.
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    private func uploader(of photo: Photo) -> Member? {
        appState.couple?.members.first { $0.id == photo.uploaderId }
    }

    private func uploadInfo(_ photo: Photo) -> String {
        let name = photo.uploaderId == appState.memberId
            ? L10n.t("common.you")
            : (uploader(of: photo)?.name ?? appState.partnerName)
        let date = photo.createdAt.formatted(date: .abbreviated, time: .shortened)
        return L10n.t("memories.gallery.by", ["name": name]) + " · " + date
    }

    // MARK: Actions

    private func toggleFavorite() {
        guard let photo = currentPhoto, let api = appState.api,
              let myId = appState.memberId else { return }
        let wasFavorite = photo.isFavorite(of: myId)
        setMyFavorite(!wasFavorite, on: photo.id, myId: myId)
        Haptics.shared.success()
        Task {
            do {
                let updated = try await api.togglePhotoFavorite(id: photo.id)
                merge(updated)
            } catch {
                // Revert by inverting only MY op on the CURRENT array — a partner's
                // concurrent photo_updated (their heart) stays intact.
                setMyFavorite(wasFavorite, on: photo.id, myId: myId)
                appState.handleAPIError(error)
            }
        }
    }

    /// Adds/removes only MY member id in the photo's current favorites array.
    private func setMyFavorite(_ favorite: Bool, on photoId: String, myId: String) {
        guard let idx = photos.firstIndex(where: { $0.id == photoId }) else { return }
        var favorites = photos[idx].favorites ?? []
        if favorite {
            if !favorites.contains(myId) { favorites.append(myId) }
        } else {
            favorites.removeAll { $0 == myId }
        }
        photos[idx].favorites = favorites
    }

    private func merge(_ photo: Photo) {
        guard let idx = photos.firstIndex(where: { $0.id == photo.id }) else { return }
        photos[idx] = photo
    }

    /// PATCH the caption (empty draft = clear it via explicit null).
    private func saveCaption() {
        guard let photo = currentPhoto, let api = appState.api else { return }
        let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String? = trimmed.isEmpty ? nil : trimmed
        guard (photo.caption ?? "") != (target ?? "") else { return }
        busy = true
        Task {
            do {
                let updated = try await api.patchPhoto(id: photo.id, caption: .some(target))
                merge(updated)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.captionSaved"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private func deleteCurrent() {
        guard let photo = currentPhoto, let api = appState.api else { return }
        busy = true
        Task {
            do {
                try await api.deletePhoto(id: photo.id)
                photos.removeAll { $0.id == photo.id }
                appState.showToast(L10n.t("memories.gallery.deleted"), style: .info)
                if photos.isEmpty { dismiss() }
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private func saveCurrent() {
        guard let photo = currentPhoto, let api = appState.api else { return }
        busy = true
        Task {
            do {
                let data = try await api.mediaData(photo.url)
                guard let image = BoundedImageDecoder.image(data: data, maxPixelSize: 4_096) else {
                    throw URLError(.cannotDecodeContentData)
                }
                GalleryImageSaver.save(image) { ok in
                    if ok {
                        Haptics.shared.success()
                        appState.showToast(L10n.t("memories.gallery.savedToLibrary"), style: .success)
                    } else {
                        appState.showToast(L10n.t("memories.gallery.saveFailed"), style: .error)
                    }
                }
            } catch {
                appState.showToast(L10n.t("memories.gallery.saveFailed"), style: .error)
            }
            busy = false
        }
    }
}

// MARK: - Photo library saver

/// UIImageWriteToSavedPhotosAlbum needs an Obj-C completion target;
/// instances keep themselves alive until the callback fires.
final class GalleryImageSaver: NSObject {
    private static var active: [GalleryImageSaver] = []
    private var completion: ((Bool) -> Void)?

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let saver = GalleryImageSaver()
        saver.completion = completion
        active.append(saver)
        UIImageWriteToSavedPhotosAlbum(image, saver,
                                       #selector(GalleryImageSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage,
                             didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeRawPointer) {
        let ok = error == nil
        DispatchQueue.main.async {
            self.completion?(ok)
            Self.active.removeAll { $0 === self }
        }
    }
}
