import SwiftUI
import AppIntents

// MARK: - Automations gallery (W7-Rest)
// The five Shortcuts recipes from docs/SHORTCUTS.md as an in-app gallery:
// a sideloaded build gets no pushes, so these automations are how the app
// "speaks up on its own". Each recipe card carries its trigger steps and a
// `SiriTipView` for the intent it drives — the tip doubles as the fastest
// way to add the shortcut, and the phrase works by voice right away.

struct AutomationsGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        introCard
                        recipeCard(icon: "alarm.fill",
                                   titleKey: "automations.r1.title",
                                   stepsKey: "automations.r1.steps",
                                   hintKey: "automations.r1.hint") {
                            SiriTipView(intent: GoodMorningIntent())
                        }
                        recipeCard(icon: "house.fill",
                                   titleKey: "automations.r2.title",
                                   stepsKey: "automations.r2.steps",
                                   hintKey: "automations.r2.hint") {
                            SiriTipView(intent: SendPulseIntent())
                        }
                        recipeCard(icon: "sensor.tag.radiowaves.forward.fill",
                                   titleKey: "automations.r3.title",
                                   stepsKey: "automations.r3.steps",
                                   hintKey: "automations.r3.hint") {
                            SiriTipView(intent: GoodNightIntent())
                        }
                        recipeCard(icon: "powerplug.fill",
                                   titleKey: "automations.r4.title",
                                   stepsKey: "automations.r4.steps",
                                   hintKey: "automations.r4.hint") {
                            SiriTipView(intent: GoodNightIntent())
                        }
                        recipeCard(icon: "moon.circle.fill",
                                   titleKey: "automations.r5.title",
                                   stepsKey: "automations.r5.steps",
                                   hintKey: "automations.r5.hint") {
                            // Recipe 5 is the zero-config focus FILTER — no
                            // shortcut involved; the tip shows the presence
                            // building block for hand-rolled variants.
                            SiriTipView(intent: SetPresenceIntent())
                        }
                        openShortcutsButton
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t("automations.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            Text(L10n.t("automations.intro"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t("automations.siriHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private func recipeCard(icon: String,
                            titleKey: String, stepsKey: String, hintKey: String,
                            @ViewBuilder tip: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                Image(systemName: icon)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.blend)
                    .frame(width: LayoutMetrics.s(34))
                Text(L10n.t(titleKey))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer(minLength: 0)
            }
            Text(L10n.t(stepsKey))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.t(hintKey))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .fixedSize(horizontal: false, vertical: true)
            tip()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
        .accessibilityElement(children: .combine)
    }

    private var openShortcutsButton: some View {
        Button {
            Haptics.shared.tap()
            if let url = URL(string: "shortcuts://") {
                openURL(url)
            }
        } label: {
            Label(L10n.t("automations.openShortcuts"), systemImage: "arrow.up.forward.app.fill")
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
