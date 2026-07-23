# UV map — Glitched Husk (`assets/eclipse/textures/entity/glitched_husk.png` + `_alt.png` + 2 glowmasks)

**Texture size:** 64×64 — **four files**: `glitched_husk.png` (calm frame),
`glitched_husk_alt.png` (corruption frame the renderer flickers to for 2–4 t bursts),
and a `_glowmask.png` for EACH (GeckoLib's `AutoGlowingTexture` appends `_glowmask` to
whichever albedo is active, so the alt frame needs its own mask at the same canvas
size). Model: `assets/eclipse/geo/entity/glitched_husk.geo.json` (GeckoLib, 10 bones /
11 cubes — humanoid but WRONG: torso split, one arm 6px longer, head tilted with a
displaced face shard). The geo file **is** the UV source of truth; layout:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | torso | 8×12×4 | box-UV (0,0) | heart-core glows through cracks (mask only) |
| shard_torso | detached slab | 4×7×4 | box-UV (0,16) | floats 2px off the right hip |
| glow_seam | seam slivers | 6×1×6 / 1×10×1 (+0.2 infl) | box-UV (0,43) / (24,43) | fully emissive |
| head | skull | 8×8×8 | box-UV (24,0) | baked 12° tilt; head-tracked as a cluster |
| head_shard | displaced half-face | 5×4×3 | box-UV (16,16) | one step behind the skull |
| arm_right | LONG arm | 3×16×3 | box-UV (32,16) | drags to knee height |
| arm_left | short arm | 3×10×3 | box-UV (44,16) | the asymmetry read |
| leg_right / leg_left | legs | 4×12×4 | box-UV (0,27) / (16,27) | uneven shamble in anim |

**Art brief (design sheet §2.3 "glitched", kind HUSK):** vanilla-silhouette-gone-wrong
in the shared glitch language (`scripts/geckolib_gen/mobs/glitch_lib.py`) —
desaturated `#4A4A52`-family flesh and rags with 1px RGB-split edge fringes
(`#FF3B6B` magenta right edges / `#37F2E5` cyan left edges). The **`_alt` frame**
re-runs the same materials with `alt=True`: scanline rows displaced horizontally in
2px blocks + whole bands hue-crushed toward magenta/cyan — the flicker must read as
datamosh corruption, not a palette swap.

**Emissive (glowmask):** the `glow_seam` slivers (shadeless white-magenta), a
`#FF6BF2`/`#C13BFF` heart-core shining through torso cracks (body bone mask), and
pinpoint eyes. The alt masks add wider chromatic seam bleed.

**Generator (deterministic, byte-identical reruns — writes all 4 PNGs):**

```
python3 scripts/geckolib_gen/mobs/glitched_husk.py
```

Final AI art may replace the PNGs byte-for-byte at the same paths/canvas size; keep
base↔alt aligned per-pixel (same UV islands) or the renderer's swap will smear.
