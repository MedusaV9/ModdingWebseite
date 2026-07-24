# FINAL-POLISH-SOL — Wave-4 technical audit

**Evaluator:** POLISH-SOL  
**Method:** static audit only, as requested (`no gradle`). Reviewed the wave-4 services, their adjacent `SavedData`/client caches, tick subscribers, C2S entry points, the armor mixin, reload plumbing, and every `DeferredRegister` declaration against `EclipseMod`.

## Verdict

**Not final-wave clean yet.** Registry wiring and the armor mixin are correct, and most service lifecycle work follows the repository rules. The blockers are two game-integrity defects and one terrain-safety defect: daily awards bypass `AWARD_VOID`, forged wand casts are accepted from spectators/dead players, and Phasenwelle's claimed crash safety has no durability barrier between snapshot dirtiness and world mutation.

Severity used here:

- **HIGH** — can violate game authority, award rules, or preserve world damage after a crash.
- **MEDIUM** — player-visible correctness failure under restart/concurrency/configuration, or credible event-load spike.
- **LOW** — bounded lifecycle retention, stale diagnostics, or incomplete operator surface.

## Ranked concrete defects

### POLISH-SOL-01 — Daily award resolution bypasses `AWARD_VOID` (**HIGH**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/awards/AwardService.java:223-246`, `src/main/java/dev/projecteclipse/eclipse/awards/AwardsState.java:47-74`, `src/main/java/dev/projecteclipse/eclipse/contracts/ContractService.java:451-464`

The wrong-kill path records `AWARD_VOID`, and the public `queueReward(..., String, AwardConfig.Reward)` overload checks it. Actual daily award grants are already stored as `AwardsState.PendingReward`; `queueResolvedRewards` calls the private `queueReward(..., PendingReward)` overload directly, and that overload has no void check. Therefore the contract penalty does not suppress the normal daily awards it was designed to suppress.

**Fix:** make the void decision with the resolved award's explicit `day`, before the pending reward is queued. Do not query mutable `EclipseWorldState.getDay()` after rollover, and ensure replay/repair of an already resolved day applies the same deterministic decision.

### POLISH-SOL-02 — Phasenwelle is not transactionally crash-safe (**HIGH**)

**File:** `src/main/java/dev/projecteclipse/eclipse/wand/WandPhaseService.java:117-126,149-192,211-234`

`castWave` adds snapshots to `SavedData` and calls `setDirty()`, then a later tick replaces blocks with air. `setDirty()` only schedules persistence; it does not establish that the snapshot reached disk before the chunk containing the air write can be saved. A crash/partial save after the chunk write but before the `SavedData` write can leave permanent air with no recovery entry. The class documentation's “can therefore never permanently eat terrain” guarantee is stronger than the implementation.

**Fix:** introduce a durable two-phase protocol: persist pending snapshots first, only permit vanish after a confirmed save boundary, then persist the `vanished` phase. Alternatively use a storage mechanism whose snapshot and mutation ordering is explicitly guaranteed. Add a crash-cut test at each phase.

### POLISH-SOL-03 — Forged C2S wand casts can execute from spectator/dead state (**HIGH**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/network/wand/WandPayloads.java:30-48`, `src/main/java/dev/projecteclipse/eclipse/wand/WandPowers.java:71-131`

The cast handler correctly re-reads the held item, owner, path, unlocked level, charge, cooldown, disable switch, and spawn protection on the server. It never checks `player.isAlive()`, `player.isSpectator()`, or an allowed game mode. A modified client retaining an owned wand can request damaging casts or `WandPhaseService.castWave` while spectator/dead, bypassing the normal item-use gate; the phase cast directly mutates blocks.

**Fix:** reject dead/removed/spectator players before any state mutation and define the allowed game modes explicitly. Apply the same basic actor-state gate to path choice. Consider a small request throttle for rejected packets so forged failures cannot spam sounds/messages.

### POLISH-SOL-04 — Paused contract deadlines advance while the server is offline (**MEDIUM**)

**File:** `src/main/java/dev/projecteclipse/eclipse/contracts/ContractService.java:117-134,185-205`

The live tick shifts deadlines while `RealtimeDayApi.isPaused`, but `resumeOnBoot` resolves an elapsed contract unconditionally before the pause-aware tick can run. `lastPauseCheckMillis` is transient and reset at stop. A contract stopped while the real-time clock is paused therefore consumes offline wall time, and can immediately expire on restart.

**Fix:** persist enough pause anchoring to shift the offline interval, or make boot resume consult the persisted pause state before resolving/shifting deadlines.

### POLISH-SOL-05 — Contract client state lacks a logout boundary; face futures can cross sessions (**MEDIUM**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/client/contracts/ContractClientState.java:23-56`, `src/main/java/dev/projecteclipse/eclipse/client/contracts/ContractRevealOverlay.java:77-95,160-180,298-314`

Both classes rely on a later tick observing `Minecraft.level == null`; neither handles `ClientPlayerNetworkEvent.LoggingOut`, unlike the wave-4 glyph and bestiary clients. More importantly, `resolveFace` has no session/generation token. An old asynchronous skin lookup can complete after `reset(false)`, or after a new hunter lookup starts, and overwrite `resolvedSkin` with the previous session's target face.

**Fix:** reset both classes on `LoggingOut`; increment a lookup generation on reveal/reset and only accept a completion whose generation and target UUID still match.

### POLISH-SOL-06 — Action-toggle movement locks have no ownership-safe release (**MEDIUM**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/admin/ActionTogglesService.java:84-87,160-170,270-287`, `src/main/java/dev/projecteclipse/eclipse/cutscene/FreezeService.java:75-117`

`MOVE_LOCKED` remembers that ActionToggles once installed the single shared `CUTSCENE_LOCK`. A later cutscene/admin `FreezeService.freeze` replaces that attachment but does not clear ActionToggles' ownership bit. If movement is then allowed, `reconcileMoveLocks`/the tick path calls `FreezeService.unfreeze` and removes the newer foreign cutscene lock.

**Fix:** give freeze locks an owner/token and release only a matching token, or add a dedicated composable movement-denial lane instead of sharing one overwriteable attachment.

### POLISH-SOL-07 — Every active Feuerwelle performs an entity query every tick (**MEDIUM**)

**File:** `src/main/java/dev/projecteclipse/eclipse/wand/WandTickService.java:141-147,181-223`

Each active wave builds an expanding AABB and calls `getEntitiesOfClass(LivingEntity.class, ...)` every tick. With one concurrent wave per player this becomes `O(players × local living entities)` for the full 40–50 tick expansion. Default 340/400-tick per-power cooldowns limit how often a player starts a wave, but there is no global active-wave cap, shared spatial query, or scan cadence while waves are active.

**Fix:** scan only on radius bands every 2–4 ticks, cap concurrent waves, or query once per level and assign candidates to waves. Keep the current hit-once set.

### POLISH-SOL-08 — Minigame inventory tickets are ordered in memory, not durably (**MEDIUM**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/minigames/MinigameService.java:460-501`, `src/main/java/dev/projecteclipse/eclipse/minigames/MinigameState.java:337-375`

Entry calls `putTicket` and then immediately teleports/clears the player's inventory. `putTicket` only marks overworld `SavedData` dirty. Player NBT and level `SavedData` are separate files, so a crash during a partial save can persist the disposable minigame inventory without the original-inventory ticket (or the converse). “TICKET FIRST” is correct in RAM but is not an atomic persistence guarantee.

**Fix:** use an explicit durable entry phase and recover both directions, or keep a second marker/snapshot in player-persistent data so either side can reconstruct the transaction. Test crash cuts between ticket, player mutation, and cleanup.

### POLISH-SOL-09 — Wand config is outside `ReloadHooks` and is not client-authoritative (**MEDIUM**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/wand/WandItems.java:98-104`, `src/main/java/dev/projecteclipse/eclipse/core/config/ReloadHooks.java:8-47`, `src/main/java/dev/projecteclipse/eclipse/devtools/dev/DevReload.java:58-68`, `src/main/java/dev/projecteclipse/eclipse/client/wand/WandChargeHud.java:51-67`, `src/main/java/dev/projecteclipse/eclipse/wand/EclipseWandItem.java:163-176`

`wand.json` registers only in `DevReloadRegistry`, so `/dev reload` happens to cover it but the required common `ReloadHooks` path (`/eclipse reload` and any direct `EclipseConfig.reload`) does not. The HUD/tooltip also call `WandConfig.get()` client-side; on a dedicated server that reads the client's local/default file, not the server's reloaded max charge, so display can disagree with authoritative charge economics.

**Fix:** register the loader in `ReloadHooks` with a JVM-lifetime duplicate guard, remove the split registration, and sync the small client-visible snapshot (at least max charge) from server to client.

### POLISH-SOL-10 — `WandConfig` accepts unsafe negative/unbounded gameplay values (**MEDIUM**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/wand/WandConfig.java:115-159`, `src/main/java/dev/projecteclipse/eclipse/wand/WandPhaseService.java:71-110`, `src/main/java/dev/projecteclipse/eclipse/wand/WandPowers.java:99-127`

Power cost, cooldown, charge max/regeneration, cube length, and max block count are read as unconstrained floats/ints. A negative cost increases charge after a cast; a non-positive cooldown removes the only cast throttle; a large phase length makes the payload handler iterate `(2r+1)^3` block positions on the main thread.

**Fix:** validate/clamp every balance field at load time, reject non-finite numbers, and hard-cap phase volume independently of config.

### POLISH-SOL-11 — Stop/logout hygiene has three bounded omissions (**LOW**)

**Files:** `src/main/java/dev/projecteclipse/eclipse/admin/ActionTogglesService.java:81-87,142-148,364-370`, `src/main/java/dev/projecteclipse/eclipse/voice/VoiceChangerService.java:36-43,136-148`, `src/main/java/dev/projecteclipse/eclipse/voice/VoiceChangerPlugin.java:55-56,114-124`, `src/main/java/dev/projecteclipse/eclipse/progression/bestiary/BestiaryService.java:63-85,163-172`

- ActionToggles clears caches on the next `ServerStartedEvent`, not on `ServerStoppedEvent`; `activeBits` also remains stale until that start.
- VoiceChangerService similarly leaves runtime presets/default/budget counters until next start. The voice plugin closes pipelines correctly, but does not reset `LAST_ERROR_LOG`.
- Bestiary clears `LAST_SIGHTING` at server stop but not player logout, retaining every visitor's transient cooldown map for the lifetime of a long-running server.

These do not cross into active gameplay after the next start, but they violate the stated lifecycle rule and retain stale world/player data longer than necessary.

### POLISH-SOL-12 — `/dev reload`'s config reference surface omits all wave-4 files (**LOW**)

**File:** `src/main/java/dev/projecteclipse/eclipse/devtools/dev/DevReload.java:28-52`

The executable hook path covers contracts, minigames, voice changer, and (through the split registry) wand. The static config-reference/handbook list contains none of `contracts.json`, `minigames.json`, `wand.json`, or `voice_changer.json`, so operator discovery and the command's own documented inventory are stale.

## 1. Lifecycle and persistence matrix

| Service | Persistent truth | Transient/static cleanup | Result |
|---|---|---|---|
| `ContractService` | `ContractState` correctly persists phase, pair, deadlines, day latch/history/tallies | signal guard + pause timestamp + log guard clear on stop; reload-hook guard correctly stays JVM-wide | **FAIL** boot pause accounting (SOL-04); client cleanup in SOL-05 |
| `ContractModifierService` | modifier ledger is `SavedData`; secret skill multiplier is also persisted in `SkillState`; transient health attribute is rebuilt on start/login/respawn/clone | signal guard clears on stop | **PASS**, except award consumer bypass (SOL-01) |
| `WandTickService` | tasks/waves/jumps/cooldowns are correctly transient | all clear on stop | **PASS** |
| `WandPhaseService` | block snapshots need persistence | no mutable static runtime state | **FAIL** durability guarantee (SOL-02) |
| `MinigameService` | phase, participants, tickets, scoring and course seeds correctly belong in `MinigameState` | bossbar, confirmations, hints, timers and readiness clear on stop; per-player entries clear on logout | **RISK** cross-file ticket atomicity (SOL-08) |
| `DawnCeremony` | presentation tasks are transient | tasks/end tick clear on stop | **PASS** |
| `GestureGlyphService` + `GestureGlyphFx` | gesture samples/glyph loops are transient | server samples clear on stop; client glyphs clear on logout | **PASS** |
| `HearthAuraService` | held-aura duration is session-local | map clears on stop | **PASS** |
| `FirstBloodService` | once-per-save latch correctly uses tiny `SavedData` | no mutable transient static | **PASS** |
| `WitnessedLossService` | pre/post death snapshot is transient | bounded map clears on stop | **PASS** |
| `KillConfirmService`, `HitStopService`, `MiningFeelService` | stateless/event-derived | nothing to clear | **PASS** |
| `EdgeGlideService` | live glide, hints and geometry cache are transient | player live state clears on logout; all caches clear on stop | **PASS** |
| `SoftLandingFx` | airborne sample is transient | clears on logout and stop | **PASS** |
| `WizardService` | enabled flag, quest ledger, entity UUID, home and death day correctly use overworld `WizardData` | service has no mutable static runtime state | **PASS**; 100-tick ensure and loaded-entity guard are sound |
| `BestiaryService` | knowledge/counts correctly use `BestiaryState`; sighting cooldown is correctly transient | server map clears on stop; client cache clears on logout | **LOW leak** no server player-logout prune (SOL-11) |
| `ActionTogglesService` | global/per-player permissions correctly use `ActionTogglesState` | player rows clear on logout; caches rebuild on start only | **FAIL** lock ownership (SOL-06), stop hygiene (SOL-11) |
| `VoiceChangerService` / plugin / config | presets correctly use `VoiceChangerState`; config is process-global; DSP pipelines are transient | pipelines close on voice disconnect/server stop; service mirror resets only on next server start | **LOW hygiene** (SOL-11) |

Pure deterministic `ElytraRace.cachedCourse` is safe to retain across saves because it is keyed only by the persisted integer seed; it is not world state.

## 2. Event-storm audit

| Subscriber | Tick cost | Throttle/verdict |
|---|---|---|
| `ContractService` | constant state-machine check | every 10 ticks; safe. Pair draw is `O(P²)` but only at contract start, not per tick |
| `WandTickService` | `O(tasks + phase entries + jumps + waves × local living entities)` | **SOL-07** for Feuerwelle; phase entries also have no global cap |
| `MinigameService` | portal/inside/bossbar loops are `O(P)` | every 10 ticks; course block IO uses shared nanosecond budget; close-time entity sweep is one-shot |
| `GestureGlyphService` | `O(P)` edge sampling | every tick, allocation-free on unchanged input; no entity query |
| `HearthAuraService` | per-player 11×7×11 block box, then small circle buckets | every 40 ticks; expensive but explicitly throttled |
| `DawnCeremony` | tiny task list | only while ceremony active |
| `EdgeGlideService`, `SoftLandingFx`, `ActionTogglesService` | `O(1)` per player tick, except a tiny cached ledge list | safe |
| `WizardService` | UUID lookup; local entity query only when the tracked wizard is missing | every 100 ticks; safe. Orin greeting is `O(P)` every 10 ticks |
| `BestiaryService` | one local mob AABB query per tracked player: `O(P × nearby mobs)` | every 40 ticks and phase-offset; this is the intended throttled case, not an unbounded every-tick storm |
| Drama death/damage/mining services | event-driven, no periodic scan | safe |
| Voice changer | `O(audio samples)` only for active voice frames | budget measured with consecutive-strike auto-disable; safe |

## 3. C2S/pseudo-C2S safety

| Entry | Server-side checks | Result |
|---|---|---|
| `C2SWandCastPayload` | server derives hand stack, owner, path, level/selection, config power, cooldown, charge, disable state, protection zone | **FAIL** actor liveness/spectator/game-mode authorization (SOL-03) |
| `C2SWandChoosePathPayload` | rejects invalid/NONE id, no held wand, foreign owner, and already-locked path | **PASS**, but should share the basic actor-state gate |
| Contracts | no C2S payloads; all three contract payloads are `playToClient` | **PASS** |
| `/minigameleave [confirm]` | not a payload; Brigadier binds the real `ServerPlayer`, checks minigame dimension both times, and consumes a server-held 15-second confirmation nonce | **PASS** |

## 4. `HumanoidArmorLayerMixin`

**PASS.**

- `@Mixin(HumanoidArmorLayer.class)` is the correct 1.21.1 client render layer.
- The explicit descriptor has the erased `LivingEntity` fourth parameter and six floats, matching the non-bridge `render` overload.
- `@At("HEAD")`, `cancellable = true`, and `defaultRequire: 1` fail loudly if the descriptor drifts.
- The body gates on both `livingEntity instanceof AbstractClientPlayer` and `ContractClientState.windowActive()`, so zombies/armor stands are unaffected and the behavior is render-only.
- The remaining lifecycle risk is the stale client flag/face state in SOL-05, not the mixin target.

## 5. Config reload coverage

| New config | `ReloadHooks` | `/dev reload` execution | Result |
|---|---:|---:|---|
| `contracts.json` | yes, JVM-guarded in `ContractService` | yes through `EclipseConfig.reload()` | pass |
| `minigames.json` | yes, idempotent bootstrap | yes through `EclipseConfig.reload()` | pass |
| `voice_changer.json` | yes, JVM-guarded | yes through `EclipseConfig.reload()` | pass |
| `wand.json` | **no**; only `DevReloadRegistry` | yes, second registry pass | **fail** SOL-09 |

The two registries make `/dev reload` broader than `/eclipse reload`; that is exactly the split `ReloadHooks` was intended to avoid. All four files are also absent from `DevReload.CONFIG_REFS` (SOL-12).

## 6. Deferred-register wiring

**PASS — no wave-4 registry leak.**

- `WandItems.ITEMS` and `WandItems.COMPONENTS` are both registered inside `WandItems.register`, called by `EclipseMod:60`.
- `WizardEntities.ENTITIES` and `WizardEntities.ITEMS` are both registered inside `WizardEntities.register`, called by `EclipseMod:61`.
- The repository-wide declaration/call cross-check found every other `DeferredRegister` reachable either directly from `EclipseMod` or through the intentional aggregators `ClassicBlocksModule` and `LangService`.

## Ship recommendation

Block final polish sign-off on **SOL-01, SOL-02, and SOL-03**. Fix **SOL-04 through SOL-10** before a high-population rehearsal or crash-recovery rehearsal. SOL-11/12 are safe to batch as final lifecycle/operator cleanup.
