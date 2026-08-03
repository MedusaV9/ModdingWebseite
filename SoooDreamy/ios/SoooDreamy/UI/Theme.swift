import SwiftUI

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
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.cardBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(Capsule().fill(Theme.heroGradient))
            .shadow(color: Theme.pink.opacity(0.45), radius: 14, y: 6)
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
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
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
