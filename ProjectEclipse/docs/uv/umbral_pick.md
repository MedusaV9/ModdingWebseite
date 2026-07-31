# UV map — Umbral Pick (`assets/eclipse/textures/item/umbral/umbral_pick.png` + `_glowmask.png`)

**Texture size:** 64×64 (beide Dateien — GeckoLibs `AutoGlowingTexture` erzwingt
Albedo = Glowmask-Canvas). Modell: `assets/eclipse/geo/item/umbral_pick.geo.json`
(GeckoLib-ITEM, **13 Bones / 12 Cubes**, Box-UV). **Geo, Anim UND Texturen sind
GENERIERT** — `python3 scripts/geckolib_gen/items/umbral_pick.py`; Layout:

| Bone | Cube | Box W×H×D | UV | Notizen |
|---|---|---|---|---|
| grip | Haft | 1×12×1 | (0,0) | `wood` in Aschen-Dunkel `#484037` (Icon-Haft) |
| grip | Knochenband | 2×2×2 (inflate −0.35) | (6,0) | `bone_band` (Griffzone, Klingen-Hilt-Sprache) |
| glow_vein_h | Haft-Ader | 1×6×0 (z +0.55) | (22,16) | emissive Ebene, schwebt vor der Haft-Front |
| collar | Kragen | 2×2×2 (inflate −0.1) | (16,0) | `umbral_head` |
| head_core | Kopfkern | 2×2×3 | (26,0) | |
| prong_f | Zinke vorn | 2×2×4 (rest x +4°) | (38,0) | −z; Vorzeichen-Gesetz: +x-Rot senkt das −z-Ende |
| prong_f_tip | Zinkenspitze vorn | 1×1×2 (rest x +10°) | (0,16) | `tip_steel` (gehont blass) |
| prong_b | Zinke hinten | 2×2×4 (rest x −4°) | (50,0) | +z |
| prong_b_tip | Zinkenspitze hinten | 1×1×2 (rest x −10°) | (8,16) | |
| glow_seam_f | Glow-Naht vorn | 1×0×4 | (26,16) | horizontale 0-Höhe-Ebene AUF der Zinke |
| glow_seam_b | Glow-Naht hinten | 1×0×4 | (38,16) | |
| glow_moon_gem | Mondstein | 1×1×1 (inflate 0.16) | (16,16) | emissiv, `flame`, Kronen-Fassung |

**Emissiv (Glowmask):** alle `glow_*`-Bones per automatischem Albedo-Copy —
`seam_glow` (gestrichelte blasse Adern mit Lücken) und `haft_vein` sind shadeless.

**Art-Brief:** dieselbe Materialsprache wie `umbral_blade` — Nachtviolett-Stahl,
`#D8CEC7`-gehonte Spitzen, `#7B4FD0`-Glownähte, Aschenholz-Haft; Palette des finalen
2D-Icons (`textures/item/umbral_pick.png`), das GUI/Ground/Fixed weiterhin zeigen.

**Generator (deterministisch, Re-Runs byte-identisch):**

```
python3 scripts/geckolib_gen/items/umbral_pick.py
```

Texturen NIE von Hand malen (AGENTS.md-Gesetz); AI-Art ersetzt später an identischen
Pfaden/Canvas-Größen.
