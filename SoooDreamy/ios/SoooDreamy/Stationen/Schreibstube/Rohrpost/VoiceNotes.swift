import SwiftUI
import AVFoundation
import Observation

/// "m:ss" for voice note durations and the recorder timer.
func chatDurationString(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}

// MARK: - Shared voice message player

/// One app-wide player for voice messages: starting a new message pauses the
/// previous one. Publishes which message is playing plus playback progress.
@MainActor
@Observable
final class VoicePlayer {
    static let shared = VoicePlayer()

    /// Cycled by the speed button: 1× → 1.5× → 2× → 1×.
    static let playbackRates: [Double] = [1.0, 1.5, 2.0]

    private(set) var playingId: String?
    private(set) var isPlaying = false
    /// 0…1 for the currently playing message.
    private(set) var progress: Double = 0
    /// Total duration (seconds) of the current message, 0 when unknown.
    private(set) var duration: Double = 0
    /// Playback speed; kept across messages so the preference sticks.
    private(set) var rate: Double = 1.0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var fallbackDuration: Double = 0

    private init() {}

    /// "1×", "1.5×", "2×" — literal labels, deliberately not localized.
    var rateLabel: String {
        rate == rate.rounded() ? "\(Int(rate))×" : String(format: "%.1f×", rate)
    }

    /// Seconds left in the current message at the current progress.
    var remainingSeconds: Double { max(0, duration * (1 - progress)) }

    func toggle(message: Message, api: API?) {
        if playingId == message.id {
            if isPlaying { pause() } else { resume() }
            return
        }
        guard let api,
              let path = message.audioUrl,
              let request = api.mediaRequest(path),
              let url = request.url else { return }
        stop()
        activatePlaybackSession()
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]
        ])
        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        playingId = message.id
        progress = 0
        fallbackDuration = message.durationSec ?? 0
        duration = fallbackDuration
        newPlayer.defaultRate = Float(rate)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stop()
            }
        }
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateProgress(time)
            }
        }
        newPlayer.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func resume() {
        activatePlaybackSession()
        player?.play()
        isPlaying = true
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player?.pause()
        player = nil
        playingId = nil
        isPlaying = false
        progress = 0
        duration = 0
        restoreAmbientSession()
    }

    /// Jump to a position (0…1) in the current message — works while paused too.
    func seek(toProgress target: Double) {
        let clamped = min(1, max(0, target))
        progress = clamped
        guard let player, duration > 0 else { return }
        let time = CMTime(seconds: clamped * duration, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Advance to the next playback speed (1× → 1.5× → 2× → 1×).
    func cycleRate() {
        let rates = Self.playbackRates
        let index = rates.firstIndex(of: rate) ?? 0
        rate = rates[(index + 1) % rates.count]
        player?.defaultRate = Float(rate)
        if isPlaying { player?.rate = Float(rate) }
    }

    private func updateProgress(_ time: CMTime) {
        guard let player else { return }
        var total = player.currentItem.map { $0.duration.seconds } ?? 0
        if !total.isFinite || total <= 0 { total = fallbackDuration }
        duration = total
        guard total > 0 else {
            progress = 0
            return
        }
        progress = min(1, max(0, time.seconds / total))
    }

    private func activatePlaybackSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// The app's SoundEngine depends on the ambient/mix-with-others session.
    private func restoreAmbientSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - Voice bubble (playback UI in the chat list)

struct ChatVoiceBubble: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    /// VoiceOver keeps the classic slider; everyone else scrubs directly
    /// on the waveform.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    let message: Message
    let isMine: Bool
    var group = ChatGroupPosition()
    let onReact: (String) -> Void
    var onDelete: (() -> Void)? = nil

    /// Non-nil while the user drags the scrub slider; the seek happens on release.
    @State private var scrubProgress: Double?

    private var player: VoicePlayer { VoicePlayer.shared }
    private var isCurrent: Bool { player.playingId == message.id }

    private var transcriptCenter: VoiceTranscriptCenter { VoiceTranscriptCenter.shared }

    private var displayedProgress: Double {
        guard isCurrent else { return 0 }
        return scrubProgress ?? player.progress
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                playButton
                VStack(alignment: .leading, spacing: 5) {
                    waveformArea
                    if isCurrent && voiceOverEnabled {
                        scrubSlider
                    }
                    HStack(spacing: 8) {
                        Text(timeText)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            // Both sides sit on paper Zettel (R1-A): quiet
                            // secondary ink, NOT the night-white compat token.
                            .foregroundStyle(Tinte.sekundaer)
                        if isCurrent {
                            speedButton
                        }
                        if group.isEnd {
                            ChatTimestampText(date: message.createdAt, isMine: isMine,
                                              read: chatReadReceipt(for: message, isMine: isMine,
                                                                    partner: appState.partner))
                        }
                    }
                }
            }
            transcriptBlock
        }
        .padding(.vertical, LayoutMetrics.s(10))
        .padding(.horizontal, LayoutMetrics.s(12))
        .background(ChatBubbleBackground(isMine: isMine,
                                         groupedTop: !group.isStart,
                                         groupedBottom: !group.isEnd))
        // Glitch-Pass (P2-B): the transcript block declares a transition,
        // but the center mutates from async tasks with no withAnimation —
        // the block popped in and grew the Zettel with a hard jump.
        .animation(Theme.Motion.settle,
                   value: transcriptCenter.visibleState(for: message.id))
        .onTapGesture(count: 2) {
            onReact(ChatReactions.quick)
        }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            transcriptMenuItems
            ChatPinButton(message: message)
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
    }

    // MARK: On-device transcript (Welle 7 [28])

    /// Expandable transcript under the waveform: transcribed on device,
    /// cached only locally, and always marked as machine output.
    @ViewBuilder private var transcriptBlock: some View {
        if let state = transcriptCenter.visibleState(for: message.id) {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Papier.kante)
                    .frame(height: Theme.hairlineWidth)
                switch state {
                case .working:
                    HStack(spacing: 6) {
                        // Both bubbles are paper Zettel (R1-A) — the dots
                        // and the caption wear the tertiary ink (.caption
                        // clears the tertiaer size floor).
                        ChatTypingDots(tint: Tinte.tertiaer)
                        Text(L10n.t("chat.transcript.working"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Tinte.tertiaer)
                    }
                case .done(let text):
                    Text(text)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                        .multilineTextAlignment(.leading)
                    // caption2 sits below the Tinte.tertiaer size floor —
                    // the machine-output micro-label takes the secondary ink.
                    Label(L10n.t("chat.transcript.label"), systemImage: "text.quote")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.sekundaer)
                case .failed(let key):
                    Text(L10n.t(key))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Tinte.tertiaer)
                }
            }
            .frame(maxWidth: LayoutMetrics.s(230), alignment: .leading)
            .transition(.opacity)
        }
    }

    @ViewBuilder private var transcriptMenuItems: some View {
        if case .failed = transcriptCenter.visibleState(for: message.id) {
            Button {
                transcriptCenter.requestTranscript(message: message, api: appState.api)
            } label: {
                Label(L10n.t("chat.transcript.retry"), systemImage: "arrow.counterclockwise")
            }
        }
        if transcriptCenter.visibleState(for: message.id) != nil {
            Button {
                transcriptCenter.hideTranscript(for: message.id)
            } label: {
                Label(L10n.t("chat.transcript.hide"), systemImage: "eye.slash")
            }
        } else if message.audioUrl != nil {
            Button {
                Haptics.shared.tap()
                transcriptCenter.requestTranscript(message: message, api: appState.api)
            } label: {
                Label(L10n.t("chat.transcript.show"), systemImage: "text.quote")
            }
        }
    }

    /// Remaining time ("-m:ss") while this message is loaded, total duration otherwise.
    private var timeText: String {
        if isCurrent, player.duration > 0 {
            let remaining = max(0, player.duration * (1 - displayedProgress))
            return "-" + chatDurationString(remaining)
        }
        return chatDurationString(message.durationSec ?? 0)
    }

    /// While playing, the waveform itself is the scrubber: tap or drag
    /// anywhere on it to seek — no extra slider row eating bubble height.
    @ViewBuilder private var waveformArea: some View {
        // Both Zettel are PAPER (R1-A): the played stroke is the couple's
        // shared ink (inkOnPaper, ≥4.5:1 pinned against every paper tone),
        // the unplayed rest a faded tertiary-ink stroke — white was
        // invisible on brief, and the gradient ink left with the gradient.
        let bars = ChatWaveformBars(seed: message.id,
                                    progress: displayedProgress,
                                    activeTint: coupleTint.tinte,
                                    inactiveTint: Tinte.tertiaer.opacity(0.4))
            .accessibilityHidden(true)
        if isCurrent && !voiceOverEnabled {
            bars
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubProgress = min(1, max(0, value.location.x / ChatWaveformBars.totalWidth))
                        }
                        .onEnded { _ in
                            if let target = scrubProgress {
                                player.seek(toProgress: target)
                            }
                            scrubProgress = nil
                        }
                )
        } else {
            bars
        }
    }

    private var scrubSlider: some View {
        Slider(
            value: Binding(
                get: { scrubProgress ?? player.progress },
                set: { scrubProgress = $0 }
            ),
            in: 0...1
        ) { editing in
            if !editing {
                if let target = scrubProgress {
                    player.seek(toProgress: target)
                }
                scrubProgress = nil
            }
        }
        .tint(coupleTint.tinte)
        .frame(height: LayoutMetrics.s(20))
        .accessibilityLabel(L10n.t("chat.voiceScrubA11y"))
        .accessibilityValue(Text(verbatim: timeText))
    }

    private var speedButton: some View {
        Button {
            Haptics.shared.tap()
            player.cycleRate()
        } label: {
            Text(player.rateLabel)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .monospacedDigit()
                // Ink stamp on paper, BOTH sides (R1-A): an ink-filled
                // capsule (inkOnPaper ≥4.5:1 against every paper tone)
                // with letter-paper text — the white-chip-on-gradient era
                // ended with the gradient bubble.
                .foregroundStyle(Papier.brief)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(coupleTint.tinte))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: player.rateLabel))
        .accessibilityHint(L10n.t("chat.voiceSpeedA11y"))
    }

    private var playButton: some View {
        Button {
            Haptics.shared.tap()
            player.toggle(message: message, api: appState.api)
        } label: {
            Image(systemName: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                // An ink stamp pressed onto the paper Zettel, BOTH sides
                // (R1-A) — solid inkOnPaper circle, glyph in letter paper
                // (≥4.5:1 pinned both ways). The white-circle-on-gradient
                // treatment left with the gradient bubble.
                .foregroundStyle(Papier.brief)
                .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                .background(Circle().fill(coupleTint.tinte))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.voiceMessage"))
    }
}

/// Simple static waveform: bar heights derived deterministically from the
/// message id, tinted up to the current playback progress.
struct ChatWaveformBars: View {
    let heights: [CGFloat]
    let progress: Double
    let activeTint: Color
    let inactiveTint: Color

    private static let barCount = 24
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2.5

    /// Intrinsic width of the bar row — lets the bubble scrub on the
    /// waveform without wrapping it in a GeometryReader.
    static var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    init(seed: String, progress: Double, activeTint: Color, inactiveTint: Color) {
        self.heights = Self.makeHeights(seed: seed)
        self.progress = progress
        self.activeTint = activeTint
        self.inactiveTint = inactiveTint
    }

    var body: some View {
        HStack(alignment: .center, spacing: Self.barSpacing) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                Capsule()
                    .fill(i < activeCount ? activeTint : inactiveTint)
                    .frame(width: Self.barWidth, height: 6 + heights[i] * 20)
            }
        }
        .frame(height: 28)
    }

    private var activeCount: Int {
        Int(progress * Double(Self.barCount))
    }

    private static func makeHeights(seed: String) -> [CGFloat] {
        var state: UInt64 = 0x9E3779B97F4A7C15
        for byte in seed.utf8 {
            state = (state ^ UInt64(byte)) &* 0x100000001B3
        }
        func rnd() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
        return (0..<barCount).map { _ in 0.15 + rnd() * 0.85 }
    }
}

// MARK: - Recorder model

@MainActor
@Observable
final class VoiceRecorderModel {
    enum Phase: Equatable {
        /// Mic idle, waiting for an explicit tap — recording NEVER starts
        /// just because the sheet opened (Linse 27).
        case armed
        case denied, failed, recording
        /// Finished take on disk: previewable, sendable, guarded on dismiss.
        case recorded
    }

    static let maxDuration: Double = 120

    private(set) var phase: Phase = .armed
    private(set) var elapsed: Double = 0
    /// Rolling window of normalized (0…1) meter levels for the live bars.
    private(set) var levels: [Double] = []
    /// The WHOLE take bucketed to the bar count — the preview stage shows
    /// the real waveform of what was said, not just the last few seconds.
    private(set) var takeWaveform: [Double] = []
    private(set) var recordedDuration: Double = 0
    /// Preview playback position of the finished take (0…1).
    private(set) var previewProgress: Double = 0
    private(set) var isPreviewing = false

    @ObservationIgnored private var recorder: AVAudioRecorder?
    /// Every meter sample of the running take (uncapped, ~20/s) — source
    /// for the downsampled `takeWaveform`.
    @ObservationIgnored private var allLevels: [Double] = []
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var fileURL: URL?
    @ObservationIgnored private var previewPlayer: AVAudioPlayer?
    @ObservationIgnored private var previewTimer: Timer?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    func start() async {
        guard phase != .recording else { return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            phase = .denied
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.prepareToRecord()
            rec.record()
            recorder = rec
            fileURL = url
            elapsed = 0
            levels = []
            allLevels = []
            takeWaveform = []
            recordedDuration = 0
            resetPreview()
            phase = .recording
            startMeterTimer()
            observeInterruptions()
        } catch {
            restoreAmbientSession()
            phase = .failed
        }
    }

    /// Stops the recording, keeps the file, restores the audio session.
    func finishRecording() {
        guard phase == .recording, let recorder else { return }
        recordedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        elapsed = recordedDuration
        takeWaveform = Self.downsampled(allLevels, to: ChatRecorderLevelBars.barCount)
        restoreAmbientSession()
        phase = .recorded
    }

    /// Buckets the raw meter samples into `count` averaged bars.
    static func downsampled(_ samples: [Double], to count: Int) -> [Double] {
        guard count > 0, !samples.isEmpty else { return [] }
        return (0..<count).map { index in
            let start = index * samples.count / count
            let end = min(max(start + 1, (index + 1) * samples.count / count), samples.count)
            let bucket = samples[start..<end]
            return bucket.reduce(0, +) / Double(bucket.count)
        }
    }

    /// Discards everything and re-arms the mic (re-record, confirmed dismiss,
    /// cleanup after a successful send).
    func cancel() {
        stopPreview(restoreSession: false)
        previewPlayer = nil
        previewProgress = 0
        meterTimer?.invalidate()
        meterTimer = nil
        recorder?.stop()
        recorder = nil
        stopObservingInterruptions()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
        levels = []
        allLevels = []
        takeWaveform = []
        restoreAmbientSession()
        phase = .armed
    }

    func recordedData() -> Data? {
        guard let fileURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    // MARK: Preview (listen before sending)

    func togglePreview() {
        guard phase == .recorded, let fileURL else { return }
        if isPreviewing {
            stopPreview()
            return
        }
        do {
            if previewPlayer == nil {
                previewPlayer = try AVAudioPlayer(contentsOf: fileURL)
            }
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            if previewProgress >= 1 {
                previewPlayer?.currentTime = 0
                previewProgress = 0
            }
            previewPlayer?.play()
            isPreviewing = true
            startPreviewTimer()
        } catch {
            // Preview is best effort — the take stays sendable without it.
            restoreAmbientSession()
        }
    }

    private func stopPreview(restoreSession: Bool = true) {
        previewTimer?.invalidate()
        previewTimer = nil
        guard isPreviewing else { return }
        previewPlayer?.pause()
        isPreviewing = false
        if restoreSession { restoreAmbientSession() }
    }

    private func resetPreview() {
        stopPreview(restoreSession: false)
        previewPlayer = nil
        previewProgress = 0
    }

    private func startPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.previewTick()
            }
        }
    }

    private func previewTick() {
        guard let player = previewPlayer, isPreviewing else { return }
        let total = player.duration
        if player.isPlaying {
            previewProgress = total > 0 ? min(1, player.currentTime / total) : 0
        } else {
            // Reached the end (or the system paused us) — rest at "played".
            previewProgress = 1
            stopPreview()
        }
    }

    // MARK: Interruptions (Linse 27: a call ends the take cleanly)

    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor [weak self] in
                if began { self?.handleInterruptionBegan() }
            }
        }
    }

    private func stopObservingInterruptions() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
    }

    private func handleInterruptionBegan() {
        guard phase == .recording else { return }
        if VoiceCaptureGuard.keepTakeAfterInterruption(elapsed: elapsed) {
            // Keep what was said so far — it lands in the preview stage.
            finishRecording()
        } else {
            // Sub-second blip: nothing worth keeping, just re-arm.
            cancel()
        }
    }

    // MARK: Internals

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard phase == .recording, let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)       // -160…0 dB
        let level = pow(10.0, Double(power) / 20.0)            // → 0…1
        let normalized = min(1, max(0.04, level * 1.6))
        levels.append(normalized)
        allLevels.append(normalized)
        if levels.count > 40 {
            levels.removeFirst(levels.count - 40)
        }
        elapsed = recorder.currentTime
        if elapsed >= Self.maxDuration {
            finishRecording()
        }
    }

    /// The app's SoundEngine depends on the ambient/mix-with-others session.
    private func restoreAmbientSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

// MARK: - Recorder sheet

struct VoiceRecorderSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    @State private var model = VoiceRecorderModel()
    @State private var sending = false
    /// Drives the "discard this recording?" confirmation (Linse 27: a sheet
    /// holding a real take never vanishes silently).
    @State private var confirmDiscard = false
    let onSent: (Message) -> Void

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            VStack(spacing: LayoutMetrics.s(22)) {
                titleRow
                stage
                Spacer(minLength: 0)
                buttons
            }
            .padding(LayoutMetrics.s(22))
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(sending || dismissNeedsConfirmation)
        .onDisappear { model.cancel() }
        .confirmationDialog(L10n.t("chat.voiceDiscardConfirm"),
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(L10n.t("chat.voiceDiscard"), role: .destructive) {
                model.cancel()
                dismiss()
            }
            Button(L10n.t("chat.voiceKeep"), role: .cancel) {}
        }
    }

    /// True while a real take (finished, or in-flight and long enough)
    /// would be lost by dismissing.
    private var dismissNeedsConfirmation: Bool {
        VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: model.phase == .recorded,
            isRecording: model.phase == .recording,
            elapsed: model.elapsed)
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .foregroundStyle(coupleTint.blend)
            Text(L10n.t("chat.voiceTitle"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, LayoutMetrics.s(16))
    }

    @ViewBuilder private var stage: some View {
        switch model.phase {
        case .armed:
            armedStage
        case .denied:
            EmptyStateView(systemImage: "mic.slash",
                           title: L10n.t("chat.voiceDeniedTitle"),
                           subtitle: L10n.t("chat.voiceDeniedSubtitle"),
                           actionTitle: L10n.t("lock.openSettings"),
                           action: {
                               UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                           })
        case .failed:
            EmptyStateView(systemImage: "lifepreserver",
                           title: L10n.t("chat.voiceFailedTitle"),
                           subtitle: L10n.t("chat.voiceFailedSubtitle"),
                           actionTitle: L10n.t("common.retry"),
                           action: {
                               Haptics.shared.tap()
                               model.cancel()
                           })
        case .recording, .recorded:
            recordingStage
        }
    }

    /// Mic is armed but silent — recording starts only on an explicit tap.
    private var armedStage: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Button {
                Haptics.shared.tap()
                Task { await model.start() }
            } label: {
                ZStack {
                    Circle()
                        .fill(coupleTint.heroGradient)
                        .overlay(Circle().fill(coupleTint.gradientTextScrim ?? .clear))
                        .frame(width: LayoutMetrics.s(72), height: LayoutMetrics.s(72))
                        .shadow(color: coupleTint.blend.opacity(0.5), radius: 14, y: 6)
                    Image(systemName: "mic.fill")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        // Computed ink on the couple gradient (round 3).
                        .foregroundStyle(coupleTint.onGradient)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voiceRecord"))
            Text(L10n.t("chat.voiceArmedHint"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // The recorder writes a voice Zettel — CONTENT lies on paper
        // (Korrespondenz), it does not float on glass. The gradient mic
        // button stays an OBJECT on the paper, never a wash.
        .paperCard(.brief, padding: .hero)
    }

    private var recordingStage: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            // Ink strokes on paper: the meter draws with the couple's
            // shared ink (inkOnPaper) — the gradient bars washed out on
            // brief for light palettes.
            ChatRecorderLevelBars(
                levels: model.phase == .recording ? model.levels : model.takeWaveform,
                live: model.phase == .recording,
                progress: model.phase == .recorded ? model.previewProgress : nil,
                inkTint: coupleTint.tinte
            )
            Text(timeLabel)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Tinte.dunkel)
            // State line ON paper: the member's ink while recording, the
            // couple's shared ink for "ready" — Licht.glut is a NIGHT
            // accent and stays off the paper (migration table).
            Text(model.phase == .recording ? L10n.t("chat.voiceRecording") : L10n.t("chat.voiceReady"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(model.phase == .recording ? coupleTint.tintePrimary : coupleTint.tinte)
            if model.phase == .recorded {
                previewRow
            } else {
                Text(L10n.t("chat.voiceMaxHint"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
        }
        .frame(maxWidth: .infinity)
        .paperCard(.brief, padding: .hero)
    }

    /// Listen before sending: play/pause + progress + re-record escape hatch.
    private var previewRow: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Button {
                Haptics.shared.tap()
                model.togglePreview()
            } label: {
                Image(systemName: model.isPreviewing ? "pause.fill" : "play.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    // Ink stamp on the paper card — same treatment as the
                    // partner bubble's play button (≥4.5:1 pinned).
                    .foregroundStyle(Papier.brief)
                    .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                    .background(Circle().fill(coupleTint.tinte))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voicePreview"))
            ProgressView(value: model.previewProgress)
                .tint(coupleTint.tinte)
            Button {
                Haptics.shared.tap()
                model.cancel()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.sekundaer)
                    .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                    .background(
                        Circle().fill(Papier.innenFill)
                            .overlay(Circle().strokeBorder(Papier.kante,
                                                           lineWidth: Theme.hairlineWidth))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("chat.voiceRerecord"))
        }
    }

    private var timeLabel: String {
        let current = model.phase == .recorded ? model.recordedDuration : model.elapsed
        return "\(chatDurationString(current)) / \(chatDurationString(VoiceRecorderModel.maxDuration))"
    }

    private var buttons: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Button(L10n.t("chat.cancel")) {
                Haptics.shared.tap()
                if dismissNeedsConfirmation {
                    confirmDiscard = true
                } else {
                    model.cancel()
                    dismiss()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(sending)

            Button(primaryLabel) {
                primaryAction()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
        }
        .padding(.bottom, 6)
    }

    private var primaryLabel: String {
        if sending { return L10n.t("chat.voiceSending") }
        switch model.phase {
        case .armed:
            return L10n.t("chat.voiceRecord")
        case .recording:
            return L10n.t("chat.voiceStop")
        case .recorded:
            return L10n.t("chat.voiceSend")
        case .denied, .failed:
            return L10n.t("chat.voiceRetry")
        }
    }

    private func primaryAction() {
        Haptics.shared.tap()
        switch model.phase {
        case .armed, .denied, .failed:
            Task { await model.start() }
        case .recording:
            stopForPreview()
        case .recorded:
            send()
        }
    }

    /// Stop → preview stage. Too-short takes re-arm instead of auto-sending.
    private func stopForPreview() {
        model.finishRecording()
        if model.recordedDuration < VoiceCaptureGuard.minimumSendableSeconds {
            Haptics.shared.warning()
            appState.showToast(L10n.t("chat.voiceTooShort"), style: .info)
            model.cancel()
        }
    }

    private func send() {
        guard !sending, model.phase == .recorded else { return }
        guard let data = model.recordedData(), let api = appState.api else { return }
        sending = true
        Task {
            do {
                let message = try await api.sendVoice(data: data, durationSec: model.recordedDuration)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("chat.voiceSent"), style: .love)
                onSent(message)
                dismiss()
            } catch {
                sending = false
                appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Live level bars

/// Live mode shows the rolling last seconds; finished mode shows the whole
/// take (already bucketed to `barCount`), tinted up to the preview progress.
struct ChatRecorderLevelBars: View {
    let levels: [Double]
    var live: Bool = true
    /// Preview playback position (0…1) for the finished take — nil while
    /// recording.
    var progress: Double? = nil
    /// Optional flat INK for paper surfaces (the chat recorder card is
    /// paper now) — nil keeps the night-era couple gradient, so the other
    /// call sites (Daymemo, on night) render exactly as before.
    var inkTint: Color? = nil

    @Environment(\.coupleTint) private var coupleTint

    static let barCount = 36

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                bar(at: i)
            }
        }
        .frame(height: LayoutMetrics.s(64))
        .accessibilityHidden(true)
    }

    private func bar(at index: Int) -> some View {
        let level = barLevel(at: index)
        return Capsule()
            .fill(inkTint.map(AnyShapeStyle.init)
                  ?? AnyShapeStyle(coupleTint.heroGradient))
            .opacity(barOpacity(at: index, level: level))
            .frame(width: 4, height: 8 + CGFloat(level) * 54)
    }

    private func barLevel(at index: Int) -> Double {
        if live {
            let offset = levels.count - Self.barCount + index
            return (offset >= 0 && offset < levels.count) ? levels[offset] : 0.04
        }
        return index < levels.count ? levels[index] : 0.04
    }

    private func barOpacity(at index: Int, level: Double) -> Double {
        if live { return 0.45 + 0.55 * level }
        guard let progress else { return 0.5 }
        let played = index < Int(progress * Double(Self.barCount))
        return played ? 0.95 : 0.35
    }
}
