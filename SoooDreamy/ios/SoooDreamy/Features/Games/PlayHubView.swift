import SwiftUI
import Combine

// MARK: - Navigation destinations

enum GameDestination: String, Hashable, Identifiable {
    case wordle, quiz, thisorthat, wouldyourather, truthordare, questions36, dateideas
    var id: String { rawValue }
}

// MARK: - Play hub (the "Play" tab)

struct PlayHubView: View {
    @Environment(AppState.self) private var appState

    @State private var engine = GameEngine()
    @State private var path: [GameDestination] = []
    @State private var wordleDoneToday = false
    @State private var wordleDuelBadge: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        header
                        sessionBanner
                        wordleCard
                        gameGrid
                        dateIdeasCard
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GameDestination.self) { destination in
                gameView(for: destination)
            }
        }
        .task {
            engine.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            refreshWordleDone()
            await engine.resume(api: appState.api)
        }
        .onChange(of: path) { _, newPath in
            // Refresh the daily-card checkmark when coming back from the game.
            if newPath.isEmpty {
                refreshWordleDone()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            receive(event)
        }
        .onChange(of: appState.servers.activeProfileID) {
            // Switching servers switches the whole couple context.
            engine.adopt(nil)
            path = []
            Task { await engine.resume(api: appState.api) }
        }
    }

    // MARK: Event handling

    private func receive(_ event: ServerEvent) {
        if event.type == .wordleResult {
            if let response = event.decode(WordleDayResponse.self) {
                applyWordleDuel(response)
            }
            return
        }
        let previousId = engine.session?.id
        engine.handle(event)
        // Little chime when a fresh invitation from the partner lands.
        guard event.type == .gameCreated,
              let session = engine.session,
              session.id != previousId,
              session.state == "lobby",
              session.createdBy != appState.memberId else { return }
        SoundEngine.shared.play(.chime)
        Haptics.shared.tap()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t("games.title"))
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.rose, Theme.pink, Theme.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Spacer()
                Text("🎲")
                    .font(.system(size: 34))
            }
            Text(L10n.t("games.subtitle"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    // MARK: Session banner (invitation / waiting / continue)

    @ViewBuilder
    private var sessionBanner: some View {
        if let session = engine.session, session.state != "ended", let kind = session.kind {
            let destination = destination(for: kind)
            if session.state == "lobby" {
                if session.createdBy == appState.memberId {
                    waitingBanner(destination: destination)
                } else {
                    inviteBanner(kind: kind, destination: destination)
                }
            } else {
                continueBanner(kind: kind, destination: destination)
            }
        }
    }

    private func inviteBanner(kind: GameKind, destination: GameDestination) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("💌")
                    .font(.system(size: 34))
                Text(L10n.t("games.invite.body",
                            ["name": appState.partnerName, "game": Self.gameTitle(for: kind)]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button {
                joinAndOpen(destination)
            } label: {
                Text(L10n.t("games.invite.join"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(engine.busy)
        }
        .glassCard(padding: 16)
    }

    private func waitingBanner(destination: GameDestination) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.pink)
                Text(L10n.t("games.invite.waitingTitle"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            Text(waitingHint)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    path.append(destination)
                } label: {
                    Text(L10n.t("games.invite.open"))
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    Task { await engine.end(api: appState.api, result: nil) }
                } label: {
                    Text(L10n.t("games.invite.cancel"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(engine.busy)
            }
        }
        .glassCard(padding: 16)
    }

    private var waitingHint: String {
        if appState.partner?.online == true {
            return L10n.t("games.invite.waitingBody", ["name": appState.partnerName])
        }
        return L10n.t("games.invite.offline", ["name": appState.partnerName])
    }

    private func continueBanner(kind: GameKind, destination: GameDestination) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("🔥")
                    .font(.system(size: 30))
                Text(L10n.t("games.continue.body", ["game": Self.gameTitle(for: kind)]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button {
                path.append(destination)
            } label: {
                Text(L10n.t("games.continue.button"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .glassCard(padding: 16)
    }

    private func joinAndOpen(_ destination: GameDestination) {
        Task {
            if await engine.join(api: appState.api) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                path.append(destination)
            }
        }
    }

    // MARK: Daily Liebes-Wordle card

    private var wordleCard: some View {
        Button {
            path.append(.wordle)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Text("💘")
                        .font(.system(size: 40))
                    if wordleDoneToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Theme.mint)
                            .background(Circle().fill(Theme.bgTop).padding(1))
                            .offset(x: 4, y: 2)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.t("games.wordle.title"))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        PillTag(text: L10n.t("games.wordle.daily"), tint: Theme.gold)
                        if let badge = wordleDuelBadge {
                            Text(badge)
                                .font(.system(size: 13))
                        }
                    }
                    Text(L10n.t(wordleDoneToday ? "games.wordle.done" : "games.wordle.teaser"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: wordleDoneToday ? "checkmark.seal.fill" : "chevron.right")
                    .font(.system(size: wordleDoneToday ? 20 : 14, weight: .bold))
                    .foregroundStyle(wordleDoneToday ? Theme.mint : Theme.gold)
            }
            .glassCard(padding: 16)
        }
        .buttonStyle(.plain)
    }

    private func refreshWordleDone() {
        guard let couple = appState.couple else {
            wordleDoneToday = false
            wordleDuelBadge = nil
            return
        }
        wordleDoneToday = WordleDaily.isFinished(coupleId: couple.id,
                                                 dateKey: SharedDates.todayKey(),
                                                 lang: L10n.lang)
        refreshWordleDuel()
    }

    /// Cheap, non-blocking duel check for the badge — only fires once my
    /// own board is done (before that no duel outcome can exist anyway).
    private func refreshWordleDuel() {
        guard wordleDoneToday, let api = appState.api else {
            wordleDuelBadge = nil
            return
        }
        Task {
            guard let response = try? await api.wordleDay(dateKey: SharedDates.todayKey()) else { return }
            applyWordleDuel(response)
        }
    }

    private func applyWordleDuel(_ response: WordleDayResponse) {
        guard response.dateKey == SharedDates.todayKey() else { return }
        guard let mine = response.mine, let partner = response.partner else {
            wordleDuelBadge = nil
            return
        }
        // 🏆 when the duel has a winner, 💞 for ties and shared defeats.
        let decided = mine.win != partner.win || (mine.win && partner.win && mine.rows != partner.rows)
        wordleDuelBadge = decided ? "🏆" : "💞"
    }

    // MARK: Game grid

    private static let gridCards: [GameCardInfo] = [
        GameCardInfo(destination: .quiz, emoji: "🧠", tint: Theme.pink, multiplayer: true),
        GameCardInfo(destination: .thisorthat, emoji: "⚡️", tint: Theme.purple, multiplayer: true),
        GameCardInfo(destination: .wouldyourather, emoji: "🤯", tint: Theme.indigo, multiplayer: true),
        GameCardInfo(destination: .truthordare, emoji: "🎭", tint: Theme.rose, multiplayer: false),
        GameCardInfo(destination: .questions36, emoji: "💫", tint: Theme.blue, multiplayer: false)
    ]

    private var gameGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(Self.gridCards) { card in
                Button {
                    path.append(card.destination)
                } label: {
                    GameCardView(card: card)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateIdeasCard: some View {
        Button {
            path.append(.dateideas)
        } label: {
            HStack(spacing: 14) {
                Text("🎰")
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("games.card.dateideas.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.t("games.card.dateideas.teaser"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            .glassCard(padding: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Destination mapping

    @ViewBuilder
    private func gameView(for destination: GameDestination) -> some View {
        switch destination {
        case .wordle:
            WordleView()
        case .quiz:
            QuizGameView(engine: engine)
        case .thisorthat:
            ChoiceGamesView(engine: engine, kind: .thisorthat)
        case .wouldyourather:
            ChoiceGamesView(engine: engine, kind: .wouldyourather)
        case .truthordare:
            TruthOrDareView()
        case .questions36:
            Questions36View()
        case .dateideas:
            DateIdeasView()
        }
    }

    private func destination(for kind: GameKind) -> GameDestination {
        switch kind {
        case .quiz: return .quiz
        case .thisorthat: return .thisorthat
        case .wouldyourather: return .wouldyourather
        case .truthordare: return .truthordare
        case .questions36: return .questions36
        }
    }

    /// Localized display name of a game type.
    static func gameTitle(for kind: GameKind) -> String {
        L10n.t("games.card.\(kind.rawValue).title")
    }
}

// MARK: - Game card

private struct GameCardInfo: Identifiable {
    let destination: GameDestination
    let emoji: String
    let tint: Color
    let multiplayer: Bool

    var id: GameDestination { destination }
    var titleKey: String { "games.card.\(destination.rawValue).title" }
    var teaserKey: String { "games.card.\(destination.rawValue).teaser" }
}

private struct GameCardView: View {
    let card: GameCardInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(card.emoji)
                .font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(Circle().fill(card.tint.opacity(0.22)))
            Text(L10n.t(card.titleKey))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(L10n.t(card.teaserKey))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PillTag(text: L10n.t(card.multiplayer ? "games.badge.multiplayer" : "games.badge.local"),
                    tint: card.multiplayer ? Theme.pink : Theme.mint)
        }
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .topLeading)
        .glassCard(padding: 14)
    }
}

// MARK: - Shared multiplayer scaffolding

/// Empty state when the couple is not complete yet — the realtime games
/// need both partners.
struct GameNeedsPartnerView: View {
    var body: some View {
        EmptyStateView(emoji: "🫶",
                       title: L10n.t("games.needPartner.title"),
                       subtitle: L10n.t("games.needPartner.body"))
            .glassCard(padding: 8)
            .padding(16)
    }
}

/// Lobby state inside a game view: either "waiting for partner to join"
/// (I created the session) or a big join button (partner invited me).
struct GameLobbyView: View {
    @Environment(AppState.self) private var appState

    let engine: GameEngine
    let accent: Color

    var body: some View {
        VStack(spacing: 14) {
            if isMine {
                waitingContent
            } else {
                joinContent
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 22)
    }

    private var isMine: Bool {
        engine.session?.createdBy == appState.memberId
    }

    private var waitingContent: some View {
        VStack(spacing: 14) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: 64,
                            online: appState.partner?.online ?? false)
            Text(L10n.t("games.waitingFor", ["name": appState.partnerName]))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(waitingHint)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .tint(accent)
            Button {
                Task { await engine.end(api: appState.api, result: nil) }
            } label: {
                Text(L10n.t("games.invite.cancel"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy)
        }
    }

    private var waitingHint: String {
        if appState.partner?.online == true {
            return L10n.t("games.invite.waitingBody", ["name": appState.partnerName])
        }
        return L10n.t("games.invite.offline", ["name": appState.partnerName])
    }

    private var joinContent: some View {
        VStack(spacing: 14) {
            Text("💌")
                .font(.system(size: 52))
            Text(L10n.t("games.lobby.joinTitle", ["name": appState.partnerName]))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(L10n.t("games.lobby.joinBody"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    if await engine.join(api: appState.api) {
                        SoundEngine.shared.play(.pop)
                        Haptics.shared.success()
                    }
                }
            } label: {
                Text(L10n.t("games.invite.join"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(engine.busy)
        }
    }
}

/// Small caption shown while waiting for the partner's move; mentions when
/// the partner is offline so nobody stares at a frozen screen.
struct GameWaitingHint: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.pink)
                Text(L10n.t("games.waitingFor", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if appState.partner?.online != true {
                Text(L10n.t("games.partnerOffline", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Thin rounded progress bar used in the game headers.
struct GameProgressBar: View {
    let progress: Double
    var tint: Color = Theme.pink

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 7)
        .animation(.spring(response: 0.4), value: progress)
    }
}
