# MD2 — ITEMS-A-Paar (arm_artifact + heart_extractor)

**Auftrag:** Zensus §5 Welle M-D Zeile MD2 (`docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md`):
Artifact `idle`-Puls bei ungelesenen Einträgen (Bone-Scale 1.0→1.04) + `open` mit
Seiten-Fächer; Extractor `extract` mit Kammer-Snap-Bone + `refuse`-Kopfschütteln
verstärken; beide `idle`/`equip` auf MD3-Niveau (Mikro-Bewegung, Glow-Akzente).

**Datei-Besitz (exklusiv, alles davon angefasst):**
`geo/item/{arm_artifact,heart_extractor}.geo.json`, `animations/item/…`,
`textures/item/{artifact,extractor}/…` (nur Painter-Output),
`scripts/geckolib_gen/items/{arm_artifact,heart_extractor}.py`,
`client/item/ItemsAClientExtensions` + `ArmArtifactRenderer`,
`artifact/ArmArtifactItem.java` + `ritual/HeartExtractorItem.java` (NUR die
GeckoLib-Controller-/Trigger-Seite), `docs/uv/{arm_artifact,heart_extractor}.md`,
dieser Report.

**NICHT angefasst:** `paint_lib.py` / `validate_geo.py` (FROZEN),
`client/item/ItemsBClientExtensions` (MD3), `HeartExtractorRenderer` (keine Änderung
nötig — `isClientChanneling` reichte bereits), `models/item/{arm_artifact,heart_extractor}.json`
(Display-Scales bleiben, Begründung §5.3), `tools/photon/**`, `assets/eclipse/fx/**`,
Lang-Dateien (siehe §7.2 — **0 neue Keys**, deshalb kein Langdrop).

---

## 1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Item | Geo vorher | Anims vorher | Trigger-Seam heute |
|---|---|---|---|
| `arm_artifact` | 6 Bones / 10 Cubes (`root`→`forearm`→{`glow_stump`, `hand`→{`fingers`, `glow_ledger`}}) | `idle` (6.0 s, 4 Bones, 9 kf), `open` (0.8 s, 5 Bones, 22 kf) | `ArmArtifactItem#use` **und** die Server-Seite von `overrideOtherStackedOnMe(SECONDARY)` feuern `open` |
| `heart_extractor` | 6 Bones / 8 Cubes (`chamber` war EIN 3×4×3-Cube) | `idle` (4.0 s, 2 Bones), `channel` (3.0 s, 10 kf), `extract` (0.5 s, 10 kf), `refuse` (0.4 s, 8 kf) | `finishUsingItem` → `extract`; `refuse()` → `refuse`; `base` swappt via `HeartExtractorRenderer.isClientChanneling` |

Controller-Contract (verifiziert an `EclipseWandItem`, `EclipseGeoAnimations`,
MD3-Report §2): genau ZWEI Controller, `base` (Blend 4, loopt `idle`) + `action`
(Transition 0, `state -> PlayState.STOP`, nur `triggerableAnim`). Beide Items halten das
schon — alle neuen Anims sind entweder ein zweiter Base-Zustand oder ein Triggerable.

**`USE_DURATION_TICKS = 60` = 3.0 s = exakt die Länge von `channel`.** Das ist kein
Zufall und der Grund, warum `channel` in ein Plateau läuft statt zu loopen (§6.2).

### 1.1 Den „Ungelesen"-Zustand gibt es nicht — Suchprotokoll

`rg -i "unread|ungelesen|isNew|hasNew|seen|markRead"` über `src/main/java` liefert für
Journal/Bestiary **nichts**. Was es gibt:

| Quelle | Was sie kann | Warum sie allein nicht reicht |
|---|---|---|
| `client/progression/ClientBestiaryCache` | `generation()`, `tierFor(id)`, `tierUpId` | `generation()` zählt JEDE Änderung (auch Re-Syncs); `tierUpId` ist ein Einzel-Toast, kein Bestand |
| `client/collections/ClientCollectionsCache` | `generation()`, `all()` mit `grantedTier()`, `discoveredItemCount()` | dito |
| `client/handbook/HandbookScreen` | ist der Ort, an dem gelesen WIRD | speichert nichts |
| `client/handbook/InventorySlotDecor` | malt einen Hinweis-Punkt am Slot | dessen Zustand ist privat und gehört nicht MD2 |

Konsequenz (§4.3): MD2 leitet den Zustand client-seitig aus einem **monotonen
Wissens-Score** ab, statt eine fremde Klasse um ein Flag zu erweitern.

---

## 2 Plan

1. **arm_artifact** — Geo 6 → 12 Bones: `ledger` (Träger, Kind von `hand`) +
   `ledger_spin` (nur die animierte Y-Drehung, MD3-§6.1-Gesetz) + vier
   `glow_page_a..d`-Ebenen als Träger des Seiten-Fächers. Anims: `idle` poliert,
   **   `idle_unread`** (3.0 s, Forearm-Scale 1.00→1.04), **`equip`** (0.6 s),
   `open` 0.8 → 1.0 s mit vierstufigem Fächer.
2. **heart_extractor** — Geo 6 → 11 Bones: `chamber` wird reiner Träger, darunter
   `chamber_body` + der neue **`chamber_lid`** (Scharnier), dazu `clamp_n`/`clamp_s`
   und die emissive `glow_gauge`. Anims: `idle` poliert, **`equip`** (0.55 s),
   `channel` um Deckel/Backen/Anzeige erweitert, `extract` 0.5 → 0.75 s mit Snap +
   Nachfedern, `refuse` 0.4 → 0.6 s als echtes Kopfschütteln.
3. **Java** — Ungelesen-Tracker + Equip-Kantenerkennung in `ItemsAClientExtensions`
   (GAME-Bus), Lesbarkeit über `ArmArtifactRenderer.hasUnreadLedgerEntries()`
   (spiegelt `HeartExtractorRenderer.isClientChanneling`), Base-Swap in
   `ArmArtifactItem`, `equip`-Triggerable in beiden Item-Klassen.
4. **Painter** beider Driver nachziehen (neue Bones brauchen Material) + die
   §5-(c)-Glow-Akzente.

---

## 3 Geänderte Dateien

| Datei | Art |
|---|---|
| `geo/item/arm_artifact.geo.json` | 6 → 12 Bones, 10 → 14 Cubes |
| `geo/item/heart_extractor.geo.json` | 6 → 11 Bones, 8 → 12 Cubes (`chamber`-Cube 3×4×3 → `chamber_body` 3×3×3 + `chamber_lid` 3×1×3) |
| `animations/item/arm_artifact.animation.json` | 2 → 4 Anims, `idle`/`open` neu geschrieben |
| `animations/item/heart_extractor.animation.json` | 4 → 5 Anims, alle vier bestehenden erweitert |
| `scripts/geckolib_gen/items/arm_artifact.py` | Material `ledger_page` ×4 + Glow-Painter `fingertip_spill`/`seam_runes` |
| `scripts/geckolib_gen/items/heart_extractor.py` | Materialien `lid_glass`/`gauge_dial`/`clamp_*` + Glow-Painter `collar_filament`/`gauge_glow` |
| `textures/item/artifact/arm_artifact{,_glowmask}.png` | Painter-Output (nur regeneriert) |
| `textures/item/extractor/heart_extractor{,_glowmask}.png` | Painter-Output (nur regeneriert) |
| `artifact/ArmArtifactItem.java` | `ANIM_IDLE_UNREAD` + `ANIM_EQUIP`, Base-Swap, Triggerable |
| `ritual/HeartExtractorItem.java` | `ANIM_EQUIP` + Triggerable (7 Zeilen) |
| `client/item/ArmArtifactRenderer.java` | `hasUnreadLedgerEntries()`-Seam |
| `client/item/ItemsAClientExtensions.java` | Ungelesen-Tracker + Equip-Kantenerkennung (GAME-Bus) |
| `docs/uv/arm_artifact.md`, `docs/uv/heart_extractor.md` | neu |

---

## 4 Ergebnis pro Item

### 4.1 arm_artifact — 6 → 12 Bones, 10 → 14 Cubes

```
root
└─ forearm                    (trägt den 1.00→1.04-Atempuls)
   ├─ glow_stump
   └─ hand
      ├─ fingers
      └─ ledger               (NEU: Träger — Hub im open, 360°-Spin im equip)
         ├─ ledger_spin       (NEU: NUR die animierte Y-Drehung, §6.1-Gesetz)
         │  └─ glow_ledger    (statischer [45,0,45]-Kipp, unverändert)
         └─ glow_page_a..d    (NEU: 4 Ledger-Blätter 4×5×0, z-gestaffelt)
```

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 6.0 s | ja | Unterarm-Wiege ±1°, Stumpf-Puls ±5 %, Mote-Orbit r = 0.5 px @ 60 °/s, zwei ungleiche Finger-Curls; Blätter auf Scale 0 gepinnt |
| `idle_unread` | 3.0 s | ja | **Forearm-Scale 1.000 ↔ 1.040** (Kosinus, Periode 3 s = ein Atemzug), doppelt so schnelle Stumpf-/Mote-Frequenz, Zwei-Schlag-Rhythmus auf der Mote, kurze Finger-Tipper, **ein** Blatt blitzt bei t = 1.56 s auf und verschwindet wieder |
| `equip` | 0.6 s | nein | Root schwingt aus −22° Yaw ein, Unterarm-Overshoot, Finger von gespreizt zu Ruhe, Mote materialisiert (Scale 0 → 1.75 → 1) während `ledger` einmal volle 360° dreht |
| `open` | 1.0 s | nein | Hub + Handkippung, Finger spreizen 34°, Mote flammt auf 2.1, **die vier Blätter fächern gestaffelt (0.10/0.12/0.14/0.16 s) auf ±40° und ±82° auf**, halten, klappen zurück auf Scale 0 |

Der Zensus verlangte „Bone-Scale 1.0→1.04 Atmung". Nachgemessen an der Kurve, nicht am
Keyframe-Text: **min 1.000000 / max 1.040000**, und `idle_unread` startet bei exakt
1.000000 = `idle`s Wert, damit der Base-Swap nicht poppt.

Der Fächer, an der tatsächlichen Geometrie gemessen (Außenkanten-Peilung der vier
Blätter in der XZ-Ebene, Grad):

| t | a | b | c | d | Spreizung | max Scale |
|---|---|---|---|---|---|---|
| 0.00 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.00 |
| 0.20 | −18.8 | −24.0 | −164.0 | −163.1 | 145.2 | 1.14 |
| 0.30 | −38.7 | −65.1 | −144.2 | −122.1 | 105.5 | 1.06 |
| 0.45 | −33.5 | −80.2 | −143.9 | −96.3 | 110.4 | 1.00 |
| 0.90 | −12.8 | −31.7 | −166.1 | −147.2 | 153.3 | 0.45 |
| 1.00 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.00 |

(c/d starten bei ±180°, weil ihre Cubes spiegelseitig vom Pivot liegen; die Spreizung
ist die relevante Zahl.) Die vier Blätter überschwingen um 4–10° und setzen sich zurück
— das liest als Papier, nicht als Klappmechanik.

### 4.2 heart_extractor — 6 → 11 Bones, 8 → 12 Cubes

```
root
├─ needle
├─ frame
│  ├─ clamp_n / clamp_s   (NEU: Messingbacken, kneifen hinter dem Snap ein)
│  └─ glow_gauge          (NEU: Vitae-Anzeige, 3×2×1)
├─ glow_vitae
├─ chamber                (jetzt reiner Träger)
│  ├─ chamber_body        (das alte chamber-Cube)
│  └─ chamber_lid         (NEU: Scharnier bei (0, 8, −1.5) — der Kammer-Snap-Bone)
└─ plunger
```

| Anim | Länge | Loop | Inhalt |
|---|---|---|---|
| `idle` | 4.0 s | ja | Root-Wiege ±1°, Nadel-Zittern ±0.35°, Vitae-Atmen, Deckel klappert 2× minimal auf (3.5°/2.2°), Backen wandern ±0.22, Anzeige zwei Herzschläge (≤ 1.18) |
| `equip` | 0.55 s | nein | Root aus −25° Yaw, Nadel richtet sich auf, Kolben fällt aus 1.2 px, Deckel setzt sich, Backen fahren aus 0.55 ein, Vitae + Anzeige zünden |
| `channel` | 3.0 s | ja | Deckel öffnet in **drei Ratschenstufen** (9°/17°/24°, je mit Rückzucker), Backen wandern gleichmäßig auf 0.55 aus, Kammer schaudert ab t = 2.2, Anzeige eskaliert 1.12 → 1.18 → 1.24 → 1.28 → 1.30, Kolben zieht auf 2.5 |
| `extract` | 0.75 s | nein | Root-Rückstoß −16°, Nadel sticht 0.75 px, Kolben schnappt runter, **Deckel knallt aus 29° auf −2° zu und federt 4.5/−1.2/2/−0.6/0.8 nach**, Backen kneifen, Vitae blitzt 1.65 und sackt auf 0.40, Anzeige kollabiert auf 0.22 |
| `refuse` | 0.6 s | nein | **Kopfschütteln: Yaw ±19/−21/+17/−12/+7/−3°**, Root hebt und weicht zurück, Nadel peitscht gegenläufig, Deckel klappert auf, Backen schnappen, Anzeige blitzt zweimal fast auf 0 |

**Kammer-Snap (Zensus-Kernforderung):** vorher war die Kammer EIN Cube — ein „Snap" wäre
nur ein Wackeln gewesen. Jetzt gibt es einen echten Scharnierdeckel; dass er über den
`channel` sichtbar aufsteht (25°) ist die Voraussetzung dafür, dass das Zuschnappen im
`extract` überhaupt eine Amplitude hat. Backen und Anzeige sind die Sekundär-Bewegung,
die den Schlag lesbar macht.

**Refuse-Verstärkung, gemessen gegen `HEAD~`:**

| Achse | vorher (HEAD) | nachher | Faktor |
|---|---|---|---|
| Roll Z | 6.00° | 7.00° | 1.17× |
| Yaw Y | — (0°) | **21.00°** | neu, 7 Nulldurchgänge |
| Pitch X | — (0°) | 5.00° | neu |
| Länge | 0.4 s | 0.6 s | 1.5× |

Vorher war es ein reines Z-Rollen — im Item-Render liest das als „Kippen", nicht als
„Nein". Jetzt dominiert die Y-Achse mit 21° und sieben Nulldurchgängen: ein echtes
Kopfschütteln mit abklingender Amplitude.

### 4.3 Der Ungelesen-Zustand (`ItemsAClientExtensions`)

Da es kein Flag gibt (§1.1), leitet MD2 eines ab:

```
knowledgeScore = Σ tierFor(id) über alle eclipse:-Entity-Ids
               + Σ grantedTier() über alle Collections-Einträge
               + discoveredItemCount()
unread         = knowledgeScore > readScore
readScore     := knowledgeScore, sobald HandbookScreen offen ist
```

Vier Eigenschaften, die den Unterschied zwischen „funktioniert" und „nervt" machen:

1. **Kosten.** Neu berechnet wird nur, wenn eine der beiden `generation()`-Zähler sich
   ändert. Ein normaler Tick kostet zwei `int`-Vergleiche.
2. **Login-Schonfrist.** Der Server schiebt Bestiary, Collections und Item-Lexikon als
   drei getrennte Payloads über mehrere Ticks. Eine naive Baseline läse das als frische
   Entdeckungen. Deshalb wird der Score während der ersten **100 t** nach Erscheinen des
   Spielers bei JEDER Änderung neu geeicht.
3. **Fällt-leise.** Sinkt der Score jemals (Logout-Wipe, Collections-Config-Reload),
   wird die Baseline nachgezogen statt „unread" zu schreien.
4. **Respawn ≠ gelesen.** `ClientPlayerNetworkEvent.Clone` setzt nur die Hand-Kanten
   zurück, NICHT die Baseline — sonst würde Sterben das Ledger stillschweigend als
   gelesen markieren.

Die Registry-Iteration über `BuiltInRegistries.ENTITY_TYPE` ist der einzige Weg, die
Bestiary-Ids von außen aufzuzählen (die Liste selbst ist privat in `BestiaryTab`). Sie
ist eine echte Obermenge, unbekannte Ids scoren 0 — ein künftiger Mob wird also am Tag
seiner Auslieferung mitgezählt, ohne dass hier jemand nachzieht.

### 4.4 Die `equip`-Kantenerkennung

GeckoLibs Trigger-Pfad ist server-seitig; Ziehen ist aber rein kosmetisch. Im
4.9.2-Bytecode verifiziert: `SingletonGeoAnimatable#triggerAnim` kürzt auf
`AnimatableInstanceCache#getManagerForId` ab, wenn die übergebene Entity in einem
Client-Level lebt. Die Instanz-Id MUSS `GeoItem.getId(stack)` sein (**nicht**
`getOrAssignId` — server-only): genau das füttert `GeoItemRenderer#getInstanceId` dem
Renderer, inklusive des geteilten `Long.MAX_VALUE`-Eimers für Stacks, denen der Server
noch keine Id vergeben hat.

Kantenerkennung pro Hand und über `Item`-Identität. Das Artefakt bekommt zusätzlich
einen Trigger beim Öffnen des Inventars: es lebt gepinnt in
`ArtifactSlotLock.ARTIFACT_SLOT` und wird praktisch nie gehalten — das Inventar ist der
einzige Moment, in dem ein Spieler es überhaupt ansieht.

---

## 5 Validierung

Alles wörtlich aus der Konsole.

### 5.1 `validate_geo.py` — 4/4 PASS, 0 Errors, 0 Warnings

Wörtlich, nur der ausgedruckte Bone-Baum und die Notiz „no 'head' bone — auto
head-tracking unavailable (fine for non-tracking mobs)" (bei Items immer) sind gekürzt:

```
=== GEO  src/main/resources/assets/eclipse/geo/item/arm_artifact.geo.json
    identifier geometry.arm_artifact  canvas 64x64  12 bones  14 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/item/arm_artifact.animation.json
    'animation.arm_artifact.idle': loop=True length=6.0 bones=10 keyframes=21 last_key=6.0s
    'animation.arm_artifact.idle_unread': loop=True length=3.0 bones=10 keyframes=42 last_key=3.0s
    'animation.arm_artifact.equip': loop=False length=0.6 bones=6 keyframes=25 last_key=0.6s
    'animation.arm_artifact.open': loop=False length=1.0 bones=10 keyframes=76 last_key=1.0s
  -> PASS (0 error(s), 0 warning(s))

validate_geo: 2/2 file(s) passed — all good

=== GEO  src/main/resources/assets/eclipse/geo/item/heart_extractor.geo.json
    identifier geometry.heart_extractor  canvas 64x64  11 bones  12 cubes
  -> PASS (0 error(s), 0 warning(s))

=== ANIM src/main/resources/assets/eclipse/animations/item/heart_extractor.animation.json
    'animation.heart_extractor.idle': loop=True length=4.0 bones=9 keyframes=37 last_key=4.0s
    'animation.heart_extractor.equip': loop=False length=0.55 bones=8 keyframes=31 last_key=0.55s
    'animation.heart_extractor.channel': loop=True length=3.0 bones=9 keyframes=66 last_key=3.0s
    'animation.heart_extractor.extract': loop=False length=0.75 bones=9 keyframes=63 last_key=0.75s
    'animation.heart_extractor.refuse': loop=False length=0.6 bones=7 keyframes=47 last_key=0.6s
  -> PASS (0 error(s), 0 warning(s))

validate_geo: 2/2 file(s) passed — all good
```

### 5.2 Painter-Determinismus + Compile

```
== run 1 ==
616fb8359c8df00bca94aee4d4f8e6b6  .../item/artifact/arm_artifact.png
dcca04da9921331f6e23ac4f1fe42c7d  .../item/artifact/arm_artifact_glowmask.png
c61aa2587b483b97caf449c6e0db9156  .../item/extractor/heart_extractor.png
5ff30abe6d280075705e133fe593c8ea  .../item/extractor/heart_extractor_glowmask.png
== run 2 ==
616fb8359c8df00bca94aee4d4f8e6b6  .../item/artifact/arm_artifact.png
dcca04da9921331f6e23ac4f1fe42c7d  .../item/artifact/arm_artifact_glowmask.png
c61aa2587b483b97caf449c6e0db9156  .../item/extractor/heart_extractor.png
5ff30abe6d280075705e133fe593c8ea  .../item/extractor/heart_extractor_glowmask.png
```

```
$ ./gradlew compileJava --console=plain
> Task :compileJava
BUILD SUCCESSFUL in 2s
```

Canvas-Konsistenz (`AutoGlowingTexture`-Zwang): Albedo und Glowmask je 64×64 für beide
Items ✓.

### 5.3 Offline-Messharness (Zahlen statt Augenmaß)

Wie MD3 habe ich GeckoLibs Transform-Semantik nachgebaut (`/tmp/md2/`, **nicht
committet**): `gecko.py` (Pose-Evaluator), `measure.py` (numerische Prüfungen),
`render.py`/`make_sheets.py` (Offline-Rasterizer mit Z-Buffer und additivem Glowmask,
für Kontaktbögen). Damit sind die Kurven geprüft, ohne einen `runClient` zu starten.

| Prüfung | arm_artifact | heart_extractor |
|---|---|---|
| Loop-Naht `idle`, max ‖M(0) − M(L)‖ | **2.7 e-15** | **2.0 e-16** |
| Loop-Naht zweiter Loop | `idle_unread` **2.0 e-15** | `channel` **2.725** — by design, §6.2 |
| One-Shots enden in Ruhelage | `equip` **0.000**, `open` **0.000** | `equip`/`extract`/`refuse` je **0.000** |
| Worst-Case-Ruck beim Rückfall an den Base-Loop | **3.775 px** (`glow_ledger`) | **0.399 px** (`glow_vitae`) |
| Kanal-Parität der beiden Base-Zustände | keine einseitigen Kanäle | keine einseitigen Kanäle |

Der Rasterizer misst außerdem den Slot-Bedarf (Sweep = Hüllkurve über die ganze Anim,
Frame = schlechtester EINZELbild-Kasten, und nur der muss passen):

| Anim | Sweep | Frame | 16-px-Slot |
|---|---|---|---|
| `arm_artifact.idle` | 6.3 × 14.3 | 6.0 × 13.9 | passt |
| `arm_artifact.idle_unread` | 6.7 × 15.1 | 6.2 × 14.8 | passt |
| `arm_artifact.equip` | 7.5 × 16.7 | 7.3 × 15.8 | passt |
| `arm_artifact.open` | 7.6 × 16.5 | 7.6 × **16.2** | **überschreitet bewusst** |
| `heart_extractor.*` | ≤ 5.6 × 16.0 | ≤ 4.8 × 14.8 | passt |

`open` ist die einzige Überschreitung (1.3 %) — und die einzige Anim, die nie im
GUI-Slot zu sehen ist: sie feuert genau dann, wenn der `HandbookScreen` den Bildschirm
übernimmt. Deshalb bleiben beide `models/item/*.json` unangetastet: eine kleinere
Display-Scale würde die anderen sieben Zustände schrumpfen, um einen zu retten, den
niemand sieht.

Weitere Extractor-spezifische Messungen:

| Prüfung | Ergebnis |
|---|---|
| `channel`(t = 3.0) → `extract`(t = 0.0), max ‖ΔM‖ | **1.7 e-16** — nahtlos |
| Deckel↔Körper-Durchdringung (im Frame der `chamber`, nicht in Welt-Y) | `idle`/`channel`/`refuse` **0.000 px**; `equip` +0.062; `extract` +0.102 |
| `refuse`-Achsenanalyse | siehe §4.2 |

0.1 px Deckelüberlappung auf dem Höhepunkt des Snaps sind ≈ 2.5 % der Deckelhöhe und im
Item-Render subpixelig — das ist die Dichtung, nicht ein Fehler. Reduzieren hieße den
Überschwung wegnehmen, der den Snap überhaupt als Schlag lesen lässt.

### 5.4 Molang-Zyklus-Gesetz

Jede Molang-Dauerrotation und jeder `math.sin` läuft über die Loop-Länge ein ganzes
Vielfaches von 360° durch (MD3-Report §2):

| Anim | Ausdruck | Länge | Durchlauf |
|---|---|---|---|
| `arm_artifact.idle` | `* 60`, `* 120`, `* 180` | 6.0 s | 360° / 720° / 1080° |
| `arm_artifact.idle_unread` | `* 120`, `* 240` | 3.0 s | 360° / 720° |
| `heart_extractor.idle` | `* 90`, `* 180`, `* 2160` | 4.0 s | 360° / 720° / 8640° |
| `heart_extractor.channel` | `* 1440` | 3.0 s | 4320° |

Das ist auch der Grund für die 2.7 e-15/2.0 e-16 in §5.3 — die Nähte sind rechnerisch
exakt, nicht nur „nah dran".

---

## 6 Vier Funde, die den Entwurf geändert haben

### 6.1 Der Ledger präzediert seit `HEAD` — dasselbe Gesetz wie MD3 §6.1, anderes Item

Das ist **kein Fehler meines Entwurfs, sondern ein bestehender Bug**: in `HEAD` trägt
`glow_ledger` die statische Rest-Rotation `[45, 0, 45]` **und** bekommt in
`animation.arm_artifact.idle` die Molang-Y-Drehung `query.anim_time * 60`. GeckoLib
rotiert Z → Y → X (`RenderUtil.rotateMatrixAroundBone`), die Y-Drehung läuft also VOR
dem 45°-Kipp — die Mote eiert statt zu kreiseln.

Fix: `ledger` (Träger) → `ledger_spin` (nur die Animation) → `glow_ledger` (nur der
statische Kipp). Dass MD3 dieselbe Falle beim Sigil-Ring gefunden hat, macht es zum
Muster, nicht zum Zufall: **statischer Bone-Kipp und animierte Drehung nie auf
demselben Bone.** Wer im Repo nach weiteren Fällen sucht: jeder Bone mit `"rotation"`
im `.geo.json`, der auch in einer `.animation.json` auftaucht, ist verdächtig.

### 6.2 `channel` hat eine Loop-Naht von 2.7 px — und die ist richtig so

`channel` läuft in ein Plateau (Kolben 2.5, Deckel 25°, Backen 0.55, Anzeige 1.30) und
springt beim Loop zurück auf Null. Das sieht nach Bug aus, ist aber die Auslegung —
schon in `HEAD`: **`USE_DURATION_TICKS = 60` = 3.0 s = die Loop-Länge.** Der Kanal endet
mit dem Item-Gebrauch, `finishUsingItem` feuert `extract`, und `extract` startet exakt
auf dem Plateau (gemessen: 1.7 e-16 Abweichung). Der Loop-Punkt bei t = 3.0 wird im
Spiel nie erreicht; das Plateau von 2.6 bis 3.0 s ist die Toleranz für den 4-Tick-Blend
des Base-Controllers.

**Wenn jemand `USE_DURATION_TICKS` ändert, muss `animation_length` von `channel`
mitziehen** — sonst rastet die Ladeanimation entweder vorzeitig zurück oder erreicht das
Plateau nicht, aus dem `extract` startet.

### 6.3 Die Vitae-Anzeige war ein orangener Klotz — zwei Fehler auf einmal

Erster Entwurf: `glow_gauge` als 1×1×1-Würfel, `shadeless`, mit Scale-Peaks bis 2.6.
Im Offline-Render las das als leuchtender Klotz, der im `extract` die halbe Kammer
verdeckt. Zwei getrennte Ursachen:

1. **Zu wenig Fläche, zu viel Skalierung.** Ein 1-px-Würfel braucht 2.6× Skalierung, um
   überhaupt aufzufallen — und dann ist er ein Klotz. Fix: 3×2×1 (eine Anzeige mit
   Blende und Balken), Peaks runter auf 1.18 (`idle`) / 1.30 (`channel`) / 1.42
   (`extract`) / 1.32 (`refuse`).
2. **Jeder `glow_*`-Bone bekommt automatisch einen Albedo-Copy in die Glowmask.**
   `AutoGlowingGeoLayer` addiert die also oben drauf — inklusive der Messingblende. Fix:
   ein expliziter `gauge_glow`-Painter, der NUR den Füllbalken emittiert, und
   `gauge_dial` ist bewusst nicht mehr `shadeless`, damit die Blende Metall bleibt.

Merksatz: **ein `glow_*`-Bone, der teils Metall und teils Licht ist, braucht immer einen
eigenen Glow-Painter.** Der Automatik-Copy kennt den Unterschied nicht.

### 6.4 `ANIM_EQUIP` als Konstante in der Client-Klasse hätte den Dedicated Server geladen

Der `equip`-Trigger lebt client-seitig, also lag die Konstante zuerst in
`ItemsAClientExtensions`. `public static final String` wird vom Compiler aber
**inline-gefaltet** — die Referenz aus `ArmArtifactItem`/`HeartExtractorItem` hätte die
Client-Klasse beim Laden der Item-Klasse mitgezogen, also auf dem Dedicated Server.
Fix: die Konstante wohnt jetzt in den Item-Klassen, die Client-Klasse liest sie von
dort. (Der lazy vollqualifizierte Renderer-Verweis in `registerControllers` ist davon
nicht betroffen — der wird erst beim Ausführen des Predicates aufgelöst.)

Nebenbei geprüft und für unkritisch befunden: `@EventBusSubscriber` ohne `bus =`.
NeoForge 21.1s `AutomaticEventSubscriber` routet jeden Listener anhand seines
Event-Typs auf den richtigen Bus, das Attribut ist deprecated. Eine Klasse darf also den
MOD-Bus-Renderer-Hook und die GAME-Bus-Tick-Hooks gemeinsam halten.

---

## 7 Offene Punkte

### 7.1 Der Seiten-Fächer ist für den lokalen Spieler kaum sichtbar

`open` feuert genau dann, wenn `HandbookScreen` aufgeht — und der deckt den Bildschirm
ab. Sichtbar ist der Fächer damit für **andere** Spieler (Drittperson) und in dem
Frame-Fenster vor dem Screen-Wechsel. Deshalb trägt `idle_unread` die eigentliche
Rückmeldung an den Besitzer: die Atmung läuft, solange etwas ungelesen ist, und das ist
der Zustand, den der Spieler im Inventar sieht.

Wer das ändern will, braucht eine Verzögerung zwischen Trigger und Screen-Öffnung in
`client/ArtifactScreenOpener` — **fremde Datei**, deshalb hier nur notiert.

### 7.2 Keine neuen Lang-Keys

MD2 hat **0** neue übersetzbare Strings hinzugefügt (reine Anim-/Asset-/Client-Arbeit,
keine Tooltips, keine Chat-Meldungen). Es gibt deshalb bewusst KEIN
`docs/plans_v3/langdrop/MD2-ITEMSA.json` — eine leere Datei wäre nur Rauschen für den
Lang-Audit.

### 7.3 „Ungelesen" ist die Sicht des Betrachters, nicht des Trägers

Nichts am Ungelesen-Zustand ist genetzt. Das Artefakt eines fremden Spielers atmet also
nach dem Ledger des Zuschauers. In der Praxis harmlos: das Artefakt ist im Inventar
gepinnt und kann nur vorübergehend in einer Hand liegen. Eine korrekte Lösung bräuchte
eine synchronisierte Komponente — das wäre eine Änderung an `EclipseItems`/Payloads und
gehört nicht MD2.

### 7.4 Nicht in-game gegengeprüft

Verifiziert ist alles offline (Messharness §5.3 + Kontaktbögen). Ein `runClient` ist in
dieser Session nicht gelaufen — die VM teilen sich parallel MB1–MB6 und MD1. Das
Test-Rezept unten ist entsprechend das, was ein Mensch noch abhaken sollte.

---

## 8 Test-Rezept

Vorbereitung: `/give @s eclipse:heart_extractor`; das Artefakt liegt bereits gepinnt im
Inventar.

1. **`idle_unread` vs. `idle`** — Inventar öffnen und das Artefakt ansehen, dann den
   Handbook öffnen und wieder schließen. Vorher: der Unterarm atmet sichtbar (4 %) mit
   3-s-Periode und die Mote schlägt doppelt. Nachher: ruhige 6-s-Wiege. Danach einen
   neuen Mob töten (Bestiary-Tier steigt) → die Atmung muss zurückkommen.
2. **Login-Schonfrist** — neu einloggen und das Artefakt SOFORT ansehen: es darf NICHT
   atmen (der Sync-Burst ist keine Entdeckung). Erst eine echte neue Entdeckung danach
   löst aus.
3. **Respawn** — sterben, während etwas ungelesen ist. Nach dem Respawn muss die Atmung
   weiterlaufen (Sterben markiert nichts als gelesen).
4. **`equip`** — Extractor in die Hotbar legen und die Slots durchschalten: beim
   Auswählen dreht sich der Zapfhahn einmal ein. Beim Öffnen des Inventars macht das
   Artefakt seine 360°-Mote-Drehung.
5. **`open` + Seiten-Fächer** — am besten zu zweit: Spieler A rechtsklickt das Artefakt
   im gepinnten Slot, Spieler B sieht die vier Blätter auffächern. Solo nur im
   Frame-Fenster vor dem Screen (siehe §7.1).
6. **`channel` → `extract`** — mit ≥ 3 Herzen den Extractor 3 s halten: Deckel öffnet in
   drei Ratschenstufen, Backen fahren aus, Anzeige eskaliert. Beim Auslösen knallt der
   Deckel zu und federt nach — der Übergang muss RUCKFREI sein (das ist die 1.7 e-16 aus
   §5.3, in-game gegenzuprüfen).
7. **`refuse`** — mit genau 2 Herzen rechtsklicken: deutliches Kopfschütteln um die
   Hochachse, nicht nur ein Kippen.
8. **GUI-Check** — beide Items im Inventar: nichts darf im 16-px-Slot abgeschnitten
   werden (Zahlen in §5.3; einzige gewollte Ausnahme ist `open`, das im Slot nie läuft).
