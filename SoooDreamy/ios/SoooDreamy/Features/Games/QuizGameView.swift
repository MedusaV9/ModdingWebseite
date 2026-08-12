import SwiftUI
import Combine

/// "Who knows who better?" — realtime couple quiz.
///
/// Round r alternates the SUBJECT (even rounds = member A, odd = member B,
/// derived from the sorted member ids so both clients agree). The subject
/// answers truthfully about themselves, the other one guesses. Once both
/// answers are in, they are revealed and the subject judges the guess:
/// a "right" verdict scores a point for the guesser.
///
/// Move protocol:
/// - `{"kind": "answer",  "round": r, "value": "<free text>"}` (both members)
/// - `{"kind": "verdict", "round": r, "value": "right" | "wrong"}` (subject only)
struct QuizGameView: View {
    @Environment(AppState.self) private var appState

    let engine: GameEngine

    @State private var answerText = ""
    @State private var sending = false
    @State private var setupRounds = 8
    @State private var didSendEnd = false
    @State private var celebrate = false
    @State private var sharing = false
    @State private var shared = false

    private static let roundOptions = [4, 8, 12]

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if celebrate {
                FloatingHeartsView(emojis: ["🏆", "💖", "✨", "💜", "🎉"], count: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.quiz.title"))
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: Derived state (pure reducer over payload + moves)

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .quiz else { return nil }
        return current
    }

    private var totalRounds: Int { engine.payloadInt("rounds", default: 8) }

    private var sortedMemberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var questions: [QuizQuestion] {
        Array(ContentPack.quizQuestions.seededShuffled(seed: engine.seed).prefix(totalRounds))
    }

    private func subjectId(round: Int) -> String? {
        guard sortedMemberIds.count == 2 else { return nil }
        return round.isMultiple(of: 2) ? sortedMemberIds[0] : sortedMemberIds[1]
    }

    private func guesserId(round: Int) -> String? {
        guard sortedMemberIds.count == 2, let subject = subjectId(round: round) else { return nil }
        return sortedMemberIds.first { $0 != subject }
    }

    /// Verdict for a round — only the subject's verdict counts.
    private func verdict(round: Int) -> String? {
        guard let subject = subjectId(round: round) else { return nil }
        return engine.move(kind: "verdict", round: round, by: subject)?.data["value"]?.stringValue
    }

    /// First round without a verdict; equals `totalRounds` when done.
    private var currentRound: Int {
        guard session != nil else { return 0 }
        for round in 0..<totalRounds where verdict(round: round) == nil {
            return round
        }
        return totalRounds
    }

    private var finished: Bool {
        session != nil && totalRounds > 0 && currentRound >= totalRounds
    }

    private func score(for memberId: String) -> Int {
        var total = 0
        for round in 0..<totalRounds {
            guard verdict(round: round) == "right",
                  guesserId(round: round) == memberId else { continue }
            total += 1
        }
        return total
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
                    GameLobbyView(engine: engine, accent: Theme.pink)
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
                Text("🧠")
                    .font(.scaled(56))
                Text(L10n.t("games.card.quiz.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.quiz.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
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
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private var roundsPicker: some View {
        VStack(spacing: 8) {
            Text(L10n.t("games.quiz.setup.rounds"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Self.roundOptions, id: \.self) { option in
                    Button {
                        setupRounds = option
                        Haptics.shared.tap()
                    } label: {
                        Text("\(option)")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: LayoutMetrics.s(56), height: LayoutMetrics.s(44))
                            .background(
                                Capsule().fill(setupRounds == option
                                               ? Theme.pink.opacity(0.4)
                                               : Color.white.opacity(0.07))
                            )
                            .overlay(
                                Capsule().strokeBorder(setupRounds == option ? Theme.pink : .clear,
                                                       lineWidth: 1.5)
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
            if await engine.create(api: appState.api, type: .quiz, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        answerText = ""
        sending = false
        didSendEnd = false
        celebrate = false
        sharing = false
        shared = false
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader
                GameProgressBar(progress: Double(currentRound) / Double(max(totalRounds, 1)),
                                tint: Theme.pink)
                lastRoundBanner
                roundCard
            }
            .padding(LayoutMetrics.s(16))
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
                    tint: Theme.indigo)
            Spacer()
            scoreBadge(memberId: appState.partner?.id, alignment: .trailing)
        }
        .glassCard(padding: 12)
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
                .foregroundStyle(Theme.gold)
            if alignment == .trailing {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
        }
    }

    @ViewBuilder
    private var lastRoundBanner: some View {
        if currentRound > 0, currentRound <= totalRounds {
            let previous = currentRound - 1
            if let result = verdict(round: previous), let guesser = guesserId(round: previous) {
                PillTag(text: result == "right"
                        ? L10n.t("games.quiz.point", ["name": name(of: guesser)])
                        : L10n.t("games.quiz.noPoint"),
                        tint: result == "right" ? Theme.mint : Theme.purple)
            }
        }
    }

    @ViewBuilder
    private var roundCard: some View {
        let round = currentRound
        if round < totalRounds, round < questions.count, let subject = subjectId(round: round) {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(questions[round].text.filled(partner: name(of: subject), lang: L10n.lang))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                roleHint(subject: subject)
                phaseContent(round: round, subject: subject)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 18)
        }
    }

    private func roleHint(subject: String) -> some View {
        let mine = subject == appState.memberId
        return PillTag(text: mine
                       ? L10n.t("games.quiz.subject.you")
                       : L10n.t("games.quiz.subject.partner", ["name": name(of: subject)]),
                       tint: mine ? Theme.gold : Theme.blue)
    }

    @ViewBuilder
    private func phaseContent(round: Int, subject: String) -> some View {
        let myId = appState.memberId ?? ""
        let partnerId = appState.partner?.id ?? ""
        let myAnswer = engine.move(kind: "answer", round: round, by: myId)
        let partnerAnswer = engine.move(kind: "answer", round: round, by: partnerId)
        if myAnswer == nil {
            answerInput(round: round)
        } else if partnerAnswer == nil {
            VStack(spacing: LayoutMetrics.s(10)) {
                answerBubble(label: L10n.t("games.quiz.answered"),
                             text: myAnswer?.data["value"]?.stringValue ?? "",
                             tint: Theme.purple)
                GameWaitingHint()
            }
        } else {
            revealSection(round: round,
                          subject: subject,
                          myAnswer: myAnswer,
                          partnerAnswer: partnerAnswer)
        }
    }

    private func answerInput(round: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            TextField(L10n.t("games.quiz.answerPlaceholder"), text: $answerText, axis: .vertical)
                .textFieldStyle(DreamyFieldStyle())
                .lineLimit(1...3)
            Button {
                submitAnswer(round: round)
            } label: {
                if sending {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.scaled(17, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
            .background(Circle().fill(Theme.heroGradient))
            .disabled(sending || answerText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    @ViewBuilder
    private func revealSection(round: Int, subject: String,
                               myAnswer: GameMove?, partnerAnswer: GameMove?) -> some View {
        let iAmSubject = subject == appState.memberId
        let subjectMove = iAmSubject ? myAnswer : partnerAnswer
        let guessMove = iAmSubject ? partnerAnswer : myAnswer
        let guesserName = name(of: guesserId(round: round) ?? "")
        VStack(spacing: LayoutMetrics.s(12)) {
            answerBubble(label: L10n.t("games.quiz.truthLabel") + " · " + name(of: subject),
                         text: subjectMove?.data["value"]?.stringValue ?? "",
                         tint: Theme.gold)
            answerBubble(label: L10n.t("games.quiz.guessLabel") + " · " + guesserName,
                         text: guessMove?.data["value"]?.stringValue ?? "",
                         tint: Theme.blue)
            if iAmSubject {
                verdictButtons(round: round, guesserName: guesserName)
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .tint(Theme.pink)
                    Text(L10n.t("games.quiz.waitVerdict", ["name": name(of: subject)]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func verdictButtons(round: Int, guesserName: String) -> some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.quiz.verdictQuestion", ["name": guesserName]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: LayoutMetrics.s(10)) {
                Button {
                    submitVerdict(round: round, value: "right")
                } label: {
                    Text(L10n.t("games.quiz.verdict.right"))
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    submitVerdict(round: round, value: "wrong")
                } label: {
                    Text(L10n.t("games.quiz.verdict.wrong"))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .disabled(sending)
        }
    }

    private func answerBubble(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutMetrics.s(12))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
        )
    }

    // MARK: Actions

    private func submitAnswer(round: Int) {
        let text = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        Task {
            let data = GameEngine.moveData(kind: "answer", round: round, value: text)
            if await engine.sendMove(api: appState.api, data: data) {
                answerText = ""
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
            sending = false
        }
    }

    private func submitVerdict(round: Int, value: String) {
        guard !sending else { return }
        sending = true
        Task {
            let data = GameEngine.moveData(kind: "verdict", round: round, value: value)
            if await engine.sendMove(api: appState.api, data: data) {
                Haptics.shared.tap()
            }
            sending = false
        }
    }

    private func handleRoundAdvance(from old: Int, to new: Int) {
        guard new > old, old < totalRounds else { return }
        if verdict(round: old) == "right" {
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
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    private var resultJSON: JSONValue {
        var scores: [String: JSONValue] = [:]
        for id in sortedMemberIds {
            scores[id] = .number(Double(score(for: id)))
        }
        return .object(["scores": .object(scores)])
    }

    // MARK: End screen

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text("🏆")
                    .font(.scaled(60))
                Text(L10n.t("games.quiz.end.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                finalScoreRow
                Text(endVerdictLine)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(endFlavorLine)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                shareButton
                Button {
                    startGame(rounds: totalRounds)
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

    // MARK: Share to chat

    @ViewBuilder
    private var shareButton: some View {
        if appState.api != nil {
            Button {
                shareToChat()
            } label: {
                if sharing {
                    ProgressView()
                        .tint(Theme.pink)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.pink)
            .disabled(sharing || shared)
        }
    }

    /// Posts the final score into the couple chat (Wordle/ToD pattern).
    private var shareText: String {
        let myId = appState.memberId ?? ""
        let partnerId = appState.partner?.id ?? ""
        let header = L10n.t("games.share.header",
                            ["game": "🧠 " + L10n.t("games.card.quiz.title")])
        let scoreLine = "\(name(of: myId)) \(score(for: myId)) : \(score(for: partnerId)) \(name(of: partnerId))"
        return header + "\n" + scoreLine + "\n" + endVerdictLine
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

    private var finalScoreRow: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            endScoreColumn(member: appState.me)
            Text(":")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textTertiary)
            endScoreColumn(member: appState.partner)
        }
    }

    private func endScoreColumn(member: Member?) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(46))
            Text("\(member.map { score(for: $0.id) } ?? 0)")
                .font(.scaled(44, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(member?.name ?? "–")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var endVerdictLine: String {
        guard let myId = appState.memberId, let partnerId = appState.partner?.id else { return "" }
        let mine = score(for: myId)
        let theirs = score(for: partnerId)
        if mine == theirs {
            return L10n.t("games.quiz.end.tie")
        }
        let winner = mine > theirs ? name(of: myId) : name(of: partnerId)
        let other = mine > theirs ? name(of: partnerId) : name(of: myId)
        return L10n.t("games.quiz.end.winner", ["name": winner, "other": other])
    }

    private var endFlavorLine: String {
        guard totalRounds > 0 else { return "" }
        let total = sortedMemberIds.reduce(0) { $0 + score(for: $1) }
        let ratio = Double(total) / Double(totalRounds)
        if ratio >= 0.75 { return L10n.t("games.quiz.end.high") }
        if ratio >= 0.4 { return L10n.t("games.quiz.end.mid") }
        return L10n.t("games.quiz.end.low")
    }
}
