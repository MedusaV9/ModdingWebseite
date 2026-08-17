import SwiftUI
import Combine

/// "Unsere Woche": a 7-day board where both partners mark their
/// availability and plan shared slots (phone date, movie night, …).
/// Recurring slots repeat weekly; days where both have time sparkle.
struct WeekplanView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var plan: WeekplanResponse?
    @State private var loading = true
    @State private var loadFailed = false
    @State private var showCompose = false
    /// Pre-filled day for the compose sheet when tapping "+" on a day card.
    @State private var composeDateKey: String?
    /// Film→Wochenplan: the freshest unplanned movie_match.
    @State private var movieSuggestion: MovieNight.Match?
    @State private var planningMovie = false
    /// Locally dismissed movie_match event ids (comma-joined, survives restarts).
    @AppStorage("weekplan.dismissedMovieMatches") private var dismissedMatchesRaw = ""

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    Text(L10n.t("weekplan.subtitle"))
                        .font(Typo.label)
                        .foregroundStyle(Theme.textSecondary)
                    if let suggestion = movieSuggestion {
                        movieMatchBanner(suggestion)
                    }
                    Button {
                        Haptics.shared.tap()
                        composeDateKey = nil
                        showCompose = true
                    } label: {
                        Label(L10n.t("weekplan.newSlot"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if let plan {
                        ForEach(plan.days, id: \.dateKey) { day in
                            WeekplanDayCard(day: day,
                                            onSetAvailability: { setAvailability(day, status: $0) },
                                            onAddSlot: {
                                                composeDateKey = day.dateKey
                                                showCompose = true
                                            },
                                            onDeleteSlot: { deleteSlot($0) })
                        }
                        weeklySlots(plan)
                    } else if loading {
                        // The board arrives in the silhouette it will occupy.
                        ForEach(0..<3, id: \.self) { _ in
                            PaperSkeleton(kind: .card(height: 120))
                        }
                    } else if loadFailed {
                        RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                            Task { await reload() }
                        }
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("weekplan.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .weekplanAvailability, .weekplanSlotAdded, .weekplanSlotUpdated, .weekplanSlotDeleted,
                 .appEvent:
                Task { await reload() }
            default:
                break
            }
        }
        .sheet(isPresented: $showCompose) {
            WeekplanSlotComposeSheet(initialDateKey: composeDateKey) {
                Task { await reload() }
            }
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = plan == nil
        do {
            let response = try await api.weekplan()
            plan = response
            loadFailed = false
            loading = false
            await refreshMovieSuggestion(plan: response)
        } catch {
            // A failed primary load must not leave a wordless blank board —
            // the shared failed/offline notice offers an honest retry.
            loadFailed = plan == nil
            loading = false
        }
    }

    // MARK: Film → Wochenplan banner (EVAL-3.0 P0-3)

    private var dismissedMatchIds: Set<String> {
        Set(dismissedMatchesRaw.split(separator: ",").map(String.init))
    }

    /// Reads recent movie_match app events and suggests the newest one that
    /// is not dismissed and not already covered by a movie slot.
    private func refreshMovieSuggestion(plan: WeekplanResponse) async {
        guard let api = appState.api else { return }
        let events = (try? await api.appEvents(type: "movie_match", limit: 10)) ?? []
        let matches = events.map {
            MovieNight.Match(id: $0.id, title: $0.dataString("title"), createdAt: $0.createdAt)
        }
        let movieSlots = plan.slots.filter { $0.kind == "movie" }.map(\.createdAt)
        movieSuggestion = MovieNight.suggestion(matches: matches,
                                                movieSlotCreations: movieSlots,
                                                dismissedIds: dismissedMatchIds)
    }

    /// "Ihr habt ein Film-Match — Filmabend eintragen?" with a 1-tap slot.
    private func movieMatchBanner(_ suggestion: MovieNight.Match) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "popcorn.fill")
                    .font(.system(.title2, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.glut)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("weekplan.movieBanner.title"))
                        .font(.system(.subheadline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Papier.aufNacht)
                    Text(suggestion.title ?? L10n.t("weekplan.movieBanner.fallbackTitle"))
                        .font(Typo.caption)
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    dismissMovieSuggestion(suggestion)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                .buttonStyle(.plain)
            }
            Button {
                planMovieNight(suggestion)
            } label: {
                if planningMovie {
                    BusySpinner()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(L10n.t("weekplan.movieBanner.cta"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(planningMovie)
        }
        .nightCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .strokeBorder(coupleTint.blend.opacity(0.45), lineWidth: 1.5)
        )
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    /// 1-tap slot on the first day both have time (else next Saturday) —
    /// success only shows after the server confirmed the slot.
    private func planMovieNight(_ suggestion: MovieNight.Match) {
        guard let api = appState.api, !planningMovie else { return }
        planningMovie = true
        Haptics.shared.tap()
        Task {
            defer { planningMovie = false }
            do {
                let overlapDays = plan?.days.filter(\.overlap).map(\.dateKey) ?? []
                let dateKey = MovieNight.slotDateKey(overlapDateKeys: overlapDays)
                let title = suggestion.title ?? L10n.t("weekplan.movieBanner.fallbackTitle")
                _ = try await api.addWeekplanSlot(title: title, emoji: "🍿", kind: "movie",
                                                  dateKey: dateKey, weekday: nil, time: nil)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("weekplan.addedToast"), style: .success)
                withAnimation(Theme.Motion.settle) {
                    movieSuggestion = nil
                }
                await reload()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func dismissMovieSuggestion(_ suggestion: MovieNight.Match) {
        Haptics.shared.tap()
        var ids = dismissedMatchIds
        ids.insert(suggestion.id)
        // Cap the persisted list — old ids age out of the event log anyway.
        dismissedMatchesRaw = ids.suffix(30).joined(separator: ",")
        withAnimation(Theme.Motion.settle) {
            movieSuggestion = nil
        }
    }

    private func setAvailability(_ day: WeekplanDay, status: String?) {
        guard let api = appState.api else { return }
        Haptics.shared.tap()
        Task {
            do {
                let updated = try await api.setAvailability(dateKey: day.dateKey, status: status)
                if var current = plan,
                   let idx = current.days.firstIndex(where: { $0.dateKey == updated.dateKey }) {
                    current.days[idx] = updated
                    plan = current
                    if updated.overlap {
                        SoundEngine.shared.play(.sparkle)
                    }
                }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func deleteSlot(_ slot: WeekplanSlot) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteWeekplanSlot(id: slot.id)
                await reload()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// The recurring appointments ("every week") below the board.
    @ViewBuilder
    private func weeklySlots(_ plan: WeekplanResponse) -> some View {
        let weekly = plan.slots.filter { $0.weekday != nil }
        if !weekly.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(L10n.t("weekplan.slots") + " · " + L10n.t("weekplan.slot.weekly"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(weekly) { slot in
                    HStack(spacing: Space.m) {
                        Text(slot.emoji ?? "💜")
                            .font(.system(.title3))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slot.title)
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .foregroundStyle(Papier.aufNacht)
                            Text(weeklyLine(slot))
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(Nacht.sekundaer)
                        }
                        Spacer()
                        Button {
                            deleteSlot(slot)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                        .buttonStyle(.plain)
                    }
                    .nightCard(padding: .compact)
                }
            }
        } else if plan.slots.isEmpty {
            Text(L10n.t("weekplan.empty.slots"))
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, Space.s)
        }
    }

    private func weeklyLine(_ slot: WeekplanSlot) -> String {
        var parts: [String] = []
        if let weekday = slot.weekday {
            parts.append(L10n.t("weekday.\(weekday)"))
        }
        if let time = slot.time { parts.append(time) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - One day on the board

private struct WeekplanDayCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let day: WeekplanDay
    let onSetAvailability: (String?) -> Void
    let onAddSlot: () -> Void
    let onDeleteSlot: (WeekplanSlot) -> Void

    private static let statuses: [(status: String, emoji: String)] = [
        ("free", "🙌"), ("busy", "🙅"), ("call", "📞"), ("date", "💘")
    ]

    private var isToday: Bool { day.dateKey == SharedDates.todayKey() }
    private var myStatus: String? {
        appState.memberId.flatMap { day.availability[$0]?.status }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            header
            if day.overlap {
                PillTag(text: L10n.t("weekplan.overlap"), tint: Licht.glut)
            }
            statusRow
            if !day.slots.isEmpty {
                slotList
            }
        }
        .nightCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .strokeBorder(isToday ? Licht.glut.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Text(L10n.t("weekday.\(day.weekday)"))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(isToday ? Licht.glut : Papier.aufNacht)
            Text(shortDate)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            Spacer()
            partnerMark
            Button {
                Haptics.shared.tap()
                onAddSlot()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .buttonStyle(.plain)
        }
    }

    private var shortDate: String {
        guard let date = SharedDates.parse(day.dateKey) else { return day.dateKey }
        return AppFormatters.dateTemplate(date, template: "d.M.", language: L10n.lang)
    }

    /// The partner's mark, read-only: avatar + status emoji.
    @ViewBuilder
    private var partnerMark: some View {
        if let partner = appState.partner,
           let mark = day.availability[partner.id],
           let entry = Self.statuses.first(where: { $0.status == mark.status }) {
            HStack(spacing: 3) {
                Text(partner.avatar)
                    .font(.system(.footnote))
                Text(entry.emoji)
                    .font(.system(.footnote))
            }
            .padding(.vertical, 3)
            .padding(.horizontal, Space.s)
            .background(Capsule().fill(Papier.nachtInnenFill))
        }
    }

    private var statusRow: some View {
        HStack(spacing: Space.s) {
            Text(L10n.t("weekplan.myDay"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
            ForEach(Self.statuses, id: \.status) { entry in
                statusChip(entry.status, emoji: entry.emoji)
            }
        }
    }

    private func statusChip(_ status: String, emoji: String) -> some View {
        let selected = myStatus == status
        // Tapping the active status clears my mark for that day.
        return Button {
            onSetAvailability(selected ? nil : status)
        } label: {
            VStack(spacing: 1) {
                Text(emoji)
                    .font(.system(.subheadline))
                Text(L10n.t("weekplan.status.\(status)"))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? AnyShapeStyle(coupleTint.blend.opacity(0.15))
                                   : AnyShapeStyle(Papier.nachtInnenFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                  lineWidth: selected ? 1.5 : Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var slotList: some View {
        VStack(spacing: Space.s) {
            ForEach(day.slots) { slot in
                HStack(spacing: Space.s) {
                    Text(slot.emoji ?? "💜")
                        .font(.system(.body))
                    Text(slot.title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    if slot.weekday != nil {
                        Image(systemName: "repeat")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                    Spacer()
                    if let time = slot.time {
                        Text(time)
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    Button {
                        onDeleteSlot(slot)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.footnote))
                            .foregroundStyle(Nacht.tertiaer.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.m)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Licht.glut.opacity(0.10))
                )
            }
        }
    }
}

// MARK: - Compose sheet

private struct WeekplanSlotComposeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let initialDateKey: String?
    let onAdded: () -> Void

    @State private var title = ""
    @State private var kind = "call"
    @State private var repeatWeekly = false
    @State private var date = Date()
    @State private var weekday = 5
    @State private var useTime = false
    @State private var time = Self.defaultTime
    @State private var adding = false

    private static let kinds: [(kind: String, emoji: String)] = [
        ("call", "📞"), ("movie", "🍿"), ("date", "💘"), ("custom", "💜")
    ]

    private static var defaultTime: Date {
        SharedDates.calendar.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        kindRow
                        TextField(L10n.t("weekplan.compose.titleField"), text: $title)
                            .textFieldStyle(RitualFieldStyle())
                        Toggle(L10n.t("weekplan.compose.repeat"), isOn: $repeatWeekly)
                            .font(Typo.label)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(coupleTint.blend)
                        if repeatWeekly {
                            weekdayRow
                        } else {
                            DatePicker(L10n.t("weekplan.compose.day"), selection: $date,
                                       in: Date()..., displayedComponents: [.date])
                                .font(Typo.label)
                                .foregroundStyle(Theme.textPrimary)
                                .tint(coupleTint.blend)
                                .colorScheme(.dark)
                                // System pickers follow the DEVICE locale,
                                // the app speaks ITS language (Amt seam,
                                // Re-Eval Runde 2 roll-out).
                                .environment(\.locale, Locale(identifier: L10n.lang))
                        }
                        Toggle(L10n.t("weekplan.compose.time"), isOn: $useTime)
                            .font(Typo.label)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(coupleTint.blend)
                        if useTime {
                            DatePicker("", selection: $time, displayedComponents: [.hourAndMinute])
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .environment(\.locale, Locale(identifier: L10n.lang))
                                .frame(maxWidth: .infinity)
                        }
                        Button(L10n.t("weekplan.newSlot")) {
                            add()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(adding || !isValid)
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("weekplan.compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            if let key = initialDateKey, let parsed = SharedDates.parse(key) {
                date = max(parsed, Date())
            }
        }
    }

    private var kindRow: some View {
        HStack(spacing: Space.s) {
            ForEach(Self.kinds, id: \.kind) { entry in
                let selected = kind == entry.kind
                Button {
                    kind = entry.kind
                    if title.isEmpty || Self.kinds.contains(where: { defaultTitle($0.kind) == title }) {
                        title = entry.kind == "custom" ? "" : defaultTitle(entry.kind)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Text(entry.emoji)
                            .font(.system(.title3))
                        Text(L10n.t("weekplan.slot.kind.\(entry.kind)"))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(selected ? AnyShapeStyle(coupleTint.blend.opacity(0.30))
                                           : AnyShapeStyle(Theme.innerFill))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(selected ? coupleTint.blend : Theme.hairline,
                                          lineWidth: selected ? 1.5 : Theme.hairlineWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<7, id: \.self) { day in
                let selected = weekday == day
                Button {
                    weekday = day
                } label: {
                    Text(L10n.t("weekday.\(day)"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(selected ? AnyShapeStyle(coupleTint.blend.opacity(0.35))
                                               : AnyShapeStyle(Theme.innerFill))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func defaultTitle(_ kind: String) -> String {
        L10n.t("weekplan.slot.kind.\(kind)")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var timeString: String? {
        guard useTime else { return nil }
        let parts = SharedDates.calendar.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func add() {
        guard let api = appState.api, !adding else { return }
        adding = true
        let emoji = Self.kinds.first { $0.kind == kind }?.emoji
        Task {
            do {
                _ = try await api.addWeekplanSlot(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    emoji: emoji,
                    kind: kind,
                    dateKey: repeatWeekly ? nil : SharedDates.todayKey(date),
                    weekday: repeatWeekly ? weekday : nil,
                    time: timeString)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("weekplan.addedToast"), style: .success)
                onAdded()
                dismiss()
            } catch {
                adding = false
                appState.handleAPIError(error)
            }
        }
    }
}
