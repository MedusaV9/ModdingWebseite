# MD3 — ITEMS-B-Trio (revive_sigil + heralds_lure + storm_heart)

**Auftrag:** Zensus §5 Welle M-D Zeile MD3 (`docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md`).
Sigil 3→7 Bones + `ritual_charge`-Loop + `shatter`; Lure Glow-Crescendo-idle +
Wurf-Vorbereitung; Storm Heart heartbeat-idle (10 Bones nutzen) + `socket` + `awaken`.

**Datei-Besitz (exklusiv):** `geo/item/{revive_sigil,heralds_lure,storm_heart}.geo.json`,
`animations/item/…`, `textures/item/{sigil,lure,stormheart}/…`,
`models/item/{revive_sigil,heralds_lure,storm_heart}.json`,
`scripts/geckolib_gen/items/{revive_sigil,heralds_lure,storm_heart}.py`,
`client/item/ItemsBClientExtensions` + die drei Renderer,
`ritual/{ReviveSigilItem,HeraldsLureItem,StormHeartItem}.java` (nur die
GeckoLib-Controller-/Trigger-Seite).
**NICHT angefasst:** `ritual/ReviveRitual.java` (B6), alle `.fx`/Photon-Generatoren
(Welle 13), 2D-Sprite-Icons, `paint_lib.py`/`validate_geo.py` (FROZEN).

---

## 1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Item | Geo | Anims | Trigger-Seam heute |
|---|---|---|---|
| `revive_sigil` | 3 Bones / 5 Cubes (`root`, `tablet`, `glow_glyph`) | `idle` (4.0 s, 3 Molang-Kanäle), `ritual` (1.6 s, 11 kf) | `ReviveSigilItem#useOn` feuert `ritual`, wenn `ReviveRitual.isRunningAt` nach `handleSigilConfirm` true ist |
| `heralds_lure` | 7 Bones / 10 Cubes | `idle` (4.8 s), `offering` (1.4 s, 23 kf) | `HeraldsLureItem#useOn` feuert `offering` direkt vor `shrink(1)` |
| `storm_heart` | 10 Bones / 18 Cubes | **nur** `idle` (6.0 s) | KEINER — die Klasse registriert bewusst keinen `action`-Controller und ist kein `SingletonGeoAnimatable` |

Controller-Contract (verifiziert an `EclipseWandItem`, `EclipseGeoAnimations`): genau
ZWEI Controller, `base` (Blend 4, loopt `idle`) + `action` (Transition 0,
`state -> PlayState.STOP`, nur `triggerableAnim`-One-Shots). Das gilt hier 1:1 —
keine dritten Controller, alle neuen Anims sind Triggerables auf `action`.

Molang-Zyklus-Gesetz (aus `heralds_lure.idle` `query.anim_time * 75` @ 4.8 s = 360°
und `storm_heart.idle` `* 60` @ 6.0 s = 360° zurückgelesen): **jede Molang-Dauer­rotation
und jeder `math.sin` muss über die Loop-Länge ein ganzes Vielfaches von 360° durchlaufen**,
sonst springt der Loop. Alle neuen Loops halten das ein (Tabelle §5.4).

`storm_heart` hat **keine Socket-Mechanik im Code** (`rg storm_heart src/main/java`:
nur `FogTyrantEntity#dropCustomDeathLoot`, `EclipseItems`-Registrierung, `ItemLexicon`) —
siehe §6.2 für die daraus folgende Seam-Entscheidung.

B6 (`B6_CEREMONY_REPORT.md` §3.2 / `ReviveRitual#sendSoulThread`): Seelenfaden-Cue alle
**40 t**, Stufe = `min(3, ticksElapsed * 3 / DURATION_TICKS + 1)`, eigener
`soulThreadTimer`-Countdown (kein Modulo, weil der Zeugenkreis ganze Sekunden auf
`ticksElapsed` addiert). Meine `ritual_charge_*`-Stufen spiegeln genau das: **2.0 s
Anim-Länge = 40 t Re-Send-Takt**, drei Dateien statt eines Parameters.

## 2 Plan

1. **Revive Sigil** — Geo 3 → 11 Bones: `tablet` wird zum reinen Träger, die drei Cubes
   werden zu `slab`/`cap_top`/`cap_bottom` (damit der `shatter` sie einzeln absprengen
   kann), dazu ein `ring`-Carrier mit 4 einzeln animierbaren `glow_rune_a..d`-Segmenten
   (tangentiale Orbit-Ebenen, r = 7 px, Ring um 25° gekippt). Anims: `idle` (6.0 s, neu
   mit Ring-Orbit), `ritual` (1.6 s, um Ring/Runen erweitert), **`ritual_charge_1/2/3`**
   (je 2.0 s = B6s 40-t-Takt, zyklisch, One-Shot ⇒ selbst-terminierend wenn das Ritual
   scheitert), **`shatter`** (1.4 s).
2. **Herald's Lure** — +2 `glow_flare_a/b`-Korona-Ebenen (gekreuzt, Loch in der Mitte,
   damit sie den Kern nicht schneiden) als Träger des Doppel-Blinks. `idle` neu auf
   6.0 s mit **3-s-Crescendo** (Molang-Sinus auf `glow_core` + Prong-„Einatmen") und
   Doppel-Blink per Keyframe auf den Flares; neu **`offering_prep`** (0.8 s Aufbäumen +
   Zittern), gefeuert aus `use()` (Luft-Rechtsklick).
3. **Storm Heart** — Geo unverändert (10 Bones werden endlich benutzt). `idle` neu als
   **Lub-Dub-Herzschlag** nach B5s Kurve (`B5_DREAD_REPORT.md` §2: LUB 1.00, DUB 0.70 bei
   +0.22 s, danach Stille), 2 Schläge auf 2.4 s Loop; neu **`socket`** (1.1 s) und
   **`awaken`** (2.0 s).
4. Painter-Driver aller drei nachziehen (neue Bones brauchen Material, sonst „no material"),
   `validate_geo.py` auf allen sechs Dateien, `./gradlew compileJava`.

Die Trigger für `ritual_charge_*`/`shatter` liegen in `ReviveRitual` = **B6s Datei** ⇒
nur Snippet (§7.1), plus zwei fertige Public-Helfer in `ReviveSigilItem`, damit B6s
Einbau wirklich 2–3 Zeilen ist.

---

## 3 Geänderte Dateien

| Datei | Art |
|---|---|
| `geo/item/revive_sigil.geo.json` | 3 → 12 Bones, 5 → 9 Cubes |
| `geo/item/heralds_lure.geo.json` | 7 → 9 Bones, 10 → 12 Cubes |
| `geo/item/storm_heart.geo.json` | **unverändert** (10 Bones werden jetzt genutzt) |
| `animations/item/revive_sigil.animation.json` | 2 → 6 Anims |
| `animations/item/heralds_lure.animation.json` | 2 → 3 Anims, `idle` neu |
| `animations/item/storm_heart.animation.json` | 1 → 3 Anims, `idle` neu |
| `models/item/revive_sigil.json` | Display-Scales ×0.82 (Ring vergrößert das Sweep-Volumen) |
| `scripts/geckolib_gen/items/revive_sigil.py` | Material für `slab`/`cap_*`/`glow_rune_a..d` |
| `scripts/geckolib_gen/items/heralds_lure.py` | Material `flare_plane` für `glow_flare_*` |
| `textures/item/sigil/revive_sigil{,_glowmask}.png` | Painter-Output (nur regeneriert) |
| `textures/item/lure/heralds_lure{,_glowmask}.png` | Painter-Output (nur regeneriert) |
| `ritual/ReviveSigilItem.java` | 4 Triggerables + 2 Public-Helfer für B6 |
| `ritual/HeraldsLureItem.java` | `offering_prep`-Triggerable + `use()` |
| `ritual/StormHeartItem.java` | `SingletonGeoAnimatable` + `action`-Controller + 2 Triggerables |

`storm_heart`-Textur und alle 2D-Sprite-Icons blieben unangetastet, ebenso
`ReviveRitual.java`, `AltarBlock.java`, `paint_lib.py`, `validate_geo.py`.

## 4 Ergebnis pro Item

### 4.1 revive_sigil — 3 → 12 Bones, 5 → 9 Cubes

```
root
├─ tablet                     (reiner Träger — vorher trug er die Cubes selbst)
│  ├─ slab / cap_top / cap_bottom   (NEU: einzeln absprengbar im shatter)
│  └─ glow_glyph
└─ ring                       (statischer 25°-Kipp)
   └─ ring_spin               (NUR die animierte Y-Drehung — siehe §6.1)
      └─ glow_rune_a..d       (4 tangentiale 2×3-Ebenen, r = 7 px, je eigene Glyphe)
```

Der Zensus verlangte 3 → 7 Bones; es sind 12 geworden, weil der `shatter` die drei
Tablet-Cubes einzeln absprengen muss (`slab`/`cap_top`/`cap_bottom`) und der Ring wegen
§6.1 in zwei Bones zerfällt.

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 6.0 s | ja | Ring-Orbit 60 °/s (= 360 °), Kern-Puls, Runen-Atmen |
| `ritual` | 1.6 s | nein | Spin-up + Glyph-Overglow (erweitert um Ring/Runen/Caps) |
| `ritual_charge_1` | 2.0 s | nein | Ring 180 °/s, Kern ±0.12, Root-Heben 0.6 |
| `ritual_charge_2` | 2.0 s | nein | Ring 360 °/s, Kern ±0.20, Cap-Spalt 0.35 |
| `ritual_charge_3` | 2.0 s | nein | Ring 540 °/s, Kern ±0.30, Cap-Spalt 0.9, Tablet-Shudder 5° |
| `shatter` | 1.4 s | nein | Runen fliegen radial auf r ≈ 14 px, Kern implodiert, Slab/Caps brechen weg |

Alle drei `ritual_charge_*` sind exakt 2.0 s = B6s 40-t-Re-Send und laufen über diese
Länge ein ganzes Vielfaches von 360° durch → ein Re-Trigger auf dem Takt ist unsichtbar.
Sie sind `loop=false`, damit ein **gescheitertes** Ritual sich von selbst beruhigt.

### 4.2 heralds_lure — 7 → 9 Bones, 10 → 12 Cubes

Neu: `glow_flare_a` + `glow_flare_b` — zwei um 90° gekreuzte 9×9-Korona-Ebenen mit
ausgespartem Zentrum (kein Z-Fighting mit `glow_core`), die den Doppel-Blink tragen.

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 6.0 s | ja | Glow-Crescendo **Periode 3.0 s** (`math.sin(anim_time * 120)`), Prong-„Einatmen", Doppel-Blink bei t = 1.46/1.62 s und 4.46/4.62 s |
| `offering_prep` | 0.8 s | nein | Aufbäumen + Zittern, endet in Ruhelage |
| `offering` | 1.4 s | nein | bestehend, um `glow_flare`-Akzente erweitert |

Der Doppel-Blink sitzt exakt auf dem Crescendo-Maximum (Kern-Peak bei t = 1.5 s / 4.5 s):
Flare A schlägt zuerst und stärker an, Flare B 0.04 s später mit 0.85× — das liest sich
als „Herzschlag des Lockmittels" statt als zwei gleiche Blitze.

### 4.3 storm_heart — Geo unverändert, alle 10 Bones bewegt

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 2.4 s | ja | **Lub-Dub**, 2 Schläge (1.2 s Takt = 50 bpm); Schalen heben+spreizen, `glow_arc_*` feuern AUF den Schlägen |
| `socket` | 1.1 s | nein | Käfig staucht, Rippen klemmen ein, dann Schnapp-Entladung |
| `awaken` | 2.0 s | nein | Zittern → Schalen schwingen auf → Kern flammt → Arcs kaskadieren → Schalen schließen |

B5s Kurve (`B5_DREAD_REPORT.md` §2) ist messbar eingehalten — nachgemessen an der
tatsächlichen Geometrie-Auslenkung, nicht am Keyframe-Text:

| Bone | LUB | DUB | Abstand | Verhältnis |
|---|---|---|---|---|
| `cage` | 0.050 s | 0.270 s | **0.220 s** | **0.700** |
| `rib_n` / `rib_s` | 0.050 s | 0.270 s | **0.220 s** | **0.701** |
| `rib_e` / `rib_w` | 0.080 s | 0.300 s | **0.220 s** | 0.710 |

*(Soll: 0.220 s / 0.700.)* Die e/w-Rippen tragen einen **absichtlichen** 0.03-s-Versatz,
damit der Käfig atmet statt zu schnappen. Wer die Summe über alle Bones misst, sieht
deshalb scheinbar 0.190 s / 0.81 — das ist der Ripple, nicht die Kurve.

---

## 5 Validierung

| Prüfung | Ergebnis |
|---|---|
| `validate_geo.py` × 3 Items (Geo + Anim) | **6/6 PASS**, 0 Errors, 0 Warnings |
| `./gradlew compileJava` | **BUILD SUCCESSFUL** |
| Painter-Determinismus | Re-Run beider Driver → md5 **byte-identisch** |
| Canvas-Konsistenz (AutoGlowingTexture) | Albedo und Glowmask je 64×64 ✓ |
| Loop-Naht `revive_sigil.idle` | max ‖M(0) − M(6.0)‖ = **1.8 e-15** |
| Loop-Naht `storm_heart.idle` | Schalen-Auslenkung bei t=0 exakt **0.000** |
| Ring-Ebene (Präzessionstest) | Ebenen-Kipp **25.1°** konstant, Rest-Abweichung nur aus dem gewollten Radial-Puls |
| One-Shot-Ruhelage | alle 9 One-Shots enden in Rest (Ausnahme by design: `glow_flare_*`/`glow_arc_*` ruhen auf Scale 0 — sie sind im Ruhezustand unsichtbar) |

Zusätzlich habe ich einen **Offline-Rasterizer** gebaut (nicht committet, `/tmp/md3_preview.py`),
der Geo + Anim + Albedo + Glowmask mit GeckoLibs Transform-Reihenfolge nachrechnet und
Frames rendert. Damit sind die Kurven visuell geprüft, ohne einen `runClient` zu starten
(die VM ist knapp bei Speicher und andere Teams arbeiten parallel).

---

## 6 Zwei Funde, die den Entwurf geändert haben

### 6.1 Der Ring präzedierte — Kipp und Drehung dürfen nicht auf demselben Bone liegen

Erster Entwurf: `ring` mit Rest-Rotation `[25, 0, 0]` **und** animierter Y-Drehung.
GeckoLib rotiert Z → Y → X (`RenderUtil.rotateMatrixAroundBone`), also wird die
Y-Drehung *vor* dem X-Kipp angewandt — der Ring eiert statt in seiner gekippten Ebene
zu laufen. Fix: `ring` trägt nur noch den statischen Kipp, das neue Kind `ring_spin`
trägt nur noch die Animation. Nachgemessen: Ebenen-Normale konstant bei 25.1°.

**Merksatz für andere Item-Geos:** statischer Bone-Kipp und animierte Drehung auf
demselben Bone = Präzession. Immer trennen.

### 6.2 `storm_heart` hat keine Socket-Mechanik — und der Altar hätte die Trophäe gefressen

`rg storm_heart src/main/java` findet nur: Registrierung (`EclipseItems:194`),
Renderer (`ItemsBClientExtensions:36`), den garantierten Drop des Fog Tyrant
(`FogTyrantEntity:1630`) und einen Sammel-Eintrag in `ItemLexicon:42`.
**Es gibt keine Einsetz-Mechanik.**

Der naheliegende Seam — Sneak-Klick auf den Altar — ist eine **Falle**:
`AltarBlock.onSneakRightClick` hängt auf `PlayerInteractEvent.RightClickBlock` mit
`EventPriority.LOWEST`, canceled das Event für **jedes** Item außer Revive Sigil und
Herald's Lure und routet es in `handleMilestoneDeposit`/`handleOffering`. Ein
`useOn` im `StormHeartItem` wäre dort also (a) toter Code, weil das gecancelte Event
`Item#useOn` nie erreicht, und (b) auf genau der Geste, die den einmaligen
Tyrant-Drop verschenkt.

Deshalb: `socket` läuft kosmetisch beim Sneak-Klick auf **gewöhnlichen** Stein
(Altäre explizit ausgenommen, Rückgabe immer `PASS` → kein Verhaltenswechsel), und
`StormHeartItem.triggerSocket(player, stack, level)` ist der Einzeiler für das Team,
das die echte Mechanik nachliefert.

### 6.3 GeckoLib-Vorzeichen: aus dem Bytecode verifiziert, nicht geraten

Beim Debuggen von §6.1 habe ich GeckoLib 4.9.2 dekompiliert, weil die Konvention
nirgends dokumentiert ist. Für künftige Anim-Autoren:

| Kanal | Behandlung |
|---|---|
| Rotation X, Y | **negiert** + Grad→Rad |
| Rotation Z | nur Grad→Rad |
| Position X | **negiert** (`RenderUtil.translateMatrixToBone`: `-getPosX()/16`) |
| Position Y, Z, alle Scales | unverändert |
| Bone-Rest-Rotation im `.geo.json` | X, Y ebenfalls negiert (`BakedModelFactory`) |
| Rotationsreihenfolge | Z → Y → X (`rotateMatrixAroundBone`) |

Die wichtige Feinheit: `BakedAnimationsAdapter` faltet Negierung und Grad→Rad nur für
`Constant`-Werte beim Laden ein — **Molang-Ausdrücke sind dort ausgenommen**. Man könnte
daraus schließen, Molang-Rotationen würden weder negiert noch von Grad umgerechnet. Das
stimmt nicht: `AnimationController.getAnimationPointAtTick` holt das für
Nicht-`Constant`-Werte zur Laufzeit nach (`Math.toRadians` + `* -1.0` für Achse X/Y).
**Numerische und Molang-Keyframes verhalten sich also identisch** — ein Richtungssprung
zwischen einem Molang-`idle` und einem numerischen One-Shot auf demselben Bone droht
nicht. Genau deshalb darf `revive_sigil` den Ring im `idle` per Molang und im
`shatter` per Keyframes drehen.

Ebenfalls verifiziert: ein explizites `animation_length` wird immer benutzt
(`bakeAnimation`, × 20 in Ticks); `calculateAnimationLength` greift nur, wenn der
Schlüssel fehlt — und liefert dann für keyframe-lose Anims `Double.MAX_VALUE`. Da alle
`ritual_charge_*` reine Molang-Anims **ohne** Keyframes sind, ist ihr explizites
`"animation_length": 2.0` das Einzige, was sie überhaupt enden lässt. Nicht entfernen.

---

## 7 Snippets

### 7.1 B6 — `ReviveRitual.java` (NICHT von mir eingebaut, Datei gehört B6)

In `sendSoulThread()`, direkt neben dem bestehenden Cue-Versand — eine Zeile:

```java
ReviveSigilItem.triggerRitualCharge(confirmer, stage, ticksElapsed);
```

Und im Erfolgspfad, **vor** dem Verbrauch des Sigils:

```java
ReviveSigilItem.triggerShatter(confirmer);
```

Beide sind `public static`, nullsicher (kein Sigil im Inventar → No-Op) und
server-seitig; das Sync zum Client macht `SingletonGeoAnimatable`.
`triggerRitualCharge` verwirft die ersten `RITUAL_SPINUP_TICKS` (32 t) selbst, damit
B6s erster Faden-Send die `ritual`-Spin-up-Anim nicht nach einem Tick abschneidet
(beide teilen sich den einen `action`-Controller).

Wichtig für B6: `CHARGE_TICKS` (40) muss gleich dem Soul-Thread-Re-Send-Intervall
bleiben. Wenn B6 den Takt ändert, hier mitziehen — sonst stottert der Ring einmal
pro Re-Send.

### 7.2 Zukünftige Socket-Mechanik

```java
StormHeartItem.triggerSocket(serverPlayer, stack, serverLevel);
```

---

## 8 Test-Rezept

Vorbereitung: `/give @s eclipse:revive_sigil`, `eclipse:heralds_lure`, `eclipse:storm_heart`.

1. **Idle-Loops** — alle drei nacheinander in die Hand nehmen und je ≥ 10 s halten:
   Sigil-Ring läuft gleichmäßig in seiner gekippten Ebene (kein Eiern, kein Ruck alle
   6 s); Lure pulst mit 3-s-Periode und blitzt am Maximum doppelt; Storm Heart schlägt
   Lub-Dub mit hörbar ungleichen Schlägen und Pause.
2. **`awaken`** — Storm Heart in die Luft rechtsklicken: Schalen öffnen sich, Kern
   flammt, Schalen schließen, danach nahtlos zurück in den Herzschlag.
3. **`socket`** — Storm Heart **sneak**-rechtsklicken auf einen gewöhnlichen Block
   (NICHT auf den Altar): Stauchen → Klemmen → Schnapp.
4. **`offering_prep`** — Herald's Lure in die Luft rechtsklicken: kurzes Aufbäumen.
5. **`ritual_charge_*` + `shatter`** — erst nach B6s Einbau von §7.1 in-game sichtbar.
   Danach: Ritual starten und über die volle Dauer zusehen, ob die Stufe alle 40 t
   ohne Ruck eskaliert.
6. **GUI-Check** — alle drei im Inventar: der Sigil-Ring darf im 16-px-Slot nicht
   abgeschnitten werden. Nachgemessen (Sweep-Box × Display-Scale 0.74):

   | Zustand | auf dem Schirm | 16-px-Slot |
   |---|---|---|
   | `idle` | 12.0 × 9.7 px | passt |
   | `ritual_charge_3` | 14.3 × 13.1 px | passt |
   | `shatter` | 22.2 × 23.0 px | **überschreitet bewusst** (die Scherben fliegen aus dem Slot) |

   Zum Vergleich der alte Sigil bei Scale 0.9: 10.9 × 11.8 px — der Ring kostet also
   trotz vierfacher Bone-Zahl kaum Slot-Fläche.
