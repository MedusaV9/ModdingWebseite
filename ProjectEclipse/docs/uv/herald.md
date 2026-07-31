# UV map — The Herald of the Eclipse (`assets/eclipse/textures/entity/herald.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases; 128 canvas per the §2.1 boss rule; the pre-conversion sheet was a 256×256
vanilla 2× repaint — byte-layout is NOT compatible). Model:
`assets/eclipse/geo/entity/herald.geo.json` (GeckoLib, **31 bones / 35 cubes** — floating
godhead, hitbox 2.2×3.2, core center 2.5 up). The geo file **is** the UV source of truth —
the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect
itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| head | godhead core | 12×12×12 | box-UV (0,0) | head-tracked; faceted black glass + wandering gold fissures |
| head | brow sill | 8×2×2 | box-UV (48,0) | proud ledge over the eye, gold-warmed bottom row |
| head | crown spike L/R | 1×5×1 | box-UV (68,0) / (72,0) | rear crown, cube-rotated outward; burning gold tips |
| glow_eye | inner eye | 6×6×6 | box-UV (48,6) | protrudes 1px from the core's front; gold furnace, 2×2 void pupil at north (fx 2-3, fy 2-3); whole bone auto-glows |
| glow_veins | front plate | 10×10×1 | box-UV (76,0) | quasi-transparent plate 0.75px proud of the core — ONLY the wandering gold vein pixels are opaque (auto-glow) |
| glow_veins | side column L/R | 1×10×1 | box-UV (98,0) / (102,0) | dashed gold seams up the core's flanks |
| horn_left | base + tip | 2×6×2, 1×5×1 | box-UV (106,0) / (114,0) | obsidian, cube-rotated out/up; tip rows burn gold |
| horn_right | base + tip | 2×6×2, 1×5×1 | box-UV (106,8) / (114,8) | mirror |
| shield_left | plate + crest fin | 2×10×7, 1×7×3 | box-UV (0,24) / (18,24) | floating shoulder shield, faceted dark glass; fin's top row + up face burn |
| shield_right | plate + crest fin | 2×10×7, 1×7×3 | box-UV (26,24) / (44,24) | mirror |
| shard1..8 | corona wedge | 2×6×2 | box-UV (i−1)·8,44 | children of the cube-less `ring` bone at r=14px every 45°, yRot pre-rotated radial; pale-violet glass, hot tips (dim glow at rest — the renderer's telegraph layer surges them); P3/death detach hides `shardN` via `HeraldGeoRenderer` |
| halo | 3 floating shards | 1×3×1 | box-UV (64,44) / (68,44) / (72,44) | the volley "ammo" ring at r≈8.7px; fully emissive (strength 1.0) |
| tentacle_{fl,fr,bl,br}_1 | upper segment | 2×10×2 | box-UV (0,52)..(24,52) | 4 chains off the core's underside corners |
| tentacle_{fl,fr,bl,br}_2 | lower segment | 1×9×1 | box-UV (32,52)..(44,52) | chained child; ragged kelp hem |

Cube-less FX/logic bones (no UV): `root` → `body` (locomotion/hover root) →
`ring` (corona spin), `glyph_ring` → **`glyph_orbit_1..3`** (A4's FX anchors, pivots at
r=10px / 120° around the core, staggered heights 42/40/38), and the per-shard bones.
`root` stays clean for the scripted 70t death collapse (`tickDeath`).

**Art brief (spec §2.1, MA3 refinement):** a broken godhead of near-black violet glass
`#181224` re-ground into diagonal facet cells with glassy catch-lights `#3D3158`, laced
with wandering GOLD crack veins `#E8A83A` → `#FFD86A` (~9-texel spacing with breaks); a
blazing gold inner eye with a 2×2 void pupil `#100A18`; three quasi-transparent floating
vein plates whose only opaque pixels are the gold paths; obsidian horns `#201830` with
burning gold tips; dark-glass shoulder shields with a gold crest fin; 8 pale-violet
corona shards `#C88AFF` fading to `#4A2E66` at the base with hot `#E9DCFF` tips; a
hot-lavender halo; and dark umbral tentacle chains `#241C36` with ragged kelp hems.

**Emissive (glowmask — the Herald's FIRST):** `glow_eye` + `glow_veins` auto via the
`glow_` prefix; custom glow painters add the core's gold fissures (same-salt albedo twin,
so mask and albedo can never drift), the crown-spike + horn tips, the shield crests, the
shard TIPS (dimmed ~alpha 170-180 at rest) and the full halo (`set_glow("halo", 1.0)`).
`HeraldGeoRenderer.TelegraphGlowLayer` replaces the plain `withGlowmask()` layer: the
whole mask throbs while a volley telegraph winds up and gutters out across the death
collapse.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/herald.py
```

Writes albedo + glowmask in one run. The old vanilla-model generator
(`scripts/skin_gen/herald_v2.py`, 256×256) was deleted with the conversion — rerunning
it would have clobbered this canvas at the wrong size and hard-failed the glowmask pair.
Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size.
