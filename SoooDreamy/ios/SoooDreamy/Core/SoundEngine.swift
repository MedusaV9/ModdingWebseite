import Foundation
import AVFoundation

/// All app sounds are synthesized in code (no bundled audio assets):
/// soft heartbeats, chimes, pops. Mixes politely with the user's music.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sooodreamy.soundsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.soundsEnabled") }
    }

    enum Sound: CaseIterable {
        case heartbeat, chime, pop, whoosh, tada, sparkle
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
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
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try engine.start()
            started = true
        } catch {
            started = false
        }
    }

    func play(_ sound: Sound) {
        guard Self.enabled else { return }
        prepare()
        guard started else { return }
        if !engine.isRunning {
            try? engine.start()
            guard engine.isRunning else { return }
        }
        let buffer = buffers[sound] ?? Self.makeBuffer(sound, format: format)
        buffers[sound] = buffer
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    func play(for kind: TouchKind) {
        switch kind {
        case .heartbeat: play(.heartbeat)
        case .kiss: play(.pop)
        case .hug: play(.whoosh)
        case .missyou: play(.sparkle)
        case .tickle: play(.sparkle)
        case .thinking: play(.chime)
        }
    }

    // MARK: Synthesis

    private static func makeBuffer(_ sound: Sound, format: AVAudioFormat) -> AVAudioPCMBuffer {
        let sr = format.sampleRate
        let duration: Double
        switch sound {
        case .heartbeat: duration = 1.3
        case .chime: duration = 1.0
        case .pop: duration = 0.25
        case .whoosh: duration = 0.6
        case .tada: duration = 1.2
        case .sparkle: duration = 0.6
        }
        let frames = AVAudioFrameCount(duration * sr)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for i in 0..<Int(frames) { samples[i] = 0 }

        func addTone(start: Double, freq: Double, length: Double, amp: Double, decay: Double, harmonic2: Double = 0) {
            let s0 = Int(start * sr)
            let n = Int(length * sr)
            for i in 0..<n {
                let idx = s0 + i
                guard idx < Int(frames) else { break }
                let t = Double(i) / sr
                let env = exp(-t * decay)
                var v = sin(2 * .pi * freq * t)
                if harmonic2 > 0 { v += harmonic2 * sin(4 * .pi * freq * t) }
                samples[idx] += Float(amp * env * v)
            }
        }

        func addNoise(start: Double, length: Double, amp: Double) {
            let s0 = Int(start * sr)
            let n = Int(length * sr)
            var state: UInt64 = 0x9E3779B97F4A7C15
            var lp: Double = 0
            for i in 0..<n {
                let idx = s0 + i
                guard idx < Int(frames) else { break }
                state = state &* 6364136223846793005 &+ 1442695040888963407
                let white = (Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)) * 2 - 1
                lp += 0.08 * (white - lp)   // cheap low-pass
                let x = Double(i) / Double(n)
                let env = sin(.pi * x)      // swell in & out
                samples[idx] += Float(amp * env * lp)
            }
        }

        switch sound {
        case .heartbeat:
            addTone(start: 0.00, freq: 58, length: 0.24, amp: 0.9, decay: 16)
            addTone(start: 0.17, freq: 47, length: 0.22, amp: 0.6, decay: 18)
            addTone(start: 0.72, freq: 58, length: 0.24, amp: 0.9, decay: 16)
            addTone(start: 0.89, freq: 47, length: 0.22, amp: 0.6, decay: 18)
        case .chime:
            addTone(start: 0.00, freq: 659.25, length: 0.9, amp: 0.28, decay: 5, harmonic2: 0.3)
            addTone(start: 0.10, freq: 783.99, length: 0.8, amp: 0.24, decay: 5, harmonic2: 0.3)
            addTone(start: 0.20, freq: 1046.50, length: 0.7, amp: 0.22, decay: 5, harmonic2: 0.2)
        case .pop:
            let s0 = 0
            let n = Int(0.09 * sr)
            for i in 0..<n {
                let t = Double(i) / sr
                let f = 320 - 2400 * t
                let env = exp(-t * 40)
                samples[s0 + i] += Float(0.8 * env * sin(2 * .pi * max(f, 70) * t))
            }
        case .whoosh:
            addNoise(start: 0, length: 0.6, amp: 0.35)
        case .tada:
            addTone(start: 0.00, freq: 523.25, length: 0.9, amp: 0.22, decay: 4, harmonic2: 0.25)
            addTone(start: 0.09, freq: 659.25, length: 0.9, amp: 0.22, decay: 4, harmonic2: 0.25)
            addTone(start: 0.18, freq: 783.99, length: 0.9, amp: 0.22, decay: 4, harmonic2: 0.25)
            addTone(start: 0.27, freq: 1046.50, length: 0.9, amp: 0.26, decay: 3.5, harmonic2: 0.2)
        case .sparkle:
            addTone(start: 0.00, freq: 1318.5, length: 0.25, amp: 0.16, decay: 12)
            addTone(start: 0.08, freq: 1760.0, length: 0.25, amp: 0.14, decay: 12)
            addTone(start: 0.16, freq: 2093.0, length: 0.30, amp: 0.12, decay: 10)
        }

        // Gentle limiter
        for i in 0..<Int(frames) {
            let v = samples[i]
            samples[i] = max(-0.95, min(0.95, v))
        }
        return buffer
    }
}
