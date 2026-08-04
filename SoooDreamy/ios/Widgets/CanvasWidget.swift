import WidgetKit
import SwiftUI

// MARK: - Timeline

struct CanvasEntry: TimelineEntry {
    let date: Date
    let strokes: [WidgetCanvasStroke]
    let snapshot: WidgetSnapshot?
}

struct CanvasProvider: TimelineProvider {
    func placeholder(in context: Context) -> CanvasEntry {
        CanvasEntry(date: Date(),
                    strokes: SharedStore.readCanvasStrokes(),
                    snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (CanvasEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CanvasEntry>) -> Void) {
        // The app mirrors strokes into the shared store on every canvas event
        // and reloads timelines, so a gentle periodic re-read is enough.
        let entry = CanvasEntry(date: Date(),
                                strokes: SharedStore.readCanvasStrokes(),
                                snapshot: SharedStore.readSnapshot())
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Views

struct CanvasWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CanvasEntry

    /// Board background — mirrors the in-app canvas; eraser strokes are
    /// painted in exactly this color, just like in CanvasView.
    private static let boardColor = Color(hexString: "FDF4E8")
    private static let boardInk = Color.black.opacity(0.35)

    private var strokeCount: Int {
        max(entry.strokes.count, entry.snapshot?.canvasStrokeCount ?? 0)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: boardCard
            }
        }
        .widgetChrome(photoFriendly: true)
        .widgetURL(URL(string: "sooodreamy://tab/memories"))
    }

    // MARK: Board

    private var boardCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Self.boardColor)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            if entry.strokes.isEmpty {
                emptyBoard
            } else {
                strokeCanvas
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var strokeCanvas: some View {
        Canvas { context, size in
            for stroke in entry.strokes {
                draw(stroke, context: &context, size: size)
            }
        }
    }

    private func draw(_ stroke: WidgetCanvasStroke, context: inout GraphicsContext, size: CGSize) {
        let points = stroke.points.compactMap { pair -> CGPoint? in
            guard pair.count >= 2 else { return nil }
            return CGPoint(x: pair[0] * size.width, y: pair[1] * size.height)
        }
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first)
        } else {
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        // Widths were drawn against the app's ~330pt board; scale them down
        // for small widgets so doodles keep their proportions.
        let scale = max(0.4, min(size.width, size.height) / 330)
        let width = stroke.width * scale
        let color = Color(hexString: stroke.color)

        func solid(_ lineWidth: Double) -> StrokeStyle {
            StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        }

        // Mirrors CanvasView.drawStroke — tool is a free string, unknown
        // tools fall back to a plain pen stroke.
        switch stroke.tool {
        case "marker":
            context.stroke(path, with: .color(color.opacity(0.6)), style: solid(width * 2.5))
        case "eraser":
            context.stroke(path, with: .color(Self.boardColor), style: solid(width * 2.5))
        case "glow":
            var halo = context
            halo.addFilter(.shadow(color: color.opacity(0.85), radius: width * 1.4))
            halo.stroke(path, with: .color(color.opacity(0.55)), style: solid(width * 1.6))
            context.stroke(path, with: .color(color), style: solid(width))
        case "dotted":
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: width * 1.4, lineCap: .round,
                                              lineJoin: .round, dash: [0.1, width * 2.8]))
        case "calligraphy":
            let offset = max(width * 0.45, 1.2)
            let slanted = path.applying(CGAffineTransform(translationX: offset, y: -offset))
            context.stroke(path, with: .color(color), style: solid(width * 0.75))
            context.stroke(slanted, with: .color(color.opacity(0.85)), style: solid(width * 0.55))
        default:
            context.stroke(path, with: .color(color), style: solid(width))
        }
    }

    private var emptyBoard: some View {
        VStack(spacing: 5) {
            Text("🎨")
                .font(.system(size: family == .systemLarge ? 40 : 28))
            Text(WText.t("Noch keine Zeichnung", "No drawing yet"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Self.boardInk)
                .multilineTextAlignment(.center)
        }
        .padding(6)
    }

    // MARK: Medium (board + meta)

    private var medium: some View {
        HStack(spacing: 12) {
            boardCard
                .aspectRatio(1, contentMode: .fit)
            VStack(alignment: .leading, spacing: 4) {
                Text(WText.t("Leinwand 🎨", "Canvas 🎨"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text(strokesLine)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WTheme.pink)
                Spacer(minLength: 0)
                if let partner = entry.snapshot?.partnerName, !partner.isEmpty {
                    Text(WText.t("Von dir & \(partner)", "By you & \(partner)"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WTheme.textSecondary)
                        .lineLimit(1)
                }
                Text(WText.t("Malt zusammen weiter", "Keep doodling together"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WTheme.textSecondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
            Spacer(minLength: 0)
        }
    }

    private var strokesLine: String {
        if strokeCount == 0 { return WText.t("Noch leer", "Still empty") }
        if strokeCount == 1 { return WText.t("1 Strich", "1 stroke") }
        return WText.t("\(strokeCount) Striche", "\(strokeCount) strokes")
    }

    // MARK: Accessory

    private var rectangular: some View {
        HStack(spacing: 8) {
            Text("🎨")
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 1) {
                Text(WText.t("Leinwand", "Canvas"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(entry.strokes.isEmpty
                     ? WText.t("Noch keine Zeichnung", "No drawing yet")
                     : strokesLine)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct CanvasWidget: Widget {
    let kind = "SoooDreamy.Canvas"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CanvasProvider()) { entry in
            CanvasWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Leinwand", "Canvas"))
        .description(WText.t("Eure gemeinsame Leinwand — direkt auf dem Homescreen.",
                             "Your shared doodle canvas, right on your home screen."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
