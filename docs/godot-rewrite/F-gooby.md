# IDEEN-IMPROVER F — Gooby-Charakter, Animationen & witzige Interaktionen

Bereich: USER-WISHES §F komplett. Verifiziert auf der VM: `blender` = **4.0.2** (headless ok),
Godot 4.4. Referenz-Web-Version: `/workspace/GOOBY` — Charakter `src/character/gooby.js`
(prozedurales Pivot-Rig, Pose-Channels), `src/character/goobyAnims.js` (19 Clips als reine
Pose-Writer), `src/character/emotions.js` (8 Emotionen: neutral/happy/ecstatic/sad/grumpy/
sleepy/hungry/dizzy), `src/character/goobyFace.js` (Lider/Münder/Wangen/Spiral-Pupillen),
`src/audio/goobyVoice.js` (100 % WebAudio-synthetisierte Stimme). Look-Referenz:
`GOOBY/public/assets/stickers/*.png` — **dicker Creme-Hase (#F2E5CE-Ton), riesige Schlappohren
mit rosa Innenseite, rosa Wangen & Pfotenpads, Knopfaugen, Mini-Schwanz** — Kenney-/Toon-Stil,
flache Farben, weiche Silhouette.

Schnittstellen zu anderen Improvern: Tür-Transition & SceneRouter = **A §5**, Raum=Szene &
Möbel-Grid = **D**, Push-Notifications/Analytics-Hooks = **B/C**. Dieses Dokument besitzt:
Charakter-Asset-Pipeline, Gooby-Runtime (`res://gooby/`), Interactable-Framework, Event-System.

---

## 1) Gooby 2.0 — Blender-Python-Charakter-Pipeline

### 1.1 Grundsatzentscheidung

Der neue Gooby ist **ein einziges skinned Mesh + Armature + Shape Keys**, gebaut von einem
**deterministischen Blender-Python-Skript** (kein manuelles .blend als Quelle — das Skript IST
die Quelle, versioniert im Repo, jederzeit headless neu baubar):

```bash
blender --background --factory-startup \
  --python tools/blender/gooby_build/build_gooby.py -- \
  --out GOOBY-GODOT/assets/gooby/gooby.glb --previews /tmp/gooby_previews/
```

Warum Skript statt Hand-Modelling: (a) reproduzierbar & diffbar, (b) die Web-Version hat schon
exakte, GETESTETE Proportionen (Birnen-Profil `PEAR_PROFILE`, Ohr-Kapseln, Pivots) — wir
übersetzen die Zahlen 1:1, der Look bleibt; (c) Iteration per Parameter statt per Maus;
(d) alle ~20 Clips sind mathematisch definierbar (Sinus/Ease-Kurven wie in `goobyAnims.js`) —
als Python-Keyframe-Tabellen viel schneller als Hand-Animation.

### 1.2 Skript-Aufbau (`tools/blender/gooby_build/`)

```
build_gooby.py     # CLI-Entry: Szene reset → mesh → rig → skin → shapekeys → anims → export
gooby_params.py    # ALLE Zahlen (Profile, Pivots, Farben, Budgets) — Single Source of Truth
mesh.py            # Geometrie: Spin(Birne) + UV-Spheren + Kapseln → join → 1 Mesh
rig.py             # Armature + Vertex-Group-Skinning (distanz-/heuristikbasiert, weich)
shapekeys.py       # Gesichts- & Editor-Morphs (prozedural: Vertex-Verschiebefunktionen)
anims.py           # Clip-Definitionen (Datentabellen) → bpy Actions → NLA-Tracks
materials.py       # 1 Palette-Textur 256×256 (Farbfelder) + UV-Zuordnung; toon-flat
export.py          # glTF-Export-Settings (GLB, +Morphs, +Actions, Y-up)
preview.py         # Workbench-Renders: Turntable + 1 PNG pro Emotion/Clip-Endpose (Review!)
```

**Mesh** (Budget ≤ 8 000 Tris, 1 Material, 1 Textur): Birnen-Körper als `Spin` über das
Catmull-Rom-geglättete `PEAR_PROFILE` (26 Samples × 24 Segmente), Kopf-Sphere (1.05/0.92/0.95
skaliert), Ohren als Kapseln (außen + abgeflachte rosa Innenfläche via UV auf Palette),
Ärmchen/Füße-Kapseln, Bauch-Patch/Wangen/Schwanz als UV-Inseln auf der Palette statt eigener
Meshes wo möglich (Bauchfleck = Textur, nicht Geometrie → weniger Tris, kein Z-Fighting).
Augen = **2 separate kleine Meshes** (flache Kugeln) mit eigenen Bones (Pupillen-Tracking +
Editor-Skalierung), Pupille als Textur mit 2 Frames (normal/Spirale) → Material-Param.
Alles `shade_smooth` + Auto-Smooth 60° — weiche Kenney-Silhouette.

**Armature** (~22 Bones — bewusst klein, mobile-freundlich):

```
Root (Boden, Squash-&-Stretch via Scale-Keys)
└─ Hips ─ Chest ─ Head ─ EarL.01 ─ EarL.02      (2-Bone-Kette → floppige Ohren)
   │               │   └ EarR.01 ─ EarR.02
   │               ├ EyeL / EyeR                 (Pupillen-Aim + Editor-Scale)
   │               └ Jaw                         (mouthOpen-Unterstützung)
   ├─ Shoulder.L ─ Arm.L ─ Paw.L   (+ .R)        (Winken, Schalter-Klick, Hammer)
   ├─ Leg.L ─ Foot.L  (+ .R)
   └─ Tail
```

Skinning: heuristische Gewichte (Höhenbänder am Körper, Radialfalloff an Gliedmaßen), danach
`bpy.ops.object.vertex_group_smooth`. Kein Auto-Weight-Zufall — deterministisch.

**Shape Keys** (≤ 24, Godot-Blendshape-Budget mobil): Gesicht: `lids_closed`, `lids_half`,
`mouth_smile`, `mouth_open`, `mouth_frown`, `mouth_flat`, `mouth_chew`, `cheek_puff`,
`brow_sad`, `brow_angry`, `eyes_wide`, `mouth_owo` (neu: Staunen). Gags: `body_squeeze_door`
(seitlich gequetscht, Bauch quillt vor/zurück — der Tür-Steckenbleib-Deform!), `belly_round`
(Weight-Tier/Nutella-Bauch). **Editor**: `eyes_apart`/`eyes_together` (Augenweite ±),
`head_chubby` (Pausbacken). Ohrenlänge & Augengröße laufen über **Bone-Scale zur Laufzeit**
(EarX.01-Scale, EyeX-Scale) — kein Morph nötig, bleibt animierbar.

**8+ Emotionen** = Runtime-Presets (wie `FACES` im Web): Emotion → Ziel-Gewichte der Face-Morphs
+ Ohr-Droop-Pose (Bone) + Kopfneigung, ge-lerpt in ~0.25 s. Die Emotionen liegen NICHT als
Blender-Actions vor — sie sind Daten in `gooby_face.gd` → jede Emotion kombiniert frei mit
jedem Clip (exakt das bewährte Web-Layering: Clip ADDIERT auf Emotions-Basispose).

### 1.3 Animations-Export & Godot-Import

`anims.py` definiert Clips als Datentabellen (Kanal → [(t, Wert, Ease)]), erzeugt pro Clip eine
`bpy.data.actions`-Action, legt jede auf einen eigenen **NLA-Track** (Name = Clip-Name) →
glTF-Export „Group by NLA Track“ ⇒ GLB enthält alle Clips als benannte Animationen. Squash &
Stretch = Root-Bone-**Scale-Keys** (glTF unterstützt Bone-Scale; Kinder skalieren mit — für
Ganzkörper-Squash gewollt; Teil-Squash macht der Shape Key). Godot-Import: `gooby.glb` →
vererbte Szene `res://gooby/gooby.tscn` (fügt AnimationTree, SpringBones, Skripte hinzu);
Loop-Flags per Import-Settings (`idle`, `walk`, `run`, `sleep`, `sit*` = loop).

**Sekundärmotion gratis**: `SpringBoneSimulator3D` (Godot 4.4) auf EarL/R.01–02 + Tail —
Ohren wackeln physikalisch bei JEDER Bewegung, ohne dass ein Clip sie animieren muss. Clips
keyen Ohren nur für gezielte Posen (Droop, Perk); sonst Spring.

### 1.4 Clip-Liste (~20 Kern-Clips, priorisiert)

| P | Clip | Dauer/Loop | Inhalt (Web-Vorbild wo vorhanden) |
|---|------|-----------|------------------------------------|
| 0 | `idle` | 2.6 s loop | Atmen scaleY 1↔1.03, Ohr-Sway (wie Web) |
| 0 | `walk` | 0.7 s loop | Watschel-Wippen, Ohren-Flop, Füße tapsen |
| 0 | `run` | 0.5 s loop | Hektisches Trippeln, Ohren nach hinten |
| 0 | `hop` | 0.6 s | Web-`jump`: Ducken→Sprung→Land-Squash |
| 0 | `sit` | loop-hold | Sitzpose (Brettspiel/Couch/PC; Var. `sit_drive`) |
| 0 | `sleep` | 2.2 s loop | Rückenlage, Zzz-Event (Web `SLEEP_POSE`) |
| 0 | `wake_up` | 1.6 s | Liegen→Rest→Streck-Gähnen (Web-Fix beibehalten!) |
| 0 | `wave` | 1.0 s | Arm hoch + 3× Winken |
| 0 | `eat` | 1.3 s | Kau-Zyklen, Wangen-Puff, Schluck-Ripple |
| 0 | `door_squeeze` | 1.8 s loop | STECKT: `body_squeeze_door`-Morph pulsiert, Strampeln |
| 0 | `sad_slump` | 0.8 s hold | Ohren-Droop, Arme hängen |
| 0 | `happy_bounce` | 0.9 s | 2 Hüpfer + Squash |
| 1 | `dance` | 1.2 s loop | Side-Steps + Arm-Pumps 100 BPM |
| 1 | `refuse` | 0.7 s | Kopfschütteln ×3 (Klettern-Verweigern + „manno“-Bubble) |
| 1 | `ragdoll_flail` | 1.0 s loop | Panisches Rudern aller Glieder (Schüttel-Stufe 3, Fake-Tumble) |
| 1 | `grip_floor` | hold | Bauchlage, Pfoten „krallen“ sich fest (Schüttel-Stufe 2) |
| 1 | `toothbrush` | 1.1 s loop | Schrubben mit Kopf-Mitwackeln, Schaum-Partikel-Event |
| 1 | `hammer_build` | 0.9 s loop | Hämmern + Rückstoß-Wobble (D §3.1 Aufbau-Gag) |
| 1 | `tomato_throw` | 0.8 s | Ausholen→Wurf (Multiplayer-Emote, C §Brettspiel) |
| 1 | `ceiling_cling` | hold | SPIDERGOOBY: kopfüber, Glieder gespreizt |
| 2 | `treadmill_run` | 0.4 s loop | Übertrieben schnelles Rennen + `treadmill_fly_off` (0.9 s) |
| 2 | `pc_gaming` | 2.0 s loop | Sitzend, Paws tippen, Kopf ruckt |
| 2 | `idle_stretch` / `ear_scratch` / `look_around` / `tail_wiggle` / `shiver` | je ~1.5 s | Idle-Variety (Web V2/G29 1:1) |
| 2 | `book_listen` | loop | Im Bett, Ohren zucken beim Zuhören, Lider sinken (Story-Stunde) |

Locomotion (`walk`/`run`) NEU (Web hatte kein Laufen — Root bewegte sich nur). Alles Weitere
(Poke-Wobble, Nies-/Hicks-Envelopes, Emotions-Bounce) bleibt **prozedural in GDScript** auf
Bone-Posen — 1:1-Port der bewährten Envelope-Mathematik, kein Clip nötig.

### 1.5 AnimationTree-Design

```
AnimationTree (root = AnimationNodeBlendTree):
  [StateMachine "base"] → [OneShot "action"] → [OneShot "gag"] → Output
   States: Locomotion(BlendSpace1D speed: idle→walk→run) | Sit | Sleep | Squeeze | Cling
   action-OneShot: wave, eat, hop, refuse, tomato_throw, idle-variety …  (filter: ganzer Body)
   gag-OneShot:    reserviert für Unterbrecher (Niesen als Clip-Alternative)
```

- Emotionen laufen **außerhalb** des Trees: `gooby_face.gd` schreibt Blendshape-Gewichte +
  Ohr-Droop direkt (lerp 0.25 s) — Layer-Reihenfolge wie im Web: Emotion-Basis + Clip-Add.
- Poke-Wobble/Squash: `SkeletonModifier3D`-Custom (`gooby_jiggle.gd`) schreibt gedämpfte
  Feder auf Root-Rotation/Scale NACH dem AnimationTree — Overlay wie Web-`pokeWobble`.
- Pupillen-Tracking: `gooby_look.gd` — Head-Yaw/Pitch-Clamp ±25° + Eye-Bone-Offset (Web-Werte).
- API-Kontrakt `gooby.gd` (spiegelt Web-API, macht Ports trivial): `play(clip, opts)→Signal`,
  `set_emotion(id)`, `look_at_point(p)`, `set_wet/stink/health/weight_tier`, `anchors`
  (BoneAttachment3D: hat/glasses/neck/hand_l/hand_r für Outfits).

### 1.6 AC-Gebrabbel (Stimme)

**Befund Assets**: `GOOBY/public/assets` enthält KEINE Voice-Samples — die Web-Stimme ist
komplett WebAudio-synthetisiert (`goobyVoice.js`: squeak/giggle/purr/yawn/snore/sneeze… als
Oszillator-Rezepte). Kenney `interface-sounds`/`impact-sounds` + `itch-sfx` (confirm/back-Blips)
taugen für UI/Thuds, nicht als Silben. **Design**: wir backen die Silben OFFLINE selbst:

1. `tools/voice/bake_syllables.py` (numpy, KEIN Blender nötig): portiert die
   `goobyVoice.js`-Rezepte (gleiche Frequenz-Konturen, Sub-Oktave, VOICE_WARMTH 0.85) und
   rendert **~14 Basis-Silben-WAVs** (44.1 kHz mono, je 0.07–0.2 s): `ba bi bu da di du ga gi
   gu ma mo wa` + `hm` + `!`-Chirp, dazu die Bestands-One-Shots (squeak/giggle/yawn/snore/…).
2. Godot `gooby_voice.gd`: `AudioStreamPlayer3D`-Pool (4 Stimmen) + pro Silbe
   `AudioStreamRandomizer` (random_pitch 1.12 ⇒ ±12 %, wie Web-Jitter). **Text→Gebrabbel**
   à la Animal Crossing: pro Buchstabe des Bubble-Texts eine Silbe (Hash Buchstabe→Silbe,
   deterministisch pro Wort), Rate ~11 Silben/s, Satzende = Pitch-Bogen runter, `?` = rauf.
   Emotion moduliert Basis-Pitch (happy +15 %, sad −20 %, grumpy −10 % + langsamer).
3. Bubble-UI ruft `voice.babble(text, emotion)` — Gebrabbel + Textanzeige synchron; Jaw-Bone
   + `mouth_open`-Morph flattern auf Silben-Onsets (billiges Lipsync).

---

## 2) Char-Editor & Onboarding

### 2.1 Editor-Parameter (Aussehen bleibt Gooby!)

| Slider | Mechanik | Bereich |
|---|---|---|
| Augenweite | Morph `eyes_apart`/`eyes_together` | −1…+1 |
| Augengröße | EyeL/R-Bone-Scale | 0.85…1.25 |
| Ohrenlänge | EarX.01-Bone-Scale-Y | 0.8…1.3 |
| Pausbacken | Morph `head_chubby` + `cheek_puff`-Grundanteil | 0…1 |

Fellfarbe NUR Shop (Palette-Textur-Swap bzw. Albedo-Tint-Modulate — Shop-System H/§Shop).
Werte in `profile.json` (`gooby.editor.*`); `gooby_customizer.gd.apply(profile)` beim Spawn.
Der **Spiegel** (§3) öffnet denselben Editor als Teilmenge — gleiche Szene, anderer Einstieg.

### 2.2 Onboarding-Storyboard (DEUTSCH, AC-knuffig)

1. **Schwarzblende → weiches Morgenlicht.** Gooby schläft mitten im leeren Zimmer auf einem
   Umzugskarton. Zzz-Partikel. Sanfte Musik.
2. Er blinzelt, `wake_up`, erschrickt niedlich (`eyes_wide`): Bubble „…oh! OH! BESUCH!“
   (Gebrabbel-Pitch hoch). Kamera fährt nah ran (A §4).
3. „Ich bin Gooby! Und du bist…?“ → **Namens-Eingabe** (großes freundliches Textfeld,
   Tastatur-sicher, Querformat ok). Danach: Gooby spricht den Namen als Gebrabbel-Kauderwelsch
   und verhaspelt sich: „Schön dich kennenzulernen, {NAME}!! Hab ich das richtig gebrabbelt?“
4. „Willst du MIR auch einen Namen geben? Sowas wie… Spitzname?“ → Eingabe (Default „Gooby“),
   Bestätigung mit `happy_bounce` + Konfetti: „{SPITZNAME}! Das bin ich! Für immer!!“
   (Hinweis-Text klein: später im Pass änderbar.)
5. **Spiegel-Moment**: ein Standspiegel „steht noch vom Umzug rum“. Gooby watschelt hin
   (`walk`, Pfadfindung-Showcase!), guckt rein: „Hmm. Bin ich schön? Dreh mal an mir rum!“
   → **Char-Editor** (Slider §2.1, Live-Vorschau, Gooby kommentiert: Ohren lang = „wheee!“,
   Augen eng = „hihi, so ernst!“). Bestätigen: „PERFEKT. Genau so wollte ich immer aussehen.“
6. Überleitung zu D §3.1: „Sooo {NAME}… ein Bett bräuchten wir noch. Hilfst du mir?“ →
   erstes Bett platzieren → `hammer_build`-Gag → Story beginnt.

Skip: Zurück-Pfeile je Schritt; kein Hard-Skip des Namens (Pflicht), Editor überspringbar
(„Sieht doch super aus!“-Button).

---

## 3) Interactable-Framework

### 3.1 Komponente

`res://components/interactable/interactable.tscn` (Area3D + Skript, Physics-Layer `interact`):

```gdscript
class_name Interactable extends Area3D
@export var id: StringName                # "lamp_livingroom", "mirror", …
@export var prompt: String                # Bubble-/Tooltip-Text (DE)
@export var walk_target: Marker3D         # wohin Gooby läuft (null = kein Anlaufen)
@export var highlight_meshes: Array[MeshInstance3D]
@export var enabled_predicate: StringName # optionaler GameState-Check ("has_pc", "is_morning")
@export var cooldown_sec: float = 0.0
signal interacted(ctx)                    # InteractionManager füllt ctx (gooby, room, …)
```

- **InteractionManager** (autoload): Tap → `PhysicsDirectSpaceState3D`-Ray auf Layer
  `interact`; sortiert nach Distanz; blockiert während Cutscenes/Baumodus; ruft optional
  `Gooby.walk_to(walk_target)` ab und emittiert dann `interacted`.
- **Highlight**: `next_pass`-Overlay-Shader (Fresnel-Rim, pulsierend, Farbton Mint) auf den
  `highlight_meshes` — an bei Hover/„Zeige alles“.
- **„Zeige alles Interagierbare“-Button** (HUD, Lupen-Icon): 3 s lang bekommen ALLE enabled
  Interactables des Raums (a) Rim-Puls und (b) ein Screen-Space-Icon via
  `camera.unproject_position()` (funktioniert auch verdeckt/außerhalb — Pfeil am Rand).
  Gooby kommentiert beim ersten Mal: „Ohh, alles glitzert! Fass ruhig alles an. Außer mich.
  Doch, mich auch.“

### 3.2 Konkrete Interaktionen (alle Räume, Kernfälle)

- **Lampe**: Klick → UI-Panel mit fettem Kippschalter (Skeuomorph, Daumen-groß). Beim Umlegen
  läuft Gooby zur Lampe, `wave`-Variante mit Ziel-IK auf den Schalter (Paw-Bone-IK, 0.4 s),
  „klick“-SFX (Kenney interface), Licht-Energy-Tween 0.15 s + Emissive am Lampenschirm.
  Ist Gooby weit weg: er ruft „Ich mach’s gleich!“ und watschelt hin — Schalter wartet.
- **Spiegel**: öffnet Editor-Teilmenge (§2.1). Gooby posiert währenddessen (`look_around`).
- **Klo/Dusche**: Gooby geht WIRKLICH aufs Klo (Bedürfnis-Stat). Sichtschutz: Duschvorhang-
  Mesh; dahinter wird Goobys Mesh unsichtbar, stattdessen **Schatten-Silhouette** = flaches
  Quad am Vorhang mit animiertem 2D-Silhouetten-Shader (3 Sprite-Frames: sitzen/schrubbeln/
  Ohren wackeln) — billig, lesbar, witzig. **Duschvorhang-Peek**: lässt man ihn nach dem
  Einseifen > 45 s sitzen ohne abzuspülen, fährt Kopf+Ohren-Proxy über die Vorhangkante,
  Bubbles rotierend: „…hallo?“ / „Das Wasser wird kalt. ICH werde kalt.“ / „Ich zähle bis
  drei. Eins… zwei… zweieinhalb…“
- **Zähneputzen-Pflicht**: Nach jedem Aufwachen Zustand `needs_brushing`: Gooby stellt sich
  ans Waschbecken (**Warte-Pose**: leicht vorgebeugt, guckt in den Spiegel, tippelt), andere
  Pflege-Aktionen geben `refuse` + „Erst Zähne! Sonst schmeckt alles nach Schlaf.“ Klick aufs
  Waschbecken → `toothbrush`-Clip + Schaum-Partikel + Schrubb-Wisch-Geste des Spielers (Reuse
  Wasch-Coverage-Logik aus Web `interactions.js`), Abschluss: blitzeblanke-Zähne-Sparkle +
  `squeakHappy`. (Goobyman-Zahnbürste kann kaputtgehen — Chance remote-konfigurierbar, §B.)
- **Geschichten-Stunde** (Einschlafen): Buch-UI (2 Seiten): links Lückentext, rechts 6 Wort-
  Chips (Drag/Tap). Bücher = `books.json`: `{id, titel, seiten[], luecken[], entertainment}`.
  Einschlaf-Logik: benötigte Wörter = f(entertainment, Abnutzung) — oft gelesene Bücher
  langweilen („schon 5× gelesen…“), neue Bücher (Shop/POW!) = schneller einschlafen. Während
  er einschläft sinken Lider (Blendshape) pro eingesetztem Wort; danach nur noch Umsehen-Modus
  (Kamera frei, Interactables aus) oder Wecken (−Laune). Falsche Wörter erlaubt = lustigere
  Geschichte, Gooby kichert im Schlaf.
- **Laufband-Gag**: Interactable am Laufband-Möbel. Ultra-schweres Tap-Alternating-Minigame
  (L/R immer schneller, Toleranzfenster schrumpft auf 90 ms). Gooby scheitert IMMER spätestens
  nach ~20 s → `treadmill_fly_off` (Fake-Tumble §5 Reuse) in die Couch. Keine Stat-Wirkung.
  Highscore-Zähler „Sekunden bis zum Abflug“ + Sticker bei 15 s. Bubble: „Sport ist Mord.
  Fast. An mir.“
- **PC + GOBBULL-Zocken**: PC-Möbel (kaufen) + GOBBULL-Konsole (kaufen) → Interactable
  „Zocken lassen“ (1–2 h Realzeit): Gooby `sit` + `pc_gaming`-Loop, Bildschirm-Glow flackert,
  gelegentliche Reaktions-Gags (Sieg: `happy_bounce` auf dem Stuhl; Niederlage: Ohren-Droop +
  Controller-fast-Wurf). Ertrag: +Spaß über Zeit; früher abbrechen ok („EIN Level noch!!“).

---

## 4) Random-Event-System

### 4.1 Datengetriebene Event-Defs

`res://events/defs/*.json` (Content-Pack-fähig, §B-Updater kann Events nachliefern):

```json
{ "id": "nutella_nacht", "weight": 2, "cooldown_days": 3,
  "trigger": { "window": ["22:30","03:00"], "conditions": ["is_asleep_player_offline"] },
  "push": { "title": "GOOBY", "body": "Du hörst etwas…" },
  "timeout_min": [10, 20],
  "fail_text": "Gooby hat es schon alleine hingekommen -_-",
  "scene_setup": "nutella_night", "reward": null }
```

- **EventScheduler** (autoload, offline-first): würfelt bei App-Aktivität + plant lokale
  Push-Notifications (iOS `UNUserNotificationCenter` via Plugin, Hook von §B/C) für
  Trigger-Fenster. Standard-Timeout 5–10 min (Event-spezifisch überschreibbar), danach
  Fail-Text als Log-Eintrag/Bubble beim nächsten Öffnen. Max. 1 aktives Event; Ruhezeiten
  respektieren Systemeinstellungen.
- **Rewards** = Buff-System: `{stat:"fun", delta:+10, duration_h:5}` — Buffs sind sichtbare
  Icons an der Stat-Leiste (H-UI), stapeln nicht pro Event-Id.
- `scene_setup` = benannter Einrichtungs-Hook im Raum (Gooby-Pose, Props, Partikel);
  `resolve` = Interactable/Mini-Geste, die das Event löst.

### 4.2 Event-Katalog (DEUTSCH, mit Texten)

| Id | Push | Ablauf & Auflösung | Reward / Fail |
|---|---|---|---|
| `hingefallen` | „Gooby ist hingefallen! Hilf ihm auf!“ | Liegt auf dem Rücken, strampelt wie ein Marienkäfer (`ragdoll_flail` langsam). Wisch-Geste nach oben → er rollt auf die Füße: „Ich hab’s geübt aufzustehen. Ehrlich.“ | +10 Spaß 5 h / Standard-Fail |
| `kuehlschrank` | „RUMMS aus der Küche…“ | Kühlschrank liegt um, 8 Lebensmittel verstreut, Gooby daneben mit `brow_sad`: „Der war schon immer wacklig!! Frag nicht.“ Alles per Drag einsammeln, Kühlschrank per Tap aufrichten. | +8 Hunger-Effizienz-Buff 4 h |
| `glas_teller` | „*KLIRR*“ | Scherben am Boden, Gooby auf Stuhl geflüchtet: „ES WAR DIE SCHWERKRAFT.“ Vorsichtig-Tipp-Sequenz (Scherben einzeln, falsche Reihenfolge = „AUA-fast!“-Squeak). | +5 Spaß 3 h |
| `nutella_nacht` | „Du hörst etwas…“ | **Voller Ablauf**: Küche nachts, Kühlschranklicht an, Gooby am Esstisch, Pfoten & Schnute voller Nutella, `eyes_wide`: „uhhh UPPPS“. Optionen: **„Ab ins Bett!“** (−5 Freude, +10 Energie; er tapst schuldbewusst zurück, Ohren hängen, murmelt „…war nicht mal meine Lieblingssorte“) oder **„Lass ihn machen“** (+10 Freude, −5 Energie; er strahlt, isst weiter, Glas-Kratz-SFX). Danach (10–20 min Realzeit) räumt er selbst auf und geht ins Bett — erwischt man ihn NICHT im Fenster, greift der Fail. | Fail: „Gooby hat es schon alleine hingekommen -_-“ (+ Nutella-Fleck auf Tisch als Beweis, wegwischbar) |
| `idle_wandern` | — (kein Push) | Bei Inaktivität wandert er durch Räume (§7-Pfadfindung, Raum-Graph). HUD-Button **„Wo ist mein Gooby?“** → Kamera-Teleport zu ihm, Bubble was er tat: „Ich hab die Blume im Garten angeguckt. Sie hat NICHTS gesagt.“ / „Ich hab gezählt, wie viele Fliesen das Bad hat. Vierzig-viele.“ Ab dann folgt er wieder. | — |
| `sockensuche` | „Gooby sucht etwas… seit 20 Minuten.“ | Er läuft im Kreis, guckt unter Möbel: „Meine Glückssocke ist WEG!“ Die Socke hängt auf seinem Ohr (Highlight erst bei Nähe). Tap auf die Socke: „…oh. Da wo ich sie hingelegt hab. Logisch.“ | +10 Spaß 5 h |
| `robo_jagd` | „Im Wohnzimmer piept was Böses.“ | Robo-Staubsauger (Deko-Item oder Leihgerät) dreht Runden, Gooby steht auf dem Tisch: „ER WEISS, DASS ICH KRÜMEL BIN!“ Sauger per Tap fangen (weicht 2× aus) und ausschalten. | +5 Spaß 3 h, Boden sauber (Hygiene-Bonus) |
| `kleber_stuhl` | „Gooby bastelt. Zu erfolgreich.“ | Er klebt am Stuhl fest (Bastelzeug-Props): „Ich bin jetzt ein Stuhlgooby. Das ist mein Leben jetzt.“ Rubbel-Wischgeste (Coverage) → *plopp*, Fake-Tumble rückwärts. | +8 Spaß 4 h |
| `klopapier_mumie` | „Aus dem Bad kommt Rascheln.“ | Komplett in Klopapier eingewickelt, nur Ohren gucken raus: „Ich wollte nur EIN Blatt.“ Kreisende Wischgeste wickelt ab (3 Lagen, Tempo-Gag: zu schnell = er dreht sich wie ein Kreisel + `squeakDizzy`). | +10 Spaß 5 h |
| `wurm_freund` | „Gooby starrt seit 20 Minuten ins Beet.“ | Garten: er liegt bäuchlings vorm Regenwurm: „Er heißt Herbert. Er sagt nichts. Ich mag ihn.“ Optionen: „Herbert bleibt draußen“ (er winkt dem Beet: „Bis morgen, Herbert.“) / „Gieß ihn mit ein“ (+Garten-Bewässerung des Felds gratis). | +5 Spaß 3 h |
| `fernbedienung` | „GOB.TY läuft auf MAXIMALER Lautstärke.“ | TV brüllt, Gooby mit Ohren als Ohrenschützer zugeklappt: „ICH FINDE SIE NICHT UND ICH FINDE AUCH MEINE GEDANKEN NICHT.“ Sofakissen antippen (3 Kissen, 1 versteckt sie) → leise, Aufatmen-`contentSigh`. | +5 Energie-Regen 3 h |
| `karton_gooby` | „Ein Paket wurde geliefert. Es… atmet?“ | Gooby sitzt im Lieferkarton, Ohren als Laschen: „Ich bin jetzt ein Möbel. Stell mich zu den anderen.“ Optionen: „Raus da!“ (Fake-Tumble raus + `happy_bounce`) / „Ok, du bist ein Möbel“ (Karton-mit-Gooby 1 h als Deko platzierbar, er hält ERSTAUNLICH lange still, blinzelt nur). | +10 Spaß 5 h |
| `gewitter_angst` | „Es donnert. Wo ist Gooby?“ | Nur bei Regen/Gewitter (Wetter-System): er ist WEG — unterm Bett, nur Augen im Dunkeln (Silhouetten-Shader-Reuse). Taschenlampen-UI (Spotlight-Wisch) findet ihn, Streichel-Geste beruhigt: „D-Donner ist nur… Himmel-Rülpsen, oder?“ | +10 Spaß 5 h, schläft danach sofort ein |
| `mehl_unfall` | „In der Küche hat es *gepufft*.“ | Küche weiß bestäubt, Gooby komplett weiß, nur Augen: „Ich wollte dir Pfannkuchen machen. Der Sack war… explosiver als gedacht.“ Abklopf-Tipps (5×, je ein Mehl-Puff-Partikel) → Fell wieder normal. | +8 Spaß 4 h, 1× Gratis-Pfannkuchen (Essen) |

(Fail-Text überall Standard, außer Nutella. Alle Texte sind finale DE-Strings für `strings.json`.)

---

## 5) Schüttel-Secret (Accelerometer, 3 Eskalationsstufen)

- **Erkennung**: `Input.get_accelerometer()` (nur Device; Editor-Fallback: Taste F9 injiziert
  Fake-Shake). Gravitations-Anteil per Low-Pass (α=0.1) abziehen; Shake-Metrik = gleitendes
  RMS der Rest-Beschleunigung über 0.5 s. Akkumulator `shake_energy` (+RMS·dt, Decay 2.5/s).
- **Stufe 1** (`energy > 4`, ~1 s schütteln): Kamera-Shake (Trauma-basiert), Decken-Staub-
  `GPUParticles3D`, Möbel-Micro-Wobble (Shader-Vertex-Sway), Gooby `eyes_wide` + „?!“-Bubble.
- **Stufe 2** (`> 9`): Gooby wirft sich flach hin → `grip_floor`-Hold, Ohren flattern
  (SpringBone-Wind), Bubble „ERDBEBEN! ODER RIESE! ODER DU!!“, Bilder an Wänden kippen schief.
- **Stufe 3** (`> 15`): **Fake-Tumble-Ragdoll** (Empfehlung statt PhysicalBone, s. Risiken):
  Gooby-Proxy = `RigidBody3D`-Kapsel mit Zufalls-Impuls + Drehimpuls, prallt an Raum-Wänden
  (2–3 Bounces, Squash-Puls je Impact), währenddessen `ragdoll_flail`-Loop + Dauer-Schrei
  (Pitch folgt der vertikalen Geschwindigkeit!). Landung: Sterne-Partikel, `dizzy`-Emotion.
  Danach Beschwerde-Phase 10 s (grumpy): „HALLO?? Ich WOHNE hier!!“ → Streicheln versöhnt
  sofort → happy + Erstmal-Sticker „Erdbebenüberlebender“. Cooldown 10 min (sonst grumpy-stack).
- `PhysicalBone3D`-Echt-Ragdoll = M3-Stretch-Goal (Rig ist mit 22 Bones klein genug), Fake-
  Tumble liefert 90 % der Komik bei 10 % des Tuning-Risikos.

## 6) BODEN-IST-LAVA / SPIDERGOOBY

Trigger: Pfadfindung meldet blockiertes Ziel (§7). Ablauf (Cutscene-Runner, skippbar):
1. Gooby stoppt vorm Hindernis, `refuse` + Bubble „Ich kann nicht so gut klettern… manno.“
2. Choice-Buttons: **„Ich baue um“** (öffnet Baumodus D §2, Kamera aufs Hindernis) /
   **„🔥 BODEN IST LAVA“**.
3. Lava: Boden-Material-Shader-Lerp (1 s) zu Emissive-Lava + Hitze-Flimmer (Postpro A §6),
   Blubber-Partikel. Gooby: Panik-`eyes_wide` → Sprung-Tween an die Decke (Ceiling-Anchor
   des Raums), `ceiling_cling`-Hold, Bubble „ICH BIN SPIDERGOOBY!!“ (+ Gebrabbel-Fanfare).
4. Lava löst sich nach ~4 s auf (Shader rückwärts), er plumpst (`hop`-Landung + Squash),
   klopft sich ab — **Baumenü öffnet sich automatisch**.
Easter-Egg: Lava-Option danach 1×/Tag auch ohne Blockade über den „Zeige alles“-Modus am Boden.

## 7) Pfadfindung im Haus

- **Pro Raum-Szene** eine `NavigationRegion3D`; Navmesh wird bei Möbel-Änderung **zur Laufzeit
  async re-gebaked** (`bake_navigation_mesh(true)`, debounce 0.5 s nach letzter Grid-Änderung —
  Möbel-Footprints aus D §1 sind die Obstacle-Quellen; Agent-Radius 0.28, Höhe egal).
- Gooby: `NavigationAgent3D` (avoidance aus — er ist allein), Locomotion-BlendSpace speist
  sich aus `velocity.length()`. Raum-übergreifend: **Raum-Graph** (Türen als Kanten, A §5) —
  erst Graph-Route, dann Navmesh je Raum; Türen triggern die Tür-Transition inkl. Squeeze-Gag.
- **Freie Standplätze**: `find_idle_spot()` sampelt 12 zufällige freie Grid-Zellen, Filter:
  auf Navmesh erreichbar, ≥ 0.6 m Abstand zu Möbeln/Türzonen, nicht hinter der Kamera;
  Score = Erreichbarkeit + Abwechslung (nicht letzter Spot) + leichte Kamera-Nähe-Präferenz.
- **Blockade-Erkennung**: `NavigationServer3D.map_get_path()` → Endpunkt > 0.5 m vom Ziel =
  blockiert → §6-Flow. Zusätzlich Stuck-Watchdog (Position ändert sich < 0.1 m in 3 s).
- Idle-Wandern (§4 `idle_wandern`) nutzt dieselben Spots + Raum-Graph; „Wo ist mein Gooby?“ =
  Kamera-Route über den Router (A §1.4).

---

## Prioritäten

- **M1 (Fundament, spielbar)**: Blender-Pipeline komplett (Mesh/Rig/Shapekeys/P0-Clips +
  Previews), GLB-Import + `gooby.tscn` (AnimationTree, SpringBones, Face-/Look-/Jiggle-Layer),
  Voice-Bake + Babble, Interactable-Kern + Lampe + „Zeige alles“, Navmesh + Walk/Run +
  Tür-Anbindung inkl. `door_squeeze` (mit A), Zähneputzen + Klo/Dusche-Silhouette.
- **M2 (Charme)**: Event-System + 8 Events (inkl. Nutella, hingefallen, Kühlschrank),
  Onboarding + Char-Editor + Spiegel, Geschichten-Stunde, Schüttel-Secret (Fake-Tumble),
  Idle-Wandern + „Wo ist mein Gooby?“, P1-Clips.
- **M3 (Kirsche)**: restliche Events (Gewitter, Karton…), Laufband-Gag, PC/GOBBULL,
  Lava/Spidergooby-Polish, P2-Clips, PhysicalBone-Ragdoll-Experiment, Duschvorhang-Peek-Varianten.

## Risiken

1. **glTF-Bone-Scale-Vererbung**: Ganzkörper-Squash via Root-Scale ok, aber Blender-
   `inherit_scale`-Modi ≠ glTF — Squash NUR am Root keyen, Teil-Deforms als Shape Keys.
   Früh testen: 1 Riegel-GLB mit Scale-Anim durch Blender→Godot jagen (Tag-1-Spike).
2. **Blendshape-Perf mobil**: ≤ 24 Morphs, 1 Mesh — Budget eingeplant, aber auf iPhone
   profilen (Godot berechnet Morphs auf GPU, sollte ok sein).
3. **Runtime-Navmesh-Rebake-Hitches**: async + debounce; Fallback: Grid-basiertes A* aus D
   (Möbel-Grid ist ohnehin die Wahrheit) statt Navmesh.
4. **Skinning-Heuristik-Qualität**: prozedurale Gewichte können an Achseln/Ohransatz knittern
   → Preview-Renders pro Clip im Build-Skript sind Pflicht-Review; notfalls Ohransatz-Ring
   manuell definierte Gewichtsbänder.
5. **Accelerometer** nur auf Gerät testbar → Fake-Shake-Debug-Input ab Tag 1.
6. **Ton der Texte**: Humor lebt von Feinschliff — Event-Texte zentral in `strings.json`
   (remote-updatebar §B), nie hardcoden.

## Scope (Dateien/LOC)

| Paket | Dateien | LOC |
|---|---|---|
| `tools/blender/gooby_build/` (7 py) | 7 | ~2 400 (davon anims.py ~900 Daten) |
| `tools/voice/bake_syllables.py` | 1 | ~250 |
| `res://gooby/` (gooby.gd, face, look, jiggle, voice, customizer, locomotion) | 8 | ~1 500 |
| `res://components/interactable/` + Manager + Highlight-Shader | 5 | ~600 |
| Interaktionen (Lampe, Spiegel, Bad-Suite, Story-Stunde, Laufband, PC) | 10 | ~1 400 |
| `res://events/` (Scheduler, Buffs, Runner) + 14 JSON-Defs | 17 | ~900 GD + JSON |
| Schüttel-Secret + Lava/Spidergooby + Navigation/Spots | 5 | ~700 |
| Onboarding-Flow | 3 | ~450 |
| **Summe** | **~56** | **~8 200 LOC** (+ GLB/WAV-Assets) |
