import XCTest

/// Re-Eval Befund 19 (Architektur): static source scan over every PLAIN
/// `@AppStorage("literal.key")` declaration in the app, widget and shared
/// sources — the L10nUsageTests pattern applied to the defaults store.
///
/// Two rules are pinned:
///  1. **Namespace**: every key wears one of the allowed dotted prefixes.
///     A bare `"heartHintDone"` or a fresh unreviewed namespace fails here.
///  2. **Eindeutigkeit**: a key literal may appear in more than one FILE
///     only when that sharing is deliberate and pinned below (two views
///     binding the same store, e.g. the dashboard's hide toggles living in
///     both the pane and its customization sheet). A new key that
///     accidentally reuses an existing literal shows up as an unpinned
///     cross-file collision and fails.
///
/// Symbolic keys (`@AppStorage(SeasonSettings.prefKey)`) are deliberately
/// out of scope — same stance as L10nUsageTests toward dynamic L10n keys:
/// the constant's single definition is its own namespace discipline.
final class AppStorageNamespaceTests: XCTestCase {

    /// Package root (ios/), derived from this file's location.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/ — the package root

    /// Matches `@AppStorage("plain.literal"` — `[^"\\]*` rejects any
    /// backslash, so interpolated keys can never match.
    private static let literalKeyPattern = #"@AppStorage\(\s*"([^"\\]+)""#

    /// Second scan (Re-Eval Runde 2, Architektur): raw defaults calls —
    /// `UserDefaults.standard.set(_, forKey: "literal")` and friends —
    /// escaped the namespace law entirely (SoooDreamyApp's What's-New
    /// version stamp). Every `forKey: "…"` literal in these sources IS a
    /// defaults key today (pinned below); interpolated keys stay out of
    /// scope like their `@AppStorage` siblings.
    private static let forKeyLiteralPattern = #"forKey:\s*"([^"\\]+)""#

    /// The reviewed key namespaces. The station prefixes mirror the app's
    /// room names; `sooodreamy.` is the app-global namespace. `amt.` and
    /// `spieltisch.` are reserved for their stations even though no key
    /// wears them yet — new keys there pass without touching this test.
    private static let allowedPrefixes: [String] = [
        "amt.",
        "chat.",
        "dashboard.",
        "home.",
        "memories.",
        "postfach.",
        "sooodreamy.",
        "spieltisch.",
        "weekplan.",
        "whatsNew.",
        "zustelldienst.",
    ]

    /// Keys DELIBERATELY declared in more than one file: two views binding
    /// the same UserDefaults store. Every entry pins the exact file set, so
    /// a third accidental binding of the same literal still fails.
    private static let pinnedSharedKeys: [String: Set<String>] = [
        // Dashboard customization: the pane and its header sheet edit the
        // same hide/pin switches.
        "dashboard.hide.games": ["DashboardView.swift", "DashboardHeaderView.swift"],
        "dashboard.hide.moments": ["DashboardView.swift", "DashboardHeaderView.swift"],
        "dashboard.hide.rituals": ["DashboardView.swift", "DashboardHeaderView.swift"],
        "dashboard.pinnedGroup": ["DashboardView.swift", "DashboardHeaderView.swift"],
        // The polaroid develop-day is one shared ritual across both
        // memory cards.
        "postfach.polaroid.entwickeltTag": ["FlashbackCard.swift", "OnThisDayCard.swift"],
        // The staging toggle lives in Settings and is honored on the
        // dashboard.
        "zustelldienst.rundenInszenieren": ["DashboardView.swift", "SettingsView.swift"],
        // The What's-New stamp: the App marks the presented version with a
        // RAW write on the launch path (the forKey scan catches it now);
        // the dashboard card binds the same store via @AppStorage.
        "whatsNew.lastPresentedVersion": ["DashboardView.swift", "SoooDreamyApp.swift"],
    ]

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

    /// Drops comment-only lines so `@AppStorage` examples in doc comments
    /// never count as real declarations.
    private func strippingCommentOnlyLines(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// All plain literal defaults keys mapped to the files declaring them:
    /// `@AppStorage("…")` declarations AND raw `forKey: "…"` calls — one
    /// map, so the namespace and cross-file laws govern both doors into
    /// the store (Re-Eval Runde 2: the raw door stood unguarded).
    private func extractDeclaredKeys() throws -> [String: Set<String>] {
        let regexes = try [Self.literalKeyPattern, Self.forKeyLiteralPattern]
            .map { try NSRegularExpression(pattern: $0) }
        var usage: [String: Set<String>] = [:]
        for dir in ["SoooDreamy", "Shared", "Widgets"] {
            for file in try swiftFiles(under: dir) {
                let source = strippingCommentOnlyLines(try String(contentsOf: file, encoding: .utf8))
                let range = NSRange(source.startIndex..., in: source)
                for regex in regexes {
                    regex.enumerateMatches(in: source, range: range) { match, _, _ in
                        guard let match, let keyRange = Range(match.range(at: 1), in: source) else { return }
                        let key = String(source[keyRange])
                        usage[key, default: []].insert(file.lastPathComponent)
                    }
                }
            }
        }
        return usage
    }

    /// The raw-write door alone must keep matching — if a refactor moves
    /// every raw call behind constants, the guard should be RETIRED
    /// consciously, not rot silently.
    func testForKeyScanStillSeesTheRawDoor() throws {
        let regex = try NSRegularExpression(pattern: Self.forKeyLiteralPattern)
        var hits = 0
        for dir in ["SoooDreamy", "Shared", "Widgets"] {
            for file in try swiftFiles(under: dir) {
                let source = strippingCommentOnlyLines(try String(contentsOf: file, encoding: .utf8))
                hits += regex.numberOfMatches(
                    in: source, range: NSRange(source.startIndex..., in: source))
            }
        }
        XCTAssertGreaterThan(hits, 0,
                             "no raw forKey: \"…\" literals found — retire or fix the second scan")
    }

    func testEveryAppStorageKeyWearsAnAllowedNamespacePrefix() throws {
        let declared = try extractDeclaredKeys()
        XCTAssertFalse(declared.isEmpty,
                       "source scan found no @AppStorage(\"...\") literals — scan is broken")

        let violations = declared.filter { key, _ in
            !Self.allowedPrefixes.contains(where: key.hasPrefix)
        }
        XCTAssertTrue(violations.isEmpty, "keys outside the reviewed namespaces: " +
                      violations.sorted { $0.key < $1.key }
                          .map { "\"\($0.key)\" (in \($0.value.sorted().joined(separator: ", ")))" }
                          .joined(separator: "; "))
    }

    func testCrossFileKeySharingIsPinnedAndDeliberate() throws {
        let declared = try extractDeclaredKeys()
        XCTAssertFalse(declared.isEmpty,
                       "source scan found no @AppStorage(\"...\") literals — scan is broken")

        // Every key living in more than one file must be pinned WITH its
        // exact file set …
        let shared = declared.filter { $0.value.count > 1 }
        for (key, files) in shared.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(Self.pinnedSharedKeys[key], files,
                           "\"\(key)\" is declared in \(files.sorted()) — cross-file " +
                           "sharing must be deliberate and pinned in pinnedSharedKeys")
        }
        // … and every pinned entry must still be real (no stale pins).
        for (key, files) in Self.pinnedSharedKeys.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(declared[key], files,
                           "pinned shared key \"\(key)\" no longer matches the sources " +
                           "(found \(declared[key]?.sorted() ?? [])) — update the pin")
        }
    }
}
