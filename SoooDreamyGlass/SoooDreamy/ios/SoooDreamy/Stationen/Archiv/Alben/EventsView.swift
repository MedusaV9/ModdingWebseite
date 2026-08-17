import SwiftUI
import Combine

/// Countdowns & special moments — events with days-until chips and Live Activity countdowns.
struct EventsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var editorTarget: EditorTarget?
    @State private var activityRefresh = 0
    @State private var filter: EventFilter = .all

    private struct EditorTarget: Identifiable {
        let id: String
        let event: EventItem?
    }

    /// Upcoming = today or later (incl. yearly repeats); past = already over.
    private enum EventFilter: String, CaseIterable, Identifiable {
        case all, upcoming, past
        var id: String { rawValue }
        var labelKey: String { "memories.events.filter.\(rawValue)" }
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
                        .foregroundStyle(coupleTint.blend)
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

    private var filteredEvents: [EventEntry] {
        sortedEvents.filter { matches($0.days) }
    }

    /// Unparseable dates (days == nil) count as past, matching their sort position.
    private func matches(_ days: Int?) -> Bool {
        switch filter {
        case .all: return true
        case .upcoming: return (days ?? -1) >= 0
        case .past: return (days ?? -1) < 0
        }
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
        VStack(spacing: Space.l) {
            Spacer()
            EmptyStateView(systemImage: "calendar",
                           title: L10n.t("memories.events.empty.title"),
                           subtitle: L10n.t("memories.events.empty.subtitle"))
            Button(L10n.t("memories.events.add")) {
                Haptics.shared.tap()
                editorTarget = EditorTarget(id: "new", event: nil)
            }
            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            if let suggestion = monthiversarySuggestion {
                monthiversaryButton(suggestion)
                    .padding(.horizontal, Space.l)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var eventList: some View {
        List {
            filterRow
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: Space.s, leading: Space.l,
                                          bottom: Space.xs, trailing: Space.l))
            // The suggestion is always an upcoming event — hide it under "past".
            if filter != .past, let suggestion = monthiversarySuggestion {
                monthiversaryButton(suggestion)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.l,
                                              bottom: Space.xs, trailing: Space.l))
            }
            if filteredEvents.isEmpty {
                filteredEmptyRow
            }
            ForEach(filteredEvents) { entry in
                row(entry.event, days: entry.days)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await appState.refreshEvents() }
    }

    // MARK: Filter (all / upcoming / past)

    private var filterRow: some View {
        HStack(spacing: Space.s) {
            ForEach(EventFilter.allCases) { f in
                filterChip(f)
            }
            Spacer()
        }
    }

    /// Paper register tabs — the calendar's index dividers.
    private func filterChip(_ f: EventFilter) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) { filter = f }
        } label: {
            PapierRegisterTab(title: L10n.t(f.labelKey), selected: filter == f)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(filter == f ? [.isSelected] : [])
    }

    /// Hint when the chosen filter has nothing to show (but the list isn't empty).
    @ViewBuilder
    private var filteredEmptyRow: some View {
        if filter != .all {
            Text(L10n.t(filter == .upcoming
                        ? "memories.events.emptyUpcoming"
                        : "memories.events.emptyPast"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.xl)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
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
            HStack(spacing: Space.m) {
                Image(icon: .sendLove)
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(coupleTint.blend)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(L10n.t("memories.events.addMonthiversary"))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("memories.events.monthiversarySub",
                                ["n": String(suggestion.months), "date": prettyDate(suggestion.dateKey)]))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(coupleTint.blend)
            }
            .nightCard()
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
        .listRowInsets(EdgeInsets(top: Space.xs, leading: Space.l,
                                  bottom: Space.xs, trailing: Space.l))
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

    /// A calendar card in the night room: emoji on a matte night well,
    /// the date line in rounded caps — countdown chips stay pills.
    private func rowContent(_ event: EventItem, days: Int?) -> some View {
        HStack(spacing: Space.l) {
            Text(event.emoji)
                .font(.system(.title))
                .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Papier.nachtInnenFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                        )
                )
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(event.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
                HStack(spacing: Space.xs) {
                    Text(prettyDate(event.date))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                    if event.repeatsYearly {
                        PillTag(text: L10n.t("memories.events.yearlyBadge"),
                                tint: Theme.blue)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Space.s) {
                countdownChip(days: days)
                liveActivityButton(event, days: days)
            }
        }
        .nightCard()
    }

    @ViewBuilder
    private func countdownChip(days: Int?) -> some View {
        if let days {
            // ONE pill for every countdown state (not an if-ladder of pills):
            // the chip keeps its view identity across day changes, so the
            // rolling-digit transition can actually run (S3, Flighty-style)
            // when a date edit or the midnight rollover moves the number.
            PillTag(text: countdownText(days: days), tint: countdownTint(days: days))
                .contentTransition(.numericText(countsDown: true))
                .animation(Theme.Motion.settle, value: days)
        }
    }

    private func countdownText(days: Int) -> String {
        switch days {
        case 0: return L10n.t("memories.countdown.today")
        case 1: return L10n.t("memories.countdown.tomorrow")
        case 2...: return L10n.t("memories.countdown.inDays", ["n": String(days)])
        default: return L10n.t("memories.countdown.daysAgo", ["n": String(-days)])
        }
    }

    /// Pill WASH tints on the night card (the label stays `textPrimary`):
    /// today wears the couple color, upcoming lamplight gold, past fades.
    private func countdownTint(days: Int) -> Color {
        switch days {
        case 0: return coupleTint.blend
        case 1...: return Theme.gold
        default: return Nacht.tertiaer
        }
    }

    @ViewBuilder
    private func liveActivityButton(_ event: EventItem, days: Int?) -> some View {
        let running = isRunningActivity(event)
        if CountdownActivityController.isSupported && (running || (days ?? -1) > 0) {
            Button {
                toggleActivity(event)
            } label: {
                // On the night card the label is LIGHT: energyRed (6.8:1
                // pinned) for stop, lamplight gold for start — wax red and
                // the paper ink were paper accents and fail on nachtkarton.
                HStack(spacing: Space.xs) {
                    Image(systemName: running ? "stop.circle.fill" : "timer")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                    Text(L10n.t(running ? "memories.events.liveStop" : "memories.events.liveStart"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(running ? Theme.energyRed : Licht.lampengold)
                .padding(.vertical, Space.xs)
                .padding(.horizontal, Space.s)
                .background(
                    Capsule().fill((running ? Theme.energyRed : Licht.lampengold).opacity(0.12))
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
        return AppFormatters.date(date, language: L10n.lang, dateStyle: .long)
    }
}

// MARK: - Editor sheet

private struct EventEditorSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

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
                    VStack(alignment: .leading, spacing: Space.l) {
                        titleField
                        emojiSection
                        dateSection
                        yearlyToggle
                        saveButton
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t(event == nil ? "memories.events.add" : "memories.events.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
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
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.t("memories.events.emoji"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            EmojiPickerGrid(emojis: Self.emojis, selection: $emoji)
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.t("memories.events.date"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            // The calendar sits on the night card — dark scheme so the
            // system picker writes in light ink, couple blend as tint.
            DatePicker(L10n.t("memories.events.date"),
                       selection: $date,
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(coupleTint.blend)
                .environment(\.colorScheme, .dark)
                // System pickers follow the DEVICE locale, the app
                // speaks ITS language (Amt seam, Re-Eval Runde 2).
                .environment(\.locale, Locale(identifier: L10n.lang))
                .nightCard(padding: .compact, grain: false)
        }
    }

    private var yearlyToggle: some View {
        Toggle(isOn: $repeatsYearly) {
            Text(L10n.t("memories.events.yearly"))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
        }
        .tint(coupleTint.blend)
        .nightCard()
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            if saving {
                BusySpinner()
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
                    // Contract v11: PATCH carries ONLY the fields that
                    // actually changed (the editor used to resend the whole
                    // old snapshot, silently overwriting concurrent edits),
                    // guarded by the freshest known `rev`.
                    let newTitle = trimmed == event.title ? nil : trimmed
                    let newEmoji = emoji == event.emoji ? nil : emoji
                    let newDate = dateKey == event.date ? nil : dateKey
                    let newYearly = repeatsYearly == event.repeatsYearly
                        ? nil : repeatsYearly
                    if newTitle != nil || newEmoji != nil || newDate != nil
                        || newYearly != nil {
                        // The list may hold a fresher rev than this sheet's
                        // snapshot (conflict reload) — guard with the newest.
                        let rev = appState.events
                            .first(where: { $0.id == event.id })?.rev ?? event.rev
                        _ = try await api.updateEvent(id: event.id, title: newTitle,
                                                      emoji: newEmoji, date: newDate,
                                                      repeatsYearly: newYearly,
                                                      ifRev: rev)
                    }
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
                handleSaveError(error)
            }
            saving = false
        }
    }

    /// 409 `conflict {current}`: the event changed on the other device while
    /// this editor was open. The server's version lands in the list, MY
    /// values stay right here in the open editor, and an honest hint says
    /// what happened — saving again is then a conscious "mine wins" against
    /// the fresh rev. No silent overwrite in either direction.
    private func handleSaveError(_ error: Error) {
        guard (error as? APIError)?.serverCode == "conflict" else {
            appState.handleAPIError(error)
            return
        }
        if let current = (error as? APIError)?.details?
            .currentResource(EventItem.self),
           let idx = appState.events.firstIndex(where: { $0.id == current.id }) {
            appState.events[idx] = current
            appState.showToast(L10n.t("memories.events.conflict"), style: .info)
        } else {
            Task {
                await appState.refreshEvents()
                appState.showToast(L10n.t("memories.events.conflict"), style: .info)
            }
        }
        Haptics.shared.warning()
    }

    private static func dateKey(_ date: Date) -> String {
        let comps = SharedDates.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
