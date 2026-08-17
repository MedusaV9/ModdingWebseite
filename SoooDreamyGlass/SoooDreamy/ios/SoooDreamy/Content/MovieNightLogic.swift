import Foundation

/// Film-Roulette → Wochenplan (EVAL-3.0 P0-3): pure decision logic
/// for turning a `movie_match` app event into a 1-tap movie-night week-plan
/// slot. UI-free so the whole flow is Linux-testable (MovieNightLogicTests).
///
/// Consumers:
/// - `MovieRouletteView` — "Filmabend planen" CTA in the match overlay and on
///   the end screen (picks the day via `slotDateKey`).
/// - `WeekplanView` — the "Filmabend eintragen?" banner for recent unplanned
///   matches (picks the match via `suggestion`).
enum MovieNight {
    /// A `movie_match` app event reduced to what the planner needs.
    struct Match: Equatable {
        let id: String
        /// Deck title from the completing swipe's annotation — cosmetic only,
        /// may be nil (the relay does not know the seeded deck).
        let title: String?
        let createdAt: Date

        init(id: String, title: String?, createdAt: Date) {
            self.id = id
            self.title = title
            self.createdAt = createdAt
        }
    }

    /// How long a match stays suggestable in the week plan.
    static let suggestionMaxAgeDays = 7

    /// The match the week-plan banner should suggest: the NEWEST match that
    /// is recent (≤ `suggestionMaxAgeDays`), not locally dismissed, and not
    /// already covered by a movie slot created at/after the match.
    static func suggestion(matches: [Match],
                           movieSlotCreations: [Date],
                           dismissedIds: Set<String>,
                           now: Date = Date()) -> Match? {
        let cutoff = now.addingTimeInterval(-Double(suggestionMaxAgeDays) * 86_400)
        return matches
            .filter { $0.createdAt >= cutoff }
            .filter { !dismissedIds.contains($0.id) }
            .filter { match in !movieSlotCreations.contains { $0 >= match.createdAt } }
            .max { $0.createdAt < $1.createdAt }
    }

    /// The 1-tap slot day: the first upcoming day where BOTH have time
    /// (week-plan overlap), else the next Saturday (today counts when it is
    /// one) — movie night defaults to the weekend.
    static func slotDateKey(overlapDateKeys: [String], now: Date = Date()) -> String {
        let today = SharedDates.todayKey(now)
        if let overlap = overlapDateKeys.filter({ $0 >= today }).sorted().first {
            return overlap
        }
        let calendar = SharedDates.calendar
        for offset in 0...6 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if calendar.component(.weekday, from: day) == 7 { // Saturday
                return SharedDates.todayKey(day)
            }
        }
        return today
    }
}
