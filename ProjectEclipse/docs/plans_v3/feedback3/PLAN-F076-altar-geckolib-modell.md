# PLAN F-076 — "Altar als richtiges Blockbench/GeckoLib-Modell"

> **User report (F-076):** _"Baue den Altar Block als Richtiges Model in Blockbench/Blender
> und er soll auch mit GeckoLib Animations haben. Er soll mächtig wirken."_ — Replace the
> altar's flat cube with a proper Blockbench-style 3D model rendered through GeckoLib,
> animated (idle + interaction reactions), and it must look POWERFUL.
>
> **Status:** planning-wave audit complete. The audit found the F-076 chassis already
> **implemented and committed** (`eae14f4` — "GeckoLib monument model … (F-075, F-076)"):
> geo + animation JSON, generated textures, renderer, BE animatable, trigger facade and
> all four server wirings exist. This document is therefore the authoritative design
> record for that implementation — exact bone/cube spec, keyframe tables, texture
> generator, trigger wiring — plus the acceptance checklist to verify it and the noted
> deviations from the original task sketch. All paths relative to `ProjectEclipse/`.

---

## 1. Audit — the altar before/around F-076

| Aspect | Finding |
|---|---|
| Block class | `ritual/AltarBlock.java` — `BaseEntityBlock`, admin-placed only, `strength(50, 1200)`, `noLootTable()`, registered as `eclipse:altar` in `registry/EclipseBlocks.java` |
| Block entity | `ritual/AltarBlockEntity.java` — existed BEFORE F-076 as the server-side brain (milestone deposits, shard banking, daily offering, revive sigil). Type `EclipseBlockEntities.ALTAR` |
| Hitbox | No `getShape` override → **full 1×1×1 cube** collision/outline. Unchanged by F-076 (the geo only EXCEEDS bounds visually) |
| Old visual | `blockstates/altar.json` → `models/block/altar.json` (`cube_bottom_top`, textures `altar_top/_side/_bottom`) — a flat retextured cube |
| Placement | Center island: `worldgen/structure/AltarSanctumBuilder` (altar at ground+`ALTAR_ABOVE_GROUND`=4) / `FloatingSanctumBuilder`; canonical position in `EclipseWorldState.getSanctumAltarPos()` |
| Interactions (server) | Sneak-right-click + item = pay in (milestone deposit → `handleMilestoneDeposit`, shards → `ShardEconomy.deposit`, else daily offering); milestone completion = `completeMilestone` (altar level up); shop purchase ceremony = `economy/AltarBuyCeremony` |

## 2. Audit — GeckoLib pattern available in the repo

* **GeckoLib 4.9.2** (`gradle.properties: geckolib_version=4.9.2`), artifact
  `software.bernie.geckolib:geckolib-neoforge-1.21.1`, embedded jar-in-jar
  (`build.gradle` §"GeckoLib 4.9.2"). Runs client+server.
* **A geo BLOCK precedent already exists**: the respawn door —
  `geo/block/respawn_door.geo.json` + `animations/block/respawn_door.animation.json` +
  a `GeoBlockRenderer` with `RenderShape.INVISIBLE` on the block ("respawn-door pattern").
  The altar copies this pattern exactly.
* **Block-entity API pattern** (same as the ~19 P6 mobs, but `GeoBlockEntity`):
  implement `software.bernie.geckolib.animatable.GeoBlockEntity`, hold an
  `AnimatableInstanceCache` from `GeckoLibUtil.createInstanceCache(this)`, register an
  `AnimationController` in `registerControllers`, add one-shots via `triggerableAnim`,
  fire server-side with `triggerAnim(controller, name)` — **GeckoLib syncs BE triggers
  over its own network path, no custom payloads needed**.
* **Renderer**: `GeoBlockRenderer<T>` + `DefaultedBlockGeoModel` (one id resolves the
  triple `geo/block/<id>.geo.json` / `animations/block/<id>.animation.json` /
  `textures/block/<id>.png`), registered via `EntityRenderersEvent.RegisterRenderers`.
* **Glowmask convention**: `AutoGlowingGeoLayer` (used by mob/item renderers, see
  `client/entity/geo/EclipseGeoRenderer`) reads `<texture>_glowmask.png` — emissive
  pixels render fullbright.
* **Anim-id scheme**: `entity/geo/EclipseGeoAnimations` — frozen
  `animation.<path>.<name>` ids, `loop()/once()/hold()` helpers.
* **Tooling**: `scripts/geckolib_gen/validate_geo.py` (geo+anim linter, bone
  cross-check, `glow_`-prefix emissive flag) and `scripts/geckolib_gen/paint_lib.py`
  (`GeoPainter`: paints per-bone materials onto the geo's UV layout, writes albedo +
  glowmask deterministically).

## 3. Files (create ✚ / modify ✎) — all present at `eae14f4`

| File | Role |
|---|---|
| ✚ `src/main/resources/assets/eclipse/geo/block/altar.geo.json` | monument geometry (§4) — hand-authored Bedrock-format JSON, linted by `validate_geo.py` |
| ✚ `src/main/resources/assets/eclipse/animations/block/altar.animation.json` | `idle` + 4 one-shots (§5) |
| ✚ `tools/altar/gen_altar_texture.py` | deterministic PIL/paint_lib texture generator (§6) |
| ✚ `src/main/resources/assets/eclipse/textures/block/altar.png` + `altar_glowmask.png` | generated 256×128 albedo + emissive |
| ✚ `src/main/java/.../client/altarmodel/AltarModelRenderer.java` | `GeoBlockRenderer<AltarBlockEntity>` + `AutoGlowingGeoLayer` + widened render AABB |
| ✚ `src/main/java/.../client/altarmodel/AltarModelRenderers.java` | BER registration (`EntityRenderersEvent.RegisterRenderers`) |
| ✚ `src/main/java/.../ritual/AltarModelTriggers.java` | server-side facade: fire any one-shot on the sanctum altar from ANY system |
| ✎ `src/main/java/.../ritual/AltarBlockEntity.java` | implements `GeoBlockEntity`; controller `state` (idle loop + 4 triggerable one-shots); fires heartbeat/stage_up internally |
| ✎ `src/main/java/.../ritual/AltarBlock.java` | `getRenderShape → RenderShape.INVISIBLE` (static JSON model no longer drawn) |
| ✎ `src/main/java/.../economy/AltarBuyCeremony.java` | fires `gift` on the purchase-ceremony climax |
| ✎ `src/main/java/.../sequence/endarrival/EndArrivalSequence.java` | fires `erupt` in the CHARGE phase (End reveal) |
| — unchanged | `blockstates/altar.json`, `models/block/altar.json` (still feed breaking particles + the admin `BlockItem` inventory look), `EclipseBlocks`, `EclipseBlockEntities` |

**Deviations from the task sketch (deliberate, house conventions win):**

* Generator lives in `tools/altar/` (sibling of `tools/photon/` etc.), not
  `tools/models/`; the shared painting engine is `scripts/geckolib_gen/paint_lib.py`.
* The `.geo.json` is authored directly as JSON (validated by `validate_geo.py`) rather
  than emitted by a python script — 15 bones/30 cubes is below the threshold where a
  generator pays off. Optional follow-up: `tools/altar/gen_altar_geo.py` if iteration
  on the silhouette is ever needed.
* Texture is 256×128 (not 64²/128²) — the UV budget for 30 cubes demands it.
* Bone/anim names follow the shipped design sheet, not the sketch vocabulary:
  `base→plinth`, `column→core_pivot`, `ring_lower/upper→ring_a/b/c` (three rings),
  `shard_1..4→debris_1..4`, `crystal_core→core`+`glow_core`, `halo→ring_c`;
  anims `deposit→heartbeat` (1.2 s), `tierup→stage_up` (2.5 s), `purchase→gift`
  (3.5 s), plus a bonus finale-grade `erupt` (6 s).

## 4. Geometry spec — `geometry.altar` (texture 256×128, visible bounds 5×4.5 @ +1.75)

Units: 16 = 1 block; origin = corner, `to = origin + size`. Silhouette: a two-step
deepslate plinth (26-wide skirt → 20 → 16 obsidian body → 22-wide crown plate) wearing
4 corner horns, 4 floating shadeless rune plates, a floating eclipse core ~1.6 blocks
above the crown, three counter-rotating rune rings and four orbiting debris chips.
Overall ~1.9 blocks tall static, visually ~2.9 blocks during `erupt`; rings reach
~1 block past the block cell on every side.

| Bone | Parent | Pivot | Cubes (origin → size) | Notes |
|---|---|---|---|---|
| `root` | — | 0,0,0 | — | quake shaker (erupt) |
| `plinth` | root | 0,0,0 | [-13,0,-13]→26×3×26; [-10,3,-10]→20×3×20; [-8,6,-8]→16×7×16; [-11,13,-11]→22×3×22 | skirt, step, body, crown plate (crown gets the gold-violet inlay ring glow) |
| `horns` | plinth | 0,16,0 | 4× 3×6×3 at the crown corners (x/z = ±11-side pairs, y 16–22) | obsidian horns, glowing tips |
| `glow_runes` | plinth | 0,9.5,0 | 4× zero-thickness 14×5 plates floating 0.25 off each body face (y 7–12) | **shadeless auto-glow** (bone-name `glow_` prefix), the "engraving" |
| `core_pivot` | root | 0,26,0 | — | bob/lift/spin carrier for the whole core |
| `core` | core_pivot | 0,26,0 | [-4,22,-4]→8×8×8 | dark crystal shell, cracks glow |
| `glow_core` | core_pivot | 0,26,0 | [-3,23,-3]→6×6×6 | the eclipse heart, shadeless auto-glow, counter-spins |
| `ring_a` | root | 0,20,0 | 4 bars: 2× 22×2×2 (z=±[9..11]) + 2× 2×2×18 — a 22-unit square frame at y 19–21 | lower ring |
| `ring_b` | root | 0,25.5,0 | 4 bars: 2× 30×1×2 + 2× 2×1×26 — a 30-unit frame at y 25–26 | middle/wide ring (~1.9 blocks across) |
| `ring_c` | root | 0,30.5,0 | 4 bars: 2× 16×1×1 + 2× 1×1×14 — a 16-unit frame at y 30–31 | top halo |
| `debris_orbit` | root | 0,22,0 | — | orbit carrier (Y-spin = all four chips orbit) |
| `debris_1..4` | debris_orbit | at each chip | 3³ @ [14,18,-2]; 2³ @ [-18,24,-1]; 3³ @ [-2,15,14]; 2³ @ [-1,28,-16] | staggered radii/heights, cracks glow |

15 bones, 30 cubes. `glow_*` bones auto-copy to the glowmask; every other bone gets a
selective glow painter (§6) so the STONE stays dark while its engravings blaze — that
contrast is the "mächtig" read at night.

## 5. Animation spec — `animation.altar.<name>` (format 1.8.0; `~` = catmullrom)

### `idle` — loop 12.0 s (perpetual, powerful-at-rest)

| Bone.channel | Keyframes |
|---|---|
| `core_pivot.rotation` | 0→[0,0,0], 12→[0,360,0] (linear full turn) |
| `core_pivot.position` | ~ 0:[0,0,0], 3:[0,2,0], 6:[0,0,0], 9:[0,-1.2,0], 12:[0,0,0] (breathing bob) |
| `glow_core.rotation` | 0→[0,0,0], 12→[0,-720,0] (heart counter-spins 2×) |
| `glow_core.scale` | ~ 1 → 1.1 @3 → 1 @6 → 1.1 @9 → 1 @12 (pulse) |
| `core.scale` | ~ 1 → 1.05 @6 → 1 @12 |
| `ring_a.rotation` / `ring_b.rotation` / `ring_c.rotation` | 0→12 s: +360 / **−360** / +360 (counter-rotation) |
| `ring_c.position` | ~ 0 → [0,0.8,0] @6 → 0 @12 (halo floats) |
| `glow_runes.scale` | ~ 1 → 1.03 @3 → 1 @6 → 1.03 @9 → 1 @12 (rune shimmer) |
| `debris_orbit.rotation` | 0→12 s: [0,−360,0] (chips orbit against the core) |
| `debris_1..4.position` | phase-offset vertical bobs, e.g. d1 ~ +1.2@4/0@8/−0.6@10; d2 −1@6; d3 +1@7; d4 +0.8@3/−0.5@8 |

### `heartbeat` — once 1.2 s (every accepted payment: the altar "swallows")

| Bone.channel | Keyframes |
|---|---|
| `core.scale` | ~ 1 → **1.28 @0.15** → 0.94 @0.4 → 1.12 @0.65 → 1 @1.2 (double-thump) |
| `glow_core.scale` | ~ 1 → 1.5 @0.15 → 1 @0.8 (flash) |
| `glow_runes.scale` | ~ 1 → 1.15 @0.2 → 1 @0.9 |
| `core_pivot.position` | ~ 0 → [0,1.5,0] @0.2 → 0 @0.9 (hop) |
| `ring_a/b.rotation` | ~ 0 → ±25° @0.35 → 0 @1.2 (recoil kick, opposed) |

### `gift` — once 3.5 s (shop purchase: rings open, core lifts, light breaks out)

| Bone.channel | Keyframes |
|---|---|
| `ring_a.position` | ~ 0 → [0,−3,0] @1.0 (hold to 2.4) → 0 @3.5 |
| `ring_b.position` / `ring_c.position` / `core_pivot.position` | ~ rise to +4 / +6 / +7 @1.0–1.2, hold to ~2.2–2.4, settle @3.5 (rings fan OPEN) |
| `ring_a.rotation` | 0 → 160° @1.6 → 360° @3.5; `ring_b.rotation` 0→−360 @3.5 |
| `ring_b.scale` | ~ 1 → [1.12,1,1.12] @1.2 → 1 @3.5 (ring dilates) |
| `core.scale` / `glow_core.scale` | ~ 1→1.18 @1.4→1; 1→**1.7** @1.3→1.4 @2.2→1 (the light "hands out") |
| `glow_runes.scale` | ~ 1 → 1.2 @1.0 → 1 @3.5 |
| `debris_orbit.rotation` | 0→[0,−720,0] (chips race) |

### `erupt` — once 6.0 s (End reveal / finale quake)

| Bone.channel | Keyframes |
|---|---|
| `root.position` | flat until 1.2, then XZ shake ±0.4→±0.15 decaying @1.35–2.4, settle @2.7 (the monument TREMBLES) |
| `core_pivot.position` | ~ 0 → +1 @0.8 → **+14 @2.2** → +15 @4.0 → 0 @6.0 (core climbs ~1 block) |
| `core_pivot.rotation` | 0→[0,1080,0] (3 full turns) |
| `glow_core.scale` | ~ 1 → **2.2 @2.4** → 1.8 @4.5 → 1 @6.0; `core.scale` 1→1.3@2.4→1 |
| `ring_a/b/c.rotation` | +1080 @5 / **−1440 @5.5** / +720 @4 (rings race, opposed) |
| `ring_a/b/c.position` | ~ rise +6/+9/+12 @2.4–2.8, hold, settle @6.0 (ring stack stretches upward) |
| `glow_runes.scale` | ~ 1 → 1.35 @2.0 → 1 @6.0; `debris_orbit.rotation` 0→−1080 |

### `stage_up` — once 2.5 s (milestone complete: ascension fanfare)

| Bone.channel | Keyframes |
|---|---|
| `ring_a/b/c.position` | ~ staggered pops +2 @0.5 / +3 @0.6 / +4 @0.7, settle @1.6/1.8/2.0 |
| `ring_a/b.rotation` | 0→±360 @2.5 (opposed) |
| `core.scale` | ~ 1→1.2 @0.3→1 @0.8→1.25 @1.2→1 @2.0 (double-pulse) |
| `glow_core.scale` | ~ 1→1.6 @0.4→1.1 @0.9→**1.7 @1.3**→1 @2.2 |
| `glow_runes.scale` | ~ 1→1.25 @0.5→1 @2.2; `core_pivot.position` ~ 0→+3 @0.9→0 @2.2 |

## 6. Texture plan — `tools/altar/gen_altar_texture.py` (deterministic, seed `0x0A17A2`)

* Engine: `scripts/geckolib_gen/paint_lib.GeoPainter` — reads the geo's UV layout and
  paints per-bone material functions; one run writes BOTH `altar.png` (256×128) and
  `altar_glowmask.png`. Reruns are byte-identical. Run from `ProjectEclipse/`:
  `python3 tools/altar/gen_altar_texture.py`.
* Palette (house gold-violet): deepslate `#2B2B33`/`#1F1F26`, obsidian `#171320`/
  `#0F0C16`, crown `#37323F`, violet `#B98CFF`/`#E7D6FF`/`#6E4DA8`, gold `#FFE9B0`/
  `#C9A24D`, void heart `#0A0510`/`#060309`.
* Materials: `deepslate()` (striations, mortar cracks, pale flecks) for the base steps;
  `obsidian()` (dark flow bands, violet sheen/glints) for body/horns/debris; crown
  plate with a gold-violet inlay ring on the up face; rune plates = violet stroke
  glyphs on transparency; core = obsidian shell with crack web; heart = near-black
  disc ringed in blazing violet; rings = dark stone frames with glowing tick marks.
* Emissive: `glow_runes`/`glow_core` bones auto-copy their (shadeless) albedo into the
  glowmask; custom glow painters add ONLY the crown inlay, horn tips, core cracks,
  ring ticks and debris cracks — `AutoGlowingGeoLayer` renders these fullbright.

## 7. Integration & trigger wiring

* **Render path**: `AltarBlock.getRenderShape → INVISIBLE`; `AltarModelRenderer`
  (`GeoBlockRenderer` + `DefaultedBlockGeoModel(eclipse:altar)` + `AutoGlowingGeoLayer`)
  registered for `EclipseBlockEntities.ALTAR` in `AltarModelRenderers`. The altar has
  no FACING property; the geo renders unrotated (4-fold symmetric).
* **Culling**: `getRenderBoundingBox` widened to `(x−2,y,z−2)…(x+3,y+5,z+3)` — the geo
  exceeds the block cell, so the default 1-cube box would frustum-pop.
* **Hitbox**: unchanged full cube (rings/core are visual-only; a taller VoxelShape would
  break existing click lanes and the sanctum's walkability). Breaking particles + the
  admin `BlockItem` inventory look still come from the retained
  `blockstates/altar.json`/`models/block/altar.json`.
* **Animation chassis** (`AltarBlockEntity`): one controller `state` (transition 4 ticks)
  looping `idle`, with `triggerableAnim` one-shots `heartbeat`/`gift`/`erupt`/`stage_up`;
  ids built via `EclipseGeoAnimations.loop/once("altar", …)`. Triggers ride GeckoLib's
  own BE trigger sync — **no new payloads**.
* **Trigger table** (server → model):

| Game event | Anim | Call site |
|---|---|---|
| Milestone deposit accepted (ladder not complete) | `heartbeat` | `AltarBlockEntity.handleMilestoneDeposit` |
| Umbral-shard banking | `heartbeat` | `AltarBlock.onSneakRightClick` (shard lane) |
| Daily offering swallowed | `heartbeat` | `AltarBlockEntity.handleOffering` |
| Milestone completes (altar level up) | `stage_up` | `AltarBlockEntity.completeMilestone` (under the W-P-ALTAR ceremony FX) |
| Shop purchase ceremony climax | `gift` | `AltarBuyCeremony` via `AltarModelTriggers.gift` |
| End-reveal CHARGE phase | `erupt` | `EndArrivalSequence` via `AltarModelTriggers.erupt` |

* **Facade** (`ritual/AltarModelTriggers`): resolves the altar via
  `EclipseWorldState.getSanctumAltarPos()`; unloaded chunk / missing BE degrades to a
  logged no-op returning `false` — triggers are garnish and must never throw.

## 8. Test checklist

1. `python3 scripts/geckolib_gen/validate_geo.py src/main/resources/assets/eclipse/geo/block/altar.geo.json src/main/resources/assets/eclipse/animations/block/altar.animation.json` → 0 errors; all animated bones exist.
2. `python3 tools/altar/gen_altar_texture.py` → reruns byte-identical (`git status` clean).
3. `./gradlew build` green.
4. Client, at the sanctum altar (or `/setblock ~ ~ ~ eclipse:altar`): monument renders ~2 blocks tall; idle loops — rings counter-rotate, core bobs+spins, debris orbits; runes/heart/inlay/ticks glow fullbright at night (glowmask).
5. Sneak-right-click an umbral shard / milestone item / offering → `heartbeat` thump each time.
6. Complete a milestone (deposit remaining cost) → `stage_up` fanfare under the level-up ceremony; NO extra heartbeat on the completing deposit.
7. Buy from the altar panel shop → `gift` (rings fan open ~3.5 s) on the ceremony climax.
8. End-reveal (or dev-trigger the sequence) → `erupt`: quake shake, core climbs ~1 block, rings race.
9. Frustum: walk so the altar's block cell leaves the screen edge while rings are visible → no pop (widened AABB).
10. Second client watching the altar sees the same one-shots (GeckoLib BE trigger sync); breaking overlay/particles still show the stone texture; the admin BlockItem still renders the old cube in inventory.
11. Leave/rejoin at the altar → idle resumes; fire a trigger with the chunk unloaded → `AltarModelTriggers` logs + returns `false`, no crash.
