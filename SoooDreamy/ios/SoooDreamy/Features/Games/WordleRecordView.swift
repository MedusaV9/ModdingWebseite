import SwiftUI

// MARK: - Duell-Bilanz — the couple's running Wordle duel record 📊

/// Pushed from `WordleView`. Loads the duel history (per-member views, newest
/// first, anti-spoiler already applied server-side) and shows a W·U·N record
/// card, an optional play-streak chip and an expandable day-by-day list.
struct WordleRecordView: View {
    @Environment(AppState.self) private var appState

    @State private var days: [WordleDayResponse] = []
    @State private var loading = true
    @State private var expandedKeys: Set<String> = []

    private var lang: String { L10n.lang }

    private var myName: String { appState.me?.name ?? L10n.t("common.you") }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                content
                    .padding(16)
                    .padding(.bottom, 12)
            }
            .refreshable { await load() }
        }
        .navigationTitle(L10n.t("games.wordle.record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && days.isEmpty {
            ProgressView()
                .tint(Theme.pink)
                .padding(.top, 120)
        } else if days.isEmpty {
            EmptyStateView(emoji: "🥊",
                           title: L10n.t("games.wordle.record.emptyTitle"),
                           subtitle: L10n.t("games.wordle.record.emptyBody"))
                .padding(.top, 80)
        } else {
            VStack(spacing: 14) {
                recordCard
                if playStreak >= 2 {
                    PillTag(text: L10n.t("games.wordle.record.streak",
                                         ["n": "\(playStreak)"]),
                            tint: Theme.gold)
                }
                dayList
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let api = appState.api else {
            loading = false
            return
        }
        let requestedLang = lang
        if let response = try? await api.wordleHistory(limit: 30, lang: requestedLang) {
            days = response
                .filter { ($0.lang ?? requestedLang) == requestedLang }
                .sorted { $0.dateKey > $1.dateKey }
        }
        loading = false
    }

    // MARK: Record (only days where BOTH results are visible count)

    private var record: (mine: Int, ties: Int, partner: Int) {
        var mine = 0, ties = 0, partner = 0
        for day in days {
            guard let myResult = day.mine, let partnerResult = day.partner else { continue }
            switch WordleDaily.duelOutcome(mine: myResult, partner: partnerResult) {
            case .meWin: mine += 1
            case .partnerWin: partner += 1
            case .tie: ties += 1
            }
        }
        return (mine, ties, partner)
    }

    private var recordCard: some View {
        let record = record
        let total = record.mine + record.ties + record.partner
        return VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                recordColumn(name: myName,
                             avatar: appState.me?.avatar,
                             colorHex: appState.me?.color,
                             wins: record.mine)
                VStack(spacing: 4) {
                    Text("\(record.ties)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 12)
                    Text(L10n.t("games.wordle.record.ties"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                recordColumn(name: appState.partnerName,
                             avatar: appState.partner?.avatar,
                             colorHex: appState.partner?.color,
                             wins: record.partner)
            }
            if total > 0 {
                Text(leaderLine(record))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("games.wordle.record.subtitle", ["n": "\(total)"]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 16)
    }

    private func recordColumn(name: String, avatar: String?, colorHex: String?,
                              wins: Int) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: 40)
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Text("\(wins)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }

    private func leaderLine(_ record: (mine: Int, ties: Int, partner: Int)) -> String {
        if record.mine > record.partner {
            return L10n.t("games.wordle.record.leaderMe")
        }
        if record.partner > record.mine {
            return L10n.t("games.wordle.record.leaderPartner",
                          ["name": appState.partnerName])
        }
        return L10n.t("games.wordle.record.leaderTie")
    }

    // MARK: Streak (consecutive calendar days from the newest where I finished)

    private var playStreak: Int {
        let calendar = SharedDates.calendar
        let played = Set(days.filter { $0.mine != nil }.map { $0.dateKey })
        var expected = calendar.startOfDay(for: Date())
        // The streak is still alive when today isn't played yet but
        // yesterday is — start walking from yesterday in that case.
        if !played.contains(SharedDates.todayKey(expected)),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: expected) {
            expected = yesterday
        }
        var streak = 0
        while played.contains(SharedDates.todayKey(expected)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: expected) else {
                break
            }
            expected = previous
        }
        return streak
    }

    // MARK: Day list

    private var dayList: some View {
        LazyVStack(spacing: 10) {
            ForEach(days, id: \.dateKey) { day in
                dayRow(day)
            }
        }
    }

    private func dayRow(_ day: WordleDayResponse) -> some View {
        let expandable = day.mine != nil && day.partner != nil
        return VStack(spacing: 12) {
            Button {
                toggle(day.dateKey)
            } label: {
                dayHeader(day, expandable: expandable)
            }
            .buttonStyle(.plain)
            .disabled(!expandable)
            if expandedKeys.contains(day.dateKey),
               let mine = day.mine, let partner = day.partner {
                expandedGrids(mine: mine, partner: partner)
            }
        }
        .glassCard(padding: 12)
    }

    private func dayHeader(_ day: WordleDayResponse, expandable: Bool) -> some View {
        HStack(spacing: 10) {
            Text(prettyDate(day.dateKey))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            scoreText(day.mine)
            Text(":")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            scoreText(day.partner)
            Text(outcomeIcon(day))
                .font(.system(size: 16))
                .frame(width: 24)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
                .rotationEffect(.degrees(expandedKeys.contains(day.dateKey) ? 180 : 0))
                .opacity(expandable ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    private func scoreText(_ result: WordleResult?) -> some View {
        let text: String
        let color: Color
        if let result {
            text = result.win ? "\(result.rows)/6" : "✗"
            color = result.win ? Theme.mint : Theme.textTertiary
        } else {
            text = "—"
            color = Theme.textTertiary
        }
        return Text(text)
            .font(.system(.footnote, design: .rounded).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 34)
    }

    /// 🏆 I won · 💪 partner won · 💞 tie · 👀 partner played but stays
    /// hidden because I didn't — blank when only my result exists.
    private func outcomeIcon(_ day: WordleDayResponse) -> String {
        if let mine = day.mine, let partner = day.partner {
            switch WordleDaily.duelOutcome(mine: mine, partner: partner) {
            case .meWin: return "🏆"
            case .partnerWin: return "💪"
            case .tie: return "💞"
            }
        }
        if day.mine == nil && day.partnerFinished { return "👀" }
        return " "
    }

    private func expandedGrids(mine: WordleResult, partner: WordleResult) -> some View {
        HStack(alignment: .top, spacing: 14) {
            gridColumn(name: myName, result: mine)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
            gridColumn(name: appState.partnerName, result: partner)
        }
    }

    private func gridColumn(name: String, result: WordleResult) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            VStack(spacing: 2) {
                ForEach(Array(result.grid.split(separator: "\n").enumerated()),
                        id: \.offset) { _, line in
                    Text(String(line))
                        .font(.system(size: 13))
                        .kerning(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ dateKey: String) {
        Haptics.shared.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if expandedKeys.contains(dateKey) {
                expandedKeys.remove(dateKey)
            } else {
                expandedKeys.insert(dateKey)
            }
        }
    }

    private func prettyDate(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
