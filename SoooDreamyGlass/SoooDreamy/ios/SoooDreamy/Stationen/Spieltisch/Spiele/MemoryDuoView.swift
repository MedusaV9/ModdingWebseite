import SwiftUI
import Combine

/// Memory-Duo live — 36 hidden cards, 18 pairs, and the deck lives ONLY on
/// the server (the seed is stripped from every client view): a card's face
/// arrives exclusively inside an accepted `{kind:"flip", index}` move.
/// Both clients reduce the identical tableau from the flip list via
/// `MemoryDuo.reduce` (Content/BoardGameRules.swift). What was flipped once
/// stays visible to BOTH as a dimmed motif — the couple's shared memory is
/// part of the game. A match scores, keeps the turn, and the server ends
/// the match with the last pair.
///
/// Faces map deterministically to SF-Symbol motifs on token tints
/// (`MemoryMotifs`) — no emoji wallpaper.
struct MemoryDuoView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false
    /// Cards held face-up for the staged two-card reveal: a resolved pair
    /// stays FULLY visible for a beat (mismatch ~0.8s, match shorter —
    /// BoardGameFeedbackRules) before settling into ghost/matched state,
    /// so the second face is actually readable before it flips back.
    @State private var stagedReveal: Set<Int> = []
    /// „Klassisch": seen motifs do NOT stay visible as dimmed ghosts — a
    /// pure memory duel. Local presentation choice per device; the shared
    /// server state is untouched, so each member picks their own style.
    @AppStorage("sooodreamy.memoryduo.classic") private var classicMode = false

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .memoryduo, finished: finished) {
            BoardDuelSetupCard(symbol: "square.on.square", kind: .memoryduo,
                               bodyKey: "games.memoryduo.setup.body",
                               busy: engine.busy, start: startGame) {
                classicToggle
            }
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: flips.count) { old, new in
            guard new > old else { return }
            stageLatestReveal()
            reactToLatestFlip()
        }
        .onChange(of: finished) { _, isDone in
            if isDone { celebrate() }
        }
        .onAppear {
            if finished { celebrate() }
        }
    }

    // MARK: Derived state

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .memoryduo else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var gridSize: Int { engine.payloadInt("size", default: 6) }
    private var cardCount: Int { engine.payloadInt("pairs", default: 18) * 2 }

    private var flips: [(memberId: String, index: Int, face: Int)] {
        engine.moves(kind: "flip").compactMap { move in
            guard let index = move.data["index"]?.intValue,
                  let face = move.data["face"]?.intValue else { return nil }
            return (move.memberId, index, face)
        }
    }

    private var boardState: MemoryDuoState {
        MemoryDuo.reduce(flips: flips, cards: cardCount,
                         starter: roster.starterId, partner: roster.otherId)
    }

    private var finished: Bool {
        guard let session, session.state == "active" || session.state == "ended" else { return false }
        return session.state == "ended" || boardState.complete
    }

    private var myTurn: Bool { boardState.turn == roster.myId && !finished }

    private var opponentId: String {
        roster.myId == roster.starterId ? roster.otherId : roster.starterId
    }

    /// A match keeps the turn — the mover of the last flip is still up.
    private var extraTurnRunning: Bool {
        guard let last = flips.last else { return false }
        return !finished && boardState.open == nil && last.memberId == boardState.turn
    }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "memoryduo") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
        } board: {
            boardView
        } footer: {
            BoardColorLegend(entries: legendEntries)
            HStack(spacing: Space.s) {
                Image(systemName: classicMode ? "eye.slash.fill" : "eye.fill")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Text(L10n.t(classicMode ? "games.memoryduo.classic.hint"
                                        : "games.memoryduo.known"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
                // Presentation only — flip it mid-match, your device, your
                // rules. (The partner keeps their own choice.)
                Toggle(L10n.t("games.memoryduo.classic"), isOn: $classicMode)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(coupleTint.blend)
                    .accessibilityLabel(L10n.t("games.memoryduo.classic"))
            }
            if !myTurn {
                GameWaitingHint()
            }
        }
    }

    /// Setup-card option: start into the classic (pure-memory) style.
    /// Sits in the night setup card since P2-C — night inks, blend tint.
    private var classicToggle: some View {
        VStack(spacing: Space.xs) {
            Toggle(L10n.t("games.memoryduo.classic"), isOn: $classicMode)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .tint(coupleTint.blend)
            Text(L10n.t("games.memoryduo.classic.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var turnLine: String {
        if extraTurnRunning {
            return myTurn ? L10n.t("games.board.extraTurn.you")
                          : L10n.t("games.board.extraTurn.partner",
                                   ["name": roster.name(of: boardState.turn)])
        }
        return myTurn ? L10n.t("games.memory.yourTurn")
                      : L10n.t("games.memory.partnerTurn", ["name": roster.name(of: boardState.turn)])
    }

    private var legendEntries: [BoardColorLegend.Entry] {
        [roster.myId, opponentId].map { id in
            BoardColorLegend.Entry(
                id: id,
                color: roster.ink(of: id),
                label: id == roster.myId ? L10n.t("games.board.yourColor") : roster.name(of: id),
                value: "\(boardState.scores[id] ?? 0)"
            )
        }
    }

    private var boardView: some View {
        let state = boardState
        return VStack(spacing: Space.xs) {
            ForEach(0..<gridSize, id: \.self) { row in
                HStack(spacing: Space.xs) {
                    ForEach(0..<gridSize, id: \.self) { col in
                        let index = row * gridSize + col
                        if index < cardCount {
                            cardView(state: state, index: index)
                        }
                    }
                }
            }
        }
        // Hardware keyboard: arrows move the shared board cursor,
        // Space/Return flips through the game's own guarded path.
        .boardKeyCursor(memoryLattice)
        .padding(Space.s)
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.memoryduo.a11y.board"))
        .accessibilityValue(L10n.t("games.memoryduo.a11y.value", [
            "mine": "\(state.scores[roster.myId] ?? 0)",
            "name": appState.partnerName,
            "theirs": "\(state.scores[opponentId] ?? 0)",
        ]))
    }

    /// Keyboard lattice: the uniform card grid; `contains` skips the slots
    /// a partial last row leaves empty.
    private var memoryLattice: BoardKeyLattice {
        .grid(columns: gridSize, rows: gridSize, spacing: Space.xs,
              contains: { column, row in row * gridSize + column < cardCount },
              activate: { column, row in
                  flip(index: row * gridSize + column)
              })
    }

    private func cardView(state: MemoryDuoState, index: Int) -> some View {
        let face = state.faces[index]
        let matchedBy = state.matched[index]
        // Staged reveal: a just-resolved pair stays face-up until the
        // pause ends — only then does the mismatch flip back.
        let isOpen = state.open == index || stagedReveal.contains(index)
        let showsGhost = face != nil && !isOpen && matchedBy == nil && !classicMode
        let faceUp = isOpen || matchedBy != nil || showsGhost
        return Button {
            flip(index: index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(cardFill(face: face, matchedBy: matchedBy, isOpen: isOpen))
                // A face learned once stays visible to BOTH members as a
                // dimmed ghost — unless this device plays „Klassisch" and
                // keeps every unmatched motif covered.
                if let face, faceUp {
                    Image(systemName: MemoryMotifs.symbol(for: face))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(MemoryMotifs.tint(for: face))
                        .opacity(isOpen ? 1 : (matchedBy != nil ? 0.45 : 0.35))
                        // Un-mirror the face on the rotated card.
                        .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(cardStroke(matchedBy: matchedBy, isOpen: isOpen),
                                  lineWidth: isOpen || matchedBy != nil ? 2 : Theme.hairlineWidth)
            )
            // The staged flip: face-down cards sit at 0°, revealing turns
            // the card over (the face above is pre-mirrored back).
            .rotation3DEffect(.degrees(faceUp ? 180 : 0),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .animation(reduceMotion ? nil : Theme.Motion.playful, value: faceUp)
            .animation(reduceMotion ? nil : Theme.Motion.playful, value: isOpen)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: matchedBy)
        }
        .buttonStyle(.plain)
        .disabled(!myTurn || sending || matchedBy != nil || isOpen || !stagedReveal.isEmpty)
        .accessibilityLabel(cardA11yLabel(state: state, index: index))
    }

    /// Card materials on the paper plan: won pairs wear the winner's ink
    /// as a wash, open cards the couple ink — face-down backs stay the
    /// matte inner fill (the one legal fill inside a paper card).
    private func cardFill(face: Int?, matchedBy: String?, isOpen: Bool) -> Color {
        if let matchedBy {
            return roster.ink(of: matchedBy).opacity(0.16)
        }
        if isOpen {
            return coupleTint.tinte.opacity(0.18)
        }
        return Papier.innenFill
    }

    private func cardStroke(matchedBy: String?, isOpen: Bool) -> Color {
        if let matchedBy {
            return roster.ink(of: matchedBy)
        }
        return isOpen ? coupleTint.tinte : Papier.kante
    }

    private func cardA11yLabel(state: MemoryDuoState, index: Int) -> String {
        let n = "\(index + 1)"
        if let owner = state.matched[index] {
            return L10n.t("games.memoryduo.a11y.matched", ["n": n, "name": roster.name(of: owner)])
        }
        if state.open == index || stagedReveal.contains(index),
           let face = state.faces[index] {
            return L10n.t("games.memoryduo.a11y.open", ["n": n, "face": "\(face + 1)"])
        }
        // The label follows the VISUAL mode (FXD-2 #6): „Klassisch" keeps
        // every unmatched motif covered, so VoiceOver must not leak what
        // sighted eyes cannot see — a covered card is just its position.
        if !classicMode, let face = state.faces[index] {
            return L10n.t("games.memoryduo.a11y.known", ["n": n, "face": "\(face + 1)"])
        }
        if classicMode {
            return L10n.t("games.memoryduo.a11y.hiddenAt",
                          ["row": "\(index / gridSize + 1)",
                           "col": "\(index % gridSize + 1)"])
        }
        return L10n.t("games.memoryduo.a11y.hidden", ["n": n])
    }

    // MARK: Interaction

    private func flip(index: Int) {
        guard myTurn, !sending, boardState.matched[index] == nil,
              boardState.open != index else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("flip"),
                "index": .number(Double(index)),
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                // The server's accepted move (with the injected face) is
                // already appended — judge the outcome from the new state.
                let state = boardState
                if state.open == index {
                    CueKit.play(.chip)
                } else if state.matched[index] == roster.myId {
                    CueKit.play(.success)
                    GamesA11y.announce(L10n.t("games.memory.match"))
                } else {
                    CueKit.play(.click)
                }
            }
            sending = false
        }
    }

    /// After the flip that RESOLVES a pair, hold both cards face-up for a
    /// readable beat: ~0.8s on a mismatch (long enough to actually study
    /// the second face), shorter on a match before it settles as won.
    private func stageLatestReveal() {
        let state = boardState
        guard state.open == nil, flips.count >= 2 else { return }
        let first = flips[flips.count - 2]
        let second = flips[flips.count - 1]
        guard first.memberId == second.memberId, first.index != second.index else { return }
        let matched = state.matched[second.index] != nil
        let pair: Set<Int> = [first.index, second.index]
        stagedReveal = pair
        let pause = matched ? BoardGameFeedback.memoryMatchPause
                            : BoardGameFeedback.memoryMismatchPause
        Task {
            try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            if stagedReveal == pair { stagedReveal = [] }
        }
    }

    private func reactToLatestFlip() {
        guard let last = flips.last, last.memberId != roster.myId else { return }
        let state = boardState
        if state.matched[last.index] == last.memberId {
            // The partner completed a pair and goes again.
            GamesA11y.announce(L10n.t("games.board.extraTurn.partner",
                                      ["name": roster.name(of: last.memberId)]))
        } else if state.open == nil {
            // Second flip without a match — the turn passes.
            GamesA11y.announce(L10n.t("games.memory.noMatch",
                                      ["name": roster.name(of: state.turn)]))
        } else {
            GamesA11y.announce(L10n.t("games.memoryduo.a11y.partnerFlipped",
                                      ["name": roster.name(of: last.memberId),
                                       "n": "\(last.index + 1)"]))
        }
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .memoryduo,
                                   payload: GameEngine.makePayload()) {
                CueKit.play(.chip)
            }
        }
    }

    private func resetLocalState() {
        sending = false
        celebrated = false
        stagedReveal = []
    }

    private func celebrate() {
        guard session != nil, !celebrated else { return }
        celebrated = true
        let winner = session?.result?["winner"]?.stringValue ?? boardState.winner
        if winner == roster.myId {
            GameEndCelebration.win()
        } else if winner != nil {
            GameEndCelebration.loss()
        } else {
            GameEndCelebration.tie()
        }
    }

    // MARK: End screen

    private var endScreen: some View {
        let winner = session?.result?["winner"]?.stringValue ?? boardState.winner
        return BoardDuelEndPanel(
            symbol: winner == nil ? "equal.circle.fill" : "trophy.fill",
            headline: endLine(winner: winner),
            detail: L10n.t("games.board.finalScore", [
                "a": "\(boardState.scores[roster.myId] ?? 0)",
                "b": "\(boardState.scores[opponentId] ?? 0)",
            ]),
            busy: engine.busy,
            rematch: startGame
        ) {
            boardView
        }
    }

    private func endLine(winner: String?) -> String {
        guard let winner else { return L10n.t("games.memory.tie") }
        return winner == roster.myId
            ? L10n.t("games.memory.win.you")
            : L10n.t("games.memory.win.partner", ["name": roster.name(of: winner)])
    }
}
