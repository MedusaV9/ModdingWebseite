import SwiftUI

struct WhatsNewEntry: Identifiable {
    let id: String
    let icon: String
    let titleKey: String
    let bodyKey: String
    let destination: AppTab
}

enum WhatsNewCatalog {
    static func entries(for version: String) -> [WhatsNewEntry] {
        switch version {
        case "4.2.0":
            return [
                WhatsNewEntry(
                    id: "dashboard",
                    icon: "✨",
                    titleKey: "whatsnew.4_2.dashboard.title",
                    bodyKey: "whatsnew.4_2.dashboard.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "discovery",
                    icon: "🧭",
                    titleKey: "whatsnew.4_2.discovery.title",
                    bodyKey: "whatsnew.4_2.discovery.body",
                    destination: .settings
                ),
            ]
        case "4.3.0":
            return [
                WhatsNewEntry(
                    id: "replay",
                    icon: "🎬",
                    titleKey: "whatsnew.4_3.replay.title",
                    bodyKey: "whatsnew.4_3.replay.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "season",
                    icon: "🏆",
                    titleKey: "whatsnew.4_3.season.title",
                    bodyKey: "whatsnew.4_3.season.body",
                    destination: .play
                ),
            ]
        case "4.4.0":
            return [
                WhatsNewEntry(
                    id: "states",
                    icon: "🛟",
                    titleKey: "whatsnew.4_4.states.title",
                    bodyKey: "whatsnew.4_4.states.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "lock",
                    icon: "🔐",
                    titleKey: "whatsnew.4_4.lock.title",
                    bodyKey: "whatsnew.4_4.lock.body",
                    destination: .settings
                ),
            ]
        case "4.5.0":
            return [
                WhatsNewEntry(
                    id: "type",
                    icon: "🔎",
                    titleKey: "whatsnew.4_5.type.title",
                    bodyKey: "whatsnew.4_5.type.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "motion",
                    icon: "🌙",
                    titleKey: "whatsnew.4_5.motion.title",
                    bodyKey: "whatsnew.4_5.motion.body",
                    destination: .settings
                ),
            ]
        case "4.6.0":
            return [
                WhatsNewEntry(
                    id: "backup",
                    icon: "📦",
                    titleKey: "whatsnew.4_6.backup.title",
                    bodyKey: "whatsnew.4_6.backup.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "restore",
                    icon: "🛡️",
                    titleKey: "whatsnew.4_6.restore.title",
                    bodyKey: "whatsnew.4_6.restore.body",
                    destination: .settings
                ),
            ]
        case "4.7.0":
            return [
                WhatsNewEntry(
                    id: "widgets",
                    icon: "🧩",
                    titleKey: "whatsnew.4_7.widgets.title",
                    bodyKey: "whatsnew.4_7.widgets.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "controls",
                    icon: "🎛️",
                    titleKey: "whatsnew.4_7.controls.title",
                    bodyKey: "whatsnew.4_7.controls.body",
                    destination: .settings
                ),
            ]
        case "4.8.0":
            return [
                WhatsNewEntry(
                    id: "repair",
                    icon: "🫶",
                    titleKey: "whatsnew.4_8.repair.title",
                    bodyKey: "whatsnew.4_8.repair.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "consideration",
                    icon: "💜",
                    titleKey: "whatsnew.4_8.consideration.title",
                    bodyKey: "whatsnew.4_8.consideration.body",
                    destination: .home
                ),
            ]
        case "4.9.0":
            return [
                WhatsNewEntry(
                    id: "manual",
                    icon: "📖",
                    titleKey: "whatsnew.4_9.manual.title",
                    bodyKey: "whatsnew.4_9.manual.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "locale",
                    icon: "🌍",
                    titleKey: "whatsnew.4_9.locale.title",
                    bodyKey: "whatsnew.4_9.locale.body",
                    destination: .settings
                ),
            ]
        case "5.0.0":
            return [
                WhatsNewEntry(
                    id: "season-calendar",
                    icon: "🗓️",
                    titleKey: "whatsnew.5_0.calendar.title",
                    bodyKey: "whatsnew.5_0.calendar.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "season-frame",
                    icon: "✨",
                    titleKey: "whatsnew.5_0.season.title",
                    bodyKey: "whatsnew.5_0.season.body",
                    destination: .settings
                ),
            ]
        case "5.1.0":
            return [
                WhatsNewEntry(
                    id: "games-wave-two",
                    icon: "🎮",
                    titleKey: "whatsnew.5_1.games.title",
                    bodyKey: "whatsnew.5_1.games.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "game-tutorials",
                    icon: "🎓",
                    titleKey: "whatsnew.5_1.tutorials.title",
                    bodyKey: "whatsnew.5_1.tutorials.body",
                    destination: .play
                ),
            ]
        case "5.2.0":
            return [
                WhatsNewEntry(
                    id: "offline-widening",
                    icon: "🛟",
                    titleKey: "whatsnew.5_2.offline.title",
                    bodyKey: "whatsnew.5_2.offline.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "reliability",
                    icon: "⚡️",
                    titleKey: "whatsnew.5_2.speed.title",
                    bodyKey: "whatsnew.5_2.speed.body",
                    destination: .settings
                ),
            ]
        case "5.3.0":
            return [
                WhatsNewEntry(
                    id: "couple-palette",
                    icon: "🎨",
                    titleKey: "whatsnew.5_3.palette.title",
                    bodyKey: "whatsnew.5_3.palette.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "chat-delight",
                    icon: "✨",
                    titleKey: "whatsnew.5_3.chat.title",
                    bodyKey: "whatsnew.5_3.chat.body",
                    destination: .chat
                ),
            ]
        case "6.0.0":
            return [
                WhatsNewEntry(
                    id: "server-migration",
                    icon: "🚚",
                    titleKey: "whatsnew.6_0.migration.title",
                    bodyKey: "whatsnew.6_0.migration.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "release-complete",
                    icon: "💜",
                    titleKey: "whatsnew.6_0.complete.title",
                    bodyKey: "whatsnew.6_0.complete.body",
                    destination: .home
                ),
            ]
        case "7.0.0":
            return [
                WhatsNewEntry(
                    id: "week-review",
                    icon: "✨",
                    titleKey: "whatsnew.7_0.weekreview.title",
                    bodyKey: "whatsnew.7_0.weekreview.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "custom-questions",
                    icon: "❓",
                    titleKey: "whatsnew.7_0.dailyq.title",
                    bodyKey: "whatsnew.7_0.dailyq.body",
                    destination: .home
                ),
            ]
        case "8.0.0":
            return [
                WhatsNewEntry(
                    id: "on-this-day",
                    icon: "📅",
                    titleKey: "whatsnew.8_0.onthisday.title",
                    bodyKey: "whatsnew.8_0.onthisday.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "story",
                    icon: "📖",
                    titleKey: "whatsnew.8_0.story.title",
                    bodyKey: "whatsnew.8_0.story.body",
                    destination: .memories
                ),
                WhatsNewEntry(
                    id: "memory-widget",
                    icon: "🖼️",
                    titleKey: "whatsnew.8_0.widget.title",
                    bodyKey: "whatsnew.8_0.widget.body",
                    destination: .settings
                ),
            ]
        case "9.0.0":
            return [
                WhatsNewEntry(
                    id: "pulses",
                    icon: "💭",
                    titleKey: "whatsnew.9_0.pulses.title",
                    bodyKey: "whatsnew.9_0.pulses.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "presence",
                    icon: "🎯",
                    titleKey: "whatsnew.9_0.presence.title",
                    bodyKey: "whatsnew.9_0.presence.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "glow",
                    icon: "✨",
                    titleKey: "whatsnew.9_0.glow.title",
                    bodyKey: "whatsnew.9_0.glow.body",
                    destination: .settings
                ),
            ]
        case "10.0.0":
            return [
                WhatsNewEntry(
                    id: "safetynet",
                    icon: "🗝️",
                    titleKey: "whatsnew.10_0.safetynet.title",
                    bodyKey: "whatsnew.10_0.safetynet.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "healing",
                    icon: "🩹",
                    titleKey: "whatsnew.10_0.healing.title",
                    bodyKey: "whatsnew.10_0.healing.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "settings",
                    icon: "🧹",
                    titleKey: "whatsnew.10_0.settings.title",
                    bodyKey: "whatsnew.10_0.settings.body",
                    destination: .settings
                ),
            ]
        case "11.0.0":
            return [
                WhatsNewEntry(
                    id: "polish",
                    icon: "✨",
                    titleKey: "whatsnew.11_0.polish.title",
                    bodyKey: "whatsnew.11_0.polish.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "voice",
                    icon: "💬",
                    titleKey: "whatsnew.11_0.voice.title",
                    bodyKey: "whatsnew.11_0.voice.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "doctor",
                    icon: "🩺",
                    titleKey: "whatsnew.11_0.doctor.title",
                    bodyKey: "whatsnew.11_0.doctor.body",
                    destination: .settings
                ),
            ]
        case "12.0.0":
            return [
                WhatsNewEntry(
                    id: "ipad",
                    icon: "🖥️",
                    titleKey: "whatsnew.12_0.ipad.title",
                    bodyKey: "whatsnew.12_0.ipad.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "devices",
                    icon: "📲",
                    titleKey: "whatsnew.12_0.devices.title",
                    bodyKey: "whatsnew.12_0.devices.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "words",
                    icon: "🪶",
                    titleKey: "whatsnew.12_0.words.title",
                    bodyKey: "whatsnew.12_0.words.body",
                    destination: .chat
                ),
                WhatsNewEntry(
                    id: "tables",
                    icon: "🎲",
                    titleKey: "whatsnew.12_0.tables.title",
                    bodyKey: "whatsnew.12_0.tables.body",
                    destination: .play
                ),
            ]
        case "16.0.0":
            return [
                WhatsNewEntry(
                    id: "postamt",
                    icon: "🏤",
                    titleKey: "whatsnew.16_0.postamt.title",
                    bodyKey: "whatsnew.16_0.postamt.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "geraet",
                    icon: "🎬",
                    titleKey: "whatsnew.16_0.geraet.title",
                    bodyKey: "whatsnew.16_0.geraet.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "zahlen",
                    icon: "🎲",
                    titleKey: "whatsnew.16_0.zahlen.title",
                    bodyKey: "whatsnew.16_0.zahlen.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "gesicht",
                    icon: "💌",
                    titleKey: "whatsnew.16_0.gesicht.title",
                    bodyKey: "whatsnew.16_0.gesicht.body",
                    destination: .settings
                ),
            ]
        case "15.0.0":
            return [
                WhatsNewEntry(
                    id: "night",
                    icon: "🌙",
                    titleKey: "whatsnew.15_0.night.title",
                    bodyKey: "whatsnew.15_0.night.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "gate",
                    icon: "💡",
                    titleKey: "whatsnew.15_0.gate.title",
                    bodyKey: "whatsnew.15_0.gate.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "smooth",
                    icon: "🎬",
                    titleKey: "whatsnew.15_0.smooth.title",
                    bodyKey: "whatsnew.15_0.smooth.body",
                    destination: .settings
                ),
                WhatsNewEntry(
                    id: "tested",
                    icon: "🧪",
                    titleKey: "whatsnew.15_0.tested.title",
                    bodyKey: "whatsnew.15_0.tested.body",
                    destination: .home
                ),
            ]
        case "14.0.0":
            return [
                WhatsNewEntry(
                    id: "room",
                    icon: "🕯️",
                    titleKey: "whatsnew.14_0.room.title",
                    bodyKey: "whatsnew.14_0.room.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "bar",
                    icon: "✨",
                    titleKey: "whatsnew.14_0.bar.title",
                    bodyKey: "whatsnew.14_0.bar.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "post",
                    icon: "💌",
                    titleKey: "whatsnew.14_0.post.title",
                    bodyKey: "whatsnew.14_0.post.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "cinema",
                    icon: "🎬",
                    titleKey: "whatsnew.14_0.cinema.title",
                    bodyKey: "whatsnew.14_0.cinema.body",
                    destination: .settings
                ),
            ]
        case "13.0.0":
            return [
                WhatsNewEntry(
                    id: "face",
                    icon: "🎨",
                    titleKey: "whatsnew.13_0.face.title",
                    bodyKey: "whatsnew.13_0.face.body",
                    destination: .home
                ),
                WhatsNewEntry(
                    id: "games",
                    icon: "🎲",
                    titleKey: "whatsnew.13_0.games.title",
                    bodyKey: "whatsnew.13_0.games.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "soul",
                    icon: "🌱",
                    titleKey: "whatsnew.13_0.soul.title",
                    bodyKey: "whatsnew.13_0.soul.body",
                    destination: .play
                ),
                WhatsNewEntry(
                    id: "eyes",
                    icon: "👀",
                    titleKey: "whatsnew.13_0.eyes.title",
                    bodyKey: "whatsnew.13_0.eyes.body",
                    destination: .home
                ),
            ]
        default:
            return []
        }
    }
}

struct WhatsNewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    let version: String

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(18)) {
                        // SF-Symbol-Herz in der Paar-Tinte statt des alten
                        // Chrome-Emojis (Gebot 1) — skaliert mit Dynamic
                        // Type statt der fixen 58-pt-Größe.
                        Image(systemName: "heart.fill")
                            .font(.system(.largeTitle).weight(.semibold))
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(coupleTint.blend)
                            .accessibilityHidden(true)
                        Text(L10n.t("whatsnew.title", ["version": version]))
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        ForEach(WhatsNewCatalog.entries(for: version)) { entry in
                            Button {
                                appState.activeTab = entry.destination
                                Haptics.shared.tap()
                                dismiss()
                            } label: {
                                HStack(alignment: .top, spacing: LayoutMetrics.s(14)) {
                                    Text(entry.icon)
                                        .font(.scaled(28))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(L10n.t(entry.titleKey))
                                            .font(.system(.headline, design: .rounded).weight(.bold))
                                            .foregroundStyle(Papier.aufNacht)
                                        Text(L10n.t(entry.bodyKey))
                                            .font(.system(.subheadline, design: .rounded))
                                            .foregroundStyle(Nacht.sekundaer)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "arrow.up.right")
                                        .foregroundStyle(Licht.glut)
                                        .accessibilityHidden(true)
                                }
                                .nightCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }
}

struct DashboardEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var pinnedGroupRaw: String
    @Binding var hideRituals: Bool
    @Binding var hideGames: Bool
    @Binding var hideMoments: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.t("dashboard.edit.pin")) {
                    Picker(L10n.t("dashboard.edit.pin"), selection: $pinnedGroupRaw) {
                        Text(L10n.t("dashboard.group.auto")).tag("")
                        Text(L10n.t("dashboard.group.rituals")).tag(DashboardGroup.rituals.rawValue)
                        Text(L10n.t("dashboard.group.games")).tag(DashboardGroup.games.rawValue)
                        Text(L10n.t("dashboard.group.moments")).tag(DashboardGroup.moments.rawValue)
                    }
                    .pickerStyle(.inline)
                }
                Section(L10n.t("dashboard.edit.visibility")) {
                    Toggle(L10n.t("dashboard.group.rituals"), isOn: visible($hideRituals))
                    Toggle(L10n.t("dashboard.group.games"), isOn: visible($hideGames))
                    Toggle(L10n.t("dashboard.group.moments"), isOn: visible($hideMoments))
                }
                Section {
                    Text(L10n.t("dashboard.edit.hint"))
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L10n.t("dashboard.edit.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private func visible(_ hidden: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { !hidden.wrappedValue }, set: { hidden.wrappedValue = !$0 })
    }
}
