# UV map — Shadow Bolt (`assets/eclipse/textures/entity/shadow_bolt.png` + `_glowmask.png`)

**Texture size:** 32×32 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/shadow_bolt.geo.json` (GeckoLib, 10 bones /
8 cubes — the cultist/warden projectile spike-orb, hitbox 0.35×0.35). The geo file
**is** the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses
it and computes every face rect itself, so only the layout is frozen here (verified
overlap-free: 186 of 1024 texels used, 0 collisions, nothing off-canvas):

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| glow_core | orb | 3×3×3 | box-UV (0,0) | flame-material violet core |
| spikes | X shaft | 6×1×1 | box-UV (0,8) | skewers the orb along X |
| spikes | Y shaft | 1×6×1 | box-UV (0,12) | along Y |
| spikes | Z shaft | 1×1×6 | box-UV (14,8) | along Z |
| glow_lance | nose collar | 2×2×2 | box-UV (12,0) | z −4…−2, sleeves the Z shaft; heat slice t 0.30→0.62 |
| glow_tip | nose needle | 1×1×2 | box-UV (22,0) | z −5.5…−3.5, the point; heat slice t 0.62→1.00 |
| glow_wake_a | trail shard | 1×1×2 | box-UV (0,20) | z 3…5 at x +1.5 |
| glow_wake_b | trail shard | 1×1×2 | box-UV (8,20) | z 3…5 at x −1.5 |

**Bone rig (this is what makes the bolt aim, spin and wobble):**

```
root → aim → spin → glow_core, spikes, glow_lance, glow_tip
           → wake → glow_wake_a, glow_wake_b
```

`GeoEntityRenderer` forces a non-`LivingEntity` to yaw 0 and ignores pitch entirely, so
the projectile's heading can only reach the model through Molang. `aim` therefore reads
`query.body_x_rotation` / `query.body_y_rotation` (the interpolated entity pitch/yaw,
registered for every entity, not just living ones) and reproduces the flight heading
exactly — verified 10/10 test headings within 1°. `spin` carries the continuous roll plus
the nutation wobble; `wake` lags behind on `query.yaw_speed` / `query.vertical_speed` so
the trail whips outward through turns.

**Art brief:** core is flame-material `#EFE3FF` → `#B98CFF` (shadeless); spike shafts are
near-black obsidian `#232030` whose tip pixels (both extremes of each shaft's long axis
and the 1×1 end caps) pick up the core light (`#B98CFF` mixed toward the core white). The
nose spear and the wake shards are painted off **one continuous longitudinal ramp** —
`#3B2861` cold at +Z, `#9F6EEB` through the middle, `#E4D5FF` only in the front third of
the needle. Wake shards run `#2A1D45` → `#C6A6FF` toward the bolt.

**Why the ramp is longitudinal and not radial:** `spin` turns the nose bones a full 720°
per second. If any face were painted hotter than its neighbour around the roll axis, the
bolt would strobe once per rotation. The `_z_t` helper in the driver resolves each texel's
position along model Z from a **measured** face→axis table (the MB3 harness dumps every
baked `GeoQuad`'s UV against its vertex positions: `+fx → −Z` on `east`, `+fx → +Z` on
`west`, `+fy → −Z` on `up`/`down`, `north` = the −Z cap).

**Emissive (glowmask):** the `glow_core` orb (auto via prefix) + the spike tip pixels
(custom glow painter, alpha 210) + the nose spear (alpha 50→215 along the ramp) + the
wake shards (steep `t²` ramp, alpha 30→230 toward the bolt). `ShadowBoltRenderer` renders
the entity fullbright (block light 15) and adds `AutoGlowingGeoLayer`, so the bolt reads
identically in lit corridors and pitch-black vault rooms.

Note the two layers behave differently and the driver relies on it: the albedo goes
through `entityCutoutNoCull`, which alpha-**tests** (a partial alpha renders fully
opaque), while the glow layer blends — so every fade in this model lives in the glowmask
alpha, never in the albedo alpha.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/shadow_bolt.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size.
