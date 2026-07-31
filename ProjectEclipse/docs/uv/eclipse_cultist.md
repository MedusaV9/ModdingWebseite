# UV map — Eclipse Cultist (`assets/eclipse/textures/entity/eclipse_cultist.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/eclipse_cultist.geo.json` (GeckoLib, 20 bones /
17 cubes — 1.9-block hunched robed caster, hitbox 0.6×1.9). The geo file **is** the UV
source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes
every face rect itself, so only the layout is frozen here (verified overlap-free: 1823 of
4096 texels used, 0 collisions, nothing off-canvas):

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| robe_lower | waist link | 7×4×5 | box-UV (0,40) | top link of the four-piece robe chain; plain weave + overlap crease |
| robe_mid | mid link | 8×3×6 | box-UV (24,40) | steps out +0.5 px per side over `robe_lower` |
| robe_hem | hem link | 9×3×7 | box-UV (0,49) | floor-length; **dashed sigil-trim band** on side row fh−2, mud-dark bottom row |
| robe_train | back drape | 6×8×1 | box-UV (34,49) | hangs off `robe_lower` at z 3.2–4.2; dashed trim column down the spine |
| torso | chest | 6×10×4 | box-UV (26,0) | dashed trim column down the north-face center (rank stole) |
| head | face block | 5×5×5 | box-UV (0,16) | head-tracked; void shadow with violet eyes at face (1,2) + (3,2) |
| hood | shell | 5×5×5 +0.5 inflate | per-face: E (20,16), W (25,16), S (30,16), U (35,16), D (40,16) — **no north face** | open hood front; the face sits recessed inside |
| hood | peak | 3×2×3 | box-UV (46,0) | pitched −12°, slumps backward |
| glow_hood | ember ring | 5.5×5.5×0 | per-face: N (52,5) at uv_size 6×6 | flat quad 0.1 px in front of the hood mouth; **only the 1 px rim is painted**, middle transparent |
| arm_right | sleeve | 3×9×3 | box-UV (0,28) | wide sleeve; knife + cuff children |
| cuff_right | bell cuff | 4×5×4 | box-UV (48,49) | flares open in `cast`; trim dashes on the rim row |
| knife | ritual knife | 1×4×1 | box-UV (12,28) | grip on top row, honed steel below |
| arm_left | sleeve | 3×9×3 | box-UV (16,28) | mirror layout, separate UV |
| cuff_left | bell cuff | 4×5×4 | box-UV (28,31) | mirror of `cuff_right` |
| glow_rune_a | page quad | 0×3×2 | per-face: E (28,28), W (31,28) | flat X-plane quad |
| glow_rune_b | page quad | 2×3×0 | per-face: N (34,28), S (37,28) | flat Z-plane quad |
| glow_rune_c | page quad | 2×3×0 | per-face: N (40,28), S (43,28) | flat Z-plane quad |

`runes` (cube-less, pivot 4.5,12,0) is the orbit driver — anims spin only its Y rotation
so the three pages circle the left hip. `neck` (cube-less, pivot 0,20,0) sits between
`torso` and `head` and carries **all** head pitch/yaw: GeckoLib's automatic head tracking
does an absolute `setRotX`/`setRotY` on the bone literally named `head` **after** the
animation ticks, so anything authored on `head.rotation.x/y` is discarded (only `.z`
survives). `body` (pivot 0,10,0) is the locomotion root.

**Art brief (design sheet §2.3 "eclipse_cultist"):** the same charcoal robe family as
eclipsed players — cloth `#26232E` (back drape `#1F1C27`, sleeves `#2C2836`, hood
`#1B1922`) in a vertical weave, with `#B98CFF` sigil trim dashes on the hem, the train
spine, the cuff rims and the chest. Under the hood only shadow `#0E0C14` and two violet
ember eyes (`#B98CFF`, core `#E7D6FF`). Ritual knife: wrapped grip `#4A4152`, steel
`#C8CCD8` with a bright honed-edge column. Rune pages are flame-material violet
(`#EFE3FF`→`#B98CFF`, shadeless). The hood ring ramps `#6D4AA8` at the brow to
`#B98CFF`+`#EFE3FF` where the coals pool at the chin.

**Emissive (glowmask):** the three `glow_rune_*` quads (auto-included via the `glow_`
prefix), the `glow_hood` ember ring (custom rim painter, alpha 60→210 bottom-weighted),
the two eye pixels (custom glow painter, alpha 255/225 — deliberately above the ring so
the eyes stay the focal point), the hem trim dashes (alpha 130), the train spine dashes
(alpha 100) and the cuff rims (alpha 120). `EclipseCultistRenderer` installs the layer via
`withGlowmask()`.

**Structural notes for a repaint (these are geometry, not paint):**

- The hood's **north face is deliberately missing** — that is what makes the cowl read as
  open. Do not "fix" it.
- `glow_hood`'s interior texels must stay at alpha 0. The renderer uses the cutout default
  (`entityCutoutNoCull`, alpha-**tested**), so a partly-transparent middle would render
  fully opaque and curtain over the eyes.
- The ring quad is inset to 5.5 px inside a 6 px hood mouth on purpose: at 6 px its outer
  edge is coplanar with the hood's own side walls and z-fights into a bright sliver along
  the silhouette at grazing angles.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/eclipse_cultist.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size.
