import XCTest
@testable import SoooDreamyLogic

/// Post & Sendungen (FullRelease P6-B): PostRules must mirror
/// `server/src/post.js` POST_LIMITS bit-for-bit — every window edge tested
/// here corresponds to a server-side rejection (`bad_deliver_at`,
/// `post_limit`, `echo_expired`, `echo_taken`) or the journal's merge order.
final class PostLogicTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000)

    // MARK: Zeitpost — deliverAt window

    func testDeliverAtFiveMinutesAheadIsOk() {
        XCTAssertEqual(PostRules.deliverAtVerdict(now.addingTimeInterval(5 * 60), now: now), .ok)
    }

    func testDeliverAtInsideClockSkewGraceStillPasses() {
        // Server forgives 30 s below the 5-minute minimum (leadGraceMs).
        let edge = now.addingTimeInterval(5 * 60 - 30)
        XCTAssertEqual(PostRules.deliverAtVerdict(edge, now: now), .ok)
    }

    func testDeliverAtBelowGraceIsTooSoon() {
        let below = now.addingTimeInterval(5 * 60 - 31)
        XCTAssertEqual(PostRules.deliverAtVerdict(below, now: now), .tooSoon)
    }

    func testDeliverAtInThePastIsTooSoon() {
        // The offline-replay poison-pill case: the moment has passed.
        XCTAssertEqual(PostRules.deliverAtVerdict(now.addingTimeInterval(-3600), now: now),
                       .tooSoon)
    }

    func testDeliverAtSevenDaysAheadIsOkButBeyondIsTooFar() {
        let sevenDays: TimeInterval = 7 * 24 * 3600
        XCTAssertEqual(PostRules.deliverAtVerdict(now.addingTimeInterval(sevenDays), now: now),
                       .ok)
        XCTAssertEqual(PostRules.deliverAtVerdict(now.addingTimeInterval(sevenDays + 1), now: now),
                       .tooFar)
    }

    func testPickableRangeIsAlwaysValidToSend() {
        // Whatever the composer offers must survive the trip to the server.
        XCTAssertEqual(PostRules.deliverAtVerdict(PostRules.earliestPickable(now: now), now: now),
                       .ok)
        XCTAssertEqual(PostRules.deliverAtVerdict(PostRules.latestPickable(now: now), now: now),
                       .ok)
        XCTAssertGreaterThanOrEqual(
            PostRules.earliestPickable(now: now).timeIntervalSince(now),
            PostRules.minLead)
    }

    // MARK: R1-D (robustness eval S3) — the composer's verdict gate & nudge

    func testStalePickIsNudgedForwardToEarliestPickable() {
        // The long-open-composer case: picked 6 minutes ahead, then the
        // sheet sat for 10 minutes — the pick is now 4 minutes in the past
        // and the server would answer `bad_deliver_at`. The nudge snaps it
        // to `earliestPickable`, which is valid to send by construction.
        let picked = now.addingTimeInterval(6 * 60)
        let later = now.addingTimeInterval(10 * 60)
        XCTAssertEqual(PostRules.deliverAtVerdict(picked, now: later), .tooSoon)
        let nudged = PostRules.nudgedDeliverAt(picked, now: later)
        XCTAssertEqual(nudged, PostRules.earliestPickable(now: later))
        XCTAssertEqual(PostRules.deliverAtVerdict(nudged ?? picked, now: later), .ok)
    }

    func testValidPickIsNeverNudged() {
        // A pick the server would accept stays exactly where it was put —
        // including the clock-skew grace edge the verdict forgives.
        XCTAssertNil(PostRules.nudgedDeliverAt(now.addingTimeInterval(3600), now: now))
        XCTAssertNil(PostRules.nudgedDeliverAt(now.addingTimeInterval(5 * 60 - 30), now: now))
    }

    func testTooFarPickIsNudgedBackToLatestPickable() {
        // Theoretical (the DatePicker range prevents it, and staleness only
        // ever shrinks the lead) — but the rule is total, so the far edge
        // snaps back instead of falling through unsendable.
        let far = now.addingTimeInterval(8 * 24 * 3600)
        XCTAssertEqual(PostRules.nudgedDeliverAt(far, now: now),
                       PostRules.latestPickable(now: now))
    }

    // MARK: Zeitpost — open-post allowance

    func testMaxOpenPostsRule() {
        XCTAssertTrue(PostRules.canScheduleMore(openCount: 0))
        XCTAssertTrue(PostRules.canScheduleMore(openCount: 4))
        XCTAssertFalse(PostRules.canScheduleMore(openCount: 5))
        XCTAssertFalse(PostRules.canScheduleMore(openCount: 6))
    }

    func testRemainingSlotsNeverGoNegative() {
        XCTAssertEqual(PostRules.remainingSlots(openCount: 0), 5)
        XCTAssertEqual(PostRules.remainingSlots(openCount: 5), 0)
        XCTAssertEqual(PostRules.remainingSlots(openCount: 9), 0)
    }

    // MARK: Zeitpost — note validation

    func testNoteValidationTrimsAndBounds() {
        XCTAssertEqual(PostRules.validatedNote("  bis gleich 💌  "), "bis gleich 💌")
        XCTAssertNil(PostRules.validatedNote("   \n "))
        let exactly120 = String(repeating: "a", count: 120)
        XCTAssertEqual(PostRules.validatedNote(exactly120), exactly120)
        XCTAssertNil(PostRules.validatedNote(String(repeating: "a", count: 121)))
    }

    // MARK: Echo — window

    func testEchoWindowOpenForTenMinutes() {
        XCTAssertTrue(PostRules.canEcho(originalCreatedAt: now.addingTimeInterval(-9 * 60),
                                        now: now))
        // Exactly at the edge still passes (server uses strict `>` to expire).
        XCTAssertTrue(PostRules.canEcho(originalCreatedAt: now.addingTimeInterval(-10 * 60),
                                        now: now))
        XCTAssertFalse(PostRules.canEcho(originalCreatedAt: now.addingTimeInterval(-10 * 60 - 1),
                                         now: now))
    }

    func testEchoToleratesSlightlyFutureTimestamps() {
        // Server clock a touch ahead of ours must not hide the affordance.
        XCTAssertTrue(PostRules.canEcho(originalCreatedAt: now.addingTimeInterval(20), now: now))
    }

    // MARK: Echo — once per original & affordance gate

    func testEchoTakenByAnyEchoOfReference() {
        XCTAssertTrue(PostRules.isEchoTaken(originalId: "t_1", echoedOriginalIds: ["t_1", "t_9"]))
        XCTAssertFalse(PostRules.isEchoTaken(originalId: "t_2", echoedOriginalIds: ["t_1"]))
    }

    func testEchoAllowedOnlyForFreshReceivedUnechoedTouches() {
        let fresh = now.addingTimeInterval(-60)
        // The happy path: partner's fresh touch, never echoed.
        XCTAssertTrue(PostRules.echoAllowed(originalSenderId: "partner", myMemberId: "me",
                                            originalIsEcho: false, originalCreatedAt: fresh,
                                            alreadyEchoed: false, now: now))
        // My own touch can never bounce back to me.
        XCTAssertFalse(PostRules.echoAllowed(originalSenderId: "me", myMemberId: "me",
                                             originalIsEcho: false, originalCreatedAt: fresh,
                                             alreadyEchoed: false, now: now))
        // An incoming echo offers no counter-echo (one bounce is the point).
        XCTAssertFalse(PostRules.echoAllowed(originalSenderId: "partner", myMemberId: "me",
                                             originalIsEcho: true, originalCreatedAt: fresh,
                                             alreadyEchoed: false, now: now))
        // Already sent back once — the server would answer `echo_taken`.
        XCTAssertFalse(PostRules.echoAllowed(originalSenderId: "partner", myMemberId: "me",
                                             originalIsEcho: false, originalCreatedAt: fresh,
                                             alreadyEchoed: true, now: now))
        // Not signed in / no member id — nothing to send back as.
        XCTAssertFalse(PostRules.echoAllowed(originalSenderId: "partner", myMemberId: nil,
                                             originalIsEcho: false, originalCreatedAt: fresh,
                                             alreadyEchoed: false, now: now))
    }

    // MARK: Journal — merge order

    private struct Entry: Equatable {
        let id: String
        let createdAt: Date
    }

    func testJournalSortsNewestFirst() {
        let entries = [
            Entry(id: "t_old", createdAt: now.addingTimeInterval(-300)),
            Entry(id: "pn_new", createdAt: now),
            Entry(id: "pl_mid", createdAt: now.addingTimeInterval(-100)),
        ]
        let sorted = PostRules.journalSorted(entries, createdAt: \.createdAt, id: \.id)
        XCTAssertEqual(sorted.map(\.id), ["pn_new", "pl_mid", "t_old"])
    }

    func testJournalBreaksTimestampTiesOnIdDescending() {
        // Server-identical: equal instants order by id DESC — deterministic
        // on every device, no matter the arrival order.
        let entries = [
            Entry(id: "a", createdAt: now),
            Entry(id: "c", createdAt: now),
            Entry(id: "b", createdAt: now),
        ]
        let sorted = PostRules.journalSorted(entries, createdAt: \.createdAt, id: \.id)
        XCTAssertEqual(sorted.map(\.id), ["c", "b", "a"])
    }

    func testJournalHorizonIsThirtyDays() {
        let inside = now.addingTimeInterval(-29.5 * 86_400)
        let outside = now.addingTimeInterval(-30.5 * 86_400)
        XCTAssertTrue(PostRules.withinJournalHorizon(createdAt: inside, now: now))
        XCTAssertFalse(PostRules.withinJournalHorizon(createdAt: outside, now: now))
        XCTAssertTrue(PostRules.withinJournalHorizon(createdAt: now, now: now))
    }

    // MARK: Cross-checks with the wire enums

    func testPostKindsMatchTheServerContract() {
        // POST_KINDS = ['touch', 'pulse', 'note'] — order and spelling.
        XCTAssertEqual(PostKind.allCases.map(\.rawValue), ["touch", "pulse", "note"])
    }

    func testEchoWindowMatchesOutboxFreshnessLifetime() {
        // The queued echo expires exactly when the server would reject it —
        // a replayed echo either lands inside the window or not at all.
        XCTAssertEqual(PostRules.echoWindow, OutboxFreshness.echoLifetime)
    }
}
