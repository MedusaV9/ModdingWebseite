import WidgetKit
import SwiftUI

// MARK: - Timeline

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(StreakEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let entry = StreakEntry(date: Date(), snapshot: SharedStore.readSnapshot())
        // A new day brings a fresh question (and resets today's answered
        // state) — re-read at the next midnight; the app reloads timelines
        // whenever an answer lands.
        let calendar = SharedDates.calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        completion(Timeline(entries: [entry], policy: .after(midnight ?? Date().addingTimeInterval(3600))))
    }
}

// MARK: - Views

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    private var streak: Int {
        entry.snapshot?.streak ?? 0
    }

    /// Today's progress toward keeping the streak alive.
    private var stateLine: String {
        guard let snapshot = entry.snapshot else {
            return WText.t("Beantwortet eure Frage des Tages", "Answer your daily question")
        }
        if snapshot.dailyBothAnswered {
            return WText.t("Heute gesichert! 💞", "Locked in for today! 💞")
        }
        if snapshot.dailyAnsweredByMe {
            return WText.t("Wartet auf deinen Schatz …", "Waiting for your love …")
        }
        return WText.t("Heute noch offen", "Still open today")
    }

    private var stateColor: Color {
        guard let snapshot = entry.snapshot else { return WTheme.pink }
        if snapshot.dailyBothAnswered { return WTheme.mint }
        if snapshot.dailyAnsweredByMe { return WTheme.gold }
        return WTheme.pink
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            default: small
            }
        }
        .widgetChrome()
        .widgetURL(URL(string: "sooodreamy://streak"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("🔥")
                    .font(.system(size: 16))
                Text(WText.t("Antwort-Serie", "Answer streak"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(WTheme.purple)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if streak > 0 {
                Text("\(streak)")
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(WTheme.countGradient)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(streak == 1
                     ? WText.t("Tag in Folge", "day in a row")
                     : WText.t("Tage in Folge", "days in a row"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(WTheme.pink)
            } else {
                Text("✨")
                    .font(.system(size: 30))
                Text(WText.t("Startet heute eure Serie", "Start your streak today"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 7, height: 7)
                Text(stateLine)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(entry.snapshot.map { "\($0.streak)" } ?? "—")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(WText.t("🔥 Antwort-Serie", "🔥 Answer streak"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Text(streak == 1
                 ? WText.t("1 Tag", "1 day")
                 : WText.t("\(streak) Tage", "\(streak) days"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .lineLimit(1)
                .widgetAccentable()
            Text(stateLine)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget

struct StreakWidget: Widget {
    let kind = "SoooDreamy.Streak"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Antwort-Serie", "Answer streak"))
        .description(WText.t("Eure Frage-des-Tages-Serie — und ob sie heute schon gesichert ist.",
                             "Your daily-question streak — and whether today is already locked in."))
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
