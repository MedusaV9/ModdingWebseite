# UV map — Fog Revenant (`assets/eclipse/textures/entity/fog_revenant.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/fog_revenant.geo.json` (GeckoLib, 16 bones /
16 cubes — tall hovering wraith, hitbox 0.7×2.2). As with all GeckoLib mobs, the geo
file **is** the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`)
parses it and computes every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| torso | chest | 8×8×5 | box-UV (0,32) | pivots at its base (0,20) — the whole upper chain leans with it |
| skirt_mid | robe segment | 8×7×6 | box-UV (0,18) | pendulum child of torso |
| skirt_low | robe hem | 10×9×8 | box-UV (0,0) | widest segment; **ragged alpha-cutout hem** on the side faces, floats 4 px off the ground |
| head | skull | 6×6×6 | box-UV (37,0) | head-tracked; two 1×2 cyan eye slits on the north face at face-cols 1 and 4 |
| hood | shell | 6×6×6 +0.6 inflate | per-face: E (37,19), W (49,19), S (55,19), U (43,13), D (49,13) — **no north face** | open hood front: the skull sits recessed 0.6 px inside the rim |
| hood | peak | 4×3×4 | box-UV (26,46) | pitched −8°, slumps behind the head |
| arm_right | sleeve | 3×13×3 | box-UV (28,29) | shoulder pivot (−5,26); reaches past the hem |
| claw_right | claw | 3×4×3 | box-UV (0,46) | wrist child; bone talons |
| arm_left | sleeve | 3×13×3 | box-UV (41,29) | mirror layout, separate UV (asymmetric weathering) |
| claw_left | claw | 3×4×3 | box-UV (13,46) | |
| growth | coral shelf | 3×4×3 | box-UV (43,46) | right-shoulder fog-coral, bone rolled +8° |
| growth | coral nub low | 2×3×2 | box-UV (54,26) | cube-rotated +18° |
| growth | coral nub high | 2×2×2 | box-UV (0,54) | cube-rotated −12° |
| glow_wisp_a | wisp | 2×2×2 | box-UV (9,54) | orbit child of `wisps` (pivot 0,18,0); radius 7 |
| glow_wisp_b | wisp | 2×2×2 | box-UV (18,54) | low orbit, radius ~7 |
| glow_wisp_c | wisp | 2×2×2 | box-UV (27,54) | high orbit, radius ~7 |

`wisps` (cube-less parent, pivot 0,18,0) is the orbit driver: the anims spin only its Y
rotation, so all three wisps circle the robe at three heights. `body` (pivot 0,4,0) is
the hover-bob root; `root` stays clean for the death drift.

**Art brief (design sheet §2.3 "fog_revenant"):** what the fog keeps, it remakes — torn
near-black robe (`#23262E`, sleeves `#2A2E38`, hood `#1B1D24`) with a vertical cloth
weave, a pale mist sheen creeping up from the ragged hem, and a shadowed skull
(`#15171C` base, dim bone `#8A8578`) hidden under the hood. Two cyan eye slits
(`#8FD5E8`, cores `#DFFBFF`) burn through the shadow. Bone claws `#C9C4B4` with darker
knuckle bands; the shoulder fog-coral shades `#5E6B7A` → `#9DB3C9` toward the tips; the
three wisps are flame-material cyan (`#8FD5E8`/`#DFFBFF`, shadeless).

**Emissive (glowmask):** the three `glow_wisp_*` cubes (auto-included via the `glow_`
bone prefix) + ONLY the two eye-slit pixels pairs on the head north face (custom glow
painter). Everything else transparent. `FogRevenantRenderer` installs the glow layer via
`withGlowmask()`.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/fog_revenant.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; keep
the hem alpha-cutout and the hood's missing north face in mind (those pixels/faces are
structural, not paint).
