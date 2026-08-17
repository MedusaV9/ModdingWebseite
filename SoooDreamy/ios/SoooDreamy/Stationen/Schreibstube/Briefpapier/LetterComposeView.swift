import SwiftUI

/// Letter-draft persistence per server profile (roadmap 20) — the same
/// storage pattern as `ChatComposerDrafts`; the pure rules (key format,
/// restore condition, emptiness) live in `Content/DraftContinuityRules`
/// and are pinned by the Linux logic tests.
enum LetterDraftStore {
    static func load(profileID: String?) -> LetterDraft? {
        let key = DraftContinuityRules.letterDraftKey(profileID: profileID)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LetterDraft.self, from: data)
    }

    /// Empty drafts remove their slot instead of storing blank strings.
    static func save(_ draft: LetterDraft, profileID: String?) {
        let key = DraftContinuityRules.letterDraftKey(profileID: profileID)
        if draft.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear(profileID: String?) {
        UserDefaults.standard.removeObject(
            forKey: DraftContinuityRules.letterDraftKey(profileID: profileID))
    }
}

/// Love-letter composer sheet: title + long text, live preview card,
/// celebratory hearts on success.
struct LetterComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Optional "Öffnen wenn …" seal.
    private enum SealChoice: Equatable {
        case none
        case preset(String)
        case custom
    }

    @State private var title = ""
    @State private var text = ""
    @State private var sealChoice: SealChoice = .none
    @State private var customSeal = ""
    @State private var sending = false
    @State private var sent = false
    /// Debounces the per-profile draft mirror (~0.5 s after the last edit).
    @State private var draftSaveTask: Task<Void, Never>?
    let onSent: (Message) -> Void

    /// Whether a stored draft may be restored into this launch — only
    /// EMPTY launches restore; forwarding a letter keeps its own content
    /// (and never clobbers the saved draft: those edits aren't mirrored).
    private let restoresDraft: Bool

    /// Empty by default; pre-filled when forwarding an existing letter
    /// as a new one (the seal is deliberately NOT copied over).
    init(initialTitle: String = "", initialText: String = "",
         onSent: @escaping (Message) -> Void) {
        _title = State(initialValue: initialTitle)
        _text = State(initialValue: initialText)
        restoresDraft = DraftContinuityRules.shouldRestore(initialTitle: initialTitle,
                                                           initialText: initialText)
        self.onSent = onSent
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token sent as `openWhen` (nil when unsealed).
    private var openWhenToken: String? {
        switch sealChoice {
        case .none:
            return nil
        case .preset(let token):
            return token
        case .custom:
            let custom = customSeal.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? nil : LetterSeal.customPrefix + custom
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        titleField
                        editor
                        // Nacht-first (P2-B): the AI workshop moved OUT of
                        // the letter paper — machine tooling is a night
                        // card below the artifact, so the writing pane
                        // stays pure correspondence. It renders nothing
                        // (not even a card shell) without available
                        // Apple Intelligence.
                        LetterWorkshopView(letterText: $text,
                                           disabled: sending || sent)
                        sealPicker
                        previewCard
                        sendButton
                    }
                    .padding(LayoutMetrics.s(16))
                }
                .scrollDismissesKeyboard(.interactively)
                if sent {
                    FloatingHeartsView(emojis: ["💌", "💖", "💜", "✨", "💞"], count: 24)
                        .ignoresSafeArea()
                        .zIndex(5)
                }
            }
            .navigationTitle(L10n.t("chat.letterTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("chat.cancel")) {
                        dismiss()
                    }
                    .disabled(sending || sent)
                }
            }
        }
        .tint(coupleTint.blend)
        .interactiveDismissDisabled(sending || sent)
        .onAppear { restoreDraft() }
        .onDisappear { flushDraft() }
        .onChange(of: title) { scheduleDraftSave() }
        .onChange(of: text) { scheduleDraftSave() }
        .onChange(of: sealChoice) { scheduleDraftSave() }
        .onChange(of: customSeal) { scheduleDraftSave() }
        .onChange(of: scenePhase) {
            // Multitasking hardening (roadmap 20): leaving the foreground
            // flushes immediately — an app kill inside the debounce window
            // must never eat a half-written letter.
            if scenePhase != .active { flushDraft() }
        }
    }

    // MARK: Draft continuity (per server profile)

    private var activeProfileID: String? {
        appState.servers.activeProfileID?.uuidString
    }

    /// The composer content as a persistable draft. An armed-but-empty
    /// custom seal collapses to nil — nothing worth keeping.
    private var currentDraft: LetterDraft {
        LetterDraft(title: title, text: text, sealToken: openWhenToken)
    }

    /// Restores the saved draft into an EMPTY composer launch — including
    /// the armed seal, which is part of the half-written thought.
    private func restoreDraft() {
        guard restoresDraft, !sent,
              let draft = LetterDraftStore.load(profileID: activeProfileID) else { return }
        title = draft.title
        text = draft.text
        applySealToken(draft.sealToken)
    }

    private func applySealToken(_ token: String?) {
        guard let token, !token.isEmpty else {
            sealChoice = .none
            return
        }
        if token.hasPrefix(LetterSeal.customPrefix) {
            sealChoice = .custom
            customSeal = String(token.dropFirst(LetterSeal.customPrefix.count))
        } else {
            sealChoice = .preset(token)
        }
    }

    /// Debounced mirror (~0.5 s after the last edit) — a process kill must
    /// not eat a half-written letter. Forwarding launches don't mirror:
    /// their content belongs to the forwarded letter, not the draft slot.
    private func scheduleDraftSave() {
        guard restoresDraft, !sent else { return }
        let draft = currentDraft
        let profileID = activeProfileID
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return  // superseded by a newer edit
            }
            LetterDraftStore.save(draft, profileID: profileID)
        }
    }

    /// Synchronous save — used on disappear and when the scene leaves the
    /// foreground. After a successful send the slot is already cleared.
    private func flushDraft() {
        draftSaveTask?.cancel()
        guard restoresDraft, !sent else { return }
        LetterDraftStore.save(currentDraft, profileID: activeProfileID)
    }

    // MARK: Fields

    private var titleField: some View {
        // The address line is written ON paper (Korrespondenz): a
        // free-standing paper slip with dark ink — the night-era matte
        // field carried near-white text on the compat paper fill.
        TextField(L10n.t("chat.letterTitlePlaceholder"),
                  text: $title,
                  prompt: Text(L10n.t("chat.letterTitlePlaceholder")).foregroundStyle(Tinte.tertiaer))
            .textFieldStyle(ChatPaperFieldStyle())
    }

    /// The writing pane: pure letter paper for the editor — the on-device
    /// workshop is its own NIGHT card below (P2-B; results are drafts the
    /// person taps into the editor, never autosent).
    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L10n.t("chat.letterPlaceholder"))
                        .font(Typo.brief)
                        .foregroundStyle(Tinte.tertiaer)
                        .padding(.top, LayoutMetrics.s(16))
                        .padding(.leading, LayoutMetrics.s(17))
                        .allowsHitTesting(false)
                }
                // Writing happens on paper: the letter body is written in
                // the same upright reading serif the reader shows, in dark
                // ink — the compat fill under near-white text was the
                // CI-proven contrast bug.
                TextEditor(text: $text)
                    .font(Typo.brief)
                    .foregroundStyle(Tinte.dunkel)
                    .tint(Tinte.dunkel)
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 8)
                    .padding(.horizontal, LayoutMetrics.s(12))
                    .frame(minHeight: LayoutMetrics.s(180))
            }
        }
        .background {
            // One writing pane = one sheet of letter paper (no grain under
            // the editor — legibility beats charm while writing).
            let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
            shape.fill(Papier.brief)
                .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                            lineWidth: Theme.hairlineWidth))
                .elevation(.resting)
        }
    }

    // MARK: Seal picker

    private var sealPicker: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            // Section label ON paper: quiet ink — gold is banned as ink on
            // paper (1.4:1, migration table).
            Text(L10n.t("chat.sealPickerTitle"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.sekundaer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Chrome chips carry SF Symbols; only the mood seals in
                    // between keep their content emojis.
                    sealChip(icon: "envelope",
                             label: L10n.t("chat.sealNone"),
                             selected: sealChoice == .none) {
                        sealChoice = .none
                    }
                    ForEach(LetterSeal.presetTokens, id: \.self) { token in
                        sealChip(emoji: LetterSeal.emoji(for: token),
                                 label: LetterSeal.chipLabel(for: token),
                                 selected: sealChoice == .preset(token)) {
                            sealChoice = .preset(token)
                        }
                    }
                    sealChip(icon: "pencil",
                             label: L10n.t("chat.sealCustom"),
                             selected: sealChoice == .custom) {
                        sealChoice = .custom
                    }
                }
            }
            if sealChoice == .custom {
                customSealField
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Content card → paper (wave rule): the seal choices lie on a
        // Zettel, they do not float.
        .paperCard()
    }

    private var customSealField: some View {
        // Inner well INSIDE the paper card — innenFill wash with the kante
        // hairline, never a second material.
        TextField(L10n.t("chat.sealCustomPlaceholder"),
                  text: $customSeal,
                  prompt: Text(L10n.t("chat.sealCustomPlaceholder")).foregroundStyle(Tinte.tertiaer))
            .textFieldStyle(ChatPaperFieldStyle(inset: true))
            .onChange(of: customSeal) {
                if customSeal.count > 40 {
                    customSeal = String(customSeal.prefix(40))
                }
            }
    }

    private func sealChip(emoji: String? = nil, icon: String? = nil,
                          label: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) {
                action()
            }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .accessibilityHidden(true)
                } else if let emoji {
                    Text(emoji)
                }
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            // Chips ON paper: dark ink when chosen, quiet ink otherwise;
            // the selection ring is the couple's shared ink (inkOnPaper,
            // ≥4.5:1 pinned) over a faint ink wash — the raw blend and the
            // night tokens washed out on brief.
            .foregroundStyle(selected ? Tinte.dunkel : Tinte.sekundaer)
            .padding(.vertical, 7)
            .padding(.horizontal, LayoutMetrics.s(12))
            .background(
                Capsule()
                    .fill(selected ? AnyShapeStyle(coupleTint.tinte.opacity(0.12))
                                   : AnyShapeStyle(Papier.innenFill))
                    .overlay(
                        Capsule().strokeBorder(selected ? coupleTint.tinte : Papier.kante,
                                               lineWidth: selected ? 1.5 : Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Preview

    /// The preview renders the letter EXACTLY as the reader will: the
    /// screen's ONE Briefbogen hero — letter paper with the couple band
    /// and the wax seal crossing its head, serif only on the paper.
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: 6) {
                Image(systemName: "envelope.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
                    .accessibilityHidden(true)
                Text(L10n.t("chat.letterPreview"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.sekundaer)
                Spacer()
            }
            if let token = openWhenToken {
                previewSealRow(token)
            }
            // The couple's own words: italic serif voice for the address
            // line in the shared ink, upright reading serif in dark ink
            // for the body — exactly the reader's treatment.
            Text(title.isEmpty ? L10n.t("chat.letterUntitled") : title)
                .font(Typo.voice)
                .foregroundStyle(coupleTint.tinte)
            Text(text.isEmpty ? L10n.t("chat.letterPreviewEmpty") : text)
                .font(Typo.brief)
                .lineSpacing(5)
                .foregroundStyle(text.isEmpty ? Tinte.tertiaer : Tinte.dunkel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Head room so the band crosses paper, not the preview label.
        .padding(.top, LayoutMetrics.s(26))
        .paperCard(.briefbogen)
        .overlay(alignment: .top) {
            // Stable seed: the preview is a draft without an id — the seal
            // keeps one tilt across renders and launches.
            ChatBriefbogenBand(seed: chatPaperSeed("letter-compose-preview"))
                .offset(y: LayoutMetrics.s(14))
        }
    }

    private func previewSealRow(_ token: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.fill")
                .font(.system(.caption2, design: .rounded))
                .accessibilityHidden(true)
            Text(LetterSeal.sentence(for: token))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(2)
        }
        // Wax red as ink on paper (5.2:1 pinned) over a faint wax wash —
        // gold is banned as ink on paper (1.4:1).
        .foregroundStyle(Wachs.rot)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(Capsule().fill(Wachs.rot.opacity(0.10)))
    }

    // MARK: Send

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Text(sending ? L10n.t("chat.letterSending") : L10n.t("chat.letterSend"))
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(sending || sent || trimmedText.isEmpty)
        .padding(.top, 4)
    }

    private func send() {
        let body = trimmedText
        guard !body.isEmpty, !sending, !sent, let api = appState.api else { return }
        let letterTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        Haptics.shared.tap()
        Task {
            do {
                let message = try await api.sendMessage(type: .letter,
                                                        text: body,
                                                        title: letterTitle.isEmpty ? nil : letterTitle,
                                                        openWhen: openWhenToken)
                sending = false
                // The letter is on its way — the draft slot has served.
                draftSaveTask?.cancel()
                if restoresDraft { LetterDraftStore.clear(profileID: activeProfileID) }
                withAnimation(Theme.Motion.settle) {
                    sent = true
                }
                // Wax presses in, the seal sets — sound and hand agree.
                AppCue.sealed.play()
                appState.showToast(L10n.t("chat.letterSent"), style: .love)
                onSent(message)
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                dismiss()
            } catch {
                sending = false
                appState.handleAPIError(error)
            }
        }
    }
}
