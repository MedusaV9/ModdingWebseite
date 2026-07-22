# UV map — Gazer (`assets/eclipse/textures/entity/gazer.png`)

**Texture size:** 64×64. Model: `client/entity/GazerModel` (6 cubes, box-UV). All face
rects below are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| cloak | (0,0) | 10×18×6 | offset (0,−6) under root (0,24); hem floats 6 px above ground |
| hood | (32,0) | 8×8×8 | offset (0,−18); yaw-tracks the look target |
| face | (32,16) | 6×6×1 | child of hood, inset at z −4.25 |
| tatter_left | (0,24) | 3×8×1 | child of cloak @ (−2.5,0,1); sways ±0.15 rad |
| tatter_right | (10,24) | 3×8×1 | child of cloak @ (2.5,0,1); counter-phase sway |
| mantle | (0,40) | 12×3×8 | offset (0,−22); shoulder slab over the cloak |

Per-face pixel rects (box-UV order: top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| cloak | (6,0)-(16,6) | (16,0)-(26,6) | (0,6)-(6,24) | (6,6)-(16,24) | (16,6)-(22,24) | (22,6)-(32,24) |
| hood | (40,0)-(48,8) | (48,0)-(56,8) | (32,8)-(40,16) | (40,8)-(48,16) | (48,8)-(56,16) | (56,8)-(64,16) |
| face | (33,16)-(39,17) | (39,16)-(45,17) | (32,17)-(33,23) | (33,17)-(39,23) | (39,17)-(40,23) | (40,17)-(46,23) |
| tatter_left | (1,24)-(4,25) | (4,24)-(7,25) | (0,25)-(1,33) | (1,25)-(4,33) | (4,25)-(5,33) | (5,25)-(8,33) |
| tatter_right | (11,24)-(14,25) | (14,24)-(17,25) | (10,25)-(11,33) | (11,25)-(14,33) | (14,25)-(15,33) | (15,25)-(18,33) |
| mantle | (8,40)-(20,48) | (20,40)-(32,48) | (0,48)-(8,51) | (8,48)-(20,51) | (20,48)-(28,51) | (28,48)-(40,51) |

**Art brief:** ragged void-cloth watcher — deep desaturated indigo cloak/hood/mantle/tatters
(placeholder `#2A2440`/`#1E1A30`/`#3A3358`), the **face cube is EMISSIVE**: it is re-rendered
fullbright with `RenderType.eyes` by `GazerRenderer.FaceEyesLayer` using THIS SAME texture —
paint it as a pale glowing mask (placeholder `#F2E8C8`) with dark hollow eye slits at
(34,19)-(35,21) and (37,19)-(38,21) on the north face. Everything except the face should be
dark so the additive eyes pass stays clean.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
