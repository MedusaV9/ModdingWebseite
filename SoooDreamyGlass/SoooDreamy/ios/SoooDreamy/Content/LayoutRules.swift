import Foundation

/// Pure container-size rules of the responsive layout — Foundation-only so
/// the Linux LogicTests can pin them down. The SwiftUI layer (`LayoutMetrics`
/// in `UI/Theme.swift`) feeds these with the REAL container width measured by
/// the root GeometryReader: the app window, never `UIScreen.main` — on iPad a
/// window is not the screen (Split View, Slide Over, Stage Manager).
enum LayoutRules {
    /// Design baseline width (iPhone Pro Max) — scale 1 by definition.
    static let designWidth: Double = 430

    /// Standard / non-Pro iPhone widths feel crowded at pure linear scale,
    /// so anything narrower than this gets compressed a touch further.
    static let compressionThreshold: Double = 410
    static let compressionFactor: Double = 0.94

    /// The layout never shrinks below this (smallest split-view slots read
    /// as a dense phone) and never grows above the design baseline — on
    /// regular widths the extra space becomes column margins, not zoom.
    static let minScale: Double = 0.78
    static let maxScale: Double = 1.0

    /// Layout scale for a container of `width` points.
    static func scale(forWidth width: Double) -> Double {
        guard width > 0 else { return 1 }
        var raw = width / designWidth
        if width < compressionThreshold { raw *= compressionFactor }
        return min(max(raw, minScale), maxScale)
    }

    /// Width a content column actually gets: the container, capped at the
    /// column's named maximum (regular-width panes center the rest away).
    static func columnWidth(container: Double, max cap: Double) -> Double {
        guard container > 0 else { return 0 }
        return min(container, cap)
    }

    /// The canvas moves its tools into a trailing rail only when the pane
    /// is genuinely wide — regular size class alone is not enough, because
    /// the Memories split view hands the canvas a detail column that can be
    /// much narrower than the window (Stage Manager, 50/50 splits).
    static let canvasRailMinWidth: Double = 700

    /// True when a canvas pane of `width` should lay out board + side rail
    /// instead of the stacked phone layout.
    static func canvasUsesSideRail(paneWidth: Double, isRegularWidth: Bool) -> Bool {
        isRegularWidth && paneWidth >= canvasRailMinWidth
    }

    /// The Memories hub keeps its 320-point section sidebar PERSISTENT only
    /// while the pane genuinely holds sidebar + a real detail column. Below
    /// this the sidebar becomes a toolbar-toggled column instead — a narrow
    /// Stage-Manager tile must never spend a third of itself on chrome.
    static let memoriesSidebarMinWidth: Double = 900

    /// True when a Memories pane of `paneWidth` should keep the section
    /// sidebar permanently visible next to the detail column.
    static func memoriesUsesPersistentSidebar(paneWidth: Double,
                                              isRegularWidth: Bool) -> Bool {
        isRegularWidth && paneWidth >= memoriesSidebarMinWidth
    }

    /// The Archiv Schrankfront (six drawer cards, ENTSCHEID §4.4) lays
    /// out two balanced columns once the pane genuinely holds two card
    /// widths — iPad half-splits land here while still compact-width;
    /// phones stay a single column of full-width drawers.
    static let schrankfrontTwoColumnMinWidth: Double = 560

    /// True when a Schrankfront pane of `paneWidth` should split the six
    /// drawer cards into two top-aligned columns.
    static func schrankfrontUsesTwoColumns(paneWidth: Double) -> Bool {
        paneWidth >= schrankfrontTwoColumnMinWidth
    }

    /// The chat gains its leading rail (letters, pins, photo moments) only
    /// when rail (300) + a full reading-width conversation (640) + a breath
    /// of margin truly fit — otherwise the conversation column pays for it.
    static let chatRailMinWidth: Double = 960

    /// Fixed width of the chat's leading rail (within the HIG 280–320 band).
    static let chatRailWidth: Double = 300

    /// True when a chat pane of `paneWidth` should show the leading rail
    /// next to the conversation column.
    static func chatUsesRail(paneWidth: Double, isRegularWidth: Bool) -> Bool {
        isRegularWidth && paneWidth >= chatRailMinWidth
    }

    // MARK: Bottom chrome (system tab bar + „Heute-Zettel" accessory)

    // Liquid glass refracts whatever parks directly under its rim into
    // mirrored text ghosts (device feedback: Spielen/Home resting state).
    // These tokens describe the bottom chrome zone in points so scroll
    // roots and particle emitters can keep their RESTING content clear of
    // it — while scrolling, content may still run under the glass (system
    // behavior). System chrome does not scale with the design scale, so
    // consumers use the values unscaled.

    /// Rest height of the tab-view bottom accessory capsule (the
    /// „Heute-Zettel" in its expanded placement: 30-pt avatar row plus
    /// capsule padding).
    static let accessoryRestHeight: Double = 48

    /// Rest height of the system tab bar glass (full, non-minimized).
    static let tabBarRestHeight: Double = 50

    /// Breathing room between hard paper text and a glass edge — the
    /// distance at which the refraction stops picking up legible ghosts.
    static let glassEdgeBreath: Double = 16

    /// Fix2-A №4: whether the „Zustellzettel" accessory is mounted at
    /// all. At accessibility text sizes the bottom chrome (accessory +
    /// tab bar) ate the content, so the accessory stays UNMOUNTED there
    /// (RootView gate) — its information (round + today status) lives in
    /// the Postfach itself (Stempelzeile, hero states, Zustellrunden).
    static func accessoryMounted(isAccessibilitySize: Bool) -> Bool {
        !isAccessibilitySize
    }

    /// Resting bottom clearance for tab-root scroll content, coupled to
    /// the REAL chrome height: with the accessory mounted the system
    /// safe area already ends at the accessory's top edge, but on real
    /// devices resting text still parked inside the refraction band —
    /// one accessory height plus breath keeps the last line clearly
    /// above the glass. At accessibility sizes the accessory is
    /// unmounted (gate above), so only the breath above the tab-bar
    /// glass remains and grown type gets the room back.
    static func restingBottomClearance(isAccessibilitySize: Bool) -> Double {
        (accessoryMounted(isAccessibilitySize: isAccessibilitySize)
            ? accessoryRestHeight : 0) + glassEdgeBreath
    }

    /// The classic (accessory-mounted) clearance — the token the non-AX
    /// tab roots keep feeding into `contentMargins(.bottom, …)`.
    static var restingBottomClearance: Double {
        restingBottomClearance(isAccessibilitySize: false)
    }

    /// Bottom exclusion for celebration particle emitters measured from
    /// the bottom SAFE AREA edge: the emitter rect never dips below the
    /// chrome edge (tab bar + accessory + breath), so no heart ever
    /// floats through the glass.
    static var celebrationBottomExclusion: Double {
        tabBarRestHeight + accessoryRestHeight + glassEdgeBreath
    }

    // MARK: Postfach bottom clearance (Fix2-A №2/№4)

    /// The 💭 pulse quick action rides IN the flow now (a trailing row
    /// under the last card, DashboardView) instead of floating over the
    /// scroll content — the overlay covered interactive elements in
    /// every seed (AX5: the plus chip; regular: the haptic-studio
    /// chevron). With no floating zone left, the Postfach margin is the
    /// chrome-coupled resting clearance — including the AX variant
    /// without the accessory share (the accessory is unmounted there).
    static func postfachBottomClearance(isAccessibilitySize: Bool) -> Double {
        restingBottomClearance(isAccessibilitySize: isAccessibilitySize)
    }

    // MARK: „Sendung Nr. 1" (pairing stage, Postfach)

    /// Fraction of the pane height that rests as air ABOVE the sealed
    /// first Sendung while waiting for the partner — the artifact sits
    /// calmly toward the middle instead of gluing under the header
    /// („tote Mitte"). Applied as a spacer, never as a fixed frame, so
    /// grown type and the unfolded QR can only push DOWN, never clip.
    static let sendungLuftAnteil: Double = 0.12
}
