import SwiftUI
import Combine

// Montagsmaler 🎨 — draw & guess with a shared deadline, roles swap every
// round. Reuses the canvas realtime pipeline idea (normalized stroke points
// rendered in a SwiftUI `Canvas`), but ships strokes as GAME MOVES so the
// whole match — drawing included — lives in one replayable move list.
// Reducer: Content/PictionaryLogic.swift (deadline from server timestamps).
struct PictionaryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var now = Date()
    @State private var guessText = ""
    @State private var currentPoints: [[Double]] = []
    @State private var localStrokes: [PictionaryStroke] = []
    @State private var selectedColor = PictionaryView.palette[0]
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrated = false

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Stroke colors on the light board (drawing CONTENT, not UI ink —
    /// the couple's felt pens, readable on letter paper).
    static let palette = ["#2D2A32", "#E8467C", "#2D7FF9", "#1FA97C", "#F59E0B", "#8B5CF6"]
    /// The easel is a sheet of letter paper — pinned to the same hex the
    /// paper cards use so eraser strokes stay invisible.
    private static let boardHex = PaperRules.briefHex

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("games.card.pictionary.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
            }
        }
        .onReceive(clock) { date in
            now = date
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
        .onChange(of: phaseIsFinished) { _, isDone in
            if isDone { handleFinish() }
        }
        .onAppear {
            if phaseIsFinished { handleFinish() }
        }
    }

    // MARK: Derived state

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .pictionary else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    /// The other member's id from MY perspective (starter or not).
    private var theirId: String { myId == starterId ? otherId : starterId }

    private var deckLang: String { session?.payload?["lang"]?.stringValue ?? L10n.lang }

    private var roundCount: Int { engine.payloadInt("rounds", default: Pictionary.defaultRounds) }

    private var secs: Int { engine.payloadInt("secs", default: Pictionary.defaultSecs) }

    private var deck: [String] {
        Pictionary.deck(seed: engine.seed, rounds: roundCount, lang: deckLang)
    }

    private var events: [PictionaryEvent] {
        engine.orderedMoves.compactMap { move in
            switch move.data["kind"]?.stringValue {
            case "round_start":
                guard let round = move.data["round"]?.intValue else { return nil }
                return .roundStart(member: move.memberId, round: round, at: move.createdAt)
            case "guess":
                guard let round = move.data["round"]?.intValue,
                      let text = move.data["text"]?.stringValue else { return nil }
                return .guess(member: move.memberId, round: round, text: text, at: move.createdAt)
            default:
                return nil
            }
        }
    }

    private var gameState: PictionaryState {
        Pictionary.reduce(events: events, deck: deck, starter: starterId,
                          partner: otherId, secs: secs, now: now)
    }

    private var phaseIsFinished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.phase == .finished
    }

    private func artist(of round: Int) -> String {
        Pictionary.artist(round: round, starter: starterId, partner: otherId)
    }

    private func name(of memberId: String) -> String {
        memberId == myId ? (appState.me?.name ?? L10n.t("common.you")) : appState.partnerName
    }

    // MARK: Strokes (from the move list, round-scoped, clear-aware)

    private struct PictionaryStroke: Identifiable {
        let id: String
        let color: String
        let width: Double
        let points: [[Double]]
    }

    private func strokes(round: Int) -> [PictionaryStroke] {
        var result: [PictionaryStroke] = []
        for move in engine.orderedMoves {
            guard move.data["round"]?.intValue == round else { continue }
            switch move.data["kind"]?.stringValue {
            case "clear":
                result.removeAll()
            case "stroke":
                guard let raw = move.data["points"]?.arrayValue else { continue }
                let points = raw.compactMap { $0.arrayValue?.compactMap(\.numberValue) }
                    .filter { $0.count >= 2 }
                guard !points.isEmpty else { continue }
                result.append(PictionaryStroke(
                    id: move.id,
                    color: move.data["color"]?.stringValue ?? Self.palette[0],
                    width: move.data["width"]?.numberValue ?? 4,
                    points: points))
            default:
                break
            }
        }
        return result
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: Licht.lampengold)
                        .padding(LayoutMetrics.s(16))
                }
            } else if phaseIsFinished {
                endScreen
            } else if session.state == "active" {
                activeScreen
            } else {
                startScreen
            }
        } else {
            startScreen
        }
    }

    @ViewBuilder
    private var activeScreen: some View {
        switch gameState.phase {
        case .waitingStart(let round):
            waitingStartScreen(round: round, previous: nil)
        case .drawing(let round, let deadline):
            drawingScreen(round: round, deadline: deadline)
        case .roundOver(let round, let solved):
            waitingStartScreen(round: round + 1, previous: (round, solved))
        case .finished:
            endScreen
        }
    }

    // MARK: Start

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "paintpalette.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.pictionary.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.pict.setup.body", ["secs": "\(Pictionary.defaultSecs)"]))
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
            if await engine.create(api: appState.api, type: .pictionary,
                                   payload: makePayload()) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func makePayload() -> JSONValue {
        // The seed comes from the server (fairness contract).
        .object([
            "rounds": .number(Double(Pictionary.defaultRounds)),
            "secs": .number(Double(Pictionary.defaultSecs)),
            "lang": .string(L10n.lang)
        ])
    }

    private func resetLocalState() {
        guessText = ""
        currentPoints = []
        localStrokes = []
        sending = false
        didSendEnd = false
        celebrated = false
    }

    // MARK: Waiting for round start (+ previous-round interstitial)

    private func waitingStartScreen(round: Int, previous: (round: Int, solved: Bool)?) -> some View {
        let iAmArtist = artist(of: round) == myId
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader
                if let previous {
                    roundResultCard(round: previous.round, solved: previous.solved)
                }
                VStack(spacing: LayoutMetrics.s(12)) {
                    Image(systemName: iAmArtist ? "paintbrush.pointed.fill" : "magnifyingglass")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(coupleTint.blend)
                        .accessibilityHidden(true)
                    Text(L10n.t("games.pict.round.header",
                                ["n": "\(round + 1)", "total": "\(roundCount)"]))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(iAmArtist
                         ? L10n.t("games.pict.youDraw")
                         : L10n.t("games.pict.partnerDraws", ["name": appState.partnerName]))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .multilineTextAlignment(.center)
                    if iAmArtist {
                        Button {
                            startRound(round)
                        } label: {
                            Text(L10n.t("games.pict.startRound"))
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sending)
                    } else {
                        ProgressView()
                            .tint(Nacht.sekundaer)
                    }
                }
                .frame(maxWidth: .infinity)
                .nightCard(padding: .hero)
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func roundResultCard(round: Int, solved: Bool) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: solved ? "checkmark.seal.fill" : "hourglass")
                .font(.system(.title2, design: .rounded))
                .foregroundStyle(solved ? Licht.glut : Nacht.sekundaer)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(solved
                     ? L10n.t("games.pict.solvedBy",
                              ["name": name(of: gameState.rounds[round].solvedBy ?? "")])
                     : L10n.t("games.pict.timeUp"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("games.pict.wordWas", ["word": deck[round]]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
        .onAppear {
            // The interstitial verdict is visual only — speak it too.
            GamesA11y.announce(
                (solved
                 ? L10n.t("games.pict.solvedBy",
                          ["name": name(of: gameState.rounds[round].solvedBy ?? "")])
                 : L10n.t("games.pict.timeUp"))
                + " " + L10n.t("games.pict.wordWas", ["word": deck[round]]))
        }
    }

    private func startRound(_ round: Int) {
        guard !sending else { return }
        sending = true
        localStrokes = []
        currentPoints = []
        Task {
            let data = JSONValue.object([
                "kind": .string("round_start"),
                "round": .number(Double(round))
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                SoundEngine.shared.play(.chime)
                Haptics.shared.tap()
            }
            sending = false
        }
    }

    // MARK: Drawing round

    /// Phone: stacked. Wide regular panes: the canvas centered like an
    /// easel, score/timer/word + tools/guesses in the rail (roadmap 22) —
    /// the guesser watches the drawing WHILE typing, no scroll in between.
    private func drawingScreen(round: Int, deadline: Date) -> some View {
        let iAmArtist = artist(of: round) == myId
        return GameTableContainer(gameType: "pictionary") { paneWidth in
            GameTableLayout(gameType: "pictionary", paneWidth: paneWidth) {
                boardCard(round: round, drawable: iAmArtist)
                    .gameActGated()
            } rail: {
                VStack(spacing: LayoutMetrics.s(12)) {
                    scoreHeader
                    timerBar(deadline: deadline)
                    if iAmArtist {
                        wordBanner(word: deck[round])
                        artistTools(round: round)
                    } else {
                        guessBanner
                        guessInput(round: round)
                    }
                    guessList(round: round)
                }
                .gameActGated()
            }
            .scrollDismissesKeyboard(.interactively)
        } stacked: {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(12)) {
                    scoreHeader
                    timerBar(deadline: deadline)
                    if iAmArtist {
                        wordBanner(word: deck[round])
                    } else {
                        guessBanner
                    }
                    boardCard(round: round, drawable: iAmArtist)
                    if iAmArtist {
                        artistTools(round: round)
                    } else {
                        guessInput(round: round)
                    }
                    guessList(round: round)
                }
                .gameActGated()
                .padding(LayoutMetrics.s(16))
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var scoreHeader: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            scoreChip(name: appState.me?.name ?? L10n.t("common.you"),
                      score: gameState.score(of: myId), tint: Papier.aufNacht)
            Spacer(minLength: 0)
            Text(L10n.t("games.pict.solvedCount",
                        ["n": "\(gameState.solvedCount)", "total": "\(roundCount)"]))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
            Spacer(minLength: 0)
            scoreChip(name: appState.partnerName,
                      score: gameState.score(of: theirId), tint: Papier.aufNacht)
        }
        .nightCard(grain: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.a11y.score"))
        .accessibilityValue(L10n.t("games.a11y.scoreValue",
                                   ["mine": "\(gameState.score(of: myId))",
                                    "name": appState.partnerName,
                                    "theirs": "\(gameState.score(of: theirId))"])
                            + ", " + L10n.t("games.pict.solvedCount",
                                            ["n": "\(gameState.solvedCount)",
                                             "total": "\(roundCount)"]))
    }

    private func scoreChip(name: String, score: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            Text("\(score)")
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(tint)
        }
    }

    private func timerBar(deadline: Date) -> some View {
        let remaining = max(0, deadline.timeIntervalSince(now))
        return HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "timer")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .accessibilityHidden(true)
            GameProgressBar(progress: remaining / Double(max(secs, 1)),
                            tint: remaining < 15 ? Licht.glut : coupleTint.blend,
                            track: Papier.nachtInnenFill)
            Text("\(Int(remaining))s")
                .font(.system(.caption, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(remaining < 15 ? Licht.glut : Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(36), alignment: .trailing)
        }
        .nightCard(grain: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.pict.a11y.timer"))
        .accessibilityValue(L10n.t("games.pict.a11y.timerValue", count: Int(remaining)))
    }

    private func wordBanner(word: String) -> some View {
        VStack(spacing: 4) {
            Text(L10n.t("games.pict.yourWord"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
            // The secret word glows in the warm lamp gold — the one
            // note only the artist may read at the night table.
            Text(word)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Licht.lampengold)
        }
        .frame(maxWidth: .infinity)
        .nightCard(grain: false)
    }

    private var guessBanner: some View {
        Text(L10n.t("games.pict.guessHint", ["name": appState.partnerName]))
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Nacht.sekundaer)
            .frame(maxWidth: .infinity)
            .nightCard(grain: false)
    }

    // MARK: Board

    private func boardCard(round: Int, drawable: Bool) -> some View {
        GeometryReader { geo in
            let board = ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: Self.boardHex))
                Canvas { context, size in
                    for stroke in strokes(round: round) {
                        draw(points: stroke.points, colorHex: stroke.color,
                             width: stroke.width, context: &context, size: size)
                    }
                    for stroke in localStrokes {
                        draw(points: stroke.points, colorHex: stroke.color,
                             width: stroke.width, context: &context, size: size)
                    }
                    if !currentPoints.isEmpty {
                        draw(points: currentPoints, colorHex: selectedColor,
                             width: 4, context: &context, size: size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            // The sheet edge — the easel paper ends in a kante hairline
            // like every other Zettel on the night table.
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            if drawable {
                board.gesture(drawGesture(round: round, size: geo.size))
            } else {
                board
            }
        }
        .aspectRatio(1.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(drawable
            ? L10n.t("games.pict.a11y.board.artist", ["word": deck[round]])
            : L10n.t("games.pict.a11y.board.guesser", ["name": appState.partnerName]))
        // The artist keeps direct finger drawing even with VoiceOver on.
        .accessibilityAddTraits(drawable ? .allowsDirectInteraction : [])
    }

    /// Shared `StrokeRenderer` (pen look) — same smoothing and dot handling
    /// as the couple canvas, so guessers see exactly what the artist drew.
    private func draw(points: [[Double]], colorHex: String, width: Double,
                      context: inout GraphicsContext, size: CGSize) {
        StrokeRenderer.draw(points: points,
                            color: Color(hex: colorHex),
                            width: width,
                            tool: "pen",
                            boardColor: Color(hex: Self.boardHex),
                            context: &context,
                            size: size)
    }

    private func drawGesture(round: Int, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = Double(min(max(value.location.x / size.width, 0), 1))
                let y = Double(min(max(value.location.y / size.height, 0), 1))
                // Capture thinning keeps segments inside the move quota.
                if let last = currentPoints.last, last.count >= 2,
                   !StrokeGeometry.farEnough(x: x, y: y, lastX: last[0], lastY: last[1]) {
                    return
                }
                currentPoints.append([x, y])
                if currentPoints.count >= 300 {
                    let segment = currentPoints
                    currentPoints = [segment[segment.count - 1]]
                    submitStroke(round: round, points: segment)
                }
            }
            .onEnded { _ in
                let segment = currentPoints
                currentPoints = []
                guard !segment.isEmpty else { return }
                submitStroke(round: round, points: segment)
            }
    }

    private func submitStroke(round: Int, points: [[Double]]) {
        // Optimistic local echo — the server copy replaces it on arrival.
        let local = PictionaryStroke(id: "local-\(UUID().uuidString)",
                                     color: selectedColor, width: 4, points: points)
        localStrokes.append(local)
        Task {
            let data = JSONValue.object([
                "kind": .string("stroke"),
                "round": .number(Double(round)),
                "color": .string(selectedColor),
                "width": .number(4),
                "points": .array(points.map { pair in
                    .array(pair.map { .number($0) })
                })
            ])
            if await engine.sendMove(api: appState.api, data: data) {
                localStrokes.removeAll { $0.id == local.id }
            }
        }
    }

    private func artistTools(round: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            ForEach(Self.palette, id: \.self) { hex in
                Button {
                    selectedColor = hex
                    Haptics.shared.tap()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                        .overlay(
                            Circle().strokeBorder(selectedColor == hex
                                                  ? Papier.aufNacht : Nacht.naht,
                                                  lineWidth: selectedColor == hex
                                                  ? 2.5 : Theme.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(colorA11yName(hex))
                .accessibilityAddTraits(selectedColor == hex ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
            Button {
                clearBoard(round: round)
            } label: {
                Image(systemName: "trash")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(34), height: LayoutMetrics.s(34))
                    .background(Circle().fill(Papier.nachtInnenFill))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("games.pict.a11y.clear"))
        }
        .nightCard(grain: false)
    }

    private func colorA11yName(_ hex: String) -> String {
        switch hex {
        case "#2D2A32": return L10n.t("games.pict.a11y.color.ink")
        case "#E8467C": return L10n.t("games.pict.a11y.color.pink")
        case "#2D7FF9": return L10n.t("games.pict.a11y.color.blue")
        case "#1FA97C": return L10n.t("games.pict.a11y.color.green")
        case "#F59E0B": return L10n.t("games.pict.a11y.color.orange")
        default: return L10n.t("games.pict.a11y.color.purple")
        }
    }

    private func clearBoard(round: Int) {
        localStrokes = []
        currentPoints = []
        Task {
            let data = JSONValue.object([
                "kind": .string("clear"),
                "round": .number(Double(round))
            ])
            _ = await engine.sendMove(api: appState.api, data: data)
        }
    }

    // MARK: Guessing

    private func guessInput(round: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            TextField(L10n.t("games.pict.guessPlaceholder"), text: $guessText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Papier.aufNacht)
                .submitLabel(.send)
                .onSubmit { sendGuess(round: round) }
            Button {
                sendGuess(round: round)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    // onBlend glyph on the lamplit couple blend — the
                    // night-safe variant of the Quiz send-stamp pattern.
                    .foregroundStyle(coupleTint.onBlend)
                    .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                    .background(Circle().fill(coupleTint.blend))
            }
            .buttonStyle(.plain)
            .disabled(guessText.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            .accessibilityLabel(L10n.t("games.a11y.sendGuess"))
        }
        .nightCard(grain: false)
    }

    private func sendGuess(round: Int) {
        let text = guessText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !sending else { return }
        sending = true
        guessText = ""
        Task {
            let data = JSONValue.object([
                "kind": .string("guess"),
                "round": .number(Double(round)),
                "text": .string(text)
            ])
            _ = await engine.sendMove(api: appState.api, data: data)
            sending = false
        }
    }

    private func guessList(round: Int) -> some View {
        let guesses: [PictionaryGuess] = gameState.rounds.indices.contains(round)
            ? Array(gameState.rounds[round].guesses.suffix(4))
            : []
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(guesses.enumerated()), id: \.offset) { _, guess in
                HStack(spacing: 8) {
                    Text(guess.correct ? "✅" : "💬")
                        .font(Typo.caption)
                    Text("\(name(of: guess.member)): \(guess.text)")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(guess.correct ? Licht.glut : Nacht.sekundaer)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name(of: guess.member)): \(guess.text)")
                .accessibilityValue(guess.correct ? L10n.t("games.pict.a11y.guessCorrect") : "")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(guesses.isEmpty ? 0 : 1)
    }

    // MARK: Finish

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrated {
            celebrated = true
            let mine = gameState.score(of: myId)
            let theirs = gameState.score(of: theirId)
            let verdictKey = mine > theirs ? "games.pict.a11y.won"
                : (mine == theirs ? "games.pict.a11y.tie" : "games.pict.a11y.lost")
            GamesA11y.announce(L10n.t(verdictKey,
                                      ["mine": "\(mine)", "theirs": "\(theirs)"]))
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
                scores[id] = .number(Double(gameState.score(of: id)))
            }
            await engine.end(api: appState.api, result: .object(["scores": .object(scores)]))
        }
    }

    private var endScreen: some View {
        let mine = gameState.score(of: myId)
        let theirs = gameState.score(of: theirId)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: mine > theirs ? "trophy.fill" : (mine == theirs ? "heart.circle.fill" : "paintpalette.fill"))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(mine > theirs ? Licht.lampengold : coupleTint.blend)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(endLine(mine: mine, theirs: theirs))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                scoreHeader
                Text(L10n.t("games.pict.solvedTotal",
                            ["n": "\(gameState.solvedCount)", "total": "\(roundCount)"]))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
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

    private func endLine(mine: Int, theirs: Int) -> String {
        if mine > theirs { return L10n.t("games.pict.win.you") }
        if mine < theirs { return L10n.t("games.pict.win.partner", ["name": appState.partnerName]) }
        return L10n.t("games.pict.tie")
    }
}
