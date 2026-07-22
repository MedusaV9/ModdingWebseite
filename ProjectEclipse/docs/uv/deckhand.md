# UV map — Deckhand (`assets/eclipse/textures/entity/deckhand.png`)

**Texture size:** 64×64. Model: `client/entity/DeckhandModel` (7 cubes, box-UV).
All face rects are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| robe | (24,16) | 8×8×6 | legless base sitting on the deck (root (0,24)) |
| torso | (0,0) | 8×10×4 | offset (0,−8), hunched xRot 0.15 |
| head | (24,0) | 8×8×8 | child of torso @ (0,−10) |
| hood | (0,27) | 8×8×8 **+0.25 inflate** | child of head, same UV shape one row down |
| arm_right | (0,14) | 3×10×3 | child of torso @ (−5.5,−9), base xRot −1.2 (rowing) |
| arm_left | (12,14) | 3×10×3 | child of torso @ (5.5,−9), same rowing phase |
| oar | (56,16) | 1×22×1 | child of arm_right @ (0,9), xRot 0.4 — shaft down to the water |

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| torso | (4,0)-(12,4) | (12,0)-(20,4) | (0,4)-(4,14) | (4,4)-(12,14) | (12,4)-(16,14) | (16,4)-(24,14) |
| head | (32,0)-(40,8) | (40,0)-(48,8) | (24,8)-(32,16) | (32,8)-(40,16) | (40,8)-(48,16) | (48,8)-(56,16) |
| arm_right | (3,14)-(6,17) | (6,14)-(9,17) | (0,17)-(3,27) | (3,17)-(6,27) | (6,17)-(9,27) | (9,17)-(12,27) |
| arm_left | (15,14)-(18,17) | (18,14)-(21,17) | (12,17)-(15,27) | (15,17)-(18,27) | (18,17)-(21,27) | (21,17)-(24,27) |
| robe | (30,16)-(38,22) | (38,16)-(46,22) | (24,22)-(30,30) | (30,22)-(38,30) | (38,22)-(44,30) | (44,22)-(52,30) |
| oar | (57,16)-(58,17) | (58,16)-(59,17) | (56,17)-(57,39) | (57,17)-(58,39) | (58,17)-(59,39) | (59,17)-(60,39) |
| hood | (8,27)-(16,35) | (16,27)-(24,35) | (0,35)-(8,43) | (8,35)-(16,43) | (16,35)-(24,43) | (24,35)-(32,43) |

**Art brief:** drowned ferryman crew — murky waterlogged gray-greens (robe `#3A4038`,
torso `#2E3430`, arms `#343A32`, hood `#262B24`), the head is pure shadow under the hood
(placeholder `#141612`) with two faint pale eyes on the head north face at (38,11) and
(41,11); oar shaft is dark wood (`#5A452E`). Mute ambience mob — keep it desaturated so it
reads as part of the ghost ship. No emissive layer.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
