import Foundation

/// Exponential WebSocket retry budget with bounded jitter. Jitter prevents two
/// paired phones from reconnecting in lockstep after a router/server restart.
enum ReconnectBackoff {
    static let maximumDelay: TimeInterval = 20

    static func delay(attempt: Int, randomUnit: Double) -> TimeInterval {
        let safeAttempt = max(1, min(attempt, 10))
        let base = min(maximumDelay, pow(1.7, Double(safeAttempt)))
        let unit = min(1, max(0, randomUnit))
        let jitter = 0.8 + (unit * 0.4)
        return min(maximumDelay, base * jitter)
    }
}

/// Debounce policy for the ambient offline banner (Linse 45/29): a live
/// connection that drops gets a quiet grace window to heal invisibly before
/// the UI starts alarming anyone. Elevator rides shouldn't cause red pills.
enum OfflineBannerPolicy {
    static let graceSeconds: TimeInterval = 60

    /// Whether a drop out of "visibly connected" should still be masked.
    static func shouldMaskDrop(disconnectedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(disconnectedAt) < graceSeconds
    }
}
