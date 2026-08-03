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
}
