import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Timeline

struct CanvasEntry: TimelineEntry {
    let date: Date
    let strokes: [WidgetCanvasStroke]
    let snapshot: WidgetSnapshot?
    let palette: WidgetPalette
}

struct CanvasProvider: AppIntentTimelineProvider {
    private func entry(for configuration: CoupleWidgetConfigIntent) -> CanvasEntry {
        CanvasEntry(date: Date(),
                    strokes: SharedStore.readCanvasStrokes(),
                    snapshot: WidgetDiagnostics.renderableSnapshot,
                    palette: WidgetPalette.resolve(kind: WidgetKindID.canvas,
                                                   intentThemeId: configuration.theme.themeId))
    }

    func placeholder(in context: Context) -> CanvasEntry {
        entry(for: CoupleWidgetConfigIntent())
    }

    func snapshot(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> CanvasEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> Timeline<CanvasEntry> {
        // The app mirrors strokes into the shared store on every canvas event
        // and reloads timelines, so a gentle periodic re-read is enough.
        let refresh = Date().addingTimeInterval(30 * 60)
        return Timeline(entries: [entry(for: configuration)], policy: .after(refresh))
    }
}

// MARK: - Views

struct CanvasWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CanvasEntry

    private var palette: WidgetPalette { entry.palette }

    /// Board background — mirrors the in-app canvas; eraser strokes are
    /// painted in exactly this color, just like in CanvasView. P6-C sync:
    /// CanvasView paints on `PaperRules.briefHex` since the paper wave —
    /// the old #FDF4E8 mirror was stale, so erased areas rendered as a
    /// visibly wrong tone in the widget.
    private static let boardColor = Color(hexString: WidgetPaperHex.brief)
    private static let boardInk = Color(hexString: WidgetPaperHex.tinteDunkel).opacity(0.35)

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
        .widgetChrome(palette, photoFriendly: true)
        .widgetFreshness(kind: WidgetKindID.canvas,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://canvas"))
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

    /// Shared `StrokeRenderer` — exactly the in-app canvas look. Widths were
    /// drawn against the app's ~330pt board; scale them down for small
    /// widgets so doodles keep their proportions.
    private func draw(_ stroke: WidgetCanvasStroke, context: inout GraphicsContext, size: CGSize) {
        let scale = max(0.4, min(size.width, size.height) / 330)
        StrokeRenderer.draw(points: stroke.points,
                            color: Color(hexString: stroke.color),
                            width: stroke.width * scale,
                            tool: stroke.tool,
                            boardColor: Self.boardColor,
                            context: &context,
                            size: size)
    }

    private var emptyBoard: some View {
        VStack(spacing: 5) {
            Text("🎨")
                .font(WidgetTypo.glyph(family == .systemLarge ? 40 : 28))
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
                    .foregroundStyle(palette.textPrimary)
                Text(strokesLine)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
                if let partner = entry.snapshot?.partnerName, !partner.isEmpty {
                    Text(WText.t("Von dir & \(partner)", "By you & \(partner)"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Text(WText.t("Malt zusammen weiter", "Keep doodling together"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
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
                .font(WidgetTypo.glyph(24))
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
    let kind = WidgetKindID.canvas

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: CanvasProvider()) { entry in
            CanvasWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Leinwand", "Canvas"))
        .description(WText.t("Eure gemeinsame Leinwand — direkt auf dem Homescreen.",
                             "Your shared doodle canvas, right on your home screen."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
