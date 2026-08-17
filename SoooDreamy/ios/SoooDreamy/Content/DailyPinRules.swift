import Foundation

/// Date gate for the server-pinned daily question (Schlussrunde 5).
///
/// The server pins `questionId` for ITS UTC day; clients render THEIR local
/// day. Around midnight — or after a timezone hop — the two calendars
/// disagree, and blindly applying the pin would freeze yesterday's question
/// onto today's card/widget. The pin therefore only counts when the server
/// names exactly the day the client is rendering; otherwise the local cycle
/// derivation runs unpinned, as if no entry existed yet.
enum DailyPinRules {
    /// The pin that may be applied to `localDateKey` — nil when there is no
    /// pin, when the pin belongs to a different day, or when the server is
    /// too old to say which day it pinned (no `pinDateKey`): guessing would
    /// risk the frozen-question bug this rule exists to prevent.
    static func applicablePin(pinnedId: Int?, pinDateKey: String?,
                              localDateKey: String) -> Int? {
        guard let pinnedId, pinDateKey == localDateKey else { return nil }
        return pinnedId
    }
}
