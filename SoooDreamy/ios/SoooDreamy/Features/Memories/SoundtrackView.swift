import SwiftUI
import Combine

/// "Unser Soundtrack" — the couple's shared song list with hearts,
/// listen links and a random-pick shuffle.
struct SoundtrackView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var editorTarget: EditorTarget?
    @State private var deleteTarget: Song?
    @State private var confirmDelete = false
    @State private var highlightedId: String?
    @State private var highlightTask: Task<Void, Never>?

    private struct EditorTarget: Identifiable {
        let id: String
        let song: Song?
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            floatingAddButton
        }
        .navigationTitle(L10n.t("memories.soundtrack.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSongs() }
        .sheet(item: $editorTarget) { target in
            SongEditorSheet(song: target.song) { saved in
                apply(saved)
            }
        }
        .confirmationDialog(L10n.t("memories.soundtrack.deleteConfirm"),
                            isPresented: $confirmDelete, titleVisibility: .visible,
                            presenting: deleteTarget) { song in
            Button(L10n.t("common.delete"), role: .destructive) { delete(song) }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .onDisappear { highlightTask?.cancel() }
    }

    /// Newest first, independent of insertion order.
    private var sortedSongs: [Song] {
        songs.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LoadingView()
        } else if songs.isEmpty {
            emptyState
        } else {
            songList
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "🎶",
                           title: L10n.t("memories.soundtrack.empty.title"),
                           subtitle: L10n.t("memories.soundtrack.empty.subtitle"))
            Spacer()
        }
    }

    private var songList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(proxy)
                List {
                    ForEach(sortedSongs) { song in
                        row(song)
                            .id(song.id)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    Color.clear
                        .frame(height: 70)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await loadSongs() }
            }
        }
    }

    // MARK: Header

    private var countText: String {
        songs.count == 1
            ? L10n.t("memories.soundtrack.countOne")
            : L10n.t("memories.soundtrack.count", ["n": String(songs.count)])
    }

    private func header(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Text(countText)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            shuffleButton(proxy)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func shuffleButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            shuffle(proxy)
        } label: {
            HStack(spacing: 5) {
                Text("🎲")
                Text(L10n.t("memories.soundtrack.shuffle"))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
            }
            .foregroundStyle(Theme.mint)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(Capsule().fill(Theme.mint.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("memories.soundtrack.shuffle"))
    }

    /// Picks a random song, scrolls to it and pulses its card briefly.
    private func shuffle(_ proxy: ScrollViewProxy) {
        guard let song = sortedSongs.randomElement() else { return }
        Haptics.shared.tap()
        SoundEngine.shared.play(.pop)
        withAnimation(.spring(response: 0.5)) {
            proxy.scrollTo(song.id, anchor: .center)
        }
        withAnimation(.spring(response: 0.35)) {
            highlightedId = song.id
        }
        highlightTask?.cancel()
        highlightTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                highlightedId = nil
            }
        }
    }

    // MARK: Row

    private func isMine(_ song: Song) -> Bool {
        song.addedBy == appState.memberId
    }

    @ViewBuilder
    private func row(_ song: Song) -> some View {
        if isMine(song) {
            songCard(song)
                .contextMenu {
                    Button {
                        editorTarget = EditorTarget(id: song.id, song: song)
                    } label: {
                        Label(L10n.t("common.edit"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteTarget = song
                        confirmDelete = true
                    } label: {
                        Label(L10n.t("common.delete"), systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleteTarget = song
                        confirmDelete = true
                    } label: {
                        Label(L10n.t("common.delete"), systemImage: "trash")
                    }
                }
        } else {
            songCard(song)
        }
    }

    private func songCard(_ song: Song) -> some View {
        let highlighted = highlightedId == song.id
        return HStack(alignment: .top, spacing: 12) {
            noteTile
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if let note = song.note, !note.isEmpty {
                    Text(note)
                        .font(.system(.caption, design: .rounded).italic())
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                addedByLine(song)
                    .padding(.top, 3)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                heartButton(song)
                if let url = listenURL(song.link) {
                    listenButton(url)
                }
            }
        }
        .glassCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.pink.opacity(highlighted ? 0.75 : 0), lineWidth: 1.5)
        )
        .scaleEffect(highlighted ? 1.03 : 1)
    }

    private var noteTile: some View {
        Text("🎵")
            .font(.system(size: 24))
            .frame(width: 48, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.mint.opacity(0.25), Theme.blue.opacity(0.18)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .rotationEffect(.degrees(-5))
    }

    private func addedByLine(_ song: Song) -> some View {
        HStack(spacing: 5) {
            EmojiAvatarView(emoji: adder(of: song)?.avatar,
                            colorHex: adder(of: song)?.color,
                            size: 16)
            Text(addedInfo(song))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private func adder(of song: Song) -> Member? {
        appState.couple?.members.first { $0.id == song.addedBy }
    }

    private func addedInfo(_ song: Song) -> String {
        let name = isMine(song)
            ? L10n.t("common.you")
            : (adder(of: song)?.name ?? appState.partnerName)
        let date = song.createdAt.formatted(date: .abbreviated, time: .omitted)
        return L10n.t("memories.soundtrack.by", ["name": name]) + " · " + date
    }

    // MARK: Heart

    private func heartButton(_ song: Song) -> some View {
        let mine = song.isHearted(by: appState.memberId)
        let count = song.heartedBy?.count ?? 0
        return Button {
            toggleHeart(song)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: mine ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .bold))
                Text(String(count))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                if count >= 2 {
                    Text("💞")
                        .font(.system(size: 10))
                }
            }
            .foregroundStyle(mine ? Theme.pink : Theme.textSecondary)
            .padding(.vertical, 5)
            .padding(.horizontal, 9)
            .background(Capsule().fill(mine ? Theme.pink.opacity(0.16) : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("memories.soundtrack.heart"))
    }

    private func toggleHeart(_ song: Song) {
        guard let api = appState.api, let myId = appState.memberId else { return }
        let wasHearted = song.isHearted(by: myId)
        setMyHeart(!wasHearted, on: song.id, myId: myId)
        Haptics.shared.tap()
        Task {
            do {
                let updated = try await api.toggleSongHeart(id: song.id)
                apply(updated)
            } catch {
                // Revert by inverting only MY op on the CURRENT array — a
                // partner's concurrent song_updated heart stays intact.
                setMyHeart(wasHearted, on: song.id, myId: myId)
                appState.handleAPIError(error)
            }
        }
    }

    /// Adds/removes only MY member id in the song's current heartedBy array.
    private func setMyHeart(_ hearted: Bool, on songId: String, myId: String) {
        guard let idx = songs.firstIndex(where: { $0.id == songId }) else { return }
        var hearts = songs[idx].heartedBy ?? []
        if hearted {
            if !hearts.contains(myId) { hearts.append(myId) }
        } else {
            hearts.removeAll { $0 == myId }
        }
        songs[idx].heartedBy = hearts
    }

    // MARK: Listen link

    private func listenButton(_ url: URL) -> some View {
        Button {
            Haptics.shared.tap()
            openURL(url)
        } label: {
            Text(L10n.t("memories.soundtrack.listen"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.blue)
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(Capsule().fill(Theme.blue.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }

    /// Builds a tappable URL — prepends https:// when the link has no scheme.
    private func listenURL(_ link: String?) -> URL? {
        guard let link else { return nil }
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        return URL(string: candidate)
    }

    // MARK: Add button

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    Haptics.shared.tap()
                    editorTarget = EditorTarget(id: "new", song: nil)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.heroGradient)
                            .frame(width: 60, height: 60)
                            .shadow(color: Theme.pink.opacity(0.5), radius: 14, y: 6)
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("memories.soundtrack.add"))
                .padding(.trailing, 20)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: Actions

    private func loadSongs() async {
        guard let api = appState.api else { return }
        do {
            songs = try await api.songs()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private func delete(_ song: Song) {
        guard let api = appState.api else { return }
        songs.removeAll { $0.id == song.id }
        Task {
            do {
                try await api.deleteSong(id: song.id)
                appState.showToast(L10n.t("memories.soundtrack.deleted"), style: .info)
            } catch {
                insert(song)
                appState.handleAPIError(error)
            }
        }
    }

    // MARK: Realtime

    private func insert(_ song: Song) {
        guard !songs.contains(where: { $0.id == song.id }) else { return }
        songs.append(song)
    }

    private func apply(_ song: Song) {
        if let idx = songs.firstIndex(where: { $0.id == song.id }) {
            songs[idx] = song
        } else {
            songs.append(song)
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .songAdded:
            if let song = event.decode(SongResponse.self)?.song {
                insert(song)
            }
        case .songUpdated:
            if let song = event.decode(SongResponse.self)?.song {
                apply(song)
            }
        case .songDeleted:
            if let id = event.decode(IdPayload.self)?.id {
                songs.removeAll { $0.id == id }
            }
        default:
            break
        }
    }
}

// MARK: - Add / edit sheet

private struct SongEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// nil = add a new song, non-nil = edit my existing song.
    let song: Song?
    let onSaved: (Song) -> Void

    @State private var title: String
    @State private var artist: String
    @State private var note: String
    @State private var link: String
    @State private var saving = false

    init(song: Song?, onSaved: @escaping (Song) -> Void) {
        self.song = song
        self.onSaved = onSaved
        _title = State(initialValue: song?.title ?? "")
        _artist = State(initialValue: song?.artist ?? "")
        _note = State(initialValue: song?.note ?? "")
        _link = State(initialValue: song?.link ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        titleField
                        artistField
                        noteField
                        linkField
                        saveButton
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.t(song == nil
                                    ? "memories.soundtrack.addTitle"
                                    : "memories.soundtrack.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(Theme.pink)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var titleField: some View {
        TextField(L10n.t("memories.soundtrack.titleField"), text: $title)
            .textFieldStyle(DreamyFieldStyle())
            .submitLabel(.next)
    }

    private var artistField: some View {
        TextField(L10n.t("memories.soundtrack.artistField"), text: $artist)
            .textFieldStyle(DreamyFieldStyle())
            .submitLabel(.next)
    }

    private var noteField: some View {
        TextField(L10n.t("memories.soundtrack.noteField"), text: $note, axis: .vertical)
            .textFieldStyle(DreamyFieldStyle())
            .lineLimit(1...3)
    }

    private var linkField: some View {
        TextField(L10n.t("memories.soundtrack.linkField"), text: $link)
            .textFieldStyle(DreamyFieldStyle())
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            if saving {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L10n.t("common.save"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        guard let api = appState.api, !saving else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        saving = true
        Task {
            do {
                if let song {
                    try await update(song, api: api, title: trimmedTitle,
                                     artist: trimmedArtist, note: trimmedNote, link: trimmedLink)
                } else {
                    let created = try await api.addSong(title: trimmedTitle,
                                                        artist: trimmedArtist.isEmpty ? nil : trimmedArtist,
                                                        note: trimmedNote.isEmpty ? nil : trimmedNote,
                                                        link: trimmedLink.isEmpty ? nil : trimmedLink)
                    onSaved(created)
                    SoundEngine.shared.play(.pop)
                    Haptics.shared.success()
                    appState.showToast(L10n.t("memories.soundtrack.added"), style: .love)
                    dismiss()
                }
            } catch {
                appState.handleAPIError(error)
            }
            saving = false
        }
    }

    /// PATCHes only changed, non-empty fields. The API client only serializes
    /// non-nil params (it can't express an explicit null), so CLEARING a field
    /// by leaving it empty is NOT supported client-side yet — empty optionals
    /// are simply skipped and keep their server value.
    private func update(_ song: Song, api: API, title: String,
                        artist: String, note: String, link: String) async throws {
        let newTitle = title != song.title ? title : nil
        let newArtist = (!artist.isEmpty && artist != song.artist) ? artist : nil
        let newNote = (!note.isEmpty && note != song.note) ? note : nil
        let newLink = (!link.isEmpty && link != song.link) ? link : nil
        if newTitle == nil && newArtist == nil && newNote == nil && newLink == nil {
            dismiss()
            return
        }
        let updated = try await api.updateSong(id: song.id, title: newTitle, artist: newArtist,
                                               note: newNote, link: newLink)
        onSaved(updated)
        Haptics.shared.success()
        appState.showToast(L10n.t("memories.soundtrack.updated"), style: .success)
        dismiss()
    }
}
