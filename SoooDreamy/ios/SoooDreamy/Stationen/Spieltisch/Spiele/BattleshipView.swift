import SwiftUI
import Combine

// Schiffe versenken 🚢💥 — commit-reveal battleship over the game relay.
//
// Flow: both partners lock a hidden fleet in (`commit` = SHA-256 of
// layout+salt, see Core/CommitReveal.swift), then fire alternating 2-shot
// salvos. The DEFENDER's device answers every salvo truthfully from its
// local board (`report`), and after the win both boards are opened
// (`reveal`) — the relay certifies the hash and `Battleship.honest` replays
// all reports, so cheating is provably visible. Reducer:
// Content/BattleshipLogic.swift (pinned by Linux logic tests).

// MARK: - Fleet vault

/// The own layout + salt are the commit-reveal SECRET: they must survive app
/// restarts (reporting and revealing need them) and must never leave the
/// device before the reveal. Persisted per gameId.
enum BattleshipVault {
    private static func key(_ gameId: String) -> String { "battleship.secret.\(gameId)" }

    static func save(gameId: String, layout: String, salt: String) {
        UserDefaults.standard.set("\(salt)#\(layout)", forKey: key(gameId))
    }

    static func load(gameId: String) -> (layout: String, salt: String)? {
        guard let raw = UserDefaults.standard.string(forKey: key(gameId)),
              let separator = raw.firstIndex(of: "#") else { return nil }
        return (String(raw[raw.index(after: separator)...]), String(raw[..<separator]))
    }
}

// MARK: - View

struct BattleshipView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var placementSeed = Int.random(in: 1...999_999_999)
    @State private var targetCells: [Int] = []
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var didReveal = false
    @State private var celebrated = false
    @State private var sentReports: Set<Int> = []
    @State private var shared = false

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.battleship.title"))
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
            autoRespond()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
            autoRespond()
        }
        .onChange(of: gameState.salvos.count) { old, new in
            if new > old {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
            autoRespond()
        }
        .onChange(of: gameState.reports.count) { _, _ in
            autoRespond()
        }
        .onChange(of: gameState.committed.count) { _, _ in
            autoRespond()
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
        guard let current = engine.session, current.kind == .battleship else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    private var partnerId: String { appState.partner?.id ?? "" }

    /// Relay moves → typed reducer events (unknown shapes are dropped).
    private var events: [BattleshipEvent] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "commit":
                guard move.data["commit"]?.stringValue != nil else { return nil }
                return .commit(member: move.memberId)
            case "salvo":
                guard let cells = move.data["cells"]?.arrayValue?.compactMap(\.intValue)
                else { return nil }
                return .salvo(member: move.memberId, cells: cells)
            case "report":
                guard let index = move.data["index"]?.intValue else { return nil }
                return .report(member: move.memberId, index: index,
                               hits: move.data["hits"]?.arrayValue?.compactMap(\.intValue) ?? [],
                               sunk: move.data["sunk"]?.arrayValue?.compactMap(\.intValue) ?? [])
            case "reveal":
                guard let layout = move.data["reveal"]?.stringValue,
                      let salt = move.data["salt"]?.stringValue else { return nil }
                return .reveal(member: move.memberId, layout: layout, salt: salt,
                               serverVerified: move.data["verified"]?.boolValue ?? false)
            default:
                return nil
            }
        }
    }

    private var gameState: BattleshipState {
        Battleship.reduce(events: events, starter: starterId, partner: otherId)
    }

    private var myTurn: Bool {
        Battleship.turn(state: gameState, starter: starterId, partner: otherId) == myId
    }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.phase == .finished
    }

    private var myFleet: [[Int]]? {
        guard let id = session?.id, let secret = BattleshipVault.load(gameId: id) else { return nil }
        return Battleship.decodeLayout(secret.layout)
    }

    private var iWon: Bool { gameState.winner == myId }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: Theme.blue)
                        .padding(LayoutMetrics.s(16))
                }
            } else if finished {
                endScreen
            } else if session.state == "active" {
                if gameState.phase == .setup {
                    placementScreen
                } else {
                    battleScreen
                }
            } else {
                startScreen
            }
        } else {
            startScreen
        }
    }

    // MARK: Start

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "sailboat.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.battleship.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.bs.setup.body"))
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
            if await engine.create(api: appState.api, type: .battleship,
                                   payload: GameEngine.makePayload()) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        placementSeed = Int.random(in: 1...999_999_999)
        targetCells = []
        sending = false
        didSendEnd = false
        didReveal = false
        celebrated = false
        sentReports = []
        shared = false
    }

    // MARK: Placement (commit phase)

    private var placementScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                if gameState.committed.contains(myId) {
                    committedCard
                } else {
                    placementCard
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var placementCard: some View {
        let ships = Battleship.randomLayout(seed: placementSeed)
        return VStack(spacing: LayoutMetrics.s(14)) {
            Text(L10n.t("games.bs.place.title"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(L10n.t("games.bs.place.body"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            boardGrid(shipCells: Set(ships.flatMap { $0 }), marks: [:], tappable: false,
                      a11yLabel: L10n.t("games.bs.a11y.placementBoard"),
                      a11yValue: L10n.t("games.bs.a11y.placementValue",
                                        ["n": "\(Battleship.fleet.count)"]))
            HStack(spacing: LayoutMetrics.s(12)) {
                Button {
                    placementSeed = Int.random(in: 1...999_999_999)
                    SoundEngine.shared.play(.pop)
                    Haptics.shared.tap()
                } label: {
                    Label(L10n.t("games.bs.shuffle"), systemImage: "die.face.5")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .padding(.horizontal, LayoutMetrics.s(16))
                        .padding(.vertical, LayoutMetrics.s(10))
                        .background(
                            Capsule().fill(Papier.innenFill)
                                .overlay(Capsule().strokeBorder(Papier.kante,
                                                                lineWidth: Theme.hairlineWidth))
                        )
                        .foregroundStyle(Tinte.dunkel)
                }
                .buttonStyle(.plain)
                Button {
                    commitFleet(ships)
                } label: {
                    Text(L10n.t("games.bs.ready"))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .padding(.horizontal, LayoutMetrics.s(16))
                        .padding(.vertical, LayoutMetrics.s(10))
                        .background(Capsule().fill(coupleTint.tinte))
                        // Letter-paper glyph on the couple ink — ≥4.5:1 by
                        // the inkOnPaper construction.
                        .foregroundStyle(Papier.brief)
                }
                .buttonStyle(.plain)
                .disabled(sending)
            }
            Text(L10n.t("games.bs.commit.sealed"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
                .multilineTextAlignment(.center)
        }
        .paperCard()
    }

    private var committedCard: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Image(systemName: "anchor")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.tinte)
                .accessibilityHidden(true)
            Text(L10n.t("games.bs.commit.done", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
            if let fleet = myFleet {
                boardGrid(shipCells: Set(fleet.flatMap { $0 }), marks: [:], tappable: false,
                          a11yLabel: L10n.t("games.bs.a11y.placementBoard"),
                          a11yValue: L10n.t("games.bs.a11y.placementValue",
                                            ["n": "\(Battleship.fleet.count)"]))
            }
            ProgressView()
                .tint(coupleTint.tinte)
        }
        .paperCard()
    }

    private func commitFleet(_ ships: [[Int]]) {
        guard let id = session?.id, !sending else { return }
        sending = true
        let layout = Battleship.encodeLayout(ships)
        let salt = CommitReveal.newSalt()
        BattleshipVault.save(gameId: id, layout: layout, salt: salt)
        Task {
            let data = JSONValue.object([
                "kind": .string("commit"),
                "commit": .string(CommitReveal.commit(secret: layout, salt: salt))
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
            }
            sending = false
        }
    }

    // MARK: Battle

    /// Phone: stacked (scroll between the two grids). Wide regular panes:
    /// the DUEL table (roadmap 22) — enemy waters centered as the big
    /// board, own fleet always visible in the rail. No mid-battle scroll.
    private var battleScreen: some View {
        GameTableContainer(gameType: "battleship") { paneWidth in
            GameTableLayout(gameType: "battleship", paneWidth: paneWidth) {
                VStack(spacing: LayoutMetrics.s(14)) {
                    enemyWatersCard
                    if myTurn {
                        fireButton
                    } else {
                        GameWaitingHint()
                    }
                }
                .gameActGated()
            } rail: {
                VStack(spacing: LayoutMetrics.s(14)) {
                    turnHeader
                    myBoardCard
                    if myFleet == nil {
                        boardLostCard
                    }
                }
                .gameActGated()
            }
        } stacked: {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(14)) {
                    turnHeader
                    enemyWatersCard
                    if myTurn {
                        fireButton
                    } else {
                        GameWaitingHint()
                    }
                    myBoardCard
                    if myFleet == nil {
                        boardLostCard
                    }
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
            }
        }
    }

    private var turnHeader: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: myTurn ? "scope" : "hourglass")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                // "Your turn" glows in the ember — wax stays material on
                // night (3.2:1, Nacht-Regel).
                .foregroundStyle(myTurn ? Licht.glut : Nacht.sekundaer)
                .accessibilityHidden(true)
            Text(myTurn
                 ? L10n.t("games.bs.yourTurn")
                 : L10n.t("games.bs.partnerTurn", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Spacer(minLength: 0)
            Text(L10n.t("games.bs.hits", ["n": "\(gameState.hitCount(by: myId))",
                                          "total": "\(Battleship.fleetCellCount)"]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
        .nightCard(grain: false)
    }

    private var enemyWatersCard: some View {
        let results = gameState.shotResults(by: myId)
        return VStack(spacing: LayoutMetrics.s(10)) {
            HStack {
                Text(L10n.t("games.bs.enemy", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                Spacer()
                fleetChips(sunk: gameState.sunkSizes(by: myId))
            }
            boardGrid(shipCells: [], marks: marks(from: results), tappable: myTurn && !sending,
                      a11yLabel: L10n.t("games.bs.enemy", ["name": appState.partnerName]),
                      a11yValue: L10n.t("games.bs.hits",
                                        ["n": "\(gameState.hitCount(by: myId))",
                                         "total": "\(Battleship.fleetCellCount)"]))
            if myTurn {
                Text(L10n.t("games.bs.target.hint", ["n": "\(salvoTarget)"]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
        }
        .paperCard()
    }

    /// Shots this salvo may fire (fewer only when the board is nearly full).
    private var salvoTarget: Int {
        let unshot = Battleship.cellCount - gameState.shotCells(by: myId).count
        return min(Battleship.salvoSize, max(unshot, 0))
    }

    private var fireButton: some View {
        Button {
            fireSalvo()
        } label: {
            Text(L10n.t("games.bs.fire",
                        ["n": "\(targetCells.count)", "total": "\(salvoTarget)"]))
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(targetCells.count != salvoTarget || sending)
    }

    private var myBoardCard: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            HStack {
                Text(L10n.t("games.bs.mine"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                Spacer()
                fleetChips(sunk: gameState.sunkSizes(by: partnerId))
            }
            boardGrid(shipCells: Set((myFleet ?? []).flatMap { $0 }),
                      marks: marks(from: gameState.shotResults(by: partnerId)),
                      tappable: false, compact: true,
                      a11yLabel: L10n.t("games.bs.mine"),
                      a11yValue: L10n.t("games.bs.a11y.myBoardValue",
                                        ["hits": "\(gameState.hitCount(by: partnerId))"]))
        }
        .paperCard()
    }

    private var boardLostCard: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.bs.lost.title"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("games.bs.lost.body"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            Button {
                // Surrender contract (28#3): the bare `/end` this used to
                // send earned a 409 while the match was still unfinished.
                Task { _ = await engine.forfeit(api: appState.api) }
            } label: {
                Text(L10n.t("games.bs.lost.abandon"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.glut)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy)
        }
        .nightCard()
    }

    /// Sizes of the fleet, greyed + struck through once sunk.
    private func fleetChips(sunk: [Int]) -> some View {
        var remaining = sunk
        let chips: [(length: Int, isSunk: Bool)] = Battleship.fleet.map { length in
            if let at = remaining.firstIndex(of: length) {
                remaining.remove(at: at)
                return (length, true)
            }
            return (length, false)
        }
        return HStack(spacing: 5) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                Text("\(chip.length)")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .strikethrough(chip.isSunk)
                    .foregroundStyle(chip.isSunk ? Tinte.tertiaer : Tinte.sekundaer)
                    .frame(width: LayoutMetrics.s(20), height: LayoutMetrics.s(20))
                    .background(
                        Circle().fill(chip.isSunk
                                      ? Papier.innenFill
                                      : coupleTint.tinte.opacity(0.16))
                    )
            }
        }
    }

    // MARK: Grid rendering

    private enum CellMark {
        case hit, miss, pending
    }

    private func marks(from results: [Int: Bool?]) -> [Int: CellMark] {
        var marks: [Int: CellMark] = [:]
        for (cell, hit) in results {
            switch hit {
            case .some(true): marks[cell] = .hit
            case .some(false): marks[cell] = .miss
            case .none: marks[cell] = .pending
            }
        }
        return marks
    }

    /// Tappable boards stay containers so VoiceOver can walk the cell
    /// buttons ("Feld C4, noch unbeschossen"); read-only boards collapse
    /// into one element with a spoken summary.
    private func boardGrid(shipCells: Set<Int>, marks: [Int: CellMark],
                           tappable: Bool, compact: Bool = false,
                           a11yLabel: String = "", a11yValue: String = "") -> some View {
        VStack(spacing: LayoutMetrics.s(compact ? 3 : 4)) {
            ForEach(0..<Battleship.size, id: \.self) { row in
                HStack(spacing: LayoutMetrics.s(compact ? 3 : 4)) {
                    ForEach(0..<Battleship.size, id: \.self) { column in
                        cellView(cell: row * Battleship.size + column,
                                 isShip: shipCells.contains(row * Battleship.size + column),
                                 mark: marks[row * Battleship.size + column],
                                 tappable: tappable)
                    }
                }
            }
        }
        .padding(LayoutMetrics.s(compact ? 6 : 8))
        // The sea chart as a matte inner well on the paper card.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Papier.innenFill)
        )
        .accessibilityElement(children: tappable ? .contain : .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityValue(a11yValue)
    }

    @ViewBuilder
    private func cellView(cell: Int, isShip: Bool, mark: CellMark?, tappable: Bool) -> some View {
        let selected = targetCells.contains(cell)
        Button {
            toggleTarget(cell)
        } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(cellFill(isShip: isShip, mark: mark, selected: selected))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(selected ? Wachs.rot : Papier.kante,
                                      lineWidth: selected ? 2 : Theme.hairlineWidth)
                )
                .overlay(cellGlyph(isShip: isShip, mark: mark, selected: selected))
                .aspectRatio(1, contentMode: .fit)
                .animation(reduceMotion ? nil : Theme.Motion.settle, value: mark != nil)
        }
        .buttonStyle(.plain)
        .disabled(!tappable || mark != nil)
        .accessibilityLabel(L10n.t("games.bs.a11y.cell",
                                   ["cell": GamesA11y.battleshipCellName(cell)]))
        .accessibilityValue(cellA11yState(isShip: isShip, mark: mark, selected: selected))
    }

    private func cellA11yState(isShip: Bool, mark: CellMark?, selected: Bool) -> String {
        switch mark {
        case .hit: return L10n.t("games.bs.a11y.state.hit")
        case .miss: return L10n.t("games.bs.a11y.state.miss")
        case .pending: return L10n.t("games.bs.a11y.state.pending")
        case nil:
            if selected { return L10n.t("games.bs.a11y.state.selected") }
            if isShip { return L10n.t("games.bs.a11y.state.ship") }
            return L10n.t("games.bs.a11y.state.open")
        }
    }

    /// Cell fills on the paper sea chart: hits are wax-red stamps, misses
    /// matte wells, own ships the couple ink wash, open water blank paper.
    private func cellFill(isShip: Bool, mark: CellMark?, selected: Bool) -> Color {
        switch mark {
        case .hit: return Wachs.rot
        case .miss: return Papier.innenFill
        case .pending: return Tinte.sekundaer.opacity(0.25)
        case nil:
            if selected { return Wachs.rot.opacity(0.25) }
            return isShip ? coupleTint.tinte.opacity(0.30) : Papier.brief
        }
    }

    @ViewBuilder
    private func cellGlyph(isShip: Bool, mark: CellMark?, selected: Bool) -> some View {
        switch mark {
        case .hit:
            Text("💥").font(.system(.caption2, design: .rounded))
        case .miss:
            Circle().fill(Tinte.tertiaer)
                .frame(width: LayoutMetrics.s(5), height: LayoutMetrics.s(5))
        case .pending:
            Text("🎯").font(.system(.caption2, design: .rounded))
        case nil:
            if selected {
                Text("🎯").font(.system(.caption2, design: .rounded))
            } else if isShip {
                Text("🚢").font(.system(.caption2, design: .rounded))
            }
        }
    }

    // MARK: Actions

    private func toggleTarget(_ cell: Int) {
        guard myTurn, !sending else { return }
        if let at = targetCells.firstIndex(of: cell) {
            targetCells.remove(at: at)
        } else if targetCells.count < salvoTarget {
            targetCells.append(cell)
            Haptics.shared.tap()
        }
    }

    private func fireSalvo() {
        guard myTurn, !sending, targetCells.count == salvoTarget, !targetCells.isEmpty else { return }
        sending = true
        let cells = targetCells
        Task {
            let data = JSONValue.object([
                "kind": .string("salvo"),
                "cells": .array(cells.map { .number(Double($0)) })
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                targetCells = []
                SoundEngine.shared.play(.whoosh)
            }
            sending = false
        }
    }

    /// The defender side runs itself: answer the partner's newest salvo
    /// truthfully from the local fleet, and open the board once the game is
    /// decided. Both are idempotent (reducer keeps the FIRST report/reveal).
    private func autoRespond() {
        guard let session, session.state == "active" || session.state == "ended" else { return }
        let state = gameState
        // 1. Pending report on me?
        if session.state == "active",
           let index = state.pendingReportIndex(defender: myId),
           !sentReports.contains(index),
           let fleet = myFleet {
            sentReports.insert(index)
            let alreadyHit = Set(state.shotResults(by: partnerId)
                .filter { $0.value == true }.map(\.key))
            let salvo = state.salvos[index]
            let answer = Battleship.report(cells: salvo.cells, layout: fleet,
                                           alreadyHit: alreadyHit)
            Task {
                let data = JSONValue.object([
                    "kind": .string("report"),
                    "index": .number(Double(index)),
                    "hits": .array(answer.hits.map { .number(Double($0)) }),
                    "sunk": .array(answer.sunk.map { .number(Double($0)) })
                ])
                _ = await engine.sendMove(api: appState.api, data: data)
                if !answer.sunk.isEmpty {
                    SoundEngine.shared.play(.lose)
                    Haptics.shared.warning()
                } else if !answer.hits.isEmpty {
                    Haptics.shared.tap()
                }
            }
        }
        // 2. Game decided → open my board (commit-reveal proof).
        if state.phase == .finished, !didReveal, state.reveals[myId] == nil,
           let secret = BattleshipVault.load(gameId: session.id) {
            didReveal = true
            let commitId = engine.orderedMoves.first {
                $0.memberId == myId && $0.data["commit"]?.stringValue != nil
            }?.id
            Task {
                var object: [String: JSONValue] = [
                    "kind": .string("reveal"),
                    "reveal": .string(secret.layout),
                    "salt": .string(secret.salt)
                ]
                if let commitId {
                    object["commitId"] = .string(commitId)
                }
                _ = await engine.sendMove(api: appState.api, data: .object(object))
            }
        }
    }

    private func handleFinish() {
        guard session != nil else { return }
        autoRespond()
        if !celebrated {
            celebrated = true
            GamesA11y.announce(iWon
                ? L10n.t("games.bs.a11y.won", ["name": appState.partnerName])
                : L10n.t("games.bs.a11y.lost", ["name": appState.partnerName]))
            if iWon {
                GameEndCelebration.win(theme: .stars)
            } else {
                GameEndCelebration.loss()
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            var scores: [String: JSONValue] = [:]
            for id in [starterId, otherId] where !id.isEmpty {
                scores[id] = .number(gameState.winner == id ? 1 : 0)
            }
            await engine.end(api: appState.api, result: .object(["scores": .object(scores)]))
        }
    }

    // MARK: End screen

    private var endScreen: some View {
        let results = gameState.shotResults(by: myId)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: iWon ? "trophy.fill" : "heart.slash.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iWon ? Licht.lampengold : Nacht.sekundaer)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(iWon
                     ? L10n.t("games.bs.win.you")
                     : L10n.t("games.bs.win.partner", ["name": appState.partnerName]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                fairPlayBadge
                enemyWatersCard
                myBoardCard
                shareButton(results: results)
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

    /// Post-game verdict of the partner's reveal: relay hash certification +
    /// local hash check + legal layout + truthful reports.
    private var fairPlayBadge: some View {
        let verdict = fairPlayVerdict
        return HStack(spacing: 8) {
            Text(verdict.emoji)
            Text(verdict.text)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.leading)
        }
        .nightCard(grain: false)
    }

    private var fairPlayVerdict: (emoji: String, text: String) {
        guard let reveal = gameState.reveals[partnerId] else {
            return ("⏳", L10n.t("games.bs.fair.wait", ["name": appState.partnerName]))
        }
        let commit = engine.orderedMoves.first {
            $0.memberId == partnerId && $0.data["commit"]?.stringValue != nil
        }?.data["commit"]?.stringValue
        let hashOk = reveal.serverVerified
            || commit.map { CommitReveal.verify(reveal: reveal.layout,
                                                salt: reveal.salt, commit: $0) } == true
        let layout = Battleship.decodeLayout(reveal.layout)
        let legal = layout.map(Battleship.isValidLayout) == true
        let honest = layout.map {
            Battleship.honest(state: gameState, defender: partnerId, layout: $0)
        } == true
        if hashOk && legal && honest {
            return ("🛡️", L10n.t("games.bs.fair.ok"))
        }
        return ("🤨", L10n.t("games.bs.fair.bad", ["name": appState.partnerName]))
    }

    // MARK: Share to chat

    @ViewBuilder
    private func shareButton(results: [Int: Bool?]) -> some View {
        Button {
            shareToChat(results: results)
        } label: {
            Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                  systemImage: shared ? "checkmark.circle.fill" : "paperplane.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .padding(.horizontal, LayoutMetrics.s(18))
                .padding(.vertical, LayoutMetrics.s(10))
                // Night-card pill: quiet inner fill once shared, the
                // couple blend (computed ink) while the action is live.
                .background(Capsule().fill(shared
                                           ? AnyShapeStyle(Papier.nachtInnenFill)
                                           : AnyShapeStyle(coupleTint.blend)))
                .overlay {
                    if shared {
                        Capsule().strokeBorder(Nacht.naht,
                                               lineWidth: Theme.hairlineWidth)
                    }
                }
                .foregroundStyle(shared ? Nacht.sekundaer : coupleTint.onBlend)
        }
        .buttonStyle(.plain)
        .disabled(shared)
    }

    private func shareToChat(results: [Int: Bool?]) {
        guard let api = appState.api, !shared else { return }
        let winnerName = iWon ? (appState.me?.name ?? L10n.t("common.you")) : appState.partnerName
        let salvoCount = gameState.salvos.filter { $0.member == gameState.winner }.count
        let text = L10n.t("games.bs.share.line",
                          ["name": winnerName, "n": "\(salvoCount)"])
            + "\n" + Battleship.shareGrid(results: results)
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: text)
                shared = true
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}
