# IDEA-18 — Limbo Atmosphere (collector 18/20, Eclipse Event wave 4)

Focus: LIMBO ATMOSPHERE — the ghost-ship sea between deaths. Grounded in:
`limbo/GhostShipBuilder`, `limbo/LimboSeascape`, `limbo/ShipLanterns`, `limbo/OarAnimator`,
`entity/DeckhandEntity` + `client/entity/DeckhandRenderer`, `client/sky/LimboSpecialEffects`
(+ `StarField`, `SkyRenderUtil`), `veilfx/LimboAmbience` (+ `QuasarSpawner`, `FxBudget`,
`FxAnchors`, `VeilPostController`), emitters `assets/eclipse/quasar/emitters/limbo_{motes,godray,fog}.json`,
post shader `assets/eclipse/pinwheel/shaders/program/limbo.fsh`.

House rules every idea respects:
- **Client-only ambience** goes through `LimboAmbience`'s `Window` pattern (rolling looping
  Quasar emitters, `FxBudget.Channel.AMBIENT`, `reducedFx` doubles cadence) or the sky pass.
- **Sky pass** (`LimboSpecialEffects.renderSky`) is Iris-guarded (`EclipseIrisState.shaderPackActive()`
  defers) and must not allocate per frame (P2 §3.5 — pre-allocated scratch statics).
- **Post uniforms are frozen** (§3.3: `Intensity`, `GodrayDir`, `CausticsAmount`, `Time`) — new
  screen-space work must reuse them or live in the sky pass, not add uniforms.
- **Server-side blocks** must follow the `GhostShipBuilder`/`LimboSeascape` law: deterministic
  `DiscMapData.ECLIPSE_SEED` hashes, idempotent set-block loops, nothing waterloggable inside the
  P3 sink volume (`deckY+1..+4` over `halfWidthAt`), never touch the frozen fight contracts (§1.3).
- One clock: the deckhand `row` loop is 60 t, phase-locked to `gameTime % 60`
  (`DeckhandEntity.ROW_SYNC_PERIOD_TICKS`, resync in `DeckhandRenderer.preRender`). Anything
  rhythmic should ride that clock, not invent a second one.

Sizing: **S** = one file / <~100 LOC / reuses existing assets. **M** = 2–4 files and/or one new
emitter JSON / sound wiring.

---

## Ranked ideas

### 1. Water reflection of the eclipse (M)
A smeared violet glimmer of the zenith disc on the black water — the single highest-payoff shot
in limbo (the sea currently reflects nothing, which reads as void, not ocean).
- **Hook (world-space, preferred):** `LimboSpecialEffects.renderSky` — after the disc draw, push
  a second pose and draw an additive, camera-facing "reflection streak" quad ON the water plane
  directly below `zenithWorldPoint(level)`: a long thin triangle-fan (reuse the
  `drawAuraGlow` builder pattern, `GameRenderer::getPositionColorShader`, additive blend already
  set up) stretched toward the camera, alpha falling with camera height above the waterline.
  Waterline Y client-side: `FxAnchors.get(FxAnchors.SHIP_DECK).y - 4` (deck = waterline+3, anchor
  publishes deck; fallback shared-spawn Y like `zenithWorldPoint` does).
- **Hook (screen-space garnish, free):** `limbo.fsh` already has the water mask + `GodrayDir`;
  add a `mirrorUv = vec2(GodrayDir.x, -GodrayDir.y)` bright smear into the existing caustics
  block — zero new uniforms, stays inside frozen §3.3.
- Breathe it with the same `pulse = 0.85 + 0.15*sin(seconds*1.3)` the aura uses so disc and
  reflection never desync.

### 2. Distant silhouette ships that vanish when looked at (M)
Peripheral-vision dread: 2–3 flat black ship silhouettes with a single soul-green stern light sit
on the horizon; the moment the camera centers one, it fades out (and re-seeds elsewhere later).
- **Hook:** new client class `client/sky/LimboHorizonShips` drawn from
  `LimboSpecialEffects.renderSky` right after `GREEN_STARS.draw(...)` (same no-fog window, then
  restore fog): 2–3 quads at fixed azimuths at `SKY_DISTANCE`, geometry = 5–6 dark triangles
  (hull + two masts) from a static float table, plus one 0.9-alpha green point (stern lantern).
- **Vanish logic:** per frame `dot(camera.getLookVector(), dirToShip)`; alpha =
  `1 - smoothstep(0.88, 0.97, dot)`, with a one-way latch per sighting (once fully faded, hold
  invisible for 1200–2400 t, then re-seed a new azimuth from an `ECLIPSE_SEED`-derived hash of
  the sighting counter — deterministic, no `level.random`). Pre-allocated `Vector3f` scratch only.
- Purely cosmetic, no entities, no server traffic; Iris guard comes for free from `renderSky`.

### 3. Fog banks rolling past (S)
The near-camera `limbo_fog` sheets hug the player; the missing layer is the *middle distance* —
big slow banks that visibly travel +X past the ship (the buoy-lane direction), selling that the
sea moves even though the ship never does.
- **Hook:** copy `assets/eclipse/quasar/emitters/limbo_fog.json` → `limbo_fogbank.json`: sphere
  dims ~`[18, 2.5, 18]`, `base_particle_size` 16–24, lifetime 90±30, alpha peak ~0.08, and raise
  the `veil:wind` module to `wind_speed: 0.05`, direction `[1.0, 0.0, 0.15]` (matches the
  `LimboSeascape.buoyLane` +X axis and the existing fog wind heading).
- **Hook:** one new line in `LimboAmbience`: `FOGBANKS = new Window(LIMBO_FOGBANK, 2, 140, 200,
  35.0D, 70.0D, 0.5D, 2.0D)` added to `WINDOWS`. The rolling-window lifecycle, budget charge,
  `reducedFx`, and disconnect reset are all inherited.

### 4. Deckhand rowing-song hum, procedural (M)
Eight mute rowers who hum one low, wordless dirge *on the stroke* — pitch pattern generated, no
new audio asset needed (or one 1-note "hum" ogg if we want it richer).
- **Hook:** small client class `veilfx/LimboRowChant` ticked from `LimboAmbience.onClientTick`
  (inside the existing `inLimbo && !isPaused` branch): on each row-clock boundary
  (`level.getGameTime() % DeckhandEntity.ROW_SYNC_PERIOD_TICKS == 0`) play one positioned
  `minecraft:block.note_block.didgeridoo` (or a new `eclipse:ambient.deckhand_hum` in
  `EclipseSounds` + `sounds.json`, mono, `stream: false`) at the nearest seated deckhand
  (`EclipseEntities.DECKHAND` scan in a 24-block AABB; skip `isHostile()` — the risen crew does
  not sing), `SoundSource.AMBIENT`, volume ~0.25.
- **Procedural melody:** pitch from a fixed table indexed by
  `(gameTime / 60) % 8` — e.g. minor-pentatonic `{0.5, 0.53, 0.5, 0.594, 0.5, 0.445, 0.5, 0.53}` —
  deterministic and identical for all clients, and every 4th cycle rests (silence sells a dirge).
- Catches: the chant must die with `OarAnimator.isTiltActive()` (cutscene) and when the crew
  rises hostile (`countHostileAlive > 0` is server-side; client-side just check the scanned
  entities' `isHostile()`), and respect `soundStartedThisVisit`-style reset on dimension change.

### 5. Ghostly ship-wake trails (S/M)
The ship is stationary but the crew rows forever — so the *water* should answer: faint luminous
wake lines peeling off each oar catch and sliding sternward (−X), plus a dim churn line astern.
- **Hook (S, zero assets):** `DeckhandRenderer.spawnCatchSplash` already finds the water surface
  under the blade tip once per 60 t cycle; after the `SPLASH` loop, add 4–6
  `ParticleTypes.GLOW` / `SOUL` particles at `surfaceY + 0.05` with velocity
  `(-0.05 * bowSign, 0, 0)` world-space sternward (bow is +X — `GhostShipBuilder` v2 silhouette),
  spread over the next ~1.5 blocks so eight synchronized blades paint eight short drift lines.
- **Hook (M, prettier):** new looping emitter `limbo_wake.json` (thin additive billboard strip,
  violet, `velocity_stretch_factor > 0`) spawned via `QuasarSpawner.spawn(WAKE, tipPos,
  FxBudget.Channel.AMBIENT)` from the same call site — budget-refused spawns degrade silently.
- Never fire while `entity.isTilt()` (already guarded at the call site) or hostile (oar hidden).

### 6. Lantern moths (S)
Pale spirit-moths orbiting the soul lights — the ship's four soul-campfire fight lanterns, the
stern great-lantern cluster, and the buoy lane — making the lights feel *inhabited*.
- **Hook:** new emitter `limbo_moths.json` (tiny billboard, `eclipse:textures/particle/purple_wisp.png`
  reused at `base_particle_size` ~0.15, lifetime 40±20, slight upward `initial_direction`,
  `veil:wind` off; a weak inward drift reads as orbiting at this size) + one `LimboAmbience`
  window `MOTHS = new Window(LIMBO_MOTHS, 3, 60, 90, 4.0D, 18.0D, 1.5D, 2.5D)`.
- **Targeting twist:** instead of the camera-ring `pickSpawnPos`, bias spawns to actual lights:
  scan the 3–4 nearest `Blocks.SOUL_LANTERN` / lit `SOUL_CAMPFIRE` positions in a 16-block cube
  around the camera (cheap: reuse the `BlockPos.betweenClosed` idiom, cache per spawn attempt,
  no per-frame work — this runs at window cadence, ~every 3–4 s) and spawn 0.5 blocks off one.
  Falls back to the camera ring over open water = fine (buoy lanterns line the lane anyway).

### 7. Drowned bell tolls from beneath the sea (S)
Every few minutes, one muffled bell from *below* — far off the beam, pitched down, quiet. Sells
depth (things are down there) with one line of sound code and zero new assets.
- **Hook:** in `LimboAmbience.onClientTick` (in-limbo branch), a countdown of
  `random.nextIntBetweenInclusive(2400, 4800)` t; on fire, pick an azimuth/distance 40–80 blocks
  out, y = waterline − 12, and `level.playLocalSound(x, y, z, EclipseSounds.BOSS_FERRYMAN_BELL
  .get()` (the registered `boss.ferryman_bell` — see `sounds.json` / `EclipseSounds`)`,
  SoundSource.AMBIENT, 0.35F, 0.55F, false)`.
- Guard: suppress while a Ferryman fight is audible (don't confuse the real bell) — client-side
  proxy: skip if any `FerrymanEntity` is within render distance (`level.getEntities` AABB scan
  at the toll cadence only).

### 8. Soul-ember columns above the seascape spires (S)
The three blackstone/obsidian spires (`LimboSeascape.spire` at (205,40), (−95,−215), (−230,−35),
soul fire on top) are invisible at night beyond their pixel of flame. Slow ember columns make
the graveyard-sea landmarks readable from the ship and give the horizon vertical interest.
- **Hook:** new emitter `limbo_embers.json` (additive, cyan-green gradient `#4FD8A0 → #1E5A46`,
  `initial_direction [0,1,0]`, speed ~0.02, lifetime 80±30) + a fixed-position variant of the
  `LimboAmbience` window: a tiny `SPIRE_EMBERS` handler that keeps ≤1 live emitter per spire,
  spawning only when the camera is within 160 blocks of that spire's constant coords (mirror the
  three `(x, z)` constants + `FxAnchors.SHIP_DECK.y − 4 + height` for the crest Y; the constants
  are already frozen in `LimboSeascape.build`). Same `spawnManaged`/prune/`clear()` discipline.

### 9. Green shooting stars (S)
The sparse green `StarField` (seed 20846, 420 stars) gets a rare companion: a single green streak
across the dome every 1–3 minutes. Cheap awe, reinforces the alien sky without touching the disc.
- **Hook:** `LimboSpecialEffects.renderSky`, after `GREEN_STARS.draw`: a static
  `nextStreakSeconds` schedule derived from the existing `seconds` clock (deterministic hash of
  the streak index — same pattern as `LimboSeascape.hash01`, no allocation); while
  `seconds ∈ [start, start+0.9]`, draw one tapered `POSITION_COLOR` quad (reuse the
  `drawAuraRays` wedge math) sweeping ~35° of arc at `SKY_DISTANCE`, alpha 0 → 0.5 → 0 over the
  0.9 s life, color `(0.35, 0.9, 0.45)` to match the stars.
- Keep it out of the zenith rotation push/pop so it streaks the dome, not the disc frame.

### 10. Row-clock rigging creaks (S)
The hull answers the stroke: one wood groan + chain clink from a mast or the gunwale on the
*recovery* beat (phase ~30 t, opposite the catch splash at ~56 t), quiet and low-pitched. Pure
sound-design glue that makes ideas 4/5 land as one organism.
- **Hook:** same client ticker as idea 4 (`LimboRowChant` — one class serves both): at
  `gameTime % 60 == 30`, play `SoundEvents.BAMBOO_WOOD_HANGING_SIGN_STEP` or
  `SoundEvents.CHAIN_STEP` (alternating via `(gameTime/60) & 1`) at a hash-picked point along
  the gunwale (`x ∈ BENCH_X`, `z = ±halfWidthAt(x)`, deck Y from the `SHIP_DECK` anchor),
  `SoundSource.AMBIENT`, volume 0.15–0.2, pitch 0.5–0.7.
- Only within 28 blocks of the ship anchor; silent during tilt and while the crew is risen
  (same guards as the hum — the fight owns the soundscape then).

---

## Cross-cutting notes for the implementer
- Ideas 3, 6, 8 are pure `Window`-pattern additions — the emitter-leak, budget, `reducedFx`,
  pause, and disconnect semantics are already solved; do not hand-roll lifecycles.
- Ideas 1, 2, 9 live entirely inside `LimboSpecialEffects.renderSky` and inherit the Iris guard;
  keep the §3.5 no-per-frame-allocation rule (static scratch `Vector3f`/`Quaternionf` like
  `ZENITH_DIR`/`ZENITH_ROT`).
- Ideas 4, 5, 10 must ride the existing 60 t row clock and honor the tilt/hostile guards — the
  cutscene (`StartEventCutscene` TILT at t=0) and the Ferryman P2 crew rise already flip the
  observable state these effects key off; no new sync channel is needed.
- Nothing above touches server block state or the frozen §1.3 fight contracts; idea 7 reuses an
  already-registered sound event, so the only new assets across the whole list are ≤3 emitter
  JSONs and (optionally) one hum ogg.
