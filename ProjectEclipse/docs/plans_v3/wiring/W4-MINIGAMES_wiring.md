# W4-MINIGAMES — command-triggered portal minigame events

## Integration

- Merge `docs/plans_v3/langdrop/W4-MINIGAMES.json` into both shipped language files
  (`assets/eclipse/lang/en_us.json` + `de_de.json`). 71 keys per locale, key sets match.
- No mod-constructor or manual event-bus wiring is required. `MinigameService`,
  `MinigameLeaveCommand` and `DevMinigameCommands` are game-bus `@EventBusSubscriber`
  classes; `MinigameService.Setup` is a MOD-bus subscriber that bootstraps the config at
  common setup. `gametest/minigames/MinigameGameTests` self-registers via
  `@GameTestHolder`.
- Datapack: new dimension type `eclipse:minigame` plus dimensions
  `eclipse:minigame_arena` and `eclipse:minigame_sky` load automatically from
  `data/eclipse/dimension_type/` / `data/eclipse/dimension/` exactly like the xbox
  jsons (void flat generator, `minecraft:the_void` biome, fixed noon, no beds/anchors,
  no raids). Existing worlds gain the two levels on first boot after the update — the
  usual vanilla "experimental settings" datapack-dimension caveat applies, same as xbox.
- `/minigameleave` is intentionally NOT added to the anonymity `CommandBlocker` list —
  the same permission-0 audit exception as `/xboxleave`. Both leave commands are
  registered in the dev handbook via `DevCommandRegistry` static init.
- No new network payloads. The timer is a vanilla `ServerBossEvent` (blue, mirroring the
  xbox purple bar), and the portal open/close visuals reuse the existing
  `S2CFxEventPayload` rift events with `RiftFx.STYLE_PORTAL` (restyled frame:
  crying-obsidian pillars, amethyst bar, sea-lantern corners — distinct from the xbox
  classic-brick frame).
- Course building reuses `worldgen/stage/BudgetedBlockWriter` tickets (owner ids
  `eclipse:minigame_arena_build/clear`, `eclipse:minigame_race_build/clear`); no new
  writer or scheduler was introduced.

## State/config additions

- New SavedData `eclipse_minigame_event` (overworld storage, `EclipseSavedData` helper):
  phase (`IDLE→OPEN→RUNNING→CLOSING`), game id, window end, `openCount` (doubles as the
  course seed so every open varies), arena round end, portal `(dimension, BlockPos)`,
  participants, per-player inventory **tickets** (return anchor, game mode, health/food,
  main+armor+offhand as `ItemStack.OPTIONAL_CODEC` NBT), rewarded-participation set,
  arena kills, race checkpoint progress / lap starts / finisher order / best lap, and
  the built-course seed markers used for idempotent rebuild-on-open.
- Tickets deliberately survive `beginInstance` — a stranded snapshot from a previous
  instance is still restored by the login rescue, never dropped.
- New config `config/eclipse/minigames.json` (written with defaults on first common
  setup, hot-reloadable via the existing `ReloadHooks` seam): `defaultMinutes` 30,
  `roundMinutes` 5, portal search radii 8..24, `participationShards` 2,
  `participationSkillXp` 40, `podiumShards` [8,5,3], `podiumSkillXp` [120,80,50]
  (podium lists are padded/truncated to exactly 3).

## Restart/idle-timeout verification

- `MinigameService.resumeOnBoot` mirrors the xbox resume: an expired persisted
  `OPEN`/`RUNNING`/`CLOSING` event closes immediately on boot (players returned via
  tickets); a still-live event rebuilds the boss bar, re-validates the portal entities
  and re-enqueues the budgeted course build when the seed marker shows the course was
  not committed before the crash.
- Login rescue covers three paths, all funnelling through `exitToTicket`: (1) login
  inside the active minigame dimension → keep playing (kit re-checked); (2) login inside
  a minigame dimension while no matching event is `OPEN`/`RUNNING` → restore ticket and
  return to anchor (overworld spawn fallback); (3) login anywhere else with an
  outstanding ticket → restore the inventory snapshot in place ("rescued" message).
- Deaths inside minigame dimensions are cancelled at `EventPriority.HIGHEST` before the
  lives pipeline can observe them (the xbox protection pattern): arena deaths respawn at
  the arena with brief i-frames and credit the killer; race falls teleport to the last
  checkpoint. `LivesService` and drop handling are never invoked.
