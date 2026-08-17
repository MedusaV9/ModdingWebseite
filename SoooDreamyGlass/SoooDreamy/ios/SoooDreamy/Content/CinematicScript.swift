import Foundation

// FullRelease N3-Kino — the first-launch cinema, written as a SCRIPT of
// CHAPTERS instead of one procedural reel.
//
// The W8D cut answered the "Remotion question" with procedural-only; the
// recon (docs/styles/RECON_REMOTION_PIPELINE.md) and the style decision
// (docs/styles/STYLE_DECISION.md §3.9) resolve it as a HYBRID now:
// "Video = Kino (zuschauen), prozedural = Bühne (fühlen)." Three
// deterministic look-scenes ship as CI-rendered HEVC clips (scene 2/3/6),
// everything interactive, everything with runtime couple colors and the
// hand-off into the live UI stay procedural (scenes 1/4/5/7).
//
// This file stays Foundation-only and Linux-tested: it owns the chapter
// order, the nominal timings, the haptic beats of every PROCEDURAL render
// path, the sound-bed schedule and the pure fallback rule
// (`chapterPlan(availableVideos:languageChosen:)`). Video chapters carry
// their beats in the committed haptics manifests instead
// (`Content/CinematicManifest.swift` decodes them; the player triggers
// beats via `AVPlayer.addBoundaryTimeObserver` on the player clock).
//
// Missing videos are a LEGAL state (Lite IPA ships none; the recon calls
// it a feature, not a workaround): every video chapter owns a shorter
// procedural Kurzfassung with its own beats, so the cinema NEVER goes
// black — it just plays the stage version of the same story.
//
// Dramaturgy (45–60 s; the language gate waits as long as it needs):
//   1 lampenklick   0– 8  the lamp clicks on, two paper cards offer
//                         "Deutsch" / "English" — the choice IS scene 1
//                         (procedural-interactive, never skipped)
//   2 umschlag      8–16  an envelope slides into the cone, the postmark
//                         stamps "TAG 1"                 (video, 8 s)
//   3 siegelbruch  16–26  the wax seal breaks, the letter unfolds
//                                                        (video, 10 s)
//   4 tinten       26–38  two ink wells: "Wähl deine Farbe" — drop,
//                         stroke, the partner stroke shimmers, both run
//                         together      (procedural-interactive)
//   5 wachssiegel  38–46  the blend pours into the wax seal, the heart
//                         embosses — the `.pairing` moment (procedural)
//   6 polaroid     46–54  an empty polaroid develops and stays empty
//                                                        (video, 8 s)
//   7 ankunft      54–60  the paper lays itself into the home screen —
//                         the cinema ends inside the real UI (procedural)

/// The seven chapters of the first-launch cinema, in playback order.
enum CinematicChapter: String, CaseIterable, Codable {
    /// The lamp clicks on; two paper cards ask for the language.
    case lampenklick
    /// The envelope slides into the light cone, the postmark stamps.
    case umschlag
    /// The neutral wax seal breaks, the letter unfolds.
    case siegelbruch
    /// Two ink wells — the member color choice, strokes run together.
    case tinten
    /// The blend pours into the wax seal and embosses the heart.
    case wachssiegel
    /// The empty polaroid develops from white and stays empty.
    case polaroid
    /// The paper lays itself into the home screen — the hand-off.
    case ankunft
}

/// A CI-rendered bundle video: flat resources next to the .caf sounds
/// (verified in CI run 31878649119 — no subdirectory), e.g.
/// `scene2_envelope.mp4` + `scene2.haptics.json`.
struct CinematicVideoSpec: Equatable {
    /// Basename of the MP4 (`Bundle.main.url(forResource:withExtension:
    /// "mp4")`).
    let videoResource: String
    /// Basename of the haptics manifest (`withExtension: "json"`).
    let manifestResource: String
}

/// One scheduled chapter: nominal duration, whether it waits for the
/// person (language / ink choice), the optional video render path, and
/// the beats + at most one sound cue of the PROCEDURAL render path
/// (times RELATIVE to the chapter start, `HapticEventSpec` wire format).
/// For video chapters the procedural fields describe the Kurzfassung
/// that plays when the MP4 is missing (Lite build, corrupt bundle).
struct CinematicChapterSpec: Equatable {
    let chapter: CinematicChapter
    /// Nominal length. Video chapters pin this to the manifest's
    /// `durationSec` (the manifest tests cross-check the two).
    let duration: Double
    /// Waits for input — the chapter clock pauses until the person acts.
    let interactive: Bool
    /// Minimum WALLCLOCK dwell of an interactive chapter (Kino-Final-Eval
    /// „Wallclock ehrlich"): the person may choose instantly, but the
    /// scene breathes out — the shell never advances before this many
    /// seconds on the chapter clock. The minimums are sized so the
    /// FASTEST first-launch path still lands inside `durationWindow` on
    /// both render paths (pinned by the wallclock tests). Nil for timed
    /// chapters (their dwell IS the rendered duration).
    let minDwell: Double?
    let video: CinematicVideoSpec?
    /// Length of the procedural Kurzfassung when the video is missing.
    let fallbackDuration: Double?
    /// Haptic beats of the procedural render path (chapter-relative).
    let hapticBeats: [HapticEventSpec]
    /// At most one cue per chapter on the procedural path (one-channel
    /// discipline); video chapters ring from their manifest instead.
    let soundCue: AppCue?
    let soundOffset: Double

    init(chapter: CinematicChapter, duration: Double,
         interactive: Bool = false,
         minDwell: Double? = nil,
         video: CinematicVideoSpec? = nil,
         fallbackDuration: Double? = nil,
         hapticBeats: [HapticEventSpec] = [],
         soundCue: AppCue? = nil, soundOffset: Double = 0) {
        self.chapter = chapter
        self.duration = duration
        self.interactive = interactive
        self.minDwell = minDwell
        self.video = video
        self.fallbackDuration = fallbackDuration
        self.hapticBeats = hapticBeats
        self.soundCue = soundCue
        self.soundOffset = soundOffset
    }

    /// The length the chapter actually plays on the given render path.
    func renderedDuration(video isVideo: Bool) -> Double {
        isVideo ? duration : (fallbackDuration ?? duration)
    }

    /// The chapter's wallclock on the FASTEST honest path: timed chapters
    /// play their rendered length; interactive chapters hold at least
    /// their minimum dwell even when the person chooses instantly.
    func fastestDwell(video isVideo: Bool) -> Double {
        interactive ? (minDwell ?? renderedDuration(video: isVideo))
                    : renderedDuration(video: isVideo)
    }
}

/// How one chapter renders at runtime — decided by the pure plan rule,
/// never by the view.
enum CinematicChapterRender: Equatable {
    case video(CinematicVideoSpec)
    case procedural

    var isVideo: Bool {
        if case .video = self { return true }
        return false
    }
}

/// One entry of the playback plan the player performs top to bottom.
struct CinematicChapterPlanEntry: Equatable {
    let spec: CinematicChapterSpec
    let render: CinematicChapterRender

    var playDuration: Double { spec.renderedDuration(video: render.isVideo) }
}

/// The synthesized voices of the score bed (SoundEngine renders them —
/// no assets). Beds are quiet ambience under the events; `mergeBloom` is
/// the single exception and plays only ON the merge beat.
enum CinematicVoice: String, CaseIterable, Codable {
    /// Soft room pad from the ink chapter to the end — the lamp hums.
    case auroraBed
    /// Two side-separated tones that crescendo with the ink strokes'
    /// approach and resolve into the blend.
    case orbTones
    /// Sub-swell + 1.5 s shimmer that blooms with the wax-seal merge.
    case mergeBloom

    /// Ambience tier: beds never count as a second event channel.
    var isBed: Bool { self != .mergeBloom }
}

/// One scheduled bed layer, CHAPTER-relative: interactive chapters wait
/// for the person, so absolute wall-clock times would drift — the layer
/// anchors to its chapter's start instead. `nominalStart`/`nominalEnd`
/// exist for the timeline tests (nominal = nobody hesitates).
struct CinematicSoundLayer: Equatable {
    let voice: CinematicVoice
    let chapter: CinematicChapter
    /// Offset from the chapter start (s).
    let offset: Double
    let duration: Double

    var nominalStart: Double { CinematicScript.chapterStart(chapter) + offset }
    var nominalEnd: Double { nominalStart + duration }
}

enum CinematicScript {
    // MARK: The chapter timeline

    /// The owner's brief asks for 45–60 seconds of first-launch cinema —
    /// the tests pin both render paths (full video cut AND the Lite
    /// Kurzfassung) inside this window.
    static let durationWindow = 45.0...60.0

    /// The full score, gapless and in order by construction; every
    /// derived query below reads from this single source of truth.
    /// Video durations mirror the committed manifests
    /// (`SoooDreamy/remotion/manifests/*.haptics.json`).
    static let chapters: [CinematicChapterSpec] = [
        // 1 — Lampenklick (0–8, waits): the room is dark, the lamp
        // clicks on at ~0.85 s and lights the two language cards. The
        // click is FELT, not heard — app start stays silent (house
        // rule); the confirmation haptic of the choice is the view's.
        // Min dwell 4 s: the card may be chosen instantly, but the scene
        // breathes out before the envelope arrives (wallclock honesty).
        CinematicChapterSpec(
            chapter: .lampenklick, duration: 8, interactive: true,
            minDwell: 4,
            hapticBeats: [
                HapticEventSpec(t: 0.85, i: 0.45, s: 0.55),
            ]),
        // 2 — Der Umschlag (8–16, video 8 s): slides into the cone,
        // the postmark stamps "TAG 1". Kurzfassung (5 s): the same slide
        // and stamp on the procedural stage — the `.sealed` cue is the
        // stamp's voice, the two beats its hand.
        CinematicChapterSpec(
            chapter: .umschlag, duration: 8,
            video: CinematicVideoSpec(videoResource: "scene2_envelope",
                                      manifestResource: "scene2.haptics"),
            fallbackDuration: 5,
            hapticBeats: [
                HapticEventSpec(t: 2.20, i: 0.45, s: 0.30, d: 0.22),
                HapticEventSpec(t: 3.60, i: 0.90, s: 0.62),
            ],
            soundCue: .sealed, soundOffset: 3.60),
        // 3 — Der Siegelbruch (16–26, video 10 s): the wax cracks, the
        // letter unfolds blank. Kurzfassung (6 s): crack + unfold with
        // the existing reveal sound world (`.unseal`).
        CinematicChapterSpec(
            chapter: .siegelbruch, duration: 10,
            video: CinematicVideoSpec(videoResource: "scene3_seal",
                                      manifestResource: "scene3.haptics"),
            fallbackDuration: 6,
            hapticBeats: [
                HapticEventSpec(t: 1.20, i: 0.35, s: 0.20, d: 0.60),
                HapticEventSpec(t: 2.20, i: 0.85, s: 0.72),
            ],
            soundCue: .unseal, soundOffset: 2.20),
        // 4 — Zwei Tintenfässer (26–38, waits): "Wähl deine Farbe." The
        // drop, the stroke and the approach are interaction-driven — the
        // beats live in the view's hands, the beds in `soundLayers`.
        // Min dwell 11.5 s: an instant pick still gets the full drop →
        // stroke → approach → blend arc plus a settled breath — the
        // fastest Lite path must not undercut the 45 s floor.
        CinematicChapterSpec(
            chapter: .tinten, duration: 12, interactive: true,
            minDwell: 11.5),
        // 5 — Das Wachssiegel (38–46): the blend pours and embosses the
        // heart. THE moment of the cinema and the only chapter that
        // speaks on both channels at once: the `.pairing` motif — the
        // exact cue of the 12.0 pairing ceremony — plus one strong
        // double beat exactly on the emboss.
        CinematicChapterSpec(
            chapter: .wachssiegel, duration: 8,
            hapticBeats: [
                HapticEventSpec(t: 1.10, i: 1.00, s: 0.40, d: 0.25),
                HapticEventSpec(t: 1.50, i: 0.40, s: 0.15, d: 0.40),
            ],
            soundCue: .pairing, soundOffset: 1.10),
        // 6 — Das leere Polaroid (46–54, video 8 s): develops from white
        // and stays empty — an invitation, not a reproach. Kurzfassung
        // (5 s): the same development; the `.chime` is the exhale bell
        // of the whole cinema on the Lite path.
        CinematicChapterSpec(
            chapter: .polaroid, duration: 8,
            video: CinematicVideoSpec(videoResource: "scene6_polaroid",
                                      manifestResource: "scene6.haptics"),
            fallbackDuration: 5,
            hapticBeats: [
                HapticEventSpec(t: 1.20, i: 0.50, s: 0.35),
                HapticEventSpec(t: 3.60, i: 0.50, s: 0.50),
            ],
            soundCue: .chime, soundOffset: 3.60),
        // 7 — Ankunft (54–60): the paper LAYS itself into the home
        // screen (Legen), the cinema ends inside the real UI. Haptic
        // only — the bell already rang (scene 6 video cue / Kurzfassung
        // chime); the hand feels the paper settle.
        CinematicChapterSpec(
            chapter: .ankunft, duration: 6,
            hapticBeats: [
                HapticEventSpec(t: 0.60, i: 0.25, s: 0.35),
            ]),
    ]

    /// Nominal total of the full video cut (nobody hesitates): 60 s.
    static var chapterTotalDuration: Double {
        chapters.reduce(0) { $0 + $1.duration }
    }

    static func spec(for chapter: CinematicChapter) -> CinematicChapterSpec? {
        chapters.first { $0.chapter == chapter }
    }

    /// Nominal start of a chapter on the full-cut timeline.
    static func chapterStart(_ chapter: CinematicChapter) -> Double {
        var t = 0.0
        for spec in chapters {
            if spec.chapter == chapter { return t }
            t += spec.duration
        }
        return t
    }

    /// Chapter under the nominal playhead — start inclusive, end
    /// exclusive; nil before 0 and from `chapterTotalDuration` on.
    static func chapter(at t: Double) -> CinematicChapterSpec? {
        guard t >= 0 else { return nil }
        var start = 0.0
        for spec in chapters {
            if t < start + spec.duration { return spec }
            start += spec.duration
        }
        return nil
    }

    /// 0…1 progress inside one chapter at nominal playhead `t`, clamped.
    static func progress(in chapter: CinematicChapter, at t: Double) -> Double {
        guard let spec = spec(for: chapter), spec.duration > 0 else { return 0 }
        let start = chapterStart(chapter)
        return min(1, max(0, (t - start) / spec.duration))
    }

    /// The chapter's procedural beats on the NOMINAL absolute timeline —
    /// the CI freeze test and the stage renderer read the same clock.
    static func absoluteBeatTimes(in chapter: CinematicChapter) -> [Double] {
        guard let spec = spec(for: chapter) else { return [] }
        let start = chapterStart(chapter)
        return spec.hapticBeats.map { start + $0.t }
    }

    // MARK: The merge — chapter 5's strong beat, THE anchor

    /// Offset of the emboss beat inside the wax-seal chapter.
    static var mergeBeatOffset: Double {
        spec(for: .wachssiegel)?.hapticBeats.first?.t ?? 0
    }

    /// Nominal absolute time of the merge beat: 39.1 s.
    static var mergeTime: Double {
        chapterStart(.wachssiegel) + mergeBeatOffset
    }

    /// The shimmer tail the merge bloom carries after the sub-swell.
    static let mergeShimmerDuration = 1.5

    /// How long the two ink strokes run toward each other after the
    /// color choice — matches the orbTones voice (4.4 s) so the tones
    /// resolve exactly INTO the blend.
    static let inkApproachDuration = 4.4

    // MARK: Interaction choreography — named so the wallclock tests can
    // prove the dwell gates never truncate a running arc

    /// Chapter 1's lift beat: the chosen language card lifts toward the
    /// light for this long before the (dwell-gated) advance may fire.
    static let languageLiftDuration = 0.9

    /// Chapter 4's post-pick arc: drop + first stroke before the
    /// approach starts…
    static let inkPickLead = 1.2
    /// …and the settled breath after the strokes met and blended.
    static let inkSettleTail = 1.0

    /// The complete post-pick choreography of the ink chapter. It must
    /// fit INSIDE the chapter's minimum dwell (pinned by the wallclock
    /// tests) so an instant pick never truncates the blend.
    static var inkPickChoreography: Double {
        inkPickLead + inkApproachDuration + inkSettleTail
    }

    // MARK: Wallclock honesty — both paths, fastest AND nominal, 45–60 s

    /// The plan's wallclock on the FASTEST honest path: every choice
    /// lands instantly, the interactive chapters still hold their
    /// minimum dwell (the scene breathes out), timed chapters play their
    /// rendered length. Pinned inside `durationWindow` for BOTH
    /// first-launch paths — the Kurzfassung may be the shorter cut, but
    /// never a rushed one (Kino-Final-Eval „Wallclock ehrlich").
    static func fastestWallclockDuration(_ plan: [CinematicChapterPlanEntry]) -> Double {
        plan.reduce(0) { $0 + $1.spec.fastestDwell(video: $1.render.isVideo) }
    }

    // MARK: The sound bed (synthesized layers under the events)

    /// The bed timeline, chapter-relative (interactive chapters wait, so
    /// the renderer starts each voice on its CHAPTER clock; skip stops
    /// them all — stoppable score). Durations mirror the fixed synth
    /// buffers in SoundEngine (bed 22.3 s, orbs 4.4 s, bloom 2.6 s).
    static let soundLayers: [CinematicSoundLayer] = [
        // The room pad rises with the ink chapter and carries across the
        // seal into the polaroid, where its end-fade closes it.
        CinematicSoundLayer(voice: .auroraBed, chapter: .tinten,
                            offset: 0, duration: 22.3),
        // The two strokes hum on their own stereo sides while they run
        // toward each other; the tones resolve exactly INTO the blend.
        CinematicSoundLayer(voice: .orbTones, chapter: .tinten,
                            offset: 12 - inkApproachDuration,
                            duration: inkApproachDuration),
        // Sub-swell + shimmer ON the merge beat — the one non-bed layer.
        CinematicSoundLayer(voice: .mergeBloom, chapter: .wachssiegel,
                            offset: 1.10,
                            duration: 1.1 + mergeShimmerDuration),
    ]

    // MARK: The plan rule — missing videos are legal, never black

    /// Pure fallback rule: which render path every chapter takes, given
    /// the video basenames that actually exist in the bundle (Lite ships
    /// none; a corrupt bundle may ship some). The language gate leaves
    /// the plan entirely once a language was ever chosen (replay,
    /// demo entry after the first launch).
    static func chapterPlan(availableVideos: Set<String>,
                            languageChosen: Bool) -> [CinematicChapterPlanEntry] {
        chapters.compactMap { spec in
            if spec.chapter == .lampenklick, languageChosen { return nil }
            if let video = spec.video, availableVideos.contains(video.videoResource) {
                return CinematicChapterPlanEntry(spec: spec, render: .video(video))
            }
            return CinematicChapterPlanEntry(spec: spec, render: .procedural)
        }
    }

    /// Nominal runtime of a plan (interactive chapters at their nominal
    /// length) — pinned inside `durationWindow` for both first-launch
    /// paths (full cut 60 s, Lite Kurzfassung 50 s).
    static func plannedTotalDuration(_ plan: [CinematicChapterPlanEntry]) -> Double {
        plan.reduce(0) { $0 + $1.playDuration }
    }

    /// The run of CONSECUTIVE video chapters starting at `index` — these
    /// share one AVQueuePlayer so scene 3 begins seamlessly on scene 2's
    /// end frame (the renders hold matching frames by design).
    static func videoRun(in plan: [CinematicChapterPlanEntry],
                         from index: Int) -> [CinematicChapterPlanEntry] {
        guard plan.indices.contains(index), plan[index].render.isVideo else { return [] }
        var run: [CinematicChapterPlanEntry] = []
        for entry in plan[index...] {
            guard entry.render.isVideo else { break }
            run.append(entry)
        }
        return run
    }

    /// The PERFORMABLE prefix of a video run (Kino-Bugjagd): planning saw
    /// the files, but loading can still fail mid-flight (corrupt bundle).
    /// Dropping an inner chapter would misalign the run's inner indices
    /// against the plan cursor — captions and progress dots would label
    /// the WRONG chapter, and the run's end would skip a chapter that
    /// never played. The rule keeps only the LEADING loadable chapters:
    /// indices stay plan-aligned, and the first broken chapter falls back
    /// to its procedural Kurzfassung when the shell reaches it.
    static func performableRun(_ run: [CinematicChapterPlanEntry],
                               loadable: Set<String>) -> [CinematicChapterPlanEntry] {
        var prefix: [CinematicChapterPlanEntry] = []
        for entry in run {
            guard case .video(let video) = entry.render,
                  loadable.contains(video.videoResource) else { break }
            prefix.append(entry)
        }
        return prefix
    }

    /// The verdict of a video run that DIED mid-flight ON THE DEVICE
    /// (hev1-Bugklasse: real iPhones hardware-decode and refuse `hev1`
    /// sample entries — the AVPlayerItem fails SILENTLY, no
    /// didPlayToEndTime ever fires, the queue runs dry; simulators
    /// decode in software, so CI stayed green). Loading probes cannot
    /// catch this: the file EXISTS, only playback dies. The rule: the
    /// broken inner chapter AND every remaining chapter of the run fall
    /// back to their procedural Kurzfassung — full compositions, never
    /// an empty room. Returns the PLAN index range to restage
    /// procedurally (its lower bound is where the shell resumes,
    /// mid-run); the inner index is clamped into the run so even a
    /// nonsense report yields a performable verdict. Nil only for an
    /// empty run — there is nothing to fall back FROM.
    static func brokenRunFallbackIndices(base: Int, length: Int,
                                         failedInner: Int) -> Range<Int>? {
        guard length > 0 else { return nil }
        let resume = base + min(max(failedInner, 0), length - 1)
        return resume..<(base + length)
    }

    /// Vordergrund-Re-Kick (Sideload-Realität: AltStore refreshes push
    /// the app to the background mid-cinema, and iOS pauses the queue
    /// player): on return the run RESUMES — never restarts, and never
    /// kicks a dead player. Only a living run, a standing player
    /// (rate 0) and a current item that can actually play get the
    /// play() call; a failed or missing item stays with the broken-run
    /// fallback instead of being kicked forever.
    static func shouldResumeVideoAfterForeground(runAlive: Bool, rate: Double,
                                                 itemReady: Bool) -> Bool {
        runAlive && rate == 0 && itemReady
    }

    // MARK: First-frame watchdog — `.readyToPlay` proves no picture

    /// readyToPlay-ohne-Frame-Lücke (Kino-Eval S2): `.readyToPlay` only
    /// proves the demuxer accepted the file — a device decoder can still
    /// refuse every FRAME (hev1-Bugklasse) without item failure,
    /// failed-to-end or a dry queue ever firing. The watchdog gives the
    /// armed item this long of FOREGROUND time to show a first frame:
    static let firstFrameWatchdogTimeout = 1.5

    /// Pure watchdog verdict at the (foreground-honest) timeout: TRUE =
    /// the run is broken and falls back to the procedural Kurzfassung.
    /// The ONLY proof of a picture is the layer's `isReadyForDisplay` —
    /// player-clock progress is NO evidence: the hev1 class can tick the
    /// clock while the hardware decoder refuses every frame (Re-Eval
    /// Runde 2: bloßer Zeitfortschritt zählte als Bildbeweis).
    static func firstFrameWatchdogVerdict(layerReady: Bool) -> Bool {
        !layerReady
    }

    /// Re-arm rule, PER QUEUE ITEM (Re-Eval Runde 2: the watchdog was
    /// armed once on play() — scene 3 after scene 2 ran unguarded): the
    /// dog re-arms whenever the run's current inner item changes,
    /// including the initial arm (nil → 0). `isReadyForDisplay == true`
    /// disarms it (the controller cancels); a same-item report never
    /// restarts a running countdown.
    static func firstFrameWatchdogShouldRearm(from oldItem: Int?,
                                              to newItem: Int) -> Bool {
        oldItem != newItem
    }

    // MARK: Watchdog generations — the frame proof is ITEM-specific
    // (Fix-Runde 3, Kino-Befund 1; verschärft in Fix-Runde 4, S2).
    // Every re-arm opens a NEW generation FOR ONE ITEM and resets the
    // frame mirror to false; a readiness report carries the generation
    // AND the item identity it was CAPTURED under (the layer host
    // stamps both at KVO time, before the main-queue hop). Only a
    // false→true EDGE of the CURRENT (generation, item) disarms —
    // item 1's true (or a seam-held `isReadyForDisplay` that never
    // re-reports) can never free item 2, and without a new edge the
    // watchdog falls back after its window.

    /// Whether a readiness report may touch the armed state at all: it
    /// must name the armed generation AND the armed item (Fix-Runde 4,
    /// S2). The generation alone was not enough — empirically proven:
    /// re-arm first, item 1's late KVO callback stamps AFTERWARDS,
    /// reads generation 2 and passed the old (2==2) gate, falsely
    /// disarming item 2. The item identity captured at the same KVO
    /// instant still names the OLD item, so the report is dropped
    /// whole: no disarm, no frame-mirror write.
    static func firstFrameReportCounts(reportedGeneration: Int,
                                       armedGeneration: Int,
                                       reportedItem: ObjectIdentifier?,
                                       armedItem: ObjectIdentifier?) -> Bool {
        reportedGeneration == armedGeneration && reportedItem == armedItem
    }

    /// The stage surface's poster filter (Fix-Runde 4, S2): what its
    /// `layerReady` mirror becomes after one report. Only ACCEPTED
    /// reports — judged by the SAME (generation, item) truth as the
    /// watchdog — write the mirror; a discarded report changes NOTHING,
    /// so a stale generation's standbild can never hide the CURRENT
    /// chapter's poster.
    static func surfaceLayerReady(current: Bool, reportCounts: Bool,
                                  reported: Bool) -> Bool {
        reportCounts ? reported : current
    }

    /// Whether a COUNTING report disarms the armed watchdog: only the
    /// false→true EDGE — the first frame this generation truly shows.
    /// A repeated true (mirror already high) is no new evidence, and a
    /// false report never disarms anything.
    static func firstFrameEdgeDisarms(alreadyShown: Bool,
                                      reported: Bool) -> Bool {
        reported && !alreadyShown
    }

    /// The armed item's honest observation time: wallclock minus the
    /// backgrounded span. iOS pauses player AND decoder in the
    /// background, so backgrounded wallclock proves nothing about
    /// frames — a foregrounding after >1.5 s away must not count as
    /// an expired watchdog (Wallclock-Foregrounding, Re-Eval Runde 2).
    static func firstFrameForegroundElapsed(wallclock: Double,
                                            backgrounded: Double) -> Double {
        max(0, wallclock - max(0, backgrounded))
    }

    /// What an expired watchdog timer may do: nil = the item really had
    /// its full foreground window — judge now (via the verdict above);
    /// otherwise the remaining foreground seconds to sleep again. Never
    /// returns 0 or negative — that IS the judge-now case.
    static func firstFrameWatchdogRemainder(foregroundElapsed: Double) -> Double? {
        let remaining = firstFrameWatchdogTimeout - foregroundElapsed
        return remaining > 1e-9 ? remaining : nil
    }

    // MARK: Advance discipline — idempotent per chapter, debounced by hand

    /// The idempotency rule of EVERY scheduled advance (Kino-Bugjagd): a
    /// fire armed on chapter `origin` (auto-advance task, language lift,
    /// ink choreography, video-run end) may only move a cursor that still
    /// STANDS on its origin. A stale fire — the auto racing a tap through
    /// the actor hop, a late task, a double schedule — is dropped instead
    /// of restarting the chapter (score refired, clock reset) or skipping
    /// one nobody saw. Backward or in-place targets never fire.
    static func advanceTarget(origin: Int, target: Int, cursor: Int) -> Int? {
        guard cursor == origin, target > origin else { return nil }
        return target
    }

    /// A manual „Weiter" counts only once the chapter stood for a beat —
    /// an accidental double-tap (or a tap landing during the crossfade)
    /// must not hop TWO chapters. Deliberately shorter than every dwell
    /// floor and every Kurzfassung (pinned by tests), so an intentional
    /// skip never feels held back.
    static let manualAdvanceDebounce = 0.35

    /// True when a manual advance may fire on a chapter `age` seconds in.
    static func canManuallyAdvance(chapterAge age: Double) -> Bool {
        age >= manualAdvanceDebounce
    }

    // MARK: Skip — per chapter and for the whole cinema

    /// The language gate is FUNCTION, not film — it can never be
    /// skipped. Every later chapter offers the quiet "Weiter", and the
    /// whole cinema offers "Überspringen" from chapter 2 on.
    static func skippable(_ chapter: CinematicChapter) -> Bool {
        chapter != .lampenklick
    }

    // MARK: Captions — the words live in L10n, never in the pixels

    /// Overlay caption key per chapter (the videos are text-free by
    /// design; SwiftUI renders the words so Dynamic Type and VoiceOver
    /// keep working). The tests pin that every key resolves DE and EN.
    static func captionKey(for chapter: CinematicChapter) -> String {
        "cinematic.chapter.\(chapter.rawValue)"
    }

    /// Seconds after the chapter start before its caption fades in.
    static let captionDelay = 1.2

    // MARK: Ink wells — spoken color names (Re-Eval Runde 2, A11y)

    /// L10n name key per member-palette hex: „Tintenfass {index} von
    /// {total}" left a blind partner picking between eight silent
    /// circles. Mirrors `MemberColorPicker`'s naming (private there —
    /// Components.swift is outside Fix-C reach); the tests pin this
    /// table against `CouplePaletteRules.memberColorHexes` DE+EN, so
    /// palette and names can never drift apart.
    static let inkWellNameKeys: [String: String] = [
        "FF5C8A": "color.rose", "A855F7": "color.purple",
        "6366F1": "color.indigo", "60A5FA": "color.sky",
        "6EE7B7": "color.mint", "FFD166": "color.gold",
        "FB923C": "color.orange", "F87171": "color.coral",
    ]

    /// The spoken name key of one ink well — an unknown hex falls back
    /// to the generic color label instead of a silent circle.
    static func inkWellNameKey(hex: String) -> String {
        inkWellNameKeys[hex] ?? "pairing.color"
    }

    // MARK: Reduce Motion — calm stills instead of motion

    /// Video chapters freeze on their manifest `posterTime` frame,
    /// procedural chapters show their settled composition; each still
    /// stands for `reducedStillDuration`, interactive chapters keep
    /// waiting for the person. The story stays the same story.
    static let reducedStillDuration = 3.5
    /// Opacity crossfade length between two stills (also used at the end).
    static let crossfadeDuration = 0.8

    /// Nominal reduced runtime of the non-interactive chapters — the
    /// interactive two wait, so ~30 s total is the honest expectation.
    static var reducedTimedDuration: Double {
        Double(chapters.filter { !$0.interactive }.count) * reducedStillDuration
    }

    /// One soft pulse marks each still change in the reduced variant —
    /// the haptic stays, only the motion leaves.
    static let reducedStillBeat = HapticEventSpec(t: 0, i: 0.30, s: 0.25)

    // MARK: CI screenshot freeze

    /// Playhead for the `-SoooDreamyScreenshotCinematic` mode: deep in
    /// the wax-seal chapter — the heart embossed, the caption up. The
    /// frozen chapter is PROCEDURAL by design: the screenshot simulator
    /// builds without videos, and the freeze must never depend on one.
    static let screenshotFreezeTime = 43.0

    /// The CI FRAME SERIES (Kino-Bugjagd): one frozen playhead per
    /// chapter type — the gate, both halves of the envelope scene (slide
    /// + stamped postmark), the seal break, the waiting ink choice, the
    /// embossed wax seal, the polaroid and the arrival. Video chapters
    /// freeze as their procedural poster still (the screenshot simulator
    /// ships no videos — the poster path IS the proof). The workflow's
    /// shot loop and the logic tests read this SAME list.
    static let screenshotFrameSeries: [Double] = [2, 9, 12, 20, 30, 41, 50, 57]

    /// Pure freeze rule for the CI shots: an explicit playhead from the
    /// `SoooDreamyCinematicFreeze` launch environment wins (clamped INTO
    /// the timeline — an overshoot still renders the final chapter, an
    /// empty stage never ships), the classic screenshot flag falls back
    /// to `screenshotFreezeTime`, everything else plays live.
    static func freezeTime(argument flagged: Bool,
                           environment raw: String?) -> Double? {
        if let raw, let t = Double(raw) {
            return min(max(t, 0), chapterTotalDuration - 0.5)
        }
        return flagged ? screenshotFreezeTime : nil
    }

    /// The frozen stage under one absolute playhead: the chapter's plan
    /// entry pinned to `.procedural` (video chapters freeze as their
    /// Kurzfassung/poster still) plus the chapter-LOCAL clock the stage
    /// renders with. Nil outside the timeline. The player's frozen path
    /// performs exactly this mapping — pure, so the tests can pin that
    /// EVERY chapter type freezes cleanly.
    static func frozenStageEntry(at t: Double)
        -> (entry: CinematicChapterPlanEntry, local: Double)? {
        guard let spec = chapter(at: t) else { return nil }
        return (CinematicChapterPlanEntry(spec: spec, render: .procedural),
                t - chapterStart(spec.chapter))
    }

    /// Chapter-local pick moment the FROZEN ink shot stages when the
    /// `SoooDreamyCinematicInk` seed is set (Re-Eval Runde 2: the t30
    /// frame froze `inkHex: nil` — the series never proved the chosen
    /// state). At the series' t=30 frame the drop is done, the stroke
    /// fully drawn and the approach visibly MID-RUN: the chosen color
    /// reads as a running trace, not a finished blend (pinned by tests
    /// against the tinten timeline).
    static let screenshotInkPickOffset = 0.5
}
