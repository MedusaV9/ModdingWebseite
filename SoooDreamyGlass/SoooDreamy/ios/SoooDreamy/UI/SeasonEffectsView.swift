import SwiftUI
import Combine

// Seasonal particles + frost edges: a dashboard overlay of
// gently falling petals/fireflies/leaves/snow, plus a glass-card edge tint.
// One Canvas pass, deterministic per-particle parameters (no allocations
// per frame), automatically still when Reduce Motion or Low Power Mode
// is on.

/// App-wide accessor for the stored preference.
enum SeasonSettings {
    static let prefKey = "sooodreamy.seasonTheme"
    static let particlesKey = "sooodreamy.seasonParticles"
    static let hemisphereKey = "sooodreamy.seasonHemisphere"

    static var preference: SeasonPreference {
        SeasonPreference(rawValue: UserDefaults.standard.string(forKey: prefKey) ?? "auto") ?? .auto
    }

    static var particlesEnabled: Bool {
        UserDefaults.standard.object(forKey: particlesKey) as? Bool ?? true
    }

    static var hemisphere: Hemisphere {
        Hemisphere(
            rawValue: UserDefaults.standard.string(forKey: hemisphereKey) ?? "northern"
        ) ?? .northern
    }

    /// The season to render right now (nil = layer off).
    static var activeSeason: Season? {
        preference.resolved(for: Date(), hemisphere: hemisphere)
    }
}

/// Full-screen drifting particle layer for the dashboard.
struct SeasonParticlesView: View {
    let season: Season
    private let particles: [Particle]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Mirrors `ProcessInfo.processInfo.isLowPowerModeEnabled`; refreshed
    /// via notification because power state is not observable directly
    /// (same pattern as `DreamyBackground`).
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    init(season: Season) {
        self.season = season
        self.particles = Self.makeParticles(for: season)
    }

    /// Deterministic particle parameters — seeded once per view identity.
    private struct Particle {
        let motif: String
        let x: CGFloat          // 0…1 base column
        let size: CGFloat
        let fallSpeed: Double   // fraction of height per second
        let swayAmp: CGFloat    // fraction of width
        let swaySpeed: Double
        let phase: Double
        let opacity: Double
    }

    private static func makeParticles(for season: Season) -> [Particle] {
        let seasonSalt = UInt64(Season.allCases.firstIndex(of: season) ?? 0)
        var seed: UInt64 = 0x5EA5_0000 &+ seasonSalt &* 7919
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        let motifs = season.particles
        // Summer fireflies float instead of falling.
        let floating = season == .summer
        return (0..<16).map { index in
            Particle(motif: motifs[index % motifs.count],
                     x: CGFloat(rnd()),
                     size: 12 + CGFloat(rnd()) * 12,
                     fallSpeed: floating ? 0.010 + rnd() * 0.02 : 0.035 + rnd() * 0.05,
                     swayAmp: CGFloat(0.02 + rnd() * (floating ? 0.10 : 0.05)),
                     swaySpeed: 0.25 + rnd() * 0.7,
                     phase: rnd() * 2 * .pi,
                     opacity: 0.35 + rnd() * 0.45)
        }
    }

    var body: some View {
        Group {
            if reduceMotion || lowPowerMode {
                // Motion off (or battery saver): a whisper of the season at
                // the top edge only.
                LinearGradient(colors: [Color(hex: season.accentHex).opacity(0.10), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 120)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                    canvas(t: timeline.date.timeIntervalSinceReferenceDate)
                }
                .allowsHitTesting(false)
                .ignoresSafeArea()
            }
        }
        .onReceive(NotificationCenter.default
            .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        Canvas { context, size in
            for particle in particles {
                // Wrap vertically: each particle loops its own fall cycle.
                let cycle = 1.0 / particle.fallSpeed
                let progress = (t / cycle + particle.phase / (2 * .pi))
                    .truncatingRemainder(dividingBy: 1)
                let y = CGFloat(progress) * (size.height + 60) - 30
                let sway = particle.swayAmp * CGFloat(sin(t * particle.swaySpeed + particle.phase))
                let x = (particle.x + sway) * size.width
                let resolved = context.resolve(
                    Text(particle.motif).font(.system(size: particle.size)))
                context.opacity = particle.opacity
                context.draw(resolved, at: CGPoint(x: x, y: y))
            }
        }
    }
}

/// Frost edge / blossom shimmer on glass cards: a season-tinted top border
/// glow. Applied by `.seasonEdge()` — a no-op when the layer is off.
struct SeasonEdgeModifier: ViewModifier {
    let season: Season?

    func body(content: Content) -> some View {
        if let season {
            content.overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: season.accentHex).opacity(0.55),
                                                Color(hex: season.accentHex).opacity(0.06),
                                                .clear],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5)
                    .allowsHitTesting(false))
        } else {
            content
        }
    }
}

extension View {
    /// Seasonal glass-card edge (frost/blossom/…): follows the user's
    /// season preference; invisible when the layer is off.
    func seasonEdge() -> some View {
        modifier(SeasonEdgeModifier(season: SeasonSettings.activeSeason))
    }
}

// MARK: - Settings card

/// Picker card for the More tab: auto / off / one fixed season, plus the
/// particle toggle.
struct SeasonThemeCard: View {
    @AppStorage(SeasonSettings.prefKey) private var preferenceRaw = "auto"
    @AppStorage(SeasonSettings.particlesKey) private var particlesOn = true
    @AppStorage(SeasonSettings.hemisphereKey) private var hemisphereRaw = "northern"
    @Environment(\.coupleTint) private var coupleTint

    private var preference: SeasonPreference {
        SeasonPreference(rawValue: preferenceRaw) ?? .auto
    }

    private var hemisphere: Hemisphere {
        Hemisphere(rawValue: hemisphereRaw) ?? .northern
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("season.settings.title"))

            VStack(spacing: 6) {
                ForEach(SeasonPreference.allCases, id: \.rawValue) { option in
                    optionRow(option)
                }
            }

            Picker(L10n.t("season.hemisphere"), selection: $hemisphereRaw) {
                ForEach(Hemisphere.allCases, id: \.rawValue) { option in
                    Text(L10n.t(option.titleKey)).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: $particlesOn) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("season.particles"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("season.particles.hint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            .tint(coupleTint.blend)
        }
        // Re-Eval Runde 2: the office speaks night, grain-free (§4.5) —
        // this card was the Amt's last glass + emoji-chrome leftover.
        .nightCard(grain: false)
    }

    private func optionRow(_ option: SeasonPreference) -> some View {
        Button {
            Haptics.shared.tap()
            preferenceRaw = option.rawValue
        } label: {
            HStack(spacing: LayoutMetrics.s(10)) {
                // SF Symbols as row chrome (commandment 1) — the seasons'
                // own particle emojis stay CONTENT of the effect layer,
                // never picker decoration.
                Image(systemName: optionSymbol(option))
                    .font(.system(.body, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(24))
                    .accessibilityHidden(true)
                Text(L10n.t(option.titleKey))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                if option == .auto,
                   let season = SeasonPreference.auto.resolved(
                    for: Date(),
                    hemisphere: hemisphere
                   ) {
                    Text("(\(L10n.t(season.titleKey)))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer(minLength: 0)
                Image(systemName: preference == option ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(preference == option ? coupleTint.blend : Nacht.tertiaer)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    /// Row glyphs mirror the seasons' voices (summer is the app's moon
    /// summer night, like its particle motif) — symbols, never emoji.
    private func optionSymbol(_ option: SeasonPreference) -> String {
        switch option {
        case .auto: return "calendar"
        case .off: return "circle.slash"
        case .spring: return "camera.macro"
        case .summer: return "moon.stars.fill"
        case .autumn: return "leaf.fill"
        case .winter: return "snowflake"
        }
    }
}
