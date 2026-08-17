import SwiftUI

/// „Unsere Geschichte": the server derives every milestone the couple
/// ever hit — pairing day, firsts, count milestones, badges — and this view
/// walks them as a liquid-glass timeline, newest chapter first.
struct StoryTimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var story: StoryResponse?
    @State private var loading = true
    @State private var failed = false

    // Full-screen photo opened from a story row ("your first photo" & co.).
    @State private var viewerPhoto: StoryPhoto?
    @State private var viewerZoomed = false
    @State private var viewerChromeVisible = true
    @State private var showBadges = false

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.l) {
                    if let story {
                        header(story)
                        if story.entries.isEmpty {
                            EmptyStateView(systemImage: "book.closed",
                                           title: L10n.t("story.empty.title"),
                                           subtitle: L10n.t("story.empty.subtitle"))
                                .padding(.top, Space.xxl)
                        } else {
                            chapters(story)
                            honestyFootnote
                        }
                    } else if loading {
                        PaperSkeleton(kind: .card(height: 110), onNacht: true)
                        PaperSkeleton(kind: .card(height: 180), onNacht: true)
                        PaperSkeleton(kind: .card(height: 180), onNacht: true)
                    } else if failed {
                        EmptyStateView(systemImage: "antenna.radiowaves.left.and.right.slash",
                                       title: L10n.t("weekreview.error.title"),
                                       subtitle: L10n.t("weekreview.error.subtitle"),
                                       actionTitle: L10n.t("common.retry"),
                                       action: { Task { await load() } })
                        .padding(.top, Space.xxl)
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationTitle(L10n.t("story.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await load()
        }
        .fullScreenCover(item: $viewerPhoto) { photo in
            storyPhotoViewer(photo)
        }
        .sheet(isPresented: $showBadges) {
            BadgeShelfView()
        }
    }

    // MARK: Header

    /// The book's title page — THE Briefbogen hero of this screen: couple
    /// band + wax seal, arriving on the Blättern signature. The title
    /// carries the couple's shared INK (`tinte`, not the raw blend — the
    /// paper variant of the brand-title law).
    private func header(_ story: StoryResponse) -> some View {
        VStack(spacing: Space.s) {
            Image(systemName: "book.fill")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundStyle(coupleTint.tinte)
                .symbolRenderingMode(.hierarchical)
            Text(L10n.t("story.days", ["n": String(story.daysTogether)]))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(coupleTint.tinte)
            Text(L10n.t("story.subtitle"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
                .padding(.bottom, Space.m)
        }
        .frame(maxWidth: .infinity)
        .paperCard(.briefbogen)
        .briefbogenBand(seed: memoriesPaperSeed(appState.couple?.id ?? "story"))
        .blaetternEintritt()
    }

    // MARK: Chapters (month groups, newest first)

    @ViewBuilder
    private func chapters(_ story: StoryResponse) -> some View {
        let months = MemoriesLogic.chapters(entryDateKeys: story.entries.map(\.dateKey))
        ForEach(months, id: \.self) { month in
            VStack(alignment: .leading, spacing: Space.m) {
                Text(monthTitle(month))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                ForEach(story.entries.filter { MemoriesLogic.monthKey(of: $0.dateKey) == month }) { entry in
                    entryRow(entry)
                }
            }
            .nightCard()
        }
    }

    private func monthTitle(_ month: String) -> String {
        guard let date = SharedDates.parse(month + "-01") else { return month }
        return AppFormatters.monthYear(date, language: L10n.lang)
    }

    // MARK: Rows

    /// Where a tapped row leads. Only rows with a real destination get the
    /// chevron — everything else stays a quiet milestone.
    private enum RowAction {
        case photo(StoryPhoto)
        case chat
        case badges
    }

    private func rowAction(for entry: StoryEntry) -> RowAction? {
        if let photo = entry.photo { return .photo(photo) }
        switch entry.kind {
        case "first_message": return .chat
        case "badge": return .badges
        default: return nil
        }
    }

    private func perform(_ action: RowAction) {
        Haptics.shared.tap()
        switch action {
        case .photo(let photo):
            viewerZoomed = false
            viewerChromeVisible = true
            viewerPhoto = photo
        case .chat:
            appState.activeTab = .chat
        case .badges:
            showBadges = true
        }
    }

    private func hintKey(for action: RowAction) -> String {
        switch action {
        case .photo: return "story.row.openPhoto"
        case .chat: return "story.row.openChat"
        case .badges: return "story.row.openBadges"
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: StoryEntry) -> some View {
        if let action = rowAction(for: entry) {
            Button {
                perform(action)
            } label: {
                entryRowContent(entry, navigable: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(L10n.t(hintKey(for: action))))
        } else {
            entryRowContent(entry, navigable: false)
        }
    }

    private func entryRowContent(_ entry: StoryEntry, navigable: Bool) -> some View {
        let spec = MemoriesLogic.presentation(forKind: entry.kind)
        return HStack(alignment: .top, spacing: Space.m) {
            Text(entry.emoji ?? spec.emoji)
                .font(.system(.title3))
                .frame(width: 34)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L10n.t(spec.titleKey, ["n": String(entry.n ?? 0)]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                if let subtitle = subtitle(for: entry) {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(2)
                }
                Text(dayString(entry.dateKey))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            Spacer(minLength: 0)
            if let photo = entry.photo, appState.api != nil {
                AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Papier.nachtInnenFill
                    }
                }
                .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                .clipShape(RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.control, padding: Space.xs),
                                            style: .continuous))
            }
            if navigable {
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.top, Space.xs)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
    }

    private func subtitle(for entry: StoryEntry) -> String? {
        switch entry.kind {
        case "first_message":
            return entry.teaser.map { "„\($0)“" }
        case "first_photo":
            return entry.photo?.caption
        case "first_game":
            guard let type = entry.gameType else { return nil }
            let resolved = L10n.t("games.card.\(type).title")
            return resolved == "games.card.\(type).title" ? nil : resolved
        case "first_daily":
            if let custom = entry.customText { return custom }
            guard let couple = appState.couple, let questionId = entry.questionId else { return nil }
            let question = ContentPack.dailyQuestions.first { $0.id == questionId }
                ?? ContentPack.dailyQuestion(dateKey: entry.dateKey, coupleId: couple.id)
            return question.text.filled(partner: appState.partnerName, lang: L10n.lang)
        case "first_goal":
            guard let title = entry.title else { return nil }
            return "\(entry.emoji ?? "🏁") \(title)"
        case "badge":
            guard let badgeId = entry.badgeId else { return nil }
            let resolved = L10n.t("badge.name.\(badgeId)")
            return resolved == "badge.name.\(badgeId)" ? nil : resolved
        default:
            return nil
        }
    }

    private func dayString(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        return AppFormatters.date(date, language: L10n.lang)
    }

    // MARK: Full-screen photo (same lightbox engine as gallery/chat/vault)

    private func storyPhotoViewer(_ photo: StoryPhoto) -> some View {
        MediaLightboxShell(dragDismissEnabled: !viewerZoomed,
                           onDismiss: { viewerPhoto = nil }) {
            MediaLightboxImage(api: appState.api,
                               path: photo.url,
                               thumbPath: photo.thumbUrl,
                               onZoomedChange: { viewerZoomed = $0 },
                               onSingleTap: {
                                   withAnimation(Theme.Motion.settle) {
                                       viewerChromeVisible.toggle()
                                   }
                               })
        } chrome: {
            if viewerChromeVisible {
                viewerChrome(photo)
            }
        }
    }

    private func viewerChrome(_ photo: StoryPhoto) -> some View {
        VStack {
            HStack {
                Button {
                    Haptics.shared.tap()
                    viewerPhoto = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                        .glass(.chrome, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("chat.readerClose"))
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            Spacer()
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.m)
                    .glass(.chrome, in: Capsule())
                    .padding(.bottom, Space.xl)
            }
        }
    }

    private var honestyFootnote: some View {
        Text(L10n.t("story.honesty"))
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Loading

    private func load() async {
        guard let api = appState.api else { return }
        loading = story == nil
        failed = false
        do {
            story = try await api.story()
        } catch {
            failed = story == nil
        }
        loading = false
    }
}
