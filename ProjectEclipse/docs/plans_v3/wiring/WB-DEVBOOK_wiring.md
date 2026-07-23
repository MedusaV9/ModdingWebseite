# WB-DEVBOOK (P5-W2 Dev Handbook GUI) — wiring notes

## Zero `EclipseMod.java` / `EclipsePayloads.java` edits required

All new classes self-register:

- `devtools/dev/handbook/DevHandbookPayloads` — own MOD-bus `RegisterPayloadHandlersEvent`
  subscriber (version group `devhandbook1`, ids `eclipse:devhandbook/sync` +
  `eclipse:devhandbook/request`), exactly the `network/growth/GrowthPayloads` pattern. Do NOT
  additionally register these payloads in `EclipsePayloads` (duplicate registration throws at
  startup).
- The `DevHandbookBridge.setOpener(...)` hook requested by `P5-W1_wiring.md` §"P5-W2" is now
  installed **inside `DevHandbookPayloads.onRegisterPayloadHandlers`** (common/MOD bus), not
  from client setup: on a dedicated server there is no client setup, but the opener must run
  there so remote ops get the GUI. That P5-W1 wiring item can be checked off.
- `devtools/dev/handbook/DevHandbookClient.DisconnectReset` — own client-dist
  `@EventBusSubscriber` (logout cache wipe). No wiring line needed.

## Langdrop

Merge `docs/plans_v3/langdrop/WB-DEVBOOK.json` (26 keys, en+de complete, all prefixed
`gui.eclipse.devhandbook.*` + one server-side `dev.eclipse.handbook.no_client`). No key
collides with the already-merged lang files.

## Ask for W11 (pre-existing placeholder EN values, NOT owned by this worker)

`assets/eclipse/lang/en_us.json` already ships machine-placeholder values for W1's category
and danger keys, which the handbook rail/badges display verbatim, e.g.:

- `dev.eclipse.category.timer` = `"Dev — eclipse — category — timer"` (de_de is correct:
  `"Timer"`). Same for all 15 `dev.eclipse.category.*` keys.
- `dev.eclipse.danger.safe|caution|destructive` = `"Dev — eclipse — danger — …"` (de_de is
  correct). Suggested EN values: `Safe`, `Caution`, `Destructive`, and category names matching
  `DevDocsExporter.categoryTitle()` (`Timer`, `Buffs`, `Quests`, `Players`, `Stage`, `Display`,
  `Spawn`, `Xbox event`, `Mods`, `Music`, `Config & handbook`, `Analytics`, `Cutscene`,
  `Event`, `Legacy`).
- A handful of legacy doc keys are also placeholders (e.g. `dev.eclipse.doc.eclipse.altar.set`
  = `"Eclipse — altar — set"`). Cosmetic only; the GUI works regardless.

Lang assets are frozen for this worker, so the fix belongs to the W11 integration pass.

## Behavior notes for integrators

- Bare `/dev` (perm ≥ 2): server pushes `S2CDevHandbookPayload` (entries pre-filtered via
  `DevCommandRegistry.visibleTo(player)` + `DevReload.configReferences()`); client caches and
  opens `DevHandbookScreen`. Vanilla/unmodded clients (`hasChannel` false) get a clickable
  `/dev help` chat pointer instead of a payload (no kick).
- `C2SDevHandbookRequestPayload` (screen open, F5, after the Configs-tab Reload button) is
  op-gated server-side: permission < 2 is **silently dropped** — non-ops receive zero registry
  data, and the client cache is wiped on logout.
- RUN buttons execute through `player.connection.sendCommand(...)` — the server's Brigadier
  permission checks apply exactly as if the operator typed the command; no bypass payload
  exists. INSERT closes the screen and pre-fills `ChatScreen` with the literal prefix
  (`"/dev timer add "`). DESTRUCTIVE entries (both RUN and INSERT) show a confirm dialog first.
- The screen reuses the frozen `client/handbook` kit (`EclipseUiTheme`, `EclipseWidget`,
  `UiSounds`, `CursorManager`) read-only — no edits there.
- No additive fields were needed on `DevCommandRegistry`/`DevCommandDoc`: the record already
  carries `category`, `danger` (destructive flag), `clickAction`, `permission`, `legacy`.
  Zero registration call-site edits.
