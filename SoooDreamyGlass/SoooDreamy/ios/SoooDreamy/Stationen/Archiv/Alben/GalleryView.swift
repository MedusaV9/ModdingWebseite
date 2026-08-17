import SwiftUI
import Combine
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Shared photo gallery: grid, PhotosPicker upload with caption + album,
/// album filter chips, fullscreen pager.
struct GalleryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    /// Reduce Motion: the polaroids lie straight — the seeded tilt is
    /// ornament, not information.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var photos: [Photo] = []
    @State private var loading = true
    /// Multi-select picker (K-21): one photo keeps the caption-sheet ritual,
    /// several go straight into the stash-first batch pipeline.
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pendingUpload: GalleryPendingUpload?
    @State private var uploading = false
    /// Live batch state (nil = no batch running) — drives the progress bar.
    @State private var batch: BatchProgress?
    /// Prepared uploads the server hasn't accepted yet (failed attempts and
    /// stashed caption-sheet drafts) — rendered as retry cards, never lost.
    @State private var pendingRetries: [PendingMediaEntry] = []
    /// Retry card the user asked to discard (drives the confirmation dialog —
    /// discarding is the one action here that really loses the photo).
    @State private var discardTarget: PendingMediaEntry?
    @State private var pagerTarget: Photo?
    @State private var celebrationDate: Date?
    @State private var celebrationTask: Task<Void, Never>?
    @State private var filter: GalleryFilter = .all
    /// The empty state's own way into the photo picker — the invitation lives
    /// where the eye already is, not in the far corner.
    @State private var emptyStatePicker = false
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
    /// Zoom transition source: the tapped grid cell blossoms into the viewer.
    @Namespace private var lightboxNamespace
    /// The photo the pager last showed — closing the viewer scrolls the grid
    /// there, so twenty swipes in the pager never strand the grid position.
    @State private var lastViewedId: String?
    /// Timestamp of the previous gallery visit — partner photos newer than
    /// this glow with a "Neu" badge until they are opened.
    @AppStorage("sooodreamy.gallery.lastSeenAt") private var lastSeenAt = 0.0
    @State private var newFromPartnerIds = Set<String>()
    /// An image drag hovers over the gallery (iPad drag & drop).
    @State private var dropTargeted = false

    /// Density flag behind the stored preference: "big" keeps 2 columns on
    /// phones, "classic" keeps 3.
    private var bigTiles: Bool {
        storedColumnCount == 2
    }

    /// Adaptive photo grid: the density picks the tile minimum, the
    /// container picks the column count — phones keep their 2/3 columns,
    /// iPad windows simply fit more of the same tiles.
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: bigTiles
                            ? LayoutMetrics.photoTileBigMin
                            : LayoutMetrics.photoTileClassicMin),
                  spacing: 6)]
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
            if let batch {
                batchBar(batch)
            }
            if let started = celebrationDate {
                FloatingHeartsView(count: 14, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            dropHint
        }
        // Roadmap 19: images dropped from Photos/Files/Split-View neighbors
        // run the same stash-first batch pipeline as the PhotosPicker.
        .dropDestination(for: Data.self) { payloads, _ in
            guard appState.api != nil, !payloads.isEmpty else { return false }
            Haptics.shared.tap()
            Task { await runDroppedUpload(payloads) }
            return true
        } isTargeted: { over in
            withAnimation(Theme.Motion.settle) { dropTargeted = over }
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
        .task {
            refreshPendingRetries()
            await loadPhotos()
            consumePendingGalleryTarget()
        }
        .onChange(of: appState.pendingGalleryPhotoId) {
            // Chat's "view in album" while the gallery is already open.
            consumePendingGalleryTarget()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            if items.count == 1, let single = items.first {
                Task { await preparePhoto(single) }
            } else {
                Task { await runBatchUpload(items) }
            }
        }
        .sheet(item: $pendingUpload) { pending in
            GalleryCaptionSheet(pending: pending, albumSuggestions: albums) { caption, album in
                upload(pending, caption: caption, album: album)
            } onDismissWithoutUpload: { caption, album in
                stashDraft(pending, caption: caption, album: album)
            }
        }
        .fullScreenCover(item: $pagerTarget) { photo in
            PhotoPagerView(photos: $photos, startId: photo.id, filter: filter,
                           lastViewedId: $lastViewedId)
                .navigationTransition(.zoom(sourceID: photo.id, in: lightboxNamespace))
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
        .confirmationDialog(L10n.t("memories.gallery.retry.discardConfirm"),
                            isPresented: Binding(get: { discardTarget != nil },
                                                 set: { if !$0 { discardTarget = nil } }),
                            titleVisibility: .visible, presenting: discardTarget) { entry in
            Button(L10n.t("memories.gallery.retry.discard"), role: .destructive) {
                PendingMediaStore.shared.remove(id: entry.id)
                refreshPendingRetries()
            }
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

    /// Chrome hint while an image drag hovers over the grid.
    @ViewBuilder private var dropHint: some View {
        if dropTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.pane, style: .continuous)
                    .strokeBorder(coupleTint.blend.opacity(0.7), lineWidth: 2)
                    .padding(Space.m)
                Label(L10n.t("memories.gallery.drop.hint"),
                      systemImage: "photo.badge.arrow.down")
                    .font(Typo.label)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, Space.s)
                    .padding(.horizontal, Space.l)
                    .glass(.chrome, in: Capsule())
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            loadingSkeleton
        } else if photos.isEmpty && pendingRetries.isEmpty {
            emptyState
        } else if photos.isEmpty {
            VStack(spacing: 0) {
                retryStrip
                emptyState
            }
        } else {
            gridArea
        }
    }

    /// Waiting in the rhythm of the coming grid (commandment 7): a filter
    /// line and photo tiles, not an anonymous spinner.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            PaperSkeleton(kind: .line(width: LayoutMetrics.s(160)), onNacht: true)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<9, id: \.self) { _ in
                    PaperSkeleton(kind: .tile(height: 110), onNacht: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("common.loading"))
    }

    /// The bounded Archivblatt (iPad-Eval S1): a letter-paper sheet at
    /// the top of the reading column instead of a stock empty state
    /// centered over the whole detail pane.
    private var emptyState: some View {
        VStack {
            ArchivBlattEmptyState(systemImage: "camera",
                                  title: L10n.t("memories.gallery.empty.title"),
                                  subtitle: L10n.t("memories.gallery.empty.subtitle"),
                                  actionTitle: L10n.t("memories.gallery.empty.action"),
                                  action: {
                                      Haptics.shared.tap()
                                      emptyStatePicker = true
                                  })
            Spacer(minLength: 0)
        }
        .photosPicker(isPresented: $emptyStatePicker, selection: $pickerItems,
                      maxSelectionCount: 20, matching: .images, photoLibrary: .shared())
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
            if !pendingRetries.isEmpty {
                retryStrip
            }
            filterChips
            if filter == .favorites && displayedPhotos.isEmpty {
                ArchivBlattEmptyState(systemImage: "heart",
                                      title: L10n.t("memories.gallery.favEmpty.title"),
                                      subtitle: L10n.t("memories.gallery.favEmpty.subtitle"),
                                      actionTitle: L10n.t("memories.gallery.favEmpty.action"),
                                      action: {
                                          Haptics.shared.tap()
                                          withAnimation(Theme.Motion.settle) { filter = .all }
                                      })
                Spacer(minLength: 0)
            } else {
                grid
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(allFilters, id: \.self) { candidate in
                    filterChip(candidate)
                }
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.top, Space.m)
    }

    private func filterChip(_ candidate: GalleryFilter) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) { filter = candidate }
        } label: {
            // Albums are register tabs sticking out of the album — at
            // night the selected tab is the lamplit night card, the rest
            // a quiet aufNacht wash (pinned aufNacht/Nacht.* contrast).
            PapierRegisterTab(title: chipTitle(candidate),
                              systemImage: candidate.isAlbum ? "folder" : nil,
                              selected: filter == candidate)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == candidate ? [.isSelected] : [])
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

    /// Album chips carry their photo count, e.g. "Urlaub (12)".
    private func chipTitle(_ candidate: GalleryFilter) -> String {
        guard case .album = candidate else { return candidate.title }
        let count = photos.filter { candidate.matches($0) }.count
        return "\(candidate.title) (\(count))"
    }

    // MARK: Retry cards (Linse 41/45)

    /// Horizontal shelf of prepared uploads the server hasn't accepted yet.
    /// Each card can be re-sent or (with confirmation) discarded — a failed
    /// upload or dismissed caption sheet never silently loses the photo.
    private var retryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.m) {
                ForEach(pendingRetries) { entry in
                    retryCard(entry)
                }
            }
            .padding(.horizontal, Space.m)
        }
        .padding(.top, Space.m)
    }

    private func retryCard(_ entry: PendingMediaEntry) -> some View {
        HStack(spacing: Space.m) {
            PendingMediaThumbnail(entryID: entry.id)
                .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                .clipShape(RoundedRectangle(
                    cornerRadius: Radius.concentric(parent: Radius.papier, padding: Space.m),
                    style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.lastErrorCode == nil
                     ? L10n.t("memories.gallery.retry.draft")
                     : L10n.t("memories.gallery.retry.failed"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(entry.lastErrorCode == nil ? Nacht.sekundaer : Theme.energyRed)
                if !entry.caption.isEmpty {
                    Text(entry.caption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .lineLimit(1)
                }
                HStack(spacing: Space.s) {
                    Button {
                        Haptics.shared.tap()
                        retry(entry)
                    } label: {
                        Text(L10n.t("memories.gallery.retry.send"))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            // Computed ink on the SOLID blend fill
                            // (Kontrast II — onBlend's contract).
                            .foregroundStyle(coupleTint.onBlend)
                            .padding(.vertical, 4)
                            .padding(.horizontal, Space.m)
                            .background(Capsule().fill(coupleTint.blend))
                    }
                    .buttonStyle(.plain)
                    .disabled(uploading)
                    Button {
                        Haptics.shared.tap()
                        discardTarget = entry
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Nacht.tertiaer)
                            .padding(5)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("memories.gallery.retry.discard"))
                }
            }
        }
        // A not-yet-sent photo waits as a night card on the desk —
        // grainless: the card is dominated by sub-subheadline copy.
        .nightCard(padding: .compact, grain: false)
        .frame(maxWidth: LayoutMetrics.s(260))
    }

    /// Enters/leaves multi-select mode (leaving always clears the selection).
    private var selectToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) {
                selecting.toggle()
                if !selecting { selectedIds.removeAll() }
            }
        } label: {
            if selecting {
                Text(L10n.t("common.done"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.blend)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(coupleTint.blend)
            }
        }
        .accessibilityLabel(L10n.t("memories.gallery.select"))
    }

    /// Big ↔ classic tiles — the icon previews the layout a tap switches TO.
    private var densityToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) {
                storedColumnCount = bigTiles ? 3 : 2
            }
        } label: {
            Image(systemName: bigTiles ? "square.grid.3x3" : "square.grid.2x2")
                .foregroundStyle(coupleTint.blend)
        }
        .accessibilityLabel(L10n.t("memories.gallery.density"))
    }

    /// Month sections over the filtered photos (newest month first) — the
    /// grouping itself is pure, Linux-tested logic.
    private var monthGroups: [(monthKey: String, photos: [Photo])] {
        let visible = displayedPhotos
        let byId = Dictionary(visible.map { ($0.id, $0) }) { first, _ in first }
        return MemoriesLogic.galleryMonthGroups(
            photos: visible.map { ($0.id, $0.sortDate) },
            timeZone: .current
        ).map { ($0.monthKey, $0.photoIds.compactMap { byId[$0] }) }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s) {
                    ForEach(monthGroups, id: \.monthKey) { group in
                        let tilted = tiltedIds(in: group.photos)
                        monthHeader(group.monthKey)
                        LazyVGrid(columns: columns, spacing: Space.s) {
                            ForEach(group.photos) { photo in
                                gridCell(photo, tilted: tilted.contains(photo.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.m)
                .padding(.bottom, LayoutMetrics.s(96))
            }
            .refreshable { await loadPhotos() }
            .onChange(of: pagerTarget == nil) { _, closed in
                // Scroll restore: land on the photo the pager last showed —
                // without animation, so the grid is simply "already there".
                guard closed, let anchor = lastViewedId else { return }
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }

    /// Seeded tilt budget of the album: at most THREE slightly crooked
    /// polaroids per month section, chosen by the same stable per-photo
    /// roll on every device — nothing flickers between renders, and most
    /// prints lie straight (kitsch guardrail). Reduce Motion: none tilt.
    private func tiltedIds(in group: [Photo]) -> Set<String> {
        guard !reduceMotion else { return [] }
        let rolls = group.map { photo in
            (photo.id, PaperRules.unitRandom(seed: memoriesPaperSeed(photo.id), index: 7))
        }
        return Set(rolls.filter { $0.1 > 0.7 }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map(\.0))
    }

    /// "August 2026" — a calm month divider like Apple Photos.
    private func monthHeader(_ monthKey: String) -> some View {
        Text(monthLabel(monthKey))
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, Space.s)
            .padding(.leading, Space.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func monthLabel(_ monthKey: String) -> String {
        var comps = DateComponents()
        comps.year = Int(monthKey.prefix(4))
        comps.month = Int(monthKey.suffix(2))
        comps.day = 1
        guard let date = Calendar.current.date(from: comps) else { return monthKey }
        return AppFormatters.monthYear(date, language: L10n.lang)
    }

    @ViewBuilder
    private func gridCell(_ photo: Photo, tilted: Bool = false) -> some View {
        let label = GalleryCell(photo: photo, api: appState.api, memberId: appState.memberId,
                                selected: selecting ? selectedIds.contains(photo.id) : nil,
                                isNew: newFromPartnerIds.contains(photo.id),
                                showsCaption: bigTiles,
                                authorColorHex: uploaderColorHex(of: photo))
        let cell = Button {
            Haptics.shared.tap()
            if selecting {
                toggleSelection(photo)
            } else {
                newFromPartnerIds.remove(photo.id)
                lastViewedId = photo.id
                pagerTarget = photo
            }
        } label: {
            if tilted {
                // Seeded, stable per photo id — the one sanctioned
                // rotation source (max 3 per month section, see above).
                label.paperTilt(seed: memoriesPaperSeed(photo.id))
            } else {
                label
            }
        }
        .buttonStyle(.plain)
        .id(photo.id)
        .matchedTransitionSource(id: photo.id, in: lightboxNamespace)
        .contextMenu {
            if !selecting {
                sendToChatButton(photo)
                albumMenu(photo)
            }
        }
        if selecting {
            // Multi-select taps stay taps — no drag session stealing them.
            cell
        } else {
            // Roadmap 19, drag-OUT: a tile can leave the app as a JPEG.
            cell.draggable(PhotoDragPayload(api: appState.api, path: photo.url))
        }
    }

    /// The uploader's member color — the cell turns it into the author's
    /// ink dot on the polaroid strip via the `inkOnPaper` ladder.
    private func uploaderColorHex(of photo: Photo) -> String? {
        appState.couple?.members.first { $0.id == photo.uploaderId }?.color
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
        withAnimation(Theme.Motion.settle) {
            selecting = false
            selectedIds.removeAll()
        }
    }

    /// Bottom bar in multi-select mode: selection count + bulk actions.
    private var selectionBar: some View {
        VStack {
            Spacer()
            HStack(spacing: Space.l) {
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
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            // The selection bar FLOATS above the album — floating tools
            // are chrome glass, never paper (Zwei-Materialien-Gesetz).
            .glass(.chrome, in: Capsule())
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.l)
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
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(selectedIds.isEmpty ? Theme.textTertiary : coupleTint.blend)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Theme.innerFill))
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
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(selectedIds.isEmpty ? Theme.textTertiary : coupleTint.blend)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Theme.innerFill))
        }
        .buttonStyle(.plain)
        .disabled(selectedIds.isEmpty)
        .accessibilityLabel(L10n.t("memories.gallery.favoriteSelected"))
    }

    /// Move every selected photo into `album` (nil / empty = out of its album),
    /// one PATCH per photo. Photos already there are skipped. A failure never
    /// aborts the run (B-10): the rest keeps moving, the result is balanced
    /// honestly and failed photos stay selected for a one-tap retry.
    private func moveSelected(toAlbum album: String?) {
        guard let api = appState.api, !selectedIds.isEmpty else { return }
        let trimmed = album?.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let targets = photos.filter { selectedIds.contains($0.id) && $0.album != target }
        let count = selectedIds.count
        finishSelection()
        Task {
            var failedIds: [String] = []
            for photo in targets {
                do {
                    let updated = try await api.patchPhoto(id: photo.id, album: .some(target))
                    apply(updated)
                } catch {
                    failedIds.append(photo.id)
                }
            }
            if failedIds.isEmpty {
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
            } else {
                restoreSelection(failedIds, done: count - failedIds.count, total: count)
            }
        }
    }

    /// B-10 aftermath: the photos an operation could not reach come back as
    /// the active selection, with an honest balance toast.
    private func restoreSelection(_ failedIds: [String], done: Int, total: Int) {
        withAnimation(Theme.Motion.settle) {
            selecting = true
            selectedIds = Set(failedIds)
        }
        appState.showToast(L10n.t("memories.gallery.bulk.partial",
                                  ["done": String(done), "total": String(total)]),
                           style: .error)
    }

    /// Mark every selected photo as one of MY favorites. The server endpoint
    /// is a toggle, so photos I already favorited are skipped (never unhearted).
    /// Failures never abort the run (B-10) — see `moveSelected`.
    private func favoriteSelected() {
        guard let api = appState.api, let myId = appState.memberId,
              !selectedIds.isEmpty else { return }
        let targets = photos.filter { selectedIds.contains($0.id) && !$0.isFavorite(of: myId) }
        let count = selectedIds.count
        finishSelection()
        Task {
            var failedIds: [String] = []
            for photo in targets {
                do {
                    let updated = try await api.togglePhotoFavorite(id: photo.id)
                    apply(updated)
                } catch {
                    failedIds.append(photo.id)
                }
            }
            if failedIds.isEmpty {
                Haptics.shared.success()
                appState.showToast(count == 1
                                   ? L10n.t("memories.gallery.favoritedOne")
                                   : L10n.t("memories.gallery.favoritedCount", ["n": String(count)]),
                                   style: .love)
            } else {
                restoreSelection(failedIds, done: count - failedIds.count, total: count)
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
            var failedCount = 0
            for photo in targets {
                do {
                    let updated = try await api.patchPhoto(id: photo.id, album: .some(newName))
                    apply(updated)
                } catch {
                    failedCount += 1
                }
            }
            if failedCount == 0 {
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.renamed", ["name": newName]),
                                   style: .success)
            } else {
                // B-10: the photos still filed under the old name keep their
                // chip — renaming the remainder again finishes the merge.
                appState.showToast(L10n.t("memories.gallery.bulk.partial",
                                          ["done": String(targets.count - failedCount),
                                           "total": String(targets.count)]),
                                   style: .error)
            }
        }
    }

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 20,
                             matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        // The add-FAB wears the couple's own two colors —
                        // the gallery's primary action IS a pair gesture.
                        // gradientTextScrim: the night-ink protection layer
                        // for palettes where no ink alone clears 4.5:1 on
                        // both stops (nil for every member-color pair).
                        Circle()
                            .fill(coupleTint.heroGradient)
                            .overlay(Circle().fill(coupleTint.gradientTextScrim ?? .clear))
                            .frame(width: LayoutMetrics.s(60), height: LayoutMetrics.s(60))
                            .shadow(color: coupleTint.blend.opacity(0.5), radius: 14, y: 6)
                        if uploading {
                            BusySpinner(tint: coupleTint.onGradient)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                // The FAB circle is the couple heroGradient —
                                // computed ink, worst stop wins (Kontrast II).
                                .foregroundStyle(coupleTint.onGradient)
                        }
                    }
                }
                .disabled(uploading)
                .accessibilityLabel(L10n.t("memories.gallery.add"))
                .padding(.trailing, LayoutMetrics.s(20))
                .padding(.bottom, Space.xl)
            }
        }
    }

    // MARK: Data

    private func loadPhotos() async {
        guard let api = appState.api else {
            // No server session (staged CI shots, pre-pairing states): the
            // honest empty state beats a spinner that can never finish.
            loading = false
            return
        }
        do {
            let list = try await api.photos()
            photos = list.sorted { $0.sortDate > $1.sortDate }
            markNewArrivals()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    /// W6-Rest chat→album bridge: when the chat asked for a specific photo,
    /// open the lightbox right on it. Runs only after the photo list is
    /// loaded; a photo deleted in the meantime gets an honest toast instead
    /// of a silently dead landing.
    private func consumePendingGalleryTarget() {
        guard !loading, let id = appState.pendingGalleryPhotoId else { return }
        appState.pendingGalleryPhotoId = nil
        guard let photo = photos.first(where: { $0.id == id }) else {
            appState.showToast(L10n.t("memories.gallery.photoGone"), style: .info)
            return
        }
        // The pager pages through the ACTIVE filter — make sure the target
        // is inside it before opening.
        if !filter.matches(photo) { filter = .all }
        pagerTarget = photo
    }

    /// Partner photos that arrived since the previous visit glow with a
    /// "Neu" badge (until opened). First visit ever stays quiet — badging
    /// the whole library would be noise, not a signal.
    private func markNewArrivals() {
        let previousVisit = lastSeenAt
        lastSeenAt = Date().timeIntervalSince1970
        guard previousVisit > 0 else { return }
        let cutoff = Date(timeIntervalSince1970: previousVisit)
        newFromPartnerIds.formUnion(
            photos.filter { $0.uploaderId != appState.memberId && $0.createdAt > cutoff }
                .map(\.id))
    }

    private func insert(_ photo: Photo) {
        guard !photos.contains(where: { $0.id == photo.id }) else { return }
        photos.append(photo)
        photos.sort { $0.sortDate > $1.sortDate }
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
                  let image = BoundedImageDecoder.image(data: data, maxPixelSize: 2_048) else {
                appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
                return
            }
            guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
                appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
                return
            }
            pendingUpload = GalleryPendingUpload(jpeg: jpeg, image: image,
                                                 takenAt: BoundedImageDecoder.takenAt(data: data))
        } catch {
            appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
        }
    }

    /// Scope for the pending-media stash — same identity boundary as the
    /// chat outbox, so drafts never leak across profiles or couples.
    private var mediaScope: OutboxScope? {
        guard let profile = appState.servers.activeProfile,
              let coupleID = profile.coupleId,
              let memberID = profile.memberId else { return nil }
        return OutboxScope(profileID: profile.id, coupleID: coupleID, memberID: memberID)
    }

    private func refreshPendingRetries() {
        guard let scope = mediaScope else {
            pendingRetries = []
            return
        }
        pendingRetries = PendingMediaStore.shared.entries(for: scope)
    }

    /// Caption sheet was dismissed without uploading: keep JPEG + caption as
    /// a retry card instead of throwing the prepared photo away (Linse 41).
    private func stashDraft(_ pending: GalleryPendingUpload, caption: String, album: String) {
        guard let scope = mediaScope else { return }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PendingMediaStore.shared.add(jpeg: pending.jpeg, caption: trimmed,
                                           album: trimmedAlbum,
                                           width: Int(pending.image.size.width),
                                           height: Int(pending.image.size.height),
                                           takenAt: pending.takenAt,
                                           scope: scope) != nil else { return }
        refreshPendingRetries()
        appState.showToast(L10n.t("memories.gallery.retry.stashed"), style: .info)
    }

    /// Stash-first upload: JPEG + caption are persisted BEFORE the request,
    /// so a crash or failure mid-flight costs a retry tap — never the photo.
    private func upload(_ pending: GalleryPendingUpload, caption: String, album: String) {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = album.trimmingCharacters(in: .whitespacesAndNewlines)
        let width = Int(pending.image.size.width)
        let height = Int(pending.image.size.height)
        if let scope = mediaScope,
           let entry = PendingMediaStore.shared.add(jpeg: pending.jpeg, caption: trimmed,
                                                    album: trimmedAlbum, width: width,
                                                    height: height, takenAt: pending.takenAt,
                                                    scope: scope) {
            refreshPendingRetries()
            retry(entry)
        } else {
            // Disk refused the stash — upload directly rather than blocking.
            performUpload(jpeg: pending.jpeg, caption: trimmed, album: trimmedAlbum,
                          width: width, height: height, takenAt: pending.takenAt,
                          entryID: nil)
        }
    }

    // MARK: Batch upload (K-21)

    /// Stash-first batch: every picked photo is prepared and persisted to the
    /// PendingMediaStore BEFORE any network I/O, then uploaded two at a time.
    /// A crash or failure mid-batch costs retry taps — never a photo.
    private func runBatchUpload(_ items: [PhotosPickerItem]) async {
        uploading = true
        defer { uploading = false }
        withAnimation(Theme.Motion.arrive) {
            batch = BatchProgress(total: items.count, done: 0, failed: 0)
        }

        // Phase 1 — read + decode + stash, sequential on purpose: decoding
        // twenty photos in parallel would spike memory for zero visible win.
        var entries: [PendingMediaEntry] = []
        for item in items {
            var stashed = false
            do {
                if let data = try await item.loadTransferable(type: Data.self),
                   let entry = stashImageData(data) {
                    entries.append(entry)
                    stashed = true
                }
            } catch {}
            if !stashed { batch?.failed += 1 }
        }
        await uploadStashedBatch(entries, total: items.count)
    }

    /// Same stash-first pipeline for images DROPPED onto the gallery
    /// (roadmap 19 — iPad drag & drop): the bytes are already here, so
    /// phase 1 is just decode + stash, then the shared batch upload runs.
    private func runDroppedUpload(_ payloads: [Data]) async {
        uploading = true
        defer { uploading = false }
        withAnimation(Theme.Motion.arrive) {
            batch = BatchProgress(total: payloads.count, done: 0, failed: 0)
        }
        var entries: [PendingMediaEntry] = []
        for data in payloads {
            if let entry = stashImageData(data) {
                entries.append(entry)
            } else {
                batch?.failed += 1
            }
        }
        await uploadStashedBatch(entries, total: payloads.count)
    }

    /// Decode + persist one image payload into the PendingMediaStore.
    private func stashImageData(_ data: Data) -> PendingMediaEntry? {
        guard let image = BoundedImageDecoder.image(data: data, maxPixelSize: 2_048),
              let jpeg = image.jpegData(compressionQuality: 0.85),
              let scope = mediaScope else { return nil }
        return PendingMediaStore.shared.add(
            jpeg: jpeg, caption: "", album: "",
            width: Int(image.size.width), height: Int(image.size.height),
            takenAt: BoundedImageDecoder.takenAt(data: data),
            scope: scope)
    }

    /// Phase 2 — upload with two workers; each finished item advances
    /// the ring and refills the group. Shared by picker batches and drops.
    private func uploadStashedBatch(_ entries: [PendingMediaEntry], total: Int) async {
        refreshPendingRetries()
        await withTaskGroup(of: Bool.self) { group in
            var iterator = entries.makeIterator()
            for _ in 0..<2 {
                if let entry = iterator.next() {
                    group.addTask { await uploadEntryQuietly(entry) }
                }
            }
            while let ok = await group.next() {
                if ok { batch?.done += 1 } else { batch?.failed += 1 }
                if let entry = iterator.next() {
                    group.addTask { await uploadEntryQuietly(entry) }
                }
            }
        }
        refreshPendingRetries()

        let done = batch?.done ?? 0
        let failed = batch?.failed ?? 0
        withAnimation(Theme.Motion.settle) { batch = nil }
        if done > 0 {
            SoundEngine.shared.play(.sparkle)
            Haptics.shared.success()
            celebrate()
        }
        if failed == 0 {
            appState.showToast(L10n.t("memories.gallery.batch.done", ["n": String(done)]),
                               style: .love)
        } else {
            // The unsent ones sit safely in the retry strip — say so.
            appState.showToast(L10n.t("memories.gallery.batch.partial",
                                      ["done": String(done), "total": String(total)]),
                               style: .error)
        }
    }

    /// One stashed entry → server, without the single-upload fanfare.
    /// Success removes the stash entry; failure keeps it as a retry card.
    private func uploadEntryQuietly(_ entry: PendingMediaEntry) async -> Bool {
        guard let api = appState.api,
              let jpeg = PendingMediaStore.shared.jpegData(id: entry.id) else { return false }
        do {
            let photo = try await api.uploadPhoto(jpeg: jpeg,
                                                  caption: entry.caption.isEmpty ? nil : entry.caption,
                                                  width: entry.width, height: entry.height,
                                                  takenAt: entry.takenAt)
            PendingMediaStore.shared.remove(id: entry.id)
            insert(photo)
            if let image = BoundedImageDecoder.image(data: jpeg, maxPixelSize: 2_048) {
                await uploadThumbnail(for: photo, from: image, api: api)
            }
            return true
        } catch {
            PendingMediaStore.shared.setLastError(
                id: entry.id, code: (error as? APIError)?.serverCode ?? "network")
            return false
        }
    }

    /// Floating progress card while a batch runs: a real ring (finished out
    /// of total) plus an honest failure line — never an anonymous spinner.
    private func batchBar(_ progress: BatchProgress) -> some View {
        VStack {
            Spacer()
            HStack(spacing: Space.m) {
                batchRing(progress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("memories.gallery.batch.progress",
                                ["done": String(progress.done),
                                 "total": String(progress.total)]))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if progress.failed > 0 {
                        Text(L10n.t("memories.gallery.batch.failedCount",
                                    ["n": String(progress.failed)]))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.energyRed)
                    }
                }
                Spacer()
            }
            .padding(Space.m)
            // The batch card floats over the album while uploads run —
            // floating chrome, not paper.
            .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.control,
                                                 style: .continuous))
            .padding(.horizontal, Space.l)
            .padding(.bottom, LayoutMetrics.s(96))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private func batchRing(_ progress: BatchProgress) -> some View {
        let fraction = progress.total == 0 ? 0
            : CGFloat(progress.done + progress.failed) / CGFloat(progress.total)
        return ZStack {
            Circle()
                .stroke(Theme.innerFill, lineWidth: 4)
            Circle()
                .trim(from: 0, to: fraction)
                // Shape-level rotation: the ring starts at 12 o'clock —
                // geometry, not paper motion.
                .rotation(.degrees(-90))
                .stroke(coupleTint.blend, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .animation(Theme.Motion.settle, value: fraction)
        }
        .frame(width: LayoutMetrics.s(30), height: LayoutMetrics.s(30))
    }

    /// Re-send one retry card (also the second half of every fresh upload).
    private func retry(_ entry: PendingMediaEntry) {
        guard let jpeg = PendingMediaStore.shared.jpegData(id: entry.id) else {
            // Bytes vanished (user cleared storage) — drop the orphaned card.
            PendingMediaStore.shared.remove(id: entry.id)
            refreshPendingRetries()
            return
        }
        performUpload(jpeg: jpeg, caption: entry.caption, album: entry.album,
                      width: entry.width, height: entry.height, takenAt: entry.takenAt,
                      entryID: entry.id)
    }

    private func performUpload(jpeg: Data, caption: String, album: String,
                               width: Int, height: Int, takenAt: Date?, entryID: String?) {
        guard let api = appState.api else { return }
        uploading = true
        Task {
            do {
                let photo = try await api.uploadPhoto(jpeg: jpeg,
                                                      caption: caption.isEmpty ? nil : caption,
                                                      width: width, height: height,
                                                      takenAt: takenAt)
                if let entryID {
                    PendingMediaStore.shared.remove(id: entryID)
                    refreshPendingRetries()
                }
                insert(photo)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.uploaded"), style: .love)
                celebrate()
                // Album is a follow-up PATCH (upload itself is a raw JPEG POST).
                // Best effort — the photo is already safely uploaded.
                if !album.isEmpty,
                   let filed = try? await api.patchPhoto(id: photo.id, album: .some(album)) {
                    apply(filed)
                }
                if let image = BoundedImageDecoder.image(data: jpeg, maxPixelSize: 2_048) {
                    await uploadThumbnail(for: photo, from: image, api: api)
                }
            } catch {
                if let entryID {
                    PendingMediaStore.shared.setLastError(
                        id: entryID, code: (error as? APIError)?.serverCode ?? "network")
                    refreshPendingRetries()
                }
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
                newFromPartnerIds.insert(photo.id)
                lastSeenAt = Date().timeIntervalSince1970
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

/// Progress of one running batch upload (read failures count as failed too).
private struct BatchProgress: Equatable {
    let total: Int
    var done: Int
    var failed: Int
}

/// Drag-OUT payload for one server photo (roadmap 19 — the other half of the
/// gallery's drop-IN): grid cells, pager pages and chat photo bubbles can be
/// dragged into Files, Notes or a Split-View neighbor as a real JPEG. The
/// bytes travel through the authenticated API and are fetched lazily when the
/// DROP lands — starting a drag never blocks on the network.
struct PhotoDragPayload: Transferable {
    /// Deferred byte source, resolved by the drop target.
    let fetch: @Sendable () async throws -> Data

    /// Payload for the photo at `path` (the app's gallery uploads are always
    /// JPEG, so the raw media bytes ARE the exported representation).
    init(api: API?, path: String) {
        fetch = {
            guard let api else { throw URLError(.userAuthenticationRequired) }
            return try await api.mediaData(path)
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { payload in
            try await payload.fetch()
        }
    }
}
