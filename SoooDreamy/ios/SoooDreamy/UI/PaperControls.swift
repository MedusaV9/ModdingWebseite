import SwiftUI

// FullRelease P6-C — the paper CONTROL vocabulary, promoted from
// Stationen/Schreibstube/ChatPaper.swift: the writing field and the quiet action
// button were born as chat machinery but are used clear across the app
// (Memories, Settings, Icon gifts, Personalization all import them) —
// cross-feature tokens belong to the UI layer, not to one feature's
// folder. `ChatPaperFieldStyle`/`ChatPaperActionButtonStyle` stay valid
// as typealiases in ChatPaper.swift, so no call site had to move.
// Every value is a design-system token (Papier/Tinte, PaperRules-backed)
// — no raw hexes here.

// MARK: - Paper writing field

/// Writing happens on paper (Korrespondenz-Blueprint): THE field style
/// for paper contexts, replacing the night-era `DreamyFieldStyle` whose
/// compat fill turned unreadable on the paper wave.
/// `inset: false` = a free-standing paper slip on the night canvas
/// (letter title, message edit); `inset: true` = an inner well INSIDE a
/// paper card — `Papier.innenFill` wash with the `Papier.kante` hairline,
/// never a second material (Zwei-Materialien-Gesetz).
struct PaperFieldStyle: TextFieldStyle {
    var font: Font = Typo.body
    var inset = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        return configuration
            .font(font)
            .foregroundStyle(Tinte.dunkel)
            .tint(Tinte.dunkel)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, LayoutMetrics.s(16))
            .background {
                if inset {
                    shape.fill(Papier.innenFill)
                        .overlay(shape.strokeBorder(Papier.kante,
                                                    lineWidth: Theme.hairlineWidth))
                } else {
                    shape.fill(Papier.brief)
                        .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                                    lineWidth: Theme.hairlineWidth))
                        .elevation(.resting)
                }
            }
    }
}

// MARK: - Paper action button

/// Quiet action button ON paper (generate/retry/use, list management):
/// an inner ink-wash capsule with the kante hairline and the couple's
/// shared ink as label — `SecondaryButtonStyle` is real glass with night
/// text and may not float on paper (Zwei-Materialien-Gesetz).
struct PaperActionButtonStyle: ButtonStyle {
    var fullWidth = false

    @Environment(\.coupleTint) private var coupleTint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(coupleTint.tinte)
            .padding(.vertical, LayoutMetrics.s(10))
            .padding(.horizontal, LayoutMetrics.s(16))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(
                Capsule().fill(Papier.innenFill)
                    .overlay(Capsule().strokeBorder(Papier.kante,
                                                    lineWidth: Theme.hairlineWidth))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.settle, value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}
