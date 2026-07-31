# MB4 — Glitch-Trio (glitched_husk + glitched_hound + glitched_tick)

**Auftrag:** `MOB_ITEM_CENSUS.md` §5 Welle M-B Zeile MB4 — (a) Shard-Detach-Beats:
`shard_torso`/`head_shard`/`jaw_shard` bekommen glitch_blink-artige Scale-Pops +
1-Frame-Versatz-Keyframes ("Datenfehler"-Look), (b) `tick_latch` auf 0.8 s strecken
mit Bein-Klammer-Kette, (c) Familien-Kohärenz-Pass: alle drei nutzen DIESELBE
Jitter-Frequenz, zentral definiert in `glitch_lib.py`, (d) Basis-Anims
(idle/walk/attack/death) aller drei auf M-A-Niveau.

**Datei-Besitz (exklusiv, §5-G1):** `entity/glitch/*`, `client/entity/glitch/*`
(beide NUR gelesen — null Java-Änderungen), `geo/animations/textures` aller drei
Glitch-Mobs inkl. Alt-Skins, `scripts/geckolib_gen/mobs/glitched_{husk,hound,tick}.py`
+ `glitch_lib.py`, `docs/uv/glitched_*.md`, dieser Report.

**Nicht angefasst:** FROZEN-Basen (`GlitchedMonster` ist NICHT frozen, blieb aber
unverändert — kein Java nötig), `GlitchedGeoRenderer` (Flicker/Pose-Pop tut, was die
Anims brauchen), `validate_geo.py`/`paint_lib.py`, `tools/photon/**`, `fx/**`,
Lang-Dateien (kein neuer Key entstanden → **kein Langdrop nötig**), `glitched_wanderer*`
(MB5-Besitz — der teilt nur die Optik, nicht die Dateien).

---

## 0. Verifizierte Grundlagen (nichts aus dem Gedächtnis)

### 0.1 Java-Kontrakt der drei Entities (gelesen, nicht geändert)

* **Death-Fenster** (`deathAnimTicks()`-Overrides): husk **30 t = 1.5 s**, hound
  **30 t = 1.5 s**, tick **20 t = 1.0 s** — die Anim-Längen müssen exakt darauf
  liegen (tun sie, §4.1).
* **`latch`** (`GlitchedTickEntity`): triggerbares One-Shot auf dem
  `action`-Controller (Transition 0). Erst-Biss triggert, danach **Re-Bite alle
  `LATCH_BITE_INTERVAL_TICKS = 20 t = 1.0 s`**, jeder Re-Bite re-triggert `latch`.
  → Eine 0.8-s-Anim füllt 80 % der Re-Bite-Kadenz und wird NIE abgeschnitten.
  Der 0.2-s-Rest läuft in der Basis-Pose — deshalb endet die neue Latch-Anim
  bewusst in einer Teil-Klammer-Pose: der 1-Frame-Snap zurück in idle IST die
  Familien-Grammatik (Datenfehler), und der nächste Biss klammert sofort neu.
* **`glitch_blink`**: husk/hound triggern es aus `GlitchedMonster`
  (Cooldown-Logik), der Tick hat bewusst KEIN blink (Zwerg-Mob, stattdessen
  Ganzkörper-Textur-Flicker) — daher bekommt der Tick seine Datenfehler-Beats in
  `latch`/`death` statt in einem Blink.
* **Renderer** (`GlitchedGeoRenderer`): 2–4-t-Textur-Flicker auf `_alt.png` +
  Pose-Pops. Kein Java-Code referenziert irgendeinen Bone-Namen
  (rg über `src/main/java`: 0 Treffer für `legs_right|legs_left|shard_torso|
  head_shard|jaw_shard|glow_core|carapace`) → das Tick-Re-Boning (§2.4) ist
  Java-seitig folgenlos.

### 0.2 Ist-Bestand HEAD (gemessen, nicht geschätzt)

| Mob | Geo | Anims (Länge / Bones / Keys+Kurven) |
|---|---|---|
| husk | 11 Bones / 11 Cubes | idle 3.0s/9b/55, walk 1.0s/9b/74, attack 0.5s/5b/19, blink 0.4s/3b/22, death 1.5s/11b/40 |
| hound | 16 Bones / 16 Cubes | idle 2.5s/10b/31, walk 0.6s/13b/37, attack 0.45s/11b/69, blink 0.5s/10b/62, death 1.5s/13b/48 |
| tick | **8 Bones** / 13 Cubes | idle 2.0s/6b/15, walk **0.35s**/6b/19, attack 0.3s/2b/13, **latch 0.5s**/6b/22, death 1.0s/6b/23 |

### 0.3 Gefundene Bugs in HEAD (die eigentliche Rechtfertigung des Kohärenz-Passes)

**(a) 14 Molang-Loop-Nähte offen** — `F × Länge` kein Vielfaches von 360°, d. h.
die Sinus-Kanäle springen an jeder Loop-Grenze (Skript-Output, HEAD):

```
husk  idle body.rotation:      90 °/s auf 3.0s-Loop (Rest 90°)
husk  idle arm_right.rotation: 110 °/s auf 3.0s-Loop (Rest 30°)  [2 Kanäle]
husk  idle arm_left.rotation:  110 °/s auf 3.0s-Loop (Rest 30°)
hound idle body.rotation:      100 °/s auf 2.5s-Loop (Rest 110°)
hound idle neck_shard.position: 150 + 95 °/s (Rest 15° / 122°)
hound idle jaw.rotation:       130 °/s (Rest 35°)
hound idle spine_shard_a/b/c:  130/120/140 °/s (Rest 35°/60°/10°)
hound idle tail.rotation:      160 °/s (Rest 40°)
tick  idle legs_right/left:    200 °/s auf 2.0s-Loop (Rest 40°)
tick  walk carapace_r/l:       1030 °/s auf 0.35s-Loop
```

**(b) Frequenz-Zoo statt Familie** — HEAD-Frequenzmengen pro Mob:
husk `{90, 110}`, hound `{95, 100, 120…160, 600, 1200}`, tick `{180, 200, 1030}`.
**Kein einziger gemeinsamer Takt** — genau das Gegenteil der Zensus-Forderung.

**(c)** Tick-`walk` 0.35 s: auf dieses Raster passt ÜBERHAUPT kein ganzzahliger
Familien-Takt (720 × 0.35 = 252° ≠ k·360°) — die Loop-Länge selbst war das Problem.

**(d)** Tick-Beine als 2 Reihen-Bones (je 3 Cubes) — eine "Bein für Bein"-Kette
war mit HEAD-Geo schlicht nicht animierbar.

**(e) Doku-Drift** in `docs/uv/`: husk-Doc unterschlug den `jaw_shard`-Bone
("10 bones"), hound-Doc unterschlug alle drei `spine_shard_*` ("13 bones/13 cubes"
statt 16/16). Beides gefixt (MB4-Besitz).

---

## 1. Plan (vor der Umsetzung festgelegt)

### 1.1 Der Familien-Jitter-Takt (Entscheidung)

**`GLITCH_JITTER_HZ = 2.0` → `GLITCH_JITTER_FREQ = 720 °/s`, Periode 0.5 s** —
zentral in `glitch_lib.py`. Begründung:

* 2 Hz ist schnell genug für "nervöses Vibrieren", langsam genug, dass es bei
  20 tps nicht zu Alias-Brei wird (4 Server-Ticks pro Periode).
* Periode 0.5 s ⇒ **jede Loop-Länge auf dem 0.5-s-Raster schließt den Takt
  nahtlos**: husk 3.0/1.0, hound 2.5/0.5, tick 2.0/0.5. (Tick-walk deshalb von
  0.35 s → 0.5 s umgetimt, hound-walk 0.6 s → 0.5 s.)
* Feinrasseln als **ganzzahlige Harmonische** (1440 = 4 Hz) erlaubt — gleicher
  Takt, eine Oktave höher.
* Langsame Sway-Kanäle bleiben **pro Mob frei** (Persönlichkeit!), müssen aber
  ihren eigenen Loop schließen (F = k·360/L): husk 120, hound 144/288, tick 180.
  Familie = gleicher Tremor, Individuum = eigenes Schwanken.

Erzwungen wird das nicht per Doku, sondern per Code: `assert_family_jitter()` in
`glitch_lib.py` läuft **am Anfang jedes der drei Painter-Driver** und wirft bei
Verstoß `AssertionError` — ein gedrifteter Sheet bricht den deterministischen
Painter-Lauf laut ab (Checks: 0.5-s-Raster, Molang-Naht-Schluss, Harmonik aller
Jitter-Klasse-Frequenzen ≥ 300 °/s, mind. ein 720er-Kanal pro Loop).

### 1.2 Datenfehler-Grammatik (über alle drei identisch)

Ein "Beat" = Bone springt in **einem Keyframe-Schritt von 0.05 s (= exakt 1
Server-Tick)** in eine falsche Pose (Position ±1–2.5 px, Rotation bis 40°, Scale
gestaucht 1.3/0.7), hält 1–6 Frames, snappt in 0.05 s zurück. Husk-Shards und
Hound-Shards nutzen dieselben Stauch-Verhältnisse; der `glow_seam`/`glow_core`
flare-t auf jedem Beat mit.

### 1.3 Latch-Kette, Basis-Polish

Latch 0.8 s: Aufbäumen (0–0.14), dann klammern **6 Beine einzeln im
0.1-s-Stagger** (heben −12°/−24° → Überschwinger +22° → Griff +18°), Körper hunched
17–19°, `glow_core` als Crescendo (Flare-Kaskade bis 1.9× + Stolper-Dip bei 0.7).
Basis-Anims: FK-Bodenkontakt messen (MA6-Standard), tote Bones bespielen,
walk-Gangarten neu (husk Schlurf-Snap, hound Trab mit Suspension, tick Tripod).

---

## 2. Umsetzung

### 2.0 Geänderte Dateien (8 + Report)

| Datei | Was |
|---|---|
| `scripts/geckolib_gen/mobs/glitch_lib.py` | +`GLITCH_JITTER_HZ/FREQ/PERIOD`, +`assert_family_jitter()` (89 neue Zeilen) |
| `scripts/geckolib_gen/mobs/glitched_{husk,hound,tick}.py` | je 1 Zeile: Gate-Aufruf in `main()` vor dem Painten |
| `geo/entity/glitched_tick.geo.json` | `legs_right/left` → Reihen-Parents mit je 3 Einzel-Bein-Kindern `*_f/m/b` (8 → 14 Bones, Cubes/UVs unverändert) |
| `animations/entity/glitched_husk.animation.json` | Shard-Detach-Beats überall, Naht-Fixes, walk/attack/blink/death-Polish |
| `animations/entity/glitched_hound.animation.json` | Shard-Pops (inkl. `spine_shard_*`, vorher tot in blink/death), walk 0.6→0.5 s, Naht-Fixes |
| `animations/entity/glitched_tick.animation.json` | latch 0.5→0.8 s Klammer-Kette, walk 0.35→0.5 s Tripod, idle/attack/death auf Einzel-Beinen |
| `docs/uv/glitched_{husk,hound,tick}.md` | Drift-Fixes (§0.3e) + neue Bein-Bone-Tabelle |

Texturen: **byte-identisch zu HEAD** (Painter-Output, §4.2) — MB4 hat kein Pixel
verändert, nur den Gate davorgeschaltet.

### 2.1 Husk — Shard-Detach-Beats (Auftrag a)

| Anim | HEAD | MB4 |
|---|---|---|
| idle | 3.0s / 9b / 55kf | 3.0s / 9b / **78kf** |
| walk | 1.0s / 9b / 74kf | 1.0s / **11b** / 90kf |
| attack | 0.5s / 5b / 19kf | 0.5s / **9b** / **63kf** |
| glitch_blink | 0.4s / 3b / 22kf | 0.4s / **5b** / **72kf** |
| death | 1.5s / 11b / 40kf | 1.5s / 11b / **69kf** |

* **idle:** `head_shard`/`shard_torso` tragen den 720er-Dauer-Tremor (Molang-Rotation
  ±1.2–1.8°, phasenversetzt 120°/240°); darauf 4 Beat-Cluster — 0.5 s
  (`head_shard` −1 px-Pop synchron mit `jaw_shard`-Dip), 0.95 s (Kopf-Snap + Arm-Zuck),
  1.4–1.75 s (der große: `jaw_shard` klappt 14° auf + Scale 1.22/0.8, `shard_torso`
  −1.5 px + Stauchung, `glow_seam`-Flare 1.35×), 2.2–2.6 s (`head_shard`-Drift mit
  Scale 1.18/0.85 — der einzige LANGE Halt, damit nicht alles metronomisch tickt).
* **walk (Schlurf-Snap):** Beine halten Stride-Posen und SNAPPEN in 0.05 s um
  (Teleport-Schritt); Root-x-Ruckler asymmetrisch (+0.5/−0.3). Shard-Beats sitzen
  auf den Fußwechseln (0.22–0.32 / 0.72–0.82). `jaw_shard` rattert als einziger auf
  der 1440er-Oktave (±0.15 px) — das Feingliedrigste rasselt am schnellsten.
* **attack:** Windup −165° Arm, auf dem Hit (0.3 s) reißen ALLE drei Shards für
  1 Frame aus (Torso −1.8 px/+14° y, danach `head_shard` 1 Frame VERSETZT bei
  0.35 s — der Fehler pflanzt sich durchs Rig fort), `glow_seam` 1.5×.
* **glitch_blink:** Kaskade mit 1-Frame-Versatz: `shard_torso` reißt bei 0.05 aus
  (Scale 1.3/0.7), `head_shard` folgt bei 0.1 (Scale 1.25/1.25/0.8 — QUER gestaucht,
  nicht gleich), `jaw_shard` hängt ab 0.05 ganze 3 Frames falsch (−1.6 px). Root
  wirft Skalen-Pumpen 1.07/0.93 → 0.9/1.12 darunter.
* **death:** Kollaps friert bei 0.6–0.8 s in einer Glitch-Standbild-Sequenz ein
  (alle drei Shards nacheinander 1-Frame-Ausreißer bei 0.65/0.7/0.75), dann
  De-Rez-Drift: Shards sinken mit Scale 0.88–0.9 ab, `glow_seam` plattet auf
  2.4×/0.3× aus (Scanline-Kollaps).

### 2.2 Hound — Shard-Pops + Trab (Auftrag c/d)

| Anim | HEAD | MB4 |
|---|---|---|
| idle | 2.5s / 10b / 31kf | 2.5s / 11b / 45kf |
| walk | **0.6s** / 13b / 37kf | **0.5s** / **16b** / 40kf |
| attack | 0.45s / 11b / 69kf | 0.45s / **16b** / **104kf** |
| glitch_blink | 0.5s / 10b / 62kf | 0.5s / **15b** / **139kf** |
| death | 1.5s / 13b / 48kf | 1.5s / **15b** / **84kf** |

* **idle:** Sway-Kanäle auf nahtschließende 144/288 umgestimmt (§0.3a);
  `hips_shard` + `spine_shard_a/b/c` sind jetzt 720er-Tremor-Träger (Positions-
  Wellen, 120°-Phasenkette die Wirbelsäule entlang) plus 2 Beat-Cluster
  (0.7–1.0 Hüfte+spine_b, 1.25–1.55 Ohr 24°/Scale 1.3).
* **walk = Trab auf 0.5 s:** diagonale Paare (fr+bl / fl+br) catmullrom ±38°,
  Suspension über Root-y (§4.5), `spine_shard_b` rattert 1440, Ohr 1440, Schwanz
  peitscht 720. Die drei vorher in walk TOTEN spine-Shards laufen mit.
* **glitch_blink (Auftrag "Scale-Pops auf Shards"):** 139 Keys — Absacken auf
  −1.6 px (0.05–0.15, Beine knicken ±30–38°), dann Verwerfung: `neck_shard`
  1.25/0.7 → 0.85/1.2 QUER, `hips_shard` 1 Frame versetzt (0.15) mit −22°-Twist,
  `spine_shard_a→b→c` als 1-Frame-Kette (0.05/0.05–0.25/0.25 — der Fehler LÄUFT
  das Rückgrat entlang), Ohr 55° + Gegen-Zuck −18°.
* **death:** Seiten-Kollaps 62°→78° mit Anfangs-Jitter; NEU: alle drei spine-Shards
  reißen beim Aufprall nacheinander aus (0.55/0.6/0.65, je 1 Frame) und driften
  dann mit Scale 0.85 ab — Hüfte twistet −20°→+25° durch.

### 2.3 Tick — Latch-Klammer-Kette (Auftrag b)

| Anim | HEAD | MB4 |
|---|---|---|
| idle | 2.0s / 6b / 15kf | 2.0s / **13b** / 22kf |
| walk | **0.35s** / 6b / 19kf | **0.5s** / **14b** / 31kf |
| attack | 0.3s / 2b / 13kf | 0.3s / **8b** / **43kf** |
| latch | **0.5s** / 6b / 22kf | **0.8s** / **14b** / **109kf** |
| death | 1.0s / 6b / 23kf | 1.0s / **13b** / **62kf** |

* **latch (0.8 s, 109 Keys):** Aufbäumen (Root +1.5 y, Body −22°) → Zubeißen
  (+16°) → **Klammer-Kette: R_f 0.08 → L_f 0.18 → R_m 0.28 → L_m 0.38 → R_b 0.48
  → L_b 0.58**, jedes Bein hebt (−12°x/−24°z), schnappt mit Überschwinger (+22°)
  und settle-t auf +18° Griff; die Reihen-Parents ziehen parallel zu (±6°);
  Mandibel-Kopf mahlt (y ±10° alternierend); ein Ganzkörper-Glitch-Pop bei
  0.4 s (Scale 1.12/0.86); `glow_core` als Crescendo 1.15→1.9× mit Stolper-Dip
  bei 0.7. Endpose = Teil-Klammer (§0.1 — der Snap zurück ist gewollt).
* **walk = Tripod-Gang auf 0.5 s:** Dreibein-Paare (R_f+R_b+L_m gegen L_f+L_b+R_m)
  via 1440er-Molang ±20° x, Reihen-Parents wippen ±4° z, Root skitter-rollt ±4°.
  Vorher: 6 Beine als 2 starre Reihen auf 0.35 s.
* **idle:** 6 Einzel-Beine tasten im 720er-Takt (±3°, 6 Phasen) — das
  Insekten-Nervöse; Carapace-Atmung (180er, nahtschließend) + 720er-Zittern oben
  drauf; Kopf-Ruck-Cluster 0.7/1.45.
* **death:** Flip auf den Rücken (165°→172°) mit Start-Jitter; die 6 Beine
  krallen sich EINZELN ein (Kette 0.3→0.72, gleiche Grammatik wie latch, nur
  nach innen); ein einzelnes Bein (L_m) zuckt bei 0.85–0.93 noch einmal — der
  letzte Prozess stirbt; Carapace-De-Rez 0.92/0.85, `glow_core` 1.7→0.2.
* **Geo-Re-Boning:** `legs_right/left` (je 3 Cubes) → cube-lose Reihen-Parents
  mit Kindern `legs_{right,left}_{f,m,b}` (Pivots an den Bein-Wurzeln ±3 x).
  Cubes, UVs, Pixel: unverändert (Beweis §4.2). Painter-Glob `legs_*` matcht
  alte wie neue Namen.

---

## 3. Familien-Kohärenz-Matrix (der Pass, den Auftrag c meint)

| Element | husk | hound | tick |
|---|---|---|---|
| Tremor-Takt (Jitter-Klasse) | 720 (head_shard, shard_torso, glow_seam) | 720 (hips/spine-Shards, tail, glow_seam) | 720 (6 Beine idle, carapace, glow_core) |
| Feinrassel-Oktave | 1440 (jaw_shard, walk) | 1440 (spine_b, ear, walk) | 1440 (alle Bein-Kanäle, walk) |
| Sway-Tempo (Persönlichkeit) | 120 (träges Pendeln) | 144/288 (canide Unruhe) | 180 (Insekten-Ticken) |
| Loop-Raster | 3.0 / 1.0 s | 2.5 / 0.5 s | 2.0 / 0.5 s |
| Datenfehler-Beat | 0.05-s-Pop + Snap, Scale 1.3/0.7-Familie | identisch, + 1-Frame-Kette übers Rückgrat | identisch, + Bein-für-Bein-Ketten |
| Glow-Antwort pro Beat | `glow_seam`-Flare | `glow_seam`-Flare | `glow_core`-Crescendo |
| Wächter | `assert_family_jitter()` läuft in allen drei Painter-Drivern | ← | ← |

---

## 4. Validierung (alle Beweise aus den ausgelieferten Dateien)

### 4.1 `validate_geo.py` — 6/6 PASS, 0 Errors / 0 Warnings

Alle drei Mobs einzeln UND als Sammel-Lauf (wörtlich, gekürzt auf die Summenzeilen):

```
=== GEO  glitched_husk.geo.json   … 11 bones 11 cubes  -> PASS (0 error(s), 0 warning(s))
=== ANIM glitched_husk.animation.json  … 5 animation(s) -> PASS (0 error(s), 0 warning(s))
=== GEO  glitched_hound.geo.json  … 16 bones 16 cubes  -> PASS (0 error(s), 0 warning(s))
=== ANIM glitched_hound.animation.json … 5 animation(s) -> PASS (0 error(s), 0 warning(s))
=== GEO  glitched_tick.geo.json   … 14 bones 13 cubes  -> PASS (0 error(s), 0 warning(s))
=== ANIM glitched_tick.animation.json  … 5 animation(s) -> PASS (0 error(s), 0 warning(s))
============================================================
validate_geo: 6/6 file(s) passed — all good
```

Anim-Längen gegen die Java-Fenster: husk death 1.5 s = 30 t ✓, hound death 1.5 s
= 30 t ✓, tick death 1.0 s = 20 t ✓, tick latch 0.8 s < 1.0-s-Re-Bite ✓.

### 4.2 Painter-Determinismus — 2× md5-identisch UND byte-identisch zu HEAD

Alle drei Driver 2× gelaufen (12 PNGs inkl. Alt-Skins + Alt-Glowmasks):

```
$ diff /tmp/mb4_run1.md5 /tmp/mb4_run2.md5 && echo OK
DETERMINISM OK: 12/12 identical
```

Nach den finalen Anim-Edits ein dritter Lauf (der Gate liest ja die Anim-Dateien):
wieder 12/12 identisch. Stärkster Beweis: `git status` zeigt **keine einzige
Textur als geändert** — die Painter reproduzieren nach dem Tick-Re-Boning exakt
die committeten Pixel (das `legs_*`-Glob-Argument aus §2.3 ist damit bewiesen,
nicht behauptet).

### 4.3 Der Gate beißt — Negativ-Tests

`assert_family_jitter()` gegen absichtlich korrumpierte Kopien in `/tmp`:

```
[1] positive gate: PASS on real family files
[2] freq 700 statt 720 -> AssertionError:
      …idle: sin freq 700.0 does not close the 3.0s loop (seam pop)
      …idle: jitter-class freq 700.0 is not a harmonic of 720.0
[3] length 2.7 statt 3.0 -> AssertionError:
      …idle: length 2.7s off the 0.5s family jitter grid
```

### 4.4 Loop-Nähte — 14 HEAD-Verstöße → 0

Offline-Checker über alle Loop-Anims der drei Sheets (Keyframes: erster == letzter
Wert UND letzter Key == Länge; Molang: F·L ≡ 0 mod 360):

```
seams: ALL CLOSED | family jitter gate: PASS
```

(HEAD-Stand zum Vergleich: die 14 Molang-Nahtbrüche aus §0.3a.)

### 4.5 Bodenkontakt (Vorwärtskinematik auf der ausgelieferten Geo, 200 Samples/Loop)

| Clip | schlimmstes Schweben des Standfußes | tiefster Punkt | höchster Schwungfuß |
|---|---|---|---|
| husk walk (MB4-Entwurf 1) | **+2.06 px** | +0.14 px (nie am Boden!) | +2.06 px |
| husk walk (MB4 final) | **+0.03 px** | −0.75 px (1-Frame-Snap-Transit) | +0.03 px |
| hound walk (MB4-Entwurf 1) | **+1.12 px** | **+0.66 px (nie am Boden!)** | +2.73 px |
| hound walk (MB4 final) | **+0.47 px** | −0.21 px | +1.43 px (= Trab-Suspension, gewollt) |
| tick walk (MB4 final) | +0.36 px | −0.45 px | +0.66 px |
| husk idle (MB4 final) | +0.15 px | ±0.00 px | — |
| tick idle (MB4 final) | +0.03 px | −0.03 px | — |

(Die Entwurf-1-Zeilen sind die MESSUNG, die den Fix erzwang — HEAD selbst hatte
andere Kurven, aber dieselbe Fehlerklasse: kein Root-y trug die Standphasen.)

Fix: Root-y-Kurven tragen jetzt die Standphasen (husk −1.8 px auf den
Stride-Halten — der Schlurf duckt sich; hound catmullrom −1.3/+0.5 — Tiefpunkt
auf den Diagonal-Stützen, Suspension am Übergang). Der Husk SCHLEIFT die Füße
(beide Füße dauerhaft in Bodennähe) — für einen korrumpierten Husk die richtige
Lesart, und mit +0.03 px steht er statt zu schweben.

### 4.6 `compileJava`

**Nicht gelaufen — bewusst:** MB4 hat null Java-Zeilen geändert (`git diff` über
`entity/glitch/` + `client/entity/glitch/` ist leer, §2.0), und der Working-Tree
enthält parallel in Arbeit befindliche Java-Dateien von MB1–MB6/MD1/MD2 — ein
Build-Ergebnis wäre deren Zwischenstand, nicht MB4s Beweis. Auftragsbedingung
("bei Java-Änderungen") greift nicht.

### 4.7 Polish-Iteration (Selbstkritik-Pässe)

Drei Pässe, vier Befunde, alle nachgezogen:

1. **Husk-walk schwebte +2.06 px** (FK-Messung Pass 2) → Root-y auf die
   Stride-Halten gelegt, jetzt +0.03 px (§4.5).
2. **Hound-walk berührte den Boden NIE** (tiefster Punkt +0.66 px) → Root-y
   −1.3/+0.5 catmullrom, jetzt +0.47/−0.21 px mit echter Trab-Suspension.
3. **UV-Doku-Drift** (husk `jaw_shard`, hound `spine_shard_*` fehlten komplett,
   Bone-Zahlen falsch) → beide Docs korrigiert, Tick-Doc auf die neue
   Bein-Struktur umgeschrieben.
4. Latch-Endpose gegen die Java-Re-Bite-Kadenz gegengelesen (§0.1): 0.8-s-Anim
   in der 1.0-s-Kadenz + Transition-0-Controller ⇒ Endpose als Teil-Klammer
   bestätigt (ein Ausklingen in Neutral hätte die Klammer zwischen den Bissen
   sichtbar gelöst; der End-Snap ist der Familien-Beat).

---

## 5. Offene Punkte / Übergaben

* **Kein Langdrop** (`docs/plans_v3/langdrop/MB4-GLITCH.json` nicht angelegt —
  es entstand kein neuer Lang-Key).
* **Kein FX-Wunsch an B2** aus dieser Welle; falls B2 später Glitch-Body-FX baut:
  die Beat-Anker sind `glow_seam` (husk/hound) bzw. `glow_core` (tick), der
  Familien-Takt ist `GLITCH_JITTER_HZ = 2.0` aus `glitch_lib.py` — FX-Pulse
  sollten auf demselben Takt liegen.
* **runClient-Sichtprüfung** steht aus (Integrator-Smoke nach dem Merge sinnvoll):
  MB4 hat bewusst nicht gegen den halb-fertigen Parallel-Tree gebaut. Alle
  statischen Beweise (0/0-Validierung, Nähte, FK, Determinismus, Gate) liegen vor.
* Die Tick-UV-Doku behauptet weiterhin "no head tracking" — der Validator flaggt
  den `head`-Bone als head-tracked. Ob der Renderer das Tracking nutzt, ist eine
  Java-Frage außerhalb dieses Auftrags; Zeile bewusst nicht angefasst.
