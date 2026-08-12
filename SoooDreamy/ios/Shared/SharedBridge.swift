import Foundation

/// Data bridge between the app and the widget extension.
/// Uses the shared app group when available (proper re-signing with app-group
/// entitlements, e.g. via AltStore/SideStore) and falls back to standard
/// defaults so nothing crashes in a plain unsigned sideload.
enum SharedStore {
    static let appGroupId = "group.app.sooodreamy.shared"
    static let snapshotKey = "sooodreamy.widgetSnapshot.v1"
    static let languageKey = "sooodreamy.language"
    static let widgetPrefsKey = "sooodreamy.widgetPrefs.v1"
    static let photoCacheName = "widget-photo-cache.jpg"
    static let canvasStrokesKey = "sooodreamy.canvasStrokes.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    static var containerURL: URL? {
        #if canImport(Darwin)
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
        #else
        return nil   // Linux (SwiftPM logic tests): no app-group containers
        #endif
    }

    static func writeSnapshot(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func writePrefs(_ prefs: WidgetPrefs) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: widgetPrefsKey)
        }
    }

    static func readPrefs() -> WidgetPrefs {
        guard let data = defaults.data(forKey: widgetPrefsKey),
              let prefs = try? JSONDecoder().decode(WidgetPrefs.self, from: data) else {
            return WidgetPrefs()
        }
        return prefs
    }

    static func writeCanvasStrokes(_ strokes: [WidgetCanvasStroke]) {
        if let data = try? JSONEncoder().encode(strokes) {
            defaults.set(data, forKey: canvasStrokesKey)
        }
    }

    static func readCanvasStrokes() -> [WidgetCanvasStroke] {
        guard let data = defaults.data(forKey: canvasStrokesKey),
              let strokes = try? JSONDecoder().decode([WidgetCanvasStroke].self, from: data) else {
            return []
        }
        return strokes
    }

    static func writeCachedPhotoJPEG(_ data: Data) {
        if let url = containerURL?.appendingPathComponent(photoCacheName) {
            try? data.write(to: url, options: .atomic)
        }
        // Also stash in defaults as last-resort when app group container is unavailable.
        defaults.set(data, forKey: "sooodreamy.photoCache.blob")
    }

    static func readCachedPhotoJPEG() -> Data? {
        if let url = containerURL?.appendingPathComponent(photoCacheName),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return defaults.data(forKey: "sooodreamy.photoCache.blob")
    }

    /// "de" or "en" — resolved app language, readable from the widget process.
    static var resolvedLanguage: String {
        get {
            if let stored = defaults.string(forKey: languageKey), stored == "de" || stored == "en" {
                return stored
            }
            return Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
        }
        set { defaults.set(newValue, forKey: languageKey) }
    }
}

/// User-configurable widget look (background style + accent). Written from Settings.
struct WidgetPrefs: Codable, Hashable {
    /// night | sunset | ocean | blush | photo | mono
    var background: String
    /// When true, photo/canvas widgets prefer the showcase photo as the chrome background.
    var usePhotoChrome: Bool

    init(background: String = "night", usePhotoChrome: Bool = false) {
        self.background = background
        self.usePhotoChrome = usePhotoChrome
    }
}

/// Compact stroke for the canvas widget (normalized points, capped client-side).
struct WidgetCanvasStroke: Codable, Hashable, Identifiable {
    var id: String
    var color: String
    var width: Double
    var tool: String
    var points: [[Double]]
}

/// Everything the widgets need to render, written by the app.
struct WidgetSnapshot: Codable {
    var partnerName: String?
    var partnerAvatar: String?
    var partnerColorHex: String?
    var partnerMood: String?
    var partnerMoodNote: String?
    var partnerMoodUpdatedAt: Date?
    var partnerOnline: Bool?
    var myName: String?
    var anniversary: String?          // "YYYY-MM-DD"
    var daysTogether: Int?
    var nextEventTitle: String?
    var nextEventEmoji: String?
    var nextEventDate: String?        // "YYYY-MM-DD"
    var dailyQuestionDE: String?
    var dailyQuestionEN: String?
    var dailyAnsweredByMe: Bool
    var dailyBothAnswered: Bool
    var streak: Int
    /// Authed absolute URL of the couple's showcase photo (newest favorite,
    /// else newest photo; thumbnail preferred) — for the photo widget.
    var photoURLString: String?
    var photoCaption: String?
    var lastTouchType: String?
    var lastTouchAt: Date?
    var canvasStrokeCount: Int
    var updatedAt: Date

    init(partnerName: String? = nil, partnerAvatar: String? = nil, partnerColorHex: String? = nil,
         partnerMood: String? = nil, partnerMoodNote: String? = nil, partnerMoodUpdatedAt: Date? = nil,
         partnerOnline: Bool? = nil,
         myName: String? = nil, anniversary: String? = nil, daysTogether: Int? = nil,
         nextEventTitle: String? = nil, nextEventEmoji: String? = nil, nextEventDate: String? = nil,
         dailyQuestionDE: String? = nil, dailyQuestionEN: String? = nil,
         dailyAnsweredByMe: Bool = false, dailyBothAnswered: Bool = false,
         streak: Int = 0, photoURLString: String? = nil, photoCaption: String? = nil,
         lastTouchType: String? = nil, lastTouchAt: Date? = nil,
         canvasStrokeCount: Int = 0,
         updatedAt: Date = Date()) {
        self.partnerName = partnerName
        self.partnerAvatar = partnerAvatar
        self.partnerColorHex = partnerColorHex
        self.partnerMood = partnerMood
        self.partnerMoodNote = partnerMoodNote
        self.partnerMoodUpdatedAt = partnerMoodUpdatedAt
        self.partnerOnline = partnerOnline
        self.myName = myName
        self.anniversary = anniversary
        self.daysTogether = daysTogether
        self.nextEventTitle = nextEventTitle
        self.nextEventEmoji = nextEventEmoji
        self.nextEventDate = nextEventDate
        self.dailyQuestionDE = dailyQuestionDE
        self.dailyQuestionEN = dailyQuestionEN
        self.dailyAnsweredByMe = dailyAnsweredByMe
        self.dailyBothAnswered = dailyBothAnswered
        self.streak = streak
        self.photoURLString = photoURLString
        self.photoCaption = photoCaption
        self.lastTouchType = lastTouchType
        self.lastTouchAt = lastTouchAt
        self.canvasStrokeCount = canvasStrokeCount
        self.updatedAt = updatedAt
    }
}

/// Small date helpers shared by app + widgets (calendar-date strings, day math).
enum SharedDates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Today as "YYYY-MM-DD" (local time).
    static func todayKey(_ now: Date = Date()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func parse(_ key: String?) -> Date? {
        guard let key else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        return calendar.date(from: comps)
    }

    /// Whole days from `from` (a "YYYY-MM-DD") until today; e.g. days together.
    static func daysSince(_ key: String?, now: Date = Date()) -> Int? {
        guard let start = parse(key) else { return nil }
        let startDay = calendar.startOfDay(for: start)
        let today = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: startDay, to: today).day
    }

    /// Days from today until the date (next occurrence if repeatsYearly).
    static func daysUntil(_ key: String?, repeatsYearly: Bool = false, now: Date = Date()) -> Int? {
        guard var target = parse(key) else { return nil }
        let today = calendar.startOfDay(for: now)
        if repeatsYearly {
            while calendar.startOfDay(for: target) < today {
                guard let next = calendar.date(byAdding: .year, value: 1, to: target) else { break }
                target = next
            }
        }
        return calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: target)).day
    }

    /// Next occurrence of an event date as a real Date (for Live Activities).
    static func nextOccurrence(_ key: String?, repeatsYearly: Bool = false, now: Date = Date()) -> Date? {
        guard var target = parse(key) else { return nil }
        if repeatsYearly {
            let today = calendar.startOfDay(for: now)
            while calendar.startOfDay(for: target) < today {
                guard let next = calendar.date(byAdding: .year, value: 1, to: target) else { break }
                target = next
            }
        }
        return target
    }
}
