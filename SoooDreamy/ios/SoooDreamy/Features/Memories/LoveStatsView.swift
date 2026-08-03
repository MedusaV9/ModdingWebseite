import SwiftUI

/// Love statistics dashboard — hero tiles, sent-vs-received touch bars & mood timeline.
struct LoveStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var barsAppeared = false
    @State private var moods: [MoodEntry] = []

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private struct MoodDay: Identifiable {
        let id: String
        let date: Date
        let entries: [MoodEntry]
    }

    private struct MoodCount: Identifiable {
        let mood: String
        let count: Int
        var id: String { mood }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("memories.stats.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.refreshStats()
            await loadMoods()
            withAnimation(.spring(response: 0.8).delay(0.15)) {
                barsAppeared = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let stats = appState.stats {
            statsScroll(stats)
        } else {
            LoadingView()
        }
    }

    private func statsScroll(_ stats: Stats) -> some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                heroTiles(stats)
                touchComparisonCard(stats)
                moodTimelineCard
                caption(stats)
            }
            .padding(LayoutMetrics.s(16))
            .padding(.bottom, LayoutMetrics.s(12))
        }
        .refreshable {
            await appState.refreshStats()
            await loadMoods()
        }
    }

    // MARK: Hero tiles

    private func heroTiles(_ stats: Stats) -> some View {
        LazyVGrid(columns: columns, spacing: LayoutMetrics.s(12)) {
            StatTile(emoji: "💞",
                     value: String(stats.daysTogether ?? appState.daysTogether ?? 0),
                     label: L10n.t("memories.stats.daysTogether"),
                     tint: Theme.pink)
            StatTile(emoji: "🔥",
                     value: String(stats.dailyStreak),
                     label: L10n.t("memories.stats.streak"),
                     tint: Theme.gold)
            StatTile(emoji: "💬",
                     value: String(stats.messages),
                     label: L10n.t("memories.stats.messages"),
                     tint: Theme.blue)
            StatTile(emoji: "📸",
                     value: String(stats.photos),
                     label: L10n.t("memories.stats.photos"),
                     tint: Theme.purple)
            StatTile(emoji: "🎮",
                     value: String(stats.gamesPlayed),
                     label: L10n.t("memories.stats.games"),
                     tint: Theme.indigo)
            StatTile(emoji: "🌌",
                     value: "\(stats.bucketDone)/\(stats.bucketTotal)",
                     label: L10n.t("memories.stats.bucket"),
                     tint: Theme.mint)
        }
    }

    // MARK: Touch comparison

    private func touchComparisonCard(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("memories.stats.touchTitle"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("memories.stats.touchSubtitle"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(TouchKind.allCases) { kind in
                touchRow(kind, stats: stats)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func touchRow(_ kind: TouchKind, stats: Stats) -> some View {
        let sent = stats.touchesSent.byType[kind.rawValue] ?? 0
        let received = stats.touchesReceived.byType[kind.rawValue] ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(kind.emoji)
                Text(L10n.t(kind.titleKey))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            bar(count: sent, maxCount: maxTouchCount(stats),
                tint: myColor, label: L10n.t("common.you"))
            bar(count: received, maxCount: maxTouchCount(stats),
                tint: partnerColor, label: appState.partnerName)
        }
        .padding(.top, 2)
    }

    private func bar(count: Int, maxCount: Int, tint: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth(total: geo.size.width, count: count, maxCount: maxCount))
                        .animation(.spring(response: 0.8), value: barsAppeared)
                }
            }
            .frame(height: 12)
            Text(String(count))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func barWidth(total: CGFloat, count: Int, maxCount: Int) -> CGFloat {
        guard barsAppeared, maxCount > 0, count > 0 else { return 0 }
        return max(8, total * CGFloat(count) / CGFloat(maxCount))
    }

    private func maxTouchCount(_ stats: Stats) -> Int {
        let sentMax = stats.touchesSent.byType.values.max() ?? 0
        let receivedMax = stats.touchesReceived.byType.values.max() ?? 0
        return max(sentMax, receivedMax)
    }

    private var myColor: Color {
        Color(hex: appState.me?.color ?? "FF5C8A")
    }

    private var partnerColor: Color {
        Color(hex: appState.partner?.color ?? "A855F7")
    }

    // MARK: Mood timeline

    private func loadMoods() async {
        guard let api = appState.api else { return }
        if let list = try? await api.moods() {
            moods = list
        }
    }

    /// Moods grouped by calendar day, newest day (and newest entry) first.
    private var moodDays: [MoodDay] {
        let calendar = SharedDates.calendar
        let grouped = Dictionary(grouping: moods) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            MoodDay(id: SharedDates.todayKey(day),
                    date: day,
                    entries: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    /// The 3 most frequent moods across BOTH members in the last 30 days —
    /// hidden while there are fewer than 3 entries to aggregate.
    private var topMoods: [MoodCount] {
        let calendar = SharedDates.calendar
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) else { return [] }
        let recent = moods.filter { $0.createdAt >= cutoff }
        guard recent.count >= 3 else { return [] }
        let counts = Dictionary(grouping: recent) { $0.mood }.mapValues { $0.count }
        return counts
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .prefix(3)
            .map { MoodCount(mood: $0.key, count: $0.value) }
    }

    @ViewBuilder
    private var topMoodsRow: some View {
        let top = topMoods
        if !top.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("memories.stats.topMoods"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 8) {
                    ForEach(top) { item in
                        moodChip(item)
                    }
                    Spacer()
                }
            }
        }
    }

    private func moodChip(_ item: MoodCount) -> some View {
        HStack(spacing: 5) {
            Text(item.mood)
                .font(.scaled(18))
            Text(L10n.t("memories.stats.topMoodCount", ["n": String(item.count)]))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, LayoutMetrics.s(10))
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private var moodTimelineCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            Text(L10n.t("memories.stats.moodTitle"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            topMoodsRow
            if moods.isEmpty {
                Text(L10n.t("memories.stats.moodEmpty"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(moodDays) { day in
                    moodDaySection(day)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func moodDaySection(_ day: MoodDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prettyDay(day.date))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            ForEach(day.entries) { entry in
                moodRow(entry)
            }
        }
    }

    private func moodRow(_ entry: MoodEntry) -> some View {
        let author = member(of: entry)
        return HStack(spacing: LayoutMetrics.s(10)) {
            EmojiAvatarView(emoji: author?.avatar, colorHex: author?.color, size: LayoutMetrics.s(34))
            Text(entry.mood)
                .font(.scaled(26))
            VStack(alignment: .leading, spacing: 1) {
                if let note = entry.moodNote, !note.isEmpty {
                    Text(note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: author?.color ?? "A855F7").opacity(0.10))
        )
    }

    private func member(of entry: MoodEntry) -> Member? {
        appState.couple?.members.first { $0.id == entry.memberId }
    }

    private func prettyDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    // MARK: Caption

    @ViewBuilder
    private func caption(_ stats: Stats) -> some View {
        let total = stats.touchesSent.total + stats.touchesReceived.total
        if total > 0 {
            Text(L10n.t("memories.stats.caption", ["n": String(total)]))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        } else {
            Text(L10n.t("memories.stats.empty"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let emoji: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.scaled(28))
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(108))
        .glassCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}
