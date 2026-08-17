import XCTest
@testable import SoooDreamyLogic

final class GamesWaveLogicTests: XCTestCase {
    func testWordChainValidatesDictionaryLetterAndRepeats() {
        XCTAssertEqual(
            WordChainRules.validate("Herz", after: nil, used: [], language: "de"),
            .valid
        )
        XCTAssertEqual(
            WordChainRules.validate("Zelt", after: "Herz", used: ["Herz"], language: "de"),
            .valid
        )
        XCTAssertEqual(
            WordChainRules.validate("Traum", after: "Herz", used: ["Herz"], language: "de"),
            .wrongLetter("z")
        )
        XCTAssertEqual(
            WordChainRules.validate("Zelt", after: "Herz", used: ["Herz", "zelt"], language: "de"),
            .repeated
        )
        XCTAssertEqual(
            WordChainRules.validate("Zorgle", after: nil, used: [], language: "en"),
            .unknown
        )
    }

    func testHangmanReducerTracksPendingSolvedAndForgivenessBudget() {
        let pending = HangmanRules.reduce(
            length: 3,
            guesses: [HangmanGuess(letter: "r", positions: nil)]
        )
        XCTAssertEqual(pending.pending, "r")

        let solved = HangmanRules.reduce(
            length: 3,
            guesses: [
                HangmanGuess(letter: "r", positions: [0]),
                HangmanGuess(letter: "x", positions: []),
                HangmanGuess(letter: "o", positions: [1]),
                HangmanGuess(letter: "m", positions: [2]),
            ]
        )
        XCTAssertTrue(solved.solved)
        XCTAssertFalse(solved.lost)
        XCTAssertEqual(solved.wrong, 1)
        XCTAssertEqual(HangmanRules.positions(of: "o", in: "Rom"), [1])
    }

    func testBingoPackHasSixtyBilingualActionsAndTenWinLines() {
        XCTAssertEqual(CoupleBingo.actions.count, 60)
        XCTAssertEqual(Set(CoupleBingo.actions.map(\.id)).count, 60)
        XCTAssertEqual(CoupleBingo.lines.count, 10)
        XCTAssertEqual(CoupleBingo.completedLine(checked: [0, 1, 2, 3]), [0, 1, 2, 3])
        XCTAssertNil(CoupleBingo.completedLine(checked: [0, 1, 2]))
        for action in CoupleBingo.actions {
            XCTAssertFalse(action.eventType.isEmpty)
            XCTAssertFalse(action.text.de.isEmpty)
            XCTAssertFalse(action.text.en.isEmpty)
        }
    }

    func testEveryShippedGameHasResumableThreeStepTutorial() {
        XCTAssertEqual(GameTutorialCatalog.all.count, 19)
        XCTAssertEqual(Set(GameTutorialCatalog.all.map(\.id)).count, 19)
        XCTAssertTrue(GameTutorialCatalog.all.allSatisfy { $0.steps.count == 3 })

        var progress = TutorialProgress()
        progress.advance()
        progress.advance()
        XCTAssertFalse(progress.complete)
        progress.advance()
        XCTAssertTrue(progress.complete)
        XCTAssertFalse(progress.skipped)

        var skipped = TutorialProgress()
        skipped.skip()
        XCTAssertTrue(skipped.complete)
        XCTAssertTrue(skipped.skipped)
        XCTAssertEqual(PracticeTurns.actor(turn: 7, members: ["a", "b"], soloMember: "solo"), "solo")
        XCTAssertEqual(PracticeTurns.actor(turn: 3, members: ["a", "b"], soloMember: nil), "b")
    }

    func testHangmanPracticePacksAreLargeAndBilingual() {
        XCTAssertGreaterThanOrEqual(HangmanRules.words["de"]?.count ?? 0, 180)
        XCTAssertGreaterThanOrEqual(HangmanRules.words["en"]?.count ?? 0, 180)
        XCTAssertGreaterThanOrEqual(WordChainRules.dictionaries["de"]?.count ?? 0, 100)
        XCTAssertGreaterThanOrEqual(WordChainRules.dictionaries["en"]?.count ?? 0, 100)
    }
}
