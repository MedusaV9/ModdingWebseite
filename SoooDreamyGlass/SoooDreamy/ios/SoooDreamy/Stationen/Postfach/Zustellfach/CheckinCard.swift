import SwiftUI
import Combine

/// Morning/night check-in card — one tap each, shared days for
/// dates on which BOTH partners checked in. W4 (Dossier 32): the button
/// matching the time of day leads, the streak rule is spelled out under
/// the buttons, and a forgotten yesterday can be caught up (the server
/// accepts `dateKey` ±1 day).
struct CheckinCard: View {
    @Environment(AppState.self) private var appState
    /// AX5: the morning/night buttons stack vertically (both full width)
    /// instead of squeezing side by side, and labels stop being scaled down.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var today: CheckinDay?
    @State private var yesterday: CheckinDay?
    @State private var streak = 0
    @State private var busyKind: String?
    @State private var showStreakCalendar = false

    /// Before 14:00 the morning greeting leads, after it the night one —
    /// never hiding the other (shift work, time zones; Dossier 32, idea 7).
    private var preferredKind: String {
        Calendar.current.component(.hour, from: Date()) < 14 ? "morning" : "night"
    }

    private var yesterdayKey: String {
        SharedDates.todayKey(Calendar.current.date(byAdding: .day, value: -1,
                                                   to: Date()) ?? Date())
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            HStack {
                Text(L10n.t("checkin.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                if streak > 0 {
                    // The pill is a door, not decoration (idea 26): shared
                    // days open the calendar of how long already.
                    Button {
                        Haptics.shared.tap()
                        showStreakCalendar = true
                    } label: {
                        SharedDaysPill(days: streak)
                    }
                    .buttonStyle(.plain)
                }
            }
            if dynamicTypeSize.prefersVerticalLayout {
                VStack(spacing: LayoutMetrics.s(10)) {
                    if preferredKind == "morning" {
                        checkinButton(kind: "morning", primary: true)
                        checkinButton(kind: "night", primary: false)
                    } else {
                        checkinButton(kind: "night", primary: true)
                        checkinButton(kind: "morning", primary: false)
                    }
                }
            } else {
                HStack(spacing: LayoutMetrics.s(10)) {
                    if preferredKind == "morning" {
                        checkinButton(kind: "morning", primary: true)
                        checkinButton(kind: "night", primary: false)
                    } else {
                        checkinButton(kind: "night", primary: true)
                        checkinButton(kind: "morning", primary: false)
                    }
                }
            }
            if let fairness = fairnessStatus {
                HStack(spacing: Space.xs) {
                    Image(systemName: fairness.done ? "checkmark.seal.fill" : "hourglass")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(fairness.done ? Licht.lampengold : Nacht.tertiaer)
                    Text(fairness.text)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                    Spacer(minLength: 0)
                }
            } else if let hint = partnerHint {
                Text(hint)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if canCatchUpYesterday {
                catchUpRow
            }
        }
        .nightCard()
        .sheet(isPresented: $showStreakCalendar) {
            StreakCalendarView()
        }
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent, event.type == .checkin,
                  let payload = event.decode(CheckinEventPayload.self) else { return }
            if payload.day.dateKey == SharedDates.todayKey() {
                today = payload.day
            } else if payload.day.dateKey == yesterdayKey {
                yesterday = payload.day
            }
            streak = payload.streak
        }
    }

    // MARK: Streak fairness (idea 11) — make the BOTH rule feel natural

    /// Three-state micro status: today already counts / partner's wave is
    /// missing / mine is missing. Silent when neither has checked in yet.
    private var fairnessStatus: (text: String, done: Bool)? {
        guard let today, let me = appState.memberId,
              let partnerId = appState.partner?.id else { return nil }
        let mine = today.checkedIn(me, kind: "morning") || today.checkedIn(me, kind: "night")
        let theirs = today.checkedIn(partnerId, kind: "morning")
            || today.checkedIn(partnerId, kind: "night")
        if mine && theirs {
            return (L10n.t("checkin.fair.counted"), true)
        }
        if mine {
            return (L10n.t("checkin.fair.partnerMissing", ["name": appState.partnerName]), false)
        }
        if theirs {
            return (L10n.t("checkin.fair.mineMissing"), false)
        }
        return nil
    }

    private var partnerHint: String? {
        guard let partnerId = appState.partner?.id, let today else { return nil }
        let morning = today.checkedIn(partnerId, kind: "morning")
        let night = today.checkedIn(partnerId, kind: "night")
        if night { return L10n.t("checkin.partner.night", ["name": appState.partnerName]) }
        if morning { return L10n.t("checkin.partner.morning", ["name": appState.partnerName]) }
        return L10n.t("checkin.partner.none", ["name": appState.partnerName])
    }

    // MARK: Catch up on yesterday (idea 6) — the fairest streak rescue

    /// Only when yesterday exactly MY greeting is missing: the partner
    /// waved, I forgot, and one late tap still mends the shared days.
    private var canCatchUpYesterday: Bool {
        guard let me = appState.memberId, let partnerId = appState.partner?.id,
              let yesterday else { return false }
        let mine = yesterday.checkedIn(me, kind: "morning")
            || yesterday.checkedIn(me, kind: "night")
        let theirs = yesterday.checkedIn(partnerId, kind: "morning")
            || yesterday.checkedIn(partnerId, kind: "night")
        return theirs && !mine
    }

    private var catchUpRow: some View {
        Button {
            send(kind: "night", dateKey: yesterdayKey)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "moon.haze.fill")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("checkin.catchup"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("checkin.catchup.hint", ["name": appState.partnerName]))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .padding(LayoutMetrics.s(10))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
            )
        }
        .buttonStyle(.plain)
        .disabled(busyKind != nil)
    }

    // MARK: Buttons

    private func checkinButton(kind: String, primary: Bool) -> some View {
        let done = today?.checkedIn(appState.memberId, kind: kind) ?? false
        // On the night card the time-of-day color stays MATERIAL (a warm
        // wash behind the label); glyphs and copy speak aufNacht/lamplight.
        let wash = kind == "morning" ? Theme.gold : Licht.glut
        let titleKey = kind == "morning" ? "checkin.morning" : "checkin.night"
        let stacked = dynamicTypeSize.prefersVerticalLayout
        return Button {
            send(kind: kind)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: kind == "morning" ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(primary ? .body : .footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(done ? Licht.lampengold : Nacht.sekundaer)
                Text(L10n.t(done ? "\(titleKey).done" : titleKey))
                    .font(.system(primary ? .subheadline : .caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    // Stacked AX layout: the label owns the row — it wraps
                    // at natural size instead of being scaled down.
                    .lineLimit(stacked ? nil : 1)
                    .minimumScaleFactor(stacked ? 1 : 0.8)
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                }
            }
            .frame(maxWidth: primary || stacked ? .infinity : nil)
            .padding(.vertical, LayoutMetrics.s(primary ? 12 : 9))
            .padding(.horizontal, LayoutMetrics.s(primary ? 12 : 10))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(done ? wash.opacity(0.28)
                          : primary ? wash.opacity(0.16) : Papier.nachtInnenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(done || primary ? wash : Nacht.naht,
                                  lineWidth: done || primary ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(done || busyKind != nil)
        .accessibilityLabel(L10n.t(titleKey))
        .accessibilityValue(done ? L10n.t("\(titleKey).done") : "")
    }

    private func reload() async {
        guard let api = appState.api else { return }
        if let response = try? await api.checkins(limit: 2) {
            streak = response.streak
            today = response.days.first { $0.dateKey == SharedDates.todayKey() }
            yesterday = response.days.first { $0.dateKey == yesterdayKey }
        }
    }

    private func send(kind: String, dateKey: String? = nil) {
        guard let api = appState.api, busyKind == nil else { return }
        busyKind = kind
        Task {
            do {
                let response = try await api.checkin(kind: kind, dateKey: dateKey)
                if dateKey == nil {
                    today = response.day
                } else {
                    yesterday = response.day
                }
                streak = response.streak
                SoundEngine.shared.play(kind == "morning" ? .sparkle : .chime)
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
            busyKind = nil
        }
    }
}
