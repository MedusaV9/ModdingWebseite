import Foundation

// The app's cue vocabulary (Dossier 47/06): every semantic event owns exactly
// ONE sound+haptic pair, addressed by name instead of scattered play calls.
// This file is Foundation-only so the Linux logic tests can see the whole
// inventory; the runtime side (SoundEngine/Haptics wiring) lives in
// Core/AppCueKit.swift.
//
// House rules of silence — as binding as the catalog itself:
//   · Errors NEVER get a sound. There is no buzzer cue and there never will
//     be one; failures speak through `Haptics.warning()` and visible UI.
//   · App start is silent. The app is a home, not a TV channel.
//   · Quiet hours (default 22–8): the haptic twin replaces the sound, so a
//     sleeping partner is never woken by a ringing phone on the nightstand.
//   · Message bursts: only the first received message rings; the rest of the
//     burst stays a gentle knock (CueScheduler).
//   · When the couple's music is playing, UI cues disappear entirely and all
//     other cues duck (SoundEngine).

/// Mixer category of a cue — mirrors `SoundEngine.Category` raw values so the
/// user's per-category volume sliders keep working for every cue.
enum CueCategory: String, CaseIterable, Codable {
    case moments, chat, games, ui

    /// Scheduling priority when two cues collide inside the rate-limit gap:
    /// moments beat chat, chat beats games, games beat interface ticks.
    var schedulingPriority: Int {
        switch self {
        case .moments: return 3
        case .chat: return 2
        case .games: return 1
        case .ui: return 0
        }
    }
}

/// How a cue is rendered at runtime (Dossier 47, section b).
/// `synth` = procedural synthesis only. `sample` = bundled recording with the
/// synthesis kept as fallback. `hybrid` = recording provides the material
/// transient, the synthesis layers the dreamy tail on top.
enum CueRenderMode: String, Codable {
    case synth, sample, hybrid
}

/// The 19-row cue inventory from Dossier 47 (rows 15 and 18 expand into
/// three fanfare stages and four game foley cues).
enum AppCue: String, CaseIterable, Codable, Identifiable {
    // Chat
    case received, sent, sealed, unseal
    // Moments
    case kiss, hug, heartbeat, sparkle, vibe, pairing
    // Interface
    case chime, click, success, reveal, unlock, drop
    // Celebrations & games
    case fanfareSmall, fanfareMedium, fanfareEpic, lose
    case dice, chip, splash, hit

    var id: String { rawValue }

    var category: CueCategory {
        switch self {
        case .received, .sent, .sealed, .unseal: return .chat
        case .kiss, .hug, .heartbeat, .sparkle, .vibe, .pairing,
             .fanfareSmall, .fanfareMedium, .fanfareEpic: return .moments
        case .chime, .click, .success, .reveal, .unlock, .drop: return .ui
        case .lose, .dice, .chip, .splash, .hit: return .games
        }
    }

    /// Render-mode verdict from the Dossier-47 inventory. The manifest in
    /// Resources/Sounds/sound_credits.json must agree — a LogicTest enforces
    /// it, so the plan, the credits and the bundle can never drift apart.
    var plannedMode: CueRenderMode {
        switch self {
        case .received, .kiss, .reveal, .unseal,
             .dice, .chip, .splash, .hit, .drop:
            return .sample
        case .hug, .chime, .sealed, .unlock:
            return .hybrid
        case .sent, .heartbeat, .sparkle, .vibe, .pairing,
             .click, .success, .fanfareSmall, .fanfareMedium, .fanfareEpic, .lose:
            return .synth
        }
    }

    /// Bundle file name for sample/hybrid cues. ALWAYS derived from the cue
    /// id, never read from the manifest — the manifest documents credits, it
    /// cannot redirect playback (one failure path less).
    var fileName: String { "cue_\(rawValue).caf" }

    /// Key moments that may occupy BOTH channels (ear + hand): the pairing
    /// ceremony and the epic match victory. Everything else follows the
    /// one-channel rule — sound OR haptic, never both at the same instant
    /// (motion eval: doubled feedback reads as slot-machine noise, not
    /// warmth). Even key moments never fire simultaneously: CueKit staggers
    /// the haptic motif behind the fanfare (`keyMomentHapticStagger`).
    var isKeyMoment: Bool {
        self == .pairing || self == .fanfareEpic
    }

    /// The haptic twin: hand and ear experience the same event with the same
    /// envelope. Sharpness follows spectral brightness (glass ≈ 0.7+, paper
    /// and cloth ≈ 0.2–0.4), intensity follows the audio amplitude.
    var hapticTwin: [HapticEventSpec] {
        switch self {
        case .received:
            // Two gentle ticks, like a soft knock on the door.
            return [HapticEventSpec(t: 0.00, i: 0.35, s: 0.50),
                    HapticEventSpec(t: 0.09, i: 0.25, s: 0.45)]
        case .sent:
            // A breath of air leaving the hand.
            return [HapticEventSpec(t: 0.00, i: 0.30, s: 0.25, d: 0.14)]
        case .sealed:
            // Pressure swelling into the wax, then the seal sets.
            return [HapticEventSpec(t: 0.00, i: 0.35, s: 0.20, d: 0.32),
                    HapticEventSpec(t: 0.36, i: 0.80, s: 0.50)]
        case .unseal:
            // A pulling tear that ends in a little snap.
            return [HapticEventSpec(t: 0.00, i: 0.30, s: 0.40, d: 0.26),
                    HapticEventSpec(t: 0.28, i: 0.70, s: 0.70)]
        case .kiss:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.20, d: 0.10),
                    HapticEventSpec(t: 0.12, i: 0.90, s: 0.60)]
        case .hug:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.15, d: 0.80)]
        case .heartbeat:
            return [HapticEventSpec(t: 0.00, i: 0.80, s: 0.30),
                    HapticEventSpec(t: 0.17, i: 0.50, s: 0.25),
                    HapticEventSpec(t: 0.72, i: 0.80, s: 0.30),
                    HapticEventSpec(t: 0.89, i: 0.50, s: 0.25)]
        case .sparkle:
            return [HapticEventSpec(t: 0.00, i: 0.30, s: 0.80),
                    HapticEventSpec(t: 0.09, i: 0.25, s: 0.85),
                    HapticEventSpec(t: 0.18, i: 0.20, s: 0.90)]
        case .vibe:
            return [HapticEventSpec(t: 0.00, i: 0.40, s: 0.20, d: 0.90)]
        case .pairing:
            // Two separate soft pulses that merge into one strong beat.
            return [HapticEventSpec(t: 0.00, i: 0.45, s: 0.30),
                    HapticEventSpec(t: 0.50, i: 0.45, s: 0.30),
                    HapticEventSpec(t: 1.10, i: 1.00, s: 0.40, d: 0.25)]
        case .chime:
            return [HapticEventSpec(t: 0.00, i: 0.45, s: 0.70)]
        case .click:
            return [HapticEventSpec(t: 0.00, i: 0.20, s: 0.60)]
        case .success:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.50),
                    HapticEventSpec(t: 0.11, i: 0.65, s: 0.55)]
        case .reveal:
            // The curtain: rising intensity, falling sharpness.
            return [HapticEventSpec(t: 0.00, i: 0.30, s: 0.80),
                    HapticEventSpec(t: 0.12, i: 0.40, s: 0.70),
                    HapticEventSpec(t: 0.24, i: 0.50, s: 0.60),
                    HapticEventSpec(t: 0.36, i: 0.65, s: 0.45),
                    HapticEventSpec(t: 0.50, i: 0.80, s: 0.30)]
        case .unlock:
            return [HapticEventSpec(t: 0.00, i: 0.60, s: 0.80),
                    HapticEventSpec(t: 0.10, i: 0.50, s: 0.60)]
        case .drop:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.35)]
        case .fanfareSmall:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.50)]
        case .fanfareMedium:
            return [HapticEventSpec(t: 0.00, i: 0.60, s: 0.50),
                    HapticEventSpec(t: 0.16, i: 0.50, s: 0.60)]
        case .fanfareEpic:
            // Three rising accents + a warm rumble finale (was Delight's).
            return [HapticEventSpec(t: 0.00, i: 0.90, s: 0.45),
                    HapticEventSpec(t: 0.16, i: 0.70, s: 0.60),
                    HapticEventSpec(t: 0.32, i: 1.00, s: 0.50),
                    HapticEventSpec(t: 0.52, i: 0.85, s: 0.15, d: 0.70),
                    HapticEventSpec(t: 1.35, i: 0.50, s: 0.30)]
        case .lose:
            // A sympathetic sigh, never a buzzer.
            return [HapticEventSpec(t: 0.00, i: 0.40, s: 0.20, d: 0.30)]
        case .dice:
            return [HapticEventSpec(t: 0.00, i: 0.70, s: 0.80),
                    HapticEventSpec(t: 0.08, i: 0.50, s: 0.75)]
        case .chip:
            return [HapticEventSpec(t: 0.00, i: 0.60, s: 0.70)]
        case .splash:
            return [HapticEventSpec(t: 0.00, i: 0.50, s: 0.30, d: 0.15)]
        case .hit:
            return [HapticEventSpec(t: 0.00, i: 0.90, s: 0.40)]
        }
    }
}

/// The outcome of asking the scheduler whether a cue may ring right now.
struct CueDecision: Equatable {
    var sound: Bool
    var haptic: Bool

    /// Both channels — reserved for `AppCue.isKeyMoment` cues (CueKit still
    /// staggers the haptic behind the sound instead of stacking them).
    static let full = CueDecision(sound: true, haptic: true)
    /// The one-channel default whenever the sound may ring: the ear leads,
    /// the hand stays quiet (motion eval: no doubled feedback).
    static let soundOnly = CueDecision(sound: true, haptic: false)
    /// Sound suppressed (quiet hours, bursts, rate limit, visible chat) —
    /// the haptic twin carries the event alone.
    static let hapticOnly = CueDecision(sound: false, haptic: true)
    /// A coalesced duplicate trigger — the first firing already played.
    static let silent = CueDecision(sound: false, haptic: false)
}

/// Pure rate-limiting brain of the cue vocabulary (Dossier 06, idea 6):
/// nothing kills the soul faster than slot-machine jingling. Injectable
/// clock keeps it fully testable on Linux.
///
/// One-channel rule (motion eval): a cue plays on exactly ONE channel —
/// sound when it may ring, otherwise the haptic twin. Only key moments
/// (`AppCue.isKeyMoment`: pairing, epic match victory) earn both channels,
/// and CueKit staggers even those. Identical cues arriving within the
/// coalesce window (double-wired call sites: a button handler AND a state
/// observer both firing) collapse into one event.
struct CueScheduler {
    /// At most one sound per 300 ms; a higher-priority cue may still ring.
    static let minSoundGap: TimeInterval = 0.3
    /// Messages arriving closer than this form a burst — only the first rings.
    static let chatBurstGap: TimeInterval = 2.0
    /// Direct double-triggers of the SAME cue coalesce into one event —
    /// e.g. chat send firing a manual tap plus the `.sent` cue on the same
    /// interaction. Judged from the last non-coalesced trigger.
    static let coalesceGap: TimeInterval = 0.15
    /// Key moments stagger their haptic motif behind the fanfare's first
    /// accent instead of stacking both channels on the same instant.
    static let keyMomentHapticStagger: TimeInterval = 0.3

    private var lastSoundAt: Date?
    private var lastSoundPriority = -1
    private var lastReceivedAt: Date?
    private var lastCue: AppCue?
    private var lastCueAt: Date?

    init() {}

    mutating func decide(_ cue: AppCue,
                         now: Date = Date(),
                         quietHours: Bool = false,
                         chatVisible: Bool = false) -> CueDecision {
        // Dedupe first: the SAME cue inside the coalesce window is one
        // semantic event, no matter how many call sites report it.
        if cue == lastCue, let at = lastCueAt,
           now.timeIntervalSince(at) < Self.coalesceGap {
            return .silent
        }
        lastCue = cue
        lastCueAt = now

        if cue == .received {
            // Record arrival regardless of the verdict so a burst is judged
            // by message spacing, not by which messages happened to ring.
            defer { lastReceivedAt = now }
            if let last = lastReceivedAt, now.timeIntervalSince(last) < Self.chatBurstGap {
                return .hapticOnly
            }
            // Chat on screen: the message is already the feedback — only a
            // gentle knock, never a ring on top of the visible bubble.
            if chatVisible { return .hapticOnly }
        }
        if quietHours { return .hapticOnly }
        if let last = lastSoundAt,
           now.timeIntervalSince(last) < Self.minSoundGap,
           cue.category.schedulingPriority <= lastSoundPriority {
            return .hapticOnly
        }
        lastSoundAt = now
        lastSoundPriority = cue.category.schedulingPriority
        // One channel by default: the ear leads when it may ring. Only key
        // moments earn the second channel (staggered by CueKit).
        return cue.isKeyMoment ? .full : .soundOnly
    }
}

/// Quiet-hours window math (Dossier 06, idea 21): at night the app feels
/// instead of ringing. Pure so the wrap-around window is testable.
enum QuietHours {
    static let defaultStartHour = 22
    static let defaultEndHour = 8

    static func isQuiet(hour: Int, startHour: Int = defaultStartHour, endHour: Int = defaultEndHour) -> Bool {
        guard startHour != endHour else { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        return hour >= startHour || hour < endHour
    }
}
