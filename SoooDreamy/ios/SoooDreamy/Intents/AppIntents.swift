import AppIntents
import Foundation

// W7 (K-20, Linse 43): the app outside the app. Sideload reality: Siri
// phrases + App Intents run fully, APNs does not — Shortcuts automations are
// the only reliable "the app speaks up on its own" channel. Every intent
// here degrades gracefully when signed out and always names a way out.

// MARK: - Partner entity (zero-config — there is exactly ONE person)

/// The partner as a Siri entity: "Schick LEA ein Herz" instead of "…mit
/// SoooDreamy". There is exactly one partner, so Siri never has to ask
/// "which one?" — the query always resolves to a single result.
struct PartnerEntity: AppEntity {
    /// Stable single-instance id — the name may change, the entity stays.
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Schatz")
    }

    static var defaultQuery = PartnerQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func current() -> PartnerEntity {
        let name = SharedStore.readSnapshot()?.partnerName
            ?? (L10n.isGerman ? "Schatz" : "your partner")
        return PartnerEntity(id: "partner", name: name)
    }
}

struct PartnerQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PartnerEntity] {
        [PartnerEntity.current()]
    }

    func suggestedEntities() async throws -> [PartnerEntity] {
        [PartnerEntity.current()]
    }

    /// Zero config: the one partner is always the default — no prompt, ever.
    func defaultResult() async -> PartnerEntity? {
        PartnerEntity.current()
    }
}

/// Re-donates the App-Shortcut parameter values whenever the partner's name
/// changes (pairing, rename) — without this Siri never learns the name and
/// "Schick Lea ein Herz" stays dead. Called from `updateWidgetSnapshot()`.
enum PartnerShortcutSync {
    private static let key = "sooodreamy.shortcuts.partnerName"

    static func syncIfNeeded(partnerName: String?) {
        let name = partnerName ?? ""
        guard UserDefaults.standard.string(forKey: key) != name else { return }
        UserDefaults.standard.set(name, forKey: key)
        SoooDreamyShortcuts.updateAppShortcutParameters()
    }
}

// MARK: - Touch type (mirrors TouchKind raw values)

enum TouchTypeAppEnum: String, AppEnum {
    case heartbeat, kiss, hug, missyou, tickle, thinking

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Liebesgruß")
    }

    static var caseDisplayRepresentations: [TouchTypeAppEnum: DisplayRepresentation] {
        [
            .heartbeat: DisplayRepresentation(title: "💓 Herzklopfen"),
            .kiss: DisplayRepresentation(title: "😘 Kuss"),
            .hug: DisplayRepresentation(title: "🫂 Umarmung"),
            .missyou: DisplayRepresentation(title: "🥺 Vermiss dich"),
            .tickle: DisplayRepresentation(title: "🪶 Kitzeln"),
            .thinking: DisplayRepresentation(title: "💭 Denk an dich")
        ]
    }

    var emoji: String {
        TouchKind(rawValue: rawValue)?.emoji ?? "💓"
    }

    var germanName: String {
        switch self {
        case .heartbeat: return "Herzklopfen"
        case .kiss: return "Kuss"
        case .hug: return "Umarmung"
        case .missyou: return "Vermiss-dich"
        case .tickle: return "Kitzeln"
        case .thinking: return "Denk-an-dich"
        }
    }

    var englishName: String {
        switch self {
        case .heartbeat: return "a heartbeat"
        case .kiss: return "a kiss"
        case .hug: return "a hug"
        case .missyou: return "a miss-you"
        case .tickle: return "a tickle"
        case .thinking: return "a loving thought"
        }
    }
}

// MARK: - Pulse kind (thinking-of-you pulses)

enum PulseKindAppEnum: String, AppEnum {
    case thinking, goodnight, heartbeat, hug

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Puls")
    }

    static var caseDisplayRepresentations: [PulseKindAppEnum: DisplayRepresentation] {
        [
            .thinking: DisplayRepresentation(title: "💭 Denk an dich"),
            .goodnight: DisplayRepresentation(title: "🌙 Gute Nacht"),
            .heartbeat: DisplayRepresentation(title: "💓 Herzschlag"),
            .hug: DisplayRepresentation(title: "🤗 Umarmung")
        ]
    }

    var emoji: String {
        PulseKind(rawValue: rawValue)?.emoji ?? "💜"
    }
}

// MARK: - Send love

struct SendLoveIntent: AppIntent {
    static var title: LocalizedStringResource = "Send love"
    static var description = IntentDescription("Sends a little love touch to your partner.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Art", default: .heartbeat)
    var type: TouchTypeAppEnum

    /// Zero-config partner slot — exists so the Siri phrase can carry the
    /// real name ("Schick Lea ein Herz"); the query's `defaultResult()`
    /// resolves it silently, Siri never asks "which one?".
    @Parameter(title: "Schatz")
    var partner: PartnerEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let profile = ServerStore.loadActiveProfileStatic(),
              profile.isPaired,
              let baseURL = profile.baseURL,
              let token = profile.token else {
            let message = L10n.isGerman
                ? "Bitte verbinde dich zuerst in SoooDreamy mit deinem Schatz. 💜"
                : "Please pair with your partner in SoooDreamy first. 💜"
            return .result(dialog: IntentDialog(stringLiteral: message))
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/touches"),
                                 timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["type": type.rawValue])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = L10n.isGerman
                ? "Das hat leider nicht geklappt — ist euer Server erreichbar?"
                : "That didn't work — is your server reachable?"
            return .result(dialog: IntentDialog(stringLiteral: message))
        }

        let message = L10n.isGerman
            ? "\(type.emoji) \(type.germanName) an \(partner.name) geschickt!"
            : "\(type.emoji) Sent \(type.englishName) to \(partner.name)!"
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Send pulse (automation building block: arrival, NFC, charger)

struct SendPulseIntent: AppIntent {
    static var title: LocalizedStringResource = "Puls senden · Send pulse"
    static var description = IntentDescription(
        "Sendet deinem Schatz einen Denk-an-dich-Puls (fühlbares Haptik-Muster) · sends a thinking-of-you pulse.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Puls", default: .thinking)
    var kind: PulseKindAppEnum

    @Parameter(title: "Schatz")
    var partner: PartnerEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let name = partner.name
        switch await CoupleServerCall.sendPulse(kind: kind.rawValue) {
        case .sent:
            let message = L10n.isGerman
                ? "\(kind.emoji) Puls an \(name) unterwegs — gleich spürbar."
                : "\(kind.emoji) Pulse to \(name) on its way — felt in a moment."
            return .result(dialog: IntentDialog(stringLiteral: message))
        case .tooSoon:
            let message = L10n.isGerman
                ? "Dein letzter Puls ist noch unterwegs 💜 — versuch es gleich nochmal."
                : "Your last pulse is still on its way 💜 — try again in a moment."
            return .result(dialog: IntentDialog(stringLiteral: message))
        case .failed:
            let message = L10n.isGerman
                ? "Das hat nicht geklappt — ist euer Server erreichbar?"
                : "That didn't work — is your server reachable?"
            return .result(dialog: IntentDialog(stringLiteral: message))
        }
    }
}

// MARK: - Good night (one intent, three effects — 43#3)

/// "Hey Siri, Gute Nacht": presence → sleep (8 h), a goodnight pulse and the
/// night check-in — the app says goodbye as a couple ritual, not as three
/// taps. Partial success is spoken honestly (GoodNightOutcome, Linux-tested).
struct GoodNightIntent: AppIntent {
    static var title: LocalizedStringResource = "Gute Nacht · Good night"
    static var description = IntentDescription(
        "Schlafmodus an, Gute-Nacht-Puls & Abend-Check-in — das ganze Ritual in einem Satz · sleep mode, goodnight pulse & night check-in in one go.")
    static var openAppWhenRun: Bool = false

    static let sleepMinutes = 480

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = GoodNightOutcome(
            presenceSet: await CoupleServerCall.setPresence(mode: "sleep",
                                                            minutes: Self.sleepMinutes),
            pulseSent: await CoupleServerCall.sendPulse(kind: "goodnight") == .sent,
            checkinDone: await CoupleServerCall.checkin(kind: "night"))
        if outcome.anySucceeded {
            // The pulse card ends the day with its summary line instead of
            // rotting on the lock screen until morning (36#6).
            await CouplePulseController.endWithDaySummary()
        }
        let dialog = outcome.dialog(partnerName: SharedStore.readSnapshot()?.partnerName,
                                    language: SharedStore.resolvedLanguage)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Good morning (alarm-off automation — 43#6)

/// Recipe partner for "when my alarm stops": ends the sleep presence, sets
/// the morning check-in and tells you how your partner is doing.
struct GoodMorningIntent: AppIntent {
    static var title: LocalizedStringResource = "Guten Morgen · Good morning"
    static var description = IntentDescription(
        "Beendet den Schlafmodus, macht den Morgen-Check-in und erzählt, wie es deinem Schatz geht · ends sleep mode, checks in and shares your partner's status.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Clearing a presence that is not set is a harmless no-op server-side.
        _ = await CoupleServerCall.clearPresence()
        let checkinDone = await CoupleServerCall.checkin(kind: "morning")
        let de = L10n.isGerman
        let snapshot = SharedStore.readSnapshot()
        let name = snapshot?.partnerName ?? (de ? "Dein Schatz" : "Your partner")
        var parts: [String] = []
        parts.append(checkinDone
            ? (de ? "Guten Morgen ☀️ — Check-in gesetzt." : "Good morning ☀️ — checked in.")
            : (de ? "Guten Morgen ☀️ — der Check-in hat nicht geklappt, öffne kurz die App."
                  : "Good morning ☀️ — the check-in didn't go through, open the app."))
        parts.append(PartnerStatusLine.line(snapshot: snapshot, name: name, german: de))
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}

// MARK: - Presence building blocks (work focus → focus mode etc., 43#8)

enum PresenceModeAppEnum: String, AppEnum {
    case focus, sleep

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Modus")
    }

    static var caseDisplayRepresentations: [PresenceModeAppEnum: DisplayRepresentation] {
        [
            .focus: DisplayRepresentation(title: "🎯 Fokus · Focus"),
            .sleep: DisplayRepresentation(title: "😴 Schlafen · Sleep")
        ]
    }
}

struct SetPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Status setzen · Set presence"
    static var description = IntentDescription(
        "Sagt deinem Schatz sanft, dass du im Fokus bist oder schläfst · gently tells your partner you're focused or asleep.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Modus", default: .focus)
    var mode: PresenceModeAppEnum

    @Parameter(title: "Minuten · Minutes", default: 120)
    var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await CoupleServerCall.setPresence(mode: mode.rawValue,
                                                    minutes: max(5, min(minutes, 24 * 60)))
        let de = L10n.isGerman
        let message: String
        if ok {
            message = mode == .sleep
                ? (de ? "😴 Schlafmodus an — dein Schatz weiß Bescheid."
                      : "😴 Sleep mode on — your partner knows.")
                : (de ? "🎯 Fokus an — dein Schatz weiß Bescheid."
                      : "🎯 Focus on — your partner knows.")
        } else {
            message = de
                ? "Das hat nicht geklappt — ist euer Server erreichbar?"
                : "That didn't work — is your server reachable?"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct ClearPresenceIntent: AppIntent {
    static var title: LocalizedStringResource = "Wieder da · I'm back"
    static var description = IntentDescription(
        "Beendet Fokus/Schlafmodus — du bist wieder erreichbar · ends focus/sleep mode.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = await CoupleServerCall.clearPresence()
        let de = L10n.isGerman
        let message = ok
            ? (de ? "💜 Wieder da — dein Schatz sieht dich wieder." : "💜 Back — your partner can see you again.")
            : (de ? "Das hat nicht geklappt — ist euer Server erreichbar?"
                  : "That didn't work — is your server reachable?")
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Focus filter (sleep focus drives presence, zero-config — 43#8)

/// The "set up once, runs forever" coupling: add SoooDreamy as a Focus
/// filter to the Sleep (or Work) Focus and iOS sets the couple presence on
/// every focus change by itself — no shortcut, no automation, no forgetting.
struct SooDreamyFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Presence-Kopplung · Presence link"
    static var description = IntentDescription(
        "Setzt deine SoooDreamy-Presence automatisch mit dem Fokus · sets your SoooDreamy presence with this Focus.")

    /// Which presence this focus declares. Default (focus off / not
    /// configured) is "keine" — then a previously filter-set presence is
    /// cleared, but a manually set one is left alone.
    @Parameter(title: "Presence", default: .off)
    var presence: FocusPresenceChoice

    var displayRepresentation: DisplayRepresentation {
        switch presence {
        case .off: return DisplayRepresentation(title: "Presence unverändert")
        case .sleep: return DisplayRepresentation(title: "😴 Presence: Schlafen")
        case .focus: return DisplayRepresentation(title: "🎯 Presence: Fokus")
        }
    }

    private static let appliedKey = "sooodreamy.focusFilter.appliedMode"

    func perform() async throws -> some IntentResult {
        let defaults = SharedStore.defaults
        switch presence {
        case .sleep, .focus:
            let ok = await CoupleServerCall.setPresence(mode: presence.rawValue,
                                                        minutes: 8 * 60)
            if ok { defaults.set(presence.rawValue, forKey: Self.appliedKey) }
        case .off:
            // Only undo what the filter itself set — a manually chosen
            // presence survives every focus change.
            if defaults.string(forKey: Self.appliedKey) != nil {
                _ = await CoupleServerCall.clearPresence()
                defaults.removeObject(forKey: Self.appliedKey)
            }
        }
        return .result()
    }
}

enum FocusPresenceChoice: String, AppEnum {
    case off, sleep, focus

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Presence")
    }

    static var caseDisplayRepresentations: [FocusPresenceChoice: DisplayRepresentation] {
        [
            .off: DisplayRepresentation(title: "Keine · None"),
            .sleep: DisplayRepresentation(title: "😴 Schlafen · Sleep"),
            .focus: DisplayRepresentation(title: "🎯 Fokus · Focus")
        ]
    }
}

// MARK: - Partner status brief (43#4 — logic in Shared/LiveActivityLogic)

struct PartnerMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Partner mood"
    static var description = IntentDescription("Tells you how your partner is doing right now — mood, energy and presence.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Schatz")
    var partner: PartnerEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SharedStore.readSnapshot()
        let de = L10n.isGerman
        let name = partner.name
        var message = PartnerStatusLine.line(snapshot: snapshot, name: name, german: de)
        if let note = snapshot?.partnerMoodNote, !note.isEmpty {
            message += de ? " — „\(note)“" : " — “\(note)”"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Shortcuts provider (curated catalog, ≤10 — 43#26)

struct SoooDreamyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // 1) The emotional core: the partner's real NAME in the phrase.
        AppShortcut(
            intent: SendLoveIntent(),
            phrases: [
                "Schick \(\.$partner) ein Herz mit \(.applicationName)",
                "Schick \(\.$partner) ein Herz in \(.applicationName)",
                "Send \(\.$partner) a heart with \(.applicationName)",
                "Schick \(\.$type) mit \(.applicationName)",
                "Send \(\.$type) with \(.applicationName)",
                "Schick Liebe mit \(.applicationName)",
                "Send love with \(.applicationName)",
                "Herzklopfen mit \(.applicationName)"
            ],
            shortTitle: "Send love",
            systemImageName: "heart.fill"
        )
        // 2) The evening ritual — also the Control/NFC/charger recipe target.
        AppShortcut(
            intent: GoodNightIntent(),
            phrases: [
                "Gute Nacht mit \(.applicationName)",
                "Gute-Nacht-Ritual in \(.applicationName)",
                "Good night with \(.applicationName)",
                "Sag Gute Nacht mit \(.applicationName)"
            ],
            shortTitle: "Gute Nacht",
            systemImageName: "moon.zzz.fill"
        )
        // 3) The alarm-off recipe partner.
        AppShortcut(
            intent: GoodMorningIntent(),
            phrases: [
                "Guten Morgen mit \(.applicationName)",
                "Good morning with \(.applicationName)",
                "Morgen-Check-in mit \(.applicationName)"
            ],
            shortTitle: "Guten Morgen",
            systemImageName: "sun.max.fill"
        )
        // 4) Status brief with the partner's name in the phrase.
        AppShortcut(
            intent: PartnerMoodIntent(),
            phrases: [
                "Wie geht es \(\.$partner) in \(.applicationName)",
                "How is \(\.$partner) doing in \(.applicationName)",
                "Wie geht es meinem Schatz? \(.applicationName)",
                "How is my partner feeling? \(.applicationName)",
                "Stimmung von meinem Schatz in \(.applicationName)"
            ],
            shortTitle: "Partner mood",
            systemImageName: "face.smiling"
        )
        // 5) Pulses — the arrival/automation building block.
        AppShortcut(
            intent: SendPulseIntent(),
            phrases: [
                "Schick \(\.$kind) mit \(.applicationName)",
                "Send \(\.$kind) with \(.applicationName)",
                "Puls an meinen Schatz mit \(.applicationName)",
                "Send a pulse with \(.applicationName)"
            ],
            shortTitle: "Puls senden",
            systemImageName: "wave.3.right"
        )
        // 6+7) Presence building blocks for custom automations.
        AppShortcut(
            intent: SetPresenceIntent(),
            phrases: [
                "Setz mich auf \(\.$mode) in \(.applicationName)",
                "Set me to \(\.$mode) in \(.applicationName)",
                "Ich gehe schlafen mit \(.applicationName)"
            ],
            shortTitle: "Status setzen",
            systemImageName: "person.crop.circle.badge.moon"
        )
        AppShortcut(
            intent: ClearPresenceIntent(),
            phrases: [
                "Ich bin wieder da in \(.applicationName)",
                "I'm back in \(.applicationName)"
            ],
            shortTitle: "Wieder da",
            systemImageName: "person.crop.circle.badge.checkmark"
        )
    }
}
