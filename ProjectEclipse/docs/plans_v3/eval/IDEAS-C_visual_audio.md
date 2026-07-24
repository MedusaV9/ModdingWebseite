# IDEAS-C — Visual/Audio Polish Ideas (reusing existing tech)

Collector: IDEAS-C (Fable). Ranked best-first. Every idea reuses an existing pipeline,
emitter, class or asset-aliasing pattern already proven in the codebase — no new systems,
no new binary assets required (the repo's "new sound" convention is `sounds.json` aliasing
of existing OGGs with pitch/volume shifts, per P2-W1 §3.5 and `scripts/placeholder_gen/
HeartBurstPlaceholder.java`'s known-good-OGG copy pattern).

Effort: S = one class + maybe one JSON touched, no new uniforms/protocol.
M = 2–3 files or a new (small) post uniform / emitter JSON.

---

## 1. Distant horizon lightning at night (ambient life) — S

Silent violet bolts flicker on the horizon a few times per night, selling "the storms are
still out there" without any server traffic. `stormfx/StormFxClient.strikeLightning(from,
to, intensity)` is already a frozen client-side entry point that renders the full jittered
ribbon bolt + impact flash + budgeted point light; a small client scheduler (pattern:
`StormFxClient`'s arc-flash cadence, 20–60 t randomized) picks a random azimuth ~200 blocks
out, gates on `OverworldPurpleEffects.dayFactor < 0.1`, charges `FxBudget.Channel.AMBIENT`,
and optionally plays `event.lightning_far` at volume 0.2. Zero new assets, huge mood win.

**Extend:** `stormfx/StormFxClient` (new client tick scheduler), gate via
`client/sky/OverworldPurpleEffects.dayFactor`, budget via `veilfx/FxBudget.Channel.AMBIENT`.

## 2. Glitched-mob hit flash with the alt texture (reactive feedback) — S

Hitting a GLITCHED mob should feel like corrupting it further: force the datamosh alt-frame
for the hurt flash. `client/entity/glitch/GlitchedGeoRenderer.isAltFrame` already swaps
albedo + glowmask to `<id>_alt.png` on a deterministic hash schedule — OR-in
`animatable.hurtTime > 0` (clamped to the existing ≥ 8 t seizure guard) so every hit pops a
2–3 t corruption burst, and spawn one `eclipse:rift_spark` one-shot via
`QuasarSpawner.spawn` at the hit position for a crackle accent. The glowmask flips in
lockstep for free (it resolves off `getTextureLocation`).

**Extend:** `client/entity/glitch/GlitchedGeoRenderer` (`isAltFrame` + `preRender`),
emitter `assets/eclipse/quasar/emitters/rift_spark.json` (reused as-is).

## 3. Altar island idle motes (ambient life) — S

The altar is the social hub but sits visually dead between rituals. Reuse the proven
`LimboAmbience` rolling-window pattern: while the player is within ~48 blocks of the
client-synced `FxAnchors.ALTAR_CENTER` anchor, keep 2–3 looping `eclipse:door_glow_motes`
emitters (already a soft idle-mote JSON) drifting around the altar via
`QuasarSpawner.spawnManaged(..., FxBudget.Channel.AMBIENT)`, holding handles and culling the
oldest exactly like `LimboAmbience` does. Doubles cadence under `reducedFx` for free.

**Extend:** new tiny client class in `veilfx/` copying `LimboAmbience`'s window loop;
anchor from `veilfx/FxAnchors.ALTAR_CENTER`; emitter `door_glow_motes.json` (or a
re-tinted copy `altar_idle_motes.json`).

## 4. Wind layer inside fog storms (audio texture) — S

Storm interiors crush fog and rain visuals but the ear only gets the churn loop. Add an
`event.storm_wind` sound event aliased in `sounds.json` to `eclipse:ambient/limbo_loop` at
pitch 1.6 / volume 0.5 (the established alias trick — `event.storm_loop` and
`event.eclipse_drone` are both limbo_loop re-pitches already), and drive one
`AbstractTickableSoundInstance` whose volume tracks `StormInteriorFx.smoothedInterior`
(model: `LimboAmbience.LimboLoopSound` fade pattern). Breathes in/out with the fog because
the interior amount is already smoothed per tick.

**Extend:** `stormfx/StormInteriorFx` (loop instance), `registry/EclipseSounds` +
`assets/eclipse/sounds.json` (one alias entry).

## 5. Screen-edge purple veins at low hearts (reactive feedback) — M

At ≤ 2 hearts, thin violet veins crawl in from the screen edges — a diegetic "the eclipse
wants you" health warning. Cheapest robust build: a new GUI overlay modeled on
`client/hud/MarkVignetteOverlay` (edge vignette, fade in/out, F1-hidden) but with 3–4
layered vein textures drawn as tinted quads; or the shader version: a small FEATURE-priority
pipeline registered through `VeilPostController.register` whose `.fsh` grows veins with
`efxNoise`/`efxHash` from `eclipse_common.glsl` (uniform `Veins` fed from
`player.getHealth()/getMaxHealth()`). GUI version works under Iris; shader version looks
better — plan both like border_glitch does (post + world-space fallback).

**Extend:** `client/hud/MarkVignetteOverlay` (as template, new class), or new
`assets/eclipse/pinwheel/post/low_health.json` + `program/low_health.fsh` registered via
`veilfx/VeilPostController.PipelineSpec` (FEATURE priority).

## 6. Slow eclipse disc rotation (sky drama) — S

The 90-unit eclipse sun is a static quad; the three corona layers already counter-rotate
(`CORONA_DEG_PER_SEC = {3.0, -1.8, 1.2}`). Give the sun disc itself a very slow roll
(~0.4°/s, same `Axis.YP/XP.rotationDegrees` pattern used for the coronas in
`OverworldPurpleEffects.renderSky`) scaled by `EclipseFxState.eclipseAmount`, so at totality
the whole assembly visibly churns while the idle sun stays vanilla-still. One rotation call
in an existing render path — the highest drama-per-line in the file.

**Extend:** `client/sky/OverworldPurpleEffects.renderSky` (sun quad pose), amount from
`veilfx/EclipseFxState.eclipseAmount`.

## 7. Aurora bands during eclipse night (sky drama) — M

Post-intro nights (permanent sun rim era) get 2–3 slow violet-green aurora curtains near the
horizon: additive, alpha ≤ 0.2, scrolling vertex-gray noise — exactly the shader-less
"scrolling procedural noise alpha via per-vertex hash" trick `StormWallRenderer` already
uses for its shells, just bent into wide sky ribbons drawn in
`OverworldPurpleEffects.renderSky` after the stars. Gate on `nightAmount > 0.3 &&
EclipseFxState.permanentSunRim()` and fade with `dayFactor` so they never fight sunrise.

**Extend:** `client/sky/OverworldPurpleEffects.renderSky` (new band pass; vertex-noise
pattern lifted from `stormfx/StormWallRenderer`), gates from `dayFactor` +
`veilfx/EclipseFxState.permanentSunRim`.

## 8. Sub-bass swell during map growth (audio texture) — S

The expansion cutscene has the eclipse drone but no low-end weight when the terrain
actually grows. Add `event.growth_rumble` in `sounds.json` aliasing
`eclipse:ambient/limbo_loop` at pitch 0.45 / volume 0.9 / `stream: true` (halving pitch of
an already-dark loop yields a usable sub-bass bed — same procedure that made
`event.eclipse_drone` at pitch 0.6), and have `ExpansionSequence` play it as a path event at
the GROW phase start and stop it at settle, exactly where `event.eclipse_drone` is cued
today. If a real synthesized OGG is wanted later it drops in at the same path
(placeholder-OGG convention, `HeartBurstPlaceholder` precedent).

**Extend:** `sequence/ExpansionSequence` (GROW-phase cue), `registry/EclipseSounds` +
`assets/eclipse/sounds.json`.

## 9. LIGHTNING-phase strike vignette (small shader win) — S

During the intro's ramping-strike phase each bolt should squeeze the screen: a quick
vignette clamp + 1-frame exposure pop per strike. `world_grade.fsh` already runs during the
eclipse and has the `ExposureMul` uniform fed per frame; add a `StrikePulse` uniform
(decaying 0→ over ~8 t, shape borrowed from `ghost_grade.fsh`'s 12% vignette falloff) set by
a new `EclipseFxState.strikePulse(intensity)` scalar that the client's existing
`eclipse:fx/lightning_strike` payload handler calls with the strike intensity
`IntroLightningPhase` already puts on the wire. No new pipeline, no new activation row.

**Extend:** `assets/eclipse/pinwheel/shaders/program/world_grade.fsh` (+ its `.json`
uniform block), `veilfx/EclipseFxState` (one eased scalar), feeder in
`veilfx/VeilPostController.feedWorldGrade`.

## 10. Storm-interior lightning flicker (small shader win) — S

Inside a storm, the shell arc flashes (`StormFxClient`'s 20–60 t ambient arcs) are visible
but the fog itself never reacts. Add a `Flicker` uniform to `storm_interior.fsh` (brief
brightness lift + slight desat release, 4–6 t decay) pulsed from the same code path that
spawns the `eclipse:storm_arc` burst, routed through a new `EclipseFxState.setStormFlicker`
scalar next to the existing `setStormInterior/stormRain` feeds. The interior grade is
already active and fed per frame — this is one more float on an existing bus.

**Extend:** `assets/eclipse/pinwheel/shaders/program/storm_interior.fsh`,
`veilfx/EclipseFxState` (scalar), pulse call in `stormfx/StormFxClient` arc scheduler,
feeder in `stormfx/StormInteriorFx`'s registered `PipelineSpec`.

## 11. Rift hum (audio texture) — S

Open rifts crackle visually (`rift_spark` loop) but are silent. Add `event.rift_hum`
aliasing `eclipse:ambient/gazer_whisper.ogg` at pitch 0.7 (breathy reversed whisper reads
as unstable-space hum) with `attenuation_distance: 24`, and have `veilfx/rift/RiftFx` own a
positional `AbstractTickableSoundInstance` per open rift for its lifetime — same
owner-manages-loop discipline as `StormFxClient`'s per-storm churn loop, torn down where
the rift's `rift_spark` handle is already removed.

**Extend:** `veilfx/rift/RiftFx` (loop lifetime), `registry/EclipseSounds` +
`assets/eclipse/sounds.json`.

## 12. Shooting stars at deep night (ambient life / sky drama) — M

Rare (1–2 per night) violet streaks crossing the star dome: one thin additive quad animated
over ~30 t along a great-circle chord, spawned by a client scheduler and drawn in
`OverworldPurpleEffects.renderSky` right after the `StarField` VBO pass, reusing the corona
quads' additive blend state. Gate on `dayFactor < 0.05` and rain level 0; charge
`FxBudget.Channel.AMBIENT` so reduced-FX players skip them. Pairs beautifully with idea 7's
auroras for "the sky is alive" nights.

**Extend:** `client/sky/OverworldPurpleEffects.renderSky` (+ small state holder alongside
`StarField`), budget via `veilfx/FxBudget`.
