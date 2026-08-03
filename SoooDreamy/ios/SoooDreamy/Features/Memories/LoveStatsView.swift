import SwiftUI

/// Love statistics dashboard — hero tiles plus sent-vs-received touch bars.
struct LoveStatsView: View {
    @Environment(AppState.self) private var appState

    @State private var barsAppeared = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("memories.stats.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.refreshStats()
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
            VStack(spacing: 16) {
                heroTiles(stats)
                touchComparisonCard(stats)
                caption(stats)
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .refreshable { await appState.refreshStats() }
    }

    // MARK: Hero tiles

    private func heroTiles(_ stats: Stats) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 14) {
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
                .font(.system(size: 28))
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
        .frame(maxWidth: .infinity, minHeight: 108)
        .glassCard(padding: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
    }
}
