import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Views

struct MoodWidgetView: View {
    @Environment(\.widgetFamily) private var family
    // W7 (05#3): StandBy night mode — on the nightstand the widget stops
    // showing numbers and becomes "she's asleep too". Red-tint-safe: white
    // on black only, the system applies the red wash itself.
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    let entry: StudioEntry

    private var palette: WidgetPalette { entry.palette }

    private var nightMode: Bool {
        luminanceReduced && (family == .systemSmall || family == .systemMedium)
    }

    private var partnerAsleep: Bool {
        ActivityHonesty.partnerAsleep(mode: entry.snapshot?.partnerPresenceMode,
                                      until: entry.snapshot?.partnerPresenceUntil,
                                      now: entry.date)
    }

    private var partnerName: String {
        entry.snapshot?.partnerName ?? WText.t("Dein Schatz", "Your partner")
    }

    private var mood: String? {
        guard let mood = entry.snapshot?.partnerMood, !mood.isEmpty else { return nil }
        return mood
    }

    private var moodNote: String? {
        guard let note = entry.snapshot?.partnerMoodNote, !note.isEmpty else { return nil }
        return note
    }

    private var energyEmoji: String? {
        switch entry.snapshot?.partnerEnergyLevel {
        case "green": return "🟢"
        case "yellow": return "🟡"
        case "red": return "🔴"
        default: return nil
        }
    }

    /// W7-Rest reveal seal — recomputed live against `RevealedDailyStore`
    /// at render time, so breaking the seal in the app clears the widget on
    /// its next redraw even before a snapshot rewrite. Deliberately absent
    /// from the StandBy night view: no gold glow on the nightstand.
    private var revealPending: Bool {
        entry.snapshot?.revealSealPending(now: entry.date) ?? false
    }

    var body: some View {
        Group {
            if nightMode {
                nightView
            } else {
                switch family {
                case .accessoryRectangular: rectangular
                case .accessoryInline: inline
                case .systemMedium: medium
                case .systemLarge: large
                default: small
                }
            }
        }
        .widgetChrome(palette, dimmed: nightMode)
        .widgetFreshness(kind: WidgetKindID.mood,
                         updatedAt: entry.snapshot?.updatedAt,
                         now: entry.date, family: family, palette: palette)
        // A pending seal turns the whole widget into the ceremony's door.
        .widgetURL(URL(string: revealPending && !nightMode
                       ? ActivityLink.reveal : "sooodreamy://tab/home"))
    }

    /// StandBy night mode: no numbers, no saturation — just the one thing
    /// that matters at 2 a.m. Costs zero extra reloads (same timeline).
    private var nightView: some View {
        VStack(spacing: 8) {
            Image(systemName: partnerAsleep ? "moon.zzz.fill" : "moon.stars.fill")
                .font(WidgetTypo.glyph(34, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(nightLine)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Honest night copy: "awake" is only claimed while the snapshot says
    /// online; without a signal the line stays a soft guess, not a fact.
    private var nightLine: String {
        if partnerAsleep {
            return WText.t("\(partnerName) schläft auch", "\(partnerName) is asleep too")
        }
        if entry.snapshot?.partnerOnline == true {
            return WText.t("\(partnerName) ist noch wach", "\(partnerName) is still awake")
        }
        return WText.t("\(partnerName) träumt vielleicht schon",
                       "\(partnerName) might be dreaming already")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                WAvatarBadge(snapshot: entry.snapshot, size: 26)
                Text(partnerName)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if revealPending {
                    WSealBadge(size: 18)
                }
            }
            Spacer(minLength: 0)
            if let mood {
                Text(mood)
                    .font(WidgetTypo.glyph(38))
                    .minimumScaleFactor(0.6)
                if let moodNote {
                    Text(moodNote)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                    Text(updatedAt, style: .relative)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
            } else {
                emptyState
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            WAvatarBadge(snapshot: entry.snapshot, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(partnerName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if entry.snapshot?.partnerOnline == true {
                        Text(WText.t("online", "online"))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(WidgetPalette.mint)
                    }
                }
                if revealPending {
                    WSealPill()
                }
                if mood != nil {
                    if let moodNote {
                        Text(moodNote)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textPrimary.opacity(0.9))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                    if let energyEmoji {
                        Text("\(energyEmoji) \(entry.snapshot?.partnerEnergyNote ?? WText.t("Energie", "Energy"))")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text(WText.t("Noch keine Stimmung geteilt", "No mood shared yet"))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 8)
            moodGlyph(size: 54)
                .minimumScaleFactor(0.6)
        }
    }

    /// Large: mood hero + last touch + streak — a little partner dashboard.
    private var large: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                WAvatarBadge(snapshot: entry.snapshot, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(partnerName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(entry.snapshot?.partnerOnline == true
                         ? WText.t("online", "online")
                         : WText.t("gerade nicht da", "away right now"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(entry.snapshot?.partnerOnline == true
                                         ? WidgetPalette.mint : palette.textSecondary)
                }
                Spacer(minLength: 0)
                WHeart(palette: palette)
            }
            Spacer(minLength: 0)
            moodGlyph(size: 92)
                .minimumScaleFactor(0.5)
            if let moodNote {
                Text("“\(moodNote)”")
                    .font(.system(.subheadline, design: .rounded).italic())
                    .foregroundStyle(palette.textPrimary.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                Text(updatedAt, style: .relative)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if revealPending {
                    WSealPill()
                }
                if let energyEmoji {
                    WChip(text: energyEmoji + " " + WText.t("Energie", "Energy"), palette: palette)
                }
                if let title = entry.snapshot?.goalTitle,
                   let percent = entry.snapshot?.goalPercent {
                    WChip(text: "\(entry.snapshot?.goalEmoji ?? "🎯") \(Int(percent))% \(title)",
                          palette: palette)
                }
                if let level = entry.snapshot?.levelNumber {
                    WChip(text: "✨ L\(level)", palette: palette)
                }
                if let touchType = entry.snapshot?.lastTouchType {
                    WChip(text: TouchEmoji.map(touchType) + " "
                          + WText.t("zuletzt", "last"), palette: palette)
                }
                if let streak = entry.snapshot?.streak, streak > 0 {
                    WChip(text: "🔥 \(streak)", palette: palette)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if entry.snapshot == nil {
            WidgetSetupHint(palette: palette)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "bubble.left.fill")
                    .font(WidgetTypo.glyph(28, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(WText.t("Noch keine Stimmung", "No mood yet"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var inline: some View {
        if revealPending {
            Label(WText.t("Euer Reveal wartet", "Your reveal is waiting"),
                  systemImage: "seal.fill")
        } else if let mood {
            Text("\(mood) \(partnerName)")
        } else {
            Label(partnerName, systemImage: "bubble.left.fill")
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            moodGlyph(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(partnerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()
                if mood != nil {
                    if let moodNote {
                        Text(moodNote)
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                    }
                    if let updatedAt = entry.snapshot?.partnerMoodUpdatedAt {
                        Text(updatedAt, style: .relative)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(WText.t("Noch keine Stimmung", "No mood yet"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if revealPending {
                WSealBadge(size: 16)
            }
        }
    }

    @ViewBuilder
    private func moodGlyph(size: CGFloat) -> some View {
        if let mood {
            Text(mood)
                .font(WidgetTypo.glyph(size))
        } else {
            Image(systemName: "bubble.left.fill")
                .font(WidgetTypo.glyph(size * 0.72, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
    }
}

// MARK: - Widget

struct MoodWidget: Widget {
    let kind = WidgetKindID.mood

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: CoupleWidgetConfigIntent.self,
                               provider: StudioProvider(kind: kind)) { entry in
            MoodWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Stimmung", "Mood"))
        .description(WText.t("Zeigt die aktuelle Stimmung deines Schatzes.",
                             "Shows your partner's current mood."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryInline])
    }
}
