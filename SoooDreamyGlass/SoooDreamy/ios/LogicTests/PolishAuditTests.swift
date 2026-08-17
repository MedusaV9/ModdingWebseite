import XCTest
@testable import SoooDreamyLogic

/// The audit is a hand-maintained inventory, not a proof — these tests
/// enforce the part a static file CAN enforce: no surface joins
/// `AuditedSurface` without a written row, no row leaves a state
/// unanswered, and every claim/gap carries a note a reviewer can follow.
/// (The old test asserted that a generated dictionary equaled the set it
/// was generated from — green theater; see EVAL P0-3.)
final class PolishAuditTests: XCTestCase {
    func testEveryDeclaredSurfaceHasAHandWrittenInventoryRow() {
        XCTAssertTrue(
            PolishAudit.unauditedSurfaces.isEmpty,
            "New surfaces need a hand-audited row in PolishAudit.inventory: "
                + PolishAudit.unauditedSurfaces.map(\.rawValue).joined(separator: ", ")
        )
    }

    func testEveryRowAnswersAllFiveStates() {
        XCTAssertTrue(
            PolishAudit.unansweredStates.isEmpty,
            "Silence is not an answer — mark each state implemented, notApplicable "
                + "or gap: \(PolishAudit.unansweredStates)"
        )
    }

    func testEveryAnswerCarriesAFollowableNote() {
        for (surface, row) in PolishAudit.inventory {
            for (state, coverage) in row {
                let note: String
                switch coverage {
                case .implemented(let text), .notApplicable(let text), .gap(let text):
                    note = text
                }
                XCTAssertFalse(
                    note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(surface.rawValue).\(state.rawValue) needs a note naming where it renders or why not"
                )
            }
        }
    }

    func testKnownGapsAreEnumerableForReview() {
        // The debt list must stay mechanically extractable (release notes,
        // review checklists). This intentionally does NOT assert emptiness:
        // an honest gap is better than a green lie — closing them is
        // tracked in review, not hidden by construction.
        for gap in PolishAudit.knownGaps {
            XCTAssertFalse(gap.note.isEmpty)
        }
        XCTAssertEqual(
            PolishAudit.knownGaps.count,
            PolishAudit.inventory.values
                .flatMap(\.values)
                .filter { if case .gap = $0 { true } else { false } }
                .count
        )
    }

    func testStateAndSurfaceIdentifiersRemainStableForEvidence() {
        XCTAssertEqual(PolishState.allCases.map(\.rawValue),
                       ["loading", "empty", "content", "offline", "failure"])
        XCTAssertEqual(Set(AuditedSurface.allCases.map(\.rawValue)).count,
                       AuditedSurface.allCases.count)
    }
}
