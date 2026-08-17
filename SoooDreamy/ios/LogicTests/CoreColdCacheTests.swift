import Foundation
import XCTest
@testable import SoooDreamyLogic

final class CoreColdCacheTests: XCTestCase {
    func testUpsertIsProfileScopedAndReplacesOldCoupleState() {
        var state = CoreColdCacheState()
        let profile = UUID()
        state.upsert(record(profile: profile, couple: "old", savedAt: 1))
        state.upsert(record(profile: profile, couple: "new", savedAt: 2))

        XCTAssertNil(state.record(profileID: profile, coupleID: "old"))
        XCTAssertEqual(state.record(profileID: profile, coupleID: "new")?.coupleID, "new")
    }

    func testBoundKeepsMostRecentProfiles() {
        var state = CoreColdCacheState()
        var profiles: [UUID] = []
        for index in 0..<(CoreColdCacheState.maximumProfiles + 3) {
            let profile = UUID()
            profiles.append(profile)
            state.upsert(record(profile: profile, couple: "c-\(index)",
                                savedAt: TimeInterval(index)))
        }
        XCTAssertEqual(state.records.count, CoreColdCacheState.maximumProfiles)
        XCTAssertNil(state.record(profileID: profiles[0], coupleID: "c-0"))
        XCTAssertNotNil(state.record(profileID: profiles.last!, coupleID: "c-\(profiles.count - 1)"))
    }

    func testStoreRoundTripAndExplicitRemoval() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold-cache-\(UUID().uuidString)", isDirectory: true)
        let file = root.appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = UUID()

        CoreColdCacheStore(fileURL: file).save(record(profile: profile, couple: "couple", savedAt: 4))
        let restored = CoreColdCacheStore(fileURL: file)
        XCTAssertEqual(restored.record(profileID: profile, coupleID: "couple")?.events,
                       Data("events".utf8))

        restored.remove(profileID: profile)
        XCTAssertNil(CoreColdCacheStore(fileURL: file)
            .record(profileID: profile, coupleID: "couple"))
    }

    private func record(profile: UUID, couple: String,
                        savedAt: TimeInterval) -> CoreColdCacheRecord {
        CoreColdCacheRecord(profileID: profile, coupleID: couple,
                            savedAt: Date(timeIntervalSince1970: savedAt),
                            couple: Data("couple".utf8),
                            events: Data("events".utf8),
                            daily: nil, stats: nil, level: nil)
    }
}
