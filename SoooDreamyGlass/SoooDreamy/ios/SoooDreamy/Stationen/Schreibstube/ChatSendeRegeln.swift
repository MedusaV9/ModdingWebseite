import Foundation

// Pure send rules of the Schreibstube (re-eval 2, Befunde 1 + 5) —
// Foundation-only so the Linux LogicTests pin them:
//   · ChatVersoehnung — the reconciliation LAW of an optimistic send: the
//     server ACK replaces the temp IN PLACE, and the row identity
//     (`rowID`) survives the local→server id swap, so the transcript row
//     never remounts and Spindelstich/Legen can never replay on the ACK.
//   · traegtHerz — the Kitsch-Budget gate of the send-button heart burst:
//     hearts fly ONLY for heart content (or the explicit heart effect,
//     which the Pult checks itself); an everyday text lands quietly as
//     Legen + Stich + Tick.

/// What the reconciliation law needs to see of a message — `Message` (an
/// app-target type) conforms in ChatModel.swift; the LogicTests pin the
/// law through a minimal test double.
protocol VersoehnbarerZettel {
    var id: String { get }
    var senderId: String { get }
    var clientMessageId: String? { get }
    var createdAt: Date { get }
}

extension VersoehnbarerZettel {
    /// Stable transcript-row identity: keyed by (sender, client message
    /// id) wherever a cmid exists, so the optimistic "local-…" temp and
    /// its server-acknowledged replacement are the SAME row (the ForEach
    /// id — no remount, no second Spindelstich/Legen on the ACK).
    /// SENDER-SCOPED (Fix-Runde 3, S1): the server only enforces cmid
    /// uniqueness PER SENDER — both partners may legitimately carry the
    /// same cmid, and a bare cmid key would collide their rows (duplicate
    /// ForEach ids, Dictionary crash in the Legen slots).
    var chatRowID: String {
        if let clientMessageId { return "cmid-\(senderId)-\(clientMessageId)" }
        return id
    }
}

enum ChatVersoehnung {
    /// The reconciliation law: fold one message — server-accepted OR a
    /// local optimistic temp — into the transcript.
    ///   1. Same server id already present (idempotent POST/socket echo)
    ///      → replace in place.
    ///   2. The SENDER'S OWN optimistic temp ("local-…" + same senderId +
    ///      same clientMessageId) → replace AT ITS INDEX: same array
    ///      position, same `chatRowID` — the id swap happens without
    ///      identity loss. Sender-scoped (Fix-Runde 3, S1): the partner's
    ///      message can never steal or replace MY temp just because both
    ///      happen to carry the same cmid.
    ///   3. The REVERSED race (Fix-Runde 4, S1 — empirically proven):
    ///      the incoming message IS a "local-…" temp whose
    ///      (senderId, clientMessageId) SERVER truth already sits in the
    ///      transcript — the ACK landed first (socket echo before a
    ///      delayed temp insert). Server truth wins: the temp is consumed
    ///      by the existing row instead of appended — a second row would
    ///      carry the SAME `chatRowID` (duplicate ForEach ids).
    ///   4. Unknown message → chronological insert.
    static func reconciled<Z: VersoehnbarerZettel>(_ messages: [Z], with sent: Z) -> [Z] {
        var updated = messages
        if let idx = updated.firstIndex(where: { $0.id == sent.id }) {
            updated[idx] = sent
            return updated
        }
        if let cmid = sent.clientMessageId {
            if let idx = updated.firstIndex(where: {
                $0.id.hasPrefix("local-")
                    && $0.senderId == sent.senderId
                    && $0.clientMessageId == cmid
            }) {
                updated[idx] = sent
                return updated
            }
            if sent.id.hasPrefix("local-"),
               updated.contains(where: {
                   !$0.id.hasPrefix("local-")
                       && $0.senderId == sent.senderId
                       && $0.clientMessageId == cmid
               }) {
                return updated
            }
        }
        updated.append(sent)
        updated.sort { $0.createdAt < $1.createdAt }
        return updated
    }
}

/// Kitsch budget of the send frame (re-eval 2, Befund 5 — DESIGN.md):
/// the 7-heart burst is reserved for sends that actually SPEAK heart.
enum ChatSendeRegeln {
    /// The heart emoji family — classic, colored, arrowed, the broken
    /// heart and the newer pink/light-blue/grey scalars. Deliberately NOT
    /// "every emoji": only hearts earn hearts. Scanning SCALARS also
    /// covers the variation-selector and ZWJ compositions (❤️, ❤️‍🔥,
    /// ❤️‍🩹) — each contains a member of this set.
    private static let herzSkalare: Set<UInt32> = [
        0x2764, 0x2763, 0x2665,           // ❤ ❣ ♥
        0x1F49A, 0x1F499, 0x1F49B, 0x1F49C, 0x1F5A4, 0x1F90D, 0x1F90E,
        0x1F9E1,                          // 🧡
        0x1F496, 0x1F497, 0x1F493, 0x1F495, 0x1F49E, 0x1F498, 0x1F49D,
        0x1F49F,                          // 💟
        0x1F494,                          // 💔 — heartbreak still speaks heart
        0x1FA75, 0x1FA76, 0x1FA77,        // 🩵 🩶 🩷
    ]

    /// True when the text visibly carries a heart — the only everyday
    /// send that earns the little heart burst at the send button.
    static func traegtHerz(_ text: String) -> Bool {
        text.unicodeScalars.contains { herzSkalare.contains($0.value) }
    }
}
