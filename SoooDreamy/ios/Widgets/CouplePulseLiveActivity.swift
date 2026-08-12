import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Couple Pulse Live Activity (lock screen + Dynamic Island)
// A living card with the partner's presence, mood, last touch and streak —
// updated locally from the app's WebSocket while it is open.

struct CouplePulseLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CouplePulseAttributes.self) { context in
            CouplePulseLockScreenView(attributes: context.attributes, state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(spacing: 3) {
                        Text(context.state.partnerMood ?? "💞")
                            .font(.system(size: 30))
                        PulseOnlineLabel(online: context.state.partnerOnline)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.partnerName)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        PulseTouchLine(state: context.state)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PulseStreakView(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let note = context.state.partnerMoodNote, !note.isEmpty {
                        Text("“\(note)”")
                            .font(.system(.caption, design: .rounded).italic())
                            .foregroundStyle(WTheme.textSecondary)
                            .lineLimit(1)
                    }
                }
            } compactLeading: {
                Text(context.state.partnerMood ?? "💞")
            } compactTrailing: {
                PulseOnlineDot(online: context.state.partnerOnline)
            } minimal: {
                Text(context.state.partnerMood ?? "💞")
            }
            .keylineTint(WTheme.pink)
        }
    }
}

// MARK: - Lock screen card

struct CouplePulseLockScreenView: View {
    let attributes: CouplePulseAttributes
    let state: CouplePulseAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Text(state.partnerMood ?? "💞")
                    .font(.system(size: 40))
                PulseOnlineDot(online: state.partnerOnline)
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(attributes.partnerName)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    PulseOnlineLabel(online: state.partnerOnline)
                }
                if let note = state.partnerMoodNote, !note.isEmpty {
                    Text("“\(note)”")
                        .font(.system(.caption, design: .rounded).italic())
                        .foregroundStyle(WTheme.textSecondary)
                        .lineLimit(1)
                }
                PulseTouchLine(state: state)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 5) {
                PulseStreakView(state: state)
                if let days = state.daysTogether {
                    Text("\(days) \(WText.t("Tage 💜", "days 💜"))")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(WTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(WTheme.bgTop.opacity(0.9))
        .activitySystemActionForegroundColor(WTheme.pink)
    }
}

// MARK: - Shared pieces

struct PulseOnlineDot: View {
    let online: Bool

    var body: some View {
        Circle()
            .fill(online ? WTheme.mint : Color.white.opacity(0.35))
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
    }
}

struct PulseOnlineLabel: View {
    let online: Bool

    var body: some View {
        Text(online ? "online" : "offline")
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(online ? WTheme.mint : WTheme.textSecondary)
    }
}

/// "💓 vor 5 Min." — the last touch received, with a live relative timestamp.
struct PulseTouchLine: View {
    let state: CouplePulseAttributes.ContentState

    var body: some View {
        if let type = state.lastTouchType, let at = state.lastTouchAt {
            HStack(spacing: 4) {
                Text(TouchEmoji.map(type))
                    .font(.system(size: 13))
                Text(at, style: .relative)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(WTheme.textSecondary)
            }
        } else {
            Text(WText.t("Noch keine Berührung heute", "No touch yet today"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(WTheme.textSecondary)
        }
    }
}

/// Daily-question streak flame + "both answered" check.
struct PulseStreakView: View {
    let state: CouplePulseAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if state.streak > 0 {
                Text("🔥 \(state.streak)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(WTheme.gold)
            }
            if state.bothAnsweredToday {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(WText.t("Beide", "Both"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(WTheme.mint)
            }
        }
    }
}
#endif
