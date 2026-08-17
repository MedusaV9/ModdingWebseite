import SwiftUI

// „Unsere Reise" (W8, Linse 12 #6) — PATCHNOTES.md existed only in the repo.
// This timeline retells the app's releases inside the app: every version is
// a chapter with its narrative name and the What's-New highlights of the
// time. Newest first, because the freshest chapter is the one you came for.

/// One release chapter of the app's story.
struct ReleaseChapter: Identifiable {
    let version: String
    /// L10n key of the narrative chapter name (matches PATCHNOTES.md).
    let titleKey: String

    var id: String { version }

    /// The What's-New highlights of this release (may be empty for
    /// polish-only releases that never had a sheet).
    var highlights: [WhatsNewEntry] { WhatsNewCatalog.entries(for: version) }
}

enum ReleaseTimeline {
    /// Newest first — the order the timeline renders in.
    static let chapters: [ReleaseChapter] = [
        ReleaseChapter(version: "16.0.0", titleKey: "journey.16_0"),
        ReleaseChapter(version: "15.0.0", titleKey: "journey.15_0"),
        ReleaseChapter(version: "14.0.0", titleKey: "journey.14_0"),
        ReleaseChapter(version: "13.0.0", titleKey: "journey.13_0"),
        ReleaseChapter(version: "12.0.0", titleKey: "journey.12_0"),
        ReleaseChapter(version: "11.1.0", titleKey: "journey.11_1"),
        ReleaseChapter(version: "11.0.0", titleKey: "journey.11_0"),
        ReleaseChapter(version: "10.1.0", titleKey: "journey.10_1"),
        ReleaseChapter(version: "10.0.0", titleKey: "journey.10_0"),
        ReleaseChapter(version: "9.0.0", titleKey: "journey.9_0"),
        ReleaseChapter(version: "8.0.0", titleKey: "journey.8_0"),
        ReleaseChapter(version: "7.0.0", titleKey: "journey.7_0"),
        ReleaseChapter(version: "6.0.0", titleKey: "journey.6_0"),
        ReleaseChapter(version: "5.3.0", titleKey: "journey.5_3"),
        ReleaseChapter(version: "5.2.0", titleKey: "journey.5_2"),
        ReleaseChapter(version: "5.1.0", titleKey: "journey.5_1"),
        ReleaseChapter(version: "5.0.0", titleKey: "journey.5_0"),
        ReleaseChapter(version: "4.9.0", titleKey: "journey.4_9"),
        ReleaseChapter(version: "4.8.0", titleKey: "journey.4_8"),
        ReleaseChapter(version: "4.7.0", titleKey: "journey.4_7"),
        ReleaseChapter(version: "4.6.0", titleKey: "journey.4_6"),
        ReleaseChapter(version: "4.5.0", titleKey: "journey.4_5"),
        ReleaseChapter(version: "4.4.0", titleKey: "journey.4_4"),
        ReleaseChapter(version: "4.3.0", titleKey: "journey.4_3"),
        ReleaseChapter(version: "4.2.0", titleKey: "journey.4_2"),
    ]
}

struct VersionHistoryView: View {
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    // The app's story as BOOK PAGES (Papier & Licht): every release is one
    // sheet of letter paper — the chapter name reads in the serif brief
    // voice, the version line in the Anschrift small caps. The pink
    // timeline thread retired with the glass.
    var body: some View {
        ZStack {
            DreamyBackground(showBlobs: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(ReleaseTimeline.chapters) { chapter in
                        chapterPage(chapter)
                    }
                }
                .padding(LayoutMetrics.s(16))
                .contentColumn(.reading)
            }
        }
        .navigationTitle(L10n.t("journey.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chapterPage(_ chapter: ReleaseChapter) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            HStack(spacing: LayoutMetrics.s(8)) {
                Text(chapter.version)
                    .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .foregroundStyle(coupleTint.tinte)
                if chapter.version == currentVersion {
                    Text(L10n.t("journey.current"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.dunkel)
                        .padding(.horizontal, LayoutMetrics.s(8))
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(coupleTint.tinte.opacity(0.12))
                                .overlay(Capsule().strokeBorder(
                                    Papier.kante, lineWidth: Theme.hairlineWidth))
                        )
                }
                Spacer(minLength: 0)
            }
            Text(L10n.t(chapter.titleKey))
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(chapter.highlights) { entry in
                HStack(alignment: .top, spacing: LayoutMetrics.s(8)) {
                    Text(entry.icon)
                        .font(.system(.footnote, design: .rounded))
                        .accessibilityHidden(true)
                    Text(L10n.t(entry.titleKey))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .accessibilityElement(children: .combine)
    }
}
