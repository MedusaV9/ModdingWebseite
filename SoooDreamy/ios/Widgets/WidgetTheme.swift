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

// MARK: - Mini design system for the widgets (dreamy night sky)

enum WTheme {
    static let bgTop = Color(hexString: "17062A")
    static let bgBottom = Color(hexString: "2B0F4A")
    static let pink = Color(hexString: "FF5C8A")
    static let purple = Color(hexString: "A855F7")
    static let gold = Color(hexString: "FFD166")
    static let mint = Color(hexString: "6EE7B7")
    static let textSecondary = Color.white.opacity(0.65)

    static let bgGradient = LinearGradient(
        colors: [bgTop, bgBottom],
        startPoint: .top, endPoint: .bottom)

    static let heroGradient = LinearGradient(
        colors: [pink, purple],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let countGradient = LinearGradient(
        colors: [pink, gold],
        startPoint: .leading, endPoint: .trailing)

    /// User-selectable background palettes (Settings → Widgets).
    /// Keep in sync with the preview swatches in SettingsView.swift.
    /// Unknown names (including "photo", which is resolved by
    /// `WidgetChromeBackground` before it gets here) fall back to night.
    static func backgroundColors(named name: String) -> [Color] {
        switch name {
        case "sunset":
            return [Color(hexString: "2B0B3A"), Color(hexString: "8A2E4F"), Color(hexString: "E8785A")]
        case "ocean":
            return [Color(hexString: "04203F"), Color(hexString: "0E4D64"), Color(hexString: "16697A")]
        case "blush":
            return [Color(hexString: "3B0F2A"), Color(hexString: "7C2949"), Color(hexString: "C95D7C")]
        case "mono":
            return [Color(hexString: "0D0D12"), Color(hexString: "232331")]
        default:
            return [bgTop, bgBottom]   // "night"
        }
    }

    /// Prefs-driven widget background gradient.
    static func background(named name: String) -> some View {
        LinearGradient(colors: backgroundColors(named: name),
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Widget chrome (prefs-driven container background)

/// Container background resolved from `SharedStore.readPrefs()`:
/// the user-picked gradient, or — for the "photo" style / photo-friendly
/// widgets with `usePhotoChrome` on — the cached showcase photo, dimmed
/// enough to keep white text legible.
struct WidgetChromeBackground: View {
    var prefs: WidgetPrefs = SharedStore.readPrefs()
    /// Photo/canvas widgets pass `true` so the `usePhotoChrome` pref applies.
    var photoFriendly = false

    private var wantsPhoto: Bool {
        prefs.background == "photo" || (photoFriendly && prefs.usePhotoChrome)
    }

    var body: some View {
        if wantsPhoto,
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
            WTheme.background(named: prefs.background)
        }
    }
}

/// Applies the prefs-driven container background to a widget view.
struct WidgetChrome: ViewModifier {
    var photoFriendly = false

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            WidgetChromeBackground(prefs: SharedStore.readPrefs(),
                                   photoFriendly: photoFriendly)
        }
    }
}

extension View {
    /// Container background from the user's widget prefs (Settings → Widgets).
    func widgetChrome(photoFriendly: Bool = false) -> some View {
        modifier(WidgetChrome(photoFriendly: photoFriendly))
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
    static func t(_ de: String, _ en: String) -> String {
        SharedStore.resolvedLanguage == "de" ? de : en
    }
}
