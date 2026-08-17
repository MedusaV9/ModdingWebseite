import SwiftUI

// FullRelease N2-C — „Spieleabend am Küchentisch": the shared paper
// vocabulary of the games wave. Boards become paper game plans, status
// rows become Zettel, and match celebrations on delight levels 1–2 bloom
// as a Lichtschein instead of full-screen confetti (Direction §5; `epic`
// keeps its particles). Everything here consumes the pinned tokens from
// UI/Theme.swift + UI/Glass.swift — no raw design values.

// MARK: - Stable paper seeds

/// Seeds for `paperTilt(seed:)` / `TornEdgeShape(seed:)` from stable item
/// IDs. Deliberately NOT `String.hashValue` (randomized per launch — a
/// Zettel must keep its tilt across app starts): FNV-1a over UTF-8.
enum GamesPaperSeed {
    static func seed(_ id: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}

// MARK: - Motion: Blättern & Legen (the two arrival signatures)

/// „Blättern" — screen/hero entry: the paper rotates in around its leading
/// edge (Signature.blaetternDegrees → 0°, anchor .leading). Reduce Motion:
/// a pure crossfade — the rotation never happens.
struct PaperBlaetternModifier: ViewModifier {
    @Environment(\.motionGate) private var motionGate
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(arrived || motionGate.reduceMotion
                         ? 0 : Theme.Motion.Signature.blaetternDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: Theme.Motion.Signature.blaetternPerspective)
            .opacity(arrived ? 1 : 0)
            .onAppear {
                guard !arrived else { return }
                withAnimation(Theme.Motion.blaettern) { arrived = true }
            }
    }
}

/// „Legen" — an element lands on the table (scale 1.04 → 1, y 6 → 0),
/// staggered by `legenStagger` for at most `legenBudget` elements; later
/// elements land together. Reduce Motion: fade without transform.
struct PaperLegenModifier: ViewModifier {
    let index: Int
    @Environment(\.motionGate) private var motionGate
    @State private var landed = false

    private var delay: TimeInterval {
        index < Theme.Motion.Signature.legenBudget
            ? TimeInterval(index) * Theme.Motion.Signature.legenStagger
            : 0
    }

    func body(content: Content) -> some View {
        content
            .opacity(landed ? 1 : 0)
            .scaleEffect(landed || motionGate.reduceMotion
                         ? 1 : Theme.Motion.Signature.legenScale)
            .offset(y: landed || motionGate.reduceMotion
                    ? 0 : Theme.Motion.Signature.legenOffsetY)
            .onAppear {
                guard !landed else { return }
                withAnimation(Theme.Motion.legen.delay(delay)) { landed = true }
            }
    }
}

extension View {
    /// Hero/screen arrival on paper (one per screen, like the hero rule).
    func paperBlaettern() -> some View {
        modifier(PaperBlaetternModifier())
    }

    /// Element arrival on paper — pass the element's position for the
    /// stagger (only the first `legenBudget` are staggered).
    func paperLegen(index: Int = 0) -> some View {
        modifier(PaperLegenModifier(index: index))
    }
}

// MARK: - Lichtschein (promoted — P6-C, app-wide since R1-D)

/// FullRelease P6-C: the Lichtschein bloom replaces small/medium confetti
/// APP-wide, not just at the games table — center, host and moment now
/// live in UI/Lichtschein.swift as `LichtscheinCenter`/`LichtscheinHost`/
/// `LichtscheinMoment`. Since FullRelease R1-D the claim is literal:
/// RootView mounts a `LichtscheinHost` over every tab pane and all fixed
/// small/medium celebrate call sites fire the glow — only arbiter-sized
/// moments (which may grant epic) keep Delight's particles. These
/// typealiases keep every existing call site valid; new code addresses
/// the UI-layer names directly.
typealias GameLichtscheinMoment = LichtscheinMoment
typealias GameLichtscheinCenter = LichtscheinCenter
typealias GameLichtscheinHost = LichtscheinHost

// MARK: - Paper tags & Zettel (status rows, badges ON paper)

/// The paper sibling of `EmptyStateView` for empty states that lie ON a
/// paper card: the shared component sets night inks (`Theme.textPrimary`)
/// that vanish on Papier.brief, so games render this twin with the three
/// paper inks instead. Layout and action affordance stay identical.
struct PaperEmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.tinte)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.top, LayoutMetrics.s(6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .padding(.horizontal, Space.xl)
    }
}

/// The paper sibling of `PillTag` for use INSIDE paper cards: `PillTag`
/// sets night ink on a tint wash, which is unreadable on Papier.brief —
/// this tag reads in a named INK on the sanctioned inner fill
/// (`Papier.innenFill` + `Papier.kante` hairline; never a second
/// material). Identity comes through the ink, never through a wash.
struct PaperTag: View {
    let text: String
    /// A paper-safe ink: `Tinte.*`, `coupleTint.tinte*` or `Wachs.rot`
    /// (5.2:1 on brief — the stamp-pad red for "your turn" moments).
    var ink: Color = Tinte.sekundaer

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(ink)
            .padding(.vertical, 5)
            .padding(.horizontal, LayoutMetrics.s(11))
            .background(
                Capsule()
                    .fill(Papier.innenFill)
                    .overlay(Capsule().strokeBorder(Papier.kante,
                                                    lineWidth: Theme.hairlineWidth))
            )
    }
}
