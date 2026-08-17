import SwiftUI

// Zone „Spindel" — das Korrektur-Blatt für eigene Zettel. Reiner
// Struktur-Umzug aus ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

/// Small sheet for rewriting one of MY text/letter messages. Saving PATCHes
/// the server, which sets `editedAt` and echoes `message_updated`.
struct MessageEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let message: Message
    let onSave: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saving is only enabled for a non-empty text that actually changed.
    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != (message.text ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
                    // Rewriting happens ON paper (Korrespondenz): the draft
                    // is a free-standing paper slip on the night canvas —
                    // dark ink on brief, tertiary-ink prompt.
                    TextField(L10n.t("chat.inputPlaceholder"),
                              text: $draft,
                              prompt: Text(L10n.t("chat.inputPlaceholder")).foregroundStyle(Tinte.tertiaer),
                              axis: .vertical)
                        .lineLimit(3...10)
                        .textFieldStyle(ChatPaperFieldStyle())
                        .focused($focused)
                    Text(L10n.t("chat.editHint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .padding(LayoutMetrics.s(16))
            }
            .navigationTitle(L10n.t("chat.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) {
                        Haptics.shared.tap()
                        dismiss()
                        onSave(draft)
                    }
                    .tint(coupleTint.blend)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                draft = message.text ?? ""
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}
