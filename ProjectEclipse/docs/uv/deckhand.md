# UV map — Deckhand (`assets/eclipse/textures/entity/deckhand.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/deckhand.geo.json` (GeckoLib, **25 bones /
27 cubes**, 2590 of 4096 texels claimed, no cross-bone UV overlap). As with all GeckoLib
mobs the geo file **is** the UV source of truth — the painter
(`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect itself, so
only the layout is frozen here.

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| robe | legless base | 8×8×6 | box-UV (24,16) | sits on the deck, v1 silhouette kept |
| robe → belt | rope band | 8.5×1.5×6.5 | per-face: U (16,56), D (25,63)↕, E (10,62), N (16,62), W (25,62), S (31,62) | MOB-AMBIENT v2 |
| belt → lantern | iron cap | 2.5×0.6×2.5 | per-face: U (32,43), D (35,46)↕, E (30,45), N (32,45), W (35,45), S (37,45) | dead drift-lantern |
| belt → lantern | glass body | 2×2.4×2 | per-face: U (46,43), D (48,45)↕, E (44,45), N (46,45), W (48,45), S (50,45) | DEAD soul-glass — the crew's lights went out |
| torso | hunch | 8×10×4 | box-UV (0,0) | rest pose pitched −8.5° |
| head | shadow void | 8×8×8 | box-UV (24,0) | head-tracked; north face is the open cowl void |
| head → `glow_face_0..3` | face card | 6×4×0 | per-face N: (0,27) (6,27) (12,27) (18,27), each 6×4 | **emissive**, one per bench |
| head → `glow_face_4..7` | face card | 6×4×0 | per-face N: (0,31) (6,31) (12,31) (18,31), each 6×4 | **emissive**, one per bench |
| head → `glow_face_wrath` | risen brand | 6×4×0 | per-face N (32,49) 6×4 | **emissive**, layered 0.2 px in front |
| head → hood | crown | 8.5×2.5×8.5 | per-face: U/D (0,35) 8×8, N/S/E/W (8,41) 8×3 | open cowl, 4 cubes |
| head → hood | back panel | 8.5×6×1.25 | per-face: N/S (8,35) 8×6, E/W (24,35) 2×6, U/D (16,41) 8×2 | |
| head → hood | side panel ×2 | 1.25×6×7.25 | per-face: E/W (16,35) 8×6, N/S (26,35) 2×6, U/D (28,35) 2×8 | |
| hood → hood_point | drooping tip | 3×3.5×3 | per-face: U (55,46), D (58,49)↕, E (52,49), N (61,49), W (58,49), S (55,49) | rest pitch −22° |
| arm_right / arm_left | sleeves | 3×10×3 | box-UV (0,14) / (12,14) | pivots at the shoulders (±5.5, 17) |
| tatter_right | rope tatter | 2×5×0 | per-face: N (48,30), S (48,36) | belt-line flutter card |
| tatter_left | rope tatter | 2×4×0 | per-face: N (0,56), S (3,56) | belt-line flutter card |
| oar → oar_loom | inboard grip | 2×2×10 | per-face: N (56,0), S (59,0), E (0,44), W (0,47), U (56,4), D (59,4) | both hands hold this |
| oar → oar_shaft | outboard shaft | 2×2×30 | per-face: N (62,0), S (62,3), E (0,50), W (0,53), U (52,16), D (55,16) | runs outboard/down |
| oar → oar_blade | blade | 1×6×12 | per-face: N (62,6), S (63,6), E (32,30), W (32,36), U (44,30), D (45,30) | feathers on the return |

(↕ = Blockbench-flipped `uv_size`, normalised by the painter/validator.)

The `oar` group (pivot 0,11,−10, rest pitch −30°) is the bug-4c/4d fix: the oar is part
of the deckhand's own skeleton — no held item, no block displays. `oar_blade` pivots at
the shaft end (0,11,−40) so the roll channel feathers the blade; the blade CUBE reaches
z = −52 (3.25 blocks), which is what `DeckhandEntity.getBoundingBoxForCulling` has to
cover.

**Art brief (v1 brief carried over + design sheet §2.3 "deckhand v2"):** drowned
ferryman crew — murky waterlogged gray-greens (robe `#3A4038`, torso `#2E3430`, arms
`#343A32`, hood `#262B24`), the head is pure shadow (`#141612`); oar is dark waterlogged
wood (`#5A452E`) with a kelp-slimed trailing edge on the blade (`#22301F`); rope tatters
and belt `#4A4232`; lantern iron `#3B3F46` with dead soul-glass `#57706B`. Mute ambience
mob — keep it desaturated so it reads as part of the ghost ship.

**Emissive (glowmask): the face, and only the face** (F-098/MB1 — this replaces the v1
brief's "NONE"). The hood is an open cowl, so the shadow void behind it is visible, and
each rower burns its own soul-light in it:

* `glow_face_0..7` — eight 6×4 cards stacked on the same spot in the cowl (all at model
  z −4.25, y 18.5–22.5). `DeckhandRenderer` shows **exactly one**, picked from the synced
  bench index, so the eight crew members are individually recognisable. The patterns
  differ in socket count, height and symmetry, not only in hue, so they read apart both
  up close and as lit-texel mass across the deck.
* `glow_face_wrath` — one more card 0.2 px in front (z −4.45), lit only while
  `isHostile()`. Its top row is deliberately empty so the rower's OWN sockets still show
  through: the crew turns hostile, it does not turn identical.
* Palette stays inside the FX crew colours (`tools/photon/backlog_fx.py`: SOUL_BLUE
  `#66CCFF`, flare core SAC_HOT `#F6EFFF`) so the cards match the Photon soul-flame.
* Card top y = 22.5 is 0.47–1.11 px below the lowest reach of the hood brim across the
  whole animation set (tightest: `death` at 22.97, `attack` at 23.05) — at the original
  y 23.5 the brim clipped the inboard half of every socket and the eyes rendered as
  L-shaped hooks. **Any new/edited clip must keep the brim above y 22.75 in head-local
  space over the eye columns (|x| ≤ 3).**
* Total glowmask coverage: 41 px (33 across the eight bench cards, 8 for the brand).
  `DeckhandRenderer` installs `withGlowmask()` (`AutoGlowingGeoLayer`).

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/deckhand.py
```

Final AI art may replace both PNGs byte-for-byte at the same paths/canvas size; keep the
nine face-card rects emissive-only, or the `AutoGlowingGeoLayer` will burn whatever else
lands in them fullbright.
