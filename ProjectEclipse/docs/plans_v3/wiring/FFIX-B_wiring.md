# FFIX-B wiring notes (final-eval SAFETY fixes per FINAL-SAT-SOL + FINAL-POLISH-SOL)

All ten fixes are self-contained code changes — no new registries, payloads, configs or
commands. One new lang key (see below). No data migration needed: every new NBT field
defaults sanely when absent from old saves.

## What shipped

### 1. Contract reward ids are day-scoped (FINAL-SAT-SOL C1)

`contracts/ContractService.resolveExpired` now queues the survivor consolation as
`contract_survived:<contractDay>` (was the constant `contract_survived`), and passes the
contract's own day to the award-void check. An offline survivor therefore receives the
consolation for EVERY survived contract, not once per save.

### 2. Daily-award resolution respects AWARD_VOID (POLISH-SOL-01)

`awards/AwardService.resolveDay` excludes voided winners when freezing `rewardGrants`;
`queueResolvedRewards` re-checks with the RECORD's day (covers pre-fix frozen records).
`queueReward` gained an explicit-day overload — callers settling a PAST day
(`ContractService.resolveExpired`, `OfferingService.queueWinnerRewards`) pass that day
instead of letting the check read the mutable current day after rollover.

### 3. Paused realtime days no longer consume the contract window (POLISH-SOL-04)

`contracts/ContractState` persists `pauseAnchorEpochMillis` (NBT `pauseAnchor`);
`ContractService.onServerTick` maintains it while `RealtimeDayApi.isPaused()`, and
`resumeOnBoot` shifts the deadlines by the offline gap before any expiry check. The old
transient `lastPauseCheckMillis` static is gone.

### 4. Contract reveal face futures are session-scoped (POLISH-SOL-05)

`client/contracts/ContractRevealOverlay`: `FACE_GENERATION` counter + volatile
`targetUuid`; skin-loader callbacks land through `acceptFace(generation, uuid, skin)` and
are dropped when either token moved on. `reset(false)` and the new client
`LoggingOut` handlers (also in `ContractClientState`) invalidate everything at the
session boundary.

### 5. Wand cast server validation (POLISH-SOL-03)

`wand/WandPowers.isActorValid` — alive, not removed, not spectator — gates both
`handleCast` and `handleChoosePath` before any other work. Existing checks (held wand,
owner, path, charge, cooldown, disable, protection) already covered the rest.

### 6. Phasenwelle durable snapshots (FINAL-SAT-SOL C2 / POLISH-SOL-02)

`core/state/EclipseSavedData.flushOverworld(server)` — `DimensionDataStorage.save()` +
`IOUtilities.waitUntilIOWorkerComplete()` — is the new durability barrier.
`wand/WandPhaseService.castWave` flushes the snapshot journal BEFORE the first block
turns to air; `restoreAllOnLoad` now reconciles ALL entries (including `vanished=false`
prepare records) against the actual block state.

### 7. Freeze lock ownership (POLISH-SOL-06)

`cutscene/CutsceneLock.ownerToken` + `FreezeService.freeze/unfreeze(…, ownerToken)`
overloads. `admin/ActionTogglesService` tags its move-deny freezes with
`action_toggles:move` and releases ONLY locks carrying that token — cutscene locks are
never stolen or released by the toggle reconciler.

### 8. Voice pipeline retry cap (FINAL-SAT-SOL H5)

`voice/VoiceChangerPlugin` removes + `closeQuietly()`s a pipeline on DSP failure and
reports to `VoiceChangerService.reportPipelineFailure`; 3 consecutive strikes trip the
existing `autoDisabled` kill switch. Strikes clear on a successful frame, disconnect,
server start and `resetAutoDisable`.

### 9. Hearth AFK regen cap (FINAL-SAT-SOL L1)

`drama/HearthAuraService`: `MAX_HEARTS_PER_DAY = 5` per player per Eclipse day
(`tryConsumeDailyHeal`, keyed by the persisted Eclipse day; map clears on rollover/stop).
Two parked alts now stop healing after 5 hearts/day each — the social sit-together loop
is untouched.

### 10. Minigames (FINAL-SAT-SOL C3, H1–H4 / POLISH-SOL-08)

- **(a) Durable ticket before inventory clear** — `MinigameService.enter` calls
  `EclipseSavedData.flushOverworld` AFTER `putTicket`/`addParticipant`, BEFORE
  `clearContent()`. The exit direction deliberately stays restore-then-remove with no
  flush: removing the ticket durably before the restored player NBT lands would invert
  the hazard.
- **(b) All dimension exits tracked** — new `onPlayerChangedDimension` watchdog: a ticket
  holder leaving a minigame dim for a non-minigame dim (admin tp, other systems) gets the
  ticket restored IN PLACE (destination respected, like login rescue), ticket released,
  participation settled, transient maps/bossbar cleaned. `EXIT_IN_PROGRESS` guards
  against `exitToTicket`'s own teleport re-entering the watchdog.
- **(c)+(e) Offline + crash-idempotent payouts** — new persisted payout ledger in
  `MinigameState` (`PendingPayout(id, shards, skillXp)`, `queuePayout` /
  `pendingPayouts` / `claimPayout`), mirroring `AwardsState`'s queue/claim pattern:
  queue once by stable id, durably claim BEFORE any grant
  (`MinigameService.grantPayout`). Arena podium (`ArenaGame.endRound`) queues
  `minigame:arena:<openCount>:<roundKey>:place:<n>` for top-3 whether online or not
  (roundKey = the round deadline, captured before its reset); race podium
  (`ElytraRace.finishLap`) uses `minigame:race:<openCount>:finish:<position>`;
  participation uses `minigame:participation:<openCount>`. Queued payouts deliver at
  login (`deliverPendingPayouts`) with the new `eclipse.minigame.reward.late` line.
- **(d) Instance scoping** — the ledger survives `beginInstance` (like tickets), ids are
  instance-scoped, and `settleParticipation` queues every participant's entitlement in
  `beginClosing` (plus defensively in `start` before `beginInstance`, for saves written
  before this fix). A new instance can no longer erase a prior instance's unclaimed
  entitlements.
- `MinigameState.markParticipationRewarded` (and its NBT list) stays for compatibility
  and gametest coverage, but no longer gates the payout — the ledger does.

## Lang

- `docs/plans_v3/langdrop/FFIX-B.json` → merge `eclipse.minigame.reward.late` (en+de)
  into `assets/eclipse/lang/en_us.json` / `de_de.json`. Args: %1$s shards, %2$s skill XP.
  Used only by the deferred login delivery; the live participation/podium lines are
  unchanged.

## New NBT (all backwards-compatible; absent = default)

| SavedData | Tag | Meaning |
|---|---|---|
| `eclipse_contracts` (`ContractState`) | `pauseAnchor` (long) | last pause-checked wall clock; 0 = not paused |
| `eclipse_minigame_event` (`MinigameState`) | `pendingPayouts` (list) | per-player queued payouts `{uuid, payouts:[{id, shards, xp}]}` |
| `eclipse_minigame_event` (`MinigameState`) | `deliveredPayouts` (list) | per-player claimed payout ids `{uuid, ids:[string]}` |

## Operational notes

- `EclipseSavedData.flushOverworld` blocks the server thread for the IO worker; it is
  called only from rare one-shot events (Phasenwelle cast, minigame entry) — never
  per-tick.
- The voice kill switch re-arms exactly like the budget switch: `/dev voice reset`
  (`VoiceChangerService.resetAutoDisable`) also clears the strike counter.
- The hearth cap (5 hearts/day) is code-constant, not config — flagged for a follow-up
  if operators want it tunable.
