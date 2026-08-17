import XCTest
@testable import SoooDreamyLogic

final class WidgetReliabilityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    func testNaturalCadencesMarkOnlyOldSnapshotsStale() {
        XCTAssertEqual(
            WidgetFreshness.state(
                updatedAt: now.addingTimeInterval(-12 * 60 * 60),
                now: now,
                kind: WidgetKindID.mood
            ),
            .current
        )
        guard case let .stale(age) = WidgetFreshness.state(
            updatedAt: now.addingTimeInterval(-14 * 60 * 60),
            now: now,
            kind: WidgetKindID.mood
        ) else {
            return XCTFail("Mood snapshots older than 13 hours must be stale")
        }
        XCTAssertEqual(age, 14 * 60 * 60, accuracy: 0.1)
        XCTAssertEqual(
            WidgetFreshness.state(updatedAt: nil, now: now, kind: WidgetKindID.photo),
            .unavailable
        )
    }

    func testFilmstripSelectionPrefersFavoritesAndIsStable() {
        let candidates = [
            FilmstripPhotoCandidate(id: "new", createdAt: now, isFavorite: false),
            FilmstripPhotoCandidate(id: "fav-old", createdAt: now.addingTimeInterval(-20), isFavorite: true),
            FilmstripPhotoCandidate(id: "fav-new", createdAt: now.addingTimeInterval(-10), isFavorite: true),
            FilmstripPhotoCandidate(id: "new", createdAt: now.addingTimeInterval(-30), isFavorite: true),
        ]
        XCTAssertEqual(
            FilmstripSelection.select(from: candidates, limit: 3).map(\.id),
            ["fav-new", "fav-old", "new"]
        )
        XCTAssertEqual(
            FilmstripSelection.select(from: Array(candidates.reversed()), limit: 3).map(\.id),
            ["fav-new", "fav-old", "new"]
        )
    }

    func testEveryWidgetHasThreeOneTapPresets() {
        for kind in WidgetKindID.all {
            let presets = WidgetPresetCatalog.presets(for: kind)
            XCTAssertEqual(presets.count, 3, kind)
            XCTAssertEqual(Set(presets.map(\.id)).count, 3, kind)
        }

        var config = WidgetKindConfig()
        let photoBooth = WidgetPresetCatalog.presets(for: WidgetKindID.photo)[2]
        WidgetPresetCatalog.apply(photoBooth, to: &config)
        XCTAssertEqual(config.themeId, "night")
        XCTAssertEqual(config.photoFrame, "photobooth")
    }
}
