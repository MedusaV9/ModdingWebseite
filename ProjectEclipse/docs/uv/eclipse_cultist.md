# UV map — Eclipse Cultist (`assets/eclipse/textures/entity/eclipse_cultist.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/eclipse_cultist.geo.json` (GeckoLib, 13 bones /
11 cubes — 1.9-block hunched robed caster, hitbox 0.6×1.9). The geo file **is** the UV
source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes
every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| robe_lower | skirt cone | 8×10×5 | box-UV (0,0) | floor-length robe; **dashed sigil-trim band** on hem row fh−2 |
| torso | chest | 6×10×4 | box-UV (26,0) | dashed trim column down the north-face center (rank stole) |
| head | face block | 5×5×5 | box-UV (0,16) | head-tracked; void shadow with violet eyes at face (1,2) + (3,2) |
| hood | shell | 5×5×5 +0.5 inflate | per-face: E (20,16), W (25,16), S (30,16), U (35,16), D (40,16) — **no north face** | open hood front; the face sits recessed inside |
| hood | peak | 3×2×3 | box-UV (46,0) | pitched −12°, slumps backward |
| arm_right | sleeve | 3×9×3 | box-UV (0,28) | wide sleeve; knife wrist child |
| knife | ritual knife | 1×4×1 | box-UV (12,28) | grip on top row, honed steel below |
| arm_left | sleeve | 3×9×3 | box-UV (16,28) | mirror layout, separate UV |
| glow_rune_a | page quad | 0×3×2 | per-face: E (28,28), W (31,28) | flat X-plane quad |
| glow_rune_b | page quad | 2×3×0 | per-face: N (34,28), S (37,28) | flat Z-plane quad |
| glow_rune_c | page quad | 2×3×0 | per-face: N (40,28), S (43,28) | flat Z-plane quad |

`runes` (cube-less, pivot 4.5,12,0) is the orbit driver — anims spin only its Y rotation
so the three pages circle the left hip. `body` (pivot 0,10,0) is the locomotion root.

**Art brief (design sheet §2.3 "eclipse_cultist"):** the same charcoal robe family as
eclipsed players — cloth `#26232E` (sleeves `#2C2836`, hood `#1B1922`) in a vertical
weave, with `#B98CFF` sigil trim dashes on the hem and chest. Under the hood only shadow
`#0E0C14` and two violet ember eyes (`#B98CFF`, core `#E7D6FF`). Ritual knife: wrapped
grip `#4A4152`, steel `#C8CCD8` with a bright honed-edge column. Rune pages are
flame-material violet (`#EFE3FF`→`#B98CFF`, shadeless).

**Emissive (glowmask):** the three `glow_rune_*` quads (auto-included via the `glow_`
prefix), the two eye pixels (custom glow painter, alpha 255/225) and the hem trim dashes
(custom glow painter, faint alpha 130). `EclipseCultistRenderer` installs the layer via
`withGlowmask()`.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/eclipse_cultist.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; keep
the hood's missing north face in mind (structural, not paint).
