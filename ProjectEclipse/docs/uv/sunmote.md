# UV map — Sunmote (`assets/eclipse/textures/entity/sunmote.png` + `_glowmask.png`)

**Texture size:** 32×32 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/sunmote.geo.json` (GeckoLib, 10 bones /
11 cubes, box-UV). As with every geo mob the geo file **is** the UV source of truth — the
painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect
itself, so only the box-UV origins are frozen here:

| Bone | Cube | Box W×H×D | UV origin | Strip (x0,y0)-(x1,y1) |
|---|---|---|---|---|
| halo | ring plate | 5×1×5 | (0,0) | (0,0)-(20,6) |
| glow_crown | 45° spike ×4 | 1×1×2 | (20,0) / (26,0) / (20,3) / (26,3) | 6×3 each |
| glow_ray_a..d | long ray | 1×1×3 | (0,6) / (8,6) / (16,6) / (24,6) | 8×4 each |
| glow_core | corona shell | 3×3×3 | (0,11) | (0,11)-(12,17) |
| glow_kernel | heartbeat | 2×2×2 | (13,11) | (13,11)-(21,15) |

Rows 17–31 of the canvas are unused and stay transparent.

The two rects the materials actually reason about (the rest are plain strips):

| Cube | up | down | north | south | west | east |
|---|---|---|---|---|---|---|
| halo | (5,0)-(10,5) | (10,0)-(15,5) | (5,5)-(10,6) | (15,5)-(20,6) | (10,5)-(15,6) | (0,5)-(5,6) |
| glow_core | (3,11)-(6,14) | (6,11)-(9,14) | (3,14)-(6,17) | (9,14)-(12,17) | (6,14)-(9,17) | (0,14)-(3,17) |

**Art brief (design sheet §1.5):** a captured spark of daylight orbiting the sanctum
altar. Core `#FFF2C0` → `#FFD98A` with `#FFFBE8` flare specks, kernel `#FFFBE8`, wreath
`#FFE9A8` hot in the middle cooling to `#FFD874`/`#FFC24A` at both ends, halo `#FFC24A` →
`#E08A22`. **No dark pixels anywhere** — Iris dims the glow layer back down to the albedo
(P6 conventions §6), so an emissive texel that is dark in the albedo cannot burn.

Two geometry facts the materials depend on:

* The ray/spike cubes are 1 texel thin and 2–3 texels long, and a Bedrock box-UV strip
  runs AROUND the cube, so which end of a face is the outer tip flips per face. The ray
  material is therefore authored **symmetric along its length** — that reads identically
  from every angle and can never end up mirrored. It also carries **no alpha dropouts**:
  one dropped texel is a third of the ray missing on one face while the opposite face
  keeps it, which reads as broken geometry rather than as flicker. The shimmer lives in
  the animation instead (per-ray scale/rotation, 90°-phase staggered).
* The halo's 5×5 up/down faces are painted as an **annulus** (transparent centre, cut
  corners) so the plate reads as a ring around the core, not a lid on top of it. Alpha-0
  texels are free here: the Sunmote renderer stays on the cutout path — unlike the Drift
  Lantern it does **not** call `withTranslucency()`.

**Emissive (glowmask):** everything under a `glow_` bone (core, kernel, wreath) is
auto-emissive at full painted brightness. The `halo` deliberately is **not**: a custom
glow painter lights only its inner edge (alpha 215) plus a sparse speckle on the outer rim
(alpha 90), so the ring reads as catching the core's light instead of as a second sun.
This is the mob's first glowmask — the pre-MC3 renderer faked emission with a whole-model
additive `RenderType.eyes` pass over the entire texture (census falle F-7).

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/sunmote.py
```

Final AI art may replace both PNGs byte-for-byte at the same paths/canvas sizes; keep the
glowmask aligned with whatever pixels should burn at night.
