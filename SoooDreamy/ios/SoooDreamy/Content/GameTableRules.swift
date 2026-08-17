import Foundation

// „Spieltische" (roadmap 22) — the pure per-game layout matrix for wide
// regular panes. On iPad a game evening wants a TABLE: the board centered
// like a physical game board, controls and history in a side rail — not a
// portrait phone layout stretched to a thousand points. Which game gets
// which arrangement is a per-game DECISION, not a blanket rule, so it lives
// here as Foundation-only data the Linux LogicTests can pin down. The SwiftUI
// half (`GameTableLayout` in Stationen/Spieltisch/GameTableView.swift) only
// renders what these rules decide.

/// The wide-pane arrangement of one game surface.
enum GameTableArrangement: String, Codable, CaseIterable {
    /// Board centered at a capped width, controls/score in a side rail
    /// (connect four, kniffel dice table, bingo card, pictionary canvas).
    case boardTable
    /// Battleship: BOTH boards visible at once — enemy waters as the big
    /// centered board, own fleet in the rail (no scrolling mid-battle).
    case duelTable
    /// Wordle/hangman: board + letter keys capped to one narrow column —
    /// a 900-point-wide keyboard is worse than a phone, not better.
    case keyboardColumn
    /// Quiz-like reading surfaces: a clean reading column is all they
    /// need (cards were designed for a hand-width measure).
    case readingColumn
}

enum GameTableRules {
    /// Wide-pane arrangement per game type (server `GameSession.type`
    /// strings plus the local "wordle" daily board). Unknown types read —
    /// a reading column can never break a future game.
    static func arrangement(forGameType type: String) -> GameTableArrangement {
        switch type {
        case "connectfour", "kniffel", "bingo", "pictionary",
             "dame", "reversi", "kaesekaestchen", "gomoku",
             "mancala", "memoryduo":
            return .boardTable
        case "battleship":
            return .duelTable
        case "wordle", "hangman":
            return .keyboardColumn
        default:
            return .readingColumn
        }
    }

    /// Absolute floor of the table threshold, independent of the game.
    /// Deliberately ABOVE the canvas rail threshold (700): the game rail
    /// is wider than the canvas tool rail (scoreboards, guess history).
    /// The REAL per-game threshold is `tableMinPaneWidth(forGameType:)` —
    /// the table only engages once its full-cap board AND the rail fit.
    static let tableMinPaneWidth: Double = 760

    /// Fixed width of the control/score rail next to the board.
    static let sidePanelWidth: Double = 320

    /// Spacing/padding unit of the table row (pane padding, board↔rail
    /// gap) — mirrors the 16-point base grid of the app.
    static let panelSpacing: Double = 16

    /// Max width of the capped keyboard column (wordle/hangman): tuned so
    /// two thumbs reach every key on a centered iPad column. Must stay
    /// below the 640 reading column — it exists to be NARROWER.
    static let keyboardColumnMax: Double = 560

    /// Per-game table threshold: the pane must hold the board AT ITS FULL
    /// CAP plus the rail plus the three spacing gaps (pane padding left +
    /// board↔rail gap + pane padding right). Engaging any earlier would
    /// SHRINK the (capped) stacked board at the very moment the "wide"
    /// layout arrives — the eval-measured 727 → 392 jump at 760 points.
    /// At exactly this width the table board equals the stacked cap, so
    /// a live resize across the threshold never changes the board size.
    static func tableMinPaneWidth(forGameType type: String) -> Double {
        max(tableMinPaneWidth,
            boardMaxWidth(forGameType: type) + sidePanelWidth + 3 * panelSpacing)
    }

    /// True when a game pane of `paneWidth` should lay out board + rail
    /// instead of the stacked phone layout. Only board/duel tables have a
    /// wide arrangement; keyboard/reading games keep one column always.
    static func usesTable(gameType: String, paneWidth: Double,
                          isRegularWidth: Bool) -> Bool {
        switch arrangement(forGameType: gameType) {
        case .boardTable, .duelTable:
            return isRegularWidth
                && paneWidth >= tableMinPaneWidth(forGameType: gameType)
        case .keyboardColumn, .readingColumn:
            return false
        }
    }

    /// Cap of the centered board region on a table, per game. The
    /// pictionary canvas earns the most room (drawing precision), connect
    /// four's 7:6 grid a bit more than the square boards. Mancala's board
    /// is a wide 6+2-pit row and the 6×6 memory tableau wants readable
    /// card faces, so both earn the canvas-sized cap.
    static func boardMaxWidth(forGameType type: String) -> Double {
        switch type {
        case "pictionary", "mancala", "memoryduo": return 640
        case "connectfour": return 620
        default: return 560
        }
    }

    /// Cap of the STACKED column below the table threshold: board cap plus
    /// the stacked layout's own edge padding (one spacing unit per side).
    /// Without this cap a stacked board keeps growing past the table cap
    /// on 760…1000-point panes and then visibly SHRINKS when the table
    /// engages — capping both sides to the same board width makes the
    /// threshold continuous in both resize directions.
    static func stackedColumnMaxWidth(forGameType type: String) -> Double {
        boardMaxWidth(forGameType: type) + 2 * panelSpacing
    }

    /// Actual width the board region gets on a table of `paneWidth`:
    /// whatever the rail leaves over, capped per game. Because the
    /// threshold already requires the full cap to fit, an ENGAGED table
    /// always shows the full-cap board — the guarantee that switching to
    /// the table never shrinks the board.
    static func boardWidth(forGameType type: String, paneWidth: Double) -> Double {
        let leftover = paneWidth - sidePanelWidth - 3 * panelSpacing
        return max(0, min(boardMaxWidth(forGameType: type), leftover))
    }
}
