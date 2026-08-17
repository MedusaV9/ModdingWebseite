import Foundation
import Network
import Observation

enum SocketState: Equatable {
    case disconnected
    case connecting
    case connected
}

/// WebSocket connection to the active server with automatic reconnection.
/// Incoming events are posted as `Notification.Name.serverEvent`
/// (object = `ServerEvent`) on the main queue.
///
/// Split-brain hardening (Linse 45): a network-path change reconnects
/// immediately instead of waiting for `receive()` to notice minutes later,
/// ping send-failures and missing pongs tear the zombie connection down,
/// and `displayState` debounces the offline banner so silent, quick
/// reconnects stay invisible.
@MainActor
@Observable
final class SocketClient {
    private(set) var state: SocketState = .disconnected

    /// What ambient UI (banners) should show: drops out of `.connected` are
    /// masked for `OfflineBannerPolicy.graceSeconds` while the socket heals
    /// itself — no flicker for tunnel-and-elevator moments.
    private(set) var displayState: SocketState = .disconnected

    /// The server must answer a ping (or send anything else) within this
    /// window, otherwise the connection is a zombie and gets torn down.
    /// 20 s ping cadence → 50 s tolerates one lost pong, never two.
    private static let livenessWindow: TimeInterval = 50

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var desired: (baseURL: URL, token: String)?
    @ObservationIgnored private var pingTimer: Timer?
    @ObservationIgnored private var lastFrameAt = Date.distantPast
    @ObservationIgnored private var displayStateTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastPathFingerprint: String?

    private struct EnvelopeHead: Decodable { let type: String }

    // MARK: Public API

    func connect(baseURL: URL, token: String) {
        startPathMonitorIfNeeded()
        // Already connected (or connecting) to exactly this target? Keep it.
        if let desired, desired.baseURL == baseURL, desired.token == token,
           state != .disconnected {
            return
        }
        desired = (baseURL, token)
        reconnectAttempt = 0
        openSocket()
    }

    func disconnect() {
        desired = nil
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        setState(.disconnected, immediate: true)
    }

    func send(_ object: [String: Any]) {
        guard let task, state == .connected,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        let gen = generation
        task.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            // A send failure is the earliest proof the socket is dead —
            // don't wait for receive() to notice.
            Task { @MainActor [weak self] in
                self?.handleTransportFailure(generation: gen)
            }
        }
    }

    func sendTyping(_ isTyping: Bool) {
        send(["type": "typing", "payload": ["isTyping": isTyping]])
    }

    // MARK: Connection lifecycle

    private func openSocket() {
        guard let desired else { return }
        generation += 1
        let gen = generation
        // Drop any stale socket before opening a fresh one.
        task?.cancel(with: .goingAway, reason: nil)
        task = nil

        guard var comps = URLComponents(url: desired.baseURL, resolvingAgainstBaseURL: false) else { return }
        comps.scheme = (comps.scheme == "https") ? "wss" : "ws"
        comps.path = "/ws"
        guard let url = comps.url else { return }

        setState(.connecting)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(desired.token)", forHTTPHeaderField: "Authorization")
        let wsTask = URLSession.shared.webSocketTask(with: request)
        task = wsTask
        wsTask.resume()
        lastFrameAt = Date()   // fresh liveness budget for the new socket

        Task { [weak self] in
            await self?.receiveLoop(wsTask, generation: gen)
        }
        startPingTimer()
    }

    private func receiveLoop(_ wsTask: URLSessionWebSocketTask, generation gen: Int) async {
        while gen == generation {
            do {
                let message = try await wsTask.receive()
                guard gen == generation else { return }
                lastFrameAt = Date()
                if state != .connected {
                    setState(.connected)
                    reconnectAttempt = 0
                }
                switch message {
                case .string(let text):
                    handle(text: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { handle(text: text) }
                @unknown default:
                    break
                }
            } catch {
                guard gen == generation else { return }
                // Terminal revocation (contract close code 4001): THIS
                // session was revoked from another device. No reconnect —
                // a revoked token would loop 401s forever — and no silent
                // recovery either; AppState tears the session down and
                // shows the honest "signed out by another device" state.
                if SessionTerminationRules.isTerminal(closeCode: wsTask.closeCode.rawValue) {
                    handleTerminalClose()
                    return
                }
                scheduleReconnect()
                return
            }
        }
    }

    /// Server said "this session is gone for good" — stop wanting the
    /// connection and tell the app exactly once.
    private func handleTerminalClose() {
        desired = nil
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        task = nil
        setState(.disconnected, immediate: true)
        NotificationCenter.default.post(name: .sessionRevoked, object: nil)
    }

    private func scheduleReconnect() {
        setState(.disconnected)
        task = nil
        guard desired != nil else { return }
        reconnectAttempt += 1
        let delay = ReconnectBackoff.delay(
            attempt: reconnectAttempt,
            randomUnit: Double.random(in: 0...1)
        )
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.generation == gen, self.desired != nil else { return }
            self.openSocket()
        }
    }

    /// Immediate teardown + reopen for failures detected out-of-band
    /// (send error, missed pong, network-path change).
    private func handleTransportFailure(generation gen: Int) {
        guard gen == generation, desired != nil else { return }
        openSocket()
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.heartbeat()
            }
        }
    }

    /// The 20 s heartbeat now verifies liveness instead of pinging blindly:
    /// no frame (pong or otherwise) within the window means the connection
    /// only LOOKS alive — reconnect right away.
    private func heartbeat() {
        guard desired != nil, state == .connected else { return }
        if Date().timeIntervalSince(lastFrameAt) > Self.livenessWindow {
            handleTransportFailure(generation: generation)
            return
        }
        send(["type": "ping"])
    }

    // MARK: Network path monitoring

    /// A path change (WLAN ↔ cellular, VPN toggle, airplane mode off)
    /// reconnects the socket immediately — the old TCP stream on the gone
    /// interface would otherwise stay a silent zombie for minutes.
    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let fingerprint = path.status == .satisfied
                ? "up:" + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
                : "down"
            Task { @MainActor [weak self] in
                self?.handlePathChange(fingerprint: fingerprint,
                                       satisfied: path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "sooodreamy.pathmonitor"))
    }

    private func handlePathChange(fingerprint: String, satisfied: Bool) {
        let previous = lastPathFingerprint
        lastPathFingerprint = fingerprint
        guard desired != nil, previous != nil, previous != fingerprint else { return }
        if satisfied {
            // New viable path: reconnect NOW (not after minutes of backoff).
            reconnectAttempt = 0
            openSocket()
        }
        // Path went down entirely: receive() will fail on its own; forcing a
        // doomed dial here would only burn the backoff sequence.
    }

    // MARK: Display state (offline banner debounce)

    private func setState(_ newState: SocketState, immediate: Bool = false) {
        state = newState
        displayStateTask?.cancel()
        if immediate || newState == .connected || displayState != .connected {
            // First connect, explicit sign-out, or the banner is already
            // honest — mirror instantly.
            displayState = newState
            return
        }
        // Dropping out of a visibly-connected state: give the socket a quiet
        // grace window to heal before alarming anyone.
        displayStateTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(OfflineBannerPolicy.graceSeconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.displayState = self.state
        }
    }

    // MARK: Incoming

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let head = try? JSONDecoder().decode(EnvelopeHead.self, from: data),
              let type = ServerEventType(rawValue: head.type) else { return }
        let event = ServerEvent(type: type, rawData: data)
        NotificationCenter.default.post(name: .serverEvent, object: event)
    }
}
