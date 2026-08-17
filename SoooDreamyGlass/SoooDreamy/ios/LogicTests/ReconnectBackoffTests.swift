import XCTest
@testable import SoooDreamyLogic

final class ReconnectBackoffTests: XCTestCase {
    func testDelayGrowsAndStaysWithinJitterAndCap() {
        let earlyLow = ReconnectBackoff.delay(attempt: 1, randomUnit: 0)
        let earlyHigh = ReconnectBackoff.delay(attempt: 1, randomUnit: 1)
        XCTAssertGreaterThan(earlyHigh, earlyLow)

        var prior = 0.0
        for attempt in 1...10 {
            let delay = ReconnectBackoff.delay(attempt: attempt, randomUnit: 0.5)
            XCTAssertGreaterThanOrEqual(delay, prior)
            XCTAssertLessThanOrEqual(delay, ReconnectBackoff.maximumDelay)
            prior = delay
        }
    }

    func testRandomInputIsClamped() {
        XCTAssertEqual(
            ReconnectBackoff.delay(attempt: 3, randomUnit: -10),
            ReconnectBackoff.delay(attempt: 3, randomUnit: 0)
        )
        XCTAssertEqual(
            ReconnectBackoff.delay(attempt: 3, randomUnit: 10),
            ReconnectBackoff.delay(attempt: 3, randomUnit: 1)
        )
    }

    func testOfflineBannerMasksQuickDropsButNotLongOutages() {
        let droppedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(OfflineBannerPolicy.shouldMaskDrop(
            disconnectedAt: droppedAt, now: droppedAt))
        XCTAssertTrue(OfflineBannerPolicy.shouldMaskDrop(
            disconnectedAt: droppedAt,
            now: droppedAt.addingTimeInterval(OfflineBannerPolicy.graceSeconds - 1)))
        XCTAssertFalse(OfflineBannerPolicy.shouldMaskDrop(
            disconnectedAt: droppedAt,
            now: droppedAt.addingTimeInterval(OfflineBannerPolicy.graceSeconds)))
        XCTAssertFalse(OfflineBannerPolicy.shouldMaskDrop(
            disconnectedAt: droppedAt,
            now: droppedAt.addingTimeInterval(3_600)))
    }
}
