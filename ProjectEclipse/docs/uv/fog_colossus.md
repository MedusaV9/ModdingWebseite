# UV map — Fog Colossus (`assets/eclipse/textures/entity/fog_colossus.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces
matching canvases; 128² is the frozen §6 canvas for the colossus tier). Model:
`assets/eclipse/geo/entity/fog_colossus.geo.json` (GeckoLib, 14 bones / 17 cubes,
3.4-block hulk — massive forearms, tiny head sunk between the shoulders, cracked-slab
back, stumpy legs; walks half-gorilla). As with all GeckoLib mobs, the geo file **is**
the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it
and computes every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | barrel | 22×22×12 | box-UV (0,0) | cracked slate, wandering fissures |
| shoulders | yoke | 26×16×16 | box-UV (0,34) | widest slab; fissures + coral fringe |
| head | sunken head | 7×7×7 | box-UV (68,0) | head-tracked; 2 ember eyes north face |
| back_slab_low | cracked slab | 16×14×3 | box-UV (84,34) | fissured back plate |
| back_slab_high | cracked slab | 12×12×3 | box-UV (84,51) | overlaps low slab, offset |
| shelf_right | coral shelves | 6×3×6 / 4×2×4 | box-UV (96,0) / (72,66) | fog-coral gradient, NO glow |
| shelf_left | coral shelves | 6×3×6 / 4×2×4 | box-UV (88,116) / (72,72) | mirrored growth |
| arm_right / arm_left | upper arms | 9×18×9 | box-UV (0,66) / (36,66) | slate, pit-weathered |
| forearm_right | forearm + knuckle | 11×24×11 / 10×5×10 | box-UV (0,93) / (88,66) | massive; knuckle pad walks the ground |
| forearm_left | forearm + knuckle | 11×24×11 / 10×5×10 | box-UV (44,93) / (88,81) | mirrored |
| leg_right / leg_left | stumps | 9×11×9 | box-UV (72,14) / (88,96) | darker slate, load-bearing |

**Art brief (design sheet §2.3 `fog_colossus`):** hulking round-shouldered brute
overgrown by the fog — body is cracked storm slate `#3E444D` (dark variant `#33383F`,
legs `#363C44`) with **glowing fissures** (wandering vertical cracks, `#8FD5E8` →
`#CFF3FF` hot centers) painted into body/shoulders/back slabs/forearms; fog-coral
shelf growths on back and shoulders run a `#77879B` → `#B7C9DC` vertical gradient
(matte, misty — deliberately not emissive); tiny head `#31363D` with two `#CFF3FF`
ember eyes. Weather pits (×0.62) and pale mineral flecks (×1.28) break up every slate
face.

**Emissive (glowmask):** the fissure cracks on every slate bone + the two eyes — the
telegraph read for the slam (fissures flare with the `slam` raise) and the light that
bleeds out during the 50 t collapse. Coral shelves stay dark on the mask.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/fog_colossus.py
```

Final AI art may replace either PNG byte-for-byte at the same path/canvas size; keep
the fissure pixels in the glowmask aligned with the albedo cracks or the flare read
dies.
