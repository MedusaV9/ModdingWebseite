import Foundation
import XCTest
@testable import SoooDreamyLogic

final class ExifDateParserTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func utcDate(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testOffsetTimeOriginalWinsOverFallbackZone() {
        // Shot 14:30 in Rome (+02:00) — the fallback zone must be ignored.
        XCTAssertEqual(
            ExifDateParser.takenAt(dateTimeOriginal: "2024:07:15 14:30:00",
                                   offset: "+02:00", fallback: utc),
            utcDate("2024-07-15T12:30:00Z"))
        XCTAssertEqual(
            ExifDateParser.takenAt(dateTimeOriginal: "2024:07:15 14:30:00",
                                   offset: "-05:30", fallback: utc),
            utcDate("2024-07-15T20:00:00Z"))
        XCTAssertEqual(
            ExifDateParser.takenAt(dateTimeOriginal: "2024:07:15 14:30:00",
                                   offset: "Z", fallback: berlin),
            utcDate("2024-07-15T14:30:00Z"))
    }

    func testMissingOrBrokenOffsetFallsBackToGivenZone() {
        // Berlin winter = UTC+1. Most non-phone cameras write no offset at all.
        XCTAssertEqual(
            ExifDateParser.takenAt(dateTimeOriginal: "2023:12:24 18:00:00",
                                   offset: nil, fallback: berlin),
            utcDate("2023-12-24T17:00:00Z"))
        XCTAssertEqual(
            ExifDateParser.takenAt(dateTimeOriginal: "2023:12:24 18:00:00",
                                   offset: "banana", fallback: berlin),
            utcDate("2023-12-24T17:00:00Z"))
    }

    func testCameraGarbageIsRejectedNotGuessed() {
        // The EXIF spec's "unknown" filler, blanks, and truncated stamps.
        for garbage in ["0000:00:00 00:00:00", "    :  :     :  :  ", "",
                        "2024:07:15", "2024:13:01 10:00:00", "2024:07:15 25:00:00",
                        "1503:04:05 06:07:08", "gestern nachmittag"] {
            XCTAssertNil(ExifDateParser.takenAt(dateTimeOriginal: garbage, fallback: utc),
                         "must reject: \(garbage)")
        }
    }

    func testOffsetParsingRules() {
        XCTAssertEqual(ExifDateParser.timeZone(fromOffset: "+02:00")?.secondsFromGMT(), 7_200)
        XCTAssertEqual(ExifDateParser.timeZone(fromOffset: "-05:30")?.secondsFromGMT(), -19_800)
        XCTAssertEqual(ExifDateParser.timeZone(fromOffset: "Z")?.secondsFromGMT(), 0)
        for garbage in [nil, "", "  ", "+2:00", "0200", "+02.00", "+15:00", "+02:60"] {
            XCTAssertNil(ExifDateParser.timeZone(fromOffset: garbage), "must reject: \(garbage ?? "nil")")
        }
    }
}
