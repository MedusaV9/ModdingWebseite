import XCTest
@testable import SoooDreamyLogic

/// Merge rules for `GET /api/inbox` → local state: the missed-inbox refresh
/// may raise the unread-chat badge and advance the last-touch teaser, but
/// must never rewind fresher local truth (live socket counts, own read
/// receipts, a newer live touch).
final class InboxMergeRulesTests: XCTestCase {

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: Unread-chat badge

    func testMissedMessagesRaiseTheBadge() {
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 0, missedCount: 3,
            newestMissedAt: date(100), myLastReadAt: nil), 3)
    }

    func testBadgeNeverLowers() {
        // Live socket events counted 5 while the inbox window only knows 2.
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 5, missedCount: 2,
            newestMissedAt: date(100), myLastReadAt: nil), 5)
    }

    func testNoMissedMessagesLeaveTheBadgeAlone() {
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 2, missedCount: 0,
            newestMissedAt: nil, myLastReadAt: nil), 2)
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 2, missedCount: nil,
            newestMissedAt: nil, myLastReadAt: nil), 2)
    }

    func testReadReceiptAtOrAfterNewestMissedSuppressesTheResurrection() {
        // I read the chat on my iPad AFTER the newest missed message — the
        // "missed" mail is already read; the badge must not come back.
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 0, missedCount: 4,
            newestMissedAt: date(100), myLastReadAt: date(100)), 0)
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 0, missedCount: 4,
            newestMissedAt: date(100), myLastReadAt: date(150)), 0)
        // An OLDER receipt does not suppress — newer mail arrived since.
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 0, missedCount: 4,
            newestMissedAt: date(100), myLastReadAt: date(50)), 4)
    }

    func testOldServerWithoutTeaserStillRaisesTheBadge() {
        // Pre-v11 buckets carry a bare {count} — a WS gap must not hide
        // mail just because the teaser timestamp is missing.
        XCTAssertEqual(InboxMergeRules.mergedUnreadChat(
            localUnread: 0, missedCount: 2,
            newestMissedAt: nil, myLastReadAt: date(999)), 2)
    }

    // MARK: Last-touch teaser

    func testNewerTeaserIsAdopted() {
        XCTAssertTrue(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: date(200), currentLastTouchAt: date(100)))
        // Nothing shown yet — any dated teaser wins.
        XCTAssertTrue(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: date(200), currentLastTouchAt: nil))
    }

    func testReplaysNeverRewindAFresherTouch() {
        XCTAssertFalse(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: date(100), currentLastTouchAt: date(200)))
        // Same instant = the touch we already show; no churn.
        XCTAssertFalse(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: date(100), currentLastTouchAt: date(100)))
    }

    func testUndatedTeaserIsIgnored() {
        XCTAssertFalse(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: nil, currentLastTouchAt: nil))
        XCTAssertFalse(InboxMergeRules.adoptsTouchTeaser(
            teaserAt: nil, currentLastTouchAt: date(100)))
    }
}
