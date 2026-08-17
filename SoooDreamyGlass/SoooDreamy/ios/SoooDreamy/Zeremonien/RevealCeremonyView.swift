import SwiftUI
import Observation

// The daily-answer reveal as a ceremony instead of a state flip (K-03):
// while both answers wait unseen, the card shows a sealed state; the tap
// opens this full-screen moment — wax seal, press-and-hold, three-act
// unveiling, reaction window. `RevealedDailyStore` (app-group) guarantees
// the ceremony fires exactly once per couple, day and device.

// MARK: - Ceremony controller

/// Presentation state of the reveal ceremony. RootView renders the overlay
/// while `moment` is set; the dashboard card re-reads the seal state via
/// `version`, which bumps the instant the seal breaks.
@MainActor
@Observable
final class RevealCeremony {
    static let shared = RevealCeremony()

    struct Moment: Equatable {
        let coupleId: String
        let dateKey: String
        let question: String
        /// "Diese Frage kam von {name}" — set on custom days once the
        /// author is public (server reveals it with `bothAnswered`).
        let questionAuthor: String?
        let myName: String
        let partnerName: String
        let myAnswer: String
        let partnerAnswer: String
        let streak: Int
        let firstReveal: Bool
    }

    private(set) var moment: Moment?
    /// Bumped on every seal change so SwiftUI re-reads `RevealedDailyStore`.
    private(set) var version = 0

    private init() {}

    /// Starts the ceremony for a both-answered entry. Politely refuses when
    /// this day was already revealed on this device — repeat visits get the
    /// calm end state, never a second confetti (Dossier 34, idea 28).
    func present(coupleId: String, dateKey: String, question: String,
                 questionAuthor: String?, myName: String, partnerName: String,
                 entry: DailyEntry) {
        guard moment == nil, entry.bothAnswered,
              !RevealedDailyStore.isRevealed(coupleId: coupleId, dateKey: dateKey) else { return }
        moment = Moment(
            coupleId: coupleId,
            dateKey: dateKey,
            question: question,
            questionAuthor: questionAuthor,
            myName: myName,
            partnerName: partnerName,
            myAnswer: entry.myAnswer ?? "",
            partnerAnswer: entry.partnerAnswer ?? "",
            streak: entry.streak,
            firstReveal: RevealedDailyStore.isFirstReveal(coupleId: coupleId)
        )
    }

    /// The seal broke — persist the one-time truth IMMEDIATELY, so an app
    /// kill mid-ceremony can never re-arm sound and confetti.
    func sealBroken() {
        guard let moment else { return }
        RevealedDailyStore.markRevealed(coupleId: moment.coupleId, dateKey: moment.dateKey)
        version += 1
    }

    func finish() {
        moment = nil
    }
}

// MARK: - Sound + haptic score

/// The ceremony's own recognizable signature (Dossier 34, idea 8) — used by
/// nothing else in the app, so the moment stays physically distinct.
@MainActor
enum RevealScore {
    /// Act 1 — the wax breaks: seal sound plus one sharp transient.
    static func sealBreak() {
        SoundEngine.shared.play(.letterSeal)
        Haptics.shared.play(events: [
            HapticEventSpec(t: 0.00, i: 1.0, s: 0.85, d: 0),
        ])
    }

    /// Act 2 — the answers rise: a quiet whoosh.
    static func unveil() {
        SoundEngine.shared.play(.whoosh)
    }

    /// Act 3 — both answers visible: two heartbeats (mine firm, theirs a
    /// touch softer) and the app-wide reveal shimmer.
    static func finale() {
        SoundEngine.shared.play(cue: .reveal)
        Haptics.shared.play(events: [
            HapticEventSpec(t: 0.00, i: 0.80, s: 0.30, d: 0),
            HapticEventSpec(t: 0.14, i: 0.55, s: 0.25, d: 0),
            HapticEventSpec(t: 0.55, i: 0.65, s: 0.28, d: 0),
            HapticEventSpec(t: 0.69, i: 0.45, s: 0.22, d: 0),
        ])
    }

    /// Rising tick while the thumb holds the seal.
    static func holdTick(progress: Double) {
        Haptics.shared.play(events: [
            HapticEventSpec(t: 0, i: 0.25 + 0.6 * progress, s: 0.5, d: 0),
        ])
    }
}

// MARK: - Full-screen ceremony

struct DailyRevealCeremonyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionGate) private var motionGate
    @Environment(\.coupleTint) private var coupleTint
    let moment: RevealCeremony.Moment

    private enum Act { case seal, unveiling, afterglow }

    @State private var act: Act = .seal
    @State private var holdProgress: Double = 0
    @State private var holdTask: Task<Void, Error>?
    @State private var shardsFlying = false
    @State private var showMine = false
    @State private var showTheirs = false
    @State private var unveilTask: Task<Void, Error>?
    @State private var sentReaction: String?
    @State private var bridgingToChat = false

    private var jackpot: Bool {
        DailyRevealLogic.isJackpot(mine: moment.myAnswer, theirs: moment.partnerAnswer)
    }

    private var echoWord: String? {
        DailyRevealLogic.sharedWord(mine: moment.myAnswer, theirs: moment.partnerAnswer)
    }

    var body: some View {
        ZStack {
            // Reduce Transparency: opaque night ink (MotionGate.scrim).
            motionGate.scrim(0.72)
                .ignoresSafeArea()
            if act == .afterglow {
                FloatingHeartsView(emojis: jackpot ? ["💞", "💜", "✨", "🩷"] : ["💜", "✨"],
                                   count: jackpot ? 24 : 10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            switch act {
            case .seal:
                sealAct
            case .unveiling, .afterglow:
                answersScroll
            }
        }
        .accessibilityAddTraits(.isModal)
        .animation(Theme.Motion.arrive, value: act)
        .onDisappear {
            holdTask?.cancel()
            unveilTask?.cancel()
        }
    }

    // MARK: Act 1 — the seal

    private var sealAct: some View {
        VStack(spacing: Space.xl) {
            // Solid ceremony gold — no gradient on text (DESIGN.md d);
            // the wax seal below already carries the golden shimmer.
            Text(moment.firstReveal ? L10n.t("reveal.firstTitle") : L10n.t("reveal.ready.title"))
                .font(Typo.hero)
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)

            if moment.firstReveal {
                Text(L10n.t("reveal.firstLine"))
                    .font(Typo.label)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.xl)
            }

            WaxSealView(progress: holdProgress, shattered: shardsFlying)
                .frame(width: LayoutMetrics.s(150), height: LayoutMetrics.s(150))
                .contentShape(Circle())
                .onLongPressGesture(minimumDuration: 0.9) {
                    breakSeal()
                } onPressingChanged: { pressing in
                    pressing ? beginHold() : cancelHold()
                }
                .accessibilityElement()
                .accessibilityLabel(L10n.t("reveal.seal.a11y"))
                .accessibilityAction(named: L10n.t("reveal.seal.action")) {
                    breakSeal()
                }

            Text(L10n.t("reveal.ready.hint"))
                .font(Typo.caption)
                .foregroundStyle(Theme.textTertiary)

            Button(L10n.t("common.cancel")) {
                RevealCeremony.shared.finish()
            }
            .buttonStyle(.plain)
            .font(Typo.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, Space.l)
            .minimumHitTarget()
        }
        .padding(Space.xxl)
        // The ceremony stays an intimate centered column on iPad windows.
        .contentColumn(.reading)
    }

    private func beginHold() {
        guard act == .seal else { return }
        withAnimation(Theme.Motion.drift(0.9)) { holdProgress = 1 }
        holdTask?.cancel()
        holdTask = Task {
            // A finer and finer vibration while the wax gives way —
            // cancellation (finger lifted) throws out of the loop.
            for step in 1...5 {
                try await Task.sleep(nanoseconds: 160_000_000)
                RevealScore.holdTick(progress: Double(step) / 5)
            }
        }
    }

    private func cancelHold() {
        guard act == .seal, !shardsFlying else { return }
        holdTask?.cancel()
        withAnimation(Theme.Motion.settle) { holdProgress = 0 }
    }

    private func breakSeal() {
        guard act == .seal else { return }
        holdTask?.cancel()
        // Persist FIRST — the one-time semantics never depend on the view
        // surviving to the end of the animation.
        RevealCeremony.shared.sealBroken()
        RevealScore.sealBreak()
        if reduceMotion {
            act = .unveiling
            revealSequence(instant: true)
        } else {
            shardsFlying = true
            Task {
                try await Task.sleep(nanoseconds: 450_000_000)
                act = .unveiling
                revealSequence(instant: false)
            }
        }
        announceCeremony()
    }

    // MARK: Act 2+3 — answers & afterglow

    private var answersScroll: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Text(moment.question)
                    .font(Typo.title)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.xxl)

                if showMine {
                    VStack(alignment: .trailing, spacing: Space.xs) {
                        Text(L10n.t("reveal.mineWhen"))
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textTertiary)
                        RevealAnswerBubble(name: moment.myName, text: moment.myAnswer,
                                           tint: coupleTint.secondary, mine: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if showTheirs {
                    RevealAnswerBubble(name: moment.partnerName, text: moment.partnerAnswer,
                                       tint: coupleTint.primary, mine: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if act == .afterglow {
                    afterglow
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(Space.xl)
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            skipToAfterglow()
        }
    }

    /// Question first, my memory of the morning second, the partner's answer
    /// as the point — a tap skips straight to the end state.
    private func revealSequence(instant: Bool) {
        if instant {
            showMine = true
            showTheirs = true
            act = .afterglow
            finale()
            return
        }
        RevealScore.unveil()
        // Cancellation (skip tap) throws out of the sequence mid-way.
        unveilTask = Task {
            try await Task.sleep(nanoseconds: 400_000_000)
            withAnimation(Theme.Motion.arrive) { showMine = true }
            try await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(Theme.Motion.arrive) { showTheirs = true }
            try await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(Theme.Motion.arrive) { act = .afterglow }
            finale()
        }
    }

    private func skipToAfterglow() {
        guard act == .unveiling else { return }
        unveilTask?.cancel()
        withAnimation(Theme.Motion.settle) {
            showMine = true
            showTheirs = true
            act = .afterglow
        }
        finale()
    }

    private func finale() {
        RevealScore.finale()
        // Jackpot and a streak milestone can land in the same breath — the
        // arbiter bundles them into ONE celebration (the bigger request
        // leads, one fanfare) and applies the app-wide big budget:
        // degraded to medium when the window is spent, never silenced.
        if jackpot {
            Delight.celebrate(DelightArbiterStore.request(.revealJackpot), theme: .hearts)
        } else if let wanted = DelightRules.milestone(forStreak: moment.streak) {
            let granted = wanted == .epic
                ? DelightArbiterStore.request(.streakMilestone)
                : wanted
            Delight.celebrate(granted, theme: .stars)
        }
    }

    private var afterglow: some View {
        VStack(spacing: Space.m) {
            if jackpot {
                celebrationBanner(title: L10n.t("reveal.jackpot.title"),
                                  line: L10n.t("reveal.jackpot.line"))
            } else if let word = echoWord {
                celebrationBanner(title: L10n.t("reveal.echo.title"),
                                  line: L10n.t("reveal.echo.line", ["word": word]))
            }

            if let author = moment.questionAuthor {
                Text(L10n.t("reveal.customAuthor", ["name": author]))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.gold)
            }

            if moment.streak > 1 {
                SharedDaysPill(days: moment.streak)
            }

            reactionRow

            Button {
                bridgeToChat()
            } label: {
                Label(L10n.t("reveal.talk"), systemImage: "bubble.left.and.bubble.right.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(bridgingToChat)

            Button(L10n.t("reveal.close")) {
                RevealCeremony.shared.finish()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, Space.s)
    }

    private func celebrationBanner(title: String, line: String) -> some View {
        VStack(spacing: Space.xs) {
            Text(title)
                .font(Typo.title)
                .foregroundStyle(Theme.gold)
            Text(line)
                .font(Typo.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.m)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.gold.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Theme.gold.opacity(0.5), lineWidth: Theme.hairlineWidth)
                )
        )
    }

    // MARK: Reaction window (Dossier 34, idea 7)

    private static let reactions = ["🥹", "❤️", "😂", "😮"]

    private var reactionRow: some View {
        HStack(spacing: Space.m) {
            Text(L10n.t("reveal.react.title"))
                .font(Typo.caption)
                .foregroundStyle(Theme.textSecondary)
            ForEach(Self.reactions, id: \.self) { emoji in
                Button {
                    sendReaction(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(.title2))
                        .frame(width: LayoutMetrics.s(42), height: LayoutMetrics.s(42))
                        .background(
                            Circle().fill(sentReaction == emoji
                                          ? coupleTint.blend.opacity(0.35)
                                          : Theme.innerFill)
                        )
                        .overlay(
                            Circle().strokeBorder(sentReaction == emoji ? coupleTint.blend
                                                                        : Theme.hairline,
                                                  lineWidth: Theme.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)
                .disabled(sentReaction != nil)
                .accessibilityLabel(L10n.t("reveal.react.a11y", ["emoji": emoji]))
            }
        }
    }

    /// One-tap reaction lands as a tiny chat message — reacting inside the
    /// warm moment instead of "later, maybe".
    private func sendReaction(_ emoji: String) {
        guard sentReaction == nil, let api = appState.api else { return }
        sentReaction = emoji
        Haptics.shared.tap()
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: emoji)
                SoundEngine.shared.play(.pop)
                appState.showToast(L10n.t("reveal.react.sent"), style: .love)
            } catch {
                sentReaction = nil
                appState.handleAPIError(error)
            }
        }
    }

    /// "Darüber reden" — conserves the Q&A in the chat and jumps there.
    private func bridgeToChat() {
        guard !bridgingToChat, let api = appState.api else { return }
        bridgingToChat = true
        Haptics.shared.tap()
        let text = L10n.t("home.dailyShareHeader") + " "
            + moment.question + "\n"
            + "\(moment.myName): \(moment.myAnswer)" + "\n"
            + "\(moment.partnerName): \(moment.partnerAnswer)"
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: text)
                RevealCeremony.shared.finish()
                appState.activeTab = .chat
            } catch {
                appState.handleAPIError(error)
            }
            bridgingToChat = false
        }
    }

    // MARK: VoiceOver choreography (Dossier 34, idea 17)

    /// The order of the announcements IS the ceremony for VoiceOver users:
    /// seal broken, your answer, their answer, then the twin moment.
    private func announceCeremony() {
        var lines = [
            L10n.t("reveal.a11y.bothAnswered"),
            L10n.t("reveal.a11y.mine", ["text": moment.myAnswer]),
            L10n.t("reveal.a11y.theirs", ["name": moment.partnerName,
                                          "text": moment.partnerAnswer]),
        ]
        if jackpot {
            lines.append(L10n.t("reveal.jackpot.line"))
        }
        Task {
            for (index, line) in lines.enumerated() {
                if index > 0 {
                    try await Task.sleep(nanoseconds: 1_400_000_000)
                }
                AccessibilityNotification.Announcement(line).post()
            }
        }
    }
}

// MARK: - Wax seal

/// The couple's wax seal — the loved letter metaphor carried to the daily
/// question. Pressure whitens the rim; at 100 % it springs into shards.
struct WaxSealView: View {
    let progress: Double
    let shattered: Bool

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        ZStack {
            if !shattered {
                seal
                    .scaleEffect(1 + 0.06 * progress)
            } else {
                SealShardsView()
            }
        }
    }

    private var seal: some View {
        Circle()
            .fill(
                LinearGradient(colors: [Theme.gold, coupleTint.blend],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                Image(systemName: "heart.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            )
            .overlay(
                Circle()
                    .strokeBorder(Theme.textPrimary, lineWidth: 2 + 3 * progress)
                    .opacity(0.35 + 0.5 * progress)
            )
            .shadow(color: Theme.gold.opacity(0.55), radius: LayoutMetrics.s(20))
    }
}

/// Six wax shards flying apart on the break — a short, single-shot burst.
private struct SealShardsView: View {
    @State private var flying = false
    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * 2 * .pi
                Circle()
                    .fill(
                        LinearGradient(colors: [Theme.gold, coupleTint.blend],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                    .offset(x: flying ? CGFloat(cos(angle)) * LayoutMetrics.s(90) : 0,
                            y: flying ? CGFloat(sin(angle)) * LayoutMetrics.s(90) : 0)
                    .opacity(flying ? 0 : 1)
            }
        }
        .onAppear {
            withAnimation(Theme.Motion.playful) { flying = true }
        }
    }
}

// MARK: - Answer bubble (opposite voices, not a form)

/// My answer sits right, the partner's left — two voices facing each other
/// like in the chat (Dossier 34, idea 15), each washed in one of the
/// couple's OWN palette colors instead of stock pink/purple (EVAL P1-2).
/// Long answers fold after six lines and open on tap (idea 16).
struct RevealAnswerBubble: View {
    let name: String
    let text: String
    let tint: Color
    let mine: Bool

    @State private var expanded = false

    private var isLong: Bool { text.count > 240 }

    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: Space.xs) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
            Text(text)
                .font(Typo.body)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(expanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(mine ? .trailing : .leading)
            if isLong && !expanded {
                Button(L10n.t("reveal.readAll")) {
                    withAnimation(Theme.Motion.settle) { expanded = true }
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundStyle(tint)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: LayoutMetrics.s(300), alignment: mine ? .trailing : .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(tint.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(tint.opacity(0.4), lineWidth: Theme.hairlineWidth)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sealed-state glow (card announcement, Dossier 34, idea 4)

/// A slowly breathing gold rim on the daily card while a reveal waits —
/// the quiet second channel next to the push. Static under Reduce Motion.
struct RevealGlowBorder: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    func body(content: Content) -> some View {
        content
            .overlay(
                // Lamp-gold glow BEHIND the paper edge — the one legal role
                // of gold near paper; radius matches the paper cut now.
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(reduceMotion ? 0.6 : (breathing ? 0.75 : 0.3)),
                                  lineWidth: 1.5)
            )
            .shadow(color: Theme.gold.opacity(reduceMotion ? 0.25 : (breathing ? 0.4 : 0.12)),
                    radius: LayoutMetrics.s(12))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Theme.Motion.drift(2.4).repeatForever(autoreverses: true)) {
                    breathing = true
                }
            }
    }
}

extension View {
    func revealGlow() -> some View {
        modifier(RevealGlowBorder())
    }
}

// MARK: - Shared-days pill (streak reframing, Dossier 02, idea 1)

/// "37 gemeinsame Tage" instead of a fire counter — a biography number,
/// not a game score. One symbol system-wide.
struct SharedDaysPill: View {
    let days: Int
    /// True when the pill sits on a paper card: label becomes dark ink,
    /// the heart becomes seal wax — gold never writes on paper (1.4:1).
    /// The warm gold wash stays as MATERIAL behind the ink.
    var onPaper: Bool = false

    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "heart.circle.fill")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(onPaper ? Wachs.rot : Theme.gold)
            Text(L10n.t("home.sharedDays", count: days))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(onPaper ? Tinte.dunkel : Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(Theme.Motion.settle, value: days)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, LayoutMetrics.s(11))
        .background(
            Capsule()
                .fill(Theme.gold.opacity(0.22))
                .overlay(Capsule().strokeBorder(onPaper ? Papier.kante
                                                        : Theme.gold.opacity(0.4),
                                                lineWidth: Theme.hairlineWidth))
        )
        .accessibilityElement(children: .combine)
    }
}
