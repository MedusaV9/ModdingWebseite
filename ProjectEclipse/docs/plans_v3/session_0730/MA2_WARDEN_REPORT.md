# MA2 — Rift Warden (Welle M-A, Mob/Item-Zensus F-098)

**Auftrag:** MOB_ITEM_CENSUS §5 Welle M-A Zeile MA2 — (a) `blink_out`/`blink_in` mit
Bone-Scale-Warp (Glitch-Stretch, ±X-Squash unmittelbar vor dem Vanish,
Überschieß-Stretch beim Reappear), (b) `idle`: Riss-Platten „atmen" via Molang-Sinus
(phasenversetzt pro Platte), (c) `volley`: Schulter-Recoil pro Salve, getimt auf
`warden_eye_laser` (A4 liefert die Beam-Zeit).

**Datei-Besitz (exklusiv, §5-G1):** `entity/boss/rift/*`, `client/entity/rift/*`,
Assets `rift_warden*` (geo/animation/textures), `scripts/geckolib_gen/mobs/rift_warden.py`,
`docs/uv/rift_warden.md`.
**Nicht angefasst:** `tools/photon/boss_b_fx.py` + `fx/boss/warden_*` + `BossPhotonFxRows`
(A4/A5 — nur GELESEN), FROZEN-Basen (`EclipseGeoMonster`/`EclipseGeoAnimations`/
`EclipseGeoRenderer`), `validate_geo.py`/`paint_lib.py`, `sounds.json`/lang.

---

## 0. Plan (vor der Implementierung festgehalten)

1. Beam-Zeit aus A4s Asset verifizieren (Generator UND kompiliertes `.fx`), Tick-Trace
   der Kampf-Schleife rechnen (Volley-Release, Blink-Teleport) — nichts schätzen.
2. `blink_out`/`blink_in`: neue `scale`-Kanäle auf Silhouetten-Bones; blink_out-Länge auf
   das echte Vanish-Fenster ziehen, damit kein Idle-Frame zwischen Vanish und Reappear
   blitzt. Kontinuität blink_out-Endframe == blink_in-Startframe (Haus-Konvention des
   Sheets, gilt bisher nur für `position`/`rotation`).
3. `idle`: Molang-Atmung auf beide `crack_plate_*` + den treibenden `glow_rift_core`;
   Frequenzen NUR aus {90, 180, 270}°/s, damit der 4-s-Loop bei beliebiger Phase
   nahtlos schließt; pro Platte andere Grundphase UND andere Oberwelle (kein Gleichtakt).
4. `volley`: Recoil-Keys nur in KANÄLE OHNE `catmullrom` einsetzen (sonst verbiegt jeder
   eingefügte Key die bestehende Raise-Spline) — Basiswerte linear nachrechnen und den
   Kick additiv drauflegen.
5. `validate_geo.py` + `./gradlew compileJava` nach jeder Runde, 1 Polish-Iteration.

---

## 1. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 1.1 A4s `warden_eye_laser` — aus Generator UND kompiliertem Asset gelesen

Quelle: `tools/photon/boss_b_fx.py` (nur gelesen) und Readback des gzip-NBT
`assets/eclipse/fx/boss/warden_eye_laser.fx` über `tools/photon/fxlib.py`:

| Emitter | Wert | Bedeutung für MA2 |
|---|---|---|
| Beam-Emitter | `duration = 20` Ticks, kein Loop | Beam brennt **0.00 s – 1.00 s** |
| Beam-Breitenkurve | Bezier 0.04 → 0.28, Crest bei **t = 18 Ticks** | „committed beam" bei **0.90 s** |
| `laser_probe` Bursts | Ticks **1, 8, 14** | Abfeuer-Momente **0.05 s / 0.40 s / 0.70 s** |
| `laser_probe` Speed | 2.4 b/Tick = 48 b/s | (A4s Raycast-Fix, für MA2 irrelevant) |
| `eye_charge` Motes | 2.5/Tick durchgehend | Ladephase, kein Recoil-Anker |

### 1.2 Tick-Trace der Kampf-Schleife (`RiftWardenEntity`)

- **Volley:** FX-Cue und `triggerAction("volley")` feuern auf **demselben Server-Tick**;
  der Action-Controller hat `transitionLength 0`, also Anim-t = 0 ≙ FX-t = 0.
  Server-Bolt-Release auf **T+21 = 1.05 s** — deckt sich exakt mit dem bereits
  vorhandenen Release-Snap der `volley` bei 1.05 s. Beam-Ende (1.00 s) liegt sauber davor.
- **Blink:** `blinkOutTimer = BLINK_OUT_TICKS (10)` wird auf demselben Tick T gesetzt wie
  `triggerAction("blink_out")`; `tickBlink` dekrementiert erst ab T+1 und ruft
  `executeBlink()` beim Übergang `0 → −1`. Der Teleport liegt also auf **T+11 = 0.55 s**
  — einen Tick nach dem Nennwert der Konstante.
  Die `blink_out` war 0.50 s lang → zwischen Animationsende und Teleport lag ein
  Fenster, in dem der Action-Controller leer ist und der Base-Controller (idle) mit
  vollem Scale durchschlägt. **Das ist die Ursache des harten Pops**, nicht die
  fehlende Unsichtbarkeit.

### 1.3 Haus-Konvention für Scale-Warps (übernommen, nicht erfunden)

`fog_tyrant.storm_step_out` nutzt `[0.5, 2.2, 0.5]`, `herald` blink `[0.55, 1, 0.55]` —
per-Achsen-Arrays mit eng gesetzten Keys, **kein** `pre`/`post`-Step. Das Sheet nutzt
`pre`/`post` nirgends; ich bleibe bei eng gesetzten Plain-Keys (deterministisch,
kein Kompatibilitätsrisiko).

---

## 2. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `src/main/resources/assets/eclipse/animations/entity/rift_warden.animation.json` | **einzige** Code-/Asset-Änderung: +178/−4 Zeilen |
| `docs/plans_v3/session_0730/MA2_WARDEN_REPORT.md` | dieser Report |

**Keine** Änderung an Geometrie, Textur, Painter, Java oder FX. Insbesondere:
`registerControllers` in `RiftWardenEntity` bleibt unverändert FINAL (base + action),
es kam kein Bone dazu (sonst wäre der Painter-Driver nötig gewesen), und
`glow_rift_core` existierte in der Geo bereits.

---

## 3. (a) `blink_out` / `blink_in` — Bone-Scale-Warp

### 3.1 Längenkorrektur (behebt den eigentlichen Pop)

`animation_length` von `blink_out` **0.5 s → 0.6 s**. Der letzte Scale-Key sitzt bei
0.50 s; GeckoLib **hält** dessen Wert bis zum Animationsende. Damit rendert der
Teleport-Tick T+11 (0.55 s) garantiert noch die Vanish-Pose, und auch ein um einen Tick
verspätetes `blink_in` findet dieselbe Pose vor. Nachgemessen mit GeckoLibs eigenem
Sampler (`AnimationController.getAnimationPointAtTick`, §5.2):

```
tick 10.0 (0.500s)  body.sX 0.0500  sY 2.2000
tick 11.0 (0.550s)  body.sX 0.0500  sY 2.2000   <-- executeBlink() Teleport-Tick
tick 12.0 (0.600s)  body.sX 0.0500  sY 2.2000
```

### 3.2 `blink_out` — Glitch-Stutter, dann Kollaps

Neue `scale`-Kanäle auf 5 Bones. `body` alterniert X/Z zwischen Squash und Overshoot,
während Y hochzieht — das liest als „schnappt kantig ein und flackert", nicht als
weiches Einschrumpfen:

| t | `body` scale (X, Y, Z) | Beat |
|---|---|---|
| 0.00 | 1.00, 1.00, 1.00 | neutral |
| 0.10 | **1.16**, 0.90, 1.06 | erste Beule |
| 0.18 | **0.58**, 1.22, 1.12 | −X-Squash |
| 0.24 | **1.30**, 0.96, 0.66 | +X-Overshoot, Z knickt |
| 0.32 | **0.42**, 1.40, 0.90 | −X-Squash |
| 0.40 | 0.80, 1.30, **0.34** | Z kollabiert |
| 0.46 | **0.20**, 1.90, 0.20 | Splitter |
| 0.50 | **0.05**, 2.20, 0.05 | Vanish-Schmierer (gehalten bis 0.60) |

Begleitende Kanäle:
- `head` — dieselbe Kurve, **1 Frame versetzt** (Keys 0.14/0.22/0.30/0.40/0.50), endet
  `0.06, 2.00, 0.06`. Der Versatz erzeugt das Doppelbild-Gefühl.
- `glow_rift_core` — **gegenläufig**: 1.00 → 1.25 → **1.60** → 1.15 → 0.30 (X/Z). Der Riss
  weitet sich, während die Rüstung zerknüllt: „der Riss frisst den Ritter".
- `crack_plate_chest` 1.00 → 1.30 → 0.25 → **0.05** (X), `crack_plate_faulds` phasenversetzt
  1.00 → 0.70 → 1.35 → **0.06** — die Platten kippen gegenläufig hochkant weg.

### 3.3 `blink_in` — Überschieß-Stretch

Startet **exakt** auf dem Endframe von `blink_out` (nachgemessen, §5.2), federt über
das Ziel hinaus und dämpft elastisch aus:

| t | `body` scale (X, Y) | Beat |
|---|---|---|
| 0.00 | 0.05, 2.20 | Sliver (== blink_out-Ende) |
| 0.06 | 0.22, 2.00 | reißt auf |
| 0.12 | **1.45, 0.74** | Überschieß-Peak (zu breit / zu flach) |
| 0.20 | 0.78, 1.22 | Gegenschwinger |
| 0.30 | 1.14, 0.92 | 2. Überschieß |
| 0.40 | 0.94, 1.04 | |
| 0.50 | 1.02, 0.99 | |
| 0.60 | 1.00, 1.00 | neutral → nahtlos zurück in idle |

`head` peakt bei 0.16 statt 0.12 (**1 Frame Nachlauf**, Whip-Effekt), `glow_rift_core`
peakt bei 0.10 mit 1.70 und fällt zurück (der Riss stößt den Ritter aus und schließt),
beide `crack_plate_*` spiegeln die Elastik mit eigenem Timing.

---

## 4. (b) `idle` — Riss-Platten atmen (Molang)

### 4.1 Loop-Gesetz

Die `idle` ist 4.0 s lang und geloopt. Damit ein Sinus **wert- UND ableitungsstetig**
über die Naht läuft, muss `f · 4 s` ein Vielfaches von 360° sein → **f ∈ {90, 180, 270}°/s**.
Alle Formeln unten halten sich daran; nachgemessen in §5.1 (Naht-Sprung < 3e-8).

### 4.2 Die Formeln

`glow_rift_core` ist die **Lunge** — der langsame 90 °/s-Grundtakt (1 Atemzug / 4 s
≈ 15 Atemzüge/min):

```
glow_rift_core.scale = [ 1 + math.sin(query.anim_time * 90) * 0.05 ,
                         1 + math.sin(query.anim_time * 90) * 0.035 ,
                         1 + math.sin(query.anim_time * 90) * 0.05 ]
```

`crack_plate_chest` — Grundphase **+40°** hinter der Lunge, plus 270 °/s-Oberwelle:

```
position = [ 0 ,
             math.sin(query.anim_time * 90 + 40) * 0.3 ,
             -0.42 + math.sin(query.anim_time * 90 + 40) * 0.3
                   + math.sin(query.anim_time * 270 + 25) * 0.12 ]
rotation = [ math.sin(query.anim_time * 90 + 40) * 2.6 , 0 ,
             math.sin(query.anim_time * 180 + 110) * 1.4 ]
scale    = [ 1 + math.sin(query.anim_time * 90 + 40) * 0.045 ,
             1 + math.sin(query.anim_time * 90 + 40) * 0.03 , 1 ]
```

`crack_plate_faulds` — Grundphase **+240°**, andere Oberwellen (180 °/s statt 270 °/s in Z,
270 °/s statt 180 °/s in rotZ). **Andere Phase UND andere Harmonik** = kein Gleichtakt:

```
position = [ 0 ,
             math.sin(query.anim_time * 90 + 240) * 0.22 ,
             -0.36 + math.sin(query.anim_time * 90 + 240) * 0.24
                   + math.sin(query.anim_time * 180 + 300) * 0.12 ]
rotation = [ math.sin(query.anim_time * 90 + 240) * 2.2 , 0 ,
             math.sin(query.anim_time * 270 + 60) * 1.6 ]
scale    = [ 1 + math.sin(query.anim_time * 90 + 240) * 0.04 ,
             1 + math.sin(query.anim_time * 90 + 240) * 0.028 , 1 ]
```

`glow_under` (Schwebesäule) atmet in **Gegenphase** (+180°) mit, damit die Säule
einzieht, wenn die Brust ausatmet:

```
glow_under.scale = [ 1 , 0.95 + math.sin(query.anim_time * 90 + 180) * 0.05 , 1 ]
```

Negatives Z = Platte steht proud vom Panzer ab. Der konstante Offset (−0.42 / −0.36)
sorgt dafür, dass Z **nie positiv** wird, die Platte also nie in den Torso einsinkt —
gemessener Bereich chest `[−0.812 … −0.028]`, faulds `[−0.672 … −0.048]` (§5.1).

---

## 5. (c) `volley` — Schulter-Recoil pro Salve

### 5.1 Anker

Drei Kicks auf die drei `laser_probe`-Bursts **0.05 s / 0.40 s / 0.70 s**, mit
Intensitätsrampe **0.55 → 0.78 → 1.00** passend zur ansteigenden Beam-Breitenkurve.
Der vierte Beat (Release 1.05 s) existierte bereits und wurde nicht angefasst.

### 5.2 Warum die Keys so sitzen

Der Torso trägt `catmullrom`-Keys — ein eingefügter Key würde die Spline verbiegen.
Recoil geht deshalb **ausschließlich** in linear interpolierte Kanäle:
`pauldron_left/right` (rotation + position), `head.rotation`, `crack_plate_chest`
(position + rotation), `crack_plate_faulds.position`, `glow_rift_core.scale`.

Pro Schuss ein 3-Key-Muster: **pre** (Basiswert, +0.02 s vor dem Schuss) → **kick**
(+0.07 s nach dem pre) → **settle** (teilweise Rückkehr). Basiswerte wurden aus den
bestehenden Keys linear nachgerechnet und der Kick additiv daraufgelegt, damit die
vorhandene Raise-Kurve exakt erhalten bleibt.

Beispiel `pauldron_left.rotation.z` (Basis = `−6 − 13.333·t` Grad):

| t | Basis | Key | Kick | Anlass |
|---|---|---|---|---|
| 0.02 | −6.27 | −6.27 | 0 | pre Schuss 1 |
| **0.07** | −6.93 | **−10.78** | **−3.85** | Kick 1 (−7° × 0.55) |
| 0.21 | −8.80 | −9.49 | −0.69 | settle |
| 0.37 | −10.93 | −10.93 | 0 | pre Schuss 2 |
| **0.42** | −11.60 | **−17.06** | **−5.46** | Kick 2 (−7° × 0.78) |
| 0.56 | −13.47 | −14.45 | −0.98 | settle |
| 0.67 | −14.93 | −14.93 | 0 | pre Schuss 3 |
| **0.72** | −15.60 | **−22.60** | **−7.00** | Kick 3 (−7° × 1.00) |
| 0.82 | −16.93 | −18.19 | −1.26 | settle → mündet in Peak 0.90 |

`pauldron_right` ist X-gespiegelt (rotZ `+8 … +24.6`, position `+X`). Ergänzend:
`head.rotation.x` nickt pro Schuss zurück (−2.75 / −3.90 / −5.00 °) mit Z-Jitter
±0.88/1.25/1.6 °, `crack_plate_chest` und `crack_plate_faulds` klappern nach außen,
und `glow_rift_core.scale` pulst **1.13 → 1.20 → 1.30** und entlädt sich auf 0.62 beim
Bolt-Release — das Auge, das den Strahl abgibt.

---

## 6. Validierung

### 6.1 Pflicht-Checks

```
$ python3 scripts/geckolib_gen/validate_geo.py \
      src/main/resources/assets/eclipse/geo/entity/rift_warden.geo.json \
      src/main/resources/assets/eclipse/animations/entity/rift_warden.animation.json
  -> PASS (0 error(s), 0 warning(s))      [geo, 21 Bones]
  -> PASS (0 error(s), 0 warning(s))      [anim, 9 Animationen]
  validate_geo: 2/2 file(s) passed — all good

$ ./gradlew compileJava processResources
  BUILD SUCCESSFUL
```

> **Fremd-Fehler-Vermerk (§5):** ein `compileJava --rerun` um 09:50 UTC schlug einmalig
> fehl; die Wiederholungen (3×) sind alle `BUILD SUCCESSFUL`. Ursache war eine
> Java-Datei eines Parallel-Teams mitten im Schreibvorgang — **nicht** MA2 (MA2 ändert
> keine einzige `.java`-Datei, siehe §2).

### 6.2 Runtime-Gegenprobe mit GeckoLibs EIGENEM Parser

Auf dieser VM belegen zwei fremde Clients ~7.7 GB von 16 GB (AGENTS.md warnt explizit
vor lingering `devlaunch.Main`-JVMs), es sind nur ~3.1 GB frei und Swap ist 0 — ein
dritter Client hätte mit hoher Wahrscheinlichkeit den OOM-Killer auf eine fremde
Session gehetzt. Statt zu raten habe ich die riskante Stelle (lädt GeckoLib meine
neuen `scale`-Kanäle und Molang-Ausdrücke überhaupt?) **direkt gegen die echte
Runtime** geprüft: eine Wegwerf-Harness in `/tmp/ma2harness/` hängt
`geckolib-neoforge-1.21.1-4.9.2.jar` in den Klassenpfad und ruft
`BakedAnimationsAdapter` bzw. den Molang-Rechner von GeckoLib auf.

Ergebnis (Artefakt `ma2_geckolib_runtime_parse.txt`):

- **PARSE OK**, 9 Animationen; `blink_out`/`blink_in` je 12 Ticks mit **5** Scale-Kanälen,
  `idle` 80 Ticks mit 4, `volley` 28 Ticks mit 1.
- Naht-Kontinuität `blink_out`-Ende ↔ `blink_in`-Start für alle 5 Bones **EXACT**
  (Differenz 0.0, nicht nur „nah dran").
- Idle-Loopnaht: |ΔWert| 2.7e-08 (chest) / 1.4e-15 (faulds), |ΔGeschwindigkeit| ~1.5e-04
  → wert- und ableitungsstetig.
- Gegenphase der Platten: Auswärts-Extrema **1.69 s auseinander** (Maximum wären 2.00 s),
  Korrelation **−0.780** → nachweislich kein Gleichtakt.
- Tail-Verhalten der `blink_out` mit GeckoLibs eigenem Sampler bestätigt (§3.1).

### 6.3 Offline-Playblast

Der Client rendert hier auf llvmpipe mit Sekunden pro Frame (AGENTS.md) — ein 1-Tick-Recoil
oder ein 2-Frame-Glitch-Schmierer ist so grundsätzlich nicht einfangbar. Ich habe deshalb
Geometrie + Animation offline gesampelt und orthografisch gerendert:

- `ma2_blink_scale_warp_before_after.png` — 4 Zeilen Kontaktbogen (blink_out VORHER/NACHHER,
  blink_in VORHER/NACHHER), Silhouetten aus den echten Cube-Daten.
- `ma2_volley_shoulder_recoil_vs_probe_bursts.png` — Recoil-Kurven mit FX-Markern.
- `ma2_idle_plate_breathing_antiphase.png` — Atemkurven beider Platten + Lunge.

---

## 7. Test-Rezept (in-game)

Voraussetzung: keine fremde Session auf dem Desktop, sonst nach AGENTS.md per PID beenden.

```bash
cd /workspace/ProjectEclipse
./gradlew runClient          # llvmpipe: 20–40 s pro Aktion einplanen
```

Im Spiel (Creative, `/gamerule doDaylightCycle false` hilft beim Fotografieren):

1. **idle-Atmung:** `/summon eclipse:rift_warden ~ ~ ~5` und **nicht** angreifen.
   Seitlich draufschauen (F5 → Seitenansicht). Erwartung: die Brustplatte und die
   Faulds-Platte heben/senken sich **sichtbar versetzt**; wenn beide gleichzeitig
   ausschlagen, ist die Phase kaputt. Periode 4 s, Extrema 1.7 s auseinander.
2. **volley-Recoil:** aus ~12 Blöcken Distanz aggro ziehen und die Volley-Phase abwarten
   (Cooldown 6 s). Erwartung: während der 1 s Beam **drei** Schulter-Zucker
   (0.05 / 0.40 / 0.70 s), dann der große Release-Snap bei 1.05 s.
   Kontrolle ohne schnelle Augen: `/dev photon test "eclipse:boss/warden_eye_laser"` in
   Zeitlupe danebenlegen — die Probe-Bursts müssen mit den Zuckern zusammenfallen.
3. **blink:** in Nahkampfreichweite bleiben, bis der Blink-Timer (10 s) auslöst.
   Erwartung: der Warden zieht sich zu einem senkrechten Schmierer zusammen, ist weg,
   und **platzt** am Zielort zu breit/zu flach heraus, bevor er einschwingt.
   Es darf **kein** Frame mit voller, unverzerrter Silhouette zwischen Vanish und
   Reappear aufblitzen — genau das war der alte harte Pop.
4. **Regression:** `attack`, `summon`, `stagger`, `death` einmal durchlaufen lassen —
   diese Animationen wurden nicht angefasst und dürfen sich nicht verändert haben.

Offline-Äquivalent (ohne Client, sekundenschnell):

```bash
python3 scripts/geckolib_gen/validate_geo.py \
    src/main/resources/assets/eclipse/geo/entity/rift_warden.geo.json \
    src/main/resources/assets/eclipse/animations/entity/rift_warden.animation.json
```

---

## 8. Koordinations-Snippets

### 8.1 An A4 (FX-Besitzer `warden_eye_laser`) — nur Info, keine Aktion nötig

MA2 hat sich auf dein Asset getimt, nicht umgekehrt. Falls du die Beam-Zeiten änderst,
brauche ich Bescheid — diese vier Zahlen sind in der `volley` hart verdrahtet:

| FX-Ereignis | Tick | Anim-Zeit | Reaktion in `rift_warden.animation.json` |
|---|---|---|---|
| `laser_probe` Burst 1 | 1 | 0.05 s | Kick 1 @ 0.07 s (55 % Intensität) |
| `laser_probe` Burst 2 | 8 | 0.40 s | Kick 2 @ 0.42 s (78 %) |
| `laser_probe` Burst 3 | 14 | 0.70 s | Kick 3 @ 0.72 s (100 %) |
| Beam-Breite Crest | 18 | 0.90 s | bestehender Raise-Peak (unverändert) |

Bewegte Bones während des Beams, falls du FX daran hängen willst:
`pauldron_left` (Pivot −5.5, 37, 0), `pauldron_right` (4, 36.5, 0),
`head` (0, 38, 0), `glow_rift_core` (2.5, 30, 0 — pulst 1.13/1.20/1.30 pro Schuss).

Zur Klarstellung, falls du den Strahlursprung je an das Modell koppeln willst: aktuell
hängt er **nicht** an einem Bone, sondern an `getEyePosition()`, also an
`RiftEntities` → `.sized(1.1F, 3.0F).eyeHeight(2.6F)` = **2.6 Blöcke ≙ 41.6 Modell-px**.
Der nächstgelegene Bone wäre `head` (Pivot y = 38, Würfel 38–45).

### 8.2 An den Integrator

- Genau **eine** Datei geändert: `assets/eclipse/animations/entity/rift_warden.animation.json`.
  Keine Java-, Geo-, Textur-, Painter- oder FX-Änderung → konfliktfrei zu allen
  Parallel-Teams. Nicht committet (Anweisung).
- `blink_out.animation_length` ist jetzt 0.6 s statt 0.5 s. Das ist **absichtlich** und
  an `RiftWardenEntity.BLINK_OUT_TICKS` (= 10, Teleport effektiv auf T+11 = 0.55 s)
  gekoppelt: wer die Konstante ändert, muss die Länge mitziehen, sonst kehrt der harte
  Pop zurück.

### 8.3 Offener Punkt (bewusst nicht gemacht, Scope-Creep)

Der Entity-Schatten bleibt während des Vanish in voller Größe stehen, weil der Scale-Warp
rein clientseitig in der Animation lebt. Sauber wäre ein synchronisiertes Blink-Flag
(neuer `EntityDataAccessor` + Abfrage im Renderer) — das ist eine Java-Änderung an
`entity/boss/rift/` + `client/entity/rift/` und gehört in ein eigenes Ticket.
