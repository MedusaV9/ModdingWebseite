# UV map — Storm Hound (`assets/eclipse/textures/entity/storm_hound.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/storm_hound.geo.json` (GeckoLib, 24 bones /
24 cubes — lean quadruped, hitbox 0.9×1.1). As with all GeckoLib mobs, the geo file
**is** the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses
it and computes every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | trunk | 8×7×16 | box-UV (0,0) | pivot (0,10,2); electric veins branch across the flank faces |
| glow_spine_a/b/c | lightning-rod shards | 1×3×2 each | box-UV (0,52) / (7,52) / (14,52) | swept back −18°/−24°/−30°; windup anim scales these |
| head | skull | 5×4×6 | box-UV (0,24) | head-tracked (pivot 0,12,−8); eye dots in the top corners of the north face |
| head | snout | 3×2×4 | box-UV (23,24) | dark bridge + nose; NO eye glow here (painter gates on face width 5) |
| jaw | lower jaw | 3×1×4 | box-UV (23,31) | split-jaw hinge at (0,10.5,−12.5); pale electric inner mouth on the up face |
| glow_horn | antenna | 1×4×1 | box-UV (49,0) | swept +35°; the "lightning rod" |
| mane_a / mane_b / mane_c | neck ruff | 3×4×2 / 2×4×2 / 2×4×2 | box-UV (37,24) / (48,6) / (48,13) | shaggy storm ruff; molang tremor in windup |
| scapula_l / scapula_r | shoulder blades | 1×3×4 each | box-UV (0,57) / (10,57) | MA6: **new parents of the forelegs** (pivots ±3,10,−4); ride above the topline in `howl`/`charge_windup` |
| leg_fl / leg_fr | upper forelegs | 2×4×3 | box-UV (0,36) / (11,36) | hip pivots at y=7; now children of `scapula_l`/`scapula_r` |
| leg_fl_lower / leg_fr_lower | forelegs lower | 2×4×2 | box-UV (22,37) / (31,37) | knee pivots at y=4, 1 px overlap hides the joint in swing |
| leg_bl / leg_br | upper hindlegs | 2×4×3 | box-UV (0,44) / (11,44) | |
| leg_bl_lower / leg_br_lower | hindlegs lower | 2×4×2 | box-UV (22,44) / (31,44) | fur darkens toward the paws |
| tail_a | tail base | 3×3×6 | box-UV (40,37) | raised +30°; whips at 2× stride frequency |
| tail_b | tail mid | 2×2×7 | box-UV (40,47) | +15° on top of tail_a |
| tail_c | tail tip | 1×1×5 | box-UV (20,57) | faint static charge on the tip |

**Art brief (design sheet §2.3 "storm_hound"):** pack hunter whelped inside the fog
storms — two-tone storm fur (`#3A4148` grained/dithered against `#2C3238`, EntitySkinArtist-style
streaks), darker jaw `#1E2126` with a pale electric inner mouth `#D9F6FF` on the jaw's
up face, deterministic branching electric veins (`#9FE8FF`, cores `#E8FBFF`) wandering
the flank midline with sparse vertical forks, eye dots `#D9F6FF`, and shadeless
flame-material spine shards + horn (`#9FE8FF`/`#E8FBFF`) that read bright even unlit.

**Emissive (glowmask):** the three `glow_spine_*` shards + `glow_horn` (auto-included
via the `glow_` bone prefix), the flank veins (the glow painter re-traces the same
deterministic vein test as the albedo), the two eye dots (gated to the 5-px-wide skull
face — the 3-px snout face is excluded, no glowing nostrils), and a faint reduced-alpha
charge on the tail tip, plus (MA6) a faint **crest line along each `scapula_*`** so the
blade ridge catches the charge when the shoulders rise. `StormHoundRenderer` installs the glow layer via
`withGlowmask()`; the charge_windup anim scales the spine bones so the glow visibly
ramps before a lunge.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/storm_hound.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; if
the vein layout changes, regenerate the glowmask with it (both are traced by the same
`_vein_at` test — hand-drawn art must keep albedo and glow veins aligned).
