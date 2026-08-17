import SwiftUI
import Combine

// Kniffel-Liebesedition 🎲💘 — async-friendly seeded Yahtzee.
//
// The dice pips are a pure function of (seed, turn, roll) — see
// Content/KniffelLogic.swift — so a "roll" move carries only the held dice
// and both phones derive identical values. Turns alternate; each turn is up
// to 3 rolls plus one category pick on the love-styled scorecard.
struct KniffelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var heldDice: Set<Int> = []
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrated = false
    @State private var bounce = 0

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.kniffel.title"))
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
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: gameState.rollCount) { old, new in
            if new > old {
                bounce += 1
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
            if new == 0 {
                heldDice = []
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
        guard let current = engine.session, current.kind == .kniffel else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    private var theirId: String { myId == starterId ? otherId : starterId }

    private var events: [KniffelEvent] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "roll":
                let held = move.data["held"]?.arrayValue?.compactMap(\.intValue) ?? []
                return .roll(member: move.memberId, held: held)
            case "score":
                guard let category = move.data["category"]?.stringValue else { return nil }
                return .score(member: move.memberId, category: category)
            default:
                return nil
            }
        }
    }

    private var gameState: KniffelState {
        Kniffel.reduce(events: events, seed: engine.seed, starter: starterId, partner: otherId)
    }

    private var currentPlayer: String {
        Kniffel.player(turn: gameState.turnIndex, starter: starterId, partner: otherId)
    }

    private var myTurn: Bool { currentPlayer == myId && !gameState.finished }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.finished
    }

    private func name(of memberId: String) -> String {
        memberId == myId ? (appState.me?.name ?? L10n.t("common.you")) : appState.partnerName
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
                Image(systemName: "dice.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.kniffel.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.kn.setup.body"))
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
            if await engine.create(api: appState.api, type: .kniffel,
                                   payload: GameEngine.makePayload()) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        heldDice = []
        sending = false
        didSendEnd = false
        celebrated = false
    }

    // MARK: Play

    /// Phone: stacked (dice above the scorepad). Wide regular panes: the
    /// dice felt centered, turn + scorepad as the side rail (roadmap 22) —
    /// no more scrolling between the roll button and the categories.
    private var playScreen: some View {
        GameTableContainer(gameType: "kniffel") { paneWidth in
            GameTableLayout(gameType: "kniffel", paneWidth: paneWidth) {
                diceCard
                    .gameActGated()
            } rail: {
                VStack(spacing: LayoutMetrics.s(12)) {
                    turnHeader
                    if !myTurn {
                        GameWaitingHint()
                    }
                    scoreboard
                }
                .gameActGated()
            }
        } stacked: {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(12)) {
                    turnHeader
                    diceCard
                    if !myTurn {
                        GameWaitingHint()
                    }
                    scoreboard
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
            }
        }
    }

    private var turnHeader: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: myTurn ? "dice.fill" : "hourglass")
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(myTurn ? Licht.lampengold : Nacht.sekundaer)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(myTurn
                     ? L10n.t("games.kn.yourTurn")
                     : L10n.t("games.kn.partnerTurn", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("games.kn.turnMeta",
                            ["n": "\(gameState.turnIndex / 2 + 1)",
                             "total": "\(Kniffel.turnsPerPlayer)",
                             "rolls": "\(gameState.rollCount)",
                             "max": "\(Kniffel.maxRolls)"]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
    }

    private var diceCard: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(0..<Kniffel.diceCount, id: \.self) { index in
                    dieView(index: index)
                }
            }
            if myTurn {
                if gameState.rollCount > 0 && gameState.rollCount < Kniffel.maxRolls {
                    Text(L10n.t("games.kn.holdHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Tinte.tertiaer)
                }
                if gameState.rollCount < Kniffel.maxRolls {
                    Button {
                        roll()
                    } label: {
                        Text(L10n.t("games.kn.roll",
                                    ["n": "\(gameState.rollCount + 1)",
                                     "max": "\(Kniffel.maxRolls)"]))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending)
                }
                if gameState.rollCount > 0 {
                    Text(L10n.t("games.kn.pickHint"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Wachs.rot)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard()
    }

    @ViewBuilder
    private func dieView(index: Int) -> some View {
        let rolled = gameState.dice.indices.contains(index)
        let value = rolled ? gameState.dice[index] : 0
        let held = heldDice.contains(index)
        let canHold = myTurn && gameState.rollCount > 0 && gameState.rollCount < Kniffel.maxRolls
        Button {
            guard canHold else { return }
            if held {
                heldDice.remove(index)
            } else {
                heldDice.insert(index)
            }
            Haptics.shared.tap()
        } label: {
            ZStack {
                // Dice as paper tokens on the game plan: held ones wear
                // the stamp-pad red (5.2:1 on brief), free ones plain ink.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(held ? Wachs.rot.opacity(0.14) : Papier.innenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(held ? Wachs.rot : Papier.kante,
                                          lineWidth: held ? 2 : Theme.hairlineWidth)
                    )
                if rolled {
                    Image(systemName: "die.face.\(value).fill")
                        .font(.system(.largeTitle, design: .rounded))
                        .foregroundStyle(held ? Wachs.rot : Tinte.dunkel)
                        .symbolEffect(.bounce, value: bounce)
                } else {
                    Text("?")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Tinte.tertiaer)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .rotation3DEffect(.degrees(held ? 0 : Double(bounce % 2) * 360),
                              axis: (x: 0, y: 0, z: 1))
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: bounce)
        }
        .buttonStyle(.plain)
        .disabled(!canHold)
    }

    private func roll() {
        guard myTurn, !sending, gameState.rollCount < Kniffel.maxRolls else { return }
        sending = true
        let held = gameState.rollCount > 0 ? Array(heldDice).sorted() : []
        Task {
            let data = JSONValue.object([
                "kind": .string("roll"),
                "held": .array(held.map { .number(Double($0)) })
            ])
            _ = await engine.sendMove(api: appState.api, data: data)
            sending = false
        }
    }

    // MARK: Scoreboard

    private static let categoryEmoji: [KniffelCategory: String] = [
        .ones: "💌", .twos: "💐", .threes: "🥂", .fours: "🕯️", .fives: "💋", .sixes: "💍",
        .threeOfAKind: "🎯", .fourOfAKind: "🎪", .fullHouse: "🏡",
        .smallStraight: "🌈", .largeStraight: "🌠", .kniffel: "💘", .chance: "🎁",
    ]

    private var scoreboard: some View {
        let myCard = gameState.scorecard(of: myId)
        let theirCard = gameState.scorecard(of: theirId)
        return VStack(spacing: LayoutMetrics.s(4)) {
            scoreboardHeader
            ForEach(KniffelCategory.allCases, id: \.rawValue) { category in
                categoryRow(category, myCard: myCard, theirCard: theirCard)
            }
            Divider()
                .overlay(Papier.kante)
            summaryRow(label: L10n.t("games.kn.bonusRow"),
                       mine: bonusText(myCard), theirs: bonusText(theirCard))
            summaryRow(label: L10n.t("games.kn.totalRow"),
                       mine: "\(Kniffel.total(myCard))", theirs: "\(Kniffel.total(theirCard))",
                       bold: true)
        }
        // THE Kniffel-Zettel: the scorepad is the paper play area, each
        // column in its member's ink (inkOnPaper ladder, ≥4.5:1).
        .paperCard(grain: false)
    }

    private var scoreboardHeader: some View {
        HStack {
            Text(L10n.t("games.kn.categories"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.tertiaer)
            Spacer()
            Text(appState.me?.name ?? L10n.t("common.you"))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.tintePrimary)
                .frame(width: LayoutMetrics.s(52), alignment: .trailing)
            Text(appState.partnerName)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.tinteSecondary)
                .frame(width: LayoutMetrics.s(52), alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func categoryRow(_ category: KniffelCategory,
                             myCard: [KniffelCategory: Int],
                             theirCard: [KniffelCategory: Int]) -> some View {
        let banked = myCard[category]
        let pickable = myTurn && gameState.rollCount > 0 && banked == nil
        let potential = pickable ? category.score(dice: gameState.dice) : nil
        Button {
            if pickable { score(category) }
        } label: {
            HStack {
                Text("\(Self.categoryEmoji[category] ?? "") \(L10n.t("games.kn.cat.\(category.rawValue)"))")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.sekundaer)
                    .lineLimit(1)
                Spacer()
                Group {
                    if let banked {
                        Text("\(banked)")
                            .foregroundStyle(Tinte.dunkel)
                    } else if let potential {
                        // Legal pick preview — stamp-pad red, the paper
                        // sibling of the old gold hint.
                        Text("+\(potential)")
                            .foregroundStyle(Wachs.rot)
                    } else {
                        Text("–")
                            .foregroundStyle(Tinte.tertiaer)
                    }
                }
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .frame(width: LayoutMetrics.s(52), alignment: .trailing)
                Text(theirCard[category].map { "\($0)" } ?? "–")
                    .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(theirCard[category] == nil ? Tinte.tertiaer : Tinte.dunkel)
                    .frame(width: LayoutMetrics.s(52), alignment: .trailing)
            }
            .padding(.vertical, LayoutMetrics.s(5))
            .padding(.horizontal, LayoutMetrics.s(8))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(potential != nil ? Wachs.rot.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(!pickable || sending)
    }

    private func summaryRow(label: String, mine: String, theirs: String, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(bold ? .heavy : .semibold))
                .foregroundStyle(bold ? Tinte.dunkel : Tinte.sekundaer)
            Spacer()
            Text(mine)
                .font(.system(.caption, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(coupleTint.tintePrimary)
                .frame(width: LayoutMetrics.s(52), alignment: .trailing)
            Text(theirs)
                .font(.system(.caption, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(coupleTint.tinteSecondary)
                .frame(width: LayoutMetrics.s(52), alignment: .trailing)
        }
        .padding(.horizontal, LayoutMetrics.s(8))
        .padding(.vertical, 2)
    }

    private func bonusText(_ card: [KniffelCategory: Int]) -> String {
        let upper = Kniffel.upperSum(card)
        return upper >= Kniffel.upperBonusThreshold
            ? "+\(Kniffel.upperBonus)"
            : "\(upper)/\(Kniffel.upperBonusThreshold)"
    }

    private func score(_ category: KniffelCategory) {
        guard myTurn, !sending, gameState.rollCount > 0 else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("score"),
                "category": .string(category.rawValue)
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                heldDice = []
                SoundEngine.shared.play(.success)
                Haptics.shared.success()
            }
            sending = false
        }
    }

    // MARK: Finish

    private func handleFinish() {
        guard session != nil else { return }
        let winner = Kniffel.winner(state: gameState, starter: starterId, partner: otherId)
        if !celebrated {
            celebrated = true
            if winner == myId {
                GameEndCelebration.win()
            } else if winner == nil {
                GameEndCelebration.tie()
            } else {
                GameEndCelebration.loss()
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            var scores: [String: JSONValue] = [:]
            for id in [starterId, otherId] where !id.isEmpty {
                scores[id] = .number(Double(Kniffel.total(gameState.scorecard(of: id))))
            }
            await engine.end(api: appState.api, result: .object(["scores": .object(scores)]))
        }
    }

    private var endScreen: some View {
        let winner = Kniffel.winner(state: gameState, starter: starterId, partner: otherId)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: winner == myId ? "trophy.fill" : (winner == nil ? "heart.circle.fill" : "dice.fill"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(winner == myId ? Licht.lampengold : coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(endLine(winner: winner))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                scoreboard
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

    private func endLine(winner: String?) -> String {
        guard let winner else { return L10n.t("games.kn.tie") }
        if winner == myId { return L10n.t("games.kn.win.you") }
        return L10n.t("games.kn.win.partner", ["name": name(of: winner)])
    }
}
