# UV map — The Herald of the Eclipse (`assets/eclipse/textures/entity/herald.png`)

**UV space:** 128×128 (frozen — the LayerDefinition size). **Sheet:** 256×256, painted at
2× (vanilla normalizes UVs by the LayerDefinition size, so every texel gets a 2×2 pixel
budget with zero Java-side UV change). Model: `client/entity/HeraldModel` (33 cubes,
box-UV). All face rects are `(x0,y0)-(x1,y1)` TEXEL bounds (exclusive right/bottom edge;
multiply by 2 for sheet pixels).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| core | (0,0) | 12×12×12 | offset (0,−40) under root (0,24) — floats at spec pivot (0,40,0); bobs `sin(age*0.06)*1.2px`, yaw/pitch-tracks the target |
| inner_eye | (48,0) | 6×6×6 | child of core @ ZERO, box z −7..−1 (front face protrudes 1px); **emissive** — re-rendered fullbright by `HeraldRenderer.EmissiveLayer` (`RenderType.eyes`) |
| crown0..3 | (72+i·4,0) | 1×5×1 | crown spikes on the core's top corners (±4, −6, ±4), base lean 0.28 outward + slow shimmer; the phase-break ROAR flares them out/up and pulls them into the **emissive pass** (`HeraldEntity.roarAmount`) |
| halo (bone) + halo0..2 | (72+i·4,8) | 1×3×1 | 3 small floating shards on a counter-rotating inner ring bone at r=9px every 120°; the volley telegraph GATHERS them inward (summon gesture) and the recoil flings them back out; **glow emissive during telegraphs** |
| shard0..7 | (i·8,32) | 2×6×2 | children of the `ring` bone (no cube, pivot (0,−40)); each at `(cos(i·45°)*14, 0, sin(i·45°)*14)` with `yRot = −i·45°` (local +X radial); ring spins `yRot = age*0.05` + the accumulated telegraph spin-up / recoil snap (`ringSpinExtra`), shard bobs with a breathing amplitude; P3 tilt-out `zRot → 0.6`; **glow emissive during volley telegraphs**; detached shards hidden |
| tentacle{t}_seg{k} | ((t·4+k)·8,44) | 2×6×2 | 4 chains × 4 chained segments off the core's underside corners (±3.5, 6, ±3.5), each child @ (0,6,0); whip-lag `xRot = sin(age*0.09 + k·0.6 + t·1.57)*0.25` (per-chain phase) + cross-sway; telegraph curls them into the claw, the roar splays them; the death staggers their limp chain-by-chain |

All spec anims run off the entity's smooth animation clock (`HeraldEntity.animAge`),
which advances ×2 in P3 with an eased ramp so nothing snaps at the phase break.

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| core | (12,0)-(24,12) | (24,0)-(36,12) | (0,12)-(12,24) | (12,12)-(24,24) | (24,12)-(36,24) | (36,12)-(48,24) |
| inner_eye | (54,0)-(60,6) | (60,0)-(66,6) | (48,6)-(54,12) | (54,6)-(60,12) | (60,6)-(66,12) | (66,6)-(72,12) |
| crown i (u = 72+i·4) | (u+1,0)-(u+2,1) | (u+2,0)-(u+3,1) | (u,1)-(u+1,6) | (u+1,1)-(u+2,6) | (u+2,1)-(u+3,6) | (u+3,1)-(u+4,6) |
| halo i (u = 72+i·4) | (u+1,8)-(u+2,9) | (u+2,8)-(u+3,9) | (u,9)-(u+1,12) | (u+1,9)-(u+2,12) | (u+2,9)-(u+3,12) | (u+3,9)-(u+4,12) |
| shard i (u = i·8) | (u+2,32)-(u+4,34) | (u+4,32)-(u+6,34) | (u,34)-(u+2,40) | (u+2,34)-(u+4,40) | (u+4,34)-(u+6,40) | (u+6,34)-(u+8,40) |
| tentacle seg s = t·4+k (u = s·8) | (u+2,44)-(u+4,46) | (u+4,44)-(u+6,46) | (u,46)-(u+2,52) | (u+2,46)-(u+4,52) | (u+4,46)-(u+6,52) | (u+6,46)-(u+8,52) |

**Art brief:** a broken godhead — near-black violet glass core (`#181224`, faceted) laced
with gold crack veins (`#E8A83A` loud on the north face, dim hairlines spilling onto
east/west/up), a blazing gold inner eye (`#FFD86A`, 2×2 void pupil `#100A18` at (56,8))
that the emissive pass keeps burning at any light, pale-violet corona shards (`#C88AFF`)
that flare during telegraphs, gold-tipped obsidian crown spikes that flare through the
roar, hot-lavender halo shards, and dark umbral tentacle chains (`#241C36` with joint
banding + sucker dots). Contrast lives in the albedo; the eye, the telegraphing corona +
halo shards, and the roaring crown additionally get the fullbright eyes pass.

**Generator:** `python3 scripts/skin_gen/herald_v2.py` (deterministic 2× repaint; shared
painter `scripts/skin_gen/boss_paint.py` — keep its cube list in sync with
`HeraldModel.createBodyLayer`). The original 128×128 placeholder came from
`java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
