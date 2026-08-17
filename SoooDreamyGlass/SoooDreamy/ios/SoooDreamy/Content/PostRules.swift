import Foundation

// Post & Sendungen (FullRelease P6-B) — the pure rules of the Post-Station:
// Zeitpost windows, the open-post allowance, the echo window and its
// once-per-original promise, and the journal's merge order. Foundation-only
// (Linux `swift test`); mirrors `server/src/post.js` POST_LIMITS bit-for-bit —
// the SERVER stays authoritative, these rules only keep the UI honest
// (disable what would be rejected, phrase what is allowed).

/// What a Sendung carries: a touch, a pulse, or a short note.
enum PostKind: String, Codable, CaseIterable, Identifiable {
    case touch, pulse, note
    var id: String { rawValue }
}

enum PostRules {
    // MARK: Limits (mirror of server POST_LIMITS)

    /// A note is a slip of paper, not a letter.
    static let noteMaxLength = 120
    /// Open scheduled posts per PERSON (not per couple).
    static let maxOpen = 5
    /// `deliverAt` must be at least this far ahead …
    static let minLead: TimeInterval = 5 * 60
    /// … the server forgives this much clock skew below the minimum …
    static let leadGrace: TimeInterval = 30
    /// … and at most this far ahead.
    static let maxLead: TimeInterval = 7 * 24 * 3600
    /// A received touch can be sent back for this long.
    static let echoWindow: TimeInterval = 10 * 60
    /// The journal looks back this many days.
    static let journalDays = 30

    // MARK: Zeitpost — deliverAt window

    enum DeliverAtVerdict: Equatable {
        case ok
        /// Less than 5 minutes ahead (beyond the clock-skew grace) —
        /// or already in the past (an offline replay that slept too long).
        case tooSoon
        /// More than 7 days ahead.
        case tooFar
    }

    /// Client-side mirror of the server's `asDeliverAt` check. The grace
    /// belongs to the SERVER's tolerance — the composer should not lean on
    /// it (use `earliestPickable` there), but the verdict must match what
    /// the server would say about an in-flight request.
    static func deliverAtVerdict(_ deliverAt: Date, now: Date = Date()) -> DeliverAtVerdict {
        let lead = deliverAt.timeIntervalSince(now)
        if lead < minLead - leadGrace { return .tooSoon }
        if lead > maxLead { return .tooFar }
        return .ok
    }

    /// Earliest moment the composer should OFFER: the 5-minute minimum plus
    /// a pick-to-send margin, so a time chosen at the edge is still valid
    /// when the request (or an offline replay) reaches the server.
    static func earliestPickable(now: Date = Date()) -> Date {
        now.addingTimeInterval(minLead + 60)
    }

    static func latestPickable(now: Date = Date()) -> Date {
        now.addingTimeInterval(maxLead)
    }

    /// FullRelease R1-D (robustness eval S3): a composer left open long
    /// enough holds a `deliverAt` the server would now reject (`tooSoon`
    /// — the pickable window slid past the pick). The pure nudge rule:
    /// an invalid pick snaps forward to `earliestPickable` (or back to
    /// `latestPickable` for the theoretical `tooFar` case), a valid pick
    /// returns nil and stays exactly where the person put it.
    static func nudgedDeliverAt(_ deliverAt: Date, now: Date = Date()) -> Date? {
        switch deliverAtVerdict(deliverAt, now: now) {
        case .ok: return nil
        case .tooSoon: return earliestPickable(now: now)
        case .tooFar: return latestPickable(now: now)
        }
    }

    // MARK: Zeitpost — open-post allowance

    static func canScheduleMore(openCount: Int) -> Bool {
        openCount < maxOpen
    }

    static func remainingSlots(openCount: Int) -> Int {
        max(0, maxOpen - openCount)
    }

    /// Trimmed note text, or nil when it cannot be posted (empty after
    /// trimming, or longer than the slip of paper allows).
    static func validatedNote(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= noteMaxLength else { return nil }
        return text
    }

    // MARK: Echo — window & once-per-original

    /// Whether the echo window is still open for a touch received at
    /// `originalCreatedAt`. Same comparison as the server: age above the
    /// window expires; a slightly-future timestamp (clock skew) passes.
    static func canEcho(originalCreatedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(originalCreatedAt) <= echoWindow
    }

    /// Once-per-original, judged from the touches the client can see:
    /// any touch carrying `echoOf == originalId` means the echo is taken —
    /// no matter who sent it or whether it arrived via replay.
    static func isEchoTaken(originalId: String, echoedOriginalIds: Set<String>) -> Bool {
        echoedOriginalIds.contains(originalId)
    }

    /// The full client-side gate for showing/enabling the "send back"
    /// affordance: only a RECEIVED touch (not my own, not itself an echo)
    /// within the window, and only while the original is un-echoed.
    static func echoAllowed(originalSenderId: String, myMemberId: String?,
                            originalIsEcho: Bool, originalCreatedAt: Date,
                            alreadyEchoed: Bool, now: Date = Date()) -> Bool {
        guard let myMemberId, originalSenderId != myMemberId else { return false }
        guard !originalIsEcho, !alreadyEchoed else { return false }
        return canEcho(originalCreatedAt: originalCreatedAt, now: now)
    }

    // MARK: Journal — merge order

    /// Server-identical order: newest first; same-instant entries break the
    /// tie on id DESCENDING (the server compares the ISO strings — for equal
    /// timestamps only the id decides, deterministically on every device).
    static func journalOrderedBefore(createdA: Date, idA: String,
                                     createdB: Date, idB: String) -> Bool {
        if createdA != createdB { return createdA > createdB }
        return idA > idB
    }

    /// Merge already-decoded entries (touches, pulses, notes) into the
    /// journal's display order — used when the client stitches live WS
    /// arrivals into a fetched journal without refetching.
    static func journalSorted<T>(_ entries: [T],
                                 createdAt: KeyPath<T, Date>,
                                 id: KeyPath<T, String>) -> [T] {
        entries.sorted {
            journalOrderedBefore(createdA: $0[keyPath: createdAt],
                                 idA: $0[keyPath: id],
                                 createdB: $1[keyPath: createdAt],
                                 idB: $1[keyPath: id])
        }
    }

    /// Entries older than the 30-day horizon fall off the journal.
    static func withinJournalHorizon(createdAt: Date, now: Date = Date()) -> Bool {
        createdAt >= now.addingTimeInterval(-TimeInterval(journalDays) * 86_400)
    }
}
