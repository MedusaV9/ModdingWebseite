import SwiftUI

/// „Klänge & Credits" — the audible acknowledgements page, generated from
/// Resources/Sounds/sound_credits.json (the same single source of truth the
/// license LogicTests enforce). Section one lists CC-BY works whose
/// attribution is MANDATORY (author, license, link); section two thanks the
/// CC0/public-domain authors voluntarily. Tapping a row plays its cue — the
/// obligation page doubles as a tiny soundboard.
struct SoundCreditsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let manifest = SoundCreditsView.loadManifest()

    var body: some View {
        ZStack {
            // Fix4 Befund 7: Amt sheets are still tool rooms.
            DreamyBackground(showBlobs: false)
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.s(18)) {
                    Text(L10n.t("settings.soundCredits.intro"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let manifest {
                        let mandatory = manifest.attributionRequired
                        if !mandatory.isEmpty {
                            creditSection(title: L10n.t("settings.soundCredits.thanks"),
                                          entries: mandatory)
                        }
                        let voluntary = manifest.voluntaryCredits
                        if !voluntary.isEmpty {
                            creditSection(title: L10n.t("settings.soundCredits.publicDomain"),
                                          entries: voluntary)
                        }
                    }

                    VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
                        Text(L10n.t("settings.soundCredits.synthFooter"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L10n.t("settings.madeWith"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.top, LayoutMetrics.s(6))
                }
                .padding(LayoutMetrics.s(20))
            }
        }
        .navigationTitle(L10n.t("settings.soundCredits.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func creditSection(title: String,
                               entries: [SoundCreditsManifest.Entry]) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(title)
                .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: LayoutMetrics.s(2)) {
                ForEach(entries, id: \.cue) { entry in
                    SoundCreditRow(entry: entry)
                }
            }
            .nightCard(padding: .compact)
        }
    }

    private static func loadManifest() -> SoundCreditsManifest? {
        guard let url = Bundle.main.url(forResource: "sound_credits", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? SoundCreditsManifest.load(from: data)
    }
}

/// One credited recording: title — author · license badge, a link to the
/// source, and the cue itself on tap (the panel is a soundboard).
private struct SoundCreditRow: View {
    let entry: SoundCreditsManifest.Entry
    @Environment(\.openURL) private var openURL
    @Environment(\.coupleTint) private var coupleTint

    private var sourceURL: URL? {
        guard let raw = entry.source?.url else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Button(action: playCue) {
                HStack(spacing: LayoutMetrics.s(10)) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(coupleTint.blend)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.source?.title ?? entry.cue)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Papier.aufNacht)
                            .multilineTextAlignment(.leading)
                        Text(byline)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("settings.soundCredits.playHint"))

            if let sourceURL {
                Button {
                    openURL(sourceURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("settings.soundCredits.openSource"))
            }
        }
        .padding(.vertical, LayoutMetrics.s(6))
        .accessibilityElement(children: .combine)
    }

    private var byline: String {
        guard let source = entry.source else { return entry.cue }
        return "\(source.author) · \(source.license)"
    }

    private func playCue() {
        guard let cue = AppCue(rawValue: entry.cue) else { return }
        Haptics.shared.tap()
        SoundEngine.shared.play(cue: cue)
    }
}
