// Standalone-Host (docs/IPAD-SETUP.md „Weg 3"): startet den Embedded-Server
// und lädt die Host-Seite (client/host/) — die WebView IST der Spiel-Server,
// Swift relayt nur Frames zwischen den Telefon-WebSockets und der Host-JS.
//
// Brücke (Vertrag in server/host-browser/relay.ts):
//   Telefone → Host-JS: evaluateJavaScript("window.__mmRelayEmpfang(<json>)")
//   Host-JS → Telefone: window.webkit.messageHandlers.mmRelay.postMessage(json)
import UIKit
import WebKit

/// Bricht den Retain-Zyklus WKUserContentController → Handler → ViewController.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var ziel: WKScriptMessageHandler?

    init(ziel: WKScriptMessageHandler) {
        self.ziel = ziel
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        ziel?.userContentController(userContentController, didReceive: message)
    }
}

final class HostViewController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler,
    UIGestureRecognizerDelegate {
    private var webView: WKWebView!
    private let server = EmbeddedServer()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard server.bundleVorhanden else {
            zeigeFehler(
                titel: "Standalone-Bundle fehlt",
                text: "Diese App wurde ohne Web-Bundle gebaut (WebDist/ fehlt). "
                    + "Die CI-.ipa enthält es — lokale Builds brauchen vorher "
                    + "`npm run build:client` + Kopie nach ios-wrapper/WebDist."
            )
            return
        }

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Jingles/Musik ohne User-Geste — die Bühne läuft im iframe der Host-Seite.
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(WeakScriptMessageHandler(ziel: self), name: "mmRelay")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Not-Ausgang wie im GameViewController: 3-Finger-Longpress → zurück.
        // (KEIN Pull-to-Reload: ein Host-Reload würde den Serverzustand verwerfen.)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(zurueck(_:)))
        longPress.numberOfTouchesRequired = 3
        longPress.minimumPressDuration = 0.8
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        webView.addGestureRecognizer(longPress)

        // Frames Telefon → Host-JS (evaluateJavaScript MUSS auf den Main-Thread).
        server.onFrameZumHost = { [weak self] json in
            DispatchQueue.main.async { self?.leiteFrameZurWebView(json) }
        }

        do {
            try server.start()
        } catch {
            zeigeFehler(
                titel: "Server-Start fehlgeschlagen",
                text: "Port 8080 ließ sich nicht öffnen: \(error.localizedDescription)"
            )
            return
        }

        // Host-Seite über den EIGENEN Server laden — gleiche Origin wie die
        // Bühnen-/Telefon-Routen, damit iframe + relative URLs sauber laufen.
        var teile = URLComponents(string: "http://127.0.0.1:\(EmbeddedServer.port)/host")!
        teile.queryItems = [
            URLQueryItem(name: "standalone", value: "1"),
            URLQueryItem(name: "origin", value: server.lanOrigin),
        ]
        webView.load(URLRequest(url: teile.url!))
    }

    deinit {
        server.stop()
    }

    // MARK: - Brücke

    private func leiteFrameZurWebView(_ json: String) {
        // JSON-String als JS-String-Literal (JSONEncoder erledigt das Escaping).
        guard let daten = try? JSONEncoder().encode(json),
              let literal = String(data: daten, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__mmRelayEmpfang && window.__mmRelayEmpfang(\(literal))")
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "mmRelay", let json = message.body as? String else { return }
        server.verarbeiteHostFrame(json)
    }

    // MARK: - Navigation/Fehler

    @objc private func zurueck(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        server.stop()
        navigationController?.popViewController(animated: true)
    }

    private func zeigeFehler(titel: String, text: String) {
        let alert = UIAlertController(title: titel, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Zurück", style: .cancel) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        zeigeFehler(titel: "Host-Seite lädt nicht", text: error.localizedDescription)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
