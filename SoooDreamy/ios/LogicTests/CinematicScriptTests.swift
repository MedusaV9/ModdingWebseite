import XCTest
@testable import SoooDreamyLogic

/// Timing and plan invariants of the first-launch cinema (FullRelease
/// N3-Kino). The script is the single source of truth the chapter player
/// performs — these tests pin the chapter order, both render paths (the
/// full video cut AND the Lite Kurzfassung) inside the 45–60 s window,
/// the pure fallback rule, the merge anchor and the caption contract.
final class CinematicScriptTests: XCTestCase {

    /// The three CI-rendered look-scenes as they exist in a FULL bundle
    /// (flat basenames — verified in CI run 31878649119).
    private let allVideos: Set<String> = [
        "scene2_envelope", "scene3_seal", "scene6_polaroid",
    ]

    // MARK: Timeline shape

    func testChapterOrderMatchesTheDramaturgy() {
        XCTAssertEqual(CinematicScript.chapters.map(\.chapter),
                       [.lampenklick, .umschlag, .siegelbruch, .tinten,
                        .wachssiegel, .polaroid, .ankunft])
        XCTAssertEqual(Set(CinematicScript.chapters.map(\.chapter)).count,
                       CinematicChapter.allCases.count,
                       "every chapter appears exactly once")
    }

    func testTimelineIsGaplessOrderedAndStartsAtZero() {
        XCTAssertEqual(CinematicScript.chapterStart(.lampenklick), 0)
        var expectedStart = 0.0
        for spec in CinematicScript.chapters {
            XCTAssertGreaterThan(spec.duration, 0, "\(spec.chapter) has no duration")
            XCTAssertEqual(CinematicScript.chapterStart(spec.chapter), expectedStart,
                           accuracy: 1e-9,
                           "gap or overlap before \(spec.chapter)")
            expectedStart += spec.duration
        }
        XCTAssertEqual(CinematicScript.chapterTotalDuration, expectedStart,
                       accuracy: 1e-9)
    }

    func testFullCutSitsInsideTheOwnersWindow() {
        XCTAssertTrue(
            CinematicScript.durationWindow.contains(CinematicScript.chapterTotalDuration),
            "full cut \(CinematicScript.chapterTotalDuration) s outside 45–60 s")
    }

    // MARK: The plan rule — missing videos are legal, never black

    func testFullPlanUsesTheThreeVideos() {
        let plan = CinematicScript.chapterPlan(availableVideos: allVideos,
                                               languageChosen: false)
        XCTAssertEqual(plan.count, CinematicChapter.allCases.count)
        let videoChapters = plan.filter { $0.render.isVideo }.map(\.spec.chapter)
        XCTAssertEqual(videoChapters, [.umschlag, .siegelbruch, .polaroid])
        XCTAssertTrue(
            CinematicScript.durationWindow.contains(
                CinematicScript.plannedTotalDuration(plan)),
            "full plan outside the window")
    }

    func testLitePlanFallsBackEverywhereAndStaysInsideTheWindow() {
        // The Lite IPA ships NO videos — the cinema plays the stage
        // version of the same story, never a black frame.
        let plan = CinematicScript.chapterPlan(availableVideos: [],
                                               languageChosen: false)
        XCTAssertEqual(plan.count, CinematicChapter.allCases.count)
        XCTAssertTrue(plan.allSatisfy { !$0.render.isVideo })
        let total = CinematicScript.plannedTotalDuration(plan)
        XCTAssertTrue(CinematicScript.durationWindow.contains(total),
                      "Lite Kurzfassung \(total) s outside 45–60 s")
        XCTAssertLessThan(total, CinematicScript.chapterTotalDuration,
                          "the Kurzfassung is the shorter cut by design")
    }

    func testPartialBundleDowngradesOnlyTheMissingChapters() {
        // A corrupt bundle may ship SOME videos — each chapter decides
        // alone; one missing file never drags the others down.
        let plan = CinematicScript.chapterPlan(availableVideos: ["scene3_seal"],
                                               languageChosen: false)
        for entry in plan {
            let expectVideo = entry.spec.chapter == .siegelbruch
            XCTAssertEqual(entry.render.isVideo, expectVideo,
                           "\(entry.spec.chapter) took the wrong render path")
        }
    }

    func testLanguageGateLeavesThePlanOnceChosen() {
        // Replay / demo entry after the first launch: the choice is made,
        // the gate is function — it never plays as film again.
        let plan = CinematicScript.chapterPlan(availableVideos: allVideos,
                                               languageChosen: true)
        XCTAssertEqual(plan.count, CinematicChapter.allCases.count - 1)
        XCTAssertFalse(plan.contains { $0.spec.chapter == .lampenklick })
        XCTAssertEqual(plan.first?.spec.chapter, .umschlag)
    }

    func testVideoChaptersCarryAFallbackAndAManifest() {
        for spec in CinematicScript.chapters {
            guard let video = spec.video else { continue }
            XCTAssertTrue(allVideos.contains(video.videoResource),
                          "\(spec.chapter) references an unknown video")
            XCTAssertFalse(video.manifestResource.isEmpty)
            XCTAssertFalse(spec.interactive,
                           "video chapters are Kino — nothing to wait for")
            guard let fallback = spec.fallbackDuration else {
                return XCTFail("\(spec.chapter) has no Kurzfassung length")
            }
            XCTAssertGreaterThan(fallback, 0)
            XCTAssertLessThan(fallback, spec.duration,
                              "the Kurzfassung is the shorter cut")
            XCTAssertEqual(spec.renderedDuration(video: true), spec.duration)
            XCTAssertEqual(spec.renderedDuration(video: false), fallback)
        }
    }

    func testInteractiveChaptersAreTheLanguageAndInkChoice() {
        let interactive = CinematicScript.chapters
            .filter(\.interactive).map(\.chapter)
        XCTAssertEqual(interactive, [.lampenklick, .tinten],
                       "exactly the two choices wait for the person")
    }

    // MARK: Wallclock honesty — the FASTEST path stays inside the window
    // (Kino-Final-Eval: summing nominal durations hid that instant
    // choices undercut the 45 s floor on the Lite path)

    func testMinimumDwellsExistExactlyOnTheInteractiveChapters() {
        for spec in CinematicScript.chapters {
            if spec.interactive {
                guard let dwell = spec.minDwell else {
                    XCTFail("\(spec.chapter) waits for the person but has no minimum dwell")
                    continue
                }
                XCTAssertGreaterThan(dwell, 0)
                XCTAssertLessThanOrEqual(dwell, spec.duration,
                    "\(spec.chapter): the dwell floor must not exceed the nominal length")
            } else {
                XCTAssertNil(spec.minDwell,
                    "\(spec.chapter) is timed — its dwell IS the rendered duration")
            }
        }
    }

    func testDwellGatesNeverTruncateTheRunningChoreography() {
        // The gate holds the ADVANCE, never the arc: the lift beat and
        // the full post-pick ink choreography must fit inside their
        // chapters' dwell floors, so an instant choice still plays out.
        XCTAssertLessThanOrEqual(CinematicScript.languageLiftDuration,
                                 CinematicScript.spec(for: .lampenklick)?.minDwell ?? 0)
        XCTAssertEqual(CinematicScript.inkPickChoreography,
                       CinematicScript.inkPickLead
                           + CinematicScript.inkApproachDuration
                           + CinematicScript.inkSettleTail,
                       accuracy: 1e-9)
        XCTAssertLessThanOrEqual(CinematicScript.inkPickChoreography,
                                 CinematicScript.spec(for: .tinten)?.minDwell ?? 0,
                                 "an instant ink pick would truncate the blend")
    }

    func testFastestFirstLaunchWallclockStaysInsideTheWindowOnBothPaths() {
        // Fastest honest path: every choice lands instantly, interactive
        // chapters still hold their dwell floor. Full cut AND Lite
        // Kurzfassung must stay ≥ 45 s — the cinema is a minute, not a
        // sprint (and ≤ 60 s — never an overstay either).
        let fullFast = CinematicScript.fastestWallclockDuration(
            CinematicScript.chapterPlan(availableVideos: allVideos,
                                        languageChosen: false))
        let liteFast = CinematicScript.fastestWallclockDuration(
            CinematicScript.chapterPlan(availableVideos: [],
                                        languageChosen: false))
        XCTAssertTrue(CinematicScript.durationWindow.contains(fullFast),
                      "fastest full path \(fullFast) s outside 45–60 s")
        XCTAssertTrue(CinematicScript.durationWindow.contains(liteFast),
                      "fastest Lite path \(liteFast) s outside 45–60 s")
    }

    func testNominalWallclockStaysInsideTheWindowOnBothPaths() {
        // The slow bound of the scheduled cinema (nobody hesitates past
        // the nominal chapter lengths): min and max TOGETHER pin the
        // honest wallclock window per render path.
        for videos in [allVideos, []] {
            let plan = CinematicScript.chapterPlan(availableVideos: videos,
                                                   languageChosen: false)
            let fastest = CinematicScript.fastestWallclockDuration(plan)
            let nominal = CinematicScript.plannedTotalDuration(plan)
            XCTAssertLessThanOrEqual(fastest, nominal,
                                     "the fast path can never outlast the nominal cut")
            XCTAssertTrue(CinematicScript.durationWindow.contains(nominal),
                          "nominal \(nominal) s outside the window")
        }
    }

    func testReplayPlansStayUnderTheWindowCeiling() {
        // Replay / demo entry drops the language gate: shorter than a
        // first launch is fine (the story is known), longer never.
        for videos in [allVideos, []] {
            let plan = CinematicScript.chapterPlan(availableVideos: videos,
                                                   languageChosen: true)
            XCTAssertLessThanOrEqual(
                CinematicScript.plannedTotalDuration(plan),
                CinematicScript.durationWindow.upperBound)
            XCTAssertLessThanOrEqual(
                CinematicScript.fastestWallclockDuration(plan),
                CinematicScript.durationWindow.upperBound)
        }
    }

    func testVideoRunGroupsConsecutiveVideoChapters() {
        // Scenes 2+3 share ONE AVQueuePlayer so scene 3 begins seamlessly
        // on scene 2's end frame; the polaroid stands alone.
        let plan = CinematicScript.chapterPlan(availableVideos: allVideos,
                                               languageChosen: false)
        guard let umschlagIndex = plan.firstIndex(where: { $0.spec.chapter == .umschlag }),
              let polaroidIndex = plan.firstIndex(where: { $0.spec.chapter == .polaroid })
        else { return XCTFail("plan lost its video chapters") }
        XCTAssertEqual(
            CinematicScript.videoRun(in: plan, from: umschlagIndex).map(\.spec.chapter),
            [.umschlag, .siegelbruch])
        XCTAssertEqual(
            CinematicScript.videoRun(in: plan, from: polaroidIndex).map(\.spec.chapter),
            [.polaroid])
        // A procedural index (or nonsense) yields no run.
        XCTAssertTrue(CinematicScript.videoRun(in: plan, from: 0).isEmpty)
        XCTAssertTrue(CinematicScript.videoRun(in: plan, from: 99).isEmpty)
    }

    // MARK: Beats stay inside their chapter — on BOTH render paths

    func testEveryProceduralBeatEndsInsideItsRenderedChapter() {
        for spec in CinematicScript.chapters {
            // Procedural beats play on the Kurzfassung clock when the
            // video is missing — they must fit the SHORTER duration.
            let rendered = spec.renderedDuration(video: false)
            for beat in spec.hapticBeats {
                XCTAssertGreaterThanOrEqual(beat.t, 0,
                    "\(spec.chapter): beat before chapter start")
                XCTAssertLessThanOrEqual(beat.t + beat.d, rendered,
                    "\(spec.chapter): beat at \(beat.t)+\(beat.d) spills past the Kurzfassung")
                XCTAssertTrue((0...1).contains(beat.i), "\(spec.chapter): intensity out of range")
                XCTAssertTrue((0...1).contains(beat.s), "\(spec.chapter): sharpness out of range")
            }
        }
    }

    func testSoundOffsetsStayInsideBothRenderPaths() {
        for spec in CinematicScript.chapters where spec.soundCue != nil {
            XCTAssertGreaterThanOrEqual(spec.soundOffset, 0)
            XCTAssertLessThan(spec.soundOffset, spec.renderedDuration(video: false),
                              "\(spec.chapter): cue after the Kurzfassung ended")
        }
    }

    func testAbsoluteBeatTimesLandInsideTheirChapter() {
        for spec in CinematicScript.chapters {
            let start = CinematicScript.chapterStart(spec.chapter)
            for time in CinematicScript.absoluteBeatTimes(in: spec.chapter) {
                XCTAssertGreaterThanOrEqual(time, start)
                XCTAssertLessThan(time, start + spec.duration)
            }
        }
    }

    // MARK: The merge — chapter 5's anchor

    func testMergeAnchorsTheWaxSealChapter() {
        // Nominal timeline: 8 + 8 + 10 + 12 = 38 s chapter start, the
        // emboss beat 1.1 s in — THE moment of the cinema at 39.1 s.
        XCTAssertEqual(CinematicScript.chapterStart(.wachssiegel), 38.0, accuracy: 1e-9)
        XCTAssertEqual(CinematicScript.mergeTime, 39.1, accuracy: 1e-9)
        // The strong beat and the cue share ONE clock moment.
        let seal = CinematicScript.spec(for: .wachssiegel)
        XCTAssertEqual(seal?.soundOffset ?? -1, CinematicScript.mergeBeatOffset,
                       accuracy: 1e-9)
    }

    func testSealReusesThePairingCeremonyMotif() {
        // Recognition contract: the cinema's climax is the SAME cue the
        // pairing ceremony plays on the real pairing day — and it is the
        // ONLY key-moment cue of the whole cinema.
        XCTAssertEqual(CinematicScript.spec(for: .wachssiegel)?.soundCue, .pairing)
        let keyMoments = CinematicScript.chapters
            .compactMap(\.soundCue).filter(\.isKeyMoment)
        XCTAssertEqual(keyMoments, [.pairing])
    }

    func testAtMostOneCuePerChapter() {
        // One-channel discipline on the procedural path: the spec CAN
        // only carry one cue — pinned so the model never grows a list.
        for spec in CinematicScript.chapters {
            _ = spec.soundCue // one optional by construction
        }
        // …and the ringing chapters are exactly the four staged moments.
        let ringing = CinematicScript.chapters.filter { $0.soundCue != nil }
        XCTAssertEqual(ringing.map(\.chapter),
                       [.umschlag, .siegelbruch, .wachssiegel, .polaroid])
    }

    // MARK: Sound bed layers (aurora pad, orb tones, merge bloom)

    func testSoundLayersAnchorToChaptersAndStayInside() {
        XCTAssertFalse(CinematicScript.soundLayers.isEmpty)
        for layer in CinematicScript.soundLayers {
            XCTAssertGreaterThanOrEqual(layer.offset, 0)
            XCTAssertGreaterThan(layer.duration, 0)
            XCTAssertGreaterThanOrEqual(layer.nominalStart, 0)
            XCTAssertLessThanOrEqual(layer.nominalEnd,
                                     CinematicScript.chapterTotalDuration + 1e-9,
                                     "\(layer.voice) spills past the cinema")
        }
        // Every voice appears exactly once — no double beds.
        XCTAssertEqual(Set(CinematicScript.soundLayers.map(\.voice)).count,
                       CinematicScript.soundLayers.count)
    }

    func testAuroraBedRisesWithTheInkChapter() {
        guard let bed = CinematicScript.soundLayers.first(where: { $0.voice == .auroraBed })
        else { return XCTFail("aurora bed missing") }
        XCTAssertEqual(bed.chapter, .tinten, "the pad rises with the ink choice")
        XCTAssertEqual(bed.offset, 0, accuracy: 1e-9)
    }

    func testOrbTonesResolveExactlyIntoTheBlend() {
        guard let orbs = CinematicScript.soundLayers.first(where: { $0.voice == .orbTones })
        else { return XCTFail("orb tones missing") }
        XCTAssertEqual(orbs.chapter, .tinten)
        XCTAssertEqual(orbs.duration, CinematicScript.inkApproachDuration, accuracy: 1e-9)
        XCTAssertEqual(orbs.nominalEnd, CinematicScript.chapterStart(.wachssiegel),
                       accuracy: 1e-9,
                       "the tones resolve exactly INTO the pour")
    }

    func testMergeBloomSitsExactlyOnTheMergeBeat() {
        guard let bloom = CinematicScript.soundLayers.first(where: { $0.voice == .mergeBloom })
        else { return XCTFail("merge bloom missing") }
        XCTAssertEqual(bloom.nominalStart, CinematicScript.mergeTime, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(bloom.duration, CinematicScript.mergeShimmerDuration,
                                    "the bloom must carry its 1.5 s shimmer")
    }

    func testOnlyTheMergeCarriesANonBedVoice() {
        for layer in CinematicScript.soundLayers where !layer.voice.isBed {
            XCTAssertEqual(layer.voice, .mergeBloom)
            XCTAssertEqual(layer.nominalStart, CinematicScript.mergeTime, accuracy: 1e-9)
        }
    }

    // MARK: Playhead queries

    func testChapterAtHonorsInclusiveStartAndExclusiveEnd() {
        XCTAssertNil(CinematicScript.chapter(at: -0.01))
        XCTAssertNil(CinematicScript.chapter(at: CinematicScript.chapterTotalDuration))
        XCTAssertEqual(CinematicScript.chapter(at: 0)?.chapter, .lampenklick)
        for spec in CinematicScript.chapters {
            let start = CinematicScript.chapterStart(spec.chapter)
            XCTAssertEqual(CinematicScript.chapter(at: start)?.chapter, spec.chapter)
            XCTAssertEqual(CinematicScript.chapter(at: start + spec.duration - 0.001)?.chapter,
                           spec.chapter)
        }
    }

    func testProgressIsClampedAndLinearInsideTheChapter() {
        for spec in CinematicScript.chapters {
            let start = CinematicScript.chapterStart(spec.chapter)
            let end = start + spec.duration
            XCTAssertEqual(CinematicScript.progress(in: spec.chapter, at: start), 0)
            XCTAssertEqual(CinematicScript.progress(in: spec.chapter, at: end), 1)
            XCTAssertEqual(CinematicScript.progress(in: spec.chapter,
                                                    at: start + spec.duration / 2),
                           0.5, accuracy: 1e-9)
            XCTAssertEqual(CinematicScript.progress(in: spec.chapter, at: start - 5), 0)
            XCTAssertEqual(CinematicScript.progress(in: spec.chapter, at: end + 5), 1)
        }
    }

    // MARK: Skip — the language gate is function, not film

    func testSkipRulesProtectTheLanguageGate() {
        XCTAssertFalse(CinematicScript.skippable(.lampenklick),
                       "the language choice can never be skipped")
        for chapter in CinematicChapter.allCases where chapter != .lampenklick {
            XCTAssertTrue(CinematicScript.skippable(chapter))
        }
    }

    // MARK: Captions — every chapter speaks DE and EN

    func testEveryChapterCaptionResolvesInBothLanguages() {
        for chapter in CinematicChapter.allCases {
            let key = CinematicScript.captionKey(for: chapter)
            guard let text = OnboardingL10n.table[key] else {
                return XCTFail("caption key \(key) missing from OnboardingL10n")
            }
            XCTAssertFalse(text.de.isEmpty, "\(key): empty German caption")
            XCTAssertFalse(text.en.isEmpty, "\(key): empty English caption")
        }
        // The caption fade-in fits even the shortest Kurzfassung.
        let shortest = CinematicScript.chapters
            .map { $0.renderedDuration(video: false) }.min() ?? 0
        XCTAssertLessThan(CinematicScript.captionDelay, shortest)
    }

    func testNoPlanEverCarriesABlankCaption() {
        // Leere-Pillen-Bugklasse (Geräte-Screenshot): the caption pill
        // is a paper Zettel FOR its words — a caption resolving to ""
        // or pure whitespace would stand as a visibly empty pill on the
        // night room. Pinned across every plan the rule can produce and
        // both languages; the view guard is only the second lock.
        let blank = CharacterSet.whitespacesAndNewlines
        for videos in [allVideos, []] {
            for chosen in [false, true] {
                let plan = CinematicScript.chapterPlan(availableVideos: videos,
                                                       languageChosen: chosen)
                for entry in plan {
                    let key = CinematicScript.captionKey(for: entry.spec.chapter)
                    guard let text = OnboardingL10n.table[key] else {
                        XCTFail("caption key \(key) missing from OnboardingL10n")
                        continue
                    }
                    XCTAssertFalse(
                        text.de.trimmingCharacters(in: blank).isEmpty,
                        "\(key): blank German caption would render an empty pill")
                    XCTAssertFalse(
                        text.en.trimmingCharacters(in: blank).isEmpty,
                        "\(key): blank English caption would render an empty pill")
                }
            }
        }
    }

    // MARK: Ink wells — spoken color names (Re-Eval Runde 2, A11y)

    func testEveryInkWellSpeaksItsColorName() {
        // The eight wells render CouplePaletteRules.memberColorHexes —
        // every hex must own a real name key that resolves DE+EN
        // („Tintenfass Rosa, 1 von 8", never eight silent circles).
        for hex in CouplePaletteRules.memberColorHexes {
            let key = CinematicScript.inkWellNameKey(hex: hex)
            XCTAssertNotEqual(key, "pairing.color",
                              "\(hex): the generic fallback is no color name")
            guard let text = CoreStrings.table[key] else {
                XCTFail("name key \(key) missing from CoreStrings")
                continue
            }
            XCTAssertFalse(text.de.isEmpty, "\(key): empty German name")
            XCTAssertFalse(text.en.isEmpty, "\(key): empty English name")
        }
        // The table covers the palette EXACTLY — no orphans, no drift
        // against MemberColorPicker's private twin.
        XCTAssertEqual(Set(CinematicScript.inkWellNameKeys.keys),
                       Set(CouplePaletteRules.memberColorHexes))
        // An unknown ink still speaks: the generic label, never silence.
        XCTAssertEqual(CinematicScript.inkWellNameKey(hex: "000000"),
                       "pairing.color")
        // The spoken template carries the {name} slot in both languages.
        let label = OnboardingL10n.table["cinematic.ink.wellA11y"]
        XCTAssertTrue(label?.de.contains("{name}") == true,
                      "DE well label lost its {name} slot")
        XCTAssertTrue(label?.en.contains("{name}") == true,
                      "EN well label lost its {name} slot")
    }

    // MARK: Reduce Motion variant

    func testReducedVariantIsCalmStills() {
        XCTAssertEqual(CinematicScript.reducedStillDuration, 3.5, accuracy: 0.5)
        XCTAssertLessThan(CinematicScript.crossfadeDuration,
                          CinematicScript.reducedStillDuration,
                          "crossfades stay shorter than the stills they connect")
        let timedChapters = CinematicScript.chapters.filter { !$0.interactive }
        XCTAssertEqual(CinematicScript.reducedTimedDuration,
                       Double(timedChapters.count) * CinematicScript.reducedStillDuration,
                       accuracy: 1e-9)
        XCTAssertTrue((0...1).contains(CinematicScript.reducedStillBeat.i))
        XCTAssertTrue((0...1).contains(CinematicScript.reducedStillBeat.s))
    }

    // MARK: CI screenshot freeze

    func testScreenshotFreezeLandsInAProceduralChapter() {
        guard let frozen = CinematicScript.chapter(at: CinematicScript.screenshotFreezeTime)
        else { return XCTFail("freeze time outside the timeline") }
        XCTAssertEqual(frozen.chapter, .wachssiegel)
        // The screenshot simulator builds WITHOUT videos — the frozen
        // chapter must never depend on one.
        XCTAssertNil(frozen.video)
        // The heart is embossed: the freeze lies after the last seal beat.
        let lastBeat = CinematicScript.absoluteBeatTimes(in: .wachssiegel).max() ?? 0
        XCTAssertGreaterThan(CinematicScript.screenshotFreezeTime, lastBeat)
    }

    func testFrozenChoiceSeedsLandOnTheirChapters() {
        // Re-Eval Runde 2: the seeded t30 ink frame must show a RUNNING
        // trace. Post-pick clock p = local − offset lies past the fully
        // drawn stroke (inkPickLead) yet inside the approach window —
        // never a settled blend, never a bare palette.
        let local = 30.0 - CinematicScript.chapterStart(.tinten)
        let p = local - CinematicScript.screenshotInkPickOffset
        XCTAssertGreaterThan(p, CinematicScript.inkPickLead,
                             "the seeded frame must show the stroke fully drawn")
        XCTAssertLessThan(p, CinematicScript.inkPickLead
                             + CinematicScript.inkApproachDuration,
                          "the approach must still be running in the seeded frame")
        // …and both seeded playheads really land on their chapters.
        XCTAssertTrue(CinematicScript.screenshotFrameSeries.contains(30))
        XCTAssertEqual(CinematicScript.chapter(at: 30)?.chapter, .tinten)
        XCTAssertTrue(CinematicScript.screenshotFrameSeries.contains(2))
        XCTAssertEqual(CinematicScript.chapter(at: 2)?.chapter, .lampenklick)
    }
}
