import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif

/// Date-Night-Modus: shared model bits for the evening
/// countdown Live Activity. Both partners run the same choreography —
/// the server relays plan + phase, each phone drives its own activity.
///
/// Phases (raw strings — the widget target has no app models):
///   anticipation ✨ → live 💞 → afterglow 🌙
enum DateNightPhaseID {
    static let anticipation = "anticipation"
    static let live = "live"
    static let afterglow = "afterglow"

    static func emoji(_ phase: String) -> String {
        switch phase {
        case live: return "💞"
        case afterglow: return "🌙"
        default: return "✨"
        }
    }

    static func next(_ phase: String) -> String? {
        switch phase {
        case anticipation: return live
        case live: return afterglow
        default: return nil
        }
    }
}

#if canImport(ActivityKit)
struct DateNightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String?
        var emoji: String?
        var startsAt: Date
        /// See DateNightPhaseID. Phase labels only change when the app (or
        /// the activity's own intent button) updates the state — the
        /// countdown itself renders with Text(timerInterval:) system-side.
        var phase: String
        var phaseChangedAt: Date
        var refreshedAt: Date
        var config: LiveActivityConfig?
    }

    var dateNightId: String
    var partnerName: String?
}

/// Update hygiene: lets the controller skip pushes whose only difference is
/// the refresh stamp (see `ActivityUpdateHygiene`).
extension DateNightActivityAttributes.ContentState: RefreshStampedState {}

/// "Weiter"-button inside the Live Activity: advances the phase. As a
/// LiveActivityIntent in BOTH targets it executes in the app's process —
/// which may be woken in the background, exactly the trick that lets phase
/// labels change without APNs. Self-contained: talks to the server with the
/// app-group credentials and updates the local activity directly.
struct DateNightAdvanceIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Date-Night weiter · Next phase"
    static var description = IntentDescription("Nächste Date-Night-Phase · advance the date night phase")
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        // Advance every running date-night activity locally…
        for activity in Activity<DateNightActivityAttributes>.activities {
            var state = activity.content.state
            guard let next = DateNightPhaseID.next(state.phase) else { continue }
            state.phase = next
            state.phaseChangedAt = Date()
            state.refreshedAt = Date()
            let stale = DateNightLifecycle.staleDate(isAfterglow: next == DateNightPhaseID.afterglow,
                                                     startsAt: state.startsAt,
                                                     phaseChangedAt: state.phaseChangedAt)
            if next == DateNightPhaseID.afterglow {
                // The evening ends with dignity: park the afterglow card,
                // let it leave the lock screen on its own a few hours later.
                await activity.end(
                    ActivityContent(state: state, staleDate: stale),
                    dismissalPolicy: .after(DateNightLifecycle.endDate(phaseChangedAt: state.phaseChangedAt)))
            } else {
                await activity.update(ActivityContent(state: state, staleDate: stale))
            }
            // …and tell the server so the partner's phone follows.
            if let creds = SharedStore.readServerCredentials(),
               let token = SharedKeychain.activeToken(profileID: creds.profileID),
               let base = URL(string: creds.baseURLString) {
                var request = URLRequest(url: base.appendingPathComponent("api/datenight/phase"),
                                         timeoutInterval: 12)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["phase": next])
                _ = try? await URLSession.shared.data(for: request)
            }
        }
        return .result()
    }
}
#endif
