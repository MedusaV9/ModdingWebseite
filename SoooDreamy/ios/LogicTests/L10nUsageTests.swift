import XCTest
@testable import SoooDreamyLogic

/// Static source scan: every PLAIN literal key passed to `L10n.t("...")`
/// anywhere in the app or widget sources must exist in the merged string
/// tables. Dynamic keys (interpolations like `"touch.\(kind)"`, ternaries,
/// variables) are deliberately skipped — only single plain string literals
/// are extracted.
final class L10nUsageTests: XCTestCase {

    /// Package root (ios/), derived from this file's location: LogicTests/L10nUsageTests.swift.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/ — the package root

    /// Matches `L10n.t("plain.literal"` followed by `,` or `)`.
    /// `[^"\\]*` rejects any backslash, so interpolated keys like
    /// `"games.card.\(kind).title"` can never match.
    private static let literalKeyPattern = #"L10n\.t\(\s*"([^"\\]*)"\s*[,)]"#

    private func swiftFiles(under relativeDir: String) throws -> [URL] {
        let root = Self.packageDir.appendingPathComponent(relativeDir, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            XCTFail("expected source directory at \(root.path)")
            return []
        }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Drops comment-only lines (`//` / `///`) so usage examples in doc
    /// comments — e.g. `L10n.t("home.hello", ...)` in L10n.swift — don't
    /// count as real key usages.
    private func strippingCommentOnlyLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// All plain literal keys used in `L10n.t(...)` calls, mapped to the files using them.
    private func extractUsedKeys() throws -> [String: Set<String>] {
        let regex = try NSRegularExpression(pattern: Self.literalKeyPattern)
        var usage: [String: Set<String>] = [:]
        for dir in ["SoooDreamy", "Widgets"] {
            for file in try swiftFiles(under: dir) {
                let source = strippingCommentOnlyLines(try String(contentsOf: file, encoding: .utf8))
                let range = NSRange(source.startIndex..., in: source)
                regex.enumerateMatches(in: source, range: range) { match, _, _ in
                    guard let match, let keyRange = Range(match.range(at: 1), in: source) else { return }
                    let key = String(source[keyRange])
                    usage[key, default: []].insert(file.lastPathComponent)
                }
            }
        }
        return usage
    }

    private var mergedTableKeys: Set<String> {
        Set(CoreStrings.table.keys)
            .union(ChatL10n.table.keys)
            .union(GamesL10n.table.keys)
            .union(MemoriesL10n.table.keys)
    }

    func testEveryLiteralKeyUsedInSourcesExistsInTables() throws {
        let usage = try extractUsedKeys()
        XCTAssertFalse(usage.isEmpty, "source scan found no L10n.t(\"...\") literals — scan is broken")

        let tableKeys = mergedTableKeys
        let missing = usage.filter { !tableKeys.contains($0.key) }
        XCTAssertTrue(missing.isEmpty, "keys used in sources but missing from all tables: " +
                      missing.sorted { $0.key < $1.key }
                          .map { "\"\($0.key)\" (in \($0.value.sorted().joined(separator: ", ")))" }
                          .joined(separator: "; "))

        // Informational only: table keys never referenced by a plain literal.
        // These may still be used via dynamic keys ("touch.received.\(type)",
        // "language.\(rawValue)", …), so this must NOT fail the test.
        let unreferenced = tableKeys.subtracting(usage.keys).sorted()
        print("[L10nUsageTests] \(usage.count) literal keys referenced in sources; " +
              "\(unreferenced.count) of \(tableKeys.count) table keys never referenced by a plain literal:")
        for key in unreferenced {
            print("[L10nUsageTests]   unreferenced: \(key)")
        }
    }
}
