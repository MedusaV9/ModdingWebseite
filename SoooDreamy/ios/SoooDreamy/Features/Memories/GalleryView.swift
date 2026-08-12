import SwiftUI
import Combine
import PhotosUI
import UIKit

/// Grid filter: everything, favorites, or one named album (dynamic —
/// album chips are derived from the photos themselves).
private enum GalleryFilter: Hashable {
    case all, favorites
    case album(String)

    var title: String {
        switch self {
        case .all: return L10n.t("memories.gallery.filterAll")
        case .favorites: return L10n.t("memories.gallery.filterFavorites")
        case .album(let name): return "📁 " + name
        }
    }

    func matches(_ photo: Photo) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return !(photo.favorites ?? []).isEmpty
        case .album(let name): return photo.album == name
        }
    }
}

/// Shared photo gallery: grid, PhotosPicker upload with caption + album,
/// album filter chips, fullscreen pager.
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
    @State private var albumPromptPhoto: Photo?
    @State private var newAlbumName = ""
    /// Album currently being renamed (drives the rename prompt).
    @State private var renameAlbumTarget: String?
    @State private var renameAlbumName = ""
    /// Multi-select mode: pick several photos, then move/favorite them at once.
    @State private var selecting = false
    @State private var selectedIds = Set<String>()
    /// "New album…" prompt for the multi-select move menu.
    @State private var bulkNewAlbumPrompt = false
    /// Grid density (2 = big tiles, 3 = classic) — survives app restarts.
    @AppStorage("sooodreamy.gallery.columns") private var storedColumnCount = 3

    private var columnCount: Int {
        storedColumnCount == 2 ? 2 : 3
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount)
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            if selecting {
                selectionBar
            } else {
                floatingAddButton
            }
            if let started = celebrationDate {
                FloatingHeartsView(emojis: ["📸", "💜", "✨", "💖"], count: 14, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("memories.gallery.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !photos.isEmpty {
                    selectToggle
                }
            }
            ToolbarItem(placement: .primaryAction) {
                densityToggle
            }
        }
        .task { await loadPhotos() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await preparePhoto(item) }
        }
        .sheet(item: $pendingUpload) { pending in
            CaptionSheet(pending: pending, albumSuggestions: albums) { caption, album in
                upload(pending, caption: caption, album: album)
            }
        }
        .fullScreenCover(item: $pagerTarget) { photo in
            PhotoPagerView(photos: $photos, startId: photo.id, filter: filter)
        }
        .alert(L10n.t("memories.gallery.newAlbumTitle"),
               isPresented: Binding(get: { albumPromptPhoto != nil },
                                    set: { if !$0 { albumPromptPhoto = nil } }),
               presenting: albumPromptPhoto) { photo in
            TextField(L10n.t("memories.gallery.albumName"), text: $newAlbumName)
            Button(L10n.t("common.save")) { move(photo, toAlbum: newAlbumName) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("memories.gallery.renameAlbumTitle"),
               isPresented: Binding(get: { renameAlbumTarget != nil },
                                    set: { if !$0 { renameAlbumTarget = nil } }),
               presenting: renameAlbumTarget) { name in
            TextField(L10n.t("memories.gallery.albumName"), text: $renameAlbumName)
            Button(L10n.t("common.save")) { renameAlbum(name, to: renameAlbumName) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("memories.gallery.newAlbumTitle"), isPresented: $bulkNewAlbumPrompt) {
            TextField(L10n.t("memories.gallery.albumName"), text: $newAlbumName)
            Button(L10n.t("common.save")) { moveSelected(toAlbum: newAlbumName) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .onChange(of: photos) { _, _ in
            // The chip for an album disappears with its last photo — fall back.
            if case .album(let name) = filter, !albums.contains(name) {
                filter = .all
            }
            // Photos deleted elsewhere (partner, other device) leave the selection.
            selectedIds.formIntersection(photos.map(\.id))
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
        photos.filter { filter.matches($0) }
    }

    /// Distinct album names across all photos, alphabetical.
    private var albums: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for photo in photos {
            guard let album = photo.album, !album.isEmpty, seen.insert(album).inserted else { continue }
            names.append(album)
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var allFilters: [GalleryFilter] {
        [.all, .favorites] + albums.map { GalleryFilter.album($0) }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allFilters, id: \.self) { candidate in
                    filterChip(candidate)
                }
            }
            .padding(.horizontal, LayoutMetrics.s(12))
        }
        .padding(.top, LayoutMetrics.s(10))
    }

    private func filterChip(_ candidate: GalleryFilter) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) { filter = candidate }
        } label: {
            Text(chipTitle(candidate))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(filter == candidate ? .white : Theme.textSecondary)
                .lineLimit(1)
                .padding(.vertical, 7)
                .padding(.horizontal, LayoutMetrics.s(14))
                .background(
                    Capsule().fill(filter == candidate ? Theme.pink.opacity(0.55) : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if case .album(let name) = candidate {
                Button {
                    renameAlbumName = name
                    renameAlbumTarget = name
                } label: {
                    Label(L10n.t("memories.gallery.renameAlbum"), systemImage: "pencil")
                }
            }
        }
    }

    /// Album chips carry their photo count, e.g. "📁 Urlaub (12)".
    private func chipTitle(_ candidate: GalleryFilter) -> String {
        guard case .album = candidate else { return candidate.title }
        let count = photos.filter { candidate.matches($0) }.count
        return "\(candidate.title) (\(count))"
    }

    /// Enters/leaves multi-select mode (leaving always clears the selection).
    private var selectToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) {
                selecting.toggle()
                if !selecting { selectedIds.removeAll() }
            }
        } label: {
            if selecting {
                Text(L10n.t("common.done"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.pink)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.pink)
            }
        }
        .accessibilityLabel(L10n.t("memories.gallery.select"))
    }

    /// 2 ↔ 3 columns — the icon previews the layout a tap switches TO.
    private var densityToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.35)) {
                storedColumnCount = columnCount == 3 ? 2 : 3
            }
        } label: {
            Image(systemName: columnCount == 3 ? "square.grid.2x2" : "square.grid.3x3")
                .foregroundStyle(Theme.pink)
        }
        .accessibilityLabel(L10n.t("memories.gallery.density"))
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(displayedPhotos) { photo in
                    Button {
                        Haptics.shared.tap()
                        if selecting {
                            toggleSelection(photo)
                        } else {
                            pagerTarget = photo
                        }
                    } label: {
                        GalleryCell(photo: photo, api: appState.api, memberId: appState.memberId,
                                    selected: selecting ? selectedIds.contains(photo.id) : nil)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !selecting {
                            sendToChatButton(photo)
                            albumMenu(photo)
                        }
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.top, LayoutMetrics.s(10))
            .padding(.bottom, LayoutMetrics.s(96))
        }
        .refreshable { await loadPhotos() }
    }

    /// "Send to chat" context-menu row: posts a v1.7 photo message that
    /// references this gallery photo (the photo itself is not re-uploaded).
    private func sendToChatButton(_ photo: Photo) -> some View {
        Button {
            sendToChat(photo)
        } label: {
            Label(L10n.t("gallery.sendToChat"), systemImage: "paperplane")
        }
    }

    private func sendToChat(_ photo: Photo) {
        guard let api = appState.api else { return }
        Task {
            do {
                _ = try await api.sendPhotoMessage(photoId: photo.id)
                Haptics.shared.success()
                SoundEngine.shared.play(.pop)
                appState.showToast(L10n.t("gallery.sentToChat"), style: .love)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// "Move to album…" context menu: pick an existing album, create a new
    /// one, or take the photo out of its album.
    @ViewBuilder
    private func albumMenu(_ photo: Photo) -> some View {
        Menu {
            ForEach(albums, id: \.self) { name in
                Button {
                    move(photo, toAlbum: name)
                } label: {
                    if photo.album == name {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
            if !albums.isEmpty { Divider() }
            Button {
                newAlbumName = ""
                albumPromptPhoto = photo
            } label: {
                Label(L10n.t("memories.gallery.newAlbum"), systemImage: "plus")
            }
        } label: {
            Label(L10n.t("memories.gallery.moveToAlbum"), systemImage: "folder")
        }
        if photo.album != nil {
            Button(role: .destructive) {
                move(photo, toAlbum: nil)
            } label: {
                Label(L10n.t("memories.gallery.removeFromAlbum"), systemImage: "folder.badge.minus")
            }
        }
    }

    // MARK: Multi-select

    private func toggleSelection(_ photo: Photo) {
        if selectedIds.remove(photo.id) == nil {
            selectedIds.insert(photo.id)
        }
    }

    private func finishSelection() {
        withAnimation(.spring(response: 0.3)) {
            selecting = false
            selectedIds.removeAll()
        }
    }

    /// Bottom bar in multi-select mode: selection count + bulk actions.
    private var selectionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: LayoutMetrics.s(14)) {
                Text(selectedIds.isEmpty
                     ? L10n.t("memories.gallery.selectHint")
                     : L10n.t("memories.gallery.selectedCount", ["n": String(selectedIds.count)]))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                bulkAlbumMenu
                bulkFavoriteButton
            }
            .padding(.vertical, LayoutMetrics.s(4))
            .padding(.horizontal, LayoutMetrics.s(6))
            .glassCard(padding: 10)
            .padding(.horizontal, LayoutMetrics.s(16))
            .padding(.bottom, LayoutMetrics.s(16))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Bulk "Move to album…" menu: existing albums, a new one, or none.
    private var bulkAlbumMenu: some View {
        Menu {
            ForEach(albums, id: \.self) { name in
                Button {
                    moveSelected(toAlbum: name)
                } label: {
                    Text(name)
                }
            }
            if !albums.isEmpty { Divider() }
            Button {
                newAlbumName = ""
                bulkNewAlbumPrompt = true
            } label: {
                Label(L10n.t("memories.gallery.newAlbum"), systemImage: "plus")
            }
            Button(role: .destructive) {
                moveSelected(toAlbum: nil)
            } label: {
                Label(L10n.t("memories.gallery.removeFromAlbum"), systemImage: "folder.badge.minus")
            }
        } label: {
            Image(systemName: "folder")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(selectedIds.isEmpty ? Theme.textTertiary : Theme.pink)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .disabled(selectedIds.isEmpty)
        .accessibilityLabel(L10n.t("memories.gallery.moveToAlbum"))
    }

    private var bulkFavoriteButton: some View {
        Button {
            Haptics.shared.tap()
            favoriteSelected()
        } label: {
            Image(systemName: "heart")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(selectedIds.isEmpty ? Theme.textTertiary : Theme.pink)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Color.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .disabled(selectedIds.isEmpty)
        .accessibilityLabel(L10n.t("memories.gallery.favoriteSelected"))
    }

    /// Move every selected photo into `album` (nil / empty = out of its album),
    /// one PATCH per photo. Photos already there are skipped.
    private func moveSelected(toAlbum album: String?) {
        guard let api = appState.api, !selectedIds.isEmpty else { return }
        let trimmed = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let targets = photos.filter { selectedIds.contains($0.id) && $0.album != target }
        let count = selectedIds.count
        finishSelection()
        Task {
            do {
                for photo in targets {
                    let updated = try await api.patchPhoto(id: photo.id, album: .some(target))
                    apply(updated)
                }
                Haptics.shared.success()
                if let name = target {
                    appState.showToast(count == 1
                                       ? L10n.t("memories.gallery.moved", ["name": name])
                                       : L10n.t("memories.gallery.movedCount",
                                                ["n": String(count), "name": name]),
                                       style: .success)
                } else {
                    appState.showToast(L10n.t("memories.gallery.removedFromAlbum"), style: .info)
                }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// Mark every selected photo as one of MY favorites. The server endpoint
    /// is a toggle, so photos I already favorited are skipped (never unhearted).
    private func favoriteSelected() {
        guard let api = appState.api, let myId = appState.memberId,
              !selectedIds.isEmpty else { return }
        let targets = photos.filter { selectedIds.contains($0.id) && !$0.isFavorite(of: myId) }
        let count = selectedIds.count
        finishSelection()
        Task {
            do {
                for photo in targets {
                    let updated = try await api.togglePhotoFavorite(id: photo.id)
                    apply(updated)
                }
                Haptics.shared.success()
                appState.showToast(count == 1
                                   ? L10n.t("memories.gallery.favoritedOne")
                                   : L10n.t("memories.gallery.favoritedCount", ["n": String(count)]),
                                   style: .love)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// Rename a whole album: PATCH every photo filed in it to the new name
    /// (renaming onto an existing album merges the two). The active filter
    /// follows the rename so the grid keeps showing the same photos.
    private func renameAlbum(_ oldName: String, to rawNewName: String) {
        guard let api = appState.api else { return }
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != oldName else { return }
        let targets = photos.filter { $0.album == oldName }
        guard !targets.isEmpty else { return }
        if filter == .album(oldName) {
            filter = .album(newName)
        }
        Task {
            do {
                for photo in targets {
                    let updated = try await api.patchPhoto(id: photo.id, album: .some(newName))
                    apply(updated)
                }
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.renamed", ["name": newName]),
                                   style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
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
                            .frame(width: LayoutMetrics.s(60), height: LayoutMetrics.s(60))
                            .shadow(color: Theme.pink.opacity(0.5), radius: 14, y: 6)
                        if uploading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus")
                                .font(.scaled(24, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(uploading)
                .accessibilityLabel(L10n.t("memories.gallery.add"))
                .padding(.trailing, LayoutMetrics.s(20))
                .padding(.bottom, LayoutMetrics.s(24))
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

    private func upload(_ pending: PendingUpload, caption: String, album: String) {
        guard let api = appState.api else { return }
        uploading = true
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
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
                // Album is a follow-up PATCH (upload itself is a raw JPEG POST).
                // Best effort — the photo is already safely uploaded.
                if !trimmedAlbum.isEmpty,
                   let filed = try? await api.patchPhoto(id: photo.id, album: .some(trimmedAlbum)) {
                    apply(filed)
                }
                await uploadThumbnail(for: photo, from: pending.image, api: api)
            } catch {
                appState.handleAPIError(error)
            }
            uploading = false
        }
    }

    /// PATCH the album (nil / empty = remove from its album, via explicit null).
    private func move(_ photo: Photo, toAlbum album: String?) {
        guard let api = appState.api else { return }
        let trimmed = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard photo.album != target else { return }
        Task {
            do {
                let updated = try await api.patchPhoto(id: photo.id, album: .some(target))
                apply(updated)
                Haptics.shared.success()
                if let name = updated.album, !name.isEmpty {
                    appState.showToast(L10n.t("memories.gallery.moved", ["name": name]), style: .success)
                } else {
                    appState.showToast(L10n.t("memories.gallery.removedFromAlbum"), style: .info)
                }
            } catch {
                appState.handleAPIError(error)
            }
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
    /// nil = multi-select off; true/false = this cell's selection state.
    var selected: Bool? = nil

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(thumbnail)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected == true ? Theme.pink : Color.white.opacity(0.10),
                                  lineWidth: selected == true ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) { favoriteBadge }
            .overlay(alignment: .bottomLeading) { selectionBadge }
    }

    /// Selection circle in multi-select mode (filled pink when selected).
    @ViewBuilder
    private var selectionBadge: some View {
        if let selected {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(selected ? Theme.pink : Color.white.opacity(0.85))
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .padding(5)
        }
    }

    /// Pink heart when I favorited, soft white heart when only the partner did.
    @ViewBuilder
    private var favoriteBadge: some View {
        if !(photo.favorites ?? []).isEmpty {
            Image(systemName: "heart.fill")
                .font(.scaled(11, weight: .bold))
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
                    .font(.scaled(20))
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
    let albumSuggestions: [String]
    let onUpload: (String, String) -> Void

    @State private var caption = ""
    @State private var album = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(18)) {
                        Image(uiImage: pending.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
                        TextField(L10n.t("memories.gallery.captionPlaceholder"), text: $caption, axis: .vertical)
                            .textFieldStyle(DreamyFieldStyle())
                            .lineLimit(1...3)
                        albumField
                        Button(L10n.t("memories.gallery.upload")) {
                            Haptics.shared.tap()
                            dismiss()
                            onUpload(caption, album)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Spacer()
                    }
                    .padding(LayoutMetrics.s(16))
                }
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

    private var albumField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.t("memories.gallery.albumField"), text: $album)
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.done)
            if !albumSuggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(albumSuggestions, id: \.self) { name in
                            Button {
                                Haptics.shared.tap()
                                album = name
                            } label: {
                                Text("📁 " + name)
                                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                                    .foregroundStyle(album == name ? .white : Theme.textSecondary)
                                    .padding(.vertical, 7)
                                    .padding(.horizontal, LayoutMetrics.s(12))
                                    .background(
                                        Capsule().fill(album == name
                                                       ? Theme.pink.opacity(0.55)
                                                       : Color.white.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fullscreen pager

private struct PhotoPagerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @Binding var photos: [Photo]
    let startId: String
    let filter: GalleryFilter

    @State private var currentId = ""
    /// Last known position of `currentId` within the visible slice — used to
    /// clamp to a neighbor when the current photo drops out of the slice.
    @State private var lastVisibleIndex = 0
    @State private var confirmDelete = false
    @State private var editingCaption = false
    @State private var captionDraft = ""
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
                            .font(.scaled(40))
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
        HStack(alignment: .center, spacing: LayoutMetrics.s(12)) {
            EmojiAvatarView(emoji: uploader(of: photo)?.avatar,
                            colorHex: uploader(of: photo)?.color,
                            size: LayoutMetrics.s(40))
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
                if let album = photo.album, !album.isEmpty {
                    Text("📁 " + album)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(LayoutMetrics.s(14))
        .glassCard(padding: 12)
        .padding(.horizontal, LayoutMetrics.s(16))
        .padding(.bottom, LayoutMetrics.s(24))
    }

    private var overlayControls: some View {
        VStack {
            HStack(spacing: LayoutMetrics.s(14)) {
                circleButton(icon: "xmark") { dismiss() }
                Spacer()
                if busy {
                    ProgressView()
                        .tint(.white)
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
            .padding(.horizontal, LayoutMetrics.s(16))
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
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
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
