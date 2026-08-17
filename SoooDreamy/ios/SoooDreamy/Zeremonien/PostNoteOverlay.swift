import SwiftUI

// FullRelease R1-D — „Die Post ist da": a delivered Zeitpost note arrives
// as a MOMENT instead of a toast. The twin of TouchReceivedOverlay (same
// layer, same a11y contract, same Reduce-Motion discipline): the room
// dims, a sealed envelope tips into the lamplight (Blättern signature),
// one tap breaks the couple's wax seal — the scene3 Siegelbruch beat —
// and the note unfolds in the written serif voice on letter paper.
//
// Accessibility contract (mirrors TouchReceivedOverlay): the overlay
// ANNOUNCES itself, the sealed envelope is ONE combined element with a
// named "break the seal" action, the opened note is ONE combined element
// (text + address line) next to a NAMED close button — the full-surface
// tap stays a sighted shortcut, never the only way out. Reduce Motion:
// the note appears statically opened. Closes by gesture, by button, and
// automatically 8 s after the note became readable.

/// R1-A consolidates the material wax-seal building block in UI/ in a
/// parallel wave — this alias is the ONE line to retarget when it lands;
/// the overlay itself never names the concrete seal type below here.
typealias PostNoteSealView = ChatWaxSealView

// MARK: - Sound + haptic score (Post & Sendungen moments)

/// The Post moments' own recognizable signature — RevealScore discipline:
/// a ceremony speaks through SoundEngine + Haptics directly (the one loud
/// moment rule), never through the rate-limited cue scheduler.
@MainActor
enum PostMomentScore {
    /// The postmark lands (Zeitpost send ceremony) — the Kino-Manifest
    /// stamp beat (scene2.haptics.json, t 5.2/5.34): one rigid tap
    /// 0.9/0.62, then the paper springs back 0.14 s later (0.32/0.2 —
    /// offset AND envelope straight from the manifest). `.sealed` is the
    /// stamp's voice.
    static func stamp() {
        SoundEngine.shared.play(cue: .sealed)
        Haptics.shared.play(events: [
            HapticEventSpec(t: 0.00, i: 0.90, s: 0.62),
            HapticEventSpec(t: 0.14, i: 0.32, s: 0.20, d: 0.16),
        ])
    }

    /// The wax cracks (note arrival) — the scene3-Manifest Siegelbruch
    /// beat: one heavy tap 1.0/0.55 plus two rebounds (the crack echo at
    /// +0.16 s from the manifest, then a soft paper settle). `.unseal`
    /// is its voice (CueKit's tear+shimmer pair, played directly here).
    static func sealBreak() {
        SoundEngine.shared.play(cue: .unseal)
        Haptics.shared.play(events: [
            HapticEventSpec(t: 0.00, i: 1.00, s: 0.55),
            HapticEventSpec(t: 0.16, i: 0.40, s: 0.50),
            HapticEventSpec(t: 0.34, i: 0.26, s: 0.30, d: 0.20),
        ])
    }
}

// MARK: - Local strings (CanvasExportSheet precedent)

/// The Post-moment copy lives NEXT to its views instead of in the shared
/// tables — the R1 waves run in parallel and must not collide there. Named
/// like `CanvasExportStrings` (NOT *L10n) so the L10nUsageTests source scan
/// keeps reading only the shared-table `L10n.t` call sites.
enum PostMomentStrings {
    static let table: [String: LText] = [
        "post.note.overlay.sealedA11y": LText(
            de: "Versiegelte Zeitpost von {name}. Siegel brechen, um sie zu lesen.",
            en: "A sealed timed post from {name}. Break the seal to read it."),
        "post.note.overlay.sealedHint": LText(
            de: "Tippen und das Siegel brechen",
            en: "Tap to break the seal"),
        "post.note.overlay.breakAction": LText(
            de: "Siegel brechen", en: "Break the seal"),
        "post.note.overlay.from": LText(
            de: "Von {name} · {ago} aufgegeben",
            en: "From {name} · posted {ago}"),
        "post.note.overlay.announce": LText(
            de: "Zeitpost von {name}: {text}",
            en: "Timed post from {name}: {text}"),
        "post.zeitpost.ceremony.skip": LText(
            de: "Weiter", en: "Continue"),
        "post.zeitpost.nudged": LText(
            de: "Die Ankunft war zu knapp geworden — sanft auf die nächste mögliche Zeit gerückt.",
            en: "That arrival had slipped too close — gently moved to the next possible time."),
    ]

    static func t(_ key: String, _ args: [String: String] = [:]) -> String {
        guard var s = table[key]?.resolved(L10n.lang) else { return key }
        for (k, v) in args {
            s = s.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return s
    }
}

// MARK: - The envelope building block

/// The little Zeitpost envelope — the SAME paper grammar as the cinema's
/// envelope scene (CinematicEnvelopeStage): brief paper, karton flap,
/// blank kante address lines. The arrival overlay presses the couple's
/// wax seal onto the flap tip; the send ceremony adds the postmark. The
/// rotation budget stays 1 per screen: only ONE detail tilts — the seal
/// (stable note-id seed) or the stamp (the cinema's stamp seed).
struct PostEnvelopeView: View {
    var sealed = false
    var stamped = false
    /// Seed for the seal's paperTilt — stable per note, so the seal
    /// keeps its tilt across renders (chat-seal discipline).
    var sealSeed: UInt64 = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(Papier.brief)
            EnvelopeFlapShape()
                .fill(Papier.karton)
                .frame(height: LayoutMetrics.s(58))
            VStack(alignment: .leading, spacing: Space.s) {
                Capsule().fill(Papier.kante)
                    .frame(width: LayoutMetrics.s(96), height: LayoutMetrics.s(6))
                Capsule().fill(Papier.kante)
                    .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.xl)
            .padding(.top, LayoutMetrics.s(76))
            if sealed {
                // The couple's wax on the flap tip — where a letter is
                // sealed. The tilt budget stays 1: the seal tilts only
                // when a seed is passed (arrival overlay); the send
                // ceremony leaves it straight — its stamp carries the
                // screen's one tilt instead.
                if sealSeed != 0 {
                    waxSeal
                        .paperTilt(seed: sealSeed)
                        .offset(y: LayoutMetrics.s(36))
                } else {
                    waxSeal
                        .offset(y: LayoutMetrics.s(36))
                }
            }
        }
        .frame(width: LayoutMetrics.s(232), height: LayoutMetrics.s(148))
        .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                    lineWidth: Theme.hairlineWidth))
        .overlay(alignment: .topTrailing) {
            if stamped {
                postmark
                    .offset(x: LayoutMetrics.s(14), y: -LayoutMetrics.s(14))
            }
        }
        .elevation(.resting)
    }

    private var waxSeal: some View {
        PostNoteSealView(size: LayoutMetrics.s(44),
                         emboss: .system(.footnote, design: .rounded).weight(.bold))
    }

    /// The postmark medallion — stamp-ink red ON paper (Wachs.rot is
    /// legal there), day line in the app's one small-caps role.
    private var postmark: some View {
        ZStack {
            Circle()
                .strokeBorder(Wachs.rot.opacity(0.85), lineWidth: Theme.hairlineWidth * 2)
            Text(L10n.t("post.station.zeitpost"))
                .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Wachs.rot)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, Space.xs)
        }
        .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
        .paperTilt(seed: 0x5231_4453_5441_4D50) // "R1DSTAMP" — the one tilt
    }
}

// MARK: - The arrival overlay

struct PostNoteOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let note: PostNote

    /// Blättern entrance done — the envelope stands in the lamplight.
    @State private var arrived = false
    /// The wax cracked (tap) — shards leave, the note unfolds next.
    @State private var sealBroken = false
    /// The note is readable — starts the 8 s auto-close window.
    @State private var opened = false
    @State private var openTask: Task<Void, Error>?
    @State private var autoCloseTask: Task<Void, Error>?
    @AccessibilityFocusState private var noteFocused: Bool

    private var senderName: String { appState.partnerName }

    private var fromLine: String {
        PostMomentStrings.t("post.note.overlay.from",
                         ["name": senderName,
                          "ago": L10n.relativeShort(note.createdAt)])
    }

    private var announcement: String {
        PostMomentStrings.t("post.note.overlay.announce",
                         ["name": senderName, "text": note.text])
    }

    var body: some View {
        ZStack {
            motionGate.scrim(0.6)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(22)) {
                if !opened {
                    sealedEnvelope
                        .transition(.opacity)
                } else {
                    notePaper
                        .transition(motionGate.reduceMotion
                                    ? .opacity
                                    : .opacity.combined(with: .scale(scale: 0.92)))
                    closeButton
                }
            }
            .padding(.horizontal, Space.xl)
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Sighted shortcut: the sealed tap IS the seal break, the
            // opened tap closes — never the only way (named a11y paths).
            if opened { close() } else { breakSeal() }
        }
        .animation(Theme.Motion.arrive, value: opened)
        .accessibilityAddTraits(.isModal)
        .onAppear { begin() }
        .onDisappear {
            openTask?.cancel()
            autoCloseTask?.cancel()
        }
    }

    // MARK: Sealed act

    private var sealedEnvelope: some View {
        VStack(spacing: LayoutMetrics.s(18)) {
            PostEnvelopeView(sealed: !sealBroken,
                             sealSeed: chatPaperSeed(note.id))
                // Blättern: the envelope tips in around its leading edge
                // (Signature degrees/perspective) — Reduce Motion skips
                // straight to the standing frame in begin().
                .rotation3DEffect(
                    .degrees(arrived ? 0 : Theme.Motion.Signature.blaetternDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: Theme.Motion.Signature.blaetternPerspective)
                .opacity(arrived ? 1 : 0)
            Text(PostMomentStrings.t("post.note.overlay.sealedHint"))
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PostMomentStrings.t("post.note.overlay.sealedA11y",
                                             ["name": senderName]))
        .accessibilityAction(named: PostMomentStrings.t("post.note.overlay.breakAction")) {
            breakSeal()
        }
    }

    // MARK: Opened act

    private var notePaper: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            // The note in the written serif voice — their words, dark ink
            // on letter paper (Typo.brief is paper-only by law).
            Text(note.text)
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // The address line in the SENDER's couple ink — authorship
            // as material, same ladder as the journal's ink edges.
            Text(fromLine)
                .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(coupleTint.tinteSecondary)
        }
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityFocused($noteFocused)
    }

    private var closeButton: some View {
        Button {
            close()
        } label: {
            Label(L10n.t("common.close"), systemImage: "xmark")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, LayoutMetrics.s(18))
                .padding(.vertical, LayoutMetrics.s(10))
                .glass(.chrome, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Choreography

    private func begin() {
        if motionGate.reduceMotion {
            // Statically opened — the story without the motion.
            arrived = true
            sealBroken = true
            opened = true
            afterOpen()
            return
        }
        withAnimation(Theme.Motion.blaettern) { arrived = true }
        AccessibilityNotification.Announcement(
            PostMomentStrings.t("post.note.overlay.sealedA11y", ["name": senderName])).post()
    }

    private func breakSeal() {
        guard !sealBroken else { return }
        sealBroken = true
        PostMomentScore.sealBreak()
        openTask = Task {
            // The shards leave first, then the paper unfolds — the same
            // two-beat order as the cinema's Siegelbruch.
            try await Task.sleep(nanoseconds: 350_000_000)
            opened = true
            afterOpen()
        }
    }

    private func afterOpen() {
        noteFocused = true
        AccessibilityNotification.Announcement(announcement).post()
        autoCloseTask = Task {
            try await Task.sleep(nanoseconds: 8_000_000_000)
            close()
        }
    }

    private func close() {
        openTask?.cancel()
        autoCloseTask?.cancel()
        appState.incomingPostNote = nil
    }
}
