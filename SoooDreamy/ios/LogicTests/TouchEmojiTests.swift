import XCTest
@testable import SoooDreamyLogic

/// `TouchEmoji.map` is the widget-side mirror of the app's `TouchKind.emoji`
/// (the app models aren't compiled into the widget extension). Keep both in
/// sync — live activities render touches from their raw string type.
final class TouchEmojiTests: XCTestCase {

    /// Must match `TouchKind` raw values and emojis in SoooDreamy/Core/Models.swift.
    private let expected: [String: String] = [
        "heartbeat": "💓",
        "kiss": "😘",
        "hug": "🫂",
        "missyou": "🥺",
        "tickle": "🪶",
        "thinking": "💭"
    ]

    func testMapsEveryKnownTouchType() {
        for (type, emoji) in expected {
            XCTAssertEqual(TouchEmoji.map(type), emoji, "wrong emoji for touch type \(type)")
        }
    }

    func testUnknownTypesFallBackToNeutralHeart() {
        XCTAssertEqual(TouchEmoji.map(""), "💞")
        XCTAssertEqual(TouchEmoji.map("something-new"), "💞")
    }

    /// Guards against drift: the raw types in the app enum (mirrored here)
    /// must all be covered explicitly, i.e. never hit the fallback.
    func testNoKnownTypeHitsFallback() {
        for type in expected.keys {
            XCTAssertNotEqual(TouchEmoji.map(type), "💞", "\(type) fell through to the fallback emoji")
        }
    }
}
