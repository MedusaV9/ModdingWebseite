# UV map — Glitched Hound (`assets/eclipse/textures/entity/glitched_hound.png` + `_alt.png` + 2 glowmasks)

**Texture size:** 64×64 — **four files**: `glitched_hound.png` (calm frame),
`glitched_hound_alt.png` (corruption frame the renderer flickers to for 2–4 t bursts),
plus a `_glowmask.png` for each (GeckoLib appends `_glowmask` to whichever albedo is
active — matching canvases enforced). Model:
`assets/eclipse/geo/entity/glitched_hound.geo.json` (GeckoLib, 13 bones / 13 cubes —
lean quadruped on umbral-stalker proportions, datamoshed: the neck is a FRAGMENTED
FLOATING segment, the head+jaw detach from it, one ear is a displaced shard, the hips
have broken off-axis). The geo file **is** the UV source of truth; layout:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | trunk | 8×7×16 | box-UV (0,0) | heart-core glows through rib cracks (mask) |
| hips_shard | broken hip block | 5×6×5 | box-UV (24,23) | rides 1–2px off-axis |
| glow_seam | seam slivers | 3×2×1 / 1×5×6 | box-UV (54,7) / (0,44) | fully emissive |
| neck_shard | floating fragment | 5×4×3 | box-UV (48,0) | gap of air between body and head |
| head | skull | 6×5×6 | box-UV (0,23) | head-tracked; pinpoint eyes on mask |
| jaw | underslung jaw | 5×2×5 | box-UV (44,23) | "arrives before the head" — leads in anim |
| ear_shard | displaced ear | 2×3×1 | box-UV (48,7) | single ear, wrong side |
| leg_fr / fl / br / bl | legs | 2×9×2 | box-UV (20,34)/(28,34)/(36,34)/(44,34) | gallop set |
| tail | tail | 2×2×8 | box-UV (0,34) | whips on blink |

**Art brief (design sheet §2.3 "glitched", kind HOUND):** shared glitch language
(`scripts/geckolib_gen/mobs/glitch_lib.py`) — desaturated `#4A4A52`-family hide with
1px RGB-split edge fringes (`#FF3B6B` / `#37F2E5`); shard bones (neck/hips/ear) are
tinted so the broken geometry reads corrupted even on the calm frame; inner mouth a
dark magenta-tinged void. The **`_alt` frame** re-runs the same materials with
`alt=True` (scanline displacement blocks + magenta/cyan band crush).

**Emissive (glowmask):** the `glow_seam` slivers, the `#FF6BF2`/`#C13BFF` heart-core
through the trunk cracks, pinpoint eyes. Alt masks widen the chromatic bleed.

**Generator (deterministic, byte-identical reruns — writes all 4 PNGs):**

```
python3 scripts/geckolib_gen/mobs/glitched_hound.py
```

Final AI art may replace the PNGs byte-for-byte at the same paths/canvas size; keep
base↔alt aligned per-pixel or the flicker smears.
