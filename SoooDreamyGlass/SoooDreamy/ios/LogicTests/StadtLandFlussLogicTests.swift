import XCTest
@testable import SoooDreamyLogic

/// Pins the Stadt-Land-Fluss reducer — the anti-spoiler ordering and the
/// classic 20/10/5 scoring are protocol.
final class StadtLandFlussLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"
    private let t0 = Date(timeIntervalSince1970: 1_754_000_000)

    private func state(_ events: [SLFEvent], rounds: Int = 2, categories: Int = 3) -> SLFState {
        StadtLandFluss.reduce(events: events, rounds: rounds, categoryCount: categories,
                              starter: anna, partner: ben)
    }

    // MARK: Letters & encoding

    func testLettersAreDeterministicAndUnique() {
        let letters = StadtLandFluss.letters(seed: 3, rounds: 5)
        XCTAssertEqual(letters, StadtLandFluss.letters(seed: 3, rounds: 5))
        XCTAssertEqual(Set(letters).count, 5)
        XCTAssertNotEqual(letters, StadtLandFluss.letters(seed: 4, rounds: 5))
    }

    func testAnswerEncodingRoundTrips() {
        let joined = StadtLandFluss.encodeAnswers(["Berlin", "", "Rhein"])
        XCTAssertEqual(StadtLandFluss.decodeAnswers(joined, categoryCount: 3),
                       ["Berlin", "", "Rhein"])
        // Short reveals are padded, long ones trimmed.
        XCTAssertEqual(StadtLandFluss.decodeAnswers("Bonn", categoryCount: 3), ["Bonn", "", ""])
    }

    func testLetterAutoCheck() {
        XCTAssertTrue(StadtLandFluss.startsCorrectly(" berlin", letter: "B"))
        XCTAssertFalse(StadtLandFluss.startsCorrectly("Hamburg", letter: "B"))
        XCTAssertFalse(StadtLandFluss.startsCorrectly("", letter: "B"))
    }

    // MARK: Anti-spoiler ordering

    func testRevealOnlyAfterBothCommits() {
        // Ben tries to reveal before Anna committed → skipped.
        var s = state([
            .commit(member: ben, round: 0, at: t0),
            .reveal(member: ben, round: 0, text: "Bonn", serverVerified: true),
        ])
        XCTAssertNil(s.rounds[0].answers[ben])
        XCTAssertEqual(s.rounds[0].phase(members: [anna, ben]), .collecting)
        // After both commits the reveal lands.
        s = state([
            .commit(member: ben, round: 0, at: t0),
            .commit(member: anna, round: 0, at: t0.addingTimeInterval(5)),
            .reveal(member: ben, round: 0, text: "Bonn", serverVerified: true),
        ])
        XCTAssertEqual(s.rounds[0].answers[ben]?.first, "Bonn")
        XCTAssertEqual(s.rounds[0].firstCommitAt, t0)
        XCTAssertEqual(s.rounds[0].phase(members: [anna, ben]), .revealing)
    }

    func testRatingOnlyAfterBothReveals() {
        let base: [SLFEvent] = [
            .commit(member: anna, round: 0, at: t0),
            .commit(member: ben, round: 0, at: t0),
            .reveal(member: anna, round: 0, text: "Berlin", serverVerified: true),
        ]
        var s = state(base + [.rate(member: anna, round: 0, verdicts: [true, true, true])])
        XCTAssertNil(s.rounds[0].ratings[anna])
        s = state(base + [
            .reveal(member: ben, round: 0, text: "Bonn", serverVerified: true),
            .rate(member: anna, round: 0, verdicts: [true, true, true]),
            .rate(member: ben, round: 0, verdicts: [true, false, true]),
        ])
        XCTAssertEqual(s.rounds[0].phase(members: [anna, ben]), .done)
        XCTAssertEqual(s.currentRound, 1)
    }

    func testRoundGatingBlocksFutureRounds() {
        let s = state([.commit(member: anna, round: 1, at: t0)])
        XCTAssertNil(s.rounds[1].commits[anna], "round 1 locked while round 0 is open")
    }

    // MARK: Scoring

    private func doneRound(mine: [String], theirs: [String],
                           myVerdicts: [Bool], theirVerdicts: [Bool]) -> SLFRound {
        var round = SLFRound()
        round.commits = [anna: t0, ben: t0]
        round.answers = [anna: mine, ben: theirs]
        round.revealVerified = [anna: true, ben: true]
        // ratings[X] = X's verdicts about the PARTNER's answers.
        round.ratings = [anna: myVerdicts, ben: theirVerdicts]
        return round
    }

    func testClassicPointsPerCategory() {
        // Categories: Stadt, Land, Fluss — letter B.
        let round = doneRound(
            mine: ["Berlin", "Brasilien", "Donau"],      // Donau fails the letter check
            theirs: ["Berlin", "", "Brigach"],
            myVerdicts: [true, true, true],              // anna approves ben's answers
            theirVerdicts: [true, true, true]            // ben approves anna's answers
        )
        // Both "Berlin" → 5 each.
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 0, letter: "B",
                                             member: anna, partner: ben), 5)
        // Anna exclusive valid ("Brasilien" vs empty) → 20.
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 1, letter: "B",
                                             member: anna, partner: ben), 20)
        // Anna's "Donau" fails the auto letter check → 0; Ben exclusive → 20.
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 2, letter: "B",
                                             member: anna, partner: ben), 0)
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 2, letter: "B",
                                             member: ben, partner: anna), 20)
    }

    func testVetoedAnswerScoresZero() {
        let round = doneRound(
            mine: ["Bxxzz", "Belgien", "Breg"],
            theirs: ["Bern", "Bolivien", "Breg"],
            myVerdicts: [true, true, true],
            theirVerdicts: [false, true, true]           // ben vetoes anna's "Bxxzz"
        )
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 0, letter: "B",
                                             member: anna, partner: ben), 0)
        // Valid but different → 10 each; same → 5 each.
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 1, letter: "B",
                                             member: anna, partner: ben), 10)
        XCTAssertEqual(StadtLandFluss.points(round: round, category: 2, letter: "B",
                                             member: ben, partner: anna), 5)
    }

    func testTotalAcrossRoundsViaFullReduce() {
        let answersA = StadtLandFluss.encodeAnswers(["Berlin", "Belgien", "Breg"])
        let answersB = StadtLandFluss.encodeAnswers(["Bern", "Belgien", ""])
        let s = state([
            .commit(member: anna, round: 0, at: t0),
            .commit(member: ben, round: 0, at: t0),
            .reveal(member: anna, round: 0, text: answersA, serverVerified: true),
            .reveal(member: ben, round: 0, text: answersB, serverVerified: true),
            .rate(member: anna, round: 0, verdicts: [true, true, true]),
            .rate(member: ben, round: 0, verdicts: [true, true, true]),
        ], rounds: 1)
        // anna: 10 (different) + 5 (same) + 20 (exclusive) = 35
        XCTAssertEqual(StadtLandFluss.total(state: s, letters: ["B"], categoryCount: 3,
                                            member: anna, partner: ben), 35)
        // ben: 10 + 5 + 0 = 15
        XCTAssertEqual(StadtLandFluss.total(state: s, letters: ["B"], categoryCount: 3,
                                            member: ben, partner: anna), 15)
        XCTAssertTrue(s.finished)
    }
}
