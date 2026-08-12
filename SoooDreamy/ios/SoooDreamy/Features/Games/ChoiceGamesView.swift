import SwiftUI
import Combine

/// Shared implementation for "This or That" AND "Would You Rather" —
/// both are 12 quick rounds where both partners pick option a or b at the
/// same time; every completed round reveals both picks (match animation!).
/// Would-You-Rather additionally shows the "Would you rather…" prefix and
/// a discuss prompt after each reveal.
///
/// Move protocol:
/// - `{"kind": "pick", "round": r, "value": "a" | "b"}` (both members)
struct ChoiceGamesView: View {
    @Environment(AppState.self) private var appState

    let engine: GameEngine
    let kind: GameKind          // .thisorthat or .wouldyourather

    /// Local view cursor: which round this client is looking at. Never
    /// runs ahead of the reducer (only advances past completed rounds).
    @State private var cursor = 0
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var heartsVisible = false
    @State private var endCelebrated = false
    @State private var heartsTask: Task<Void, Never>?
    @State private var sharing = false
    @State private var shared = false

    private static let defaultRounds = 12

    private enum RevealState: Equatable {
        case none, match, different
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if heartsVisible {
                FloatingHeartsView(emojis: ["💞", "💖", "✨", "💜"], count: 16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.\(kind.rawValue).title"))
        .navigationBarTitleDisplayMode(.inline)
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
            syncCursor()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
            syncCursor()
        }
        .onChange(of: revealState) { _, new in
            handleReveal(new)
        }
        .onDisappear {
            heartsTask?.cancel()
        }
    }

    // MARK: Derived state (pure reducer over payload + moves)

    private var session: GameSession? {
        guard let current = engine.session, current.kind == kind else { return nil }
        return current
    }

    private var isWouldYouRather: Bool { kind == .wouldyourather }

    private var totalRounds: Int {
        engine.payloadInt("rounds", default: Self.defaultRounds)
    }

    private var sortedMemberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var pairs: [ChoicePair] {
        let source = isWouldYouRather ? ContentPack.wouldYouRather : ContentPack.thisOrThat
        return Array(source.seededShuffled(seed: engine.seed).prefix(totalRounds))
    }

    /// memberId → "a"/"b" for one round (first pick per member wins).
    private func picks(round: Int) -> [String: String] {
        engine.movesByMember(round: round, kind: "pick")
            .compactMapValues { $0.data["value"]?.stringValue }
    }

    private func complete(round: Int) -> Bool {
        guard sortedMemberIds.count == 2 else { return false }
        let current = picks(round: round)
        return sortedMemberIds.allSatisfy { current[$0] != nil }
    }

    private var firstOpenRound: Int {
        guard session != nil else { return 0 }
        for round in 0..<totalRounds where !complete(round: round) {
            return round
        }
        return totalRounds
    }

    private var allComplete: Bool {
        session != nil && totalRounds > 0 && firstOpenRound >= totalRounds
    }

    private var matchCount: Int {
        guard sortedMemberIds.count == 2 else { return 0 }
        var count = 0
        for round in 0..<totalRounds {
            let current = picks(round: round)
            guard let first = current[sortedMemberIds[0]],
                  let second = current[sortedMemberIds[1]] else { continue }
            if first == second { count += 1 }
        }
        return count
    }

    private var revealState: RevealState {
        guard session?.state == "active" || session?.state == "ended",
              cursor < totalRounds,
              complete(round: cursor),
              sortedMemberIds.count == 2 else { return .none }
        let current = picks(round: cursor)
        let first = current[sortedMemberIds[0]]
        let second = current[sortedMemberIds[1]]
        return first == second ? .match : .different
    }

    private var showEndScreen: Bool {
        guard let session, allComplete else { return false }
        return cursor >= totalRounds || session.state == "ended"
    }

    private var myPickForCursor: String? {
        guard let myId = appState.memberId else { return nil }
        return picks(round: cursor)[myId]
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: accent)
                        .padding(LayoutMetrics.s(16))
                }
            } else if showEndScreen {
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

    private var accent: Color {
        isWouldYouRather ? Theme.indigo : Theme.purple
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(isWouldYouRather ? "🤯" : "⚡️")
                    .font(.scaled(56))
                Text(L10n.t("games.card.\(kind.rawValue).title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t(isWouldYouRather
                            ? "games.choice.howto.wouldyourather"
                            : "games.choice.howto.thisorthat"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
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
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            let payload = GameEngine.makePayload(options: ["rounds": Self.defaultRounds])
            if await engine.create(api: appState.api, type: kind, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        cursor = 0
        sending = false
        didSendEnd = false
        endCelebrated = false
        heartsVisible = false
        sharing = false
        shared = false
    }

    private func syncCursor() {
        cursor = firstOpenRound
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                playHeader
                GameProgressBar(progress: Double(min(cursor, totalRounds)) / Double(max(totalRounds, 1)),
                                tint: accent)
                roundCard
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    private var playHeader: some View {
        HStack {
            PillTag(text: L10n.t("games.round",
                                 ["n": String(min(cursor + 1, totalRounds)),
                                  "total": String(totalRounds)]),
                    tint: accent)
            Spacer()
            PillTag(text: "💞 " + L10n.t("games.choice.matches", ["n": String(matchCount)]),
                    tint: Theme.pink)
        }
    }

    @ViewBuilder
    private var roundCard: some View {
        if cursor < totalRounds, cursor < pairs.count {
            let pair = pairs[cursor]
            VStack(spacing: LayoutMetrics.s(14)) {
                if isWouldYouRather {
                    Text(L10n.t("games.wyr.prefix"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.gold)
                }
                optionCard(option: "a", text: pair.a.resolved(L10n.lang))
                Text(L10n.t("games.choice.or"))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textTertiary)
                optionCard(option: "b", text: pair.b.resolved(L10n.lang))
                footerForRound
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 16)
        }
    }

    @ViewBuilder
    private var footerForRound: some View {
        switch revealState {
        case .none:
            if myPickForCursor != nil {
                GameWaitingHint()
            }
        case .match, .different:
            revealFooter
        }
    }

    private var revealFooter: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(revealState == .match
                 ? L10n.t("games.choice.match")
                 : L10n.t("games.choice.noMatch"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(revealState == .match ? Theme.mint : Theme.gold)
            if isWouldYouRather {
                Text(L10n.t("games.wyr.discuss"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button {
                advance()
            } label: {
                Text(L10n.t("games.next"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 4)
    }

    private func optionCard(option: String, text: String) -> some View {
        let tint: Color = option == "a" ? Theme.purple : Theme.pink
        let myPick = myPickForCursor
        let isMine = myPick == option
        let revealed = revealState != .none
        return Button {
            pick(option)
        } label: {
            VStack(spacing: 8) {
                Text(text)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if revealed {
                    revealChips(option: option)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(18))
            .padding(.horizontal, LayoutMetrics.s(14))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(tint.opacity(isMine ? 0.34 : 0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isMine ? tint : Color.white.opacity(0.08), lineWidth: 1.5)
            )
            .scaleEffect(isMine ? 1.02 : 1)
            .animation(.spring(response: 0.3), value: isMine)
        }
        .buttonStyle(.plain)
        .disabled(myPick != nil || sending || revealed)
    }

    /// Avatar chips of everyone who picked this option (shown on reveal).
    @ViewBuilder
    private func revealChips(option: String) -> some View {
        let current = picks(round: cursor)
        let members = (appState.couple?.members ?? []).filter { current[$0.id] == option }
        if !members.isEmpty {
            HStack(spacing: 6) {
                ForEach(members) { member in
                    HStack(spacing: 4) {
                        EmojiAvatarView(emoji: member.avatar, colorHex: member.color, size: 22)
                        Text(member.id == appState.memberId
                             ? L10n.t("common.you")
                             : member.name)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.black.opacity(0.25)))
                }
            }
        }
    }

    // MARK: Actions

    private func pick(_ option: String) {
        guard myPickForCursor == nil, !sending, cursor < totalRounds else { return }
        sending = true
        Haptics.shared.tap()
        Task {
            let data = GameEngine.moveData(kind: "pick", round: cursor, value: option)
            _ = await engine.sendMove(api: appState.api, data: data)
            sending = false
        }
    }

    private func advance() {
        guard complete(round: cursor) else { return }
        withAnimation(.spring(response: 0.35)) {
            cursor += 1
        }
        if cursor >= totalRounds {
            maybeFinish()
        }
    }

    private func handleReveal(_ state: RevealState) {
        switch state {
        case .match:
            SoundEngine.shared.play(.sparkle)
            Haptics.shared.success()
            flashHearts()
        case .different:
            SoundEngine.shared.play(.pop)
            Haptics.shared.tap()
        case .none:
            break
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

    private func maybeFinish() {
        guard allComplete, let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            let result = JSONValue.object([
                "matches": .number(Double(matchCount)),
                "rounds": .number(Double(totalRounds))
            ])
            await engine.end(api: appState.api, result: result)
        }
    }

    // MARK: End screen

    private var matchPercent: Int {
        guard totalRounds > 0 else { return 0 }
        return Int((Double(matchCount) / Double(totalRounds) * 100).rounded())
    }

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(matchPercent >= 65 ? "💞" : "🎉")
                    .font(.scaled(60))
                Text(L10n.t("games.choice.end.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(matchPercent)%")
                    .font(.scaled(58, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.rose, Theme.pink, Theme.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                Text(L10n.t("games.choice.end.summary",
                            ["n": String(matchCount), "total": String(totalRounds)]))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(endFlavor)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                shareButton
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
        .onAppear {
            maybeFinish()
            celebrateEnd()
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
                        .tint(Theme.pink)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.pink)
            .disabled(sharing || shared)
        }
    }

    /// Posts the match result into the couple chat (Wordle/ToD pattern).
    private var shareText: String {
        let game = (isWouldYouRather ? "🤯 " : "⚡️ ") + L10n.t("games.card.\(kind.rawValue).title")
        let header = L10n.t("games.share.header", ["game": game])
        let summary = "\(matchPercent)% · " + L10n.t("games.choice.end.summary",
                                                     ["n": String(matchCount),
                                                      "total": String(totalRounds)])
        return header + "\n" + summary + "\n" + endFlavor
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

    private var endFlavor: String {
        if matchPercent >= 90 { return L10n.t("games.choice.end.soulmates") }
        if matchPercent >= 65 { return L10n.t("games.choice.end.great") }
        if matchPercent >= 40 { return L10n.t("games.choice.end.ok") }
        return L10n.t("games.choice.end.spicy")
    }

    private func celebrateEnd() {
        guard !endCelebrated else { return }
        endCelebrated = true
        SoundEngine.shared.play(.tada)
        Haptics.shared.success()
        flashHearts()
    }
}
