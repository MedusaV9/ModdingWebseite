import SwiftUI

// Adoption A2 „Polaroid entwickeln" (ENTSCHEID §1.2, übernommen aus dem
// Zimmerhaus-Dossier §3.5): Press-and-hold entwickelt das milchige
// „Heute vor …"-Polaroid radial unterm Daumen — sechs weiche Haptik-Ticks
// im Crescendo, Loslassen milcht zurück, am Ende Stille statt Konfetti.
// Reduce Motion / VoiceOver: ein einzelner Tap bzw. die benannte
// AX-Aktion entwickelt sofort. Foto-Papier-Physik, kein Feature-Gate:
// die Erinnerung liegt so oder so im Fach.
//
// Lokal in der Postfach-Station (Datei-Hoheit N2); die Archiv-Welle
// übernimmt denselben benannten Modifier später für PotdView.
// Kollisions-Regel (§1.2): der Briefschlitz feuert nur beim Rundenbeginn,
// das Entwickeln ist nutzer-initiiert — zwei leise Momente, nie gleichzeitig.

struct PolaroidEntwickeln: ViewModifier {
    /// Developed state — the parent persists it (per dateKey), so one held
    /// development carries the whole day instead of re-milking per scroll.
    @Binding var entwickelt: Bool
    /// Full VoiceOver sentence, announced when the picture appears:
    /// „Heute vor {n} Jahren: {Titel}" (wörtlich aus dem Dossier).
    var ansage: String
    /// Name of the AX develop action ("Foto entwickeln").
    var aktionsTitel: String
    /// The quiet hold hint printed on the milky paper.
    var hinweis: String
    /// The Reduce-Motion hint ("Antippen zum Entwickeln") — under RM a
    /// single TAP develops, so the printed line and the VoiceOver hint
    /// must never claim "Halten…" (re-eval №8).
    var hinweisTippen: String

    @Environment(\.motionGate) private var motionGate
    /// 0 = milky photo paper, 1 = developed — drives the radial reveal.
    @State private var fortschritt: CGFloat = 0
    /// Where the thumb rests — the development blooms under it.
    @State private var daumen: CGPoint?
    /// The running development; cancelled the moment the thumb lifts.
    @State private var entwicklung: Task<Void, Never>?

    /// Development time and the six crescendo ticks that fill it.
    private static let dauer: TimeInterval = 1.6
    private static let ticks = 6

    func body(content: Content) -> some View {
        let basis = Group {
            if motionGate.reduceMotion {
                // Reduce Motion: a single tap develops instantly — the
                // waiting gesture is choreography, never a gate.
                grundkoerper(content)
                    .onTapGesture { sofortEntwickeln() }
            } else {
                grundkoerper(content)
                    .gesture(halteGeste)
            }
        }
        .accessibilityElement(children: .ignore)

        // Re-eval №8: undeveloped, the polaroid IS a button — the VoiceOver
        // DEFAULT activation develops (no rotor detour), the trait says so,
        // and the hint tells the honest gesture (tap under Reduce Motion,
        // hold otherwise — VO's double-tap always just develops). Once
        // developed, action, trait and hint disappear: a picture, not a
        // dead control.
        return Group {
            if entwickelt {
                basis.accessibilityLabel(ansage)
            } else {
                basis
                    .accessibilityLabel(aktionsTitel)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(hinweisTippen)
                    .accessibilityAction { sofortEntwickeln() }
            }
        }
    }

    private func grundkoerper(_ content: Content) -> some View {
        content
            .overlay {
                if !entwickelt {
                    milchschicht
                }
            }
            .contentShape(Rectangle())
    }

    /// The undeveloped photo paper: a milky polaroid veil that thins
    /// radially under the thumb while the picture develops — feathered
    /// rim, so the chemistry blooms instead of punching a hole.
    private var milchschicht: some View {
        GeometryReader { geo in
            let mitte = daumen
                ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            // 1.5 × the longer edge always covers the far corner — the
            // bloom finishes fully developed wherever the thumb rests.
            let radius = max(max(geo.size.width, geo.size.height) * 1.5 * fortschritt,
                             0.1)
            Rectangle()
                .fill(Papier.polaroid.opacity(0.94))
                .overlay {
                    if fortschritt == 0 {
                        hinweisZeile
                    }
                }
                .mask {
                    ZStack {
                        Rectangle()
                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [.init(color: .black, location: 0.65),
                                            .init(color: .clear, location: 1)],
                                    center: .center,
                                    startRadius: 0, endRadius: radius)
                            )
                            .frame(width: radius * 2, height: radius * 2)
                            .position(mitte)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The hint speaks quiet ink on the milky paper — no button, the
    /// whole photo is the darkroom. Reduce Motion prints the honest tap
    /// line instead of the hold line (re-eval №8).
    private var hinweisZeile: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: "hand.tap")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.tertiaer)
                .accessibilityHidden(true)
            Text(motionGate.reduceMotion ? hinweisTippen : hinweis)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
        }
        .padding(Space.m)
    }

    // MARK: Halten & Loslassen

    private var halteGeste: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { wert in
                daumen = wert.location
                entwicklungBeginnen()
            }
            .onEnded { _ in daumenGehoben() }
    }

    private func entwicklungBeginnen() {
        guard entwicklung == nil, !entwickelt else { return }
        // drift carries the chemistry: one slow token curve, no free-hand
        // easing (Gebot 11).
        withAnimation(Theme.Motion.drift(Self.dauer)) { fortschritt = 1 }
        entwicklung = Task {
            let schritt = UInt64(Self.dauer / Double(Self.ticks) * 1_000_000_000)
            for tick in 0..<Self.ticks {
                // Choreography pause between the crescendo ticks.
                try? await Task.sleep(nanoseconds: schritt)
                guard !Task.isCancelled else { return }
                Haptics.shared.composerTick(intensity: 0.25 + Double(tick) * 0.12)
            }
            guard !Task.isCancelled else { return }
            // Developed — and silence instead of confetti (A2).
            entwickelt = true
            entwicklung = nil
            AccessibilityNotification.Announcement(ansage).post()
        }
    }

    private func daumenGehoben() {
        guard !entwickelt else { return }
        // Loslassen milcht zurück — photo paper is honest physics.
        entwicklung?.cancel()
        entwicklung = nil
        withAnimation(Theme.Motion.settle) { fortschritt = 0 }
    }

    private func sofortEntwickeln() {
        guard !entwickelt else { return }
        Haptics.shared.tap()
        fortschritt = 1
        entwickelt = true
        AccessibilityNotification.Announcement(ansage).post()
    }
}

extension View {
    /// A2 „Polaroid entwickeln": hold until the picture appears — radial
    /// development under the thumb, haptic crescendo, release milks back;
    /// Reduce Motion / VoiceOver develop instantly (their hint is the
    /// honest `hinweisTippen`).
    func polaroidEntwickeln(entwickelt: Binding<Bool>, ansage: String,
                            aktionsTitel: String, hinweis: String,
                            hinweisTippen: String) -> some View {
        modifier(PolaroidEntwickeln(entwickelt: entwickelt, ansage: ansage,
                                    aktionsTitel: aktionsTitel, hinweis: hinweis,
                                    hinweisTippen: hinweisTippen))
    }
}
