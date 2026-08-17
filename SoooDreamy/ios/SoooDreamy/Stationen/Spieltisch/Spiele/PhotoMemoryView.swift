import SwiftUI
import Combine

/// Foto-Memory 🖼️ — realtime pairs with the couple's OWN gallery photos.
///
/// The creator picks the pair count; the create payload carries the chosen
/// `photoIds` plus a seed, so both phones derive the identical shuffled
/// board (`PhotoMemory.tiles`). One move = one full turn (two flipped
/// tiles): `{"kind": "flip", "first": i, "second": j}`. Match → point and
/// the same player goes again; miss → turn switches (reducer in
/// Content/CoupleGamesLogic.swift, pinned by the Linux logic tests).
struct PhotoMemoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var photos: [Photo] = []
    @State private var photosLoaded = false
    @State private var setupPairs = 6
    @State private var pendingFirst: Int?
    @State private var revealed: Set<Int> = []
    @State private var revealTask: Task<Void, Never>?
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrate = false

    private static let pairOptions = [4, 6, 8]
    private static let minPairs = 4

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if celebrate {
                FloatingHeartsView(emojis: ["🖼️", "💞", "🏆", "✨", "📸"], count: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.photomemory.title"))
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
            await loadPhotos()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
        }
        .onChange(of: flips.count) { old, new in
            if new > old { revealLatestFlip() }
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
        guard let current = engine.session, current.kind == .photomemory else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var photoIds: [String] {
        session?.payload?["photoIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private var pairCount: Int { max(2, min(photoIds.count, PhotoMemory.maxPairs)) }

    private var tiles: [Int] {
        guard session != nil, !photoIds.isEmpty else { return [] }
        return PhotoMemory.tiles(pairCount: pairCount, seed: engine.seed)
    }

    private var flips: [(memberId: String, first: Int, second: Int)] {
        engine.moves(kind: "flip").compactMap { move in
            guard let first = move.data["first"]?.intValue,
                  let second = move.data["second"]?.intValue else { return nil }
            return (move.memberId, first, second)
        }
    }

    private var boardState: PhotoMemoryState {
        PhotoMemory.reduce(flips: flips, tiles: tiles, starter: starterId, partner: otherId)
    }

    private var myTurn: Bool { boardState.turn == appState.memberId }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended",
              !tiles.isEmpty else { return false }
        return PhotoMemory.finished(state: boardState, tiles: tiles)
    }

    private func photo(forPair pairIndex: Int) -> Photo? {
        guard photoIds.indices.contains(pairIndex) else { return nil }
        let id = photoIds[pairIndex]
        return photos.first { $0.id == id }
    }

    private func name(of memberId: String) -> String {
        if memberId == appState.memberId {
            return appState.me?.name ?? L10n.t("common.you")
        }
        return appState.partnerName
    }

    // MARK: Photos

    private func loadPhotos() async {
        guard let api = appState.api else { return }
        if let loaded = try? await api.photos() {
            photos = loaded
        }
        photosLoaded = true
    }

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
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.photomemory.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.memory.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !photosLoaded {
                    ProgressView()
                        .tint(Nacht.sekundaer)
                } else if photos.count < Self.minPairs {
                    Text(L10n.t("games.memory.needPhotos", ["n": String(Self.minPairs)]))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.glut)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    pairsPicker
                    Button {
                        startGame(pairs: setupPairs)
                    } label: {
                        Text(L10n.t("games.start"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(engine.busy)
                }
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var pairsPicker: some View {
        VStack(spacing: 8) {
            Text(L10n.t("games.memory.setup.pairs"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Self.pairOptions, id: \.self) { option in
                    Button {
                        setupPairs = option
                        Haptics.shared.tap()
                    } label: {
                        Text("\(option)")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(option > photos.count
                                             ? Nacht.tertiaer : Papier.aufNacht)
                            .frame(width: LayoutMetrics.s(56), height: LayoutMetrics.s(44))
                            .background(
                                Capsule().fill(setupPairs == option
                                               ? coupleTint.blend.opacity(0.16)
                                               : Papier.nachtInnenFill)
                            )
                            .overlay(
                                Capsule().strokeBorder(setupPairs == option
                                                       ? coupleTint.blend : Nacht.naht,
                                                       lineWidth: setupPairs == option
                                                       ? 1.5 : Theme.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(option > photos.count)
                }
            }
        }
    }

    private func startGame(pairs: Int) {
        guard !engine.busy, photos.count >= Self.minPairs else { return }
        let count = min(pairs, photos.count, PhotoMemory.maxPairs)
        let picked = photos.shuffled().prefix(count).map(\.id)
        Task {
            resetLocalState()
            // The seed comes from the server (fairness contract).
            let payload = JSONValue.object([
                "pairs": .number(Double(count)),
                "photoIds": .array(picked.map { .string($0) })
            ])
            if await engine.create(api: appState.api, type: .photomemory, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        pendingFirst = nil
        revealed = []
        revealTask?.cancel()
        sending = false
        didSendEnd = false
        celebrate = false
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                scoreHeader
                lastFlipBanner
                boardGrid
                if !myTurn {
                    GameWaitingHint()
                }
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var scoreHeader: some View {
        let state = boardState
        return HStack(spacing: LayoutMetrics.s(12)) {
            scoreBadge(memberId: appState.memberId, score: state.score(of: appState.memberId ?? ""),
                       alignment: .leading, ink: Papier.aufNacht)
            Spacer()
            PillTag(text: myTurn
                    ? L10n.t("games.memory.yourTurn")
                    : L10n.t("games.memory.partnerTurn", ["name": appState.partnerName]),
                    tint: myTurn ? Licht.glut : coupleTint.blend)
            Spacer()
            scoreBadge(memberId: appState.partner?.id,
                       score: state.score(of: appState.partner?.id ?? ""),
                       alignment: .trailing, ink: Papier.aufNacht)
        }
        .nightCard(padding: .compact, grain: false)
    }

    private func scoreBadge(memberId: String?, score: Int,
                            alignment: HorizontalAlignment, ink: Color) -> some View {
        let member = appState.couple?.members.first { $0.id == memberId }
        return HStack(spacing: 8) {
            if alignment == .leading {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
            Text("\(score)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(ink)
            if alignment == .trailing {
                EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(34))
            }
        }
    }

    @ViewBuilder
    private var lastFlipBanner: some View {
        if let flip = flips.last {
            let isMatch = tiles.indices.contains(flip.first)
                && tiles.indices.contains(flip.second)
                && tiles[flip.first] == tiles[flip.second]
            PillTag(text: isMatch
                    ? L10n.t("games.memory.match")
                    : L10n.t("games.memory.noMatch", ["name": name(of: boardState.turn)]),
                    tint: isMatch ? Licht.glut : coupleTint.blend)
        }
    }

    private var boardGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tiles.indices, id: \.self) { index in
                tileView(index: index)
            }
        }
        .paperCard(padding: .compact)
    }

    @ViewBuilder
    private func tileView(index: Int) -> some View {
        let pairIndex = tiles[index]
        let matchedBy = boardState.matched[pairIndex]
        let faceUp = matchedBy != nil || pendingFirst == index || revealed.contains(index)
        Button {
            tap(index: index)
        } label: {
            ZStack {
                // Card back = a tint-washed print on the paper board; the
                // matched frame carries the finder's ink.
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(faceUp ? Papier.innenFill : coupleTint.tinte.opacity(0.16))
                if faceUp {
                    tileImage(pairIndex: pairIndex)
                } else {
                    Image(systemName: "heart.fill")
                        .font(.system(.title2, design: .rounded))
                        .foregroundStyle(coupleTint.tinte)
                        .accessibilityHidden(true)
                }
                if let matchedBy {
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(matchedBy == appState.memberId
                                      ? coupleTint.tintePrimary : coupleTint.tinteSecondary,
                                      lineWidth: 2)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous))
            .rotation3DEffect(.degrees(faceUp ? 0 : 180), axis: (x: 0, y: 1, z: 0))
            .animation(Theme.Motion.playful, value: faceUp)
        }
        .buttonStyle(.plain)
        .disabled(!myTurn || sending || faceUp)
    }

    @ViewBuilder
    private func tileImage(pairIndex: Int) -> some View {
        if let photo = photo(forPair: pairIndex) {
            AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                default:
                    Image(systemName: "camera.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                        .accessibilityHidden(true)
                }
            }
        } else {
            // Photo deleted meanwhile — the pair index still identifies it.
            Image(systemName: "camera.fill")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .accessibilityHidden(true)
        }
    }

    // MARK: Actions

    private func tap(index: Int) {
        guard myTurn, !sending else { return }
        Haptics.shared.tap()
        if pendingFirst == nil {
            pendingFirst = index
            SoundEngine.shared.play(.click)
            return
        }
        guard let first = pendingFirst, first != index else { return }
        sending = true
        Task {
            let data = JSONValue.object([
                "kind": .string("flip"),
                "first": .number(Double(first)),
                "second": .number(Double(index))
            ])
            _ = await engine.sendMove(api: appState.api, data: data)
            pendingFirst = nil
            sending = false
        }
    }

    /// Show the two tiles of the newest flip briefly; matches stay face-up
    /// via the reducer, misses flip back after a beat.
    private func revealLatestFlip() {
        guard let flip = flips.last else { return }
        let isMatch = tiles.indices.contains(flip.first)
            && tiles.indices.contains(flip.second)
            && tiles[flip.first] == tiles[flip.second]
        revealed = [flip.first, flip.second]
        if isMatch {
            SoundEngine.shared.play(.success)
            Haptics.shared.success()
        } else {
            SoundEngine.shared.play(.pop)
        }
        revealTask?.cancel()
        revealTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            revealed = []
        }
    }

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrate {
            celebrate = true
            let state = boardState
            let mine = state.score(of: appState.memberId ?? "")
            let theirs = state.score(of: appState.partner?.id ?? "")
            if mine > theirs {
                GameEndCelebration.win(visual: .localHearts)
            } else if mine == theirs {
                GameEndCelebration.tie(visual: .localHearts)
            } else {
                GameEndCelebration.loss(visual: .localHearts)
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            await engine.end(api: appState.api, result: resultJSON)
        }
    }

    private var resultJSON: JSONValue {
        let state = boardState
        var scores: [String: JSONValue] = [:]
        for id in [starterId, otherId] where !id.isEmpty {
            scores[id] = .number(Double(state.score(of: id)))
        }
        return .object(["scores": .object(scores)])
    }

    // MARK: End screen

    private var endScreen: some View {
        let state = boardState
        let mine = state.score(of: appState.memberId ?? "")
        let theirs = state.score(of: appState.partner?.id ?? "")
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: mine == theirs ? "heart.circle.fill" : "trophy.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(mine == theirs ? coupleTint.blend : Licht.lampengold)
                    .background(VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(endLine(mine: mine, theirs: theirs))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                finalScoreRow(state: state)
                Button {
                    startGame(pairs: pairCount)
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy || photos.count < Self.minPairs)
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func endLine(mine: Int, theirs: Int) -> String {
        if mine == theirs { return L10n.t("games.memory.tie") }
        if mine > theirs { return L10n.t("games.memory.win.you") }
        return L10n.t("games.memory.win.partner", ["name": appState.partnerName])
    }

    private func finalScoreRow(state: PhotoMemoryState) -> some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            endScoreColumn(member: appState.me, state: state)
            Text(":")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Nacht.tertiaer)
            endScoreColumn(member: appState.partner, state: state)
        }
    }

    private func endScoreColumn(member: Member?, state: PhotoMemoryState) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: member?.avatar, colorHex: member?.color, size: LayoutMetrics.s(46))
            Text("\(member.map { state.score(of: $0.id) } ?? 0)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(Papier.aufNacht)
            Text(member?.name ?? "–")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
    }
}
