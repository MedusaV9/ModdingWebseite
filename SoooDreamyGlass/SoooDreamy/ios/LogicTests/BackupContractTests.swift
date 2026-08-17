import XCTest
@testable import SoooDreamyLogic

final class BackupContractTests: XCTestCase {
    func testManifestRoundTripsEveryDomain() throws {
        let manifest = BackupManifest(domains: Set(BackupDomain.allCases))
        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(BackupManifest.self, from: data), manifest)
        XCTAssertNoThrow(try manifest.validate())
    }

    func testLegacyMigrationDistinguishesOptionalCoupleSnapshot() {
        XCTAssertEqual(
            BackupManifest.migratedLegacy(hasCoupleSnapshot: false).domains,
            [.deviceSettings, .appGroupSettings, .serverProfiles]
        )
        XCTAssertTrue(
            BackupManifest.migratedLegacy(hasCoupleSnapshot: true)
                .domains.contains(.coupleSnapshot)
        )
    }

    func testValidationRejectsEmptyAndFutureSchema() {
        XCTAssertThrowsError(try BackupManifest(domains: []).validate()) {
            XCTAssertEqual($0 as? BackupManifest.ValidationError, .empty)
        }
        XCTAssertThrowsError(try BackupManifest(schema: 99, domains: [.deviceSettings]).validate()) {
            XCTAssertEqual($0 as? BackupManifest.ValidationError, .unsupportedSchema(99))
        }
    }

    func testRestoreSelectionNeverRestoresCoupleSnapshotIntoLocalState() {
        let options = BackupRestoreOptions(
            deviceSettings: false,
            appGroupSettings: true,
            serverProfiles: true
        )
        XCTAssertEqual(
            options.selectedDomains(available: Set(BackupDomain.allCases)),
            [.appGroupSettings, .serverProfiles]
        )
    }

    func testFailedTransactionRollsBackAndSuccessfulTransactionCommits() {
        enum Failure: Error { case injected }
        var value = ["old"]
        XCTAssertThrowsError(try RestoreTransaction.apply(state: &value) {
            $0.append("partial")
            throw Failure.injected
        })
        XCTAssertEqual(value, ["old"])

        RestoreTransaction.apply(state: &value) { $0.append("new") }
        XCTAssertEqual(value, ["old", "new"])
    }
}
