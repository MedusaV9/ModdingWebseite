# UV map — Pale Sentinel (`assets/eclipse/textures/entity/pale_sentinel.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/pale_sentinel.geo.json` (GeckoLib, 16 bones /
18 cubes — 2.4-block gaunt tree-revenant, hitbox 0.8×2.6). The geo file **is** the UV
source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes
every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| leg_right | stilt | 3×16×3 | box-UV (0,0) | stilt legs, hip pivots at y16 |
| leg_left | stilt | 3×16×3 | box-UV (12,0) | separate UV (asymmetric grain) |
| pelvis | hip block | 7×4×4 | box-UV (24,0) | parents the tendril skirt |
| tendril_a | root | 2×7×1 | box-UV (32,35) | **ragged alpha-cut hem** on side faces |
| tendril_b | root | 2×8×1 | box-UV (38,35) | longest tendril, rear-right |
| tendril_c | root | 2×7×1 | box-UV (44,35) | rear-center |
| torso | log trunk | 8×10×5 | box-UV (24,8) | pale-oak grain + dark fissures |
| head | skull block | 5×6×5 | box-UV (0,24) | head-tracked; **hollow face** rows 1-4 / cols 1-3 of the north face; ember eyes at face (1,2) + (3,2) |
| antler_right | twig main | 1×6×1 | box-UV (50,0) | crown, rolled −16° |
| antler_right | twig tine | 2×1×1 | box-UV (54,0) | |
| antler_left | twig main | 1×6×1 | box-UV (50,8) | rolled +16° |
| antler_left | twig tine | 2×1×1 | box-UV (54,8) | |
| arm_right | arm | 2×14×2 | box-UV (0,35) | shoulder pivot (−4.5,29); hangs past the knees |
| hand_right | finger long | 1×5×1 | box-UV (8,35) | root-claw fingers, earth-stained tips |
| hand_right | finger short | 1×4×1 | box-UV (12,35) | |
| arm_left | arm | 2×14×2 | box-UV (16,35) | mirror layout, separate UV |
| hand_left | finger long | 1×5×1 | box-UV (24,35) | |
| hand_left | finger short | 1×4×1 | box-UV (28,35) | |

`body` (pivot 0,18,0) is the cube-less locomotion root; `root` stays clean so the
scripted death crumble (`tickDeath`) and burrow sink can move the whole model.

**Art brief (design sheet §2.3 "pale_sentinel"):** pale-oak log grain `#D8D2C4`/`#B9B2A2`
split by near-black bark fissures `#575044`; root-claw hands and skirt tendrils in dry
root grey `#8C8474` with darker node rings and stained tips; dead-twig antlers `#6E6555`.
The face caves into a `#2A261E` hollow — the **orange-ember eyes `#FF9A3C`
(cores `#FFD9A0`) are the only glow on the whole mob**.

**Emissive (glowmask):** ONLY the two eye pixels on the head's north face (custom glow
painter, alpha 235/205 — deliberately faint). There are no `glow_*` bones in this geo.
`PaleSentinelRenderer` installs the layer via `withGlowmask()`.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/pale_sentinel.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; keep
the tendril hem alpha-cutout and the hollow-face recess in mind (structural, not paint).
