# UV map — Sunmote (`assets/eclipse/textures/entity/sunmote.png`)

**Texture size:** 32×32. Model: `client/entity/SunmoteModel` (2 cubes, box-UV).
All face rects are `(x0,y0)-(x1,y1)` pixel bounds (exclusive right/bottom edge).

| Cube | UV origin | Box W×H×D | Pivot / pose |
|---|---|---|---|
| core | (0,0) | 2×2×2 | centered on root (0,21) |
| halo | (0,4) | 4×1×4 | flat plate mounted at 45°, spins `yRot += age*0.1` |

Per-face pixel rects (top, bottom, east/right, north/front, west/left, south/back):

| Cube | top | bottom | east | north | west | south |
|---|---|---|---|---|---|---|
| core | (2,0)-(4,2) | (4,0)-(6,2) | (0,2)-(2,4) | (2,2)-(4,4) | (4,2)-(6,4) | (6,2)-(8,4) |
| halo | (4,4)-(8,8) | (8,4)-(12,8) | (0,8)-(4,9) | (4,8)-(8,9) | (8,8)-(12,9) | (12,8)-(16,9) |

**Art brief:** a captured spark of daylight — white-gold core (placeholder `#FFF2C0`) and
amber halo (`#FFC24A`). The WHOLE model renders fullbright AND gets an additive
`RenderType.eyes` glow pass over the same texture (`SunmoteRenderer.GlowLayer`), so bright
warm values everywhere are correct; avoid dark pixels (they go muddy under the additive
pass). Rest of the 32×32 canvas stays transparent.

**Generator:** `java scripts/placeholder_gen/EntitySkinPlaceholder.java`.
