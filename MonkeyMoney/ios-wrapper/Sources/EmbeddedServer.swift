// Embedded-HTTP+WS-Server für den Standalone-Modus (TECH-SPEC §6 + docs/
// IPAD-SETUP.md „Weg 3"): das iPad IST der Server. Swifter (SPM) serviert das
// gebaute Client-Bundle (WebDist/, kopiert der CI-Build aus client/dist) und
// die Laufzeit-Medien (Media/, aus assets/) im LAN auf Port 8080 und relayt
// WebSocket-Frames 1:1 zwischen den Telefonen (/ws) und der Host-JS-Schicht
// in der WKWebView (WKScriptMessageHandler rein, evaluateJavaScript raus).
//
// WICHTIG: Dieser Server versteht KEINE Spiellogik. Die Autorität ist die
// Host-Seite (client/host/ → server/host-browser/). Die beiden Frame-Verträge
// (Wire + Relay) sind in server/host-browser/relay.ts definiert; der Node-
// Stellvertreter tools/ipad-host/relay-sim.mjs spiegelt exakt dieses Verhalten
// — Änderungen IMMER an allen drei Stellen nachziehen.
import CoreImage
import Foundation
import Swifter

/// Relay-Frame (Vertrag 2 aus relay.ts): {kind:"open"|"frame"|"close", clientId, data?}
private struct RelayFrame: Codable {
    let kind: String
    let clientId: String
    var data: String?
}

final class EmbeddedServer {
    static let port: in_port_t = 8080

    private let server = HttpServer()
    /// Schützt sessions/sessionIds — Swifter ruft Callbacks auf Socket-Threads.
    private let zustand = DispatchQueue(label: "mm.embedded-server.zustand")
    private var sessions: [String: WebSocketSession] = [:]
    private var sessionIds: [WebSocketSession: String] = [:]
    private var clientNr = 0

    /// Frames Richtung Host-JS — der HostViewController hängt evaluateJavaScript dran.
    var onFrameZumHost: ((String) -> Void)?

    private let webDist: URL?
    private let media: URL?
    let lanOrigin: String

    init() {
        webDist = Bundle.main.url(forResource: "WebDist", withExtension: nil)
        media = Bundle.main.url(forResource: "Media", withExtension: nil)
        let ip = EmbeddedServer.wlanIPv4() ?? "127.0.0.1"
        lanOrigin = "http://\(ip):\(EmbeddedServer.port)"
        konfiguriereRouten()
    }

    /// CI-Builds bündeln WebDist/ — lokale Xcode-Builds ohne `npm run build:client` nicht.
    var bundleVorhanden: Bool { webDist != nil }

    func start() throws {
        try server.start(EmbeddedServer.port, forceIPv4: true, priority: .userInteractive)
    }

    func stop() {
        server.stop()
        zustand.sync {
            sessions.removeAll()
            sessionIds.removeAll()
        }
    }

    // MARK: - Host-JS → Telefone (WKScriptMessageHandler-Eingang)

    /// JSON-Frame der Host-Seite verarbeiten: an das richtige Telefon schreiben.
    func verarbeiteHostFrame(_ json: String) {
        guard let daten = json.data(using: .utf8),
              let frame = try? JSONDecoder().decode(RelayFrame.self, from: daten) else { return }
        let session = zustand.sync { sessions[frame.clientId] }
        guard let session else { return }
        if frame.kind == "frame", let data = frame.data {
            session.writeText(data)
        } else if frame.kind == "close" {
            session.writeCloseFrame()
            session.socket.close()
        }
    }

    // MARK: - Telefone → Host-JS

    private func sendeZumHost(_ frame: RelayFrame) {
        guard let daten = try? JSONEncoder().encode(frame),
              let json = String(data: daten, encoding: .utf8) else { return }
        onFrameZumHost?(json)
    }

    // MARK: - Routen

    private func konfiguriereRouten() {
        // Telefon-WebSocket: dummes 1:1-Relay (open/frame/close an die Host-JS).
        server["/ws"] = websocket(
            text: { [weak self] session, text in
                guard let self else { return }
                let clientId = self.zustand.sync { self.sessionIds[session] }
                guard let clientId else { return }
                self.sendeZumHost(RelayFrame(kind: "frame", clientId: clientId, data: text))
            },
            connected: { [weak self] session in
                guard let self else { return }
                let clientId: String = self.zustand.sync {
                    self.clientNr += 1
                    let id = "c_\(self.clientNr)"
                    self.sessions[id] = session
                    self.sessionIds[session] = id
                    return id
                }
                self.sendeZumHost(RelayFrame(kind: "open", clientId: clientId, data: nil))
            },
            disconnected: { [weak self] session in
                guard let self else { return }
                let clientId: String? = self.zustand.sync {
                    guard let id = self.sessionIds[session] else { return nil }
                    self.sessions.removeValue(forKey: id)
                    self.sessionIds.removeValue(forKey: session)
                    return id
                }
                if let clientId {
                    self.sendeZumHost(RelayFrame(kind: "close", clientId: clientId, data: nil))
                }
            }
        )

        // Alles außer /ws läuft über die Middleware (Swifter: Middleware VOR Router
        // — für /ws gibt sie nil zurück, damit der WebSocket-Handshake greift).
        server.middleware.append { [weak self] request in
            guard let self else { return .internalServerError }
            return self.bediene(request)
        }
    }

    /// HTTP-Routen — Spiegel von tools/ipad-host/relay-sim.mjs.
    private func bediene(_ request: HttpRequest) -> HttpResponse? {
        let teile = request.path.components(separatedBy: "?")
        let pfad = teile[0]
        if pfad == "/ws" { return nil } // → WebSocket-Route

        if pfad == "/healthz" {
            let clients = zustand.sync { sessions.count }
            return .ok(.json(["ok": true, "modus": "standalone-ipad", "clients": clients]))
        }

        if pfad == "/api/qr" {
            let code = request.queryParams.first(where: { $0.0 == "code" })?.1 ?? ""
            guard let png = qrPng(fuer: "\(lanOrigin)/j/\(code)") else { return .internalServerError }
            return .ok(.data(png, contentType: "image/png"))
        }

        // Rollen-Routen: OHNE ?standalone=1 → Redirect MIT (Clients erkennen
        // daran den Standalone-Modus und nutzen den Relay-WebSocket).
        let rollenDatei: [String: String] = [
            "/screen": "screen.html", "/gm": "gm.html", "/player": "player.html", "/host": "host.html",
        ]
        let istJoin = pfad.range(of: #"^/(j|join)/[A-Za-z]{4}$"#, options: .regularExpression) != nil
        // WICHTIG: Variablenname darf die Methode datei(aus:relPfad:range:) nicht
        // shadowen — sonst "cannot call value of non-function type 'String'".
        if let zielDatei = rollenDatei[pfad] ?? (istJoin ? "player.html" : nil) {
            let hatStandalone = request.queryParams.contains(where: { $0.0 == "standalone" && $0.1 == "1" })
            if !hatStandalone {
                var query = request.queryParams.map { "\($0.0)=\($0.1)" }
                query.append("standalone=1")
                return .movedTemporarily("\(pfad)?\(query.joined(separator: "&"))")
            }
            return datei(aus: webDist, relPfad: zielDatei, range: request.headers["range"])
        }

        if pfad.hasPrefix("/media/") {
            let rel = String(pfad.dropFirst("/media/".count)).removingPercentEncoding ?? ""
            return datei(aus: media, relPfad: rel, range: request.headers["range"])
        }

        let rel = pfad == "/" ? "index.html" : String(pfad.dropFirst()).removingPercentEncoding ?? ""
        return datei(aus: webDist, relPfad: rel, range: request.headers["range"])
    }

    // MARK: - Statische Dateien (mit Range-Support — iOS-Video verlangt 206)

    private func datei(aus basis: URL?, relPfad: String, range: String?) -> HttpResponse {
        guard let basis, !relPfad.contains("..") else { return .notFound }
        let url = basis.appendingPathComponent(relPfad)
        guard let daten = try? Data(contentsOf: url) else { return .notFound }
        let mime = EmbeddedServer.mimeTypen[url.pathExtension.lowercased()] ?? "application/octet-stream"

        // Range-Requests (WKWebView/Safari streamen <video>/<audio> NUR mit 206).
        if let range, range.hasPrefix("bytes=") {
            let spanne = range.dropFirst("bytes=".count).components(separatedBy: "-")
            let von = Int(spanne.first ?? "") ?? 0
            let bisWunsch = Int(spanne.count > 1 ? spanne[1] : "") ?? (daten.count - 1)
            let bis = min(bisWunsch, daten.count - 1)
            guard von <= bis else { return .notFound }
            let teil = daten.subdata(in: von..<(bis + 1))
            return .raw(206, "Partial Content", [
                "Content-Type": mime,
                "Content-Range": "bytes \(von)-\(bis)/\(daten.count)",
                "Accept-Ranges": "bytes",
            ]) { schreiber in
                try schreiber.write(teil)
            }
        }
        return .raw(200, "OK", ["Content-Type": mime, "Accept-Ranges": "bytes"]) { schreiber in
            try schreiber.write(daten)
        }
    }

    private static let mimeTypen: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript", "css": "text/css",
        "json": "application/json", "svg": "image/svg+xml", "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "webp": "image/webp", "gif": "image/gif",
        "mp3": "audio/mpeg", "ogg": "audio/ogg", "wav": "audio/wav",
        "mp4": "video/mp4", "webm": "video/webm",
        "ttf": "font/ttf", "woff": "font/woff", "woff2": "font/woff2", "ico": "image/x-icon",
    ]

    // MARK: - QR (CoreImage — kein externer Dienst, LAN ohne Internet)

    private func qrPng(fuer text: String) -> Data? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let bild = filter.outputImage else { return nil }
        let skaliert = bild.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let kontext = CIContext()
        guard let farbraum = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return kontext.pngRepresentation(of: skaliert, format: .RGBA8, colorSpace: farbraum)
    }

    // MARK: - LAN-IP (en0 = WLAN; Fallback: erste Nicht-Loopback-IPv4)

    static func wlanIPv4() -> String? {
        var adressen: [String: String] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let erste = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var zeiger: UnsafeMutablePointer<ifaddrs>? = erste
        while let aktuell = zeiger {
            let interface = aktuell.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                    &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: host)
                    if ip != "127.0.0.1" { adressen[name] = ip }
                }
            }
            zeiger = interface.ifa_next
        }
        // en0 = WLAN (auch der eigene Hotspot meldet sich hier bzw. als bridge100).
        return adressen["en0"] ?? adressen["bridge100"] ?? adressen.values.first
    }
}
