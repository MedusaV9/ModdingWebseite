# SoooDreamy Admin-Panel / Admin Panel

Stand / as of: v11.0. Backend: `SoooDreamy/server/src/admin/admin.js`,
Frontend (Vanilla JS/CSS, statisch ausgeliefert): `SoooDreamy/server/src/admin/public/`.
Tests: `SoooDreamy/server/test/admin.test.js`.

---

## Deutsch

### Start

Das Panel läuft im selben Prozess wie der Server — nichts zusätzlich zu
starten, kein zweiter Port. Einfach den Server starten und die URL aus der
Konsole öffnen:

```bash
cd SoooDreamy/server
npm start
```

HTTP ist für das private Standard-Setup aktiv, aber unverschlüsselt.
`ALLOW_HTTP_PRIVATE_LAN=1` schränkt es auf private Quellen ein;
`REQUIRE_HTTPS=1` erzwingt den Betrieb hinter einem TLS-Proxy.

Beim Start erscheint ein gerahmter Banner mit URL und dem frischen Passwort:

```
  ╭──────────────────────────────────────────────────────────────────╮
  │ SoooDreamy Admin-Panel                                           │
  │                                                                  │
  │ URL       http://localhost:4321/admin                            │
  │ LAN       http://192.168.1.20:4321/admin                         │
  │ Passwort  falke-mond-kiesel-tau                                  │
  │                                                                  │
  │ Wird bei jedem Serverstart neu generiert und nur hier angezeigt. │
  │ Regenerated on every server start and shown only here.           │
  ╰──────────────────────────────────────────────────────────────────╯
```

### Passwort-Konzept

- **Bei jedem Boot neu**: 4 zufällige Wörter aus einer 256-Wörter-Liste
  (`src/admin/wordlist.js`), verbunden mit `-` → 2³² Kombinationen,
  kryptografisch zufällig (`crypto.randomInt`), gut tippbar (auch am Handy).
- **Nur in der Konsole**: Das Passwort wird nie gespeichert und von keiner
  API zurückgegeben; der Server behält nur einen SHA-256-Digest im Speicher.
  Passwort vergessen? Server neu starten → neues Passwort im Banner.
- **Brute-Force-Schutz**: Login ist rate-limitiert — 10 Versuche pro IP und
  100 global je 15 Minuten (`429 rate_limited`); Fehlversuche landen im
  Audit-Log.

### Features

1. **Paare-Übersicht** — alle Paare mit Mitgliedern (Name, Avatar,
   online/zuletzt gesehen), App-Versionen (User-Agent der aktiven Sessions),
   Datenumfang (Nachrichten/Fotos/Videos/Events/Spiele/Songs/Coupons +
   Segmentgröße in Bytes) und Segment-Gesundheit: `ok`, `recovered`
   (Quarantäne-Dateien vorhanden, Paar läuft weiter) oder `quarantined`
   (Paar ist nur noch als Quarantäne-Eintrag bekannt).
2. **Codes zurücksetzen** — je Paar den Invite-Code, je Mitglied-Slot
   Recovery-Key und Replace-Code neu generieren. Alte Codes werden dabei
   invalidiert (genau ein gültiger Code je Art). Jede Aktion verlangt eine
   Bestätigung im Dialog und wird auditiert.
3. **Geräte ausloggen** — Sessions je Paar listen (Gerätename, App-Version,
   erstellt/zuletzt benutzt, live/abgelaufen/revoked) und einzeln oder alle
   eines Slots revoken. Revoke wirkt sofort: offene WebSockets werden
   geschlossen, Push-Registrierungen entfernt, der Token ist ab sofort 401.
4. **Login-QR** — pro Mitglied-Slot einen zufälligen, fest an diesen Slot
   gebundenen Einmal-Nonce (30 Min TTL) als QR-Code erzeugen. Der Nonce ist
   nie selbst ein Bearer und wird beim ersten erfolgreichen Rejoin atomar
   verbraucht; Replay oder Ablauf werden abgelehnt. Payload ist der Deep-Link
   `sooodreamy://rejoin?server=<url-encoded>&token=<token>` — exakt der
   Kontrakt aus [`REJOIN-QR.md`](REJOIN-QR.md), den der iOS-Scanner einlöst
   (`POST /api/couples/rejoin`). Die Server-Basis-URL ist standardmäßig die
   des Panels und im Dialog überschreibbar (z. B. LAN-/Tailscale-Adresse).
5. **Backups** — Status (letztes Backup, Intervall, Liste) plus
   „Backup jetzt“ (verifiziertes Backup + Rotation, wie `npm run backup`).
6. **Log-Tail** — die letzten 200 Server-Log-Zeilen und die letzten 200
   Audit-Einträge, read-only.

Oberfläche: Single-Page im SooDreamy-Look (Liquid-Glass, Herz-Akzent),
responsive (Handy), DE/EN-Umschalter und Dunkel/Hell-Modus (beides in
`localStorage` gemerkt).

### Sicherheit

- **Session**: httpOnly-Cookie `sooodreamy_admin`, `SameSite=Lax`,
  `Path=/admin`, `Secure` bei HTTPS. Sessions leben nur im Speicher
  (12 h gleitende TTL, max. 32) und sterben mit dem Prozess.
- **Alle Admin-APIs hinter der Session**: ohne gültiges Cookie
  `401 admin_unauthorized`. Schreibende Browser-Requests mit vorhandenem
  `Origin` prüfen ihn gegen den Request-Host (`403 admin_bad_origin`);
  `SameSite=Lax` ist die primäre Browser-CSRF-Grenze.
- **Audit-Log**: append-only JSONL unter `DATA_DIR/admin-audit.log` —
  jede Aktion mit Zeitstempel, IP und Kontext (`login`, `login_failed`,
  `logout`, `invite_code_reset`, `recovery_key_reset`, `replace_code_reset`,
  `session_revoked`, `sessions_revoked_all`, `rejoin_qr_issued`,
  `backup_created`). Tägliche bzw. 5-MiB-Rotation, standardmäßig 30
  Altdateien (`AUDIT_MAX_BYTES`, `AUDIT_RETENTION_FILES`).
- **CSP**: `index.html` wird mit strikter Content-Security-Policy
  (`default-src 'self'`, `frame-ancestors 'none'`) und `no-store`
  ausgeliefert.
- Geheimnisse (Recovery-Key, Replace-Code, QR-Nonce) erscheinen genau
  einmal in der jeweiligen API-Antwort — nie im Audit-Log, nie im Log-Tail.

---

## English

### Getting started

The panel runs inside the server process — nothing extra to start, no second
port. Start the server and open the URL printed to the console:

```bash
cd SoooDreamy/server
npm start
```

HTTP is enabled for the default private setup but is unencrypted.
`ALLOW_HTTP_PRIVATE_LAN=1` restricts it to private sources;
`REQUIRE_HTTPS=1` requires a TLS reverse proxy.

On boot a framed banner shows the URL and the freshly generated password
(see the German section above for a sample).

### Password concept

- **New on every boot**: 4 random words from a 256-word list
  (`src/admin/wordlist.js`) joined with `-` → 2³² combinations,
  cryptographically random (`crypto.randomInt`), easy to type on a phone.
- **Console only**: the password is never persisted and never returned by
  any API; the server keeps only a SHA-256 digest in memory. Forgot it?
  Restart the server → a new password appears in the banner.
- **Brute-force protection**: login is rate-limited — 10 attempts per IP and
  100 globally per 15 minutes (`429 rate_limited`); failed attempts are
  audited.

### Features

1. **Couples overview** — every couple with members (name, avatar,
   online/last seen), app versions (user agents of live sessions), data
   volume (messages/photos/videos/events/games/songs/coupons + segment size
   in bytes) and segment health: `ok`, `recovered` (quarantine files exist,
   couple keeps running) or `quarantined`.
2. **Reset codes** — regenerate the invite code per couple and the recovery
   key / replace code per member slot. Old codes are invalidated (exactly
   one valid code of each kind). Every reset requires a confirmation dialog
   and is audited.
3. **Log out devices** — list sessions per couple (device name, app version,
   created/last used, live/expired/revoked) and revoke them individually or
   all of a slot at once. Revocation is immediate: open WebSockets are
   closed, push registrations removed, the token returns 401 from then on.
4. **Login QR** — issue a random single-use nonce (30 min TTL), fixed to one
   member slot, as a QR code. It is never itself a bearer and is atomically
   consumed by the first successful rejoin; replay or expiry is rejected.
   The payload is the deep link
   `sooodreamy://rejoin?server=<url-encoded>&token=<token>` — exactly the
   contract in [`REJOIN-QR.md`](REJOIN-QR.md) that the iOS scanner redeems
   via `POST /api/couples/rejoin`. The server base URL defaults to the
   panel's own and can be overridden in the dialog (e.g. LAN/Tailscale).
5. **Backups** — status (latest backup, interval, list) plus a
   "Backup now" button (verified backup + rotation, like `npm run backup`).
6. **Log tail** — the last 200 server log lines and the last 200 audit
   entries, read-only.

UI: single page in the SooDreamy look (liquid glass, heart accent),
responsive (phone-friendly), DE/EN language toggle and dark/light mode
(both remembered in `localStorage`).

### Security

- **Session**: httpOnly cookie `sooodreamy_admin`, `SameSite=Lax`,
  `Path=/admin`, `Secure` over HTTPS. Sessions live in memory only
  (12 h sliding TTL, capped at 32) and die with the process.
- **Every admin API behind the session**: without a valid cookie
  `401 admin_unauthorized`. State-changing browser requests that carry
  `Origin` check it against the request host (`403 admin_bad_origin`);
  `SameSite=Lax` is the primary browser-CSRF boundary.
- **Audit log**: append-only JSONL at `DATA_DIR/admin-audit.log` — every
  action with timestamp, IP and context (`login`, `login_failed`, `logout`,
  `invite_code_reset`, `recovery_key_reset`, `replace_code_reset`,
  `session_revoked`, `sessions_revoked_all`, `rejoin_qr_issued`,
  `backup_created`). It rotates daily or at 5 MiB and retains 30 rotated
  files by default (`AUDIT_MAX_BYTES`, `AUDIT_RETENTION_FILES`).
- **CSP**: `index.html` ships with a strict content security policy
  (`default-src 'self'`, `frame-ancestors 'none'`) and `no-store`.
- Secrets (recovery key, replace code, QR nonce) appear exactly once in the
  respective API response — never in the audit log, never in the log tail.

---

## API-Referenz / API reference

Alle Routen unter `/admin/api/*`, JSON, Session-Cookie erforderlich (außer
Login). / All routes under `/admin/api/*`, JSON, session cookie required
(except login). Details: [`../SoooDreamy/docs/API.md`](../SoooDreamy/docs/API.md).

| Route | Zweck / Purpose |
| ----- | --------------- |
| `POST /admin/api/login` | `{password}` → Session-Cookie. Rate-limitiert / rate-limited. |
| `POST /admin/api/logout` | Session beenden / end session. |
| `GET /admin/api/me` | Session-Check (Name, Version, `startedAt`). |
| `GET /admin/api/state` | Server-Stats + alle Paare + Quarantäne / server stats + all couples + quarantine. |
| `GET /admin/api/couples/:coupleId/sessions` | Sessions eines Paares / sessions of one couple. |
| `POST /admin/api/couples/:coupleId/invite-code/reset` | Neuer Invite-Code (alter ungültig) / new invite code (old invalidated). |
| `POST /admin/api/couples/:coupleId/members/:memberId/recovery-key/reset` | Neuer Recovery-Key / new recovery key. |
| `POST /admin/api/couples/:coupleId/members/:memberId/replace-code/reset` | Neuer Replace-Code / new replace code. |
| `POST /admin/api/sessions/:sessionId/revoke` | Einzelne Session revoken / revoke one session. |
| `POST /admin/api/couples/:coupleId/members/:memberId/sessions/revoke-all` | Alle Sessions eines Slots revoken / revoke all of a slot. |
| `POST /admin/api/couples/:coupleId/members/:memberId/rejoin-qr` | `{server?}` → `{deepLink, svg, expiresAt, …}` (QR als SVG). |
| `GET /admin/api/backups` | Backup-Liste + Intervall / backup list + interval. |
| `POST /admin/api/backups` | „Backup jetzt“ / "backup now". |
| `GET /admin/api/logs` | Letzte 200 Log-Zeilen / last 200 log lines. |
| `GET /admin/api/audit` | Letzte 200 Audit-Einträge / last 200 audit entries. |
