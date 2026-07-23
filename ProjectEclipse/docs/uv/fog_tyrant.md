# UV map — Fog Tyrant (`assets/eclipse/textures/entity/fog_tyrant.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces
matching canvases; 128² is the frozen §6 canvas for the boss tier). Model:
`assets/eclipse/geo/entity/fog_tyrant.geo.json` (GeckoLib, 23 bones / 29 cubes,
4.2-block regal storm wraith — layered tattered storm-robe, caged chest core, twin
lance arms, hooded head under a floating shard-crown; hovers, never quite touches the
ground). As with all GeckoLib mobs, the geo file **is** the UV source of truth — the
painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes every face rect
itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| robe | skirt / mid | 22×12×16 / 18×12×14 | box-UV (0,0) / (0,28) | storm slate, electric seams |
| robe_tatter_front | tatter | 16×6×1 | box-UV (34,113) | ragged alpha-cut hem (kelp material) |
| robe_tatter_back | tatter | 16×6×1 | box-UV (34,120) | mirrored rag |
| robe_tatter_left / _right | tatters | 1×6×14 | box-UV (48,93) / (78,93) | side rags |
| torso | top slab / sides ×2 / spine | 16×5×12 / 5×10×12 ×2 / 6×10×6 | box-UV (0,54) / (0,71)+(34,71) / (68,71) | chest CAVITY between the side columns; seams |
| glow_core | storm core | 5×5×5 | box-UV (76,17) | fully emissive `#E8FBFF`; gutters on death |
| chest_cage | ribs ×2 | 6×1×1 each | box-UV (108,16) / (108,18) | dark metal bars caging the core |
| cloak_back | outer cloak | 18×24×1 | box-UV (64,28) | dark→fog-pale gradient, ragged hem |
| cloak_mid | inner cloak | 14×16×1 | box-UV (96,59) | second layer, offset sway |
| shoulder_left / _right | pauldrons | 7×5×10 | box-UV (92,76) / (0,113) | slate + seams |
| arm_left / arm_right | arms | 6×14×6 | box-UV (0,93) / (24,93) | near-black, seamless (reads as robe sleeve) |
| lance_left | guard + blade | 5×3×5 / 3×20×3 | box-UV (96,20) / (102,28) | wrapped guard; blade centerline burns electric |
| lance_right | guard + blade | 5×3×5 / 3×20×3 | box-UV (102,51) / (114,28) | mirrored |
| head | hooded skull | 8×9×8 | box-UV (76,0) | head-tracked; 2 hard electric eyes north face |
| crown | ring | 10×2×10 | box-UV (56,54) | tarnished storm-silver, lit upper rim |
| glow_crown_f / _b / _l / _r | shard-spikes | 3×6×1 / 3×5×1 / 1×5×3 / 1×5×3 | box-UV (108,0) / (116,0) / (108,7) / (116,7) | floating crown, fully emissive |

**Art brief (design sheet §2.4 `fog_tyrant` + W11 brief):** the fog-storm apex boss — a
crowned storm monarch in deep storm blue-black. Robe base `#232830` (arms `#1C2027`,
tatters `#2A313A`), torso/shoulders wet slate `#2F343C`, all broken by **electric
seams** (wandering hairline vertical cracks `#9FE8FF` → `#CFF3FF`, ~11-texel spacing
with breaks), rain-streak darkening and sparse pale mineral flecks. Cloak layers run
`#39414B` → fog-bank pale `#8496AB` toward the ragged hems (fog gathering at the
trailing edge). Head is a near-black cowl `#20242B` with a shadowed face pit and two
hard `#CFF3FF` eyes. Lances: slate metal `#5E6B7A` with an electric centerline that
brightens toward the point-down tip; cloth-wrapped guards. Crown ring `#4A525E`
storm-silver; the four floating shard-spikes and the caged chest core burn
`#E8FBFF`/`#9FE8FF` flame-style.

**Emissive (glowmask):** the crown shards + chest core (`glow_` bones, auto-included) +
both eyes + the lance centerlines + every electric seam + a flickering crown-ring rim.
The seams/edges reuse the exact albedo pixel test (same salt), so mask and albedo can
never drift apart. This is the fight's light language: seams flare with phase pushes,
the core gutters through the 70 t death, and the crown is the last thing to go dark.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/fog_tyrant.py
```

Final AI art may replace either PNG byte-for-byte at the same path/canvas size; keep
the seam pixels in the glowmask aligned with the albedo cracks (and the emissive
pixels bright in the albedo too — Iris rule) or the storm-light read dies.
