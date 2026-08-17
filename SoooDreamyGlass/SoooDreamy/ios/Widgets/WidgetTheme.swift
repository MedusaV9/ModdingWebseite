import SwiftUI
import WidgetKit
import UIKit
import ImageIO

// MARK: - Color helper

extension Color {
    /// "#FF5C8A" / "FF5C8A" → Color.
    /// Named `init(hexString:)` on purpose: `Shared/` is compiled into both
    /// targets and the app target already defines `Color(hex:)` — keeping a
    /// distinct name avoids any clash if files ever move between targets.
    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r: Double
        let g: Double
        let b: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 1; g = 0.36; b = 0.54
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Resolved palette (theme spec → SwiftUI)

/// A `WidgetThemeSpec` resolved into SwiftUI colors/gradients for rendering.
struct WidgetPalette {
    let spec: WidgetThemeSpec

    /// The paper&light home theme (P6-C): the sepia room writes in warm
    /// aufNacht instead of hard white — decorative themes (ocean, sunset …)
    /// keep white for maximum headroom on their free-colored gradients.
    private var isPaperNight: Bool { spec.id == "night" }

    var accent: Color { Color(hexString: spec.accentHex) }
    var accentSecondary: Color { Color(hexString: spec.accentSecondaryHex) }
    /// Light themes write in INK (was the violet-era #26102E): tinteDunkel,
    /// 13.6:1 on brief. The sepia room writes in aufNacht (14.8:1).
    var textPrimary: Color {
        if spec.isLight { return Color(hexString: WidgetPaperHex.tinteDunkel) }
        return isPaperNight ? Color(hexString: WidgetPaperHex.aufNacht) : .white
    }
    /// Secondary copy: solid faded ink on paper (7.5:1), the app's named
    /// 0.78 night step on the room (9.4:1) — decorative themes keep 0.65.
    var textSecondary: Color {
        if spec.isLight { return Color(hexString: WidgetPaperHex.tinteSekundaer) }
        return textPrimary.opacity(isPaperNight ? WidgetPaperHex.nachtSekundaerOpacity : 0.65)
    }
    /// Dynamic Island remains black even when a light widget theme is active.
    var islandTextPrimary: Color { .white }
    var islandTextSecondary: Color { Color.white.opacity(0.65) }
    /// Chips: an ink wash on paper (the innenFill idea), a warm text-toned
    /// wash on dark grounds — no more cold black/white washes.
    var chipFill: Color {
        spec.isLight ? Color(hexString: WidgetPaperHex.tinteDunkel).opacity(0.07)
                     : textPrimary.opacity(0.12)
    }
    var backgroundTint: Color {
        Color(hexString: spec.backgroundHexes.first ?? WidgetPaperHex.zimmerOben)
    }

    var background: LinearGradient {
        LinearGradient(colors: spec.backgroundHexes.map { Color(hexString: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Palette for a widget kind: per-widget/intent override → studio default.
    static func resolve(kind: String, intentThemeId: String? = nil) -> WidgetPalette {
        let studio = SharedStore.readStudioConfig()
        let selectedId: String
        if let intentThemeId, intentThemeId != "studio",
           WidgetThemes.all.contains(where: { $0.id == intentThemeId }) {
            selectedId = intentThemeId
        } else {
            selectedId = studio.config(for: kind).themeId ?? studio.themeId
        }
        if selectedId == "appicon" {
            // W7/35-Rest: widgets dressed like the home-screen icon — the
            // app mirrors the active icon id into the app group, so the
            // whole family switches together on the next render.
            return WidgetPalette(spec: WidgetThemes.renderSpec(id: selectedId))
        }
        if selectedId == "couple",
           let snapshot = SharedStore.readSnapshot(),
           let primary = snapshot.couplePalettePrimary,
           let secondary = snapshot.couplePaletteSecondary,
           let accent = snapshot.couplePaletteAccent {
            return WidgetPalette(spec: WidgetThemeSpec(
                id: "couple",
                nameDE: "Eure Farben",
                nameEN: "Your colors",
                backgroundHexes: [primary, secondary],
                accentHex: accent,
                accentSecondaryHex: secondary,
                isLight: false
            ))
        }
        return WidgetPalette(spec: WidgetThemes.spec(id: selectedId))
    }
}

// MARK: - Fixed semantic accents (theme-independent)

extension WidgetPalette {
    /// The few colors that stay constant across every widget theme —
    /// mirrored from the app's paper&light vocabulary (P6-C, sources in
    /// `WidgetPaperHex`): ceremony gold is the LAMP now, the presence/
    /// success green of the night era became the ember (the app's
    /// `Theme.mint` aliases `Licht.glut`), and the seal wax is the deep
    /// stamp-pad red instead of candy pink.
    static let gold = Color(hexString: WidgetPaperHex.lampengold)
    static let mint = Color(hexString: WidgetPaperHex.glut)
    static let wax = Color(hexString: WidgetPaperHex.wachsRot)
}

// MARK: - Type roles (FXC-4 #13)

/// The widget family's shared type scale. WidgetKit's fixed geometry
/// legitimately needs fixed point sizes (Dynamic Type does not reach
/// widget extensions) — but they live here as NAMED tokens, not as 78
/// inline magic numbers scattered across every file. Wherever a layout
/// tolerates it, dynamic roles (`.caption2` …) stay preferred.
enum WidgetTypo {
    // Counters — heavy rounded numerals; pair with `.monospacedDigit()`.
    /// The one poster number on a systemLarge stage.
    static let counterPoster = Font.system(size: 64, weight: .heavy, design: .rounded)
    /// Hero number of a medium/large layout.
    static let counterHero = Font.system(size: 52, weight: .heavy, design: .rounded)
    /// Standard big count (small families, StandBy).
    static let counterLarge = Font.system(size: 44, weight: .heavy, design: .rounded)
    /// Compact count where the number shares the stage.
    static let counterMedium = Font.system(size: 40, weight: .heavy, design: .rounded)
    /// The smallest hero numeral (inline rows, rectangular accessories).
    static let counterSmall = Font.system(size: 38, weight: .heavy, design: .rounded)

    // Fixed-chrome labels (Dynamic Island regions, chips, badges).
    /// Tiny bold badge/label inside fixed chrome.
    static let badge = Font.system(size: 10, weight: .bold, design: .rounded)
    /// Small caption in island/lock-screen regions.
    static let labelSmall = Font.system(size: 11, weight: .semibold, design: .rounded)
    /// Standard fixed label where dynamic type would overflow the region.
    static let label = Font.system(size: 13, weight: .semibold, design: .rounded)

    /// Free-size counter for stage numbers whose size is layout-driven
    /// (large vs extra-large families share one implementation).
    static func counter(_ points: CGFloat) -> Font {
        .system(size: points, weight: .heavy, design: .rounded)
    }

    /// Emoji/symbol glyph at a fixed or geometry-proportional point size —
    /// emoji ignore text styles, so a numeric size is the only way to set
    /// their optical size (avatar bubbles, mood faces, meters).
    static func glyph(_ points: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: points, weight: weight)
    }

    /// Miniature print on the PhotoWidget polaroid: the tiny fixed sizes
    /// ARE the aesthetic — a shrunken photo print, not UI text.
    static func print(_ points: CGFloat, weight: Font.Weight = .semibold,
                      design: Font.Design = .rounded) -> Font {
        .system(size: points, weight: weight, design: design)
    }
}

// MARK: - Widget chrome (studio-driven container background)

/// Container background resolved from the Widget Studio config: the widget's
/// theme gradient, or — for photo-friendly widgets with photo chrome on —
/// the cached showcase photo, dimmed enough to keep text legible.
struct WidgetChromeBackground: View {
    let palette: WidgetPalette
    /// Photo/canvas widgets pass `true` so the photo-chrome pref applies.
    var photoFriendly = false

    var body: some View {
        if photoFriendly,
           SharedStore.readStudioConfig().usePhotoChrome,
           let data = SharedStore.readCachedPhotoJPEG(),
           let image = WidgetImages.decode(data, maxDimension: 700) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    colors: [Color.black.opacity(0.38), Color.black.opacity(0.62)],
                    startPoint: .top, endPoint: .bottom)
            }
        } else {
            ZStack {
                palette.background
                // The 10-o'clock lamp (P6-C): on the sepia room the sweep is
                // lampengold — the lamp IS the light source, exactly like the
                // app's DreamyBackground; every other theme keeps its white
                // liquid-glass sheen.
                LinearGradient(
                    colors: [sheenColor, .clear],
                    startPoint: .topLeading, endPoint: .center)
            }
        }
    }

    private var sheenColor: Color {
        if palette.spec.id == "night" {
            return Color(hexString: WidgetPaperHex.lampengold).opacity(0.16)
        }
        return Color.white.opacity(palette.spec.isLight ? 0.35 : 0.14)
    }
}

/// Applies the palette-driven container background to a widget view.
struct WidgetChrome: ViewModifier {
    let palette: WidgetPalette
    var photoFriendly = false
    /// StandBy night mode (`isLuminanceReduced`): plain black instead of the
    /// tinted gradient — no glowing rectangle on the nightstand.
    var dimmed = false

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if dimmed {
                Color.black
            } else {
                WidgetChromeBackground(palette: palette, photoFriendly: photoFriendly)
            }
        }
    }
}

extension View {
    /// Container background from the resolved widget palette.
    func widgetChrome(_ palette: WidgetPalette, photoFriendly: Bool = false,
                      dimmed: Bool = false) -> some View {
        modifier(WidgetChrome(palette: palette, photoFriendly: photoFriendly,
                              dimmed: dimmed))
    }

    func widgetFreshness(
        kind: String,
        updatedAt: Date?,
        now: Date,
        family: WidgetFamily,
        palette: WidgetPalette
    ) -> some View {
        overlay(alignment: .topTrailing) {
            if case .stale = WidgetFreshness.state(updatedAt: updatedAt, now: now, kind: kind),
               family != .accessoryInline,
               family != .accessoryCircular {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(WidgetTypo.badge)
                    .foregroundStyle(palette.textSecondary)
                    .padding(5)
                    .background(Circle().fill(palette.chipFill))
                    .accessibilityLabel(WText.t(
                        "Widget-Daten sind älter als üblich",
                        "Widget data is older than usual"
                    ))
            }
        }
    }
}

// MARK: - App-group diagnostics

enum WidgetDiagnostics {
    /// True when the widget can actually read data the app wrote. When the
    /// app group is unavailable (sideload without the group entitlement) the
    /// snapshot is always nil — the widgets show a targeted hint instead of
    /// an eternal placeholder.
    static var hasAppGroup: Bool { SharedStore.appGroupAvailable }

    static var hasSnapshot: Bool { SharedStore.readSnapshot() != nil }

    /// W7 (B-22): the widget-side truth about the session — separates
    /// "signed out" from "never opened" from "app group missing".
    static var connection: WidgetConnection.State {
        WidgetConnection.state(hasAppGroup: hasAppGroup,
                               hasCredentials: SharedStore.readServerCredentials() != nil,
                               hasSnapshot: hasSnapshot)
    }

    /// Snapshot for rendering. After a sign-out the lingering snapshot is
    /// withheld (nil), so no widget ever presents day-old partner mood as
    /// if the connection were merely stale.
    static var renderableSnapshot: WidgetSnapshot? {
        connection == .signedOut ? nil : SharedStore.readSnapshot()
    }
}

/// Friendly hint replacing the eternal-placeholder failure mode: explains
/// whether the session ended (sign back in), data is simply missing (open
/// the app) or the app group is unavailable. Signing details stay in a
/// secondary paragraph so the primary guidance remains easy to understand.
struct WidgetSetupHint: View {
    let palette: WidgetPalette

    private var message: String {
        switch WidgetDiagnostics.connection {
        case .signedOut:
            return WText.t("Abgemeldet — öffne SoooDreamy und verbinde dich neu.",
                           "Signed out — open SoooDreamy and reconnect.")
        case .appGroupMissing:
            return WText.t(
                "Die Widgets können gerade keine Daten aus SoooDreamy lesen. Installiere die App mit deinem Sideload-Tool erneut.",
                "The widgets can’t currently read data from SoooDreamy. Reinstall the app with your sideload tool."
            )
        case .ready, .awaitingFirstOpen:
            return WText.t("Öffne SoooDreamy einmal, dann füllen sich die Widgets.",
                           "Open SoooDreamy once and the widgets fill up.")
        }
    }

    private var technicalDetail: String? {
        switch WidgetDiagnostics.connection {
        case .appGroupMissing:
            return WText.t(
                "Technisches Detail: Die App-Gruppe group.app.sooodreamy.shared muss beim Signieren enthalten sein.",
                "Technical detail: The app group group.app.sooodreamy.shared must be included when signing."
            )
        case .signedOut, .ready, .awaitingFirstOpen:
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "square.grid.2x2.fill")
                .font(WidgetTypo.glyph(24, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(message)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            if let technicalDetail {
                Text(technicalDetail)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Image decoding

enum WidgetImages {
    /// Memory-safe decode: `CGImageSourceCreateThumbnailAtIndex` never
    /// materializes the full-resolution bitmap, so even a huge photo stays
    /// within the widget's tight memory budget.
    static func decode(_ data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Tiny bilingual string helper (German first)

enum WText {
    static var isGerman: Bool { SharedStore.resolvedLanguage == "de" }

    static func t(_ de: String, _ en: String) -> String {
        isGerman ? de : en
    }
}
