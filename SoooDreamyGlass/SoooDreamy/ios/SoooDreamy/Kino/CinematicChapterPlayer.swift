import SwiftUI
import AVFoundation
import Combine

// FullRelease N3-Kino — the VIDEO half of the chapter player. Three
// CI-rendered look-scenes (scene 2/3/6) ship as muted HEVC clips, flat in
// the bundle next to their haptics manifests. This file owns:
//   * CinematicVideoLibrary — bundle probing (what can actually PLAY),
//   * CinematicVideoRunController — one AVQueuePlayer per run of
//     CONSECUTIVE video chapters, so scene 3 begins seamlessly on scene
//     2's end frame (the renders hold matching frames by design),
//   * beat/cue firing via AVPlayer.addBoundaryTimeObserver on the player
//     clock (correct across pause/seek/skip — RECON §3.6),
//   * the Reduce-Motion poster still (AVAssetImageGenerator at the
//     manifest's posterTime — zero extra assets).
//
// Sound policy (RECON §3.5): the videos are MUTED; every cue rings
// through the existing SoundEngine, whose session is `.ambient` with
// mix-with-others — the silent switch and the couple's music stay
// respected, and quiet hours keep working. The cinema gets no audio
// side-world of its own.

/// Bundle probing for the chapter videos. A video counts as available
/// only when the MP4 exists AND its manifest decodes and validates —
/// a broken manifest downgrades the chapter to its procedural
/// Kurzfassung exactly like a missing file (fail-soft, never black).
enum CinematicVideoLibrary {
    static func videoURL(for basename: String) -> URL? {
        Bundle.main.url(forResource: basename, withExtension: "mp4")
    }

    /// Decoded + validated manifest, or nil (which means: procedural).
    static func manifest(named resource: String) -> CinematicManifest? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? CinematicManifest.decode(data),
              manifest.isValid
        else { return nil }
        return manifest
    }

    /// The basenames `CinematicScript.chapterPlan` gets to plan with.
    /// The Lite IPA ships none (legal state); a corrupt bundle may ship
    /// some — each chapter decides alone.
    static func availableVideos() -> Set<String> {
        var available: Set<String> = []
        for spec in CinematicScript.chapters {
            guard let video = spec.video,
                  videoURL(for: video.videoResource) != nil,
                  manifest(named: video.manifestResource) != nil
            else { continue }
            available.insert(video.videoResource)
        }
        return available
    }
}

/// Capture-time stamp of the first-frame watchdog's GENERATION plus the
/// armed ITEM's identity (Fix-Runde 3, Kino-Befund 1; Item-Provenienz
/// in Fix-Runde 4, S2): the layer host reads the generation inside the
/// KVO handler — possibly off-main, BEFORE the main-queue hop — and
/// captures the item it observes at that same instant, so a late
/// delivery still names the (generation, item) it actually SAW. The
/// generation alone was not enough: a re-arm racing the callback let
/// item 1's late report read generation 2 and pass the (2==2) gate. A
/// lock instead of actor isolation because the read must stay
/// synchronous at KVO time; the operations are a counter bump and
/// snapshots, nothing blocks.
final class CinematicWatchdogGenerations: @unchecked Sendable {
    /// One (generation, item) truth: the controller ARMS one, every
    /// readiness report CARRIES one — acceptance compares the two
    /// through `CinematicScript.firstFrameReportCounts`.
    struct Stamp: Equatable, Sendable {
        let generation: Int
        let item: ObjectIdentifier?
    }

    private let lock = NSLock()
    private var value = 0
    private var armedItem: ObjectIdentifier?

    /// Open the next generation FOR ONE ITEM (the controller's re-arm)
    /// — returns the new generation.
    @discardableResult
    func advance(item: ObjectIdentifier?) -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        armedItem = item
        return value
    }

    /// The armed truth every readiness report is judged against.
    var current: Stamp {
        lock.lock(); defer { lock.unlock() }
        return Stamp(generation: value, item: armedItem)
    }
}

/// Plays one run of CONSECUTIVE video chapters on a single AVQueuePlayer
/// (local bundle files decode without buffer pauses; an eventual one-frame
/// seam hides on the shared hold-frames). Beats and cues fire from the
/// manifest via a boundary observer on the PLAYER clock, re-registered
/// per item. The controller is deliberately dumb about the cinema: the
/// shell owns plan, captions and chrome — this class owns time.
@MainActor
final class CinematicVideoRunController {
    struct RunChapter {
        let entry: CinematicChapterPlanEntry
        let manifest: CinematicManifest
        let url: URL
    }

    let player = AVQueuePlayer()
    private(set) var chapters: [RunChapter] = []
    private(set) var currentIndex = 0

    private var items: [AVPlayerItem] = []
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var itemStatusObservations: [NSKeyValueObservation] = []
    private var currentItemObservation: NSKeyValueObservation?
    /// Grace task of the dry-queue verdict — a run-out queue is
    /// AMBIGUOUS for one beat (see `queueBecameDry`).
    private var dryQueueVerdict: Task<Void, Never>?
    /// First-frame watchdog (readyToPlay-ohne-Frame-Lücke): armed on
    /// play() and RE-ARMED per queue item (Re-Eval Runde 2 — scene 3
    /// after scene 2 used to run unguarded), disarmed by a REAL frame;
    /// expires via the pure verdict in `CinematicScript`.
    private var firstFrameWatchdog: Task<Void, Never>?
    /// Wallclock anchor of the armed watchdog — foreground honesty is
    /// computed against it at expiry.
    private var watchdogArmedAt = Date()
    /// Backgrounded wallclock accumulated since the watchdog was armed
    /// (iOS pauses the decoder there — that time proves nothing).
    private var watchdogBackgrounded: TimeInterval = 0
    /// Set while the scene is away; the foreground hand-off closes it.
    private var backgroundedAt: Date?
    /// The inner index the watchdog is armed on — the pure re-arm rule
    /// compares item identities, never timers.
    private var watchdogItemIndex: Int?
    /// Watchdog (GENERATION, ITEM) per queue item (Fix-Runde 3, Kino-
    /// Befund 1; Fix-Runde 4, S2): every re-arm opens a new generation
    /// FOR its item, readiness reports carry the pair they were
    /// captured under, and reports naming a stale generation OR a
    /// foreign item are dropped whole — item 1's late true can never
    /// disarm item 2, even when the race lets it read generation 2.
    let watchdogGenerations = CinematicWatchdogGenerations()
    /// Mirror of the stage layer's `isReadyForDisplay` FOR THE CURRENT
    /// (GENERATION, ITEM) arming (the shell forwards it from
    /// `CinematicVideoSurface`) — the truth "a frame of THIS item is
    /// really showing", which `.readyToPlay` alone never proves. Reset
    /// to false on every re-arm: a seam-held ready without a new edge
    /// proves nothing.
    private(set) var layerShowsFrame = false
    /// Inner indices whose item already reported `.failed` — the run
    /// breaks the moment it reaches (or stands on) one of them.
    private var failedIndices: Set<Int> = []
    private var stopped = false

    /// Inner run index became current (0-based) — the shell moves its
    /// plan cursor, caption and progress dots.
    var onChapterChange: ((Int) -> Void)?
    /// The whole run played (or was skipped) to its end.
    var onFinished: (() -> Void)?
    /// The VIDEO PATH of the run died at this inner index (hev1-Bugklasse:
    /// item `.failed`, failed-to-play-to-end, or a silently dry queue).
    /// The shell restages the rest of the run procedurally — the honest
    /// hand-over instead of an empty room under a running caption.
    var onRunBroken: ((Int) -> Void)?
    /// One manifest beat fires NOW (relativeTime already zeroed).
    var fireBeat: ((HapticEventSpec) -> Void)?
    /// One manifest cue rings NOW (quiet hours are the shell's call).
    var ringCue: ((AppCue) -> Void)?

    init(run: [CinematicChapterPlanEntry]) {
        // Loading may still fail between planning and playing (corrupt
        // bundle mid-flight). Only the LEADING loadable prefix plays —
        // dropping an INNER chapter would misalign the run's indices
        // against the plan cursor (wrong caption, a chapter silently
        // skipped). The pure rule owns that decision; the first broken
        // chapter falls back to its Kurzfassung when the shell reaches it.
        var loadable: Set<String> = []
        var probed: [String: (manifest: CinematicManifest, url: URL)] = [:]
        for entry in run {
            guard case .video(let video) = entry.render,
                  let url = CinematicVideoLibrary.videoURL(for: video.videoResource),
                  let manifest = CinematicVideoLibrary.manifest(named: video.manifestResource)
            else { continue }
            loadable.insert(video.videoResource)
            probed[video.videoResource] = (manifest, url)
        }
        for entry in CinematicScript.performableRun(run, loadable: loadable) {
            guard case .video(let video) = entry.render,
                  let loaded = probed[video.videoResource] else { break }
            chapters.append(RunChapter(entry: entry, manifest: loaded.manifest,
                                       url: loaded.url))
        }
    }

    /// True when nothing in the run could be loaded — the shell then
    /// falls through to the procedural path instead of a black stage.
    var isEmpty: Bool { chapters.isEmpty }

    /// First-frame underlay source of the chapter the run currently
    /// plays: the poster the stage holds under the player layer until it
    /// reports a real frame — at the seam this is the run's matching
    /// hold frame (scene 3 opens on scene 2's end frame by design).
    var currentPosterURL: URL? {
        chapters.indices.contains(currentIndex) ? chapters[currentIndex].url : nil
    }

    func start() {
        guard !chapters.isEmpty, !stopped else {
            onFinished?()
            return
        }
        // Rendered muted in CI; the SoundEngine is the one voice.
        player.isMuted = true
        player.actionAtItemEnd = .advance
        // Local bundle files never rebuffer — start on the first decoded
        // frame instead of letting the stalling heuristic hold a blank
        // layer (the poster underlay carries the stage until then).
        player.automaticallyWaitsToMinimizeStalling = false
        items = chapters.map { AVPlayerItem(url: $0.url) }
        for item in items {
            player.insert(item, after: nil)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            Task { @MainActor in
                self?.itemDidEnd(item)
            }
        }
        // hev1-Bugklasse (real-device screenshots): iPhone hardware
        // decoders refuse `hev1` sample entries and let the item die
        // WITHOUT a didPlayToEndTime — the probe above only proved the
        // file EXISTS, not that it plays. Three failure signals cover
        // the whole class (broken/undecodable/stalling video):
        //   * the item's status flips to `.failed` (KVO, per item),
        //   * failedToPlayToEndTime fires mid-item,
        //   * the queue runs dry although the run is not finished.
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            Task { @MainActor in
                self?.itemFailedToEnd(item)
            }
        }
        // Third kill signal (readyToPlay-ohne-Frame-Lücke): local bundle
        // files never legitimately stall (automaticallyWaits… is off) —
        // a playbackStalled mid-run IS the broken-decoder class wearing
        // another coat, and waiting it out would strand an empty stage.
        stalledObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let item = note.object as? AVPlayerItem
            Task { @MainActor in
                self?.itemStalled(item)
            }
        }
        for (index, item) in items.enumerated() {
            itemStatusObservations.append(item.observe(
                \.status, options: [.initial, .new]
            ) { [weak self] item, _ in
                guard item.status == .failed else { return }
                Task { @MainActor in
                    self?.itemFailed(at: index)
                }
            })
        }
        currentItemObservation = player.observe(
            \.currentItem, options: [.new]
        ) { [weak self] player, _ in
            let dry = player.currentItem == nil
            Task { @MainActor in
                if dry { self?.queueBecameDry() } else { self?.queueRefilled() }
            }
        }
        installBoundaryObserver()
        player.play()
        rearmFirstFrameWatchdog(for: 0)
        onChapterChange?(0)
    }

    /// The stage layer's `isReadyForDisplay` changed (the shell forwards
    /// it, stamped with the (generation, item) the layer host captured
    /// it under — the parameter keeps its `generation:` label because
    /// the shell's wiring passes the stamp through under that name).
    /// The pure rules judge (Fix-Runde 4, S2): a report naming a stale
    /// generation OR a foreign item is dropped whole — the proven
    /// re-arm-before-callback race stamps the NEW generation but still
    /// the OLD item, so item 1's late true never disarms item 2 — and
    /// only the false→true EDGE of the current arming disarms; from
    /// then on the other death signals own the run.
    func layerReadinessChanged(_ ready: Bool,
                               generation stamp: CinematicWatchdogGenerations.Stamp) {
        let armed = watchdogGenerations.current
        guard CinematicScript.firstFrameReportCounts(
            reportedGeneration: stamp.generation,
            armedGeneration: armed.generation,
            reportedItem: stamp.item,
            armedItem: armed.item) else { return }
        let disarms = CinematicScript.firstFrameEdgeDisarms(
            alreadyShown: layerShowsFrame, reported: ready)
        layerShowsFrame = ready
        if disarms {
            firstFrameWatchdog?.cancel()
            firstFrameWatchdog = nil
        }
    }

    /// Sideload-Realität (AltStore refresh mid-cinema): backgrounding
    /// pauses the queue player, and nothing restarts it by itself. On
    /// scenePhase→active the shell calls this — the pure rule resumes
    /// ONLY a living run with a standing, playable item: never a
    /// restart, never a kick on a dead player (the broken-run fallback
    /// owns those). The hand-off also CLOSES the backgrounded span, so
    /// the first-frame watchdog counts foreground time only (Re-Eval
    /// Runde 2: a >1.5 s refresh away must not expire the dog).
    func resumeAfterForeground() {
        if let backgroundedAt {
            watchdogBackgrounded += Date().timeIntervalSince(backgroundedAt)
            self.backgroundedAt = nil
        }
        guard CinematicScript.shouldResumeVideoAfterForeground(
            runAlive: !stopped,
            rate: Double(player.rate),
            itemReady: player.currentItem?.status == .readyToPlay
        ) else { return }
        player.play()
    }

    /// scenePhase left `.active` — the watchdog's clock stops counting
    /// (the decoder is frozen; the span is subtracted at expiry).
    func noteBackgrounded() {
        guard backgroundedAt == nil else { return }
        backgroundedAt = Date()
    }

    /// The quiet per-chapter "Weiter": jump to the next item, or hand
    /// over when this was the run's last chapter.
    func skipCurrentChapter() {
        guard !stopped else { return }
        // The queue may already have advanced BY ITSELF: a natural item
        // end reaches `itemDidEnd` one main-queue hop late, while the
        // player has long moved on. A tap in that window must not skip
        // TWICE (stranding a never-played item) — the tap's „next" is
        // exactly where the queue already is: sync, don't double-skip.
        let queueIndex = player.currentItem.flatMap { items.firstIndex(of: $0) }
        if let queueIndex, queueIndex > currentIndex {
            advance(to: queueIndex)
            return
        }
        if currentIndex >= chapters.count - 1 {
            finishRun()
        } else if player.currentItem == nil {
            // A dry queue mid-run cannot play the next chapter — the
            // video path is broken (hev1-Bugklasse). Hand the REST of
            // the run to the procedural stage instead of skipping
            // chapters nobody saw.
            breakRun(at: currentIndex + 1)
        } else {
            player.advanceToNextItem()
            advance(to: currentIndex + 1)
        }
    }

    /// Hard stop (whole-cinema skip / disappear) — silences and frees
    /// everything, fires NO callbacks.
    func stop() {
        guard !stopped else { return }
        stopped = true
        removeObservers()
        player.pause()
        player.removeAllItems()
    }

    // MARK: Internals

    private func itemDidEnd(_ item: AVPlayerItem?) {
        guard !stopped, let item,
              let index = items.firstIndex(of: item),
              index == currentIndex
        else { return }
        if index >= chapters.count - 1 {
            finishRun()
        } else {
            advance(to: index + 1)
        }
    }

    // MARK: Failure signals — the video path must never die silently

    private func itemFailed(at index: Int) {
        guard !stopped else { return }
        failedIndices.insert(index)
        // The CURRENT chapter died → break now. A FUTURE item's early
        // failure waits: the healthy chapters before it keep playing,
        // and `advance(to:)` breaks the moment the run reaches it.
        if index == currentIndex {
            breakRun(at: index)
        }
    }

    private func itemFailedToEnd(_ item: AVPlayerItem?) {
        guard !stopped, let item,
              let index = items.firstIndex(of: item) else { return }
        itemFailed(at: index)
    }

    /// playbackStalled on a LOCAL bundle file is a decoder giving up,
    /// not a network hiccup — same verdict as a failed item.
    private func itemStalled(_ item: AVPlayerItem?) {
        guard !stopped, let item,
              let index = items.firstIndex(of: item) else { return }
        itemFailed(at: index)
    }

    /// First-frame watchdog (readyToPlay-ohne-Frame-Lücke, Kino-Eval
    /// S2, verschärft in Re-Eval Runde 2): `.readyToPlay` only proves
    /// the demuxer liked the file — a device decoder can refuse every
    /// FRAME without any other death signal, and the player CLOCK can
    /// tick regardless, so time is no picture. The pure rules own all
    /// three decisions: re-arm per queue item, judge ONLY on
    /// `isReadyForDisplay`, and count foreground time only.
    private func rearmFirstFrameWatchdog(for itemIndex: Int) {
        guard CinematicScript.firstFrameWatchdogShouldRearm(
            from: watchdogItemIndex, to: itemIndex) else { return }
        watchdogItemIndex = itemIndex
        watchdogArmedAt = Date()
        watchdogBackgrounded = 0
        // Generation++ FOR THIS ITEM plus mirror reset (Fix-Runde 3,
        // Kino-Befund 1; Fix-Runde 4, S2): the new item owes its OWN
        // frame proof — item 1's true, and a seam-held
        // `isReadyForDisplay` that never re-reports, are no evidence
        // for item 2. The armed item identity is part of the truth:
        // even a late report that races the re-arm and reads THIS
        // generation still names the old item and is dropped. Without a
        // fresh edge of THIS (generation, item) the verdict below
        // breaks the run after the window.
        watchdogGenerations.advance(item: ObjectIdentifier(items[itemIndex]))
        layerShowsFrame = false
        scheduleFirstFrameWatchdog(
            after: CinematicScript.firstFrameWatchdogTimeout)
    }

    private func scheduleFirstFrameWatchdog(after seconds: Double) {
        firstFrameWatchdog?.cancel()
        firstFrameWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(
                max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.firstFrameWatchdogExpired()
        }
    }

    private func firstFrameWatchdogExpired() {
        guard !stopped else { return }
        // Foreground honesty: a span spent backgrounded (including one
        // still open right now) proved nothing — sleep the difference
        // instead of judging a decoder that was frozen.
        var away = watchdogBackgrounded
        if let backgroundedAt {
            away += Date().timeIntervalSince(backgroundedAt)
        }
        let foreground = CinematicScript.firstFrameForegroundElapsed(
            wallclock: Date().timeIntervalSince(watchdogArmedAt),
            backgrounded: away)
        if let remainder = CinematicScript.firstFrameWatchdogRemainder(
            foregroundElapsed: foreground) {
            scheduleFirstFrameWatchdog(after: remainder)
            return
        }
        guard CinematicScript.firstFrameWatchdogVerdict(
            layerReady: layerShowsFrame) else { return }
        breakRun(at: currentIndex)
    }

    /// A dry queue is AMBIGUOUS for one beat: the LAST chapter's natural
    /// didPlayToEndTime hops the main queue and lands right after this
    /// KVO — `finishRun` then resolves it. If nothing resolves it within
    /// the grace, the queue died without a single end signal (the hev1
    /// silent death) and the run is broken at the chapter it showed.
    private func queueBecameDry() {
        guard !stopped else { return }
        dryQueueVerdict?.cancel()
        dryQueueVerdict = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.dryQueueGraceExpired()
        }
    }

    private func queueRefilled() {
        dryQueueVerdict?.cancel()
        dryQueueVerdict = nil
    }

    private func dryQueueGraceExpired() {
        guard !stopped, player.currentItem == nil else { return }
        breakRun(at: currentIndex)
    }

    /// The video path died (hev1-Bugklasse). Tear the player down and
    /// hand the run to the shell — the pure rule
    /// (`CinematicScript.brokenRunFallbackIndices`) decides which plan
    /// chapters restage procedurally from here.
    private func breakRun(at index: Int) {
        guard !stopped else { return }
        stopped = true
        removeObservers()
        player.pause()
        player.removeAllItems()
        onRunBroken?(index)
    }

    private func advance(to index: Int) {
        // An already-failed item can never play — break instead of
        // moving the cursor onto a chapter whose picture will not come.
        if failedIndices.contains(index) {
            breakRun(at: index)
            return
        }
        currentIndex = index
        installBoundaryObserver()
        // Every queue item must prove its OWN first frame (Re-Eval
        // Runde 2): the seam into a broken scene 3 used to run without
        // a watchdog once scene 2 had shown a picture.
        rearmFirstFrameWatchdog(for: index)
        onChapterChange?(index)
    }

    private func finishRun() {
        guard !stopped else { return }
        stopped = true
        removeObservers()
        player.pause()
        onFinished?()
    }

    /// Boundary times are ITEM-relative — the observer is rebuilt for
    /// every chapter of the run from that chapter's manifest.
    private func installBoundaryObserver() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        guard chapters.indices.contains(currentIndex) else { return }
        let manifest = chapters[currentIndex].manifest
        let times = manifest.boundaryTimes.map {
            NSValue(time: CMTime(seconds: $0, preferredTimescale: 600))
        }
        guard !times.isEmpty else { return }
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: times, queue: .main
        ) { [weak self] in
            Task { @MainActor in
                self?.boundaryFired()
            }
        }
    }

    /// One boundary crossed: fire everything the manifest schedules at
    /// (about) the current player time. The tolerance absorbs observer
    /// jitter without ever double-firing — boundaries are unique times.
    private func boundaryFired() {
        guard !stopped, chapters.indices.contains(currentIndex) else { return }
        // Between a natural item end and its (main-hopped) `itemDidEnd`,
        // the queue already plays the NEXT item while the observer still
        // carries the OLD chapter's times — a fire in that window would
        // press the old chapter's beats into the new chapter's opening
        // frames. Only fire while observer and queue agree.
        guard let item = player.currentItem,
              items.firstIndex(of: item) == currentIndex else { return }
        let manifest = chapters[currentIndex].manifest
        let now = player.currentTime().seconds
        let tolerance = 0.12
        for beat in manifest.beats where abs(beat.t - now) < tolerance {
            fireBeat?(HapticEventSpec(t: 0, i: beat.i, s: beat.s, d: beat.d ?? 0))
        }
        for cue in manifest.resolvedCues where abs(cue.time - now) < tolerance {
            ringCue?(cue.cue)
        }
    }

    private func removeObservers() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        if let stalledObserver {
            NotificationCenter.default.removeObserver(stalledObserver)
            self.stalledObserver = nil
        }
        for observation in itemStatusObservations {
            observation.invalidate()
        }
        itemStatusObservations.removeAll()
        currentItemObservation?.invalidate()
        currentItemObservation = nil
        dryQueueVerdict?.cancel()
        dryQueueVerdict = nil
        firstFrameWatchdog?.cancel()
        firstFrameWatchdog = nil
    }
}

/// AVPlayerLayer host — the cutscene needs its own chrome (skip, caption
/// overlays, progress dots), so the system transport UI of SwiftUI's
/// `VideoPlayer` is exactly what we do NOT want (RECON §3.1). The host
/// reports the layer's `isReadyForDisplay` upward, so the stage can hold
/// its poster underlay until a REAL frame exists (and again if the layer
/// ever drops one across an item swap) — the picture is never black.
struct CinematicPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    /// Capture-time generation source (Fix-Runde 3, Kino-Befund 1) —
    /// nil stamps the neutral (0, nil) (callers without a watchdog).
    var generations: CinematicWatchdogGenerations? = nil
    var onReadyChange: ((Bool, CinematicWatchdogGenerations.Stamp) -> Void)? = nil

    final class LayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var generations: CinematicWatchdogGenerations?
        var onReadyChange: ((Bool, CinematicWatchdogGenerations.Stamp) -> Void)?
        private var readyObservation: NSKeyValueObservation?

        func observeReadiness() {
            guard readyObservation == nil else { return }
            readyObservation = playerLayer.observe(
                \.isReadyForDisplay, options: [.initial, .new]
            ) { [weak self] layer, _ in
                let ready = layer.isReadyForDisplay
                // The stamp is taken HERE, at KVO time — generation AND
                // item provenance in one breath (Fix-Runde 4, S2): a
                // late main-hop delivery still names the (generation,
                // item) it SAW. The item is the layer's player's
                // current item at this instant — the only item this
                // readiness can be evidence FOR; the generation alone
                // let a report that raced the re-arm pass as the new
                // item's proof.
                let stamp: CinematicWatchdogGenerations.Stamp
                if let generations = self?.generations {
                    stamp = CinematicWatchdogGenerations.Stamp(
                        generation: generations.current.generation,
                        item: (layer.player?.currentItem).map(ObjectIdentifier.init))
                } else {
                    stamp = CinematicWatchdogGenerations.Stamp(
                        generation: 0, item: nil)
                }
                // KVO may deliver off-main; state writes hop over.
                DispatchQueue.main.async {
                    self?.onReadyChange?(ready, stamp)
                }
            }
        }
    }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        view.isUserInteractionEnabled = false
        view.generations = generations
        view.onReadyChange = onReadyChange
        view.observeReadiness()
        return view
    }

    func updateUIView(_ view: LayerHostView, context: Context) {
        view.generations = generations
        view.onReadyChange = onReadyChange
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// The PICTURE of a live video run: the run's ONE player layer over a
/// first-frame poster underlay. The shell mounts this OUTSIDE the
/// crossfading chapter identities — recreating an AVPlayerLayer per
/// chapter would blank the outgoing body mid-fade (AVFoundation renders
/// video only into the most recently created layer), the 2→3 seam flash.
/// The underlay carries the stage until the layer reports readiness, and
/// its poster is always the CURRENT chapter's opening frame — at the
/// seam that is the run's matching hold frame by render design.
///
/// Failure-proofing (hev1-Bugklasse): the poster hides ONLY while the
/// layer truly shows a picture AND the player still holds an item — a
/// dead queue behind a stale `isReadyForDisplay` must never leave the
/// stage bare. And when the poster frame itself cannot decode (same
/// hardware decoder as playback), `onPosterFailure` tells the shell to
/// fall to the Kurzfassung instead of waiting for a frame that never
/// comes.
struct CinematicVideoSurface: View {
    let player: AVPlayer
    let posterURL: URL?
    /// Capture-time watchdog-generation source (Fix-Runde 3, Kino-
    /// Befund 1) — handed down to the layer host, which stamps every
    /// readiness report with the (generation, item) it was captured
    /// under.
    var generations: CinematicWatchdogGenerations? = nil
    var onPosterFailure: (() -> Void)? = nil
    /// Forwards the layer's `isReadyForDisplay` (plus its capture-time
    /// stamp) to the shell — the run controller's first-frame watchdog
    /// and the poster-failure refutation both need the truth "a frame
    /// is really showing", item-specific.
    var onLayerReady: ((Bool, CinematicWatchdogGenerations.Stamp) -> Void)? = nil

    @State private var layerReady = false
    /// Pessimistic until the player proves an item — the poster stands.
    @State private var hasCurrentItem = false

    var body: some View {
        ZStack {
            if let posterURL {
                CinematicPosterView(url: posterURL, posterTime: 0,
                                    showsRoomPlaceholder: false,
                                    onDecodeFailure: { onPosterFailure?() })
                    .opacity(layerReady && hasCurrentItem ? 0 : 1)
            }
            CinematicPlayerLayerView(player: player,
                                     generations: generations) { ready, stamp in
                // Poster filter (Fix-Runde 4, S2): `layerReady` follows
                // ONLY accepted reports — the SAME armed (generation,
                // item) truth the watchdog judges with. A discarded
                // report sets NOTHING: a verworfene generation's stale
                // standbild must never hide the CURRENT chapter's
                // poster. Reports are still forwarded unfiltered — the
                // controller judges with its own armed truth.
                let armed = generations?.current
                    ?? CinematicWatchdogGenerations.Stamp(generation: 0, item: nil)
                let counts = CinematicScript.firstFrameReportCounts(
                    reportedGeneration: stamp.generation,
                    armedGeneration: armed.generation,
                    reportedItem: stamp.item,
                    armedItem: armed.item)
                layerReady = CinematicScript.surfaceLayerReady(
                    current: layerReady, reportCounts: counts, reported: ready)
                onLayerReady?(ready, stamp)
            }
            .ignoresSafeArea()
        }
        .onReceive(player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)) { item in
            hasCurrentItem = item != nil
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single video frame as a calm still (AVAssetImageGenerator — zero
/// extra assets). Two callers: the Reduce-Motion chapter still (manifest
/// `posterTime`, warm room placeholder while decoding) and the live
/// run's first-frame underlay (`showsRoomPlaceholder: false` — the
/// animated room already stands behind it, an opaque flat color would
/// cover it). The decode re-runs when the source frame changes (the
/// underlay follows the run across its chapters); the previous frame
/// stays up during a re-decode — a hold frame, never a blank.
struct CinematicPosterView: View {
    let url: URL
    let posterTime: Double
    var showsRoomPlaceholder = true
    /// The frame decode FAILED (hev1-Bugklasse: the generator rides the
    /// same hardware decoder that refuses playback on device) — the
    /// owner switches to the procedural Kurzfassung instead of waiting
    /// for a poster that never comes.
    var onDecodeFailure: (() -> Void)? = nil

    @State private var poster: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if showsRoomPlaceholder {
                    Papier.zimmerUnten
                }
                if let poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            }
        }
        .ignoresSafeArea()
        .task(id: "\(url.absoluteString)#\(posterTime)") {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: posterTime, preferredTimescale: 600)
            do {
                let result = try await generator.image(at: time)
                poster = UIImage(cgImage: result.image)
            } catch {
                // The placeholder (or the previous frame) stays — a
                // missing frame must never turn the stage black. A
                // CANCELLED decode (view left) is no verdict; a real
                // decode failure is reported so the stage can fall to
                // the Kurzfassung.
                guard !Task.isCancelled else { return }
                onDecodeFailure?()
            }
        }
    }
}
