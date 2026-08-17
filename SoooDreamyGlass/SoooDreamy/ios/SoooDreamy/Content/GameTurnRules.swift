import Foundation

// „Du bist dran" — pure decision rule for the turn hints (hub badges,
// session banners). Contract v11 adds a server-authoritative
// `serializeGame.turnMemberId` (null once the game ended and on no-turn
// types); old servers omit the field entirely. The client prefers the
// server's verdict and falls back to the pre-v11 local derivation (lobby
// invitation from the partner / last move came from the partner) ONLY when
// the field is missing — everywhere (frames, move responses AND fetched
// sessions) the field is three-state, so an explicit "nobody" never decays
// into the fallback. Foundation-only so Linux `swift test` covers every
// branch.
enum GameTurnRules {
    /// Whether MY action is awaited in one session, from the three-state
    /// `turnMemberId` verdict: `.some(nil)` means EXPLICITLY nobody (the
    /// fallback must NOT resurrect a turn hint), `.none` means the field
    /// is missing (old server — fall back to the pre-v11 derivation).
    static func awaitingMe(state: String, createdBy: String,
                           turnVerdict: String??,
                           lastMoveMemberId: String?,
                           myId: String?) -> Bool {
        guard let myId else { return false }
        // Ended games never await anyone — even against a server that
        // (buggily) still carries a turn holder on them.
        guard state != "ended" else { return false }
        // Server truth wins whenever it spoke — including "nobody".
        if case .some(let verdict) = turnVerdict { return verdict == myId }
        // Fallback: the pre-v11 derivation.
        if state == "lobby" { return createdBy != myId }
        guard state == "active", let lastMoveMemberId else { return false }
        return lastMoveMemberId != myId
    }

    /// Layer the freshest live-frame verdict (outer `.some` = the server
    /// spoke in a `game_move` frame) over the session's own three-state
    /// field. The session side is three-state too (contract v12 for the
    /// REST fetch): `.some(nil)` — the fetched session says EXPLICITLY
    /// nobody — must survive a reconcile that just dropped all frame
    /// verdicts, or the fallback resurrects a phantom turn hint. Used by
    /// the coordinator's turn hints.
    static func layeredVerdict(frame: String??, session: String??) -> String?? {
        if case .some(let verdict) = frame { return .some(verdict) }
        return session
    }

    /// Decode a `turnMemberId` wire field into the three-state verdict:
    /// `.none` = field missing (old server), `.some(nil)` = explicit null
    /// (nobody's turn), `.some(id)` = explicit holder. Shared by the
    /// `game_move` frame and the `POST …/move` response models.
    static func decodeVerdict<K: CodingKey>(
        from container: KeyedDecodingContainer<K>, key: K
    ) throws -> String?? {
        guard container.contains(key) else { return .none }
        if try container.decodeNil(forKey: key) { return .some(nil) }
        return .some(try container.decode(String.self, forKey: key))
    }
}
