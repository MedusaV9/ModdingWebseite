import XCTest
@testable import SoooDreamyLogic

/// Client half of sync contract h (games_catalog.test.js is the server half):
/// the ```gametypes block in docs/API.md is the canonical 28-type manifest —
/// GAME_TYPES on the server is drift-watched against it, and `GameKind` in
/// Core/Models.swift must carry EXACTLY the same raw values, or the Play hub
/// silently hides server games again (the FXC-3 finding: 28 vs 25).
/// Models.swift is app-only (not in the Linux target), so this scans the
/// source like L10nUsageTests does.
final class GameKindParityTests: XCTestCase {

    /// Package root (ios/), derived from this file's location.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/ — the package root

    /// The one machine-readable list: ```gametypes … ``` in docs/API.md.
    private func documentedTypes() throws -> [String] {
        let doc = Self.packageDir
            .deletingLastPathComponent()          // SoooDreamy/
            .appendingPathComponent("docs/API.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "```gametypes\\n([\\s\\S]*?)```")
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        XCTAssertEqual(matches.count, 1, "docs/API.md must contain exactly ONE ```gametypes block")
        guard let match = matches.first, let body = Range(match.range(at: 1), in: text) else {
            return []
        }
        return text[body].split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Raw values of `GameKind`, parsed from the enum declaration in
    /// Core/Models.swift (all cases are bare lowercase identifiers — none
    /// carries an explicit raw value, so case name == rawValue).
    private func gameKindCases() throws -> [String] {
        let models = Self.packageDir.appendingPathComponent("SoooDreamy/Core/Models.swift")
        let source = try String(contentsOf: models, encoding: .utf8)
        guard let start = source.range(of: "enum GameKind"),
              let end = source.range(of: "var id", range: start.upperBound..<source.endIndex) else {
            XCTFail("Core/Models.swift: could not locate the GameKind declaration")
            return []
        }
        let body = source[start.upperBound..<end.lowerBound]
        var cases: [String] = []
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("case ") else { continue }
            cases += trimmed.dropFirst("case ".count)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return cases
    }

    func testGameKindMatchesTheCanonical28TypeManifest() throws {
        let documented = try documentedTypes()
        let cases = try gameKindCases()

        XCTAssertEqual(documented.count, 28, "the canonical manifest has exactly 28 types")
        XCTAssertEqual(Set(documented).count, documented.count,
                       "docs/API.md gametypes block contains duplicates")
        XCTAssertEqual(Set(cases).count, cases.count,
                       "GameKind declares a case twice")

        let missing = Set(documented).subtracting(cases).sorted()
        let extra = Set(cases).subtracting(documented).sorted()
        XCTAssertTrue(missing.isEmpty,
                      "GameKind is missing server types \(missing) — the hub would hide them")
        XCTAssertTrue(extra.isEmpty,
                      "GameKind declares types the server does not know: \(extra)")
    }
}
