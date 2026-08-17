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
/// - `payload` on create: `{...game options}`; the server ALWAYS adds a random
///   `"seed"` (client seeds are discarded so nobody can pick their
///   own shuffle). The seed drives a deterministic shuffle so both clients
///   see the same questions.
/// - every move is an object with a `"kind"` field, e.g.
///   `{"kind": "answer", "round": 3, "value": "a"}`.
@MainActor
@Observable
final class GameEngine {

    /// Parallel sessions: when set, this engine only tracks sessions
    /// of ONE game type — every game view gets its own engine so a partner
    /// starting Kniffel no longer hijacks a running battleship board.
    /// `nil` keeps the pre-3.0 "one session at a time" behavior.
    @ObservationIgnored let kind: GameKind?

    /// Latest known session (lobby / active / ended). nil = nothing running.
    var session: GameSession?

    /// True while create/join/end is in flight (used to disable buttons).
    var busy = false

    /// Error sink — the views wire this to `AppState.handleAPIError`.
    @ObservationIgnored var onError: ((Error) -> Void)?

    /// Ids of moves already in `session.moves` — the server echoes our own
    /// moves back over the socket, so every append must dedupe.
    @ObservationIgnored private var knownMoveIds: Set<String> = []

    /// Lease carried by the last `game_lease_held` refusal (typed error
    /// `details`, contract v11). The refusal is always about MY member's
    /// lease but the body carries no member key — `seat()` resolves it
    /// against the session it belongs to. Cleared by every fresh session
    /// or lease truth (adopt / game_lease fanout).
    @ObservationIgnored private var refusedLease: (gameId: String, lease: GameLease)?

    init(kind: GameKind? = nil) {
        self.kind = kind
    }

    // MARK: - Session lifecycle

    /// A session this engine is willing to track (nil always passes so the
    /// session can be cleared).
    private func accepts(_ game: GameSession?) -> Bool {
        guard let kind, let game else { return true }
        return game.kind == kind
    }

    /// Replace the session wholesale (create/join/end responses and
    /// game_created/started/ended socket events carry the full session).
    func adopt(_ game: GameSession?) {
        guard accepts(game) else { return }
        session = game
        knownMoveIds = Set(game?.moves.map(\.id) ?? [])
        refusedLease = nil
    }

    /// Resume after app restart / tab appear: fetch the latest open session
    /// (of this engine's type, when set) from the server. Best effort —
    /// errors stay quiet.
    func resume(api: API?) async {
        guard let api else { return }
        if let kind {
            if let games = try? await api.openGames(),
               let mine = games.first(where: { $0.kind == kind }) {
                adopt(mine)
            }
        } else if let game = try? await api.activeGame() {
            adopt(game)
        }
    }

    /// Create a new session. The server automatically ends any previous
    /// non-ended game of the SAME type (parallel sessions).
    @discardableResult
    func create(api: API?, type: GameKind, payload: JSONValue) async -> Bool {
        guard let api, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            adopt(try await api.createGame(type: type, payload: payload))
            return true
        } catch {
            // Mutual-create race (28#4): a 409 here means a same-type session
            // already runs — and since own untouched lobbies are auto-replaced
            // server-side, it is either active or the PARTNER's waiting
            // invitation. Slide into that session instead of showing an error:
            // whoever pressed "start" wanted to play, and a matching game is
            // right there.
            if (error as? APIError)?.serverCode == "game_in_progress" {
                do {
                    if let existing = try await api.openGames()
                        .first(where: { $0.type == type.rawValue }) {
                        adopt(existing)
                        if existing.state == "lobby" {
                            adopt(try await api.joinGame(id: existing.id))
                        }
                        return true
                    }
                } catch {
                    onError?(error)
                    return false
                }
            }
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
    /// A DECISIVE move (W8C board games) ends the session server-side and
    /// the response carries the final game — adopt it right away so the
    /// mover sees the result without waiting for the `game_ended` fanout.
    @discardableResult
    func sendMove(api: API?, data: JSONValue) async -> Bool {
        guard let api, let id = session?.id else { return false }
        do {
            let response = try await api.sendMoveDetailed(gameId: id, data: data)
            append(response.move, gameId: id)
            adoptTurnVerdict(response.turnMemberId, gameId: id)
            if let ended = response.game, ended.id == id {
                adopt(ended)
            }
            return true
        } catch {
            await noteLeaseRefusal(error, api: api, gameId: id)
            onError?(error)
            return false
        }
    }

    /// Offline-first variant for quest checks and ratings. AppState persists
    /// the move before transmission and replays it with the same client id.
    @discardableResult
    func sendDurableMove(appState: AppState, data: JSONValue,
                         kind: OfflineOperationKind) async -> Bool {
        guard let id = session?.id else { return false }
        do {
            let response = try await appState.sendGameMoveOfflineFirst(
                gameId: id, data: data, kind: kind
            )
            append(response.move, gameId: id)
            adoptTurnVerdict(response.turnMemberId, gameId: id)
            // Decisive move — or a RETRIED final move on a meanwhile-ended
            // session, which the server answers with {duplicate:true, move,
            // game} (contract v11): either way the carried game is truth.
            if let ended = response.game, ended.id == id {
                adopt(ended)
            }
            return true
        } catch {
            await noteLeaseRefusal(error, api: appState.api, gameId: id)
            onError?(error)
            return false
        }
    }

    // MARK: - Input lease (Welle 6)

    /// The lease view `seat()` decides from — the newest server truth: a
    /// lease learned from a `game_lease_held` refusal (typed details)
    /// outranks the session's possibly-stale lease map. The spectator
    /// banner reads THIS (not the raw session leases), so a refused move
    /// flips the UI to read-only immediately instead of waiting for a
    /// fanout that may never come.
    func effectiveLease(myMemberId: String?) -> GameLease? {
        guard let myMemberId, let session else { return nil }
        if let refused = refusedLease, refused.gameId == session.id {
            return refused.lease
        }
        return session.leases?[myMemberId]
    }

    /// The seat THIS device holds for the current session — drives the
    /// spectator banner. Nil identity fails open (see GameLeaseRules).
    func seat(myMemberId: String?, sessionId: String?) -> GameLeaseRules.Seat {
        GameLeaseRules.seat(lease: effectiveLease(myMemberId: myMemberId),
                            ownSessionId: sessionId)
    }

    /// Pull the member's lease onto THIS device ("Hier weiterspielen" on
    /// the spectator banner). The response updates the lease view directly;
    /// the `game_lease` fanout converges the sibling devices.
    @discardableResult
    func takeover(api: API?) async -> Bool {
        guard let api, let id = session?.id, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            let payload = try await api.takeoverGame(id: id)
            applyLease(payload)
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    /// A `game_lease_held` refusal means another own device holds the
    /// lease and OUR lease view is stale (the fanout was missed — app
    /// restart, socket gap). Contract v11 puts the holding lease right in
    /// the error body (`details: {gameId, lease}`) — apply it directly, no
    /// extra GET. Old servers without details keep the re-fetch fallback
    /// so the spectator banner still appears instead of a bare error toast.
    private func noteLeaseRefusal(_ error: Error, api: API?, gameId: String) async {
        guard let apiError = error as? APIError,
              apiError.serverCode == GameLeaseRules.refusalCode else { return }
        if let details = apiError.details, let lease = details.lease,
           details.gameId == nil || details.gameId == gameId {
            refusedLease = (gameId: gameId, lease: lease)
            // Re-assign so observers re-evaluate seat().
            if let current = session, current.id == gameId { session = current }
            return
        }
        guard let api else { return }
        do {
            let fresh = try await api.game(id: gameId)
            guard var current = session, current.id == fresh.id else { return }
            current.leases = fresh.leases
            session = current
        } catch {
            // The refresh only accelerates the banner; the REFUSAL itself is
            // already surfaced via onError right after this call — a failed
            // refresh has nothing extra to tell the human.
        }
    }

    private func applyLease(_ payload: GameLeasePayload) {
        guard var current = session, current.id == payload.gameId else { return }
        var leases = current.leases ?? [:]
        leases[payload.memberId] = payload.lease
        current.leases = leases
        session = current
        // The fanout is fresher truth than any cached refusal lease.
        if refusedLease?.gameId == payload.gameId { refusedLease = nil }
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

    /// Surrender an unfinished game — the partner takes the win (28#3).
    /// Sends `{forfeit:true}`; the bare `/end` this button used to fire
    /// earned a `409 game_incomplete` and left zombie sessions behind.
    @discardableResult
    func forfeit(api: API?) async -> Bool {
        guard let api, let id = session?.id, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            adopt(try await api.endGame(id: id, forfeit: true))
            return true
        } catch {
            onError?(error)
            return false
        }
    }

    // MARK: - Socket events

    /// Feed every incoming `.serverEvent` here. Handling is idempotent, so
    /// it is safe if several views forward the same event.
    func handle(_ event: ServerEvent) {
        switch event.type {
        case .gameCreated:
            // A new session of OUR type supersedes whatever we had (the
            // server silently ended the previous same-type game before
            // creating this one). Other types are ignored via `accepts`.
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
                adoptTurnVerdict(payload.turnMemberId, gameId: payload.gameId)
            }
        case .gameLease:
            // Member-only fanout: the input lease changed hands (first
            // valid move, silent inheritance, or explicit takeover).
            if let payload = event.decode(GameLeasePayload.self) {
                applyLease(payload)
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

    /// Contract v12: move responses name the post-move turn holder — adopt
    /// it into the held session's three-state field so its `turnMemberId`
    /// never lags behind an extra move (an explicit "nobody" is adopted as
    /// such). Outer nil (old server: field missing) changes nothing.
    private func adoptTurnVerdict(_ verdict: String??, gameId: String) {
        guard case .some = verdict,
              var current = session, current.id == gameId else { return }
        current.turnMemberId = verdict
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

    /// Create-payload with integer game options. The shared random seed is
    /// GENERATED BY THE SERVER — a client-sent seed would be
    /// discarded anyway (fairness: nobody may pick their own shuffle).
    static func makePayload(options: [String: Int] = [:]) -> JSONValue {
        var object: [String: JSONValue] = [:]
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
