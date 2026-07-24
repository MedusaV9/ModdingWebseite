# UV map — Drift Lantern (`assets/eclipse/textures/entity/drift_lantern.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/drift_lantern.geo.json` (GeckoLib, 8 bones /
9 cubes, box-UV). Unlike the hand-coded models, the geo file **is** the UV source of
truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes every
face rect itself, so only the box-UV origins are frozen here:

| Bone | Cube | Box W×H×D | UV origin | Strip (x0,y0)-(x1,y1) |
|---|---|---|---|---|
| body | bottom plate | 4×1×4 | (0,21) | (0,21)-(16,26) |
| body | top plate | 5×1×5 | (0,14) | (0,14)-(20,20) |
| body | hanger loop | 2×1×2 | (24,0) | (24,0)-(32,3) |
| glow_flame | soul flame | 3×4×3 | (24,4) | (24,4)-(36,11) |
| cage | glass cage | 6×6×6 | (0,0) | (0,0)-(24,12) |
| tendril_a..d | kelp chain | 2×8×1 | (40,0) / (48,0) / (40,10) / (48,10) | 6×9 each |

**Art brief (design sheet §2.3, plans_v3/P6):** a soul-lantern "jellyfish" — brushed-iron
plates and hanger (`#3B3F46`), glass cage at **40% alpha** panes (`#9FB8C4`, rim slightly
more opaque; the renderer uses `entityTranslucent`, so partial alpha really blends), soul
flame `#7FE3D2` with a near-white core (`#E9FFF9`), waterlogged kelp tendrils `#2E4A44`
with ragged alpha-cutout hems and chain-node bands.

**Emissive (glowmask):** the flame cube at full painted brightness, PLUS the
shine-through: a center-weighted soul-tinted blob on every cage face except the bottom
(max alpha ≈ 230 at the pane center) and a faint speckled rim (alpha 60). The
shine-through lives on the CAGE's pixels because the glow layer's re-render of the inner
flame bone is depth-rejected underneath translucent glass — see the "inner glow through
translucent shells" rule in `docs/plans_v3/handoff/P6_geckolib_conventions.md`. Iron and
tendrils stay fully transparent in the glowmask.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/drift_lantern.py
```

Final AI art may replace both PNGs byte-for-byte at the same paths/canvas sizes; keep the
glowmask aligned with whatever pixels should burn at night.
