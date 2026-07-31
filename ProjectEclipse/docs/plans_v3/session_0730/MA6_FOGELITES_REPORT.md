# MA6 — Fog-Eliten (Fog Colossus + Storm Hound)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-A, Zeile **MA6**.
**Datei-Besitz (exklusiv):** `entity/fog/{FogColossus,StormHound}Entity` + `ChargedLungeGoal`
(+ `GroundSlamGoal` als Lese-Quelle), `client/entity/fog/{FogColossus,StormHound}Renderer`,
`geo/animations/textures fog_colossus*` + `storm_hound*`,
`scripts/geckolib_gen/mobs/{fog_colossus,storm_hound}.py`, `docs/uv/{fog_colossus,storm_hound}.md`.

**NICHT angefasst (Leitplanken):** `EclipseGeoMob`/`EclipseGeoMonster`/`EclipseGeoAnimations`/
`EclipseGeoRenderer` (FROZEN), `validate_geo.py`/`paint_lib.py` (FROZEN),
`tools/photon/mobs_fx.py`, `fx/hound_*`, `MobPhotonFxRows.java`, `PhotonMobFx.java`
(alles **B2-Besitz** — hier nur gelesen; die Wünsche stehen als Spec in §5/§6).
`registerControllers` bleibt final (`base` + `action`, keine dritten Controller).

---

## 0. Plan (vor der Implementierung geschrieben)

### 0.1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Datei | Ist-Stand |
|---|---|
| `geo/entity/fog_colossus.geo.json` | 18 Bones / 22 Cubes, Canvas 128², **kein** Kiefer-Bone, **kein** Brustkorb-Bone, **kein** Becken-Bone (`body` und beide `leg_*` hängen direkt an `root`) |
| `animations/entity/fog_colossus.animation.json` | 6 Anims: idle(4.0s), walk(1.6s/58kf), attack(0.8s), slam(2.0s/78kf), roar(1.5s/34kf), death(2.5s/60kf) |
| `geo/entity/storm_hound.geo.json` | 22 Bones / 22 Cubes, Canvas 64², `jaw` vorhanden, **keine** Schulterblatt-Bones (`leg_fl`/`leg_fr` hängen direkt an `body`) |
| `animations/entity/storm_hound.animation.json` | 7 Anims, **kein** `sprint`; `walk`(0.7s) bewegt beide Vorderbeine **in Phase** (= Bound, kein Diagonalgang) |
| `FogColossusEntity` | `slam`/`roar` Triggerables, roar auf erstem `setTarget`, Death 50t |
| `StormHoundEntity` | `charge_windup`/`lunge`/`howl` Triggerables, `handleBaseState` **nicht** überschrieben (= nur walk/idle) |
| `ChargedLungeGoal` | WINDUP 20t → DASH ≤14t @0.9 b/t → STAGGER 40t, Cooldown 160t |
| `GroundSlamGoal` | Telegraph `IMPACT_TICK`=27t, r=6 Welle, Recover 12t, Cooldown 200–240t |
| B2 (`B2_MOB_REPORT.md` §1) | `hound_dash_trail`: neuer `dash_grit`-Emitter, `distance_rate` 0.35 b/Partikel, `inheritVelocity +0.3`, `colorBySpeed`. Braucht meine Tick-Tabelle. |

`isMoving()`-Falle (§7 F-9): **greift hier nicht** — beide Mobs bewegen sich über
`PathNavigation`/`travel()`, also füttert `walkAnimation` den `limbSwingAmount` korrekt.
Der Hund fährt seinen Dash zwar per `setDeltaMovement`, aber das ist echte Physik-Bewegung
(kein `setPos`-Drift), und während des Dashs überschreibt ohnehin der `action`-Controller.

### 0.2 Arbeitsplan

**Fog Colossus**
1. Geo: `hips` (Transform-Bone, trägt `body`), `chest` (2 Rippen-Cubes, trägt `maw`+`jaw`),
   `jaw` (Mandibel-Platte unter dem Brust-Maul). Legs bleiben an `root` → Hüft-Shift
   verschiebt die Masse, die Füße bleiben stehen.
2. `walk` neu getimt: Kontakt auf den Extremen, Hüft-Shift zur Standbein-Seite,
   Boden-Kontakt-Halte-Frames (linear, nicht catmullrom) an Beinen UND Knöchel-Armen
   (Halb-Gorilla-Gang!), Kopf nickt auf den Aufschlag, Schultern laufen nach.
3. `roar` von 1.5s auf 1.8s: Einatmen (Brustkorb bläht) → Kiefer-Snap → Sustain mit
   Tremor → Ausatem-Kollaps.
4. `chest`/`jaw` in idle/attack/slam/death mitbespielen, damit die neuen Bones nirgends tot sind.
5. Painter: Materialien für `chest` (Rippen) + `jaw` (Mandibel mit Glut-Naht).

**Storm Hound**
1. Geo: `scapula_l`/`scapula_r` (je 1 Platten-Cube), Vorderbeine darunter umgehängt.
2. **NEU `sprint`** (0.5s Galopp, 2 Flugphasen: gestreckte + gesammelte Suspension,
   Lead/Trail-Versatz 0.06s).
3. `walk` auf **Diagonalgang** korrigiert (Vorderbeine waren in Phase) — sonst liest der
   Galopp nicht als eigener Gang.
4. `howl` mit Schulterblatt-Anhebung (Blätter fahren hoch, Beine kompensieren per
   Position, damit die Pfoten stehen bleiben).
5. Scapula in allen übrigen Anims mitbespielt (Windup-Crouch = Blätter über der Wirbelsäule).
6. Java: `ANIM_SPRINT` + `handleBaseState`-Override (Gate auf dem **gesynchten**
   `isAggressive()`-Flag + 8t-Hysterese gegen `LeapAtTargetGoal`-Flackern).
7. Painter: Material + Glowmask für `scapula_*`.

**Koordination:** §5 Colossus-Body-FX-Wunsch-Spec an B2, §6 Lunge-Tick-Tabelle an B2.

---

## 1. Geänderte Dateien (13 — alle im MA6-Besitz)

| Datei | Δ | Was |
|---|---|---|
| `geo/entity/fog_colossus.geo.json` | +24/−2 | **+3 Bones** (`hips`, `chest`, `jaw`), **+3 Cubes**; `body` an `hips` umgehängt |
| `animations/entity/fog_colossus.animation.json` | +418/−83 | `walk` + `roar` neu, `idle`/`attack`/`slam`/`death` um die neuen Bones erweitert |
| `geo/entity/storm_hound.geo.json` | +18/−2 | **+2 Bones** (`scapula_l`/`scapula_r`), **+2 Cubes**; `leg_fl`/`leg_fr` darunter umgehängt |
| `animations/entity/storm_hound.animation.json` | +493/−56 | **neu `sprint`**, `howl` + `walk` überarbeitet, Scapula in allen 8 Anims bespielt |
| `entity/fog/StormHoundEntity.java` | +56/−0 | `ANIM_SPRINT`, `handleBaseState`-Override, `sprintAnim()`, `updateSprintGate()` |
| `scripts/geckolib_gen/mobs/fog_colossus.py` | +59/−0 | Materialien für `chest` (Rippen) + `jaw` (Mandibel), Glowmask-Zuweisungen |
| `scripts/geckolib_gen/mobs/storm_hound.py` | +33/−3 | Material + Glowmask für `scapula_*` |
| `textures/entity/fog_colossus{,_glowmask}.png` | bin | **regeneriert** (nur Painter-Driver, kein Handedit) |
| `textures/entity/storm_hound{,_glowmask}.png` | bin | **regeneriert** (nur Painter-Driver, kein Handedit) |
| `docs/uv/fog_colossus.md` | +8/−1 | Bone/Cube-Zählung, `hips`/`chest`/`jaw`-Zeilen, UV-Packungsnotiz |
| `docs/uv/storm_hound.md` | +9/−5 | Bone/Cube-Zählung, `scapula_*`-Zeilen, Emissive-Notiz |

**`FogColossusEntity.java` wurde NICHT angefasst** — der Koloss brauchte keine Java-Änderung
(`walk`/`roar` hängen an bestehenden Triggern). Der Hund brauchte eine, weil `sprint` ein
**dritter Locomotion-Zustand auf dem `base`-Controller** ist.

---

## 2. Fog Colossus

### 2.1 Neue Bones (Geo: 18 Bones/22 Cubes → **21/25**)

| Bone | Parent | Pivot | Cubes | Zweck |
|---|---|---|---|---|
| `hips` | `root` | `0,12,0` | **0** (Transform-Bone) | trägt die Gewichtsverlagerung |
| `chest` | `body` | `0,20,-6` | 2 (Rippenpaar 5×12×1) | bläht sich vor dem Roar |
| `jaw` | `chest` | `0,18,-6.6` | 1 (Mandibel 12×4×1) | Kiefer unter dem Brust-Maul |

**Der Trick beim Massegesetz:** `hips` sitzt zwischen `root` und `body`, aber `leg_right`/
`leg_left` hängen weiterhin **direkt an `root`**. Dadurch verschiebt ein Hüft-Shift die
gesamte Oberkörpermasse über das Standbein, **ohne die Füße mitzunehmen** — genau das,
was „der Koloss wuchtet" visuell bedeutet. Das ist der Grund, warum `hips` kein Cube hat.

### 2.2 `walk` — Gewichtsverlagerung (1.6 s / 32 t)

58 → **152 Keyframe-Einträge**, 16 → 19 Bones.

| Bone | Keyframes | Was neu ist |
|---|---|---|
| `hips` | **20** (neu) | ±2.10 px Lateral-Shift + −1.7 px Absacken auf den Aufschlag, ±4.5° Roll |
| `root` | 14 → 18 | Heave-Kurve auf 2 Kontakte pro Zyklus umgetimt |
| `leg_right` / `leg_left` | je 3 → **11** | **Boden-Kontakt-Halte-Frames** (linear statt catmullrom auf 0.0/0.12/0.8/0.92) |
| `arm_*` / `forearm_*` | je 3–5 → **9** | Knöchelgang: die Fäuste bekommen dieselben Halte-Frames, kontralateral zu den Beinen |
| `head` | 3 → **11** | nickt mit +4° **in** das Gewicht (auf 0.12 s / 0.92 s), −6° im Durchschwung |
| `body` | 7 → 11 | Torso-Pitch 4.5–8°, Roll gegenläufig zur Hüfte |
| `shoulders` | 3 → 7 | läuft der Hüfte um ~0.2 s **nach** (Massenträgheit) |
| `chest` / `jaw` / `maw` | 9 / 7 / 11 | Atem-/Klapper-Garnitur, damit die neuen Bones nicht tot sind |

**Der Gang.** Zwei Kontakte pro 1.6-s-Zyklus, halb-gorilla (kontralateral):

| Zeit | Tick | Kontakt |
|---|---|---|
| **0.12 s** | 2.4 | **rechter Fuß** + **linke Faust** (Hüfte auf x = −2.1) |
| **0.92 s** | 18.4 | **linker Fuß** + **rechte Faust** (Hüfte auf x = +2.1) |

Gemessen (Vorwärtskinematik auf der ausgelieferten Geo, §4.5): Füße **−0.14 px bis −1.60 px** —
also nie über der Bodenebene. Vorher (HEAD): **+1.28 px** → die Füße schwebten sichtbar.

### 2.3 `roar` — Kiefer + Brustkorb (1.5 s → **1.8 s** / 36 t)

34 → **105 Keyframe-Einträge**, 10 → 19 Bones. Der Beat:

| Zeit | Phase | Was passiert |
|---|---|---|
| 0.00–0.15 s | Antizipation | Kopf senkt sich, Schultern ziehen ein, `chest` zieht sich auf **0.98** zusammen, `jaw` schließt 3° → −2° |
| 0.15–0.62 s | **Einatmen** | `chest` bläht auf **X 1.20 / Y 1.16 / Z 1.22**, `jaw` presst auf −4° |
| **0.55 → 0.62 s** | **Kiefer-Snap** | `jaw` **−4° → +52° in 0.07 s (1.4 t)**; Arme flaren, Kopf reißt hoch |
| 0.62–1.30 s | Sustain | `jaw` hält 46° mit Molang-Tremor **±2°**, `chest` pumpt ±0.02 gegen die Halteposition |
| 1.30–1.80 s | Ausatem | `chest` kollabiert **unter** 1.0 (0.94–0.96), `jaw` fällt 10° → 3°, Körper sackt zusammen |

`jaw` ist mit **12** Keyframes der dichteste Kanal — der Snap braucht die Dichte, sonst
interpoliert catmullrom das Aufreißen weich und der Schlag geht verloren. Der Kollaps
**unter** 1.0 am Ende ist Absicht: ein Brustkorb, der nach dem Brüllen exakt auf 1.0
zurückgeht, hat nicht ausgeatmet.

### 2.4 Nebenanimationen

`idle`, `attack`, `slam`, `death` haben `hips`/`chest`/`jaw` mitbekommen (Atem-Sinus im
Idle, Kiefer-Klappern beim Attack, Brust-Stoß beim Slam-Aufschlag, Kiefer fällt offen im
Death). Kein Bone ist in irgendeiner Animation unbespielt.

---

## 3. Storm Hound

### 3.1 Neue Bones (Geo: 22 Bones/22 Cubes → **24/24**)

| Bone | Parent | Pivot | Cubes | Zweck |
|---|---|---|---|---|
| `scapula_l` | `body` | `3,10,-4` | 1 (Platte 1×3×4) | **neuer Parent von `leg_fl`** |
| `scapula_r` | `body` | `-3,10,-4` | 1 (Platte 1×3×4) | **neuer Parent von `leg_fr`** |

Die Vorderbeine hängen jetzt unter den Schulterblättern statt direkt am `body`. Damit
kann das Blatt über die Rückenlinie steigen, während das Bein darunter kompensiert.

### 3.2 `sprint` — NEU (0.5 s / 10 t, 107 Keyframes, 23 Bones)

Die Ausgangslage war **nicht** „walk × Speed", sondern schlimmer: `handleBaseState` war
gar nicht überschrieben, und `EclipseGeoMonster` ruft nirgends `setAnimationSpeed` auf —
die `walk`-Loop lief also bei **jedem** Tempo mit identischen 0.7 s. Es gab schlicht keinen
zweiten Gang, und auch keine Tempoanpassung des ersten.

`sprint` ist ein echter Galopp, kein schnellerer Trab:

| Zeit | Phase |
|---|---|
| 0.00 s | **gestreckte Suspension** (alle vier Läufe in der Luft, Körper lang) |
| 0.15 s | Vorderhand-Kontakt (Lead-Bein zuerst) |
| 0.30 s | **gesammelte Suspension** (Läufe unter dem Körper eingeklappt) |
| 0.40 s | Hinterhand-Schub |

Messbarer Gangunterschied (Harness §4.3 + Vorwärtskinematik §4.5):

| | walk (Trab) | sprint (Galopp) |
|---|---|---|
| Zykluslänge | 0.7 s | **0.5 s** |
| Diagonalversatz `fl` vs `br` | **0.000 s** (echter Trab) | — |
| Lead/Trail `fl` vs `fr` | 0.000 s | **0.039 s** (Galopp) |
| Lead/Trail `bl` vs `br` | 0.000 s | **0.034 s** |
| `leg_fl` Ausschlag | 78.0° | **96.0°** (Streckphase) |
| `body.y` | flach | **+0.06 … +2.00 px, zwei Gipfel** |

Nebenbefund und mitkorrigiert: der alte `walk` bewegte **beide Vorderbeine in Phase**
(Bound, kein Diagonalgang). Ohne diese Korrektur hätte der Galopp nicht als eigener Gang
gelesen — er wäre nur „dasselbe, schneller" gewesen. `walk` ist jetzt ein sauberer Trab
(Diagonalversatz exakt 0.000 s).

### 3.3 `howl` — Schulterblatt-Anhebung (1.6 s / 32 t)

91 → **141 Keyframe-Einträge**, 15 → 21 Bones.

| Bone | Keyframes | Was |
|---|---|---|
| `scapula_l` / `scapula_r` | je **10** (neu) | Blätter fahren auf **+1.48 px** über die Rückenlinie, −14° Rotation |
| `leg_fl_lower` / `leg_fr_lower` | je **5** (neu) | Gegenversatz −1.0 px, damit die Pfoten trotz Hub stehen bleiben |
| `leg_fl` / `leg_fr` | je 5 → **10** | Kompensation der neuen Parent-Kette |
| `leg_bl` / `leg_br` | je **5** (neu) | Hinterhand stemmt sich in den Hub |

Der Körper hebt sich mit: `body.y` **−1.20 → +0.31 px**, Gipfel bei t = 0.99 s — synchron
mit dem Scapula-Gipfel. Das Heulen hebt also tatsächlich den ganzen Hund, nicht nur den Kopf.

Gemessene Bodenhaftung: Vorderpfoten **−0.38 px bis +0.81 px** (vorher schwebten sie
+1.61 px), Hinterpfoten **−0.55 px bis 0.00 px**.

### 3.4 Java: der Galopp-Gate (`StormHoundEntity`, +56 Zeilen)

`registerControllers` bleibt unangetastet final. `sprint` läuft als **dritter Zustand auf
dem bestehenden `base`-Controller**:

```java
@Override
protected PlayState handleBaseState(AnimationState<?> state) {
    if (!state.isMoving()) {
        return state.setAndContinue(idleAnim());
    }
    return state.setAndContinue(this.sprintHold > 0 ? sprintAnim() : walkAnim());
}
```

Das Gate ist **`isAggressive()`** — von `MeleeAttackGoal` gesetzt und über das Vanilla-
Living-Entity-Flag-Byte gesynct, also clientseitig lesbar, ohne ein eigenes `EntityDataAccessor`
zu erfinden. Der Haken: `MeleeAttackGoal` **löscht das Flag für einzelne Ticks**, sobald
`LeapAtTargetGoal` es verdrängt oder der Pfad neu berechnet wird. Ohne Puffer würde der
Controller mitten im Schritt zwischen Trab und Galopp umschalten und jedes Mal neu über
4 Ticks blenden. Deshalb `SPRINT_HOLD_TICKS = 8`, rein clientseitig getickt
(`updateSprintGate()` läuft nur unter `level().isClientSide` — kein Server-Seam, kein
zusätzlicher Sync).

### 3.5 §7-Falle `isMoving()` — geprüft, greift hier nicht

Verifiziert im dekompilierten `GeoEntityRenderer` (GeckoLib 4.9.2): `isMoving` ist

```
(|deltaMovement.x| + |deltaMovement.z|) / 2 >= getMotionAnimThreshold()   // default 0.015F
&& limbSwingAmount != 0
```

Beide Bedingungen brauchen **echte Physikbewegung**. Die Falle trifft Drifter, die per
`setPos`/gravitationsfreiem `travel()` fahren (Herald, Ferryman, Soul Wisp) — dort bleibt
`limbSwingAmount` 0. Fog Colossus und Storm Hound laufen beide über `PathNavigation` +
vanilla `travel()`, also ist `limbSwingAmount` echt und der Schwellwert wird um
Größenordnungen überschritten. Der Dash des Hundes läuft zwar über `setDeltaMovement`,
aber das ist ebenfalls echte Physik — und währenddessen überschreibt ohnehin der
`action`-Controller.

---

## 4. Validierung

Volles Log: `ma6_validate_and_compile.txt` (Artefakt).

### 4.1 `validate_geo.py` — 4/4 PASS

```
=== GEO  fog_colossus.geo.json   canvas 128x128  21 bones  25 cubes   -> PASS (0 error, 0 warning)
=== GEO  storm_hound.geo.json    canvas  64x64   24 bones  24 cubes   -> PASS (0 error, 0 warning)
=== ANIM fog_colossus.animation.json   6 animation(s)                 -> PASS (0 error, 0 warning)
=== ANIM storm_hound.animation.json    8 animation(s)                 -> PASS (0 error, 0 warning)
validate_geo: 4/4 file(s) passed — all good
```

### 4.2 Painter-Driver — deterministisch

Beide Treiber zweimal laufen lassen, MD5 vor/nach identisch. Keine Textur wurde von Hand
angefasst. Colossus 12 976 Albedo-px / 931 Glowmask-px, Hound 1 602 / 256.

### 4.3 GeckoLib-4.9.2-Laufzeit-Harness (offline, echte Bibliothek)

`validate_geo.py` ist ein eigener Parser — er sagt nicht, ob **GeckoLib** die Dateien
frisst. Deshalb zusätzlich ein Harness gegen den echten `BakedAnimationsAdapter` und den
echten Sampler (`AnimationController.getAnimationPointAtTick` + `EasingType`), damit
catmullrom, Molang-Auswertung und die Grad→Radiant-Konvertierung die der Bibliothek sind:

```
== GeckoLib 4.9.2 BakedAnimationsAdapter: PARSE OK ==   fog_colossus  6 animations
== GeckoLib 4.9.2 BakedAnimationsAdapter: PARSE OK ==   storm_hound   8 animations
  colossus walk   loop seam worst |v(0)-v(T)| = 6.68e-07   (leg_right.rot.x)
  hound    walk   loop seam worst |v(0)-v(T)| = 3.42e-06   (tail_c.rot.y)
  hound    sprint loop seam worst |v(0)-v(T)| = 8.54e-07   (tail_c.rot.y)
  hound    windup -> lunge chain seam = 6.68e-07          (mane_a.rot.x)
```

Dabei ist ein echter Fehler aufgefallen und behoben worden: die Molang-Frequenzen der
`mane_*`/`tail_*`-Kanäle im Hund-`walk` waren 257 — bei 0.7 s Zykluslänge schließt der
Sinus damit **nicht** und die Rute machte an der Loop-Naht einen Sprung. `math.sin` rechnet
in Grad und `query.anim_time` in Sekunden, die schließende Frequenz ist also
**`360 / 0.7 = 514.2857`** (genau eine Periode pro Zyklus). Nahtfehler danach: 3.42e-06.

### 4.4 `compileJava` — BUILD SUCCESSFUL

Mit `--rerun-tasks --no-build-cache` erzwungen (ein `UP-TO-DATE` beweist nichts):

```
BUILD SUCCESSFUL in 8s
2 actionable tasks: 2 executed
100 warnings
```

Alle 100 Warnungen sind die vorbestehenden `EventBusSubscriber.bus()`-Deprecations in
fremden `veilfx/*FxRows.java`-Dateien. **Kein einziges javac-Diagnostikum nennt eine
MA6-Datei** (gegengeprüft per grep über die volle Ausgabe).

### 4.5 Bodenkontakt-Messung (Vorwärtskinematik auf der ausgelieferten Geo)

| Clip | höchster Fuß | tiefster Fuß |
|---|---|---|
| colossus walk (HEAD, vor MA6) | **+1.28 px** | −1.26 px |
| colossus walk (MA6) | **−0.14 px** | −1.60 px |
| hound walk (MA6) | +1.26 px | −0.53 px |
| hound sprint (MA6, neu) | +5.28 px | −0.36 px |
| hound howl Vorderhand (MA6) | **+0.81 px** | −0.38 px |
| hound howl Hinterhand (MA6) | +0.00 px | −0.55 px |

Positiv = schwebt über der Entity-Ebene y=0. Beim Sprint sind +5.28 px **gewollt** — das
ist die Suspension. Beim Walk und beim Howl ist Schweben ein Fehler, und beides steht jetzt.

### 4.6 Polish-Iteration (Schritt 5 des Workflows)

Vier Befunde aus dem ersten Durchlauf, alle nachgezogen:

1. Hund-`walk`-Loop-Naht (Molang-Frequenz 257 → 514.2857), s. §4.3.
2. Colossus-`walk`: Füße schwebten +1.28 px → `root`/`hips`-Kurven umgetimt auf −0.14 px.
3. Hund-`howl`: Vorderpfoten schwebten +1.61 px → Gegenversatz auf `leg_f*_lower`, jetzt +0.81 px.
4. Colossus-`roar`: die Arme verdeckten in der Frontalansicht den Kopf. Nach dem
   Frontal-Render-Test war der ursprüngliche Flare doch der bessere Kompromiss
   (das Brust-Maul muss sichtbar bleiben) — Änderung **zurückgenommen**.

---

## 5. Body-FX-Wunsch-Spec an B2 — Fog Colossus

> **Koordinations-Snippet. MA6 hat hier NICHTS angefasst.** `tools/photon/mobs_fx.py`,
> `fx/*`, `MobPhotonFxRows.java`, `PhotonMobFx.java` und `FxCues.java` sind B2-Besitz.
> Alle Zahlen unten sind aus der ausgelieferten Geo/Anim/Goal gelesen, nicht geschätzt.

Der Koloss ist der einzige Elite ohne eigenes `.fx`. Photon-lose Basis heute
(bleibt unangetastet, `Mode.LAYER`): `GroundSlamGoal` stempelt beim Aufschlag zwei
`CAMPFIRE_COSY_SMOKE`-Ringe (r=3 / 20 Partikel, r=5 / 28 Partikel) plus 4 × `SONIC_BOOM`
auf r=2.2, dazu `S2CShakePayload.shake(0.5f, 12)` im Radius 24.

### 5.1 Bone-Anker (Modell-lokal → Block-Offsets)

Maßstab 16 px = 1 Block. Entity-Hitbox 1.6 × 3.4, `eyeHeight` **2.8** — `PhotonMobFx`-
und `spawnOnEntity`-Offsets sind **vom Auge aus** gerechnet (siehe `HOUND_FEET_OFFSET`).

| Anker | Geo | Blöcke (Entity-lokal) | Offset **vom Auge** |
|---|---|---|---|
| Faust-Aufschlag L/R | `forearm_*` Knöchelpad, Cube y 0–5 px, x-Mitte ±16.5 px | y = 0.00, **x = ±1.03** | `(0, −2.80, 0)` |
| Fuß-Aufschlag L/R | `leg_*` Cube y 0–11 px, x-Mitte ±6.5 px | y = 0.00, **x = ±0.41** | `(0, −2.80, 0)` |
| Schulterjoch (Kragen) | `shoulders` Cube y 30–46 px, x ±13 px, z ±8 px | y = 2.63, r ≈ 0.81 | **`(0, −0.18, 0)`** |
| Korallen-Shelfs | `shelf_*` bis x ±15 px, y bis 50 px | y = 2.88, r ≈ 0.94 | `(0, +0.08, 0)` |

**Achtung, B2-eigene Regel:** laut `B2_MOB_REPORT.md` §0.2 sind `EntityEffectExecutor`-
Offsets **Welt-Achsen**. Der laterale ±1.03-Versatz der beiden Fäuste darf also **nicht**
über den Java-Offset laufen, sondern muss als zwei Emitter-Shapes bei lokal x = ±1.03
**ins Asset gebacken** werden — mit `AUTO_ROTATE_FORWARD`, damit das Paar der Blickrichtung
folgt. Der Kragen ist rotationssymmetrisch und braucht das nicht (`AUTO_ROTATE_NONE`).

### 5.2 Farbwelt

Direkt aus dem Painter-Driver (`scripts/geckolib_gen/mobs/fog_colossus.py`) — damit die
FX zur Textur passen, nicht zu einer anderen Fog-Familie:

| Rolle | Hex | Painter-Konstante | fxlib-Nachbar |
|---|---|---|---|
| Körper-Schiefer | `#3E444D` | `SLATE` | ≈ `STM_SLATE` `#3A3A55` |
| Staubkern (hell) | `#77879B` | `CORAL_LO` | — |
| Staubsaum (kalt-violett) | `#B9B3DC` | `CORAL_HI` | — |
| Spaltenglut (Kern) | `#A9F07E` | `GLOW_GREEN` | — |
| Spaltenglut (heiß) | `#E9FFD8` | `GLOW_PALE` | — |
| Violett-Flecken / Rim | `#9C63E8` / `#6F52B8` | `GLOW_VIOLET` / `RIM_VIOLET` | — |
| Ausklang (tot) | `#241C38` | — | `GLI_DEAD` |

Leitbild: **Staub ist Schiefer, kein Sand** — `CORAL_LO` → `STM_SLATE` → `GLI_DEAD` über
die Lebenszeit, und nur die ersten ~15 % tragen einen `GLOW_GREEN`-Anteil (die Spalten
blitzen im Aufschlag auf und erlöschen sofort). Kein warmer Ton, nirgends.

### 5.3 `colossus_slam_dust` — One-Shot, zwei Trigger-Lanes

**Lane A — der Ground Slam (der eigentliche Auftrag).** `GroundSlamGoal` ist exakt getimt:

| Tick (ab `start()`) | Ereignis |
|---|---|
| t0 | `slam`-Anim getriggert, Navigation gestoppt, `RAVAGER_ROAR` @0.5 |
| t0 .. t0+26 | Telegraph; alle 4 t `WHITE_ASH` auf y+2.6 (Spaltenflirren) |
| **t0+27** | **`IMPACT_TICK`** — Schaden r=6, Ringstempel, Shake |
| t0+28 .. t0+39 | `RECOVER_TICKS` = 12 t Nachschwung |
| danach | Cooldown 200 + rand(0..40) t |

Die `slam`-Animation ist 2.0 s / 40 t und landet den Faustschlag bei **1.35 s = Tick 27** —
das ist deckungsgleich mit `IMPACT_TICK`. Der Burst muss also **auf Tick 27** liegen, nicht
auf t0.

Vorschlag (B2 entscheidet): `FxCues.CUE_COLOSSUS_SLAM` + eine `Row` in `MobPhotonFxRows`
nach dem Muster der Hound-Zeilen. MA6 hängt den Sender in `GroundSlamGoal.slam()`
(MA6-Datei, einzeilig), sobald B2 die Konstante angelegt hat:

```java
// in GroundSlamGoal.slam(), direkt nach den beiden stampDustRing-Aufrufen:
FxPayloads.sendFxEntityEvent(serverLevel, FxCues.CUE_COLOSSUS_SLAM, this.colossus,
        0.0F, 0.0F, 48.0D);
```

```java
// MobPhotonFxRows.onClientSetup — Entity-Lane, FORWARD (das Faustpaar folgt dem Blick).
private static final Vec3 COLOSSUS_GROUND_OFFSET = new Vec3(0.0D, -2.8D, 0.0D);

PhotonFxRegistry.registerRow(new PhotonFxRegistry.Row(
        FxCues.CUE_COLOSSUS_SLAM,
        fx("colossus_slam_dust"),
        null,                            // photon-lose Basis = die Campfire-Ringe
        FxBudget.Channel.BURST,
        PhotonFxRegistry.Mode.LAYER,
        false,                           // 200-240t Cooldown -> kein Overlap
        (photonFx, pos, entity, a, b) -> entity != null
                ? PhotonBridge.spawnOnEntity(photonFx, entity,
                        PhotonBridge.AUTO_ROTATE_FORWARD, COLOSSUS_GROUND_OFFSET)
                : PhotonBridge.spawn(photonFx, pos)));
```

Asset-Wünsche:

| Emitter | Shape | Timing | Bewegung |
|---|---|---|---|
| `fist_kick` ×2 | `circle(radius=0.55)` bei lokal **x = ±1.03**, y = 0 | Burst 0 t, 18–24 Partikel je Seite, Lifetime 14–20 t | `start_speed` 0.35–0.6, `velocity_over_lifetime.linear.y` +0.05, harter `SEG_DECAY_TAIL` |
| `shock_ring` | `circle(radius=1.2, thickness=0.15)`, flach | Burst 0 t, Lifetime 22 t | radial nach außen auf **r = 6.0** in 22 t (= 5.45 b/s) — der Ring muss die Schadenszone lesen |
| `slate_grit` | `cone` nach oben, `radius=0.9` | Burst 0 t, 10–14 Partikel, Lifetime 26–34 t | Schwerkraft an, `random_gradient` (zwei Kolosse dürfen nicht identisch stauben) |

Der `shock_ring`-Radius ist **kein Design-Wunsch, sondern Gameplay**: `RADIUS = 6.0`,
`INNER_RADIUS = 3.0`, und außerhalb r=3 ist der Slam springbar. Wenn der Ring die 6 Blöcke
nicht sauber erreicht, lügt die Telegrafierung.

**Lane B — die Stampf-Frames im Gehen.** Der Koloss ist ein Knöchelgänger; jeder Schritt
sollte einen kleinen Puff werfen. Die Beats stehen fest (§2.2): **0.12 s** und **0.92 s**
im 1.6-s-Zyklus, also alle **16 Ticks** abwechselnd rechts/links.

Ein nicht offensichtlicher Punkt, den B2 kennen muss: der `base`-Controller läuft
**ohne `setAnimationSpeed`** (`EclipseGeoMonster` ist FROZEN). Die Walk-Loop hat damit
eine **feste 32-Tick-Periode, unabhängig vom Lauftempo**. Eine `distanceRate`-Kopplung
wäre hier also genau falsch — sie würde bei langsamer Bewegung zwischen den Fußaufschlägen
stauben. Richtig ist ein **Zeit-Trigger auf der 16-Tick-Kadenz**, angeklinkt an die
steigende Flanke von „bewegt sich" (dieselbe Bedingung, die auch den Controller auf `walk`
schaltet — `(|dx|+|dz|)/2 >= 0.015 && limbSwingAmount != 0`, §3.5). Ein client-lokaler
Watcher nach dem Muster von `GazeTetherWatcher` löst das ohne eine einzige Zeile
Wire-Traffic; ein `PhotonMobFx.LoopRow` mit einem 16-t-Puffer im Asset tut es auch.
MA6 liefert auf Zuruf einen `walkCyclePhase()`-Getter auf `FogColossusEntity`, falls B2
die Phase exakt statt geflankt haben will — sag Bescheid, das ist MA6-Gebiet.

### 5.4 `Nebelkragen-Loop` — Dauerschleier um die Schultern

Kein Cue, kein Paket: das gehört in die **Loop-Tier-Tabelle** von `PhotonMobFx`, genau wie
`revenant_fog_ribbons`.

```java
// PhotonMobFx.ROWS — Schulterjoch-Anker (Auge 2.8 -> Joch-Oberhälfte 2.63), nearest-3.
new LoopRow(FogColossusEntity.class, fx("colossus_fog_collar"),
        PhotonBridge.AUTO_ROTATE_NONE, new Vec3(0.0D, -0.18D, 0.0D),
        24.0D, 3, ALWAYS, null, null),
```

| Parameter | Wunsch | Begründung |
|---|---|---|
| `simulation_space` | **`"Local"`** | der Kragen muss am Mob kleben, nicht in der Welt stehenbleiben |
| `inheritVelocity` | **−0.35** | Local + negativ = Schleppe; der Kragen reißt nach, wenn er losstapft (dieselbe Mechanik wie `revenant_fog_ribbons` mit −0.4, aber der Koloss ist träger) |
| `shape` | `cylinder(radius=1.05, thickness=0.35)`, `scale=(1.0, 0.45, 1.0)` | Joch-Halbbreite 0.81 + Shelfs 0.94 → 1.05 liegt knapp außerhalb der Silhouette |
| `rate` | `constant(0.5)`, `max_particles` **48** | Loop-Tier-Gesetz: kleine Budgets, eigene `cull`-Box |
| `distance_rate` | **`constant(0.30)`** | beim Stapfen quillt mehr Nebel nach |
| `start_lifetime` | `random_between(40, 60)` | träge — der Koloss ist keine Nebelschwade |
| `color_over_lifetime` | `CORAL_LO #77879B` → `STM_SLATE` → `GLI_DEAD` | §5.2 |
| `random_gradient` | **ja** | zwei Kolosse in einem Sturm dürfen nicht denselben Kragen tragen |
| `cull_box` | ≈ `((-2.5,-0.5,-2.5),(2.5,2.0,2.5))` | relativ zum Anker, nicht zum Entity-Ursprung |
| `colorBySpeed` | **nein** | der Kragen darf beim Laufen nicht aufhellen — er ist Nebel, keine Reibung |

Der `roar` blendet den Kragen idealerweise kurz auf: der Brustkorb bläht sich 0.15–0.62 s,
der Kiefer schnappt bei 0.62 s (§2.3). Ein Puls auf `rate` bei Anim-Tick 12 wäre die Kür —
aber das braucht wieder einen Cue, und `roar` feuert nur einmal pro Mob (erstes
`setTarget`). Aus MA6-Sicht: **verzichtbar**, die Prio liegt auf Slam-Staub und Kragen.

---

## 6. Lunge-Timing-Tabelle an B2 — Storm Hound

> Für das `inheritVelocity`-/`distanceRate`-Tuning von `hound_dash_trail`
> (`B2_MOB_REPORT.md` §1, Zeile `dash_grit`). Quelle: `ChargedLungeGoal.java`, gelesen,
> nicht geschätzt. t0 = der Server-Tick, in dem `Goal.start()` läuft.

### 6.1 Die Phasen

| Phase | Ticks (relativ t0) | Dauer | Geschwindigkeit | Was passiert |
|---|---|---|---|---|
| **WINDUP** | `t0` … `t0+19` | **20 t** / 1.00 s | **0** (verwurzelt: `setDeltaMovement(0, y, 0)`) | `charge_windup` getriggert, `CUE_HOUND_WINDUP` gesendet (Radius 48), `WARDEN_SONIC_CHARGE` @1.9, alle 2 t `ELECTRIC_SPARK` |
| **RELEASE** | Ende `t0+19` | 1 t | 0 | Dash-Linie **rastet ein** (auf die Ist-Position des Ziels), `lunge` getriggert, **`CUE_HOUND_DASH` gesendet**, `TRIDENT_RIPTIDE_1` @1.3 |
| **DASH** | `t0+20` … `t0+33` | **≤ 14 t** / 0.70 s | **0.9 b/t = 18.0 b/s** | gerade Linie, Yaw hart auf die Linie gesetzt, 2 × `ELECTRIC_SPARK`/t |
| **IMPACT** | frühestens `t0+20` | — | — | erster Treffer in `boundingBox.inflate(0.4)`: 6 dmg + Slowness IV 20 t, `attack`-Biss, Velocity ×0.2, **Phase sofort IDLE** |
| **STAGGER** (nur bei Fehlschlag) | `t0+34` … `t0+73` | **40 t** / 2.00 s | 0 | `WOLF_WHINE` @0.8, alle 6 t `SMOKE` + `ELECTRIC_SPARK` |
| **COOLDOWN** | ab `stop()` | **160 t** / 8.00 s | — | `readyAtTick = tickCount + 160` |

### 6.2 Die Zahlen, die B2 wirklich braucht

| Größe | Wert | Bedeutung für `hound_dash_trail` |
|---|---|---|
| Dash-Geschwindigkeit | **0.9 b/t** | exakt und konstant — vom Goal gesetzt, keine Beschleunigungsrampe |
| Dash-Geschwindigkeit in `colorBySpeed`-Einheiten | **18.0 b/s** | `colorBySpeed` bekommt `\|realVelocity\|·20` = Blöcke/Sekunde. Die Windup-Range 0.05–0.45 b/s ist für den **stehenden** Hund; für den Dash ist `speedRange` ≈ **a = 2.0, b = 18.0** die passende Spanne |
| Maximale Dash-Länge | **14 t × 0.9 = 12.6 Blöcke** | `distance_rate = 0.35` → **36 Grit-Partikel** über die volle Linie. Das ist die Obergrenze fürs Budget |
| Trigger-Range | 6–14 Blöcke | **bei 14 Blöcken kann der Dash das Ziel nicht erreichen** (12.6 < 14) — der Hund verfehlt konstruktionsbedingt. Effektives Trefferband ≈ ≤ 13.7 Blöcke (12.6 + `inflate(0.4)` + beide Hitbox-Halbbreiten) |
| Trefferzeit aus Minimaldistanz (6 Blöcke) | **≈ `t0+25`** (6 Dash-Ticks) | Kontakt greift ≈ 1.15 Blöcke früher als die Distanz (`inflate(0.4)` + beide Hitbox-Halbbreiten), das Ziel bewegt sich noch. Heißt: **das Asset muss schon nach 6 Ticks gut aussehen**, nicht erst nach 14 |
| Ribbon-Lebensdauer | **≤ 14 t nach `CUE_HOUND_DASH`** | siehe §6.3 |
| Wiederholrate | ≥ 160 t | `allowMulti=false` ist korrekt; kein Overlap möglich |

### 6.3 Animationsabgleich — der eine Stolperstein

| Animation | Länge | Deckt ab |
|---|---|---|
| `charge_windup` | 1.0 s = **20 t** | **exakt** die Windup-Phase |
| `lunge` | 1.1 s = **22 t** | Dash (14 t) **+ 8 t Überhang** |

Die `lunge`-Animation ist bewusst länger als der Dash: Strecksprung bei 0.12 s, gehaltene
Streckung bis **0.70 s = Tick 14** (= exakt das Dash-Ende), Landung 0.70–0.90 s, Ausklang
bis 1.10 s. Die letzten 8 Ticks fallen also in den **Stagger**.

**Konsequenz für B2:** das Dash-Ribbon darf **nicht** an die Animationslänge gekoppelt
werden. Es muss bei **Tick 14** nach `CUE_HOUND_DASH` auslaufen, sonst zieht der Hund noch
eine Spur, während er längst gestrauchelt dasteht. Und weil der Dash bei einem Treffer
**früher** endet (frühestens Tick 1), ist ein weicher `SEG_DECAY_TAIL` auf
`sizeOverLifetime` robuster als ein harter Cut — es gibt keinen „Dash-Ende"-Cue.

### 6.4 Bone-Anker Storm Hound (16 px = 1 Block, `eyeHeight` 0.8, Hitbox 0.9 × 1.1)

| Anker | Geo-Pivot | Blöcke (Entity-lokal) | Offset vom Auge |
|---|---|---|---|
| Körpermitte (heutiges `HOUND_BODY_OFFSET`) | `body` `0,10,2` | y = 0.63 | `(0, −0.40, 0)` ✔ passt |
| Pfoten (heutiges `HOUND_FEET_OFFSET`) | Cube-Unterkante y = 0 | y = 0.00 | `(0, −0.90, 0)` ✔ passt |
| **`scapula_l` / `scapula_r`** (neu) | `±3,10,−4` | x = ±0.19, y = 0.63, z = −0.25 | `(0, −0.18, 0)` |
| `glow_horn` (Ladeanzeige) | `0,14,−10` | y = 0.88, z = −0.63 | `(0, +0.08, 0)` |

Die beiden Scapula-Bones sind **neu** und im Glowmask emissiv angebunden — im
`charge_windup` fahren sie auf −14° über die Rückenlinie und tremorieren dort. Falls B2
den Windup-Spiralkollaps noch enger an den Mob binden will, ist das der interessanteste
neue Anker.

---

## 7. Test-Rezept

```
# --- Fog Colossus -------------------------------------------------------
# 1) Grundstellung: idle-Atmung, Brustkorb + Kiefer leben (chest/jaw Sinus)
/summon eclipse:fog_colossus ~ ~ ~5 {NoAI:1b,CustomName:'"MA6 idle"'}

# 2) walk mit Gewichtsverlagerung — laufen lassen und von VORNE ansehen:
#    Hüfte kippt sichtbar auf die Standbeinseite, Kopf nickt mit, Füße kleben.
/summon eclipse:fog_colossus ~ ~ ~12 {CustomName:'"MA6 walk"',PersistenceRequired:1b}
#    ... dann wegrennen, damit er die 12 Blöcke wirklich läuft.

# 3) roar — feuert einmalig auf das ERSTE setTarget. Also: in Sichtweite gehen.
#    Achte auf die Reihenfolge: Einatmen (Brust bläht) -> Kiefer-Snap bei 0.62 s.
/summon eclipse:fog_colossus ~ ~ ~8 {CustomName:'"MA6 roar"'}

# 4) slam — GroundSlamGoal braucht ein Ziel <= 5 Blöcke und tickCount >= 80.
#    Impact liegt auf Tick 27 der 40-Tick-Animation.
/summon eclipse:fog_colossus ~ ~ ~3 {CustomName:'"MA6 slam"'}

# 5) death (50 t, aufrecht gehaltener Kollaps, Kiefer fällt offen)
/kill @e[type=eclipse:fog_colossus,limit=1,sort=nearest]

# --- Storm Hound --------------------------------------------------------
# 6) walk = Trab. Ohne Ziel bleibt isAggressive() false -> NIE Galopp.
/summon eclipse:storm_hound ~ ~ ~10 {NoAI:0b,CustomName:'"MA6 trot"'}

# 7) sprint = Galopp. Braucht isAggressive() (MeleeAttackGoal mit lebendem Ziel).
#    Der Umschaltpunkt ist der Moment, in dem er dich anvisiert — von der SEITE ansehen:
#    zwei Suspensionsphasen, 0.5 s Zyklus statt 0.7 s.
/summon eclipse:storm_hound ~ ~ ~16 {CustomName:'"MA6 gallop"'}
#    Gegenprobe auf die 8-Tick-Hysterese: wegrennen, bis er das Ziel verliert —
#    der Galopp darf NICHT im Schritt flackern, sondern erst nach ~8 t in den Trab fallen.

# 8) charge_windup + lunge (die Tabelle aus §6): 6-14 Blöcke Abstand + Sichtlinie.
#    20 t Hocke, dann 14 t Dash. Bei 14 Blöcken verfehlt er konstruktionsbedingt
#    -> gute Gelegenheit, den 40-t-Stagger zu sehen.
/summon eclipse:storm_hound ~ ~ ~13 {CustomName:'"MA6 lunge miss"'}
/summon eclipse:storm_hound ~ ~ ~7  {CustomName:'"MA6 lunge hit"'}

# 9) howl — Schulterblätter. Von der SEITE ansehen: die Blätter steigen über die
#    Rückenlinie, der ganze Körper hebt mit, die Vorderpfoten bleiben stehen.
/summon eclipse:storm_hound ~ ~ ~6 {CustomName:'"MA6 howl"'}
#    (howl feuert einmalig, wenn der Hund ein Ziel bekommt — vgl. FogTyrant-Pack-Howl.)

# 10) death (30 t Seitenkollaps + Spine-Flicker)
/kill @e[type=eclipse:storm_hound,limit=1,sort=nearest]
```

Wenn die Registrare noch nicht verdrahtet sind, loggt der Mod das beim Start
(`FogEliteEntities registrar not wired yet` bzw. `FogEntities registrar not wired yet`) —
dann greifen die `/summon`-IDs nicht, und das liegt nicht an MA6.

---

## 8. Rest-Notizen (ehrlich)

**Die Chain-Nähte, die das Harness anzeigt und die MA6 NICHT verursacht hat:**

```
colossus  roar -> idle   worst |end-start| = 5.00 deg  (arm_right.rot.z)
colossus  slam -> idle   worst |end-start| = 5.00 deg  (arm_right.rot.z)
hound     howl -> idle   worst |end-start| = 18.0 deg  (head.rot.y)
```

Beide stammen aus dem **Ruhe-Offset der `idle`-Animation**, nicht aus den neuen Clips:
`idle` fährt `arm_right.rot.z = "5 + sin(...)·2"` und `head.rot.y` mit ±18°-Sweep. Wenn ein
`action`-One-Shot endet, gibt er die Bones zurück an den `base`-Controller, der die ganze
Zeit weitergelaufen ist — und der steht dann an einer beliebigen Phase. Belege: (a) die
`slam`-Naht ist mit 5.00° identisch, obwohl MA6 die Slam-Arme nicht angefasst hat; (b) der
`action`-Controller hat in `EclipseGeoMonster` `transitionLength = 0` — das ist Teil der
**FROZEN** Controller-Definition. Sauber beheben ließe sich das nur mit einem
Transition-Wert auf dem `action`-Controller, und das ist eine Änderung an einer
FROZEN-Datei. Beim Hund kommt dazu, dass `head` **head-tracked** ist, der Anim-Wert also
ohnehin nur Garnitur auf der Blickrichtung ist. Kein Handlungsbedarf aus MA6-Sicht,
aber es sollte jemand wissen.

**Nicht gemacht (bewusst):**

- Keine FX-Datei angefasst. §5/§6 sind Specs, keine Implementierung.
- Keine Textur von Hand editiert — beide PNG-Paare kommen deterministisch aus dem Painter.
- `registerControllers` unverändert final; `sprint` ist ein dritter **Zustand**, kein
  dritter Controller.
- `FogColossusEntity.java` unverändert.
- Nicht committet (Integrator committet zentral).
