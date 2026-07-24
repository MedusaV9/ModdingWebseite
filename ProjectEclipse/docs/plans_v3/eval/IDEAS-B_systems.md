# IDEAS-B — Systems Robustness + Operator Experience

Ranked by expected reduction in live-event risk for a roughly 20-player server, then by operator leverage.

## 1. Persisted sequence journal with explicit recovery policies

Before each externally visible phase, persist a run record containing the sequence id, run id, phase, participants, return anchors, and a `RESUME` / `FINISH_SAFE` / `ROLLBACK` recovery policy; mark the phase complete only after its idempotent side effects finish. This would replace the current mix of transient state (`StartEventCutscene.running`), skip-to-end recovery (`IntroSequence` and `ExpansionSequence`), and ritual-specific recovery with one inspectable boot-time mechanism, preventing a restart between Limbo teleport and `startEventDone` from stranding part of the roster.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/limbo/StartEventCutscene.java`, `sequence/IntroSequence.java`, `sequence/ExpansionSequence.java`, `ritual/FinaleRitual.java`, `core/state/EclipseWorldState.java`; new `core/state/EventRunData.java` and `sequence/EventRunJournal.java`.  
**Effort:** M

## 2. One `/dev status` dashboard with PASS/WARN/FAIL health checks

Merge the overlapping `/eclipse status` and timeline dump into a compact `/dev status` summary backed by an `EventHealthReport`, with clickable detail sections for progression, jobs, sequences, players, and config. Checks should flag persisted/runtime phase disagreement, overdue schedules, stale growth cursors, old or unplaceable pending structures, missing backups, stranded return anchors, cutscene watchdogs, and active persisted fog sites missing from `StormRegistry`; also emit the same report as structured JSON in the server log for remote monitoring.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/devtools/TimelineInspector.java`, `devtools/dev/DevRoot.java`, `admin/EclipseCommands.java`, `devtools/PhaseScheduler.java`, `worldgen/stage/RingGrowthService.java`, `worldgen/structure/StructurePendingRegistry.java`, `cutscene/CutsceneService.java`, `cutscene/FreezeService.java`, `stormfx/StormRegistry.java`, `worldgen/fog/FogStormSites.java`; new `devtools/EventHealthReport.java`.  
**Effort:** M

## 3. Dry-run stage plans with state-bound confirmation tokens

Add `/dev stage plan <load|restore|grow> ...` that performs no writes and reports old/new radii, affected chunks, players currently inside the rewrite band, player-placed block count, block entities/containers, pending structure changes, and estimated backup size/time. Return a short-lived digest token that the destructive command must receive as `--confirm <digest>`; reject it if the stage, config hash, or affected-chunk set changed after the plan was produced.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/devtools/dev/DevStageCommands.java`, `devtools/StageIO.java`, `devtools/StageBackups.java`, `worldgen/stage/WorldStageService.java`, `worldgen/stage/RingGrowthService.java`, `analytics/PlacedBlockTracker.java`, `analytics/PlacedBlockData.java`; new `devtools/StagePlan.java`.  
**Effort:** M

## 4. Versioned day-5+ late-join onboarding

When `startEventDone` is true and a player has no onboarding record, give them a stable start-disc assignment, a safe invulnerable arrival, a short catch-up cutscene/handbook flow, and one atomic sync of current day, unlocks, goals, lives, stages, border, and timeline state; persist an onboarding version before granting any one-time starter resources so retries cannot duplicate rewards. Add `/dev onboard inspect|retry <player>` so an operator can see the last completed step and safely resume a disconnect without replaying the global intro.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/start/StartAssignmentService.java`, `start/StartState.java`, `limbo/LimboGate.java`, `network/EclipsePayloads.java`, `cutscene/CutsceneService.java`, `progression/UnlockSync.java`, `progression/goals/QuestEngine.java`, `lives/LivesApi.java`; new `start/LateJoinOnboarding.java` and persisted `start/OnboardingState.java`.  
**Effort:** M

## 5. Lag-aware cutscene READY barrier and degraded fallback

Extend the existing cutscene ACK protocol with `PREPARE(pathHash, startTick)` and `READY`, allowing up to a small bounded window for clients to load the path/chunks before a synchronized start; show READY/STARTED/FINISHED state per player in `/dev status`. A client that never becomes ready should receive a short fade/caption fallback and be removed from the completion quorum, so one laggy or packet-losing player neither misses an unsafe teleport nor holds a 20-player sequence until the full watchdog expires.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/cutscene/CutsceneService.java`, `cutscene/client/CameraDirector.java`, `network/C2SCutsceneStatePayload.java`, `network/S2CCutscenePlayPayload.java`, `sequence/IntroSequence.java`, `sequence/ExpansionSequence.java`, `ritual/FinaleRitual.java`, `devtools/TimelineInspector.java`.  
**Effort:** M

## 6. Transactional, self-describing hot reload

Replace the split `ReloadHooks` / `DevReloadRegistry` orchestration with descriptors that declare source files, validation, prepare/apply/rollback, client re-sync, and a last-loaded content hash; `/dev reload --check` should validate every target first and mutate nothing. This closes the current observability hole where `ReloadHooks` catches an exception internally but `DevReload` still prints the bridge as successful, and prevents documentation drift such as the `music.json` reference even though music uses client-side `eclipse-music.toml`.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/core/config/ReloadHooks.java`, `core/config/EclipseConfig.java`, `devtools/dev/DevReload.java`, `devtools/dev/DevReloadRegistry.java`, `music/MusicConfig.java`, and config loaders under `progression/`, `skills/`, `buffs/`, `analytics/`, `protection/`, `worldgen/`, and `xboxevent/`; new `core/config/ReloadTarget.java`.  
**Effort:** M

## 7. Player-build-aware ring growth and restore

Use the existing placed-block chunk attachment during stage planning and execution: snapshot connected clusters of player-placed blocks and their block entities in the rewrite band, then either restore them after terrain generation or refuse the operation above a configurable risk threshold unless explicitly overridden. Record stale-tracker caveats such as piston/explosion movement in the plan, and keep the existing full terrain backup as the final rollback rather than silently allowing `RingGrowthService`'s full-chunk rewrite to erase builds.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/worldgen/stage/RingGrowthService.java`, `analytics/PlacedBlockTracker.java`, `analytics/PlacedBlockData.java`, `devtools/StageBackups.java`, `devtools/StageIO.java`, `registry/EclipseAttachments.java`; new `worldgen/stage/BuildPreservationPlan.java`.  
**Effort:** M

## 8. Boot-time reconciliation for persisted intent versus transient registries

Introduce a registry of idempotent reconcilers that runs after all dimensions and placers are available, rebuilding transient runtime state from SavedData and reporting discrepancies instead of relying on each subsystem's event-order assumptions. Initial reconcilers should cover active fog sites versus storms, pending/in-flight structures, FX anchors, running realtime bossbars, Xbox participants/returns, and finale boss/arrival state; missing dimensions or entities should produce a health warning and retain the recovery row rather than destructively “completing” it.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/worldgen/fog/FogStormSites.java`, `stormfx/StormRegistry.java`, `worldgen/structure/StructurePendingRegistry.java`, `veilfx/FxAnchors.java`, `progression/realtime/RealtimeDayService.java`, `xboxevent/XboxEventService.java`, `xboxevent/XboxEventState.java`, `ritual/FinaleRitual.java`; new `core/state/StartupReconciler.java`.  
**Effort:** M

## 9. Adaptive lag circuit breaker for terrain and structure jobs

Track rolling MSPT plus blocks, sections, chunk packets, and structure jobs processed per tick, then automatically pause noncritical work when the server exceeds a configurable threshold and resume only after sustained recovery. `/dev jobs` should expose queue depth, ETA, current throttle reason, and safe pause/resume controls, preventing a growth sweep and several `SitePrep` placements from stacking into a watchdog-triggering lag spike while 20 players are online.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/worldgen/stage/RingGrowthService.java`, `worldgen/stage/BudgetedBlockWriter.java`, `worldgen/structure/SitePrep.java`, `worldgen/structure/StructurePendingRegistry.java`, `core/config/EclipseConfig.java`, `devtools/TimelineInspector.java`; new `devtools/WorkloadGovernor.java` and `devtools/dev/DevJobsCommands.java`.  
**Effort:** M

## 10. `/dev player doctor` for stranded-state diagnosis and repair

Add `/dev player doctor <player> [--fix]` to detect contradictory or unsafe states: Limbo after event start, no disc assignment, stale Nether/finale return, a freeze without a cutscene session, banned/lives mismatch, or a player outside the current soft border. The default command should be read-only and explain every proposed action; `--fix` should snapshot location/state first and apply idempotent subsystem APIs rather than editing NBT fields directly.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/limbo/LimboGate.java`, `start/StartAssignmentService.java`, `sequence/ExpansionSequence.java` and its `NetherReturns`, `ritual/FinaleRitual.java`, `cutscene/FreezeService.java`, `cutscene/CutsceneService.java`, `lives/BanService.java`, `border/SoftBorder.java`, `core/snapshot/SnapshotService.java`; new `devtools/dev/DevPlayerDoctor.java`.  
**Effort:** M

## 11. Destination-based protection rules plus an operator probe

Harden sanctum protection around the destination of effects, not only the initiating player/entity: cancel explosion block damage, piston pushes, dispenser fluids, fire spread, falling blocks, end-crystal damage, and vehicle movement into the protected cylinder even when triggered from outside it. Add `/dev protection probe <x> <y> <z> <action>` that reports the matched zone, rule, and exemption, making boundary grief reports reproducible without trial-and-error edits to `protection.json`.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/protection/SpawnProtectionRules.java`, `protection/ProtectionConfig.java`, `worldgen/structure/SanctumProtection.java`, NeoForge block/explosion/piston/fire/entity event handlers; new `devtools/dev/DevProtectionCommands.java`.  
**Effort:** M

## 12. Crash-point rehearsal suite for every irreversible phase

Add test-only crash points immediately before and after each journaled side effect, then GameTests that save/reload at those points and assert a single final outcome: no duplicate boss/reward/structure, no lost return anchor, no frozen player, and no half-committed stage. A `/dev rehearse check` command can list which live sequence phases have recovery coverage, giving operators a concrete pre-event readiness signal without enabling fault injection on production servers.

**Files/systems:** `src/main/java/dev/projecteclipse/eclipse/gametest/`, `limbo/StartEventCutscene.java`, `sequence/IntroSequence.java`, `sequence/ExpansionSequence.java`, `ritual/FinaleRitual.java`, `worldgen/stage/RingGrowthService.java`, `worldgen/structure/StructurePendingRegistry.java`; new `gametest/recovery/SequenceRecoveryTests.java` and `devtools/dev/DevRehearsalCommands.java`.  
**Effort:** M
