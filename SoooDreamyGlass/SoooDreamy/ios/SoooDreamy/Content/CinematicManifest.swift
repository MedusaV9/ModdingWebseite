import Foundation

// FullRelease N3-Kino — the decoder for the haptics manifests that ride
// next to every CI-rendered cinema video (`scene2.haptics.json` beside
// `scene2_envelope.mp4`, flat in the bundle). One TypeScript timeline in
// `SoooDreamy/remotion/src` exports frames AND beats, so picture and
// haptics can never drift — this file is the app-side half of that
// contract (RECON_REMOTION_PIPELINE.md §3.6).
//
// Foundation-only by design: the player (AVFoundation) lives in
// Kino/; parsing and validation live HERE so the Linux
// logic tests can pin the format against string-literal fixtures. A
// manifest that fails `validationIssues()` is treated like a missing
// video — the chapter falls back to its procedural Kurzfassung, the
// cinema never crashes and never goes black.

/// One beat row: the wire twin of `HapticEventSpec` (t/i/s/d) plus the
/// render-side `type` tag Remotion uses for its own preview overlay —
/// the app plays the numbers, not the label.
struct CinematicManifestBeat: Codable, Equatable {
    let t: Double
    let type: String?
    let i: Double
    let s: Double
    /// Absent in older manifests — a missing duration means a transient.
    let d: Double?

    /// The app-side event this beat plays (`CinematicHapticScore`).
    var event: HapticEventSpec {
        HapticEventSpec(t: t, i: i, s: s, d: d ?? 0)
    }
}

/// One sound cue row: `id` addresses the existing `AppCue` vocabulary —
/// the manifest may never invent sounds, only schedule the catalog.
struct CinematicManifestCue: Codable, Equatable {
    let t: Double
    let id: String

    /// Resolved against the catalog; nil = unknown id (a validation issue).
    var appCue: AppCue? { AppCue(rawValue: id) }
}

/// One caption row: the videos are text-free by design — SwiftUI renders
/// these words (Dynamic Type, VoiceOver), never the pixels.
struct CinematicManifestCaption: Codable, Equatable {
    let t: Double
    let end: Double
    let de: String
    let en: String
}

/// A decoded `*.haptics.json` manifest. Decoding is strict about shape
/// (missing required keys throw), tolerant about extras (unknown keys
/// are ignored) — CI may grow the format without breaking old players.
struct CinematicManifest: Codable, Equatable {
    /// File name of the video this manifest belongs to (with extension).
    let video: String
    /// Remotion composition id — provenance, unused by the player.
    let composition: String?
    let fps: Double
    let durationSec: Double
    /// Reduce-Motion still frame (and preview poster) — seconds.
    let posterTime: Double
    let beats: [CinematicManifestBeat]
    let cues: [CinematicManifestCue]
    /// Optional — the three committed look-scenes are caption-free
    /// (their words live in OnboardingL10n as chapter captions).
    let captions: [CinematicManifestCaption]?

    // MARK: Decoding

    static func decode(_ data: Data) throws -> CinematicManifest {
        try JSONDecoder().decode(CinematicManifest.self, from: data)
    }

    static func decode(json: String) throws -> CinematicManifest {
        try decode(Data(json.utf8))
    }

    // MARK: Player-side projections

    /// All beats as app events, in manifest order.
    var hapticEvents: [HapticEventSpec] { beats.map(\.event) }

    /// Cues resolved against the catalog, unknown ids dropped (the
    /// validation names them; playback stays fail-soft).
    var resolvedCues: [(time: Double, cue: AppCue)] {
        cues.compactMap { cue in
            cue.appCue.map { (time: cue.t, cue: $0) }
        }
    }

    /// The sorted, de-duplicated union of beat starts and cue times —
    /// exactly the times the player hands to
    /// `AVPlayer.addBoundaryTimeObserver(forTimes:)`.
    var boundaryTimes: [Double] {
        Array(Set(beats.map(\.t) + cues.map(\.t))).sorted()
    }

    /// The caption under the playhead, if any.
    func caption(at t: Double) -> CinematicManifestCaption? {
        captions?.first { t >= $0.t && t < $0.end }
    }

    // MARK: Validation — pure, exhaustive, Linux-tested

    enum Issue: Equatable {
        case nonPositiveDuration
        case nonPositiveFPS
        case posterTimeOutsideVideo
        /// Beat starts before 0 or its tail spills past the video.
        case beatOutsideVideo(index: Int)
        /// Intensity or sharpness outside 0…1.
        case beatOutOfUnitRange(index: Int)
        case cueOutsideVideo(index: Int)
        /// The id is not part of the `AppCue` catalog.
        case unknownCue(id: String)
        case captionOutsideVideo(index: Int)
        case captionMissingText(index: Int)
    }

    /// Every rule the CI gate checks, re-checked on the playing side —
    /// a manifest with issues downgrades its chapter to the procedural
    /// Kurzfassung instead of firing beats into the wrong frames.
    func validationIssues() -> [Issue] {
        var issues: [Issue] = []
        if durationSec <= 0 { issues.append(.nonPositiveDuration) }
        if fps <= 0 { issues.append(.nonPositiveFPS) }
        if posterTime < 0 || posterTime >= durationSec {
            issues.append(.posterTimeOutsideVideo)
        }
        for (index, beat) in beats.enumerated() {
            if beat.t < 0 || beat.t + (beat.d ?? 0) > durationSec {
                issues.append(.beatOutsideVideo(index: index))
            }
            if !(0...1).contains(beat.i) || !(0...1).contains(beat.s) {
                issues.append(.beatOutOfUnitRange(index: index))
            }
        }
        for (index, cue) in cues.enumerated() {
            if cue.t < 0 || cue.t >= durationSec {
                issues.append(.cueOutsideVideo(index: index))
            }
            if cue.appCue == nil {
                issues.append(.unknownCue(id: cue.id))
            }
        }
        for (index, caption) in (captions ?? []).enumerated() {
            if caption.t < 0 || caption.end <= caption.t || caption.end > durationSec {
                issues.append(.captionOutsideVideo(index: index))
            }
            if caption.de.isEmpty || caption.en.isEmpty {
                issues.append(.captionMissingText(index: index))
            }
        }
        return issues
    }

    var isValid: Bool { validationIssues().isEmpty }
}
