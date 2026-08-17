import Foundation

// Foundation-only Live-Activity/Widget lifecycle logic, shared by the app and
// the widget extension and covered by the Linux logic tests. Everything here
// enforces one rule from DESIGN.md: the lock screen never claims a fresher
// truth than a sideloaded app (no APNs) can actually deliver.

// MARK: - Tap targets

/// Deep-link destinations for activities and widgets. The strings mirror the
/// hosts `AppState.handleURL` routes — keep both sides in sync.
enum ActivityLink {
    static let pulse = "sooodreamy://tab/home"
    static let countdown = "sooodreamy://events"
    /// Celebration state: capture the moment — straight into the photos.
    static let celebration = "sooodreamy://photos"
    /// The date-night card lives on the dashboard; `handleURL` has no
    /// dedicated date-night route (yet), so the honest target is home.
    static let dateNight = "sooodreamy://tab/home"
    static let daily = "sooodreamy://daily"
    /// W7-Rest: the sealed daily reveal — a tap on the gold seal jumps
    /// straight into the ceremony instead of just landing on home.
    static let reveal = "sooodreamy://reveal"
    static let sendLove = "sooodreamy://tab/home"

    static func url(_ raw: String) -> URL? { URL(string: raw) }
}

// MARK: - Honesty rules (staleness, sleep, transparency)

enum ActivityHonesty {
    /// Presence/mood in the pulse activity goes stale after 25 minutes, not
    /// 8 hours — a relationship app must never claim "online" all evening
    /// after the app died.
    static let pulseStaleInterval: TimeInterval = 25 * 60

    /// Data older than this makes the activities show their "aktualisiert
    /// vor …" footer (rendered system-side, costs no updates).
    static let transparencyAge: TimeInterval = 10 * 60

    static func showsLastRefresh(refreshedAt: Date, isStale: Bool,
                                 now: Date = Date()) -> Bool {
        isStale || now.timeIntervalSince(refreshedAt) > transparencyAge
    }

    /// True while the partner's declared sleep mode is running — the card
    /// comes to rest ("Schläft — bis später") instead of nagging about
    /// missing touches. Mirrors the server's lazy presence expiry.
    static func partnerAsleep(mode: String?, until: Date?,
                              now: Date = Date()) -> Bool {
        guard mode == "sleep" else { return false }
        guard let until else { return true }
        return until > now
    }

    /// Content-identical updates are still pushed once in a while so the
    /// short stale window keeps sliding forward while the app is
    /// demonstrably alive — without a re-render on every socket event.
    static let keepAliveInterval: TimeInterval = 5 * 60

    /// Whether an activity update is worth pushing: real content changes
    /// always are; unchanged content only when the previous push is old
    /// enough that the stale window needs a nudge.
    static func shouldPush(contentChanged: Bool, staleDate: Date?,
                           staleInterval: TimeInterval,
                           now: Date = Date()) -> Bool {
        if contentChanged { return true }
        guard let staleDate else { return true }
        let lastPush = staleDate.addingTimeInterval(-staleInterval)
        return now.timeIntervalSince(lastPush) >= keepAliveInterval
    }
}

// MARK: - Alert copy (bilingual — the shared layer has no L10n table)

/// Copy for the rare lock-screen alert moments. Kept here so the exact
/// wording is testable on Linux and identical in app + widget process.
enum ActivityAlertText {
    static func touchReceived(partnerName: String?, emoji: String,
                              language: String) -> (title: String, body: String) {
        let de = language == "de"
        let name = (partnerName?.isEmpty == false)
            ? partnerName! : (de ? "Dein Schatz" : "Your partner")
        return (title: "\(emoji) \(name)",
                body: de ? "\(name) denkt gerade an dich."
                         : "\(name) is thinking of you right now.")
    }

    static func countdownArrived(title: String, emoji: String,
                                 language: String) -> (title: String, body: String) {
        let de = language == "de"
        return (title: "\(emoji) \(title)",
                body: de ? "Der Moment ist da — feiert ihn!"
                         : "The moment is here — celebrate it!")
    }

    static func dateNightLive(partnerName: String?,
                              language: String) -> (title: String, body: String) {
        let de = language == "de"
        let name = (partnerName?.isEmpty == false)
            ? partnerName! : (de ? "euch beide" : "you two")
        return (title: de ? "💞 Es geht los!" : "💞 It's on!",
                body: de ? "Eure Date-Night beginnt — Zeit für \(name)."
                         : "Your date night starts — time for \(name).")
    }
}

// MARK: - Update hygiene

/// Content states that carry a refresh timestamp next to their payload.
protocol RefreshStampedState: Hashable {
    var refreshedAt: Date { get set }
}

enum ActivityUpdateHygiene {
    /// Two states are the same CONTENT when only the refresh stamp differs.
    /// Such updates are skipped entirely: every WS event used to force a
    /// re-render of the island (budget, battery, contentTransition flicker).
    static func contentChanged<State: RefreshStampedState>(_ old: State,
                                                           _ new: State) -> Bool {
        var a = old
        var b = new
        let epoch = Date(timeIntervalSince1970: 0)
        a.refreshedAt = epoch
        b.refreshedAt = epoch
        return a != b
    }

    /// True when `new` marks a genuinely newer moment than `old` — the
    /// guard for "this touch deserves a lock-screen alert".
    static func isNewer(_ new: Date?, than old: Date?) -> Bool {
        guard let new else { return false }
        guard let old else { return true }
        return new > old
    }
}

/// Lock-screen alerts are rare by charter: at most two per activity
/// lifetime — key moments only, never a drumbeat.
enum ActivityAlertBudget {
    static let maxAlertsPerActivity = 2

    static func mayAlert(alreadySent: Int) -> Bool {
        alreadySent < maxAlertsPerActivity
    }
}

// MARK: - Countdown lifecycle

enum CountdownLifecycle {
    /// The stale date sits EXACTLY on the target: the stale transition is a
    /// guaranteed system-side re-render at the very moment of celebration —
    /// even when the app has been dead since the night before.
    static func staleDate(target: Date) -> Date { target }

    /// How long a finished celebration lingers before dismissing itself.
    static let celebrationLinger: TimeInterval = 3 * 3600

    /// Celebration truth for the views: the explicit flag, a passed target,
    /// or the stale transition (which fires exactly at the target).
    static func isCelebrating(celebrationFlag: Bool?, target: Date,
                              isStale: Bool, now: Date = Date()) -> Bool {
        celebrationFlag == true || target <= now || (isStale && target <= now)
    }

    /// A compact ticking timer far from the moment is noise: beyond this
    /// horizon the island shows the static day count instead.
    static let compactTickerHorizon: TimeInterval = 48 * 3600

    static func showsCompactTicker(target: Date, liveTimer: Bool,
                                   now: Date = Date()) -> Bool {
        liveTimer && target > now
            && target.timeIntervalSince(now) < compactTickerHorizon
    }

    /// Which running activities belong to no existing event any more.
    /// Matching prefers the stable event id; activities started before the
    /// id existed fall back to the title. Activities whose moment already
    /// arrived are never orphans — they are celebrations winding down.
    static func orphanIndices(
        activities: [(eventId: String?, title: String, target: Date)],
        eventIds: Set<String>, eventTitles: Set<String>,
        now: Date = Date()
    ) -> [Int] {
        activities.enumerated().compactMap { index, activity in
            guard activity.target > now else { return nil }
            if let id = activity.eventId {
                return eventIds.contains(id) ? nil : index
            }
            return eventTitles.contains(activity.title) ? nil : index
        }
    }
}

// MARK: - Date-night lifecycle

enum DateNightLifecycle {
    /// If nobody ever advances the phase, the activity dims 6 h after the
    /// planned start instead of pretending the evening is still ahead.
    static let liveGrace: TimeInterval = 6 * 3600

    /// How long the afterglow lingers before the card leaves the lock
    /// screen on its own — the evening ends with dignity, not with a stale
    /// card at breakfast.
    static let afterglowLinger: TimeInterval = 3 * 3600

    static func endDate(phaseChangedAt: Date) -> Date {
        phaseChangedAt.addingTimeInterval(afterglowLinger)
    }

    static func staleDate(isAfterglow: Bool, startsAt: Date,
                          phaseChangedAt: Date) -> Date {
        isAfterglow ? endDate(phaseChangedAt: phaseChangedAt)
                    : startsAt.addingTimeInterval(liveGrace)
    }
}

// MARK: - Celebration day (widget confetti)

enum CelebrationDay {
    /// Extra render slots across the celebration day: timeline entries are
    /// free (only reloads cost budget), and each slot re-seeds the confetti
    /// so the static widget still feels alive.
    static func entryDates(target: Date, now: Date,
                           stepHours: Int = 4, count: Int = 6) -> [Date] {
        guard stepHours > 0, count > 0 else { return [] }
        return (0..<count)
            .map { target.addingTimeInterval(TimeInterval($0 * stepHours) * 3600) }
            .filter { $0 > now }
    }

    /// Which confetti slot a render date falls into (0 before the moment).
    static func slot(for date: Date, target: Date, stepHours: Int = 4) -> Int {
        let elapsed = date.timeIntervalSince(target)
        guard elapsed > 0, stepHours > 0 else { return 0 }
        return Int(elapsed / (TimeInterval(stepHours) * 3600))
    }
}

struct ConfettiPiece: Equatable {
    /// Normalized position (0…1 in both axes).
    let x: Double
    let y: Double
    /// Rotation in radians.
    let angle: Double
    /// 0.6…1.4 — small size jitter.
    let scale: Double
    /// Index into the rendering palette (0…3).
    let paletteIndex: Int
}

enum ConfettiLayout {
    /// Stable seed from the event key plus a per-entry slot. Swift's Hasher
    /// is deliberately process-randomized, so this uses FNV-1a: the same
    /// event lays the same confetti on every device and every render.
    static func seed(eventKey: String, slot: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in eventKey.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        hash ^= UInt64(truncatingIfNeeded: slot) &* 0x9E37_79B9_7F4A_7C15
        return hash == 0 ? 0x9E37_79B9_7F4A_7C15 : hash
    }

    static func pieces(seed: UInt64, count: Int) -> [ConfettiPiece] {
        var state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func next() -> Double {
            // xorshift64* — tiny, deterministic, plenty for confetti.
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            let value = state &* 0x2545_F491_4F6C_DD1D
            return Double(value >> 11) / Double(UInt64(1) << 53)
        }
        guard count > 0 else { return [] }
        return (0..<count).map { _ in
            ConfettiPiece(x: next(), y: next(),
                          angle: next() * 2 * .pi,
                          scale: 0.6 + next() * 0.8,
                          paletteIndex: min(Int(next() * 4), 3))
        }
    }
}

// MARK: - Pulse day summary (dignified end of the evening)

enum PulseDaySummary {
    /// How long the closing line stays on the lock screen after the
    /// good-night ritual before the card removes itself.
    static let linger: TimeInterval = 2 * 3600

    /// "Heute berührt 💓 · Serie 12 · Gute Nacht 🌙" — the pulse activity's
    /// closing line when the good-night ritual ends the day.
    static func line(streak: Int, bothAnswered: Bool,
                     lastTouchEmoji: String?, language: String) -> String {
        let de = language == "de"
        var parts: [String] = []
        if let lastTouchEmoji, !lastTouchEmoji.isEmpty {
            parts.append(de ? "Heute berührt \(lastTouchEmoji)"
                            : "Touched today \(lastTouchEmoji)")
        }
        if streak > 0 {
            parts.append(de ? "Serie \(streak)" : "Streak \(streak)")
        }
        if bothAnswered {
            parts.append(de ? "Frage beantwortet ✓" : "Question answered ✓")
        }
        parts.append(de ? "Gute Nacht 🌙" : "Good night 🌙")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Good-night ritual outcome

/// Result of the three-step good-night ritual (presence → pulse → check-in).
/// The dialog is honest about partial success and always names a way out.
struct GoodNightOutcome: Equatable {
    var presenceSet: Bool
    var pulseSent: Bool
    var checkinDone: Bool

    var anySucceeded: Bool { presenceSet || pulseSent || checkinDone }
    var allSucceeded: Bool { presenceSet && pulseSent && checkinDone }

    func dialog(partnerName: String?, language: String) -> String {
        let de = language == "de"
        let name = (partnerName?.isEmpty == false)
            ? partnerName! : (de ? "dein Schatz" : "your partner")
        if allSucceeded {
            return de
                ? "Gute Nacht 🌙 — \(name) weiß jetzt, dass du schläfst."
                : "Good night 🌙 — \(name) knows you're off to sleep."
        }
        if !anySucceeded {
            return de
                ? "Das hat gerade nicht geklappt — ist euer Server erreichbar? Versuch es gleich nochmal."
                : "That didn't work right now — is your server reachable? Try again in a moment."
        }
        var done: [String] = []
        if presenceSet { done.append(de ? "Schlafmodus an" : "sleep mode on") }
        if pulseSent { done.append(de ? "Gute-Nacht-Puls unterwegs" : "good-night pulse sent") }
        if checkinDone { done.append(de ? "Abend-Check-in gesetzt" : "evening check-in done") }
        let list = done.joined(separator: ", ")
        return de
            ? "Fast geschafft: \(list). Der Rest hat nicht geklappt — öffne die App, um ihn nachzuholen."
            : "Almost there: \(list). The rest didn't go through — open the app to finish up."
    }
}

// MARK: - Partner status brief (Siri: "Wie geht es Lea?" — 43#4)

/// One spoken status sentence for PartnerMoodIntent + GoodMorningIntent —
/// built ONLY from app-group snapshot data, defined even when the cache is
/// empty (empty answers break user automations, honest fallbacks don't).
enum PartnerStatusLine {
    static func line(snapshot: WidgetSnapshot?, name: String, german de: Bool,
                     now: Date = Date()) -> String {
        guard let snapshot else {
            return de ? "Öffne SoooDreamy einmal, dann weiß ich mehr über \(name)."
                      : "Open SoooDreamy once and I'll know more about \(name)."
        }
        var parts: [String] = []
        if let mood = snapshot.partnerMood, !mood.isEmpty {
            parts.append(de ? "\(name) fühlt sich \(mood)" : "\(name) is feeling \(mood)")
        }
        if let energy = snapshot.partnerEnergyLevel {
            let text: String? = switch energy {
            case "green": de ? "Energie voll 🔋" : "energy full 🔋"
            case "yellow": de ? "Energie mittel" : "energy okay"
            case "red": de ? "Energie niedrig 🪫" : "energy low 🪫"
            default: nil
            }
            if let text { parts.append(text) }
        }
        let presenceActive = snapshot.partnerPresenceUntil.map { $0 > now } ?? true
        if presenceActive, let mode = snapshot.partnerPresenceMode {
            if mode == "sleep" {
                parts.append(de ? "schläft gerade 😴" : "asleep right now 😴")
            } else if mode == "focus" {
                parts.append(de ? "ist im Fokus 🎯" : "in focus mode 🎯")
            }
        } else if snapshot.partnerOnline == true {
            parts.append(de ? "ist gerade online" : "online right now")
        }
        if parts.isEmpty {
            return de ? "\(name) hat heute noch nichts geteilt. 💭"
                      : "\(name) hasn't shared anything yet today. 💭"
        }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Widget connection honesty (sign-out vs. first launch)

enum WidgetConnection {
    enum State: Equatable {
        /// Snapshot + credentials — render normally.
        case ready
        /// Session gone but old data lingers: say "abgemeldet", never show
        /// day-old partner mood as if it were merely stale.
        case signedOut
        /// Nothing written yet — invite to open the app once.
        case awaitingFirstOpen
        /// Sideload without the app-group entitlement: the widgets can never
        /// see app data; explain the re-sign fix.
        case appGroupMissing
    }

    static func state(hasAppGroup: Bool, hasCredentials: Bool,
                      hasSnapshot: Bool) -> State {
        guard hasAppGroup else { return .appGroupMissing }
        if hasCredentials {
            return hasSnapshot ? .ready : .awaitingFirstOpen
        }
        return hasSnapshot ? .signedOut : .awaitingFirstOpen
    }
}
