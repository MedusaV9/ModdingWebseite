import XCTest
@testable import SoooDreamyLogic

/// The license gate and bundle discipline for the sound package (Dossier 47,
/// section g): every cue has a file OR synthesis, every recording has a clean
/// license, CC-BY attribution can never be forgotten, and no orphan asset
/// hides in the bundle. Runs on Linux against the repo checkout via #filePath.
final class SoundManifestTests: XCTestCase {

    /// Package root (ios/), derived from this file's location.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/

    private static let soundsDir = packageDir
        .appendingPathComponent("SoooDreamy/Resources/Sounds", isDirectory: true)

    private static let budgetPerCue = 120 * 1024
    private static let budgetTotal = 1_536_000

    private func loadManifest() throws -> SoundCreditsManifest {
        let url = Self.soundsDir.appendingPathComponent("sound_credits.json")
        let data = try Data(contentsOf: url)
        return try SoundCreditsManifest.load(from: data)
    }

    /// Audio files actually present in Resources/Sounds (excluding the
    /// separate notif_* inventory for UNNotificationSound and the manifest).
    private func bundledCueFiles() throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.soundsDir.path)
        return Set(names.filter { !$0.hasPrefix("notif_") && !$0.hasSuffix(".json") })
    }

    // MARK: Schema + completeness

    func testManifestPassesEveryValidationRule() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest.version, 1)
        let issues = manifest.validationIssues(existingFiles: try bundledCueFiles())
        XCTAssertTrue(issues.isEmpty, "manifest violations:\n" + issues.joined(separator: "\n"))
    }

    /// The core guarantee: EVERY cue in the vocabulary is playable — either
    /// it ships a bundled recording, or it stays procedural synthesis.
    func testEveryCueHasFileOrSynthesis() throws {
        let manifest = try loadManifest()
        let files = try bundledCueFiles()
        for cue in AppCue.allCases {
            let entry = try XCTUnwrap(manifest.entry(for: cue),
                                      "cue \(cue.rawValue) missing from manifest")
            switch entry.mode {
            case .synth:
                XCTAssertNil(entry.file, "\(cue.rawValue): synth cues carry no file")
            case .sample, .hybrid:
                XCTAssertTrue(files.contains(cue.fileName),
                              "\(cue.rawValue): \(cue.fileName) missing from Resources/Sounds")
            }
        }
    }

    /// The manifest must mirror the catalog verdicts — plan and bundle may
    /// never drift apart.
    func testManifestModesMatchCatalogVerdicts() throws {
        let manifest = try loadManifest()
        for cue in AppCue.allCases {
            XCTAssertEqual(manifest.entry(for: cue)?.mode, cue.plannedMode,
                           "mode drift for \(cue.rawValue)")
        }
    }

    // MARK: License gate

    func testEveryRecordingCarriesAnAllowlistedLicense() throws {
        let manifest = try loadManifest()
        for entry in manifest.sounds where entry.mode != .synth {
            let source = try XCTUnwrap(entry.source, "\(entry.cue): recording without source")
            XCTAssertTrue(SoundCreditsManifest.allowedLicenses.contains(source.license),
                          "\(entry.cue): license \(source.license) not allowed")
            XCTAssertFalse(source.title.isEmpty, "\(entry.cue): source title missing")
            XCTAssertFalse(source.author.isEmpty, "\(entry.cue): author missing")
            XCTAssertFalse(source.url.isEmpty, "\(entry.cue): source url missing")
            XCTAssertFalse(source.sha256?.isEmpty ?? true,
                           "\(entry.cue): raw-file sha256 receipt missing")
        }
    }

    /// CC-BY attribution is MANDATORY — author, title, url and an edits note.
    /// This test makes it impossible to ship a CC-BY file without credits.
    func testCCByEntriesCarryFullAttribution() throws {
        let manifest = try loadManifest()
        for entry in manifest.attributionRequired {
            let source = try XCTUnwrap(entry.source)
            XCTAssertFalse(source.author.isEmpty, "\(entry.cue): CC-BY needs the author")
            XCTAssertFalse(source.title.isEmpty, "\(entry.cue): CC-BY needs the title")
            XCTAssertFalse(source.url.isEmpty, "\(entry.cue): CC-BY needs the source url")
            XCTAssertFalse(source.edits?.isEmpty ?? true,
                           "\(entry.cue): CC-BY requires documenting edits")
        }
    }

    // MARK: Bundle discipline

    func testCueFilesRespectFormatAndBudget() throws {
        let files = try bundledCueFiles()
        var total = 0
        for name in files.sorted() {
            XCTAssertTrue(name.hasSuffix(".caf"), "\(name): cues are CAF/PCM16 (no AAC priming)")
            let url = Self.soundsDir.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            XCTAssertGreaterThan(data.count, 44, "\(name): suspiciously small")
            XCTAssertLessThanOrEqual(data.count, Self.budgetPerCue,
                                     "\(name): exceeds the 120 KB per-cue budget")
            XCTAssertEqual(data.prefix(4), Data("caff".utf8), "\(name): missing CAF magic bytes")
            total += data.count
        }
        XCTAssertLessThanOrEqual(total, Self.budgetTotal,
                                 "cue files exceed the 1.5 MB total budget (\(total) bytes)")
    }

    /// No orphan assets: every audio file in Sounds/ (apart from the notif_*
    /// inventory) must be credited in the manifest — no license corpses.
    func testNoOrphanAudioFiles() throws {
        let manifest = try loadManifest()
        let referenced = Set(manifest.sounds.compactMap(\.file))
        for name in try bundledCueFiles() {
            XCTAssertTrue(referenced.contains(name),
                          "\(name) is bundled but not credited in sound_credits.json")
        }
    }

    /// Naming is deterministic: manifest files must be cue_<id>.caf.
    func testFileNamesDeriveFromCueIds() throws {
        let manifest = try loadManifest()
        for entry in manifest.sounds {
            guard let file = entry.file else { continue }
            XCTAssertEqual(file, "cue_\(entry.cue).caf", "\(entry.cue): free-form file name")
        }
    }
}
