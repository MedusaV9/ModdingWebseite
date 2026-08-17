import Foundation

// „Nähe trotz Distanz" — pure presence/pulse logic, mirrored from
// server/src/presence.js. Foundation-only so `swift test` covers it on Linux.

// MARK: - Presence modes (focus / sleep)

/// A member's declared mode. "Available" is simply the absence of one —
/// exactly like the server, which stores `presence: null` then.
enum PresenceModeKind: String, Codable, CaseIterable, Identifiable {
    case focus, sleep
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .focus: return "🎯"
        case .sleep: return "😴"
        }
    }

    /// "Fokus" / "Schlafmodus" — the pill on my own toggle.
    var titleKey: String { "presence.mode.\(rawValue)" }
    /// "Mia ist im Fokus …" — the gentle hint on the partner's phone.
    var partnerHintKey: String { "presence.partnerHint.\(rawValue)" }
    /// Short subtitle explaining what the mode signals.
    var subtitleKey: String { "presence.mode.\(rawValue).subtitle" }
}

enum PresenceLogic {
    /// Server contract: minutes must be an integer in 5…720 (12 h).
    static let minMinutes = 5
    static let maxMinutes = 720
    /// Note ≤ 80 chars (server truncates nothing — it rejects).
    static let maxNoteLength = 80
    /// Sheet quick-picks; `nil` = "until I turn it off".
    static let durationChoicesMinutes: [Int?] = [nil, 30, 60, 120, 480]

    /// Mirrors the server's lazy expiry: a presence with a passed `until`
    /// is treated as cleared without waiting for a round-trip.
    static func isActive(until: Date?, now: Date = Date()) -> Bool {
        guard let until else { return true }
        return until > now
    }

    /// Whole minutes left until `until`, rounded UP (49:30 → "noch 50 min"),
    /// nil for open-ended modes or already-expired ones.
    static func remainingMinutes(until: Date?, now: Date = Date()) -> Int? {
        guard let until, until > now else { return nil }
        return Int((until.timeIntervalSince(now) / 60).rounded(.up))
    }

    /// "noch 45 min" / "noch 2 Std." — key + args for the countdown pill.
    static func remainingLabel(minutes: Int) -> (key: String, args: [String: String]) {
        if minutes >= 60 {
            let hours = Int((Double(minutes) / 60).rounded())
            return ("presence.remaining.hours", ["hours": String(hours)])
        }
        return ("presence.remaining.minutes", ["minutes": String(minutes)])
    }
}

// MARK: - Thinking-of-you pulses

/// The four pulse flavours. Order = UI order in the send bar.
enum PulseKind: String, Codable, CaseIterable, Identifiable {
    case thinking, goodnight, heartbeat, hug
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .thinking: return "💭"
        case .goodnight: return "🌙"
        case .heartbeat: return "💓"
        case .hug: return "🤗"
        }
    }

    /// "Denk an dich" — button label.
    var titleKey: String { "pulse.kind.\(rawValue)" }
    /// "{name} denkt gerade an dich" — received overlay line.
    var receivedKey: String { "pulse.received.\(rawValue)" }

    /// The haptic signature the partner FEELS. Deliberately distinct from
    /// the touch patterns (Haptics.pattern(for:)) — pulses are slower and
    /// softer, more like a message traced onto skin than a notification.
    var timeline: [HapticEventSpec] {
        switch self {
        case .thinking:
            // three soft knocks, like fingertips on a window
            return [
                HapticEventSpec(t: 0.00, i: 0.45, s: 0.30),
                HapticEventSpec(t: 0.35, i: 0.60, s: 0.35),
                HapticEventSpec(t: 0.70, i: 0.45, s: 0.30),
            ]
        case .goodnight:
            // one long fading wave — pulling the blanket up
            return [
                HapticEventSpec(t: 0.00, i: 0.70, s: 0.10, d: 0.9),
                HapticEventSpec(t: 1.00, i: 0.35, s: 0.08, d: 0.6),
            ]
        case .heartbeat:
            // two slow lub-dubs at resting pulse (~55 bpm)
            return [
                HapticEventSpec(t: 0.00, i: 0.90, s: 0.25),
                HapticEventSpec(t: 0.20, i: 0.55, s: 0.15),
                HapticEventSpec(t: 1.10, i: 0.90, s: 0.25),
                HapticEventSpec(t: 1.30, i: 0.55, s: 0.15),
            ]
        case .hug:
            // swelling squeeze, held, released
            return [
                HapticEventSpec(t: 0.00, i: 0.40, s: 0.08, d: 0.5),
                HapticEventSpec(t: 0.50, i: 0.85, s: 0.10, d: 1.0),
                HapticEventSpec(t: 1.60, i: 0.40, s: 0.05, d: 0.4),
            ]
        }
    }
}

enum PulseLogic {
    /// Server contract: one pulse per sender per 30 s (429 otherwise).
    static let cooldown: TimeInterval = 30

    /// Seconds the send bar still has to wait, 0 when free. Mirrors the
    /// server check so the UI can disable buttons instead of collecting 429s.
    static func cooldownRemaining(lastSentAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let lastSentAt else { return 0 }
        return max(0, cooldown - now.timeIntervalSince(lastSentAt))
    }

    /// Total played duration of a pulse timeline (for overlay auto-dismiss).
    static func timelineDuration(_ events: [HapticEventSpec]) -> TimeInterval {
        events.map { $0.t + $0.d }.max() ?? 0
    }
}
