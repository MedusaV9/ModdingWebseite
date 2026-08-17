import XCTest
@testable import SoooDreamyLogic

final class SurfaceStateTests: XCTestCase {
    func testCompletePrecedenceMatrix() {
        XCTAssertEqual(SurfaceState.resolve(
            loading: true, hasContent: false, connected: false, requestFailed: false
        ), .loading)
        XCTAssertEqual(SurfaceState.resolve(
            loading: false, hasContent: true, connected: false, requestFailed: true
        ), .content)
        XCTAssertEqual(SurfaceState.resolve(
            loading: false, hasContent: false, connected: true, requestFailed: true
        ), .failed)
        XCTAssertEqual(SurfaceState.resolve(
            loading: false, hasContent: false, connected: false, requestFailed: false
        ), .offline)
        XCTAssertEqual(SurfaceState.resolve(
            loading: false, hasContent: false, connected: true, requestFailed: false
        ), .empty)
    }
}
