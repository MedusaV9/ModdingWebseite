# GOOBY-SERVER

Privater Multiplayer-/Meta-Server für **GOOBY 5.0** (Godot-Client, siehe
[`GOOBY-GODOT/README.md`](../GOOBY-GODOT/README.md)): Freunde + Presence,
GoobyPal-Münztransfers, Online-Codes, Admin-Events, Spielzeit-Analytics, Haus-Besuche,
Schiffe versenken — plus Admin-**Webpanel**. Für einen Freundeskreis gebaut, nicht fürs
offene Internet.

**Ein Prozess, ein Port:** `node server.js` startet express (REST + Panel) und `ws`
(WebSocket-Protokoll unter `/ws`) auf demselben HTTP-Listener.
**Keine Datenbank, keine nativen Module:** Storage sind reine JSON-Dateien unter `data/`
— `npm install` kann auf keinem Host an Build-Tools scheitern (wichtig für AMP).

## Schnellstart (lokal)

Voraussetzung: Node ≥ 18 (keine nativen Module, kein Build-Schritt).

```bash
npm install --omit=dev          # installiert nur express + ws
GOOBY_ADMIN_PASSWORD=geheim node server.js
# → http://localhost:8080/health   {"ok":true,...}
# → http://localhost:8080/panel/   Webpanel (Login mit dem Passwort oben)
# → ws://localhost:8080/ws         Spiel-Protokoll (HELLO/WELCOME, siehe Protokoll-Doku)
```

Tests (kein Netzwerk nötig, echte Server auf Port 0):

```bash
node --test
```

## ENV-Referenz

| Variable | Default | Bedeutung |
|---|---|---|
| `PORT` | `8080` | Der EINE Port für HTTP + WebSocket |
| `GOOBY_ADMIN_PASSWORD` | *(leer)* | **Pflicht fürs Panel.** Fehlt sie, ist `/panel` komplett deaktiviert (503, fail-closed) — Spiel-Features laufen trotzdem |
| `DATA_DIR` | `./data` | Persistenz-Verzeichnis (JSON-Collections, JSONL-Logs, Blobs). Alias: `GOOBY_DATA_DIR` |
| `GOOBY_TZ` | `Europe/Berlin` | Zeitzone für Tagesgrenzen (GoobyPal-Limit, Analytics-Tage) |
| `GOOBY_PAL_DAILY_LIMIT` | `250` | GoobyPal: maximale Münzen pro Tag pro **Absender** |
| `GOOBY_MAX_PHOTO_KB` | `512` | Größenlimit für Foto-Blobs (Post/Mail, M2) |
| `GOOBY_HEARTBEAT_SEC` | `20` | PING-Intervall, das der Server den Clients ansagt |
| `GOOBY_BOARD_REJOIN_MS` | `120000` | Brettspiel: Rejoin-Fenster nach Verbindungsabriss |

## Deployment auf AMP (CubeCoders) — „Node.js App Runner“

Der Server ist exakt auf dieses Modell zugeschnitten: 1 Prozess, 1 TCP-Port, keine
nativen Dependencies, `/health` fürs Monitoring.

1. **Instanz anlegen:** AMP → *Create Instance* → Anwendung **„Node.js App Runner“**
   (Generic-Modul). Node ≥ 18 genügt (jede aktuelle AMP-Node-Version passt).
2. **Dateien hochladen:** den kompletten `GOOBY-SERVER/`-Ordner (ohne `node_modules/`,
   ohne `data/`-Inhalte) per AMP-File-Manager oder SFTP in das Instanz-Verzeichnis.
3. **Dependencies installieren:** in der AMP-Konsole
   ```bash
   npm install --omit=dev
   ```
   Das installiert NUR `express` und `ws` (pure JS — kein Compiler, kein node-gyp).
4. **App-Einstellungen:**
   - *Startkommando / Application entrypoint:* `node server.js` (oder `npm start`)
   - *Port:* AMP weist der App einen Port zu → als ENV `PORT` durchreichen
     (App Runner setzt `PORT` üblicherweise selbst; sonst manuell setzen).
5. **ENV setzen** (AMP → Configuration → Environment):
   ```
   GOOBY_ADMIN_PASSWORD=<starkes Passwort — ohne bleibt das Panel aus>
   GOOBY_TZ=Europe/Berlin
   DATA_DIR=./data
   ```
6. **Port-Mapping/Firewall:** den einen TCP-Port freigeben. HTTP, WebSocket und Panel
   laufen ALLE über diesen Port (`/ws`, `/api/*`, `/panel/*`, `/health`).
7. **Persistenz:** `data/` liegt im Instanz-Verzeichnis und überlebt Neustarts. AMPs
   Stop/Restart sendet SIGTERM → der Server flusht Snapshots und verabschiedet die
   Clients sauber (`GOING_DOWN`).
8. **Monitoring:** `GET /health` → `{"ok":true,"uptime":…,"clients":…}` als
   AMP-Health-Check-URL eintragen.

### Backup

**Einfach den Ordner `data/` sichern** (im laufenden Betrieb ok — Snapshots werden
atomar via tmp→rename geschrieben):

- `data/*.json` — Spieler, Freunde, Codes, Events, Häuser, Analytics-Aggregate
- `data/sessions/*.jsonl` — Spielzeit-Rohdaten (monatlich rotiert)
- `data/ledger/*.jsonl` — GoobyPal-Transfer-Ledger (append-only, Audit)
- `data/blobs/`, `data/mail/` — Haus-Snapshots, später Fotos

Restore = Ordner zurückkopieren, Server neu starten. Zum Aufräumen alter Logs einfach
alte `sessions-YYYY-MM.jsonl` archivieren/löschen — der Server hält sie nicht offen.

### TLS / öffentliches Internet

Der Server spricht selbst nur `http://`/`ws://`. Wenn er übers Internet erreichbar sein
soll: hinter einen TLS-Reverse-Proxy (Caddy/nginx/Traefik) legen → Clients verbinden per
`wss://`. Im reinen Heimnetz ist `ws://` ok. Das erste HELLO überträgt das deviceSecret
(TOFU) — im offenen Netz daher unbedingt TLS.

## Sicherheit (Kurzfassung)

- **Kein PII:** nur Spitznamen + zufällige Geräte-IDs. `deviceSecret` wird NUR als
  SHA-256-Hash gespeichert (TOFU: Trust On First Use beim ersten HELLO).
- **Panel fail-closed:** ohne `GOOBY_ADMIN_PASSWORD` → 503. Login-Rate-Limit 5/15 min
  pro IP, Session-Cookie httpOnly/SameSite=Lax (12 h), Sessions in-memory.
- **Rate-Limits (Token-Bucket):** 30 WS-msg/s pro Verbindung, HELLO 5/min/IP,
  Freundschaftsanfragen 10/h, GoobyPal 20/h, Code-Redeem 5/15 min, POS-Relay 5 Hz.
- **Payload-Limits:** WS-Frames ≤ 16 KB, Room-Bodies ≤ 8 KB, Haus-Snapshot ≤ 256 KB,
  Analytics-Batch ≤ 200 Sessions, Fotos ≤ 512 KB. Kein CORS. Blob-IDs sind
  server-generiert (kein Pfad-Traversal). Alle Panel-Ausgaben sind HTML-escaped.

## Protokoll & Architektur

- Envelope `{v,t,seq,ts,d}` (v=1), Antworten korrelieren über `re`. Vollständige
  Message-Schemas + REST-Endpoints: Handoff-Doku `W2c-protocol.md`
  (im Repo-Workflow unter `/tmp/gooby-godot/handoffs/`; Godot-Client W2d konsumiert sie).
- Module: `src/config.js` (ENV), `src/storage.js` (atomare JSON-Files), `src/protocol.js`
  (Envelope), `src/ratelimit.js` (Buckets), `src/auth.js` (TOFU/FriendCode),
  `src/ws.js` (Hub: HELLO/WELCOME/PING), `src/rooms.js` (visit:/board:/drive:/mg:-Relay),
  Features: `friends/presence/goobypal/analytics/codes/events/visits/boardgames.js`,
  Panel: `webpanel/`. Neue Module werden in `src/modules.js` mit EINER Zeile registriert.
