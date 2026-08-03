import SwiftUI

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
}

// MARK: - Tiny bilingual string helper (German first)

enum WText {
    static func t(_ de: String, _ en: String) -> String {
        SharedStore.resolvedLanguage == "de" ? de : en
    }
}
