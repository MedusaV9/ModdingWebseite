import SwiftUI

/// Love-letter composer sheet: title + long text, live preview card,
/// celebratory hearts on success.
struct LetterComposeView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Optional "Öffnen wenn …" seal.
    private enum SealChoice: Equatable {
        case none
        case preset(String)
        case custom
    }

    @State private var title = ""
    @State private var text = ""
    @State private var sealChoice: SealChoice = .none
    @State private var customSeal = ""
    @State private var sending = false
    @State private var sent = false
    let onSent: (Message) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token sent as `openWhen` (nil when unsealed).
    private var openWhenToken: String? {
        switch sealChoice {
        case .none:
            return nil
        case .preset(let token):
            return token
        case .custom:
            let custom = customSeal.trimmingCharacters(in: .whitespacesAndNewlines)
            return custom.isEmpty ? nil : LetterSeal.customPrefix + custom
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        titleField
                        editor
                        sealPicker
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

    // MARK: Seal picker

    private var sealPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("chat.sealPickerTitle"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    sealChip(emoji: "✉️",
                             label: L10n.t("chat.sealNone"),
                             selected: sealChoice == .none) {
                        sealChoice = .none
                    }
                    ForEach(LetterSeal.presetTokens, id: \.self) { token in
                        sealChip(emoji: LetterSeal.emoji(for: token),
                                 label: LetterSeal.chipLabel(for: token),
                                 selected: sealChoice == .preset(token)) {
                            sealChoice = .preset(token)
                        }
                    }
                    sealChip(emoji: "✏️",
                             label: L10n.t("chat.sealCustom"),
                             selected: sealChoice == .custom) {
                        sealChoice = .custom
                    }
                }
            }
            if sealChoice == .custom {
                customSealField
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    private var customSealField: some View {
        TextField(L10n.t("chat.sealCustomPlaceholder"),
                  text: $customSeal,
                  prompt: Text(L10n.t("chat.sealCustomPlaceholder")).foregroundStyle(Theme.textTertiary))
            .textFieldStyle(DreamyFieldStyle())
            .onChange(of: customSeal) {
                if customSeal.count > 40 {
                    customSeal = String(customSeal.prefix(40))
                }
            }
    }

    private func sealChip(emoji: String, label: String, selected: Bool,
                          action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) {
                action()
            }
        } label: {
            HStack(spacing: 5) {
                Text(emoji)
                Text(label)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule()
                    .fill(selected ? Theme.pink.opacity(0.35) : Color.white.opacity(0.06))
                    .overlay(
                        Capsule().strokeBorder(selected ? Theme.pink : Color.white.opacity(0.12),
                                               lineWidth: selected ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
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
            if let token = openWhenToken {
                previewSealRow(token)
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

    private func previewSealRow(_ token: String) -> some View {
        HStack(spacing: 5) {
            Text("🔒")
                .font(.system(size: 10))
            Text(LetterSeal.sentence(for: token))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .lineLimit(2)
        }
        .foregroundStyle(Theme.gold)
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(Capsule().fill(Theme.gold.opacity(0.14)))
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
                                                        title: letterTitle.isEmpty ? nil : letterTitle,
                                                        openWhen: openWhenToken)
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
