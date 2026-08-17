import SwiftUI

// W7: deterministic celebration confetti for widgets + live activities.
// Layout comes from `ConfettiLayout` (Shared, Linux-tested): the same event
// lays the same confetti on every device and every render — no randomness
// at render time, so a static WidgetKit snapshot still looks intentional.

struct WConfetti: View {
    /// Stable identity of the celebrated moment (event id or title).
    let eventKey: String
    /// Timeline slot — each celebration-day entry re-seeds the layout so the
    /// static widget feels alive across the day.
    var slot: Int = 0
    var count: Int = 22
    let palette: WidgetPalette

    var body: some View {
        GeometryReader { geo in
            let seed = ConfettiLayout.seed(eventKey: eventKey, slot: slot)
            ForEach(Array(ConfettiLayout.pieces(seed: seed, count: count).enumerated()),
                    id: \.offset) { _, piece in
                RoundedRectangle(cornerRadius: 1.2)
                    .fill(color(piece.paletteIndex))
                    .frame(width: 6 * piece.scale, height: 3.5 * piece.scale)
                    .rotationEffect(.radians(piece.angle))
                    .position(x: piece.x * geo.size.width,
                              y: piece.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func color(_ index: Int) -> Color {
        switch index {
        case 0: return palette.accent.opacity(0.85)
        case 1: return palette.accentSecondary.opacity(0.85)
        case 2: return WidgetPalette.gold.opacity(0.8)
        default: return WidgetPalette.mint.opacity(0.75)
        }
    }
}
