import XCTest
@testable import SoooDreamyLogic

/// Pins the daily-quest determinism, the shared-checkbox reducer and the
/// streak math — all pure (dateKeys injected, no OS clock).
final class DailyQuestsLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"

    func testPoolIsBigAndClean() {
        let pool = ContentPack.dailyQuests
        XCTAssertGreaterThanOrEqual(pool.count, 200, "expansion target: 200+ quests")
        XCTAssertEqual(Set(pool.map(\.id)).count, pool.count, "ids must be unique")
        XCTAssertEqual(Set(pool.map(\.text.de)).count, pool.count, "German quest texts must be unique")
        XCTAssertEqual(Set(pool.map(\.text.en)).count, pool.count, "English quest texts must be unique")
        for quest in pool {
            XCTAssertFalse(quest.text.de.isEmpty)
            XCTAssertFalse(quest.text.en.isEmpty)
            XCTAssertFalse(quest.emoji.isEmpty)
        }
    }

    func testPoolHasEnoughQuickQuestsForTiredEvenings() {
        let pool = ContentPack.dailyQuests
        let quick = pool.filter { $0.energy == .quick }.count
        XCTAssertGreaterThanOrEqual(quick, 100, "need plenty of low-battery quests")
        XCTAssertGreaterThanOrEqual(pool.count - quick, 20, "need some real-moment quests too")
    }

    func testQuestIndexesAreDeterministicAndDistinct() {
        let first = DailyQuests.questIndexes(coupleId: "cp_1", dateKey: "2026-08-08")
        let again = DailyQuests.questIndexes(coupleId: "cp_1", dateKey: "2026-08-08")
        XCTAssertEqual(first, again, "same couple + day → same quests on both devices")
        XCTAssertEqual(first.count, DailyQuests.questsPerDay)
        XCTAssertEqual(Set(first).count, first.count, "no duplicate quests in one day")
        for index in first {
            XCTAssertTrue(ContentPack.dailyQuests.indices.contains(index))
        }
    }

    func testQuestIndexesVaryByDayAndCouple() {
        let base = DailyQuests.questIndexes(coupleId: "cp_1", dateKey: "2026-08-08")
        let nextDay = DailyQuests.questIndexes(coupleId: "cp_1", dateKey: "2026-08-09")
        let otherCouple = DailyQuests.questIndexes(coupleId: "cp_2", dateKey: "2026-08-08")
        XCTAssertNotEqual(base, nextDay)
        XCTAssertNotEqual(base, otherCouple)
    }

    /// "YYYY-MM-DD" keys for `count` consecutive days starting at `start`.
    private func dateKeys(from start: String, count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = start.split(separator: "-").compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let startDate = calendar.date(from: components) else { return [] }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
    }

    func testQuestCycleCoversWholePoolBeforeAnyRepeat() {
        let poolSize = ContentPack.dailyQuests.count
        let passDays = (poolSize + DailyQuests.questsPerDay - 1) / DailyQuests.questsPerDay
        var seen: [Int] = []
        for day in dateKeys(from: "2026-11-20", count: passDays) {
            seen.append(contentsOf: DailyQuests.questIndexes(coupleId: "cp-cover", dateKey: day))
        }
        XCTAssertEqual(Set(seen.prefix(poolSize)).count, poolSize,
                       "one full pass (\(passDays) days) must surface every quest before any repeat")
    }

    func testQuestLockoutIsAtLeast45DaysForSaneOversizedPools() {
        // Walking the couple cycle in blocks of 3 gives a hard stateless
        // lockout of ⌊pool/3⌋…⌈pool/3⌉ days. For every pool of 135–180 cards
        // that lands in the required 45–60-day window; the shipped pool is
        // pinned separately below.
        for poolSize in [135, 136, 153, 179, 180] {
            var lastSeen: [Int: Int] = [:]
            var minGap = Int.max
            let days = dateKeys(from: "2026-01-01", count: 140)
            for (dayOffset, day) in days.enumerated() {
                for index in DailyQuests.questIndexes(coupleId: "cp-lock", dateKey: day,
                                                      poolSize: poolSize) {
                    if let last = lastSeen[index] {
                        minGap = min(minGap, dayOffset - last)
                    }
                    lastSeen[index] = dayOffset
                }
            }
            XCTAssertGreaterThanOrEqual(minGap, 45,
                                        "pool \(poolSize): a quest resurfaced after only \(minGap) days")
            XCTAssertLessThanOrEqual(minGap, 61,
                                     "pool \(poolSize): quests must still come around (gap \(minGap))")
        }
    }

    func testShippedQuestPoolLockoutWindow() {
        let poolSize = ContentPack.dailyQuests.count
        let lockout = poolSize / DailyQuests.questsPerDay
        XCTAssertGreaterThanOrEqual(lockout, 45,
                                    "shipped pool (\(poolSize)) must give every card at least 45 days of rest")
    }

    func testReduceFirstTapWinsAndSkipsAliens() {
        let valid = [3, 17, 42]
        let state = DailyQuests.reduce(events: [
            .done(member: anna, questIndex: 17),
            .done(member: ben, questIndex: 17), // re-check → ignored
            .done(member: ben, questIndex: 5), // not today's quest → skipped
            .done(member: ben, questIndex: 3),
        ], validIndexes: valid)
        XCTAssertEqual(state.doneCount, 2)
        XCTAssertEqual(state.doneBy[17], anna, "first tap wins")
        XCTAssertEqual(state.doneBy[3], ben)
        XCTAssertNil(state.doneBy[5])
    }

    func testStreakCountsBackFromToday() {
        let done: Set<String> = ["2026-08-06", "2026-08-07", "2026-08-08"]
        XCTAssertEqual(DailyQuests.streak(completedDays: done, today: "2026-08-08"), 3)
    }

    func testStreakGraceWhileTodayInProgress() {
        // Today not done yet → the chain ending yesterday still counts.
        let done: Set<String> = ["2026-08-06", "2026-08-07"]
        XCTAssertEqual(DailyQuests.streak(completedDays: done, today: "2026-08-08"), 2)
    }

    func testStreakBreaksOnGap() {
        let done: Set<String> = ["2026-08-04", "2026-08-05", "2026-08-07"]
        XCTAssertEqual(DailyQuests.streak(completedDays: done, today: "2026-08-07"), 1)
        XCTAssertEqual(DailyQuests.streak(completedDays: [], today: "2026-08-08"), 0)
    }

    func testPreviousDayHandlesMonthAndYearBounds() {
        XCTAssertEqual(DailyQuests.previousDay(of: "2026-08-08"), "2026-08-07")
        XCTAssertEqual(DailyQuests.previousDay(of: "2026-03-01"), "2026-02-28")
        XCTAssertEqual(DailyQuests.previousDay(of: "2024-03-01"), "2024-02-29")
        XCTAssertEqual(DailyQuests.previousDay(of: "2026-01-01"), "2025-12-31")
        XCTAssertNil(DailyQuests.previousDay(of: "kaputt"))
    }
}
