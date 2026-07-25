# Photon .fx Ideas — WAND + PLAYER-ATTACHED effects (PHOTON-IDEAS-3)

Domain: everything that anchors to a **living entity** — wand path identity, power payoffs,
prestige/ghost cosmetics, and the two entity-to-entity showpieces. All specs follow
`API.md` (EntityEffectExecutor semantics), `FX_FORMAT.md` (module schema, templates A/B)
and `INTEGRATION.md` (bridge laws, PhotonFxRegistry). Ten ranked concepts below; shared
bridge prerequisites first, since every concept needs them.

---

## 0. Shared prerequisite — `PhotonBridge.spawnOnEntity` / `stopOnEntity`

`PhotonBridge` today reflects only `BlockEffectExecutor`. INTEGRATION.md §3 point 5
pre-sanctions the extension; every concept in this file rides on it:

```java
// new reflected handles (all verified in the 2.1.5 jar, API.md §1):
Class<?> entityExec = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor");
Class<?> autoRotate = Class.forName("com.lowdragmc.photon.client.fx.EntityEffectExecutor$AutoRotate");
Constructor<?> ctor = entityExec.getConstructor(fxClass, Level.class, Entity.class, autoRotate);
Method start = entityExec.getMethod("start");
// knobs (inherited from FXEffectExecutor): setOffset(Vector3f), setScale(Vector3f),
// setRotation(Quaternionf), setDelay(int), setAllowMulti(boolean), getRuntime()
// stop path: getRuntime() -> FXRuntime.destroy(boolean force)
```

Proposed API (mirrors `QuasarSpawner.ensureAttached/removeAttached` so call sites read
identically):

```java
public static boolean spawnOnEntity(ResourceLocation fxId, Entity entity, String autoRotate);          // one-shot
public static boolean ensureAttachedFx(ResourceLocation fxId, Entity entity, String autoRotate);       // idle loops
public static void   stopAttachedFx(ResourceLocation fxId, Entity entity, boolean force);              // graceful fade default
```

Key executor facts that shape every spec below (API.md §1):

- Root follows **`entity.getEyePosition() + offset`** every render frame → auras that
  should sit at chest/feet need a constant negative-Y offset baked into the executor call
  (e.g. `setOffset(0, -0.9, 0)` for a feet ring on a standing player).
- **Entity death / untrack** → `runtime.destroy(forcedDeath)` + CACHE self-removal is
  automatic. Loops never leak; re-track needs a re-ensure (see dedup notes per concept).
- **Dedup**: `allowMulti=false` (default) makes a repeat `start()` of the same fx id on the
  same entity a silent no-op while alive — this is the *idle-loop keepalive primitive*:
  call `ensureAttachedFx` on a slow cadence (every 20–40 ticks) and dedup guarantees
  exactly one live runtime, self-healing after untrack/re-track. Only stackable one-shots
  ever set `setAllowMulti(true)`.
- **Loop-law note (INTEGRATION.md §4 amendment proposal):** the existing law bans
  *high-frequency Photon cues*. A single long-lived **looping executor** is one spawn +
  dedup'd no-op keepalives — spawn frequency is low even though the visual is continuous.
  The budget discipline moves INTO the asset (`maxParticles` cap + renderer cull box +
  `reducedFx` gate). Concepts below flag which side of the law they sit on.
- **First-person caveat:** the local player's own eye-anchored aura sits inside the camera.
  Idle auras below use a low/forward offset and small sizes; call sites additionally skip
  the ensure for `Minecraft.getInstance().player` while `options.getCameraType().isFirstPerson()`
  (the loop simply re-ensures once the player toggles to F5 — cheap, self-correcting).

Registry integration: player-attached cues need an **entity anchor kind** in
`PhotonFxRegistry.Entry` (INTEGRATION.md already reserves this). Wire cues resolve the
entity client-side (nearest-player match like `FxPayloads.nearestPlayer`, or client-known
state: teams, reveal payloads) — the server stays photon-blind, ids only.

---

## Ranked concepts

### 1. `eclipse:wand_soulbind_flash` — soulbind moment HDR flash  ⭐ flagship one-shot

The path-lock ceremony is the wand's single most important beat and already has a frozen
timeline (`WandPowers.handleChoosePath`: orbit → orbit(+7t) → **flash(+18t)** + sting
downbeat). Photon layers a true HDR bloom pop on the flash tick — the one thing Quasar
cannot do (FX_FORMAT.md §7.1).

- **.fx spec** (one-shot, `looping:0b`, whole tree ~50 ticks):
  - `empty` root `soulbind` →
  - `particle_emitter "core_flash"`: burst 1 @ t0, `startSize` 1.6→(sizeOverLifetime curve
    pop-in 0.2→1.0 in 2t, decay to 0 by 12t), Billboard, `texture` material
    `photon:textures/particle/circle.png` with **`hdr:[2.5,2.2,3.5,1]` ADDITIVE** (white-violet,
    feeds bloom), blend SRC_ALPHA/ONE, `lights{15,15}`, lifetime 12t.
  - `particle_emitter "ring_shock"`: burst 1 @ t1, VerticalBillboard flat ring sprite,
    `sizeOverLifetime` 0.4→3.2 (ease-out curve), alpha gradient →0, hdr [1.2,1.0,1.8,1].
  - `particle_emitter "sparks"`: burst 24 @ t1, sphere shell r=0.3, `startSpeed` rnd
    0.3–0.7, gravity 0.15, `colorOverLifetime` white→path-agnostic violet→0, lifetime 20–30t.
  - `particle_emitter "afterglow"`: burst 1 @ t4, soft smoke texture, alpha-blend, slow
    expand, 30t — covers the bloom falloff so the pop doesn't "cut".
- **Attach:** `EntityEffectExecutor(player)`, `AutoRotate.NONE`, offset `(0, -0.4, 0)`
  (chest/wand height — ceremony holds the wand up). One-shot: entity attach makes the
  flash *ride the player* if they move mid-ceremony, which the block-anchored Quasar cue
  cannot.
- **Trigger:** client-side in `EclipsePayloads.handleQuasar` seam —
  `PhotonBridge.enhanceQuasarCue` gains a row: `S2CQuasarPayload id == wand_soulbind_flash`
  → `spawnOnEntity(WAND_SOULBIND_FLASH, nearestPlayer(pos), NONE)`. No wire change.
- **Dedup:** default `allowMulti=false` is correct — the flash fires once; a duplicate
  payload within its 50t life no-ops harmlessly.
- **Quasar fallback:** existing `wand_soulbind_flash.json` emitter keeps running —
  `Mode.LAYER` (D12 law: Photon is garnish, the Quasar flash is the guarantee).
- **Budget:** ≤ 30 live particles, `maxParticles: 64`, one-shot — zero steady-state cost.
  Sequence-grade: fully inside the existing Photon law. **Impact/risk: best in file.**

### 2. `eclipse:stern_komet` — Kometenschlag descent ribbon + HDR impact  ⭐ flagship power

`castKometenschlag` fakes the descent with two teleported `STERN_KOMET_CORE` re-spawns
(18 → 9 → 0 blocks). Photon replaces the fake with a real falling head dragging an
`ara_trail` ribbon, and an HDR bloom detonation on the impact tick.

- **.fx spec** (one-shot, ~`telegraph+20` ticks; authored as TWO files so timing stays
  server-owned):
  - `eclipse:stern_komet_fall` — root `empty` animated? No: simplest correct form is a
    `particle_emitter "head"` with **one** particle (burst 1), `startSpeed 0`,
    `velocityOverLifetime.linear` Y = curve −1.8 blocks/t easing in (18 blocks over ~14t),
    Model? No — Billboard, hdr [1.8,1.8,2.6,1] white-blue; **`trails` module ON**
    (`trailType: ARA_TRAIL`, `araConfig`: thickness 0.35, time 0.9 s, `alignment: View`,
    `colorOverLength` white→transparent-blue, physics `inertia 0.25, damping 0.8` so the
    ribbon whips) + `subEmitters` `Tick` interval 2 → `eclipse:stern_komet_sparkle`
    (tiny 4-mote glitter burst inheriting position).
  - `eclipse:stern_komet_impact` — HDR core flash (hdr [2.2,2.0,3.0,1]) + vertical light
    pillar (StretchedBillboard, lengthScale 4) + ground ring shock + 30 debris sparks
    with `physics` bounce (chance 0.5, rate 0.35) + slow dome afterglow. `looping:0b`.
- **Attach:** **block executors** (the target is a ground point, not an entity) — listed
  here because the *fall* fx spawns at `target + (0,18,0)` with the descent baked into the
  asset, replacing both re-spawn beats. Impact spawns at `target` with
  `setDelay(telegraph − spawnTick)` so the bloom lands exactly on the damage tick.
- **Trigger:** new `FxCues.CUE_STERN_KOMET` sent once from `castKometenschlag` (replaces
  nothing server-side — Quasar beats keep firing). `PhotonFxRegistry` row, `Mode.LAYER`;
  a/b payload floats carry `telegraphTicks` so the client can `setDelay` correctly.
- **Dedup:** two casts on the same aimed block within one telegraph are legitimate
  stacking → `setAllowMulti(true)` on both files (they are one-shots; CACHE prunes fast).
- **Quasar fallback:** `stern_komet_core` + `stern_funke_fall` (unchanged, always run).
- **Budget:** fall = 1 head + ribbon (~40 ara segments) + ~30 sparkle motes; impact ≤ 80
  particles, `maxParticles: 128`, cull box ±8. L3 power (30 s-class cooldown) — squarely
  sequence-grade.

### 3. `eclipse:heart_theft_arc` — soul-transfer ribbon between victim and killer  ⭐ ceremony showpiece

The theft ceremony (`HeartTheftService.celebrate`) is global titles + bell + one
`HEART_BURST` at the corpse. The missing image is the *transfer*: the victim's heart
visibly flying to the killer. Photon trick: **two entity executors + a timed handoff** —
no single .fx can span two moving entities, so the eye is made to complete the arc.

- **.fx spec** (three files):
  - `eclipse:theft_soul_rise` (on victim, ~20t): burst 1 purple heart-mote (hdr
    [1.6,0.6,1.8,1]), rises 1.2 blocks (`velocityOverLifetime` Y curve), **`trails` ARA_TRAIL**
    thin violet ribbon; + 12 orbiting wisps spiraling INTO the mote (`orbital` +
    negative `radial`).
  - `eclipse:theft_soul_launch` (on victim, fired at +20t): burst 1 mote, `startSpeed 14`
    along **+Z local** with slight up-arc (`forceOverLifetime` Y −0.4 then gravity),
    lifetime ~10t, fat ara ribbon (thickness 0.25, time 0.6 s, `NewerOnTop`) — the comet
    that visibly departs TOWARD the killer.
  - `eclipse:theft_soul_arrive` (on killer): 3t in-suck (16 wisps, negative radial toward
    chest) → burst heart bloom (HDR pop [1.8,0.5,1.5,1]) + soft ring. `looping:0b`.
- **Attach + handoff choreography (all client-side in the handler):**
  1. `spawnOnEntity(theft_soul_rise, victim, NONE, offset(0,-0.3,0))`.
  2. `spawnOnEntity(theft_soul_launch, victim, NONE)` with `setDelay(20)` and
     **`setRotation(quat aiming local +Z at killer)`** — the client knows both entities;
     compute yaw/pitch from `victim.getEyePosition()` → `killer.getEyePosition()` at spawn
     time. The ribbon flies a straight aimed ballistic; for typical kill ranges (< 16
     blocks) the killer barely moves in 10 ticks, so the arc reads true.
  3. `spawnOnEntity(theft_soul_arrive, killer, NONE)` with
     `setDelay(20 + clamp(dist/1.4, 4, 12))` — arrival synced to the ribbon's flight time.
- **Trigger:** new `FxCues.CUE_HEART_THEFT` from `celebrate(...)` — payload pos = victim,
  `a` = killer entity id (float-safe: client re-resolves via `level.getEntity((int)a)`),
  fallback to nearest-player match if unresolvable. Server stays photon-blind (ids only).
- **Dedup:** one-shots; killer-cooldown (45 min) makes stacking impossible in practice —
  keep default `allowMulti=false` as a free double-send guard.
- **Quasar fallback:** existing `HEART_BURST` drift (unchanged, `Mode.LAYER`).
- **Budget:** ≤ 60 particles + 2 short ribbons across ~2 s, then dead. Rarest cue in the
  file — perfect Photon material. Risk: handoff timing needs in-game tuning (killer
  sprinting away stretches the illusion; acceptable — the arrive in-suck re-anchors it).

### 4. `eclipse:riss_schlag_maw` — Rissschlag maw implosion with sub-emitter chain

The maw (`castRissschlag`) is the RISS identity power. Photon adds what Quasar can't:
an **implosion** (debris sucked IN, not blown out) with a `subEmitters` Death-chain.

- **.fx spec** (one-shot, duration = `openTicks` ≈ 25t):
  - `particle_emitter "maw_suck"`: `emissionRate 3/t` on sphere shell r=3.5 →
    **negative `radial` velocity** (−0.9) so streaks fall inward; StretchedBillboard
    (velocityScale 0.6) for datamosh streaking; glitch-cyan/magenta `random_color`;
    `subEmitters: [{fx: eclipse:riss_glitch_pop, event: Death, emitProbability 0.35}]` —
    every swallowed streak *pops* a 3-particle static burst at the lip (the chain ask).
  - `particle_emitter "lip_ring"`: 1 flat ring sprite, `rotationOverLifetime.roll 4°/t`,
    hdr [0.8,1.4,1.6,1], scanline `uvAnimation` (tiles [1,4], SingleRow) for the broken-TV
    read.
  - `eclipse:riss_glitch_pop` (separate file, sub-emitter target): burst 3, 4t life,
    hard additive squares (pixelArt `_enable:1b, bits:4`).
  - Snap-shut beat stays server-timed: a second one-shot `eclipse:riss_maw_snap`
    (single-frame white-cyan HDR slice + 8 outward shards with `physics.removedWhenCollided`)
    spawned with `setDelay(openTicks)` from the same client dispatch.
- **Attach:** block executor at the aimed point (power targets a spot). `AutoRotate` n/a.
- **Trigger:** `FxCues.CUE_RISS_SCHLAG` from `castRissschlag` (pos = target, a = openTicks),
  registry row `Mode.LAYER` over `riss_schlag_maw` + `riss_maw_shimmer` + `riss_seam_scar`.
- **Dedup:** `setAllowMulti(true)` — L3 has a real cooldown but two casters can maw the
  same choke point; both maws must render.
- **Quasar fallback:** existing 4-emitter Quasar composition (unchanged).
- **Budget:** steady ~75 live during the 25t window (3/t × 25t lifetime capped),
  `maxParticles: 160`, cull box ±6. Death-chain probability 0.35 keeps sub-spawns ~25.

### 5. `eclipse:glut_sprung_crater` — Magmasprung eruption with bounce physics + collision sub-emitters

GLUT's L3 is the physicality path — Photon's **real world-collision** module (FX_FORMAT.md
§3.3 `physics`) makes launch/landing debris that Quasar fundamentally cannot do.

- **.fx spec** (one-shot, 50t window):
  - `particle_emitter "magma_chunks"`: burst 14 @ t0, cone (angle 40°, up), speed rnd
    0.5–1.1, `startSize` rnd 0.12–0.28, `physics{_enable, hasCollision:1b, gravity 0.5,
    bounceChance 0.8, bounceRate 0.45, bounceSpreadRate 0.15, collidedFriction 0.6}` —
    chunks arc out, **bounce off real terrain**, settle;
    `subEmitters: [{fx: eclipse:glut_splash, event: Collision, emitProbability 0.5},
    {fx: eclipse:glut_ember_die, event: Death, emitProbability 0.3}]` — every bounce
    splashes (the collision-sub-emitter ask).
  - `particle_emitter "crater_flash"`: 1 HDR orange pop (hdr [2.0,1.1,0.3,1]) + ground
    ring; `particle_emitter "smoke"`: 8 alpha-blend soft smoke, 40t, DISTANCE sorted.
  - `eclipse:glut_splash` (sub-file): burst 5 tiny embers, gravity, 8t, additive.
  - `eclipse:glut_ember_die`: 2-particle fizzle.
- **Attach:** launch = `EntityEffectExecutor(player, AutoRotate.NONE)` offset (0,−1.5,0)
  (feet) — the eruption *departs with the player's launch*, which the block-anchored
  Quasar crater can't show; landing reuses the same file via **block executor** at the
  landing pos (the slam already has a server-known tick in `WandTickService.MagmaJump`).
- **Trigger:** `FxCues.CUE_GLUT_SPRUNG` at cast (entity anchor) + landing slam re-send
  (pos anchor) from `WandTickService.MagmaJump`'s existing payoff seam. `Mode.LAYER` over
  `glut_sprung_crater` + `glut_heat_column`.
- **Dedup:** `setAllowMulti(true)` — launch and landing overlap within 50t on the same
  player/pos by design.
- **Quasar fallback:** existing crater/contrail/scorch composition (unchanged).
- **Budget:** worst case ~60 live (14 chunks + subs + smoke), `maxParticles: 96`.
  **Physics collision is Photon's most expensive module** (per-particle world queries,
  FX_FORMAT.md §9) — 14 colliders is fine; never raise the burst above ~24.

### 6. Per-path idle hand auras — `eclipse:wand_idle_riss` / `_glut` / `_stern`  (the identity loops)

A leveled wand should *read* from across a courtyard. Three tiny looping auras attached to
any player holding an owned, pathed wand. This is the concept that most needs the §0
loop-law amendment — flagged explicitly.

- **.fx specs** (all: `looping:1b`, `prewarm 10`, `simulationSpace: Local` so the aura
  glides with the hand, renderer cull box ±2, `maxParticles ≤ 48`):
  - **RISS — glitch scanline ribbon:** `ara_trail_emitter` (standalone), custom `section`
    = thin 4-vertex strip, `space: Local`, emitter transform slowly orbits via parent
    `empty` (child ribbon inherits) — a 0.5-block scanline ribbon circling the hand;
    `colorOverTime` cyan↔magenta hard steps (`gradient` with tight stops = glitch bands);
    `thicknessOverTime` flickers via 2-segment curve; + 1 `particle_emitter` spitting
    2-px squares (rate 0.3/t, pixelArt material). Photon-only: ara ribbon + pixelArt.
  - **GLUT — ember ring:** `particle_emitter`, cylinder shell r=0.35, `shapeArc {arcMode:
    Loop, arcSpeed 0.6}` (Template B pattern: emission point orbits), rate 0.8/t, life
    20–30t, up-drift 0.02, ember gradient white-hot→deep red→0, hdr [1.3,0.5,0.15,1] on a
    soft dot, `lights{15,15}`. Photon-only: HDR ember glow.
  - **STERN — star halo:** `particle_emitter`, circle r=0.4 tilted 20° via shape
    rotation NF3, rate 0.4/t, near-static motes (`speed 0`), 4-point-star sprite,
    `uvAnimation` 2×2 flipbook twinkle, hdr [1.0,1.0,1.6,1]; + `trails` hairline
    (TRAIL type, width 0.02) so drifting motes draw constellation lines.
- **Attach:** `EntityEffectExecutor(player, AutoRotate.LOOK)` — LOOK keeps the ring
  oriented to the facing so it hugs the hand side; offset `(0.35, -0.45, 0.4)` in the
  rotated frame ≈ main-hand position. First-person: skip local ensure (see §0).
- **Trigger:** **pure client-side, zero wire.** The client already knows everything:
  a client tick handler (new `client/wand/WandAuraClient`, 20t cadence) scans visible
  players' held items for `EclipseWandItem` + `WAND_PATH` component (components sync to
  all trackers) → `ensureAttachedFx(idle fx for path, player, LOOK)`; wand unequipped/path
  NONE → `stopAttachedFx(..., force=false)` (graceful fade).
- **Dedup:** THE showcase for default `allowMulti=false`: the 20t ensure is a silent
  no-op while the loop lives; untrack→re-track self-heals on the next ensure. Never set
  allowMulti here — two stacked auras is the failure mode.
- **Quasar fallback:** none today (idle auras don't exist) → registry `Mode.REPLACE` with
  `quasarEmitter = null`; photon-less clients simply see no idle aura (pure additive
  cosmetic, degradation law satisfied). Optionally later: a 1-particle vanilla sparkle.
- **Budget:** ≤ 30 live per player, ~5 visible wand-holders worst case ≈ 150 particles —
  but this is the loop-law edge: gate behind BOTH `photonFx` and a new client toggle
  `wandAuras` (default on), and hard-cap the ensure scan to the 8 nearest players.

### 7. `eclipse:rebirth_aura` — prestige ribbon orbit, tier-scaling  (keepsake upgrade)

`RebirthAuraService` ships a 3-point WITCH-particle ring (server vanilla particles).
Photon tier: a silk-thin violet **ara ribbon** orbiting the feet — the "I've been through
the fire" halo. Tier-scales with rebirth count.

- **.fx spec:** `empty` root spinning (authored transform animation? No — use ribbon
  physics instead): `ara_trail_emitter`, `space: World`, segment `time 1.2 s`,
  thickness 0.06, `colorOverLength` violet→transparent, `physicsSetting {inertia 0.35,
  damping 0.7}` — the emitter object itself is orbited by a parent `particle_emitter`?
  Cleanest verified pattern: a single-particle emitter (burst 1, infinite re-burst per
  cycle) with `velocityOverLifetime.orbital` Y = 0.55 rad/t around offset (0,0,0) and
  `trails ARA_TRAIL` — the orbiting invisible mote drags the ribbon circle. Plus a
  2nd emitter: sparse rising motes (rate 0.15/t, witch-purple, alpha blend).
  Tier variants: **one file, executor `setScale`** — t1 scale 1.0 / t2 1.15 + second
  ribbon enabled? Scale can't add ribbons, so ship `rebirth_aura_1/2/3` (counts 1/2/3
  ribbons at phase offsets; 3 = subtle gold `hdr [1.2,1.0,0.5,1]` tint on the third).
- **Attach:** `EntityEffectExecutor(player, AutoRotate.NONE)`, offset `(0, -1.45, 0)`
  (eye→feet), `simulationSpace`/ribbon `World` so the ribbon lags beautifully when the
  player walks (the physics module is the whole point).
- **Trigger:** client-side ensure like concept 6, driven by synced rebirth state
  (`S2CRebirthStatePayload` / `ClientRebirthState` already exists for the local player;
  OTHER players' counts aren't synced today — v1 scope: **local player only in F5 +
  others see it only if a tiny `rebirthCount` byte is added to an existing sync**; the
  aura-off toggle `/skills aura on|off` must also gate the Photon leg — mirror
  `RebirthState.Entry#auraEnabled` client-side via the same payload).
- **Dedup:** ensure-cadence + default dedup (one aura). Tier change (new rebirth) =
  `stopAttachedFx(old, force=false)` then ensure the new id — ids differ per tier, so
  dedup never blocks the upgrade.
- **Quasar fallback:** the existing WITCH ring **keeps running for everyone** (it's
  server-side vanilla, all clients see it) → registry `Mode.LAYER`; on Photon clients the
  ring + ribbon coexist (the ring reads as "sparks off the ribbon"). No double-loop risk:
  different systems.
- **Budget:** 1–3 single-particle orbiters + ribbons (~30 segments each) + ~4 motes.
  Tiny. Loop-law: same gating as concept 6.

### 8. `eclipse:contract_mark` — hunter's target-locked pulse ring

During an ACTIVE REAL contract the hunter knows the target (`S2CContractRevealPayload`,
hunter-only by the anonymity law). A Photon pulse ring on the target — **rendered only on
the hunter's client** — turns the hunt from GPS-text into sightline drama.

- **.fx spec** (`looping:1b`, duration 30t/cycle): `particle_emitter "lock_ring"`:
  burst 1/cycle flat ring sprite at feet, `sizeOverLifetime` 0.6→1.8 expanding +
  alpha→0 (sonar ping), blood-orange, hdr [1.4,0.6,0.2,1]; `particle_emitter "crown"`:
  2 near-static chevron sprites over the head (offset via shape position NF3 (0,2.2,0)),
  slow `rotationOverLifetime.yaw`; cadence reads as a heartbeat (two pulses per 30t via
  bursts at t0 and t6).
- **Attach:** `EntityEffectExecutor(targetPlayer, AutoRotate.NONE)`, offset `(0,-1.4,0)`.
- **Trigger:** client-side on the HUNTER only: `ContractPayloads.handleReveal`
  (ROLE_HUNTER) stores the target UUID (already does, for `ContractRevealOverlay`);
  a 20t ensure scans `level.players()` for that UUID → `ensureAttachedFx`. Window
  end / resolve payload (`S2CContractResolvePayload`) → `stopAttachedFx(force=false)`.
  **Never** spawn on other clients — the mark must not leak the target's identity
  (anonymity law, ContractPayloads javadoc).
- **Dedup:** ensure + default dedup; target untracked (out of render distance) →
  executor auto-dies → re-ensure re-attaches on re-track. Exactly the CACHE lifecycle
  the API doc promises.
- **Quasar fallback:** none (feature doesn't exist) — `Mode.REPLACE`, null Quasar leg;
  photon-less hunters keep today's overlay-only experience.
- **Budget:** ≤ 6 live particles. Trivial. Loop-law: single-entity, hunter-client-only —
  the cheapest loop in the file.

### 9. `eclipse:ghost_wisp` — spectral wisp for Limbo ghosts

Banned players become "green ghosts" (`BanService`: ghost team + glowing, adventure mode,
Limbo). A cold spectral wisp loop attached to every ghost makes the state read as *lore*
instead of a potion effect.

- **.fx spec** (`looping:1b`, prewarm 15): `particle_emitter "wisps"`: rate 0.5/t,
  sphere r=0.5 volume, life 30–45t, up-drift 0.015 + `noise{frequency 0.6, position 0.08}`
  (organic float), pale-green→cyan gradient, alpha-blend soft dots, DISTANCE sort;
  `particle_emitter "core"`: 1 persistent mote at chest, faint hdr [0.5,1.0,0.8,1] pulse
  via `colorOverLifetime` on a 40t cycle; optional hairline `trails` on 20 % of wisps
  (`ratio 0.2`).
- **Attach:** `EntityEffectExecutor(ghost, AutoRotate.NONE)`, offset `(0,-0.6,0)`.
- **Trigger:** pure client-side, zero wire: the ghost team is client-visible —
  20t ensure over `level.players()` where
  `player.getTeam() != null && "eclipse_ghosts".equals(player.getTeam().getName())`
  (constant `BanService.GHOST_TEAM_NAME`). Team leave → `stopAttachedFx` graceful.
  Bonus: the local ghost's own `S2CGhostStatePayload` grade (`EclipseFxState.setGhost`)
  stays untouched — this concept is the THIRD-person view of the same state.
- **Dedup:** ensure + default dedup, identical lifecycle to concept 8.
- **Quasar fallback:** none (vanilla glowing outline remains the guaranteed signal) —
  `Mode.REPLACE`, null leg.
- **Budget:** ~20 live per ghost; ghosts are rare and Limbo-confined (own dimension —
  overworld players never pay for it). Cull box ±2.

### 10. `eclipse:glide_trail` — ara_trail ribbon for the edge-glide

The glide FX (`FX_GLIDE_START/STOP` → `QuasarSpawner.ensureAttached(glide_trail)`) is a
working loop today. The Photon upgrade is a real physics ribbon off each hand — but this
is the LOWEST rank because the Quasar version already reads well and INTEGRATION.md
explicitly lists "glide trails" as the example of what NOT to give a Photon leg.
Included because the event-edge trigger (start/stop, not per-tick) actually satisfies the
law's intent — spawn frequency is low; judgement call for the implementer.

- **.fx spec:** two `ara_trail_emitter` objects under offset `empty` nodes (±0.5 X =
  wingtips), `space: World`, `alignment: Velocity`, thickness 0.12,
  `thicknessOverLength` taper curve →0, cool white-blue `colorOverLength` fading out,
  `physicsSetting {inertia 0.3, velocitySmoothing 0.8, damping 0.7}` — ribbons sag and
  snap in turns; `timeInterval 0.05, time 0.8 s`; + one 0.2/t sparkle emitter.
  `looping:1b` (ara emit is continuous while alive).
- **Attach:** `EntityEffectExecutor(glider, AutoRotate.FORWARD)` — FORWARD keeps the
  wingtip offsets tracking the flight vector (the one concept where AutoRotate ≠ NONE is
  load-bearing). Offset `(0,-0.3,0)`.
- **Trigger:** the existing client seam, one line each: `FxPayloads.handleFxEvent`
  FX_GLIDE_START branch adds `PhotonBridge.ensureAttachedFx(GLIDE_TRAIL_FX, glider,
  FORWARD)`; FX_GLIDE_STOP adds `stopAttachedFx(..., force=false)` (graceful — the ribbon
  tail dissolves naturally, exactly what `destroy(false)` is for).
- **Dedup:** default dedup; repeated START events while gliding no-op. STOP always stops
  (CACHE scan by fx id + entity).
- **Quasar fallback:** existing `glide_trail` Quasar loop — `Mode.LAYER` but the honest
  recommendation is **REPLACE** (two trails = mud; Photon spawn-failure re-enters the
  Quasar leg automatically per registry law 2).
- **Budget:** 2 ribbons ≈ 60 GPU segments + sparkles; only while airborne on sanctum
  ledges. Cull box generous (±4 — ribbons trail).

---

## Cross-cutting notes

- **Authoring order:** 1 → 2 → 3 first (pure sequence-grade, zero law friction, biggest
  wow); 4 → 5 next (power identity); 6 → 10 only after the loop-law amendment + the
  `wandAuras`-style client toggles land.
- **All triggers are client-resolved** — no payload carries a Photon reference; the four
  new `FxCues` ids (`CUE_STERN_KOMET`, `CUE_HEART_THEFT`, `CUE_RISS_SCHLAG`,
  `CUE_GLUT_SPRUNG`) are plain fx-lane sends, and concepts 6/7/8/9 need **no wire at all**
  (components, teams, reveal payloads, rebirth sync already give the client the truth).
- **Every loop concept** (6–10) must register with the disconnect/world-unload sweep the
  bridge will need (mirror `QuasarSpawner`'s clear-all; Photon's own level-change mixin
  clears the engine, but our ATTACHED bookkeeping map must reset too).
- **Commit the `.fxproj` next to every `.fx`** (binary-diff law, FX_FORMAT.md §7).
