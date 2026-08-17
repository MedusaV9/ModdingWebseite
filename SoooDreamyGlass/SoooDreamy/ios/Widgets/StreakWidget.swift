import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Views

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudioEntry

    private var palette: WidgetPalette { entry.palette }

    private var streak: Int {
        entry.snapshot?.streak ?? 0
    }

    private var isOpenToday: Bool {
        guard let snapshot = entry.snapshot else { return false }
        return !snapshot.dailyBothAnswered
    }

    /// Today's progress toward keeping the streak alive.
    private var stateLine: String {
        guard let snapshot = entry.snapshot else {
            return WText.t("Beantwortet eure Frage des Tages", "Answer your daily question")
        }
        if snapshot.dailyBothAnswered {
            return WText.t("Heute gesichert!", "Locked in for today!")
        }
        if snapshot.dailyAnsweredByMe {
            return WText.t("Wartet auf deinen Schatz …", "Waiting for your partner …")
        }
        return WText.t("Heute noch offen", "Still open today")
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
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: inline
            case .systemMedium: medium
            default: small
            }
        }
        .widgetChrome(palette)
        .widgetFreshness(kind: WidgetKindID.streak,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://streak"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(WidgetTypo.glyph(14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(WText.t("Antwort-Serie", "Answer streak"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            if streak > 0 {
                Text("\(streak)")
                    .font(WidgetTypo.counterLarge)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(streak == 1
                     ? WText.t("Tag in Folge", "day in a row")
                     : WText.t("Tage in Folge", "days in a row"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
            } else if entry.snapshot == nil {
                WidgetSetupHint(palette: palette)
            } else {
                Image(systemName: "sparkles")
                    .font(WidgetTypo.glyph(27, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(WText.t("Startet heute eure Serie", "Start your streak today"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
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

    /// Medium: streak hero + live midnight deadline while today is open.
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(WidgetTypo.glyph(14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text(WText.t("Antwort-Serie", "Answer streak"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                }
                Spacer(minLength: 0)
                Text("\(streak)")
                    .font(WidgetTypo.counterLarge)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(streak == 1
                     ? WText.t("Tag in Folge", "day in a row")
                     : WText.t("Tage in Folge", "days in a row"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 7, height: 7)
                    Text(stateLine)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(stateColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                if entry.animated, isOpenToday, streak > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(WText.t("Serie läuft ab in", "Streak expires in"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                        // Ticks down to midnight all by itself.
                        WLiveTimer(target: WidgetClock.nextMidnight())
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.accentSecondary)
                    }
                } else if entry.snapshot?.dailyBothAnswered == true {
                    Image(systemName: "heart.fill")
                        .font(WidgetTypo.glyph(30, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            // Progress toward the next streak milestone (7/30/100/365 days).
            Gauge(value: milestoneProgress) {
                Image(systemName: "flame.fill")
                    .font(WidgetTypo.badge)
            } currentValueLabel: {
                Text(entry.snapshot.map { "\($0.streak)" } ?? "—")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }

    private var milestoneProgress: Double {
        let milestones = [7, 30, 100, 365]
        let next = milestones.first { streak < $0 } ?? 365
        return min(Double(streak) / Double(next), 1)
    }

    private var inline: some View {
        Label(streak > 0
              ? WText.t("\(streak)er-Serie", "\(streak)-day streak")
              : WText.t("Serie starten", "Start your streak"),
              systemImage: "flame.fill")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(WidgetTypo.glyph(10, weight: .semibold))
                Text(WText.t("Antwort-Serie", "Answer streak"))
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
            if entry.animated, isOpenToday, streak > 0 {
                HStack(spacing: 4) {
                    Text(WText.t("endet in", "ends in"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    WLiveTimer(target: WidgetClock.nextMidnight())
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                }
            } else {
                Text(stateLine)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Widget

struct StreakWidget: Widget {
    let kind = WidgetKindID.streak

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: StudioProvider(kind: kind)) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Antwort-Serie", "Answer streak"))
        .description(WText.t("Eure Frage-des-Tages-Serie — mit tickender Frist bis Mitternacht.",
                             "Your daily-question streak — with a live midnight deadline."))
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
