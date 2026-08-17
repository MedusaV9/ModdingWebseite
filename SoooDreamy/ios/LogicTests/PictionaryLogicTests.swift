import XCTest
@testable import SoooDreamyLogic

/// Pins the Montagsmaler reducer — deadline math from server timestamps,
/// role switching and answer matching are protocol, not implementation.
final class PictionaryLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"
    private let t0 = Date(timeIntervalSince1970: 1_754_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    private func state(_ events: [PictionaryEvent], deck: [String] = ["Herz", "Kaktus"],
                       secs: Int = 90, now: Date) -> PictionaryState {
        Pictionary.reduce(events: events, deck: deck, starter: anna, partner: ben,
                          secs: secs, now: now)
    }

    // MARK: Deck & words

    func testDeckIsDeterministicPerLanguage() {
        let a = Pictionary.deck(seed: 7, rounds: 6, lang: "de")
        XCTAssertEqual(a, Pictionary.deck(seed: 7, rounds: 6, lang: "de"))
        XCTAssertNotEqual(a, Pictionary.deck(seed: 8, rounds: 6, lang: "de"))
        XCTAssertEqual(a.count, 6)
        XCTAssertEqual(Set(a).count, 6, "no duplicate words in one session")
    }

    func testWordListsAreBigAndAligned() {
        XCTAssertGreaterThanOrEqual(PictionaryWords.de.count, 100)
        XCTAssertGreaterThanOrEqual(PictionaryWords.en.count, 100)
        XCTAssertEqual(Set(PictionaryWords.de).count, PictionaryWords.de.count)
        XCTAssertEqual(Set(PictionaryWords.en).count, PictionaryWords.en.count)
    }

    func testNormalizeMatchesForgivingly() {
        XCTAssertEqual(Pictionary.normalize(" Heiß-Luft Ballon! "),
                       Pictionary.normalize("heissluftballon"))
        XCTAssertNotEqual(Pictionary.normalize("Herz"), Pictionary.normalize("Hase"))
    }

    // MARK: Roles & phases

    func testRolesSwapEveryRound() {
        XCTAssertEqual(Pictionary.artist(round: 0, starter: anna, partner: ben), anna)
        XCTAssertEqual(Pictionary.artist(round: 1, starter: anna, partner: ben), ben)
        XCTAssertEqual(Pictionary.artist(round: 2, starter: anna, partner: ben), anna)
    }

    func testPhaseFlowAcrossARound() {
        // Nothing started yet.
        var s = state([], now: at(0))
        XCTAssertEqual(s.phase, .waitingStart(round: 0))
        // Only the artist can start; Ben's attempt on round 0 is skipped.
        s = state([.roundStart(member: ben, round: 0, at: at(1))], now: at(1))
        XCTAssertEqual(s.phase, .waitingStart(round: 0))
        // Live round with a deadline 90s after the SERVER timestamp.
        s = state([.roundStart(member: anna, round: 0, at: at(10))], now: at(20))
        XCTAssertEqual(s.phase, .drawing(round: 0, deadline: at(100)))
        // Clock ran out → round over, unsolved.
        s = state([.roundStart(member: anna, round: 0, at: at(10))], now: at(101))
        XCTAssertEqual(s.phase, .roundOver(round: 0, solved: false))
    }

    func testCorrectGuessSolvesAndScores() {
        let events: [PictionaryEvent] = [
            .roundStart(member: anna, round: 0, at: at(0)),
            .guess(member: ben, round: 0, text: "Hase", at: at(10)),
            .guess(member: anna, round: 0, text: "Herz", at: at(11)),  // artist can't guess
            .guess(member: ben, round: 0, text: "  herz ", at: at(12)),
            .guess(member: ben, round: 0, text: "Herz", at: at(13)),   // after solve → skipped
        ]
        let s = state(events, now: at(20))
        XCTAssertEqual(s.rounds[0].solvedBy, ben)
        XCTAssertEqual(s.score(of: ben), 1)
        XCTAssertEqual(s.score(of: anna), 0)
        XCTAssertEqual(s.rounds[0].guesses.count, 2)
        XCTAssertEqual(s.phase, .roundOver(round: 0, solved: true))
        XCTAssertEqual(s.solvedCount, 1)
    }

    func testLateGuessDoesNotCount() {
        let events: [PictionaryEvent] = [
            .roundStart(member: anna, round: 0, at: at(0)),
            .guess(member: ben, round: 0, text: "Herz", at: at(91)),  // 1s too late
        ]
        let s = state(events, now: at(95))
        XCTAssertNil(s.rounds[0].solvedBy)
        XCTAssertEqual(s.score(of: ben), 0)
    }

    func testNextRoundOnlyAfterPreviousIsOver() {
        // Ben tries to start round 1 while round 0 is still live → skipped.
        var s = state([
            .roundStart(member: anna, round: 0, at: at(0)),
            .roundStart(member: ben, round: 1, at: at(30)),
        ], now: at(40))
        XCTAssertNil(s.rounds[1].startedAt)
        // After a solve the swap works and the deadline restarts.
        s = state([
            .roundStart(member: anna, round: 0, at: at(0)),
            .guess(member: ben, round: 0, text: "Herz", at: at(5)),
            .roundStart(member: ben, round: 1, at: at(30)),
        ], now: at(40))
        XCTAssertEqual(s.phase, .drawing(round: 1, deadline: at(120)))
    }

    func testFinishedAfterLastRound() {
        let s = state([
            .roundStart(member: anna, round: 0, at: at(0)),
            .guess(member: ben, round: 0, text: "Herz", at: at(5)),
            .roundStart(member: ben, round: 1, at: at(10)),
            .guess(member: anna, round: 1, text: "Kaktus", at: at(15)),
        ], now: at(20))
        XCTAssertEqual(s.phase, .finished)
        XCTAssertEqual(s.score(of: anna), 1)
        XCTAssertEqual(s.score(of: ben), 1)
        XCTAssertEqual(s.solvedCount, 2)
    }
}
