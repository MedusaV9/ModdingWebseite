# UV map — The Herald of the Eclipse (`assets/eclipse/textures/entity/herald.png`)

**Texture size:** 128×128. Model: `client/entity/HeraldModel` (26 cubes, box-UV).
All face rects are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| core | (0,0) | 12×12×12 | offset (0,−40) under root (0,24) — floats at spec pivot (0,40,0); bobs `sin(age*0.06)*1.2px`, yaw/pitch-tracks the target |
| inner_eye | (48,0) | 6×6×6 | child of core @ ZERO, box z −7..−1 (front face protrudes 1px); **emissive** — re-rendered fullbright by `HeraldRenderer.EmissiveLayer` (`RenderType.eyes`) |
| shard0..7 | (i·8,32) | 2×6×2 | children of the `ring` bone (no cube, pivot (0,−40)); each at `(cos(i·45°)*14, 0, sin(i·45°)*14)` with `yRot = −i·45°` (local +X radial); ring spins `yRot = age*0.05`, shard bobs `sin(age*0.1 + i·π/4)*2px`; P3 tilt-out `zRot → 0.6`; **glow emissive during volley telegraphs**; detached shards hidden |
| tentacle{t}_seg{k} | ((t·4+k)·8,44) | 2×6×2 | 4 chains × 4 chained segments off the core's underside corners (±3.5, 6, ±3.5), each child @ (0,6,0); whip-lag `xRot = sin(age*0.09 + k·0.6)*0.25` |

All spec anims run off the entity's smooth animation clock (`HeraldEntity.animAge`),
which advances ×2 in P3 with an eased ramp so nothing snaps at the phase break.

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| core | (12,0)-(24,12) | (24,0)-(36,12) | (0,12)-(12,24) | (12,12)-(24,24) | (24,12)-(36,24) | (36,12)-(48,24) |
| inner_eye | (54,0)-(60,6) | (60,0)-(66,6) | (48,6)-(54,12) | (54,6)-(60,12) | (60,6)-(66,12) | (66,6)-(72,12) |
| shard i (u = i·8) | (u+2,32)-(u+4,34) | (u+4,32)-(u+6,34) | (u,34)-(u+2,40) | (u+2,34)-(u+4,40) | (u+4,34)-(u+6,40) | (u+6,34)-(u+8,40) |
| tentacle seg s = t·4+k (u = s·8) | (u+2,44)-(u+4,46) | (u+4,44)-(u+6,46) | (u,46)-(u+2,52) | (u+2,46)-(u+4,52) | (u+4,46)-(u+6,52) | (u+6,46)-(u+8,52) |

**Art brief:** a broken godhead — near-black violet glass core (placeholder `#181224`) laced
with gold crack veins (`#E8A83A`) on the north face, a blazing gold inner eye (`#FFD86A`,
2×2 void pupil `#100A18` at (56,8)) that the emissive pass keeps burning at any light,
pale-violet corona shards (`#C88AFF`) that flare during telegraphs, and dark umbral
tentacle chains (`#241C36`). Contrast lives in the albedo; the eye + telegraphing shards
additionally get the fullbright eyes pass.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
