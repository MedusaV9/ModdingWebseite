import SwiftUI

// „Spieltische" (roadmap 22) — the SwiftUI half of GameTableRules
// (Content/GameTableRules.swift, Foundation-only + tested). Two pieces:
//
//   * `GameTableContainer` measures the REAL pane width (GeometryReader,
//     never UIScreen — Split View / Stage Manager panes are not screens)
//     and picks table vs. the untouched stacked phone layout live, so
//     dragging a window across the threshold swaps layouts mid-flight.
//   * `GameTableLayout` renders the table: board centered at its
//     rule-capped width, controls/score in a fixed-width trailing rail.
//
// The phone layouts stay EXACTLY as they were — each game view keeps its
// stacked screen and only gains the wide arrangement.

/// Live width-driven switch between the wide game table and the stacked
/// phone layout of one game screen.
struct GameTableContainer<Table: View, Stacked: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let gameType: String
    @ViewBuilder var table: (CGFloat) -> Table
    @ViewBuilder var stacked: () -> Stacked

    var body: some View {
        GeometryReader { geo in
            if GameTableRules.usesTable(gameType: gameType,
                                        paneWidth: Double(geo.size.width),
                                        isRegularWidth: horizontalSizeClass == .regular) {
                table(geo.size.width)
            } else {
                stacked()
                    // Below the (per-game) table threshold the stacked
                    // column is capped to the SAME board width the table
                    // will show — a live resize across the threshold never
                    // shrinks the board (GameTableRules, eval: 727→392 at
                    // 760 points). Phones sit under the cap anyway.
                    .frame(maxWidth: CGFloat(
                        GameTableRules.stackedColumnMaxWidth(forGameType: gameType)))
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// One wide game table: centered board + trailing control rail, both in a
/// shared scroll (tall rails — kniffel scoreboard, pictionary guesses —
/// scroll with the board instead of clipping).
struct GameTableLayout<Board: View, Rail: View>: View {
    let gameType: String
    let paneWidth: CGFloat
    @ViewBuilder var board: () -> Board
    @ViewBuilder var rail: () -> Rail

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: LayoutMetrics.s(16)) {
                board()
                    .frame(maxWidth: CGFloat(GameTableRules.boardWidth(
                        forGameType: gameType, paneWidth: Double(paneWidth))))
                    .frame(maxWidth: .infinity)
                rail()
                    .frame(width: CGFloat(GameTableRules.sidePanelWidth))
            }
            .padding(LayoutMetrics.s(16))
        }
    }
}
