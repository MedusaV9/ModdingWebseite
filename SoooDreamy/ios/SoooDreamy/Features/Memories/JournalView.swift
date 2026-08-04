import SwiftUI

/// „Unser Tagebuch" — the history of past daily questions with both answers.
struct JournalView: View {
    @Environment(AppState.self) private var appState

    @State private var entries: [DailyEntry] = []
    @State private var loading = true
    @State private var searchQuery = ""

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("memories.journal.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEntries() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LoadingView()
        } else if entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "📖",
                           title: L10n.t("memories.journal.empty.title"),
                           subtitle: L10n.t("memories.journal.empty.subtitle"))
            Spacer()
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                searchField
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
            .padding(LayoutMetrics.s(16))
            .padding(.bottom, LayoutMetrics.s(12))
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

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField(L10n.t("memories.journal.searchPlaceholder"),
                      text: $searchQuery,
                      prompt: Text(L10n.t("memories.journal.searchPlaceholder"))
                          .foregroundStyle(Theme.textTertiary))
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.search)
            if !searchQuery.isEmpty {
                Button {
                    Haptics.shared.tap()
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.scaled(16, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("common.delete"))
            }
        }
    }

    private var searchEmptyState: some View {
        EmptyStateView(emoji: "🔍",
                       title: L10n.t("memories.journal.searchNoResults.title"),
                       subtitle: L10n.t("memories.journal.searchNoResults.subtitle",
                                        ["query": searchText]))
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date)
    }

    private func monthHeader(_ title: String) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 1)
        }
        .padding(.top, LayoutMetrics.s(4))
    }

    // MARK: Entry card

    private func entryCard(_ entry: DailyEntry) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(prettyDate(entry.dateKey))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textTertiary)
            Text(questionText(entry))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            answers(entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
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
            VStack(alignment: .leading, spacing: 8) {
                answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                             text: entry.myAnswer ?? "", tint: Theme.purple)
                answerBubble(name: appState.partnerName,
                             text: entry.partnerAnswer ?? "", tint: Theme.pink)
            }
        } else if let mine = entry.myAnswer {
            VStack(alignment: .leading, spacing: 8) {
                answerBubble(name: appState.me?.name ?? L10n.t("common.you"),
                             text: mine, tint: Theme.purple)
                Text(L10n.t("memories.journal.waiting", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            // Either only the partner answered (answers stay hidden until both did)
            // or nobody answered — a neutral hint covers both.
            Text(L10n.t("memories.journal.noAnswer"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func answerBubble(name: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
        )
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.dateStyle = .long
        return formatter.string(from: date)
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
