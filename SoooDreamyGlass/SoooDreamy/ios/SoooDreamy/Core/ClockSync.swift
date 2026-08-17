import Foundation

/// NTP-light estimation of the offset between the server clock and this
/// device (haptic duet). Piggybacks on the app's WebSocket: we send
/// `ping {echo}` frames, the server answers `pong {echo}` and every frame
/// carries the server time `ts` — offset = serverTs − (t₀ + rtt/2). The
/// estimate from the sample with the smallest round-trip wins (least queueing
/// noise). ±30 ms is plenty for feeling "simultaneous" haptics.
@MainActor
final class ClockSync {
    static let shared = ClockSync()

    /// serverTime − localTime in seconds; nil until the first sample landed.
    private(set) var offset: TimeInterval?
    private(set) var bestRTT: TimeInterval = .infinity

    private var pending: [String: Date] = [:]

    private init() {}

    /// Fires a burst of pings (spaced ~120 ms) through the socket. Safe to
    /// call any time — e.g. when the duet view appears and before starting.
    func sample(via socket: SocketClient, count: Int = 5) {
        Task { [weak socket] in
            for _ in 0..<count {
                guard let socket else { return }
                let marker = "cs-\(UUID().uuidString.prefix(8))"
                pending[marker] = Date()
                socket.send(["type": "ping", "payload": ["echo": marker]])
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    /// Feed every incoming `pong` frame here (AppState does).
    func handlePong(echo: String?, serverTime: Date?) {
        guard let echo, let serverTime, let sentAt = pending.removeValue(forKey: echo) else { return }
        let now = Date()
        let rtt = now.timeIntervalSince(sentAt)
        guard rtt >= 0, rtt < 3 else { return }   // ignore pathological samples
        if rtt < bestRTT {
            bestRTT = rtt
            offset = serverTime.timeIntervalSince(sentAt) - rtt / 2
        }
    }

    /// Converts a server-clock unix timestamp (ms) into a local Date.
    /// Falls back to `fallbackServerNowMs` (a "server now" the same payload
    /// carried) for a rough single-shot estimate when no samples exist yet.
    func localDate(forServerMs ms: Double, fallbackServerNowMs: Double? = nil) -> Date {
        if let offset {
            return Date(timeIntervalSince1970: ms / 1000 - offset)
        }
        if let serverNow = fallbackServerNowMs {
            // No RTT info: assume the payload arrived "now" — the lead-in
            // still absorbs typical one-way latency.
            let delta = (ms - serverNow) / 1000
            return Date().addingTimeInterval(delta)
        }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// Drop state (server switch — another server, another clock).
    func reset() {
        offset = nil
        bestRTT = .infinity
        pending.removeAll()
    }
}
