# P2-W5 wiring notes — Supply beam + shockwave (WaveOverlay v2)

Zero `EclipseMod` / `EclipsePayloads` / `FxPayloads` / `EclipseCommands` edits. Everything
self-registers (`@EventBusSubscriber`) or was already dispatched by W1's frozen registrar.
No lang strings (langdrop `P2-W5.json` is empty by design — the `event.beam_hum` subtitle
already shipped in W1's `P2-W1.json`).

## What W5 landed

- **`veilfx/SupplyBeamClient`** — implements the frozen compile contract
  `SupplyBeamClient.handle(S2CSupplyMarkerPayload)` that `network/fx/FxPayloads` already
  calls. Owns the client beam set, ONE budgeted Veil point light per beam
  (`FxBudget.tryLight`, radius 12, brightness 0.9±0.15 violet, claimed ≤ 64 blocks /
  released > 80), the positional `event.beam_hum` loop per beam, and the one-shot landing FX
  (`eclipse:altar_beam` + new `eclipse:supply_spark`, BURST channel, ≤ 128 blocks).
- **`veilfx/SupplyBeamRenderer`** — world-space beam at `AFTER_PARTICLES` (constant swap to
  `AFTER_TRANSLUCENT_BLOCKS` is the documented Sodium fallback): 4 crossed additive core
  planes + 4 haze planes + 8-segment impact glow disc, 64 blocks tall, scrolling
  `border_glitch.png` noise, per-beam pulse. LOD: > 192 blocks core planes only; > 512
  culled. 16 quads/beam max (§3.5 budget). Renders under Iris (world-space fallback, §7).
- **`economy/SupplyBeacon`** (M, scoped to FX emission + lifecycle; economy logic —
  cost, distance roll, ticket-load, loot-table crate — untouched):
  - `drop()` no longer sends `S2CQuasarPayload(ALTAR_BEAM)` and `onServerTick` no longer
    builds END_ROD `ClientboundLevelParticlesPacket`s (v1: 13 packets/s/marker × 512-block
    broadcast — the packet half of the drop lag). One `S2CSupplyMarkerPayload(add=true)`
    per drop instead.
  - Lifecycle (the "beam never disappears" fix): markers track their crate entity by UUID;
    once the `FallingBlockEntity` is gone the landing column is scanned and the marker
    binds to the barrel `BlockPos` (re-announcing the base if it landed past the predicted
    surface). First `PlayerInteractEvent.RightClickBlock` on the barrel OR the position no
    longer being a barrel → remove + broadcast `add=false, fadeTicks=40`. The 180 s expiry
    stays as a backstop only.
  - Login + dimension-change resync (`PlayerLoggedInEvent`, `PlayerChangedDimensionEvent` →
    overworld only): active markers re-sent with `fadeTicks=0`; the client clears its beams
    when leaving the overworld.
- **`client/WaveOverlay`** (v2) — registers the `eclipse:shockwave` pipeline row (FEATURE,
  frozen uniforms `ShockCenter (vec2 NDC) / ShockProgress / ShockStrength`) from its static
  init and feeds it: a live `EclipseFxState.shockwaveParams(...)` (world shockwaves from
  `eclipse:fx/shockwave`) wins; otherwise the submerge phases pulse looping rings from the
  screen center (45-tick cycle, strength ramps over SUBMERGE, fades over EMERGE). The flat
  tiled `wave_overlay.png` visual is gone; the GUI layer keeps only a slim underwater tint
  at 40% of the v1 wash alpha. `LAYER_ID`, the `render(GuiGraphics, DeltaTracker)`
  signature and the audio-muffle + crash-restore machinery are unchanged
  (`EclipseGuiLayers`' registration/whitelist needs no edit).
- Assets: `pinwheel/post/shockwave.json` + `shaders/program/shockwave.fsh/.json` (uses the
  `eclipse:eclipse_common` include), `quasar/emitters/supply_spark.json` (count 12/rate 1/
  life 2, no light module), and `quasar/emitters/altar_beam.json` lost its `veil:light`
  module (the ~60-concurrent-lights half of the drop lag, §1.5 rule: replaced by the ONE
  renderer-owned light above). Heads-up: `altar_beam` is also spawned by `HeraldEntity`,
  `ritual/BeamEmitter` and `worldgen/structure/StrongholdEmergence` via `S2CQuasarPayload` —
  those bursts keep their color/motion but stop attaching per-particle lights too, which is
  exactly the frozen §1.5 rule (`veil:light` only on ≤ 8-particle emitters) applied to the
  shared asset.

## Payload semantics (additive clarification of the frozen §3.2 shape)

`S2CSupplyMarkerPayload(add, pos, fadeTicks)` — the shape is untouched; W5 defines the
`fadeTicks` meaning **on add** (the plan only fixed it for remove):

| add | fadeTicks | Meaning |
|---|---|---|
| true | > 0 | fresh drop: fade the beam in over `fadeTicks` AND play the one-shot landing burst |
| true | 0 | resync (login/dimension return) or beam-base reposition after landing: snap, no burst FX |
| false | any | fade out over `fadeTicks` (`<= 0` snaps), then release light/hum |

Beams are keyed by their **XZ column** client-side (falling crates have no horizontal
motion), so a reposition add updates the existing beam instead of duplicating it.

## Notes for sibling workers / the orchestrator

- **W6/W7**: `eclipse:fx/shockwave` events are now actually visible — W1's handler already
  called `EclipseFxState.startShockwave`, and W5's pipeline row renders it. Nothing for you
  to register; just send the payload (`FxPayloads.sendFxEvent(level, FX_SHOCKWAVE, pos,
  strength, durationTicks, range)`).
- **W6**: `StartEventCutscene`'s v1 phase broadcasts (`S2CCutscenePayload` TILT/SUBMERGE/
  WAVES/EMERGE) keep driving WaveOverlay v2 unchanged — keep broadcasting them from your
  reworked timeline. SHAKE receipts still latch `activePhase` without visuals (v1 parity).
- **W2**: no whitelist change needed; `WaveOverlay.LAYER_ID` is already whitelisted and the
  layer id / render signature did not move.
- **W2 (`/eclipsefx supplybeam test`)**: spawn a beam client-side by calling
  `SupplyBeamClient.handle(new S2CSupplyMarkerPayload(true, pos, 10))`, remove with
  `(false, pos, 40)` — no server marker required for a visual test.
- **Frozen-file check**: `admin/EclipseCommands.java` line ~1306 calls
  `SupplyBeacon.drop(server)` — the signature and return value are unchanged.

## Deviations from the plan text

- None functional. One addition: the server also re-syncs markers on
  `PlayerChangedDimensionEvent` (plan only listed login sync) because the client clears its
  beam set when leaving the overworld — without the re-send, a nether round-trip during an
  active drop would lose (or worse, stale-keep) beams.
