import SwiftUI

/// DS — the named token vocabulary of the DesignSystem module (redesign
/// wave 1, see REDESIGN.md). Lives INSIDE the UI layer on purpose: the
/// charter allows raw design values only here. Everything below either
/// aliases an existing Theme token or names a NEW value once, so feature
/// code keeps referencing names, never numbers (commandment 11).
///
/// The module extends the Papier & Licht vocabulary — it never competes
/// with it: motion comes from `Theme.Motion`, surfaces from the paper/
/// night cards, color from `CoupleTint` and the Licht/Nacht families.
enum DS {

    // MARK: Press response

    /// The visible answer of a touchable surface (commandment 14: the UI
    /// answers in the frame of the tap). One scale, one curve — every
    /// pressable card and chrome circle breathes the same way.
    enum Press {
        /// Resting → pressed scale for cards, tiles and chrome circles.
        static let scale: CGFloat = 0.96
        /// Slightly deeper for small round controls (avatars, icon dots),
        /// where 0.96 is barely visible.
        static let compactScale: CGFloat = 0.92
        /// The one press curve — the settle spring of the motion library.
        static var animation: Animation { Theme.Motion.settle }
    }

    // MARK: Ambient breathing (AnimatedBackground)

    /// The Atemglühen of the living room background: two glow fields in
    /// the couple's colors breathe under the lamp cone. Deliberately
    /// QUIET — the peaks stay far below the lamp cone's pinned 0.30
    /// paint, so every night-ink contrast anchor keeps its margin.
    enum Atem {
        /// One full in-and-out breath, in seconds. Ambience is measured
        /// in many seconds (Theme.Motion.drift philosophy).
        static let period: TimeInterval = 9
        /// Peak opacity of the primary-color glow.
        static let peakPrimary: Double = 0.10
        /// Peak opacity of the secondary-color glow (asymmetry keeps the
        /// room from pulsing like a metronome).
        static let peakSecondary: Double = 0.07
        /// Frame budget of the breathing canvas — ambience never renders
        /// faster than this (the ink dust runs at 12 Hz; the breath is
        /// slower and needs even less).
        static let hz: Double = 8
        /// Anchor points of the two glow fields, in unit space. Fixed and
        /// named — seeded per-couple positions read as flicker between
        /// launches, which ambience must never do.
        static let primaryCenter = UnitPoint(x: 0.78, y: 0.24)
        static let secondaryCenter = UnitPoint(x: 0.24, y: 0.72)
        /// Glow radius as a fraction of the longer screen side.
        static let radiusFactor: CGFloat = 0.42
        /// How far the breath swells the radius around its resting size.
        static let radiusSwell: CGFloat = 0.08
        /// Phase offset of the second glow (radians) — the two fields
        /// breathe against each other, never in metronome lockstep.
        static let secondaryPhase: Double = 1.9
    }

    // MARK: Chips

    /// Capsule chip metrics — one rhythm for every selectable chip.
    enum Chip {
        static var verticalPadding: CGFloat { LayoutMetrics.s(6) }
        static var horizontalPadding: CGFloat { LayoutMetrics.s(12) }
        /// Icon-to-label gap inside a chip.
        static var spacing: CGFloat { Space.xs }
        /// Fill opacity of a QUIET chip (done/passive state) — the tint
        /// whispers instead of filling. Increased Contrast firms it up
        /// so the capsule still reads as a surface.
        static func quietFill(increased: Bool) -> Double {
            increased ? 0.24 : 0.14
        }
    }

    // MARK: Empty-state choreography

    /// The arrival moment of a DSEmptyState: the symbol bounces ONCE and
    /// the Lichtschein blooms behind it — an invitation, not a loop.
    enum Leben {
        /// Diameter of the glow behind the empty-state symbol.
        static var glowSize: CGFloat { LayoutMetrics.s(140) }
        /// Delay before the one welcome bounce, so the card lands first.
        static let bounceDelay: TimeInterval = 0.35
        /// Scale the symbol starts from before its one welcome bounce.
        static let startScale: CGFloat = 0.6
        /// Resting opacity of the lamp-gold bloom behind the symbol —
        /// quieter than the celebration Lichtschein (0.22): an empty
        /// state invites, it does not celebrate.
        static let glowOpacity: Double = 0.16
    }
}
