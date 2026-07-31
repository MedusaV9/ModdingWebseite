# MC3 — Sunmote + Drift Lantern (Ambient-Paar, F-098 Welle M-C)

**Status:** FERTIG — `validate_geo` 2/2 PASS für BEIDE Paare (0 Errors / 0 Warnings),
Painter deterministisch (2× Lauf, md5 identisch), `./gradlew compileJava` grün (auch mit
`--rerun`, also echter Vollcompile, nicht UP-TO-DATE). Wörtliche Belege in §8.
**Datei-Besitz (Zensus §5, Zeile MC3):** `entity/SunmoteEntity` +
`client/entity/sunmote/*` (neuer Renderer-Ordner; die Löschung der Legacy-Zeilen läuft
über das Snippet in §10), `entity/ambient/*`, Assets `sunmote*` + `drift_lantern*`,
Painter `scripts/geckolib_gen/mobs/{sunmote,drift_lantern}.py`, `docs/uv/{sunmote,drift_lantern}.md`,
dieser Report. Nichts anderes angefasst — insbesondere KEINE FROZEN-Basis, kein
`validate_geo.py`/`paint_lib.py`, kein `tools/photon/**`, keine Lang-Datei.

---

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

Alles hier ist gegen echte Quellen geprüft, nicht gegen Erinnerung — die Zeilennummern
stammen aus dem entpackten NeoForge-Sources-Jar (21.1.238) bzw. aus `javap -c` auf
`geckolib-neoforge-1.21.1-4.9.2.jar`.

**F-9 (`state.isMoving()` triggert bei tick-getriebenen Drifters nie).** Der Zensus nennt
das Symptom, nicht die Ursache. Es sind ZWEI unabhängige Ursachen, jede allein tödlich:

1. **Reihenfolge.** `ServerLevel.tickNonPassenger` (Z. 770) und
   `ClientLevel.tickNonPassenger` (Z. 297) rufen `setOldPosAndRot()` unmittelbar VOR
   `Entity.tick()`. Das Limb-Swing wird in `LivingEntity.travel()` am Ende über
   `calculateEntityAnimation` (Z. 2346) aus `getX() - this.xo` berechnet — also BEVOR ein
   Drifter, der sein `setPos` in seinem eigenen `tick()`-Override nach `super.tick()`
   absetzt, überhaupt umgezogen ist. `walkAnimation.speed` bleibt dauerhaft 0.
2. **Schwelle.** GeckoLib berechnet `isMoving` in `GeoEntityRenderer` als
   `(|motion.x| + |motion.z|) / 2 >= getMotionAnimThreshold(...)` **UND**
   `limbSwingAmount != 0` (Bytecode `GeoEntityRenderer` Offsets 419–480; der Default in
   `GeoRenderer.getMotionAnimThreshold` ist wörtlich `ldc #41 // float 0.015f`). Die
   Laterne driftet mit 0.025 b/t nur auf EINER Achse → `(0.025 + 0)/2 = 0.0125 < 0.015`.
   Sie fällt selbst dann durch, wenn Ursache 1 behoben wäre.

**Wie MA5 es umgeht (angeschaut, wie beauftragt).** Der Soul Wisp
(`ferryman/finale/SoulWispEntity`) überschreibt `handleBaseState` **gar nicht**. Er
umgeht F-9 strukturell: er teleportiert nie, sondern setzt nur `setDeltaMovement(...)`
und überschreibt `travel(Vec3)` (Z. 266–271) mit `move(MoverType.SELF, …)`. Damit bleibt
er auf dem Vanilla-Bewegungspfad, `calculateEntityAnimation` sieht die Bewegung, und
seine Chase-/Swirl-Speeds liegen über 0.015. **Dieser Weg stand meinen beiden Mobs nicht
offen:** die Laterne ist mit 0.025 b/t zu langsam für die Schwelle (Ursache 2 bleibt), und
der Sunmote muss exakt auf seiner Orbit-Kreisbahn sitzen — eine `move()`-Integration mit
Kollision/Reibung würde gegen die Positionsvorgabe arbeiten. Beide brauchen also wirklich
das eigene Delta.

**Warum `getX() - this.xOld` das richtige Delta ist.** Ich habe alle Schreiber von `xOld`
im gesamten entpackten Sources-Jar aufgelistet (`grep -rn "xOld\s*="`), nicht nur in
`Entity`. Es sind fünf, und **keiner** davon greift bei meinen beiden Mobs in den Tick ein:

| Schreiber | betrifft |
|---|---|
| `Entity.setOldPosAndRot()` (Z. 1479) | alle — der eine gewollte Schreiber, läuft direkt vor `tick()` |
| `LevelRenderer` (Z. 1021) | nur `tickCount == 0`, reiner Erst-Frame-Primer |
| `ClientPacketListener` (Z. 676/681) | nur der lokale Spieler |
| `Shulker` (Z. 342), `EnderDragon` (Z. 393) | eigene Klassen |

Am Ende von `tick()` gemessen ist `getX() - xOld` damit exakt der Tick-Versatz — server-
wie clientseitig (auf dem Client hat `super.tick()` da bereits den Interpolationsschritt
angewandt). Wichtig ist die Feldwahl: `xOld` ≠ `xo`. Beide setzt `setOldPosAndRot()`, aber
`absMoveTo` (Z. 1439) überschreibt zusätzlich **nur `xo`** mit dem Ziel und würde das Delta
auf jedem Tick, der da durchläuft, still auf 0 ziehen. `xOld` bleibt davon unberührt und
ist deshalb das saubere Feld für den Tracker. (`calculateEntityAnimation` selbst liest
`xo` — deswegen ist der Vanilla-Pfad der anfälligere.)

**Ist-Zustand vor MC3.** Sunmote: `SunmoteModel` (3 Cubes, handcodiert), `SunmoteRenderer`
mit additivem `RenderType.eyes`-Pass über die GANZE Textur (Zensus-Falle F-7 — keine
Glowmask, keine differenzierte Emission), kein Keyframe-Sheet. Drift Lantern: GeckoLib
schon da (P6-W1-Pilot), aber 8 Bones / 9 Cubes ohne Aufhängung — der „Hanger-Loop" saß
oben auf dem Deckel und hing an nichts.

**Hitboxen bleiben unangetastet** (`EclipseEntities`/`AmbientEntities` sind fremd, G2):
Sunmote 0.4×0.4 / eye 0.2, Drift Lantern 0.6×1.1 / eye 0.75, beide `updateInterval` =
Default 3. Die 3 ist die Zahl, gegen die der Hold des Trackers dimensioniert ist.

---

## 1. Sunmote — Geo (`geometry.sunmote`, 32², 10 Bones / 11 Cubes)

```
root
└─ body (0,4,0)                     Träger für Bob/Lean; kein Cube
   ├─ glow_core (0,4,0)             Korona-Schale 3³, y 2.5–5.5   — emissiv
   │  └─ glow_kernel (0,4,0)        Herzschlag-Kern 2³, y 3–5     — emissiv;
   │                                pulst bis 1.8× und BRICHT dabei durch die Schale
   ├─ glow_crown (0,4,0)            4 kurze 45°-Spitzen 1×1×2 als CUBES auf EINEM Bone
   │  ├─ glow_ray_a (0,4,0)         ┐ 4 lange Strahlen 1×1×3, kardinal (Cube-yRot 0/90/180/270)
   │  ├─ glow_ray_b (0,4,0)         │ EIGENE Bones, weil jeder Strahl unabhängig
   │  ├─ glow_ray_c (0,4,0)         │ schimmert (90°-Phasenversatz) — auf einem Bone
   │  └─ glow_ray_d (0,4,0)         ┘ ginge nur ein gemeinsamer Takt
   └─ halo (0,4,0)                  Ring-Platte 5×1×5, um 45° gedreht, y 3.25–4.25
```

**Auftrag war „~8 Bones", geworden sind 10.** Die zwei über Plan sind `glow_kernel` und
`halo`: der Kranz ist als 4 Cubes auf `glow_crown` + 4 Bones zusammengefasst (statt 8
Bones), aber Kern und Halo brauchen eigene Kanäle — der Kern, weil sein Puls unabhängig
von der Schale laufen muss (er ist ja das, was DURCH die Schale bricht), der Halo, weil er
gegenläufig zum Kranz rotiert. 10 statt 8 kaufen also genau die zwei Bewegungen, die den
Mote von einem leuchtenden Würfel unterscheiden.

**Ausdehnung.** Strahlenspitzen bei r=4.5 px (0.281 b), Halo-Ecken bei 3.53 px. Die Hitbox
ist 0.4 b breit (±0.2 b = ±3.2 px), der Kranz ragt also ~1.3 px darüber hinaus. Das ist
Absicht und nicht änderbar: die Hitbox gehört `EclipseEntities` (G2, fremd), und ein auf
3.2 px gestutzter Kranz wäre kein Kranz mehr. Der KÖRPER des Motes (die Korona, r=1.5 px)
liegt komfortabel innen — man schlägt nach dem Kern, nicht nach dem Lichtstrahl.

---

## 2. Sunmote — Animation (`animation.sunmote.*`, Format 1.8.0)

| Anim | Loop | Länge | Rolle |
|---|---|---|---|
| `idle` | true | 4.0 s | Basking-Pause: langsamer Bob, ruhiger Kranz-Spin, sanfter Kern-Puls |
| `walk` | true | 3.0 s | Orbit-Gleiten: 5° Vorlage, schnellerer Doppel-Puls, stärkeres Strahlen-Flackern |
| `chime` | false | 0.9 s | Flare-Beat auf den Ambient-Chime (Kranz + Halo + Korona blühen auf) |
| `attack` | false | 0.6 s | härterer Flare, im Sheet vorhanden aber ungenutzt (Sunmote greift nicht an) |
| `death` | hold | 1.2 s | Kranz klappt weg, Kern flackert zweimal auf und guttert aus (= 24 t) |

**Kontinuierliche Rotation über `query.life_time`, nicht `query.anim_time`.** Kranz und
Halo drehen dauerhaft (`[0, "query.life_time * 90", 0]` bzw. `* -55`). Mit `anim_time`
würde die Drehung bei jedem Loop-Neustart auf 0 zurückspringen und beim Wechsel
idle↔walk rückwärts schnappen; `life_time` läuft monoton mit dem Entity-Alter weiter.
Beide Loops benutzen **dieselben** Raten, sodass der Übergang die Drehung nicht anfasst.
Die `death`-Keyframes sind ebenfalls als `"query.life_time * 90 + 150"` geschrieben — der
Spin läuft in den Tod hinein weiter, statt auf einen absoluten Winkel zu schnappen.

**Kanal-Eigentum (siehe §6, Pass 3).** `idle`/`walk` fahren ausschließlich Rotation und
Position plus `glow_kernel.scale`. Alle `scale`-Kanäle von Korona, Kranz, Strahlen und
Halo gehören exklusiv den One-Shots. Damit teilen sich Basis-Loop und `chime`/`attack`
KEINEN einzigen Kanal, und der Moment, in dem der `action`-Controller stoppt, ist
unsichtbar. Bezahlt wird das mit größeren Rotations-Amplituden in den Loops, damit die
Strahlen ohne Scale-Kanal trotzdem leben.

---

## 3. Drift Lantern — Aufhängungs-Kette (Geo, 64², 11 Bones / 13 Cubes)

Neu gegenüber dem P6-W1-Pilot sind `chain_upper` und `chain_lower`; der alte „Hanger-Loop"
ist jetzt der Schäkel-Ring am unteren Kettenglied, und `body` hängt unter der Kette statt
unter `root`:

```
root
└─ chain_upper  (0,28,0)   Kettenstrang 2×6×2, y 22–28 — oberes Ende löst sich in den Nebel auf
   └─ chain_lower (0,22,0) Kettenstrang 2×4×2 (y 17–21) + Schäkel-Ring 3×1×3 (y 21–22)
      └─ body (0,17,0)     Laterne, pendelt um ihre Aufhängung
         ├─ glow_flame → glow_flame_core
         ├─ cage
         └─ tendril_a..d
```

Die Kette hängt an y=28 px = 1.75 b, also 0.65 b über der 1.1-b-Hitbox. Das ist gewollt:
man trifft die Laterne, nicht die Kette. Damit das nicht wie ein abgeschnittener Stumpf
aussieht, blendet der Painter die obersten zwei Texel-Reihen von `chain_upper` in der
Alpha aus und lässt die Deckelfläche ganz weg — die Kette verschwindet im Limbo-Nebel.
`visible_bounds` sind auf 2×3 b bei Offset y=0.9 angehoben, sonst poppt die Kette beim
Frustum-Cull.

Die Kette liest sich nur dann als Kette, wenn man durch sie hindurchsieht: das Material
lässt jede dritte Texelreihe auf Alpha 0 fallen (echte Löcher, der Cube ist hohl und
back-face-culled). Das war nur zulässig, weil der Renderer wegen der 40-%-Glasscheiben
ohnehin `withTranslucency()` fährt.

---

## 4. Drift Lantern — Pendel + `flicker`

| Anim | Loop | Länge | Rolle |
|---|---|---|---|
| `idle` | true | 2.0 s | Hover: Kette schwingt ruhig, Flamme atmet |
| `walk` | true | 2.0 s | Gleiten: Kette hängt 3.5° nach hinten und schwingt weiter aus |
| `flicker` | false | 0.8 s | Flammen-Gutter: vier unregelmäßige Einbrüche, endet exakt in Ruhelage |
| `attack` | false | 0.5 s | Sheet-Vollständigkeit, ungenutzt |
| `death` | hold | 1.5 s | Kette erschlafft, Laterne kippt aus, Flamme erlischt (= 30 t) |

**Die 2.0 s sind nicht gewürfelt.** Vom Nebel-Anker (y=28 px) bis zur Flamme (y≈12 px)
sind 16 px = 1.00 m. Ein mathematisches Pendel dieser Länge hat
`T = 2π·√(L/g) = 2π·√(1.00/9.81) = 2.006 s`. Auf 2.0 s gerundet ist das exakt der
Loop — und 2.0 s = 40 t geht glatt in den Tick auf.

Das untere Segment ist als Oberschwingung dazugemischt (`sin(anim_time·360)`, also 1.0 s
= Oktave), nicht mit seiner echten Normalmode: das Untersegment allein hätte
`2π·√(0.625/9.81) = 1.586 s`, und 1.586 teilt 2.0 nicht — es würde die Loop-Naht
aufreißen. Die Oktave ist die bewusste Näherung, die den „das untere Glied zappelt
schneller"-Eindruck liefert UND `f·len ≡ 0 mod 360` erfüllt.

**Nachlauf.** Kette, Laterne und Tentakel müssen dem Anker nach unten hin folgen: jedes
Segment schwingt weiter aus und läuft phasenmäßig nach. Das ist im Sheet nicht ablesbar,
weil jede Bone-Rotation RELATIV zum Elternteil ist — die absolute Bewegung ist die Summe
über die Hierarchie. Genau da lag ein Bug (§6, Pass 2). Der geprüfte Endstand:

```
idle / X-swing                        walk / X-swing
  chain_upper  amp  3.00°  (Anker)      chain_upper  amp  4.50°  (Anker)
  chain_lower  amp  6.77°  +lag +17.2°  chain_lower  amp 10.15°  +lag +17.2°
  body         amp 10.48°  +lag +23.0°  body         amp 15.72°  +lag +23.0°
  tendril_a    amp 15.20°  +lag +30.2°  tendril_a    amp 22.76°  +lag +30.1°
  tendril_b    amp 16.68°  +lag +45.2°  tendril_b    amp 25.05°  +lag +45.3°
  tendril_c    amp 15.76°  +lag +21.9°  tendril_c    amp 23.64°  +lag +21.9°
  tendril_d    amp 17.80°  +lag +51.8°  tendril_d    amp 26.78°  +lag +51.9°
```

Amplitude und Nachlauf wachsen auf beiden Achsen und in beiden Loops monoton nach unten.
Die vier Tentakel behalten dabei absichtlich unterschiedliche Nachläufe (+22° bis +52°) —
vier Kelp-Stränge sollen nicht im Gleichschritt wedeln — aber jeder von ihnen läuft dem
Körper nach, statt gegen ihn zu arbeiten.

**Gierung (Java).** Der `walk`-Loop hängt die Kette nach hinten aus der Fahrtrichtung.
Das ergibt nur Sinn, wenn die Laterne auch in ihre Fahrtrichtung schaut — vorher behielt
sie ewig den Zufalls-Yaw vom Spawn. `faceDrift()` zieht den Yaw mit `Mth.rotLerp(0.06, …)`
nach (≈1.5 s für 180°, kein Schnappen bei neuem Wegpunkt) und ignoriert fast senkrechte
Beine, deren Horizontalanteil nur Rauschen ist.

**`flicker` (0.8 s).** Nur `glow_flame` — Scale, Position und Rotation, alle mit
`catmullrom`. Vier Einbrüche mit ungleichen Abständen (0.06 / 0.26 / 0.46 s) und
ungleicher Tiefe (0.42 → 0.30 → 0.48 der Höhe), damit es nicht als Sinus liest; die
Flamme sackt dabei bis −1 px durch (sie „fällt" in den Docht), kippt ±5° und schießt bei
0.58 s auf 1.2 über, bevor sie bei 0.8 s exakt auf `[1,1,1]` / `[0,0,0]` zurückkommt. Die
Ruhelage am Ende ist maschinell geprüft (§6, Pass 3).

---

## 5. F-9 in Java — `entity/ambient/DriftTracker`

Statt zweimal dieselbe Delta-Logik zu schreiben, liegt sie einmal in einer 74-Zeilen-
Hilfsklasse, die sich beide Mobs teilen (`SunmoteEntity` und `DriftLanternEntity`
halten je eine Instanz). Kern:

```java
public void track(double dx, double dz) {
    if (dx * dx + dz * dz > this.epsilonSqr) {   // 1.0E-5 = 0.0032 b/t
        this.glideTicks = this.holdTicks;        // 6
    } else if (this.glideTicks > 0) {
        this.glideTicks--;
    }
}
public boolean gliding() { return this.glideTicks > 0; }
```

Beide Mobs rufen `drift.track(getX() - xOld, getZ() - zOld)` als **letzte** Anweisung in
`tick()` — server- wie clientseitig — und `handleBaseState` liest nur noch
`drift.gliding() ? walkAnim() : idleAnim()`.

Drei Entscheidungen, die nicht offensichtlich sind:

* **Der Hold von 6 Ticks ist Pflicht, nicht Komfort.** Der Client bekommt nur alle
  `updateInterval` = 3 Ticks eine Positionsaktualisierung; an den zwei Ticks dazwischen
  ist das rohe Delta 0. Ein naives Lesen lässt den `base`-Controller mit ~7 Hz zwischen
  `walk` und `idle` flattern. 6 = 2× Paket-Kadenz.
* **Nur horizontal.** Beide Drifter reiten eine permanente Vertikal-Sinus (Sunmote-Bob,
  Laternen-Hover). Zählte man sie mit, stünde `gliding()` für immer auf true und der
  `idle`-Loop wäre unerreichbar — beim Sunmote wäre damit ausgerechnet das Basking
  unsichtbar. Preis: ein fast rein vertikales Driftbein liest als Schweben.
* **`handleBaseState` liest nur, es misst nicht.** Der frühere Inline-Read von
  `getX() - xOld` direkt im State-Handler war im Prinzip richtig, lief aber auf dem
  RENDER-Thread, wo genau das obige Null-Delta-Problem zuschlägt. Der Tracker sampelt
  einmal pro Tick und hält.

Zusätzlich am Sunmote: der Orbit-Yaw folgt jetzt der Tangente
(`atan2(cos θ, −sin θ)·RAD_TO_DEG − 90`, gegen die MC-Yaw-Konvention geprüft), damit der
zurückgeschwungene Kranz im `walk` auch wirklich hinter der Flugrichtung liegt; und ein
Basking-Zyklus (alle ~13–25 s für 2–5 s) hält den Orbitwinkel an, damit der `idle`-Loop
überhaupt je zu sehen ist.

---

## 6. Selbstkritik — was die Polish-Pässe gefunden haben

Ich habe drei Pässe gefahren, jeder mit einem eigenen kleinen Prüf-Harness statt mit dem
Auge (Anhang A). Alle drei haben echte Bugs gefunden — keiner davon war beim Lesen des
Sheets sichtbar.

### Pass 1 — Z-Fighting im Sunmote-Kranz (Geometrie)

Zwei koplanare Flächen flimmern nur dann, wenn beide das Back-Face-Culling überleben,
also wenn ihre Normalen in dieselbe Richtung zeigen. Ein Cube, der auf einem anderen
steht, ist harmlos (Unterseite trifft Oberseite). Halo, Kranz-Spitzen und Strahlen lagen
aber alle exakt im Band y 3.5–4.5 — ihre Ober- **und** Unterseiten waren paarweise
koplanar und gleichgerichtet:

```
sunmote (vor dem Fix): 11 cubes, 16 coplanar same-facing overlaps
      up y=4.5  glow_crown#0 <-> halo#0
    down y=3.5  glow_crown#0 <-> halo#0
      … (je 2 pro Kranz-Spitze und pro Strahl, 8 Cubes × 2)
```

Fix: Halo auf y 3.25–4.25 abgesenkt (der Ring sitzt jetzt eine Vierteltexel unter der
Kranz-Ebene und liest dadurch sogar besser als eigener Ring). Bei der Gelegenheit die
Strahlen von z −5…−2 auf −4.5…−1.5 gezogen: sie sitzen jetzt bündig an der Korona statt
mit 0.5 px Luft davor zu schweben. Die Innenfläche des Strahls ist zwar koplanar mit der
Korona-Außenfläche, zeigt aber in die Gegenrichtung → wird weggecullt, kein Flimmern.
Nachher: **0 Treffer** bei beiden Modellen. UVs unverändert, also Textur bit-identisch.

### Pass 2 — die Kette schwang gegen sich selbst (Animation)

Der ursprüngliche Nachlauf des Laternenkörpers war `sin(θ + 140°)` — als absoluter
Winkel gerechnet ein Nachlauf von 220°, also faktisch ein Gegenschwung. Der Körper hob
die Schwingung des unteren Kettenglieds teilweise auf:

```
vorher, idle / X:  chain_upper 3.00° lag 90.0° | chain_lower 6.77° lag 107.2°
                   body        2.90° lag 65.3°   <-- kleinere Amplitude UND weniger Nachlauf
```

Das ist physikalisch falsch herum. Die Antriebsperiode (2.0 s) liegt UNTER der
Eigenfrequenz des Unterpendels (1.586 s), also unterhalb der Resonanz — dort folgt die
Last mit kleinem Nachlauf, sie schlägt nicht um. Ich habe die Zielphasoren gesetzt
(Amplitude ×1.55, Nachlauf +23° pro Segment) und die relative Bone-Rotation daraus
zurückgerechnet: `sin(θ − 72°)` für X, `sin(θ + 18°)` für Z. Die Amplituden blieben
dabei fast unverändert — es war ein reiner Phasenfehler.

Derselbe Test hat danach die Tentakel erwischt: zwei der vier (a und d) schwangen
absolut SCHWÄCHER als der Körper, an dem sie hängen — sie sahen geschleppt aus statt
nachlaufend. Ursache war der 90°-Versatz zwischen ihnen, gedacht als organische Variation,
aber so groß, dass zwei Stränge gegen die Phase liefen. Jetzt sind es +30/+45/+22/+52°
Nachlauf bei Gain 1.45–1.70: immer noch vier erkennbar verschiedene Stränge, aber alle
hinter dem Körper. Endstand siehe die Tabelle in §4.

### Pass 3 — Loop-Nähte, Ruhelagen und Kanal-Eigentum

Die Regel `f·len ≡ 0 mod 360` prüft nur reine Sinus. Ich habe stattdessen die echten
Kurven abgetastet und Wert UND Steigung an der Naht verglichen — das deckt auch
Harmonik-Summen, Kosinus-Phasen und die `life_time`-Rampen ab (die sind vom Nahttest
befreit, weil sie nie zurückspringen, dafür wird ihre Linearität separat geprüft: eine
`life_time` INNERHALB eines `sin()` kann nicht loopen und wird als Fehler gemeldet).
Dazu der Ruhelagen-Test für One-Shots und der Kanal-Eigentums-Test.

Der Kanal-Test war der wertvollste: GeckoLib schreibt die Kanäle jedes Controllers
absolut auf den Bone-Snapshot, und der zuletzt registrierte gewinnt — `action`
überschreibt also stillschweigend `base` und gibt den Kanal in dem Frame zurück, in dem
der One-Shot stoppt. Daraus folgen zwei harte Regeln, die jetzt maschinell gelten:

```
sunmote.animation.json
  base (idle+walk) owns 10: body.position, body.rotation, glow_crown.rotation,
    glow_kernel.scale, glow_ray_a..d.rotation, halo.position, halo.rotation
  chime    owns  7, overlap with base: none
  attack   owns  7, overlap with base: none
  death    owns 17, covers base: YES

drift_lantern.animation.json
  base (idle+walk) owns 9: body.rotation, chain_lower.rotation, chain_upper.rotation,
    glow_flame_core.scale, root.position, tendril_a..d.rotation
  flicker  owns  3, overlap with base: none
  attack   owns  3, overlap with base: none
  death    owns 10, covers base: YES
```

„overlap: none" heißt: kein Pop beim Stopp des One-Shots. „covers base: YES" heißt: die
gehaltene Todes-Pose atmet nicht weiter — sonst würde die Leiche auf den vergessenen
Kanälen munter weiterpendeln.

Die drei Harnesse melden jetzt **0 Probleme** (§8). Damit die Zahl etwas wert ist, habe
ich jeden gegen absichtlich kaputte Kopien laufen lassen (Anhang A) — sie schlagen an.

### Was ich NICHT gelöst habe

* **Die Glowmask der Laterne ist statisch.** Der Schein-durch-das-Glas ist in die
  Cage-Textur gebacken, weil der Glow-Layer den inneren Flammen-Bone unter dem
  transluzenten Glas per Tiefentest verwirft. Wenn `flicker` die Flamme guttert, bleibt
  der Käfig also gleich hell — der Einbruch ist nur an der geschrumpften Flamme zu sehen,
  nicht am Lichtwurf. Das ist weder in der Textur noch in GeckoLib lösbar und genau der
  Grund für §7.
* **Kein `runClient`-Sichttest.** Zensus-Falle F-14: es gibt keinen Test-Task, und der
  Client wurde in dieser Session nicht gestartet. Alles oben ist analytisch bzw. per
  Offline-Renderer geprüft, was Silhouette, Hierarchie, Pose, Loop-Verhalten und
  Z-Fighting abdeckt — aber nicht Shader-Interaktion, Iris-Verhalten oder die tatsächlich
  wahrgenommene Helligkeit. Das Rezept dafür steht in §12.

---

## 7. Photon-Koppel-Spec für `flicker` (SPEC ONLY — nicht gebaut)

Ziel: der Lichtwurf der Laterne soll mit dem `flicker` einbrechen, nicht nur die
Flammen-Geometrie. Das gehört nicht MC3 (`tools/photon/**` und `assets/eclipse/fx/**` sind
fremd), deshalb hier nur die Schnittstelle. **Nichts davon ist implementiert.**

**Der Kopplungspunkt ist ein `timeline`-Keyframe, kein zweiter Timer.** Verifiziert:
GeckoLib 4.9.2 parst `sound_effects`, `particle_effects` und `timeline` in
`loading/json/typeadapter/KeyFramesAdapter`, und `AnimationController` bietet
`setCustomInstructionKeyframeHandler(...)`. Damit feuert die Kopplung Frame-genau aus dem
Sheet heraus statt aus einem parallel laufenden Java-Timer, der gegen die Animation
driftet.

**Schritt 1 — Sheet** (`drift_lantern.animation.json`, `animation.drift_lantern.flicker`,
neben `bones`):

```json
"timeline": {
  "0.06": "photon:flicker_dip 0.42",
  "0.26": "photon:flicker_dip 0.30",
  "0.46": "photon:flicker_dip 0.48",
  "0.58": "photon:flicker_surge 1.20"
}
```

Die vier Zeitpunkte sind **exakt** die Scale-Tiefpunkte bzw. der Überschwinger der
bestehenden `glow_flame`-Kurve, und der Zahlenwert ist der Scale-Faktor an dieser Stelle.
Wer die Kurve später umtimt, muss die `timeline` mitziehen — sonst löst sich die Kopplung
lautlos.

**Schritt 2 — Controller** (in `DriftLanternEntity.registerActionTriggers`, MC3-Besitz,
also dort einbaubar sobald die FX-Seite steht):

```java
action.setCustomInstructionKeyframeHandler(event -> {
    String[] parts = event.getKeyframeData().getInstructions().split(" ");
    DriftLanternFx.pulse(event.getAnimatable(), parts[0], Float.parseFloat(parts[1]));
});
```

**Schritt 3 — FX-Seite** (gehört dem FX-Team, nicht MC3): ein
`PhotonBridge.spawnOnEntity(...)`-Row nach dem Muster von
`veilfx/BossPhotonFxRows`/`PhotonFxRegistry.Row`, mit dem Loop-Muster von
`tools/photon/grave_lantern_fx.py` als Vorlage — dort steht bereits alles über
Model-Partikel-Anker, den erzwungenen Lightmap-15 und die HDR-Stapel-Obergrenze.

**Vier Randbedingungen, die die spätere Umsetzung sonst teuer bezahlt:**

1. **`timeline` kostet eine `validate_geo`-Warnung.** Der Validator (Z. 384–387) warnt
   bei `sound_effects`/`particle_effects`/`timeline` mit *„GeckoLib keyframe handlers must
   be wired in the controller for it to do anything"*. Das ist genau richtig so — aber es
   heißt, das Sheet und die Controller-Verdrahtung müssen **im selben Commit** landen,
   sonst reißt es das 0-Warnings-Ziel dieses Pakets auf. Deshalb ist die `timeline` heute
   nicht drin.
2. **Der `action`-Controller trägt auch `death`.** Ein Custom-Handler bekommt die
   Keyframes JEDER Animation dieses Controllers. Wenn `death` später ebenfalls eine
   `timeline` bekommt, muss der Handler nach Instruktions-Präfix unterscheiden — er darf
   nicht davon ausgehen, nur `flicker` zu hören.
3. **`flicker` läuft ohne Server-Rückfrage weiter.** Der Trigger kommt vom Server
   (`triggerAction(ANIM_FLICKER)` alle 12–24 s), der Keyframe feuert danach clientseitig.
   Der Puls darf also nichts Autoritatives tun (kein Schaden, kein Lichtblock) — reine
   Optik.
4. **Der eigentliche Gewinn ist der Käfig, nicht die Flamme.** Die Flamme schrumpft schon
   sichtbar. Was fehlt, ist der Einbruch des SCHEINS auf den Glasscheiben (§6). Der
   Photon-Puls sollte deshalb am Käfig-Mittelpunkt (Bone `cage`, y≈12 px = 0.75 b über
   dem Entity-Ursprung) ansetzen und mit dem Scale-Faktor aus der `timeline` skalieren —
   nicht an der Flammenspitze.

---

## 8. Validierung (wörtlich)

### 8.1 `validate_geo` — beide Paare, 0 Errors / 0 Warnings

```
$ python3 scripts/geckolib_gen/validate_geo.py \
      src/main/resources/assets/eclipse/geo/entity/sunmote.geo.json \
      src/main/resources/assets/eclipse/animations/entity/sunmote.animation.json

=== GEO  src/main/resources/assets/eclipse/geo/entity/sunmote.geo.json
    note: no 'head' bone — auto head-tracking unavailable (fine for non-tracking mobs)
    identifier geometry.sunmote  canvas 32x32  10 bones  11 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/entity/sunmote.animation.json
    'animation.sunmote.idle': loop=True length=4.0 bones=8 keyframes=9 last_key=0.0s
    'animation.sunmote.walk': loop=True length=3.0 bones=8 keyframes=10 last_key=0.0s
    'animation.sunmote.chime': loop=False length=0.9 bones=7 keyframes=29 last_key=0.9s
    'animation.sunmote.attack': loop=False length=0.6 bones=7 keyframes=28 last_key=0.6s
    'animation.sunmote.death': loop='hold_on_last_frame' length=1.2 bones=9 keyframes=62 last_key=1.2s
  -> PASS (0 error(s), 0 warning(s))

============================================================
validate_geo: 2/2 file(s) passed — all good
```

```
$ python3 scripts/geckolib_gen/validate_geo.py \
      src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json \
      src/main/resources/assets/eclipse/animations/entity/drift_lantern.animation.json

=== GEO  src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json
    note: no 'head' bone — auto head-tracking unavailable (fine for non-tracking mobs)
    identifier geometry.drift_lantern  canvas 64x64  11 bones  13 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/entity/drift_lantern.animation.json
    'animation.drift_lantern.idle': loop=True length=2.0 bones=9 keyframes=9 last_key=0.0s
    'animation.drift_lantern.walk': loop=True length=2.0 bones=9 keyframes=9 last_key=0.0s
    'animation.drift_lantern.flicker': loop=False length=0.8 bones=1 keyframes=19 last_key=0.8s
    'animation.drift_lantern.attack': loop=False length=0.5 bones=3 keyframes=11 last_key=0.5s
    'animation.drift_lantern.death': loop='hold_on_last_frame' length=1.5 bones=10 keyframes=35 last_key=1.5s
  -> PASS (0 error(s), 0 warning(s))

============================================================
validate_geo: 2/2 file(s) passed — all good
```

### 8.2 Painter-Determinismus — 2× Lauf, md5 identisch

```
$ for i in 1 2; do python3 scripts/geckolib_gen/mobs/sunmote.py \
      && python3 scripts/geckolib_gen/mobs/drift_lantern.py \
      && echo "--- run $i ---" && md5sum <die vier PNGs>; done

--- run 1 ---
e06bd436aeadb631726db2d7eafebade  .../textures/entity/sunmote.png
0bd66dea4a77935154852971f54ff204  .../textures/entity/sunmote_glowmask.png
7e98080299e37302edee810c9dc75345  .../textures/entity/drift_lantern.png
e2580a962a041df96874ca057e29a971  .../textures/entity/drift_lantern_glowmask.png
--- run 2 ---
e06bd436aeadb631726db2d7eafebade  .../textures/entity/sunmote.png
0bd66dea4a77935154852971f54ff204  .../textures/entity/sunmote_glowmask.png
7e98080299e37302edee810c9dc75345  .../textures/entity/drift_lantern.png
e2580a962a041df96874ca057e29a971  .../textures/entity/drift_lantern_glowmask.png
```

### 8.3 `./gradlew compileJava` — grün, echter Vollcompile

Der erste Aufruf meldete `UP-TO-DATE` und wäre damit kein Beweis gewesen, deshalb mit
`--rerun` erzwungen:

```
$ ./gradlew compileJava --rerun --console=plain
…
Note: Some input files use or override a deprecated API.
100 warnings

BUILD SUCCESSFUL in 6s
2 actionable tasks: 1 executed, 1 up-to-date
```

Die 100 Warnungen sind der Bestand (`EventBusSubscriber.Bus` deprecated, quer durch
`veilfx/**` u. a.). Gegenprobe, dass keine davon aus MC3-Dateien kommt:

```
$ ./gradlew compileJava --rerun --console=plain 2>&1 | grep -E "(Sunmote|DriftLantern|DriftTracker|sunmote)"
(keine Ausgabe)
```

### 8.4 Zusätzliche Harnesse (Anhang A) — 0 Probleme

```
########## loop seams / rest poses ##########
sunmote.animation.json: 0 problem(s)
drift_lantern.animation.json: 0 problem(s)

########## channel ownership ##########
  chime/attack/flicker: overlap with base: none    death: covers base: YES   (beide Mobs)

########## coplanar faces ##########
sunmote.geo.json: 11 cubes, 0 coplanar same-facing overlaps
drift_lantern.geo.json: 13 cubes, 0 coplanar same-facing overlaps

########## pendulum ##########
every segment trails the one above it, both axes, both loops: True
```

---

## 9. Ergebnisse

### 9.1 Dateien

| Datei | Status | Inhalt |
|---|---|---|
| `assets/eclipse/geo/entity/sunmote.geo.json` | NEU | 10 Bones / 11 Cubes, 32² |
| `assets/eclipse/animations/entity/sunmote.animation.json` | NEU | 5 Anims (idle/walk/chime/attack/death) |
| `assets/eclipse/textures/entity/sunmote.png` | überschrieben | 32², 226 Texel (neues UV-Layout!) |
| `assets/eclipse/textures/entity/sunmote_glowmask.png` | NEU | 32², 203 Texel — erste Glowmask des Mobs |
| `scripts/geckolib_gen/mobs/sunmote.py` | NEU | Painter, 148 Z. |
| `entity/SunmoteEntity.java` | umgebaut | `EclipseGeoMob`, DriftTracker, Basking, Chime→Flare, Tangenten-Yaw, 24 t Tod |
| `client/entity/sunmote/SunmoteGeoRenderer.java` | NEU | Glowmask + Upright-Death + Fullbright, kein Schatten |
| `client/entity/sunmote/SunmoteRenderers.java` | NEU | eigener Registrar, `EventPriority.LOWEST` + `isBound()`-Guard |
| `client/entity/sunmote/package-info.java` | NEU | Paket-Doku |
| `assets/eclipse/geo/entity/drift_lantern.geo.json` | geändert | 8→11 Bones, 9→13 Cubes (Kette) |
| `assets/eclipse/animations/entity/drift_lantern.animation.json` | geändert | Pendel in idle/walk, `flicker` neu, death auf Kette erweitert |
| `assets/eclipse/textures/entity/drift_lantern{,_glowmask}.png` | neu gemalt | Ketten-Material + Catch-Light |
| `scripts/geckolib_gen/mobs/drift_lantern.py` | geändert | `chain_link()`, `chain_glow()` |
| `entity/ambient/DriftLanternEntity.java` | geändert | DriftTracker, `faceDrift()`, Doku |
| `entity/ambient/DriftTracker.java` | NEU | die geteilte F-9-Antwort, 74 Z. |
| `docs/uv/sunmote.md` | neu geschrieben | beschrieb noch das Handmodell |
| `docs/uv/drift_lantern.md` | geändert | Ketten-Cubes, `glow_flame_core`, statischer Schein |

**Kein Lang-Drop nötig:** `entity.eclipse.sunmote`, `entity.eclipse.drift_lantern` und die
vier `bestiary.eclipse.drift_lantern.*`-Keys existieren bereits in `lang/en_us.json`; MC3
führt keinen neuen Key ein. `docs/plans_v3/langdrop/MC3-AMBIENT.json` entfällt deshalb.

### 9.2 Zahlen

| | Sunmote | Drift Lantern |
|---|---|---|
| Bones / Cubes | 10 / 11 | 11 / 13 |
| Canvas | 32² | 64² |
| bemalte Texel Albedo / Glowmask | 226 / 203 | 720 / 243 |
| Animationen | 5 | 5 |
| Keyframes gesamt | 138 | 83 |
| Todes-Fenster | 24 t = 1.2 s | 30 t = 1.5 s |
| Basis-Loops | idle 4.0 s / walk 3.0 s | idle 2.0 s / walk 2.0 s |

---

## 10. Patch-Snippet für den Integrator (SHARED `EclipseEntityRenderers.java`, G2)

Der neue Registrar hängt auf `EventPriority.LOWEST` und gewinnt deterministisch gegen die
Legacy-Registrierung — verifiziert: `EntityRenderersEvent.RegisterRenderers
.registerEntityRenderer` reicht an `EntityRenderers.register` durch, und das ist ein
`PROVIDERS.put(...)` auf eine `Object2ObjectOpenHashMap` (Last-Write-Wins), während der
NeoForge-Bus die Listener in absteigender Priorität aufruft. **Das Paket funktioniert also
auch ohne dieses Snippet.** Es ist trotzdem fällig, weil die Legacy-Klassen sonst
Leichen bleiben — und weil `sunmote.png` jetzt ein völlig anderes UV-Layout hat: würde
irgendwer den alten Renderer wieder scharf schalten, bekäme er zerlegte Texel.

In `client/entity/EclipseEntityRenderers.java` diese drei Zeilen entfernen:

```java
// Z. 26
public static final ModelLayerLocation SUNMOTE_LAYER = layer("sunmote");
// Z. 44
event.registerLayerDefinition(SUNMOTE_LAYER, SunmoteModel::createBodyLayer);
// Z. 55
event.registerEntityRenderer(EclipseEntities.SUNMOTE.get(), SunmoteRenderer::new);
```

… die dann unbenutzten Importe von `SunmoteModel`/`SunmoteRenderer` mitnehmen und
anschließend löschen:

```
src/main/java/dev/projecteclipse/eclipse/client/entity/SunmoteModel.java
src/main/java/dev/projecteclipse/eclipse/client/entity/SunmoteRenderer.java
```

`SunmoteRenderer` ist der einzige weitere Nutzer von `SUNMOTE_LAYER` (geprüft per `rg`),
danach ist die Referenz sauber weg. Die `EventPriority.LOWEST`-Annotation in
`SunmoteRenderers` ist ab dann redundant, aber harmlos — sie kann stehen bleiben.

---

## 11. Offene Punkte

1. **`runClient`-Sichtprüfung steht aus** (F-14: es gibt keinen Test-Task). Rezept in §12.
   Alles Analytische ist geprüft; ungeprüft bleiben Shader-/Iris-Interaktion und die
   gefühlte Helligkeit der neuen Sunmote-Glowmask bei Nacht.
2. **Statischer Käfig-Schein bei `flicker`** — braucht den Photon-Puls aus §7. Bis dahin
   ist der Gutter an der Flamme sichtbar, nicht am Lichtwurf.
3. **Kranz-Überstand über die Sunmote-Hitbox** (~1.3 px). Bewusst so; falls jemand das
   anders will, ist das eine Änderung an `EclipseEntities` (fremd, G2), nicht am Geo.
4. **`attack` ist bei beiden Mobs totes Sheet-Gewicht.** Registriert und validiert, aber
   nie getriggert (keiner der beiden greift an). Ich habe es drin gelassen, weil das
   P6-Sheet-Schema es vorsieht und ein späterer „Sunmote wehrt sich"-Wunsch sonst wieder
   am Painter vorbei müsste.
5. **`glow_flame_core` hängt an per-Face-UVs** (1.5³ Cube). Wer die Kantenlänge je auf
   einen ganzzahligen Wert ändert, sollte auf Box-UV zurückgehen — die Handpinnung ist
   nur die Ausweichlösung für die halben Texel.

---

## 12. Test-Rezept (Client; auf llvmpipe 20–40 s Ladezeit einplanen)

```
# --- Sunmote ---
# 1) Basis-Loops. walk ist der Normalfall (der Mote umkreist ständig), idle nur im Basking:
/summon eclipse:sunmote ~ ~2 ~
#    → Kranz + Halo drehen GEGENLÄUFIG und ruckeln beim Loop-Ende NICHT (life_time-Rampe).
#    → alle ~13–25 s hält der Orbit 2–5 s an: das ist der idle-Wechsel. Kein Flattern
#      dazwischen — genau dafür ist der 6-Tick-Hold des DriftTrackers da.
# 2) Glowmask (die eigentliche Neuerung): Nacht abwarten bzw. /time set midnight,
#    Mote gegen dunkle Wand halten. Korona/Kern/Kranz brennen, der Halo NICHT — er zeigt
#    nur eine helle Innenkante. Vorher glühte durch den eyes-Pass die ganze Textur gleich.
# 3) chime: ~alle 10 s (Ambient-Intervall 200 t). Der Ton und das Aufblühen müssen
#    GLEICHZEITIG kommen — die Anim hängt an playAmbientSound(), nicht an einem 2. Timer.
# 4) death: /kill @e[type=eclipse:sunmote] → 24 t aufrecht (kein Vanilla-Kipper),
#    Kranz klappt weg, Kern flackert zweimal, dann POOF. Ein Glowstone-Staub fällt.

# --- Drift Lantern (nur Limbo — außerhalb verwirft sie sich selbst) ---
# 5) In den Limbo, an die Bojengasse (x 32..240, z ±6):
/execute in eclipse:limbo run tp @s 120 ~ 0
#    → Die Kette hängt sichtbar in den Nebel aus (oberste Reihen ausgeblendet), die
#      Glieder haben echte Lücken. Beim Gleiten dreht sich die Laterne IN die
#      Fahrtrichtung und die Kette hängt nach hinten aus.
# 6) Pendel prüfen: von der Seite zusehen. Der Ausschlag muss nach unten hin GRÖSSER
#    werden (Kette < Laterne < Tentakel) und jedes Segment dem darüber nachlaufen.
#    Das war der Bug aus §6/Pass 2 — hier sieht man, ob er wirklich weg ist.
# 7) flicker: alle 12–24 s. Vier ungleiche Einbrüche, danach steht die Flamme exakt
#    wieder wie vorher (kein Versatz). Der Käfig-Schein bleibt konstant → §7.
# 8) death: /kill → 30 t, Kette erschlafft, Laterne kippt aus, Flamme guttert, sinkt.
```

---

## Anhang A — die drei Prüf-Harnesse

Ad-hoc-Skripte, bewusst NICHT unter `scripts/geckolib_gen/` abgelegt (das Verzeichnis
enthält die FROZEN-Werkzeuge und gehört mir nicht). Die Methode ist hier vollständig
beschrieben, damit spätere Mob-Wellen sie nachbauen können — sie hat in diesem Paket drei
Bugs gefunden, die beim Lesen des Sheets unsichtbar waren.

**A1 — Koplanaritäts-Prüfer (Geo).** Für jedes Cube-Paar: bei den horizontalen Flächen
sind Ober-/Unterkante direkt vergleichbar, weil eine Bedrock-Cube-Rotation um Y (die
einzige, die beide Modelle benutzen) y-Ebenen und Flächennormalen unberührt lässt — die
Grundrisse sind dann gedrehte Rechtecke und werden per SAT geschnitten. Vertikale Flächen
nur zwischen Cubes gleicher Gierung. Gemeldet wird nur, wenn die Normalen in dieselbe
Richtung zeigen (Gegenrichtung = Back-Face-Culling = harmlos). Gegenprobe an der
Vor-Fix-Geometrie: 16 Treffer, danach 0.

**A2 — Nahtprüfer (Anim).** Tastet jeden Loop-Kanal an t=0 und t=`animation_length` ab und
vergleicht Wert und Steigung (einseitige Differenz mit h=1e-6; größere h erzeugen aus der
Krümmung heraus Falschmeldungen an Extrempunkten). `life_time`-Terme werden vom Nahttest
befreit, aber auf Linearität geprüft, und `life_time` innerhalb eines `sin()`/`cos()` ist
ein harter Fehler. Für `loop: false` wird zusätzlich geprüft, dass Anfang UND Ende auf der
Ruhelage liegen (Rotation/Position 0, Scale 1); bei `hold_on_last_frame` nur der Anfang.
Gegenprobe mit drei absichtlich eingebauten Fehlern (Naht 100·4.0=400, ein `chime`, das
den Halo auf 1.1 stehen lässt, ein `sin(life_time)`): alle drei gemeldet.

**A3 — Kanal-Eigentum + Pendel.** Der Kanal-Test bildet die Bone.Kanal-Mengen von
`base` = idle ∪ walk gegen jede One-Shot-Menge und verlangt: Schnitt leer für die kurzen
One-Shots, Obermenge für `death`. Der Pendel-Test summiert jede Rotationsachse die
Hierarchie hinunter, projiziert die absolute Kurve auf die Grundschwingung des Loops
(Oberschwingungen sind Detail, nicht Schwung) und verlangt, dass Amplitude und Nachlauf
nach unten monoton wachsen — mit Wrap-sicherem Phasenvergleich, sonst meldet ein
Nachlauf von 360° ≡ 0° einen Phantomfehler.
