import SwiftUI

/// One-time opt-in for the on-device writing helpers. Appears on FIRST
/// CONTACT with an AI feature (never at app start): three sentences that
/// say what runs where, one clear yes, one pressure-free "not now".
/// The durable switch lives in Settings → security/privacy card.
struct IntelligenceConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    /// Called after the choice is persisted — `true` lets the tapped
    /// feature continue right away instead of asking for a second tap.
    var onDecision: (Bool) -> Void = { _ in }

    var body: some View {
        ZStack {
            DreamyBackground(showBlobs: false)
            ScrollView {
                VStack(spacing: Space.l) {
                    Image(systemName: "sparkles")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(coupleTint.blend)
                        .padding(.top, Space.xl)
                        .accessibilityHidden(true)

                    Text(L10n.t("ai.consent.title"))
                        .font(Typo.title)
                        .foregroundStyle(Theme.textPrimary)

                    OnDeviceBadge()

                    VStack(alignment: .leading, spacing: Space.m) {
                        promiseLine("text.bubble", key: "ai.consent.line1")
                        promiseLine("lock.shield", key: "ai.consent.line2")
                        promiseLine("square.and.pencil", key: "ai.consent.line3")
                    }
                    .nightCard()

                    Button {
                        decide(granted: true)
                    } label: {
                        Text(L10n.t("ai.consent.accept"))
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(L10n.t("ai.consent.later")) {
                        decide(granted: false)
                    }
                    .buttonStyle(.plain)
                    .font(Typo.label)
                    .foregroundStyle(Theme.textSecondary)
                    .minimumHitTarget()
                }
                .padding(Space.l)
                .contentColumn(.reading)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(false)
    }

    private func promiseLine(_ symbol: String, key: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(24))
                .accessibilityHidden(true)
            Text(L10n.t(key))
                .font(Typo.body)
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func decide(granted: Bool) {
        Haptics.shared.tap()
        Intelligence.shared.apply(granted ? .grant : .decline)
        onDecision(granted)
        dismiss()
    }
}

/// The honesty pill every AI surface wears: this stays on the device.
/// Matte fill — the badge is a statement, not a floating control.
/// P6-C: `onPaper` renders the paper variant (Tinte.sekundaer ink on the
/// innenFill wash with the kante hairline) for badges that lie ON a
/// paper card — the night accent reads 2.1:1 on brief. Default stays
/// the night variant, so every existing call site is untouched.
struct OnDeviceBadge: View {
    var onPaper = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "iphone")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .accessibilityHidden(true)
            Text(L10n.t("ai.onDevice.badge"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(onPaper ? Tinte.sekundaer : Theme.mint)
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .background(
            Capsule()
                .fill(onPaper ? Papier.innenFill : Theme.innerFill)
                .overlay(Capsule().strokeBorder(
                    onPaper ? Papier.kante : Theme.mint.opacity(0.35),
                    lineWidth: Theme.hairlineWidth))
        )
        .accessibilityElement(children: .combine)
    }
}
