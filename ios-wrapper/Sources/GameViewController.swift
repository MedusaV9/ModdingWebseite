// Vollbild-WKWebView für die Bildschirm-/GM-Rolle (TECH-SPEC §6.1):
// Autoplay ohne Touch (Jingles!), Pull-to-Reload, 3-Finger-Longpress → Connect-Screen.
import UIKit
import WebKit

final class GameViewController: UIViewController, WKNavigationDelegate, UIGestureRecognizerDelegate {
    private let startURL: URL
    private var webView: WKWebView!
    private let refreshControl = UIRefreshControl()

    init(startURL: URL) {
        self.startURL = startURL
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) wird nicht unterstützt")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Jingles/Musik dürfen OHNE User-Geste starten — der Audio-Unlock der
        // Web-Clients bleibt trotzdem drin (Safari-Pfad), stört hier aber nicht.
        config.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // Bewusst an die View-Kanten, nicht an die Safe Area: die Bühne ist Vollbild.
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Pull-to-Reload: der Reconnect der Web-Clients heilt fast alles —
        // für den Rest reicht Runterziehen statt App-Neustart.
        refreshControl.tintColor = .white
        refreshControl.addTarget(self, action: #selector(reloadPage), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        // Not-Ausgang: 3-Finger-Longpress → zurück zum Connect-Screen
        // (bewusst sperrig, damit niemand aus Versehen die Show verlässt).
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(backToConnect(_:)))
        longPress.numberOfTouchesRequired = 3
        longPress.minimumPressDuration = 0.8
        longPress.cancelsTouchesInView = false
        longPress.delegate = self
        webView.addGestureRecognizer(longPress)

        webView.load(URLRequest(url: startURL))
    }

    @objc private func reloadPage() {
        if webView.url != nil {
            webView.reload()
        } else {
            webView.load(URLRequest(url: startURL))
        }
    }

    @objc private func backToConnect(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        navigationController?.popViewController(animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshControl.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        refreshControl.endRefreshing()
        showLoadError(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        refreshControl.endRefreshing()
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        let alert = UIAlertController(
            title: "Verbindung fehlgeschlagen",
            message: "\(startURL.absoluteString)\n\n\(error.localizedDescription)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Nochmal versuchen", style: .default) { [weak self] _ in
            guard let self else { return }
            self.webView.load(URLRequest(url: self.startURL))
        })
        alert.addAction(UIAlertAction(title: "Zurück zum Start", style: .cancel) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Der Longpress darf neben den WebView-internen Gesten leben.
        true
    }
}
