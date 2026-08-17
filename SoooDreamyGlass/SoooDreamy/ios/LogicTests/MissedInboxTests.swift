import XCTest
@testable import SoooDreamyLogic

/// Dossier 40: the return moment must follow emotional priority, bundle the
/// rest into one sentence and dissolve only when everything was visited.
final class MissedInboxTests: XCTestCase {

    private var savedLanguage: AppLanguage!

    override func setUp() {
        super.setUp()
        savedLanguage = L10n.language
    }

    override func tearDown() {
        L10n.language = savedLanguage
        super.tearDown()
    }

    // MARK: Hero priority (idea 8: emotion before system)

    func testOpenNeedIsTheUnconditionalHero() {
        var snapshot = MissedInboxLogic.Snapshot(messages: 5, touches: 3, photos: 2)
        snapshot.lastMessageIsLetter = true
        snapshot.hasOpenNeed = true
        XCTAssertEqual(MissedInboxLogic.hero(snapshot), .need)
    }

    func testLetterBeatsHeartbeatsBeatsPhotos() {
        var snapshot = MissedInboxLogic.Snapshot(messages: 2, touches: 3, photos: 4)
        snapshot.lastMessageIsLetter = true
        XCTAssertEqual(MissedInboxLogic.hero(snapshot), .letter)

        snapshot.lastMessageIsLetter = false
        XCTAssertEqual(MissedInboxLogic.hero(snapshot), .touches(3))

        snapshot.touches = 0
        XCTAssertEqual(MissedInboxLogic.hero(snapshot), .photos(4))
    }

    func testPlainMessagesAloneProduceNoHero() {
        // Ordinary chat lines have the chat badge — no hero theater for them.
        let snapshot = MissedInboxLogic.Snapshot(messages: 4, coupons: 1)
        XCTAssertNil(MissedInboxLogic.hero(snapshot))
    }

    func testLetterFlagWithoutMessagesIsIgnored() {
        var snapshot = MissedInboxLogic.Snapshot(touches: 1)
        snapshot.lastMessageIsLetter = true
        XCTAssertEqual(MissedInboxLogic.hero(snapshot), .touches(1))
    }

    // MARK: Chips (ideas 1/20: hero absorbs its bucket, system chips gone)

    func testHeroAbsorbsItsOwnBucket() {
        let snapshot = MissedInboxLogic.Snapshot(messages: 1, touches: 3, photos: 2)
        let hero = MissedInboxLogic.hero(snapshot)
        XCTAssertEqual(hero, .touches(3))
        let chips = MissedInboxLogic.chips(snapshot, hero: hero)
        XCTAssertFalse(chips.contains { $0.category == .touches },
                       "the hero line IS the touches bundle — no duplicate chip")
        XCTAssertEqual(chips, [.init(category: .messages, count: 1),
                               .init(category: .photos, count: 2)])
    }

    func testLetterHeroAbsorbsExactlyOneMessage() {
        var snapshot = MissedInboxLogic.Snapshot(messages: 3)
        snapshot.lastMessageIsLetter = true
        let chips = MissedInboxLogic.chips(snapshot, hero: .letter)
        XCTAssertEqual(chips, [.init(category: .messages, count: 2)])

        snapshot.messages = 1
        XCTAssertTrue(MissedInboxLogic.chips(snapshot, hero: .letter).isEmpty)
    }

    func testChipsKeepTheFixedEmotionalOrder() {
        let snapshot = MissedInboxLogic.Snapshot(
            messages: 1, touches: 1, photos: 1, coupons: 1, songs: 1, canvas: 1)
        let chips = MissedInboxLogic.chips(snapshot, hero: nil)
        XCTAssertEqual(chips.map(\.category),
                       [.messages, .touches, .photos, .coupons, .songs, .canvas])
    }

    // MARK: Bundled sentence (idea 2)

    func testSentenceBuildsFromTopTwoPlusMore() {
        L10n.language = .de
        let chips: [MissedInboxLogic.Chip] = [
            .init(category: .touches, count: 3),
            .init(category: .photos, count: 1),
            .init(category: .songs, count: 2),
            .init(category: .canvas, count: 1),
        ]
        XCTAssertEqual(MissedInboxLogic.sentence(chips: chips),
                       "3 Herzschläge und ein Foto · + 3 mehr")
    }

    func testSentenceSingularsReadLikeGerman() {
        L10n.language = .de
        let chips: [MissedInboxLogic.Chip] = [
            .init(category: .messages, count: 1),
            .init(category: .coupons, count: 1),
        ]
        XCTAssertEqual(MissedInboxLogic.sentence(chips: chips),
                       "eine Nachricht und ein Gutschein")
    }

    func testSentenceEnglish() {
        L10n.language = .en
        let chips: [MissedInboxLogic.Chip] = [
            .init(category: .touches, count: 2),
            .init(category: .canvas, count: 1),
        ]
        XCTAssertEqual(MissedInboxLogic.sentence(chips: chips),
                       "2 heartbeats and one doodle")
    }

    func testSentenceEmptyForNoChips() {
        XCTAssertEqual(MissedInboxLogic.sentence(chips: []), "")
    }

    // MARK: Checklist completion (ideas 6/7/28)

    func testCaughtUpNeedsEveryChipVisited() {
        let snapshot = MissedInboxLogic.Snapshot(messages: 2, photos: 1)
        XCTAssertFalse(MissedInboxLogic.caughtUp(snapshot, hero: nil, visited: ["messages"]))
        XCTAssertTrue(MissedInboxLogic.caughtUp(snapshot, hero: nil,
                                                visited: ["messages", "photos"]))
    }

    func testCaughtUpWaitsForTheNeedAck() {
        var snapshot = MissedInboxLogic.Snapshot(touches: 1)
        snapshot.hasOpenNeed = true
        let hero = MissedInboxLogic.hero(snapshot)
        XCTAssertEqual(hero, .need)
        XCTAssertFalse(MissedInboxLogic.caughtUp(snapshot, hero: hero, visited: ["touches"]))
        XCTAssertTrue(MissedInboxLogic.caughtUp(snapshot, hero: hero,
                                                visited: ["touches", "need"]))
    }

    func testCaughtUpRequiresTheHeroToo() {
        let snapshot = MissedInboxLogic.Snapshot(touches: 2, coupons: 1)
        let hero = MissedInboxLogic.hero(snapshot)
        XCTAssertEqual(hero, .touches(2))
        // The coupon chip is visited, but the heartbeats were never felt.
        XCTAssertFalse(MissedInboxLogic.caughtUp(snapshot, hero: hero, visited: ["coupons"]))
        XCTAssertTrue(MissedInboxLogic.caughtUp(snapshot, hero: hero,
                                                visited: ["coupons", "touches"]))
    }

    func testEmptySnapshot() {
        XCTAssertTrue(MissedInboxLogic.Snapshot().isEmpty)
        XCTAssertFalse(MissedInboxLogic.Snapshot(messages: 1).isEmpty)
        var withNeed = MissedInboxLogic.Snapshot()
        withNeed.hasOpenNeed = true
        XCTAssertFalse(withNeed.isEmpty)
    }
}
