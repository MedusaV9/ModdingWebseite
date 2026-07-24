# W4-HEARTS wiring notes — purple hearts system (IDEA-13 R1 + R2 + R4)

**Zero hub edits.** No `EclipseMod`, `EclipsePayloads`, `EclipseGuiLayers`, `registry/**`,
lang JSON, `sounds.json` or `build.gradle` changes. The two new classes self-register
(`@EventBusSubscriber` / self-registrar payload group, the `GhostHeartsLayer` /
`DeathFlowPayloads` conventions). Langdrop: `docs/plans_v3/langdrop/W4-HEARTS.json`
(2 keys × en/de — the settings row below).

## What landed

### R1 — `hearts/client/PurpleHeartsLayer.java` (NEW)
- Cancels `VanillaGuiLayers.PLAYER_HEALTH` (`RenderGuiLayerEvent.Pre`,
  `receiveCanceled = true` so a ghost-row/letterbox cancel still clears its own frame
  flag) and re-adds vanilla's exact `leftHeight` increment; renders the row from the new
  `textures/gui/hearts/` purple set with full vanilla parity: absorption (violet-white
  sprites; wither override like vanilla), regen-wave −2px lift, damage/heal blink
  (container highlight + white-flash hearts up to the mirrored `displayHealth`), ≤4 hp
  jitter (suppressed under `reducedFx`), poison/wither/frozen tint pass. Hardcore
  variants deliberately ignored (custom lives).
- Registered `registerBelow(HeartBurstOverlay.LAYER_ID, …)` at mod-bus priority **LOW**
  (deterministically after `EclipseGuiLayers`' default-priority registration) — shatters
  always draw on top.
- Defers to `GhostHeartsLayer.isOwningHealthSlot()` (new public seam) — exactly one layer
  ever cancels/compensates.
- Kill-switch `purpleHearts` read **reflectively with default ON** (the
  `UiSounds.uiSoundVolume` MethodHandle precedent) until the config ask below merges.

### `hearts/client/HeartRowGeometry.java` (NEW)
Vanilla-exact shared row math (verified against the NeoForge-patched
`Gui.renderHealthLevel`/`renderHearts` sources): rows/rowStep/leftHeight increment, row
origin reconstruction from the post-layer `Gui.leftHeight`, descending jitter replay
(seed `guiTicks * 312871`), regen slot. Packed-long positions — zero per-frame allocs.
Used by `PurpleHeartsLayer`, `HeartBurstOverlay` and `GhostHeartsLayer` (constants +
one-row compensation), so bursts land pixel-exact on the drawn hearts at any gui scale.

### R2 — `hearts/client/HeartBurstOverlay.java` (queue rework)
- The static `heartIndex`/`animationTick` pair became a fixed-capacity FIFO queue
  (`HeartsService.MAX_HEARTS + 1` = 8 entries), 8-tick stagger
  (`GhostHeartsLayer.BURST_STAGGER_TICKS` precedent), one glass-crack cue per burst
  start. Multiple triggers now play sequentially over their exact row slots.
- Geometry delegated to `HeartRowGeometry` (incl. the purple layer's `displayHealth`
  mirror and the reducedFx jitter suppression, so shatter and row never desync).
- Debris (sheet frames + shards) tinted toward `EclipseUiTheme.ACCENT` (#B98CFF) while
  the purple layer owns the row.
- Senders completed: `HeartExtractorItem` now sends **two** payloads (indices
  `heartsAfter`, `heartsAfter + 1`); `AltarBlockEntity.handleHeartSacrifice` sends one
  `S2CHeartBurstPayload(LivesApi.get(player))` + an `S2CQuasarPayload(HEART_BURST)`
  world echo at the altar (one statement, 3 lines — see coordination note below).
- Respawn replay (`LifecycleEvents.onPlayerRespawn`): verified and upgraded — now sends
  one burst per heart actually missing since the death (`hearts … previousHearts-1`),
  which the queue plays one-by-one ("wenn man respawnt sollen die verlorenen Herzen über
  der Hotbar zerplatzen"). A normal death still sends exactly one payload with the same
  index as before; the world-echo quasar is unchanged.

### R4 — ritual vigil
- `network/hearts/HeartsPayloads.java` (NEW self-registrar, version group `w4hearts1`,
  id `eclipse:hearts/ritual_vigil`): `S2CRitualVigilPayload(float progress, boolean
  active)` — no names, no positions (anonymity law).
- `ritual/ReviveRitual.tick()` sends it every 20 t to the **online** ghost target;
  `fail()` sends `active=false` (covers confirmer-death, stray, logout-of-confirmer,
  server-stop and the aborted-success path, which all route through `fail`). Success
  needs no payload — unban → `S2CRevivedPayload` → ghost-row burst resets the vigil.
- `client/death/GhostHeartsLayer.java`: violet fill (ACCENT family) rises left-to-right
  across the 5 cracked hearts (partial-sprite blit + 1px waterline), the crack hairlines
  knit shut per-heart as its fill completes; on `active=false` the fill drains and the
  cracks return over ~20 ticks. Fill eases toward the last synced progress
  (0.004/tick rise, 0.05/tick revert); reset on level unload / mode exit.

### Art — `scripts/item_art/gen_purple_hearts.py` (NEW, run; deterministic)
Fills the `asset_audit.md` "manifest vs code path split" gap: the canonical
`textures/gui/hearts/` set now exists. `heart_full.png` is a byte-copy of the committed
purple 9×9 (`textures/gui/heart_full.png` — handbook art unchanged and untouched);
derived: `heart_half`, `heart_full_blinking`, `heart_half_blinking` (whitened toward
TEXT like vanilla's blink family), `heart_absorbing_full/half` (violet-white ACCENT+TEXT
shift); painted from the vanilla 9×9 container mask: `heart_container`,
`heart_container_blinking` (VEIL outline / HAIRLINE well; blink outline TEXT).

## Wiring asks (integrator)

### 1. `purpleHearts` client-config key (shared `EclipseClientConfig` — exact diff)

After the `CUSTOM_LOADING_SCREENS` definition:

```java
    public static final ModConfigSpec.BooleanValue PURPLE_HEARTS = BUILDER
            .comment("Render the player health row as Eclipse purple hearts",
                    "(false = vanilla red hearts killswitch).")
            .define("purpleHearts", true);
```

Next to the other §7.1 getters (name is load-bearing — `PurpleHeartsLayer` binds
`purpleHearts()Z` via `MethodHandles.publicLookup().findStatic`, exactly like
`UiSounds` binds `uiSoundVolume()`; until this merges the layer treats the toggle as ON):

```java
    /** W4-HEARTS R1: purple player-hearts renderer (read reflectively by PurpleHeartsLayer). */
    public static boolean purpleHearts() {
        return get(PURPLE_HEARTS, true);
    }
```

### 2. Settings row (shared `client/menu/SettingsPanel.buildRows`, display section)

After the `death_screen` toggle:

```java
        y = toggle(y, "purple_hearts", EclipseClientConfig::purpleHearts,
                EclipseClientConfig.PURPLE_HEARTS);
```

### 3. Langdrop merge
`docs/plans_v3/langdrop/W4-HEARTS.json` →
`gui.eclipse.settings.option.purple_hearts` (+ `.tip`), en + de.

## Shared-payload / shared-file notes

- `S2CHeartBurstPayload` stays registered in `EclipsePayloads` (version group "2") —
  **untouched**; record/codec/id unchanged. Only the NEW vigil payload lives in
  `network/hearts/HeartsPayloads` (`w4hearts1`). Do NOT re-register either elsewhere
  (duplicate-id rule).
- **`AltarBlockEntity` coordination (W-ISLAND):** my only edit is one 3-line send
  statement in `handleHeartSacrifice`, inserted directly after the
  `WitnessedLossService.onHeartLost(player)` line (fully-qualified
  `S2CHeartBurstPayload` — the import block is untouched to keep the merge trivial).
  The offering path (`handleOffering`) is untouched.
- `LifecycleEvents.onPlayerRespawn`: single-burst send became the per-missing-heart loop
  (see R2). No other change in that file.

## Optional follow-ups (deliberately NOT done — outside ownership)

- `EclipseDeathScreen.renderHeartRow`/`renderGhostHearts` still draw vanilla
  `hud/heart/full`; the ideas doc's "bonus consistency" swap to the purple sprite under
  the toggle is a 2-line change for the death-screen owner.
- `client/handbook` tabs keep reading `textures/gui/heart_full.png` (same art; the
  handbook owner may repoint to `gui/hearts/heart_full.png` and delete the old file).

## Risks

- **`PLAYER_HEALTH` cancellation**: third-party mods hooking the vanilla health layer see
  it cancelled while `purpleHearts` is on — the exact exposure `GhostHeartsLayer` already
  accepts; the toggle (default ON) is the zero-risk escape hatch.
- **Blink mirror divergence**: vanilla's `displayHealth`/`healthBlinkTime` are private, so
  the layer keeps a faithful mirror. While the purple layer is OFF, `HeartBurstOverlay`
  approximates `displayHealth` with live health for row-count purposes (sub-second window
  after a max-health drop, one row-step of error at worst) — same class of approximation
  the pre-rework overlay had, now vanilla-formula exact otherwise.
- **Event-order edge**: two other subscribers also cancel `PLAYER_HEALTH`
  (`GhostHeartsLayer`, `LetterboxLayer` HUD suppression). `PurpleHeartsLayer` handles
  every arrival order via `receiveCanceled + isCanceled()` and the
  `isOwningHealthSlot()` check; compensation can never double.
- **Vigil catch-up pacing**: a ghost logging in mid-ritual eases into the current
  progress at 0.004/tick (~12 s worst case from zero) rather than snapping — intended
  drama, flagged here in case playtest wants a faster rate (single constant).
