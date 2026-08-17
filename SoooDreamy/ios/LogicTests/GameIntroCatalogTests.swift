import XCTest
@testable import SoooDreamyLogic

final class GameIntroCatalogTests: XCTestCase {

    func testBoardWaveCoversTheSevenMissingHubEntries() {
        XCTAssertEqual(Set(GameTutorialCatalog.boardWave.map(\.id)),
                       ["dame", "mancala", "reversi", "memoryduo",
                        "kaesekaestchen", "gomoku", "wordle"])
    }

    func testLibraryKeepsThreeStepShapeAndUniqueIds() {
        XCTAssertEqual(GameTutorialCatalog.library.count, 26)
        XCTAssertEqual(Set(GameTutorialCatalog.library.map(\.id)).count, 26)
        XCTAssertTrue(GameTutorialCatalog.library.allSatisfy { $0.steps.count == 3 })
        XCTAssertTrue(GameTutorialCatalog.library.allSatisfy {
            !$0.practicePrompt.de.isEmpty && !$0.practicePrompt.en.isEmpty
        })
    }

    func testIntroLookupCoversOldAndNewIds() {
        XCTAssertEqual(GameTutorialCatalog.intro(for: "dame")?.title.de, "Dame")
        XCTAssertEqual(GameTutorialCatalog.intro(for: "quiz")?.id, "quiz")
        XCTAssertNil(GameTutorialCatalog.intro(for: "unknown"))
        // The pre-wave lookup stays untouched for the original 19.
        XCTAssertNil(GameTutorialCatalog.tutorial(for: "dame"))
    }

    func testDameIntroLeadsWithCaptureDutyAndChains() {
        guard let dame = GameTutorialCatalog.intro(for: "dame") else {
            return XCTFail("dame intro missing")
        }
        XCTAssertTrue(dame.steps[1].de.contains("Pflicht"))
        XCTAssertTrue(dame.steps[1].de.lowercased().contains("kette"))
    }
}
