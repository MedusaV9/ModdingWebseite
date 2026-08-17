import SwiftUI
import Combine

/// Rituals block on the dashboard: week-plan day-of banner, the one-tap
/// need button and the evening audio check-in teaser. One line in
/// DashboardView mounts it all. The season-door card moved OUT of this
/// block — it is its own ranked dashboard card now (FXC-4 #9), mounted
/// directly by `DashboardView`. Neubau N2: `EnergyCard` moved out too —
/// the battery is the head's Dienstlicht now (§4.1 Kopf), presented by
/// `DashboardHeaderView` one tap from the lamp dot.
struct RitualsDashboardSection: View {
    var body: some View {
        WeekplanTodayBanner()
        NeedsCard()
        DaymemoCard()
        WeekReviewSupportCard()
        RepairSupportCard()
    }
}

private struct WeekReviewSupportCard: View {
    var body: some View {
        NavigationLink {
            WeekReviewView()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.lampengold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Licht.lampengold.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("weekreview.card.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("weekreview.card.hint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
    }
}

/// The season-calendar door card: instead of a static "calendars exist"
/// hint, it surfaces the NEXT door addressed to me — with a live countdown
/// while it's locked and a ready badge the moment it can be opened. The
/// waiting is the delight; invisible waiting is none (FX-O #8).
/// Internal (not private): `DashboardView` mounts it as its OWN ranked
/// card — a ready door is a waiting surprise, not the seventh unit of the
/// rituals block (FXC-4 #9).
struct SeasonCalendarSupportCard: View {
    @Environment(AppState.self) private var appState
    @State private var calendars: [CoupleSeasonCalendar] = []

    var body: some View {
        NavigationLink {
            SeasonCalendarView()
        } label: {
            // Minute cadence: enough to keep the countdown honest and to
            // flip locked → ready without a ticking seconds clock.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                cardLabel(now: timeline.date)
            }
        }
        .buttonStyle(.plain)
        .task(id: appState.couple?.id) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent,
                  event.type == .seasonCalendarChanged else { return }
            Task { await reload() }
        }
    }

    private func cardLabel(now: Date) -> some View {
        let next = nextDoor(now: now)
        let ready = next.map { $0.unlockAt <= now } ?? false
        return HStack(spacing: Space.m) {
            Image(systemName: ready ? "gift.fill" : "calendar.badge.clock")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Licht.glut)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Licht.glut.opacity(0.14)))
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("seasoncalendar.card.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(statusLine(next: next, now: now))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(ready ? Licht.glut : Nacht.sekundaer)
            }
            Spacer()
            if ready {
                PillTag(text: L10n.t("seasoncalendar.next.readyPill"), tint: Theme.gold)
            }
            Image(systemName: "chevron.right")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t("seasoncalendar.card.title") + ", "
                            + statusLine(next: next, now: now))
    }

    /// Without a waiting door the card keeps its old quiet hint.
    private func statusLine(next: SeasonDoorSummary?, now: Date) -> String {
        guard let next else { return L10n.t("seasoncalendar.card.hint") }
        let number = "\(next.number)"
        switch SeasonDoorDashboard.countdown(until: next.unlockAt, now: now) {
        case .ready:
            return L10n.t("seasoncalendar.next.ready", ["n": number])
        case .days(let days):
            return L10n.t("seasoncalendar.next.countdown",
                          ["n": number,
                           "time": L10n.t("seasoncalendar.next.days", ["n": "\(days)"])])
        case .hoursMinutes(let hours, let minutes):
            return L10n.t("seasoncalendar.next.countdown",
                          ["n": number,
                           "time": L10n.t("seasoncalendar.next.hoursMinutes",
                                          ["h": "\(hours)", "m": "\(minutes)"])])
        case .minutes(let minutes):
            return L10n.t("seasoncalendar.next.countdown",
                          ["n": number,
                           "time": L10n.t("seasoncalendar.next.minutes", ["n": "\(minutes)"])])
        case .soon:
            return L10n.t("seasoncalendar.next.soon", ["n": number])
        }
    }

    private func nextDoor(now: Date) -> SeasonDoorSummary? {
        let feeds = calendars.map { calendar in
            SeasonCalendarDoorFeed(
                forMe: calendar.recipientId == appState.memberId,
                doors: calendar.doors.map {
                    SeasonDoorSummary(number: $0.number,
                                      unlockAt: $0.unlockAt,
                                      opened: $0.openedAt != nil)
                }
            )
        }
        return SeasonDoorDashboard.nextDoor(in: feeds, now: now)
    }

    /// Quiet prefetch — a failure only means the card keeps its static
    /// hint; the full calendar view behind it handles errors visibly.
    private func reload() async {
        guard let api = appState.api else { return }
        do {
            calendars = try await api.seasonCalendars()
        } catch {}
    }
}

private struct RepairSupportCard: View {
    var body: some View {
        NavigationLink {
            RepairConsiderationView()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.lampengold)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Licht.lampengold.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("repair.card.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("repair.card.hint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Energy battery card

/// The battery frame, consistently (Dossier 32, ideas 9/10): "how full are
/// you" is value-free, unlike a traffic light's "state: forbidden". Levels
/// carry a SHAPE (battery fill) besides the color, and red is a warm own
/// tone — never the love-pink.
struct EnergyCard: View {
    @Environment(AppState.self) private var appState
    @State private var busy = false
    /// Long-press target for the "what would help?" note (idea 8).
    @State private var noteLevel: EnergyLevel?
    @State private var noteText = ""

    private var myLevel: EnergyLevel? {
        appState.me?.energy.flatMap { EnergyLevel(rawValue: $0.level) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Image(systemName: "battery.75percent")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(L10n.t("energy.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
            }
            partnerRow
            Text(L10n.t("energy.mine"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            HStack(spacing: Space.s) {
                ForEach(EnergyLevel.allCases) { level in
                    levelButton(level)
                }
            }
            // The server hides the light after 12 h — say so instead of
            // vanishing wordlessly (idea 19).
            if let energy = appState.me?.energy {
                Text(L10n.t("energy.validUntil",
                            ["time": energy.visibleUntil.formatted(date: .omitted,
                                                                   time: .shortened)]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .nightCard()
        .alert(L10n.t("energy.notePrompt"),
               isPresented: Binding(get: { noteLevel != nil },
                                    set: { if !$0 { noteLevel = nil } })) {
            TextField(L10n.t("energy.noteField"), text: $noteText)
            Button(L10n.t("common.save")) {
                if let level = noteLevel {
                    set(level, note: noteText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                noteLevel = nil
            }
            Button(L10n.t("common.cancel"), role: .cancel) {
                noteLevel = nil
            }
        }
    }

    @ViewBuilder
    private var partnerRow: some View {
        if let partner = appState.partner {
            if let energy = partner.energy, let level = EnergyLevel(rawValue: energy.level) {
                HStack(spacing: Space.s) {
                    Image(systemName: level.symbol)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(tint(for: level))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("energy.partnerLabel", ["name": partner.name]) + " " + L10n.t(level.titleKey))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        Text(energy.note?.isEmpty == false ? energy.note! : L10n.t(level.hintKey))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(L10n.relativeShort(energy.setAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                .padding(LayoutMetrics.s(10))
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(tint(for: level).opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(tint(for: level).opacity(0.45), lineWidth: 1)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("energy.partnerLabel", ["name": partner.name])
                                    + " " + L10n.t(level.titleKey))
            } else {
                Text(L10n.t("energy.partnerUnset", ["name": partner.name]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
    }

    private func tint(for level: EnergyLevel) -> Color {
        switch level {
        case .green: return Theme.mint
        case .yellow: return Theme.gold
        case .red: return Theme.energyRed
        }
    }

    private func levelButton(_ level: EnergyLevel) -> some View {
        let selected = myLevel == level
        return Button {
            toggle(level)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: level.symbol)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected ? tint(for: level) : Nacht.sekundaer)
                Text(L10n.t(level.titleKey))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(10))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? tint(for: level).opacity(0.30) : Papier.nachtInnenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? tint(for: level) : Nacht.naht,
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(busy)
        // Long-press wakes the dormant note field the server always accepted
        // (idea 8); tap stays the fast path.
        .onLongPressGesture {
            Haptics.shared.tap()
            noteText = appState.me?.energy?.note ?? ""
            noteLevel = level
        }
        .accessibilityLabel(L10n.t(level.titleKey))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Tap = set, tap the active level again = turn it off.
    private func toggle(_ level: EnergyLevel) {
        if myLevel == level {
            clear()
        } else {
            set(level, note: nil)
        }
    }

    private func set(_ level: EnergyLevel, note: String?) {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            do {
                let energy = try await api.setEnergy(level: level,
                                                     note: note?.isEmpty == false ? note : nil)
                appState.applyEnergy(memberId: appState.memberId ?? "", energy: energy)
                Haptics.shared.success()
                appState.showToast(L10n.t("energy.setToast", ["name": appState.partnerName]),
                                   style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private func clear() {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            do {
                try await api.clearEnergy()
                appState.applyEnergy(memberId: appState.memberId ?? "", energy: nil)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }
}

// MARK: - Need button card

struct NeedsCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @State private var openNeedFromPartner: NeedSignal?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Image(systemName: "hands.and.sparkles.fill")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("needs.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                NavigationLink {
                    NeedsHistoryView()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                .buttonStyle(.plain)
            }
            if let need = openNeedFromPartner, let type = need.needType {
                partnerNeedBanner(need, type: type)
            }
            needButtons
        }
        .nightCard()
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .need, .needAcked:
                if let payload = event.decode(NeedEventPayload.self) {
                    apply(payload.need)
                }
            default:
                break
            }
        }
    }

    private func apply(_ need: NeedSignal) {
        guard need.forMember == appState.memberId else { return }
        if need.ackAt == nil {
            withAnimation(Theme.Motion.arrive) { openNeedFromPartner = need }
        } else if openNeedFromPartner?.id == need.id {
            withAnimation(Theme.Motion.settle) { openNeedFromPartner = nil }
        }
    }

    private func reload() async {
        guard let api = appState.api, let me = appState.memberId else { return }
        if let needs = try? await api.needs(limit: 10) {
            openNeedFromPartner = needs.first { $0.forMember == me && $0.ackAt == nil }
        }
    }

    /// The partner's open signal — gently prominent, one tap to respond.
    private func partnerNeedBanner(_ need: NeedSignal, type: NeedType) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(type.emoji)
                    .font(.system(.title2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("needs.partnerNeeds", ["name": appState.partnerName]))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                    Text(L10n.t(type.titleKey))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                }
                Spacer()
                Text(L10n.relativeShort(need.createdAt))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            if let note = need.note, !note.isEmpty {
                Text("„\(note)“")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
            Button(L10n.t("needs.ack")) {
                acknowledge(need)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(coupleTint.blend.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(coupleTint.blend.opacity(0.5), lineWidth: Theme.hairlineWidth)
        )
    }

    private func acknowledge(_ need: NeedSignal) {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            do {
                let updated = try await api.ackNeed(id: need.id)
                apply(updated)
                Haptics.shared.success()
                SoundEngine.shared.play(.sparkle)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private var needButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(NeedType.allCases) { type in
                    needButton(type)
                }
            }
        }
    }

    private func needButton(_ type: NeedType) -> some View {
        Button {
            send(type)
        } label: {
            HStack(spacing: 6) {
                Text(type.emoji)
                    .font(.system(.body))
                Text(L10n.t(type.titleKey))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
            }
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            .background(Capsule().fill(Papier.nachtInnenFill))
            .overlay(Capsule().strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
        }
        .buttonStyle(.plain)
        .disabled(busy || appState.partner == nil)
    }

    private func send(_ type: NeedType) {
        guard let api = appState.api, !busy else { return }
        busy = true
        Haptics.shared.tap()
        Task {
            do {
                _ = try await api.sendNeed(type: type, note: nil)
                SoundEngine.shared.play(.pop)
                appState.showToast(L10n.t("needs.sentToast", ["name": appState.partnerName]),
                                   style: .love)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }
}

// MARK: - Audio check-in teaser card

struct DaymemoCard: View {
    @Environment(AppState.self) private var appState
    @State private var today: DaymemoDay?
    @State private var streak = 0

    var body: some View {
        NavigationLink {
            DaymemoView()
        } label: {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Image(systemName: "mic.fill")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.lampengold)
                    Text(L10n.t("daymemo.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Spacer()
                    if streak > 0 {
                        // Shared days, not a fire score (Dossier 02): the
                        // number tells biography, it doesn't threaten loss.
                        SharedDaysPill(days: streak)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Text(statusText)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent, event.type == .daymemo,
                  let day = event.decode(DaymemoDay.self) else { return }
            if day.dateKey == SharedDates.todayKey() { today = day }
            streak = day.streak
        }
    }

    private var statusText: String {
        let name = appState.partnerName
        guard let today else { return L10n.t("daymemo.card.hint", ["name": name]) }
        if today.bothRecorded { return L10n.t("daymemo.card.ready") }
        if today.mine != nil { return L10n.t("daymemo.card.waiting", ["name": name]) }
        if today.partnerRecorded { return L10n.t("daymemo.card.partnerFirst", ["name": name]) }
        return L10n.t("daymemo.card.hint", ["name": name])
    }

    private func reload() async {
        guard let api = appState.api else { return }
        if let response = try? await api.daymemos(limit: 1) {
            streak = response.streak
            today = response.days.first { $0.dateKey == SharedDates.todayKey() }
        }
    }
}

// MARK: - Week-plan day-of banner

/// "Today: movie night 🍿" — shows only when today actually has slots.
struct WeekplanTodayBanner: View {
    @Environment(AppState.self) private var appState
    @State private var todaySlots: [WeekplanSlot] = []

    var body: some View {
        Group {
            if !todaySlots.isEmpty {
                NavigationLink {
                    WeekplanView()
                } label: {
                    HStack(spacing: Space.m) {
                        Image(systemName: "calendar")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .foregroundStyle(Licht.glut)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(todaySlots.prefix(2)) { slot in
                                Text(L10n.t("weekplan.today.banner", ["title": slotLine(slot)]))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .foregroundStyle(Papier.aufNacht)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                    .nightCard()
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                            .strokeBorder(Licht.glut.opacity(0.45), lineWidth: Theme.hairlineWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .weekplanSlotAdded, .weekplanSlotUpdated, .weekplanSlotDeleted:
                Task { await reload() }
            default:
                break
            }
        }
    }

    private func slotLine(_ slot: WeekplanSlot) -> String {
        var line = "\(slot.emoji ?? "💜") \(slot.title)"
        if let time = slot.time { line += " · \(time)" }
        return line
    }

    private func reload() async {
        guard let api = appState.api else { return }
        if let plan = try? await api.weekplan(days: 1),
           let today = plan.days.first {
            todaySlots = today.slots.sorted { ($0.time ?? "99") < ($1.time ?? "99") }
        }
    }
}
