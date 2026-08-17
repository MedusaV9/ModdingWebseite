import Foundation

/// The rebuilt v10 onboarding is data-driven: pages live here (testable),
/// the SwiftUI layer only renders them. Keys must exist in CoreStrings DE+EN.
///
/// Re-Eval Runde 2 (S1): the emoji hero died. The welcome page carries NO
/// glyph at all (`symbol == nil`) — the view renders the material
/// WachsSiegel-über-Briefbogen composition from existing Kino/About
/// building blocks; every other page gets a small SF-Symbol vignette in
/// couple ink on a paper stamp (commandment 1: symbols, never emoji).
struct OnboardingPage: Equatable, Identifiable {
    let id: String
    /// SF Symbol of the page's vignette — nil ONLY on the hero page,
    /// whose place is taken by the sealed-letter composition.
    let symbol: String?
    let titleKey: String
    let bodyKey: String
    /// (SF Symbol, text key, accent role 0-3) rows — empty = hero page.
    let features: [(icon: String, textKey: String, tint: Int)]

    static func == (lhs: OnboardingPage, rhs: OnboardingPage) -> Bool {
        lhs.id == rhs.id
    }
}

enum OnboardingScript {
    /// Welcome → what you can do → your server → the safety net → the way
    /// in. The safety page explains recovery keys BEFORE the first pairing
    /// (the ceremony sheet lands on prepared minds); the closing guide page
    /// (Welle 7 [29]) turns the abstract tour into three concrete steps —
    /// connect server, pair up, go — with the Welle-3 second-device link
    /// path named as its own visible option.
    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome", symbol: nil,
            titleKey: "onboarding.title",
            bodyKey: "onboarding.tagline",
            features: []),
        OnboardingPage(
            id: "together", symbol: "person.2.fill",
            titleKey: "onboarding.page.together.title",
            bodyKey: "onboarding.page.together.body",
            features: [
                ("heart.fill", "onboarding.feature1", 0),
                ("bubble.left.and.bubble.right.fill", "onboarding.feature2", 1),
                ("gamecontroller.fill", "onboarding.feature3", 2),
                ("sparkles", "onboarding.feature4", 3),
            ]),
        OnboardingPage(
            id: "server", symbol: "house.fill",
            titleKey: "onboarding.page.server.title",
            bodyKey: "onboarding.page.server.body",
            features: [
                ("lock.shield.fill", "onboarding.page.server.point1", 0),
                ("server.rack", "onboarding.page.server.point2", 1),
                ("icloud.slash.fill", "onboarding.page.server.point3", 2),
            ]),
        OnboardingPage(
            id: "safety", symbol: "lifepreserver",
            titleKey: "onboarding.page.safety.title",
            bodyKey: "onboarding.page.safety.body",
            features: [
                ("key.fill", "onboarding.page.safety.point1", 0),
                ("arrow.triangle.2.circlepath", "onboarding.page.safety.point2", 1),
                ("person.2.fill", "onboarding.page.safety.point3", 2),
            ]),
        OnboardingPage(
            id: "guide", symbol: "signpost.right.fill",
            titleKey: "onboarding.page.guide.title",
            bodyKey: "onboarding.page.guide.body",
            // Fix4 Befund 1b: the numbered icons stay as the pinned ROUTE
            // ORDER data (LogicTests) — the view no longer stamps them.
            // OnboardingFlowView composes rows 0–2 as ONE connected
            // Zustellroute (paper stops + night seam) and renders row 3,
            // the second-device path, as a quiet subordinate clause.
            features: [
                ("1.circle.fill", "onboarding.page.guide.step1", 0),
                ("2.circle.fill", "onboarding.page.guide.step2", 1),
                ("3.circle.fill", "onboarding.page.guide.step3", 2),
                ("ipad.and.iphone", "onboarding.page.guide.link", 3),
            ]),
    ]

    static var pageCount: Int { pages.count }
}
