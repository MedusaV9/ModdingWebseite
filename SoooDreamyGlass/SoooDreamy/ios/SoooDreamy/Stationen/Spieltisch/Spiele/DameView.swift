import SwiftUI
import Combine

/// Dame (checkers) live — 8×8 dark squares, forced captures, jump chains
/// and the crowning. Both clients reduce the identical board from the
/// ordered `{kind:"move", path:[from,…,to]}` list via `Dame.reduce`
/// (Content/BoardGameRules.swift, pinned by the Linux logic tests); the
/// server ends the match on the decisive move.
///
/// Path input: tap a piece, then tap along the highlighted targets — a
/// quiet step sends immediately, a jump chain collects the full path
/// (Fortsetzungspflicht: only complete chains are legal) and sends when
/// the chain is finished.
struct DameView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false
    @State private var selection: [Int] = []
    /// Square of the last rejected tap — drives the brief "no" wiggle.
    @State private var rejectedIndex: Int?

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .dame, finished: finished) {
            BoardDuelSetupCard(symbol: "checkerboard.rectangle", kind: .dame,
                               bodyKey: "games.dame.setup.body",
                               busy: engine.busy, start: startGame)
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: boardState.moveCount) { old, new in
            guard new > old else { return }
            selection = []
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
        guard let current = engine.session, current.kind == .dame else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var pathMoves: [(memberId: String, path: [Int])] {
        engine.moves(kind: "move").compactMap { move in
            guard let path = move.data["path"]?.arrayValue?.compactMap(\.intValue),
                  path.count >= 2 else { return nil }
            return (move.memberId, path)
        }
    }

    private var boardState: DameState {
        Dame.reduce(moves: pathMoves, starter: roster.starterId, partner: roster.otherId)
    }

    private var drawPlies: Int { engine.payloadInt("drawPlies", default: 40) }

    private var status: (complete: Bool, winner: String?, draw: Bool) {
        Dame.status(state: boardState, drawPlies: drawPlies)
    }

    private var finished: Bool {
        guard let session, session.state == "active" || session.state == "ended" else { return false }
        return session.state == "ended" || (status.complete && !pathMoves.isEmpty)
    }

    private var myTurn: Bool { boardState.turn == roster.myId && !finished }

    /// Complete legal paths for me, filtered down to the current selection.
    private var candidatePaths: [[Int]] {
        guard myTurn else { return [] }
        let all = Dame.legalPaths(state: boardState)
        guard !selection.isEmpty else { return all }
        return all.filter { $0.count > selection.count && Array($0.prefix(selection.count)) == selection }
            + all.filter { $0 == selection }
    }

    private var mustCapture: Bool {
        myTurn && Dame.sideHasCapture(board: boardState.board, owner: roster.myId)
    }

    /// Squares I may tap next: legal origins (no selection yet) or the next
    /// step of every path matching the selection.
    private var tapTargets: Set<Int> {
        guard myTurn, !sending else { return [] }
        if selection.isEmpty {
            return Set(candidatePaths.map { $0[0] })
        }
        return Set(candidatePaths.filter { $0.count > selection.count }.map { $0[selection.count] })
    }

    /// Own pieces that may START a move right now (forced captures shrink
    /// this set!) — only these read as tappable; the rest of my pieces
    /// answer taps with a quiet "no" wiggle instead of silent nothing.
    private var legalOrigins: Set<Int> {
        guard myTurn, !sending, selection.count <= 1 else { return [] }
        return Set(Dame.legalPaths(state: boardState).map { $0[0] })
    }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "dame") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
            if mustCapture {
                Text(L10n.t(selection.count > 1 ? "games.dame.chain.hint" : "games.dame.capture.hint"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        myTurn ? L10n.t("games.board.yourTurn")
               : L10n.t("games.board.partnerTurn", ["name": roster.name(of: boardState.turn)])
    }

    private var legendEntries: [BoardColorLegend.Entry] {
        [roster.myId, roster.myId == roster.starterId ? roster.otherId : roster.starterId].map { id in
            BoardColorLegend.Entry(
                id: id,
                color: roster.ink(of: id),
                label: id == roster.myId ? L10n.t("games.board.yourColor") : roster.name(of: id),
                value: "\(boardState.count(of: id))"
            )
        }
    }

    /// The creator plays "up" from row 0 — each member sees their own back
    /// row at the bottom of the screen.
    private var displayRows: [Int] {
        roster.myId == roster.starterId ? Array((0..<Dame.size).reversed()) : Array(0..<Dame.size)
    }

    private var boardView: some View {
        let state = boardState
        return VStack(spacing: 2) {
            ForEach(displayRows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<Dame.size, id: \.self) { col in
                        squareView(state: state, index: row * Dame.size + col)
                    }
                }
            }
        }
        // Hardware keyboard: arrows move the shared board cursor,
        // Space/Return taps through the game's own path (all turn/legality
        // guards intact), Esc clears cursor + jump-chain selection.
        .boardKeyCursor(BoardKeyLattice.grid(
            columns: Dame.size, rows: Dame.size, spacing: 2,
            activate: { column, row in
                tap(index: displayRows[row] * Dame.size + column)
            },
            escape: { selection = [] }))
        .padding(2)
        // The paper game plan: the gaps between the opaque squares expose
        // this fill — a printed ink grid on the letter-paper sheet.
        .background(
            RoundedRectangle(cornerRadius: Radius.concentric(
                parent: Radius.papier, padding: Space.m), style: .continuous)
                .fill(Tinte.sekundaer.opacity(0.6))
        )
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.dame.a11y.board"))
        .accessibilityValue(L10n.t("games.dame.a11y.value", [
            "mine": "\(state.count(of: roster.myId))",
            "name": appState.partnerName,
            "theirs": "\(state.count(of: roster.myId == roster.starterId ? roster.otherId : roster.starterId))",
        ]))
    }

    private func squareView(state: DameState, index: Int) -> some View {
        let piece = Dame.isPlayable(index) ? state.board[index] : nil
        let isTarget = tapTargets.contains(index)
        let isSelected = selection.contains(index)
        let isMovable = legalOrigins.contains(index)
        let isRejected = rejectedIndex == index
        return Button {
            tap(index: index)
        } label: {
            ZStack {
                // Opaque paper squares over the ink grid: playable squares
                // carry a printed sekundaer wash, the rest stay clean.
                Rectangle()
                    .fill(Papier.brief)
                if Dame.isPlayable(index) {
                    Rectangle()
                        .fill(Tinte.sekundaer.opacity(0.30))
                }
                if let piece {
                    Circle()
                        .fill(roster.ink(of: piece.owner))
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? Tinte.dunkel
                                    : isMovable ? Wachs.rot : Papier.kante,
                                lineWidth: (isSelected || isMovable) ? 2 : Theme.hairlineWidth
                            )
                        )
                        .overlay {
                            if piece.king {
                                // Light paper glyph embossed on the dark
                                // ink piece (inkOnPaper guarantees ≥4.5:1
                                // against the paper family — symmetric).
                                Image(systemName: "crown.fill")
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(Papier.brief)
                            }
                        }
                        .padding(2)
                        // My pieces that may NOT move right now (capture
                        // duty elsewhere) read as parked, not as buttons.
                        .opacity(piece.owner == roster.myId && myTurn && !isMovable && !isSelected
                                 ? 0.55 : 1)
                } else if isTarget {
                    Circle()
                        .fill(coupleTint.tinte)
                        .padding(Space.s)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .rotationEffect(.degrees(isRejected ? 6 : 0))
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: piece?.owner)
            .animation(reduceMotion ? nil : Theme.Motion.playful, value: isRejected)
        }
        .buttonStyle(.plain)
        .disabled(!myTurn || sending || (!isTarget && !(piece?.owner == roster.myId)))
        .accessibilityLabel(squareA11yLabel(state: state, index: index))
    }

    private func squareA11yLabel(state: DameState, index: Int) -> String {
        let square = BoardDuel.squareName(index, size: Dame.size)
        guard Dame.isPlayable(index), let piece = state.board[index] else {
            return L10n.t("games.dame.a11y.empty", ["square": square])
        }
        return L10n.t(piece.king ? "games.dame.a11y.king" : "games.dame.a11y.man",
                      ["name": roster.name(of: piece.owner), "square": square])
    }

    // MARK: Interaction

    private func tap(index: Int) {
        guard myTurn, !sending else { return }
        // Reselect a different own piece while no jump is underway.
        if selection.count <= 1, boardState.board[index]?.owner == roster.myId {
            guard legalOrigins.contains(index) else {
                reject(index: index)
                return
            }
            selection = [index]
            CueKit.play(.click)
            GamesA11y.announce(L10n.t("games.dame.a11y.select",
                                      ["square": BoardDuel.squareName(index, size: Dame.size)]))
            return
        }
        guard tapTargets.contains(index) else { return }
        selection.append(index)
        if let complete = candidatePaths.first(where: { $0 == selection }) {
            send(path: complete)
        } else {
            CueKit.play(.click)
        }
    }

    /// The quiet "no": this piece of mine may not move right now (usually
    /// capture duty elsewhere). A tiny wiggle + warning tick instead of a
    /// tap that silently does nothing.
    private func reject(index: Int) {
        Haptics.shared.warning()
        rejectedIndex = index
        GamesA11y.announce(L10n.t(mustCapture ? "games.dame.a11y.lockedCapture"
                                              : "games.dame.a11y.locked"))
        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if rejectedIndex == index { rejectedIndex = nil }
        }
    }

    private func send(path: [Int]) {
        sending = true
        let captured = path.count > 2 || abs(Dame.row(path[1]) - Dame.row(path[0])) == 2
        Task {
            let data = JSONValue.object([
                "kind": .string("move"),
                "path": .array(path.map { .number(Double($0)) }),
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                CueKit.play(captured ? .hit : .chip)
            }
            selection = []
            sending = false
        }
    }

    private func announceLatestMove() {
        guard let last = pathMoves.last, last.memberId != roster.myId,
              let target = last.path.last else { return }
        GamesA11y.announce(L10n.t("games.dame.a11y.partnerMoved",
                                  ["name": roster.name(of: last.memberId),
                                   "square": BoardDuel.squareName(target, size: Dame.size)]))
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .dame,
                                   payload: GameEngine.makePayload()) {
                CueKit.play(.chip)
            }
        }
    }

    private func resetLocalState() {
        sending = false
        celebrated = false
        selection = []
    }

    private func celebrate() {
        guard session != nil, !celebrated else { return }
        celebrated = true
        let winner = session?.result?["winner"]?.stringValue ?? status.winner
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
        let winner = session?.result?["winner"]?.stringValue ?? status.winner
        return BoardDuelEndPanel(
            symbol: winner == nil ? "equal.circle.fill" : "trophy.fill",
            headline: endLine(winner: winner),
            detail: L10n.t("games.dame.pieces", [
                "mine": "\(boardState.count(of: roster.myId))",
                "theirs": "\(boardState.count(of: roster.myId == roster.starterId ? roster.otherId : roster.starterId))",
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
