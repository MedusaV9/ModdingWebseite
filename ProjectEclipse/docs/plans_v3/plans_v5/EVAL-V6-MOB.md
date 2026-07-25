# EVAL-MOB — v6 mob polish precision grade

## Verdict

**Overall: 8.8/10.**

The asset plumbing is unusually strong: all 14 GeckoLib geo/animation pairs parse, all
bone-parent graphs resolve, every cube UV stays inside its declared canvas, all animated
bones exist, all animation timestamps/lengths/loop modes validate, the Java animation
contract is exact, and the Ferryman/Herald model-part contracts are complete. The main
precision failure is concentrated in MOB-BOSS2: both showcase death animations are
nominally authored to fill the entities' exact death windows, but a Java action-controller
slowdown means the entities are removed after only about one quarter of those animations.
Fog Tyrant's new wisps also double-apply their geo rest roll.

No Gradle or git command was run, per evaluation constraints.

## Scores

| Cluster | Score | Precision judgment |
|---|---:|---|
| MOB-BOSS1 — Ferryman, Herald | **10.0/10** | Both 256² sheets are intentional 2× texel-density skins over 128² `LayerDefinition`s. All 19 Ferryman and 36 Herald constructor `getChild` references resolve against `createBodyLayer`; generators reproduce committed sheets exactly. |
| MOB-BOSS2 — Fog Tyrant, Rift Warden | **6.0/10** | Geo, UV, animation schema, IDs, masks, and generators are clean, but both new death showcases are cut off by the 0.2× controller-speed floor. Tyrant's new wisp rotations also encode the geo rest roll a second time. |
| MOB-FOG — Colossus, Revenant, Storm Hound | **10.0/10** | All three pairs validate with no schema/contract defect, 0 UV overlaps, exact base/mask dimensions, exact generator reproduction, and correct one-shot/loop modes. |
| MOB-GLITCH — Husk, Hound, Tick, Wanderer, The Other | **9.0/10** | Four GeckoLib pairs and Java IDs/bones are clean; deterministic regeneration is exact. Hound alone has emissive pixels over fully transparent albedo in both frames. Tick's absent `glitch_blink` is intentional because its inherited blink cooldown is disabled. |
| MOB-AMBIENT — Deckhand, Orin, Sentinel, Gazer, Cultist, Stalker, Sunmote, Lantern | **9.0/10** | Contracts and deterministic output are clean. The validator reports 46 fractional-UV warnings in three touched geos (32 on v6-added cubes), so painter rasterization rounds beyond exact UV boundaries. Gazer's current Javadoc also still says six cubes after adding four more. |

## Audit evidence

### 1. GeckoLib geometry and animation

- Ran `scripts/geckolib_gen/validate_geo.py` over all 28 files: **28/28 PASS**.
- Geometry: 14/14 identifiers/canvases valid; no duplicate bones, missing/orphan
  parents, parent cycles, negative cube sizes, or out-of-bounds face UVs.
- Programmatic face-footprint audit: **0 cross-cube UV overlaps** in every geo
  (1,450 face rectangles total).
- Animation: 88 animations; every animated bone belongs to its paired geo; no negative,
  unsorted, or beyond-length keyframes. Idle/locomotion animations loop, attacks/specials
  are one-shot, and deaths use `hold_on_last_frame` as intended.
- The only validator warnings are fractional box-UV rectangles:
  Deckhand 20, Wizard Orin 20, Drift Lantern 6. These are legal, but the generator rounds
  the painter footprint outward.

### 2. Java-to-asset contract

- Expanded inherited `idle`/`walk`/`death` IDs plus every entity override and
  `triggerableAnim` registration: **88/88 Java-required animation IDs exist** and the 14
  animation files contain no unexplained extra IDs.
- Fog Tyrant: 10/10; Rift Warden: 9/9; Fog trio: 18/18; glitch family: 21/21;
  ambient GeckoLib set: 30/30.
- Deckhand's Java/OarAnimator names `head`, `oar`, and `oar_blade` all exist in
  `deckhand.geo.json`. Other head-tracking renderers likewise have `head`; Drift Lantern
  correctly does not opt into head tracking.
- `glitched_tick.animation.json` correctly omits `glitch_blink`: `GlitchedMonster`
  defaults `blinkCooldownMinTicks()` to `-1`, so Tick neither registers nor triggers it.

### 3. Vanilla hierarchical models

- Ferryman: **19 referenced / 25 defined / 0 unresolved**.
- Herald: **36 referenced / 36 defined / 0 unresolved**.
- Dynamic families were expanded during the comparison: Ferryman `strip0..3`,
  `tatter0..2`, `chain0..2`; Herald `crown0..3`, `shard0..7`, `halo0..2`, and all
  16 `tentacle{0..3}_seg{0..3}` paths.
- The 256² Ferryman/Herald PNGs are not a canvas mismatch. Their Java UV space remains
  128² and the sheets deliberately provide two physical texels per model UV unit.

### 4. Textures and generators

- Relevant generators exist under `scripts/geckolib_gen/mobs/` and
  `scripts/skin_gen/`; no `tools/` fallback is needed.
- Ran 17 relevant drivers twice in an isolated copy. The complete generated asset tree
  was SHA-256-identical between passes **and byte-identical to the committed tree**.
- All 14 GeckoLib base PNG dimensions equal their geo canvas declarations.
- Checked all 19 base/glowmask pairs: **0 dimension mismatches**.
- Glow-vs-albedo alpha check found only Hound:
  `glitched_hound.png` and `glitched_hound_alt.png` each have glow at `(42,42)` and
  `(42,43)` while base alpha is zero.

## Defects

### D1 — HIGH: Rift Warden's v6 death shatter cannot reach its payoff

`RiftWardenEntity` slows the entire action controller from 0.9× to a permanent 0.2×
during death (`src/main/java/dev/projecteclipse/eclipse/entity/boss/rift/RiftWardenEntity.java:290-294`),
while removing the entity at 60 ticks
(`src/main/java/dev/projecteclipse/eclipse/entity/boss/rift/RiftWardenEntity.java:917-939`).
The JSON is 3.0 seconds and places the new shard-D collapse at 1.4–3.0 seconds and plate
peels at 1.2–3.0 seconds
(`src/main/resources/assets/eclipse/animations/entity/rift_warden.animation.json:976-987`,
`:1133-1173`). Integrating the speed handler over 60 ticks advances only about 14.8
animation ticks, or **0.74 s**. The new shard collapse and plate peel never occur before
removal. This directly contradicts the claimed 60-tick completion check in
`docs/plans_v3/plans_v5/fxteams/MOB-BOSS2.md:199-201`.

### D2 — HIGH: Fog Tyrant's v6 death dissipation is likewise truncated

The same controller slowdown exists at
`src/main/java/dev/projecteclipse/eclipse/entity/boss/fog/FogTyrantEntity.java:399-403`,
and the entity is removed at 70 ticks
(`src/main/java/dev/projecteclipse/eclipse/entity/boss/fog/FogTyrantEntity.java:1255-1302`).
The death animation is 3.5 seconds
(`src/main/resources/assets/eclipse/animations/entity/fog_tyrant.animation.json:815-824`),
but the handler advances only about 16.8 animation ticks, or **0.84 s**. The new wisp rise
does not even reach its first 1.0-second key, much less the 1.8/2.6/3.5-second
dissipation keys (`src/main/resources/assets/eclipse/animations/entity/fog_tyrant.animation.json:936-953`).

### D3 — MEDIUM: Fog Tyrant's new wisp rest roll is encoded twice

The geo already pre-rolls the wisps −8°/+8°
(`src/main/resources/assets/eclipse/geo/entity/fog_tyrant.geo.json:126-142`), while idle
adds `-8 + sin(...)` / `8 + sin(...)`
(`src/main/resources/assets/eclipse/animations/entity/fog_tyrant.animation.json:82-90`);
action start/end keys repeat the same ±8 pattern. GeckoLib 4.9.2 adds sampled animation
rotation to the bone snapshot's rotation, so the idle center is −16°/+16°, not the logged
−8°/+8° rest. The polish note itself incorrectly calls `-8 + sin(...)` “relative” at
`docs/plans_v3/plans_v5/fxteams/MOB-BOSS2.md:106-108`. The animation delta should center
on zero if the geo owns the pre-roll.

### D4 — MEDIUM: Hound glowmask survives two albedo dropout pixels

Both base and alt Hound sheets glow at `(42,42)` and `(42,43)` where albedo alpha is
zero. The base body gets independent alpha dropout at
`scripts/geckolib_gen/mobs/glitched_hound.py:72-83`, but body emissive scars are generated
independently at `scripts/geckolib_gen/mobs/glitched_hound.py:92-96`;
`scripts/geckolib_gen/mobs/glitch_lib.py:86-115` shows the two unrelated gates. Mask the
glow result by final albedo alpha (or share the dropout gate) so holes remain holes.

### D5 — LOW: v6 adds fractional box-UV footprints that require outward raster rounding

The new Deckhand hood/belt/lantern cubes use 3.5, 8.5, 6.5, 0.6, and 2.4 dimensions
(`src/main/resources/assets/eclipse/geo/entity/deckhand.geo.json:52-74`), Orin's crystal
uses 1.2³ (`src/main/resources/assets/eclipse/geo/entity/wizard_orin.geo.json:141-146`),
and Lantern's kernel uses 1.5³
(`src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json:37-42`).
Those v6 cubes account for **32 fractional-UV warnings**. They remain in bounds and do not
overlap another cube, so this is not a schema failure; it is a precision debt because
painted integer texels extend beyond the exact sampled rectangles.

### D6 — INFO: Gazer cube-count Javadoc was not updated

`src/main/java/dev/projecteclipse/eclipse/client/entity/GazerModel.java:20-29` still calls
the current model “6 cubes,” then describes the four newly added iris/lid cubes. The
actual layer now defines ten cubes. This has no runtime impact, but it makes the model
inventory imprecise.

## Three weakest mobs

1. **Fog Tyrant** — two independent v6 misses: the shoulder wisps double their intended
   rest roll, and essentially the entire new death-dissipation sequence occurs after the
   server has removed the model.
2. **Rift Warden** — its marquee v6 shard/plate death shatter is authored correctly in
   JSON but never reaches the relevant keyframes because the controller slowdown was not
   included in the timing audit.
3. **Glitched Hound** — otherwise clean, but it is the only mob whose regenerated
   glowmask emits through fully transparent albedo, in both normal and alt frames.

## Recommended correction order

1. Remove or compensate for the boss action-controller death slowdown; at 1×, the
   existing 3.5 s/70 t and 3.0 s/60 t authoring already matches the server windows.
2. Re-center Fog Tyrant wisp animation rotations on zero while retaining ±8° in the geo.
3. Apply Hound dropout to glow generation, then regenerate both frames and masks.
4. Prefer integer box dimensions/UV footprints for future added cubes, or document and
   test intentional per-face fractional sampling.
