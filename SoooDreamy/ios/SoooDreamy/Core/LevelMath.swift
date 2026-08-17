import Foundation

/// Client-side mirror of the server level curve (server/src/gamification.js)
/// — pure Foundation so it runs in the Linux logic tests and in the widget
/// process. The SERVER is the source of truth for XP; this mirror only
/// derives display values (ring progress, "XP to next level") from a total.
///
/// Curve: threshold to REACH level n (1-based) is T(n) = 100·(n−1)·n/2
/// (triangular numbers × 100): L1=0, L2=100, L3=300, L4=600, L5=1000, …
///
/// Prestige chapters: the ten title stems no longer dead-end at level 10
/// ("Höchster Titel erreicht" after ~week ten). Levels 11–20 replay the
/// stems as "Kapitel II", 21–30 as "Kapitel III", … — the journey keeps a
/// name forever. The server composes the displayed title the same way;
/// keep BOTH sides in sync.
enum LevelMath {
    /// Number of distinct title stems per chapter.
    static let titleCount = 10
    /// Historic name for the stem count (mirrors LevelState.maxTitleLevel,
    /// which the server still sends for older clients). Progression itself
    /// is unbounded — nothing caps at this level anymore.
    static let maxTitleLevel = 10

    /// Cumulative XP required to reach `level`.
    static func xpForLevel(_ level: Int) -> Int {
        let n = max(1, level)
        return 100 * (n - 1) * n / 2
    }

    /// 1-based level for a total XP amount (unbounded).
    static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpForLevel(level + 1) <= xp { level += 1 }
        return level
    }

    /// Progress 0…1 through the current level.
    static func progress(forXP xp: Int) -> Double {
        let level = level(forXP: xp)
        let current = xpForLevel(level)
        let next = xpForLevel(level + 1)
        guard next > current else { return 0 }
        return min(1, Double(xp - current) / Double(next - current))
    }

    // MARK: Prestige chapters

    /// 1-based chapter: levels 1–10 are chapter I, 11–20 chapter II, …
    static func chapter(forLevel level: Int) -> Int {
        (max(1, level) - 1) / titleCount + 1
    }

    /// Title stem 1…titleCount inside the chapter (level 11 → stem 1).
    static func titleStem(forLevel level: Int) -> Int {
        (max(1, level) - 1) % titleCount + 1
    }

    /// L10n key of the stem title — cycles through the catalog with each
    /// chapter instead of clamping at the last entry.
    static func titleKey(forLevel level: Int) -> String {
        "level.title.\(titleStem(forLevel: level))"
    }

    /// Roman numeral for the chapter chip ("II", "III", …) — mirrors the
    /// server's `romanNumeral` so both sides compose identical titles.
    static func chapterNumeral(_ chapter: Int) -> String {
        let values: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var rest = max(1, chapter)
        var out = ""
        for (value, symbol) in values {
            while rest >= value {
                out += symbol
                rest -= value
            }
        }
        return out
    }
}
