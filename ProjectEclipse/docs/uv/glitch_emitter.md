# UV map — Glitch Emitter (`assets/eclipse/textures/entity/glitch_emitter.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` hard-fails on a
canvas mismatch, census §7 F-7). Model: `assets/eclipse/geo/entity/glitch_emitter.geo.json`
(32 bones / 24 cubes, box-UV, `format_version 1.12.0`). Painter:
`tools/woahdome/gen_glitch_emitter_textures.py` (census §7 F-11 — this emitter's painter
deliberately lives under `tools/woahdome/`, not `scripts/geckolib_gen/mobs/`).

Every cube size is an **integer**, so every box-UV face rect lands on whole texels — the
validator reports 0 fractional-UV warnings. The eight segments of a hoop are identical
cubes and therefore intentionally **share one atlas rect**.

## Atlas (all rects exclusive on the right/bottom edge)

| Bone(s) | Box W×H×D | UV origin | Footprint | Rect | Emissive |
|---|---|---|---|---|---|
| `base` | 12×3×12 | (0,0) | 48×15 | (0,0)-(48,15) | — |
| `leg_0..2` | 2×5×2 | (48,0) | 8×7 | (48,0)-(56,7) | — |
| `antenna` (mast) | 1×9×1 | (56,0) | 4×10 | (56,0)-(60,10) | tip band, 4 px |
| `antenna` (knob) | 3×3×3 | (48,10) | 12×6 | (48,10)-(60,16) | full, 72 px |
| `pylon` | 4×15×4 | (0,16) | 16×19 | (0,16)-(16,35) | — |
| `core` | 6×6×6 | (16,16) | 24×12 | (16,16)-(40,28) | full, 288 px |
| `ring_inner_seg_0..7` | 1×2×5 | (16,28) | 12×7 | (16,28)-(28,35) | top seam, 15 px |
| `ring_outer_seg_0..7` | 2×2×7 | (40,16) | 18×9 | (40,16)-(58,25) | — |

24 cubes → 8 distinct rects, **0 overlapping atlas pixels**, 1726/4096 px used (42.1 %),
379 emissive pixels.

## Art brief

Dark gunmetal chassis (`#282C31`–`#4A5158`) with copper edging (`#7A4428`–`#D68A52`) and
a sparse oxidized-patina speckle (`#5E7A64`–`#8BAD8D`). The energy palette is C3's dome
green (`#4DF29E`, highlights `#96FFCD`) so the device reads as the same system as the
shell it powers.

Per-cube treatment:

- **base plate** — gunmetal deck, copper 1-px frame on the side faces, 6 % oxide speckle.
- **legs** — plain dark struts (they sit in the plate's shadow).
- **antenna mast** — mid gunmetal with two copper collars and an emissive green tip band.
  Deliberately **not** the dark palette: the mast is 1×1 px in cross-section and is the
  only thing linking the glowing knob to the pylon, so near-black pixels make the knob
  read as a detached floating cube against a dark sky.
- **antenna knob** — toxic green, fully emissive (the sky beam's origin).
- **pylon** — gunmetal with copper bands at thirds plus one green seam.
- **core** — toxic green with darker scanline rows every 3 px, fully emissive.
- **ring_outer** — copper with a dark gunmetal **end cap** on the two 2×2 segment faces
  (so the octagon reads as eight discrete segments) and a 1-px oxide wear line along the
  bottom of each long wall. No `edge_frame` here: the walls are only `sy = 2` px tall, so
  a 1-px frame would cover 100 % of them and turn the whole hoop patina-green.
- **ring_inner** — brighter copper with a toxic seam on its top edge (`up` face + the top
  row of both long walls). The inner hoop is the one the eye can track inside the outer
  one, so it is the only ring that glows.

## Emissive (glowmask)

Core cube, antenna knob, antenna tip band and the inner-hoop seam only; transparent
everywhere else (the repo's `AutoGlowingGeoLayer` convention, enabled via
`DomeEmitterRenderer.withGlowmask()`).

## Generator (deterministic, byte-identical reruns)

```
python3 tools/woahdome/gen_glitch_emitter_textures.py
```

Seeded `numpy.random.default_rng(20260101)`; two consecutive runs produce identical MD5s.
Note that the painter walks the atlas in source order, so **inserting a paint call
re-rolls every rect painted after it** — re-run and re-check both PNGs after any edit.
