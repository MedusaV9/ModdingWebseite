# UV map — Orin the Sun-Reader (`assets/eclipse/textures/entity/wizard_orin.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/wizard_orin.geo.json` (GeckoLib, 14 bones /
15 cubes, box-UV, zero strip overlaps). The geo file **is** the UV source of truth — the
painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect
itself, so only the box-UV origins are frozen here:

| Bone | Cube | Box W×H×D | UV origin | Strip (x0,y0)-(x1,y1) |
|---|---|---|---|---|
| robe_lower | skirt | 9×11×6 | (0,0) | (0,0)-(30,17) |
| torso | chest | 7×10×5 | (30,0) | (30,0)-(54,15) |
| head | head | 5×5×5 | (0,17) | (0,17)-(20,27) |
| hat | brim | 8×1×8 | (20,17) | (20,17)-(52,26) |
| hat | cone | 5×3.5×5 | (0,27) | (0,27)-(20,36) |
| hat | tip | 3×2.5×3 | (20,27) | (20,27)-(32,33) |
| glow_hat_star | star charm | 1×1×1 | (32,27) | (32,27)-(36,29) |
| glow_staff_tip | starlit tip | 1.5×1.5×1.5 | (38,27) | (38,27)-(44,30) |
| arm_right | sleeve | 3×9×3 | (0,36) | (0,36)-(12,48) |
| arm_left | sleeve | 3×9×3 | (12,36) | (12,36)-(24,48) |
| staff | shaft | 1×14×1 | (24,36) | (24,36)-(28,51) |
| beard | main fall | 4×8×1 | (28,36) | (28,36)-(38,45) |
| beard | tip tuft | 2×3×1 | (38,36) | (38,36)-(44,40) |
| spyglass | back-slung tube | 2×6×2 | (30,48) | (30,48)-(38,56) |
| scarf | collar wrap | 8×3×6 (inflate 0.25) | (0,52) | (0,52)-(28,61) |

**Art brief (IDEA-19 §3, W4-WIZARD):** a hermit astronomer — midnight-blue robe
(`#1E2748`, sleeves/hood/hat `#161C36`) embroidered with sparse constellation stitches
(single pixels blended `#F5E6B8`→`#9FC4FF`, side faces only), a brass belt band on the
torso (`#B08D42`), grey-violet scarf (`#3D3A66`), warm lantern-lit face (`#E8B98A`,
brighter toward the nose, dark deep-set eyes + silver brows), long silver beard
(`#C9CCD4`, vertical strand streaks with dark partings), oak staff (`#6B4A2E`), brass
spyglass slung on the back, and a pointed hat whose brim/cone/tip carry the same
stitches. The face lives on the head's **north** face; every other head face is hood
blue.

**Emissive (glowmask):** the star charm (`#FFF7DC`→`#FFE9A6`) and the staff tip
(`#EAF6FF`→`#BFE2FF`) at full painted brightness (auto — `glow_` bones), PLUS the
constellation stitches at alpha 190 on robe/torso/sleeves/hat. Stitch predicate and
colors are shared between the albedo material and the glow painter (same noise salt),
so day-art and night-glow always agree. Skin, beard, brass, wood, scarf stay fully
transparent in the glowmask.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/wizard_orin.py
```

Validate model + animations together:

```
python3 scripts/geckolib_gen/validate_geo.py \
    src/main/resources/assets/eclipse/geo/entity/wizard_orin.geo.json \
    src/main/resources/assets/eclipse/animations/entity/wizard_orin.animation.json
```

Final AI art may replace both PNGs byte-for-byte at the same paths/canvas sizes; keep the
glowmask aligned with whatever pixels should burn at night (stitches, star charm, staff
tip).
