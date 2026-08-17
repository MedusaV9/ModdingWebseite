import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Couple Pulse Live Activity (lock screen + Dynamic Island)
// A living card with the partner's presence, mood, last touch and streak —
// updated locally from the app's WebSocket while it is open and from the
// background task while it is not. Style + visible elements come from
// `state.config` (set by the in-app Live-Activity sheet).
//
// W7 honesty rules: once iOS marks the content stale (`context.isStale`,
// 25 min after the last push), the card stops claiming presence and shows
// a moon + "zuletzt aktiv" instead — a relationship app must never fake
// an evening-long "online". Old-but-not-yet-stale data carries a system-
// rendered "aktualisiert vor …" footer.

private let pulseThemeKind = "SoooDreamy.CouplePulse"

private func pulsePalette(_ config: LiveActivityConfig?) -> WidgetPalette {
    WidgetPalette.resolve(kind: pulseThemeKind,
                          intentThemeId: config?.themeId ?? "night")
}

/// Presence-mode styling: SF Symbol, short label and glow tint per mode.
/// Raw strings (not the app's enum) so the extension needs no app models.
private func presenceStyle(_ mode: String?) -> (systemImage: String, label: String, color: Color)? {
    switch mode {
    case "focus": return ("scope", WText.t("Fokus", "focus"), Color(hexString: "8BB8FF"))
    case "sleep": return ("moon.zzz.fill", WText.t("schläft", "sleeping"),
                          Color(hexString: "B39DFF"))
    default: return nil
    }
}

struct CouplePulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CouplePulseAttributes.self) { context in
            CouplePulseLockScreenView(attributes: context.attributes,
                                      state: context.state,
                                      isStale: context.isStale)
        } dynamicIsland: { context in
            let palette = pulsePalette(context.state.config)
            let config = context.state.config ?? LiveActivityConfig()
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(spacing: 3) {
                        PulseMoodIcon(mood: context.state.partnerMood,
                                      palette: palette, size: 30)
                            .contentTransition(.opacity)
                            .presenceGlow(context.isStale ? nil : context.state.partnerPresenceMode)
                        if config.showPresence {
                            PulseOnlineLabel(online: context.state.partnerOnline,
                                             presenceMode: context.state.partnerPresenceMode,
                                             isStale: context.isStale,
                                             palette: palette,
                                             onIsland: true)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.partnerName)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(palette.islandTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if config.showTouch {
                            PulseTouchLine(state: context.state,
                                           palette: palette,
                                           onIsland: true)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Streak + daily question live on the dashboard — give the
                    // region its own, more precise tap target.
                    if let url = ActivityLink.url(ActivityLink.daily) {
                        Link(destination: url) {
                            PulseStreakView(state: context.state, palette: palette)
                        }
                    } else {
                        PulseStreakView(state: context.state, palette: palette)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if context.state.dailyRevealPending == true {
                            // W7-Rest: the sealed reveal outranks the mood
                            // note — it is the one actionable moment here.
                            PulseSealPill()
                        } else if config.showMood,
                                  let note = context.state.partnerMoodNote, !note.isEmpty {
                            Text("“\(note)”")
                                .font(.system(.caption, design: .rounded).italic())
                                .foregroundStyle(palette.islandTextSecondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        // 💓 send one back — right from the island, no app hop.
                        PulseSendBackButton(palette: palette)
                    }
                }
            } compactLeading: {
                PulseMoodIcon(mood: context.state.partnerMood,
                              palette: palette, size: 16)
                    .widgetURL(ActivityLink.url(compactTarget(context)))
            } compactTrailing: {
                Group {
                    if context.isStale {
                        // Honesty in 12 pt: stale presence is a moon, not a dot.
                        Image(systemName: "moon.zzz.fill")
                            .font(WidgetTypo.labelSmall)
                            .foregroundStyle(Color(hexString: "B39DFF"))
                    } else if context.state.dailyRevealPending == true {
                        // W7-Rest: the sealed reveal outranks presence — a
                        // quiet gold seal instead of the online dot.
                        Image(systemName: "seal.fill")
                            .font(WidgetTypo.glyph(11, weight: .bold))
                            .foregroundStyle(palette.accentSecondary)
                            .shadow(color: palette.accentSecondary.opacity(0.9), radius: 4)
                    } else if config.showPresence,
                              let style = presenceStyle(context.state.partnerPresenceMode) {
                        // The mode outranks the online dot — "im Fokus"
                        // says more than "online".
                        Image(systemName: style.systemImage)
                            .font(WidgetTypo.labelSmall)
                            .foregroundStyle(style.color)
                            .shadow(color: style.color.opacity(0.9), radius: 4)
                    } else if config.showPresence {
                        PulseOnlineDot(online: context.state.partnerOnline,
                                       palette: palette)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(WidgetTypo.labelSmall)
                            .foregroundStyle(palette.accent)
                    }
                }
                .widgetURL(ActivityLink.url(compactTarget(context)))
            } minimal: {
                PulseMoodIcon(mood: context.state.partnerMood,
                              palette: palette, size: 16)
                    .widgetURL(ActivityLink.url(compactTarget(context)))
            }
            .keylineTint(palette.accent)
        }
    }
}

/// Compact/minimal island tap target: while a reveal waits (and the data is
/// fresh), the tap jumps straight into the ceremony instead of just home.
private func compactTarget(_ context: ActivityViewContext<CouplePulseAttributes>) -> String {
    context.state.dailyRevealPending == true && !context.isStale
        ? ActivityLink.reveal : ActivityLink.pulse
}

/// W7-Rest: the sealed daily reveal as a subtle gold pill — the shared
/// `WSealPill`, wrapped in a Link straight into the ceremony.
struct PulseSealPill: View {
    var body: some View {
        if let url = ActivityLink.url(ActivityLink.reveal) {
            Link(destination: url) { WSealPill() }
        } else {
            WSealPill()
        }
    }
}

// MARK: - Lock screen card

struct CouplePulseLockScreenView: View {
    let attributes: CouplePulseAttributes
    let state: CouplePulseAttributes.ContentState
    var isStale = false

    private var palette: WidgetPalette { pulsePalette(state.config) }
    private var config: LiveActivityConfig { state.config ?? LiveActivityConfig() }

    var body: some View {
        VStack(spacing: 8) {
            if let summary = state.daySummary, !summary.isEmpty {
                daySummaryCard(summary)
            } else {
                livePulseCard
            }
        }
        .padding(16)
        .activityBackgroundTint(palette.backgroundTint.opacity(0.92))
        .activitySystemActionForegroundColor(palette.accent)
        .widgetURL(ActivityLink.url(ActivityLink.pulse))
    }

    private var livePulseCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    PulseMoodIcon(mood: state.partnerMood,
                                  palette: palette, size: 40)
                        .contentTransition(.opacity)
                        .presenceGlow(isStale ? nil : state.partnerPresenceMode)
                    if config.showPresence, !isStale {
                        PulseOnlineDot(online: state.partnerOnline,
                                       palette: palette)
                            .offset(x: 2, y: 2)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(attributes.partnerName)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if config.showPresence {
                            PulseOnlineLabel(online: state.partnerOnline,
                                             presenceMode: state.partnerPresenceMode,
                                             isStale: isStale,
                                             palette: palette)
                        }
                    }
                    if config.showMood, let note = state.partnerMoodNote, !note.isEmpty {
                        Text("“\(note)”")
                            .font(.system(.caption, design: .rounded).italic())
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    if config.showTouch {
                        PulseTouchLine(state: state, palette: palette)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    PulseStreakView(state: state, palette: palette)
                    if config.showDaysTogether, let days = state.daysTogether {
                        Text("\(days) \(WText.t("Tage", "days"))")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            // W7-Rest: while both answers wait sealed, the card offers the
            // ceremony's door — a gold pill with its own precise tap target.
            if state.dailyRevealPending == true, !isStale {
                HStack {
                    PulseSealPill()
                    Spacer(minLength: 0)
                }
            }
            PulseFreshnessFooter(refreshedAt: state.refreshedAt,
                                 isStale: isStale,
                                 palette: palette)
        }
    }

    /// The good-night ending: one calm closing line instead of a card that
    /// silently rots overnight.
    private func daySummaryCard(_ summary: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(WidgetTypo.glyph(28))
                .foregroundStyle(Color(hexString: "B39DFF"))
                .shadow(color: Color(hexString: "B39DFF").opacity(0.7), radius: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(attributes.partnerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared pieces

struct PulseMoodIcon: View {
    let mood: String?
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        Group {
            if let mood, !mood.isEmpty {
                Text(mood)
            } else {
                Image(systemName: "heart.fill")
                    .foregroundStyle(palette.accent)
            }
        }
        .font(WidgetTypo.glyph(size))
    }
}

struct PulseOnlineDot: View {
    let online: Bool
    let palette: WidgetPalette

    var body: some View {
        Circle()
            .fill(online ? palette.accent : palette.textSecondary.opacity(0.55))
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }
}

struct PulseOnlineLabel: View {
    let online: Bool
    /// When the partner declared 🎯/😴, the mode replaces the plain
    /// online/offline word — it says more.
    var presenceMode: String? = nil
    /// W7 (B-19): stale data must never claim presence. The moon label is a
    /// designed state, not an error.
    var isStale = false
    let palette: WidgetPalette
    var onIsland = false

    private var secondaryColor: Color {
        onIsland ? palette.islandTextSecondary : palette.textSecondary
    }

    var body: some View {
        if isStale {
            HStack(spacing: 3) {
                Image(systemName: "moon.zzz.fill")
                Text(WText.t("zuletzt aktiv", "last seen"))
            }
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(secondaryColor)
        } else if let style = presenceStyle(presenceMode) {
            HStack(spacing: 3) {
                Image(systemName: style.systemImage)
                Text(style.label)
            }
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(style.color)
        } else {
            Text(online ? "online" : "offline")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(online ? palette.accent : secondaryColor)
        }
    }
}

private extension View {
    /// Soft status glow behind the partner emoji while a mode is active.
    @ViewBuilder
    func presenceGlow(_ mode: String?) -> some View {
        if let style = presenceStyle(mode) {
            self.shadow(color: style.color.opacity(0.85), radius: 9)
        } else {
            self
        }
    }
}

/// "💓 vor 5 Min." — the last touch received, with a live relative timestamp.
/// While the partner sleeps the line comes to rest instead of nagging about
/// missing touches (W7 sleep microcopy).
struct PulseTouchLine: View {
    let state: CouplePulseAttributes.ContentState
    let palette: WidgetPalette
    var onIsland = false

    private var secondaryColor: Color {
        onIsland ? palette.islandTextSecondary : palette.textSecondary
    }

    var body: some View {
        if let type = state.lastTouchType, let at = state.lastTouchAt {
            HStack(spacing: 4) {
                Text(TouchEmoji.map(type))
                    .font(WidgetTypo.glyph(13))
                Text(at, style: .relative)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(secondaryColor)
            }
        } else if state.partnerPresenceMode == "sleep" {
            HStack(spacing: 3) {
                Image(systemName: "moon.zzz.fill")
                Text(WText.t("Schläft — bis später", "Asleep — see you later"))
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(secondaryColor)
        } else {
            Text(WText.t("Noch keine Berührung heute", "No touch yet today"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(secondaryColor)
        }
    }
}

/// Transparency footer: once the data is old (or iOS marked it stale), the
/// card says so — rendered system-side via `Text(_, style: .relative)`, so
/// honesty costs zero update budget.
struct PulseFreshnessFooter: View {
    let refreshedAt: Date
    let isStale: Bool
    let palette: WidgetPalette

    var body: some View {
        if ActivityHonesty.showsLastRefresh(refreshedAt: refreshedAt, isStale: isStale) {
            let suffix = WText.t("", "ago")
            HStack(spacing: 4) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(WidgetTypo.glyph(9, weight: .semibold))
                Text(WText.t("aktualisiert vor", "updated"))
                    .font(.system(.caption2, design: .rounded))
                Text(refreshedAt, style: .relative)
                    .font(.system(.caption2, design: .rounded))
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(.system(.caption2, design: .rounded))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.textSecondary.opacity(0.8))
        }
    }
}

/// 💓 "send one back" — a `WidgetSendTouchIntent` button for the island's
/// expanded bottom region; runs in the widget process with app-group creds.
struct PulseSendBackButton: View {
    let palette: WidgetPalette

    var body: some View {
        Button(intent: WidgetSendTouchIntent(type: .heartbeat)) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(WidgetTypo.badge)
                    .foregroundStyle(palette.accent)
                Text(WText.t("Zurücksenden", "Send back"))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 11)
            .background(Capsule().fill(palette.accent.opacity(0.28)))
            .overlay(Capsule().strokeBorder(palette.accent.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.islandTextPrimary)
    }
}

/// Daily-question streak flame + "both answered" check.
struct PulseStreakView: View {
    let state: CouplePulseAttributes.ContentState
    var palette: WidgetPalette = WidgetPalette(spec: WidgetThemes.spec(id: "night"))

    private var config: LiveActivityConfig { state.config ?? LiveActivityConfig() }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if config.showStreak, state.streak > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill")
                    Text("\(state.streak)")
                        .monospacedDigit()
                }
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(palette.accentSecondary)
                    .contentTransition(.numericText())
            }
            if config.showStreak, state.bothAnsweredToday {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(WidgetTypo.badge)
                    Text(WText.t("Beide", "Both"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(palette.accent)
            }
        }
    }
}
#endif
