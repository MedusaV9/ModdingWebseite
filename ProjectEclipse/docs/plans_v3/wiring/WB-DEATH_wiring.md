# WB-DEATH wiring handoff

Custom death screen + ghost health bar + ship-respawn/door flow (P3 §3.7, worker P3-W7).
Everything is self-registered; **no shared file was edited** — no hub, registry, lang asset,
`EclipsePayloads`, `EclipseMod`, `limbo/door/**`, `client/hud/**` or existing `lives/` class
was touched.

## Already wired in this worker

- `network/death/DeathFlowPayloads` self-registers on its own MOD-bus
  `RegisterPayloadHandlersEvent` subscriber (the `GrowthPayloads` pattern) under version
  group `wbdeath1`. Ids: `eclipse:death/state`, `eclipse:death/revived`,
  `eclipse:death/ready`. Do NOT also register these in `EclipsePayloads` (duplicate
  registration throws at startup).
- `lives/DeathFlowHooks` (game bus, common) drives the server flow: death payload →
  vanilla respawn → capture the real respawn point → borrow the player onto the limbo
  ship deck → door opens via `RespawnDoorApi.playOpenFor` → walk-through / sneak-skip /
  auto-return → teleport home behind the client fade. Ghosts (banned at 0 hearts) are
  left exactly where `BanService.applyLimboState` parks them; only payloads are resynced
  and the door is never opened for them.
- `client/death/DeathScreenSwap` swaps the exact vanilla `DeathScreen` class for
  `EclipseDeathScreen` on `ScreenEvent.Opening`; `client/death/DeathFlowController`
  mirrors the server phases (TransitionFx envelopes, action-bar prompts,
  `ReceivingLevelScreen` suppression in bounded windows, sneak-to-skip input);
  `client/death/GhostHeartsLayer` self-registers its GUI layer above `PLAYER_HEALTH`,
  cancels the vanilla health layer while ghosted (with `leftHeight` compensation) and
  plays the one-by-one revive burst with `UiSounds.ghostBurst()`.
- Kill-switch: the `customDeathScreen` client config gates the screen swap and all client
  theater at read-time — saving `false` restores the full vanilla death flow immediately.
  The ghost health bar is deliberately NOT gated (it conveys gameplay-relevant state).
- The vanilla `PERFORM_RESPAWN` packet is never intercepted; with every custom payload
  lost the player still respawns normally.

## Event-ordering contract (do not reshuffle priorities)

| Event | Existing handler (priority) | WB-DEATH handler (priority) | Why |
|---|---|---|---|
| `LivingDeathEvent` | `LifecycleEvents.onLivingDeath` (NORMAL): heart decrement, kill transfer, ban at 0 | `DeathFlowHooks.onLivingDeath` (LOW) | payload must carry the post-death heart count / ban truth |
| `PlayerRespawnEvent` | `LifecycleEvents.onPlayerRespawn`, `HeartsService.onPlayerRespawn` (NORMAL): limbo re-apply for banned, heart-burst replay, max-health | `DeathFlowHooks.onPlayerRespawn` (LOWEST) | vanilla respawn position must be final before it is captured as "home"; ship teleport happens last |
| `PlayerLoggedInEvent` | `ReviveRitual.onPlayerLoggedIn` (NORMAL): completes offline revives | `DeathFlowHooks.onPlayerLoggedIn` (LOWEST) | a ghost revived while offline gets the celebration on this very login; mid-flow state resyncs after everyone else |

`DeathFlowHooks.onServerTick` (`ServerTickEvent.Post`) is the flow driver and also the
revive watch: a banned→unbanned flip on an online player IS the revive (every
`BanService.unban` caller — altar ritual, finale, admin — is covered without touching
`BanService`).

## Optional integration seam (P4 revive ritual)

`DeathFlowHooks.onRevived(ServerPlayer)` is a public entry point. The unban watch already
detects every revive one tick later, so **no edit is required** — but if the revive-ritual
owner wants a flash-free handoff, call it directly right AFTER `BanService.unban(target)`
for an online target. A duplicate call while the celebration is live is a no-op. During
the finale mass-revive (`EclipseWorldState.isFerrymanDefeated()`) the ship theater is
skipped automatically — `FinaleRitual` owns the trip home; only the ghost-heart burst
payload is sent.

## Lang merge

Merge `docs/plans_v3/langdrop/WB-DEATH.json` into both locale assets (`en_us` + `de_de`).
No locale asset is edited by this worker. Keys: `gui.eclipse.death.*` (screen, cause
lines, ghost tag) and `message.eclipse.death.*` (action-bar prompts).

## Risks / watch items

- **Deck coordinates**: `DeathFlowHooks.teleportToDeck` places feet at
  `(0.5, waterlineY+4, 0.5)` facing the stern door (yaw 90) — deck planks are at
  `waterline+3` per `GhostShipBuilder`. A ship-geometry rework must revisit this one
  method (grep `teleportToDeck`).
- **Cause keys**: the death screen maps `DamageSource.getMsgId()` onto
  `gui.eclipse.death.cause.<key>`; unmapped ids fall back to the generic line. New
  custom damage types can be flavored by adding lang keys only.
- **Health-layer cancel**: while ghosted, `RenderGuiLayerEvent.Pre` cancels
  `VanillaGuiLayers.PLAYER_HEALTH` and compensates `leftHeight` by one row (10 px) —
  matches the single-row/no-absorption ghost case. Another HUD worker replacing the
  health layer must coordinate here.
- **Restart amnesia**: the revive watch's known-ghost set is in-memory. A ghost revived
  offline across a full server restart logs in alive without the ship celebration
  (payloads/state still correct — cosmetic only, accepted).
- **Soft-lock proofing** (verify when changing timings): door auto-return 100 ticks after
  opening, whole-ship hard caps 160/240 ticks, death-screen button failsafe-enables after
  15 s, client phases go stale after 30 s, `ReceivingLevelScreen` suppression windows are
  4 s bounded, flows survive relogs and are TTL-pruned after 1 h.

## Test steps

1. **Normal death** (2+ hearts, `customDeathScreen=true`): die → Quiet-Eclipse screen
   (localized cause, hold-gated "Zur Reling", no score/coordinates) → respawn lands on
   the ship deck, hotbar heart bursts → door opens (~1.5 s) with glow + prompt → walk
   through → fade → wake at the real respawn point (bed respected).
2. **Sneak-skip + auto**: during the door phase sneak → immediate return. Stand still →
   auto-return 5 s after the door opened.
3. **Ghost death** (1 heart left): big last-heart shatter on the screen, ghost variant
   texts → respawn on ship, ghost grade + ghost heart row + "GEIST" tag, door stays
   closed, no vanilla hearts.
4. **Revive** (altar ritual or admin unban): ghost hearts burst one by one with the
   `ghost_burst` sound → real heart returns → back on deck → door opens → home.
5. **Relog mid-flow**: disconnect on the death screen / on deck / during the door phase;
   log back in → state resyncs and the flow completes. Disconnect as a ghost → still a
   ghost with the ghost bar on login.
6. **Kill-switch**: set `customDeathScreen=false` (no restart) → vanilla death screen and
   no ship detour; the ghost health bar still works.
7. **Finale**: after the Ferryman falls, mass-revive must NOT bounce players via the
   ship (FinaleRitual owns the return); ghost hearts still burst wherever they stand.
