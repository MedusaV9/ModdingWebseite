import Foundation
import UserNotifications

/// Local notifications: a gentle daily reminder for the question of the day.
/// (Remote push is not possible with an unsigned sideloaded build, realtime
/// happens via WebSocket while the app is open.)
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
        if isEnabled {
            _ = await setEnabled(true)   // reschedule with the new time
        }
    }

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        if enabled {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else {
                UserDefaults.standard.set(false, forKey: enabledKey)
                return false
            }
            let content = UNMutableNotificationContent()
            content.title = L10n.isGerman ? "Frage des Tages 💌" : "Question of the day 💌"
            content.body = L10n.isGerman
                ? "Eure heutige Frage wartet — was wohl dein Schatz antwortet?"
                : "Today's question is waiting — what will your sweetheart answer?"
            content.sound = .default
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
