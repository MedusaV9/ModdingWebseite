import SwiftUI

// FullRelease N2-D — „Fotoalbum & Sekretär": shared building blocks of the
// Archiv hub (W9A component split from the 1 000-line MemoriesView) plus the
// paper toolkit of the Memories/Settings wave: icon badge, recent-activity
// chip, register tab, wax seal and the Briefbogen band. All chrome glyphs
// are SF Symbols (commandment 1); only emoji the couple picked themselves
// (event emoji, coupon emoji) remain text. The old grid tile and full-width
// banner retired with the Schrankfront (Neubau N4, ENTSCHEID §4.4).

// MARK: - Paper physics seed

/// Stable seed for `paperTilt(seed:)`/`TornEdgeShape(seed:)` from an item
/// id — djb2 like the rest of the app (`ContentCycle.seed`), NEVER
/// `String.hashValue` (process-randomized: the tilt would flicker between
/// launches and differ between the partners' devices).
func memoriesPaperSeed(_ id: String) -> UInt64 {
    ContentCycle.seed(id)
}

// MARK: - Wax seal (the couple's blend as material)

/// The couple's wax seal: a DEEP wax circle (`coupleTint.wachsTief` —
/// nacht-first P2, MIGRATION_DUNKEL §5: the flat pale `wachs` chip is
/// lifted to the satt seal wax) with an embossed heart in the LIGHT
/// verdict-secured `aufWachs` ink, seeded tilt (the one sanctioned
/// rotation source). Counts as ONE artifact against the 3-per-screen
/// budget.
struct WachsSiegelBadge: View {
    /// Stable seed (item/screen id) for the seeded tilt.
    var seed: UInt64
    var size: CGFloat = 44
    /// SF Symbol embossed into the wax.
    var symbol: String = "heart.fill"

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tilted = ZStack {
            Circle()
                .fill(coupleTint.wachsTief)
            Circle()
                .strokeBorder(coupleTint.aufWachs.opacity(0.35),
                              lineWidth: Theme.hairlineWidth)
                .padding(size * 0.12)
            Image(systemName: symbol)
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.aufWachs)
        }
        .frame(width: LayoutMetrics.s(size), height: LayoutMetrics.s(size))
        .elevation(.raised)
        .accessibilityHidden(true)

        // Reduce Motion: artifacts lie straight — the tilt is ornament.
        if reduceMotion {
            tilted
        } else {
            tilted.paperTilt(seed: seed)
        }
    }
}

// MARK: - Briefbogen hero (paper + band + seal — exactly ONE per screen)

/// The couple band + wax seal overlay of the ONE Briefbogen hero card per
/// screen: the heroGradient leaves the surface and becomes a 6-pt OBJECT
/// crossing the paper, the seal sits on the band. Apply ON TOP of
/// `paperCard(.briefbogen)` — band and seal are overlay decor without
/// layout contribution (AX: text never displaces a seal, a seal never
/// displaces text).
struct BriefbogenBandOverlay: ViewModifier {
    /// Stable seed for the seal tilt.
    var seed: UInt64
    /// Sealed ceremonies show the wax; quiet heroes carry only the band.
    var showsSeal = true

    @Environment(\.coupleTint) private var coupleTint

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(coupleTint.band)
                    .frame(height: Papier.bandBreite)
                    .padding(.bottom, Space.l)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomTrailing) {
                if showsSeal {
                    WachsSiegelBadge(seed: seed)
                        .padding(.trailing, Space.l)
                        .padding(.bottom, Space.xs)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Band + seal for the one `PaperLevel.briefbogen` hero of a screen.
    func briefbogenBand(seed: UInt64, showsSeal: Bool = true) -> some View {
        modifier(BriefbogenBandOverlay(seed: seed, showsSeal: showsSeal))
    }
}

// MARK: - Blättern entry (hero/screen arrival)

/// The Blättern motion signature: the card rotates in around its leading
/// edge (Signature.blaetternDegrees → 0°, anchor .leading) driven by
/// `Theme.Motion.blaettern`. Reduce Motion: a pure crossfade — the page is
/// simply there.
struct BlaetternEintritt: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(arrived || reduceMotion
                         ? 0 : Theme.Motion.Signature.blaetternDegrees),
                axis: (x: 0, y: 1, z: 0),
                anchor: .leading,
                perspective: Theme.Motion.Signature.blaetternPerspective)
            .opacity(arrived ? 1 : 0)
            .onAppear {
                withAnimation(Theme.Motion.blaettern) { arrived = true }
            }
    }
}

extension View {
    /// Hero/screen entry on the Blättern signature (crossfade under
    /// Reduce Motion). At most the hero per screen — never lists.
    func blaetternEintritt() -> some View {
        modifier(BlaetternEintritt())
    }
}

// MARK: - Register tab (paper folder tabs: albums, sidebar, filters)

/// A register tab at night — the album/filter chip of the photo-album
/// world (nacht-first P2): the selected tab is the pulled-out night card
/// wearing the lamp's edge, unselected tabs are a quiet aufNacht wash on
/// the room. Top corners rounded, bottom edge straight — a tab sticking
/// out of a folder.
struct PapierRegisterTab: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Radius.papier,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0,
                               topTrailingRadius: Radius.papier,
                               style: .continuous)
    }

    var body: some View {
        HStack(spacing: Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
        .padding(.vertical, 7)
        .padding(.horizontal, Space.l)
        .background(
            shape.fill(selected ? Papier.nachtkarton
                                : Papier.nachtInnenFill)
                .overlay(shape.strokeBorder(
                    selected && colorSchemeContrast != .increased
                        ? AnyShapeStyle(PaperLightEdge.nachtGradient)
                        : AnyShapeStyle(Theme.Contrast.hairline(
                            increased: colorSchemeContrast == .increased)),
                    lineWidth: Theme.hairlineWidth))
                .elevation(selected ? .raised : .resting)
        )
        .overlay(alignment: .bottom) {
            // The couple's shared color marks the open tab — a non-text
            // identity line (blend is verdict-secured on night).
            if selected {
                Rectangle()
                    .fill(coupleTint.blend)
                    .frame(height: LayoutMetrics.s(2))
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Icon badge

/// The hub's ONE icon-badge voice (UX polish, P2-D): every drawer card
/// leads with the same quiet roundel — an inner wash with a hairline
/// carrying the hierarchical symbol. Night language by default (aufNacht
/// wash + naht); badges inside paper heroes pass `onPaper` for the ink
/// family. The tint stays secondary by default.
struct MemoriesIconBadge: View {
    let symbol: String
    var tint: Color = Nacht.sekundaer
    var size: CGFloat = 36
    /// True on the ONE paper hero — wash and hairline become ink washes.
    var onPaper = false

    var body: some View {
        Image(systemName: symbol)
            .font(Typo.label)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: LayoutMetrics.s(size), height: LayoutMetrics.s(size))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(onPaper ? Papier.innenFill : Papier.nachtInnenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control,
                                         style: .continuous)
                            .strokeBorder(onPaper ? Papier.kante : Nacht.naht,
                                          lineWidth: Theme.hairlineWidth))
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Archivblatt (bounded empty sheet, iPad-Eval S1)

/// The Archiv's empty state as a BOUNDED archive sheet: a letter-paper
/// card carrying symbol, words and the wax-seal CTA, sitting at the top
/// of the READING column — never a bare empty state centered over the
/// whole detail pane (ipad-memories-de.png: the giant stock empty state
/// beside the sidebar). Ink family on paper (`Tinte.*`), the CTA is the
/// existing Siegellack `PrimaryButtonStyle` — no new material.
struct ArchivBlattEmptyState: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Tinte.sekundaer)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
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
        .paperCard(.brief)
        .contentColumn(.reading)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.xl)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Recent activity chip

/// One small night card in the horizontal recent-activity ribbon:
/// leading visual + kind label + one-line content + relative time.
/// Nachtkarton — text is the night family, the tint stays on the
/// leading visual.
struct RecentActivityChip<Leading: View>: View {
    let kind: String
    let text: String
    let time: String
    let tint: Color
    @ViewBuilder var leading: Leading

    var body: some View {
        HStack(spacing: Space.s) {
            leading
            VStack(alignment: .leading, spacing: 1) {
                Text(kind)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(text)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
                Text(time)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .padding(.vertical, Space.s)
        .padding(.horizontal, Space.m)
        .frame(maxWidth: LayoutMetrics.s(220), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.nachtkarton)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(PaperLightEdge.nachtGradient,
                                      lineWidth: Theme.hairlineWidth)
                )
                .elevation(.resting)
        )
    }
}

// MARK: - Section model

/// The sections of the Archiv hub. On compact widths they are the rows
/// inside the Schrankfront drawers (ENTSCHEID §4.4); on regular widths
/// they become the rows of the persistent sidebar (roadmap 17 — split
/// layout instead of stacked navigation). Symbols/titles mirror the old
/// cards exactly — SF Symbols, never emoji (commandment 1); the couple's
/// own emoji stay content. One case per line: `ArchivRulesTests` scans
/// this declaration to guarantee every section keeps a drawer.
enum MemoriesSection: String, CaseIterable, Identifiable {
    case coupons
    case soundtrack
    case gallery
    case videos
    case potd
    case lists
    case canvas
    case bucket
    case events
    case stats
    case journal
    case capsules
    case goals
    case weekplan
    case magazine
    case vault
    case story
    case yearReview
    // Neubau N4: the Chronik/Lagerfach newcomers — screens that lived
    // push-only in the Zustelldienst world join the cabinet.
    case weekReview
    case needsHistory
    case seasonCalendar

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .coupons: return "ticket.fill"
        case .soundtrack: return "music.note.list"
        case .gallery: return "photo.on.rectangle.angled"
        case .videos: return "film.fill"
        case .potd: return Icon.photo.rawValue
        case .lists: return "checklist"
        case .canvas: return Icon.canvas.rawValue
        case .bucket: return "wand.and.stars"
        case .events: return "calendar"
        case .stats: return "chart.bar.fill"
        case .journal: return "book.fill"
        case .capsules: return "envelope.fill"
        case .goals: return "target"
        case .weekplan: return "calendar.badge.clock"
        case .magazine: return "magazine.fill"
        case .vault: return Icon.secret.rawValue
        case .story: return "book.pages.fill"
        case .yearReview: return Icon.memory.rawValue
        case .weekReview: return "chart.bar.doc.horizontal"
        case .needsHistory: return "clock.arrow.circlepath"
        case .seasonCalendar: return "door.left.hand.closed"
        }
    }

    /// Reuses the card/screen title keys — the cabinet never invents
    /// new copy (only the needs history gets a contextful drawer label;
    /// its bare screen title „Verlauf" says nothing inside a drawer).
    var titleKey: String {
        switch self {
        case .yearReview: return "memories.card.yearreview"
        case .weekReview: return "weekreview.title"
        case .needsHistory: return "archiv.section.needsHistory"
        case .seasonCalendar: return "seasoncalendar.title"
        default: return "memories.card.\(rawValue)"
        }
    }
}
