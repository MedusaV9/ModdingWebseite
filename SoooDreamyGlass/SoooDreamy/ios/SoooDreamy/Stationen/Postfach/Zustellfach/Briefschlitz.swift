import SwiftUI

// Der Briefschlitz — der Signature-Moment der Postfach-Station (ENTSCHEID
// §4.1/§4.6): beim ersten Vordergrund-Eintritt einer neuen Zustellrunde
// gleitet der Hero durch die 1-pt-`Nacht.naht`-Hairline ins Fach (arrive-
// Alias), Haptik `tap` + trockener rigid-Tick beim Aufliegen, Klang das
// papierene Flap (`swish`). VoiceOver bekommt den ganzen Satz („Tagespost
// ist da: Frage des Tages."); Reduce Motion legt die Karte sofort und
// lässt den statischen Lichtschein den Moment tragen (MotionGate, Gebot 13).
//
// Lokal in der Postfach-Station (Datei-Hoheit N2): der Modifier konsumiert
// ausschließlich benannte Theme-Tokens — die Naht ist Architektur des
// Zustellfachs und steht auch in Ruhe über dem Hero, nur die Choreografie
// spielt EINMAL pro Runde und Gerät (Ein-Marken-Modell, ZustellrundenLogic).
//
// Re-Eval №1: die Choreo hängt an der Runden-MARKE (`.task(id: marke)`),
// nicht mehr an onAppear — wechselt die Runde im SICHTBAREN Tab, setzt die
// neue Marke die Bühne zurück und inszeniert neu; Re-Appears derselben
// Runde (Tab-Wechsel) spielen weiterhin nie doppelt. №13: der 480-ms-Tick
// lebt im selben strukturierten Task — Verschwinden oder eine neue Marke
// cancelt ihn mit (kein Streuner-Task überlebt den Blickwechsel).

struct BriefschlitzEntry: ViewModifier {
    /// Die Runden-Marke „{dateKey}#{runde}" (ZustellrundenLogic.marke) —
    /// die Identität der Inszenierung: gleiche Marke spielt nie erneut,
    /// eine NEUE Marke im sichtbaren Tab setzt die Bühne zurück.
    var marke: String
    /// True genau dann, wenn diese Runde auf diesem Gerät noch nicht
    /// inszeniert wurde — der Auftritt wird beim Bühnenstart eingefroren,
    /// damit ein später kippendes Flag nie mitten im Blick die
    /// Choreografie wechselt.
    var inszeniert: Bool
    /// Ganzer VoiceOver-Satz der Runde („Tagespost ist da: {Titel}.").
    var ansage: String
    /// Schreibt die Marke, sobald die Inszenierung tatsächlich spielt —
    /// nie beim bloßen Berechnen (Bühne, nie Gate).
    var onGespielt: () -> Void

    @Environment(\.motionGate) private var motionGate

    /// Der beim Bühnenstart gewählte Auftritt: Briefschlitz für die
    /// eine Inszenierung der Runde, sonst das normale Blättern des Heros.
    private enum Auftritt { case briefschlitz, blaettern }
    @State private var auftritt: Auftritt?
    @State private var angekommen = false
    /// Die Marke, deren Bühne dieser lebende Pane zuletzt gestellt hat —
    /// nur eine ABWEICHENDE Marke darf `angekommen` je zurücksetzen.
    @State private var gestellteMarke: String?

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Die Naht: der Schlitz, aus dem die Runde ins Fach gleitet —
            // sichtbar auch in Ruhe (Architektur, nicht Effekt), 1 pt
            // unterm überhängenden Stempel des Bogens.
            Rectangle()
                .fill(Nacht.naht)
                .frame(height: 1)
                .accessibilityHidden(true)
            content
                .rotation3DEffect(
                    .degrees(blaetternWinkel),
                    axis: (x: 0, y: 1, z: 0), anchor: .leading,
                    perspective: Theme.Motion.Signature.blaetternPerspective)
                .offset(y: schlitzVersatz)
                .opacity(angekommen ? 1 : 0)
                .background {
                    if auftritt == .briefschlitz && motionGate.reduceMotion {
                        // Reduce Motion: das Lichtschein-Standbild statt
                        // der Gleit-Choreografie (statischer End-Glow).
                        LichtscheinGlow(size: LayoutMetrics.s(170))
                    }
                }
        }
        // Die MARKE ist die Task-Identität: Erst-Erscheinen UND jeder
        // Rundenwechsel im sichtbaren Tab stellen die Bühne; Verschwinden
        // oder eine neue Marke canceln den laufenden Auftritt strukturell.
        .task(id: marke) { await eintreffen() }
    }

    /// Blättern-Pfad (kein Inszenierungs-Anspruch): exakt die Winkel des
    /// benannten Signature-Satzes, Reduce Motion bleibt der reine Fade.
    private var blaetternWinkel: Double {
        auftritt == .blaettern && !angekommen && !motionGate.reduceMotion
            ? Theme.Motion.Signature.blaetternDegrees : 0
    }

    /// Briefschlitz-Pfad: der Bogen startet knapp ÜBER der Naht und
    /// gleitet mit `arrive` ins Fach (Offset + Fade — bewusst ohne
    /// Clipping, damit Siegel-Schatten und Stempel-Überhang des Bogens
    /// nie hart geschnitten werden).
    private var schlitzVersatz: CGFloat {
        auftritt == .briefschlitz && !angekommen && !motionGate.reduceMotion
            ? -LayoutMetrics.s(18) : 0
    }

    @MainActor
    private func eintreffen() async {
        if gestellteMarke != marke {
            // Neue Runde im lebenden Pane: die alte Inszenierung ist
            // Geschichte — Bühne zurück, der neue Brief darf eintreffen.
            if gestellteMarke != nil {
                angekommen = false
                auftritt = nil
            }
            gestellteMarke = marke
        }
        // Re-Appear derselben Marke (Tab-Wechsel): nichts spielt erneut —
        // die Runde hat ihre EINE Inszenierung gehabt.
        guard !angekommen else { return }
        let modus = auftritt ?? (inszeniert ? Auftritt.briefschlitz : .blaettern)
        auftritt = modus
        guard modus == .briefschlitz else {
            withAnimation(Theme.Motion.blaettern) { angekommen = true }
            return
        }
        // Die Marke fällt, WEIL gespielt wird — nicht schon beim Rechnen.
        onGespielt()
        AccessibilityNotification.Announcement(ansage).post()
        guard !motionGate.reduceMotion else {
            angekommen = true
            return
        }
        Haptics.shared.tap()
        SoundEngine.shared.play(.swish)
        withAnimation(Theme.Motion.arrive) { angekommen = true }
        // Choreografie-Pause: der trockene rigid-Tick genau dann, wenn der
        // Bogen im Fach aufliegt (arrive ≈ 0,5 s) — im STRUKTURIERTEN Task:
        // Verschwinden/neue Marke canceln den Schlaf, der Tick verstummt.
        try? await Task.sleep(nanoseconds: 480_000_000)
        guard !Task.isCancelled else { return }
        Haptics.shared.composerTick(intensity: 0.8)
    }
}

extension View {
    /// Hero-Eintritt des Zustellfachs: EINMAL pro Runde der Briefschlitz,
    /// sonst das normale Blättern — immer unter der Naht des Fachs. Die
    /// Marke bindet die Choreo an die Runde (Rundenwechsel im sichtbaren
    /// Tab inszeniert neu).
    func briefschlitzEntry(marke: String, inszeniert: Bool, ansage: String,
                           onGespielt: @escaping () -> Void) -> some View {
        modifier(BriefschlitzEntry(marke: marke, inszeniert: inszeniert,
                                   ansage: ansage, onGespielt: onGespielt))
    }
}
