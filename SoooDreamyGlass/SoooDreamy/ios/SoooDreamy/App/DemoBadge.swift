import SwiftUI

/// Welle 7 [29]: the permanent, unmissable marker of demo mode. Floats as
/// a top bar above the whole main UI (every tab, every scroll position) so
/// staged content can never be mistaken for a real relationship. The badge
/// IS the exit: one tap offers „Eigenen Server verbinden" — leaving
/// evaporates everything staged, only the demo flag itself was ever
/// persisted (see `AppState.exitDemo`).
struct DemoBadge: View {
    @Environment(AppState.self) private var appState
    @State private var confirmExit = false

    var body: some View {
        Button {
            Haptics.shared.tap()
            confirmExit = true
        } label: {
            HStack(spacing: LayoutMetrics.s(8)) {
                Image(systemName: "binoculars.fill")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                Text(verbatim: "Demo")
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .textCase(.uppercase)
                    .kerning(1.2)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: Theme.hairlineWidth, height: LayoutMetrics.s(12))
                Text(L10n.t("demo.badge.exit"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.gold)
            .padding(.vertical, LayoutMetrics.s(8))
            .padding(.horizontal, LayoutMetrics.s(14))
        }
        .buttonStyle(.plain)
        .glass(.chrome, in: Capsule(), interactive: true)
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.45),
                                        lineWidth: Theme.hairlineWidth))
        .confirmationDialog(L10n.t("demo.exit.title"),
                            isPresented: $confirmExit,
                            titleVisibility: .visible) {
            Button(L10n.t("demo.exit.connect")) {
                Haptics.shared.tap()
                appState.exitDemo(toServerSetup: true)
            }
            Button(L10n.t("demo.exit.keepLooking"), role: .cancel) {}
        } message: {
            Text(L10n.t("demo.exit.body"))
        }
        .accessibilityLabel(L10n.t("demo.badge.a11y"))
        .accessibilityHint(L10n.t("demo.badge.a11yHint"))
        .accessibilityIdentifier("demo.badge")
    }
}
