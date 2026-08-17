import SwiftUI

// DesignSystem wave 1 (REDESIGN.md §3): the two interaction primitives
// every screen was missing —
//   * DSPressableStyle: a VISIBLE press answer for buttons that used to
//     reply only through haptics (`.plain` avatars, chrome circles).
//   * DSChip: ONE capsule-chip vocabulary (icon + label + tint) instead
//     of per-feature hand-built capsules.
// Both speak exclusively in named tokens (DS.*, Theme.*, Space) — the
// charter's motion and color laws hold by construction.

// MARK: - Press response

/// The visible answer of a pressable surface (commandment 14): the label
/// breathes down to `DS.Press.scale` on the settle spring and lifts under
/// the iPad pointer. For `.plain` buttons that today answer the finger
/// only with haptics — apply this instead, nothing else changes.
struct DSPressableStyle: ButtonStyle {
    /// Compact controls (44-pt circles, avatars) press slightly deeper —
    /// on a small target the standard scale is barely visible.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed
                         ? (compact ? DS.Press.compactScale : DS.Press.scale)
                         : 1)
            .animation(DS.Press.animation, value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}

// MARK: - Chips

/// ONE capsule chip for the whole app: SF-Symbol + label on a tinted
/// capsule, with the shared press response. Two prominences:
///   * `.filled` — an inviting/actionable chip: tint wash fill
///     (`Theme.Contrast.tintFill`, Increased-Contrast-aware), primary ink.
///   * `.quiet` — a done/passive chip: whisper-thin tint fill, the tint
///     itself as ink.
/// The chip never invents colors — callers pass a token or coupleTint role.
struct DSChip: View {
    enum Prominence {
        case filled
        case quiet
    }

    /// Optional SF Symbol before the label — never an emoji (commandment 1).
    var icon: String? = nil
    let title: String
    /// Color role of the chip (a Theme token or a `coupleTint` role).
    var tint: Color
    var prominence: Prominence = .filled
    let action: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var increased: Bool { colorSchemeContrast == .increased }

    private var ink: Color {
        prominence == .filled ? Theme.textPrimary : tint
    }

    private var fill: Color {
        switch prominence {
        case .filled:
            return Theme.Contrast.tintFill(tint, increased: increased)
        case .quiet:
            return tint.opacity(DS.Chip.quietFill(increased: increased))
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Chip.spacing) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            .foregroundStyle(ink)
            .padding(.vertical, DS.Chip.verticalPadding)
            .padding(.horizontal, DS.Chip.horizontalPadding)
            .background(Capsule().fill(fill))
            // Increased Contrast: a firm edge so the capsule reads as a
            // surface, not a ghost — same strengthening as the buttons.
            .overlay {
                if increased {
                    Capsule().strokeBorder(
                        Theme.Contrast.hairline(increased: true),
                        lineWidth: Theme.hairlineWidth)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(DSPressableStyle())
    }
}
