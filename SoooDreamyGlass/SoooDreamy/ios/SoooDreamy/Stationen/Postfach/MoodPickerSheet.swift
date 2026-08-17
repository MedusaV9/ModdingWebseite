import SwiftUI

// The mood picker sheet — extracted from the old 2 300-line DashboardView
// (W8A component split). One tap saves; the note and the now-playing song
// stay optional follow-ups. The mood emoji themselves are CONTENT the
// couple shares, never UI chrome.

struct MoodPickerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    /// 16 moods with human labels — without words the grid is an emoji
    /// cliché quiz where 🫠 means three different things to two people
    /// (Dossier 32, idea 2).
    private static let moods: [(emoji: String, key: String)] = [
        ("🥰", "loved"), ("😊", "sunny"), ("😌", "calm"), ("🥳", "party"),
        ("😴", "sleepy"), ("🤒", "sick"), ("😢", "sad"), ("😤", "charged"),
        ("🥺", "needy"), ("😩", "drained"), ("💪", "strong"), ("🤗", "cuddly"),
        ("🫠", "melted"), ("🤍", "tender"), ("😇", "grateful"), ("🤪", "silly"),
    ]

    @State private var selected: String = ""
    @State private var note = ""
    /// Non-nil once THIS sheet wrote a mood — drives the "shared" confirm.
    @State private var savedMood: String?
    /// What the last save carried, so "Done" never re-sends unchanged data.
    @State private var lastSavedNote = ""
    @State private var songTitle = ""
    @State private var songArtist = ""
    @State private var savingSong = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        // One tap saves (Dossier 32, idea 1) — the confirm
                        // button was pure friction. The note stays as an
                        // optional follow-up below.
                        moodGrid
                        if savedMood != nil {
                            HStack(spacing: Space.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(Theme.mint)
                                Text(L10n.t("home.mood.saved"))
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .transition(.opacity)
                        }
                        TextField(L10n.t("home.moodNote"), text: $note, axis: .vertical)
                            .textFieldStyle(DreamyFieldStyle())
                            .lineLimit(1...3)
                        Button(L10n.t("common.done")) {
                            let trimmed = note.trimmingCharacters(in: .whitespaces)
                            if !selected.isEmpty, trimmed != lastSavedNote {
                                save(mood: selected)
                            }
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if appState.me?.mood != nil {
                            Button(L10n.t("common.delete")) {
                                appState.setMood(nil, note: nil)
                                dismiss()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        nowPlayingSection
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("home.setMood"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            selected = appState.me?.mood ?? ""
            note = appState.me?.moodNote ?? ""
            lastSavedNote = note.trimmingCharacters(in: .whitespaces)
            songTitle = appState.me?.nowPlaying?.title ?? ""
            songArtist = appState.me?.nowPlaying?.artist ?? ""
        }
    }

    private var moodGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 4),
                  spacing: Space.s) {
            ForEach(Self.moods, id: \.emoji) { mood in
                moodCell(mood)
            }
        }
    }

    private func moodCell(_ mood: (emoji: String, key: String)) -> some View {
        let isSelected = selected == mood.emoji
        return Button {
            Haptics.shared.tap()
            selected = mood.emoji
            save(mood: mood.emoji)
        } label: {
            VStack(spacing: 3) {
                Text(mood.emoji)
                    .font(.system(.title2))
                Text(L10n.t("mood.label.\(mood.key)"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(8))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(isSelected ? coupleTint.blend.opacity(0.3) : Theme.innerFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(isSelected ? coupleTint.blend : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("mood.label.\(mood.key)"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func save(mood: String) {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        appState.setMood(mood, note: trimmed.isEmpty ? nil : trimmed)
        withAnimation(Theme.Motion.settle) {
            savedMood = mood
        }
        lastSavedNote = trimmed
    }

    // MARK: "Gerade am Hören"

    private var nowPlayingSection: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("nowplaying.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
            }
            TextField(L10n.t("nowplaying.songField"), text: $songTitle)
                .textFieldStyle(DreamyFieldStyle())
            TextField(L10n.t("nowplaying.artistField"), text: $songArtist)
                .textFieldStyle(DreamyFieldStyle())
            Button {
                setNowPlaying()
            } label: {
                if savingSong {
                    BusySpinner()
                } else {
                    Text(L10n.t("nowplaying.set"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(savingSong || songTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            if appState.me?.nowPlaying != nil {
                Button(L10n.t("nowplaying.clear")) {
                    clearNowPlaying()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(savingSong)
            }
            Text(L10n.t("nowplaying.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard()
    }

    private func setNowPlaying() {
        guard let api = appState.api, !savingSong else { return }
        let title = songTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = songArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        savingSong = true
        Task {
            do {
                _ = try await api.setNowPlaying(title: title, artist: artist.isEmpty ? nil : artist)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            savingSong = false
        }
    }

    private func clearNowPlaying() {
        guard let api = appState.api, !savingSong else { return }
        savingSong = true
        Task {
            do {
                try await api.clearNowPlaying()
                Haptics.shared.tap()
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            savingSong = false
        }
    }
}
