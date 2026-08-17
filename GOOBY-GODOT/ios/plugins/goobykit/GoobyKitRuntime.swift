// goobykit — Swift-Laufzeit im HAUPT-App-Target (GOOBY-WIDGETS).
//
// Wird von tools/ci/inject_widgets.rb in das exportierte Xcode-Projekt
// injiziert und von goobykit_bootstrap.mm (goobykit_init → NSClassFromString
// → +start) beim Godot-Engine-Start angestossen.
//
// Aufgaben:
//  1. Datei-Outbox Documents/goobykit/ beobachten (schreibt
//     scripts/platform/goobykit_bridge.gd atomar via tmp+rename):
//     - widget_snapshot.json → App-Group-NSUserDefaults spiegeln und
//       WidgetCenter.reloadAllTimelines() ausloesen.
//     - live_activity.json ({seq, active, payload}) → ActivityKit-Live-
//       Activity starten/aktualisieren/beenden (iOS 16.2+, sonst No-op).
//  2. Bei willResignActive sofort synchronisieren — der letzte Moment vor
//     dem Suspend, ActivityKit-Requests brauchen den Vordergrund.
//
// Kein Godot-Header noetig: die Godot-Seite kennt nur die Datei-Outbox.

import Foundation
import UIKit
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@objc(GoobyKitRuntime)
public final class GoobyKitRuntime: NSObject {
    private static var shared: GoobyKitRuntime?

    private let queue = DispatchQueue(label: "goobykit.outbox", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastSnapshotJson: String = ""
    private var lastActivityJson: String = ""
    private var activitySyncRunning = false

    @objc public static func start() {
        DispatchQueue.main.async {
            if shared == nil {
                let runtime = GoobyKitRuntime()
                shared = runtime
                runtime.begin()
            }
        }
    }

    @objc public static func stop() {
        DispatchQueue.main.async {
            shared?.end()
            shared = nil
        }
    }

    private func begin() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1.0, repeating: 2.0)
        source.setEventHandler { [weak self] in self?.syncOutbox() }
        source.resume()
        timer = source

        // Der letzte Vordergrund-Moment: Godot flusht bei APPLICATION_PAUSED,
        // hier ziehen wir den frischen Stand sofort nach (Activity-Start ist
        // nur im Vordergrund erlaubt).
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncNowFromNotification),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncNowFromNotification),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        NSLog("[goobykit] Outbox-Sync aktiv (Ordner: %@)", Self.outboxDir.path)
    }

    private func end() {
        timer?.cancel()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func syncNowFromNotification() {
        queue.async { [weak self] in self?.syncOutbox() }
    }

    // MARK: - Outbox

    private static var outboxDir: URL {
        let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!
        return documents.appendingPathComponent("goobykit", isDirectory: true)
    }

    private func syncOutbox() {
        syncSnapshot()
        syncLiveActivityFile()
    }

    private func syncSnapshot() {
        let url = Self.outboxDir.appendingPathComponent("widget_snapshot.json")
        guard let json = try? String(contentsOf: url, encoding: .utf8),
            !json.isEmpty, json != lastSnapshotJson
        else { return }
        lastSnapshotJson = json
        guard let defaults = UserDefaults(suiteName: GoobyKitConfig.appGroupId) else {
            NSLog("[goobykit] App-Group %@ nicht verfuegbar", GoobyKitConfig.appGroupId)
            return
        }
        defaults.set(json, forKey: GoobyKitConfig.snapshotKey)
        defaults.set(Date().timeIntervalSince1970, forKey: GoobyKitConfig.snapshotWrittenAtKey)
        WidgetCenter.shared.reloadAllTimelines()
        NSLog("[goobykit] Widget-Snapshot gespiegelt (%@ Zeichen)", String(json.count))
    }

    private func syncLiveActivityFile() {
        let url = Self.outboxDir.appendingPathComponent("live_activity.json")
        guard let json = try? String(contentsOf: url, encoding: .utf8),
            !json.isEmpty, json != lastActivityJson
        else { return }
        lastActivityJson = json
        guard
            let data = json.data(using: .utf8),
            let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            NSLog("[goobykit] live_activity.json unlesbar — ignoriert")
            return
        }
        if #available(iOS 16.2, *) {
            applyLiveActivityEnvelope(envelope)
        }
    }

    // MARK: - Live Activity (iOS 16.2+)

    @available(iOS 16.2, *)
    private func applyLiveActivityEnvelope(_ envelope: [String: Any]) {
        guard !activitySyncRunning else { return }
        activitySyncRunning = true
        let active = envelope["active"] as? Bool ?? false
        let seq = (envelope["seq"] as? NSNumber)?.intValue ?? 0
        let payload = envelope["payload"] as? [String: Any] ?? [:]
        Task { [weak self] in
            await Self.reconcileActivities(active: active, seq: seq, payload: payload)
            self?.queue.async { self?.activitySyncRunning = false }
        }
    }

    @available(iOS 16.2, *)
    private static func reconcileActivities(
        active: Bool, seq: Int, payload: [String: Any]
    ) async {
        let existing = Activity<GoobyActivityAttributes>.activities
        guard active, let state = contentState(from: payload) else {
            for activity in existing {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            if !existing.isEmpty { NSLog("[goobykit] Live Activity beendet") }
            return
        }
        let kind = payload["kind"] as? String ?? ""
        let staleDate = Date(timeIntervalSince1970: Double(state.endsAtMs) / 1000.0 + 60.0)
        let content = ActivityContent(state: state, staleDate: staleDate)
        if let current = existing.first(where: { $0.attributes.kind == kind }),
            existing.count == 1 {
            await current.update(content)
            NSLog("[goobykit] Live Activity aktualisiert (kind=%@, seq=%d)", kind, seq)
            return
        }
        for activity in existing {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            NSLog("[goobykit] Live Activities deaktiviert (System-Einstellung)")
            return
        }
        do {
            _ = try Activity.request(
                attributes: GoobyActivityAttributes(kind: kind), content: content)
            NSLog("[goobykit] Live Activity gestartet (kind=%@, seq=%d)", kind, seq)
        } catch {
            NSLog("[goobykit] Live-Activity-Start fehlgeschlagen: %@", "\(error)")
        }
    }

    @available(iOS 16.1, *)
    private static func contentState(
        from payload: [String: Any]
    ) -> GoobyActivityAttributes.ContentState? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }
        return GoobyActivityAttributes.ContentState(
            title: title,
            statusText: payload["statusText"] as? String ?? "",
            emoji: payload["emoji"] as? String ?? "✨",
            startedAtMs: (payload["startedAtMs"] as? NSNumber)?.intValue ?? 0,
            endsAtMs: (payload["endsAtMs"] as? NSNumber)?.intValue ?? 0)
    }
}
