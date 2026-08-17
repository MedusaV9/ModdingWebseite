# MONKEY MONEY — TECH-SPEC (verbindlich)

Konsolidierte, ENTSCHIEDENE Technik-Spezifikation für die Jackbox/Buzz-artige
Quiz-Show-Party-App. Quellen: Ideen-Kataloge 01–20 (`/tmp/monkey-money-ideen/`),
insbesondere 17 (Architektur), 18 (iPad/App Clips), 15 (Analytics), 19
(Onboarding/AI/Controller), 13 (Frage-Typen), 02 (Minispiel-Mechaniken),
07 (Session/Save), 03 (GM-Werkzeuge), 09 (Bühne/Rendering), 20 (Polish),
11 (Cutscenes/Remotion).

Rahmen (fix): Node.js. Hosting-Pfad A = AMP-Server, **NUR HTTP**. Hosting-Pfad
B = PC + Cloudflare-Tunnel (**HTTPS**). iPad/PC-Browser = Bildschirm; iPhones
(11+, hochkant, Safari) joinen per QR/Link. Rollen: Spieler / Bildschirm / GM
(+ implizit Spectator). Reconnect ist der wichtigste Flow. Controller-Support.
Save/Load-Slots. Modular, keine Monolithen. Unsignierte iPad-.ipa via GitHub
Actions (Muster: vorhandene xcodebuild-ohne-Signing-Pipeline auf macos-Runnern).

Leitprinzipien (nicht verhandelbar):

1. **Server = einzige Wahrheit.** Clients sind Renderer von rollen-gefilterten
   Views. Kein Spielzustand nur im Browser.
2. **Ein Build, zwei Transport-Welten.** Identischer Code über `http://`
   (AMP/LAN) und `https://` (Tunnel). Alles Secure-Context-Abhängige läuft
   über die Capability-Schicht `shared/caps.ts` — nie hart vorausgesetzt.
3. **Determinismus.** Zeit (`Clock`) und Zufall (`Rng`) werden injiziert —
   nie `Date.now()`/`Math.random()` in Spiellogik (Repo-Disziplin aus GOOBY).
4. **Null native Node-Module.** AMP-Deploy = `npm ci --omit=dev` + `node
   server/index.js`. Kein node-gyp, keine Prebuild-Lotterie.
5. **Player-Client ultraleicht.** < 200 KB gzipped, eine Ansicht pro Phase,
   überlebt den ganzen Abend ohne Reload.

---

## 1. Stack-Entscheidung

### 1.1 Server-Transport: **Express + socket.io v4** ✅ (nicht rohes `ws`)

| Kriterium | `ws` roh | **socket.io v4** |
|---|---|---|
| Transport-Reconnect (Backoff, Re-Attach) | selbst bauen | eingebaut, plus Connection State Recovery |
| Räume/Broadcast (`io.to(room)`) | selbst bauen | fertig |
| ACKs mit Timeout (`emit(..., ack)`) | selbst bauen | fertig |
| Fallback in zickigen Party-WLANs / hinter Cloudflare | keiner | HTTP-Long-Polling |
| Overhead | minimal | ~10 KB Client, vertretbar |

**Begründung:** Reconnect ist DER kritische Flow; genau die Teile, die man bei
rohem `ws` nachbauen müsste (Backoff, Räume, ACKs), sind die fehleranfälligsten
einer Party-App im Wackel-WLAN. Wichtig: socket.io liefert nur den
**Transport**-Reconnect. Die **fachliche** Wiederherstellung („du bist wieder
Spieler 3 mit 4200 MM") machen wir selbst über Session-Token + Snapshot/seq
(Abschnitt 3). Connection State Recovery ist Bonus für Kurz-Aussetzer, nie die
Grundlage. Express bleibt als HTTP-Schicht (Static aus `client/dist/`,
`/j/:code`, `/healthz`, `/api/qr`, Save/Load-REST für GM) — AMP-erprobt, trivial.

### 1.2 Frontend: **Vite-Build → statische Dateien; Vanilla TypeScript + lit-html** ✅ (kein Buildless, kein React)

- **Vite** (Multi-Page: `screen.html`, `player.html`, `gm.html`, `index.html`
  Landing): Dev-Server mit HMR, `vite build` erzeugt reine statische Dateien
  nach `client/dist/`, die Express ausliefert. **AMP sieht nie einen Build**
  — das Deploy-Artefakt ist fertig gebaut. Damit ist das
  Buildless-Hauptargument („AMP-Einfachheit") erledigt, ohne dessen Nachteile:
  Buildless hieße kein TypeScript im Browser, kein Bundling (viele Requests im
  Party-WLAN), Import-Maps auf älteren iOS-Versionen wackelig. **Abgelehnt.**
- **lit-html** (~7 KB) statt React/Vue: drei Clients sind reine
  `render(view) → DOM`-Renderer; kein VDOM, kein Framework-Lock-in, kein
  Hydration-Thema. Player-Client bewusst spartanisch (CSS-Transitions statt
  JS-Animationen, `100dvh`, `viewport-fit=cover`).
- **Server-Code:** TypeScript, Dev via `tsx`, Release als esbuild-Bundle
  (eine JS-Datei pro Entry) — auf dem AMP-Server läuft nur fertiges JS.
- **Validierung:** Zod für Protokoll- UND Content-Schemas (eine Quelle,
  beidseitig importierbar).

### 1.3 Storage: **JSON-Dateien mit Atomic-Write + JSONL-Event-Log** ✅ (kein better-sqlite3 in v1)

- better-sqlite3 ist ein natives Modul: Die Node-Version des
  AMP-App-Runners ist nicht garantiert prebuild-kompatibel → schlimmstenfalls
  node-gyp auf dem Gameserver. Genau das Risiko, das ein Party-Abend nicht
  braucht. **Abgelehnt für v1.**
- Datenvolumen ist winzig (Saves = wenige KB, Packs read-only, Event-Log =
  append-only Text). Ein Prozess, keine Concurrency → Dateien reichen.
- **Analytics-Queries** (Katalog 15) laufen NICHT ad-hoc über eine DB, sondern
  über **materialisierte Aggregate** (`player_stats.json`,
  `question_stats.json`), die nach jedem Match inkrementell aktualisiert und
  jederzeit per Replay aus dem JSONL-Event-Log komplett neu gebaut werden
  können (`tools/rebuild-stats`). Neue Stats sind damit rückwirkend einführbar.
- Schreiben IMMER `write tmp → fsync → rename` (atomar); jede Datei trägt
  `schemaVersion` + Migrationsfunktion beim Laden. Pfad via `DATA_DIR`-Env.
- Abstraktion: `Storage`-Interface (get/put/list/append) in
  `server/persistence/`. **Designierter Upgrade-Pfad:** `node:sqlite`
  (eingebaut ab Node ≥ 22.5, kein natives npm-Modul) als zweiter Adapter,
  falls Event-Log-Volumen je echte Queries verlangt. Niemals node-gyp.

### 1.4 3D/Rendering: **DOM/CSS-2.5D-Bühne + EIN Canvas-Partikel-Overlay; Three.js NICHT im Kern** ✅

Entscheidung pro Screen-Typ (aus Katalog 09, A-22 — bestätigt gegen 17):

| Client | Rendering | Begründung |
|---|---|---|
| **Player (iPhone)** | 100 % DOM/CSS | < 200-KB-Budget, Akku, Zuverlässigkeit; niemals WebGL auf dem Controller |
| **GM (iPad/Laptop)** | 100 % DOM/CSS | Cockpit ist Formular + Listen; Three.js hätte null Nutzen |
| **Screen (iPad/PC)** | DOM/CSS-2.5D (Perspective-Transforms, virtuelle Kamerafahrten) + genau **ein** transparentes Vollbild-`<canvas>` (2D) für Partikel (Money-Regen, Konfetti, max. 120 Sprites, Object-Pooling) | Flexbox macht Podien/Text gratis; Compositor-Transforms laufen auf iPad-Safari mit 120 Hz; WebGL-Context-Loss-Risiko bei Tab-Wechsel entfällt; DOM ist snapshot-testbar |
| Three.js | **v1: NEIN.** Später höchstens als lazy-geladene Insel für 1–2 Signatur-Momente (3D-Tresor im Finale), mit CSS-Fallback | ~170 KB gzipped für 2 Momente lohnt erst nach stabilem Kern (P2/COULD) |

Performance-Budget Screen: nur `transform`/`opacity` animieren,
Auto-Degradation bei < 45 fps (3 Stufen), `prefers-reduced-motion` erzwingt
Stufe 3, Asset-Budget ≤ 2,5 MB WebP mit Preload in der Lobby.

### 1.5 Stack-Summe

```
Node ≥ 20 (Ziel 22) · Express (HTTP/Static/REST) · socket.io v4 (Realtime)
TypeScript überall · lit-html (alle 3 Clients) · Vite (Dev + Build, MPA)
Zod (Protokoll + Content) · JSON/JSONL-Storage atomar (DATA_DIR)
qrcode (npm, serverseitig) · Vitest (Unit) · Playwright (E2E) · Remotion (nur Build-Zeit)
Keine nativen Module. Ein Build für HTTP- und HTTPS-Pfad.
```

---

## 2. Repo-/Modul-Layout

```
monkey-money/
├─ package.json                  # npm workspaces: server, client, shared, remotion, tools
├─ shared/                       # Von Server UND Client importiert — NUR Typen, Zod-Schemas, pure Helfer
│  ├─ protocol.ts                #   Nachrichten-Katalog als diskriminierte Unions (Abschnitt 3)
│  ├─ views.ts                   #   Rollen-gefilterte View-Typen (ScreenView, PlayerView, GmView, SpectatorView)
│  ├─ caps.ts                    #   Capability-Detection (isSecureContext, wakeLock, gamepad, clipboard, vibrate, tts)
│  ├─ ids.ts / money.ts / time.ts#   Branded Types, MM-Integer-Arithmetik, Clock-Interface
│  └─ minigames/<id>.meta.ts     #   Pro Minigame: Meta + View-/Action-Typen (beidseitig gebraucht)
├─ server/
│  ├─ core/                      # Wiring: Express-App, socket.io-Setup, Env-Config (PORT, DATA_DIR, MAX_ROOMS), /healthz, Static-Serving
│  ├─ rooms/                     # Raum-Codes (4 Buchstaben, kollisionsfrei), Raum-Lifecycle + TTL, Sessions (Token↔Slot), Grace-Period, Claim-Flow, Sync (Snapshot/Event/seq, Ping/RTT), GM-PIN
│  ├─ engine/                    # Pure Zustandsmaschine: Show-Phasen (Lobby→Intro→Runden→Finale→Ende), Reducer (state, action, ctx{clock,rng})→state', Scoring/Streaks/Ökonomie, viewFor(role), GM-Command-Handler, Save-Serialisierung
│  ├─ minigames/                 # 1 Ordner = 1 Server-Plugin nach MinigamePlugin-Interface (unten); _api/ enthält Interface + Contract-Test-Harness
│  │  ├─ _api/
│  │  ├─ vier-lianen/            #   Referenz 1: 4er-Choice (Simultan-Eingabe)
│  │  ├─ bananen-buzzer/         #   Referenz 2: Buzzer-Runde (Latenz-Fairness)
│  │  ├─ bananen-waage/          #   Referenz 3: Schätz-Slider
│  │  └─ pixel-dschungel/        #   Referenz 4: Stufen-Enthüllung (Screen-zentriert) — Interface erst NACH diesen vieren einfrieren
│  ├─ content-loader/            # Lädt/validiert Fragen-Packs (Zod), Fragen-Auswahl (Kategorie/Schwierigkeit/Region/Cooldown/No-Repeat), Lizenz-Manifest
│  ├─ analytics/                 # Append-only Event-Log (JSONL), inkrementelle Aggregate, Replay-Rebuild, Fragen-Gesundheit (Flags, Drift, Abnutzung)
│  └─ persistence/               # Storage-Interface + JSON-Atomic-Implementierung, Save-Slots, Profile, schemaVersion-Migrationen
├─ client/
│  ├─ screen/                    # Bühne: Lobby+QR, 2.5D-Studio, Partikel-Canvas, Scoreboard, Audio-Ausgabe, Couch-Player-Input (v2)
│  ├─ player/                    # iPhone hochkant: Join, Buzzer, Antwort-Formulare (5 Input-Primitive: Buttons/Slider/Drag-Liste/Halten/Tap-Frenzy), Warte-Screen
│  ├─ gm/                        # Regiepult: 3-Zonen-Cockpit, Spickzettel, Fragen-Regal, Aktions-Log+Undo, Save/Load-UI, Soundboard
│  └─ shared/                    # Client-only Gemeingut: socket-Wrapper (relative URL!), Design-System (Farbe+Form+Buchstabe), Audio-Unlock, NoSleep, haptics(), Minigame-Renderer-Registry (Vite-Glob → Code-Splitting pro Minigame)
│     └─ minigames/<id>/         #   Pro Minigame: screen.ts, player.ts, gm.ts, explain.ts (JIT-Erklärkarte)
├─ content/
│  ├─ schema.md                  # Dokumentation des Pack-Formats (Quelle der Wahrheit: shared/… Zod)
│  └─ packs/<packId>/pack.json   # Fragen-Packs inkl. Lizenz-Manifest (Abschnitt 5.4); Medien daneben (bilder/, audio/)
├─ assets/                       # Quell-Assets der Clients: ~30–35 generierte Bitmaps (WebP), SVG/CSS-Bausteine, Sounds, Fonts (lokal — kein CDN im HTTP-LAN!)
├─ tools/                        # pack-validate (CLI, auch CI), bots/ (Bot-Spieler-Framework, Abschnitt 8), rebuild-stats, release-zip, tunnel-Start-Wrapper
├─ docs/                         # DEPLOY-AMP.md, QUICKSTART-PC.md, TUNNEL.md, GUIDED-ACCESS.md, CONTENT-GUIDE.md
├─ remotion/                     # Remotion-Projekt: Trailer + Minigame-Tutorials („HowToCard"-Template) — rendert AUSSCHLIESSLICH in Build/CI, nie zur Laufzeit
├─ ios-wrapper/                  # WKWebView-Wrapper (XcodeGen project.yml + ~3 Swift-Dateien + Info.plist), Abschnitt 6
└─ .github/workflows/            # ci.yml (lint, typecheck, unit, bots, e2e, build), ipa.yml (macos-15, pfadgefiltert), release.yml (Tag → Release-Zip + .ipa)
```

**Abhängigkeitsregeln (hart, via ESLint `no-restricted-imports` zementiert):**
`shared` ← alle · `server/engine` importiert nur `shared` + `minigames/_api` ·
`server/minigames/*` importieren nur `shared` + `_api` · `server/core|rooms`
importieren `engine`, nie umgekehrt · `client/*` importieren nur `shared` +
`client/shared`. Ein Minigame hat exakt drei Heimaten (shared-Meta,
Server-Plugin, Client-Renderer); ein Contract-Test prüft, dass alle drei
existieren.

### 2.1 Minigame-Plugin-Interface (der wichtigste Vertrag)

**Server-Seite** (`server/minigames/_api/plugin.ts`):

```ts
interface MinigamePlugin<S, A extends { type: string }> {
  meta: {
    id: string; name: string;
    minPlayers: number; maxPlayers: number;
    formats: ("buttons"|"slider"|"dragList"|"hold"|"tapFrenzy"|"buzzer"|"text")[];
    contentKind: "quiz"|"estimate"|"sort"|"media"|"none";
    requiresSecureContext?: boolean;  // Mikro/Kipp-Spiele → im HTTP-Pfad ausgeblendet
    needsScreen?: boolean;            // im Screen-los-Modus gefiltert/gespiegelt
    supportsGamepad?: boolean;        // Couch-Player-tauglich (v2)
  };
  // Lifecycle-Hooks — ALLE pure, Clock/Rng NUR aus ctx, State IMMER serialisierbar:
  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): S;
  reduce(state: S, action: PlayerAction<A> | GmAction, ctx: Ctx): S;  // Spieler-Input + GM-Eingriffe
  tick(state: S, ctx: Ctx): S;              // Server-Timer-Fortschritt (Phasen, Enthüllungs-Stufen)
  onDisconnect(state: S, p: PlayerId, ctx: Ctx): S;   // AFK-Regel des Spiels (Default: no-op)
  onReconnect(state: S, p: PlayerId, ctx: Ctx): S;
  viewFor(state: S, role: Role, player?: PlayerId): unknown;  // Geheimnis-Filterung SERVERSEITIG
  isFinished(state: S): boolean;
  scores(state: S): Record<PlayerId, number>;  // Engine bucht aufs MM-Konto
}
```

Minigame-State lebt IM Engine-State → Save/Load, Reconnect und Event-Log
funktionieren automatisch für jedes Plugin, das „pure + serialisierbar"
einhält. Contract-Tests (Abschnitt 8) erzwingen das maschinell.

**Client-Seite** (`client/shared/minigames/<id>/`):

```ts
interface MinigameClientModule {
  id: string;
  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void;   // FxApi = Partikel/Sound/Kamera
  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void;
  renderGm?(view: unknown, host: HTMLElement, gm: GmApi): void;      // Default: generisches Status-Panel
  explainCard: { text: string; animation: TemplateResult };          // JIT-Regelerklärung (Katalog 19/3)
}
```

Registrierung per Vite-Glob-Import → Code-Splitting pro Minigame gratis;
Player lädt nur Renderer der Formate, die das aktive Pack braucht.
**Interface-Einfrieren erst nach den 4 Referenz-Minigames** (Simultan /
Buzzer / Schätzen / Screen-zentrierte Enthüllung).

---

## 3. Realtime-Protokoll

Grundmodell: **Snapshot + Events mit Sequenznummern.** Server hält pro Raum
den kompletten Zustand; jede Änderung läuft durch die Engine und erhöht
`seq`. Clients bekommen rollen-gefilterte Views (`viewFor`) — Filterung
IMMER serverseitig. Erkennt ein Client eine seq-Lücke, fordert er einen
Voll-Snapshot an → Protokoll ist selbstheilend, Reconnect ist Normalfall.
Timer laufen NUR auf dem Server; Clients bekommen `{endsAtServerTime}` +
Offset und rendern lokal (kein Tick-Spam).

### 3.1 Nachrichten-Katalog

| # | Richtung | Nachricht | Payload (Kern) | Zweck / Regeln |
|---|---|---|---|---|
| 1 | C→S | `room.create` | `{role: "screen"\|"gm", origin}` | Erzeugt Raum; Antwort `{code, gmPin, qrSvg}`. QR-URL basiert auf der Screen-Origin (Tunnel- vs. LAN-URL automatisch richtig) |
| 2 | C→S | `hello` | `{roomCode, role?, sessionToken?, name?, avatar?}` | Join UND Rejoin. Mit bekanntem Token: Slot-Restore. GM zusätzlich `gmPin`. Antwort: `welcome` |
| 3 | S→C | `welcome` | `{playerId, sessionToken, seq, view, serverTime}` | Token = UUID, Client speichert in `localStorage` unter `mm:<roomCode>`. View = Voll-Snapshot der Rolle |
| 4 | S→C | `view.snapshot` | `{seq, view}` | Voll-Snapshot (nach Rejoin, seq-Lücke, Phasenwechsel großer Art) |
| 5 | S→C | `view.event` | `{seq, event}` | Kleines Delta im Normalbetrieb; Client mit Lücke → #6 |
| 6 | C→S | `sync.request` | `{}` | Erzwingt #4. Selbstheilung |
| 7 | C→S | `time.ping` | `{t0}` | Alle ~5 s; Antwort `time.pong {t0, serverTime}` → Client hält Median-RTT (letzte 5) + Server-Zeit-Offset |
| 8 | C→S | `player.action` | `{minigameId, actionId, payload, idemKey}` | Alle Minigame-Inputs. `idemKey` macht Netz-Retries idempotent (Doppel-Tap-Schutz). ACK mit Timeout |
| 9 | C→S | `buzz` | `{pressedAtServerEst}` | Sonderfall von #8 mit Latenz-Kompensation (3.3) |
| 10 | C→S | `gm.cmd` | `{cmd, args, cmdId}` | EIN Kanal für alle GM-Kommandos (3.4); ACK `gm.ack {cmdId, ok, error?}` |
| 11 | S→GM | `gm.log` | `{entry}` | Aktions-Log-Eintrag (Zeitleiste der Wahrheit, undo-fähig markiert) |
| 12 | S→C | `room.presence` | `{playerId, connected, graceUntil?}` | Verbindungs-Ampel; Screen zeigt WLAN-Icon am Avatar |
| 13 | C→S | `claim.request` | `{targetPlayerId, name}` | Handy-Wechsel/Token weg: abwesenden Slot beanspruchen → GM bestätigt via `gm.cmd claim.approve` |
| 14 | C→S | `spectate.join` | `{roomCode}` | Vierte Rolle; Antwort wie #3 ohne Slot |
| 15 | S→C | `spectate.view` | `{seq, view}` | Screen-View in Handy-Layout, gedrosselt auf ~1/s |
| 16 | S→C | `room.closed` | `{reason}` | TTL abgelaufen (30 min ohne Clients → Autosave + Aufräumen) oder GM-Ende |

**Rollen-Handshake:** Rolle wird pro Verbindung fixiert (Rollenwechsel = neuer
`hello`). Screen ist tokenlos und mehrfach erlaubt (iPad + Beamer-PC). GM
verlangt die **GM-PIN**, die bei Raum-Erstellung auf dem Screen angezeigt wird
(kein Account-System, aber der Sitznachbar kann nicht einfach `/gm` öffnen).
Raum-Codes: 4 Buchstaben, Alphabet ohne Verwechsler (kein I/O/0/1),
server-generiert, Join-URL `http://host/j/AFFE`.

**Spät-Joiner:** landet automatisch als Spectator (mit Live-Crashkurs-Karten,
Katalog 19/5); zu Beginn der nächsten Runde fragt der Server den GM
(`gm.cmd latejoin.approve`) → Einstieg mit **Median**-Kontostand, Sternchen im
Endscreen. Hartes Limit 8 Spieler, danach nur Spectator.

### 3.2 Reconnect (der wichtigste Flow)

1. socket.io reconnectet den Transport (Auto-Backoff).
2. Client schickt `hello` mit gespeichertem `sessionToken`.
3. Server findet Slot, markiert „verbunden", schickt Voll-Snapshot mit
   aktueller `seq` → Client rendert exakt die richtige Phase, egal wo.
4. **Grace-Period 180 s:** Disconnect ≠ Rauswurf; Spiel pausiert NICHT
   automatisch; GM hat einen „Warten auf X"-Knopf. Minigames definieren ihre
   AFK-Regel selbst (`onDisconnect`, z. B. „letzter Slider-Stand zählt").
5. Handy-Wechsel: Claim-Flow (#13) mit GM-Bestätigung.
6. Screen/GM reconnecten identisch (Screen tokenlos, GM via PIN).
7. iOS-Hintergrund-Tab = normaler Reconnect (kein Sonderpfad).

### 3.3 Buzzer-Fairness — ENTSCHIEDENES Verfahren

**Server-autoritative Zeit + Median-RTT-Kompensation mit hartem Clamp +
Sammel-Fenster.** Konkret:

1. Client pingt alle ~5 s (#7); hält **Median-RTT der letzten 5** (Median,
   nicht Mittel — WLAN-Ausreißer) und Server-Zeit-Offset. Die „Nullrunde"
   (Aufwärm-Probefrage, Katalog 19/4) liefert die Erstmessung vor der ersten
   echten Buzzer-Runde.
2. Server armiert den Buzzer mit `{armedAtServerTime}`.
3. Beim Druck sendet der Client `pressedAtServerEst` (lokale Zeit → Server-Zeit
   umgerechnet).
4. Server rechnet: `floor = receiveTime − medianRTT` (mehr Gutschrift als die
   gemessene Latenz gibt es NIE) und wertet
   `final = max(armedAt, clamp(pressedAtServerEst, floor, receiveTime))`.
   Ein manipulierter Client kann sich damit weder in die Vergangenheit noch
   vor die Armierung buzzern.
5. **Sammel-Fenster 280 ms** nach dem ersten eingehenden Buzz für Nachzügler;
   dann Sortierung nach `final` und Verkündung. Kürzer als die gefühlte
   „Ergebnis kommt sofort"-Schwelle, lang genug für 100+ ms WLAN-Asymmetrie.
6. Differenz < 40 ms ⇒ sichtbarer „FOTOFINISH"-Münzwurf auf dem Screen
   (injizierter Rng) statt stillschweigendem WLAN-Vorteil.
7. Sofortiges lokales Feedback am Handy (Button färbt, Haptik-Fallback);
   die Reihenfolge verkündet der Server. Couch-Player (v2) haben RTT≈0,
   bekommen KEINE Kompensation, laufen aber durchs selbe Fenster.
8. Transparenz: GM kann die Buzz-Deltas in ms einsehen (Streitfälle).

**Latenz-Leitplanke für ALLE Minigames** (aus Katalog 02): Wertungen hängen
nie an frame-genauen Zeitpunkten, sondern an Stufen/Blöcken (3-s-Pixel-Stufen,
5-s-Kurs-Blöcke, 1-s-Tap-Batches) oder an gedeckelten Client-Timestamps.

### 3.4 Heartbeat/Timeout & GM-Kommando-Katalog

**Heartbeat:** Transport-Ebene socket.io `pingInterval` 10 s / `pingTimeout`
8 s. App-Ebene: `time.ping` (dient doppelt als Liveness), Presence-Broadcast
(#12), Grace 180 s, Raum-TTL 30 min (Router-Neustart-Realität) mit Autosave.

**GM-Kommandos — EIN Kanal, drei Bedienarten** (Mensch / Copilot / Auto-GM
nutzen dieselbe Command-API; alles landet im undo-fähigen Log). Katalog
(deckt alle 25 GM-Werkzeuge aus Katalog 03 ab):

| Gruppe | `cmd` | Wirkung |
|---|---|---|
| Ablauf | `flow.next` · `flow.reveal` · `flow.endRound` · `round.encore` | Nächste Frage, Auflösen, Runde beenden, +1 Extra-Frage (max. 2/Runde) |
| Zeit | `timer.pause` · `timer.resume` · `timer.extend {ms}` · `timer.freeze` | Max. 2 Verlängerungen/Frage, immer für ALLE |
| Session | `session.pause {duration?, text?}` · `session.resume` · `session.end` | Pause = natürlicher Save-Point |
| Fragen | `question.swap {questionId}` · `question.discard` · `question.search {filter}` · `question.markBroken {reason, refund: "annul"\|"grantAll"}` | Fragen-Regal; Roter Buzzer mit atomarem Rollback (Antworten, Punkte, Joker) |
| Minigame | `game.skip {keepPoints}` · `game.restart` · `game.flagBuggy {reason}` | 3 Flags ⇒ Auto-Rotation-Sperre |
| Punkte | `score.adjust {playerId, delta, reasonChip}` | Begründungs-Chip Pflicht; Soft-Cap ±20 % des Runden-Maximums, Override wird ROT geloggt |
| Fürsorge | `boost.underdog {playerId, kind, public}` · `joker.grant {playerId\|"all", jokerId}` · `hint.global {stage}` · `hint.whisper {playerId, text}` | Caps: 1 Boost/Spieler/Runde, Joker-Budget/Session, 2 Flüster-Tipps/Spieler/Runde (Aufdeckung am Runden-Ende) |
| Show | `vote.start {template\|custom, binding}` · `rule.play {cardId}` · `punish.apply {playerId, punishmentId}` · `sound.play {sfxId}` · `wheel.spin {rigTarget?}` | Anti-Mobbing-Sperre hart im Server; gezinkte Räder ROT geloggt; Sound-Rate-Limit 1/2 s |
| Feedback | `mood.poll` · `feedback.collect` | Max. 3 Blitz-Stimmungen/Session |
| Verwaltung | `save.slot {n, label}` · `load.slot {n}` · `claim.approve/deny` · `latejoin.approve/deny` · `gm.undo {logEntryId}` | Undo wo semantisch möglich (Punkte/Joker ja, Sounds nein), erzeugt selbst Log-Eintrag |

Fairness-Grenzen (Caps, Anti-Mobbing, Schwierigkeits-Kopplung) sitzen im
**Server**, nicht in der UI.

---

## 4. HTTP-only-Wahrheiten (AMP-Pfad)

Kernproblem: `http://<lan-ip>` ist **kein Secure Context** (Ausnahme
`localhost`). Zentrale Capability-Schicht `shared/caps.ts` prüft einmal beim
Start und liefert Flags; UI passt sich an, nichts wirft ungefangen. Es gibt
nie „Button da, aber tot" — die Lobby zeigt einen Modus-Badge
(„LAN-Modus" vs. „Tunnel-Modus: alle Features").

| Feature | HTTP (LAN-IP) | Workaround (konkret) |
|---|---|---|
| **Service Worker / PWA-Install** | ❌ | Gar nicht erst darauf bauen. Kleine Assets + `Cache-Control` mit Hash-Dateinamen; Reconnect-Logik lebt in der App, nicht im SW. „Zum Home-Bildschirm" (Hülle ohne SW) geht auch über HTTP |
| **Wake Lock API** | ❌ (`NotAllowedError`) | **NoSleep-Muster:** nach erstem Touch unsichtbares, stummes Loop-Video (iOS-Safari-erprobt). Lobby-Hinweis „Auto-Sperre → Nie". Wichtigste Maßnahme bleibt: Reconnect macht ein gesperrtes Handy nach Entsperren sofort wieder spielbereit. Im HTTPS-Pfad echtes `navigator.wakeLock` |
| **Clipboard API** | ❌ | Primär QR + kurze Tipp-URL (`/j/AFFE`). Sekundär: Link in selektiertem `<input readonly>` („gedrückt halten → Kopieren"), `document.execCommand('copy')` als Best-Effort |
| **Gamepad API** | ⚠️ Chromium bindet an Secure Context; auf `http://<lan-ip>` i. d. R. tot. `http://localhost` und Tunnel: ✅ | Controller = Screen-Feature mit dokumentierten zwei Wegen: Screen-Browser auf dem Host-PC (`localhost`) oder Tunnel-Link. Caps blendet Controller-UI aus, wenn `getGamepads` fehlt. Tastatur-Zonen als garantiert HTTP-sicherer Fallback |
| **Vibration API** | iOS Safari: **gar nicht** (HTTP wie HTTPS!). Android Chrome: ✅ auch über HTTP (nach User-Aktivierung) | Drei-Stufen-`haptics()`-Fallback: (1) Android `navigator.vibrate`, (2) iOS ≥ 17.4 Switch-Trick (`<input type="checkbox" switch>` per Label-Klick → nativer Haptik-Tick, kein Secure-Context-Feature), (3) überall: 30-ms-Screen-Shake + Klick-Sound |
| **Web Audio / `<audio>`** | ✅, aber Autoplay-Policy | „Tippe zum Starten"-Overlay auf JEDEM Client entsperrt den AudioContext (stummer Buffer-Play) — beim Join-Tap miterledigt. Show-Sound kommt vom Screen, Handys bleiben stumm (kein Echo-Chaos) |
| **speechSynthesis (TTS)** | ✅ (nicht Secure-Context-gebunden) | Unlock per User-Geste mit dem Audio-Unlock zusammen; `getVoices()` asynchron (voiceschanged). Vorlesen primär am Screen. **STT (SpeechRecognition) NICHT einplanen** (Secure Context + Cloud) |
| **getUserMedia / DeviceMotion/-Orientation** | ❌ (iOS `requestPermission` nur Secure Context) | Minigames deklarieren `requiresSecureContext: true` → im HTTP-Pfad ausgeblendet statt kaputt angeboten. Kern-Mechaniken setzen NIE Sensoren voraus |
| **Web Share API** | ❌ | Button nur zeigen, wenn `navigator.share` existiert; QR reicht |
| **Fullscreen API** | ✅ (kein Secure Context nötig) | iPhone-Safari kann eh kein Element-Fullscreen → Player braucht es nicht (`100dvh`, `viewport-fit=cover`); Screen/PC: Fullscreen-Button |
| **WebSocket** | ✅ `ws://` | Gegenrichtung beachten: Tunnel-Seite braucht `wss://` → socket.io-Client IMMER mit relativer URL/`window.location` initialisieren, nie hart `ws://`. Cloudflare kann WebSockets; Long-Polling fängt den Rest |

**Cloudflare-Pfad parallel sauber:** genau EIN Build; alle URLs relativ; QR
nutzt die Screen-Origin (zeigt automatisch Tunnel-URL); Caps entscheidet zur
Laufzeit; `tools/tunnel`-Wrapper shellt auf `cloudflared tunnel --url
http://localhost:<port>`, parst die `trycloudflare.com`-URL und zeigt sie als
QR. Doku empfiehlt für Stammrunden einen benannten Tunnel mit fester Domain
(Quick-Tunnel-URLs sind flüchtig, ohne SLA).

---

## 5. Persistenz

Alles unter `DATA_DIR` (Env, AMP-persistentes Verzeichnis). Jede Datei:
`schemaVersion` + Migration beim Laden; Schreiben atomar
(`tmp → fsync → rename`).

```
DATA_DIR/
├─ saves/slot-1.json … slot-8.json + auto-1..3.json   # Save-Slots (5.2)
├─ profiles/profiles.json                              # Profile (5.1)
├─ events/2026-08.jsonl                                # Event-Log, append-only, monatsrotiert (5.3)
├─ stats/player_stats.json · question_stats.json · alltime.json   # materialisierte Aggregate
└─ meta/rooms.json                                     # TTL-Wiederbelebung nach Server-Neustart
```

### 5.1 Profile & All-time

`{profileId (UUID), name, avatar, pinHash?, createdAt, deviceTokens[],
titles[], unlocks[], settings{textScale, mirrorLayout, reducedMotion}}`.
Frictionless: Name + Affe, fertig; `device_token` in localStorage →
„Willkommen zurück"-Kacheln; Claim-Code (6 Zeichen) für Gerätewechsel;
Gast-Modus mit nachträglichem „Adoptieren" (Events werden rückwirkend
umgehängt — billig dank Event-Log). Privacy: Export als JSON/ZIP, Löschen
zweistufig (Anonymisieren mit Tombstone-`actorId` vs. Voll-Löschung),
Voll-Backup = `DATA_DIR` zippen. Keinerlei Telefonie nach außen.

### 5.2 Save-Slots — ENTSCHEIDUNG: kompletter Engine-State, nur an Phasengrenzen

**Format:** Ein Slot = eine JSON-Datei:

```json
{ "schemaVersion": 1, "savedAt": "...", "label": "WG-Dienstag",
  "roomCodeHint": "AFFE", "settings": { "...": "Match-Settings-Matrix" },
  "players": [ { "playerId": "...", "profileId": "...", "name": "...", "avatar": "...", "balance": 4200 } ],
  "engineState": { "phase": "round:3", "roundPlan": [], "usedQuestionIds": [],
                    "jokers": {}, "minigameState": null, "rngState": "..." } }
```

- **Gespeichert wird das laufende Match KOMPLETT** — aber ausschließlich an
  sauberen Phasengrenzen (Runden-/Fragengrenze, Pause), nie mitten in einer
  Buzzer-Millisekunde. Eine angebrochene Frage wird beim Laden NEU gestellt
  (frische Frage — auch Anti-Schummel). `usedQuestionIds` verhindert
  Wiederholungen, `rngState` hält Determinismus.
- **Autosave** an jeder Phasengrenze in einen Ring aus 3 Auto-Slots +
  **manuelle Slots 1–8** übers GM-Cockpit (Label, Überschreiben mit
  Bestätigung).
- **Load-Flow:** GM wählt Slot → neuer Raum im Zustand „Wiederaufnahme":
  Screen zeigt QR + gespeicherte Spieler als „unclaimed" Avatare → jeder
  claimt seinen Platz (GM bestätigt strittige) → GM drückt „Weiter".
  Session-Tokens werden bewusst NICHT persistiert (neuer Abend, neue Handys)
  — dafür existiert der Claim-Flow.
- Auto-Slots verfallen nach 7 Tagen; Turnier-Stände sind eigene, unbegrenzt
  haltbare Dateien (`saves/tournament-<name>.json`).

### 5.3 Stats-Event-Log — Schema

Append-only JSONL, eine Zeile pro Ereignis, **Single Source of Truth** für
alle Stats/Bestenlisten/Analytics (Katalog 15/23):

```json
{ "v": 1, "ts": 1755212345678, "matchId": "m_...", "seq": 412,
  "type": "buzz", "actor": "profile_...", "questionId": "q_...",
  "payload": { "latencyMs": 43, "rank": 1 } }
```

Event-Typen (v1): `match_started`, `player_joined`, `question_shown`, `buzz`,
`answer_submitted`, `answer_judged`, `joker_used`, `hint_bought`,
`money_changed`, `gm_command`, `question_flagged`, `minigame_started`,
`minigame_finished`, `match_ended`, `feedback_given`. Zeitstempel über
injizierte Clock. Aggregate (`player_stats` = Genauigkeits-Matrix
Kategorie×Schwierigkeit, Reaktionszeit-Profil, Streaks, Head-to-Head;
`question_stats` = Ausspiel-Zähler, Richtig-Quote je Modus, Flags, Drift)
werden nach jedem Match inkrementell aktualisiert; `tools/rebuild-stats`
baut sie jederzeit per Replay komplett neu (Bug-Heilung, rückwirkende Stats).
Kompaktierung/Retention bewusst P3 (JSONL verkraftet Jahre).

### 5.4 Fragen-Packs-Format

`content/packs/<packId>/pack.json`, Zod-validiert (CLI `tools/pack-validate`,
läuft auch in CI):

```json
{ "schemaVersion": 1, "id": "basis-de", "name": "Basis DE", "locale": "de",
  "region": "DE|GLOBAL", "questions": [ {
    "id": "q_0001", "kind": "choice4|trueFalse|estimate|sort|gapText|imageChoice|pixelReveal|audio|emoji",
    "category": "geografie", "difficulty": 1, "text": "…",
    "options": ["…"], "answer": 0,
    "tips": [ { "stage": 1, "text": "…", "costPct": 15 } ],
    "erklaerung": "PFLICHTFELD — 1–2 Sätze (Warum-Karte, Trainingsmodus)",
    "media": { "file": "bilder/q_0001.webp", "license": { "source": "…", "author": "…", "license": "CC0|CC-BY|PD|eigene", "url": "…" } },
    "tags": { "needsScreen": false, "farbkritisch": false, "adult": false, "kids": false }
} ] }
```

Validator-Gates: Maximal-Längen (längste Frage muss in Textgröße „Riesig" auf
iPhone 11 UND aus 4 m am Screen lesbar sein), `erklaerung` Pflicht,
Lizenz-Manifest Pflicht bei Medien (kein NC/ND), Distraktoren-Anzahl je
`kind`. Der `content-loader` filtert zur Laufzeit nach Kategorie,
Schwierigkeit, Region-Regler, Cooldown („abgenutzt"), Flags und
`needsScreen`/`adult`/`kids` je Session-Settings.

---

## 6. iPad-.ipa-Plan (WKWebView-Wrapper)

**Entscheidung:** Minimaler nativer WKWebView-Wrapper (Swift/UIKit, XcodeGen)
für das **Gastgeber-iPad** (Bildschirm/GM). Gäste-iPhones bekommen NIE eine
App — die joinen per QR in Safari. Capacitor abgelehnt (Overhead ohne
Nutzen: die zwei nötigen Native-Features sind 1 Zeile Swift + 4 Zeilen plist).

### 6.1 Projekt-Skizze

```
ios-wrapper/
├─ project.yml                    # XcodeGen-Spec (~40 Zeilen; diff-freundlich, kein .xcodeproj im Repo)
├─ Sources/
│  ├─ AppDelegate.swift           # ~30 Z.: Window, isIdleTimerDisabled=true, AVAudioSession .playback
│  ├─ ConnectViewController.swift # ~120 Z.: Server-URL-Eingabe (UserDefaults-Vorschlag), Rollen-Wahl Bildschirm/GM (hängt ?role=screen|gm an), großer Verbinden-Button; QR-Scan (AVFoundation) als P2
│  └─ GameViewController.swift    # ~80 Z.: WKWebView fullscreen; allowsInlineMediaPlayback=true; mediaTypesRequiringUserActionForPlayback=[] (Jingles ohne Touch!); 3-Finger-Longpress → zurück zum Connect-Screen; Pull-to-Reload-Geste
├─ Info.plist
└─ Assets.xcassets/               # AppIcon (Single-Size)
```

**Info.plist — die entscheidenden Keys:**

```xml
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
  <string>UIInterfaceOrientationLandscapeLeft</string>
  <string>UIInterfaceOrientationLandscapeRight</string>
</array>                                          <!-- Landscape-Lock -->
<key>UIRequiresFullScreen</key><true/>            <!-- kein Split View/Slide Over -->
<key>UIStatusBarHidden</key><true/>
<key>UIViewControllerBasedStatusBarAppearance</key><false/>
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>   <!-- ATS-Ausnahme: http://192.168.x.x -->
<key>NSLocalNetworkUsageDescription</key>
<string>Verbindet sich mit dem MONKEY-MONEY-Server im lokalen Netz.</string>
<key>NSCameraUsageDescription</key>
<string>Scannt den QR-Code des Spielservers.</string>    <!-- erst mit QR-Scan (P2) nötig -->
```

`isIdleTimerDisabled = true` (Sleep aus — DER Grund für den Wrapper) +
Landscape-plist + Autoplay-Freigabe lösen exakt die drei Dinge, die Safari
nicht kann. Erwartete .ipa-Größe: **< 1 MB** (WebKit ist System-Framework).

### 6.2 GitHub-Actions-Job (Muster: vorhandene xcodebuild-ohne-Signing-Pipeline)

```yaml
ipad-wrapper-ipa:            # .github/workflows/ipa.yml, Pfad-Filter: ios-wrapper/**
  runs-on: macos-15
  steps:
    - uses: actions/checkout@v4
    - run: brew install xcodegen && xcodegen generate --spec ios-wrapper/project.yml
    - name: Archive (unsigned)
      run: |
        xcodebuild archive \
          -project ios-wrapper/MonkeyMoneyPad.xcodeproj \
          -scheme MonkeyMoneyPad -configuration Release \
          -destination 'generic/platform=iOS' \
          -archivePath build/MonkeyMoneyPad.xcarchive \
          CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
          CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM=""
    - name: Package .ipa
      run: |
        mkdir -p build/Payload
        cp -R build/MonkeyMoneyPad.xcarchive/Products/Applications/*.app build/Payload/
        (cd build && zip -qry monkey-money-ipad-unsigned.ipa Payload)
    - run: python3 tools/verify_wrapper_ipa.py   # Erwartungen aus project.yml ableiten (Godot-Muster):
      # nur Landscape, UIRequiresFullScreen, Bundle-Id, NSAllowsLocalNetworking,
      # Erfolgszeile „.ipa gebaut: X MB, Y Dateien"
    - uses: actions/upload-artifact@v4
      with: { name: monkey-money-ipad-unsigned-ipa, path: build/monkey-money-ipad-unsigned.ipa }
```

Sideload-Realität ehrlich: unsignierte .ipa wird beim Sideload (AltStore/
Sideloadly/Xcode + freie Apple-ID) neu signiert; freie Apple-ID = 7 Tage
Laufzeit, max. 3 Apps. Für Party-Nutzung ausreichend; Release-Job optional
per Tag `ipad-v<semver>`.

### 6.3 App-Clips-WAHRHEIT

**App Clips gehen mit unsignierten Builds/Sideload NICHT. Definitiv.**
Gründe: (1) Associated-Domains-Entitlement (`appclips:…`) muss in der
Code-Signatur stecken — eine unsignierte .ipa hat keine verwertbare;
(2) Apple validiert eine AASA-Datei auf einer öffentlichen HTTPS-Domain
gegen den signierten Clip; (3) Auslieferung ausschließlich über App Store
Connect (selbst „Local Experiences" verlangen Dev-/AdHoc-/TestFlight-Signatur);
(4) kein Sideload-Kanal fürs On-Demand-System. **Gestrichen** —
wiedervorlegen nur bei App-Store-Plänen.

### 6.4 Alternativen ohne Wrapper (dokumentiert in `docs/`)

- **Safari-Fullscreen-Meta:** `<meta name="apple-mobile-web-app-capable"
  content="yes">` + „Zum Home-Bildschirm" öffnet ohne Adressleiste (auch über
  HTTP; nur die Hülle, kein SW/Offline). UI so bauen, dass die Safari-Leiste
  beim Scrollen kollabiert; Buttons nie hinter
  `env(safe-area-inset-bottom)`.
- **Guided Access (Geführter Zugriff):** Einstellungen → Bedienungshilfen →
  Geführter Zugriff aktivieren → Safari öffnen → Dreifachklick Seitentaste →
  Start. Sperrt das iPad in Safari UND unterdrückt Auto-Lock — der
  dokumentierte No-Wrapper-Fallback. Ergänzend: Auto-Sperre → „Nie".

---

## 7. Geräte-Erkennung + Rollen-Flow, QR, Controller

### 7.1 Landing-Page-Logik (`/`, < 20 KB)

1. Erkennung: Telefon via `maxTouchPoints` + Bildschirmbreite; **iPad-Falle:**
   iPadOS meldet macOS → `platform === 'MacIntel' && maxTouchPoints > 1` ⇒ iPad.
2. Heuristik wählt VOR: Telefon ⇒ „Spieler"; iPad/PC ⇒ Auswahl
   „Bildschirm / Show-Master / Spieler" (Default iPad ⇒ Bildschirm).
   **Immer mit einem Tap bestätigen lassen** — Auto-Routing ohne Frage
   produziert „warum bin ich Bildschirm?"-Supportfälle.
3. Wahl landet in `localStorage` → Reload/Reconnect ohne Dialog („Rolle
   wechseln"-Link bleibt).
4. `/j/CODE` überspringt die Frage: per Definition Spieler-Join
   (QR hängt am Beitritt). Join-Ziel: Name (Vorschlags-Chips) + Avatar
   (1 Tap aus 8) + „Rein da!" — Messlatte: QR-Scan → spielbereit < 20 s.
5. Wrapper-App (`?role=screen|gm`) überspringt Erkennung UND Frage.

### 7.2 QR-Erzeugung — serverseitig

npm-Paket `qrcode` → SVG im Lobby-Snapshot + `GET /api/qr?code=AFFE`.
Kein externer Dienst (LAN ohne Internet!), kein Client-Bundle-Gewicht.
**URL-Quelle = Origin des Screens** (wird beim Screen-`hello` mitgeschickt)
→ zeigt im Tunnel-Fall automatisch die Tunnel-URL, im LAN-Fall die LAN-IP;
Server-eigene IP-Raterei nur Fallback (Mehrfach-Interfaces). Anzeige groß in
der Lobby + dauerhaft klein in der Screen-Ecke für Nachzügler.

### 7.3 Controller (Gamepad-API) — ENTSCHEIDUNG: **v2**, aber v1-vorbereitet

- **Entscheidung:** Controller-Support („Sofa-Modus"/Hotseat am Screen)
  kommt in **v2**. Gründe: (a) Gamepad-API ist im primären AMP-LAN-Pfad auf
  Fremdgeräten i. d. R. tot (Secure Context, Abschnitt 4) — das Feature
  funktioniert dort nur am Host-PC/`localhost` oder via Tunnel; (b) der
  Buzzer-Kern muss zuerst stabil sein; (c) verdeckte Eingaben sind am
  geteilten Screen unmöglich → Sofa-Modus braucht eigene
  Blind-Commit-Varianten der Minigames.
- **v1 bereitet vor (Kostenpunkt ≈ 0):** Couch-Player sind im Protokoll
  normale Spieler, deren Session der Screen-Client hält
  (`inputSource: "gamepad"|"keyboard"` als Metadatum) — Server, Engine und
  Minigames unterscheiden sie NIE. Buzz ohne Kompensation (RTT≈0), selbes
  Sammel-Fenster. Button-Mapping erbt das Farbe+Form+Buchstabe-System
  (Süd-Button = Buzzer, 4 Face-Buttons = Formen A–D, D-Pad = Auswahl).
  Tastatur-Zonen (WASD/Pfeile/Numpad/IJKL) sind der garantiert
  HTTP-sichere Fallback und kommen mit demselben v2-Baustein.

---

## 8. Qualitäts-Infrastruktur

### 8.1 Test-Strategie (vier Ebenen)

1. **Unit (Vitest):** Engine-Reducer, Scoring/Streak/Ökonomie,
   Buzzer-Arbitrierung (mit simulierten RTTs + Clamp-Grenzfällen),
   Save-Migrationen, Content-Filter. Alles pure dank Clock/Rng-Injektion —
   Seed = Testfall.
2. **Protokoll-/Contract-Tests (Vitest):** (a) Zod-Schemas als Golden-Tests
   für jeden Nachrichtentyp; (b) **Minigame-Contract-Suite**, die JEDES
   Plugin automatisch durchläuft: State JSON-serialisierbar,
   Reducer-Purity via Doppel-Ausführung, `viewFor` leakt keine Geheimnisse
   an Spieler-Views (Snapshot-Diff gegen Antwort-Felder), `scores()` summiert
   integer, Save→Load→identisches Verhalten.
3. **BOT-SPIELER-Framework (`tools/bots/`, headless socket.io-Clients):**
   spielt **automatisierte Vollrunden gegen den echten Server** —
   `npm run bots -- --players 6 --match quick --seed 42`. Personas
   (schnell/langsam/AFK/Falschbuzzer) + **Chaos-Modus**: zufällige
   Disconnects, Doppel-Connects, 5-s-Delays, ein Client künstlich +150 ms
   (Latenz-Asymmetrie als wiederholbarer Buzzer-Fairness-Testfall).
   Exit-Code ≠ 0 bei Invarianten-Verletzung (Geld-Summen, seq-Lücken,
   hängende Phasen > 30 s). Dasselbe Framework treibt auch die AI-Spieler-
   Basis (deterministische Antwortzeit-Verteilungen).
4. **Playwright (E2E/UI):** ein Browser-Context pro Rolle (Screen + 2 Player
   + GM) gegen den echten Server; Smoke = komplettes Quick-Match; WebKit-
   Projekt für iOS-Nähe; Screenshot-Snapshots der Screen-Phasen.
   Geräte-Checkliste zusätzlich manuell: echtes iPhone über
   `http://<lan-ip>` (nicht localhost!) — Secure-Context-Bugs sind auf dem
   Entwickler-Setup unsichtbar.

### 8.2 Lint/Format — ENTSCHEIDUNG: **ESLint (Flat Config) + Prettier** ✅

typescript-eslint strict + `no-restricted-imports` (Abhängigkeitsregeln aus
Abschnitt 2 maschinell) + Verbot von `Date.now`/`Math.random` außerhalb von
`server/core` (Clock/Rng-Disziplin als Lint-Regel). Prettier für Format
(keine Stil-Diskussionen; Lehre aus GOOBY: vergessene Format-Läufe waren 10
von 11 roten CI-Runs → `npm run preflight` spiegelt die CI lokal und ist
Pflicht vor jedem Push).

### 8.3 CI-Jobs (`.github/workflows/`)

| Job | Inhalt | Trigger |
|---|---|---|
| `lint` | Prettier-Check, ESLint, `tsc --noEmit`, `tools/pack-validate content/packs/` | jeder Push/PR |
| `test` | Vitest (Unit + Protokoll + Minigame-Contracts) | jeder Push/PR |
| `bots` | Server starten → Bot-Vollrunde (6 Bots, Chaos-Modus, Seed fix) → Invarianten | jeder Push/PR |
| `e2e` | Playwright chromium + webkit, Quick-Match-Smoke | PR + main |
| `build` | `vite build` + Server-esbuild + `tools/release-zip` (Artefakt = AMP-Deploy-Zip) | main + Tag |
| `ipa` | Abschnitt 6.2 | Pfad `ios-wrapper/**` |
| `videos` (optional) | `npx remotion render` Trailer/Tutorials als Artefakt | manuell/Tag |
| `release` | Tag `v<semver>` → Release mit Deploy-Zip + .ipa | Tag |

### 8.4 Deploy-Anleitungen (Vollversionen in `docs/`)

**AMP Schritt für Schritt (`docs/DEPLOY-AMP.md`):**
1. Release-Zip aus CI laden (`client/dist/` + `server/dist/` + `package.json`
   + Lockfile + `content/packs/` — keine nativen Module).
2. AMP: Instanz „Generic Module / Application Deployment", Node-Runtime,
   App-Verzeichnis = entpacktes Zip.
3. Update-Task einmalig: `npm ci --omit=dev`. Start-Kommando:
   `node server/dist/index.js`.
4. Env im AMP-Panel: `PORT` (von AMP zugewiesen — Server respektiert
   `process.env.PORT`), `DATA_DIR` (persistenter Pfad, den Updates nicht
   wegputzen), optional `MAX_ROOMS`, `GM_PIN_LENGTH`.
5. Port in der AMP-Portfreigabe öffnen; Health-Check `/healthz` in AMPs
   Monitoring. Ein Prozess, kein Cluster (8 Spieler = Grundrauschen).
6. Hinweis: Dieser Pfad ist HTTP-only → LAN-Modus-Badge; für Wake Lock &
   Controller überall den Tunnel-Pfad nutzen.

**PC-Quickstart (`docs/QUICKSTART-PC.md`):** `npx monkey-money` — startet
Server auf freiem Port, druckt LAN-URL + ASCII-QR, öffnet den Screen im
Browser. Entwickler: `git clone && npm i && npm run dev` (Vite + tsx, ein
Kommando).

**Cloudflare-Tunnel (`docs/TUNNEL.md`):** `npx monkey-money --tunnel` shellt
auf installiertes `cloudflared` (`cloudflared tunnel --url
http://localhost:<port>`), parst die `trycloudflare.com`-URL, zeigt sie als
QR. Ohne `cloudflared`: Install-Einzeiler (winget/brew/apt). Für Stammrunden:
benannter Tunnel mit fester Domain.

---

## 9. Risiko-Liste (Top 8) mit Entschärfung

| # | Risiko | Entschärfung |
|---|---|---|
| 1 | **Secure-Context-Brüche im HTTP/AMP-Pfad** — Features laufen beim Entwickler (localhost/Tunnel = secure) und sterben erst auf der Party im LAN | Capability-Schicht ab Tag 1; Test-Checkliste ausdrücklich „echtes iPhone über `http://<lan-ip>`"; NoSleep-Video + QR-statt-Clipboard als Standard, nicht Ausnahme; LAN-Modus-Badge macht Grenzen sichtbar statt mysteriös |
| 2 | **Reconnect-Robustheit im Party-WLAN** — Doppel-Sockets, Claim während Grace, seq-Lücken sind hier Normalfall | Snapshot+seq mit Selbstheilung (Lücke ⇒ Voll-Snapshot); Session-Restore als eigener, unit-getesteter Pfad; Bot-Chaos-Tests (Random-Disconnects, Doppel-Connects, Delays) als CI-Job gegen den echten Server |
| 3 | **iOS-Safari-Eigenheiten** (Audio-Unlock, Display-Sperre, 100vh, Tab-Suspend, iPad-UA-Lüge) treffen 100 % der Spieler-Clients | iPhone-Gerätetest ab dem ersten Lobby-Prototyp; `100dvh` + `viewport-fit=cover` von Anfang an; Audio-Unlock-Overlay als fester Baustein; Hintergrund-Tab = normaler Reconnect; NoSleep-Video früh auf echten Geräten verifizieren |
| 4 | **Buzzer-Fairness** — fühlt sich Buzzern unfair an, kippt das Vertrauen in die Show; naive Client-Timestamps sind Schummel-Vektor | Verfahren 3.3 (Median-RTT, harter Clamp, 280-ms-Fenster, Fotofinish-Los); Bot-Testfall mit +150-ms-Asymmetrie in CI; GM sieht Buzz-Deltas in ms (Transparenz bei Streit) |
| 5 | **Minigame-Interface zu früh eingefroren oder zu schwammig** — die zentrale Architektur-Wette; Fehlschnitt erzwingt Umbauten in Engine UND allen Clients | Einfrieren erst nach 4 bewusst verschiedenartigen Referenz-Minigames; Contract-Test-Suite (Serialisierbarkeit, Purity, Leak-Check) läuft automatisch gegen jedes Plugin; Minigame-State im Engine-State ⇒ Save/Reconnect gelten automatisch |
| 6 | **AMP-Runner-Unbekannte** (Node-Version, Port-Zwang, flüchtige Verzeichnisse) zeigen sich erst beim echten Deploy | Null native Module (Storage-Entscheidung 1.3); `PORT`/`DATA_DIR` strikt aus Env; `/healthz`; Deploy-Smoke-Test auf dem echten AMP früh in der Roadmap, nicht am Ende; Release-Zip in CI = reproduzierbares Artefakt |
| 7 | **Party-WLAN-/Tunnel-Qualität** — Captive-Portal-Verhalten, Router-Neustarts, flüchtige trycloudflare-URLs über lange Abende | socket.io-Long-Polling-Fallback; Raum-TTL 30 min + Autosave (alle fliegen, alle kommen wieder); Latenz-Leitplanke „Stufen statt Frames" in jedem Minigame; Doku: benannter Tunnel für Stammrunden |
| 8 | **Content-Pipeline als schleichender Blocker** — Lizenz-Fehler, zu lange Texte (zerschießen Textgrößen), fehlende `erklaerung`-Felder über tausende Fragen nachrüsten ist teuer | Pack-Validator mit harten Gates (Länge, Lizenz-Manifest, Pflichtfelder) ab dem ERSTEN Pack in CI; Fehlerhaft-Queue + Auto-Rotation-Sperre ab X Flags; Fragen-Gesundheits-Aggregate (Drift, Abnutzung) von Tag 1 aus dem Event-Log |

---

## Anhang: Bau-Reihenfolge (P0 → P2, komprimiert)

1. **P0:** `shared` (Protokoll, caps) → `server/core+rooms` (Sessions,
   Snapshot/seq, Reconnect) → `server/engine` (Phasen, Reducer, viewFor)
   → Player/Screen/GM-Minimal-Clients → Buzzer-Fairness → 4 Referenz-
   Minigames → Interface einfrieren. Bot-Framework parallel ab Woche 1 der
   Engine (es IST das Testwerkzeug).
2. **P1:** Save/Load + Claim-Flow → Content-Pipeline + Validator + 1 Pack →
   QR/Landing/Geräte-Erkennung → Event-Log + Aggregate → GM-Cockpit-Vollausbau
   → AMP-Deploy-Doku + Release-Zip → ios-wrapper + ipa-Job.
3. **P2:** Controller/Sofa-Modus → Three.js-Insel (optional) → Spectator-
   Emotes → Remotion-Trailer/Tutorials → Profile-Extras (Titel, Saisons).
