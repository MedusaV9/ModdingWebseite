import Foundation
import Observation

/// Parallel game sessions: one `GameEngine` per game type plus the list
/// of ALL open sessions (for the hub's "your running games" banners and the
/// "Du bist dran!" hints). Routes socket events to the right engine and
/// keeps the open list fresh — the per-type engines stay the single source
/// of truth inside each game view.
@MainActor
@Observable
final class GamesCoordinator {

    /// All non-ended sessions of the couple, newest first.
    var openSessions: [GameSession] = []

    /// gameId → the turn verdict of the NEWEST `game_move` frame (contract
    /// v12). Key present = the server spoke; a nil VALUE = explicitly
    /// nobody (decisive move — `game_ended` follows moments later). The
    /// sessions carry the same three-state verdict themselves now; this
    /// overlay only keeps the FRESHEST frame ahead of a possibly-stale held
    /// session between two full refreshes. Entries die with the next full
    /// session (upsert/reconcile/reset) — which is safe precisely because
    /// the fetched session's own field preserves an explicit "nobody".
    private(set) var liveTurnVerdicts: [String: String?] = [:]

    @ObservationIgnored private var engines: [GameKind: GameEngine] = [:]

    /// Error sink shared by all engines (wired to `AppState.handleAPIError`).
    @ObservationIgnored var onError: ((Error) -> Void)?

    /// API captured from the last `refresh` — lets the `welcome` frame
    /// trigger a REST reconciliation without touching the (frozen) hub
    /// view. Refreshed on every tab appear / server switch.
    @ObservationIgnored private var lastKnownAPI: API?

    /// True while a reconcile runs — welcome frames may burst on flaky
    /// networks; one flight at a time keeps the engine updates atomic.
    @ObservationIgnored private var reconcileInFlight = false

    /// The lazily-created engine tracking sessions of one game type.
    func engine(for kind: GameKind) -> GameEngine {
        if let engine = engines[kind] { return engine }
        let engine = GameEngine(kind: kind)
        engine.onError = { [weak self] error in self?.onError?(error) }
        engines[kind] = engine
        return engine
    }

    /// Fetch all open sessions and seed the per-type engines (app start,
    /// tab appear). Best effort — errors stay quiet like `GameEngine.resume`.
    func refresh(api: API?) async {
        lastKnownAPI = api
        await reconcile(api: api)
    }

    /// Full REST reconciliation — runs on refresh AND on every socket
    /// `welcome` (a WS gap may have eaten game_move/game_ended fanouts):
    /// the open list is replaced wholesale, every engine of an open type
    /// adopts the fresh session, and engines whose session VANISHED from
    /// the open list get its final state by id (so an on-screen board
    /// shows the result instead of a stale turn) or are cleared when the
    /// session is gone entirely.
    func reconcile(api: API?) async {
        guard let api, !reconcileInFlight else { return }
        reconcileInFlight = true
        defer { reconcileInFlight = false }
        guard let games = try? await api.openGames() else { return }
        openSessions = games
        // Fresh full sessions carry the authoritative verdict themselves —
        // three-state, so an explicit "nobody" (e.g. the daily-quests
        // checklist after the partner's move) survives dropping every held
        // frame verdict instead of decaying into the last-mover fallback.
        liveTurnVerdicts = [:]
        for game in games {
            guard let kind = game.kind else { continue }
            engine(for: kind).adopt(game)
        }
        for (kind, engine) in engines {
            guard let held = engine.session, held.state != "ended",
                  !games.contains(where: { $0.kind == kind }) else { continue }
            if let final = try? await api.game(id: held.id) {
                engine.adopt(final)
            } else {
                // 404 — the session is gone for good; a cleared engine
                // makes the game screen reload instead of showing a ghost.
                engine.adopt(nil)
            }
        }
    }

    /// Feed every `.serverEvent` here — updates the open list and forwards
    /// to the engines (which dedupe/filter themselves, so double-feeding
    /// from individual game views stays harmless).
    func handle(_ event: ServerEvent) {
        switch event.type {
        case .welcome:
            // Socket (re)connected — a gap may have eaten game fanouts:
            // stale boards, ghost sessions, wrong turn hints. Reconcile
            // everything known via REST (the hub forwards every event
            // here, so this needs no view change).
            Task { await reconcile(api: lastKnownAPI) }
        case .gameCreated, .gameStarted, .gameEnded:
            guard let game = event.decode(GameOnlyResponse.self)?.game else { return }
            if let kind = game.kind {
                engine(for: kind).handle(event)
            }
            upsert(game)
        case .gameMove:
            guard let payload = event.decode(GameMovePayload.self) else { return }
            for engine in engines.values {
                engine.handle(event)
            }
            // v12 frames name the post-move turn holder — remember the
            // verdict (including an explicit "nobody") so extra moves keep
            // the hint with the mover instead of flipping to "last player".
            if case .some(let verdict) = payload.turnMemberId {
                liveTurnVerdicts[payload.gameId] = verdict
            } else {
                liveTurnVerdicts.removeValue(forKey: payload.gameId)
            }
            // Keep the open list's move tails fresh for the turn hints.
            if let idx = openSessions.firstIndex(where: { $0.id == payload.gameId }),
               !openSessions[idx].moves.contains(where: { $0.id == payload.move.id }) {
                openSessions[idx].moves.append(payload.move)
                // The session's own verdict is now stale. Both sides are
                // three-state: a v12 frame replaces it outright (explicit
                // "nobody" included), a pre-v12 frame (`.none`) clears it
                // so `awaitingMe` falls back to the move-tail derivation
                // until the next full session.
                openSessions[idx].turnMemberId = payload.turnMemberId
            }
        case .gameLease:
            // Input lease changed hands — only the engine tracking that
            // session cares; each engine filters by session id itself.
            for engine in engines.values {
                engine.handle(event)
            }
        default:
            break
        }
    }

    /// Server switch / logout: drop every session context.
    func reset() {
        openSessions = []
        liveTurnVerdicts = [:]
        for engine in engines.values {
            engine.adopt(nil)
        }
    }

    private func upsert(_ game: GameSession) {
        openSessions.removeAll { $0.id == game.id }
        // The full session carries the authoritative verdict itself — a
        // held frame verdict is older by definition.
        liveTurnVerdicts.removeValue(forKey: game.id)
        if game.state != "ended" {
            openSessions.insert(game, at: 0)
        }
    }

    /// "Du bist dran!" — prefers the server verdict (freshest `game_move`
    /// frame first, then the session's own `turnMemberId`, contract
    /// v11/v12) and falls back to the pre-v11 derivation (lobby invitation
    /// from the partner / last move came from the partner) ONLY when no
    /// verdict exists. See GameTurnRules.
    func awaitingMe(_ game: GameSession, myId: String?) -> Bool {
        GameTurnRules.awaitingMe(
            state: game.state,
            createdBy: game.createdBy,
            turnVerdict: GameTurnRules.layeredVerdict(
                frame: liveTurnVerdicts[game.id],
                session: game.turnMemberId
            ),
            lastMoveMemberId: game.moves.last?.memberId,
            myId: myId
        )
    }
}
