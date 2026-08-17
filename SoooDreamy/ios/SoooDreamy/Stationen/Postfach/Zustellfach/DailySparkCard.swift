import SwiftUI

/// One persisted spark per pair and day (FX-O #8): the follow-up question
/// must survive scrolling, tab switches and app restarts — a delight that
/// vanishes teaches people not to invest in it. A single key means
/// yesterday's spark prunes itself when today's is saved.
enum DailySparkStore {
    struct Saved: Codable, Equatable {
        var coupleId: String
        var dateKey: String
        var text: String
        var retriesUsed: Int
    }

    private static let key = "ai.spark.today.v1"

    static func load(coupleId: String, dateKey: String,
                     defaults: UserDefaults = .standard) -> Saved? {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              saved.coupleId == coupleId, saved.dateKey == dateKey else { return nil }
        return saved
    }

    static func save(_ saved: Saved, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        defaults.set(data, forKey: key)
    }
}

/// "Gemeinsamer Funke" — once both daily answers are revealed, the couple
/// can ask their iPhone for ONE follow-up question built from both
/// answers. Lives in the daily card's calm end state on the dashboard
/// (not in the reveal ceremony: the ceremony is a tight three-act
/// choreography, while this end state stays on screen all day). Entirely
/// client-side — the server never sees a byte of it — and renders only
/// on devices where Apple Intelligence is available.
struct DailySparkCard: View {
    let question: String
    let myName: String
    let myAnswer: String
    let partnerName: String
    let partnerAnswer: String

    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    private enum Phase: Equatable {
        case idle
        case generating
        case spark(String)
        /// The honest failure line — answers untouched, retry offered.
        case failed(key: String)
    }

    @State private var phase: Phase = .idle
    @State private var showConsent = false
    @State private var generationTask: Task<Void, Never>?
    /// Exactly ONE deliberate re-roll per pair and day keeps the spark
    /// precious. Error retries (failed phase) never count against it.
    @State private var retriesUsed = 0

    var body: some View {
        // Inner section of the daily PAPER card — ink washes with kante
        // hairlines only, never a second material (Papier & Licht).
        if Intelligence.shared.featureVisible {
            VStack(alignment: .leading, spacing: Space.s) {
                switch phase {
                case .idle:
                    entryButton
                case .generating:
                    header
                    PaperSkeleton(kind: .line(width: LayoutMetrics.s(240)))
                case .spark(let sparkQuestion):
                    header
                    sparkContent(sparkQuestion)
                case .failed(let key):
                    header
                    failedContent(key: key)
                }
            }
            .animation(Theme.Motion.settle, value: phase)
            .sheet(isPresented: $showConsent) {
                IntelligenceConsentSheet { granted in
                    if granted {
                        generate()
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear { restore() }
            .onDisappear {
                generationTask?.cancel()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "sparkles")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.tinte)
                .accessibilityHidden(true)
            Text(L10n.t("ai.spark.title"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.tinte)
            Spacer(minLength: 0)
            OnDeviceBadge()
        }
    }

    /// The quiet invitation — one row, no glow, no competition with the
    /// reveal that just happened.
    private var entryButton: some View {
        Button {
            Haptics.shared.tap()
            requestSpark()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "sparkles")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.tinte)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("ai.spark.title"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.dunkel)
                    Text(L10n.t("ai.spark.hint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Tinte.tertiaer)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text(L10n.t("ai.spark.generate"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(coupleTint.tinte)
            }
            .padding(Space.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.innenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(L10n.t("ai.spark.hint"))
    }

    private func sparkContent(_ sparkQuestion: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(sparkQuestion)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.dunkel)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(coupleTint.tinte.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .strokeBorder(coupleTint.tinte.opacity(0.4),
                                              lineWidth: Theme.hairlineWidth)
                        )
                )
            if retriesUsed == 0 {
                Button {
                    Haptics.shared.tap()
                    retriesUsed = 1
                    generate()
                } label: {
                    Label(L10n.t("ai.spark.again"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(coupleTint.tinte)
                .minimumHitTarget()
            } else {
                // The one re-roll is spent — say so instead of hiding the
                // control wordlessly.
                Text(L10n.t("ai.spark.kept"))
                    .font(Typo.caption)
                    .foregroundStyle(Tinte.tertiaer)
            }
        }
    }

    private func failedContent(key: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.t(key))
                .font(Typo.caption)
                .foregroundStyle(Tinte.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Haptics.shared.tap()
                generate()
            } label: {
                Label(L10n.t("common.retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .font(Typo.caption)
            .foregroundStyle(coupleTint.tinte)
            .minimumHitTarget()
        }
    }

    // MARK: Flow

    /// First contact runs through the consent sheet; afterwards taps
    /// generate directly. A decline keeps the invitation row — the sheet
    /// simply asks again next time.
    private func requestSpark() {
        if IntelligenceConsentRules.needsConsentSheet(Intelligence.shared.consent) {
            showConsent = true
        } else {
            generate()
        }
    }

    private func generate() {
        generationTask?.cancel()
        phase = .generating
        generationTask = Task {
            do {
                let spark = try await Intelligence.shared.dailySpark(
                    question: question, myName: myName, myAnswer: myAnswer,
                    partnerName: partnerName, partnerAnswer: partnerAnswer)
                guard !Task.isCancelled else { return }
                phase = .spark(spark)
                persist(spark)
                Haptics.shared.tap()
                AccessibilityNotification.Announcement(spark).post()
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                let key = (error as? IntelligenceError) == .guardrail
                    ? "ai.workshop.guardrail" : "ai.spark.failed"
                phase = .failed(key: key)
            }
        }
    }

    // MARK: Persistence (one spark per pair/day)

    /// A spark generated earlier today comes back exactly as it was —
    /// including whether the one re-roll is already spent.
    private func restore() {
        guard case .idle = phase, let coupleId = appState.couple?.id,
              let saved = DailySparkStore.load(coupleId: coupleId,
                                               dateKey: SharedDates.todayKey()) else { return }
        retriesUsed = saved.retriesUsed
        phase = .spark(saved.text)
    }

    /// Persist only successes: a failed re-roll leaves today's earlier
    /// spark on disk, so leaving and coming back returns the last good
    /// question (and the unspent retry).
    private func persist(_ spark: String) {
        guard let coupleId = appState.couple?.id else { return }
        DailySparkStore.save(.init(coupleId: coupleId,
                                   dateKey: SharedDates.todayKey(),
                                   text: spark,
                                   retriesUsed: retriesUsed))
    }
}
