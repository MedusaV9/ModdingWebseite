import SwiftUI

// MARK: - Emoji-Rätsel live 🧩📱📱 (realtime two-phone mode)
//
// Same riddles as the pass-and-play mode, but each partner plays on their
// own phone via the game-session relay (like the couple quiz):
// both see the same seeded deck, type a guess, and once both guesses are
// in the answer is revealed and each player honestly scores their own
// guess ("honor system").
//
// Move protocol:
// - `{"kind": "guess", "round": r, "value": "<free text>"}` (both members)
// - `{"kind": "claim", "round": r, "value": "right" | "wrong"}` (both members,
//   each judging their OWN guess)
//
// Create payload options (ints only, see GameEngine.makePayload):
// - "rounds": requested round count
// - "cats":   category bitmask over `EmojiRiddleLive.categories`
//             (bit i set = category i in play; 0 = all categories)

/// Reducer helpers over payload + moves, shared by the mode switch in
/// `EmojiRiddleView` and the live gameplay below. The pure deck derivation
/// lives in `EmojiRiddleDeck` (Content/ContentModels.swift) so the Linux
/// logic tests can cover it.
@MainActor
enum EmojiRiddleLive {
    /// Canonical category order — the "cats" bitmask indexes into this.
    static let categories = EmojiRiddleDeck.categories

    static func categoryMask(for selected: Set<String>) -> Int {
        EmojiRiddleDeck.categoryMask(for: selected)
    }

    /// Deterministic deck both clients derive from the create payload.
    static func deck(engine: GameEngine) -> [EmojiRiddle] {
        EmojiRiddleDeck.deck(seed: engine.seed,
                             mask: engine.payloadInt("cats", default: 0),
                             rounds: engine.payloadInt("rounds", default: 10))
    }

    /// Effective round count — never larger than the deck (small category
    /// pools may not fill the requested rounds).
    static func totalRounds(engine: GameEngine) -> Int {
        min(engine.payloadInt("rounds", default: 10), deck(engine: engine).count)
    }

    static func guess(engine: GameEngine, round: Int, by memberId: String) -> String? {
        engine.move(kind: "guess", round: round, by: memberId)?.data["value"]?.stringValue
    }

    static func claim(engine: GameEngine, round: Int, by memberId: String) -> String? {
        engine.move(kind: "claim", round: round, by: memberId)?.data["value"]?.stringValue
    }

    /// A round is done once BOTH members judged their own guess.
    static func roundComplete(engine: GameEngine, round: Int, memberIds: [String]) -> Bool {
        guard memberIds.count == 2 else { return false }
        return memberIds.allSatisfy { claim(engine: engine, round: round, by: $0) != nil }
    }

    /// First round without both claims; equals totalRounds when done.
    static func currentRound(engine: GameEngine, memberIds: [String]) -> Int {
        let total = totalRounds(engine: engine)
        for round in 0..<total where !roundComplete(engine: engine, round: round, memberIds: memberIds) {
            return round
        }
        return total
    }

    static func finished(engine: GameEngine, memberIds: [String]) -> Bool {
        let total = totalRounds(engine: engine)
        return total > 0 && currentRound(engine: engine, memberIds: memberIds) >= total
    }

    static func score(engine: GameEngine, memberId: String) -> Int {
        var total = 0
        for round in 0..<totalRounds(engine: engine)
        where claim(engine: engine, round: round, by: memberId) == "right" {
            total += 1
        }
        return total
    }
}

/// Gameplay content for a live emoji-riddle session. The hosting
/// `EmojiRiddleView` owns background, navigation title, event forwarding
/// and the mode switch — this view only renders the session.
struct EmojiRiddleLiveView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    @State private var guessText = ""
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrate = false
    @State private var sharing = false
    @State private var shared = false

    var body: some View {
        ZStack {
            content
            if celebrate && !reduceMotion {
                FloatingHeartsView(emojis: ["🧩", "🎉", "💖", "✨", "🏆"], count: 20)
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
        guard let current = engine.session, current.kind == .emojiriddle else { return nil }
        return current
    }

    private var sortedMemberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var deck: [EmojiRiddle] {
        EmojiRiddleLive.deck(engine: engine)
    }

    private var totalRounds: Int {
        EmojiRiddleLive.totalRounds(engine: engine)
    }

    private var currentRound: Int {
        guard session != nil else { return 0 }
        return EmojiRiddleLive.currentRound(engine: engine, memberIds: sortedMemberIds)
    }

    private var finished: Bool {
        session != nil && EmojiRiddleLive.finished(engine: engine, memberIds: sortedMemberIds)
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
                    GameLobbyView(engine: engine, accent: Theme.gold)
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
                                tint: coupleTint.blend,
                                track: Papier.nachtInnenFill)
                roundCard
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var scoreHeader: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            scoreBadge(memberId: appState.memberId, alignment: .leading)
            Spacer()
            PillTag(text: L10n.t("games.round",
                                 ["n": String(min(currentRound + 1, totalRounds)),
                                  "total": String(totalRounds)]),
                    tint: coupleTint.blend)
            Spacer()
            scoreBadge(memberId: appState.partner?.id, alignment: .trailing)
        }
        .nightCard(grain: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.a11y.score"))
        .accessibilityValue(L10n.t("games.a11y.scoreValue",
                                   ["mine": "\(myScore)",
                                    "name": appState.partnerName,
                                    "theirs": "\(partnerScore)"])
                            + ", " + L10n.t("games.round",
                                            ["n": String(min(currentRound + 1, totalRounds)),
                                             "total": String(totalRounds)]))
    }

    private func scoreBadge(memberId: String?, alignment: HorizontalAlignment) -> some View {
        let member = appState.couple?.members.first { $0.id == memberId }
        let points = memberId.map { EmojiRiddleLive.score(engine: engine, memberId: $0) } ?? 0
        return HStack(spacing: 8) {
            if alignment == .leading {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
            Text("\(points)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Licht.lampengold)
            if alignment == .trailing {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
        }
    }

    @ViewBuilder
    private var roundCard: some View {
        let round = currentRound
        if round < totalRounds, round < deck.count {
            let riddle = deck[round]
            VStack(spacing: LayoutMetrics.s(16)) {
                VStack(spacing: LayoutMetrics.s(16)) {
                    PaperTag(text: L10n.t("games.emoji.cat.\(riddle.category)"))
                    Text(riddle.emojis)
                        .font(.system(.largeTitle, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineSpacing(8)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("games.emoji.cat.\(riddle.category)") + ". "
                                    + L10n.t("games.emoji.a11y.riddle", ["emojis": riddle.emojis]))
                phaseContent(round: round, riddle: riddle)
            }
            .frame(maxWidth: .infinity)
            .paperCard()
        }
    }

    @ViewBuilder
    private func phaseContent(round: Int, riddle: EmojiRiddle) -> some View {
        let myId = appState.memberId ?? ""
        let partnerId = appState.partner?.id ?? ""
        let myGuess = EmojiRiddleLive.guess(engine: engine, round: round, by: myId)
        let partnerGuess = EmojiRiddleLive.guess(engine: engine, round: round, by: partnerId)
        if myGuess == nil {
            guessInput(round: round)
        } else if partnerGuess == nil {
            VStack(spacing: LayoutMetrics.s(10)) {
                guessBubble(label: L10n.t("games.emoji.live.guessed"),
                            text: myGuess ?? "",
                            tint: Tinte.sekundaer)
                GameWaitingHint(onPaper: true)
            }
        } else {
            revealSection(round: round, riddle: riddle,
                          myGuess: myGuess ?? "", partnerGuess: partnerGuess ?? "")
        }
    }

    /// Guess line ON the paper card: an inner writing well (matte fill +
    /// kante hairline — DreamyFieldStyle is night-tuned) and a send stamp
    /// in the couple ink (Quiz pattern).
    private func guessInput(round: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                TextField(L10n.t("games.emoji.live.guessPlaceholder"), text: $guessText, axis: .vertical)
                    .font(Typo.body)
                    .foregroundStyle(Tinte.dunkel)
                    .lineLimit(1...3)
                    .padding(.vertical, LayoutMetrics.s(13))
                    .padding(.horizontal, LayoutMetrics.s(16))
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.innenFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth)
                    )
                Button {
                    submitGuess(round: round)
                } label: {
                    if sending {
                        ProgressView()
                            .tint(Papier.brief)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.brief)
                    }
                }
                .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                .background(Circle().fill(coupleTint.tinte))
                .disabled(sending || guessText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(L10n.t("games.a11y.sendGuess"))
            }
            Text(L10n.t("games.emoji.live.guessHint"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func revealSection(round: Int, riddle: EmojiRiddle,
                               myGuess: String, partnerGuess: String) -> some View {
        let myId = appState.memberId ?? ""
        let myClaim = EmojiRiddleLive.claim(engine: engine, round: round, by: myId)
        VStack(spacing: LayoutMetrics.s(12)) {
            // The answer wears the stamp-pad red, the two guesses plain
            // inks — all readable washes on the paper card.
            guessBubble(label: L10n.t("games.emoji.live.answerLabel"),
                        text: riddle.answer.resolved(L10n.lang),
                        tint: Wachs.rot)
            guessBubble(label: L10n.t("games.emoji.live.myGuess"),
                        text: myGuess, tint: coupleTint.tinte)
            guessBubble(label: L10n.t("games.emoji.live.partnerGuess",
                                      ["name": appState.partnerName]),
                        text: partnerGuess, tint: Tinte.sekundaer)
            if myClaim == nil {
                claimButtons(round: round)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .tint(coupleTint.tinte)
                    Text(L10n.t("games.emoji.live.waitClaim", ["name": appState.partnerName]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                }
            }
        }
        // The reveal section appears once both guesses are in — speak the
        // answer so VoiceOver players hear the resolution immediately.
        .onAppear {
            GamesA11y.announce(L10n.t("games.emoji.a11y.answer",
                                      ["answer": riddle.answer.resolved(L10n.lang)]))
        }
    }

    private func claimButtons(round: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.emoji.live.claimQuestion"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.dunkel)
            HStack(spacing: LayoutMetrics.s(10)) {
                Button {
                    submitClaim(round: round, value: "right")
                } label: {
                    Text(L10n.t("games.emoji.live.claimYes"))
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    submitClaim(round: round, value: "wrong")
                } label: {
                    Text(L10n.t("games.emoji.live.claimNo"))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(sending)
            Text(L10n.t("games.emoji.live.honor"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
                .multilineTextAlignment(.center)
        }
    }

    private func guessBubble(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutMetrics.s(12))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    // MARK: Actions

    private func submitGuess(round: Int) {
        let text = guessText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task {
            let data = GameEngine.moveData(kind: "guess", round: round, value: text)
            if await engine.sendMove(api: appState.api, data: data) {
                guessText = ""
                SoundEngine.shared.play(.pop)
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
                if value == "right" {
                    SoundEngine.shared.play(.sparkle)
                    Haptics.shared.success()
                } else {
                    Haptics.shared.tap()
                }
            }
            sending = false
        }
    }

    private func resetLocalState() {
        guessText = ""
        sending = false
        didSendEnd = false
        celebrate = false
        sharing = false
        shared = false
    }

    private func handleRoundAdvance(from old: Int, to new: Int) {
        guard new > old, old < totalRounds, new < totalRounds else { return }
        SoundEngine.shared.play(.whoosh)
    }

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrate {
            celebrate = true
            if myScore > partnerScore {
                GameEndCelebration.win(visual: .localHearts)
            } else if myScore == partnerScore {
                GameEndCelebration.tie(visual: .localHearts)
            } else {
                GameEndCelebration.loss(visual: .localHearts)
            }
            GamesA11y.announce(endTitle + ". "
                               + L10n.t("games.a11y.scoreValue",
                                        ["mine": "\(myScore)",
                                         "name": appState.partnerName,
                                         "theirs": "\(partnerScore)"]))
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    /// Same shape as the quiz result, so the scoreboard can reuse its path.
    private var resultJSON: JSONValue {
        var scores: [String: JSONValue] = [:]
        for id in sortedMemberIds {
            scores[id] = .number(Double(EmojiRiddleLive.score(engine: engine, memberId: id)))
        }
        return .object(["scores": .object(scores)])
    }

    // MARK: End screen

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: isTie ? "heart.circle.fill" : "trophy.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTie ? coupleTint.blend : Licht.lampengold)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(endTitle)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                finalScoreRow
                shareButton
                Button {
                    rematch()
                } label: {
                    Text(L10n.t("games.emoji.rematch"))
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

    // MARK: Share to chat

    @ViewBuilder
    private var shareButton: some View {
        if appState.api != nil {
            Button {
                shareToChat()
            } label: {
                if sharing {
                    ProgressView()
                        .tint(Nacht.sekundaer)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Licht.lampengold)
            .disabled(sharing || shared)
        }
    }

    /// Posts the final score into the couple chat (Wordle/ToD pattern).
    private var shareText: String {
        let header = L10n.t("games.share.header",
                            ["game": "🧩 " + L10n.t("games.emoji.title")])
        let myName = appState.me?.name ?? L10n.t("common.you")
        let scoreLine = "\(myName) \(myScore) : \(partnerScore) \(appState.partnerName)"
        return header + "\n" + scoreLine + "\n" + endTitle
    }

    private func shareToChat() {
        guard let api = appState.api, !sharing, !shared else { return }
        sharing = true
        Haptics.shared.tap()
        let text = shareText
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                shared = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharing = false
        }
    }

    private var myScore: Int {
        appState.memberId.map { EmojiRiddleLive.score(engine: engine, memberId: $0) } ?? 0
    }

    private var partnerScore: Int {
        appState.partner.map { EmojiRiddleLive.score(engine: engine, memberId: $0.id) } ?? 0
    }

    private var isTie: Bool { myScore == partnerScore }

    private var endTitle: String {
        if isTie { return L10n.t("games.emoji.tie") }
        let winner = myScore > partnerScore
            ? (appState.me?.name ?? L10n.t("common.you"))
            : appState.partnerName
        return L10n.t("games.emoji.winner", ["name": winner])
    }

    private var finalScoreRow: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            endScoreColumn(member: appState.me, points: myScore)
            Text(":")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Nacht.tertiaer)
            endScoreColumn(member: appState.partner, points: partnerScore)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.a11y.score"))
        .accessibilityValue(L10n.t("games.a11y.scoreValue",
                                   ["mine": "\(myScore)",
                                    "name": appState.partnerName,
                                    "theirs": "\(partnerScore)"]))
    }

    private func endScoreColumn(member: Member?, points: Int) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(46))
            Text("\(points)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(Papier.aufNacht)
            Text(member?.name ?? "–")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
    }

    private func rematch() {
        guard !engine.busy else { return }
        let rounds = engine.payloadInt("rounds", default: 10)
        let cats = engine.payloadInt("cats", default: 0)
        Task {
            resetLocalState()
            let payload = GameEngine.makePayload(options: ["rounds": rounds, "cats": cats])
            if await engine.create(api: appState.api, type: .emojiriddle, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }
}
