import SwiftUI
import Combine

// MARK: - Emoji-Rätsel 🧩 (local pass-and-play party game + live mode)
// Both partners look at the same screen, shout their guess, and whoever
// was first taps their own name to claim the point. Works solo-with-friends
// too: without a partner the second player is a generic "Team 2".
// With a paired partner the setup also offers the LIVE two-phone mode
// (EmojiRiddleLiveView) played via the game-session relay.

struct EmojiRiddleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine

    private enum Stage {
        case setup, playing, finished
    }

    private static let categories = EmojiRiddleLive.categories
    private static let categoryEmoji: [String: String] = [
        "movie": "🎬", "song": "🎵", "place": "🌍",
        "food": "🍕", "couple": "💞", "activity": "🎯"
    ]
    private static let roundOptions = [10, 15, 20]

    @State private var stage = Stage.setup
    @State private var roundCount = 15
    @State private var selectedCategories = Set(EmojiRiddleLive.categories)
    @State private var deck: [EmojiRiddle] = []
    @State private var cursor = 0
    @State private var scores = [0, 0]
    @State private var revealed = false
    @State private var lastWinner: Int?
    @State private var celebrate = false
    @State private var sharing = false
    @State private var shared = false

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
            if isLive {
                EmojiRiddleLiveView(engine: engine)
            } else {
                localContent
            }
        }
        .navigationTitle(L10n.t("games.emoji.title"))
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
    }

    /// Live sessions take over the screen; ended sessions only keep it when
    /// they actually finished (their end screen) — a cancelled invitation
    /// falls back to the local pass-and-play mode.
    private var isLive: Bool {
        guard let session = engine.session, session.kind == .emojiriddle else { return false }
        if session.state == "ended" {
            return EmojiRiddleLive.finished(engine: engine,
                                            memberIds: (appState.couple?.members.map(\.id) ?? []).sorted())
        }
        return true
    }

    private var localContent: some View {
        ZStack {
            switch stage {
            case .setup:
                setupScreen
            case .playing:
                playScreen
            case .finished:
                endScreen
            }
            if celebrate && !reduceMotion {
                FloatingHeartsView(emojis: ["🧩", "🎉", "💖", "✨", "🏆"])
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                explainerCard
                roundsCard
                categoriesCard
                if appState.partner != nil {
                    Button(action: startLive) {
                        Text(L10n.t("games.emoji.playLive"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedCategories.isEmpty || engine.busy)
                    Button(action: start) {
                        Text(L10n.t("games.emoji.playLocal"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(selectedCategories.isEmpty)
                } else {
                    Button(action: start) {
                        Text(L10n.t("games.emoji.start"))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedCategories.isEmpty)
                }
            }
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    /// Creates a live two-phone session over the game relay; the seed +
    /// options in the payload let both clients derive the identical deck.
    private func startLive() {
        guard !engine.busy else { return }
        let options = ["rounds": roundCount,
                       "cats": EmojiRiddleLive.categoryMask(for: selectedCategories)]
        Task {
            let payload = GameEngine.makePayload(options: options)
            if await engine.create(api: appState.api, type: .emojiriddle, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private var explainerCard: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("games.emoji.howto"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .nightCard(grain: false)
    }

    private var roundsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.emoji.rounds"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Self.roundOptions, id: \.self) { option in
                    roundChip(option)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private func roundChip(_ option: Int) -> some View {
        let selected = roundCount == option
        return Button {
            roundCount = option
            Haptics.shared.tap()
        } label: {
            Text("\(option)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(selected ? coupleTint.onBlend : Papier.aufNacht)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LayoutMetrics.s(10))
                .background(
                    Capsule().fill(selected ? coupleTint.blend : Papier.nachtInnenFill)
                )
                .overlay(
                    Capsule().strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private var categoriesCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("games.emoji.categories"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
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
        .nightCard()
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
                    .font(.system(.title3, design: .rounded))
                Text(L10n.t("games.emoji.cat.\(category)"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? Papier.aufNacht : Nacht.tertiaer)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(10))
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? coupleTint.blend.opacity(0.16) : Papier.nachtInnenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                  lineWidth: selected ? 1.5 : Theme.hairlineWidth)
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
        sharing = false
        shared = false
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
        .gameActGated()
        .padding(LayoutMetrics.s(16))
    }

    private var scoreHeader: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            scoreBadge(0)
            VStack(spacing: 5) {
                Text(L10n.t("games.emoji.round",
                            ["n": String(cursor + 1), "total": String(deck.count)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                GameProgressBar(progress: Double(cursor) / Double(max(deck.count, 1)),
                                tint: coupleTint.blend,
                                track: Papier.nachtInnenFill)
            }
            .frame(maxWidth: .infinity)
            scoreBadge(1)
        }
        .nightCard(grain: false)
    }

    private func scoreBadge(_ index: Int) -> some View {
        HStack(spacing: 6) {
            EmojiAvatarView(emoji: playerAvatars[index],
                            colorHex: playerColors[index],
                            size: LayoutMetrics.s(30))
            Text("\(scores[index])")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Papier.aufNacht)
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
        // Reduce Motion: the answer appears in place — no 3D flip, no slide.
        .animation(reduceMotion ? nil : Theme.Motion.arrive, value: revealed)
        .id(cursor)
        .transition(reduceMotion
                    ? .opacity
                    : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                  removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func riddleFront(_ riddle: EmojiRiddle) -> some View {
        VStack(spacing: LayoutMetrics.s(16)) {
            categoryPill(riddle.category)
            Text(riddle.emojis)
                .font(.system(.largeTitle, design: .rounded))
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .minimumScaleFactor(0.6)
            Text(L10n.t("games.emoji.shout"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.tertiaer)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(240))
        .paperCard(padding: .hero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.emoji.cat.\(riddle.category)") + ". "
                            + L10n.t("games.emoji.a11y.riddle", ["emojis": riddle.emojis]))
        .accessibilityValue(L10n.t("games.emoji.shout"))
    }

    private func riddleBack(_ riddle: EmojiRiddle) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(riddle.emojis)
                .font(.system(.title2, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(riddle.answer.resolved(L10n.lang))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(revealLine)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(lastWinner == nil ? Tinte.sekundaer : coupleTint.tinte)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(240))
        .paperCard(padding: .hero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.emoji.a11y.answer",
                                   ["answer": riddle.answer.resolved(L10n.lang)]))
        .accessibilityValue(revealLine)
    }

    private var revealLine: String {
        if let winner = lastWinner {
            return L10n.t("games.emoji.gotIt", ["name": playerNames[winner]])
        }
        return L10n.t("games.emoji.noOneKnew")
    }

    private func categoryPill(_ category: String) -> some View {
        PaperTag(text: (Self.categoryEmoji[category] ?? "") + " " + L10n.t("games.emoji.cat.\(category)"),
                 ink: Tinte.sekundaer)
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
                        .fill(Papier.nachtInnenFill)
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
        if let riddle = currentRiddle {
            GamesA11y.announce(L10n.t("games.emoji.a11y.answer",
                                      ["answer": riddle.answer.resolved(L10n.lang)])
                               + ". " + revealLine)
        }
    }

    private func advance() {
        if cursor + 1 >= deck.count {
            finishGame()
            return
        }
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            cursor += 1
            revealed = false
            lastWinner = nil
        }
        Haptics.shared.tap()
    }

    private func finishGame() {
        stage = .finished
        // Pass-around duel on ONE device: the winner is in the room, both
        // hands feel the (budget-tiered) victory motif together.
        if scores[0] == scores[1] {
            GameEndCelebration.tie(visual: .localHearts)
        } else {
            GameEndCelebration.win(visual: .localHearts)
        }
        GamesA11y.announce(isTie
            ? L10n.t("games.emoji.tie")
            : L10n.t("games.emoji.winner", ["name": playerNames[winnerIndex]]))
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
                Image(systemName: isTie ? "heart.circle.fill" : "trophy.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isTie ? coupleTint.blend : Licht.lampengold)
                    .background(VerdictLampenschein())
                    .padding(.top, LayoutMetrics.s(24))
                Text(isTie
                     ? L10n.t("games.emoji.tie")
                     : L10n.t("games.emoji.winner", ["name": playerNames[winnerIndex]]))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                finalScoreCard
                shareButton
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
            .contentColumn(.reading)
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
                        .tint(coupleTint.blend)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(coupleTint.blend)
            .disabled(sharing || shared)
        }
    }

    /// Posts the final score into the couple chat (Wordle/ToD pattern).
    private var shareText: String {
        let header = L10n.t("games.share.header",
                            ["game": "🧩 " + L10n.t("games.emoji.title")])
        let scoreLine = "\(playerNames[0]) \(scores[0]) : \(scores[1]) \(playerNames[1])"
        let verdict = isTie
            ? L10n.t("games.emoji.tie")
            : L10n.t("games.emoji.winner", ["name": playerNames[winnerIndex]])
        return header + "\n" + scoreLine + "\n" + verdict
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

    private var finalScoreCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Text(L10n.t("games.emoji.finalScore"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            HStack(spacing: LayoutMetrics.s(20)) {
                finalScoreColumn(0)
                Text(":")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Nacht.tertiaer)
                finalScoreColumn(1)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    private func finalScoreColumn(_ index: Int) -> some View {
        VStack(spacing: 8) {
            EmojiAvatarView(emoji: playerAvatars[index],
                            colorHex: playerColors[index],
                            size: LayoutMetrics.s(48))
            Text(playerNames[index])
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            Text("\(scores[index])")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(!isTie && winnerIndex == index
                                 ? Licht.lampengold : Papier.aufNacht)
        }
        .frame(maxWidth: .infinity)
    }
}
