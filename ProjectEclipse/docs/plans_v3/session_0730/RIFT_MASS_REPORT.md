# RIFT_MASS_REPORT — F-102 Team B „Rift-Masse"

**Mission (User-Wunsch):** „Die Rifts sehen nicht heftig und nicht groß genug aus und die
müssen auch so volumetrisch 3d sein statt nur so Scheiben. Ich will Sachen mit Masse und
Tiefe damit man denkt oha was ist das denn." — plus für Struktur-Rifts: „Rifts sollten
weiter oben spawnen und es sollten mehr Block Displays raus fallen passend dazu wie die
Struktur spawnt."

Drei Konsumenten, alle drei angehoben: (1) Tagesriss-Schlund, (2) Struktur-Spawn-Rifts,
(3) `rift_glitch`-Post-Shader-Tiefen-Fake.

---

## 0. Exploration — identifizierte Treiber-Klassen

| Klasse | Rolle | Geändert? |
|---|---|---|
| `ferryman/finale/DayRiftOrbits` | Server-Treiber Tagesriss: Rollover-Beat, Maw-Cue, Orbit-Display-Schwarm | **JA** (Counts + Drop-Choreo) |
| `veilfx/FerrymanFinaleFxRows` | Client-Row-Registrar `CUE_DAY_RIFT_MAW` | **JA** (nur Kommentar des day_rift-Blocks) |
| `ferryman/finale/PortalFormation` | Konsumiert den Schwarm am Finaltag (liest `orbitCount`/`liveDisplays`, keine CAP-Annahme) | nein |
| `worldgen/stage/StructureFlightFx` | Delivery-Flug der Struktur-Rifts (Displays aus dem Riss) | **JA** (Höhe, Budget, Streu-Cap) |
| `sequence/ExpansionSequence` | Öffnet den Himmelsriss des Beats (`SKY_RIFT_HEIGHT`, Lockstep-Spiegel) | **JA** (Höhe 44→64) |
| `worldgen/structure/StructurePendingRegistry` | `revealRiftWidth` (adaptive Rissbreite) | nein |
| `veilfx/rift/RiftFx` / `RiftRenderer` / `RiftVolumeFx` | Client-Riss-Geometrie + Volumetrik-Pass (`MAX_WIDTH = 72`) | nein |
| `veilfx/TransitionFx` | Uniform-Feed für `rift_glitch` (`Time` aus Java, `RiftCenter`/`RiftAmount` via `setRiftAmbient`, Ambient-Cap 0.6) | nein |
| `pinwheel/shaders/program/rift_glitch.fsh` | Screen-Space-Anteil | **JA** (v4-Layer) |

Tabu-Klassen (storm/credits/nether/glitchzone) wurden nicht angefasst. Hinweis: während
der Gates war `veilfx/NetherOpenPhotonFxRows` (Team Nether) vorübergehend rot — fremde
Datei, hat sich im Shared-Checkout selbst aufgelöst; mein Diff war nie beteiligt.

`docs/plans_v3/langdrop/RIFT2.json` wurde NICHT angelegt: kein einziger neuer UI-String
nötig (alle Beats nutzen bestehende Captions/Sounds).

---

## 1. Konsument 1 — Tagesriss am Himmel (day_rift_maw v3 „Schlund")

### 1.1 PLAN
- **Job:** F-044-Rollover-Beat. `DayRiftOrbits.riftBeat` sendet `CUE_DAY_RIFT_MAW` an
  `riftPoint` (72 Blöcke über Inseltop) und lässt neue Orbit-Displays „herausfallen".
  Row: `FerrymanFinaleFxRows` → Asset `eclipse:day_rift_maw`, Quasar-Fallback
  `riss_maw_shimmer` (unverändert).
- **Trigger/Replay:** Rollover (`EclipseSignals.onDayRollover` POST) bzw. manuell
  `/eclipse day set <aktuellerTag+1>` (feuert das Signal nur bei exakt +1);
  Asset-only: `/dev photon test eclipse:day_rift_maw [x y z]`.
- **Bestand (FX-W11/W13), auf dem AUFGEBAUT wurde:** Glockenvorhang-Unterhang,
  Orbit-Stratifikation „schwere Platten tief+langsam" (Sediment-Gesetz in
  `paramsFor`), echter 72-Block-Motenregen mit `day_rift_dust_puff`-Stempel,
  RGB-Split-Tears am Saum. Nichts davon weggeworfen.

### 1.2 IDEEN (mit Verwerfungsgründen)
1. **Volumetrik über den `eclipse:rift_volume`-Post-Pass** (Raymarch-Kegel für den
   Tagesriss). VERWORFEN: der Pass ist pro-Tear budgetiert und gehört dem
   RiftFx/RiftVolumeFx-Bestand; den ambienten 30-s-Tagesriss dauerhaft in das
   Screen-Space-Budget zu hängen ist teurer als Photon-Schalen, die echte
   Welt-Parallaxe gratis liefern.
2. **Einfach größere flache Scheibe** (Radius + Alpha hoch). VERWORFEN: bleibt exakt
   die „Scheibe", die der User moniert; Alpha-Stacking (V2.1) würde zudem zur
   Sprite-Eigenfarbe konvergieren.
3. **Mehrschalige Kehle: gestaffelte Ring-Schalen + dunkler Kern + heller Saum**
   (GEWÄHLT): drei Ringe auf +2.6/+5.2/+7.8 mit schrumpfendem Radius, sinkender
   Helligkeit, alternierender Rotationsrichtung; fast-schwarzer Rauchpfropf am
   Schachtende; emissiver Violettring an der Mundkante. Überlappung + Größen- +
   Helligkeitsstaffelung = Tiefe in EINEM Standbild.
4. **Unterhang auf 20+ Blöcke verlängern** („Schlot nach unten"). TEILWEISE
   VERWORFEN: vertieft auf 14 (von 10), aber nicht weiter — das Orbit-Band endet bei
   Höhe 60 (Riss bei 72), ab ~58 schnitte ein längerer Vorhang sichtbar durch die
   obersten Orbit-Displays.

### 1.3 IMPLEMENT — neuer Generator `tools/photon/rift_mass_fx.py`
Autorisiert `day_rift_maw.fx` + `day_rift_dust_puff.fx` (Dust-Puff 1:1 übernommen,
budget-eingefroren an der LINT-SUBEM-FAT-Linie). Maw v3, alle Emitter:

| Emitter | Neu/Geändert | Zweck (Tiefen-Cue) |
|---|---|---|
| `maw_smoke` | Radius 4.5→**7.0**, max 80, Burst 24@t0, radial −1.1 | Mundkörper; „nicht groß genug" behoben; Frame-1 lesbar |
| `maw_underhang` | Tiefe 10→**14**, R0 6.5, Wachstum 5.0, Burst 14@t0 | hängende Masse unter dem Riss (Lag = Schwere) |
| `throat_low/mid/high` | **NEU**, je 24 max, Burst 9@t0, Radien 5.6/4.0/2.7, Orbital +0.16/−0.11/+0.07 | die Kehle: konzentrische, gegenläufige, dunkler werdende Ringe = Trichter |
| `throat_core` | **NEU**, 10 max, fast-schwarz (Alpha-Peak 0.55) auf +8.2 | der dunkle Schlund-Kern hinter dem hellen Saum |
| `mouth_rim` | **NEU**, 60 max, HDR ≤1.45, sky/block 15 | das EINE helle Element, an dem das Auge die Dunkelheit misst |
| `maw_pulse` | steigt jetzt 4.5 b/s den Schacht HOCH und schrumpft dabei | Perspektiv-Cue: der Puls entfernt sich in die Tiefe |
| `maw_drip` | Geburts-Annulus 1.0–3.8 → **1.5–6.0** | Regen fällt aus dem GANZEN Mund |
| `maw_tear` | Ring auf 6.7 nachgeführt | Saum-RGB-Tears bleiben der einzige Screen-Space-Akzent |

CullBoxen: Maw-Körper (−16,−22,−16)…(16,13,16) deckt Bell-Sag UND Kehlen-/Kern-Säule;
Regen behält die eigene 96-Block-Hülle. Alle Struktur-Emitter feuern t=0-Bursts
(Prewarm-Doktrin für One-Shots — Prewarm existiert nur für Loops). V2.1: alle
Alpha-Pässe mit dunklen Birth-Tints, HDR via `hdr()`-Clamp ≤ 1.45, Alpha sortiert
DISTANCE, Kollisions-Emitter `parallelUpdate` OFF. `arc_mode` kommt nirgends vor
(nur circle/cone/dot/function_shape — keine Arc-Shapes, die Uniform-Falle ist
konstruktiv ausgeschlossen).

### 1.4 Fallout-Treiber `DayRiftOrbits` (Masse + Choreo)
- Counts: `FIRST_DAY_COUNT` 20→**30**, `DAILY_MIN/MAX` 15–30→**22–42**, `CAP`
  350→**450**. Budget: weiterhin EIN Mount-Chunk, ein interpolierter Pose-Push pro
  Display pro 40t, Player-gated (160 Blöcke) — bei 450 im Schnitt ~11 Pakete/Tick.
  `PortalFormation` liest nur `orbitCount()`/`liveDisplays()` — CAP-agnostisch.
- **Drop-Choreo** („fällt raus passend zum Maw"): Geburt jetzt auf einem
  deterministischen Spill-Annulus 1.5–5.5 (= Drip-Ring des v3-Assets) statt am
  exakten Zentrum; horizontaler Blend quadratisch verzögert (`s²`) → das Stück
  FÄLLT erst fast senkrecht aus dem Mund, taucht am Sag unter die Orbitlinie und
  schwingt dann seitlich in den Slot. Keine neue Persistenz — alles bleibt reine
  Funktion von (seed, index) + transienter `DROP_BIRTH_TICKS`.

### 1.5 Selbst-Iterationen (Eigenkritik)
- **Iteration 1 (Frame-1-/Geometrie-Kritik):** Erstentwurf verließ sich auf
  `rate`-Anlauf → in den ersten ~2 s der 30-s-Windows wäre der Riss fast leer
  (CullBox/Prewarm-Doktrin verletzt im Geiste). Fix: t=0-Bursts auf allen
  Struktur-Emittern (24/14/3×9/4/22). Außerdem: Drip-Annulus war noch auf den alten
  4.5er-Mund geeicht (Regen aus der Mitte einer 7er-Öffnung sähe falsch aus) →
  auf 1.5–6.0 geweitet; CullBox musste die neue Kehlen-/Kern-Säule (+8.2 +
  Partikelgröße) nach oben decken → Max-Y 8→13.
- **Iteration 2 (Standbild-/Stacking-Kritik):** (a) `maw_smoke` radial −1.6 b/s ×
  ~4.5 s Lebenszeit = jeder Sprite wandert bis zur Achse und STIRBT dort — genau
  die Zone, durch die der dunkle `throat_core` von der Insel aus lesen muss, wäre
  zugestopft. Fix: −1.1 (stirbt bei ~Radius 2; Sog-Read bleibt, Zentrum bleibt
  offen). (b) Sustain-Audit gegen die fxlib-Semantik (`rate` = Partikel/TICK,
  nicht /s): Kehlen-Schalen ~17 stehend, Kern ~7, Saum ~32 — kein Ausdünnen nach
  dem Burst. (c) Determinismus-Beweis: `day_rift_dust_puff.fx` nach Generator-Lauf
  byte-identisch (kein `M` in git), ebenso alle verbleibenden ferryman2-Assets.

---

## 2. Konsument 2 — Struktur-Spawn-Rifts

### 2.1 PLAN
- **Job/Trigger-Pfad:** `ExpansionSequence` öffnet den Himmelsriss des Beats
  (`FX_RIFT_OPEN` auf `SKY_RIFT_HEIGHT` über der Site, Breite adaptiv aus
  `StructurePendingRegistry.revealRiftWidth`); `StructureFlightFx.begin` re-öffnet
  den Riss am `RIFT_MOUTH_HEIGHT`-Mund (Lockstep-Spiegelpaar!) und fliegt die
  gesampelten ECHTEN Strukturblöcke als Displays heraus.
- **Replay:** `/dev structure place <id>` (z. B. `minecraft:ancient_city`) in
  Spielernähe (< 224 Blöcke, sonst wird der Flug übersprungen).

### 2.2 IDEEN (mit Verwerfungsgründen)
1. **Adaptive Höhe nach Footprint** (kleine Ruine 48, Trial Chamber 90). VERWORFEN:
   das Spiegelpaar `SKY_RIFT_HEIGHT`/`RIFT_MOUTH_HEIGHT` ist ein dokumentierter
   Lockstep-Vertrag, und die CUT-EXPANSION-Kamera-Beats (Punch-Through-Timings)
   nehmen ein festes Höhenband an — adaptive Höhe desynchronisiert beides für
   wenig Mehrwert.
2. **Zweiter Photon-Maw über Struktur-Rifts** (day_rift_maw-Variante andocken).
   VERWORFEN: `RiftFx`-Tear + `RiftVolumeFx` besitzen diesen Read bereits
   (Stern-Prisma-Schalen + Volumetrik-Pass); ein Photon-Doppel würde dagegen
   stacken statt addieren und das AMBIENT-Budget pro Delivery belasten.
3. **Höhe rauf + Budget rauf + Streuung an die echte Rissbreite koppeln**
   (GEWÄHLT): 44→64 Blöcke, Default 640→800 / Ceiling 800→1000 Displays,
   Mund-Streuungs-Cap 48→72 (= `RiftFx.MAX_WIDTH`).

### 2.3 IMPLEMENT
- `StructureFlightFx.RIFT_MOUTH_HEIGHT` 44 → **64** und (Lockstep)
  `ExpansionSequence.SKY_RIFT_HEIGHT` 44 → **64**: der Riss hängt unübersehbar im
  Himmelsband, der Fall der Stücke deckt eine echte Strecke, die Bezier-Bögen
  werden steiler/wuchtiger. Der Replay-Pfad (`SKY_RIFT_HEIGHT` im
  Watcher-Replay) zieht automatisch mit.
- `DEFAULT_MAX_DISPLAYS` 640 → **800**, `HARD_MAX_DISPLAYS` 800 → **1000**
  („mehr Block Displays … passend dazu wie die Struktur spawnt": der
  Sampled-Path füllt das Budget mit ECHTEN Blöcken der Struktur — mehr Budget =
  mehr echte Struktur fliegt, kein Konfetti).
- `mouthScatter`-Cap 48 → **72** an beiden Callsites: Stücke quellen aus der
  GANZEN Breite eines großen Tears (bis ±18 Blöcke), nicht aus einem schmalen
  Kernfenster.

### 2.4 Selbst-Iterationen (Eigenkritik)
- **Iteration 1 (Budget-/Choreo-Audit):** 1000 Stücke: Launch-Clock spawnt
  weiterhin max. `BATCH_SIZE` 28 Entities/Tick; Launch-Fenster wächst nur ~8
  Batch-Strides (~72t für Voll-Cap), Gesamtfenster ~164t « `WATCHDOG_TICKS` 400.
  Bandbreite: +25 % über der BD-STORM-Messlinie, transient und Viewer-gated —
  im HARD_MAX-Kommentar als Messauflage dokumentiert. Orphan-/Sweep-Muster
  (ENTITY_TAG + LIVE_DISPLAYS + Join-Sweep, F-084-Doktrin) unangetastet.
- **Iteration 2 (Konsistenz-Fund):** die Mund-Streuung clampte noch auf das ALTE
  `RiftFx`-Limit 48, obwohl FXTEAM-RIFT den Render-Clamp längst auf 72 gehoben
  hat — bei Ancient-City-Breiten fiel alles aus dem Mittelfenster eines viel
  breiteren Tears. Fix: beide `Math.min(48, …)` → `Math.min(72, …)` mit
  Verweis auf `RiftFx.MAX_WIDTH`. (Kein gemeinsames Symbol eingeführt —
  `MAX_WIDTH` ist privat in RiftFx (Client-Klasse); Server-seitiger Import wäre
  eine neue Kopplung, der Kommentar benennt die Spiegelpflicht.)

---

## 3. Konsument 3 — `rift_glitch`-Post-Shader v4 (Tiefen-Fake)

### 3.1 PLAN
- **Job:** Screen-Space-Anteil bei Riss-Nähe (`RiftAmount`/`RiftCenter` aus
  `TransitionFx.setRiftAmbient`, gefüttert von `RiftFx`; Ambient-Cap 0.6, unter
  reducedFx immer 0) + Transitions (`GlitchAmount`, `FadeAmount`). `Time` ist der
  Java-Feed aus `TransitionFx` (KEIN VeilRenderTime in pinwheel-Posts) —
  weiterverwendet, KEINE neuen Uniforms, `.json` unverändert.
- **Verträge respektiert:** §3.3 Uniform-Namen frozen; f=1 bleibt EXAKT schwarz
  (v4-Layer wirken nur auf uv/Chroma VOR der Iris; Dither-Pfad unverändert);
  R11 „kein Strobe bei Riss-Nähe" (alle v4-Layer sind gebundene, langsame
  Oszillationen).

### 3.2 IDEEN (mit Verwerfungsgründen)
1. **Echte Tiefenpuffer-Refraktion** (Depth-Sampler + VeilCamera-Rekonstruktion).
   VERWORFEN: die TRANSITION-Pipeline ist ein Single-Stage `veil:blit` nur mit
   `DiffuseSampler0`; ein Depth-Attachment änderte den frozen .json-Vertrag und
   die Veil-Verdrahtung — Risiko am kritischsten Pass des Mods (Portal-Fade).
2. **History-Buffer-Parallaxe** (echtes Vorframe-Ghosting mit Versatz). VERWORFEN:
   kein zweites Render-Target vorhanden (die v2-Echo-Doku legt das explizit
   fest); der 8-Hz-Fake bleibt.
3. **Kontinuierlicher Interior-Swirl.** VERWORFEN: exakt das Wasser/Portal-Klischee,
   das schon das v2-Team abgelehnt und v3 nur QUANTISIERT wieder zugelassen hat —
   stattdessen diskrete Tiefen-Regale (Haus-Vokabular „glitch snap").
4. **Drei-Schichten-Tiefen-Fake** (GEWÄHLT): Interior-Parallax-REGALE +
   Saum-Refraktion + radiale chromatische Fransen (Details unten).

### 3.3 IMPLEMENT (v4-Layer, alle × `RiftAmount`)
- **INTERIOR-PARALLAX-REGALE:** Disc-Inneres in diskrete lensDist-Ringe geschnitten
  (`floor(lensDist·9)`) — das Screen-Space-Pendant zu den Photon-Kehlenschalen.
  Jedes Regal resampled radial NACH AUSSEN (konkave Minifikation = Blick in eine
  Grube), Betrag wächst quadratisch zur Mitte (max 0.020 UV), dazu pro Regal ein
  langsamer radialer „Atem" (gehashte Rate) und ein ALTERNIERENDER tangentialer
  Drift (gegenläufige Strata — gebundene sin(Time)-Oszillation, kein
  Endlos-Schmieren, kein Motion-Sickness-Vektor). Im Standbild bleiben die
  Regal-Sprünge als gestufte Tiefenkanten lesbar.
- **SAUM-REFRAKTION:** schmale Annulus-Zone 0.42–0.88 (außerhalb der Shard-Disc)
  biegt die Szene nach außen wie eine dicke Linsenkante (max 0.014 UV);
  Zerrissenheit über `efxNoise` auf dem Richtungs-EINHEITSVEKTOR (stetig über den
  atan-Wrap!) mit langsamem Time-Kriechen — ausgefranste, leicht brodelnde Kante
  statt Zirkelkreis.
- **CHROMATISCHE SAUM-FRANSEN:** im selben Annulus richtet sich der RGB-Split
  RADIAL aus (`chromaDir` mixt zur Achse) und schwillt mit derselben
  Zerrissenheit (`seamRag` geteilt) — Prismenkante genau dort, wo die Fake-Linse
  am stärksten biegt.
- Reihenfolge: Streaks → Spiral-Warp (v3, unverändert) → Regale → Saum-Refraktion →
  Shard-Mix (v2, unverändert — Shards behalten ihre Sektoren per mix-TOWARD) →
  Chroma. NaN-Hygiene: alle neuen Branches tragen den `lensDist > 1e-4`-Guard des
  Bestands; kein atan in den neuen Layern.

### 3.4 Selbst-Iterationen (Eigenkritik)
- **Iteration 1 (Korrektheits-Audit):** (a) Erstansatz hatte die Saum-Raggedness
  als Noise ÜBER DEM WINKEL — Unstetigkeit am ±π-Wrap hätte eine stehende Naht
  ins Bild gezogen; auf Noise über dem Einheitsvektor umgestellt. (b) Drift-Terme
  auf Gebundenheit geprüft (nur sin(Time)-Oszillation, nichts integriert →
  kein unbegrenzter Versatz). (c) Zonen-Überlappung mit twist (0.05–0.45) und
  shards (0.18–0.62) durchgerechnet: Regale sind additiv, Shards mixen darüber
  (gewollt, Header-Gesetz), Summe der Inner-Displacements ≤ ~0.03 UV.
  (d) f=1-Schwarz-Vertrag: v4 endet vor der Iris — unangetastet.
- **Iteration 2 (Standbild-Lesbarkeit unter dem Ambient-Cap):** mit
  `RiftAmount ≤ 0.6` peakte die Franse bei ~4 px @1080p — im llvmpipe-Standbild
  zu zaghaft. `seamFringe`-Koeffizient 0.006 → 0.008 (~5–6 px am Saum; Kanten
  bleiben lesbar, kein Ganzbild-Schmieren, da die Zone annulus-gebunden ist).
  Gegenprobe Parallax-Amplitude: 0.020·0.6 ≈ 13 px Max-Versatz im Zentrum —
  kräftig genug, nicht angefasst.

---

## 4. Chirurgische Edits — exakte Stellen (git-Hunks)

- `tools/photon/ferryman2_fx.py` (NUR day_rift-Ablösung):
  - `@@ -2,16 +2,9 @@` — Header-Doku: die zwei day_rift-Einträge (alte Zeilen 5–14)
    durch 3-Zeilen-„moved out (F-102)"-Vermerk ersetzt.
  - `@@ -138,232 +131,6 @@` — alte Zeilen 141–369: kompletter Block
    `build_day_rift_dust_puff` + Abschnittskommentare + Modul-Konstanten
    (`UNDERHANG_*`, `MAW_CULL_*`, `RAIN_*`) + `build_day_rift_maw` entfernt.
  - `@@ -939,11 +706,8 @@` — die zwei `BUILDERS`-Einträge (alte Zeilen 945–946)
    entfernt; Leitkommentar durch Verweis auf `rift_mass_fx.py` ersetzt.
    (Eigenkritik: dieser dritte Hunk fehlte im ersten Anlauf — der Generator
    crashte mit NameError; im Gate-Lauf gefunden und geschlossen. Beweis:
    `python3 tools/photon/ferryman2_fx.py` schreibt jetzt alle 6 verbleibenden
    Assets byte-identisch.)
- `src/main/java/dev/projecteclipse/eclipse/veilfx/FerrymanFinaleFxRows.java`:
  - `@@ -45,9 +45,11 @@` — NUR der F-044-Blockkommentar (Zeilen 47–52 neu);
    Row-Registrierung selbst byte-identisch.
- `src/main/java/dev/projecteclipse/eclipse/ferryman/finale/DayRiftOrbits.java`:
  - `@@ -53,7 +53,8 @@` Klassen-Javadoc-Zahlen; `@@ -89,13 +90,19 @@` Counts
    (CAP/FIRST_DAY/DAILY); `@@ -134,6 +141,13 @@` SPILL_R-Konstanten;
    `@@ -507,11 +521,19 @@` Drop-Blend-Choreo in `poseAt`.
- `src/main/java/dev/projecteclipse/eclipse/worldgen/stage/StructureFlightFx.java`:
  - `@@ -142,17 +142,22 @@` Display-Budgets; `@@ -266,9 +271,12 @@`
    RIFT_MOUTH_HEIGHT; `@@ -971,7 +979,9 @@` + `@@ -1032,7 +1042,8 @@`
    mouthScatter-Cap (beide Pfade).
- `src/main/java/dev/projecteclipse/eclipse/sequence/ExpansionSequence.java`:
  - `@@ -173,10 +173,12 @@` SKY_RIFT_HEIGHT 44→64 (Lockstep-Spiegel).
- `src/main/resources/assets/eclipse/pinwheel/shaders/program/rift_glitch.fsh`:
  - `@@ -27,6 +27,24 @@` v4-Header; `@@ -98,6 +116,37 @@` Regale + Saum-Refraktion;
    `@@ -118,7 +167,16 @@` chromatische Fransen. `.json` unverändert.
- NEU: `tools/photon/rift_mass_fx.py`, regeneriert:
  `assets/eclipse/fx/day_rift_maw.fx/.fxproj` (day_rift_dust_puff byte-identisch).

## 5. Gate-Ergebnisse

| Gate | Ergebnis |
|---|---|
| `python3 tools/photon/rift_mass_fx.py` | beide Assets WROTE + round-trip valid |
| `python3 tools/photon/fxlib.py validate --lint` | 275 Dateien, **0 NEW error/warn** (27 grandfathered, 149 advisory; keine day_rift-Meldung) |
| glslang-Harness (`/tmp/gzvalidate.py rift_glitch`, Veil-Präambel-Komposit + Bare-Return-Lint) | **OK / PASS** |
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** |

## 6. Verifikations-Skript für den Main-Agent (RCON)

**Vorab (einmalig, Client):** `/photon_client clear_client_fx_cache` — Photon cached
.fx statisch, F3+T lädt NICHT neu. Ohne diesen Schritt spielt der ALTE Maw.

1. **Tagesriss, Asset-only (schnell):**
   `/dev photon test eclipse:day_rift_maw ~ ~40 ~`
   Erwartet (von unten UND seitlich prüfen): ~14 Blöcke breiter dunkler Mundring ab
   Frame 1; DURCH den Mund drei gegenläufig rotierende, nach oben kleiner/dunkler
   werdende Ringe; dahinter fast-schwarzer Kern; dünner heller Violettsaum an der
   Mundkante; Pulse steigen schrumpfend den Schacht hoch; Regen fällt aus einem
   breiten Annulus. Standbild-Test: EIN Screenshot von schräg unten muss
   konzentrische Ringe + dunkles Zentrum hinter hellem Saum zeigen.
2. **Tagesriss, voller Beat (Fallout-Choreo):**
   `/eclipse day goals` (aktuellen Tag ablesen, muss < 14 sein) →
   `/eclipse day set <Tag+1>` → `/dev ferryman status` (Orbit-Count +22–42,
   Tag 1: +30). Erwartet: Displays quellen über ~25 s aus dem GANZEN Mund
   (nicht einem Punkt), fallen erst fast senkrecht, tauchen unter die Orbitlinie
   und schwingen dann seitlich ins Band; Akkumulation um die Mittelinsel.
3. **Struktur-Rift:**
   `/dev structure place minecraft:ancient_city` (nahe des Spielers, < 224 Blöcke).
   Erwartet: Tear reißt **64** Blöcke über der Site auf (vorher 44 — sichtbar
   höher), bis zu 800 Displays (echte Deepslate/Sculk-Blöcke) quellen aus der
   ganzen Tear-Breite, Bottom-up-Spiral-Assembly, Blitz-Storm am Rim, Tear
   schnappt zu wenn das letzte Stück sitzt. Kleinere Probe: `/dev structure
   place eclipse:collapsed_vault`.
4. **`rift_glitch` v4:**
   `/eclipsefx rift ~ ~12 ~ 24` → nah heranstellen (< 16 Blöcke, Blick auf den
   Tear). Erwartet auf dem SCREEN (nicht in der Welt): das Bild um den Tear
   zieht sich in gestuften Regalen zur Mitte zusammen (Grube-Read, diskrete
   Kanten zwischen den Ringen); am Disc-Rand eine ausgefranste, langsam
   kriechende Refraktionskante; genau dort radiale RGB-Fransen (~5 px).
   Wegdrehen → weiches Abklingen (RiftCenter parkt offscreen). Danach
   `/eclipsefx rift close`. reducedFx-Gegenprobe: mit reduzierten Effekten
   bleibt ALLES davon aus (RiftAmount = 0 an der Quelle).

## 7. Offene Risiken / Notizen
- `HARD_MAX_DISPLAYS` 1000 ist +25 % über der BD-STORM-Messlinie; Kommentar
  fordert weiterhin Messung — falls TPS-Dips bei Voll-Cap-Deliveries auf
  schwachen Servern: `flight_fx.max_displays` in `config/eclipse/dungeons.json`
  drosselt ohne Codeänderung.
- Der 48→72-Scatter-Cap spiegelt `RiftFx.MAX_WIDTH` als Literal (privates
  Client-Feld); wer den Render-Clamp erneut hebt, muss beide Callsites
  nachziehen (Kommentare benennen das).
- `fxlib.py`-Änderungswünsche: keine.
- Fremd-Beobachtung (nicht mein Eigentum): `veilfx/NetherOpenPhotonFxRows` war
  während meines Gate-Laufs kurz rot (fehlendes `tremorSlamKick`-Symbol des
  Nether-Teams) und heilte sich im Shared-Checkout; Final-Compile GRÜN.
