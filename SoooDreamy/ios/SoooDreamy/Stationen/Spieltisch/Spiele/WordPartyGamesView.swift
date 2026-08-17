import SwiftUI
import Combine

// The word & party trio (`wordleduo`, `rps`, `story`) — the last three
// server game types without an iOS surface (parity fix FXC-3). All three
// ride the same relay conventions as their wave-II siblings in
// WaveGamesViews.swift: deterministic reducers over `payload` + ordered
// moves, commit-reveal via Core/CommitReveal.swift where hidden information
// exists, and the shared lobby/forfeit/spectator chrome from PlayHubView.

// MARK: - Wordle Duo — coop board, alternating guessers

/// Client-side derivation for the shared duo target. Both phones must land
/// on the SAME word without telling the humans: deterministic like
/// `WordleDaily.solution`, but with its own seed prefix so playing the duo
/// never spoils the solo daily duel word.
enum WordleDuoLogic {
    static func target(coupleId: String, dateKey: String, lang: String) -> String {
        let list = WordleDaily.words(lang: lang)
        guard !list.isEmpty else { return lang == "de" ? "LIEBE" : "HEART" }
        let seed = ("duo#" + dateKey + coupleId).unicodeScalars.reduce(5381 as UInt64) {
            ($0 << 5) &+ $0 &+ UInt64($1.value)
        }
        return list[Int(seed % UInt64(list.count))]
    }
}

struct WordleDuoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var guess = ""
    @State private var rejectedGuess = false
    @State private var sending = false
    @State private var celebrated = false

    private var session: GameSession? {
        guard engine.session?.kind == .wordleduo else { return nil }
        return engine.session
    }
    private var starter: String { session?.createdBy ?? "" }
    private var partner: String {
        appState.couple?.members.first { $0.id != starter }?.id ?? ""
    }
    private var maxRows: Int { engine.payloadInt("maxRows", default: 6) }
    private var dateKey: String {
        session?.payload?["dateKey"]?.stringValue ?? SharedDates.todayKey()
    }
    private var lang: String {
        session?.payload?["lang"]?.stringValue ?? L10n.lang
    }
    private var target: String {
        WordleDuoLogic.target(coupleId: appState.couple?.id ?? "",
                              dateKey: dateKey, lang: lang)
    }

    /// Mirror of the server's `wordleDuoState` reducer.
    private struct DuoState {
        var commit: String?
        var guesses: [String] = []
        var reveal: String?
    }

    private var duoState: DuoState {
        var state = DuoState()
        for move in engine.orderedMoves {
            guard let kind = move.data["kind"]?.stringValue else { continue }
            if kind == "target", state.commit == nil, move.memberId == starter {
                state.commit = move.data["commit"]?.stringValue
            } else if kind == "guess", state.commit != nil, state.reveal == nil,
                      move.data["row"]?.intValue == state.guesses.count,
                      let text = move.data["text"]?.stringValue,
                      move.memberId == (state.guesses.count.isMultiple(of: 2) ? starter : partner) {
                state.guesses.append(text)
            } else if kind == "reveal", state.reveal == nil, move.memberId == starter {
                state.reveal = move.data["reveal"]?.stringValue
            }
        }
        return state
    }

    private func isSolved(_ state: DuoState) -> Bool {
        state.guesses.contains { $0.uppercased() == target }
    }

    private func boardDone(_ state: DuoState) -> Bool {
        isSolved(state) || state.guesses.count >= maxRows
    }

    private func myTurn(_ state: DuoState) -> Bool {
        guard state.commit != nil, state.reveal == nil, !boardDone(state) else { return false }
        return (state.guesses.count.isMultiple(of: 2) ? starter : partner) == appState.memberId
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.wordleduo.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
                advanceCreator()
            }
        }
        .task {
            engine.onError = { [weak appState] in appState?.handleAPIError($0) }
            if engine.session == nil { await engine.resume(api: appState.api) }
            advanceCreator()
            celebrateIfNeeded()
        }
        .onChange(of: engine.session?.state) { _, _ in
            advanceCreator()
            celebrateIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: coupleTint.blend)
                        .padding(LayoutMetrics.s(16))
                }
            } else if session.state == "ended" {
                endScreen
            } else {
                playScreen
            }
        } else {
            wordPartySetup(symbol: "square.grid.3x3.fill",
                           tint: coupleTint.blend,
                           teaser: L10n.t("games.card.wordleduo.teaser"),
                           body: L10n.t("games.duo.rules"),
                           start: start)
        }
    }

    private var playScreen: some View {
        let state = duoState
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                statusLine(state)
                board(state)
                if myTurn(state) {
                    guessField(state)
                } else if state.commit == nil {
                    Text(L10n.t("games.duo.sealing"))
                        .font(Typo.label)
                        .foregroundStyle(Nacht.sekundaer)
                        .nightCard(grain: false)
                } else if !boardDone(state) {
                    GameWaitingHint()
                } else if state.reveal == nil {
                    // Waiting for the creator's automatic verified reveal.
                    GameWaitingHint()
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.keys)
        }
    }

    private func statusLine(_ state: DuoState) -> some View {
        HStack {
            Text(myTurn(state)
                 ? L10n.t("games.duo.yourRow")
                 : L10n.t("games.duo.partnerRow", ["name": appState.partnerName]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Spacer(minLength: 0)
            PillTag(text: "\(state.guesses.count)/\(maxRows)", tint: coupleTint.blend)
        }
        .nightCard(grain: false)
    }

    private func board(_ state: DuoState) -> some View {
        VStack(spacing: 6) {
            ForEach(0..<maxRows, id: \.self) { row in
                boardRow(row, state: state)
            }
        }
        // The shared Tafel — one letter-paper sheet, same as the solo game.
        .paperCard(padding: .compact)
        // VoiceOver reads the whole board exactly like the solo Wordle
        // (WordleView): one element, every filled row spells its letters
        // WITH their verdicts — correct spot, wrong spot, not in the word.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.wordle.a11y.board",
                                   ["n": "\(state.guesses.count)",
                                    "total": "\(maxRows)"]))
        .accessibilityValue(boardA11yValue(state))
    }

    private func boardA11yValue(_ state: DuoState) -> String {
        (0..<state.guesses.count)
            .map { rowA11ySummary($0, state: state) }
            .joined(separator: ". ")
    }

    /// "Row 2: E correct, R wrong spot, …" — the letter-by-letter verdict
    /// summary in the voice the solo Wordle already speaks.
    private func rowA11ySummary(_ row: Int, state: DuoState) -> String {
        let guess = state.guesses[row].uppercased()
        let marks = WordleDaily.score(guess: guess, solution: target)
        let content = zip(Array(guess), marks)
            .map { letter, mark in "\(letter) \(markA11yName(mark))" }
            .joined(separator: ", ")
        return L10n.t("games.wordle.a11y.row", ["n": "\(row + 1)", "content": content])
    }

    private func markA11yName(_ mark: WordleMark) -> String {
        switch mark {
        case .correct: return L10n.t("games.wordle.a11y.mark.correct")
        case .present: return L10n.t("games.wordle.a11y.mark.present")
        case .absent: return L10n.t("games.wordle.a11y.mark.absent")
        }
    }

    @ViewBuilder
    private func boardRow(_ row: Int, state: DuoState) -> some View {
        if row < state.guesses.count {
            let letters = Array(state.guesses[row].uppercased())
            let marks = WordleDaily.score(guess: state.guesses[row].uppercased(),
                                          solution: target)
            HStack(spacing: 6) {
                ForEach(0..<WordleDaily.wordLength, id: \.self) { column in
                    duoTile(letter: column < letters.count ? String(letters[column]) : "",
                            mark: column < marks.count ? marks[column] : nil)
                }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(0..<WordleDaily.wordLength, id: \.self) { _ in
                    duoTile(letter: "", mark: nil)
                }
            }
        }
    }

    private func duoTile(letter: String, mark: WordleMark?) -> some View {
        Text(letter)
            .font(.system(.title3, design: .rounded).weight(.heavy))
            .foregroundStyle(tileLetter(mark))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.control, padding: 6),
                                 style: .continuous)
                    .fill(tileFill(mark))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.control, padding: 6),
                                 style: .continuous)
                    .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth)
            )
    }

    /// The same documented stamp mapping as the solo Wordle: mint/gold
    /// fail ≥4.5:1 on paper, so correct = dark-ink stamp, present =
    /// wax-red pad, absent = faded ink on the sheet (all pinned pairs).
    private func tileFill(_ mark: WordleMark?) -> Color {
        switch mark {
        case .correct: return Tinte.dunkel
        case .present: return Wachs.rot
        case .absent: return Papier.innenFill
        case nil: return Papier.innenFill
        }
    }

    private func tileLetter(_ mark: WordleMark?) -> Color {
        switch mark {
        case .correct, .present: return Papier.brief
        case .absent: return Tinte.tertiaer
        case nil: return Tinte.dunkel
        }
    }

    private func guessField(_ state: DuoState) -> some View {
        VStack(spacing: Space.s) {
            HStack(spacing: 10) {
                TextField(L10n.t("games.duo.placeholder"), text: $guess)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Theme.innerFill)
                    )
                Button {
                    submit(state)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(.title2, design: .rounded))
                }
                .accessibilityLabel(L10n.t("games.wordle.a11y.submit"))
                .disabled(sending || cleanGuess.count != WordleDaily.wordLength)
            }
            if rejectedGuess {
                Text(L10n.t("games.wordle.notInList"))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.energyRed)
            }
        }
    }

    private var cleanGuess: String {
        guess.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var endScreen: some View {
        let state = duoState
        let result = session?.result
        let solved = result?["solved"]?.boolValue ?? isSolved(state)
        let rows = result?["rows"]?.intValue ?? state.guesses.count
        let word = result?["target"]?.stringValue ?? state.reveal ?? target
        let void = engine.moves(kind: "reveal").first?.data["verified"]?.boolValue == false
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Image(systemName: void ? "exclamationmark.triangle.fill"
                      : (solved ? "checkmark.seal.fill" : "heart.circle.fill"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(void ? Licht.glut : (solved ? Licht.lampengold : coupleTint.blend))
                    .background(solved && !void ? VerdictLampenschein() : nil)
                    .accessibilityHidden(true)
                Text(word.uppercased())
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                Text(void
                     ? L10n.t("games.duo.void")
                     : (solved
                        ? L10n.t("games.duo.solved", ["n": "\(rows)"])
                        : L10n.t("games.duo.unsolved", ["word": word.uppercased()])))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(24))
            .contentColumn(.reading)
        }
    }

    // MARK: Actions

    private func start() {
        Task {
            let payload = JSONValue.object([
                "dateKey": .string(SharedDates.todayKey()),
                "lang": .string(L10n.lang),
            ])
            if await engine.create(api: appState.api, type: .wordleduo, payload: payload) {
                advanceCreator()
            }
        }
    }

    private func submit(_ state: DuoState) {
        let candidate = cleanGuess
        guard candidate.count == WordleDaily.wordLength, myTurn(state), !sending else { return }
        guard WordleDaily.dictionary(lang: lang).contains(candidate) else {
            rejectedGuess = true
            Haptics.shared.tap()
            return
        }
        rejectedGuess = false
        sending = true
        Task {
            let ok = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("guess"),
                "row": .number(Double(state.guesses.count)),
                "text": .string(candidate),
            ]))
            if ok {
                guess = ""
                Haptics.shared.tap()
                SoundEngine.shared.play(.pop)
            }
            sending = false
            advanceCreator()
        }
    }

    /// The creator drives the two automatic protocol steps: sealing the
    /// derived target once the session turns active, and the verified
    /// reveal once the board is solved or exhausted (hangman pattern).
    private func advanceCreator() {
        guard let session, session.state == "active",
              appState.memberId == starter, !sending else { return }
        let state = duoState
        if state.commit == nil {
            let secret = loadSecret(gameId: session.id) ?? {
                let fresh = (word: target, salt: CommitReveal.newSalt())
                saveSecret(word: fresh.word, salt: fresh.salt, gameId: session.id)
                return fresh
            }()
            sending = true
            Task {
                _ = await engine.sendMove(api: appState.api, data: .object([
                    "kind": .string("target"),
                    "commit": .string(CommitReveal.commit(secret: secret.word, salt: secret.salt)),
                ]))
                sending = false
            }
        } else if state.reveal == nil, boardDone(state), !state.guesses.isEmpty,
                  let secret = loadSecret(gameId: session.id) {
            sending = true
            Task {
                _ = await engine.sendMove(api: appState.api, data: .object([
                    "kind": .string("reveal"),
                    "reveal": .string(secret.word),
                    "salt": .string(secret.salt),
                ]))
                sending = false
                UserDefaults.standard.removeObject(forKey: secretKey(session.id))
            }
        }
    }

    private func celebrateIfNeeded() {
        guard session?.state == "ended", !celebrated else { return }
        celebrated = true
        if session?.result?["solved"]?.boolValue == true {
            GameEndCelebration.win(theme: .hearts)
        } else {
            GameEndCelebration.tie()
        }
    }

    private func secretKey(_ gameId: String) -> String { "sooodreamy.wordleduo.secret.\(gameId)" }

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

// MARK: - Rock, Paper, Scissors — commit-reveal best-of duel

struct RockPaperScissorsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false
    /// Rounds whose verdict VoiceOver already spoke — primed on resume so
    /// reopening a running match never re-announces old rounds.
    @State private var announcedRounds = 0

    private static let choices = ["rock", "paper", "scissors"]
    private static let beats = ["rock": "scissors", "paper": "rock", "scissors": "paper"]

    private var session: GameSession? {
        guard engine.session?.kind == .rps else { return nil }
        return engine.session
    }
    private var target: Int { engine.payloadInt("target", default: 4) }
    private var memberIds: [String] {
        appState.couple?.members.map(\.id) ?? []
    }

    /// Mirror of the server's `rpsState` reducer.
    private struct RpsRound {
        var commits: [String: String] = [:]
        var reveals: [String: String] = [:]
    }
    private struct RpsState {
        var rounds: [RpsRound] = []
        var scores: [String: Int] = [:]
        var winner: String?
        var current = 0
    }

    private var rpsState: RpsState {
        var state = RpsState()
        let members = memberIds
        for move in engine.orderedMoves {
            guard let round = move.data["round"]?.intValue, round >= 0 else { continue }
            while state.rounds.count <= round {
                state.rounds.append(RpsRound())
            }
            if move.data["kind"]?.stringValue == "commit",
               state.rounds[round].commits[move.memberId] == nil {
                state.rounds[round].commits[move.memberId] = move.data["commit"]?.stringValue
            } else if move.data["kind"]?.stringValue == "reveal",
                      state.rounds[round].reveals[move.memberId] == nil {
                state.rounds[round].reveals[move.memberId] = move.data["reveal"]?.stringValue
            }
        }
        for id in members { state.scores[id] = 0 }
        for (index, round) in state.rounds.enumerated() {
            guard members.count == 2,
                  members.allSatisfy({ round.reveals[$0] != nil }) else { break }
            let a = members[0], b = members[1]
            if round.reveals[a] != round.reveals[b] {
                let roundWinner = Self.beats[round.reveals[a] ?? ""] == round.reveals[b] ? a : b
                state.scores[roundWinner, default: 0] += 1
                if state.winner == nil, state.scores[roundWinner, default: 0] >= target {
                    state.winner = roundWinner
                }
            }
            state.current = index + 1
        }
        return state
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.rps.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
                advanceReveal()
                announceRoundIfNeeded()
            }
        }
        .task {
            engine.onError = { [weak appState] in appState?.handleAPIError($0) }
            if engine.session == nil { await engine.resume(api: appState.api) }
            // Prime the announcement cursor: rounds resolved before this
            // screen opened are visible history, not news to speak.
            announcedRounds = rpsState.current
            advanceReveal()
            celebrateIfNeeded()
        }
        .onChange(of: engine.session?.state) { _, _ in
            advanceReveal()
            celebrateIfNeeded()
        }
    }

    /// VoiceOver hears each resolved round the moment sighted eyes see the
    /// verdict line — the same announcement channel GameEndCelebration
    /// uses for match endings. The final round stays silent: the end
    /// ceremony's win/loss announcement already carries that news.
    private func announceRoundIfNeeded() {
        let state = rpsState
        guard state.current > announcedRounds else { return }
        announcedRounds = state.current
        guard state.winner == nil, let verdict = lastVerdict(state) else { return }
        GamesA11y.announce(verdict)
    }

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: Licht.lampengold)
                        .padding(LayoutMetrics.s(16))
                }
            } else if session.state == "ended" {
                endScreen
            } else {
                playScreen
            }
        } else {
            wordPartySetup(symbol: "scissors",
                           tint: coupleTint.blend,
                           teaser: L10n.t("games.card.rps.teaser"),
                           body: L10n.t("games.rps.rules"),
                           start: start)
        }
    }

    private var playScreen: some View {
        let state = rpsState
        let myId = appState.memberId ?? ""
        let round = state.rounds.indices.contains(state.current)
            ? state.rounds[state.current] : RpsRound()
        let iCommitted = round.commits[myId] != nil
        let bothCommitted = memberIds.count == 2
            && memberIds.allSatisfy { round.commits[$0] != nil }
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader(state)
                if let verdict = lastVerdict(state) {
                    Text(verdict)
                        .font(Typo.label)
                        .foregroundStyle(Licht.lampengold)
                }
                if !iCommitted {
                    choiceButtons(state)
                } else if !bothCommitted {
                    Text(L10n.t("games.rps.sealed", ["name": appState.partnerName]))
                        .font(Typo.label)
                        .foregroundStyle(Nacht.sekundaer)
                        .nightCard(grain: false)
                } else {
                    Text(L10n.t("games.rps.revealing"))
                        .font(Typo.label)
                        .foregroundStyle(Nacht.sekundaer)
                        .nightCard(grain: false)
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func scoreHeader(_ state: RpsState) -> some View {
        let myId = appState.memberId ?? ""
        let mine = state.scores[myId] ?? 0
        let theirs = state.scores.first { $0.key != myId }?.value ?? 0
        return VStack(spacing: Space.s) {
            HStack(spacing: LayoutMetrics.s(14)) {
                scoreColumn(member: appState.me, points: mine)
                Text(":")
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Nacht.tertiaer)
                scoreColumn(member: appState.partner, points: theirs)
            }
            HStack(spacing: Space.s) {
                PillTag(text: L10n.t("games.rps.round", ["n": "\(state.current + 1)"]))
                PillTag(text: L10n.t("games.rps.target", ["n": "\(target)"]),
                        tint: coupleTint.blend)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    private func scoreColumn(member: Member?, points: Int) -> some View {
        VStack(spacing: 4) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color,
                            size: LayoutMetrics.s(36))
            Text("\(points)")
                .font(Typo.number)
                .foregroundStyle(Papier.aufNacht)
        }
        .frame(maxWidth: .infinity)
    }

    /// Verdict of the last fully revealed round, if any.
    private func lastVerdict(_ state: RpsState) -> String? {
        guard state.current > 0 else { return nil }
        let round = state.rounds[state.current - 1]
        let myId = appState.memberId ?? ""
        guard let mine = round.reveals[myId],
              let theirs = round.reveals.first(where: { $0.key != myId })?.value else {
            return nil
        }
        if mine == theirs { return L10n.t("games.rps.round.tie") }
        let iWon = Self.beats[mine] == theirs
        return iWon
            ? L10n.t("games.rps.round.you")
            : L10n.t("games.rps.round.partner", ["name": appState.partnerName])
    }

    private func choiceButtons(_ state: RpsState) -> some View {
        VStack(spacing: Space.m) {
            Text(L10n.t("games.rps.choose"))
                .font(Typo.label)
                .foregroundStyle(Tinte.dunkel)
            HStack(spacing: Space.m) {
                choiceButton("rock", symbol: "mountain.2.fill",
                             label: L10n.t("games.rps.rock"), round: state.current)
                choiceButton("paper", symbol: "doc.fill",
                             label: L10n.t("games.rps.paper"), round: state.current)
                choiceButton("scissors", symbol: "scissors",
                             label: L10n.t("games.rps.scissors"), round: state.current)
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard()
    }

    private func choiceButton(_ choice: String, symbol: String, label: String,
                              round: Int) -> some View {
        Button {
            commit(choice, round: round)
        } label: {
            VStack(spacing: Space.s) {
                Image(systemName: symbol)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.tinte)
                Text(label)
                    .font(Typo.caption)
                    .foregroundStyle(Tinte.dunkel)
            }
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(84))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.innenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .disabled(sending)
        .accessibilityLabel(label)
    }

    private var endScreen: some View {
        let winner = session?.result?["winner"]?.stringValue
        let iWon = winner == appState.memberId
        let scores = session?.result?["scores"]?.objectValue ?? [:]
        let mine = appState.memberId.flatMap { scores[$0]?.intValue } ?? 0
        let theirs = scores.first { $0.key != appState.memberId }?.value.intValue ?? 0
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Image(systemName: iWon ? "trophy.fill" : "heart.circle.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iWon ? Licht.lampengold : coupleTint.blend)
                    .background(iWon ? VerdictLampenschein() : nil)
                    .accessibilityHidden(true)
                Text(iWon
                     ? L10n.t("games.rps.win.you")
                     : L10n.t("games.rps.win.partner", ["name": appState.partnerName]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text("\(mine) : \(theirs)")
                    .font(Typo.number)
                    .foregroundStyle(Nacht.sekundaer)
                Button(L10n.t("games.rematch")) { start() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(24))
            .contentColumn(.reading)
        }
        .task {
            if let id = session?.id {
                UserDefaults.standard.removeObject(forKey: secretKey(id))
            }
        }
    }

    // MARK: Actions

    private func start() {
        Task {
            _ = await engine.create(api: appState.api, type: .rps, payload: .object([:]))
        }
    }

    private func commit(_ choice: String, round: Int) {
        guard let gameId = session?.id, !sending else { return }
        let salt = CommitReveal.newSalt()
        saveChoice(choice: choice, salt: salt, round: round, gameId: gameId)
        sending = true
        Task {
            let ok = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("commit"),
                "round": .number(Double(round)),
                "commit": .string(CommitReveal.commit(secret: choice, salt: salt)),
            ]))
            if ok {
                Haptics.shared.tap()
                SoundEngine.shared.play(.pop)
            }
            sending = false
            advanceReveal()
        }
    }

    /// Once both commitments of the active round exist, every member
    /// reveals automatically — the saved choice + salt open the seal.
    private func advanceReveal() {
        guard let session, session.state == "active", !sending,
              let myId = appState.memberId else { return }
        let state = rpsState
        guard state.winner == nil,
              state.rounds.indices.contains(state.current) else { return }
        let round = state.rounds[state.current]
        guard memberIds.count == 2,
              memberIds.allSatisfy({ round.commits[$0] != nil }),
              round.reveals[myId] == nil,
              let saved = loadChoice(gameId: session.id), saved.round == state.current else {
            return
        }
        sending = true
        Task {
            _ = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("reveal"),
                "round": .number(Double(state.current)),
                "reveal": .string(saved.choice),
                "salt": .string(saved.salt),
            ]))
            sending = false
            // My own reveal may be the one that completes the round.
            announceRoundIfNeeded()
        }
    }

    private func celebrateIfNeeded() {
        guard session?.state == "ended", !celebrated else { return }
        celebrated = true
        if session?.result?["winner"]?.stringValue == appState.memberId {
            GameEndCelebration.win()
        } else {
            GameEndCelebration.loss()
        }
    }

    private func secretKey(_ gameId: String) -> String { "sooodreamy.rps.secret.\(gameId)" }

    private func saveChoice(choice: String, salt: String, round: Int, gameId: String) {
        UserDefaults.standard.set(["choice": choice, "salt": salt, "round": "\(round)"],
                                  forKey: secretKey(gameId))
    }

    private func loadChoice(gameId: String) -> (choice: String, salt: String, round: Int)? {
        guard let value = UserDefaults.standard.dictionary(forKey: secretKey(gameId)),
              let choice = value["choice"] as? String,
              let salt = value["salt"] as? String,
              let round = (value["round"] as? String).flatMap(Int.init) else { return nil }
        return (choice, salt, round)
    }
}

// MARK: - Story Relay — cooperative continuation story

struct StoryRelayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let engine: GameEngine

    @State private var sentence = ""
    @State private var sending = false
    @State private var celebrated = false
    @State private var genre = 0
    @State private var classicLength = false

    private static let genreCount = 8
    private static let twistCount = 6

    private var session: GameSession? {
        guard engine.session?.kind == .story else { return nil }
        return engine.session
    }
    private var starter: String { session?.createdBy ?? "" }
    private var partner: String {
        appState.couple?.members.first { $0.id != starter }?.id ?? ""
    }
    private var total: Int { engine.payloadInt("sentences", default: 20) }
    private var sessionGenre: Int { engine.payloadInt("genre", default: 0) }

    /// Mirror of the server's `storyState` reducer.
    private var sentences: [(memberId: String, text: String)] {
        var collected: [(String, String)] = []
        for move in engine.orderedMoves {
            guard move.data["kind"]?.stringValue == "sentence",
                  move.data["index"]?.intValue == collected.count,
                  let text = move.data["text"]?.stringValue,
                  move.memberId == (collected.count.isMultiple(of: 2) ? starter : partner)
            else { continue }
            collected.append((move.memberId, text))
        }
        return collected
    }

    private var myTurn: Bool {
        let count = sentences.count
        guard count < total else { return false }
        return (count.isMultiple(of: 2) ? starter : partner) == appState.memberId
    }

    /// Two deterministic twist positions derived from the server seed —
    /// identical on both phones, never the first or the final sentence.
    private var twistIndexes: Set<Int> {
        guard total >= 8 else { return [] }
        let seed = engine.seed
        let half = total / 2
        let first = 1 + (seed % (half - 1))
        let second = half + ((seed / 7) % (half - 1))
        return [first, second]
    }

    private func twistPrompt(for index: Int) -> String {
        L10n.t("games.story.twist.\((engine.seed + index) % Self.twistCount)")
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.story.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
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
                ScrollView {
                    GameLobbyView(engine: engine, accent: coupleTint.blend)
                        .padding(LayoutMetrics.s(16))
                }
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
                Image(systemName: "book.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.story.rules"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                SectionHeader(title: L10n.t("games.story.genre.title"))
                genrePicker
                SectionHeader(title: L10n.t("games.story.length.title"))
                lengthPicker
                Button(L10n.t("games.start")) { start() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var genrePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.s(140)), spacing: 8)],
                  spacing: 8) {
            ForEach(0..<Self.genreCount, id: \.self) { index in
                selectableChip(text: L10n.t("games.story.genre.\(index)"),
                               selected: genre == index) {
                    genre = index
                }
            }
        }
    }

    private var lengthPicker: some View {
        HStack(spacing: Space.s) {
            selectableChip(text: L10n.t("games.story.length.short"),
                           selected: !classicLength) {
                classicLength = false
            }
            selectableChip(text: L10n.t("games.story.length.classic"),
                           selected: classicLength) {
                classicLength = true
            }
        }
    }

    private func selectableChip(text: String, selected: Bool,
                                action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.shared.tap()
        } label: {
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(selected ? coupleTint.onBlend : Papier.aufNacht)
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(selected ? coupleTint.blend : Papier.nachtInnenFill))
                .overlay(Capsule().strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var playScreen: some View {
        let collected = sentences
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(myTurn
                             ? L10n.t("games.story.yourTurn")
                             : L10n.t("games.story.partnerTurn", ["name": appState.partnerName]))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        Text(L10n.t("games.story.progress",
                                    ["n": "\(collected.count + 1)", "total": "\(total)"]))
                            .font(Typo.caption)
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    Spacer(minLength: 0)
                    PillTag(text: L10n.t("games.story.genre.\(sessionGenre)"),
                            tint: coupleTint.blend)
                }
                .nightCard(grain: false)

                // The growing story lives on ONE sheet of paper — the
                // couple's own sentences in the written-by-you voice.
                if !collected.isEmpty {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(collected.enumerated()), id: \.offset) { _, entry in
                            sentenceRow(entry)
                        }
                    }
                    .paperCard()
                }

                if myTurn {
                    if twistIndexes.contains(collected.count) {
                        twistCard(index: collected.count)
                    }
                    inputRow(nextIndex: collected.count)
                } else {
                    GameWaitingHint()
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func sentenceRow(_ entry: (memberId: String, text: String)) -> some View {
        let mine = entry.memberId == appState.memberId
        return HStack {
            if mine { Spacer(minLength: LayoutMetrics.s(32)) }
            Text(entry.text)
                // Serif ON paper — these sentences are written by the two.
                .font(Typo.voice)
                .foregroundStyle(Tinte.dunkel)
                .padding(Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(mine ? coupleTint.tinte.opacity(0.14) : Papier.innenFill)
                )
                .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: LayoutMetrics.s(32)) }
        }
        // Sighted eyes read authorship from the bubble side — VoiceOver
        // gets the author spoken with every contribution.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.story.a11y.sentence",
                                   ["name": mine ? L10n.t("common.you")
                                                 : appState.partnerName,
                                    "text": entry.text]))
    }

    private func twistCard(index: Int) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: "sparkles")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Licht.glut)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                // The ember carries the twist on the night note.
                Text(L10n.t("games.story.twist.kicker"))
                    .font(Typo.caption)
                    .foregroundStyle(Licht.glut)
                Text(twistPrompt(for: index))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
    }

    private func inputRow(nextIndex: Int) -> some View {
        HStack(spacing: 10) {
            TextField(L10n.t("games.story.placeholder"), text: $sentence, axis: .vertical)
                .lineLimit(1...4)
                .padding(Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Theme.innerFill)
                )
            Button {
                submit(nextIndex: nextIndex)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(.title2, design: .rounded))
            }
            // The button SENDS — "your turn" is the status line's job.
            .accessibilityLabel(L10n.t("games.story.a11y.send"))
            .disabled(sending || cleanSentence.isEmpty)
        }
    }

    private var cleanSentence: String {
        String(sentence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private var endScreen: some View {
        let collected = sentences
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Image(systemName: "book.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(L10n.t("games.story.done", ["n": "\(collected.count)"]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                PillTag(text: L10n.t("games.story.genre.\(sessionGenre)"),
                        tint: coupleTint.blend)
                // The finished story is the prize — the couple's own words
                // in the voice type reserved for what the partners wrote,
                // serif on the paper sheet it was written on.
                Text(collected.map(\.text).joined(separator: " "))
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .paperCard()
                Button(L10n.t("games.rematch")) { engine.adopt(nil) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(24))
            .contentColumn(.reading)
        }
    }

    // MARK: Actions

    private func start() {
        Task {
            let payload = JSONValue.object([
                "genre": .number(Double(genre)),
                "sentences": .number(Double(classicLength ? 20 : 12)),
                "lang": .string(L10n.lang),
            ])
            _ = await engine.create(api: appState.api, type: .story, payload: payload)
        }
    }

    private func submit(nextIndex: Int) {
        let text = cleanSentence
        guard !text.isEmpty, myTurn, !sending else { return }
        sending = true
        Task {
            let ok = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("sentence"),
                "index": .number(Double(nextIndex)),
                "text": .string(text),
            ]))
            if ok {
                sentence = ""
                Haptics.shared.tap()
                SoundEngine.shared.play(.pop)
            }
            sending = false
        }
    }

    private func celebrateIfNeeded() {
        guard session?.state == "ended", !celebrated else { return }
        celebrated = true
        // Purely cooperative — the shared tie ceremony, never a winner.
        GameEndCelebration.tie()
    }
}

// MARK: - Shared setup shell (mirrors the WaveGamesViews helper)

private func wordPartySetup(
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
