import AppIntents
import Foundation
import WidgetKit

// MARK: - Theme choice (per-widget override of the studio default)

enum WidgetThemeChoice: String, AppEnum {
    case studio, night, paper, sunset, ocean, blush, mono, dawn, forest, candy, gold, aurora

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Theme")
    }

    static var caseDisplayRepresentations: [WidgetThemeChoice: DisplayRepresentation] {
        [
            .studio: "✨ Studio",
            .night: "🕯️ Zimmer bei Nacht · Lamplit room",
            .paper: "📜 Papier & Licht · Paper & light",
            .sunset: "🌇 Sonnenuntergang · Sunset",
            .ocean: "🌊 Ozean · Ocean",
            .blush: "🌸 Rosé · Blush",
            .mono: "🌑 Mitternacht · Midnight",
            .dawn: "🌅 Morgenrot · Dawn",
            .forest: "🌲 Zauberwald · Forest",
            .candy: "🍬 Zuckerwatte · Candy",
            .gold: "🌟 Golden Hour",
            .aurora: "🌠 Polarlicht · Aurora",
        ]
    }

    /// nil-like sentinel resolved by `WidgetPalette.resolve`.
    var themeId: String? { self == .studio ? nil : rawValue }
}

// MARK: - Layout choice

enum WidgetLayoutChoice: String, AppEnum {
    case auto, classic, hero, minimal

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Layout")
    }

    static var caseDisplayRepresentations: [WidgetLayoutChoice: DisplayRepresentation] {
        [
            .auto: "✨ Studio",
            .classic: "📋 Klassisch · Classic",
            .hero: "💥 Groß · Hero",
            .minimal: "◽️ Minimal",
        ]
    }
}

// MARK: - Layout resolution helper

enum WidgetLayoutResolver {
    /// Effective layout for a widget: intent override → studio config → auto.
    static func resolve(kind: String, intent: WidgetLayoutChoice) -> String {
        if intent != .auto { return intent.rawValue }
        return SharedStore.readStudioConfig().config(for: kind).layout ?? "auto"
    }
}

// MARK: - Generic per-widget configuration (theme + layout)

struct CoupleWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget-Stil · Widget style"
    static var description = IntentDescription("Theme & Layout für dieses Widget · theme & layout for this widget")

    @Parameter(title: "Theme", default: .studio)
    var theme: WidgetThemeChoice

    @Parameter(title: "Layout", default: .auto)
    var layout: WidgetLayoutChoice
}

// MARK: - Countdown configuration (pinned moment + live ticker)

struct WidgetEventEntity: AppEntity {
    var id: String
    var title: String
    var emoji: String
    var date: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Moment")
    }

    static var defaultQuery = WidgetEventQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(title)", subtitle: "\(date)")
    }
}

struct WidgetEventQuery: EntityQuery {
    private func allEvents() -> [WidgetEventEntity] {
        (SharedStore.readSnapshot()?.allEvents ?? []).map {
            WidgetEventEntity(id: $0.id, title: $0.title, emoji: $0.emoji, date: $0.date)
        }
    }

    func entities(for identifiers: [String]) async throws -> [WidgetEventEntity] {
        allEvents().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetEventEntity] {
        allEvents()
    }
}

struct CountdownWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Countdown-Stil · Countdown style"
    static var description = IntentDescription("Moment, Theme & Live-Ticker · moment, theme & live ticker")

    @Parameter(title: "Moment")
    var event: WidgetEventEntity?

    @Parameter(title: "Theme", default: .studio)
    var theme: WidgetThemeChoice

    @Parameter(title: "Layout", default: .auto)
    var layout: WidgetLayoutChoice

    @Parameter(title: "Live-Ticker · live ticker", default: true)
    var animated: Bool
}

// MARK: - Photo configuration

enum WidgetPhotoSourceChoice: String, AppEnum {
    case studio, favorite, newest

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Fotoquelle · Photo source")
    }

    static var caseDisplayRepresentations: [WidgetPhotoSourceChoice: DisplayRepresentation] {
        [
            .studio: "✨ Studio",
            .favorite: "❤️ Favorit · Favorite",
            .newest: "🆕 Neuestes · Newest",
        ]
    }
}

// Photo frames: polaroid / film strip / scrapbook.
enum WidgetPhotoFrameChoice: String, AppEnum {
    case studio, none, polaroid, filmstrip, photobooth, scrapbook

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Rahmen · Frame")
    }

    static var caseDisplayRepresentations: [WidgetPhotoFrameChoice: DisplayRepresentation] {
        [
            .studio: "✨ Studio",
            .none: "🖼️ Ohne Rahmen · No frame",
            .polaroid: "🤍 Polaroid",
            .filmstrip: "🎞️ Filmstreifen · Film strip",
            .photobooth: "📷 Passbildautomat · Photo booth",
            .scrapbook: "📔 Scrapbook",
        ]
    }

    /// Resolved frame id; nil = frameless ("studio" defers to the config).
    var frameId: String? {
        switch self {
        case .studio, .none: return nil
        default: return rawValue
        }
    }
}

struct PhotoWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Foto-Widget · Photo widget"
    static var description = IntentDescription("Welches Foto & welcher Stil · which photo & style")

    @Parameter(title: "Foto · Photo", default: .studio)
    var source: WidgetPhotoSourceChoice

    @Parameter(title: "Theme", default: .studio)
    var theme: WidgetThemeChoice

    @Parameter(title: "Rahmen · Frame", default: .studio)
    var frame: WidgetPhotoFrameChoice
}

// MARK: - Interactive: send a touch straight from the widget

enum WidgetTouchChoice: String, AppEnum {
    case heartbeat, kiss, hug, missyou, tickle, thinking

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Berührung · Touch")
    }

    static var caseDisplayRepresentations: [WidgetTouchChoice: DisplayRepresentation] {
        [
            .heartbeat: "💓 Herzklopfen · Heartbeat",
            .kiss: "💋 Kuss · Kiss",
            .hug: "🤗 Umarmung · Hug",
            .missyou: "🥺 Vermiss dich · Miss you",
            .tickle: "🪶 Kitzeln · Tickle",
            .thinking: "💭 Denk an dich · Thinking of you",
        ]
    }

    var emoji: String { TouchEmoji.map(rawValue) }
}

/// Sends a touch to the partner directly from the widget process (iOS 17
/// interactive widgets) using the app-group-mirrored server credentials.
struct WidgetSendTouchIntent: AppIntent {
    static var title: LocalizedStringResource = "Liebe senden · Send love"
    static var description = IntentDescription("Sendet deinem Schatz eine Berührung · sends your partner a touch")

    @Parameter(title: "Art · Kind", default: .heartbeat)
    var type: WidgetTouchChoice

    init() {}

    init(type: WidgetTouchChoice) {
        self.type = type
    }

    func perform() async throws -> some IntentResult {
        guard let creds = SharedStore.readServerCredentials(),
              let token = SharedKeychain.activeToken(profileID: creds.profileID),
              let base = URL(string: creds.baseURLString) else {
            SendLoveState.record(type: type.rawValue, ok: false)
            return .result()
        }
        var request = URLRequest(url: base.appendingPathComponent("api/touches"),
                                 timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["type": type.rawValue])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            SendLoveState.record(type: type.rawValue, ok: ok)
        } catch {
            SendLoveState.record(type: type.rawValue, ok: false)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKindID.sendLove)
        return .result()
    }
}

/// Tiny app-group flag so the widget can show a short "sent 💌" confirmation
/// (or a failure hint) right after the interactive button was tapped.
enum SendLoveState {
    private static let key = "sooodreamy.sendLove.last"

    struct Last: Codable {
        var type: String
        var ok: Bool
        var at: Date
    }

    static func record(type: String, ok: Bool) {
        if let data = try? JSONEncoder().encode(Last(type: type, ok: ok, at: Date())) {
            SharedStore.defaults.set(data, forKey: key)
        }
    }

    /// The last send, when it happened within the past `window` seconds.
    static func recent(window: TimeInterval = 75) -> Last? {
        guard let data = SharedStore.defaults.data(forKey: key),
              let last = try? JSONDecoder().decode(Last.self, from: data),
              Date().timeIntervalSince(last.at) < window else { return nil }
        return last
    }
}
