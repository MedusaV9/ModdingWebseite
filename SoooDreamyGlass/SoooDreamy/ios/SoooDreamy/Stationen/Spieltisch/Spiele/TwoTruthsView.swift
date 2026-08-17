import SwiftUI
import Combine

// Zwei Wahrheiten, eine Lüge 🤥 — quick & witty. The teller writes three
// statements and marks the lie; its index is sealed as a SHA-256 commit in
// the SAME move, so it provably cannot be switched after the guess. Three
// moves per round (statements+commit → guess → reveal), roles alternate.
// Reducer: Content/TwoTruthsLogic.swift.

/// Local lie index + salt per (game, round) — the commit-reveal secret must
/// survive app restarts and never leave the device before the reveal.
enum TTVault {
    private static func key(_ gameId: String, _ round: Int) -> String {
        "twotruths.secret.\(gameId).\(round)"
    }

    static func save(gameId: String, round: Int, lieIndex: Int, salt: String) {
        UserDefaults.standard.set("\(salt)#\(lieIndex)", forKey: key(gameId, round))
    }

    static func load(gameId: String, round: Int) -> (lieIndex: Int, salt: String)? {
        guard let raw = UserDefaults.standard.string(forKey: key(gameId, round)),
              let separator = raw.firstIndex(of: "#"),
              let index = Int(raw[raw.index(after: separator)...]) else { return nil }
        return (index, String(raw[..<separator]))
    }
}

/// Recap of a finished round for the result overlay.
private struct TTRoundResult: Equatable {
    let round: Int
    let iWasTeller: Bool
    let guessedRight: Bool
    let lieText: String
}

struct TwoTruthsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var texts = ["", "", ""]
    @State private var liePick: Int?
    @State private var guessPick: Int?
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrated = false
    @State private var didRevealRounds: Set<Int> = []
    @State private var resultBanner: TTRoundResult?
    @State private var seenDone = 0

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if let result = resultBanner {
                resultOverlay(result)
            }
        }
        .navigationTitle(L10n.t("games.card.twotruths.title"))
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
            seenDone = doneCount
            autoActions()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
            seenDone = doneCount
        }
        .onChange(of: engine.session?.moves.count ?? 0) { _, _ in
            autoActions()
        }
        .onChange(of: doneCount) { old, new in
            if new > old { announceRound(index: new - 1) }
            seenDone = new
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
        guard let current = engine.session, current.kind == .twotruths else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    private var theirId: String { myId == starterId ? otherId : starterId }

    private var roundCount: Int {
        engine.payloadInt("rounds", default: TwoTruths.defaultRounds)
    }

    private var events: [TwoTruthsEvent] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "statements":
                guard let round = move.data["round"]?.intValue,
                      let raw = move.data["texts"]?.arrayValue else { return nil }
                return .statements(member: move.memberId, round: round,
                                   texts: raw.compactMap(\.stringValue))
            case "guess":
                guard let round = move.data["round"]?.intValue,
                      let pick = move.data["pick"]?.intValue else { return nil }
                return .guess(member: move.memberId, round: round, pick: pick)
            case "reveal":
                guard let round = move.data["round"]?.intValue,
                      let text = move.data["reveal"]?.stringValue,
                      let lie = Int(text) else { return nil }
                return .reveal(member: move.memberId, round: round, lieIndex: lie,
                               serverVerified: move.data["verified"]?.boolValue ?? false)
            default:
                return nil
            }
        }
    }

    private var gameState: TwoTruthsState {
        TwoTruths.reduce(events: events, rounds: roundCount,
                         starter: starterId, partner: otherId)
    }

    private var doneCount: Int {
        gameState.rounds.filter { $0.phase == .done }.count
    }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.finished
    }

    private func score(of member: String) -> Int {
        TwoTruths.score(state: gameState, member: member,
                        starter: starterId, partner: otherId)
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
                roundScreen
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
                Image(systemName: "person.fill.questionmark")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.twotruths.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.tt.setup.body"))
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
            if await engine.create(api: appState.api, type: .twotruths, payload: .object([
                "rounds": .number(Double(TwoTruths.defaultRounds))
            ])) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        texts = ["", "", ""]
        liePick = nil
        guessPick = nil
        sending = false
        didSendEnd = false
        celebrated = false
        didRevealRounds = []
        resultBanner = nil
    }

    // MARK: Round screen

    private var roundScreen: some View {
        let round = gameState.currentRound
        let teller = TwoTruths.teller(round: round, starter: starterId, partner: otherId)
        let phase = gameState.rounds.indices.contains(round)
            ? gameState.rounds[round].phase : .composing
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                roundHeader(round: round, teller: teller)
                switch phase {
                case .composing:
                    if teller == myId {
                        composer(round: round)
                    } else {
                        waitingCard(emoji: "✍️",
                                    text: L10n.t("games.tt.wait.compose",
                                                 ["name": appState.partnerName]))
                    }
                case .guessing:
                    if teller == myId {
                        waitingCard(emoji: "🕵️",
                                    text: L10n.t("games.tt.wait.guess",
                                                 ["name": appState.partnerName]))
                    } else {
                        guessPicker(round: round)
                    }
                case .revealing, .done:
                    waitingCard(emoji: "🔐", text: L10n.t("games.tt.revealing"))
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func roundHeader(round: Int, teller: String) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "person.fill.questionmark")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Licht.lampengold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("games.tt.round",
                            ["n": "\(round + 1)", "total": "\(roundCount)"]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(teller == myId
                     ? L10n.t("games.tt.role.teller")
                     : L10n.t("games.tt.role.guesser", ["name": appState.partnerName]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer(minLength: 0)
            PillTag(text: "\(score(of: myId)) : \(score(of: theirId))", tint: Licht.glut)
        }
        .nightCard(grain: false)
    }

    // MARK: Composing (teller)

    private func composer(round: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.tt.compose.title"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(L10n.t("games.tt.compose.hint"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(0..<3, id: \.self) { index in
                composerRow(index: index)
            }
            Button {
                sendStatements(round: round)
            } label: {
                Text(L10n.t("games.tt.compose.submit"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || liePick == nil
                      || texts.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        }
        .paperCard()
    }

    private func composerRow(index: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(8)) {
            TextField(L10n.t("games.tt.compose.placeholder", ["n": "\(index + 1)"]),
                      text: $texts[index], axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.dunkel)
                .lineLimit(1...3)
            Button {
                liePick = index
                Haptics.shared.tap()
            } label: {
                Text(liePick == index ? "🤥" : "😇")
                    .font(.system(.title3, design: .rounded))
                    .padding(LayoutMetrics.s(6))
                    .background(
                        Circle().fill(liePick == index
                                      ? coupleTint.tinte.opacity(0.16)
                                      : Papier.brief)
                            .overlay(Circle().strokeBorder(Papier.kante,
                                                           lineWidth: Theme.hairlineWidth))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LayoutMetrics.s(12))
        .padding(.vertical, LayoutMetrics.s(8))
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.innenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .stroke(liePick == index ? coupleTint.tinte : Papier.kante,
                                lineWidth: liePick == index ? 1.5 : Theme.hairlineWidth)
                )
        )
    }

    private func sendStatements(round: Int) {
        guard let lie = liePick, !sending, let gameId = session?.id else { return }
        let trimmed = texts.map { $0.trimmingCharacters(in: .whitespaces) }
        guard trimmed.allSatisfy({ !$0.isEmpty }) else { return }
        sending = true
        // Seal the lie's index BEFORE the partner sees the statements.
        let salt = CommitReveal.newSalt()
        let commit = CommitReveal.commit(secret: "\(lie)", salt: salt)
        TTVault.save(gameId: gameId, round: round, lieIndex: lie, salt: salt)
        SoundEngine.shared.play(.pop)
        Haptics.shared.tap()
        Task {
            _ = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("statements"),
                "round": .number(Double(round)),
                "texts": .array(trimmed.map { .string($0) }),
                "commit": .string(commit)
            ]))
            texts = ["", "", ""]
            liePick = nil
            sending = false
        }
    }

    // MARK: Guessing (partner)

    private func guessPicker(round: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.tt.guess.title"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(L10n.t("games.tt.guess.hint", ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
            ForEach(Array((gameState.rounds[round].texts ?? []).enumerated()),
                    id: \.offset) { index, text in
                Button {
                    guessPick = index
                    Haptics.shared.tap()
                } label: {
                    HStack(spacing: LayoutMetrics.s(10)) {
                        Text(guessPick == index ? "🤥" : "💬")
                            .font(.system(.title3, design: .rounded))
                        Text(text)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Tinte.dunkel)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(LayoutMetrics.s(12))
                    .background(
                        RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                            .fill(guessPick == index
                                  ? coupleTint.tinte.opacity(0.16)
                                  : Papier.innenFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                                    .stroke(guessPick == index
                                            ? coupleTint.tinte : Papier.kante,
                                            lineWidth: guessPick == index
                                            ? 1.5 : Theme.hairlineWidth)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Button {
                sendGuess(round: round)
            } label: {
                Text(L10n.t("games.tt.guess.submit"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || guessPick == nil)
        }
        .paperCard()
    }

    private func sendGuess(round: Int) {
        guard let pick = guessPick, !sending else { return }
        sending = true
        SoundEngine.shared.play(.click)
        Haptics.shared.tap()
        Task {
            _ = await engine.sendMove(api: appState.api, data: .object([
                "kind": .string("guess"),
                "round": .number(Double(round)),
                "pick": .number(Double(pick))
            ]))
            guessPick = nil
            sending = false
        }
    }

    private func waitingCard(emoji: String, text: String) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(emoji)
                .font(.system(.largeTitle, design: .rounded))
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

    // MARK: Auto reveal (teller, after the guess)

    private func autoActions() {
        guard let session, session.state == "active" else { return }
        let state = gameState
        let round = state.currentRound
        guard state.rounds.indices.contains(round) else { return }
        guard state.rounds[round].phase == .revealing,
              myId == TwoTruths.teller(round: round, starter: starterId, partner: otherId),
              !didRevealRounds.contains(round),
              let secret = TTVault.load(gameId: session.id, round: round) else { return }
        didRevealRounds.insert(round)
        let commitId = engine.orderedMoves.first {
            $0.memberId == myId && $0.data["kind"]?.stringValue == "statements"
                && $0.data["round"]?.intValue == round
        }?.id
        Task {
            var object: [String: JSONValue] = [
                "kind": .string("reveal"),
                "round": .number(Double(round)),
                "reveal": .string("\(secret.lieIndex)"),
                "salt": .string(secret.salt)
            ]
            if let commitId {
                object["commitId"] = .string(commitId)
            }
            _ = await engine.sendMove(api: appState.api, data: .object(object))
        }
    }

    // MARK: Round result overlay

    private func announceRound(index: Int) {
        guard gameState.rounds.indices.contains(index),
              let right = gameState.rounds[index].guessedRight,
              let lie = gameState.rounds[index].lieIndex,
              let roundTexts = gameState.rounds[index].texts,
              roundTexts.indices.contains(lie) else { return }
        let iWasTeller = myId == TwoTruths.teller(round: index, starter: starterId,
                                                  partner: otherId)
        let iWon = iWasTeller ? !right : right
        if iWon {
            // R1-D: the round win blooms in the app-wide Lichtschein
            // instead of confetti; the fanfare stays the ear's half.
            AppCue.fanfareMedium.play()
            LichtscheinCenter.shared.fire()
        } else {
            SoundEngine.shared.play(.click)
            Haptics.shared.warning()
        }
        withAnimation(Theme.Motion.settle) {
            resultBanner = TTRoundResult(round: index, iWasTeller: iWasTeller,
                                         guessedRight: right, lieText: roundTexts[lie])
        }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Theme.Motion.settle) {
                if resultBanner?.round == index { resultBanner = nil }
            }
        }
    }

    private func resultOverlay(_ result: TTRoundResult) -> some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            Image(systemName: result.guessedRight ? "checkmark.seal.fill" : "theatermasks.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(result.guessedRight ? Theme.mint : coupleTint.blend)
                .accessibilityHidden(true)
            Text(resultLine(result))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(L10n.t("games.tt.result.lieWas", ["text": result.lieText]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
        }
        .padding(LayoutMetrics.s(24))
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .padding(LayoutMetrics.s(24))
        .transition(.scale.combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private func resultLine(_ result: TTRoundResult) -> String {
        let name = appState.partnerName
        if result.iWasTeller {
            return result.guessedRight
                ? L10n.t("games.tt.result.caughtYou", ["name": name])
                : L10n.t("games.tt.result.fooledThem", ["name": name])
        }
        return result.guessedRight
            ? L10n.t("games.tt.result.gotcha")
            : L10n.t("games.tt.result.fooledYou")
    }

    // MARK: Finish

    private func handleFinish() {
        guard session != nil else { return }
        let mine = score(of: myId)
        let theirs = score(of: theirId)
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
                scores[id] = .number(Double(score(of: id)))
            }
            await engine.end(api: appState.api, result: .object(["scores": .object(scores)]))
        }
    }

    private var endScreen: some View {
        let mine = score(of: myId)
        let theirs = score(of: theirId)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: mine > theirs ? "trophy.fill" : (mine == theirs ? "heart.circle.fill" : "person.fill.questionmark"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(mine > theirs ? Licht.lampengold : coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(mine > theirs
                     ? L10n.t("games.tt.win.you")
                     : (mine == theirs
                        ? L10n.t("games.tt.tie")
                        : L10n.t("games.tt.win.partner", ["name": appState.partnerName])))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                HStack(spacing: LayoutMetrics.s(24)) {
                    scorePill(name: appState.me?.name ?? L10n.t("common.you"),
                              points: mine, mine: true)
                    Text(":")
                        .font(.system(.title, design: .rounded).weight(.heavy))
                        .foregroundStyle(Nacht.tertiaer)
                    scorePill(name: appState.partnerName, points: theirs, mine: false)
                }
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

    private func scorePill(name: String, points: Int, mine: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
                .lineLimit(1)
            Text("\(points)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Papier.aufNacht)
        }
        .frame(minWidth: LayoutMetrics.s(72))
    }
}
