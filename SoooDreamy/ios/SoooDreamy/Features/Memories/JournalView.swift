import SwiftUI

/// „Unser Tagebuch" — the history of past daily questions with both answers.
struct JournalView: View {
    @Environment(AppState.self) private var appState

    @State private var entries: [DailyEntry] = []
    @State private var loading = true

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
            LazyVStack(spacing: 14) {
                ForEach(entries, id: \.dateKey) { entry in
                    entryCard(entry)
                }
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .refreshable { await loadEntries() }
    }

    // MARK: Entry card

    private func entryCard(_ entry: DailyEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
