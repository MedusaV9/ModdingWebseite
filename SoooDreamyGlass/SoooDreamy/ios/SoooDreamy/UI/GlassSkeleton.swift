import SwiftUI

/// Waiting should look like "almost here", not like "maybe never"
/// (DESIGN.md, commandment 7): instead of an anonymous spinner, a matte
/// placeholder in the shape of the coming content with a slow light sweep.
/// Spinners remain legitimate only inside buttons for sub-second actions.
///
/// Usage: compose a few of these in the layout the real content will have —
/// e.g. one `.line` per text row, `.tile` for an image cell.
struct GlassSkeleton: View {
    enum Kind {
        /// A text row — capsule, default height 14.
        case line(width: CGFloat? = nil)
        /// An image/photo cell — rounded rect using `Radius.control`.
        case tile(height: CGFloat = 88)
        /// A whole card placeholder using `Radius.card`.
        case card(height: CGFloat = 120)
    }

    var kind: Kind = .card()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        base
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.10), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: sweep ? geo.size.width : -geo.size.width * 0.6)
                    }
                    .clipShape(sweepClip)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Theme.Motion.drift(1.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var base: some View {
        switch kind {
        case .line(let width):
            Capsule()
                .fill(Theme.innerFill)
                .frame(width: width, height: LayoutMetrics.s(14))
        case .tile(let height):
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.innerFill)
                .frame(height: LayoutMetrics.s(height))
        case .card(let height):
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.innerFill)
                .frame(height: LayoutMetrics.s(height))
        }
    }

    private var sweepClip: AnyShape {
        switch kind {
        case .line: return AnyShape(Capsule())
        case .tile: return AnyShape(RoundedRectangle(cornerRadius: Radius.control,
                                                     style: .continuous))
        case .card: return AnyShape(RoundedRectangle(cornerRadius: Radius.card,
                                                     style: .continuous))
        }
    }
}
