import Foundation
import XCTest
@testable import SoooDreamyLogic

final class PendingMediaStoreTests: XCTestCase {
    private let scopeA = OutboxScope(profileID: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                     coupleID: "couple-a", memberID: "member-a")
    private let scopeB = OutboxScope(profileID: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
                                     coupleID: "couple-b", memberID: "member-b")

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pending-media-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testAddPersistsBytesAndMetadataAcrossRelaunch() {
        let store = PendingMediaStore(directory: directory)
        let jpeg = Data("fake-jpeg-bytes".utf8)
        let entry = store.add(jpeg: jpeg, caption: "Sonnenuntergang", album: "Urlaub",
                              width: 2_048, height: 1_536, scope: scopeA)
        XCTAssertNotNil(entry)

        // A second instance over the same directory = process relaunch.
        let relaunched = PendingMediaStore(directory: directory)
        let entries = relaunched.entries(for: scopeA)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.caption, "Sonnenuntergang")
        XCTAssertEqual(entries.first?.album, "Urlaub")
        XCTAssertEqual(entries.first?.width, 2_048)
        XCTAssertNil(entries.first?.lastErrorCode)
        XCTAssertEqual(relaunched.jpegData(id: entry!.id), jpeg)
    }

    func testEntriesAreScopedAndOrderedOldestFirst() {
        let store = PendingMediaStore(directory: directory)
        store.add(jpeg: Data([2]), caption: "later", album: "", width: 1, height: 1,
                  scope: scopeA, id: "later", createdAt: Date(timeIntervalSince1970: 20))
        store.add(jpeg: Data([1]), caption: "earlier", album: "", width: 1, height: 1,
                  scope: scopeA, id: "earlier", createdAt: Date(timeIntervalSince1970: 10))
        store.add(jpeg: Data([3]), caption: "other couple", album: "", width: 1, height: 1,
                  scope: scopeB, id: "foreign", createdAt: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(store.entries(for: scopeA).map(\.id), ["earlier", "later"])
        XCTAssertEqual(store.entries(for: scopeB).map(\.id), ["foreign"])
    }

    func testUpdateAndLastErrorSurviveRelaunch() {
        let store = PendingMediaStore(directory: directory)
        store.add(jpeg: Data([1]), caption: "old", album: "", width: 1, height: 1,
                  scope: scopeA, id: "draft")
        store.update(id: "draft", caption: "new caption", album: "Album")
        store.setLastError(id: "draft", code: "payload_too_large")

        let relaunched = PendingMediaStore(directory: directory)
        let entry = relaunched.entries(for: scopeA).first
        XCTAssertEqual(entry?.caption, "new caption")
        XCTAssertEqual(entry?.album, "Album")
        XCTAssertEqual(entry?.lastErrorCode, "payload_too_large")
    }

    func testRemoveDeletesEntryAndBytes() {
        let store = PendingMediaStore(directory: directory)
        store.add(jpeg: Data([1]), caption: "", album: "", width: 1, height: 1,
                  scope: scopeA, id: "gone")
        store.remove(id: "gone")

        XCTAssertTrue(store.entries(for: scopeA).isEmpty)
        XCTAssertNil(store.jpegData(id: "gone"))
        XCTAssertTrue(PendingMediaStore(directory: directory).entries(for: scopeA).isEmpty)
    }

    func testStoreIsBoundedAndDropsOldestEntriesWithTheirBytes() {
        let store = PendingMediaStore(directory: directory)
        for index in 0..<(PendingMediaStore.maximumEntries + 3) {
            store.add(jpeg: Data([UInt8(index)]), caption: "", album: "", width: 1, height: 1,
                      scope: scopeA, id: "photo-\(index)",
                      createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        let entries = store.entries(for: scopeA)
        XCTAssertEqual(entries.count, PendingMediaStore.maximumEntries)
        XCTAssertEqual(entries.first?.id, "photo-3")
        XCTAssertNil(store.jpegData(id: "photo-0"), "evicted bytes must be deleted")
        XCTAssertNotNil(store.jpegData(id: "photo-3"))
    }

    /// EXIF capture time must survive the stash — a retried upload still
    /// sends the real date. Pre-takenAt index files (key absent) decode too.
    func testTakenAtSurvivesRelaunchAndOldIndexesDecode() {
        let store = PendingMediaStore(directory: directory)
        let shot = Date(timeIntervalSince1970: 1_720_000_000)
        store.add(jpeg: Data([1]), caption: "", album: "", width: 1, height: 1,
                  takenAt: shot, scope: scopeA, id: "dated")
        store.add(jpeg: Data([2]), caption: "", album: "", width: 1, height: 1,
                  scope: scopeA, id: "undated")

        let relaunched = PendingMediaStore(directory: directory)
        let byId = Dictionary(uniqueKeysWithValues: relaunched.entries(for: scopeA).map { ($0.id, $0) })
        XCTAssertEqual(byId["dated"]?.takenAt, shot)
        XCTAssertNil(byId["undated"]?.takenAt)

        // An index written before the takenAt field existed still loads.
        let legacy = """
        [{"id":"old","scope":{"profileID":"00000000-0000-0000-0000-00000000000A",\
        "coupleID":"couple-a","memberID":"member-a"},"caption":"","album":"",\
        "width":1,"height":1,"createdAt":0}]
        """
        try? Data(legacy.utf8).write(to: directory.appendingPathComponent("index.json"))
        let migrated = PendingMediaStore(directory: directory)
        XCTAssertEqual(migrated.entries(for: scopeA).map(\.id), ["old"])
        XCTAssertNil(migrated.entries(for: scopeA).first?.takenAt)
    }

    func testReaddingSameIdReplacesInsteadOfDuplicating() {
        let store = PendingMediaStore(directory: directory)
        store.add(jpeg: Data([1]), caption: "first", album: "", width: 1, height: 1,
                  scope: scopeA, id: "same")
        store.add(jpeg: Data([2]), caption: "second", album: "", width: 1, height: 1,
                  scope: scopeA, id: "same")

        let entries = store.entries(for: scopeA)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.caption, "second")
        XCTAssertEqual(store.jpegData(id: "same"), Data([2]))
    }
}
