# MB6 — Pale-Paar (Pale Sentinel + Fog Revenant)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-B, Zeile **MB6**.
**Datei-Besitz (exklusiv):** `entity/pale/*` + `entity/fog/FogRevenantEntity.java`,
`client/entity/*`-Renderer der beiden, `geo/animations/textures pale_sentinel*` +
`fog_revenant*`, `scripts/geckolib_gen/mobs/{pale_sentinel,fog_revenant}.py`,
`docs/uv/{pale_sentinel,fog_revenant}.md`, dieser Report.

**NICHT angefasst (Leitplanken):** `EclipseGeoMob`/`EclipseGeoMonster`/`EclipseGeoAnimations`/
`EclipseGeoRenderer` (FROZEN), `validate_geo.py`/`paint_lib.py` (FROZEN),
`tools/photon/**`, `assets/eclipse/fx/**`, `PhotonMobFx.java` (**B2-Besitz** — nur
gelesen; der Orbit-Pairing-Wunsch steht als Spec in §5), `entity/fog/StormHoundEntity.java`
(MA6), Lang-Dateien (**keine neuen Keys nötig** — kein Langdrop). `registerControllers`
bleibt final (`base` + `action`, kein dritter Controller).

---

## 0. Plan (vor der Implementierung geschrieben)

### 0.1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Datei | Ist-Stand |
|---|---|
| `geo/entity/pale_sentinel.geo.json` | 20 Bones / 22 Cubes, Canvas 64²; 4 Petal-Platten (`petal_shoulder_*`, `petal_chest`, `petal_back`) vorhanden, aber **keine** Tip-Anker für B2 |
| `animations/entity/pale_sentinel.animation.json` | 6 Anims; `freeze` = statischer Halte-Loop, `handleBaseState` schaltet **hart** von walk/idle auf `freeze` (nur 4t-Controller-Blend = der bemängelte Loop-Schnitt); `walk` = reine Molang-Sinus (Frequenz 514 auf 0.7 s → **Loop-Naht**, 514·0.7 = 359.8 ≠ n·360) |
| `PaleSentinelEntity` | `freeze` über gesynchtes `DATA_FROZEN`, base-Controller-Blend 4t, `bloom`-Trigger beim Tauen, Death 35t scripted |
| `geo/entity/fog_revenant.geo.json` | 22 Bones / 22 Cubes; 4 `tatter_*`-Saumstreifen als **1-Segment**-Anhänger (3×4×1 bzw. 1×4×2) — zu steif für „Ziehen“ |
| `animations/entity/fog_revenant.animation.json` | `idle` 4.0 s / **20 kf**; `walk` Molang mit Frequenz 90 auf 2.0 s (90·2 = 180 ≠ n·360 → **halbe Periode, Naht**); tatters in attack/cast_blind/death tot |
| `PhotonMobFx.java` (B2, gelesen) | `sentinel_petal_orbit`-LoopRow ankert **statisch** bei eye−0.85 (Statuen-Zentrum), Gate `isFrozen()` — kein Bone-Pairing, weil keine Anker-Bones existierten |
| `paint_lib.py` (FROZEN, gelesen) | Cube-lose Bones werden ignoriert; bei Material-Patterns gewinnt die **spätere** Deklaration |
| GeckoLib 4.9.2 (Bytecode via `javap`) | Anim-Rotationen sind **additiv** auf die Geo-Rest-Rotation (`initialSnapshot + lerp`) — deshalb dürfen freeze_in/bloom-Keys 1:1 gegen die `freeze`-Werte geprüft werden |

### 0.2 Arbeitsplan

**Pale Sentinel**
1. Geo: 4 cube-lose `petal_tip_*`-Locator an den freien Sepal-Enden (B2-Orbit-Anker).
2. **`freeze_in` (Kernaufgabe):** 0.3 s / non-loop, gedämpfter Ring-Down nach Masse
   (schwere Bones sterben zuerst, Papier-Petals zuletzt), Endpose **exakt** = `freeze`.
3. Java: `handleBaseState` frozen-Zweig auf `thenPlay(freeze_in).thenLoop(freeze)`
   umstellen (gecachte `RawAnimation`), Blend auf 3t schärfen.
4. `walk` von Molang (Naht!) auf keyframed Stelz-Stakkato umschreiben; idle-Frequenzen
   loop-sauber; attack/death/bloom mit Sekundärmotion (Petals/Tendrils/Antlers) auf M-A.
5. Painter: unverändert (Locator sind cube-los) — Determinismus-Nachweis reicht.

**Fog Revenant**
1. Geo: jede `tatter_*` in **2-Segment-Kette** splitten (`tatter_*` y2–4 + Kind
   `tatter_*_tip` y0–2, Gelenkebene y2), 4 neue UV-Slots.
2. `idle` 20 → **125 kf**: catmullrom-Wanderwellen Wurzel→Tip (Tip ~0.2 s Phasenverzug),
   Atem-Torso, Hood-Sway, Arm/Claw-Drift.
3. `walk`-Molang-Frequenzen loop-sauber (90 → 180 usw.), Schlepp-Saum keyframed;
   attack/cast_blind/death: Tip-Peitschen, Hood-Snap, Growth-Jiggle, Wisp-Flare.
4. Painter: `tatter_root` (Weave+Mist, KEIN Rag-Cut) vs. `tatter_tip` (stärkster Mist,
   Alpha-Cut ≤ 1 Reihe), Tip-Pattern NACH dem Root-Pattern deklarieren.

**Koordination:** §5 Petal-Orbit-Pairing-Spec an B2, §6 Tatter-Ketten-Notiz für die
`revenant_fog_ribbons`.

---

## 1. Geänderte Dateien (9 — alle im MB6-Besitz)

| Datei | Δ | Was |
|---|---|---|
| `geo/entity/pale_sentinel.geo.json` | +20/−0 | **+4 cube-lose Locator** `petal_tip_{right,left,chest,back}` an den Petal-Platten |
| `animations/entity/pale_sentinel.animation.json` | +589/−46 | **neu `freeze_in`** (0.3 s/112 kf); `walk` Molang→keyframed (124 kf); idle-Frequenzen loop-sauber; attack/death/bloom-Polish |
| `entity/pale/PaleSentinelEntity.java` | +38/−4 | `ANIM_FREEZE_IN`, gecachte `freeze_in→freeze`-Sequenz in `handleBaseState`, `baseTransitionTicks()` 4→3 |
| `geo/entity/fog_revenant.geo.json` | +36/−4 | **+4 Bones/+4 Cubes**: tatter-Split in 2-Segment-Ketten; Bugfix `tatter_d` (Cube-`pivot`/`rotation`-Rest + falscher origin) |
| `animations/entity/fog_revenant.animation.json` | +324/−11 | `idle` 20→**125 kf** Saum-Wellen; walk-Naht-Fix + Schlepp-Saum; attack/cast_blind/death um die Tips erweitert |
| `scripts/geckolib_gen/mobs/fog_revenant.py` | +30/−11 | `tatter()` → `tatter_root()`/`tatter_tip()`, Material-Split root/tip |
| `textures/entity/fog_revenant{,_glowmask}.png` | bin | **regeneriert** (nur Painter-Driver, kein Handedit) |
| `docs/uv/pale_sentinel.md` | +17/−7 | Tabelle auf 24 Bones/22 Cubes (Petals + Locator waren nie dokumentiert), Locator-Absatz, Petal-Farben im Art-Brief |
| `docs/uv/fog_revenant.md` | +22/−4 | Tabelle auf 26 Bones/26 Cubes (Forearms + Tatters fehlten komplett), Tatter-Ketten-Absatz |

`pale_sentinel{,_glowmask}.png` wurden zur Determinismus-Probe neu erzeugt und sind
**byte-identisch zu HEAD** (kein Cube geändert → kein Diff). `pale_sentinel.py`
unverändert (Locator sind cube-los, der Painter ignoriert sie).

---

## 2. Pale Sentinel

### 2.1 `freeze_in` — der Erstarrungs-Übergang (Kernaufgabe, 0.3 s / 6 t / 112 kf / 19 Bones)

Vorher: `handleBaseState` schnitt bei `isFrozen()` hart auf den statischen `freeze`-Loop
(nur der 4t-Controller-Blend kaschierte den Schnitt — Bewegungsenergie verschwand
„zwischen zwei Frames“). Jetzt spielt der frozen-Zweig eine **gecachte Sequenz**
`thenPlay(freeze_in).thenLoop(freeze)`:

- **Gedämpfte Rest-Schwingung statt Lerp:** jeder Bone pendelt 1–3× mit fallender
  Amplitude ÜBER die Zielpose hinaus und in sie zurück (catmullrom). Beispiel `head`:
  `(-13,8,10) → (-5,3,5) → (-10,6.4,8.4) → (-7,4.4,6.4) → … → (-8,5,7)` — Überschwinger
  ≈ 60 % → 30 % → 0.
- **Masse-Staffelung:** `body`/`pelvis`/Beine stehen nach 0.10 s; `torso`/`head`/Arme
  nach 0.20 s; Papier-Anhänge (`petal_*`, `tendril_*`, `antler_*`, `hand_*`) zittern bis
  0.28–0.30 s nach — schwere Bones sterben zuerst, genau wie bei einem echten Arret.
- **Endpose-Garantie:** die letzten Keys (t=0.3) sind **wertgleich** mit dem statischen
  `freeze`-Loop, maschinell geprüft (§4.4) — der Übergang in den Loop ist unsichtbar,
  ab da Totenstille.
- **Java-Seite** (`PaleSentinelEntity`, +38/−4): `ANIM_FREEZE_IN`-Konstante, lazy
  gecachte `RawAnimation` (Semantik von `setAndContinue`: nur eine **neue** Instanz
  restartet — die Sequenz spielt pro Freeze genau einmal an, der Loop hält danach;
  beim Tauen wechselt der Controller auf idle/walk, der nächste Freeze startet den
  Ring-Down frisch). `baseTransitionTicks()` 4→3, damit der Einstieg in den Ring-Down
  innerhalb von 3 t greift und die 6 t Rest-Schwingung nicht vom Blend aufgefressen
  werden.

### 2.2 Petal-Locator-Bones (Geo: 20 Bones/22 Cubes → **24/22**)

4 **cube-lose** Kinder der Petal-Platten, Pivot jeweils am freien Sepal-Ende (= der
Punkt, der beim Flattern/Bloom am weitesten ausschlägt):

| Locator | Parent | Pivot (Modell-px) |
|---|---|---|
| `petal_tip_right` | `petal_shoulder_right` (Roll −24°) | (−8, 25.5, 0) |
| `petal_tip_left` | `petal_shoulder_left` (Roll +24°) | (8, 25.5, 0) |
| `petal_tip_chest` | `petal_chest` (Pitch −12°) | (0, 24, −2.9) |
| `petal_tip_back` | `petal_back` (Pitch +10°) | (0, 23.5, 2.9) |

Cube-los = kein UV, kein Paint, kein Render-Overhead; validate_geo listet sie als
normale Bones, der Painter ignoriert sie (verifiziert: Texturen byte-identisch). Die
Locator erben die volle Petal-FK — Spec für B2 in §5.

### 2.3 `walk` — Stelz-Stakkato (0.7 s / 14 t, Molang → 124 kf / 19 Bones)

Der alte Molang-Walk (Frequenz 514 auf 0.7 s) hatte eine **Loop-Naht** (514·0.7 = 359.8°
≠ n·360°) und lief als gleichmäßiger Sinus — für einen Stelzen-Baum zu weich. Neu
keyframed: ruckartige Wurzel-Schritte mit Kontakt auf den Extremen, Body-Dip auf jedem
Aufschlag, Torso-Gegenrotation, Kopf-Snaps (2-Frame-Umschlag statt Sinus), nachlaufende
Arme/Hände, Tendril-Kaskade mit Phasenverzug, Petal-Flattern + Antler-Jiggle auf den
Aufschlägen. Erste/letzte Keys wertgleich (§4.4).

### 2.4 Nebenanimationen

- **`idle`** (5.0 s): Frequenzen auf n·72 gezogen (72·5 = 360 → nahtlos), Torso-Scan
  verlangsamt, `pelvis` mitbespielt — Petal-Phasen 90° versetzt (Kreis-Atmung, füttert
  optisch den B2-Orbit).
- **`attack`** (0.6 s): Bein-Bracing, Body-Lurch, Tendril/Petal-Sekundärmotion,
  Antler-Mitschwung — der Hieb kommt jetzt aus dem Stand, nicht aus dem Arm allein.
- **`death`** (1.75 s / hold): Mehr-Beat-Crumble — Tremor → Bein-Knick-Stagger →
  Petal-Klammer → Tendril-Zerfall, Endframe = Rinden-Haufen-Pose.
- **`bloom`** (0.7 s): startet jetzt **exakt** auf der `freeze`-Pose (alle 19 Bones,
  maschinell geprüft) — vorher sprangen Arme/Hände/Tendrils beim Tauen; im 2. Pass
  auch `leg_right`/`leg_left` ergänzt (§4.5).

---

## 3. Fog Revenant

### 3.1 Tatter-Ketten (Geo: 22 Bones/22 Cubes → **26/26**)

Jeder Saumstreifen ist jetzt eine 2-Segment-FK-Kette: `tatter_*` (Wurzel, Cube y2–4,
Pivot y4 am `skirt_low`-Saum) trägt `tatter_*_tip` (Cube y0–2, **Pivot exakt auf der
Gelenkebene y2** — FK-geprüft in §4.4). Neue Tip-UV-Slots (28,18) (28,21) (53,32)
(53,36) — kollisionsfrei (validate_geo 0 Warnings). **Beifang-Bugfix:** der alte
`tatter_d`-Cube trug ein cube-lokales `pivot`/`rotation`-Paar (Kopierrest) und einen
um 1 px versetzten origin — bereinigt, Bone-Rotation ist jetzt die einzige Quelle.

### 3.2 `idle` — Saum-Wellen (4.0 s, 20 → **125 kf** / 25 Bones, Auftrag: 50+)

Wanderwellen durch die Ketten: Tip-Keys laufen den Wurzel-Keys ~0.2 s hinterher
(`tatter_a` Wurzel `9° @0.0 → −6° @1.0`, Tip `14° @0.2 → −10° @1.2`), alle 4 Ketten
mit eigenem Phasen-Offset und eigener Wellenrichtung (a/b pitchen, c/d rollen) —
der Saum „zieht“, statt zu pendeln. Dazu Atem-Torso + Hood-Nachschwingen, Kopf-Scan,
Arm/Forearm/Claw-Drift, Growth-Jiggle, `wisps`-Y-Molang (Frequenz 90 = n·360/4 s,
nahtlos). Durchgängig catmullrom, erste/letzte Keys wertgleich (§4.4).

### 3.3 Nebenanimationen

- **`walk`** (2.0 s): Molang-Nahtfix (Torso/Kopf/Skirt-Frequenzen 90 → 180 = n·360/2 s),
  Schlepp-Saum keyframed (Tips hängen im Fahrtwind nach), `growth` mitbespielt —
  vorher sprang der halbe Oberkörper an der Loop-Naht.
- **`attack`** (0.6 s): Tatter-Tip-Peitsche auf den Klauen-Swipe, Hood-Snap,
  Growth-Jiggle, Wisp-Flare.
- **`cast_blind`** (1.5 s): Tips flaren beim Channel auf und peitschen beim Release,
  Hood bläht.
- **`death`** (2.0 s / hold): Tips reißen nach OBEN aus (der Sturm frisst die Robe
  zuerst), Hood/Growth-Scale-Kollaps, Drift über `root` bleibt unangetastet.

### 3.4 Painter-Split (`fog_revenant.py`, +30/−11)

`tatter()` → `_tatter_col()` + `tatter_root()` (Weave + Mist-Anstieg, **kein** Rag-Cut —
die Risskante gehört ans freie Ende) + `tatter_tip()` (stärkster Mist-Wash, Alpha-Cut
auf **max. 1 Reihe** gekappt, damit vom 2-px-Segment etwas übrig bleibt).
`set_material("tatter_*_tip", …)` steht NACH `set_material("tatter_*", …)` — in
`paint_lib` gewinnt die spätere Deklaration, sonst hätten die Tips Root-Material.
Texturen regeneriert, Determinismus in §4.2.

---

## 4. Validierung

### 4.1 `validate_geo.py` — 2×2/2 PASS (wörtlich)

```
=== GEO  src/main/resources/assets/eclipse/geo/entity/pale_sentinel.geo.json
    identifier geometry.pale_sentinel  canvas 64x64  24 bones  22 cubes
  -> PASS (0 error(s), 0 warning(s))
=== ANIM src/main/resources/assets/eclipse/animations/entity/pale_sentinel.animation.json
    'animation.pale_sentinel.idle': loop=True length=5.0 bones=17 keyframes=17 last_key=0.0s
    'animation.pale_sentinel.walk': loop=True length=0.7 bones=19 keyframes=124 last_key=0.7s
    'animation.pale_sentinel.freeze_in': loop=False length=0.3 bones=19 keyframes=112 last_key=0.3s
    'animation.pale_sentinel.freeze': loop=True length=2.0 bones=19 keyframes=20 last_key=0.0s
    'animation.pale_sentinel.attack': loop=False length=0.6 bones=19 keyframes=86 last_key=0.6s
    'animation.pale_sentinel.death': loop='hold_on_last_frame' length=1.75 bones=19 keyframes=101 last_key=1.75s
    'animation.pale_sentinel.bloom': loop=False length=0.7 bones=19 keyframes=73 last_key=0.7s
  -> PASS (0 error(s), 0 warning(s))
validate_geo: 2/2 file(s) passed — all good

=== GEO  src/main/resources/assets/eclipse/geo/entity/fog_revenant.geo.json
    identifier geometry.fog_revenant  canvas 64x64  26 bones  26 cubes
  -> PASS (0 error(s), 0 warning(s))
=== ANIM src/main/resources/assets/eclipse/animations/entity/fog_revenant.animation.json
    'animation.fog_revenant.idle': loop=True length=4.0 bones=25 keyframes=125 last_key=4.0s
    'animation.fog_revenant.walk': loop=True length=2.0 bones=25 keyframes=26 last_key=0.0s
    'animation.fog_revenant.attack': loop=False length=0.6 bones=20 keyframes=82 last_key=0.6s
    'animation.fog_revenant.cast_blind': loop=False length=1.5 bones=20 keyframes=102 last_key=1.5s
    'animation.fog_revenant.death': loop='hold_on_last_frame' length=2.0 bones=20 keyframes=96 last_key=2.0s
  -> PASS (0 error(s), 0 warning(s))
validate_geo: 2/2 file(s) passed — all good
```

### 4.2 Painter-Driver — deterministisch (2 Läufe, md5 identisch, wörtlich)

```
Lauf 1 == Lauf 2:
6dcef89aa5285dc7cb36ccd96f281ecb  textures/entity/pale_sentinel.png
9e285d9cccaabae218f89f284f9a2dff  textures/entity/pale_sentinel_glowmask.png
b9c661da0d079241a85dc4eb4e30733e  textures/entity/fog_revenant.png
193bc7d525f62830f9e88fc0d1b1162a  textures/entity/fog_revenant_glowmask.png
```

Sentinel-PNGs zusätzlich **byte-identisch zu HEAD** (`git diff` leer — Locator sind
cube-los, der Painter sieht sie nicht → Beweis, dass die Geo-Änderung paint-neutral ist).

### 4.3 `compileJava` — BUILD SUCCESSFUL (wörtlich)

```
> Task :createMinecraftArtifacts UP-TO-DATE
> Task :compileJava UP-TO-DATE
BUILD SUCCESSFUL in 785ms
2 actionable tasks: 2 up-to-date
```

(UP-TO-DATE = Gradle hat den aktuellen Stand von `PaleSentinelEntity.java` bereits
erfolgreich kompiliert und input-gehasht — Quellstand == Kompilat.)

### 4.4 Offline-Naht/FK-Checks (Wegwerf-Skript, nicht eingecheckt)

Maschinell geprüft, Ergebnis nach dem 2. Pass:

```
ALL CHECKS PASSED (pose match, loop seams, molang frequencies)
```

- **Pose-Match:** letzte `freeze_in`-Keys und erste `bloom`-Keys == statische
  `freeze`-Werte, pro Bone/Kanal (Toleranz 1e-6); zusätzlich: kein Bone, den `freeze`
  hält, den freeze_in/bloom NICHT bedienen.
- **Loop-Nähte:** in allen `loop=true`-Anims erste == letzte Keyframe-Werte, erste
  Keys auf t=0.
- **Molang-Frequenzen:** jedes `anim_time * f` in Loops erfüllt `f·len ≡ 0 (mod 360)`.
- **FK:** `tatter_*_tip`-Pivots exakt auf der y2-Gelenkebene der Wurzel-Cubes;
  `petal_tip_*`-Pivots exakt auf den freien Cube-Ecken der Sepals.

### 4.5 Polish-Iteration (Selbstkritik-Pass)

Der Pose-Match-Check aus §4.4 fand im 2. Pass zwei echte Löcher: `freeze` hält
`leg_right`/`leg_left` auf (−4°/+7°) (asymmetrischer Statuen-Stand), aber `bloom`
bediente die Beine nicht → Bein-Snap beim Tauen. Fix: Beide Beine in `bloom` ergänzt
(Start = Freeze-Stand, federnder Überschwinger bei 0.35 s, neutral bei 0.6 s). Danach
Re-Validierung: §4.1–§4.4 alle grün.

---

## 5. B2-Spec — Petal-Orbit-Pairing (Pale Sentinel)

**Ist-Stand B2** (`PhotonMobFx.ROWS`, nur gelesen): `sentinel_petal_orbit` ankert
statisch bei `eye − 0.85` (Statuen-Zentrum), Gate `isFrozen()`. Die Orbit-Partikel
kreisen damit um einen toten Punkt — die Petal-Platten selbst flattern (idle/walk),
klammern (freeze) und schnappen auf (bloom), ohne dass die FX folgen.

**Angebot (jetzt im Geo):** 4 cube-lose Locator mit voller Petal-FK — Bone-Namen und
Pivots in §2.2. Bind-Pose-Anker in Blöcken (16 px = 1 b; Hitbox 0.8×2.4, `eyeHeight`
2.1) für einen statischen Fallback:

| Locator | Block-Offset (x, y, z) ab Fußpunkt | eye-relativ |
|---|---|---|
| `petal_tip_right` | (−0.61, 1.72, 0.00) | eye − 0.38 |
| `petal_tip_left` | (+0.61, 1.72, 0.00) | eye − 0.38 |
| `petal_tip_chest` | (0.00, 1.51, −0.26) | eye − 0.59 |
| `petal_tip_back` | (0.00, 1.48, +0.25) | eye − 0.62 |

**Aber:** statische Offsets bleiben zweite Wahl. Die Tips wandern mit den Anims
deutlich — im `freeze` klammern die Platten an den Körper (Anim-Add `+18/−18` Roll bzw.
`+10/−8` Pitch gegen die Rest-Rotation ≈ Platten flach am Torso, Tips ziehen ~0.15–0.2 b
ein), `bloom` fächert in 0.25 s wieder auf, `walk` flattert ±6°. **Wunsch:** die 4
Orbit-Emitter je Locator-Bone pairen (GeckoLib-Bone-World-Transform pro Frame), damit
(a) der Orbit im Freeze sichtbar auf die geklammerte Panzer-Silhouette kollabiert und
(b) der `bloom`-Aufschnapper die Partikel mitreißt. Yaw beachten: `body` dreht mit
`yBodyRot` — Modell-x/z rotieren, nicht welt-fix addieren (die eye-relativen y-Werte
sind yaw-invariant). Gate kann `isFrozen()` bleiben; das Rising-Edge-`sentinel_alert`
ist von den Locatorn unberührt.

---

## 6. Notiz an B2 — `revenant_fog_ribbons` vs. Tatter-Ketten (Fog Revenant)

Die Robe-Säume sind jetzt 2-Segment-Ketten (§3.1); die `idle`-Wanderwellen laufen
Wurzel→Tip mit ~0.2 s Verzug und 4 individuellen Phasen-Offsets (a: 0.0 s, c: +0.5 s,
b: +1.0 s, d: +1.5 s auf dem 4.0-s-Loop; a/b pitchen, c/d rollen gegenphasig). Wenn die Ribbon-Streamer an den Saum fassen
sollen: die visuell „gezogenen“ Punkte sind die **Tip-Unterkanten** (Modell-y 0, Block
y ≈ 0.25 unter Berücksichtigung des 4-px-Hovers via `body`) an x/z der vier
Kettenwurzeln (±2/∓3.5 vorn/hinten, ±4.5/±5 seitlich, in px). Kein Locator nötig —
die Tips tragen eigene Cubes (`tatter_*_tip` ist direkt pairbar).

---

## 7. Test-Rezept

```
# --- Pale Sentinel ------------------------------------------------------
/summon eclipse:pale_sentinel
# 1) freeze_in (Kernaufgabe): dem Sentinel den Rücken zudrehen, warten bis er
#    stakst, dann RUCKARTIG hinsehen. Erwartung: KEIN harter Pose-Schnitt mehr,
#    sondern 0.3 s abklingendes Nachzittern — Beine stehen sofort, Kopf/Arme
#    pendeln 1-2x nach, Petals/Tendrils/Antlers flattern als letzte aus. Danach
#    Totenstille (freeze-Loop ist statisch, kein Loop-Pumpen).
# 2) Gegenprobe Tauen: wegsehen (5t Grace) -> bloom. Erwartung: Petals schnappen
#    auf, Arme/Beine lösen sich FEDERND aus dem Statuen-Stand (kein Bein-Snap —
#    der §4.5-Fix).
# 3) walk von der SEITE: Stelz-Stakkato mit Body-Dip auf jedem Aufschlag,
#    Kopf-Snaps, Tendril-Kaskade — und an der Loop-Naht kein Ruck (Molang-Naht
#    ist raus).
# 4) attack/death wie gehabt triggern (Melee-Reichweite / töten).

# --- Fog Revenant -------------------------------------------------------
/summon eclipse:fog_revenant
# 5) idle von NAH ansehen: die 4 Saumstreifen knicken zweigliedrig und die Welle
#    LÄUFT von der Wurzel in den Tip (nicht mehr Brett-Pendeln); alle 4 Ketten
#    asynchron. 4-s-Loop ohne Naht-Ruck.
# 6) walk: Säume schleppen nach hinten, Tips hängen im Fahrtwind nach; an der
#    2-s-Naht springt NICHTS mehr (vorher: halbe-Periode-Bug an Torso/Kopf/Skirt).
# 7) attack (Melee) / cast_blind (Distanz): Tip-Peitsche bzw. Flare-und-Peitsche.
# 8) death: Tips reißen nach oben aus, Hood/Growth kollabieren.
# 9) Texturen: Rag-Kante sitzt NUR noch am Tip-Segment, Wurzel-Segment ist
#    geschlossen gewebt (Painter-Split §3.4).
```

---

## 8. Rest-Notizen (ehrlich)

- **Gefundene Fremd-/Alt-Bugs (gefixt, weil im MB6-Besitz):** (1) Sentinel-`walk`-
  Molang-Naht (514·0.7 ≠ n·360); (2) Revenant-`walk`-Molang-Naht (90·2 = halbe
  Periode); (3) `tatter_d`-Cube mit Kopierrest-`pivot`/`rotation` + 1 px origin-Versatz;
  (4) `bloom` ohne Bein-Deckung gegen den `freeze`-Stand (§4.5); (5) beide
  `docs/uv/*.md` waren stark veraltet (Sentinel-Petals, Revenant-Forearms und -Tatters
  fehlten komplett in den Tabellen) — neu geschrieben.
- **`freeze_in` restartet pro Freeze-Flanke korrekt**, weil der Thaw-Pfad den
  base-Controller erst auf idle/walk zurückschaltet (neue `RawAnimation`-Instanz beim
  nächsten Freeze). Sollte je ein Pfad entstehen, der frozen→frozen ohne
  Zwischenzustand toggelt, hält `setAndContinue` die alte Sequenz — dann müsste ein
  `stop()`-Kick her. Heute existiert so ein Pfad nicht.
- **Offen für B2:** das eigentliche Orbit-Pairing (§5) und optional das
  Ribbon-Greifen an den Tatter-Tips (§6) — beides B2-Besitz (`PhotonMobFx`/
  `tools/photon`), von mir nur als Spec geliefert.
- **Kein Langdrop:** keine neuen Entities/Items/Sounds → keine Lang-Keys;
  `docs/plans_v3/langdrop/MB6-PALE.json` wurde bewusst NICHT angelegt.
- **Nicht gemacht (bewusst):** kein dritter Anim-Controller für freeze_in (FROZEN-Base
  verbietet es — die Chain-Lösung auf dem base-Controller braucht ihn auch nicht);
  keine Handkorrekturen an den PNGs (Painter-only-Regel).
