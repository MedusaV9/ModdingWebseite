import AppIntents
import Foundation

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

// MARK: - Send love

struct SendLoveIntent: AppIntent {
    static var title: LocalizedStringResource = "Send love"
    static var description = IntentDescription("Sends a little love touch to your partner.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Art", default: .heartbeat)
    var type: TouchTypeAppEnum

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

        let partner = SharedStore.readSnapshot()?.partnerName
            ?? (L10n.isGerman ? "deinen Schatz" : "your love")
        let message = L10n.isGerman
            ? "\(type.emoji) \(type.germanName) an \(partner) geschickt!"
            : "\(type.emoji) Sent \(type.englishName) to \(partner)!"
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Partner mood

struct PartnerMoodIntent: AppIntent {
    static var title: LocalizedStringResource = "Partner mood"
    static var description = IntentDescription("Tells you how your partner is feeling right now.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SharedStore.readSnapshot()
        let name = snapshot?.partnerName ?? (L10n.isGerman ? "Dein Schatz" : "Your love")

        guard let mood = snapshot?.partnerMood, !mood.isEmpty else {
            let message = L10n.isGerman
                ? "\(name) hat noch keine Stimmung geteilt. 💭"
                : "\(name) hasn't shared a mood yet. 💭"
            return .result(dialog: IntentDialog(stringLiteral: message))
        }

        var message = L10n.isGerman
            ? "\(name) fühlt sich gerade so: \(mood)"
            : "\(name) is feeling \(mood) right now"
        if let note = snapshot?.partnerMoodNote, !note.isEmpty {
            message += L10n.isGerman ? " — „\(note)“" : " — “\(note)”"
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - Shortcuts provider

struct SoooDreamyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SendLoveIntent(),
            phrases: [
                "Schick Liebe mit \(.applicationName)",
                "Send love with \(.applicationName)",
                "Herzklopfen mit \(.applicationName)",
                "Send a heartbeat with \(.applicationName)"
            ],
            shortTitle: "Send love",
            systemImageName: "heart.fill"
        )
        AppShortcut(
            intent: PartnerMoodIntent(),
            phrases: [
                "Wie geht es meinem Schatz? \(.applicationName)",
                "How is my partner feeling? \(.applicationName)",
                "Stimmung von meinem Schatz in \(.applicationName)"
            ],
            shortTitle: "Partner mood",
            systemImageName: "face.smiling"
        )
    }
}
