# UV map — Ferryman's Toll (`assets/eclipse/textures/item/toll/ferryman_toll.png` + `_glowmask.png`)

**Texture size:** 64×64 (beide Dateien — GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/ferryman_toll.geo.json`
(GeckoLib-ITEM, **12 Bones / 11 Cubes**, Box-UV + **Per-Face-UV** auf den beiden
Gravur-Ebenen). **Geo, Anim UND Texturen sind GENERIERT** —
`python3 scripts/geckolib_gen/items/ferryman_toll.py`; Layout:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| disc | Münzslab vertikal | 6×8×1 | (0,0) | `coin_bronze` (Grünspan + Silber-Abrieb) |
| disc | Münzslab horizontal | 8×6×1 | (16,0) | gekreuzt = Oktagon, Ø 8, Dicke 1 |
| emboss | Laternen-Boss | 2×2×2 (inflate −0.3) | (36,0) | erhaben auf BEIDEN Faces; Glow-Painter nur Krone |
| glow_rim | Randband oben | 6×1×1 (inflate 0.15) | (46,0) | emissiv, `rim_band` shadeless |
| glow_rim | Randband unten | 6×1×1 (inflate 0.15) | (0,12) | |
| glow_rim | Randband links | 1×6×1 (inflate 0.15) | (16,10) | |
| glow_rim | Randband rechts | 1×6×1 (inflate 0.15) | (24,10) | |
| glow_face_f | Gravur AVERS (Fähre) | 8×8×0 (z +0.55) | south (32,16) 16×16 | **Per-Face-UV, 2 Texel/Unit** — Gravur feiner als die Geometrie |
| glow_face_b | Gravur REVERS (Laterne) | 8×8×0 (z −0.55) | north (48,16) 16×16 | nur die AUSSEN-Face deklariert |
| glow_obol_a | Obol-Glyphe | 1×1×1 (inflate −0.15) | (32,8) | emissiv, orbitiert auf `halo_spin` |
| glow_obol_b | Obol-Glyphe | 1×1×1 (inflate −0.15) | (40,8) | |

**Präzession (MD3-§6.1-Gesetz):** statischer 10°-Kipp auf `tilt`, die 360°/8-s-Drehung
auf dem Kind `spin`; die Obols hängen an `halo` (18° Gegen-Kipp) → `halo_spin`
(−360°/8 s). Kipp und Drehung teilen sich NIE einen Bone.

**Emissiv (Glowmask):**

* `glow_rim`, `glow_obol_*` — automatischer Albedo-Copy (shadeless Materialien).
* `face_glow` — läuft ANSTELLE des Auto-Copys: 1px-Ringring (α 200–255, DER
  "otherworldly currency"-Rand) + Motivlinien (Fähre mit drei Seelen + Buglaterne /
  Käfiglaterne mit Flammenkern), α 120–230 nach Gravur-Intensität.
* `boss_glow` — nur Kronen-Texel des Bosses, α 70 (Highlight, keine Lampe).

**Art-Brief:** spektrale Grünspan-Bronze (`#4A6A5C`/`#2C4238`), Silber `#8E9E9D`,
Glow in Seelen-Teal `#8FF2DE` — bewusst NICHT das Umbral-Violett: die Palette des
finalen 2D-Icons (`textures/item/ferryman_toll.png`), das GUI/Ground/Fixed weiterhin
zeigen.

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/ferryman_toll.py
```

Texturen NIE von Hand malen (AGENTS.md-Gesetz); AI-Art ersetzt später an identischen
Pfaden/Canvas-Größen.
