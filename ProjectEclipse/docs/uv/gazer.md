# UV map — Gazer (`assets/eclipse/textures/entity/gazer.png` + `gazer_glowmask.png`)

**Texture size:** 64×64, BOTH PNGs (GeckoLib `AutoGlowingTexture` enforces matching
canvases). Model: `geo/entity/gazer.geo.json` (MC1 GeckoLib conversion, 19 bones /
15 cubes, box-UV), rendered by `client/entity/gazer/GazerGeoRenderer` (head tracking,
glowmask, upright death). All rects below are `(x0,y0)-(x1,y1)` pixel bounds
(exclusive right/bottom edge, full box-UV strip).

| Cube (bone) | UV origin | Box W×H×D | Strip rect | Pivot / role |
|---|---|---|---|---|
| cloak | (0,0) | 10×18×6 | (0,0)-(32,24) | pivot (0,24,0); body y6..24, hem floats 6 px up |
| hood | (32,0) | 8×8×8 | (32,0)-(64,16) | pivot (0,18,0) under `head` (tracking bone, cube-less) |
| glow_face | (32,16) | 6×6×1 | (32,16)-(46,23) | the pale mask, front at z −4.25; EMISSIVE north face |
| glow_iris_left/right | (46,16) shared | 1×2×1 | (46,16)-(50,19) | pips at (±1.5, 22, −4.5..−3.5) under `iris_carrier`; EMISSIVE whole |
| tatter_left_1 / _2 | (0,24) / (0,28) | 3×3×1 | (0,24)-(8,28) / (0,28)-(8,32) | 2-segment hem chain @ (−3, 6/3, 1) |
| tatter_right_1 / _2 | (10,24) / (10,28) | 3×3×1 | (10,24)-(18,28) / (10,28)-(18,32) | mirror chain @ (3, 6/3, 1) |
| tatter_back_1 / _2 | (20,24) / (20,28) | 3×3×1 | (20,24)-(28,28) / (20,28)-(28,32) | rear chain @ (0, 6/3, 2) |
| brow | (32,24) | 8×1×1 | (32,24)-(50,26) | glare ledge over the mask @ (0,25,−4), 0.75 px proud |
| lid_top | (44,32) | 7×3×1 | (44,32)-(60,36) | pivot at TOP edge (0,25.2,−4.25); anim y-scale 0.1 rest → 1 blink |
| lid_bottom | (44,36) | 7×3×1 | (44,36)-(60,40) | pivot at BOTTOM edge (0,18.8,−4.25); counter-lid |
| mantle | (0,40) | 12×3×8 | (0,40)-(40,51) | shoulder slab @ (0,23,0) |

**Art brief:** ragged void-cloth watcher — deep desaturated indigo cloak `#262040`
(vertical fold weave, center seam, shadowed hem, near-black underside), near-black hood
`#1B1730` whose front opening is a pure void ring `#0A0714` around the mask, dusk-violet
mantle `#383159` with a lit top edge, kelp-ragged tatters `#211C38` (lower segments
darker + more torn), brow ledge `#141024` (darkest cloth — a shadow shelf). The **face
is the mob's only light**: bone-pale mask `#EFE6CC`→`#C9BC9E` (radial dim toward the
rim), two 1×2 hollow void eye slits `#0E0A1C` at face-local columns 1 and 4, rows 2..3,
a chipped top-right corner and a faint etched chin mark. Iris pips `#E8D6FF`→`#A87CF0`
with rare white glints. Lids are hood cloth `#241E3D` with a darkened closing edge
`#0F0B1E` (bottom row of lid_top, top row of lid_bottom) so a blink reads as a hard
shutter line.

**Emissive regions (glowmask — the Gazer's first):** `glow_iris_*` auto-copied whole
(bone prefix); `glow_face` uses a custom same-salt glow painter — ONLY the north mask
face burns (alpha 215 dimming to ~125 at the rim, chip at 60), slits and the plate's
edge faces stay dark. Lids/hood/cloak carry no glow and OCCLUDE the mask glow in z when
the lids scale shut (they sit proud at z −4.75).

**Generator:** `python3 scripts/geckolib_gen/mobs/gazer.py` (deterministic, seed
`0x6A2E77CD`; one run writes albedo AND glowmask — reruns byte-identical). The old
in-place face-rig painter `scripts/skin_gen/gazer_v2.py` was deleted with the MC1
conversion (it targeted the old code-model UV layout).
