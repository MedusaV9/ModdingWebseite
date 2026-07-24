# UV map — Respawn Door (`assets/eclipse/textures/block/respawn_door.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/block/respawn_door.geo.json` (GeckoLib **block**
model, 6 bones / 14 cubes — P6-W3, rendered by
`client/entity/door/RespawnDoorRenderer` off the multiblock's controller BE). As with
every GeckoLib asset here, the geo file **is** the UV source of truth — the painter
(`scripts/geckolib_gen/paint_lib.py`) parses it and computes each face rect itself, so
only the layout is frozen below. All UVs are hand-packed per-face rects (no box-UV).

Model scale: 16 units = 1 block. The door stands 79.5 u (~5 blocks) tall and 47 u
(~3 blocks) wide — exactly the 3×5 bulkhead aperture, inset a hair to avoid z-fighting
the sterncastle pillars. Authored front-facing NORTH (Blockbench default);
`GeoBlockRenderer` yaws it to the blockstate `FACING` (EAST on the ship).

| Bone | Cube | Box W×H×D | Front UV | Notes |
|---|---|---|---|---|
| frame | jamb ×2 (`±19.5..±23.5`) | 4×79.5×6 | N (84,0) | shared rect for both jambs (mirror-safe: barnacled silverwood) |
| frame | lintel/arch header | 39×16×6 | N (0,80) | carries the carved eclipse arch relief |
| frame | sill | 39×2×7 | N (0,104) | y 0.25..2.25, z-proud by 0.5 u — no coplanar faces with jambs/leaves |
| glow_void | void plane | 40×62×0 | N=S (104,0) | z=+2.5 BEHIND the leaves; only visible through the seam/holes — emissive (`glow_` prefix) |
| glow_disc | eclipse disc | 14×10×0 | N=S (104,31) | floats 0.25 u proud of the header; ringed eclipse sigil — emissive |
| leaf_px / leaf_nx | main slab | 19×61×4 | N (19,0) / (0,0) | hinge pivots at x=±19.5, z=+1.5; leaves meet at the center seam |
| leaf_px / leaf_nx | silver band ×2 | 18×5×1 | N (0,122) | tarnished strap bands at y 12 and 45 |
| leaf_px / leaf_nx | ring handle | 6×8×1.5 | N (104,41) | oversized ring pair flanking the seam at y 27..35 |

**Art brief (design sheet §2.5 "Respawn Door"):** the imposing double door in the ghost
ship's sterncastle bulkhead — blackened-oak leaves (`#241B14` planks over `#1A130E`
grooves) carved with an eclipse-glyph relief, tarnished-silver banding and jamb wale
(`#8C8F9A`/`#6F7280`), oversized ring handles, and purple void light bleeding through
every gap: seam, plank cracks, under the sill, around the arch. Purples: `#B98CFF`
blaze, `#E7D6FF` core, `#6E4DA8` fade, `#43206B` void mid, `#16081F` void edge.

**Emissive (glowmask):** the `glow_void` plane and `glow_disc` are `glow_`-prefixed
bones — their albedo is copied to the glowmask at full strength automatically. The
leaves/frame additionally get hand-painted glow pixels from the painter: glyph strokes,
ring-handle glint, and a 1-px edge bleed around every leaf border so light reads as
leaking around the slab even at MC block resolution (4904 glow px total).
`RespawnDoorRenderer` installs the `AutoGlowingGeoLayer`; the animated 0..1 spill
strength for P2's Veil hook is `RespawnDoorBlockEntity.getGlowStrength()`.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/respawn_door.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; keep
the glowmask in sync (same canvas, glow where light should bloom) or regenerate both.
