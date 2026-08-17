import XCTest
@testable import SoooDreamyLogic

/// Pins the shared stroke math down: capture thinning, payload compaction,
/// dot detection and the Catmull-Rom→Bézier conversion every drawing
/// surface renders through.
final class StrokeGeometryTests: XCTestCase {

    // MARK: Capture thinning

    func testFarEnoughFiltersProMotionJitter() {
        // 120-Hz samples a hair apart are noise …
        XCTAssertFalse(StrokeGeometry.farEnough(x: 0.5005, y: 0.5, lastX: 0.5, lastY: 0.5))
        // … a real finger movement passes.
        XCTAssertTrue(StrokeGeometry.farEnough(x: 0.51, y: 0.5, lastX: 0.5, lastY: 0.5))
        // The threshold measures Euclidean distance, not per-axis deltas.
        XCTAssertTrue(StrokeGeometry.farEnough(x: 0.503, y: 0.503, lastX: 0.5, lastY: 0.5))
    }

    // MARK: Payload compaction

    func testCompactedRoundsToFourDecimals() {
        let compacted = StrokeGeometry.compacted([[0.123456789, 0.98765432]])
        XCTAssertEqual(compacted, [[0.1235, 0.9877]])
    }

    func testCompactedIsIdempotent() {
        let once = StrokeGeometry.compacted([[0.333333, 0.666666]])
        XCTAssertEqual(once, StrokeGeometry.compacted(once))
    }

    // MARK: Dot detection

    func testSinglePointIsADot() {
        XCTAssertTrue(StrokeGeometry.isDot([[0.5, 0.5]]))
    }

    func testTapJitterClusterIsADot() {
        // A tap on a real screen produces 2–4 samples inside a tiny radius.
        XCTAssertTrue(StrokeGeometry.isDot([[0.5, 0.5], [0.502, 0.501], [0.499, 0.503]]))
    }

    func testRealStrokeIsNotADot() {
        XCTAssertFalse(StrokeGeometry.isDot([[0.1, 0.1], [0.4, 0.4], [0.8, 0.2]]))
    }

    func testEmptyOrMalformedPointsAreNotADot() {
        XCTAssertFalse(StrokeGeometry.isDot([]))
        XCTAssertFalse(StrokeGeometry.isDot([[0.5]]))
    }

    // MARK: Catmull-Rom smoothing

    func testBezierSegmentsCountAndInterpolation() {
        let points: [[Double]] = [[0, 0], [0.5, 0.5], [1, 0]]
        let segments = StrokeGeometry.bezierSegments(points)
        // n points → n−1 segments, each ending exactly on the next input
        // point (the curve interpolates, it never re-samples).
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].toX, 0.5)
        XCTAssertEqual(segments[0].toY, 0.5)
        XCTAssertEqual(segments[1].toX, 1)
        XCTAssertEqual(segments[1].toY, 0)
    }

    func testStraightLineStaysStraight() {
        // Collinear input must produce control points on the same line —
        // smoothing may round corners, never bend straights.
        let points: [[Double]] = [[0, 0], [0.25, 0.25], [0.5, 0.5], [1, 1]]
        for segment in StrokeGeometry.bezierSegments(points) {
            XCTAssertEqual(segment.control1X, segment.control1Y, accuracy: 1e-12)
            XCTAssertEqual(segment.control2X, segment.control2Y, accuracy: 1e-12)
        }
    }

    func testTwoPointStrokeYieldsOneSegment() {
        let segments = StrokeGeometry.bezierSegments([[0, 0], [1, 1]])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].toX, 1)
        XCTAssertEqual(segments[0].toY, 1)
    }

    func testMalformedPairsAreSkipped() {
        let segments = StrokeGeometry.bezierSegments([[0, 0], [0.5], [1, 1]])
        XCTAssertEqual(segments.count, 1)
    }
}
