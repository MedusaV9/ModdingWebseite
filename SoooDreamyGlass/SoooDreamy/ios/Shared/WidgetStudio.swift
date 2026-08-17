import Foundation

// Foundation-only widget-studio model shared by app + widget extension
// (and compiled into the Linux logic tests — keep SwiftUI/WidgetKit out).

// MARK: - Paper & light mirror (FullRelease P6-C)

/// The Papier-&-Licht hexes MIRRORED from `Content/PaperRules.swift` —
/// the widget extension compiles standalone (it must not import the app
/// target), so the law table cannot be referenced directly. Every value
/// carries its source constant; `WidgetThemesTests` pins each mirror
/// against the original, so the two tables can never drift apart.
/// Un-prefixed RRGGBB like every other spec hex in this file.
enum WidgetPaperHex {
    /// PaperRules.zimmerObenHex — dark sepia umbra, the night anchor
    /// (nacht-first P1-A: the widgets mirror the darker room).
    static let zimmerOben = "1A100B"
    /// PaperRules.zimmerUntenHex — warm chestnut, lower edge.
    static let zimmerUnten = "2A1B12"
    /// PaperRules.briefHex — letter paper, the standard card surface.
    static let brief = "F7F1E4"
    /// PaperRules.kartonHex — cardboard, secondary surfaces.
    static let karton = "EFE6D2"
    /// PaperRules.polaroidHex — polaroid frame (photos only).
    static let polaroid = "FAF6EC"
    /// PaperRules.tinteDunkelHex — primary ink on paper (13.6:1 on brief).
    static let tinteDunkel = "2E2318"
    /// PaperRules.tinteSekundaerHex — faded ink (7.5:1 on brief).
    static let tinteSekundaer = "5A4A38"
    /// PaperRules.aufNachtHex — text on the room (15.7:1), replaces white.
    static let aufNacht = "F3EAD9"
    /// PaperRules.lampengoldHex — ceremony accent on night (11.9:1).
    static let lampengold = "FFC46B"
    /// PaperRules.glutHex — second warm accent (7.0:1 on night); the app's
    /// `Theme.mint` aliases to this ember since the paper wave.
    static let glut = "E8845E"
    /// PaperRules.wachsRotHex — seal wax, MATERIAL (5.2:1 on paper).
    static let wachsRot = "B33A3A"
    /// PaperRules.wachsGelbHex — warn-amber wax (5.3:1 on brief).
    static let wachsGelb = "8A5A00"
    /// PaperRules.nachtSekundaerOpacity — secondary copy on the room.
    static let nachtSekundaerOpacity = 0.78
}

// MARK: - Theme registry

/// A widget theme as pure data (hex colors) — resolved to SwiftUI gradients
/// by the widget extension and to preview swatches by the in-app studio.
struct WidgetThemeSpec: Codable, Hashable, Identifiable {
    let id: String
    let nameDE: String
    let nameEN: String
    /// Background gradient stops, top-leading → bottom-trailing.
    let backgroundHexes: [String]
    /// Accent used for hero numbers / highlights.
    let accentHex: String
    /// Secondary accent (gradient partner of the accent).
    let accentSecondaryHex: String
    /// True for light backgrounds (dark text needed).
    let isLight: Bool

    func name(lang: String) -> String { lang == "de" ? nameDE : nameEN }
}

enum WidgetThemes {
    /// All available widget themes. IDs are stable — they are persisted in
    /// the app group and in per-widget intent configurations.
    static let all: [WidgetThemeSpec] = [
        // P6-C paperization: the DEFAULT theme (stable id "night" — persisted
        // in configs and pinned by WidgetReliabilityTests) now wears the
        // app's sepia room instead of the retired violet: zimmerOben →
        // zimmerUnten gradient, lampengold + glut accents (WidgetPaperHex).
        WidgetThemeSpec(id: "night", nameDE: "Zimmer bei Nacht", nameEN: "Lamplit room",
                        backgroundHexes: [WidgetPaperHex.zimmerOben, WidgetPaperHex.zimmerUnten],
                        accentHex: WidgetPaperHex.lampengold,
                        accentSecondaryHex: WidgetPaperHex.glut, isLight: false),
        // The daylight twin: paper-card surfaces with wax accents — the only
        // theme where the widget itself IS the sheet of paper.
        WidgetThemeSpec(id: "paper", nameDE: "Papier & Licht", nameEN: "Paper & light",
                        backgroundHexes: [WidgetPaperHex.brief, WidgetPaperHex.karton],
                        accentHex: WidgetPaperHex.wachsRot,
                        accentSecondaryHex: WidgetPaperHex.wachsGelb, isLight: true),
        WidgetThemeSpec(id: "sunset", nameDE: "Sonnenuntergang", nameEN: "Sunset",
                        backgroundHexes: ["2B0B3A", "8A2E4F", "E8785A"],
                        accentHex: "FFD166", accentSecondaryHex: "FF8FAB", isLight: false),
        WidgetThemeSpec(id: "ocean", nameDE: "Ozean", nameEN: "Ocean",
                        backgroundHexes: ["04203F", "0E4D64", "16697A"],
                        accentHex: "6EE7B7", accentSecondaryHex: "60A5FA", isLight: false),
        WidgetThemeSpec(id: "blush", nameDE: "Rosé", nameEN: "Blush",
                        backgroundHexes: ["3B0F2A", "7C2949", "C95D7C"],
                        accentHex: "FFC2D1", accentSecondaryHex: "FFD166", isLight: false),
        WidgetThemeSpec(id: "mono", nameDE: "Mitternacht", nameEN: "Midnight",
                        backgroundHexes: ["0D0D12", "232331"],
                        accentHex: "A855F7", accentSecondaryHex: "6366F1", isLight: false),
        WidgetThemeSpec(id: "dawn", nameDE: "Morgenrot", nameEN: "Dawn",
                        backgroundHexes: ["1D1135", "5C2A6E", "C4699C"],
                        accentHex: "FFE29A", accentSecondaryHex: "FF9DBB", isLight: false),
        WidgetThemeSpec(id: "forest", nameDE: "Zauberwald", nameEN: "Enchanted forest",
                        backgroundHexes: ["07231C", "0E3B2E", "1D5C43"],
                        accentHex: "8AF0C2", accentSecondaryHex: "FFD166", isLight: false),
        WidgetThemeSpec(id: "candy", nameDE: "Zuckerwatte", nameEN: "Cotton candy",
                        backgroundHexes: ["FBD3E9", "E3B5E8", "BBD7F5"],
                        accentHex: "D6336C", accentSecondaryHex: "7048E8", isLight: true),
        WidgetThemeSpec(id: "gold", nameDE: "Golden Hour", nameEN: "Golden hour",
                        backgroundHexes: ["2E1A05", "6E4312", "B87E2C"],
                        accentHex: "FFE08A", accentSecondaryHex: "FF9E6D", isLight: false),
        WidgetThemeSpec(id: "aurora", nameDE: "Polarlicht", nameEN: "Aurora",
                        backgroundHexes: ["061426", "0B3D4A", "1F6E5C", "3E9C6E"],
                        accentHex: "9CF2D4", accentSecondaryHex: "C7A5FF", isLight: false),
        // Picker face only — `WidgetPalette.resolve` swaps in the couple's
        // real colors; the fallback ground is the sepia room, not the violet.
        WidgetThemeSpec(id: "couple", nameDE: "Eure Farben", nameEN: "Your colors",
                        backgroundHexes: [WidgetPaperHex.zimmerOben, WidgetPaperHex.zimmerUnten],
                        accentHex: "FF5C8A", accentSecondaryHex: "A855F7", isLight: false),
        // W7/35-Rest icon+widget family set: resolved DYNAMICALLY against
        // the active home-screen icon (see `iconSpec`); the hexes here are
        // the classic-icon face shown in pickers and used as fallback —
        // since the Nachtpostamt recolor: Nachtraum ground, goldene Tinte,
        // Glut as the widget-only secondary (all PaperRules values).
        WidgetThemeSpec(id: "appicon", nameDE: "Passend zum Icon", nameEN: "Match the icon",
                        backgroundHexes: ["1A100B", "2A1B12", "4A3320"],
                        accentHex: "FFC46B", accentSecondaryHex: "E8845E", isLight: false),
    ]

    static func spec(id: String?) -> WidgetThemeSpec {
        all.first { $0.id == id } ?? all[0]
    }

    // MARK: Icon-matching palettes (W7/35-Rest)

    /// The `AppIconKit` palettes as widget themes: the icon renderer's night
    /// gradient as background, the glass heart as accent — so home screen
    /// icon and widgets can dress as ONE family. Backgrounds and hearts
    /// DERIVE from `IconPaletteTable` (the single source, R2) — only the
    /// display names and the secondary accents live here, because they are
    /// widget-only vocabulary the icon itself never uses.
    static let iconPalettes: [WidgetThemeSpec] = {
        let extras: [String: (de: String, en: String, secondary: String)] = [
            // Nachtpostamt classic: Glut (PaperRules) as the widget-only
            // secondary next to the golden heart — no violet leftovers.
            "classic": ("Klassisch", "Classic", "E8845E"),
            "sunset": ("Sonnenuntergang", "Sunset", "FFD166"),
            "midnight": ("Mitternacht", "Midnight", "B39DFF"),
            "mint": ("Minze", "Mint", "FFD166"),
            "rose": ("Rose", "Rose", "FFC2D1"),
            "ocean": ("Ozean", "Ocean", "6EE7B7"),
            "gold": ("Gold", "Gold", "FFE08A"),
            "lavender": ("Lavendel", "Lavender", "FF9DBB"),
            "blossom": ("Blüte", "Blossom", "FFD166"),
            "aurora": ("Aurora", "Aurora", "C7A5FF"),
        ]
        return IconPaletteTable.entries.map { entry in
            let extra = extras[entry.id] ?? (entry.id, entry.id, entry.heart)
            return WidgetThemeSpec(id: "icon-\(entry.id)",
                                   nameDE: extra.de, nameEN: extra.en,
                                   backgroundHexes: entry.bg,
                                   accentHex: entry.heart,
                                   accentSecondaryHex: extra.secondary,
                                   isLight: false)
        }
    }()

    /// Palette for the "appicon" theme: the spec matching the ACTIVE icon
    /// (the app mirrors the id into the app group on every icon change).
    /// Unknown/nil ids fall back to the classic icon — never a dead widget.
    static func iconSpec(iconId: String?) -> WidgetThemeSpec {
        iconPalettes.first { $0.id == "icon-\(iconId ?? "classic")" } ?? iconPalettes[0]
    }

    /// Spec for RENDERING: resolves the dynamic "appicon" entry against the
    /// mirrored icon id, every other id stays static. Render sites call
    /// this instead of `spec` so the icon+widget family switches together.
    static func renderSpec(id: String?, iconId: String? = nil) -> WidgetThemeSpec {
        id == "appicon" ? iconSpec(iconId: iconId ?? SharedStore.readAppIconId()) : spec(id: id)
    }
}

// MARK: - Widget kinds

/// Stable widget kind identifiers (used by WidgetCenter reloads and as
/// per-widget config keys in the studio).
enum WidgetKindID {
    static let daysTogether = "SoooDreamy.DaysTogether"
    static let mood = "SoooDreamy.Mood"
    static let countdown = "SoooDreamy.Countdown"
    static let daily = "SoooDreamy.DailyQuestion"
    static let streak = "SoooDreamy.Streak"
    static let photo = "SoooDreamy.Photo"
    static let canvas = "SoooDreamy.Canvas"
    static let sendLove = "SoooDreamy.SendLove"
    /// „An diesem Tag" memory widget.
    static let memory = "SoooDreamy.Memory"

    static let all: [String] = [daysTogether, mood, countdown, daily,
                                streak, photo, canvas, sendLove, memory]
}

// MARK: - Studio configuration

/// Per-widget-kind overrides configured in the in-app Widget Studio.
struct WidgetKindConfig: Codable, Hashable {
    /// Theme override; nil → studio default theme.
    var themeId: String?
    /// Layout id ("auto", "classic", "hero", "minimal") — widgets that don't
    /// know a layout fall back to "auto".
    var layout: String?
    /// Live ticking countdown / count-up (Text(timerInterval:)) where supported.
    var animated: Bool?
    /// Photo widget: "favorite" | "newest" — which photo the app showcases.
    var photoSource: String?
    /// Countdown widget: pinned event id; nil → next upcoming event.
    var eventId: String?
    /// Show the daily-question streak flame where supported.
    var showStreak: Bool?
    /// Photo widget frame style: "polaroid" | "filmstrip" | "photobooth" | "scrapbook";
    /// nil → frameless full-bleed photo (pre-3.0 look).
    var photoFrame: String?

    init(themeId: String? = nil, layout: String? = nil, animated: Bool? = nil,
         photoSource: String? = nil, eventId: String? = nil, showStreak: Bool? = nil,
         photoFrame: String? = nil) {
        self.themeId = themeId
        self.layout = layout
        self.animated = animated
        self.photoSource = photoSource
        self.eventId = eventId
        self.showStreak = showStreak
        self.photoFrame = photoFrame
    }

    var isEmpty: Bool {
        themeId == nil && layout == nil && animated == nil
            && photoSource == nil && eventId == nil && showStreak == nil
            && photoFrame == nil
    }
}

/// Everything the Widget Studio configures, written to the app group.
/// Widgets read it on every timeline render.
struct WidgetStudioConfig: Codable, Hashable {
    /// Default theme for all widgets (per-widget overrides win).
    var themeId: String
    /// When true, photo/canvas widgets prefer the showcase photo as chrome.
    var usePhotoChrome: Bool
    /// Per-widget-kind overrides, keyed by `WidgetKindID`.
    var widgets: [String: WidgetKindConfig]

    init(themeId: String = "night", usePhotoChrome: Bool = false,
         widgets: [String: WidgetKindConfig] = [:]) {
        self.themeId = themeId
        self.usePhotoChrome = usePhotoChrome
        self.widgets = widgets
    }

    func config(for kind: String) -> WidgetKindConfig {
        widgets[kind] ?? WidgetKindConfig()
    }

    func theme(for kind: String) -> WidgetThemeSpec {
        // renderSpec: the "appicon" theme resolves to the active icon.
        WidgetThemes.renderSpec(id: config(for: kind).themeId ?? themeId)
    }

    mutating func update(kind: String, _ mutate: (inout WidgetKindConfig) -> Void) {
        var cfg = config(for: kind)
        mutate(&cfg)
        widgets[kind] = cfg.isEmpty ? nil : cfg
    }
}

// MARK: - Server credentials mirror (widget intents + background refresh)

/// The active server session mirrored into the app group so the widget
/// extension (interactive intents, photo fetch) and BGTask refresh can talk
/// to the couple server without launching the app.
struct SharedServerCredentials: Codable, Hashable {
    var baseURLString: String
    var profileID: UUID
}

// MARK: - Shared storage extensions

extension SharedStore {
    static let studioConfigKey = "sooodreamy.widgetStudio.v1"
    static let serverCredentialsKey = "sooodreamy.serverCredentials.v1"

    /// True when the app-group container actually resolves — when this is
    /// false (sideload without app-group entitlement) the widgets cannot see
    /// any data the app writes. Surfaced as a diagnostic in the Widget Studio.
    static var appGroupAvailable: Bool {
        containerURL != nil
    }

    static func writeStudioConfig(_ config: WidgetStudioConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: studioConfigKey)
        }
    }

    static func readStudioConfig() -> WidgetStudioConfig {
        if let data = defaults.data(forKey: studioConfigKey),
           let config = try? JSONDecoder().decode(WidgetStudioConfig.self, from: data) {
            return config
        }
        // Migrate the pre-2.0 prefs (background style + photo chrome) once.
        let legacy = readPrefs()
        return WidgetStudioConfig(themeId: WidgetThemes.all.contains { $0.id == legacy.background }
                                      ? legacy.background : "night",
                                  usePhotoChrome: legacy.usePhotoChrome || legacy.background == "photo")
    }

    static func writeServerCredentials(_ credentials: SharedServerCredentials?) {
        guard let credentials, let data = try? JSONEncoder().encode(credentials) else {
            defaults.removeObject(forKey: serverCredentialsKey)
            return
        }
        defaults.set(data, forKey: serverCredentialsKey)
    }

    static func readServerCredentials() -> SharedServerCredentials? {
        guard let data = defaults.data(forKey: serverCredentialsKey) else { return nil }
        return try? JSONDecoder().decode(SharedServerCredentials.self, from: data)
    }
}

// MARK: - Lightweight event list for widgets

/// All upcoming moments mirrored into the snapshot so the countdown widget
/// can be pinned to a specific event (not just the next one).
struct WidgetEventLite: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var emoji: String
    /// "YYYY-MM-DD"
    var date: String
    var repeatsYearly: Bool
}
