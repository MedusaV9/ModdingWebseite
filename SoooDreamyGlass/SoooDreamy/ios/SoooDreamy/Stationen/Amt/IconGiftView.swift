import SwiftUI
import WidgetKit

// App-icon gifts: 9 procedurally rendered icon variants
// (GenerateIcon.swift renders the PNGs in CI; the previews here re-draw the
// same palettes in SwiftUI, so the repo stays binary-free). A partner can
// gift an icon — the unwrap ceremony pops on the receiver's next app-open.

/// Client metadata for every icon variant. `assetName` must match the
/// appiconset names in Assets.xcassets + ASSETCATALOG_COMPILER_ALTERNATE_-
/// APPICON_NAMES in project.yml; ids mirror the server's ICON_IDS.
enum AppIconKit {
    struct Variant: Identifiable, Equatable {
        let id: String
        /// nil = primary icon (classic).
        let assetName: String?
        let bg: [Color]
        let heart: Color
    }

    /// Derived from `IconPaletteTable` (the single Foundation source, R2) —
    /// this mirror can no longer drift from the widget palettes by
    /// construction; the generator script is held to the same table by the
    /// source-scan test in `WidgetThemesTests`.
    static let variants: [Variant] = IconPaletteTable.entries.map { entry in
        Variant(id: entry.id,
                assetName: entry.id == "classic" ? nil : "AppIcon-\(entry.id)",
                bg: entry.bg.map { Color(hex: $0) },
                heart: Color(hex: entry.heart))
    }

    static func variant(_ id: String) -> Variant {
        variants.first { $0.id == id } ?? variants[0]
    }

    static var currentId: String {
        guard let name = UIApplication.shared.alternateIconName else { return "classic" }
        return variants.first { $0.assetName == name }?.id ?? "classic"
    }

    /// Switches the home-screen icon; completion(false) when iOS refuses
    /// (e.g. sideload signing stripped the alternate icons).
    static func apply(_ id: String, completion: @escaping (Bool) -> Void) {
        let variant = variant(id)
        guard UIApplication.shared.supportsAlternateIcons else {
            completion(false)
            return
        }
        UIApplication.shared.setAlternateIconName(variant.assetName) { error in
            if error == nil {
                // W7/35-Rest: mirror the icon into the app group and redraw
                // — widgets on the "Passend zum Icon" theme follow along.
                Task { @MainActor in
                    SharedStore.writeAppIconId(id)
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            completion(error == nil)
        }
    }

    /// Seeds/heals the app-group mirror on app start (first run after the
    /// update, restored backups, …) — the widget theme must never dress as
    /// an icon the home screen is not actually wearing.
    @MainActor
    static func syncMirror() {
        SharedStore.writeAppIconId(currentId)
    }
}

// MARK: - Procedural preview (mirrors GenerateIcon's sealed polaroid)

/// Miniature of an icon variant — the v3.0 „Versiegeltes Polaroid" motif
/// the CI renderer paints (GenerateIcon.swift, four layers back→front:
/// sepia room + lamp cone, paper polaroid with the wide foot border, two
/// interflowing ink arcs, wax seal with embossed heart), redrawn live in
/// SwiftUI at the renderer's exact proportions so no PNGs are bundled
/// for the picker. P6-C replaced the previous aurora/glass-heart sketch,
/// which no longer matched the shipping icon.
struct IconVariantPreview: View {
    let variant: AppIconKit.Variant
    var size: CGFloat = 58

    /// GenerateIcon geometry in 1024-space, normalized: paper 640 wide,
    /// 44-pt border, 146-pt foot → window 552² at y 90; seal Ø 340 at
    /// (0.581, 0.8126); paper tilt −4°.
    private var paperWidth: CGFloat { size * 0.625 }
    private var paperBorder: CGFloat { size * 0.043 }
    private var windowSide: CGFloat { paperWidth - 2 * paperBorder }
    private var paperHeight: CGFloat { size * 0.7246 }
    private var paperTop: CGFloat { size * 0.088 }
    private var sealDiameter: CGFloat { size * 0.332 }

    var body: some View {
        ZStack {
            room
            polaroid
                // The renderer's fixed −4° through the ONE sanctioned
                // rotation token: seed 4453 lands the seeded tilt on
                // −4.00° (brute-forced against PaperRules.tiltDegrees).
                .paperTilt(seed: 4453)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
    }

    /// L1 Zimmer: the variant gradient bent sepia-warm (GenerateIcon
    /// mixes 16 % toward its sepia 0.42/0.31/0.20) + the invariant
    /// Licht.lampengold cone falling in from 10 o'clock.
    private var room: some View {
        ZStack {
            LinearGradient(colors: [variant.bg[2], variant.bg[1], variant.bg[0]],
                           startPoint: .top, endPoint: .bottom)
            Color(red: 0.42, green: 0.31, blue: 0.20).opacity(0.16)
            RadialGradient(
                colors: [Licht.lampengold.opacity(0.5), Licht.lampengold.opacity(0)],
                center: UnitPoint(x: 0.11, y: -0.06),
                startRadius: 0, endRadius: size * 0.93)
        }
    }

    /// L2 Papier + L3 Foto + L4 Siegel — one tilt group, like the render.
    private var polaroid: some View {
        ZStack(alignment: .top) {
            // L2: invariant paper white, wide foot border, kante hairline.
            RoundedRectangle(cornerRadius: size * 0.014, style: .continuous)
                .fill(Papier.polaroid)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.014, style: .continuous)
                        .strokeBorder(Papier.kante, lineWidth: max(0.5, size * 0.006)))
                .frame(width: paperWidth, height: paperHeight)
                .shadow(color: .black.opacity(0.3),
                        radius: size * 0.045, x: size * 0.018, y: size * 0.028)
            photoWindow
                .padding(.top, paperBorder)
            seal
                .offset(x: paperWidth * 0.13, y: paperHeight - sealDiameter / 2)
        }
        .frame(width: paperWidth, height: paperHeight)
        .position(x: size / 2, y: paperTop + paperHeight / 2)
    }

    /// L3: the memory — two interflowing ink arcs (heart hex + the
    /// hue-shifted companion) over the darkened variant ground.
    private var photoWindow: some View {
        ZStack {
            LinearGradient(colors: [variant.bg[0], variant.bg[1]],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
            // Arc A (heart ink) tips right; arc B folds over A's shoulder
            // — GenerateIcon's spines, scaled into the window square.
            InkArcShape(spine: .a)
                .stroke(variant.heart,
                        style: StrokeStyle(lineWidth: windowSide * 0.19,
                                           lineCap: .round))
            InkArcShape(spine: .b)
                .stroke(variant.heart,
                        style: StrokeStyle(lineWidth: windowSide * 0.17,
                                           lineCap: .round))
                // The companion ink = heart hue-rotated −40°, slightly
                // darkened — the same derivation the renderer computes.
                .hueRotation(.degrees(-40))
                .brightness(-0.08)
        }
        .frame(width: windowSide, height: windowSide)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.008))
    }

    /// L4: the wax seal — heart hex bent toward Wachs.rot, lit from
    /// 10 o'clock, embossed heart relief.
    private var seal: some View {
        ZStack {
            Circle()
                .fill(variant.heart)
                // Mirrors GenerateIcon's `waxRedMix`: the Nachtpostamt
                // classic bends its golden heart decisively toward
                // Wachs.rot (tiefer Siegellack unter goldener Tinte);
                // the gift variants keep the gentle bend.
                .overlay(Circle().fill(
                    Wachs.rot.opacity(variant.id == "classic" ? 0.72 : 0.35)))
                // Depth: the lamp catches the upper-left, the lower-right
                // sinks — one radial darkening instead of three strokes.
                .overlay(
                    Circle().fill(RadialGradient(
                        colors: [.clear, .black.opacity(0.32)],
                        center: UnitPoint(x: 0.36, y: 0.36),
                        startRadius: 0, endRadius: sealDiameter * 0.72)))
            HeartGlyph()
                .fill(.black.opacity(0.24))
                .frame(width: sealDiameter * 0.52, height: sealDiameter * 0.48)
                .offset(y: -sealDiameter * 0.02)
            // Matte gloss point, upper-left (GenerateIcon's white 0.20).
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.22), .clear],
                                     center: .center,
                                     startRadius: 0, endRadius: sealDiameter * 0.2))
                .frame(width: sealDiameter * 0.4, height: sealDiameter * 0.4)
                .offset(x: -sealDiameter * 0.2, y: -sealDiameter * 0.22)
        }
        .frame(width: sealDiameter, height: sealDiameter)
        .shadow(color: .black.opacity(0.28), radius: size * 0.02,
                x: size * 0.008, y: size * 0.012)
    }
}

/// GenerateIcon's two ink-arc spines (cubic beziers in 552-window space,
/// normalized) — the mini strokes the spine instead of building the full
/// tapered ribbon: at picker sizes the calligraphic taper is sub-pixel.
private struct InkArcShape: Shape {
    enum Spine {
        case a, b
    }

    let spine: Spine

    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        switch spine {
        case .a:
            path.move(to: pt(0.344, 0.895))
            path.addCurve(to: pt(0.681, 0.170),
                          control1: pt(0.250, 0.609),
                          control2: pt(0.388, 0.268))
        case .b:
            path.move(to: pt(0.728, 0.895))
            path.addCurve(to: pt(0.370, 0.221),
                          control1: pt(0.808, 0.591),
                          control2: pt(0.681, 0.297))
        }
        return path
    }
}

/// Classic parametric heart (matches the icon renderer's silhouette).
struct HeartGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let t = Double(i) / Double(steps) * 2 * .pi
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            let point = CGPoint(x: rect.midX + CGFloat(x) / 34 * rect.width,
                                y: rect.midY - CGFloat(y - 1.5) / 31 * rect.height)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Icon picker & gifting sheet

struct IconGiftSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var selected: String = AppIconKit.currentId
    @State private var note = ""
    @State private var sending = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        // Variant grid (shared by both actions below).
                        LazyVGrid(columns: columns, spacing: LayoutMetrics.s(14)) {
                            ForEach(AppIconKit.variants) { variant in
                                variantCell(variant)
                            }
                        }
                        .nightCard()

                        applyMineCard
                        if appState.partner != nil {
                            giftCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t("icongift.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func variantCell(_ variant: AppIconKit.Variant) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) { selected = variant.id }
        } label: {
            VStack(spacing: 6) {
                IconVariantPreview(variant: variant, size: LayoutMetrics.s(62))
                    .overlay(
                        RoundedRectangle(cornerRadius: LayoutMetrics.s(62) * 0.22, style: .continuous)
                            .strokeBorder(selected == variant.id ? coupleTint.blend : .clear, lineWidth: 2))
                Text(L10n.t("icon.name.\(variant.id)"))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(selected == variant.id ? Papier.aufNacht : Nacht.sekundaer)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if AppIconKit.currentId == variant.id {
                    Text(L10n.t("icongift.current"))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var applyMineCard: some View {
        Button {
            applySelected()
        } label: {
            HStack {
                Image(systemName: "iphone")
                    .font(.system(.title3, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Nacht.sekundaer)
                Text(L10n.t("icongift.pickMine"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(coupleTint.blend)
                    .opacity(AppIconKit.currentId == selected ? 1 : 0.25)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .disabled(AppIconKit.currentId == selected)
    }

    private var giftCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("icongift.giftTitle", ["name": appState.partnerName]))
            TextField(L10n.t("icongift.notePlaceholder"), text: $note, axis: .vertical)
                .textFieldStyle(DreamyFieldStyle())
                .lineLimit(1...3)
            Button {
                sendGift()
            } label: {
                if sending {
                    BusySpinner()
                } else {
                    Text(L10n.t("icongift.send"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending)
        }
        .nightCard()
    }

    private func applySelected() {
        Haptics.shared.tap()
        AppIconKit.apply(selected) { ok in
            if ok {
                SoundEngine.shared.play(.success)
                Haptics.shared.success()
                appState.showToast(L10n.t("icongift.appliedToast"), style: .success)
            } else {
                appState.showToast(L10n.t("icongift.applyFailed"), style: .error)
            }
        }
    }

    private func sendGift() {
        guard !sending else { return }
        sending = true
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let ok = await appState.giftIcon(selected, note: trimmed.isEmpty ? nil : trimmed)
            sending = false
            if ok { dismiss() }
        }
    }
}

// MARK: - Unwrap ceremony (full-screen overlay)

struct IconGiftUnwrapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.motionGate) private var motionGate
    let gift: IconGift

    @State private var unwrapped = false
    @State private var shaking = false

    private var variant: AppIconKit.Variant { AppIconKit.variant(gift.icon) }

    var body: some View {
        ZStack {
            // Reduce Transparency: the hand-painted dim layer becomes the
            // opaque night ink (MotionGate.scrim).
            motionGate.scrim(0.75)
                .ignoresSafeArea()
            if unwrapped {
                FloatingHeartsView(emojis: ["🎁", "✨", "💜", "🌟"], count: 20)
                    .ignoresSafeArea()
            }

            VStack(spacing: LayoutMetrics.s(18)) {
                Text(L10n.t("icongift.unwrap.title", ["name": appState.partnerName]))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                if unwrapped {
                    IconVariantPreview(variant: variant, size: LayoutMetrics.s(140))
                        .shadow(color: variant.heart.opacity(0.8), radius: 36)
                        .transition(.scale(scale: 0.35).combined(with: .opacity))

                    Text(L10n.t("icon.name.\(variant.id)"))
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.gold)

                    if let note = gift.note, !note.isEmpty {
                        Text("„\(note)“")
                            .font(.system(.subheadline, design: .rounded).italic())
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(L10n.t("icongift.unwrap.apply")) {
                        // Immediate quiet feedback in the tap frame — the
                        // apply result (success sound/toast) lands later.
                        AppCue.click.play()
                        applyAndClose()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, LayoutMetrics.s(44))

                    Button(L10n.t("icongift.unwrap.later")) {
                        AppCue.click.play()
                        close()
                    }
                    .buttonStyle(.plain)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    Button {
                        unwrap()
                    } label: {
                        Image(systemName: "gift.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: LayoutMetrics.s(110), height: LayoutMetrics.s(110))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.gold)
                            .rotationEffect(.degrees(shaking ? 4 : -4))
                            // Endless gift wiggle — gated: under Reduce
                            // Motion the parcel rests tilted (MotionGate).
                            .animation(motionGate.ambient(
                                Theme.Motion.drift(0.18).repeatForever(autoreverses: true)),
                                       value: shaking)
                            .shadow(color: Theme.gold.opacity(0.7), radius: 40)
                    }
                    .buttonStyle(.plain)

                    Text(L10n.t("icongift.unwrap.hint"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(LayoutMetrics.s(30))
            .contentColumn(.reading)
        }
        .onAppear { shaking = true }
    }

    private func unwrap() {
        SoundEngine.shared.play(.unlock)
        Haptics.shared.success()
        withAnimation(Theme.Motion.playful) {
            unwrapped = true
        }
        // R1-D: delight levels 1–2 bloom in the app-wide Lichtschein
        // (RootView host) instead of confetti — the fanfare stays.
        AppCue.fanfareMedium.play()
        LichtscheinCenter.shared.fire()
        // Tell the server (and the sender) the surprise landed.
        Task { _ = await appState.unwrapIconGift() }
    }

    private func applyAndClose() {
        AppIconKit.apply(variant.id) { ok in
            if ok {
                SoundEngine.shared.play(.success)
                appState.showToast(L10n.t("icongift.appliedToast"), style: .success)
            } else {
                appState.showToast(L10n.t("icongift.applyFailed"), style: .error)
            }
        }
        close()
    }

    private func close() {
        withAnimation(Theme.Motion.settle) {
            appState.pendingIconGift = nil
        }
    }
}
