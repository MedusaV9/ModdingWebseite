# WB-SIDEBAR wiring handoff

## Already wired in this worker

- `SidebarSyncService` self-registers, sends a baseline on login, listens to the shared
  gameplay/day/level signals, and flushes one trailing per-player batch after 10 ticks.
- `SidebarPanel` remains on the existing Eclipse GUI-layer registration. It reads only the
  payload-backed `ClientStateCache.sidebar*` fields and the companion quest/buff caches.
- TAB expansion uses the configured vanilla player-list key. Both the existing
  `TabListHider` and the panel's own layer guard suppress `VanillaGuiLayers.TAB_LIST`.
- `StartAssignmentService` and `/eclipse-start assign|show` self-register. The sole permitted
  `StartEventCutscene` call-site edit now passes the persisted assignment map to
  `IntroSequence.start`.

## Required integration seams

The source packages own their mutation choke points. Add these one-line calls after a
successful mutation so non-gameplay/admin paths also refresh the aggregate:

| Owner | Mutation choke point | Call |
|---|---|---|
| P4-B4 skills | `SkillService.addXp` after applied XP and `SkillsApi.setTotalXp` | `SidebarSyncService.markDirty(player)` |
| P4-B2 goals | `QuestEngine.markDirty(uuid)` / `markAllDirty()` | matching `SidebarSyncService.markDirty(uuid)` / `markAllDirty(server)` |
| P4-B9 buffs | successful start, stop, and expiry prune in `TimedBuffService` | `SidebarSyncService.markAllDirty(server)` |
| Economy | `ShardEconomy.setShards` after the attachment write | `SidebarSyncService.markDirty(player)` |
| Altar/admin | any direct `EclipseWorldState.setAltarLevel` path that does not fire `altarDeposit` | `SidebarSyncService.markAllDirty(server)` |

The gameplay signal listeners already cover ordinary mining, kill, craft, smelt, explore,
biome, altar-deposit, quest-completion, breed, trade, death, advancement, skill-level, and
day-rollover paths. The calls above close direct mutation and progress-without-completion
paths without adding a periodic broadcast.

## Start teleport follow-up

The hard ownership rule allowed changing only the `IntroSequence.start` call line in
`StartEventCutscene`. Its earlier t=140 transport loop still chooses discs from Limbo list
order. When that file is next owned by the intro worker, compute
`StartAssignmentService.assign(server, inLimbo)` before the loop and use each returned
`BlockPos` for transport as well as the intro framing map. Until then, assignment persistence
and intro framing are deterministic, but physical landing order can differ from the saved map.

## Lang merge

Merge `docs/plans_v3/langdrop/WB-SIDEBAR.json` into both locale assets. No locale asset is
edited by this worker.
