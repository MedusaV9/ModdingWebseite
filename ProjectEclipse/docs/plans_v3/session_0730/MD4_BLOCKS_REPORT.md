# MD4 — Block-Geo-Paar (altar + respawn_door) + 3D-Kandidaten-Spec

**Auftrag:** Zensus §5 Welle M-D Zeile MD4 (`docs/plans_v3/session_0730/MOB_ITEM_CENSUS.md`).
(a) Respawn-Tür `locked_shudder`-Verstärkung (Scharnier-Ruck, Panel-Vibration,
Nachschwingen); (b) Altar NUR additiver Anim-Polish unter F-13; (c) Vorschlags-Spec
(nur Doku) für 3D-Konversionen `umbral_blade`/`umbral_pick`/`ferryman_toll`;
(d) Selbstkritik + Polish-Pass (Loop-Nähte, One-Shot-Ruhelagen).

**Datei-Besitz (exklusiv):** `geo/block/{altar,respawn_door}.geo.json`,
`animations/block/{altar,respawn_door}.animation.json`, `client/altarmodel/*`,
`client/entity/door/*` + `limbo/door/*` (Renderer-Seite), `scripts/geckolib_gen/mobs/respawn_door.py`,
`docs/uv/respawn_door.md`, dieser Report.
**NICHT angefasst:** `tools/photon/**` (A7!), `assets/eclipse/fx/**`, `AltarBlock*.java`-Logik,
`RespawnDoorApi/Block/BlockEntity`-Java, FROZEN-Basen, `validate_geo.py`/`paint_lib.py`,
Lang-/Sound-JSONs (keine neuen Keys nötig — kein Langdrop), Dateien der Parallel-Teams
(MC1–MC5; deren Working-Tree-Änderungen an sunmote/glitch_emitter wurden gesehen und gemieden).

---

## 1 Verifizierte Ausgangslage (gelesen, nichts aus dem Gedächtnis)

| Block | Geo | Anims | Trigger-Seams heute |
|---|---|---|---|
| `altar` | 15 Bones / 30 Cubes, 256×128 | `idle` (12 s Loop), `heartbeat` (1.2 s), `gift` (3.5 s), `erupt` (6 s), `stage_up` (2.5 s) | EIN Controller `state` (`AltarBlockEntity#registerControllers`, Blend 4 t); heartbeat bei akzeptierter Zahlung, stage_up aus `completeMilestone` (im SELBEN Tick wie `FX_ALTAR_LEVELUP`), gift/erupt via `AltarModelTriggers` |
| `respawn_door` | 6 Bones / 14 Cubes, 128×128 | `closed_idle` (6 s Loop), `open` (3 s hold), `close` (2 s), `locked_shudder` (0.7 s) | EIN Controller `state`; Shudder aus `RespawnDoorBlock.handleUse` (Ghost-Klick) + `RespawnDoorApi.playLockedShudder` + `S2CDoorCuePayload.POSE_SHUDDER`, IMMER gepaart mit `IRON_DOOR_CLOSE` pitch 0.45 bei t = 0 |

**F-13 präzisiert (aus `tools/photon/fx_altar.py` zurückgelesen, nicht aus dem Zensus
zitiert):** Photon 2.1.5 kann NICHT vom GeckoLib-Geo emittieren (`mesh` sampelt nur
gebakte Modelle) — A7s „Mesh-Emission" ist in Wahrheit ein **Zahlen-Kontrakt**: das
Monument ist in `fx_altar.py` als Annuli mit exakt den Radien/Höhen/Tilts/Spin-Raten des
Geos+idles nachgebaut. Load-bearing sind damit konkret:

| Gepinnt (A7-Kontrakt) | Wert |
|---|---|
| `ring_a/b/c`-Quadrat-Halbweiten, Höhen, statische Tilts (12° X / −8° Z) | Geo-Datei |
| idle: `ring_a` +360°, `ring_b` −360°, `ring_c` +360° (+0.05 b y-Bob), `core_pivot` +360°, `glow_core` −720° — alle über die **12.0-s**-Loop-Länge | Anim `idle` |
| stage_up: Ring-Pops Peak 0.5/0.6/0.7 s, `glow_core`-Flash ~0.4 s + ~1.3 s, `ring_a/b` ±360°-Whip über **2.5 s**, `ring_c` OHNE Rotationskanal | Anim `stage_up` |

Konsequenz: **Altar-Geo komplett unangetastet** (stärkster F-13-Beweis), alle gepinnten
Kanäle byte-identisch; Polish NUR als neue Kanäle/eingefügte Keys auf nicht gepinnten
Bones (`debris_*`, `horns`, `plinth`, Glow-Scales).

**Tür-Controller-Falle (verifiziert an `RespawnDoorBlockEntity`):** die Tür hat EINEN
Controller — ein getriggerter One-Shot ERSETZT die Pose-Anim vollständig, nicht gekeyte
Bones blenden über 4 t zur Bind-Pose. Deshalb keyt der neue `locked_shudder` auch
`glow_disc` (sonst poppt der 1.05-idle-Scale beim Shudder kurz auf 1.0).

## 2 Plan

1. **Tür-Geo:** die Ring-Griffe (je Cube 3 der Leaves) in neue Kind-Bones
   `handle_px`/`handle_nx` umziehen (Pivot an der Montageplatte y = 33.5) — die
   dokumentierte Fiktion ist wörtlich „a ghost rattles the handles", aber die Griffe
   waren starr. Nur Additionen, Cube/UVs identisch, Painter zieht nach
   (Beweis: byte-identische Texturen).
2. **`locked_shudder` v2** (0.7 → 1.4 s): Impact auf dem Sound-Beat (t = 0), Scharnier-Ruck
   4.2°, Panel-Vibration (Rotations-Jitter + z-Shiver ±0.35 px), Griff-Rattle bis −16°,
   **zweiter, asymmetrischer Ruck** bei 0.62 s (nur die px-Seite voll — der Ghost packt
   EINEN Griff), Nachschwingen als catmullrom-Decay durch Null bis 1.4 s; `glow_void`
   flammt am Saum, `glow_disc` pulst.
3. **Tür-Bestands-Anims additiv:** Griff-Trägheit in `open` (Whip beim Aufschwingen,
   Decel-Slap) und `close` (Slam-Schlag gegen das Panel bei 1.38 s), Grusel-Pendeln
   (< 1°) in `closed_idle`; `glow_void`-Slam-Blitz in `close`. Bestehende Kanäle unangetastet.
4. **Altar additiv:** idle Debris-Eigenrotation (4 verschiedene Tumble-Achsen/-Raten,
   alle ×360°-Vielfache), Orbit-y-Drift, Horn-Atmung, Glow-Echo-Keys; heartbeat wird
   Lub-Dub (Dub-Echo auf `glow_core`), Plinth-Absorb, gestaffelte Debris-Kicks; gift
   Debris-Staffel-Sprünge + Glints, Horn-Flare; erupt Horn-Rattle synchron zum
   Root-Quake + radialer Debris-Scatter; stage_up Debris-**Echo-Ladder** (Pops 0.8/0.9/1.0/1.1 s
   — exakt 0.3 s hinter A7s Ring-Leiter 0.5/0.6/0.7) + Horn-Salut.
5. Beweise: `validate_geo.py` 0/0 beide Paare; Additiv-/Pinned-/Naht-/Ruhelage-Checks
   per Skript (`/tmp/md4_checks.py`, nicht committet); Painter-md5.

## 3 Geänderte Dateien

| Datei | Art |
|---|---|
| `geo/block/respawn_door.geo.json` | 6 → 8 Bones (nur `handle_px`/`handle_nx` NEU), 14 Cubes unverändert |
| `animations/block/respawn_door.animation.json` | `locked_shudder` neu (0.7 s/18 kf → 1.4 s/108 kf), Handle-/Glow-Kanäle additiv in `closed_idle`/`open`/`close` |
| `geo/block/altar.geo.json` | **byte-identisch unverändert** (git diff leer) |
| `animations/block/altar.animation.json` | 5 Anims, rein additiv: 48→69 / 20→45 / 36→63 / 51→82 / 29→64 kf |
| `scripts/geckolib_gen/mobs/respawn_door.py` | Material-/Glow-Zuordnung auf `handle_*`-Bones umgezogen |
| `textures/block/respawn_door{,_glowmask}.png` | Painter-Rerun — **md5 byte-identisch** (kein Pixel geändert) |
| `docs/uv/respawn_door.md` | Bone-Tabelle: Handle-Zeile + 8-Bones-Zählung |

Keine Java-Änderungen (Renderer/BlockEntities unverändert — die neuen Bones brauchen
keine Code-Seite), keine FX-/Lang-/Sound-Dateien.

## 4 Ergebnis pro Block

### 4.1 respawn_door — locked_shudder liest jetzt körperlich

```
root
├─ frame (Zargen/Sturz/Schwelle)
│  ├─ glow_void   (Void-Ebene hinter dem Spalt)
│  └─ glow_disc   (Eclipse-Siegel im Sturz)
├─ leaf_px ── handle_px   (NEU: Ring-Griff, Pivot an der Montageplatte)
└─ leaf_nx ── handle_nx   (NEU)
```

Beat-Struktur des neuen `locked_shudder` (1.4 s; Sound `IRON_DOOR_CLOSE` @ t = 0):

| Zeit | Was passiert |
|---|---|
| 0.00–0.06 | **Impact**: Leaves flexen 4.2° in Öffnungsrichtung gegen das Schloss, root-Schub +0.5 px vom Klopfenden weg, Griffe kicken −16° aus dem Panel |
| 0.06–0.55 | **Panel-Vibration**: abklingender Rotations-Jitter (4.2→0.2°) + z-Shiver ±0.35 px, erster Impuls in Stoßrichtung (+z); Griffe schlagen wechselnd aus/an (−9/+3/−5°); `glow_void` flammt am Saum (Scale-x 1.08) |
| 0.62 | **Zweiter Ruck, asymmetrisch**: px-Seite voll (2.8° / Griff −11°), nx-Seite nur ~57 % (1.6° / −5.5°) — liest als „der Ghost packt EINEN Griff und reißt" statt als Loop des ersten Schlags |
| 0.88–1.40 | **Nachschwingen**: catmullrom-Decay durch Null (−0.9 → +0.45 → −0.25 → +0.1 → 0), Griffe pendeln aus (−2.5 → +0.8 → 0) |

Quantitativ vs. vorher: Länge 0.7 → 1.4 s, 18 → 108 Keyframes, max. Leaf-Ausschlag
2.2° → 4.2°, Griffe 0° → 16°, 1 → 2 Schläge, 3 → 7 bewegte Bones.

Bestands-Anims (nur additive Kanäle): `open` — Griffe pressen beim Pull-back (+2.2°),
whippen im Schwung (−8°), Decel-Slap (+2.8°), Ruhe bei 3.0 s (hold_on_last_frame endet
in Rest ✓); `close` — Griffe fliegen im Zuschwung (−9°), Slam-Schlag +3.8° bei 1.38 s
(0.08 s nach dem Leaf-Overshoot), `glow_void`-Blitz; `closed_idle` — Sub-Grad-Pendeln
gegenphasig px/nx. Vorzeichen-Konvention aus MD3 §6.3 übernommen: authored −X schwingt
den hängenden Ring VOM Panel weg (+X-Exkursionen ≤ +4° gedeckelt, ~0.6 px Tip-Kontakt =
„schlägt ans Holz", kein sichtbares Clipping).

### 4.2 altar — additiver Polish unter F-13 (Geo byte-identisch)

| Anim | Additionen (NUR neue Kanäle / eingefügte Keys) |
|---|---|
| `idle` (12 s) | Debris-Eigenrotation gestaffelt: d1 [360,720,0], d2 [0,−1080,−360], d3 [720,360,0], d4 [−360,−720,0] (alle ≡ 0 mod 360 über die Loop-Länge); `debris_orbit`-y-Drift (+0.6/−0.4, Phase gegen den core-Bob versetzt); Horn-Atmung (Scale-y 1.02/0.995); Glow-Echo-Keys: `glow_core` +1.03 @ 4.1/10.1 s, `glow_runes` Flash-Decay-Keys @ 3.55/9.55 s |
| `heartbeat` (1.2 s) | `glow_core` wird **Lub-Dub** (Dub 1.3 @ 0.65 s — spiegelt die schon vorhandene core-Kurve 1.28/0.94/1.12); Horn-Clench (1.05/0.985); Plinth-Absorb (−0.3 px dip); Debris-Kicks 4× gestaffelt (Onsets 0.05/0.12/0.19/0.26 s, Ruhe ≤ 0.95 s) |
| `gift` (3.5 s) | Debris-Staffel-Sprünge (Peaks 1.1/1.3/1.5/1.7 s, Amp 2.2/1.8/2.0/1.6 px) + Scale-Glints 1.15; Horn-Flare [1.03,1.06,1.03] @ 1.4 s |
| `erupt` (6 s) | Horn-Rattle ±1.2° exakt auf den root-Quake-Keys (1.35–2.7 s); radialer Debris-Scatter je in lokaler Pivot-Richtung (d1 +x, d2 −x, d3 +z, d4 −z; Onsets 2.0/2.2/2.4/2.6 s, Hover, Rückkehr 6.0 s) — durch den −1080°-Orbit liest das als Spiral-Scatter |
| `stage_up` (2.5 s) | **Echo-Ladder**: Debris-Pops 0.8/0.9/1.0/1.1 s (= A7s Ring-Leiter 0.5/0.6/0.7 s + 0.3 s Echo) + Scale-Glints 1.25; Horn-Salut @ 0.6 s. Alle BESTANDS-Kanäle byte-identisch, `ring_c` weiterhin ohne Rotationskanal |

## 5 Validierung (wörtlich)

| Prüfung | Ergebnis |
|---|---|
| `validate_geo.py` altar (Geo + Anim) | `-> PASS (0 error(s), 0 warning(s))` × 2, „validate_geo: 2/2 file(s) passed — all good" |
| `validate_geo.py` respawn_door (Geo + Anim) | `-> PASS (0 error(s), 0 warning(s))` × 2, „2/2 file(s) passed" |
| Altar-Geo-Datei | `git diff --quiet` = leer → **byte-identisch**; Bone-Liste HEAD vs. Arbeitskopie identisch (15 Namen, Skript-PASS) |
| Tür-Geo | alte Bone-Menge ⊆ neue (`added=['handle_nx','handle_px']`), Cube-Zahl 14 = 14 |
| Altar-Anim additiv | jedes ALTE (Anim, Bone, Kanal, Key)-Quadrupel in der neuen Datei vorhanden und wertidentisch (`violations=[]`); `loop`/`animation_length` aller 5 Anims unverändert; `git diff --numstat` = **253 Insertions / 0 Deletions** (reine Zeilen-Addition) |
| F-13-Pinned-Kanäle | 12 gepinnte Kanäle (idle-Spins/Bob, stage_up-Pops/Whips/Flash) **byte-identisch**, `stage_up.ring_c` ohne Rotationskanal (Skript-PASS) |
| Loop-Nähte (f·len ≡ 0 mod 360; pos/scale start = end) | idle 21/21 Kanäle PASS, closed_idle 5/5 PASS |
| One-Shot-Ruhelagen | altar 71 Kanal-Checks PASS, respawn_door 15 PASS (Rotationen enden auf 0 mod 360, Positionen [0,0,0], Scales [1,1,1]; `open` ist hold_on_last_frame by design) |
| Painter-Determinismus + Byte-Identität | Rerun VOR Änderung: md5 identisch (`ced9515c…` / `5436f548…`); Rerun NACH Geo-Split + Painter-Umbau: **dieselben** md5-Summen — der Bone-Umzug hat kein Pixel geändert (14430 Albedo-px, 4904 Glow-px konstant) |
| Java | keine Java-Änderungen ⇒ kein `compileJava` nötig (Auftragsregel „bei Java-Änderungen") |

Client-Sichtprüfung nicht gefahren (llvmpipe-VM, Parallel-Teams auf demselben Speicher —
gleiche Abwägung wie MD3); die Kurven sind stattdessen numerisch bewiesen (Naht-/
Ruhelage-/Pinned-Suite oben) und das Test-Rezept (§8) macht die In-Game-Prüfung zum
Zwei-Kommando-Vorgang.

## 6 Funde, die den Entwurf geändert haben

### 6.1 F-13 ist ein Zahlen-Kontrakt, keine Laufzeit-Referenz

`fx_altar.py` kann das GeckoLib-Geo gar nicht laden — Photon sampelt nur gebakte
Modelle. Die „Mesh-Emission" ist eine handgepflegte Kopie der Monument-Geometrie
(Radien/Tilts/Spins als Konstanten im Generator, Tabelle im Docstring). Das macht die
Falle GRÖSSER als „keine Bone-Renames": auch **Werte-Änderungen** an Ring-Tilts,
Loop-Länge oder Spin-Raten desyncen die Corona lautlos. Deshalb prüft mein
Beweis-Skript die 12 gepinnten Kanäle auf Byte-Identität statt nur die Bone-Namen.
Empfehlung an den Integrator: diese Pinned-Liste in `P6_geckolib_conventions.md`
aufnehmen, damit spätere Altar-Teams sie nicht aus `fx_altar.py` rekonstruieren müssen.

### 6.2 Ein-Controller-Blöcke: One-Shots müssen ALLE sichtbaren Loop-Kanäle mit-keyen

Beide Blöcke haben (anders als die Mobs mit `base`+`action`) EINEN Controller — ein
One-Shot ersetzt den Loop komplett, nicht gekeyte Bones blenden 4 t zur Bind-Pose und
zurück. Beim alten Shudder poppte deshalb der `glow_disc`-idle-Scale unsichtbar knapp
(1.05→1.0→1.05). Der neue Shudder keyt `glow_disc`/`glow_void` explizit. Beim Altar ist
derselbe Effekt der Grund, warum die Ring-Spins während jedes One-Shots kurz einfrieren —
Bestandsverhalten, bewusst NICHT „gefixt": die Ringe in jedem One-Shot mitzukeyen hieße,
gepinnte stage_up-Kanäle anzufassen (F-13) bzw. heartbeat/gift aufzublähen.

### 6.3 Painter-Noise ist koordinaten-, nicht bone-basiert — deshalb war der Griff-Split gratis

`paint_lib.GeoPainter`-Noise hasht (seed, gx, gy, salt); Bone-/Cube-Identität geht nicht
ein. Der Umzug des Griff-Cubes in einen neuen Bone mit identischen UVs erzeugt exakt
dieselben Pixel — bewiesen per md5. Merksatz: Cube-Umzüge in neue Bones sind
textur-neutral, solange UVs und Cube-Geometrie unverändert bleiben und die
Material-/Glow-Zuordnung im Driver mitzieht (`set_material("handle_*", …)`,
`set_glow_painter("handle_*", leaf_glow)` — `leaf_glow` keyt über Canvas-Rects, nicht
über Bones, und dient daher unverändert weiter).

### 6.4 Selbstkritik-Pass: zwei Physik-Fehler im eigenen ersten Wurf

(1) Die Panel-z-Vibration startete ZUM Klopfenden hin (−z) — der erste Impuls muss vom
Klopfenden WEG gehen (+z, konsistent mit dem root-Schub); Vorzeichen beider Leaves
geflippt. (2) Der zweite Ruck war ein exakter Klon des ersten (liest als Anim-Loop,
nicht als Wesen) — nx-Seite auf ~57 % reduziert, dadurch bekommt der zweite Schlag
eine eigene Handschrift. Beides nach dem Fix erneut durch die volle Beweis-Suite.

## 7 Koordinations-Snippets

### 7.1 An A7 (FX-Welle 13, Altar-Hub) — nur Information, keine Datei-Berührung

Alle A7-gepinnten Kanäle sind byte-identisch (Beweis §5). Neu und ggf. FX-pairbar:
stage_up-Debris-Echo-Ladder — Pops bei **16/18/20/22 t** (0.8/0.9/1.0/1.1 s), also exakt
6 t hinter deiner Ring-Whip-Leiter (10/12/14 t). Falls die `altar_stageup_shockwave`
je Glint-Kinder auf den Chips will: die Chips stehen zu den Pop-Zeiten um +1.6/+1.3/
+1.4/+1.1 px höher und skalieren auf 1.25. Kein Handlungsbedarf, reine Option.

### 7.2 An den Integrator

Keine Registrar-/Lang-/Sound-Snippets nötig (keine Java-/Key-Änderungen). Einzige
Empfehlung: Pinned-Liste aus §6.1 in den FROZEN-Contract aufnehmen.

## 8 Test-Rezept

Tür (Limbo — frische Welt nötig, Pre-Event-Save; AGENTS.md „Pre-event vs started saves"):

1. **Shudder**: als Ghost (oder gebannt) die Tür rechtsklicken → 1.4-s-Sequenz: Schlag
   auf dem Iron-Door-Sound, Griffe rattern sichtbar, zweiter (einseitiger) Ruck,
   Ausschwingen. Mehrfachklick spammt sauber (Re-Trigger startet auf dem Sound-Beat).
2. **open/close**: P4-Flow bzw. `S2CDoorCuePayload.POSE_OPEN/POSE_CLOSE`-Cue → Griffe
   whippen beim Aufschwingen, schlagen beim Slam ans Holz (0.08 s nach dem Leaf-Overshoot).
3. **closed_idle** ≥ 12 s ansehen: Sub-Grad-Griff-Pendeln, kein Naht-Ruck bei 6 s.

Altar (Overworld-Disc, `/eclipse`-Flow):

4. **idle** ≥ 24 s: vier Debris-Chips taumeln individuell (kein Gleichtakt), Kronen-Hörner
   atmen kaum merklich, Glow-Doppel-Puls; Ringe drehen UNVERÄNDERT (A7-Corona bei L5
   muss weiter auf den Ringen reiten — Regressions-Check für F-13).
5. **heartbeat** (Zahlung an den Altar): Lub-Dub statt Einzelblitz, Chips zucken gestaffelt.
6. **stage_up** (`/eclipse stage set` bzw. Milestone): Ring-Leiter wie immer, 0.3 s später
   die Debris-Echo-Ladder; `altar_stageup_shockwave`-Sync darf sich NICHT verschoben haben.
7. **erupt** (`AltarModelTriggers`/End-Reveal): Hörner rattern im Quake-Fenster, Chips
   spiral-scattern und kehren in die Ruhelage zurück (nahtloser idle-Wiedereinstieg).

---

## 9 Vorschlags-Spec: 3D-Konversionen `umbral_blade` / `umbral_pick` / `ferryman_toll`

**Status: NUR Spec fürs nächste Planning — in dieser Welle nichts gebaut.**
AGENTS.md-Gesetz beachtet: die Pixel-Icons sind finale Kunst. Die Konversion ERGÄNZT:
BEWLR rendert das GeckoLib-Geo nur in Hand-Kontexten (FIRST/THIRD_PERSON), während
GUI/GROUND/FIXED weiter das finale 2D-Sprite zeichnen (Renderer brancht auf
`ItemDisplayContext` — anders als die 6 Bestands-Hero-Items, die überall 3D sind).
Das ist der Kern-Unterschied zu MD1–MD3 und der Grund, warum die Icons unangetastet bleiben.

### 9.1 Verifizierte Ist-Lage

| Item | Registrierung | Klasse | Prominenz |
|---|---|---|---|
| `umbral_pick` | `EclipseItems:110`, Shop 12 Shards | vanilla `PickaxeItem` (UmbralTier, +50 % Break-Speed unter Nachthimmel) | Dauerpräsenz in Hand (Abbau-Tool) |
| `umbral_blade` | `EclipseItems:117`, Shop 16 Shards | vanilla `SwordItem` (+1 Herz Lifesteal bei Spieler-Kill via `lives/LifecycleEvents:121`) | Dauerpräsenz in Hand (Kampf) |
| `ferryman_toll` | `EclipseItems:158`, garantierter Ferryman-Drop (`FerrymanEntity:1182`) | vanilla `Item`, EPIC-Trophäe — **nichts konsumiert sie bisher** (rg-verifiziert) | Finale-Übergabe-Moment Tag 14 |

### 9.2 Bone-Layouts + Anim-Ideen

**umbral_blade** (~9 Bones / ~12 Cubes, 64²+Glowmask):
`root → grip → guard → blade_carrier → {blade_core (2 Cubes), glow_edge (0-Tiefe-Ebene
entlang der Schneide), glow_vein_a/b} · pommel → glow_eye · wisp_a/b` (2 Schatten-Fahnen,
Ruhe-Scale 0 nach MD3-Muster). Anims: `idle` 6 s (Edge-Glow-Atmung per Molang-Sinus
`* 60` = 360°/6 s, Wisp-Flicker), **`feast`** 1.2 s One-Shot (Pommel-Auge dilatiert,
Edge flammt — Trigger-Einzeiler in `LifecycleEvents` neben dem Lifesteal, exakt das
MD3-`triggerShatter`-Muster: public-static-Helfer in der neuen Item-Klasse).

**umbral_pick** (~8 Bones / ~11 Cubes, 64²+G):
`root → grip → collar → head_carrier → {pick_head (2 Cubes), tip_l, tip_r, glow_veins
(0-Tiefe-Adern), glow_moon_gem}`. Anims: `idle` 6 s (Adern pulsieren; nachts intensiver
wäre Code-seitig — NICHT in v1, Molang hat keine Tageszeit-Query im Item-Kontext),
**`night_bite`** 0.5 s One-Shot (Tips funkeln — Trigger beim Block-Break unter
Nachthimmel, wo der +50 %-Buff ohnehin geprüft wird; 1 Zeile im bestehenden Speed-Hook).

**ferryman_toll** (~10 Bones / ~14 Cubes, 64²+G — der zeremoniellste):
`root → chain_a → chain_b → bell_shell (2 Cubes) → {clapper (Pendel-Bone!), glow_seam}
· halo → halo_spin → glow_obol_a/b` (2 orbitierende Glyphen-Münzen; Kipp und Spin
getrennt — MD3-§6.1-Präzessions-Gesetz). Anims: `idle` 8 s (Ketten-Sway, Clapper-
Mikro-Pendel GEGEN den Sway, Obol-Orbit 360°/8 s), **`toll`** 2.0 s One-Shot (Clapper
schlägt, Shell-Ripple, Halo-Flare — Trigger-Vorschlag: Erst-Aufnahme nach dem
Ferryman-Kill; endgültige Economy-Nutzung entscheidet W13, der Helfer wartet dann schon).

### 9.3 Aufwandsschätzung nach Dateien (pro Item, MD3-Kalibrierung)

| Datei | neu/edit | Umfang |
|---|---|---|
| `geo/item/<id>.geo.json` + `animations/item/<id>.animation.json` | neu | ~120 + ~90 Zeilen |
| `scripts/geckolib_gen/items/<id>.py` + `textures/item/<dir>/{<id>,_glowmask}.png` | neu | ~150 Zeilen + 2 PNGs (Painter-Output) |
| `models/item/<id>.json` | **edit** (layer0 → builtin/entity) | Achtung: hier stirbt das GUI-Sprite → der Renderer MUSS den GUI-Zweig auf das gebakte 2D-Modell zurückrouten (neues Repo-Muster, einmal bauen, 3× nutzen) |
| Item-Klasse `Umbral{Blade,Pick}Item`/`FerrymanTollItem` (extends bisherige Klasse + `GeoItem`) | neu | ~60 Zeilen; Registrar-Zeile in `EclipseItems` = 1-Zeilen-Edit (Integrator-Absprache, shared File) |
| `client/item/ItemsCClientExtensions` + 3 Renderer | neu (EIN Registrar für alle drei) | ~30 + 3×~45 Zeilen |
| Trigger-Einzeiler (`LifecycleEvents` / Break-Hook / Pickup) | edit fremder Dateien | als Snippet an die Owner, MD3-§7-Muster |
| `docs/uv/<id>.md` | neu | Standard |

Summe alle drei: **~20 neue Dateien, 2–4 Fremd-Einzeiler als Snippets**, keine
FX-/Lang-Berührung (Namen existieren schon). Empfohlene Priorität: blade → pick → toll
(Hand-Dauerpräsenz vor Moment-Prominenz). Größtes Einzelrisiko: der GUI-Sprite-Fallback
im BEWLR (neues Muster — an EINEM Item beweisen, dann kopieren).
