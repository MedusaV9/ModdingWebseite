import SwiftUI
import Combine

/// Reversi live — 8×8, enclose and flip. Both clients reduce the identical
/// board from the ordered `{kind:"place", index}` / `{kind:"pass"}` list
/// via `Reversi.reduce` (Content/BoardGameRules.swift); legal squares are
/// highlighted from the same rule the server enforces (`no_flip` /
/// `pass_not_allowed`), and the server ends the match on the decisive move.
struct ReversiView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .reversi, finished: finished) {
            BoardDuelSetupCard(symbol: "circle.lefthalf.filled", kind: .reversi,
                               bodyKey: "games.reversi.setup.body",
                               busy: engine.busy, start: startGame)
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: parsedMoves.count) { old, new in
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
        guard let current = engine.session, current.kind == .reversi else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var parsedMoves: [(memberId: String, move: ReversiMove)] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "place":
                guard let index = move.data["index"]?.intValue else { return nil }
                return (move.memberId, .place(index))
            case "pass":
                return (move.memberId, .pass)
            default:
                return nil
            }
        }
    }

    private var boardState: ReversiState {
        Reversi.reduce(moves: parsedMoves, starter: roster.starterId, partner: roster.otherId)
    }

    private var finished: Bool {
        guard let session, session.state == "active" || session.state == "ended" else { return false }
        return session.state == "ended" || boardState.complete
    }

    private var myTurn: Bool { boardState.turn == roster.myId && !finished }

    private var legalSquares: Set<Int> {
        guard myTurn, !sending else { return [] }
        return Set(Reversi.legalMoves(board: boardState.board, owner: roster.myId))
    }

    private var mustPass: Bool { myTurn && legalSquares.isEmpty }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "reversi") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
        } board: {
            boardView
        } footer: {
            BoardColorLegend(entries: legendEntries)
            if mustPass {
                Button {
                    sendPass()
                } label: {
                    Text(L10n.t("games.reversi.pass"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending)
            }
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
                value: "\(boardState.count(of: id))"
            )
        }
    }

    private var opponentId: String {
        roster.myId == roster.starterId ? roster.otherId : roster.starterId
    }

    private var boardView: some View {
        let state = boardState
        return VStack(spacing: 2) {
            ForEach(0..<Reversi.size, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<Reversi.size, id: \.self) { col in
                        squareView(state: state, index: row * Reversi.size + col)
                    }
                }
            }
        }
        // Hardware keyboard: arrows move the shared board cursor,
        // Space/Return places through the game's own guarded path.
        .boardKeyCursor(BoardKeyLattice.grid(
            columns: Reversi.size, rows: Reversi.size, spacing: 2,
            activate: { column, row in
                place(index: row * Reversi.size + column)
            }))
        .padding(2)
        // Paper game plan: the gaps expose the printed ink grid.
        .background(
            RoundedRectangle(cornerRadius: Radius.concentric(
                parent: Radius.papier, padding: Space.m), style: .continuous)
                .fill(Tinte.sekundaer.opacity(0.6))
        )
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.reversi.a11y.board"))
        .accessibilityValue(L10n.t("games.reversi.a11y.value", [
            "mine": "\(state.count(of: roster.myId))",
            "name": appState.partnerName,
            "theirs": "\(state.count(of: opponentId))",
        ]))
    }

    private func squareView(state: ReversiState, index: Int) -> some View {
        let owner = state.board[index]
        let legal = legalSquares.contains(index)
        return Button {
            place(index: index)
        } label: {
            ZStack {
                Rectangle()
                    .fill(Papier.brief)
                if let owner {
                    Circle()
                        .fill(roster.ink(of: owner))
                        .overlay(Circle().strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
                        .padding(2)
                } else if legal {
                    // Legal-move ring in the couple ink — readable on the
                    // paper square, unlike the raw blend.
                    Circle()
                        .strokeBorder(coupleTint.tinte, lineWidth: 2)
                        .padding(Space.s)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: owner)
        }
        .buttonStyle(.plain)
        .disabled(!legal)
        .accessibilityLabel(squareA11yLabel(state: state, index: index, legal: legal))
    }

    private func squareA11yLabel(state: ReversiState, index: Int, legal: Bool) -> String {
        let square = BoardDuel.squareName(index, size: Reversi.size)
        if let owner = state.board[index] {
            return "\(square): \(roster.name(of: owner))"
        }
        if legal {
            let flips = Reversi.flips(board: state.board, index: index, owner: roster.myId).count
            return L10n.t("games.reversi.a11y.place", ["square": square, "n": "\(flips)"])
        }
        return square
    }

    // MARK: Interaction

    private func place(index: Int) {
        guard legalSquares.contains(index), !sending else { return }
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

    private func sendPass() {
        guard mustPass, !sending else { return }
        sending = true
        Task {
            if await engine.sendMove(api: appState.api,
                                     data: .object(["kind": .string("pass")])) {
                CueKit.play(.click)
            }
            sending = false
        }
    }

    private func announceLatestMove() {
        guard let last = parsedMoves.last, last.memberId != roster.myId else { return }
        switch last.move {
        case .place(let index):
            GamesA11y.announce(L10n.t("games.reversi.a11y.partnerPlaced",
                                      ["name": roster.name(of: last.memberId),
                                       "square": BoardDuel.squareName(index, size: Reversi.size)]))
        case .pass:
            GamesA11y.announce(L10n.t("games.reversi.a11y.partnerPassed",
                                      ["name": roster.name(of: last.memberId)]))
        }
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .reversi,
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
            detail: L10n.t("games.reversi.discs", [
                "mine": "\(boardState.count(of: roster.myId))",
                "theirs": "\(boardState.count(of: opponentId))",
            ]),
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
