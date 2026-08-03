import SwiftUI

/// The classic "36 questions to fall in love" — one phone between the two
/// of you. Pick a set (3 × 12 questions), read each question out loud and
/// both answer. The finish screen suggests the famous 4 minutes of eye
/// contact with a built-in countdown.
struct Questions36View: View {
    private enum Stage {
        case setup, deck, finish
    }

    private static let eyeContactSeconds = 240

    @State private var stage: Stage = .setup
    @State private var selectedSet = 1
    @State private var index = 0
    @State private var goingForward = true

    // Eye-contact countdown
    @State private var remaining = Questions36View.eyeContactSeconds
    @State private var timerRunning = false
    @State private var timerDone = false
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if timerDone {
                FloatingHeartsView(emojis: ["💜", "💖", "✨", "🥹"], count: 22)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.questions36.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            timerTask?.cancel()
        }
    }

    // MARK: Data

    private var questions: [Question36] {
        ContentPack.questions36
            .filter { $0.set == selectedSet }
            .sorted { $0.id < $1.id }
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .setup:
            setupScreen
        case .deck:
            deckScreen
        case .finish:
            finishScreen
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text("💫")
                    .font(.scaled(56))
                Text(L10n.t("games.card.questions36.title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("games.q36.intro"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    setRow(set: 1, emoji: "🌱")
                    setRow(set: 2, emoji: "🌊")
                    setRow(set: 3, emoji: "🔥")
                }
                Button {
                    startDeck()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private func setRow(set: Int, emoji: String) -> some View {
        let selected = selectedSet == set
        return Button {
            selectedSet = set
            Haptics.shared.tap()
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                Text(emoji)
                    .font(.scaled(26))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("games.q36.set", ["n": String(set)]))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.t("games.q36.set\(set)"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.blue : Theme.textTertiary)
            }
            .padding(LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.blue.opacity(0.18) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Theme.blue : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func startDeck() {
        index = 0
        goingForward = true
        stage = .deck
        SoundEngine.shared.play(.pop)
        Haptics.shared.tap()
    }

    // MARK: Deck

    private var deckScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                VStack(spacing: 8) {
                    Text(L10n.t("games.q36.progress",
                                ["n": String(index + 1), "total": String(questions.count)]))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    GameProgressBar(progress: Double(index + 1) / Double(max(questions.count, 1)),
                                    tint: Theme.blue)
                }
                questionCard
                deckControls
                Text(L10n.t("games.q36.swipeHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(LayoutMetrics.s(16))
        }
    }

    @ViewBuilder
    private var questionCard: some View {
        if index < questions.count {
            VStack(spacing: LayoutMetrics.s(14)) {
                Text("„")
                    .font(.scaled(44, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.blue.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(questions[index].text.resolved(L10n.lang))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(LayoutMetrics.s(20))
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(280))
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.indigo.opacity(0.45), Theme.purple.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            )
            .id(index)
            .transition(cardTransition)
            .gesture(swipeGesture)
        }
    }

    private var cardTransition: AnyTransition {
        if goingForward {
            return .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                               removal: .move(edge: .leading).combined(with: .opacity))
        }
        return .asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                           removal: .move(edge: .trailing).combined(with: .opacity))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -50 {
                    goNext()
                } else if value.translation.width > 50 {
                    goBack()
                }
            }
    }

    private var deckControls: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.scaled(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: LayoutMetrics.s(54), height: LayoutMetrics.s(48))
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .opacity(index == 0 ? 0.35 : 1)
            Button {
                goNext()
            } label: {
                Text(index >= questions.count - 1
                     ? L10n.t("common.done")
                     : L10n.t("games.next"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func goNext() {
        Haptics.shared.tap()
        if index >= questions.count - 1 {
            stage = .finish
            SoundEngine.shared.play(.sparkle)
            return
        }
        goingForward = true
        withAnimation(.spring(response: 0.35)) {
            index += 1
        }
        SoundEngine.shared.play(.pop)
    }

    private func goBack() {
        guard index > 0 else { return }
        goingForward = false
        withAnimation(.spring(response: 0.35)) {
            index -= 1
        }
        Haptics.shared.tap()
    }

    // MARK: Finish + eye-contact timer

    private var finishScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Text(timerDone ? "🥹" : "👀")
                    .font(.scaled(56))
                Text(L10n.t("games.q36.finishTitle"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.q36.eyeContact"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                timerRing
                if timerDone {
                    Text(L10n.t("games.q36.timerDone"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.gold)
                        .multilineTextAlignment(.center)
                }
                timerButtons
                Button {
                    restart()
                } label: {
                    Text(L10n.t("games.q36.again"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .glassCard(padding: 22)
            .padding(LayoutMetrics.s(16))
        }
    }

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 10)
            Circle()
                .trim(from: 0, to: timerProgress)
                .stroke(
                    LinearGradient(colors: [Theme.pink, Theme.purple],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: timerProgress)
            Text(timeString)
                .font(.scaled(42, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
        }
        .frame(width: LayoutMetrics.s(190), height: LayoutMetrics.s(190))
        .padding(.vertical, 6)
    }

    private var timerProgress: Double {
        Double(Self.eyeContactSeconds - remaining) / Double(Self.eyeContactSeconds)
    }

    private var timeString: String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var timerButtons: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Button {
                toggleTimer()
            } label: {
                Text(timerLabel)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(remaining == 0)
            Button {
                resetTimer()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.scaled(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: LayoutMetrics.s(54), height: LayoutMetrics.s(48))
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
        }
    }

    private var timerLabel: String {
        if timerRunning {
            return L10n.t("games.q36.timerPause")
        }
        if remaining < Self.eyeContactSeconds && remaining > 0 {
            return L10n.t("games.q36.timerResume")
        }
        return L10n.t("games.q36.timerStart")
    }

    private func toggleTimer() {
        if timerRunning {
            pauseTimer()
        } else {
            startTimer()
        }
    }

    private func startTimer() {
        guard remaining > 0 else { return }
        timerRunning = true
        Haptics.shared.tap()
        timerTask?.cancel()
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                tick()
                if remaining <= 0 { return }
            }
        }
    }

    private func pauseTimer() {
        timerRunning = false
        timerTask?.cancel()
        Haptics.shared.tap()
    }

    private func resetTimer() {
        timerTask?.cancel()
        timerRunning = false
        timerDone = false
        remaining = Self.eyeContactSeconds
        Haptics.shared.tap()
    }

    private func tick() {
        guard timerRunning, remaining > 0 else { return }
        remaining -= 1
        if remaining == 0 {
            timerRunning = false
            timerDone = true
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
        }
    }

    private func restart() {
        resetTimer()
        stage = .setup
        index = 0
    }
}
