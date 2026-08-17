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

/// Closed-envelope look for a received, not-yet-opened sealed letter —
/// a partner Zettel (Korrespondenz): letter paper with grain, the lamp's
/// light edge and the partner's ink edge; the night-era indigo/gold
/// envelope glass is gone.
struct SealedLetterCard: View {
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let message: Message
    let unsealing: Bool
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            envelope
            Text(L10n.t("chat.sealedTitle"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
            Text(LetterSeal.sentence(for: message.openWhen ?? ""))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
            openButton
            ChatTimestampText(date: message.createdAt, isMine: false)
        }
        .frame(maxWidth: .infinity)
        .padding(LayoutMetrics.s(16))
        .background(sealedBackground)
    }

    private var envelope: some View {
        ZStack(alignment: .center) {
            Image(systemName: "envelope.fill")
                .font(.system(.largeTitle, design: .rounded))
                .imageScale(.large)
                // The couple gradient stays an OBJECT — the envelope is
                // the Zettel's one identity artifact, never a card wash.
                .foregroundStyle(coupleTint.heroGradient)
                .accessibilityHidden(true)
            ChatWaxSealView()
                .offset(x: 20, y: 15)
        }
        .padding(.top, 4)
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
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(Papier.brief)
            if colorSchemeContrast != .increased {
                PaperGrainView()
            }
            // Sealed letters are always the partner's — their ink edge
            // marks the authorship like on every partner Zettel.
            Rectangle()
                .fill(coupleTint.tintePrimary)
                .frame(width: Papier.tintenkante)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                    lineWidth: Theme.hairlineWidth))
        .elevation(.resting)
    }
}

// MARK: - Letter reader sheet

/// Full-screen reader for an (unsealed or own) love letter.
struct LetterReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let message: Message
    let senderName: String

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        Image(systemName: "envelope.open.fill")
                            .font(.system(.largeTitle, design: .rounded))
                            // Lamplight ceremony accent ON NIGHT (11.3:1) —
                            // legal here, banned as ink on the paper below.
                            .foregroundStyle(Licht.lampengold)
                            .accessibilityHidden(true)
                            .padding(.top, 8)
                        letterSheet
                        metaRow
                    }
                    .padding(LayoutMetrics.s(20))
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
        .tint(coupleTint.blend)
    }

    private var titleText: String {
        if let title = message.title, !title.isEmpty { return title }
        return L10n.t("chat.letterUntitled")
    }

    /// The letter itself — the screen's ONE Briefbogen hero: letter paper
    /// with the couple band and the wax seal crossing its head. Serif
    /// lives HERE (serif only on paper): the title in the couple's voice,
    /// the body in the upright reading serif.
    private var letterSheet: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            // The title is the couple's own wording — the serif voice in
            // the couple's shared ink (identity accent, never body copy).
            Text(titleText)
                .font(Typo.voice)
                .foregroundStyle(coupleTint.tinte)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            if let token = message.openWhen {
                sealLine(token)
                    .frame(maxWidth: .infinity)
            }
            Text(message.text ?? "")
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Extra head room so the band crosses paper, not the title.
        .padding(.top, LayoutMetrics.s(30))
        .paperCard(.briefbogen, padding: .hero)
        .overlay(alignment: .top) {
            ChatBriefbogenBand(seed: chatPaperSeed(message.id))
                .offset(y: LayoutMetrics.s(16))
        }
    }

    private func sealLine(_ token: String) -> some View {
        HStack(spacing: 6) {
            Text(LetterSeal.emoji(for: token))
            Text(LetterSeal.sentence(for: token))
                .font(.system(.caption, design: .rounded).weight(.semibold))
        }
        // Wax red is INK on paper here (5.2:1 pinned) over a faint wax
        // wash — gold read 1.4:1 on brief and is banned there.
        .foregroundStyle(Wachs.rot)
        .padding(.vertical, 5)
        .padding(.horizontal, LayoutMetrics.s(12))
        .background(Capsule().fill(Wachs.rot.opacity(0.10)))
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
        .padding(.bottom, LayoutMetrics.s(12))
    }
}
