# P4-B9 wiring notes (integrator)

Worker **P4-B9** owns timed buffs, voice global mute, and logout ghosts. Apply these hub
changes after the wave merges — **do not** expect B9 to edit foreign files.

## EclipseMod.java (required)

Register the logout ghost entity deferred register in the mod constructor (same pattern as
`AmbientEntities`):

```java
dev.projecteclipse.eclipse.ghosts.GhostEntities.register(modEventBus);
```

Suggested placement: immediately after `AmbientEntities.register(modEventBus);`.

Until this line lands, logout ghost spawn soft-fails with one log line; buffs and voice work
without it.

## Already self-registering (no EclipseMod change)

- `TimedBuffService` — `@EventBusSubscriber`, sets `TimedBuffApi.Holder` on `ServerStartedEvent`
- `BuffConfig` — reload hook via `ReloadHooks.register("buffs", …)` on server start
- `BuffCommands` — `/eclipse-buffs` via `RegisterCommandsEvent`
- `BuffEffects` — NeoForge bus subscribers for ore/shard drops, magnet, hunger factor
- `VoiceCommands` — `/eclipse-voice` via `RegisterCommandsEvent`
- `LogoutGhostService` — login/logout/stop handlers

## EclipseVoicePlugin.java (unchanged)

Global mute requires **no** plugin edit — `EclipseVoicePlugin` already calls
`VoiceMuteApi.isMuted(server, sender)`; B9 extended that method with the global leg.

## P6-W12 ghost renderer contract

| Field | Value |
|---|---|
| Entity type id | `eclipse:logout_ghost` |
| Entity class | `dev.projecteclipse.eclipse.ghosts.LogoutGhostEntity` |
| Registry holder | `GhostEntities.LOGOUT_GHOST` |
| Synched data | `LogoutGhostEntity.DATA_OWNER_UUID` (`Optional<UUID>`) |
| Synched data | `LogoutGhostEntity.DATA_REVEAL_TICKS` (`int`, glitch shader driver) |
| Server-only NBT | `OwnerName` string — **never** synched to clients |
| Hurt hook | call `LogoutGhostService.onGhostHurt(ghost, attacker)` from `hurt()` |
| Validity poll | call `LogoutGhostService.isValid(ghost)` every 100t (entity already does) |

Reveal payload: `S2CGhostRevealPayload(ghostEntityId, ownerName, ticks)` — the **only**
player name on the wire.

## P5 / P3 consumers

- **P5-W4 / Xbox rewards**: `TimedBuffApi.Holder.get().start(server, "double_skill_xp", minutes)`
- **P5-W9**: buff ids — `double_skill_xp`, `double_ore_drops`, `half_hunger`,
  `double_shard_finds`, `supply_rush`, `xp_magnet`, `glitch_surge`
- **P3**: renders `S2CBuffStatePayload` + buff bossbar theme `goal` (already sent)
- **P4-B4 skills**: calls `TimedBuffApi.multiplier(server, "skill_xp")` via Holder
- **P4-B8 glitch**: `TimedBuffApi.multiplier(server, "glitch_spawn")`
- **P4-C1 sidebar**: `TimedBuffApi.active(server)` for buff id list

## Optional: protection.json ghosts section (B7 content)

B9 reads when present:

```json
"ghosts": {
  "enabled": true,
  "revealTicks": 60,
  "revealCooldownSeconds": 5,
  "dimensions": ["minecraft:overworld", "minecraft:the_nether"]
}
```

Defaults match the above if the section is absent.

## buffs.json

Created on first run at `config/eclipse/buffs.json` with seven definitions (B3 may commit
authored values under `run/config/eclipse/buffs.json`).
