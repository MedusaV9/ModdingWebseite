import XCTest
@testable import SoooDreamyLogic

// FullRelease N1-A: the dock-width/AX5, wiggle and concentric-radius tests
// died with the custom dock — the native TabView owns bar layout now. The
// rules that stayed OURS (badge cap, re-tap scroll-to-top) stay pinned.
final class TabBarLogicTests: XCTestCase {
    func testBadgeHiddenAtZeroAndNegative() {
        XCTAssertNil(TabBarLogic.badgeText(for: 0))
        XCTAssertNil(TabBarLogic.badgeText(for: -3))
    }

    func testBadgeShowsExactCountUpToCap() {
        XCTAssertEqual(TabBarLogic.badgeText(for: 1), "1")
        XCTAssertEqual(TabBarLogic.badgeText(for: 42), "42")
        XCTAssertEqual(TabBarLogic.badgeText(for: 99), "99")
    }

    func testBadgeCapsAboveNinetyNine() {
        XCTAssertEqual(TabBarLogic.badgeText(for: 100), "99+")
        XCTAssertEqual(TabBarLogic.badgeText(for: 1_204), "99+")
    }

    // MARK: Re-tap on the active tab (HIG: return to top)

    func testReTapScrollsAScrolledVisiblePane() {
        XCTAssertTrue(TabBarLogic.shouldScrollToTop(
            alpha: 1, isHidden: false,
            contentHeight: 2_000, boundsHeight: 800,
            offsetY: 350, topInset: 59
        ))
    }

    func testReTapIgnoresParkedSiblingPanes() {
        // Parked sibling tab panes sit in the UIKit-backed TabView hidden /
        // at alpha 0 — their scroll positions must survive a re-tap.
        XCTAssertFalse(TabBarLogic.shouldScrollToTop(
            alpha: 0, isHidden: false,
            contentHeight: 2_000, boundsHeight: 800,
            offsetY: 350, topInset: 59
        ))
        XCTAssertFalse(TabBarLogic.shouldScrollToTop(
            alpha: 1, isHidden: true,
            contentHeight: 2_000, boundsHeight: 800,
            offsetY: 350, topInset: 59
        ))
    }

    func testReTapSkipsUnscrollableAndAlreadyTopSurfaces() {
        // Content shorter than the viewport has no top to return to.
        XCTAssertFalse(TabBarLogic.shouldScrollToTop(
            alpha: 1, isHidden: false,
            contentHeight: 500, boundsHeight: 800,
            offsetY: 10, topInset: 0
        ))
        // Resting at the top (offset == -topInset) is a no-op.
        XCTAssertFalse(TabBarLogic.shouldScrollToTop(
            alpha: 1, isHidden: false,
            contentHeight: 2_000, boundsHeight: 800,
            offsetY: -59, topInset: 59
        ))
    }
}
