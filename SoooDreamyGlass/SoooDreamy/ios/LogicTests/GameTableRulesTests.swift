import XCTest
@testable import SoooDreamyLogic

/// Pins the „Spieltische" matrix (roadmap 22): which game gets which
/// wide-pane arrangement, when the table engages, and that moving to the
/// table never shrinks the board below a phone-sized one.
final class GameTableRulesTests: XCTestCase {

    // MARK: Matrix

    func testBoardGamesSitAtTheTable() {
        for type in ["connectfour", "kniffel", "bingo", "pictionary",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            XCTAssertEqual(GameTableRules.arrangement(forGameType: type),
                           .boardTable, type)
        }
    }

    func testBattleshipGetsTheDuelTable() {
        XCTAssertEqual(GameTableRules.arrangement(forGameType: "battleship"),
                       .duelTable)
    }

    func testLetterGamesKeepANarrowKeyboardColumn() {
        for type in ["wordle", "hangman"] {
            XCTAssertEqual(GameTableRules.arrangement(forGameType: type),
                           .keyboardColumn, type)
        }
    }

    func testQuizLikeGamesReadInAColumn() {
        // The complete remaining inventory of game types — a new game
        // landing here by default is deliberate (reading never breaks).
        for type in ["quiz", "thisorthat", "wouldyourather", "truthordare",
                     "questions36", "emojiriddle", "quizduel", "photomemory",
                     "movieroulette", "stadtlandfluss", "twotruths",
                     "dailyquests", "wordchain"] {
            XCTAssertEqual(GameTableRules.arrangement(forGameType: type),
                           .readingColumn, type)
        }
        XCTAssertEqual(GameTableRules.arrangement(forGameType: "somefuturegame"),
                       .readingColumn)
    }

    // MARK: Table threshold

    func testTableNeedsRegularWidthAndARealPane() {
        // Compact width never gets a table, no matter how wide the pane
        // (landscape phone reports compact — the stacked layout stays).
        XCTAssertFalse(GameTableRules.usesTable(gameType: "connectfour",
                                                paneWidth: 1600,
                                                isRegularWidth: false))
        // Regular width but a narrow split-view slot: stacked.
        let threshold = GameTableRules.tableMinPaneWidth(forGameType: "connectfour")
        XCTAssertFalse(GameTableRules.usesTable(gameType: "connectfour",
                                                paneWidth: threshold - 1,
                                                isRegularWidth: true))
        // Regular and wide enough for the FULL board cap + rail: table.
        XCTAssertTrue(GameTableRules.usesTable(gameType: "connectfour",
                                               paneWidth: threshold,
                                               isRegularWidth: true))
        XCTAssertTrue(GameTableRules.usesTable(gameType: "battleship",
                                               paneWidth: 1180,
                                               isRegularWidth: true))
    }

    func testPerGameThresholdRequiresCapAndRailToFit() {
        // The threshold formula itself: full board cap + rail + the three
        // spacing gaps. Engaging earlier would shrink the board on switch.
        for type in ["connectfour", "kniffel", "bingo", "pictionary", "battleship",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            XCTAssertEqual(GameTableRules.tableMinPaneWidth(forGameType: type),
                           GameTableRules.boardMaxWidth(forGameType: type)
                               + GameTableRules.sidePanelWidth
                               + 3 * GameTableRules.panelSpacing,
                           type)
        }
    }

    func testBoundaryWidthsStayStackedUntilTheTableTrulyFits() {
        // The eval-measured discontinuity: at 760 the OLD threshold flipped
        // dame to a 392-point table board while the stacked board had ~727.
        // 759 AND 760 now both stay stacked; the square boards (cap 560)
        // switch at 928, connect four (620) at 988, the 640-cap boards at
        // 1008 — each exactly where the full-cap board + rail fit.
        for width in [759.0, 760.0] {
            XCTAssertFalse(GameTableRules.usesTable(gameType: "dame",
                                                    paneWidth: width,
                                                    isRegularWidth: true), "\(width)")
        }
        // 1000: square boards + connect four sit at the table (full cap),
        // the 640-cap boards (threshold 1008) still stack.
        XCTAssertTrue(GameTableRules.usesTable(gameType: "dame",
                                               paneWidth: 1000,
                                               isRegularWidth: true))
        XCTAssertEqual(GameTableRules.boardWidth(forGameType: "dame", paneWidth: 1000), 560)
        XCTAssertTrue(GameTableRules.usesTable(gameType: "connectfour",
                                               paneWidth: 1000,
                                               isRegularWidth: true))
        XCTAssertEqual(GameTableRules.boardWidth(forGameType: "connectfour",
                                                 paneWidth: 1000), 620)
        XCTAssertFalse(GameTableRules.usesTable(gameType: "pictionary",
                                                paneWidth: 1000,
                                                isRegularWidth: true))
        // 1100: every board game sits at the table with its full cap.
        for type in ["connectfour", "kniffel", "bingo", "pictionary", "battleship",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            XCTAssertTrue(GameTableRules.usesTable(gameType: type,
                                                   paneWidth: 1100,
                                                   isRegularWidth: true), type)
            XCTAssertEqual(GameTableRules.boardWidth(forGameType: type, paneWidth: 1100),
                           GameTableRules.boardMaxWidth(forGameType: type), type)
        }
    }

    func testThresholdIsContinuousInBoardWidth() {
        // No layout may shrink the board during a live resize: right AT the
        // per-game threshold the table board equals the full cap — which is
        // exactly what the capped stacked column shows just below it.
        for type in ["connectfour", "kniffel", "bingo", "pictionary", "battleship",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            let threshold = GameTableRules.tableMinPaneWidth(forGameType: type)
            let cap = GameTableRules.boardMaxWidth(forGameType: type)
            XCTAssertEqual(GameTableRules.boardWidth(forGameType: type,
                                                     paneWidth: threshold),
                           cap, type)
            // Stacked column cap = board cap + its own edge padding, so the
            // stacked board tops out at the same width the table shows.
            XCTAssertEqual(GameTableRules.stackedColumnMaxWidth(forGameType: type),
                           cap + 2 * GameTableRules.panelSpacing, type)
        }
    }

    func testKeyboardAndReadingGamesNeverTable() {
        for type in ["wordle", "hangman", "quiz", "twotruths"] {
            XCTAssertFalse(GameTableRules.usesTable(gameType: type,
                                                    paneWidth: 1400,
                                                    isRegularWidth: true), type)
        }
    }

    func testTableThresholdStaysAboveTheCanvasRailThreshold() {
        // The game rail is wider than the canvas tool rail — engaging the
        // table earlier than the canvas rail would shrink boards. Holds for
        // the floor AND for every per-game threshold built on top of it.
        XCTAssertGreaterThanOrEqual(GameTableRules.tableMinPaneWidth,
                                    LayoutRules.canvasRailMinWidth)
        for type in ["connectfour", "battleship", "dame", "pictionary"] {
            XCTAssertGreaterThanOrEqual(
                GameTableRules.tableMinPaneWidth(forGameType: type),
                GameTableRules.tableMinPaneWidth, type)
        }
    }

    // MARK: Board sizing

    func testBoardAtThresholdIsStillPhoneSized() {
        // The guarantee that makes the threshold honest: at each game's own
        // minimum table width every board still gets ≥ the ~360-point board
        // a phone layout shows — the table never trades size for furniture.
        for type in ["connectfour", "kniffel", "bingo", "pictionary", "battleship",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            let width = GameTableRules.boardWidth(
                forGameType: type,
                paneWidth: GameTableRules.tableMinPaneWidth(forGameType: type))
            XCTAssertGreaterThanOrEqual(width, 360, type)
        }
    }

    func testBoardWidthIsCappedPerGame() {
        // A full 13" landscape pane must not blow boards up to wall size.
        for type in ["connectfour", "kniffel", "bingo", "pictionary", "battleship",
                     "dame", "reversi", "kaesekaestchen", "gomoku",
                     "mancala", "memoryduo"] {
            let cap = GameTableRules.boardMaxWidth(forGameType: type)
            XCTAssertEqual(GameTableRules.boardWidth(forGameType: type, paneWidth: 1600),
                           cap, type)
            XCTAssertLessThanOrEqual(cap, 640, type)
        }
        // Drawing precision: the pictionary canvas earns the biggest board.
        XCTAssertGreaterThan(GameTableRules.boardMaxWidth(forGameType: "pictionary"),
                             GameTableRules.boardMaxWidth(forGameType: "bingo"))
        // The wide mancala row and the 6×6 memory tableau earn the canvas cap.
        XCTAssertEqual(GameTableRules.boardMaxWidth(forGameType: "mancala"), 640)
        XCTAssertEqual(GameTableRules.boardMaxWidth(forGameType: "memoryduo"), 640)
        // The square boards keep the standard square cap.
        for type in ["dame", "reversi", "kaesekaestchen", "gomoku"] {
            XCTAssertEqual(GameTableRules.boardMaxWidth(forGameType: type), 560, type)
        }
    }

    func testBoardWidthNeverGoesNegative() {
        XCTAssertEqual(GameTableRules.boardWidth(forGameType: "bingo", paneWidth: 0), 0)
        XCTAssertEqual(GameTableRules.boardWidth(forGameType: "bingo", paneWidth: 300), 0)
    }

    func testKeyboardColumnIsNarrowerThanTheReadingColumn() {
        // 640 is the reading column (LayoutMetrics.readingColumnMax) —
        // the keyboard column exists to be narrower than that.
        XCTAssertLessThan(GameTableRules.keyboardColumnMax, 640)
        XCTAssertGreaterThanOrEqual(GameTableRules.keyboardColumnMax, 430)
    }
}
