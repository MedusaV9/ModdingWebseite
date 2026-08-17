import XCTest
@testable import SoooDreamyLogic

/// Pins the replay time-lapse, the turning-point pick and the highlight
/// rules — the pure heart of the replay & spectator feature.
final class ReplayLogicTests: XCTestCase {
    func testEveryCanonicalGameHasAnExplicitReplayAdapter() {
        XCTAssertEqual(Set(Replay.supportedGameTypes).count, Replay.supportedGameTypes.count)
        XCTAssertTrue(Replay.supportedGameTypes.allSatisfy { Replay.adapter(for: $0) != nil })
        XCTAssertNil(Replay.adapter(for: "future-unknown-game"))
        XCTAssertEqual(Replay.adapter(for: "connectfour"), .board)
        XCTAssertEqual(Replay.adapter(for: "pictionary"), .drawing)
        XCTAssertEqual(Replay.adapter(for: "wordleduo"), .word)
        XCTAssertEqual(Replay.adapter(for: "story"), .story)
    }

    func testBoardDuelWaveIsRegisteredForReplay() {
        // The six W8C games are replayable: five boards and the card tableau.
        for type in ["dame", "reversi", "kaesekaestchen", "gomoku", "mancala"] {
            XCTAssertEqual(Replay.adapter(for: type), .board, type)
        }
        XCTAssertEqual(Replay.adapter(for: "memoryduo"), .cards)
        XCTAssertTrue(Set(Replay.supportedGameTypes).isSuperset(of: [
            "dame", "reversi", "kaesekaestchen", "gomoku", "mancala", "memoryduo",
        ]))

        // Highlight rules — magnitude carries the stored move weight.
        XCTAssertTrue(Replay.isHighlight(gameType: "dame", moveKind: "move", magnitude: 2))
        XCTAssertFalse(Replay.isHighlight(gameType: "dame", moveKind: "move", magnitude: 1))
        XCTAssertTrue(Replay.isHighlight(gameType: "reversi", moveKind: "place", magnitude: 4))
        XCTAssertFalse(Replay.isHighlight(gameType: "reversi", moveKind: "place", magnitude: 3))
        XCTAssertTrue(Replay.isHighlight(gameType: "kaesekaestchen", moveKind: "edge", magnitude: 2))
        XCTAssertFalse(Replay.isHighlight(gameType: "kaesekaestchen", moveKind: "edge", magnitude: 1))
        XCTAssertTrue(Replay.isHighlight(gameType: "mancala", moveKind: "sow", magnitude: 1))
        XCTAssertFalse(Replay.isHighlight(gameType: "mancala", moveKind: "sow", magnitude: 0))
        XCTAssertTrue(Replay.isHighlight(gameType: "memoryduo", moveKind: "flip", magnitude: 1))
        // photomemory flips keep their old quiet feed (type-scoped rule).
        XCTAssertFalse(Replay.isHighlight(gameType: "photomemory", moveKind: "flip", magnitude: 1))
        // Gomoku has no mid-game highlight — the winning stone IS the ending.
        XCTAssertFalse(Replay.isHighlight(gameType: "gomoku", moveKind: "place", magnitude: 5))

        // Feed glyphs — "place" differs per stone color convention.
        XCTAssertEqual(Replay.stepEmoji(gameType: "gomoku", moveKind: "place"), "⚫️")
        XCTAssertEqual(Replay.stepEmoji(gameType: "reversi", moveKind: "place"), "⚪️")
        XCTAssertEqual(Replay.stepEmoji(gameType: "mancala", moveKind: "sow"), "🌱")
        XCTAssertEqual(Replay.stepEmoji(gameType: "memoryduo", moveKind: "flip"), "🃏")
    }

    func testPlaybackDelayCompressesAsyncGaps() {
        // A 3-hour async pause becomes a watchable beat …
        XCTAssertEqual(Replay.playbackDelay(forGap: 3 * 3600, speed: 1), Replay.maxDelay)
        // … rapid-fire moves stay readable …
        XCTAssertEqual(Replay.playbackDelay(forGap: 0.05, speed: 1), Replay.minDelay)
        // … and in-between gaps pass through.
        XCTAssertEqual(Replay.playbackDelay(forGap: 1.4, speed: 1), 1.4, accuracy: 0.001)
        // Speed divides the delay.
        XCTAssertEqual(Replay.playbackDelay(forGap: 1.4, speed: 2), 0.7, accuracy: 0.001)
    }

    func testDelaysMapWholeLists() {
        let delays = Replay.delays(gaps: [0, 7200, 1], speed: 1)
        XCTAssertEqual(delays, [Replay.minDelay, Replay.maxDelay, 1])
    }

    func testTurningPointIsLastHighlightBeforeTheEnd() {
        XCTAssertEqual(Replay.turningPoint(highlights: [false, true, false, true, false]), 3)
        // The final move itself is the ending, not the turn of the tide.
        XCTAssertEqual(Replay.turningPoint(highlights: [false, true, false, false, true]), 1)
        XCTAssertNil(Replay.turningPoint(highlights: [false, false, false]))
        XCTAssertNil(Replay.turningPoint(highlights: []))
        XCTAssertNil(Replay.turningPoint(highlights: [true]), "single move → no drama")
    }

    func testHighlightRules() {
        XCTAssertTrue(Replay.isHighlight(gameType: "battleship", moveKind: "report", magnitude: 1))
        XCTAssertFalse(Replay.isHighlight(gameType: "battleship", moveKind: "report", magnitude: 0))
        XCTAssertTrue(Replay.isHighlight(gameType: "kniffel", moveKind: "score", magnitude: 30))
        XCTAssertFalse(Replay.isHighlight(gameType: "kniffel", moveKind: "score", magnitude: 8))
        XCTAssertTrue(Replay.isHighlight(gameType: "twotruths", moveKind: "reveal", magnitude: 0))
        XCTAssertTrue(Replay.isHighlight(gameType: "movieroulette", moveKind: "swipe", magnitude: 1))
        XCTAssertFalse(Replay.isHighlight(gameType: "movieroulette", moveKind: "swipe", magnitude: 0))
        XCTAssertFalse(Replay.isHighlight(gameType: "quiz", moveKind: "answer", magnitude: 9))
    }

    func testStepEmojiKnowsTheProtocolsAndFallsBack() {
        XCTAssertEqual(Replay.stepEmoji(gameType: "battleship", moveKind: "salvo"), "💣")
        XCTAssertEqual(Replay.stepEmoji(gameType: "movieroulette", moveKind: "swipe"), "🍿")
        XCTAssertEqual(Replay.stepEmoji(gameType: "kniffel", moveKind: "roll"), "🎲")
        XCTAssertEqual(Replay.stepEmoji(gameType: "quiz", moveKind: "answer"), "▶️")
    }
}
