import SwiftUI
import Observation

// MARK: - Seal tokens

/// "Öffnen wenn …" seals for love letters. A seal is stored in
/// `Message.openWhen` as a token ("sad", "night", …) or "custom:<text>".
enum LetterSeal {
    static let customPrefix = "custom:"
    static let presetTokens = ["sad", "missme", "happy", "badday", "night", "anniversary"]

    static func isCustom(_ token: String) -> Bool {
        token.hasPrefix(customPrefix)
    }

    static func customText(_ token: String) -> String? {
        guard token.hasPrefix(customPrefix) else { return nil }
        let text = String(token.dropFirst(customPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func emoji(for token: String) -> String {
        switch token {
        case "sad": return "😢"
        case "missme": return "🥺"
        case "happy": return "🥳"
        case "badday": return "🌧️"
        case "night": return "🌙"
        case "anniversary": return "💍"
        default: return "💌"
        }
    }

    /// Short label for the compose chips.
    static func chipLabel(for token: String) -> String {
        if let custom = customText(token) { return custom }
        if presetTokens.contains(token) { return L10n.t("chat.seal.\(token)") }
        return L10n.t("chat.sealLine.generic")
    }

    /// Warm full sentence shown on the sealed envelope / seal chip.
    static func sentence(for token: String) -> String {
        if let custom = customText(token) {
            return L10n.t("chat.sealLine.custom", ["text": custom])
        }
        if presetTokens.contains(token) { return L10n.t("chat.sealLine.\(token)") }
        return L10n.t("chat.sealLine.generic")
    }
}

// MARK: - Opened letters persistence

/// Remembers which sealed letters were opened on this device,
/// per couple (UserDefaults key "sooodreamy.openedLetters.<coupleId>").
@MainActor
@Observable
final class OpenedLettersStore {
    static let shared = OpenedLettersStore()

    /// Bumped on every change so SwiftUI re-reads `isOpened`.
    private(set) var version = 0
    @ObservationIgnored private var cache: [String: Set<String>] = [:]

    private init() {}

    func isOpened(_ messageId: String, coupleId: String?) -> Bool {
        _ = version
        guard let coupleId else { return false }
        return openedIds(coupleId).contains(messageId)
    }

    func markOpened(_ messageId: String, coupleId: String?) {
        guard let coupleId else { return }
        var ids = openedIds(coupleId)
        guard !ids.contains(messageId) else { return }
        ids.insert(messageId)
        cache[coupleId] = ids
        UserDefaults.standard.set(Array(ids).sorted(), forKey: storageKey(coupleId))
        version += 1
    }

    private func storageKey(_ coupleId: String) -> String {
        "sooodreamy.openedLetters.\(coupleId)"
    }

    private func openedIds(_ coupleId: String) -> Set<String> {
        if let cached = cache[coupleId] { return cached }
        let stored = Set(UserDefaults.standard.stringArray(forKey: storageKey(coupleId)) ?? [])
        cache[coupleId] = stored
        return stored
    }
}

// MARK: - Sealed envelope card

/// Closed-envelope look for a received, not-yet-opened sealed letter.
struct SealedLetterCard: View {
    let message: Message
    let unsealing: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            envelope
            Text(L10n.t("chat.sealedTitle"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
            Text(LetterSeal.sentence(for: message.openWhen ?? ""))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            openButton
            ChatTimestampText(date: message.createdAt, isMine: false)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(sealedBackground)
    }

    private var envelope: some View {
        ZStack(alignment: .center) {
            Text("💌")
                .font(.system(size: 46))
            waxSeal
                .offset(x: 20, y: 15)
        }
        .padding(.top, 4)
    }

    private var waxSeal: some View {
        Circle()
            .fill(
                LinearGradient(colors: [Theme.gold, Theme.pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "heart.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
            .shadow(color: Theme.gold.opacity(0.6), radius: 5)
    }

    private var openButton: some View {
        Button {
            onOpen()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "envelope.open.fill")
                Text(L10n.t("chat.sealedOpen"))
            }
        }
        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
        .disabled(unsealing)
    }

    private var sealedBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(colors: [Theme.purple.opacity(0.35), Theme.indigo.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.60), lineWidth: 1.5)
            )
            .shadow(color: Theme.gold.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - Letter reader sheet

/// Full-screen reader for an (unsealed or own) love letter.
struct LetterReaderView: View {
    @Environment(\.dismiss) private var dismiss
    let message: Message
    let senderName: String

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        Text("💌")
                            .font(.system(size: 48))
                            .padding(.top, 8)
                        Text(titleText)
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.gold)
                            .multilineTextAlignment(.center)
                        if let token = message.openWhen {
                            sealLine(token)
                        }
                        letterCard
                        metaRow
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("chat.readerClose")) {
                        dismiss()
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(Theme.pink)
    }

    private var titleText: String {
        if let title = message.title, !title.isEmpty { return title }
        return L10n.t("chat.letterUntitled")
    }

    private func sealLine(_ token: String) -> some View {
        HStack(spacing: 6) {
            Text(LetterSeal.emoji(for: token))
            Text(LetterSeal.sentence(for: token))
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(Theme.gold)
        .padding(.vertical, 5)
        .padding(.horizontal, 12)
        .background(Capsule().fill(Theme.gold.opacity(0.14)))
    }

    private var letterCard: some View {
        Text(message.text ?? "")
            .font(.body)
            .fontDesign(.serif)
            .foregroundStyle(Theme.textPrimary)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Theme.purple.opacity(0.28), Theme.pink.opacity(0.16)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Theme.gold.opacity(0.50), lineWidth: 1.5)
                    )
            )
    }

    private var metaRow: some View {
        VStack(spacing: 2) {
            Text(L10n.t("chat.readerFrom", ["name": senderName]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(message.createdAt.formatted(date: .long, time: .shortened))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.bottom, 12)
    }
}
