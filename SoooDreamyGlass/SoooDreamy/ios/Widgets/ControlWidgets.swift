import AppIntents
import SwiftUI
import WidgetKit

// Controls: Control Center / Lock Screen / Action Button
// shortcuts. Both reuse the widget-process plumbing that already exists
// (WidgetSendTouchIntent + app-group server credentials), so they work
// without launching the app. The app is iOS 26-only — no gates needed.

/// "Herzklopfen senden": one tap anywhere → the partner's phone pulses.
struct HeartbeatControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.heartbeat"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WidgetSendTouchIntent(type: .heartbeat)) {
                Label("Herzklopfen senden · Send heartbeat", systemImage: "heart.fill")
            }
        }
        .displayName("Herzklopfen · Heartbeat")
        .description("Sendet deinem Schatz sofort ein Herzklopfen · instantly sends your partner a heartbeat")
    }
}

/// "Denk an dich": the gentle one-tap touch requested for the complete
/// iOS-18 control family. It uses the same authenticated widget intent as
/// the interactive Home Screen widget.
struct ThinkingOfYouControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.thinking"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WidgetSendTouchIntent(type: .thinking)) {
                Label("Denk an dich · Thinking of you", systemImage: "heart.text.square.fill")
            }
        }
        .displayName("Denk an dich · Thinking of you")
        .description("Schickt eine sanfte Nachricht an deinen Schatz · sends a gentle touch to your partner")
    }
}

struct StartDateNightControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.date-night"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenDateNightIntent()) {
                Label("Date-Night starten · Start date night", systemImage: "moon.stars.fill")
            }
        }
        .displayName("Date-Night · Date night")
        .description("Öffnet die gemeinsame Date-Night-Planung · opens your shared date-night plan")
    }
}

/// Opens the app right on the dashboard where the need button lives.
struct OpenNeedButtonControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.need"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenNeedButtonIntent()) {
                Label("Bedürfnis-Knopf · Need button", systemImage: "hand.raised.fill")
            }
        }
        .displayName("Bedürfnis-Knopf · Need button")
        .description("Öffnet SoooDreamy beim Bedürfnis-Knopf · opens SoooDreamy at the need button")
    }
}

// MARK: - W7 (43#12/#14): good-night ritual + presence toggle with REAL state

/// "Gute Nacht" as the last tap of the day, right next to the flashlight:
/// presence → sleep, a goodnight pulse and the night check-in — the whole
/// ritual from the lock screen, without launching the app.
struct GoodNightControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.goodnight"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: WidgetGoodNightIntent()) {
                Label("Gute Nacht · Good night", systemImage: "moon.zzz.fill")
            }
        }
        .displayName("Gute Nacht · Good night")
        .description("Schlafmodus, Gute-Nacht-Puls & Check-in — das Abendritual mit einem Tap · the whole evening ritual in one tap")
    }
}

/// The only control with real on/off state: shows whether sleep mode is
/// actually active (app-group mirror) instead of firing blindly.
struct SleepPresenceControlWidget: ControlWidget {
    static let kind = "app.sooodreamy.control.sleep"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetToggle(
                "Schlafmodus · Sleep mode",
                isOn: CoupleServerCall.myPresenceMode() == "sleep",
                action: WidgetSleepToggleIntent()
            ) { isOn in
                Label(isOn ? "Schläft · Asleep" : "Wach · Awake",
                      systemImage: isOn ? "moon.zzz.fill" : "moon")
            }
        }
        .displayName("Schlafmodus · Sleep mode")
        .description("Zeigt & schaltet deinen Schlaf-Status für deinen Schatz · shows and toggles your sleep status")
    }
}

/// Widget-process good-night ritual (three server calls via the shared
/// plumbing). The pulse activity's day-summary ending stays app-side —
/// extensions cannot end activities the app requested.
struct WidgetGoodNightIntent: AppIntent {
    static var title: LocalizedStringResource = "Gute Nacht · Good night"
    static var description = IntentDescription(
        "Schlafmodus an, Gute-Nacht-Puls & Abend-Check-in · sleep mode, goodnight pulse & night check-in")

    init() {}

    func perform() async throws -> some IntentResult {
        _ = await CoupleServerCall.setPresence(mode: "sleep", minutes: 480)
        _ = await CoupleServerCall.sendPulse(kind: "goodnight")
        _ = await CoupleServerCall.checkin(kind: "night")
        ControlCenter.shared.reloadControls(ofKind: SleepPresenceControlWidget.kind)
        return .result()
    }
}

struct WidgetSleepToggleIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Schlafmodus · Sleep mode"
    static var description = IntentDescription(
        "Setzt oder beendet deinen Schlaf-Status · sets or ends your sleep status")

    @Parameter(title: "Schlafen · Sleep")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        if value {
            _ = await CoupleServerCall.setPresence(mode: "sleep", minutes: 480)
        } else {
            _ = await CoupleServerCall.clearPresence()
        }
        ControlCenter.shared.reloadControls(ofKind: SleepPresenceControlWidget.kind)
        return .result()
    }
}

struct OpenDateNightIntent: AppIntent {
    static var title: LocalizedStringResource = "Date-Night starten · Start date night"
    static var description = IntentDescription(
        "Öffnet SoooDreamy bei der Date-Night-Planung · opens SoooDreamy at date-night planning")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "sooodreamy://date-night")!))
    }
}

/// Launches the app via deep link (controls run in the widget process).
struct OpenNeedButtonIntent: AppIntent {
    static var title: LocalizedStringResource = "Bedürfnis-Knopf öffnen · Open need button"
    static var description = IntentDescription(
        "Öffnet SoooDreamy beim Bedürfnis-Knopf · opens SoooDreamy at the need button")
    static var openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "sooodreamy://need")!))
    }
}
