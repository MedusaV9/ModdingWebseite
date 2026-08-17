import XCTest
@testable import SoooDreamyLogic

/// The page-1 invite hand-over slot: consume-once, 15-minute shelf life,
/// explicit clear on abort/replace. EVAL repro: a code parked by an
/// abandoned setup flow used to survive indefinitely and silently seeded a
/// pairing attempt days later.
final class PendingInviteTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    private func freshDefaults(_ suite: String) throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testStoreConsumeRoundTripWithinShelfLife() throws {
        let suite = "pendinginvite.tests.roundtrip"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "LOVE42", now: t0, defaults: defaults)
        XCTAssertEqual(PendingInvite.consume(now: t0.addingTimeInterval(60),
                                             defaults: defaults), "LOVE42")
        // Consume-once: the slot is empty afterwards.
        XCTAssertNil(PendingInvite.consume(now: t0.addingTimeInterval(61),
                                           defaults: defaults))
    }

    func testExpiredCodeIsDroppedAndTheSlotEmpties() throws {
        let suite = "pendinginvite.tests.expiry"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "LOVE42", now: t0, defaults: defaults)
        // Just inside the shelf life: still served.
        XCTAssertNotNil(defaults.string(forKey: PendingInvite.codeKey))
        // At/after the shelf life: dropped, AND the stale slot is wiped.
        XCTAssertNil(PendingInvite.consume(
            now: t0.addingTimeInterval(PendingInvite.shelfLife),
            defaults: defaults))
        XCTAssertNil(defaults.string(forKey: PendingInvite.codeKey))
    }

    func testBoundaryJustUnderShelfLifeStillServes() throws {
        let suite = "pendinginvite.tests.boundary"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "LOVE42", now: t0, defaults: defaults)
        XCTAssertEqual(PendingInvite.consume(
            now: t0.addingTimeInterval(PendingInvite.shelfLife - 1),
            defaults: defaults), "LOVE42")
    }

    func testLegacyCodeWithoutTimestampCountsAsStale() throws {
        // A code written by the pre-expiry app has no stored-at stamp —
        // it IS the abandoned-flow leftover this fix targets.
        let suite = "pendinginvite.tests.legacy"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("OLD123", forKey: PendingInvite.codeKey)
        XCTAssertNil(PendingInvite.consume(now: t0, defaults: defaults))
        XCTAssertNil(defaults.string(forKey: PendingInvite.codeKey))
    }

    func testClockSetBackDropsTheFutureStampedCode() throws {
        let suite = "pendinginvite.tests.clock"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "LOVE42", now: t0.addingTimeInterval(3600),
                            defaults: defaults)
        XCTAssertNil(PendingInvite.consume(now: t0, defaults: defaults))
    }

    func testStoreReplacesTheOlderCode() throws {
        let suite = "pendinginvite.tests.replace"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "FIRST1", now: t0, defaults: defaults)
        PendingInvite.store(code: "SECOND", now: t0.addingTimeInterval(30),
                            defaults: defaults)
        XCTAssertEqual(PendingInvite.consume(now: t0.addingTimeInterval(60),
                                             defaults: defaults), "SECOND")
    }

    func testExplicitClearEmptiesTheSlot() throws {
        // The abort/replace hooks (demo entry, rejoin link, completed
        // auth, profile removal) all end here.
        let suite = "pendinginvite.tests.clear"
        let defaults = try freshDefaults(suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        PendingInvite.store(code: "LOVE42", now: t0, defaults: defaults)
        PendingInvite.clear(defaults: defaults)
        XCTAssertNil(PendingInvite.consume(now: t0.addingTimeInterval(1),
                                           defaults: defaults))
    }
}
