import SwiftUI
import Combine
import PhotosUI
import UIKit

/// Shared photo gallery: grid, PhotosPicker upload with caption, fullscreen pager.
struct GalleryView: View {
    @Environment(AppState.self) private var appState

    @State private var photos: [Photo] = []
    @State private var loading = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingUpload: PendingUpload?
    @State private var uploading = false
    @State private var pagerTarget: Photo?
    @State private var celebrationDate: Date?
    @State private var celebrationTask: Task<Void, Never>?
    @State private var filter: GalleryFilter = .all

    private enum GalleryFilter: String, CaseIterable, Identifiable {
        case all, favorites
        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .all: return "memories.gallery.filterAll"
            case .favorites: return "memories.gallery.filterFavorites"
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            floatingAddButton
            if let started = celebrationDate {
                FloatingHeartsView(emojis: ["📸", "💜", "✨", "💖"], count: 14, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("memories.gallery.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhotos() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await preparePhoto(item) }
        }
        .sheet(item: $pendingUpload) { pending in
            CaptionSheet(pending: pending) { caption in
                upload(pending, caption: caption)
            }
        }
        .fullScreenCover(item: $pagerTarget) { photo in
            PhotoPagerView(photos: $photos, startId: photo.id,
                           favoritesOnly: filter == .favorites)
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LoadingView()
        } else if photos.isEmpty {
            emptyState
        } else {
            gridArea
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "📸",
                           title: L10n.t("memories.gallery.empty.title"),
                           subtitle: L10n.t("memories.gallery.empty.subtitle"))
            Spacer()
        }
    }

    /// Photos matching the active filter (favorites = liked by either member).
    private var displayedPhotos: [Photo] {
        switch filter {
        case .all:
            return photos
        case .favorites:
            return photos.filter { !($0.favorites ?? []).isEmpty }
        }
    }

    private var gridArea: some View {
        VStack(spacing: 0) {
            filterChips
            if filter == .favorites && displayedPhotos.isEmpty {
                Spacer()
                EmptyStateView(emoji: "💗",
                               title: L10n.t("memories.gallery.favEmpty.title"),
                               subtitle: L10n.t("memories.gallery.favEmpty.subtitle"))
                Spacer()
            } else {
                grid
            }
        }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(GalleryFilter.allCases) { candidate in
                filterChip(candidate)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private func filterChip(_ candidate: GalleryFilter) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) { filter = candidate }
        } label: {
            Text(L10n.t(candidate.titleKey))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(filter == candidate ? .white : Theme.textSecondary)
                .padding(.vertical, 7)
                .padding(.horizontal, 14)
                .background(
                    Capsule().fill(filter == candidate ? Theme.pink.opacity(0.55) : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(displayedPhotos) { photo in
                    Button {
                        Haptics.shared.tap()
                        pagerTarget = photo
                    } label: {
                        GalleryCell(photo: photo, api: appState.api, memberId: appState.memberId)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .refreshable { await loadPhotos() }
    }

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        Circle()
                            .fill(Theme.heroGradient)
                            .frame(width: 60, height: 60)
                            .shadow(color: Theme.pink.opacity(0.5), radius: 14, y: 6)
                        if uploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(uploading)
                .accessibilityLabel(L10n.t("memories.gallery.add"))
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Data

    private func loadPhotos() async {
        guard let api = appState.api else { return }
        do {
            let list = try await api.photos()
            photos = list.sorted { $0.createdAt > $1.createdAt }
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private func insert(_ photo: Photo) {
        guard !photos.contains(where: { $0.id == photo.id }) else { return }
        photos.append(photo)
        photos.sort { $0.createdAt > $1.createdAt }
    }

    /// Replace an existing photo (id match) or insert it.
    private func apply(_ photo: Photo) {
        if let idx = photos.firstIndex(where: { $0.id == photo.id }) {
            photos[idx] = photo
        } else {
            insert(photo)
        }
    }

    // MARK: Upload flow

    private func preparePhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
                return
            }
            let scaled = Self.downscaled(image, maxDimension: 2048)
            guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else {
                appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
                return
            }
            pendingUpload = PendingUpload(jpeg: jpeg, image: scaled)
        } catch {
            appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
        }
    }

    private func upload(_ pending: PendingUpload, caption: String) {
        guard let api = appState.api else { return }
        uploading = true
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let photo = try await api.uploadPhoto(jpeg: pending.jpeg,
                                                      caption: trimmed.isEmpty ? nil : trimmed,
                                                      width: Int(pending.image.size.width),
                                                      height: Int(pending.image.size.height))
                insert(photo)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.uploaded"), style: .love)
                celebrate()
                await uploadThumbnail(for: photo, from: pending.image, api: api)
            } catch {
                appState.handleAPIError(error)
            }
            uploading = false
        }
    }

    /// Best-effort grid thumbnail — the grid falls back to the full url if it fails.
    private func uploadThumbnail(for photo: Photo, from image: UIImage, api: API) async {
        let thumb = Self.downscaled(image, maxDimension: 320)
        guard let jpeg = thumb.jpegData(compressionQuality: 0.7) else { return }
        if let updated = try? await api.uploadPhotoThumb(photoId: photo.id, jpeg: jpeg) {
            apply(updated)
        }
    }

    private func celebrate() {
        celebrationDate = Date()
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { celebrationDate = nil }
        }
    }

    /// Downscale so the longest side is at most `maxDimension` (device pixels).
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let maxSide = max(pixelWidth, pixelHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        guard maxSide > maxDimension else {
            guard image.scale != 1 else { return image }
            let size = CGSize(width: pixelWidth, height: pixelHeight)
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
        }
        let factor = maxDimension / maxSide
        let size = CGSize(width: floor(pixelWidth * factor), height: floor(pixelHeight * factor))
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: Realtime

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .photoAdded:
            guard let photo = event.decode(PhotoResponse.self)?.photo else { return }
            let isNew = !photos.contains(where: { $0.id == photo.id })
            insert(photo)
            if isNew && photo.uploaderId != appState.memberId {
                SoundEngine.shared.play(.pop)
            }
        case .photoUpdated:
            guard let photo = event.decode(PhotoResponse.self)?.photo else { return }
            apply(photo)
        case .photoDeleted:
            guard let id = event.decode(IdPayload.self)?.id else { return }
            photos.removeAll { $0.id == id }
        default:
            break
        }
    }
}

// MARK: - Pending upload

private struct PendingUpload: Identifiable {
    let id = UUID()
    let jpeg: Data
    let image: UIImage
}

// MARK: - Grid cell

private struct GalleryCell: View {
    let photo: Photo
    let api: API?
    let memberId: String?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) { favoriteBadge }
    }

    /// Pink heart when I favorited, soft white heart when only the partner did.
    @ViewBuilder
    private var favoriteBadge: some View {
        if !(photo.favorites ?? []).isEmpty {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(photo.isFavorite(of: memberId) ? Theme.pink : Color.white.opacity(0.85))
                .padding(5)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .padding(5)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = api?.mediaURL(photo.thumbUrl ?? photo.url) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder(icon: "photo.badge.exclamationmark")
                default:
                    placeholder(icon: nil)
                }
            }
        } else {
            placeholder(icon: "photo")
        }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.purple.opacity(0.25), Theme.indigo.opacity(0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ProgressView()
                    .tint(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Caption sheet

private struct CaptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let pending: PendingUpload
    let onUpload: (String) -> Void

    @State private var caption = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                VStack(spacing: 18) {
                    Image(uiImage: pending.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                    TextField(L10n.t("memories.gallery.captionPlaceholder"), text: $caption, axis: .vertical)
                        .textFieldStyle(DreamyFieldStyle())
                        .lineLimit(1...3)
                    Button(L10n.t("memories.gallery.upload")) {
                        Haptics.shared.tap()
                        dismiss()
                        onUpload(caption)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }
                .padding(16)
            }
            .navigationTitle(L10n.t("memories.gallery.captionTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(Theme.pink)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Fullscreen pager

private struct PhotoPagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @Binding var photos: [Photo]
    let startId: String
    let favoritesOnly: Bool

    @State private var currentId = ""
    /// Last known position of `currentId` within the visible slice — used to
    /// clamp to a neighbor when the current photo drops out of the slice.
    @State private var lastVisibleIndex = 0
    @State private var confirmDelete = false
    @State private var busy = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            pager
            overlayControls
        }
        .onAppear {
            currentId = startId
            lastVisibleIndex = visiblePhotos.firstIndex { $0.id == startId } ?? 0
        }
        .onChange(of: currentId) { _, newId in
            if let idx = visiblePhotos.firstIndex(where: { $0.id == newId }) {
                lastVisibleIndex = idx
            }
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
    }

    /// The slice the pager pages over — mirrors the grid filter. Derived from
    /// the master array so mutations (favorites, deletes) flow straight back.
    private var visiblePhotos: [Photo] {
        favoritesOnly ? photos.filter { !($0.favorites ?? []).isEmpty } : photos
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
        .tabViewStyle(.page(indexDisplayMode: visiblePhotos.count > 1 ? .automatic : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
    }

    private func pageContent(_ photo: Photo) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let url = appState.api?.mediaURL(photo.url) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textTertiary)
                    default:
                        ProgressView()
                            .tint(.white)
                    }
                }
            }
            Spacer(minLength: 0)
            captionBar(photo)
        }
    }

    private func captionBar(_ photo: Photo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            EmojiAvatarView(emoji: uploader(of: photo)?.avatar,
                            colorHex: uploader(of: photo)?.color,
                            size: 40)
            VStack(alignment: .leading, spacing: 2) {
                if let caption = photo.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(3)
                }
                Text(uploadInfo(photo))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .glassCard(padding: 12)
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    private var overlayControls: some View {
        VStack {
            HStack(spacing: 14) {
                circleButton(icon: "xmark") { dismiss() }
                Spacer()
                if busy {
                    ProgressView()
                        .tint(.white)
                        .padding(10)
                } else {
                    favoriteButton
                    circleButton(icon: "square.and.arrow.down") { saveCurrent() }
                    if currentPhoto?.uploaderId == appState.memberId {
                        circleButton(icon: "trash") { confirmDelete = true }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    private var currentIsFavorite: Bool {
        currentPhoto?.isFavorite(of: appState.memberId) ?? false
    }

    private var favoriteButton: some View {
        circleButton(icon: currentIsFavorite ? "heart.fill" : "heart",
                     tint: currentIsFavorite ? Theme.pink : .white) {
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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.14)))
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
        guard let photo = currentPhoto, let url = appState.api?.mediaURL(photo.url) else { return }
        busy = true
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    throw URLError(.cannotDecodeContentData)
                }
                ImageSaver.save(image) { ok in
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
private final class ImageSaver: NSObject {
    private static var active: [ImageSaver] = []
    private var completion: ((Bool) -> Void)?

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let saver = ImageSaver()
        saver.completion = completion
        active.append(saver)
        UIImageWriteToSavedPhotosAlbum(image, saver,
                                       #selector(ImageSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
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
