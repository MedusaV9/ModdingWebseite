import SwiftUI
import Combine

/// Truth or Dare — couple edition. Local pass-and-play on ONE phone
/// (works offline, no server session): you take turns, pick truth or dare,
/// flip the card, do the thing. Spice filter, consequence-free passing and a
/// shared streak counter keep it spicy.
/// With a paired partner the setup also offers the LIVE two-phone mode
/// (TruthOrDareLiveView) played via the game-session relay.
struct TruthOrDareView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    private enum Stage {
        case setup, choosing, card
    }

    /// Last chosen spice level survives app restarts (defaults to Flirty).
    private static let spiceKey = "sooodreamy.tod.spice"

    private static var storedSpice: Int {
        let value = UserDefaults.standard.integer(forKey: spiceKey)
        return (1...3).contains(value) ? value : 2
    }

    @State private var stage: Stage = .setup
    @State private var spice = TruthOrDareView.storedSpice
    @State private var currentPlayer = 0
    @State private var streak = 0
    @State private var usedTruthIds: Set<Int> = []
    @State private var usedDareIds: Set<Int> = []
    @State private var card: TruthOrDareItem?
    @State private var flipped = false
    @State private var sharing = false
    @State private var heartsVisible = false
    @State private var heartsTask: Task<Void, Never>?
    /// The Karteikarte is a real object on the table — draggable, and it
    /// settles back when released (Reduce Motion: no bounce, direct).
    @State private var cardDrag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DreamyBackground()
            if isLive {
                TruthOrDareLiveView(engine: engine)
            } else {
                localContent
            }
        }
        .navigationTitle(L10n.t("games.card.truthordare.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar {
            if stage != .setup && !isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        restart()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(coupleTint.blend)
                    }
                }
            }
        }
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
        .onDisappear {
            heartsTask?.cancel()
        }
    }

    /// Live sessions take over the screen; ended sessions only keep it when
    /// they actually finished (their end screen) — a cancelled invitation
    /// falls back to the local pass-and-play mode.
    private var isLive: Bool {
        guard let session = engine.session, session.kind == .truthordare else { return false }
        if session.state == "ended" {
            return TruthOrDareLive.finished(engine: engine,
                                            memberIds: (appState.couple?.members.map(\.id) ?? []).sorted())
        }
        return true
    }

    private var localContent: some View {
        ZStack {
            content
            if heartsVisible {
                FloatingHeartsView(emojis: ["🔥", "💖", "✨", "😏"], count: 16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Players

    private var playerNames: [String] {
        let me = appState.me?.name ?? L10n.t("common.you")
        return [me, appState.partnerName]
    }

    private var currentName: String {
        playerNames[currentPlayer]
    }

    private var currentMember: Member? {
        currentPlayer == 0 ? appState.me : appState.partner
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .setup:
            setupScreen
        case .choosing:
            choosingScreen
        case .card:
            cardScreen
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "theatermasks.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.truthordare.title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("games.tod.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                spicePicker
                if appState.partner != nil {
                    Button {
                        startLive()
                    } label: {
                        Text(L10n.t("games.tod.playLive"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(engine.busy)
                    Button {
                        start()
                    } label: {
                        Text(L10n.t("games.tod.playLocal"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button {
                        start()
                    } label: {
                        Text(L10n.t("games.start"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    /// Creates a live two-phone session over the game relay; seed + spice +
    /// rounds in the payload let both clients derive the identical decks.
    private func startLive() {
        guard !engine.busy else { return }
        let options = ["rounds": TruthOrDareLive.defaultRounds, "spice": spice]
        Task {
            let payload = GameEngine.makePayload(options: options)
            if await engine.create(api: appState.api, type: .truthordare, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private var spicePicker: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.tod.spiceTitle"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            VStack(spacing: 8) {
                spiceRow(level: 1, emoji: "🍭")
                spiceRow(level: 2, emoji: "😏")
                spiceRow(level: 3, emoji: "🌶️")
            }
        }
    }

    private func spiceRow(level: Int, emoji: String) -> some View {
        let selected = spice == level
        return Button {
            spice = level
            UserDefaults.standard.set(level, forKey: Self.spiceKey)
            Haptics.shared.tap()
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                Text(emoji)
                    .font(.system(.title2, design: .rounded))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("games.tod.spice\(level)"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("games.tod.spice\(level).sub"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? coupleTint.blend : Nacht.tertiaer)
            }
            .padding(LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? coupleTint.blend.opacity(0.14) : Papier.nachtInnenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                  lineWidth: selected ? 1.5 : Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        currentPlayer = Int.random(in: 0...1)
        streak = 0
        usedTruthIds = []
        usedDareIds = []
        card = nil
        flipped = false
        stage = .choosing
        SoundEngine.shared.play(.pop)
        Haptics.shared.tap()
    }

    private func restart() {
        stage = .setup
        card = nil
        flipped = false
    }

    // MARK: Status header (streak + pass hint)

    private var statusHeader: some View {
        HStack {
            PillTag(text: "🔥 " + L10n.t("games.tod.streak", ["n": String(streak)]),
                    tint: streak > 0 ? Theme.gold : Theme.indigo)
            Spacer()
            // Consent rule: passing is always allowed and never punished —
            // no quota, no countdown (Eval FX-T follow-up).
            PillTag(text: L10n.t("games.tod.skipFree"), tint: Theme.indigo)
        }
    }

    // MARK: Choosing (whose turn + truth/dare buttons)

    private var choosingScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                statusHeader
                VStack(spacing: LayoutMetrics.s(14)) {
                    EmojiAvatarView(emoji: currentMember?.avatar,
                                    colorHex: currentMember?.color,
                                    size: LayoutMetrics.s(62))
                    Text(L10n.t("games.tod.turn", ["name": currentName]))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .multilineTextAlignment(.center)
                    Text(L10n.t("games.tod.pickPrompt"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                    HStack(spacing: LayoutMetrics.s(12)) {
                        choiceButton(isDare: false)
                        choiceButton(isDare: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .nightCard(padding: .hero)
            }
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    /// Truth pours the couple blend, Dare the wax red — two solid stamps
    /// on the night card. Each stamp carries its own type contrast (label
    /// on fill); against nachtkarton the fills read as material.
    private func choiceButton(isDare: Bool) -> some View {
        Button {
            draw(isDare: isDare)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: isDare ? "flame.fill" : "bubble.left.and.bubble.right.fill")
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .accessibilityHidden(true)
                Text(L10n.t(isDare ? "games.tod.dare" : "games.tod.truth"))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
            }
            .foregroundStyle(isDare ? Papier.brief : coupleTint.onBlend)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(26))
            .background(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(isDare ? Wachs.rot : coupleTint.blend)
            )
        }
        .buttonStyle(.plain)
    }

    private func draw(isDare: Bool) {
        let pool = ContentPack.truthOrDare.filter { $0.isDare == isDare && $0.spice <= spice }
        var used = isDare ? usedDareIds : usedTruthIds
        var available = pool.filter { !used.contains($0.id) }
        if available.isEmpty {
            used = []
            available = pool
            appState.showToast(L10n.t("games.tod.reshuffled"), style: .info)
        }
        guard let item = available.randomElement() else { return }
        used.insert(item.id)
        if isDare {
            usedDareIds = used
        } else {
            usedTruthIds = used
        }
        card = item
        flipped = false
        stage = .card
        SoundEngine.shared.play(.whoosh)
        Haptics.shared.tap()
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.spring(response: 0.65, dampingFraction: 0.75)) {
                flipped = true
            }
        }
    }

    // MARK: Card (big flip card + done/skip)

    private var cardScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                statusHeader
                Text(L10n.t("games.tod.turn", ["name": currentName]))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                flipCard
                if flipped {
                    actionButtons
                    shareButton
                }
            }
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    /// The drawn Karteikarte: arrives with the blättern page-turn, flips
    /// from its karton back to the letter-paper face, and is a DRAGGABLE
    /// object on the table — it follows the finger and settles back.
    @ViewBuilder
    private var flipCard: some View {
        if let card {
            ZStack {
                cardBack
                    .rotation3DEffect(.degrees(flipped ? 180 : 0),
                                      axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .opacity(flipped ? 0 : 1)
                cardFront(card)
                    .rotation3DEffect(.degrees(flipped ? 0 : -180),
                                      axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                    .opacity(flipped ? 1 : 0)
            }
            .offset(cardDrag)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        cardDrag = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                            cardDrag = .zero
                        }
                    }
            )
            .paperBlaettern()
            .id(card.id)
        }
    }

    private var cardBack: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Tinte.sekundaer)
                .accessibilityHidden(true)
            Text(L10n.t("games.tod.pickPrompt"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(300))
        .paperCard(.karton, grain: false)
    }

    private func cardFront(_ card: TruthOrDareItem) -> some View {
        VStack(spacing: LayoutMetrics.s(16)) {
            HStack {
                PaperTag(text: L10n.t(card.isDare ? "games.tod.dare" : "games.tod.truth"),
                         ink: card.isDare ? Wachs.rot : coupleTint.tinte)
                Spacer()
                Text(String(repeating: "🌶️", count: card.spice))
                    .font(.system(.footnote, design: .rounded))
            }
            Spacer()
            Text(card.text.resolved(L10n.lang))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(300))
        .paperCard()
    }

    private var actionButtons: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Button {
                skip()
            } label: {
                Text(L10n.t("games.tod.skip"))
            }
            .buttonStyle(SecondaryButtonStyle())
            Button {
                done()
            } label: {
                Text(L10n.t("games.tod.done"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if appState.api != nil {
            Button {
                shareToChat()
            } label: {
                if sharing {
                    ProgressView()
                        .tint(coupleTint.blend)
                } else {
                    Label(L10n.t("games.shareToChat"), systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(coupleTint.blend)
            .disabled(sharing)
        }
    }

    /// Posts the current card into the couple chat ("💋 Dare for Mia: …").
    private func shareToChat() {
        guard let api = appState.api, let card, !sharing else { return }
        sharing = true
        Haptics.shared.tap()
        let header = L10n.t(card.isDare ? "games.tod.shareDare" : "games.tod.shareTruth",
                            ["name": currentName])
        let text = header + "\n" + card.text.resolved(L10n.lang)
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharing = false
        }
    }

    // MARK: Turn actions

    private func done() {
        streak += 1
        SoundEngine.shared.play(.chime)
        Haptics.shared.success()
        if streak > 0, streak % 5 == 0 {
            // A landed streak is a round-tier lift, not a match ceremony.
            GameEndCelebration.roundWon()
            flashHearts()
        }
        nextTurn()
    }

    private func skip() {
        // Consent rule: passing is always okay — it neither resets the shared
        // streak nor triggers warning feedback. Only "done" chains count up.
        SoundEngine.shared.play(.pop)
        Haptics.shared.tap()
        nextTurn()
    }

    private func nextTurn() {
        withAnimation(.spring(response: 0.4)) {
            currentPlayer = (currentPlayer + 1) % 2
            card = nil
            flipped = false
            stage = .choosing
        }
    }

    private func flashHearts() {
        heartsVisible = true
        heartsTask?.cancel()
        heartsTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled {
                heartsVisible = false
            }
        }
    }
}
