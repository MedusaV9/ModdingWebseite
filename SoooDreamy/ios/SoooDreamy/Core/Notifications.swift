import Foundation
import AVFoundation
import UserNotifications

// MARK: - Local notifications
//
// Remote push is impossible with an unsigned sideloaded build, so everything
// here is LOCAL: couple alerts fire when WebSocket events arrive while the
// app is running (foreground or briefly backgrounded with a live socket),
// plus a repeating daily-question reminder. Sounds are the bundled
// Resources/Sounds/notif_*.wav files (< 30 s, as UNNotificationSound requires).

// MARK: - Notification sound

/// A selectable alert sound: one of the bundled WAVs or the iOS default.
enum NotificationSound: String, CaseIterable, Identifiable, Codable {
    case soft, chime, heartbeat, kiss, sparkle, whoosh, tada
    case systemDefault = "default"

    var id: String { rawValue }

    /// Bundled file name ("notif_chime.wav"); nil for the system default.
    var fileName: String? {
        self == .systemDefault ? nil : "notif_\(rawValue).wav"
    }

    /// DE/EN display name, resolved through the L10n tables.
    var displayNameKey: String { "notif.sound.\(rawValue)" }
    var displayName: String { L10n.t(displayNameKey) }

    var emoji: String {
        switch self {
        case .soft: return "🌙"
        case .chime: return "🔔"
        case .heartbeat: return "💓"
        case .kiss: return "😘"
        case .sparkle: return "✨"
        case .whoosh: return "🌊"
        case .tada: return "🎉"
        case .systemDefault: return "📱"
        }
    }

    /// Sound object for UNNotificationContent (bundled WAV or iOS default).
    var unSound: UNNotificationSound? {
        guard let fileName else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: fileName))
    }

    /// Default sound for an incoming touch when the user set no explicit
    /// override — mirrors the in-app SoundEngine mapping.
    static func mapped(for kind: TouchKind) -> NotificationSound {
        switch kind {
        case .heartbeat: return .heartbeat
        case .kiss: return .kiss
        case .hug: return .whoosh
        case .missyou: return .soft
        case .tickle: return .sparkle
        case .thinking: return .chime
        }
    }

    @MainActor private static var previewPlayer: AVAudioPlayer?

    /// Plays the WAV in-app (Settings sound picker). No-op for the system
    /// default — that sound can't be played on demand.
    @MainActor
    func preview() {
        guard let fileName,
              let url = Bundle.main.url(forResource: String(fileName.dropLast(4)), withExtension: "wav") else {
            return
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.9
        player?.play()
        Self.previewPlayer = player
    }
}

// MARK: - Alert kinds

/// Partner events that can raise a local notification (per-kind toggle).
enum CoupleAlertKind: String, CaseIterable, Identifiable {
    case touch, message, photo, dailyReveal, partnerOnline, coupon

    var id: String { rawValue }
    var titleKey: String { "notif.type.\(rawValue)" }

    var icon: String {
        switch self {
        case .touch: return "heart.fill"
        case .message: return "text.bubble.fill"
        case .photo: return "photo.fill"
        case .dailyReveal: return "questionmark.bubble.fill"
        case .partnerOnline: return "dot.radiowaves.left.and.right"
        case .coupon: return "ticket.fill"
        }
    }
}

// MARK: - Preferences

/// UserDefaults-backed notification preferences: master switch, one global
/// sound, plus optional per-kind toggles and sound overrides.
enum NotificationPrefs {
    private static let enabledKey = "sooodreamy.notif.enabled"
    private static let soundKey = "sooodreamy.notif.sound"
    private static func kindEnabledKey(_ kind: CoupleAlertKind) -> String { "sooodreamy.notif.\(kind.rawValue).enabled" }
    private static func kindSoundKey(_ kind: CoupleAlertKind) -> String { "sooodreamy.notif.\(kind.rawValue).sound" }

    /// Master switch for couple alerts (on by default — permission is only
    /// requested when the first alert would actually fire).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Global alert sound; per-kind overrides win when set.
    static var globalSound: NotificationSound {
        get {
            guard let raw = UserDefaults.standard.string(forKey: soundKey),
                  let sound = NotificationSound(rawValue: raw) else { return .soft }
            return sound
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: soundKey) }
    }

    static func isEnabled(_ kind: CoupleAlertKind) -> Bool {
        UserDefaults.standard.object(forKey: kindEnabledKey(kind)) as? Bool ?? true
    }

    static func setEnabled(_ on: Bool, for kind: CoupleAlertKind) {
        UserDefaults.standard.set(on, forKey: kindEnabledKey(kind))
    }

    /// Explicit per-kind sound; nil means "use the global sound".
    static func soundOverride(for kind: CoupleAlertKind) -> NotificationSound? {
        guard let raw = UserDefaults.standard.string(forKey: kindSoundKey(kind)) else { return nil }
        return NotificationSound(rawValue: raw)
    }

    static func setSoundOverride(_ sound: NotificationSound?, for kind: CoupleAlertKind) {
        if let sound {
            UserDefaults.standard.set(sound.rawValue, forKey: kindSoundKey(kind))
        } else {
            UserDefaults.standard.removeObject(forKey: kindSoundKey(kind))
        }
    }

    /// Effective sound for a kind: override if set, else the global sound.
    static func sound(for kind: CoupleAlertKind) -> NotificationSound {
        soundOverride(for: kind) ?? globalSound
    }
}

// MARK: - Posting alerts

/// Posts immediate local notifications for couple events.
enum CoupleNotify {
    /// userInfo key holding a "sooodreamy://…" deep link, opened on tap.
    static let linkKey = "link"

    /// True when notifications are (or become) authorized. Prompts the user
    /// only while the status is still undetermined.
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    /// Convenience for partner events: respects the master switch and the
    /// per-kind toggle, resolves the user's sound choice.
    static func alert(_ kind: CoupleAlertKind, title: String, body: String,
                      sound: NotificationSound? = nil, link: String? = nil) {
        guard NotificationPrefs.enabled, NotificationPrefs.isEnabled(kind) else { return }
        post(title: title, body: body,
             sound: sound ?? NotificationPrefs.sound(for: kind),
             category: "sooodreamy.\(kind.rawValue)",
             userInfo: link.map { [linkKey: $0] } ?? [:])
    }

    /// Requests authorization if needed and schedules an immediate
    /// UNNotificationRequest (0.1 s trigger).
    static func post(title: String, body: String,
                     sound: NotificationSound = .soft,
                     category: String? = nil,
                     userInfo: [String: Any] = [:]) {
        Task {
            guard await requestAuthorizationIfNeeded() else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = sound.unSound
            if let category { content.categoryIdentifier = category }
            if !userInfo.isEmpty { content.userInfo = userInfo }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
            let request = UNNotificationRequest(identifier: "sooodreamy.alert.\(UUID().uuidString)",
                                                content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }
}

// MARK: - Foreground presentation & taps

/// Shows banner + sound while the app is in the foreground and routes
/// notification taps to their deep link (userInfo["link"] = "sooodreamy://…").
/// Installed as UNUserNotificationCenter delegate at app launch.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Set at launch (SoooDreamyApp); receives the tapped notification's URL.
    var onOpenLink: (@MainActor (URL) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[CoupleNotify.linkKey] as? String,
              let url = URL(string: raw),
              let open = onOpenLink else { return }
        await MainActor.run { open(url) }
    }
}

// MARK: - Daily reminder

/// Repeating local reminder for the question of the day (uses the user's
/// selected notification sound).
enum ReminderManager {
    static let identifier = "sooodreamy.dailyReminder"
    private static let enabledKey = "sooodreamy.dailyReminderEnabled"
    private static let hourKey = "sooodreamy.dailyReminderHour"
    private static let minuteKey = "sooodreamy.dailyReminderMinute"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Reminder time (default 20:00).
    static var time: (hour: Int, minute: Int) {
        let d = UserDefaults.standard
        let hour = d.object(forKey: hourKey) as? Int ?? 20
        let minute = d.object(forKey: minuteKey) as? Int ?? 0
        return (hour, minute)
    }

    static func setTime(hour: Int, minute: Int) async {
        UserDefaults.standard.set(hour, forKey: hourKey)
        UserDefaults.standard.set(minute, forKey: minuteKey)
        await rescheduleIfNeeded()
    }

    /// Re-schedules the pending reminder (after time or sound changes).
    static func rescheduleIfNeeded() async {
        if isEnabled {
            _ = await setEnabled(true)
        }
    }

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        if enabled {
            guard await CoupleNotify.requestAuthorizationIfNeeded() else {
                UserDefaults.standard.set(false, forKey: enabledKey)
                return false
            }
            let content = UNMutableNotificationContent()
            content.title = L10n.isGerman ? "Frage des Tages 💌" : "Question of the day 💌"
            content.body = L10n.isGerman
                ? "Eure heutige Frage wartet — was wohl dein Schatz antwortet?"
                : "Today's question is waiting — what will your sweetheart answer?"
            content.sound = NotificationPrefs.globalSound.unSound
            content.userInfo = [CoupleNotify.linkKey: "sooodreamy://daily"]
            var comps = DateComponents()
            comps.hour = time.hour
            comps.minute = time.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
            UserDefaults.standard.set(true, forKey: enabledKey)
            return true
        } else {
            UserDefaults.standard.set(false, forKey: enabledKey)
            return true
        }
    }

    // MARK: Streak guard ("streak at risk" late-evening nudge)

    static let streakIdentifier = "sooodreamy.streakReminder"
    private static let streakEnabledKey = "sooodreamy.streakReminderEnabled"

    /// Fixed late-evening slot — deliberately after the regular reminder's
    /// default (20:00), acting as a last call before the day (and streak) ends.
    static let streakGuardHour = 21
    static let streakGuardMinute = 30

    static var isStreakGuardEnabled: Bool {
        UserDefaults.standard.bool(forKey: streakEnabledKey)
    }

    static func setStreakGuardEnabled(_ enabled: Bool, entry: DailyEntry?) async -> Bool {
        if enabled {
            guard await CoupleNotify.requestAuthorizationIfNeeded() else {
                UserDefaults.standard.set(false, forKey: streakEnabledKey)
                return false
            }
        }
        UserDefaults.standard.set(enabled, forKey: streakEnabledKey)
        await syncStreakGuard(entry: entry)
        return true
    }

    /// (Re-)schedules tonight's ONE-SHOT "streak at risk" nudge from the
    /// latest daily entry. Called on every dailyEntry change: answering
    /// today's question cancels it, an unanswered day with a running streak
    /// re-arms it. The server keeps yesterday's streak alive until midnight,
    /// so `streak > 0` + `myAnswer == nil` is exactly the at-risk state.
    static func syncStreakGuard(entry: DailyEntry?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [streakIdentifier])
        guard isStreakGuardEnabled,
              let entry,
              entry.dateKey == SharedDates.todayKey(),
              entry.myAnswer == nil,
              entry.streak > 0 else { return }
        // Only schedule while tonight's slot is still ahead — firing
        // tomorrow about "today's" streak would be misleading.
        var comps = SharedDates.calendar.dateComponents([.year, .month, .day], from: Date())
        comps.hour = streakGuardHour
        comps.minute = streakGuardMinute
        guard let fireDate = SharedDates.calendar.date(from: comps),
              fireDate.timeIntervalSinceNow > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.t("notif.streak.title")
        content.body = L10n.t("notif.streak.body", ["n": String(entry.streak)])
        content.sound = NotificationPrefs.globalSound.unSound
        content.userInfo = [CoupleNotify.linkKey: "sooodreamy://daily"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSinceNow,
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: streakIdentifier,
                                            content: content, trigger: trigger)
        try? await center.add(request)
    }
}

// MARK: - Coupon expiry reminders ("expiring soon")

/// One-shot local nudges for unredeemed coupons gifted TO me that expire
/// soon. Local-only like everything above: (re-)synced whenever the coupon
/// list loads or changes (CouponsView), so redeeming/deleting a coupon
/// naturally cancels its pending reminder.
enum CouponReminder {
    /// Pending-request identifier per coupon: "sooodreamy.couponExpiry.<id>".
    static let identifierPrefix = "sooodreamy.couponExpiry."
    private static let enabledKey = "sooodreamy.couponExpiryReminderEnabled"

    /// Only coupons expiring within this window get a reminder scheduled.
    /// Sync runs on every coupons load, so a far-away expiry is picked up
    /// once it slides into the window.
    static let expiringSoonWindow: TimeInterval = 48 * 3600
    /// Preferred lead time before expiry …
    static let primaryLead: TimeInterval = 24 * 3600
    /// … and the "last call" lead when less than a day remains.
    static let lastCallLead: TimeInterval = 3600

    /// On by default — the master alerts switch and the per-kind `.coupon`
    /// toggle still gate the actual scheduling (see `sync`).
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Settings toggle entry point — mirrors ReminderManager.setEnabled:
    /// requests permission when turning on, then re-syncs from the given list.
    static func setEnabled(_ enabled: Bool, coupons: [Coupon], myMemberId: String?) async -> Bool {
        if enabled {
            guard await CoupleNotify.requestAuthorizationIfNeeded() else {
                isEnabled = false
                return false
            }
        }
        isEnabled = enabled
        await sync(coupons: coupons, myMemberId: myMemberId)
        return true
    }

    /// When the reminder for a coupon should fire — nil when none should
    /// pend (redeemed, no/near/passed expiry, or outside the 48 h window).
    static func fireDate(for coupon: Coupon, now: Date = Date()) -> Date? {
        guard coupon.redeemedAt == nil,
              let expiresAt = coupon.expiresAt,
              expiresAt > now,
              expiresAt.timeIntervalSince(now) <= expiringSoonWindow else { return nil }
        let primary = expiresAt.addingTimeInterval(-primaryLead)
        if primary > now { return primary }
        let lastCall = expiresAt.addingTimeInterval(-lastCallLead)
        // Under an hour left: skip — the user just saw the live countdown chip.
        return lastCall > now ? lastCall : nil
    }

    /// Replaces ALL pending coupon reminders with fresh ones for the coupons
    /// currently expiring soon. Cheap enough to call on every list change.
    static func sync(coupons: [Coupon], myMemberId: String?) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard isEnabled, NotificationPrefs.enabled, NotificationPrefs.isEnabled(.coupon),
              let myMemberId else { return }
        let now = Date()
        let expiring = coupons
            .filter { $0.forMember == myMemberId }
            .compactMap { coupon in fireDate(for: coupon, now: now).map { (coupon, $0) } }
        guard !expiring.isEmpty, await CoupleNotify.requestAuthorizationIfNeeded() else { return }
        for (coupon, fireAt) in expiring {
            let content = UNMutableNotificationContent()
            content.title = L10n.t("notif.couponExpiry.title")
            content.body = L10n.t("notif.couponExpiry.body", ["title": coupon.title])
            content.sound = NotificationPrefs.sound(for: .coupon).unSound
            content.userInfo = [CoupleNotify.linkKey: "sooodreamy://coupons"]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: fireAt.timeIntervalSince(now), repeats: false)
            let request = UNNotificationRequest(identifier: identifierPrefix + coupon.id,
                                                content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
