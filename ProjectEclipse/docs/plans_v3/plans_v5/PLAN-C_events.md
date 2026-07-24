# PLAN-C — Events & Sequences (plans_v5)

PLANNER-C worker packages. Scope: the EVENT/SEQUENCE items from the v5 user feedback
round (limbo, intro, expansion, fog storms, ferryman, end, portals/event dimensions,
music). Every package was root-caused against the actual code; files are cited per
package. Ownership is disjoint: no two packages edit the same file. Cross-planner seams
(PLAN-A client/UI, PLAN-D systems) are called out explicitly.

Conventions (same as PLAN-D):

- **Effort** — S (≤ 3 files / < 1 focused session), M (4–10 files), L (> 10 files or new
  package + client + assets).
- New dimensions follow the `minigames/MinigameDimensions` void-dim pattern; new stamped
  structures follow `worldgen/structure/StructurePendingRegistry` (rift reveal, SavedData
  resume, dedup for free); new `/dev` commands register `DevCommandDoc` entries.
- All new strings ship en_us+de_de via `docs/plans_v3/langdrop/<PKG>.json` and depend on
  PLAN-A A1's i18n merge fix landing first.
- Restart mid-sequence skips to the end state (the `IntroSequence` law) — never resume a
  half-played cinematic.

**Items NOT given a C-package (already owned elsewhere — do not duplicate):**

- **Item 9 (no artifact + no sidebar pre-event)** — fully owned by PLAN-A **A8**
  (sidebar `eventStarted` gate + payload flag) and **A12** (`ArtifactSlotLock` pre-event
  early-return). PLAN-C adds nothing.
- **Item 15 (cutscene texts not translated)** — root cause is PLAN-A **A1**'s dead locale
  merge: `EclipseLang.mergeLocale` predicates never match (`…/en_us` vs actual
  `lang/en_us.json`), `KEY_PREFIXES` lacks `eclipse.caption.`, and `CaptionRenderer`
  bypasses `EclipseLang` via raw `Component.translatable(...).getString()`. All caption
  keys DO exist in both lang files (verified: `eclipse.caption.intro.*`, `…finale.*`,
  `…expansion.*` in `en_us.json` + `de_de.json`) — this is purely the A1 resolver bug.
  One residual C-side task lives in C6 step 6 (stale `config/eclipse/cutscenes/*.json`
  operator copies can carry pre-i18n literal ids).
- **Item 28, XP sub-point (quests/XP disabled in event dimensions)** — owned by PLAN-D
  **D2** (`skills/XpGates.actionXpAllowed` denies LIMBO/minigame/xbox dimensions). C17
  adds only the QUEST-detector side (D2 gates XP, not quest goal progress).
- **Item 28, bossbar sub-point** — the "too many bossbars" consolidation doctrine is
  PLAN-A **A7** (ONE day timer, strip bossbar duplicates). C17 executes the server side
  for the xbox timer bar specifically (the client HUD surface is A7's).

---

## C1 — Limbo water shader: real water mask + world-anchored waves + horizon curvature

**Covers items:** 1, 2, 5, and the shader half of 6.

**Root cause (verified in `assets/eclipse/pinwheel/shaders/program/limbo.fsh` +
`pinwheel/post/limbo.json`):**

1. *(Item 1)* The "water" mask is heuristic: the shader classifies a pixel as water from
   `baseLuma` (scene luminance) plus a screen-Y band. Anything dark below the horizon —
   ship hull, deckhands, wreck spars, players — passes the luma test and receives the
   purple caustic texture. There is no depth/world-position test at all.
2. *(Item 2)* Caustic noise coordinates are the raw screen-space `uv`. The pattern is
   therefore glued to the viewport and swims with every camera turn instead of being
   pinned to the sea surface.
3. *(Item 5)* No curvature/horizon term exists in the pipeline; the limbo sea ends at the
   vanilla far plane like any flat render.

**Exact fix (all in the limbo post pipeline; Veil post passes can bind the depth buffer
and inverse view-projection):**

1. Add the depth sampler + `CameraPos` / inverse view-proj uniforms to
   `pinwheel/post/limbo.json`; in `limbo.fsh` reconstruct the world position per pixel
   (`worldPos = invViewProj * ndc(uv, depth)`).
2. Water mask = `abs(worldPos.y - WaterlineY) < ε` AND downward-facing reconstruction
   (reject pixels whose depth belongs to geometry above the waterline). `WaterlineY` is a
   new uniform fed from `GhostShipBuilder.waterlineY` via `LimboAmbience` (which already
   feeds `GodrayDir` every frame — same seam). Deckhands/hull/players stop receiving
   caustics entirely.
3. Caustic UVs = `worldPos.xz * scale + VoyageOffset` — world-anchored; waves stay put
   when the camera moves. `VoyageOffset` is a new steadily-increasing `vec2` uniform
   (fed by `LimboAmbience`, direction = ship forward −X→+X): the whole caustic field
   streams slowly past the hull, which is the shader half of the item-6 "sailing"
   illusion. A custom still-water fluid is NOT recommended: the sea is vanilla water
   blocks under a post effect; replacing the fluid would touch worldgen
   (`LimboSeascape`), physics, and the intro submerge FX for zero visual gain over the
   world-anchored shader.
4. *(Item 5)* Curvature term in the same pass: displace the sampled scene UV vertically
   by `k * horizontalDistance(worldPos, CameraPos)²` (classic planet-curvature warp,
   bending UP toward the eclipse azimuth from `GodrayDir`), and fog the last 15% before
   the far plane into the sky gradient so the sea reads as endless instead of clipping.
   Clamp the warp near the screen edges (no letterbox smearing); respect `reducedFx`.

**Files:** `assets/eclipse/pinwheel/shaders/program/limbo.fsh`,
`assets/eclipse/pinwheel/post/limbo.json`, `veilfx/LimboAmbience.java` (uniform feeder).

**Effort:** M.

---

## C2 — Limbo sky: fix the glitchy zenith disc + world-drift illusion

**Covers items:** 4, and the sky/horizon half of 6.

**Root cause (verified in `client/sky/LimboSpecialEffects.java`):** the "giant purple
THING" is the zenith eclipse disc + aura (and its water reflection streak) drawn by
`LimboSpecialEffects`. It is positioned from `zenithWorldPoint` — a WORLD point at a
finite distance — instead of being camera-relative like vanilla celestials. As the ship
bobs and the camera moves, the disc parallax-swims, pops against the fog/horizon planes
and the separately-computed water reflection tears away from it: the "bugging around"
glitch. `LimboHorizonShips` (silhouette ships) is NOT the culprit — those fade correctly.

**Exact fix:**

1. Render the disc/aura camera-relative at effectively infinite distance: translate the
   modelview by the camera position (direction from `zenithWorldPoint - camera`,
   normalized), fixed angular diameter, depth test/write OFF, drawn in the sky pass
   before fog planes. No parallax, no clipping, no jitter.
2. Derive the water reflection streak from the SAME angular direction (mirror about the
   waterline plane) so disc and reflection can never desynchronize; fade the streak with
   the C1 water mask uniform seam (`WaterlineY`), not luminance.
3. *(Item 6, world half)* Sailing drift: give `LimboHorizonShips` a slow constant
   heading-relative drift (silhouettes slide astern over ~90 s and respawn ahead), and
   emit a sparse lane of foam/mote particles streaming past the hull (client-side, from
   the existing `LimboSpecialEffects` render hook; respects `reducedFx`). Combined with
   C1's `VoyageOffset` caustic stream, the world reads as moving around the anchored
   ship without touching any real geometry.

**Files:** `client/sky/LimboSpecialEffects.java`, `client/sky/LimboHorizonShips.java`.

**Effort:** M.

---

## C3 — Deckhands: stop look-at from wrecking the row cycle

**Covers item:** 3.

**Root cause (verified):** `DeckhandEntity` registers an unconditional
`LookAtPlayerGoal`, and vanilla body-rotation logic drags `yBodyRot` after `yHeadRot`
when a mob looks around. `DeckhandRenderer` mirrors the row animation for the port side
based on `yBodyRot` — so when a seated deckhand turns its head at a passing player, the
body yaw crosses the mirror threshold and the renderer flips/blends the row cycle: they
visibly "row wrong".

**Exact fix:**

1. Gate `LookAtPlayerGoal` behind the hostile state (curious idle stares are the bug's
   only benefit; hostile deckhands may keep it).
2. While benched/rowing, hard-pin the body: override the head-turn tick to
   `yBodyRot = yBodyRotO = benchFacingYaw` and clamp `yHeadRot` to ±30° of it (glances
   stay, torso never moves).
3. `DeckhandRenderer`: derive port/starboard mirroring from the seat assignment
   (`OarAnimator` knows the bench side) instead of live `yBodyRot` — makes the mirror
   decision immune to any future rotation source.

**Files:** `entity/DeckhandEntity.java`, `client/entity/DeckhandRenderer.java`,
`limbo/OarAnimator.java` (seat-side accessor).

**Effort:** S/M.

---

## C4 — Pre-event limbo safety: no deaths, water rescue, ghost-state refresh

**Covers items:** 7, 8.

**Root cause (verified):**

- *(Item 7)* Before `EclipseWorldState.isStartEventDone()`, players on the ghost ship
  are in survival and fully vulnerable — nothing in `limbo/` or `lives/` grants
  pre-event immunity (`LimboGate` only handles placement). Falling into the sea means
  real drowning damage and a real death through the whole `DeathFlowHooks` pipeline —
  losing a life before the event even started.
- *(Item 8)* `LivesApi.set/add` mutate the permanent heart count but never consult
  `BanService`: a ghost (BANNED attachment) who gains a life stays a ghost. The only
  unban paths are `ReviveRitual`, `FinaleRitual` mass-revive, and `DeathFlowHooks`' own
  unban watch — none of which watch `LivesApi`.

**Exact fix (new `limbo/PreEventSafety.java`, one event owner):**

1. `LivingDamageEvent.Pre` (and `LivingDeathEvent` belt) — cancel for players in
   `LimboDimension.LIMBO` while `!isStartEventDone()`.
2. Water rescue: per-tick scan of limbo players (piggyback the existing
   `PreEventSafety` tick); on `isInWater()` — immediately add invisibility (the "turn
   invisible in water" beat), freeze via `FreezeService` (already grants
   invulnerability + rubber-band lock), send a slow fade-to-black
   (`CaptionRenderer.fade` client entry already exists via `FxPayloads`), then after
   ~40 t `FreezeService.transport` them to `GhostShipBuilder.platformArrivalPos`/deck,
   fade back in, clear invisibility. Works pre- AND post-event in limbo (falling
   overboard during the Ferryman fight already has its own flow — guard with
   `FinaleRitual` arrival/fight-not-running check).
3. *(Item 8)* Post-mutation hook in `LivesApi.set/add`: when a player's hearts go
   0 → >0 and `BanService.isBanned(player)`, call `BanService.unban(player)` (the
   standard revive path — restores survival, team, effects). Offline gains (altar
   deposits for absent ghosts) clear the persistent ban set so
   `ReviveRitual.onPlayerLoggedIn` finishes on next login — mirror
   `FinaleRitual.beginVictory`'s offline branch.

**Files:** `limbo/PreEventSafety.java` (new), `core/state/LivesApi.java` (post-set hook
lines only), `lives/BanService.java` (no signature change — call-sites only if a
helper is needed).

**Effort:** M.

---

## C5 — Intro storm phase: standing push zone, day switch, no free night credit

**Covers item:** 10.

**Root cause (verified):**

- `IntroLightningPhase` applies kickback velocity only on strike ticks — between
  strikes, players can walk arbitrarily deep toward the vortex.
- The intro ends into whatever time-of-day the world happens to have; there is no
  explicit `setDayTime` after the final blast, so the event regularly "starts" at night.
- `QuestDetectors.pollNightWindow` awards the "survive the night without damage" quest
  from natural dawn crossings; a scripted jump to DAY would fire exactly that window and
  hand everyone unearned mission credit.

**Exact fix:**

1. `IntroLightningPhase`: continuous protective zone for the WHOLE phase — every tick,
   players inside radius R of the vortex center get a radial outward velocity ramp
   (stronger the deeper they are; ≤ 1.2 blocks/t at the wall), plus the existing strike
   kickback on top. Server-side only, no payload needed.
2. `IntroSequence` final blast/sunrise phase: explicitly
   `level.setDayTime(dayStart)` (morning, 1000 t) instead of leaving the clock. Set a
   transient static `IntroSequence.scriptedTimeJumpGameTime` marker.
3. `QuestDetectors.pollNightWindow`: invalidate any night window whose dawn crossing
   happened within ±200 t of the scripted jump marker (read-only seam; one guard
   clause) — no "survived the night" credit from the cinematic.

**Files:** `sequence/IntroLightningPhase.java`, `sequence/IntroSequence.java`,
`progression/goals/QuestDetectors.java` (guard clause only).

**Effort:** M.

---

## C6 — Cutscene engine: chunk preload, hidden player, border vignette, FOV audit, day-12 return

**Covers items:** 11, 12, 13, 14, 23 (+ the config-staleness residue of 15).

**Root causes (all verified):**

1. *(Item 11)* `CutsceneService.play` pushes view distance (`ViewDistanceService`) and
   gathers, then starts the camera flight the SAME tick — the client is still receiving
   and meshing chunks, so the flight shows holes and pop-in.
2. *(Item 12)* `CameraDirector.handlePlay` deliberately switches to
   `CameraType.THIRD_PERSON_BACK` ("own body renders in frame"), so the local player
   model sits in every shot.
3. *(Item 13)* `progression/BorderController.applyRing` calls
   `border.lerpSizeBetween(...)` and `setWarningBlocks(0)` but NEVER
   `setWarningTime(0)`. Vanilla's red vignette distance during a lerp is
   `max(warningBlocks, min(lerpSpeed × warningTime, |target − size|))` — with the
   default `warningTime = 15 s` and the intro's huge fast lerp, the red frame covers
   everyone on the map and persists until the lerp completes, i.e. well past the
   cutscene. (`client/mixin/LevelRendererMixin` hides only the border WALL render, not
   the GUI vignette.)
4. *(Item 14)* Per-keyframe FOV is ALREADY fully implemented: `CutscenePath` parses
   `fov`, `CameraDirector.onComputeFov` interpolates and applies it, and the bundled
   `intro_v3_flight.json`/`intro_v3_ship.json` author it. The gap is (a) operator
   copies under `config/eclipse/cutscenes/` from older versions predate the field and
   shadow the bundled defaults (the `CutscenePaths` fingerprint upgrade only replaces
   byte-identical stale defaults), and (b) several bundled paths never author `fov`.
5. *(Item 23)* `CutsceneService.validatedReturnPosition` "heals" return snapshots: if
   `pos.y < heightmapSurface − 2`, the player is snapped UP to the heightmap. Once the
   End disc materializes at Y≈360 (day 12), the MOTION_BLOCKING heightmap of every
   column under the disc reports the DISC surface — so any global cutscene return (the
   day-12 `final_day` stage sweep plays `ExpansionSequence` FLYOVER with
   `PlayOptions.global`) teleports players whose origin lies under the disc onto the
   island instead of back to their base. `gatherSpot` has the same heightmap flaw.

**Exact fix:**

1. Preload stage: after gather + view-distance push, hold behind the existing gather
   fade; server polls the chunks along the sampled keyframe path
   (`level.getChunkSource()` ticket + loaded check) AND waits for a new tiny
   `C2SCutsceneReadyPayload` the client sends when the chunks around the first camera
   position are meshed (`ClientChunkCache` lookup in `ViewDistanceClient`); timeout
   100 t then start regardless. Start the flight only then.
2. `CameraDirector`: new optional path flag `showOwnBody` (default false). When false,
   cancel the local player's render (`RenderPlayerEvent.Pre`, only while a flight is
   active, only for `minecraft.player`). Keep `THIRD_PERSON_BACK` (needed so the head
   doesn't occlude), restore exactly as today.
3. `BorderController.applyRing`: add `border.setWarningTime(0)` beside
   `setWarningBlocks(0)`; for the intro's scripted resize call the `ms <= 0` snap
   branch (the failsafe border is invisible anyway — `LevelRendererMixin`). Result: the
   red vignette can never arm.
4. FOV: extend the `CutscenePaths` stale-default fingerprint list with the current
   pre-fov file hashes so old config copies upgrade in place; author `fov` on
   `expansion_flyover`, `expansion_skyward`, `unlock_ring`, `finale_return`; document
   the field in each JSON's `_doc`.
5. Return healing: replace the blind up-snap with a floating-surface test — walk DOWN
   from the heightmap surface at the return column; if there is ≥ 32 blocks of air
   between the heightmap surface and the snapshot Y, the "surface" is a floating shell
   (End disc, wing decks): keep the original Y when the 2-block collision box at the
   snapshot is free, else find the first safe Y BELOW the shell. Apply the same test in
   `gatherSpot`.
6. *(Item 15 residue)* Ship a fingerprint-list bump so pre-i18n operator cutscene copies
   (caption ids as literal text) upgrade to the bundled key-based defaults; log a WARN
   when a caption event id contains a space (cannot be a lang key).

**Files:** `cutscene/CutsceneService.java`, `cutscene/CutscenePaths.java`,
`cutscene/client/CameraDirector.java`, `cutscene/client/ViewDistanceClient.java`,
`cutscene/CutscenePath.java` (flag field), `progression/BorderController.java`,
`network/` (one new C2S payload + registration line),
`assets/eclipse/cutscenes/*.json` (fov authoring).

**Effort:** L.

---

## C7 — Expansion growth: rift 2.0 (real 3D, adaptive size) + block-display assembly

**Covers item:** 16.

**Root cause (verified):** structures materialize via `StructureStamper`/
`BudgetedBlockWriter` set-block passes — blocks just appear. The rift
(`veilfx/rift/RiftRenderer`) is a camera-facing 2D star polygon; its `a` payload param
already carries a width but nothing derives it from the structure being revealed. The
growth beat has captions + two small shakes (`expansion_flyover.json`) and no lightning,
no flying pieces.

**Exact fix:**

1. **Volumetric rift** (`RiftRenderer` rework): layered 3D tear — an extruded
   star-prism (4–6 depth-stacked, counter-rotating jagged shells with additive violet
   emissive, parallax interior using the existing `rift_glitch` post pipeline) instead
   of one billboard. Size from the payload `a` as today; the SERVER now computes
   `a = max(structure bounding box XZ diagonal × 1.15, 4)` when opening a reveal rift
   (`StructurePendingRegistry` reveal call-site — it knows the pending site bounds).
2. **Flying assembly** (new `worldgen/stage/StructureFlightFx.java`): before the real
   set-block pass, spawn ≤ N (config, default 80) `BLOCK_DISPLAY` entities at the rift
   mouth sampling the structure's most visible blocks (surface-first), arc them along a
   ballistic Bezier to their target cells over 30–60 t using display interpolation
   (`transformation` + `teleport_duration`, the `devtools/display/DisplayAnimator`
   pattern), then despawn each display as `BudgetedBlockWriter` writes the real block
   beneath it (writer callback seam — writer stays owned by its file; the callback is
   registered, not edited in). Restart-safe: displays are tagged and swept on load
   (`OarAnimator.sweepStrayDisplays` pattern).
3. **Beats**: screen shake pulses (`S2CShakePayload` at 0 %, 40 %, 80 % of the flight),
   2–3 scripted `LightningBolt` strikes on the structure footprint rim, sound suite
   (rift groan loop while open, whoosh per launched piece batch, bass thud on landing —
   new `EclipseSounds` events + OGGs via the C19-fixed pipeline).

**Files:** `veilfx/rift/RiftRenderer.java`, `worldgen/stage/StructureFlightFx.java`
(new), `worldgen/structure/StructurePendingRegistry.java` (reveal call-site: size calc +
flight kickoff lines), `registry/EclipseSounds.java` (+ sounds.json entries + OGGs).

**Effort:** L.

---

## C8 — Fog storms: spheres, distinct interior, explode-on-death, better reward

**Covers item:** 17.

**Root cause (verified):** `StormRegistry` knows exactly two shapes — `TYPE_VORTEX`
(intro) and `TYPE_WALL`; `StormWallRenderer` tessellates every wall storm as an opaque
CYLINDER, which is why site storms read as columns. `StormInteriorFx` reuses the intro
vortex's interior treatment (same fog/rain), so the inside is "boring"/samey. Fog
Tyrant death currently just despawns the storm via the registry — no explosion beat —
and the reward is the plain loot table.

**Exact fix:**

1. `TYPE_SPHERE` in `StormRegistry` + `S2CStormStatePayload` (one byte); spawn helper
   `spawnSphere(level, center, radius, rampTicks)`; the Fog-Tyrant site spawner switches
   to it.
2. `StormWallRenderer`: UV-sphere shell tessellation for the new type (two hemispheres,
   rim-lit edge, slow banded rotation); keep cylinders for legacy walls.
3. `StormInteriorFx`: interior VARIANT keyed by storm type — sphere interiors get
   drifting horizontal fog banks, ember-like motes falling UP, heartbeat sub-bass loop
   and muffled exterior audio (distinct from the vortex's rain rings); 2 new ambient
   loops + 3 stingers in `EclipseSounds`.
4. Death beat: `FogTyrantEntity.die()` → `StormRegistry` dissipate call becomes
   `explode`: 15 t white-out flash + expanding shockwave shell (reuse the sphere mesh,
   scale-up + fade), `S2CShakePayload`, thunder + glass-shatter layered sound, THEN
   remove. Reward: guaranteed drop upgrade — a new `FOG_CORE` epic item (registered in
   `EclipseItems`) + storm-scaled shard bonus via the existing reward rails; seam note:
   if PLAN-D's economy packages add a loot config, route the shard number through it.

**Files:** `stormfx/StormRegistry.java`, `stormfx/StormWallRenderer.java`,
`stormfx/StormInteriorFx.java`, `network/S2CStormStatePayload.java`,
`entity/boss/fog/FogTyrantEntity.java` (death call-site), `registry/EclipseItems.java`
(one item), sounds.json + OGGs.

**Effort:** L.

---

## C9 — Ferryman spawn: out of the door, facing the right way

**Covers item:** 18.

**Root cause (verified — two compounding bugs in `FerrymanEntity.summon`):**

1. **Wrong yaw sign.** `ferryman.moveTo(x, deck + 1, z, 90.0F, 0.0F)` with the comment
   "faces the bow (+X)" — but Minecraft yaw 90° faces WEST (−X), i.e. straight INTO the
   sterncastle door. +X (east, the bow) is yaw **−90°**.
2. **Anchor too close to the bulkhead.** `STERN_X = -(HALF_LENGTH - 3) = −16`; the boss
   spawns at x = −15.5, only 1.5 blocks from the bulkhead/door plane at
   `DOOR_X = −17`. The hitbox (1.4 × 3.5) technically clears it, but the kneeling
   GeckoLib model extends well past the hitbox in the facing direction — facing west
   (bug 1), the model embeds visually in the door aperture: "spawns stuck in the door".

**Exact fix:** yaw → `-90.0F`; move the anchor forward:
`STERN_X = -(HALF_LENGTH - 6)` (x = −13, still on the open stern deck, clear of the
x = −12 bench column). Update `tickCrewPhase`'s drift-home anchor (same constant — it
already reuses `STERN_X`) and verify `faceTowards(bow)` there (already correct). Add a
`summon(ServerLevel, Vec3 anchor, float yaw)` overload (anchor-parameterized) — C10
consumes it for the arena; default overload keeps ship behavior.

**Files:** `entity/boss/FerrymanEntity.java` only.

**Effort:** S.

---

## C10 — Ferryman rework: altar dead-door → ship → wait-gate → arena transform + spectator ship

**Covers item:** 19.

**Root cause / current state (verified):** the whole finale happens on the limbo ghost
ship: `FinaleRitual` ships players to the deck, summons the Ferryman at `SUMMON_TICK`
after a fixed arrival timeline (no wait-for-all), the fight arena IS the 39×9 deck, and
dead players fall back into the regular ghost flow (`DeathFlowHooks`) with no dedicated
vantage. Nothing transforms; there is no separate fight dimension.

**Exact fix (new `ferryman/` server package + one datapack dimension):**

1. **Altar dead-door**: stamp a `RespawnDoorApi`-style door multiblock at the altar at
   finale arm time (the door registry/multiblock code is reused via its API, not
   edited); walking through (interaction volume, `XboxPortal` pattern) teleports the
   player to the ship deck behind a `PortalTransitionController` fade.
2. **Wait-for-all gate**: replace the fixed `SUMMON_TICK` with a gate — the arrival
   timeline holds until every non-ghost online player stands on the deck (bounding box
   check) OR a 90 s timeout; 10 s countdown captions, then the fight arms.
3. **Arena transform**: new void dimension `eclipse:ferryman_arena`
   (`MinigameDimensions` pattern). On fight start: 60 t transformation beat on the ship
   (deck planks lift as `BLOCK_DISPLAY` pieces spiraling upward + shake + white-out —
   the C7 flight animator pattern), then all fighters are transported
   (`FreezeService.transport`) to the arena: a pre-stamped giant ship-turned-arena
   (deterministic builder, `GhostShipBuilder` idempotence law — deck ~96×40, mast
   pillars, lantern ring for the crew phase). Ferryman summons there via C9's
   anchor-parameterized `summon` overload.
4. **Spectator ship**: a small stamped vessel 60 blocks abeam in the same dimension;
   `DeathFlowHooks`' ghost respawn seam gains one branch: while the arena fight runs,
   banned/dead players respawn on the spectator deck (invulnerable, no interference)
   instead of the limbo ship door.
5. **Victory/wipe**: victory keeps `FinaleRitual.beginVictory` (mass revive) but the
   trip home leaves from the arena; wipe path unchanged. Restart mid-fight: skip to end
   state (fight re-arms from the gate, never mid-transform).

**Files:** `ferryman/ArenaDimension.java`, `ferryman/ArenaBuilder.java`,
`ferryman/ArenaFight.java`, `ferryman/AltarDoor.java` (all new),
`data/eclipse/dimension/ferryman_arena.json` (new), `ritual/FinaleRitual.java` (gate +
handoffs; ALSO executes C15's one-line credits hook — see C15),
`lives/DeathFlowHooks.java` (spectator respawn branch only).

**Effort:** L. **DEPENDS-ON:** C9 (summon overload).

---

## C11 — Wizard-mountain sky launcher to the End disc

**Covers item:** 20.

**Root cause / current state (verified):** the End disc surface hangs at Y≈360
(`EndDiscGeometry.END_DISC_SURFACE_Y`); the wizard mountain (highest authored peak,
`WizardObservatory` on the summit, peak ≈ Y 280) has no way up — players currently need
scaffold towers/pearls. No launcher structure or mechanic exists anywhere in
`worldgen/structure/`.

**Exact fix (new pending-site structure + launch logic):**

1. `worldgen/structure/SkyLauncher.java` — a small "wind altar" ring (8×8; sculk-vein
   accents, amethyst spire, four chain pylons) stamped on a terraced shelf just below
   the observatory summit via `StructurePendingRegistry` (site id
   `eclipse:sky_launcher`), enqueued by the same stage listener window as the End disc
   (`final_day` trigger) so it appears WITH the island.
2. Launch: an `interaction` entity on the pad; on use — 15 t charge-up (particles +
   rising tone), then apply a computed ballistic velocity toward
   `EndConfig.centerX/centerZ` at disc height (solve the arc server-side from the
   pad→rim vector; cap horizontal speed, guarantee apex ≥ surface + 8), grant
   Slow Falling (45 s) + a no-fall-damage window via `TimedBuffApi`, wind-charge sound +
   camera shake. A return pad on the disc rim mirrors the trip down (slow-fall only).
3. Safety: landing check — if a launched player would overshoot (leaves the disc
   footprint at apex descent), nudge velocity mid-flight once (server tick watch, tag
   on launch, removed on landing).

**Files:** `worldgen/structure/SkyLauncher.java` (new), registration call-lines in the
pending-registry bootstrap it already exposes, sounds.json entry.

**Effort:** M.

---

## C12 — End disc biome: no more snow on the island

**Covers item:** 22.

**Root cause (verified in `worldgen/DiscBiomeSource.getNoiseBiome`):** the
`minecraft:the_end` biome is returned only for columns where
`EndDiscGeometry.footprintContains(x, z)` AND `y > END_BIOME_MIN_Y (320)`. Everything
outside the exact footprint at that height keeps the surface biome of the terrain far
below — including snowy/cold biomes. Vanilla precipitation gets colder with altitude,
so at Y≈360 the neighboring columns snow, and biome-quart blending (4×4×4 grid) plus
edge columns let snowfall render visibly over the disc rim: "snow falls on the End
disc".

**Exact fix:** drop the footprint check in the upper band — return the End holder for
EVERY column with `y > END_BIOME_MIN_Y` (quart Y > 80). Nothing else legitimately
occupies that band (the wizard mountain tops out ≈ 280; `END_BIOME_MIN_Y = 320`), so
the whole sky layer above 320 becomes `the_end`: no precipitation, no snow
accumulation, correct sky/fog tint on the island, zero effect on ground biomes.
Belt: assert in a comment + gametest that no authored terrain exceeds Y 320 outside the
disc (`DiscTerrainFunction` max).

**Files:** `worldgen/DiscBiomeSource.java`, gametest
`gametest/worldgen/EndBiomeBandTest.java` (new).

**Effort:** S.

---

## C13 — Dragon victory: the island shatters into floating End islets

**Covers item:** 21.

**Root cause / current state (verified):** `EclipseDragonFight` fires
`Listener.onDragonVictory(server, center)` after rewards/portal placement — the seam
exists and nothing subscribes for terrain drama. The disc stays a monolithic pancake
after the kill; no end cities/shulkers exist on it.

**Exact fix (new `worldgen/end/EndShatterSequence.java`, registered via
`EclipseDragonFight.addListener` at bootstrap — call-site line only):**

1. **Beat 0 (victory +40 t)**: global cutscene (`CutsceneService.play`, global gather
   with C6's preload; new `end_shatter.json` orbit path) + shake + bass rumble.
2. **Shatter**: deterministic crack pattern (seed-hashed, `DiscMapData.ECLIPSE_SEED`
   law) divides the disc into 6–9 islets; the seams (3–5 block wide channels) are
   removed via `BudgetedBlockWriter` (async-budgeted, exactly like materialization but
   subtractive); each islet gets a vertical offset (−12…+16) applied as a budgeted
   copy-then-clear translation, so the result is REAL floating islands. Debris:
   ≤ 120 `BLOCK_DISPLAY` chunks tumbling into the void (C7 animator pattern, tagged +
   swept).
3. **End structures**: stamp 2 mini end-city towers (hand-authored deterministic
   builders with real loot + 4–6 shulkers) and 1 end-ship silhouette on the three
   largest islets, enqueued through `StructurePendingRegistry` so they get rift
   reveals.
4. **Player safety**: at shatter start, EVERY player in the overworld above Y 300 gets
   Slow Falling and a 120 s no-fall-damage grace (`TimedBuffApi` timed buff +
   one `LivingDamageEvent` guard keyed on the buff), announced with a caption.
5. Veil/sound: violet fracture-glow along the crack seams for 60 s
   (`S2CFxEventPayload` reuse), layered crack/boom/debris sounds.
   Restart mid-shatter: SavedData cursor (materialization pattern) resumes the
   subtractive pass; the cinematic never resumes.

**Files:** `worldgen/end/EndShatterSequence.java` (new), `worldgen/end/EndCityKit.java`
(new builders), `assets/eclipse/cutscenes/end_shatter.json` (new),
`worldgen/end/EclipseDragonFight.java` (ONE `addListener` bootstrap line),
sounds.json + OGGs.

**Effort:** L. **DEPENDS-ON:** C6 (preload for the cutscene), C19 (sound pipeline).

---

## C14 — Adaptive day texts: day 13 must not demand a dead dragon

**Covers item:** 24.

**Root cause (verified):** day titles/subtitles are static literals from
`EclipseConfig.defaultDays()` (`days.json`): day 13 always announces
"DAY 13 — THE DRAGON / Bring the dragon down and claim the egg" via
`TimelineService.dayTitleKey` → `AnnouncementService`, regardless of
`EndFightState.dragonKilled()` (the persisted victory flag `EclipseDragonFight`
maintains). No conditional text path exists anywhere in the day pipeline.

**Exact fix:**

1. `EclipseConfig.DayPlan`: optional `titleDone`/`subtitleDone` (+ localized variants)
   fields, parsed backward-compatibly (absent = never swap). Author day 13's done-texts
   ("DAY 13 — THE SILENT SKY / The dragon has fallen. Rest — tomorrow the ship sails.")
   and day 12's (stronghold already breached) in `defaultDays()`.
2. `TimelineService.dayTitleKey(day[, player])`: new server-truth predicate parameter —
   a tiny `DayTextConditions` helper mapping day → "done" check (13 →
   `EndFightState.get(server).dragonKilled()`, 12 → stronghold breached flag if
   available, else never). Returns the done-variant when the predicate holds at
   announcement/timeline build time. `AnnouncementService` call-sites pass the server
   through (signature already has it via the player).
3. Goals list stays as-is (quest completion already ticks them); only title/subtitle
   swap.

**Files:** `timeline/TimelineService.java`, `timeline/DayTextConditions.java` (new),
`core/config/EclipseConfig.java` (DayPlan fields + defaults), langdrop lines.

**Effort:** S/M.

---

## C15 — Final credits sequence (day 14, post-Ferryman) + client close

**Covers item:** 25.

**Root cause / current state (verified):** after the Ferryman dies,
`FinaleRitual.beginVictory` revives ghosts, `bringEveryoneHome` ships players to the
overworld spawn and plays the `finale_return` descent — then normal play resumes. No
credits, no title cards, no client close. A `CreditsScreen` already exists
(`MusicClientHooks.openCredits` opens it) and `victory_theme` is already cued. The full
shot-list design (timings, auto-run, `Minecraft.stop()`, failure-safety) is already
authored in `docs/plans_v3/plans_v5/IDEAS-backrooms_finale.md` §B — this package
implements it.

**Exact fix (implement IDEAS §B1–B7; new `ritual/CreditsSequence.java` +
client pieces):**

1. Hook: C10's `FinaleRitual` (file owner) replaces the `bringEveryoneHome` →
   `finale_return` play with ONE line: `CreditsSequence.begin(server)` (spec here,
   executed by C10's worker; everything else lives in new files).
2. Beats (server timeline, IDEAS §B1): fade-to-black → helm shot (short authored
   cutscene `credits_helm.json`, player-anchored on the ship's wheel) → fade WHITE →
   hidden white loading hold (client: `PortalTransitionController` white variant) →
   scene swap to the overworld sunrise field → **auto-run** (IDEAS §B2: client input
   injection with server nudge fallback) → huge lightning + `BLOCK_DISPLAY` flyby
   (C7 animator pattern) → title card 1 "MINECRAFT ECLIPSE COMES BACK IN AVENGERS:
   DOOMSDAY" → burst → title card 2 "ECLIPSE: DOOMSDAY" → fade black → 10–15 s music
   finale (new `credits_finale` non-looping cue) → **client close**.
3. Client close (IDEAS §B3): new `S2CClientClosePayload`; handler schedules
   `Minecraft.getInstance().stop()` 20 t after the fade completes; singleplayer/LAN
   guard (save + quit to title instead of hard stop for the host), dedicated server
   broadcasts then stays up.
4. Title cards: new full-screen card layer (NOT captions — cards need custom typography
   /burst FX), registered above the letterbox like `CaptionRenderer`.
5. Failure-safety (IDEAS §B5): every beat has a watchdog; a disconnect/restart lands the
   player in the post-credits world state (event over flag in `EclipseWorldState`), the
   sequence never replays.

**Files:** `ritual/CreditsSequence.java` (new), `client/credits/TitleCardLayer.java`
(new), `network/S2CClientClosePayload.java` (new + registration line),
`assets/eclipse/cutscenes/credits_helm.json` (new), `music/` cue addition
(`credits_finale` — coordinate with C19's file ownership: C19 lands first, C15 adds the
enum/sounds.json/OGG lines), langdrop.

**Effort:** L. **DEPENDS-ON:** C10 (hook line), C19 (music pipeline), C6 (preload).

---

## C16 — Portal build: frameless star-rift + better Veil portal effect

**Covers item:** 26 (portal build + FX halves; the announcement text half is C17's,
which owns `XboxEventService`).

**Root cause (verified):** `XboxPortal.place` builds a decorative block-display FRAME
from classic blocks around the 3×4 interaction volume — the user wants NO frame, just
the star/rift. The portal's Veil visual is the generic `fx/rift_open` payload
(style 1) rendered by the 2D `RiftRenderer` billboard, with a plain reverse-portal
particle column fallback.

**Exact fix:**

1. Remove the frame: `place` spawns ONLY the interaction volume + the rift FX payload
   (keep the tag sweep for legacy frames so existing worlds clean up).
2. Better portal effect: consume C7's volumetric rift (style 1 = portal gets the
   layered star-prism with a lensed interior — a cheap cubemap-ish inner quad sampling
   the destination's sky tint), plus idle audio loop and slow rotation; particle column
   fallback stays for Iris/reducedFx.
3. Portal width already flows through payload `a` — author 5.0 as today.

**Files:** `xboxevent/XboxPortal.java` only (rift internals are C7's renderer).

**Effort:** S/M. **DEPENDS-ON:** C7 (volumetric rift).

---

## C17 — Tutorial worlds: generic announcement, one timer, era immersion, more TUs

**Covers items:** 26 (announcement half), 28 (minus the D2/A7-owned sub-points).

**Root cause / current state (verified):**

- `XboxEventService` announces `eclipse.xbox.announce.start` WITH the world name
  (datamine-y detail; user wants ONLY "ein Portal hat sich geöffnet").
- The 30:00 timer is a `ServerBossEvent` bossbar — one more bar in an already crowded
  stack (A7's complaint); an `S2CXboxTimerPayload` ALREADY exists and is sent —
  the client HUD side just needs to be the only surface.
- Classic items spill only into CHESTS (`ClassicChestLoot`); no item frames.
- No era color-filter shader or UI skin exists for the xbox dimensions (no
  xbox/classic pipeline under `assets/eclipse/pinwheel/`).
- Old music: `XboxMusicHook`/`MusicManager` already cue `xbox_nostalgia` (C19 makes it
  actually play); no old SOUND effects swap exists.
- Quest goal progress is not dimension-gated (XP is — PLAN-D D2).
- Manifest ships `tu1`, `tu12`, `tu14` only; the user wants TU19 + TU31 + TU69
  (TU69 does not exist — the last Xbox 360 title update is TU75; plan the nearest real:
  TU19, TU31, TU75).
- "Leave-command untranslated": all 7 `eclipse.xbox.leave.*` keys exist in BOTH lang
  files — the strings show untranslated because of PLAN-A A1's dead locale merge and
  missing `eclipse.xbox.` prefix (A1 fixes; C17 only re-verifies after A1 lands).

**Exact fix:**

1. Announcement: `eclipse.xbox.announce.start` args drop the world name — new copy
   "Ein Portal hat sich geöffnet." / "A portal has opened." (no world, no timer in the
   start line); the detail lines move to the INSIDE-only welcome title.
2. Timer: delete the `ServerBossEvent` (keep `S2CXboxTimerPayload` as the single
   source); seam to A7: the client timer strip renders it in the day-timer slot while
   inside (spec handed to A7's owner — one layer branch).
3. Item frames: `XboxWorldInstaller` post-install pass places item frames from a new
   optional `frames` section in `<id>_loot.json` (pos + facing + classic item id),
   populated by the packaging tool.
4. Era color filter + UI skin: new `pinwheel/post/xbox_era.json` (subtle desaturation,
   lifted blacks, slight yellow-green LUT — console-era look) enabled by dimension
   check client-side; UI skin: while in an xbox dimension, swap the HUD theme accents
   to the classic gray (theme hook, not per-widget edits). Respect `reducedFx`.
5. Old sounds: a dimension-scoped sound REPLACEMENT map (client): remap new-school
   event sounds (modern step/place variants) to legacy-style equivalents where a
   vanilla legacy sound still exists; old-music side is just the (C19-fixed)
   `xbox_nostalgia` cue.
6. Quests: `progression` seam — quest goal detectors skip progress while
   `XboxDimensions.isXboxDimension` (mirror of D2's XP gate; one guard in the detector
   poll, coordinated so D2 lands first).
7. Legacy texture verification (authentic pipeline): the classic blocks/items must be
   1:1 era-correct — plan: pull candidate "legacy" packs from Modrinth (research task:
   verify license allows redistribution; prefer CC0/ARR-with-permission), diff against
   `classicblocks` textures, and document provenance per texture in
   `docs/plans_v3/xbox_texture_provenance.md`. Water/lava/redstone functionality is
   untouched by textures (behavior never modified) — add a gametest that flowing water,
   lava and a redstone clock work in an installed TU world.
8. New worlds: package TU19, TU31, TU75 zips via `tools/xboxworlds/package.py`
   (manifest entries + loot bakes + spawn/yaw), register dimensions in
   `XboxDimensions`.

**Files:** `xboxevent/XboxEventService.java`, `xboxevent/XboxWorldInstaller.java`,
`xboxevent/XboxDimensions.java`, `xboxevent/XboxWorldsManifest.java` (frames schema),
`assets/eclipse/pinwheel/post/xbox_era.json` (new) + client toggle class (new,
`client/xbox/XboxEraFx.java`), `tools/xboxworlds/package.py`, manifest + zips + loot
JSONs, one guard in `progression/goals/` detector poll (coordinate with C5's
`QuestDetectors` ownership — C5 lands first, C17 rebases; the two guards are disjoint
methods), gametest.

**Effort:** L. **DEPENDS-ON:** A1 (i18n), A7 (timer HUD slot), D2 (XP gate), C19
(music), C5 (QuestDetectors merge order).

---

## C18 — Backrooms event dimension (+ portal roadmap)

**Covers item:** 27.

**Root cause / current state:** no backrooms code exists. The complete design is
already authored in `docs/plans_v3/plans_v5/IDEAS-backrooms_finale.md` §A (maze
generation with per-instance seed law, buzz/flicker ambience, two reused horror mobs,
ONE photosensitivity-capped mini-jumpscare, xbox-style safe-return rules, loot + exit
rules, ranked ambience details) — grounded in the same code readings this plan used.
This package implements IDEAS §A1–A6 verbatim; deviations require an orchestrator note.

**Implementation outline (see IDEAS §A for full detail):**

1. `eclipse:backrooms` void dimension (datapack JSON + `BackroomsDimension` key class;
   `fixed_time` midnight, no skylight, height 32).
2. Finite stamped maze at event start (24×24 cells of 8×8, bond-percolation edge
   opening at 58 %, froglight panel lighting with flicker), `StructureStamper`-style
   idempotent pass, re-stampable from the persisted instance seed.
3. Event lifecycle mirrors `XboxEventService` (ANNOUNCED → OPEN → CLOSING, SavedData,
   crash resume, protected deaths, `TimedBuffApi` reward, `/backroomsleave` per the
   xbox leave pattern) — shared via a new `eventdim/EventDimensionTemplate` base class
   extracted WITHOUT touching the xbox files (template-method wrapper; xbox migrates
   later).
4. Mobs + jumpscare: `GlitchedHuskEntity` re-skin + `TheOtherEntity` cameo
   (IDEAS §A3/§A4; jumpscare ≤ 1 per instance, flash-capped, `reducedFx` disables).
5. Portal: frameless star-rift (C16's build) with a yellow-tinted style variant.
6. **More unique portals later**: the template class + the portal style byte are the
   extension points — document a 1-page recipe (`docs/plans_v3/plans_v5/PORTAL_RECIPE.md`)
   for future one-off event dimensions (dim JSON + template subclass + portal style).

**Files:** new `backrooms/` package (~6 classes), `data/eclipse/dimension/backrooms.json`,
`eventdim/EventDimensionTemplate.java` (new), portal style byte in C16's payload path
(one constant — coordinate), langdrop, sounds.

**Effort:** L. **DEPENDS-ON:** C16 (portal), C19 (ambience audio pipeline).

---

## C19 — MUSIC: why the generated score NEVER plays (critical)

**Covers item:** 29.

**Root cause — three independent, verified defects; the first alone silences
EVERYTHING:**

1. **Every cue is skipped at start (code).** `MusicManager.CueSound` begins its
   crossfade at `volume = 0.0F` (constructor) and does NOT override
   `SoundInstance.canStartSilent()` (defaults to `false`). Vanilla
   `SoundEngine.play` computes the initial effective volume, gets `0.0`, and **refuses
   to start the sound** (debug log: "skipped playing sound …, volume was zero"). The
   manager then believes a cue is playing (`current != null`), keeps calling
   `minecraft.getMusicManager().stopPlaying()` every tick — so vanilla music is ALSO
   suppressed: total silence, exactly as reported. (`cleanupFinished` even removes the
   never-started instance after 10 ticks via `isActive`, after which `transitionTo`
   re-creates it and the cycle repeats.)
2. **Corrupt generated assets.** Verified with ffprobe:
   `day_final.ogg` is an **Ogg THEORA video** container (undecodable as a sound);
   `boss_ferryman/boss_herald/limbo_ambience/title_theme/wand_awakening/xbox_nostalgia
   .ogg` are Vorbis at **192,000 Hz** with corrupt bitrate headers (~4294967294 bps) —
   raw generation-API downloads. Only the older 44.1 kHz files
   (`intro_storm`, `expansion_theme`, `victory_theme`, `eclipse_totality`,
   `kill_contract`, `boss_rift_warden`) are healthy.
3. **The tool's postprocess step never existed.** `tools/music/treblo_generate.py`'s
   docstring promises "Minecraft-ready OGG Vorbis happens in postprocess() (loudnorm +
   size budget)" — there is no `postprocess()` in the file; `<id>_raw.ogg` API payloads
   were copied into `assets/eclipse/sounds/music/` verbatim.

Registration/wiring is NOT the problem (verified end-to-end): `EclipseMusicSounds`
event ids match `sounds.json` keys (`music.<id>` → `eclipse:music/<id>` streamed),
all 13 OGG files exist at the right paths, `MusicConfig` defaults to enabled at 0.85,
and the payload→`MusicCues.play`→`MusicClientHooks`→`MusicManager` chain is sound.

**Exact fix:**

1. `CueSound`: `@Override public boolean canStartSilent() { return true; }` — the
   one-line critical fix. (Vanilla's own fading sounds, e.g. biome ambience, do exactly
   this.)
2. Re-encode all six 192 kHz tracks and demux/re-encode `day_final.ogg`
   (`ffmpeg -i in.ogg -vn -c:a libvorbis -q:a 4 -ar 44100 out.ogg`); target ≤ 2.5 MB
   per track (stream=true keeps memory flat).
3. Add the missing `postprocess()` to `treblo_generate.py`: loudnorm (-16 LUFS), 44.1 kHz
   stereo Vorbis re-encode, strip non-audio streams, size budget check — run
   automatically after download so raw files can never ship again.
4. Guard: a gametest/CI check that every `music.*` sounds.json entry resolves to a
   pure-Vorbis, ≤ 48 kHz OGG (tiny header parse — no decode needed).
5. Verify the boss-cue path end-to-end in-game after the fix (bossbar-name observation
   in `MusicManager.onBossbar` depends on the bossbar rendering — the existing
   `BOSS_SEEN_GRACE_MILLIS` handles letterbox gaps; no change expected).

**Files:** `music/MusicManager.java` (one override), `assets/eclipse/sounds/music/*.ogg`
(7 re-encodes), `tools/music/treblo_generate.py`, gametest
`gametest/music/MusicAssetValidationTest.java` (new).

**Effort:** M (mostly asset re-encode + tool).

---

## Merge-order notes

1. **C19 first** (unblocks every audio-bearing package: C7, C8, C11, C13, C15, C17, C18).
2. **C6 second** (cutscene engine used by C13, C15; contains the day-12 return fix that
   should land BEFORE the next final-day window).
3. C9 → C10 → C15 (ferryman chain); C7 → C16 → C18 (rift chain); C5 → C17
   (QuestDetectors file order); A1/A7/D2 land independently on their planners' schedule.
