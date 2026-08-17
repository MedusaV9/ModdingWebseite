import Foundation
import SwiftUI
import Observation
#if canImport(Translation)
import Translation
#endif

// The ONLY file that imports the Translation framework — a thin facade
// over on-device translation of single partner messages (Welle 7 [27]).
// The offer rules and the stopword heuristic live in
// Content/ChatLanguageRules.swift (Linux-testable); the server is never
// involved and nothing is persisted — a translation is as ephemeral as
// the reading moment, the original stays the only durable truth.
//
// Session policy: the session lives inside the chat's `translationTask`
// (system requirement — using a session after its view disappears traps).
// The center only stores the REQUEST and the RESULTS; every run gets a
// fresh session instance from SwiftUI.

/// What one message's translation can be, as the bubble renders it.
enum ChatTranslationState: Equatable {
    case translating
    case translated(String)
    /// Honest failure line (l10n key) — language unsupported, language
    /// pack download declined, or the engine gave up.
    case failed(String)
}

@MainActor
@Observable
final class ChatTranslationCenter {
    static let shared = ChatTranslationCenter()

    /// Per-message results for this app run — in-memory only.
    private(set) var states: [String: ChatTranslationState] = [:]
    /// Messages whose translation is folded away — hiding keeps the
    /// result so re-showing is instant and free.
    private(set) var hidden: Set<String> = []

    /// The request the next session run translates.
    private var pendingId: String?
    private var pendingText = ""
    /// Target language of the live configuration — the configuration is
    /// rebuilt when the app language changes mid-run.
    private var configuredTarget: String?

    #if canImport(Translation)
    /// Non-nil once the first request armed the chat's translation task.
    private(set) var configuration: TranslationSession.Configuration?
    #endif

    private init() {}

    /// The state a bubble renders under the original (nil = nothing).
    func visibleState(for messageId: String) -> ChatTranslationState? {
        guard !hidden.contains(messageId) else { return nil }
        return states[messageId]
    }

    /// True while the bubble shows a translation block (any state) —
    /// drives the "hide translation" menu entry.
    func isShowing(_ messageId: String) -> Bool {
        visibleState(for: messageId) != nil
    }

    /// True when the visible state is a failure — drives the retry entry.
    func isShowingFailure(_ messageId: String) -> Bool {
        if case .failed = visibleState(for: messageId) { return true }
        return false
    }

    func hideTranslation(for messageId: String) {
        hidden.insert(messageId)
    }

    /// Context action: translate the message — or re-show the cached
    /// result, or retry after a failure. Source language stays nil: the
    /// system detects the message language itself (the stopword guess is
    /// only menu gating, never ground truth).
    func requestTranslation(messageId: String, text: String) {
        hidden.remove(messageId)
        if let existing = states[messageId], !Self.isFailed(existing) {
            return  // already translated (or in flight) — just re-shown
        }
        #if canImport(Translation)
        states[messageId] = .translating
        pendingId = messageId
        pendingText = ChatTranslationRules.normalizedSource(text)
        let target = ChatTranslationRules.targetLanguageIdentifier(appLanguage: L10n.lang)
        if configuration == nil || configuredTarget != target {
            configuredTarget = target
            configuration = TranslationSession.Configuration(
                source: nil,
                target: Locale.Language(identifier: target))
        } else {
            configuration?.invalidate()
        }
        #else
        states[messageId] = .failed("chat.translate.failed")
        #endif
    }

    #if canImport(Translation)
    /// Runs inside the chat's `translationTask` with a session bound to
    /// the visible chat view. A missing language pack makes the system
    /// present its download sheet during `translate(_:)` automatically;
    /// declining it (or an unsupported language) surfaces here as an
    /// error and becomes one honest line under the original.
    func run(_ session: TranslationSession) async {
        guard let id = pendingId else { return }
        pendingId = nil
        let text = pendingText
        do {
            let response = try await session.translate(text)
            states[id] = .translated(response.targetText)
        } catch is CancellationError {
            // View went away mid-request — forget the attempt so the
            // next tap starts clean instead of showing a stale spinner.
            states.removeValue(forKey: id)
        } catch {
            states[id] = .failed("chat.translate.failed")
        }
    }
    #endif

    /// Profile/couple switches drop every cached translation — a
    /// translation from couple context A must never surface in B.
    func reset() {
        states = [:]
        hidden = []
        pendingId = nil
        pendingText = ""
    }

    private static func isFailed(_ state: ChatTranslationState) -> Bool {
        if case .failed = state { return true }
        return false
    }
}

/// Chat-screen modifier hosting the one `translationTask` all bubbles
/// share. Attached once to the conversation, so the system download
/// sheet has a stable, visible anchor view.
struct ChatTranslationHost: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(Translation)
        content.translationTask(ChatTranslationCenter.shared.configuration) { session in
            await ChatTranslationCenter.shared.run(session)
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Arms the chat screen for on-device message translation.
    func chatTranslationHost() -> some View {
        modifier(ChatTranslationHost())
    }
}
