import SwiftUI
import Combine

/// Gomoku live — 15×15, alternating stones, and EXACTLY five in a row wins
/// (an overline of six or more does not). Both clients reduce the identical
/// board from the ordered `{kind:"place", index}` list via `Gomoku.reduce`
/// (Content/BoardGameRules.swift); the winning-run highlight uses the SAME
/// exact-five rule as the server, so an overline never lights up. The
/// server ends the match on the decisive stone.
struct GomokuView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .gomoku, finished: finished) {
            BoardDuelSetupCard(symbol: "circle.grid.3x3.fill", kind: .gomoku,
                               bodyKey: "games.gomoku.setup.body",
                               busy: engine.busy, start: startGame)
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: placements.count) { old, new in
            guard new > old else { return }
            announceLatestMove()
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
        guard let current = engine.session, current.kind == .gomoku else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var placements: [(memberId: String, index: Int)] {
        engine.moves(kind: "place").compactMap { move in
            guard let index = move.data["index"]?.intValue else { return nil }
            return (move.memberId, index)
        }
    }

    private var boardState: GomokuState {
        Gomoku.reduce(placements: placements, starter: roster.starterId, partner: roster.otherId)
    }

    private var finished: Bool {
        guard let session, session.state == "active" || session.state == "ended" else { return false }
        return session.state == "ended" || boardState.winner != nil || boardState.draw
    }

    private var myTurn: Bool { boardState.turn == roster.myId && !finished }

    private var opponentId: String {
        roster.myId == roster.starterId ? roster.otherId : roster.starterId
    }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "gomoku") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
        } board: {
            boardView
        } footer: {
            BoardColorLegend(entries: legendEntries)
            Text(L10n.t("games.gomoku.exactFive"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !myTurn {
                GameWaitingHint()
            }
        }
    }

    private var turnLine: String {
        myTurn ? L10n.t("games.board.yourTurn")
               : L10n.t("games.board.partnerTurn", ["name": roster.name(of: boardState.turn)])
    }

    private var legendEntries: [BoardColorLegend.Entry] {
        [roster.myId, opponentId].map { id in
            BoardColorLegend.Entry(
                id: id,
                color: roster.ink(of: id),
                label: id == roster.myId ? L10n.t("games.board.yourColor") : roster.name(of: id),
                value: nil
            )
        }
    }

    private var boardView: some View {
        let state = boardState
        let winning = Set(state.winningRun)
        return VStack(spacing: 1) {
            ForEach(0..<Gomoku.size, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(0..<Gomoku.size, id: \.self) { col in
                        cellView(state: state, index: row * Gomoku.size + col,
                                 winning: winning)
                    }
                }
            }
        }
        // Hardware keyboard: arrows move the shared board cursor,
        // Space/Return places through the game's own guarded path.
        .boardKeyCursor(BoardKeyLattice.grid(
            columns: Gomoku.size, rows: Gomoku.size, spacing: 1,
            activate: { column, row in
                place(index: row * Gomoku.size + column)
            }))
        .padding(1)
        // Paper game plan: the 1-pt gaps expose the printed ink lattice —
        // a 15×15 Go-paper grid drawn in faded ink.
        .background(
            RoundedRectangle(cornerRadius: Radius.concentric(
                parent: Radius.papier, padding: Space.m), style: .continuous)
                .fill(Tinte.sekundaer.opacity(0.6))
        )
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.gomoku.a11y.board"))
        .accessibilityValue(L10n.t("games.gomoku.a11y.value", ["n": "\(state.placed)"]))
    }

    private func cellView(state: GomokuState, index: Int, winning: Set<Int>) -> some View {
        let owner = state.board[index]
        let highlight = winning.contains(index)
        return Button {
            place(index: index)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Papier.brief)
                if let owner {
                    Circle()
                        .fill(roster.ink(of: owner))
                        .overlay(
                            // The winning run is embossed with a light
                            // paper ring; the lampengold GLOW behind the
                            // stones is the one legal gold-on-paper role.
                            Circle().strokeBorder(highlight ? Papier.brief : Color.clear,
                                                  lineWidth: highlight ? 2 : 0)
                        )
                        .shadow(color: highlight ? Licht.lampengold.opacity(0.7) : .clear, radius: 3)
                        .padding(1)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: owner)
        }
        .buttonStyle(.plain)
        .disabled(!myTurn || sending || owner != nil)
        .accessibilityLabel(cellA11yLabel(state: state, index: index))
    }

    private func cellA11yLabel(state: GomokuState, index: Int) -> String {
        let square = BoardDuel.squareName(index, size: Gomoku.size)
        if let owner = state.board[index] {
            return "\(square): \(roster.name(of: owner))"
        }
        return L10n.t("games.gomoku.a11y.place", ["square": square])
    }

    // MARK: Interaction

    private func place(index: Int) {
        guard myTurn, !sending, boardState.board[index] == nil else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("place"),
                "index": .number(Double(index)),
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                CueKit.play(.chip)
            }
            sending = false
        }
    }

    private func announceLatestMove() {
        guard let last = placements.last, last.memberId != roster.myId else { return }
        GamesA11y.announce(L10n.t("games.gomoku.a11y.partnerPlaced",
                                  ["name": roster.name(of: last.memberId),
                                   "square": BoardDuel.squareName(last.index, size: Gomoku.size)]))
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .gomoku,
                                   payload: GameEngine.makePayload()) {
                CueKit.play(.chip)
            }
        }
    }

    private func resetLocalState() {
        sending = false
        celebrated = false
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
            detail: nil,
            busy: engine.busy,
            rematch: startGame
        ) {
            boardView
        }
    }

    private func endLine(winner: String?) -> String {
        guard let winner else { return L10n.t("games.board.draw") }
        return winner == roster.myId
            ? L10n.t("games.board.win.you")
            : L10n.t("games.board.win.partner", ["name": roster.name(of: winner)])
    }
}
