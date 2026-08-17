import Foundation

/// „Eure Woche" — pure ISO-8601 week math and card building.
///
/// Mirrors `server/src/weekreview.js` bit-for-bit: weeks are Monday-based ISO
/// weeks over plain `YYYY-MM-DD` dateKeys. All math runs on civil day numbers
/// (no `Calendar`, no time zones) so Linux CI, the simulator and the server
/// always agree on which week a day belongs to.
enum WeekReviewLogic {

    // MARK: - civil day-number math (Howard Hinnant's algorithms)

    /// Days since 1970-01-01 for a proleptic Gregorian date.
    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Inverse of `dayNumber`.
    static func civilDate(fromDayNumber z: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = z + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let doe = shifted - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp + (mp < 10 ? 3 : -9)
        return (month <= 2 ? y + 1 : y, month, day)
    }

    static func parseDateKey(_ dateKey: String) -> (year: Int, month: Int, day: Int)? {
        let parts = dateKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, dateKey.count == 10,
              (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    static func dateKey(fromDayNumber z: Int) -> String {
        let date = civilDate(fromDayNumber: z)
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    /// Weekday with Monday = 0 … Sunday = 6 (1970-01-01 was a Thursday).
    static func mondayBasedWeekday(ofDayNumber z: Int) -> Int {
        ((z + 3) % 7 + 7) % 7
    }

    // MARK: - ISO week keys

    /// "2026-08-13" → "2026-W33" (nil for malformed keys).
    static func weekKey(forDateKey dateKey: String) -> String? {
        guard let date = parseDateKey(dateKey) else { return nil }
        let z = dayNumber(year: date.year, month: date.month, day: date.day)
        // Shift to the ISO week's Thursday — its calendar year IS the ISO year.
        let thursday = z - mondayBasedWeekday(ofDayNumber: z) + 3
        let isoYear = civilDate(fromDayNumber: thursday).year
        let yearStart = dayNumber(year: isoYear, month: 1, day: 1)
        let week = (thursday - yearStart) / 7 + 1
        return String(format: "%04d-W%02d", isoYear, week)
    }

    /// "2026-W33" → "2026-08-10" (the week's Monday). Rejects invalid keys
    /// like a 53rd week in a 52-week year.
    static func startDateKey(ofWeek weekKey: String) -> String? {
        guard weekKey.count == 8, weekKey[weekKey.index(weekKey.startIndex, offsetBy: 4)] == "-",
              let year = Int(weekKey.prefix(4)),
              weekKey[weekKey.index(weekKey.startIndex, offsetBy: 5)] == "W",
              let week = Int(weekKey.suffix(2)), (1...53).contains(week) else { return nil }
        // Jan 4 is always inside ISO week 1.
        let jan4 = dayNumber(year: year, month: 1, day: 4)
        let monday = jan4 - mondayBasedWeekday(ofDayNumber: jan4) + (week - 1) * 7
        let key = dateKey(fromDayNumber: monday)
        return self.weekKey(forDateKey: key) == weekKey ? key : nil
    }

    /// The seven dateKeys (Mon…Sun) of a week, or [] for invalid keys.
    static func dateKeys(ofWeek weekKey: String) -> [String] {
        guard let start = startDateKey(ofWeek: weekKey),
              let date = parseDateKey(start) else { return [] }
        let z = dayNumber(year: date.year, month: date.month, day: date.day)
        return (0..<7).map { dateKey(fromDayNumber: z + $0) }
    }

    static func previousWeekKey(_ weekKey: String) -> String? {
        guard let start = startDateKey(ofWeek: weekKey),
              let date = parseDateKey(start) else { return nil }
        let z = dayNumber(year: date.year, month: date.month, day: date.day)
        return self.weekKey(forDateKey: dateKey(fromDayNumber: z - 7))
    }

    /// The most recent COMPLETED week (relative to `todayKey`) — the week the
    /// Sunday-evening ritual looks back on once a new week has started.
    static func lastCompletedWeekKey(todayKey: String) -> String? {
        guard let current = weekKey(forDateKey: todayKey) else { return nil }
        return previousWeekKey(current)
    }

    // MARK: - stat cards

    struct Stats: Equatable {
        var messages = 0
        var touches = 0
        var hugsSent = 0
        var photosAdded = 0
        var videosAdded = 0
        var gamesPlayed = 0
        var wordleDays = 0
        var dailyBothAnswered = 0
        var checkinDaysBoth = 0
        var daymemoDays = 0
        var questsDone = 0
        var perfectDays = 0
    }

    struct StatCard: Equatable, Identifiable {
        let id: String
        let emoji: String
        let titleKey: String
        let value: Int
    }

    /// Ordered liquid-glass cards for one week. The three ritual counters
    /// (perfect days, both-answered dailies, both check-in days) always show
    /// (even at 0 — the ritual invites), activity counters hide when 0.
    static func statCards(from stats: Stats) -> [StatCard] {
        let always: [StatCard] = [
            StatCard(id: "perfect", emoji: "✨", titleKey: "weekreview.stat.perfectDays", value: stats.perfectDays),
            StatCard(id: "daily", emoji: "❓", titleKey: "weekreview.stat.dailyBoth", value: stats.dailyBothAnswered),
            StatCard(id: "checkin", emoji: "🌙", titleKey: "weekreview.stat.checkinBoth", value: stats.checkinDaysBoth),
        ]
        let optional: [StatCard] = [
            StatCard(id: "messages", emoji: "💬", titleKey: "weekreview.stat.messages", value: stats.messages),
            StatCard(id: "touches", emoji: "💓", titleKey: "weekreview.stat.touches", value: stats.touches),
            StatCard(id: "games", emoji: "🎮", titleKey: "weekreview.stat.games", value: stats.gamesPlayed),
            StatCard(id: "photos", emoji: "📸", titleKey: "weekreview.stat.photos", value: stats.photosAdded),
            StatCard(id: "videos", emoji: "🎬", titleKey: "weekreview.stat.videos", value: stats.videosAdded),
            StatCard(id: "hugs", emoji: "🫂", titleKey: "weekreview.stat.hugs", value: stats.hugsSent),
            StatCard(id: "wordle", emoji: "🟩", titleKey: "weekreview.stat.wordle", value: stats.wordleDays),
            StatCard(id: "daymemos", emoji: "🎙️", titleKey: "weekreview.stat.daymemos", value: stats.daymemoDays),
            StatCard(id: "quests", emoji: "⚔️", titleKey: "weekreview.stat.quests", value: stats.questsDone),
        ]
        return always + optional.filter { $0.value > 0 }
    }

    // MARK: - dramaturgy (48#3: numbers should tell a story, not fill a grid)

    /// A week in which literally nothing happened — the review shows a
    /// dignified quiet-week card instead of a wall of zeros.
    static func isQuietWeek(_ stats: Stats) -> Bool {
        stats == Stats()
    }

    /// Stat cards ordered for storytelling: the two ritual counters lead
    /// (they always show — the ritual invites), then activity counters
    /// sorted by size so the loudest number of the week speaks first.
    /// Perfect days are NOT in here — they get their own hero card.
    static func dramaturgyCards(from stats: Stats) -> [StatCard] {
        let rituals: [StatCard] = [
            StatCard(id: "daily", emoji: "❓", titleKey: "weekreview.stat.dailyBoth", value: stats.dailyBothAnswered),
            StatCard(id: "checkin", emoji: "🌙", titleKey: "weekreview.stat.checkinBoth", value: stats.checkinDaysBoth),
        ]
        let activity: [StatCard] = [
            StatCard(id: "messages", emoji: "💬", titleKey: "weekreview.stat.messages", value: stats.messages),
            StatCard(id: "touches", emoji: "💓", titleKey: "weekreview.stat.touches", value: stats.touches),
            StatCard(id: "games", emoji: "🎮", titleKey: "weekreview.stat.games", value: stats.gamesPlayed),
            StatCard(id: "photos", emoji: "📸", titleKey: "weekreview.stat.photos", value: stats.photosAdded),
            StatCard(id: "videos", emoji: "🎬", titleKey: "weekreview.stat.videos", value: stats.videosAdded),
            StatCard(id: "hugs", emoji: "🫂", titleKey: "weekreview.stat.hugs", value: stats.hugsSent),
            StatCard(id: "wordle", emoji: "🟩", titleKey: "weekreview.stat.wordle", value: stats.wordleDays),
            StatCard(id: "daymemos", emoji: "🎙️", titleKey: "weekreview.stat.daymemos", value: stats.daymemoDays),
            StatCard(id: "quests", emoji: "⚔️", titleKey: "weekreview.stat.quests", value: stats.questsDone),
        ]
        let loudest = activity.filter { $0.value > 0 }
            .enumerated()
            .sorted { ($0.element.value, $1.offset) > ($1.element.value, $0.offset) }
            .map(\.element)
        return rituals + loudest
    }

    // MARK: - highlight window countdown

    /// Days (counting today) the highlight window of `week` stays open —
    /// a highlight may be shared during the week itself and the week after,
    /// so the window closes when the FOLLOWING week's Sunday ends.
    /// nil = window closed (or malformed keys).
    static func highlightWindowDaysLeft(week: String, todayKey: String) -> Int? {
        guard let start = startDateKey(ofWeek: week),
              let startDate = parseDateKey(start),
              let today = parseDateKey(todayKey) else { return nil }
        let weekStart = dayNumber(year: startDate.year, month: startDate.month, day: startDate.day)
        let windowEnd = weekStart + 13
        let z = dayNumber(year: today.year, month: today.month, day: today.day)
        let left = windowEnd - z + 1
        return (1...14).contains(left) ? left : nil
    }
}
