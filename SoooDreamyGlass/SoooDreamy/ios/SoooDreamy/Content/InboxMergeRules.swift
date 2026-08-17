import Foundation

// Merge rules for `GET /api/inbox` → local app state. The inbox reports
// what happened SINCE the last check window — which overlaps with events
// the client may have already seen live (or read on another device). These
// rules decide what may be adopted, so the missed-inbox refresh can update
// `unreadChat` and the last-touch teaser without ever rewinding fresher
// local truth. Foundation-only so Linux `swift test` covers every branch.
enum InboxMergeRules {
    /// New unread-chat badge after an inbox check.
    ///
    /// - Never lowers: live socket events may have counted messages the
    ///   (older) inbox window doesn't know about.
    /// - Never resurrects: when my own read receipt (`myLastReadAt`, any of
    ///   my devices) is at/after the newest missed message, the "missed"
    ///   messages were already read — the badge stays as it is.
    /// - Old servers without a message teaser (`newestMissedAt == nil`)
    ///   still raise the badge — a WS gap must not hide mail.
    static func mergedUnreadChat(localUnread: Int, missedCount: Int?,
                                 newestMissedAt: Date?, myLastReadAt: Date?) -> Int {
        guard let missedCount, missedCount > 0 else { return localUnread }
        if let read = myLastReadAt, let newest = newestMissedAt, read >= newest {
            return localUnread
        }
        return max(localUnread, missedCount)
    }

    /// Whether the inbox touch teaser may become the "last touch" shown on
    /// widgets/live activities: only when it is provably newer than what
    /// the client already shows (replays never rewind a fresher touch).
    static func adoptsTouchTeaser(teaserAt: Date?, currentLastTouchAt: Date?) -> Bool {
        guard let teaserAt else { return false }
        guard let current = currentLastTouchAt else { return true }
        return teaserAt > current
    }
}
