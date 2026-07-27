# PLAN F-081…F-087 — Storm-Boss Rework (statue trigger, death reset, storm independence, display cleanup, grave protection)

Status: PLAN ONLY (read-only audit performed 2026-07-27; no code changed).
Scope: `ProjectEclipse/src/main/java/dev/projecteclipse/eclipse/…` (NeoForge 1.21.1, Mojang mappings).
All file paths below are relative to `ProjectEclipse/`.

Feedback rows covered (from repo-root `UserFeedback.md`):

| # | Feedback (paraphrased) |
|---|---|
| F-081 | Storm boss fight starts only when players HIT A STATUE inside the storm — not by mere presence |
| F-082 | Death during the storm boss fight ⇒ fight resets (boss despawns/heals, arena pre-fight); graves survive untouched |
| F-083 | Storms decoupled: every storm spawns its own boss independently (no "boss A before boss B") |
| F-084 | Stuck BlockDisplays after dying in the storm fight are reliably cleaned up (also across restarts) |
| F-085/086/087 | Grave protection: bosses can neither move nor destroy graves (explosions, block throws, storm suction); wand spells never damage graves |

---

## 1. Current-state map

### 1.1 File → responsibility

| File | Responsibility |
|---|---|
| `…/worldgen/fog/FogStormSites.java` | Frozen fog-storm site table (`fogstorms.json` per save), grove materialization, persisted per-site lifecycle (`EclipseWorldgenState.FogSiteState`: chests/placed/active/recovered), `stormEnded()` retirement + snow recovery, **`reconcileTyrantLair()` — the single-lair gate (see §1.3)** |
| `…/stormfx/StormRegistry.java` | In-memory server registry of storm walls/vortices/spheres; stable per-site storm id (`siteStormId`); `spawnSphere`/`dissipate`/`explode`; polls `FogStormSites.sites()` and stands SPHERE domes over active sites; login/respawn/dimension resync |
| `…/stormfx/StormSiege.java` | The F-031 siege orchestrator: poll-detects a living `FogTyrantEntity` inside an ACTIVE sphere storm → client overlay payload (`S2CStormSiegePayload`, storm grows ×1.3), 80–150 orbiting whirl `Display.BlockDisplay`s (tag `eclipse_storm_siege_debris`), block-lift volleys that tear 3–6 REAL blocks out of the ring and fling them at players; victory-fling / abandon-sink endings; join-time stray sweep; `LIVE_DISPLAYS` UUID set |
| `…/stormfx/StormReveal.java`, `StormFxClient.java`, `StormPhotonFx.java`, `StormInteriorFx.java`, … | Client/FX side of storms: reveal choreography, volumetric far-field (Veil), Photon near-field loops (`storm_debris_belt`, `storm_cloud_belt`, `storm_skirt_dust`, authored by `tools/photon/build_storm_fx.py`) |
| `…/entity/boss/fog/FogBankMarker.java` | Session-only lair list per dimension; ambient smoke-pillar dressing; **current fight trigger: player within `TRIGGER_RANGE = 20` blocks → `FogTyrantEntity.summonAt` and the lair disarms** |
| `…/entity/boss/fog/FogTyrantEntity.java` | The boss (Herald-chassis scripted `tick()`): `summonAt` (64-block dedup), `initFight` (arena pin + player-count HP scaling), `updateParticipants` (arena entry → roster, persisted in NBT), `tickReset` (abandon: no player within `RESET_RANGE = 24` for `RESET_TICKS = 1200` → heal + `discardTaggedAdds` + `discard()`), outside-arena damage deflect, adds tagged `eclipse_tyrant_add`, 70t scripted death (`tickDeath`) → `explodeHostStorm` (`StormRegistry.explode` + `FogStormSites.stormEnded`) + reward chest |
| `…/entity/boss/fog/FogTyrantArena.java` | Arena math r=16 (deflect/clamp) + r=18 leash impulse + particle wall; NBT persisted so restarts resume the exact ring |
| `…/entity/boss/fog/FogBossEntities.java` | `DeferredRegister` for `eclipse:fog_tyrant` (family-owned registrar; `isBound()` no-op guards) |
| `…/entity/fog/…` (`FogEntities`, `StormHoundEntity`, `FogColossusEntity`, `GroundSlamGoal`, `FogEliteEntities`) | Storm adds (hounds, colossus). Audit: **no block writes** in this package (verified by grep — no `setBlock`/`destroyBlock`/`explode`) |
| `…/sequence/StormDebrisFx.java` | Intro-cutscene debris swarm; the "despawn guarantee" doctrine this plan extends: command tag + live-UUID set + join sweep + watchdog + `/kill @e[tag=…]` |
| `…/worldgen/stage/DisplayBrightnessFx.java` | Display brightness/view-range helper reused by all display spawners |
| `…/lives/GraveBlock.java` | Grave block (`BaseEntityBlock`, strength 1.5 / **blast resistance 6.0**, `noLootTable`); `onRemove` scatters stored items and unregisters from the dowser index — ANY removal path scatters instead of voiding |
| `…/lives/GraveBlockEntity.java` | Stored drops + owner UUID + created time; owner opens anytime, others after grace; self-scatters after 3× grace |
| `…/lives/LifecycleEvents.java` | Death economy: heart loss, `onLivingDrops` places the grave at the death position and registers it in `EclipseWorldState.addGravePosition` (W13 dowser index) |
| `…/lives/DeathFlowHooks.java` | Ship-respawn theater layered on top; respawn teleports the player to the limbo deck, then home — i.e. after a storm-fight death the player leaves the arena chunks quickly |
| `…/core/state/EclipseWorldState.java` | SavedData: `gravePositions` map (owner → `List<GlobalPos>`), `add/removeGravePosition`, `getGravePositions` |
| `…/wand/WandSpells.java`, `WandSpellEffects.java`, `WandPowers.java` | The 30-spell registry + execution. Audit: **the live spell set performs zero world block writes** (F-038 replaced the only block-writing spell); damage goes through `WandPowers.damageAround` (entity-only, `igniteForSeconds` on entities, never terrain) |
| `…/wand/WandPhaseService.java` | RETIRED Phasenwelle journal drain — the only historical spell block writer; its hard blacklist already excludes ALL block entities (graves qualify) |
| `…/woah/mansiondome/MansionDomeProtection.java` | House pattern for zone protection: `BlockEvent.BreakEvent`/`EntityPlaceEvent` cancel + `ExplosionEvent.Detonate` affected-block pruning + `DevMode` exemption |
| `…/protection/SpawnProtectionRules.java` | House pattern for `EntityMobGriefingEvent` / interaction filtering |
| `…/woah/gravityrift/GravityRiftService.java` | House pattern for a HIT TRIGGER: tagged `minecraft:interaction` hitbox spawned via NBT, `AttackEntityEvent` + `PlayerInteractEvent.EntityInteract` filtered by command tag, event cancelled, self-heal respawn of the hitbox |
| `…/worldgen/structure/WatcherStatues.java` | House pattern for a REAL-BLOCK statue build (obsidian watcher, ~7 blocks on a plinth) |
| `…/entity/boss/FerrymanEntity.java` + `…/ferryman/ArenaFight.java` | House pattern for **wipe detection**: `checkWipe()` = every online participant dead/spectator/banned → announce, restore arena, heal, despawn |
| `…/network/fx/FxCues.java` + `FxPayloads.java` | Server→client Photon cue dispatch (`sendFxEvent`/`sendFxEntityEvent`); boss cues like `CUE_TYRANT_SQUALL`, `CUE_TYRANT_FOG_ARMS` live here |

### 1.2 How a fight starts today (trigger chain)

1. `FogStormSites` materializes/restores a site → site `active=true` → `StormRegistry.pollFogSites` stands a SPHERE storm over it.
2. `FogStormSites.reconcileTyrantLair(level)` (called from materialize-complete, `stormEnded`, stage rollback, `restoreFromState`) clears ALL lairs and marks **exactly one**: the active site with the highest stage (ties by id) → `FogBankMarker.markLair(level, center)`.
3. `FogBankMarker.onServerTick` (every 40t): any live non-spectator player within **20 blocks** of the lair center → `FogTyrantEntity.summonAt(level, lair)`; the lair entry is removed (disarmed).
4. `FogTyrantEntity.summonAt` dedups against a live tyrant within 64 blocks, pins the r=16 arena, scales HP by players within 32 blocks.
5. `StormSiege.detectFights` (every 20t) sees a living tyrant inside an ACTIVE sphere storm → starts the siege (storm growth overlay, whirl displays, block lifts).

**Presence alone starts the fight — this is what F-081 replaces.**

### 1.3 The F-083 ordering gate (exact location)

`…/worldgen/fog/FogStormSites.java`, method **`reconcileTyrantLair(ServerLevel)`** (lines ~227–237):

```java
FogBankMarker.clearAll(level);
sites.stream().filter(Site::active)
        .max(java.util.Comparator.comparingInt(Site::stage).thenComparing(Site::id))
        .ifPresent(site -> FogBankMarker.markLair(level, surfaceCenter(level, site.x(), site.z())));
```

Exactly ONE active site ever hosts a lair ("exactly one active highest-stage storm hosts the Fog Tyrant lair", per its javadoc). The next storm only receives a lair after `stormEnded()` (boss defeat) re-runs the reconcile with the defeated site now `active=false`. That is precisely the observed "boss A must die before storm B gets its boss".

Secondary couplings to keep in mind (no change needed if sites are >64 blocks apart, which grove sites are):
- `FogTyrantEntity.SUMMON_DEDUP_RANGE = 64` — a summon near another live tyrant returns the existing one.
- `FogBankMarker.LIVE_TYRANT_RANGE = 48` — lair trigger suppressed near a live tyrant.
- `StormSiege.SIEGES` is keyed by storm id and `detectFights` scans per storm — already multi-fight capable.
- `FogTyrantEntity.findHostSiteId` picks the nearest containing active site — already multi-fight capable.

### 1.4 What happens on player death today (F-082 gap)

- `LifecycleEvents.onLivingDeath` (hearts) → `LifecycleEvents.onLivingDrops` places the **grave at the death position** (often inside the arena) → `DeathFlowHooks` teleports the respawned player to the limbo ship, then to their real respawn point — the arena chunks typically drop out of player range within seconds.
- The boss does **nothing special on participant death**. There is no wipe check (unlike `FerrymanEntity.checkWipe`). The only reset is the abandon timer: no live player within 24 blocks for 1200t (60 s) → heal, discard `eclipse_tyrant_add` adds, despawn. The boss keeps his damage for that whole minute, and if any player rushes back within 60 s the fight continues from where it was — no reset.
- **Found gap G-1 (re-arm bug, feeds F-081/F-082):** after the abandon reset despawns the tyrant, NOTHING re-marks the lair — `reconcileTyrantLair` only runs on site lifecycle changes, and `FogBankMarker.tickLair` removed the lair entry at summon time. In the current build a reset fight can never restart until a server restart re-runs `restoreFromState`. The statue re-arm design below fixes this explicitly.

### 1.5 Display-entity lifecycle today and the F-084 leak

`StormSiege` doctrine (good bones): every display carries the tag `eclipse_storm_siege_debris`, its UUID is recorded in the session set `LIVE_DISPLAYS`, `onEntityJoin` discards any TAGGED joiner NOT in the set (crash strays after restart), a 30-min watchdog force-abandons a wedged siege, and `/kill @e[tag=eclipse_storm_siege_debris]` always works.

**Found gap G-2 (the actual stuck-display bug):** displays are normal persistent entities. When the dead player is whisked away (§1.4) the arena chunks unload; each display entity is *unloaded-to-chunk* (`isRemoved() == true`, saved to disk, **UUID still in `LIVE_DISPLAYS`**). Then:

- `Siege.animateWhirl()` prunes pieces whose display `isRemoved()` from `this.whirl` **without** removing their UUIDs from `LIVE_DISPLAYS`; `discardAll()` later never sees them.
- `Siege.tickLifts()` similarly drops lifts whose display `isRemoved()` — the torn-out REAL block is silently lost too.
- When the chunk reloads (same server session), `onEntityJoin` **adopts** the display (its UUID *is* in `LIVE_DISPLAYS`) — but no siege animates it anymore → a block display frozen mid-air forever. Only a full server restart (clearing `LIVE_DISPLAYS`) plus revisiting the chunk sweeps it. This matches the report exactly ("nach Tod bleiben BlockDisplays für immer stehen").
- Additional small leak: `onServerStopped` clears `LIVE_DISPLAYS`, so the restart join-sweep works — but only when the chunk is actually loaded again; nothing proactively sweeps.

### 1.6 Grave representation + current protections

- Representation: **one block** `eclipse:grave` (`EclipseBlocks.GRAVE`, strength 1.5, blast resistance **6.0** — a creeper/TNT CAN pop it today; `onRemove` scatters contents rather than voiding) + `GraveBlockEntity` (items/owner/grace) + persistent index `EclipseWorldState.gravePositions` (owner → `GlobalPos` list, used by the Grave Dowser).
- Already-safe by construction:
  - `StormSiege.liftable()` rejects blocks with a `BlockEntity` → a grave itself is never sucked up/thrown.
  - Lift impact / abandon restore only writes into `canBeReplaced()` cells → never overwrites a grave.
  - Pistons cannot move block entities (vanilla) → no piston vector.
  - Wand spells: zero world block writes in the live set (§1.1); retired `WandPhaseService` blacklists BEs.
  - `FogTyrantEntity` lightning is `setVisualOnly(true)` (no fire/grief); no mod boss uses real `Level.explode`.
- **Unprotected vectors (F-085/086/087):** generic explosions (creepers pulled into the fight, TNT, any future boss explosion) can destroy the grave (scatters items into the storm); `LivingDestroyBlockEvent`-style mob grief (e.g. future colossus abilities); storm suction lifting the block UNDER a grave (leaves it floating; ugly and risky with future gravity behavior); nothing marks graves as excluded for future spell/boss block writes.

---

## 2. Designs

### 2.1 F-081 — Statue trigger ("hit the statue to wake the storm")

**New file** `…/entity/boss/fog/TyrantStatue.java` (family-owned sibling per the P6 no-shared-file rule; `@EventBusSubscriber` like `FogBankMarker`).

- **Per-lair statue, session-spawned:** when `FogBankMarker.markLair` arms a lair, `TyrantStatue.spawnFor(level, lairCenter, siteId)` stands a small display statue at the storm center: 3–4 `Display.BlockDisplay` pieces (suggested palette matching the tyrant: `POLISHED_BLACKSTONE` plinth ~1.2 scale, tilted `DEEPSLATE` torso ~1.0, `CRYING_OBSIDIAN` head ~0.7, a small `LIGHTNING_ROD` crown accent) + **one `minecraft:interaction` hitbox** (width ~1.4, height ~3.2) spawned via NBT exactly like `GravityRiftService.spawnHeartInteraction` (the `SkyLauncher.spawnPadInteraction` precedent). Use `DisplayBrightnessFx.set` for readable brightness inside the dark storm.
- **Tags (cleanup doctrine, feeds F-084):** every statue piece + hitbox carries `eclipse_storm_fx`, `eclipse_tyrant_statue`, and the per-fight scope tag `eclipse_fight_site_<siteId>`. Pieces are session entities: tracked in a live-UUID set; tagged joiners not in the set are discarded on load (`StormDebrisFx`/`StormSiege` doctrine), and `markLair` on restart re-stamps them — identical restore semantics to the lairs themselves.
- **Hit detection:** `AttackEntityEvent` (cancel, no damage) + `PlayerInteractEvent.EntityInteract` (accessibility, same as the rift heart) filtered by `eclipse_tyrant_statue`; require the striker to be a live non-spectator `ServerPlayer`. On hit → awaken sequence.
- **Idle FX so players read "interactive":** a new Photon cue `FxCues.CUE_TYRANT_STATUE_IDLE` (asset `eclipse:boss/tyrant_statue_idle` — slow ember orbit + faint crown sparks; author in `tools/photon/` beside the tyrant cues; LAYER law: photon-less clients keep a vanilla fallback). Server side, replace `FogBankMarker.stampBankPillars`'s summon role with statue dressing: keep the smoke ring, add an `ELECTRIC_SPARK` spiral on the statue column at the existing 40t cadence, re-send the idle cue on a dedup-aligned cadence like `CUE_TYRANT_FOG_ARMS` (`FOG_ARMS_REFIRE_TICKS` pattern).
- **Awaken sequence (~3 s):** hit → statue state `AWAKENING`: shake payload (`S2CShakePayload`), rising `AMETHYST_BLOCK_RESONATE` pitch (crown-lightning telegraph pattern), display micro-jitter via interpolated transform pushes, then a `fogBurstFx`-style burst → discard all statue pieces → `FogTyrantEntity.summonAt(level, lairCenter)` (its arrival FX + boss intro title already exist) → statue state `FIGHT`.
- **`FogBankMarker` changes:** `tickLair` no longer summons on proximity; it only (a) stamps ambient FX while `anyoneWatching`, (b) ensures the statue exists (self-heal respawn like the rift heart), (c) keeps the `LIVE_TYRANT_RANGE` guard so a statue is never armed while its tyrant lives (mid-fight restart resume). The lair entry is now removed at *statue hit* time instead of proximity time.
- **State machine per lair** (in `TyrantStatue`, keyed by lair `BlockPos`): `ARMED` (statue stands, idle FX) → `AWAKENING` (hit; timer) → `FIGHT` (tyrant alive; no statue) → `COOLDOWN` (after a reset; timer, §2.2) → `ARMED`. Victory removes the entry (`stormEnded` retires the site and the lair).

### 2.2 F-082 — Fight reset on death

**Reset condition (recommended, matching the task's recommendation):** the fight resets when **no living participant remains in the fight zone** — i.e. every enrolled participant is dead, a spectator, offline, or beyond `RESET_RANGE`; evaluated only once at least one participant has died during the fight (so "everyone briefly steps out" stays governed by the existing 60 s abandon timer, not an instant reset).

- **New method `checkWipeReset(ServerLevel)` in `FogTyrantEntity`,** called from `tickFight` right after `updateParticipants` on a 20t cadence (Ferryman `checkWipe` pattern, `WIPE_CHECK_TICKS`): if `participants` non-empty AND ≥1 participant died since summon (track a `boolean participantDied`, set from the death hook below) AND no participant is alive+non-spectator within `RESET_RANGE` → run `resetFight(level, "wipe")`.
- **Death hook:** a small `@SubscribeEvent LivingDeathEvent` (priority NORMAL, in `TyrantStatue` or a new `FogTyrantFightHooks` sibling — never in `LifecycleEvents`): if the victim is a `ServerPlayer` enrolled in a live tyrant's `participants` within its dimension, flag that tyrant's `participantDied` (public setter or event-scan via `getEntitiesOfClass`). No behavior change for graves — `LifecycleEvents.onLivingDrops` keeps placing the grave first (event priority NORMAL there; our hook only sets a flag).
- **`resetFight` = existing abandon-reset + re-arming, extracted from `tickReset` so both paths share it:**
  1. `clearTelegraphs()`, `discardTaggedAdds(level)` (hounds/colossus),
  2. heal to full (`setHealth(getMaxHealth())`) — phase re-derives to 1 on the next summon; enrage stacks/`colossusCalled` die with the entity,
  3. `this.discard()` (boss despawns — "despawns/heals" per feedback),
  4. `StormSiege` notices the tyrant is gone within one poll and runs its **abandon ending** (debris sinks, airborne lifts restore into their sockets) — no new wiring needed; add the F-084 sweep (§2.4) at ending completion,
  5. **statue re-arm with cooldown:** call `TyrantStatue.onFightReset(level, arenaCenter)` → state `COOLDOWN` for `RESET_REARM_TICKS = 600` (30 s), then respawn the statue and `FogBankMarker.markLair` again — this also fixes gap G-1 for the abandon path (call the same hook from `tickReset`).
- **Graves survive:** the reset writes no blocks except `StormSiege.resolveLift(restore=true)`, which is `canBeReplaced()`-guarded (a grave can never be overwritten) — plus the explicit `GraveProtection` guards of §2.5 as belt-and-braces. The grave placed by the death sits untouched inside the re-armed arena, lootable after the fight or between attempts.

### 2.3 F-083 — Storm independence

- **The one-line gate fix:** `FogStormSites.reconcileTyrantLair` — replace the `.max(…).ifPresent(markLair)` selection with **mark a lair for EVERY active site**:
  ```java
  FogBankMarker.clearAll(level);
  for (Site site : sites) {
      if (site.active()) {
          FogBankMarker.markLair(level, surfaceCenter(level, site.x(), site.z()));
      }
  }
  ```
  Update the class javadoc ("exactly one active highest-stage storm hosts the Fog Tyrant lair" is retired) and the `FogBankMarker` javadoc.
- Each lair now gets its own statue (§2.1) and its own tyrant; fights can run concurrently and in any order:
  - `StormSiege` already supports one siege per storm id;
  - `FogTyrantEntity.findHostSiteId` already resolves the nearest containing site, so each death bursts only its own storm;
  - keep `SUMMON_DEDUP_RANGE`/`LIVE_TYRANT_RANGE` as-is (sites are far apart); add a log-once warning if two configured sites are closer than 2×`SUMMON_DEDUP_RANGE` so map authors notice.
- `FogBankMarker.clearAll(level)` calls in `FogStormSites.onServerStopping`/`reloadFromSave` stay correct (lairs re-derive from active sites).

### 2.4 F-084 — Bulletproof display cleanup

Unify on the tag doctrine and close gap G-2. Tags on every fight-spawned display/hitbox: umbrella `eclipse_storm_fx` + system tag (`eclipse_storm_siege_debris` / `eclipse_tyrant_statue`) + scope `eclipse_fight_site_<siteId>` (or `eclipse_fight_storm_<stormId>` for plain-summon fights).

Changes in `…/stormfx/StormSiege.java`:

1. **Fix the tracking leaks:** in `animateWhirl()`'s `removeIf` and `tickLifts()`'s `isRemoved()` prune, distinguish *discarded* from *unloaded*: for unloaded displays remove the UUID from `LIVE_DISPLAYS` (so the join sweep reclaims them on chunk reload) and, for lifts, resolve the block (drop as item at the socket) instead of silently forgetting it.
2. **Sweep on fight end/reset:** when an ending completes (`tickEnding` → `discardAll`), additionally run a level-wide tagged sweep for this siege's scope tag over *loaded* entities (`level.getEntities(EntityTypeTest.forClass(Display.BlockDisplay.class), e -> e.getTags().contains(scopeTag))` … `discard()`), and drop every swept UUID from `LIVE_DISPLAYS`.
3. **Sweep on server start (orphan sweep):** already implicit — `LIVE_DISPLAYS` is empty after boot, so `onEntityJoin` discards every tagged joiner. Extend the join check from `Display.BlockDisplay` to *any* entity carrying `eclipse_storm_fx` (covers statue `Interaction` hitboxes too). This IS the "persistent tag-based sweep across restarts": nothing tagged survives a restart once its chunk loads.
4. **Sweep on chunk load mid-session:** the same `EntityJoinLevelEvent` handler additionally discards a tagged joiner whose scope tag has **no live siege/statue** (query `SIEGES` + `TyrantStatue` registry) — this reclaims frozen displays the moment their chunk reloads even within one session, closing G-2 completely.
5. Keep the 30-min watchdog and the `/kill @e[tag=eclipse_storm_siege_debris]` escape hatch; add `/kill @e[tag=eclipse_storm_fx]` to the admin docs.

Reuse, don't reinvent: `StormDebrisFx` (doctrine reference), `DisplayBrightnessFx` (spawn plumbing), `StormSiege.spawnDisplay/discardDisplay` (extend for the extra tags).

### 2.5 F-085/086/087 — Grave protection

**New file** `…/lives/GraveProtection.java` (`@EventBusSubscriber`, `MansionDomeProtection`/`SpawnProtectionRules` house patterns):

- `public static boolean isGraveAt(Level level, BlockPos pos)` → `level.getBlockState(pos).is(EclipseBlocks.GRAVE.get())` (cheap, no SavedData scan).
- `public static boolean nearGrave(ServerLevel level, BlockPos pos, int radius)` → small cube scan (radius ≤ 2) used by the siege lift sampler; graves are rare so this stays cheap at volley cadence.
- **Explosions:** `@SubscribeEvent ExplosionEvent.Detonate` → `event.getAffectedBlocks().removeIf(pos -> isGraveAt(level, pos))` (exact `MansionDomeProtection.onExplosionDetonate` pattern; protects against creepers dragged into the fight, TNT, and any future boss explosion). Entities still take damage; only the grave block is pruned.
- **Mob grief:** `@SubscribeEvent LivingDestroyBlockEvent` → cancel when `isGraveAt` (covers withers/ravagers/future boss abilities). Optionally also deny `EntityMobGriefingEvent` for entities colliding with a grave cell — recommend NOT: it is a per-entity blanket switch (the `SpawnProtectionRules` usage is zone-wide); the two block-accurate hooks above plus §below cover every real vector.
- **Players stay allowed** to mine graves (existing design: `onRemove` scatters safely; the dowser index unregisters). No `BlockEvent.BreakEvent` cancel.
- **Boss block-throw / storm-suction exclusion (F-086):** in `StormSiege.Siege.liftable(pos)` add `&& !GraveProtection.isGraveAt(level, pos) && !GraveProtection.nearGrave(level, pos, 1)` — never lift a grave (already BE-excluded, now explicit) **and never lift the ground directly under/around one** (no floating graves). In `impact()`/`resolveLift()` add an `isGraveAt(landing)` guard before `setBlockAndUpdate` (today unreachable thanks to `canBeReplaced()`, but the guard survives future refactors).
- **Wand spells (F-087):** audit conclusion — the live spell set writes no blocks and ignites no terrain (§1.6), so graves cannot be damaged by spells today. Defensive hardening anyway: (a) add an explicit grave check to `WandPhaseService`'s hard blacklist (one line beside the existing BE check, with an F-087 comment); (b) document in `WandSpellEffects`'s class javadoc the standing rule: *any future spell that writes/ignites blocks MUST consult `GraveProtection.isGraveAt`*; (c) since `Feuerball`/`Eruptionslinie` explosions are FX-only (`WandPowers.damageAround`, no `Level.explode`), no per-spell change is needed — if a future spell adopts real explosions, the `ExplosionEvent.Detonate` hook already covers it.
- **Grave hardening (optional, recommended):** raise `EclipseBlocks.GRAVE` blast resistance from 6.0F to 1200.0F (obsidian-class) so even *unhooked* explosion paths (mods, `/summon tnt`) cannot pop graves; keep strength 1.5 so players still mine it by hand.

---

## 3. Ordered implementation checklist

Order chosen so every step is independently testable and the risky display work lands before the trigger rework builds on its tags.

1. **`lives/GraveProtection.java` (NEW)** — `isGraveAt`, `nearGrave`, `ExplosionEvent.Detonate` pruning, `LivingDestroyBlockEvent` cancel. Register nothing in `EclipseMod` (auto via `@EventBusSubscriber`).
2. **`registry/EclipseBlocks.java`** — grave blast resistance 6.0F → 1200.0F (one literal).
3. **`stormfx/StormSiege.java`** — F-084: fix `animateWhirl`/`tickLifts` unload leaks (LIVE_DISPLAYS bookkeeping + lift block drop); add scope tag `eclipse_fight_…` + umbrella tag `eclipse_storm_fx` in `spawnDisplay`; extend `onEntityJoin` sweep (any tagged entity; discard when no live owner for the scope tag); ending-completion sweep; grave guards in `liftable`/`impact`/`resolveLift` (uses step 1).
4. **`entity/boss/fog/TyrantStatue.java` (NEW)** — statue spawn (displays + `Interaction` NBT spawn), live-UUID set + join-sweep participation, `AttackEntityEvent`/`EntityInteract` hit detection, awaken sequence, per-lair state machine (`ARMED/AWAKENING/FIGHT/COOLDOWN`), `onFightReset` cooldown re-arm, self-heal respawn. Event hooks: `ServerTickEvent.Post`, `AttackEntityEvent`, `PlayerInteractEvent.EntityInteract`, `EntityJoinLevelEvent`, `ServerStoppedEvent`.
5. **`entity/boss/fog/FogBankMarker.java`** — remove the proximity summon from `tickLair`; delegate statue ensure/dressing to `TyrantStatue`; lair disarms at statue-hit (callback from step 4); keep `LIVE_TYRANT_RANGE` guard.
6. **`worldgen/fog/FogStormSites.java`** — F-083: `reconcileTyrantLair` marks EVERY active site (§2.3); javadoc updates; optional proximity warning log.
7. **`entity/boss/fog/FogTyrantEntity.java`** — F-082: extract `resetFight(level, reason)` from `tickReset`; add `participantDied` flag + `checkWipeReset` on a 20t cadence in `tickFight`; both reset paths call `TyrantStatue.onFightReset`. Persist `participantDied` in NBT beside `Participants` (restart mid-fight keeps wipe semantics).
8. **`entity/boss/fog/FogTyrantFightHooks.java` (NEW, tiny)** — `LivingDeathEvent` listener that flags `participantDied` on the enrolled tyrant (or fold into `TyrantStatue` if preferred; keep out of `lives/`).
9. **`network/fx/FxCues.java` + client row registrar (`stormfx/StormPhotonFx.java` neighborhood or the boss FX rows) + `tools/photon/` asset** — `CUE_TYRANT_STATUE_IDLE` (+ optional `CUE_TYRANT_STATUE_AWAKEN`); vanilla particle fallback stays server-stamped (LAYER law).
10. **`wand/WandPhaseService.java`** — one-line grave blacklist addition + F-087 comment; **`wand/WandSpellEffects.java`** — javadoc rule (§2.5).
11. **Docs:** update `docs/plans_v3/wiring/WB-TYRANT_wiring.md` (trigger is now the statue; lairs per storm) and `UserFeedback.md` rows F-081…F-087 → ✅ after verification.
12. **Lang:** action-bar/caption strings for statue hint + awaken (e.g. `eclipse.storm.statue.hint`, `eclipse.storm.statue.awaken`) in both lang files, following `eclipse.storm.siege.*` precedent.

**Explicitly NOT changed:** `LifecycleEvents` (grave placement flow), `DeathFlowHooks` (ship theater), `GraveBlock.onRemove` scatter semantics, `StormRegistry` API, `FogTyrantArena`, the boss's phases/attacks.

---

## 4. Manual test script (dedicated server + RCON)

Prereqs: dev server running with RCON on (the repo's `tools/rcon/rcon.py` defaults: `127.0.0.1:25575`, password `eclipsedev`); one test player `Dev1` online. Every command below runs as
`python3 ProjectEclipse/tools/rcon/rcon.py "<command>"` (multiple commands per call are fine).

```bash
RCON() { python3 ProjectEclipse/tools/rcon/rcon.py "$@"; }

# 0. Locate the storms (site coords come from the save's eclipse/fogstorms.json).
RCON "data get storage eclipse:debug fogstorms" || true   # if unavailable, read the JSON directly
# Expect after F-083: server log shows one 'FogBankMarker: tyrant lair marked' PER active site.

# 1. F-081 — statue stands, presence does NOT start the fight.
RCON "tp Dev1 <siteA_x> <siteA_y+2> <siteA_z>"
RCON "execute at Dev1 run summon minecraft:armor_stand ~ ~ ~"   # dummy marker for screenshots (optional)
sleep 65   # over the old 40t trigger cadence and then some
RCON "execute as Dev1 run kill @e[type=eclipse:fog_tyrant,distance=..64]"  # must match NOTHING:
# Expect: 'No entity was found' — no tyrant from mere presence; statue displays + idle FX visible,
#   log shows no 'summoning the Fog Tyrant'.

# 2. F-081 — hitting the statue starts the fight.
#    (manual: left-click the statue as Dev1; or the step-4 hitbox can be hit via a dev command if added)
# Expect: awaken sequence (~3 s), then 'Fog Tyrant summoned at …' in the log, bossbar up,
#   StormSiege 'siege up' log, debris orbiting.

# 3. F-082 — death resets the fight, grave survives.
RCON "execute as @e[type=eclipse:fog_tyrant,limit=1] run data get entity @s Health"   # note damaged HP after some hits
RCON "kill Dev1"                                        # all participants dead => wipe
sleep 25    # one wipe-check cadence
RCON "execute as Dev1 run kill @e[type=eclipse:fog_tyrant,distance=..512]"   # expect: No entity was found (boss despawned)
RCON "execute in minecraft:overworld run setblock <deathX> <deathY> <deathZ> air keep"  # sanity: must FAIL (grave block present)
RCON "execute if block <deathX> <deathY> <deathZ> eclipse:grave run say GRAVE_OK"
# Expect: 'GRAVE_OK'; log shows resetFight + statue COOLDOWN then re-ARMED after ~30 s.

# 4. F-084 — no stuck displays after the reset.
RCON "execute as Dev1 run kill @e[tag=eclipse_storm_siege_debris,distance=..512]"
RCON "execute as Dev1 run kill @e[tag=eclipse_storm_fx,distance=..512]"
# Expect BOTH: 'No entity was found' once the sink ending finished (~2 s after reset).
# Restart leg: start a fight, kill the player, HARD-STOP the server mid-siege, restart, tp back:
# Expect: join sweep discards every tagged display as chunks load ('crash stray' path), zero frozen debris.

# 5. F-083 — second storm is independent (fight it FIRST, i.e. before storm A's boss ever died).
RCON "tp Dev1 <siteB_x> <siteB_y+2> <siteB_z>"
# hit statue B; expect its own tyrant + own siege overlay while storm A's boss was never killed.
# Then also verify both fights can run CONCURRENTLY with two players (or sequentially re-armed).

# 6. F-085/086/087 — grave protection.
RCON "execute in minecraft:overworld run setblock <gx> <gy+1> <gz> minecraft:air"       # clear headroom
RCON "summon minecraft:tnt <gx> <gy+1> <gz>"
sleep 5
RCON "execute if block <gx> <gy> <gz> eclipse:grave run say GRAVE_SURVIVED_TNT"          # expect: GRAVE_SURVIVED_TNT
# Storm suction: run a siege around a grave in the lift ring; expect the grave AND its floor block
#   never lifted (log: no lift within r=1 of grave), no floating grave.
# Wand: as Dev1 cast Feuerball/Eruptionslinie/Sonnenkern AT the grave (creative wand via /give,
#   spells unlocked via the wand dev commands); expect the grave block unchanged:
RCON "execute if block <gx> <gy> <gz> eclipse:grave run say GRAVE_SURVIVED_SPELLS"

# 7. Regression: victory path (storm bursts, site retires, snow recovery, reward chest).
#    Re-arm a statue, start the fight, kill the boss legitimately (or /kill the tyrant to force die()),
#    expect the C8 death beat unchanged and NO tagged entities left afterwards (step-4 checks again).
```

Note: `/kill @e[…]`-style *assert-empty* probes double as cleanup if they unexpectedly match — read the RCON output ("No entity was found" = pass) and the server log breadcrumbs (`FogBankMarker:`, `Fog Tyrant`, `StormSiege:`) for every transition; the codebase logs all of them already.

---

## 5. Risks / open points

- **Multiple concurrent sieges** raise the display budget (80–150 per fight). Acceptable for 2–3 storms; if more sites go active simultaneously, add a global debris cap in `StormSiege` (split `DEBRIS_MAX` across live sieges).
- **`Interaction` hitbox persistence:** the hitbox is a normal persistent entity — the join-sweep + live-UUID doctrine (step 4) must include it, and `TyrantStatue` must self-heal a missing hitbox (rift-heart precedent already does exactly this).
- **Statue vs. restart mid-fight:** a tyrant persisted in NBT resumes its fight; `TyrantStatue` must check `LIVE_TYRANT_RANGE` before arming (design §2.1 keeps this guard) or two triggers could coexist.
- **`participantDied` semantics with mixed outcomes** (one player dead, one alive who then leaves): wipe reset fires only when the zone is empty of living participants — the abandon timer remains the fallback for "left without dying". Both call the same `resetFight`.
- **Grave blast-resistance bump** also protects graves from *player* TNT mining — intended per F-085, but note it in the changelog.
