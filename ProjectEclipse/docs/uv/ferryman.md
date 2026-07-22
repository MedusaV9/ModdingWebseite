# UV map — The Ferryman (`assets/eclipse/textures/entity/ferryman.png`)

**Texture size:** 128×128. Model: `client/entity/FerrymanModel` (17 cubes, box-UV), ~3.5 blocks tall.
All face rects are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| body | (0,0) | 10×26×8 | offset (0,−27) under root (0,24) — the robe floats with its hem ~14px off the deck; bob `sin(age*0.05)*1.5px`; P2 kneel drops it 11px and hunches `xRot=0.3` |
| strip0..3 | (32+i·8,36) | 2×6×1 | ragged hem strips at (±2.5, 13, ±3.5) under the robe; sway `xRot = sin(age*0.06 + i·1.3)*0.18` |
| head | (80,0) | 7×7×7 | skull on the robe top (0,−13); tracks target yaw/0.6×pitch |
| hood | (40,0) | 9×9×9 | child of head @ ZERO — **north (front) face is TRANSPARENT** in the skin so the skull shows inside the open cowl |
| eyes | (108,0) | 5×2×1 | brow slit, box z −4.25..−3.25 (pokes 0.25px past the hood front); **emissive** — re-rendered fullbright by `FerrymanRenderer.EmissiveLayer` (`RenderType.eyes`) |
| arm_right / arm_left | (0,36) / (16,36) | 3×20×3 | shoulders (∓6.5, −11); pose-blended between rowing, telegraph raise, kneel fold and P3 plant |
| oar | (64,36) | 2×36×2 | two-handed sweep oar, pivot mid-shaft at chest (0,−6,−7); rowing idle `xRot = −0.7 + sin(age*0.08)*0.35`; telegraph raises overhead (`raiseAmount`→`xRot −2.5`); P3 plants it vertical beside him (`plantAmount`→ offset (9,9), `xRot 0`) |
| blade | (76,36) | 1×6×5 | child of oar @ ZERO at the shaft's lower end (y 12..18) |
| chain0..2 | (92+k·6,36) | 1×4×1 | 3-segment kinematic chain off the LEFT shoulder (6.5,−11,1.5), each child at (0,4,0); drag-lag swing `zRot = sin(age*0.07 − k·0.45)*0.3`, `xRot = sin(age*0.055 − k·0.4)*0.12` |
| lantern | (92,44) | 4×5×4 | hangs off chain2 at (0,4,0); housing joins the **emissive pass only while Lantern Gaze is active** (`FerrymanEntity.isGazing`) |
| flame | (110,36) | 2×2×2 | soul flame inside the lantern; **always emissive** |

All anims run off the entity's smooth animation clock (`FerrymanEntity.animAge`), which
advances ×1.4 in P3; the pose weights (`raiseAmount`/`kneelAmount`/`plantAmount`) are
client-side lerps of the synced telegraph/kneel/plant flags, so nothing snaps.

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| body | (8,0)-(18,8) | (18,0)-(28,8) | (0,8)-(8,34) | (8,8)-(18,34) | (18,8)-(26,34) | (26,8)-(36,34) |
| hood | (49,0)-(58,9) | (58,0)-(67,9) | (40,9)-(49,18) | (49,9)-(58,18) **transparent** | (58,9)-(67,18) | (67,9)-(76,18) |
| head | (87,0)-(94,7) | (94,0)-(101,7) | (80,7)-(87,14) | (87,7)-(94,14) | (94,7)-(101,14) | (101,7)-(108,14) |
| eyes | (109,0)-(114,1) | (114,0)-(119,1) | (108,1)-(109,3) | (109,1)-(114,3) | (114,1)-(115,3) | (115,1)-(120,3) |
| arm_right | (3,36)-(6,39) | (6,36)-(9,39) | (0,39)-(3,59) | (3,39)-(6,59) | (6,39)-(9,59) | (9,39)-(12,59) |
| arm_left | (19,36)-(22,39) | (22,36)-(25,39) | (16,39)-(19,59) | (19,39)-(22,59) | (22,39)-(25,59) | (25,39)-(28,59) |
| strip i (u = 32+i·8) | (u+1,36)-(u+3,37) | (u+3,36)-(u+5,37) | (u,37)-(u+1,43) | (u+1,37)-(u+3,43) | (u+3,37)-(u+4,43) | (u+4,37)-(u+6,43) |
| oar | (66,36)-(68,38) | (68,36)-(70,38) | (64,38)-(66,74) | (66,38)-(68,74) | (68,38)-(70,74) | (70,38)-(72,74) |
| blade | (81,36)-(82,41) | (82,36)-(83,41) | (76,41)-(81,47) | (81,41)-(82,47) | (82,41)-(87,47) | (87,41)-(88,47) |
| chain k (u = 92+k·6) | (u+1,36)-(u+2,37) | (u+2,36)-(u+3,37) | (u,37)-(u+1,41) | (u+1,37)-(u+2,41) | (u+2,37)-(u+3,41) | (u+3,37)-(u+4,41) |
| lantern | (96,44)-(100,48) | (100,44)-(104,48) | (92,48)-(96,53) | (96,48)-(100,53) | (100,48)-(104,53) | (104,48)-(108,53) |
| flame | (112,36)-(114,38) | (114,36)-(116,38) | (110,38)-(112,40) | (112,38)-(114,40) | (114,38)-(116,40) | (116,38)-(118,40) |

**Art brief:** the drowned pilot of the ghost ship — a drowned green-black wool robe
(placeholder `#202C28`) flecked with pale barnacle growth (`#5E7466`), ragged hem strips
(`#18221E`), a deep hood shell (`#141B18`) whose open front reveals an old-bone skull
(`#D8D2BE`, hollow sockets `#0E1410`), a soul-teal eye slit (`#8FF2DE`) burning in the brow,
a waterlogged sweep oar (`#4A3A28` shaft, `#3C2F20` blade), wet iron chain links (`#626670`)
and a lantern (`#3A3E46`) cradling a soul flame (`#A8F7E6`). The eye slit + flame get the
fullbright eyes pass at all times; the lantern housing flares fullbright while the Lantern
Gaze marks its prey.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
