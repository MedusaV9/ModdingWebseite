import XCTest
@testable import SoooDreamyLogic

/// The haptics-manifest contract (FullRelease N3-Kino). The fixtures are
/// verbatim copies of the committed manifests in
/// `SoooDreamy/remotion/manifests/` — one TypeScript timeline exports
/// frames AND beats, and THESE tests pin that the app-side decoder, the
/// validation rules and `CinematicScript`'s video chapters agree with
/// exactly that export. Change a manifest, change these fixtures — the
/// drift becomes a red test instead of a beat in the wrong frame.
final class CinematicManifestTests: XCTestCase {

    // MARK: Fixtures — verbatim committed manifests

    private let scene2JSON = """
    {
      "video": "scene2_envelope.mp4",
      "composition": "Scene2Envelope",
      "fps": 30,
      "durationSec": 8,
      "posterTime": 6.8,
      "beats": [
        { "t": 3, "type": "soft", "i": 0.45, "s": 0.3, "d": 0.22 },
        { "t": 5.2, "type": "tap", "i": 0.9, "s": 0.62, "d": 0 },
        { "t": 5.34, "type": "soft", "i": 0.32, "s": 0.2, "d": 0.16 }
      ],
      "cues": [
        { "t": 3, "id": "drop" },
        { "t": 5.2, "id": "sealed" }
      ]
    }
    """

    private let scene3JSON = """
    {
      "video": "scene3_seal.mp4",
      "composition": "Scene3SealBreak",
      "fps": 30,
      "durationSec": 10,
      "posterTime": 8.6,
      "beats": [
        { "t": 1.2, "type": "soft", "i": 0.35, "s": 0.2, "d": 0.9 },
        { "t": 2.4, "type": "tap", "i": 0.85, "s": 0.72, "d": 0 },
        { "t": 2.56, "type": "tap", "i": 0.4, "s": 0.5, "d": 0 },
        { "t": 3.6, "type": "soft", "i": 0.3, "s": 0.15, "d": 0.5 },
        { "t": 4.5, "type": "soft", "i": 0.26, "s": 0.15, "d": 0.4 },
        { "t": 5.4, "type": "success", "i": 0.5, "s": 0.5, "d": 0 },
        { "t": 5.51, "type": "success", "i": 0.65, "s": 0.55, "d": 0 }
      ],
      "cues": [
        { "t": 2.4, "id": "unseal" },
        { "t": 3.6, "id": "reveal" }
      ]
    }
    """

    private let scene6JSON = """
    {
      "video": "scene6_polaroid.mp4",
      "composition": "Scene6Polaroid",
      "fps": 30,
      "durationSec": 8,
      "posterTime": 7.2,
      "beats": [
        { "t": 1.4, "type": "soft", "i": 0.5, "s": 0.35, "d": 0 },
        { "t": 2.2, "type": "tap", "i": 0.22, "s": 0.4, "d": 0 },
        { "t": 2.9, "type": "tap", "i": 0.16, "s": 0.4, "d": 0 },
        { "t": 5.8, "type": "success", "i": 0.5, "s": 0.5, "d": 0 },
        { "t": 5.91, "type": "success", "i": 0.65, "s": 0.55, "d": 0 }
      ],
      "cues": [
        { "t": 1.4, "id": "drop" },
        { "t": 5.8, "id": "chime" }
      ]
    }
    """

    private var allFixtures: [String: String] {
        ["scene2.haptics": scene2JSON,
         "scene3.haptics": scene3JSON,
         "scene6.haptics": scene6JSON]
    }

    // MARK: Decoding

    func testDecodesTheCommittedSceneTwoManifest() throws {
        let manifest = try CinematicManifest.decode(json: scene2JSON)
        XCTAssertEqual(manifest.video, "scene2_envelope.mp4")
        XCTAssertEqual(manifest.composition, "Scene2Envelope")
        XCTAssertEqual(manifest.fps, 30)
        XCTAssertEqual(manifest.durationSec, 8)
        XCTAssertEqual(manifest.posterTime, 6.8, accuracy: 1e-9)
        XCTAssertEqual(manifest.beats.count, 3)
        XCTAssertEqual(manifest.cues.count, 2)
        XCTAssertNil(manifest.captions, "the look-scenes are caption-free")
    }

    func testBeatsMapToHapticEventSpecs() throws {
        let manifest = try CinematicManifest.decode(json: scene2JSON)
        let events = manifest.hapticEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0], HapticEventSpec(t: 3, i: 0.45, s: 0.3, d: 0.22))
        XCTAssertEqual(events[1], HapticEventSpec(t: 5.2, i: 0.9, s: 0.62, d: 0))
        // A beat without "d" is a transient (d = 0).
        let bare = try CinematicManifest.decode(json: """
        { "video": "x.mp4", "fps": 30, "durationSec": 2, "posterTime": 1,
          "beats": [{ "t": 0.5, "i": 0.4, "s": 0.3 }], "cues": [] }
        """)
        XCTAssertEqual(bare.hapticEvents, [HapticEventSpec(t: 0.5, i: 0.4, s: 0.3, d: 0)])
    }

    func testCuesResolveAgainstTheAppCueCatalog() throws {
        // The manifests may only schedule the existing vocabulary —
        // every committed cue id must be a real AppCue.
        for (name, json) in allFixtures {
            let manifest = try CinematicManifest.decode(json: json)
            for cue in manifest.cues {
                XCTAssertNotNil(cue.appCue, "\(name): unknown cue id \(cue.id)")
            }
            XCTAssertEqual(manifest.resolvedCues.count, manifest.cues.count)
        }
        let scene6 = try CinematicManifest.decode(json: scene6JSON)
        XCTAssertEqual(scene6.resolvedCues.map(\.cue), [.drop, .chime])
    }

    func testBoundaryTimesAreTheSortedUniqueUnion() throws {
        // Beat at 3 and cue at 3 collapse into ONE boundary — the player
        // registers each time once with AVPlayer.addBoundaryTimeObserver.
        let manifest = try CinematicManifest.decode(json: scene2JSON)
        XCTAssertEqual(manifest.boundaryTimes, [3, 5.2, 5.34])
    }

    func testCaptionLookupCoversItsWindow() throws {
        let manifest = try CinematicManifest.decode(json: """
        { "video": "x.mp4", "fps": 30, "durationSec": 10, "posterTime": 2,
          "beats": [], "cues": [],
          "captions": [
            { "t": 1.0, "end": 4.0, "de": "Zwei Welten.", "en": "Two worlds." }
          ] }
        """)
        XCTAssertNil(manifest.caption(at: 0.5))
        XCTAssertEqual(manifest.caption(at: 1.0)?.de, "Zwei Welten.")
        XCTAssertEqual(manifest.caption(at: 3.99)?.en, "Two worlds.")
        XCTAssertNil(manifest.caption(at: 4.0), "end is exclusive")
    }

    // MARK: Validation

    func testCommittedManifestsValidateCleanly() throws {
        for (name, json) in allFixtures {
            let manifest = try CinematicManifest.decode(json: json)
            XCTAssertEqual(manifest.validationIssues(), [],
                           "\(name) must pass its own gate")
            XCTAssertTrue(manifest.isValid)
        }
    }

    func testValidationFlagsEveryRuleBreak() throws {
        let broken = try CinematicManifest.decode(json: """
        { "video": "x.mp4", "fps": 0, "durationSec": 5, "posterTime": 5,
          "beats": [
            { "t": 4.9, "i": 0.5, "s": 0.5, "d": 0.5 },
            { "t": 1.0, "i": 1.4, "s": 0.5, "d": 0 }
          ],
          "cues": [
            { "t": 6.0, "id": "chime" },
            { "t": 1.0, "id": "airhorn" }
          ],
          "captions": [
            { "t": 2.0, "end": 1.0, "de": "x", "en": "y" },
            { "t": 0.0, "end": 1.0, "de": "", "en": "y" }
          ] }
        """)
        let issues = broken.validationIssues()
        XCTAssertTrue(issues.contains(.nonPositiveFPS))
        XCTAssertTrue(issues.contains(.posterTimeOutsideVideo),
                      "posterTime == durationSec has no frame to freeze")
        XCTAssertTrue(issues.contains(.beatOutsideVideo(index: 0)),
                      "a beat tail past the video must be flagged")
        XCTAssertTrue(issues.contains(.beatOutOfUnitRange(index: 1)))
        XCTAssertTrue(issues.contains(.cueOutsideVideo(index: 0)))
        XCTAssertTrue(issues.contains(.unknownCue(id: "airhorn")))
        XCTAssertTrue(issues.contains(.captionOutsideVideo(index: 0)))
        XCTAssertTrue(issues.contains(.captionMissingText(index: 1)))
        XCTAssertFalse(broken.isValid)
    }

    func testMissingRequiredKeysThrow() {
        XCTAssertThrowsError(try CinematicManifest.decode(json: """
        { "video": "x.mp4", "fps": 30, "posterTime": 1, "beats": [], "cues": [] }
        """), "a manifest without durationSec is unusable")
        XCTAssertThrowsError(try CinematicManifest.decode(json: "not json"))
    }

    func testUnknownKeysAreIgnored() throws {
        // CI may grow the format — old players must keep decoding.
        let manifest = try CinematicManifest.decode(json: """
        { "video": "x.mp4", "fps": 30, "durationSec": 2, "posterTime": 1,
          "beats": [], "cues": [], "renderHash": "abc123", "schema": 2 }
        """)
        XCTAssertTrue(manifest.isValid)
    }

    // MARK: Cross-check against the script — one timeline, no drift

    func testVideoChaptersAgreeWithTheirManifests() throws {
        for spec in CinematicScript.chapters {
            guard let video = spec.video else { continue }
            guard let json = allFixtures[video.manifestResource] else {
                return XCTFail("\(spec.chapter): no fixture for \(video.manifestResource)")
            }
            let manifest = try CinematicManifest.decode(json: json)
            XCTAssertEqual(manifest.video, video.videoResource + ".mp4",
                           "\(spec.chapter): manifest and script name different videos")
            XCTAssertEqual(manifest.durationSec, spec.duration, accuracy: 1e-9,
                           "\(spec.chapter): script duration must mirror the manifest")
            XCTAssertLessThan(manifest.posterTime, manifest.durationSec)
            XCTAssertFalse(manifest.beats.isEmpty,
                           "\(spec.chapter): a video chapter without beats has no hands")
        }
    }
}
