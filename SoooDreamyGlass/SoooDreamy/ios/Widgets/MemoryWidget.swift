import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Timeline

/// „An diesem Tag": shows today's closest memory — a photo or a
/// daily-question moment from exactly n months/years ago. The app mirrors
/// the closest memory into the shared snapshot; photo bytes are fetched
/// here with the mirrored credentials (same pattern as the photo widget).
struct MemoryEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let palette: WidgetPalette
    let image: UIImage?
}

struct MemoryProvider: AppIntentTimelineProvider {
    private func entry(for configuration: CoupleWidgetConfigIntent,
                       date: Date = Date(),
                       image: UIImage? = nil) -> MemoryEntry {
        MemoryEntry(date: date,
                    snapshot: WidgetDiagnostics.renderableSnapshot,
                    palette: WidgetPalette.resolve(kind: WidgetKindID.memory,
                                                   intentThemeId: configuration.theme.themeId),
                    image: image)
    }

    func placeholder(in context: Context) -> MemoryEntry {
        MemoryEntry(date: Date(), snapshot: WidgetDiagnostics.renderableSnapshot,
                    palette: WidgetPalette.resolve(kind: WidgetKindID.memory), image: nil)
    }

    func snapshot(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> MemoryEntry {
        // Gallery preview: no network fetch.
        entry(for: configuration)
    }

    func timeline(for configuration: CoupleWidgetConfigIntent, in context: Context) async -> Timeline<MemoryEntry> {
        let snapshot = WidgetDiagnostics.renderableSnapshot
        var image: UIImage?
        if snapshot?.memoryDateKey == SharedDates.todayKey(),
           snapshot?.memoryKind == "photo",
           let urlString = snapshot?.memoryPhotoURLString,
           let url = URL(string: urlString),
           let credentials = SharedStore.readServerCredentials(),
           let token = SharedKeychain.activeToken(profileID: credentials.profileID) {
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
               !data.isEmpty {
                image = WidgetImages.decode(data, maxDimension: 600)
            }
        }
        // Second entry at midnight so yesterday's memory disappears even when
        // the app never opens — the view re-checks memoryDateKey per entry date.
        let midnight = WidgetClock.nextMidnight()
        return Timeline(entries: [entry(for: configuration, image: image),
                                  entry(for: configuration, date: midnight, image: nil)],
                        policy: .after(midnight))
    }
}

// MARK: - Views

struct MemoryWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MemoryEntry

    private var palette: WidgetPalette { entry.palette }
    private var snapshot: WidgetSnapshot? { entry.snapshot }

    /// Only today's memory counts — a stale snapshot must not claim
    /// "on this day" for the wrong day.
    private var hasMemory: Bool {
        snapshot?.memoryDateKey == SharedDates.todayKey(entry.date)
            && snapshot?.memoryDistanceN != nil
    }

    private var agoText: String? {
        guard let n = snapshot?.memoryDistanceN,
              let unit = snapshot?.memoryDistanceUnit else { return nil }
        if unit == "years" {
            return n == 1 ? WText.t("vor 1 Jahr", "1 year ago")
                          : WText.t("vor \(n) Jahren", "\(n) years ago")
        }
        return n == 1 ? WText.t("vor 1 Monat", "1 month ago")
                      : WText.t("vor \(n) Monaten", "\(n) months ago")
    }

    private var line: String? {
        let text = WText.t(snapshot?.memoryLineDE ?? "", snapshot?.memoryLineEN ?? "")
        return text.isEmpty ? nil : text
    }

    private var moreCount: Int {
        max(0, (snapshot?.memoryCount ?? 0) - 1)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium, .systemLarge, .systemExtraLarge: medium
            default: small
            }
        }
        .widgetChrome(palette)
        .widgetFreshness(kind: WidgetKindID.memory,
                         updatedAt: snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://tab/memories"))
    }

    // MARK: Small

    @ViewBuilder
    private var small: some View {
        if hasMemory {
            ZStack(alignment: .bottomLeading) {
                photoBackdrop
                VStack(alignment: .leading, spacing: 3) {
                    if entry.image == nil {
                        Image(systemName: memorySystemImage)
                            .font(WidgetTypo.glyph(24, weight: .semibold))
                            .foregroundStyle(palette.accent)
                        Spacer(minLength: 0)
                    }
                    Text(WText.t("An diesem Tag", "On this day"))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.image == nil ? AnyShapeStyle(palette.accent)
                                                            : AnyShapeStyle(WidgetPalette.gold))
                    if let agoText {
                        Text(agoText)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(entry.image == nil ? palette.textPrimary : .white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if entry.image == nil, let line {
                        Text(line)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(entry.image == nil ? 0 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: entry.image == nil ? .topLeading : .bottomLeading)
            }
        } else {
            emptyState
        }
    }

    // MARK: Medium & large

    @ViewBuilder
    private var medium: some View {
        if hasMemory {
            HStack(spacing: 12) {
                if let image = entry.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: memorySystemImage)
                        .font(WidgetTypo.glyph(38, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 72)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(WText.t("An diesem Tag", "On this day"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                    if let agoText {
                        Text(agoText)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let line {
                        Text(line)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(2)
                    }
                    if moreCount > 0 {
                        WChip(text: WText.t("+\(moreCount) weitere", "+\(moreCount) more"),
                              palette: palette)
                    }
                }
                Spacer(minLength: 0)
            }
        } else {
            emptyState
        }
    }

    // MARK: Pieces

    /// Photo filling the content area with a legibility scrim (small family).
    @ViewBuilder
    private var photoBackdrop: some View {
        if let image = entry.image {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    )
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if snapshot == nil {
            WidgetSetupHint(palette: palette)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "photo.fill")
                    .font(WidgetTypo.glyph(26, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(WText.t("Heute keine Erinnerung — macht heute neue!",
                             "No memory today — go make new ones!"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    // MARK: Accessories

    @ViewBuilder
    private var inline: some View {
        if hasMemory {
            Label(WText.t("An diesem Tag ", "On this day ") + (agoText ?? ""),
                  systemImage: "calendar")
        } else {
            Label("SoooDreamy", systemImage: "heart.fill")
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(WidgetTypo.glyph(18, weight: .bold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(WText.t("An diesem Tag", "On this day"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text(hasMemory ? (agoText ?? "") + (moreCount > 0 ? " · +\(moreCount)" : "")
                               : WText.t("keine Erinnerung heute", "no memory today"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var memorySystemImage: String {
        snapshot?.memoryKind == "daily" ? "questionmark.bubble.fill" : "calendar"
    }
}

// MARK: - Widget

struct MemoryWidget: Widget {
    let kind = WidgetKindID.memory

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: MemoryProvider()) { entry in
            MemoryWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("An diesem Tag", "On this day"))
        .description(WText.t("Eure Erinnerung von heute vor X Monaten oder Jahren.",
                             "Your memory from exactly X months or years ago today."))
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryRectangular, .accessoryInline])
    }
}
