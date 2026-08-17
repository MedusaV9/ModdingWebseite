import SwiftUI
import Combine

// Replay & Zuschauer-Modus 🎬 — finished matches play back as a movie
// (moves in original order, async pauses time-lapsed, the turning point
// starred), and open sessions can be watched live: the relay broadcasts
// `game_move` to ALL sockets of the couple, so a second device (iPad!)
// renders the same feed read-only. Core: Content/ReplayLogic.swift.

// MARK: - Hub (live sessions + finished games)

struct ReplayHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    /// The ONE page the hub loads — the section header names this window
    /// honestly („die letzten 50", Fix-Runde 3, Befund 8b) instead of
    /// implying the register's whole-history replay count is browsable.
    private static let seitenFenster = 50

    @State private var openSessions: [GameSession] = []
    @State private var finished: [GameSession] = []
    @State private var loading = true
    @State private var requestFailed = false

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                content
                    .padding(LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(12))
            }
            .refreshable { await load() }
        }
        .navigationTitle(L10n.t("games.replay.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent,
                  event.type == .gameCreated || event.type == .gameEnded else { return }
            Task { await load() }
        }
    }

    private func load() async {
        guard let api = appState.api else {
            requestFailed = true
            loading = false
            return
        }
        loading = true
        requestFailed = false
        do {
            async let open = api.openGames()
            async let history = api.games(limit: Self.seitenFenster)
            let (openValue, historyValue) = try await (open, history)
            openSessions = openValue.filter { $0.kind != nil }
            finished = historyValue.filter { $0.state == "ended" && !$0.moves.isEmpty
                && $0.kind != nil }
        } catch {
            requestFailed = true
        }
        loading = false
    }

    private var phase: SurfacePhase {
        SurfaceState.resolve(
            loading: loading,
            hasContent: !finished.isEmpty || !openSessions.isEmpty,
            connected: appState.socket.state == .connected,
            requestFailed: requestFailed
        )
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .tint(coupleTint.blend)
                .padding(.top, LayoutMetrics.s(120))
        case .offline:
            StateNoticeView(
                kind: .offline,
                title: L10n.t("state.offline.title"),
                message: L10n.t("state.offline.body"),
                retry: { Task { await load() } }
            )
            .padding(.top, LayoutMetrics.s(48))
        case .failed:
            StateNoticeView(
                kind: .failed,
                title: L10n.t("state.failed.title"),
                message: L10n.t("state.failed.body"),
                retry: { Task { await load() } }
            )
            .padding(.top, LayoutMetrics.s(48))
        case .empty:
            EmptyStateView(systemImage: "film.stack",
                           title: L10n.t("games.replay.emptyTitle"),
                           subtitle: L10n.t("games.replay.emptyBody"),
                           actionTitle: L10n.t("games.replay.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               dismiss()
                           })
                .padding(.top, LayoutMetrics.s(80))
        case .content:
            VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                if !openSessions.isEmpty {
                    SectionHeader(title: L10n.t("games.replay.liveSection"))
                    ForEach(openSessions) { session in
                        row(session, live: true)
                    }
                }
                if !finished.isEmpty {
                    SectionHeader(title: L10n.t("games.replay.pastSection",
                                                ["n": "\(Self.seitenFenster)"]))
                    ForEach(finished) { session in
                        row(session, live: false)
                    }
                }
            }
        }
    }

    private func row(_ session: GameSession, live: Bool) -> some View {
        NavigationLink {
            ReplayPlayerView(initial: session)
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                GameKindGlyph(kind: session.kind, size: 22, tint: coupleTint.blend)
                    .frame(width: LayoutMetrics.s(42), height: LayoutMetrics.s(42))
                    .background(Circle().fill(Papier.nachtInnenFill))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.kind.map(PlayHubView.gameTitle(for:)) ?? "?")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(live
                         ? L10n.t("games.replay.liveMoves", ["n": "\(session.moves.count)"])
                         : prettyDate(session.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer(minLength: 0)
                if live {
                    PillTag(text: L10n.t("games.replay.liveBadge"), tint: Licht.glut)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "play.circle.fill")
                            .font(Typo.caption)
                        Text("\(session.moves.count)")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Licht.lampengold)
                }
            }
            .nightCard(padding: .compact, grain: false)
        }
        .buttonStyle(.plain)
    }

    private func prettyDate(_ date: Date) -> String {
        AppFormatters.date(
            date,
            language: L10n.lang,
            dateStyle: .medium,
            timeStyle: .short
        )
    }
}

// MARK: - Player (replay of an ended match / live spectating)

struct ReplayPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let initial: GameSession

    @State private var session: GameSession
    @State private var playIndex = -1
    @State private var playing = false
    @State private var speed = 1.0
    @State private var shared = false
    @State private var playbackTask: Task<Void, Never>?

    init(initial: GameSession) {
        self.initial = initial
        _session = State(initialValue: initial)
    }

    private var live: Bool { session.state != "ended" }

    var body: some View {
        ZStack {
            DreamyBackground()
            VStack(spacing: LayoutMetrics.s(12)) {
                header
                feed
                if !live {
                    controls
                }
            }
            .padding(LayoutMetrics.s(16))
        }
        .navigationTitle(session.kind.map(PlayHubView.gameTitle(for:)) ?? "🎬")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Fresh copy (spectator may open the hub before the last frames).
            if let latest = try? await appState.api?.game(id: session.id) {
                session = latest
            }
            if live {
                playIndex = steps.count - 1
            } else if playIndex < 0 {
                startPlayback(from: -1)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleLive(event)
        }
        .onDisappear {
            playbackTask?.cancel()
        }
    }

    // MARK: Steps (moves → feed entries)

    private struct Step: Identifiable {
        let id: String
        let memberId: String
        let emoji: String
        let text: String
        let at: Date
        let highlight: Bool
    }

    private var orderedMoves: [GameMove] {
        session.moves.sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }
    }

    /// Feed steps — consecutive canvas strokes of one artist collapse into
    /// a single "draws…" entry so Montagsmaler replays stay watchable.
    private var steps: [Step] {
        let type = session.kind?.rawValue ?? "?"
        var result: [Step] = []
        var strokeRun = 0
        var strokeMember = ""
        var strokeId = ""
        var strokeAt = Date()
        func flushStrokes() {
            guard strokeRun > 0 else { return }
            result.append(Step(id: strokeId, memberId: strokeMember,
                               emoji: Replay.stepEmoji(gameType: type, moveKind: "stroke"),
                               text: L10n.t("games.replay.step.strokes", ["n": "\(strokeRun)"]),
                               at: strokeAt, highlight: false))
            strokeRun = 0
        }
        for move in orderedMoves {
            let kind = move.data["kind"]?.stringValue ?? ""
            if kind == "stroke" {
                if strokeRun > 0 && strokeMember != move.memberId {
                    flushStrokes()
                }
                if strokeRun == 0 {
                    strokeMember = move.memberId
                    strokeId = move.id
                    strokeAt = move.createdAt
                }
                strokeRun += 1
                continue
            }
            flushStrokes()
            result.append(step(for: move, type: type, kind: kind))
        }
        flushStrokes()
        return result
    }

    private func step(for move: GameMove, type: String, kind: String) -> Step {
        let (text, magnitude) = describe(move: move, type: type, kind: kind)
        return Step(id: move.id, memberId: move.memberId,
                    emoji: Replay.stepEmoji(gameType: type, moveKind: kind),
                    text: text, at: move.createdAt,
                    highlight: Replay.isHighlight(gameType: type, moveKind: kind,
                                                  magnitude: magnitude))
    }

    /// Localized feed line + highlight magnitude per move.
    private func describe(move: GameMove, type: String, kind: String) -> (String, Int) {
        let data = move.data
        switch (type, kind) {
        case (_, "commit"):
            return (L10n.t("games.replay.step.commit"), 0)
        case (_, "reveal"):
            let verified = data["verified"]?.boolValue ?? false
            return (L10n.t(verified ? "games.replay.step.revealVerified"
                                    : "games.replay.step.reveal"), 0)
        case ("battleship", "salvo"):
            let n = data["cells"]?.arrayValue?.count ?? 0
            return (L10n.t("games.replay.step.salvo", ["n": "\(n)"]), 0)
        case ("battleship", "report"):
            let hits = data["hits"]?.arrayValue?.count ?? 0
            let sunk = data["sunk"]?.arrayValue?.count ?? 0
            if sunk > 0 {
                return (L10n.t("games.replay.step.sunk", ["n": "\(sunk)"]), sunk)
            }
            return (L10n.t("games.replay.step.report", ["n": "\(hits)"]), 0)
        case ("pictionary", "round_start"):
            let round = data["round"]?.intValue ?? 0
            return (L10n.t("games.replay.step.round", ["n": "\(round + 1)"]), 0)
        case ("pictionary", "guess"):
            let text = data["text"]?.stringValue ?? "?"
            return (L10n.t("games.replay.step.pictGuess", ["text": text]), 0)
        case ("kniffel", "roll"):
            return (L10n.t("games.replay.step.roll"), 0)
        case ("kniffel", "score"):
            let category = data["category"]?.stringValue ?? "?"
            return (L10n.t("games.replay.step.score",
                           ["cat": L10n.t("games.kn.cat.\(category)")]), 0)
        case ("movieroulette", "swipe"):
            if let match = data["match"]?.objectValue,
               let title = match["title"]?.stringValue {
                return (L10n.t("games.replay.step.match", ["title": title]), 1)
            }
            let liked = data["like"]?.boolValue ?? false
            return (L10n.t(liked ? "games.replay.step.like" : "games.replay.step.nope"), 0)
        case ("stadtlandfluss", "rate"):
            return (L10n.t("games.replay.step.rate"), 0)
        case ("twotruths", "statements"):
            return (L10n.t("games.replay.step.statements"), 0)
        case ("twotruths", "guess"):
            return (L10n.t("games.replay.step.ttGuess"), 0)
        case ("dailyquests", "quest_done"):
            return (L10n.t("games.replay.step.quest"), 1)
        // W8C board & duel games — magnitudes follow Replay.isHighlight
        // (captures / flips / boxes / stones / match).
        case ("dame", "move"):
            let path = data["path"]?.arrayValue?.compactMap(\.intValue) ?? []
            let captures = data["captures"]?.arrayValue?.count ?? 0
            if captures > 0 {
                return (L10n.t("games.replay.step.dameCapture", ["n": "\(captures)"]), captures)
            }
            let from = path.first.map { BoardDuel.squareName($0, size: 8) } ?? "?"
            let to = path.last.map { BoardDuel.squareName($0, size: 8) } ?? "?"
            return (L10n.t("games.replay.step.damePath", ["from": from, "to": to]), 0)
        case ("reversi", "place"):
            let flips = data["flips"]?.arrayValue?.count ?? 0
            let square = data["index"]?.intValue.map { BoardDuel.squareName($0, size: 8) } ?? "?"
            return (L10n.t("games.replay.step.reversiPlace",
                           ["square": square, "n": "\(flips)"]), flips)
        case ("reversi", "pass"):
            return (L10n.t("games.replay.step.reversiPass"), 0)
        case ("kaesekaestchen", "edge"):
            let boxes = data["boxes"]?.arrayValue?.count ?? 0
            if boxes > 0 {
                return (L10n.t("games.replay.step.kaeseClosed", ["n": "\(boxes)"]), boxes)
            }
            return (L10n.t("games.replay.step.kaeseEdge"), 0)
        case ("gomoku", "place"):
            let square = data["index"]?.intValue.map { BoardDuel.squareName($0, size: 15) } ?? "?"
            return (L10n.t("games.replay.step.gomokuPlace", ["square": square]), 0)
        case ("mancala", "sow"):
            let pit = (data["pit"]?.intValue ?? 0) + 1
            let captured = data["captured"]?.intValue ?? 0
            if captured > 0 {
                return (L10n.t("games.replay.step.mancalaCapture",
                               ["n": "\(pit)", "c": "\(captured)"]), captured)
            }
            return (L10n.t("games.replay.step.mancalaSow", ["n": "\(pit)"]), 0)
        case ("memoryduo", "flip"):
            if data["match"]?.boolValue == true {
                return (L10n.t("games.replay.step.memoryMatch"), 1)
            }
            let n = (data["index"]?.intValue ?? 0) + 1
            return (L10n.t("games.replay.step.memoryFlip", ["n": "\(n)"]), 0)
        default:
            return (L10n.t("games.replay.step.generic"), 0)
        }
    }

    private var turningPointIndex: Int? {
        live ? nil : Replay.turningPoint(highlights: steps.map(\.highlight))
    }

    // MARK: Live spectating

    private func handleLive(_ event: ServerEvent) {
        switch event.type {
        case .gameMove:
            guard let payload = event.decode(GameMovePayload.self),
                  payload.gameId == session.id,
                  !session.moves.contains(where: { $0.id == payload.move.id }) else { return }
            session.moves.append(payload.move)
            if live {
                playIndex = steps.count - 1
                SoundEngine.shared.play(.click)
            }
        case .gameEnded:
            if let game = event.decode(GameOnlyResponse.self)?.game, game.id == session.id {
                session = game
                playIndex = steps.count - 1
            }
        default:
            break
        }
    }

    // MARK: Header / feed / controls

    private var header: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            GameKindGlyph(kind: session.kind, size: 24, tint: coupleTint.blend)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(live
                     ? L10n.t("games.replay.watching")
                     : L10n.t("games.replay.movesCount", ["n": "\(steps.count)"]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                if let scores = scoresLine {
                    Text(scores)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            Spacer(minLength: 0)
            if live {
                PillTag(text: L10n.t("games.replay.liveBadge"), tint: Licht.glut)
            } else {
                shareButton
            }
        }
        .nightCard(grain: false)
    }

    private var scoresLine: String? {
        guard let scores = session.result?["scores"]?.objectValue else { return nil }
        let mine = appState.memberId.flatMap { scores[$0]?.intValue } ?? 0
        let theirs = scores.first { $0.key != appState.memberId }?.value.intValue ?? 0
        return L10n.t("games.replay.finalScore", ["a": "\(mine)", "b": "\(theirs)"])
    }

    private var feed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LayoutMetrics.s(8)) {
                    ForEach(Array(steps.prefix(playIndex + 1).enumerated()),
                            id: \.element.id) { index, step in
                        stepRow(step, index: index)
                            .id(step.id)
                    }
                }
                .padding(.vertical, LayoutMetrics.s(4))
            }
            .onChange(of: playIndex) { _, new in
                guard new >= 0, new < steps.count else { return }
                withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                    proxy.scrollTo(steps[new].id, anchor: .bottom)
                }
            }
        }
    }

    private func stepRow(_ step: Step, index: Int) -> some View {
        VStack(spacing: LayoutMetrics.s(6)) {
            if index == turningPointIndex {
                HStack(spacing: 6) {
                    Text("⭐️")
                        .accessibilityHidden(true)
                    Text(L10n.t("games.replay.turningPoint"))
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(Licht.lampengold)
                    Text("⭐️")
                        .accessibilityHidden(true)
                }
            }
            // Nacht & Licht: every feed entry is an opaque night Zettel on
            // the table — paper-white ink for the play, the ember stars the
            // highlights (two-materials law: no translucent pseudo-glass).
            // Split into small typed helpers: the combined ternary/overlay
            // expression sent Xcode's type-checker over its time budget.
            stepRowContent(step)
                .padding(LayoutMetrics.s(10))
                .background(zettelBackground(highlight: step.highlight))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(memberName(step.memberId) + ": " + step.text)
                .accessibilityValue(stepA11yValue(step))
        }
    }

    private func stepRowContent(_ step: Step) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Text(step.emoji)
                .font(.system(.title3, design: .rounded))
            VStack(alignment: .leading, spacing: 2) {
                Text(memberName(step.memberId))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(step.text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(step.at.formatted(date: .omitted, time: .shortened))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            if step.highlight {
                Image(systemName: "sparkles")
                    .foregroundStyle(Licht.glut)
                    .accessibilityHidden(true)
            }
        }
    }

    private func zettelBackground(highlight: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        let wash: Color = highlight ? Licht.glut.opacity(0.10) : Color.clear
        let edge: Color = highlight ? Licht.glut.opacity(0.45) : Nacht.naht
        return shape
            .fill(Papier.nachtkarton)
            .overlay(shape.fill(wash))
            .overlay(shape.strokeBorder(edge, lineWidth: Theme.hairlineWidth))
    }

    private func stepA11yValue(_ step: Step) -> String {
        var value = step.at.formatted(date: .omitted, time: .shortened)
        if step.highlight {
            value += ", " + L10n.t("games.replay.a11y.highlight")
        }
        return value
    }

    // Playback deck: floating projector chrome over the night table — this
    // is UI that hovers, so it stays glass (chrome), never paper.
    private var controls: some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundStyle(coupleTint.blend)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t(playing
                                       ? "games.replay.a11y.pause"
                                       : "games.replay.a11y.play"))
            Slider(value: Binding(
                get: { Double(Swift.max(0, playIndex)) },
                set: { value in
                    pause()
                    playIndex = Int(value.rounded())
                }
            ), in: 0...Double(Swift.max(1, steps.count - 1)), step: 1)
            .tint(coupleTint.blend)
            .accessibilityLabel(L10n.t("games.replay.a11y.position"))
            Button {
                speed = speed >= 4 ? 1 : speed * 2
                if playing { startPlayback(from: playIndex) }
            } label: {
                Text("\(Int(speed))×")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(30))
                    .background(Capsule().fill(Theme.innerFill))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("games.replay.a11y.speed", ["n": "\(Int(speed))"]))
        }
        .padding(.vertical, LayoutMetrics.s(8))
        .padding(.horizontal, LayoutMetrics.s(14))
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    // MARK: Playback engine (time-lapse via ReplayLogic)

    private func togglePlay() {
        if playing {
            pause()
        } else {
            let start = playIndex >= steps.count - 1 ? -1 : playIndex
            startPlayback(from: start)
        }
    }

    private func pause() {
        playing = false
        playbackTask?.cancel()
    }

    private func startPlayback(from start: Int) {
        playbackTask?.cancel()
        playing = true
        playIndex = start
        let all = steps
        playbackTask = Task {
            var previous: Date? = start >= 0 && start < all.count ? all[start].at : nil
            for index in (start + 1)..<all.count {
                let gap = previous.map { all[index].at.timeIntervalSince($0) } ?? 0
                let delay = Replay.playbackDelay(forGap: gap, speed: speed)
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                playIndex = index
                previous = all[index].at
                if all[index].highlight {
                    Haptics.shared.tap()
                }
                if index == turningPointIndex {
                    SoundEngine.shared.play(.sparkle)
                }
            }
            playing = false
            if !all.isEmpty {
                SoundEngine.shared.play(.chime)
            }
        }
    }

    // MARK: Share recap to chat

    private var shareButton: some View {
        Button {
            shareToChat()
        } label: {
            Image(systemName: shared ? "checkmark.circle.fill" : "paperplane.fill")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(shared ? Nacht.sekundaer : Licht.lampengold)
        }
        .buttonStyle(.plain)
        .disabled(shared)
        .accessibilityLabel(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"))
    }

    private func shareToChat() {
        guard let api = appState.api, !shared, let kind = session.kind else { return }
        var lines = [
            L10n.t("games.replay.share.title",
                   ["emoji": PlayHubView.gameEmoji(for: kind),
                    "game": PlayHubView.gameTitle(for: kind),
                    "n": "\(steps.count)"])
        ]
        if let scores = scoresLine {
            lines.append(scores)
        }
        if let turn = turningPointIndex {
            lines.append(L10n.t("games.replay.share.turn", ["text": steps[turn].text]))
        }
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: lines.joined(separator: "\n"))
                shared = true
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func memberName(_ id: String) -> String {
        if id == appState.memberId {
            return appState.me?.name ?? L10n.t("common.you")
        }
        return appState.couple?.members.first { $0.id == id }?.name ?? appState.partnerName
    }
}
