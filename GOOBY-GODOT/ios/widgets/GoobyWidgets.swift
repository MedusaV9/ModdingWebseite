// GOOBY-WIDGETS — WidgetKit-Extension (Target "GoobyWidgets", min iOS 16.2;
// injiziert von tools/ci/inject_widgets.rb als zweites Xcode-Target).
//
// Drei Home-Screen-Widgets + Lock-Screen-Accessories, alle Texte deutsch:
//  - Gooby-Status  (Small/Medium + accessoryCircular/Inline): Stimmungs-
//    Emoji, Muenzen, Statuszeile aus dem Snapshot.
//  - Tagesquest    (Small + accessoryRectangular): Fortschritt des
//    Tagesquest-Bretts (geclaimt/abholbereit/gesamt).
//  - Countdown     (Medium + accessoryRectangular): naechstes Ereignis
//    (Urlaubs-Rueckkehr/Abholung, Aufwachen, Tagesbonus-Reset) mit tickendem
//    Text(timerInterval:).
//
// Datenquelle: App-Group-Snapshot (GoobyWidgetSnapshot.loadFromAppGroup) —
// geschrieben von GoobyKitRuntime beim App-Lauf. Kein Snapshot (frisch
// installiert) → Platzhalter-Zustand mit Hinweis.

import SwiftUI
import UIKit
import WidgetKit

// MARK: - Timeline

struct GoobyEntry: TimelineEntry {
    let date: Date
    let snapshot: GoobyWidgetSnapshot?

    static func sample() -> GoobyEntry {
        var snapshot = GoobyWidgetSnapshot()
        snapshot.nickname = "Gooby"
        snapshot.coins = 1250
        snapshot.moodEmoji = "😊"
        snapshot.statusText = "Gooby ist glücklich."
        snapshot.hunger = 80
        snapshot.energy = 90
        snapshot.questsClaimed = 1
        snapshot.questsClaimable = 1
        snapshot.questsTotal = 3
        snapshot.streak = 4
        snapshot.countdownKind = "dailyReset"
        snapshot.countdownLabel = "Nächster Tagesbonus"
        snapshot.countdownEndsAtMs = Int(Date().timeIntervalSince1970 * 1000.0) + 7_200_000
        return GoobyEntry(date: Date(), snapshot: snapshot)
    }
}

struct GoobyProvider: TimelineProvider {
    func placeholder(in context: Context) -> GoobyEntry {
        GoobyEntry.sample()
    }

    func getSnapshot(in context: Context, completion: @escaping (GoobyEntry) -> Void) {
        if context.isPreview {
            completion(GoobyEntry.sample())
            return
        }
        completion(GoobyEntry(date: Date(), snapshot: GoobyWidgetSnapshot.loadFromAppGroup()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GoobyEntry>) -> Void) {
        let snapshot = GoobyWidgetSnapshot.loadFromAppGroup()
        let now = Date()
        var entries = [GoobyEntry(date: now, snapshot: snapshot)]
        // Countdown-Ende als zweiter Eintrag: das Widget kippt dann von
        // selbst in den "fertig"-Zustand, ohne dass die App laufen muss.
        if let snapshot, snapshot.countdownEndsAtMs > 0, snapshot.countdownEndsAt > now {
            entries.append(GoobyEntry(date: snapshot.countdownEndsAt, snapshot: snapshot))
        }
        // Danach alle 30 min neu versuchen (Budget-schonend; frische Daten
        // kommen ohnehin per reloadAllTimelines aus der App).
        let refreshAt = now.addingTimeInterval(30.0 * 60.0)
        completion(Timeline(entries: entries, policy: .after(refreshAt)))
    }
}

// MARK: - Bausteine

struct GoobyNoDataView: View {
    var body: some View {
        VStack(spacing: 4.0) {
            Text("💤").font(.title)
            Text("Öffne GOOBY einmal,\ndann füllt sich das Widget.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }
}

struct GoobyCoinBadge: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 2.0) {
            Text("🪙")
            Text("\(coins)").fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption)
    }
}

extension View {
    /// containerBackground ist ab iOS 17 Pflicht (StandBy/Smart Stack);
    /// darunter reicht ein normaler Hintergrund.
    @ViewBuilder
    func goobyWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { Color(.systemBackground) }
        } else {
            self
        }
    }
}

// MARK: - Widget 1: Gooby-Status

struct GoobyStatusView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoobyEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else {
                noData
            }
        }
        .goobyWidgetBackground()
    }

    @ViewBuilder
    private var noData: some View {
        switch family {
        case .accessoryCircular: Text("💤")
        case .accessoryInline: Text("GOOBY: noch keine Daten")
        default: GoobyNoDataView()
        }
    }

    @ViewBuilder
    private func content(_ snapshot: GoobyWidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0.0) {
                Text(snapshot.moodEmoji).font(.title3)
                Text("\(snapshot.coins)").font(.caption2).monospacedDigit()
            }
        case .accessoryInline:
            Text("\(snapshot.moodEmoji) \(snapshot.nickname) · 🪙\(snapshot.coins)")
        case .systemMedium:
            HStack(spacing: 12.0) {
                Text(snapshot.moodEmoji).font(.system(size: 52.0))
                VStack(alignment: .leading, spacing: 4.0) {
                    HStack {
                        Text(snapshot.nickname).font(.headline)
                        Spacer()
                        GoobyCoinBadge(coins: snapshot.coins)
                    }
                    Text(snapshot.statusText).font(.caption).lineLimit(2)
                    HStack(spacing: 8.0) {
                        statBar("🍎", snapshot.hunger)
                        statBar("⚡️", snapshot.energy)
                        statBar("🫧", snapshot.hygiene)
                        statBar("🎈", snapshot.fun)
                    }
                }
            }
            .padding(.horizontal, 4.0)
        default:
            VStack(spacing: 4.0) {
                Text(snapshot.moodEmoji).font(.system(size: 40.0))
                Text(snapshot.nickname).font(.caption).fontWeight(.semibold).lineLimit(1)
                Text(snapshot.statusText)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                GoobyCoinBadge(coins: snapshot.coins)
            }
        }
    }

    private func statBar(_ icon: String, _ value: Int) -> some View {
        VStack(spacing: 1.0) {
            Text(icon).font(.caption2)
            ProgressView(value: Double(max(0, min(100, value))), total: 100.0)
                .progressViewStyle(.linear)
                .tint(value < 25 ? .red : .green)
        }
    }
}

struct GoobyStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoobyStatusWidget", provider: GoobyProvider()) { entry in
            GoobyStatusView(entry: entry)
        }
        .configurationDisplayName("Gooby-Status")
        .description("Stimmung, Münzen und Statuszeile deines Goobys.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Widget 2: Tagesquest

struct GoobyQuestView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoobyEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(snapshot)
            } else if family == .accessoryRectangular {
                Text("GOOBY: noch keine Daten").font(.caption2)
            } else {
                GoobyNoDataView()
            }
        }
        .goobyWidgetBackground()
    }

    @ViewBuilder
    private func content(_ snapshot: GoobyWidgetSnapshot) -> some View {
        let done = snapshot.questsClaimed
        let total = snapshot.questsTotal
        let ready = snapshot.questsClaimable
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2.0) {
                Text("📋 Tagesquests").font(.headline)
                ProgressView(value: Double(done), total: Double(total))
                Text(questLine(done: done, total: total, ready: ready)).font(.caption2)
            }
        default:
            VStack(spacing: 6.0) {
                Text("📋").font(.system(size: 28.0))
                Text("Tagesquests").font(.caption).fontWeight(.semibold)
                Gauge(value: Double(done), in: 0.0...Double(total)) {
                    Text("Quests")
                } currentValueLabel: {
                    Text("\(done)/\(total)").monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(done >= total ? .green : .blue)
                Text(questLine(done: done, total: total, ready: ready))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func questLine(done: Int, total: Int, ready: Int) -> String {
        if done >= total {
            return "Alles geschafft! 🎉"
        }
        if ready > 0 {
            return ready == 1 ? "1 Belohnung wartet!" : "\(ready) Belohnungen warten!"
        }
        return "\(done) von \(total) erledigt"
    }
}

struct GoobyQuestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoobyQuestWidget", provider: GoobyProvider()) { entry in
            GoobyQuestView(entry: entry)
        }
        .configurationDisplayName("Tagesquest")
        .description("Fortschritt deiner täglichen Gooby-Quests.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

// MARK: - Widget 3: Countdown

struct GoobyCountdownView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GoobyEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.countdownLabel.isEmpty {
                content(snapshot)
            } else if family == .accessoryRectangular {
                Text("GOOBY: noch keine Daten").font(.caption2)
            } else {
                GoobyNoDataView()
            }
        }
        .goobyWidgetBackground()
    }

    @ViewBuilder
    private func content(_ snapshot: GoobyWidgetSnapshot) -> some View {
        let endsAt = snapshot.countdownEndsAt
        let running = snapshot.countdownEndsAtMs > 0 && endsAt > entry.date
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2.0) {
                Text("\(countdownEmoji(snapshot.countdownKind)) \(snapshot.countdownLabel)")
                    .font(.caption)
                    .lineLimit(1)
                if running {
                    Text(timerInterval: entry.date...endsAt, countsDown: true)
                        .font(.headline)
                        .monospacedDigit()
                } else {
                    Text(doneText(snapshot.countdownKind)).font(.headline)
                }
            }
        default:
            HStack(spacing: 14.0) {
                Text(countdownEmoji(snapshot.countdownKind)).font(.system(size: 44.0))
                VStack(alignment: .leading, spacing: 4.0) {
                    Text(snapshot.countdownLabel).font(.headline).lineLimit(2)
                    if running {
                        Text(timerInterval: entry.date...endsAt, countsDown: true)
                            .font(.system(size: 30.0, weight: .bold))
                            .monospacedDigit()
                    } else {
                        Text(doneText(snapshot.countdownKind))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    Text(snapshot.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4.0)
        }
    }

    private func countdownEmoji(_ kind: String) -> String {
        switch kind {
        case "vacationReturn", "vacationPickup": return "✈️"
        case "sleepWake": return "😴"
        case "dailyReady": return "🎁"
        default: return "⏳"
        }
    }

    private func doneText(_ kind: String) -> String {
        switch kind {
        case "vacationReturn": return "Gleich zurück!"
        case "vacationPickup": return "Wartet am Flughafen!"
        case "sleepWake": return "Wach! 🌞"
        case "dailyReady": return "Bonus bereit! 🎁"
        default: return "Jetzt!"
        }
    }
}

struct GoobyCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GoobyCountdownWidget", provider: GoobyProvider()) { entry in
            GoobyCountdownView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        .description("Nächstes Ereignis: Urlaubs-Rückkehr, Aufwachen oder Tagesbonus.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

// MARK: - Bundle

@main
struct GoobyWidgetBundle: WidgetBundle {
    var body: some Widget {
        GoobyStatusWidget()
        GoobyQuestWidget()
        GoobyCountdownWidget()
        GoobyLiveActivityWidget()
    }
}
