import WidgetKit
import SwiftUI

// MARK: - Timeline

struct CountdownEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct CountdownProvider: TimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: Date(), snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        // One entry now + the next 3 midnights so "in N Tagen" stays fresh.
        var entries = [CountdownEntry(date: Date(), snapshot: snapshot)]
        let calendar = SharedDates.calendar
        var day = calendar.startOfDay(for: Date())
        for _ in 0..<3 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            entries.append(CountdownEntry(date: day, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Views

struct CountdownWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    private struct EventInfo {
        let title: String
        let emoji: String
        let date: Date
        let days: Int
    }

    private var event: EventInfo? {
        guard let snapshot = entry.snapshot,
              let title = snapshot.nextEventTitle, !title.isEmpty,
              let date = SharedDates.parse(snapshot.nextEventDate),
              let days = SharedDates.daysUntil(snapshot.nextEventDate, now: entry.date),
              days >= 0 else { return nil }
        return EventInfo(title: title, emoji: snapshot.nextEventEmoji ?? "💫", date: date, days: days)
    }

    private func daysText(_ days: Int) -> String {
        if days == 0 { return WText.t("HEUTE! 🎉", "TODAY! 🎉") }
        if days == 1 { return WText.t("in 1 Tag", "in 1 day") }
        return WText.t("in \(days) Tagen", "in \(days) days")
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(for: .widget) { WTheme.bgGradient }
        .widgetURL(URL(string: "sooodreamy://tab/memories"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let event {
                Text(event.emoji)
                    .font(.system(size: 30))
                Spacer(minLength: 0)
                Text(event.title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(daysText(event.days))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(WTheme.countGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(event.date, format: .dateTime.day().month())
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WTheme.textSecondary)
            } else {
                emptyState
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let event {
                emojiBadge(event.emoji)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Text(event.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WTheme.textSecondary)
                }
                Spacer(minLength: 8)
                trailingCount(event.days)
            } else {
                emptyState
                Spacer(minLength: 0)
            }
        }
    }

    private func emojiBadge(_ emoji: String) -> some View {
        Text(emoji)
            .font(.system(size: 36))
            .frame(width: 62, height: 62)
            .background(Circle().fill(Color.white.opacity(0.08)))
            .overlay(Circle().strokeBorder(WTheme.heroGradient, lineWidth: 1.5))
    }

    private func trailingCount(_ days: Int) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            if days == 0 {
                Text("🎉")
                    .font(.system(size: 30))
                Text(WText.t("HEUTE!", "TODAY!"))
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(WTheme.gold)
            } else {
                Text("\(days)")
                    .font(.system(size: 38, weight: .heavy, design: .rounded))
                    .foregroundStyle(WTheme.countGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(days == 1 ? WText.t("Tag", "day") : WText.t("Tage", "days"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(WTheme.textSecondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("✨")
                .font(.system(size: 30))
            Spacer(minLength: 0)
            Text(WText.t("Kein Moment geplant", "No moment planned"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
            Text(WText.t("Füge in der App einen Moment hinzu", "Add a moment in the app"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(WTheme.textSecondary)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let event {
                Text("\(event.emoji) \(event.title)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(daysText(event.days))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1)
                Text(event.date, format: .dateTime.day().month())
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text(WText.t("Kein Moment geplant", "No moment planned"))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Text(WText.t("Plant etwas Schönes ✨", "Plan something lovely ✨"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Widget

struct CountdownWidget: Widget {
    let kind = "SoooDreamy.Countdown"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Countdown", "Countdown"))
        .description(WText.t("Zählt die Tage bis zu eurem nächsten Moment.",
                             "Counts down to your next moment together."))
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
