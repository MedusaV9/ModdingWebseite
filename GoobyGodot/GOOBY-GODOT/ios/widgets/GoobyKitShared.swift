// goobykit — GETEILTER Code zwischen Haupt-App und Widget-Extension
// (GOOBY-WIDGETS). tools/ci/inject_widgets.rb kompiliert diese Datei in
// BEIDE Targets: die App braucht GoobyKitConfig + GoobyActivityAttributes
// (ActivityKit-Start), die Extension zusaetzlich das Snapshot-Modell.
//
// Das Snapshot-JSON schreibt scripts/platform/widget_snapshot.gd (Godot,
// Schema-VERSION 1) — Felder dort nachlesen. Der Decoder hier ist bewusst
// tolerant (fehlende Keys → Defaults), damit App-Updates mit neuen Feldern
// nie ein installiertes Widget brechen.

import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

public enum GoobyKitConfig {
    /// MUSS mit der App-Group in den Entitlements (App + Extension) und dem
    /// Aufruf von tools/ci/inject_widgets.rb im Workflow uebereinstimmen.
    public static let appGroupId = "group.com.permissionmaxed.gooby.shared"
    public static let snapshotKey = "gooby.widget.snapshot"
    public static let snapshotWrittenAtKey = "gooby.widget.snapshotWrittenAt"
}

// MARK: - Live-Activity-Attribute (App startet, Extension rendert)

#if canImport(ActivityKit)
@available(iOS 16.1, *)
public struct GoobyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var statusText: String
        public var emoji: String
        public var startedAtMs: Int
        public var endsAtMs: Int

        public init(
            title: String, statusText: String, emoji: String,
            startedAtMs: Int, endsAtMs: Int
        ) {
            self.title = title
            self.statusText = statusText
            self.emoji = emoji
            self.startedAtMs = startedAtMs
            self.endsAtMs = endsAtMs
        }

        public var endsAt: Date { Date(timeIntervalSince1970: Double(endsAtMs) / 1000.0) }
        public var startedAt: Date {
            Date(timeIntervalSince1970: Double(startedAtMs) / 1000.0)
        }
    }

    /// "vacation" | "sleep" | "daily" — stabil pro Activity-Lebenszyklus.
    public var kind: String

    public init(kind: String) {
        self.kind = kind
    }
}
#endif

// MARK: - Widget-Snapshot (Extension liest, App schreibt via App Group)

public struct GoobyWidgetSnapshot {
    public var nickname = "Gooby"
    public var coins = 0
    public var hunger = 0
    public var energy = 0
    public var hygiene = 0
    public var fun = 0
    public var moodEmoji = "🙂"
    public var moodBand = "neutral"
    public var statusText = ""
    public var questsClaimed = 0
    public var questsClaimable = 0
    public var questsTotal = 3
    public var streak = 0
    public var claimedToday = false
    public var countdownKind = ""
    public var countdownLabel = ""
    public var countdownEndsAtMs = 0
    public var generatedAtMs = 0

    public var countdownEndsAt: Date {
        Date(timeIntervalSince1970: Double(countdownEndsAtMs) / 1000.0)
    }

    public static func decode(json: String) -> GoobyWidgetSnapshot? {
        guard
            let data = json.data(using: .utf8),
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        var snapshot = GoobyWidgetSnapshot()
        snapshot.nickname = root["nickname"] as? String ?? "Gooby"
        snapshot.coins = intValue(root["coins"])
        snapshot.generatedAtMs = intValue(root["generatedAtMs"])
        snapshot.statusText = root["statusText"] as? String ?? ""
        if let stats = root["stats"] as? [String: Any] {
            snapshot.hunger = intValue(stats["hunger"])
            snapshot.energy = intValue(stats["energy"])
            snapshot.hygiene = intValue(stats["hygiene"])
            snapshot.fun = intValue(stats["fun"])
        }
        if let mood = root["mood"] as? [String: Any] {
            snapshot.moodEmoji = mood["emoji"] as? String ?? "🙂"
            snapshot.moodBand = mood["band"] as? String ?? "neutral"
        }
        if let quests = root["quests"] as? [String: Any] {
            snapshot.questsClaimed = intValue(quests["claimed"])
            snapshot.questsClaimable = intValue(quests["claimable"])
            snapshot.questsTotal = max(1, intValue(quests["total"]))
        }
        if let daily = root["daily"] as? [String: Any] {
            snapshot.streak = intValue(daily["streak"])
            snapshot.claimedToday = daily["claimedToday"] as? Bool ?? false
        }
        if let countdown = root["countdown"] as? [String: Any] {
            snapshot.countdownKind = countdown["kind"] as? String ?? ""
            snapshot.countdownLabel = countdown["label"] as? String ?? ""
            snapshot.countdownEndsAtMs = intValue(countdown["endsAtMs"])
        }
        return snapshot
    }

    /// Snapshot aus der App Group; nil = App lief noch nie (Platzhalter).
    public static func loadFromAppGroup() -> GoobyWidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: GoobyKitConfig.appGroupId),
            let json = defaults.string(forKey: GoobyKitConfig.snapshotKey)
        else { return nil }
        return decode(json: json)
    }

    private static func intValue(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
