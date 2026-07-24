# goals.json / quests.json v5 migration (D5 — phase-aware + harder)

D5 rewrote the **default** `config/eclipse/goals.json` and `config/eclipse/quests.json`.
Fresh worlds pick the new defaults up automatically. **Live saves keep their existing
files** — `GoalConfig` never overwrites a present config — so event servers that want the
v5 ladder must either delete the two files (they regenerate on next boot / `/eclipse
reload`) or apply the changes below by hand / via `/eclipse goals edit`.

## Schema addition: `requiresUnlock`

Every goal/quest entry (mains, sides, personals) accepts an optional string field:

```json
{ "id": "d06_blaze_slayer", "kind": "side",
  "trigger": { "type": "kill_entity", "target": "minecraft:blaze", "count": 8 },
  "reward": { "skillXp": 200 }, "text": { "en": "...", "de": "..." },
  "requiresUnlock": "nether" }
```

- The value is an `UnlockState` key (day-plan `unlocks[]` entry, altar milestone reward,
  or the derived `herald_slain` boss key). Empty/absent = ungated.
- **Personals**: a gated quest never rolls while its key is locked (checked at draw time,
  on top of `minDay`/`maxDay`). Nether quests cannot appear before the nether opens.
- **Sides**: a gated side does not materialize into the day at all while locked, and
  materializes the moment the key is granted mid-day (the resolved-day cache keys on the
  unlock set).
- **Mains are never filtered** — the 3-main day arc is hand-authored and a stalled unlock
  must not strand a day. `requiresUnlock` on a main is accepted but ignored at
  materialization (documented for editor symmetry).

Keys used by the v5 defaults: `nether`, `create`, `brewing`, `enchanting`, `end`.

## Retune summary (old → new, defaults only)

Quantities went up ~2.5–4× per day tier ("day-3 tasks must feel like day 3"), XP scaled
with them, and every personal quest now pays 1–2 shards. Highlights:

| Day | Change |
|---|---|
| 1 | timber 96→128 logs; scout 24→32 chunks; descend Y0→Y-16 |
| 2 | gold rush 24→32 ingots; prospector 12→24 iron ore; mason 64→128 blocks |
| 3 | NEW mains: forge (12× `#eclipse:tier_iron_gear`), kinetics (`create_kinetics_built` beat), survey 96 chunks |
| 4 | NEW main: feast (12× `#eclipse:hearty_meals`); husbandry 12→24; NEW iron wall (4× `#eclipse:tier_iron_armor`) |
| 5 | skyward 160→240 chunks; iron stock 96→128; tinker 16→24 pistons |
| 6 | fortress/blaze mains per player; blaze slayer side gated `nether` |
| 7 | slay XP 600 + 2 shards; altar_3 demoted to side |
| 8 | hoard 4→6 ender chests; pearls 24→32; endermen 3→6 |
| 9 | alchemy 8→16 potions; NEW main altar_5; pool 32→48 shards |
| 10 | debris 12→16; bastion 256→384 blocks; wither side gated `nether` |
| 11 | end kit 12→16 eyes; shepherd 6→12 breeds |
| 12 | breach 16→20 eyes; NEW main war chest (`shard_pool_64`); purge demoted to side |
| 13 | dragon XP 700 + 3 shards; hostiles 40 kills |
| 14 | ferryman XP 800 + 4 shards; last stand 40 kills |

Personals: quantities roughly doubled-to-tripled (e.g. explorer 40→64 chunks, hunter
15→30 kills), day windows tightened, and gates added: `p_blaze_hunter` +
`p_fortress_raider` → `nether`, `p_alchemist` → `brewing`, `p_enchanter` → `enchanting`,
`p_end_touch` → `end`.

## New item tags (data pack, ship with the mod)

- `#eclipse:tier_iron_gear` — full iron armor + tool set (9 vanilla items).
- `#eclipse:hearty_meals` — vanilla stews/soups + Farmer's Delight meals (FD entries are
  `required: false`, so the tag loads without the mod).

No world-state migration is needed: `QuestState` progress is keyed by goal id, and ids
that vanished from the config are simply skipped on load.
