import SwiftUI

// MARK: - Post-Station switch

/// A COUNTER of the Post-Station, not a gesture: a compact horizontal
/// switch (SF-symbol chrome in lamplight + label) — clearly a service
/// row, never another touch tile. Lives with its one consumer, the
/// Postfach TelegrammLeiste (the old TouchGridCard died with the
/// emoji grid in the Fix-A wave).
struct StationTile: View {
    let systemImage: String
    let title: String
    let a11yLabel: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.lampengold)
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11yLabel)
    }
}
