# P5-W56 wiring — stage backups, display placer, spawn tools, replay

## Required integrator line

Add this import/call in the `EclipseMod` constructor with the other item registrars:

```java
dev.projecteclipse.eclipse.devtools.display.DevToolItems.register(modEventBus);
```

This is the only `EclipseMod` line. `DisplayPayloads` self-registers on
`RegisterPayloadHandlersEvent` (do **not** also add it to `EclipsePayloads`, or startup will
fail on duplicate payload registration). `DisplayAnimator`, `StageBackups`, and all command
classes are game-bus `@EventBusSubscriber`s, so their ticks/listeners/commands need no hub
registration.

## Resource merges

- Merge `docs/plans_v3/langdrop/P5-W56.json` into both shipped language files.
- Add `eclipse:display_wand` to `#eclipse:emi_hidden`. For 1.21.1 the item-tag resource is
  `data/eclipse/tags/item/emi_hidden.json`.

## Behavioral integration notes

- `StageBackups` reads optional `general.json.stageBackupRetention`; it defaults to 10 until
  P1 adds the key to `EclipseConfig.General`.
- `SpawnProtectionRules.isInProtectionZone` now uses the broad `protection.json` gameplay
  zone (default r=96). `SanctumProtection.isProtected` remains the separate r=18-default
  build-protection cylinder. `/dev spawn radius` is the explicit SavedData override for
  both; `/dev spawn set` similarly overrides their shared center.
- Axiom integration is intentionally absent: its 1.21.1 releases are Fabric-only/ARR.
  Displays are vanilla `minecraft:block_display` entities and the supported editor on this
  stack is the wand plus `/dev display`.
