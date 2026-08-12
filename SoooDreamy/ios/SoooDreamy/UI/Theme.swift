import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {
    /// "#FF5C8A" / "FF5C8A" → Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
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

// MARK: - Responsive layout scale

/// Design baseline = iPhone Pro Max (~430pt wide). Smaller phones shrink
/// proportionally; Pro Max stays 1.0. Extra compression below ~402pt so
/// standard iPhone 16 / non-Pro sizes don't feel oversized.
enum LayoutMetrics {
    static let designWidth: CGFloat = 430

    /// Mutable so RootView can refresh from GeometryReader (split view / future).
    /// Default comes from the main screen bounds.
    static var scale: CGFloat = Self.scale(forWidth: Self.currentScreenWidth)

    static func scale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        var raw = width / designWidth
        // Standard / non-Pro widths feel crowded at pure linear scale.
        if width < 410 { raw *= 0.94 }
        return min(max(raw, 0.78), 1.0)
    }

    /// Apply current scale (rounded to 0.5pt for crisp layout).
    static func s(_ value: CGFloat) -> CGFloat {
        (value * scale * 2).rounded() / 2
    }

    static func update(forWidth width: CGFloat) {
        scale = scale(forWidth: width)
    }

    private static var currentScreenWidth: CGFloat {
        #if canImport(UIKit)
        // Portrait phone app — longest side is height; use short side as width.
        let bounds = UIScreen.main.bounds
        return min(bounds.width, bounds.height)
        #else
        return designWidth
        #endif
    }
}

private struct LayoutScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = LayoutMetrics.scale
}

extension EnvironmentValues {
    var layoutScale: CGFloat {
        get { self[LayoutScaleKey.self] }
        set { self[LayoutScaleKey.self] = newValue }
    }
}

extension Font {
    /// Scaled display/hero font. Prefer semantic `.system(.body)` etc. for body copy.
    static func scaled(_ size: CGFloat,
                       weight: Font.Weight = .regular,
                       design: Font.Design = .rounded) -> Font {
        .system(size: LayoutMetrics.s(size), weight: weight, design: design)
    }
}

extension View {
    /// Scaled fixed frame (decorative glyphs, QR, hero canvases).
    func sFrame(width: CGFloat? = nil, height: CGFloat? = nil,
                alignment: Alignment = .center) -> some View {
        frame(width: width.map(LayoutMetrics.s),
              height: height.map(LayoutMetrics.s),
              alignment: alignment)
    }

    func sPadding(_ edges: Edge.Set = .all, _ length: CGFloat) -> some View {
        padding(edges, LayoutMetrics.s(length))
    }

    /// Installs width-based layout scale for the subtree (and updates global metrics).
    func fitsPhoneLayout() -> some View {
        modifier(PhoneLayoutScaleModifier())
    }
}

private struct PhoneLayoutScaleModifier: ViewModifier {
    @State private var width: CGFloat = LayoutMetrics.currentScreenWidthPublic

    func body(content: Content) -> some View {
        content
            .environment(\.layoutScale, LayoutMetrics.scale(forWidth: width))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: PhoneWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(PhoneWidthKey.self) { w in
                guard w > 0, abs(w - width) > 0.5 else { return }
                width = w
                LayoutMetrics.update(forWidth: w)
            }
            .onAppear {
                LayoutMetrics.update(forWidth: width)
            }
    }
}

private struct PhoneWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension LayoutMetrics {
    static var currentScreenWidthPublic: CGFloat { currentScreenWidth }
}

/// SoooDreamy design system — dreamy night-sky look.
enum Theme {
    // Palette
    static let bgTop = Color(hex: "17062A")
    static let bgBottom = Color(hex: "2B0F4A")
    static let card = Color.white.opacity(0.07)
    static let cardBorder = Color.white.opacity(0.12)
    static let pink = Color(hex: "FF5C8A")
    static let rose = Color(hex: "FF8FAB")
    static let purple = Color(hex: "A855F7")
    static let indigo = Color(hex: "6366F1")
    static let blue = Color(hex: "60A5FA")
    static let gold = Color(hex: "FFD166")
    static let mint = Color(hex: "6EE7B7")
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.4)

    // Scaled layout tokens (read LayoutMetrics.scale at use time)
    static var cardPadding: CGFloat { LayoutMetrics.s(16) }
    static var cardRadius: CGFloat { LayoutMetrics.s(24) }
    static var screenPadding: CGFloat { LayoutMetrics.s(16) }
    static var sectionSpacing: CGFloat { LayoutMetrics.s(18) }

    // Gradients
    static let heroGradient = LinearGradient(
        colors: [pink, purple, indigo],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let pinkGradient = LinearGradient(
        colors: [rose, pink],
        startPoint: .top, endPoint: .bottom)

    static let bgGradient = LinearGradient(
        colors: [bgTop, bgBottom],
        startPoint: .top, endPoint: .bottom)

    /// Avatar color choices during profile setup.
    static let memberColors: [String] = [
        "FF5C8A", "A855F7", "6366F1", "60A5FA", "6EE7B7", "FFD166", "FB923C", "F87171"
    ]

    /// Avatar emoji choices.
    static let avatarEmojis: [String] = [
        "🦊", "🐰", "🐻", "🐼", "🐨", "🦁", "🐯", "🐸", "🐙", "🦄", "🐝", "🦋",
        "🌸", "🌙", "⭐️", "🍓", "🍑", "🌈", "💫", "🔥", "🌊", "🍀", "🎀", "👑"
    ]
}

// MARK: - Backgrounds

/// Full-screen dreamy background with subtle drifting star field.
struct DreamyBackground: View {
    var showStars: Bool = true

    var body: some View {
        ZStack {
            Theme.bgGradient
            if showStars {
                StarFieldView()
                    .opacity(0.5)
            }
        }
        .ignoresSafeArea()
    }
}

struct StarFieldView: View {
    private struct Star {
        let x: CGFloat
        let y: CGFloat
        let r: CGFloat
        let phase: Double
        let speed: Double
    }

    private static let stars: [Star] = {
        var seed: UInt64 = 0xDEADBEEF
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
        return (0..<60).map { _ in
            Star(x: rnd(), y: rnd(), r: 0.6 + rnd() * 1.8,
                 phase: Double(rnd()) * 2 * .pi, speed: 0.4 + Double(rnd()) * 1.2)
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for star in Self.stars {
                    let twinkle = 0.35 + 0.65 * abs(sin(t * star.speed + star.phase))
                    let rect = CGRect(x: star.x * size.width, y: star.y * size.height,
                                      width: star.r * 2, height: star.r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 * twinkle)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Card & buttons

struct GlassCardModifier: ViewModifier {
    /// Design-space padding (already scaled by `glassCard`).
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        let radius = Theme.cardRadius
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    /// `padding` is a design-space value (Pro Max baseline); it is scaled for the device.
    func glassCard(padding: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(padding: LayoutMetrics.s(padding)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, LayoutMetrics.s(14))
            .padding(.horizontal, LayoutMetrics.s(22))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(Theme.heroGradient))
            .shadow(color: Theme.pink.opacity(0.45), radius: LayoutMetrics.s(12), y: LayoutMetrics.s(5))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, LayoutMetrics.s(20))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.09))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
