import SwiftUI

struct HandbookView: View {
    @Environment(\.dismiss) private var dismiss
    let initialAnchor: String

    @State private var sections: [HandbookSection] = []
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Fix4 Befund 7: Amt sheets are still tool rooms.
                DreamyBackground(showBlobs: false)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: LayoutMetrics.s(20)) {
                            if loadFailed {
                                EmptyStateView(
                                    systemImage: "book.closed",
                                    title: L10n.t("handbook.missing.title"),
                                    subtitle: L10n.t("handbook.missing.body")
                                )
                            }
                            ForEach(sections) { section in
                                handbookSection(section)
                                    .id(section.id)
                            }
                        }
                        .padding(LayoutMetrics.s(16))
                    }
                    .task(id: L10n.lang) {
                        load()
                        await Task.yield()
                        withAnimation(Theme.Motion.settle) {
                            proxy.scrollTo(initialAnchor, anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle(L10n.t("handbook.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func handbookSection(_ section: HandbookSection) -> some View {
        if let attributed = try? AttributedString(markdown: section.markdown) {
            // Book pages (paper wave): the manual reads like a manual —
            // serif letter type in ink on paper sheets.
            Text(attributed)
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperCard()
                .accessibilityElement(children: .contain)
        }
    }

    private func load() {
        let resource = "Handbook.\(L10n.lang)"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8) else {
            sections = []
            loadFailed = true
            return
        }
        let parsed = HandbookDocument.parse(markdown)
        sections = parsed
        loadFailed = Set(parsed.map(\.id)) != Set(HandbookDocument.requiredAnchors)
    }
}

/// FullRelease N1-A: help left the dock — the floating "?" glass circle
/// died with `LiquidTabBar`, so every main screen carries this button in
/// its own header (or native toolbar). One symbol, one sheet, and the
/// screen's own handbook anchor instead of the old activeTab mapping.
struct HandbookButton: View {
    /// Section anchor of the hosting screen (`HandbookDocument.requiredAnchors`).
    let anchor: String
    var style: Style = .header

    /// `.header` renders the interactive glass circle of the custom
    /// headers (same chrome as Chat's search toggle); `.toolbar` stays a
    /// bare symbol — the native bar brings its own glass platter and
    /// glass-on-glass is forbidden.
    enum Style { case header, toolbar }

    @State private var showHandbook = false

    var body: some View {
        switch style {
        case .header: headerButton
        case .toolbar: toolbarButton
        }
    }

    private var headerButton: some View {
        Button {
            Haptics.shared.tap()
            showHandbook = true
        } label: {
            symbol
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: LayoutMetrics.s(32), height: LayoutMetrics.s(32))
                .glass(.chrome, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .accessibilityLabel(L10n.t("handbook.open"))
        .sheet(isPresented: $showHandbook) {
            HandbookView(initialAnchor: anchor)
        }
    }

    private var toolbarButton: some View {
        Button {
            Haptics.shared.tap()
            showHandbook = true
        } label: {
            symbol
        }
        .accessibilityLabel(L10n.t("handbook.open"))
        .sheet(isPresented: $showHandbook) {
            HandbookView(initialAnchor: anchor)
        }
    }

    private var symbol: some View {
        Image(systemName: "questionmark.circle")
    }
}
