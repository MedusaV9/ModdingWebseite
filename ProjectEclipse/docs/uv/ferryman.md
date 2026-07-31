# UV map — The Ferryman (`assets/eclipse/textures/entity/ferryman.png` + `_glowmask.png`)

**Texture size:** 128×128 (both files — GeckoLib's `AutoGlowingTexture` enforces
matching canvases; 128² is the frozen boss-tier canvas, same as fog_tyrant/rift_warden —
the pre-conversion sheet already used a 128 UV space, so nothing rescales). Model:
`assets/eclipse/geo/entity/ferryman.geo.json` (GeckoLib — MA4 conversion of the old
hand-coded `FerrymanModel`; 32 bones / 30 cubes, ~3-block drowned pilot of the ghost
ship: floating barnacle-crusted robe with 4 hem segments + 3 two-segment cloak tatters,
open-cowl hood over a bone skull, a 3-segment lantern chain off the left shoulder ending
in the cube-less `lantern_hook` FX locator, the two-handed sweep oar on its own
`oar_grip→oar_shaft→oar_blade` bone chain, and four `glow_*` bones). The **boat** is NOT
part of the model — the "boat" is the block-built ghost ship (`limbo/GhostShipBuilder`);
the deck swell lives as Molang list/counter-roll on the `body` bone in
`idle_row`/`walk` instead. As with all GeckoLib mobs, the geo file **is** the UV source
of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses it and computes
every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | robe | 10×26×8 | box-UV (0,0) | drowned green-black weave; barnacle waterline crust on the bottom third |
| hem_front_left / _right | hem segments | 2×6×1 | box-UV (0,34) / (8,34) | robe hem plates, kneel/harvest flare keys |
| hem_back_left / _right | hem segments | 2×6×1 | box-UV (16,34) / (24,34) | mirrored rear pair |
| tatter_left / tatter_left_tip | cloak tatter chain | 2×5×1 / 2×4×1 | box-UV (0,42) / (0,49) | 2-segment drag chain, ragged kelp alpha hem on the tip |
| tatter_right / tatter_right_tip | cloak tatter chain | 2×5×1 / 2×4×1 | box-UV (8,42) / (8,49) | mirrored flank |
| tatter_back / tatter_back_tip | cloak tatter chain | 2×5×1 / 2×4×1 | box-UV (16,42) / (16,49) | stern tatter |
| glow_robe | lantern-sheen plate | 1×10×4 | box-UV (100,22) | +x (lantern-side) flank wash — **emissive (soft, alpha 120)**; hidden with the flame on death |
| head | skull | 7×7×7 | box-UV (72,0) | head-tracked (`turnsHead=true`); bone north face with hollow sockets + nasal slit, socket embers faintly emissive |
| hood | cowl shell | 9×9×9 | box-UV (36,0) | **north face TRANSPARENT** (ragged 1px rim only) — the open cowl; skull floats inside |
| glow_eyes | eye slit | 5×2×1 | box-UV (100,0) | soul-teal brow band, hotter mid — **emissive** |
| arm_right / arm_left | sleeves | 3×20×3 | box-UV (36,18) / (48,18) | robe weave, no crust |
| chain_1 / chain_2 / chain_3 | chain segments | 1×4×1 | box-UV (88,18) / (92,18) / (96,18) | wet iron, link-band darkening + rust blooms |
| link_1 / link_2 / link_3 | crosspieces | 2×2×1 | box-UV (80,24) / (86,24) / (92,24) | alternating 0°/90° yaw so the chain reads interlocked |
| lantern_hook | — (cube-less) | — | — | **FX locator** at the chain terminus — `ferry_lantern_swarm` anchor (A4) |
| lantern | housing | 4×5×4 | box-UV (100,4) | riveted iron frame border, soul-glass panes inside; pane shine-through emissive |
| glow_flame | soul flame | 2×2×2 | box-UV (116,4) | white-hot core → teal rim — **emissive**; renderer sputters it out over the first 30t of the death collapse (`isLanternFlameLit`) |
| cap | lantern crown | 3×1×3 | box-UV (116,0) | iron cap the chain seats into |
| glow_gaze | soul shell | 4×5×4 (inflate 0.35) | box-UV (100,13) | translucent teal veil (alpha 96, rim-boosted, bright motes) — **emissive**, rendered ONLY while `isGazing()` (renderer un-hides it); needs `withTranslucency()` |
| oar_grip | — (cube-less) | — | — | grip anchor at chest height — every oar pose rotates here |
| oar_shaft | shaft | 2×36×2 | box-UV (60,18) | waterlogged wood grain; wrapped grip rows on the top third |
| oar_blade | blade + tip | 1×7×5 / 1×2×3 | box-UV (68,18) / (80,18) | soul-stain blotches toward the chipped tip; whip-lag bone in the sweep |

**Art brief (carried over from the frozen MOB-BOSS1/v2 identity,
`scripts/skin_gen/ferryman_v2.py`):** the drowned pilot of the ghost ship — drowned
green-black robe `#202C28` (hems/tatters `#18221E`) silting into pale barnacle crust
`#5E7466`/`#7A9284` toward the waterline, with rare wet beads catching the lantern; hood
`#141B18` wet sackcloth with the open north cowl; old-bone skull `#D8D2BE` (shadow
`#A8A28C`, hollow sockets `#0E1410`); soul-teal eye slit `#8FF2DE` → `#D9FFF6`;
waterlogged oar `#4A3A28` shaft (grip wrap `#2E2418`) with a `#3C2F20` blade stained
`#33301F` at the tip; wet iron chain `#626670` with rust `#4A3E36`; riveted lantern
`#3A3E46`/`#6A707C` over `#274441` soul-glass; soul flame `#A8F7E6` with an `#E8FFF8`
heart and `#7ADCC8` rim; robe sheen wash `#57907F`.

**Emissive (glowmask):** `glow_eyes` + `glow_flame` + `glow_gaze` + `glow_robe`
(`glow_` bones auto-included by the painter) plus glow painters for the skull's socket
embers and the lantern's glass-pane shine-through. All emissive pixels are ALSO painted
bright in the albedo (conventions §4 — they must read under Iris shaderpacks). The
glowmask is masked by the albedo alpha, so the kelp-ragged tatter cutouts stay dark.

**Generator:** `python3 scripts/geckolib_gen/mobs/ferryman.py` (deterministic —
byte-identical on rerun; writes albedo + glowmask in one run). The legacy 256×256
repaint (`scripts/skin_gen/ferryman_v2.py`) is obsolete with the vanilla model and gets
deleted in the integrator cleanup patch (`docs/plans_v3/session_0730/
MA4_FERRYMAN_REPORT.md` §7).
