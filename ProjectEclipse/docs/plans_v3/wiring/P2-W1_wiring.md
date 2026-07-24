# P2-W1 wiring notes — FX core, sun truth, global grades, sky scale-up

Zero `EclipseMod` / `EclipsePayloads` / `EclipseCommands` edits. Everything below
self-registers (`@EventBusSubscriber`) or is a note for a sibling worker about the exact
signature W1 already calls / provides.

## What W1 landed (hub surface siblings consume)

- `veilfx/EclipseFxState` — frozen §3.1 blackboard. Extra (additive) helpers beyond the
  frozen list: `exposureMul(float partialTick)` (R3 TOTAL exposure dip, fed to
  `world_grade`), `clientTicks()` (package-private time base for `FxBudget`).
- `veilfx/FxBudget` — frozen §3.1. Channels AMBIENT/BURST/SEQUENCE/STORM; window caps
  12/15/30(burst 60)/12 per 20 ticks under a global 30 (SEQUENCE bursts may push to 60 for
  ≤3 s, then hysteresis clamps back); live-particle cap 1500; lights cap 16. `reducedFx`
  halves everything; tier 0 (= `reducedFx` + `veilPostFx` off) kills AMBIENT.
- `veilfx/SunTracker` — frozen §3.1 + additive helpers:
  - `sunAngleRadians(ClientLevel, float)` — the ONE celestial angle; the sky quad rotates
    from it and `SunScreen` is projected from it.
  - `worldToNdc(Vec3, Vector4f dest)` — project any world point through THIS frame's exact
    render matrices (AFTER_SKY capture, bobbing included). W5 shockwave / W2 captions /
    W9 lightning may use it instead of touching `veil:camera`.
- `veilfx/FxAnchors` — frozen §3.1; server map + client cache + login resync + server-stop
  clear. `handleClient(id, set, pos)` is the payload-side entry (already wired).
- `veilfx/VeilPostController` — table-driven rewrite. Frozen API kept:
  `register(PipelineSpec)`, `setEnabled(id, bool)`, `isActive(id)`.
  - `PipelineSpec(ResourceLocation id, PipelinePriority priority, BooleanSupplier
    activationPredicate, Consumer<PostPipeline> uniformFeeder)`; priorities
    `GRADE(0) < FEATURE(1) < TRANSITION(2)` (eviction rank; ≤3 concurrent, lowest evicted
    first). Manager run order: GRADE(3000) → FEATURE(2000) → TRANSITION(1000).
  - `setEnabled(id, true)` = force-on, `false` = force-off; `clearOverride(id)` returns to
    predicate-driven (additive helper — W2's `/eclipsefx post` may expose all three).
    Overrides clear on logout.
  - **W3/W4 note**: the controller registers backward-compat rows for `eclipse:limbo`
    (`Intensity` only) and `eclipse:border_glitch` (`Proximity`+`Time`) via a
    never-overwrite path. Your `register(...)` call REPLACES the compat row regardless of
    class-load order — just call it from your feature class's static init.
  - **W4 note**: `VeilPostController.setBorderProximity(float)` still exists as a
    deprecated shim delegating to `EclipseFxState.setBorderProximity` so the pre-P2
    `BorderFxRenderer` keeps compiling. Migrate to `EclipseFxState` and the shim can be
    deleted (it is W1-owned; ping W1 or delete it in your PR once nothing references it).
- `veilfx/QuasarSpawner` — every spawn path now charges `FxBudget` first. New overloads:
  `spawn(id, pos, Channel)`, `spawnManaged(id, pos, Channel)`,
  `spawnOrFallback(id, pos, Channel)`, `ensureAttached(id, entity, Channel)`. The old
  signatures default to BURST (one-shots) / AMBIENT (attached loops). Budget refusal =
  silent drop (NEVER the vanilla fallback burst — that stays reserved for broken/unknown
  emitter ids). Pass SEQUENCE/STORM explicitly in sequence/storm code.
- `network/fx/*` — the 9 frozen payloads + `FxPayloads` registrar (MOD-bus, own version
  group `fx1`, ids `eclipse:fx/...`). Server helpers available now:
  `FxPayloads.sendEclipsePhase(server, phase, intensity, rampTicks, permanentRim)`,
  `FxPayloads.sendFxEvent(level, id, pos, a, b, range)` (range ≤ 0 → whole dimension),
  `FxPayloads.sendGhostState(player, active)`.
- Post pipelines: `eclipse:world_grade` (new; uniforms `EclipseAmount, NightAmount,
  DesatAmount, ExposureMul`) and `eclipse:sun_halo` (rewritten screen-space; uniforms
  `SunScreen (vec4), HaloStrength, RimOnly`). Shared include
  `#include eclipse:eclipse_common` provides `efxHash/efxNoise/efxChroma/efxBlockOffset/
  efxCrush` — use it in every new `.fsh`.
- Sounds registered (`registry/EclipseSounds` + `sounds.json`, placeholder oggs):
  `event.lightning_close`, `event.lightning_far`, `event.storm_loop` (fixed range 64),
  `event.storm_burst`, `event.rift_open`, `event.rift_slam`, `event.eclipse_drone`,
  `event.beam_hum` (fixed range 48), `ui.caption_tick`.
- Config: `EclipseClientConfig.cinematicViewDistance()` (bool, default true) — W2's
  `ViewDistanceClient` must gate on it.

## Sibling signatures W1's `FxPayloads` dispatch ALREADY CALLS (compile contract)

These are direct compile-time references per the plan ("integration builds once all
packages land"). If your class/method differs, the merge build breaks — implement exactly:

| Worker | Required signature | Called for |
|---|---|---|
| W9 | `stormfx.StormFxClient.handle(S2CStormStatePayload)` | `eclipse:fx/storm_state` payload (frozen in plan) |
| W9 | `stormfx.StormFxClient.strikeLightning(Vec3 from, Vec3 to, float intensity)` | `eclipse:fx/lightning_strike`; W1 reconstructs `from = pos + sunDir·180` (y ≥ pos.y+60) via `SunTracker`; `b` (giant flag) is NOT forwarded — giant strikes should arrive with `a = 1.0`, and the giant SOUND is the sender's job (W6) |
| W5 | `veilfx.SupplyBeamClient.handle(S2CSupplyMarkerPayload)` | `eclipse:fx/supply_marker` payload |
| W2 | `cutscene.client.ViewDistanceClient.handle(S2CViewDistancePayload)` | `eclipse:fx/view_distance` payload |
| W2 | `cutscene.client.CaptionRenderer.fade(int inTicks, int holdTicks, int outTicks, int argb)` | `eclipse:fx/screen_fade` payload |
| W2 | `cutscene.client.CaptionRenderer.enqueue(String langKey, int durationTicks, int style)` | `eclipse:fx/caption` payload (style 0/1/2 per `S2CCaptionPayload` constants) |
| W8 | `veilfx.rift.RiftFx.openRift(Vec3 pos, Vec3 normal, float width, int durationTicks, int style)` | `eclipse:fx/rift_open`; W1 passes normal = (0,1,0), durationTicks = 0 (= stay open until close), style = (int) b (0 structure / 1 portal) |
| W8 | `veilfx.rift.RiftFx.closeRift(Vec3 pos)` | `eclipse:fx/rift_close` |
| W10 | `client.ShipDoorGlow.handleDoorGlow(boolean on)` | `eclipse:fx/door_glow` (on = a > 0.5) |

- **W9 heads-up — payload accessor rename**: the plan table's `type` field on
  `S2CStormStatePayload` is `stormType()` in Java. A record component named `type` cannot
  implement `CustomPacketPayload` (its generated `int type()` accessor clashes with the
  interface's `Type<?> type()` — javac hard error, found in the W1 compile check). Wire
  order/format is UNCHANGED (`stormId, center, radius, height, stormType, state, ticks`);
  the `TYPE_WALL/TYPE_VORTEX/STATE_*` constants live on the payload as planned.
- Glide FX (`eclipse:fx/glide_start|stop`): no sibling class is declared for it, so W1's
  handler attaches/removes the looping `eclipse:glide_trail` emitter (W6 owns the JSON) on
  the nearest player within 8 blocks of `pos` via `QuasarSpawner`. W6: if you also want the
  FOV +5 ease + wind loop from R10, add it in your own client class keyed on the same
  events — do NOT re-handle the emitter (double-attach is prevented by `ensureAttached`,
  but keep ownership clean).

## Notes for the orchestrator

- `OverworldPurpleEffects.dayFactor` became `public` (was package-private) — needed by the
  controller's NightAmount feeder. No other visibility changes.
- The compat `eclipse:limbo` row keeps v1's `Intensity`-only feed; after W3 lands their
  richer feeder replaces it. Same for `eclipse:border_glitch` (W4).
- `EclipseFxState.clearAll()` runs on logout via its own subscriber; the controller also
  removes all pipelines quietly on logout (as before).
