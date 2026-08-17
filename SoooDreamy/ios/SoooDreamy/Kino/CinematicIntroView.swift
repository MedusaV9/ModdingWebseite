import SwiftUI
import CoreHaptics

// FullRelease N3-Kino — the SHELL of the first-launch cinema: 45–60
// seconds before anything is set up, told in seven chapters
// (Content/CinematicScript.swift owns order, times and the pure plan
// rule). The shell performs the plan top to bottom:
//   * chapter 1 is the language gate — FUNCTION, not film: it waits as
//     long as it needs, can never be skipped, and leaves the plan once
//     a language was ever chosen (replay, demo entry),
//   * video chapters (2/3/6) play through CinematicVideoRunController —
//     one AVQueuePlayer per run of consecutive clips, beats and cues
//     fired from the haptics manifests on the PLAYER clock,
//   * procedural chapters (1/4/5/7 — and the Kurzfassungen of 2/3/6
//     whenever a video is missing: Lite IPA, corrupt bundle) render in
//     CinematicChapterStages on a chapter-local TimelineView clock,
//   * every chapter ≥ 2 offers the quiet „Weiter", the whole cinema the
//     quiet „Überspringen"; the score (CoreHaptics advanced players +
//     SoundEngine voices) is STOPPABLE and falls silent mid-beat.
//
// Reduce Motion is a version, not an absence (DESIGN.md commandment 13):
// video chapters freeze on their manifest posterTime frame, procedural
// chapters show their settled composition, one soft pulse marks each
// still — and the interactive chapters keep waiting for the person.

/// Persisted first-launch gate. The seen-flag is the only thing the
/// cinema ever writes for itself — same pattern as `DemoMode.flagKey`.
enum CinematicIntroGate {
    static let seenKey = "sooodreamy.cinematicIntroSeen"
    /// The ink chapter's color pick — PairingView offers it as the
    /// preselected member color, so the cinema's choice carries through.
    static let inkHexKey = "sooodreamy.cinematicInkHex"

    /// True on the very first start, before the guide. The CI screenshot
    /// mode always plays (frozen), no matter what an earlier launch on
    /// the same simulator persisted. Demo mode never bypasses this gate:
    /// the cinema finished before „Erst mal ansehen" was even offered.
    static var shouldPlay: Bool {
        if ScreenshotSeed.cinematicFreezeTime != nil { return true }
        return !UserDefaults.standard.bool(forKey: seenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// The 1-line replay hook a future Settings entry calls („Intro
    /// erneut ansehen" — N2-D's decision): clears the seen-flag so the
    /// next OnboardingFlowView appearance plays the cinema again. The
    /// language gate stays out of replays (`languageEverChosen`).
    static func resetForReplay() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }

    /// Whether a language was EVER explicitly chosen BY A PERSON. This
    /// deliberately does NOT key off the `sooodreamy.appLanguage` storage
    /// key: `AppState.bootstrap()` self-assigns `L10n.language` on every
    /// boot to trigger the shared-language mirror, which persists that key
    /// on the very first launch — the gate never appeared for anyone
    /// (the user's report, proven by UI-test run 31906140012). A dedicated
    /// key that only the explicit pickers write keeps the gate honest.
    static let languageChosenKey = "sooodreamy.languageGateDone"

    static var languageEverChosen: Bool {
        UserDefaults.standard.bool(forKey: languageChosenKey)
    }

    /// Every EXPLICIT language pick calls this (cinema gate, guide chips,
    /// settings row) — nothing else may.
    static func markLanguageChosen() {
        UserDefaults.standard.set(true, forKey: languageChosenKey)
    }

    /// The cinema's ink pick, validated against the member palette —
    /// PairingView preselects it so the story continues into setup.
    static var pickedInkHex: String? {
        guard let hex = UserDefaults.standard.string(forKey: inkHexKey),
              Theme.memberColors.contains(hex) else { return nil }
        return hex
    }
}

/// The cinema's own haptic voice. Unlike the fire-and-forget
/// `Haptics.play(events:)`, every pattern starts on an ADVANCED player
/// that stays referenced — so the skip can stop the score mid-beat
/// (Motion-eval finding: a skipped intro must fall silent INSTANTLY,
/// not finish its queued beats into the next screen).
@MainActor
final class CinematicHapticScore {
    private var engine: CHHapticEngine?
    private var players: [CHHapticAdvancedPatternPlayer] = []

    func prepare() {
        guard Haptics.enabled, Haptics.deviceSupportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    func play(beats: [HapticEventSpec]) {
        guard let engine, !beats.isEmpty else { return }
        let events = beats.map { spec -> CHHapticEvent in
            let parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(spec.i)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(spec.s)),
            ]
            return spec.d > 0
                ? CHHapticEvent(eventType: .hapticContinuous, parameters: parameters,
                                relativeTime: spec.t, duration: spec.d)
                : CHHapticEvent(eventType: .hapticTransient, parameters: parameters,
                                relativeTime: spec.t)
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            players.append(player)
        } catch {
            // Haptics are garnish here — a failed pattern never interrupts
            // the picture, and the next chapter tries again.
        }
    }

    /// Stops everything scheduled, immediately. Idempotent.
    func stop() {
        for player in players {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        players.removeAll()
        engine?.stop(completionHandler: nil)
        engine = nil
    }
}

/// The staging of the chapter plan. Owns the cursor, the chapter-local
/// clock, the stoppable score and the chrome (caption, progress dots,
/// „Weiter", „Überspringen") — the chapters themselves live in
/// CinematicChapterStages (procedural) and CinematicChapterPlayer
/// (video).
struct CinematicIntroView: View {
    /// Measured frames of the REAL guide elements underneath (see
    /// CinematicHandoff.swift) — chapter 7 lays its papers onto exactly
    /// these rects, so the hand-off is a morph, never a cut.
    var handoffTargets: [CinematicHandoffElement: CGRect] = [:]
    /// Called exactly once, when the cinema finished or was skipped.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    /// The performed plan — computed ONCE on appear from what the bundle
    /// actually ships (Lite has no videos; the plan rule is pure and
    /// Linux-tested, this view only executes it).
    @State private var plan: [CinematicChapterPlanEntry] = []
    @State private var cursor = 0
    @State private var chapterBegan = Date()
    @State private var hapticScore = CinematicHapticScore()
    /// One task per chapter walks its score events and the auto-advance.
    @State private var chapterTask: Task<Void, Never>?
    /// The interactive chapters' OWN advance task (language lift, ink
    /// choreography) — separate from the score walk, so an instant pick
    /// no longer cancels beats that have not fired yet (Kino-Bugjagd:
    /// the gate's 0.85 s lamp click used to die under a 0.3 s choice).
    @State private var inputTask: Task<Void, Never>?
    @State private var videoController: CinematicVideoRunController?
    @State private var videoRunBase = 0
    @State private var videoRunLength = 0
    /// Plan indices whose video path DIED on this device (hev1-Bugklasse:
    /// the item fails silently, the queue runs dry, the poster frame
    /// cannot decode). These chapters play their procedural Kurzfassung —
    /// mid-run and for the rest of the cinema, never a retry into the
    /// same broken decoder.
    @State private var brokenVideoIndices: Set<Int> = []
    /// Ink chapter input — the pick recolors chapter 5's wax.
    @State private var inkHex: String?
    @State private var inkPicked: Date?
    @State private var finished = false

    /// CI screenshot mode: frozen playhead, no score, no completion.
    private var frozenTime: Double? { ScreenshotSeed.cinematicFreezeTime }

    private var current: CinematicChapterPlanEntry? {
        plan.indices.contains(cursor) ? plan[cursor] : nil
    }

    var body: some View {
        ZStack {
            // Opaque room BASE under the transitioning chapter bodies: the
            // per-chapter crossfade must never let the guide underneath
            // shimmer through (R1-B: the guide is mounted below the whole
            // cinema for the hand-off). Dark while the gate's lamp is
            // still off, lit from chapter 2 on — the animated room in the
            // chapter body performs the actual ignite.
            CinematicRoomStage(t: 0, strength: baseRoomLit ? 1 : 0,
                               animated: false)
            // The run's ONE AVPlayerLayer, mounted UNDER the crossfading
            // chapter bodies and OUTSIDE their `.id` identity (Kino-
            // Bugjagd): a per-chapter layer would blank the outgoing
            // body mid-fade — AVFoundation renders video only into the
            // most recently created AVPlayerLayer — and DIM the whole
            // stage at the 2→3 seam. Live video chapter bodies render
            // chrome only; this surface is the picture, with a poster
            // underlay until the layer truly has a frame.
            if let videoController, frozenTime == nil {
                CinematicVideoSurface(player: videoController.player,
                                      posterURL: videoController.currentPosterURL,
                                      generations: videoController.watchdogGenerations,
                                      onPosterFailure: posterUnderlayFailed,
                                      onLayerReady: { ready, generation in
                                          videoController.layerReadinessChanged(
                                              ready, generation: generation)
                                      })
            }
            if let frozenTime {
                frozenStage(at: frozenTime)
            } else if let entry = current {
                chapterOnStage(entry)
                    .id(cursor)
                    .transition(.opacity)
            }
        }
        // The cinema is the whole stage — no status bar, no home
        // indicator chrome over the room (Kino-Final-Eval finding 7).
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: begin)
        .onDisappear(perform: silence)
        // Sideload-Realität (AltStore refresh mid-cinema): iOS pauses
        // the queue player in the background and nothing restarts it by
        // itself — on return the run RESUMES where it stood (the
        // controller's pure rule refuses restarts and dead players).
        // Leaving `.active` is REPORTED too: the first-frame watchdog
        // counts foreground time only (Re-Eval Runde 2 — a >1.5 s
        // refresh away must not expire the dog on return).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                videoController?.resumeAfterForeground()
            } else {
                videoController?.noteBackgrounded()
            }
        }
    }

    /// The base stays dark while the language gate's lamp is off — the
    /// frozen shots honor the same rule (the freeze used to light even
    /// pre-click chapter-1 frames: `current` is nil in freeze mode).
    private var baseRoomLit: Bool {
        if let frozenTime {
            return CinematicScript.chapter(at: frozenTime)?.chapter != .lampenklick
        }
        return current?.spec.chapter != .lampenklick
    }

    /// One chapter, captured BY VALUE (Kino-Bugjagd): the outgoing
    /// instance of the `.id(cursor)` crossfade keeps rendering during
    /// the fade — with live @State reads it re-rendered the NEW chapter
    /// (clock reset to 0, video surface dropped to the Kurzfassung) the
    /// moment the cursor moved: the double-exposure flash on every
    /// chapter change. Stored properties keep the outgoing instance on
    /// the OLD chapter and the OLD clock until it has fully faded.
    private func chapterOnStage(_ entry: CinematicChapterPlanEntry) -> some View {
        CinematicChapterOnStage(
            entry: entry,
            began: chapterBegan,
            frozenAt: nil,
            planCount: plan.count,
            cursorIndex: cursor,
            inkHex: inkHex,
            inkPickOffset: inkPicked?.timeIntervalSince(chapterBegan),
            videoSurfaceActive: videoController != nil,
            handoffTargets: handoffTargets,
            onNext: nextChapter,
            onSkipAll: skipWholeCinema,
            onChooseLanguage: chooseLanguage,
            onPickInk: pickInk)
    }

    // MARK: Lifecycle

    private func begin() {
        guard frozenTime == nil else { return }
        Haptics.shared.prepare()
        hapticScore.prepare()
        SoundEngine.shared.prepare()
        plan = CinematicScript.chapterPlan(
            availableVideos: CinematicVideoLibrary.availableVideos(),
            languageChosen: CinematicIntroGate.languageEverChosen)
        guard !plan.isEmpty else {
            finishNow()
            return
        }
        if voiceOverEnabled {
            AccessibilityNotification.Announcement(L10n.t("cinematic.a11y")).post()
        }
        cursor = 0
        startChapter(at: 0)
    }

    private func startChapter(at index: Int) {
        guard plan.indices.contains(index) else { return }
        chapterTask?.cancel()
        inputTask?.cancel()
        chapterBegan = Date()
        let entry = plan[index]
        // A chapter whose video path already died on this device never
        // re-enters the broken decoder — its Kurzfassung carries it.
        if entry.render.isVideo, !reduceMotion,
           !brokenVideoIndices.contains(index) {
            startVideoRun(from: index)
            return
        }
        runChapterScore(entry, at: index)
    }

    /// The chapter's score + auto-advance, one task on the chapter clock:
    /// beat pattern at 0 (the engine keeps the beat, not the runloop),
    /// the cue on its offset, the bed voices on theirs — and for timed
    /// chapters the advance at the rendered length. Interactive chapters
    /// wait; their input handlers schedule the advance themselves.
    private func runChapterScore(_ entry: CinematicChapterPlanEntry, at index: Int) {
        let spec = entry.spec
        let schedule = chapterSchedule(spec, planIndex: index)
        // The score walk IS the procedural performer — even when the
        // plan entry says .video, every caller of this path renders the
        // Kurzfassung (missing file, broken decoder). The hold is the
        // KURZFASSUNG's length, not the video's: the stage settles at
        // the shorter cut and must not stand still for the difference.
        let hold: Double? = spec.interactive
            ? nil
            : (reduceMotion ? CinematicScript.reducedStillDuration
                            : spec.renderedDuration(video: false))
        chapterTask = Task {
            var clock = 0.0
            for event in schedule {
                guard await pause(event.time - clock) else { return }
                clock = event.time
                perform(event)
            }
            guard let hold else { return }
            guard await pause(hold - clock) else { return }
            advance(from: index, to: index + 1)
        }
    }

    private struct ChapterEvent {
        let time: Double
        var beats: [HapticEventSpec] = []
        var cue: AppCue?
        var voice: CinematicVoice?
    }

    private func chapterSchedule(_ spec: CinematicChapterSpec,
                                 planIndex: Int) -> [ChapterEvent] {
        if reduceMotion {
            // The quiet version keeps the story's pulse: one soft beat
            // per still change (none on the opening), plus the chapter's
            // cue. No beds — resting, also for the ears.
            var still = ChapterEvent(time: 0)
            if planIndex > 0 { still.beats = [CinematicScript.reducedStillBeat] }
            still.cue = spec.soundCue
            return (still.beats.isEmpty && still.cue == nil) ? [] : [still]
        }
        var events: [ChapterEvent] = []
        if !spec.hapticBeats.isEmpty {
            events.append(ChapterEvent(time: 0, beats: spec.hapticBeats))
        }
        if let cue = spec.soundCue {
            events.append(ChapterEvent(time: spec.soundOffset, cue: cue))
        }
        // Bed voices anchored to this chapter. The orb tones are NOT
        // scheduled here — they ride the ink pick (interactive chapters
        // wait, so their nominal offset would drift; see pickInk).
        for layer in CinematicScript.soundLayers
        where layer.chapter == spec.chapter && layer.voice != .orbTones {
            events.append(ChapterEvent(time: layer.offset, voice: layer.voice))
        }
        return events.sorted { $0.time < $1.time }
    }

    private func perform(_ event: ChapterEvent) {
        // Honest on iPads without a Taptic Engine: no stand-in impacts —
        // the choreography carries the moment alone.
        if !event.beats.isEmpty {
            hapticScore.play(beats: event.beats)
        }
        if !isQuietHour {
            if let cue = event.cue {
                SoundEngine.shared.play(cue: cue)
            }
            if let voice = event.voice {
                SoundEngine.shared.playScoreVoice(synthSound(for: voice))
            }
        }
    }

    private func synthSound(for voice: CinematicVoice) -> SoundEngine.Sound {
        switch voice {
        case .auroraBed: return .cinematicBed
        case .orbTones: return .cinematicOrbs
        case .mergeBloom: return .cinematicBloom
        }
    }

    /// House rule of the cue vocabulary: in quiet hours the app feels
    /// instead of ringing — the cinema honors the same window CueKit does.
    private var isQuietHour: Bool {
        CueKit.quietHoursEnabled
            && QuietHours.isQuiet(hour: Calendar.current.component(.hour, from: Date()),
                                  startHour: CueKit.quietStartHour,
                                  endHour: CueKit.quietEndHour)
    }

    /// Cancellable choreography pause; false = the chapter was left.
    private func pause(_ seconds: Double) async -> Bool {
        guard seconds > 0 else { return !Task.isCancelled }
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    // MARK: Video runs

    /// One AVQueuePlayer per run of CONSECUTIVE video chapters — scene 3
    /// begins seamlessly on scene 2's end frame (the CI renders hold
    /// matching frames by design).
    private func startVideoRun(from index: Int) {
        let run = CinematicScript.videoRun(in: plan, from: index)
        let controller = CinematicVideoRunController(run: run)
        guard !controller.isEmpty else {
            // Files vanished between planning and playing (a corrupt
            // bundle mid-flight) — the Kurzfassung carries the chapter.
            runChapterScore(plan[index], at: index)
            return
        }
        videoRunBase = index
        // The controller may perform only the run's leading loadable
        // prefix (corrupt bundle mid-flight) — the shell hands over
        // exactly where IT ends, and the first broken chapter falls
        // back to its Kurzfassung instead of being silently skipped.
        videoRunLength = controller.chapters.count
        controller.onChapterChange = { inner in
            let target = videoRunBase + inner
            withAnimation(Theme.Motion.arrive) { cursor = target }
            chapterBegan = Date()
        }
        controller.onFinished = {
            // Fade the surface out WITH the incoming chapter body — an
            // instant unmount would flash the base room mid-crossfade.
            withAnimation(Theme.Motion.arrive) { videoController = nil }
            advance(from: videoRunBase + videoRunLength - 1,
                    to: videoRunBase + videoRunLength)
        }
        controller.onRunBroken = { inner in
            fallBackFromBrokenVideoRun(at: inner)
        }
        controller.fireBeat = { beat in
            hapticScore.play(beats: [beat])
        }
        controller.ringCue = { cue in
            if !isQuietHour { SoundEngine.shared.play(cue: cue) }
        }
        videoController = controller
        controller.start()
    }

    /// hev1-Bugklasse (reale Geräte-Screenshots): the probe saw the
    /// files, but the DEVICE decoder refused them mid-run — the queue
    /// died silently and the old shell stood in an empty room under a
    /// running caption. The honest hand-over: the pure rule names every
    /// plan chapter from the broken one to the run's end, they all fall
    /// to their procedural Kurzfassung (full compositions, the same
    /// path Reduce Motion performs), and the CURRENT chapter restages
    /// immediately — mid-run, without a gap.
    private func fallBackFromBrokenVideoRun(at inner: Int) {
        guard !finished, frozenTime == nil, videoController != nil,
              let fallback = CinematicScript.brokenRunFallbackIndices(
                  base: videoRunBase, length: videoRunLength,
                  failedInner: inner),
              plan.indices.contains(fallback.lowerBound) else { return }
        brokenVideoIndices.formUnion(fallback)
        // Idempotent when the break came from the controller itself;
        // required when the POSTER failure broke the run from outside.
        videoController?.stop()
        withAnimation(Theme.Motion.arrive) {
            videoController = nil
            cursor = fallback.lowerBound
        }
        chapterBegan = Date()
        runChapterScore(plan[fallback.lowerBound], at: fallback.lowerBound)
    }

    /// The underlay poster could not decode its frame — on device that
    /// is the SAME decoder playback needs (hev1-Bugklasse), so the run
    /// is about to die too. Fall to the Kurzfassung right away instead
    /// of waiting out the item's own failure. readyToPlay-ohne-Frame-
    /// Lücke (Kino-Eval S2): `.readyToPlay` alone refutes NOTHING — it
    /// only proves the demuxer liked the file. The suspicion stands
    /// unless the layer TRULY shows (`isReadyForDisplay == true`).
    private func posterUnderlayFailed() {
        guard let controller = videoController else { return }
        if controller.player.currentItem?.status == .readyToPlay,
           controller.layerShowsFrame {
            return
        }
        fallBackFromBrokenVideoRun(at: controller.currentIndex)
    }

    // MARK: Input — the two chapters that wait for the person

    /// Seconds the chapter still owes its minimum dwell (Kino-Final-Eval
    /// „Wallclock ehrlich"), measured on the chapter clock — the person
    /// may choose instantly, but the scene breathes out. Reduce Motion
    /// keeps its own quicker rhythm: the stills version never aimed for
    /// the 45 s window, and a waiting person with motion sensitivity is
    /// not held by dramaturgy.
    private func dwellRemaining(_ spec: CinematicChapterSpec) -> Double {
        guard !reduceMotion, let minDwell = spec.minDwell else { return 0 }
        return minDwell - Date().timeIntervalSince(chapterBegan)
    }

    /// Chapter 1's whole purpose: persist the choice (existing L10n
    /// storage — Settings keeps offering the switch later), confirm it
    /// in the hand, and let the chosen card lift before moving on — no
    /// earlier than the chapter's dwell floor. The score task keeps
    /// walking (Kino-Bugjagd): an instant pick must not cancel beats
    /// that have not fired yet — the 0.85 s lamp click survives.
    private func chooseLanguage(_ language: AppLanguage) {
        guard let entry = current, entry.spec.chapter == .lampenklick,
              !finished, frozenTime == nil else { return }
        L10n.language = language
        CinematicIntroGate.markLanguageChosen()
        Haptics.shared.success()
        let origin = cursor
        let lift = reduceMotion ? 0.45 : CinematicScript.languageLiftDuration
        let hold = max(lift, dwellRemaining(entry.spec))
        inputTask?.cancel()
        inputTask = Task {
            guard await pause(hold) else { return }
            advance(from: origin, to: origin + 1)
        }
    }

    /// Chapter 4's pick: remember the ink (PairingView preselects it
    /// later), start the orb tones exactly when the strokes start their
    /// approach, and advance once they have met, the blend settled AND
    /// the chapter's dwell floor passed.
    private func pickInk(_ hex: String) {
        guard let entry = current, entry.spec.chapter == .tinten,
              inkHex == nil, !finished, frozenTime == nil else { return }
        // Glitch-Pass (P2-B): the ink stage swaps palette ↔ partner line
        // with fade transitions — the pick is user input (not playback),
        // so IT carries the driver; without one the palette popped away.
        withAnimation(Theme.Motion.settle) { inkHex = hex }
        inkPicked = Date()
        UserDefaults.standard.set(hex, forKey: CinematicIntroGate.inkHexKey)
        let origin = cursor
        inputTask?.cancel()
        inputTask = Task {
            if reduceMotion {
                guard await pause(1.5) else { return }
            } else {
                // Drop + first stroke, then the approach with its tones.
                guard await pause(CinematicScript.inkPickLead) else { return }
                if !isQuietHour {
                    SoundEngine.shared.playScoreVoice(.cinematicOrbs)
                }
                let arc = CinematicScript.inkApproachDuration
                    + CinematicScript.inkSettleTail
                guard await pause(max(arc, dwellRemaining(entry.spec))) else { return }
            }
            advance(from: origin, to: origin + 1)
        }
    }

    // MARK: Skip & finish

    private func nextChapter() {
        guard let entry = current, !finished,
              CinematicScript.skippable(entry.spec.chapter) else { return }
        // Debounced by the pure rule: an accidental double-tap (or a tap
        // landing during the crossfade) must not hop TWO chapters.
        guard CinematicScript.canManuallyAdvance(
            chapterAge: Date().timeIntervalSince(chapterBegan)) else { return }
        Haptics.shared.tap()
        if let videoController {
            videoController.skipCurrentChapter()
        } else {
            chapterTask?.cancel()
            advance(from: cursor, to: cursor + 1)
        }
    }

    private func skipWholeCinema() {
        guard let entry = current, !finished,
              CinematicScript.skippable(entry.spec.chapter) else { return }
        Haptics.shared.tap()
        finishNow()
    }

    /// The ONE advance gate (Kino-Bugjagd): every scheduled or manual
    /// fire names the chapter it was armed on, and the pure script rule
    /// drops stale fires — a late auto-advance racing a tap used to
    /// RESTART the tapped-to chapter (score refired, clock reset)
    /// because its target equaled the already-current cursor.
    private func advance(from origin: Int, to target: Int) {
        guard !finished, frozenTime == nil else { return }
        guard let next = CinematicScript.advanceTarget(origin: origin,
                                                       target: target,
                                                       cursor: cursor) else { return }
        guard next < plan.count else {
            finishNow()
            return
        }
        withAnimation(Theme.Motion.arrive) { cursor = next }
        startChapter(at: next)
    }

    private func finishNow() {
        guard !finished else { return }
        finished = true
        silence()
        CinematicIntroGate.markSeen()
        onFinished()
    }

    /// The whole performed score falls silent NOW: pending events,
    /// playing haptic patterns, bed voices, the video run. Called on
    /// skip, finish and disappear.
    private func silence() {
        chapterTask?.cancel()
        inputTask?.cancel()
        hapticScore.stop()
        SoundEngine.shared.stopScoreVoices()
        videoController?.stop()
        videoController = nil
    }

    // MARK: CI screenshot freeze

    /// The frozen playhead renders through the SAME chapter stage as the
    /// live cinema, mapped by the pure script rule — EVERY chapter type
    /// freezes: video chapters as their procedural Kurzfassung still
    /// (the screenshot simulator ships no videos; the poster path IS the
    /// visual proof), the interactive two in their waiting composition —
    /// UNLESS a choice seed stages them chosen (Re-Eval Runde 2): the
    /// ink seed passes the picked hex plus the script's pick offset, so
    /// the t30 frame shows drop, drawn stroke and a mid-run approach.
    /// The classic 43 s shot and the CI frame series share this path.
    @ViewBuilder
    private func frozenStage(at t: Double) -> some View {
        if let frozen = CinematicScript.frozenStageEntry(at: t) {
            CinematicChapterOnStage(
                entry: frozen.entry,
                began: Date(),
                frozenAt: frozen.local,
                planCount: CinematicScript.chapters.count,
                cursorIndex: CinematicScript.chapters.firstIndex {
                    $0.chapter == frozen.entry.spec.chapter
                } ?? 0,
                inkHex: ScreenshotSeed.cinematicInkHex,
                inkPickOffset: ScreenshotSeed.cinematicInkHex == nil
                    ? nil : CinematicScript.screenshotInkPickOffset,
                videoSurfaceActive: false,
                handoffTargets: handoffTargets,
                onNext: {}, onSkipAll: {},
                onChooseLanguage: { _ in }, onPickInk: { _ in })
        }
    }
}

/// One chapter ON stage, every input captured BY VALUE (Kino-Bugjagd).
/// The shell swaps chapter identities with `.id(cursor)` + an opacity
/// crossfade, and SwiftUI keeps the OUTGOING instance rendering while it
/// fades. Were this content a closure over the shell's live @State (as
/// it used to be), the outgoing instance would re-render the NEW chapter
/// the moment the cursor moves — clock reset to zero, video surface
/// swapped for the Kurzfassung — a double-exposure flash on every single
/// chapter change. Stored properties pin the outgoing instance to the
/// OLD chapter on the OLD clock until it has fully faded.
///
/// The same body renders the CI freeze (`frozenAt`): a fixed playhead
/// instead of the TimelineView clock, deterministic room and dust.
private struct CinematicChapterOnStage: View {
    let entry: CinematicChapterPlanEntry
    /// Wallclock anchor of the chapter-local clock.
    let began: Date
    /// Frozen playhead (CI screenshots) — nil plays the live clock.
    let frozenAt: Double?
    let planCount: Int
    let cursorIndex: Int
    /// Ink chapter input — the pick recolors chapter 5's wax.
    let inkHex: String?
    /// The pick's moment on the chapter clock (nil while waiting).
    let inkPickOffset: Double?
    /// True while the run's player layer lives BELOW this body (outside
    /// the crossfading identity) — the body then contributes chrome
    /// only; the persistent surface is the picture.
    let videoSurfaceActive: Bool
    let handoffTargets: [CinematicHandoffElement: CGRect]
    let onNext: () -> Void
    let onSkipAll: () -> Void
    let onChooseLanguage: (AppLanguage) -> Void
    let onPickInk: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.coupleTint) private var coupleTint

    /// The Reduce-Motion poster still failed to decode (hev1-Bugklasse:
    /// the file exists, the device decoder refuses it) — the procedural
    /// Kurzfassung stands in. Per-chapter state: `.id(cursor)` gives
    /// every chapter a fresh try.
    @State private var posterBroken = false

    var body: some View {
        if let frozenAt {
            chapterBody(t: frozenAt)
        } else {
            TimelineView(.animation) { timeline in
                chapterBody(t: timeline.date.timeIntervalSince(began))
            }
        }
    }

    /// Live video chapters paint no room and no stage of their own —
    /// the run's persistent surface below is the picture, and an opaque
    /// room here would cover it.
    private var liveVideoSurface: Bool {
        entry.render.isVideo && !reduceMotion && videoSurfaceActive
            && frozenAt == nil
    }

    @ViewBuilder
    private func chapterBody(t: Double) -> some View {
        let skippable = CinematicScript.skippable(entry.spec.chapter)
        let exit = chromeExit(t: t)
        ZStack {
            if !liveVideoSurface {
                room(t: t)
            }
            surface(t: t)
            // The videos composite their dust ABOVE the paper — the
            // stage does the same (video chapters bring their own).
            if !entry.render.isVideo {
                CinematicRoomDust(t: reduceMotion ? 0 : t)
            }
            chrome(t: t)
                .opacity(1 - exit)
        }
        // The merged story element wraps stage + chrome ONLY — the skip
        // vocabulary below stays its own, always reachable elements
        // (Kino-Final-Eval finding 6: VoiceOver used to swallow it).
        .modifier(CinematicA11yModifier(
            merged: !entry.spec.interactive,
            label: L10n.t(CinematicScript.captionKey(for: entry.spec.chapter)),
            next: onNext,
            skipAll: onSkipAll))
        .contentShape(Rectangle())
        // The quiet „Weiter"-Geste: a tap anywhere on a NON-interactive
        // chapter moves on (interactive chapters keep their taps for the
        // cards and ink wells — their skip is the explicit button).
        .onTapGesture {
            if !entry.spec.interactive { onNext() }
        }
        .overlay(alignment: .topTrailing) {
            if skippable { skipAllButton.opacity(1 - exit) }
        }
        .overlay(alignment: .bottomTrailing) {
            if skippable { nextChapterButton.opacity(1 - exit) }
        }
    }

    /// The Zimmer behind every chapter — chapter 1's lamp click ignites
    /// the cone on its felt beat (0.85 s), everything later burns full.
    /// The finale settles the dramatic cinema light into the EXACT ambient
    /// composition of `DreamyBackground` (same window as the chrome exit),
    /// so the layer swap changes no background pixel (R2, letzter Kino-S2).
    /// Frozen frames render the same math at a standing playhead.
    private func room(t: Double) -> some View {
        let strength: Double = entry.spec.chapter == .lampenklick && !reduceMotion
            ? CinematicStageMath.smooth((t - 0.85) / 0.5)
            : 1
        return CinematicRoomStage(t: reduceMotion ? 0 : t,
                                  strength: strength,
                                  animated: !reduceMotion && frozenAt == nil,
                                  ambientSettle: ambientSettle(t: t))
    }

    /// 0…1 during the arrival chapter's final window; Reduce Motion lives
    /// in ambient light for the whole finale (no animated hand-off there).
    private func ambientSettle(t: Double) -> Double {
        guard entry.spec.chapter == .ankunft else { return 0 }
        if reduceMotion { return 1 }
        let duration = entry.playDuration
        return CinematicStageMath.smooth((t - (duration - 1.6)) / 0.8)
    }

    /// The finale's chrome leaves BEFORE the entry paths land (t57-
    /// Handoff, Gesamtbild-Eval S1): the first paper starts flying at
    /// 1.2 s — caption, dots and the skip vocabulary are fully gone by
    /// 1.1 s, so the caption pill never touches the buttons and dots +
    /// „Weiter" never compete with the paths. The CI freeze (t57) shows
    /// the same clean state; the bottom stays a fixed free band. Reduce
    /// Motion renders the settled arrival — same rule, chrome off. The
    /// merged VoiceOver element keeps its named next/skip actions.
    private func chromeExit(t: Double) -> Double {
        guard entry.spec.chapter == .ankunft else { return 0 }
        if reduceMotion { return 1 }
        return CinematicStageMath.smooth((t - 0.35) / 0.75)
    }

    /// The picture of the chapter: nothing when the run's persistent
    /// player surface below carries it, the Reduce-Motion poster still,
    /// or the procedural stage (always for 1/4/5/7, as the Kurzfassung
    /// for 2/3/6 without their clip — and for every frozen frame).
    @ViewBuilder
    private func surface(t: Double) -> some View {
        switch entry.render {
        case .video(let video):
            if reduceMotion {
                if !posterBroken,
                   let url = CinematicVideoLibrary.videoURL(for: video.videoResource),
                   let manifest = CinematicVideoLibrary.manifest(named: video.manifestResource) {
                    CinematicPosterView(url: url, posterTime: manifest.posterTime,
                                        onDecodeFailure: {
                        // Same decoder as playback: the still will never
                        // come — the settled Kurzfassung is the honest
                        // version, not a bare room placeholder.
                        withAnimation(Theme.Motion.arrive) { posterBroken = true }
                    })
                } else {
                    proceduralStage(t: t)
                }
            } else if videoSurfaceActive {
                Color.clear.allowsHitTesting(false)
            } else {
                // The run controller could not load this chapter — the
                // Kurzfassung stands in, the stage is never black.
                proceduralStage(t: t)
            }
        case .procedural:
            proceduralStage(t: t)
        }
    }

    @ViewBuilder
    private func proceduralStage(t: Double) -> some View {
        // Reduce Motion: the settled end pose of the same composition —
        // the timed chapters become calm stills, the interactive two
        // keep their (quiet) input paths.
        let settled = entry.spec.renderedDuration(video: false)
        let stageTime = reduceMotion ? settled : t
        switch entry.spec.chapter {
        case .lampenklick:
            // Under a freeze the language seed stages the gate CHOSEN
            // (Re-Eval Runde 2 — the frame series never proved the
            // selection); live runs never see the seed.
            CinematicLanguageGateStage(
                t: t, reduceMotion: reduceMotion,
                staged: frozenAt != nil ? ScreenshotSeed.cinematicChosenLanguage : nil
            ) { language in
                onChooseLanguage(language)
            }
        case .umschlag:
            CinematicEnvelopeStage(t: stageTime)
        case .siegelbruch:
            CinematicSealBreakStage(t: stageTime)
        case .tinten:
            CinematicInkStage(t: t, reduceMotion: reduceMotion,
                              chosenHex: inkHex,
                              pickTime: inkPickOffset) { hex in
                onPickInk(hex)
            }
        case .wachssiegel:
            CinematicWaxSealStage(t: stageTime, blend: inkBlend)
        case .polaroid:
            CinematicPolaroidStage(t: stageTime)
        case .ankunft:
            CinematicArrivalStage(t: stageTime, targets: handoffTargets)
        }
    }

    /// The ink chapter's mix, recomputed for chapter 5's wax — same law
    /// as the stage (chosen ink toward lamp gold).
    private var inkBlend: Color? {
        inkHex.map { Color(hex: $0).mix(with: Licht.lampengold, by: 0.4) }
    }

    // MARK: Chrome — caption, dots, skip vocabulary

    private func chrome(t: Double) -> some View {
        VStack(spacing: Space.l) {
            Spacer()
            caption(t: t)
            progressDots
        }
        .padding(.bottom, Space.xxl)
        .allowsHitTesting(false)
    }

    /// The chapter's words — the videos are text-free by design, SwiftUI
    /// renders the caption so Dynamic Type and VoiceOver keep working.
    /// Serif lives ONLY on visible paper (style law — Kino-Final-Eval
    /// finding 5): the line stands on a small paper Zettel in the cone,
    /// never bare on the night room. No grain, no tilt — the slip is a
    /// reading surface, and the tilt budget belongs to the stage props.
    /// Weiß-Audit verdict (MIGRATION_DUNKEL §10, N4): this slip IS an
    /// artifact — a WRITTEN intertitle in the silent-film sense, compact
    /// inset scale, never a full pane — it stays bright paper.
    private func caption(t: Double) -> some View {
        let reveal = reduceMotion
            ? 1.0
            : CinematicStageMath.smooth((t - CinematicScript.captionDelay) / 0.6)
        // The paper Zettel exists FOR its words: a caption that resolves
        // to nothing (or whitespace) must never stand as an empty pill
        // on the night room (Geräte-Screenshot der Bugklasse). The pure
        // rule pins non-empty captions for every plan; this guard keeps
        // the promise even against a future broken table.
        let words = L10n.t(CinematicScript.captionKey(for: entry.spec.chapter))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if !words.isEmpty {
                Text(words)
                    .font(Typo.brief)
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .paperCard(.brief, padding: .compact, grain: false)
                    .padding(.horizontal, Space.xxl)
                    .opacity(reveal)
                    .contentColumn(.reading)
            }
        }
    }

    /// Quiet progress: one dot per plan chapter — the current one wears
    /// the couple blend (defaults before any couple exists).
    private var progressDots: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<planCount, id: \.self) { index in
                Circle()
                    .fill(index == cursorIndex
                          ? AnyShapeStyle(coupleTint.blend)
                          : AnyShapeStyle(Papier.aufNacht.opacity(0.28)))
                    .frame(width: LayoutMetrics.s(index == cursorIndex ? 8 : 5),
                           height: LayoutMetrics.s(index == cursorIndex ? 8 : 5))
            }
        }
        .accessibilityLabel(L10n.t("cinematic.progressA11y",
                                   ["current": String(cursorIndex + 1),
                                    "total": String(max(planCount, 1))]))
    }

    private var skipAllButton: some View {
        Button {
            onSkipAll()
        } label: {
            Text(L10n.t("cinematic.skip"))
                .font(Typo.label)
                .foregroundStyle(Papier.aufNacht.opacity(0.7))
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.l)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .padding(.top, Space.m)
        .padding(.trailing, Space.s)
        .accessibilityIdentifier("cinematic.skipAll")
        .accessibilityHint(L10n.t("cinematic.skipA11y"))
    }

    private var nextChapterButton: some View {
        Button {
            onNext()
        } label: {
            HStack(spacing: Space.xs) {
                Text(L10n.t("cinematic.next"))
                Image(systemName: "chevron.right")
            }
            .font(Typo.label)
            .foregroundStyle(Papier.aufNacht.opacity(0.7))
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.l)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .padding(.bottom, Space.m)
        .padding(.trailing, Space.s)
        .accessibilityIdentifier("cinematic.next")
        .accessibilityHint(L10n.t("cinematic.nextA11y"))
    }
}

/// With closed eyes, every passive chapter is ONE element that speaks
/// its OWN caption (Kino-Final-Eval finding 6: a generic cinema label
/// used to swallow the words) and carries the skip vocabulary as REAL
/// actions: activate = „Weiter" to the next chapter, plus two named
/// actions — „Weiter" and „Kino überspringen". The interactive chapters
/// expose their children instead (the language cards and ink wells MUST
/// be reachable — the gate cannot be skipped, not even by accident);
/// their chrome buttons stay separate elements outside this merge.
private struct CinematicA11yModifier: ViewModifier {
    let merged: Bool
    /// The chapter's caption — the story line VoiceOver reads.
    let label: String
    let next: () -> Void
    let skipAll: () -> Void

    func body(content: Content) -> some View {
        if merged {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityHint(L10n.t("cinematic.nextA11y"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { next() }
                .accessibilityAction(named: Text(L10n.t("cinematic.next"))) { next() }
                .accessibilityAction(named: Text(L10n.t("cinematic.skipAll"))) { skipAll() }
        } else {
            content
        }
    }
}
