import SwiftUI

// FullRelease N2-A — „Korrespondenz": the chat feature's shared paper
// machinery. The Zettel background itself lives next to the bubbles in
// ChatView; THIS file holds the pieces several chat surfaces share — the
// couple's wax seal, the Briefbogen band, the paper writing field and
// the Legen entrance of the transcript. Every value is a design-system
// token (Papier/Tinte/Wachs, PaperRules-backed) — no raw hexes here.

// MARK: - Stable paper seed

/// Seed for `paperTilt(seed:)` from stable item IDs (message ids) —
/// deliberately NOT `String.hashValue` (randomized per launch; a seal must
/// keep its tilt across app starts): FNV-1a over UTF-8, the same family
/// as `GamesPaperSeed`/`memoriesPaperSeed`.
func chatPaperSeed(_ id: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in id.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

// MARK: - Wax seal

/// The couple's wax seal — since FullRelease R1-A a thin wrapper over
/// the ONE material seal building block in the UI layer (`WachsSiegel`:
/// seeded irregular rim, pressed-in heart relief, matte sheen). The
/// contrast machinery is unchanged: gold→blend wax with the `onWax`
/// embossing, judged against BOTH wax stops (Schlussrunde 5 pin).
/// Existing call sites (LetterSeals, the Briefbogen band) keep their
/// parameters; `seed` lets an item deform its own rim.
struct ChatWaxSealView: View {
    var size: CGFloat = LayoutMetrics.s(24)
    /// Embossing glyph size follows the seal size via a semantic role —
    /// the small chat seal presses a caption heart, the Briefbogen seal
    /// a footnote one.
    var emboss: Font = .system(.caption2, design: .rounded).weight(.bold)
    /// Stable rim seed — defaults to the shared chrome-seal rim.
    var seed: UInt64 = 0x53_49_45_47_45_4C // "SIEGEL"

    var body: some View {
        WachsSiegel(seed: seed, size: size, emboss: emboss)
    }
}

// MARK: - Briefbogen band

/// The Briefbogen dressing: the couple band — the heroGradient as a 6-pt
/// OBJECT (`Papier.bandBreite`), never a card wash — crossing the hero
/// card, with the wax seal pressed onto it. Exactly ONE Briefbogen per
/// screen (charter hero rule): the letter composer's preview and the
/// letter reader each dress their single hero with this overlay.
struct ChatBriefbogenBand: View {
    /// Stable item seed — drives the seal's `paperTilt`, the screen's one
    /// sanctioned rotation.
    let seed: UInt64

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        ZStack {
            Rectangle()
                .fill(coupleTint.band)
                .frame(height: Papier.bandBreite)
            ChatWaxSealView(size: LayoutMetrics.s(40),
                            emboss: .system(.footnote, design: .rounded).weight(.bold),
                            seed: seed)
                .paperTilt(seed: seed)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Paper writing field & action button (promoted — P6-C)

/// FullRelease P6-C: the paper field and action-button styles were born
/// here but are used clear across the app (Memories, Settings, Icon
/// gifts) — they now live in UI/PaperControls.swift as `PaperFieldStyle`
/// and `PaperActionButtonStyle`. These typealiases keep every existing
/// call site valid; new code addresses the UI-layer names directly.
typealias ChatPaperFieldStyle = PaperFieldStyle
typealias ChatPaperActionButtonStyle = PaperActionButtonStyle

// MARK: - Legen entrance

/// „Legen" — the transcript's entrance: the newest Zettel land on the
/// desk when the chat opens (scale legenScale → 1, y legenOffsetY → 0,
/// `Theme.Motion.legen`, `legenStagger` between slots, at most
/// `legenBudget` elements — all Signature parameters, nothing invented
/// here). Reduce Motion: a pure fade without transform or stagger.
/// Rows without a slot render untouched.
struct ChatLegenEntrance: ViewModifier {
    /// Stagger slot 0…legenBudget−1 — nil for rows outside the entrance.
    var slot: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    private var entering: Bool { slot != nil && !landed }

    func body(content: Content) -> some View {
        content
            .opacity(entering ? 0 : 1)
            .scaleEffect(entering && !reduceMotion
                         ? Theme.Motion.Signature.legenScale : 1)
            .offset(y: entering && !reduceMotion
                    ? Theme.Motion.Signature.legenOffsetY : 0)
            // SwiftUI's parent/child onAppear order is undefined — the row
            // may appear before the transcript hands out its slots. Both
            // paths land the Zettel exactly once.
            .onAppear(perform: land)
            .onChange(of: slot != nil) { land() }
    }

    private func land() {
        guard let slot, !landed else { return }
        let stagger = reduceMotion
            ? 0 : Double(slot) * Theme.Motion.Signature.legenStagger
        withAnimation(Theme.Motion.legen.delay(stagger)) {
            landed = true
        }
    }
}
