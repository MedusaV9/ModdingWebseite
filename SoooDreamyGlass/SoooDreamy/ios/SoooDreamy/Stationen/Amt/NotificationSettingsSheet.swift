import SwiftUI

// W8 Settings-IA (Linse 12 #9): the notification card was the longest card of
// the whole app — 6+ toggles, a time picker and sound chips. The details live
// here now; the main settings card keeps only the master switch plus a
// one-line summary and the link into this sheet.

struct NotificationSettingsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var alertSound = NotificationPrefs.globalSound
    @State private var alertKinds: [CoupleAlertKind: Bool] = Dictionary(
        uniqueKeysWithValues: CoupleAlertKind.allCases.map { ($0, NotificationPrefs.isEnabled($0)) })

    @State private var reminderOn = ReminderManager.isEnabled
    @State private var streakGuardOn = ReminderManager.isStreakGuardEnabled
    @State private var couponReminderOn = CouponReminder.isEnabled
    @State private var reminderTime: Date = {
        let t = ReminderManager.time
        return Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date()
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                // Native grouped Form (system semantics, spacing, focus
                // order); the rows sit as night cartons over the
                // DreamyBackground — same content, same order.
                Form {
                    soundSection
                    eventsSection
                    remindersSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .contentColumn(.reading)
            }
            .navigationTitle(L10n.t("notif.section"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sound

    private var soundSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.s(8)) {
                    ForEach(NotificationSound.allCases) { sound in
                        soundChip(sound)
                    }
                }
            }
        } header: {
            Text(L10n.t("notif.sound"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private func soundChip(_ sound: NotificationSound) -> some View {
        let selected = alertSound == sound
        return Button {
            alertSound = sound
            NotificationPrefs.globalSound = sound
            Haptics.shared.tap()
            sound.preview()
            Task { await ReminderManager.rescheduleIfNeeded() }
        } label: {
            HStack(spacing: LayoutMetrics.s(5)) {
                Text(sound.emoji)
                    .font(.system(.footnote))
                Text(sound.displayName)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.vertical, LayoutMetrics.s(8))
            .background(Capsule().fill(selected ? AnyShapeStyle(coupleTint.blend.opacity(0.16))
                                                : AnyShapeStyle(Papier.nachtInnenFill)))
            .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(coupleTint.blend)
                                                     : AnyShapeStyle(Nacht.naht),
                                            lineWidth: Theme.hairlineWidth))
            .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
        }
        .buttonStyle(.plain)
    }

    // MARK: Per-event toggles

    private var eventsSection: some View {
        Section {
            ForEach(CoupleAlertKind.allCases) { kind in
                Toggle(isOn: alertBinding(kind)) {
                    Label(L10n.t(kind.titleKey), systemImage: kind.icon)
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
            }
        } header: {
            Text(L10n.t("settings.notif.events"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private func alertBinding(_ kind: CoupleAlertKind) -> Binding<Bool> {
        Binding(
            get: { alertKinds[kind] ?? true },
            set: { on in
                alertKinds[kind] = on
                NotificationPrefs.setEnabled(on, for: kind)
            }
        )
    }

    // MARK: Reminders (daily nudge, streak guard, coupon expiry)

    private var remindersSection: some View {
        Section {
            // Daily reminder
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $reminderOn) {
                    Label(L10n.t("settings.reminder"), systemImage: "bell.badge.fill")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: reminderOn) { _, on in
                    Task {
                        let ok = await ReminderManager.setEnabled(on)
                        if !ok { reminderOn = false }
                    }
                }
                Text(L10n.t("settings.reminderHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
                if reminderOn {
                    DatePicker(L10n.t("settings.reminderTime"),
                               selection: $reminderTime,
                               displayedComponents: .hourAndMinute)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .tint(coupleTint.blend)
                        // System pickers follow the DEVICE locale, the app
                        // speaks ITS language (Amt seam, Re-Eval Runde 2).
                        .environment(\.locale, Locale(identifier: L10n.lang))
                        .padding(.leading, LayoutMetrics.s(40))
                        .onChange(of: reminderTime) { _, newValue in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            Task {
                                await ReminderManager.setTime(hour: comps.hour ?? 20,
                                                              minute: comps.minute ?? 0)
                            }
                        }
                }
            }

            // Streak guard (second, "streak at risk" evening nudge)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $streakGuardOn) {
                    Label(L10n.t("settings.streakGuard"), systemImage: "flame.fill")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: streakGuardOn) { _, on in
                    Task {
                        let ok = await ReminderManager.setStreakGuardEnabled(on, entry: appState.dailyEntry)
                        if !ok { streakGuardOn = false }
                    }
                }
                Text(L10n.t("settings.streakGuardHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }

            // Coupon expiry reminder ("expiring soon" nudge)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $couponReminderOn) {
                    Label(L10n.t("settings.couponReminder"), systemImage: "ticket.fill")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: couponReminderOn) { _, on in
                    Task {
                        var coupons: [Coupon] = []
                        if on, let api = appState.api {
                            coupons = (try? await api.coupons()) ?? []
                        }
                        let ok = await CouponReminder.setEnabled(on, coupons: coupons,
                                                                 myMemberId: appState.memberId)
                        if !ok { couponReminderOn = false }
                    }
                }
                Text(L10n.t("settings.couponReminderHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }
        } header: {
            Text(L10n.t("settings.notif.reminders"))
        }
        .listRowBackground(Papier.nachtkarton)
    }
}
