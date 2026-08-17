import SwiftUI

/// One-shot micro burst of tiny hearts — anchored feedback right at
/// the control that triggered it (e.g. the chat send button), deliberately
/// smaller than the full-screen Delight engine. Bump `trigger` to fire.
/// Respects Reduce Motion (renders nothing) and never intercepts touches.
struct HeartBurstView: View {
    let trigger: Int
    var emojis: [String] = ["💜", "💖", "🩷"]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var firedAt: Date?

    private static let lifetime: TimeInterval = 0.9

    private struct Particle {
        let angle: Double      // radians, fanning upward
        let distance: CGFloat  // travel distance factor
        let size: CGFloat
        let spin: Double
        let emojiIndex: Int
    }

    /// Deterministic per-trigger fan of 7 hearts (seeded, no Foundation RNG).
    private func particles(salt: Int) -> [Particle] {
        var seed: UInt64 = 0x5EED &+ UInt64(truncatingIfNeeded: salt)
        func rnd() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
        }
        return (0..<7).map { i in
            // Fan between ~35° and ~145° (up and outward).
            let angle = Double.pi * (0.20 + 0.60 * rnd())
            return Particle(angle: angle,
                            distance: 0.55 + rnd() * 0.45,
                            size: 9 + rnd() * 8,
                            spin: (rnd() - 0.5) * 2.4,
                            emojiIndex: i % emojis.count)
        }
    }

    var body: some View {
        ZStack {
            if let firedAt, !reduceMotion {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(firedAt)
                    Canvas { context, size in
                        guard t >= 0, t < Self.lifetime else { return }
                        let progress = t / Self.lifetime
                        // Ease-out flight, quick fade at the end.
                        let eased = 1 - pow(1 - progress, 2.2)
                        let alpha = progress < 0.75 ? 1.0 : (1 - progress) / 0.25
                        let reach = min(size.width, size.height) * 0.5
                        for p in particles(salt: trigger) {
                            let r = reach * p.distance * CGFloat(eased)
                            let x = size.width / 2 + cos(p.angle) * r
                            let y = size.height / 2 - sin(p.angle) * r
                            var ctx = context
                            ctx.opacity = alpha
                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: .radians(p.spin * eased))
                            let text = Text(emojis[p.emojiIndex])
                                .font(.system(size: p.size * CGFloat(0.7 + 0.3 * eased)))
                            ctx.draw(ctx.resolve(text), at: .zero)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            firedAt = Date()
            // Let the timeline stop again after the burst has faded.
            Task {
                try? await Task.sleep(nanoseconds: UInt64(Self.lifetime * 1_200_000_000))
                if let firedAt, Date().timeIntervalSince(firedAt) >= Self.lifetime {
                    self.firedAt = nil
                }
            }
        }
    }
}
