# W4-CLOSEOUT — OLD-PLAN partial closeout (verification-first)

Closes the remaining `docs/plans_v3/eval/IDEAS-D_completeness.md` PARTIAL items that the
`91d5c56` fix wave did not fully land. Every item was VERIFIED against the current tree
first; only confirmed-broken items were touched.

## Per-item results

| # | Item | Result |
|---:|---|---|
| 1 | bossbar v3: progress remains full | **FIXED** (server-side; client `BossbarSkin` was already correct) |
| 2 | mansion/outpost/ancient-city retry adjusts position | **FIXED** (retries were deterministic re-fails) |
| 3 | Xbox participation reward for early leavers | **VERIFIED-OK** (no change) |
| 4 | start-disc teleport ordering via `StartAssignmentService` | **VERIFIED-OK** (no change) |
| 5 | sidebar craft-hint rows payload-driven + localized | **VERIFIED-OK** (no change) |
| 6 | scoreboard/HUD online-count leaks | **VERIFIED-OK in code; leftover lang keys removed** |
| 7 | `InvLockSync` armor rows vs armor unlock day | **VERIFIED-OK** (no change) |
| 8 | `requestssongs.md` closeout | **DONE** (marked done, kept for history) |
| 9 | `docs/DEV_COMMANDS.md` | note below — not hand-edited |
| 10 | EVAL-1/2/3/5 Critical audit | see "EVAL Critical status" below |

## Item 1 — buff bossbar progress (FIXED)

The GOAL-themed buff bossbar stayed full because `TimedBuffService.refreshBossbar` set
`total = Math.max(remaining, 1L)` — progress was always `remaining/remaining = 1.0`.
The DAY bar (`RealtimeDayService`, real `boundary - prevBoundary` window) and every
boss-health bar were already correct; the client `client/hud/BossbarSkin.java` renders
whatever fraction the `LerpingBossEvent` reports and needed no change.

- `buffs/BuffMath.java` — `ActiveBuff` gained `totalDurationMillis` (full granted window;
  grows on STACK extension; `0` = unknown/legacy). Old 3-/4-arg constructors delegate, so
  existing call sites and gametests compile unchanged.
- `buffs/BuffState.java` — persists/loads `totalDurationMillis` (absent in pre-v3 saves →
  0); `updatePeriodicFire` preserves it.
- `buffs/TimedBuffService.java` — `refreshBossbar` divides remaining by the persisted
  total; legacy entries reconstruct the denominator from the definition's
  `defaultMinutes()`, clamped ≥ remaining so the fraction never exceeds 1.

## Item 2 — vanilla-structure placement retries (FIXED)

The fix wave's retry-not-placed (`StructurePendingRegistry`, `FAILURES` up to 3, row
abandoned WITHOUT a placed record) was verified present — but each retry re-ran
`Structure.generate` with the identical `mapSeed + attempt` seeds at the identical anchor
chunk, so retries 2/3 failed deterministically the same way.

- `worldgen/structure/StructurePendingRegistry.java` — new `failureCount(siteId)` accessor
  (failure counts were already persisted in SavedData rows, so retries survive restart).
- `worldgen/structure/StructureStamper.java` — `placeWithFallback`/`placeCavity` now derive
  a per-retry anchor (`retryAnchor`: retry 1 exact, retries 2/3 shift 24 blocks diagonally
  on alternating sides — always a fresh start chunk, still inside the landmark footprint;
  plateau anchors re-derive surface Y at the shifted column, cavity anchors keep their
  authored depth) and pass `retry * VANILLA_ATTEMPTS` as a seed nudge so fresh jigsaw
  layouts are rolled. New `generateVanilla(..., seedNudge)` overload; the 3-arg signature
  delegates with 0 (callers in `UndergroundSites`/`StrongholdEmergence` unchanged).
- `worldgen/structure/VanillaLandmarks.java` — `placeVanillaAsync(..., seedNudge, ...)`
  overload; the old signature delegates with 0 (`HangingCourtBuilder` unchanged).
- SitePrep terraforming itself needed no relaxation: the plateau/cavity prep always
  succeeds around whatever anchor it is given; the failure source was `Structure.generate`.

## Item 3 — Xbox participation reward (VERIFIED-OK)

`XboxEventState.addParticipant` fires on dimension ENTRY and is persisted; no exit path
(death, death-lockout, voluntary `/xboxleave`, close) removes participation — only a new
`beginInstance` clears the set. `beginClosing` grants the reward when the participant set
is non-empty, guarded by the persisted once-per-instance `markRewardGranted()` (fix wave),
and the reward is a server-wide timed buff, so a player who entered and left early still
counts and still benefits at close. Crash-recovery re-close cannot double-extend.

## Item 4 — start-disc teleport ordering (VERIFIED-OK)

`StartEventCutscene.teleportLimboPlayersToDiscs` resolves ONE
`StartAssignmentService.assign(server, inLimbo)` map and uses the same entry for the
physical teleport and the `discCenters` map handed to `IntroSequence.start` — the
"player-list order vs sorted-UUID order" divergence is gone. The t=140→t=160 login race is
closed by the re-run inside `emerge()` before `startEventDone` commits. Late joins during
FLIGHT (or any later intro phase) are covered: `LimboGate` (login + respawn) calls
`gatherLateJoiner`, which assigns from the persisted service and transports while
`running || IntroSequence.isRunning()`. `IntroSequence.Run.discCenters` is informational
only (never read after construction), so a late joiner absent from that map is not a gap.

## Item 5 — sidebar craft hints (VERIFIED-OK)

There is no dedicated "craft hints" row; craft hints surface as craft-type goal rows
(`CRAFT_ITEM` quests) in the sidebar goals section. They are payload-driven
(`S2CQuestStatePayload.QuestEntry` ships authored en+de literal pairs — deliberate R2
anti-datamining, not lang keys) and localized client-side (`SidebarExpanded.goalText`
picks `textDe` when the locale starts with `de`). Buff rows use the same en/de pattern.
Nothing hardcoded-EN.

## Item 6 — online-count leaks (VERIFIED-OK + leftover keys removed)

- `S2CSidebarStatePayload` carries no player count ("removed by design"); no
  `getPlayerCount`/`players().size()` reads anywhere in `client/` or `hud/`.
- Handbook `StatusTab` dropped the "souls awake" row (v2 → v3, anonymity).
- Removed the three dead leftover keys from BOTH `en_us.json`/`de_de.json`:
  `gui.eclipse.handbook.status.online.many`, `gui.eclipse.handbook.status.online.one`,
  `sidebar.eclipse.online`. Parity re-verified (1422 keys per locale). No langdrop ever
  contained them, so a langdrop re-merge cannot resurrect them.

## Item 7 — armor unlock day sync (VERIFIED-OK)

`InvLockSync.earliestGrantDay(KEY_ARMOR)` scans the live `EclipseConfig.days()` plans, and
`UnlockState` unlocks `armor` purely day-driven (it is in neither `DAY_GRANT_GATES` nor
the enchanting boss gate), so tooltip day == actual unlock day by construction (day 4 in
the default config). Slot split matches on all three layers (`PhaseInventoryLock` sweep,
`InvLockSync.computeLockedBits`, client `InvLockClientState.unlockDayFor`): armor rows are
container slots 36–40. Config reloads propagate through the 1 Hz poll + payload equality.

## Item 8 — requestssongs.md (DONE)

`/workspace/requestssongs.md` (repo-adjacent, workspace root) now carries a DONE banner:
key provided via the `TREBLO_API_KEY` secret, 15 V3-model songs generated on 2026-07-24
via `tools/music/treblo_generate.py` (15 `TRACKS` entries). File kept for history.

## Item 9 — docs/DEV_COMMANDS.md

Do NOT hand-edit `docs/DEV_COMMANDS.md`: the orchestrator regenerates it in-game from the
live command registry (`/dev docs regen` path — see commit `a9818be` "regenerated
DEV_COMMANDS.md from live registry"). Any drift observed there is resolved by the next
in-game regeneration, not by manual patches.

## Item 10 — EVAL Critical status

Verified against `91d5c56` and the current tree:

- **EVAL-1 (all 6 HIGH): addressed.** Frozen-radii reload coherence (`FrozenParams`
  `ReloadHooks` "frozen-worldgen" restores save-frozen radii on ordinary reload); personal
  quest isolation (`QuestEngine.isEligible` — personal specs only mutate the assigned
  UUID; reroll rebuilds the detector index); dragon victory beat
  (`EclipseDragonFight` fires `QuestApi.completeTeamBeat("dragon_defeated")`);
  start-disc ordering + limbo late-join rescue (item 4 above); failed placements recorded
  retryable, and retries now actually adjust (item 2 above).
- **EVAL-2 (C1, C2): addressed.** Award/offering settlement is idempotent with a persisted
  pending-reward ledger (rewards removed from the ledger before application; restart-safe
  delivery on login); analytics distinct block/chunk identities persist in
  `AnalyticsState` SavedData so restarts cannot re-fire exploration rewards.
- **EVAL-3 (H-1): addressed.** Expanded-sidebar timers compute from
  `estimatedServerNow()` (epoch clock payload + epoch-elapsed), never mixing monotonic
  `Util.getMillis()` into epoch math.
- **EVAL-5 C1: STILL-OPEN (policy/architecture).** Anonymity remains presentation-only:
  real `GameProfile`s still reach every client; render/UI hiding cannot hold against
  modified clients. Fixing this needs pseudonymous profiles or a proxy layer — an
  architectural decision, deliberately NOT attempted in this closeout. If honest-client
  privacy is the intended threat model, document that explicitly.
- **EVAL-5 C2: STILL-OPEN (intentional feature).** The logout-ghost hit reveal sends the
  owner's real name by design (requirement #78 "logout ghosts, hit reveal"); it is a
  deliberate, documented exception to anonymity. Needs a policy call, not a code fix.

## Langdrop

`docs/plans_v3/langdrop/W4-CLOSEOUT.json` is intentionally EMPTY (en+de): this wave adds
no keys; it only deletes the three dead online-count keys directly from the shipped lang
files (the additive langdrop merger has no removal semantics).

## Files touched

- `src/main/java/dev/projecteclipse/eclipse/buffs/BuffMath.java`
- `src/main/java/dev/projecteclipse/eclipse/buffs/BuffState.java`
- `src/main/java/dev/projecteclipse/eclipse/buffs/TimedBuffService.java`
- `src/main/java/dev/projecteclipse/eclipse/worldgen/structure/StructurePendingRegistry.java`
- `src/main/java/dev/projecteclipse/eclipse/worldgen/structure/StructureStamper.java`
- `src/main/java/dev/projecteclipse/eclipse/worldgen/structure/VanillaLandmarks.java`
- `src/main/resources/assets/eclipse/lang/en_us.json`
- `src/main/resources/assets/eclipse/lang/de_de.json`
- `/workspace/requestssongs.md`
- `docs/plans_v3/langdrop/W4-CLOSEOUT.json` (new)
- `docs/plans_v3/wiring/W4-CLOSEOUT_wiring.md` (this file)
