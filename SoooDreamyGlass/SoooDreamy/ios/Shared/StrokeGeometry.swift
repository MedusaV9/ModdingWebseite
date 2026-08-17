import Foundation

/// One cubic-Bézier segment of a smoothed stroke: curve to `(toX, toY)`
/// with the two control points. Coordinates stay in the space of the input
/// points (normalized 0…1 on the wire) — Bézier control points are affine
/// combinations of the inputs, so scaling the segment to any board size
/// afterwards yields exactly the curve that would have been computed there.
struct StrokeBezierSegment: Equatable {
    let toX: Double
    let toY: Double
    let control1X: Double
    let control1Y: Double
    let control2X: Double
    let control2Y: Double
}

/// Pure stroke geometry shared by every drawing surface (couple canvas,
/// canvas widget, Pictionary board, sticker pad). Foundation-only so the
/// Linux logic tests can pin the math down; the SwiftUI rendering lives in
/// `StrokeRenderer`.
enum StrokeGeometry {
    /// Minimum normalized distance between two captured points — closer
    /// samples (120-Hz ProMotion jitter) carry no visible information and
    /// only fatten the payload toward the server's point limit.
    static let minCapturedDistance: Double = 0.004

    /// Points huddling inside this normalized radius read as a deliberate
    /// dot (a tap plus finger micro-jitter), not as a line.
    static let dotRadius: Double = 0.006

    /// Capture-time thinning: keep a sample only when it moved far enough
    /// from the previously kept one.
    static func farEnough(x: Double, y: Double,
                          lastX: Double, lastY: Double,
                          minDistance: Double = minCapturedDistance) -> Bool {
        let dx = x - lastX
        let dy = y - lastY
        return (dx * dx + dy * dy).squareRoot() >= minDistance
    }

    /// Payload compaction before upload: four decimals are ~0.1 pt on any
    /// phone board — visually lossless, roughly half the JSON bytes.
    static func compacted(_ points: [[Double]]) -> [[Double]] {
        points.map { pair in
            pair.map { ($0 * 10_000).rounded() / 10_000 }
        }
    }

    /// True when the whole stroke huddles inside `dotRadius` around its
    /// first point — rendered as a filled dot instead of a degenerate line.
    static func isDot(_ points: [[Double]]) -> Bool {
        guard let first = points.first, first.count >= 2 else { return false }
        guard points.count > 1 else { return true }
        return points.allSatisfy { pair in
            guard pair.count >= 2 else { return false }
            let dx = pair[0] - first[0]
            let dy = pair[1] - first[1]
            return (dx * dx + dy * dy).squareRoot() <= dotRadius
        }
    }

    /// Catmull-Rom smoothing: converts a polyline into cubic-Bézier
    /// segments (uniform Catmull-Rom, endpoint-clamped). The curve passes
    /// through every input point — nothing is re-sampled, the wire format
    /// stays untouched — but corners between samples round off.
    static func bezierSegments(_ points: [[Double]]) -> [StrokeBezierSegment] {
        let pts = points.filter { $0.count >= 2 }
        guard pts.count >= 2 else { return [] }
        var segments: [StrokeBezierSegment] = []
        segments.reserveCapacity(pts.count - 1)
        for index in 0..<(pts.count - 1) {
            let p0 = pts[max(index - 1, 0)]
            let p1 = pts[index]
            let p2 = pts[index + 1]
            let p3 = pts[min(index + 2, pts.count - 1)]
            segments.append(StrokeBezierSegment(
                toX: p2[0],
                toY: p2[1],
                control1X: p1[0] + (p2[0] - p0[0]) / 6,
                control1Y: p1[1] + (p2[1] - p0[1]) / 6,
                control2X: p2[0] - (p3[0] - p1[0]) / 6,
                control2Y: p2[1] - (p3[1] - p1[1]) / 6
            ))
        }
        return segments
    }
}
