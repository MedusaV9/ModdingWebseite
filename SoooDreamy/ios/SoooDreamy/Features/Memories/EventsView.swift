import SwiftUI
import Combine

/// Countdowns & special moments — events with days-until chips and Live Activity countdowns.
struct EventsView: View {
    @Environment(AppState.self) private var appState

    @State private var editorTarget: EditorTarget?
    @State private var activityRefresh = 0

    private struct EditorTarget: Identifiable {
        let id: String
        let event: EventItem?
    }

    private struct EventEntry: Identifiable {
        let event: EventItem
        let days: Int?
        var id: String { event.id }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("memories.events.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.shared.tap()
                    editorTarget = EditorTarget(id: "new", event: nil)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.pink)
                }
                .accessibilityLabel(L10n.t("memories.events.add"))
            }
        }
        .task { await appState.refreshEvents() }
        .sheet(item: $editorTarget) { target in
            EventEditorSheet(event: target.event)
        }
    }

    private var sortedEvents: [EventEntry] {
        appState.events
            .map { EventEntry(event: $0, days: SharedDates.daysUntil($0.date, repeatsYearly: $0.repeatsYearly)) }
            .sorted { lhs, rhs in
                sortRank(lhs.days) < sortRank(rhs.days)
            }
    }

    /// Upcoming first (soonest at top), past events afterwards (most recent first).
    private func sortRank(_ days: Int?) -> Int {
        guard let days else { return Int.max }
        return days >= 0 ? days : 100_000 - days
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if appState.events.isEmpty {
            emptyState
        } else {
            eventList
        }
    }

    private var emptyState: some View {
        VStack(spacing: LayoutMetrics.s(18)) {
            Spacer()
            EmptyStateView(emoji: "🗓️",
                           title: L10n.t("memories.events.empty.title"),
                           subtitle: L10n.t("memories.events.empty.subtitle"))
            Button(L10n.t("memories.events.add")) {
                Haptics.shared.tap()
                editorTarget = EditorTarget(id: "new", event: nil)
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            if let suggestion = monthiversarySuggestion {
                monthiversaryButton(suggestion)
                    .padding(.horizontal, LayoutMetrics.s(16))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var eventList: some View {
        List {
            if let suggestion = monthiversarySuggestion {
                monthiversaryButton(suggestion)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            ForEach(sortedEvents) { entry in
                row(entry.event, days: entry.days)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await appState.refreshEvents() }
    }

    // MARK: Monthiversary helper

    private struct MonthiversarySuggestion {
        let months: Int
        let dateKey: String
        var title: String {
            L10n.t("memories.events.monthiversaryTitle", ["n": String(months)])
        }
    }

    /// The next monthiversary (anniversary day-of-month, ≥ today) — nil while
    /// no anniversary is set, or once the suggested event already exists.
    private var monthiversarySuggestion: MonthiversarySuggestion? {
        guard let key = appState.couple?.anniversary,
              let anniversary = SharedDates.parse(key) else { return nil }
        let calendar = SharedDates.calendar
        let annDay = calendar.startOfDay(for: anniversary)
        let today = calendar.startOfDay(for: Date())
        var months = max(calendar.dateComponents([.month], from: annDay, to: today).month ?? 0, 1)
        var candidate = calendar.date(byAdding: .month, value: months, to: annDay)
        while let c = candidate, calendar.startOfDay(for: c) < today {
            months += 1
            candidate = calendar.date(byAdding: .month, value: months, to: annDay)
        }
        guard let date = candidate else { return nil }
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let dateKey = String(format: "%04d-%02d-%02d",
                             comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
        let suggestion = MonthiversarySuggestion(months: months, dateKey: dateKey)
        guard !appState.events.contains(where: { $0.date == dateKey && $0.title == suggestion.title }) else {
            return nil
        }
        return suggestion
    }

    private func monthiversaryButton(_ suggestion: MonthiversarySuggestion) -> some View {
        Button {
            addMonthiversary(suggestion)
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                Text("💞")
                    .font(.scaled(26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("memories.events.addMonthiversary"))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.t("memories.events.monthiversarySub",
                                ["n": String(suggestion.months), "date": prettyDate(suggestion.dateKey)]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.scaled(20))
                    .foregroundStyle(Theme.pink)
            }
            .glassCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func addMonthiversary(_ suggestion: MonthiversarySuggestion) {
        guard let api = appState.api else { return }
        guard !appState.events.contains(where: { $0.date == suggestion.dateKey && $0.title == suggestion.title }) else {
            appState.showToast(L10n.t("memories.events.monthiversaryExists"), style: .info)
            return
        }
        Haptics.shared.tap()
        Task {
            do {
                _ = try await api.addEvent(title: suggestion.title, emoji: "💞",
                                           date: suggestion.dateKey, repeatsYearly: false)
                await appState.refreshEvents()
                appState.updateWidgetSnapshot()
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.events.saved"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    // MARK: Row

    private func row(_ event: EventItem, days: Int?) -> some View {
        Button {
            Haptics.shared.tap()
            editorTarget = EditorTarget(id: event.id, event: event)
        } label: {
            rowContent(event, days: days)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteEvent(event)
            } label: {
                Label(L10n.t("common.delete"), systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                shareToChat(event, days: days)
            } label: {
                Label(L10n.t("memories.events.share"), systemImage: "paperplane.fill")
            }
        }
    }

    private func rowContent(_ event: EventItem, days: Int?) -> some View {
        HStack(spacing: LayoutMetrics.s(14)) {
            Text(event.emoji)
                .font(.scaled(30))
                .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(prettyDate(event.date))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    if event.repeatsYearly {
                        PillTag(text: L10n.t("memories.events.yearlyBadge"), tint: Theme.indigo)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                countdownChip(days: days)
                liveActivityButton(event, days: days)
            }
        }
        .glassCard(padding: 14)
    }

    @ViewBuilder
    private func countdownChip(days: Int?) -> some View {
        if let days {
            if days == 0 {
                PillTag(text: L10n.t("memories.countdown.today"), tint: Theme.pink)
            } else if days == 1 {
                PillTag(text: L10n.t("memories.countdown.tomorrow"), tint: Theme.gold)
            } else if days > 1 {
                PillTag(text: L10n.t("memories.countdown.inDays", ["n": String(days)]), tint: Theme.gold)
            } else {
                PillTag(text: L10n.t("memories.countdown.daysAgo", ["n": String(-days)]),
                        tint: Color.gray)
            }
        }
    }

    @ViewBuilder
    private func liveActivityButton(_ event: EventItem, days: Int?) -> some View {
        let running = isRunningActivity(event)
        if CountdownActivityController.isSupported && (running || (days ?? -1) > 0) {
            Button {
                toggleActivity(event)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: running ? "stop.circle.fill" : "timer")
                        .font(.scaled(11, weight: .bold))
                    Text(L10n.t(running ? "memories.events.liveStop" : "memories.events.liveStart"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(running ? Color(hex: "F87171") : Theme.mint)
                .padding(.vertical, 4)
                .padding(.horizontal, 9)
                .background(
                    Capsule().fill((running ? Color(hex: "F87171") : Theme.mint).opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Live Activity

    private func isRunningActivity(_ event: EventItem) -> Bool {
        _ = activityRefresh
        return CountdownActivityController.activeEventTitle == event.title
    }

    private func toggleActivity(_ event: EventItem) {
        Haptics.shared.tap()
        if isRunningActivity(event) {
            CountdownActivityController.stopAll()
            appState.showToast(L10n.t("memories.events.liveStopped"), style: .info)
        } else if CountdownActivityController.start(for: event, partnerName: appState.partner?.name) {
            SoundEngine.shared.play(.chime)
            appState.showToast(L10n.t("memories.events.liveStarted"), style: .success)
        } else {
            appState.showToast(L10n.t("memories.events.liveFailed"), style: .error)
        }
        activityRefresh += 1
    }

    // MARK: Actions

    /// Posts a pretty two-line countdown message into the couple chat.
    private func shareToChat(_ event: EventItem, days: Int?) {
        guard let api = appState.api else { return }
        let text = shareText(event, days: days)
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                Haptics.shared.success()
                SoundEngine.shared.play(.pop)
                appState.showToast(L10n.t("memories.events.shareSent"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func shareText(_ event: EventItem, days: Int?) -> String {
        let header = L10n.t("memories.events.shareHeader",
                            ["emoji": event.emoji, "title": event.title])
        let date = prettyDate(event.date)
        let line: String
        switch days {
        case .some(0):
            line = L10n.t("memories.events.shareToday", ["date": date])
        case .some(1):
            line = L10n.t("memories.events.shareOneDay", ["date": date])
        case .some(let n) where n > 1:
            line = L10n.t("memories.events.shareInDays", ["n": String(n), "date": date])
        default:
            // Past non-repeating (or unparseable) events get a plain date line.
            line = date
        }
        return header + "\n" + line
    }

    private func deleteEvent(_ event: EventItem) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteEvent(id: event.id)
                if isRunningActivity(event) {
                    CountdownActivityController.stop(matchingTitle: event.title)
                    activityRefresh += 1
                }
                await appState.refreshEvents()
                appState.updateWidgetSnapshot()
                appState.showToast(L10n.t("memories.events.deleted"), style: .info)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func prettyDate(_ key: String) -> String {
        guard let date = SharedDates.parse(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isGerman ? "de_DE" : "en_US")
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }
}

// MARK: - Editor sheet

private struct EventEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let event: EventItem?

    @State private var title: String
    @State private var emoji: String
    @State private var date: Date
    @State private var repeatsYearly: Bool
    @State private var saving = false

    private static let emojis = [
        "🎂", "💍", "✈️", "🎄", "🎉", "💞", "🌙", "🎓",
        "🏝️", "🎁", "🥂", "🎃", "🐣", "❤️", "🗓️", "⭐️",
        "🎆", "🏡"
    ]

    init(event: EventItem?) {
        self.event = event
        _title = State(initialValue: event?.title ?? "")
        _emoji = State(initialValue: event?.emoji ?? "🎉")
        _date = State(initialValue: SharedDates.parse(event?.date) ?? Date())
        _repeatsYearly = State(initialValue: event?.repeatsYearly ?? false)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        titleField
                        emojiSection
                        dateSection
                        yearlyToggle
                        saveButton
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t(event == nil ? "memories.events.add" : "memories.events.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(Theme.pink)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var titleField: some View {
        TextField(L10n.t("memories.events.titleField"), text: $title)
            .textFieldStyle(DreamyFieldStyle())
            .submitLabel(.done)
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("memories.events.emoji"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            EmojiPickerGrid(emojis: Self.emojis, selection: $emoji)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("memories.events.date"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            DatePicker(L10n.t("memories.events.date"),
                       selection: $date,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(Theme.pink)
                .environment(\.colorScheme, .dark)
                .glassCard(padding: 8)
        }
    }

    private var yearlyToggle: some View {
        Toggle(isOn: $repeatsYearly) {
            Text(L10n.t("memories.events.yearly"))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.pink)
        .glassCard(padding: 14)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            if saving {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
            } else {
                Text(L10n.t("common.save"))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        guard let api = appState.api, !saving else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        saving = true
        let dateKey = Self.dateKey(date)
        Task {
            do {
                if let event {
                    _ = try await api.updateEvent(id: event.id, title: trimmed, emoji: emoji,
                                                  date: dateKey, repeatsYearly: repeatsYearly)
                } else {
                    _ = try await api.addEvent(title: trimmed, emoji: emoji,
                                               date: dateKey, repeatsYearly: repeatsYearly)
                }
                await appState.refreshEvents()
                appState.updateWidgetSnapshot()
                Haptics.shared.success()
                SoundEngine.shared.play(.chime)
                appState.showToast(L10n.t("memories.events.saved"), style: .success)
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            saving = false
        }
    }

    private static func dateKey(_ date: Date) -> String {
        let comps = SharedDates.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
