import SwiftUI

/// Love-letter composer sheet: title + long text, live preview card,
/// celebratory hearts on success.
struct LetterComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""
    @State private var sending = false
    @State private var sent = false
    let onSent: (Message) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        titleField
                        editor
                        previewCard
                        sendButton
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                if sent {
                    FloatingHeartsView(emojis: ["💌", "💖", "💜", "✨", "💞"], count: 24)
                        .ignoresSafeArea()
                        .zIndex(5)
                }
            }
            .navigationTitle(L10n.t("chat.letterTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("chat.cancel")) {
                        dismiss()
                    }
                    .disabled(sending || sent)
                }
            }
        }
        .tint(Theme.pink)
        .interactiveDismissDisabled(sending || sent)
    }

    // MARK: Fields

    private var titleField: some View {
        TextField(L10n.t("chat.letterTitlePlaceholder"),
                  text: $title,
                  prompt: Text(L10n.t("chat.letterTitlePlaceholder")).foregroundStyle(Theme.textTertiary))
            .textFieldStyle(DreamyFieldStyle())
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(L10n.t("chat.letterPlaceholder"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 16)
                    .padding(.leading, 17)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .frame(minHeight: 180)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    // MARK: Preview

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("💌")
                Text(L10n.t("chat.letterPreview"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.gold)
                Spacer()
            }
            Text(title.isEmpty ? L10n.t("chat.letterUntitled") : title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
            Text(text.isEmpty ? L10n.t("chat.letterPreviewEmpty") : text)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(text.isEmpty ? Theme.textTertiary : Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(colors: [Theme.purple.opacity(0.28), Theme.pink.opacity(0.18)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.gold.opacity(0.50), lineWidth: 1.5)
                )
        )
    }

    // MARK: Send

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Text(sending ? L10n.t("chat.letterSending") : L10n.t("chat.letterSend"))
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(sending || sent || trimmedText.isEmpty)
        .padding(.top, 4)
    }

    private func send() {
        let body = trimmedText
        guard !body.isEmpty, !sending, !sent, let api = appState.api else { return }
        let letterTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        Haptics.shared.tap()
        Task {
            do {
                let message = try await api.sendMessage(type: .letter,
                                                        text: body,
                                                        title: letterTitle.isEmpty ? nil : letterTitle)
                sending = false
                withAnimation(.spring(response: 0.35)) {
                    sent = true
                }
                SoundEngine.shared.play(.tada)
                Haptics.shared.success()
                appState.showToast(L10n.t("chat.letterSent"), style: .love)
                onSent(message)
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                dismiss()
            } catch {
                sending = false
                appState.handleAPIError(error)
            }
        }
    }
}
