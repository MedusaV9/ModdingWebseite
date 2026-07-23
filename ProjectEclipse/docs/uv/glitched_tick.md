# UV map — Glitched Tick (`assets/eclipse/textures/entity/glitched_tick.png` + `_alt.png` + 2 glowmasks)

**Texture size:** 64×64 — **four files**: `glitched_tick.png` (calm frame),
`glitched_tick_alt.png` (corruption frame the renderer flickers to for 2–4 t bursts),
plus a `_glowmask.png` for each (GeckoLib appends `_glowmask` to whichever albedo is
active — matching canvases enforced). Model:
`assets/eclipse/geo/entity/glitched_tick.geo.json` (GeckoLib, 8 bones / 14 cubes —
0.5-block shard-mite: 6 stub legs grouped into two rows, SPLIT carapace with the
magenta core exposed in the gap, mandibled head). The geo file **is** the UV source of
truth; layout:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | abdomen | 6×4×8 | box-UV (0,0) | glitch hide, fringed edges |
| glow_core | exposed core | 3×1×6 | box-UV (0,12) | fully emissive; throbs in `idle`, flares on `latch` |
| carapace_right | split plate | 4×2×8 | box-UV (28,0) | cants outward — the split read |
| carapace_left | split plate | 4×2×8 | box-UV (28,10) | mirrored cant |
| head | head + mandibles | 4×3×3 / 2×2×1 ×2 | box-UV (0,19) / (14,19) / (14,22) | mandibles twitch; no head tracking |
| legs_right | 3 stubs | 2×2×1 ×3 | box-UV (0,25)/(6,25)/(12,25) | animated as one row (skitter) |
| legs_left | 3 stubs | 2×2×1 ×3 | box-UV (18,25)/(24,25)/(30,25) | opposite phase |

**Art brief (design sheet §2.3 "glitched", kind TICK):** shared glitch language
(`scripts/geckolib_gen/mobs/glitch_lib.py`) — desaturated `#4A4A52`-family body, the
carapace plates a touch darker with `#FF3B6B`/`#37F2E5` RGB-split rims; the exposed
core between the plates is the `#FF6BF2` heart material. The **`_alt` frame** re-runs
the same materials with `alt=True` (scanline displacement + band crush) — on a mob
this small the flicker reads as the whole bug dropping frames.

**Emissive (glowmask):** the `glow_core` strip (shadeless), a thin glowing rim along
each carapace plate's inner (split-facing) edge, pinpoint eyes. Alt masks brighten the
rims.

**Generator (deterministic, byte-identical reruns — writes all 4 PNGs):**

```
python3 scripts/geckolib_gen/mobs/glitched_tick.py
```

Final AI art may replace the PNGs byte-for-byte at the same paths/canvas size; keep
base↔alt aligned per-pixel or the flicker smears.
