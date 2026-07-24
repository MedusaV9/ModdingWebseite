# UV map — Rift Warden (`assets/eclipse/textures/entity/rift_warden.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases; 128 canvas per §2.1 boss rule). Model:
`assets/eclipse/geo/entity/rift_warden.geo.json` (GeckoLib, 18 bones / 18 cubes —
2.9-block vertically-split wraith-knight, hitbox 1.1×3.0). The geo file **is** the UV
source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes
every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| glow_under | void column | 6×10×4 | box-UV (0,28) | fills the hollow under the faulds — the warden hovers on it |
| faulds | skirt armor | 10×8×6 | box-UV (0,0) | widest plate; sways in the stride |
| hips | waist plate | 8×6×4 | box-UV (32,0) | |
| torso | **armor half** | 5×12×5 | box-UV (56,0) | spans x −5..0 ONLY — the right torso half is deliberately missing |
| glow_rift_core | void tear | 4×10×4 | box-UV (76,0) | spans x 0.5..4.5 — replaces the missing torso half |
| glow_shard_a | drift shard | 2×3×2 | box-UV (96,18) | orbit-bobs above the tear |
| glow_shard_b | drift shard | 2×2×2 | box-UV (104,18) | |
| glow_shard_c | drift shard | 1×2×1 | box-UV (112,18) | |
| pauldron_left | floating plate | 7×3×7 | box-UV (0,14) | armor-side pauldron, rolled −6°, floats (no arm attachment) |
| pauldron_right | floating plate | 5×2×5 | box-UV (28,14) | rift-side, smaller/higher, rolled +8° |
| head | horned helm | 6×7×6 | box-UV (92,0) | head-tracked; violet **eye slit** row 3, cols 1-4 of the north face |
| horn | helm horn | 1×6×1 | box-UV (116,0) | single left horn, rolled −22° |
| arm_armor | plated arm | 3×12×3 | box-UV (48,22) | armor-side (−x) arm |
| blade_left | blade main | 1×12×3 | box-UV (60,22) | curved rift-blade; **edge column (fx 0) burns** |
| blade_left | blade tip | 1×7×2 | box-UV (68,22) | cube-rotated −14° (the curve) |
| arm_rift | void arm | 2×10×2 | box-UV (74,22) | rift-side (+x) arm — painted as part of the tear |
| blade_right | blade main | 1×12×3 | box-UV (82,22) | |
| blade_right | blade tip | 1×7×2 | box-UV (90,22) | cube-rotated −14° |

`body` (pivot 0,24,0) is the hover/locomotion root; `root` stays clean for the scripted
60t death implosion (`tickDeath`).

**Art brief (design sheet §2.4 "rift_warden"):** the LEFT half is polished obsidian
plate `#1B1D26`/`#2E3242` with `#4A5068` bevel rims; the RIGHT half is a void tear
shading `#B98CFF` → `#5E2EA8` (core `#E9DCFF`, dark reality-static flecks) with three
drifting shards. Helm horn `#3A3648`. Blades: near-black steel `#232732` with a burning
`#B98CFF` edge column and rift shimmer creeping up from the tips.

**Emissive (glowmask):** the whole rift half — `glow_rift_core`, `glow_shard_*`,
`glow_under` (auto via prefix) plus `arm_rift` at strength 0.85 — the helm eye slit and
both blades' edge columns (custom glow painters). Armor half stays dark.
`RiftWardenRenderer` installs the layer via `withGlowmask()`.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/rift_warden.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; the
split-torso gap (armor cube x −5..0, tear cube x 0.5..4.5) is geometry, not paint.
