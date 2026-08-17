import Foundation

// Runtime side of the cue vocabulary: `AppCue.play()` is the ONE public API
// for "this semantic event just happened — let it sound and feel right".
// It consults the pure CueScheduler (rate limiting, burst throttling) and
// the quiet-hours window, then drives SoundEngine + the haptic twin. The
// catalog, scheduler and quiet-hours math live Foundation-only in
// Core/AppCueCatalog.swift so Linux tests cover them.
//
// One-channel contract (motion eval):
//   * A cue occupies ONE channel — sound when it may ring, otherwise its
//     haptic twin. Only `AppCue.isKeyMoment` cues (pairing, epic match
//     victory) earn both, and even those are STAGGERED: the fanfare leads,
//     the motif answers `CueScheduler.keyMomentHapticStagger` later.
//   * Call sites must not pair a manual `Haptics.tap()`/`sensoryFeedback`
//     with a cue for the same interaction — the cue's twin IS the haptic.
//     Where a legacy caller still double-fires (chat send: tap +
//     sensoryFeedback + `.sent` cue), the scheduler coalesces identical
//     cues inside `CueScheduler.coalesceGap` (~150 ms) into ONE event, so
//     the vocabulary side never doubles the feedback again.

@MainActor
enum CueKit {
    private static var scheduler = CueScheduler()

    /// Quiet hours (Dossier 06, idea 21): at night the app feels instead of
    /// ringing — one partner sleeps while the other writes. On by default;
    /// the Settings toggle arrives with the settings wave.
    static var quietHoursEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "sooodreamy.quietHoursEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.quietHoursEnabled") }
    }

    static var quietStartHour: Int {
        get { UserDefaults.standard.object(forKey: "sooodreamy.quietStartHour") as? Int ?? QuietHours.defaultStartHour }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.quietStartHour") }
    }

    static var quietEndHour: Int {
        get { UserDefaults.standard.object(forKey: "sooodreamy.quietEndHour") as? Int ?? QuietHours.defaultEndHour }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.quietEndHour") }
    }

    /// Plays one cue as a sound+haptic pair. `chatVisible` matters only for
    /// `.received`: with the chat on screen the bubble itself is the news,
    /// so the cue stays a gentle knock. `hapticOverride` swaps the cue's
    /// generic twin for a specific motif (the game victory signature,
    /// roadmap 24) while keeping scheduling and quiet hours intact;
    /// `soundOverride` is its sound-side sibling — another CATALOG cue's
    /// sample rings instead (the chat send's dry spindle tick). The override
    /// carries ONLY the material: scheduling, coalescing, quiet hours AND
    /// the mixer channel (per-category volume slider) all stay the original
    /// cue's — `.sent` with the `.chip` sample still rides the Chat slider,
    /// never the Games one (re-eval 2, Befund 3).
    static func play(_ cue: AppCue, chatVisible: Bool = false, now: Date = Date(),
                     hapticOverride: [HapticEventSpec]? = nil,
                     soundOverride: AppCue? = nil) {
        let hour = Calendar.current.component(.hour, from: now)
        let quiet = quietHoursEnabled
            && QuietHours.isQuiet(hour: hour, startHour: quietStartHour, endHour: quietEndHour)
        let decision = scheduler.decide(cue, now: now, quietHours: quiet, chatVisible: chatVisible)
        if decision.sound {
            SoundEngine.shared.play(cue: soundOverride ?? cue, mixedAs: cue.category)
            if cue == .unseal {
                // The paper tears, then the shimmer rises (Dossier 47, cue 13).
                Task {
                    do {
                        try await Task.sleep(nanoseconds: 400_000_000)
                    } catch { return }
                    SoundEngine.shared.play(cue: .reveal)
                }
            }
        }
        if decision.haptic {
            let events = hapticOverride ?? cue.hapticTwin
            if decision.sound && cue.isKeyMoment {
                // Key moments own both channels but never the same instant:
                // the fanfare leads, the motif answers a beat later.
                Task {
                    do {
                        let stagger = CueScheduler.keyMomentHapticStagger
                        try await Task.sleep(nanoseconds: UInt64(stagger * 1_000_000_000))
                    } catch { return }
                    Haptics.shared.play(events: events)
                }
            } else {
                Haptics.shared.play(events: events)
            }
        }
    }
}

extension AppCue {
    /// `AppCue.sealed.play()` — the call sites' entire vocabulary.
    @MainActor
    func play(chatVisible: Bool = false) {
        CueKit.play(self, chatVisible: chatVisible)
    }
}
