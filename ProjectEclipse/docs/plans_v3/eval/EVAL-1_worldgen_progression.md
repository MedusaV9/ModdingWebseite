# EVAL-1 — Worldgen + progression correctness audit

Scope: static, read-only audit of the requested NeoForge 1.21.1 worldgen and progression
domains. No Gradle task or live-server action was run, as requested. Line references are
approximate and refer to the audited revision.

## Critical bugs

### HIGH — Ordinary config reload breaks the per-save stage-radius freeze

- **Area / files:** per-save freeze; `core/config/EclipseConfig.java` around lines 303–325
  and 342–364, `worldgen/FrozenParams.java` around lines 76–83 and 253–275.
- **Failure:** `FrozenParams` correctly installs the save-frozen radii into `StageRadii` at
  activation, but every ordinary `EclipseConfig.reload()` subsequently calls
  `applyStageRadii()` and overwrites `StageRadii` from global `config/eclipse/stages.json`.
  The frozen arrays in `FrozenParams.Context` are not updated. The running save is then
  split-brain: terrain radius, border, sweep bounds, and `WorldStageService.maxStage()` read
  global `StageRadii`, while ore annulus lookup still reads the save-frozen arrays through
  `FrozenParams.annulusBand`.
- **Impact:** `/eclipse reload` can reshape an existing save without an explicit refreeze,
  produce terrain/ore band seams, or make persisted stages out of range. This directly
  violates D9's “terrain shaping comes only from the frozen copy” contract.

### HIGH — Personal quest detectors leak assignments across players and rerolls

- **Area / files:** goals; `progression/goals/QuestEngine.java` around lines 114–125,
  215–245, 621–675 and 848–858; `QuestDetectors.java` around lines 86–205.
- **Failure:** `ensurePlayer` adds each player's personal specs to one shared
  `ResolvedDay.byType`. Every signal detector and polling loop then evaluates that shared
  list for every player, without checking that the player was assigned the personal spec.
  `ResolvedDay.index` deduplicates only by goal id, not by player. A reroll adds new specs
  but never removes the old specs from those indexes.
- **Impact:** player B can progress, complete, and receive rewards for player A's personal
  quest; rerolled-away quests can still complete invisibly. This is both a reward exploit
  and a corruption of the persisted lifetime-exclusion set.

### HIGH — The authored dragon main can never observe the custom dragon victory

- **Area / files:** goals/end interaction; `QuestEngine.java` around lines 549–580,
  `worldgen/end/EclipseDragonFight.java` around lines 460–490, and
  `worldgen/end/EndFightState.java` around lines 200–210.
- **Failure:** the `dragon_defeated` built-in beat checks the vanilla End dimension's
  `EndDragonFight.hasPreviouslyKilledDragon()`. Eclipse deliberately runs a custom dragon
  in the overworld and records victory in `EndFightState.dragonKilled()`. No caller
  registers an `EclipseDragonFight.Listener` to fire the quest beat.
- **Impact:** the day-13 `d13_dragon` main remains incomplete after the actual Eclipse
  dragon is killed, blocking normal progression unless an admin manually completes it.

### HIGH — Physical start discs and persisted assignments are computed from different orders

- **Area / files:** start/limbo interaction; `limbo/StartEventCutscene.java` around lines
  197–215 and 228–250; `start/StartAssignmentService.java` around lines 45–81 and 130–140.
- **Failure:** the cutscene teleports `limbo.players()` in its current list order and maps
  list index to disc index. At `EMERGE`, it passes only the UUID key set to
  `StartAssignmentService.assign`, which sorts UUIDs before independently assigning indexes.
  Player-list order is not guaranteed to equal UUID order.
- **Impact:** a player's persisted anchor and the map handed to `IntroSequence` can point at
  a different disc from the one the player physically occupies. Camera/fusion framing,
  diagnostics, and reconnect behavior can therefore target the wrong disc.

### HIGH — A login during the cutscene's final 20 ticks can strand a player in Limbo

- **Area / files:** Limbo/start interaction; `StartEventCutscene.java` around lines 55–66,
  128–146, 197–215 and 228–250; `limbo/LimboGate.java` around lines 23–55.
- **Failure:** the cutscene snapshots and teleports Limbo players at tick 140, then sets
  `startEventDone=true` at tick 160. A player who logs in after the tick-140 snapshot is
  gated into Limbo but is absent from `teleportedPlayers` and `discCenters`; `emerge` does
  not sweep Limbo again. Once the flag flips, subsequent login/respawn gating returns early.
- **Impact:** the late joiner misses the intro handoff and remains in Limbo with no automatic
  recovery path.

### HIGH — Failed structure placement is persisted as successfully placed

- **Area / files:** two-phase structures; `worldgen/structure/StructurePendingRegistry.java`
  around lines 319–391.
- **Failure:** a synchronous placer exception falls through to `removeAndRecord(site, true)`.
  The async `completeAsync` path does the same when `error != null`, then fires `PLACED`.
  Thus transient chunk, registry, or preparation errors delete the pending row and create a
  placed record.
- **Impact:** the site is never retried and future enqueue attempts are deduplicated as
  already placed. Progression structures can be permanently absent while downstream
  listeners are told placement succeeded.

## Medium bugs

### MED — Stage downgrade does not cancel an in-flight async structure writer

- **Area / files:** structures/tick budgets; `StructurePendingRegistry.java` around lines
  248–259 and 377–391; `worldgen/stage/BudgetedBlockWriter.java` around lines 75–113.
- **Failure:** `clearPlacedAbove` removes matching pending rows and removes their ids from
  `IN_FLIGHT`, but the queued `BudgetedBlockWriter` job has no cancellation. It can continue
  writing after the erase sweep; its completion callback is then ignored because the
  in-flight id was already removed.
- **Impact:** a downgraded stage can regain partial/full structure blocks after its erase,
  with no pending or placed record. Regrowth can stamp the site again.

### MED — Persisted pending sites do not restore their PENDING notification

- **Area / files:** structure restore; `StructurePendingRegistry.java` around lines 264–274
  and 443–469.
- **Failure:** startup reloads the pending rows but neither rebroadcasts
  `S2CStructureRiftPayload` nor re-fires the `PENDING` listener phase. There is also no
  login-time pending-site sync.
- **Impact:** after a restart, the server eventually auto-places the structure, but current
  clients and the expansion-sequence listener cannot reconstruct the pending rift state.
  The two-phase visual/trigger contract silently degrades to an unannounced placement.

### MED — Team completion has no offline-player credit/reward backfill

- **Area / files:** goal backfill; `QuestEngine.java` around lines 215–245 and 433–458.
- **Failure:** `completeTeam` sets global team completion but grants rewards, marks per-player
  done, and fires `questCompleted` only for players online at that instant. `ensurePlayer`
  backfills only already-fired `EACH_PLAYER` beats; it does not credit a previously known
  player who was offline when a `TEAM_TOTAL`/`TEAM_ALL` goal completed.
- **Impact:** the player sees the team goal as done on next login but permanently misses
  shards/items/skill XP and the completion signal.

### MED — Potion “collect” goals do not count normal brewing

- **Area / files:** goal trigger correctness; `QuestEngine.java` around lines 287–299 and
  678–695; `GoalConfig.java` around lines 622–626 and 796–797.
- **Failure:** `COLLECT_ITEM` observes only `ITEM_PICKED_UP` and `ITEM_CRAFTED` stat deltas.
  Normal brewing-stand output is neither a crafting result nor an item-entity pickup.
  Nevertheless, both `d09_alchemy` and `p_alchemist` use `COLLECT_ITEM` for potions and tell
  players to “Prepare” them.
- **Impact:** brewing the requested potions normally produces zero progress; players must
  discover a non-obvious drop/re-pickup workaround.

### MED — Ore hot reload reads global data into a save-frozen world

- **Area / files:** frozen ores; `FrozenParams.java` around lines 59–61 and 269–275.
- **Failure:** startup correctly loads `OreConfig` from the save extract, but the
  `ReloadHooks` entry always reloads global `config/eclipse/ores.json`.
- **Impact:** `/eclipse reload` silently replaces the active save's frozen ore table without
  updating `worldgen.json`; a restart reverts it, and chunks generated in between can differ.

### MED — End refreeze is not activated immediately, and restart activation is order-dependent

- **Area / files:** End config; `FrozenParams.java` around lines 173–200 and 253–275,
  `worldgen/end/EndConfig.java` around lines 58–76 and 109–112, and
  `EndDiscService.java` around lines 67–101 and 199–206.
- **Failure:** `activateFromJson` extracts the frozen `end.json` but never reloads
  `EndConfig`. Therefore `refreeze end`/`refreeze all` reports success while the active
  snapshot remains stale. On restart, both `EndConfig` and `EndDiscService` load at
  `ServerStartedEvent`; if the service resumes first, its `Job` permanently captures the
  previous/default snapshot before `EndConfig.reloadCurrent()` runs.
- **Impact:** crystal count, loot policy, and writer budget can come from the wrong revision
  for the entire resumed materialization.

### MED — Fog Tyrant lairs are not reconciled with storm lifecycle

- **Area / files:** fog/tyrant seam; `worldgen/fog/FogStormSites.java` around lines 141–157,
  195–212 and 318–334.
- **Failure:** downgrade marks a fog site inactive but never calls
  `FogBankMarker.clearLair`. Selection also uses maximum radius, although the wiring contract
  says highest-stage site. With tied maximum radii (including the two defaults), live
  materialization marks every tie, while restart restoration marks only one `.max(...)`
  result.
- **Impact:** an erased/inactive storm can still summon the Tyrant, and the number/location
  of armed lairs changes after restart.

### MED — Removing/renaming a fog site during refreeze leaves old session effects alive

- **Area / files:** fog refreeze; `FogStormSites.java` around lines 288–305 and 318–334;
  `stormfx/StormRegistry.java` around lines 218–238.
- **Failure:** `reloadFromSave` replaces `sites` and restores only ids in the new list. It
  never broadcasts `active=false` or clears a lair for ids removed by the refreeze.
  `StormRegistry.pollFogSites` can only retire sites still present in that list.
- **Impact:** deleted sites retain their storm wall and possible Tyrant lair until server
  restart.

## Low bugs

### LOW — `SitePrep` “silent” writes send every block update to clients

- **Area / files:** structure prep; `worldgen/structure/SitePrep.java` around lines 600–603.
- **Failure:** `setSilent` uses `Block.UPDATE_CLIENTS | Block.UPDATE_KNOWN_SHAPE`, despite its
  contract saying clients see only the final relight/chunk resend.
- **Impact:** large plateau/cavity jobs emit redundant per-block traffic before the full
  chunk packet, increasing load and exposing partially prepared terrain/flicker.

### LOW — Pre-event containment has no dimension-change enforcement

- **Area / files:** Limbo; `limbo/LimboGate.java` around lines 23–55.
- **Failure:** containment runs only on login and respawn. A portal, command, or another mod's
  teleport can move a player out of Limbo before `startEventDone`; no
  `PlayerChangedDimensionEvent` or server-side containment check returns them.
- **Impact:** the documented “everyone waits in Limbo” invariant is bypassable until the next
  login/respawn.

### LOW — Realtime startup can leave a clock armed beyond a newly lowered final day

- **Area / files:** realtime lifecycle; `progression/realtime/RealtimeDayService.java` around
  lines 447–472 and 513–526.
- **Failure:** final-day reconciliation occurs only when a boundary is due or a day is
  applied. If `maxDay` is lowered while the server is offline and the saved boundary is
  still in the future (especially while paused), startup leaves the clock armed and shows a
  countdown even though `currentDay >= maxDay`.
- **Impact:** stale clock/bossbar state can persist until the future boundary, or indefinitely
  while paused. Normal unchanged-config rollover, DST, pause/resume, and catch-up paths
  otherwise appeared internally consistent.

## Quick wins

1. **Make frozen activation the single reload authority.** On ordinary reload, reinstall the
   active save's radii and reload ores/end from `FrozenParams.saveEclipseDir`; only explicit
   `refreeze` should copy global terrain-shaping data. Add one assertion/log showing global
   and frozen radii cannot diverge.
2. **Put quest eligibility at the write choke point.** Before `increment`/`raiseTo`, reject a
   personal spec not assigned to that UUID; rebuild personal indexes after reroll, backfill
   known offline team members on login, and fire `dragon_defeated` directly from the custom
   victory listener.
3. **Assign the start cohort before teleporting it.** Use the returned UUID→disc map for the
   physical hop and `IntroSequence`, then run one final Limbo reconciliation at `EMERGE` for
   players who joined after the tick-140 snapshot.

Coverage notes:

- **Nether breach/transfer/Hanging Court:** no additional concrete correctness defect was
  confirmed; dimension checks, cooldown cleanup, idempotent replay, and destination build
  ordering are coherent in the audited paths.
- **End disc/spires/config:** findings are the dragon-beat integration and End config
  activation ordering above; materialization cursors and crystal persistence are otherwise
  restart-aware.
- **Disc map/ore freeze:** painted heightmap loading and map-seed plumbing consistently use
  the save snapshot; the confirmed defects are reload authority, not seed use.
- **Fog/structures:** inactive-site propagation to `StormRegistry` does update the in-memory
  site row; the confirmed defects are lair/refreeze reconciliation and failure/cancellation.
- **Goals/localization:** current quest completion calls the receiver-localized
  `Localized` announcement overload. The raw-string overload has no live caller, so it is
  not reported as a bug.
- **Realtime/start/Limbo:** realtime's normal boundary math passed static scrutiny; the
  start ordering and late-login race are the material progression defects.
