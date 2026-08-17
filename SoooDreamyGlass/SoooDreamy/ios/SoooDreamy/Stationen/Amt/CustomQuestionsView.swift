import SwiftUI

/// Eigene Tagesfragen: each partner secretly feeds questions into the
/// couple's pool; roughly every third day the daily question comes from that
/// pool instead of the built-in pack. Only MY questions are listed here —
/// the partner's stay invisible so authorship remains a surprise until the
/// both-answered reveal.
struct CustomQuestionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var questions: [CustomDailyQuestion] = []
    @State private var poolSize = 0
    @State private var loading = true
    @State private var loadFailed = false
    @State private var newText = ""
    @State private var saving = false

    private let maxLength = 240

    var body: some View {
        NavigationStack {
            ZStack {
                // Fix4 Befund 7: Amt sheets are still tool rooms.
                DreamyBackground(showBlobs: false)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Space.l) {
                        explainer
                        composeCard
                        myQuestions
                    }
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.xxl)
                }
            }
            .navigationTitle(L10n.t("dailyq.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .tint(coupleTint.blend)
                }
            }
        }
        .task { await load() }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(icon: .gift)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Licht.lampengold)
                    .symbolRenderingMode(.hierarchical)
                Text(L10n.t("dailyq.explainer.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
            }
            Text(L10n.t("dailyq.explainer.body", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            if poolSize > 0 {
                Text(L10n.t("dailyq.poolSize", ["n": String(poolSize)]))
                    .font(Typo.caption)
                    .foregroundStyle(Licht.lampengold)
            }
        }
        .nightCard()
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("dailyq.new"), systemImage: "plus.bubble.fill")
            TextField(L10n.t("dailyq.placeholder"), text: $newText, axis: .vertical)
                .textFieldStyle(DreamyFieldStyle())
                .lineLimit(1...4)
                .onChange(of: newText) {
                    if newText.count > maxLength { newText = String(newText.prefix(maxLength)) }
                }
            HStack {
                Text("\(newText.count)/\(maxLength)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .monospacedDigit()
                Spacer()
                Button {
                    Task { await add() }
                } label: {
                    if saving {
                        BusySpinner()
                    } else {
                        Label(L10n.t("dailyq.add"), systemImage: "plus")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
                .disabled(saving || newText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .nightCard()
    }

    @ViewBuilder
    private var myQuestions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader(title: L10n.t("dailyq.mine"), systemImage: "tray.full.fill")
            if loading {
                PaperSkeleton(kind: .tile(height: 52))
                PaperSkeleton(kind: .tile(height: 52))
                PaperSkeleton(kind: .tile(height: 52))
            } else if questions.isEmpty {
                if loadFailed {
                    RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                        Task { await load() }
                    }
                } else {
                    Text(L10n.t("dailyq.empty"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(questions) { question in
                    HStack(alignment: .top, spacing: Space.m) {
                        Image(icon: .dailyQuestion)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Licht.lampengold)
                            .symbolRenderingMode(.hierarchical)
                        Text(question.text)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Papier.aufNacht)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button {
                            Task { await remove(question) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(.footnote, design: .rounded).weight(.semibold))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.t("common.delete"))
                    }
                    .padding(Space.m)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Papier.nachtInnenFill)
                    )
                }
            }
        }
        .nightCard()
    }

    // MARK: Actions

    private func load() async {
        guard let api = appState.api else { return }
        loading = questions.isEmpty
        do {
            let response = try await api.customDailyQuestions()
            questions = response.questions.sorted { $0.createdAt > $1.createdAt }
            poolSize = response.poolSize
            loadFailed = false
        } catch {
            // A failed primary load must not LOOK like an empty pool —
            // the shared failed/offline notice offers an honest retry.
            loadFailed = true
        }
        loading = false
    }

    private func add() async {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = appState.api, !text.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }
        do {
            let response = try await api.addCustomDailyQuestion(text: text)
            questions.insert(response.question, at: 0)
            poolSize = response.poolSize
            newText = ""
            SoundEngine.shared.play(.pop)
            Haptics.shared.success()
            appState.showToast(L10n.t("dailyq.addedToast"), style: .success)
        } catch {
            appState.handleAPIError(error)
        }
    }

    private func remove(_ question: CustomDailyQuestion) async {
        guard let api = appState.api else { return }
        do {
            try await api.deleteCustomDailyQuestion(id: question.id)
            withAnimation(Theme.Motion.settle) {
                questions.removeAll { $0.id == question.id }
            }
            poolSize = max(0, poolSize - 1)
            Haptics.shared.tap()
        } catch {
            appState.handleAPIError(error)
        }
    }
}
