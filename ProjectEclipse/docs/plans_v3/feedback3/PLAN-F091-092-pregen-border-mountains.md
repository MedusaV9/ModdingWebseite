# PLAN F-091 + F-092 — Full-map pregeneration & giant border mountains

Feedback (UserFeedback.md):

- **F-091** — "Warum generierst du nicht einmal die Map vor? und lädst die dann einfach immer?" — build a
  `/dev preload everything` command that generates the WHOLE map once, then unloads it, so afterwards chunks
  only ever LOAD from disk (fast, no visible raw generation — including during the start event). Bonus: with
  every chunk pre-existing, the expansion can be animated much more deliberately.
- **F-092** — "Am Rand die Felsen sind nicht groß genug — sie sollen einmal wie riesige Berge sich auftürmen
  am Rand, die Map quasi einkreisen, von der ganzen Map aus sehbar sein und beim Erweitern langsam
  zurückweichen." — the border rocks must become GIANT mountains that encircle the whole map, are visible
  from anywhere on the disc, and slowly recede outward on each expansion day.

Status: PLANNED (this document). No code has been changed yet.

---

## 1. Current-state map (audit)

### 1.1 Disc creation & radii

| Concern | Where | Facts |
|---|---|---|
| Base terrain function | `worldgen/DiscTerrainFunction.java` | Pure function of (profile, x, y, z, stage). Owns silhouette, rim taper (`RIM_WIDTH` 12 + `RIM_NOISE_AMP` 8, `RIM_REWRITE_MARGIN` 24), underside, strata, rivers, moat, mountain, caves, breach, End disc. Interior output is stage-independent (lens normalised against `DiscProfile.lensNormRadius()` = 480). |
| Chunk generator | `worldgen/DiscChunkGenerator.java` | `eclipse:disc` — evaluates the terrain function at the CURRENT COMMITTED STAGE (via `WorldStageAccess`), then runs the real vanilla pipeline (`worldgen/vanilla/DiscGenPipeline`: carvers → placed features under the frozen map seed → animal seeding). |
| Biomes | `worldgen/DiscBiomeSource.java`, `DiscMapDefaults.java` | Position-only, stage-free — biomes bake correctly into a chunk no matter WHEN it generates. This makes early pregeneration safe. |
| Stage radii | `worldgen/FrozenParams.java`, `StageRadii`, `run/config/eclipse/stages.json` | Frozen per save. Overworld `{96, 150, 210, 280, 360, 440}` (stage 0 = main disc r96 + eight r24 player discs on the r170 ring, `DiscGeometry`). Nether `{0, 150, 280, 440}`. **Final overworld radius = 440**; detached rim shards/crumble reach `radius + RIM_NOISE_AMP` (448); mushroom shards sit just off the final rim; lens shape normalises to 480. |
| Stage triggers | `stages.json` + `progression/DayScheduler` + `timeline`/milestones | overworld: 1=`intro_fusion` (150), 2=`milestone:2` (210), 3=`milestone:3` (280), 4=`milestone:4` (360), 5=`final_day` (440). nether: 1=`day:2` (150), 2=`day:10` (280), 3=`day:12` (440). |

### 1.2 Expansion step

- `worldgen/stage/WorldStageService.setStage` — the single commit choke point: persist stage → publish to
  chunkgen seam → `S2CStagePayload` → kick `RingGrowthService`.
- `worldgen/stage/RingGrowthService` — tick-budgeted sweep that REWRITES the annulus between old and new
  radius in already-generated chunks (byte-identical to chunkgen, full pipeline replay per finished chunk).
  Key fact for F-091: **never-generated chunks are SKIPPED** — "chunkgen covers them at the committed
  stage", i.e. they generate raw, on demand, when a player first walks/flies near. That lazy generation is
  exactly the visible "reingenerieren" the user reports. Generated-but-unloaded chunks are found via async
  region reads and loaded at `ExpansionTiming.SWEEP_CHUNK_LOADS_PER_TICK` = 4/tick. Cursor persists via
  `EclipseWorldState.setGrowthCursor` every 100 columns → sweeps resume across restarts.
- `sequence/ExpansionSequence` — SKYWARD → FLYOVER → GROWTH → STRUCTURES → END cinematic around the sweep;
  `worldgen/stage/ChunkPreload` only warms a 3×3 chunk square at teleport destinations (NOT a map pregen).
- `border/SoftBorder` — server-authoritative circular soft border per disc dimension, radius =
  `stageOuterRadius + borderOffset` (12). Vanilla world border is only a hidden failsafe at ring+48
  (`progression/BorderController`, render cancelled by `client/mixin/LevelRendererMixin`). Client ring
  radius is synced + client-lerped: `S2CBorderPayload` → `client/ClientStateCache.currentBorderRadius`
  (area-proportional lerp over `ExpansionTiming.BORDER_GROWTH_LERP_TICKS` = 500).
- View distance (`run/server.properties`): `view-distance=12` (192 blocks), `simulation-distance=10`.

### 1.3 The existing border rocks (what F-092 says is too small)

`worldgen/stage/ExpansionBorderFx.java` — the "chunk-gated border expansion spectacle":

- 12 `BLOCK_DISPLAY` multi-slab monoliths, **4–8 blocks tall** (`HEIGHT_MIN`/`HEIGHT_MAX`), raised ~6 blocks
  inside the rim when a growth gate arms, quaking while the sweep runs, sinking on release. Transient only —
  they exist for the minutes of one expansion.
- Hard physical limits (documented in the class): a BlockDisplay's entity tracking range is 10 chunks
  (160 blocks) — nobody further away is ever SENT the entity; `view_range` 8 (=512 blocks) only helps within
  that horizon. So this approach can never satisfy "von der ganzen Map aus sehbar" on a disc up to r=440
  (opposite rim = 880 blocks away).
- There is no persistent rim rock/mountain terrain today: `DiscTerrainFunction`'s rim band is a 12-block
  smoothstep TAPER DOWN to a crumbly knife edge — the map edge currently reads as a cliff-down, not a wall-up.

### 1.4 Relevant client/FX infrastructure

- `client/sky/OverworldPurpleEffects` — full custom `DimensionSpecialEffects` sky (purple sun, coronas,
  star field, day escalation). Registered for the overworld; Iris shaderpack active → returns `false`
  and vanilla/shaderpack owns the sky. **This is the natural hook for a far-field silhouette layer.**
- `client/ClientStateCache` — already caches committed stage radii + the animated border ring radius per
  dimension. No new payload is needed for the silhouette to know where the rim is.
- Veil 4.3.0 is a required jar-in-jar dependency (`veilfx/VeilPostController` post pipelines, Quasar);
  Photon is an optional reflection bridge (`veilfx/PhotonBridge`) with row registrars
  (`veilfx/WorldEventPhotonFxRows` pattern) and `network/fx/FxCues` cue rows.
- Dev command conventions: self-registering `literal("dev")` trees (Brigadier merges), docs via
  `devtools/dev/DevCommandRegistry` + `DevCommandDoc` (see `DevStageCommands`), permission gate
  `DevRoot::canUseDev` / `hasPermission(2..3)`.
- SavedData conventions: `core/state/EclipseSavedData.getOverworld` helper, e.g. `start/StartState`
  (`eclipse_start_assign.dat`); `EclipseWorldState` persists the growth cursor.
- Bossbar precedent: `ServerBossEvent` used in `minigames/MinigameService`, `xboxevent/XboxEventService`,
  boss fights.

---

## 2. F-091 — `/dev preload everything` (full-map pregeneration)

### 2.1 Scope decision

Pregenerate to the FINAL frozen radius, not the current stage:

| Dimension | Pregen radius (blocks) | Chunk radius | ~Chunks (disc) | Rationale |
|---|---|---|---|---|
| Overworld | **480** | 30 | ~3,000 | final stage 440 + rim noise 8 + border offset 12 + failsafe/mushroom-shard margin; 480 = `lensNormRadius`, safely covers everything that can ever be solid. |
| Nether | **480** | 30 | ~3,000 | final nether stage 440 (IDEA-17 1:1 disc); includes the breach arrival region (85,85) trivially. |
| Limbo / backrooms / arenas / xbox worlds | — | — | — | OUT of default scope: small, event-local, force-loaded or built at runtime; `/dev preload dimension <dim> <radius>` is an optional extension, not part of "everything". |

Total ≈ 6,000 chunks. Chunks pregenerated at an EARLY stage are still correct later: biomes are position-only
(§1.1), and beyond the committed radius the terrain function emits void — when the stage later commits,
`RingGrowthService` rewrites those (now generated) chunks through its normal animated sweep + pipeline replay,
byte-identical to fresh chunkgen. **Consequence: after pregen, expansions never show raw chunkgen — every new
chunk appears through the paced, reveal-delayed sweep animation. This is precisely the F-091 ask.**

Trade-off to accept (and tune): the sweep can no longer "skip never-generated chunks", so late-stage sweeps
rewrite the full annulus (stage 4→5 ≈ 1,050 chunks). At 4 disk loads/tick + 8 finishes/tick this stretches the
sweep past the 500-tick pacing target; either accept longer final expansions (they are the spectacle anyway) or
raise `SWEEP_CHUNK_LOADS_PER_TICK` for post-pregen worlds (knob exists in `ExpansionTiming`/`GrowthPacing`).

### 2.2 New classes

All server-side, package `dev.projecteclipse.eclipse.worldgen.pregen`:

- **`MapPregenService`** — the tick-driven pregen engine (mirrors `RingGrowthService`'s job shape:
  `@EventBusSubscriber`, one job per dimension, `ServerTickEvent.Post`, `ServerStoppingEvent` persistence).
- **`PregenState`** — `SavedData` (`eclipse_pregen.dat` via `EclipseSavedData.getOverworld`), stores per
  dimension: target radius, spiral cursor index, chunksDone, done flag, and a `generatorFingerprint`
  (mapSeed + frozen radii hash) so a refrozen/re-authored save invalidates stale progress.
- **`DevPreloadCommands`** — self-registering `literal("dev")` tree + `DevCommandRegistry` docs.

### 2.3 Generation algorithm (per dimension job)

1. **Order**: concentric chunk rings from the origin outward (deterministic ring-then-angle order like the
   GROW sweep — resumable by a single long cursor, and the playable center is served first).
2. **Batching**: each tick, top up an in-flight window of chunk requests:
   - `maxInFlight` default **12** concurrent chunk targets, issue at most `issuesPerTick` (default 4) new ones
     per tick.
   - Primary mechanism: `serverLevel.getChunkSource().getChunkFuture(cx, cz, ChunkStatus.FULL, true)` on the
     server thread; completion (whenever the worker/main-thread pipeline finishes) counts the chunk done and
     releases the slot. Fallback if the future API proves awkward: the proven codebase pattern — a self-expiring
     `TicketType` (`TicketType.create("eclipse_pregen", …, ttl)`) + `addRegionTicket(pos, 0)` and a
     `getChunkNow != null` poll (the `ChunkPreload`/`ExpansionBorderFx` pattern).
   - **Skip already-generated chunks** cheaply: reuse `RingGrowthService`'s async region-read probe (stored
     status ≥ `minecraft:noise` → count as done without loading). On a fresh setup world this is a no-op; on a
     half-explored world it makes `/dev preload everything` re-entrant and fast.
3. **MSPT guard**: identical doctrine to the sweep — issue nothing while the server is above 40 ms/tick, so
   pregen can never become a TPS cliff while players are on.
4. **Memory safety**: no persistent tickets are held — the request ticket expires on its own, the distance
   manager unloads each chunk shortly after promotion, and the unload path saves it to region files. The
   in-flight cap (12) bounds simultaneous full chunks; ~6,000 chunks never coexist in memory.
5. **Resume**: cursor + counters persist in `PregenState` every 64 completed chunks and on
   `ServerStoppingEvent`. On `ServerStartedEvent`, an unfinished job with a matching fingerprint resumes
   automatically (log line, ops bossbar reappears).
6. **Progress + ETA**:
   - `ServerBossEvent` visible to operators (and optionally all players pre-event): name
     `Pregen overworld 42% (1,260/3,010) — ETA 2:41`, progress = done/total.
   - Action bar to the issuing player every 40 ticks; chat milestone lines every 10%.
   - ETA from an exponential moving average of chunks/sec over the last ~30 s (rate is bursty: interior
     ocean-of-void chunks are cheap, forested rim chunks are not).
7. **Completion / automatic unload**: when the cursor exhausts:
   - stop issuing, wait for in-flight to drain,
   - one `server.saveEverything(true, true, false)`-style flush (suppress logs, flush to disk) so the whole
     map is durably on disk before the event,
   - log + bossbar "done" for 200 ticks, then remove; `PregenState.done = true`.
   - No explicit "unload" pass is needed (nothing holds tickets), but `/dev preload unload` (§2.5) exists as
     a belt-and-braces manual flush+verify.

### 2.4 Automatic trigger (start event never shows raw generation)

- New `pregen` block in `worldgen_tuning.json` (`GrowthPacing` owns the file; bump `CONFIG_VERSION`):
  `{ autoStart: true, maxInFlight: 12, issuesPerTick: 4, msptGuard: 40 }`.
- On `ServerStartedEvent`: if `autoStart` && `EclipseWorldState.startEventDone == false` && `PregenState`
  not done → start quietly (ops-only bossbar). Setup worlds are booted days before the event, so the map is
  fully on disk long before `/start_event`; the LIMBO half (`limbo/StartEventCutscene`) then hops players
  onto discs whose chunks are pure region-file loads.
- The intro FUSION sweep (overworld 0→1, `FusionSequence`) also benefits: every chunk of the r150 disc
  already exists, so the sweep only rewrites, never waits on chunkgen.
- Guard rails: never run while `RingGrowthService.isRunning(profile)` (pause the job, resume when the sweep
  ends — the sweep has priority on the chunk-load budget); never run during an active
  `ExpansionSequence`/cutscene.

### 2.5 Command syntax

```
/dev preload everything                    # both disc dimensions to final radius (the F-091 command)
/dev preload start <overworld|nether|all> [radiusBlocks]   # scoped/custom run
/dev preload status                        # cursor, %, rate, ETA, per-dimension
/dev preload pause | resume | cancel
/dev preload unload                        # manual flush-save + verify nothing pregen-ticketed
```

Permission 3 (world-mutating, like `/dev stage`); documented via `DevCommandRegistry` (category STAGE or a
new WORLD category), danger CAUTION (`everything`/`start`), SAFE (`status`).

### 2.6 Performance budget (pregen)

- ~6,000 chunks total; measured chunkgen throughput on the dedicated server should be sampled, but with 12
  in-flight and the full vanilla pipeline expect **25–50 chunks/s** → **2–4 minutes** for everything.
- Disk: overworld height 640 → expect roughly 1–3 GB of region/entity files for both discs. Verify free disk
  in `status` output (warn under 5 GB).
- Zero steady-state cost after completion: no tickets, no listeners beyond the idle `@SubscribeEvent`.

---

## 3. F-092 — giant border mountains

### 3.1 Approach evaluation

| Option | Verdict | Why |
|---|---|---|
| (a) Real terrain mountains only | ✗ alone | Physically present, survives Iris/shaderpacks, players can climb them. But blocks beyond client view distance (12 chunks = **192 blocks**) do not render — from the map center at stage 5 the rim is 440+ blocks away, from the far side 880+. Real blocks can NEVER be "visible from the whole map". |
| (b) Fake far-field only (sky-layer silhouette / Veil ring / BlockDisplay megastructures) | ✗ alone | BlockDisplays are dead on arrival (160-block tracking horizon — the documented lesson of `ExpansionBorderFx` v1). A sky-pass silhouette IS visible from everywhere and animates freely, but walking up to the rim would reveal there is no actual mountain — immersion break at the one place players stare at the border. |
| **(c) Hybrid: real rim wall near + client silhouette far** | ✅ CHOSEN | The silhouette guarantees all-map visibility and drives the recede animation for free (it is parameterized by the already-synced, already-lerped ring radius); the real wall makes the rim physically mountainous within view distance; a distance-based alpha crossfade hides the seam. `ExpansionBorderFx` boulders stay as the near-field quake garnish during expansion gates. |

### 3.2 Layer A (REQUIRED) — client far-field silhouette ring

**New class** `client/sky/RimMountainSilhouette` (client-only), invoked from
`OverworldPurpleEffects.renderSkyEffects` after the sky disc / before the sun (so the eclipse sun rises
behind the peaks) — the sky pass already runs camera-relative with fog disabled, exactly what a
beyond-render-distance backdrop needs. Under an active Iris shaderpack the whole custom sky is skipped
today; the silhouette inherits that (documented, acceptable — same degradation as the purple sun).

Geometry & data flow:

- **Ridgeline**: 256 azimuth segments × 2–3 stacked ridge layers (back ridge tallest/darkest, front ridge
  lighter with fog tint) as one triangle strip per layer, rebuilt only when inputs change materially
  (camera moved > 4 blocks or radius lerping). Peak heights from a **fixed constant seed** hash + 1-D value
  noise over the azimuth (period 2π-safe), so every client renders the identical ridgeline without needing
  the server's map seed. Heights 120–220 world-blocks equivalent, cragged (two noise octaves, sharp `1-|n|`
  crests).
- **True-geometry parallax**: for camera at distance `d` from the disc center, in view direction azimuth θ
  the silhouette ring (placed at `R_sil = ringRadius + 48`) is at ground distance
  `t(θ) = -d·cosΔ + sqrt(R_sil² - d²·sin²Δ)` (Δ = θ − bearing-to-center). Each vertex's elevation angle is
  `atan((peakY - camY) / t(θ))`, projected onto a fixed sky-dome radius (like the sun quad). Result: the
  mountains genuinely LOOM as you approach the rim and flatten toward the horizon from the center — a real
  parallax cue, although the layer is fake.
- **Radius source**: `ClientStateCache.currentBorderRadius(dimension)` — server syncs `S2CBorderPayload`
  on login and every stage commit, and the client already animates the radius area-proportionally over the
  sweep duration. **The recede animation costs zero new networking.**
- **Fog/atmosphere blend**: vertex color = mix(fog color, deep purple palette from `OverworldPurpleEffects`)
  by `t(θ)`; alpha ramps 0→1 between `t` = 80 and `t` = 200 blocks, so within real render distance the fake
  layer fades out exactly where the Layer-B real wall fades in. Night: dim to sky-disc luminance so the
  ring reads as a black cutout against the star field.
- Optional Veil polish (post-MVP): an `eclipse:rim_mountains` post row via `VeilPostController` for a haze
  glow hugging the ridgeline (uniforms: RingRadius, RecedeLerp, Time) — additive only, the geometry layer
  is the Iris-safe base truth.
- Nether: out of scope (enclosed cavern; its rim reads as cave wall + the glitch border).

### 3.3 Layer B — real rim mountain wall (terrain)

Extend `DiscTerrainFunction` with a **rim uplift band** (new noise salt 33, hash salts 33+ as reserved by
the class docs):

- Band: `[R_stage − 56, R_stage − 6]` (annulus width ~50 blocks just inside the rim taper). Surface lift:
  smoothstep envelope 0 at the inner edge → max at ~12 blocks from the rim, jagged ridge noise on top;
  peaks reach **y ≈ 200–240** (below THE mountain's 280 crown so the authored peak keeps primacy; still a
  130–170-block wall over typical y≈71 terrain — "riesige Berge" at close range). Strata: existing high-rock
  shell rules apply automatically (stone + tuff/calcite bands, `SNOW_BLOCK` caps above y 210 — free).
- Suppressions: authored river spillways (the rim waterfalls must keep pouring), `BreachGeometry` funnel,
  landmark clearance boxes near the rim (stronghold r400 site!), the stage-0 player discs (tiny crags only),
  and gaps where cave entrances/`CaveDressings` anchor.
- **Stage-reproducibility contract**: the uplift is keyed to the CURRENT stage radius, i.e. it is
  stage-dependent — legal only inside the band the ring sweep rewrites. Therefore `RIM_REWRITE_MARGIN`
  must grow from 24 to **68** (band 56 + rim noise 8 + safety 4), and `RingGrowthService`'s band membership
  picks that up automatically (it derives from the constant). Cost: each sweep rewrites a ~44-block-wider
  inner annulus (~+25–35% touched chunks per sweep) — covered in §5.
- Because pregen (§2) writes chunks at the committed stage, the wall exists at the CURRENT rim on disk;
  each expansion sweep tears the old wall down (interior rewrite) and raises the new one at the new rim —
  physically, chunk ring by chunk ring, following the wavefront.

### 3.4 Recede animation on expansion day

Sequencing (all existing beats, retargeted):

1. Stage commit → `ExpansionSequence` SKYWARD/FLYOVER; `ExpansionBorderFx.armFrontier` keeps its quake
   monoliths (retune `HEIGHT_MAX` toward 12–16 now that they garnish a real wall).
2. GROWTH: `SoftBorder` hold keeps the client ring radius at the OLD rim → the silhouette stays put while
   the sweep runs behind the wall. The sweep's outward wavefront rewrites the old wall band first
   (`RIM_REWRITE_MARGIN` now covers it) — watchers at the frontier see the real mountains crumble to
   interior terrain under the `growth_dust_wall` curtain (`ExpansionSequence.ClientHooks`), ring by ring.
3. RELEASE (terrain complete): `SoftBorder.releaseGrowthHold` lerps the ring over
   `BORDER_RELEASE_LERP_MS` (2.5 s) → `ClientStateCache.currentBorderRadius` glides outward → **the
   silhouette ring visibly marches back** for every player on the map, not just the frontier watchers.
   Consider stretching this specific lerp to ~8–12 s for the mountain era ("langsam zurückweichen") — one
   constant in `ExpansionTiming`.
4. Drama: one new `FxCues` cue row `eclipse:rim_recede` fired at release (anchor = nearest rim point per
   player): Photon dust curtain + low rumble via the `WorldEventPhotonFxRows` registrar pattern with a
   Quasar fallback, plus the existing `S2CShakePayload` beat. No new payload type — `FxCues` rows ride the
   existing generic FX payload lane.

---

## 4. New files / changed files

| File | Change |
|---|---|
| `worldgen/pregen/MapPregenService.java` | NEW — pregen engine (§2.3) |
| `worldgen/pregen/PregenState.java` | NEW — SavedData `eclipse_pregen.dat` (§2.2) |
| `devtools/dev/DevPreloadCommands.java` | NEW — `/dev preload …` + docs registration (§2.5) |
| `worldgen/stage/GrowthPacing.java` | `pregen` config block, CONFIG_VERSION bump (§2.4) |
| `worldgen/DiscTerrainFunction.java` | rim uplift band, salt 33, `RIM_REWRITE_MARGIN` 24 → 68 (§3.3) |
| `client/sky/RimMountainSilhouette.java` | NEW — far-field ridge ring (§3.2) |
| `client/sky/OverworldPurpleEffects.java` | invoke silhouette in the sky pass (§3.2) |
| `worldgen/stage/ExpansionBorderFx.java` | retune monolith heights; no structural change (§3.4) |
| `worldgen/stage/ExpansionTiming.java` | optional longer mountain-era release lerp (§3.4) |
| `network/fx/FxCues.java` + `veilfx/*FxRows` | `eclipse:rim_recede` cue row (§3.4) |
| `docs/DEV_COMMANDS.md` | document `/dev preload` |

Payload changes: **none required** (border/stage payloads already carry the radius; FX rides `FxCues`).

## 5. Performance budget

| Item | Budget |
|---|---|
| Pregen run | 2–4 min for ~6,000 chunks, ≤12 in-flight, MSPT-guarded; one-time. Disk ~1–3 GB. |
| Silhouette render | 1 draw call × 2–3 strips × 256 segments ≈ ≤2k vertices/frame; strip rebuild only on movement/lerp; zero entities, zero network. |
| Rim wall worldgen | Extra noise ops only inside the 50-block rim band (~11% of disc columns at stage 5); no new chunk cost class. |
| Wider sweep band (`RIM_REWRITE_MARGIN` 68) | +25–35% touched chunks per expansion sweep; with pregen (no skips) plan sweeps at ~1.5–2× the measured 60.7 s stage-3 baseline; raise `SWEEP_CHUNK_LOADS_PER_TICK` 4 → 8 if the pacing target must hold. |
| Recede FX | 1 FxCues cue per player per expansion; Photon budget rules already enforced by the rows framework. |

## 6. Implementation checklist (ordered)

1. `PregenState` SavedData + fingerprint invalidation. Unit-testable without a world.
2. `MapPregenService` job: spiral cursor, region-read skip probe, future/ticket batching, MSPT guard,
   persistence hooks (`ServerStoppingEvent`, resume on `ServerStartedEvent`).
3. Progress surface: ops bossbar + action bar + ETA; `status` formatting.
4. `DevPreloadCommands` (`everything|start|status|pause|resume|cancel|unload`) + `DevCommandRegistry` docs
   + `DEV_COMMANDS.md`.
5. `pregen` block in `worldgen_tuning.json` (autoStart wiring on `ServerStartedEvent`); sweep-priority
   pause guard.
6. GameTest (pattern: `gametest/integration/*`): tiny-radius pregen run completes, resumes after simulated
   stop, skips existing chunks.
7. Measure: full `/dev preload everything` on the dev server; record chunks/s, MSPT, disk; tune inFlight.
8. `DiscTerrainFunction` rim uplift band (salt 33) + suppressions; bump `RIM_REWRITE_MARGIN`; verify a
   stage grow rewrites the old wall fully (no fossil peaks) via `/dev chunk regen` spot checks + sweep run.
9. `RimMountainSilhouette` + `OverworldPurpleEffects` hook; crossfade tuning against the real wall.
10. Recede polish: release-lerp constant, `eclipse:rim_recede` FxCues row + Photon asset, monolith retune.
11. Full rehearsal: fresh world → auto-pregen → `/start_event` → milestone/stage advances to final day.

## 7. Manual test recipes (RCON / server console + one observer client)

1. **Pregen run + progress**: fresh dev world → `dev preload everything` → watch bossbar/`dev preload status`
   (expect monotonically increasing %, sane ETA, MSPT < 45 throughout: `forge tps`). On completion verify
   region files exist out to r≈480 (`ls run/world/region` — expect r.-2..1.-2..1 fully populated + rims) and
   heap returns to idle (no retained chunks: `/forge tps` + F3 on the observer shows unloaded far chunks).
2. **Resume**: start `dev preload everything`, `stop` the server at ~30%, boot — expect auto-resume log +
   bossbar at the persisted %; final count matches a clean run.
3. **No raw generation visible**: after pregen, observer client flies (`/gamemode spectator`, speed 5) from
   center past the rim at stage 5 radius and across the whole disc — no "generating terrain" holes, chunk
   pop-in is load-only (instant sections, no visible column-by-column build). Repeat during `/start_event`
   with 2 clients: the wake-up-on-disc beat shows fully built terrain.
4. **Mountains visible from everywhere**: with Layer A+B in, stand at map center (r=0), spawn plaza, and at
   the OPPOSITE rim — the ridge ring must read in all directions (screenshot each); approach the rim and
   confirm the silhouette crossfades into real climbable mountain terrain without a double image.
5. **Recede animation**: `dev stage set overworld 3` (or milestone advance) while the observer stands
   mid-map: expect (a) frontier wall crumbling under the dust wavefront for rim watchers, (b) on release the
   distant ring visibly gliding outward over the release lerp for the mid-map observer, (c) `rim_recede`
   dust/rumble cue, (d) no leftover wall fragments inside the new interior (fly the old rim circle after).
6. **Sweep interplay**: start a pregen, immediately commit a stage — pregen must pause (log) and resume
   after `RingGrowthService` completes; no double chunk-load budget spike (`forge tps` during both).
