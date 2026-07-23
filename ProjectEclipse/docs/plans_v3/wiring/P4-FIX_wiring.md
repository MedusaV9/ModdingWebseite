# P4-FIX wiring notes

## Runtime seams

- `S2CDayStatePayload.currentFor(ServerPlayer, ...)` is the receiver-localized day-state
  factory. `DayScheduler` uses it for day changes; `LangService` re-sends it on login and
  locale changes. Day announcements and timeline entries now pick `DayPlan` literals per
  receiver. No forbidden hub/ritual/devtool file is part of this fix bundle.
- `EclipseConfig.DayPlan` retains the legacy English `goals()`, `title()` and `subtitle()`
  views while storing `Localized` values in `localizedGoals()`, `localizedTitle()` and
  `localizedSubtitle()`. Legacy string JSON and `{en,de}` JSON both round-trip, including
  the `GoalConfig` fallback for days without authored quest goals.
- `SkillService` reads `GoalSpec.reward().skillXp()` from `questCompleted` and adds the
  configured per-kind flat bonus in the same XP grant.
- `QuestEngine.ensurePlayer` backfills `skill_level` from `SkillsApi.getLevel` after
  assignment/login.
- `QuestCommands` registers the legacy `/eclipse goals tick` executor at `LOWEST` priority,
  after the old tree, so validation, feedback and completion all use
  `QuestEngine.currentMains`.
- `QuestState` persists the open Minecraft-night id, dusk eligibility and per-player damage
  flags. `QuestDetectors` resumes the same window after restart, ignores shutdown-generated
  logout events, and still forfeits a player who leaves during a running server.
- `AnalyticsService` remains the sole NeoForge owner for breed/trade events and fires the new
  `EclipseSignals.fireBreed` / `fireTrade` lanes. Analytics, skills and breed goals consume
  those lanes.
- `VillagerRestrictions` resets its per-server gamerule guard on `ServerStoppedEvent`.
  Its `LOWEST` server-start listener registers after `ProtectionConfig`, so the reload hook
  applies the refreshed `doTraderSpawning` value in both enable and disable directions.

## Data and tests

- `GameTestSupport.mockServerPlayer` uses NeoForge's real connected mock-server-player
  helper; the harness smoke test removes only its own listener. The retained quest-test
  rearm hook no longer clears any sibling service listeners.
- `scripts/gametest/gen_empty_nbt.py` deterministically generates
  `data/eclipse/structure/gametest/empty.nbt`.
- Diamond/netherite gear tags contain all vanilla armor, sword and tool ids; the netherite
  tag also contains `netherite_upgrade_smithing_template`.
- No new localization keys were needed; `langdrop/P4-FIX.json` intentionally contains empty
  locale maps.

## Owner follow-up

- The canonical day-change path and locale/login re-sync are receiver-localized. Legacy
  refresh sends remain in hard-rule-excluded owners (`network/EclipsePayloads`,
  `admin/EclipseCommands`, `ritual/AltarBlockEntity`, and devtools). Their owners should
  replace global `new S2CDayStatePayload(..., plan.goals())` sends with per-player
  `S2CDayStatePayload.currentFor(...)` calls.
