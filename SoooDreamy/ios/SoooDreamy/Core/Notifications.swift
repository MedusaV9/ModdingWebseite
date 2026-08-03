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
}
