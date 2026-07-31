# UV map — Umbral Stalker (`assets/eclipse/textures/entity/umbral_stalker.png` + `_glowmask.png`)

**Texture size:** 64×64 (both files — GeckoLib's `AutoGlowingTexture` enforces matching
canvases). Model: `assets/eclipse/geo/entity/umbral_stalker.geo.json` (GeckoLib, MC2
conversion — 28 bones / 27 cubes; hitbox 0.9×1.2). As with every GeckoLib mob the geo
file **is** the UV source of truth — the painter (`scripts/geckolib_gen/paint_lib.py`)
parses it and computes each face rect itself, so only the layout is frozen here:

| Bone | Cube | Box W×H×D | UV | Notes |
|---|---|---|---|---|
| body | trunk | 7×6×12 | box-UV (0,0) | pivot (0,11,0); umbral cracks wander the flank faces |
| hump | **shoulder hump** | 6×5×7 | box-UV (38,0) | +5°; THE silhouette read — pivot (0,13,−3), bone keel along the crest |
| hump | crest cap | 4×2×5 | box-UV (10,37) | +9°; the keel ridge continues over it |
| glow_spine_a/b/c | crystal shards | 2×4×2 / 2×3×2 / 2×2×2 | box-UV (44,45) / (0,52) / (18,52) | swept −18°/−26°/−34°, shrinking toward the tail |
| neck | neck | 4×4×4 | box-UV (24,28) | pivot (0,13,−5.5) — **carries all animated head pitch/yaw** (see trap below) |
| head | skull | 6×5×5 | box-UV (0,18) | head-tracked bone (pivot 0,12,−8.5); eye pinpricks in the north-face top corners |
| head | snout | 4×3×3 | box-UV (14,45) | charcoal muzzle + bare nose; NO eye glow (painter gates on face width ≥ 6) |
| jaw | lower jaw | 4×2×4 | box-UV (28,45) | hinge (0,9.5,−13.5); pale violet inner mouth on the up face |
| tusk_l / tusk_r | bone sabres | 1×3×1 each | box-UV (60,28) / (60,37) | hang past the jaw line; deliberately **not** emissive |
| scapula_l / scapula_r | shoulder blades | 1×4×5 each | box-UV (0,28) / (12,28) | parents of the forelegs (pivots ±3,12.5,−4); ride up in `stalk_low` |
| leg_fl / leg_fr | upper forelegs | 2×5×3 | box-UV (54,18) / (40,28) | hip pivots at y=9.5, children of the scapulae |
| leg_fl_lower / leg_fr_lower | lower forelegs | 2×5×2 | box-UV (28,37) / (36,37) | knee pivots at y=5, 1 px overlap hides the joint in swing |
| haunch_l / haunch_r | haunches | 3×5×5 | box-UV (22,18) / (38,18) | pivots (±2.5,12,4) |
| leg_bl / leg_br | upper hindlegs | 2×5×3 | box-UV (50,28) / (0,37) | hip pivots at y=9 |
| leg_bl_lower / leg_br_lower | lower hindlegs | 2×5×2 | box-UV (44,37) / (52,37) | hide darkens toward the paws |
| tail_a | whip base | 2×2×5 | box-UV (0,45) | raised −14° |
| tail_b | whip mid | 2×2×4 | box-UV (52,45) | −10° on top of tail_a |
| tail_c | whip tip | 1×1×4 | box-UV (8,52) | −6°; shard-charged, glows |
| fx_smear_l / fx_smear_r | **empty FX anchors** | — | — | pivots (±3.5,11,−2); reserved for the B2 sprint shadow-smear spec (no cubes, no UV) |

**Art brief:** a wrong, shadow-slick night pack hunter. Near-black violet hide
(`#221A2E` vertically grained and hash-dithered against `#16111F`, with rare near-black
slick patches) pulled over a bone-ribbed **shoulder hump** — the hump IS the silhouette
the player reads across a dark field, so its crest carries a cold pale keel
(`#8B8398`→`#CCC3D6`, deliberately violet-grey, never warm ivory). Broken umbral cracks
(`#6B3FD4`, rare `#E4D4FF` flares) leak down the flanks, the muzzle is charcoal
(`#1C1626`) with a near-black jaw (`#120E19`) and a pale violet inner mouth (`#C6A6FF`),
two bone sabre tusks hang past the chin, and three shadeless flame-material spine shards
burn `#E4D4FF`→`#8A5CFF` down the back.

**Emissive (glowmask):** the three `glow_spine_*` shards (auto-included via the `glow_`
bone prefix), the **hump keel ridge** (a 2 px line down the crest plus the top row of the
side faces — the only thing that traces the hump at light 0), the `scapula_*` crests, the
flank cracks (the glow painter re-runs the same deterministic `_crack_at` test as the
albedo, at α 165 so the shadow leaks rather than floodlights), the two eye pinpricks
(gated to the ≥ 6 px skull face — no glowing nostrils), the inner mouth and the charged
whip-tail tip. The **tusks are dark on purpose**: they are the only non-glowing bright
thing on the mob, so the bite still reads against the shard light.
`UmbralStalkerGeoRenderer` installs the layer via `withGlowmask()`.

**Head-tracking trap:** `DefaultedEntityGeoModel.setCustomAnimations` *sets* (not adds)
the `head` bone's X/Y rotation from `netHeadYaw`/`headPitch` after the animation pass, so
any authored head pitch/yaw is silently discarded. Every animation therefore drives the
**`neck`** bone for pitch/yaw and leaves `head` with Z-roll only (verified by
`docs`-side audit: no animation writes a non-zero head X or Y).

**Generator (deterministic, byte-identical reruns):**

```
python3 scripts/geckolib_gen/mobs/umbral_stalker.py
```

Final AI art may replace the albedo PNG byte-for-byte at the same path/canvas size; if
the crack layout changes, regenerate the glowmask with it (both are traced by the same
`_crack_at` test — hand-drawn art must keep albedo and glow cracks aligned).
