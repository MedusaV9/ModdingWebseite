import Foundation

enum AccessibilityBudget {
    static func particleLimit(
        intensity: DelightIntensity,
        reduceMotion: Bool,
        accessibilityText: Bool
    ) -> Int {
        if reduceMotion { return 0 }
        let normal: Int
        switch intensity {
        case .small: normal = 14
        case .medium: normal = 30
        case .epic: normal = 64
        }
        return accessibilityText ? min(normal, 32) : normal
    }

    static func prefersVerticalLayout(accessibilityText: Bool, availableWidth: Double) -> Bool {
        accessibilityText || availableWidth < 340
    }

    /// Grid columns under Dynamic Type (EVAL AX5): multi-column grids
    /// collapse BEFORE their labels shatter into single letters — the
    /// 3-column touch grid drops to 2 at the first accessibility sizes and
    /// to a single column at the giant ones. `accessibilityLevel` is 0
    /// outside the accessibility sizes and 1…5 for AX1…AX5.
    static func gridColumns(regular: Int, accessibilityLevel: Int) -> Int {
        let base = max(regular, 1)
        guard base > 1, accessibilityLevel > 0 else { return base }
        return accessibilityLevel >= 3 ? 1 : min(base, 2)
    }

    /// Persistent side chrome (the chat rail, the Memories section sidebar)
    /// collapses at accessibility text sizes (FXD-2 #4): giant type needs
    /// the whole pane for the content column, and fixed-width chrome would
    /// truncate every label it holds. Nothing becomes unreachable — the
    /// chat rail only LINKS existing features, and Memories falls back to
    /// its toolbar-toggled overlay sidebar.
    static func sideChromeCollapses(accessibilityText: Bool) -> Bool {
        accessibilityText
    }
}
