# 17 — Technik-Architektur für MONKEY MONEY

Ideen-Agent 17/20 · Thema: Technik-Architektur (Stack, HTTP-only-Fallstricke,
Realtime, Modul-Schnitt, Betrieb). Rahmen: Node.js-App, AMP-Server (NUR HTTP)
ODER lokaler PC + Cloudflare-Tunnel (HTTPS), iPad/PC = Bildschirm, iPhones
(hochkant, Safari) als Controller, Rollen Spieler/Bildschirm/Show-Master,
2–8 Spieler, Reconnect-fähig, Controller-Support, Save/Load-Slots, modular.

---

## 0. Leitprinzipien (aus den Rahmenbedingungen abgeleitet)

1. **Server = einzige Wahrheit.** Clients sind dumme Renderer von Snapshots +
   Events. Kein Spielzustand, der nur im Browser lebt.
2. **Zwei Transport-Welten, ein Code-Pfad.** Die App läuft identisch über
   `http://` (AMP/LAN) und `https://` (Cloudflare-Tunnel). Alles, was einen
   Secure Context braucht, läuft über eine zentrale Capability-Schicht mit
   Fallbacks — niemals hart vorausgesetzt.
3. **Determinismus in der Engine.** Zeit (`Clock`) und Zufall (RNG) werden
   injiziert, nie `Date.now()`/`Math.random()` direkt in der Spiellogik.
   (Gleiche Disziplin wie im GOOBY-Repo bewährt — macht Save/Load, Replay
   und Tests trivial.)
4. **Keine nativen Node-Module, kein Build-Zwang auf dem Server.** AMP-Deploy
   muss „npm ci → node starten" sein. Alles Fragile (node-gyp, Prebuilds)
   fliegt raus.
5. **Handy-Client ultraleicht.** Party-WLAN + iPhone-Safari: das
   Spieler-Frontend muss in < 200 KB (gzipped) laden und ohne Reload durch
   den ganzen Abend kommen.

---

## (a) Stack-Empfehlung mit Begründung

### Transport: **Express + socket.io** (nicht rohes `ws`)

| Kriterium | `ws` (roh) | **socket.io v4** |
|---|---|---|
| Reconnect | selbst bauen (Heartbeat, Backoff, Re-Auth) | eingebaut: Auto-Reconnect mit Backoff, **Connection State Recovery** (verpasste Events werden nachgeliefert) |
| Räume/Broadcast | selbst bauen | `io.to(room).emit(...)` fertig |
| Fallback bei zickigen Netzen | keiner | HTTP-Long-Polling-Fallback (hilft bei Captive-Portal-artigen Party-WLANs und hinter Cloudflare) |
| Acknowledgements/Timeouts | selbst bauen | `emit(..., ack)` mit Timeout eingebaut |
| Overhead | minimal | ~10 KB extra am Client, minimaler Protokoll-Overhead |

**Entscheidung: socket.io.** Der einzige Vorteil von rohem `ws` ist Schlankheit
— und genau die Features, die wir dann nachbauen müssten (Reconnect, Räume,
ACKs), sind die fehleranfälligsten Teile einer Party-App im Wackel-WLAN.
Wichtig: socket.io-Reconnect ersetzt NICHT unsere Session-Logik (siehe (c)) —
es liefert nur den Transport-Reconnect; die fachliche Wiederherstellung
(„du bist wieder Spieler 3 mit 4200 Punkten") machen wir selbst mit
Session-Tokens + Snapshot. Connection State Recovery ist nur Bonus für
Kurz-Aussetzer (< ~2 min), nicht die Grundlage.

Express bleibt als HTTP-Schicht (Static Files, `/j/:code`-Kurz-URLs,
Health-Endpoint, Save/Load-REST für den GM). Kein Fastify/Koa-Experiment
nötig — Express ist AMP-erprobt, überall dokumentiert, und der HTTP-Teil ist
bei uns trivial.

### Frontend: **Vanilla TypeScript + lit-html** (kein React/Vue)

- Drei Clients (Screen, Player, GM) sind zustandsgetriebene Renderer:
  `render(snapshot) → DOM`. Dafür reicht **lit-html** (~7 KB) als
  Templating mit effizientem Re-Render; kein virtueller DOM, kein
  Framework-Lock-in, kein Hydration-Thema.
- Preact wäre die Alternative, falls das Team JSX-Komfort will (~11 KB,
  buildless via HTM möglich). Empfehlung trotzdem lit-html: weniger
  Konzepte, näher an „Snapshot rein, HTML raus".
- Player-Client bewusst spartanisch: große Touch-Flächen, ein Screen pro
  Phase, CSS-Transitions statt JS-Animationen → schont iPhone-Akku und
  bleibt bei Lag flüssig.

### Three.js: **nur für Bühnen-Momente auf dem Screen-Client, lazy geladen**

- Komplett-3D lohnt nicht: 90 % der Show sind Text, Buzzer, Scoreboards —
  DOM/CSS (+ etwas Canvas 2D für Konfetti/Partikel) ist schneller gebaut,
  besser lesbar auf iPad-Distanz und robuster.
- Three.js (~150 KB+) nur als **dynamischer Import im Screen-Client** für
  2–3 Signatur-Momente (Intro-Logo, Finale, Jackpot-Regen). Player/GM-Client
  laden es NIE. Fallback: wenn WebGL fehlt oder das iPad ruckelt →
  CSS-Variante desselben Moments (Motion-Budget-Flag im Screen-Client).

### Build-Tooling: **Vite (build → statische Dateien), Server via tsx/esbuild**

| Option | Bewertung |
|---|---|
| **Vite** | ✅ Empfehlung. Dev-Server mit HMR für 3 Clients (Multi-Page: `screen.html`, `player.html`, `gm.html`), `vite build` erzeugt reine statische Dateien nach `dist/`, die Express ausliefert. AMP sieht davon nichts — auf dem Server läuft kein Build. |
| esbuild pur | Schneller, aber Dev-Ergonomie (HMR, CSS-Handling) selbst verdrahten. Als Vite-Unterbau ohnehin dabei. |
| Buildless ES-Modules + Import-Maps | Verlockend fürs AMP-Deploy („einfach Dateien hinlegen"), aber: kein TypeScript im Browser ohne Build, kein Bundling → viele Requests im Party-WLAN, Import-Maps in älteren iOS-Versionen wackelig. **Nur als Notfall-Pfad interessant.** |

**Deploy-Artefakt = `dist/` + `server/` + `node_modules` (prod).** Der Build
läuft in CI oder auf dem Entwickler-PC, nie auf dem AMP-Server. Server-Code
in TS, mit `tsx` im Dev und als transpiliertes JS (esbuild, ein File pro
Package) im Release — Alternative: Server gleich in modernem JS mit JSDoc-Typen,
dann entfällt sogar der Server-Buildschritt.

### Storage: **JSON-Dateien mit Atomic-Write** (kein better-sqlite3 in v1)

- better-sqlite3 ist ein natives Modul: Prebuilds existieren, aber die
  Node-Version des AMP-App-Runners ist nicht garantiert prebuild-kompatibel
  → im schlimmsten Fall node-gyp/Compiler auf dem Gameserver. Genau das
  Risiko, das ein Party-Abend nicht braucht.
- Unsere Daten sind winzig: Save-Slots (wenige KB JSON), Fragen-Packs
  (statisch, read-only), evtl. Statistiken. Kein Query-Bedarf, keine
  Concurrency (ein Prozess, ein Raum-Set).
- **Design:** `data/`-Verzeichnis (Pfad via `DATA_DIR`-Env, AMP-freundlich),
  pro Slot eine Datei `saves/slot-<n>.json`, Schreiben immer
  `write tmp → fsync → rename` (atomar, kein korruptes Save bei Absturz),
  `schemaVersion`-Feld + Migrations-Funktion beim Laden.
- Abstraktion `Storage`-Interface (get/put/list) im server-core, damit ein
  späterer Wechsel auf SQLite (falls je Statistiken/Historie wachsen) ein
  Adapter bleibt, kein Umbau.

### Stack-Zusammenfassung

```
Node 20+ · Express (HTTP/Static) · socket.io (Realtime)
TypeScript überall · lit-html (Clients) · Three.js lazy nur Screen
Vite (Dev+Build, Multi-Page) · JSON-Storage atomar · qrcode (npm) für QR
Zod für Protokoll- und Content-Validierung · Vitest für Engine-Tests
```

---

## (b) HTTP-ONLY-Fallstricke (AMP-Pfad) + Workarounds

Kernproblem: über `http://<lan-ip>` ist der Origin **kein Secure Context**
(Ausnahme: `localhost`). Der Cloudflare-Tunnel liefert dagegen echtes HTTPS.
Beide Pfade müssen sauber funktionieren → zentrale **Capability-Schicht**
`shared/caps.ts`: einmal beim Start `isSecureContext`, Feature-Detection und
Plattform prüfen, Ergebnis als Flags an alle Module; UI passt sich an,
nichts wirft ungefangen.

| Feature | Über HTTP (LAN-IP) | Konsequenz | Workaround |
|---|---|---|---|
| **Service Worker / PWA** | ❌ geht NICHT (Secure Context Pflicht) | kein Offline-Cache, kein Install-Prompt, kein Push | Gar nicht erst darauf bauen. Assets klein halten + aggressive `Cache-Control` mit Hash-Dateinamen. Reconnect-Logik lebt in der App, nicht im SW. iOS „Zum Home-Bildschirm" funktioniert auch ohne SW (nur ohne Offline). |
| **Clipboard API** (`navigator.clipboard`) | ❌ | „Link kopieren"-Button tot | Primär: **QR-Code + kurze Join-URL zum Abtippen** (`http://ip:port/j/AFFE`). Sekundär: Link in ein selektiertes `<input readonly>` legen („gedrückt halten → Kopieren"), Legacy `document.execCommand('copy')` als Best-Effort. |
| **Wake Lock API** | ❌ | iPhone-Display geht mitten in der Runde aus → gefühlter Disconnect | **NoSleep-Muster**: nach erstem Touch ein unsichtbares, stummes Loop-Video abspielen (funktioniert in iOS-Safari). Zusätzlich UI-Hinweis in der Lobby: „Auto-Sperre auf ,Nie' stellen". Im HTTPS-Pfad echtes `navigator.wakeLock`. |
| **Gamepad API** | ⚠️ In Chromium an Secure Context gebunden; auf `http://<lan-ip>` i. d. R. tot. Auf `http://localhost` (Screen auf dem Host-PC) und via Tunnel: ✅ | Controller-Support bricht ausgerechnet im AMP-LAN-Fall | Controller-Support als **Screen-Feature** deklarieren und dokumentieren: „Controller? Screen-Browser auf dem Host-PC (`localhost`) öffnen oder Tunnel-Link nutzen." Notnagel für Technikaffine: Chrome-Flag `unsafely-treat-insecure-origin-as-secure`. Caps-Layer blendet Controller-UI aus, wenn `getGamepads` fehlt/leer bleibt. |
| **Fullscreen API** | ✅ (kein Secure Context nötig) | — | iPhone-Safari kann eh kein Element-Fullscreen (nur Video) → Player-UI so bauen, dass sie es nicht braucht (`100dvh`, `viewport-fit=cover`, Meta-Theme-Color). iPad/PC-Screen: Fullscreen-Button funktioniert. |
| **Web Audio / `<audio>`** | ✅, aber Autoplay-Policy | Sound erst nach User-Geste | Standard-Muster: „Tippe zum Starten"-Overlay auf JEDEM Client entsperrt AudioContext (ein stummer Buffer-Play). Screen: GM klickt einmal beim Show-Start. |
| **getUserMedia (Mikro)** | ❌ | Mikro-Minigames unmöglich im AMP-Pfad | Solche Minigames im Manifest als `requiresSecureContext: true` markieren → Lobby blendet sie im HTTP-Pfad aus statt kaputt anzubieten. |
| **DeviceMotion/-Orientation (Schütteln/Kippen)** | ❌ auf iOS (`requestPermission` nur Secure Context) | Kipp-Minigames nur via Tunnel | wie Mikro: Capability-Flag pro Minigame. |
| **Web Share API** | ❌ | „Teilen"-Button tot | QR reicht; Button nur zeigen, wenn `navigator.share` existiert. |
| **WebSocket** | ✅ `ws://` von HTTP-Seite | — | Achtung Gegenrichtung: HTTPS-Seite (Tunnel) braucht `wss://` → socket.io-Client IMMER mit relativer URL/`window.location` initialisieren, nie hart `ws://`. Cloudflare-Tunnel kann WebSockets; Long-Polling-Fallback von socket.io fängt Rest ab. |

**Doppelpfad-Regel:** Es gibt genau EINEN Build. Der Client entscheidet zur
Laufzeit via `caps` was er anbietet. Die Lobby zeigt einen dezenten
Status-Badge („LAN-Modus: Bildschirm-an-Modus per Video aktiv, Controller nur
am Host-PC" vs. „Tunnel-Modus: alle Features"). So gibt es nie die Situation
„Button da, aber tot".

---

## (c) Realtime-Design

### Raum-Codes & Join

- **4 Buchstaben**, Alphabet ohne Verwechsler (kein I/O/0/1, keine deutschen
  Problemfälle), server-generiert, kollisionfrei geprüft. ~330k Kombinationen
  — genug, auch wenn der Server mehrere Räume gleichzeitig hält.
- Join-URL `http://host/j/AFFE` → Redirect auf Player-Client mit
  vorausgefülltem Code. QR-Code enthält genau diese URL.
- Räume haben TTL: ohne verbundene Clients 30 min am Leben halten (Party-
  Realität: Router-Neustart, alle fliegen, alle kommen wieder), dann
  Autosave + Aufräumen.

### Rollen-Handshake

```
Client                              Server
  |-- hello {role?, roomCode, sessionToken?} -->|
  |<-- welcome {playerId, sessionToken,         |   neuer Spieler: Token frisch
  |            snapshot, seq}                   |   bekannter Token: Slot-Restore
```

- **Spieler:** Name + Emoji/Avatar wählen → Server vergibt `playerId` +
  `sessionToken` (UUID, in `localStorage` unter `mm:<roomCode>`), Slot
  belegt.
- **Bildschirm:** Rolle „screen" ist unkritisch (zeigt nur öffentliches
  Wissen), mehrere Screens erlaubt (z. B. iPad + Beamer-PC) — alle kriegen
  denselben Stream.
- **Show-Master:** sensibel (sieht Antworten, steuert Show). GM-Client
  verlangt eine **GM-PIN**, die beim Raum-Erstellen auf dem Screen angezeigt
  wird. Kein Account-System — Party-Pragmatismus, aber der Sitznachbar kann
  nicht einfach `/gm` öffnen.
- Rolle wird pro Verbindung fixiert; Rollenwechsel = neuer Handshake.

### Zustands-Synchronisation: Snapshot + Events mit Sequenznummern

- Server hält pro Raum den **kompletten Zustand** (Lobby, Phase, Scores,
  aktives Minigame-Sub-State). Jede Änderung läuft durch die Engine
  (Reducer, s. (d)) und erhöht `seq`.
- **Clients bekommen View-gefilterte Snapshots:** Spieler sehen nie fremde
  Antworten vor der Auflösung, der Screen nie GM-Notizen. Filterung passiert
  serverseitig pro Rolle (`viewFor(role, playerId, state)`) — nie „im Client
  ausblenden", sonst ist Schummeln per DevTools trivial.
- Laufender Betrieb: kleine **Events** (`{seq, patch|event}`); erkennt ein
  Client eine Seq-Lücke (Event verpasst), fordert er einen Voll-Snapshot an.
  Das macht das Protokoll selbstheilend und Reconnect zum Normalfall statt
  Sonderfall.
- **Timer laufen NUR auf dem Server** (injizierte Clock). Clients bekommen
  `{endsAtServerTime}` + laufende Server-Zeit-Offsets und rendern den
  Countdown lokal — kein Tick-Spam über das WLAN.

### Reconnect (der wichtigste Flow der ganzen App)

1. socket.io reconnectet den Transport automatisch (Backoff).
2. Client schickt `hello` mit gespeichertem `sessionToken`.
3. Server findet den Slot, markiert Spieler „verbunden", schickt Voll-
   Snapshot mit aktueller `seq` → Client rendert exakt die richtige Phase
   (mitten in der Frage, mitten im Buzzer-Lock, egal wo).
4. **Grace-Period:** Disconnect ≠ Rauswurf. Spieler bleibt 3 min „abwesend"
   (Screen zeigt WLAN-Icon am Avatar), Spiel pausiert NICHT automatisch —
   der GM hat einen „Warten auf Spieler X"-Knopf, wenn er warten will.
5. Auch **Handy-Wechsel** geht: „Ich bin schon im Spiel"-Option beim Join
   listet abwesende Spieler → Claim mit GM-Bestätigung (Token weg, Handy
   kaputt — Party-Realität).
6. Screen/GM reconnecten identisch (Screen tokenlos, GM via PIN).

### Buzzer-Fairness (Latenz-Kompensation)

- Jeder Player-Client pingt alle ~5 s (`ping → pong` mit Server-Zeit);
  Client hält **Median-RTT der letzten 5 Pings** (Median, nicht Mittelwert —
  WLAN-Ausreißer!) und den Server-Zeit-Offset.
- Buzz-Ablauf: Server öffnet Buzzer mit `{armedAtServerTime}`. Client sendet
  beim Druck `{clientPressTime (in Server-Zeit umgerechnet)}`. Server rechnet
  gegen: `estimatedPress = receiveTime − RTT/2`, nimmt das **Maximum aus
  Client-Angabe und plausiblem Fenster** (Clamp: Kompensation nie mehr als
  gemessener Median-RTT, nie vor `armedAt`) — verhindert, dass ein
  manipulierter Client sich in die Vergangenheit buzzert.
- **Sammel-Fenster:** Nach dem ersten eingehenden Buzz wartet der Server
  noch 250–300 ms auf Nachzügler, sortiert dann nach kompensierter Zeit und
  verkündet die Reihenfolge. Das Fenster ist kürzer als menschliche
  Wahrnehmung des „Ergebnis kommt sofort", aber lang genug, um 100 ms
  WLAN-Unterschied zwischen zwei iPhones auszugleichen.
- Sofortiges lokales Feedback (Button färbt sich beim Druck, Haptik via
  kurzem CSS-Flash) — die Verkündung „wer war Erster" kommt vom Server.
  Gefühlte Latenz ≠ echte Unfairness.

### Spectator

- Vierte, implizite Rolle: Join-Seite bietet „Nur zuschauen", wenn der Raum
  voll ist (8 Spieler) oder das Spiel läuft. Spectator bekommt den
  **Screen-View in Handy-Layout** (öffentliches Wissen, gedrosselt auf
  Snapshot alle ~1 s statt jedes Event) — praktisch gratis, weil die
  View-Filterung schon existiert. Kein Input außer Emoji-Reactions
  (optional, rate-limited), die der Screen als Overlay einblendet.

---

## (d) Modul-Schnitt (Monorepo, keine Monolithen)

```
monkey-money/
├─ package.json               # npm workspaces
├─ packages/
│  ├─ shared/                 # NUR Typen + Zod-Schemas + reine Helfer
│  │  ├─ protocol.ts          #   Client↔Server-Messages (diskriminierte Unions)
│  │  ├─ views.ts             #   Rollen-gefilterte View-Typen
│  │  └─ caps.ts              #   Capability-Detection (Browser)
│  ├─ engine/                 # Spiel-Zustandsmaschine, 100 % pure & testbar
│  │  ├─ gameState.ts         #   Show-Phasen: Lobby→Intro→Runden→Finale→Ende
│  │  ├─ reducer.ts           #   (state, action, ctx{clock, rng}) → state'
│  │  ├─ viewFor.ts           #   Rollen-Filterung der Snapshots
│  │  └─ save.ts              #   Serialisierung + schemaVersion-Migration
│  ├─ server/                 # Express + socket.io + Räume + Sessions
│  │  ├─ rooms.ts             #   Raum-Codes, TTL, Raum→Engine-Instanz
│  │  ├─ sessions.ts          #   sessionToken↔Slot, Grace-Period, Claim
│  │  ├─ sync.ts              #   Snapshot/Event/seq-Versand, Ping/RTT
│  │  ├─ storage.ts           #   Storage-Interface + JSON-Atomic-Impl
│  │  └─ index.ts             #   Wiring, Static-Serving von dist/
│  ├─ minigames/              # 1 Ordner = 1 Plugin, einheitliches Interface
│  │  ├─ _api/                #   MinigameModule-Interface (s. u.)
│  │  ├─ buzzer-quiz/
│  │  ├─ schaetzchen/         #   (Schätzfragen)
│  │  └─ sortier-affe/        #   (Reihenfolge sortieren)
│  └─ content/                # Fragen-Packs: JSON + Schema + Validator-CLI
│     ├─ schema.ts
│     └─ packs/*.json
├─ clients/
│  ├─ screen/                 # iPad/PC-Bühne (einziger Ort mit Three.js, lazy)
│  ├─ player/                 # iPhone hochkant, ultraleicht
│  └─ gm/                     # Show-Master-Cockpit (Tablet/Laptop-Layout)
└─ tools/                     #  Dev-Skripte, Pack-Validator, Fake-Player-Bot
```

### Das Minigame-Plugin-Interface (der wichtigste Vertrag)

```ts
interface MinigameModule<S, A> {
  meta: {
    id: string; name: string;
    minPlayers: number; maxPlayers: number;
    requiresSecureContext?: boolean;   // Mikro/Kipp-Spiele
    supportsGamepad?: boolean;         // Local-Play am Screen
    contentKind?: "quiz" | "estimate" | "none"; // welche Packs es frisst
  };
  init(players: PlayerId[], content: ContentSlice, rng: Rng): S;
  reduce(state: S, action: A, ctx: Ctx): S;        // pure! Clock/Rng aus ctx
  viewFor(state: S, role: Role, player?: PlayerId): unknown;
  isFinished(state: S): boolean;
  scores(state: S): Record<PlayerId, number>;      // Engine addiert aufs Konto
}
// Client-Seite gespiegelt: pro Minigame ein render{Screen,Player,Gm}(view)
// — per Vite-Glob-Import registriert, Code-Splitting pro Minigame gratis.
```

- Die **Engine kennt Minigames nur über dieses Interface** — neue Spiele =
  neuer Ordner, Registrierung, fertig. Kein Anfassen von server/ oder engine/.
- Minigame-State ist Teil des Engine-States → **Save/Load und Reconnect
  funktionieren automatisch für jedes Minigame**, das sich an „pure reducer,
  serialisierbarer State" hält. Das Interface erzwingt die Disziplin.
- Validierung des Schnitts: **von Anfang an 3 bewusst unterschiedliche
  Minigames bauen** (Buzzer-Reaktion, Alle-antworten-gleichzeitig,
  Screen-zentriertes Spiel mit Gamepad) — erst dann das Interface einfrieren.

### Abhängigkeitsregeln (hart)

`shared` ← alle · `engine` importiert nur `shared` (+ minigames-API) ·
`minigames/*` importieren nur `shared` + `_api` · `server` importiert
`engine`, nie umgekehrt · `clients/*` importieren nur `shared` + eigene
Minigame-Views. Ein ESLint-`no-restricted-imports`-Set zementiert das.

---

## (e) Querschnitts-Themen

### QR-Code-Erzeugung

- **npm-Paket `qrcode`, serverseitig** → SVG/DataURL. Kein externer Dienst
  (LAN ohne Internet!), kein Client-Bundle-Gewicht. Screen ruft
  `GET /api/qr?code=AFFE` ab bzw. bekommt das SVG im Lobby-Snapshot.
- URL im QR: die Origin, unter der der **Screen** die Seite geöffnet hat
  (`window.location.origin` wird beim Screen-Hello mitgeschickt) — so zeigt
  der QR im Tunnel-Fall automatisch die Tunnel-URL und im LAN-Fall die
  LAN-IP. Server-Raten der eigenen IP nur als Fallback (mehrere Interfaces!).
- Anzeige groß + dauerhaft klein in der Screen-Ecke während der Lobby, damit
  Nachzügler joinen können.

### Geräte-Erkennung-Flow

1. `/` lädt eine Mini-Landing (< 20 KB): Erkennung via
   `maxTouchPoints`, Bildschirmgröße, UA-Hints. **iPad-Falle:** iPadOS
   meldet sich als macOS → `platform === 'MacIntel' && maxTouchPoints > 1`
   ⇒ iPad.
2. Heuristik wählt VOR: Telefon ⇒ „Spieler", iPad/PC ⇒ Auswahl
   „Bildschirm / Show-Master / Spieler" mit sinnvollem Default (iPad ⇒
   Bildschirm). **Immer bestätigen lassen** (ein Tap) — Auto-Routing ohne
   Frage produziert die „warum bin ich Bildschirm?"-Supportfälle.
3. Wahl wird in `localStorage` gemerkt → beim Reload/Reconnect kein erneuter
   Dialog (aber änderbar via kleinem „Rolle wechseln"-Link).
4. Kommt der Client über `/j/CODE`, entfällt die Frage: das ist per
   Definition ein Spieler-Join (QR hängt am Beitritt).

### Controller-Support (Gamepad-API)

- **Modell: Controller = lokale Spieler am Screen-Gerät** („Couch-Player").
  Der Screen-Client pollt `navigator.getGamepads()` im rAF-Loop, mappt
  Buttons (Süd-Button = Buzzer, D-Pad = Auswahl) und schickt Inputs als
  normale Spieler-Actions an den Server — für Engine & Minigames sind
  Couch-Player von Handy-Spielern **ununterscheidbar**. Kein Sonderpfad in
  der Spiellogik.
- Pairing-UX: Lobby-Hinweis „Beliebige Taste am Controller drücken" →
  `gamepadconnected` → Avatar-Erstellung am Screen (Name per D-Pad-Tastatur
  oder GM tippt).
- Secure-Context-Realität (s. (b)): funktioniert sicher auf
  `http://localhost` (Screen läuft auf dem Host-PC) und im Tunnel-Pfad; im
  AMP-LAN-Pfad auf Fremdgerät ggf. tot → Caps-Layer blendet das Feature
  dann aus, Hinweistext erklärt die zwei funktionierenden Wege.
- Buzzer-Fairness: Couch-Player haben ~0 Latenz → ihre Buzzes bekommen
  KEINE Kompensation (RTT=0), laufen aber durchs selbe Sammel-Fenster.

### Save/Load-Slots-Design

- **Slot = eine JSON-Datei** (`saves/slot-3.json`):
  `{schemaVersion, savedAt, label, roomCodeHint, engineState}` —
  `engineState` enthält Scores, Rundenplan, absolvierte Fragen (gegen
  Wiederholung!) und ggf. Minigame-State.
- **Autosave** an jeder Phasengrenze in einen Ring aus 3 Auto-Slots +
  **manuelle Slots 1–8** über das GM-Cockpit (Name eingebbar, Überschreiben
  mit Bestätigung). Atomic-Write wie in (a).
- **Load-Flow:** GM wählt Slot → Server erstellt neuen Raum im Zustand
  „Wiederaufnahme": Screen zeigt QR + die gespeicherten Spieler als
  „unclaimed" Avatare → jeder joint und **claimt seinen alten Platz**
  (GM bestätigt strittige Claims). Erst wenn der GM „Weiter" drückt, läuft
  die Show ab der gespeicherten Phasengrenze weiter (nie mitten in einer
  Buzzer-Millisekunde — gespeichert wird nur an sauberen Grenzen).
- Session-Tokens werden NICHT persistiert (neuer Abend, neue Handys) —
  genau deshalb der Claim-Flow.

### AMP-Deploy-Anleitung (Skizze)

1. Release-Zip aus CI: `dist/` (Client-Builds) + `server/` (JS) +
   `package.json` + `package-lock.json` + `content/packs/`. KEINE nativen
   Module (bewusste Stack-Entscheidung, s. (a)).
2. AMP: Instanz mit **Generic Module / Application Deployment**, Node-Runtime;
   App-Verzeichnis = entpacktes Release.
3. Start-Kommando: `npm ci --omit=dev && node server/index.js` (oder `ci`
   einmalig als Update-Task, Start dann nur `node server/index.js`).
4. Env-Variablen im AMP-Panel: `PORT` (von AMP zugewiesen — Server MUSS
   `process.env.PORT` respektieren), `DATA_DIR` (persistentes Verzeichnis
   für Saves — in AMP auf einen Pfad legen, den Instanz-Updates nicht
   wegputzen), optional `GM_PIN_LENGTH`, `MAX_ROOMS`.
5. Port in der AMP-Firewall/Portfreigabe öffnen; Health-Check-URL `/healthz`
   für AMPs Monitoring eintragen. Ein Prozess, kein Cluster — 8 Spieler
   sind für einen Node-Prozess Lärm im Grundrauschen.
6. Hinweis in der Doku: „Dieser Pfad ist HTTP-only → LAN-Modus-Badge, s. (b).
   Für volle Features (Wake Lock, Controller überall) den Tunnel-Pfad nutzen."

### PC-Quickstart

- **Komfort-Pfad: `npx monkey-money`** (veröffentlichtes Paket mit
  eingebetteten `dist/`-Assets): startet Server auf freiem Port, druckt
  LAN-URL + QR **als ASCII in die Konsole**, öffnet den Screen im Browser.
- Tunnel-Pfad: `npx monkey-money --tunnel` shellt auf installiertes
  `cloudflared` (`cloudflared tunnel --url http://localhost:<port>`), parst
  die `trycloudflare.com`-URL und zeigt sie als QR. Ohne `cloudflared`:
  freundliche Install-Anleitung (winget/brew/apt-Einzeiler).
- Entwickler-Pfad: `git clone && npm i && npm run dev` (Vite + tsx
  parallel, ein Kommando).
- Docker optional (`docker run -p 8080:8080 -v saves:/data monkey-money`)
  — nice-to-have, NICHT der beworbene Weg: Zielgruppe Partyhost hat eher
  Node/npx als Docker.

---

## Aufwand & Priorität je Baustein

Aufwand als Komplexitätsgröße (S/M/L = Umfang & Risiko der nötigen Eingriffe),
Prio P0 = ohne das keine Show, P1 = erster Release, P2 = danach.

| Baustein | Aufwand | Prio | Anmerkung |
|---|---|---|---|
| server-core (Express, socket.io, Räume, Sessions, Sync) | **L** | P0 | Fundament; Reconnect-Protokoll ist der Kern |
| engine (Phasen-Maschine, Reducer, viewFor, Clock/RNG-Injektion) | M | P0 | pure & test-first, Vitest |
| Player-Client (Join, Lobby, Buzzer, Antwort-Formulare) | M | P0 | ultraleicht, iOS-Safari zuerst testen |
| Screen-Client (Lobby, QR, Scoreboard, Phasen-Rendering) | M | P0 | Three.js-Momente NICHT hier, s. u. |
| GM-Client (Cockpit: Phase steuern, Skip, PIN, Save/Load) | M | P0 | hässlich-funktional zuerst |
| Capability-Schicht + HTTP/HTTPS-Doppelpfad | S | P0 | klein, aber früh — sonst überall Sonderfälle |
| Buzzer-Fairness (Ping/RTT, Sammel-Fenster, Clamps) | M | P0 | mit Latenz-Simulation testen (tc/Netz-Throttle) |
| Minigame-API + 3 Referenz-Minigames | L | P0/P1 | Interface erst nach dem 3. Spiel einfrieren |
| Save/Load-Slots + Claim-Flow | M | P1 | Autosave zuerst, Slots-UI danach |
| Content-Pipeline (Schema, Validator, 1 Fragen-Pack) | S | P1 | Validator in CI |
| QR + Geräte-Erkennung + Landing | S | P1 | iPad-Erkennungsfalle beachten |
| Controller-Support (Couch-Player) | M | P2 | erst wenn Buzzer-Kern stabil; Caps-abhängig |
| Three.js-Bühnen-Momente | M | P2 | reine Politur; CSS-Fallback zuerst |
| Spectator + Emoji-Reactions | S | P2 | fällt fast gratis aus viewFor ab |
| npx-Quickstart + Tunnel-Wrapper + AMP-Doku | S/M | P1 | Deploy-Doku parallel zum ersten Release |

---

## Die 5 riskantesten Punkte + Entschärfungs-Plan

1. **Secure-Context-Brüche im HTTP/AMP-Pfad** (Wake Lock, Gamepad,
   Clipboard, SW/PWA tot). *Risiko:* Features funktionieren beim Entwickler
   (localhost/Tunnel = secure) und sterben erst auf der Party im LAN.
   *Entschärfung:* Capability-Schicht ab Tag 1; CI-/Test-Checkliste
   ausdrücklich über `http://<lan-ip>` von einem echten iPhone (nicht
   localhost!); Wake-Lock-Video-Fallback und QR-statt-Clipboard als
   Standard, nicht als Ausnahme; LAN-Modus-Badge macht Einschränkungen
   sichtbar statt mysteriös.

2. **Reconnect-Robustheit im Party-WLAN.** *Risiko:* Der eine Flow, der
   den Abend rettet oder ruiniert; Race-Conditions (Doppel-Sockets, Claim
   während Grace-Period, Seq-Lücken) sind hier Standard, nicht Ausnahme.
   *Entschärfung:* Snapshot+seq-Protokoll mit Selbstheilung (Lücke ⇒
   Voll-Snapshot); Session-Restore als eigener, engine-getesteter Pfad;
   Chaos-Tests mit Fake-Player-Bot (`tools/`): zufällige Disconnects,
   Doppel-Connects, 5-s-Delays — als automatisierter Testlauf gegen den
   echten Server, nicht nur Unit-Tests.

3. **iOS-Safari-Eigenheiten auf dem Spieler-Handy** (Audio-Unlock,
   Display-Sperre, `100vh`-Chaos, Tab-Suspend im Hintergrund, iPad-UA-Lüge).
   *Risiko:* 100 % der Spieler-Clients sind iPhones — jede Eigenheit trifft
   alle. *Entschärfung:* iPhone-Gerätetest ab dem ersten Lobby-Prototyp
   (nicht erst „später"); `100dvh` + `viewport-fit=cover` von Anfang an;
   Audio-Unlock-Overlay als fester Baustein; „App war im Hintergrund"-Pfad
   = normaler Reconnect (Punkt 2 zahlt doppelt ein); NoSleep-Video früh
   auf echten Geräten verifizieren.

4. **Buzzer-Fairness bei ungleicher Latenz.** *Risiko:* Fühlt sich das
   Buzzern unfair an, kippt das Vertrauen in die ganze Show; naive
   Client-Timestamps sind zugleich ein Schummel-Vektor. *Entschärfung:*
   Server-autoritative Zeit + Median-RTT-Kompensation MIT hartem Clamp
   (nie mehr Gutschrift als gemessene Latenz, nie vor `armedAt`);
   250–300-ms-Sammel-Fenster; Testaufbau mit künstlicher Asymmetrie
   (ein Client +150 ms via Netz-Throttle) als wiederholbarer Testfall;
   Transparenz-Feature für Streitfälle: GM kann die Buzz-Deltas in ms sehen.

5. **Minigame-Interface zu früh eingefroren (oder zu schwammig).**
   *Risiko:* Der Modul-Schnitt ist die zentrale Architektur-Wette; ein
   Interface, das nur für Buzzer-Quiz passt, erzwingt später Umbauten in
   Engine UND allen Clients. *Entschärfung:* Interface erst nach drei
   bewusst verschiedenartigen Referenz-Minigames fixieren (Buzzer /
   Simultan-Eingabe / Screen-zentriert+Gamepad); Contract-Tests, die jedes
   Minigame automatisch durchlaufen muss (Serialisierbarkeit des States,
   Reducer-Purity via Doppel-Ausführung, viewFor leakt keine Geheimnisse an
   Spieler-Views); Minigame-State lebt im Engine-State ⇒ Save/Load und
   Reconnect gelten automatisch — Verstöße fallen im Contract-Test auf,
   nicht auf der Party.

*(Ehrenvolle Erwähnung, knapp außerhalb der Top 5: Cloudflare-Quick-Tunnel-
Stabilität über einen langen Abend — `trycloudflare`-URLs sind flüchtig und
ohne SLA. Entschärfung: Reconnect-Design (Punkt 2) toleriert Tunnel-Hänger;
Doku empfiehlt für wiederkehrende Runden einen benannten Tunnel mit fester
Domain.)*
