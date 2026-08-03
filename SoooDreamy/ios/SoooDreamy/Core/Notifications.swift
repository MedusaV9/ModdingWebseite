import Foundation
import UserNotifications

/// Local notifications: a gentle daily reminder for the question of the day.
/// (Remote push is not possible with an unsigned sideloaded build, realtime
/// happens via WebSocket while the app is open.)
enum ReminderManager {
    static let identifier = "sooodreamy.dailyReminder"
    private static let enabledKey = "sooodreamy.dailyReminderEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
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
            comps.hour = 20
            comps.minute = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
            UserDefaults.standard.set(true, forKey: enabledKey)
            return true
        } else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            UserDefaults.standard.set(false, forKey: enabledKey)
            return true
        }
    }
}
