import SwiftUI
import UIKit

// „Sendung Nr. 1" — the pairing stage as the ENTSCHEID tells it (re-eval
// №4): no generic code card and no nest talk, but the couple's FIRST
// delivery — an addressed, SEALED letter sheet waiting to be sent. The
// recipient line stays open („Für …") until the partner exists, the code
// is the address line, a deep wax point closes the sheet, and ONE
// Siegellack action sends the invitation. Copying and the QR unfold stay
// as quiet secondary lines; the waiting pulse glows wax/gold — never the
// pink-purple heart of the template era.

struct WaitingForPartnerCard: View {
    @Environment(AppState.self) private var appState
    /// Fix2-A №7: the endless waiting pulse runs through the central
    /// motion gate — under Reduce Motion the seal simply glows.
    @Environment(\.motionGate) private var motionGate
    @State private var showQR = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            if let code = appState.couple?.code {
                sendung(code: code)

                // The ONE Siegellack action of the stage: send the
                // invitation — sealing the first delivery IS the call.
                ShareLink(item: shareText(code: code)) {
                    Label(L10n.t("postfach.sendung1.aktion"),
                          systemImage: "paperplane.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityHint(L10n.t("pairing.shareHintA11y"))

                stilleZeilen(code: code)

                if showQR, let server = appState.servers.activeProfile?.urlString,
                   let qr = QRGenerator.image(for: PairQRPayload.encode(server: server, code: code)) {
                    VStack(spacing: 6) {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: LayoutMetrics.s(180), height: LayoutMetrics.s(180))
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: Radius.control).fill(.white))
                            .accessibilityLabel(L10n.t("pairing.qrImageA11y"))
                        Text(L10n.t("pairing.qrHint"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                            .multilineTextAlignment(.center)
                    }
                }
            }

            // A softly glowing seal instead of an anonymous spinner —
            // waiting for the partner is anticipation, not a network delay
            // (DESIGN.md, commandment 7). Wax/gold, never a pink heart.
            // The repeat is ornamental and therefore gated (Fix2-A №7):
            // under Reduce Motion the seal holds its lit resting state.
            HStack(spacing: Space.s) {
                Image(systemName: "seal.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Licht.lampengold)
                    .symbolEffect(.pulse, options: .repeating,
                                  isActive: motionGate.particlesEnabled)
                Text(L10n.t("pairing.waiting"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .padding(.top, 2)
        }
        // iPad (Fix2-A №9): the letter sheet, actions and QR hold a
        // readable column while the night-card SURFACE keeps the full
        // width — margin inside, not zoom (FirstMomentCard pattern), so
        // the coming ipad-main shot composes instead of stretching.
        .contentColumn(.reading)
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    /// The sealed first delivery: a letter-paper artifact ON the night
    /// card (paper is the special thing in a dark room — the stage
    /// chrome stays night). Printed head, open recipient line, the code
    /// as the address line, and the deep wax point that keeps the sheet
    /// closed until the partner breaks it by joining.
    private func sendung(code: String) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            StempelzeileView(text: L10n.t("postfach.sendung1.stempel"))
            // The recipient line stays open — the name is what's missing.
            // VoiceOver hears the honest state instead of an ellipsis.
            Text(L10n.t("postfach.sendung1.empfaenger"))
                .font(Typo.voice)
                .foregroundStyle(Tinte.dunkel)
                .accessibilityLabel(L10n.t("pairing.waiting"))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(L10n.t("pairing.yourCode"))
                    .font(Typo.caption)
                    .foregroundStyle(Tinte.tertiaer)
                Text(code.map(String.init).joined(separator: " "))
                    .font(.system(.title2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(Tinte.dunkel)
                    // VoiceOver spells the code character by character (P2-9).
                    .accessibilityLabel(L10n.t("pairing.yourCodeA11y",
                                               ["code": code.map(String.init).joined(separator: ", ")]))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Room under the address so the wax point closes the sheet's
            // lower lip without covering a single glyph.
            .padding(.bottom, Space.l)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.brief)
        )
        .overlay(alignment: .bottomTrailing) {
            WachsSiegel(size: LayoutMetrics.s(40))
                .padding(.trailing, Space.l)
                .padding(.bottom, Space.m)
        }
        .accessibilityElement(children: .combine)
    }

    /// Copying and the QR unfold — quiet secondary lines under the one
    /// Siegellack action (every path to the code stays reachable).
    private func stilleZeilen(code: String) -> some View {
        HStack(spacing: LayoutMetrics.s(18)) {
            Button {
                UIPasteboard.general.string = code
                copied = true
                Haptics.shared.success()
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    copied = false
                }
            } label: {
                Label(L10n.t(copied ? "common.copied" : "common.copy"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Licht.lampengold)

            Button {
                withAnimation(Theme.Motion.settle) { showQR.toggle() }
            } label: {
                Label(L10n.t("pairing.showQR"), systemImage: "qrcode")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Licht.lampengold)
            .accessibilityHint(L10n.t("pairing.qrShowHintA11y"))
        }
    }

    private func shareText(code: String) -> String {
        let server = appState.servers.activeProfile?.urlString ?? ""
        return L10n.t("postfach.sendung1.einladung", ["server": server, "code": code])
    }
}
