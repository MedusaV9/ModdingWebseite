import Foundation

// „AHAP-Partituren + Sieg-Motive über Delight-Budget" (roadmap 24) — the
// pure ceremony rules of the games layer. Which game event may celebrate
// HOW BIG, with an anti-inflation budget: when every match win is epic,
// none is (DESIGN.md Gebot 4). Foundation-only; the runtime half
// (GameEndCelebration in Stationen/Spieltisch/PlayHubView.swift) only performs
// what these rules grant. Milestone COUNTER rules live in
// Core/DelightRules.swift — this file owns the game-EVENT ceremonies.

/// A celebratable game event, from the smallest (a move landing) to the
/// rarest (a season milestone).
enum GameCeremonyEvent: String, Codable, CaseIterable {
    case move
    case roundWon
    case matchWon
    case matchTied
    case matchLost
    case seasonMilestone
}

/// Ceremony size. Deliberately NOT DelightIntensity: the tier is the
/// GRANT (how big this moment may be), the intensity is one part of the
/// rendering (`GameDelightRules.spec`).
enum GameCeremonyTier: String, Codable, CaseIterable, Comparable {
    case subtle, normal, big

    private var rank: Int {
        switch self {
        case .subtle: return 0
        case .normal: return 1
        case .big: return 2
        }
    }

    static func < (lhs: GameCeremonyTier, rhs: GameCeremonyTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Rolling ledger of granted BIG ceremonies — the anti-inflation memory.
/// Since the arbiter generalized the budget app-wide, the ledger TYPE
/// lives in Content/DelightArbiter.swift; this alias keeps the games
/// layer (and its persisted Codable shape) unchanged.
typealias GameCeremonyLedger = DelightLedger

/// What one granted ceremony renders: the full-screen overlay intensity
/// (nil = the view's own confetti or nothing), the fanfare cue (sound +
/// haptic twin through CueKit), and an optional haptic OVERRIDE — the
/// victory motif that replaces the cue's generic twin on match wins.
struct GameCeremonySpec: Equatable {
    let overlay: DelightIntensity?
    let fanfare: AppCue?
    let victoryMotif: [HapticEventSpec]?
}

enum GameDelightRules {
    // MARK: Budget

    /// Rolling window and cap for BIG ceremonies: at most two epics per
    /// twenty minutes. The third match win in a hot streak is still a
    /// win — it just celebrates at the normal tier. The numbers live in
    /// the app-wide arbiter now; games read the SAME budget.
    static var bigWindow: TimeInterval { DelightArbiter.bigWindow }
    static var maxBigPerWindow: Int { DelightArbiter.maxBigPerWindow }

    /// The tier an event ASKS for before the budget speaks.
    static func requestedTier(for event: GameCeremonyEvent) -> GameCeremonyTier {
        switch event {
        case .move: return .subtle
        case .roundWon: return .normal
        case .matchWon: return .big
        case .matchTied: return .normal
        case .matchLost: return .subtle
        case .seasonMilestone: return .big
        }
    }

    /// Applies the anti-inflation budget: BIG requests inside an exhausted
    /// window are granted `.normal` instead; granted bigs are recorded in
    /// the returned ledger (pruned to the rolling window). Smaller tiers
    /// never touch the budget — they are already rate-limited by the
    /// CueScheduler. The budget math itself is DELEGATED to the app-wide
    /// DelightArbiter, so a game epic and a level-up epic spend from the
    /// same purse.
    static func grant(event: GameCeremonyEvent, ledger: GameCeremonyLedger,
                      now: Date) -> (tier: GameCeremonyTier, ledger: GameCeremonyLedger) {
        let requested = requestedTier(for: event)
        guard requested == .big else {
            return (requested, DelightArbiter.pruned(ledger, now: now))
        }
        let result = DelightArbiter.requestBig(ledger: ledger, now: now)
        return (result.granted ? .big : .normal, result.ledger)
    }

    // MARK: Rendering matrix

    /// Event + granted tier → ceremony. The matrix is the whole delight
    /// language of the games layer; the LogicTests pin every row.
    static func spec(event: GameCeremonyEvent, tier: GameCeremonyTier) -> GameCeremonySpec {
        switch event {
        case .move:
            // Moves keep their per-game foley (dice, chip, splash) at the
            // call sites — the ceremony layer stays silent.
            return GameCeremonySpec(overlay: nil, fanfare: nil, victoryMotif: nil)
        case .roundWon:
            // A lift, not a ceremony: no overlay, just the success cue.
            return GameCeremonySpec(overlay: nil, fanfare: .success, victoryMotif: nil)
        case .matchWon:
            if tier == .big {
                return GameCeremonySpec(overlay: .epic, fanfare: .fanfareEpic,
                                        victoryMotif: victoryMotif(tier: .big))
            }
            return GameCeremonySpec(overlay: .medium, fanfare: .fanfareMedium,
                                    victoryMotif: victoryMotif(tier: .normal))
        case .matchTied:
            return GameCeremonySpec(overlay: .medium, fanfare: .fanfareMedium,
                                    victoryMotif: nil)
        case .matchLost:
            // The sympathetic sigh (28#11): soft cue, small warm moment,
            // never a buzzer, never mocking.
            return GameCeremonySpec(overlay: .small, fanfare: .lose, victoryMotif: nil)
        case .seasonMilestone:
            if tier == .big {
                return GameCeremonySpec(overlay: .epic, fanfare: .fanfareEpic,
                                        victoryMotif: nil)
            }
            return GameCeremonySpec(overlay: .medium, fanfare: .fanfareMedium,
                                    victoryMotif: nil)
        }
    }

    // MARK: Victory motif

    /// The match-win signature on the hand: two heartbeats — the two of
    /// us — accelerating into one shared ta-daa. Replaces the generic
    /// fanfare twin ONLY on match wins, so winning a match feels
    /// different from every other celebration in the app.
    static func victoryMotif(tier: GameCeremonyTier) -> [HapticEventSpec] {
        switch tier {
        case .big:
            return [
                HapticEventSpec(t: 0.00, i: 0.80, s: 0.30),          // lub
                HapticEventSpec(t: 0.16, i: 0.50, s: 0.25),          // dub
                HapticEventSpec(t: 0.55, i: 0.85, s: 0.35),          // lub (closer)
                HapticEventSpec(t: 0.69, i: 0.55, s: 0.30),          // dub
                HapticEventSpec(t: 1.00, i: 1.00, s: 0.65),          // TA
                HapticEventSpec(t: 1.14, i: 0.85, s: 0.15, d: 0.60), // DAA (warm swell)
                HapticEventSpec(t: 1.85, i: 0.40, s: 0.80),          // sparkle tail
            ]
        case .normal:
            return [
                HapticEventSpec(t: 0.00, i: 0.75, s: 0.30),          // lub
                HapticEventSpec(t: 0.15, i: 0.50, s: 0.25),          // dub
                HapticEventSpec(t: 0.50, i: 0.90, s: 0.60),          // ta
                HapticEventSpec(t: 0.64, i: 0.70, s: 0.20, d: 0.35), // daa
            ]
        case .subtle:
            return [
                HapticEventSpec(t: 0.00, i: 0.55, s: 0.35),
                HapticEventSpec(t: 0.14, i: 0.35, s: 0.30),
            ]
        }
    }
}
