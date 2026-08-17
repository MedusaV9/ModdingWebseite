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
    /// W7/35-Rest: active app-icon id ("classic", "sunset", …) mirrored for
    /// the "Passend zum Icon" widget theme — the widget process cannot ask
    /// UIApplication for the alternate icon itself.
    static let appIconKey = "sooodreamy.appIcon.v1"

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

    static func writeAppIconId(_ id: String) {
        defaults.set(id, forKey: appIconKey)
    }

    static func readAppIconId() -> String? {
        defaults.string(forKey: appIconKey)
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
    var partnerEnergyLevel: String?
    var partnerEnergyNote: String?
    var partnerEnergySetAt: Date?
    /// Presence mode ("focus"/"sleep") — check `partnerPresenceUntil`
    /// before showing; a passed expiry means "available" again.
    var partnerPresenceMode: String?
    var partnerPresenceUntil: Date?
    var partnerOnline: Bool?
    var myName: String?
    /// W7: MY OWN presence mode mirrored for the sleep-toggle control —
    /// the only control with real on/off state. Written by the app on every
    /// snapshot and patched directly by presence intents/controls.
    var myPresenceMode: String?
    var myPresenceUntil: Date?
    var couplePalettePrimary: String?
    var couplePaletteSecondary: String?
    var couplePaletteAccent: String?
    var couplePaletteOnAccent: String?
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
    /// All upcoming moments (soonest first) — lets the countdown widget be
    /// pinned to a specific event. Optional: pre-2.0 snapshots decode fine.
    var allEvents: [WidgetEventLite]?
    /// v4 compact shared-goal card.
    var goalTitle: String?
    var goalEmoji: String?
    var goalPercent: Double?
    /// Relationship level — optional so pre-3.0 snapshots
    /// decode fine; widgets hide the ring when nil.
    var levelNumber: Int?
    var levelTitleDE: String?
    var levelTitleEN: String?
    var levelProgress: Double?
    /// „An diesem Tag" — the closest memory of today for the memory
    /// widget. `memoryDateKey` names the day the data refers to, so the
    /// widget hides yesterday's memory after midnight instead of lying.
    var memoryDateKey: String?
    var memoryKind: String?           // "photo" | "daily"
    var memoryDistanceUnit: String?   // "months" | "years"
    var memoryDistanceN: Int?
    var memoryLineDE: String?
    var memoryLineEN: String?
    var memoryPhotoURLString: String?
    var memoryCount: Int?
    /// W7-Rest reveal seal: both answered today, but the ceremony is still
    /// sealed on THIS device. `dailyRevealDateKey` names the day the flag
    /// refers to (widgets drop the seal after midnight instead of glowing
    /// for yesterday); `coupleId` lets the widget process re-check
    /// `RevealedDailyStore` live, so breaking the seal in the app flips the
    /// widgets on their next render even before a snapshot rewrite.
    var coupleId: String?
    var dailyRevealPending: Bool?
    var dailyRevealDateKey: String?
    var updatedAt: Date

    init(partnerName: String? = nil, partnerAvatar: String? = nil, partnerColorHex: String? = nil,
         partnerMood: String? = nil, partnerMoodNote: String? = nil, partnerMoodUpdatedAt: Date? = nil,
         partnerEnergyLevel: String? = nil, partnerEnergyNote: String? = nil,
         partnerEnergySetAt: Date? = nil,
         partnerPresenceMode: String? = nil,
         partnerPresenceUntil: Date? = nil,
         partnerOnline: Bool? = nil,
         myName: String? = nil, anniversary: String? = nil, daysTogether: Int? = nil,
         nextEventTitle: String? = nil, nextEventEmoji: String? = nil, nextEventDate: String? = nil,
         dailyQuestionDE: String? = nil, dailyQuestionEN: String? = nil,
         dailyAnsweredByMe: Bool = false, dailyBothAnswered: Bool = false,
         streak: Int = 0, photoURLString: String? = nil, photoCaption: String? = nil,
         lastTouchType: String? = nil, lastTouchAt: Date? = nil,
         canvasStrokeCount: Int = 0,
         allEvents: [WidgetEventLite]? = nil,
         goalTitle: String? = nil, goalEmoji: String? = nil, goalPercent: Double? = nil,
         updatedAt: Date = Date()) {
        self.partnerName = partnerName
        self.partnerAvatar = partnerAvatar
        self.partnerColorHex = partnerColorHex
        self.partnerMood = partnerMood
        self.partnerMoodNote = partnerMoodNote
        self.partnerMoodUpdatedAt = partnerMoodUpdatedAt
        self.partnerEnergyLevel = partnerEnergyLevel
        self.partnerEnergyNote = partnerEnergyNote
        self.partnerEnergySetAt = partnerEnergySetAt
        self.partnerPresenceMode = partnerPresenceMode
        self.partnerPresenceUntil = partnerPresenceUntil
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
        self.allEvents = allEvents
        self.goalTitle = goalTitle
        self.goalEmoji = goalEmoji
        self.goalPercent = goalPercent
        self.updatedAt = updatedAt
    }

    /// v10 performance pass: a stable byte signature of the CONTENT (the
    /// write timestamp is zeroed out first). The app compares signatures and
    /// skips `WidgetCenter.reloadAllTimelines()` when nothing the widgets can
    /// see actually changed — every socket event used to trigger a reload.
    /// Sorted keys make the encoding deterministic across processes/runs.
    var contentSignature: Data? {
        var stable = self
        stable.updatedAt = Date(timeIntervalSince1970: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(stable)
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
