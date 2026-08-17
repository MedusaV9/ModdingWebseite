import Foundation

/// Pure presentation rules for the tab bar — Foundation-only so the Linux
/// LogicTests can pin the behavior. FullRelease N1-A: the native iOS-26
/// `TabView` replaced the custom dock, and everything the system now owns
/// (dock-width contract, AX5 icon cap, wiggle keyframes, concentric radii)
/// is gone. What remains is OUR logic on top of the system bar: the badge
/// text and the re-tap scroll-to-top rule.
enum TabBarLogic {
    /// Largest count shown as an exact number; anything above renders "99+".
    static let badgeCap = 99

    /// Display text for an item badge. `nil` hides the badge entirely.
    static func badgeText(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > badgeCap ? "\(badgeCap)+" : "\(count)"
    }

    // MARK: Re-tap on the active tab (HIG: return to top)

    /// Minimum downward travel (beyond the top inset) before a re-tap
    /// scroll actually animates — spares a no-op glide at the very top.
    static let reselectScrollTolerance: Double = 1

    /// True when a scroll surface should glide back to its top after the
    /// active tab was re-tapped: it must be visible (parked sibling tab
    /// panes stay untouched), genuinely scrollable in the vertical axis,
    /// and not already resting at the top.
    static func shouldScrollToTop(alpha: Double, isHidden: Bool,
                                  contentHeight: Double, boundsHeight: Double,
                                  offsetY: Double, topInset: Double) -> Bool {
        guard !isHidden, alpha > 0.01 else { return false }
        guard contentHeight > boundsHeight else { return false }
        return offsetY > -topInset + reselectScrollTolerance
    }
}
