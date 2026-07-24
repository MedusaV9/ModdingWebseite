# P4-B7 wiring notes (Restriction suite)

Worker **P4-B7** owns recipe gating, villager restrictions, day-1 containment, and
spawn-protection v2 **extensions**. It does **not** edit foreign hub files.

## Already self-wired (no hub edit required)

| System | Registration |
|--------|----------------|
| `RecipeGate` / `RecipeGateConfig` | `@EventBusSubscriber`, `ReloadHooks`, login + day-rollover POST sync |
| `ContainmentService` | `@EventBusSubscriber` player tick + fall damage |
| `SpawnProtectionRules` | `@EventBusSubscriber` (queries `SanctumProtection.isProtected`) |
| `VillagerRestrictions` | `@EventBusSubscriber` + `VillagerTradesEvent` / `WandererTradesEvent` |
| `ProtectionConfig` | `@EventBusSubscriber`, `ReloadHooks` |

## Optional hub / sibling follow-ups

| Target | Owner | Need |
|--------|-------|------|
| `network/EclipsePayloads.java` | Hub | **Optional:** call `RecipeGate.syncTo(player)` from central login fan-in (B7 already syncs on its own `PlayerLoggedInEvent`). |
| `network/S2CQuasarPayload.java` | A1/P2 | Add `CONTAINMENT_BOUNCE` constant alias for `eclipse:containment_bounce` (B7 uses `ContainmentService.CONTAINMENT_BOUNCE_EMITTER` locally until then). |
| `data/eclipse/tags/item/tier_*_gear.json` | P4-B3 | Tag files referenced by default `recipegate.json`; until merged, diamond/netherite gear locks rely on explicit recipe scan + any ids B3 adds. |
| `worldgen/structure/SanctumProtection.java` | P6 | Plan R14 config radius (`protection.json` `spawn.radius`) is **stored** but zone queries for break/place remain P6's r=18 cylinder until P6 migrates geometry to config. B7 fall-safe band uses `SanctumProtection.RADIUS + edgeBandExtra` around altar from `EclipseWorldState`. |
| P1 | World | Confirm `protection.json` `containment.bounceY` default (`-180`) against disc underside. |
| P3 / P5 EMI | UI | Consume `ClientStateCache.lockedItemIds` / `lockedRecipeIds` (from `S2CRecipeLocksPayload`) or server `RecipeGateApi`. |

## RecipeGateApi surface (EMI / devtools)

```java
RecipeGateApi.isItemLocked(server, stack)      // boolean — craft gate query
RecipeGateApi.lockedItemIds(server)            // List<String> — flattened item ids (tags expanded)
RecipeGateApi.lockedRecipeIds(server)          // List<String> — locked recipe ids (+ results matching locked items)
RecipeGateApi.rebroadcast(server)              // push S2CRecipeLocksPayload to all online players
```

Payload shape (A1): `S2CRecipeLocksPayload(lockedItemIds, lockedRecipeIds)`.

## Manual `/eclipse day set` rebroadcast

`RecipeGate` rebroadcasts on `EclipseSignals.dayRollover POST` only. If day changes
outside that signal (legacy admin path before B1 wires signals on every `setDay`), call
`RecipeGateApi.rebroadcast(server)` from the day scheduler hook when B1 lands.

## Config files created at runtime

- `config/eclipse/recipegate.json` — defaults per plan §2.7 (day 1/5/10 tiers)
- `config/eclipse/protection.json` — spawn toggles, villager flags, containment days/Y

`run/config/eclipse/*.json` authored values: **P4-B3** (content worker).
