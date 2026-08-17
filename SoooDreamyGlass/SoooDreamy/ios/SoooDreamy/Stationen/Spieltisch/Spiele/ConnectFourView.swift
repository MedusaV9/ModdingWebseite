import SwiftUI
import Combine

/// 4 Gewinnt live 🔴🟡 — realtime Connect Four over the game-session relay.
///
/// The creator drops first, then strict alternation. Both clients reduce
/// the identical board from the ordered move list via `ConnectFour.reduce`
/// (Content/CoupleGamesLogic.swift, pinned by the Linux logic tests).
///
/// Move protocol: `{"kind": "drop", "column": 0…6}`.
struct ConnectFourView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrate = false
    @State private var lastCount = 0

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if celebrate && !reduceMotion {
                FloatingHeartsView(emojis: ["🏆", "🔴", "🟡", "✨", "🎉"], count: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.connectfour.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
            }
        }
        .task {
            engine.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            if engine.session == nil {
                await engine.resume(api: appState.api)
            }
            lastCount = boardState.moveCount
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: boardState.moveCount) { old, new in
            if new > old {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
                announceLatestDrop()
            }
        }
        .onChange(of: finished) { _, isDone in
            if isDone { handleFinish() }
        }
        .onAppear {
            if finished { handleFinish() }
        }
    }

    // MARK: Derived state

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .connectfour else { return nil }
        return current
    }

    /// Creator drops first; the partner id is the other couple member.
    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var drops: [(memberId: String, column: Int)] {
        engine.moves(kind: "drop").compactMap { move in
            guard let column = move.data["column"]?.intValue else { return nil }
            return (move.memberId, column)
        }
    }

    private var boardState: ConnectFourState {
        ConnectFour.reduce(drops: drops, starter: starterId, partner: otherId)
    }

    private var turnId: String {
        ConnectFour.turn(state: boardState, starter: starterId, partner: otherId)
    }

    private var myTurn: Bool { turnId == appState.memberId }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        let state = boardState
        return state.winner != nil || state.isDraw
    }

    /// Disc as INK on the paper board — the same inkOnPaper ladder as the
    /// board duels (≥4.5:1 on every paper tone): mine = my ink, partner =
    /// partner ink. One member, one ink on any Zettel.
    private func discInk(of memberId: String) -> Color {
        memberId == appState.memberId ? coupleTint.tintePrimary : coupleTint.tinteSecondary
    }

    private func name(of memberId: String) -> String {
        if memberId == appState.memberId {
            return appState.me?.name ?? L10n.t("common.you")
        }
        return appState.partnerName
    }

    // MARK: Content switch

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
            } else if finished {
                endScreen
            } else if session.state == "active" {
                playScreen
            } else {
                setupScreen
            }
        } else {
            setupScreen
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.connectfour.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.c4.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            if await engine.create(api: appState.api, type: .connectfour,
                                   payload: GameEngine.makePayload()) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        sending = false
        didSendEnd = false
        celebrate = false
        lastCount = 0
    }

    // MARK: Play

    /// Phone: stacked. Wide regular panes: game table (roadmap 22) — the
    /// board centered like a real table, turn/legend in the side rail.
    private var playScreen: some View {
        GameTableContainer(gameType: "connectfour") { paneWidth in
            GameTableLayout(gameType: "connectfour", paneWidth: paneWidth) {
                boardView
                    .gameActGated()
            } rail: {
                VStack(spacing: LayoutMetrics.s(14)) {
                    turnHeader
                    colorLegend
                    if !myTurn {
                        GameWaitingHint()
                    }
                }
                .gameActGated()
            }
        } stacked: {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(14)) {
                    turnHeader
                    boardView
                    colorLegend
                    if !myTurn {
                        GameWaitingHint()
                    }
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
            }
        }
    }

    private var turnHeader: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            BoardPieceDot(color: discInk(of: turnId))
            Text(myTurn
                 ? L10n.t("games.c4.yourTurn")
                 : L10n.t("games.c4.partnerTurn", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
    }

    /// One VoiceOver element for the whole board: the value walks the
    /// column stands, drops happen through named custom actions ("In
    /// Spalte 4 einwerfen") instead of 42 anonymous circles.
    private var boardView: some View {
        let state = boardState
        return VStack(spacing: LayoutMetrics.s(6)) {
            ForEach((0..<ConnectFour.rows).reversed(), id: \.self) { row in
                HStack(spacing: LayoutMetrics.s(6)) {
                    ForEach(0..<ConnectFour.columns, id: \.self) { column in
                        cell(state: state, column: column, row: row)
                    }
                }
            }
        }
        .padding(LayoutMetrics.s(10))
        // The rack as paper game plan: a matte inner well on the paper
        // card — the punched holes show the letter paper beneath.
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.innenFill)
        )
        .paperCard(padding: .compact)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.c4.a11y.board"))
        .accessibilityValue(boardA11yValue(state: state))
        .accessibilityActions {
            if myTurn && !finished && !sending {
                ForEach(0..<ConnectFour.columns, id: \.self) { column in
                    if state.height(column) < ConnectFour.rows {
                        Button(L10n.t("games.c4.a11y.drop", ["col": "\(column + 1)"])) {
                            drop(column: column)
                        }
                    }
                }
            }
        }
    }

    private func boardA11yValue(state: ConnectFourState) -> String {
        (0..<ConnectFour.columns).map { column in
            let height = state.height(column)
            guard height > 0, let top = state.owner(column: column, row: height - 1) else {
                return L10n.t("games.c4.a11y.colEmpty", ["col": "\(column + 1)"])
            }
            return L10n.t("games.c4.a11y.colState", count: height,
                          ["col": "\(column + 1)", "name": name(of: top)])
        }
        .joined(separator: "; ")
    }

    private func cell(state: ConnectFourState, column: Int, row: Int) -> some View {
        let owner = state.owner(column: column, row: row)
        let winning = state.winningCells.contains(ConnectFourCell(column: column, row: row))
        return Button {
            drop(column: column)
        } label: {
            Circle()
                .fill(owner.map(discInk(of:)) ?? Papier.brief)
                .overlay(
                    // The winning four wear the stamp-pad red ring — a
                    // wax mark instead of the glass-era white glow.
                    Circle().strokeBorder(winning ? Wachs.rot : Papier.kante,
                                          lineWidth: winning ? 2.5 : Theme.hairlineWidth)
                )
                .aspectRatio(1, contentMode: .fit)
                .animation(reduceMotion ? nil : Theme.Motion.settle, value: owner)
        }
        .buttonStyle(.plain)
        .disabled(!myTurn || sending || owner != nil)
    }

    private var colorLegend: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            legendEntry(memberId: appState.memberId ?? "", label: L10n.t("games.c4.discs"))
            Spacer()
            legendEntry(memberId: appState.partner?.id ?? "", label: appState.partnerName)
        }
        .nightCard(padding: .compact, grain: false)
    }

    private func legendEntry(memberId: String, label: String) -> some View {
        HStack(spacing: 8) {
            BoardPieceDot(color: discInk(of: memberId))
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
    }

    // MARK: Actions

    private func drop(column: Int) {
        guard myTurn, !sending, boardState.height(column) < ConnectFour.rows else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("drop"),
                "column": .number(Double(column))
            ])
            _ = await engine.sendMove(api: appState.api, data: data)
            sending = false
        }
    }

    /// Speaks the partner's drop so VoiceOver players hear the move land.
    private func announceLatestDrop() {
        guard let last = drops.last, last.memberId != appState.memberId else { return }
        GamesA11y.announce(L10n.t("games.c4.a11y.partnerDropped",
                                  ["name": name(of: last.memberId),
                                   "col": "\(last.column + 1)"]))
    }

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrate {
            celebrate = true
            let state = boardState
            if state.winner == appState.memberId {
                GamesA11y.announce(L10n.t("games.c4.a11y.won"))
                GameEndCelebration.win(visual: .localHearts)
            } else if let winner = state.winner {
                GamesA11y.announce(L10n.t("games.c4.a11y.lost", ["name": name(of: winner)]))
                GameEndCelebration.loss(visual: .localHearts)
            } else {
                GamesA11y.announce(L10n.t("games.c4.a11y.draw"))
                GameEndCelebration.tie(visual: .localHearts)
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    /// `{"scores": {winner: 1, loser: 0}}` — same shape as the quiz so the
    /// scoreboard (GamesRecordView) picks it up without special-casing.
    private var resultJSON: JSONValue {
        let state = boardState
        var scores: [String: JSONValue] = [:]
        for id in [starterId, otherId] where !id.isEmpty {
            scores[id] = .number(state.winner == id ? 1 : 0)
        }
        return .object(["scores": .object(scores)])
    }

    // MARK: End screen

    private var endScreen: some View {
        let state = boardState
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: state.winner == nil ? "hands.clap.fill" : "trophy.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.winner == nil ? coupleTint.blend : Licht.lampengold)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(endLine(state: state))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                boardView
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func endLine(state: ConnectFourState) -> String {
        guard let winner = state.winner else { return L10n.t("games.c4.draw") }
        if winner == appState.memberId {
            return L10n.t("games.c4.win.you")
        }
        return L10n.t("games.c4.win.partner", ["name": name(of: winner)])
    }
}
