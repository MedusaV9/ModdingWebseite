import Foundation

/// Parses EXIF capture-time strings into a `Date` — pure string math, no
/// ImageIO, so the rules are pinned by Linux tests. The caller (the upload
/// pipeline) extracts `DateTimeOriginal`/`OffsetTimeOriginal` from the
/// ORIGINAL picked bytes, because our re-encode via
/// `jpegData(compressionQuality:)` writes a metadata-free JPEG — good for
/// privacy (GPS never leaves the phone), fatal for the capture date.
enum ExifDateParser {

    /// EXIF `DateTimeOriginal` is `"2024:07:15 14:30:00"` — colons in the
    /// date part, no zone. `offset` is EXIF `OffsetTimeOriginal` (`"+02:00"`),
    /// written by iPhones since iOS 13 but missing on many cameras; without
    /// one the wall clock is read in `fallback`. That is the least-wrong
    /// guess (couples mostly shoot photos in the zone they live in) and
    /// matches what the gallery's month grouping assumes anyway.
    static func takenAt(dateTimeOriginal: String, offset: String? = nil,
                        fallback: TimeZone = .current) -> Date? {
        let trimmed = dateTimeOriginal.trimmingCharacters(in: .whitespaces)
        let halves = trimmed.split(separator: " ")
        guard halves.count == 2 else { return nil }
        let date = halves[0].split(separator: ":").compactMap { Int($0) }
        let time = halves[1].split(separator: ":").compactMap { Int($0) }
        // The EXIF spec fills unknown fields with blanks or zeros
        // ("0000:00:00 00:00:00") — the range checks reject both.
        guard date.count == 3, time.count == 3,
              (1826...9999).contains(date[0]), // no photos before photography
              (1...12).contains(date[1]), (1...31).contains(date[2]),
              (0...23).contains(time[0]), (0...59).contains(time[1]),
              (0...59).contains(time[2]) else { return nil }
        var components = DateComponents()
        components.year = date[0]
        components.month = date[1]
        components.day = date[2]
        components.hour = time[0]
        components.minute = time[1]
        components.second = time[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(fromOffset: offset) ?? fallback
        return calendar.date(from: components)
    }

    /// `"+02:00"` / `"-05:30"` / `"Z"` → `TimeZone`; anything malformed → nil
    /// (the caller then falls back to the local zone instead of guessing).
    static func timeZone(fromOffset offset: String?) -> TimeZone? {
        guard let raw = offset?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw == "Z" { return TimeZone(secondsFromGMT: 0) }
        guard raw.count == 6, raw.first == "+" || raw.first == "-",
              raw[raw.index(raw.startIndex, offsetBy: 3)] == ":",
              let hours = Int(raw.dropFirst().prefix(2)),
              let minutes = Int(raw.suffix(2)),
              (0...14).contains(hours), (0...59).contains(minutes) else { return nil }
        let sign = raw.first == "-" ? -1 : 1
        return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
    }
}
