# MC5 — Glitch Emitter / Mansion-Dome (Welle M-C, Mob/Item-Zensus F-098)

**Auftrag:** MOB_ITEM_CENSUS §5 Welle M-C Zeile MC5 — (a) Ring-Dauerrotation via Molang
(`query.anim_time`), loop-nahtlos; (b) `hit` von 10 auf 30+ Keyframes mit **Ring-Desync**;
(c) `death`-Kollaps exakt auf C3s DomeShatter-Beats getimt; (d) Selbstkritik + weitere
Polish-Pässe.

**Datei-Besitz (exklusiv, §5-G1):** `woah/mansiondome/*` (Entity + Renderer),
`glitch_emitter*` (geo/animation/textures), `tools/woahdome/gen_glitch_emitter_textures.py`,
`docs/uv/glitch_emitter.md`, dieser Report.
**Nicht angefasst:** `DomeShatterFx`/`MansionDomeService`/`MansionDomeClient` (C3s
Shatter-Choreografie — nur **gelesen** fürs Timing), FROZEN-Basen (`EclipseGeoMob`,
`EclipseGeoAnimations`, `EclipseGeoRenderer`), `validate_geo.py`/`paint_lib.py`,
`tools/photon/**`, `assets/eclipse/fx/**`, Lang-/Sound-JSONs (keine neuen Keys nötig →
**kein** `langdrop/MC5-EMITTER.json`), Dateien von MC1–MC4/MD4.

---

## 0. Plan (vor der Implementierung festgehalten)

1. C3s Beat-Tabelle nicht aus dem Report abschreiben, sondern aus `MansionDomeService`
   nachrechnen — insbesondere **wann die Entity verschwindet**, denn darauf muss der
   Kollaps enden, nicht auf „irgendwann bei 1.5 s".
2. GeckoLib-Runtime-Fakten belegen statt annehmen: Ist `query.anim_time` Sekunden oder
   Ticks? Wird es pro Loop zurückgesetzt? Überschreibt der `action`-Controller den
   `base`-Controller oder addiert er? → aus dem dekompilierten `geckolib-4.9.2.jar`.
3. Dauerrotation braucht eine **Bone-Trennung**: ein Bone trägt die Molang-Endlosdrehung
   (Idle, läuft immer), ein zweiter trägt die One-Shot-Eingriffe. Sonst kämpfen beide
   Controller um denselben Kanal → Pop bei jedem Treffer.
4. Ring-Desync auf **Segment-Ebene**, nicht als Ganz-Ring-Ruck — dafür müssen die „Ringe"
   überhaupt erst Ringe sein (siehe 1.4).
5. Alles offline gegen GeckoLibs eigenen Parser/Easing/Molang-Evaluator beweisen (kein
   GPU auf der VM), plus texturierte Playblasts als Sichtprüfung.
6. `validate_geo.py` 0/0, Textur-Generator 2× md5-identisch, `compileJava` grün, ≥ 2
   Selbstkritik-Pässe.

---

## 1. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 1.1 C3s Zerstörungs-Beats — aus `MansionDomeService` nachgerechnet

| Konstante | Tick | Sekunde | Was passiert (Quelle) |
|---|---|---|---|
| `T_DEVICE_DEATH` | 0 | 0.00 | `beatDeviceDeath` → `device.triggerAction(ANIM_DEATH)`, `ANVIL_LAND` (Pitch 0.6), `EVENT_BORDER_GLITCH`, `CUE_DOME_DEVICE_HIT`, Datamosh-Zone r24 für 60 t |
| `T_SHAKE` | 10 | 0.50 | `beatShake(0.6F, 20 t, r200)` → `S2CShakePayload` |
| `T_LOOT` | 20 | 1.00 | `beatLoot` → 3 Glitch-Shards + Vitae-Shard + XP + `PLAYER_LEVELUP` |
| `T_SHATTER` | 30 | 1.50 | `beatShatter` → **`discardDevice()`**, `DomeShatterFx.begin()` (240 Hull-Shards), `CUE_DOME_SHATTER_BURST`, `EVENT_STORM_SHATTER`, `GENERIC_EXPLODE`, `beatShake(1.0F, 30 t, r300)` |

**Das entscheidende Detail:** `beatShatter` ruft `discardDevice(level, state)` — die Entity
ist auf Tick 30 **weg**. Der Kollaps hat also nicht „ungefähr 1.5 s" Zeit, sondern muss auf
Tick 30 eine **leere Silhouette** hinterlassen, sonst poppt das Gerät mitten im Shard-Burst
aus dem Bild. Genau daran ist die HEAD-Fassung gescheitert (siehe 3.1, Bug B-1).

`MansionDomeClient.COLLAPSE_SHATTER_TICK = T_SHATTER` und
`COLLAPSE_BEAM_END_TICK = T_SHATTER + 20` bestätigen: die Shell schaltet auf demselben
Beat hart ab, der Beam kollabiert danach über t30 → t50. Die Anim endet also bewusst,
bevor C3s Nachlauf beginnt.

### 1.2 GeckoLib 4.9.2 — Molang-Semantik (dekompiliert, nicht geraten)

`AnimationController.processCurrentAnimation`:

```java
MathParser.setVariable("query.anim_time", () -> finalAdjustedTick / 20.0);   // Z. 352
```

und im Transitions-Zweig:

```java
MathParser.setVariable("query.anim_time", () -> 0.0);                        // Z. 304
```

Daraus folgt hart:

- `query.anim_time` ist in **Sekunden** seit dem letzten `adjustTick`-Reset.
- Beim Loop setzt `processCurrentAnimation` `shouldResetTick = true` → **anim_time startet
  bei jedem Durchlauf wieder bei 0**. Die Loop-Naht ist damit ein echter Sprung
  `f(len) → f(0)`, nicht ein stetiger Weiterlauf.
- **Loop-Gesetz:** jede Molang-Frequenz `f` (°/s) muss `f · 4.0 s ≡ 0 (mod 360)` erfüllen,
  also `f ∈ {90, 180, 270, 360, …}`. Alle fünf Idle-Kanäle halten das ein.
- Während der 4-Tick-Transition des `base`-Controllers steht `anim_time` auf 0, die Ringe
  stehen dort also. Das passiert genau einmal beim Spawn und ist unsichtbar.

### 1.3 Controller-Interaktion — override, nicht additiv

`AnimationProcessor.tickAnimation` lässt die Controller in Registrierungsreihenfolge
schreiben (`base` zuerst, `action` danach), und `AnimationController` setzt die Bones per
`bone.setRotX(value + initialSnapshot)` — ein **Set**, kein Add. Wer zuletzt schreibt,
gewinnt den Kanal.

Zweitens `AnimationController.handleAnimationState` / `tryTriggerAnimation`:

```java
if (this.triggeredAnimation != null) {
    if (this.currentRawAnimation != this.triggeredAnimation) this.currentAnimation = null;
    this.setAnimation(this.triggeredAnimation);      // baut Queue neu, shouldResetTick
```

Ein neu getriggerter One-Shot **unterbricht den laufenden sofort** (bei
`transitionLength = 0` ohne Blend). Das ist die Ursache von Bug B-4 (siehe 3.4).

### 1.4 HEAD-Bestand — was tatsächlich dastand

- 18 Bones / 16 Cubes auf einem 128²-Canvas (~11 % belegt).
- `hit`: **10 Keyframes** auf 3 Bones (`root`, `core`, `ring_outer`), 0.35 s. Kein Desync.
- `idle`: 17 Keyframes; `ring_outer` fuhr 0 → 360° über **Keyframes**, `ring_inner` 0 → 0
  (drehte also gar nicht). Kein Molang.
- `death`: 27 Keyframes auf 5 Bones.
- **Die „Ringe" waren keine Ringe.** `ring_*_seg_*` waren je 4 **radiale Speichen**
  (`5×2×3` bzw. `3.5×1.6×2` mit Ursprung nahe der Achse) — von oben ein Kreuz, kein Reifen.
  Ein „Ring-Desync" an vier Speichen liest sich als Wackeln, nicht als aus-dem-Takt-Ring.
- Die `3.5×1.6×2`-Cubes des Innenrings erzeugten **24 fractional-UV-Warnungen** im
  Validator (die Vorgabe ist 0 Warnungen).

---

## 2. Was gebaut wurde

### 2.0 Geometrie-Umbau (Voraussetzung für a–c)

`glitch_emitter.geo.json`: 18 → **32 Bones**, 16 → **24 Cubes**, Canvas 128² → **64²**.

Beide Reifen sind jetzt **Achtecke aus 8 tangentialen Segmenten** (Außenring `2×2×7`
auf r = 10, Innenring `1×2×5` auf r = 6.25). Alle Cube-Maße sind ganzzahlig → 0
fractional-UV-Warnungen.

Die neue Kette pro Reifen ist der Kern des ganzen Pakets:

```
pylon
└─ ring_outer          <- GIMBAL: Kippen/Absacken (nur death)
   └─ ring_outer_brake <- BREMSE: Phasen-Eingriff (hit + death)
      └─ ring_outer_spin  (rest rotation [15, 0, 0])   <- MOLANG-DAUERDREHUNG (nur idle)
         └─ ring_outer_seg_0..7                        <- DESYNC (hit + death)
```

Warum drei Bones statt einem: `Ry(brake) · Ry(spin) = Ry(brake + spin)`, weil die Bremse
der **direkte** Elternknoten des Spin-Bones ist. Die scheinbare Ringgeschwindigkeit ist
damit exakt `Idle-Rate + Steigung des Bremskanals` — ein One-Shot kann den Ring anhalten,
überholen lassen oder festbremsen, **ohne** den Idle-Kanal anzufassen. Idle und One-Shots
teilen sich dadurch keinen einzigen Kanal (Law 1 unten).

`core_pulse` (Idle-Atmung) und `antenna_sway` (Idle-Schwanken) sind aus demselben Grund von
`core` bzw. `antenna` (One-Shot-Verformung) getrennt.

Rest-Kippung `+15°` außen / `−24°` innen um X: die Reifen laufen in verschiedenen Ebenen,
kreuzen sich optisch und können bei 2.25 px radialem Abstand nie kollidieren.

### 2.1 (a) Ring-Dauerrotation via Molang

`idle` (4.0 s, loop) animiert **nur noch 4 Bones** — die Idle-Seite der Trennung:

| Bone | Kanal | Ausdruck |
|---|---|---|
| `ring_outer_spin` | rot.y | `query.anim_time * 90 + math.sin(query.anim_time * 180) * 2.5` |
| `ring_inner_spin` | rot.y | `query.anim_time * -180 + math.sin(query.anim_time * 270 + 35) * 3.5` |
| `core_pulse` | scale x/y/z | `1 + math.sin(query.anim_time * 90) * 0.045` / `… * 90 + 25) * 0.06` / `… * 0.045` |
| `core_pulse` | pos.y | `math.sin(query.anim_time * 90) * 0.45` |
| `antenna_sway` | rot x/y/z | `math.sin(… * 90 + 20) * 1.6` / `math.sin(… * 180) * 3.0` / `math.sin(… * 270 + 110) * 1.2` |

Außenring 1 Umdrehung / 4 s im Uhrzeigersinn, Innenring 2 Umdrehungen / 4 s gegenläufig —
plus ein Servo-„Jagen" auf einer anderen Oberwelle (180 vs. 270 °/s) und mit Phasenversatz,
damit die beiden Reifen nie in den Gleichtakt fallen. Alle Frequenzen aus {90, 180, 270},
also `f · 4 s ∈ {360°, 720°, 1080°}` → naht-stetig in **Wert und Ableitung** (Beweis 4.2).

Das ganze Sheet braucht dafür **5 Keyframes** statt der bisherigen Keyframe-Rampe — die
Rotation läuft jetzt wirklich endlos und nicht mit einem Reset pro Loop.

### 2.2 (b) `hit`: 10 → 135 Keyframes mit echtem Ring-Desync

Länge **0.45 s (9 Ticks)** — bewusst *unter* `DomeEmitterEntity.HIT_IFRAME_TICKS = 10`,
weil GeckoLibs `tryTriggerAnimation` einen Trigger nur aus `State.STOPPED` sauber neu
startet; eine Anim länger als das I-Frame-Fenster verschluckt den nächsten Flinch.

Aufbau in vier Schichten:

1. **Chassis-Recoil** — `root` (rot + pos), `pylon`, `core`-Squash/Stretch, `antenna`-Kick.
2. **Ganz-Ring-Phasenruck** über die Bremskanäle: der Außenring **bleibt stehen**
   (scheinbar +0 °/s für 0.05 s) und holt danach mit Überschuss auf (+131.7 °/s); der
   Innenring macht das Gegenteil und **schießt zuerst vor** (−360 °/s, doppelte Drehzahl),
   bremst dann auf −117.5 °/s ab. Die beiden Reifen geraten also gegeneinander aus dem
   Takt statt gemeinsam zu ruckeln.
3. **Segment-Desync-Welle** — pro Segment ein azimutales Scheren (±9…12°) plus
   Radial-Pop (Scale) plus ein **Out-of-plane-Kippen** über den Z-Kanal. Der Z-Kanal wird
   von GeckoLib *außerhalb* der Rest-`Ry`-Azimut komponiert (`Rz · Ry · Rx` der Summe aus
   Rest + Anim), kippt das Segment also je nach Sitzposition unterschiedlich stark aus der
   Reifenebene → der Ring **beult**, statt nur zu leiern. Die Welle läuft außen mit der
   Drehrichtung (22 ms/Segment), innen dagegen (18 ms/Segment).
4. **Rückfang** — jeder Kanal ist bei `t = 0.45` wieder exakt auf Neutral, und die Bremse
   steht wieder auf 0, d. h. die Ringphase ist **verlustfrei eingeholt**: nach dem Treffer
   stehen die Reifen genau dort, wo sie ohne Treffer stünden.

### 2.3 (c) `death`: Kollaps auf C3s Beats

Länge **1.5 s = 30 Ticks = `T_SHATTER`**, 218 Keyframes, `hold_on_last_frame`.

Die Beat-Tabelle steht in Abschnitt 5, hier die Mechanik:

- **Gyroskop-Bremse:** die Bremskanäle haben eine Steigung, die die Idle-Drehzahl
  aufzehrt. Außen `+90 °/s` nominal → scheinbar +70 → +41.4 → +6.0 → **±0.0 °/s ab
  1.20 s**; innen `−180 °/s` → −126.7 → −65.7 → −20.0 → **±0.0 °/s ab 1.15 s**. Die
  Reifen kommen also *sichtbar zum Stillstand*, obwohl der Idle-Controller ununterbrochen
  weiterdreht.
- **Gimbal-Kollaps:** `ring_outer` kippt auf (52°, 0, −28°) und sackt 6.2 px,
  `ring_inner` gegenläufig auf (−44°, 0, 31°) — die Kreiselachsen fallen auseinander.
- **Core-Ruptur:** Aufblähen bis 1.45× bei 0.95 s, Bruch-Squash bei **1.00 s = `T_LOOT`**
  (der Moment, in dem der Service die Shards auswirft), danach Implosion auf **exakt 0**
  bei 1.50 s.
- **Ganz-Rig-Implosion (Polish-Pass 2, siehe 3.1):** `pylon.scale` und `base.scale` ziehen
  die komplette Baugruppe in den Sockel; der Silhouetten-Faktor `base.sY · pylon.sY` steht
  bis Tick 20 auf 1.0, macht bei Tick 23 eine kurze Anticipation-Streckung auf 1.042 und
  fällt dann auf 0.731 → 0.104 → 0.023 → **0.0000 auf Tick 30**.
- **T_SHAKE-Akzent:** bei 0.50 s ein scharfer Lurch in `root` (pos −1.25 px, rot 2.6/−4.2°
  in 1 Tick, danach zurück) — die Kamera fängt genau dann an zu schütteln.

### 2.4 Java (`DomeEmitterEntity`)

Eine inhaltliche Änderung (Bug B-4, siehe 3.4): der **tödliche Treffer** löst keinen
Flinch mehr aus.

```java
if (this.hitsRemaining() > 1) {
    triggerAction(ANIM_HIT);
}
```

`DomeEmitterRenderer` blieb unverändert (Glowmask + Tint + Jitter passen weiter).

### 2.5 Texturen (nur über den Generator)

`tools/woahdome/gen_glitch_emitter_textures.py` auf das neue 64²-Layout umgestellt (8
Atlas-Rects statt der alten 128²-Streuung), plus zwei Lesbarkeits-Fixes aus den
Playblasts (Bugs B-5/B-6). Vollständige Rect-Tabelle + Art-Brief: `docs/uv/glitch_emitter.md`.

---

## 3. Gefundene Bugs (und was daraus wurde)

| # | Befund | Status |
|---|---|---|
| **B-1** | **`death` hinterlässt auf `T_SHATTER` ein volles Gerät.** HEAD skalierte nur den Core auf 0 (und das schon bei 1.2 s, danach 0.3 s tote Frames); Sockel, Beine und Pylon standen auf Tick 30 in Originalgröße, als `discardDevice()` sie wegschaltete → harter Pop mitten im Shard-Burst. | Gefixt: Ganz-Rig-Implosion über `pylon.scale`/`base.scale`, Silhouette = 0.0000 auf Tick 30 (Trace in 4.5) |
| **B-2** | **Die „Ringe" waren radiale Speichen**, keine Reifen — an 4 Speichen ist ein Ring-Desync nicht darstellbar. | Gefixt: 8-Segment-Achtecke pro Reifen |
| **B-3** | **24 fractional-UV-Warnungen** durch die `3.5×1.6×2`-Cubes des Innenrings (Vorgabe: 0 Warnungen). | Gefixt: alle Maße ganzzahlig, Atlas auf 64² neu gepackt |
| **B-4** | **Flinch und Kollaps kollidieren.** Der 8. Treffer feuert `hit` und einen Tick später `death` auf demselben `action`-Controller; GeckoLib tauscht getriggerte Anims hart aus, der Flinch wird also 1 Tick nach dem Start — am Scheitel des Recoils — abgeschnitten und springt in die neutrale `death`-t0-Pose. | Gefixt in Java: tödlicher Treffer überspringt den Flinch |
| **B-5** | **Der Außenring war patina-grün statt kupfern.** Der Generator legte `edge_frame(..., COPPER_OXID)` auf die Seitenflächen — die sind aber nur `sy = 2` px hoch, ein 1-px-Rahmen deckt sie also zu **100 %** ab. | Gefixt: kein Frame; dunkle Gunmetal-Stoßkappen auf den 2×2-Segmentenden + 1-px-Oxid-Verschleißlinie |
| **B-6** | **Der Antennenknauf sah abgelöst aus.** Der 1×1-Mast war in `GUNMETAL_DARK` (≈ `#1E2125`) gemalt und verschwand gegen den dunklen Himmel — der leuchtende Knauf schwebte frei über dem Gerät. | Gefixt: Mast in mittlerem Gunmetal mit zwei Kupferkragen |
| **B-7** | **Die beiden Reifen lasen sich als ein dickes Band.** Radialer Abstand war nur 0.75 px, von oben nicht trennbar → der Innenring-Desync war unsichtbar. | Gefixt: Außenring von r = 8.5 auf **r = 10** (Abstand 2.25 px) |
| **B-8** | HEAD-`hit` ließ `ring_outer` von der Keyframe-Rampe des Idle wegspringen (beide Controller schrieben denselben Kanal). | Strukturell erledigt durch die spin/brake/gimbal-Trennung — Idle- und One-Shot-Bonemengen sind jetzt disjunkt (Law 1) |

### 3.1 Anmerkung zu B-1

Der Trace vor dem Fix zeigte `core.sX = 0` ab 1.2 s (0.3 s Standbild) und Sockel/Pylon
unverändert bei 1.0 — die Anim war also gleichzeitig zu früh fertig **und** zu spät.

### 3.4 Anmerkung zu B-4

Der Fix ist bewusst in der Entity und nicht in der Anim: eine `death`, die bei t0 auf
einer Recoil-Pose startet, würde jeden *anderen* Pfad kaputtmachen (Restart-Replay von
`tickCollapse` mit `cursor = −1`, `/dev`-Auslöser). Der billigste korrekte Ort ist die
Stelle, die weiß, dass es der letzte Treffer war.

---

## 4. Validierung (wörtlich)

### 4.1 `validate_geo.py` — 0 Errors / 0 Warnings

```
$ python3 scripts/geckolib_gen/validate_geo.py <geo> <anim>
    identifier geometry.glitch_emitter  canvas 64x64  32 bones  24 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/entity/glitch_emitter.animation.json
    'animation.glitch_emitter.idle': loop=True length=4.0 bones=4 keyframes=5 last_key=0.0s
    'animation.glitch_emitter.hit': loop=False length=0.45 bones=22 keyframes=135 last_key=0.45s
    'animation.glitch_emitter.death': loop='hold_on_last_frame' length=1.5 bones=25 keyframes=218 last_key=1.5s
    3 animation(s): animation.glitch_emitter.idle, animation.glitch_emitter.hit, animation.glitch_emitter.death
  -> PASS (0 error(s), 0 warning(s))

============================================================
validate_geo: 2/2 file(s) passed — all good
```

`hit` = **135 Keyframes** (Vorgabe 30+), `death` = 218.

### 4.2 GeckoLib-Runtime-Harness (eigener Harness gegen `geckolib-4.9.2.jar`)

Der Harness lädt Geo **und** Animationen durch GeckoLibs eigene Adapter, backt das Modell
mit GeckoLibs eigener `BakedModelFactory` (also exakt dem Client-Ladepfad) und sampelt
jeden Kanal durch GeckoLibs eigenes Easing + `MathParser`, mit `query.anim_time` genauso
gefüttert wie in `processCurrentAnimation`.

```
GEO BAKE OK (GeckoLib BakedModelFactory): 32 bones, 24 cubes, 144 quads, top-level=1

PARSE OK: 3 animations

  animation.glitch_emitter.death           len= 30.00t (1.50s) bones=25 xKeys=218
  animation.glitch_emitter.hit             len=  9.00t (0.45s) bones=22 xKeys=135
  animation.glitch_emitter.idle            len= 80.00t (4.00s) bones= 4 xKeys=5

=== LAW 1: idle-owned bones vs one-shot-owned bones are DISJOINT
  idle  : [antenna_sway, core_pulse, ring_inner_spin, ring_outer_spin]
  idle & hit   = []   OK
  idle & death = []   OK

=== LAW 2: idle molang seam (value + derivative), h = 1e-4 s
  ring_outer_spin  rotation |dValue|=(0.00e+00,1.00e-05,0.00e+00)  |dRate|=(0.00e+00,2.28e-01,0.00e+00)
  ring_inner_spin  rotation |dValue|=(0.00e+00,8.30e-06,0.00e+00)  |dRate|=(0.00e+00,1.66e-01,0.00e+00)
  core_pulse       position |dValue|=(0.00e+00,2.19e-08,0.00e+00)  |dRate|=(0.00e+00,1.70e-08,0.00e+00)
  core_pulse       scale    |dValue|=(0.00e+00,0.00e+00,0.00e+00)  |dRate|=(5.96e-04,1.19e-03,5.96e-04)
  antenna_sway     rotation |dValue|=(1.07e-07,2.92e-07,1.07e-07)  |dRate|=(5.34e-04,9.87e-07,2.13e-03)
  -- |dRate| vs step size (ring_outer_spin.rotation.y):
       h=1e-04      |dRate|=(0.00e+00,2.28e-01,0.00e+00)
       h=1e-03      |dRate|=(0.00e+00,8.98e-03,0.00e+00)
       h=1e-02      |dRate|=(0.00e+00,2.06e-03,0.00e+00)
       h=5e-02      |dRate|=(0.00e+00,2.48e-04,0.00e+00)
```

**Law 1** ist der Beweis, dass kein Kanal zwischen Idle und One-Shot umkämpft ist.

**Law 2, Wertsprung:** `|dValue| ≤ 1e-5°` an der Naht (Rotation modulo 360 verglichen,
weil eine Dauerdrehung über die Naht um ganze Umdrehungen weiterläuft).

**Law 2, Ableitungssprung:** die 2.28e-1 °/s beim kleinsten Schritt sind **kein** echter
Knick — ein echter Knick ist schrittweiten-invariant. Der h-Sweep zeigt einen Abfall um
Faktor ~920 bei 500× größerem h, also reines Rundungsrauschen der Sampling-Kette. Analytisch
ist die Naht ohnehin C¹: die Kanäle sind Summen aus einer Linearrampe mit
`f · 4 s ≡ 0 (mod 360)` und Sinus-Termen, deren Perioden die Looplänge teilen.

### 4.3 Ring-Desync — scheinbare Drehzahl = Idle-Drehzahl + Bremssteigung

```
=== LAW 3: apparent ring speed = idle spin + brake slope
  hit    ring_outer_brake   nominal   +90.0 deg/s
         0.00- 0.05s  brake    +0.00 ->    -4.50 deg   slope    -90.0   APPARENT     +0.0 deg/s
         0.05- 0.14s  brake    -4.50 ->    -8.00 deg   slope    -38.9   APPARENT    +51.1 deg/s
         0.14- 0.22s  brake    -8.00 ->    -6.50 deg   slope    +18.8   APPARENT   +108.8 deg/s
         0.22- 0.34s  brake    -6.50 ->    -1.50 deg   slope    +41.7   APPARENT   +131.7 deg/s
         0.34- 0.45s  brake    -1.50 ->    +0.00 deg   slope    +13.6   APPARENT   +103.6 deg/s
  hit    ring_inner_brake   nominal  -180.0 deg/s
         0.00- 0.04s  brake    +0.00 ->    -7.20 deg   slope   -180.0   APPARENT   -360.0 deg/s
         0.04- 0.10s  brake    -7.20 ->    -9.00 deg   slope    -30.0   APPARENT   -210.0 deg/s
         0.10- 0.18s  brake    -9.00 ->    -4.00 deg   slope    +62.5   APPARENT   -117.5 deg/s
         0.18- 0.30s  brake    -4.00 ->    +2.50 deg   slope    +54.2   APPARENT   -125.8 deg/s
         0.30- 0.45s  brake    +2.50 ->    +0.00 deg   slope    -16.7   APPARENT   -196.7 deg/s
  death  ring_outer_brake   nominal   +90.0 deg/s
         0.00- 0.15s  brake    +0.00 ->    -3.00 deg   slope    -20.0   APPARENT    +70.0 deg/s
         0.15- 0.50s  brake    -3.00 ->   -20.00 deg   slope    -48.6   APPARENT    +41.4 deg/s
         0.50- 1.00s  brake   -20.00 ->   -62.00 deg   slope    -84.0   APPARENT     +6.0 deg/s
         1.00- 1.20s  brake   -62.00 ->   -80.00 deg   slope    -90.0   APPARENT     -0.0 deg/s
         1.20- 1.50s  brake   -80.00 ->  -107.00 deg   slope    -90.0   APPARENT     +0.0 deg/s
  death  ring_inner_brake   nominal  -180.0 deg/s
         0.00- 0.15s  brake    +0.00 ->    +8.00 deg   slope    +53.3   APPARENT   -126.7 deg/s
         0.15- 0.50s  brake    +8.00 ->   +48.00 deg   slope   +114.3   APPARENT    -65.7 deg/s
         0.50- 1.00s  brake   +48.00 ->  +128.00 deg   slope   +160.0   APPARENT    -20.0 deg/s
         1.00- 1.15s  brake  +128.00 ->  +155.00 deg   slope   +180.0   APPARENT     +0.0 deg/s
         1.15- 1.50s  brake  +155.00 ->  +218.00 deg   slope   +180.0   APPARENT     -0.0 deg/s
```

### 4.4 Kein Snap rein, kein Pop raus

```
=== LAW 4: one-shot start/end == rest pose (no snap in, no pop out)
  animation.glitch_emitter.hit           worst |start-neutral| = 0.000000 (-)
  animation.glitch_emitter.hit           worst |end  -neutral| = 0.000000 (-)
  animation.glitch_emitter.death         worst |start-neutral| = 0.000000 (-)
  animation.glitch_emitter.death         worst |end  -neutral| = 217.999995 (ring_inner_brake.rotation)   [death holds — never released]
```

`hit` startet **und** endet auf exakt Neutral (0.000000): kein Sprung beim Einsetzen des
`action`-Controllers, kein Sprung beim Freigeben. Bei `death` ist der Endwert
erwartungsgemäß nicht neutral — die Anim hält auf dem letzten Frame und die Entity wird
auf demselben Tick entfernt.

### 4.5 `death`-Trace auf dem Beat-Raster

```
=== death: collapse trace on the dome beat grid
    t(s)  tick   base.sY pylon.sY  core.sX   SILHOU.  ring_outer rot(x,z)
    0.00     0    1.0000   1.0000   1.0000    1.0000  ( -0.00,  0.00)
    0.25     5    1.0000   1.0000   1.1458    1.0000  (  7.36, -4.63)
    0.50    10    1.0000   1.0000   1.1960    1.0000  ( 16.00, -9.00)
    0.75    15    1.0000   1.0000   1.3350    1.0000  ( 24.25,-13.63)
    1.00    20    1.0000   1.0000   1.3800    1.0000  ( 34.00,-19.00)
    1.15    23    1.0000   1.0417   0.7200    1.0417  ( 41.06,-22.53)
    1.25    25    0.8417   0.8686   0.4965    0.7310  ( 46.00,-25.00)
    1.40    28    0.3000   0.3467   0.1933    0.1040  ( 49.74,-26.87)
    1.45    29    0.1375   0.1667   0.1000    0.0229  ( 51.09,-27.54)
    1.50    30    0.0000   0.0000   0.0000    0.0000  ( 52.00,-28.00)
```

`SILHOU. = base.sY · pylon.sY` ist der Skalenfaktor, der die gesamte Baugruppe trägt
(Sockel → Pylon → Reifen/Core/Antenne). Auf Tick 30, dem Tick von `discardDevice()`, ist
er **exakt 0** — es gibt nichts mehr, das poppen könnte.

### 4.6 UV-/Atlas-Audit

```
canvas 64x64   24 cubes -> 8 distinct atlas rects
  OK  uv=( 0, 0) 48x15  size=(12, 3, 12)   glow=  0px  <- base
  OK  uv=( 0,16) 16x19  size=(4, 15, 4)    glow=  0px  <- pylon
  OK  uv=(16,16) 24x12  size=(6, 6, 6)     glow=288px  <- core
  OK  uv=(16,28) 12x7   size=(1, 2, 5)     glow= 15px  <- ring_inner_seg_0..7
  OK  uv=(40,16) 18x9   size=(2, 2, 7)     glow=  0px  <- ring_outer_seg_0..7
  OK  uv=(48, 0)  8x7   size=(2, 5, 2)     glow=  0px  <- leg_0..2
  OK  uv=(48,10) 12x6   size=(3, 3, 3)     glow= 72px  <- antenna
  OK  uv=(56, 0)  4x10  size=(1, 9, 1)     glow=  4px  <- antenna

  overlapping atlas pixels : 0
  atlas coverage           : 1726/4096 px (42.1%)
  emissive pixels total    : 379
  -> PASS
```

Beide PNGs sind 64×64 (Zensus §7 F-7: `AutoGlowingTexture` hard-failt sonst), jedes
Footprint liegt vollständig im Canvas, ist deckend gemalt und überlappt kein anderes.

### 4.7 Textur-Generator-Determinismus (2×, md5 identisch)

```
$ python3 tools/woahdome/gen_glitch_emitter_textures.py   # run 1
e5d35ba262e480e825334f93ddd35242  .../glitch_emitter_glowmask.png
c52de0eb31bcdd720330f79dbb5de150  .../glitch_emitter.png
$ python3 tools/woahdome/gen_glitch_emitter_textures.py   # run 2
e5d35ba262e480e825334f93ddd35242  .../glitch_emitter_glowmask.png
c52de0eb31bcdd720330f79dbb5de150  .../glitch_emitter.png
```

### 4.8 `./gradlew compileJava`

```
$ ./gradlew compileJava --console=plain
Reusing configuration cache.
> Task :createMinecraftArtifacts UP-TO-DATE
> Task :compileJava UP-TO-DATE

BUILD SUCCESSFUL in 705ms
2 actionable tasks: 2 up-to-date
Configuration cache entry reused.
```

**Hinweis an den Integrator:** zwischenzeitlich schlug `compileJava` mit 8 Fehlern in
`entity/SunmoteEntity.java` fehl (`glideTicks` / `GLIDE_HOLD_TICKS` nicht gefunden) — das
ist MC3s Datei mitten im Umbau, nicht meine. Während dieses Fensters habe ich mein Paket
isoliert übersetzt (`javac` über `woah/mansiondome/**` gegen `build/classes/java/main` +
Veil 4.3.0): **exit 0**, 11 Klassen. MC3 hat die Datei inzwischen repariert, der
Gesamt-Build ist wieder grün.

---

## 5. Death-Beat-Tabelle (das Kernstück von (c))

`t = 0` ist `T_DEVICE_DEATH`, also der Tick, auf dem `beatDeviceDeath` das
`triggerAction(ANIM_DEATH)` absetzt. Der `action`-Controller hat `transitionLength 0`,
Anim-t und Beat-t laufen also deckungsgleich.

| Tick | s | C3 / `MansionDomeService` | MC5 `death` — was zu sehen ist |
|---|---|---|---|
| **0** | 0.00 | `T_DEVICE_DEATH`: Anvil-Land (0.6), Border-Glitch, Device-Hit-Cue, Datamosh r24 | Start exakt auf Ruhepose (Law 4). Erster Ruck: `root` −1.1 px / 1.5°/−2.5°, Core-Blitz auf 1.32× bei 0.06 s, Pylon knickt an, Antenne schlägt −14° |
| 3–9 | 0.15–0.45 | — | Beide Bremsen greifen: außen +90 → +41.4 °/s, innen −180 → −65.7 °/s. Gimbals beginnen zu kippen (außen +16°/−9°, innen −14°/+11°), Reifen sacken 0.6–0.8 px |
| **10** | 0.50 | `T_SHAKE`: `S2CShakePayload(0.6F, 20 t, r200)` | **Lurch-Akzent:** `root` fällt in 1 Tick von −0.42 auf −1.25 px und kippt auf 2.6°/−4.2°, danach Rückfederung. Der Bildschirm fängt exakt hier an zu wackeln |
| 11–19 | 0.55–0.95 | Shake läuft | Außenring auf +6.0 °/s (praktisch stehend), Innenring −20.0 °/s. Segment-Splay startet, Core bläht auf **1.45×** (Maximum bei 0.95 s) |
| **20** | 1.00 | `T_LOOT`: 3 Glitch-Shards + Vitae-Shard + XP + Level-Up-Sound | **Core-Ruptur** — Bruch-Squash `[1.38, 1.06, 1.38]` genau hier; die Reifen verlieren ab diesem Frame endgültig die Formation (Segment-Splay staffelt sich mit 30 ms/Segment). Silhouette noch 1.0000 |
| 23 | 1.15 | — | Anticipation: Pylon streckt kurz auf 1.042 (Silhouette-Faktor), Core bereits auf 0.72 gefallen. Innenring-Bremse erreicht ±0.0 °/s |
| 24 | 1.20 | — | Außenring-Bremse erreicht ±0.0 °/s — **beide Kreisel stehen** |
| 25 | 1.25 | — | Implosion läuft: Silhouette 0.7310, Core 0.4965, Ringe auf (46°, −25°) gekippt und 4.6 px abgesackt |
| 28–29 | 1.40–1.45 | — | Silhouette 0.1040 → 0.0229; nur noch ein flacher Rest über dem Sockel |
| **30** | 1.50 | `T_SHATTER`: **`discardDevice()`**, `DomeShatterFx.begin()` (240 Shards), Shatter-Burst-Cue, Storm-Shatter + Explode, `beatShake(1.0F, 30 t, r300)` | **Silhouette exakt 0.0000**, Core-Scale exakt 0. Die Entity verschwindet in demselben Frame, in dem nichts mehr von ihr zu sehen ist — die Hülle zerspringt in ein leeres Loch |
| 50 | 2.50 | `COLLAPSE_BEAM_END_TICK`: Beam-Kollaps fertig | (nach MC5) |

---

## 6. Selbstkritik-Pässe

**Pass 1 — Struktur (nach dem ersten Bauen).** Der erste Wurf drehte die Ringe per Molang
direkt auf `ring_outer`/`ring_inner`. Der Harness zeigte sofort, dass `hit` und `death`
dieselben Bones anfassen (Law 1 rot) → jeder Treffer hätte die Dauerdrehung
weggeschrieben. Ergebnis: die spin/brake/gimbal-Kette (2.0). Im selben Pass fielen B-2
(Speichen statt Reifen) und B-3 (fractional UV) auf, plus Start-Snaps in `pylon` und
`antenna` der `hit` (fehlende `t = 0`-Keys) — Law 4 stand danach auf 0.000000.

**Pass 2 — Playblast gegen die Beats.** Aus GeckoLib-exakten Posen gerenderte
Contact-Sheets zeigten den Kollaps bis 1.24 s stimmig und danach ein volles Gerät, das auf
Tick 30 einfach verschwindet → **B-1**. Fix: Ganz-Rig-Implosion + der T_SHAKE-Lurch, der
vorher als weiche Spline durchlief und den Kameraschüttler nicht bediente. Außerdem in
diesem Pass: der Segment-Desync war von oben kaum lesbar, weil die Reifen sich als ein
Band lasen → **B-7** (Außenring auf r = 10) und ein zusätzlicher Out-of-plane-Kanal in der
Desync-Welle.

**Pass 3 — texturierter Playblast.** Bis dahin waren die Renders flach eingefärbt. Ein
Renderer, der jedes Texel aus der echten Box-UV zieht, deckte zwei Malfehler auf, die
farblos unsichtbar waren: **B-5** (Außenring komplett patina-grün, weil ein 1-px-Rahmen
eine 2-px-Fläche vollständig ausfüllt) und **B-6** (schwarzer Antennenmast → schwebender
Knauf). Beide nur über den Generator gefixt, nie am PNG.

**Pass 4 — Runtime-Audit der Java-Seite.** Beim Nachlesen von `tryTriggerAnimation` /
`handleAnimationState` fiel **B-4** auf (Flinch des Todesstoßes wird nach 1 Tick vom
Kollaps abgeschnitten). Ebenfalls hier geprüft und für gut befunden: `HIT_IFRAME_TICKS`
(10 t) > `hit`-Länge (9 t), also kann sich der Flinch nie selbst überlappen.

**Was ich mir vorwerfe.** Der Geometrie-Umbau ist größer, als eine reine Animationsaufgabe
sein müsste — ohne echte Reifen wäre der beauftragte Ring-Desync aber nur eine Behauptung
gewesen. Und Pass 3 hätte vor Pass 2 kommen sollen: zwei Polish-Runden liefen gegen
flach eingefärbte Renders, in denen Texturfehler grundsätzlich nicht sichtbar sein können.

---

## 7. Offene Punkte

1. **Kein `runClient`-Screenshot.** Zensus §8.4 verlangt eine Client-Sichtprüfung. Auf der
   VM liefen zum Arbeitszeitpunkt bereits vier fremde Minecraft-JVMs paralleler Teams
   (~7.5 GB, u. a. MA5) — ein fünfter Client hätte um World-Lock und RAM konkurriert.
   Ersatzweise: Geo **und** Animationen laufen durch GeckoLibs eigenen Ladepfad
   (`BakedModelFactory`, 144/144 Quads aufgelöst), Molang durch GeckoLibs eigenen
   `MathParser`, plus texturierte Playblasts aus genau diesen Posen. Eine Sichtprüfung im
   laufenden Client bleibt trotzdem offen und sollte beim nächsten freien Client-Slot
   nachgeholt werden — Kommando: `/summon eclipse:glitch_emitter`.
2. **`death` hält auf dem letzten Frame, der Idle-Spin läuft weiter.** Die Bremse steht
   dann fest auf −107° (außen) / +218° (innen), während der `base`-Controller weiterdreht
   — nach dem Halten würden die Reifen also wieder losdrehen. Praktisch unerreichbar, weil
   `beatShatter` die Entity auf demselben Tick entfernt (und Silhouette = 0 ist). Wer
   `death` künftig aus einem anderen Pfad triggert, ohne innerhalb von 30 Ticks zu
   `discard`en, muss das wissen.
3. **Keine eigenen Sounds.** Der Emitter recycelt weiter Vanilla-Sounds aus dem Service
   (Zensus §7 F-8: nur 11/87 Events gehören Mobs). Ein eigenes Ring-Servo-Loop + ein
   Bruch-Sample wären das nächste sinnvolle Paket, gehören aber ins Audio-Paket, nicht
   hierher.
4. **FX-Kopplung.** Für C3/A-Wellen, falls jemand Partikel an die Ringe hängen will, sind
   die stabilen Locator-Bones: `ring_outer_spin` / `ring_inner_spin` (drehen endlos, r =
   10 bzw. 6.25 px um Pivot `[0, 24, 0]`), `core` (Pivot `[0, 24, 0]`, pulsiert 1.0 ±
   0.06) und `antenna` (Knauf-Mitte `[0, 37.5, 0]` — der Ansatzpunkt des Himmelsstrahls).
   Ich habe keine `.fx`-Datei und keine Row angefasst.
