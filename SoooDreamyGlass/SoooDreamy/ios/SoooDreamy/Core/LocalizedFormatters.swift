import Foundation

/// Locale-aware formatting tied to the in-app language rather than the
/// device language. Pure Foundation so Linux tests pin DE/EN behavior.
///
/// Formatters are served from a static cache keyed on their full
/// configuration (language + style/template + time zone): creating a
/// DateFormatter compiles ICU patterns and is among the most expensive
/// Foundation calls, while list screens format dozens of dates per pass.
/// Cached instances are configured exactly once and never mutated
/// afterwards (the time zone is part of the key), so handing the same
/// instance out repeatedly is safe; the dictionaries are lock-guarded.
enum AppFormatters {
    static func locale(for language: String) -> Locale {
        Locale(identifier: language == "de" ? "de_DE" : "en_US")
    }

    // MARK: - Formatter cache

    private static let cacheLock = NSLock()
    private static var dateFormatters: [String: DateFormatter] = [:]
    private static var numberFormatters: [String: NumberFormatter] = [:]

    private static func cachedDateFormatter(
        key: String, make: () -> DateFormatter
    ) -> DateFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = dateFormatters[key] { return cached }
        let formatter = make()
        dateFormatters[key] = formatter
        return formatter
    }

    /// Internal (not private) so the logic tests can pin cache-hit identity.
    static func dateFormatter(
        language: String,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style,
        timeZone: TimeZone
    ) -> DateFormatter {
        let key = "style|\(language)|\(dateStyle.rawValue)|\(timeStyle.rawValue)|\(timeZone.identifier)"
        return cachedDateFormatter(key: key) {
            let formatter = DateFormatter()
            formatter.locale = locale(for: language)
            formatter.timeZone = timeZone
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter
        }
    }

    /// Internal (not private) so the logic tests can pin cache-hit identity.
    static func templateDateFormatter(
        language: String,
        template: String,
        timeZone: TimeZone
    ) -> DateFormatter {
        let key = "template|\(language)|\(template)|\(timeZone.identifier)"
        return cachedDateFormatter(key: key) {
            let formatter = DateFormatter()
            formatter.locale = locale(for: language)
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        }
    }

    /// Internal (not private) so the logic tests can pin cache-hit identity.
    static func numberFormatter(
        language: String,
        maximumFractionDigits: Int
    ) -> NumberFormatter {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let key = "\(language)|\(maximumFractionDigits)"
        if let cached = numberFormatters[key] { return cached }
        let formatter = NumberFormatter()
        formatter.locale = locale(for: language)
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        numberFormatters[key] = formatter
        return formatter
    }

    // MARK: - Formatting API (signatures unchanged)

    static func date(
        _ date: Date,
        language: String,
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style = .none,
        timeZone: TimeZone = .current
    ) -> String {
        dateFormatter(language: language, dateStyle: dateStyle,
                      timeStyle: timeStyle, timeZone: timeZone)
            .string(from: date)
    }

    static func monthYear(
        _ date: Date,
        language: String,
        timeZone: TimeZone = .current
    ) -> String {
        templateDateFormatter(language: language, template: "LLLL yyyy",
                              timeZone: timeZone)
            .string(from: date)
    }

    static func dateTemplate(
        _ date: Date,
        template: String,
        language: String,
        timeZone: TimeZone = .current
    ) -> String {
        templateDateFormatter(language: language, template: template,
                              timeZone: timeZone)
            .string(from: date)
    }

    static func veryShortWeekdaySymbols(language: String) -> [String] {
        // Reading symbols never mutates the formatter — one per language.
        let formatter = cachedDateFormatter(key: "symbols|\(language)") {
            let formatter = DateFormatter()
            formatter.locale = locale(for: language)
            return formatter
        }
        return formatter.veryShortWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    static func integer(_ value: Int, language: String) -> String {
        numberFormatter(language: language, maximumFractionDigits: 0)
            .string(from: NSNumber(value: value)) ?? String(value)
    }

    static func decimal(
        _ value: Double,
        language: String,
        maximumFractionDigits: Int = 2
    ) -> String {
        numberFormatter(language: language,
                        maximumFractionDigits: maximumFractionDigits)
            .string(from: NSNumber(value: value)) ?? String(value)
    }

    static func duration(minutes: Int, language: String) -> String {
        // Explicit because DateComponentsFormatter follows the process locale
        // on Linux instead of the app's independent language setting.
        if minutes < 60 {
            return language == "de" ? "\(max(0, minutes)) Min." : "\(max(0, minutes)) min"
        }
        let hours = max(0, minutes) / 60
        let rest = max(0, minutes) % 60
        if rest == 0 {
            return language == "de" ? "\(hours) Std." : "\(hours) hr"
        }
        return language == "de"
            ? "\(hours) Std. \(rest) Min."
            : "\(hours) hr \(rest) min"
    }
}
