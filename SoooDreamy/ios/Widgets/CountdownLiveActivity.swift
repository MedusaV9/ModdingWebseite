import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity (lock screen + Dynamic Island)

struct CountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CountdownActivityAttributes.self) { context in
            CountdownLockScreenView(attributes: context.attributes)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.emoji)
                        .font(.system(size: 30))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        CountdownTimerText(targetDate: context.attributes.targetDate)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(WTheme.pink)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownDaysView(targetDate: context.attributes.targetDate)
                }
            } compactLeading: {
                Text(context.attributes.emoji)
            } compactTrailing: {
                CountdownTimerText(targetDate: context.attributes.targetDate)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(WTheme.pink)
                    .frame(maxWidth: 56)
            } minimal: {
                Text(context.attributes.emoji)
            }
            .keylineTint(WTheme.pink)
        }
    }
}

// MARK: - Lock screen banner

struct CountdownLockScreenView: View {
    let attributes: CountdownActivityAttributes

    var body: some View {
        HStack(spacing: 14) {
            Text(attributes.emoji)
                .font(.system(size: 38))
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                CountdownTimerText(targetDate: attributes.targetDate)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(WTheme.pink)
                if let partnerName = attributes.partnerName, !partnerName.isEmpty {
                    Text(WText.t("mit \(partnerName) 💞", "with \(partnerName) 💞"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(WTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
            CountdownDaysView(targetDate: attributes.targetDate)
        }
        .padding(16)
        .activityBackgroundTint(WTheme.bgTop.opacity(0.9))
        .activitySystemActionForegroundColor(WTheme.pink)
    }
}

// MARK: - Shared pieces

/// Live countdown; clamps to a celebration once the target date has passed.
struct CountdownTimerText: View {
    let targetDate: Date

    var body: some View {
        if targetDate > Date() {
            Text(timerInterval: Date()...targetDate, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.leading)
        } else {
            Text("🎉")
        }
    }
}

/// Remaining whole days, e.g. "12 Tage" in the trailing island region.
struct CountdownDaysView: View {
    let targetDate: Date

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
                .foregroundStyle(WTheme.gold)
            Text(days == 1 ? WText.t("Tag", "day") : WText.t("Tage", "days"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(WTheme.textSecondary)
        }
    }
}
#endif
