# Between — Arbeits-Log & User-Feedback

**Between** ist das Game-Server-Management-Panel (à la Pterodactyl / AMP), das in diesem Repo unter `Between/` entsteht. Läuft auf **Linux und Windows**, verwaltet Game-Server-Prozesse direkt (kein Docker nötig), unterstützt **SteamCMD** und Custom-Lösungen, mit Themes, Benutzerverwaltung, Backups, Zeitplänen und vielem mehr.

---

## So funktioniert dieser Feedback-Loop

1. Ich (der Agent) logge hier **jede Runde**, was ich gebaut/gefixt/poliert habe.
2. **Du schreibst dein Feedback in den Abschnitt „Dein Feedback"** (direkt auf dem Branch `cursor/between-panel-ab64` committen — z. B. über die GitHub-Weboberfläche) **oder einfach in den Chat**.
3. Ich schaue regelmäßig per `git fetch` nach, ob hier neues Feedback steht. Wenn ja: umsetzen. Wenn nein: weiter polieren, verbessern, debuggen.
4. **STOPP** (hier oder im Chat) beendet den Loop.

> Hinweis: Innerhalb einer Chat-Runde arbeite ich so lange wie möglich und checke dieses File mehrfach. Wenn meine Runde endet, mache ich mit deiner nächsten Chat-Nachricht (oder neuem Feedback hier) direkt weiter.

---

## Dein Feedback (hier reinschreiben!)

_(noch leer — schreib hier alles rein: Wünsche, Bugs, Prioritäten, Design-Feedback, „STOPP" …)_

---

## Status

- **Aktuelle Runde:** 13
- **Zustand:** Stabilitäts-Härtung nach 5+-Minuten-Soak: WebSocket-/Shell-Sessions enden jetzt bei Logout/Session-Entzug und sind gegen langsame Clients sowie übergroße Frames gedeckelt; sämtliche gefundenen Runtime-Timer, Log-Streams, Scheduler-Waits, Docker-Antwortpuffer und Child-stdio-Lebenszyklen werden begrenzt bzw. beim Shutdown abgeräumt. Auth-Rate-Limit-State ist hart gedeckelt. **307 Tests grün** (287 bestanden + 20 Docker-Skips ohne Daemon), Typecheck, Build, Lint (0 Warnungen), Audit (0 Vulnerabilities) und 73/73 Blueprints sauber. Prozess-Runtime per curl + Live-WebSocket über 310 s verifiziert; keine Unhandled Rejections/Exceptions, Game-Child nach Delete sicher geerntet.
- **Branch / PR:** `cursor/between-panel-docker-evolution-afac` (PR #2), Basis `cursor/between-panel-ab64` (PR #1)

---

## Arbeits-Log

### Runde 1 — 2026-07-30

- [x] Produkt-Recherche abgeschlossen (Subagent, Fable 5 Max Thinking): Feature-Sets von Pterodactyl, AMP, PufferPanel, Crafty, WindowsGSM, LinuxGSM analysiert; ~40 Spiele-Tabelle mit SteamCMD-AppIDs, Start-Commands, Ports, Stop-Methoden; Top-Schmerzpunkte der Community gesammelt → fließt in `Between/docs/IDEAS.md`
- [x] Scaffold: npm-Workspaces (`Between/server` + `Between/web`), TypeScript, Vite, Tailwind v4, oxlint
- [x] Backend-Kern: JSON-Store (atomare Writes), Auth (scrypt, Sessions, TOTP-2FA, API-Keys mit Scopes), Rollen (Admin/User) & Subuser-Rechte pro Server, Audit-Log
- [x] Server-Manager: Prozess-Lifecycle (start/stop/restart/kill), Live-Konsole (Ringpuffer + stdin), Crash-Detection + Auto-Restart mit Backoff & Circuit-Breaker, Ressourcen-Monitoring (CPU/RAM pro Prozessbaum, Linux `/proc` + Windows PowerShell), Port-Konflikt-Prüfung (bei Erstellung UND Start)
- [x] Installer: SteamCMD-Manager (Download + App-Install/Update), Direkt-Downloads mit Fortschritt & SHA256, Version-Resolver (Paper/Vanilla/Fabric/Velocity), Zip/Tar.gz-Extraktion (handgerollt, traversal-sicher), Custom-Blueprints
- [x] Features: Datei-Manager (sandboxed, Editor, Upload/Download, Zip/Entpacken), Backups (Zip, Lock, Retention, Restore), Zeitpläne (eigener Cron-Parser, Vixie-Semantik), Game-Queries (Minecraft-Ping, Source A2S), Host-Metriken, Discord-Webhooks
- [x] Frontend: 8 Themes + 6 Akzentfarben, Dashboard (Live-Metriken), Server-Detail mit 8 Tabs (Konsole/Dateien/Config/Backups/Zeitpläne/Benutzer/Aktivität/Einstellungen), Create-Wizard (3 Schritte), Blueprint-Galerie + Editor, Admin (Benutzer, Audit, Panel-Settings), Account (Passwort, 2FA, Sessions, API-Keys), i18n (EN/DE), Live-Updates über WebSocket
- [x] Blueprint-Paket: **43 Spiele** validiert (Minecraft-Familie, Valheim, Palworld, Rust, ARK, CS2, TF2, Satisfactory, Terraria, Factorio, … + `demo-echo` zum Testen ohne Downloads)
- [x] Tests: **86/86 grün** (64 Unit + 22 API-Integration, komplette User-Journey inkl. Crash-Detection & Rechte-Checks), Lint sauber, Typecheck sauber, Prod-Build ok
- [x] Bugfixes dieser Runde: `requireAdmin`-Middleware hatte alle `/api/*`-Routen für Nicht-Admins blockiert (Express-Mounting-Reihenfolge); Port-Konflikt jetzt schon bei Server-Erstellung; `/resources`-API liefert letzten Snapshot + Historie; Fehler-Mapping (Path-Traversal, gesperrte Backups → 400 statt 500)
- [ ] E2E-Demo im Browser (computerUse) + Video
- [ ] Echtes Spiel: Minecraft-Paper-Server E2E
- [ ] README/Doku, weitere Polish-Runden

### Runde 2 — 2026-07-31

**E2E-Tests im echten Browser (alle bestanden, 4 Videos):**

- [x] **Video 1 — Kompletter Lebenszyklus**: Setup (erster Admin) → Dashboard (Live-Metriken) → Server-Wizard (demo-echo) → Installation → Start → Konsolen-Befehl → Live-Ressourcen → sauberer Stop
- [x] **Video 2 — Management-Tour**: Datei-Editor + Ordner anlegen, Backup mit Notiz, Zeitplan anlegen (Cron-Preset + Vorschau) + „Jetzt ausführen", Aktivitäts-Log, Theme-Wechsel (Daylight + Akzentfarben), Sprachwechsel EN↔DE
- [x] **Video 3 — ECHTES Minecraft**: Paper **26.2 build 87** über den Wizard erstellt (inkl. EULA-Toggle + erweiterte `JAVA_BIN`-Variable), 59-MB-Download mit sha256-Verifikation, Weltgenerierung, „Done (11.3s)!", `say`-Befehl, Live-Query (Version + Spielerzahl) + Sparklines, graceful Stop
- [x] **Video 4 — ECHTES Valheim via SteamCMD**: 1,7 GB in 47s über das Panel installiert („Success! App '896660' fully installed."), Start mit `LD_LIBRARY_PATH` aus Blueprint-Variable, **A2S-Query live** (0/10 Spieler, 41 ms), Stop per SIGINT mit Welt-Speicherung

**Gefundene & gefixte Bugs dieser Runde:**

- [x] **Modal-Positionierungs-Falle**: `fade-in-up` (fill-mode `both`) ließ einen dauerhaften `transform` auf Seiten-Wrappern zurück → `position:fixed`-Modals wurden am Wrapper statt am Viewport verankert (Header abgeschnitten, Backdrop nur über dem Content). Fix: Modal rendert per React-Portal nach `<body>` + Animation auf `backwards` umgestellt
- [x] **Zeitplan-Speichern wirkte tot**: Save-Button war still deaktiviert (leerer Name; Platzhalter sah aus wie ein Wert). Fix: Validierung beim Klick mit klaren Fehlermeldungen, eindeutige „z. B."-Platzhalter, deutlicherer Disabled-Look
- [x] **PaperMC-API tot (HTTP 410)**: Valve… äh, PaperMC hat die v2-API abgeschaltet → Resolver auf die neue **Fill-v3-API** migriert, lädt jetzt mit **sha256-Verifikation**
- [x] **Java-Versions-Konflikt**: MC 26.1+ braucht Java 25, ältere Server Java 21 → neue erweiterte Variable **`JAVA_BIN`** in allen Java-Blueprints (Paper/Purpur/Vanilla/Fabric/Velocity): jeder Server kann sein eigenes JDK nutzen (klassischer Pterodactyl-Schmerzpunkt gelöst)
- [x] SteamCMD-Doku: Linux braucht `lib32gcc-s1 lib32stdc++6` (in README + AGENTS.md festgehalten)

**Doku:**

- [x] `Between/README.md`: Features, Quickstart, Konfiguration, Entwicklung, Plattform-Hinweise, Sicherheitsmodell
- [x] `docs/GAMES.md`: Tabelle aller 43 Blueprints mit AppIDs, Ports, Stop-Methoden, Eigenheiten

### Runde 3 — 2026-07-31 (Hardening: 2 Deep-Reviews, 21 Findings gefixt)

Zwei unabhängige Review-Subagents (Fable 5 Max Thinking) haben Backend und Frontend auseinandergenommen. Alle Findings wurden gefixt und mit Tests abgesichert — **101/101 Tests grün** (vorher 86).

**Backend-Härtung (10 Findings):**

- [x] **KRITISCH — Malformed-Cookie-Crash (DoS)**: Ein einziges kaputtes Cookie (`%zz`) im WebSocket-Upgrade brachte den ganzen Panel-Prozess zum Absturz (uncaught `URIError`). Fix: sicheres Cookie-Parsing + Guard um den Upgrade-Pfad + globale `uncaughtException`/`unhandledRejection`-Handler (mit Daten-Flush vor Exit). Per curl verifiziert: Panel antwortet jetzt sauber 401 und lebt weiter
- [x] **Stop-Signal ignoriert**: Blueprints konfigurieren SIGINT (z. B. Valheim braucht das zum Welt-Speichern), aber `killTree` schickte immer SIGTERM. Fix: Signal wird jetzt durchgereicht (Linux: Prozessgruppe/Baum, Windows: `taskkill /t` bzw. `/f`). **Live verifiziert**: Testserver mit Signal-Trap loggt „SIGINT received — graceful shutdown"
- [x] **Löschen während Installation**: Server-Löschung mitten im Install ließ SteamCMD/Downloads weiterlaufen und das Verzeichnis wiederauferstehen. Fix: Installs sind jetzt abbrechbar (AbortSignal durch die ganze Pipeline: Downloads, Commands, SteamCMD), `remove()` bricht ab und wartet aufs Unwinding
- [x] **JSON-Flush-Crash**: Ein Schreibfehler (Disk voll, Rechte) im debounced Flush-Timer crashte den Prozess — jetzt geloggt + Retry bei nächster Mutation
- [x] **OOM durch newline-freie Child-Ausgabe**: Zeilenpuffer wachsen nicht mehr unbegrenzt (64-KiB-Cap in Konsole, Install-Pipeline und SteamCMD)
- [x] **fd-Leak im Tar-Extraktor** bei korrupten Archiven + zurückgelassene `.part`-Dateien bei abgebrochenen Downloads — beides räumt jetzt auf
- [x] **Scheduler-Shutdown-Race**: Zeitpläne konnten nach Panel-Shutdown noch Server starten
- [x] **INI-Config-Sync**: Neue Keys landeten hinter doppelten Sektions-Headern (`[ServerSettings]` zweimal) — Einfügung jetzt in die bestehende Sektion (mit Unit-Tests)
- [x] **Query-Param-Validierung**: `?limit=abc` ergab stillschweigend `NaN`-Verhalten → zentraler `intQuery`-Helper mit Clamping (mit Unit-Tests)
- [x] **WS-Broadcast-Bug beim Löschen** (beim E2E-Testen dieser Runde selbst gefunden!): Das `deleted`-Event wurde gegen den bereits gelöschten Store-Eintrag berechtigungsgeprüft → Event erreichte niemanden. Fix: Visibility-Check läuft jetzt gegen das übergebene Server-Objekt; Integration-Test deckt das ab

**Frontend-Polish (11 Findings):**

- [x] **Doppel-Submit systemweit**: Buttons deaktivieren sich jetzt automatisch im `loading`-Zustand
- [x] **Subuser-Rechte im UI**: Tabs, Power-Buttons und Danger-Zone richten sich jetzt nach den effektiven Rechten (`myPermissions` vom Backend). Ein Subuser mit nur Konsole/Command/Power sieht exakt den Konsolen-Tab — **im Browser-Video demonstriert** (Moderator vs. Admin)
- [x] **Stale-Response-Races** beim schnellen Server-Wechsel (Konsole zeigte Zeilen des vorherigen Servers) + Dedupe beim Merge von Backlog und Live-Stream
- [x] **WS-Reconnect nach Logout**: ausstehender Reconnect-Timer wird jetzt gecancelt (kein unauthentifizierter Reconnect-Loop mehr)
- [x] **Gelöschte Server verschwinden live** aus anderen offenen Sessions (Dashboard-Karte + Zähler aktualisieren ohne Reload — **im Video festgehalten**); wer die Detailseite offen hat, bekommt Toast + Auto-Redirect (**zweites Video**)
- [x] **Deep-Link nach Login**: `/servers/xyz` aufrufen → einloggen → landet wieder auf `/servers/xyz` statt auf dem Dashboard
- [x] **Verbindungs-Feedback**: „Verbindung getrennt"-Toast kommt jetzt SOFORT beim Abbruch (vorher erst nachträglich), „wiederhergestellt" beim Reconnect
- [x] **i18n-Lücken**: relative Zeiten („vor 5 Min."), Zeilen-Zähler, „Load more", „you"-Badge, Crash-Toast mit Servernamen — alles lokalisiert (EN/DE)
- [x] **Dirty-Check in Editoren**: Backdrop-Klick/Escape verwirft ungespeicherte Änderungen nicht mehr stillschweigend (Datei-Editor, Zeitplan-Editor, Blueprint-Editor fragen nach)
- [x] **Bestätigungen für irreversible Mikro-Aktionen**: API-Key löschen, Rollen-Wechsel — mit Confirm-Dialog und Fehler-Toasts
- [x] **Session-Cookie-Handling**: `parseCookies`-Unit-Tests (6 Fälle inkl. Malformed-Escapes)

### Runde 4 — 2026-07-31 (RCON + Spielerlisten, komplett im Browser demonstriert)

Viele Source-Spiele (CS2, GMod, TF2, Palworld, ARK, …) ignorieren stdin komplett — ohne RCON gibt es dort keine Konsolen-Befehle. Deshalb:

**Source-RCON von Grund auf selbst implementiert** (`server/src/lib/rcon.ts`, null Dependencies):

- [x] Volles Protokoll: Auth-Handshake (beide srcds-Antwort-Reihenfolgen), Multi-Packet-Antworten mit Sentinel-Trick + Quiet-Period-Fallback, TCP-Fragment-Reassembly, Timeouts, 1-MiB-Response-Cap, serialisierte Befehls-Queue — 10 Unit-Tests gegen einen Mock-RCON-Server
- [x] **Konsole über RCON**: Erkennt das Panel ein konfiguriertes RCON (Blueprint + gesetztes Passwort), gehen Konsolen-Befehle automatisch über RCON statt stdin — mit „RCON"-Badge am Eingabefeld. Antworten erscheinen in der Konsole (auf 50 Zeilen gekappt gegen Flooding)
- [x] **Stop über RCON**: neue Stop-Strategie `rcon` (z. B. `quit`) mit SIGTERM-Fallback, wenn RCON nicht erreichbar/konfiguriert ist
- [x] **7 Blueprints erweitert**: CS2, GMod, TF2, L4D2 (`+rcon_password` im Startcommand), Palworld, ARK (getrennte RCON-Ports); Rust-Notiz (WebRCON ≠ Source RCON, noch nicht unterstützt)

**Spielerlisten** (`A2S_PLAYER` + Minecraft-Sample):

- [x] A2S_PLAYER-Query mit Challenge-Handshake, defensivem Parser (Truncation → `null` statt Teil-Listen), 14 neue Unit-Tests inkl. Live-UDP-Roundtrip gegen Fake-Server
- [x] Minecraft-Ping liefert jetzt das `players.sample` mit (§-Farbcodes bereinigt)
- [x] **Players-Karte** in der Konsolen-Sidebar: Name, Score, Spielzeit — live über WebSocket, „+N weitere" ab 20

**Konsolen-Werkzeuge:**

- [x] **Suche/Filter** über den Konsolen-Puffer (case-insensitive, „X / Y Zeilen"-Zähler)
- [x] **Log-Download** als .txt (mit Timestamps + Stream-Labels)

**Dev-Fixture** `server/scripts/fake-srcds.mjs`: simuliert einen echten Source-Server (RCON + A2S mit Challenge) — damit lässt sich der komplette RCON-Pfad ohne 30-GB-Spiel testen. Als Custom-Blueprint im Panel angelegt („CS Legends"-Demo).

**Bugs dieser Runde gefunden & gefixt:**

- [x] **Blueprint-Edits brauchten Panel-Neustart**: Instanzen cachen ihr Blueprint — Custom-Blueprint-Updates (Startcommand, Stop-Strategie, RCON-Config) griffen erst nach Neustart. Jetzt: `refreshBlueprint()` beim PUT, live verifiziert (Hostname-Änderung greift beim nächsten Start sofort)
- [x] Fake-srcds-Blueprint: Variablen mit Leerzeichen im Startcommand müssen gequotet werden (`--name "{{SERVER_NAME}}"`) — Quoting funktioniert durch den Shellwords-Tokenizer sauber

**E2E-Video**: Start → Players-Karte (Gordon/Alyx/Barney mit Scores) → `status`-Befehl über RCON (Multi-Line-Antwort) → Konsolen-Suche „Gordon" (2/42 Zeilen) → Log-Download → Stop via RCON `quit` → sauberer Exit Code 0. Alle 7 Schritte im Video, keine Glitches.

### Runde 5 — 2026-07-31 (Mod-Browser, Auto-Update, Live-Feed)

**Modrinth-Mod/Plugin-Browser** (der wohl größte Pterodactyl-Schmerzpunkt: Mods manuell per SFTP hochladen — jetzt per Klick):

- [x] Modrinth-v2-Client (null Dependencies, Facet-Syntax live gegen die echte API verifiziert), Loader-Mapping pro Blueprint (`paper`/`fabric`/`velocity` + Zielordner `plugins/`/`mods/`), MC-Versions-Filter aus der Server-Variable
- [x] 5 neue API-Endpoints: Übersicht (installierte Jars), Suche, Versionen, Install (sha512-verifizierter Download, Concurrency-Guard, Audit-Log), Löschen — alles Subuser-Rechte-gated (`server.files.*`)
- [x] **Mods-Tab im UI**: Suche mit Debounce, Icons, Download-Zahlen kompakt (9,2M), Install-Button mit Per-Row-Spinner, Installiert-Liste mit Confirm-Löschen — EN/DE
- [x] 15 neue Unit-Tests (Mock-Modrinth-Server) + Live-Smoke gegen die echte API
- [x] **E2E-Video mit ECHTEM Minecraft**: „Plugin Lab" (Paper 1.21.1) → WorldEdit (9,2M Downloads) + Chunky per Klick installiert → Server-Start → beide Plugins laden im Log → `plugins`-Befehl zeigt beide grün. Komplett ohne manuelle Dateiarbeit

**SteamCMD-Auto-Update vor Start** (AMP-Klassiker):

- [x] Server-Option „Auto-update before start": jeder Panel-Start läuft erst durch `app_update` (Status „Updating" → SteamCMD-Konsole → dann Start). Fehlschlag blockiert den Start nicht („starting anyway")
- [x] Nebenbei gefixt: der „Run Steam update"-Button in den Einstellungen war nie sichtbar (Bedingung las ein Feld, das die API gar nicht liefert — jetzt `hasSteamcmd`-Flag)
- [x] **E2E-Video mit ECHTEM Valheim**: Toggle an → Start → „Updating" (SteamCMD verifiziert 1,7 GB in 15,5s, „Success! App '896660' fully installed") → Valheim bootet normal

**Live-Activity-Feed auf dem Dashboard:**

- [x] Neuer admin-gated WebSocket-Kanal `audit`: jede Audit-Aktion (Backups, User-Anlage, Power, Mod-Installs, …) erscheint sofort oben im „Recent activity"-Feed — ohne Reload (im Video: 2 Einträge poppen live rein, ältere rutschen nach unten)

**Kleinere Verbesserungen aus Runde 4/5-Tests:**

- [x] Blueprint-Edits greifen jetzt sofort für existierende Server (vorher: Panel-Neustart nötig, weil Instanzen ihr Blueprint cachen)

### Runde 6 — 2026-07-31 (2FA-Recovery, Server-Klonen, Blueprint-Export/Import, Player-Quick-Actions)

**2FA-Recovery-Codes** (Konto-Absicherung — was tun, wenn das Authenticator-Handy weg ist?):

- [x] Backend: beim Aktivieren von 2FA werden **10 Einmal-Codes** erzeugt (Format `xxxx-xxxx-xxxx`, 60-Bit-Entropie, verzerrungsfreie 5-Bit-Auswahl aus 32er-Alphabet). Gespeichert werden **nur sha256-Hashes** der normalisierten Codes — Klartext erscheint genau einmal
- [x] Login akzeptiert am 2FA-Prompt **wahlweise** den 6-stelligen TOTP-Code **oder** einen Recovery-Code (case-insensitive, Bindestriche/Whitespace egal); ein eingelöster Code wird sofort entwertet (jeder Code genau einmal)
- [x] Codes neu erzeugen (invalidiert alle alten) — beides TOTP-geschützt; neue Endpoints, Audit-Log-Einträge
- [x] UI: Account-Seite zeigt Recovery-Codes-Modal beim Aktivieren + „Neu generieren", Login-Seite mit Hinweis „… oder einer deiner Recovery-Codes"
- [x] 5 neue Unit-Tests (Erzeugung, Format, Eindeutigkeit, Einlösung, Einmaligkeit) + Integrationstest für den kompletten Login-mit-Recovery-Code-Flow
- [x] **E2E-Video 1**: 2FA aktivieren (TOTP-Code eingegeben) → Recovery-Codes-Modal mit 10 Codes. **E2E-Video 2**: Logout → Login mit Passwort → 2FA-Prompt → Recovery-Code eingegeben → eingeloggt (Zähler 10 → 9)

**Server-Klonen** (AMP/Pterodactyl-Klassiker: Testserver duplizieren):

- [x] `manager.clone()`: legt neuen Server mit denselben Variablen an, **optional Datei-Kopie** (rekursiv, sandboxed), **Port-Overrides** (frei wählbar, mit Konfliktprüfung), Blueprint bleibt verknüpft
- [x] Neue API-Route `POST /servers/:id/clone` (owner-gated), Wizard-Modal mit vorbelegtem Namen, Datei-Kopier-Toggle und auto-vorgeschlagenen freien Ports
- [x] **E2E-Video**: Klon-Icon im Header eines Offline-Servers → Modal (Ports auf frei geändert) → „Clone" → „CS Legends (copy)" erscheint im Server-Grid, Konsole zeigt „Cloned from …(files copied)"

**Blueprint-Export/Import**:

- [x] Custom-Blueprints als JSON exportieren (Download) und über den Blueprint-Editor wieder importieren — Teilen/Backup eigener Spielprofile

**Player-Quick-Actions** (Moderation direkt aus der Players-Karte):

- [x] Deklaratives `playerActions`-Feld im Blueprint (`{ key, label, command, confirm? }`, `{{PLAYER}}` wird ersetzt) — Schema-validiert; Minecraft- (Kick/Ban/Op/Deop) und Source-Blueprints (Kick) bestückt
- [x] Players-Karte bekommt pro Zeile ein Aktions-Menü (Kick/Ban…); Ban fragt per Confirm-Dialog nach; Befehl geht über den passenden Transport (RCON oder stdin)
- [x] **Sofort-Aktualisierung**: nach jedem Konsolen-Befehl triggert ein einmaliger Query-Refresh (~1,5s statt bis zu 30s Polling-Wartezeit) — so verschwindet ein gekickter Spieler sofort aus der Karte
- [x] `fake-srcds`-Fixture um echten `kick`-Befehl erweitert (entfernt den Spieler wirklich) + Blueprint mit `playerActions` bestückt
- [x] **E2E-Video**: Players-Karte (Gordon/Alyx/Barney) → Kick auf Gordon → Konsole zeigt Kommando/Antwort → Karte fällt live von 3/16 auf 2/16, Gordon weg

**Tests/Qualität:** 145/145 grün (Unit + Integration), Typecheck & Lint sauber.

### Runde 7 — 2026-07-31 (Security- & Robustness-Hardening, 3. Deep-Review mit 2× Fable 5 Max Thinking)

Zwei unabhängige Review-Subagents (Fable 5 Max Thinking) haben Backend und Frontend erneut kritisch auseinandergenommen. Diesmal kamen **echte Sicherheitslücken** ans Licht — alle gefixt und mit Tests/Live-Demo abgesichert (**148/148 Tests grün**, vorher 145).

**Backend-Security (die wichtigsten Funde):**

- [x] **Subuser-Rechteausweitung geschlossen (kritisch)**: Ein Subuser mit `server.users` konnte sich selbst (und anderen) *beliebige* Rechte geben — inkl. `server.config`, was den Startbefehl frei setzbar macht (= Codeausführung als Panel-User). Fix: beim Anlegen/Ändern von Subusern werden Rechte jetzt auf die **eigenen effektiven Rechte des Vergebers geklammert**, und das Bearbeiten der **eigenen** Subuser-Zeile ist verboten. Integrationstest deckt beide Wege ab
- [x] **Schedule-Rechteumgehung geschlossen**: `server.schedules` allein erlaubte über Zeitplan-Tasks heimlich `power`/`command`/`backup`. Fix: beim Erstellen/Ändern/`Jetzt ausführen` wird pro Task geprüft, ob der Aufrufer die zugehörige Berechtigung (`server.power`/`server.command`/`server.backups`) hält
- [x] **API-Key-Scopes werden jetzt erzwungen**: Scopes wurden gespeichert, aber nie geprüft — jeder Key hatte volle Nutzerrechte. Fix: **Read-only-Keys** (Scope `read`) dürfen nur noch sichere Methoden (GET/HEAD); Keys ohne Scope bleiben Voll-Keys (abwärtskompatibel). Neue „Nur-Lesen"-Option + Badge im Account-UI. **Live verifiziert**: GET → 200, POST → 403 „this API key is read-only"
- [x] **Auto-Restart-Timer-Leak beim Löschen**: Ein *abgestürzter* Server (Prozess bereits weg, aber Restart-Timer läuft) konnte nach dem Löschen den Timer feuern und sich — mit `keepFiles` sogar als echten, ungetrackten Prozess — wiederauferstehen lassen. Fix: neues `dispose()` bricht beim Entfernen alle Timer ab
- [x] **`trust proxy` gehärtet**: stand auf `true` → ein direkt verbundener Client konnte per gefälschtem `X-Forwarded-For` das Login-Ratelimit umgehen (und Audit-IPs verfälschen). Standard jetzt `loopback` (nur lokaler Reverse-Proxy wird vertraut), per `BETWEEN_TRUST_PROXY` konfigurierbar
- [x] **WebSocket-Rechte-Recheck**: Konsolen-Events wurden nur beim Abonnieren rechtegeprüft. Wird `server.console` einem offenen Client entzogen, stoppt der Stream jetzt sofort (Prüfung pro Nachricht)
- [x] Kleiner Robustheits-Fix: `reinstall` war fire-and-forget ohne `.catch` (potenzielle unhandled rejection) — jetzt abgefangen

**Frontend-Robustheit:**

- [x] **Datei-Editor-Race (Datenverlust!) gefixt**: eine langsame Antwort für Datei A konnte nach dem Öffnen von Datei B deren Inhalt überschreiben — und ein anschließendes Speichern hätte A-Inhalt in B geschrieben. Jetzt „latest-wins"-Schutz für Verzeichnis-Listing *und* Editor
- [x] **Schreibrechte-Gating im Datei-Manager**: ein Nur-Lese-Subuser sah bisher alle Schreib-Buttons (die dann mit 403 fehlschlugen). Jetzt sind „Neue Datei/Ordner", Upload, Umbenennen, Löschen, Zip/Entpacken und der Speichern-Button ausgeblendet, wenn `server.files.write` fehlt — **im Browser-Video gezeigt** (Nutzer „viewer" sieht einen reinen Lese-Dateimanager, Inhalt weiterhin sicht- und ladbar)
- [x] **WS-Reconnect-Deadlock gefixt**: Abmelden/Trennen während des Verbindungsaufbaus ließ das `connecting`-Flag hängen → die nächste Verbindung wurde still verworfen (tote Live-Schicht bis Reload). `disconnect()` löst jetzt sauber ab
- [x] **Clipboard-Fallback**: „Kopieren" (u. a. für Recovery-Codes!) schlug auf `http://`-LAN-IPs still fehl (`navigator.clipboard` nur in Secure Contexts). Jetzt `execCommand`-Fallback + klare Fehlermeldung
- [x] Upload-Input wird zurückgesetzt (dieselbe Datei erneut hochladbar); Panel-Settings zeigt bei Ladefehler jetzt Fehler + „Aktualisieren" statt Endlos-Spinner

**Für die nächste Runde vorgemerkt (Review-Funde niedrigerer Priorität):** Tar/Zip-Extraktion gegen OOM/Zip-Bomben deckeln (kumulatives Größen-/Eintragslimit), Konsolen-Backlog nach WS-Reconnect nachladen, Terminal-Zeilen mit stabiler ID (Render-Storm bei vollem Puffer vermeiden), Pterodactyl-Egg-Importer.

### Runde 8 — 2026-07-31 (Archiv-Extraktion gegen Zip-Bomben & OOM härten)

Umsetzung des in Runde 7 vorgemerkten Funds. Ein kleines hochgeladenes Archiv (Upload-Limit 4 GiB) kann sich zu Petabytes entpacken (klassische Zip-Bombe) oder Millionen Einträge enthalten — bisher lief die Extraktion ungebremst und konnte Platte/Speicher/CPU erschöpfen. Jetzt sind **alle** Extraktionspfade (Datei-Manager, Installer-Downloads, SteamCMD-Bootstrap, Backup-Restore) gedeckelt.

- [x] **Gemeinsames Limit-Modul** (`server/src/lib/extractlimits.ts`): kumulatives Byte-Budget (Default **64 GiB**, `BETWEEN_MAX_EXTRACT_GIB`), Entry-Count-Limit (Default **200 000**, `BETWEEN_MAX_EXTRACT_ENTRIES`), Tar-Metadaten-Cap (1 MiB pro Long-Name/pax-Record)
- [x] **ZIP** (`unzip`): Vorabprüfung gegen das Central Directory (ehrlich deklarierte Bombe wird abgelehnt, **bevor** ein Byte geschrieben wird) **plus** ein Streaming-Zähler pro Eintrag, der auch Archive mit *gelogenen* Größenangaben abfängt (Deflate-Output ist nicht durch die deklarierte Größe begrenzt). Halb geschriebene Dateien werden bei Abbruch entfernt
- [x] **TAR/TAR.GZ** (`extractTar`): kumulatives Byte-Budget über *alle* Body-Bytes (deckt auch Gzip-Bomben und CPU-Erschöpfung ab), Entry-Count-Limit, Metadaten-Cap. **Discard-Einträge** (unsichere Namen, Symlinks/Hardlinks/Devices) werden jetzt *stream-übersprungen* statt komplett in den Speicher gepuffert — vorher konnte ein einzelner präparierter Eintrag GBs an RAM binden
- [x] **Nebenbefund gefixt**: der ZIP-*Writer* (`zipDirectory`) hängte pro Eintrag neue `error`/`close`-Listener an den Ausgabestream (`pipeline(..., out, { end: false })`) → `MaxListenersExceededWarning` und Leak bei großen Verzeichnissen. Jetzt wird der komprimierte Stream ohne Listener-Leak geschrieben
- [x] **8 neue Unit-Tests** (`extractlimits.test.ts`): ehrliche Zip-Bombe, Zip mit gelogener Metadaten-Größe, Zip-/Tar-Entry-Flut, Tar-Byte-Budget (+ Partial-Cleanup), Gzip-Bombe (winzig auf Platte), übergroße pax/Long-Name-Records, und der Nachweis, dass unsichere/Nicht-Regular-Einträge übersprungen werden, der Stream aber sauber weiterläuft
- [x] **Live über die echte HTTP-API verifiziert** (Panel mit `BETWEEN_MAX_EXTRACT_GIB=1`): 1169-Byte-Archiv, das 2 GiB deklariert → Upload 200, Entpacken **400 „archive too large: declares 2.0 GiB extracted (limit 1.0 GiB)"**, Zielordner bleibt leer; ein legitimes ZIP entpackt unverändert (kein Fehlalarm)
- [x] README: neue Env-Variablen dokumentiert (`BETWEEN_MAX_EXTRACT_GIB`, `BETWEEN_MAX_EXTRACT_ENTRIES`, `BETWEEN_TRUST_PROXY`) und veraltete Default-/Zahlenangaben korrigiert

**Review durch Fable 5 Max Thinking (fand eine echte Lücke):**

- [x] **Prozess-Crash-DoS im `unzip` gefixt (High)**: Der Zweig für leere Einträge (`csize === 0`) rief `dest.end()` auf einem *nicht awaiteten* Write-Stream ohne `error`-Handler auf. Kollidierte der Eintragsname mit einem bereits existierenden **Verzeichnis** (präparierbar als `foo/` + gespeicherter leerer `foo`), wurde der asynchrone `EISDIR`-Fehler zu einer `uncaughtException` → das ganze Panel stürzt ab. Jetzt wird die leere Datei **synchron** erzeugt (`openSync`), sodass der Fehler abgefangen wird, die Extraktion sauber abbricht und das vorhandene Verzeichnis erhalten bleibt. 2 Regressionstests
- [x] **Präzisions-Clamp (Low)**: `BETWEEN_MAX_EXTRACT_GIB` wird auf ≤ 1 PiB begrenzt, damit `maxBytes` auch bei absurder Fehlkonfiguration unter `Number.MAX_SAFE_INTEGER` bleibt
- [ ] **Vorgemerkt (Medium, nächste Runde):** Bei Abbruch bleiben bereits entpackte Dateien liegen (kein Rollback); das Byte-Budget deckelt den Worst Case, aber ein Angreifer könnte bis zum Limit Platte belegen. Sauberer Fix: in ein Temp-Verzeichnis entpacken und erst bei Erfolg atomar verschieben — heikel, weil Backup-Restore bewusst über bestehende Dateien legt (Merge-Semantik). Wird separat angegangen

**Tests/Qualität:** 158/158 grün (Unit + Integration), Typecheck & Lint sauber; live über die HTTP-API auf finalem Stand bestätigt (Bombe → 400, legitimes ZIP → 200).

### Runde 9 — 2026-08-03 (Docker-Runtime, Egg-Importer, Design-Overhaul — Rivale zu AMP/Pterodactyl)

Große Runde, komplett mit Subagents (Fable 5 Max Thinking) gebaut und reviewt. Ziel: Between soll Docker können und Pterodactyls Ökosystem anzapfen.

**1. Docker-Runtime (das Kern-Feature):**

- [x] **Hand-gerollter Docker-Engine-API-Client** (`server/src/lib/docker.ts`, null Dependencies): HTTP über den lokalen Daemon-Socket (Unix-Socket bzw. Windows-Named-Pipe), Image-Inspect/-Pull mit ndjson-Fortschritt, Container create/start/kill/wait/remove/inspect/list, Log-Fetch, Live-**Stats-Stream** und ein **hijacked bidirektionaler Attach-Stream** für Konsolen-I/O. Eigener Multiplex-Demuxer für das Docker-Stream-Framing.
- [x] **Runtime-Abstraktion** (`server/src/servers/runtime.ts`): ein gestarteter Server ist ein `RuntimeHandle` — entweder ein Host-Prozess (klassisch) oder ein Container. Der ganze Lifecycle in `instance.ts` (Konsole, Ready-Erkennung, Stop-Ketten, Crash-Detection, Ressourcen, Queries, RCON) ist jetzt runtime-agnostisch.
- [x] **Container überleben Panel-Neustarts**: beim Shutdown werden Container *detached* statt gestoppt; beim Boot werden laufende Container über ein Label re-adoptiert (inkl. Konsolen-Backlog aus den Container-Logs). Etwas, das der Prozess-Modus prinzipbedingt nicht kann.
- [x] Harte **Memory-/CPU-Limits** (cgroups), **Bridge/Host-Netzwerk**, Port-Publishing 1:1, Container laufen als **Panel-User** (nie root) mit nur dem Server-Verzeichnis gemountet, `Init: true` (tini) für sauberes Signal-Handling. Server-Löschen entfernt Container (laufend + Leichen).
- [x] `runtime`/`docker`-Felder in Blueprint-/Server-Schema + Validierung (Image-Ref-Regex, geklammerte Limits), neue API `GET /api/docker/status`, Docker-Verfügbarkeit im Blueprint-Listing, Docker-Defaults in 9 Builtin-Blueprints (Java-Familie mit Image-Auswahl Java 8–25, Demo, Custom, Factorio).
- [x] **Frontend**: Runtime-Picker im Erstell-Wizard **und** im Server-Settings-Tab (Image-Dropdown + Custom, Limits, Netzwerk), Docker-Badge in Header/Listen/Dashboard/Palette, Docker-Status-Karte in den Panel-Settings.

**2. Pterodactyl-Egg-Importer** (`server/src/lib/eggs.ts`): PTDL_v1 **und** v2, doppelt-kodierte `config`-Strings, Laravel-Rules → Variablentypen, `{{VAR}}`-Startup + Ptero-Builtins (`SERVER_MEMORY`/`SERVER_PORT`/…), `docker_images` → Image-Auswahl, `config.files` → Between-`configFiles`, `scripts.installation` → neuer **`docker-script`-Install-Step** (läuft das Egg-Install-Skript als root in einem Wegwerf-Container mit dem Server-Dir unter `/mnt/server`, Pterodactyl-Konvention). Neuer Admin-Endpoint `POST /api/blueprints/import-egg` + Import-UI mit Vorschau und Warn-Liste für jeden verlustbehafteten Mapping-Schritt.

**3. Design-Overhaul:** Command-Palette (**Strg/⌘+K**, Fuzzy-Sprung zu Servern/Seiten/Aktionen), Dashboard mit Zeit-basiertem Gruß + Live-Zusammenfassung + „Neuer Server", zweispaltiger Login mit Feature-Panel, Karten-Hover-Politur, Glow am „Running"-Status. Dazu zwei Konsolen-Fixes aus Runde-7-Merkliste: **stabile Zeilen-IDs** (`seq`) statt Positions-Keys (kein Render-Storm mehr bei vollem Puffer) und **Backlog-Nachladen nach WS-Reconnect** (Zeilen während Trennung gehen nicht mehr verloren).

**4. Deep-Review (Fable 5 Max Thinking) — 6 echte Bugs gefixt + Härtung:**

- [x] **High**: pre-aborted `AbortSignal` löste ein unbehandeltes `error`-Event → **Prozess-Crash** (Abbruch eines Installs/Shutdowns im falschen Moment). Fix: `error`-Handler vor jeder `destroy()` verdrahtet.
- [x] **High**: ein extrem schnell beendeter Container meldete seinen Exit, bevor `start()` das Handle installiert hatte → **Zombie-Handle** (Server hängt für immer auf „crashed | läuft"). Fix: solche Exits werden bis zur Handle-Installation gepuffert (in `start()` **und** in der Re-Adoption).
- [x] **Medium**: Demuxer/Pull-Parser puffern bei gelogenem Frame-Header nicht mehr unbegrenzt (1-MiB-Cap, Oversized-Frames werden durchgestreamt); Delete-während-Start hinterlässt keinen verwaisten Container mehr; Install-Container-Leichen nach Panel-Crash werden beim Boot aufgeräumt; `detach()`-Race gegen `watch()` leakt keine Sockets mehr.
- [x] **Low**: Container-IDs in allen API-Pfaden `encodeURIComponent`-kodiert (Defense-in-Depth gegen Request-Smuggling in der hand-geschriebenen Attach-Zeile); Egg-generiertes `readyRegex` gedeckelt (max 8 Marker · 200 Zeichen); Konsolen-`seq`-Keys um `ts` ergänzt (kollisionsfrei über Panel-Neustarts).
- [x] 8 neue Regressionstests dafür.

**E2E (echter Docker-Daemon in der VM):** Minecraft **Paper 1.21.1** über den Wizard auf der **Docker-Runtime** erstellt (eclipse-temurin:21-jre) → Install (Paper-Download) → Container-Start → Konsole erreicht „Done" → `say`/`list` über den Attach-Stream → Live-Query (Paper 1.21.1, 9 ms) + Stats → Stop → Container entfernt. Zwei Videos (Erstellung + laufende Konsole). Panel-Neustart-Überleben durch Integrationstest abgedeckt.

**Tests/Qualität:** **216/216 grün** (Unit + Integration, inkl. Live-Docker- und Egg-Tests), Typecheck & Lint sauber, 43/43 Blueprints valide.

### Runde 10 — 2026-08-03 (Docker-Robustheit + Image-Pull-Aktion)

Kein neues User-Feedback im Loop → weiter poliert und die Runde-9-Restpunkte des Reviews abgearbeitet.

**Robustheit (selbst, mit Regressionstests):**

- [x] **Container-Liveness-Re-Verify**: Wenn der Exit-Long-Poll (oder der Attach-Stream) durch einen Daemon-/Verbindungs-Hänger abreißt, galt der Container bisher sofort als „gecrasht" und wurde entfernt — ein kurzer Daemon-Schluckauf konnte also ein **laufendes Spiel killen**. Jetzt wird zuerst per `inspect` geprüft: läuft der Container noch, hängt sich das Panel **neu an** (Attach + Stats + Wait neu aufgebaut, gedeckelt gegen Endlos-Schleifen); ist er wirklich weg, wird's als Exit gemeldet. Zwei Regressionstests (noch-am-Leben → re-attach, verschwunden → Exit).
- [x] **Ready-Regex einmal pro Start kompiliert** statt bei jeder Konsolenzeile (Perf; ein Busy-Server spuckt Tausende Zeilen/s).
- [x] **`memoryLimitMb`-NaN-Guard** in `updateServer` (nicht-numerischer PATCH landete als `NaN` im Store).

**Flagship — Docker-Image on-demand ziehen/aktualisieren** (AMP/Pterodactyl-Klassiker, per Subagent Fable 5 Max Thinking):

- [x] `ServerManager.pullDockerImage()` + Route `POST /servers/:id/docker/pull` (`server.config`): zieht das effektive Image, streamt den Fortschritt live als `install`-Zeilen in die Konsole. Nutzt den vorhandenen `installController` für Abbruch + Nebenläufigkeits-Schutz (Server-Löschen/Shutdown brechen den Pull ab; kein Parallel-Lauf mit Reinstall/Steam-Update). Ändert bewusst **nicht** den Status — ein laufender Container behält sein Image, das neue greift beim nächsten Start (Hinweis im UI).
- [x] Button „Pull / update image" in der Runtime-Karte der Server-Einstellungen (nur bei Docker-Runtime + erreichbarem Daemon), Toast + Fortschritt im Konsolen-Tab.
- [x] 8 neue Tests (Unit mit Fake-Daemon + Live-Integration: echter Download von Docker Hub, Pull bei laufendem Container lässt den Container-ID unverändert).

**Beim Testen gefunden & gefixt (echter Bug):**

- [x] Die Server-Detail-API lieferte im `blueprint`-Subset **kein `platforms`** → `SettingsTab` las `server.blueprint.platforms.includes('linux')` und **crashte die Runtime-Karte** bei Docker-Servern. Fix: `platforms` ins Detail-Payload aufgenommen (+ defensives Optional-Chaining), Regressions-Assertion im Integrationstest.
- [x] **Test-Flake beseitigt**: die Docker-Integrationstest-Dateien liefen parallel und stritten sich um den gemeinsamen Daemon (Timeouts). `--test-concurrency=1` macht die Suite deterministisch (isoliert grün war der betroffene Test in 0,2 s statt 60 s Timeout).

**E2E:** Image-Pull im Browser demonstriert — Runtime-Karte → „Pull / update image" → Konsole streamt echten Layer-Download von `node:22-slim` bis „Image node:22-slim updated." (Video).

**Tests/Qualität:** **226/226 grün** (serielle Ausführung, kein Flake), Typecheck & Lint sauber, 43/43 Blueprints valide.

### Runde 11 — 2026-08-03 (Industrie-Standard: „jedes Spiel" + kinderleicht Spiele & Configs hinzufügen)

Kein neues User-Feedback im Loop → große, koordinierte Runde mit mehreren Fable-5-Max-Thinking-Subagents auf disjunkten Dateien, danach Deep-Review.

**1. Config-Engine + Live-Config-Editor (die „plus deren Configs"-Basis):**

- [x] Hand-gerolltes **YAML** (`server/src/lib/yaml.ts`) und **TOML** (`server/src/lib/toml.ts`) — null Dependencies, **chirurgische** In-Place-Updates, die Kommentare/Formatierung/unbeteiligte Keys byte-genau erhalten (genau wie die bestehenden properties/ini-Updater), plus Parser für die Lese-Seite. Dokumentierte Grenzen (kein voller YAML-1.2/TOML-1.0-Umfang, aber deckt echte Game-/Plugin-Configs).
- [x] **Config-Lese/Schreib-API**: `GET /api/servers/:id/configfiles` (zeigt je deklarierter Config-Datei die verwalteten Keys mit aktuellem On-Disk-Wert) und `PUT` (schreibt Werte über die Format-Engine, nur deklarierte Pfade, `safeJoin`-gesichert).
- [x] **Live-Config-Editor** im Config-Tab: jede deklarierte Config-Datei mit typisierten Feldern pro Key, Dirty-Tracking pro Datei, „Save file", raw→Files-Link. **Im Browser demonstriert** (Paper `server.properties`: motd + max-players live geändert, auf Platte verifiziert).

**2. Game Library — „gefühlt jedes Spiel":**

- [x] Kuratierter **Katalog mit 60 Einträgen** (`server/src/catalog/`): 40 Builtins + 20 Community-Eggs (echte öffentliche Egg-Repos). `GET /api/catalog` + `POST /api/catalog/:id/add`. Builtin-Einträge sind sofort nutzbar; Community-Eggs werden beim Hinzufügen geholt, per `convertEgg` umgewandelt und gespeichert. Self-Check stellt sicher, dass jeder Builtin-Verweis existiert (kein „Katalog-Rot").
- [x] **Egg-Import per URL** (jeden Pterodactyl/Pelican-Egg-Link einlesen) mit **SSRF-Härtung** (`server/src/lib/nettrust.ts`): nur http/https, private/loopback/link-local/reservierte IPv4+IPv6 blockiert, DNS-Auflösung geprüft, Redirects pro Hop revalidiert, Timeout + Größen-Cap.
- [x] Neue **Game-Library-Seite** (Suche, Kategorien, Built-in/Community/Added-Badges, 1-Klick-Add mit Warn-Modal, „Create server"-Link) + Nav + Command-Palette. **Im Browser demonstriert** (Veloren-Community-Egg per Klick hinzugefügt).

**3. +30 Builtin-Blueprints → 73 gesamt** (`server/src/blueprints/builtin/`): u. a. The Isle, Icarus, Conan Exiles, ARK: SA, Empyrion, Avorion, Pavlov VR, viele Source-Shooter (DoD:S, CS:S, HL2:DM, NMRiH, Sven Co-op, ZPS, FoF), Xonotic, OpenTTD, ETS2, tModLoader, open.mp, MTA, FiveM, TeamSpeak 3, Mumble, und MC Forge/NeoForge/Quilt/Folia. Viele wurden **live gebootet** (OpenTTD, TS3, Murmur, open.mp, MTA, tModLoader, Quilt, NeoForge …). Passende `configFiles` (yaml/toml/ini/json/keyvalue), `rcon`/`query`/`docker`-Blöcke, `docs/GAMES.md` erweitert. Ein paar SteamCMD-App-IDs/Start-Args sind als „vor Produktivnutzung verifizieren" markiert.

**4. Deep-Review (Fable 5 Max Thinking) — 2 kritische Bugs gefixt:**

- [x] **KRITISCH — Prototype-Pollution in `parseToml`**: ein `.toml` mit `[__proto__]` / `a.constructor.prototype.x` verschmutzte `Object.prototype` global (erreichbar über `GET /configfiles` → `getConfigValue`). Gefixt (Descent durch `__proto__`/`constructor`/`prototype` verweigert).
- [x] **KRITISCH — Prototype-Pollution in `applyJsonPath`**: über `PUT /configfiles`-Keys bzw. ein präpariertes Egg-Mapping (`__proto__.x`) erreichbar. Gefixt (gefährliche Dot-Paths verworfen), `parseYaml` defensiv nachgezogen.
- [x] Ungültige/verlustbehaftete Zahlen-Quotings in YAML/TOML gefixt (führende Nullen `08`/`007`, `3.0`) — sonst reparste SnakeYAML `007` als Oktal bzw. TOML wäre ungültig. Egg-in-Docker-Testtimeout für Determinismus erhöht. +5 Regressionstests.

**Tests/Qualität:** **285/285 grün**, Typecheck & Lint sauber, **73/73 Blueprints** valide.

### Runde 12 — 2026-08-04 (Web-Terminal: interaktive Shell im Container)

Kein neues User-Feedback im Loop → Flagship gebaut (Subagent, Fable 5 Max Thinking) + Deep-Review.

**Web-Terminal (`docker exec`-Shell im laufenden Container):**

- [x] `docker.ts`: die HTTP/1.1-Socket-Hijack-Mechanik (Connection: Upgrade) in einen privaten `hijack()`-Helper gezogen, den jetzt **sowohl** `attachContainer` (byte-genau unverändert) **als auch** die neuen `execCreate` / `execStart` (TTY, roher Stream ohne Demux) / `execResize` nutzen.
- [x] Neuer **`ShellHub`** (`server/src/ws/shell.ts`): eine dedizierte WebSocket pro Session unter `/api/servers/:id/shell`, session-cookie-authentifiziert wie der Haupt-Hub, hinter **`server.config`** (Shell = beliebige Code-Ausführung, gleicher Trust wie der Start-Command-Override). **Nur Docker-Runtime** mit laufendem Container; die Exec zielt ausschließlich auf den Container *dieses* Servers (nie eine Host-Shell). Protokoll: Ausgabe als Text-Frames, Eingabe als `{op:'stdin'|'resize'}`. Sauberes Teardown auf allen Wegen (Client-Close, Shell-Exit, Container-Tod, Ping-Reaper, App-Stop, Race beim Setup).
- [x] **Shell-Tab** im Server-Detail (nur bei Docker-Runtime sichtbar, `server.config`-gated): dunkles Terminal mit Verbindungsstatus, Reconnect, Eingabe-History, ANSI-Cleanup, gedeckelter Scrollback.
- [x] Tests: Unit gegen Fake-Daemon (Exec-Create/Start/Resize + roher Passthrough beweist „kein Demux im TTY-Modus"; Attach bleibt grün) + Live-Integration (echte Shell in einen `node:22-alpine`-Container, `echo`/`cd`/`pwd`, persistente Session; Non-Docker → Fehler; ohne Cookie → 401).

**Deep-Review (Fable 5 Max Thinking) — 4 Bugs + 2 Härtungen:**

- [x] **High**: Output-Buffering bei langsamem Client war unbegrenzt (`ws.send`-Queue wuchs im RAM; ein `yes`-Flood → OOM). Fix: Session bei `bufferedAmount > 4 MiB` beenden (live verifiziert: RSS-Wachstum von +96 MB auf +16 MB gedeckelt).
- [x] **Medium**: eine offene Shell **überlebte den Entzug** von `server.config`. Fix: Re-Check pro Eingabe-Frame (Eingabe stoppt sofort) + Sweep im 30-s-Ping-Reaper (Output-only-Watcher fallen binnen ~30 s) — analog zum Console-Kanal.
- [x] **Low**: Multi-Byte-UTF-8 an 64-KiB-Chunk-Grenzen zerhackt → `StringDecoder` pro Session. Fehlerhafte `%`-Escapes in der ID → lokal 400 statt bloßem Handshake-Abbruch. Härtung: `.catch` auf dem async Upgrade-Pfad, Inbound-Frame-Cap 4 MiB. +4 Regressionstests.

**Tests/Qualität:** **299/299 grün**, Typecheck & Lint sauber, **73/73 Blueprints** valide.

### Runde 13 — 2026-08-12 (Stabilitäts-Härtung: Leaks, Timer, Child-Prozesse, Backpressure)

Die Ausgangslage war funktional grün, aber der gezielte Langzeit-Audit fand mehrere Pfade, die ein Panel unter Last oder nach wiederholten Starts/Stops erst nach einiger Laufzeit destabilisieren konnten.

**Gefundene & gefixte Stabilitätsprobleme:**

- [x] **Main-WebSocket ohne Backpressure-Cap**: Ein langsamer/angehaltener Browser konnte bei einer lauten Game-Konsole unbegrenzt Sendepuffer im Panel aufbauen. Jetzt 4-MiB-Cap + sofortiges Terminate; eingehende Frames sind auf 64 KiB begrenzt.
- [x] **Offene Sockets überlebten Logout/Session-Entzug**: Main-Hub und Docker-Shell prüfen die ursprüngliche Session während der gesamten Verbindung erneut. Logout, Ablauf, Suspendierung und Session-Revoke schließen den Socket; Audit-/Console-Rechte werden weiterhin pro Nachricht geprüft.
- [x] **Ungetrackte Instance-Timer**: Fallback-Ready-, initiale Query- und Command-Refresh-Timer konnten nach Exit/Restart weiterfeuern. Alle Timer gehören jetzt der Instance, werden beim Cleanup gelöscht und Query-Refreshes koaleszieren. Sampling/Queries laufen nicht überlappend und erzeugen keine unbehandelten Promise-Rejections.
- [x] **Console-Log-FD/RAM-Risiko**: Log-WriteStreams hatten keinen asynchronen `error`-Handler (ENOSPC/EACCES → Prozess-Crash), ignorierten Backpressure und blieben nach Install-/Fehlstart-Ausgabe offen. Jetzt: Error-Containment, Backpressure-Drop-Zähler, Idle-Close und deterministisches Cleanup.
- [x] **Child-stdio-Exit-Race**: Prozess-, Installer- und SteamCMD-Pfade warteten auf `exit`, obwohl stdout/stderr noch Daten liefern konnten; stdin-EPIPE konnte als unbehandeltes Event hochkommen. Jetzt wird auf `close` gewartet, Streamfehler sind verdrahtet und SteamCMD-Bootstrap-Downloads übernehmen das AbortSignal.
- [x] **Shutdown-Races**: Docker-Re-Adoption und gestaffelte Autostarts werden getrackt/gejoint; offene WebSockets werden beim Shutdown terminiert; lange Schedule-Waits sind abbrechbar und werden gejoint; Discord-Fetches haben 10-s-Timeout + Shutdown-Abbruch; Frontend-Toast-/Schedule-Timer werden beim Unmount gelöscht.
- [x] **Unbegrenzte Nebenpuffer**: Login-Rate-Limit-IPs sind auf 10.000 aktive Fenster gedeckelt (danach fail-closed); normale Docker-API-Antworten auf 16 MiB und Pull-Layer-State auf 10.000 Einträge.
- [x] **Dependency-Audit**: transitive `nanoid`-DoS-Lücke von 3.3.16 auf 3.3.18 gepatcht; `npm audit` jetzt 0 Findings.

**Runtime-Evidence ohne Docker-Daemon:**

- [x] `/api/docker/status` → 200 + `available:false`; Docker-Server-Anlage → sauberes 400 statt Crash; Prozess-Runtime unverändert funktionsfähig.
- [x] curl-Journey: unauth → 401, Login → 200, Create → 201, Read/Patch/Start/Command/Console → 200, Live-Console-Event über `/api/ws`, Stop/Delete → 200.
- [x] 310-s-Soak: 160 s idle + 5 Aktivitätszyklen; Panel und Demo-Server blieben gesund, RSS 117216→118904 KiB, FDs 37→38 während aktiver Verbindung; 0 Treffer für `unhandled`, `uncaught`, `MaxListenersExceeded`, `ENOMEM`, `EPIPE`, `failed` oder `error`.
- [x] Nach Stop/Delete war der Game-Child-PID beendet und `/api/meta` antwortete weiter mit 200.

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Integrationstests mangels Daemon sauber übersprungen), 0 Fehler; Typecheck, Produktions-Build, Lint **ohne Warnungen**, `npm audit` 0 Vulnerabilities, **73/73 Blueprints** valide.

### Runde 14 — 2026-08-15 (Liquid-Glass-Redesign: Apple-Stil, Mobile-Version, Motion-System)

Dein Auftrag: UI moderner, Apple-Stil / „Liquid Glass", schöne Animationen, dynamisch skalierend über Auflösungen, volle Mobile-Nutzbarkeit derselben Seite. Umgesetzt in **9 Subagent-Wellen** (Fable 5 Max Thinking; Implementierung, Reviews, Fixes, Verifikation — alles durch Subagents).

**1. Design-System als bindender Vertrag (`Between/web/DESIGN.md`):**

- [x] **Glass-Materialien** `.glass` / `.glass-strong` / `.glass-subtle`: transluzente Flächen per `color-mix` aus den Theme-Tokens, `backdrop-blur + saturate`, Hairline-Border, spekulare Oberkante, weiche Schatten. Alles über `--glass-*`-Variablen getrieben → funktioniert auf allen 7 Themes (Daylight = „White Frost" mit eigenem Variablen-Satz via `data-theme-dark`); `@supports`-Fallback ohne `backdrop-filter`; hartes **Blur-Budget** (nie in Listenzeilen — `.glass-subtle` ist bewusst blur-frei).
- [x] **Motion-System**: `fade-in`/`fade-in-up`, `scale-in`, `slide-up-sheet`, `slide-in-left`, `.stagger` (+40 ms/Kind), `.pressable` (federnder Press-Scale) — als **variantenfähige Tailwind-Utilities** (`sm:scale-in`), komplett von `prefers-reduced-motion` neutralisiert (inkl. Delays!), Seitenwechsel-Transition im Layout (gekeyt auf die ersten Pfadsegmente, damit Tab-Wechsel den Konsolen-State nicht remounten).
- [x] **Dynamische Skalierung**: Root-Font `clamp(13.5px → 16px)` + rem-Regel für alle UI-Texte (Mono/Konsole bewusst px), Content-Container `max-w-7xl` mit fluidem `clamp`-Padding, `viewport-fit=cover` + Safe-Area-Klassen.
- [x] **Apple-Typo**: SF-first-Stack (`-apple-system` → `Segoe UI Variable` → Inter-Webfont), Space Grotesk entfernt, Display-Titel mit −0.02em-Tracking, `.tabular` für alle Statistik-Zahlen.
- [x] **Primitives**: Toggle als iOS-Switch, neue `SegmentedControl`, `IconButton` (Pflicht-`aria-label`, `loading`), `Chip` (Filter-Pills, `aria-pressed`), Card = Glass `rounded-2xl`, glasige Inputs mit Akzent-Fokusring, 44-px-Touch-Targets bei `pointer: coarse`.

**2. Alles restylt (4 parallele Seiten-Wellen mit disjunktem Datei-Besitz):** Dashboard (Glass-Hero + Stagger-Metriken), Servers (Chip-Filter, 2×2-Stats mobil), Create (Stepper mit Gradient-Verbindern), Catalog/Blueprints (Glass-Grids), Server-Detail komplett (Hero-Header, Pill-Tab-Strip, Konsole mit `dvh`-Höhe, Files mit `.table-scroll` + **touch-sichtbaren** Zeilen-Aktionen, Danger-Zone in Danger-Glas), Login/Setup (Glass-Strong-Karten), Account/Appearance (**Theme-Karten mit Live-Mini-Previews**), AdminUsers/Audit (Tabellen scrollen im Karten-Rahmen statt die Seite zu sprengen), 404; Modal (**mobil = Bottom-Sheet mit Grab-Handle**, Desktop = Scale-in), ConfirmModal, Command-Palette, Terminal-Frame (`--console-bg`-Token), StatusPill, Sparkline/ProgressBar (Gradient), GameIcon, RuntimePicker, VariablesForm (animierte Advanced-Disclosure), Toasts (mobil **über dem Dock**).

**3. Mobile-Version:** Floating-Glass-**Bottom-Dock** (<1024px: Dashboard / Server / Library / Mehr), Drawer mit voller Navigation (Slide-in, schließt bei Routenwechsel), Bottom-Sheets, Safe-Areas, keinerlei horizontaler Overflow bei 390px (per `scrollWidth`-Probe auf jeder Seite gemessen), Landscape 844×390 geprüft (Sheets/Terminal passen per `dvh`/`min-h`).

**4. Bugs gefunden & gefixt (nicht nur Optik):**

- [x] **„server not found"-Flash**: Fehlerzustand war nicht id-gekeyt und wurde beim Navigieren nicht zurückgesetzt; ein fehlgeschlagener Refresh blankte sogar eine geladene Seite. Jetzt: `{id, message, status}`-Fehler, Render-Guard gegen Fremd-id-Fehler, Vollseiten-Fehler nur ohne geladenen Server, 404 via `ApiError.status` mit übersetztem Glass-Empty-State. **Beweis**: 150-Frame-rAF-Sampling + MutationObserver → 0 Fehler-Frames beim Ping-Pong zwischen Servern.
- [x] **`.stagger` war seit jeher wirkungslos** (unlayered `fade-in-up` schlug die Delays) — als Utility mit verschachtelten `nth-child`-Regeln repariert.
- [x] **Reduced-Motion ließ Stagger-Delays stehen** → Inhalt blieb bis 320 ms unsichtbar und „ploppte" — Delays werden jetzt mitgenullt.
- [x] **Flexbox-Zentrier-Clipping** auf kurzen Viewports (Setup **und** Login): `items-center justify-center` + `overflow-y-auto` macht Kopfinhalt unerreichbar (−106px `scrollTop`-Falle) — klassischer Fix via `m-auto`.
- [x] **Setup-Wizard erstmals echt verifiziert**: Wegwerf-Zweitinstanz (`BETWEEN_DATA=/tmp/… BETWEEN_PORT=8585`), Wizard gerendert, Admin-Account per CDP durchgeklickt, Landung im Panel — dann sauber abgebaut.

**5. Zwei Review-Wellen (defensives QA, Fable 5 Max Thinking):**

- [x] **Kontrast gemessen** (echtes Alpha-Compositing über dem Glass-Stack): Mikro-Labels von `text-muted/60-70` auf voll `text-muted` (5.97 dunkel / 5.48 hell); **Light-Theme-Statusfarben** waren ~2.2:1 → `slate-light` bekommt eigene Semantik-Tokens `#147a3a`/`#ac4f08`/`#b91c1c` (≥4.5:1 auf Surface, Bg **und** Elevated, numerisch nachgerechnet).
- [x] **Modal-Fokusfalle**: initialer Fokus (autoFocus-sicher), Tab/Shift-Tab-Zyklus, `role="dialog"`+`aria-modal`+`aria-labelledby`, Fokus-Restore auf den Öffner (StrictMode-Doppelmount abgefangen); per CDP-Tastatur-Events bewiesen (Zyklus, Reverse, Restore, Dirty-Discard-Pfad).
- [x] Toggle bekam `aria-label`-Durchreichung (Schedules-Schalter benannt), Players-Menü-Trigger benannt, Blur-Budget auf der Servers-Seite durchgesetzt (5→3 Blur-Flächen), Z-Leiter verifiziert (Dock 30 < Drawer 40 < Modal 50 < Palette 90 < Toasts 100), i18n-Parität ist compiler-erzwungen, tote Keys entfernt.

**Demos (Video-Review-bestätigt):** Desktop-Tour (Palette, Konsole, Tabs, Theme-Wechsel Daylight↔Dark) + Mobile-Tour (Dock-Navigation, Konsole, Bottom-Sheet-Clone, Drawer, Audit-Tabelle) als MP4-Artefakte; dazu Screenshots aller Kernseiten in dark/light/carbon.

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Skips), 0 Fehler; Typecheck, Lint (0 Warnungen), Produktions-Build sauber; **73/73 Blueprints** valide. Server-Code unangetastet (reines Frontend + 2 i18n-Dateien).

### Runde 15 — 2026-08-16 (Perfektions-Pass: 40-Punkte-Audit → Fixes → Re-Audit)

Dein Auftrag: „sieht nicht perfekt aus — mach es perfekt, loope endlos". Umgesetzt als Audit-→Fix-→Re-Audit-Schleife, komplett mit Fable-5-Max-Thinking-Subagents.

**1. Gnadenloses Design-Audit (78 Screenshots, 4 Themes, 4 Viewports):** priorisierte 40-Punkte-Mängelliste mit gemessenen Pixelwerten, exakten Dateien und konkreten Fixes (1× P0, 13× P1, 26× P2).

**2. Der P0:** Konsole auf hellen Themes war schwarz-auf-schwarz (Theme-Tokens auf theme-invariantem dunklem Konsolen-Grund). Jetzt: fixe `--console-text-*`-Tokens analog zur ANSI-Palette — Konsole auf allen 7 Themes lesbar.

**3. Die wichtigsten P1-Fixes:**

- [x] **Sparkline-Bug mit Tiefgang**: konstante Serien wurden als deckende Fläche gerendert — und der eigentliche Linien-Gradient war per SVG-Spezifikation unsichtbar (Zero-Height-BBox bei horizontaler Linie → `objectBoundingBox`-Gradient rendert nichts). Fix: Midline-Sonderfall + `userSpaceOnUse` + 25 % Headroom; RAM-Sparkline skaliert jetzt gegen Host-Gesamtspeicher (Daten kamen schon per WS).
- [x] **10-px-Layout-Shift** zwischen Seiten mit/ohne Scrollbar → `scrollbar-gutter: stable` (gemessen: identische Breiten).
- [x] **Roh-Audit-Keys im Dashboard** („server.power.start") → gemeinsame `lib/audit.ts` mit 22 humanisierten i18n-Labels + Tint-Mapping, auf allen drei Flächen (Dashboard, Audit-Log, Server-Activity) dieselbe Behandlung.
- [x] **Katalog beruhigt**: 60 leuchtende Primary-CTAs → Secondary, Badge nur noch für die seltene Sorte (Community), Karten jetzt echt klickbar (eine Aktion, kein Doppel-Feuer).
- [x] **Deep-Link-Sackgasse**: `?blueprint=`-Einstieg füllte den Servernamen nicht vor → disabled-Primary-Falle; gefixt (+ Stepper-Konnektor füllt bis zum aktiven Schritt).
- [x] **Ehrliche Save-Buttons**: Server-Settings-Save committete stillschweigend eine fremde Karte (Crash-Restart als Subsektion eingefaltet); Panel-Settings-Header-Save mit Teil-Scope → per-Karten-Saves, Status-Karten sichtbar read-only.
- [x] **Schedule-TaskEditor**: unzuverlässige `w-*`-Overrides (dokumentierte Falle) zerlegten das Layout → Wrapper-Breiten + fester ✕-Slot, eine Silhouette für alle Task-Typen; Editor-Footer mit Cancel.
- [x] **Mobile-Konsole**: Terminal + Prompt passen jetzt auf einen 390×844-Screen (Icon-Power-Buttons, 1-Zeilen-Stats, 34dvh-Terminal, Tab-Strip-Edge-Fade).
- [x] **Native Checkboxen** neben Glass-Controls → eigene `Checkbox`-Primitive (Files-Auswahl, Restore/Delete-Dialoge, API-Keys).
- [x] **Login-Copy**: „43 games built in" → „70+" (Panel liefert 73).
- [x] **Palette**: Tastatur-Reihenfolge ≠ visuelle Reihenfolge (Score- vs. Gruppen-Sortierung) → deckungsgleich.

**4. Re-Audit (frische Augen, 54 Screenshots):** 39/40 VERIFIED-FIXED, 1 partiell, **null Regressionen** (10 gezielte Proben inkl. Deutsch-Roundtrip, Doppel-Klick-Schutz, Save-Scopes per PATCH-Body). 7 neue P2s gefunden und sofort gefixt — darunter ein echter Bug: das Tint-Regex ordnete `restart` als „start" (grün statt bernstein) und `disable` als „enable" ein; dazu lokalisierte Datumsformate (deutsche UI = deutsches Format), Cancel-Buttons in drei destruktiven Dialogen, humanisierte Schedule-Run-Logs.

**5. Video-Review-Schleife:** Der Reviewer stufte die Tastatur-Markierung der Palette im komprimierten Video als unsichtbar ein — Laufzeit-Sonde bewies: Logik korrekt, Stil zu subtil. Fix: Akzent-Indikator-Balken + stärkerer Tint; Neuaufnahme bestätigt einwandfrei.

**Mikro-Typo & System:** eine `.microlabel`-Spezifikation statt drei konkurrierender, Radius-Skala ohne `rounded-md`, ein Gutter-Rhythmus pro Seite, ruhige Disabled-Primaries, zentrierter Mobile-Topbar-Titel, kein ⌘K-Hinweis im Touch-Drawer, sm-Header-Saves als Konvention.

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, **73/73 Blueprints** valide.

### Runde 16 — 2026-08-16 (First-Run-Erlebnis + Skeleton-Loading)

Weiter im Endlos-Loop: Die Zustände, die bisher **kein** Audit gesehen hat (alle liefen mit Demo-Daten) — der allererste Eindruck eines frischen Self-Hosters und die Lade-Momente.

- [x] **Zero-State-Audit an frischer Wegwerf-Instanz** (`BETWEEN_DATA`-Zweitinstanz, Seed-Admin): Dashboard mit 0 Servern war ein „totes Cockpit" (grauer Icon + „No servers yet."), Servers-Seite eine nackte Zeile ohne Wegweiser. Blueprints/Catalog/Audit/Settings bestehen auch leer.
- [x] **First-Run-Dashboard**: einladendes Glass-Panel (Rocket-Chip, Pitch-Zeile, Primary „Erstelle deinen ersten Server" + Secondary „Spielebibliothek durchstöbern") statt der leeren Server-Karte; Host-Metriken bleiben live.
- [x] **Servers-Empty-State**: gleiche Einladung über die `EmptyState`-Primitive (neuer optionaler `body`-Prop, alle Alt-Aufrufer rendern unverändert); der „keine Treffer"-Filterpfad bleibt intakt.
- [x] **Skeleton-System**: `Skeleton`-Primitive + `.skeleton`-Shimmer (transform-only, unter `prefers-reduced-motion` statisch — per Computed-Style bewiesen). Inhaltsförmige Skeletons ersetzen die Spinner auf Dashboard (Hero + 4 Metrik-Karten + Listen), Servers (2 Karten) und Server-Detail (Hero + Tab-Pills + Stats + Konsole). **Layout-Sprung gemessen: 0–2 px** zwischen Skeleton und Inhalt.
- [x] WS-Reconnect-Banner geprüft und dokumentiert (bestehende Glass-Toasts, unverändert gut).

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber; Wegwerf-Instanz nach dem Test rückstandsfrei entfernt.

### Runde 17 — 2026-08-16 (Performance, Installierbarkeit, Power-User)

Loop läuft weiter (2 parallele Fable-5-Max-Wellen):

- [x] **Route-Level-Code-Splitting**: Hauptbundle **508 → 367 kB** raw (143 → 112 kB gzip, −28 %); ServerDetail (83 kB), Blueprints, Catalog, Create, Admin-Seiten, Account/Appearance als Lazy-Chunks mit Glass-Fallbacks; Login/Dashboard/Servers bewusst eager (kein Doppel-Skeleton nach Login). Chunk-Ladefehler enden nicht im weißen Bildschirm, sondern in einer Retry-Karte (live bewiesen durch Blockieren der Chunk-URL). Deep-Links, Back/Forward und die Seiten-Transition bleiben intakt.
- [x] **PWA-Installierbarkeit**: Fund — `public/` existierte gar nicht, das referenzierte Favicon war ein 404. Jetzt: Marken-Icon als SVG (Gradient-Kachel mit geometrischem „B", kein Font-Risiko), per Headless-Chrome gerasterte PNGs (192/512/512-maskable/180 apple-touch), `manifest.webmanifest` (standalone, Theme-Farben); `Page.getAppManifest` → **errors: []** auf dem Prod-Server.
- [x] **Shortcuts-Overlay**: „?" öffnet eine Glass-Übersicht aller ECHTEN Shortcuts (aus dem Code enumeriert, nichts erfunden) — mit Input-Guard (Tippen von „?" in Eingabefeldern öffnet nichts, bewiesen), Hilfe-Button in Rail + Drawer, mobil als Bottom-Sheet.
- [x] **Skip-to-Content-Link** (A11y): erstes fokussierbares Element, als Glass-Pill sichtbar bei Fokus; Tab → Enter springt in `main` (per activeElement-Kette bewiesen).
- [x] **Konsolen-Suche**: „/" fokussiert, Substring-Filter über den Scrollback mit Live-Trefferzähler („6 / 801 lines"), neue Zeilen erscheinen live im Filter; `useDeferredValue` statt Timer-Debounce; ungefilterte Auto-Scroll-Semantik byte-identisch.

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber.

### Runde 18 — 2026-08-16 (QA-Runde über Runde 17 + Guard-Nachzug)

Frische Review-Augen über den Runde-17-Diff (Fable 5 Max Thinking, Fix-Befugnis):

- [x] **P1: Das „reparierte" Favicon war in Wirklichkeit kaputt** — ein ungültiges UTF-8-Byte (0x92, Mojibake) im SVG-Kommentar → fataler XML-Encoding-Fehler, Chrome zeigte gar kein Icon (HTTP 200, Decode-Fehler). Gefixt; Tab zeigt jetzt die Gradient-„B"-Kachel.
- [x] **P1: Palette ohne Dialog-Semantik** — `role="dialog"` fehlte, wodurch die neuen „?"/„/"-Guards durchsickerten (Overlay konnte sich ÜBER die offene Palette legen); zudem schloss Escape die Palette nicht, wenn der Fokus außerhalb lag (vorbestehend). Beides gefixt (aria-modal, Labels, Window-Level-Escape).
- [x] **Ctrl+K-Guard**: Palette öffnete sich über offenen Modals und konnte per Navigation den Dirty-Discard umgehen — geschlossen (gemeinsamer `hasOpenDialog()`-Helper mit dem „?"-Guard; Toggle-Verhalten bleibt).
- [x] Chunk-Fehlerkarte von Stub („Error"/„Retry") zu erklärender Karte (en+de), Konsolen-Suche mit aria-label.
- [x] **Messwert**: Suspense-Fallback erscheint beim Erstbesuch einer Lazy-Route konstant ~300 ms (Reacts eingebauter Anti-Flicker-Throttle), bei Folgebesuchen gar nicht — bewusst so belassen.
- Gemeldet, bewusst nicht gebaut: aria-live auf dem Match-Zähler (würde bei gesprächigen Servern Screenreader fluten — bräuchte entkoppelte Architektur).

**Demo-Video** (Video-Review-bestätigt): „?"-Overlay → Konsolen-Suche mit Zähler → Ctrl+K prallt am offenen Modal ab → Palette → Lazy-Audit-Log.

**Tests/Qualität:** **307 Tests** (287 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber.

### Runde 19 — 2026-08-16 (Metrik-Historie: Charts überleben Reloads)

- [x] **Problem**: Alle Sparklines (Host-CPU/-RAM, Server-CPU/-RAM) bauten sich nur aus Live-WS-Samples auf — jeder Reload = leere Charts.
- [x] **Backend**: wiederverwendbarer `RingBuffer<T>` (O(1)-Push, zero-dep) für Host-Ring (720 Samples ≈ 1 h) und Instanz-Ring (360 ≈ 15 min; überlebt Game-Server-Restarts, stirbt mit Delete); `?limit=N` auf beiden bestehenden History-Endpunkten (bewusst KEINE neuen Endpunkte — `GET /api/system/metrics` und `GET /api/servers/:id/resources` existierten mit exakt den geforderten Permission-Gates; ehrlich gemeldet statt dupliziert).
- [x] **Frontend**: ConsoleTab seedet die Stat-Karten einmalig aus `/resources?limit=60` (ts-Dedupe an der Naht, Offline-Guard gegen wiederauferstehende Stale-Samples), Dashboard merged Seed + Live-Race sauber.
- [x] **Beweis**: Hard-Reload per CDP, Screenshot nach **1,8 s** — sichtbare Linien sind physikalisch nur per Seeding möglich (Live-Akkumulation bräuchte ≥10 s für zwei Punkte).
- [x] **+16 Tests** (RingBuffer-Unit + Integrations-Suite: Shapes, `limit`-Trim, Retention über Stop, 401/403-Gates).

**Tests/Qualität:** **323 Tests** (303 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

### Runde 20 — 2026-08-16 (Drag-&-Drop-Upload im Datei-Manager)

- [x] **Glass-Dropzone**: Dateien irgendwo über den Files-Tab ziehen → `.glass-strong`-Overlay mit gestricheltem Akzent-Rahmen und Zielpfad („Dateien loslassen, um sie nach /… hochzuladen"); Dragenter-Counter gegen das klassische Child-Flicker-Problem; ohne `server.files.write` werden die Handler gar nicht erst montiert (Negativ-Test mit eigens angelegtem Read-Only-Subuser bewiesen, danach aufgeräumt).
- [x] **Multi-File-Queue**: Parallelität 2 mit Same-Path-Guard (kein interleaved Write auf dieselbe Datei), Fortschritts-Leiste pro Datei, Fehler bleiben bis zum Dismiss stehen, Erfolgs-Batches schließen sich selbst; ein Listing-Refresh pro Batch (navigationssicher).
- [x] **Ordner-Drops** werden unterstützt (nicht abgelehnt): `webkitGetAsEntry`-Traversierung (mit Chrome-100er-Batch-Schleife), verschachtelte Pfade laufen durch die bestehende `safeJoin`-Upload-Route — kein Backend-Change nötig.
- [x] **Beweis**: 4×3-MiB-Drop mit gedrosseltem Upload (Concurrency 2 sichtbar), SHA-256-Roundtrip aller Dateien, Ordner-Drop mit verschachtelten Pfaden, Button-Pfad über dieselbe Queue; alle Testdateien und der Test-User restlos entfernt.

**Tests/Qualität:** **323 Tests** (303 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber.

### Runde 21 — 2026-08-16 (Privatsphäre, Sortierung, Export — 3 parallele Wellen)

- [x] **Selbst-gehostete Fonts**: Google-Fonts-Links entfernt — Inter + JetBrains Mono als Variable-Fonts lokal (176 kB gesamt, latin + latin-ext per unicode-range). Netzwerk-Beweis: **null externe Requests** über Dashboard/Konsole/Deutsch-UI — wichtig für DSGVO und Air-Gap-/LAN-Betrieb. Umlaute per Width-Probe verifiziert.
- [x] **Server-Sortierung**: SegmentedControl (Status/Name/Spieler) mit sinnvollem Status-Ranking (laufend → startend → … → offline), `localeCompare` mit numeric (Server 2 < Server 10), localStorage-persistiert; stabile Keys → kein Stagger-Replay beim Umsortieren (Node-Identität bewiesen).
- [x] **Adresse-kopieren-Button** im Server-Hero (Check-Feedback statt Toast, Clipboard-API + Fallback, per CDP-Clipboard-Read bewiesen).
- [x] **Audit-CSV-Export**: aktuell geladene + gefilterte Zeilen, RFC-4180-Escaping mit UTF-8-BOM (Excel-Umlaute), ISO-Timestamps, raw + humanisierte Action-Spalte; Byte-Level-Beweis inkl. `"Nächtlicher ""Restart"", täglich"`-Roundtrip.
- [x] **Konsolen-Zeitstempel-Toggle** (persistiert, wirkt sofort auf bestehende Zeilen, Phones bleiben clean).

**Tests/Qualität:** **323 Tests** (303 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber.

### Runde 22 — 2026-08-16 (Backup-Retention)

- [x] **Pro-Server-Policy „behalte die letzten N ungesperrten Backups"**: `null` erbt den Panel-Default, `0` = unbegrenzt, gesperrte Backups zählen nie und werden nie automatisch gelöscht. EIN Choke-Point in `BackupService.create()` deckt manuelle, Schedule- und Pre-Restore-Backups ab; Prune-Fehler können die Backup-Erstellung nie scheitern lassen. Neue Audit-Aktion `backup.pruned` (Akteur `system`), effektive Retention in der API, Settings-Input + BackupsTab-Hinweis.
- [x] **Zwei Sicherheits-Funde nebenbei**: Backups in derselben Sekunde teilten sich einen Dateinamen (Cross-Delete-Risiko) → `-2`-Suffix; das Sicherheits-Backup eines Restores konnte das wiederherzustellende Backup selbst prunen → `protectId`.
- [x] **+14 Tests → 337**; live auf dem Panel bewiesen (Prune bei drittem Backup, Locked überlebt, 400-Validierung), restlos aufgeräumt.

### Runde 23 — 2026-08-16 (Tablet-Band 768–1023 px)

- [x] Erstes Audit der nie geprüften Breiten (768/900/1023/1024): Konsolen-Stats waren aufgeblähte 2×2-Boxen (353–481 px pro Zelle), Dashboard einspaltig mit Activity unterm Fold, Toasts 736-px-Streifen. Fixes rein per `md:`-Band: 4-up-Stat-Strips (beseitigt auch den störenden 1023↔1024-Dichtesprung), 2:1-Dashboard-Split ab md, rechtsbündige md-Toasts, breiterer Drawer/Dock; Skeletons gespiegelt. **0 px Overflow auf allen sechs Breiten, Phone/Desktop pixel-regressionfrei.**

### Runde 24 — 2026-08-16 (Generischer Webhook-Notifier)

- [x] **JSON-Webhook zusätzlich zu Discord** (n8n/ntfy/eigene Skripte): stabiler Payload-Vertrag (`event`, ISO-`timestamp`, `panel`, `server`-Kontext, `data` mit title/message + strukturierten Extras), eigene Event-Toggles (crash/power/backup), 10-s-Timeout + Shutdown-Abort über denselben Stop-Pfad wie Discord, Queue-Cap 20, kein Retry (Parität).
- [x] **SSRF-Haltung bewusst dokumentiert**: Shape-only-Validierung (http/https, Längen-Cap) — private Hosts sind ERLAUBT, denn LAN-Receiver sind der Sinn eines Self-Hosted-Panels; Discord bleibt regex-gepinnt.
- [x] `POST /api/settings/webhook-test` + „Test senden"-Button mit Inline-Ergebnis; **+12 Tests → 349** (inkl. echtem Crash-Event über das demo-echo-`crash`-Kommando und Hung-Receiver-Timeout); live mit lokalem Receiver bewiesen.

**Tests/Qualität:** **349 Tests** (329 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

### Runde 25 — 2026-08-16 (QA über Runden 21–24 + Nachzieh-Fixes)

- [x] **P1 Sicherheit: CSV-Formel-Injektion** im Audit-Export neutralisiert — von Subusern beeinflussbare Strings (z. B. Datei `=SUM(A1:B9).txt`) wurden in Excel/LibreOffice zu lebenden Formeln; jetzt Apostroph-Prefix für führende `=`/`+`/`-`/`@`/Tab/CR (im echten Download byte-genau verifiziert).
- [x] **A11y app-weit**: `Field` verdrahtet jetzt automatisch `htmlFor` + `aria-describedby` (jedes Einzel-Kind-Feld der App profitiert); `SegmentedControl` nimmt `aria-label` an (die Sortierung ist jetzt benannt).
- [x] **Deutsch-Politur** (Sie/du-Mischung im Retention-Hinweis, falsches Genus im Webhook-Hinweis) + Regressionstest für den `protectId`-Restore-Pfad.
- [x] **Nachzieh-Fixes aus den Reports**: Schedule-Backups feuern jetzt Benachrichtigungen (Schedule-Name im Text + additives `data.schedule`-Feld, `system`-Konvention statt Fake-Username; deterministisch über die Run-Now-Route getestet); `zipDirectory` räumt bei Mid-Write-Fehlern sein Teilarchiv auf (nur selbst erzeugte Dateien, per erzwungenem Mid-Loop-Fehler getestet).
- Gemeldet/bewusst belassen: Retention über `server.config` setzbar (konsistent mit dem Rechtemodell — Prune feuert nur bei Create, das `server.backups` braucht), Clamp-Asymmetrie Panel-Default (1–100) vs. pro Server (0 = unbegrenzt) ist Absicht.

**Tests/Qualität:** **352 Tests** (332 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

### Runde 26 — 2026-08-16 (MULTI-NODE: Server auf mehreren Maschinen — das AMP-„Spires"-Feature)

Dein großer Auftrag (AMP nachbauen und besser): Das Flaggschiff zuerst — echtes Multi-Node.

**Backend (Welle 26a, +39 Tests → 391):**

- [x] **Agent-Modus**: derselbe Code als headless Node via `BETWEEN_MODE=node` + `BETWEEN_NODE_TOKEN` (min. 16 Zeichen, constant-time sha256+timingSafeEqual, nur als Bearer-Header — nie in URLs/Logs, nie serialisiert). Kein Web-UI/keine Benutzer auf dem Agent; Rechte prüft IMMER das Panel (inkl. Re-Check pro WS-Nachricht).
- [x] **NodeService** (Registry + Health-Poll + Reconcile mit owned Timern und Stop-Pfad), **ServerGateway** (chirurgischer Dispatch in den Routen: Remote → Proxy mit 10-s-Timeouts, Agent-4xx wörtlich durchgereicht, 502 bei Offline), **NodeStreamBridge** (EINE gemultiplexte WS pro Node, lazy connect, Backoff, Anti-Spoofing-Guard, Frame-Caps) — Konsole/Stats erreichen das Browser-Frontend über identische Kanalnamen, null Frontend-Änderungen nötig.
- [x] Remote-Create bettet das komplette Blueprint-JSON ein (Custom-Blueprints laufen auf Nodes), Datei-Up-/Downloads werden gestreamt (4-GiB-Cap beidseitig), Node-Ausfall degradiert sauber (`node-offline`-Status + klare Fehler). Zero-Node-Setups byte-identisch (alle Alt-Tests unverändert grün).

**Frontend (Welle 26b):**

- [x] **Nodes-Seite** im AMP-Spires-Stil (Glass-Maschinen-Karten: Online-Puls, CPU/RAM/Disk live, Latenz, Version, Server-Zahl; „This panel"-Pseudo-Karte mit Local-Badge), **Add-Node-Dialog** mit generiertem Token + kopierbarem Agent-Startbefehl + Auto-Test, **Node-Picker** im Create-Wizard (offline deaktiviert), Node-Badges auf Karten/Hero, `node-offline`-StatusPill, Host-Strip im Dashboard. Pro-Tab-Politik für Remote-Server (Konsole/Files/Backups/Users/Activity transparent; Settings-Hinweis; Shell/Mods/Config/Schedules ausgeblendet). 41 i18n-Keys ×2.

**E2E-Beweis (echter zweiter Agent in dieser VM, tmux `node-agent`, Port 8485):** Node per UI hinzugefügt (echte Health-Daten, 3 ms Latenz), „Remote Demo" per Wizard AUF dem Node erstellt (Port-Kollision 27777 als erwartetes Same-VM-Phänomen erkannt → 27790), Install-Stream + `say hello from remote` durch die Bridge, Node-Kill → Offline-Degradation binnen ~15 s → Recovery nach Neustart, Löschung über die UI. **Demo-Video** (Video-Review-bestätigt) + `docs/NODES.md` (Konzept, Sicherheitsmodell, Betrieb).

**Tests/Qualität:** **391 Tests** (371 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

### Runde 27 — 2026-08-16 (Datei-Manager auf AMP-Niveau)

- [x] **Rename / Copy / Move** (Datei UND Ordner, rekursiv budgetiert, Kollisionen per Auto-Suffix „ (2)"), **Archiv aus Auswahl** (Einträge parent-relativ — das alte Root-relative Verhalten war ein stiller Fehler), **Extract** für zip + tar/tar.gz — mit **Zip-Slip-Schutz, Symlink-Skip und Bomben-Budgets**, per handgebauten Angriffs-Archiven getestet (`../../../evil-escape.txt` landet nachweislich nirgendwo; 4-GiB-Lügen-Header → 400, Zielordner leer).
- [x] **Detail-Seitenpanel** im AMP-Stil (≥lg Grid-Split, mobil Bottom-Sheet): Metadaten, Pfad, Aktionen und **Bildvorschau** (objectURL über den authentifizierten Download, 5-MiB-Cap, SVG strikt via `<img>`); funktioniert auch für Remote-Node-Server (gestreamter Proxy, Hash-identischer Roundtrip).
- [x] Remote-Server: neue Mutationen sauber ausgeblendet (v1 lokal-only per Gateway-Guard). +10 Tests.

### Runde 28 — 2026-08-16 (Event-Trigger + Template-Variablen im Scheduler)

- [x] **Trigger-Union**: Cron (unverändert) ODER Event — `server.running`/`offline`/`crashed` aus dem Status-Hook (grundsolide) + `player.joined`/`left` per Poll-Diffing mit **zwei ehrlichen Erkennungsstufen** (Namens-Diff nur bei vollständiger Namensliste, sonst Count-Delta mit leerem `{user}`; Spiele ohne Query-Block: Optionen ausgegraut mit Hinweis). 30-s-Debounce pro Schedule (Crash-Loop ⇒ ein Lauf, nicht fünfzig).
- [x] **Template-Variablen** zur Laufzeit: `{server}` `{state}` `{players}` `{maxPlayers}` `{user}` `{time}` `{node}`, `{{`-Escape, unbekannte Platzhalter bleiben stehen; injektionssicher (Single-Pass, `Object.hasOwn` gegen `{__proto__}`, Callback-Replace gegen `$&`) — alles unit-getestet.
- [x] Editor: „When"-SegmentedControl (Cron | Event), `{ }`-Variablen-Panel mit Cursor-Insert, Event-Badges auf Zeilen, Run-Log mit Quelle (`cron`/`manual`/`event:<name>`); Alt-Schedules laufen unverändert. Live bewiesen: `server.running`-Trigger rendert `say Server Lobby One is running with 0 players` in die Konsole. +16 Tests (davon 1 gemeinsamer Integrationslauf mit Crash-Recovery-Kette).

**Tests/Qualität:** **416 Tests** (396 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

### Runde 29 — 2026-08-16 (Steam-/SteamCMD-Logins)

- [x] **Sicherheits-Design zuerst**: Passwort + Guard-Code existieren nur innerhalb EINES Requests — nie auf argv (Prozesslisten!), nie persistiert, nie geloggt (`scrubSecrets` über alle Ausgaben, per Grep über Datendir + Steam-Home bewiesen: 0 Treffer). Interaktiver stdin-Flow: `password:`-Prompt → stdin, `Steam Guard code:` → Zwei-Schritt im UI; nach Erfolg cached SteamCMD die Session (Sentry) — genau dafür ist der Flow da.
- [x] **Echter Bug durch Live-Test gefunden**: Das reale SteamCMD ummantelt Prompts mit ANSI-SGR-Codes (`password: \x1b[0m`) und meldet `ERROR (…)` statt `FAILED (…)` — der Parser strippt jetzt ANSI und akzeptiert beide Formen; `fake-steamcmd.mjs` emittiert die byte-genauen echten Sequenzen.
- [x] Session-Probe mit 5-min-TTL (serialisiert — zwei SteamCMDs auf einem Home korrumpieren sich), deterministischer Logout (config.vdf + ssfn-Dateien), Admin-API + Steam-Karte in den Panel-Einstellungen (ehrliche Negativ-Demo gegen das echte Binary: „Invalid Password"-Zustand).
- [x] **Blueprint-Ehrlichkeit**: Alle 50 SteamCMD-Blueprints installieren nachweislich anonym → KEINES bekommt `requiresLogin` (Fähigkeit voll verdrahtet: Blueprint-Flag, Server-Override `useSteamLogin`, Fail-Fast mit handlungsleitender Meldung). Multi-Node: Sessions sind pro Maschine — v1 panel-lokal, Remote-Installs mit Login-Pflicht scheitern mit klarer Meldung (in docs/NODES.md dokumentiert).
- [x] **+23 Tests → 439** (Fake-SteamCMD-Harness, Guard-Zwei-Schritt, No-Leak-Greps, Override, Logout, Audit-Assertions).

**Tests/Qualität:** **439 Tests** (419 bestanden, 20 Docker-Skips), Typecheck/Lint/Build sauber, 73/73 Blueprints valide.

_Log wird laufend ergänzt…_
