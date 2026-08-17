import SwiftUI
import Combine

// The Games-Wave-II surfaces in ONE file (there is deliberately no
// `GamesWaveView` type): the tutorial library + three-step tutorial
// sheets, Word Chain Blitz, Hangman and Couple Bingo. The pure rules
// they consume live in Content/GamesWaveLogic.swift (Linux-pinned).

// MARK: - Tutorial library

struct GameTutorialLibraryView: View {
    @Environment(\.coupleTint) private var coupleTint
    @State private var selected: GameTutorial?

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                LazyVStack(spacing: LayoutMetrics.s(10)) {
                    Text(L10n.t("games.tutorial.library.body"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                    ForEach(GameTutorialCatalog.library) { tutorial in
                        Button {
                            selected = tutorial
                        } label: {
                            HStack(spacing: LayoutMetrics.s(12)) {
                                GameKindGlyph(kind: GameKind(rawValue: tutorial.id),
                                              size: 28, tint: coupleTint.blend)
                                    .accessibilityHidden(true)
                                Text(tutorial.title.resolved(L10n.lang))
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Papier.aufNacht)
                                Spacer()
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(coupleTint.blend)
                            }
                            .nightCard(grain: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(LayoutMetrics.s(16))
            }
        }
        .navigationTitle(L10n.t("games.tutorial.library.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { tutorial in
            GameTutorialView(tutorial: tutorial)
        }
    }
}

struct GameTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let tutorial: GameTutorial

    @AppStorage private var savedStep: Int
    @State private var step: Int
    @State private var practice = false

    init(tutorial: GameTutorial) {
        self.tutorial = tutorial
        let key = "sooodreamy.gameTutorial.\(tutorial.id)"
        let existing = UserDefaults.standard.integer(forKey: key)
        _savedStep = AppStorage(wrappedValue: existing, key)
        _step = State(initialValue: min(existing, 2))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: LayoutMetrics.s(20)) {
                    Text(tutorial.emoji)
                        .font(.system(.largeTitle, design: .rounded))
                        .accessibilityHidden(true)
                    Text(tutorial.title.resolved(L10n.lang))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    if practice {
                        practiceCard
                    } else {
                        VStack(spacing: 12) {
                            Text(L10n.t("games.tutorial.step", [
                                "n": "\(step + 1)",
                                "total": "\(tutorial.steps.count)",
                            ]))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Licht.glut)
                            Text(tutorial.steps[step].resolved(L10n.lang))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(Papier.aufNacht)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 90)
                        }
                        .frame(maxWidth: .infinity)
                        .nightCard(padding: .hero)
                    }

                    HStack(spacing: 8) {
                        ForEach(tutorial.steps.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == step ? coupleTint.blend : Theme.textTertiary)
                                .frame(width: index == step ? 28 : 8, height: 8)
                        }
                    }

                    Button {
                        advance()
                    } label: {
                        Text(step == tutorial.steps.count - 1
                             ? L10n.t("games.tutorial.practice")
                             : L10n.t("games.tutorial.next"))
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(L10n.t("games.tutorial.skip")) {
                        savedStep = tutorial.steps.count
                        dismiss()
                    }
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(LayoutMetrics.s(24))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private var practiceCard: some View {
        VStack(spacing: 12) {
            Label(L10n.t("games.practice.local"), systemImage: "iphone")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Licht.glut)
            Text(tutorial.practicePrompt.resolved(L10n.lang))
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Papier.aufNacht)
                .multilineTextAlignment(.center)
            Text(L10n.t("games.practice.honest"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    private func advance() {
        if practice {
            savedStep = tutorial.steps.count
            dismiss()
        } else if step < tutorial.steps.count - 1 {
            step += 1
            savedStep = max(savedStep, step)
            Haptics.shared.tap()
        } else {
            practice = true
            savedStep = tutorial.steps.count
            Haptics.shared.success()
        }
    }
}

// MARK: - Word Chain Blitz

struct WordChainView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var word = ""
    @State private var sending = false
    @State private var tutorial: GameTutorial?
    /// Inline verdict of `WordChainRules.validate` — set on a rejected
    /// submit, cleared as soon as the word changes. Never `.valid`.
    @State private var feedback: WordChainValidation?

    private var session: GameSession? {
        guard engine.session?.kind == .wordchain else { return nil }
        return engine.session
    }

    private var words: [(String, String)] {
        engine.moves(kind: "word").compactMap {
            guard let text = $0.data["text"]?.stringValue else { return nil }
            return ($0.memberId, text)
        }
    }

    private var starter: String { session?.createdBy ?? "" }
    private var partner: String {
        appState.couple?.members.first { $0.id != starter }?.id ?? ""
    }
    private var turn: String { words.count.isMultiple(of: 2) ? starter : partner }
    private var myTurn: Bool { turn == appState.memberId }
    /// The chain letter — through `WordChainRules.normalized`, the SAME
    /// pure rule the validator and the tests use (no inline twin that
    /// could drift from the ß→ss law).
    private var requiredLetter: String? {
        words.last.map { WordChainRules.normalized($0.1) }?
            .last.map { String($0).uppercased() }
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.wordchain.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar { tutorialButton(kind: "wordchain") }
        .sheet(item: $tutorial) { GameTutorialView(tutorial: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent { engine.handle(event) }
        }
        .task {
            engine.onError = { [weak appState] in appState?.handleAPIError($0) }
            if engine.session == nil { await engine.resume(api: appState.api) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView { GameLobbyView(engine: engine, accent: Licht.glut).padding(LayoutMetrics.s(16)) }
            } else if session.state == "ended" {
                endScreen
            } else {
                playScreen
            }
        } else {
            setupScreen
        }
    }

    private var setupScreen: some View {
        gameSetup(
            symbol: "link",
            tint: coupleTint.blend,
            teaser: L10n.t("games.card.wordchain.teaser"),
            body: L10n.t("games.wordchain.rules"),
            start: start
        )
    }

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(myTurn ? L10n.t("games.turn.yours")
                             : L10n.t("games.turn.partner", ["name": appState.partnerName]))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        if let requiredLetter {
                            Text(L10n.t("games.wordchain.required", ["letter": requiredLetter]))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Licht.glut)
                        }
                    }
                    Spacer()
                    PillTag(text: "\(words.count)", tint: coupleTint.blend)
                }
                .nightCard(grain: false)

                LazyVStack(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.offset) { index, entry in
                        HStack {
                            Text("\(index + 1)")
                                .font(.system(.caption, design: .rounded).weight(.heavy))
                                .foregroundStyle(coupleTint.tinte)
                            Text(entry.1)
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Tinte.dunkel)
                            Spacer()
                            Text(entry.0 == appState.memberId ? L10n.t("common.you") : appState.partnerName)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Tinte.sekundaer)
                        }
                        .paperCard(grain: false)
                    }
                }

                // The next word gets written on the pad itself — an inner
                // fill on the zettel, never a second material (Migration §4).
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        TextField(L10n.t("games.wordchain.placeholder"), text: $word)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Tinte.dunkel)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.papier)
                                    .fill(Papier.innenFill)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.papier)
                                        .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
                            )
                        Button { submit() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(.title2, design: .rounded))
                                .foregroundStyle(coupleTint.tinte)
                        }
                        .disabled(!myTurn || sending || word.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                    // Inline verdict of the pure rule — caution writes in
                    // amber wax ON paper (the sanctioned deadline ink).
                    if let feedback {
                        Text(feedbackText(feedback))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Wachs.gelb)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                .paperCard(grain: false)
                .onChange(of: word) {
                    feedback = nil
                }

                Button(L10n.t("games.wordchain.finish")) { finish() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!myTurn || sending || words.isEmpty)
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Image(systemName: "link")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(L10n.t("games.wordchain.result", ["count": "\(words.count)"]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Button(L10n.t("games.rematch")) { start() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(24))
            .contentColumn(.reading)
        }
    }

    private func start() {
        Task {
            let payload = JSONValue.object([
                "lang": .string(L10n.lang),
                "dateKey": .string(SharedDates.todayKey()),
            ])
            _ = await engine.create(api: appState.api, type: .wordchain, payload: payload)
        }
    }

    private func submit() {
        let candidate = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard myTurn, !sending else { return }
        // The pure rule runs BEFORE the move leaves the device: the same
        // WordChainRules the LogicTests pin — inline feedback instead of
        // a silent server bounce.
        let verdict = WordChainRules.validate(candidate, after: words.last?.1,
                                              used: words.map(\.1),
                                              language: L10n.lang)
        guard verdict == .valid else {
            withAnimation(Theme.Motion.settle) { feedback = verdict }
            Haptics.shared.warning()
            return
        }
        feedback = nil
        sending = true
        Task {
            let ok = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("word"),
                "index": .number(Double(words.count)),
                "text": .string(candidate),
            ]))
            if ok { word = ""; Haptics.shared.success() }
            sending = false
        }
    }

    /// Spoken form of a validate verdict — `wrongLetter` reuses the
    /// existing chain-letter line, the rest have their own keys.
    private func feedbackText(_ verdict: WordChainValidation) -> String {
        switch verdict {
        case .valid:
            return ""
        case .empty:
            return L10n.t("games.wordchain.feedback.empty")
        case .unknown:
            return L10n.t("games.wordchain.feedback.unknown")
        case .repeated:
            return L10n.t("games.wordchain.feedback.repeated")
        case .wrongLetter(let letter):
            return L10n.t("games.wordchain.required",
                          ["letter": String(letter).uppercased()])
        }
    }

    private func finish() {
        sending = true
        Task {
            _ = await engine.sendMove(api: appState.api, data: .object(["kind": .string("finish")]))
            sending = false
        }
    }

    @ToolbarContentBuilder
    private func tutorialButton(kind: String) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                tutorial = GameTutorialCatalog.tutorial(for: kind)
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel(L10n.t("games.tutorial.open"))
        }
    }
}

// MARK: - Hangman: Our Word

struct HangmanView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var secret = ""
    @State private var hint = ""
    @State private var sending = false
    @State private var tutorial: GameTutorial?

    private var session: GameSession? {
        guard engine.session?.kind == .hangman else { return nil }
        return engine.session
    }
    private var setter: String { session?.createdBy ?? "" }
    private var guesser: String {
        appState.couple?.members.first { $0.id != setter }?.id ?? ""
    }
    private var length: Int {
        session?.payload?["len"]?.intValue
            ?? engine.moves(kind: "setup").first?.data["len"]?.intValue
            ?? 0
    }
    private var clue: String {
        session?.payload?["hint"]?.stringValue
            ?? engine.moves(kind: "setup").first?.data["hint"]?.stringValue
            ?? ""
    }
    private var guesses: [HangmanGuess] {
        var result: [HangmanGuess] = []
        for move in engine.orderedMoves {
            if move.data["kind"]?.stringValue == "letter",
               let value = move.data["letter"]?.stringValue?.first {
                result.append(HangmanGuess(letter: value, positions: nil))
            } else if move.data["kind"]?.stringValue == "positions",
                      let letter = move.data["letter"]?.stringValue?.first,
                      let positions = move.data["positions"]?.arrayValue?.compactMap(\.intValue),
                      let index = result.firstIndex(where: { $0.letter == letter && $0.positions == nil }) {
                result[index] = HangmanGuess(letter: letter, positions: positions)
            }
        }
        return result
    }
    private var state: HangmanBoardState { HangmanRules.reduce(length: length, guesses: guesses) }
    private var asked: Set<Character> { Set(guesses.map(\.letter)) }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.hangman.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tutorial = GameTutorialCatalog.tutorial(for: "hangman") } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel(L10n.t("games.tutorial.open"))
            }
        }
        .sheet(item: $tutorial) { GameTutorialView(tutorial: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
                advanceSetter()
            }
        }
        .task {
            engine.onError = { [weak appState] in appState?.handleAPIError($0) }
            if engine.session == nil { await engine.resume(api: appState.api) }
            advanceSetter()
        }
        .onChange(of: engine.session?.state) { _, _ in advanceSetter() }
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView { GameLobbyView(engine: engine, accent: Licht.lampengold).padding(LayoutMetrics.s(16)) }
            } else if session.state == "ended" {
                endScreen
            } else {
                playScreen
            }
        } else {
            setupScreen
        }
    }

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "textformat.abc")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.hangman.rules"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                TextField(L10n.t("games.hangman.word"), text: $secret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.none)
                TextField(L10n.t("games.hangman.hint"), text: $hint)
                Button(L10n.t("games.hangman.seal")) { start() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(cleanSecret.count < 3 || cleanSecret.count > 24 || sending)
                Text(L10n.t("games.hangman.privacy"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .multilineTextAlignment(.center)
            }
            .textFieldStyle(.roundedBorder)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(state.lost ? "🥀" : "🌸")
                    .font(.system(.largeTitle, design: .rounded))
                if !clue.isEmpty {
                    // The hint is a night note next to the word card —
                    // ember ink so it reads as "written extra", not body.
                    Label(clue, systemImage: "lightbulb.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.glut)
                        .nightCard(padding: .compact, grain: false)
                }
                HStack(spacing: 6) {
                    ForEach(0..<length, id: \.self) { index in
                        Text(state.revealed.contains(index)
                             ? revealedCharacter(at: index)
                             : "•")
                            .font(.system(.title2, design: .monospaced).weight(.heavy))
                            .frame(minWidth: 20)
                            .foregroundStyle(Tinte.dunkel)
                    }
                }
                .paperCard()
                Text(L10n.t("games.hangman.wrong", [
                    "count": "\(state.wrong)",
                    "max": "\(HangmanRules.maxWrong)",
                ]))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(state.wrong >= 7 ? Theme.energyRed : Theme.textSecondary)

                if appState.memberId == guesser {
                    letterGrid
                    if state.pending != nil { GameWaitingHint() }
                } else {
                    Text(state.pending == nil
                         ? L10n.t("games.hangman.waitGuess")
                         : L10n.t("games.hangman.answering"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                        .nightCard(grain: false)
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            // Letter-game column (roadmap 22): word + letters one hand wide.
            .contentColumn(.keys)
        }
    }

    /// Letter keys on a karton pad — the Wordle keyboard treatment: fresh
    /// keys are letter paper, spent ones sink into the matte inner fill.
    private var letterGrid: some View {
        let letters = Array(L10n.lang == "de" ? "abcdefghijklmnopqrstuvwxyzäöü" : "abcdefghijklmnopqrstuvwxyz")
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(letters, id: \.self) { letter in
                Button(String(letter).uppercased()) { guess(letter) }
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .buttonStyle(.plain)
                    .foregroundStyle(asked.contains(letter) ? Tinte.tertiaer : Tinte.dunkel)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(
                            asked.contains(letter) ? Papier.innenFill : Papier.brief)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
                    )
                    .disabled(asked.contains(letter) || state.pending != nil || sending || state.solved || state.lost)
            }
        }
        .paperCard(.karton, padding: .compact, grain: false)
    }

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Image(systemName: session?.result?["integrity"]?.boolValue == false
                      ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(session?.result?["integrity"]?.boolValue == false
                                     ? Licht.glut : Licht.lampengold)
                    .background(session?.result?["integrity"]?.boolValue == false
                                ? nil : VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(session?.result?["word"]?.stringValue ?? L10n.t("games.hangman.revealed"))
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                Text(session?.result?["integrity"]?.boolValue == false
                     ? L10n.t("games.hangman.integrityFailed")
                     : L10n.t("games.hangman.integrity"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                Button(L10n.t("games.rematch")) { startSuggested() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(24))
            .contentColumn(.reading)
        }
    }

    private var cleanSecret: String {
        secret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func start() {
        let value = cleanSecret
        guard value.count >= 3,
              value.count <= 24,
              value.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else { return }
        let salt = CommitReveal.newSalt()
        sending = true
        Task {
            let payload = JSONValue.object([
                "lang": .string(L10n.lang),
                "commit": .string(CommitReveal.commit(secret: value, salt: salt)),
                "len": .number(Double(value.count)),
                "hint": .string(String(hint.prefix(60))),
            ])
            if await engine.create(api: appState.api, type: .hangman, payload: payload),
               let id = engine.session?.id {
                saveSecret(word: value, salt: salt, gameId: id)
                secret = ""
                hint = ""
            }
            sending = false
        }
    }

    private func startSuggested() {
        secret = HangmanRules.words[L10n.lang]?.randomElement() ?? (L10n.lang == "de" ? "Herz" : "Heart")
        hint = ""
        engine.adopt(nil)
    }

    private func guess(_ letter: Character) {
        sending = true
        Task {
            _ = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("letter"),
                "letter": .string(String(letter)),
            ]))
            sending = false
        }
    }

    private func advanceSetter() {
        guard appState.memberId == setter,
              session?.state == "active",
              !sending,
              let gameId = session?.id,
              let saved = loadSecret(gameId: gameId) else { return }
        if let pending = state.pending {
            sending = true
            let positions = HangmanRules.positions(of: pending, in: saved.word)
            Task {
                _ = await engine.sendMove(api: appState.api, data: .object([
                    "kind": .string("positions"),
                    "letter": .string(String(pending)),
                    "positions": .array(positions.map { .number(Double($0)) }),
                ]))
                sending = false
                advanceSetter()
            }
        } else if state.solved || state.lost {
            sending = true
            Task {
                _ = await engine.sendMove(api: appState.api, data: .object([
                    "kind": .string("reveal"),
                    "reveal": .string(saved.word),
                    "salt": .string(saved.salt),
                ]))
                sending = false
                UserDefaults.standard.removeObject(forKey: secretKey(gameId))
            }
        }
    }

    private func revealedCharacter(at index: Int) -> String {
        if let id = session?.id, let word = loadSecret(gameId: id)?.word {
            let characters = Array(word)
            if characters.indices.contains(index) {
                return String(characters[index]).uppercased()
            }
        }
        if let guess = guesses.first(where: { $0.positions?.contains(index) == true }) {
            return String(guess.letter).uppercased()
        }
        return "♥"
    }

    private func secretKey(_ gameId: String) -> String { "sooodreamy.hangman.secret.\(gameId)" }

    private func saveSecret(word: String, salt: String, gameId: String) {
        UserDefaults.standard.set(["word": word, "salt": salt], forKey: secretKey(gameId))
    }

    private func loadSecret(gameId: String) -> (word: String, salt: String)? {
        guard let value = UserDefaults.standard.dictionary(forKey: secretKey(gameId)),
              let word = value["word"] as? String,
              let salt = value["salt"] as? String else { return nil }
        return (word, salt)
    }
}

// MARK: - Weekly Couple Bingo

struct CoupleBingoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var celebrated = false
    @State private var tutorial: GameTutorial?

    private var session: GameSession? {
        guard engine.session?.kind == .bingo else { return nil }
        return engine.session
    }
    private var actionIndexes: [Int] {
        session?.payload?["cardIndexes"]?.arrayValue?.compactMap(\.intValue) ?? []
    }
    private var checked: Set<Int> {
        Set(engine.moves(kind: "auto_check").compactMap { $0.data["cardIndex"]?.intValue })
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if session?.state == "ended" {
                FloatingHeartsView(emojis: ["💞", "✨", "B", "I", "N", "G", "O"], count: 28)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.bingo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tutorial = GameTutorialCatalog.tutorial(for: "bingo") } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel(L10n.t("games.tutorial.open"))
            }
        }
        .sheet(item: $tutorial) { GameTutorialView(tutorial: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent { engine.handle(event) }
        }
        .task {
            engine.onError = { [weak appState] in appState?.handleAPIError($0) }
            if engine.session == nil { await engine.resume(api: appState.api) }
            celebrateIfNeeded()
        }
        .onChange(of: engine.session?.state) { _, _ in celebrateIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView { GameLobbyView(engine: engine, accent: Licht.lampengold).padding(LayoutMetrics.s(16)) }
            } else {
                board
            }
        } else {
            gameSetup(
                symbol: "heart.text.square.fill",
                tint: coupleTint.blend,
                teaser: L10n.t("games.card.bingo.teaser"),
                body: L10n.t("games.bingo.rules"),
                start: start
            )
        }
    }

    /// Phone: stacked. Wide regular panes: the bingo card centered like a
    /// real card on the table, status + rules in the rail (roadmap 22).
    private var board: some View {
        GameTableContainer(gameType: "bingo") { paneWidth in
            GameTableLayout(gameType: "bingo", paneWidth: paneWidth) {
                cardGrid
            } rail: {
                VStack(spacing: LayoutMetrics.s(14)) {
                    statusLine
                    autoNote
                    nextWeekButton
                }
                .gameActGated()
            }
        } stacked: {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(14)) {
                    statusLine
                    cardGrid
                    autoNote
                    nextWeekButton
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
            }
        }
    }

    /// Status as a night note on the table — lamp gold when the card is
    /// full, plain paper-white ink while the week is still running.
    @ViewBuilder
    private var statusLine: some View {
        if session?.state == "ended" {
            Text(L10n.t("games.bingo.complete"))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Licht.lampengold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .nightCard(grain: false)
        } else {
            Text(L10n.t("games.bingo.progress", ["count": "\(checked.count)"]))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .frame(maxWidth: .infinity)
                .nightCard(grain: false)
        }
    }

    /// The weekly card is ONE sheet of paper on the night table; the 16
    /// fields are inner fills on it, never cards of their own.
    private var cardGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(Array(actionIndexes.enumerated()), id: \.offset) { position, actionIndex in
                bingoCell(position: position, actionIndex: actionIndex)
            }
        }
        .paperCard(padding: .compact)
    }

    private var autoNote: some View {
        Text(L10n.t("games.bingo.auto"))
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var nextWeekButton: some View {
        if session?.state == "ended" {
            Button(L10n.t("games.bingo.nextWeek")) { start() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func bingoCell(position: Int, actionIndex: Int) -> some View {
        let action = CoupleBingo.actions.indices.contains(actionIndex)
            ? CoupleBingo.actions[actionIndex]
            : CoupleBingo.actions[0]
        let done = checked.contains(position)
        return VStack(spacing: 6) {
            Image(systemName: done ? "checkmark.seal.fill" : "heart")
                .foregroundStyle(done ? coupleTint.tinte : Wachs.rot)
            Text(action.text.resolved(L10n.lang))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: 102)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: Radius.papier).fill(
            done ? coupleTint.tinte.opacity(0.16) : Papier.innenFill
        ))
        .overlay(RoundedRectangle(cornerRadius: Radius.papier).strokeBorder(
            done ? coupleTint.tinte : Papier.kante,
            lineWidth: done ? 1.5 : Theme.hairlineWidth
        ))
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? L10n.t("games.bingo.checked") : L10n.t("games.bingo.open"))
    }

    private func start() {
        Task {
            _ = await engine.create(api: appState.api, type: .bingo, payload: .object([:]))
        }
    }

    private func celebrateIfNeeded() {
        guard session?.state == "ended", !celebrated else { return }
        celebrated = true
        // The view already rains its own B-I-N-G-O letters — only the
        // tiered fanfare + victory motif come from the ceremony layer.
        GameEndCelebration.win(theme: .hearts, visual: .localHearts)
    }
}

// MARK: - Shared setup shell

private func gameSetup(
    symbol: String,
    tint: Color,
    teaser: String,
    body: String,
    start: @escaping () -> Void
) -> some View {
    ScrollView {
        VStack(spacing: LayoutMetrics.s(16)) {
            Image(systemName: symbol)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(teaser)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            Button(L10n.t("games.start"), action: start)
                .buttonStyle(PrimaryButtonStyle())
        }
        .nightCard(padding: .hero)
        .padding(LayoutMetrics.s(16))
        .contentColumn(.reading)
    }
}
