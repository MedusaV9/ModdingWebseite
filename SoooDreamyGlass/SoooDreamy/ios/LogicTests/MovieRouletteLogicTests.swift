import XCTest
@testable import SoooDreamyLogic

/// Pins the Film-Roulette reducer and deck derivation.
final class MovieRouletteLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"

    // MARK: Deck

    func testDeckIsDeterministicAndIncludesCustomCards() {
        let deck = MovieRoulette.deck(seed: 5, size: 20, custom: ["Unser Lieblingsfilm"])
        XCTAssertEqual(deck.count, 20)
        XCTAssertEqual(deck.map(\.de), MovieRoulette.deck(seed: 5, size: 20,
                                                          custom: ["Unser Lieblingsfilm"]).map(\.de))
        XCTAssertTrue(deck.contains { $0.de == "Unser Lieblingsfilm" && $0.genre == "custom" })
        XCTAssertNotEqual(deck.map(\.de),
                          MovieRoulette.deck(seed: 6, size: 20, custom: ["Unser Lieblingsfilm"]).map(\.de))
    }

    func testDeckTitlesFollowDisplayLanguageButIndexesMatch() {
        let card = MovieRouletteData.cards[0]
        XCTAssertFalse(card.title(lang: "de").isEmpty)
        XCTAssertFalse(card.title(lang: "en").isEmpty)
        XCTAssertGreaterThanOrEqual(MovieRouletteData.cards.count, 50)
    }

    // MARK: Reducer

    func testMatchWhenBothLike() {
        let state = MovieRoulette.reduce(events: [
            .swipe(member: anna, index: 0, like: true),
            .swipe(member: ben, index: 0, like: false),
            .swipe(member: anna, index: 1, like: true),
            .swipe(member: ben, index: 1, like: true),
            .swipe(member: ben, index: 2, like: true),
            .swipe(member: anna, index: 2, like: true),
        ], deckSize: 20)
        XCTAssertEqual(state.matches, [1, 2])
        XCTAssertEqual(state.swipeCount(of: anna), 3)
        XCTAssertEqual(state.nextIndex(of: anna, deckSize: 20), 3)
    }

    func testReswipesAndBadIndexesAreSkipped() {
        let state = MovieRoulette.reduce(events: [
            .swipe(member: anna, index: 0, like: false),
            .swipe(member: anna, index: 0, like: true),   // re-swipe → skipped
            .swipe(member: anna, index: 99, like: true),  // out of deck → skipped
            .swipe(member: ben, index: 0, like: true),
        ], deckSize: 20)
        XCTAssertEqual(state.matches, [])
        XCTAssertEqual(state.swipes[anna]?[0], false)
    }

    func testCompletesMatchDrivesTheAnnotation() {
        let state = MovieRoulette.reduce(events: [
            .swipe(member: ben, index: 4, like: true),
        ], deckSize: 20)
        XCTAssertTrue(MovieRoulette.completesMatch(state: state, index: 4, partner: ben))
        XCTAssertFalse(MovieRoulette.completesMatch(state: state, index: 5, partner: ben))
    }

    func testFinishedWhenBothSwipedTheWholeDeck() {
        var events: [MovieRouletteEvent] = []
        for index in 0..<3 {
            events.append(.swipe(member: anna, index: index, like: false))
            events.append(.swipe(member: ben, index: index, like: false))
        }
        let state = MovieRoulette.reduce(events: events, deckSize: 3)
        XCTAssertTrue(state.finished(deckSize: 3, members: [anna, ben]))
        XCTAssertNil(state.nextIndex(of: anna, deckSize: 3))
    }
}
