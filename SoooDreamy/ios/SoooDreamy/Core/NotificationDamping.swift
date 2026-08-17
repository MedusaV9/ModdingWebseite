import Foundation

/// Priority classes for couple alerts (Linse 11): heartbeats may interrupt,
/// conversation arrives as a normal banner, ambient info only slips silently
/// into the notification list. Keyed by `CoupleAlertKind.rawValue` so the
/// table stays pure Foundation and Linux-testable.
enum NotificationPriorityClass: String {
    case heartbeat, conversation, ambient

    static func classify(kindRawValue: String) -> NotificationPriorityClass {
        switch kindRawValue {
        case "touch", "coupon":
            return .heartbeat
        case "message", "photo":
            return .conversation
        case "dailyReveal", "partnerOnline":
            return .ambient
        default:
            return .conversation
        }
    }
}

/// Sleep-mode damping (Linse 11): while MY presence mode is `sleep`, the app
/// already promises the sender "it won't wake them" — these pure helpers
/// make that promise true and plan the morning catch-up summary.
enum SleepQuietHours {
    /// Quiet while a sleep window is active. `sleepUntil` is the announced
    /// wake time (`Date.distantFuture` for an open-ended sleep), nil when
    /// not sleeping at all.
    static func isQuiet(sleepUntil: Date?, now: Date = Date()) -> Bool {
        guard let sleepUntil else { return false }
        return sleepUntil > now
    }

    /// When the morning summary should fire: at the announced wake time when
    /// it is within a day, otherwise at the next 08:00.
    static func summaryFireDate(sleepUntil: Date?, now: Date,
                                calendar: Calendar = SharedDates.calendar) -> Date {
        if let sleepUntil, sleepUntil > now,
           sleepUntil.timeIntervalSince(now) <= 24 * 3600 {
            return sleepUntil
        }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = 8
        comps.minute = 0
        let todayMorning = calendar.date(from: comps) ?? now
        if todayMorning > now { return todayMorning }
        return calendar.date(byAdding: .day, value: 1, to: todayMorning) ?? now
    }

    /// Display order for the summary fragments (warmest first).
    static let summaryOrder = ["message", "touch", "photo", "coupon", "dailyReveal"]

    /// One warm sentence for the morning summary, e.g.
    /// "Über Nacht: 3 Nachrichten, 1 Berührung 💜" — nil when nothing arrived
    /// (no summary notification should exist then).
    static func summaryBody(counts: [String: Int], partnerName: String) -> String? {
        let fragments = summaryOrder.compactMap { key -> String? in
            guard let count = counts[key], count > 0 else { return nil }
            return L10n.t("notif.sleepSummary.part.\(key)", count: count)
        }
        guard !fragments.isEmpty else { return nil }
        return L10n.t("notif.sleepSummary.body",
                      ["items": fragments.joined(separator: ", "), "name": partnerName])
    }
}
