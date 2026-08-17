import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

// The ONLY file that imports FoundationModels — a thin facade over the
// on-device model. Views talk to `Intelligence.shared`; the rules that
// make this testable on Linux (consent machine, availability mapping,
// prompt assembly, sanitizing) live in Content/IntelligenceRules.swift.
//
// Session policy: one EPHEMERAL session per request. Features never share
// a transcript, so couple content from one moment cannot bleed into the
// next request's context — and the context window can never fill up.

/// What generation can honestly report upward. The UI maps `guardrail`
/// to its own copy (the safety system declined, rephrase and retry) and
/// everything else to the generic "unchanged draft, try again" line.
enum IntelligenceError: Error, Equatable {
    /// Gate closed: model unavailable or consent missing/withdrawn.
    case gateClosed
    /// The safety system declined the request or the response.
    case guardrail
    /// The model answered, but nothing usable survived sanitizing.
    case emptyResult
    /// Anything else — cancellation aside, callers retry.
    case failed

    var l10nKey: String {
        switch self {
        case .guardrail: return "ai.workshop.guardrail"
        case .gateClosed, .emptyResult, .failed: return "ai.workshop.failed"
        }
    }
}

@MainActor
@Observable
final class Intelligence {
    static let shared = Intelligence()

    /// Device-scoped consent, persisted like every other preference
    /// (see AppLock.isEnabled / SoundEngine.enabled).
    private static let consentKey = "sooodreamy.ai.consent"

    private(set) var consent: IntelligenceConsentState

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.consentKey) ?? ""
        consent = IntelligenceConsentState(rawValue: stored) ?? .unasked
    }

    func apply(_ event: IntelligenceConsentEvent) {
        consent = IntelligenceConsentRules.transition(from: consent, event: event)
        UserDefaults.standard.set(consent.rawValue, forKey: Self.consentKey)
    }

    // MARK: Availability

    /// Live system state, mapped into the Foundation-only mirror enum.
    /// Computed on every read — Apple Intelligence can be toggled in iOS
    /// Settings or finish downloading while the app is open, and a stale
    /// cache would show dead entry points either way.
    var availability: IntelligenceAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .intelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unknown
        }
        #else
        return .deviceNotEligible
        #endif
    }

    /// Entry points render only when this is true — no dead buttons.
    var featureVisible: Bool {
        IntelligenceGate.featureVisible(availability: availability)
    }

    /// The one question every feature asks before generating.
    var canGenerate: Bool {
        IntelligenceGate.canCreateSession(availability: availability, consent: consent)
    }

    // MARK: Letter openings (Briefanfang-Werkstatt)

    /// Three distinct letter openings in the chosen tone, in the app
    /// language. Guided generation guarantees the three-part shape; the
    /// sanitizer enforces "actually different" and the length contract.
    func letterOpeners(tone: IntelligenceTone) async throws -> [String] {
        guard canGenerate else { throw IntelligenceError.gateClosed }
        #if canImport(FoundationModels)
        let language = L10n.lang
        let session = LanguageModelSession(
            instructions: IntelligencePrompts.instructions(feature: .letterOpeners,
                                                           language: language))
        do {
            let response = try await session.respond(
                to: Prompt(IntelligencePrompts.letterOpenersPrompt(tone: tone,
                                                                   language: language)),
                generating: LetterOpenersDraft.self,
                options: GenerationOptions(temperature: 0.9))
            let openers = IntelligenceSanitizer.sanitizedOpeners([
                response.content.first, response.content.second, response.content.third,
            ])
            guard !openers.isEmpty else { throw IntelligenceError.emptyResult }
            return openers
        } catch {
            throw Self.mapped(error)
        }
        #else
        throw IntelligenceError.gateClosed
        #endif
    }

    // MARK: "Say it gently"

    /// A gentler rewording of the draft — same meaning, same language.
    /// The caller keeps the original until the person explicitly adopts.
    func gentleRephrase(of draft: String) async throws -> String {
        guard canGenerate else { throw IntelligenceError.gateClosed }
        #if canImport(FoundationModels)
        let language = L10n.lang
        let session = LanguageModelSession(
            instructions: IntelligencePrompts.instructions(feature: .gentleRephrase,
                                                           language: language))
        do {
            let response = try await session.respond(
                to: Prompt(IntelligencePrompts.rephrasePrompt(draft: draft,
                                                              language: language)),
                options: GenerationOptions(temperature: 0.4))
            let text = IntelligenceSanitizer.sanitize(response.content, for: .gentleRephrase)
            guard !text.isEmpty else { throw IntelligenceError.emptyResult }
            return text
        } catch {
            throw Self.mapped(error)
        }
        #else
        throw IntelligenceError.gateClosed
        #endif
    }

    // MARK: Daily-question spark

    /// One follow-up question built from both revealed answers — client
    /// only, the server never sees a byte of this.
    func dailySpark(question: String, myName: String, myAnswer: String,
                    partnerName: String, partnerAnswer: String) async throws -> String {
        guard canGenerate else { throw IntelligenceError.gateClosed }
        #if canImport(FoundationModels)
        let language = L10n.lang
        let session = LanguageModelSession(
            instructions: IntelligencePrompts.instructions(feature: .dailySpark,
                                                           language: language))
        do {
            let response = try await session.respond(
                to: Prompt(IntelligencePrompts.dailySparkPrompt(
                    question: question, myName: myName, myAnswer: myAnswer,
                    partnerName: partnerName, partnerAnswer: partnerAnswer,
                    language: language)),
                options: GenerationOptions(temperature: 0.8))
            let text = IntelligenceSanitizer.sanitize(response.content, for: .dailySpark)
            guard !text.isEmpty else { throw IntelligenceError.emptyResult }
            return text
        } catch {
            throw Self.mapped(error)
        }
        #else
        throw IntelligenceError.gateClosed
        #endif
    }

    // MARK: Error mapping

    private static func mapped(_ error: Error) -> Error {
        if error is CancellationError { return error }
        if let known = error as? IntelligenceError { return known }
        #if canImport(FoundationModels)
        if let generation = error as? LanguageModelSession.GenerationError,
           case .guardrailViolation = generation {
            return IntelligenceError.guardrail
        }
        #endif
        return IntelligenceError.failed
    }
}

#if canImport(FoundationModels)
/// Guided-generation shape for the workshop: three named fields instead
/// of an array, so the model cannot under- or over-deliver structurally.
@Generable
private struct LetterOpenersDraft {
    @Guide(description: "The first letter opening, one to two sentences.")
    var first: String
    @Guide(description: "A second, clearly different letter opening, one to two sentences.")
    var second: String
    @Guide(description: "A third opening, clearly different from the first two, one to two sentences.")
    var third: String
}
#endif
