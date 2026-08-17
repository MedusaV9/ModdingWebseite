# ARCHITEKTUR — Engine v1 (voller Spielfluss)

Wo liegt was, und wie docken die nächsten Agents an. Verbindliche Entscheidungen
stehen in `docs/TECH-SPEC.md`, die Spielregeln in `docs/GAME-DESIGN.md` —
dieses Dokument beschreibt den IST-Stand und die Andock-Punkte.

## Modul-Baum (IST)

```
shared/                  Von Server UND Client importiert — nur Typen, Zod, pure Helfer
├─ protocol.ts           Nachrichten-Katalog (implementierter Kern) + Grenzen (2–8, Grace, TTL)
├─ views.ts              Rollen-gefilterte View-Typen (ScreenView/PlayerView/GmView)
├─ content.ts            Question/ContentSlice (Zod) + FrageMods (Laufzeit-Modifier)
├─ money.ts              MM-Werte 100/250/500/1000, Speed-Bonus, Timer je Schwierigkeit
├─ settings.ts           MatchSettings + Modi-Matrix (Quick/Klassik/Marathon-Blaupausen)
├─ economy.ts            Streak-Faktor, Rückenwind+Überhol-Kappe, W_final, Dispo, AT
├─ jokers.ts             Die 7 v1-Joker: Fenster, Preise (Sozialrabatt), Plugin-Hooks
├─ wheel.ts              Glücksrad: 14 Segmente + Gewichte, Kompatibilität, Pity, Dreh
├─ buzzer.ts             Buzzer-Fairness: Median-RTT, Clamp, 280ms-Fenster, Fotofinish
├─ ids.ts / time.ts / rng.ts / caps.ts
├─ meta.ts               META: Profile/AT/Level, Shop-Sortiment (20 Items), Avatar-Wire-
│                        Format mit Extras, Spaced-Repetition, Fragen-Gesundheit, Personas
└─ minigames/<id>.meta.ts   Meta + Action-Typen (beidseitig)

server/
├─ core/                 Wiring: Express (Static, /healthz, /api/qr, /j/:code), socket.io,
│                        Env-Config, EINZIGE Stelle mit OS-Uhr (clock.ts), gm-commands.ts
├─ rooms/                codes.ts (4 Buchstaben, kollisionsfrei) · sessions.ts (Token↔Slot)
│                        room.ts (Engine + seq + Broadcast + RTT-Messung + Buzz-Clamp)
├─ engine/               PURE Zustandsmaschine: engine.ts (reduce/tick), types.ts,
│                        plan.ts (Match-Plan + Fragen-Wahl), flow.ts (Phasen-Fluss),
│                        scoring.ts (Buchungs-Pipeline), jokers.ts (Joker-Regeln),
│                        rad.ts (Glücksrad-Runtime), gm.ts (17 GM-Werkzeuge),
│                        views.ts (viewFor — Geheimnis-Filterung)
├─ minigames/            _api/plugin.ts (DER Vertrag) · 21 Plugins (10 v1-Formate
│                        bananen-basics, vier-lianen, kokosnuss-uhr, bananen-tresor,
│                        affenleiter, pixel-dschungel, affenbank, stinkbanane,
│                        taschendieb, alles-oder-banane + lianen-finale + 6 v2-Formate
│                        + 4 Musik-Formate) · registry.ts
├─ content-loader/       index.ts — KAPSELT den Fragen-Zugriff (v1: echte Packs;
│                        ADDITIV: alleFragen() — Voll-Katalog für Übung/Analytics;
│                        bild_pixel ⇒ Question.media mit /media-URL)
├─ analytics/            event-log.ts — JSONL pro Match (Schema TECH-SPEC §5.3)
│                        aggregate.ts — Event-Log ⇒ materialisierte Aggregate
│                        (15 Spieler-Stats + Fragen-Gesundheit) · reports.ts — 5 Reports
├─ meta/                 META-Modul (Andocken 4): index.ts (MetaService = RoomMetaHooks),
│                        profile-store.ts (Profile/PIN/AT/Shop, atomar), boards.ts
│                        (4 Bestenlisten + Profil-Karte), practice.ts (Übungsmodus),
│                        save-store.ts (3 Slots + Autosave), bots.ts (In-Prozess-KI),
│                        http-api.ts (/api/meta/* + /admin) · admin-ui.ts (Dashboard)
│                        META v2: level.ts (Kauf-Gates + Level-Up-Erkennung),
│                        season.ts (Bananen-Pass-Store, meta/pass.json),
│                        quests.ts (Daily/Monats-Quests, meta/quests.json)
└─ persistence/          storage.ts — Storage-Interface + atomare JSON-Writes (DATA_DIR;
                         ADDITIV: readText/listeDateien für Log-Replay + Aggregate)

client/
├─ index/screen/player/gm.html   Vite-Multi-Page-Entries → client/dist/
├─ landing/              Geräte-Erkennung (iPad-Falle!) + Rollen-Wahl
│                        meta-landing.ts|css — Bestenlisten/Shop/Profil-Karte/Training
│                        + Tab „Pass & Quests" (Pass-Leiste, Quest-Karten, Saison-Archiv)
├─ screen/               Bühne: alle Phasen (Kategorie-Wahl, Erklärkarte, Rad,
│                        Siegerehrung, Momente-Banner) — Hüllen für den Polish-Agent
├─ player/               Join, alle Phasen + Joker-Leiste, Rad-Interaktionen,
│                        Flüster-Tipp, Feedback-Formular, time.probe-Echo
│                        meta-join.ts|css — Profil-Wahl im Join-Flow (Gast bleibt Default)
│                        meta-ende.ts — Match-Ende-Overlay (XP/Quests/Level-Up + Konfetti)
├─ gm/                   Cockpit KOMPLETT: 17 Werkzeuge, Spickzettel (geheim),
│                        Fragen-Regal + Maßanzug, Drama-Meter, Budgets, Aktions-Log
│                        meta-gm.ts — Bots hinzufügen/entfernen + Save/Load-Slots
└─ shared/               socket.ts (relative URL, Snapshot+seq+Selbstheilung), ui.ts,
                         session.ts (Token in localStorage), minigames/ (Renderer-Registry),
                         meta-avatar.ts (Shop-Kosmetik als SVG-Overlays, alltimeItems)

tools/bots/              Bot-Framework v1: alle Phasen generisch, Personas (Skill/Delay),
                         Joker-Zufallsnutzung, CHAOS-Modus (Disconnect+Token-Restore)
assets/                  Laufzeit-Medien: img/generated/pixel/ (12 Bilderrätsel-Motive,
                         MANIFEST.md daneben) · video/ (trailer.mp4, logo_stinger.webm/mp4
                         [VP9 mit Alpha — Show-Opening], tutorial_*.mp4 [Erklärkarten]) —
                         der Server liefert das Verzeichnis als /media/* aus (core/http.ts)
data/                    (gitignored) events/*.jsonl · meta/rooms.json
```

Abhängigkeitsregeln (per ESLint erzwungen): `shared` ← alle · `engine` nur
`shared` + `minigames/_api` · `minigames/*` nur `shared` + `_api` · `client/*`
nie Server-Code · `Date.now`/`Math.random` NUR in `server/core` (Clock/Rng
werden überall injiziert).

## Andocken 1: Neues Minigame (HowTo)

Ein Minigame hat exakt DREI Heimaten:

1. **`shared/minigames/<id>.meta.ts`** — Meta + Action-Typen (beidseitig).
2. **`server/minigames/<id>/index.ts`** — implementiert `MinigamePlugin<S, A>`
   aus `server/minigames/_api/plugin.ts` und wird in
   `server/minigames/registry.ts` eingetragen:

```ts
interface MinigamePlugin<S, A extends { type: string }> {
  meta: {
    id; name; minPlayers; maxPlayers; formats; contentKind; …;
    // ADDITIV (Engine v1) — alles optional:
    roundBased?: boolean;      // init bekommt ALLE Fragen der Runde, 1 Buchung am Ende
    streak?: boolean;          // false = Runden zählen nicht für den Streak (§3.2)
    strafenInsGlas?: boolean;  // Strafgelder wandern ins Jackpot-Glas (z. B. Stinkbanane)
    jokerAktionen?: JokerAction["type"][]; // welche Joker-Effekte reduce versteht
  };
  init(players: PlayerId[], content: ContentSlice, ctx: Ctx): S;
  reduce(state: S, action: PlayerAction<A | JokerAction> | GmAction, ctx: Ctx): S;
  tick(state: S, ctx: Ctx): S;
  onDisconnect(state: S, p: PlayerId, ctx: Ctx): S;
  onReconnect(state: S, p: PlayerId, ctx: Ctx): S;
  viewFor(state: S, role: Role, player?: PlayerId): unknown; // Geheimnisse HIER filtern
  isFinished(state: S): boolean;
  scores(state: S): Record<PlayerId, number>; // Engine bucht aufs MM-Konto
  // ADDITIV: präzise Richtig/Falsch+Timing-Infos für die Buchungs-Pipeline
  // (Streak, Fotofinish, Börsen-Roulette). Ohne outcomes gilt: delta > 0 = richtig.
  outcomes?(state: S): Record<PlayerId, PlayerOutcome>;
}
```

Regeln: alle Hooks PURE (Clock/Rng nur aus `ctx`), State JSON-serialisierbar
(lebt IM Engine-State ⇒ Save/Reconnect/Event-Log gratis). `GmAction` versteht
jedes Plugin: `timer.extend`, `timer.shift` (Pause), `force.finish` (Skip),
`option.remove` (Tipp-Kanone, optional).

**Neue `ctx`-Felder (ADDITIV, beide optional — Engine reicht sie zur Laufzeit
rein, in Unit-Tests des Plugins dürfen sie fehlen):**

```ts
interface Ctx {
  clock;
  rng; // wie bisher
  buzzer?: {
    medianRtt(p: PlayerId): number; // 0 wenn unbekannt
    sammelfensterMs: number; // 280 (TECH-SPEC §3.3)
    fotofinishMs: number; // 24 — darunter entscheidet das Los
    ordne(kandidaten: BuzzKandidat[]): BuzzErgebnis[]; // Ranking inkl. Losentscheid
  };
  match?: {
    balance(p: PlayerId): number; // MM-Kontostand (z. B. für Einsatz-Spiele)
    reihenfolge(): PlayerId[]; // Sitz-Reihenfolge (Join-Order)
    hatKlauSchutz(p: PlayerId): boolean; // Bananentresor-Schild (J6) aktiv?
    istVerbunden(p: PlayerId): boolean;
  };
}
```

**Joker-Aktionen** (kommen als normale `PlayerAction` mit diesen `type`s an —
nur wenn im Meta deklariert): `fiftyFifty` (Bananen-Split: 2 falsche Optionen
für DIESEN Spieler sperren), `removeOne {playerId | null}` (eine falsche Option
sperren; `null` = global für alle, Tipp-Kanone), `secondTry` (Rückgaberecht:
falsche Antwort zurücknehmen, halbe Punkte). Buzz kommt als
`{type: "buzz", finalAt}` an — `finalAt` ist bereits Median-RTT-kompensiert und
geclampt (Raum-Ebene), das Plugin sammelt und ruft `ctx.buzzer.ordne(…)`.

**Fragen-Modifier** (`ContentSlice.mods`, von Rad/Jokern/GM gesetzt — Plugins
sollten unterstützen, was zu ihrem Format passt): `timerFaktor` (0.5 = Halbe
Miete), `insiderId`+`insiderVorsprungMs` (Insider-Tipp sieht früher),
`geraeteMischung` (Affentheater: Antwort-Positionen pro Gerät mischen),
`fragenProSpieler` (Maßanzug/Portfolio: eigene Frage pro Spieler).

3. **`client/shared/minigames/<id>/index.ts`** — Default-Export nach
   `MinigameClientModule` (Datei `types.ts` daneben); die Registry findet ihn
   automatisch per Vite-Glob:

```ts
interface MinigameClientModule {
  id: string;
  renderScreen(view: unknown, host: HTMLElement, fx: FxApi): void;
  renderPlayer(view: unknown, host: HTMLElement, send: SendAction): void;
  renderGm?(view: unknown, host: HTMLElement, gm: GmApi): void;
  explainCard: { text: string; animation: TemplateResult };
}
```

Referenz zum Abgucken: `vier-lianen` (Server-Plugin, Client-Renderer, Tests in
`server/minigames/vier-lianen.test.ts`). WICHTIG (TECH-SPEC): Das Interface
wird erst NACH 4 verschiedenartigen Referenz-Minigames eingefroren — Änderungen
bitte über den Engine-Agent koordinieren. TODO offen: Contract-Test-Harness in
`_api/` (Serialisierbarkeit, Purity, Leak-Check automatisch für jedes Plugin).

## Andocken 2: Content-Loader (Content-Agent)

Der GESAMTE Fragen-Zugriff läuft über `server/content-loader/index.ts` (v1):

```ts
interface ContentLoader {
  loadPacks(): Promise<void>; // liest content/packs/**/*.json, wirft bei kaputten Packs
  pickQuestions(opts: PickOptions): Question[];
}
interface PickOptions {
  anzahl: number;
  usedQuestionIds?: string[]; // No-Repeat
  rng?: Rng; // injizierter Zufall (Fallback: deterministischer Seed)
  // ADDITIV (v1) — alles optional, die Engine ruft heute pickQuestions({ anzahl }):
  kategorien?: string[]; // Ober- ODER Unter-Slugs aus content/taxonomie.json
  schwierigkeiten?: ("easy" | "medium" | "hard" | "ultrahard")[];
  region?: string; // Region-Regler: "de" ⇒ global+de, "global" ⇒ nur global
  typen?: PlanFrageTyp[]; // Plan-Typen; choice4-fähig: choice, emoji, bild_pixel
}
```

Quelle sind die Pack-Dateien `content/packs/<ober>/<unter>.json` (Struktur:
`content/schema/frage.schema.json`; harte 14-Regeln-Prüfung:
`node tools/content/validate.mjs`; Lücken-Report: `node tools/content/stats.mjs`).
Stand W20: **1.300 validierte Fragen** in 43 Packs (0 Validator-Fehler;
der Content-Agent erweitert die Packs laufend — `node tools/content/stats.mjs`
liefert die aktuelle Zahl).
Plan-Schwierigkeiten leicht/mittel/schwer/ultrahard ⇒ easy/medium/hard/ultrahard.
pickQuestions liefert choice4-fähige Typen: `choice`, `emoji` (die Emojis
wandern in den Fragetext) und `bild_pixel` (Medien-Datei ⇒ `Question.media.bild`
als /media-URL); die übrigen 5 Plan-Typen liegen bereits validiert in den Packs
und werden freigeschaltet, sobald `shared/content.ts` weitere kinds kennt
(ADDITIV, mit Engine-Agent koordinieren). HowTos:
`docs/content/FRAGEN-SCHREIBEN.md` (Fragen-Agents) und
`docs/content/EIGENE-FRAGEN.md` (User).

**Medien-Pipeline (bild_pixel):** `medien.datei` im Pack zeigt repo-relativ
auf `assets/…` (z. B. `assets/img/generated/pixel/pixel_leuchtturm.png`,
Motive: `assets/img/generated/MANIFEST.md`); der Loader übersetzt das in eine
`/media/…`-URL, `server/core/http.ts` liefert repo-`assets/` als Express-Static
unter `/media` aus (Vite-Dev-Server proxied `/media` an :8080).
**Format-Content-Zuordnung** (`server/engine/plan.ts#passtFrageZuFormat`):
Fragen MIT `media` zieht NUR Pixel-Dschungel (dort bevorzugt — Platzhalter-SVGs
bleiben Fallback), alle anderen Formate meiden sie;
`server/rooms/room.ts#startMatch` mischt die bild_pixel-Fragen dem Match-Pool
garantiert bei. Wächter: `server/engine/format-content.test.ts`.

**Song-Packs (Musik-Agent, ADDITIV):** Der Song-Zugriff läuft ebenfalls über
den Content-Loader — Quelle ist `content/musik/songs.json` (Pipeline:
`node tools/musik/import.mjs`, HowTo: `docs/MUSIK-PACKS.md`; hartes Gate:
`node tools/musik/validate-songs.mjs`; kanonische Typen: `shared/songs.ts`):

```ts
interface ContentLoader {
  // … wie oben, plus (optional — Test-Fakes bleiben gültig):
  loadSongs?(): Promise<void>; // liest content/musik/songs.json; FEHLENDE Datei ⇒ 0 Songs
  pickSongs?(opts: PickSongsOptions): Song[];
}
interface PickSongsOptions {
  anzahl: number;
  usedSongIds?: string[]; // No-Repeat
  rng?: Rng;
  schwierigkeiten?: ("easy" | "medium" | "hard" | "ultrahard")[]; // Pack „leicht…" ⇒ Engine-Stufen
  region?: string; // "de" ⇒ global+de, "global" ⇒ nur global
  mitVideo?: boolean; // true ⇒ nur Songs mit medien.video3s (Stummfilm-Studio)
}
```

Fluss zu den Formaten (analog Fragen): `room.startMatch` zieht den Song-Pool
(`pickSongs`) und filtert die Playlist über `registry.allePluginsFuer({
songsVerfuegbar })` — ohne Songs fallen contentKind-`"songs"`-Formate via
`plan.aufloesen()` aufs Frage-Format zurück. Die Engine hält den Pool im
State (`songsPool`/`usedSongIds`, Save/Load-sicher) und befüllt beim init()
`ContentSlice.songs`: `songs[0]` = Ziel-Song (Rng-Wahl, No-Repeat, Recycle bei
erschöpftem Pool), Rest = Distraktoren-Pool (`server/engine/flow.ts`).
`medien`-Referenzen bleiben Pipeline-Pfade (`media/<id>/…`) — die Plugins
normalisieren beim init() über `shared/songs.ts#songMediaUrl`;
`server/core/http.ts` liefert `content/musik/media/` unter `/media-musik/*`
aus. Wächter: `server/content-loader/songs.test.ts` +
`server/engine/songs-slice.test.ts`.

## Andocken 3: Protokoll-Referenz (implementierter Kern)

Zod-Schemas in `shared/protocol.ts`; Wire-Format socket.io-Events:

| Nachricht               | Richtung  | Kern-Payload / Antwort                                                                                                         |
| ----------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `room.create`           | C→S (ack) | `{role, origin}` → `{ok, code, gmPin, qrPath}`                                                                                 |
| `hello`                 | C→S (ack) | `{roomCode, role, sessionToken?, name?, avatar?, gmPin?, origin?}` → `welcome {playerId, sessionToken, seq, view, serverTime}` |
| `view.snapshot`         | S→C       | `{seq, view}` — Voll-Snapshot der Rolle                                                                                        |
| `view.event`            | S→C       | `{seq, event}` — Deltas: `presence`, `answered`, `timer`                                                                       |
| `sync.request`          | C→S       | `{}` ⇒ erzwingt Snapshot (seq-Lücke = Selbstheilung)                                                                           |
| `time.ping`/`time.pong` | C↔S       | `{t0}` / `{t0, serverTime}` alle ~5 s (Offset + Liveness)                                                                      |
| `player.action`         | C→S (ack) | `{minigameId, actionId, payload, idemKey}`                                                                                     |
| `buzz`                  | C→S (ack) | `{minigameId, pressedAtServerEst, idemKey}` — Server clampt (Median-RTT) ⇒ Plugin-Action `{type:"buzz", finalAt}`              |
| `time.probe`            | S→C→S     | `{t}` — Client echot SOFORT zurück; Server misst Median-RTT pro Spieler (alle ~5 s)                                            |
| `joker.use`             | C→S (ack) | `{jokerId, stufe?, idemKey}` — Einsatzfenster/Preis prüft der Server                                                           |
| `joker.buy`             | C→S (ack) | `{jokerId, idemKey}` — Ladung nachkaufen (Preisformel + Sozialrabatt)                                                          |
| `kategorie.vote`        | C→S (ack) | `{kategorie}` — Kategorien-Wahl-Phase                                                                                          |
| `vote.cast`             | C→S (ack) | `{option}` — GM-Voting ODER Blitz-Stimmung (0–4)                                                                               |
| `phase.ready`           | C→S (ack) | `{was: "bereit" \| "streik"}` — Erklärkarte (alle bereit ⇒ früher; Streik-Mehrheit ⇒ Minispiel-Swap)                           |
| `rad.aktion`            | C→S (ack) | `{wahl: "long" \| "short" \| "umarmt" \| "ja" \| "nein"}` — Rad-Interaktionen                                                  |
| `feedback.text`         | C→S (ack) | `{text}` — Freitext-Feedback (GM-Werkzeug 14 / Abspann)                                                                        |
| `gm.cmd`                | C→S (ack) | `{cmd, args, cmdId}` → `gm.ack {cmdId, ok, error?}`                                                                            |
| `gm.log`                | S→GM      | `{entry}` — Aktions-Log-Eintrag                                                                                                |
| `room.presence`         | —         | (im Skeleton als `view.event` Typ `presence`)                                                                                  |
| `room.closed`           | S→C       | `{reason: "ttl" \| "gm-ende"}`                                                                                                 |

GM-Kommandos (KOMPLETT implementiert, `server/core/gm-commands.ts` ⇒
`server/engine/gm.ts`): `score.adjust {playerId, delta, grund, override?}`
(Soft-Cap ±20 % des Runden-Maximums) · `timer.extend {ms}` (max. 2/Frage) ·
`session.pause {text?, dauerMs?}` (Bananen-Pause mit Countdown auf allen
Geräten) / `session.resume` · `flow.next` (Universal-Weiter für JEDE Phase;
Lobby ⇒ Match-Start) · `settings.set {modus?, jokerAn?, rad?, kategorienWahl?,
autoGm?, kurzeShow?, finaleFaktor?}` (Modus nur in der Lobby) ·
`kategorie.pick {kategorie}` · `question.pick {questionId}` ·
`question.assign {playerId, questionId|null}` (Maßanzug) ·
`regal.filter {kategorie?, schwierigkeit?}` · `hint.global` (Tipp-Kanone,
−25 %/Stufe, max. 3) · `hint.whisper {playerId, text}` (NUR Ziel-Handy, max.
2/Runde) · `vote.start {frage, optionen, dauerMs?}` ·
`question.markBroken {grund, refund: "annul"|"grantAll"}` ·
`game.skip {keepPoints}` · `game.flagBuggy {grund}` ·
`player.punish {playerId, strafe: "bananensteuer"|"clown"}` (Anti-Mobbing:
nie 2× derselbe in Folge) · `player.boost {playerId, art: "x2"|"plus300"|
"joker", grund}` (Pflicht-Begründungs-Chip, max. 1/Spieler/Runde) ·
`joker.grant {ziel: playerId|"alle", jokerId}` (Budget 6 Chips/Session) ·
`wheel.spin {rigTarget?}` (nur im Zwischenstand; Rig bleibt geheim) ·
`mood.poll` (max. 3/Session) · `feedback.collect` · `flow.encore` (max.
2/Runde) · `sound.play {sfxId}` · `autogm.set {enabled}` · `session.ende`.

Zustandsmaschine (Engine v1): `lobby → intro → [pro Abschnitt:
kategorie-wahl? → erklaerkarte → (frage → aufloesung)×N → zwischenstand →
rad?] → … → siegerehrung → ende` (Tick alle 250 ms; Frage-Timer lebt im
Plugin-State; `paused` friert alles ein und verschiebt Deadlines beim Resume).
Der Match-Plan (`server/engine/plan.ts`) entsteht beim Start aus den
`MatchSettings` + Modi-Matrix (`shared/settings.ts`): Runden-Abschnitte
(Slot-Dramaturgie opener/aufbau/geld/konflikt/risiko), optional
Jackpot-Frage-Abschnitt (2.000 MM + Glas-Inhalt) und Finale-Abschnitt
(W_final = Formel §3.5, an alle angesagt). Jackpot/Finale laufen durch
DIESELBEN frage/aufloesung-Phasen (`view.abschnitt.typ` unterscheidet).
Wunsch-Minigames der Playlist, die (noch) nicht in der Registry sind, fallen
auf `vier-lianen` zurück. Rad-Modifier („nächste Frage"/„Runde") verwaltet
die Engine und reicht sie als `ContentSlice.mods` bzw. Buchungs-Faktoren
weiter. Auto-GM (Settings-Flag) übernimmt: Timer-Verlängerung wenn < 50 %
geantwortet, Kategorie-Auto-Pick nach Timeout, Drama-Rad-Dreh bei
davongezogenem Leader.

## Andocken 4: Meta-Modul (Profile · AT · Shop · Analytics · Saves · Bots)

Der gesamte Meta-Kram lebt in `server/meta/` und hängt über GENAU EINE
Schnittstelle am Spielbetrieb: `RoomMetaHooks` (in `server/rooms/room.ts`,
Instanz: `createMetaService(…)` aus `server/meta/index.ts`, verdrahtet in
`server/core/index.ts`). Räume/Engine kennen KEINE Meta-Interna:

- `profilJoin(profileId, {pin?, deviceToken?})` — Join MIT Profil (§7.1):
  `hello` darf statt `name` ein `profileId`+`profilPin`/`deviceToken` tragen;
  Name/Avatar kommen aus dem Profil-Store, der Slot wird per
  `room.bindeProfil(playerId, profileId)` gebunden. Gast-Join bleibt unberührt.
- `matchBeendet(room)` — feuert beim committeten `match_ended`: rechnet die
  AT-Umrechnung (Formel §3.6 aus `shared/economy.ts`) und bucht pro gebundenem
  Profil — idempotent über `gebuchteMatches` (matchId-Liste im Profil).
- `botTick(room)` / `gmMetaCmd(room, cmd, args)` — In-Prozess-Bots
  (`bot.add`/`bot.remove`, 5 Personas aus `shared/meta.ts`) und Save/Load
  (`save.write {slot}` / `save.load {slot}`) als GM-Kommandos AUSSERHALB des
  Engine-Katalogs (`gm-commands.ts` delegiert Unbekanntes an den Hook; Achtung:
  diese Acks sind Promises — `sockets.ts` wrappt mit `Promise.resolve`).
- `raumSchliesst(room, reason)` — Autosave: läuft ein Match beim TTL-Abbau
  noch, landet es in Slot 0 (`saves/autosave.json`).

**Save-Serialisierung (der vormals offene Punkt — ERLEDIGT):** Der Server-Rng
ist jetzt stateful (`shared/rng.ts#createStatefulRng`, Mulberry32 mit
`getState()`/`setState()`). Ein Save (`saves/slot-{1..3}.json`) trägt
`schemaVersion, roomCode, gmPin, matchId, seq, engineState, rngState,
sessions, profilBindungen, bots`. Beim Schreiben friert `friereEin` den State
als Pause AB `savedAt` ein (der bestehende Pause/Resume-Mechanismus verschiebt
dann beim `gm.resume` alle Deadlines — kein Timer läuft ab, während das Match
im Regal lag). Laden geht NUR aus der Lobby: der frische Raum übernimmt Code
(Re-Key über `RoomManager.schluessleUm`), PIN, matchId (Event-Log setzt die
SELBE Datei mit einem `match_loaded`-Marker fort), Sessions (Spieler-Rejoin
per altem Token) und Bot-Anbindungen. Roundtrip-Beweis inkl. „Neustart":
`server/meta/save-load.test.ts`.

**Stats-Pipeline:** Event-Log (JSONL) bleibt Single Source of Truth.
`server/analytics/aggregate.ts` materialisiert daraus `meta/stats.json`
(15 Spieler-Stats pro Profil + Fragen-Gesundheit + Feedback-Inbox) — läuft
alle 60 s + nach Match-Ende, verarbeitet nur neue/gewachsene Logs (Cursor je
Datei) und ist über Replay jederzeit neu aufbaubar. `reports.ts` destilliert
die 5 Admin-Reports (zu-oft-gespielt, Schwierigkeits-Drift mit
Umstufungs-Vorschlag nach CONTENT-PLAN §3, Fehlerhaft-Queue, Kategorie-Lücken,
Feedback-Inbox). Dashboard: `/admin` (server-gerendert, PIN aus `ADMIN_PIN` —
ohne Env-Wert ist die Route aus).

**HTTP-API (`server/meta/http-api.ts`):** `/api/meta/profile` (GET Liste per
`?device=`, POST anlegen, `:id/login`, `:id/karte`, `:id/update`),
`/api/meta/shop` + `:id/kaufe` + `:id/ruestung` (atomar über die
Promise-Kette des Profile-Stores), `/api/meta/boards` (die 4 Bestenlisten),
`/api/meta/uebung/*` (Übungsmodus: kategorien/frage/antwort/tipp/stats —
Spaced-Repetition-Gewichte in `shared/meta.ts`, Lernstand pro Profil ODER
Geräte-Token unter `meta/uebung/`), `/api/meta/saves`, `/api/meta/personas`,
`/api/admin/reports` (PIN-Header). Datenlayout: `meta/profiles.json` (EINE
atomare Datei, Mutationen strikt sequenziell), `meta/stats.json`,
`meta/uebung/*.json`, `saves/*.json`, `events/*.jsonl`.

**Client-Andockpunkte (chirurgisch):** `player/meta-join.ts` (Profil-Wahl im
Join-Flow; `hello` bekommt `profileId`/`profilPin`/`deviceToken` —
`shared/protocol.ts` ADDITIV erweitert), `landing/meta-landing.ts`
(Bestenlisten/Shop/Profil-Karte/Training als eigener Screen),
`gm/meta-gm.ts` (Bots + Save/Load im Cockpit), `client/shared/meta-avatar.ts`
(Kosmetik als SVG-Overlays auf die Gelenk-Puppen — Wire-Format
`affe.farbe.item1+item2`, drittes Segment ADDITIV; Match-Setting
`alltimeItems` schaltet die Extras pro Match ab, `ViewBase.alltimeItems`
liefert den Schalter an alle Renderer).

**META v2 — Level · Bananen-Pass · Quests (`shared/quests.ts` +
`server/meta/{level,season,quests}.ts`):**

- **Level** = Funktion der Lifetime-AT-EINNAHMEN (`at.gesamt`, Ausgeben senkt
  nie): Level n ab kumulativ `1.000 · n·(n+1)/2` AT (L1 = 1 k, L5 = 15 k,
  L10 = 55 k, L100 = 5,05 Mio. — nach oben offen). Helfer in
  `shared/meta.ts` (`levelFuerAt`/`atFuerLevel`/`levelFortschritt`). 10 Items
  sind zusätzlich level-gated (`ShopItem.minLevel`, geprüft in
  `server/meta/level.ts#kaufSperre`). Anzeige: das Level reist als
  Pseudo-Extra `lv<N>` im Avatar-Wire-Format mit
  (`don-bananas.gelb.hut-zylinder+lv7`) — `meta-avatar.ts#schmueckeName`
  macht daraus das kleine Badge neben dem Namen (Lobby/Podium/Profil-Karte).
- **Bananen-Pass** (Gratis-Track, KEIN Echtgeld): Saison = UTC-Kalendermonat
  (`saisonIdFuer` → „2026-08"), 30 Stufen (XP-Kosten: S1–10 je 100,
  S11–20 je 150, S21–30 je 200 ⇒ 4.500 XP gesamt). PASS-XP: Match beendet 50,
  Sieg +50, Daily-Quest 80, Monats-Quest 400. Belohnungen: AT-Boni + 4–6
  exklusive Saison-Cosmetics auf S5/10/15/(20)/25/30 (Saison 1
  „Dschungel-Auftakt" konkret, spätere Saisons generiert das Themen-Rad
  deterministisch aus `SAISON_THEMEN`; Lookup über `itemFuer`, das auch
  Saison-Items kennt). Saison-Ende: `season.ts` rollt beim ersten Zugriff im
  neuen Monat, nicht erreichte Stufen verfallen, Erreichtes wandert ins
  Archiv (`PassArchivEintrag`, Anzeige im Landing-Tab).
- **Quests**: 3 Dailys/Tag (deterministische Rotation aus ~20er-Pool per
  `dailyQuestIdsFuer(tagKey)`) + 3 Monats-Quests/Saison (inkl. „Erreiche
  Pass-Stufe 15", das der Quest-Store direkt am Pass-Stand misst).
  Fortschritt wird beim `matchBeendet`-Hook aus dem Event-Log des Matches
  gemessen: `verbucheMatchMeta` (in `server/meta/index.ts`) wartet auf den
  `match_ended`-Eintrag im JSONL, destilliert `matchFakten` pro Profil
  (rein/testbar in `shared/quests.ts`), verbucht Quests + XP + Belohnungen
  idempotent (matchId-Liste) und puffert das Ergebnis
  (`MatchMetaErgebnis`) für die Handy-Abfrage.
- **HTTP additiv**: `GET /api/meta/profile/:id/pass` (PassUebersicht für den
  Landing-Tab) + `GET /api/meta/profile/:id/match-meta` (Match-Ende-Ergebnis;
  `client/player/meta-ende.ts` pollt beim Phasenwechsel auf
  Siegerehrung/Ende und zeigt XP/Quest-Deltas/Level-Up + Konfetti).
- **Cosmetics v2** (`shared/meta.ts`, 51 Items): +10 Titel, 6 Banner
  (CSS-Gradients in `ShopItem.stil`, Renderer legt sie als Hintergrund
  hinter die Puppe), 4 Namens-Styles (`ShopItem.klasse`/`stil`,
  `meta-avatar.ts`-CSS), 2 neue Konfetti-Stile (partikel.ts: `muenzen`,
  `laub`). Pass-Exklusive tragen `passExklusiv: <saisonId>` und sind im
  Shop unverkäuflich.

## Offene Andock-Punkte (nächste Agents)

- **Engine-Agent (erledigt in v1):** Match-Plan/Slots, Ökonomie komplett
  (Streak/Speed/Jackpot/Rückenwind/W_final), Buzzer-Fairness-Modul, 7 Joker,
  Glücksrad (14 Segmente), 17 GM-Werkzeuge, Auto-GM, Bot-Personas+Chaos.
  Save-Serialisierung an Phasengrenzen: ERLEDIGT (Meta-Agent, Andocken 4).
  NOCH offen: Spectator-Rolle, Claim-Flow, Spät-Joiner, Buzzer-Minigame als
  Erstnutzer von `ctx.buzzer` (Modul unit-getestet, wartet auf Buzzer-Format).
- **Minigame-Agents (v1 erledigt):** alle 10 v1-Formate + lianen-finale sind
  implementiert. NOCH offen: ein echtes Buzzer-Format als Erstnutzer von
  `ctx.buzzer`; `ContentSlice.mods` unterstützen (mind. `timerFaktor`); danach
  Interface einfrieren + Contract-Test-Harness.
- **Content-Agent:** weitere Frage-Typen freischalten (mit Engine-Agent),
  Cooldown/Flags, Lizenz-Manifest.
- **Client-Agents (Polish):** Bühnen-Polish (2.5D, Partikel-Canvas via
  `FxApi`), Rad-Animation (echtes Rad statt Lauflicht — `RadView.ergebnisIndex`
  - `dreh.dauerMs` liegen bereit), Audio-Unlock/NoSleep (`shared/caps.ts`),
    Landing-Feinschliff, lazy Renderer-Registry. Die Phasen-Hüllen (Kategorie-
    Wahl, Erklärkarte, Rad, Siegerehrung, Joker-Leiste, GM-Cockpit) stehen
    funktional.
- **Test-Agent:** Playwright-E2E, Test-Wellen mit `tools/bots` (Personas +
  `--chaos` liegen bereit), CI-Workflows (`.github/workflows/ci.yml` fehlt).
- **Persistenz/Meta-Agent (erledigt, Andocken 4):** Save-Slots (3 + Autosave
  beim TTL-Abbau), Profile/AT/Shop, Bestenlisten, Aggregations-Job + /admin,
  Übungsmodus, In-Prozess-Bots. NOCH offen: `meta/rooms.json`-Wiederbelebung
  OFFENER Räume nach Neustart (laufende Matches gehen über die Save-Slots),
  Buzzer-Sound/Konfetti-Kosmetik im Match-Client hörbar/sichtbar machen
  (Besitz+Ausrüstung liegen im Profil, Avatar-Overlays sind angebunden),
  Bestenlisten-Rotation auf dem Screen-Client im Leerlauf.
