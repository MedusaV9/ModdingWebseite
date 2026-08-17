import XCTest
@testable import SoooDreamyLogic

/// Pins the v3.0 delight language: which counter/streak values are moments
/// and how big they celebrate. The choreography itself is UI; THESE rules
/// are the contract every feature (rituals, games, levels) relies on.
final class DelightRulesTests: XCTestCase {
    func testCounterMilestones() {
        XCTAssertNil(DelightRules.milestone(forCount: 0))
        XCTAssertNil(DelightRules.milestone(forCount: 1))
        XCTAssertNil(DelightRules.milestone(forCount: 9))
        XCTAssertEqual(DelightRules.milestone(forCount: 10), .small)
        XCTAssertEqual(DelightRules.milestone(forCount: 25), .small)
        XCTAssertEqual(DelightRules.milestone(forCount: 50), .medium)
        XCTAssertEqual(DelightRules.milestone(forCount: 100), .medium)
        XCTAssertEqual(DelightRules.milestone(forCount: 250), .epic)
        XCTAssertEqual(DelightRules.milestone(forCount: 500), .epic)
        XCTAssertEqual(DelightRules.milestone(forCount: 1000), .epic)
        XCTAssertNil(DelightRules.milestone(forCount: 1001))
        XCTAssertEqual(DelightRules.milestone(forCount: 1500), .epic)
        XCTAssertEqual(DelightRules.milestone(forCount: 5000), .epic)
        XCTAssertNil(DelightRules.milestone(forCount: 5100))
    }

    func testStreakMilestones() {
        XCTAssertNil(DelightRules.milestone(forStreak: 0))
        XCTAssertNil(DelightRules.milestone(forStreak: 2))
        XCTAssertEqual(DelightRules.milestone(forStreak: 3), .small)
        XCTAssertEqual(DelightRules.milestone(forStreak: 7), .medium)
        XCTAssertEqual(DelightRules.milestone(forStreak: 14), .medium)
        XCTAssertEqual(DelightRules.milestone(forStreak: 30), .epic)
        XCTAssertEqual(DelightRules.milestone(forStreak: 100), .epic)
        XCTAssertEqual(DelightRules.milestone(forStreak: 365), .epic)
        XCTAssertEqual(DelightRules.milestone(forStreak: 730), .epic)
        XCTAssertNil(DelightRules.milestone(forStreak: 31))
    }

    func testLevelUpsAndBadgesAlwaysCelebrate() {
        XCTAssertEqual(DelightRules.intensity(forLevelUp: 2), .epic)
        XCTAssertEqual(DelightRules.intensity(forLevelUp: 10), .epic)
        XCTAssertEqual(DelightRules.intensity(forBadgeSecret: true), .epic)
        XCTAssertEqual(DelightRules.intensity(forBadgeSecret: false), .medium)
    }

    func testIntensityOrdering() {
        XCTAssertLessThan(DelightIntensity.small, .medium)
        XCTAssertLessThan(DelightIntensity.medium, .epic)
        XCTAssertFalse(DelightIntensity.epic < .small)
    }
}
