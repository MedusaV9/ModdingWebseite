import SwiftUI

// MARK: - Emoji-Rätsel 🧩 (local pass-and-play party game)
// Both partners look at the same screen, shout their guess, and whoever
// was first taps their own name to claim the point. Works solo-with-friends
// too: without a partner the second player is a generic "Team 2".

struct EmojiRiddleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private enum Stage {
        case setup, playing, finished
    }

    private static let categories = ["movie", "song", "place", "food", "couple", "activity"]
    private static let categoryEmoji: [String: String] = [
        "movie": "🎬", "song": "🎵", "place": "🌍",
        "food": "🍕", "couple": "💞", "activity": "🎯"
    ]
    private static let roundOptions = [10, 15, 20]

    @State private var stage = Stage.setup
    @State private var roundCount = 15
    @State private var selectedCategories = Set(EmojiRiddleView.categories)
    @State private var deck: [EmojiRiddle] = []
    @State private var cursor = 0
    @State private var scores = [0, 0]
    @State private var revealed = false
    @State private var lastWinner: Int?
    @State private var celebrate = false

    // MARK: Players (index 0 = me, 1 = partner or generic team 2)

    private var playerNames: [String] {
        [appState.me?.name ?? L10n.t("common.you"),
         appState.partner?.name ?? L10n.t("games.emoji.teamTwo")]
    }

    private var playerColors: [String?] {
        [appState.me?.color, appState.partner?.color]
    }

    private var playerAvatars: [String?] {
        [appState.me?.avatar, appState.partner?.avatar ?? "🎲"]
    }

    private var currentRiddle: EmojiRiddle? {
        deck.indices.contains(cursor) ? deck[cursor] : nil
    }

    // MARK: Body

    var body: some View {
        ZStack {
            DreamyBackground()
            switch stage {
            case .setup:
                setupScreen
            case .playing:
                playScreen
            case .finished:
                endScreen
            }
            if celebrate {
                FloatingHeartsView(emojis: ["🧩", "🎉", "💖", "✨", "🏆"])
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.emoji.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                explainerCard
                roundsCard
                categoriesCard
                Button(action: start) {
                    Text(L10n.t("games.emoji.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedCategories.isEmpty)
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    private var explainerCard: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Text("🧩")
                .font(.scaled(40))
            Text(L10n.t("games.emoji.howto"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .glassCard(padding: 16)
    }

    private var roundsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.emoji.rounds"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Self.roundOptions, id: \.self) { option in
                    roundChip(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func roundChip(_ option: Int) -> some View {
        let selected = roundCount == option
        return Button {
            roundCount = option
            Haptics.shared.tap()
        } label: {
            Text("\(option)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(selected ? Theme.bgTop : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LayoutMetrics.s(10))
                .background(
                    Capsule().fill(selected ? Theme.gold : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.emoji.categories"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8)],
                      spacing: 8) {
                ForEach(Self.categories, id: \.self) { category in
                    categoryChip(category)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 16)
    }

    private func categoryChip(_ category: String) -> some View {
        let selected = selectedCategories.contains(category)
        return Button {
            if selected {
                selectedCategories.remove(category)
            } else {
                selectedCategories.insert(category)
            }
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 4) {
                Text(Self.categoryEmoji[category] ?? "❓")
                    .font(.scaled(22))
                Text(L10n.t("games.emoji.cat.\(category)"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(10))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Theme.pink.opacity(0.25) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Theme.pink.opacity(0.7) : Color.white.opacity(0.1),
                                  lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        let pool = ContentPack.emojiRiddles.filter { selectedCategories.contains($0.category) }
        deck = Array(pool.seededShuffled(seed: Int.random(in: 0..<Int.max)).prefix(roundCount))
        cursor = 0
        scores = [0, 0]
        revealed = false
        lastWinner = nil
        stage = .playing
        SoundEngine.shared.play(.whoosh)
        Haptics.shared.tap()
    }

    // MARK: Playing

    private var playScreen: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            scoreHeader
            Spacer(minLength: 0)
            if let riddle = currentRiddle {
                riddleCard(riddle)
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(LayoutMetrics.s(16))
    }

    private var scoreHeader: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            scoreBadge(0)
            VStack(spacing: 5) {
                Text(L10n.t("games.emoji.round",
                            ["n": String(cursor + 1), "total": String(deck.count)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                GameProgressBar(progress: Double(cursor) / Double(max(deck.count, 1)),
                                tint: Theme.gold)
            }
            .frame(maxWidth: .infinity)
            scoreBadge(1)
        }
        .glassCard(padding: 12)
    }

    private func scoreBadge(_ index: Int) -> some View {
        HStack(spacing: 6) {
            EmojiAvatarView(emoji: playerAvatars[index],
                            colorHex: playerColors[index],
                            size: LayoutMetrics.s(30))
            Text("\(scores[index])")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: scores[index])
        }
    }

    // MARK: Riddle card (flip reveal)

    private func riddleCard(_ riddle: EmojiRiddle) -> some View {
        ZStack {
            riddleFront(riddle)
                .rotation3DEffect(.degrees(revealed ? 180 : 0),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                .opacity(revealed ? 0 : 1)
            riddleBack(riddle)
                .rotation3DEffect(.degrees(revealed ? 0 : -180),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                .opacity(revealed ? 1 : 0)
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.75), value: revealed)
        .id(cursor)
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func riddleFront(_ riddle: EmojiRiddle) -> some View {
        VStack(spacing: LayoutMetrics.s(16)) {
            categoryPill(riddle.category)
            Text(riddle.emojis)
                .font(.scaled(54))
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .minimumScaleFactor(0.6)
            Text(L10n.t("games.emoji.shout"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(240))
        .glassCard(padding: 20)
    }

    private func riddleBack(_ riddle: EmojiRiddle) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(riddle.emojis)
                .font(.scaled(26))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(riddle.answer.resolved(L10n.lang))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(revealLine)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(lastWinner == nil ? Theme.textSecondary : Theme.gold)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(240))
        .glassCard(padding: 20)
    }

    private var revealLine: String {
        if let winner = lastWinner {
            return L10n.t("games.emoji.gotIt", ["name": playerNames[winner]])
        }
        return L10n.t("games.emoji.noOneKnew")
    }

    private func categoryPill(_ category: String) -> some View {
        PillTag(text: (Self.categoryEmoji[category] ?? "") + " " + L10n.t("games.emoji.cat.\(category)"),
                tint: Theme.purple)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if revealed {
            Button(action: advance) {
                Text(L10n.t(cursor + 1 >= deck.count ? "games.emoji.results" : "games.emoji.next"))
            }
            .buttonStyle(PrimaryButtonStyle())
        } else {
            VStack(spacing: LayoutMetrics.s(10)) {
                HStack(spacing: LayoutMetrics.s(10)) {
                    pointButton(0)
                    pointButton(1)
                }
                nobodyButton
            }
        }
    }

    private func pointButton(_ index: Int) -> some View {
        let tint = Color(hex: playerColors[index] ?? "A855F7")
        return Button {
            award(index)
        } label: {
            HStack(spacing: 8) {
                EmojiAvatarView(emoji: playerAvatars[index],
                                colorHex: playerColors[index],
                                size: 26)
                Text(L10n.t("games.emoji.point", ["name": playerNames[index]]))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(tint.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(tint.opacity(0.8), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var nobodyButton: some View {
        Button {
            award(nil)
        } label: {
            Text(L10n.t("games.emoji.nobody"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LayoutMetrics.s(10))
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Round flow

    /// The tap first flips the card open (and awards the point), the
    /// "Weiter" button then advances to the next riddle.
    private func award(_ index: Int?) {
        guard !revealed else { return }
        lastWinner = index
        revealed = true
        if let index {
            scores[index] += 1
            Haptics.shared.success()
            SoundEngine.shared.play(.pop)
        } else {
            Haptics.shared.tap()
            SoundEngine.shared.play(.whoosh)
        }
    }

    private func advance() {
        if cursor + 1 >= deck.count {
            finishGame()
            return
        }
        withAnimation(.spring(response: 0.4)) {
            cursor += 1
            revealed = false
            lastWinner = nil
        }
        Haptics.shared.tap()
    }

    private func finishGame() {
        stage = .finished
        if scores[0] == scores[1] {
            SoundEngine.shared.play(.chime)
        } else {
            SoundEngine.shared.play(.tada)
        }
        Haptics.shared.success()
        celebrate = true
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                celebrate = false
            }
        }
    }

    // MARK: End screen

    private var isTie: Bool {
        scores[0] == scores[1]
    }

    private var winnerIndex: Int {
        scores[0] >= scores[1] ? 0 : 1
    }

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(18)) {
                Text(isTie ? "💞" : "🏆")
                    .font(.scaled(64))
                    .padding(.top, LayoutMetrics.s(24))
                Text(isTie
                     ? L10n.t("games.emoji.tie")
                     : L10n.t("games.emoji.winner", ["name": playerNames[winnerIndex]]))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                finalScoreCard
                Button(action: start) {
                    Text(L10n.t("games.emoji.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    dismiss()
                } label: {
                    Text(L10n.t("games.emoji.backToHub"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    private var finalScoreCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.emoji.finalScore"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: LayoutMetrics.s(20)) {
                finalScoreColumn(0)
                Text(":")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textTertiary)
                finalScoreColumn(1)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 18)
    }

    private func finalScoreColumn(_ index: Int) -> some View {
        VStack(spacing: 8) {
            EmojiAvatarView(emoji: playerAvatars[index],
                            colorHex: playerColors[index],
                            size: LayoutMetrics.s(48))
            Text(playerNames[index])
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text("\(scores[index])")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(!isTie && winnerIndex == index ? Theme.gold : Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
}
