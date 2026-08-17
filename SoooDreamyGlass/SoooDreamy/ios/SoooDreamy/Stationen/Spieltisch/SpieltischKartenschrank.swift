import SwiftUI

// Zonen „Kartenschrank" + „Spielbuch" des Spieltischs (NEUBAU_ENTSCHEID
// §4.3, NEUBAU_POSTAMT §3.3): die Fach-Kopfzeilen und Spielbuch-Zeilen
// tragen Adoption A1 — das Kapitelverzeichnis mit Punktlinien-Seitenzahl
// („Fernpartien ····· 34", Zahl = gespielte Partien) — und die Spiele
// liegen als Spielkarten-Umschläge im Schrank. Die Fach-Zuordnung selbst
// ist PURE (`Content/KartenschrankRules.swift`, Linux-gepinnt); hier lebt
// nur die Optik. Signature „Lasche auf": Spielstart klappt die Dreiecks-
// Lasche des Umschlags per `rotation3DEffect` um die Oberkante auf.

// MARK: - Signature „Lasche auf" (ENTSCHEID §4.3)

/// Choreography parameters of the flap signature, local to the station —
/// Theme ist nicht N3-Hoheit, deshalb leben die Werte hier (dieselbe
/// Mechanik-Familie wie `Signature.blaettern*`: rotation3DEffect um eine
/// Kante, Perspektive 0.3).
enum SpieltischLasche {
    /// The flap swings from closed to wide open around its top edge.
    static let aufDegrees: Double = -150
    static let perspektive: CGFloat = 0.3
    /// Head start the flap gets before the board "blätters" in behind it
    /// — long enough to read as cause, short enough to stay an answer in
    /// the tap frame's family.
    static let aufdauer: TimeInterval = 0.32
    /// The dry rigid tick in the flip-open frame. Rides the ONE cue lane
    /// via `hapticOverride` on the catalog's tear cue (`.unseal`) —
    /// scheduling and quiet hours stay exactly the cue's.
    static let haptik = [HapticEventSpec(t: 0.00, i: 0.75, s: 0.95)]
    /// Height of the triangular flap at rest.
    static var hoehe: CGFloat { LayoutMetrics.s(20) }
}

// MARK: - Adoption A1: the register line („{Titel} ····· {n}")

/// The horizontal dotted leader between chapter title and page number —
/// a shape so the dots stretch to whatever room the line has; the shape's
/// baseline (its bottom edge) sits on the text baseline like a classic
/// table-of-contents leader. The literal compact form lives as a pure
/// function in `KartenschrankRules.punktzeile` (pinned by the LogicTests).
struct PunktLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// One A1 register line: chapter title in rounded Kapitälchen
/// (`Typo.caption` + uppercase — the DateIdeas filter-label precedent),
/// the dotted leader, and the honest count in `Typo.number`. These lines
/// lie on NIGHT cards, and serif — including the `Typo.anschrift`
/// small-caps role — appears ONLY on paper (Fix-Runde 3, Befund 11); the
/// uppercase keeps the register character without new smallcaps outside
/// the Typo API. On night the title speaks lamplight (SoundCredits
/// precedent), the number is primary night ink — pure typography, zero
/// artifact budget. `untergrenze` renders the count as „{n}+": an
/// aggregate seeded from an already-capped store is an honest floor,
/// never an exact total (Befund 6).
struct PunktlinienZeile: View {
    let titel: String
    let zahl: Int
    var untergrenze = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(titel)
                .font(Typo.caption)
                .textCase(.uppercase)
                .foregroundStyle(Licht.lampengold)
                .lineLimit(1)
                .layoutPriority(1)
            PunktLeader()
                .stroke(Nacht.tertiaer,
                        style: StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                           dash: [0.01, 5]))
                .frame(height: 1.4)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            Text(untergrenze ? "\(zahl)+" : "\(zahl)")
                .font(Typo.number)
                .monospacedDigit()
                .foregroundStyle(Papier.aufNacht)
                .layoutPriority(1)
        }
    }
}

/// The tappable drawer header of the Kartenschrank: the A1 line plus the
/// fold chevron that keeps the collapsed state honest. The carrying
/// Button in PlayHubView adds label/value for VoiceOver.
struct KartenschrankFachKopf: View {
    let titel: String
    let partien: Int
    var untergrenze = false
    let eingeklappt: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            PunktlinienZeile(titel: titel, zahl: partien, untergrenze: untergrenze)
            Image(systemName: eingeklappt ? "chevron.right" : "chevron.down")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.tertiaer)
                .accessibilityHidden(true)
        }
        .nightCard(padding: .compact, grain: false)
    }
}

/// One Spielbuch entry (Turnier · Siegerliste · Wiederholungen ·
/// Anleitungen) — the SAME register-line anatomy as the drawer headers
/// (ENTSCHEID A1), pushing its `GameDestination` instead of folding.
struct SpielbuchZeile: View {
    let titel: String
    let zahl: Int
    var untergrenze = false
    let oeffnen: () -> Void

    var body: some View {
        Button(action: oeffnen) {
            HStack(spacing: Space.s) {
                PunktlinienZeile(titel: titel, zahl: zahl, untergrenze: untergrenze)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .accessibilityHidden(true)
            }
            .nightCard(padding: .compact, grain: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titel)
        // The floor speaks honestly too: „mindestens {n}" (Befund 6).
        .accessibilityValue(untergrenze
                            ? L10n.t("games.zahl.floor.a11y", ["n": "\(zahl)"])
                            : "\(zahl)")
    }
}

// MARK: - Spielkarten-Umschlag (the envelope game card)

/// The triangular envelope flap: an open V from the top corners down to
/// the center apex — a stroked path overlay in `Papier.kante` (edge
/// MATERIAL, not a paper surface; artifact budgets untouched).
struct LascheShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// One game of the cabinet as a Spielkarten-Umschlag (nacht-first index
/// card + the flap fold on its top edge; Fernpartien additionally carry
/// the anschrift line „Für {Partner}" — a correspondence round is
/// addressed post). Tapping runs the „Lasche auf" signature and then
/// hands over to `starten` (the hub pushes the destination — the board
/// "blätters" in behind the opened flap). Reduce Motion: the flap stays
/// still, the board arrives by crossfade + Lichtschein.
struct UmschlagKarte: View {
    let destination: GameDestination
    /// The address line — only Fernpartien envelopes are addressed.
    var anschrift: String?
    var multiplayer = true
    let starten: () -> Void

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lascheOffen = false
    /// Shared start guard of BOTH aufklappen paths (re-eval 2, Befund 12):
    /// the Reduce-Motion branch used to bypass the task choreography and
    /// start synchronously on EVERY tap — a double-tap navigated twice.
    /// Armed on the first tap, reset when the card reappears (back from
    /// the board) or the mid-flight task is cancelled.
    @State private var startetGerade = false
    /// „Lasche auf" choreography, BOUND to the card (ChatPult draft-task
    /// pattern): held in @State and cancelled on disappear, so a recycled
    /// LazyVGrid cell never keeps a ghost task that pushes a destination
    /// after the card is gone.
    @State private var startTask: Task<Void, Never>?

    var body: some View {
        Button {
            aufklappen()
        } label: {
            inhalt
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .onAppear {
            lascheOffen = false
            startetGerade = false
        }
        .onDisappear {
            startTask?.cancel()
            startTask = nil
            startetGerade = false
        }
    }

    // MARK: Signature „Lasche auf"

    private func aufklappen() {
        // ONE start per visible card, in BOTH motion worlds — the second
        // tap of a double-tap bounces off here instead of pushing the
        // destination twice.
        guard !startetGerade else { return }
        startetGerade = true
        // ONE cue lane for the start moment: the catalog's tear tick, its
        // generic twin swapped for the dry rigid stitch of the flap frame.
        // No extra Haptics.tap() — the cue's twin IS the haptic.
        CueKit.play(.unseal, hapticOverride: SpieltischLasche.haptik)
        // What sighted players SEE begin, VoiceOver players hear begin.
        GamesA11y.announce(L10n.t("games.lasche.beginnt", ["game": titel]))
        if reduceMotion {
            // Direct transition: no flap swing — crossfade + Lichtschein
            // (the app-wide host in RootView draws the glow).
            GameLichtscheinCenter.shared.fire()
            starten()
            return
        }
        withAnimation(Theme.Motion.settle) { lascheOffen = true }
        startTask?.cancel()
        startTask = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(SpieltischLasche.aufdauer * 1_000_000_000))
            guard !Task.isCancelled else { return }
            starten()
            // Close the envelope again while the pushed board covers the
            // hub — coming back, the card rests sealed like its siblings
            // (onAppear also resets, for the cancelled-mid-flight case).
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            lascheOffen = false
            startetGerade = false
        }
    }

    // MARK: Painting

    private var titel: String {
        L10n.t("games.card.\(destination.rawValue).title")
    }

    private var symbol: String {
        if let kind = GameKind(rawValue: destination.rawValue) {
            return PlayHubView.gameSymbol(for: kind)
        }
        // The one drawer destination without a session engine keeps its
        // established hub glyph.
        return destination == .dateideas ? "wand.and.stars" : "dice.fill"
    }

    /// True once the hub grid has collapsed to ONE column (AX3+, rule in
    /// `AccessibilityBudget.gridColumns`): the card owns the full row, so
    /// every lineLimit lifts and labels wrap in natural size instead of
    /// truncating or downscaling (MemoriesView AX5 pattern).
    private var einspaltig: Bool {
        dynamicTypeSize.gridColumns(regular: 2) == 1
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Image(systemName: symbol)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Licht.lampengold)
                .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                .background(
                    Circle().fill(Papier.nachtInnenFill)
                        .overlay(Circle().strokeBorder(Nacht.naht,
                                                       lineWidth: Theme.hairlineWidth))
                )
                .accessibilityHidden(true)
            if let anschrift {
                // The address line on the NIGHT envelope: rounded
                // Kapitälchen instead of the serif anschrift role —
                // serif appears only on paper (Fix-Runde 3, Befund 11).
                Text(anschrift)
                    .font(Typo.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(Nacht.tertiaer)
                    .lineLimit(einspaltig ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(titel)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .lineLimit(einspaltig ? nil : 2)
                .minimumScaleFactor(einspaltig ? 1 : 0.85)
            Text(L10n.t("games.card.\(destination.rawValue).teaser"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(einspaltig ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            PillTag(text: L10n.t(multiplayer ? "games.badge.multiplayer"
                                             : "games.badge.local"),
                    tint: multiplayer ? coupleTint.blend : Licht.glut)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(172),
               alignment: .topLeading)
        .nightCard()
        .overlay(alignment: .top) { lasche }
    }

    /// The flap fold on the top edge — a stroked V in edge material. It
    /// swings around the top edge (x-axis, `anchor: .top`, perspective
    /// 0.3 — the blaettern mechanics family) when the round starts.
    private var lasche: some View {
        LascheShape()
            .stroke(Papier.kante.opacity(0.6),
                    style: StrokeStyle(lineWidth: Theme.hairlineWidth * 2,
                                       lineCap: .round, lineJoin: .round))
            .frame(height: SpieltischLasche.hoehe)
            .padding(.horizontal, LayoutMetrics.s(18))
            .rotation3DEffect(
                .degrees(lascheOffen ? SpieltischLasche.aufDegrees : 0),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: SpieltischLasche.perspektive)
            .allowsHitTesting(false)
            // Decorative fold — the card itself announces the game.
            .accessibilityHidden(true)
    }
}
