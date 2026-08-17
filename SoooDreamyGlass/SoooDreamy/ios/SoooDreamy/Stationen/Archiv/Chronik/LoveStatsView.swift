import SwiftUI

/// Love statistics dashboard — hero tiles, sent-vs-received touch bars & mood timeline.
struct LoveStatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var barsAppeared = false
    @State private var moods: [MoodEntry] = []
    @State private var touches: [Touch] = []
    @State private var sharingMoods = false
    @State private var sharedMoods = false

    private let columns = [
        GridItem(.flexible(), spacing: Space.m),
        GridItem(.flexible(), spacing: Space.m)
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
            await loadTouches()
            withAnimation(Theme.Motion.arrive.delay(0.15)) {
                barsAppeared = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let stats = appState.stats {
            statsScroll(stats)
        } else {
            ScrollView {
                VStack(spacing: Space.l) {
                    HStack(spacing: Space.m) {
                        PaperSkeleton(kind: .card(height: 108), onNacht: true)
                        PaperSkeleton(kind: .card(height: 108), onNacht: true)
                    }
                    HStack(spacing: Space.m) {
                        PaperSkeleton(kind: .card(height: 108), onNacht: true)
                        PaperSkeleton(kind: .card(height: 108), onNacht: true)
                    }
                    PaperSkeleton(kind: .card(height: 200), onNacht: true)
                }
                .padding(Space.l)
            }
        }
    }

    private func statsScroll(_ stats: Stats) -> some View {
        ScrollView {
            VStack(spacing: Space.l) {
                heroTiles(stats)
                touchComparisonCard(stats)
                weeklyTouchesCard
                moodTimelineCard
                caption(stats)
            }
            .padding(Space.l)
            .padding(.bottom, Space.m)
        }
        .refreshable {
            await appState.refreshStats()
            await loadMoods()
            await loadTouches()
        }
    }

    // MARK: Hero tiles

    private func heroTiles(_ stats: Stats) -> some View {
        LazyVGrid(columns: columns, spacing: Space.m) {
            StatTile(emoji: "💞",
                     value: String(stats.daysTogether ?? appState.daysTogether ?? 0),
                     label: L10n.t("memories.stats.daysTogether"),
                     tint: coupleTint.blend)
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
                     tint: coupleTint.primary)
            StatTile(emoji: "🎮",
                     value: String(stats.gamesPlayed),
                     label: L10n.t("memories.stats.games"),
                     tint: coupleTint.secondary)
            StatTile(emoji: "🌌",
                     value: "\(stats.bucketDone)/\(stats.bucketTotal)",
                     label: L10n.t("memories.stats.bucket"),
                     tint: Theme.mint)
        }
    }

    // MARK: Touch comparison

    private func touchComparisonCard(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L10n.t("memories.stats.touchTitle"))
                    .font(Typo.title)
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("memories.stats.touchSubtitle"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            ForEach(TouchKind.allCases) { kind in
                touchRow(kind, stats: stats)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private func touchRow(_ kind: TouchKind, stats: Stats) -> some View {
        let sent = stats.touchesSent.byType[kind.rawValue] ?? 0
        let received = stats.touchesReceived.byType[kind.rawValue] ?? 0
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Text(kind.emoji)
                Text(L10n.t(kind.titleKey))
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
            }
            bar(count: sent, maxCount: maxTouchCount(stats),
                tint: myColor, label: L10n.t("common.you"))
            bar(count: received, maxCount: maxTouchCount(stats),
                tint: partnerColor, label: appState.partnerName)
        }
        .padding(.top, Space.xs)
    }

    private func bar(count: Int, maxCount: Int, tint: Color, label: String) -> some View {
        HStack(spacing: Space.s) {
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Papier.nachtInnenFill)
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth(total: geo.size.width, count: count, maxCount: maxCount))
                        .animation(Theme.Motion.arrive, value: barsAppeared)
                }
            }
            .frame(height: 12)
            Text(String(count))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .frame(width: 36, alignment: .trailing)
                // Rolling digits when a refresh bumps the touch tally (S3).
                .contentTransition(.numericText())
                .animation(Theme.Motion.settle, value: count)
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

    /// Member colors for bars and legend dots on the NIGHT charts — raw
    /// member colors stay non-text marks against the dark card (the old
    /// `inkOnPaper` ladder darkened them for bright paper and would sink
    /// them into nachtkarton).
    private var myColor: Color {
        appState.me.map { Color(hex: $0.color) } ?? coupleTint.primary
    }

    private var partnerColor: Color {
        appState.partner.map { Color(hex: $0.color) } ?? coupleTint.secondary
    }

    // MARK: Weekly touches chart

    private func loadTouches() async {
        guard let api = appState.api else { return }
        if let list = try? await api.recentTouches(limit: 200) {
            touches = list
        }
    }

    private struct WeekDay: Identifiable {
        let id: String
        let date: Date
        let mine: Int
        let partners: Int
        var total: Int { mine + partners }
    }

    /// Last 7 calendar days (oldest → today), touches split by sender.
    private var weekDays: [WeekDay] {
        let calendar = SharedDates.calendar
        let today = calendar.startOfDay(for: Date())
        let myId = appState.me?.id
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let dayTouches = touches.filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
            let mine = dayTouches.filter { $0.senderId == myId }.count
            return WeekDay(id: SharedDates.todayKey(day), date: day,
                           mine: mine, partners: dayTouches.count - mine)
        }
    }

    private var weeklyTouchesCard: some View {
        let days = weekDays
        let maxCount = max(days.map(\.total).max() ?? 0, 1)
        let weekTotal = days.reduce(0) { $0 + $1.total }
        return VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L10n.t("memories.stats.weekTitle"))
                    .font(Typo.title)
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("memories.stats.weekSubtitle"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            if weekTotal == 0 {
                Text(L10n.t("memories.stats.weekEmpty"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .bottom, spacing: Space.m) {
                    ForEach(days) { day in
                        weekColumn(day, maxCount: maxCount)
                    }
                }
                weekLegend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private func weekColumn(_ day: WeekDay, maxCount: Int) -> some View {
        VStack(spacing: Space.xs) {
            Text(day.total > 0 ? String(day.total) : " ")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
                .monospacedDigit()
                // Rolling digits when a refresh moves a day's total (S3).
                .contentTransition(.numericText())
                .animation(Theme.Motion.settle, value: day.total)
            VStack(spacing: 2) {
                if day.partners > 0 {
                    Capsule(style: .continuous)
                        .fill(partnerColor)
                        .frame(height: weekBarHeight(count: day.partners, maxCount: maxCount))
                }
                if day.mine > 0 {
                    Capsule(style: .continuous)
                        .fill(myColor)
                        .frame(height: weekBarHeight(count: day.mine, maxCount: maxCount))
                }
                if day.total == 0 {
                    Capsule(style: .continuous)
                        .fill(Papier.nachtInnenFill)
                        .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Theme.Motion.arrive, value: barsAppeared)
            Text(weekdayLetter(day.date))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
        }
        .frame(maxWidth: .infinity)
    }

    private func weekBarHeight(count: Int, maxCount: Int) -> CGFloat {
        guard barsAppeared, count > 0 else { return 4 }
        return max(6, 80 * CGFloat(count) / CGFloat(maxCount))
    }

    private var weekLegend: some View {
        HStack(spacing: Space.l) {
            legendDot(color: myColor, label: L10n.t("common.you"))
            legendDot(color: partnerColor, label: appState.partnerName)
            Spacer()
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        AppFormatters.dateTemplate(date, template: "EEEEE", language: L10n.lang)
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
            VStack(alignment: .leading, spacing: Space.s) {
                Text(L10n.t("memories.stats.topMoods"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                HStack(spacing: Space.s) {
                    ForEach(top) { item in
                        moodChip(item)
                    }
                    Spacer()
                }
                shareMoodsButton
            }
        }
    }

    /// Posts the top-moods summary into the couple chat.
    @ViewBuilder
    private var shareMoodsButton: some View {
        if appState.api != nil {
            Button {
                shareTopMoods()
            } label: {
                if sharingMoods {
                    BusySpinner(tint: coupleTint.blend)
                } else {
                    Label(L10n.t(sharedMoods ? "memories.stats.moodShared" : "memories.stats.moodShare"),
                          systemImage: sharedMoods ? "checkmark" : "paperplane.fill")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(sharedMoods ? Nacht.sekundaer : Licht.lampengold)
            .disabled(sharingMoods || sharedMoods)
        }
    }

    private func shareTopMoods() {
        guard let api = appState.api, !sharingMoods, !sharedMoods else { return }
        let top = topMoods
        guard !top.isEmpty else { return }
        sharingMoods = true
        Haptics.shared.tap()
        let summary = top
            .map { "\($0.mood) \(L10n.t("memories.stats.topMoodCount", ["n": String($0.count)]))" }
            .joined(separator: "  ·  ")
        let text = L10n.t("memories.stats.moodShareHeader") + "\n" + summary
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                sharedMoods = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.stats.moodShareSent"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharingMoods = false
        }
    }

    private func moodChip(_ item: MoodCount) -> some View {
        HStack(spacing: Space.xs) {
            Text(item.mood)
                .font(.system(.body))
            Text(L10n.t("memories.stats.topMoodCount", ["n": String(item.count)]))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .background(
            Capsule().fill(Papier.nachtInnenFill)
                .overlay(Capsule().strokeBorder(Nacht.naht,
                                                lineWidth: Theme.hairlineWidth))
        )
    }

    private var moodTimelineCard: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(L10n.t("memories.stats.moodTitle"))
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            topMoodsRow
            if moods.isEmpty {
                Text(L10n.t("memories.stats.moodEmpty"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            } else {
                ForEach(moodDays) { day in
                    moodDaySection(day)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private func moodDaySection(_ day: MoodDay) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(prettyDay(day.date))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
            ForEach(day.entries) { entry in
                moodRow(entry)
            }
        }
    }

    private func moodRow(_ entry: MoodEntry) -> some View {
        let author = member(of: entry)
        // Author wash on the night card: the raw member color at low
        // opacity marks the row — text stays the pinned night inks.
        let authorInk = author.map { Color(hex: $0.color) } ?? coupleTint.blend
        return HStack(spacing: Space.m) {
            EmojiAvatarView(emoji: author?.avatar, colorHex: author?.color, size: LayoutMetrics.s(34))
            Text(entry.mood)
                .font(.system(.title2))
            VStack(alignment: .leading, spacing: 1) {
                if let note = entry.moodNote, !note.isEmpty {
                    Text(note)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Papier.aufNacht)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            Spacer()
        }
        .padding(Space.s)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(authorInk.opacity(0.08))
        )
    }

    private func member(of entry: MoodEntry) -> Member? {
        appState.couple?.members.first { $0.id == entry.memberId }
    }

    private func prettyDay(_ date: Date) -> String {
        AppFormatters.date(date, language: L10n.lang, dateStyle: .long)
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
            EmptyStateView(systemImage: "chart.bar",
                           title: L10n.t("memories.stats.emptyTitle"),
                           subtitle: L10n.t("memories.stats.empty"))
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
        VStack(spacing: Space.s) {
            Text(emoji)
                .font(.system(.title))
            Text(value)
                .font(Typo.number)
                .foregroundStyle(Papier.aufNacht)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Flighty-style rolling digits when a refresh bumps a counter
                // (S3): the number ticks over instead of hard-swapping.
                .contentTransition(.numericText())
                .animation(Theme.Motion.settle, value: value)
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(108))
        .nightCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: Theme.hairlineWidth)
        )
    }
}
