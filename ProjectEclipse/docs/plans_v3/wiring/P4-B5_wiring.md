# P4-B5 wiring notes (analytics + placed-block tracker)

No hub/foreign files were edited. All B5 code lives in `analytics/**` +
`gametest/analytics/**`; everything below is read-only consumption or a note for the
orchestrator / sibling workers.

## Signals FIRED by analytics (single owner per §2.0 rule 6 — do NOT re-subscribe the raw events)

| Signal | Fired when | Notes |
|---|---|---|
| `naturalBlockMined(player, state, pos)` | `BlockEvent.BreakEvent` (LOW), placed-bit check says NATURAL, player is tracked | placed-bit is cleared FIRST; player-built breaks fire nothing (fail-safe) |
| `blockPlaced(player, state, pos)` | `BlockEvent.EntityPlaceEvent` (LOW) | fired once PER BLOCK — a door/bed multi-place fires once per half, matching `place_total` |
| `mobKilled(player, victim)` | `LivingDeathEvent` (LOW, after `lives/LifecycleEvents`), non-player victim, tracked player killer | |
| `playerDeath(victim, killerOrNull)` | `LivingDeathEvent` (LOW), player victim | fires for ALL players (counter only for tracked) |
| `itemCrafted(player, stack)` | `ItemCraftedEvent` (LOW) | empty (ModGate/RecipeGate-confiscated) results neither count nor fan out |
| `itemSmelted(player, stack)` | `ItemSmeltedEvent` (LOW) | |
| `chunkExplored(player, chunkPos)` | 1 Hz sampler, first visit of that chunk THAT DAY | per-day-distinct, capped at `chunkSetCap` |
| `biomeVisited(player, biomeId)` | 1 Hz sampler, first LIFETIME visit of that biome | lifetime set persists in `eclipse_analytics` |

"Tracked" = real (non-`FakePlayer`) player in SURVIVAL/ADVENTURE via
`AnalyticsService.isTracked` (authoritative `player.gameMode.getGameModeForPlayer()`, not
the abilities flag). Untracked actors still update placed bits (world truth) but never
earn counters or trigger signals.

## Signals CONSUMED by analytics (registered on ServerStarted)

- `altarDeposit` → `altar_value` (MILESTONE/OFFERING × value points) / `shards_banked`
  (SHARD_BANK). **B6 must fire the signal from all three altar paths.**
- `questCompleted` → `quests_done` + `mains_done`/`sides_done`/`personals_done` by `kind()`.
- `dayRollover` (PRE) → per-day scratch reset (place-type + chunk sets) and
  `retentionDays` prune. The day cut itself is inherent: every write keys off the CURRENT
  `EclipseWorldState` day, which flips inside `DayScheduler.setDay` right after PRE.

## Plan gaps found (orchestrator attention)

1. **No `animalBred` / `villagerTraded` signals exist in A1's frozen `EclipseSignals`**,
   though §2.3's earn table has `breed: 6` / `trade: 10` and §2.4 says analytics listens to
   the goal engine's breed "signal". B5 therefore counts `breed_total` via its own
   count-only LOW `BabyEntitySpawnEvent` listener (B2 still owns the trigger detection per
   §2.2 — no double signal risk, analytics fires nothing for breed) and `trade_total` via
   `TradeWithVillagerEvent`. If signals are added to `EclipseSignals` later, analytics can
   switch with a one-line change. B4 (skills) has the same gap for its breed/trade XP.
2. **`altarDeposit` carries no value points** — analytics computes `altar_value` from
   `offering_values.json` READ-ONLY (`analytics/DepositValues`, plan §2.6 defaults built in;
   file creation/ownership stays with B6). The enchanted ×1.5 bonus is not applied (the
   signal has no ItemStack) — deliberate under-credit; B6's own resolution computes exact
   offering scores independently.
3. **A1 gametest helper bug**: `GameTestSupport.mockSurvivalPlayer` casts
   `helper.makeMockPlayer(...)` to `ServerPlayer`, but vanilla returns an anonymous
   `Player` → guaranteed `ClassCastException`; the NeoForge-correct call is
   `helper.makeMockServerPlayerInLevel()` (registers via `PlayerList.placeNewPlayer`, but
   hardcodes `isCreative() == true`, hence the game-mode-based `isTracked` above). B5's
   tests use `makeMockServerPlayerInLevel` directly. A1 should fix the helper the same way.
4. **A1's `HarnessSmokeTest.signalsDispatchAndClear` calls
   `EclipseSignals.clearAllListeners()` mid-run**, wiping every production listener on the
   shared gametest server for later-ordered tests. B5 tests are immune (fresh recorders +
   direct handler calls), but any suite relying on ServerStarted-registered listeners will
   flake. Suggest the harness test restore state or run last.

## For B6 (awards) — frozen AnalyticsApi surface

```java
AnalyticsApi.value(server, day, uuid, key)      // 0 when unknown; offline uuids fine
AnalyticsApi.top(server, day, key, n)           // List<Entry(uuid,value)> desc, uuid tiebreak; n<=0 = all;
                                                // players with ANY data that day are listed (value 0 rows
                                                // included so order:"min" categories can rank them)
AnalyticsApi.sumAcrossDays(server, uuid, key)
AnalyticsApi.keys(server, day)
AnalyticsApi.onlineOrKnownUuids(server, day)    // awards candidate universe
AnalyticsApi.categories()                       // static category ids, documented order
```

Key namespace (see `AnalyticsKeys`): `kill_total death dmg_dealt dmg_taken mine_total
place_total place_types craft_total smelt_total dist_cm biomes chunks_new playtime_s
depth_min_y breed_total trade_total altar_value shards_banked quests_done mains_done
sides_done personals_done` + dynamic `kill:<entity_id>` / `mine:<block_id>` /
`craft:<item_id>` (craft ids allowlisted from goals/quests/awards configs +
`analytics.json craftAllowlistExtras`). `dmg_*` are ×10 fixed-point;
`depth_min_y` stores `4096 - blockY` (max = deepest) — `awards.json deep_diver` should use
`order: "max"` as planned.

## For B4 (skills) / B9 (buffs) — natural check

- Preferred: consume `EclipseSignals.onNaturalBlockMined` (only ever fired for natural
  breaks by tracked players).
- Loot-level checks (T2/T6 re-rolls, B9 `BlockDropsEvent` ore doubling):
  `PlacedBlockTracker.isPlaced(level, pos)` — O(1), safe on any loaded chunk. Bits are
  cleared on break, so drop-time queries run BEFORE analytics' LOW break handler clears the
  bit only if you subscribe at HIGHER priority than LOW on the same event; `BlockDropsEvent`
  fires after `BreakEvent` entirely — for that path query `isPlaced` from your own
  `BreakEvent` HIGH/NORMAL listener or rely on the signal instead.

## For B2 (goals)

- `travel_distance` trigger: poll `AnalyticsApi.value(server, day, uuid, "dist_cm")`
  deltas (20t cadence is fine — reads are map lookups).
- `explore_chunks`/`visit_biomes` triggers: consume the `chunkExplored`/`biomeVisited`
  signals ("new chunk" = first visit that day, memory-capped; "new biome" = first lifetime
  visit).

## Config

- `config/eclipse/analytics.json` (created with defaults on first run; hot-reload via the
  registered `ReloadHooks` "analytics" hook): `samplerEnabled`, `distanceSampleCapCm`
  (default 10 000 = 100 m/sample), `chunkSetCap` (65 536), `maxDynamicKeysPerPlayerPerDay`
  (2 048 — overflow drops per-id detail, never `*_total`), `craftAllowlistExtras`,
  `retentionDays` (20 — never prunes a 14-day event).
- No `run/config/eclipse/analytics.json` was authored: the defaults ARE the event values
  and B3's content package does not list analytics.json. Add one only if the event ops
  team wants different caps.

## Perm-3 smoke commands (`analytics/AnalyticsCommands`, self-registered)

`/eclipse-analytics top <day> <key> [n]` · `dump <day> <player>` · `categories` · `reload`
(RCON smoke per §3.6: `/eclipse-analytics top 1 mine_total`).
