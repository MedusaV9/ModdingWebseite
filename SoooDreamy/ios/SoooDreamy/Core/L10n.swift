import Foundation

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case system, de, en
    var id: String { rawValue }

    var resolved: String {
        switch self {
        case .de: return "de"
        case .en: return "en"
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
        }
    }

    var displayNameKey: String { "language.\(rawValue)" }
}

/// Tiny in-app localization engine (German/English), switchable at runtime.
/// Feature areas contribute their own tables (see `tables`).
enum L10n {
    private static let storageKey = "sooodreamy.appLanguage"

    static var language: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let l = AppLanguage(rawValue: raw) {
            return l
        }
        return .system
    }() {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
            SharedStore.resolvedLanguage = language.resolved
        }
    }

    /// "de" or "en"
    static var lang: String { language.resolved }
    static var isGerman: Bool { lang == "de" }

    private static var tables: [[String: LText]] {
        [CoreStrings.table, ChatL10n.table, GamesL10n.table, MemoriesL10n.table]
    }

    static func t(_ key: String) -> String {
        for table in tables {
            if let v = table[key] { return v.resolved(lang) }
        }
        return key
    }

    /// Replaces `{placeholders}` with values: `L10n.t("home.hello", ["name": "Mia"])`.
    static func t(_ key: String, _ args: [String: String]) -> String {
        var s = t(key)
        for (k, v) in args {
            s = s.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return s
    }

    /// Compact relative time in the APP language — the system relative
    /// formatter follows the device locale, which can differ from the
    /// in-app language choice. "gerade eben" · "vor 5 Min." · "vor 3 Std."
    /// · "gestern" · "vor 4 Tagen" (and the English equivalents).
    static func relativeShort(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 90 { return t("time.justNow") }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return t("time.minutesAgo", ["n": String(minutes)]) }
        let hours = Int(seconds / 3600)
        if hours < 24 { return t("time.hoursAgo", ["n": String(hours)]) }
        let days = Int(seconds / 86400)
        if days == 1 { return t("time.yesterday") }
        return t("time.daysAgo", ["n": String(days)])
    }
}
