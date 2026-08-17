import SwiftUI
import Combine

/// „Eure Woche": the server aggregates every ISO week into a small
/// liquid-glass review — numbers, the week's quote, the top photo — plus the
/// mutual highlight ritual: each partner shares their moment of the week and
/// the partner's pick reveals only once BOTH shared (server-enforced).
struct WeekReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    /// The week to open with (nil = current week).
    var initialWeek: String?

    @State private var selectedWeek: String?
    @State private var review: WeekReviewResponse?
    @State private var loading = true
    @State private var failed = false
    @State private var highlightText = ""
    /// Optional photo attached to my highlight (server: `photoId`).
    @State private var highlightPhotoId: String?
    @State private var showHighlightPhotoPicker = false
    @State private var sendingHighlight = false
    @State private var sharedToChat = false
    @State private var sharingToChat = false
    /// Weeks whose read receipt already left this session (B-21: the POST
    /// fires when the END of the review scrolls into view, not on open).
    @State private var receiptedWeeks = Set<String>()

    private var currentWeek: String? {
        WeekReviewLogic.weekKey(forDateKey: SharedDates.todayKey())
    }

    /// Each partner's own chosen color carries their bubble — never a
    /// stock pink/purple pair (commandment 11). On paper the raw colors
    /// run through the ink ladder so names stay ≥4.5:1 on every tone.
    private var myTint: Color {
        appState.me.map { Color(hex: CouplePaletteRules.inkOnPaper($0.color)) }
            ?? coupleTint.tintePrimary
    }

    private var partnerTint: Color {
        appState.partner.map { Color(hex: CouplePaletteRules.inkOnPaper($0.color)) }
            ?? coupleTint.tinteSecondary
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView(showsIndicators: false) {
                VStack(spacing: Space.l) {
                    weekPicker
                    if let review {
                        content(review)
                    } else if loading {
                        // Skeletons in the rhythm of the coming review:
                        // header, highlight ritual, stats grid — paper
                        // silhouettes, because paper is what arrives.
                        VStack(spacing: Space.l) {
                            PaperSkeleton(kind: .card(height: 110))
                            PaperSkeleton(kind: .card(height: 150))
                            PaperSkeleton(kind: .card(height: 190))
                        }
                    } else if failed {
                        EmptyStateView(systemImage: "antenna.radiowaves.left.and.right.slash",
                                       title: L10n.t("weekreview.error.title"),
                                       subtitle: L10n.t("weekreview.error.subtitle"),
                                       actionTitle: L10n.t("common.retry"),
                                       action: { Task { await load() } })
                        .padding(.top, LayoutMetrics.s(40))
                    }
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
        }
        .navigationTitle(L10n.t("weekreview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            if selectedWeek == nil { selectedWeek = initialWeek ?? currentWeek }
            await load()
        }
        .onChange(of: selectedWeek) {
            sharedToChat = false
            highlightPhotoId = nil
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .weekHighlight:
                if let payload = event.decode(WeekReviewResponse.self),
                   payload.week == selectedWeek {
                    let wasBoth = review?.highlight.bothShared ?? false
                    review = payload
                    if payload.highlight.bothShared && !wasBoth {
                        // R1-D: medium celebrations bloom in the app-wide
                        // Lichtschein instead of confetti (epic keeps its
                        // particles); the fanfare stays the ear's half.
                        AppCue.fanfareMedium.play()
                        LichtscheinCenter.shared.fire()
                        SoundEngine.shared.play(.sparkle)
                    }
                }
            case .weekReviewSeen:
                if let payload = event.decode(WeekReviewSeenResponse.self),
                   payload.week == selectedWeek {
                    Task { await load(quietly: true) }
                }
            default:
                break
            }
        }
    }

    // MARK: Week picker (current + the last few weeks)

    private var pickableWeeks: [String] {
        guard var week = currentWeek else { return [] }
        var keys: [String] = []
        for _ in 0..<6 {
            keys.append(week)
            guard let previous = WeekReviewLogic.previousWeekKey(week) else { break }
            week = previous
        }
        return keys
    }

    private var weekPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(pickableWeeks, id: \.self) { week in
                    let selected = week == selectedWeek
                    Button {
                        Haptics.shared.tap()
                        selectedWeek = week
                    } label: {
                        Text(weekLabel(week))
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
            .padding(.vertical, 2)
        }
    }

    private func weekLabel(_ week: String) -> String {
        if week == currentWeek { return L10n.t("weekreview.thisWeek") }
        if let current = currentWeek, WeekReviewLogic.previousWeekKey(current) == week {
            return L10n.t("weekreview.lastWeek")
        }
        return weekRangeString(week)
    }

    private func weekRangeString(_ week: String) -> String {
        let days = WeekReviewLogic.dateKeys(ofWeek: week)
        guard let first = days.first, let last = days.last,
              let start = SharedDates.parse(first), let end = SharedDates.parse(last) else {
            return week
        }
        return AppFormatters.dateTemplate(start, template: "d.M.", language: L10n.lang)
            + " – " + AppFormatters.dateTemplate(end, template: "d.M.yyyy", language: L10n.lang)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ review: WeekReviewResponse) -> some View {
        header(review)
        highlightCard(review)
        if WeekReviewLogic.isQuietWeek(review.stats.asLogicStats), !review.current {
            quietWeekCard
        } else {
            if review.stats.perfectDays > 0 {
                perfectDaysCard(review.stats.perfectDays)
            }
            statsGrid(review)
        }
        if let quote = review.quote {
            quoteCard(quote)
        }
        if let photo = review.topPhoto {
            topPhotoCard(photo)
        }
        if !review.current {
            shareButton(review)
            readReceiptSentinel(review)
        }
    }

    /// A completed week in which nothing happened deserves warmth, not a
    /// wall of zeros (48#4).
    private var quietWeekCard: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "moon.stars.fill")
                .font(.system(.title2, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
            Text(L10n.t("weekreview.quiet.title"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("weekreview.quiet.subtitle"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    /// Hero card for the rarest number of the week: days on which BOTH the
    /// daily question and the check-in happened (48#3 dramaturgy — the best
    /// number gets a stage, not a grid tile).
    private func perfectDaysCard(_ perfectDays: Int) -> some View {
        HStack(spacing: Space.l) {
            // The hero number glows in lamplight on night (11.9:1) — couple
            // inks are paper-only.
            Text(AppFormatters.integer(perfectDays, language: L10n.lang))
                .font(.system(.largeTitle, design: .rounded).weight(.heavy)
                    .monospacedDigit())
                .foregroundStyle(Licht.lampengold)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(perfectDays == 1 ? "weekreview.perfect.one"
                                             : "weekreview.perfect.many"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("weekreview.perfect.caption"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .nightCard()
    }

    /// B-21: the read receipt fires when this end-of-review marker becomes
    /// visible — "both read it" then actually means both scrolled through.
    private func readReceiptSentinel(_ review: WeekReviewResponse) -> some View {
        Color.clear
            .frame(height: 1)
            .onAppear { markSeen(review) }
    }

    private func markSeen(_ review: WeekReviewResponse) {
        guard !review.current,
              let api = appState.api,
              let myId = appState.memberId,
              review.seen[myId] == nil,
              receiptedWeeks.insert(review.week).inserted else { return }
        Task {
            do {
                _ = try await api.markWeekReviewSeen(week: review.week)
                await load(quietly: true)
            } catch {
                // The server still counts the week as unread — allow another
                // attempt the next time the end scrolls into view.
                receiptedWeeks.remove(review.week)
            }
        }
    }

    private func header(_ review: WeekReviewResponse) -> some View {
        VStack(spacing: Space.s) {
            Image(icon: .memory)
                .font(Typo.hero)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(review.current ? L10n.t("weekreview.header.current")
                                : L10n.t("weekreview.header.done"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Licht.lampengold)
            Text(weekRangeString(review.week))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            if bothSeen(review) {
                Text(L10n.t("weekreview.seenBoth"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    private func bothSeen(_ review: WeekReviewResponse) -> Bool {
        guard let members = appState.couple?.members, members.count == 2 else { return false }
        return members.allSatisfy { review.seen[$0.id] != nil }
    }

    // MARK: Stats

    private func statsGrid(_ review: WeekReviewResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("weekreview.stats"), systemImage: "chart.bar.fill")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m),
                                GridItem(.flexible(), spacing: Space.m)],
                      spacing: Space.m) {
                ForEach(WeekReviewLogic.dramaturgyCards(from: review.stats.asLogicStats)) { card in
                    VStack(spacing: 3) {
                        Text(card.emoji)
                            .font(.system(.title3))
                        Text(AppFormatters.integer(card.value, language: L10n.lang))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(Papier.aufNacht)
                        Text(L10n.t(card.titleKey))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Nacht.sekundaer)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.nachtInnenFill)
                    )
                }
            }
        }
        .nightCard()
    }

    // MARK: Highlight ritual

    @ViewBuilder
    private func highlightCard(_ review: WeekReviewResponse) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("weekreview.highlight.title"), systemImage: "sparkles",
                          onPaper: true)

            if review.highlight.bothShared {
                if let mine = review.highlight.mine {
                    highlightBubble(name: appState.me?.name ?? L10n.t("common.you"),
                                    text: mine.text, tint: myTint,
                                    photoId: mine.photoId)
                }
                if let partner = review.highlight.partner {
                    highlightBubble(name: appState.partnerName,
                                    text: partner.text, tint: partnerTint,
                                    photoId: partner.photoId)
                }
                Text(L10n.t("weekreview.highlight.bothShared"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.tinte)
            } else if let mine = review.highlight.mine {
                highlightBubble(name: appState.me?.name ?? L10n.t("common.you"),
                                text: mine.text, tint: myTint,
                                photoId: mine.photoId)
                Text(L10n.t("weekreview.highlight.waiting", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            } else if highlightWindowOpen(review.week) {
                Text(L10n.t("weekreview.highlight.prompt", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.m) {
                    TextField(L10n.t("weekreview.highlight.placeholder"),
                              text: $highlightText, axis: .vertical)
                        .paperField()
                        .lineLimit(1...4)
                    Button {
                        Task { await submitHighlight(review.week) }
                    } label: {
                        if sendingHighlight {
                            BusySpinner(tint: Theme.onHero)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(.body, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.onHero)
                        }
                    }
                    .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                    // Computed ink + platter: white read only 2.94:1 on the
                    // static brand gradient (Schlussrunde 5).
                    .background(Theme.heroPlatter(in: Circle()))
                    .disabled(sendingHighlight
                              || highlightText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel(L10n.t("weekreview.highlight.send"))
                }
                highlightPhotoRow(review)
                if let daysLeft = WeekReviewLogic.highlightWindowDaysLeft(
                    week: review.week, todayKey: SharedDates.todayKey()) {
                    Text(daysLeft == 1
                         ? L10n.t("weekreview.window.day")
                         : L10n.t("weekreview.window.days", ["n": String(daysLeft)]))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.tertiaer)
                        .monospacedDigit()
                }
            } else {
                Text(L10n.t("weekreview.highlight.closed"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
        }
        .paperCard()
        .sheet(isPresented: $showHighlightPhotoPicker) {
            WeekHighlightPhotoPicker(week: review.week) { photoId in
                highlightPhotoId = photoId
            }
        }
    }

    /// Attach-a-photo row under the composer: the server carries `photoId`
    /// with the highlight, so the moment can come with its picture (K-14).
    @ViewBuilder
    private func highlightPhotoRow(_ review: WeekReviewResponse) -> some View {
        if let photoId = highlightPhotoId {
            HStack(spacing: Space.m) {
                AuthenticatedAsyncImage(api: appState.api,
                                        path: "/api/photos/\(photoId)/thumb/raw",
                                        maxPixelSize: 256) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        PaperSkeleton(kind: .tile(height: 44))
                    }
                }
                .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                .clipShape(RoundedRectangle(
                    cornerRadius: Radius.concentric(parent: Radius.control, padding: Space.xs),
                    style: .continuous))
                Text(L10n.t("weekreview.highlight.photoAttached"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.sekundaer)
                Spacer()
                Button {
                    Haptics.shared.tap()
                    highlightPhotoId = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Tinte.tertiaer)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("weekreview.highlight.removePhoto"))
            }
        } else {
            Button {
                Haptics.shared.tap()
                showHighlightPhotoPicker = true
            } label: {
                Label(L10n.t("weekreview.highlight.addPhoto"), systemImage: "photo.badge.plus")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.tinte)
            }
            .buttonStyle(.plain)
        }
    }

    private func highlightWindowOpen(_ week: String) -> Bool {
        guard let current = currentWeek else { return false }
        return week == current || week == WeekReviewLogic.previousWeekKey(current)
    }

    /// The partner's words as an ink paragraph: name in their own ink, the
    /// flowing text in Tinte.dunkel, a 4-pt ink edge marking authorship —
    /// never a tinted bubble on paper.
    private func highlightBubble(name: String, text: String, tint: Color,
                                 photoId: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            if let photoId {
                highlightBubblePhoto(photoId)
            }
            Text(text)
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: Papier.tintenkante / 2, style: .continuous)
                .fill(tint)
                .frame(width: Papier.tintenkante)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The photo a partner attached to their highlight. A deleted photo
    /// degrades to nothing — the words still stand on their own.
    private func highlightBubblePhoto(_ photoId: String) -> some View {
        AuthenticatedAsyncImage(api: appState.api,
                                path: "/api/photos/\(photoId)/thumb/raw") { phase in
            switch phase {
            case .success(let image):
                image.resizable()
                    .scaledToFill()
                    .frame(height: LayoutMetrics.s(140))
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(
                        cornerRadius: Radius.concentric(parent: Radius.control, padding: Space.xs),
                        style: .continuous))
            case .failure:
                EmptyView()
            default:
                PaperSkeleton(kind: .tile(height: 140))
            }
        }
    }

    // MARK: Quote & photo

    private func quoteCard(_ quote: WeekReviewQuote) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("weekreview.quote"), systemImage: "quote.bubble.fill",
                          onPaper: true)
            if let text = quoteQuestionText(quote) {
                // The couple's question of the week speaks in their voice —
                // serif on paper, like the daily-question hero.
                Text(text)
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(sortedAnswers(quote), id: \.0) { memberId, answer in
                let member = appState.couple?.members.first { $0.id == memberId }
                highlightBubble(name: member?.name ?? "?",
                                text: answer,
                                tint: memberId == appState.memberId ? myTint : partnerTint)
            }
        }
        .paperCard()
    }

    private func quoteQuestionText(_ quote: WeekReviewQuote) -> String? {
        if let custom = quote.customText { return custom }
        guard let couple = appState.couple else { return nil }
        let question = ContentPack.dailyQuestions.first { $0.id == quote.questionId }
            ?? ContentPack.dailyQuestion(dateKey: quote.dateKey, coupleId: couple.id)
        return question.text.filled(partner: appState.partnerName, lang: L10n.lang)
    }

    private func sortedAnswers(_ quote: WeekReviewQuote) -> [(String, String)] {
        quote.answers.sorted { lhs, _ in lhs.key == appState.memberId }
            .map { ($0.key, $0.value) }
    }

    private func topPhotoCard(_ photo: MagazinePhoto) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: L10n.t("weekreview.topPhoto"), systemImage: "photo.fill",
                          onPaper: true)
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
            if let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Tinte.sekundaer)
                    .lineLimit(2)
            }
        }
        .paperCard(.polaroid)
    }

    // MARK: Share to chat

    private func shareButton(_ review: WeekReviewResponse) -> some View {
        Button {
            shareToChat(review)
        } label: {
            if sharingToChat {
                BusySpinner()
            } else {
                Label(L10n.t(sharedToChat ? "games.sharedToChat" : "weekreview.share"),
                      systemImage: sharedToChat ? "checkmark" : "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(sharingToChat || sharedToChat)
    }

    private func shareToChat(_ review: WeekReviewResponse) {
        guard let api = appState.api, !sharingToChat, !sharedToChat else { return }
        sharingToChat = true
        Haptics.shared.tap()
        let stats = review.stats
        var lines = [L10n.t("weekreview.share.header", ["range": weekRangeString(review.week)])]
        lines.append("💬 \(stats.messages) · 💓 \(stats.touches) · 🎮 \(stats.gamesPlayed) · 📸 \(stats.photosAdded)")
        if stats.perfectDays > 0 {
            lines.append(L10n.t("weekreview.share.perfect", count: stats.perfectDays))
        }
        if review.highlight.bothShared,
           let mine = review.highlight.mine, let partner = review.highlight.partner {
            let myName = appState.me?.name ?? L10n.t("common.you")
            lines.append("✨ \(myName): \(mine.text)")
            lines.append("✨ \(appState.partnerName): \(partner.text)")
        }
        let text = lines.joined(separator: "\n")
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: text)
                sharedToChat = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharingToChat = false
        }
    }

    // MARK: Loading & actions

    private func load(quietly: Bool = false) async {
        guard let api = appState.api, let week = selectedWeek else { return }
        if !quietly {
            loading = review == nil
            failed = false
        }
        do {
            let loaded = try await api.weekReview(week: week)
            review = loaded
            // The read receipt does NOT fire here (B-21): opening is not
            // reading. It fires from the end-of-review sentinel instead.
        } catch {
            if !quietly {
                failed = review == nil
            }
        }
        loading = false
    }

    private func submitHighlight(_ week: String) async {
        let text = highlightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = appState.api, !text.isEmpty else { return }
        sendingHighlight = true
        defer { sendingHighlight = false }
        do {
            let updated = try await api.setWeekHighlight(week: week, text: text,
                                                         photoId: highlightPhotoId)
            review = updated
            highlightText = ""
            highlightPhotoId = nil
            SoundEngine.shared.play(.chime)
            Haptics.shared.success()
            if updated.highlight.bothShared {
                // R1-D: the both-shared moment blooms in the Lichtschein.
                AppCue.fanfareMedium.play()
                LichtscheinCenter.shared.fire()
            }
        } catch {
            appState.handleAPIError(error)
        }
    }
}

// MARK: - Week highlight photo picker

/// Grid of THIS week's photos to attach one to a highlight. Uses local
/// dateKeys for the week filter — the same wall clock the couple lives in.
private struct WeekHighlightPhotoPicker: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let week: String
    let onPick: (String) -> Void

    @State private var photos: [Photo] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                content
            }
            .navigationTitle(L10n.t("weekreview.highlight.photoPicker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private var weekPhotos: [Photo] {
        let keys = Set(WeekReviewLogic.dateKeys(ofWeek: week))
        return photos.filter { keys.contains(SharedDates.todayKey($0.createdAt)) }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                LazyVGrid(columns: pickerColumns, spacing: 6) {
                    ForEach(0..<6, id: \.self) { _ in
                        GlassSkeleton(kind: .tile(height: 110))
                    }
                }
                .padding(Space.l)
            }
        } else if failed {
            EmptyStateView(systemImage: "antenna.radiowaves.left.and.right.slash",
                           title: L10n.t("weekreview.error.title"),
                           subtitle: L10n.t("weekreview.error.subtitle"),
                           actionTitle: L10n.t("common.retry"),
                           action: { Task { await load() } })
        } else if weekPhotos.isEmpty {
            EmptyStateView(systemImage: "camera",
                           title: L10n.t("weekreview.highlight.photoPicker.empty.title"),
                           subtitle: L10n.t("weekreview.highlight.photoPicker.empty.subtitle"))
        } else {
            ScrollView {
                LazyVGrid(columns: pickerColumns, spacing: 6) {
                    ForEach(weekPhotos) { photo in
                        pickerCell(photo)
                    }
                }
                .padding(Space.l)
            }
        }
    }

    private var pickerColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
    }

    private func pickerCell(_ photo: Photo) -> some View {
        Button {
            Haptics.shared.tap()
            onPick(photo.id)
            dismiss()
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    AuthenticatedAsyncImage(api: appState.api,
                                            path: photo.thumbUrl ?? photo.url,
                                            maxPixelSize: 512) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            GlassSkeleton(kind: .tile(height: 130))
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        guard let api = appState.api else { return }
        failed = false
        do {
            photos = try await api.photos().sorted { $0.createdAt > $1.createdAt }
        } catch {
            failed = true
        }
        loading = false
    }
}
