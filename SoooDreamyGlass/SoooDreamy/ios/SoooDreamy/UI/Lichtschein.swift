import SwiftUI

// FullRelease P6-C — the Lichtschein celebration, promoted from
// Stationen/Spieltisch/GamesPaperKit.swift: the radial lamp-gold bloom is the
// app-wide replacement for small/medium confetti (Direction §5, delight
// levels 1–2 — `epic` keeps its particles), not a games-only trick.
// `GameLichtscheinCenter`/`Host`/`Moment` stay valid as typealiases in
// GamesPaperKit.swift, so no call site had to move. All choreography
// parameters come from `Theme.Motion.Signature` — nothing invented here.

/// One fired Lichtschein — identity keeps repeated blooms distinct. The
/// hold matches the medium DelightMoment cadence it replaces.
struct LichtscheinMoment: Identifiable, Equatable {
    let id = UUID()
    let duration: TimeInterval = 2.2
}

/// Tiny hub between a celebration trigger and the ONE overlay host per
/// surface (the games NavigationStack today) — the paper twin of
/// DelightCenter, for the glow that replaces small/medium confetti.
@MainActor
@Observable
final class LichtscheinCenter {
    static let shared = LichtscheinCenter()

    private(set) var moment: LichtscheinMoment?
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    private init() {}

    func fire() {
        let new = LichtscheinMoment()
        moment = new
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(new.duration * 1_000_000_000))
            if !Task.isCancelled { self?.moment = nil }
        }
    }
}

/// The radial `Licht.lampengold` glow that blooms behind the celebrated
/// moment (opacity 0 → peak → rest, radius 0 → 1.4 × element size) and
/// then STAYS lit until the moment clears. Reduce Motion: the static end
/// glow appears immediately — a painting, not a black hole. Purely
/// decorative: hidden from VoiceOver (the ceremonies announce themselves
/// via `GamesA11y.announce`), never hit-testable.
struct LichtscheinHost: View {
    @Environment(\.motionGate) private var motionGate
    @State private var glowOpacity: Double = 0
    @State private var bloomed = false

    private var center: LichtscheinCenter { .shared }

    var body: some View {
        GeometryReader { geo in
            if let moment = center.moment {
                let radius = min(geo.size.width, geo.size.height)
                    * Theme.Motion.Signature.lichtscheinRadiusFactor / 2
                Circle()
                    .fill(RadialGradient(
                        colors: [Licht.lampengold.opacity(glowOpacity), .clear],
                        center: .center, startRadius: 0, endRadius: radius))
                    .frame(width: radius * 2, height: radius * 2)
                    .scaleEffect(bloomed || motionGate.reduceMotion ? 1 : 0.01)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .transition(.opacity)
                    .id(moment.id)
                    .onAppear { bloom() }
                    .onChange(of: moment.id) { bloom() }
            }
        }
        .animation(Theme.Motion.settle, value: center.moment?.id)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bloom() {
        if motionGate.reduceMotion {
            // The still path: the lit end state, immediately.
            bloomed = true
            glowOpacity = Theme.Motion.Signature.lichtscheinRestOpacity
            return
        }
        bloomed = false
        glowOpacity = 0
        withAnimation(Theme.Motion.lichtschein) {
            bloomed = true
            glowOpacity = Theme.Motion.Signature.lichtscheinPeakOpacity
        }
        withAnimation(Theme.Motion.lichtschein.delay(1.2)) {
            glowOpacity = Theme.Motion.Signature.lichtscheinRestOpacity
        }
    }
}
