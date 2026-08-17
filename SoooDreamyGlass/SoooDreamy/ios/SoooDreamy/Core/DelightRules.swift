import Foundation

// Delight-Engine — pure rules layer (Foundation-only, Linux-testable).
// The SwiftUI/haptics/sound half lives in Core/Delight.swift; THIS file only
// answers "is this a moment, and how big?" so the delight language stays
// curated in one place instead of scattered ad-hoc confetti.

/// How big a celebration is. The engine maps each intensity to a fixed
/// choreography (particles + haptic motif + sound sting) so every feature
/// that calls `Delight.celebrate(...)` feels part of the same language.
enum DelightIntensity: String, Codable, CaseIterable, Comparable {
    case small, medium, epic

    private var rank: Int {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .epic: return 2
        }
    }

    static func < (lhs: DelightIntensity, rhs: DelightIntensity) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Central milestone rules: round counters, streaks and level-ups.
/// All functions are pure — callers inject the current values, nothing
/// reads clocks or state here (see AGENTS.md on injected time).
enum DelightRules {
    /// Lifetime-counter milestones (messages sent, touches, photos, …).
    /// Returns nil for non-milestones. The curve celebrates early progress
    /// (10, 25) softly, mid milestones (50, 100) noticeably and big round
    /// numbers (every 250 up to 1000, then every 500) epically.
    static func milestone(forCount count: Int) -> DelightIntensity? {
        switch count {
        case 10, 25: return .small
        case 50, 100: return .medium
        case 250, 500, 750, 1000: return .epic
        default:
            return count > 1000 && count % 500 == 0 ? .epic : nil
        }
    }

    /// Streak milestones (consecutive days): 3 is a soft nudge, a full week
    /// and two weeks feel real, a month and beyond deserve fireworks.
    static func milestone(forStreak days: Int) -> DelightIntensity? {
        switch days {
        case 3: return .small
        case 7, 14: return .medium
        case 30, 50, 100, 200, 365: return .epic
        default:
            return days > 365 && days % 365 == 0 ? .epic : nil
        }
    }

    /// Level-ups are always the biggest moment in the delight language.
    static func intensity(forLevelUp newLevel: Int) -> DelightIntensity {
        _ = newLevel
        return .epic
    }

    /// Badge unlocks: secret badges get the full ceremony, regular ones a
    /// medium burst (the shelf view itself adds the shine).
    static func intensity(forBadgeSecret secret: Bool) -> DelightIntensity {
        secret ? .epic : .medium
    }
}
