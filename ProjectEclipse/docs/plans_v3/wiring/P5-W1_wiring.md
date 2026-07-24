# P5-W1 wiring notes

`DevRoot` and related classes use `@EventBusSubscriber(modid = EclipseMod.MOD_ID)` — **no
`EclipseMod.java` edits required** for command registration or server-start registry freeze.

## P5-W2 (Dev Handbook GUI)

When `DevHandbookPayloads` lands, register the handbook opener from server/common setup:

```java
DevHandbookBridge.setOpener((player, entries) -> {
    // send S2CDevHandbookPayload with entries + DevReload.configReferences()
});
```

## Optional: bootstrap generated docs at build time

W11 may run `DevDocsExporter.generate(null, false)` during integration to refresh
`docs/DEV_COMMANDS.md` without a live server (description columns show lang keys until merged).

`DevReload` step 1 calls `EclipseConfig.reload()`, which already invokes P4's
`ReloadHooks.runAll()` at the tail (P4-A1). Step 3 is reported as informational feedback only
(no second hook pass).
