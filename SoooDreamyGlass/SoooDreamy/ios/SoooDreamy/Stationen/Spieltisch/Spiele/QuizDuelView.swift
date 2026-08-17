import SwiftUI
import Combine

/// Liebes-Quiz-Duell ⚡️ — buzzer trivia on two phones.
///
/// Both partners see the SAME question (seeded deck) and race: the answer
/// that reaches the server first AND is correct scores 2 points, a later
/// correct answer still gets 1, wrong answers get nothing. Scoring reduces
/// over the moves in server-arrival order (`QuizDuel.scores`,
/// Content/CoupleGamesLogic.swift, pinned by the Linux logic tests).
///
/// Move protocol: `{"kind": "answer", "round": r, "option": 0…2}`.
struct QuizDuelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var sending = false
    @State private var setupRounds = 10
    @State private var didSendEnd = false
    @State private var celebrate = false

    private static let roundOptions = [6, 10, 14]

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if celebrate {
                FloatingHeartsView(emojis: ["⚡️", "🏆", "💖", "✨", "🎉"], count: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.quizduel.title"))
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

    // MARK: Derived state

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .quizduel else { return nil }
        return current
    }

    private var totalRounds: Int { engine.payloadInt("rounds", default: QuizDuel.defaultRounds) }

    private var memberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var deck: [DuelQuestion] {
        QuizDuel.deck(seed: engine.seed, rounds: totalRounds)
    }

    /// Answers in server-arrival order — the buzzer ranking.
    private var answers: [(memberId: String, round: Int, option: Int)] {
        engine.moves(kind: "answer").compactMap { move in
            guard let round = move.data["round"]?.intValue,
                  let option = move.data["option"]?.intValue else { return nil }
            return (move.memberId, round, option)
        }
    }

    private var currentRound: Int {
        guard session != nil else { return 0 }
        let all = answers
        for round in 0..<min(totalRounds, deck.count)
        where !QuizDuel.bothAnswered(answers: all, round: round, members: memberIds) {
            return round
        }
        return min(totalRounds, deck.count)
    }

    private var finished: Bool {
        guard session != nil, !deck.isEmpty else { return false }
        return currentRound >= min(totalRounds, deck.count)
    }

    private var scores: [String: Int] {
        QuizDuel.scores(answers: answers, deck: deck)
    }

    private func score(for memberId: String) -> Int { scores[memberId] ?? 0 }

    private func myAnswer(round: Int) -> Int? {
        guard let myId = appState.memberId else { return nil }
        return answers.first { $0.memberId == myId && $0.round == round }?.option
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
                Image(systemName: "bolt.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.quizduel.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.duel.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                roundsPicker
                Button {
                    startGame(rounds: setupRounds)
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

    private var roundsPicker: some View {
        VStack(spacing: 8) {
            Text(L10n.t("games.duel.setup.rounds"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Self.roundOptions, id: \.self) { option in
                    Button {
                        setupRounds = option
                        Haptics.shared.tap()
                    } label: {
                        Text("\(option)")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(setupRounds == option
                                             ? coupleTint.onBlend : Papier.aufNacht)
                            .frame(width: LayoutMetrics.s(56), height: LayoutMetrics.s(44))
                            .background(
                                Capsule().fill(setupRounds == option
                                               ? AnyShapeStyle(coupleTint.blend)
                                               : AnyShapeStyle(Papier.nachtInnenFill))
                            )
                            .overlay(
                                Capsule().strokeBorder(Nacht.naht,
                                                       lineWidth: Theme.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func startGame(rounds: Int) {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            let payload = GameEngine.makePayload(options: ["rounds": rounds])
            if await engine.create(api: appState.api, type: .quizduel, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        sending = false
        didSendEnd = false
        celebrate = false
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader
                GameProgressBar(progress: Double(currentRound) / Double(max(totalRounds, 1)),
                                tint: coupleTint.blend,
                                track: Papier.nachtInnenFill)
                lastRoundBanner
                roundCard
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
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
    }

    private func scoreBadge(memberId: String?, alignment: HorizontalAlignment) -> some View {
        let member = appState.couple?.members.first { $0.id == memberId }
        let points = memberId.map { score(for: $0) } ?? 0
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

    /// Recap of the previous round: who buzzed the 2 points, the correct
    /// answer, and my own verdict.
    @ViewBuilder
    private var lastRoundBanner: some View {
        if currentRound > 0, deck.indices.contains(currentRound - 1) {
            let round = currentRound - 1
            let question = deck[round]
            VStack(spacing: 8) {
                PillTag(text: recapLine(round: round, question: question),
                        tint: recapWasCorrect(round: round) ? Licht.lampengold : Licht.glut)
                Text(L10n.t("games.duel.reveal.answer") + ": "
                     + question.options[question.correct].resolved(L10n.lang))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            // Recap sits directly on the night room — night inks stay.
        }
    }

    private func recapWasCorrect(round: Int) -> Bool {
        guard let mine = myAnswer(round: round),
              deck.indices.contains(round) else { return false }
        return mine == deck[round].correct
    }

    private func recapLine(round: Int, question: DuelQuestion) -> String {
        // First correct answer in arrival order took the 2 points.
        let winner = answers.first { $0.round == round && $0.option == question.correct }
        guard let winner else { return L10n.t("games.duel.nobody") }
        let second = answers.first {
            $0.round == round && $0.option == question.correct && $0.memberId != winner.memberId
        }
        var line = L10n.t("games.duel.fast", ["name": name(of: winner.memberId)])
        if let second {
            line += " · " + L10n.t("games.duel.slow", ["name": name(of: second.memberId)])
        }
        return line
    }

    @ViewBuilder
    private var roundCard: some View {
        let round = currentRound
        if round < totalRounds, deck.indices.contains(round) {
            let question = deck[round]
            let mine = myAnswer(round: round)
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(question.text.resolved(L10n.lang))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(question.options.indices, id: \.self) { index in
                    optionButton(round: round, question: question, index: index, mine: mine)
                }
                if mine != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(coupleTint.tinte)
                        Text(L10n.t("games.duel.answered", ["name": appState.partnerName]))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Tinte.sekundaer)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .paperCard()
        }
    }

    private func optionButton(round: Int, question: DuelQuestion,
                              index: Int, mine: Int?) -> some View {
        let picked = mine == index
        return Button {
            submitAnswer(round: round, option: index)
        } label: {
            HStack {
                Text(question.options[index].resolved(L10n.lang))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if picked {
                    Image(systemName: "bolt.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(coupleTint.tinte)
                }
            }
            .padding(LayoutMetrics.s(13))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(picked ? coupleTint.tinte.opacity(0.16) : Papier.innenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(picked ? coupleTint.tinte : Papier.kante,
                                  lineWidth: picked ? 1.5 : Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(sending || mine != nil)
    }

    // MARK: Actions

    private func submitAnswer(round: Int, option: Int) {
        guard !sending, myAnswer(round: round) == nil else { return }
        sending = true
        Haptics.shared.tap()
        Task {
            let data = JSONValue.object([
                "kind": .string("answer"),
                "round": .number(Double(round)),
                "option": .number(Double(option))
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                SoundEngine.shared.play(.click)
            }
            sending = false
        }
    }

    private func handleRoundAdvance(from old: Int, to new: Int) {
        guard new > old, old < totalRounds else { return }
        if recapWasCorrect(round: old) {
            SoundEngine.shared.play(.sparkle)
            Haptics.shared.success()
        } else {
            SoundEngine.shared.play(.pop)
        }
    }

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrate {
            celebrate = true
            let mine = score(for: appState.memberId ?? "")
            let theirs = score(for: appState.partner?.id ?? "")
            if mine > theirs {
                GameEndCelebration.win(theme: .confetti)
            } else if mine == theirs {
                GameEndCelebration.tie()
            } else {
                GameEndCelebration.loss()
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    private var resultJSON: JSONValue {
        var result: [String: JSONValue] = [:]
        for id in memberIds {
            result[id] = .number(Double(score(for: id)))
        }
        return .object(["scores": .object(result)])
    }

    // MARK: End screen

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "trophy.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.lampengold)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(L10n.t("games.quiz.end.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                finalScoreRow
                Text(endVerdictLine)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.lampengold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    startGame(rounds: totalRounds)
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

    private var finalScoreRow: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            endScoreColumn(member: appState.me)
            Text(":")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Nacht.tertiaer)
            endScoreColumn(member: appState.partner)
        }
    }

    private func endScoreColumn(member: Member?) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(46))
            Text("\(member.map { score(for: $0.id) } ?? 0)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(Papier.aufNacht)
            Text(member?.name ?? "–")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
    }

    private var endVerdictLine: String {
        guard let myId = appState.memberId, let partnerId = appState.partner?.id else { return "" }
        let mine = score(for: myId)
        let theirs = score(for: partnerId)
        if mine == theirs {
            return L10n.t("games.duel.end.tie")
        }
        let winner = mine > theirs ? name(of: myId) : name(of: partnerId)
        return L10n.t("games.duel.end.winner", ["name": winner])
    }
}
