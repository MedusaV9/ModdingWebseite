import WidgetKit
import SwiftUI

// MARK: - Timeline

struct DaysTogetherEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct DaysTogetherProvider: TimelineProvider {
    func placeholder(in context: Context) -> DaysTogetherEntry {
        DaysTogetherEntry(date: Date(), snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (DaysTogetherEntry) -> Void) {
        completion(DaysTogetherEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DaysTogetherEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        // One entry now + the next 3 midnights so the day count stays fresh.
        var entries = [DaysTogetherEntry(date: Date(), snapshot: snapshot)]
        let calendar = SharedDates.calendar
        var day = calendar.startOfDay(for: Date())
        for _ in 0..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(DaysTogetherEntry(date: day, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct DaysTogetherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DaysTogetherEntry

    /// Recomputed from the anniversary at render time; stored value as fallback.
    private var days: Int? {
        if let computed = SharedDates.daysSince(entry.snapshot?.anniversary, now: entry.date) {
            return computed
        }
        return entry.snapshot?.daysTogether
    }

    private var anniversaryDate: Date? {
        SharedDates.parse(entry.snapshot?.anniversary)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: small
            }
        }
        .containerBackground(for: .widget) { WTheme.bgGradient }
        .widgetURL(URL(string: "sooodreamy://tab/home"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            if let days {
                Text("\(days)")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(WTheme.countGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(WText.t("Tage zusammen", "days together"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(WTheme.pink)
                if let anniversaryDate {
                    Text(anniversaryDate, format: .dateTime.day().month().year())
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(WTheme.textSecondary)
                }
            } else {
                emptyState
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let avatar = entry.snapshot?.partnerAvatar, !avatar.isEmpty {
                Text(avatar)
                    .font(.system(size: 16))
            }
            if let name = entry.snapshot?.partnerName, !name.isEmpty {
                Text(name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            beatingHeart
        }
    }

    private var beatingHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 16))
            .foregroundStyle(WTheme.pink)
            .shadow(color: WTheme.pink.opacity(0.8), radius: 6)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("💞")
                .font(.system(size: 32))
            Text(WText.t("Jahrestag in der App festlegen", "Set your anniversary in the app"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(WTheme.textSecondary)
        }
    }

    private var inline: some View {
        Text(inlineText)
    }

    private var inlineText: String {
        guard let days else { return "SoooDreamy 💜" }
        if days == 1 { return WText.t("💜 1 Tag", "💜 1 day") }
        return WText.t("💜 \(days) Tage", "💜 \(days) days")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(days.map { "\($0)" } ?? "—")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .widgetAccentable()
        }
    }
}

// MARK: - Widget

struct DaysTogetherWidget: Widget {
    let kind = "SoooDreamy.DaysTogether"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DaysTogetherProvider()) { entry in
            DaysTogetherWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Tage zusammen", "Days together"))
        .description(WText.t("Zählt eure gemeinsamen Tage seit dem Jahrestag.",
                             "Counts your days together since your anniversary."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}
