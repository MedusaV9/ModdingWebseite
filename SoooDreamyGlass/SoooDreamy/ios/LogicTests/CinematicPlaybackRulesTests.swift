import XCTest
@testable import SoooDreamyLogic

/// Playback-hardening rules of the first-launch cinema (Kino-Bugjagd):
/// the idempotent advance gate, the manual-advance debounce, the
/// performable video-run prefix and the CI freeze parametrization with
/// its frame series. Every rule here is pure — the shell only executes
/// what these tests pin.
final class CinematicPlaybackRulesTests: XCTestCase {

    private let allVideos: Set<String> = [
        "scene2_envelope", "scene3_seal", "scene6_polaroid",
    ]

    // MARK: The idempotent advance — one fire per chapter, never a restart

    func testAdvanceFiresOnlyWhileTheCursorStandsOnItsOrigin() {
        // The armed fire matches the cursor: it moves.
        XCTAssertEqual(CinematicScript.advanceTarget(origin: 2, target: 3, cursor: 2), 3)
        // A tap already moved the cursor on — the stale auto-advance is
        // dropped instead of RESTARTING chapter 3 (score refired, clock
        // reset: the double-fire glitch).
        XCTAssertNil(CinematicScript.advanceTarget(origin: 2, target: 3, cursor: 3))
        // A very late fire from two chapters ago never jumps backward.
        XCTAssertNil(CinematicScript.advanceTarget(origin: 1, target: 2, cursor: 4))
    }

    func testAdvanceNeverMovesBackwardOrInPlace() {
        XCTAssertNil(CinematicScript.advanceTarget(origin: 3, target: 3, cursor: 3),
                     "an in-place target would restart the running chapter")
        XCTAssertNil(CinematicScript.advanceTarget(origin: 3, target: 2, cursor: 3),
                     "the cinema only ever plays forward")
    }

    func testVideoRunEndAdvanceUsesTheRunsLastChapterAsOrigin() {
        // The run's finish fires from its LAST chapter to one past the
        // run — the same rule guards it, so a whole-cinema skip racing
        // the finish can never double-advance.
        let base = 1, length = 2
        XCTAssertEqual(CinematicScript.advanceTarget(origin: base + length - 1,
                                                     target: base + length,
                                                     cursor: base + length - 1),
                       base + length)
        XCTAssertNil(CinematicScript.advanceTarget(origin: base + length - 1,
                                                   target: base + length,
                                                   cursor: base + length))
    }

    // MARK: The manual-advance debounce — one tap, one chapter

    func testManualAdvanceDebounceBoundaries() {
        XCTAssertGreaterThan(CinematicScript.manualAdvanceDebounce, 0)
        XCTAssertFalse(CinematicScript.canManuallyAdvance(chapterAge: 0),
                       "the second half of a double-tap lands near age 0")
        XCTAssertFalse(CinematicScript.canManuallyAdvance(
            chapterAge: CinematicScript.manualAdvanceDebounce - 0.01))
        XCTAssertTrue(CinematicScript.canManuallyAdvance(
            chapterAge: CinematicScript.manualAdvanceDebounce))
    }

    func testDebounceNeverHoldsADeliberateSkipHostage() {
        // Shorter than every rendered chapter on BOTH paths and shorter
        // than every dwell floor: someone hammering „Weiter" still walks
        // the whole cinema chapter by chapter.
        for spec in CinematicScript.chapters {
            XCTAssertLessThan(CinematicScript.manualAdvanceDebounce,
                              spec.renderedDuration(video: false),
                              "\(spec.chapter): debounce outlasts the Kurzfassung")
            if let dwell = spec.minDwell {
                XCTAssertLessThan(CinematicScript.manualAdvanceDebounce, dwell)
            }
        }
    }

    // MARK: The performable run prefix — inner indices stay plan-aligned

    private func fullVideoRun() -> [CinematicChapterPlanEntry] {
        let plan = CinematicScript.chapterPlan(availableVideos: allVideos,
                                               languageChosen: false)
        guard let start = plan.firstIndex(where: { $0.render.isVideo }) else {
            XCTFail("plan lost its video chapters")
            return []
        }
        return CinematicScript.videoRun(in: plan, from: start)
    }

    func testPerformableRunKeepsEverythingWhenAllChaptersLoad() {
        let run = fullVideoRun()
        XCTAssertEqual(CinematicScript.performableRun(run, loadable: allVideos),
                       run)
    }

    func testPerformableRunStopsAtTheFirstUnloadableChapter() {
        // Scene 3's file broke between planning and playing: only the
        // LEADING prefix plays. Dropping the inner chapter instead would
        // shift every later inner index — wrong caption, wrong dots, and
        // the run's end would skip a chapter nobody saw.
        let run = fullVideoRun() // [umschlag, siegelbruch]
        let prefix = CinematicScript.performableRun(run,
                                                    loadable: ["scene2_envelope"])
        XCTAssertEqual(prefix.map(\.spec.chapter), [.umschlag])
    }

    func testPerformableRunIsEmptyWhenTheFirstChapterIsBroken() {
        let run = fullVideoRun()
        XCTAssertTrue(CinematicScript.performableRun(run, loadable: ["scene3_seal"])
            .isEmpty,
            "a broken FIRST chapter downgrades the whole run — the shell falls back")
        XCTAssertTrue(CinematicScript.performableRun(run, loadable: []).isEmpty)
    }

    func testPerformableRunIgnoresProceduralEntries() {
        let plan = CinematicScript.chapterPlan(availableVideos: [],
                                               languageChosen: false)
        XCTAssertTrue(CinematicScript.performableRun(plan, loadable: allVideos)
            .isEmpty,
            "procedural entries never enter a queue player")
    }

    // MARK: The broken-run verdict — hev1-Bugklasse, mid-run fallback

    func testBrokenRunFallsBackFromTheFailedChapterToTheRunsEnd() {
        // The device decoder killed the run at inner index k: THIS
        // chapter and every remaining chapter of the run restage
        // procedurally — the Kurzfassungen carry the story from exactly
        // where the video died, never an empty room, never a skipped
        // chapter. Scenes 2+3 share a run at plan base 1.
        XCTAssertEqual(CinematicScript.brokenRunFallbackIndices(
            base: 1, length: 2, failedInner: 0), 1..<3,
            "item 1 died instantly (typical hev1): the WHOLE run falls back")
        XCTAssertEqual(CinematicScript.brokenRunFallbackIndices(
            base: 1, length: 2, failedInner: 1), 2..<3,
            "scene 2 played, scene 3 died: only the remainder falls back")
    }

    func testBrokenRunVerdictMapsOntoTheRunsPlanChapters() {
        // The verdict's indices are PLAN indices: applied to the full
        // plan they name exactly the run's chapters from the break on.
        let plan = CinematicScript.chapterPlan(availableVideos: allVideos,
                                               languageChosen: false)
        guard let base = plan.firstIndex(where: { $0.render.isVideo }) else {
            return XCTFail("plan lost its video chapters")
        }
        let run = CinematicScript.videoRun(in: plan, from: base)
        guard let fallback = CinematicScript.brokenRunFallbackIndices(
            base: base, length: run.count, failedInner: 0) else {
            return XCTFail("a live run must yield a verdict")
        }
        XCTAssertEqual(fallback.map { plan[$0].spec.chapter },
                       [.umschlag, .siegelbruch])
    }

    func testBrokenRunVerdictClampsNonsenseInnerIndices() {
        // A garbled report still yields a PERFORMABLE verdict — the
        // stage never strands on an empty range outside the run.
        XCTAssertEqual(CinematicScript.brokenRunFallbackIndices(
            base: 1, length: 2, failedInner: -3), 1..<3,
            "an underflow clamps to the run's first chapter")
        XCTAssertEqual(CinematicScript.brokenRunFallbackIndices(
            base: 1, length: 2, failedInner: 99), 2..<3,
            "an overshoot clamps to the run's last chapter, never past it")
    }

    func testBrokenRunVerdictOnAnEmptyRunIsNil() {
        XCTAssertNil(CinematicScript.brokenRunFallbackIndices(
            base: 1, length: 0, failedInner: 0),
            "nothing played, nothing breaks — the empty-run path (isEmpty) owns it")
    }

    // MARK: The first-frame watchdog — readyToPlay proves no picture

    func testFirstFrameWatchdogJudgesOnlyByTheDisplayedFrame() {
        // readyToPlay-ohne-Frame-Lücke, verschärft (Re-Eval Runde 2):
        // the ONLY success proof is `isReadyForDisplay == true`. A
        // ticking player clock is NO evidence — the hev1 class ticks
        // while the hardware decoder refuses every frame, and the old
        // time-progress escape waved exactly that through.
        XCTAssertTrue(CinematicScript.firstFrameWatchdogVerdict(layerReady: false),
                      "no displayed frame at the timeout = broken run")
        XCTAssertFalse(CinematicScript.firstFrameWatchdogVerdict(layerReady: true),
                       "the layer truly shows — the run lives")
    }

    func testFirstFrameWatchdogRearmsPerQueueItem() {
        // Item change re-arms — INCLUDING the initial arm (nil → 0):
        // scene 3 after scene 2 must prove its own first frame.
        XCTAssertTrue(CinematicScript.firstFrameWatchdogShouldRearm(from: nil, to: 0))
        XCTAssertTrue(CinematicScript.firstFrameWatchdogShouldRearm(from: 0, to: 1))
        // A same-item report never restarts a running countdown (the
        // disarm on readyForDisplay is the controller's cancel — the
        // rule only guards against double arming).
        XCTAssertFalse(CinematicScript.firstFrameWatchdogShouldRearm(from: 1, to: 1))
    }

    // MARK: Watchdog generations — the frame proof is ITEM-specific
    // (Fix-Runde 3, Kino-Befund 1; Item-Provenienz in Fix-Runde 4, S2)

    /// Stand-in for AVPlayerItem identity — the pure rule compares only
    /// ObjectIdentifiers, never AVFoundation types.
    private final class ItemStandIn {}

    func testStaleGenerationReportNeverCounts() {
        // „Spätes altes true entwaffnet nicht": item 1's readiness
        // callback hops the main queue and lands AFTER the re-arm for
        // item 2 — its capture-time stamp names the old generation, so
        // the report is dropped whole (no disarm, no mirror write).
        let alt = ItemStandIn(), neu = ItemStandIn()
        XCTAssertFalse(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 1, armedGeneration: 2,
            reportedItem: ObjectIdentifier(alt),
            armedItem: ObjectIdentifier(neu)))
        // A report from a FUTURE generation is equally alien — only the
        // armed generation's own reports count.
        XCTAssertFalse(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 3, armedGeneration: 2,
            reportedItem: ObjectIdentifier(neu),
            armedItem: ObjectIdentifier(neu)))
    }

    func testRearmBeforeCallbackRaceNeverCounts() {
        // THE empirically proven race (Fix-Runde 4, S2): the re-arm for
        // item 2 fires FIRST, item 1's late KVO callback stamps
        // AFTERWARDS — it reads generation 2, and the old
        // generation-only gate waved it through ((2==2) falsely
        // disarmed item 2). The stamp's ITEM provenance still names the
        // OLD item, so the report never counts: altes Item, neue Gen.
        let alt = ItemStandIn(), neu = ItemStandIn()
        XCTAssertFalse(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 2, armedGeneration: 2,
            reportedItem: ObjectIdentifier(alt),
            armedItem: ObjectIdentifier(neu)),
            "a matching generation with a foreign item must never count")
        // A missing observed item (dry queue at capture time) is no
        // proof for an armed item either.
        XCTAssertFalse(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 2, armedGeneration: 2,
            reportedItem: nil, armedItem: ObjectIdentifier(neu)))
    }

    func testSameItemWithCurrentGenerationCounts() {
        // „Gleiches Item + aktuelle Gen zählt": only the armed pair's
        // own reports may touch the watchdog and the frame mirror.
        let item = ItemStandIn()
        XCTAssertTrue(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 2, armedGeneration: 2,
            reportedItem: ObjectIdentifier(item),
            armedItem: ObjectIdentifier(item)))
        // The watchdog-less surface path stamps the neutral (0, nil)
        // and is judged against the same neutral truth — it counts.
        XCTAssertTrue(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 0, armedGeneration: 0,
            reportedItem: nil, armedItem: nil))
    }

    func testSurfacePosterFilterFollowsOnlyAcceptedReports() {
        // Surface-Filter-Regel (Fix-Runde 4, S2): the poster underlay's
        // `layerReady` mirror follows ACCEPTED reports in both
        // directions — and a discarded report changes NOTHING, in
        // either mirror state: a stale generation's standbild must
        // never hide (or expose) the current chapter's poster.
        XCTAssertTrue(CinematicScript.surfaceLayerReady(
            current: false, reportCounts: true, reported: true))
        XCTAssertFalse(CinematicScript.surfaceLayerReady(
            current: true, reportCounts: true, reported: false))
        XCTAssertFalse(CinematicScript.surfaceLayerReady(
            current: false, reportCounts: false, reported: true),
            "a discarded true must not hide the poster")
        XCTAssertTrue(CinematicScript.surfaceLayerReady(
            current: true, reportCounts: false, reported: false),
            "a discarded false must not drop a truly showing frame")
    }

    func testOnlyACurrentGenerationEdgeDisarms() {
        // „Kante der aktuellen Generation entwaffnet": the re-arm reset
        // the mirror to false — the first true of THIS (generation,
        // item) arming is the edge that frees the item.
        let item = ItemStandIn()
        XCTAssertTrue(CinematicScript.firstFrameReportCounts(
            reportedGeneration: 2, armedGeneration: 2,
            reportedItem: ObjectIdentifier(item),
            armedItem: ObjectIdentifier(item)))
        XCTAssertTrue(CinematicScript.firstFrameEdgeDisarms(
            alreadyShown: false, reported: true))
        // A repeated true (mirror already high) is no NEW evidence, and
        // a false report never disarms anything.
        XCTAssertFalse(CinematicScript.firstFrameEdgeDisarms(
            alreadyShown: true, reported: true))
        XCTAssertFalse(CinematicScript.firstFrameEdgeDisarms(
            alreadyShown: false, reported: false))
        XCTAssertFalse(CinematicScript.firstFrameEdgeDisarms(
            alreadyShown: true, reported: false))
    }

    func testSeamHeldReadyWithoutANewEdgeFallsBackAfterTheWindow() {
        // „Naht-gehaltenes ready ohne neue Kante → Fallback nach
        // Fenster": across the 2→3 seam the layer can HOLD
        // `isReadyForDisplay == true` without ever re-reporting — no
        // KVO change, no edge, and the re-arm reset the mirror to
        // false. At the timeout the verdict judges that reset mirror:
        // the run breaks into its Kurzfassung instead of standing on
        // item 1's stale proof.
        XCTAssertTrue(CinematicScript.firstFrameWatchdogVerdict(layerReady: false),
                      "no current-generation edge at the timeout = broken run")
        // Only a mirror raised BY the current generation survives it.
        XCTAssertFalse(CinematicScript.firstFrameWatchdogVerdict(layerReady: true))
    }

    func testFirstFrameWatchdogCountsForegroundTimeOnly() {
        // Wallclock-Foregrounding (Re-Eval Runde 2): an AltStore refresh
        // parks the app for 4 s — on return the dog has seen 0.4 s of
        // FOREGROUND and must sleep the remaining 1.1 s, never judge.
        let foreground = CinematicScript.firstFrameForegroundElapsed(
            wallclock: 4.4, backgrounded: 4.0)
        XCTAssertEqual(foreground, 0.4, accuracy: 1e-9)
        XCTAssertEqual(CinematicScript.firstFrameWatchdogRemainder(
            foregroundElapsed: foreground) ?? -1, 1.1, accuracy: 1e-9)
        // The full foreground window really passed — judge now.
        XCTAssertNil(CinematicScript.firstFrameWatchdogRemainder(
            foregroundElapsed: CinematicScript.firstFrameWatchdogTimeout))
        XCTAssertNil(CinematicScript.firstFrameWatchdogRemainder(
            foregroundElapsed: CinematicScript.firstFrameWatchdogTimeout + 3))
        // Garbage clocks clamp instead of arming a negative sleep.
        XCTAssertEqual(CinematicScript.firstFrameForegroundElapsed(
            wallclock: 1.0, backgrounded: 2.5), 0)
        XCTAssertEqual(CinematicScript.firstFrameForegroundElapsed(
            wallclock: 1.0, backgrounded: -3), 1.0)
        XCTAssertEqual(CinematicScript.firstFrameWatchdogRemainder(
            foregroundElapsed: 0) ?? -1,
            CinematicScript.firstFrameWatchdogTimeout, accuracy: 1e-9)
    }

    func testFirstFrameWatchdogWindowIsSizedForTheStage() {
        // 1.5 s: enough for a cold decoder spin-up, short enough that
        // the fallback lands with the Kurzfassung still ahead of it.
        XCTAssertEqual(CinematicScript.firstFrameWatchdogTimeout, 1.5)
        for spec in CinematicScript.chapters where spec.video != nil {
            XCTAssertLessThan(CinematicScript.firstFrameWatchdogTimeout,
                              spec.renderedDuration(video: false),
                              "\(spec.chapter): the watchdog must break INTO a "
                              + "Kurzfassung that still has time to play")
        }
    }

    // MARK: The foreground re-kick — resume, never restart

    func testForegroundResumeOnlyKicksAStandingPlayableRun() {
        // Sideload-Realität: backgrounding pauses the player; the
        // re-kick fires ONLY on a living run, a standing player and a
        // playable item.
        XCTAssertTrue(CinematicScript.shouldResumeVideoAfterForeground(
            runAlive: true, rate: 0, itemReady: true))
        XCTAssertFalse(CinematicScript.shouldResumeVideoAfterForeground(
            runAlive: true, rate: 1, itemReady: true),
            "an already-playing run gets no second kick")
        XCTAssertFalse(CinematicScript.shouldResumeVideoAfterForeground(
            runAlive: false, rate: 0, itemReady: true),
            "a stopped or finished run never resumes")
        XCTAssertFalse(CinematicScript.shouldResumeVideoAfterForeground(
            runAlive: true, rate: 0, itemReady: false),
            "a dead item is the broken-run fallback's case, not a play() loop")
    }

    // MARK: Freeze parametrization — the CI frame series knob

    func testFreezeTimeParsesTheLaunchEnvironment() {
        XCTAssertEqual(CinematicScript.freezeTime(argument: false, environment: "12"),
                       12)
        XCTAssertEqual(CinematicScript.freezeTime(argument: false, environment: "2.5"),
                       2.5)
        // The environment wins over the classic flag.
        XCTAssertEqual(CinematicScript.freezeTime(argument: true, environment: "20"),
                       20)
    }

    func testFreezeTimeClampsIntoTheTimeline() {
        XCTAssertEqual(CinematicScript.freezeTime(argument: false, environment: "-3"),
                       0, "a playhead before the cinema clamps to its start")
        guard let overshoot = CinematicScript.freezeTime(argument: false,
                                                         environment: "999") else {
            return XCTFail("overshoot must still freeze")
        }
        XCTAssertLessThan(overshoot, CinematicScript.chapterTotalDuration)
        XCTAssertNotNil(CinematicScript.chapter(at: overshoot),
                        "the clamped playhead still lands INSIDE a chapter — an "
                        + "empty stage never ships")
    }

    func testFreezeTimeFallsBackToTheFlagOnGarbageAndAbsence() {
        XCTAssertEqual(CinematicScript.freezeTime(argument: true, environment: "kaputt"),
                       CinematicScript.screenshotFreezeTime)
        XCTAssertEqual(CinematicScript.freezeTime(argument: true, environment: nil),
                       CinematicScript.screenshotFreezeTime)
        XCTAssertNil(CinematicScript.freezeTime(argument: false, environment: nil))
        XCTAssertNil(CinematicScript.freezeTime(argument: false, environment: ""))
    }

    // MARK: The frozen stage mapping — every chapter type freezes cleanly

    func testFrozenStageEntryIsAlwaysProceduralAcrossTheWholeTimeline() {
        // Sweep the full cut in small steps: EVERY freeze renders the
        // procedural stage — video chapters as their Kurzfassung still
        // (the screenshot simulator ships no videos by design).
        var t = 0.0
        while t < CinematicScript.chapterTotalDuration {
            guard let frozen = CinematicScript.frozenStageEntry(at: t) else {
                XCTFail("no frozen stage at \(t) s despite being inside the cut")
                return
            }
            XCTAssertEqual(frozen.entry.render, .procedural,
                           "freeze at \(t) s depends on a video")
            XCTAssertGreaterThanOrEqual(frozen.local, 0)
            XCTAssertLessThan(frozen.local, frozen.entry.spec.duration)
            t += 0.5
        }
        XCTAssertNil(CinematicScript.frozenStageEntry(at: -0.01))
        XCTAssertNil(CinematicScript.frozenStageEntry(
            at: CinematicScript.chapterTotalDuration))
    }

    func testFrozenStageLocalClockIsChapterRelative() {
        guard let frozen = CinematicScript.frozenStageEntry(at: 9) else {
            return XCTFail("9 s lies inside the envelope chapter")
        }
        XCTAssertEqual(frozen.entry.spec.chapter, .umschlag)
        XCTAssertEqual(frozen.local, 1, accuracy: 1e-9,
                       "chapter 2 starts at 8 s — the stage clock is local")
    }

    func testFrameSeriesMapsToItsIntendedChapters() {
        // t=2 gate, 9 + 12 the envelope video's Kurzfassung (slide, then
        // stamped postmark), 20 the seal break, 30 the waiting ink
        // choice, 41 the embossed wax seal, 50 the polaroid, 57 arrival.
        let expected: [CinematicChapter] = [
            .lampenklick, .umschlag, .umschlag, .siegelbruch,
            .tinten, .wachssiegel, .polaroid, .ankunft,
        ]
        XCTAssertEqual(CinematicScript.screenshotFrameSeries.count, expected.count)
        for (t, chapter) in zip(CinematicScript.screenshotFrameSeries, expected) {
            XCTAssertEqual(CinematicScript.frozenStageEntry(at: t)?.entry.spec.chapter,
                           chapter, "series time \(t) s froze the wrong chapter")
        }
    }

    func testFrameSeriesCoversEveryChapterType() {
        let frozen = Set(CinematicScript.screenshotFrameSeries.compactMap {
            CinematicScript.frozenStageEntry(at: $0)?.entry.spec.chapter
        })
        XCTAssertEqual(frozen, Set(CinematicChapter.allCases),
                       "the CI series must show every chapter of the cinema")
    }

    func testFrameSeriesShowsTheEnvelopeBeforeAndAfterItsPostmark() {
        // The two envelope frames bracket the Kurzfassung's stamp beat
        // (3.6 s local): one slide-in frame, one stamped frame — the
        // series proves motion, not just presence.
        guard let stamp = CinematicScript.spec(for: .umschlag)?.hapticBeats.last?.t
        else { return XCTFail("the envelope lost its stamp beat") }
        let locals = CinematicScript.screenshotFrameSeries.compactMap {
            time -> Double? in
            guard let frozen = CinematicScript.frozenStageEntry(at: time),
                  frozen.entry.spec.chapter == .umschlag else { return nil }
            return frozen.local
        }
        XCTAssertEqual(locals.count, 2)
        XCTAssertLessThan(locals[0], stamp, "first envelope frame: mid-slide")
        XCTAssertGreaterThan(locals[1], stamp, "second envelope frame: stamped")
    }

    func testClassicScreenshotFreezeStillWorksThroughTheSharedRule() {
        // The flag path is untouched: 43 s → wax-seal act, procedural.
        guard let time = CinematicScript.freezeTime(argument: true, environment: nil),
              let frozen = CinematicScript.frozenStageEntry(at: time) else {
            return XCTFail("the classic freeze must resolve")
        }
        XCTAssertEqual(frozen.entry.spec.chapter, .wachssiegel)
        XCTAssertEqual(frozen.entry.render, .procedural)
    }
}
