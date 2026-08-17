# SoooDreamy ARENA 🏟

Ein reproduzierbares Multi-Paar-Live-Testsystem: Die Arena spielt die echten
App-Flows **über HTTP + WebSocket** gegen einen echten Serverprozess — genau
das, was reale Paare tun — mit vielen Paaren, mehreren Geräten pro Mitglied,
Reconnect-Stürmen und einem harten Server-Crash mitten im Lauf. Während und
nach dem Lauf prüft sie die Kern-Invarianten des Protokolls. Kein Mock, kein
In-Process-Server: der Server läuft als eigener Prozess in tmux und wird per
SIGKILL gecrasht wie bei einem Stromausfall.

## Schnellstart

```bash
cd SoooDreamy/tools/arena
npm install          # einzige Dependency: ws
node arena.mjs run --couples 6 --devices 2 --minutes 3 --seed 42
```

Die Arena startet ihren **eigenen** Server (tmux-Session `arena-server`,
Port 4399, frisches `DATA_DIR=/tmp/arena-data`) — der normale Dev-Server auf
4321 bleibt unberührt. Exit-Code 0 = keine verletzte Invariante; der volle
Report (jede Verletzung mit Kontext) landet als JSON in `/tmp/arena-reports/`.

### CLI-Flags

| Flag | Default | Bedeutung |
|---|---|---|
| `--couples N` | 6 | Anzahl Paare (1–24) |
| `--devices D` | 2 | Geräte-Sessions pro Mitglied (1–4, via Device-Link-Flow) |
| `--minutes M` | 3 | Dauer des Szenario-Fensters (Bruchteile erlaubt) |
| `--seed S` | 42 | Seed — gleicher Seed ⇒ gleicher Szenario-Fahrplan |
| `--no-restart` | – | Crash+Restart-Choreografie überspringen |
| `--port` / `--session` / `--data-dir` | 4399 / `arena-server` / `/tmp/arena-data` | für parallele Arena-Instanzen |
| `--label L` | generiert | Report-Dateiname |

Zwei Arenen können parallel laufen (verschiedene Ports/Sessions/DATA_DIRs),
z. B. `--port 4398 --session arena-server-b --data-dir /tmp/arena-data-b`.

## Wie die Arena funktioniert

- **Jedes simulierte Gerät ist ein eigener „Haushalt":** HTTP- und
  WS-Verbindungen binden eine eigene Loopback-Quell-IP (`127.7.<paar>.<gerät>`).
  Der Server rate-limitet und deckelt pro Client-IP (`requestKey`) — mit
  eigenen Quell-IPs verhalten sich N Paare von einer Testmaschine wie echter
  Traffic hinter einem Reverse-Proxy, ohne ein Server-Limit anzufassen.
- **Echtes Pairing:** Mitglied A `POST /api/couples`, Mitglied B
  `/api/couples/join`, Zusatzgeräte über `POST /api/sessions/link-code` →
  `POST /api/couples/link`. Jedes Gerät hält seinen eigenen `/ws`-Socket
  (Bearer im Header, wie die App).
- **Seeded Szenario-Treiber pro Paar** (ein sequentieller Loop pro Paar, alle
  Paare parallel): gewichtete Auswahl aus dem Szenario-Katalog unten, bis das
  Zeitfenster endet. Bei ~55 % der Laufzeit wird der Server per **SIGKILL**
  gecrasht (Pane-PID der tmux-Session, nie `pkill`), ~4 s liegen gelassen und
  mit demselben `DATA_DIR` neu gestartet; alle Geräte reconnecten.
- **Zeitpost in Sekunden statt Minuten:** der Arena-Server läuft mit
  `POST_MIN_LEAD_SECONDS=2` (env-gated Testoverride in `server/src/post.js`,
  ohne die Variable byte-identisches Verhalten) und
  `POST_DELIVERY_INTERVAL_SECONDS=1`, sodass echte Zustellungen — auch die
  „wird fällig, während der Server tot ist"-Fälle — im Lauf passieren.

## Szenario-Katalog (`lib/scenarios.mjs`)

| Szenario | Was gespielt wird | Inline-Asserts |
|---|---|---|
| `chat` | Text senden (+ `clientMessageId`-Retry), Partner-Reaktion (+ Op-Id-Retry), Read-Receipt | 201/200 `duplicate:true`, `message`/`message_updated`-Frames auf allen Partner-Geräten |
| `touchEcho` | Touch (+ Retry), Partner-Echo, Zweit-Echo, Echo-auf-Echo, Echo auf eigenen Touch | Echo-Einmaligkeit (`409 echo_taken`), `400` für eigenen Touch, `echo:true`/`echoOf` |
| `pulse` | Pulse (+ Retry), sofortiger zweiter Pulse, `pulses/seen` | 30-s-Cooldown (`429 too_soon` + `retry-after`), `duplicate:true`, `pulse`-Frame nur beim Partner, `pulse_felt`-Receipt |
| `zeitpost` | Touch/Pulse/Note 4–9 s voraus planen (+ Retry), teils canceln; Partner-Sichtbarkeits-Proben | `duplicate:true`; Partner-`GET /api/post/scheduled` leer, Partner-`DELETE` = 404 (Überraschungs-Kontrakt) |
| `dailyPinRace` | Beide Mitglieder antworten GLEICHZEITIG mit divergenten `questionId`s; Verlierer re-antwortet; Edit nach Reveal | genau ein Gewinner, `409 daily_question_mismatch` mit autoritativer Id, konsistente Views, `409 daily_revealed` |
| `game` | Gomoku mit Skript-Sieg: Out-of-Turn-Proben, Spectator-Device (`409 game_lease_held`), explizites Takeover + Weiterspielen vom anderen Gerät, paralleler Doppel-Send mit gleicher `clientMoveId`, später Retry des Final-Moves | `turnMemberId` server-autoritativ (inkl. explizitem `null`), genau ein gespeicherter Move pro `clientMoveId`, `game_lease`-Frames nur an eigene Geräte, Ergebnis server-derived |
| `listsCanvas` | Parallele Listen-Items beider Mitglieder, bewusst-stale `ifRev`, parallele Canvas-Striche mit `generation`, Fremd-Lösch-Probe, seltener Clear | `409 conflict` + `current`, `403` für fremde Striche, `409 stale_generation` nach Clear |
| `reconnect` | Socket trennen, 0,2–0,9 s warten, neu verbinden | `welcome` mit korrekter Identität, Catch-up: neueste Nachricht via REST auffindbar |

## Invarianten (`lib/checks.mjs` + Live-Checks)

- **(a) Cross-Couple-Isolation:** Jede Server-Antwort registriert jede
  Id-förmige Zeichenkette als Eigentum des anfragenden Paares; jeder
  empfangene WS-Frame wird (live + im Post-Run über das komplette Frame-Log)
  gegen die Registry gescannt. Zusätzlich trägt jeder generierte Text einen
  Paar-Marker `⟦A<n>⟧`, der bei fremden Paaren nie auftauchen darf.
- **(b) Echo-Einmaligkeit & Fenster:** live (`echo_taken`-Proben) + Post-Run
  (max. ein `echoOf` pro Original im Journal).
- **(c) Zeitpost exactly-once:** pro geplanter Post genau EIN Artefakt unter
  der stabilen Id (`t_/pl_/pn_<postId>`) — auch wenn die Zustellung durch den
  Crash fällt; gecancelte Posts erzeugen NIE ein Artefakt; der Empfänger sieht
  offene Posts nie (Liste, Cancel-Probe, `post_scheduled`-Fanout-Audit).
- **(d) Daily:** EIN gepinntes `questionId` pro Paar/Tag trotz Race; beide
  Member-Views konsistent; Reveal-Semantik.
- **(e) Spiel:** gespeicherte Move-Liste == geskriptete Sequenz (keine
  Doppel-/Verlust-Moves trotz paralleler Sends), keine doppelten Move-Ids,
  Zugfolge server-autoritativ.
- **(f) Journal-Ordnung:** `createdAt` absteigend, Ties per Id — über das
  ganze Journal jedes Paares.
- **(g) Idempotenz:** jeder wiederholte `clientOperationId`/`clientMessageId`/
  `clientMoveId` muss `duplicate:true` mit dem Original liefern.
- **(h) Keine 5xx, keine unerwarteten WS-Disconnects:** jeder Request landet
  im Ledger; jeder Socket-Close außerhalb geplanter Fenster ist eine
  Verletzung. Die Server-Logs beider Instanzen werden zusätzlich manuell auf
  `uncaughtException`/Fehler gescannt.
- **(i) Persistenz über Crash:** GET-Snapshots (Couple, Messages, Daily,
  Games, Lists, Canvas, Events, Scheduled, Journal, Pulses) vor SIGKILL ==
  nach Restart; einzige legitime Differenz sind Zeitposts, die während der
  Downtime fällig wurden — für die gilt: aus `scheduled` verschwunden UND
  exakt ein Artefakt.

## Interpretation der Ergebnisse

Jede Verletzung wird live auf stderr geloggt und landet strukturiert im
JSON-Report (`/tmp/arena-reports/<label>.json`) mit Code, Severity, Nachricht
und Kontext. Exit-Code: `0` sauber, `1` Verletzungen, `3` Lauf abgebrochen.
Erwartete 4xx (Echo-Proben, Cooldowns, Lease-Refusals, Conflict-Proben) sind
Teil der Szenarien und zählen nicht als Verletzung — nur Abweichungen vom
dokumentierten Kontrakt.

Repro: gleiche Flags + gleicher `--seed` ⇒ gleicher Fahrplan. Echtes
Netz-/Scheduler-Jitter bleibt (deshalb sind die Zeit-Toleranzen der Checks
dokumentiert konservativ).

## Wie CI die Arena später fahren könnte (nur Doku, kein Workflow hier)

- Job-Schritte: `cd SoooDreamy/tools/arena && npm ci && node arena.mjs run
  --couples 4 --devices 2 --minutes 2 --seed 42`. tmux muss installiert sein
  (`apt-get install -y tmux`); ohne `/exec-daemon/tmux.portal.conf` fällt die
  Arena automatisch auf plain `tmux` zurück.
- Exit-Code gated den Job; den JSON-Report als Artefakt hochladen.
- Empfehlung: ein kurzer Smoke (2 Paare, 1 min, `--no-restart`) auf jedem PR,
  der volle Lauf (6–12 Paare inkl. Restart) nightly — der Restart-Teil braucht
  ~15 s extra und ist der wertvollste Teil (exactly-once über Crash).
- Flaky-Schutz: Läufe sind seeded; bei einem Fund denselben Seed erneut fahren
  und den Report diffen.

## Gefundene & gefixte Bugs (Historie)

- **Pulse-Cooldown durch Zeitpost-Zustellung neu gestartet** (gefunden im
  6-Paar-Lauf, Seed 7): Eine zugestellte Zeitpost-Pulse landet mit
  `createdAt = Zustellzeit` und Sender-Id in `couple.pulses`; der
  Live-Cooldown-Check bestrafte den Sender anschließend mit einem
  überraschenden `429 too_soon` (+ irreführendem `retry-after`-Countdown),
  obwohl er nichts gesendet hatte. Fix in `server/src/presence.js` (Cooldown
  zählt nur `viaPost !== true`), Regressionstest in
  `server/test/arena_regressions.test.js`.
