# E8 — GOOBY-Charakter (3D-Rig, Pipeline, Voice, Integration)

**Agent:** EVAL-AGENT E8 · **Repo:** `/workspace` · **Branch:** `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`) @ `8cfc20e0`
**Datum:** 2026-07-25 · **Werkzeuge:** Godot 4.4.1, Blender 4.0.2, xvfb, python (gltf/wave-Parser)
**Repo-Änderungen:** KEINE (`git status` vor und nach dem Lauf sauber). Alle Builds/Kopien/Renders
liefen in `/tmp/e8/` bzw. `/tmp/gooby-godot/eval/E8-shots/`.

---

## 0. Verdict

**GRÜN mit Auflagen.** Die Pipeline ist erstklassig: `build_gooby.sh` reproduziert das eingecheckte
GLB **byte-identisch**, das Asset liegt weit unter Budget (4406 / 8000 Tris), der Contract
(11 Clips / 19 Bones / 14 Shapekeys) stimmt, alle Loop-Nähte sind exakt 0.0, und 438/438 Godot-Tests
sind grün. Das *Modell* ist solide.

Die Probleme liegen **eine Schicht darüber — in der Ansteuerung**: Emotionen, Editor-Morphs und der
Tür-Quetsch-Gag kommen im Spiel nicht so an, wie sie gebaut wurden. Alle vier P1 sind
GDScript-Fixes; das GLB muss dafür **nicht** neu gebacken werden.

---

## 1. Pipeline-Reproduzierbarkeit — ✅ byte-identisch

```
tools/blender/build_gooby.sh /tmp/e8/build /tmp/e8/gooby_rebuild.glb
```

Das Skript nimmt `GLB_OUT` als 2. Argument, der Output ging also nie ins Repo.

| | sha256 | Bytes |
|---|---|---|
| eingecheckt `GOOBY-GODOT/assets/character/gooby.glb` | `9aab915b17c89aa7e9e01b07dfa8ca339b646bf6bfc13ff5631971ea847b1be1` | 434 616 |
| rebuild `/tmp/e8/gooby_rebuild.glb` | `9aab915b17c89aa7e9e01b07dfa8ca339b646bf6bfc13ff5631971ea847b1be1` | 434 616 |

`cmp` → **BYTE-IDENTICAL**. 4 Stufen (Mesh → Rig → Anims → GLB) in ~35 s, keine Fehler.
`PYTHONDONTWRITEBYTECODE=1` verhindert `__pycache__` im Repo — sauber gelöst.
Einzige Meldung: Draco-Lib fehlt (`libextern_draco.so`) — irrelevant, es wird nicht komprimiert exportiert.

---

## 2. GLB-Qualität — ✅ innerhalb aller Budgets

Eigener glTF-Parser: `/tmp/e8/inspect_glb.py`

* **Geometrie:** 1 Mesh, 1 Primitive, 2340 Verts, **4406 Tris** (Budget `TRI_BUDGET = 8000`, 55 % genutzt)
* **Material:** 1 (`GoobyToon`, doubleSided, rough 0.92, metal 0, 1 Palette-Textur 256²)
* **Skin:** 1 Armature, **19 Joints**, saubere Hierarchie `root → hips → spine → chest → head → {jaw, eye.L/R, ear.*.01→02}` + `arm.L/R`, `leg.L/R → foot.L/R`, `tail`
* **Shapekeys:** **14** (8 Emotionen, `blink`, `mouth_open`, `body_squeeze_door`, `eye_width`, `eye_size`, `ear_length`) — exakt `P.SHAPEKEYS`
* **Clips:** **11**, je 57 Kanäle (19 Bones × T/R/S)

### Clip-Längen & Loop-Nähte

Godots Importer strippt das `-loop`-Suffix und setzt das Loop-Flag automatisch.

| Clip | Soll (`CLIP_LIST`) | GLB | Δ | Loop-Naht (max abs first−last) |
|---|---|---|---|---|
| idle | 2.60 | 2.583 | 1 Frame | **0.00000** ✅ |
| idle_lookaround | 2.50 | 2.500 | 0 | 0.00000 (kein Loop) |
| walk | 0.70 | 0.708 | 1 Frame | **0.00000** ✅ |
| hop | 0.60 | 0.583 | 1 Frame | 0.06339 (`root.scale`) — **kein Loop, unkritisch** |
| sit | 2.00 | 2.000 | 0 | **0.00000** ✅ |
| sleep | 2.20 | 2.208 | 1 Frame | **0.00000** ✅ |
| wave | 1.00 | 1.000 | 0 | 0.00000 (kein Loop) |
| squeeze_door | 1.80 | 1.792 | 1 Frame | **0.00000** ✅ |
| brush_teeth | 1.10 | 1.083 | 1 Frame | **0.00000** ✅ |
| build_hammer | 0.90 | 0.917 | 1 Frame | **0.00000** ✅ |
| celebrate | 0.90 | 0.917 | 1 Frame | 0.00000 (kein Loop) |

Alle Δ ≤ 1 Frame @ 24 fps (Rundung `ANIM_FPS`). **Alle 7 Loop-Clips schließen exakt.** Tadellos.

---

## 3. Render-Review — 103 Shots, alle angesehen

Renderlauf: `xvfb-run -a godot --rendering-method gl_compatibility --rendering-driver opengl3`
mit einer Eval-Szene, die **nur in der /tmp-Kopie** des Projekts liegt (`/tmp/e8/proj/eval_e8/`).
Posen deterministisch über `AnimationPlayer.seek()` + `advance(0)`, nicht über Wanduhr.

### Galerie — `/tmp/gooby-godot/eval/E8-shots/`

| Kontaktbogen | Inhalt |
|---|---|
| `_sheets/SHEET_sticker_vs_3d.png` | **Referenz-Sticker vs. 3D** (Look-Urteil) |
| `_sheets/SHEET_clips_1.png`, `SHEET_clips_2.png` | alle **11 Clips × 4 Phasen** (44 Shots) |
| `_sheets/SHEET_clip_action.png` | wave / hop / brush_teeth / build_hammer im Detail |
| `_sheets/SHEET_clip_sit_sleep.png`, `SHEET_clip_squeeze_walk.png` | sit / sleep / squeeze_door / walk |
| `_sheets/SHEET_sleep_angles.png`, `SHEET_sit_squeeze_angles.png` | sleep/sit/squeeze aus 4 Kamerawinkeln |
| `_sheets/SHEET_emotions_face.png`, `SHEET_emotions_body.png` | **alle 8 Emotionen**, Nah + Ganzkörper |
| `_sheets/SHEET_morphs_face.png`, `SHEET_morphs_body.png` | **eye_width / eye_size / ear_length** je min+max (+ Spiel-Range) |
| `_sheets/SHEET_squeezeface.png` | `body_squeeze_door` 0.00→1.00 Rampe, Kopf-Nah |
| `_sheets/SHEET_squeeze.png` | Squeeze-Shapekey front + seitlich |
| `_sheets/SHEET_armseam.png` | Arm-/Bauch-Nahtprüfung |
| `_sheets/SHEET_turntable.png` | 8× 45° Drehteller |
| `_sheets/SHEET_clipcheck.png` | walk + `ear_length` 1.4, 4 Winkel (Ohr-Clipping) |
| `_sheets/SHEET_face_extra.png` | blink, mouth_open |
| `_sheets/SHEET_rig_tint.png` | GoobyRig-Ladepfad + **oranger Liefer-Gooby** |

Einzelbilder mit den deutlichsten Befunden:
`x_squeezeface_1.00_neutral.png`, `x_wavearm_yaw000.png`, `x_armseam_yaw070.png`,
`clip_sleep_p1_t0.73.png`, `y_sleep_yaw035_h1.45.png`, `x_liefergooby_orange.png`

### Sieht Gooby überall aus wie der Sticker-Gooby? — **Nein, aber „schuldlos".**

Die Sticker-Referenz (`GOOBY/public/assets/stickers/firstNom.png`) zeigt: cremefarbener Hase mit
**langen Schlappohren nach unten**, weichem Pastell-Ohrinneren, dunkler Outline, gut lesbaren Armen
mit **rosa Pfotenballen**, und einem Bauch, der farblich kaum vom Körper abweicht.

Der 3D-Gooby hat **kurze, aufrechte Ohren**, einen schmalen **knallrosa Streifen** als Ohrinneres,
keine Outline, **Stummelärmchen ohne Ballen** und einen **großen, fast weißen Bauchfleck**.
Silhouette ist die stärkste Identitätsmarke — dadurch liest sich der 3D-Gooby eher als „generisches
niedliches Häschen" denn als *der* Gooby vom Sticker.

**Aber:** `gooby_params.py` deklariert explizit als Quelle nicht den Sticker, sondern die
**Web-Referenz** `GOOBY/src/character/gooby.js` („ALLE Zahlen sind 1:1 aus der Web-Referenz
portiert"). Und `gooby.js:137` bestätigt: *„Ears: pivots on the head top at (±0.13, 1.06, 0),
tilt ±10°"* — der Web-Gooby hat ebenfalls aufrechte Ohren. **Die Portierung ist gegen ihre erklärte
Quelle korrekt.** Die Divergenz liegt zwischen Sticker-Art und Spiel-Gooby, nicht in der Pipeline.
Das ist eine Art-Direction-Entscheidung, keine Umsetzungslücke — sollte aber bewusst getroffen werden.

**Wo die Portierung wirklich unvollständig ist:** siehe P1-1 (Ohr-Droop pro Emotion) — genau *das*
Element, das dem Web-Gooby seine Ausdruckskraft gibt, fehlt.

### Kaputte Posen?

* **sit** — bestes Ergebnis. Aus allen 4 Winkeln stimmig, rosa Pfotenballen sichtbar, sehr nah am Sticker. ✅
* **idle / idle_lookaround / walk / hop** — sauber, keine Durchdringungen, `hop` hat einen lesbaren Stretch-Apex. ✅
* **sleep** — Rückenlage. Aus der Home-Kamera (`camera_rig.gd: FOLLOW_OFFSET (0, 4.6, 4.1)`, steile Aufsicht) liest sie sich gut. Auf Augenhöhe (wie `ort_scene.gd`, Cam y=2.0/−12°) ist das Gesicht **hinter dem Bauchfleck verdeckt** und der Kopf steckt sichtbar im Rumpf → P2-4.
* **wave / celebrate** — Geste **nicht lesbar**. Die Arme sind kurze Kapsel-Stummel, die mit harter Naht aus dem Körper ragen → P2-2.
* **squeeze_door** — über alle 4 Phasen **optisch nicht von idle unterscheidbar**. Kein Quetschen → P1-4.
* **brush_teeth / build_hammer** — Prop-los und mit Stummelarmen kaum als Tätigkeit erkennbar; für die Distanz akzeptabel, aber schwach.

### Clipping Ohren/Arme?

* **Ohren:** kein Clipping. Auch bei `ear_length` = 1.4 (Slider-Max) bleiben beide Ohren sauber, keine Durchdringung von Kopf oder Körper, keine Selbstdurchdringung in `walk` aus 4 Winkeln. ✅
* **Arme:** kein Durchstoßen, aber eine **harte, ungeglättete Vereinigungsnaht** dort, wo die Arm-Kapsel in die Körperkugel läuft (`x_armseam_yaw070.png`). Der Arm wirkt wie ein aufgesetztes Würstchen. Kenney-Style-Primitiv-Union — stilistisch vertretbar, optisch schwach.
* **Bauchfleck:** ragt in gequetschten und liegenden Posen sichtbar **über die Körpersilhouette hinaus** (`squeeze_shape_1.0_front.png`, `clip_sleep_p1_t0.73.png`). Das ist echtes Clipping → P2-3.

### Squeeze-Door-Shapekey glaubwürdig? — Deform ja, Gesicht nein.

Die Körperverformung selbst ist überzeugend: schmal in X, breit in Z = durch einen engen Spalt
gequetscht. **Das Gesicht zerfällt dabei aber vollständig** (`SHEET_squeezeface.png`):

| `body_squeeze_door` | Gesicht |
|---|---|
| 0.00 | normal — Augen, Nase, Wangen, Lächeln, Hasenzähne |
| 0.25 | noch in Ordnung |
| 0.50 | Augen auf Punkte geschrumpft, **Nase weg**, Lächelbogen weg |
| 0.75 | **Augen weg, Mund weg** — nur der weiße Zahn-Quader + Wangenreste |
| 1.00 | **komplett leeres Ei**, nur ein weißer Fleck |

Ursache: Der Shapekey verbreitert den Kopf in Z, wodurch die Kopfschale die als eigene Kugeln/Decals
modellierten Augenperlen, Nase und Mund verschluckt — die Features wandern nicht mit.

Aktuell **latent**, weil den Shapekey niemand ansteuert (siehe P1-4) — deshalb P2, nicht P0.

---

## 4. Voice — ✅ Samples sauber, ⚠️ Timing-Semantik falsch benannt

Analyse: `/tmp/e8/voice.py` (reines `wave` + `numpy`, keine Godot-Abhängigkeit)

14 WAVs in `GOOBY-GODOT/assets/audio/voice/` — **alle** 22050 Hz, mono, 16 bit:

| Metrik | Wert |
|---|---|
| Dauer | 160.0 – 183.8 ms (Ø 168.3 ms) |
| Peak | **exakt 0.720 bei allen 14** → sauber normalisiert, 2.8 dB Headroom |
| Clipping | **0.00 %** durchgehend |
| DC-Offset | ≤ 0.0003 (vernachlässigbar) |
| RMS | 0.202 – 0.397 |
| Grundton f0 | 279 – 320 Hz — hoch/niedlich, für ein kleines Wesen genau richtig |

Keine Ausreißer, keine Stille-Dateien, keine Stereo-/Samplerate-Mischung. **Sample-Satz ist gesund.**

### `gooby_voice.gd::sagt()` — Silben-Timing

`RATE = 11.0` → Intervall **90.9 ms**. Samples sind Ø 168 ms → **1.85× Überlappung**;
`POOL_SIZE = 4` Round-Robin-Player decken das ab (nötig wären ~2). ✅

**Aber:** `_plan_syllables()` erzeugt einen Onset **pro Buchstabe**, nicht pro Silbe
(`gooby_voice.gd:139`, jeder Buchstabe → ein `plan`-Eintrag). Der Doc-Kommentar behauptet
„Rate ~11 Silben/s" — tatsächlich sind es **11 Buchstaben/s**. Deutsche Sprechrate liegt bei
4–7 Silben/s:

| Text | Onsets | Dauer |
|---|---|---|
| `"Hallo hallo!"` | 10 (statt 4 Silben) | 1.00 s |
| `"Juhu, geschafft?"` | 13 (statt 5) | 1.27 s |
| `"Guten Morgen, mein Freund!"` | 21 (statt 7) | 2.18 s |

Die **Gesamtdauer** ist plausibel (11 Zeichen/s ≈ normales Lesetempo), das Gebrabbel wird aber
~2.5× dichter als echtes Animal-Crossing-Babble. Stilistisch vertretbar, die Benennung ist falsch → P2-5.

Korrekt umgesetzt: `sad` verlangsamt auf 107 ms Intervall, `?` hebt den Schlussbogen (+0.06/Silbe über
die letzten 3), Emotion moduliert Basis-Pitch (0.8 sad … 1.2 ecstatic), ±12 % deterministischer
Hash-Jitter, `_token` entwertet laufende Schleifen sauber. Lipsync-Hook `silbe → babble_pulse()` ist
in `gooby_showcase`, `ort_scene` und `gooberando` verdrahtet. ✅

---

## 5. Integration — ✅ ein Ladepfad, ✅ Tint, ❌ Morphs

### Ladepfade — sauber, keine Duplikate

`GLB_PATH := "res://assets/character/gooby.glb"` ist die **einzige** Stelle, die das GLB lädt
(`gooby_rig.gd:18`). Alle 6 Konsumenten gehen über `GoobyRig.new()`:

| Konsument | Datei | Kontext |
|---|---|---|
| Home | `scripts/home/gooby_home.gd:28` | Wohnraum + NavigationAgent3D |
| City-Ort | `scripts/city/ort_scene.gd:144` | NPC, getintet |
| GOOBERANDO | `scripts/city/travel/gooberando.gd:215` | Liefer-Gooby im SubViewport |
| Reise-Cutscene | `scripts/city/travel/reise_cutscene.gd:124` | — |
| Besuch + Battleship | `scripts/social/remote_gooby.gd:19` | via `RemoteGooby`, genutzt von `visit_scene.gd:109` und `battleship_scene.gd:150` |
| Showcase | `scripts/character/gooby_showcase.gd:45` | Dev |

Verifiziert im Live-Lauf: `rig.clip_names()` liefert in allen Fällen alle 11 Clips, `set_emotion`
und `play_clip` greifen. **Kein doppelter Ladepfad.** ✅

Einzige zweite Gooby-Darstellung: `scripts/ui/onboarding/gooby_preview.gd` — eine **2D-Vektor-Zeichnung**,
im Header selbst als „PLATZHALTER" markiert, mit dokumentiertem Ablöse-Vertrag. Bewusst, in Ordnung —
liefert aber den Beweis für P1-2 (siehe unten).

### Tint Liefer-Gooby orange — ✅ funktioniert

`gooberando.gd:200-224`, `ORANGE = #FF7A00`, Code verbatim nachgestellt und gerendert:

```
tint: found 1 MeshInstance3D
tint:   Gooby surface_override_count=1 mesh_surfaces=1
tint:     surf 0 mat=StandardMaterial3D is_std=true
tint:     albedo before=(1.0, 1.0, 1.0, 1.0)
tint:     albedo after =(1.0, 0.6871, 0.4, 1.0)
```

→ `x_liefergooby_orange.png`: deutlich oranger Gooby, Augen bleiben dunkel, Wangen/Nase/Ohrinneres
werden zu einem satteren Orangerot, Bauch bleibt heller. **Liest sich gut.** ✅
Der Kommentar „Container ZUERST in den Tree" ist eine echte, richtig verstandene Falle
(`GoobyRig` lädt sein GLB erst in `_ready`) — sauber gelöst.

Anmerkung: `albedo_color` multipliziert die Palette-Textur global, tintet also alles gleichmäßig.
Für „Fell-Tint" gewollt. Identische Logik steht dupliziert in `ort_scene.gd::_tinte_npc` (P3-2).

---

## 6. Findings

### P0 — keine

### P1

**P1-1 · Emotionen sind auf Spieldistanz nicht unterscheidbar (Ohr-Droop/Kopfneigung/Arm-Hang fehlen)**
`gooby_rig.gd::set_emotion()` blendet ausschließlich Gesichts-Shapekeys. Die Referenz
`GOOBY/src/character/emotions.js` definiert pro Emotion zusätzlich `earDroopL/R`, `headPitch` und
`armsHang` — z. B. `sad: earDroop 0.7/0.7, headPitch 0.26, armsHang 1.0`, `angry: earDroop 0.7/0.08`
(asymmetrisch!), `ecstatic: earDroop -0.1` (Ohren perken). Der Web-Gooby lerpt diese in `gooby.js:603`.
**Nichts davon ist im Godot-Rig implementiert.** Beleg: in `SHEET_emotions_body.png` haben alle 8
Emotionen eine **identische Silhouette** — Ohren kerzengerade, Kopf gerade, Arme gleich. Nur wenige
Pixel Gesichtsdecal ändern sich. Bei der Home-Kamera-Distanz (`FOLLOW_OFFSET (0, 4.6, 4.1)`) ist
davon praktisch nichts mehr zu sehen.
Die Bones sind alle vorhanden (`ear.L.01/02`, `ear.R.01/02`, `head`, `arm.L/R`) — es fehlt nur die
Ansteuerung. Kein GLB-Rebuild nötig, reiner GDScript-Fix analog zum bestehenden `LookModifier`.

**P1-2 · Morph-Wertebereich-Mismatch: Multiplikator-Werte landen roh in Delta-Shapekeys**
`spiegel.gd:9-15` und `save_schema.gd:359-361` definieren `eye_scale` und `ear_len` als
**0.7 … 1.4 mit Neutral = 1.0** (Multiplikatoren) und reichen sie ungerechnet an
`set_morph("eye_size" | "ear_length", value)` weiter. Die Shapekeys sind aber **0…1-Deltas**:
`build_rig.py:277` „`eye_size` +1 = 35 % größere Knopfaugen", `:280` „`ear_length` +1 = 25 % längere
Schlappohren". Folgen:
* Der **Default-Zustand (1.0) steht permanent auf vollem Morph** — die Basis-Optik ist im Spiel unerreichbar.
* Der Slider fährt nur das Band 0.7…1.4 im Delta-Raum ab (also +24 %…+49 % Augen), nie 0.
Visuell belegt: `x_rig_gamedefault_morphs.png` vs. `x_rig_true_neutral_morphs.png` sowie
`SHEET_morphs_face.png` (Zeile `eye_size`: 0.00 / 0.70 / 1.00 / 1.40).
**Gegenprobe:** die 2D-Onboarding-Vorschau rechnet *richtig* multiplikativ
(`gooby_preview.gd:46 -78.0 * ear_len`, `:65 8.5 * eye_scale`). Onboarding-Vorschau und 3D-Gooby
zeigen also **unterschiedliche Charaktere** bei identischen Slider-Werten.
Fix: Mapping in `set_morph` bzw. `RIG_MAP` (z. B. `(eye_scale − 1.0) / 0.35`).
`eye_width` ist korrekt (−1…+1 auf −1…+1, Godot extrapoliert negative Shapekeys sauber — beide
Extreme gerendert und in Ordnung).

**P1-3 · Gespeicherte `charMorphs` werden nie auf den Rig angewendet**
Einziger `set_morph`-Aufrufer im gesamten Spielcode ist `spiegel.gd::_on_morph_changed` — also
**nur live während des Slider-Ziehens am Badezimmer-Spiegel**. Kein Konsument (`gooby_home`,
`ort_scene`, `remote_gooby`, `gooberando`, `reise_cutscene`) liest `meta.charMorphs` beim Aufbau.
Folge: Die komplette Charakter-Anpassung aus dem Onboarding ist am 3D-Gooby **unsichtbar**, und jede
Spiegel-Änderung ist beim nächsten Szenenwechsel weg. Der Wert wird korrekt persistiert
(`save_schema.gd:115`) — nur nie zurückgelesen.

**P1-4 · Der Tür-Quetsch-Gag quetscht nicht**
`door_transition.gd:270` spielt `play_clip("squeeze_door")`. Dieser Clip animiert ausschließlich
Bones (57 Kanäle T/R/S, **keine** Shapekey-Kanäle im GLB verifiziert) und ist über alle 4 Phasen
**optisch nicht von idle zu unterscheiden** (`SHEET_clip_squeeze_walk.png`, obere Reihe;
gegengeprüft aus 4 Winkeln in `SHEET_sit_squeeze_angles.png`). Der Shapekey `body_squeeze_door`,
der die Verformung liefern *würde*, wird von **keiner Zeile im Repo** angesteuert
(grep über `scripts/` + `scenes/`). Der Gag existiert damit faktisch nicht.
Achtung: Vor dem Verdrahten muss P2-1 gefixt sein, sonst verschwindet das Gesicht.

### P2

**P2-1 · `body_squeeze_door` löscht das Gesicht** — ab 0.5 verschwinden Nase und Mundbogen, ab 0.75
die Augen, bei 1.0 ist der Kopf ein leeres Ei (`SHEET_squeezeface.png`, `x_squeezeface_1.00_neutral.png`).
Der Shapekey verbreitert den Kopf in Z; die als separate Kugeln/Decals modellierten Augenperlen,
Nase und Mund werden von der Kopfschale verschluckt. Aktuell latent (P1-4), wird aber zum P0, sobald
jemand den Shapekey verdrahtet. Fix gehört in `build_rig.py` (Face-Features im Squeeze-Key mitziehen).

**P2-2 · Arme sind unlesbare Stummel mit harter Naht** — `wave` und `celebrate` lesen sich nicht als
Gesten (`x_wavearm_yaw000.png`, `clip_celebrate_p1_t0.30.png`). Die Arm-Kapsel schneidet mit
sichtbarer, ungeglätteter Ellipsen-Naht in die Körperkugel (`x_armseam_yaw070.png`). Keine Pfoten,
keine Ballen. Der Sticker-Gooby lebt von seinen Armen.

**P2-3 · Bauchfleck liest sich als separate weiße Kugel und clippt** — `#FFF9EC` gegen Körper
`#F6EAD7` ist unter dieser Beleuchtung nahezu Weiß; der Fleck dominiert die Frontsilhouette
(`turntable_000.png`) und **ragt in `sleep` und im Squeeze über die Körperkontur hinaus**
(`clip_sleep_p1_t0.73.png`, `squeeze_shape_1.0_front.png`). Sticker und Web-Referenz haben einen
deutlich subtileren Bauch.

**P2-4 · `sleep`: Kopf steckt im Rumpf, Gesicht auf Augenhöhe verdeckt** — Rückenlage. Aus der
Home-Aufsicht gut (`y_sleep_yaw035_h1.45.png`), auf Augenhöhe liegt das Gesicht hinter dem Bauchfleck
und der Kopf durchdringt sichtbar den Rumpf (`clip_sleep_p1_t0.73.png`, `y_sleep_yaw090_h0.80.png`).
Betrifft `ort_scene.gd` (Cam y=2.0 / −12°) und den Besuch.

**P2-5 · `GoobyVoice.RATE` ist Buchstaben/s, nicht Silben/s** — siehe §4. Doc-Kommentar
(`gooby_voice.gd:14` „Rate ~11 Silben/s") und `_plan_syllables` (ein Onset pro Buchstabe) widersprechen
sich; Gebrabbel ist ~2.5× dichter als deklariert.

### P3

* **P3-1** `gooby_params.py:124` sagt „Rig: 21 Bones (Plan ~22)", `BONES` hat **19** (GLB und `EXPECTED_BONES` im Test bestätigen 19). Kommentar veraltet.
* **P3-2** Tint-Logik wortgleich dupliziert in `ort_scene.gd::_tinte_npc` und `gooberando.gd::_liefer_gooby` — gehört in `GoobyRig`.
* **P3-3** `gooby_voice.gd:11` dokumentiert `fertig` „auch bei Abbruch"; der Token-Guard in `:124` verhindert genau das im abgebrochenen Coroutine.
* **P3-4** `gooby_rig.gd:123` `trim_suffix("-loop")` ist ein No-Op — Godots Importer strippt das Suffix bereits. Harmlos, aber irreführend.
* **P3-5** Material heißt `GoobyToon`, ist aber Standard-PBR (rough 0.92, kein Outline-Pass, keine Ramp). Der Sticker lebt von seiner dunklen Outline.
* **P3-6** `hop` hat 0.063 Naht auf `root.scale` — kein Loop-Clip, damit unkritisch; nur der Vollständigkeit halber notiert.

---

## 7. Was ausdrücklich gut ist

* **Byte-identische Reproduzierbarkeit** — vierstufige Blender-Pipeline, deterministisch, kein Repo-Leak, sauber parametrisiert.
* **`gooby_params.py` als Single Source of Truth** mit Quellenangaben pro Zahl und `assert names == P.SHAPEKEYS` — vorbildlich.
* **Budget-Disziplin:** 4406/8000 Tris, 14/24 Shapekeys, 19 Bones.
* **Alle 7 Loop-Clips schließen auf 0.00000** — das ist selten sauber.
* **Voice-Samples** technisch einwandfrei (einheitlicher Peak, kein Clipping, kein DC).
* **Ein einziger Ladepfad** für das GLB über 6 Konsumenten.
* **`test_character_pipeline.gd`** prüft GLB, Clips inkl. Loop-Flags, Bones, Shapekeys, Rig-API und Voice. **438/438 Tests grün** (voller Lauf, 53 s).
* **`sit`** ist die überzeugendste Pose und trifft den Sticker-Gooby am besten.

> Bemerkenswert: **alle vier P1 sind semantische Fehler, die von der grünen Test-Suite nicht erfasst
> werden.** Die Tests prüfen, dass die Shapekeys *existieren* — nicht, dass die richtigen Werte in
> ihnen landen oder dass sie überhaupt angesteuert werden.

---

## 8. Reproduktion

```bash
# 1) Pipeline in /tmp (Repo bleibt unberührt)
cd /workspace && tools/blender/build_gooby.sh /tmp/e8/build /tmp/e8/gooby_rebuild.glb
cmp /tmp/e8/gooby_rebuild.glb GOOBY-GODOT/assets/character/gooby.glb   # -> identisch

# 2) GLB inspizieren
python3 /tmp/e8/inspect_glb.py /workspace/GOOBY-GODOT/assets/character/gooby.glb

# 3) Voice
python3 /tmp/e8/voice.py

# 4) Renders (Eval-Szenen liegen NUR in der /tmp-Projektkopie)
cp -a /workspace/GOOBY-GODOT /tmp/e8/proj      # + /tmp/e8/proj/eval_e8/*
xvfb-run -a godot --path /tmp/e8/proj --rendering-method gl_compatibility \
  --rendering-driver opengl3 --resolution 900x900 \
  res://eval_e8/e8_render.tscn -- --shots=/tmp/gooby-godot/eval/E8-shots
python3 /tmp/e8/sheet.py all

# 5) Test-Suite
xvfb-run -a godot --headless --path /tmp/e8/proj --script res://tests/run_tests.gd
```
