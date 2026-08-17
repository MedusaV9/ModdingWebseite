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

    /// Internal (not private) on purpose (Fix-Runde 4, S3): the archive's
    /// language-independent search index (`MemoriesL10n.searchTitleVariants`)
    /// iterates THIS list — its previous hand-copied twin would have
    /// silently starved the index the day an eleventh table joined here.
    static var tables: [[String: LText]] {
        [CoreStrings.table, ChatL10n.table, GamesL10n.table, MemoriesL10n.table, RitualsL10n.table,
         OnboardingL10n.table,
         SettingsL10n.table,
         PlatformL10n.table, IntelligenceL10n.table,
         PostfachL10n.table]
    }

    static func t(_ key: String) -> String {
        value(for: key)?.resolved(lang) ?? key
    }

    private static func value(for key: String) -> LText? {
        for table in tables {
            if let value = table[key] { return value }
        }
        return nil
    }

    /// Replaces `{placeholders}` with values: `L10n.t("home.hello", ["name": "Mia"])`.
    /// Every argument also provides a genitive twin: `{nameGen}` resolves to
    /// `genitive(args["name"])` — "Mias Tag", but "Jonas' Tag" (see below).
    static func t(_ key: String, _ args: [String: String]) -> String {
        var s = t(key)
        for (k, v) in args {
            if s.contains("{\(k)Gen}") {
                s = s.replacingOccurrences(of: "{\(k)Gen}", with: genitive(v))
            }
            // The lowercase partner fallback („dein Schatz“) capitalizes
            // itself at sentence starts — "Dein Schatz ist da!" instead of
            // "dein Schatz ist da!". Real names are unaffected.
            var value = v
            if s.hasPrefix("{\(k)}"), v == t("misc.partnerDefault"),
               let first = v.first {
                value = first.uppercased() + v.dropFirst()
            }
            s = s.replacingOccurrences(of: "{\(k)}", with: value)
        }
        return s
    }

    /// Possessive form of a proper name, correct in both app languages.
    /// German: names ending in an s-sound (s/ß/x/z) take a bare apostrophe
    /// („Jonas' Tag“, „Felix' Gewässer“), everyone else a plain s („Mias Tag“).
    /// English: "Mia's", but "Jonas'". The neutral partner fallback
    /// („dein Schatz“) declines properly instead of getting an apostrophe.
    static func genitive(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.lowercased().last else { return trimmed }
        if trimmed == t("misc.partnerDefault") { return t("misc.partnerDefaultGen") }
        let endsInSibilant = "sßxz".contains(last)
        if isGerman {
            return endsInSibilant ? trimmed + "'" : trimmed + "s"
        }
        return endsInSibilant ? trimmed + "'" : trimmed + "'s"
    }

    /// Minimal DE/EN cardinal plural selection. Tables provide `.one` and
    /// `.other` variants; `{count}` and any additional placeholders are
    /// replaced after selecting the variant.
    static func t(
        _ key: String,
        count: Int,
        _ args: [String: String] = [:]
    ) -> String {
        let variantKey = "\(key).\(count == 1 ? "one" : "other")"
        var resolved = value(for: variantKey)?.resolved(lang)
            ?? value(for: key)?.resolved(lang)
            ?? key
        var values = args
        values["count"] = AppFormatters.integer(count, language: lang)
        values["n"] = values["count"]
        for (placeholder, value) in values {
            if resolved.contains("{\(placeholder)Gen}") {
                resolved = resolved.replacingOccurrences(
                    of: "{\(placeholder)Gen}", with: genitive(value))
            }
            resolved = resolved.replacingOccurrences(of: "{\(placeholder)}", with: value)
        }
        return resolved
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
