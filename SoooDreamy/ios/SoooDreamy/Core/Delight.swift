import SwiftUI

// Delight-Engine — the central micro-celebration layer.
//
// One call, one consistent choreography (particles + haptic motif + sound
// sting) in three intensities:
//
//     Delight.celebrate(.small)                 // soft puff + tap + pop
//     Delight.celebrate(.medium)                // burst + success + sparkle
//     Delight.celebrate(.epic, theme: .hearts)  // full-screen rain + fanfare
//
// Every feature (rituals, games, level-ups, badges, quests, icon gifts …)
// speaks the same delight language through this API instead of scattering
// its own confetti. The overlay host lives in RootView so celebrations work
// from any screen. Reduce Motion swaps particles for a gentle glow flash.
// Milestone RULES (which counter values are moments) live in
// Core/DelightRules.swift — pure and Linux-testable.

@MainActor
enum Delight {
    /// Fires the celebration choreography for the given intensity.
    static func celebrate(_ intensity: DelightIntensity, theme: DelightTheme = .hearts) {
        playCue(intensity)
        DelightCenter.shared.fire(DelightMoment(intensity: intensity, theme: theme))
    }

    /// Convenience: celebrates a lifetime-counter value IF it is a milestone
    /// (see DelightRules). Returns true when a celebration fired.
    @discardableResult
    static func celebrateMilestone(count: Int, theme: DelightTheme = .hearts) -> Bool {
        guard let intensity = DelightRules.milestone(forCount: count) else { return false }
        celebrate(intensity, theme: theme)
        return true
    }

    /// Convenience: celebrates a streak value IF it is a milestone.
    @discardableResult
    static func celebrateStreak(days: Int, theme: DelightTheme = .stars) -> Bool {
        guard let intensity = DelightRules.milestone(forStreak: days) else { return false }
        celebrate(intensity, theme: theme)
        return true
    }

    /// One fanfare family in three stages — sound and haptic twin come as a
    /// pair from the cue vocabulary (CueKit), including the rate limiter.
    private static func playCue(_ intensity: DelightIntensity) {
        switch intensity {
        case .small: AppCue.fanfareSmall.play()
        case .medium: AppCue.fanfareMedium.play()
        case .epic: AppCue.fanfareEpic.play()
        }
    }
}

/// Visual flavor of a celebration (particle emoji + tint colors).
enum DelightTheme: String, CaseIterable {
    case hearts, stars, confetti

    var emojis: [String] {
        switch self {
        case .hearts: return ["💜", "💖", "💗", "💞", "✨"]
        case .stars: return ["⭐️", "✨", "🌟", "💫", "🌙"]
        case .confetti: return ["🎉", "🎊", "✨", "💜", "🩷"]
        }
    }

    var tint: Color {
        switch self {
        case .hearts: return Theme.pink
        case .stars: return Theme.gold
        case .confetti: return Theme.purple
        }
    }
}

/// One fired celebration (identity keeps repeated bursts distinct).
struct DelightMoment: Identifiable, Equatable {
    let id = UUID()
    let intensity: DelightIntensity
    let theme: DelightTheme
    let startedAt = Date()

    var duration: TimeInterval {
        switch intensity {
        case .small: return 1.3
        case .medium: return 2.2
        case .epic: return 4.2
        }
    }
}

/// Tiny observable hub between `Delight.celebrate` and the overlay host in
/// RootView. Epic moments replace smaller running ones; a smaller moment
/// never interrupts a bigger one that is still playing.
@MainActor
@Observable
final class DelightCenter {
    static let shared = DelightCenter()

    private(set) var moment: DelightMoment?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    private init() {}

    func fire(_ new: DelightMoment) {
        if let current = moment, current.intensity > new.intensity,
           Date().timeIntervalSince(current.startedAt) < current.duration {
            return
        }
        moment = new
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(new.duration * 1_000_000_000))
            if !Task.isCancelled { self?.moment = nil }
        }
    }
}

/// Overlay host — mounted once in RootView above all screens.
struct DelightOverlayHost: View {
    @State private var center = DelightCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let moment = center.moment {
                if reduceMotion {
                    DelightGlowFlash(moment: moment)
                } else {
                    DelightBurstView(moment: moment)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        // Named curve instead of a raw ease (commandment 11).
        .animation(reduceMotion ? nil : Theme.Motion.settle, value: center.moment)
    }
}

/// Reduce-Motion alternative: a soft full-screen glow that breathes once.
private struct DelightGlowFlash: View {
    let moment: DelightMoment

    var body: some View {
        let alpha = moment.intensity == .epic ? 0.24 : 0.14
        RadialGradient(colors: [moment.theme.tint.opacity(alpha), .clear],
                       center: .center, startRadius: 0, endRadius: 500)
            .accessibilityHidden(true)
    }
}

/// The particle choreography, drawn in a single Canvas pass.
/// small/medium: one burst from the lower center. epic: a rising burst plus
/// a full-screen emoji rain with sway — same visual grammar as the app's
/// FloatingHeartsView, but time-limited and intensity-scaled.
struct DelightBurstView: View {
    let moment: DelightMoment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct Particle {
        let angle: Double        // burst direction (radians)
        let speed: Double        // fraction of min(size)/s
        let spin: Double
        let size: CGFloat
        let delay: Double
        let emojiIndex: Int
        let rain: Bool           // true = falls from the top (epic only)
        let x: CGFloat           // rain column 0…1
        let sway: CGFloat
    }

    private var particleCount: Int {
        AccessibilityBudget.particleLimit(
            intensity: moment.intensity,
            reduceMotion: false,
            accessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var particles: [Particle] {
        var seed = UInt64(truncatingIfNeeded: moment.id.hashValue) | 1
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
        let emojiCount = moment.theme.emojis.count
        let rainShare = moment.intensity == .epic ? 0.55 : 0.0
        return (0..<particleCount).map { i in
            let isRain = Double(rnd()) < rainShare
            return Particle(
                angle: Double.pi * (0.15 + 0.7 * Double(rnd())),
                speed: 0.55 + Double(rnd()) * 0.75,
                spin: (Double(rnd()) - 0.5) * 5,
                size: LayoutMetrics.s(14 + rnd() * (moment.intensity == .small ? 12 : 22)),
                delay: Double(rnd()) * (isRain ? 1.6 : 0.25),
                emojiIndex: i % emojiCount,
                rain: isRain,
                x: 0.05 + rnd() * 0.9,
                sway: LayoutMetrics.s(12 + rnd() * 26))
        }
    }

    var body: some View {
        let items = particles
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(moment.startedAt)
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.72)
                let reach = min(size.width, size.height)
                for p in items {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let fade = 1 - min(1, life / (moment.duration - p.delay).clamped(min: 0.4))
                    guard fade > 0 else { continue }
                    var pos: CGPoint
                    if p.rain {
                        let y = size.height * CGFloat(life * p.speed * 0.5) - p.size
                        pos = CGPoint(x: p.x * size.width + sin(life * 3.2) * p.sway, y: y)
                        guard pos.y < size.height + p.size else { continue }
                    } else {
                        // Burst: radial fling + gravity pulling back down.
                        let dist = CGFloat(life * p.speed) * reach * 0.55
                        let gravity = CGFloat(life * life) * reach * 0.30
                        pos = CGPoint(x: origin.x + cos(p.angle) * dist,
                                      y: origin.y - sin(p.angle) * dist + gravity)
                    }
                    let resolved = context.resolve(
                        Text(moment.theme.emojis[p.emojiIndex]).font(.system(size: p.size)))
                    context.drawLayer { layer in
                        layer.opacity = fade
                        layer.translateBy(x: pos.x, y: pos.y)
                        layer.rotate(by: .radians(life * p.spin))
                        layer.draw(resolved, at: .zero)
                    }
                }
            }
        }
    }
}

private extension Double {
    func clamped(min lower: Double) -> Double { Swift.max(lower, self) }
}
