import SwiftUI
import Combine

/// "Wir"/"Us" tab — hub for gallery, canvas, bucket list, events & love stats.
struct MemoriesView: View {
    @Environment(AppState.self) private var appState

    @State private var openCouponCount: Int?
    @State private var songCount: Int?
    // Recent-activity strip (v1.5.3): newest photo / song / coupon.
    @State private var latestPhoto: Photo?
    @State private var latestSong: Song?
    @State private var latestCoupon: Coupon?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(18)) {
                        header
                        if latestPhoto != nil || latestSong != nil || latestCoupon != nil {
                            recentStrip
                        }
                        couponsCard
                        soundtrackCard
                        LazyVGrid(columns: columns, spacing: LayoutMetrics.s(14)) {
                            galleryCard
                            canvasCard
                            bucketCard
                            eventsCard
                            statsCard
                            journalCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(12))
                }
                .refreshable {
                    await appState.refreshStats()
                    await appState.refreshEvents()
                    await loadCouponTeaser()
                    await loadSongTeaser()
                    await loadLatestPhoto()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await appState.refreshStats()
            await loadCouponTeaser()
            await loadSongTeaser()
            await loadLatestPhoto()
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

    // MARK: Recent activity strip (v1.5.3)

    /// Horizontal "what's new between you two" ribbon under the header:
    /// the newest photo, song and coupon, each deep-linking to its screen.
    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            Text(L10n.t("memories.recent.title"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.s(10)) {
                    if let photo = latestPhoto {
                        NavigationLink {
                            GalleryView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.photo"),
                                               text: photoChipText(photo),
                                               time: L10n.relativeShort(photo.createdAt),
                                               tint: Theme.pink) {
                                photoChipThumb(photo)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let song = latestSong {
                        NavigationLink {
                            SoundtrackView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.song"),
                                               text: songChipText(song),
                                               time: L10n.relativeShort(song.createdAt),
                                               tint: Theme.mint) {
                                Text("🎶")
                                    .font(.scaled(22))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    if let coupon = latestCoupon {
                        NavigationLink {
                            CouponsView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.coupon"),
                                               text: coupon.title,
                                               time: L10n.relativeShort(coupon.createdAt),
                                               tint: Theme.gold) {
                                Text(coupon.emoji)
                                    .font(.scaled(22))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Caption when present, otherwise "by <uploader>".
    private func photoChipText(_ photo: Photo) -> String {
        if let caption = photo.caption, !caption.isEmpty { return caption }
        let uploader = appState.couple?.members.first { $0.id == photo.uploaderId }?.name
        return L10n.t("memories.gallery.by", ["name": uploader ?? "💜"])
    }

    private func songChipText(_ song: Song) -> String {
        if let artist = song.artist, !artist.isEmpty { return "\(song.title) · \(artist)" }
        return song.title
    }

    @ViewBuilder
    private func photoChipThumb(_ photo: Photo) -> some View {
        if let url = appState.api?.mediaURL(photo.thumbUrl ?? photo.url) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08)
            }
            .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            Text("📸")
                .font(.scaled(22))
        }
    }

    // MARK: Cards

    /// Full-width "ticket" card — coupons get featured above the grid.
    private var couponsCard: some View {
        NavigationLink {
            CouponsView()
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                Text("🎟️")
                    .font(.scaled(34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("memories.card.coupons"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    couponTeaser
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(12, weight: .bold))
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
            HStack(spacing: LayoutMetrics.s(14)) {
                Text("🎵")
                    .font(.scaled(34))
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("memories.card.soundtrack"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    soundtrackTeaser
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(12, weight: .bold))
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
                        .font(.scaled(13, weight: .bold))
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
            latestCoupon = list.max { $0.createdAt < $1.createdAt }
        }
    }

    private func loadSongTeaser() async {
        guard let api = appState.api else { return }
        if let list = try? await api.songs() {
            songCount = list.count
            latestSong = list.max { $0.createdAt < $1.createdAt }
        }
    }

    /// Newest photo for the recent-activity strip (v1.5.3).
    private func loadLatestPhoto() async {
        guard let api = appState.api else { return }
        if let list = try? await api.photos() {
            latestPhoto = list.max { $0.createdAt < $1.createdAt }
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .photoAdded, .photoDeleted:
            Task {
                await appState.refreshStats()
                await loadLatestPhoto()
            }
        case .bucketAdded, .bucketUpdated, .bucketDeleted:
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
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(alignment: .top) {
                Text(emoji)
                    .font(.scaled(32))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(12, weight: .bold))
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
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(138), alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.14), radius: 12, y: 5)
    }
}

// MARK: - Recent activity chip (v1.5.3)

/// One small card in the horizontal recent-activity ribbon:
/// leading visual + kind label + one-line content + relative time.
private struct RecentActivityChip<Leading: View>: View {
    let kind: String
    let text: String
    let time: String
    let tint: Color
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: LayoutMetrics.s(9)) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(kind)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                Text(text)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(time)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, LayoutMetrics.s(8))
        .padding(.horizontal, LayoutMetrics.s(11))
        .frame(maxWidth: LayoutMetrics.s(220), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                )
        )
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
