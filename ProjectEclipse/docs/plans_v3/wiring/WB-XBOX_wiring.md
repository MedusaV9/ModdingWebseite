# WB-XBOX — Xbox event seam fixes

## Integration

- Merge `docs/plans_v3/langdrop/WB-XBOX.json` into both shipped language files.
- No event-bus or mod-constructor wiring is required. `XboxMusicHook` is a game-bus
  `@EventBusSubscriber` and silently no-ops when the optional music API is absent.
- The music wave's optional server seam is discovered once by reflection at
  `dev.projecteclipse.eclipse.music.MusicCues`. Supported signatures are
  `play(String, ServerPlayer)` plus either `stop(String, ServerPlayer)` or
  `stop(ServerPlayer)`. Cue id: `xbox_nostalgia`.

## State/config additions

- `eclipse_xbox_event` SavedData now persists the current lockout mode and consumed
  manifest chest `(worldId, BlockPos)` pairs. Both are instance-scoped; consumed chests
  clear at `beginInstance`, while an in-progress event retains them across restart.
- `config/eclipse/xboxevent.json` accepts `"lockoutOnDeath": false`. Missing values remain
  `false`; a new instance starts in `voluntary` mode when false and `both` mode when true.
  `/dev xboxevent lockout mode voluntary|death|both` overrides the current instance only.
- `beginInstance` clears `/dev xboxevent reward set` overrides. The plan defines that
  command as current-instance-only; durable reward defaults remain the config's `reward`.

## Restart/idle-timeout verification

No new rescue listener was needed. `XboxEventService.resumeOnBoot` closes an expired
persisted `OPEN`/`ANNOUNCED` event, and the existing `PlayerLoggedInEvent` path detects any
player still saved in a tutorial dimension while the matching event is not `OPEN`, then
returns them to their persisted anchor (or overworld spawn fallback).
