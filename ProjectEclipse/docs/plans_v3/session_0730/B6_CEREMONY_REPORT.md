# B6 — Progression / Zeremonien (FX-Welle 13, §7 Welle B Zeile B6)

**Auftrag:** `rebirth_*` / `revive_*` / `award_*` / `dawn_*` auf Welle-13-Niveau, N9
Seelenfaden der Wiederbelebung, `gen_player_fx.py`-Rest (ohne `stern_komet_*`),
`dawn_toll`-Eskalation.

**Datei-Besitz:** `tools/photon/ceremony_fx.py`, `tools/photon/gen_player_fx.py` (ohne
`stern_komet_*`), deren `.fx`/`.fxproj`, `veilfx/CeremonyPhotonFxRows.java`,
`ritual/ReviveRitual.java` (nur Cue-Hook).

---

## 1 Bestandsaufnahme (verifiziert, nicht aus dem Gedächtnis)

### 1.1 Besitz-Klärung — was NICHT mir gehört

| Asset | Generator | Befund |
|---|---|---|
| `award_star_shower`, `award_star_glint` | `tools/photon/mobs_fx.py` | Generator gehört **B2** (§7 Welle B). Konflikt-Gesetz 1: Konflikt-Einheit = Generator. **Nicht angefasst**, Patch-Snippet in §6. |
| `rebirth_aura_1/2/3` | `tools/photon/gen_ph_social.py` | Windowed Entity-Loops (PH-SOCIAL #7), Generator ist in Welle 13 **keinem** Team zugeteilt. Nicht angefasst (Konflikt-Gesetz 1 schlägt die `fx/rebirth_*`-Namensliste), Patch-Snippet in §6. |
| `wand_idle_riss/glut/stern` | `tools/photon/gen_player_fx.py` | Zensus §7 listet sie bei A2, aber `wand2_fx.py` erzeugt sie **nicht** (nur ein Kommentar-Treffer). Generator = Autorität ⇒ **mir**. |

Damit bleibt mein realer Asset-Satz: die 5 `ceremony_fx.py`-Dateien + die 9 nicht-Komet-
Assets aus `gen_player_fx.py` + die 4 neuen (N9 ×3, `dawn_toll_rift`).

### 1.2 Der eine große Befund: Einheiten-Slip über die ganze Zeremonien-Familie

Photon rechnet `startSpeed`/`velocityOverLifetime.linear` in **Blöcken pro SEKUNDE**
(`×0.05`/Tick), `radial` in **×0.01**/Tick, `orbital` in **rad/SEKUNDE** (`×0.05`/Tick).
`ceremony_fx.py` war durchgehend so geschrieben, als wären es Blöcke/Tick — Faktor 20 bzw.
100 zu langsam. Konkret nachgerechnet (Weg = v·0.05·Lebensdauer):

| Emitter | Autoren-Absicht | Ist-Weg vor dem Pass |
|---|---|---|
| `rebirth_starfall.star_streaks` | 8 Blöcke Ring-Einfall + 7.4 Blöcke Sturz in 18 t | **0.45 / 0.38 Blöcke** — die Sterne fallen nie ein |
| `rebirth_starfall.indraw_shell` | Schale r = 1.7 kollabiert in 8 t auf die Naht | **0.10 Blöcke** |
| `rebirth_starfall.wing_l/r` | Flügelfächer schnappen auf | **0.4 Blöcke** |
| `ghost_soul_departure.soul_ribbon` | Band wird bis y ≈ 9 hochgerissen (dort sitzt `tear_pop`!) | **0.8 Blöcke** — der Riss knallt in leere Luft |
| `revive_thunderbloom.sigil_indraw` | Zeugenring r = 3.4 wird ins Sigil gesogen | **0.2 Blöcke** |
| `revive_thunderbloom.lightning_ring` | Filamente rasen über den Zeugenkreis | **0.4 Blöcke** |
| `dawn_toll_bloom.glint_*` | Glockenstaub sinkt („Schleier fallen") | **0.05 Blöcke** |
| `offering_gutter.wisp_retreat` | Wisps ziehen sich in den Stein zurück (`radial −0.1`) | **0.014 Blöcke** |

Das ist der Grund, warum die Zeremonien „stehen": es gibt schlicht keine Bewegung zu
lesen. Der Pass rechnet jeden Wert auf die tatsächlich gewollte Strecke zurück.

### 1.3 Welle-13-Hebel, die im Paket fehlten

`random_gradient` 0 · `colorBySpeed` 0 · HDR über der 1.45-Decke an 7 Materialien ·
Birth-Tints hell (SAC_HOT als erster RGB-Stop bei 26 überlappenden Additiv-Quads) ·
Attack/Decay symmetrisch statt „kurz rein, lang raus".

---

## 2 Plan

### P1 Zeremonien-Politur (`ceremony_fx.py`)

1. **Einheiten** — jede Geschwindigkeit auf die in den Kommentaren dokumentierte Strecke
   zurückgerechnet (b/s statt b/t; `radial` ×100, `orbital` auf rad/s).
2. **`random_gradient`** über den `varied()`-Helfer (wandfx2-A1-Muster) auf jedem Emitter
   mit ≥ 3 Partikeln — kein Petal, kein Glitter-Korn, kein Filament sieht mehr aus wie
   sein Nachbar.
3. **`colorBySpeed`** genau dort, wo Bewegung die Aussage ist: Sternschweife, Flügelfeuer,
   Seelenband, Blitzfilamente, Glockenstaub, Seelenfaden-Motes. Modul über `with_module`
   (fxlib `_min_max` schreibt `min`/`max`, `Range.CODEC` will `a`/`b`).
4. **Dunkle Birth-Tints + breite Schalen** (V2.1-Stacking-Gesetz): erster RGB-Stop auf
   `SAC_VOID`/dunkles Deep, Peak erst bei t ≈ 0.2–0.35; Schalen (Glitter, Motes,
   Lightning-Ring) verbreitert statt Counts erhöht.
5. **HDR-Decke 1.45** über einen lokalen `hdr()`-Clamp (Hue-Ratio bleibt).
6. **Timing-Snap** — neue Haus-Segmente `SEG_SNAP_SWELL` / `SEG_SNAP_FLASH` /
   `SEG_LONG_TAIL`: Attack 8 t → 3–5 t, Decay verlängert.

### P2 N9 `revive_soul_thread` (neu)

* **3 Assets** `revive_soul_thread_1/2/3` (locker → straff → gespannt) aus EINEM
  parametrisierten Builder. Gestufte Cue-Re-Sends sind laut Auftrag ausdrücklich erlaubt
  und robuster als ein a-Wert: der Client müsste sonst Fortschritt raten.
* **Faden = 3-Ribbon-Stack** (`section`-Tubes sind in 2.1.5 kaputt): drei EMBEDDED
  `trails/ARA_TRAIL`-Konfigurationen auf drei fast unsichtbaren Träger-Partikeln
  (A8/N4-Muster — ein *stehender* `ara_trail_emitter` zeichnet nichts, der Träger muss
  sich bewegen). Träger laufen vom Grab-Ende zum Sigil: der Faden wird **eingezogen**.
* **Straffung** = Ara-Physik (gravity/inertia/damping) + Trägertempo + Ribbon-Alpha:
  Stufe 1 hängt durch und schleicht, Stufe 3 steht wie eine Saite und rast.
* **Verankerung** am Sigil, lokales **+Z** zeigt zum Grab (heart-theft-Aim-Konvention:
  Server rechnet das X/Y-Euler-Paar, `a` = xDeg, `b` = yDeg). Spannweite fest 11 Blöcke —
  Executor-`scale` würde World-Space-Trägergeschwindigkeiten NICHT mitskalieren.
* **Cue-Hook** in `ReviveRitual.tick()`: alle 40 t, Grab über
  `EclipseWorldState.getGravePositions(targetId)` (nächstes Grab in derselben Dimension),
  Stufe aus `ticksElapsed / DURATION_TICKS`. Kein Grab getrackt ⇒ kein Faden (Ritual
  läuft unverändert weiter).

### P3 `gen_player_fx.py`-Rest

`wand_soulbind_flash`, `riss_schlag_maw`, `riss_glitch_pop`, `glut_sprung_crater`,
`glut_splash`, `glut_ember_die`, `wand_idle_riss/glut/stern` — dieselbe Behandlung
(Einheiten, `colorBySpeed`, `random_gradient`, HDR-Clamp über den bereits vorhandenen
`hdr()`), plus `inheritVelocity` auf den Idle-Loops, damit die Handauren beim Laufen
nachziehen statt starr an der Hand zu kleben. **`stern_komet_*` bleibt unberührt.**

### P4 `dawn_toll` — der eskalierende Tagesriss

Der Tageswechsel-Beat ist `dawn_toll_bloom` (Entity-Lane, ein Send pro Spieler aus
`DawnCeremony.dawnToll`). Der Dispatch-Punkt gibt heute `a = 0, b = 0` her — und
`drama/DawnCeremony.java` gehört mir diese Welle **nicht**. Lösung ohne Fremd-Datei:

* Der Row-Leg liest den Tag client-seitig aus `ClientStateCache.day` (die Tagesnummer ist
  seit jeher mit `S2CDayStatePayload` synchron) und **respektiert `a > 0` als Override**,
  falls der Integrator den Sender später nachzieht (3-Zeilen-Snippet in §6).
* Eskalation ist **nicht** Executor-`scale` (skaliert World-Space-Geschwindigkeiten nicht),
  sondern ein neues Overlay-Asset **`dawn_toll_rift`**: 0 Risse bis Tag 5, 1 ab Tag 6,
  2 ab Tag 10, 3 ab Tag 13 — golden-Winkel-versetzt und um 7 t gestaffelt, damit der
  Himmel jeden Tag hörbar UND sichtbar weiter aufreißt.

---

## 3 Was tatsächlich gebaut wurde

### 3.1 P1 — Zeremonien-Politur (`ceremony_fx.py`, 5 Assets)

Gemeinsame Helfer neu im File: `hdr()` (Deckel 1.45, Hue-Ratio bleibt), `color_by_speed()`
(`a`/`b`-Range statt fxlibs `min`/`max`), `varied()` (`random_gradient`),
`ribbon_renderer()`, `lerp()`, `SMOKE_TILES` (smoke.png ist ein 2×2-Flipbook — ohne
`uvAnimation` rendert jedes Partikel alle vier Puffs als Quadrat), plus die
Timing-Segmente `SEG_SNAP_SWELL` / `SEG_SNAP_FLASH` / `SEG_HOLD_DRAW`.

| Asset | Einheiten (b/s, zurückgerechnet) | Welle-13-Hebel |
|---|---|---|
| `dawn_toll_bloom` | Glockenstaub `0.03 → 0.4–1.1` (1.1 Blöcke Sinkweg in 30 t), Glint-`orbital` auf 0.5–1.1 rad/s | `colorBySpeed` auf beiden Glint-Stimmen, `varied` auf Petals+Glints, Schalen r 1.0 → 1.35, `SEG_SNAP_SWELL` |
| `rebirth_starfall` | Streaks `−0.5 → −9.5` (8.6 Blöcke Einfall in 18 t), Schale `−0.1 → −4.6`, Flügel `0.4 → 8–13` (mit `speedModifier`-Decay ≈ 4.6 Blöcke), Glitter `0.05 → 1.0–2.6` | `colorBySpeed` auf Streaks + beiden Flügeln, `varied` überall, Birth auf `SAC_BIRTH`, Glitter-Schale r 1.4 → 2.1, Naht-Flash 3 t → 5 t Nachglühen |
| `offering_gutter` | Asche `0.06 → 0.8–1.8`, Wisp-`radial` `−0.1 → −3.9`, Sink `−0.06 → −1.2` | `colorBySpeed` (kalt-grau), `varied`, `SMOKE_TILES`; bleibt bewusst HDR-frei |
| `ghost_soul_departure` | Nebel `0.01 → 0.1–0.3` + `linear`-Kurve 0.05 → 2.6 (Knien, dann Aufstieg), Band `0.04 → 0.3–0.8` + `linear` 1.2 → 10.5 (Kopf landet bei y ≈ 9.5, wo `tear_pop` sitzt) | `colorBySpeed` auf dem Band, `varied`, `SEG_HOLD_DRAW`, `TEAR_Y` auf 9.4 nachgezogen |
| `revive_thunderbloom` | Zeugenring `−0.2 → −6…−8`, Filamente `0.4 → 9–13` (mit Decay ≈ 4.1 Blöcke), Herz-Motes `0.04 → 0.4–1.1` + `orbital` 0.8–1.4 rad/s | `colorBySpeed` auf dem Blitzring, `varied`, Ring r 1.2 → 1.9, Motes r 1.8 → 2.4, Bloom-Flash 4 t → 7 t |

### 3.2 P2 — N9 `revive_soul_thread_1/2/3` (neu)

Ein parametrisierter Builder, drei Dateien (`taut = (stage−1)/2`). Aufbau je Datei:
drei Träger-Partikel (`thread_veil` / `thread_core` / `thread_spark`) mit je EINER
eingebetteten `trails/ARA_TRAIL`-Konfiguration (= der 3-Ribbon-Stack; `section` bleibt
draußen, Tubes sind in 2.1.5 kaputt), dazu `thread_motes` (Fluss) und ab Stufe 2
`sigil_catch` (Ankunfts-Glints).

| | Stufe 1 (locker) | Stufe 2 (straff) | Stufe 3 (gespannt) |
|---|---|---|---|
| Trägerlaufzeit | 36 t (6.11 b/s) | 28 t (7.86 b/s) | 20 t (11.0 b/s) |
| Ara-`gravity` (Kern) | −1.10 | −0.60 | −0.10 |
| Ara-`inertia` / `damping` (Kern) | 0.40 / 0.88 | 0.22 / 0.52 | 0.04 / 0.15 |
| Ribbon-Alpha (Kern-Kopf) | 0.55 | 0.75 | 0.95 |
| Motes | 16 @ 4.4 b/s | 23 @ 9.2 b/s | 30 @ 14.0 b/s |
| `sigil_catch` | — | ja | ja (dichter) |

Weg-Invariante (aus den geschriebenen Bytes zurückgelesen): `speed × 0.05 × lifetime`
= **11.00 Blöcke = `THREAD_SPAN`** in allen drei Stufen und allen drei Ribbon-Layern —
jeder Träger kommt exakt am Sigil an, wenn er stirbt.

Kontinuität: `rate = THREAD_CONCURRENT / travel` hält ~3 Träger pro Layer gleichzeitig
am Leben; ihre gestaffelten Fortschritte überlappen zu einem durchgehenden Strang, und
`dieWithParticles = 0` lässt jedes Ribbon nach der Ankunft seines Trägers ausblenden
statt zu verschwinden — das ist die Übergabe zwischen zwei Trägern. Asset-Laufzeit 44 t
gegen 40 t Re-Send-Takt = 4 t Kreuzblende zwischen zwei Stufen-Dateien.

Server-Hook (`ReviveRitual`): eigener Countdown `soulThreadTimer` statt
`ticksElapsed % 40` — der Zeugenkreis addiert ganze Sekunden auf `ticksElapsed` und
würde eine Modulo-Grenze überspringen (= Faden reißt genau dann, wenn Publikum kommt).
Grab = nächstes getracktes Grab des Ziels in derselben Dimension
(`EclipseWorldState.getGravePositions`); kein Grab ⇒ kein Cue, Ritual läuft unverändert.

### 3.3 P3 — `gen_player_fx.py`-Rest (9 Assets, `stern_komet_*` unberührt)

Neu im File (eigene Funktionen, A8s Komet-Kette nur gelesen): `color_by_speed()`,
`varied()`, `inherit_velocity()`, `IDLE_DRAG`, `IDLE_PER_BLOCK`.

| Asset | Befund | Fix |
|---|---|---|
| `wand_soulbind_flash` | 24 Funken mit 0.3–0.7 b/s = 0.3–1.0 Blöcke Wurf, alle weiß in einer r-0.3-Kugel geboren | 2.5–5.0 b/s + `speedModifier`-Decay (≈ 2.5 Blöcke), Schale r 0.75, dunkler Birth-Stop, `colorBySpeed`, `varied`; HDR 3.5 → 1.45 |
| `riss_schlag_maw` | **`radial −0.9` = 0.05 Blöcke** — die Implosion implodierte nie, die Streaks blieben auf ihrer 3.5-Blöcke-Schale sitzen | `radial` Kurve −34 → −74 (beschleunigend, 3.5 Blöcke in 6.5 t), `colorBySpeed`, `varied`; HDR 1.6 → 1.45 |
| `riss_glitch_pop` | 0.02 Blöcke Streuung | 1.2–3.2 b/s (0.25–0.65 Blöcke) |
| `glut_sprung_crater` | Brocken 0.5–1.1 b/s gegen `gravity 0.5` = 4 cm Sprung; Rauchsäule 0.16 Blöcke | Brocken 5–9 b/s (Apex ~3 Blöcke, dann Kollisions-Bounce), Rauch 0.5–1.1 b/s + Crest-Ease (retiriert 3 Lint-Grandfathers), `colorBySpeed`, `varied` |
| `glut_splash` / `glut_ember_die` | 0.06–0.14 / 0.02 Blöcke | 1.5–3.5 / 0.4–1.2 b/s, `varied` |
| `wand_idle_riss` | **`orbital 0.3` = 34° Bogen pro 40-t-Loop** — die im Docstring versprochene „Scanline-Kreisbahn" war ein Stummel, der sich nie schloss | `orbital = π` rad/s = genau eine Umdrehung pro Loop; Squares 0.2–0.6 b/s, `inheritVelocity(−0.4)` + `distanceRate` |
| `wand_idle_glut` | Embers stiegen 0.03 Blöcke | `linear.y` 0.35 b/s, `inheritVelocity` + `distanceRate`, `varied` |
| `wand_idle_stern` | **Trail zeichnete nichts**: `minVertexDistance 0.02` gegen 0.0005–0.0015 Blöcke/Tick = ein Vertex alle 13–40 t | 0.2–0.5 b/s (≈ ein Vertex/Tick ⇒ die Konstellationslinien entstehen), `inheritVelocity` + `distanceRate`, `varied`; HDR 1.6 → 1.45 |

`inheritVelocity`/`distanceRate` sind hier legal, weil `WandAuraClient` die Idle-Loops
über `PhotonBridge.ensureAttachedFx` **entity-attached** spawnt (beide Module lesen das
Positions-Delta des Executors — ein Welt-Anker hat keines).

### 3.4 P4 — `dawn_toll` eskaliert

Neues Overlay `dawn_toll_rift` (Naht + Ausbluten + dunkle Schwade, alles `varied`,
Bleed mit `colorBySpeed`) und ein Tages-Gate im bestehenden B1-Leg:
0 Risse bis Tag 5, 1 ab Tag 6, 2 ab Tag 10, 3 ab Tag 13; Bearings −42°/95°/222°,
je 7 t versetzt. Tag kommt aus `ClientStateCache.day`, ein `a ≥ 1` aus dem Payload
schlägt ihn (Vorbereitung für den Tag, an dem `DawnCeremony` den Wert mitschickt —
die Datei gehört mir diese Welle nicht). Position-Lane statt Entity-Lane: die Risse
gehören zum HIMMEL und dürfen nicht mitlaufen. `allowMulti` ist Pflicht (eine Asset-ID,
ein Anker, drei Instanzen).

---

## 4 Geänderte / neue Dateien

**Generatoren**
* `tools/photon/ceremony_fx.py` — P1-Politur + `build_dawn_toll_rift` +
  `build_revive_soul_thread(stage)`
* `tools/photon/gen_player_fx.py` — P3 (nur die nicht-Komet-Builder + neue Helfer)
* `tools/photon/lint_baseline.txt` — 14 Einträge gestrichen (nur eigene Dateien)

**Assets (generiert, nie von Hand)** — je `.fx` + `.fxproj`
* geändert: `dawn_toll_bloom`, `rebirth_starfall`, `offering_gutter`,
  `ghost_soul_departure`, `revive_thunderbloom`, `wand_soulbind_flash`,
  `riss_schlag_maw`, `riss_glitch_pop`, `glut_sprung_crater`, `glut_splash`,
  `glut_ember_die`, `wand_idle_riss`, `wand_idle_glut`, `wand_idle_stern`
* neu: `dawn_toll_rift`, `revive_soul_thread_1`, `revive_soul_thread_2`,
  `revive_soul_thread_3`

**Java**
* `veilfx/CeremonyPhotonFxRows.java` — 3 N9-Rows + `soulThread`-Leg;
  `dawnTollBloom` um `dawnDay()` / `openDawnRifts()` erweitert
* `ritual/ReviveRitual.java` — `CUE_SOUL_THREAD[]` (via `FxCues.cue`, `FxCues.java`
  unberührt), `soulThreadTimer`, `sendSoulThread()`, `nearestGrave()`

---

## 5 Verifikation

```
python3 tools/photon/ceremony_fx.py     → 9/9 WROTE … valid, + .fxproj
python3 tools/photon/gen_player_fx.py   → 16/16 WROTE … valid, + .fxproj
python3 tools/photon/fxlib.py validate --lint
   → lint: 264 file(s), 0 NEW error/warn, 27 grandfathered, 129 advisory info
```

```
./gradlew compileJava --rerun          → BUILD SUCCESSFUL, exit 0 (echter Neu-Compile,
                                          nicht UP-TO-DATE; nur Deprecation-Warnungen)
```

Der volle Build ist **grün**. Er war zwischenzeitlich an fremdem, uncommittetem Code rot
(`MobPhotonFxRows`, §6.1) — B2 hat das inzwischen selbst behoben; der Punkt ist erledigt.
Die zwei Warnungen auf `CeremonyPhotonFxRows.java:51` (`EventBusSubscriber.bus`) sind
vorbestehend und stehen wortgleich auf jeder anderen Rows-Datei (z. B.
`CreditsFinaleFxRows.java:22`) — kein Regress aus diesem Pass.

Geometrie-Nachweis N9 (`Quaternionf.rotationXYZ`, echtes JOML 1.10.5, exakt der Aufruf
aus `PhotonBridge`, gegen die Winkel aus `ReviveRitual.sendSoulThread`):

```
grave (rel. to sigil)          xDeg     yDeg    aim.+Z |spawn|  vel.aim (+90 bug)
(14.5, -1.2, 0.0)             90.00    85.47   1.00000  11.000 -1.00000   1.00000  OK
(0.0, -1.2, -9.5)            173.10     0.00   1.00000  11.000 -1.00000   1.00000  OK
(-6.0, 14.8, 7.0)            -64.76   -20.08   1.00000  11.000 -1.00000   1.00000  OK
(3.0, -53.2, 2.0)             87.85     3.23   1.00000  11.000 -1.00000   1.00000  OK
(0.0, 54.8, 0.0)             -90.00     0.00   1.00000  11.000 -1.00000   1.00000  OK
(1.2, -0.2, -0.9)            170.54    52.75   1.00000  11.000 -1.00000   1.00000  OK
```

Das ist auch der Fund der Politur-Iteration: der Träger-Emitter stand auf
`.rotated(+90, 0, 0)` und hätte die Ribbons vom Sigil WEG geschickt (Spalte „+90 bug"
= +1.0 statt −1.0). JOMLs Rx(θ) bildet (0,1,0) auf (0, cos θ, sin θ) ab, also trifft
**−90** die −Z-Achse. Der `-90 → +Z`-Kommentar in `wandfx2_fx.py` hat das Vorzeichen
verdreht; `ferryman2_fx.py` und `wave13_cutscene_fx.py` schreiben es richtig.

Rückgelesene Bewegungs-/Stacking-Zahlen (aus den geschriebenen `.fx`-Bytes, nicht aus
dem Generator): höchster HDR-Peak in beiden Paketen **1.45** (= Deckel, nicht darüber);
alle N9-Träger `travel = 11.00`; kein Emitter mehr unter der Wahrnehmungsschwelle außer
den bewusst statischen (`cold_ember`, Flash-/Ring-Emitter mit `startSpeed 0`).

**Nicht verifiziert:** kein In-Game-Blick. Auf der VM lief zum Arbeitszeitpunkt bereits
ein fremder `runServer` (PID 7366), `load average 6.6`, ~3 GB RAM frei; ein zweiter
`runClient` (llvmpipe, Sekunden pro Frame) hätte die Session einer anderen Gruppe
gefährdet. Test-Kommandos für den Integrator stehen in §7.

---

## 6 Offene Punkte

### 6.1 ~~Der Build ist durch eine FREMDE Datei rot~~ — ERLEDIGT

`veilfx/MobPhotonFxRows.java` (B2) übergab `null` an das überladene `spawnOnEntity`
(`(…, int, Vec3)` und `(…, int, SpawnOptions)` matchten beide → *reference to
spawnOnEntity is ambiguous*). B2 hat die Stelle inzwischen selbst auf
`SpawnOptions.DEFAULT.withAllowMulti(true)` umgestellt; `./gradlew compileJava --rerun`
ist grün. Kein Handlungsbedarf mehr für den Integrator.

### 6.2 `gen_player_fx.py` neu laufen zu lassen fasst A8s Komet-Assets an

`FxBuilder` würfelt pro Lauf frische `transform.id`-UUIDs, d. h. ein Lauf des Generators
schreibt auch die sieben `stern_komet_*`-Dateien byte-verschieden (inhaltlich identisch).
Ich habe sie nach jedem Lauf mit `git checkout --` auf HEAD zurückgesetzt; im Diff
tauchen sie deshalb nicht auf. Wer den Generator anfasst, muss das ebenso tun —
oder der Integrator nimmt die Neu-UUIDs bewusst mit.

### 6.3 Nicht angefasste Assets aus der Zensus-Namensliste

* `award_star_shower` / `award_star_glint` — Generator `tools/photon/mobs_fx.py` (B2).
  Beide sind noch auf b/t-Einheiten und ohne `colorBySpeed`. Patch-Vorschlag für B2:

```python
# mobs_fx.py, award_star_shower: 0.02–0.06 b/s ist 0.03 Blöcke über 30 t
-            start_speed=random_between(0.02, 0.06),
+            start_speed=random_between(0.4, 1.2),   # b/s -> ~0.9 Blöcke Rieseln
+       .with_module("colorBySpeed", color_by_speed(COOL, HOT, 0.4, 2.0))
```

* `rebirth_aura_1/2/3` — Generator `tools/photon/gen_ph_social.py`, in Welle 13 keinem
  Team zugeteilt. `radial=constant(-0.06)` bzw. `-0.28` (= 0.4 bzw. 1.7 cm) und
  `orbital 0.45`/`0.35` rad/s sind dieselbe Einheiten-Klasse; der Faktor-100-Fix auf
  `radial` wäre ein Einzeiler pro Emitter.

### 6.4 `a`-Parameter für `dawn_toll`

`drama/DawnCeremony.dawnToll` schickt weiterhin `a = 0`. Der Client-Fallback
(`ClientStateCache.day`) trägt die Eskalation vollständig; wenn der Integrator den
Sender nachziehen will, reicht:

```java
 // drama/DawnCeremony.java (~L179)
+        int day = EclipseWorldState.get(server).getDay();
         for (ServerPlayer online : server.getPlayerList().getPlayers()) {
             PacketDistributor.sendToPlayer(online, new S2CFxEntityEventPayload(
-                    FxCues.CUE_DAWN_TOLL, online.getId(), online.position(), 0.0F, 0.0F));
+                    FxCues.CUE_DAWN_TOLL, online.getId(), online.position(), day, 0.0F));
         }
```

Das Leg respektiert `a ≥ 1` bereits als Override — kein Client-Änderung nötig.

### 6.5 Spannweite des Fadens ist fest

`THREAD_SPAN = 11` ist gebacken, weil Executor-`scale` die World-Space-Geschwindigkeiten
der Träger NICHT mitskaliert (ein skalierter Faden würde sich selbst zerreißen). Bei
einem Grab in 40 Blöcken Entfernung zeigt der Faden korrekt dorthin, endet aber nach 11
Blöcken — die `colorOverLength`-Rampe blendet dafür zu 0 aus, sodass es als „greift in
die Dunkelheit" liest statt als abgeschnittene Wurst. Wer echte Spannweite will, braucht
pro Distanzklasse eine eigene Datei (oder Photon 2.2 mit skalierten Velocities).

### 6.6 Ohne Grab kein Faden — und Gräber entstehen nicht immer

`LifecycleEvents#onLivingDrops` legt das Grab **nur an, wenn der Tote etwas fallen
lässt** (`if (stacks.isEmpty()) return;`), und `GraveBlock#onRemove` streicht die
Position wieder, sobald jemand das Grab plündert. Ein Ziel, das mit leerem Inventar
gestorben ist, in einer anderen Dimension liegt oder dessen Grab schon leergeräumt ist,
bekommt deshalb keinen Seelenfaden — `sendSoulThread()` bricht still ab und das Ritual
läuft exakt wie vor dieser Welle. Das ist bewusst so (kein Fallback-Faden ins Nichts),
aber es heißt für den Test: **vorher `/give` benutzen**, sonst sieht man nichts und hält
es für einen Bug. Wenn ein garantierter Faden gewünscht ist, wäre der richtige Ort ein
Ersatz-Anker in `ReviveRitual` (z. B. die letzte Todesposition aus `EclipseWorldState`)
— das ist eine Design-Entscheidung, keine reine FX-Frage, deshalb hier nur als Vorschlag.

---

## 7 Test-Kommandos

```bash
# Generatoren + Lint (der Pflichtpfad)
python3 tools/photon/ceremony_fx.py
python3 tools/photon/gen_player_fx.py     # danach stern_komet_* auf HEAD zurücksetzen, §6.2
python3 tools/photon/fxlib.py validate --lint          # 0 NEW error/warn

./gradlew compileJava --rerun                          # BUILD SUCCESSFUL (verifiziert)
```

In-Game. **Zuerst** der Cache-Killer im CLIENT-Chat (RCON erreicht ihn nicht, und ohne
ihn testet man das alte Asset — jede Änderung sieht dann wie ein No-Op aus):

```
/photon_client clear_client_fx_cache
```

Dann als Spieler (`/dev photon test` braucht eine Spieler-Quelle; ohne `pos` landet das
Asset 4 Blöcke vor den Augen; ein ROHES `eclipse:<name>` spawnt direkt über
`PhotonBridge` **ohne Rotation**, ein `eclipse:fx/cue/<name>` läuft durch meinen Leg):

```
/dev photon test "eclipse:revive_soul_thread_1"
/dev photon test "eclipse:revive_soul_thread_3"     # direkt danach — die Straffung ist der Diff
/dev photon test "eclipse:dawn_toll_rift"
/dev photon test "eclipse:rebirth_starfall"
/dev photon test "eclipse:revive_thunderbloom"
/dev photon test "eclipse:ghost_soul_departure"
/dev photon test "eclipse:offering_gutter"
/dev photon test "eclipse:riss_schlag_maw"          # die Implosion, die vorher keine war
/dev photon test "eclipse:glut_sprung_crater"
/dev photon test "eclipse:wand_idle_riss"           # der Scanline-Ring schließt sich jetzt
/dev photon test "eclipse:wand_idle_stern"
/dev photon status                                  # keine missing .fx ids, Rows registriert
```

Roh-Spawn zeigt den Faden entlang Welt-`+Z`; die echte Zielrichtung entsteht erst über
die a/b des Cues, also im Ritual (unten).

Ganze Kette statt Einzelasset:

```
# N9 im echten Ritual. WICHTIG: das Grab entsteht in LifecycleEvents#onLivingDrops und
# NUR wenn der Tote etwas fallen lässt (`if (stacks.isEmpty()) return;`). Mit leerem
# Inventar stirbt man grablos -> sendSoulThread() findet nichts und schweigt korrekt.
/give @p minecraft:dirt        # irgendein Drop, sonst kein Grab
/kill @p                       # legt das getrackte Grab an (EclipseWorldState)
# Ziel auf 0 Leben bringen (Ghost) und das Revive-Sigil am Altar benutzen -> der Faden
# muss vom Sigil zum Grab zeigen und nach 1/3 bzw. 2/3 der Ritualdauer sichtbar
# straffer + schneller werden. Das Grab darf bis dahin nicht geplündert sein
# (GraveBlock#onRemove streicht die Position wieder).

# dawn_toll-Eskalation: Tag setzen (1-14), dann den Tageswechsel auslösen
/eclipse day set 5    # 0 Risse
/eclipse day set 6    # 1 Riss
/eclipse day set 10   # 2 Risse
/eclipse day set 13   # 3 Risse
```

Beim Idle-Aura-Test **laufen**: `inheritVelocity`/`distanceRate` sind nur in Bewegung
sichtbar (im Stand ist der Loop exakt der alte).
