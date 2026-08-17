import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity (lock screen + Dynamic Island)
// Styling + visible elements come from `state.config` (set by the in-app
// Live-Activity sheet) — updating the state restyles the running activity.
//
// W7 (B-20): the controller pins the `staleDate` EXACTLY to the target, so
// `context.isStale` doubles as the guaranteed celebration re-render — the
// party starts on time even when the app has been dead since the night
// before (`CountdownLifecycle.isCelebrating`).

/// Palette helper for live activities: config theme → WidgetPalette.
private let countdownThemeKind = "SoooDreamy.CountdownLiveActivity"

private func laPalette(_ config: LiveActivityConfig?) -> WidgetPalette {
    WidgetPalette.resolve(kind: countdownThemeKind,
                          intentThemeId: config?.themeId ?? "night")
}

struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            CountdownLockScreenView(attributes: context.attributes,
                                    state: context.state,
                                    isStale: context.isStale)
        } dynamicIsland: { context in
            let palette = laPalette(context.state.config)
            let celebrating = CountdownLifecycle.isCelebrating(
                celebrationFlag: context.state.celebration,
                target: context.attributes.targetDate,
                isStale: context.isStale)
            let tapTarget = ActivityLink.url(celebrating ? ActivityLink.celebration
                                                         : ActivityLink.countdown)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(WidgetTypo.glyph(30))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if celebrating {
                            Text(WText.t("Es ist so weit! 🎉", "It's time! 🎉"))
                                .font(.system(.title3, design: .rounded).weight(.heavy))
                                .foregroundStyle(palette.accent)
                        } else {
                            CountdownTimerText(targetDate: context.attributes.targetDate,
                                               live: context.state.config?.liveTimer ?? true)
                                .font(.system(.title2, design: .rounded).weight(.heavy))
                                .foregroundStyle(palette.accent)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !celebrating {
                        CountdownDaysView(targetDate: context.attributes.targetDate,
                                          palette: palette)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        if celebrating, let url = ActivityLink.url(ActivityLink.celebration) {
                            // Celebration: the tap target becomes an action —
                            // capture the moment, straight into the photos.
                            Link(destination: url) {
                                CountdownCaptureHint(palette: palette)
                            }
                        }
                        if !celebrating, context.state.config?.showProgress != false {
                            CountdownProgressBar(state: context.state,
                                                 targetDate: context.attributes.targetDate,
                                                 palette: palette)
                        }
                        CountdownPulseStrip(state: context.state, palette: palette)
                    }
                }
            } compactLeading: {
                Text(context.attributes.emoji)
                    .widgetURL(tapTarget)
            } compactTrailing: {
                Group {
                    if celebrating {
                        Text("🎉")
                    } else if CountdownLifecycle.showsCompactTicker(
                        target: context.attributes.targetDate,
                        liveTimer: context.state.config?.liveTimer ?? true) {
                        CountdownTimerText(targetDate: context.attributes.targetDate,
                                           live: true)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(laPalette(context.state.config).accent)
                            .frame(maxWidth: 56)
                    } else {
                        // Far from the moment a ticking timer is noise — the
                        // static day count says everything (W7 hygiene).
                        CountdownCompactDays(targetDate: context.attributes.targetDate,
                                             palette: laPalette(context.state.config))
                    }
                }
                .widgetURL(tapTarget)
            } minimal: {
                Text(context.attributes.emoji)
                    .widgetURL(tapTarget)
            }
            .keylineTint(palette.accent)
        }
    }
}

// MARK: - Lock screen banner

struct CountdownLockScreenView: View {
    let attributes: CountdownActivityAttributes
    let state: CountdownActivityAttributes.ContentState
    var isStale = false

    private var palette: WidgetPalette { laPalette(state.config) }

    private var celebrating: Bool {
        CountdownLifecycle.isCelebrating(celebrationFlag: state.celebration,
                                         target: attributes.targetDate,
                                         isStale: isStale)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Text(attributes.emoji)
                    .font(WidgetTypo.glyph(38))
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if celebrating {
                        Text(WText.t("Es ist so weit! 🎉", "It's time! 🎉"))
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.accent)
                    } else {
                        CountdownTimerText(targetDate: attributes.targetDate,
                                           live: state.config?.liveTimer ?? true)
                            .font(.system(.title, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.accent)
                    }
                    if let partnerName = attributes.partnerName, !partnerName.isEmpty {
                        Text(WText.t("mit \(partnerName)", "with \(partnerName)"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if celebrating {
                    Text("🎉")
                        .font(WidgetTypo.glyph(34))
                } else {
                    CountdownDaysView(targetDate: attributes.targetDate, palette: palette)
                }
            }
            if !celebrating, state.config?.showProgress != false {
                CountdownProgressBar(state: state, targetDate: attributes.targetDate,
                                     palette: palette)
            }
            CountdownPulseStrip(state: state, palette: palette)
            // Old couple context under a still-running countdown gets the
            // honest footer; the countdown itself ticks system-side anyway.
            if !celebrating {
                PulseFreshnessFooter(refreshedAt: state.refreshedAt,
                                     isStale: isStale,
                                     palette: palette)
            }
        }
        .padding(16)
        .background {
            if celebrating {
                // Deterministic confetti — the same event lays the same
                // pieces on every render (seeded, no runtime randomness).
                WConfetti(eventKey: attributes.eventId ?? attributes.title,
                          slot: CelebrationDay.slot(for: Date(),
                                                    target: attributes.targetDate),
                          palette: palette)
                    .opacity(0.55)
            }
        }
        .activityBackgroundTint(palette.backgroundTint.opacity(0.92))
        .activitySystemActionForegroundColor(palette.accent)
        .widgetURL(ActivityLink.url(celebrating ? ActivityLink.celebration
                                                : ActivityLink.countdown))
    }
}

/// "Haltet den Moment fest 📸" — the celebration's call to action.
struct CountdownCaptureHint: View {
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "camera.fill")
                .font(WidgetTypo.badge)
            Text(WText.t("Haltet den Moment fest", "Capture the moment"))
                .font(.system(.caption2, design: .rounded).weight(.bold))
        }
        .foregroundStyle(palette.accent)
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background(Capsule().fill(palette.accent.opacity(0.22)))
    }
}

/// Auto-filling anticipation bar over the final 48 h (animates on its own —
/// `ProgressView(timerInterval:)` needs no updates from the app).
struct CountdownProgressBar: View {
    let state: CountdownActivityAttributes.ContentState
    let targetDate: Date
    let palette: WidgetPalette

    var body: some View {
        if targetDate > Date(), targetDate.timeIntervalSince(Date()) < 48 * 3600 {
            ProgressView(timerInterval: targetDate.addingTimeInterval(-48 * 3600)...targetDate,
                         countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(palette.accent)
            .frame(height: 4)
        }
    }
}

/// Compact live couple context under the countdown: online dot, mood,
/// last touch and streak — element visibility follows the user's config.
struct CountdownPulseStrip: View {
    let state: CountdownActivityAttributes.ContentState
    let palette: WidgetPalette

    private var config: LiveActivityConfig { state.config ?? LiveActivityConfig() }

    private var hasContent: Bool {
        (config.showPresence && state.partnerOnline != nil)
            || (config.showMood && state.partnerMood != nil)
            || (config.showTouch && state.lastTouchEmoji != nil)
            || (config.showStreak && (state.streak ?? 0) > 0)
    }

    var body: some View {
        if hasContent {
            HStack(spacing: 8) {
                if config.showPresence, let online = state.partnerOnline {
                    Circle()
                        .fill(online ? palette.accent : palette.textSecondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                }
                if config.showMood, let mood = state.partnerMood, !mood.isEmpty {
                    Text(mood)
                        .font(WidgetTypo.glyph(12))
                }
                if config.showTouch, let touch = state.lastTouchEmoji, !touch.isEmpty {
                    Text(touch)
                        .font(WidgetTypo.glyph(12))
                }
                if config.showStreak, let streak = state.streak, streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                        Text("\(streak)")
                            .monospacedDigit()
                    }
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accentSecondary)
                }
                if config.showMood, let note = state.note, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.system(.caption2, design: .rounded).italic())
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Shared pieces

/// Live countdown; clamps to a celebration once the target date has passed.
/// With `live` off it shows a static "in N Tagen" instead of ticking.
struct CountdownTimerText: View {
    let targetDate: Date
    var live = true

    var body: some View {
        if targetDate <= Date() {
            Text("🎉")
        } else if live {
            Text(timerInterval: Date()...targetDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        } else {
            Text(staticText)
        }
    }

    private var staticText: String {
        let days = max(SharedDates.calendar.dateComponents(
            [.day],
            from: SharedDates.calendar.startOfDay(for: Date()),
            to: SharedDates.calendar.startOfDay(for: targetDate)).day ?? 0, 0)
        if days == 0 { return WText.t("heute!", "today!") }
        if days == 1 { return WText.t("morgen", "tomorrow") }
        return WText.t("in \(days) Tagen", "in \(days) days")
    }
}

/// Remaining whole days, e.g. "12 Tage" in the trailing island region.
struct CountdownDaysView: View {
    let targetDate: Date
    var palette: WidgetPalette = WidgetPalette(spec: WidgetThemes.spec(id: "night"))

    private var days: Int {
        let calendar = SharedDates.calendar
        let remaining = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: targetDate)).day ?? 0
        return max(remaining, 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(days)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(palette.accentSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(days == 1 ? WText.t("Tag", "day") : WText.t("Tage", "days"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(palette.textSecondary)
        }
    }
}

/// Static day count for the compact island slot — used beyond the 48 h
/// ticker horizon where a racing timer would only be noise.
struct CountdownCompactDays: View {
    let targetDate: Date
    let palette: WidgetPalette

    private var days: Int {
        let calendar = SharedDates.calendar
        let remaining = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: targetDate)).day ?? 0
        return max(remaining, 0)
    }

    var body: some View {
        Text(WText.t("\(days) Tg.", "\(days)d"))
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(palette.accent)
    }
}
#endif
