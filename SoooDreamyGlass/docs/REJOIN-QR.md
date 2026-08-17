# Rejoin-QR / Deep-Link-Kontrakt (`sooodreamy://rejoin`)

Stand: v10.1 „Große Polish-Runde". iOS-Parser: `SoooDreamy/ios/SoooDreamy/Content/RejoinLink.swift`
(Linux-getestet in `LogicTests/RejoinLinkTests.swift`). **Für das Admin-Webpanel
(Server-Seite): Bitte QR-Codes exakt in diesem Format erzeugen.**

## Format

Der QR-Payload IST der Deep-Link (eine Zeile, URL-encoded). Dadurch
funktioniert derselbe Code dreifach: iOS-Kamera-App → öffnet SoooDreamy,
In-App-Scanner, und als klickbarer Link.

```
sooodreamy://rejoin?server=<URL>&code=<Paar-Code>&replaceCode=<Code>     ← Partner-hilft-QR
sooodreamy://rejoin?server=<URL>&code=<Paar-Code>&recoveryKey=<rec_…>    ← Schlüssel-Variante
sooodreamy://rejoin?server=<URL>&token=<alter Bearer>                     ← Admin-Panel-QR
```

Alle Varianten mappen 1:1 auf die bestehende Route `POST /api/couples/rejoin`
(Proof-Reihenfolge des Servers: `recoveryKey` → `token` → `replaceCode`).

## Parameter

| Parameter | Aliasse (akzeptiert) | Inhalt |
| --------- | -------------------- | ------ |
| `server`  | `url`, `serverUrl`   | Basis-URL des Paar-Servers, `http://` ist erste Klasse (z. B. `http://138.201.60.230:4321`). **Bitte percent-encoden.** Ohne Schema ergänzt der Client `http://`. |
| `code`    | `coupleCode`, `couple` | 6-stelliger Paar-Code. Client und Server vergleichen uppercase. |
| `recoveryKey` | `recovery`, `key` | Recovery-Key (`rec_…` oder Custom-Secret), verbatim. |
| `replaceCode` | `replace`        | Ersatz-Code (Standard 8 Zeichen oder Custom ≤ 32). Wird nur uppercased, innere Zeichen bleiben unangetastet (Server digest = `trim().toUpperCase()`). |
| `token`   | —                    | Früherer Session-Bearer (nie widerrufen). **Der Admin-Panel-QR trägt `server` + `token`.** |

Parameternamen sind case-insensitiv. Unbekannte Parameter werden ignoriert
(vorwärtskompatibel). Ein Link ganz ohne bekannte Parameter ist ungültig.

## Client-Verhalten beim Scan / Öffnen

1. `server` (falls vorhanden) wird normalisiert, als Server-Profil angelegt
   bzw. aktiviert.
2. Ist ein vollständiger Proof enthalten (`code`+`recoveryKey` | `token` |
   `code`+`replaceCode`), ruft die App sofort `POST /api/couples/rejoin` auf
   — ein Scan, wieder drin.
3. Fehlt der Proof, werden die Felder im „Wieder verbinden"-Screen
   vorausgefüllt.

## Wo QR-Codes entstehen

- **Admin-Webpanel** (Server-Agent): `server` + `token` für einen Member-Slot.
- **Partner-Gerät**: Einstellungen → „Sicherheitsnetz" → Ersatz-Code erzeugen
  zeigt zusätzlich den QR (`server` + `code` + `replaceCode`,
  via Replace-Code-Route `POST /api/couples/replace-partner`).
