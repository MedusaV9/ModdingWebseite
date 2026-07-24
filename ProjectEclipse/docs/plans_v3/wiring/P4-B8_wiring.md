# P4-B8 wiring — revive rework + glitch path

## No hub registration required

- `EclipseItems` already registers `heart_fragment`, `heart_extractor`, `glitch_shard`,
  `revive_sigil`, and `vitae_shard`; B8 therefore adds no registrar and needs no
  `EclipseMod` call.
- `GlitchConfig`, `GlitchSpawnService`, and `GlitchDrops` self-register through
  `@EventBusSubscriber`. `GlitchConfig` installs its `ReloadHooks` callback at class load.
- The existing altar sigil flow remains authoritative:
  `ReviveSigilItem` → `AltarBlockEntity.handleSigilConfirm` → `ReviveRitual` →
  `BanService.unban`, which restores exactly one max heart via `LivesApi.set(player, 1)`.

## P6 entity contract

P6 must register these exact entity type ids:

- `eclipse:glitched_husk`
- `eclipse:glitched_hound`
- `eclipse:glitched_tick`

Both the spawner and entity tag refer to ids only. Tag entries are `required: false`, and
registry lookups silently skip absent types, so B8 boots clean before P6 lands.

## Runtime configuration

`config/eclipse/glitch.json` is created on first boot and hot-reloads through
`/eclipse reload`. It controls day/night gates, cadence, attempts/chance, alive cap,
player-distance bounds, fresh-ring window, drop chance/count/Looting bonus, and entity ids.

The effective fresh-ring window is:

`min(glitch.json freshRingWindowTicks, worldgen_tuning.json glitch.freshTicks)`

because `NewRingRegistry.sampleFreshPositions` deliberately never returns a row already
stale according to worldgen.

Optional day gating for `eclipse:vitae_shard_glitch` belongs in the existing
`config/eclipse/recipegate.json` `locks.recipes` list. B8 does not modify the shared recipe
gate implementation or authored event config.

## Crafting-grid constraint

A vanilla shaped crafting grid has nine slots, so the requested total of 8 glitch shards +
2 diamond blocks + 1 totem (11 inputs) cannot be represented by one shaped recipe.
`vitae_shard_glitch.json` uses the valid maximum-cost 3×3 layout: 6 glitch shards +
2 diamond blocks + 1 totem. An exact 11-item cost would require a separately registered
multi-step intermediate item/recipe or a custom crafting station.
