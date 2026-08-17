import SwiftUI
import WidgetKit

struct CoupleMonogramView: View {
    let firstName: String
    let secondName: String
    let palette: CouplePalette?
    let style: MonogramStyle
    var size: CGFloat = 64

    private var resolved: CouplePalette {
        palette ?? CouplePaletteRules.derived(first: "#FF5C8A", second: "#A855F7")
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: resolved.primary), Color(hex: resolved.secondary)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(
                    Color(hex: resolved.accent),
                    style: StrokeStyle(
                        lineWidth: style == .minimal ? 1.5 : 3,
                        dash: style == .ribbon ? [6, 4] : []
                    )
                )
            Text(CoupleMonogram.initials(first: firstName, second: secondName))
                .font(.system(size: size * 0.28, weight: .heavy, design: .serif))
                .foregroundStyle(Color(hex: resolved.onAccent))
                .minimumScaleFactor(0.65)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hex: resolved.accent).opacity(0.3), radius: size * 0.12)
        .accessibilityLabel(L10n.t("personalization.monogram.a11y"))
    }
}

struct PersonalizationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var primary = "#FF5C8A"
    @State private var secondary = "#A855F7"
    @State private var style = MonogramStyle.seal
    @State private var saving = false

    private var palette: CouplePalette {
        CouplePaletteRules.derived(first: primary, second: secondary)
    }

    private var firstName: String { appState.me?.name ?? L10n.t("chat.you") }
    private var secondName: String { appState.partnerName }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fix4 Befund 7: Amt sheets are still tool rooms — no
                // animated dust behind the palette work.
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(18)) {
                        preview
                        presetSection
                        customSection
                        monogramSection
                        contrastSection
                        Button {
                            Task { await save() }
                        } label: {
                            if saving {
                                BusySpinner()
                            } else {
                                Text(L10n.t("common.save"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(saving)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("personalization.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            if let current = appState.couple?.palette {
                primary = current.primary
                secondary = current.secondary
            } else {
                primary = appState.me?.color ?? primary
                secondary = appState.partner?.color ?? secondary
            }
            style = appState.couple?.monogramStyle ?? .seal
        }
    }

    private var preview: some View {
        HStack(spacing: LayoutMetrics.s(16)) {
            CoupleMonogramView(
                firstName: firstName,
                secondName: secondName,
                palette: palette,
                style: style,
                size: LayoutMetrics.s(82)
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("personalization.preview"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("personalization.preview.body"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: L10n.t("personalization.presets"))
            HStack(spacing: LayoutMetrics.s(12)) {
                ForEach(Array(CouplePaletteRules.presets.enumerated()), id: \.offset) { _, preset in
                    Button {
                        primary = preset.primary
                        secondary = preset.secondary
                        Haptics.shared.tap()
                    } label: {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: preset.primary), Color(hex: preset.secondary)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle().strokeBorder(
                                    primary == preset.primary && secondary == preset.secondary
                                        ? Color.white : Theme.hairline,
                                    lineWidth: 2
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("personalization.preset.a11y"))
                }
            }
        }
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: L10n.t("personalization.custom"))
            TextField(L10n.t("personalization.primary"), text: $primary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(DreamyFieldStyle())
            TextField(L10n.t("personalization.secondary"), text: $secondary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(DreamyFieldStyle())
            Text(L10n.t("personalization.custom.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var monogramSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader(title: L10n.t("personalization.monogram"))
            Picker(L10n.t("personalization.monogram"), selection: $style) {
                ForEach(MonogramStyle.allCases, id: \.self) { option in
                    Text(L10n.t("personalization.monogram.\(option.rawValue)")).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var contrastSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(Theme.mint)
            // Judged against the REAL night anchor (the room's sepia umbra,
            // Papier & Licht) — the retired violet literal understated the
            // ratio the derivation ladder actually guarantees.
            Text(L10n.t("personalization.contrast", [
                "ratio": String(
                    format: "%.1f",
                    CouplePaletteRules.contrastRatio(
                        palette.accent, CouplePaletteRules.darkBackgroundHex) ?? 0
                ),
            ]))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func save() async {
        guard let api = appState.api else { return }
        saving = true
        defer { saving = false }
        do {
            let updated = try await api.updateCouple(palette: palette, monogramStyle: style)
            appState.couple = updated
            appState.updateWidgetSnapshot()
            var studio = SharedStore.readStudioConfig()
            studio.themeId = "couple"
            SharedStore.writeStudioConfig(studio)
            WidgetCenter.shared.reloadAllTimelines()
            Haptics.shared.success()
            dismiss()
        } catch {
            appState.handleAPIError(error)
        }
    }
}

struct ProceduralStickerView: View {
    let recipe: StickerRecipe
    var size: CGFloat = 120

    private var symbol: String {
        switch recipe.shape {
        case .heart: "heart.fill"
        case .cloud: "cloud.fill"
        case .burst: "seal.fill"
        case .seal: "rosette"
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color(hex: recipe.color))
                .shadow(color: Color(hex: recipe.color).opacity(0.5), radius: 10)
            if let label = recipe.label {
                // Computed ink instead of hard white: light sticker colors
                // (mint 1.52:1, gold 1.44:1, sky 2.54:1) drowned the label —
                // the readable-foreground rule keeps white only where it
                // truly clears the floor (pinned in PersonalizationLogicTests).
                Text(label)
                    .font(.system(size: size * 0.12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(
                        hex: CouplePaletteRules.readableForeground(on: recipe.color)))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .padding(size * 0.19)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(recipe.label ?? L10n.t("chat.sticker"))
    }
}

/// Recently sent sticker recipes, per couple — a favorite sticker never
/// requires re-scribbling the whole doodle.
enum StickerRecents {
    static let capacity = 12

    private static func key(coupleId: String?) -> String {
        "sooodreamy.stickerRecents.\(coupleId ?? "solo")"
    }

    static func load(coupleId: String?) -> [StickerRecipe] {
        guard let data = UserDefaults.standard.data(forKey: key(coupleId: coupleId)),
              let recipes = try? JSONDecoder().decode([StickerRecipe].self, from: data) else {
            return []
        }
        return recipes
    }

    static func record(_ recipe: StickerRecipe, coupleId: String?) {
        var recipes = load(coupleId: coupleId)
        recipes.removeAll { $0 == recipe }
        recipes.insert(recipe, at: 0)
        if recipes.count > capacity {
            recipes = Array(recipes.prefix(capacity))
        }
        if let data = try? JSONEncoder().encode(recipes) {
            UserDefaults.standard.set(data, forKey: key(coupleId: coupleId))
        }
    }
}

struct StickerWorkshopSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onSend: (StickerRecipe) -> Void

    /// One entry per pen-down…pen-up — separate strokes never get joined
    /// by a phantom connecting line, so an "i" with a dot finally works.
    @State private var strokes: [[StickerPoint]] = []
    @State private var currentStroke: [StickerPoint] = []
    @State private var color = "#FF5C8A"
    @State private var label = ""
    @State private var recents: [StickerRecipe] = []

    /// The recipe hash runs over the flat point list (wire format and
    /// existing stickers stay stable).
    private var flatPoints: [StickerPoint] {
        strokes.flatMap { $0 } + currentStroke
    }

    private var recipe: StickerRecipe {
        StickerWorkshop.recipe(points: flatPoints, color: color, label: label)
    }

    /// An empty pad plus an empty label would produce a meaningless
    /// default-seed sticker — blocked at the button.
    private var isEmpty: Bool {
        flatPoints.isEmpty && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fix4 Befund 7: still tool room, like the parent sheet.
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: Space.l) {
                        recentsRow
                        doodlePad
                        padActions
                        // Conscious glass exception: the preview shows the
                        // sticker exactly as it will land on the night chat
                        // canvas — paper here would lie about the result.
                        ProceduralStickerView(recipe: recipe, size: LayoutMetrics.s(140))
                            .glassCard(.compact)
                        TextField(L10n.t("chat.sticker.label"), text: $label)
                            .textFieldStyle(DreamyFieldStyle())
                        HStack {
                            ForEach(Theme.memberColors, id: \.self) { value in
                                Button {
                                    color = "#" + value
                                } label: {
                                    Circle()
                                        .fill(Color(hex: value))
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle().strokeBorder(
                                                color == "#" + value ? .white : .clear,
                                                lineWidth: 2
                                            )
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text(L10n.t(isEmpty ? "chat.sticker.emptyHint" : "chat.sticker.honesty"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            send(recipe)
                        } label: {
                            Label(L10n.t("chat.sticker.send"), systemImage: "paperplane.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isEmpty)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("chat.sticker.workshop"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
            .onAppear {
                recents = StickerRecents.load(coupleId: appState.couple?.id)
            }
        }
    }

    private func send(_ recipe: StickerRecipe) {
        StickerRecents.record(recipe, coupleId: appState.couple?.id)
        onSend(recipe)
        dismiss()
    }

    /// One-tap resend of the last sent stickers — above the pad, so the
    /// favorite path is the shortest one.
    @ViewBuilder private var recentsRow: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(L10n.t("chat.sticker.recent"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(Array(recents.enumerated()), id: \.offset) { _, recent in
                            Button {
                                Haptics.shared.tap()
                                send(recent)
                            } label: {
                                ProceduralStickerView(recipe: recent, size: LayoutMetrics.s(52))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(recent.label ?? L10n.t("chat.sticker"))
                        }
                    }
                }
            }
        }
    }

    private var doodlePad: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                for stroke in strokes {
                    drawStroke(stroke, context: &context, size: size)
                }
                if !currentStroke.isEmpty {
                    drawStroke(currentStroke, context: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width = max(proxy.size.width, 1)
                        let height = max(proxy.size.height, 1)
                        currentStroke.append(StickerPoint(
                            x: min(1, max(0, value.location.x / width)),
                            y: min(1, max(0, value.location.y / height))
                        ))
                    }
                    .onEnded { _ in
                        guard !currentStroke.isEmpty else { return }
                        strokes.append(currentStroke)
                        currentStroke = []
                    }
            )
        }
        .frame(height: LayoutMetrics.s(180))
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Theme.innerFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.hairline)
                )
        )
        .accessibilityLabel(L10n.t("chat.sticker.canvas.a11y"))
    }

    /// Shared `StrokeRenderer` — the pad draws exactly like the big canvas
    /// (smoothing, tap = dot).
    private func drawStroke(_ stroke: [StickerPoint],
                            context: inout GraphicsContext, size: CGSize) {
        StrokeRenderer.draw(points: stroke.map { [$0.x, $0.y] },
                            color: Color(hex: color),
                            width: 7,
                            tool: "pen",
                            boardColor: .clear,
                            context: &context,
                            size: size)
    }

    /// Undo & clear live in the thumb zone, right under the pad — a botched
    /// last stroke no longer forces a full restart.
    private var padActions: some View {
        HStack(spacing: Space.m) {
            Button {
                Haptics.shared.tap()
                if !currentStroke.isEmpty {
                    currentStroke = []
                } else if !strokes.isEmpty {
                    strokes.removeLast()
                }
            } label: {
                Label(L10n.t("chat.sticker.undo"), systemImage: "arrow.uturn.backward")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(strokes.isEmpty && currentStroke.isEmpty
                             ? Theme.textTertiary : Theme.textPrimary)
            .disabled(strokes.isEmpty && currentStroke.isEmpty)
            Button {
                Haptics.shared.tap()
                strokes = []
                currentStroke = []
            } label: {
                Label(L10n.t("chat.sticker.clear"), systemImage: "trash")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(strokes.isEmpty && currentStroke.isEmpty
                             ? Theme.textTertiary : Theme.energyRed)
            .disabled(strokes.isEmpty && currentStroke.isEmpty)
            Spacer(minLength: 0)
        }
    }
}

struct MessageEffectOverlay: View {
    let effect: MessageEffect
    @State private var expanded = false

    private var emoji: String {
        switch effect {
        case .hearts: "💞"
        case .snow: "❄️"
        case .sparkle: "✨"
        case .fireworks: "🎆"
        case .slam: "💥"
        case .invisible: "🫥"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(expanded ? 0.2 : 0)
                .ignoresSafeArea()
            ForEach(0..<18, id: \.self) { index in
                Text(emoji)
                    .font(.system(.title2))
                    .scaleEffect(1 + CGFloat(index % 4) * 0.25)
                    .offset(
                        x: expanded ? CGFloat((index * 47) % 320 - 160) : 0,
                        y: expanded ? CGFloat((index * 83) % 620 - 310) : 0
                    )
                    .opacity(expanded ? 0 : 1)
                    .scaleEffect(expanded ? 1.35 : 0.3)
                    .animation(
                        Theme.Motion.drift(effect == .slam ? 0.65 : 2.2)
                            .delay(Double(index) * 0.025),
                        value: expanded
                    )
            }
        }
        .allowsHitTesting(false)
        .onAppear { expanded = true }
        .accessibilityHidden(true)
    }
}
