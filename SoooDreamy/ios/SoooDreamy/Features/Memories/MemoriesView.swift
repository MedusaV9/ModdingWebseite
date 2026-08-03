import SwiftUI
import Combine

/// "Wir"/"Us" tab — hub for gallery, canvas, bucket list, events & love stats.
struct MemoriesView: View {
    @Environment(AppState.self) private var appState

    @State private var openCouponCount: Int?
    @State private var songCount: Int?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        couponsCard
                        soundtrackCard
                        LazyVGrid(columns: columns, spacing: 14) {
                            galleryCard
                            canvasCard
                            bucketCard
                            eventsCard
                            statsCard
                            journalCard
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 12)
                }
                .refreshable {
                    await appState.refreshStats()
                    await appState.refreshEvents()
                    await loadCouponTeaser()
                    await loadSongTeaser()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await appState.refreshStats()
            await loadCouponTeaser()
            await loadSongTeaser()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("memories.title"))
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(
                    LinearGradient(colors: [Theme.rose, Theme.pink, Theme.purple],
                                   startPoint: .leading, endPoint: .trailing)
                )
            Text(L10n.t("memories.subtitle"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    // MARK: Cards

    /// Full-width "ticket" card — coupons get featured above the grid.
    private var couponsCard: some View {
        NavigationLink {
            CouponsView()
        } label: {
            HStack(spacing: 14) {
                Text("🎟️")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("memories.card.coupons"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    couponTeaser
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            )
            .shadow(color: Theme.gold.opacity(0.12), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var couponTeaser: some View {
        if let count = openCouponCount, count > 0 {
            PillTag(text: "🎁 " + L10n.t("memories.card.couponsRedeemable", ["n": String(count)]),
                    tint: Theme.gold)
        } else {
            Text(L10n.t("memories.card.couponsHint"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    /// Full-width soundtrack card — the shared playlist sits below the coupons ticket.
    private var soundtrackCard: some View {
        NavigationLink {
            SoundtrackView()
        } label: {
            HStack(spacing: 14) {
                Text("🎵")
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("memories.card.soundtrack"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    soundtrackTeaser
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Theme.mint.opacity(0.45), Theme.blue.opacity(0.4)],
                                                 startPoint: .leading, endPoint: .trailing),
                                  lineWidth: 1.5)
            )
            .shadow(color: Theme.mint.opacity(0.12), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var soundtrackTeaser: some View {
        if let count = songCount, count > 0 {
            PillTag(text: "🎶 " + songCountText(count), tint: Theme.mint)
        } else {
            Text(L10n.t("memories.card.soundtrackHint"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func songCountText(_ count: Int) -> String {
        count == 1
            ? L10n.t("memories.card.songOne")
            : L10n.t("memories.card.songCount", ["n": String(count)])
    }

    private var galleryCard: some View {
        NavigationLink {
            GalleryView()
        } label: {
            MemoryFeatureCard(emoji: "📸",
                              title: L10n.t("memories.card.gallery"),
                              tint: Theme.pink) {
                PillTag(text: photoTeaserText, tint: Theme.pink)
            }
        }
        .buttonStyle(.plain)
    }

    private var canvasCard: some View {
        NavigationLink {
            CanvasView()
        } label: {
            MemoryFeatureCard(emoji: "🎨",
                              title: L10n.t("memories.card.canvas"),
                              tint: Theme.purple) {
                HStack(spacing: 6) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.purple)
                    Text(L10n.t("memories.card.drawTogether"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var bucketCard: some View {
        NavigationLink {
            BucketListView()
        } label: {
            MemoryFeatureCard(emoji: "🌌",
                              title: L10n.t("memories.card.bucket"),
                              tint: Theme.indigo) {
                bucketTeaser
            }
        }
        .buttonStyle(.plain)
    }

    private var eventsCard: some View {
        NavigationLink {
            EventsView()
        } label: {
            MemoryFeatureCard(emoji: "🗓️",
                              title: L10n.t("memories.card.events"),
                              tint: Theme.gold) {
                eventTeaser
            }
        }
        .buttonStyle(.plain)
    }

    private var statsCard: some View {
        NavigationLink {
            LoveStatsView()
        } label: {
            MemoryFeatureCard(emoji: "📊",
                              title: L10n.t("memories.card.stats"),
                              tint: Theme.mint) {
                statsTeaser
            }
        }
        .buttonStyle(.plain)
    }

    private var journalCard: some View {
        NavigationLink {
            JournalView()
        } label: {
            MemoryFeatureCard(emoji: "📖",
                              title: L10n.t("memories.card.journal"),
                              tint: Theme.rose) {
                journalTeaser
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Teasers

    private var photoTeaserText: String {
        guard let count = appState.stats?.photos, count > 0 else {
            return L10n.t("memories.card.noPhotos")
        }
        if count == 1 { return L10n.t("memories.card.photoOne") }
        return L10n.t("memories.card.photoCount", ["n": String(count)])
    }

    @ViewBuilder
    private var bucketTeaser: some View {
        let done = appState.stats?.bucketDone ?? 0
        let total = appState.stats?.bucketTotal ?? 0
        if total > 0 {
            HStack(spacing: 8) {
                MiniProgressRing(progress: Double(done) / Double(max(total, 1)))
                Text("\(done)/\(total) \(L10n.t("memories.card.dreams"))")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        } else {
            Text(L10n.t("memories.card.noBucket"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var eventTeaser: some View {
        if let next = appState.nextEvent {
            PillTag(text: "\(next.event.emoji) \(countdownText(days: next.days))", tint: Theme.gold)
        } else {
            Text(L10n.t("memories.card.noEvent"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var statsTeaser: some View {
        if let days = appState.stats?.daysTogether ?? appState.daysTogether, days > 0 {
            PillTag(text: "💞 " + L10n.t("memories.card.daysOfLove", ["n": String(days)]),
                    tint: Theme.mint)
        } else {
            Text(L10n.t("memories.card.statsHint"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var journalTeaser: some View {
        if let answered = appState.stats?.dailyAnswered, answered > 0 {
            PillTag(text: L10n.t("memories.card.journalCount", ["n": String(answered)]),
                    tint: Theme.rose)
        } else {
            Text(L10n.t("memories.card.journalHint"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func countdownText(days: Int) -> String {
        if days == 0 { return L10n.t("memories.countdown.today") }
        if days == 1 { return L10n.t("memories.countdown.tomorrow") }
        return L10n.t("memories.countdown.inDays", ["n": String(days)])
    }

    // MARK: Realtime teaser refresh

    private func loadCouponTeaser() async {
        guard let api = appState.api, let myId = appState.memberId else { return }
        if let list = try? await api.coupons() {
            openCouponCount = list.filter { $0.forMember == myId && $0.redeemedAt == nil }.count
        }
    }

    private func loadSongTeaser() async {
        guard let api = appState.api else { return }
        if let list = try? await api.songs() {
            songCount = list.count
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .photoAdded, .photoDeleted, .bucketAdded, .bucketUpdated, .bucketDeleted:
            Task { await appState.refreshStats() }
        case .couponAdded, .couponRedeemed, .couponDeleted:
            Task { await loadCouponTeaser() }
        case .songAdded, .songDeleted:
            Task { await loadSongTeaser() }
        default:
            break
        }
    }
}

// MARK: - Feature card

private struct MemoryFeatureCard<Teaser: View>: View {
    let emoji: String
    let title: String
    let tint: Color
    @ViewBuilder var teaser: Teaser

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(emoji)
                    .font(.system(size: 32))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
            }
            Spacer(minLength: 4)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            teaser
                .frame(height: 26, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.14), radius: 12, y: 5)
    }
}

// MARK: - Mini progress ring

private struct MiniProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Theme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
    }
}
