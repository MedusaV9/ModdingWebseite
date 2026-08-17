import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// "Couple Pulse" Live Activity (lock screen + Dynamic Island): a living card
/// showing what your partner is up to — presence, mood, last touch, streak.
/// Updated locally from the WebSocket while the app is open (no APNs).
struct CouplePulseAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var partnerOnline: Bool
        var partnerMood: String?
        var partnerMoodNote: String?
        /// Presence mode ("focus"/"sleep") — status glow + label.
        /// Optional: activities started before 9.0 decode fine.
        var partnerPresenceMode: String?
        /// Raw touch type ("heartbeat", "kiss", …) — mapped to an emoji via
        /// `TouchEmoji.map` so the widget never needs the app's models.
        var lastTouchType: String?
        var lastTouchAt: Date?
        var streak: Int
        var bothAnsweredToday: Bool
        var daysTogether: Int?
        var refreshedAt: Date
        /// Style + visible elements (2.0). Travels in the state so the
        /// in-app sheet restyles running activities without a restart.
        /// Optional: activities started before 2.0 decode fine.
        var config: LiveActivityConfig?
        /// W7: set only when the good-night ritual closes the day — the
        /// activity ends showing this line instead of vanishing mid-thought.
        var daySummary: String?
        /// W7-Rest reveal seal: both answered, but the ceremony is still
        /// sealed on this device — drives the gold seal pill. Optional:
        /// activities started before the seal existed decode fine.
        var dailyRevealPending: Bool?
    }

    var myName: String
    var partnerName: String
}

/// Update hygiene: lets the controller skip pushes whose only difference is
/// the refresh stamp (see `ActivityUpdateHygiene`).
extension CouplePulseAttributes.ContentState: RefreshStampedState {}
#endif
