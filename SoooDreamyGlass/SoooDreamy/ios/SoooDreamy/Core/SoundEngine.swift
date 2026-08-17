import AVFoundation
import Foundation

/// Hybrid sound engine. The synthesis (stereo voices with cent-detune, real
/// attack/decay envelopes, inharmonic bell spectra, a feedback-echo tail,
/// soft-knee saturation) remains the heart and the ETERNAL fallback of every
/// cue. On top of it, cues from the `AppCue` catalog may carry a bundled
/// CC0/CC-BY recording (`Resources/Sounds/cue_<id>.caf`, credited in
/// sound_credits.json — see docs/CREDITS.md): resolution order is
/// cache → bundled CAF → synthesis, so a missing or broken file can never
/// silence or crash the app. Volumes are soft by default and adjustable per
/// category in Settings. Mixes politely with the user's music.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sooodreamy.soundsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.soundsEnabled") }
    }

    /// Hidden debug A/B switch: forces the procedural voice for every cue.
    /// This is the tool for gain-tuning sessions and honest "is the sample
    /// really better?" reviews — no remote-config machinery needed.
    static var forceSynthSounds: Bool {
        get { UserDefaults.standard.bool(forKey: "sooodreamy.forceSynthSounds") }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.forceSynthSounds") }
    }

    // MARK: Categories (per-category volume, v2.0)

    enum Category: String, CaseIterable, Identifiable {
        case moments, chat, games, ui

        var id: String { rawValue }

        /// "Soft by default" — tuned so nothing ever startles.
        var defaultVolume: Double {
            switch self {
            case .moments: return 0.65
            case .chat: return 0.5
            case .games: return 0.6
            case .ui: return 0.35
            }
        }

        var titleKey: String { "settings.soundvol.\(rawValue)" }

        var icon: String {
            switch self {
            case .moments: return "heart.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .games: return "gamecontroller.fill"
            case .ui: return "wand.and.stars"
            }
        }

        /// Representative sound for the volume-slider preview.
        var previewSound: Sound {
            switch self {
            case .moments: return .heartbeat
            case .chat: return .pop
            case .games: return .tada
            case .ui: return .chime
            }
        }
    }

    static func volume(for category: Category) -> Double {
        UserDefaults.standard.object(forKey: "sooodreamy.soundVolume.\(category.rawValue)") as? Double
            ?? category.defaultVolume
    }

    static func setVolume(_ value: Double, for category: Category) {
        UserDefaults.standard.set(min(1, max(0, value)), forKey: "sooodreamy.soundVolume.\(category.rawValue)")
    }

    // MARK: Sounds

    enum Sound: CaseIterable {
        case heartbeat, chime, pop, whoosh, tada, sparkle
        case click, success, letterSeal, unlock, win, lose, vibe
        // Short airy send-swish — the procedural voice of the `sent` cue.
        case swish
        // The cinematic's score voices (CinematicScript.soundLayers):
        // a long aurora pad, two side-separated orb tones, and the
        // merge's sub-swell + shimmer. Rendered on demand, never cached
        // (they play once per install), stoppable via the score nodes.
        case cinematicBed, cinematicOrbs, cinematicBloom

        var category: Category {
            switch self {
            case .heartbeat, .sparkle, .whoosh, .vibe: return .moments
            case .cinematicBed, .cinematicOrbs, .cinematicBloom: return .moments
            case .pop, .letterSeal, .swish: return .chat
            case .tada, .win, .lose: return .games
            case .chime, .click, .success, .unlock: return .ui
            }
        }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    /// Decoded bundle recordings per cue; `nil` caches a failed/missing file
    /// so the fallback decision happens once, not on every play.
    private var cueFileBuffers: [AppCue: AVAudioPCMBuffer?] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    private var started = false

    private init() {}

    func prepare() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for _ in 0..<4 {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            players.append(node)
        }
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    func play(_ sound: Sound) {
        // The glass-family sounds carry bundled recordings via their cue —
        // route legacy call sites through the resolver so the whole app
        // speaks the same material without touching every caller.
        switch sound {
        case .chime: play(cue: .chime)
        case .letterSeal: play(cue: .sealed)
        case .unlock: play(cue: .unlock)
        default:
            guard readyToPlay(), let volume = effectiveVolume(for: sound.category) else { return }
            schedule(synthBuffer(for: sound), volume: volume)
        }
    }

    /// Cue playback (Dossier 47): cache → bundled CAF → synthesis. Hybrid
    /// cues layer the dreamy synth voice under the recorded transient so the
    /// sound identity stays ONE world.
    ///
    /// `mixedAs` separates MATERIAL from CHANNEL (re-eval 2, Schreibstube
    /// Befund 3): a `soundOverride` substitutes another cue's sample, but
    /// the volume slider that governs it stays the ORIGINAL cue's semantic
    /// category — the chat send's spindle tick rides the Chat slider, never
    /// the Games one. Defaults to the cue's own category.
    func play(cue: AppCue, mixedAs semanticCategory: CueCategory? = nil) {
        guard readyToPlay() else { return }
        let category = Category(rawValue: (semanticCategory ?? cue.category).rawValue) ?? .ui
        guard let volume = effectiveVolume(for: category) else { return }
        if !Self.forceSynthSounds, let fileBuffer = fileBuffer(for: cue) {
            schedule(fileBuffer, volume: volume)
            if cue.plannedMode == .hybrid {
                schedule(synthBuffer(for: cue.synthSound), volume: volume * 0.6)
            }
        } else {
            schedule(synthBuffer(for: cue.synthSound), volume: volume)
        }
    }

    func play(for kind: TouchKind) {
        switch kind {
        case .heartbeat: play(cue: .heartbeat)
        case .kiss: play(cue: .kiss)
        case .hug: play(cue: .hug)
        case .missyou: play(cue: .sparkle)
        case .tickle: play(cue: .sparkle)
        case .thinking: play(cue: .chime)
        case .stolz: play(cue: .sparkle)
        case .halteDurch: play(cue: .heartbeat)
        }
    }

    // MARK: Score voices (long, stoppable layers — the cinematic's bed)

    /// Long score layers play on dedicated nodes: the 4-player one-shot
    /// round-robin would steal a 22 s aurora bed mid-breath, and the
    /// intro's skip must be able to silence the WHOLE score at once.
    private var scoreVoiceNodes: [AVAudioPlayerNode] = []
    private var scoreFadeTask: Task<Void, Never>?

    func playScoreVoice(_ sound: Sound) {
        guard readyToPlay(), let volume = effectiveVolume(for: sound.category) else { return }
        scoreFadeTask?.cancel()
        let node: AVAudioPlayerNode
        if let idle = scoreVoiceNodes.first(where: { !$0.isPlaying }) {
            node = idle
        } else {
            node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            scoreVoiceNodes.append(node)
        }
        node.stop()
        node.volume = Float(volume)
        // Rendered fresh, not cached: score voices play once per install —
        // caching would pin the 22 s bed (~8 MB) for the app's lifetime.
        node.scheduleBuffer(Self.makeBuffer(sound, format: format), at: nil)
        node.play()
    }

    /// Stops every score voice with a short fade — the skip's silence is
    /// soft, never a click. Safe to call when nothing plays.
    func stopScoreVoices(fadeOut: TimeInterval = 0.2) {
        let nodes = scoreVoiceNodes.filter(\.isPlaying)
        guard !nodes.isEmpty else { return }
        scoreFadeTask?.cancel()
        scoreFadeTask = Task {
            let startVolumes = nodes.map(\.volume)
            let steps = 6
            for step in 1...steps {
                do {
                    try await Task.sleep(nanoseconds: UInt64(fadeOut / Double(steps) * 1_000_000_000))
                } catch { break }
                let gain = Float(1 - Double(step) / Double(steps))
                for (node, v0) in zip(nodes, startVolumes) { node.volume = v0 * gain }
            }
            for (node, v0) in zip(nodes, startVolumes) {
                node.stop()
                node.volume = v0
            }
        }
    }

    // MARK: Playback plumbing

    private func readyToPlay() -> Bool {
        guard Self.enabled else { return false }
        prepare()
        guard started else { return false }
        if !engine.isRunning {
            try? engine.start()
        }
        return engine.isRunning
    }

    /// Per-category volume with music-ducking respect (Dossier 06, idea 20):
    /// while the couple's own music plays, interface ticks vanish entirely
    /// and everything else steps ~10 dB back. Returns nil to skip playback.
    private func effectiveVolume(for category: Category) -> Double? {
        var volume = Self.volume(for: category)
        let session = AVAudioSession.sharedInstance()
        if session.isOtherAudioPlaying || session.secondaryAudioShouldBeSilencedHint {
            guard category != .ui else { return nil }
            volume *= 0.32
        }
        return volume
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, volume: Double) {
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.volume = Float(volume)
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private func synthBuffer(for sound: Sound) -> AVAudioPCMBuffer {
        if let cached = buffers[sound] { return cached }
        let buffer = Self.makeBuffer(sound, format: format)
        buffers[sound] = buffer
        return buffer
    }

    // MARK: Bundled cue recordings

    /// Runtime gains (dB) from sound_credits.json — tuning a cue's loudness
    /// is a JSON edit, never a re-encode.
    private static let manifestGains: [String: Double] = {
        guard let url = Bundle.main.url(forResource: "sound_credits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? SoundCreditsManifest.load(from: data) else { return [:] }
        var gains: [String: Double] = [:]
        for entry in manifest.sounds {
            if let gain = entry.gain { gains[entry.cue] = gain }
        }
        return gains
    }()

    private func fileBuffer(for cue: AppCue) -> AVAudioPCMBuffer? {
        if let cached = cueFileBuffers[cue] { return cached }
        let buffer = Self.loadCueFile(cue, format: format)
        cueFileBuffers[cue] = buffer
        return buffer
    }

    /// Decodes `cue_<id>.caf` from the bundle into the engine format and
    /// applies the manifest gain. Any failure logs once (DEBUG) and returns
    /// nil — the app may never fall silent, and never crash over an audio
    /// file (the synthesis is always there).
    private static func loadCueFile(_ cue: AppCue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let resource = (cue.fileName as NSString).deletingPathExtension
        guard let url = Bundle.main.url(forResource: resource, withExtension: "caf") else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            let inFormat = file.processingFormat
            let frames = AVAudioFrameCount(file.length)
            guard frames > 0, let raw = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: frames) else {
                return nil
            }
            try file.read(into: raw)
            let converted: AVAudioPCMBuffer
            if inFormat == format {
                converted = raw
            } else {
                guard let converter = AVAudioConverter(from: inFormat, to: format) else { return nil }
                let ratio = format.sampleRate / inFormat.sampleRate
                let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
                guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
                    return nil
                }
                var fed = false
                var conversionError: NSError?
                converter.convert(to: out, error: &conversionError) { _, status in
                    if fed {
                        status.pointee = .endOfStream
                        return nil
                    }
                    fed = true
                    status.pointee = .haveData
                    return raw
                }
                if let conversionError { throw conversionError }
                converted = out
            }
            let gainDB = manifestGains[cue.rawValue] ?? 0
            if gainDB != 0, let channels = converted.floatChannelData {
                let factor = Float(pow(10, gainDB / 20))
                for channel in 0..<Int(converted.format.channelCount) {
                    for i in 0..<Int(converted.frameLength) {
                        channels[channel][i] *= factor
                    }
                }
            }
            return converted
        } catch {
            #if DEBUG
            print("SoundEngine: synthesis fallback for \(cue.rawValue) — \(error)")
            #endif
            return nil
        }
    }

    // MARK: Synthesis

    /// Renders one sound into a fresh stereo buffer. All numbers below are
    /// sound design, tuned by ear-math: frequencies are real notes, bell
    /// spectra use inharmonic partial ratios (~tuned percussion), and every
    /// envelope has a real attack so nothing clicks.
    private static func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let duration: Double
        switch sound {
        case .heartbeat: duration = 1.4
        case .chime: duration = 1.7
        case .pop: duration = 0.22
        case .whoosh: duration = 0.75
        case .tada: duration = 1.7
        case .sparkle: duration = 0.9
        case .click: duration = 0.08
        case .success: duration = 0.7
        case .letterSeal: duration = 0.7
        case .unlock: duration = 0.8
        case .win: duration = 2.0
        case .lose: duration = 1.0
        case .vibe: duration = 1.3
        case .swish: duration = 0.32
        // Cinematic score voices — lengths mirror CinematicScript's
        // soundLayers (bed: intro minus its 0.7 s entry; orbs: approach
        // until the 8.0 s merge; bloom: sub-swell + 1.5 s shimmer).
        case .cinematicBed: duration = 22.3
        case .cinematicOrbs: duration = 4.4
        case .cinematicBloom: duration = 2.6
        }
        let frames = Int(duration * sr)
        var left = [Float](repeating: 0, count: frames)
        var right = [Float](repeating: 0, count: frames)

        /// Attack-then-exponential-decay envelope.
        func env(_ t: Double, attack: Double, decay: Double) -> Double {
            t < attack ? t / max(attack, 1e-4) : exp(-(t - attack) * decay)
        }

        /// Layered partial voice, detuned between channels for width.
        /// `partials`: (ratio, relative amp); higher partials decay faster.
        func tone(start: Double, freq: Double, length: Double, amp: Double,
                  attack: Double = 0.006, decay: Double = 5,
                  partials: [(Double, Double)] = [(1, 1)],
                  detuneCents: Double = 3, pan: Double = 0) {
            let s0 = Int(start * sr)
            let n = Int(length * sr)
            let lGain = sqrt(0.5 * (1 - pan))
            let rGain = sqrt(0.5 * (1 + pan))
            let detune = pow(2, detuneCents / 1200)
            for i in 0..<n {
                let idx = s0 + i
                guard idx < frames else { break }
                let t = Double(i) / sr
                var vL = 0.0, vR = 0.0
                for (p, (ratio, pAmp)) in partials.enumerated() {
                    let pDecay = decay * (1 + 0.55 * Double(p))     // brights die first
                    let e = env(t, attack: attack, decay: pDecay)
                    vL += pAmp * e * sin(2 * .pi * freq * ratio / detune * t)
                    vR += pAmp * e * sin(2 * .pi * freq * ratio * detune * t)
                }
                left[idx] += Float(amp * vL * lGain * 2)
                right[idx] += Float(amp * vR * rGain * 2)
            }
        }

        /// Dreamy glass bell — inharmonic spectrum of struck idiophones.
        func bell(start: Double, freq: Double, amp: Double, decay: Double = 5,
                  detuneCents: Double = 3, pan: Double = 0) {
            tone(start: start, freq: freq, length: min(2.2, duration - start), amp: amp,
                 attack: 0.004, decay: decay,
                 partials: [(1, 1), (2.0, 0.5), (2.99, 0.28), (4.16, 0.16), (5.43, 0.08)],
                 detuneCents: detuneCents, pan: pan)
        }

        /// Pitch glide (pops, thumps): freq sweeps `from`→`to` over `length`.
        func glide(start: Double, from: Double, to: Double, length: Double,
                   amp: Double, decay: Double) {
            let s0 = Int(start * sr)
            let n = Int(length * sr)
            var phase = 0.0
            for i in 0..<n {
                let idx = s0 + i
                guard idx < frames else { break }
                let t = Double(i) / sr
                let x = t / length
                let f = from + (to - from) * x
                phase += 2 * .pi * f / sr
                let v = env(t, attack: 0.002, decay: decay) * sin(phase)
                left[idx] += Float(amp * v)
                right[idx] += Float(amp * v)
            }
        }

        /// Filtered noise with an animated low-pass (opening → closing) and
        /// decorrelated channels — air, paper, waves.
        func noise(start: Double, length: Double, amp: Double,
                   lpFrom: Double = 0.04, lpPeak: Double = 0.22, lpTo: Double = 0.04) {
            let s0 = Int(start * sr)
            let n = Int(length * sr)
            var stateL: UInt64 = 0x9E3779B97F4A7C15
            var stateR: UInt64 = 0xD1B54A32D192ED03
            var lpL = 0.0, lpR = 0.0
            for i in 0..<n {
                let idx = s0 + i
                guard idx < frames else { break }
                let x = Double(i) / Double(n)
                // low-pass coefficient sweeps: closed → open → closed
                let k = x < 0.4 ? lpFrom + (lpPeak - lpFrom) * (x / 0.4)
                                : lpPeak + (lpTo - lpPeak) * ((x - 0.4) / 0.6)
                stateL = stateL &* 6364136223846793005 &+ 1442695040888963407
                stateR = stateR &* 6364136223846793005 &+ 1442695040888963407
                let wL = (Double((stateL >> 33) & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
                let wR = (Double((stateR >> 33) & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
                lpL += k * (wL - lpL)
                lpR += k * (wR - lpR)
                let e = sin(.pi * x)
                left[idx] += Float(amp * e * lpL)
                right[idx] += Float(amp * e * lpR)
            }
        }

        /// Feedback delay over the whole buffer — the "dreamy" tail.
        func echo(delay: Double, feedback: Float) {
            let d = Int(delay * sr)
            guard d > 0 else { return }
            for i in d..<frames {
                left[i] += feedback * left[i - d]
                right[i] += feedback * right[i - d]
            }
        }

        switch sound {
        case .heartbeat:
            // Two warm lub-dubs: pitch-dropping thumps + a felt "skin" tap.
            for beat in [0.0, 0.72] {
                glide(start: beat, from: 64, to: 45, length: 0.20, amp: 0.85, decay: 15)
                noise(start: beat, length: 0.05, amp: 0.10, lpFrom: 0.03, lpPeak: 0.08, lpTo: 0.02)
                glide(start: beat + 0.17, from: 52, to: 40, length: 0.18, amp: 0.55, decay: 17)
            }

        case .chime:
            // E5 glass bell with a fifth shimmering in — the app's signature.
            bell(start: 0.00, freq: 659.25, amp: 0.20, decay: 4.5, detuneCents: 3, pan: -0.15)
            bell(start: 0.12, freq: 987.77, amp: 0.13, decay: 5.0, detuneCents: 4, pan: 0.2)
            echo(delay: 0.26, feedback: 0.32)

        case .pop:
            // Bubble kiss: fast pitch drop + a breath of air.
            glide(start: 0, from: 640, to: 90, length: 0.06, amp: 0.7, decay: 38)
            noise(start: 0, length: 0.03, amp: 0.08, lpFrom: 0.3, lpPeak: 0.4, lpTo: 0.2)

        case .whoosh:
            // A hug of air with a low warm swell underneath.
            noise(start: 0, length: 0.75, amp: 0.32)
            tone(start: 0.05, freq: 88, length: 0.6, amp: 0.10, attack: 0.2, decay: 4,
                 partials: [(1, 1), (2, 0.2)], detuneCents: 5)

        case .tada:
            // Rising C-major bell arpeggio with fairy dust on top.
            for (i, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                bell(start: Double(i) * 0.08, freq: f, amp: 0.14, decay: 4,
                     detuneCents: 3, pan: Double(i) * 0.12 - 0.18)
            }
            bell(start: 0.42, freq: 2093.0, amp: 0.05, decay: 8, pan: 0.3)
            bell(start: 0.52, freq: 2637.0, amp: 0.04, decay: 9, pan: -0.3)
            echo(delay: 0.24, feedback: 0.3)

        case .sparkle:
            // Three tiny glass stars, ascending.
            bell(start: 0.00, freq: 1318.5, amp: 0.10, decay: 8, pan: -0.25)
            bell(start: 0.09, freq: 1760.0, amp: 0.09, decay: 8, pan: 0.25)
            bell(start: 0.18, freq: 2217.5, amp: 0.08, decay: 7, pan: 0)
            echo(delay: 0.13, feedback: 0.28)

        case .click:
            // Barely-there UI tick.
            glide(start: 0, from: 1900, to: 1400, length: 0.02, amp: 0.16, decay: 90)

        case .success:
            // Gentle two-note confirm (E5 → B5).
            tone(start: 0.00, freq: 659.25, length: 0.35, amp: 0.14, decay: 7,
                 partials: [(1, 1), (2, 0.3)])
            tone(start: 0.11, freq: 987.77, length: 0.45, amp: 0.13, decay: 6,
                 partials: [(1, 1), (2, 0.25)])

        case .letterSeal:
            // Paper slide + wax press + a tiny bell kiss.
            noise(start: 0, length: 0.16, amp: 0.16, lpFrom: 0.12, lpPeak: 0.3, lpTo: 0.05)
            glide(start: 0.14, from: 150, to: 70, length: 0.12, amp: 0.4, decay: 22)
            bell(start: 0.3, freq: 1567.98, amp: 0.06, decay: 8)

        case .unlock:
            // Vault open: two quick metallic bells, upward (G5 → D6).
            bell(start: 0.00, freq: 783.99, amp: 0.12, decay: 7, detuneCents: 5)
            bell(start: 0.10, freq: 1174.66, amp: 0.11, decay: 6, detuneCents: 5)
            echo(delay: 0.15, feedback: 0.22)

        case .win:
            // A little fanfare: G-major lift with shimmer rain.
            for (i, f) in [392.0, 493.88, 587.33, 783.99].enumerated() {
                bell(start: Double(i) * 0.1, freq: f, amp: 0.15, decay: 3.4,
                     detuneCents: 4, pan: Double(i) * 0.12 - 0.18)
            }
            for (i, f) in [1567.98, 1975.53, 2349.32].enumerated() {
                bell(start: 0.55 + Double(i) * 0.07, freq: f, amp: 0.05, decay: 7,
                     pan: Double(i) * 0.25 - 0.25)
            }
            echo(delay: 0.27, feedback: 0.32)

        case .lose:
            // Sympathetic descending sigh (A4 → F4) — soft, never mocking.
            tone(start: 0.00, freq: 440.0, length: 0.4, amp: 0.12, attack: 0.02, decay: 6,
                 partials: [(1, 1), (2, 0.2)])
            tone(start: 0.22, freq: 349.23, length: 0.6, amp: 0.11, attack: 0.02, decay: 5,
                 partials: [(1, 1), (2, 0.15)])

        case .swish:
            // Send-swish: a short breath of air rising away from the hand —
            // the outgoing half of the sent/received question-answer pair.
            noise(start: 0, length: 0.3, amp: 0.22, lpFrom: 0.06, lpPeak: 0.3, lpTo: 0.12)
            glide(start: 0.02, from: 320, to: 520, length: 0.18, amp: 0.05, decay: 9)

        case .vibe:
            // Warm pad swell for incoming custom vibrations: detuned A-minor
            // triad breathing in and out.
            tone(start: 0, freq: 220.0, length: 1.25, amp: 0.10, attack: 0.3, decay: 3.2,
                 partials: [(1, 1), (2, 0.3)], detuneCents: 7, pan: -0.1)
            tone(start: 0.05, freq: 329.63, length: 1.2, amp: 0.08, attack: 0.32, decay: 3.2,
                 partials: [(1, 1), (2, 0.25)], detuneCents: 6, pan: 0.15)
            tone(start: 0.1, freq: 440.0, length: 1.1, amp: 0.07, attack: 0.35, decay: 3.4,
                 partials: [(1, 1)], detuneCents: 8, pan: 0)
            bell(start: 0.5, freq: 1760.0, amp: 0.04, decay: 8, pan: 0.2)
            echo(delay: 0.3, feedback: 0.25)

        case .cinematicBed:
            // Aurora bed: a barely-there A-major dawn pad (A2/E3/A3) with a
            // long shared breath and a whisper of air. decay≈0 → the tones
            // sustain; the manual end-fade below closes the buffer softly.
            tone(start: 0, freq: 110.0, length: duration, amp: 0.050, attack: 3.0,
                 decay: 0.02, partials: [(1, 1), (2, 0.25)], detuneCents: 6, pan: -0.12)
            tone(start: 1.2, freq: 164.81, length: duration - 1.2, amp: 0.040, attack: 3.4,
                 decay: 0.02, partials: [(1, 1), (2, 0.2)], detuneCents: 7, pan: 0.14)
            tone(start: 2.6, freq: 220.0, length: duration - 2.6, amp: 0.030, attack: 3.8,
                 decay: 0.02, partials: [(1, 1)], detuneCents: 9, pan: 0)
            noise(start: 0.5, length: duration - 0.5, amp: 0.020,
                  lpFrom: 0.02, lpPeak: 0.05, lpTo: 0.02)

        case .cinematicOrbs:
            // The approach, heard: each orb hums on its own stereo side —
            // A3 left, E4 right, a fifth apart — and the long attacks
            // crescendo the whole way so the tones resolve INTO the merge.
            tone(start: 0, freq: 220.0, length: duration, amp: 0.085, attack: 3.4,
                 decay: 0.03, partials: [(1, 1), (2, 0.2)], detuneCents: 6, pan: -0.75)
            tone(start: 0.3, freq: 329.63, length: duration - 0.3, amp: 0.075, attack: 3.2,
                 decay: 0.03, partials: [(1, 1), (2, 0.18)], detuneCents: 7, pan: 0.75)

        case .cinematicBloom:
            // The merge, heard from below and above: a sub-swell rises out
            // of the floor, then a 1.5 s shimmer of tiny glass stars rains
            // outward, alternating sides — the couple blend as sound.
            tone(start: 0, freq: 44.0, length: 1.3, amp: 0.34, attack: 0.35, decay: 2.6,
                 partials: [(1, 1), (2, 0.12)], detuneCents: 4, pan: 0)
            for (i, freq) in [1567.98, 1975.53, 2349.32, 2637.02, 3135.96, 2093.0].enumerated() {
                bell(start: 0.28 + Double(i) * 0.24, freq: freq, amp: 0.045, decay: 6,
                     detuneCents: 5, pan: (i.isMultiple(of: 2) ? -1 : 1) * (0.2 + 0.1 * Double(i)))
            }
            echo(delay: 0.22, feedback: 0.28)
        }

        // Score voices sustain instead of decaying — close them with a
        // gentle end-fade so a full-length bed never clicks off.
        switch sound {
        case .cinematicBed, .cinematicOrbs:
            let fadeFrames = min(frames, Int(1.2 * sr))
            for i in 0..<fadeFrames {
                let gain = Float(i) / Float(fadeFrames)
                left[frames - 1 - i] *= gain
                right[frames - 1 - i] *= gain
            }
        default:
            break
        }

        // Soft-knee saturation (analog-ish, no hard clipping artifacts).
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let outL = buffer.floatChannelData![0]
        let outR = buffer.floatChannelData![1]
        let norm = Float(tanh(1.6))
        for i in 0..<frames {
            outL[i] = tanhf(1.6 * left[i]) / norm * 0.92
            outR[i] = tanhf(1.6 * right[i]) / norm * 0.92
        }
        return buffer
    }
}

extension AppCue {
    /// The procedural voice of this cue — the eternal fallback, and the
    /// dream layer of hybrid cues. Exhaustive by design: EVERY cue can
    /// always sound, bundled recording or not.
    var synthSound: SoundEngine.Sound {
        switch self {
        case .received, .kiss, .fanfareSmall: return .pop
        case .sent: return .swish
        case .sealed, .unseal: return .letterSeal
        case .hug: return .whoosh
        case .heartbeat: return .heartbeat
        case .sparkle, .reveal, .fanfareMedium: return .sparkle
        case .vibe: return .vibe
        case .pairing: return .tada
        case .chime: return .chime
        case .click, .chip: return .click
        case .success: return .success
        case .unlock: return .unlock
        case .drop, .dice, .hit: return .pop
        case .fanfareEpic: return .win
        case .lose: return .lose
        case .splash: return .whoosh
        }
    }
}
