import SwiftUI

/// The writing workshop of the letter composer: "Schreibblockade?"
/// offers three distinct openings in a chosen tone, "Sag es sanft" a
/// gentler rewording of the current draft. Lives in the composer (not the
/// chat input bar) because this is where long, meaningful text is written
/// — the chat bar is dense floating chrome with no room for a workshop.
///
/// Nacht-first (P2-B): the workshop is a NIGHT CARD below the letter
/// paper — the machine's suggestions are workshop tooling, not part of
/// the correspondence artifact. It carries its own `nightCard()` so the
/// composer never renders an empty card shell when Apple Intelligence is
/// unavailable.
///
/// Renders NOTHING on devices without available Apple Intelligence (no
/// dead buttons — Settings carries the honest reason). Every result is a
/// draft: it only enters the letter through an explicit tap, and the
/// composer alone decides about sending.
struct LetterWorkshopView: View {
    @Binding var letterText: String
    /// Mirrors the composer's sending/sent lock.
    var disabled: Bool = false

    @Environment(\.coupleTint) private var coupleTint

    private enum Phase: Equatable {
        /// Panel open, tone picker waiting — the workshop's empty state.
        case openersIdle
        case openersGenerating
        case openers([String])
        case softenGenerating
        case soften(String)
        /// key = honest copy (failed/guardrail); retry re-runs the target.
        case failed(key: String, retry: RetryTarget)
    }

    private enum RetryTarget: Equatable {
        case openers
        case soften
    }

    /// nil = panel closed; the entry chips are the only visible trace.
    @State private var phase: Phase?
    @State private var tone: IntelligenceTone = .tender
    @State private var showConsent = false
    /// Remembered across the consent sheet so a grant continues the tap.
    @State private var pendingTarget: RetryTarget?
    @State private var generationTask: Task<Void, Never>?

    private var trimmedDraft: String {
        letterText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // Availability is re-read on every render — the entry hides the
        // moment Apple Intelligence goes away (honesty over persistence).
        if Intelligence.shared.featureVisible {
            VStack(alignment: .leading, spacing: Space.m) {
                entryRow
                if let phase {
                    panel(for: phase)
                }
            }
            .nightCard(padding: .compact)
            .animation(Theme.Motion.settle, value: phase)
            .sheet(isPresented: $showConsent, onDismiss: { pendingTarget = nil }) {
                IntelligenceConsentSheet { granted in
                    guard granted, let target = pendingTarget else {
                        pendingTarget = nil
                        return
                    }
                    pendingTarget = nil
                    resume(target)
                }
                .presentationDetents([.medium, .large])
            }
            .onDisappear {
                generationTask?.cancel()
            }
        }
    }

    // MARK: Entry chips

    private var entryRow: some View {
        HStack(spacing: Space.s) {
            entryChip(icon: "sparkles",
                      title: L10n.t("ai.workshop.entry"),
                      a11y: L10n.t("ai.workshop.entryA11y"),
                      active: isOpenersPhase) {
                toggleOpeners()
            }
            if !trimmedDraft.isEmpty {
                entryChip(icon: "wand.and.sparkles",
                          title: L10n.t("ai.soften.entry"),
                          a11y: L10n.t("ai.soften.entryA11y"),
                          active: isSoftenPhase) {
                    requestSoften()
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var isOpenersPhase: Bool {
        switch phase {
        case .openersIdle, .openersGenerating, .openers: return true
        case .failed(_, let retry): return retry == .openers
        default: return false
        }
    }

    private var isSoftenPhase: Bool {
        switch phase {
        case .softenGenerating, .soften: return true
        case .failed(_, let retry): return retry == .soften
        default: return false
        }
    }

    private func entryChip(icon: String, title: String, a11y: String,
                           active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: icon)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            // Night-card inks (MIGRATION_DUNKEL §4): aufNacht when active,
            // the quiet night step otherwise; the selection ring/wash is
            // the couple blend (non-text, ≥3:1 pinned).
            .foregroundStyle(active ? Papier.aufNacht : Nacht.sekundaer)
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            .background(
                Capsule()
                    .fill(active ? AnyShapeStyle(coupleTint.blend.opacity(0.18))
                                 : AnyShapeStyle(Papier.nachtInnenFill))
                    .overlay(
                        Capsule().strokeBorder(active ? AnyShapeStyle(coupleTint.blend)
                                                      : AnyShapeStyle(Nacht.naht),
                                               lineWidth: Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(a11y)
    }

    // MARK: Panel

    private func panel(for phase: Phase) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                // Section label on the night card: the quiet night step.
                Text(panelTitle(for: phase))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                Spacer(minLength: 0)
                OnDeviceBadge()
            }

            switch phase {
            case .openersIdle:
                openersIdleContent
            case .openersGenerating:
                skeletonLines
            case .openers(let openers):
                openersContent(openers)
            case .softenGenerating:
                GlassSkeleton(kind: .card(height: 96))
                    .background(RoundedRectangle(cornerRadius: Radius.card,
                                                 style: .continuous)
                        .fill(Papier.nachtInnenFill))
            case .soften(let suggestion):
                softenContent(suggestion)
            case .failed(let key, let retry):
                failedContent(key: key, retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A section of the workshop card, not a card glued underneath:
        // the night seam separates it from the entry chips (one material).
        .padding(.top, Space.m)
        .overlay(alignment: .top) { Divider().overlay(Nacht.naht) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func panelTitle(for phase: Phase) -> String {
        switch phase {
        case .softenGenerating, .soften: return L10n.t("ai.soften.title")
        case .failed(_, .soften): return L10n.t("ai.soften.title")
        default: return L10n.t("ai.workshop.title")
        }
    }

    // MARK: Openers states

    private var openersIdleContent: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L10n.t("ai.workshop.pick"))
                .font(Typo.caption)
                .foregroundStyle(Nacht.sekundaer)
            toneRow
            // Night action instead of SecondaryButtonStyle: that style is
            // real glass — glass may not float on paper, and nachtkarton
            // IS paper (Zwei-Materialien-Gesetz).
            Button {
                start(.openers)
            } label: {
                Label(L10n.t("ai.workshop.generate"), systemImage: "sparkles")
            }
            .buttonStyle(NightActionButtonStyle())
            .disabled(disabled)
        }
    }

    private var toneRow: some View {
        HStack(spacing: Space.s) {
            ForEach(IntelligenceTone.allCases, id: \.rawValue) { candidate in
                toneChip(candidate)
            }
        }
    }

    private func toneChip(_ candidate: IntelligenceTone) -> some View {
        let selected = tone == candidate
        return Button {
            Haptics.shared.tap()
            tone = candidate
        } label: {
            Text(L10n.t(candidate.titleKey))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.m)
                .background(
                    Capsule()
                        .fill(selected ? AnyShapeStyle(coupleTint.blend.opacity(0.18))
                                       : AnyShapeStyle(Papier.nachtInnenFill))
                        .overlay(
                            Capsule().strokeBorder(selected ? AnyShapeStyle(coupleTint.blend)
                                                            : AnyShapeStyle(Nacht.naht),
                                                   lineWidth: Theme.hairlineWidth)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Waiting in the shape of what arrives: three opening lines. A
    /// nachtInnenFill capsule under each skeleton line keeps the wash
    /// visible on the dark card (Tinte-based innenFill drowns there).
    private var skeletonLines: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            GlassSkeleton(kind: .line(width: LayoutMetrics.s(230)))
                .background(Capsule().fill(Papier.nachtInnenFill))
            GlassSkeleton(kind: .line(width: LayoutMetrics.s(260)))
                .background(Capsule().fill(Papier.nachtInnenFill))
            GlassSkeleton(kind: .line(width: LayoutMetrics.s(200)))
                .background(Capsule().fill(Papier.nachtInnenFill))
        }
    }

    private func openersContent(_ openers: [String]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(openers, id: \.self) { opener in
                Button {
                    adoptOpener(opener)
                } label: {
                    HStack(alignment: .top, spacing: Space.s) {
                        Text(opener)
                            .font(Typo.body)
                            .foregroundStyle(Papier.aufNacht)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down.doc")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Licht.lampengold)
                            .accessibilityHidden(true)
                    }
                    .padding(Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.nachtInnenFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityHint(L10n.t("ai.workshop.useOpenerA11y"))
            }
            Button {
                start(.openers)
            } label: {
                Label(L10n.t("ai.workshop.regenerate"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(Typo.caption)
            // Accent text on night speaks lamplight (§4).
            .foregroundStyle(Licht.lampengold)
            .disabled(disabled)
            .minimumHitTarget()
        }
    }

    // MARK: Soften states

    private func softenContent(_ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(suggestion)
                .font(Typo.body)
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Papier.nachtInnenFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                        )
                )
            // caption2 sits below the tertiary size floor — the hint
            // takes the secondary night step.
            Text(L10n.t("ai.soften.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
            HStack(spacing: Space.m) {
                Button {
                    adoptSoftened(suggestion)
                } label: {
                    Text(L10n.t("ai.soften.use"))
                }
                .buttonStyle(NightActionButtonStyle())
                .disabled(disabled)
                Button(L10n.t("ai.soften.keep")) {
                    Haptics.shared.tap()
                    phase = nil
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(Nacht.sekundaer)
                .minimumHitTarget()
            }
        }
    }

    // MARK: Failure state

    private func failedContent(key: String, retry: RetryTarget) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L10n.t(key))
                .font(Typo.caption)
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                start(retry)
            } label: {
                Label(L10n.t("common.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(NightActionButtonStyle())
            .disabled(disabled)
        }
    }

    // MARK: Flow

    private func toggleOpeners() {
        if isOpenersPhase {
            generationTask?.cancel()
            phase = nil
            return
        }
        guard consentSettled(for: .openers) else { return }
        // A still-running soften request must not overwrite this panel.
        generationTask?.cancel()
        phase = .openersIdle
    }

    private func requestSoften() {
        if isSoftenPhase {
            generationTask?.cancel()
            phase = nil
            return
        }
        guard consentSettled(for: .soften) else { return }
        start(.soften)
    }

    /// First contact: without a grant the consent sheet takes over and
    /// resumes the tapped feature on "yes". Declined earlier? The sheet
    /// simply asks again — a way back in instead of a dead chip.
    private func consentSettled(for target: RetryTarget) -> Bool {
        guard IntelligenceConsentRules.needsConsentSheet(Intelligence.shared.consent) else {
            return true
        }
        pendingTarget = target
        showConsent = true
        return false
    }

    /// Continues the feature the person tapped BEFORE the consent sheet:
    /// openers land on the tone picker (choosing the tone is part of the
    /// flow), the rephrase generates right away (its input is the draft).
    private func resume(_ target: RetryTarget) {
        switch target {
        case .openers:
            generationTask?.cancel()
            phase = .openersIdle
        case .soften:
            start(.soften)
        }
    }

    private func start(_ target: RetryTarget) {
        generationTask?.cancel()
        switch target {
        case .openers:
            phase = .openersGenerating
            let chosenTone = tone
            generationTask = Task {
                do {
                    let openers = try await Intelligence.shared.letterOpeners(tone: chosenTone)
                    guard !Task.isCancelled else { return }
                    phase = .openers(openers)
                    announceArrival(key: "ai.workshop.readyA11y")
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else { return }
                    phase = .failed(key: Self.copyKey(for: error), retry: .openers)
                }
            }
        case .soften:
            phase = .softenGenerating
            let draft = trimmedDraft
            generationTask = Task {
                do {
                    let softened = try await Intelligence.shared.gentleRephrase(of: draft)
                    guard !Task.isCancelled else { return }
                    phase = .soften(softened)
                    announceArrival(key: "ai.soften.readyA11y")
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else { return }
                    phase = .failed(key: Self.copyKey(for: error), retry: .soften)
                }
            }
        }
    }

    private static func copyKey(for error: Error) -> String {
        (error as? IntelligenceError)?.l10nKey ?? "ai.workshop.failed"
    }

    /// VoiceOver hears the arrival the moment sighted eyes see it.
    private func announceArrival(key: String) {
        Haptics.shared.tap()
        AccessibilityNotification.Announcement(L10n.t(key)).post()
    }

    // MARK: Adoption (the ONLY paths into the letter)

    /// An opening belongs at the top: empty drafts become the opener,
    /// existing text keeps everything and gains the opener above it.
    private func adoptOpener(_ opener: String) {
        Haptics.shared.tap()
        if trimmedDraft.isEmpty {
            letterText = opener
        } else {
            letterText = opener + "\n\n" + letterText
        }
        phase = nil
    }

    private func adoptSoftened(_ suggestion: String) {
        Haptics.shared.tap()
        letterText = suggestion
        phase = nil
    }
}

// MARK: - Night action button (workshop-local)

/// The night twin of `PaperActionButtonStyle` for actions ON a night
/// card: aufNacht-wash capsule with the `Nacht.naht` seam, label in
/// lamplight (accent-TEXT rule, MIGRATION_DUNKEL §4). SecondaryButtonStyle
/// is real glass and may not float on paper — nachtkarton included.
private struct NightActionButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Licht.lampengold)
            .padding(.vertical, LayoutMetrics.s(10))
            .padding(.horizontal, LayoutMetrics.s(16))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(
                Capsule().fill(Papier.nachtInnenFill)
                    .overlay(Capsule().strokeBorder(Nacht.naht,
                                                    lineWidth: Theme.hairlineWidth))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.settle, value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}
