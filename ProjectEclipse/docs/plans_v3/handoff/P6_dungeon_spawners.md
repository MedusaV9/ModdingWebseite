# P6 dungeon spawner sheet — handoff for the DungeonSpawners integrator

**From:** P6-W56. **Consumer:** whoever edits `config/eclipse/dungeons.json` defaults (or
`worldgen/structure/dungeon/DungeonSpawners.java` — P1-owned; P6 never edits it).

## How the seam works (already live — no code needed)

`DungeonSpawners` reads `config/eclipse/dungeons.json`: each dungeon id has a `"spawners"`
string array and every placed spawner block picks `array[slotIndex % array.length]`.
Unknown/absent `eclipse:*` ids fall back to vanilla mobs with ONE warning — so this config can
ship **before** all mob families merge. `/eclipse reload` re-targets already-placed spawner
blocks in place (edit json → reload → watch the spawner switch).

## Slot maps (from the builders — order matters for the rotating arrays)

- **`collapsed_vault`** (`CollapsedVaultBuilder`): standalone vault uses slots **0** (main hall,
  x+17) and **1** (treasury approach, x+26). The stronghold gauntlet uses slots **0..2** (one per
  descent room) and slot **3** at the portal-room doorstep — the **rift antechamber trap**.
- **`umbral_warrens`** (`UmbralWarrensBuilder`): slots **0/1** flank the sculk heart; pocket
  rooms use slots **2+index** (even pockets only).
- **`monster_room`** (`UndergroundSites` clusters): slot hashed 0..2 per room.

## Recommended arrays (plan §2.8, translated to the frozen split glitched ids)

```json
{
  "collapsed_vault": {
    "spawners": ["eclipse:eclipse_cultist", "eclipse:glitched_husk", "eclipse:eclipse_cultist", "eclipse:glitched_tick"]
  },
  "umbral_warrens": {
    "spawners": ["eclipse:eclipse_cultist", "eclipse:glitched_hound", "eclipse:eclipse_cultist"]
  },
  "monster_room": {
    "spawners": ["minecraft:zombie", "eclipse:glitched_husk", "minecraft:skeleton"]
  }
}
```

Why these mappings:

- **Collapsed Vault** = plan's "stronghold-edge dungeon": `eclipse_cultist` ×2 (slots 0 and 2),
  `glitched_husk` ×1 (slot 1), and slot 3 — the portal-room antechamber — gets the
  **`glitched_tick` burst trap** (plan: "rift antechamber trap: Kind:TICK burst"; with the split
  ids this is simply `eclipse:glitched_tick`, and ticks self-swarm in threes).
- **Umbral Warrens**: cultists hold the sculk heart (slots 0/2 wrap to cultist), `glitched_hound`
  on slot 1; pockets rotate through all three. No fog mobs underground — they belong to storms.
- **`monster_room`**: stays mostly vanilla (early-game caves) with one `glitched_husk` slot for
  flavor; harmless before the mob merges thanks to the fallback.
- **`rift_warden` appears in NO spawner array** — it is the dungeon **mini-boss** (tier 3),
  placed/summoned by its own encounter, never spawner-farmable.
- **Fog family** (`fog_revenant`/`storm_hound`/`fog_colossus`) is **storm-gated ambient spawning**
  (owned by `entity/spawn/EventSpawnRules`), not dungeon spawners. If a "fog shrine" dungeon
  theme is ever added, use `["eclipse:storm_hound", "eclipse:fog_revenant"]` per plan §2.8.

## Per-spawner tuning values (for a future `retarget(...)` extension)

`DungeonSpawners.retarget` currently only calls `setEntityId(...)`, so all spawners run vanilla
defaults (`MinSpawnDelay` 200, `MaxSpawnDelay` 800, `SpawnCount` 4, `MaxNearbyEntities` 6,
`RequiredPlayerRange` 16, `SpawnRange` 4). Recommended values when someone extends the seam to
write spawner NBT (keyed by mob id, not dungeon):

| mob id | MinSpawnDelay | MaxSpawnDelay | SpawnCount | MaxNearbyEntities | RequiredPlayerRange | rationale |
|---|---|---|---|---|---|---|
| `eclipse:eclipse_cultist` | 300 | 700 | 2 | 3 | 14 | caster mob — few but persistent pressure |
| `eclipse:glitched_husk` | 200 | 800 | 3 | 4 | 16 | vanilla-ish brawler pacing |
| `eclipse:glitched_hound` | 250 | 800 | 2 | 4 | 16 | leaping hunter — 2 at once is plenty |
| `eclipse:glitched_tick` | 100 | 300 | 4 | 8 | 12 | burst trap: fast, many, short range — reward breaking the spawner |
| vanilla fallbacks | (defaults) | | | | | leave untouched |

## Coordination

- Densities: `EventSpawnRules` (ambient gates) and dungeon spawners count the SAME entities for
  vanilla despawn purposes; both spawn NON-persistent mobs, so abandoned dungeons drain naturally.
- Everything above is copy-pasteable into `dungeons.json` today; ids that have not merged log one
  warning and fall back — zero breakage risk.
