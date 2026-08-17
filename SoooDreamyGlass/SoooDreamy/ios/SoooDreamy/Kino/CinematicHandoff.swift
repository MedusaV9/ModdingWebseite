import SwiftUI

// FullRelease R1-B — the REAL hand-off between the first-launch cinema
// and the onboarding guide (Kino-Final-Eval finding 1: chapter 7 used to
// morph into a MOCK home view of three Zettel and then hard-crossfade to
// the guide — the cut was visible).
//
// Architecture: the guide is mounted UNDER the cinema for the whole
// performance (the cinema's room is opaque, so it stays invisible but
// laid out). Its first REAL elements — the wordmark title and the three
// entry cards (scan / server / demo) — report their frames through this
// PreferenceKey in the shared `space` coordinate system. Chapter 7 lays
// its papers onto EXACTLY these rects and morphs them into the real
// button rendering (same styles, same labels, same radii), so the moment
// the cinema layer leaves, the pixels underneath are identical — the
// mock BECOMES the original, and the guide's remaining chrome (emoji,
// body, dots, top bar) lays itself in afterwards as the film's last
// breath instead of a cut.

/// The guide elements the finale morphs onto. Wordmark = the hero title
/// of page 0; scan/server/demo = the three entry-path buttons.
enum CinematicHandoffElement: Hashable {
    case wordmark
    case scan
    case server
    case demo
}

enum CinematicHandoff {
    /// The shared coordinate space of guide and cinema — both layers fill
    /// the same ZStack in OnboardingFlowView, so a frame measured here is
    /// directly a stage position for the finale.
    static let space = "cinematic-handoff"
}

struct CinematicHandoffFramesKey: PreferenceKey {
    static var defaultValue: [CinematicHandoffElement: CGRect] { [:] }

    static func reduce(value: inout [CinematicHandoffElement: CGRect],
                       nextValue: () -> [CinematicHandoffElement: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks a guide element as a hand-off anchor: its frame (in the
    /// shared space) becomes the finale's landing rect for this element.
    func cinematicHandoffAnchor(_ element: CinematicHandoffElement) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: CinematicHandoffFramesKey.self,
                    value: [element: geo.frame(in: .named(CinematicHandoff.space))])
            }
        )
    }
}
