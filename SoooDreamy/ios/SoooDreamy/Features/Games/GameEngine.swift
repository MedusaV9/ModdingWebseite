import Foundation
import Observation

/// Session engine for the realtime couple games (quiz, this-or-that, would-you-rather).
///
/// The server is a dumb relay: it stores the session (`payload` set on create)
/// plus an ordered list of `moves` and broadcasts every change to both members.
/// Both clients derive the entire game state DETERMINISTICALLY from
/// `payload` + the ordered moves (pure reducer). This type owns the session,
/// wraps the API calls and offers the reducer helpers the game views build on.
///
/// Conventions:
/// - `payload` on create: `{"seed": <random Int>, ...game options}` — the seed
///   drives a deterministic shuffle so both clients see the same questions.
/// - every move is an object with a `"kind"` field, e.g.
///   `{"kind": "answer", "round": 3, "value": "a"}`.
@MainActor
@Observable
final class GameEngine {

    /// Latest known session (lobby / active / ended). nil = nothing running.
    var session: GameSession?

    /// True while create/join/end is in flight (used to disable buttons).
    var busy = false

    /// Error sink — the views wire this to `AppState.handleAPIError`.
    @ObservationIgnored var onError: ((Error) -> Void)?

    /// Ids of moves already in `session.moves` — the server echoes our own
    /// moves back over the socket, so every append must dedupe.
    @ObservationIgnored private var knownMoveIds: Set<String> = []

    // MARK: - Session lifecycle

    /// Replace the session wholesale (create/join/end responses and
    /// game_created/started/ended socket events carry the full session).
    func adopt(_ game: GameSession?) {
        session = game
        knownMoveIds = Set(game?.moves.map(\.id) ?? [])
    }

    /// Resume after app restart / tab appear: fetch the latest lobby or
    /// active session from the server. Best effort — errors stay quiet.
    func resume(api: API?) async {
        guard let api else { return }
        if let game = try? await api.activeGame() {
            adopt(game)
        }
    }

    /// Create a new session. The server automatically ends any previous
    /// non-ended game of the couple.
    @discardableResult
    func create(api: API?, type: GameKind, payload: JSONValue) async -> Bool {
        guard let api, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            adopt(try await api.createGame(type: type, payload: payload))
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// Join the current lobby session (state flips to "active").
    @discardableResult
    func join(api: API?) async -> Bool {
        guard let api, let id = session?.id, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            adopt(try await api.joinGame(id: id))
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// Send a move for the current session and append the server's copy.
    @discardableResult
    func sendMove(api: API?, data: JSONValue) async -> Bool {
        guard let api, let id = session?.id else { return false }
        do {
            let move = try await api.sendMove(gameId: id, data: data)
            append(move, gameId: id)
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// End the current session with an optional result summary.
    /// Ending an already-ended session is harmless on the server.
    func end(api: API?, result: JSONValue?) async {
        guard let api, let id = session?.id, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            adopt(try await api.endGame(id: id, result: result))
        } catch {
            onError?(error)
        }
    }

    // MARK: - Socket events

    /// Feed every incoming `.serverEvent` here. Handling is idempotent, so
    /// it is safe if several views forward the same event.
    func handle(_ event: ServerEvent) {
        switch event.type {
        case .gameCreated:
            // A new session always supersedes whatever we had (the server
            // silently ended any previous game before creating this one).
            if let game = event.decode(GameOnlyResponse.self)?.game {
                adopt(game)
            }
        case .gameStarted:
            if let game = event.decode(GameOnlyResponse.self)?.game,
               session == nil || session?.id == game.id || session?.state == "ended" {
                adopt(game)
            }
        case .gameEnded:
            if let game = event.decode(GameOnlyResponse.self)?.game,
               session?.id == game.id {
                adopt(game)
            }
        case .gameMove:
            if let payload = event.decode(GameMovePayload.self) {
                append(payload.move, gameId: payload.gameId)
            }
        default:
            break
        }
    }

    private func append(_ move: GameMove, gameId: String) {
        guard var current = session, current.id == gameId else { return }
        guard !knownMoveIds.contains(move.id) else { return }
        knownMoveIds.insert(move.id)
        current.moves.append(move)
        session = current
    }

    // MARK: - Reducer helpers

    /// Moves in a stable, deterministic order — sorted by createdAt, ties
    /// broken by id, so both clients reduce identical state even when
    /// socket frames arrive out of order.
    var orderedMoves: [GameMove] {
        (session?.moves ?? []).sorted { a, b in
            if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
            return a.id < b.id
        }
    }

    /// All moves whose data carries the given `"kind"`.
    func moves(kind: String) -> [GameMove] {
        orderedMoves.filter { $0.data["kind"]?.stringValue == kind }
    }

    /// First move per member for one round — later duplicates are ignored,
    /// which keeps the reducer stable against double sends.
    func movesByMember(round: Int, kind: String) -> [String: GameMove] {
        var result: [String: GameMove] = [:]
        for move in moves(kind: kind) where move.data["round"]?.intValue == round {
            if result[move.memberId] == nil {
                result[move.memberId] = move
            }
        }
        return result
    }

    /// First move of a kind in a round by a specific member.
    func move(kind: String, round: Int, by memberId: String) -> GameMove? {
        moves(kind: kind).first {
            $0.memberId == memberId && $0.data["round"]?.intValue == round
        }
    }

    // MARK: - Payload access

    /// Shared random seed from the create payload.
    var seed: Int { session?.payload?["seed"]?.intValue ?? 0 }

    /// Integer option from the create payload (e.g. "rounds", "spice", "set").
    func payloadInt(_ key: String, default fallback: Int) -> Int {
        session?.payload?[key]?.intValue ?? fallback
    }

    // MARK: - Builders

    /// Create-payload with a fresh random seed plus integer game options.
    static func makePayload(options: [String: Int] = [:]) -> JSONValue {
        var object: [String: JSONValue] = [
            "seed": .number(Double(Int.random(in: 1...999_999_999)))
        ]
        for (key, value) in options {
            object[key] = .number(Double(value))
        }
        return .object(object)
    }

    /// Standard move body: `{"kind": ..., "round": ..., "value": ...}`.
    static func moveData(kind: String, round: Int, value: String) -> JSONValue {
        .object([
            "kind": .string(kind),
            "round": .number(Double(round)),
            "value": .string(value)
        ])
    }
}

// NOTE: SeededGenerator + Array.seededShuffled(seed:) live in
// Core/SeededRandom.swift (shared with the Linux logic-test package).
