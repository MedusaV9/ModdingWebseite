import SwiftUI

/// THE stroke renderer. The couple canvas, the canvas widget, the
/// Pictionary board and the sticker pad all draw through this one code
/// path, so smoothing, dot handling and tool looks stay identical
/// everywhere (and get fixed in one place).
///
/// `tool` is deliberately a free string on the wire — unknown tools fall
/// back to the pen look so older clients render newer strokes gracefully.
/// The two retired brushes ("dotted", "calligraphy") keep their renderers
/// here so existing artwork never changes appearance.
enum StrokeRenderer {
    static func draw(points: [[Double]], color: Color, width: Double, tool: String,
                     boardColor: Color, context: inout GraphicsContext, size: CGSize) {
        guard let first = points.first, first.count >= 2 else { return }

        if StrokeGeometry.isDot(points) {
            drawDot(at: CGPoint(x: first[0] * size.width, y: first[1] * size.height),
                    color: color, width: width, tool: tool,
                    boardColor: boardColor, context: &context)
            return
        }

        let path = smoothedPath(points, size: size)

        func solid(_ lineWidth: Double) -> StrokeStyle {
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        }

        switch tool {
        case "marker":
            context.stroke(path, with: .color(color.opacity(0.6)), style: solid(width * 2.5))
        case "eraser":
            context.stroke(path, with: .color(boardColor), style: solid(width * 2.5))
        case "glow":
            // Neon look: soft shadow halo underneath + a bright core stroke.
            var halo = context
            halo.addFilter(.shadow(color: color.opacity(0.85), radius: width * 1.4))
            halo.stroke(path, with: .color(color.opacity(0.55)), style: solid(width * 1.6))
            context.stroke(path, with: .color(color), style: solid(width))
        case "dotted":
            // Zero-ish dash segments with round caps render as evenly spaced dots.
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width * 1.4, lineCap: .round,
                                              lineJoin: .round, dash: [0.1, width * 2.8]))
        case "calligraphy":
            // Variable-width illusion: main stroke + a thinner, diagonally
            // offset twin — diagonals thicken, horizontals stay slim.
            let offset = max(width * 0.45, 1.2)
            let slanted = path.applying(CGAffineTransform(translationX: offset, y: -offset))
            context.stroke(path, with: .color(color), style: solid(width * 0.75))
            context.stroke(slanted, with: .color(color.opacity(0.85)), style: solid(width * 0.55))
        default:
            context.stroke(path, with: .color(color), style: solid(width))
        }
    }

    /// Catmull-Rom smoothed path through all points (scaled to the board).
    static func smoothedPath(_ points: [[Double]], size: CGSize) -> Path {
        var path = Path()
        guard let first = points.first(where: { $0.count >= 2 }) else { return path }
        path.move(to: CGPoint(x: first[0] * size.width, y: first[1] * size.height))
        for segment in StrokeGeometry.bezierSegments(points) {
            path.addCurve(to: CGPoint(x: segment.toX * size.width,
                                      y: segment.toY * size.height),
                          control1: CGPoint(x: segment.control1X * size.width,
                                            y: segment.control1Y * size.height),
                          control2: CGPoint(x: segment.control2X * size.width,
                                            y: segment.control2Y * size.height))
        }
        return path
    }

    /// A tap is a deliberate dot — eyes, i-dots, little stars — and renders
    /// as a filled circle in the tool's own look instead of an invisible
    /// zero-length line.
    private static func drawDot(at center: CGPoint, color: Color, width: Double,
                                tool: String, boardColor: Color,
                                context: inout GraphicsContext) {
        func circle(radius: Double) -> Path {
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                   width: radius * 2, height: radius * 2))
        }
        switch tool {
        case "marker":
            context.fill(circle(radius: width * 1.25), with: .color(color.opacity(0.6)))
        case "eraser":
            context.fill(circle(radius: width * 1.25), with: .color(boardColor))
        case "glow":
            var halo = context
            halo.addFilter(.shadow(color: color.opacity(0.85), radius: width * 1.4))
            halo.fill(circle(radius: width * 0.8), with: .color(color.opacity(0.55)))
            context.fill(circle(radius: width * 0.6), with: .color(color))
        default:
            context.fill(circle(radius: max(width * 0.6, 1.5)), with: .color(color))
        }
    }
}
