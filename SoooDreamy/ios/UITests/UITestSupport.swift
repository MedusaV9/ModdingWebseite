import XCTest

// Shared plumbing of the XCUITest suite (P1-D). Everything here is
// DEFENSIVE by design: the suite's first real run happens on the CI
// macos-26 runner (no local simulator on the Linux dev VM), so every
// interaction waits on existence instead of sleeping, every anchor is a
// REAL user-facing label from the L10n tables, and every key moment
// leaves an XCTAttachment screenshot behind (lifetime .keepAlways — the
// CI job exports them from the .xcresult bundle as review artifacts).
//
// State strategy — the app has NO reset launch argument (and P1-D must
// not add app code): determinism comes from three layers instead.
//   1. The CI step ERASES the simulator before `xcodebuild test`, so
//      test01 really is a first launch.
//   2. Tests run alphabetically in ONE class (test01…test05, scheme
//      parallelization off), so cross-test UserDefaults leakage is a
//      known, ordered quantity.
//   3. Every launch pins the persisted flags it depends on through the
//      NSArgumentDomain (highest-precedence UserDefaults read): the
//      intro-seen flag `sooodreamy.cinematicIntroSeen`, the demo flag
//      `demo.active` (see App/ScreenshotSeed.swift `DemoMode.flagKey`)
//      and the chosen language `sooodreamy.appLanguage` (L10n).

// MARK: - UserDefaults keys mirrored from the app (read-only contract)

enum AppDefaultsKey {
    /// CinematicIntroGate.seenKey — first-launch cinema gate.
    static let introSeen = "sooodreamy.cinematicIntroSeen"
    /// DemoMode.flagKey — the ONLY thing demo mode persists.
    static let demoActive = "demo.active"
    /// L10n.storageKey — non-nil once a language was explicitly chosen.
    static let appLanguage = "sooodreamy.appLanguage"
}

// MARK: - Launch configuration

struct LaunchConfig {
    /// Pin the cinema gate: false forces the first-launch cinema (the
    /// argument domain outranks whatever an earlier test persisted).
    var introSeen = true
    /// Pin the demo flag. nil leaves whatever earlier tests persisted.
    var demoActive: Bool? = false
    /// Pin the UI language. The cinema's language gate no longer keys off
    /// this (it has its own `sooodreamy.languageGateDone`, written only by
    /// explicit picks) — false still leaves the key alone for honesty.
    var germanChosen = true
    var extraArguments: [String] = []

    func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        var args: [String] = [
            // Deterministic German UI + locale for every assertion below.
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
            "-\(AppDefaultsKey.introSeen)", introSeen ? "YES" : "NO",
        ]
        if let demoActive {
            args += ["-\(AppDefaultsKey.demoActive)", demoActive ? "YES" : "NO"]
        }
        if germanChosen {
            args += ["-\(AppDefaultsKey.appLanguage)", "de"]
        }
        args += extraArguments
        app.launchArguments += args
        return app
    }
}

// MARK: - XCTestCase helpers

extension XCTestCase {

    /// Default explicit-wait budget. CI simulators are slow on first
    /// frames — generous beats flaky.
    static var uiTimeout: TimeInterval { 20 }

    /// Launch with pinned state and wait until the process is really in
    /// the foreground. Cold CI simulators time the FIRST launch out
    /// ("Timed out while launching via Xcode", run 31902067688) — so this
    /// waits on the app state explicitly and retries ONCE before letting
    /// the element waits fail the test.
    @discardableResult
    func launchApp(_ config: LaunchConfig) -> XCUIApplication {
        let app = config.makeApp()
        for attempt in 1...2 {
            app.launch()
            let foreground = NSPredicate(
                format: "state == %d",
                XCUIApplication.State.runningForeground.rawValue)
            let settled = XCTNSPredicateExpectation(predicate: foreground, object: app)
            if XCTWaiter().wait(for: [settled], timeout: 90) == .completed { break }
            if attempt == 1 { app.terminate() }
        }
        return app
    }

    /// Expectation-based existence wait (never a bare sleep).
    @discardableResult
    func waitFor(_ element: XCUIElement,
                 timeout: TimeInterval = XCTestCase.uiTimeout,
                 _ message: String,
                 file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let ok = element.waitForExistence(timeout: timeout)
        if !ok { XCTFail(message, file: file, line: line) }
        return ok
    }

    /// Wait until an element leaves the hierarchy (search filters,
    /// dismissed sheets). Polls via expectation, not sleep.
    @discardableResult
    func waitForDisappearance(of element: XCUIElement,
                              timeout: TimeInterval = XCTestCase.uiTimeout) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: gone, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Screenshot attachment that ALWAYS survives into the .xcresult.
    func attachScreenshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

// MARK: - Element lookup helpers

extension XCUIApplication {

    /// Any button whose accessibility label begins with `prefix` — many
    /// app buttons carry richer a11y labels than their visible text
    /// (e.g. the language cards: "Deutsch. Die App spricht …").
    func button(startingWith prefix: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Any static text containing `fragment` (chapter captions, toasts).
    func text(containing fragment: String) -> XCUIElement {
        staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Tab-bar button by label prefix — the chat tab's label grows with
    /// the unread count ("Schreibstube, 2 ungelesene Nachrichten"), so
    /// exact matches would be brittle. Falls back to a plain button query
    /// when the native TabView exposes no tabBars container.
    func tabButton(startingWith prefix: String) -> XCUIElement {
        let inBar = tabBars.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        if inBar.exists { return inBar }
        return button(startingWith: prefix)
    }

    /// Switch tabs ROBUSTLY. The bar no longer minimizes (the minimize
    /// behavior was removed — on devices it only re-expanded at scroll
    /// top), so the tab buttons should always be present; the retry loop
    /// with its restore swipes stays as harmless CI armor against slow
    /// first frames and transient scroll-edge chrome. Prefers the stable
    /// a11y id, falls back to the label prefix.
    func switchTab(id: String, labelPrefix: String,
                   file: StaticString = #filePath, line: UInt = #line) {
        for attempt in 0..<6 {
            let byId = buttons[id].exists ? buttons[id] : tabBars.buttons[id]
            let candidate = byId.exists ? byId : tabButton(startingWith: labelPrefix)
            if candidate.waitForExistence(timeout: 2), candidate.isHittable {
                candidate.tap()
                return
            }
            // Nudge the scroll position and let the chrome settle before
            // re-querying (alternating velocities, run 31909619889).
            swipeDown(velocity: attempt % 2 == 0 ? .slow : .default)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
        XCTFail("Tab \(id) (\(labelPrefix)) nicht erreichbar",
                file: file, line: line)
    }

    /// Text field by placeholder fragment (placeholders end in a typo-
    /// graphic ellipsis the tests should not have to reproduce exactly).
    func textField(placeholderContaining fragment: String) -> XCUIElement {
        let byPlaceholder = textFields.matching(
            NSPredicate(format: "placeholderValue CONTAINS %@", fragment)).firstMatch
        if byPlaceholder.exists { return byPlaceholder }
        // SwiftUI sometimes surfaces the placeholder as the label.
        return textFields.matching(
            NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    /// Swipe up until the element exists and is hittable (LazyVStack /
    /// LazyVGrid content materializes only near the viewport).
    @discardableResult
    func scrollToFind(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return true }
            swipeUp(velocity: .slow)
        }
        // Existence still counts: elements pinned under bottom chrome
        // (accessory/tab bar) never turn hittable — `tapRobust` handles
        // the tap via coordinates in that case.
        return element.exists
    }

    /// Tap that survives „exists but not hittable" (bottom chrome overlap):
    /// falls back to a coordinate tap on the element's center.
    func tapRobust(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// A couple of gentle scroll rounds — the "no crash while scrolling"
    /// smoke motion for content-heavy tabs.
    func scrollRounds(_ rounds: Int = 2) {
        for _ in 0..<rounds { swipeUp() }
        for _ in 0..<rounds { swipeDown() }
    }
}

// MARK: - Server API client (test05)

/// Minimal synchronous JSON client against the REAL Node server the CI
/// step boots on localhost:4321 (docs/API.md). Used for the member-A
/// setup fallback and the in-test kiss verification — the CI step
/// additionally curls the journal after the run (belt and braces).
struct CoupleServerClient {
    let baseURL: URL

    struct AuthResult {
        let token: String
        let code: String
    }

    enum ClientError: Error, CustomStringConvertible {
        case transport(String)
        case badResponse(String)
        var description: String {
            switch self {
            case .transport(let detail): return "transport: \(detail)"
            case .badResponse(let detail): return "bad response: \(detail)"
            }
        }
    }

    /// Blocking request helper — the UI-test process may block freely.
    private func request(path: String, method: String, token: String? = nil,
                         body: [String: Any]? = nil) throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var payload: [String: Any]?
        var failure: String?
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                failure = error.localizedDescription
                return
            }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dictionary = object as? [String: Any] else {
                failure = "unparseable body"
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                failure = "HTTP \(http.statusCode): \(dictionary["error"] ?? "?")"
                return
            }
            payload = dictionary
        }.resume()
        if semaphore.wait(timeout: .now() + 20) == .timedOut {
            throw ClientError.transport("request timed out")
        }
        if let failure { throw ClientError.transport(failure) }
        guard let payload else { throw ClientError.badResponse("empty payload") }
        return payload
    }

    func health() throws -> [String: Any] {
        try request(path: "api/health", method: "GET")
    }

    /// POST /api/couples — creates the couple as member A ("Mia") and
    /// returns her bearer token + the 6-char pairing code.
    func createCouple() throws -> AuthResult {
        let payload = try request(path: "api/couples", method: "POST",
                                  body: ["name": "Mia", "avatar": "🦊",
                                         "color": "#60A5FA"])
        guard let token = payload["token"] as? String,
              let couple = payload["couple"] as? [String: Any],
              let code = couple["code"] as? String else {
            throw ClientError.badResponse("couples response without token/code")
        }
        return AuthResult(token: token, code: code)
    }

    /// GET /api/post/journal — true when the greeting (heartbeat touch)
    /// already arrived.
    func journalContainsGreeting(token: String) throws -> Bool {
        let payload = try request(path: "api/post/journal", method: "GET",
                                  token: token)
        guard let entries = payload["entries"] as? [[String: Any]] else {
            throw ClientError.badResponse("journal response without entries")
        }
        return entries.contains {
            ($0["kind"] as? String) == "touch" && ($0["type"] as? String) == "heartbeat"
        }
    }
}
