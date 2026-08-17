// GOOBY-WIDGETS — Live-Activity-UI (Lock Screen + Dynamic Island).
//
// Gestartet/aktualisiert/beendet wird die Activity von GoobyKitRuntime im
// Haupt-App-Target (ActivityKit, iOS 16.2+); die Attributes teilen sich
// beide Targets via GoobyKitShared.swift. Faelle (kind):
//  - "vacation": Urlaubs-/Reise-Countdown (Abflug → Rueckkehr/Abholung)
//  - "sleep":    Gooby schlaeft bis X (Langzeit-Aktion)
//  - "daily":    Tagesbonus-Serie, Countdown bis zum Reset um Mitternacht

import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

struct GoobyLiveActivityView: View {
    let state: GoobyActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14.0) {
            Text(state.emoji).font(.system(size: 40.0))
            VStack(alignment: .leading, spacing: 3.0) {
                Text(state.title).font(.headline).lineLimit(2)
                Text(state.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let range = state.timerRange {
                    Text(timerInterval: range, countsDown: true)
                        .font(.system(size: 26.0, weight: .bold))
                        .monospacedDigit()
                }
            }
            Spacer()
        }
        .padding(14.0)
        .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
    }
}

extension GoobyActivityAttributes.ContentState {
    /// Gueltiger Timer-Bereich oder nil (abgelaufen/kein Ende gesetzt).
    var timerRange: ClosedRange<Date>? {
        guard endsAtMs > 0 else { return nil }
        let now = Date()
        guard endsAt > now else { return nil }
        return now...endsAt
    }
}

struct GoobyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoobyActivityAttributes.self) { context in
            GoobyLiveActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.emoji).font(.title)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2.0) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let range = context.state.timerRange {
                        Text(timerInterval: range, countsDown: true)
                            .font(.headline)
                            .monospacedDigit()
                            .frame(maxWidth: 60.0)
                    }
                }
            } compactLeading: {
                Text(context.state.emoji)
            } compactTrailing: {
                if let range = context.state.timerRange {
                    Text(timerInterval: range, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 48.0)
                } else {
                    Text("✓")
                }
            } minimal: {
                Text(context.state.emoji)
            }
        }
    }
}
