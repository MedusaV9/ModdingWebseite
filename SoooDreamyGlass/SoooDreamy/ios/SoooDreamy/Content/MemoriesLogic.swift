import Foundation

/// Pure logic for the „Erinnerungen" features — mirrors
/// `server/src/memories.js` bit-for-bit so both phones and the server
/// always agree on what counts as an "on this day" memory.
enum MemoriesLogic {

    // MARK: - month math (server mirror)

    /// Whole months from `past` to `now` when both share the SAME
    /// day-of-month, else nil. Returns n >= 1 only for genuinely past dates.
    static func monthsBackSameDay(past: String, now: String) -> Int? {
        guard past.count == 10, now.count == 10,
              let py = Int(past.prefix(4)), let pm = Int(past.dropFirst(5).prefix(2)),
              let pd = Int(past.dropFirst(8).prefix(2)),
              let ny = Int(now.prefix(4)), let nm = Int(now.dropFirst(5).prefix(2)),
              let nd = Int(now.dropFirst(8).prefix(2)) else { return nil }
        guard pd == nd else { return nil }
        let months = (ny * 12 + nm) - (py * 12 + pm)
        return months >= 1 ? months : nil
    }

    struct Distance: Equatable {
        let unit: String   // "months" | "years"
        let n: Int
    }

    /// Whole years collapse (24 months → 2 years) — matches the server.
    static func distance(fromMonths months: Int) -> Distance {
        months % 12 == 0
            ? Distance(unit: "years", n: months / 12)
            : Distance(unit: "months", n: months)
    }

    /// L10n key + count for a "{n} months/years ago" label.
    /// Keys: memories.ago.month / .months / .year / .years (all take {n}).
    static func agoLabelKey(unit: String, n: Int) -> String {
        if unit == "years" {
            return n == 1 ? "memories.ago.year" : "memories.ago.years"
        }
        return n == 1 ? "memories.ago.month" : "memories.ago.months"
    }

    /// L10n key for the monthiversary celebration line ("today marks n
    /// months/years together") — NOT the "ago" phrasing, because the server
    /// sends the same {unit, n} shape for both.
    /// Keys: onthisday.monthiversary.month / .months / .year / .years.
    static func monthiversaryLabelKey(unit: String, n: Int) -> String {
        if unit == "years" {
            return n == 1 ? "onthisday.monthiversary.year" : "onthisday.monthiversary.years"
        }
        return n == 1 ? "onthisday.monthiversary.month" : "onthisday.monthiversary.months"
    }

    // MARK: - gallery month sections

    struct GalleryMonthGroup: Equatable {
        /// "2026-08" — sortable, locale-free; the view renders the label.
        let monthKey: String
        let photoIds: [String]
    }

    /// Groups photos into month sections while keeping the caller's order
    /// inside each month (the gallery passes newest-first, so months come
    /// out newest-first too). `date` is `takenAt ?? createdAt` — the moment
    /// the photo HAPPENED, not the upload time. The key is derived in the
    /// given time zone — photos belong to the wall-clock month the couple
    /// experienced, not the UTC one.
    static func galleryMonthGroups(photos: [(id: String, date: Date)],
                                   timeZone: TimeZone) -> [GalleryMonthGroup] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var order: [String] = []
        var byMonth: [String: [String]] = [:]
        for photo in photos {
            let comps = calendar.dateComponents([.year, .month], from: photo.date)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(photo.id)
        }
        return order.map { GalleryMonthGroup(monthKey: $0, photoIds: byMonth[$0] ?? []) }
    }

    // MARK: - story timeline presentation

    /// "2026-08-13" → "2026-08" (chapter grouping key).
    static func monthKey(of dateKey: String) -> String {
        String(dateKey.prefix(7))
    }

    /// Every server story kind maps to an emoji + a title L10n key.
    /// Count milestones ({n}) and badges resolve their details in the view.
    static let storyKinds: [String: (emoji: String, titleKey: String)] = [
        "begin": ("💞", "story.kind.begin"),
        "paired": ("🔗", "story.kind.paired"),
        "first_message": ("💬", "story.kind.first_message"),
        "first_photo": ("📸", "story.kind.first_photo"),
        "first_video": ("🎬", "story.kind.first_video"),
        "first_game": ("🎮", "story.kind.first_game"),
        "first_daily": ("❓", "story.kind.first_daily"),
        "first_daymemo": ("🎙️", "story.kind.first_daymemo"),
        "first_capsule": ("💌", "story.kind.first_capsule"),
        "first_hug": ("🫂", "story.kind.first_hug"),
        "first_goal": ("🏁", "story.kind.first_goal"),
        "photos_milestone": ("🌟", "story.kind.photos_milestone"),
        "messages_milestone": ("💬", "story.kind.messages_milestone"),
        "daily_milestone": ("🔥", "story.kind.daily_milestone"),
        "badge": ("🏅", "story.kind.badge"),
    ]

    /// Unknown future kinds render honestly as a generic memory instead of
    /// being silently dropped or mislabeled.
    static func presentation(forKind kind: String) -> (emoji: String, titleKey: String) {
        storyKinds[kind] ?? ("✨", "story.kind.unknown")
    }

    /// Orders month chapters newest-first while keeping entries inside a
    /// chapter in their chronological (server) order.
    static func chapters(entryDateKeys: [String]) -> [String] {
        var seen = Set<String>()
        var months: [String] = []
        for dateKey in entryDateKeys {
            let month = monthKey(of: dateKey)
            if seen.insert(month).inserted { months.append(month) }
        }
        return months.reversed()
    }
}
