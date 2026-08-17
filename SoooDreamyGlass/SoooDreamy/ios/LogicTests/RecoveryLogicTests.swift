import XCTest
@testable import SoooDreamyLogic

/// v10 „Der große Runde" — recovery-key formatting/validation, the
/// onboarding script, and the widget-snapshot change signature.
final class RecoveryLogicTests: XCTestCase {

    // MARK: Recovery key validation

    func testRecoveryKeyValidationMatchesServerFormat() {
        // Server format: "rec_" + 40 lowercase hex chars (20 random bytes).
        let valid = "rec_" + String(repeating: "ab12", count: 10)
        XCTAssertEqual(valid.count, 44)
        XCTAssertTrue(RecoveryKit.looksLikeRecoveryKey(valid))
        // Whitespace + case noise from manual entry is tolerated…
        XCTAssertTrue(RecoveryKit.looksLikeRecoveryKey("  REC_" + String(repeating: "AB12", count: 10) + " "))
        // …and since the server accepts flexible custom recovery secrets,
        // any non-"rec_" input of at least 4 characters passes the client
        // gate too (the server digest check stays the real judge).
        XCTAssertTrue(RecoveryKit.looksLikeRecoveryKey("key_" + String(repeating: "ab12", count: 10)))
        XCTAssertTrue(RecoveryKit.looksLikeRecoveryKey("mein-eigener-schlüssel"))
        // Structural problems still fail fast:
        XCTAssertFalse(RecoveryKit.looksLikeRecoveryKey(""))
        XCTAssertFalse(RecoveryKit.looksLikeRecoveryKey("ab"))                           // too short for anything
        XCTAssertFalse(RecoveryKit.looksLikeRecoveryKey("rec_zz"))                       // rec_ prefix stays strict
        XCTAssertFalse(RecoveryKit.looksLikeRecoveryKey("rec_" + String(repeating: "gh34", count: 10)))  // non-hex
    }

    func testGroupedAndNormalizedRoundTrip() {
        let key = "rec_0123456789abcdef0123456789abcdef01234567"
        let grouped = RecoveryKit.grouped(key)
        // Blocks of 4 → "rec_0123 4567 89ab …"
        XCTAssertTrue(grouped.hasPrefix("rec_0123 4567"))
        XCTAssertEqual(grouped.split(separator: " ").count, 10)
        // Un-grouping restores the exact wire format.
        XCTAssertEqual(RecoveryKit.normalizedRecoveryKey(grouped), key)
        XCTAssertTrue(RecoveryKit.looksLikeRecoveryKey(grouped))
    }

    func testMaskedKeyLeaksOnlyEdges() {
        let key = "rec_0123456789abcdef0123456789abcdef01234567"
        let masked = RecoveryKit.masked(key)
        XCTAssertEqual(masked, "rec_0123 ···· 4567")
        XCTAssertFalse(masked.contains("89abcdef"))
        // Garbage never echoes back input.
        XCTAssertEqual(RecoveryKit.masked("hello"), "····")
    }

    // MARK: Replace / pairing codes

    func testCodeNormalizationSharesServerAlphabet() {
        // Alphabet drops I, O, 0, 1 — the confusables.
        XCTAssertFalse(RecoveryKit.codeAlphabet.contains("I"))
        XCTAssertFalse(RecoveryKit.codeAlphabet.contains("O"))
        XCTAssertFalse(RecoveryKit.codeAlphabet.contains("0"))
        XCTAssertFalse(RecoveryKit.codeAlphabet.contains("1"))
        XCTAssertEqual(RecoveryKit.codeAlphabet.count, 32)

        // Lowercase input uppercased, confusables dropped, length capped.
        XCTAssertEqual(RecoveryKit.normalizedCode("ab-cd ef01ix", length: 8), "ABCDEFX")
        XCTAssertEqual(RecoveryKit.normalizedCode("abcdefghjklm", length: 8), "ABCDEFGH")
        XCTAssertEqual(RecoveryKit.normalizedCode("ab23", length: 6), "AB23")

        XCTAssertTrue(RecoveryKit.isCompleteReplaceCode("ABCDEFGH"))
        XCTAssertFalse(RecoveryKit.isCompleteReplaceCode("ABC"))
        // 6-char pairing code length stays in sync with the join contract.
        XCTAssertEqual(RecoveryKit.pairingCodeLength, 6)
        XCTAssertEqual(RecoveryKit.replaceCodeLength, 8)
    }

    func testFlexibleReplaceCodesKeepInnerCharacters() {
        // v10.1: custom replace codes (server digest = trim().toUpperCase())
        // must survive typing untouched — only uppercased and capped at the
        // server maximum of 32 characters.
        XCTAssertEqual(RecoveryKit.normalizedFlexibleCode("mausi-2010"), "MAUSI-2010")
        XCTAssertEqual(RecoveryKit.normalizedFlexibleCode("wxyz2345"), "WXYZ2345")
        XCTAssertEqual(RecoveryKit.normalizedFlexibleCode(String(repeating: "a", count: 40)),
                       String(repeating: "A", count: 32))
        XCTAssertEqual(RecoveryKit.replaceCodeMaxLength, 32)

        // Loose completeness gate: ≥ 4 visible characters.
        XCTAssertTrue(RecoveryKit.looksLikeReplaceCode("ABCDEFGH"))
        XCTAssertTrue(RecoveryKit.looksLikeReplaceCode("MAUSI-2010"))
        XCTAssertTrue(RecoveryKit.looksLikeReplaceCode("  AB23  "))
        XCTAssertFalse(RecoveryKit.looksLikeReplaceCode("AB"))
        XCTAssertFalse(RecoveryKit.looksLikeReplaceCode("   "))
    }

    func testReplaceCodeCountdown() {
        let now = Date()
        let expiry = now.addingTimeInterval(15 * 60)
        let remaining = RecoveryKit.replaceCodeRemaining(expiresAt: expiry, now: now)
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 900, accuracy: 0.5)
        XCTAssertEqual(RecoveryKit.countdownLabel(remaining!), "15:00")
        XCTAssertEqual(RecoveryKit.countdownLabel(59), "0:59")
        // Expired → nil (UI switches to the "expired" line).
        XCTAssertNil(RecoveryKit.replaceCodeRemaining(expiresAt: now.addingTimeInterval(-1), now: now))
    }

    // MARK: Onboarding script

    func testOnboardingScriptShapeAndLocalization() {
        let pages = OnboardingScript.pages
        // Welle 7 [29]: the guide page closes the tour — welcome opens it,
        // safety (recovery) still comes before the first pairing.
        XCTAssertEqual(pages.map(\.id), ["welcome", "together", "server", "safety", "guide"])
        XCTAssertTrue(pages[0].features.isEmpty, "hero page carries no feature rows")

        // The guide is the 3-step orientation: exactly three numbered steps
        // plus the second-device link path as a visible fourth option.
        let guide = pages.last!
        XCTAssertEqual(guide.features.count, 4)
        XCTAssertEqual(guide.features[0].icon, "1.circle.fill")
        XCTAssertEqual(guide.features[1].icon, "2.circle.fill")
        XCTAssertEqual(guide.features[2].icon, "3.circle.fill")
        XCTAssertTrue(guide.features[3].textKey.contains("link"),
                      "the Welle-3 device-link path must stay visible in the guide")

        // Every referenced key exists in BOTH languages and differs DE vs EN
        // (except brand names). The guide's route steps live in
        // OnboardingL10n since Fix-Runde 3 (Kino-Befund 3) — the lookup
        // walks the same two tables the runtime resolver does.
        for page in pages {
            for key in [page.titleKey, page.bodyKey] + page.features.map({ $0.textKey }) {
                for lang in ["de", "en"] {
                    let resolved = (CoreStrings.table[key]
                        ?? OnboardingL10n.table[key])?.resolved(lang)
                    XCTAssertNotNil(resolved, "missing \(lang) for \(key)")
                    XCTAssertFalse(resolved!.isEmpty, "empty \(lang) for \(key)")
                }
            }
        }

        // Re-Eval Runde 2 (S1): the emoji hero died. The welcome page
        // carries NO glyph (the view renders the sealed-letter artifact);
        // every tour page carries an SF-Symbol NAME — plain ASCII, so an
        // emoji can never sneak back in through the script.
        XCTAssertNil(pages[0].symbol, "hero page renders the material seal, no glyph")
        for page in pages.dropFirst() {
            let symbol = page.symbol
            XCTAssertNotNil(symbol, "\(page.id): tour pages need a vignette symbol")
            XCTAssertFalse(symbol!.isEmpty)
            XCTAssertTrue(symbol!.allSatisfy { $0.isASCII },
                          "\(page.id): „\(symbol!)“ is no SF-Symbol name")
        }
    }

    func testRecoveryStringsExistInBothLanguages() {
        let keys = [
            "onboarding.next", "onboarding.skip", "onboarding.pageA11y",
            "pairing.rejoin", "pairing.rejoin.title", "pairing.rejoin.subtitle",
            "pairing.rejoin.keyPlaceholder", "pairing.rejoin.keyFound",
            "pairing.rejoin.replaceToggle", "pairing.rejoin.replacePlaceholder",
            "pairing.rejoin.help", "pairing.rejoin.badKey", "pairing.rejoin.badReplace",
            "pairing.rejoin.revoked", "pairing.coupleFullRejoin",
            "settings.security",
            "recovery.title", "recovery.settingsHint", "recovery.sheet.subtitle",
            "recovery.ceremony.title", "recovery.ceremony.subtitle",
            "recovery.ceremony.point1", "recovery.ceremony.point1.local",
            "recovery.ceremony.point2", "recovery.ceremony.point3",
            "recovery.ceremony.done", "recovery.copy", "recovery.copied",
            "recovery.key.section", "recovery.status.stored", "recovery.status.missing",
            "recovery.status.since", "recovery.storage.synced", "recovery.storage.local",
            "recovery.reveal", "recovery.hide",
            "recovery.issue", "recovery.rotate", "recovery.rotate.confirmTitle",
            "recovery.rotate.confirmBody", "recovery.issue.confirmBody",
            "recovery.rotated", "recovery.issued", "recovery.key.hint",
            "recovery.replace.section", "recovery.replace.explain",
            "recovery.replace.generate", "recovery.replace.expires",
            "recovery.replace.expired", "recovery.replace.cancel",
            "recovery.replace.cancelled", "recovery.replace.hint",
            "recovery.how.section", "recovery.how.point1", "recovery.how.point2",
            "recovery.how.point3", "recovery.sessionHealed",
            "whatsnew.10_0.safetynet.title", "whatsnew.10_0.safetynet.body",
            "whatsnew.10_0.healing.title", "whatsnew.10_0.healing.body",
            "whatsnew.10_0.settings.title", "whatsnew.10_0.settings.body",
        ]
        for key in keys {
            guard let text = CoreStrings.table[key] else {
                XCTFail("missing key \(key)")
                continue
            }
            XCTAssertFalse(text.resolved("de").isEmpty, "empty DE for \(key)")
            XCTAssertFalse(text.resolved("en").isEmpty, "empty EN for \(key)")
            XCTAssertNotEqual(text.resolved("de"), text.resolved("en"),
                              "DE == EN for \(key) — untranslated?")
        }
        // Placeholder contracts used by the views.
        XCTAssertTrue(CoreStrings.table["recovery.replace.expires"]!.resolved("de").contains("{time}"))
        XCTAssertTrue(CoreStrings.table["recovery.replace.explain"]!.resolved("en").contains("{name}"))
        XCTAssertTrue(CoreStrings.table["recovery.status.since"]!.resolved("en").contains("{date}"))
    }

    // MARK: Widget snapshot signature (performance pass)

    func testSnapshotSignatureIgnoresTimestampButSeesContent() {
        var a = WidgetSnapshot()
        a.partnerName = "Mia"
        a.streak = 7
        a.updatedAt = Date(timeIntervalSince1970: 1_000)

        var b = a
        b.updatedAt = Date(timeIntervalSince1970: 2_000)
        // Same content, different write time → same signature (no reload).
        XCTAssertNotNil(a.contentSignature)
        XCTAssertEqual(a.contentSignature, b.contentSignature)

        // Any visible change → different signature (reload happens).
        var c = a
        c.streak = 8
        XCTAssertNotEqual(a.contentSignature, c.contentSignature)
        var d = a
        d.partnerPresenceMode = "focus"
        XCTAssertNotEqual(a.contentSignature, d.contentSignature)
    }

    func testSnapshotSignatureIsDeterministic() {
        var snapshot = WidgetSnapshot()
        snapshot.partnerName = "Robin"
        snapshot.daysTogether = 1234
        snapshot.dailyBothAnswered = true
        // Sorted-keys encoding: byte-identical across repeated encodes.
        XCTAssertEqual(snapshot.contentSignature, snapshot.contentSignature)
    }
}
