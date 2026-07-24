# IDEA-16 — Boss Fight Spectacle (Eclipse Event, wave 4, collector 16/20)

Scope: Herald, Ferryman, Rift Warden, Fog Tyrant — `entity/boss/`, `client/entity/`.
All four bosses share the "house fight chassis" (scripted `tick()`, synced
`DATA_PHASE`/`DATA_TELEGRAPH`, `updatePhase` one-transition-per-call, scripted
`tickDeath`, participant roster, `LOGGER.info` breadcrumbs). Every idea below rides
existing seams; effort is S (hours, one file cluster) or M (a day-ish, new payload or
block bookkeeping). All client flourishes must respect `EclipseClientConfig.reducedFx()`
and the Iris gate (`EclipseIrisState.postFxAllowed()`) where post FX are involved.

---

## 1. Boss intro title cards with GlitchText decode — M

The name arrives corrupted and resolves. On summon, each boss fires a new
`S2CAnnouncePayload.STYLE_BOSS_INTRO`; the client renders a centered card (above the
`AnnouncementOverlay` sweep) whose title starts as `GlitchText.scramble(len, salt)` and
locks in one real character every 2t, left to right (salt = entity id so two viewers
don't sync). Subtitle line ("Day-7 Boss — The Broken Godhead") uses the existing
`TypewriterLine`.

- **Hooks:** send from `HeraldEntity.summon`, `FerrymanEntity.summon`,
  `RiftWardenEntity.summonAt`, `FogTyrantEntity.summonAt` (all already have arrival-FX
  blocks) via `timeline/AnnouncementService`; client work in
  `client/hud/AnnouncementOverlay.start` + a new `BossIntroCard` layer stacked with
  `BossbarSkin.drawThemedBar(theme=THEME_BOSS)`; scramble from
  `client/handbook/GlitchText.scramble` (already reducedFx-aware — falls back to a
  static `???` run).
- **Why ranked #1:** one payload style + one overlay covers all four bosses at once;
  highest spectacle-per-line-of-code in this list.

## 2. Phase-transition arena transformations — M

Each phase break physically re-dresses the ring, not just a roar. All three land in the
existing `updatePhase(...)` phase-branch blocks, which already play sound/shake there:

- **Herald P3 (33%):** the dais cracks — ring of SOUL_FIRE_FLAME jets every 8t from
  `arenaCenter` at r=4/8/12 plus a persistent low purple haze column (add to the
  `phase == 3` branch in `HeraldEntity.updatePhase`, alongside the existing
  `BOSS_SLAM`). Particle-only: no restore bookkeeping.
- **Rift Warden P2 (50%):** the arena wall becomes a visible rift — upgrade
  `RiftAnchor.particleWall` with a `phase` param: REVERSE_PORTAL density ×3 + END_ROD
  streaks arcing over the ring (call site: `RiftWardenEntity.tickArenaLock`).
- **Fog Tyrant P2/P3:** the storm closes in — `FogTyrantArena.particleWall` gains a
  `severity` param; P3 adds intermittent visual-only `LightningBolt`s ON the ring wall
  (reuse the `releaseCrownLightning` visual-only pattern, zero damage).

Block-edit variants (e.g. actually cracking dais blocks) must copy the Ferryman
`placedWater`/`restoreShip` tracked-edit + NBT persistence pattern — that pushes any
block version to M+; the particle versions above are safe M.

## 3. Death "slow-motion" + staggered loot ceremony — M

The kill should feel like a held breath. Two halves:

- **Client slow-mo illusion (no tick manipulation):** the Herald already eases
  `animSpeed` in `tickClientAnim`; extend all four to ease animation speed toward ~0.2
  while `deathTime > 0` (`HeraldEntity.tickClientAnim`, `FerrymanEntity.tickClientAnim`;
  Geo bosses via a `deathTime`-aware speed in `client/entity/geo/EclipseGeoRenderer`).
  Add one long soft `CameraDirector.addShakeImpulse(0.15F, 40, lowFreq)` at kill for the
  dreamlike drift. True server slow-motion (tick freeze) is NOT recommended — multiplayer
  and the finale handoff (`FinaleRitual.beginVictory`) would stall.
- **Loot ceremony:** today `dropCustomDeathLoot` dumps everything at t=0 of the collapse.
  Move the per-participant shard payouts into `tickDeath` keyframes (e.g. Herald
  deathTime 20/35/50): each payout drops at the player's feet with a
  `S2CQuasarPayload.HEART_BURST` + amethyst chime, so the collapse doubles as an award
  sequence. The corpse-drop core item stays in `dropCustomDeathLoot` (fires from
  `die()`, guaranteed-once semantics untouched — keep the "runs exactly once" contract
  documented on `die`).

## 4. Health-threshold sky reactions (sky flickers at 50%) — M

The eclipse itself reacts to the fight. Add a tiny `S2CSkyPulsePayload(ticks, strength)`
sent from each boss's `updatePhase` (and once at 50% HP for the 2-phase Rift Warden);
client keeps a static decay timer (`SkyPulseState.trigger(ticks)`) consulted by the
existing sky stack: `client/sky/OverworldFogTint` darkens/brightens the fog tint on a
4t flicker, `StarField` jitters star brightness, `client/drama/HorizonLightning` fires
one horizon arc. Bosses fighting under the open eclipse sky (Herald, Fog Tyrant) get the
full effect; Limbo (Ferryman) routes to `LimboSpecialEffects` for a lantern-light
shudder instead. Must no-op when `EclipseIrisState.shaderPackActive()` (sky is
pack-owned then) and under `reducedFx`.

## 5. Post-kill trophy placement at the arena center — S

A permanent monument where the boss fell. At the end of the scripted death
(`HeraldEntity.shatter`, `RiftWardenEntity.implode`, `FogTyrantEntity`'s
`DEATH_THUNDERCLAP_TICK` block, `FerrymanEntity.tickDeath` final-bell tick), place a
1-block marker at the tracked center (`arenaCenter` / `anchor.center()` /
`arena.center()` / stern anchor): amethyst cluster on the dais (Herald), sealed
obsidian+end-rod pillar (Rift Warden), lightning rod (Fog Tyrant), a lit soul lantern
at the stern (Ferryman — survives `restoreShip` since restore only sweeps water).
Air-check before placing; gate on the `EclipseWorldState` defeat flags so re-summons
don't stack monuments. Optional M upgrade: an `ItemDisplay` entity showing the boss's
trophy item (loot tables already flavor "trophy" drops) rotating above the block.

## 6. Bossbar phase-break shatter flourish — S

When the synced phase increments, the boss-theme HUD bar visibly breaks: the client
`BossbarSkin` boss skin (already themed via `S2CBossbarStylePayload.THEME_BOSS` sent in
every `startSeenByPlayer`) plays a 10t white-hot glow spike (the existing `glowAlpha`
param of `drawThemedBar`) plus 6–8 falling 2×2 px fragments from the notch position.
Detect the break client-side by watching the tracked bossbar progress cross 2/3 / 1/3 /
1/2 (or the entity's `getPhase()` when in render distance) — zero new network traffic.
Covers all four bosses in one file.

## 7. Renderer flourishes for already-synced-but-unused flags — S

Two invited hooks are sitting idle:

- `FogTyrantEntity.DATA_ENRAGE_STACKS` is synced "for future renderer/P2 flourish
  hooks" — make `FogTyrantRenderer`'s glowmask pulse frequency scale with
  `getEnrageStacks()` (0 = slow breathe, 5 = strobing), and tint the crown glow toward
  red at max stacks (`EclipseGeoRenderer` exposes the emissive pass).
- `RiftWardenEntity.DATA_STAGGERED` — during the P2 weakpoint window, flare the rift
  half's glowmask to full and add a slow 0.95→1.0 scale throb in `RiftWardenRenderer`
  so "hit me now" reads at a glance (server already sparks END_ROD, but the body itself
  should scream it).

## 8. Marked-player spotlight for the Gaze mechanics — S

Herald P2 gaze and Ferryman Lantern Gaze are private to the victim
(`S2CShakePayload.mark` → `MarkVignetteOverlay`); teammates can't see who to peel for.
Add a third-person tell: while a gaze/mark is active, the server drops an
`S2CQuasarPayload.ALTAR_BEAM` (or a thin END_ROD column, 2 blocks tall) at the marked
player every 20t. Hooks: `HeraldEntity.tickGaze` (charge loop already runs every-2t
particle code) and `FerrymanEntity.tickGaze` mark-begin/refresh. Pure server-side
particles — no client work at all.

## 9. Summon fly-by letterbox cutscene — M

A 3-second skippable orbit around the freshly-summoned boss: `CutscenePath` +
`CameraDirector.handlePlay` + `LetterboxLayer` already exist (the Ferryman finale uses
the full stack, including its `SPAWN_GRACE_TICKS` freeze pattern). Add a compact
"boss_reveal" path (orbit r=8, rise 4 blocks, end at the player's own camera) triggered
from `HeraldEntity.summon` / `RiftWardenEntity.summonAt` / `FogTyrantEntity.summonAt`
for players inside `SCALING_RANGE`. Pair with idea #1's title card. Keep the Herald's
grace: reuse the Ferryman `spawnGraceTicks` idea (hold attacks ~60t) so nobody gets
volleyed mid-cutscene — that's the only entity-side change.

## 10. Sub-10% arena heartbeat crescendo — S

When the boss drops below 10% HP, every participant hears an accelerating heartbeat and
the arena wall pulses in sync. Server-only: in each `tickFight`, when
`getHealth()/getMaxHealth() < 0.10`, send `WARDEN_HEARTBEAT` to `livingParticipants`
every 30t → 20t → 12t as HP falls (Herald already has the private-sound plumbing:
`sendPrivateHeartbeat` via `ClientboundSoundPacket`), and double the arena-wall particle
cadence in the same window (`tickArenaLock` / `RiftAnchor.particleWall` /
`FogTyrantArena.particleWall` call sites). Throttle like the existing
`DEFLECT_CUE_INTERVAL_TICKS` pattern.

---

### Ranking rationale

1–3 are the marquee "spectacle" wins (intro, mid-fight, death — the full arc), 4–5 make
the world remember the fight, 6–8 are cheap high-read polish on existing synced state,
9 is the most expensive and depends on 1, 10 is the cheapest tension-builder.

### Cross-cutting constraints observed in code

- Never leave stuck synced flags: every phase break / death already calls
  `setTelegraphing(false)` / `clearTelegraphs()` — new flags must follow.
- Block edits require tracked restore + NBT persistence (Ferryman `placedWater` is the
  only sanctioned precedent).
- `die()` runs exactly once; `tickDeath` may run on both sides — server-only work needs
  the `level() instanceof ServerLevel` guard all four bosses already use.
- Client FX: gate on `reducedFx`, and sky/post work additionally on
  `EclipseIrisState` (`shaderPackActive` / `postFxAllowed`).
