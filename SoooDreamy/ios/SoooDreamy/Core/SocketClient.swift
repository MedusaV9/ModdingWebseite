import Foundation
import Observation

enum SocketState: Equatable {
    case disconnected
    case connecting
    case connected
}

/// WebSocket connection to the active server with automatic reconnection.
/// Incoming events are posted as `Notification.Name.serverEvent`
/// (object = `ServerEvent`) on the main queue.
@MainActor
@Observable
final class SocketClient {
    private(set) var state: SocketState = .disconnected

    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var desired: (baseURL: URL, token: String)?
    @ObservationIgnored private var pingTimer: Timer?

    private struct EnvelopeHead: Decodable { let type: String }

    // MARK: Public API

    func connect(baseURL: URL, token: String) {
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
        state = .disconnected
    }

    func send(_ object: [String: Any]) {
        guard let task, state == .connected,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
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
        comps.queryItems = [URLQueryItem(name: "token", value: desired.token)]
        guard let url = comps.url else { return }

        state = .connecting
        let wsTask = URLSession.shared.webSocketTask(with: url)
        task = wsTask
        wsTask.resume()

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
                if state != .connected {
                    state = .connected
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
                scheduleReconnect()
                return
            }
        }
    }

    private func scheduleReconnect() {
        state = .disconnected
        task = nil
        guard desired != nil else { return }
        reconnectAttempt += 1
        let delay = min(15.0, pow(1.7, Double(min(reconnectAttempt, 8))))
        let gen = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.generation == gen, self.desired != nil else { return }
            self.openSocket()
        }
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.send(["type": "ping"])
            }
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
