# G — Minigames komplett (Godot 4.4) — konkretes Design

Ideen-Improver G. Bereich: USER-WISHES §G (alle Punkte) + Anschlüsse: §A (Orientierung/
Postprocessing, Improver A §2/§6), §C (WS-Relay für PvP/Coop, Improver C §3.8), §D
(`cars.json`-Autostats, Improver D Kap. 7). Referenz-Web-Spiel: `/workspace/GOOBY` —
32 Spiele unter `src/minigames/games/`, **jedes mit purer `.logic.js`** (deterministisch,
Bot + Difficulty), Framework-Contract §E8 in `src/minigames/framework.js` (ctx mit
`rng/difficulty/onScore/onEnd/onStrike`), Metadaten in `src/data/minigames.js`
(Coin-Tabellen, Unlock-Level, Energie). Cover-Art liegt fertig in
`public/assets/covers/*.png` (31 nutzbar). `goobyWelt` wird ENTFERNT (§A-Wunsch).

---

## 1) Minigame-Framework in Godot

### 1.1 Szenen-/Dateistruktur

```
res://minigames/
├── framework/
│   ├── minigame_host.tscn/.gd     # DIE eine Rahmen-Szene (SceneRouter lädt sie)
│   ├── minigame_base.gd           # Basisklasse aller Spiel-Szenen (Contract §1.2)
│   ├── minigame_ctx.gd            # RefCounted-Ctx (rng, difficulty, score/end/strike)
│   ├── gooby_rng.gd               # mulberry32-Port — bit-identisch zum Web (§2.3)
│   ├── pregame.tscn/.gd           # Schwierigkeit + ORIENTIERUNG + Bestwerte + Cover
│   ├── countdown.tscn             # 3-2-1-LOS (erst NACH ready des Spiels)
│   ├── pause_menu.tscn            # Weiter / Neustart / Aufgeben
│   ├── results.tscn/.gd           # Score, Münzen (×2-Tagesbonus), Bestwert, Nochmal
│   └── juice_kit.gd + juice_layer.tscn   # Juice-Baukasten (§1.4)
├── registry.gd                    # id → Szenenpfad + Meta (aus JSON, §1.5)
└── games/<id>/<id>.tscn + <id>.gd # 1 Ordner pro Spiel (Darstellung)
res://logic/games/<id>_logic.gd    # PURE Ports der *.logic.js (node-frei, §2)
res://content/base/minigames/minigames.json   # Meta (Content-Pack, §B-updatebar)
```

**Host-Szenenbaum** (`minigame_host.tscn`):

```
MinigameHost (Node)
├── GameSlot: SubViewportContainer (stretch) └── SubViewport   ← Spiel-Szene landet HIER
├── HudLayer   (CanvasLayer 50): ScorePill, Timer, Streak-Toast, PauseBtn (safe-area)
├── JuiceLayer (CanvasLayer 90): 1 Fullscreen-ColorRect-Shader (Chroma/Vignette/Flash)
└── OverlayLayer (CanvasLayer 100): pregame / countdown / pause / results / rotate-gate
```

**Warum SubViewport für den GameSlot:** (a) Orientierungs-Fallback per 90°-Rotation des
Containers (§1.3), (b) Render-Scale auf schwachen Geräten (Viewport kleiner rendern als
UI), (c) Ende-Screenshot fürs Results-Panel/Fotoalbum, (d) 3D-Spiele und 2D-Spiele
identisch gehostet. HUD/Overlays bleiben AUSSERHALB → immer scharf, immer richtig herum.

### 1.2 Contract (Analog §E8, aber Godot-idiomatisch: Signale statt Callbacks)

```gdscript
# minigame_base.gd
class_name MinigameBase extends Node
## Jede Spiel-Szene erbt hiervon. Lifecycle gehört dem Host:
## instanzieren → setup(ctx) → await ready_for_countdown → start() → … → teardown()

var ctx: MinigameCtx                      # vom Host VOR add_child gesetzt

func setup(_ctx: MinigameCtx) -> void: pass   # Assets/Level bauen (async ok)
func start() -> void: pass                    # Countdown fertig → Input freigeben
func set_paused(_p: bool) -> void: pass       # Host pausiert Tree; Hook für Audio o. Ä.
func apply_view(_size: Vector2) -> void: pass # Resize/Rotation (Pflicht! §1.3)
func teardown() -> void: pass                 # vor queue_free
```

```gdscript
# minigame_ctx.gd
class_name MinigameCtx extends RefCounted
var game_id: StringName
var difficulty: StringName        # &"easy"|&"normal"|&"hard"|&"endless" (Policy wie Web:
                                  # effectiveDifficulty — Trips/ausgenommene Spiele = normal)
var params: Dictionary            # mode:"shopTrip" etc., modifier, seed-Override (Tests)
var rng: GoobyRng                 # mulberry32, geseedet vom Host (deterministisch!)
var view_size: Vector2            # Größe des SubViewports (NICHT Window!)
var orientation: StringName       # &"portrait"|&"landscape" — die GEWÄHLTE für diesen Run
var juice: JuiceKit               # §1.4
var hud: MinigameHud              # Score-Anzeige, Timer-Anzeige, Toasts
var audio: AudioDirector          # (Autoload-Ref) SFX/Musik-Ducking
signal score_changed(total: int)
func score(points: int) -> void   # Host akkumuliert, HUD-Pulse, floor 0
func strike() -> int              # 3-Strikes-Teleport (Port von applyStrike/POLISH-E)
func end(result := {}) -> void    # {score?:int, coins_override?:int, meta?:Dictionary}
```

Der Host besitzt (wie `framework.js`): Energie-Abzug, Coin-Berechnung
(`applyDifficultyCoinBase`-Port: `clamp(floor(score/divisor),min,max) × {0.7,1,1.3}`,
Endlos flat 5, Tages-×2 danach), Bestwert-Schreiben pro Modus (`best`/`bestByDiff`/
`endlessBest`), Endlos-Lock (`beaten.hard && level ≥ 10`), 3-Strikes-Teleport-Cutscene,
Pause bei `NOTIFICATION_APPLICATION_PAUSED` (App in Hintergrund → auto-Pause, nie Score-
Verlust). Spiel-Szenen kennen NIE Save/Economy — nur `ctx`.

### 1.3 Orientierung (der §G-Kernwunsch) — konkretes Godot-Design

**Entscheidung: 3-stufig — echtes OS-Lock zuerst, SubViewport-Rotation als Fallback,
Layout-Umschaltung im Spiel als Pflicht.**

1. **Wahl-UI:** Im Pregame-Panel (bei der Schwierigkeitswahl, exakt wie gewünscht) ein
   3-fach-Toggle: `[Hochkant] [Quer] [Wie Settings]` mit Handy-Icons. Default beim ersten
   Öffnen = Empfehlung des Spiels (Port-Tabelle §3, Spalte „Orient."). Gespeichert pro
   Spiel: `save.minigames.prefs[id] = { orientation: "portrait"|"landscape"|"global" }`.
   Global: `settings.minigame_orientation` (Default `landscape` — QUERFORMAT ist ab
   jetzt bevorzugt, §A). Web-Analog: `normalizeOrientation`/`orientationLockFor` aus
   `framework.logic.js` — wird 1:1 als `logic/orientation_logic.gd` geportet + getestet.
2. **OS-Lock (Primärweg):** Improver A's `OrientationService.lock(mode)` →
   `DisplayServer.screen_set_orientation(SCREEN_SENSOR_LANDSCAPE | SCREEN_SENSOR_PORTRAIT)`
   beim Countdown-Start; `SCREEN_SENSOR` (bzw. globale App-Policy) bei exit/results.
   iOS-Voraussetzung: Info.plist erlaubt alle 4 Lagen (A §R1). „Sensor-Landscape" statt
   hart „Landscape": beide Quer-Lagen bleiben nutzbar (Geräterotation!, §A-Wunsch).
3. **Rotate-Gate:** Passt die echte Fensterlage nicht zur Wahl (Lock verboten/fehlge-
   schlagen, z. B. iOS-Rotationssperre des Users), zeigt der Host VOR dem Countdown den
   „Bitte dreh dein Handy 🔄"-Overlay (Port von `shouldShowRotateGate`; quadratisch zählt
   als Hochkant). Nach 3 s ohne Drehung erscheint zusätzlich der Button **„Trotzdem
   spielen"** → Stufe 4.
4. **SubViewport-Fallback (der Godot-Trick):** `GameSlot.rotation = ±90°`, SubViewport-
   Größe getauscht (w↔h), Pivot Mitte. Das Spiel sieht via `ctx.view_size` eine ganz
   normale Quer-Auflösung — es merkt den Fallback NICHT. Touch-Input wird vom
   SubViewportContainer automatisch mittransformiert (Godot macht das für push_input).
   HUD/Overlays rotieren mit (eigener Rotations-Container im HudLayer), damit Score
   lesbar bleibt.
5. **Layout-Pflicht `apply_view(size)`:** Jedes Spiel MUSS mit beiden Seitenverhält-
   nissen leben: 2D → `Camera2D`-zoom-to-fit auf eine Design-Spielfläche (z. B. 1280×720
   quer / 720×1280 hoch) + UI-Anker; 3D → FOV/Distanz aus Aspekt (`keep_height` quer,
   `keep_width` hoch). Spiele mit ECHT anderem Layout pro Lage (GvZ! §4) bekommen zwei
   Layout-Presets und schalten in `apply_view` um. Mid-Round-Rotation (nur bei „Wie
   Settings"+Sensor möglich): Host pausiert 0,3 s, ruft `apply_view`, blendet weich.

### 1.4 Juice-Baukasten (`JuiceKit`) — mobile-tauglich

Ein RefCounted pro Run, vom Host verdrahtet mit Kamera, JuiceLayer-Shader und
WorldEnvironment (nur 3D-Spiele). API (alles fire-and-forget, intern getweent):

```gdscript
juice.hit_freeze(ms := 70)        # Engine.time_scale=0.05; Timer ignoriert time_scale
juice.shake(amp := 6.0, dur := .3)# Kamera-Offset-Noise (Trauma-Decay-Modell)
juice.slowmo(scale := .3, dur:=.6)# Zeitlupe (Results-Slam, letzte Sekunde)
juice.bloom_pulse(strength := .8) # s. unten
juice.chroma(amount := 2.5, dur := .25)   # Chromatic Aberration Moment (Treffer/Combo)
juice.flash(color := WHITE, a := .35)     # 1-Frame-Blitz
juice.vignette_pulse()                    # Herzschlag-Vignette (Endlos-Gefahr)
juice.confetti(pos, n := 40)      # gepoolte GPUParticles2D/3D
juice.haptic(ms := 12)            # Input.vibrate_handheld (iOS: leicht)
juice.number_pop(pos, "+6", tint) # fliegende Punktzahl (gepoolte Label)
```

**Technik + Mobile-Budget:**

- **Fullscreen-Effekte** (Chroma/Vignette/Flash) = EIN gemeinsamer CanvasItem-Shader auf
  dem JuiceLayer-ColorRect (`hint_screen_texture`), Parameter-Uniforms getweent. Chroma =
  3 Texture-Reads mit radialem UV-Offset — auf A12+ irrelevant. Regel: **maximal dieser
  eine Fullscreen-Pass**; ist alles idle (alle Uniforms 0) → `visible = false` (kein
  Pass, keine Kosten).
- **Bloom:** 3D-Spiele → `WorldEnvironment`-Glow (A §6 liefert `env_minigame_punchy.tres`),
  `bloom_pulse` tweent `glow_intensity` 0.4→1.2→0.4 (0,4 s). 2D-Spiele: Godot-4-Glow auf
  2D braucht **HDR-2D** (`rendering/viewport/hdr_2d`) — kostet auf Mobile echten
  Bandbreiten-Aufschlag. Entscheidung: HDR-2D **AN nur innerhalb des Minigame-
  SubViewports** (`use_hdr_2d = true` pro Viewport, nicht global!) und nur für Spiele
  mit `meta.glow2d = true` (GvZ, ghostHunt, lanternFloat, rocketRescue, starHopper,
  bubblePop). Alle anderen 2D-Spiele faken den Puls per additivem „Glow-Sprite"
  (vorgeblurte Textur, Scale/Alpha-Tween) — sieht bei Einzeltreffern identisch aus.
- **Reduced Motion:** globales Setting `settings.reduced_motion` (+ iOS-Systemflag via
  `DisplayServer`-Check wo verfügbar). Mapping IM JuiceKit (Spiele müssen nichts tun):
  shake→flash(0.15), hit_freeze→flash, chroma→aus, slowmo bleibt (kein Motion-Problem),
  confetti n/4, vignette_pulse→statisch. So erfüllt JEDES Spiel den Wunsch automatisch.
- **Standard-Verdrahtung im Host** (Spiele kriegen Juice geschenkt): `score()` mit
  points ≥ „groß" → number_pop + kleiner bloom_pulse; `strike()` → shake + chroma;
  Countdown „LOS!" → flash; Results-Einflug → slowmo + confetti. Spiele dürfen
  zusätzlich selbst rufen (z. B. teaParty-Perfect → hit_freeze(50) + haptic).

### 1.5 Meta-Registry als Content-Pack

`minigames.json` (Basis-Pack, per Auto-Updater §B überschreibbar): pro Spiel
`{ id, titel_de, cover, scene, logic, minLevel, coinTable:{divisor,min,max}, energie,
orientDefault, kategorie, glow2d, difficulty:{…Tuning-Multiplikatoren…} }`. Die
Difficulty-Zahlen wandern AUS dem Code IN dieses JSON (Web hatte sie als `Object.freeze`
im Modul) → **Balancing ohne App-Update** (§B-Wunsch). `registry.gd` validiert beim Boot:
jede id hat Szene+Logic+Cover, sonst „Bald verfügbar"-Kachel (Web-Verhalten).
Cover: alle 31 PNGs aus `public/assets/covers/` werden übernommen (GvZ, GOB NOM: neu
generieren — Bilder generieren ist erlaubt/erwünscht). Arcade-Preloading der Cover beim
Szenenaufbau fixt den „alte Icons flackern kurz"-Bug (§A-Wunsch) strukturell.

---

## 2) Port-Strategie `.logic.js` → GDScript

### 2.1 Warum das trivialer ist als es klingt

Die `.logic.js` sind bereits: node-frei, deterministisch (injizierter `rng`), Difficulty
als Datenzeilen, Bot als `simulate*Autoplay(mode, seed)`. Das ist EXAKT das
`RefCounted + static func`-Muster aus Improver A §1.1 (`logic/` node-frei). GDScript hat
64-bit-Floats wie JS-Doubles → Mathe ist bit-kompatibel portierbar.

### 2.2 Mechanische Übersetzungsregeln

| JS | GDScript |
|---|---|
| `export const TEA = Object.freeze({...})` | `const TEA := {...}` (Dictionary-const; Mutation-Guard im Test) |
| `export function f(a, b = X)` | `static func f(a, b := X)` |
| `rng()` (Closure 0..1) | `rng.randf()` auf `GoobyRng` (mulberry32-Port, §2.3) |
| `a ?? b` / `obj?.x` | `dict.get("x", b)` / `if d is Dictionary` Defensiv-Reader |
| `Math.max/min/floor` | `maxf/minf/floorf` (bzw. `maxi/…` für ints) |
| `Object.freeze({...spread, k:v})` | `tune.duplicated()` + Key-Assign (Helper `Tune.derive`) |
| camelCase | snake_case (Konvertierungs-Checkliste pro Datei) |

Ein Hilfs-Skript `tools/port_scaffold.py` (einmalig) übersetzt 80 % mechanisch
(Konstanten-Blöcke, Signaturen, JSDoc→Docstring); Handarbeit bleibt für Semantik.

### 2.3 `GoobyRng` — bit-identisch zum Web

`framework.js` nutzt mulberry32. Port als `gooby_rng.gd` mit int32-Arithmetik
(GDScript-`int` ist 64 bit → nach jedem Schritt `& 0xFFFFFFFF` maskieren, `imul` als
`(a * b) & 0xFFFFFFFF` mit Vorzeichen-Korrektur). **Gewinn:** die Zertifizierungs-Bots
liefern mit gleichem Seed DIESELBEN Scores wie im Web → der Port ist per Zahlenvergleich
beweisbar korrekt (§2.5), und Difficulty-Targets aus dem Web gelten weiter.

### 2.4 Portmuster einmal durchdekliniert: `teaParty.logic.js` → `tea_party_logic.gd`

```gdscript
# res://logic/games/tea_party_logic.gd — PURE (node-frei). Port von teaParty.logic.js.
# Mechanik: HOLD-to-pour; Loslassen im Band = perfect(+6)/good(+3); Überlauf = Patzer;
# jeder 3. Perfect in Folge +2. Tuning-Zahlen kommen zur Laufzeit aus minigames.json.
class_name TeaPartyLogic
extends RefCounted

const TEA := {
    duration_sec = 60.0, fill_rate = 0.5,
    band_center_min = 0.55, band_center_max = 0.85,
    band_half_w = 0.075, perfect_half_w = 0.028,
    perfect_pts = 6, good_pts = 3, streak_every = 3, streak_bonus = 2,
    serve_sec_start = 1.7, serve_sec_end = 1.1,
    overflow_level = 1.0, endless = false, endless_max_spills = 3,
    autoplay_aim_err = 0.06,
}

const DIFFICULTY := {
    easy = { fill = 0.8, band = 1.25, duration = 1.2, serve = 1.0, bot_err = 0.05 },
    hard = { fill = 1.2, band = 0.8, duration = 1.0, serve = 0.85, bot_err = 0.068 },
    endless = { fill = 1.2, band = 0.8, duration = 1.0, serve = 0.85, bot_err = 0.068 },
}

static func apply_difficulty(tune: Dictionary, mode: StringName) -> Dictionary:
    if mode == &"normal" or not DIFFICULTY.has(mode): return tune
    var row: Dictionary = DIFFICULTY[mode]
    var t := tune.duplicate()
    t.duration_sec *= row.duration; t.fill_rate *= row.fill
    t.band_half_w *= row.band;      t.perfect_half_w *= row.band
    t.serve_sec_start *= row.serve; t.serve_sec_end *= row.serve
    t.autoplay_aim_err = row.bot_err; t.endless = (mode == &"endless")
    return t

static func roll_band(rng: GoobyRng, tune := TEA) -> Dictionary:
    var c: float = tune.band_center_min \
        + rng.randf() * (tune.band_center_max - tune.band_center_min)
    return { center = c, half = tune.band_half_w, perfect_half = tune.perfect_half_w }

static func fill_after(level: float, dt: float, tune := TEA) -> float:
    return maxf(0.0, level) + tune.fill_rate * maxf(0.0, dt)

static func pour_result(level: float, band: Dictionary, tune := TEA) -> Dictionary:
    var overflow: bool = level >= tune.overflow_level
    var dist: float = absf(level - band.center)
    if not overflow and dist <= band.perfect_half:
        return { result = &"perfect", points = tune.perfect_pts, overflow = false }
    if not overflow and dist <= band.half:
        return { result = &"good", points = tune.good_pts, overflow = false }
    return { result = &"miss", points = 0, overflow = overflow }

static func streak_bonus_at(streak: int, tune := TEA) -> int:
    return tune.streak_bonus if streak > 0 and streak % tune.streak_every == 0 else 0

static func serve_interval_at(elapsed: float, duration: float, tune := TEA) -> float:
    var t := clampf(elapsed / duration, 0.0, 1.0)
    return tune.serve_sec_start + (tune.serve_sec_end - tune.serve_sec_start) * t

static func simulate_autoplay(mode := &"normal", seed := 1) -> Dictionary:
    var tune := apply_difficulty(TEA, mode)
    var rng := GoobyRng.new(seed)          # mulberry32 — Web-Seed-kompatibel
    var elapsed := 0.0; var score := 0; var cups := 0; var spills := 0; var streak := 0
    var limit: float = 600.0 if tune.endless else tune.duration_sec
    while elapsed < limit and not (tune.endless and spills >= tune.endless_max_spills):
        var band := roll_band(rng, tune)
        var level: float = band.center + (rng.randf() * 2.0 - 1.0) * tune.autoplay_aim_err
        var res := pour_result(level, band, tune)
        score = maxi(0, score + res.points)
        if res.result == &"perfect":
            streak += 1; score += streak_bonus_at(streak, tune)
        else:
            streak = 0
            if res.result == &"miss": spills += 1
        cups += 1
        elapsed += level / tune.fill_rate + serve_interval_at(elapsed, tune.duration_sec, tune)
    return { seed = seed, mode = mode, score = score, cups = cups,
             spills = spills, elapsed = elapsed }
```

Die Szene `games/tea_party/tea_party.gd` (erbt `MinigameBase`) hält NUR: Tassen-Sprites,
Füllstand-Shader, Input (`_gui_input` Hold/Release), ruft `TeaPartyLogic.*` und
`ctx.score/juice`. Muster gilt für alle 30 weiteren Ports — 1 Logic-Datei, 1 Szene.

### 2.5 Bot-Tests headless (Zertifizierung)

- `godot --headless -s res://tests/run_tests.gd` (A §9 Runner). Pro Spiel eine
  `test_<id>_logic.gd`: (1) Unit-Asserts der Pure-Funktionen (aus den Web-Tests
  übernommen), (2) **Bot-Zertifizierung**: `simulate_autoplay` über Seeds 1..50 ×
  {easy,normal,hard,endless} → Score-Median muss im Zielband der Difficulty-Targets
  liegen (Web-Tabelle `difficultyTargets` wird mitportiert als JSON).
- **Einmalige Cross-Zertifizierung:** `tools/cross_check.mjs` läuft in Node über die
  ORIGINAL-`.logic.js` mit denselben Seeds und schreibt `expected/<id>.json`; der
  Godot-Test vergleicht exakt (int) bzw. mit ε=1e-9 (float). Nach bestandener
  Zertifizierung wird die Datei ins Repo committet → Regressionsschutz für immer,
  auch wenn `/workspace/GOOBY` irgendwann wegfällt.
- CI (GitHub Actions): Headless-Godot-Job vor jedem IPA-Build (§Prozess).

---

## 3) Port-Tabelle — 32 Spiele → Kategorie / Priorität / Orientierung

Kategorien: **C** = Control-UI (kein Weltraum nötig), **2D** = Node2D+Camera2D,
**2D-P** = Node2D mit Physik, **2D-L** = Node2D mit Light2D, **3D** = volle 3D-Szene,
**3D-lite** = 3D mit fixer Kamera/Diorama. Orient = Empfehlungs-Default im Pregame
(wählbar bleibt IMMER beides). M1 = die 10 einfachsten/beliebtesten zuerst.

| # | id | DE-Titel | Kat. | Orient | Prio | Notizen |
|---|---|---|---|---|---|---|
| 1 | carrotCatch | Karottenfang | 2D | Hoch | **M1** | Fallende Objekte, idealer Erst-Port |
| 2 | bunnyHop | Hasenhüpfer | 2D | Hoch | **M1** | One-Tap-Timing |
| 3 | goobySays | Gooby sagt | C | Hoch | **M1** | Simon-Says, reine UI |
| 4 | memoryMatch | Memory | C | Hoch | **M1** | GridContainer + Flip-Tween |
| 5 | teaParty | Teestube | 2D | Hoch | **M1** | **Referenz-Port §2.4** |
| 6 | hideSeek | Guck-Guck-Garten | 2D | Quer | **M1** | Kleinste Logic (163 LOC) |
| 7 | basketBounce | Korbwurf | 2D-P | Hoch | **M1** | Flick-Wurf, RigidBody2D |
| 8 | pancakeTower | Pancake-Turm | 2D | Hoch | **M1** | Stapel-Timing |
| 9 | veggieChop | Gemüse-Schnippler | 2D | Quer | **M1** | Swipe-Slices, Juice-Vorzeige-Spiel |
| 10 | bubblePop | Blasen-Platzer | 2D | Hoch | **M1** | glow2d-Kandidat |
| 11 | carrotGuard | Karottenwache | 2D | Quer | M2 | Mini-Defense (GvZ-Vorstudie!) |
| 12 | gardenRush | Garten-Hektik | 2D | Quer | M2 | |
| 13 | burgerBuild | Burger-Meister | C | Hoch | M2 | Zutaten-Reihenfolge |
| 14 | trampoline | Trampolin-Tricks | 2D | Hoch | M2 | |
| 15 | goalieGooby | Torwart-Gooby | 2D | Quer | M2 | |
| 16 | fishingPond | Angelteich | 2D | Hoch | M2 | |
| 17 | danceParty | Tanzparty | 2D | Hoch | M2 | Rhythmus; Audio-Latenz-Kalibrierung! |
| 18 | snailMail | Schneckenpost | 2D | Quer | M2 | |
| 19 | lanternFloat | Laternenfluss | 2D | Hoch | M2 | glow2d (Laternen!) |
| 20 | pipeFlow | Rohr-Dreher | C | beide | M2 | Puzzle, aspektneutral |
| 21 | purblePlace | Tortenwerkstatt | C | Quer | M2 | größte C-Logic (1179 LOC) |
| 22 | ghostHunt | Geisterjagd | 2D-L | Quer | M2 | PointLight2D-Taschenlampe = Juice |
| 23 | rocketRescue | Raketen-Rettung | 2D-P | Hoch | M2 | **Weltraum §7**; glow2d |
| 24 | starHopper | Sternenhüpfer | 3D-lite | Hoch | M2 | **Weltraum §7**; 3 Lanes |
| 25 | runner | Gooby-Renner | 3D-lite | Hoch | M2 | Lane-Runner |
| 26 | harborHopper | Hafenhüpfer | 3D-lite | Hoch | M2 | Frogger-Grid |
| 27 | miniGolf | Minigolf | 3D-lite | Quer | M2 | Diorama-Bahnen |
| 28 | cityDrive | Einkaufsfahrt | 3D | Quer | M2 | **Fahr-Spiel §6**; Trip-Semantik, KEINE Difficulty (Web-Regel) |
| 29 | deliveryRush | Liefer-Flitzer | 3D | Quer | M2 | **Fahr-Spiel §6** |
| 30 | toyRacer | Spielzeug-Grand-Prix | 3D | Quer | M2 | **Fahr-Spiel §6**; größte 3D-Logic |
| 31 | shoppingSurf | Einkaufs-Surfer | 3D | Hoch | M2 | Flaggschiff (1311 LOC), zuletzt |
| 32 | goobyWelt | — | — | — | **ENTFÄLLT** | Gaussian Splats raus (§A); Cover archivieren |
| N1 | gvz | Goobys vs Zombies | 2D | Quer | **M1.5** | NEU §4 — eigener Track parallel zu M2 |
| N2 | gobNom | GOB NOM | 2D-P | Hoch | M2 | NEU §5 |

Reihenfolge-Begründung M1: nur C/2D ohne Sonderfälle → Framework + Juice + Orientierung
reifen an 10 kleinen Spielen, BEVOR die 3D-/Physik-Schwergewichte kommen. `carrotGuard`
früh in M2 als Mechanik-Vorstudie für GvZ (Lane-Defense-Verwandtschaft).

---

## 4) GOOBYS VS ZOMBIES (NEU — Flaggschiff)

### 4.1 Grundgerüst

- **Feld:** Quer-Layout 5 Reihen × 9 Spalten (Zombies laufen rechts→links auf Goobys
  Gartenhaus zu). Hochkant-Layout: identische Logik, Feld 90° konzeptuell gedreht —
  5 Spalten × 7 sichtbare Reihen, Zombies oben→unten (Grid-Logik ist achsenagnostisch:
  `lane` + `progress 0..1`; nur die Szene mappt anders). Coop: 6 Reihen (§4.6).
- **Ressource: NUTELLA** (statt Sonnen). Vom Himmel fallen „Nutella-Kleckse" (+25, alle
  ~10 s, antippen; zerlaufen nach 8 s), Nutella-Sammler-Goobys produzieren (+25/24 s).
  Nacht-Level: kein Himmels-Klecks → Sammler Pflicht.
- **Loop:** Wellen aus `levels/*.json`; „RIESIGE WELLE!"-Banner; verloren, wenn ein
  Zombie die Haustür erreicht (letzte Verteidigung: 1× „Rasenmäher" pro Reihe =
  **Nutella-Dampfwalze**, rollt die Reihe frei).
- **Szene:** Node2D + `gvz_board.gd`; Türme/Zombies gepoolte Sprite2D-Rigs mit 2-3
  Frame-Animationen + Squash-Tweens; glow2d an (Projektile leuchten). Logik komplett in
  `logic/games/gvz_logic.gd` (tick-basiert, 20 Hz Fixed-Tick, deterministisch — Pflicht
  für PvP/Coop-Relay §4.5 und Bot-Tests).

### 4.2 Gooby-Türme (12 + 1 Code-Bonus; Kosten in Nutella)

| Name (DE) | Kosten | HP | Fähigkeit | ab Level |
|---|---|---|---|---|
| **Nutella-Sammler-Gooby** | 50 | 300 | Produziert 25 Nutella / 24 s (hält Glas hoch, leckt ab und zu — Idle-Gag) | L2 |
| **Möhrenschütze** | 100 | 300 | Schießt Möhren: 20 Schaden / 1,4 s | L1 |
| **Dicker Bert** | 50 | 4000 | Wall-Gooby; futtert gemütlich, macht Grimassen wenn angeknabbert (3 Schadens-Stufen) | L3 |
| **Schnarch-Knolle** | 25 | 300 | Kartoffel-Mine: schläft 14 s ein („zzz"), dann 1-Hit-KO auf 1 Zelle | L4 |
| **Boom-Beere** | 150 | — | Einmal-Explosion 3×3, 1800 Schaden, Konfetti-Overkill | L5 |
| **Eis-Gooby** | 175 | 300 | Frost-Möhren: 20 Schaden + 50 % Slow für 3 s | L7 |
| **Doppelmöhre** | 200 | 300 | 2 Möhren pro Salve (40/1,4 s) | L8 |
| **Magnet-Gooby** | 100 | 300 | Klaut Eimer/Helme/Schilder (12 s Cooldown) | L10 |
| **Trampolin-Gooby** | 125 | 300 | Katapultiert den vordersten Zombie zurück an den Reihenstart (3 Ladungen) | L11 |
| **Pust-Gooby** | 150 | 300 | Ventilator: holt Ballon-Zombies runter + 20 % Lane-Slow-Aura | L12 |
| **Sternchen-Gooby** | 140 | 300 | Schießt Sterne in eigene + beide Nachbar-Reihen (15 Schaden) | L13 |
| **Melonen-Meier** | 300 | 300 | Lobber über Schilde: 80 Schaden + 1×3-Splash / 3 s | L14 |
| **Goldi** ✨ | 75 | 300 | Produziert 50 Nutella/24 s — NUR per Einlöse-Code (§B-Codes-Anbindung!) | Code |

### 4.3 Zombie-Typen (10 + Boss)

| Name (DE) | HP | Tempo | Eigenheit |
|---|---|---|---|
| **Schlurfi** | 200 | 1,0 | Basis; verliert witzig Kleidungsteile bei Schaden |
| **Hütchen-Zombie** | 200+370 | 1,0 | Pylonen-Hut als Rüstung |
| **Sprinter** | 150 | 2,0 | Joggt; Kopfhörer auf |
| **Eimer-Zombie** | 200+1100 | 1,0 | Eimer; Magnet-Gooby klaut ihn |
| **Zeitungs-Opa** | 150+150 | 0,8→2,5 | Zeitung kaputt → WUTMODUS (rennt, schimpft) |
| **Türsteher** | 200+600 | 0,9 | Frontschild blockt Geschosse; Lobber/Stern umgehen |
| **Hüpf-Zombie** | 250 | 1,2 | Überspringt den ERSTEN Gooby (1×); Trampolin kontert |
| **Maulwurf-Zombie** | 250 | 1,0 | Gräbt unter allen durch, taucht hinten auf, frisst rückwärts |
| **Ballon-Zombie** | 150 | 1,1 | Schwebt über alles; nur Pust-/Sternchen-Gooby treffen |
| **Brocken** | 3000 | 0,5 | Riese: zerquetscht Goobys (1 Hit), wirft bei 50 % einen Mini-Schlurfi |
| **Zombie-König Knurps** (Boss) | 3 Phasen | — | L15: fährt im Müllwagen quer, wirft Mülltonnen (zerstören 1 Zelle), ruft Wellen; Phasenwechsel = Wagen qualmt mehr |

### 4.4 Kampagne — 15 Level (jedes Level 1 neue Mechanik)

| Lvl | Setting | Neu (Mechanik/Turm) | Neu (Gegner) | Kurve |
|---|---|---|---|---|
| 1 | Vorgarten, 1 Reihe | Tutorial: Nutella tippen, Möhrenschütze | Schlurfi | sanft |
| 2 | 3 Reihen | Nutella-Sammler (Ökonomie!) | mehr Schlurfis | sanft |
| 3 | 5 Reihen (voll) | Dicker Bert | Hütchen | leicht |
| 4 | Vorgarten | Schnarch-Knolle | Sprinter | leicht |
| 5 | Vorgarten | Boom-Beere; 1. „RIESIGE WELLE!" | Eimer | Spitze |
| 6 | **Nacht** | kein Himmels-Nutella | Zeitungs-Opa | Ökonomie-Druck |
| 7 | Nacht | Eis-Gooby | Hüpf-Zombie | mittel |
| 8 | Nacht | Doppelmöhre | Türsteher | mittel |
| 9 | Garage | **Förderband**: vorgegebene Goobys statt Nutella | Mix | Denk-Level (Verschnaufer) |
| 10 | Garage | Magnet-Gooby; **Mid-Boss** | Maulwurf + 1 Brocken | Spitze |
| 11 | Garten | Trampolin-Gooby; **Nebel** (rechte 3 Spalten verdeckt) | Mix | Info-Druck |
| 12 | Garten | Pust-Gooby | Ballon-Zombie | mittel |
| 13 | Garten, **Regen** | Sternchen-Gooby; Regen: Zombies +10 % Tempo, Kleckse zerlaufen schneller | alle | hoch |
| 14 | Dach | Melonen-Meier (Pflicht: Schilde/Distanz) | 2 Brocken, 3 Riesen-Wellen | fast max |
| 15 | Straße | **BOSS** Knurps; Hybrid Förderband + Nutella | Boss + alles | Finale |

Sieg pro Level: Münzen (Coin-Row `divisor 4 / min 6 / max 30`) + 1× Sticker bei L5/10/15
(§H-Sticker-Anbindung). Level-Select-Karte mit Sternen (1–3 nach verlorenen Dampfwalzen).

### 4.5 PvP („einer Goobys, einer Zombies") — via WS-Relay (Improver C §3.8)

- **Netzmodell:** Host-autoritativ, Event-Relay `mg:<uuid>`-Room. Beide Clients führen
  die deterministische 20-Hz-Simulation; es fliegen NUR Aktionen
  (`{n, PLACE, cell/lane, type}`) mit Sequenznummer; Host-Snapshot alle 2 s als
  Drift-Korrektur (exakt C's Empfehlung — quasi rundenbasiert, latenzunkritisch).
- **Zombie-Seite:** Ressource **„Matsch"** — tropft automatisch (15/10 s, steigert sich
  alle 45 s um +5 → natürliche Eskalation, Spiel endet IMMER). Platzierung nur am
  rechten Rand (Reihenwahl). Kosten: Schlurfi 25, Sprinter/Hütchen 75, Opa 100,
  Eimer/Türsteher 125, Hüpfer/Maulwurf/Ballon 150, Brocken 400; Cooldown pro Typ.
- **Sieg:** Zombie-Spieler gewinnt, wenn ein Zombie die Tür erreicht (Dampfwalzen aus im
  PvP); Gooby-Spieler gewinnt, wenn er 3:30 min übersteht. **Best-of-3 mit Seitentausch**
  löst die Asymmetrie-Fairness. Emotes (§C-Brettspiel-Emotes) funktionieren auch hier.

### 4.6 Coop — 15 Level

- Feld 6 Reihen: Spieler A Reihen 1–3 (oben), B Reihen 4–6 (unten); platzieren nur in
  der eigenen Hälfte (Geist-Cursor des Partners sichtbar, 5-Hz-Relay).
- **Nutella: GETRENNTE Konten + „Rüberschieben"-Button** (25er-Schritte, kleine
  Klecks-Wurf-Animation zum Partner). Entscheidung gegen geteilten Topf: verhindert
  Weg-Klick-Frust, ERZEUGT aktive Kommunikation („brauchst du was?") — der eigentliche
  Coop-Kick. Himmels-Kleckse fallen hälftenspezifisch.
- Level C1–C15 = Remix der Kampagnen-Mechaniken + Coop-Twists: C3 Kleckse fallen NUR in
  A's Hälfte (teilen!), C6 Maulwürfe wechseln beim Graben die Hälfte, C9 Förderband
  liefert A nur Schützen / B nur Support (tauschen unmöglich → absprechen), C12
  Ballon-Wellen nur oben (B muss B-Pust-Goobys nach oben „verleihen" via
  Reihe-3/4-Grenzzellen: EINE gemeinsame Doppelreihe, beide dürfen dort bauen), C15
  Doppel-Boss (2 Müllwagen, je Hälfte einer). Disconnect: Pause 30 s, dann straffreier
  Abbruch (C-Regel).

### 4.7 Balancing als Daten

`res://content/base/minigames/gvz/balance.json` (alle Turm-/Zombie-/Ökonomie-Zahlen aus
§4.2/§4.3), `levels/L01..L15.json`, `coop/C01..C15.json` (Wellen-Skripte:
`[{t: 30, lane: 2, type: "schlurfi"}, …]`), `pvp.json` (Matsch-Kurve, Kosten, Timer).
Alles per Auto-Updater (§B) hotfixbar — Balancing-Patches ohne IPA. Bot-Zertifizierung:
Gooby-Bot (Greedy-Placement) muss L1–L5 mit Seeds 1..20 gewinnen, L13–L15 verlieren
dürfen (Schwierigkeits-Monotonie-Test über die Levelnummer).

---

## 5) GOB NOM (Cut-the-Rope-Prinzip)

### 5.1 Physik-Design (Godot 2D)

- **Süßigkeit** (Bonbon/Keks): `RigidBody2D` (CircleShape2D, `continuous_cd` an,
  Physik-Tick fix 60 Hz → deterministisch genug für Bot-Replay-Tests).
- **Seile: EIN-seitige Distanz-Constraints statt Joints.** `DampedSpringJoint2D` drückt
  auch (Stab-Verhalten) und Ketten aus Mini-RigidBodies sind teuer/zittrig. Eigener
  `RopeLink`-Node: wenn `dist(anchor, candy) > rest_length`, ziehe die Süßigkeit per
  `apply_central_force` Richtung Anker (steife Feder + Dämpfung nur radial) — exakt das
  Original-„Cut the Rope"-Verhalten (Seile ziehen nur). **Optik:** kosmetische
  Verlet-Kette (14 Punkte, 3 Iterationen, zwischen Anker und Candy gespannt) als
  `Line2D` mit Textur — sieht physisch aus, kostet nichts, schneidet sich sauber.
- **Schneiden:** Swipe = Segment; Test gegen die Verlet-Segmente (Linien-Schnitt);
  Treffer → `RopeLink.queue_free()`, Verlet-Kette fällt lose runter (reine Deko),
  Schnitt-Blitz + haptic. Mehrere Seile pro Swipe möglich (wichtiges Original-Gefühl).
- **Gooby-Mund:** `Area2D`; Candy drin → NOM-Animation (Mund riesig auf, Sterne-Augen),
  Level geschafft. Candy fällt aus dem Bild → weiche Fail-Anim („Ohhh…"), Instant-Retry.

### 5.2 Element-Baukasten (alle als eigenständige `.tscn`-Bausteine)

`Seil-Anker` (fix), `Schiebe-Anker` (auf Schiene ziehbar), `Auto-Seil-Schießer` (schießt
neues Seil, wenn Candy im Radius), `Luftkissen` (Tap → Luftstoß-Impuls, ∞ oder n Ladungen),
`Blase` (fängt Candy, schwebt aufwärts; Tap = platzen), `Ventilator` (Dauerwind,
schaltbar), `Stachelbrett` (Fail bei Kontakt), `Zuckerwatte-Wolke` (bremst stark) und
**Sammelobjekt: NUTELLA-GLAS** (3 pro Level, ersetzt Sterne; Ergebnis 0–3 Gläser =
Sterne-Rating; Gläser zählen zusätzlich auf einen Meta-Zähler → alle 25 Gläser 1 Sticker).

### 5.3 Kampagne — 15 Level (Fenster-Logik: alle 3 Level 1 neues Element)

| Lvl | Neu | Skizze (1 Satz) |
|---|---|---|
| 1 | 1 Seil | Schneiden-Tutorial: Candy hängt direkt über Gooby |
| 2 | 2 Seile | Pendel aufbauen: erst links, dann rechts schneiden |
| 3 | Timing | 3 Seile, Gläser nur im Pendel-Bogen erreichbar |
| 4 | Blase | Candy fällt, Blase fängt, über Gooby platzen |
| 5 | Blase+Seil | Blase nach oben durch Glas-Gasse, Seil stoppt sie |
| 6 | Luftkissen | Horizontal-Schubser über eine Lücke |
| 7 | Kissen-Kombo | 2 Kissen als „Flipper", Timing für alle 3 Gläser |
| 8 | Schiebe-Anker | Anker verschieben, DANN schneiden (Reihenfolge-Puzzle) |
| 9 | Auto-Schießer | Fang-Kette: Fall durch 2 Schießer-Radien lenken |
| 10 | Stachel | Präzisions-Pendel zwischen zwei Stachelwänden |
| 11 | Ventilator | Dauerwind krümmt jede Flugbahn; gegenhalten mit Kissen |
| 12 | Watte-Wolke | Bremszonen nutzen, um im Wind zu „parken" |
| 13 | alles | Doppel-Candy? Nein: 2-Phasen-Level (Glas-Tour, dann Rückweg) |
| 14 | alles | Blase+Wind+Schießer-Uhrwerk, 3 Schnitte gesamt (Schnitt-Limit!) |
| 15 | Finale | „Nutella-Fabrik": langer Rube-Goldberg, alle Elemente, Skip-sicher getestet |

### 5.4 Coop — 10 Level (geteilte Kontrolle)

Ein Bildschirm (lokal via Splitscreen ODER 2 Geräte via C-Relay): vertikale Trennlinie,
**jeder darf nur in seiner Hälfte schneiden/tippen** (Input-Gate im Host: Touch-Position
→ Spielerzuordnung; remote: Aktionen des Partners kommen als Events, Physik läuft beim
Host, 10-Hz-Candy-Snapshot zum Gast — Candy-Flug ist glatt interpolierbar). Level CN1–10:
Candy MUSS die Seite wechseln (CN1 simple Übergabe, CN3 Blase links platzen damit rechts
das Kissen trifft, CN5 synchrones Doppel-Schneiden (2 Seile gleichzeitig, sonst
Stachel-Pendel), CN7 Wind bläst zurück — Ping-Pong mit 3 Übergaben, CN10 Uhrwerk mit
Countdown-Schnitten „3-2-1-JETZT!"-Voiceline).

Level-Daten: `gobnom/levels/*.json` (Element-Positionen — Content-Pack-updatebar, neue
Level-Packs ohne IPA!). Editor: die Host-Szene lädt JSON auch im Godot-Editor via
`@tool` → Level-Bau in-Editor mit Live-Preview.

---

## 6) Auto-Integration (Autohaus → Fahr-Spiele)

Quelle: Improver D Kap. 7 — `cars.json`: `{ id, glb, price, stats: { speed, accel,
handling } (1–10), colors }`; Save `cars.active`.

- **Betroffene Spiele:** `cityDrive` (Einkaufsfahrt), `deliveryRush` (Liefer-Flitzer),
  `toyRacer` (Spielzeug-Grand-Prix — fährt die SPIELZEUG-Version des aktiven Autos,
  gleiche GLB in Toy-Scale + Aufziehschlüssel am Heck: Wiedererkennungs-Gag).
- **Stats-Mapping** (Basis-Auto `sedan` = 3/3/3 ⇒ neutral 1,0 — Alt-Balance bleibt exakt):
  `speed_mult = 1 + 0.025·(speed−3)` (max +17,5 %), `accel`: Boost-Aufladung/Anfahrt
  `1 + 0.03·(accel−3)`, `handling`: Lenkrate/Spurwechselzeit `1 + 0.03·(handling−3)`.
  In toyRacer wirkt speed auf `TARGET_LAP_SEC ÷ speed_mult`, gedeckelt so, dass die
  Rubber-Band-KI (`rubberMax 1.12`) mithalten kann → schnellere Autos = spürbar bessere
  Zeiten/Scores, **Coin-Caps unverändert** (Ökonomie sicher; bessere Autos = leichter ans
  Cap, nicht drüber).
- **UI:** Pregame zeigt „Dein Auto: <Name> · +8 % Tempo" + Mini-Icon in Lackfarbe;
  Farb-Override = Material-Override des Karosserie-Slots (D's Blender-Split).
- Mapping-Formeln liegen in `logic/car_stats_logic.gd` (pure, getestet) + die
  Multiplikator-Konstanten in `minigames.json` (Balancing updatebar).

## 7) Weltraum (Rückblick-Ort) — Entscheidung

**Port von `rocketRescue` + `starHopper` REICHT — kein neues Spiel.** Beide sind bereits
Weltraum-Spiele mit fertiger Logic + Cover. Damit der RÜCKBLICK-ORT abgedeckt ist (nicht
nur zwei Arcade-Kacheln): kleine Wrapper-Szene **„Raumstation GOOB-1"** (1 Innenraum,
Fenster mit Erd-Blick, Gooby schwebt leicht) — erreichbar über Reise/Flughafen wie die
anderen Rückblick-Orte (Improver E baut Orte; wir liefern die Szene als Minigame-Hub).
Darin 2 Terminals: „Raketen-Rettung" und „Sternenhüpfer" (starten die normalen
Minigame-Runs über den Host). Kosten: 1 kleine Szene (~200 LOC + Assets aus Kenney
space-kit, schon im Web-Projekt benutzt) statt eines dritten Weltraum-Spiels. goobyWelt
entfällt ersatzlos; sein L12-Slot in der Arcade wird durch GvZ belegt.

---

## 8) Prioritäten (Milestones, abgestimmt auf A/C/D)

1. **G-M1a — Framework:** Host, Ctx, GoobyRng, Pregame (Difficulty+Orientierung),
   Countdown/Pause/Results, JuiceKit, Registry+JSON, Orientierungs-Pipeline (OS-Lock +
   Gate + SubViewport-Fallback), Headless-Test-Runner + Cross-Check-Tooling.
2. **G-M1b — 10 Erst-Ports** (Tabelle §3 M1) inkl. Bot-Zertifizierung je Spiel.
3. **G-M1.5 — GvZ Kampagne** (Solo, 15 Level, Balancing-JSONs) — parallel zu M2-Ports
   startbar, da nur Framework nötig; das neue Flaggschiff früh in Spieler-Hände.
4. **G-M2 — Rest-Ports** (18 Spiele; 3D-Fahr-Spiele nach D's cars.json;
   shoppingSurf zuletzt) + GOB NOM Kampagne + Raumstation GOOB-1.
5. **G-M3 — Multiplayer:** GvZ PvP + Coop, GOB-NOM-Coop (C's `mg:`-Rooms, C-M3),
   danach Juice-Polish-Pass über alle Spiele (Polish-Subagents).

## 9) Risiken

- **R1 iOS-Orientation-Lock zur Laufzeit** (auch A §R1): früh auf Gerät testen; unser
  SubViewport-Fallback (§1.3.4) macht das Feature davon UNABHÄNGIG — Risiko = nur Komfort.
- **R2 HDR-2D-Glow-Kosten auf alten Geräten:** per-Spiel-Flag + Auto-Downgrade auf
  Fake-Glow, wenn FPS < 50 über 5 s (Telemetrie lokal).
- **R3 GvZ-Determinismus** (PvP/Coop): Float-Drift zwischen Geräten → Simulation NUR mit
  int-Millimetern/Fixed-Ticks in `gvz_logic.gd` (keine Physik-Engine!) — von Anfang an so
  bauen, nicht nachrüsten.
- **R4 GOB-NOM-Physik-Feel:** RopeLink-Steifigkeit braucht Tuning-Iterationen; früher
  Feel-Prototyp (Level 1–3) VOR Level-Massenproduktion.
- **R5 danceParty-Audio-Latenz** auf iOS (Bluetooth!): Kalibrierungs-Screen einplanen.
- **R6 Umfang:** 31 Ports + 2 Neubauten ist der größte Einzelbereich — die Logic-Ports
  sind dank §2 mechanisch, aber die 31 SZENEN sind Handarbeit; Cover/Assets existieren,
  Kenney-Kits decken die 3D-Spiele.

## 10) Scope-Schätzung (Dateien / LOC)

| Baustein | Dateien | LOC (~) |
|---|---|---|
| Framework (Host, Ctx, Pregame, Results, JuiceKit, Registry, Orientierung) | 14 | 2.600 |
| GoobyRng + Test-Runner + Cross-Check-Tooling | 4 | 500 |
| Logic-Ports 30× (`*_logic.gd`, Ø 350) | 30 | 10.500 |
| Spiel-Szenen 30× (`.tscn`+`.gd`, Ø 280) | 60 | 8.400 |
| Logic-Tests 30× (Ø 120) | 30 | 3.600 |
| GvZ (Logik, Board-Szene, PvP/Coop-Glue, Balance-/Level-JSONs, Tests) | 22 | 6.500 |
| GOB NOM (Physik, Elemente, 25 Level-JSONs, Coop-Gate, Tests) | 20 | 4.000 |
| Auto-Stats-Mapping + Raumstation GOOB-1 | 4 | 600 |
| Content-JSONs (minigames.json, difficulty, targets) | 5 | 900 |
| **Summe** | **~189** | **~37.600** |
