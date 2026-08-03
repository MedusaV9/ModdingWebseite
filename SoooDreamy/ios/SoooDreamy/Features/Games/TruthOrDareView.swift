import SwiftUI

/// Truth or Dare — couple edition. Local pass-and-play on ONE phone
/// (works offline, no server session): you take turns, pick truth or dare,
/// flip the card, do the thing. Spice filter, skips (max 3 each) and a
/// shared streak counter keep it spicy.
struct TruthOrDareView: View {
    @Environment(AppState.self) private var appState

    private enum Stage {
        case setup, choosing, card
    }

    @State private var stage: Stage = .setup
    @State private var spice = 2
    @State private var currentPlayer = 0
    @State private var streak = 0
    @State private var skipsLeft = [3, 3]
    @State private var usedTruthIds: Set<Int> = []
    @State private var usedDareIds: Set<Int> = []
    @State private var card: TruthOrDareItem?
    @State private var flipped = false
    @State private var heartsVisible = false
    @State private var heartsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if heartsVisible {
                FloatingHeartsView(emojis: ["🔥", "💖", "✨", "😏"], count: 16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.truthordare.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if stage != .setup {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        restart()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(Theme.pink)
                    }
                }
            }
        }
        .onDisappear {
            heartsTask?.cancel()
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
                Text("🎭")
                    .font(.scaled(56))
                Text(L10n.t("games.card.truthordare.title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("games.tod.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                spicePicker
                Button {
                    start()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private var spicePicker: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.tod.spiceTitle"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
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
            Haptics.shared.tap()
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                Text(emoji)
                    .font(.scaled(26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("games.tod.spice\(level)"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.t("games.tod.spice\(level).sub"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.pink : Theme.textTertiary)
            }
            .padding(LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.pink.opacity(0.18) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.pink : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        currentPlayer = Int.random(in: 0...1)
        streak = 0
        skipsLeft = [3, 3]
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

    // MARK: Status header (streak + skips)

    private var statusHeader: some View {
        HStack {
            PillTag(text: "🔥 " + L10n.t("games.tod.streak", ["n": String(streak)]),
                    tint: streak > 0 ? Theme.gold : Theme.purple)
            Spacer()
            PillTag(text: L10n.t("games.tod.skipsLeft", ["n": String(skipsLeft[currentPlayer])]),
                    tint: Theme.indigo)
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
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(L10n.t("games.tod.pickPrompt"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: LayoutMetrics.s(12)) {
                        choiceButton(isDare: false)
                        choiceButton(isDare: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .glassCard(padding: 20)
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    private func choiceButton(isDare: Bool) -> some View {
        Button {
            draw(isDare: isDare)
        } label: {
            VStack(spacing: 8) {
                Text(isDare ? "💋" : "💬")
                    .font(.scaled(34))
                Text(L10n.t(isDare ? "games.tod.dare" : "games.tod.truth"))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(26))
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isDare ? darePinkGradient : truthBlueGradient)
            )
            .shadow(color: (isDare ? Theme.pink : Theme.indigo).opacity(0.45), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var truthBlueGradient: LinearGradient {
        LinearGradient(colors: [Theme.blue, Theme.purple],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var darePinkGradient: LinearGradient {
        LinearGradient(colors: [Theme.rose, Theme.pink],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
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
                }
            }
            .padding(LayoutMetrics.s(16))
        }
    }

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
        }
    }

    private var cardBack: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text("❔")
                .font(.scaled(60))
            Text(L10n.t("games.tod.pickPrompt"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(300))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Theme.bgBottom, Theme.indigo],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func cardFront(_ card: TruthOrDareItem) -> some View {
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
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(300))
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(card.isDare ? darePinkGradient : truthBlueGradient)
        )
        .shadow(color: (card.isDare ? Theme.pink : Theme.indigo).opacity(0.5), radius: 18, y: 8)
    }

    private var actionButtons: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Button {
                skip()
            } label: {
                Text(L10n.t("games.tod.skip"))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(skipsLeft[currentPlayer] <= 0)
            .opacity(skipsLeft[currentPlayer] <= 0 ? 0.4 : 1)
            Button {
                done()
            } label: {
                Text(L10n.t("games.tod.done"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Turn actions

    private func done() {
        streak += 1
        SoundEngine.shared.play(.chime)
        Haptics.shared.success()
        if streak > 0, streak % 5 == 0 {
            SoundEngine.shared.play(.tada)
            flashHearts()
        }
        nextTurn()
    }

    private func skip() {
        guard skipsLeft[currentPlayer] > 0 else { return }
        skipsLeft[currentPlayer] -= 1
        streak = 0
        SoundEngine.shared.play(.pop)
        Haptics.shared.warning()
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
