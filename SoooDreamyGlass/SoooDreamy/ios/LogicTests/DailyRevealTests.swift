import XCTest
@testable import SoooDreamyLogic

/// Reveal-ceremony rules: one seal break per couple/day/device, plus the
/// jackpot detection for identical answers.
final class DailyRevealTests: XCTestCase {

    // MARK: RevealedDailyStore (app-group persistence)

    private var defaults: UserDefaults!
    private let suite = "sooodreamy.tests.revealedDaily"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testMarkRevealedFiresExactlyOncePerCoupleAndDay() {
        XCTAssertFalse(RevealedDailyStore.isRevealed(coupleId: "c1", dateKey: "2026-08-13",
                                                     defaults: defaults))
        XCTAssertTrue(RevealedDailyStore.isFirstReveal(coupleId: "c1", defaults: defaults))

        XCTAssertTrue(RevealedDailyStore.markRevealed(coupleId: "c1", dateKey: "2026-08-13",
                                                      defaults: defaults))
        // Second attempt must report "already revealed" — the ceremony
        // never fires twice, even across app restarts.
        XCTAssertFalse(RevealedDailyStore.markRevealed(coupleId: "c1", dateKey: "2026-08-13",
                                                       defaults: defaults))
        XCTAssertTrue(RevealedDailyStore.isRevealed(coupleId: "c1", dateKey: "2026-08-13",
                                                    defaults: defaults))
        XCTAssertFalse(RevealedDailyStore.isFirstReveal(coupleId: "c1", defaults: defaults))

        // Midnight: the next day is a fresh seal.
        XCTAssertFalse(RevealedDailyStore.isRevealed(coupleId: "c1", dateKey: "2026-08-14",
                                                     defaults: defaults))
        // Other couples on the same device stay independent.
        XCTAssertFalse(RevealedDailyStore.isRevealed(coupleId: "c2", dateKey: "2026-08-13",
                                                     defaults: defaults))
    }

    func testNilCoupleNeverRevealsAndNeverCrashes() {
        XCTAssertFalse(RevealedDailyStore.isRevealed(coupleId: nil, dateKey: "2026-08-13",
                                                     defaults: defaults))
        XCTAssertFalse(RevealedDailyStore.markRevealed(coupleId: nil, dateKey: "2026-08-13",
                                                       defaults: defaults))
        XCTAssertFalse(RevealedDailyStore.isFirstReveal(coupleId: nil, defaults: defaults))
    }

    func testSealPendingNeedsBothAnsweredAndNoRevealYet() {
        XCTAssertFalse(RevealedDailyStore.sealPending(coupleId: "c1", dateKey: "2026-08-13",
                                                      bothAnswered: false, defaults: defaults))
        XCTAssertTrue(RevealedDailyStore.sealPending(coupleId: "c1", dateKey: "2026-08-13",
                                                     bothAnswered: true, defaults: defaults))
        RevealedDailyStore.markRevealed(coupleId: "c1", dateKey: "2026-08-13", defaults: defaults)
        XCTAssertFalse(RevealedDailyStore.sealPending(coupleId: "c1", dateKey: "2026-08-13",
                                                      bothAnswered: true, defaults: defaults))
    }

    // MARK: Widget seal (W7-Rest)

    /// The widget seal must stay honest against a stale snapshot: it dies
    /// after midnight (dateKey mismatch) and the moment the in-app ceremony
    /// marks the day revealed — without waiting for a snapshot rewrite.
    func testWidgetSnapshotSealChecksDateKeyAndLiveStore() {
        let now = Date()
        var snapshot = WidgetSnapshot(dailyBothAnswered: true)
        snapshot.coupleId = "c1"
        snapshot.dailyRevealPending = true
        snapshot.dailyRevealDateKey = SharedDates.todayKey(now)
        XCTAssertTrue(snapshot.revealSealPending(now: now, defaults: defaults))

        // Midnight passed: yesterday's snapshot must not keep glowing.
        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertFalse(snapshot.revealSealPending(now: tomorrow, defaults: defaults))

        // The app broke the seal — the widget flips on its next render,
        // even though the snapshot still says pending.
        RevealedDailyStore.markRevealed(coupleId: "c1", dateKey: SharedDates.todayKey(now),
                                        defaults: defaults)
        XCTAssertFalse(snapshot.revealSealPending(now: now, defaults: defaults))
    }

    func testWidgetSnapshotSealNeedsAllFields() {
        let now = Date()
        // Pre-seal snapshots (all fields nil) never glow.
        XCTAssertFalse(WidgetSnapshot().revealSealPending(now: now, defaults: defaults))

        var snapshot = WidgetSnapshot(dailyBothAnswered: true)
        snapshot.dailyRevealPending = true
        snapshot.dailyRevealDateKey = SharedDates.todayKey(now)
        // No coupleId — the store cannot be checked, so no gold claim.
        XCTAssertFalse(snapshot.revealSealPending(now: now, defaults: defaults))

        snapshot.coupleId = "c1"
        snapshot.dailyRevealPending = false
        XCTAssertFalse(snapshot.revealSealPending(now: now, defaults: defaults))
    }

    func testCapacityKeepsTheNewestDays() {
        for day in 1...(RevealedDailyStore.capacity + 10) {
            let key = String(format: "2026-01-%03d", day)   // string-sortable fake keys
            RevealedDailyStore.markRevealed(coupleId: "c1", dateKey: key, defaults: defaults)
        }
        let kept = RevealedDailyStore.revealedKeys(coupleId: "c1", defaults: defaults)
        XCTAssertEqual(kept.count, RevealedDailyStore.capacity)
        XCTAssertFalse(kept.contains("2026-01-001"), "oldest entries must be evicted")
        XCTAssertTrue(kept.contains(String(format: "2026-01-%03d", RevealedDailyStore.capacity + 10)))
    }

    // MARK: Jackpot (identical answers)

    func testJackpotNormalizesCasePunctuationAndWhitespace() {
        XCTAssertTrue(DailyRevealLogic.isJackpot(mine: "Pizza!!", theirs: " pizza "))
        XCTAssertTrue(DailyRevealLogic.isJackpot(mine: "Am  Meer,\nnachts.", theirs: "am meer nachts"))
        XCTAssertFalse(DailyRevealLogic.isJackpot(mine: "Pizza", theirs: "Pasta"))
        XCTAssertFalse(DailyRevealLogic.isJackpot(mine: nil, theirs: "Pizza"))
        XCTAssertFalse(DailyRevealLogic.isJackpot(mine: "", theirs: ""))
        XCTAssertFalse(DailyRevealLogic.isJackpot(mine: "!!!", theirs: "???"),
                       "punctuation-only answers must not jackpot as empty == empty")
    }

    func testSharedWordFindsTheSmallerEcho() {
        XCTAssertEqual(DailyRevealLogic.sharedWord(mine: "Abends Pizza essen",
                                                   theirs: "PIZZA, ganz klar"), "pizza")
        // Short filler words never count as an echo.
        XCTAssertNil(DailyRevealLogic.sharedWord(mine: "am See", theirs: "am Meer"))
        // A full jackpot is not additionally a "shared word" moment.
        XCTAssertNil(DailyRevealLogic.sharedWord(mine: "Pizza", theirs: "pizza"))
        XCTAssertNil(DailyRevealLogic.sharedWord(mine: nil, theirs: "Pizza"))
    }
}
