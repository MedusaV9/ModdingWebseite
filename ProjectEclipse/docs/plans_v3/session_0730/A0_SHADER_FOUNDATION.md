# A0 — Shader-Grundstein (custom_shader in Photon 2.1.5)

**Team A0, Session 0730.** Referenz-Doku für alle Effekt-Teams (A2/A3/A5/A7), die Photon-
`custom_shader`-Materialien nutzen wollen. Alle Aussagen sind **jar-verifiziert** gegen
`run/mods/photon-neoforge-1.21.1-2.1.5.jar` und die gebundelte LDLib2 (entpackt + `javap`
auf die relevanten Klassen: `CustomShaderMaterial`, `LDShaderHolder`, `LDShaderInstance`,
`CurveTexture`, `GradientTexture`).

TL;DR: **Ja, Photon 2.1.5 unterstützt custom shaders rein über Assets** — kein Java, keine
Registry. Ein Emitter-Material vom Typ `custom_shader` referenziert per `shaderLocation`
eine Core-Shader-JSON im eigenen Namespace; LDLib2 lädt sie über den normalen
ResourceManager. Drei Haus-Shader liegen bereit, `fxlib.material_shader(...)` setzt das
Feld, `fxlib validate` prüft die komplette Referenzkette.

---

## 1. Mechanismus (Beweis)

### 1.1 NBT-Format im .fx (Emitter-Material)

Ein Partikel-Emitter trägt in `config.material.material` (Photon-`IMaterial`, per
`PersistedParser` serialisiert):

```
material: {
  type: "custom_shader",            // Photon-Materialtyp (neben texture/hdr_particle/…)
  data: {
    shaderLocation: "eclipse:soft_particle",   // <ns>:<name> — SIEHE 1.2
    curveTexture:   [ …ListTag von Kurven-Compounds… ],    // optional, bare ListTag!
    gradientTexture:[ …ListTag von Gradient-Compounds… ],  // optional, bare ListTag!
    _additional: {                   // editor-persistierte Uniform-/Sampler-Overrides
      shaderData: {
        uniforms: { SoftDistance: [0.9f], HDRMode: [I;1], … },
        samplers: { MainTexture: { type: "texture", resource: "photon:textures/particle/smoke.png" } }
      }
    }
  }
}
```

Beweise:

- `CustomShaderMaterial` (Photon-Jar) deklariert `shaderLocation` als `@Persisted`-Feld
  und `shaderData` als `_additional`-Compound; `javap -c` zeigt das Parsen von
  `uniforms` (Float-`ListTag` bzw. `IntArrayTag`) und `samplers`
  (`{type:"texture", resource:<rl>}`) — dieselben Schlüssel tauchen als String-Konstanten
  in `LDShaderHolder` auf (`"uniforms"`, `"samplers"`, `"type"`, `"texture"`, `"resource"`).
- `CurveTexture`/`GradientTexture` serialisieren als **bare `ListTag`** der Zeilen
  (NICHT als Compound mit `curves`-Schlüssel — der alte fxlib-Code hätte nie geladen;
  in `material_shader` gefixt). Jede Zeile wird in eine 128×128-LUT gebacken, GLSL liest
  sie über `getCurveValue(row, t)` / `getGradientValue(row, t)` aus
  `photon:particle.glsl`.
- **Fail-soft**: Kompiliert der Shader nicht, fällt Photon zur Laufzeit auf
  `photon:hdr_particle` zurück und zeigt im Editor einen Fehler — der Client crasht nicht.

### 1.2 Asset-Pfade & Namespace-Konvention

`LDShaderInstance.create` baut aus `shaderLocation = <ns>:<name>` den Pfad
`assets/<ns>/shaders/core/<name>.json` (Bytecode: String-Konkatenation
`"shaders/core/" + path + ".json"`). Die JSON referenziert die GLSL-Stufen wieder als
ResourceLocations, die zu `assets/<ns>/shaders/core/<file>.vsh|.fsh|.gsh` aufgelöst
werden. Für uns:

```
src/main/resources/assets/eclipse/shaders/core/
  particle_fx.vsh          gemeinsamer Vertex-Shader (Partikel-Daten + viewZ)
  soft_particle.json/.fsh
  fresnel_shell.json/.fsh
  rgb_split_distort.json/.fsh
```

`#moj_import` funktioniert wie bei Vanilla-Core-Shadern, inklusive Cross-Namespace:
`#moj_import <photon:particle.glsl>` liefert `getParticleData()` (Position, Color, UV,
LightUV, …) und die LUT-Helfer. Vertex-Format ist `DefaultVertexFormat.BLOCK`
(Position/Color/UV0/UV2/Normal).

### 1.3 Shader-JSON-Struktur

Gleiches Schema wie Vanilla-Core-Shader (Beispiele in der Jar:
`assets/photon/shaders/core/hdr_particle.json`, `circle.json`, `sprite_hdr_particle.json`):

```json
{
  "vertex":   "eclipse:particle_fx",
  "fragment": "eclipse:soft_particle",
  "samplers": [ { "name": "MainTexture" }, { "name": "Sampler2" }, { "name": "SamplerSceneDepth" } ],
  "uniforms": [ { "name": "SoftDistance", "type": "float", "count": 1, "values": [ 0.75 ] }, … ]
}
```

Optional `"geometry"` für eine Geometry-Stufe. Jede Uniform, die per fxlib überschrieben
werden soll, MUSS hier deklariert sein (validate erzwingt das).

### 1.4 Was Photon/LDLib2 automatisch liefert (Uniform-/Sampler-Liste)

Per Raw-String-Scan + `javap` über die Photon-Klassen bestätigt:

| Name | Art | Inhalt |
|---|---|---|
| `U_CameraPosition` | vec3-Uniform | Kameraposition (Weltkoordinaten) |
| `U_InverseProjectionMatrix` | mat4-Uniform | inverse Projektionsmatrix (Depth-Rekonstruktion) |
| `U_InverseViewMatrix` | mat4-Uniform | inverse View-Matrix |
| `U_ViewPort` | vec4-Uniform | `(x, y, width, height)` des Viewports |
| `U_SpriteUV` | vec4-Uniform | nur vom `sprite_hdr_particle`-Pfad gesetzt (Sprite-Sheets) |
| `SamplerSceneDepth` | sampler2D | **Scene-Depth-Kopie** (vor Partikel-Pass) |
| `SamplerSceneColor` | sampler2D | **Scene-Color-Kopie** (vor Partikel-Pass) |
| `SamplerBlockAtlas` | sampler2D | Block-/Partikel-Atlas |
| `SamplerCurve` / `SamplerGradient` | sampler2D | die 128×128-LUTs aus `curveTexture`/`gradientTexture` |
| `Sampler2` | sampler2D | Lightmap (Vanilla-Konvention) |

Dazu die Vanilla-Builtins, sofern in der JSON deklariert: `ModelViewMat`, `ProjMat`,
`ColorModulator`, `FogStart`, `FogEnd`, `FogColor`, `FogShape`, `GameTime`
(**normalisierter Tageszeit-Bruch, wrappt** — für Wobble ok, nicht monoton!), `ScreenSize`.
Photon-eigene Material-Uniforms: `DiscardThreshold`, `HDR` (vec4), `HDRMode` (int).

Sampler-Regel: Namen, die mit `Sampler` beginnen, verdrahtet LDLib2 automatisch
(Konstanten-Prefix `"Sampler"` in `LDShaderHolder`); alle anderen (z. B. `MainTexture`)
sind **user-assignable** und werden über `shaderData.samplers` (bzw. fxlib `textures=`)
gebunden — unbelegt = schwarz.

---

## 2. Die drei Haus-Shader (eclipse-Namespace)

Alle nutzen den gemeinsamen Vertex-Shader `eclipse:particle_fx` (liefert zusätzlich
`viewZ` = View-Space-Tiefe in Blöcken).

### 2.1 `eclipse:soft_particle` — weiches Ausblenden an Geometrie

Vergleicht `viewZ` mit rekonstruiertem Scene-Depth (`SamplerSceneDepth` +
`U_InverseProjectionMatrix` + `U_ViewPort`) und blendet Alpha an Schnittkanten und nahe
der Kamera aus. Für Nebel/Rauch/Staub, der nicht mehr hart im Boden clippen soll.

| Knob | Default | Bedeutung |
|---|---|---|
| `SoftDistance` | 0.75 | Blöcke, über die an Geometrie ausgeblendet wird |
| `NearFade` | 0.5 | Blöcke Kamera-Nahblende |
| `MainTexture` (Sampler) | — | Partikeltextur, PFLICHT via `textures=` |
| `HDR`/`HDRMode` | aus | wie hdr_particle (Bloom) |

Empfehlung: `BLEND_ALPHA` + `vertex_sorting="DISTANCE"`, `depth_mask=False`.

### 2.2 `eclipse:fresnel_shell` — Force-Field

Kugel-Impostor auf dem Partikel-Quad: Fresnel-Rim glüht (HDR-fähig via `RimHDRColor`
> 1.0), Fläche bleibt fast transparent, Schnittlinie mit Szenen-Geometrie leuchtet
(`SamplerSceneDepth`-Naht). Billboard-Partikel genügt — keine Mesh-Kugel nötig.

| Knob | Default | Bedeutung |
|---|---|---|
| `ShellColor` | (0.72, 0.55, 1.0, 0.85) | Grundfarbe der Hülle |
| `RimHDRColor` | (1.2, 0.9, 1.6, 1.0) | Rim-Farbe, >1 = Bloom |
| `FresnelPower` | 2.5 | Kantenschärfe des Rims |
| `FaceAlpha` | 0.08 | Restdeckung der Fläche |
| `IntersectWidth` | 0.35 | Breite der Geometrie-Schnittnaht (Blöcke) |

### 2.3 `eclipse:rgb_split_distort` — Glitch-Akzent

Screen-Space: liest `SamplerSceneColor`, verschiebt R/G/B-Kanäle radial (chromatische
Aberration) + zeitbasierter UV-Wobble (`GameTime`), maskiert über prozeduralen Soft-Disc
auf dem Quad. KEINE Textur nötig.

| Knob | Default | Bedeutung |
|---|---|---|
| `SplitStrength` | 0.006 | Kanaltrennung (Screen-UV-Einheiten) |
| `WobbleAmp` | 0.004 | UV-Wobble-Amplitude |
| `WobbleSpeed` | 1.6 | Wobble-Frequenz-Multiplikator |
| `TintColor` | (1.0, 0.45, 0.95, 0.25) | Einfärbung, Alpha = Mischanteil |

Achtung: liest die Szene VOR dem Partikel-Pass — mehrere überlappende
rgb_split-Partikel sehen einander nicht (kein Stacking der Verzerrung).

---

## 3. fxlib-API für Generatoren

```python
from fxlib import material_shader, BLEND_ALPHA

.with_material(material_shader(
    "eclipse:soft_particle",                       # <ns>:<name> Core-Shader-Referenz
    uniforms={"SoftDistance": 0.9, "NearFade": 0.6},   # Skalar oder Tupel; Floats als Floats!
    textures={"MainTexture": "photon:textures/particle/smoke.png"},
    curves=[curve(...)], gradients=[gradient(...)],    # optional: LUT-Zeilen für GLSL
    blend=BLEND_ALPHA, cull=True, depth_test=True, depth_mask=False,
))
```

Signatur:

```python
def material_shader(shader, uniforms=None, textures=None, curves=None, gradients=None,
                    blend=None, cull=True, depth_test=True, depth_mask=False)
```

- `uniforms`: Werte, die die JSON-Defaults überschreiben (persistiert wie Editor-Knobs).
  Nur-Int-Werte werden als IntArray (int-Uniforms) geschrieben, sonst Float-Liste —
  **`1.0` statt `1` schreiben**, wenn die Uniform float ist.
- `textures`: nur für Sampler OHNE `Sampler`-Prefix (user-assignable).
- `curves`/`gradients`: `curve(...)`-/`gradient(...)`-NumberFunctions (oder
  `(alpha_pts, rgb_pts)`-Tupel), Zeile n → `getCurveValue(n, t)`/`getGradientValue(n, t)`.
- Das alte `custom_shader_material` ist deprecated (Alias, nie in einem .fx verschifft;
  schrieb zudem ein falsches LUT-Layout, jetzt gefixt).

### Validierung

`python3 tools/photon/fxlib.py validate <pfad.fx>` (und `FxBuilder.write`) prüfen die
komplette Referenzkette jedes `custom_shader`-Materials:

1. `shaderLocation` muss `<ns>:<name>` sein; `photon:*` gegen die Jar-Whitelist,
   `eclipse:*` gegen `src/main/resources/assets/eclipse/shaders/core/`.
2. `<name>.json` muss existieren + parsen; referenzierte `.vsh`/`.fsh`/`.gsh` müssen
   existieren.
3. Jede Uniform/jeder Sampler in `shaderData` muss in der JSON deklariert sein
   (Tippfehler wie `SoftDist` schlagen beim Authoring fehl, nicht erst in-game).
4. Struktur-Checks auf `curveTexture`/`gradientTexture`/`_additional`.

`HDR`-Uniform-Overrides fließen zusätzlich in den `LINT-HDR`-Check ein.

---

## 4. Beweis-Effekt & In-Game-Test

- Generator: `tools/photon/a0_proof_fx.py` → Asset
  `src/main/resources/assets/eclipse/fx/a0_shader_proof.fx` (+ `.fxproj` für den Editor).
  Drei Emitter: `soft_mist` (soft_particle), `force_dome` (fresnel_shell),
  `glitch_pops` (rgb_split_distort). ~160 Ticks, einmalig, kein Loop.
- **Bewusst in KEINER Registry** (keine Änderungen an FxCues/FxPayloads/
  PhotonFxRegistry-Kern).
- `/dev photon test eclipse:a0_shader_proof` funktioniert trotzdem:
  `FxDevClient.photonTest` prüft zuerst `PhotonFxRegistry.row(id)`; ist die ID dort
  unbekannt, spawnt sie **direkt** über `PhotonBridge.spawn(id, pos, …withAllowMulti)`,
  und `PhotonBridge`/`FXHelper.getFX` lädt schlicht `assets/<ns>/fx/<path>.fx`.
  Raw-Asset-IDs sind also ohne Registry-Eintrag testbar.

## 5. Grenzen & Gotchas

- `GameTime` ist der normalisierte Tageszeit-Bruch (wrappt bei Tageswechsel; skaliert mit
  Welten-Ticks). Für periodischen Wobble ok; für monotone Animationen stattdessen
  Partikel-Lifetime über eine Curve-LUT einspeisen.
- `SamplerSceneDepth`/`SamplerSceneColor` sind Kopien VOR dem Partikel-Pass: Partikel
  sehen einander nicht (kein Distortion-Stacking, Soft-Fade nur gegen Weltgeometrie).
- Shader-Compile-Fehler sind fail-soft (Fallback `photon:hdr_particle` + Editor-Fehler) —
  aber im Log sichtbar; validate fängt Referenz-/Deklarationsfehler vorher.
- Uniform-Typen: `int`-Uniforms brauchen Int-Werte (IntArray), `float`-Uniforms
  Float-Werte — Mischformen macht LDLib2 nicht heil.
- Editor-Roundtrip: Öffnet man das .fxproj im Photon-Editor, erscheinen die
  `shaderData`-Overrides als Knobs; Hand-Edits am .fx bleiben verboten (Generator-Regel).
- Kein per-Partikel-Zufalls-Seed als Uniform; Pseudo-Random im Shader über
  `texCoord0`/Weltposition hashen.
- HDR/Bloom: Werte > 1.0 in Farb-Uniforms (z. B. `RimHDRColor`) triggern Photons
  Bloom-Pipeline wie bei `hdr_particle`; `LINT-HDR`-Budget gilt weiterhin.

## 6. Was A2/A3/A5/A7 jetzt konkret nutzen können

- **A2 (Atmosphäre/Nebel)**: `eclipse:soft_particle` für alle bodennahen
  Rauch-/Nebel-Emitter — beendet hartes Geometrie-Clipping. Rezept: Abschnitt 2.1.
- **A3 (Schilde/Barrieren)**: `eclipse:fresnel_shell` als Ein-Partikel-Force-Field
  (Billboard genügt), Rim via `RimHDRColor` bloomfähig.
- **A5 (Glitch/Riss)**: `eclipse:rgb_split_distort` für Riss-/Echo-Akzente; `TintColor`
  auf GLI-MAGENTA-Palette setzen.
- **A7 (neue Shader)**: `particle_fx.vsh` wiederverwenden, JSON + .fsh nach Schema 1.3
  daneben legen — `material_shader("eclipse:<neu>")` und validate greifen automatisch.
