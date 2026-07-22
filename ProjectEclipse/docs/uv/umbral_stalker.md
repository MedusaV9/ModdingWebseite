# UV map — Umbral Stalker (`assets/eclipse/textures/entity/umbral_stalker.png`)

**Texture size:** 64×64. Model: `client/entity/UmbralStalkerModel` (11 cubes, box-UV).
All face rects are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| body | (0,0) | 8×7×14 | offset (0,−10) under root (0,24), xRot 0.05 |
| head | (0,21) | 7×6×8 | offset (0,−12,−8); lowers 0.3 rad while hunting |
| jaw_left | (30,21) | 1×3×1 | child of head @ (−1.5,3,−7.5), hangs below the muzzle |
| jaw_right | (36,21) | 1×3×1 | child of head @ (1.5,3,−7.5) |
| leg_front_left | (0,35) | 3×8×3 | (−2.5,−8,−5); gait `cos(limbSwing*0.66+phase)*1.2*amt` |
| leg_front_right | (12,35) | 3×8×3 | (2.5,−8,−5) |
| leg_hind_left | (24,35) | 3×8×3 | (−2.5,−8,5) |
| leg_hind_right | (36,35) | 3×8×3 | (2.5,−8,5) |
| spine_front | (44,0) | 2×4×2 | child of body @ (0,−3.5,−4), zRot 0.2; pulse-breathes |
| spine_mid | (44,6) | 2×5×2 | child of body @ (0,−3.5,0), zRot −0.2 |
| spine_back | (44,13) | 2×4×2 | child of body @ (0,−3.5,4), zRot 0.2 |

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| body | (14,0)-(22,14) | (22,0)-(30,14) | (0,14)-(14,21) | (14,14)-(22,21) | (22,14)-(36,21) | (36,14)-(44,21) |
| head | (8,21)-(15,29) | (15,21)-(22,29) | (0,29)-(8,35) | (8,29)-(15,35) | (15,29)-(23,35) | (23,29)-(30,35) |
| jaw_left | (31,21)-(32,22) | (32,21)-(33,22) | (30,22)-(31,25) | (31,22)-(32,25) | (32,22)-(33,25) | (33,22)-(34,25) |
| jaw_right | (37,21)-(38,22) | (38,21)-(39,22) | (36,22)-(37,25) | (37,22)-(38,25) | (38,22)-(39,25) | (39,22)-(40,25) |
| leg (each, u ∈ {0,12,24,36}) | (u+3,35)-(u+6,38) | (u+6,35)-(u+9,38) | (u,38)-(u+3,46) | (u+3,38)-(u+6,46) | (u+6,38)-(u+9,46) | (u+9,38)-(u+12,46) |
| spine_front | (46,0)-(48,2) | (48,0)-(50,2) | (44,2)-(46,6) | (46,2)-(48,6) | (48,2)-(50,6) | (50,2)-(52,6) |
| spine_mid | (46,6)-(48,8) | (48,6)-(50,8) | (44,8)-(46,13) | (46,8)-(48,13) | (48,8)-(50,13) | (50,8)-(52,13) |
| spine_back | (46,13)-(48,15) | (48,13)-(50,15) | (44,15)-(46,19) | (46,15)-(48,19) | (48,15)-(50,19) | (50,15)-(52,19) |

**Art brief:** a wrong, shadow-slick quadruped — near-black violet body/head/legs
(placeholder `#221A2E`/`#2A2038`/`#1C1626`), pale bone jaw shards (`#D8D0C0`), and bright
violet crystal spine shards (`#8A5CFF`) that pulse in-game (animated lift + rock). Two tiny
violet eye pinpricks on the head north face at (10,30) and (12,30). No emissive layer —
keep contrast in the albedo.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
