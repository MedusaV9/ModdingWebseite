import Foundation
import AVFoundation
import Observation
#if canImport(Speech)
import Speech
#endif

// The ONLY file that touches the iOS-26 SpeechAnalyzer stack — a thin
// facade over on-device transcription of voice notes (Welle 7 [28]).
// The cache contract and the locale matching live in
// Content/ChatLanguageRules.swift (Linux-testable).
//
// Privacy contract: the audio is fetched over the couple's own server
// exactly like playback does, transcribed ON DEVICE, and the resulting
// text is cached ONLY in local UserDefaults per couple — a transcript
// never travels to any server, in no field, ever.

/// What one voice note's transcript can be, as the bubble renders it.
enum VoiceTranscriptState: Equatable {
    /// Transcribing (which may include the one-time on-device model
    /// download the system performs into system storage).
    case working
    case done(String)
    /// Honest failure line (l10n key) — unsupported language, unreadable
    /// audio, or the engine gave up.
    case failed(String)
}

@MainActor
@Observable
final class VoiceTranscriptCenter {
    static let shared = VoiceTranscriptCenter()

    private(set) var states: [String: VoiceTranscriptState] = [:]
    /// Voice bubbles currently showing their transcript block.
    private(set) var expanded: Set<String> = []

    /// Couple scope of the live cache — switching couples swaps the
    /// cache and collapses everything.
    private var coupleId: String?
    private var cache: [VoiceTranscriptCacheEntry] = []

    private init() {}

    private static func cacheKey(_ coupleId: String) -> String {
        "sooodreamy.voiceTranscripts.\(coupleId)"
    }

    /// Rebinds the center to the active couple (chat appear / profile
    /// switch). A transcript from couple A never surfaces in couple B.
    func configure(coupleId newCoupleId: String?) {
        guard coupleId != newCoupleId else { return }
        coupleId = newCoupleId
        states = [:]
        expanded = []
        cache = Self.loadCache(coupleId: newCoupleId)
    }

    func isShowing(_ messageId: String) -> Bool {
        expanded.contains(messageId) && states[messageId] != nil
    }

    /// The state a bubble renders below the waveform (nil = collapsed).
    func visibleState(for messageId: String) -> VoiceTranscriptState? {
        guard expanded.contains(messageId) else { return nil }
        return states[messageId]
    }

    func hideTranscript(for messageId: String) {
        expanded.remove(messageId)
    }

    /// Context action: show the transcript — instantly from the local
    /// cache when this note was transcribed before, otherwise via a
    /// fresh on-device analyzer run.
    func requestTranscript(message: Message, api: API?) {
        let id = message.id
        expanded.insert(id)
        if let cached = cache.first(where: { $0.id == id })?.text {
            states[id] = .done(cached)
            return
        }
        if case .working = states[id] { return }  // already in flight
        if case .done = states[id] { return }     // kept from this run
        guard let api, let path = message.audioUrl else {
            states[id] = .failed("chat.transcript.failed")
            return
        }
        states[id] = .working
        Task { await transcribe(id: id, path: path, api: api) }
    }

    // MARK: On-device analyzer run

    private func transcribe(id: String, path: String, api: API) async {
        #if canImport(Speech)
        do {
            // 1. Honest language limits: the app language picks the model.
            let supported = await SpeechTranscriber.supportedLocales
                .map { $0.identifier(.bcp47) }
            guard let localeId = VoiceTranscriptRules.matchingLocaleIdentifier(
                appLanguage: L10n.lang, supportedBCP47: supported) else {
                states[id] = .failed("chat.transcript.unsupported")
                return
            }
            // 2. Fetch the audio over the authenticated media path and
            //    park it in a temp file for the analyzer.
            let data = try await api.mediaData(path)
            let fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("transcript-\(UUID().uuidString).m4a")
            try data.write(to: fileURL)
            defer { try? FileManager.default.removeItem(at: fileURL) }
            // 3. Transcribe on device.
            let raw = try await Self.transcribeFile(at: fileURL,
                                                    localeIdentifier: localeId)
            let text = VoiceTranscriptRules.normalizedTranscript(raw)
            guard !text.isEmpty else {
                states[id] = .failed("chat.transcript.empty")
                return
            }
            states[id] = .done(text)
            storeInCache(id: id, text: text)
        } catch {
            states[id] = .failed("chat.transcript.failed")
        }
        #else
        states[id] = .failed("chat.transcript.unsupported")
        #endif
    }

    #if canImport(Speech)
    /// One-shot file transcription, straight from the documented
    /// SpeechAnalyzer pattern: results are consumed concurrently while
    /// `analyzeSequence` feeds the file through the analyzer. The model
    /// assets live in system storage; `downloadAndInstall` is a no-op
    /// once they are present.
    ///
    /// Configuration note: the WWDC25 sample's `.offlineTranscription`
    /// preset did NOT ship — the released `SpeechTranscriber.Preset` only
    /// has `transcription`/`progressiveTranscription`/… . We use the
    /// explicit initializer with EMPTY option sets, which per the Preset
    /// docs table is exactly the `transcription` row (no volatile, no
    /// fast, no alternative results, no time ranges): batch-style finals
    /// only. On-device is not a preset property but the architecture:
    /// SpeechTranscriber's model runs locally by design, AssetInventory
    /// installs it into SYSTEM storage, and after that no network is
    /// involved in transcription ("offline" in the beta name meant
    /// non-live batch audio, not network state).
    private static func transcribeFile(at url: URL,
                                       localeIdentifier: String) async throws -> String {
        let locale = Locale(identifier: localeIdentifier)
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        async let collected = collectText(from: transcriber)
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected
    }

    /// Concatenates the result segments into one plain string. With empty
    /// reporting options the transcriber delivers ONLY finalized results
    /// (volatile/fast results are opt-in), so every segment counts.
    private static func collectText(from transcriber: SpeechTranscriber) async throws -> String {
        var text = ""
        for try await result in transcriber.results {
            text += String(result.text.characters) + " "
        }
        return text
    }
    #endif

    // MARK: Local cache (UserDefaults, per couple, capped)

    private func storeInCache(id: String, text: String) {
        cache = VoiceTranscriptRules.appending(
            VoiceTranscriptCacheEntry(id: id, text: text), to: cache)
        guard let coupleId else { return }
        if let encoded = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey(coupleId))
        }
    }

    private static func loadCache(coupleId: String?) -> [VoiceTranscriptCacheEntry] {
        guard let coupleId,
              let data = UserDefaults.standard.data(forKey: cacheKey(coupleId)),
              let entries = try? JSONDecoder().decode([VoiceTranscriptCacheEntry].self, from: data) else {
            return []
        }
        return entries
    }
}
