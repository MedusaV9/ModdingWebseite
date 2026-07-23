# WB-LOADING (P3-W11) wiring — loading screens + portal transition + EMI gate

Worker: WB-LOADING. Scope: P3 §3.11 (R10 loading screens) + §3.12 (R11 EMI gate) +
P5 §2.18 (C20 runtime hooks). No hub files, no `build.gradle`, no `XboxPayloads.java`,
no `veilfx/**`, no `registry/**`, no lang assets touched.

## Files landed

| File | Role |
|---|---|
| `client/loading/EclipseLoadingScreen.java` | Quiet-Eclipse loading screen; hidden-delegate close logic; 60/90 s failsafe; black variant under an active portal transition |
| `client/loading/LoadingScreenSwap.java` | `ScreenEvent.Opening` exact-class swap of `ReceivingLevelScreen` + `LevelLoadingScreen`; `customLoadingScreens` killswitch |
| `client/loading/PortalTransitionController.java` | payload-driven glitch → fade-to-black → hold → fade-in choreography (wall-clock, defensive timeouts, 90 s cap) |
| `network/gate/S2CPortalFxPayload.java` | `{phase: ENTER/HOLD/EXIT, styleId: String, holdTicks: VAR_INT}`, id `eclipse:gate/portal_fx` |
| `network/gate/S2CUnlockedKeysPayload.java` | `{keys: List<String>, lockedNamespaces: List<String>}`, id `eclipse:gate/unlocked_keys` |
| `network/gate/GatePayloads.java` | self-registrar (registrar version `"2"`, §7.3); dedicated-server-safe consumer seams for client dispatch |
| `progression/UnlockSync.java` | server sender: login sync + 1 Hz change-poll broadcast of the derived `UnlockState` + locked ModGate namespaces |
| `client/progression/ClientUnlockCache.java` | client cache; frozen API `isNamespaceLocked(String)` / `isKeyUnlocked(String)` (§7.2); triggers EMI re-index on diff |
| `client/emi/EclipseEmiPlugin.java` | `@EmiEntrypoint` EMI plugin (ONLY file with compile-time EMI imports) |
| `client/emi/EmiReindexer.java` | reflection-only `EmiReloadManager.reload()` trigger; log-once + localized stale hint on drift |
| `xboxevent/XboxTransitionBridge.java` | common-setup install of the `XboxPayloads.setPortalTransitionSender` seam (P5-W9 one-liner, verbatim constants) |
| `src/main/resources/data/eclipse/tags/item/emi_hidden.json` | 175 entries: `display_wand`, `grave`, `altar` + the 172 P5-W8 classic ids (all verified against the registries) |
| `docs/plans_v3/langdrop/WB-LOADING.json` | en+de keys: `gui.eclipse.loading.receiving/preparing`, `gui.eclipse.loading.tip.1..8`, `gui.eclipse.emi.stale_hint` |

## Integration asks (ledger)

1. **`build.gradle` (P5-W10, sole owner) — REQUIRED, merge-order sensitive**: minimum
   `compileOnly "dev.emi:emi-neoforge:1.1.18+1.21.1"` (repo/maven:
   `https://maven.terraformersmc.com/releases/`). `client/emi/EclipseEmiPlugin.java` does
   NOT compile until this lands (every other WB-LOADING file compiles without EMI).
   **Status at hand-off**: P5-W10's in-flight `build.gradle` edit in this workspace already
   adds the TerraformersMC repo + `compileOnly "dev.emi:emi-neoforge:1.1.18+1.21.1:api"` +
   `jarJar` of the full artifact — the plugin was compile-verified against BOTH that exact
   `:api` classifier jar and the full runtime jar; no further gradle work is needed as long
   as that edit merges in/before this wave.
   Note: plan §3.12 mentions `1.1.22+1.21.1:api`; the wave brief pins **1.1.18** — the API
   surface used here (`removeEmiStacks`/`removeRecipes` predicates, `EmiStack.getId/
   getItemStack/isEmpty`, `EmiRecipe.getId/getOutputs`, `EmiReloadManager.reload/isLoaded`)
   is identical in 1.1.18–1.1.22, so bumping the pin is a version-string-only change.
2. **Lang ledger**: merge `docs/plans_v3/langdrop/WB-LOADING.json` into
   `assets/eclipse/lang/en_us.json` / `de_de.json` (all keys inside `EclipseLang`'s cached
   `gui.eclipse.` prefix — no code change needed).
3. **P4 (§5.1 unlock recompute)**: `UnlockSync` detects changes by polling the memoized
   `UnlockState.unlockedKeys` snapshot at 1 Hz (tick phase 13 — clear of the ModGate/
   PhaseInventoryLock sweeps). If P4 refactors `UnlockState` to push change notifications,
   call `UnlockSync.broadcastAll(server)` from that hook and delete the poll.
4. **P5-W8/P4 tag extensions**: future dev/admin or policy items go into
   `data/eclipse/tags/item/emi_hidden.json` `values[]` (plain additions; the plugin reads
   the tag, no code change).
5. **P6/P2 portal senders**: any future dimension-hop teleport can reuse the choreography —
   send `GatePayloads.sendPortalFx(player, new S2CPortalFxPayload(ENTER, styleId, holdTicks))`
   right BEFORE the teleport. `HOLD` refreshes an active hold, `EXIT` force-releases
   (normally unnecessary: the controller self-releases on level receipt).
6. **P2 optional assets (§5.2)**: `textures/gui/loading/ring.png` (the sigil is code-drawn
   until then) and an `eclipse:portal_glitch` Veil pipeline. The controller currently
   mirrors into the frozen `TransitionFx` (`rift_glitch`) world-side pipeline and draws
   GUI-space glitch slabs as the Iris-safe fallback; a dedicated pipeline row can be added
   later inside `PortalTransitionController` without touching `veilfx/**`.

## Contract/deviation notes

- **Payload package**: the wave brief places the payloads in `network/gate/` (plan §4's
  table said `network/`); brief wins. Ids are `eclipse:gate/*`, so no collision either way.
- **`S2CPortalFxPayload` fields**: brief specifies `{phase, styleId}`; the frozen
  `XboxPayloads.setPortalTransitionSender` contract requires transmitting
  `{style, holdTicks}`. The record carries the union `{phase, styleId, holdTicks}` —
  `XboxTransitionBridge` transmits `ENTER / TRANSITION_STYLE / TRANSITION_HOLD_TICKS`
  verbatim, honoring both.
- **`setPortalTransitionSender` signature** is `Consumer<ServerPlayer>` (no `entering`
  flag; W9 invokes it before entry AND exit teleports) — the bridge therefore sends `ENTER`
  for every hop, which is correct: each hop is one full glitch→black→arrive choreography.
- **`EclipseLoadingScreen extends ReceivingLevelScreen`** (plan text said "replicate"):
  the private `levelReceived` supplier concern is solved by the hidden-delegate pattern
  (the ORIGINAL screen's untouched `tick()` closes us via its own `minecraft.setScreen`);
  the subclassing is purely so vanilla `instanceof ReceivingLevelScreen` checks keep
  working (`LocalPlayer.aiStep` suppresses the nether-portal confusion overlay while a
  receiving screen is up). Base-class close logic is inert (`() -> false` supplier,
  `super.tick()` never called).
- **EMI entrypoint mechanism VERIFIED**: EMI-NeoForge 1.1.18 discovers plugins by scanning
  every mod's `ModFileScanData` for `@dev.emi.emi.api.EmiEntrypoint` annotations
  (decompiled `dev.emi.emi.platform.neoforge.EmiAgnosNeoForge`). No META-INF service file,
  no assets entry, no registration call — the annotated class is sufficient, and nothing
  loads it when EMI is absent.
- **Anti-clutter (§3.13) line items**: the loading screen is a Screen (F1-exempt by
  definition, no `hideGui` interplay); the transition overlay deliberately renders under
  F1/hideGui — it is teleport COVER, not HUD clutter (a fade that vanishes under F1 would
  expose the raw dimension swap). `reducedFx` removes glitch slabs and sigil/tip motion,
  keeping plain fades and static visuals. Neither surface captures input; nothing queues
  behind cutscenes (transitions must play exactly when the teleport happens).

## Risks

| Risk | Mitigation |
|---|---|
| EMI has no live-hide API; `EmiReloadManager.reload()` is internal (R-1) | reflection isolated in `EmiReindexer`, `isLoaded("emi")` + `isLoaded()` guards, 5 s debounce, log-once + localized stale hint; worst case index refreshes on next reload/relog; ModGate/RecipeGate remain server truth |
| EMI version drift breaking the plugin compile/API | single file (`EclipseEmiPlugin`) holds all EMI imports; predicates + registration wrapped in try/catch so a broken bake never crashes the client |
| Another mod swaps/subclasses the loading screens (R-5) | exact-class match only; effective-new-screen check respects earlier handlers; killswitch `customLoadingScreens=false` restores vanilla instantly |
| Loading screen stuck (delegate never closes) | delegate owns vanilla close logic (incl. vanilla's 30 s receiving cap); wall-clock failsafe (60 s receiving / 90 s SP-prepare) checked in `render` too because `Minecraft.doWorldLoad` renders without ticking the current screen |
| Portal payload without a following teleport (aborted hop) | HOLD releases after `holdTicks` + 2 s grace when no loading screen ever appeared; unconditional 90 s cap; logout reset |
| Client ticks stall during dimension swap | all controller phase math is wall-clock and also advanced from the render hooks — the fade cannot freeze |
| First unlock payload racing EMI's initial bake at login | `EmiReindexer` skips while `EmiReloadManager.isLoaded()` is false (the pending bake reads the fresh cache); otherwise one extra async reload (~1–3 s) |

## Test steps (once P5-W10's gradle line is merged)

1. `./gradlew build` — compiles incl. `EclipseEmiPlugin` (EMI compileOnly).
2. `runClient`, create a SP world → the Quiet-Eclipse **PREPARING** screen shows (sigil +
   tip), then the **RECEIVING** variant on join; gameplay is always reached. No vanilla
   dirt/panorama loading screens anywhere.
3. Nether portal there-and-back + `/dev limbo` teleport → RECEIVING variant each hop,
   always closes (vanilla close logic drives it).
4. Set `customLoadingScreens=false` in `eclipse-client.toml` (or settings) → vanilla
   screens return immediately; set back → eclipse screens return.
5. Failsafe: breakpoint/suspend the server during a hop (or drop the connection mid-hop) →
   screen force-closes after 60 s with a warn log; no trap.
6. `/dev xboxevent start tu12` + walk into the portal → screen glitch-slabs ramp, fade to
   black, black hold through the hop, fade-in at destination; same on exit. With an Iris
   shaderpack active the GUI choreography still renders (world pipeline gated off).
7. EMI (with `localRuntime` or the jar in `run/mods`): day 1 → `create:*` items absent
   from the index, recipes unresolvable; `eclipse:display_wand`, `eclipse:grave`,
   `eclipse:altar` and all `eclipse:classic_*` never indexed; locked RecipeGate recipes
   hidden. `/eclipse day set <create-unlock-day>` mid-session → "Requested EMI re-index"
   log, items appear within ~5 s (or the documented one-line stale hint if reflection
   drifted).
8. Remove EMI from the mods folder → client boots clean, no `dev.emi` classloading
   (`EclipseEmiPlugin` is only referenced by EMI's own annotation scan; `EmiReindexer`
   no-ops behind `ModList.isLoaded`).
