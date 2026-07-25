# Photon FX Ideas — Custom Mobs + Celebration Moments (PHOTON-IDEAS-5, 2026-07)

Scope: **custom mob effects + celebration moments**. Concepts for editor-authored `.fx`
assets (`assets/eclipse/fx/<id>.fx`) played through the reflection bridge
(`veilfx/PhotonBridge`, see `INTEGRATION.md`). Every effect here is an ADDITIVE garnish:
the shipped vanilla/Quasar layer keeps running unchanged, and Photon absence is a silent
no-op (D12 degradation law). All format facts cited below come from `FX_FORMAT.md` /
`API.md` (verified against photon-neoforge-1.21.1-2.1.5); all trigger points were read
from the current entity/overlay sources.

---

## 0. Cross-cutting design laws for this batch

1. **Two executor kinds.** One-shots at a position use the already-reflected
   `BlockEffectExecutor` (`PhotonBridge.spawn`). Everything attached to a mob needs the
   **one** new reflection surface `INTEGRATION.md` §3.5 pre-authorizes:
   `EntityEffectExecutor(FX, Level, Entity, AutoRotate)` + `AutoRotate.valueOf(...)` →
   a new `PhotonBridge.spawnOnEntity(fxId, entity, autoRotate)` (same guard chain, same
   `MISSING_FX` law). Entity executors re-anchor to `entity.getEyePosition()+offset`
   every frame and **auto-destroy when the entity dies** — projectile/mob cleanup is free.
2. **The loop tier (new, explicit).** INTEGRATION §4 forbids high-frequency *cues* with a
   Photon leg; entity-attached **loops** are a different shape (no wire traffic at all —
   attach is client-local, keyed off synced state the client already has). Loop rules:
   attach client-side only (renderer/tick observation, zero server code), default
   `allowMulti=false` so a re-attach attempt while the loop lives is a **silent no-op**
   (the per-entity CACHE dedup does our bookkeeping), graceful stop via
   `runtime.destroy(false)` on the state edge, every loop `.fx` carries a `renderer.cull`
   box and a small `maxParticles`, and the whole tier sits behind
   `PhotonBridge.available()` (so `reducedFx`/`photonFx=false` kills it wholesale).
   Suggested single owner class: `veilfx/PhotonMobFx` (`@OnlyIn(Dist.CLIENT)`) — a table
   of `EntityType → (fxId, autoRotate, attach predicate)` walked from a cheap client-tick
   scan of tracked entities in range; keep it ONE class, no per-mob seams.
3. **allowMulti semantics** (API.md §3): default `false` dedups per BlockPos/Entity per
   fx location while a runtime is alive. Every concept below states its choice.
4. **Bloom is a bright-pass** (FX_FORMAT §5: threshold 1.0, additive/multiplicative HDR
   boost). **Dark pixels can never bloom** — "dark bloom" ideas must be built from (a)
   desaturated low-luminance violet that stays under the threshold plus (b) a
   `REVERSE_SUB` blend pass (`dst − src`) that *eats* framebuffer light. That is real
   GL-equation support (`blendFunc: ADD|SUB|REVERSE_SUB|MIN|MAX` per material) and it
   works with bloom disabled too.
5. **Budgets.** Photon spawns bypass `FxBudget`; the numbers below are the budget.
   House ceiling for this batch: ≤ 400 live Photon particles per concept, ≤ 2 concurrent
   loop *kinds* per mob, `vertexSortingMode: NONE` wherever blending is additive,
   physics collision only where it IS the effect (award shower).
6. **Fallback invariant**: every trigger point below already has a shipped vanilla/Quasar
   visual. Photon failing/missing must leave that layer bit-identical. No concept below
   removes or conditions an existing particle call.

---

## Ranked concepts

Ranking = (moment impact × showcase of Photon-only capability) ÷ (integration risk).
One-shots that ride existing seams rank above loops that need the new attach manager.

---

### #1 — Boss intro name-lock ground shockwave — `eclipse:boss_intro_shockwave`

The celebration half of the boss intro card: the instant `BossIntroOverlay` locks the
last character of the boss name (its DANGER→TEXT `LOCK_FLASH_TICKS` beat), the ground
under the boss answers with a bloom-edged shockwave ring — HUD and world snap together
on one frame.

- **`.fx` spec** (one-shot, `looping:0b`, duration 30t):
  - `ring` (particle_emitter): `circle` shape r=0.4, `radiusThickness:0f` (shell),
    `shapeArc {arcMode:"BurstSpread"}`; one burst of 90 at t=0; `startSpeed` radial
    2.2 (particles ARE the expanding ring), `startLifetime` 16–22t; `sizeOverLifetime`
    curve 1→0; texture material `photon:textures/particle/circle.png`,
    `hdr:[1.6,1.2,2.4,1]` ADDITIVE (violet-white bloom crest), blend ADD, `lights`
    fullbright; `simulationSpace: World`.
  - `dust_kick` (particle_emitter, child): cone up, 24 burst, alpha-blended smoke,
    gravity 0.12, `shade:1b` (world-lit dust grounds the bloom flash).
  - `crack_glow` (beam_emitter ×4 under an `empty` pivot): short radial beams
    (`end:[0,0,-2.5]`, width 0.12, `raycast: BLOCKS` so they clip into terrain),
    `emitRate:0` continuous for 12t, HDR color — light bleeding along the ground seams.
- **Attach/trigger**: server side, every `BossPayloads.sendIntro` call site (Ferryman /
  Herald / Fog Tyrant / Rift Warden summon blocks) also sends the existing-lane
  `FxPayloads` cue `eclipse:fx/cue/boss_intro_shockwave` with the same `center` —
  a `PhotonFxRegistry` row (INTEGRATION §3), `Mode.LAYER`, `quasarEmitter: null`.
  Client dispatch does NOT spawn immediately: it parks the pos and spawns via
  `PhotonBridge.spawn` with `setDelay(decodeEnd)` where `decodeEnd` =
  `PRE_TICKS + nameLength × TICKS_PER_CHAR` — the same deterministic formula
  `BossIntroOverlay.decodeEndTick()` uses (per-client glitch salt scrambles only the
  noise, never the lock timing), so the ring erupts on the lock flash. If no card is
  live client-side (queue overflow, reducedFx text mode), spawn with delay 0.
- **allowMulti**: `false` — one ring per intro; queued double-intros at one arena
  BlockPos dedup while alive (correct: the card queue serializes them anyway).
- **Fallback**: intro card + existing arrival FX unchanged (the card never depended on
  a world accent). Photon-less clients simply keep today's presentation.
- **Budget**: ≤ 130 particles for ≤ 30t, 4 beams for 12t; cull box ±6 blocks;
  no physics; `parallel*: 0b`. Sequence-grade one-shot — exactly the INTEGRATION §4 tier.

---

### #2 — Offering swallow 2.0: item-soul ribbon spiral — `eclipse:offering_swallow_soul`

Upgrade of the flagship altar beat: as `OfferingSwallowFx` flies the item billboard
hand→altar, Photon adds a converging soul-ribbon spiral being *inhaled* by the altar,
with an HDR-hot tip that primes the bloom right where the beam is about to erupt.

- **`.fx` spec** (one-shot, duration 32t = `OfferingSwallowFx.FLIGHT_TICKS`):
  - `soul_intake` (particle_emitter): `function` shape mirroring the flight spiral but
    anchored at the altar — `x:"(1-t)*2.4*cos(t*4*PI+randomA*6.28)"`,
    `z:"(1-t)*2.4*sin(t*4*PI+randomA*6.28)"`, `y:"(1-t)*1.4"`, speed expressions aimed
    inward (`speedX:"0-x*0.35"` etc.) so motes spawn on a shrinking helix and fall into
    the stone; emissionRate 2.5/t, lifetime 10–14t; **`trails` module ON**
    (`trailType: ARA_TRAIL`, `inheritParticleColor:1b`, lifetime 0.6) — every mote drags
    a physically-lagging mini-ribbon (`araConfig.physicsSetting {inertia:0.4,
    damping:0.6}`), which is the "soul ribbon" read Quasar cannot do.
  - `hdr_tip` (particle_emitter): 1-particle "comet head" re-emitted every 4t on the
    same helix expression, size 0.22, sprite material with `hdr:[2.5,1.8,1.0,1]`
    (gold-hot tip feeding the bloom chain), StretchedBillboard `velocityScale: 1.4`.
  - Palette: violet→gold `colorOverLifetime` gradient (house altar palette; the glow fan
    already tints per-item, the Photon layer stays neutral).
- **Attach/trigger**: client-side in `OfferingSwallowFx.beginFlight` (the class already
  is the client owner of this beat): after `spawnManaged(...)`, call
  `PhotonBridge.spawn(OFFERING_SWALLOW_SOUL, target)` — anchored at the altar target,
  NOT the moving item (block executor is enough; no per-tick repositioning). New
  constant on `PhotonBridge`, same pattern as `ALTAR_LEVELUP`.
- **allowMulti**: **`true`** — `MAX_FLIGHTS = 4` concurrent offerings share one altar
  BlockPos during a rush; default dedup would silently eat offerings 2–4.
- **Fallback**: the item billboard + glow fan + Quasar trail are untouched; degraded
  beat (reducedFx / anchor unsynced) already routes to the plain burst and must NOT get
  a Photon call (guard on the same branch `beginFlight` already takes).
- **Budget**: ~80 motes + ribbons ≤ 32t, one HDR head; per-flight cost ×4 max; cull box
  ±4 blocks around the altar; `time: 0.5` s ribbon retention keeps ara segments short.

---

### #3 — Award ceremony winner star shower — `eclipse:award_star_shower`

The daily-award roulette's podium moment, physicalized: when the needle lands on the
local winner, star models rain down around them, **bounce off the real floor** and
settle as glinting debris — Photon's model-particles + genuine collision physics in one
celebratory shot (Quasar can do neither).

- **`.fx` spec** (one-shot, duration 50t):
  - `star_fall` (particle_emitter): `box` shape (Shell) 3×0.5×3 positioned +5 blocks up
    (shape `position` NF3), bursts 3×14 at t=0/6/12; `renderMode: Model` with `mesh`
    shape `meshData.modelLocation:"item/nether_star"` + `block_atlas`-family material
    (`useBlockUV`) so each particle IS a spinning star model; `startSize` 0.12–0.2,
    `rotationOverLifetime` roll 14°/t; **`physics` ON**: `hasCollision:1b`, gravity 0.5,
    `bounceChance:0.85`, `bounceRate:0.45`, `bounceSpreadRate:0.15`,
    `collidedFriction:0.6` — stars clatter and skid on the actual floor collider;
    lifetime 30–45t; `lights` fullbright.
  - `glint_pop` (subEmitters module on `star_fall`): event `Collision`,
    `emitProbability` 0.5, fx `eclipse:award_star_glint` — a 4-particle HDR micro-spark
    (`hdr:[1.8,1.5,0.6,1]`) at every bounce. Sub-emitters-on-collision is the showcase.
  - `gold_haze` (particle_emitter): soft additive gold veil, 20 particles, no physics.
- **Attach/trigger**: client-local in `AwardsOverlay.podiumBurst()` (already exists,
  already client-only, already fires exactly once when `reveal.localWon()` on the LAND
  transition, already spawns the `unlock_burst` Quasar emitter over the local player):
  add `PhotonBridge.spawn(AWARD_STAR_SHOWER, player.position())`.
- **allowMulti**: `false` — one shower per reveal; shared-win ties each see their own
  local shower (per-client anyway). Dedup also protects against LAND replays.
- **Fallback**: `unlock_burst` Quasar burst + award sting remain the podium moment.
- **Budget**: 42 star models + ≤ 21 collision glints + 20 haze ≤ 50t. Physics is the
  most expensive module (world queries per particle) — hard cap 42 colliding particles,
  `maxParticles: 64`, cull box ±5; this is the ONLY concept in the batch allowed
  collision. One-shot per day per client: cost is a non-issue.

---

### #4 — Fog family: hound lunge charge-up spiral + dash fog ribbon; revenant robe wisps
`eclipse:hound_lunge_windup`, `eclipse:hound_dash_trail`, `eclipse:revenant_fog_ribbons`

Combat readability first: the Storm Hound's 20t rooted windup gets an unmissable
converging spiral telegraph, the 12-block dash drags a physical fog ribbon, and the Fog
Revenant's hem wisps upgrade from CAMPFIRE smoke to lagging robe ribbons.

- **`.fx` specs**:
  - `hound_lunge_windup` (one-shot, 20t = `ChargedLungeGoal.WINDUP_TICKS`): `function`
    shape spiral collapsing inward — `x:"(1-t)*1.2*cos(t*6*PI)"`,
    `z:"(1-t)*1.2*sin(t*6*PI)"`, `y:"0.2+t*0.6"`; emission 3/t, electric white-blue,
    `colorBySpeed` toward white, small HDR (`[0.8,1.0,1.4,1]`) so the crest of the
    spiral blooms right as the glow-spine anim peaks; burst of 16 at t=19 (release pop).
  - `hound_dash_trail` (one-shot, 16t): a bare **`ara_trail_emitter`** —
    `alignment: Velocity`, `thickness 0.35`, `thicknessOverLength` curve fat→0,
    `time: 0.7` s, `physicsSetting {inertia:0.55, velocitySmoothing:0.8, damping:0.7}`
    (the ribbon whips and settles behind the dash), fog-grey `colorOverLength` gradient
    with transparent tail, alpha blend, `shade:1b`. Attached `FORWARD` so the ribbon
    lays along the dash line.
  - `revenant_fog_ribbons` (loop, duration 60t `looping:1b`, prewarm 20): 2-emitter
    tree — `hem_wisps` cylinder shell r=0.5 low emission (0.6/t, lifetime 30–40t, slow
    rise, `noise` module wobble, alpha-blend fog sprites, `shade:1b`) + `trails` module
    (TRAIL type, short) so wisps tear off the robe as streamers. Local simulation space
    (aura follows the drift).
- **Attach/trigger**: needs `PhotonBridge.spawnOnEntity`. Windup: the client observes
  the `charge_windup` GeckoLib one-shot? No — cleaner: `ChargedLungeGoal.startWindup`
  already plays `WARDEN_SONIC_CHARGE`; add a `PhotonFxRegistry` **entity** cue row on
  the same send (`FxPayloads` carries pos; the client resolves the nearest StormHound
  within 2 blocks) — or simplest sanctioned shape: client-side `PhotonMobFx` watches
  `StormHoundEntity` anim state. RECOMMENDATION: entity cue payload (windup + dash are
  server-authoritative phases; a 1-int entity-id cue variant is the honest carrier —
  flag as the one small payload addition in this batch, reusable by #6/#7).
  Dash: same seam at the DASH transition, `AutoRotate.FORWARD`. Revenant loop:
  `PhotonMobFx` table row, attach on client tick for tracked `FogRevenantEntity`,
  `AutoRotate.NONE`, offset −0.9 y (hem, not eyes).
- **allowMulti**: windup/dash `false` per entity (160t cooldown guarantees no overlap;
  dedup absorbs duplicate cues). Loop `false` (re-attach = no-op by CACHE law).
- **Fallback**: existing tells stay — glow-spine anim scale-up + sonic-charge sound
  (windup), ELECTRIC_SPARK hit burst, CAMPFIRE hem smoke (revenant). Photon adds, never
  replaces.
- **Budget**: windup ≤ 60+16 particles/20t; dash = 1 ara ribbon (segments only);
  revenant loop ≤ 40 live wisps, cull box ±3, `maxParticles: 64`. Packs of 2–3 hounds:
  worst case 3 windups ≈ 230 particles — fine. Loop count bounded by storm-patch
  revenant population; cap attach at nearest 4 revenants in `PhotonMobFx`.

---

### #5 — Glitched family: datamosh blink pop + corruption drip loop
`eclipse:glitch_pop`, `eclipse:glitch_drip`

`GlitchedMonster.tryBlink()`'s javadoc already reserves the slot: *"P2's
`eclipse:glitch_pop` emitter replaces the vanilla burst later"*. Photon's per-material
GL blend equations make the datamosh read literal: a `REVERSE_SUB` pass rips a dark
"decompression hole" in the framebuffer at origin and exit, while an ADD pass scatters
hot RGB-split shards.

- **`.fx` specs**:
  - `glitch_pop` (one-shot, 14t): one particle_emitter, **two materials in
    `renderer.materials`** (multi-material = multi-pass, FX_FORMAT §3.2):
    pass 1 `blendFunc:"REVERSE_SUB"`, src/dst factors ONE/ONE, soft-square texture —
    every particle *subtracts* light where it overlaps (the dark datamosh rip; works
    with bloom off, no dark-bloom dependency); pass 2 ADD with
    `uvAnimation` 4×4 static-noise flipbook (`tiles:[4,4]`, WholeSheet,
    `frameOverTime` linear) and slight per-particle `startColor` random between pure R /
    pure G / pure B ints — chromatic-aberration shards. Burst 18 at t=0, box Shell
    shape matching mob bounds, lifetime 6–10t, `startRotation` random roll, World space
    (the hole hangs in air after the mob is gone). `maxParticles: 32`.
  - `glitch_drip` (loop, 40t cycle): sparse corruption dripping off the seams —
    emission 0.35/t, `dot` shape at random offsets via `noise` position, gravity 0.25,
    `removedWhenCollided`? No physics — cheaper: lifetime 18t and `sizeOverLifetime`
    to 0. Materials: single pass, `pixelArt {_enable:1b, bits:8}` (Photon's pixel-art AA
    keeps drips chunky-crisp), dark violet, occasional bright frame via `random_color`
    a/b. `maxParticles: 24`, cull ±2.
- **Attach/trigger**: blink pop is server-known (`tryBlink` sends paired
  REVERSE_PORTAL bursts at origin + exit today) → one `FxCues` position cue per
  endpoint over the existing `FxPayloads` lane, registry rows `Mode.LAYER`. Drip loop:
  `PhotonMobFx` row for `GlitchedHuskEntity`/`GlitchedHoundEntity`/`GlitchedTickEntity`
  (+ Wanderer inherits, see #9), `AutoRotate.NONE`.
- **allowMulti**: **`true`** for `glitch_pop` — short blinks can land origin and exit
  in the SAME BlockPos, and hounds blink on 120–200t cadence in packs; default dedup
  would eat the exit half. Drip loop `false`.
- **Fallback**: paired REVERSE_PORTAL bursts + ENDERMAN_TELEPORT sound + client WHITE_ASH
  static (in `aiStep`) all remain.
- **Budget**: pop = 18 particles ×2 endpoints ×2 passes ≤ 14t (cheap; blink cadence is
  120–280t per mob so bursts never stack per-entity). Drips ≤ 24/mob, attach cap
  nearest 6 glitched mobs. REVERSE_SUB is order-independent against itself —
  `vertexSortingMode: NONE`.

---

### #6 — Cultist shadow bolt ribbon + impact — `eclipse:shadow_bolt_ribbon`, `eclipse:shadow_bolt_impact`

The purple seeker (`ShadowBoltProjectile`, cultist 3-bolt fans + Rift Warden volleys)
trades its vanilla WITCH dribble for a hard ara ribbon with a wither-violet core, and
detonation gets a real impact flower.

- **`.fx` specs**:
  - `shadow_bolt_ribbon` (loop, lives as long as the bolt — entity executor
    auto-destroys on projectile removal, LIFETIME_TICKS=100 max): single
    `ara_trail_emitter`, `space: World`, `alignment: View`, thickness 0.16,
    `thicknessOverTime` fade, `time: 0.45` s retention, `colorOverLength` violet-core →
    black-edge gradient, tiny `hdr:[0.9,0.4,1.3,1]` on the core material (a faint bloom
    thread — bright violet core, NOT a dark bloom), plus a child particle_emitter
    dripping 0.5/t wither-motes with `inheritVelocity {mode: CURRENT, multiply: 0.3}`.
  - `shadow_bolt_impact` (one-shot, 16t): sphere-shell burst 22, REVERSE_SUB dark
    flash pass + ADD violet shards pass (same two-pass trick as #5), 4-beam
    `beam_emitter` micro-cross clipped by `raycast: BLOCKS`, lifetime 8–12t.
- **Attach/trigger**: ribbon — client-side attach on projectile appearance:
  `PhotonMobFx` row keyed on `EntityType` SHADOW_BOLT via client entity-join
  observation, `AutoRotate.NONE` (World-space ara follows the eye position each frame —
  exactly what a homing bolt needs). Impact — `ShadowBoltProjectile.onHit*` already
  runs server-side particle sends; add an `FxCues` position cue there
  (`Mode.LAYER`, quasar leg null).
- **allowMulti**: ribbon `false` per entity (one ribbon per bolt, free). Impact
  **`true`** — a 3-bolt fan can strike the same wall block within 2 ticks.
- **Fallback**: WITCH trail particle (`getTrailParticle`) + existing hit
  spark/sound remain untouched.
- **Budget**: 1 ara ribbon + ≤ 10 motes per live bolt; fans are 3 bolts, warden volleys
  more — cap attach at 8 nearest bolts in `PhotonMobFx` (past that, vanilla WITCH trail
  carries it). Impact ≤ 22×2-pass + 4 beams/16t. Watch item: this is the highest-
  frequency concept in the batch — dungeon spawner rooms re-supply cultists
  indefinitely; the nearest-8 cap and per-bolt tiny budgets are the guard rails.

---

### #7 — Pale Sentinel: freeze alert flare + petal-light orbit
`eclipse:sentinel_alert`, `eclipse:sentinel_petal_orbit`

The weeping-angel statue moment, made luminous: the instant the sentinel freezes a
petal-flash cracks off it, and while it stays frozen a slow halo of pale petals orbits
the statue — beautiful, and a gameplay tell ("it is frozen because YOU are looking").

- **`.fx` specs**:
  - `sentinel_alert` (one-shot, 10t): burst 20 from box-shell, cherry-petal-like sprite
    (atlas `sprite` material), white-pink, quick outward puff + `rotationOverLifetime`,
    single mid-bright HDR wink particle (`hdr:[1.2,1.0,0.9,1]`) at the chest — reads as
    a camera-flash "caught you looking".
  - `sentinel_petal_orbit` (loop, 80t cycle, prewarm 30): cylinder shell r=1.1,
    `shapeArc {arcMode:"Loop", arcSpeed: 0.4}` (emission point orbits),
    `velocityOverLifetime.orbital` y=0.5 AngularVelocity, lifetime 50–70t, petals lit
    by the `lights` module (`blockLight: 10` — a soft fake glow so the pale petals read
    at night without bloom), alpha blend, `vertexSortingMode: DISTANCE`, Local space
    (statue never moves while the loop lives — cheap). `maxParticles: 48`.
- **Attach/trigger**: purely client-side — `DATA_FROZEN` is a **synced** entity flag.
  `PhotonMobFx` watches tracked `PaleSentinelEntity`: rising edge of `isFrozen()` →
  spawn `sentinel_alert` (entity executor, one-shot) AND attach `sentinel_petal_orbit`;
  falling edge (thaw after `UNSEEN_GRACE_TICKS`) → look up the loop executor handle and
  `runtime.destroy(false)` — graceful petal fade, not a pop. Death/burrow: entity
  executor auto-destroy covers death; burrow discards the entity → same cleanup.
- **allowMulti**: both `false` per entity. The freeze flag can strobe at a screen edge
  (hysteresis limits it, but grace is only 5t): the CACHE dedup means a re-freeze while
  petals are still fading simply no-ops into the surviving loop — ideal.
- **Fallback**: existing frozen-hit CHERRY_LEAVES/WHITE_ASH bursts, creak channel and
  freeze pose remain the complete vanilla experience.
- **Budget**: alert 21 particles/10t; orbit ≤ 48 live petals, cull box ±2.5×3, attach
  cap nearest 3 sentinels. `lights` module is a forced lightmap — zero dynamic-light
  cost.

---

### #8 — The Other: dread aura — `eclipse:other_dread_aura`

The doppelganger should feel *wrong* before it is recognized. A slow-breathing aura of
desaturated violet that visibly EATS light around its silhouette — built on the
REVERSE_SUB equation, deliberately NOT on bloom (task caution is correct: bloom is a
bright-pass and cannot bloom darkness; anything dark must come from subtraction).

- **`.fx` spec** (loop, 100t cycle = one 5 s "breath", prewarm 50):
  - `light_eater` (particle_emitter): 6–8 large (0.9–1.3) soft-circle particles hugging
    the body (box Volume shape scaled to the humanoid), material pass 1
    `blendFunc:"REVERSE_SUB"` factors ONE/ONE with a LOW-intensity texture (subtracting
    ~12% luminance where they overlap — subtle dimming shroud, photosensitivity-safe:
    the breath is a 5 s sine, no strobe); `sizeOverLifetime` curve breathes 0.85→1.0→0.85
    across the cycle; `depthTest:1b, depthMask:0b`.
  - `violet_motes` (particle_emitter): 0.4/t desaturated violet motes (ARGB around
    `0x5A4E66`→`0x3A3244` gradient — greyed violet, luminance far below bloom threshold,
    so NO hdr field at all), drift down (negative y velocity — dread falls, not rises),
    lifetime 40t, alpha blend, `shade:0b`.
  - Renderer `orderInLayer` low so the shroud draws before other translucents.
- **Attach/trigger**: `PhotonMobFx` row for `TheOtherEntity`, `AutoRotate.NONE`,
  attach only within 24 blocks (the aura is an up-close read; at distance the
  doppelganger must stay indistinguishable from a teammate — attaching at range would
  *defeat the mob design*, so the attach predicate uses camera distance). Detach
  (destroy(false)) when it leaves the radius; the dawn despawn/death auto-cleans.
- **allowMulti**: `false` per entity.
- **Fallback**: none needed — the mob currently has no ambient FX (by design); Photon
  absence = exactly today's clean mimic. This is also why the aura must stay whisper-
  subtle: it is a garnish for Photon-equipped clients, not a new gameplay tell (the
  24-block gate keeps the long-range mimicry intact everywhere).
- **Budget**: ≤ 8 shroud quads + ≤ 16 motes per Other; 2–3 spawn per Pale Night event →
  ≤ 72 particles world-wide. Cull box ±2×3. Cheapest concept in the batch.

---

### #9 — Gazer: eye-beam telegraph + hypnosis ring — `eclipse:gazer_gaze_beam`

The ambient watcher gets an *almost subliminal* gaze thread: a hair-thin violet beam
from the hood toward the watched player, and a slow counter-rotating ring pulsing
around its head — visible only when you are close and it is already staring at you.

- **`.fx` spec** (loop, 60t cycle):
  - `gaze_thread` (**beam_emitter**): `end:[0,0,-14]` local (−Z = facing), width 0.035,
    near-transparent desaturated violet (`color` gradient brighter at the gazer end,
    fading to nothing toward the player — a thread you *sense*, not a laser),
    `raycast: BLOCKS_AND_ENTITIES` so it clips onto the first thing in the gaze line
    (terrain occlusion for free; it also terminates ON the player's body),
    `emitRate: 0` continuous, `uvAnimation` slow scroll for a shimmering-filament feel.
  - `hypnosis_ring` (particle_emitter): circle shell r=0.45 around the head
    (`facingMode: EMITTER_TRANSFORM_XY` — the ring faces along the gaze),
    `shapeArc Loop` sweep, 0.5/t, lifetime 20t, `rotationOverLifetime` slow, faint
    violet, alpha blend. A second ring child counter-rotates (negative `arcSpeed`).
- **Attach/trigger**: `PhotonMobFx` row for `GazerEntity` with
  **`AutoRotate.LOOK`** — the executor re-orients the whole FX along the entity's look
  every frame, and the gazer's `LookAtPlayerGoal` hood-tracking aims the beam at the
  nearest player with zero extra code. Attach predicate: camera within 20 blocks
  (matches the 12-block whisper-loop intimacy; far gazers stay bare silhouettes).
  Vanish/relocate: `vanish()` discards the entity → auto-destroy; `RelocateGoal`
  teleports keep the SAME entity → the loop snaps with it (correct — the watcher
  re-appears already staring).
- **allowMulti**: `false` per entity.
- **Fallback**: whisper loop + PORTAL/ARM_WISPS vanish burst remain the whole gazer kit.
- **Budget**: 1 beam + ≤ 24 ring particles per gazer; population is ~1 per area by
  spawner design (plus the altar watcher). Raycast beams query per frame — the ONE
  beam per gazer and the 20-block attach gate keep it trivial. Cull box ±16 on the
  beam's own AABB (beam length).
- **Design caution** (why #9 despite the showcase): the gazer's dread IS its
  understatement. The beam must sit at the edge of perception — if playtests read it
  as a "laser telegraph", ship the ring only.

---

### #10 — Backrooms Wanderer: flicker-synced static shroud — `eclipse:wanderer_static_shroud`

The trick that makes this concept: the Backrooms flicker is REAL light
(`BackroomsEventService.tickFlicker` swaps `ochre_froglight ↔ yellow_stained_glass`,
flag 3 relight). Photon's renderer flag `shade: 1b` samples the world lightmap per
particle — so a mono-yellow dust shroud attached to the Wanderer **dims in perfect sync
with every dark window, with zero sync code**. The mob flickers with its corridor.

- **`.fx` spec** (loop, 50t cycle):
  - `paint_haze` (particle_emitter): box Volume around the body, 0.8/t, lifetime
    25–35t, mono-yellow "wet paint" motes (match the texture sheet palette), alpha
    blend, **`shade: 1b`** (the whole concept), `noise` drift, Local space.
  - `static_seams` (particle_emitter): sparse 0.2/t REVERSE_SUB dark flecks with the
    4×4 static `uvAnimation` flipbook (shared texture with #5 — one PNG serves both),
    `shade: 0b` (the static reads even in the dark window — it is the thing that does
    NOT obey the lights).
  - Plus the inherited glitched kit: the Wanderer extends `GlitchedHuskEntity`, so the
    #5 `glitch_pop` blink cue and `glitch_drip` row apply automatically — no extra work.
- **Attach/trigger**: `PhotonMobFx` row for `GlitchedWandererEntity`,
  `AutoRotate.NONE`; the Backrooms dimension gate is implicit (the mob only exists
  there via `BackroomsEventService`'s budgeted pass, cap `WANDERER_CAP`).
- **allowMulti**: `false` per entity.
- **Fallback**: inherited WHITE_ASH/REVERSE_PORTAL static + the real light flicker +
  buzz dip already deliver the scene.
- **Budget**: ≤ 32 haze + ≤ 8 static flecks per Wanderer, capped by `WANDERER_CAP`
  population; cull ±2×3. Photosensitivity: the shroud only *follows* the already-safe
  hashed panel schedule (one dark window per 120–279t) — it adds no new strobe source.

---

## Below the cut (specced, not ranked — deploy only after the loop tier proves out)

### Deckhand soul-flame hats — `eclipse:deckhand_soul_flame`

Every hooded rower on the limbo ghost ship carries a small soul-flame above the hood —
8 quiet candles rowing in the dark; they gutter and flare when `riseHostile` turns the
crew.

- **`.fx` spec** (loop, 40t): `cone` shape r=0.06 angle 8°, emission 1.2/t, lifetime
  10–14t, soul-blue gradient (`0x66CCFF`→`0x2244AA`), tiny sizes 0.05–0.09,
  StretchedBillboard `velocityScale 0.6`, `lights {blockLight: 13}` fake glow, faint
  `hdr:[0.5,0.9,1.4,1]` ONLY on the flame tip material (limbo is dark — a low boost
  reads without blowing out). A `rise` variant burst (flare to 3× emission for 15t) is
  just a second burst-only emitter in the same file with `startDelay` — no second asset.
- **Attach/trigger**: `PhotonMobFx` row for `DeckhandEntity`, offset +0.55 above the
  eye (hood crown), `AutoRotate.NONE`; limbo-only by mob existence. Hostile flare:
  client watches the synced hostile flag / `rise` action state.
- **allowMulti**: `false` per entity. **Fallback**: none needed (garnish; the ship reads
  fine today). **Budget**: ≤ 14 particles × 8 rowers = ≤ 112 live in one scene — the
  single most concurrent loop set in this doc, which is exactly why it sits below the
  cut: land it after #4/#7/#8 loop telemetry looks clean. Cull box ±0.6×1.
- **Why cut from the top 10**: lowest moment-impact per particle (ambience for a scene
  players see briefly), highest concurrent-loop count, and limbo already has a strong
  authored mood; the same effort spent on #1–#3 touches every player every day.

---

## Integration deltas this batch needs (summary)

| Delta | Needed by | Size |
|---|---|---|
| `PhotonBridge.spawnOnEntity(fxId, entity, autoRotate)` + `EntityEffectExecutor`/`AutoRotate` reflection handles (pre-authorized, INTEGRATION §3.5) | #4–#10, deckhand | 1 ctor + 1 enum valueOf + 1 method |
| `PhotonBridge.spawn(...)` overload threading `setDelay(int)` / `setAllowMulti(boolean)` (both verified public on the abstract executor) | #1 (delay), #2/#5/#6 (allowMulti) | 2 reflected setters |
| `veilfx/PhotonMobFx` client attach manager (EntityType table, nearest-N caps, state-edge destroy(false)) | #4, #5, #6, #7, #8, #9, #10 | 1 new client class |
| `FxCues` position cues: `cue/boss_intro_shockwave`, `cue/glitch_pop`, `cue/shadow_bolt_impact`; ONE entity-id cue variant for the hound windup/dash | #1, #5, #6, #4 | registry rows on the existing `fx1` lane |
| Shared static-noise flipbook PNG (`assets/eclipse/textures/particle/static_4x4.png`) | #5, #10 | 1 texture |

Authoring order recommendation: #1 → #2 → #3 (pure one-shots, zero new attach code
beyond the delay/allowMulti setters), then land `PhotonMobFx` with #7 (cleanest synced-
flag edge) as its pilot, then #4/#5/#6, then #8/#9/#10, then the deckhand hats.
Every asset: author in `/photon_editor` (singleplayer), export `.fx` +
commit the `.fxproj` beside it (binary-diff law, FX_FORMAT §7), drop into
`src/main/resources/assets/eclipse/fx/`, verify via the absence of the one-time
`MISSING_FX` INFO and the effect layering over the untouched vanilla/Quasar cue.
