import Foundation

// W7 (43#3/#7/#8/#12): couple-server plumbing for intents that must work in
// BOTH processes — Siri/app intents (app process) and Control Center buttons
// (widget process). Uses the app-group-mirrored credentials, exactly like
// WidgetSendTouchIntent. Not part of the Linux logic package (URLSession).

enum CoupleServerCall {
    enum PulseOutcome {
        case sent
        /// Server rate limit (30 s) — "your last pulse is still on its way".
        case tooSoon
        case failed
    }

    /// Authenticated request against the couple server, nil when signed out.
    private static func request(path: String, method: String,
                                body: [String: Any]? = nil) -> URLRequest? {
        guard let creds = SharedStore.readServerCredentials(),
              let token = SharedKeychain.activeToken(profileID: creds.profileID),
              let base = URL(string: creds.baseURLString) else { return nil }
        var request = URLRequest(url: base.appendingPathComponent(path),
                                 timeoutInterval: 12)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private static func statusCode(of request: URLRequest) async -> Int? {
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    /// `PUT /api/presence` — sets my focus/sleep mode and mirrors it into
    /// the app group so the presence toggle control shows the real state.
    static func setPresence(mode: String, minutes: Int?) async -> Bool {
        var body: [String: Any] = ["mode": mode]
        if let minutes { body["minutes"] = minutes }
        guard let request = request(path: "api/presence", method: "PUT", body: body),
              let status = await statusCode(of: request), (200..<300).contains(status)
        else { return false }
        let until = minutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) }
        mirrorMyPresence(mode: mode, until: until)
        return true
    }

    /// `DELETE /api/presence` — clears my mode (mirror follows).
    static func clearPresence() async -> Bool {
        guard let request = request(path: "api/presence", method: "DELETE"),
              let status = await statusCode(of: request), (200..<300).contains(status)
        else { return false }
        mirrorMyPresence(mode: nil, until: nil)
        return true
    }

    /// `POST /api/pulses` — a thinking-of-you pulse; 429 is the friendly
    /// "too soon" outcome, never a hard error.
    static func sendPulse(kind: String) async -> PulseOutcome {
        guard let request = request(path: "api/pulses", method: "POST",
                                    body: ["kind": kind]),
              let status = await statusCode(of: request) else { return .failed }
        if (200..<300).contains(status) { return .sent }
        return status == 429 ? .tooSoon : .failed
    }

    /// `POST /api/checkins` — morning/night check-in.
    static func checkin(kind: String) async -> Bool {
        guard let request = request(path: "api/checkins", method: "POST",
                                    body: ["kind": kind]),
              let status = await statusCode(of: request) else { return false }
        return (200..<300).contains(status)
    }

    /// Keeps the snapshot's my-presence mirror truthful after an intent (or
    /// control) changed the mode outside the app. The app overwrites this
    /// with server truth on its next snapshot write.
    static func mirrorMyPresence(mode: String?, until: Date?) {
        guard var snapshot = SharedStore.readSnapshot() else { return }
        snapshot.myPresenceMode = mode
        snapshot.myPresenceUntil = until
        SharedStore.writeSnapshot(snapshot)
    }

    /// My own fresh presence mode from the app-group mirror (client-side
    /// expiry, mirrors the server's lazy expiry) — control toggle state.
    static func myPresenceMode() -> String? {
        guard let snapshot = SharedStore.readSnapshot(),
              let mode = snapshot.myPresenceMode else { return nil }
        if let until = snapshot.myPresenceUntil, until <= Date() { return nil }
        return mode
    }
}
