# P4-B2 wiring notes (goal & personal-quest engine)

No hub/foreign files were edited beyond the two the §3.0 matrix assigns to B2:
`progression/GoalTracker.java` (adapter rework) and `network/S2CGoalProgressPayload.java`
(re-source, wire shape UNCHANGED). Everything else lives in `progression/goals/**` +
`gametest/goals/**`. No registry, `EclipseMod`, `EclipsePayloads` or command-tree edits —
`/eclipse-quests` registers itself via `RegisterCommandsEvent` like `/eclipse-skills`.

## New public surface

| Class | Role |
|---|---|
| `progression/goals/TriggerType` | FROZEN 17-id trigger registry (`ids()`, `byId`, `byIdStrict`, `polled()`, `description()`) — the dropdown source for P5-W2's reworked GoalEditor |
| `progression/goals/GoalSpec` | §2.2 schema (`Kind` main/side/personal, `Scope` each_player/team_total/team_all, flat `Trigger`, `Reward`, `Localized` text, personal `weight`/`minDay`/`maxDay`); implements `EclipseSignals.QuestSpecRef` |
| `progression/goals/GoalConfig` | loads `config/eclipse/goals.json` + `quests.json` (auto-created defaults = migrated days.json arc, rebalanced harder per §3.4 anchors); `validateAndNormalize(JsonElement)` throws `IllegalArgumentException` for P5's ConfigEditor allowlist; `setDirectoryOverride(Path)` = injectable base path for tests; `generation()` bumps per reload |
| `progression/goals/QuestState` | SavedData `eclipse_quests` (overworld) — replaces the `eclipse:goal_progress` attachment, which B2 STOPPED WRITING (attachment stays registered; do not delete the registry entry without a save-compat pass) |
| `progression/goals/QuestMath` | pure deterministic seed/draw/bitmask (no MC imports) |
| `progression/goals/QuestEngine` | resolution, assignment, single completion pipeline, ONE shared 20t poll (polled triggers + built-in beats + payload coalescing), payload builder |
| `progression/goals/QuestDetectors` | all signal listeners + the two owned NeoForge events (`BabyEntitySpawnEvent`, `LivingDamageEvent.Post` night-damage flag) + night watcher |
| `progression/goals/QuestApi` | **FROZEN for P5-W4**: `mains/sides/personals/allForPlayer`, `byId`, `suggestedIds`, `progress`, `isDone`, `complete`, `revoke`, `revokeTeam`, `completeTeamBeat`, `reroll`, `resyncAll`, `triggerTypes()/triggerTypeIds()` |
| `progression/goals/QuestCommands` | `/eclipse-quests tick <p> <id> | revoke <p> <id> | reroll <p> | list [p] | reload` (perm 3) — reference caller for every QuestApi mutator |

## Signals CONSUMED (registered on ServerStarted via `QuestEngine.onServerStarted`)

`naturalBlockMined`, `blockPlaced`, `mobKilled`, `itemCrafted`, `itemSmelted`,
`chunkExplored`, `biomeVisited`, `altarDeposit`, `skillLevelUp`, `dayRollover`
(POST → resolve + assign + flush). Polled instead of signal-fed: `visit_location`,
`reach_depth`, `collect_item`, `travel_distance`, `stat_threshold` (vanilla stat deltas
against per-(day,uuid) baselines captured at assignment/login), plus built-in beat
conditions and the night window — all inside the ONE 20t poll (`QuestEngine.runPollNow`).

## Signals FIRED

- `questCompleted(player, spec, scope)` — once per credited player per completion, from
  the single pipeline (`completeForPlayer` / `completeTeam`). The `spec` ref IS a
  `GoalSpec`: **B4 (skills) grants `((GoalSpec) spec).reward().skillXp()` from this
  signal** (B2 grants shards/items itself; per §2.0 rule B-wave workers don't call each
  other's classes — B2 does NOT call SkillsApi). B5 counts `quests_done` etc. from the
  same signal — already landed.

## Team beats (data-driven successors of the hardcoded switch(day) detectors)

`trigger: { "type": "manual", "beatId": "…" }` completes when the beat fires, once per
(day, beat). Built-in polled conditions: `altar_level_<n>`, `shard_pool_<n>`,
`all_hearts_<n>`, `herald_defeated`, `ferryman_defeated`, `dragon_defeated`. External
beats fired by shims (call `QuestApi.completeTeamBeat(server, id)` from foreign code):
`herald_summoned` (fired by `GoalTracker.onHeraldSummoned` ← `HeraldsLureItem`, unchanged
call site) and `finale_begun` (`GoalTracker.onFinaleBegun` ← `FinaleRitual`, unchanged).
Admin revoke of a beat goal re-arms the beat (`QuestState.clearBeatFired`) — a still-true
built-in condition will legitimately re-complete on the next poll.

## Legacy bridge (what changed in the two edited files)

- `GoalTracker` is now a thin adapter: `complete(player, index)` → today's MAIN[index]
  manual-complete with the FULL pipeline; `mask(player, day)` → mains done-flag bitmask
  (stale day = 0, as before); herald/finale hooks → team-beat shims. DELETED: all
  `switch(day)` detectors, the `goal_progress` attachment writes, the day-1 shard-seed
  logic (migrated into the authored day-1 goal `d01_touch_altar` reward: 2×
  `eclipse:umbral_shard` + 300 skillXp) and the nether dimension-change listener
  (replaced by authored `visit_biomes #minecraft:is_nether`).
- `S2CGoalProgressPayload.currentFor` now renders TODAY'S MAINS from the engine — lines
  localized per receiver via `LangService.pick`, flags from `QuestEngine.mainDoneFlags`.
  Wire shape untouched; the old sidebar keeps working. Fallback intact: a day missing
  from goals.json renders its days.json strings as `manual` mains (`legacy_d<d>_m<i>`).

## Notes for specific workers

- **P5-W4 (`DevQuestCommands`)**: bridge to `QuestApi` (`complete` fires announce/rewards/
  signal side effects; `revoke` un-completes and clears progress+baselines; both return
  false on no-op). Suggestion provider: `QuestApi.suggestedIds(server)`. ConfigEditor
  allowlist: `GoalConfig.validateAndNormalize` accepts BOTH file shapes (`{"days":[…]}` /
  `{"quests":[…]}`) and throws `IllegalArgumentException` with a human-readable message.
- **P5-W2 (GoalEditor rework)**: type dropdown from `QuestApi.triggerTypes()` (stable ids,
  `polled()` flag, English `description()` tooltip). Round-trip files through
  `validateAndNormalize` before writing.
- **P4-B3 (content)**: author real `goals.json`/`quests.json` over the built-in defaults
  (14 days × 3 mains + 3-5 sides, 21-entry personal pool already migrated as a baseline).
  CAVEAT: default `d01_touch_altar` is `visit_location x=0 z=0 r=10` — the legacy
  detector followed the DYNAMIC sanctum altar position; re-author with the real spawn
  coords for the live world (or as `deposit_altar`). Counts: `travel_distance` in meters,
  `stat_threshold` in raw stat units (distances cm, damage tenths of hearts).
- **P4-B6 (altar)**: keep firing `altarDeposit` from all three deposit paths — the
  `deposit_altar` trigger (and day 7 `d07_core`) depends on it. `d02_altar_1`/`d08_altar_4`
  poll `EclipseWorldState.getAltarLevel()`; no altar-side work needed.
- **P3 (HUD)**: `S2CQuestStatePayload` is fed on login, on every progress change
  (coalesced ≤1s) and on day/config change; `entries` order = mains, sides, personals.
  MAIN completions additionally announce via `AnnouncementService.announceGoalCompleted`
  with the EN literal (overlay renders literals — the documented seam if P3 wants to
  localize announcements later). Sides/personals are action-bar only (anonymity rule).

## Plan gaps / deviations (orchestrator attention)

1. **`/eclipse goals tick` index seam**: the untouchable command validates `index` and
   prints goal text against `EclipseConfig.day(day).goals()` (days.json strings) BEFORE
   calling `GoalTracker.complete`, which maps the index onto goals.json MAINS. With the
   shipped defaults both lists are 3-per-day so indexes agree, but if B3 authors ≠3 mains
   the command's pre-check text/range can drift from what actually ticks. Fix belongs to
   the command owner (P5-W4 bridge supersedes it anyway).
2. **`/eclipse-quests revoke` added** beyond the §3.3 command list — reference caller for
   the frozen `QuestApi.revoke` that P5-W4's acceptance ("revoke un-completes") needs.
3. **Reroll nonce**: personal draws use `seed(worldSeed, uuid, day, nonce)` with a
   persisted per-(day,uuid) nonce (0 = daily assignment) so `reroll` stays deterministic —
   a superset of the plan's `hash(worldSeed, uuid, day)`.
4. **Gametest harness**: A1's `GameTestSupport.mockSurvivalPlayer` casts vanilla
   `makeMockPlayer` to `ServerPlayer` (CCE at runtime — already flagged by B5); B2 tests
   use `helper.makeMockServerPlayerInLevel()` directly. Also
   `HarnessSmokeTest.signalsDispatchAndClear` wipes ALL signal listeners mid-run and
   never re-arms the service registrations; B2 tests re-arm via the public
   `QuestDetectors.rearmSignalListenersForTest(server)` (clears + re-registers ONLY quest
   listeners). Sibling packages with signal-driven tests need the same pattern, or A1
   should make the smoke test restore listeners.
5. **Night watcher restart semantics**: eligibility is in-memory by design (statics reset
   on ServerStopped) — a server restart mid-night forfeits that night for everyone online
   (nobody was "online the whole night" of the surviving process). Documented, not a bug.
6. **`skill_level` trigger**: progress mirrors the highest level reached via the
   `skillLevelUp` signal only — players already past the level before assignment don't
   auto-complete until the next level-up (B4 could expose a level query later; not needed
   for the shipped content which uses it only in the personal pool).
