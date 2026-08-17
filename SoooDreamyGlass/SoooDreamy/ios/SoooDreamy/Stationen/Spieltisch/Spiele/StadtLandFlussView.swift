import SwiftUI
import Combine

// Stadt-Land-Fluss Paar-Edition 🗺️ — anti-spoiler commit, mutual rating,
// custom categories. Answers are committed as a SHA-256 hash first and only
// revealed once BOTH committed (enforced by the reducer, certified by the
// relay). When one partner commits, the other gets a 45s "Stop!" countdown.
// Reducer: Content/StadtLandFlussLogic.swift.

/// Local answers + salt per (game, round) — the commit-reveal secret must
/// survive app restarts and never leave the device before the reveal.
enum SLFVault {
    private static func key(_ gameId: String, _ round: Int) -> String {
        "slf.secret.\(gameId).\(round)"
    }

    static func save(gameId: String, round: Int, joined: String, salt: String) {
        UserDefaults.standard.set("\(salt)#\(joined)", forKey: key(gameId, round))
    }

    static func load(gameId: String, round: Int) -> (joined: String, salt: String)? {
        guard let raw = UserDefaults.standard.string(forKey: key(gameId, round)),
              let separator = raw.firstIndex(of: "#") else { return nil }
        return (String(raw[raw.index(after: separator)...]), String(raw[..<separator]))
    }
}

struct StadtLandFlussView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var now = Date()
    @State private var answers: [String] = []
    @State private var customCategories: [String] = []
    @State private var categoryInput = ""
    @State private var verdicts: [Bool] = []
    @State private var verdictsForRound = -1
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrated = false
    @State private var didRevealRounds: Set<Int> = []
    @State private var didAutoCommit = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.stadtlandfluss.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
            }
        }
        .onReceive(clock) { date in
            now = date
            autoActions()
        }
        .task {
            engine.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            if engine.session == nil {
                await engine.resume(api: appState.api)
            }
            autoActions()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: engine.session?.moves.count ?? 0) { _, _ in
            autoActions()
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
        guard let current = engine.session, current.kind == .stadtlandfluss else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    private var theirId: String { myId == starterId ? otherId : starterId }

    private var categories: [String] {
        session?.payload?["categories"]?.arrayValue?.compactMap(\.stringValue)
            ?? StadtLandFluss.defaultCategories(lang: L10n.lang)
    }

    private var roundCount: Int {
        engine.payloadInt("rounds", default: StadtLandFluss.defaultRounds)
    }

    private var letters: [String] {
        StadtLandFluss.letters(seed: engine.seed, rounds: roundCount)
    }

    private var events: [SLFEvent] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "commit":
                guard move.data["commit"]?.stringValue != nil,
                      let round = move.data["round"]?.intValue else { return nil }
                return .commit(member: move.memberId, round: round, at: move.createdAt)
            case "reveal":
                guard let round = move.data["round"]?.intValue,
                      let text = move.data["reveal"]?.stringValue else { return nil }
                return .reveal(member: move.memberId, round: round, text: text,
                               serverVerified: move.data["verified"]?.boolValue ?? false)
            case "rate":
                guard let round = move.data["round"]?.intValue,
                      let raw = move.data["verdicts"]?.arrayValue else { return nil }
                return .rate(member: move.memberId, round: round,
                             verdicts: raw.compactMap(\.boolValue))
            default:
                return nil
            }
        }
    }

    private var gameState: SLFState {
        StadtLandFluss.reduce(events: events, rounds: roundCount,
                              categoryCount: categories.count,
                              starter: starterId, partner: otherId)
    }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.finished
    }

    private func total(of member: String) -> Int {
        StadtLandFluss.total(state: gameState, letters: letters,
                             categoryCount: categories.count,
                             member: member, partner: member == myId ? theirId : myId)
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: Licht.glut)
                        .padding(LayoutMetrics.s(16))
                }
            } else if finished {
                endScreen
            } else if session.state == "active" {
                roundScreen
            } else {
                setupScreen
            }
        } else {
            setupScreen
        }
    }

    // MARK: Setup (custom categories)

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "map.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.stadtlandfluss.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.slf.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                categoryEditor
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy || setupCategories.count < 3)
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var setupCategories: [String] {
        customCategories.isEmpty
            ? StadtLandFluss.defaultCategories(lang: L10n.lang)
            : customCategories
    }

    private var categoryEditor: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.s(96)), spacing: 6)],
                      spacing: 6) {
                ForEach(setupCategories, id: \.self) { category in
                    HStack(spacing: 4) {
                        Text(category)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Papier.aufNacht)
                            .lineLimit(1)
                        Button {
                            removeCategory(category)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, LayoutMetrics.s(10))
                    .padding(.vertical, LayoutMetrics.s(6))
                    .background(
                        Capsule().fill(Papier.nachtInnenFill)
                            .overlay(Capsule().strokeBorder(Nacht.naht,
                                                            lineWidth: Theme.hairlineWidth))
                    )
                }
            }
            HStack(spacing: LayoutMetrics.s(8)) {
                TextField(L10n.t("games.slf.custom.placeholder"), text: $categoryInput)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Papier.aufNacht)
                    .submitLabel(.done)
                    .onSubmit(addCategory)
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(coupleTint.blend)
                }
                .buttonStyle(.plain)
                .disabled(categoryInput.trimmingCharacters(in: .whitespaces).isEmpty
                          || setupCategories.count >= 8)
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.vertical, LayoutMetrics.s(8))
            .background(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
            )
        }
    }

    private func addCategory() {
        let name = categoryInput.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, setupCategories.count < 8, !setupCategories.contains(name) else { return }
        customCategories = setupCategories + [name]
        categoryInput = ""
        Haptics.shared.tap()
    }

    private func removeCategory(_ category: String) {
        var list = setupCategories
        list.removeAll { $0 == category }
        customCategories = list
    }

    private func startGame() {
        guard !engine.busy else { return }
        let chosen = setupCategories
        Task {
            resetLocalState()
            // The seed comes from the server (fairness contract).
            let payload = JSONValue.object([
                "rounds": .number(Double(StadtLandFluss.defaultRounds)),
                "categories": .array(chosen.map { .string($0) })
            ])
            if await engine.create(api: appState.api, type: .stadtlandfluss, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        answers = []
        verdicts = []
        verdictsForRound = -1
        sending = false
        didSendEnd = false
        celebrated = false
        didRevealRounds = []
        didAutoCommit = false
    }

    // MARK: Round flow

    @ViewBuilder
    private var roundScreen: some View {
        let round = gameState.currentRound
        if gameState.rounds.indices.contains(round) {
            let roundState = gameState.rounds[round]
            let phase = roundState.phase(members: [starterId, otherId])
            ScrollView {
                VStack(spacing: LayoutMetrics.s(12)) {
                    scoreHeader(round: round)
                    switch phase {
                    case .collecting:
                        if roundState.commits[myId] == nil {
                            collectingCard(round: round, roundState: roundState)
                        } else {
                            waitingCard(text: L10n.t("games.slf.waitCommit",
                                                     ["name": appState.partnerName]))
                        }
                    case .revealing:
                        waitingCard(text: L10n.t("games.slf.revealing"))
                    case .rating:
                        if roundState.ratings[myId] == nil {
                            ratingCard(round: round, roundState: roundState)
                        } else {
                            waitingCard(text: L10n.t("games.slf.waitRating",
                                                     ["name": appState.partnerName]))
                        }
                    case .done:
                        waitingCard(text: L10n.t("games.slf.revealing"))
                    }
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
                .contentColumn(.reading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func scoreHeader(round: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("games.slf.round", ["n": "\(min(round + 1, roundCount))",
                                                "total": "\(roundCount)"]))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.tertiaer)
                // The round letter is THE stamp of the round — ember glow.
                Text(L10n.t("games.slf.letter", ["letter": letters[safe: round] ?? "?"]))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Licht.glut)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(appState.me?.name ?? L10n.t("common.you")): \(total(of: myId))")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text("\(appState.partnerName): \(total(of: theirId))")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
            }
        }
        .nightCard(grain: false)
    }

    // MARK: Collecting

    private func collectingCard(round: Int, roundState: SLFRound) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            if let deadline = stopDeadline(roundState: roundState) {
                stopCountdown(deadline: deadline)
            }
            ForEach(categories.indices, id: \.self) { index in
                HStack(spacing: LayoutMetrics.s(8)) {
                    Text(categories[index])
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.sekundaer)
                        .frame(width: LayoutMetrics.s(88), alignment: .leading)
                        .lineLimit(1)
                    TextField(letters[safe: round].map { "\($0)…" } ?? "…",
                              text: answerBinding(index))
                        .textFieldStyle(.plain)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Tinte.dunkel)
                        .autocorrectionDisabled()
                        .padding(.horizontal, LayoutMetrics.s(10))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(
                            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                                .fill(Papier.innenFill)
                                .overlay(RoundedRectangle(cornerRadius: Radius.papier,
                                                          style: .continuous)
                                    .strokeBorder(Papier.kante,
                                                  lineWidth: Theme.hairlineWidth))
                        )
                }
            }
            Button {
                commitAnswers(round: round)
            } label: {
                Text(L10n.t("games.slf.commit"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
            Text(L10n.t("games.slf.commit.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
                .multilineTextAlignment(.center)
        }
        .paperCard()
    }

    private func answerBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { answers[safe: index] ?? "" },
            set: { newValue in
                while answers.count <= index { answers.append("") }
                answers[index] = newValue
            }
        )
    }

    /// "Stop!" pressure: once the PARTNER committed, I have 45s left.
    private func stopDeadline(roundState: SLFRound) -> Date? {
        guard roundState.commits[myId] == nil,
              let partnerCommit = roundState.commits[theirId] else { return nil }
        return partnerCommit.addingTimeInterval(TimeInterval(StadtLandFluss.stopSecs))
    }

    private func stopCountdown(deadline: Date) -> some View {
        let remaining = max(0, deadline.timeIntervalSince(now))
        return HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "bell.fill")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Wachs.rot)
                .accessibilityHidden(true)
            Text(L10n.t("games.slf.stop", ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Wachs.rot)
            Spacer(minLength: 0)
            Text("\(Int(remaining))s")
                .font(.system(.subheadline, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(Wachs.rot)
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Wachs.rot.opacity(0.12))
        )
    }

    private func commitAnswers(round: Int) {
        guard let id = session?.id, !sending else { return }
        sending = true
        var filled = answers
        while filled.count < categories.count { filled.append("") }
        let joined = StadtLandFluss.encodeAnswers(Array(filled.prefix(categories.count)))
        let salt = CommitReveal.newSalt()
        SLFVault.save(gameId: id, round: round, joined: joined, salt: salt)
        Task {
            let data = JSONValue.object([
                "kind": .string("commit"),
                "round": .number(Double(round)),
                "commit": .string(CommitReveal.commit(secret: joined, salt: salt))
            ])
            if await engine.sendDurableMove(appState: appState, data: data, kind: .rating) {
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                answers = []
            }
            sending = false
        }
    }

    // MARK: Auto actions (reveal + stop auto-commit)

    private func autoActions() {
        guard let session, session.state == "active" else { return }
        let state = gameState
        let round = state.currentRound
        guard state.rounds.indices.contains(round) else { return }
        let roundState = state.rounds[round]
        let phase = roundState.phase(members: [starterId, otherId])
        // 1. Both committed → open my answers (relay certifies the hash).
        if phase == .revealing, roundState.answers[myId] == nil,
           !didRevealRounds.contains(round),
           let secret = SLFVault.load(gameId: session.id, round: round) {
            didRevealRounds.insert(round)
            let commitId = engine.orderedMoves.first {
                $0.memberId == myId && $0.data["kind"]?.stringValue == "commit"
                    && $0.data["round"]?.intValue == round
            }?.id
            Task {
                var object: [String: JSONValue] = [
                    "kind": .string("reveal"),
                    "round": .number(Double(round)),
                    "reveal": .string(secret.joined),
                    "salt": .string(secret.salt)
                ]
                if let commitId {
                    object["commitId"] = .string(commitId)
                }
                _ = await engine.sendMove(api: appState.api, data: .object(object))
            }
        }
        // 2. Partner committed and my clock ran out → auto-commit what I have.
        if phase == .collecting, roundState.commits[myId] == nil, !didAutoCommit,
           let deadline = stopDeadline(roundState: roundState), now > deadline {
            didAutoCommit = true
            commitAnswers(round: round)
        }
        if phase != .collecting {
            didAutoCommit = false
        }
    }

    // MARK: Rating

    private func ratingCard(round: Int, roundState: SLFRound) -> some View {
        let partnerAnswers = roundState.answers[theirId] ?? []
        let letter = letters[safe: round] ?? "?"
        if verdictsForRound != round {
            // Prefill with the auto letter check (runs once per round).
            DispatchQueue.main.async {
                verdicts = partnerAnswers.map { StadtLandFluss.startsCorrectly($0, letter: letter) }
                verdictsForRound = round
            }
        }
        return VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.slf.rate.title", ["name": appState.partnerName]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(L10n.t("games.slf.rate.hint"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
                .multilineTextAlignment(.center)
            ForEach(categories.indices, id: \.self) { index in
                ratingRow(index: index, answer: partnerAnswers[safe: index] ?? "", letter: letter)
            }
            Button {
                submitRating(round: round)
            } label: {
                Text(L10n.t("games.slf.rate.submit"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || verdictsForRound != round)
        }
        .paperCard()
    }

    private func ratingRow(index: Int, answer: String, letter: String) -> some View {
        let empty = answer.trimmingCharacters(in: .whitespaces).isEmpty
        let approved = verdicts[safe: index] ?? false
        return HStack(spacing: LayoutMetrics.s(8)) {
            VStack(alignment: .leading, spacing: 1) {
                Text(categories[safe: index] ?? "")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.tertiaer)
                Text(empty ? "—" : answer)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(empty ? Tinte.tertiaer : Tinte.dunkel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !empty {
                Button {
                    if verdicts.indices.contains(index) {
                        verdicts[index].toggle()
                        Haptics.shared.tap()
                    }
                } label: {
                    Image(systemName: approved ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(approved ? coupleTint.tinte : Wachs.rot)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }

    private func submitRating(round: Int) {
        guard !sending, verdictsForRound == round else { return }
        sending = true
        let sent = verdicts
        Task {
            let data = JSONValue.object([
                "kind": .string("rate"),
                "round": .number(Double(round)),
                "verdicts": .array(sent.map { .bool($0) })
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                SoundEngine.shared.play(.success)
                Haptics.shared.success()
            }
            sending = false
        }
    }

    private func waitingCard(text: String) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "lock.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            ProgressView()
                .tint(Nacht.sekundaer)
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    // MARK: Finish

    private func handleFinish() {
        guard session != nil else { return }
        let mine = total(of: myId)
        let theirs = total(of: theirId)
        if !celebrated {
            celebrated = true
            if mine > theirs {
                GameEndCelebration.win()
            } else if mine == theirs {
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
                scores[id] = .number(Double(total(of: id)))
            }
            await engine.end(api: appState.api, result: .object(["scores": .object(scores)]))
        }
    }

    private var endScreen: some View {
        let mine = total(of: myId)
        let theirs = total(of: theirId)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: mine > theirs ? "trophy.fill" : (mine == theirs ? "heart.circle.fill" : "map.fill"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(mine > theirs ? Licht.lampengold : coupleTint.blend)
                    .background(mine > theirs ? VerdictLampenschein() : nil)
                    .accessibilityHidden(true)
                Text(mine > theirs
                     ? L10n.t("games.slf.win.you")
                     : (mine == theirs
                        ? L10n.t("games.slf.tie")
                        : L10n.t("games.slf.win.partner", ["name": appState.partnerName])))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                HStack(spacing: LayoutMetrics.s(20)) {
                    endScore(name: appState.me?.name ?? L10n.t("common.you"),
                             score: mine, tint: Papier.aufNacht)
                    endScore(name: appState.partnerName, score: theirs,
                             tint: Papier.aufNacht)
                }
                roundRecap
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

    private func endScore(name: String, score: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(tint)
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
        .frame(maxWidth: .infinity)
    }

    /// Round-by-round recap as an inner fill ON the end-screen night
    /// panel — a results table, not a second card.
    private var roundRecap: some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            ForEach(gameState.rounds.indices, id: \.self) { index in
                let round = gameState.rounds[index]
                if round.phase(members: [starterId, otherId]) == .done {
                    HStack {
                        Text(L10n.t("games.slf.letter", ["letter": letters[safe: index] ?? "?"]))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Licht.glut)
                        Spacer()
                        Text("\(roundTotal(round: index, member: myId)) : \(roundTotal(round: index, member: theirId))")
                            .font(.system(.caption, design: .rounded).weight(.heavy).monospacedDigit())
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    .padding(.horizontal, LayoutMetrics.s(4))
                }
            }
        }
        .padding(LayoutMetrics.s(12))
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.nachtInnenFill)
        )
    }

    private func roundTotal(round: Int, member: String) -> Int {
        guard gameState.rounds.indices.contains(round),
              let letter = letters[safe: round] else { return 0 }
        let partner = member == myId ? theirId : myId
        return (0..<categories.count).reduce(0) { sum, category in
            sum + StadtLandFluss.points(round: gameState.rounds[round], category: category,
                                        letter: letter, member: member, partner: partner)
        }
    }
}
