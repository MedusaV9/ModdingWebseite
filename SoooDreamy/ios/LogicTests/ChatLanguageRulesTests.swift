import XCTest
@testable import SoooDreamyLogic

/// Welle 7 [27]+[28]: offer rules + stopword heuristic for the chat
/// translation, and the local voice-transcript cache contract.
final class ChatLanguageRulesTests: XCTestCase {

    // MARK: - Translation offer rules

    func testNeverOffersOnMyOwnMessages() {
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "How are you today, my love?", isMine: true, appLanguage: "de"))
    }

    func testNeverOffersOnEmptyOrMissingText() {
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: nil, isMine: false, appLanguage: "de"))
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "   ", isMine: false, appLanguage: "de"))
    }

    func testNeverOffersOnEmojiOrNumberOnlyMessages() {
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "❤️❤️❤️", isMine: false, appLanguage: "de"))
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "12345", isMine: false, appLanguage: "de"))
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "ok", isMine: false, appLanguage: "de"))
    }

    func testNeverOffersOnLinkOnlyMessages() {
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "https://example.com/some/path", isMine: false, appLanguage: "de"))
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "www.example.com", isMine: false, appLanguage: "de"))
        // A link inside a sentence is still prose.
        XCTAssertTrue(ChatTranslationRules.offersTranslation(
            text: "look at this https://example.com so beautiful",
            isMine: false, appLanguage: "de"))
    }

    func testSuppressesWhenMessageConfidentlyMatchesAppLanguage() {
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "Ich vermisse dich heute schon sehr", isMine: false, appLanguage: "de"))
        XCTAssertFalse(ChatTranslationRules.offersTranslation(
            text: "How are you doing today?", isMine: false, appLanguage: "en"))
    }

    func testOffersOnForeignOrUnclearMessages() {
        // English message in a German app — the flagship case.
        XCTAssertTrue(ChatTranslationRules.offersTranslation(
            text: "How are you doing today?", isMine: false, appLanguage: "de"))
        // German message in an English app.
        XCTAssertTrue(ChatTranslationRules.offersTranslation(
            text: "Ich vermisse dich heute schon sehr", isMine: false, appLanguage: "en"))
        // Third language: no stopword hits either way — stays offered.
        XCTAssertTrue(ChatTranslationRules.offersTranslation(
            text: "Ti amo tanto amore mio", isMine: false, appLanguage: "de"))
    }

    // MARK: - Stopword heuristic

    func testStopwordGuessGerman() {
        XCTAssertEqual(ChatTranslationRules.stopwordLanguageGuess(
            "Ich liebe dich und vermisse dich"), "de")
    }

    func testStopwordGuessEnglish() {
        XCTAssertEqual(ChatTranslationRules.stopwordLanguageGuess(
            "I really miss you and love you"), "en")
    }

    func testUmlautsAloneSignalGerman() {
        XCTAssertEqual(ChatTranslationRules.stopwordLanguageGuess(
            "Schönen Feierabend, Süße"), "de")
    }

    func testGuessStaysNilWithoutClearSignal() {
        XCTAssertNil(ChatTranslationRules.stopwordLanguageGuess("Ti amo tanto"))
        XCTAssertNil(ChatTranslationRules.stopwordLanguageGuess(""))
        // One hit is not enough — two distinctive words required.
        XCTAssertNil(ChatTranslationRules.stopwordLanguageGuess("thanks a lot"))
    }

    func testGuessNeverReturnsAThirdValue() {
        let samples = ["Guten Morgen mein Schatz", "See you tonight sweetheart",
                       "Je t'aime mon amour", "ok", "1234", "❤️"]
        for sample in samples {
            let guess = ChatTranslationRules.stopwordLanguageGuess(sample)
            XCTAssertTrue(guess == nil || guess == "de" || guess == "en",
                          "unexpected guess \(String(describing: guess)) for \(sample)")
        }
    }

    func testTargetLanguageFollowsAppLanguage() {
        XCTAssertEqual(ChatTranslationRules.targetLanguageIdentifier(appLanguage: "de"), "de")
        XCTAssertEqual(ChatTranslationRules.targetLanguageIdentifier(appLanguage: "en"), "en")
        // Anything unexpected falls back to English, never crashes.
        XCTAssertEqual(ChatTranslationRules.targetLanguageIdentifier(appLanguage: "fr"), "en")
    }

    func testNormalizedSourceTrimsEdgesOnly() {
        XCTAssertEqual(ChatTranslationRules.normalizedSource("  Hallo\ndu  "),
                       "Hallo\ndu")
    }

    // MARK: - Transcript cache contract

    func testCacheAppendKeepsOrderAndReplacesById() {
        let a = VoiceTranscriptCacheEntry(id: "a", text: "one")
        let b = VoiceTranscriptCacheEntry(id: "b", text: "two")
        var cache = VoiceTranscriptRules.appending(a, to: [])
        cache = VoiceTranscriptRules.appending(b, to: cache)
        XCTAssertEqual(cache.map(\.id), ["a", "b"])

        // Refreshing "a" moves it to the newest slot with the new text.
        let a2 = VoiceTranscriptCacheEntry(id: "a", text: "one-updated")
        cache = VoiceTranscriptRules.appending(a2, to: cache)
        XCTAssertEqual(cache.map(\.id), ["b", "a"])
        XCTAssertEqual(cache.last?.text, "one-updated")
    }

    func testCacheEvictsOldestBeyondLimit() {
        var cache: [VoiceTranscriptCacheEntry] = []
        for index in 0..<70 {
            cache = VoiceTranscriptRules.appending(
                VoiceTranscriptCacheEntry(id: "m\(index)", text: "t\(index)"),
                to: cache)
        }
        XCTAssertEqual(cache.count, VoiceTranscriptRules.cacheLimit)
        XCTAssertEqual(cache.first?.id, "m10")  // 0…9 evicted
        XCTAssertEqual(cache.last?.id, "m69")
    }

    func testCacheEntryRoundTripsThroughJSON() throws {
        let entries = [VoiceTranscriptCacheEntry(id: "x", text: "Hallo du")]
        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([VoiceTranscriptCacheEntry].self, from: data)
        XCTAssertEqual(decoded, entries)
    }

    // MARK: - Transcript locale matching

    func testLocaleMatchingPrefersRegionalDefault() {
        let supported = ["en-US", "en-GB", "de-DE", "de-AT", "fr-FR"]
        XCTAssertEqual(VoiceTranscriptRules.matchingLocaleIdentifier(
            appLanguage: "de", supportedBCP47: supported), "de-DE")
        XCTAssertEqual(VoiceTranscriptRules.matchingLocaleIdentifier(
            appLanguage: "en", supportedBCP47: supported), "en-US")
    }

    func testLocaleMatchingFallsBackToAnyRegionOfTheLanguage() {
        XCTAssertEqual(VoiceTranscriptRules.matchingLocaleIdentifier(
            appLanguage: "de", supportedBCP47: ["en-US", "de-CH"]), "de-CH")
    }

    func testLocaleMatchingReturnsNilWhenLanguageUnsupported() {
        XCTAssertNil(VoiceTranscriptRules.matchingLocaleIdentifier(
            appLanguage: "de", supportedBCP47: ["en-US", "fr-FR"]))
        XCTAssertNil(VoiceTranscriptRules.matchingLocaleIdentifier(
            appLanguage: "de", supportedBCP47: []))
    }

    func testTranscriptNormalizationCollapsesWhitespace() {
        XCTAssertEqual(VoiceTranscriptRules.normalizedTranscript(
            "  Hallo   du \n bist  toll  "), "Hallo du bist toll")
        XCTAssertEqual(VoiceTranscriptRules.normalizedTranscript("   "), "")
    }
}
