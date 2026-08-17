import SwiftUI
import Combine
import UIKit

/// "Unser Monat": the server aggregates each month into a flippable
/// magazine — cover, moments, quote & song of the month and a stats spread.
/// Read receipts show when both partners flipped through an issue.
struct MagazineView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var months: [String] = []
    @State private var selectedMonth: String?
    @State private var issue: MagazineIssue?
    @State private var loading = true
    @State private var loadFailed = false
    @State private var exportImages: [UIImage] = []
    @State private var showExport = false

    var body: some View {
        ZStack {
            DreamyBackground()
            VStack(spacing: Space.m) {
                if months.count > 1 {
                    archiveBar
                }
                if let issue {
                    MagazinePages(issue: issue)
                } else if !loading {
                    ScrollView {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await loadMonths() }
                            }
                            .padding(.top, LayoutMetrics.s(60))
                            .padding(.horizontal, Space.l)
                        } else {
                            EmptyStateView(systemImage: "book.closed",
                                           title: L10n.t("magazine.empty.title"),
                                           subtitle: L10n.t("magazine.empty.subtitle"))
                                .padding(.top, LayoutMetrics.s(60))
                        }
                    }
                } else {
                    // A page-shaped placeholder — the issue arrives in the
                    // same silhouette it will occupy.
                    PaperSkeleton(kind: .card(height: 420))
                        .padding(.horizontal, Space.l)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(.top, Space.s)
        }
        .navigationTitle(L10n.t("magazine.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let issue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        renderExport(issue)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L10n.t("magazine.export"))
                }
            }
        }
        .task(id: appState.couple?.id) {
            await loadMonths()
        }
        .onChange(of: selectedMonth) {
            Task { await loadIssue() }
        }
        .sheet(isPresented: $showExport) {
            MagazineExportSheet(images: exportImages)
        }
    }

    // MARK: Archive

    private var archiveBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                Text(L10n.t("magazine.archive"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                ForEach(months, id: \.self) { month in
                    let selected = month == selectedMonth
                    Button {
                        Haptics.shared.tap()
                        selectedMonth = month
                    } label: {
                        Text(magazineMonthName(month))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.vertical, Space.s)
                            .padding(.horizontal, Space.m)
                            .background(Capsule().fill(selected
                                ? AnyShapeStyle(coupleTint.blend.opacity(0.30))
                                : AnyShapeStyle(Theme.innerFill)))
                            .overlay(Capsule().strokeBorder(selected ? coupleTint.blend : .clear,
                                                            lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.l)
        }
    }

    // MARK: Loading

    private func loadMonths() async {
        guard let api = appState.api else { return }
        loading = true
        do {
            let list = try await api.magazineMonths()
            months = list
            if selectedMonth == nil || !list.contains(selectedMonth ?? "") {
                selectedMonth = list.first
            }
            loadFailed = false
            await loadIssue()
        } catch {
            // A failed primary load must not LOOK like "no issues yet" —
            // the shared failed/offline notice offers an honest retry.
            loadFailed = true
        }
        loading = false
    }

    private func loadIssue() async {
        guard let api = appState.api, let month = selectedMonth else { return }
        do {
            issue = try await api.magazine(month: month)
            loadFailed = false
            // Read receipt — fire-and-forget; the WS echo updates the partner.
            _ = try? await api.markMagazineSeen(month: month)
        } catch {
            // Only an honest notice when NO issue is on screen — an already
            // rendered issue stays (content wins over transient errors).
            if issue == nil { loadFailed = true }
        }
    }

    @MainActor
    private func renderExport(_ issue: MagazineIssue) {
        let palette = appState.couple?.palette
        let pages = [
            MagazineExportCard(issue: issue, page: .highlights, palette: palette),
            MagazineExportCard(issue: issue, page: .stats, palette: palette),
        ]
        exportImages = pages.compactMap { page in
            let renderer = ImageRenderer(content: page.frame(width: 360, height: 640))
            renderer.scale = 3
            return renderer.uiImage
        }
        showExport = !exportImages.isEmpty
    }
}

/// Month title like "August 2026" from a "YYYY-MM" key.
func magazineMonthName(_ month: String) -> String {
    let parts = month.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 2,
          let date = SharedDates.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: 15))
    else { return month }
    return AppFormatters.monthYear(date, language: L10n.lang)
}

// MARK: - The flippable issue

private struct MagazinePages: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let issue: MagazineIssue

    var body: some View {
        TabView {
            coverPage
            if !issue.photos.isEmpty {
                photosPage
            }
            if let quote = issue.quote {
                quotePage(quote)
            }
            if let song = issue.song {
                songPage(song)
            }
            statsPage
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    private var bothSeen: Bool {
        guard let members = appState.couple?.members, members.count == 2 else { return false }
        return members.allSatisfy { issue.seen[$0.id] != nil }
    }

    // MARK: Cover

    private var coverPage: some View {
        MagazinePage {
            Spacer()
            if let members = appState.couple?.members, members.count >= 2 {
                CoupleMonogramView(
                    firstName: members[0].name,
                    secondName: members[1].name,
                    palette: appState.couple?.palette,
                    style: appState.couple?.monogramStyle ?? .seal,
                    size: LayoutMetrics.s(88)
                )
            } else {
                Image(icon: .sendLove)
                    .font(Typo.hero)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.tinte)
                    .accessibilityHidden(true)
            }
            // Shared couple ink on the paper cover — brandTitle carries
            // the raw blend and stays a night-surface treatment.
            Text(L10n.t("magazine.title"))
                .font(Typo.hero)
                .foregroundStyle(coupleTint.tinte)
            Text(magazineMonthName(issue.month))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            PillTag(text: L10n.t("magazine.issue") + " " + issue.month, tint: Theme.gold,
                    onPaper: true)
            if bothSeen {
                Text(L10n.t("magazine.seenBoth"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.tinte)
            }
            Spacer()
            Text(L10n.t("magazine.swipeHint"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.tertiaer)
                .padding(.bottom, Space.m)
        }
    }

    // MARK: Moments of the month

    private var photosPage: some View {
        MagazinePage(scrolls: true) {
            pageTitle("photo.on.rectangle.angled", L10n.t("magazine.photos"))
            ForEach(issue.photos) { photo in
                VStack(alignment: .leading, spacing: Space.s) {
                    if appState.api != nil {
                        AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                PaperSkeleton(kind: .tile(height: 190))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: LayoutMetrics.s(190))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                    }
                    HStack {
                        if let caption = photo.caption, !caption.isEmpty {
                            Text(caption)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Tinte.sekundaer)
                                .lineLimit(2)
                        }
                        Spacer()
                        if !photo.favorites.isEmpty {
                            HStack(spacing: 3) {
                                Image(icon: .sendLove)
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(coupleTint.tinte)
                                Text(String(photo.favorites.count))
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(Tinte.tertiaer)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Quote of the month

    private func quotePage(_ quote: MagazineQuote) -> some View {
        MagazinePage(scrolls: true) {
            pageTitle("quote.bubble.fill", L10n.t("magazine.quote"))
            if let question = questionText(quote) {
                Text(question)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sortedAnswers(quote), id: \.0) { memberId, answer in
                let member = appState.couple?.members.first { $0.id == memberId }
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("\(member?.avatar ?? "") \(member?.name ?? "?")")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Tinte.sekundaer)
                    Text("„\(answer)“")
                        .font(Typo.voice)
                        .foregroundStyle(Tinte.dunkel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Papier.innenFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
                )
            }
            if let date = SharedDates.parse(quote.dateKey) {
                Text(ritualDateString(date))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
        }
    }

    private func questionText(_ quote: MagazineQuote) -> String? {
        guard let couple = appState.couple else { return nil }
        let question = ContentPack.dailyQuestions.first { $0.id == quote.questionId }
            ?? ContentPack.dailyQuestion(dateKey: quote.dateKey, coupleId: couple.id)
        return question.text.filled(partner: appState.partnerName, lang: L10n.lang)
    }

    /// My answer first, then the partner's.
    private func sortedAnswers(_ quote: MagazineQuote) -> [(String, String)] {
        quote.answers.sorted { lhs, _ in lhs.key == appState.memberId }
            .map { ($0.key, $0.value) }
    }

    // MARK: Song of the month

    private func songPage(_ song: MagazineSong) -> some View {
        MagazinePage {
            Spacer()
            pageTitle("music.note", L10n.t("magazine.song"))
            Text(song.title)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
            if let artist = song.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            }
            if !song.heartedBy.isEmpty {
                Text(String(repeating: "💜", count: song.heartedBy.count))
                    .font(.system(.title3))
            }
            Spacer()
        }
    }

    // MARK: Stats spread

    private var statsPage: some View {
        MagazinePage(scrolls: true) {
            pageTitle("chart.bar.fill", L10n.t("magazine.stats"))
            let tiles = statTiles.filter { $0.value > 0 }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m)],
                      spacing: Space.m) {
                ForEach(tiles.isEmpty ? statTiles : tiles, id: \.key) { tile in
                    VStack(spacing: 3) {
                        Text(tile.emoji)
                            .font(.system(.title3))
                        Text(String(tile.value))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Tinte.dunkel)
                        Text(L10n.t(tile.key))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Tinte.sekundaer)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.innenFill)
                    )
                }
            }
        }
    }

    private var statTiles: [(key: String, emoji: String, value: Int)] {
        let stats = issue.stats
        return [
            ("magazine.stat.messages", "💬", stats.messages),
            ("magazine.stat.touches", "💞", stats.touches),
            ("magazine.stat.photos", "📸", stats.photosAdded),
            ("magazine.stat.videos", "🎬", stats.videosAdded),
            ("magazine.stat.games", "🎮", stats.gamesPlayed),
            ("magazine.stat.wordle", "🟩", stats.wordleDays),
            ("magazine.stat.daily", "❓", stats.dailyBothAnswered),
            ("magazine.stat.checkins", "🌤️", stats.checkinDaysBoth),
            ("magazine.stat.daymemos", "🎙️", stats.daymemoDays),
            ("magazine.stat.hugs", "🫂", stats.hugsSent),
            ("magazine.stat.potd", "📷", stats.potdDays),
            ("magazine.stat.goals", "🎯", stats.goalsCompleted)
        ]
    }

    /// Page header: SF Symbol chrome above the title — magazine sections
    /// speak the app's icon language, not emoji (commandment 1).
    private func pageTitle(_ systemImage: String, _ title: String) -> some View {
        VStack(spacing: Space.xs) {
            Image(systemName: systemImage)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.tinte)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Tinte.dunkel)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - One magazine page frame

private struct MagazinePage<Content: View>: View {
    var scrolls = false
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if scrolls {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Space.l) {
                        content
                    }
                    .padding(CardPadding.hero.value)
                }
            } else {
                VStack(spacing: Space.l) {
                    content
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(CardPadding.hero.value)
            }
        }
        // The issue is a sheet of paper on the desk: opaque brief fill,
        // grain, the lamp's light edge — the `paperCard()` recipe, hand-
        // built because the page owns its scroll/padding structure.
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.brief)
                .overlay(PaperGrainView().clipShape(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(PaperLightEdge.gradient,
                                      lineWidth: Theme.hairlineWidth)
                )
                .elevation(.resting)
        )
        .padding(.horizontal, Space.l)
        .padding(.bottom, LayoutMetrics.s(34))
    }
}

private enum MagazineExportPage: Equatable {
    case highlights
    case stats
}

private struct MagazineExportCard: View {
    let issue: MagazineIssue
    let page: MagazineExportPage
    /// Rendered offscreen via `ImageRenderer` — the environment does not
    /// flow in, so the couple's palette is passed explicitly.
    var palette: CouplePalette?

    private var tint: CoupleTint { CoupleTint(palette: palette) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.bgTop, Theme.indigo.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 18) {
                Image(systemName: "heart.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(tint.blend)
                Text(L10n.t("magazine.title"))
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(tint.blend)
                Text(magazineMonthName(issue.month))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Divider().overlay(Theme.hairline)
                if page == .highlights {
                    highlights
                } else {
                    stats
                }
                Spacer()
                Text("SoooDreamy · made by Sonic0810")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(30)
        }
    }

    @ViewBuilder
    private var highlights: some View {
        if let quote = issue.quote {
            Text(L10n.t("magazine.quote"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
            ForEach(Array(quote.answers.values.prefix(2)), id: \.self) { answer in
                Text("“\(answer)”")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        } else if let song = issue.song {
            HStack(spacing: Space.s) {
                Image(systemName: "music.note")
                    .foregroundStyle(Theme.gold)
                Text(song.title)
            }
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            if let artist = song.artist {
                Text(artist)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Text(L10n.t("magazine.photos"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(String(issue.photos.count))
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.gold)
        }
    }

    private var stats: some View {
        let values = [
            ("💬", L10n.t("magazine.stat.messages"), issue.stats.messages),
            ("💞", L10n.t("magazine.stat.touches"), issue.stats.touches),
            ("📸", L10n.t("magazine.stat.photos"), issue.stats.photosAdded),
            ("🎮", L10n.t("magazine.stat.games"), issue.stats.gamesPlayed),
            ("❓", L10n.t("magazine.stat.daily"), issue.stats.dailyBothAnswered),
            ("🎯", L10n.t("magazine.stat.goals"), issue.stats.goalsCompleted),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Text(item.0)
                        .font(.system(.title2))
                    Text(String(item.2))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Text(item.1)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Theme.innerFill))
            }
        }
    }
}

private struct MagazineExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let images: [UIImage]
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.control))
                    }
                    Button {
                        showShareSheet = true
                    } label: {
                        Label(L10n.t("magazine.export.share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Space.l)
            }
            .background(DreamyBackground())
            .navigationTitle(L10n.t("magazine.export"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                MagazineActivityShareSheet(items: images)
            }
        }
    }
}

private struct MagazineActivityShareSheet: UIViewControllerRepresentable {
    let items: [UIImage]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
