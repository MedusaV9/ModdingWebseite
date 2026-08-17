import SwiftUI

// DesignSystem wave 1 (REDESIGN.md §3): GlassPanel v2 — the ONE named
// building block for floating chrome clusters. Today every input bar,
// toolbar pill and floating doctor panel assembles its own
// `glass(.chrome, in:)` stack; the panel names that assembly once so
// wave-2 adopters (chat composer, connection doctor) stop re-deriving
// it. REAL system glass only (Zwei-Materialien-Gesetz): the material,
// its elevation and its accessibility degradations all come from
// `GlassLevel.chrome` — nothing is hand-painted on top.

struct GlassPanel<Content: View>: View {
    /// The three sanctioned chrome silhouettes — a name, never a number.
    enum PanelShape {
        /// Pills and bars (input rows, toolbar clusters).
        case capsule
        /// Small floating control panes (`Radius.control`).
        case control
        /// Large floating panes — sheets-within-screens (`Radius.pane`).
        case pane

        var shape: AnyShape {
            switch self {
            case .capsule:
                return AnyShape(Capsule())
            case .control:
                return AnyShape(RoundedRectangle(cornerRadius: Radius.control,
                                                 style: .continuous))
            case .pane:
                return AnyShape(RoundedRectangle(cornerRadius: Radius.pane,
                                                 style: .continuous))
            }
        }
    }

    var shape: PanelShape = .capsule
    /// Named content density (the card rhythm law applies to chrome too).
    var padding: CardPadding = .compact
    /// `true` for panels that ARE a control — the system glass answers
    /// the finger with its own springy press response.
    var interactive = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding.value)
            .glass(.chrome, in: shape.shape, interactive: interactive)
    }
}
