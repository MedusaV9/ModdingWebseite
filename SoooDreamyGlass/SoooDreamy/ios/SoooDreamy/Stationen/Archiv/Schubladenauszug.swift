import SwiftUI

// Neubau N4 — Signature „Der Schubladenauszug" (ENTSCHEID §4.4): a drawer
// of the Archiv cabinet opens INLINE — its section rows glide out
// horizontally on `Theme.Motion.settle` (x −12 → 0, 40 ms stagger, capped
// at six), and the pull ends in ONE soft haptic detent, deliberately
// soundless (commandment 3: felt, not heard). Reduce Motion: the drawer
// opens directly — rows fade in without slide or stagger, the detent
// stays. The detent itself lives with the drawer (MemoriesView fires it
// once per pull), never per row.

/// Row-level part of the signature: leading offset + fade per section row.
struct SchubladenauszugRow: ViewModifier {
    /// Row position inside the drawer — drives the 40 ms stagger.
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false

    /// Glide start offset in points (leading) — the drawer depth.
    static let auszug: CGFloat = -12
    /// Stagger per row; rows beyond the sixth arrive with the sixth.
    static let staggerSeconds = 0.04
    static let maxStaggered = 6

    func body(content: Content) -> some View {
        content
            .offset(x: settled || reduceMotion ? 0 : Self.auszug)
            .opacity(settled ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    // Direct open: one calm fade, no slide, no stagger.
                    withAnimation(Theme.Motion.settle) { settled = true }
                } else {
                    let delay = Double(min(index, Self.maxStaggered - 1))
                        * Self.staggerSeconds
                    withAnimation(Theme.Motion.settle.delay(delay)) {
                        settled = true
                    }
                }
            }
    }
}

extension View {
    /// One section row gliding out of an opening Archiv drawer.
    func schubladenauszug(index: Int) -> some View {
        modifier(SchubladenauszugRow(index: index))
    }
}
