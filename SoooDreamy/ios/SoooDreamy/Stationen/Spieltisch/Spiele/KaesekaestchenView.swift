import SwiftUI
import Combine

/// Käsekästchen (dots & boxes) live — draw one edge per turn, close a box
/// to own it AND move again (chainable). Both clients reduce the identical
/// field from the ordered `{kind:"edge", edge}` list via
/// `Kaesekaestchen.reduce` (Content/BoardGameRules.swift); the server ends
/// the match once every edge is drawn.
///
/// Edge indexes follow the server contract: horizontal edges first
/// (`row*size+col`, row 0…size), then vertical (`size*(size+1) +
/// row*(size+1) + col`).
struct KaesekaestchenView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false
    @State private var chosenSize = 5

    private static let dot: CGFloat = 10

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .kaesekaestchen, finished: finished) {
            BoardDuelSetupCard(symbol: "squareshape.split.3x3", kind: .kaesekaestchen,
                               bodyKey: "games.kaese.setup.body",
                               busy: engine.busy, start: startGame) {
                sizePicker
            }
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: edgeMoves.count) { old, new in
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
        guard let current = engine.session, current.kind == .kaesekaestchen else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var boardSize: Int { engine.payloadInt("size", default: 5) }

    private var edgeMoves: [(memberId: String, edge: Int)] {
        engine.moves(kind: "edge").compactMap { move in
            guard let edge = move.data["edge"]?.intValue else { return nil }
            return (move.memberId, edge)
        }
    }

    private var boardState: KaeseState {
        Kaesekaestchen.reduce(moves: edgeMoves, size: boardSize,
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

    /// The mover kept the turn — the last accepted edge closed a box.
    private var extraTurnRunning: Bool {
        guard let last = edgeMoves.last else { return false }
        return !finished && last.memberId == boardState.turn
    }

    // MARK: Setup options

    private var sizePicker: some View {
        VStack(spacing: Space.s) {
            Text(L10n.t("games.kaese.setup.size"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                // Sits in the night setup card since P2-C — night ink.
                .foregroundStyle(Nacht.sekundaer)
            Picker(L10n.t("games.kaese.setup.size"), selection: $chosenSize) {
                ForEach([3, 4, 5, 6], id: \.self) { size in
                    Text("\(size) × \(size)").tag(size)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "kaesekaestchen") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
        } board: {
            boardView
        } footer: {
            BoardColorLegend(entries: legendEntries)
            if !myTurn {
                GameWaitingHint()
            }
        }
    }

    private var turnLine: String {
        if extraTurnRunning {
            return myTurn ? L10n.t("games.board.extraTurn.you")
                          : L10n.t("games.board.extraTurn.partner",
                                   ["name": roster.name(of: boardState.turn)])
        }
        return myTurn ? L10n.t("games.board.yourTurn")
                      : L10n.t("games.board.partnerTurn", ["name": roster.name(of: boardState.turn)])
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

    // MARK: Board (alternating dot/edge and edge/box rows)

    private var boardView: some View {
        let state = boardState
        let size = boardSize
        return VStack(spacing: 0) {
            ForEach(0...size, id: \.self) { row in
                horizontalEdgeRow(state: state, row: row, size: size)
                if row < size {
                    boxRow(state: state, row: row, size: size)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Hardware keyboard on the alternating edge lattice: even cursor
        // rows are a dot row's horizontal edges, odd rows a box row's
        // vertical edges; Space/Return draws through the game's own path.
        .boardKeyCursor(BoardKeyLattice.kaeseEdges(
            size: size, dot: Self.dot,
            activate: { column, row in
                let edge = row.isMultiple(of: 2)
                    ? Kaesekaestchen.horizontalEdge(size: size, row: row / 2, col: column)
                    : Kaesekaestchen.verticalEdge(size: size, row: (row - 1) / 2, col: column)
                draw(edge: edge)
            }))
        .padding(Space.m)
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.kaese.a11y.board"))
        .accessibilityValue(L10n.t("games.kaese.a11y.value", [
            "mine": "\(state.scores[roster.myId] ?? 0)",
            "name": appState.partnerName,
            "theirs": "\(state.scores[opponentId] ?? 0)",
        ]))
    }

    private func horizontalEdgeRow(state: KaeseState, row: Int, size: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<size, id: \.self) { col in
                dotView
                edgeButton(state: state,
                           edge: Kaesekaestchen.horizontalEdge(size: size, row: row, col: col),
                           horizontal: true)
            }
            dotView
        }
        .frame(height: Self.dot)
    }

    private func boxRow(state: KaeseState, row: Int, size: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<size, id: \.self) { col in
                edgeButton(state: state,
                           edge: Kaesekaestchen.verticalEdge(size: size, row: row, col: col),
                           horizontal: false)
                boxView(state: state, box: row * size + col)
            }
            edgeButton(state: state,
                       edge: Kaesekaestchen.verticalEdge(size: size, row: row, col: size),
                       horizontal: false)
        }
    }

    private var dotView: some View {
        // The printed dots of the game plan — faded ink on paper.
        Circle()
            .fill(Tinte.sekundaer)
            .frame(width: Self.dot, height: Self.dot)
            .accessibilityHidden(true)
    }

    private func edgeButton(state: KaeseState, edge: Int, horizontal: Bool) -> some View {
        let drawn = state.drawn.contains(edge)
        return Button {
            draw(edge: edge)
        } label: {
            Capsule()
                .fill(drawn ? AnyShapeStyle(coupleTint.tinte)
                            : AnyShapeStyle(Papier.innenFill))
                .padding(horizontal ? EdgeInsets(top: 2, leading: 1, bottom: 2, trailing: 1)
                                    : EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 2))
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : Theme.Motion.settle, value: drawn)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: horizontal ? .infinity : Self.dot,
               maxHeight: horizontal ? Self.dot : .infinity)
        .disabled(!myTurn || sending || drawn)
        .accessibilityLabel(edgeA11yLabel(edge: edge))
        .accessibilityValue(drawn ? L10n.t("games.kaese.a11y.drawn") : "")
    }

    /// Spatial edge name — „Obere Kante von B2" instead of a bare index
    /// (BoardGameFeedbackRules maps the server's edge numbering to named
    /// box sides; the logic tests pin every edge of every size).
    private func edgeA11yLabel(edge: Int) -> String {
        guard let description = BoardGameFeedback.kaeseEdgeDescription(size: boardSize,
                                                                       edge: edge) else {
            return L10n.t("games.kaese.a11y.edge", ["n": "\(edge)"])
        }
        return L10n.t("games.kaese.a11y.edge.\(description.side.rawValue)",
                      ["square": description.square])
    }

    private func boxView(state: KaeseState, box: Int) -> some View {
        ZStack {
            // A closed box gets a light wash of the owner's ink; the
            // heart stamp on top stays full-strength ink.
            Rectangle()
                .fill(state.owners[box].map { roster.ink(of: $0).opacity(0.25) } ?? Color.clear)
            if let owner = state.owners[box] {
                Image(systemName: "heart.fill")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(roster.ink(of: owner))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : Theme.Motion.settle, value: state.owners[box])
        .accessibilityHidden(state.owners[box] == nil)
        .accessibilityLabel(state.owners[box].map { roster.name(of: $0) } ?? "")
    }

    // MARK: Interaction

    private func draw(edge: Int) {
        guard myTurn, !sending, !boardState.drawn.contains(edge) else { return }
        // Predict the outcome with the same rule the reducer applies, so
        // the cue can distinguish a plain edge from a box closure.
        let closes = !Kaesekaestchen.closedBoxes(size: boardSize,
                                                 drawn: boardState.drawn.union([edge]),
                                                 owners: boardState.owners,
                                                 edge: edge).isEmpty
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("edge"),
                "edge": .number(Double(edge)),
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                CueKit.play(closes ? .success : .chip)
            }
            sending = false
        }
    }

    private func announceLatestMove() {
        guard let last = edgeMoves.last, last.memberId != roster.myId else { return }
        // Boxes the partner owns whose frame contains the fresh edge — the
        // ones this very move closed.
        let closed = (0..<(boardSize * boardSize)).filter { box in
            boardState.owners[box] == last.memberId
                && Kaesekaestchen.boxEdges(size: boardSize, box: box).contains(last.edge)
        }.count
        if closed > 0 {
            GamesA11y.announce(L10n.t("games.kaese.a11y.partnerClosed",
                                      ["name": roster.name(of: last.memberId),
                                       "n": "\(closed)"]))
        } else {
            GamesA11y.announce(L10n.t("games.kaese.a11y.partnerDrew",
                                      ["name": roster.name(of: last.memberId)]))
        }
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .kaesekaestchen,
                                   payload: GameEngine.makePayload(options: ["size": chosenSize])) {
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
            detail: L10n.t("games.kaese.boxes", [
                "mine": "\(boardState.scores[roster.myId] ?? 0)",
                "theirs": "\(boardState.scores[opponentId] ?? 0)",
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
