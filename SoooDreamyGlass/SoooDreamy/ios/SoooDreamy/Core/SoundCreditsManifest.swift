import Foundation

// Resources/Sounds/sound_credits.json is the single source of truth for
// every bundled recording: which cue it serves, where it came from, under
// which license, and how loud it plays (runtime gain in dB — tuning is a
// JSON edit, never a re-encode). The Settings credits panel renders from it,
// docs/CREDITS.md is regenerated from it, and the Linux LogicTests enforce
// its rules — compliance is code, not process documentation.

struct SoundCreditsManifest: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var cue: String
        var mode: CueRenderMode
        /// Bundle file — required for sample/hybrid, forbidden for synth.
        var file: String?
        /// Runtime gain in dB, calibrated by ear against the synth chime.
        var gain: Double?
        /// Provenance — required for sample/hybrid, absent for synth.
        var source: Source?
    }

    struct Source: Codable, Equatable {
        var title: String
        var author: String
        var url: String
        var license: String
        var licenseUrl: String?
        var downloadedAt: String?
        /// SHA-256 of the RAW downloaded file (originals stay out of the
        /// repo in tools/sound_sources/, gitignored — this is the receipt).
        var sha256: String?
        /// CC-BY requires documenting changes; we document them for CC0 too.
        var edits: String?
    }

    var version: Int
    var sounds: [Entry]

    /// The only licenses that may ever enter the bundle.
    static let allowedLicenses: Set<String> = ["CC0-1.0", "CC-BY-3.0", "CC-BY-4.0", "Pixabay"]

    /// Sane runtime-gain window: quieter is always allowed, but nothing may
    /// be boosted into startling territory.
    static let gainRange: ClosedRange<Double> = -24...6

    static func load(from data: Data) throws -> SoundCreditsManifest {
        try JSONDecoder().decode(SoundCreditsManifest.self, from: data)
    }

    func entry(for cue: AppCue) -> Entry? {
        sounds.first { $0.cue == cue.rawValue }
    }

    /// Entries whose license makes attribution MANDATORY (CC-BY family).
    var attributionRequired: [Entry] {
        sounds.filter { $0.source?.license.hasPrefix("CC-BY") == true }
    }

    /// Entries with a bundled recording under a no-attribution license
    /// (CC0/Pixabay) — thanked voluntarily in the credits panel.
    var voluntaryCredits: [Entry] {
        sounds.filter { $0.source != nil && $0.source?.license.hasPrefix("CC-BY") != true }
    }

    /// All manifest rules in one place; the LogicTests assert this comes
    /// back empty, so a violation breaks CI before it can ship.
    /// `existingFiles` = file names actually present in Resources/Sounds.
    func validationIssues(existingFiles: Set<String>) -> [String] {
        var issues: [String] = []

        let knownCues = Set(AppCue.allCases.map(\.rawValue))
        var seen: Set<String> = []
        for entry in sounds {
            if !knownCues.contains(entry.cue) {
                issues.append("unknown cue '\(entry.cue)' in manifest")
            }
            if !seen.insert(entry.cue).inserted {
                issues.append("duplicate manifest entry for cue '\(entry.cue)'")
            }
        }

        for cue in AppCue.allCases {
            guard let entry = entry(for: cue) else {
                issues.append("cue '\(cue.rawValue)' missing from manifest")
                continue
            }
            if entry.mode != cue.plannedMode {
                issues.append("cue '\(cue.rawValue)' mode \(entry.mode.rawValue) contradicts catalog verdict \(cue.plannedMode.rawValue)")
            }
            switch entry.mode {
            case .synth:
                if entry.file != nil {
                    issues.append("synth cue '\(cue.rawValue)' must not name a file")
                }
                if entry.source != nil {
                    issues.append("synth cue '\(cue.rawValue)' must not carry a source — it is original synthesis")
                }
            case .sample, .hybrid:
                if entry.file != cue.fileName {
                    issues.append("cue '\(cue.rawValue)' file must be \(cue.fileName) (deterministic naming)")
                }
                if !existingFiles.contains(cue.fileName) {
                    issues.append("cue '\(cue.rawValue)' names \(cue.fileName) but the file is not in Resources/Sounds")
                }
                guard let source = entry.source else {
                    issues.append("cue '\(cue.rawValue)' has a recording but no source credit")
                    continue
                }
                if !Self.allowedLicenses.contains(source.license) {
                    issues.append("cue '\(cue.rawValue)' license '\(source.license)' is not on the allowlist")
                }
                if source.title.isEmpty || source.author.isEmpty || source.url.isEmpty {
                    issues.append("cue '\(cue.rawValue)' source needs title, author and url")
                }
                if source.license.hasPrefix("CC-BY"),
                   source.edits?.isEmpty != false {
                    issues.append("cue '\(cue.rawValue)' is CC-BY and must document its edits")
                }
                if let gain = entry.gain, !Self.gainRange.contains(gain) {
                    issues.append("cue '\(cue.rawValue)' gain \(gain) dB is outside \(Self.gainRange)")
                }
            }
        }
        return issues
    }
}
