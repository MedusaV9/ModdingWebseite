import SwiftUI
import Combine

/// Mancala (Kalaha) live — six pits and a store per member. Both clients
/// reduce the identical board from the ordered `{kind:"sow", pit}` list
/// via `Mancala.reduce` (Content/BoardGameRules.swift): sowing runs
/// counter-clockwise over own pits → own store → opponent pits (their
/// store is skipped); the last stone in the own store grants an extra
/// turn, in an own empty pit it captures the opposite pit. The sowing
/// PREVIEW (`Mancala.preview`) marks pits that would end in the store.
struct MancalaView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var celebrated = false
    @State private var chosenStones = 4
    /// Pit held down for the sowing preview (press-and-hold peek): while
    /// set, the board overlays the per-pit gains, landing ring and the
    /// capture target of `BoardGameFeedback.mancalaSowPlan`.
    @State private var previewPit: Int?
    /// True from peek start until shortly after release — swallows the
    /// button tap the peek's release would otherwise fire as a sow.
    @State private var previewHeld = false

    var body: some View {
        BoardDuelScreen(engine: engine, kind: .mancala, finished: finished) {
            BoardDuelSetupCard(symbol: "circlebadge.2.fill", kind: .mancala,
                               bodyKey: "games.mancala.setup.body",
                               busy: engine.busy, start: startGame) {
                stonesPicker
            }
        } play: {
            playScreen
        } end: {
            endScreen
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: sows.count) { old, new in
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
        guard let current = engine.session, current.kind == .mancala else { return nil }
        return current
    }

    private var roster: DuelRoster { DuelRoster(appState: appState, session: session) }

    private var stones: Int { engine.payloadInt("stones", default: 4) }

    private var sows: [(memberId: String, pit: Int)] {
        engine.moves(kind: "sow").compactMap { move in
            guard let pit = move.data["pit"]?.intValue else { return nil }
            return (move.memberId, pit)
        }
    }

    private var boardState: MancalaState {
        Mancala.reduce(sows: sows, stones: stones,
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

    /// The mover kept the turn — the last sow ended in the own store.
    private var extraTurnRunning: Bool {
        guard let last = sows.last else { return false }
        return !finished && last.memberId == boardState.turn
    }

    /// Own pits that would end in the store (extra turn) — the sowing hint.
    private var extraTurnPits: Set<Int> {
        guard myTurn else { return [] }
        return Set((0..<Mancala.pitsPerSide).filter { pit in
            Mancala.preview(state: boardState, member: roster.myId, pit: pit)?
                .outcome.extraTurn == true
        })
    }

    /// The full sowing plan for the held pit — path gains, landing pit,
    /// store gain and the capture target (BoardGameFeedbackRules, the
    /// read-only twin of `Mancala.sow` pinned by the logic tests).
    private var previewPlan: BoardGameFeedback.MancalaSowPlan? {
        guard myTurn, let pit = previewPit else { return nil }
        return BoardGameFeedback.mancalaSowPlan(
            ownPits: boardState.pits[roster.myId] ?? [],
            theirPits: boardState.pits[opponentId] ?? [],
            pit: pit
        )
    }

    // MARK: Setup options

    private var stonesPicker: some View {
        VStack(spacing: Space.s) {
            Text(L10n.t("games.mancala.setup.stones"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                // Sits in the night setup card since P2-C — night ink.
                .foregroundStyle(Nacht.sekundaer)
            Picker(L10n.t("games.mancala.setup.stones"), selection: $chosenStones) {
                ForEach([3, 4, 5, 6], id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Play screen

    private var playScreen: some View {
        BoardDuelPlayLayout(gameType: "mancala") {
            BoardTurnBanner(color: roster.ink(of: boardState.turn), text: turnLine)
            if let plan = previewPlan {
                previewSummary(plan: plan)
            } else if !extraTurnPits.isEmpty {
                Text(L10n.t("games.mancala.extraHint"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if myTurn {
                Text(L10n.t("games.mancala.previewHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
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

    /// One line under the banner while a pit is held: where the sow ends
    /// and what it earns — the same verdict the overlays show in place.
    private func previewSummary(plan: BoardGameFeedback.MancalaSowPlan) -> some View {
        let line: String
        if plan.landsInStore {
            line = L10n.t("games.mancala.preview.extra")
        } else if let captured = plan.capturedOpponentPit {
            line = L10n.t("games.mancala.preview.capture",
                          ["count": "\(plan.capturedStones)", "n": "\(captured + 1)"])
        } else {
            line = L10n.t("games.mancala.preview.pass")
        }
        return Text(line)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(plan.landsInStore || plan.capturedStones > 0
                             ? Licht.lampengold : Nacht.sekundaer)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
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
                label: id == roster.myId ? L10n.t("games.mancala.store.you")
                                         : L10n.t("games.mancala.store.partner",
                                                  ["name": roster.name(of: id)]),
                value: "\(boardState.stores[id] ?? 0)"
            )
        }
    }

    /// Classic table: the opponent's row on top (mirrored so the
    /// counter-clockwise flow reads as one circle), own row at the bottom,
    /// the two stores on the sides.
    private var boardView: some View {
        let state = boardState
        return HStack(spacing: Space.s) {
            storeView(state: state, member: opponentId)
            VStack(spacing: Space.m) {
                HStack(spacing: Space.s) {
                    ForEach(Array((0..<Mancala.pitsPerSide).reversed()), id: \.self) { pit in
                        pitView(state: state, member: opponentId, pit: pit)
                    }
                }
                HStack(spacing: Space.s) {
                    ForEach(0..<Mancala.pitsPerSide, id: \.self) { pit in
                        pitView(state: state, member: roster.myId, pit: pit)
                    }
                }
                // Hardware keyboard on MY sowing row (only own pits are
                // ever playable): arrows walk the pits, Space/Return sows
                // through the game's own guarded path.
                .boardKeyCursor(BoardKeyLattice.grid(
                    columns: Mancala.pitsPerSide, rows: 1, spacing: Space.s,
                    activate: { column, _ in
                        sow(pit: column)
                    }))
            }
            storeView(state: state, member: roster.myId)
        }
        .padding(Space.m)
        .paperCard(padding: .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("games.mancala.a11y.board"))
        .accessibilityValue(L10n.t("games.mancala.a11y.value", [
            "mine": "\(state.stores[roster.myId] ?? 0)",
            "name": appState.partnerName,
            "theirs": "\(state.stores[opponentId] ?? 0)",
        ]))
    }

    private func pitView(state: MancalaState, member: String, pit: Int) -> some View {
        let count = state.pits[member]?[pit] ?? 0
        let mine = member == roster.myId
        let playable = mine && myTurn && !sending && count > 0
        let hint = mine && extraTurnPits.contains(pit)
        let gain = previewGain(member: member, pit: pit)
        let isSource = mine && previewPit == pit
        let isLanding = mine && previewPlan?.landingOwnPit == pit
        let isCaptured = !mine && previewPlan?.capturedOpponentPit == pit
        return Button {
            sow(pit: pit)
        } label: {
            VStack(spacing: 2) {
                Text("\(count)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? Tinte.dunkel : Tinte.tertiaer)
                if let gain {
                    // The sowing path: every pit this move feeds shows its
                    // gain while the source pit is held. Capture targets are
                    // marked in wax red — the one danger ink on paper.
                    Text("+\(gain)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isCaptured ? Wachs.rot : coupleTint.tinte)
                } else if hint && previewPit == nil {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(coupleTint.tinte)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.8, contentMode: .fit)
            .background(
                // Playable pits carry the member's ink as a wash on the
                // paper plan (lampengold never inks paper).
                Capsule()
                    .fill(playable ? roster.ink(of: member).opacity(0.22)
                                   : Papier.innenFill)
            )
            .overlay(
                Capsule().strokeBorder(
                    isCaptured ? Wachs.rot
                        : (isSource || isLanding) ? coupleTint.tinte
                        : hint ? coupleTint.tinte : Papier.kante,
                    lineWidth: (hint || gain != nil || isSource) ? 2 : Theme.hairlineWidth
                )
            )
            .opacity(isSource ? 0.75 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: count)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: gain)
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .simultaneousGesture(
            // Hold-to-peek: the long press shows the plan, releasing hides
            // it again. The latch swallows the button tap that fires on
            // the release of a peek, so peeking never sows.
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    guard playable, case .second = value, previewPit != pit else { return }
                    Haptics.shared.tap()
                    previewHeld = true
                    previewPit = pit
                    announcePreview(pit: pit)
                }
                .onEnded { _ in
                    previewPit = nil
                    Task {
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        previewHeld = false
                    }
                }
        )
        .accessibilityLabel(L10n.t("games.mancala.a11y.pit",
                                   ["n": "\(pit + 1)", "count": "\(count)"]))
        .accessibilityHint(playable ? L10n.t("games.mancala.a11y.sow", ["n": "\(pit + 1)"]) : "")
    }

    /// Stones this pit would receive from the held pit's sow, nil when the
    /// path skips it (or no preview is active).
    private func previewGain(member: String, pit: Int) -> Int? {
        guard let plan = previewPlan else { return nil }
        let gains = member == roster.myId ? plan.ownGains : plan.theirGains
        guard pit < gains.count, gains[pit] > 0 else { return nil }
        return gains[pit]
    }

    private func storeView(state: MancalaState, member: String) -> some View {
        let storeGain: Int = {
            guard member == roster.myId, let plan = previewPlan else { return 0 }
            return plan.storeGain + plan.capturedStones
        }()
        return VStack(spacing: Space.s) {
            Text("\(state.stores[member] ?? 0)")
                .font(Typo.number)
                .foregroundStyle(Tinte.dunkel)
            if storeGain > 0 {
                Text("+\(storeGain)")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(coupleTint.tinte)
                    .transition(.opacity)
            }
            Circle()
                .fill(roster.ink(of: member))
                .frame(width: Space.m, height: Space.m)
                .overlay(Circle().strokeBorder(Papier.kante,
                                               lineWidth: Theme.hairlineWidth))
        }
        .frame(maxWidth: Space.xxl * 2)
        .padding(.vertical, Space.l)
        .background(
            Capsule().fill(roster.ink(of: member).opacity(0.14))
        )
        .animation(reduceMotion ? nil : Theme.Motion.settle, value: state.stores[member])
        .accessibilityLabel(member == roster.myId
                            ? L10n.t("games.mancala.store.you")
                            : L10n.t("games.mancala.store.partner",
                                     ["name": roster.name(of: member)]))
        .accessibilityValue("\(state.stores[member] ?? 0)")
    }

    // MARK: Interaction

    private func sow(pit: Int) {
        // A peek release is not a move.
        guard !previewHeld else { return }
        guard myTurn, !sending,
              let preview = Mancala.preview(state: boardState, member: roster.myId, pit: pit)
        else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("sow"),
                "pit": .number(Double(pit)),
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                if preview.outcome.captured > 0 {
                    CueKit.play(.hit)
                } else if preview.outcome.extraTurn {
                    CueKit.play(.success)
                } else {
                    CueKit.play(.chip)
                }
            }
            sending = false
        }
    }

    private func announceLatestMove() {
        guard let last = sows.last, last.memberId != roster.myId else { return }
        GamesA11y.announce(L10n.t("games.mancala.a11y.partnerSowed",
                                  ["name": roster.name(of: last.memberId),
                                   "n": "\(last.pit + 1)"]))
    }

    /// Speaks the peek verdict so the preview is not eyes-only.
    private func announcePreview(pit: Int) {
        guard let plan = BoardGameFeedback.mancalaSowPlan(
            ownPits: boardState.pits[roster.myId] ?? [],
            theirPits: boardState.pits[opponentId] ?? [],
            pit: pit
        ) else { return }
        if plan.landsInStore {
            GamesA11y.announce(L10n.t("games.mancala.preview.extra"))
        } else if let captured = plan.capturedOpponentPit {
            GamesA11y.announce(L10n.t("games.mancala.preview.capture",
                                      ["count": "\(plan.capturedStones)",
                                       "n": "\(captured + 1)"]))
        } else {
            GamesA11y.announce(L10n.t("games.mancala.preview.pass"))
        }
    }

    // MARK: Lifecycle

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .mancala,
                                   payload: GameEngine.makePayload(options: ["stones": chosenStones])) {
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
            detail: L10n.t("games.board.finalScore", [
                "a": "\(boardState.stores[roster.myId] ?? 0)",
                "b": "\(boardState.stores[opponentId] ?? 0)",
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
