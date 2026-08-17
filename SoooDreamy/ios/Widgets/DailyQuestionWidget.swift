import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Views

struct DailyQuestionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudioEntry

    private var palette: WidgetPalette { entry.palette }

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

    /// Both still can answer today — the deadline ticker adds gentle urgency.
    private var isOpenToday: Bool {
        guard let snapshot = entry.snapshot else { return false }
        return !snapshot.dailyBothAnswered
    }

    private var stateLine: String {
        guard let snapshot = entry.snapshot else {
            return WText.t("Beantworte die Frage des Tages", "Answer today's question")
        }
        if snapshot.dailyBothAnswered {
            return WText.t("Antworten enthüllt!", "Answers revealed!")
        }
        if snapshot.dailyAnsweredByMe {
            return WText.t("Wartet auf deinen Schatz …", "Waiting for your partner …")
        }
        return WText.t("Beantworte die Frage des Tages", "Answer today's question")
    }

    private var stateColor: Color {
        guard let snapshot = entry.snapshot else { return palette.accent }
        if snapshot.dailyBothAnswered { return WidgetPalette.mint }
        if snapshot.dailyAnsweredByMe { return palette.accentSecondary }
        return palette.accent
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemSmall: small
            case .systemLarge, .systemExtraLarge: large
            default: medium
            }
        }
        .widgetChrome(palette)
        .widgetFreshness(kind: WidgetKindID.daily,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://daily"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "envelope.fill")
                    .font(WidgetTypo.glyph(13, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
                if streak > 1 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                    }
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accentSecondary)
                }
            }
            Text(question ?? WText.t("Öffne SoooDreamy für eure heutige Frage",
                                     "Open SoooDreamy for today's question"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(4)
                .minimumScaleFactor(0.75)
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

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Spacer(minLength: 0)
            Text(question ?? WText.t("Öffne SoooDreamy für eure heutige Frage",
                                     "Open SoooDreamy for today's question"))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(6)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 8, height: 8)
                Text(stateLine)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if entry.animated, isOpenToday {
                    // Live countdown to midnight — the answer deadline.
                    WLiveTimer(target: WidgetClock.nextMidnight())
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .background(Capsule().fill(palette.chipFill))
            Text(WText.t("Zum Antworten tippen", "Tap to answer"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(question ?? WText.t("Öffne SoooDreamy für eure heutige Frage",
                                     "Open SoooDreamy for today's question"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Text(stateLine)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if entry.animated, isOpenToday {
                    WLiveTimer(target: WidgetClock.nextMidnight())
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.fill")
                .font(WidgetTypo.labelSmall)
                .foregroundStyle(palette.accent)
            Text(WText.t("Frage des Tages", "Question of the day"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(palette.accent)
            Spacer(minLength: 0)
            if streak > 1 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)")
                }
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accentSecondary)
            }
        }
    }

    private var inline: some View {
        Label(entry.snapshot?.dailyBothAnswered == true
              ? WText.t("Enthüllt", "Revealed")
              : WText.t("Frage des Tages offen", "Daily question open"),
              systemImage: "envelope.fill")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "envelope.fill")
                    .font(WidgetTypo.glyph(10, weight: .semibold))
                Text(WText.t("Frage des Tages", "Daily question"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                if streak > 1 {
                    HStack(spacing: 1) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                    }
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
    let kind = WidgetKindID.daily

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: StudioProvider(kind: kind)) { entry in
            DailyQuestionWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Frage des Tages", "Daily question"))
        .description(WText.t("Eure tägliche Frage — antwortet beide und enthüllt die Antworten.",
                             "Your daily question — both answer to reveal."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}
