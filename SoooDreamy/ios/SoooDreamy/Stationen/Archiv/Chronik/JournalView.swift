import SwiftUI

/// „Unser Tagebuch" — the history of past daily questions with both
/// answers, read as letter-paper diary pages: printed question, the
/// couple's answers in serif ink, each signed with the author's ink edge.
struct JournalView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var entries: [DailyEntry] = []
    @State private var loading = true
    @State private var searchQuery = ""

    /// Each partner's own chosen color as READABLE ink on paper — the
    /// `inkOnPaper` ladder guarantees ≥ 4.5:1 on every paper tone.
    private var myInk: Color {
        appState.me.map { Color(hex: CouplePaletteRules.inkOnPaper($0.color)) }
            ?? coupleTint.tintePrimary
    }

    private var partnerInk: Color {
        appState.partner.map { Color(hex: CouplePaletteRules.inkOnPaper($0.color)) }
            ?? coupleTint.tinteSecondary
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("memories.journal.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Native search (system field in the navigation bar): dictation,
        // cancel button, focus handling and VoiceOver come from the system;
        // the filter logic below is unchanged.
        .searchable(text: $searchQuery,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: L10n.t("memories.journal.searchPlaceholder"))
        .task { await loadEntries() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                VStack(spacing: Space.l) {
                    ForEach(0..<3, id: \.self) { _ in
                        PaperSkeleton(kind: .card(height: 150), onNacht: true)
                    }
                }
                .padding(Space.l)
            }
        } else if entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(systemImage: "book.closed",
                           title: L10n.t("memories.journal.empty.title"),
                           subtitle: L10n.t("memories.journal.empty.subtitle"),
                           actionTitle: L10n.t("memories.journal.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               appState.activeTab = .home
                           })
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.l) {
                if isFiltering && monthGroups.isEmpty {
                    searchEmptyState
                }
                ForEach(monthGroups) { group in
                    monthHeader(group.title)
                    ForEach(group.entries, id: \.dateKey) { entry in
                        entryCard(entry)
                    }
                }
            }
            .padding(Space.l)
            .padding(.bottom, Space.m)
        }
        .refreshable { await loadEntries() }
    }

    // MARK: Search

    /// Trimmed query — filtering only kicks in with a non-empty search.
    private var searchText: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        !searchText.isEmpty
    }

    /// Entries matching the query in the question text or either visible
    /// answer (case-insensitive).
    private var filteredEntries: [DailyEntry] {
        guard isFiltering else { return entries }
        let query = searchText
        return entries.filter { entry in
            questionText(entry).localizedCaseInsensitiveContains(query)
                || (entry.myAnswer?.localizedCaseInsensitiveContains(query) ?? false)
                || (entry.partnerAnswer?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var searchEmptyState: some View {
        EmptyStateView(systemImage: "magnifyingglass",
                       title: L10n.t("memories.journal.searchNoResults.title"),
                       subtitle: L10n.t("memories.journal.searchNoResults.subtitle",
                                        ["query": searchText]),
                       actionTitle: L10n.t("common.clearSearch"),
                       action: {
                           Haptics.shared.tap()
                           searchQuery = ""
                       })
    }

    // MARK: Month groups

    private struct MonthGroup: Identifiable {
        let id: String      // "YYYY-MM"
        let title: String
        var entries: [DailyEntry]
    }

    /// Filtered entries grouped by calendar month, preserving the API's
    /// newest-first order (dateKeys sort chronologically as strings).
    private var monthGroups: [MonthGroup] {
        var groups: [MonthGroup] = []
        for entry in filteredEntries {
            let key = String(entry.dateKey.prefix(7))
            if let last = groups.indices.last, groups[last].id == key {
                groups[last].entries.append(entry)
            } else {
                groups.append(MonthGroup(id: key, title: monthTitle(key), entries: [entry]))
            }
        }
        return groups
    }

    /// "2026-08" → "August 2026" in the app language.
    private func monthTitle(_ monthKey: String) -> String {
        guard let date = SharedDates.parse(monthKey + "-01") else { return monthKey }
        return AppFormatters.monthYear(date, language: L10n.lang)
    }

    private func monthHeader(_ title: String) -> some View {
        HStack(spacing: Space.m) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            Rectangle()
                .fill(Theme.hairline)
                .frame(height: Theme.hairlineWidth)
        }
        .padding(.top, Space.xs)
    }

    // MARK: Entry card (diary page)

    private func entryCard(_ entry: DailyEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            // The postmark date line — the app's one small-caps role,
            // serif on paper only.
            Text(prettyDate(entry.dateKey))
                .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Tinte.tertiaer)
            // The question is PRINTED (the app speaks — rounded ink).
            Text(questionText(entry))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
            answers(entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .contextMenu {
            if entry.myAnswer != nil {
                Button {
                    shareToChat(entry)
                } label: {
                    Label(L10n.t("memories.journal.share"), systemImage: "paperplane.fill")
                }
            }
        }
    }

    /// Posts a past daily question with the visible answers into the couple
    /// chat (the partner's answer is only included once both answered).
    private func shareToChat(_ entry: DailyEntry) {
        guard let api = appState.api else { return }
        Haptics.shared.tap()
        var lines = [L10n.t("memories.journal.shareHeader", ["date": prettyDate(entry.dateKey)])]
        let question = questionText(entry)
        if !question.isEmpty {
            lines.append(question)
        }
        if let mine = entry.myAnswer {
            lines.append("\(appState.me?.name ?? L10n.t("common.you")): \(mine)")
        }
        if let partner = entry.partnerAnswer {
            lines.append("\(appState.partnerName): \(partner)")
        }
        let text = lines.joined(separator: "\n")
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                Haptics.shared.success()
                SoundEngine.shared.play(.pop)
                appState.showToast(L10n.t("memories.journal.shareSent"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    @ViewBuilder
    private func answers(_ entry: DailyEntry) -> some View {
        if entry.bothAnswered {
            VStack(alignment: .leading, spacing: Space.s) {
                answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                             text: entry.myAnswer ?? "", ink: myInk)
                answerBubble(name: appState.partnerName,
                             text: entry.partnerAnswer ?? "", ink: partnerInk)
            }
        } else if let mine = entry.myAnswer {
            VStack(alignment: .leading, spacing: Space.s) {
                answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                             text: mine, ink: myInk)
                Text(L10n.t("memories.journal.waiting", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            }
        } else {
            // Either only the partner answered (answers stay hidden until both did)
            // or nobody answered — a neutral hint covers both.
            Text(L10n.t("memories.journal.noAnswer"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
        }
    }

    /// One answer on the diary page: the couple's own words in the serif
    /// reading voice (`Typo.brief` — journal full text), body always in
    /// dark ink; authorship rides on the name label and the 4-pt ink edge
    /// (doubly coded, readable for color-blind partners via the name).
    private func answerBubble(name: String, text: String, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(ink)
            Text(text)
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.papier,
                                                             padding: Space.m),
                             style: .continuous)
                .fill(Papier.innenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.papier,
                                                                     padding: Space.m),
                                     style: .continuous)
                        .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
        )
        .overlay(alignment: .leading) {
            // The author's ink edge (Tintenkante).
            UnevenRoundedRectangle(topLeadingRadius: Radius.papier,
                                   bottomLeadingRadius: Radius.papier,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: 0,
                                   style: .continuous)
                .fill(ink)
                .frame(width: Papier.tintenkante)
                .accessibilityHidden(true)
        }
    }

    // MARK: Helpers

    private func questionText(_ entry: DailyEntry) -> String {
        var question: DailyQuestion?
        if let qid = entry.questionId {
            question = ContentPack.dailyQuestions.first { $0.id == qid }
        }
        if question == nil, let couple = appState.couple {
            question = ContentPack.dailyQuestion(dateKey: entry.dateKey, coupleId: couple.id)
        }
        guard let question else { return "" }
        return question.text.filled(partner: appState.partnerName, lang: L10n.lang)
    }

    private func prettyDate(_ key: String) -> String {
        guard let date = SharedDates.parse(key) else { return key }
        return AppFormatters.date(date, language: L10n.lang, dateStyle: .long)
    }

    private func loadEntries() async {
        guard let api = appState.api else { return }
        do {
            entries = try await api.dailyHistory()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }
}
