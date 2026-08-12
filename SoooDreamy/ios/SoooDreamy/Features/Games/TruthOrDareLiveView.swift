import SwiftUI

// MARK: - Wahrheit oder Pflicht live 🎭📱📱 (realtime two-phone mode)
//
// Same card pack as the pass-and-play mode, but each partner plays on their
// own phone via the game-session relay (like the emoji riddles): the turns
// alternate — whoever is up picks truth or dare, BOTH phones reveal the
// identical card (seeded decks), and the active player closes the round
// with "done" or "skip".
//
// Move protocol (only the round's ACTIVE member moves):
// - `{"kind": "pick",  "round": r, "value": "truth" | "dare"}`
// - `{"kind": "claim", "round": r, "value": "done" | "skip"}`
//
// Create payload options (ints only, see GameEngine.makePayload):
// - "rounds": number of cards in the session
// - "spice":  max spice level (1...3), same scale as the solo mode

/// Reducer helpers over payload + moves, shared by the mode switch in
/// `TruthOrDareView` and the live gameplay below. Everything is derived
/// deterministically, so both phones always agree on turn, card and score.
@MainActor
enum TruthOrDareLive {
    /// Cards per live session (turns alternate → half each).
    static let defaultRounds = 10

    /// Skip budget per player, mirroring the pass-and-play mode.
    static let maxSkips = 3

    static func totalRounds(engine: GameEngine) -> Int {
        max(engine.payloadInt("rounds", default: defaultRounds), 1)
    }

    static func spice(engine: GameEngine) -> Int {
        min(max(engine.payloadInt("spice", default: 2), 1), 3)
    }

    /// The member doing this round's truth/dare — turns alternate, the
    /// shared seed decides who starts so it isn't always the same partner.
    static func activeMemberId(engine: GameEngine, round: Int, memberIds: [String]) -> String? {
        guard memberIds.count == 2 else { return nil }
        return memberIds[(engine.seed + round) % 2]
    }

    /// "truth" | "dare" picked by the round's active member (nil = not yet).
    static func pick(engine: GameEngine, round: Int, memberIds: [String]) -> String? {
        guard let active = activeMemberId(engine: engine, round: round, memberIds: memberIds) else {
            return nil
        }
        return engine.move(kind: "pick", round: round, by: active)?.data["value"]?.stringValue
    }

    /// "done" | "skip" claimed by the round's active member (nil = not yet).
    static func claim(engine: GameEngine, round: Int, memberIds: [String]) -> String? {
        guard let active = activeMemberId(engine: engine, round: round, memberIds: memberIds) else {
            return nil
        }
        return engine.move(kind: "claim", round: round, by: active)?.data["value"]?.stringValue
    }

    /// Deterministic per-kind card deck both clients derive from the create
    /// payload (offset seed so truth and dare orders are unrelated).
    static func deck(engine: GameEngine, isDare: Bool) -> [TruthOrDareItem] {
        let level = spice(engine: engine)
        let pool = ContentPack.truthOrDare.filter { $0.isDare == isDare && $0.spice <= level }
        return pool.seededShuffled(seed: engine.seed &+ (isDare ? 1 : 0))
    }

    /// Both phones show the same card: the n-th "truth" pick reveals the
    /// n-th card of the truth deck (wrapping when exhausted), same for dares.
    static func card(engine: GameEngine, round: Int, memberIds: [String]) -> TruthOrDareItem? {
        guard let value = pick(engine: engine, round: round, memberIds: memberIds) else {
            return nil
        }
        var index = 0
        for previous in 0..<round
        where pick(engine: engine, round: previous, memberIds: memberIds) == value {
            index += 1
        }
        let cards = deck(engine: engine, isDare: value == "dare")
        guard !cards.isEmpty else { return nil }
        return cards[index % cards.count]
    }

    /// A round is done once the active player claimed done or skip.
    static func roundComplete(engine: GameEngine, round: Int, memberIds: [String]) -> Bool {
        claim(engine: engine, round: round, memberIds: memberIds) != nil
    }

    /// First round without a claim; equals totalRounds when done.
    static func currentRound(engine: GameEngine, memberIds: [String]) -> Int {
        let total = totalRounds(engine: engine)
        for round in 0..<total where !roundComplete(engine: engine, round: round, memberIds: memberIds) {
            return round
        }
        return total
    }

    static func finished(engine: GameEngine, memberIds: [String]) -> Bool {
        guard memberIds.count == 2 else { return false }
        return currentRound(engine: engine, memberIds: memberIds) >= totalRounds(engine: engine)
    }

    /// Completed cards ("done" claims) of one member.
    static func score(engine: GameEngine, memberId: String, memberIds: [String]) -> Int {
        claimCount(engine: engine, memberId: memberId, memberIds: memberIds, value: "done")
    }

    /// Used skips of one member (each player has `maxSkips`).
    static func skipsUsed(engine: GameEngine, memberId: String, memberIds: [String]) -> Int {
        claimCount(engine: engine, memberId: memberId, memberIds: memberIds, value: "skip")
    }

    private static func claimCount(engine: GameEngine, memberId: String,
                                   memberIds: [String], value: String) -> Int {
        var total = 0
        for round in 0..<totalRounds(engine: engine)
        where activeMemberId(engine: engine, round: round, memberIds: memberIds) == memberId
            && claim(engine: engine, round: round, memberIds: memberIds) == value {
            total += 1
        }
        return total
    }
}

/// Gameplay content for a live truth-or-dare session. The hosting
/// `TruthOrDareView` owns background, navigation title, event forwarding
/// and the mode switch — this view only renders the session.
struct TruthOrDareLiveView: View {
    @Environment(AppState.self) private var appState

    let engine: GameEngine

    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrate = false

    var body: some View {
        ZStack {
            content
            if celebrate {
                FloatingHeartsView(emojis: ["🎭", "🔥", "💖", "✨", "🏆"], count: 20)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: currentRound) { old, new in
            handleRoundAdvance(from: old, to: new)
        }
        .onChange(of: finished) { _, isDone in
            if isDone { handleFinish() }
        }
        .onAppear {
            if finished { handleFinish() }
        }
    }

    // MARK: Derived state (pure reducer over payload + moves)

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .truthordare else { return nil }
        return current
    }

    private var sortedMemberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var totalRounds: Int {
        TruthOrDareLive.totalRounds(engine: engine)
    }

    private var currentRound: Int {
        guard session != nil else { return 0 }
        return TruthOrDareLive.currentRound(engine: engine, memberIds: sortedMemberIds)
    }

    private var finished: Bool {
        session != nil && TruthOrDareLive.finished(engine: engine, memberIds: sortedMemberIds)
    }

    private var activeMemberId: String? {
        TruthOrDareLive.activeMemberId(engine: engine, round: currentRound, memberIds: sortedMemberIds)
    }

    private var isMyTurn: Bool {
        activeMemberId != nil && activeMemberId == appState.memberId
    }

    private var activeMember: Member? {
        appState.couple?.members.first { $0.id == activeMemberId }
    }

    private func name(of memberId: String?) -> String {
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
                    GameLobbyView(engine: engine, accent: Theme.rose)
                        .padding(LayoutMetrics.s(16))
                }
            } else if finished {
                endScreen
            } else {
                playScreen
            }
        }
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader
                GameProgressBar(progress: Double(currentRound) / Double(max(totalRounds, 1)),
                                tint: Theme.rose)
                turnCard
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    private var scoreHeader: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            scoreBadge(memberId: appState.memberId, alignment: .leading)
            Spacer()
            PillTag(text: L10n.t("games.round",
                                 ["n": String(min(currentRound + 1, totalRounds)),
                                  "total": String(totalRounds)]),
                    tint: Theme.purple)
            Spacer()
            scoreBadge(memberId: appState.partner?.id, alignment: .trailing)
        }
        .glassCard(padding: 12)
    }

    private func scoreBadge(memberId: String?, alignment: HorizontalAlignment) -> some View {
        let member = appState.couple?.members.first { $0.id == memberId }
        let points = memberId.map {
            TruthOrDareLive.score(engine: engine, memberId: $0, memberIds: sortedMemberIds)
        } ?? 0
        return HStack(spacing: 8) {
            if alignment == .leading {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
            Text("\(points)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.rose)
            if alignment == .trailing {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
        }
    }

    @ViewBuilder
    private var turnCard: some View {
        let round = currentRound
        if round < totalRounds {
            VStack(spacing: LayoutMetrics.s(16)) {
                EmojiAvatarView(emoji: activeMember?.avatar,
                                colorHex: activeMember?.color,
                                size: LayoutMetrics.s(56))
                Text(L10n.t("games.tod.turn", ["name": name(of: activeMemberId)]))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                phaseContent(round: round)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 18)
        }
    }

    @ViewBuilder
    private func phaseContent(round: Int) -> some View {
        if let card = TruthOrDareLive.card(engine: engine, round: round, memberIds: sortedMemberIds) {
            cardSection(round: round, card: card)
        } else if isMyTurn {
            pickSection(round: round)
        } else {
            waitingHint(text: L10n.t("games.tod.live.partnerPicking",
                                     ["name": appState.partnerName]))
        }
    }

    private func waitingHint(text: String) -> some View {
        VStack(spacing: 6) {
            ProgressView()
                .tint(Theme.pink)
            Text(text)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 6)
    }

    // MARK: Pick phase (active player chooses truth or dare)

    private func pickSection(round: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.tod.pickPrompt"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: LayoutMetrics.s(12)) {
                pickButton(round: round, isDare: false)
                pickButton(round: round, isDare: true)
            }
            .disabled(sending)
        }
    }

    private func pickButton(round: Int, isDare: Bool) -> some View {
        Button {
            submitPick(round: round, isDare: isDare)
        } label: {
            VStack(spacing: 8) {
                Text(isDare ? "💋" : "💬")
                    .font(.scaled(34))
                Text(L10n.t(isDare ? "games.tod.dare" : "games.tod.truth"))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(22))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isDare ? dareGradient : truthGradient)
            )
            .shadow(color: (isDare ? Theme.pink : Theme.indigo).opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var truthGradient: LinearGradient {
        LinearGradient(colors: [Theme.blue, Theme.purple],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var dareGradient: LinearGradient {
        LinearGradient(colors: [Theme.rose, Theme.pink],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Card phase (both see the card, active player claims done/skip)

    private func cardSection(round: Int, card: TruthOrDareItem) -> some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Text(isMyTurn
                 ? L10n.t("games.tod.live.yourCard")
                 : L10n.t("games.tod.live.partnerCard", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            cardFace(card)
                .id(round)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            if isMyTurn {
                claimButtons(round: round)
            } else {
                waitingHint(text: L10n.t("games.tod.live.partnerDoing",
                                         ["name": appState.partnerName]))
            }
        }
    }

    private func cardFace(_ card: TruthOrDareItem) -> some View {
        VStack(spacing: LayoutMetrics.s(16)) {
            HStack {
                PillTag(text: L10n.t(card.isDare ? "games.tod.dare" : "games.tod.truth"),
                        tint: .black.opacity(0.5))
                Spacer()
                Text(String(repeating: "🌶️", count: card.spice))
                    .font(.scaled(15))
            }
            Spacer()
            Text(card.text.resolved(L10n.lang))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(LayoutMetrics.s(20))
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(240))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(card.isDare ? dareGradient : truthGradient)
        )
        .shadow(color: (card.isDare ? Theme.pink : Theme.indigo).opacity(0.5), radius: 18, y: 8)
    }

    private func claimButtons(round: Int) -> some View {
        let memberId = appState.memberId ?? ""
        let skipsLeft = TruthOrDareLive.maxSkips
            - TruthOrDareLive.skipsUsed(engine: engine, memberId: memberId, memberIds: sortedMemberIds)
        return VStack(spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                Button {
                    submitClaim(round: round, value: "skip")
                } label: {
                    Text(L10n.t("games.tod.skip"))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(sending || skipsLeft <= 0)
                .opacity(skipsLeft <= 0 ? 0.4 : 1)
                Button {
                    submitClaim(round: round, value: "done")
                } label: {
                    Text(L10n.t("games.tod.done"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending)
            }
            Text(L10n.t("games.tod.skipsLeft", ["n": String(max(skipsLeft, 0))]))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Actions

    private func submitPick(round: Int, isDare: Bool) {
        guard !sending else { return }
        sending = true
        Task {
            let data = GameEngine.moveData(kind: "pick", round: round,
                                           value: isDare ? "dare" : "truth")
            if await engine.sendMove(api: appState.api, data: data) {
                SoundEngine.shared.play(.whoosh)
                Haptics.shared.tap()
            }
            sending = false
        }
    }

    private func submitClaim(round: Int, value: String) {
        guard !sending else { return }
        sending = true
        Task {
            let data = GameEngine.moveData(kind: "claim", round: round, value: value)
            if await engine.sendMove(api: appState.api, data: data) {
                if value == "done" {
                    SoundEngine.shared.play(.chime)
                    Haptics.shared.success()
                } else {
                    SoundEngine.shared.play(.pop)
                    Haptics.shared.warning()
                }
            }
            sending = false
        }
    }

    private func resetLocalState() {
        sending = false
        didSendEnd = false
        celebrate = false
    }

    private func handleRoundAdvance(from old: Int, to new: Int) {
        guard new > old, old < totalRounds, new < totalRounds else { return }
        SoundEngine.shared.play(.whoosh)
    }

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrate {
            celebrate = true
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    /// Same shape as the quiz result ("scores" per member = completed cards),
    /// so a future scoreboard integration can reuse that path.
    private var resultJSON: JSONValue {
        var scores: [String: JSONValue] = [:]
        for id in sortedMemberIds {
            scores[id] = .number(Double(TruthOrDareLive.score(engine: engine, memberId: id,
                                                              memberIds: sortedMemberIds)))
        }
        return .object(["scores": .object(scores)])
    }

    // MARK: End screen

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(isTie ? "💞" : "🏆")
                    .font(.scaled(60))
                Text(endTitle)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("games.tod.live.finalScore"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                finalScoreRow
                Button {
                    rematch()
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private var myScore: Int {
        appState.memberId.map {
            TruthOrDareLive.score(engine: engine, memberId: $0, memberIds: sortedMemberIds)
        } ?? 0
    }

    private var partnerScore: Int {
        appState.partner.map {
            TruthOrDareLive.score(engine: engine, memberId: $0.id, memberIds: sortedMemberIds)
        } ?? 0
    }

    private var isTie: Bool { myScore == partnerScore }

    private var endTitle: String {
        if isTie { return L10n.t("games.tod.live.tie") }
        let winner = myScore > partnerScore
            ? (appState.me?.name ?? L10n.t("common.you"))
            : appState.partnerName
        return L10n.t("games.tod.live.winner", ["name": winner])
    }

    private var finalScoreRow: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            endScoreColumn(member: appState.me, points: myScore)
            Text(":")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textTertiary)
            endScoreColumn(member: appState.partner, points: partnerScore)
        }
    }

    private func endScoreColumn(member: Member?, points: Int) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(46))
            Text("\(points)")
                .font(.scaled(44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.rose)
            Text(member?.name ?? "–")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func rematch() {
        guard !engine.busy else { return }
        let rounds = TruthOrDareLive.totalRounds(engine: engine)
        let spice = TruthOrDareLive.spice(engine: engine)
        Task {
            resetLocalState()
            let payload = GameEngine.makePayload(options: ["rounds": rounds, "spice": spice])
            if await engine.create(api: appState.api, type: .truthordare, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }
}
