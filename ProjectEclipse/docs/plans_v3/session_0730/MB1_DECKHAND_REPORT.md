# MB1 — Deckhand (Limbo-Ruderercrew)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-B, Zeile **MB1** —
(a) `rise` massiv verbessern + Planken-Staub-Cue an B2 spec'en,
(b) Gesichts-Glow-Differenzierung im Glowmask-Painter,
(c) `row`-Sync gegen die OarAnimator-/F-003-Fixes verifizieren,
(d) Freiheit zum Gesamt-Polish auf M-A-Niveau.

**Datei-Besitz (exklusiv):** `entity/DeckhandEntity.java`,
`client/entity/DeckhandRenderer.java`, `limbo/OarAnimator.java` (nur gelesen),
`geo/animations/textures deckhand*`, `scripts/geckolib_gen/mobs/deckhand.py`,
`docs/uv/deckhand.md`, dieser Report.

**NICHT angefasst (Leitplanken):** `EclipseGeoMob`/`EclipseGeoMonster`/
`EclipseGeoAnimations`/`EclipseGeoRenderer` (FROZEN), `validate_geo.py`/`paint_lib.py`
(FROZEN), `tools/photon/**`, `assets/eclipse/fx/**`, `veilfx/PhotonMobFx.java`
(alles **B2-Besitz** — hier nur gelesen, die Wünsche stehen als Spec in §7),
`en_us.json`/`de_de.json` (**keine neuen Lang-Keys nötig — kein `langdrop` von MB1**),
`limbo/StartEventCutscene.java` (nur gelesen, für die Tilt-Fensterlänge).
`limbo/OarAnimator.java` gehört zwar MB1, hat aber **null geänderte Zeilen** — §5 ist ein
reiner Verifikations-Auftrag.
`registerControllers` bleibt final (`base` + `action`, kein dritter Controller).

---

## 0. Plan (vor der Implementierung geschrieben)

### 0.1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Quelle | Ist-Stand bei HEAD |
|---|---|
| `geo/entity/deckhand.geo.json` | **16 Bones / 15 Cubes**, Canvas 64². Hood = **ein** aufgeblasener 8×8×8-Würfel über dem Kopf → das Gesicht war komplett zugemauert. Keine emissive Geometrie. |
| `animations/entity/deckhand.animation.json` | 7 Anims: row(3.0 s/49 kf), idle_sag(3.0/12), walk(0.9/28), rise(**1.25**/38), attack(0.6/25), death(1.5/32), tilt(3.0/21) |
| `DeckhandEntity` | `ROW_SYNC_PERIOD_TICKS = 60`; `rise` als `action`-Triggerable; `getBoundingBoxForCulling` = `inflate(2.7, 1.6, 2.7)`; `benchIndex()` gesynct (C3) |
| `DeckhandRenderer` | Oar-Hide auf `!isHostile()`; Port-Spiegel (`oar.rotY`, `oar_blade.rotZ`) mit Restore; Einmal-`forceAnimationReset` pro Rudersession; Splash bei Level-Takt-Phase 1.0 t, Blattspitze hart auf 2.53/0.41 Blöcke |
| `OarAnimator` | P6-W2 entkernt. Übrig: Legacy-`BLOCK_DISPLAY`-Migration, `tiltMode`-Flag, `isPortBench(int)`. **Animiert nichts mehr** — der F-003-Sync hängt ausschließlich am Renderer + der 3.0-s-Cliplänge. |
| `StartEventCutscene` | `TILT_TICK = 0`, `SUBMERGE_TICK = 100` → das Tilt-Fenster ist **~100 t = 1,67 Durchläufe** der 3-s-Schleife, und es wird genau **einmal** betreten. |
| `EclipseGeoMob` (FROZEN) | `base`-Controller `transitionLength = baseTransitionTicks()` = **4 t**; `action`-Controller **`transitionLength = 0`** — ein One-Shot kann grundsätzlich nicht einblenden. |
| `veilfx/PhotonMobFx` (B2) | `deckhand_soul_flame` Loop (Anker Auge + 0.55) + `deckhand_soul_flare` als **Edge-One-Shot** auf der steigenden Flanke von `isHostile()`, 15 t lang. |

### 0.2 Arbeitsplan

1. **Offline-Werkzeugkasten bauen** (nicht committet, `/tmp/mb1`): Vorwärtskinematik-
   Sampler mit Molang-Auswertung + orthografischer Preview-Renderer + Audit
   (Loop-Nähte, catmullrom-Overshoot, Hood-Brim-Freiheit über den Gesichtskarten,
   Modell-Reichweite vs. Culling-Box) + Hand-Over-Snap-Messer. Ohne das ist jede
   Aussage über eine Animation ohne GUI geraten.
2. **(b) Gesicht:** Hood zur offenen Kutte umbauen (sonst gibt es kein Gesicht zu sehen),
   9 emissive Nulltiefe-Karten in die Kutte, Renderer zeigt genau eine pro Bank,
   Painter malt acht unterscheidbare Muster + die Zorn-Brandmarke.
3. **(a) `rise`:** 1.25 s → 1.6 s, echter Beat (Sinken **unter** die Planken → Durchbruch
   → Überkopf-Spitze → zwei Nachschwinger), Ruder verschwindet per Scale-Dissolve statt
   per Ein-Frame-Hide.
4. **(c) `row`-Sync:** Cliplänge, Reset-Pfad, Culling-Box und Spiegel gegen den F-003-Fix
   gegenlesen und **messen**, nicht behaupten.
5. **(d) Polish-Pässe** auf idle_sag/walk/attack/death, dann Selbstkritik, dann `tilt`.
6. Validierung, `docs/uv/deckhand.md`, Report, B2-Spec.

---

## 1. Geänderte Dateien (8 — alle im MB1-Besitz)

| Datei | Δ | Was |
|---|---|---|
| `geo/entity/deckhand.geo.json` | +120/−1 | **+9 Bones / +12 Cubes**: 8 Bank-Gesichtskarten + Zorn-Brandmarke; Hood vom Vollwürfel zur **4-Cube-Kutte** mit Per-Face-UVs |
| `animations/entity/deckhand.animation.json` | +652/−150 | `rise` neu (1.25→1.6 s), `tilt` neu, idle_sag/walk/attack/death/row verdichtet — **205 → 613 Keyframe-Einträge** |
| `entity/DeckhandEntity.java` | +38/−8 | `ANIM_RISE` public, `getBoneResetTime()`-Override (3.0 t), Culling-Box 2.7/1.6 → **3.0/1.8** (gemessen) |
| `client/entity/DeckhandRenderer.java` | +116/−12 | `withGlowmask()`, Gesichtskarten-Auswahl, Oar-Hide/Spiegel auf das neue `oarShown`-Gate, Splash-Blattspitze neu gemessen (inkl. **Vorzeichenfehler**) |
| `scripts/geckolib_gen/mobs/deckhand.py` | +124/−14 | 9 emissive Karten-Materialien, Kutten-Schattenverlauf, Doku |
| `textures/entity/deckhand.png` | bin | **regeneriert** (nur Painter, kein Handedit) |
| `textures/entity/deckhand_glowmask.png` | bin | **regeneriert** — von 0 auf **41 emissive Texel** |
| `docs/uv/deckhand.md` | +48/−17 | Bone/Cube-Zählung, Kutten- und Karten-Rects, Emissiv-Abschnitt, Brim-Gesetz |

**`limbo/OarAnimator.java` wurde NICHT angefasst.** §5 ist ein Verifikations-Auftrag; die
Klasse animiert seit P6-W2 nichts mehr, und jede Zeile dort wäre eine Regressionsfläche
für genau den Bug, den ich absichern soll.

Geo gesamt: **16 Bones / 15 Cubes → 25 / 27**, Canvas unverändert 64².

---

## 2. (b) Gesichts-Glow-Differenzierung

### 2.1 Das eigentliche Problem war nicht die Textur, sondern die Kapuze

Der v1-Hood war **ein** Cube `8×8×8 inflate 0.25` auf demselben Pivot wie der Kopf — also
eine massive Haube, die den Kopf allseitig 0.25 px überragt. Es gab schlicht keine Fläche,
auf der ein Gesicht hätte leuchten können; jedes emissive Texel auf dem `head` wäre vom
Hood-Cube verdeckt worden. Ein Painter-only-Ansatz (Auftrag wörtlich: „im Glowmask-Painter")
war damit physisch unmöglich, ohne die Geo anzufassen.

Der Hood ist deshalb jetzt eine **offene Kutte aus 4 Cubes**:

| Cube | Box | Rolle |
|---|---|---|
| Krone | 8.5 × 2.5 × 8.5 auf y 23.75 | Deckel, bildet die Brim-Kante |
| Rückwand | 8.5 × 6 × 1.25 auf z 3 | Hinterkopf |
| Seitenwand ×2 | 1.25 × 6 × 7.25 auf x ∓4.25 | Wangenblenden, lassen den Nordausschnitt frei |

Der Nordausschnitt (y 17.75–23.75, |x| ≤ 3) ist damit offen, und der `head`-Cube dahinter
ist reine Schwarzvoid — der Painter legt in diesem Streifen zusätzlich einen Top-Down-
Verlauf an (`head_shadow`, direkt unter der Brim am dunkelsten), damit die Karte nicht auf
flachem Schwarz klebt.

### 2.2 Neun Karten, eine sichtbar

| Bone | Pivot | Cube | UV | Zweck |
|---|---|---|---|---|
| `glow_face_0..7` | `0,20.5,−4.25` | 6×4×**0** | (0,27)…(18,31), je 6×4 | eine Karte pro Bank |
| `glow_face_wrath` | `0,20.5,−4.45` | 6×4×**0** | (32,49) | Brandmarke der erhobenen Crew |

Nulltiefe-Karten (`size z = 0`) statt Texel auf dem `head`-Cube: so ist die Sichtbarkeit
pro Rudererin **ein Bone-Flag**, kein Textur-Swap — GeckoLib kennt keine Per-Entity-Textur
auf einem geteilten `DefaultedEntityGeoModel`. Die Zorn-Karte liegt **0.2 px vor** den
Bank-Karten; das ist bewusst mehr als Z-Fighting-Toleranz und weniger als ein Texel.

`DeckhandRenderer.applyFace` blendet pro Frame pro Rudererin acht Karten aus und eine ein:

```java
private static int faceVariant(DeckhandEntity entity) {
    int bench = entity.benchIndex();
    if (bench >= 0) {
        return bench % FACE_VARIANTS;
    }
    return Math.floorMod(entity.getUUID().hashCode(), FACE_VARIANTS);
}
```

Der **gesyncte Bank-Index** ist der Treiber, nicht `entity.getId()`: er liegt im NBT, also
zeigt Bank 3 nach jedem Reload dasselbe Gesicht, und Client wie Server sind sich einig.
Pre-P6-Streuner ohne Bank (`−1`) fallen auf einen UUID-Hash zurück statt auf eine gemeinsame
Default-Karte — zwei Streuner bleiben unterscheidbar.

Das Modell (und damit die Bone-Flags) ist von **allen acht** Ruderern geteilt. Deshalb läuft
das in `preRender` direkt vor dem Draw dieser einen Entity, exakt wie der Oar-Toggle und wie
`FerrymanGeoRenderer` es für `glow_gaze` macht. `preRender` steigt bei `isReRender` sofort
aus, die Flags überleben also unverändert in den `AutoGlowingGeoLayer`-Pass — die emissive
Kopie zeigt dieselbe eine Karte.

### 2.3 Die acht Muster (Painter, `FACE_CARDS`)

Designregel: die Paare unterscheiden sich in **Anzahl, Höhe und Symmetrie**, nicht nur im
Farbton. Über das Deck hinweg liest man die Leuchtmasse, aus der Nähe das Muster.

| Bank | Name | Muster | Farbe |
|---|---|---|---|
| 0 | even pair | zwei ruhige Augen | `#6FD8E8` |
| 1 | wide burn | doppelt breite Höhlen + Halo | `#8FE8C8` |
| 2 | half-lit | ein Auge ersoffen, eine Träne die Wange runter | `#66CCFF` |
| 3 | narrow-set | Paar über der Nasenwurzel gekniffen + Kinnstriche | `#9FD8A8` |
| 4 | crooked | Höhlen auf verschiedener Höhe, eine Lampe hängt | `#7FC0E8` |
| 5 | off-centre | beide Lichter nach Backbord verschoben + Kieferglut | `#B8E4E0` |
| 6 | four marks | Augen plus gebranntes Paar auf den Wangenknochen | `#5FA8C8` |
| 7 | guttering | dunkles breites Paar mit Halo — die älteste Hand an Bord | `#C8E8A0` |

Palette bleibt innerhalb der FX-Crewfarben (`tools/photon/backlog_fx.py`: SOUL_BLUE
`#66CCFF`, Flare-Kern SAC_HOT `#F6EFFF`), damit die Karten zur Photon-Seelenflamme über der
Kapuze passen.

**Zeile 0 der Zorn-Karte ist absichtlich leer.** Jede Bank-Karte hat ihre Höhlen genau auf
dieser Zeile (das ist die Regel, nach der die acht Muster gebaut sind), also zeigt auch eine
erhobene Rudererin weiter **ihre eigenen** Lampen. Die Zeilen 1–3 sind der Überlauf: das
Licht quillt seitlich aus den Höhlen, läuft zwei Texel die Wangen runter und tropft vom Kinn.
Die Crew wird zornig, sie wird nicht identisch.

### 2.4 Das Brim-Gesetz (gemessen, nicht geschätzt)

Erster Wurf: Kartenoberkante auf y 23.5 (klassische Augenhöhe). Der Vorwärtskinematik-Audit
zeigte, dass die Brim über den Augenspalten in `death` bis y 22.97 und in `attack` bis 23.05
sinkt — die Brim schnitt die innere Hälfte jeder Höhle ab, die Augen rendern als
**L-förmige Haken**. Karten deshalb auf y 18.5–22.5 heruntergezogen. Ist-Stand über den
gesamten Clipsatz (Freiraum zwischen Kartenoberkante und tiefster Brim-Ecke über |x| ≤ 3):

| Clip | tiefste Brim y | Freiraum |
|---|---|---|
| walk | 23.61 | **+1.11** |
| rise | 23.47 | +0.97 |
| tilt | 23.40 | +0.90 |
| row | 23.16 | +0.66 |
| idle_sag | 23.14 | +0.64 |
| attack | 23.05 | +0.55 |
| death | 22.97 | **+0.47** |

Das Gesetz steht jetzt in `docs/uv/deckhand.md`: **jeder neue oder geänderte Clip muss die
Brim über y 22.75 halten.** Es hat im dritten Polish-Pass sofort zugebissen (§6.3).

---

## 3. (a) `rise` — 1.25 s / 38 kf → 1.6 s / 145 kf

### 3.1 Was vorher fehlte

Der alte Clip war ein Aufstehen aus dem Sitzen. Die Fiktion ist aber „der Ruderer **steigt
aus den Planken**" — es fehlte das Wichtigste: er muss erst einmal **verschwinden**. Dazu
schnitt der Renderer das Ruder auf Frame 1 hart weg (§3.3).

### 3.2 Der neue Beat (16 t-Raster, gemessen an der ausgelieferten Geo)

| Zeit | Tick | Phase | Messwert |
|---|---|---|---|
| 0.00–0.05 s | 0–1 | Ansatz: Torso kippt, Ruder beginnt zu schrumpfen | Robensaum durchstößt die Deckebene bei **t = 0.05 s** |
| 0.05–0.48 s | 1–10 | **Sinken** unter die Planken | tiefster Körperpunkt **−12.48 px = −0.78 Blöcke** bei t = 0.48 s |
| 0.34 s | 7 | Ruder ist auf Scale 0.01 aufgelöst | `oar.scale` 1 → 0.97 → 0.74 → 0.40 → 0.12 → 0.01 |
| 0.48–0.83 s | 10–17 | Auftauchen | Saum durchstößt die Deckebene aufwärts bei **t = 0.83 s** |
| 0.83–1.02 s | 17–20 | **Durchbruch**: Arme über Kopf, Torso überstreckt | `arm_right` Spitze **98.7°** bei t = 0.95 s, `root.y` +2.6 px, `torso` +19° |
| 1.02–1.32 s | 20–26 | erster Nachschwinger | Saum streift die Planken (−1.73 px bei t = 1.20 s) |
| 1.32–1.60 s | 26–32 | zweiter, kleinerer Nachschwinger → Standpose | Endpose = `idle_sag`-Mittelwert (§3.4) |

Die Tatter- und Lantern-Kanäle laufen dem Körper phasenversetzt nach (Lantern-Spitze
t = 1.04 s, 0.09 s **nach** der Armspitze), die Kapuze macht ihren eigenen zweiten Schlag bei
t = 1.06 s. Kein Kanal teilt sich einen Extremwert-Zeitpunkt mit dem Root — das ist der
Unterschied zwischen „animiert" und „alles zappelt im Takt".

### 3.3 Der Ruder-Pop — und warum die Lösung im Bone-Reset liegt

`DeckhandEntity.riseHostile` setzt `HOSTILE` **auf demselben Tick**, auf dem es `rise`
triggert. Der Renderer versteckte das Ruder auf `isHostile()`. Ergebnis: ein
zwei Blöcke langes Ruder verschwand in einem einzigen Frame, exakt in dem Moment, in dem der
Blick des Spielers ohnehin auf dem Ruderer lag.

Erster Versuch: Ruder-Rotation im `rise` mit ausanimieren. Gemessen war das schlimmer — der
`action`-Controller hat `transitionLength = 0` (FROZEN), also gab es beim Eintritt einen
Ein-Frame-Sprung von bis zu **24° am `oar`** und **80° am `oar_blade`** (Worst-Case über die
freilaufende `row`-Phase, `handoff.py`).

Die ausgelieferte Lösung arbeitet **mit** dem Nulltransition statt dagegen:

* `rise` animiert am Ruder **ausschließlich die Scale** (1 → 0.01 über 0.14–0.34 s). Ein
  Kanal, der in beiden Clips fehlt, kann keinen Sprung machen.
* Rotation und Position des Ruders fallen aus der `row`-Kurve heraus und laufen über
  GeckoLibs Bone-Reset-Rampe aus. Deren Default ist **1 t = ein Frame** — also genau der
  Snap. `DeckhandEntity.getBoneResetTime()` gibt jetzt **3.0** zurück: aus dem 24°-Flick
  wird eine 3-t-Rampe, und während dieser Rampe ist das Ruder bereits auf ~55 % geschrumpft.
* Der Renderer hält das Ruder sichtbar, **solange der `rise`-One-Shot läuft** — nicht mehr
  auf `!isHostile()`:

```java
this.oarShown = !entity.isHostile() || isPlaying(entity, EclipseGeoAnimations.CONTROLLER_ACTION,
        EclipseGeoAnimations.animId("deckhand", DeckhandEntity.ANIM_RISE));
```

`isPlaying` prüft zuerst `hasAnimationFinished()` und erst dann `getCurrentAnimation()` —
im dekompilierten `AnimationController` (4.9.2) ist `hasAnimationFinished()` genau
`currentRawAnimation != null && animationState == STOPPED`, und `currentAnimation` bleibt
nach dem Stop stehen. Ohne die Reihenfolge wäre das Ruder für immer sichtbar geblieben.

`getBoneResetTime()` ist gefahrlos, weil **jeder andere Bone** in beiden Clips (aus- wie
eingehend) bespielt ist: die Rampe greift ausschließlich für das Ruder. Nachgeprüft über die
Bone-Abdeckungsmatrix aller sieben Clips.

### 3.4 Ein- und Ausstieg gemessen statt gefühlt

| Kante | Worst-Case-Snap | Bemerkung |
|---|---|---|
| `row` → `rise` (Arme) | `arm_right` t=0 = **49°**, `row`-Bereich 37–63° | mitten im Band, ~0–13° Snap |
| `rise` → `idle_sag` | Lantern 17°, `hood_point` 12°, Tatter je 8° | Arme **0.3°**: `rise` endet auf 10.0/10.0, `idle_sag`-Mittel ist **10.26/10.26** |
| `rise` → `row` | Arme 53–54° | **existiert nicht** — nach `rise` ist die Crew hostile, der `base`-Controller kann `row` gar nicht wählen |

Die Endpose des `rise` ist also nicht „irgendwo aus", sondern auf den gemessenen Mittelwert
der Folge-Loop gelegt. Das ist der einzige Hebel, den man gegen ein `transitionLength = 0`
in einer FROZEN-Basis überhaupt hat.

---

## 4. (d) Die übrigen Clips

| Clip | kf vorher → nachher | Bones | Was dazukam |
|---|---|---|---|
| `row` | 49 → **114** | 11 → 14 | Zug in Antrieb/Ausheben/Rückholen/Blatt-Quadrieren zerlegt, Blattfeder (`oar_blade` 0→79°) als eigener Kanal, Kopf-/Kutten-/Lantern-Garnitur |
| `idle_sag` | 12 → **70** | 10 → 12 | war eine reine Molang-Wolke; jetzt ein Atembeat mit einem gelegentlichen Zucken bei t = 2.1 s (die Crew ist tot, nicht schlafend) |
| `walk` | 28 → **50** | 11 → 12 | zwei Schritte pro 0.9-s-Zyklus (`root.y`-Gipfel 0.225 s / 0.675 s), `root`-Roll ±4.5° in das jeweilige Standbein, kontralateraler Armschwung, Kopfrolle gegen den Schritt. Der Mob hat **keine Beine** (Robenbasis) — der Gang muss vollständig aus Heave + Roll gelesen werden |
| `attack` | 25 → **60** | 6 → 10 | Antizipation → Schlag → Rückholen mit zwei Nachschwingern; Kutte/Kapuze/Lantern mitbespielt |
| `death` | 32 → **64** | 11 | Robe kollabiert über `scale` (1.0 → 1.15/0.45/1.15 — Stoff sackt breiter, nicht kleiner), Lantern fällt vor, Kopf rollt weg |
| `tilt` | 21 → **110** | 12 → 14 | dritter Polish-Pass, §6.3 |

Bespielte Bones je Clip stehen jetzt bei 10–14 von 16 animierbaren. Unbespielt bleiben nur
`oar_loom`/`oar_shaft` (starre Segmente **im** `oar`-Bone, die sich definitionsgemäß mit ihm
bewegen) und die neun Gesichtskarten (starre Karten am `head` — ihre „Animation" ist die
Sichtbarkeitswahl, §2.2).

**Molang-Frequenzgesetz.** `math.sin` rechnet in Grad, `query.anim_time` in Sekunden — eine
schließende Frequenz auf einer L-Sekunden-Loop ist `360·n / L`. Alle verwendeten Frequenzen
sind Vielfache von `360/L`: 120/240/600/720 auf den 3-s-Loops, **400/800** auf der 0.9-s-
`walk`-Loop. Damit schließen alle Sinus an der Naht, unabhängig davon, ob GeckoLib
`anim_time` loop-relativ oder freilaufend füttert — das ist der Grund für die Regel, nicht
Kosmetik. (Gegenprobe: die Wertnähte in §8.4 sind exakt 0, obwohl mehrere Kanäle **rein**
aus Molang bestehen.)

---

## 5. (c) `row`-Sync + F-003 — Verifikation

> **Auftrag war Verifizieren, nicht Ändern.** `OarAnimator.java`: 0 Zeilen geändert.
> Die drei F-003-Symptome (3-s-Ruck, Ruder-Culling, Spiegel-Flackern) werden einzeln
> gegengelesen.

### 5.1 Der 3-s-Ruck (GeckoLib-Reset-Loop)

Die Kette, die halten muss:

| Glied | Ist-Wert | Beleg |
|---|---|---|
| `animation.deckhand.row` Länge | **3.0 s** | `validate_geo`-Ausgabe §8.1: `length=3.0 last_key=3.0s` |
| `ROW_SYNC_PERIOD_TICKS` | **60** | `DeckhandEntity:104` |
| 3.0 s × 20 t/s | **60 t** ✔ | die Loop schließt exakt auf dem Sync-Raster |
| Reset-Häufigkeit | **einmal pro Rudersession** | Gate `clientRowResetAt == Long.MIN_VALUE && gameTime % 60 == 0` |
| Marke-Löschbedingung | `isHostile() \|\| !isAlive() \|\| isTilt()` | **semantisch identisch zu HEAD** (dort `!rowing` mit `rowing = !isHostile()`) |

Der letzte Punkt ist die eigentliche Regressionsfalle dieser Welle und ich habe sie bewusst
umschifft: ich habe ein zweites Sichtbarkeits-Flag `oarShown` eingeführt, das **weiter**
ist als `!isHostile()` (es umfasst den laufenden `rise`). Hätte ich die Löschbedingung auf
`!oarShown` umgeschrieben — die naheliegende Vereinfachung —, dann würde die Sync-Marke
während des `rise` **nicht** gelöscht, und eine Crew, die später wieder ruhig wird, käme mit
einer veralteten Marke in die `row`-Loop zurück und würde sich nie wieder auf das Raster
legen. Die Löschbedingung liest deshalb explizit `entity.isHostile()`.

Ebenfalls unverändert: `SPLASH_PHASE_TICKS = 1.0`. Die `row`-Loop verankert sich 4 t nach der
Rasterkante (`AnimationController.process` setzt `shouldResetTick` beim
TRANSITIONING→RUNNING-Flip erneut), der authorierte Catch-Beat bei 2.8–3.0 s liegt damit auf
Level-Takt-Phase 0–4, und Phase 1.0 entspricht **Anim-Tick 57 = 2.85 s**. Das ist genau die
Stelle, an der ich die Blattspitze gemessen habe (§5.2).

Die authorierte Zug-Zerlegung, damit die Zahl 2.85 s nachvollziehbar ist:

| Zeit | Phase |
|---|---|
| 0.00–1.10 s | Antrieb (Blatt im Wasser, `oar.y` +14° → −12°, Torso lehnt auf +12.6° zurück) |
| 1.15–1.32 s | Ausheben, Blatt federt auf 79° (flach) |
| 1.32–2.60 s | Rückholen gefedert (`oar.y` −14° → +14°) |
| 2.62–2.82 s | Blatt quadriert (79° → 0°) |
| **2.80–3.00 s** | **Catch** — `oar.x` 18° → −12°, das Blatt taucht ein |

### 5.2 Ruder-Culling — die alte Box war 0.15 Blöcke zu klein

`getBoundingBoxForCulling` stand auf `inflate(2.7, 1.6, 2.7)`, hergeleitet aus dem **Pivot**
von `oar_blade` (`z = −40` = 2.5 Blöcke). Der Blatt-**Cube** läuft aber bis `z = −52`, und
`row` federt ihn zusätzlich aus. Gemessen über jede Bone-Ecke jedes Clips (`audit.py reach`):

```
ALL        x[  -13.25    13.52] y[  -19.32    40.67] z[  -51.20     9.17]
-> inflate needed (blocks): x/z 2.850, y-down 1.207, y-up 0.942
```

2.850 > 2.7 — die äußerste Blattspitze lag **außerhalb** der LIMBOFIX2-Polsterung und ist
weiter gepoppt. Neu: `inflate(3.0, 1.8, 3.0)`, mit Luft nach oben, damit der nächste
Polish-Pass die Box nicht wieder überholt. Der y-up-Bedarf von 0.942 kommt aus `tilt`
(Ruder himmelwärts geschifft), der y-down-Bedarf von 1.207 aus dem `row`-Catch.

### 5.3 Spiegel-Flackern

Die Negier-und-Restore-Mechanik in `renderRecursively` ist unverändert (sie ist der
LIMBOFIX2-Fix gegen den `handleAnimations`-Early-Return auf nicht fortgeschrittener
Frame-Zeit). Geändert ist nur das **Gate**: `!animatable.isHostile()` → `this.oarShown`.

Das ist notwendig, kein Kosmetikwunsch: während des `rise` ist `isHostile()` bereits wahr,
das Ruder aber noch da. Mit dem alten Gate hätte ein Backbord-Ruder in dem Moment, in dem die
Flanke kippt, seinen Schwenk quer über den Rumpf gerissen — direkt vor der Auflösung. Da
`oarShown ⊇ !isHostile()`, ist der Spiegel jetzt exakt dann aktiv, wenn das Ruder auch
gezeichnet wird: kein Frame mit sichtbarem, ungespiegeltem Ruder existiert.

`oarShown` wird in `preRender` gesetzt und in `renderRecursively` gelesen. Das ist derselbe
Vertrag, auf dem die geteilten Bone-Sichtbarkeitsflags ohnehin schon stehen (ein
Renderer zeichnet zu einem Zeitpunkt genau eine Entity), und `preRender` steigt bei
`isReRender` aus, so dass der Glowmask-Pass denselben Wert sieht.

Nebenbefund, geprüft und **kein** Bug: `tilt` hält `oar_blade.rotZ` auf 85°, was der Spiegel
für Backbord auf −85° dreht. Ein flaches, zur Ebene symmetrisches Blatt sieht bei ±85°
Rollwinkel gleich aus — die geschifften Ruder lesen auf beiden Bordseiten identisch.

### 5.4 Splash-Position — ein gefundener Vorzeichenfehler

`TIP_OUT_BLOCKS`/`TIP_ALONG_BLOCKS` beschrieben mit 2.53/0.41 den Blatt-**Pivot** in der
**Ruhepose**, nicht die Spitze im Catch. Gemessen an der posierten Skelettkette im
Splash-Frame (Anim 2.85 s), Mittelpunkt der außenbords liegenden Blattfläche:

| | Steuerbord | Backbord (gespiegelt) |
|---|---|---|
| Modell-Position | `(−9.07, −8.78, −46.20)` px | `(+9.07, −8.78, −46.20)` px |
| außenbords (Modell −Z) | **2.887 Blöcke** | 2.887 Blöcke |
| längs Rumpf (Modell +X) | **−0.567 Blöcke** | +0.567 Blöcke |

Zwei Fehler in einem: der Betrag war 0.35 Blöcke zu klein **und das Längsglied hatte das
falsche Vorzeichen** — der Splash lag damit 1.13 Blöcke rumpfaufwärts, also unter der Bank
der Nachbarin. Neu: `TIP_OUT_BLOCKS = 2.89`, `TIP_ALONG_BLOCKS = −0.57` (der Renderer negiert
es für Backbord, was mit der gemessenen Spiegelung übereinstimmt).

### 5.5 `OarAnimator` — was der Sync heute wirklich braucht

Gegengelesen: die Klasse hat **keine** Animationsrolle mehr. `isPortBench(int)` ist ihr
einziger Beitrag zum Rendern, und der Renderer leitet die Spiegelentscheidung daraus ab —
aus der **Sitzzuweisung**, nicht aus `yBodyRot`. Damit ist die Spiegelung
konstruktionsbedingt immun gegen jede Rotationsquelle (der ursprüngliche Flacker-Pfad).
`beginTilt`/`endTilt` schalten nur ein statisches Flag, das `DeckhandEntity.tick` in seinen
gesyncten `TILT`-Zustand spiegelt.

---

## 6. Selbstkritik-Pässe

### 6.1 Pass 1 — „was ist noch billig?"

1. **Die Kapuze klemmte die Augen ab** (§2.4) → Karten auf y 18.5–22.5, Brim-Gesetz in die
   UV-Doku.
2. **Der `rise`-Eintritt riss das Ruder** um bis zu 24°/80° → Rotationskanäle aus dem Clip
   entfernt, `getBoneResetTime()` auf 3.0 (§3.3).
3. **Die Culling-Box war zu klein** (2.850 nötig vs. 2.7 vorhanden) → 3.0/1.8 (§5.2).
4. **`idle_sag` war eine Molang-Wolke** ohne einen einzigen Beat → Zucken bei t = 2.1 s.

### 6.2 Pass 2 — Konvention und Fehlsignale

5. **Der Splash saß falsch** → §5.4 (Betrag **und** Vorzeichen).
6. **`death`/`attack` standen ohne Reserve auf dem Brim-Limit** — gemessen am
   zurückgerechneten Vor-Stand: `attack` **22.751** (Freiraum +0.25, also exakt auf der
   22.75-Grenze) und `death` **22.793** (+0.29). Bei dieser Reserve entscheidet jede
   künftige Kapuzen-Änderung über abgeschnittene Augen. `hood`/`hood_point` in beiden Clips
   nachgezogen → jetzt **23.05** (+0.55) und **22.97** (+0.47).
7. **Vorschaufehler im eigenen Werkzeug:** der Yaw-Kamerapfad meines Preview-Renderers
   berechnete den Up-Vektor falsch, die Konturblätter waren vertikal gespiegelt. Behoben,
   bevor daraus eine Design-Entscheidung wurde. (Werkzeug liegt in `/tmp`, nicht committet.)
8. **Rotations-Konventions-Alarm** — untersucht und **entwarnt**, Herleitung in §9.1.

### 6.3 Pass 3 — der Clip, den niemand poliert hatte

`tilt` war mit 21 Keyframes auf 12 Bones der letzte Clip auf v1-Niveau: eine statische
Bremspose mit ein bisschen Sinus. Für ein Cutscene-Fenster von 100 t (§0.1) ist das die
sichtbarste Stelle des ganzen Mobs — der Spieler hat in diesem Moment nichts anderes zu tun,
als die Crew anzusehen.

Neu: **110 Keyframes auf 14 Bones**, gebaut um **einen** Rumpfstoß pro 3-s-Zyklus:

| Zeit | Was |
|---|---|
| 0.00–0.95 s | das Schiff reitet hoch (`root.y` +0.15 → +0.44 px), Torso lehnt sich tiefer in die Krängung (−14° → −16.4°) |
| **1.12–1.18 s** | **das Deck fällt weg**: `root.y` −0.9 px, Torso schnappt auf −5.5° nach vorn, Greifarm reißt auf 26°, freier Arm flart auf Z +20° |
| 1.28–1.45 s | Nachbeben (`root.y` −0.42 → −0.66 px), Torso überschwingt auf −18.2° |
| 1.45–2.10 s | Ausschwingen |
| 2.10–3.00 s | zurück in die Haltepose (Naht-Wert exakt 0.000000) |

Die Laterne ist dabei die eigentliche Arbeit: sie hängt am Gürtel und bekommt eine gedämpfte
Pendel-Kette mit 12 Keyframes (−24° → −4° → −38° → −14° → −31° → −19° → −27° → −24°), also
ein echtes Ausschwingen und kein Sinus. Neu bespielt: `robe` (Stoff bleibt beim Sturz kurz
stehen), `head` (**nur Z-Rolle**, siehe §9.2), `belt` (Z-Mikro statt totem Konstantwert).

Beim ersten Wurf riss der Kapuzen-Schlag die Brim auf **+0.26** Freiraum herunter — das
Brim-Gesetz aus §2.4 hat sofort zugebissen. Ursache war ein Vorzeichenirrtum meinerseits:
ich hatte angenommen, negatives `hood.rotX` hebe die Brim. Der Audit zeigt das Gegenteil
(`death` hat sein Minimum bei `hood ≈ −0.8°`, nicht bei seinem Maximum von +12°). Nach dem
Umdrehen des Schlags — physikalisch ohnehin richtiger, loser Stoff bleibt beim Wegsacken des
Kopfes zurück, die Brim kippt also **hoch** — steht `tilt` bei **+0.90**.

---

## 7. Spec an B2 — Planken-Staub und die Flare-Taktung

> **Koordinations-Snippet. MB1 hat hier NICHTS angefasst.** `tools/photon/backlog_fx.py`,
> `assets/eclipse/fx/**` und `veilfx/PhotonMobFx.java` sind B2-Besitz. Alle Zahlen sind
> aus der ausgelieferten Geo/Anim gelesen bzw. per Vorwärtskinematik gemessen.

### 7.1 Der Befund: `deckhand_soul_flare` feuert heute auf dem falschen Beat

`PhotonMobFx` feuert `deckhand_soul_flare` (15 t) auf der **steigenden Flanke von
`isHostile()`**, verankert auf `Auge + 0.55`. `DeckhandEntity` setzt diese Flanke auf
demselben Tick, auf dem `rise` startet. Das war vor MB1 vertretbar (der alte `rise` blieb
oben). Der neue `rise` **sinkt in die Planken**, und der Anker ist an der **Entity-Position**
festgemacht, nicht am Bone — die Entity bewegt sich während des Clips nicht, das Modell aber
um bis zu 0.78 Blöcke nach unten.

Gemessen (Anker liegt fest auf y = 1.85 Blöcke: `eyeHeight` 1.3 + Offset 0.55):

| Anim-Tick | Kapuzenkrone (Blöcke) | Flare-Anker steht darüber |
|---|---|---|
| 0 | 1.716 | +0.13 |
| 4 | 1.403 | +0.45 |
| 8 | 0.906 | +0.94 |
| **10** | **0.854** | **+1.00** ← Flare brennt einen ganzen Block über einem Ruderer, der unter Deck ist |
| 14 | 1.230 | +0.62 |
| **15** | — | **Flare ist zu Ende** |
| 18 | 1.962 | −0.11 |
| **19** | **1.979** | ← das ist der Beat, auf den die Flare gehört (Arme auf 98.7°) |

Kurz: die Flare ist vollständig **abgebrannt, vier Ticks bevor** die Rudererin oben ist, und
verbringt ihre mittleren 10 Ticks als freischwebende Flamme über leerem Deck. Dasselbe gilt
für die `deckhand_soul_flame`-Dauerschleife: sie bleibt in der Luft stehen, während das
Modell darunter wegsackt.

### 7.2 Wunsch 1 — Flare um 18 t verzögern (oder in zwei Beats teilen)

| Beat | Anim-Tick | Anker (Auge + …) | Wunsch |
|---|---|---|---|
| Zündung | 0–2 | +0.55 | winziger Wink, 3–4 t, `SAC_HOT` → sofort weg. „Etwas hat sich entschieden." |
| **Hauptflare** | **18** | +0.55 | die heutige 15-t-Kegelflare, unverändert, nur verzögert |
| Loop-Pause | 2–16 | — | `deckhand_soul_flame` idealerweise stumm/ausgeblendet, solange das Modell unter Deck ist |

Aus MB1-Sicht ist die Verzögerung die Priorität; die Zündung ist Kür. Wenn der
Edge-Lane-Mechanismus keinen Delay kennt, ist die saubere Variante ein `FxCues`-Cue, den MB1
in `riseHostile` selbst sendet, sobald B2 die Konstante angelegt hat — einzeilig und in
MB1-Datei:

```java
// in DeckhandEntity.riseHostile(), direkt nach deckhand.triggerAction(ANIM_RISE):
FxPayloads.sendFxEntityEvent(limbo, FxCues.CUE_DECKHAND_RISE, deckhand, 0.0F, 0.0F, 48.0D);
```

Ein Asset-interner 18-t-Burst-Delay ist B2 gegenüber der Wire-Variante vorzuziehen — der
Cue kostet ein Paket pro Rudererin (8 Stück in einem Tick), der Delay kostet nichts.

### 7.3 Wunsch 2 — `deckhand_plank_dust` (der eigentliche Auftrag)

Ein One-Shot, zwei Bursts, verankert auf der **Deckebene**, nicht am Auge.

| Größe | Wert | Herkunft |
|---|---|---|
| Anker | `(0, −1.30, 0)` vom Auge = Entity-Fußebene y 0 | `eyeHeight` 1.3, Hitbox 0.7 × 1.6 |
| Ringradius | **0.28 Blöcke** (Robe ist 8 px = 0.5 Blöcke breit, Halbbreite 0.25 + Saum) | `robe`-Cube 8×8×6 |
| Burst A („er geht runter") | **Anim-Tick 1** | Saum durchstößt die Deckebene abwärts bei t = 0.05 s |
| Tiefpunkt | Anim-Tick 10, −0.78 Blöcke | tiefster Körperpunkt −12.48 px |
| **Burst B („er kommt hoch")** | **Anim-Tick 17** | Saum durchstößt die Deckebene aufwärts bei t = 0.83 s |
| Nachwischer | Anim-Ticks 22–26 | Saum streift die Planken noch zweimal (−1.73 px bei t = 1.20 s) |
| Gesamtfenster | 32 t | `rise` ist 1.6 s |
| Wiederholrate | einmal pro Weltdurchlauf | `riseHostile` feuert am Phasenbruch, für alle 8 gleichzeitig |

Asset-Wünsche:

| Emitter | Shape | Timing | Bewegung |
|---|---|---|---|
| `plank_suck` | `circle(radius=0.28, thickness=0.08)`, flach | Burst auf Tick 1, 6–8 Partikel, Lifetime 10–16 t | **nach innen/unten** ziehend (`start_speed` 0.05–0.12, `velocity_over_lifetime.linear.y` −0.03) — das Deck saugt, es stäubt nicht |
| `plank_burst` | `circle(radius=0.30, thickness=0.10)` | Burst auf **Tick 17**, 14–18 Partikel, Lifetime 18–26 t | radial nach außen auf r ≈ 0.9 in 20 t, Schwerkraft an, harter `SEG_DECAY_TAIL` |
| `plank_splinters` | `cone(angle=20, radius=0.2)` nach oben | Burst auf Tick 17, 4–6 Partikel, Lifetime 20–30 t | schwerer, fällt zurück — Holzsplitter, kein Staub |

Farbe: das ist **nasses, altes Schiffsholz**, kein Sand. Direkt aus dem Painter-Treiber, damit
der Staub zur Textur passt: Kern `OAR_WOOD #5A452E` → Saum `KELP_EDGE #22301F` → aus.
**Kein** `SOUL_BLUE`-Anteil — die Seelenfarbe gehört der Flare über der Kapuze, und wenn der
Staub mitleuchtet, verliert der Durchbruch seinen Kontrast. Ein `random_gradient` ist
erwünscht: acht Ruderer, die gleichzeitig durchbrechen, dürfen nicht denselben Puff werfen.

`AUTO_ROTATE_NONE` genügt — der Ring ist rotationssymmetrisch, und die Ruderer sitzen
paarweise gegenüber, ein blickrichtungsabhängiges Asset würde die beiden Bordseiten
gegeneinander ausrichten.

### 7.4 Anker-Tabelle Deckhand (16 px = 1 Block, `eyeHeight` 1.3, Hitbox 0.7 × 1.6)

| Anker | Geo | Blöcke (Entity-lokal) | Offset vom Auge |
|---|---|---|---|
| Deckebene / Planken | Modell y 0 | y = 0.00 | **`(0, −1.30, 0)`** |
| Kapuzenkrone (heutiges Flammen-Offset) | `hood` bis y ≈ 27.5 px | y = 1.72 | `(0, +0.42, 0)` — heute `+0.55` |
| **Gesichtskarten (neu)** | `glow_face_*` Mitte `0,20.5,−4.25` | y = 1.28, z = −0.27 | `(0, −0.02, −0.27)` |
| Gürtellaterne | `lantern` Glaskörper, Cube y 4.2–6.6 px, Pivot `−3.5, 7.4, −3.35` | x = −0.22, y = 0.34, z = −0.21 | `(−0.22, −0.96, −0.21)` |
| Blattspitze im Catch | §5.4 | y ≈ −0.55, out 2.89, längs −0.57 | — |

Die **Gesichtskarten** sind der interessanteste neue Anker: acht individuell gefärbte
Punktlichter (§2.3). Falls B2 die Seelenflamme farblich an die Rudererin koppeln will, steht
die Palette dort — das wäre die Kür, aus MB1-Sicht aber verzichtbar.

---

## 8. Validierung

Volles Log: `mb1_validate_and_compile.txt` (Artefakt).

### 8.1 `validate_geo.py` — 2/2 PASS

```
=== GEO  deckhand.geo.json      canvas 64x64   25 bones  27 cubes  -> PASS (0 error(s), 0 warning(s))
=== ANIM deckhand.animation.json
    'animation.deckhand.row':      loop=True                length=3.0  bones=14 keyframes=114 last_key=3.0s
    'animation.deckhand.idle_sag': loop=True                length=3.0  bones=12 keyframes=70  last_key=3.0s
    'animation.deckhand.walk':     loop=True                length=0.9  bones=12 keyframes=50  last_key=0.9s
    'animation.deckhand.rise':     loop=False               length=1.6  bones=13 keyframes=145 last_key=1.6s
    'animation.deckhand.attack':   loop=False               length=0.6  bones=10 keyframes=60  last_key=0.6s
    'animation.deckhand.death':    loop='hold_on_last_frame' length=1.5 bones=11 keyframes=64  last_key=1.5s
    'animation.deckhand.tilt':     loop=True                length=3.0  bones=14 keyframes=110 last_key=3.0s
    7 animation(s)                                                     -> PASS (0 error(s), 0 warning(s))

validate_geo: 2/2 file(s) passed — all good
```

Der Validator erkennt die neun `glow_`-Bones von sich aus als emissiv
(`glow_face_0 (pivot 0,20.5,-4.25 · 1 cube · emissive)` …), das Glowmask-Kontrakt ist also
nicht nur behauptet, sondern vom FROZEN-Validator bestätigt.

### 8.2 Painter-Determinismus — 2× gelaufen, MD5 identisch

```
painted geometry.deckhand (64x64) -> .../textures/entity/deckhand.png
  2885 albedo px, 41 glowmask px -> .../textures/entity/deckhand_glowmask.png
bee1f09268aeb4f29b118f1d428c0789  src/main/resources/assets/eclipse/textures/entity/deckhand.png
f227f74ef7e76f3f21d1a228a50bfdb0  src/main/resources/assets/eclipse/textures/entity/deckhand_glowmask.png

painted geometry.deckhand (64x64) -> .../textures/entity/deckhand.png
  2885 albedo px, 41 glowmask px -> .../textures/entity/deckhand_glowmask.png
bee1f09268aeb4f29b118f1d428c0789  src/main/resources/assets/eclipse/textures/entity/deckhand.png
f227f74ef7e76f3f21d1a228a50bfdb0  src/main/resources/assets/eclipse/textures/entity/deckhand_glowmask.png
```

Beide Paare bytegleich. Keine Textur wurde von Hand angefasst. 41 emissive Texel = 33 über
die acht Bank-Karten + 8 für die Brandmarke (vorher: 0 — die Glowmask war ein leeres PNG).
Das Karten-Flackern im Painter ist global-pixel-gekeyed (`px.noise(61)`), also deterministisch.

### 8.3 `compileJava` — BUILD SUCCESSFUL

Mit `--rerun-tasks --no-build-cache` erzwungen (ein `UP-TO-DATE` beweist nichts):

```
BUILD SUCCESSFUL in 7s
2 actionable tasks: 2 executed
100 warnings
```

Alle 100 Warnungen sind die vorbestehenden `EventBusSubscriber.bus()`-Deprecations in fremden
`veilfx/*FxRows.java`-Dateien. **Kein einziges javac-Diagnostikum nennt eine Deckhand-Datei**
(gegengeprüft per `grep -i deckhand` über die volle Ausgabe: 0 Treffer).

### 8.4 Loop-Nähte (Vorwärtskinematik + Molang, alle Loop-Clips)

```
row        value 0.000000 (tatter_right.rot)   slope jump 22.2/s (arm_left.rot)
idle_sag   value 0.000000 (lantern.rot)        slope jump 11.4/s (lantern.rot)
walk       value 0.000000 (lantern.rot)        slope jump 44.4/s (arm_right.rot)
tilt       value 0.000000 (tatter_left.rot)    slope jump 17.1/s (tatter_left.rot)
```

Wertnaht exakt 0 auf allen vier Loops (das ist die harte Bedingung). Die Steigungssprünge
sind kosmetisch und liegen unter dem, was ein 4-t-Blend ohnehin verwischt.

### 8.5 catmullrom-Overshoot

Größter Ausreißer: `rise.arm_left.rotation` 3.14° = **3 % der Kanalspanne**; relativ am
größten `tilt.hood_point` mit 10 % (1.3°). Beides gewollt (der Durchbruch **soll**
überschwingen) und weit unter den Werten, bei denen ein Bone in die Geometrie einläuft — die
Brim-Messung §2.4 samplet mit 201 Stützstellen, also inklusive aller Overshoots.

### 8.6 Modellreichweite vs. Culling-Box

```
ALL   x[-13.25  13.52]  y[-19.32  40.67]  z[-51.20   9.17]
-> inflate needed (blocks): x/z 2.850, y-down 1.207, y-up 0.942     (ausgeliefert: 3.0 / 1.8 / 1.8)
```

---

## 9. Rest-Notizen (ehrlich)

### 9.1 Rotations-Konvention — Alarm untersucht, entwarnt (mit Herleitung)

Beim Dekompilieren von GeckoLib 4.9.2 fiel auf, dass **sowohl** der Modell-Bake
(`BakedModelFactory$Builtin.constructBone/constructCube`) **als auch** der Animations-Bake
(`BakedAnimationsAdapter`) die Rotationen als `(−x, −y, +z)` ablegen und die Pivots als
`(−x, +y, +z)`. Gelesen als „GeckoLib invertiert die authorierte Bewegung" wäre das ein
projektweiter Befund gewesen — und es hätte jede Zahl in diesem Report entwertet, weil mein
Sampler in reinen Blockbench-Koordinaten rechnet.

Es ist keiner. Die Kette lässt sich vollständig auflösen:

* Positionen: `updatePivot(−x, y, z)` und `translateMatrixToBone(−posX, posY, posZ)` — eine
  Spiegelung `Mx = diag(−1, 1, 1)`.
* `GeoEntityRenderer.applyRotations` dreht das Modell mit `Axis.YP.rotationDegrees(180 − yaw)`.
  Bei yaw = 0 ist das `Ry(180°) = diag(−1, 1, −1)`.
* Gesamtabbildung Blockbench → Renderraum: `Ry(180)·Mx = diag(1, 1, −1) = Mz`.
* Eine Rotation `R` muss in den neuen Raum konjugiert werden: `Mz·R·Mz⁻¹`. Für
  `Mz = diag(1,1,−1)` gilt `Rx(θ) → Rx(−θ)`, `Ry(θ) → Ry(−θ)`, `Rz(θ) → Rz(+θ)`.
* **Genau das** tut GeckoLib: `(−x, −y, +z)`.
* Die Euler-Reihenfolge stimmt ebenfalls überein: `RenderUtil.rotateMatrixAroundBone`
  multipliziert Z, dann Y, dann X (= `Rz·Ry·Rx`), mein Sampler `mz @ my @ mx`. Konjugation
  mit einer Diagonalmatrix ist reihenfolgeerhaltend.

Fazit: die Negation ist ein **Basiswechsel**, kein Vorzeichenfehler; das gerenderte Ergebnis
ist die Blockbench-Vorschau. Und weil `Mz` nur `z` spiegelt, sind alle Größen, die ich messe
(Höhen in y, Breiten in |x|, Freiraum über den Karten) **invariant**. Der Vorderseiten-Test
`z < −4.25` wird im Renderraum zu `z > +4.25`, zeigt also weiterhin auf dasselbe Gesicht.

Ich habe meinem Sampler trotzdem einen `MB1_ROT=geckolib`-Schalter spendiert, der die
Halb-Konjugation simuliert. Unter ihr würden `rise` und `death` die Brim in die Karten
ziehen (−0.71 / +0.02 statt +0.97 / +0.47) — das ist ein weiterer Beleg dafür, dass diese
Lesart falsch ist, denn dann wären auch die Ruder in `tilt` nach unten geschifft.

### 9.2 Head-Tracking überschreibt `head.rotX/rotY` — projektweit, nicht MB1-spezifisch

`DeckhandRenderer` konstruiert mit `turnsHead = true`. In GeckoLib 4.9.2 läuft
`GeoModel.handleAnimations` in der Reihenfolge `tickAnimation(...)` → `setCustomAnimations(...)`,
und `DefaultedEntityGeoModel.setCustomAnimations` macht:

```java
head.setRotX(entityData.headPitch() * (float)(Math.PI / 180.0));
head.setRotY(entityData.netHeadYaw() * (float)(Math.PI / 180.0));
```

Das ist ein **Setter, kein Addierer**, und er läuft **nach** der Animation. Jeder
`head`-Rotationskanal in X oder Y ist bei einem kopfverfolgenden Mob also tot. Deshalb
bespielt kein einziger der sieben Deckhand-Clips `head.rotX/rotY` — der Kopf bekommt
ausschließlich **Z-Rollen** (Nicken kommt aus `hood`/`hood_point`, die als Kinder unberührt
bleiben). Das ist keine Stilentscheidung, sondern die einzige Möglichkeit.

Für andere Teams relevant: wer bei einem `turnsHead = true`-Mob ein Kopfnicken authoriert,
sieht es nie. Ich fasse fremde Mobs nicht an, aber es sollte jemand wissen.

### 9.3 `action`-Controller mit `transitionLength = 0` (FROZEN)

`attack` steigt auf `arm_* = 55°` ein und aus. Das ist auf `walk` getunt (Mittelwert 63.3°,
Snap ≈ 8°) — eine Deckhand, die zuschlägt, ist in aller Regel eine, die gerade herangelaufen
ist. Steht sie dagegen still, ist die Basis `idle_sag` (Mittelwert 10.3°) und der Snap
beträgt **45° in einem Frame**. Sauber lösen ließe sich das nur mit einem
Transition-Wert auf dem `action`-Controller, und der lebt in der FROZEN-Basis
`EclipseGeoMob`. Derselbe Befund steht bereits in `MA6_FOGELITES_REPORT.md` §8 — es ist ein
Wellen-übergreifendes Thema, kein Deckhand-Thema.

### 9.4 Nicht gemacht (bewusst)

* Keine FX-Datei angefasst. §7 ist eine Spec, keine Implementierung — `deckhand_soul_flare`
  bleibt unverändert.
* Keine Textur von Hand editiert; beide PNGs kommen deterministisch aus dem Painter.
* `OarAnimator.java`: null Zeilen. Der Auftrag war Verifikation (§5).
* `registerControllers` unverändert final.
* Keine neuen Lang-Keys → **kein** `docs/plans_v3/langdrop/MB1-DECKHAND.json`.
* Der Krängungs-Roll in `tilt` läuft bewusst **nicht** über eine Z-Rotation am `root`:
  Backbord und Steuerbord sitzen einander gegenüber (yaw 180 vs. 0), ein modellraum-lokaler
  Roll würde die beiden Bordseiten **gegeneinander** kippen lassen. Ein weltraumrichtiger
  Roll bräuchte eine dritte Spiegelregel im Renderer; das ist mehr Regressionsfläche für den
  F-003-Pfad, als eine 100-t-Cutscene wert ist. Die Krängung liegt daher in Pitch + Stoß.
* Die Werkzeuge unter `/tmp/mb1` (FK-Sampler, Molang-Auswerter, Ortho-Renderer, Audit,
  Hand-Over-Messer) sind **nicht** committet — sie hängen an keiner Projekt-API und wären
  nach dem nächsten GeckoLib-Update Wartungsschuld.

---

## 10. Test-Rezept

```
# 1) Gesichter: acht Ruderer, acht Gesichter. Aus 3-4 Blöcken Abstand von VORNE ansehen,
#    dann die Bank wechseln — Muster, Höhe und Anzahl der Lichter müssen sich ändern.
/execute in eclipse:limbo run tp @s <ghost ship>
#    Gegenprobe auf die NBT-Stabilität: Welt neu laden -> Bank 3 zeigt dasselbe Gesicht.

# 2) row-Sync (der F-003-Kern): von der Seite auf die ganze Reihe schauen.
#    Alle acht Blätter müssen im selben Frame eintauchen, dauerhaft, ohne 3-s-Ruck.
#    Der Splash muss UNTER dem eigenen Blatt liegen, nicht unter der Nachbarbank.

# 3) Ruder-Culling: Kamera dicht an einer Rudererin vorbeischwenken, bis sie den
#    Bildrand streift. Weder Ruderer noch Blattspitze dürfen poppen.

# 4) rise: den Phasenbruch auslösen (Ferryman P2). Von der SEITE ansehen —
#    Sinken unter die Planken (Tick 1-10), Durchbruch (Tick 17), Überkopf-Spitze
#    (Tick 19), zwei Nachschwinger. Das Ruder darf NICHT wegblinken, es schrumpft.
#    Backbord gegenprobieren: das Ruder darf beim Schrumpfen nicht über den Rumpf springen.

# 5) Zorn-Brandmarke: nach dem rise muss zusätzlich zur eigenen Lampe der Überlauf
#    brennen (Wangen + Kinn) — die eigene Lampe bleibt aber erkennbar.

# 6) attack/death an einer erhobenen Crew.

# 7) tilt: Start-Event-Cutscene (t=0..100). Von der SEITE: Ruder himmelwärts geschifft,
#    ein deutlicher Rumpfstoß pro 3 s, die Gürtellaterne pendelt sich danach aus.
#    Backbord/Steuerbord müssen identisch lesen.
```

Wenn die Registrare nicht verdrahtet sind, loggt der Mod das beim Start — dann greifen die
Limbo-Fahrten nicht, und das liegt nicht an MB1.
