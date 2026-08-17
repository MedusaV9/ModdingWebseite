import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Views

struct DaysTogetherWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudioEntry

    private var palette: WidgetPalette { entry.palette }

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

    private var streak: Int {
        entry.snapshot?.streak ?? 0
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            case .systemLarge: large
            case .systemExtraLarge: extraLarge
            default: small
            }
        }
        .widgetChrome(palette)
        .widgetFreshness(kind: WidgetKindID.daysTogether,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://tab/home"))
    }

    // MARK: Small

    @ViewBuilder
    private var small: some View {
        switch entry.layout {
        case "hero": smallHero
        case "minimal": smallMinimal
        default: smallClassic
        }
    }

    private var smallClassic: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 0)
            if let days {
                Text("\(days)")
                    .font(WidgetTypo.counterLarge)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(WText.t("Tage zusammen", "days together"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
                if let anniversaryDate {
                    Text(anniversaryDate, format: .dateTime.day().month().year())
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                emptyState
            }
        }
    }

    private var smallHero: some View {
        VStack(spacing: 2) {
            if let days {
                Spacer(minLength: 0)
                Text("\(days)")
                    .font(WidgetTypo.counterHero)
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                Text(WText.t("Tage", "days"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var smallMinimal: some View {
        VStack(alignment: .leading, spacing: 3) {
            WHeart(palette: palette, size: 14)
            Spacer(minLength: 0)
            if let days {
                Text("\(days)")
                    .font(WidgetTypo.counterMedium)
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(WText.t("Tage", "days"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            } else {
                emptyState
            }
        }
    }

    // MARK: Medium

    private var medium: some View {
        HStack(spacing: 14) {
            if let days {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        WHeart(palette: palette)
                        if let name = entry.snapshot?.partnerName, !name.isEmpty {
                            Text(WText.t("Mit \(name)", "With \(name)"))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Text("\(days)")
                        .font(WidgetTypo.counterLarge)
                        .foregroundStyle(palette.accent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text(WText.t("Tage zusammen", "days together"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                    if entry.animated, let anniversaryDate, anniversaryDate <= entry.date {
                        // Lively "together for …" line — updates by itself.
                        Text(anniversaryDate, style: .relative)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    } else if let anniversaryDate {
                        Text(anniversaryDate, format: .dateTime.day().month().year())
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    WAvatarBadge(snapshot: entry.snapshot, size: 58)
                    if streak > 1 {
                        WChip(text: "🔥 " + WText.t("\(streak)er-Serie", "\(streak)-day streak"),
                              palette: palette)
                    }
                }
            } else {
                emptyState
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Large

    private var large: some View {
        VStack(spacing: 4) {
            if let days {
                HStack(spacing: 8) {
                    WAvatarBadge(snapshot: entry.snapshot, size: 44)
                    if let name = entry.snapshot?.partnerName, !name.isEmpty {
                        Text(name)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    WHeart(palette: palette)
                }
                Spacer(minLength: 0)
                heroNumber(days, size: 88)
                Text(WText.t("Tage zusammen", "days together"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
                if let anniversaryDate {
                    Text(WText.t("seit ", "since ")
                         + anniversaryDate.formatted(.dateTime.day().month(.wide).year()))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                    if entry.animated, anniversaryDate <= entry.date {
                        Text(anniversaryDate, style: .relative)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if streak > 1 {
                        WChip(text: "🔥 " + WText.t("\(streak)er-Serie", "\(streak)-day streak"),
                              palette: palette)
                    }
                    if let mine = entry.snapshot?.myName, !mine.isEmpty,
                       let theirs = entry.snapshot?.partnerName, !theirs.isEmpty {
                        WChip(text: "\(mine) · \(theirs)", palette: palette)
                    }
                }
            } else {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Extra large (iPad — Welle 7 [26])

    /// The iPad-wide family is a true two-pane layout instead of the
    /// stretched large one: the day count anchors the left, the couple
    /// (avatars, names, streak, next round number) lives on the right.
    /// Same entry, same provider, same timeline — only the canvas grows,
    /// never the reload pressure.
    private var extraLarge: some View {
        HStack(alignment: .center, spacing: 20) {
            if let days {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        WHeart(palette: palette)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    heroNumber(days, size: 124)
                    Text(WText.t("Tage zusammen", "days together"))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                    if let anniversaryDate {
                        Text(WText.t("seit ", "since ")
                             + anniversaryDate.formatted(.dateTime.day().month(.wide).year()))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 12)
                VStack(alignment: .center, spacing: 12) {
                    WAvatarBadge(snapshot: entry.snapshot, size: 84)
                    if let mine = entry.snapshot?.myName, !mine.isEmpty,
                       let theirs = entry.snapshot?.partnerName, !theirs.isEmpty {
                        WChip(text: "\(mine) · \(theirs)", palette: palette)
                    }
                    if entry.animated, let anniversaryDate, anniversaryDate <= entry.date {
                        Text(anniversaryDate, style: .relative)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if streak > 1 {
                        WChip(text: "🔥 " + WText.t("\(streak)er-Serie", "\(streak)-day streak"),
                              palette: palette)
                    }
                    nextMilestoneChip(days)
                }
            } else {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            }
        }
    }

    /// Render-time milestone math (never a timeline dependency): the next
    /// round hundred is always ahead of today, so this line stays honest
    /// for every entry the existing provider produces.
    private func nextMilestoneChip(_ days: Int) -> some View {
        let next = (days / 100 + 1) * 100
        return WChip(text: WText.t("Noch \(next - days) Tage bis \(next)",
                                   "\(next - days) days to \(next)"),
                     palette: palette)
    }

    // MARK: Pieces

    /// The big day count — one implementation for large and extra large.
    private func heroNumber(_ days: Int, size: CGFloat) -> some View {
        Text("\(days)")
            .font(WidgetTypo.counter(size))
            .foregroundStyle(palette.accent)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .contentTransition(.numericText())
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let avatar = entry.snapshot?.partnerAvatar, !avatar.isEmpty {
                Text(avatar)
                    .font(WidgetTypo.glyph(16))
            }
            if let name = entry.snapshot?.partnerName, !name.isEmpty {
                Text(name)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            WHeart(palette: palette)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if entry.snapshot == nil {
            WidgetSetupHint(palette: palette)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "calendar.badge.plus")
                    .font(WidgetTypo.glyph(28, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(WText.t("Jahrestag in der App festlegen", "Set your anniversary in the app"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Accessories

    private var inline: some View {
        Label {
            Text(inlineText)
        } icon: {
            Image(systemName: "heart.fill")
        }
    }

    private var inlineText: String {
        guard let days else { return "SoooDreamy" }
        if days == 1 { return WText.t("1 Tag", "1 day") }
        return WText.t("\(days) Tage", "\(days) days")
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(WidgetTypo.badge)
                Text(days.map { "\($0)" } ?? "—")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(WidgetTypo.glyph(18, weight: .bold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(days.map { WText.t("\($0) Tage zusammen", "\($0) days together") }
                     ?? WText.t("Tage zusammen", "Days together"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                if let name = entry.snapshot?.partnerName {
                    Text(WText.t("mit \(name)", "with \(name)"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct DaysTogetherWidget: Widget {
    let kind = WidgetKindID.daysTogether

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: StudioProvider(kind: kind)) { entry in
            DaysTogetherWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Tage zusammen", "Days together"))
        .description(WText.t("Zählt eure gemeinsamen Tage seit dem Jahrestag.",
                             "Counts your days together since your anniversary."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
