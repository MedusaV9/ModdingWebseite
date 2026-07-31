# MB3 — Dungeon-Familie (Eclipse Cultist + Shadow Bolt)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-B, Zeile **MB3** — *„Cultist: Robe 1→4 Cubes
+ Ärmel-Flare im cast, Hood-`glow_`-Bone; Bolt: Molang-Dauerspin + Taumel Richtung Ziel;
Body-FX-Wunsch (Hood-Glut-Loop) an B2"*.

**Datei-Besitz (exklusiv):** `entity/dungeon/{EclipseCultistEntity,RangedShadowBoltGoal,
ShadowBoltProjectile,DungeonEntities}`, `client/entity/dungeon/{EclipseCultist,ShadowBolt}Renderer`,
geo/animations/textures `eclipse_cultist*` + `shadow_bolt*`,
`scripts/geckolib_gen/mobs/{eclipse_cultist,shadow_bolt}.py`,
`docs/uv/{eclipse_cultist,shadow_bolt}.md`, dieser Report.

**NICHT angefasst (Leitplanken):** `EclipseGeoMonster`/`EclipseGeoRenderer`/
`EclipseGeoAnimations` (FROZEN — nur gelesen), `validate_geo.py`/`paint_lib.py` (FROZEN),
`tools/photon/mobs_fx.py` + `veilfx/PhotonMobFx.java` + `assets/eclipse/fx/**` (**B2-Besitz**
— hier nur gelesen, der Wunsch steht als Spec in §6), `en_us.json`/`de_de.json`
(→ `docs/plans_v3/langdrop/MB3-DUNGEON.json`). `registerControllers` bleibt final
(`base` + `action`, keine dritten Controller). Kein `git add`/`commit`/`push`.

---

## 0. Plan (vor der Implementierung geschrieben)

### 0.1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Datei | Ist-Stand vor MB3 |
|---|---|
| `geo/entity/eclipse_cultist.geo.json` | 13 Bones / 11 Cubes, Canvas 64². Robe = **ein** Cube (8×10×5). Kein Cuff-Bone, kein `glow_`-Bone an der Hood, **kein** `neck` |
| `animations/entity/eclipse_cultist.animation.json` | 5 Anims: idle(4.0 s/12 kf/12 Bones), walk(1.0 s/12 kf), cast(1.2 s/64 kf), attack(0.5 s/26 kf/**6** Bones), death(1.5 s/44 kf) |
| `geo/entity/shadow_bolt.geo.json` | 3 Bones / 4 Cubes (`root`→`glow_core`,`spikes`), Canvas 32². Keine Nase, kein Aim-Bone |
| `animations/entity/shadow_bolt.animation.json` | 1 Anim `idle`, 4 kf, 3 Bones: `root.rotation.y = query.anim_time*360` — ein **Karussell um die Hochachse**, keine Flugrichtung, kein Taumeln |
| `EclipseCultistEntity` | `cast`/`attack` Triggerables, Death 30 t scripted, **kein** gesyncter Zustand (kein Pendant zu `DeckhandEntity#isHostile()`) |
| `RangedShadowBoltGoal` | Band 8–14, `CAST_INTERVAL` 60 t, `CAST_WINDUP_TICKS` 20 → Release auf Tick **21** nach dem Trigger, 3-Bolt-Fächer ±12° |
| `ShadowBoltProjectile` | `AbstractHurtingProjectile`, `steerTowardsTarget()` je Tick, Lifetime 60 t |
| `EclipseCultistRenderer` | `EclipseGeoRenderer`, `turnsHead = true`, `withGlowmask()`, `withUprightDeath()` |
| `ShadowBoltRenderer` | **`GeoEntityRenderer` direkt** (Projektil ist kein `LivingEntity`), fullbright 15, `AutoGlowingGeoLayer` |
| `PhotonMobFx` (B2) | `LoopRow(EntityClass, fxId, autoRotate, offset **relativ zur EYE-Position**, attachRange, maxAttached, attachWhen, edgeFx, edgeOffset)`. Vorbild `DeckhandEntity#isHostile()` als Edge-Prädikat |

### 0.2 Die zwei Fallen, die den ganzen Entwurf bestimmt haben

**Falle A — `head`-Rotationen X/Y sind tote Kanäle.**
`DefaultedEntityGeoModel#setCustomAnimations` läuft **nach** `tickAnimation` und macht ein
absolutes `headBone.setRotX/setRotY`. Bei `turnsHead = true` (und das ist der Cultist) wird
also jedes `head.rotation.x/y` aus dem Sheet verworfen — nur `.z` überlebt.
→ **Ein `neck`-Bone zwischen `torso` und `head`** trägt jetzt sämtliches Kopfnicken/-drehen;
auf `head` steht nur noch die Z-Neige (Kopf-Loll). Harness §3 misst das Sheet-für-Sheet.

**Falle B — das Projektil bekommt seine Flugrichtung NICHT vom Renderer.**
`GeoEntityRenderer` zwingt eine Nicht-`LivingEntity` auf Yaw 0 (danach die feste
180°-Modellraum-Drehung) und ignoriert Pitch **komplett**. Ein Shadow Bolt kann sich also
nicht „von selbst" in die Flugrichtung legen.
→ Die Zielrichtung erreicht das Modell **nur** über Molang: `query.body_x_rotation` /
`query.body_y_rotation` liefern den interpolierten Entity-Pitch/-Yaw und sind (per
Bytecode-Prüfung an `MolangQueries`) für **jede** Entity registriert, nicht nur für
Lebewesen. Das ist die Antwort auf „prüfe wie die Entity ihre Zielrichtung ins Client-Model
bekommt". Harness §1 reproduziert 10/10 Flugrichtungen auf 0.00° genau.

### 0.3 Arbeitsplan

```
Cultist   Geo:  Robe 1 -> 4 Cubes (robe_lower/mid/hem + robe_train), 2 Bell-Cuffs,
                neck-Bone, glow_hood
          Anim: alle 5 Sheets auf M-A (mehr Keys, catmullrom, Nachschwing,
                phasenversetzte Details), Ärmel-Flare im cast auf den Release
Bolt      Geo:  root -> aim -> spin/wake, Nasen-Speer (glow_lance + glow_tip),
                zwei Wake-Shards
          Anim: aim = Molang-Flugrichtung, spin = Dauerrolle + Nutation,
                wake = nachlaufendes Bank/Roll
Painter   beide Driver erweitern (Determinismus 2x md5)
Beweis    validate_geo 4/4, GeckoLib-Laufzeit-Harness, Offline-Rasterizer, compileJava
```

---

## 1. Geänderte Dateien (14 — alle im MB3-Besitz)

```
 docs/uv/eclipse_cultist.md                                        |  55 +-
 docs/uv/shadow_bolt.md                                            |  51 +-
 scripts/geckolib_gen/mobs/eclipse_cultist.py                      | 149 ++++-
 scripts/geckolib_gen/mobs/shadow_bolt.py                          | 106 ++-
 .../entity/dungeon/EclipseCultistEntity.java                      |  30 +
 .../entity/dungeon/RangedShadowBoltGoal.java                      |   5 +
 .../animations/entity/eclipse_cultist.animation.json              | 741 ++++++++++++---
 .../animations/entity/shadow_bolt.animation.json                  |  47 +-
 .../geo/entity/eclipse_cultist.geo.json                           |  63 +-
 .../geo/entity/shadow_bolt.geo.json                               |  53 +-
 .../textures/entity/eclipse_cultist.png            (Painter)      | Bin
 .../textures/entity/eclipse_cultist_glowmask.png   (Painter)      | Bin
 .../textures/entity/shadow_bolt.png                (Painter)      | Bin
 .../textures/entity/shadow_bolt_glowmask.png       (Painter)      | Bin
```

Dazu neu: `docs/plans_v3/langdrop/MB3-DUNGEON.json` (keine NEUEN Keys — zwei
Bestiarium-Zeilen, die den Text wieder an die Silhouette angleichen) und dieser Report.

---

## 2. Eclipse Cultist

### 2.1 Geo: 13 Bones / 11 Cubes → **20 / 17**

```
body
├─ robe_lower  7×4×5   y  6…10          Taille (war: EIN Cube 8×10×5)
│  ├─ robe_mid  8×3×6  y  3…6           +0.5 px/Seite
│  │  └─ robe_hem 9×3×7 y 0.6…3.6       +0.5 px/Seite, trägt jetzt den Sigil-Saum
│  └─ robe_train 6×8×1 z 3.2…4.2        Rückenschleppe, Sigil-Naht auf der Wirbelsäule
├─ torso
│  ├─ neck  (cubelos)                   NEU — trägt Kopf-Pitch/-Yaw (Falle A)
│  │  └─ head → hood → glow_hood 5.5×5.5×0   NEU — Glutring in der Kapuzenöffnung
│  ├─ arm_right → cuff_right 4×5×4      NEU — Glockenärmel
│  └─ arm_left  → cuff_left  4×5×4      NEU
└─ runes → glow_rune_a/b/c              unverändert
```

Die Kette ist **verschachtelt, nicht nebeneinander**: `robe_hem` hängt an `robe_mid` hängt
an `robe_lower`. Eine Rotation an der Taille zieht die beiden Unterteile mit und die drei
Kurven addieren sich zu einem Stoff-Nachlauf — genau das, was ein einzelner Rock-Cube
nicht kann. Die Tiefen steppen mit (5 → 6 → 7), damit **keine zwei Frontflächen koplanar**
werden; sonst z-fightet die Kette.

`robe_train` hängt bewusst an `robe_lower` und nicht an `robe_hem`: die Schleppe soll aus
der Hüfte fallen, nicht dem Saum hinterherwedeln.

### 2.2 `cast` (1.2 s/64 kf/12 Bones → **1.3 s / 192 kf / 19 Bones**) — der Ärmel-Flare

Getaktet auf die echte Server-Uhr: `RangedShadowBoltGoal.beginCast()` feuert `ANIM_CAST`
und setzt `windupTicks = 20`; der Fächer verlässt den Cultist auf Tick **21 = 1.05 s**.
Das Sheet setzt seinen Höhepunkt exakt dort und hat danach noch 0.25 s Nachschwing.

Cuff-Roll (Harness §3, gemessen an der ausgelieferten Geo):

```
 t (s)   cuff_r.z   cuff_l.z robe_low.x robe_mid.x robe_hem.x    train.x
  0.00      -2.00       2.00      -0.00      -0.00      -0.00      -0.00
  0.22      -3.32       3.32       1.97       1.75       1.51       1.99
  0.43      -9.36       9.36       0.23       0.87       1.38       2.66
  0.65     -17.85      17.85      -1.56      -1.37      -1.00      -1.17
  0.87     -28.70      28.70      -3.12      -3.83      -3.74      -4.96
  0.98     -36.31      36.31      -4.34      -3.94      -3.31      -6.14   <- Release
  1.08      -8.33       8.33       4.48       0.17       1.43       2.22
  1.19      -1.78       1.78       3.83       5.89       5.25      13.70   <- Nachschlag
  1.30      -2.00       2.00      -0.00       1.00       2.00       4.00
```

Zwei Dinge stecken da drin, die man einzeln nicht sieht:

- Die Glocken gehen **beschleunigt** auf (2 → 3 → 9 → 18 → 29 → 36°), nicht linear. Der
  Aufzug liest sich dadurch als Sog und nicht als Kurbel.
- Der Rückschlag ist **phasenversetzt durch die Kette**: bei 1.08 s schwingt schon die
  Taille nach vorn (+4.48°), während Saum und Schleppe noch hinterherhängen; bei 1.19 s
  hat sich das umgedreht (Taille 3.83°, Saum 5.25°, Schleppe **13.70°**). Der Stoff läuft
  dem Körper hinterher, statt mit ihm zu springen.

Dazu skalieren die Cuffs im Peak auf 1.28 in X/Z (und nur 1.07 in Y) — die Glocke bläht
sich auf, statt zu wachsen. `glow_rune_*` steigen zeitversetzt (a bei 0.55/0.85/1.05,
b +0.03 s, c +0.06 s), damit die drei Seiten nicht im Gleichschritt hochfahren.

### 2.3 `glow_hood` — warum es ein **Ring** und keine Glutleiste ist

Erster Wurf war eine 3×1-Glutleiste auf Gesichtshöhe. Im Rasterizer (§5.3) war sofort
klar: unter zwei Augen gelesen ist eine waagerechte Leiste ein **Mund**. Das widerspricht
dem Design-Sheet §2.3 direkt — *„a deep hood whose opening shows only shadow and two violet
eye embers"*.

Jetzt: eine flache 5.5×5.5-Quad-Scheibe, 0.1 px **vor** der Kapuzenöffnung aufgehängt, von
der der Painter **nur den 1-px-Rand** malt; die Mitte bleibt Alpha 0. Der Ring folgt der
Maulöffnung, die Augen lesen mittendurch. Der Verlauf ist unten-schwer (Brauen `#7A55B7`
α 87 → Kinn `#D6BBFF` α 210) — Glut, die sich im Boden der Kapuze sammelt, nicht ein
gleichmäßig leuchtendes Visier.

Zwei Details, die nicht offensichtlich sind und in `docs/uv/eclipse_cultist.md` stehen:

- **Die Mitte MUSS Alpha 0 sein.** Der Cultist rendert mit dem Cutout-Default
  (`entityCutoutNoCull`), der Alpha *testet*. Ein halbtransparenter Kern würde voll
  deckend rendern und die Augen zuhängen.
- **5.5 px, nicht 6.** Bei 6 px läge die Ring-Außenkante exakt auf den Seitenwänden der
  Kapuze (beide bei |x| = 3) — bei streifendem Blick z-fightet das zu einem hellen
  1-px-Splitter entlang der Silhouette. Im Rückansichts-Render war der Splitter deutlich
  sichtbar; mit 5.5 px verdeckt die Kapuze ihn sauber (Rück-Frame in
  `mb3_eclipse_cultist_all_anims_360.mp4`).

### 2.4 idle / walk / attack / death

| Sheet | vorher | jetzt | was neu drin ist |
|---|---|---|---|
| `idle` | 4.0 s / 12 kf / 12 Bones | 4.0 s / **24 kf / 19 Bones** | reines Molang (nahtlos per Konstruktion): Atmung auf `torso`/`neck`, Robenkette mit 3 Phasenversätzen, Cuffs gegenphasig zu den Armen, Ring-Puls auf der 4-s-Periode des Sheets |
| `walk` | 1.0 s / 12 kf | 1.0 s / **23 kf / 19 Bones** | Robenkette schwingt der Hüfte 40°/70°/100° Phase hinterher, Schleppe pendelt am längsten nach, Ring pulst im 0.25-s-Schritttakt |
| `attack` | 0.5 s / 26 kf / **6 Bones** | 0.5 s / **106 kf / 19 Bones** | war das dünnste Sheet: Messerhand, Torso, Kopf. Jetzt schwingen Robenkette, Cuffs, Runen und Ring mit — das Panikmesser reißt den ganzen Stoff mit |
| `death` | 1.5 s / 44 kf | 1.5 s / **108 kf / 19 Bones** | Kniefall mit Nachsacken; Ring schwillt bei 0.25 s auf 1.30 und erlischt bis 1.5 s auf 0.01 (Kapuze leert sich), Runen fallen zeitversetzt |

Loop-Nähte idle+walk: **worst |v(0) − v(T)| = 0.0000** über alle Kanäle (Harness §3).

### 2.5 Java: ein gesynctes Flag (+30/+5 Zeilen)

`EclipseCultistEntity` bekommt `DATA_CASTING` (`EntityDataSerializers.BOOLEAN`,
transient) plus `isCasting()`/`setCasting()`; `RangedShadowBoltGoal` setzt es in
`beginCast()`, löscht es auf dem Release-Tick, in `stop()` und `die()` räumt auf.

Das ist kein Gameplay-Change — es ist **der Haken, den B2 braucht** (§6.3). Ohne ihn ist
GeckoLibs Trigger-Kanal aus einem Render-Thread-Prädikat nicht abfragbar und die
`edgeWhen`-Lane von `PhotonMobFx` bliebe leer. Muster 1:1 wie
`DeckhandEntity#isHostile()`, das in `PhotonMobFx` schon genau so benutzt wird.

---

## 3. Shadow Bolt

### 3.1 Geo: 3 Bones / 4 Cubes → **10 / 8**

```
root
└─ aim                                  Flugrichtung (Molang, siehe 3.2)
   ├─ spin                              Dauerrolle + Nutation
   │  ├─ glow_core   3×3×3              unverändert
   │  ├─ spikes      3 Schäfte          unverändert
   │  ├─ glow_lance  2×2×2  z −4…−2     NEU — Kragen der Nase
   │  └─ glow_tip    1×1×2  z −5.5…−3.5 NEU — die Spitze
   └─ wake                              nachlaufender Schweif
      ├─ glow_wake_a 1×1×2  x +1.5      NEU
      └─ glow_wake_b 1×1×2  x −1.5      NEU
```

Die Dreiteilung ist der Kern: `aim` **zeigt**, `spin` **dreht**, `wake` **hinkt hinterher**.
Läge der Spin auf demselben Bone wie das Zielen, würde die Rolle die Flugrichtung
mitdrehen; läge der Schweif unter `spin`, würde er mitrotieren statt nachzuziehen.

### 3.2 Anim: Zielen, Dauerspin, Taumeln

```json
"aim":  { "rotation": [ "query.body_x_rotation + math.clamp(query.vertical_speed * -4, -10, 10)",
                        "query.body_y_rotation + math.clamp(query.yaw_speed * 2.5, -20, 20)", 0 ] },
"spin": { "rotation": [ "math.sin(query.anim_time * 360) * 6 + math.clamp(query.yaw_speed * 1.2, -7, 7)",
                        "math.sin(query.anim_time * 360 + 90) * 6",
                        "query.anim_time * 720" ] },
"wake": { "rotation": [ "math.clamp(query.vertical_speed * -7, -16, 16)",
                        "math.clamp(query.yaw_speed * -4, -28, 28)",
                        "math.clamp(query.yaw_speed * -3.5, -24, 24) + math.sin(query.anim_time * 360) * 6" ] }
```

- **Zielen** (Falle B): `aim` liest Pitch/Yaw direkt. Die Rotationsreihenfolge in
  `RenderUtil.prepMatrixForBone` ist Z→Y→X, mit Z = 0 ergibt das `Ry·Rx` — exakt die
  Minecraft-Konvention (erst Gieren, dann Nicken um die mitgedrehte Achse). Deshalb
  reproduziert das Modell den Kurs ohne Korrekturterm; Harness §1: **10/10 auf 0.00°**.
- **Dauerspin:** `query.anim_time * 720` = zwei volle Umdrehungen pro Sekunde. 720 ist ein
  Vielfaches von 360, also ist die Naht am Loop-Ende exakt 0 (gemessen: 0.0000) —
  unabhängig davon, ob GeckoLib `anim_time` beim Loop zurücksetzt oder monoton weiterzählt.
  Dieselbe Regel gilt für jeden Kanal im Sheet.
- **Taumeln:** die Nutation auf `spin.x/y` sind zwei um 90° versetzte Sinusse — ein
  präzedierender Kreisel, nicht ein Wackeln in einer Ebene. Der Vorhalt aus
  `query.yaw_speed` liegt bewusst **klein** (Gain 1.2, Clamp ±7) auf dem Körper und
  **groß** (Gain −4, Clamp ±28) auf dem Schweif: `yaw_speed` ist clientseitig spitz, weil
  die Rotation nur alle 2 Ticks über den Tracker kommt. Auf dem Schweif liest sich das als
  Peitschen, auf dem Körper wäre es Jitter.

Der Vorwärts-Lean nach `query.vertical_speed` ist die zweite Hälfte von „Taumeln Richtung
Ziel": der Bolt homt über `steerTowardsTarget()`, also fällt/steigt er ständig, und die
Nase legt sich in genau diese Änderung hinein.

### 3.3 Warum der Verlauf längs und nicht radial gemalt ist

`spin` dreht die Nase 720°/s. Wäre eine Fläche heller als ihre Nachbarin **um die
Rollachse herum**, würde der Bolt einmal pro Umdrehung stroboskopieren. Der Driver malt
deshalb alles über einen einzigen Längsverlauf (`_z_t`), und die Fläche→Achse-Zuordnung ist
**gemessen, nicht angenommen**: Harness §4 kippt jedes gebackene `GeoQuad` aus und
protokolliert, wohin `+fx`/`+fy` je Fläche zeigen (`+fx → −Z` auf `east`, `+fx → +Z` auf
`west`, `+fy → −Z` auf `up`/`down`, `north` = die −Z-Kappe). Genau dieselbe Tabelle sagt
auch, dass `+fy` auf den Seitenflächen **nach unten** läuft — die Grundlage für „Saumband
auf `fy == fh−2`" und „Cuff-Lippe auf `fy == fh−1`" beim Cultist.

---

## 4. Selbstkritik — was die Polish-Pässe gefunden haben

Der Rasterizer (§5.3) hat mehr gefunden als der Validator, und zwar durchweg Dinge, die in
JSON-Zahlen völlig unauffällig aussehen:

| # | Befund | Fix |
|---|---|---|
| 1 | Die 3×1-Glutleiste unter den Augen las sich als **Mund** — Widerspruch zum Design-Sheet („only shadow and two violet eye embers") | `glow_hood` als Randring der Kapuzenöffnung neu gebaut, Mitte transparent (§2.3) |
| 2 | Ring mit 6 px Breite = koplanar mit den Kapuzen-Seitenwänden → **1-px-Z-Fight-Splitter** entlang der Silhouette in der Rückansicht | auf 5.5 px eingerückt; Splitter im Re-Render verschwunden |
| 3 | Der Nasen-Speer war 6 px lang und fast weiß → der Bolt las sich als **Rakete/weißer Stab**, nicht als Schattengeschoss. Additiver Glow-Layer verstärkt das noch | Speer auf 2+2 px gekürzt (2.5 px über die Spikes hinaus), Palette gekühlt (`#F7F1FF`→`#E4D5FF`, Weiß erst ab t > 0.7 statt 0.55), Glow-Alpha 255 → 215 |
| 4 | Nach der Kürzung landete das Hitzeband (`ring == 1`) **auf der heißen Spitze** statt dahinter und dämpfte sie | Band auf Flächen > 2 Texel begrenzt |
| 5 | Saum 10 px breit bei 7→8→**10**-Stufung = Hochzeitstorte mit ungleichmäßiger Terrasse | Saum auf 9 px, Stufung jetzt gleichmäßig +0.5 px/Seite wie die Tiefen |
| 6 | Cast-Ringskala 1.9 war für die 3-px-Leiste getunt; auf dem 5.5-px-Ring wäre das ein 10.5-px-**Heiligenschein** um den Kopf gewesen | auf 1.32 Peak retuned, alle 5 Sheets nachgezogen |
| 7 | Robenkette klippte im `cast` mit −0.0899 Blöcken durch den Boden | Saum um 0.6 px angehoben + Rückschlag-Amplituden halbiert → jetzt **−0.0465**, unter einem Texel (§5.2) |
| 8 | Kopf-Pitch/-Yaw im Sheet waren **wirkungslos** (Falle A) | `neck`-Bone; Harness prüft jetzt die *Spitzenwerte* je Achse, nicht bloß „gibt es Keys" |
| 9 | B2 hätte kein clientseitiges Prädikat für den Cast-Burst gehabt | gesynctes `isCasting()` (§2.5) |

Der Harness selbst hatte dabei zwei eigene Fehler, die Ergebnisse verfälscht hätten:
`toYawPitch` rechnete Yaw mit `atan2(d.z, d.x) + 90` statt `atan2(-d.x, d.z)` (konstanter
180°-Versatz, hätte „falsche" Molang-Vorzeichen vorgetäuscht), und die
Head-Tracking-Prüfung meldete jeden *existierenden* X/Y-Kanal als tot — der
`BakedAnimationsAdapter` füllt aber immer alle drei Achsen, ein durchgehend auf 0
stehender Kanal ist harmlos.

---

## 5. Validierung

### 5.1 `validate_geo.py` — 4/4 PASS, 0 Errors / 0 Warnings

```
=== GEO  .../geo/entity/eclipse_cultist.geo.json
    identifier geometry.eclipse_cultist  canvas 64x64  20 bones  17 cubes
  -> PASS (0 error(s), 0 warning(s))
=== ANIM .../animations/entity/eclipse_cultist.animation.json
    'animation.eclipse_cultist.idle': loop=True length=4.0 bones=19 keyframes=24 last_key=0.0s
    'animation.eclipse_cultist.walk': loop=True length=1.0 bones=19 keyframes=23 last_key=0.0s
    'animation.eclipse_cultist.cast': loop=False length=1.3 bones=19 keyframes=192 last_key=1.3s
    'animation.eclipse_cultist.attack': loop=False length=0.5 bones=19 keyframes=106 last_key=0.5s
    'animation.eclipse_cultist.death': loop='hold_on_last_frame' length=1.5 bones=19 keyframes=108 last_key=1.5s
  -> PASS (0 error(s), 0 warning(s))
============================================================
validate_geo: 2/2 file(s) passed — all good

=== GEO  .../geo/entity/shadow_bolt.geo.json
    note: no 'head' bone — auto head-tracking unavailable (fine for non-tracking mobs)
    identifier geometry.shadow_bolt  canvas 32x32  10 bones  8 cubes
  -> PASS (0 error(s), 0 warning(s))
=== ANIM .../animations/entity/shadow_bolt.animation.json
    'animation.shadow_bolt.idle': loop=True length=1.0 bones=9 keyframes=15 last_key=0.0s
  -> PASS (0 error(s), 0 warning(s))
============================================================
validate_geo: 2/2 file(s) passed — all good
```

Die `no 'head' bone`-Notiz am Bolt ist korrekt und gewollt: `ShadowBoltRenderer` baut sein
`DefaultedEntityGeoModel` ohne Head-Tracking.

Zusätzlich (eigenes Skript, kein Datei-Besitz berührt): **UV-Atlas-Kollisionsprüfung** —
Cultist 1823 / 4096 Texel belegt, Bolt 186 / 1024, in beiden Fällen **0 Überlappungen und
nichts außerhalb des Canvas**.

### 5.2 Painter-Determinismus — 2× laufen, md5 identisch

```
9832ca0b04e0087290e246290b64904a  .../eclipse_cultist_glowmask.png
43b5007e84f084b9e572fc9b97bdb96b  .../eclipse_cultist.png
5b8b7c53acadebf32ce13f715550c7a7  .../shadow_bolt.png
fe95c7232759ba92f8afb359f65c4bcf  .../shadow_bolt_glowmask.png
```

`diff run1 run2` → leer. Beide Driver melden 0 Cubes ohne Material
(Cultist 1807 Albedo-px / 124 Glow-px, Bolt 186 / 138).

### 5.3 GeckoLib-4.9.2-Laufzeit-Harness + Offline-Rasterizer

Der Validator prüft Schema und Bone-Namen — er kann nicht sagen, wohin eine Nase zeigt
oder ob ein Saum im Boden steckt. Deshalb zwei Werkzeuge gegen die **echte** Bibliothek
(GeckoLibs eigene Gson-Adapter, `BakedModelFactory`, `AnimationController#getAnimationPointAtTick`,
`RenderUtil.prepMatrixForBone`), Volltext in `mb3_geckolib_runtime_harness.txt`:

```
1  SHADOW BOLT — does the nose follow the flight heading?
    yRot     xRot |   nose yaw nose pitch | verdict
     0.0      0.0 |       0.00       0.00 | MATCH (dyaw 0.00, dpitch 0.00)
    45.0      0.0 |      45.00       0.00 | MATCH (dyaw 0.00, dpitch 0.00)
   -90.0      0.0 |     -90.00       0.00 | MATCH (dyaw 0.00, dpitch 0.00)
   180.0      0.0 |    -180.00       0.00 | MATCH (dyaw 0.00, dpitch 0.00)
   135.0    -20.0 |     135.00     -20.00 | MATCH (dyaw 0.00, dpitch 0.00)
    30.0     16.0 |      30.00      16.00 | MATCH (dyaw 0.00, dpitch 0.00)
   -30.0    -22.0 |     -30.00     -22.00 | MATCH (dyaw 0.00, dpitch 0.00)
  -> 10/10 headings reproduced within 1 degree

2  SHADOW BOLT — spin + wake, one loop
  loop seam: worst |v(0) - v(T)| = 0.0000  (spin.rot.z)

3  ECLIPSE CULTIST — loop seams
  idle: worst |v(0) - v(T)| = 0.0000     walk: worst |v(0) - v(T)| = 0.0000

3  ECLIPSE CULTIST — ground clearance (lowest cloth vertex, world Y in blocks)
   budget: one model texel = 1/16 block = 0.0625
anim            hem y     at t      train y     at t   verdict
attack        -0.0302     0.35       0.0483     0.40   ok (sub-texel)
cast          -0.0465     1.18       0.0481     0.22   ok (sub-texel)
death         -0.5348     1.50      -0.2581     1.50   (collapse — sinking is the point)
idle          -0.0166     1.35       0.0392     3.45   ok (sub-texel)
walk           0.0022     0.27       0.1067     0.00   ok (sub-texel)

3  ECLIPSE CULTIST — head-tracking overwrite check
  attack   peak |head.rot| x= 0.00 y= 0.00 z= 4.00 -> clean (z survives head-tracking)
  cast     peak |head.rot| x= 0.00 y= 0.00 z= 3.81 -> clean (z survives head-tracking)
  death    peak |head.rot| x= 0.00 y= 0.00 z=14.00 -> clean (z survives head-tracking)
  idle     peak |head.rot| x= 0.00 y= 0.00 z= 1.20 -> clean (z survives head-tracking)
  walk     peak |head.rot| x= 0.00 y= 0.00 z= 1.50 -> clean (z survives head-tracking)

3  ECLIPSE CULTIST — hood ember ring registration
anim      peak |x| px   min |x| px     min z px   verdict
attack          3.406        2.695       -3.100   ok (rides the hood lip)
cast            3.645        2.668       -3.550   ok (rides the hood lip)
death           3.571        0.028       -3.100   ok (snuffs out on purpose)
idle            2.832        2.628       -3.100   ok (rides the hood lip)
walk            2.832        2.654       -3.100   ok (rides the hood lip)
```

Die Bodenkontakt-Zeile ist eine echte Vorwärtskinematik über die ausgelieferte Geo: jeder
Stoff-Vertex durch die volle Bone-Kette, tiefster Punkt je Sheet. Budget ist **ein
Modell-Texel** (1/16 Block) — flacher als das kann kein einziger Pixel Saum unter der
Bodenebene erscheinen. Der Death-Wert ist Absicht (der Kniefall sackt durch).

Der zweite Teil ist ein Offline-Rasterizer, der dieselben gebackenen Bones mit Albedo +
Glowmask (additiv komponiert) in PNG-Sequenzen zeichnet. Die Artefakte:

- `mb3_eclipse_cultist_all_anims_360.mp4` — alle 5 Sheets, Kamera fährt einmal komplett um
  den Mob (die Rückansicht ist der Grund, warum Befund 2 in §4 überhaupt aufgefallen ist).
- `mb3_cultist_cast_sleeve_flare_beats.png` — die 6 Cast-Beats groß, inkl. Release-Frame.
- `mb3_shadow_bolt_homing_arc_spin.mp4` / `mb3_shadow_bolt_aim_contact_sheet.png` — ein
  Homing-Bogen über 100° Yaw und ±34° Pitch mit echten `yaw_speed`-Werten pro Tick.

### 5.4 `compileJava` — BUILD SUCCESSFUL

```
$ ./gradlew compileJava --offline --console=plain
Reusing configuration cache.
> Task :createMinecraftArtifacts UP-TO-DATE
> Task :compileJava
BUILD SUCCESSFUL in 1s
```

Gegenprobe, damit das kein Cache-Treffer ist: Gradle hasht Inhalte, `touch` allein macht
den Task also nicht schmutzig (`UP-TO-DATE`), und ein blosses Löschen der Klassen zieht
sie aus dem Build-Cache (`FROM-CACHE`). Erst mit deaktiviertem Cache läuft `javac` wirklich:

```
$ rm -rf build/classes/java/main
$ ./gradlew compileJava --offline --no-build-cache --console=plain
BUILD SUCCESSFUL in 5s
2 actionable tasks: 1 executed, 1 up-to-date
100 warnings
```

Die 100 Warnungen sind ausnahmslos fremde `EventBusSubscriber.Bus`-Deprecations
(`veilfx/**`, `worldgen/**`, `network/**`, …); aus `entity/dungeon/**` kommt **keine
einzige** — geprüft mit `grep -c 'entity/dungeon'` über das volle Compiler-Log → `0`.

### 5.5 Was NICHT gemacht wurde

Kein `runClient`-Screenshot-Durchlauf (Zensus §6.4 Punkt 4). Der Arbeitsbaum wird gerade
von sechs weiteren Executor-Teams parallel bearbeitet, ein 20–40-s-llvmpipe-Client auf
einem geteilten Stand hätte nichts Reproduzierbares geliefert. Ersatz ist der Weg, den
MA2/MA6 in dieser Welle etabliert haben: die echte GeckoLib-Ladekette offline plus ein
Rasterizer über dieselben gebackenen Bones. Was der ersetzt: Geometrie, Bone-Transforme,
Molang-Auswertung, UV-Zuordnung, Glowmask-Komposition. Was er **nicht** ersetzt:
Ressourcen-Pack-Auflösung (Pfad-Tippfehler in `geoId()`-Assets) und die echten
Blend-Modi des Render-Types. Beide Pfade sind hier unverändert bzw. bereits im Spiel
bewiesen — die Asset-Triple-Pfade sind unangetastet, und der Cultist/Bolt hat vorher schon
mit Glowmask gerendert.

---

## 6. Body-FX-Wunsch an B2 — `eclipse:cultist_hood_embers` (Hood-Glut-Loop)

**MB3 baut das NICHT.** Was folgt, ist die Spec in der Sprache von
`PhotonMobFx.LoopRow` + `tools/photon/mobs_fx.py`.

### 6.1 Anker

| | Wert |
|---|---|
| Bone | `glow_hood`, Kette `root → body → torso → neck → head → hood → glow_hood` |
| Pivot (Modell) | `(0, 22.5, −3.1)` px |
| Pivot (Blöcke, ab Fuß) | `(0, 1.406, −0.194)` — model −Z ist die Blickrichtung |
| Entity | `eyeHeight` **1.6**, Hitbox 0.6 × 1.9 |
| **`LoopRow.offset`** | **`new Vec3(0.0D, -0.19D, 0.0D)`** (Auge − 0.19 = 1.41 Blöcke = die Ringebene) |
| Ringdurchmesser | 5.5 px = **0.344 Blöcke** → Emissions-Annulus r ≈ 0.14–0.18 Blöcke |
| Vorversatz | 0.19 Blöcke **vor** der Kopfmitte entlang der Blickachse |

Zum Vorversatz: `LoopRow.offset` ist ein reiner Welt-Vektor auf die Augenposition, kann
also keine Blickrichtung tragen — alle bestehenden Zeilen nutzen ausschließlich `(0, dy, 0)`.
0.19 Blöcke liegen noch innerhalb der 0.6er Hitbox, ein reiner Y-Offset ist also brauchbar.
**Sauberer** wäre das Muster aus `gazer_gaze_beam`: `AUTO_ROTATE_LOOK` plus ein
`fx.empty(...).at(0.19, 0.0, 0.0)` als Kind — dann sitzt der Emitter exakt in der Ringebene
und **folgt dem Head-Tracking** (der Ring hängt unter `head`, und der Renderer läuft mit
`turnsHead = true`; ein fester Augen-Offset ignoriert die Kopfdrehung).

### 6.2 Timing

Loop-Lane, `attachWhen = ALWAYS`. Empfehlung `attachRange 24.0`, `maxAttached 6` —
Dungeon-Spawner (Collapsed Vault / Umbral Warrens) liefern Cultists unbegrenzt nach, die
Bolt-Zeile fährt aus demselben Grund schon ein Nearest-8-Geländer.

Die Ringgeometrie atmet bereits; die Emissionsrate sollte **phasengleich** mitgehen, sonst
schlägt Partikel- gegen Geometrie-Puls:

| Sheet | Periode | Ringskala |
|---|---|---|
| `idle` | 4.0 s (= Sheet-Länge) | 0.955 → 1.030 |
| `walk` | 0.25 s | 0.965 → 1.030 |
| `cast` | One-Shot 1.3 s | siehe unten |
| `attack` | One-Shot 0.5 s | 1.00 → **1.24 @ 0.18 s** → 0.98 @ 0.40 → 1.00 |
| `death` | One-Shot 1.5 s | 1.00 → 1.30 @ 0.25 s → 0.50 @ 0.9 → **0.01 @ 1.5** |

**Cast-Burst (Edge-Lane).** Prädikat:
`entity -> ((EclipseCultistEntity) entity).isCasting()` — das Flag hat MB3 genau dafür neu
eingezogen (§2.5). Es steht **21 Ticks = 1.05 s** auf `true`: vom Tick, an dem
`RangedShadowBoltGoal.beginCast()` den `ANIM_CAST`-Trigger feuert, bis einschließlich des
Ticks, an dem der 3-Bolt-Fächer den Cultist verlässt.

```
t (s)   0.00   0.25   0.55   0.85   1.00   1.05   1.15   1.22   1.30
scale   1.00   1.03   1.08   1.17   1.25   1.32   1.07   0.97   1.00
                                           ^ Release: hier gehen die 3 Bolts raus
```

Zwei Fallstricke:

- Auf die **steigende** Flanke triggern, nicht auf die fallende. Die fallende liegt auf dem
  Release (also 5 t vor dem Ende des Sheets) **und** feuert außerdem, wenn das Goal bei
  verlorenem Ziel `stop()` macht — dann hat es nie einen Cast gegeben.
- Der One-Shot sollte die vollen **26 t (1.3 s)** des Sheets laufen, nicht 21: der
  Nachschwing (Ring 1.07 → 0.97 → 1.00) ist die Entspannung nach dem Stoß.

`CAST_INTERVAL` ist 60 t, ein Cultist zündet also höchstens alle 3 s.

### 6.3 Farbwelt (exakt aus dem Painter)

| Rolle | Hex | Glow-Alpha |
|---|---|---|
| Ring Braue (oben, kälteste Stelle) | `#7A55B7` | 87 |
| Ring Flanke | `#B98CFF` | ~150 |
| Ring Kinn (unten, heißeste Stelle) | `#D6BBFF` | 210 |
| Augenglut — **muss heller bleiben als alles von B2** | `#E7D6FF` / `#B98CFF` | 255 / 225 |
| Kaltes Ende für Partikel, die die Kapuze verlieren | `#0E0C14` (Kapuzenschatten) bzw. `#1F1C27` (Schleppe) | — |
| Sigil-Familie am Rest des Mobs | `#B98CFF` Saum/Cuff-Trim, `#EFE3FF` Runenkern | — |

Dieselbe Violettfamilie wie `COR_VIOLET`/`COR_INK` in `mobs_fx.py`, am Kinn eine Stufe
wärmer. Das Erlöschen (`death`) ist nach innen und nach unten zu spielen — die Glut fällt
in die Kapuze, sie stiebt nicht auseinander.

### 6.4 Warum das Ding wirklich gebraucht wird

`glow_hood` ist eine **flache Quad-Scheibe**. Von der Seite und von hinten ist sie
unsichtbar, und die Kapuze zeigt dort gar keine Glut. Aus dem Modell heraus lässt sich das
nicht lösen: der Cultist rendert mit dem Cutout-Default, der Alpha *testet* — es gibt kein
weiches Ausblenden in der Albedo. Der Partikel-Loop ist also nicht Zuckerguss, sondern das,
was der Kapuze aus dem Profil überhaupt erst Volumen gibt. Bitte volumetrisch (flacher
Torus/Annulus) und **nicht** als Billboard in der Quad-Ebene.

### 6.5 Kollisionen mit bestehenden Partikeln — MB3 räumt auf Zuruf

Serverseitig laufen heute schon Vanilla-Partikel, die B2 in die Quere kommen:

- `RangedShadowBoltGoal.tickCastWindup`: `ParticleTypes.WITCH` ×4 alle 4 t auf **y + 1.4** —
  das ist praktisch exakt die Ringebene (1.41).
- `EclipseCultistEntity.tickDeath`: WITCH alle 6 t auf y + 0.8, plus SOUL-Puff am Ende.

Beide Dateien gehören MB3. Wenn `cultist_hood_embers` steht, fliegt der Windup-WITCH-Burst
auf ein Wort hin raus — er war der Platzhalter für genau diesen Effekt.

### 6.6 Nachtrag zu `shadow_bolt_ribbon` (bestehende B2-Zeile, Concept #6)

Der Bolt hat jetzt eine **Nase** (bis Modell z −5.5 px = 0.34 Blöcke vor der Mitte) und
zwei Wake-Shards (+3…+5 px = 0.19…0.31 Blöcke dahinter). Die Ribbon-Zeile ankert
offset-los auf der Augenposition, das Band startet also mitten in der jetzt hell
leuchtenden Spitze. Vorschlag: den Ribbon-Anker rund **0.25 Blöcke entgegen der
Flugrichtung** setzen, damit das Band hinter den Wake-Shards ansetzt statt vor ihnen. Kein
Muss — nur der Punkt, an dem sich die zwei Effekte jetzt überlagern.

---

## 7. Test-Rezept (Client)

```
# --- Eclipse Cultist ----------------------------------------------------
# 1) /summon eclipse:eclipse_cultist ~3 ~ ~ und STEHEN BLEIBEN (kein Ziel):
#    idle. Kapuzenring pulst auf der 4-s-Periode, Robenkette und Cuffs
#    schwingen mit drei verschiedenen Phasen — von der SEITE ansehen.
# 2) Wegdrehen und laufen lassen: walk. Der Saum hinkt der Hüfte hinterher,
#    die Rückenschleppe am längsten.
# 3) In das 8–14-Band stellen -> cast. Der Ärmel-Flare geht beschleunigt auf
#    und die 3 Bolts verlassen ihn auf Tick 21 im Peak der Glocken (1.05 s).
#    Beim Nachschwing auf 1.19 s wirft die Schleppe am weitesten nach vorn.
# 4) Auf 2 Blöcke rangehen -> attack (Panikmesser). Das war vorher ein
#    6-Bone-Sheet; jetzt reisst der Stich die ganze Robe mit.
# 5) /kill -> death (30 t, aufrecht gehalten). Der Kapuzenring erlischt.
# 6) Gegenprobe Head-Tracking: um ihn herumlaufen. Der Kopf folgt (Renderer
#    turnsHead=true), die Nick-Kurven aus dem Sheet liegen auf `neck` und
#    ueberleben das.
#
# --- Shadow Bolt --------------------------------------------------------
# 7) Den Fächer aus 12 Blöcken auf sich zufliegen lassen und SEITLICH
#    ausweichen: die Bolts homen, und die Nase legt sich sichtbar in die
#    Kurve (aim) waehrend der Koerper weiterrollt (spin, 2 U/s).
# 8) Von der Seite zusehen, wie ein Bolt einen Bogen fliegt: der Schweif
#    (wake) haengt nach aussen aus der Kurve heraus, nicht mittig hinterher.
# 9) In einem stockdunklen Raum wiederholen — fullbright + Glowmask, der
#    Bolt muss identisch lesen.
```

---

## 8. Offene Punkte

1. **Kein `runClient`-Durchlauf** (§5.5). Empfehlung an den Integrator: einen gesammelten
   Client-Pass für alle M-B-Teams fahren, sobald der Baum ruhig ist — die Asset-Pfade sind
   unverändert, es geht nur um den finalen Augenschein.
2. **`glow_hood` ist seitlich unsichtbar** (flache Scheibe, §6.4). Bewusst so; die Lücke
   schließt B2s Loop. Alternative wäre ein hohler Ringkörper aus 4 Cubes — vier Cubes und
   vier UV-Rechtecke für einen Effekt, den der Partikel-Emitter besser kann.
3. **`isCasting()` ist neu und noch ungenutzt.** Bis B2 die Zeile zieht, kostet das Flag
   ein Bit im Sync-Paket und sonst nichts. Falls B2 den Effekt streicht: Flag wieder
   ausbauen (3 Stellen in 2 Dateien).
4. **Windup-WITCH-Partikel warten auf B2** (§6.5) — MB3 nimmt sie raus, sobald der echte
   Effekt steht, nicht vorher (sonst hat der Cast in der Zwischenzeit gar keinen Tell).
5. **Langdrop enthält Ersetzungen, keine neuen Keys** — `docs/plans_v3/langdrop/MB3-DUNGEON.json`
   überschreibt zwei bestehende Bestiarium-Zeilen (Lore + Behavior, en+de), damit der Text
   die neue Silhouette beschreibt. Der Integrator muss hier bewusst *überschreiben*, nicht
   anfügen.
