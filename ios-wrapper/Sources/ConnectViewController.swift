// Start-Screen (W4-Hierarchie): GROSSER Hero-Button „Party hosten — iPad ist
// der Server" (startet Embedded-Server + Host-Seite, der Normalfall für den
// Spieleabend), darunter sekundär „Mit Server verbinden" (URL-Eingabe +
// Rollen-Schnellwahl Bildschirm/GM wie bisher — lädt direkt /screen bzw. /gm
// des externen Servers, TECH-SPEC §7.1.5). Swift kompiliert erst im CI
// (macos-Job) — Änderungen hier bleiben bewusst API-konservativ (nur UIKit-
// APIs, die diese Datei schon nutzt: UIButton.Configuration, UIStackView).
import UIKit

final class ConnectViewController: UIViewController, UITextFieldDelegate {
    private enum Keys {
        static let serverURL = "mm.serverURL"
        static let role = "mm.role" // "screen" | "gm"
    }

    // Banana-Vault-Palette (client/shared: --bg #0e1a12, --mm-vault-gold #f5b301).
    private static let vaultBackground = UIColor(red: 14 / 255, green: 26 / 255, blue: 18 / 255, alpha: 1)
    private static let vaultGold = UIColor(red: 245 / 255, green: 179 / 255, blue: 1 / 255, alpha: 1)

    private let urlField = UITextField()
    private let roleControl = UISegmentedControl(items: ["Bildschirm", "Show-Master (GM)"])
    private let connectButton = UIButton(type: .system)
    private let hostButton = UIButton(type: .system)

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Self.vaultBackground
        buildLayout()
        restorePersistedInput()
    }

    // MARK: - Layout

    private func buildLayout() {
        let titleLabel = UILabel()
        titleLabel.text = "🐒 MONKEY MONEY"
        titleLabel.font = .systemFont(ofSize: 44, weight: .black)
        titleLabel.textColor = Self.vaultGold
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Bühne, Regie und Server für den Spieleabend"
        subtitleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        subtitleLabel.textColor = .white
        subtitleLabel.textAlignment = .center

        // HERO (primär): das iPad hostet selbst — Embedded-Server + Host-Seite
        // (docs/IPAD-SETUP.md „Weg 3"). Kein AMP, kein PC, kein Internet.
        var hostConfig = UIButton.Configuration.filled()
        var hostTitel = AttributeContainer()
        hostTitel.font = UIFont.systemFont(ofSize: 26, weight: .black)
        hostConfig.attributedTitle = AttributedString(
            "🎪 Party hosten — iPad ist der Server", attributes: hostTitel
        )
        hostConfig.baseBackgroundColor = Self.vaultGold
        hostConfig.baseForegroundColor = .black
        hostConfig.cornerStyle = .large
        hostConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 22, leading: 32, bottom: 22, trailing: 32
        )
        hostButton.configuration = hostConfig
        hostButton.addTarget(self, action: #selector(hostTapped), for: .touchUpInside)

        let hostHint = UILabel()
        hostHint.text = "Bühne + QR sofort hier · iPhones ins gleiche WLAN/Hotspot · "
            + "Fortschritt wird lokal auf dem iPad gespeichert."
        hostHint.font = .systemFont(ofSize: 14, weight: .regular)
        hostHint.textColor = UIColor.white.withAlphaComponent(0.7)
        hostHint.textAlignment = .center
        hostHint.numberOfLines = 0

        let trennerLabel = UILabel()
        trennerLabel.text = "— oder mit vorhandenem Server verbinden —"
        trennerLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        trennerLabel.textColor = UIColor.white.withAlphaComponent(0.55)
        trennerLabel.textAlignment = .center

        urlField.placeholder = "http://192.168.1.20:8080"
        urlField.font = .monospacedSystemFont(ofSize: 20, weight: .regular)
        urlField.borderStyle = .roundedRect
        urlField.keyboardType = .URL
        urlField.autocapitalizationType = .none
        urlField.autocorrectionType = .no
        urlField.spellCheckingType = .no
        urlField.clearButtonMode = .whileEditing
        urlField.returnKeyType = .go
        urlField.delegate = self
        urlField.heightAnchor.constraint(equalToConstant: 52).isActive = true

        roleControl.selectedSegmentIndex = 0
        roleControl.selectedSegmentTintColor = Self.vaultGold
        roleControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        roleControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        roleControl.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Sekundär (bordered statt filled): Verbinden mit AMP-/PC-Server.
        var config = UIButton.Configuration.bordered()
        var titel = AttributeContainer()
        titel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        config.attributedTitle = AttributedString("Verbinden", attributes: titel)
        config.baseForegroundColor = Self.vaultGold
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        connectButton.configuration = config
        connectButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)

        let hintLabel = UILabel()
        hintLabel.text = "Bildschirm = Bühne mit QR-Code · Show-Master = Regiepult (braucht die GM-PIN)"
        hintLabel.font = .systemFont(ofSize: 14, weight: .regular)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, subtitleLabel, hostButton, hostHint,
            trennerLabel, urlField, roleControl, connectButton, hintLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 20
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(32, after: subtitleLabel)
        stack.setCustomSpacing(8, after: hostButton)
        stack.setCustomSpacing(36, after: hostHint)
        stack.setCustomSpacing(28, after: trennerLabel)
        stack.setCustomSpacing(12, after: connectButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            urlField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            hostButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: - Persistenz

    private func restorePersistedInput() {
        let defaults = UserDefaults.standard
        urlField.text = defaults.string(forKey: Keys.serverURL)
        roleControl.selectedSegmentIndex = defaults.string(forKey: Keys.role) == "gm" ? 1 : 0
    }

    private var selectedRole: String {
        roleControl.selectedSegmentIndex == 1 ? "gm" : "screen"
    }

    // MARK: - Verbinden

    @objc private func hostTapped() {
        navigationController?.pushViewController(HostViewController(), animated: true)
    }

    @objc private func connectTapped() {
        guard let serverURL = normalizedServerURL() else {
            showError("Bitte eine gültige Server-Adresse eingeben, z. B. http://192.168.1.20:8080")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(urlField.text ?? "", forKey: Keys.serverURL)
        defaults.set(selectedRole, forKey: Keys.role)

        // Direkte Rollen-Routen des Servers: /screen (Bühne) bzw. /gm (Regiepult).
        let target = serverURL.appendingPathComponent(selectedRole)
        navigationController?.pushViewController(GameViewController(startURL: target), animated: true)
    }

    /// Normalisiert die Eingabe: Schema ergänzen (HTTP ist im LAN-Pfad der Normalfall),
    /// abschließende Slashes entfernen, Host-Pflicht.
    private func normalizedServerURL() -> URL? {
        var text = (urlField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text = String(text.dropLast()) }
        guard let url = URL(string: text), url.host != nil else { return nil }
        return url
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Keine gültige Adresse", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        connectTapped()
        return true
    }
}
