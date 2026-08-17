import XCTest
@testable import SoooDreamyLogic

/// Pins the Schreibstube reconciliation law (re-eval 2, Befund 1;
/// Fix-Runde 3, S1): a server ACK REPLACES the sender's own optimistic
/// temp in place — same array position, same `chatRowID` — so the
/// transcript row never remounts on the local→server id swap and
/// Spindelstich/Legen can never replay. Identity and temp matching are
/// SENDER-SCOPED: the server only enforces cmid uniqueness per sender,
/// so both partners may carry the same clientMessageId and must coexist
/// as two rows. Also pins the Kitsch-Budget gate of the send-button
/// heart burst (Befund 5): only hearts earn hearts.
final class ChatVersoehnungTests: XCTestCase {

    /// Minimal test double of what the law sees of a `Message`.
    private struct Zettel: VersoehnbarerZettel, Equatable {
        let id: String
        let senderId: String
        let clientMessageId: String?
        let createdAt: Date
        var text = ""
    }

    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func zettel(_ id: String, von senderId: String = "me",
                        cmid: String? = nil,
                        at offset: TimeInterval = 0, text: String = "") -> Zettel {
        Zettel(id: id, senderId: senderId, clientMessageId: cmid,
               createdAt: t0.addingTimeInterval(offset), text: text)
    }

    // MARK: chatRowID — the identity that survives the id swap

    func testChatRowIDIsKeyedBySenderAndClientMessageIdWhereOneExists() {
        XCTAssertEqual(zettel("local-abc", von: "me", cmid: "abc").chatRowID,
                       "cmid-me-abc")
        XCTAssertEqual(zettel("srv-1", von: "me", cmid: "abc").chatRowID,
                       "cmid-me-abc")
        XCTAssertEqual(zettel("srv-2").chatRowID, "srv-2")
        // S1: the SAME cmid from the other sender is a DIFFERENT row —
        // two distinct ForEach ids, no Dictionary-key collision.
        XCTAssertNotEqual(zettel("srv-3", von: "partner", cmid: "abc").chatRowID,
                          zettel("local-abc", von: "me", cmid: "abc").chatRowID)
    }

    func testRowIdentitySurvivesTheLocalToServerIdSwap() {
        let temp = zettel("local-abc", cmid: "abc", at: 5)
        let ack = zettel("srv-9", cmid: "abc", at: 5)
        XCTAssertNotEqual(temp.id, ack.id, "the swap really swaps the id")
        XCTAssertEqual(temp.chatRowID, ack.chatRowID,
                       "the ForEach id must NOT change on the ACK")
    }

    // MARK: Sender scope (Fix-Runde 3, S1)

    func testSameClientMessageIdFromBothPartnersCoexists() {
        // My optimistic temp is waiting for its ACK — and the PARTNER'S
        // message with the very same cmid arrives first. It must never
        // replace my temp: two senders, two rows.
        let before = [zettel("local-abc", von: "me", cmid: "abc", at: 5, text: "meins")]
        let fremd = zettel("srv-7", von: "partner", cmid: "abc", at: 6, text: "deins")
        let after = ChatVersoehnung.reconciled(before, with: fremd)

        XCTAssertEqual(after.map(\.id), ["local-abc", "srv-7"],
                       "the partner's message appends — my temp survives")
        XCTAssertEqual(Set(after.map(\.chatRowID)).count, after.count,
                       "no duplicate ForEach ids despite the shared cmid")
        // A DIFFERENT server id with an unmatched cmid appends too (the
        // pre-S1 foreign-cmid pin, still true under sender scope).
        let stranger = zettel("srv-5", von: "me", cmid: "xyz", at: 3)
        XCTAssertEqual(ChatVersoehnung.reconciled(before, with: stranger).map(\.id),
                       ["srv-5", "local-abc"],
                       "unmatched cmid appends chronologically instead of replacing")
    }

    // MARK: The reconciliation law itself

    func testAckReplacesTheTempAtItsIndexWithoutIdentityLoss() {
        let before = [zettel("srv-1", von: "partner", at: 0),
                      zettel("local-abc", cmid: "abc", at: 5),
                      zettel("srv-2", von: "partner", at: 9)]
        let ack = zettel("srv-9", cmid: "abc", at: 6, text: "hallo")
        let after = ChatVersoehnung.reconciled(before, with: ack)

        XCTAssertEqual(after.count, before.count, "replace, never remove+insert")
        XCTAssertEqual(after[1].id, "srv-9", "the ACK sits at the temp's index")
        XCTAssertEqual(after[1].text, "hallo", "server truth wins")
        XCTAssertEqual(after.map(\.chatRowID), before.map(\.chatRowID),
                       "the row-id sequence is UNCHANGED — no remount, no "
                       + "list re-animation on the ACK")
    }

    func testSameServerIdReplacesInPlaceIdempotently() {
        // POST response and socket echo carry the same server id — the
        // second arrival must fold into the first, never duplicate.
        let before = [zettel("srv-1", von: "partner", at: 0),
                      zettel("srv-9", cmid: "abc", at: 5)]
        let echo = zettel("srv-9", cmid: "abc", at: 5, text: "echo")
        let after = ChatVersoehnung.reconciled(before, with: echo)
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(after[1].text, "echo")
    }

    func testUnknownMessageInsertsChronologically() {
        let before = [zettel("srv-1", at: 0), zettel("srv-3", at: 10)]
        let incoming = zettel("srv-2", von: "partner", at: 5)
        let after = ChatVersoehnung.reconciled(before, with: incoming)
        XCTAssertEqual(after.map(\.id), ["srv-1", "srv-2", "srv-3"])
    }

    func testAckBeforeInsertYieldsExactlyOneRow() {
        // The EMPIRICALLY proven race (Fix-Runde 4, S1): the server ACK
        // lands FIRST, the local temp insert arrives LATE — the old pin
        // only replayed the ACK and never exercised the late temp, which
        // used to append a second row with the SAME chatRowID
        // (ids ["srv-9", "local-abc"], rowIDs both "cmid-me-abc":
        // duplicate ForEach ids, Dictionary crash in the Legen slots).
        let ack = zettel("srv-9", cmid: "abc", at: 5, text: "hallo")
        var transcript = ChatVersoehnung.reconciled([], with: ack)
        XCTAssertEqual(transcript.map(\.id), ["srv-9"])

        let lateTemp = zettel("local-abc", cmid: "abc", at: 5, text: "hallo")
        transcript = ChatVersoehnung.reconciled(transcript, with: lateTemp)
        XCTAssertEqual(transcript.map(\.id), ["srv-9"],
                       "server truth wins — the late temp is consumed, not appended")
        XCTAssertEqual(transcript[0].text, "hallo", "the ACK's content stands")
        XCTAssertEqual(transcript[0].chatRowID, "cmid-me-abc")
        XCTAssertEqual(Set(transcript.map(\.chatRowID)).count, transcript.count,
                       "ONE row with the server id — no duplicate ForEach ids")

        // Later arrivals of the same send (POST response, page merge)
        // still fold into that ONE row.
        transcript = ChatVersoehnung.reconciled(transcript, with: ack)
        XCTAssertEqual(transcript.count, 1, "ONE row, however often the ACK arrives")

        // Sender scope survives the reversed race too: the PARTNER'S
        // temp with the same cmid is its OWN row — my ACK never eats it.
        let partnerTemp = zettel("local-p", von: "partner", cmid: "abc", at: 6)
        let both = ChatVersoehnung.reconciled(transcript, with: partnerTemp)
        XCTAssertEqual(both.map(\.id), ["srv-9", "local-p"])
        XCTAssertEqual(Set(both.map(\.chatRowID)).count, both.count)
    }

    // MARK: Abläufe (8. + 9. Pin — Fix-Runde 3, S1)

    func testPageMergeFoldsBothPartnersSharedCmidWithoutTheft() {
        // 8. Pin — the page-merge Ablauf: while my temp waits, a fetched
        // page delivers BOTH partners' messages with the same cmid. My
        // ACK replaces my temp at its index; the partner's message
        // inserts as its own row; nothing is stolen, nothing doubled.
        var transcript = [zettel("srv-1", von: "partner", at: 0),
                          zettel("local-abc", cmid: "abc", at: 5, text: "meins")]
        let page = [zettel("srv-9", cmid: "abc", at: 5, text: "meins"),
                    zettel("srv-10", von: "partner", cmid: "abc", at: 6, text: "deins")]
        for message in page {
            transcript = ChatVersoehnung.reconciled(transcript, with: message)
        }
        XCTAssertEqual(transcript.map(\.id), ["srv-1", "srv-9", "srv-10"])
        XCTAssertEqual(transcript[1].chatRowID, "cmid-me-abc",
                       "my row identity survived the merge")
        XCTAssertEqual(transcript[2].chatRowID, "cmid-partner-abc",
                       "the partner's same-cmid message is its OWN row")
        XCTAssertEqual(Set(transcript.map(\.chatRowID)).count, transcript.count)
    }

    func testOutboxRetryFlowKeepsOneRowAcrossFailureAndRetry() {
        // 9. Pin — the outbox-retry Ablauf: the optimistic temp stays in
        // the transcript across a failed transmit (nothing reconciles),
        // the RETRY's ACK then replaces it in place, and the trailing
        // socket echo stays idempotent. Never two rows for one send.
        let temp = zettel("local-abc", cmid: "abc", at: 5, text: "queued")
        var transcript = [zettel("srv-1", von: "partner", at: 0), temp]

        // Attempt 1 fails: no ACK, the temp keeps waiting.
        XCTAssertEqual(transcript.filter { $0.clientMessageId == "abc" }.count, 1)

        // Attempt 2 (retry) succeeds — the ACK folds into the temp's row.
        let ack = zettel("srv-9", cmid: "abc", at: 5, text: "queued")
        transcript = ChatVersoehnung.reconciled(transcript, with: ack)
        XCTAssertEqual(transcript.map(\.id), ["srv-1", "srv-9"])
        XCTAssertEqual(transcript[1].chatRowID, temp.chatRowID,
                       "the retry lands in the SAME row the send opened")

        // The socket echo of the retried send changes nothing.
        transcript = ChatVersoehnung.reconciled(transcript, with: ack)
        XCTAssertEqual(transcript.count, 2, "echo after retry never duplicates")
    }

    // MARK: Kitsch budget — hearts only for hearts (Befund 5 + Fix-Runde 3, S3)

    func testTraegtHerzOnlyFiresForHeartContent() {
        // Parametrized over the heart family — including the broken
        // heart, variation-selector forms and the ZWJ compositions.
        let herzen: [String] = [
            "Ich liebe dich ❤️",   // VS16 form
            "❤",                    // bare U+2764
            "💔",                   // broken heart (Fix-Runde 3, S3)
            "❤️‍🔥",                  // heart on fire (ZWJ)
            "❤️‍🩹",                  // mending heart (ZWJ)
            "💙", "🩷", "🩶", "🩵", "♥",
            "gute nacht 🩷",
        ]
        for text in herzen {
            XCTAssertTrue(ChatSendeRegeln.traegtHerz(text),
                          "\(text) speaks heart and must earn the burst")
        }
        let keineHerzen = ["bis gleich!", "😀🎉👍", "", "1 + 1 < 3", "🫶"]
        for text in keineHerzen {
            XCTAssertFalse(ChatSendeRegeln.traegtHerz(text),
                           "\(text) must land quietly — no heart burst")
        }
    }
}
