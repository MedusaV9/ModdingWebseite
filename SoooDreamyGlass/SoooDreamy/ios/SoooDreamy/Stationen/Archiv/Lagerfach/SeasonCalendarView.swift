import SwiftUI
import Combine

struct SeasonCalendarView: View {
    @Environment(AppState.self) private var appState

    @State private var calendars: [CoupleSeasonCalendar] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var showCompose = false
    @State private var revealedDoor: SeasonCalendarDoor?

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    seasonalSuggestion
                    Button {
                        Haptics.shared.tap()
                        showCompose = true
                    } label: {
                        Label(L10n.t("seasoncalendar.new"), systemImage: "calendar.badge.plus")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if loading {
                        PaperSkeleton(kind: .card(height: 180))
                        PaperSkeleton(kind: .card(height: 180))
                    } else if calendars.isEmpty {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        } else {
                            EmptyStateView(
                                systemImage: "calendar",
                                title: L10n.t("seasoncalendar.empty.title"),
                                subtitle: L10n.t("seasoncalendar.empty.body")
                            )
                        }
                    } else {
                        ForEach(calendars) { calendar in
                            SeasonCalendarCard(
                                calendar: calendar,
                                memberId: appState.memberId,
                                onOpen: { door in open(door, in: calendar) },
                                onDelete: calendar.createdBy == appState.memberId
                                    && calendar.doors.allSatisfy { $0.openedAt == nil }
                                    ? { delete(calendar) } : nil
                            )
                        }
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("seasoncalendar.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent,
                  event.type == .seasonCalendarChanged,
                  let payload = event.decode(SeasonCalendarEventPayload.self) else { return }
            if payload.deleted {
                calendars.removeAll { $0.id == payload.calendarId }
            } else if let calendar = payload.calendar {
                apply(calendar)
            }
        }
        .sheet(isPresented: $showCompose) {
            SeasonCalendarComposeSheet { calendar in
                apply(calendar)
            }
        }
        .sheet(item: $revealedDoor) { door in
            SeasonDoorRevealSheet(door: door)
        }
    }

    @ViewBuilder
    private var seasonalSuggestion: some View {
        let anniversary = appState.couple?.anniversary.flatMap(SharedDates.parse)
        let events = SeasonalEvent.active(on: Date(), anniversary: anniversary)
        if let event = events.last {
            HStack(spacing: Space.m) {
                Image(systemName: event == .anniversary ? "sparkles" : "party.popper.fill")
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(Licht.glut)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(L10n.t(event.titleKey))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("seasonalevent.skinSuggestion"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                PillTag(text: L10n.t("seasonalevent.suggested"), tint: Theme.gold)
            }
            .nightCard()
            .seasonEdge()
        }
    }

    private func apply(_ calendar: CoupleSeasonCalendar) {
        if let index = calendars.firstIndex(where: { $0.id == calendar.id }) {
            calendars[index] = calendar
        } else {
            calendars.insert(calendar, at: 0)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        guard let api = appState.api else { return }
        do {
            calendars = try await api.seasonCalendars()
            loadFailed = false
        } catch {
            // A failed primary load must not LOOK like an empty calendar
            // shelf — the shared failed/offline notice offers a retry.
            loadFailed = true
        }
    }

    private func open(_ door: SeasonCalendarDoor, in calendar: CoupleSeasonCalendar) {
        if door.openedAt != nil {
            revealedDoor = door
            return
        }
        guard door.unlocked, calendar.recipientId == appState.memberId,
              let api = appState.api else { return }
        Task {
            do {
                let updated = try await api.openSeasonCalendarDoor(
                    calendarId: calendar.id,
                    doorId: door.id
                )
                apply(updated)
                if let opened = updated.doors.first(where: { $0.id == door.id }) {
                    // R1-D: the door moment blooms in the app-wide
                    // Lichtschein instead of confetti (epic keeps its
                    // particles); the fanfare stays the ear's half.
                    AppCue.fanfareMedium.play()
                    LichtscheinCenter.shared.fire()
                    revealedDoor = opened
                }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func delete(_ calendar: CoupleSeasonCalendar) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteSeasonCalendar(id: calendar.id)
                calendars.removeAll { $0.id == calendar.id }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}

private struct SeasonCalendarCard: View {
    @Environment(AppState.self) private var appState
    let calendar: CoupleSeasonCalendar
    let memberId: String?
    let onOpen: (SeasonCalendarDoor) -> Void
    let onDelete: (() -> Void)?

    @State private var confirmDelete = false

    private let columns = [
        GridItem(.adaptive(minimum: 66), spacing: Space.s),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text(calendar.emoji ?? "🗓️")
                    .font(.system(.title))
                    .accessibilityHidden(true)
                if let members = appState.couple?.members, members.count >= 2 {
                    CoupleMonogramView(
                        firstName: members[0].name,
                        secondName: members[1].name,
                        palette: appState.couple?.palette,
                        style: appState.couple?.monogramStyle ?? .seal,
                        size: 34
                    )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(
                        calendar.recipientId == memberId
                            ? L10n.t("seasoncalendar.forYou")
                            : L10n.t("seasoncalendar.forPartner")
                    )
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                if let onDelete {
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Nacht.tertiaer)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        L10n.t("seasoncalendar.deleteConfirm"),
                        isPresented: $confirmDelete,
                        titleVisibility: .visible
                    ) {
                        Button(L10n.t("common.delete"), role: .destructive) { onDelete() }
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: Space.s) {
                ForEach(calendar.doors) { door in
                    doorButton(door)
                }
            }
        }
        .nightCard()
    }

    private func doorButton(_ door: SeasonCalendarDoor) -> some View {
        let isRecipient = calendar.recipientId == memberId
        let canOpen = isRecipient && door.unlocked
        let revealed = door.openedAt != nil || calendar.createdBy == memberId
        return Button {
            onOpen(door)
        } label: {
            VStack(spacing: Space.xs) {
                Image(systemName: door.openedAt != nil
                      ? "checkmark.seal.fill"
                      : door.unlocked ? "gift.fill" : "lock.fill")
                    .font(.system(.body, design: .rounded).weight(.bold))
                Text(L10n.t("seasoncalendar.door", ["number": "\(door.number)"]))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .lineLimit(1)
                if revealed, let payload = door.payload {
                    Text(payload.text)
                        .font(.system(.caption2, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(AppFormatters.date(door.unlockAt, language: L10n.lang))
                        .font(.system(.caption2, design: .rounded))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(canOpen ? Papier.aufNacht : Nacht.sekundaer)
            .frame(maxWidth: .infinity, minHeight: 72)
            .padding(Space.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(canOpen ? Theme.gold.opacity(0.18) : Papier.nachtInnenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(canOpen ? Theme.gold.opacity(0.55) : Nacht.naht,
                                  lineWidth: Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(!revealed && !canOpen)
        .accessibilityLabel(
            L10n.t("seasoncalendar.door.a11y", [
                "number": "\(door.number)",
                "state": door.openedAt != nil
                    ? L10n.t("seasoncalendar.opened")
                    : door.unlocked ? L10n.t("seasoncalendar.ready") : L10n.t("seasoncalendar.locked"),
            ])
        )
    }
}

private struct SeasonCalendarComposeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let onCreated: (CoupleSeasonCalendar) -> Void

    @State private var title = ""
    @State private var kind = SeasonCalendarKind.countdown
    @State private var start = Date().addingTimeInterval(86_400)
    @State private var doorCount = 7
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("seasoncalendar.compose.details")) {
                    TextField(L10n.t("seasoncalendar.compose.titleField"), text: $title)
                    Picker(L10n.t("seasoncalendar.compose.kind"), selection: $kind) {
                        ForEach(SeasonCalendarKind.allCases) { option in
                            Text(L10n.t(option.titleKey)).tag(option)
                        }
                    }
                    DatePicker(
                        L10n.t("seasoncalendar.compose.start"),
                        selection: $start,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    // System pickers follow the DEVICE locale, the app
                    // speaks ITS language (Amt seam, Re-Eval Runde 2).
                    .environment(\.locale, Locale(identifier: L10n.lang))
                    Stepper(
                        L10n.t("seasoncalendar.compose.count", ["count": "\(doorCount)"]),
                        value: $doorCount,
                        in: 1...24
                    )
                }

                Section(L10n.t("seasoncalendar.compose.preview")) {
                    ForEach(Array(selectedTemplates.prefix(4).enumerated()), id: \.offset) { index, template in
                        Text(L10n.t("seasoncalendar.compose.previewRow", [
                            "number": "\(index + 1)",
                            "text": template.text(language: L10n.lang),
                        ]))
                    }
                    if doorCount > 4 {
                        Text(L10n.t("seasoncalendar.compose.more", ["count": "\(doorCount - 4)"]))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(L10n.t("seasoncalendar.compose.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(
                        saving
                            ? L10n.t("seasoncalendar.compose.saving")
                            : L10n.t("seasoncalendar.compose.create")
                    ) {
                        create()
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var selectedTemplates: [SeasonDoorTemplate] {
        let source: [SeasonDoorTemplate]
        switch kind {
        case .advent: source = SeasonDoorTemplates.quests
        case .birthday: source = SeasonDoorTemplates.prompts
        case .anniversary: source = SeasonDoorTemplates.letters
        case .countdown: source = SeasonDoorTemplates.games
        }
        return (0..<doorCount).map { source[$0 % source.count] }
    }

    private func create() {
        guard let api = appState.api, !saving else { return }
        saving = true
        let dates = SeasonCalendarPlan.doorDates(startingAt: start, count: doorCount)
        let drafts = zip(dates, selectedTemplates).map { date, template in
            SeasonDoorDraft(
                unlockAt: date,
                kind: template.kind,
                text: template.text(language: L10n.lang)
            )
        }
        Task {
            do {
                let calendar = try await api.createSeasonCalendar(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    emoji: kindEmoji,
                    kind: kind,
                    doors: drafts
                )
                Haptics.shared.success()
                onCreated(calendar)
                dismiss()
            } catch {
                saving = false
                appState.handleAPIError(error)
            }
        }
    }

    private var kindEmoji: String {
        switch kind {
        case .advent: return "🎄"
        case .birthday: return "🎂"
        case .anniversary: return "💍"
        case .countdown: return "✨"
        }
    }
}

private struct SeasonDoorRevealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let door: SeasonCalendarDoor

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: Space.l) {
                    Image(icon: .gift)
                        .font(Typo.hero)
                        .foregroundStyle(Theme.gold)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    // Sheet title sits on the NIGHT room, not on paper.
                    Text(L10n.t("seasoncalendar.door", ["number": "\(door.number)"]))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.textPrimary)
                    // The door's words: a letter read on paper (serif brief).
                    Text(door.payload?.text ?? L10n.t("seasoncalendar.payloadMissing"))
                        .font(Typo.brief)
                        .foregroundStyle(Tinte.dunkel)
                        .multilineTextAlignment(.center)
                        .paperCard(padding: .hero)
                    Button(L10n.t("common.done")) { dismiss() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(Space.xl)
            }
        }
    }
}
