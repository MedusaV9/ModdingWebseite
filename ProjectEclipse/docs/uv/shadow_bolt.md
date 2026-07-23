# UV map — Shadow Bolt (`assets/eclipse/textures/entity/shadow_bolt.png` + `_glowmask.png`)

**Texture size:** 32×32 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/shadow_bolt.geo.json` (GeckoLib, 3 bones /
4 cubes — the cultist/warden projectile spike-orb, hitbox 0.35×0.35). The geo file
**is** the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`) parses
it and computes every face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| glow_core | orb | 3×3×3 | box-UV (0,0) | flame-material violet core |
| spikes | X shaft | 6×1×1 | box-UV (0,8) | skewers the orb along X |
| spikes | Y shaft | 1×6×1 | box-UV (0,12) | along Y |
| spikes | Z shaft | 1×1×6 | box-UV (14,8) | along Z |

`root` (pivot 0,2.8,0) spins in `animation.shadow_bolt.idle`; `spikes` counter-tumbles
and `glow_core` counter-rotates so the orb strobes against the shafts in flight.

**Art brief:** core is flame-material `#EFE3FF` → `#B98CFF` (shadeless); spike shafts are
near-black obsidian `#232030` whose tip pixels (both extremes of each shaft's long axis
and the 1×1 end caps) pick up the core light (`#B98CFF` mixed toward the core white).

**Emissive (glowmask):** the `glow_core` orb (auto via prefix) + the spike tip pixels
(custom glow painter, alpha 210). `ShadowBoltRenderer` renders the entity fullbright
(block light 15) and adds `AutoGlowingGeoLayer`, so the bolt reads identically in
lit corridors and pitch-black vault rooms.

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/shadow_bolt.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size.
