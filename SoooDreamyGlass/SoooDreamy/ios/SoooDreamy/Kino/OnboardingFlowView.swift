import SwiftUI

/// v10 „Der große Runde": paged first-launch flow. Four Liquid-Glass pages
/// (welcome → what you can do → your server → the safety net) from
/// `OnboardingScript` (Linux-tested), then the server setup sheet.
/// Pairing follows via `phase` — with recovery explained BEFORE it happens.
///
/// W8D: on the VERY first launch the cinematic intro plays above this guide
/// (`CinematicIntroGate` persists the seen-flag), and the welcome page keeps
/// a quiet replay entry. The demo („Erst mal ansehen") never re-triggers it:
/// the intro finished before the demo button was even reachable.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @State private var pageIndex = 0
    @State private var showServerSetup = false
    /// Onboarding-eval fix: page 1 carries the invite scan — the partner's
    /// QR holds server AND code, so scanning must not wait behind a manual
    /// server setup that the QR would make redundant.
    @State private var showInviteScanner = false
    /// Session-local: flips when the intro finishes so the guide takes
    /// over without waiting for the next UserDefaults read.
    @State private var cinematicDone = false
    @State private var replayCinematic = false
    /// Measured frames of the guide's hand-off anchors (wordmark + the
    /// three entry cards) in `CinematicHandoff.space` — the cinema's
    /// finale lays its papers onto exactly these rects, so the swap is
    /// a morph, never a cut (Kino-Final-Eval finding 1).
    @State private var handoffFrames: [CinematicHandoffElement: CGRect] = [:]

    private var pages: [OnboardingPage] { OnboardingScript.pages }
    private var isLastPage: Bool { pageIndex >= pages.count - 1 }

    private var showsCinematic: Bool {
        replayCinematic || (!cinematicDone && CinematicIntroGate.shouldPlay)
    }

    var body: some View {
        ZStack {
            // The guide is mounted UNDER the cinema for the whole
            // performance: the cinema's room is opaque, so the guide
            // stays invisible but LAID OUT — its wordmark and entry
            // cards report their real frames through the handoff
            // preference, and chapter 7 morphs its papers onto exactly
            // those rects. When the cinema layer leaves, the matched
            // pixels are identical (the mock BECAME the original); only
            // the guide's remaining chrome lays itself in — a last
            // breath, not a cut. Hit-testing and VoiceOver stay with
            // the cinema until it finished.
            guide
                .allowsHitTesting(!showsCinematic)
                .accessibilityHidden(showsCinematic)
            if showsCinematic {
                CinematicIntroView(handoffTargets: handoffFrames) {
                    withAnimation(Theme.Motion.arrive) {
                        cinematicDone = true
                        replayCinematic = false
                    }
                }
                .transition(.opacity)
            }
        }
        .coordinateSpace(name: CinematicHandoff.space)
        .onPreferenceChange(CinematicHandoffFramesKey.self) { frames in
            handoffFrames = frames
        }
        .sheet(isPresented: $showServerSetup) {
            ServerSetupSheet(isOnboarding: true)
        }
        .sheet(isPresented: $showInviteScanner) {
            NavigationStack {
                QRCodeScanner { text in
                    handleInviteScan(text)
                }
                .ignoresSafeArea()
                .navigationTitle(L10n.t("onboarding.path.scan"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.t("common.cancel")) { showInviteScanner = false }
                    }
                }
            }
        }
        .onAppear {
            // The demo's „Eigenen Server verbinden" exit lands here — jump
            // straight to the guide page and open the server sheet, so the
            // promised action happens instead of a fresh tour.
            if appState.demoExitToSetup {
                appState.demoExitToSetup = false
                pageIndex = pages.count - 1
                showServerSetup = true
            }
            // Re-Eval Runde 2 (Befund 3): the CI matrix shoots the guide's
            // CLOSING page (`guide-ende-de`) — the NSArgumentDomain pin
            // stages it, clamped so a stale pin never points past the
            // script. Real launches carry no pin.
            if let staged = ScreenshotSeed.guidePageIndex {
                pageIndex = min(max(staged, 0), pages.count - 1)
            }
        }
    }

    private var guide: some View {
        ZStack {
            // The guide's atmosphere is the room itself: lamp cone plus
            // the quiet Tintenstaub motes (golden ink before pairing) —
            // the emoji heart rain of the generic era is gone.
            DreamyBackground()

            VStack(spacing: 0) {
                // Top bar: language switch (left) + skip (right)
                HStack {
                    languagePicker
                    Spacer()
                    if !isLastPage {
                        Button(L10n.t("onboarding.skip")) {
                            Haptics.shared.tap()
                            withAnimation(Theme.Motion.settle) { pageIndex = pages.count - 1 }
                        }
                        .font(Typo.label)
                        .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, LayoutMetrics.s(20))
                .padding(.top, LayoutMetrics.s(10))

                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        OnboardingPageView(page: page, isHero: index == 0)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Glitch-Pass (P2-B): no `.animation(value: pageIndex)` on
                // top — every programmatic page change is already wrapped in
                // `withAnimation`, and the doubled driver re-animated the
                // TabView's own gesture settle (visible double-step on fast
                // swipes). The page dots keep their own animation below.

                pageDots
                    .padding(.bottom, LayoutMetrics.s(16))

                VStack(spacing: LayoutMetrics.s(12)) {
                    if pageIndex == 0 {
                        entryPaths
                    } else {
                        Button(isLastPage ? L10n.t("onboarding.start") : L10n.t("onboarding.next")) {
                            Haptics.shared.tap()
                            if isLastPage {
                                SoundEngine.shared.play(.chime)
                                showServerSetup = true
                            } else {
                                withAnimation(Theme.Motion.settle) { pageIndex += 1 }
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        // Welle 7 [29]: „Erst mal ansehen" — the demo also
                        // waits at the end of the tour, right where the
                        // real start begins (page 1 offers it earlier).
                        if isLastPage {
                            Button(L10n.t("onboarding.demo.enter")) {
                                Haptics.shared.tap()
                                appState.enterDemo()
                            }
                            .font(Typo.label)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHint(L10n.t("onboarding.demo.enterHintA11y"))
                        }
                    }
                }
                .padding(.horizontal, LayoutMetrics.s(24))
                .padding(.bottom, LayoutMetrics.s(30))
            }
            // First impression on iPad: a centered story column, not a
            // welcome stretched across the whole window.
            .contentColumn(.reading)
        }
    }

    /// Onboarding-eval fix: the FIRST page already offers the three real
    /// ways in — scan the invitation (the partner's QR carries server AND
    /// code in one), connect a server by hand, or look around in the demo.
    /// Nobody swipes five pages before a decision is possible anymore; the
    /// tour stays one quiet tap below for those who want the story first.
    ///
    /// P2-B BALANCE DECISION (documented per MIGRATION_DUNKEL): the three
    /// ways in ARE the invitation — the cinema's finale
    /// (`CinematicArrivalStage`) lays `Papier.brief` paper faces onto
    /// exactly these frames and morphs them into these very button
    /// renderings (the scan action seals in Siegellack wax, the two
    /// side paths stay glass). Both layers draw the IDENTICAL styles,
    /// so the hand-off swap changes no pixel; the REST of the guide
    /// speaks night.
    @ViewBuilder
    private var entryPaths: some View {
        Button {
            Haptics.shared.tap()
            showInviteScanner = true
        } label: {
            Label(L10n.t("onboarding.path.scan"), systemImage: "qrcode.viewfinder")
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityIdentifier("onboarding.path.scan")
        .accessibilityHint(L10n.t("onboarding.path.scanHintA11y"))
        .cinematicHandoffAnchor(.scan)

        HStack(spacing: LayoutMetrics.s(12)) {
            Button {
                Haptics.shared.tap()
                showServerSetup = true
            } label: {
                Label(L10n.t("onboarding.path.server"), systemImage: "server.rack")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("onboarding.path.server")
            .cinematicHandoffAnchor(.server)

            Button {
                Haptics.shared.tap()
                appState.enterDemo()
            } label: {
                Label(L10n.t("onboarding.demo.enter"), systemImage: "sparkles")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("onboarding.path.demo")
            .accessibilityHint(L10n.t("onboarding.demo.enterHintA11y"))
            .cinematicHandoffAnchor(.demo)
        }

        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) { pageIndex += 1 }
        } label: {
            HStack(spacing: 6) {
                Text(L10n.t("onboarding.path.tour"))
                Image(systemName: "chevron.right")
            }
            .font(Typo.label)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 2)

        // W8D: rewatch the first-launch cinematic — right where the intro
        // just faded into the guide.
        Button(L10n.t("cinematic.replay")) {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.arrive) { replayCinematic = true }
        }
        .font(Typo.label)
        .foregroundStyle(Theme.textTertiary)
        .accessibilityHint(L10n.t("cinematic.a11y"))
    }

    /// One scan, one step: an invitation QR carries server + couple code —
    /// activate the server (the phase flips to pairing by itself) and park
    /// the code for PairingView, which starts in join mode with it. Device
    /// hand-off and rejoin QRs complete themselves via their AppState paths.
    private func handleInviteScan(_ text: String) {
        showInviteScanner = false
        if let link = DeviceLinkURL.parse(text) {
            Haptics.shared.success()
            appState.applyDeviceLink(link)
            return
        }
        if let link = RejoinLink.parse(text) {
            Haptics.shared.success()
            appState.applyRejoinLink(link)
            return
        }
        if let payload = PairQRPayload.decode(text) {
            PendingInvite.store(code: payload.code)
            if let normalized = ServerProfile.normalize(payload.server) {
                Haptics.shared.success()
                if let existing = appState.servers.profiles.first(
                    where: { $0.urlString == normalized }) {
                    appState.servers.setActive(id: existing.id)
                } else if let profile = appState.servers.add(name: normalized,
                                                             urlString: normalized) {
                    appState.servers.setActive(id: profile.id)
                }
            } else {
                // Payload without a usable server: the code is parked; the
                // person only adds the server, the code fills itself in.
                appState.showToast(L10n.t("onboarding.invite.needServer"), style: .info)
                showServerSetup = true
            }
            return
        }
        // A bare couple code (older invites): park it and walk straight to
        // the server step — nothing gets typed twice.
        let code = RecoveryKit.normalizedCode(text, length: RecoveryKit.pairingCodeLength)
        guard code.count == RecoveryKit.pairingCodeLength else {
            appState.showToast(L10n.t("onboarding.invite.unrecognized"), style: .error)
            return
        }
        PendingInvite.store(code: code)
        Haptics.shared.success()
        appState.showToast(L10n.t("onboarding.invite.needServer"), style: .info)
        showServerSetup = true
    }

    private var pageDots: some View {
        HStack(spacing: Space.s) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex
                          ? AnyShapeStyle(Theme.heroGradient)
                          : AnyShapeStyle(Theme.hairline))
                    .frame(width: index == pageIndex ? LayoutMetrics.s(26) : LayoutMetrics.s(8),
                           height: LayoutMetrics.s(8))
                    .animation(Theme.Motion.settle, value: pageIndex)
            }
        }
        .accessibilityLabel(L10n.t("onboarding.pageA11y",
                                   ["current": String(pageIndex + 1), "total": String(pages.count)]))
    }

    private var languagePicker: some View {
        HStack(spacing: Space.s) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    L10n.language = lang
                    CinematicIntroGate.markLanguageChosen()
                    appState.uiRefresh += 1
                }                 label: {
                    Text(L10n.t(lang.displayNameKey))
                        .font(Typo.caption)
                        // Nacht-first (P2-B): the resting chip is quiet
                        // night chrome — the active chip is the SOLID
                        // couple-blend platter with its machine-judged
                        // `onBlend` ink (golden ink pre-pairing), so the
                        // label clears the floor on every blend.
                        .foregroundStyle(L10n.language == lang
                                         ? coupleTint.onBlend : Theme.textSecondary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .background(
                            Capsule().fill(L10n.language == lang
                                           ? AnyShapeStyle(coupleTint.blend)
                                           : AnyShapeStyle(Papier.nachtInnenFill))
                                .overlay(
                                    Capsule().strokeBorder(Nacht.naht,
                                                           lineWidth: Theme.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// One onboarding page: material hero artifact (or SF-Symbol vignette) +
/// title + body, and (non-hero pages) a night card listing the page's
/// feature rows.
private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isHero: Bool

    @Environment(\.coupleTint) private var coupleTint

    /// Feature-row tints, indexed by the script's `tint` role — the couple's
    /// own INKS first (the glyphs sit on the paper Briefmarke insets; raw
    /// member colors and lampengold fail the paper floor), then ink and
    /// stamp red.
    private var tints: [Color] {
        [coupleTint.tintePrimary, Tinte.dunkel, coupleTint.tinteSecondary, Wachs.rot]
    }

    @State private var floating = false
    @Environment(\.motionGate) private var motionGate

    var body: some View {
        // Fix4 Befund 1a: the page grows intrinsically and SCROLLS when
        // the room is shorter than the letter (large Dynamic Type, small
        // phones) — the guide-ende card used to clip its closing lines
        // („warten sc…") against the fixed TabView height. When the
        // content fits, minHeight keeps the classic centered composition
        // and the scroll never bounces.
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                pageContent
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var pageContent: some View {
        VStack(spacing: 0) {
            Spacer()

            // Re-Eval Runde 2 (S1): the 84-pt purple emoji heart after the
            // wax/letter/polaroid chain broke the brand. The hero shows the
            // MATERIAL artifact — a sealed letter built from the existing
            // Briefbogen + WachsSiegel building blocks; the tour pages get
            // a small SF-Symbol vignette in couple ink on a paper stamp.
            Group {
                if isHero {
                    sealedLetter
                } else {
                    pageVignette
                }
            }
            .offset(y: floating ? -7 : 7)
            // Ornamental endless float — gated: under Reduce Motion the
            // artifact simply rests at its lifted position (MotionGate).
            .animation(motionGate.ambient(
                Theme.Motion.drift(2.4).repeatForever(autoreverses: true)),
                       value: floating)
            .padding(.bottom, LayoutMetrics.s(18))
            .onAppear { floating = true }
            .accessibilityHidden(true)

            if isHero {
                // The hero wordmark is the finale's first landing rect —
                // the cinema's title rises exactly onto this frame. It
                // is also the page's HEADING (Fix-Runde 3, Kino-Befund
                // 4): VoiceOver's heading rotor must find it.
                Text(L10n.t(page.titleKey))
                    .brandTitle()
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .cinematicHandoffAnchor(.wordmark)
            } else {
                Text(L10n.t(page.titleKey))
                    .font(Typo.hero)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(24))
            }

            Text(L10n.t(page.bodyKey))
                .font(Typo.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, LayoutMetrics.s(36))
                .padding(.top, LayoutMetrics.s(10))

            if page.id == "guide" {
                // Fix4 Befund 1b: the closing page is ONE Zustellroute,
                // not a numbered form — see `zustellroute` below.
                zustellroute
                    .nightCard(padding: .hero)
                    .padding(.horizontal, LayoutMetrics.s(24))
                    .padding(.top, LayoutMetrics.s(26))
            } else if !page.features.isEmpty {
                // Weiß-Audit verdict (MIGRATION_DUNKEL §10, N4): the tour
                // NARRATES the app — it is no possession-paper the couple
                // writes or keeps, so the feature list speaks night; each
                // row keeps its rank through a stamp-sized paper Briefmarke
                // around its glyph instead of a full letter pane.
                VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                    ForEach(Array(page.features.enumerated()), id: \.offset) { _, feature in
                        featureRow(feature.icon, feature.textKey,
                                   tints[feature.tint % tints.count])
                    }
                }
                .nightCard(padding: .hero)
                .padding(.horizontal, LayoutMetrics.s(24))
                .padding(.top, LayoutMetrics.s(26))
            }

            Spacer()
        }
    }

    // MARK: The guide's Zustellroute (Fix4 Befund 1b)

    /// The route dot: a small letter-paper stop under the lamp — the
    /// same direct sheet grammar as the sealed letter above (Papier.brief
    /// fill + light edge), no new material.
    private var routeDot: CGFloat { LayoutMetrics.s(12) }

    /// The three closing steps compose as ONE connected delivery route:
    /// paper stop-points stitched by a quiet night seam, the reading
    /// order IS the route order — no 1/2/3 stamps (the script's numbered
    /// icons stay pinned as route-order data, the composition replaces
    /// their rendering). The second device rides below as a smaller,
    /// subordinate clause off the route, not a fourth station.
    private var zustellroute: some View {
        let stops = Array(page.features.prefix(3))
        let link = page.features.count > 3 ? page.features[3] : nil
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                routeStop(textKey: stop.textKey, isLast: index == stops.count - 1)
            }
            if let link {
                routeLinkRow(icon: link.icon, textKey: link.textKey)
            }
        }
    }

    /// One stop on the route; every stop but the last continues the seam
    /// down to its successor (drawn in the row's own background, so the
    /// line always spans exactly the text's grown height — AX included).
    private func routeStop(textKey: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Circle()
                .fill(Papier.brief)
                .overlay(Circle().strokeBorder(PaperLightEdge.gradient,
                                               lineWidth: Theme.hairlineWidth))
                .frame(width: routeDot, height: routeDot)
                .padding(.top, LayoutMetrics.s(3))
            Text(L10n.t(textKey))
                .font(Typo.body)
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, isLast ? 0 : LayoutMetrics.s(14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(Nacht.naht)
                    .frame(width: LayoutMetrics.s(2))
                    .padding(.leading, (routeDot - LayoutMetrics.s(2)) / 2)
                    .padding(.top, routeDot + LayoutMetrics.s(3))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The Zweitgerät clause: a quiet footnote hanging off the route —
    /// smaller voice, tertiary glyph, clearly not a station.
    private func routeLinkRow(icon: String, textKey: String) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: icon)
                .font(Typo.caption)
                .foregroundStyle(Nacht.tertiaer)
                .frame(width: routeDot)
                .padding(.top, LayoutMetrics.s(2))
                .accessibilityHidden(true)
            Text(L10n.t(textKey))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LayoutMetrics.s(14))
    }

    /// The hero artifact: the WachsSiegel-über-Briefbogen motif from the
    /// Kino/About family — a small letter sheet with quiet ink address
    /// lines, sealed with the app's material wax seal. The sheet is drawn
    /// in the CINEMA's own grammar (direct `Papier.brief` fill + light
    /// edge + resting shadow, like `CinematicEnvelopeStage`'s envelope),
    /// tilted via the seeded `paperTilt` token; decorative, so the whole
    /// group is hidden from VoiceOver above.
    private var sealedLetter: some View {
        let sheet = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        return VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            // Address lines in faded ink — the letter is addressed to the
            // couple, not readable copy (same mechanic as the freeze-frame
            // letter sheets).
            Capsule().fill(Tinte.dunkel.opacity(0.34))
                .frame(width: LayoutMetrics.s(96), height: LayoutMetrics.s(3))
            Capsule().fill(Tinte.dunkel.opacity(0.26))
                .frame(width: LayoutMetrics.s(66), height: LayoutMetrics.s(3))
            Capsule().fill(coupleTint.tintePrimary.opacity(0.55))
                .frame(width: LayoutMetrics.s(80), height: LayoutMetrics.s(3))
        }
        .frame(width: LayoutMetrics.s(128), alignment: .leading)
        .padding(Space.l)
        .background(
            sheet.fill(Papier.brief)
                .overlay(sheet.strokeBorder(PaperLightEdge.gradient,
                                            lineWidth: Theme.hairlineWidth))
                .elevation(.resting))
        .paperTilt(seed: 0x4F4E_4253_4945_474C) // "ONBSIEGL" — the page's one tilt
        .overlay(alignment: .bottomTrailing) {
            WachsSiegel(size: LayoutMetrics.s(52),
                        emboss: .system(.body, design: .rounded).weight(.bold))
                .offset(x: LayoutMetrics.s(10), y: LayoutMetrics.s(12))
        }
        .padding(.trailing, LayoutMetrics.s(10))
        .padding(.bottom, LayoutMetrics.s(12))
    }

    /// Non-hero pages: a small SF-Symbol vignette in couple ink on the
    /// stamp-sized paper inset — the feature rows' Briefmarke mechanic,
    /// one size up (commandment 1: symbols, never emoji). Drawn in the
    /// same direct sheet grammar; the symbol wears a Dynamic-Type text
    /// style, never a fixed point size.
    private var pageVignette: some View {
        let stamp = RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
        return Image(systemName: page.symbol ?? "seal")
            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(coupleTint.tintePrimary)
            .frame(width: LayoutMetrics.s(56), height: LayoutMetrics.s(56))
            .padding(Space.m)
            .background(
                stamp.fill(Papier.polaroid)
                    .overlay(stamp.strokeBorder(PaperLightEdge.gradient,
                                                lineWidth: Theme.hairlineWidth))
                    .elevation(.resting))
            .paperTilt(seed: 0x4F4E_424D_4152_4B45) // "ONBMARKE" — the page's one tilt
    }

    private func featureRow(_ icon: String, _ key: String, _ tint: Color) -> some View {
        HStack(spacing: Space.m) {
            // The Briefmarke: the feature glyph in couple ink on a
            // stamp-sized bright paper inset (`paperCard(.polaroid)`
            // mechanic, PlayHub-hero pattern) — the ink tints still sit
            // on paper, only the pane around them turned night.
            Image(systemName: icon)
                .font(Typo.label)
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                .paperCard(.polaroid, padding: .compact, grain: false)
            Text(L10n.t(key))
                .font(Typo.body)
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Add/edit a server with live connection testing.
/// Used from onboarding and from Settings → Manage servers.
struct ServerSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var isOnboarding = false
    var existing: ServerProfile? = nil

    @State private var name = ""
    @State private var urlString = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(18)) {
                        Text(L10n.t("server.setupSubtitle"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        // Nacht-first (P2-B): the address fields are a
                        // STANDARD sheet card, not a hero artifact — the
                        // one briefbogen of the flow is the tour's feature
                        // list. Night card + the matte night wells
                        // (MIGRATION_DUNKEL §3/§4: paperField → Dreamy).
                        VStack(spacing: LayoutMetrics.s(12)) {
                            TextField(L10n.t("server.name"), text: $name)
                                .textFieldStyle(DreamyFieldStyle())
                            TextField(L10n.t("server.url"), text: $urlString)
                                .textFieldStyle(DreamyFieldStyle())
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .accessibilityIdentifier("server.urlField")
                        }
                        .nightCard(padding: .compact)

                        if let result = testResult {
                            HStack(spacing: 8) {
                                // Night-card inks (§4): success speaks in
                                // lamplight, failure in the glut accent —
                                // wax stays material on paper only.
                                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.ok ? Licht.lampengold : Licht.glut)
                                Text(result.text)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Nacht.sekundaer)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .nightCard(padding: .compact)
                        }

                        Button {
                            Task { await test() }
                        } label: {
                            if testing {
                                ProgressView().tint(.white)
                            } else {
                                Label(L10n.t("server.test"), systemImage: "bolt.horizontal.fill")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(testing || normalized == nil)
                        .accessibilityIdentifier("server.testButton")

                        Button(isOnboarding ? L10n.t("server.continue") : L10n.t("common.save")) {
                            save()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(normalized == nil)
                        .accessibilityIdentifier("server.saveButton")

                        Text(L10n.t("server.buildBadge", ["version": appVersionLabel]))
                            .font(Typo.caption)
                            .foregroundStyle(Theme.mint)
                            .padding(.top, 4)

                        Text(L10n.t("server.hint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t(existing == nil ? "server.add" : "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let existing {
                name = existing.name
                urlString = existing.urlString
            }
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var normalized: String? {
        ServerProfile.normalize(urlString)
    }

    private func test() async {
        guard let normalized, let url = URL(string: normalized) else {
            testResult = (false, L10n.t("server.invalidURL"))
            return
        }
        testing = true
        defer { testing = false }
        do {
            let health = try await API(baseURL: url, token: nil).health()
            testResult = (true, L10n.t("server.testOK", ["name": health.name, "version": health.version]))
            Haptics.shared.success()
        } catch {
            let raw = error.localizedDescription
            let looksLikeATS = raw.localizedCaseInsensitiveContains("App Transport Security")
                || raw.localizedCaseInsensitiveContains("secure connection")
            if looksLikeATS {
                testResult = (false, L10n.t("server.testFailATS"))
            } else {
                testResult = (false, L10n.t("server.testFail", ["error": raw]))
            }
            Haptics.shared.warning()
        }
    }

    private func save() {
        guard let normalized else { return }
        if var existing {
            existing.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? normalized : name
            existing.urlString = normalized
            appState.servers.update(existing)
        } else if let profile = appState.servers.add(name: name, urlString: normalized) {
            appState.servers.setActive(id: profile.id)
        }
        Haptics.shared.success()
        dismiss()
    }
}

/// The NACHT-CHROME-INPUT (MIGRATION_DUNKEL §4: `paperField()` is the ink
/// well ON paper, `DreamyFieldStyle` is its night twin): a dark matte well
/// for fields that sit on the night room or on `nightCard()`s. P2-B fix:
/// the legacy fill went through `Theme.card`, which the paper wave aliased
/// to BRIGHT letter paper — near-white `Theme.textPrimary` on brief was
/// unreadable in every remaining call site (Home sheets, server setup).
/// The well is the room anchor now: aufNacht reads 15.7:1 on zimmerOben
/// (pinned), and on a nightcard the darker recess stays distinct.
struct DreamyFieldStyle: TextFieldStyle {
    var font: Font = Typo.body

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return configuration
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            .tint(Licht.lampengold)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, LayoutMetrics.s(16))
            .background(
                // Matte night well — inner depth without rebuilding glass
                // next to the system material (EVAL P1-8).
                shape.fill(Papier.zimmerOben
                    .shadow(.inner(color: .black.opacity(0.25), radius: 5, y: 2)))
                    .overlay(shape.strokeBorder(Theme.hairline,
                                                lineWidth: Theme.hairlineWidth))
            )
    }
}
