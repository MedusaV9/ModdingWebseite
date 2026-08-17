import Foundation

// „Versiegelter Zug" — pure decision rules for the commit-reveal takeover
// guard. Battleship, Stadt-Land-Fluss, Zwei Wahrheiten and Galgenraten seal
// a secret (layout / answers / lie index / word) as a SHA-256 commit whose
// plaintext + salt live ONLY in the committing device's UserDefaults vault.
// Pulling the input lease onto another device during such a phase would
// strand the reveal — the sealed move can never be opened elsewhere. These
// rules decide, from the server-visible move list alone, whether the member
// currently holds an unrevealed commit (→ the takeover button locks with an
// honest device hint instead of luring the couple into a stuck session).
// Foundation-only so Linux `swift test` pins every decision.

/// The commit-reveal-relevant slice of one game move — the view maps
/// `GameMove.data` down to this so the rule stays UI- and JSON-free.
struct GameSecretMoveSummary: Hashable {
    let memberId: String
    /// `data["kind"]` — "reveal" closes a pending commit.
    let kind: String?
    /// `data["round"]` — round-scoped games (SLF, Zwei Wahrheiten) commit
    /// and reveal per round; nil for whole-game secrets (Battleship).
    let round: Int?
    /// True when the move carries a `commit` hash (Battleship `commit`,
    /// SLF `commit`, Zwei Wahrheiten `statements`).
    let carriesCommit: Bool

    init(memberId: String, kind: String?, round: Int?, carriesCommit: Bool) {
        self.memberId = memberId
        self.kind = kind
        self.round = round
        self.carriesCommit = carriesCommit
    }
}

enum GameSecretRules {
    /// Game types whose flow seals device-local secrets. Everything else
    /// may always change devices mid-match. WordleDuo (the creator's
    /// sealed target word, whole-game) and RPS (the own sealed choice per
    /// round) were missing here (FXD-1 Fund 4) — "Hier weiterspielen"
    /// stayed active during their sealed phases and stranded the match on
    /// the vault-less second device.
    static let commitRevealTypes: Set<String> = [
        "battleship", "stadtlandfluss", "twotruths", "hangman",
        "wordleduo", "rps",
    ]

    /// True when `memberId` has sealed a commit in this ACTIVE session that
    /// no reveal has opened yet — the phase in which a takeover onto a
    /// device without the vault would hang the game.
    ///
    /// - Hangman seals in the CREATE payload (`payloadCarriesCommit`), so
    ///   the setter is bound to the committing device until the final
    ///   reveal move.
    /// - All other flows seal per move; a commit is pending until a
    ///   `reveal` by the same member with the same round (nil == nil for
    ///   whole-game secrets) exists. WordleDuo's creator `target` move is
    ///   such a whole-game commit (open until the final verified reveal);
    ///   an RPS `commit` carries its round number, so each member is bound
    ///   only while their OWN round commit is still sealed.
    static func holdsSealedSecret(gameType: String, state: String?, memberId: String,
                                  createdBy: String?, payloadCarriesCommit: Bool,
                                  moves: [GameSecretMoveSummary]) -> Bool {
        guard state == "active", commitRevealTypes.contains(gameType) else { return false }
        let mine = moves.filter { $0.memberId == memberId }
        if gameType == "hangman" {
            guard memberId == createdBy, payloadCarriesCommit else { return false }
            return !mine.contains { $0.kind == "reveal" }
        }
        return mine.contains { move in
            guard move.carriesCommit else { return false }
            return !mine.contains { $0.kind == "reveal" && $0.round == move.round }
        }
    }
}
