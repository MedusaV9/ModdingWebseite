import SwiftUI
import Combine

// MARK: - Spiele-Bilanz — recent couple games & winners 🏆

/// Pushed from the Play hub. Loads past sessions (`GET /api/games`),
/// shows a win/tie record card for the competitive quiz plus a list of
/// recent games: quiz rows carry the score and the winner, the cooperative
/// choice games (This or That / Would You Rather) show their match rate.
struct GamesRecordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    /// The ONE page the Bilanz reads — its section header names this
    /// window honestly („die letzten 30", Fix-Runde 3, Befund 8b).
    private static let seitenFenster = 30

    @State private var games: [GameSession] = []
    @State private var loading = true

    private var myName: String { appState.me?.name ?? L10n.t("common.you") }

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
        .navigationTitle(L10n.t("games.record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            // A game just finished — the scoreboard is stale.
            guard let event = note.object as? ServerEvent, event.type == .gameEnded else { return }
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && games.isEmpty {
            ProgressView()
                .tint(coupleTint.blend)
                .padding(.top, LayoutMetrics.s(120))
        } else if games.isEmpty {
            EmptyStateView(systemImage: "trophy.fill",
                           title: L10n.t("games.record.emptyTitle"),
                           subtitle: L10n.t("games.record.emptyBody"),
                           actionTitle: L10n.t("games.record.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               dismiss()
                           })
                .padding(.top, LayoutMetrics.s(80))
        } else {
            VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                recordCard
                SectionHeader(title: L10n.t("games.record.recent",
                                            ["n": "\(Self.seitenFenster)"]))
                gameList
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let api = appState.api else {
            loading = false
            return
        }
        // Pre-v1.6 servers 404 the list — the empty state stays up quietly.
        if let sessions = try? await api.games(limit: Self.seitenFenster) {
            games = sessions
                .filter { $0.state == "ended" && outcome(of: $0) != nil }
                .sorted { $0.createdAt > $1.createdAt }
        }
        loading = false
    }

    // MARK: Outcomes

    /// What a finished session amounted to on the scoreboard.
    private enum Outcome {
        /// Competitive quiz: my points vs. the partner's.
        case score(mine: Int, partner: Int)
        /// Cooperative choice games: how often the picks matched.
        case matches(n: Int, total: Int)
    }

    private func outcome(of game: GameSession) -> Outcome? {
        guard let kind = game.kind, let result = game.result else { return nil }
        switch kind {
        case .quiz, .emojiriddle, .connectfour, .photomemory, .quizduel,
             .battleship, .pictionary, .kniffel, .stadtlandfluss, .twotruths,
             .hangman, .bingo, .rps,
             // W8C board & duel games — all six store result.scores + winner.
             .dame, .reversi, .kaesekaestchen, .gomoku, .mancala, .memoryduo:
            // Competitive games store `result.scores` too; sessions
            // without one quietly stay off the record.
            guard let scores = result["scores"]?.objectValue else { return nil }
            let mine = appState.memberId.flatMap { scores[$0]?.intValue } ?? 0
            let partner = scores.first { $0.key != appState.memberId }?.value.intValue ?? 0
            return .score(mine: mine, partner: partner)
        case .thisorthat, .wouldyourather:
            guard let n = result["matches"]?.intValue,
                  let total = result["rounds"]?.intValue, total > 0 else { return nil }
            return .matches(n: n, total: total)
        case .truthordare, .questions36:
            return nil   // local pass-the-phone games never store results
        case .movieroulette, .dailyquests, .wordchain, .wordleduo, .story:
            return nil   // matching/quest/co-op sessions — no head-to-head score
        }
    }

    // MARK: Record card (competitive games only)

    private var record: (mine: Int, ties: Int, partner: Int) {
        var mine = 0, ties = 0, partner = 0
        for game in games {
            guard case .score(let m, let p)? = outcome(of: game) else { continue }
            if m > p { mine += 1 } else if p > m { partner += 1 } else { ties += 1 }
        }
        return (mine, ties, partner)
    }

    // Nacht & Licht: the couple's tally sheet is a night note on the
    // table — wins in paper-white ink, the leader line glowing ember.
    private var recordCard: some View {
        let record = record
        let total = record.mine + record.ties + record.partner
        return VStack(spacing: LayoutMetrics.s(10)) {
            HStack(alignment: .top, spacing: LayoutMetrics.s(12)) {
                recordColumn(name: myName,
                             avatar: appState.me?.avatar,
                             colorHex: appState.me?.color,
                             wins: record.mine,
                             ink: Papier.aufNacht)
                VStack(spacing: 4) {
                    Text("\(record.ties)")
                        .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                        .foregroundStyle(Nacht.sekundaer)
                        .padding(.top, LayoutMetrics.s(12))
                    Text(L10n.t("games.record.ties"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                recordColumn(name: appState.partnerName,
                             avatar: appState.partner?.avatar,
                             colorHex: appState.partner?.color,
                             wins: record.partner,
                             ink: Papier.aufNacht)
            }
            if total > 0 {
                Text(leaderLine(record))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.glut)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("games.record.subtitle", ["n": "\(total)"]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    private func recordColumn(name: String, avatar: String?, colorHex: String?,
                              wins: Int, ink: Color) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(40))
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            Text("\(wins)")
                .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
    }

    private func leaderLine(_ record: (mine: Int, ties: Int, partner: Int)) -> String {
        if record.mine > record.partner {
            return L10n.t("games.record.leaderMe")
        }
        if record.partner > record.mine {
            return L10n.t("games.record.leaderPartner", ["name": appState.partnerName])
        }
        return L10n.t("games.record.leaderTie")
    }

    // MARK: Game list

    private var gameList: some View {
        LazyVStack(spacing: LayoutMetrics.s(8)) {
            ForEach(games) { game in
                gameRow(game)
            }
        }
    }

    @ViewBuilder
    private func gameRow(_ game: GameSession) -> some View {
        if let kind = game.kind, let outcome = outcome(of: game) {
            HStack(spacing: LayoutMetrics.s(12)) {
                GameKindGlyph(kind: kind, size: 22, tint: coupleTint.blend)
                    .frame(width: LayoutMetrics.s(42), height: LayoutMetrics.s(42))
                    .background(Circle().fill(Papier.nachtInnenFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(PlayHubView.gameTitle(for: kind))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(prettyDate(game.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer(minLength: 0)
                outcomeView(outcome)
            }
            .nightCard(padding: .compact, grain: false)
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: Outcome) -> some View {
        switch outcome {
        case .score(let mine, let partner):
            HStack(spacing: LayoutMetrics.s(8)) {
                Text("\(mine) : \(partner)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(mine >= partner ? Licht.lampengold : Nacht.sekundaer)
                Image(systemName: mine > partner ? "trophy.fill" : (partner > mine ? "figure.strengthtraining.traditional" : "heart.circle.fill"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(mine > partner ? Licht.lampengold : coupleTint.blend)
                    .accessibilityHidden(true)
            }
        case .matches(let n, let total):
            HStack(spacing: LayoutMetrics.s(8)) {
                Text(L10n.t("games.record.matches", ["n": "\(n)", "total": "\(total)"]))
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Licht.lampengold)
                Image(systemName: total > 0 && n * 2 >= total ? "heart.circle.fill" : "hands.clap.fill")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
            }
        }
    }

    private func prettyDate(_ date: Date) -> String {
        AppFormatters.date(date, language: L10n.lang)
    }
}
