# UV map — Deckhand (`assets/eclipse/textures/entity/deckhand.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases; the deckhand's glowmask is intentionally **fully transparent**, see below).
Model: `assets/eclipse/geo/entity/deckhand.geo.json` (GeckoLib, 13 bones / 11 cubes —
P6-W2 remodel, replaces the retired hand-coded `client/entity/DeckhandModel`). As with
all GeckoLib mobs, the geo file **is** the UV source of truth — the painter
(`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect itself, so
only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| robe | legless base | 8×8×6 | box-UV (24,16) | sits on the deck, v1 silhouette kept |
| torso | hunch | 8×10×4 | box-UV (0,0) | rest pose pitched −8.5° |
| head | shadow void | 8×8×8 | box-UV (24,0) | head-tracked; 2 pale eyes on north face |
| hood | shell | 8×8×8 +0.25 inflate | box-UV (0,27) | child of head |
| arm_right / arm_left | sleeves | 3×10×3 | box-UV (0,14) / (12,14) | pivots at the shoulders (±5.5, 17) |
| tatter_right | rope tatter | 2×5×0 | per-face: N (48,30), S (48,36) | belt-line flutter card |
| tatter_left | rope tatter | 2×4×0 | per-face: N (0,56), S (3,56) | belt-line flutter card |
| oar → oar_loom | inboard grip | 2×2×10 | per-face: N (56,0), S (59,0), E (0,44), W (0,47), U (56,4), D (59,4) | both hands hold this |
| oar → oar_shaft | outboard shaft | 2×2×30 | per-face: N (62,0), S (62,3), E (0,50), W (0,53), U (52,16), D (55,16) | runs outboard/down |
| oar → oar_blade | blade | 1×6×12 | per-face: N (62,6), S (63,6), E (32,30), W (32,36), U (44,30), D (45,30) | feathers on the return |

The `oar` group (pivot 0,11,−10, rest pitch −30°) is the bug-4c/4d fix: the oar is part
of the deckhand's own skeleton — no held item, no block displays. `oar_blade` pivots at
the shaft end (0,11,−40) so the roll channel feathers the blade.

**Art brief (v1 brief carried over + design sheet §2.3 "deckhand v2"):** drowned
ferryman crew — murky waterlogged gray-greens (robe `#3A4038`, torso `#2E3430`, arms
`#343A32`, hood `#262B24`), the head is pure shadow (`#141612`) with two faint pale eyes
(`#7A8578`) on the head north face; oar is dark waterlogged wood (`#5A452E`) with a
kelp-slimed trailing edge on the blade (`#22301F`); rope tatters `#4A4232`. Mute
ambience mob — keep it desaturated so it reads as part of the ghost ship.

**Emissive (glowmask):** NONE — the design sheet is explicit. The painter still writes
`deckhand_glowmask.png` (fully transparent, 0 px) for pipeline uniformity, but
`DeckhandRenderer` installs no `AutoGlowingGeoLayer`, so it is never sampled.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/deckhand.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; if
art ever adds emissive pixels, also install the glow layer in `DeckhandRenderer`.
