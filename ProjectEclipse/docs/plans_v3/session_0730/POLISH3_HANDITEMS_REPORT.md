# POLISH3 — Hand-3D-Items: `umbral_blade` / `umbral_pick` / `ferryman_toll`

**Team 3 („Hand-3D-Items"), Umsetzung der MD4-§9-Spec.** Die drei letzten sichtbaren
2D-Sprites in der Hand sind jetzt GeckoLib-3D — **nur in Hand-Kontexten**:
First/Third-Person rendern neue Geo-Modelle mit Glowmask und Idle-Leben,
GUI/Ground/Fixed zeigen unverändert die finalen Pixel-Icons (AGENTS.md-Gesetz:
die Icons sind finale Kunst und wurden nicht angefasst).

---

## 1 Kontext-Switch-Mechanismus: `neoforge:separate_transforms` (JSON-only)

MD4 §9.3 hatte den GUI-Sprite-Fallback als „größtes Einzelrisiko" markiert und einen
Renderer-Branch auf `ItemDisplayContext` vorgeschlagen. Es geht eine Ebene sauberer —
**ganz ohne Java-Branch**, verifiziert direkt in den NeoForge-21.1.238-Quellen
(`SeparateTransformsModel.java`, `ItemRenderer.java`, `UnbakedGeometryHelper.java`):

1. Das Item-Modell (`models/item/<id>.json`) lädt über den NeoForge-Loader
   `neoforge:separate_transforms`: `base` = Inline-Modell mit `"parent": "builtin/entity"`
   (+ Hand-Display-Transforms), `perspectives.gui/ground/fixed` = Verweis auf ein
   neues `<id>_2d.json` (exakt das bisherige Sprite-Modell).
2. `ItemRenderer#render` ruft ERST `ClientHooks.handleCameraTransforms` →
   `SeparateTransformsModel.Baked#applyTransform` gibt pro `ItemDisplayContext` das
   jeweilige Kind-Modell zurück — und prüft DANACH `isCustomRenderer()` auf dem
   **zurückgegebenen** Modell:
   * gui/ground/fixed → gebackenes Sprite-Modell (`isCustomRenderer() == false`)
     → vanilla Quad-Pfad, Pixel-Icon wie bisher.
   * alle Hand-(und Head-)Kontexte → `builtin/entity`-Basis (`BuiltInModel`,
     `isCustomRenderer() == true`) → BEWLR → `GeoItemRenderer`.
3. Stolperfalle geprüft: verschachtelte `item/generated`-Kinder laufen bei NeoForge
   durch `UnbakedGeometryHelper.bake`, das den `GENERATION_MARKER` selbst behandelt
   (Zeile 103–104) — die Sprite-Quads entstehen also auch im Perspectives-Zweig.
   `gui_light: front` steht am Top-Level, damit die GUI-Beleuchtung flach bleibt wie
   beim alten `item/generated`-Modell.

Der BEWLR bekommt GUI **nie** zu sehen; die drei Renderer brauchen keinen
Kontext-Branch (Kommentar-Hinweis in `ItemsCClientExtensions`). Einmal gebaut,
dreimal genutzt — das von MD4 gewünschte Repo-Muster.

## 2 Was gebaut wurde

Alle Geo-/Anim-JSONs und Texturen sind **generiert** (`scripts/geckolib_gen/items/`,
ein Driver pro Item schreibt Geo + Anim + Albedo + Glowmask deterministisch;
backrooms_wanderer-Präzedenz fürs Geo-Schreiben, paint_lib fürs Malen). Details/UV:
`docs/uv/{umbral_blade,umbral_pick,ferryman_toll}.md`.

### 2.1 `umbral_blade` — 14 Bones / 16 Cubes

| Bone (Hierarchie) | Zweck |
|---|---|
| root | Idle-Sway-Träger |
| ├ grip (2 Cubes) | Knochengriff + Wickelband |
| │ └ pommel → **glow_eye** | Knauf; emissives Auge (inflate 0.18 = Iris-Ring) |
| ├ guard (3 Cubes) | Parierbalken + zwei nach außen geschwungene Hörner (±28° z) |
| │ ├ wisp_a / wisp_b | Schatten-Fahnen, **Ruhe-Scale 0** (MD3-Muster) |
| └ blade_carrier → blade_root → blade_mid (rest z 5°) → blade_tip (rest z 7°) | die **Kurve**: 12° kumuliert Richtung Schneide — Silhouette ≠ jedes gerade Vanilla-Schwert |
| glow_edge_a/b/c (je an ihrem Segment) | 0-Tiefe-Auraebenen, ragen über die Schneide hinaus |

Adern: KEINE Bones — pixelgenauer Glow-Painter auf den Klingen-Faces (wandernde
Säule + Seitenzweige), Albedo-Einleger und Glowmask aus derselben Maskenfunktion.

**Anims:** `idle` 6 s (Edge-Glow-Atmung wandert per Phasenversatz spitzenwärts,
Auge pulsiert, Sub-Grad-„Kurven-Atmen" der Segmente, zwei Wisp-Flicker mit
Scale-0-Naht) · `feast` 1.2 s One-Shot (Auge dilatiert 2.1×, Kanten flammen
gestaffelt, Wisps wehen aus, Klinge peitscht; endet in Ruhe).

### 2.2 `umbral_pick` — 13 Bones / 12 Cubes

| Bone (Hierarchie) | Zweck |
|---|---|
| root → grip (2 Cubes) | Aschenholz-Haft + Knochenband |
| │ └ **glow_vein_h** | Haft-Ader (0-Tiefe, schwebt 0.05 vor der Front) |
| ├ collar | Kragen |
| └ head_carrier → head_core | Kopf-Träger (Nick-Bone) + Kern |
| prong_f (rest x +4°) → prong_f_tip (rest x +10°) | Zinke vorn (−z), Spitze senkt sich |
| prong_b (rest x −4°) → prong_b_tip (rest x −10°) | Zinke hinten (+z), gespiegelt |
| glow_seam_f / glow_seam_b | 0-Höhe-Glownähte AUF den Zinken |
| **glow_moon_gem** | Mondstein in der Krone (inflate 0.16) |

Vorzeichen-Gesetz für die Spitzen aus dem Repo-Präzedenzfall verifiziert
(heart_extractor `chamber_lid`: positives X hebt das +z-Ende): fore-Zinke senkt
mit +x, aft-Zinke mit −x — beide Spitzen hängen wie bei einer echten Spitzhacke.

**Anims:** `idle` 6 s (Gem/Ader/Nähte atmen, Nähte gegenphasig, Kopf-Mikronicken) ·
`night_bite` 0.5 s One-Shot (Spitzen **beißen nach unten** +9/−9°, Nähte und Gem
blitzen; endet in Ruhe).

### 2.3 `ferryman_toll` — 12 Bones / 11 Cubes (das Zeremoniellste)

| Bone (Hierarchie) | Zweck |
|---|---|
| root | Schwebe-Bob |
| └ tilt (rest x 10°) → spin | **Präzessions-Gesetz MD3 §6.1**: statischer Kipp und 360°/8-s-Drehung strikt getrennt |
| spin → disc (2 Cubes) | gekreuzte Slabs = Oktagon-Münze Ø 8 |
| disc → emboss | erhabener Laternen-Boss (beidseitig proud) |
| disc → glow_face_f / glow_face_b | Gravur-Ebenen mit **Per-Face-UV 16×16** (2 Texel/Unit): AVERS Fähre mit drei Seelen + Buglaterne, REVERS Käfiglaterne |
| disc → glow_rim (4 Cubes) | **der starke Rand**: emissive Bänder, inflate 0.15 um die Kante |
| root → halo (rest x 18°) → halo_spin → glow_obol_a/b | zwei Obol-Glyphen orbitieren gegenläufig (−360°/8 s) auf gegengekipptem Ring |

**Anims:** `idle` 8 s (Spin 360°, Tilt-Wobble ±2.5° als echte Präzession über dem
10°-Rest, Halo-Gegenorbit, Rand/Gravur/Obols atmen, Schwebe-Bob) · `present` 2.0 s
One-Shot — der MD4-„Übergabe-Moment": Münze steigt +3, `tilt` neutralisiert den
Rest-Kipp (Zeremonie-waagerecht), Flip +180° → **Laternen-Revers wird präsentiert**,
Halten, Rück-Flip mit Overshoot, Absetzen. Bewusst 180-und-zurück statt 360°:
jeder Kanal endet numerisch auf 0 — kein Rückspul-Unwind beim Controller-Handback.

## 3 Java-Verdrahtung

| Datei | Inhalt |
|---|---|
| `economy/UmbralBladeItem` (neu) | `SwordItem` + `GeoItem`; base=idle, action=`feast` (triggerable). **`triggerFeast(ServerPlayer)`** = nullsicherer public-static-Einzeiler für den `LifecycleEvents`-Owner (MD3-`triggerShatter`-Muster) — NICHT von POLISH3 eingebaut, Datei gehört dem Lives-Team. |
| `economy/UmbralPickItem` (neu) | `PickaxeItem` + `GeoItem`; `night_bite` feuert aus dem EIGENEN `mineBlock`-Override, exakt unter der Buff-Bedingung von `ShardEconomy#onBreakSpeed` (Nacht + `canSeeSky(pos.above())`), 10-t-Throttle gegen Strip-Mining-Restart-Stottern. Kein Fremd-File-Edit nötig. |
| `economy/FerrymanTollItem` (neu) | `Item` + `GeoItem`; `present` feuert server-seitig aus `use()` (Rückgabe **PASS** — null Verhaltensänderung, MD4 §9.1: nichts konsumiert die Toll), 40-t-Throttle gegen Halte-Rechtsklick-Respam. `triggerPresent(ServerPlayer, ItemStack)` wartet auf W13s echte Economy-Nutzung. |
| `registry/EclipseItems` (3-Zeilen-Edit) | Registrierungen auf die neuen Klassen; Properties unverändert; alle Fremd-Referenzen (`is(...)`, `Offer(Supplier<? extends Item>)`) bleiben typkompatibel. |
| `client/item/{UmbralBlade,UmbralPick,FerrymanToll}Renderer` (neu) | `GeoItemRenderer` + `AutoGlowingGeoLayer`; Textur-Override auf `textures/item/umbral/...` bzw. `toll/...` (der Defaulted-Pfad wäre mit den 2D-Icons kollidiert!). |
| `client/item/ItemsCClientExtensions` (neu) | EIN Registrar für alle drei (ItemsB-Muster, lazy BEWLR, MOD-Bus). |

Anim-Trigger laufen über `SingletonGeoAnimatable.registerSyncedAnimatable` +
`GeoItem.getOrAssignId` — exakt das HeartExtractor-Idiom.

## 4 Validierung

| Prüfung | Ergebnis |
|---|---|
| `validate_geo.py` × 3 Items (Geo + Anim in einer Invocation, Bone-Crosscheck aktiv) | **6/6 PASS, 0 Errors, 0 Warnings** |
| Painter/Generator-Determinismus | alle 3 Driver 2× gelaufen → `md5sum -c` auf 12 Dateien (3 Geo + 3 Anim + 6 PNG) **byte-identisch OK** |
| `flock /tmp/gradle.lock ./gradlew compileJava --offline --console=plain` | **BUILD SUCCESSFUL** (neue Klassen in `build/classes` verifiziert) |
| Canvas-Konsistenz (AutoGlowingTexture) | Albedo und Glowmask je 64×64 ✓ |
| Loop-Nähte | alle Molang-Sinus auf 360°/Länge-Teiler; Wisp-/Spin-Keyframes starten und enden identisch (Scale 0 bzw. 0°≡360°) |
| One-Shot-Ruhelage | `feast`/`night_bite`/`present` enden auf Rest (Wisps by design auf Scale 0) |
| Offline-Wireframe-Check (nicht committet, `/tmp/polish3_preview.py`) | GeckoLib-Transformkette (Z→Y→X, X/Y negiert) nachgerechnet: Klingen-Kurve zur Schneide, Guard-Hörner außen, Zinken hängen, Münz-Kipp + Obol-Orbits — Silhouetten geprüft |

Iteration auf eigenem Output (Pflichtrunde): (a) Klingen-Faces sind nur 2 px breit —
der geplante Spalten-Bevel griff nie; Schneiden-Licht auf die WEST-Face verlegt.
(b) Zinken-/Hörner-Vorzeichen gegen den `chamber_lid`-Präzedenzfall verifiziert und
gedreht (Zinken hingen anfangs NACH OBEN, Hörner kippten einwärts). (c) `present`
von 360°-Flip auf 180-und-zurück umgebaut (Unwind-Falle, §2.3).

## 5 Dateien (Ownership POLISH3)

* `scripts/geckolib_gen/items/{umbral_blade,umbral_pick,ferryman_toll}.py` (neu)
* `geo/item/*.geo.json` ×3, `animations/item/*.animation.json` ×3 (GENERIERT)
* `textures/item/umbral/{umbral_blade,umbral_pick}{,_glowmask}.png`,
  `textures/item/toll/ferryman_toll{,_glowmask}.png` (GENERIERT)
* `models/item/{umbral_blade,umbral_pick,ferryman_toll}.json` (Edit → separate_transforms),
  `models/item/*_2d.json` ×3 (neu, = alte Sprite-Modelle)
* Java: 3 Item-Klassen, 3 Renderer, `ItemsCClientExtensions` (neu),
  `EclipseItems` (3 Registrierungs-Edits)
* Docs: `docs/uv/{umbral_blade,umbral_pick,ferryman_toll}.md`, dieser Report

**Nicht angefasst:** 2D-Icons, EclipseGeoMob/-Monster, Wand/Arm-Artifact/
Heart-Extractor (nur als Referenz gelesen), Photon, Storm, LifecycleEvents/
ShardEconomy (Blade-`feast`-Einzeiler liegt als Snippet bereit, §3).

## 6 Snippet an den LifecycleEvents-Owner (NICHT eingebaut)

In `LifecycleEvents` direkt neben dem bestehenden Blade-Lifesteal-Log (Zeile ~124),
eine Zeile:

```java
dev.projecteclipse.eclipse.economy.UmbralBladeItem.triggerFeast(killer);
```

Nullsicher (kein Blade in der Haupthand → No-Op), server-seitig, Sync macht
`SingletonGeoAnimatable`.

## 7 Test-Rezept (In-Game)

1. `/give @s eclipse:umbral_blade` — Inventar/Truhe/Item-Frame/Boden zeigen das
   PIXEL-Icon; in der Hand (F1/F5 prüfen) das kurvige 3D-Schwert mit atmender
   Schneide; ~alle 3 s ein Wisp-Flicker an den Guard-Hörnern.
2. Pick nachts unter freiem Himmel Blöcke brechen → Zinken-Biss + Naht-Blitz
   (gleiches Fenster wie der +50 %-Speed-Buff); tagsüber/unter Dach: nichts.
3. Toll halten: Münze präzediert über der Faust (Kipp-Wobble + Spin + Obol-Orbit);
   Rechtsklick → steigt, nivelliert, flippt zur Laternen-Seite und zurück (2 s,
   Respam-gedrosselt).
