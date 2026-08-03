import WidgetKit
import SwiftUI

// MARK: - Timeline

struct DailyQuestionEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct DailyQuestionProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyQuestionEntry {
        DailyQuestionEntry(date: Date(), snapshot: SharedStore.readSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyQuestionEntry) -> Void) {
        completion(DailyQuestionEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyQuestionEntry>) -> Void) {
        let entry = DailyQuestionEntry(date: Date(), snapshot: SharedStore.readSnapshot())
        // Re-read the snapshot at the next midnight (a new question arrives daily);
        // the app reloads timelines on answer changes.
        let calendar = SharedDates.calendar
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
        completion(Timeline(entries: [entry], policy: .after(midnight ?? Date().addingTimeInterval(3600))))
    }
}

// MARK: - Views

struct DailyQuestionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyQuestionEntry

    private var question: String? {
        guard let snapshot = entry.snapshot else { return nil }
        let q = SharedStore.resolvedLanguage == "de"
            ? (snapshot.dailyQuestionDE ?? snapshot.dailyQuestionEN)
            : (snapshot.dailyQuestionEN ?? snapshot.dailyQuestionDE)
        guard let q, !q.isEmpty else { return nil }
        return q
    }

    private var streak: Int {
        entry.snapshot?.streak ?? 0
    }

    private var stateLine: String {
        guard let snapshot = entry.snapshot else {
            return WText.t("Beantworte die Frage des Tages 💌", "Answer today's question 💌")
        }
        if snapshot.dailyBothAnswered {
            return WText.t("Antworten enthüllt! 💞", "Answers revealed! 💞")
        }
        if snapshot.dailyAnsweredByMe {
            return WText.t("Wartet auf deinen Schatz …", "Waiting for your love …")
        }
        return WText.t("Beantworte die Frage des Tages 💌", "Answer today's question 💌")
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
            case .accessoryRectangular: rectangular
            default: medium
            }
        }
        .containerBackground(for: .widget) { WTheme.bgGradient }
        .widgetURL(URL(string: "sooodreamy://daily"))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(question ?? WText.t("Öffne SoooDreamy für eure heutige Frage",
                                     "Open SoooDreamy for today's question"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(stateLine)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(stateColor)
                .lineLimit(1)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(WText.t("Frage des Tages 💌", "Question of the day 💌"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(WTheme.purple)
            Spacer(minLength: 0)
            if streak > 1 {
                Text("🔥 \(streak)")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(WTheme.gold)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(WText.t("💌 Frage des Tages", "💌 Daily question"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                if streak > 1 {
                    Text("🔥\(streak)")
                        .font(.system(.caption2, design: .rounded))
                }
                Spacer(minLength: 0)
            }
            Text(question ?? WText.t("Öffne SoooDreamy", "Open SoooDreamy"))
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
        }
    }
}

// MARK: - Widget

struct DailyQuestionWidget: Widget {
    let kind = "SoooDreamy.DailyQuestion"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DailyQuestionProvider()) { entry in
            DailyQuestionWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Frage des Tages", "Daily question"))
        .description(WText.t("Eure tägliche Frage — antwortet beide und enthüllt die Antworten.",
                             "Your daily question — both answer to reveal."))
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}
