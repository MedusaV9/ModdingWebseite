# P2-W10 wiring notes — Death/respawn & ship FX (R18)

Zero hub edits: no `EclipseMod` / `EclipsePayloads` / `FxPayloads` / `EclipseCommands` /
lang changes. Both new classes self-register (`@EventBusSubscriber(Dist.CLIENT)`); the
`eclipse:ghost_grade` pipeline row registers from `client.GhostGradeFx`'s static init (the
landed W1 `VeilPostController.register` pattern). No new sounds, no new textures — every
asset reuses existing sprites (`purple_wisp.png`, `heart_full.png`, `burst_sheet.png`).

## What W10 landed

- `client/ShipDoorGlow.java` — implements the frozen §3.2 entry
  `ShipDoorGlow.handleDoorGlow(boolean on)` that W1's `FxPayloads` already dispatches for
  `eclipse:fx/door_glow` (`on` = `a > 0.5`). While on + anchored + within 48 blocks:
  ONE budgeted Veil point light (radius 6, violet, brightness 0.8–1.2 pulsing at 0.5 Hz)
  plus the looping `eclipse:door_glow_motes` emitter (AMBIENT channel, ≤ 12 live motes).
  Releases the light slot and emitter on `off`, out-of-range (56-block hysteresis), anchor
  removal, dimension hop and disconnect.
- `client/GhostGradeFx.java` + `pinwheel post/program ghost_grade` — 0-lives spectral
  grade (`eclipse:ghost_grade`, GRADE priority, single frozen uniform `Ghost`): 70% desat,
  cold blue-violet lift, 12% vignette, 1.5 px radial chroma, subtle 0.2 Hz breathing.
  Reads `EclipseFxState.ghostAmount` (30-tick ease both ways — W1's payload handler
  already feeds it from `S2CGhostStatePayload`). Idle-skips below 0.003. Iris fallback:
  none, by design (R18 — grade-only).
- `hearts/client/HeartBurstOverlay.java` + `quasar/emitters/heart_burst.json` v2 —
  14-fragment shatter: 8 rotating glass shards on gravity+drag arcs over 600 ms (12 ticks)
  + 6 fast white→violet spark pops on the HUD; the world emitter now throws 14 heart
  shards (gravity 0.34 + drag 0.06 arcs) per burst. Trigger flow unchanged
  (`S2CHeartBurstPayload` → `trigger(int)`, `S2CQuasarPayload.HEART_BURST`).

## For P6-W3 (ship + physical door, THIS wave)

- Publish the anchor: `FxAnchors.set(FxAnchors.SHIP_DOOR, level, pos)` with `pos` at the
  door's **visual center (mid-height)** — the client applies NO offset: the point light
  sits exactly on the anchor and the motes rise from a ~1-block sphere around it.
- Fire the glow: `FxPayloads.sendFxEvent(level, FxPayloads.FX_DOOR_GLOW, doorPos,
  on ? 1.0F : 0.0F, 0.0F, range)` on every door state change (`range <= 0` → whole
  dimension; the client distance-gates anyway).
- Order independence: event-before-anchor and anchor-before-event both work — the client
  latches the desired state and materializes once both are present.
- **Login/relog**: the client's desired glow state resets on disconnect. Re-send the
  current door state per player at login (or re-fire it whenever you (re-)set the anchor),
  otherwise a relogging player sees no glow until the next state change.
- Re-setting the anchor to a new position repositions live FX in place (no off/on needed).

## For P3-W7 / P4-B9 (death screen & ghost logic)

- Toggle the grade with `FxPayloads.sendGhostState(player, active)` (or the raw
  `S2CGhostStatePayload`) when a player enters/leaves the 0-lives ghost state. The ease is
  30 ticks each way, so the "fades within 1.5 s" acceptance is met client-side.
- Client FX state clears on disconnect: re-send `active = true` at login for players who
  are still ghosts (server state is authoritative — same rule as the permanent sun rim).
- Nothing else to call: the pipeline activates itself off `EclipseFxState.ghostAmount`.

## Notes for the orchestrator

- **Plan-path correction**: §8.1 lists `client/hud/HeartBurstOverlay.java`, but the class
  has always lived at `hearts/client/HeartBurstOverlay.java`. Modified in place — the
  public contract (`LAYER_ID`, `trigger(int)`, `render(GuiGraphics, DeltaTracker)`) is
  untouched, so `EclipseGuiLayers` (W2-owned) and `EclipsePayloads` references are
  unaffected.
- **heart_burst emission math**: Quasar emitters spawn `count` particles on add AND every
  `rate` ticks starting at t=1 (verified in the Veil 4.3.0 jar). With `max_lifetime: 2`,
  `rate: 1`, `count: 7` the burst emits exactly 2 × 7 = **14** shards (v1 was 2 × 6 = 12,
  which §1.5 tabulated as "count 6"). The plan's "two sub-emitters" cannot be expressed in
  a single emitter JSON (`veil:tick_sub_emitter` needs a second, unowned emitter file) —
  the two populations (shards + sparks) live in the HUD overlay instead; the world burst
  is one 14-shard population with gravity+drag arcs.
- `eclipse:ghost_grade` has no `Time` uniform (frozen §3.3 list is `Ghost` only): the
  0.2 Hz breathing is premultiplied CPU-side onto the `Ghost` scalar by `GhostGradeFx`.
- Budget audit hooks: `FxBudget.lightsHeld()` counts the door light; the door claims at
  most one slot for the session ("exactly one FX light claimed" acceptance).
- Langdrop `P2-W10.json` is empty (en/de objects present, 0 keys) — W10 ships no
  user-visible strings (W3's "empty allowed" precedent).
