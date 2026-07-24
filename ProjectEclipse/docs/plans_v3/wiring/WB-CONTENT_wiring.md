# WB-CONTENT wiring — P4-B3 content, balance, advancements

## Source of truth and validation

This worker intentionally authors the Java default builders, not `run/config/eclipse/*.json`.
Each loader writes these defaults only when its runtime file is absent; an existing event-server
config is never overwritten. Validate a fresh generated config after one server boot:

```bash
python3 scripts/p4_balance_check.py --strict
```

Use `--config-dir <game-dir>/config/eclipse` when the game directory is not the repository's
`run/`. Without `--strict`, the script validates advancement/lang JSON and Java default table
shape when generated runtime config is absent.

## Advancement behavior

All 18 event advancements set `hidden: true` and `announce_to_chat: false`. Vanilla-detectable
milestones use only vanilla criteria. Skill XP is not a datapack reward function: earning any
`eclipse:` advancement reaches `skills/AdvancementXpBridge`, which resolves the advancement's
`event/`-stripped id through `skills.json` `xp.advancements`.

The three `skill_10|25|40` advancements use `minecraft:impossible` deliberately and are already
granted by `AdvancementXpBridge.onSkillLevelReached`.

## Required engine seams for impossible event criteria

Vanilla criteria cannot observe altar-offering acceptance, ritual completion, the real-time event
day, or team-wide survival. The corresponding JSONs therefore use `minecraft:impossible`. Apply
these small calls in the owning engine files; do not replace them with proxy inventory criteria.

1. `offering/OfferingService.accept`, immediately before its successful `return true`:

   ```java
   AdvancementXpBridge.grantAdvancement(player, "eclipse:event/first_offering");
   ```

2. `ritual/ReviveRitual.succeed`, after the target is unbanned/removed from the banned set and
   before `cleanup()`:

   ```java
   ServerPlayer ritualist = server.getPlayerList().getPlayer(this.confirmerId);
   if (ritualist != null) {
       AdvancementXpBridge.grantAdvancement(ritualist, "eclipse:event/first_revive");
   }
   QuestApi.completeTeamBeat(server, "player_revived");
   ```

3. Add one self-registering event-advancement listener to the day-rollover signal. On POST where
   `endedDay == 3 && newDay == 4`, grant `eclipse:event/survive_day_3` to each online, living,
   non-banned player. On PRE for every ended day, build the participant cohort from analytics
   `playtime_s > 0`; if the cohort is non-empty and every member has `death == 0`, grant
   `eclipse:event/team_survives_day` to each online cohort member. Use `AnalyticsKeys.DEATH` and
   `AnalyticsKeys.PLAYTIME_S`, not string variants, and retain the normal ServerStopped static
   reset discipline.

4. `ritual/FinaleRitual.beginVictory`, after its duplicate-run guard succeeds:

   ```java
   QuestApi.completeTeamBeat(server, "crossing_survived");
   ```

These calls also activate the authored day-11 `player_revived` and day-14 `crossing_survived`
main-goal beats. Until items 1–4 are wired, those two goals and four non-skill impossible
advancements require an admin tick and must not be represented as automatically functional.

## Existing test pin requiring an orchestrator update

`gametest/skills/SkillMathGameTests.treeShapeMatchesPlanTable` still pins the old content shape.
Update only its content assertions from 21 nodes / 51 points to 25 nodes / 66 points. No skill
engine behavior changes are required: all four added capstones reuse existing implemented effect
types and each adds only 2–4%.

## Balance notes

- Day 1 team timber rises to 96 logs; later mains replace generic manual placeholders with actual
  craft, mine, collect, explore, location, or persisted beat triggers.
- The 28-entry personal pool uses day windows and weighted draws; harder/boss-adjacent entries add
  one shard while all entries grant skill XP.
- Milestones are multi-item team sinks at roughly 2–3× the old costs.
- Diamond and netherite gear unlock on days 5 and 10. Gold remains available because P4 §2.7 does
  not define a gold lock and it is weaker than iron; anvil/enchanting unlock on days 2/3.
- The skill curve remains `C(12)=2639`; the checker models one active hour at roughly 650 XP
  including one representative personal quest.
