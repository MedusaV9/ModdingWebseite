# P2-W9 wiring notes — Storm walls & vortex system

Zero foreign-file edits: no `EclipseMod` / `EclipsePayloads` / `FxPayloads` /
`EclipseCommands` / lang / build changes. Every class self-registers
(`@EventBusSubscriber`, client or game bus) and the `eclipse:storm_interior` pipeline row
is a static-init registration. `langdrop/P2-W9.json` is the empty en/de shape — all four
storm sound subtitles (`event.storm_loop/_burst`, `event.lightning_close/_far`) were
already in W1's drop, and W9 adds no UI text.

## What W9 landed

| File | What |
|---|---|
| `stormfx/StormFxClient.java` C | Client storm list + FX orchestration. FROZEN `handle(S2CStormStatePayload)` / `strikeLightning(Vec3,Vec3,float)` — verified against W1's `FxPayloads` call sites, including the `stormType()` accessor heads-up |
| `stormfx/StormWallRenderer.java` C | World-space shells: opaque occluder (never see inside), 4/2-shell LOD with crossfade, 8-quad impostor ring > 320 blocks, swirl cone cap (vortex) / ragged dome ring (wall), bolt + arc ribbons (`AFTER_PARTICLES`) |
| `stormfx/StormInteriorFx.java` C | Interior: `ViewportEvent.RenderFog` clamp (~24 blocks, works under Iris), fog color to storm slate, `eclipse:storm_interior` pipeline row (GRADE priority, uniforms `Interior, RainAmount, Time`), rolling `storm_rain_sheet` loop emitters |
| `stormfx/StormReveal.java` C | Server reveal choreography (R14): pause → glitch → 5 hammer strikes → ramp → `finishLoading` callback (P1 §6.1 contract, runs exactly once) |
| `stormfx/StormRegistry.java` C | Server source of truth: spawn/dissipate API, dimension broadcast, login/dimension/respawn resync, `FogStormSites.sites()` poll bridge |
| `stormfx/package-info.java` C | Package doc (not in the plan file list; documentation only) |
| `assets/eclipse/pinwheel/post/storm_interior.json` + `shaders/program/storm_interior.fsh/.json` C | Interior grade (crush + desat + sky wipe + procedural rain streaks + vignette; `eclipse:eclipse_common` helpers, zero textures) |
| `assets/eclipse/quasar/emitters/storm_arc.json` C | One-shot arc crackle burst (count 6, additive, white→violet) |
| `assets/eclipse/quasar/emitters/storm_rain_sheet.json` C | Interior rain loop (rate 4 / count 2 per plan; `veil:initial_velocity` down + `veil:gravity`) |
| `assets/eclipse/quasar/emitters/vortex_wisp.json` C | Vortex smoke wisp loop (rate 3 / count 2; `veil:vortex` + `veil:drag` + `veil:wind` — codec field names verified against Veil 4.3.0) |

## Frozen surface delivered (exact, for consumers)

```java
// client — dispatched by W1's FxPayloads (ALREADY WIRED, nothing to do):
StormFxClient.handle(S2CStormStatePayload payload);          // eclipse:storm_state
StormFxClient.strikeLightning(Vec3 from, Vec3 to, float i);  // eclipse:fx/lightning_strike

// server control API (StormRegistry):
int  spawnWall  (ServerLevel lvl, Vec3 center, float radius, float height, int rampTicks);
int  spawnVortex(ServerLevel lvl, Vec3 center, float radius, float height, int rampTicks);
void dissipate(int stormId, int ticks);   // fade out, then forget
void remove(int stormId);                 // 2-tick fade
@Nullable StormData get(int stormId);     // record: id, dimension, center, radius, height, stormType, state
List<StormData> storms(ServerLevel lvl);
void handleFogSite(ServerLevel lvl, String siteId, Vec3 center, float radius, boolean active);
// constants: RAMP_TICKS=80, DISSIPATE_TICKS=60, REVEAL_TOTAL_TICKS=200,
//            DEFAULT_RADIUS=24, heightFor(r)=clamp(2r, 32, 96)

// server reveal (StormReveal — P1 §6.1 contract):
void request(ServerLevel lvl, String areaId, Vec3 center, float radius, float height,
             Runnable finishLoading);     // radius/height <= 0 → fallback defaults
```

Reveal protocol needs **no extra payload shape**: a `SPAWN` whose `ticks >
RAMP_TICKS` is reveal-style — the client holds the storm invisible, pulses the 0.4
`rift_glitch` when the 40-tick pause ends (`TransitionFx.glitchPulse(0.4F, 20)`), sits
through the server-driven hammer strikes and ramps shells over the LAST 80 ticks.

## P2-W6 — intro vortex recipe (frozen, next wave)

```java
// intro t=300 (R10/R15): raise the spawn vortex, ~22 radius / 48 height reads right
int vortexId = StormRegistry.spawnVortex(level, spawnCenter, 22.0F, 48.0F, StormRegistry.RAMP_TICKS);
// giant-strike beat: collapse it
StormRegistry.dissipate(vortexId, StormRegistry.DISSIPATE_TICKS);
```

- Broadcast + late-join resync are automatic; W6 needs **zero client code**. The client
  gives vortex-type storms swirling shells (0.35 rad/s), an inward-tilt cone cap and three
  spiraling `vortex_wisp` emitters.
- For the giant strike itself send `FxPayloads.sendFxEvent(level, FX_LIGHTNING_STRIKE,
  impactPos, 1.0F, 0f, 0.0)` (W1 dispatch reconstructs the sky origin along the sun
  direction). Audio is the **sender's** job (sender-owns-audio rule) — W6 plays the giant
  crack; `strikeLightning` is visual-only.

## P1 fog sites — NO wiring needed, plus two asks

`StormRegistry` polls the frozen `FogStormSites.sites()` seam (§3.10) every 40 ticks:
a site turning `active` (i.e. `materializeSite` ran — terrain already placed) gets the
full R14 reveal via `StormReveal.request` (wall radius = site radius + 4, height =
`heightFor`); `active=false` dissipates it. The poll is idempotent (stable per-site storm
ids). When W1.6's two-phase apply lands, P1 may instead call `StormReveal.request(...)`
directly from the trigger with a real `finishLoading` — the poll sees the storm standing
under the same site id and will not double-fire.

1. **Compile error in P1-W1.9's `FrozenParams.java:320`** — the lambda
   `() -> defaultFogstormsJson(mapSeed)` captures `mapSeed`, which is reassigned at line
   301 → not effectively final → javac hard error. One-liner: copy to a
   `final long frozenSeed = mapSeed;` after the randomize branch and capture that. (W9's
   whole compile closure was verified green in a sandbox with exactly that patch applied
   to an out-of-tree copy.)
2. **Restart gap**: after a server restart at stage ≥ 3, `loadSites`/`parseSites` hardcode
   `active=false` and the stage listener only fires on stage *transitions* — sites never
   re-announce, so standing storms don't come back. Suggest persisting the placed flag
   (or marking loaded sites with existing placement `active=true` on load); W9's poll then
   restores the walls automatically, with the plain 80-tick ramp via `handleFogSite`-style
   re-announce or the reveal if you route through `StormReveal.request`.

## Hub / orchestrator wiring (NOT edited by W9)

| Target | Action |
|---|---|
| `network/EclipsePayloads.java` | Register `S2CFogStormPayload.TYPE` with a **no-op client handler** (P1-W1.9's pending row). Keep it no-op: W9 consumes sites server-side; a client handler that spawns visuals would double the storms |
| W2 `cutscene/dev/FxDevCommands.java` (P5 may alias) | The planned `/eclipsefx storm add x y z radius height wall\|vortex` → `StormRegistry.spawnWall/spawnVortex(level, center, radius, height, RAMP_TICKS)` (keep the returned id for `remove`); `storm remove <id>` → `dissipate(id, DISSIPATE_TICKS)`; `storm bolt` → `FxPayloads.sendFxEvent(level, FX_LIGHTNING_STRIKE, hitPos, 1.0F, 0f, 0.0)`; consider `storm reveal` → `StormReveal.request` for R14 QA |
| Lang merge | `langdrop/P2-W9.json` — **zero keys** (empty en/de shape; storm subtitles were W1's) |

## Notes for P6 (fog mobs W7/W8, later)

- Spawn gating: `StormRegistry.storms(level)` / `get(id)` snapshots (center, radius,
  height, stormType, state) server-side; `FogStormSites.sites()` carries the `mobSet`.
- Client-side "am I inside?": `StormInteriorFx.interiorAmount()` (smoothed 0..1; > 0.5 ≈
  camera fully inside a storm).

## Deviations from the plan sketch

1. `StormReveal.request` takes the `ServerLevel` up front (the §6.1 sketch had no level
   param) — a reveal cannot broadcast without its dimension.
2. Bolt ribbons use 6 sub-segments instead of the sketched 3 (still ≤ 14 quads: 6 core +
   6 glow + 2 impact cross-flash — same budget, smoother read).
3. Vortex wisps are swirled from Java (`ParticleEmitter.setPosition` per tick) with the
   `veil:vortex` force module adding micro-swirl only — a baked JSON vortex radius could
   not track per-storm sizes.
4. `stormfx/package-info.java` added (documentation only).
5. Plan line 409 names the langdrop `P2W9.json`; the folder convention (`P2-W1.json`, …)
   won: `P2-W9.json`.

## Visual QA checklist (needs runClient — not run by W9)

1. **Wall, near** (`/eclipsefx storm add 0 100 0 24 48 wall` once W2's command lands, or
   stand at a materialized fog site): 4 concentric churning shells + slow drift, ragged
   dome ring on top, base skirt; shell arc crackles every 1–3 s with quiet far-thunder;
   positional churn loop from the wall direction within 56 blocks.
2. **Cannot see inside**: from outside, walk the full circle — the interior must read as
   a near-black silhouette at every angle/elevation (opaque occluder at r−5); flying above
   the rim must still show the cone/dome cap, not the interior floor.
3. **LOD**: back away — shells drop 4→2 at ~160 blocks and to a static 8-quad impostor
   ring at ~320, each with a ~16-block crossfade (no pop); arcs/wisps/sounds stop beyond
   160.
4. **Interior**: walk through the wall — fog clamps to ~24 blocks and tints slate, screen
   grade crushes/desaturates with rain streaks (`RainAmount`), rain sheet particles fall
   around the camera; everything releases smoothly (~6-tick ease) on exit. Under an Iris
   pack: fog + particles still work, the post grade stays off.
5. **Reveal** (`StormReveal.request` or first site materialization): terrain visible →
   ~2 s of nothing (pause) → one 0.4 glitch pop → five lightning hammers with cracks over
   ~3 s, ramping louder → shells fade/scale in over 4 s → storm-burst sting; log shows the
   `finishLoading` line exactly once.
6. **Vortex** (`/eclipsefx storm add 0 100 0 22 48 vortex`): shells counter-rotate with
   tangential swirl + 8° inward tilt, cone cap narrows to the top, three smoke wisps
   spiral up and around; `storm remove` collapses it over 3 s.
7. **Resync**: relog / change dimension / respawn near a standing storm — it must be back
   (mid-ramp storms may resync at full ramp; accepted).
8. **Budgets** (plan acceptance line 410): 3 storms + border + a cutscene stay within
   budgets — frame-time spot check vs. baseline; zero per-frame allocation regressions
   (shells build into per-frame `BufferBuilder`s from static scratch state, no iterators
   in the render path).
