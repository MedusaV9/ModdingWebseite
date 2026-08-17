import SwiftUI
import WidgetKit

// MARK: - Widget Studio
// Live-preview + configure every SoooDreamy widget: theme, layout, data
// sources and animation. Everything lands in the app-group studio config —
// the widgets read it on their next render, which we trigger immediately
// via WidgetCenter reloads.

struct WidgetStudioView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var config = SharedStore.readStudioConfig()
    private let snapshot = SharedStore.readSnapshot()

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        diagnosticsCard
                        globalThemeCard
                        widgetCard(kind: WidgetKindID.daysTogether,
                                   title: L10n.t("studio.widget.days"), icon: "heart.fill",
                                   preview: { palette in DaysPreview(palette: palette, snapshot: snapshot, layout: layoutBinding(WidgetKindID.daysTogether).wrappedValue) },
                                   showsLayout: true, showsAnimated: true)
                        widgetCard(kind: WidgetKindID.countdown,
                                   title: L10n.t("studio.widget.countdown"), icon: "calendar.badge.clock",
                                   preview: { palette in CountdownPreview(palette: palette, snapshot: snapshot, pinnedEventId: config.config(for: WidgetKindID.countdown).eventId, events: appState.events) },
                                   showsLayout: false, showsAnimated: true,
                                   extra: { countdownEventPicker })
                        widgetCard(kind: WidgetKindID.mood,
                                   title: L10n.t("studio.widget.mood"), icon: "face.smiling",
                                   preview: { palette in MoodPreview(palette: palette, snapshot: snapshot) },
                                   showsLayout: false, showsAnimated: false)
                        widgetCard(kind: WidgetKindID.daily,
                                   title: L10n.t("studio.widget.daily"), icon: "envelope.fill",
                                   preview: { palette in DailyPreview(palette: palette, snapshot: snapshot) },
                                   showsLayout: false, showsAnimated: true)
                        widgetCard(kind: WidgetKindID.streak,
                                   title: L10n.t("studio.widget.streak"), icon: "flame.fill",
                                   preview: { palette in StreakPreview(palette: palette, snapshot: snapshot) },
                                   showsLayout: false, showsAnimated: true)
                        widgetCard(kind: WidgetKindID.photo,
                                   title: L10n.t("studio.widget.photo"), icon: "camera.fill",
                                   preview: { palette in PhotoPreview(palette: palette) },
                                   showsLayout: false, showsAnimated: false,
                                   extra: {
                                       VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
                                           photoSourcePicker
                                           photoFramePicker   // Frames
                                       }
                                   })
                        widgetCard(kind: WidgetKindID.sendLove,
                                   title: L10n.t("studio.widget.sendLove"), icon: "paperplane.fill",
                                   preview: { palette in SendLovePreview(palette: palette, snapshot: snapshot) },
                                   showsLayout: false, showsAnimated: false)
                        widgetCard(kind: WidgetKindID.memory,
                                   title: L10n.t("studio.widget.memory"), icon: "photo.on.rectangle.angled",
                                   preview: { palette in MemoryPreview(palette: palette, snapshot: snapshot) },
                                   showsLayout: false, showsAnimated: false)
                        photoChromeCard
                        hintCard
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
            }
            .navigationTitle(L10n.t("studio.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: config) { _, newValue in
            SharedStore.writeStudioConfig(newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Diagnostics

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            if SharedStore.appGroupAvailable {
                if snapshot != nil {
                    Label(L10n.t("studio.diag.ok"), systemImage: "checkmark.seal.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.lampengold)
                    if let updatedAt = snapshot?.updatedAt {
                        Text(L10n.t("studio.diag.updated", ["time": L10n.relativeShort(updatedAt)]))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                } else {
                    Label(L10n.t("studio.diag.noData"), systemImage: "hourglass")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                }
            } else {
                Label(L10n.t("studio.diag.noGroup"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.energyRed)
                Text(L10n.t("studio.diag.noGroupHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard(grain: false)
    }

    // MARK: Global theme

    private var globalThemeCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("studio.globalTheme"))
            Text(L10n.t("studio.globalThemeHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            themeSwatchRow(selection: Binding(
                get: { config.themeId },
                set: { config.themeId = $0 }
            ), allowStudioDefault: false)
        }
        .nightCard()
    }

    private var photoChromeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { config.usePhotoChrome },
                set: { config.usePhotoChrome = $0 }
            )) {
                Label(L10n.t("settings.widgetPhotoChrome"), systemImage: "photo.on.rectangle.angled")
                    .labelStyle(SettingsRowLabelStyle())
            }
            .tint(coupleTint.blend)
            Text(L10n.t("settings.widgetPhotoChromeHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .padding(.leading, LayoutMetrics.s(40))
        }
        .nightCard()
    }

    private var hintCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("settings.widgets"), systemImage: "square.grid.2x2.fill")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("settings.widgetsHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            Text(L10n.t("studio.perWidgetHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    // MARK: Per-widget card

    @ViewBuilder
    private func widgetCard(kind: String, title: String, icon: String,
                            preview: (WidgetPreviewPalette) -> some View,
                            showsLayout: Bool, showsAnimated: Bool,
                            @ViewBuilder extra: () -> some View = { EmptyView() }) -> some View {
        let palette = WidgetPreviewPalette(spec: config.theme(for: kind))
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Nacht.sekundaer)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
            }

            // Live preview (small-widget replica)
            HStack {
                Spacer(minLength: 0)
                preview(palette)
                    .frame(width: LayoutMetrics.s(150), height: LayoutMetrics.s(150))
                    .background(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(LinearGradient(colors: palette.backgroundColors,
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                Spacer(minLength: 0)
            }

            Text(L10n.t("studio.presets"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            presetRow(kind: kind)

            // Theme override
            Text(L10n.t("studio.theme"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            themeSwatchRow(selection: themeBinding(kind), allowStudioDefault: true)

            if showsLayout {
                Text(L10n.t("studio.layout"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                layoutRow(kind: kind)
            }

            if showsAnimated {
                Toggle(isOn: animatedBinding(kind)) {
                    Label(L10n.t("studio.animated"), systemImage: "timer")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
            }

            extra()
        }
        .nightCard()
    }

    // MARK: Controls

    /// Theme swatches; "studio default" prepended for per-widget overrides.
    private func themeSwatchRow(selection: Binding<String?>, allowStudioDefault: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.s(10)) {
                if allowStudioDefault {
                    swatch(hexes: [], label: L10n.t("studio.themeDefault"),
                           selected: selection.wrappedValue == nil) {
                        selection.wrappedValue = nil
                    }
                }
                ForEach(WidgetThemes.all) { spec in
                    swatch(hexes: spec.backgroundHexes,
                           label: spec.name(lang: L10n.lang),
                           selected: selection.wrappedValue == spec.id) {
                        selection.wrappedValue = spec.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Overload for the non-optional global theme.
    private func themeSwatchRow(selection: Binding<String>, allowStudioDefault: Bool) -> some View {
        themeSwatchRow(selection: Binding<String?>(
            get: { selection.wrappedValue },
            set: { selection.wrappedValue = $0 ?? "night" }
        ), allowStudioDefault: allowStudioDefault)
    }

    private func swatch(hexes: [String], label: String, selected: Bool,
                        action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if hexes.isEmpty {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.nachtInnenFill)
                        Image(systemName: "sparkles")
                            .font(.system(.footnote))
                            .foregroundStyle(Nacht.sekundaer)
                    } else {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(LinearGradient(colors: hexes.map { Color(hex: $0) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(selected ? AnyShapeStyle(coupleTint.blend)
                                               : AnyShapeStyle(Nacht.naht),
                                      lineWidth: selected ? 2.5 : Theme.hairlineWidth)
                )
                .shadow(color: selected ? coupleTint.blend.opacity(0.35) : .clear, radius: 6)
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func layoutRow(kind: String) -> some View {
        let layouts: [(id: String, label: String)] = [
            ("auto", L10n.t("studio.layout.auto")),
            ("classic", L10n.t("studio.layout.classic")),
            ("hero", L10n.t("studio.layout.hero")),
            ("minimal", L10n.t("studio.layout.minimal")),
        ]
        let binding = layoutBinding(kind)
        return HStack(spacing: LayoutMetrics.s(8)) {
            ForEach(layouts, id: \.id) { layout in
                let selected = (binding.wrappedValue ?? "auto") == layout.id
                Button {
                    binding.wrappedValue = layout.id == "auto" ? nil : layout.id
                    Haptics.shared.tap()
                } label: {
                    Text(layout.label)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .padding(.horizontal, LayoutMetrics.s(12))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(Capsule().fill(selected ? coupleTint.blend.opacity(0.16) : Papier.nachtInnenFill))
                        .overlay(Capsule().strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                                        lineWidth: Theme.hairlineWidth))
                        .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func presetRow(kind: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.s(8)) {
                ForEach(WidgetPresetCatalog.presets(for: kind)) { preset in
                    Button {
                        config.update(kind: kind) {
                            WidgetPresetCatalog.apply(preset, to: &$0)
                        }
                        Haptics.shared.tap()
                    } label: {
                        Text(preset.name(language: L10n.lang))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, LayoutMetrics.s(12))
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Papier.nachtInnenFill))
                            .overlay(Capsule().strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
                            .foregroundStyle(Papier.aufNacht)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var countdownEventPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("studio.countdownEvent"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            Menu {
                Button {
                    config.update(kind: WidgetKindID.countdown) { $0.eventId = nil }
                } label: {
                    if config.config(for: WidgetKindID.countdown).eventId == nil {
                        Label(L10n.t("studio.countdownNext"), systemImage: "checkmark")
                    } else {
                        Text(L10n.t("studio.countdownNext"))
                    }
                }
                ForEach(appState.events) { event in
                    Button {
                        config.update(kind: WidgetKindID.countdown) { $0.eventId = event.id }
                    } label: {
                        if config.config(for: WidgetKindID.countdown).eventId == event.id {
                            Label("\(event.emoji) \(event.title)", systemImage: "checkmark")
                        } else {
                            Text("\(event.emoji) \(event.title)")
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedCountdownLabel)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(coupleTint.blend)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
        }
    }

    private var selectedCountdownLabel: String {
        guard let id = config.config(for: WidgetKindID.countdown).eventId,
              let event = appState.events.first(where: { $0.id == id }) else {
            return L10n.t("studio.countdownNext")
        }
        return "\(event.emoji) \(event.title)"
    }

    private var photoSourcePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("studio.photoSource"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            HStack(spacing: LayoutMetrics.s(8)) {
                photoSourceChip(nil, label: L10n.t("studio.photoSource.favorite"))
                photoSourceChip("newest", label: L10n.t("studio.photoSource.newest"))
            }
        }
    }

    private func photoSourceChip(_ value: String?, label: String) -> some View {
        let current = config.config(for: WidgetKindID.photo).photoSource
        let selected = current == value || (value == nil && current == "favorite")
        return Button {
            config.update(kind: WidgetKindID.photo) { $0.photoSource = value }
            Haptics.shared.tap()
            Task {
                await appState.refreshWidgetPhoto()
                appState.updateWidgetSnapshot()
            }
        } label: {
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, LayoutMetrics.s(12))
                .padding(.vertical, LayoutMetrics.s(8))
                .background(Capsule().fill(selected ? coupleTint.blend.opacity(0.16) : Papier.nachtInnenFill))
                .overlay(Capsule().strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                                lineWidth: Theme.hairlineWidth))
                .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
        }
        .buttonStyle(.plain)
    }

    // Photo frame styles: polaroid / film strip / scrapbook.

    private var photoFramePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("photoframe.title"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.s(8)) {
                    photoFrameChip(nil, emoji: "🖼️", label: L10n.t("photoframe.none"))
                    photoFrameChip("polaroid", emoji: "🤍", label: L10n.t("photoframe.polaroid"))
                    photoFrameChip("filmstrip", emoji: "🎞️", label: L10n.t("photoframe.filmstrip"))
                    photoFrameChip("photobooth", emoji: "📷", label: L10n.t("photoframe.photobooth"))
                    photoFrameChip("scrapbook", emoji: "📔", label: L10n.t("photoframe.scrapbook"))
                }
            }
        }
    }

    private func photoFrameChip(_ value: String?, emoji: String, label: String) -> some View {
        let selected = config.config(for: WidgetKindID.photo).photoFrame == value
        return Button {
            config.update(kind: WidgetKindID.photo) { $0.photoFrame = value }
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 3) {
                Text(emoji)
                    .font(.system(.subheadline))
                Text(label)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(7))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? coupleTint.blend.opacity(0.16) : Papier.nachtInnenFill))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(coupleTint.blend)
                                           : AnyShapeStyle(Nacht.naht),
                                  lineWidth: Theme.hairlineWidth))
            .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
        }
        .buttonStyle(.plain)
    }

    // MARK: Bindings

    private func themeBinding(_ kind: String) -> Binding<String?> {
        Binding(
            get: { config.config(for: kind).themeId },
            set: { newValue in config.update(kind: kind) { $0.themeId = newValue } }
        )
    }

    private func layoutBinding(_ kind: String) -> Binding<String?> {
        Binding(
            get: { config.config(for: kind).layout },
            set: { newValue in config.update(kind: kind) { $0.layout = newValue } }
        )
    }

    private func animatedBinding(_ kind: String) -> Binding<Bool> {
        Binding(
            get: { config.config(for: kind).animated ?? true },
            set: { newValue in config.update(kind: kind) { $0.animated = newValue } }
        )
    }
}

// MARK: - Preview palette (app-side mirror of the widget palette)

struct WidgetPreviewPalette {
    let spec: WidgetThemeSpec

    var backgroundColors: [Color] { spec.backgroundHexes.map { Color(hex: $0) } }
    var accent: Color { Color(hex: spec.accentHex) }
    var accentSecondary: Color { Color(hex: spec.accentSecondaryHex) }
    var textPrimary: Color { spec.isLight ? Color(hex: "26102E") : .white }
    var textSecondary: Color { textPrimary.opacity(0.65) }
    var chipFill: Color { spec.isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.1) }

    var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accentSecondary],
                       startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Mini previews (small-widget replicas rendered in-app)

private struct DaysPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?
    let layout: String?

    private var days: Int {
        SharedDates.daysSince(snapshot?.anniversary) ?? snapshot?.daysTogether ?? 1002
    }

    var body: some View {
        Group {
            if layout == "hero" {
                VStack(spacing: 2) {
                    Text("\(days)")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(palette.heroGradient)
                        .minimumScaleFactor(0.4)
                    Text(L10n.isGerman ? "Tage 💜" : "days 💜")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                }
            } else if layout == "minimal" {
                VStack(alignment: .leading, spacing: 3) {
                    Image(systemName: "heart.fill")
                        .font(.system(.caption))
                        .foregroundStyle(palette.accent)
                    Spacer(minLength: 0)
                    Text("\(days)")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text(L10n.isGerman ? "Tage" : "days")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(snapshot?.partnerAvatar ?? "💜")
                            .font(.system(.caption))
                        Text(snapshot?.partnerName ?? "Schatz")
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "heart.fill")
                            .font(.system(.caption2))
                            .foregroundStyle(palette.accent)
                    }
                    Spacer(minLength: 0)
                    Text("\(days)")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(palette.heroGradient)
                        .minimumScaleFactor(0.5)
                    Text(L10n.isGerman ? "Tage zusammen" : "days together")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accent)
                }
                .padding(12)
            }
        }
    }
}

private struct CountdownPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?
    let pinnedEventId: String?
    let events: [EventItem]

    private var eventInfo: (title: String, emoji: String, days: Int)? {
        if let pinnedEventId,
           let event = events.first(where: { $0.id == pinnedEventId }),
           let days = SharedDates.daysUntil(event.date, repeatsYearly: event.repeatsYearly),
           days >= 0 {
            return (event.title, event.emoji, days)
        }
        if let title = snapshot?.nextEventTitle,
           let days = SharedDates.daysUntil(snapshot?.nextEventDate), days >= 0 {
            return (title, snapshot?.nextEventEmoji ?? "💫", days)
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let info = eventInfo {
                Text(info.emoji)
                    .font(.system(.title2))
                Spacer(minLength: 0)
                Text(info.title)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text(L10n.isGerman ? "in \(info.days) Tagen" : "in \(info.days) days")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .foregroundStyle(palette.heroGradient)
            } else {
                Text("✨")
                    .font(.system(.title2))
                Spacer(minLength: 0)
                Text(L10n.isGerman ? "Kein Moment geplant" : "No moment planned")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct MoodPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(snapshot?.partnerAvatar ?? "💜")
                    .font(.system(.caption))
                Text(snapshot?.partnerName ?? "Schatz")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(snapshot?.partnerMood ?? "🥰")
                .font(.system(.largeTitle))
            if let note = snapshot?.partnerMoodNote, !note.isEmpty {
                Text(note)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct DailyPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?

    private var question: String {
        (L10n.isGerman ? snapshot?.dailyQuestionDE : snapshot?.dailyQuestionEN)
            ?? (L10n.isGerman ? "Eure Frage des Tages" : "Your daily question")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("💌")
                    .font(.system(.caption))
                Spacer(minLength: 0)
                if let streak = snapshot?.streak, streak > 1 {
                    Text("🔥 \(streak)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.accentSecondary)
                }
            }
            Text(question)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct StreakPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("🔥")
                    .font(.system(.caption))
                Text(L10n.isGerman ? "Antwort-Serie" : "Answer streak")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text("\(snapshot?.streak ?? 5)")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(palette.heroGradient)
            Text(L10n.isGerman ? "Tage in Folge" : "days in a row")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(palette.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct PhotoPreview: View {
    let palette: WidgetPreviewPalette

    var body: some View {
        Group {
            if let data = SharedStore.readCachedPhotoJPEG(),
               let image = BoundedImageDecoder.image(data: data, maxPixelSize: 800) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 4) {
                    Text("📸")
                        .font(.system(.title))
                    Text(L10n.isGerman ? "Noch kein Foto" : "No photo yet")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

private struct SendLovePreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(snapshot?.partnerAvatar ?? "💜")
                    .font(.system(.caption))
                Text(snapshot?.partnerName ?? "Schatz")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(["💓", "😘", "🫂", "💭"], id: \.self) { emoji in
                    Text(emoji)
                        .font(.system(.callout))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(palette.chipFill))
                        .overlay(Circle().strokeBorder(palette.accent.opacity(0.4), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// „An diesem Tag" memory widget preview.
private struct MemoryPreview: View {
    let palette: WidgetPreviewPalette
    let snapshot: WidgetSnapshot?

    private var agoText: String {
        guard let n = snapshot?.memoryDistanceN,
              let unit = snapshot?.memoryDistanceUnit,
              snapshot?.memoryDateKey == SharedDates.todayKey() else {
            return L10n.t(MemoriesLogic.agoLabelKey(unit: "months", n: 3), ["n": "3"])
        }
        return L10n.t(MemoriesLogic.agoLabelKey(unit: unit, n: n), ["n": String(n)])
    }

    private var line: String? {
        guard snapshot?.memoryDateKey == SharedDates.todayKey() else { return nil }
        return L10n.isGerman ? snapshot?.memoryLineDE : snapshot?.memoryLineEN
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("📅")
                .font(.system(.title2))
            Spacer(minLength: 0)
            Text(L10n.t("onthisday.title"))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(palette.accent)
            Text(agoText)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            if let line, !line.isEmpty {
                Text(line)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
    }
}
