#!/usr/bin/env python3
"""backlog_fx — PH-IMPROVE-2: the PHOTON-QUALITY.md gap-backlog assets, via fxlib.

Implements the never-shipped IDEAS-*.md concepts (into
`src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`), each with its
`.fxproj` editor sibling. Java seams per asset are listed with their registrar:

    eclipse:riss_maw_snap         IDEAS-player #4 second beat: single-frame white-cyan
                                  HDR slice + 8 collide-and-die shards, spawned with
                                  setDelay(a = openTicks) from the CUE_RISS_SCHLAG leg
                                  (client/wand/WandPhotonFxRows).
    eclipse:shadow_bolt_impact    IDEAS-mobs #6 detonation flower: REVERSE_SUB dark rip
                                  + ADD violet shards two-pass burst + 4-beam raycast
                                  micro-cross. CUE_SHADOW_BOLT_IMPACT, allowMulti=true
                                  (veilfx/MobPhotonFxRows; ShadowBoltProjectile.burst).
    eclipse:intro_sunrise_rays    IDEAS-events #8 god-ray ribbons: 4 staggered ara
                                  ribbons climbing sunward off the island rim + rim
                                  motes. CUE_INTRO_SUNRISE from IntroSequence.
                                  beginSunrise (veilfx/EventsPhotonFxRows).
    eclipse:boss/tyrant_fog_arms  IDEAS-boss #10 P3 fog arms: model particles along the
                                  shipped eclipse:item/fog_tendril mesh, precessing +
                                  breathing, plus shed motes. CUE_TYRANT_FOG_ARMS
                                  entity-lane (veilfx/BossPhotonFxRows; FogTyrantEntity
                                  P3 seam re-fires every 100t — the spec's 160t cadence
                                  with a 200t asset would gap 120t under the absorb-only
                                  CACHE dedup; 100t divides 200t = seamless).
    eclipse:revenant_fog_ribbons  IDEAS-mobs #4 robe wisps: hem cylinder wisps tearing
                                  off as short TRAIL streamers. PhotonMobFx attach row
                                  (no wire).
    eclipse:glitch_drip           IDEAS-mobs #5 corruption drip loop on all
                                  GlitchedMonster kinds. PhotonMobFx attach row.
    eclipse:deckhand_soul_flame   IDEAS-mobs below-the-cut: hood soul-candle loop
                                  (limbo rowers). PhotonMobFx attach row.
    eclipse:deckhand_soul_flare   the `rise` hostile flare: fired on the isHostile()
                                  RISING edge via the PhotonMobFx edge lane. (The spec's
                                  "burst emitter in the same file" cannot retrigger on a
                                  state edge — an attached loop spawns ONCE — so the
                                  flare ships as the sentinel_alert-pattern edge
                                  one-shot instead; same total budget.)
    eclipse:intro_storm_wall      IDEAS-events #7 vortex wall lightning: 3 sputtering
                                  raycast wall-chord beams + orbiting wall glow +
                                  zenith bloom, authored at the intro vortex's real
                                  r=22/h=48 (spawnLoop carries no scale knob).
                                  WINDOWED loop — stormfx/IntroStormWallFx watches the
                                  TYPE_VORTEX storm payloads (replay parity free).
    eclipse:credits_contrail      IDEAS-events #9b flyover contrails: one crisp ara
                                  ribbon per flyer, attached client-side to moving
                                  BlockDisplays (client/credits/CreditsContrailFx).
    eclipse:end_crack_bleed       IDEAS-world #6a Option B: 3 splayed HDR bleed shafts
                                  + seam-strip embers per crack-race step.
                                  CUE_END_CRACK (veilfx/WorldPhotonFxRows;
                                  EndShatterSequence sends it beside FX_RIFT_OPEN and
                                  RiftFx.openRift retires its EXPANSION_RIFT_GLOW while
                                  a bleed is live at the tear).
    eclipse:wizard_hearth         IDEAS-world #10 observatory ambience: gusty chimney
                                  sparks + one rising smoke wisp + interior lantern
                                  motes. WINDOWED loop (client/wizard/
                                  ObservatoryAmbience probe window). The spec's static
                                  `trail_emitter` cannot render (a non-moving trail
                                  head never passes minVertexDistance) and trail
                                  emitters have no `shape` block to animate, so the
                                  wisp is a 1-carrier particle emitter dragging a
                                  TRAIL-type ribbon — same one-thin-strip read.
    eclipse:era_dust_motes        IDEAS-events #10 CRT era motes: GPU-instanced pixel
                                  dust + subliminal dead-pixel blinks around the local
                                  player, WINDOWED inside the xbox dims only
                                  (client/xbox/EraDustMotes; INTEGRATION.md §4
                                  amendment sanctions the player-scoped event-dim
                                  ambient loop). Verified legal before authoring.

NOT here: `storm_wall_veins` — SKIPPED. The storm rebuild already ships the concept as
`eclipse:storm_vein_bolt` (tools/photon/build_storm_fx.py, driven by
`StormPhotonFx.tickVein`): crawling luminous veins on the storm shell wall. Verified to
cover the IDEAS-world storm-veins concept 1:1; authoring a second vein asset would
double-draw the same read.

These files are fxlib-generated (this script IS the committed source) AND each ships an
editor-openable `.fxproj` sibling (binary-diff law / LINT-FXPROJ). Regenerate +
validate with:

    python3 tools/photon/backlog_fx.py
    python3 tools/photon/fxlib.py validate --lint

Style-guide conformance (FX-STYLE-GUIDE.md §1): riss/glitch concepts stay on GLI_*
(white pops, cyan/violet, dead-signal fades), shadow bolt on COR_VIOLET/COR_INK wither
tones, the intro pair on SAC gold/violet with the exact SUNRISE_WARM_BLOOM gold
(#FFC994) and the permanent rim violet (#8800FF), fog family on desaturated slate-teal
(alpha-blend, shade, no bloom — fog is weather), deckhand flames on limbo soul-blue,
era motes on the ERA_* CRT LUT tokens. Eased curves per §5.1 house segments; every
looping emitter carries a cull box + hard maxParticles.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, I, REPO_ROOT,
    aabb, blend, box, burst, circle, cone, constant, curve, cylinder, dot, gradient,
    material_shader, mesh, nf3, random_between, random_curve, random_gradient, rom,
    sphere, texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_BEAM = "eclipse:textures/particle/beam_core.png"
TEX_STATIC = "eclipse:textures/particle/static_4x4.png"
TEX_SQUARE = "eclipse:textures/particle/square_4x4.png"
TEX_NOISE_STRIP = "eclipse:textures/particle/noise_strip.png"

BLEND_REVERSE_SUB = blend("ONE", "ONE", "ONE", "ZERO", "REVERSE_SUB")

# FX-STYLE-GUIDE §1 tokens (r, g, b in 0..1) + the spec-pinned exact tints.
SAC_HOT = (0.965, 0.937, 1.0)         # #F6EFFF
SAC_VIOLET = (0.725, 0.549, 1.0)      # #B98CFF (= GLI_VIOLET)
SAC_DEEP = (0.482, 0.310, 0.816)      # #7B4FD0
SAC_GOLD_PALE = (1.0, 0.914, 0.659)   # #FFE9A8
SAC_VOID = (0.180, 0.137, 0.278)      # #2E2347
GLI_WHITE = (1.0, 1.0, 1.0)
GLI_CYAN = (0.310, 0.910, 1.0)        # #4FE8FF
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38
COR_VIOLET = (0.616, 0.306, 0.867)    # #9D4EDD
COR_INK = (0.235, 0.035, 0.424)       # #3C096C
ERA_CREAM = (1.0, 0.953, 0.769)       # #FFF3C4
ERA_AMBER = (1.0, 0.698, 0.369)       # #FFB25E
ERA_SHADOW = (0.227, 0.227, 0.333)    # #3A3A55 (= STM_SLATE)
STM_SLATE = ERA_SHADOW
SUNRISE_GOLD = (1.0, 0.788, 0.580)    # #FFC994 — the SUNRISE_WARM_BLOOM tint, exact
RIM_VIOLET = (0.533, 0.0, 1.0)        # #8800FF — the permanent-rim violet, exact
SOUL_BLUE = (0.4, 0.8, 1.0)           # #66CCFF (IDEAS deckhand spec)
SOUL_DEEP = (0.133, 0.267, 0.667)     # #2244AA
BLEED_PALE = (0.906, 0.839, 1.0)      # #E7D6FF (IDEAS end-crack spec)
BLEED_VIOLET = (0.482, 0.247, 0.851)  # #7B3FD9
HEARTH_GOLD = (1.0, 0.824, 0.478)     # #FFD27A (IDEAS hearth spec)
HEARTH_EMBER = (0.886, 0.341, 0.118)  # #E2571E
SMOKE_DARK = (0.227, 0.204, 0.188)    # #3A3430
MOTE_WARM = (1.0, 0.914, 0.753)       # #FFE9C0
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body


def eased(points, lock=True):
    """NF curve through (t, value) points with smoothstep tangents — every non-flat
    segment carries genuinely off-chord control points (LINT-LINEAR-CURVE clean)."""
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        third = (x1 - x0) / 3.0
        segments.append((x0, y0, x0 + third, y0, x1 - third, y1, x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments, lock=lock)


# Noise remap curves (NoiseSetting.remap, jar-default output band -1..1, xAxis "base
# noise"). Photon's default remap is the identity ramp, which spreads the fBm evenly and
# reads as uniform jitter. Reshaping the histogram is what turns jitter into BILLOWING:
#   FOG_BILLOW_REMAP  soft S with plateaus near both ends — the field lingers in a lobe,
#                     then slews across: slow, organic, cloud-like folding.
#   FOG_SHRED_REMAP   near-binary step — the field snaps between two states, so small
#                     rags flick sideways instead of wandering.
FOG_BILLOW_REMAP = curve(-1.0, 1.0, [
    (0.0, 0.0, 0.30, 0.02, 0.42, 0.10, 0.5, 0.5),
    (0.5, 0.5, 0.58, 0.90, 0.70, 0.98, 1.0, 1.0)], "base noise", "remap result")
FOG_SHRED_REMAP = curve(-1.0, 1.0, [
    (0.0, 0.06, 0.34, 0.0, 0.44, 0.04, 0.5, 0.5),
    (0.5, 0.5, 0.56, 0.96, 0.66, 1.0, 1.0, 0.94)], "base noise", "remap result")


def ribbon_renderer(material_entry, sorting="NONE", cull_box=None):
    """Explicit RendererSetting for embedded trail/ara configs (never MISSING-pink)."""
    cull = {"_enable": B(0)} if cull_box is None else \
        {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": sorting}


# ---------------------------------------------------------------------------
# 1. eclipse:riss_maw_snap — the maw's snap-shut beat (one-shot, 18t)
# ---------------------------------------------------------------------------
def build_riss_maw_snap() -> FxBuilder:
    """IDEAS-player #4: a single-frame white-cyan HDR slice (the jaws slamming) plus 8
    outward shards that die on world contact (physics.removedWhenCollided). Spawned by
    the CUE_RISS_SCHLAG Photon leg with setDelay(a = openTicks) + allowMulti=true, so
    the snap lands exactly on the server's snap-shut damage tick. GLITCH grammar: the
    slice pops at full value with a squared-off hold — no ease-in anticipation (the
    maw's 25t in-suck IS the anticipation)."""
    fx = FxBuilder("riss_maw_snap")

    # L1 the slice: one tall thin vertical flash, 5t. Full-bright for <=2 ticks
    # (photosensitivity impact law), then a fast eased decay to the void tone.
    (fx.particle_emitter(
            "snap_slice",
            duration=18, looping=False,
            start_lifetime=constant(5), start_speed=constant(0.0),
            start_size=nf3(0.55, 3.0, 0.55),
            simulation_space="World", max_particles=1)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
       .with_shape(dot())
       .with_renderer(render_mode="VerticalBillboard")
       .with_material(texture_material(TEX_BEAM, hdr=(1.9, 2.6, 3.0)))
       .with_curves(
            size_over_lifetime=nf3(
                eased([(0.0, 1.0), (0.4, 1.0), (1.0, 0.12)]),  # pinches shut
                eased([(0.0, 1.0), (1.0, 0.85)]),
                eased([(0.0, 1.0), (0.4, 1.0), (1.0, 0.12)])),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.4, 1.0), (0.6, 0.45), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.5, *GLI_CYAN), (1.0, *SAC_VOID)]))
       .with_cull_box((-3.0, -2.0, -3.0), (3.0, 4.0, 3.0)))

    # L2 the shards: 8 hot flecks thrown outward off the closing lips; real collision,
    # removed on contact — bitten-off pieces spat against the walls of the choke point.
    (fx.particle_emitter(
            "snap_shards",
            duration=18, looping=False,
            start_lifetime=random_between(10, 16),
            start_speed=random_between(0.45, 0.85),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8), cycles=1)])
       .with_shape(sphere(radius=0.35, thickness=0.0))
       .with_physics(collision=True, removed_when_collided=True, friction=0.98,
                     collided_friction=0.6, gravity=0.35, bounce_chance=0.0)
       .with_material(texture_material(TEX_STATIC, hdr=(1.2, 1.5, 1.9),
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(
            size_over_lifetime=eased([(0.0, 1.0), (0.6, 0.85), (1.0, 0.3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.55, 0.7), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.35, *GLI_CYAN), (0.7, *SAC_VIOLET), (1.0, *GLI_DEAD)]))
       .with_cull_box((-5.0, -2.5, -5.0), (5.0, 4.0, 5.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:shadow_bolt_impact — cultist bolt detonation flower (one-shot, 16t)
# ---------------------------------------------------------------------------
def build_shadow_bolt_impact() -> FxBuilder:
    """IDEAS-mobs #6: sphere-shell burst 22 rendered in TWO passes on one emitter
    (multi-material = multi-pass): a REVERSE_SUB (ONE/ONE) pass rips a dark hole in the
    framebuffer, an ADD pass scatters hot violet shards through it — the wither-violet
    "flower". Four raycast-clipped micro-cross beams ground the hit on real geometry.
    allowMulti=true at the row: 3-bolt fans strike the same wall block within ticks."""
    fx = FxBuilder("shadow_bolt_impact")

    # L1 the flower: burst 22 on a tight shell; both passes share the emission and the
    # violet->ink lifecycle. REVERSE_SUB is order-independent vs itself, ADD too — NONE.
    (fx.particle_emitter(
            "impact_flower",
            duration=16, looping=False,
            start_lifetime=random_between(8, 12),
            start_speed=random_between(0.35, 0.7),
            start_size=nf3(random_between(0.09, 0.18), random_between(0.09, 0.18),
                           random_between(0.09, 0.18)),
            start_rotation=nf3(random_between(0, 360), random_between(0, 360),
                               random_between(0, 360)),
            simulation_space="World", max_particles=22)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(22), cycles=1)])
       .with_shape(sphere(radius=0.25, thickness=0.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_REVERSE_SUB))
       .with_material(texture_material(TEX_STATIC, hdr=(0.9, 0.4, 1.3),
                                       pixel_art=True, pixel_art_bits=4))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.55), (0.25, 1.0), (1.0, 0.75)]),
            velocity_over_lifetime=dict(
                speed_modifier=eased([(0.0, 1.0), (0.5, 0.45), (1.0, 0.15)])),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.2, 0.85), (0.75, 0.55), (1.0, 0.0)],
                [(0.0, *COR_VIOLET), (0.6, *COR_INK), (1.0, *GLI_DEAD)]))
       .with_cull_box((-3.5, -3.5, -3.5), (3.5, 3.5, 3.5)))

    # L2 micro-cross: 4 short beams clipped by the world (raycast BLOCKS) — the flash
    # visibly stops AT the wall/floor that was hit. 10t, eased width flicker.
    cross = [("cross_n", (0.0, 0.35, -2.2)), ("cross_s", (0.0, 0.35, 2.2)),
             ("cross_e", (2.2, 0.35, 0.0)), ("cross_w", (-2.2, 0.35, 0.0))]
    for name, end in cross:
        (fx.beam_emitter(
                name, duration=10, looping=False, end=end,
                width=random_curve(0.03, 0.11,
                                   [(0.0, 1.0, 0.1, 0.35, 0.5, 0.8, 1.0, 0.0)],
                                   [(0.0, 0.7, 0.15, 1.0, 0.6, 0.3, 1.0, 0.0)]),
                raycast="BLOCKS",
                color_nf=gradient(
                    [(0.0, 0.9), (0.5, 0.6), (1.0, 0.0)],
                    [(0.0, *SAC_HOT), (0.45, *COR_VIOLET), (1.0, *COR_INK)]))
           .with_material(texture_material(TEX_BEAM, hdr=(1.4, 0.8, 2.0)))
           .with_cull_box((-3.0, -1.5, -3.0), (3.0, 2.0, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:intro_sunrise_rays — sunrise god-ray ribbons (one-shot, 230t)
# ---------------------------------------------------------------------------
def build_intro_sunrise_rays() -> FxBuilder:
    """IDEAS-events #8: four physical god-ray ribbons climbing off the island rim
    toward the risen sun (+X = east), igniting one by one (delays 20/50/85/120 — the
    first with the SUNRISE_WARM_BLOOM screen fade, both on the same 20t offset), each
    carrying the exact warm-bloom gold fading through the permanent-rim violet. Slow
    heaven-bound drift with a living waver via ara physics gravity. Dies on its own at
    230t = SUNRISE_RAMP_TICKS + linger, exactly as IntroSequence.finish() runs."""
    fx = FxBuilder("intro_sunrise_rays")

    rays = [("ray_ribbon_a", 20, (12.0, 0.5, 0.0), (0.36, 0.55, 0.02)),
            ("ray_ribbon_b", 50, (0.0, 0.5, -11.0), (0.33, 0.58, -0.05)),
            ("ray_ribbon_c", 85, (-13.0, 0.5, 3.0), (0.30, 0.52, 0.08)),
            ("ray_ribbon_d", 120, (4.0, 0.5, 13.0), (0.38, 0.60, -0.03))]
    for name, delay, pos, vel in rays:
        (fx.ara_trail_emitter(
                name, duration=230, looping=False, start_delay=delay,
                space="Local", alignment="View",
                thickness=0.9, smoothness=6,
                time=2.5, time_interval=0.05,
                initial_velocity=vel,
                thickness_over_length=eased([(0.0, 1.0), (0.55, 0.7), (1.0, 0.08)]),
                color_over_time=gradient(
                    [(0.0, 0.0), (0.12, 0.85), (0.6, 0.5), (1.0, 0.0)],
                    [(0.0, *SUNRISE_GOLD), (0.55, *RIM_VIOLET), (1.0, *SAC_VOID)]),
                physics=dict(warmup=0.0, gravity=(0.0, 0.008, 0.0), inertia=0.2,
                             velocity_smoothing=0.75, damping=0.9))
           .at(*pos)
           .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.3, 1.0)))
           .with_cull_box((-18.0, -3.0, -18.0), (18.0, 42.0, 18.0)))

    # rim_motes: tiny gold sparks lifting off the rim ring for the first ~150t
    # (emission curve ramps out), lit full so they read against the brightening sky.
    (fx.particle_emitter(
            "rim_motes",
            duration=230, looping=False,
            start_lifetime=random_between(40, 60),
            start_speed=random_between(0.04, 0.1),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="Local", max_particles=64)
       .with_emission(rate=eased([(0.0, 0.5), (0.55, 0.45), (0.75, 0.0), (1.0, 0.0)]))
       .with_shape(circle(radius=12.0, thickness=0.25))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 1.1, 0.9)))
       .with_lights(sky=15, block=15)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0.02), constant(0.05),
                                                   constant(0.0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, *SAC_GOLD_PALE), (0.6, *SUNRISE_GOLD), (1.0, *SAC_VOID)]))
       .with_cull_box((-18.0, -3.0, -18.0), (18.0, 24.0, 18.0)))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:tyrant_fog_arms — P3 desperation fog-arm mesh tendrils (200t episode)
# ---------------------------------------------------------------------------
def build_tyrant_fog_arms() -> FxBuilder:
    """IDEAS-boss #10: fog particles emitted ALONG the shipped eclipse:item/fog_tendril
    claw model (mesh shape, Triangle emit). The emission volume breathes (shape scale
    0.8<->1.15) and precesses (shape rotation y 0->72°) so successive arms trace around
    the body; Noise3D writhes them. Rides the tyrant via spawnOnEntity(FORWARD) —
    Local space, the rig walks and faces with the boss. Translucent alpha-sorted fog,
    never a wall, zero bloom — fog is weather.

    WAVE-13/A5 pass (three changes, all inside this one asset):

    1. `eclipse:soft_particle` (A0 custom shader) on every fog body. The quads used to
       cut a razor edge wherever they crossed terrain or the boss walked them into a
       wall; the SceneDepth fade now dissolves them at the contact plane and at the
       camera near-plane, so P3 fog stops clipping and you can walk INTO the arms.
    2. Curve-remapped Noise3D instead of raw fBm. `NoiseSetting$Remap.remapCurve`
       (jar-default -1..1, xAxis "base noise") reshapes the noise histogram before it
       drives the offset: an S with soft plateaus makes the field HOLD a shape and then
       slew, i.e. billowing, where the linear default only jitters. Two frequencies:
       0.42 for the slab base, 1.7 for the shreds.
    3. Depth stratification (the mass law read as fog): a sluggish DARK slab base
       (34-52 t lives, big bodies, ~0.6 blk/s) with faster torn shreds ON TOP
       (12-20 t, small bodies, ~2 blk/s) plus a soft_particle GROUND BANK pooling at
       the boss's feet. Three read distances instead of one flat curtain.

    Stacking law (V2.1, learned on tyrant_step): birth tint is STM_SLATE, never the
    light FOG_TEAL — 90 alpha quads born inside one volume converge to their birth
    tint, and a light birth tint is exactly the white ball the style guide forbids.
    Speeds are Photon units: startSpeed/linear x0.05 per tick = blocks/SECOND, radial
    x0.01 per tick = 0.2 blk/s per unit (the pre-wave values sat below the perception
    floor at ~0.05 blk/s)."""
    fx = FxBuilder("boss/tyrant_fog_arms")

    cull = ((-10.0, -2.5, -10.0), (10.0, 6.5, 10.0))
    pivot = fx.empty("arm_pivot").at(0.0, 1.8, 0.0)

    # L1 arm slab: the slow, heavy body of the arms. Long lives, fat quads, low noise
    # frequency — this layer is the silhouette, so it must drift, not flicker.
    (fx.particle_emitter(
            "fog_arms",
            duration=200, looping=False,
            start_lifetime=random_between(34, 52),
            start_speed=random_between(0.4, 0.9),      # blk/s
            start_size=nf3(random_between(0.5, 0.95), random_between(0.5, 0.95),
                           random_between(0.5, 0.95)),
            simulation_space="Local", max_particles=90)
       .child_of(pivot)
       .with_emission(rate=constant(1.15))
       .with_shape(mesh(model="eclipse:item/fog_tendril", emit_from="Triangle"),
                   scale=(eased([(0.0, 0.8), (0.3, 1.15), (0.6, 0.85), (1.0, 1.1)]),
                          eased([(0.0, 0.8), (0.35, 1.1), (0.7, 0.9), (1.0, 1.15)]),
                          eased([(0.0, 0.8), (0.3, 1.15), (0.6, 0.85), (1.0, 1.1)])),
                   rotation=(constant(0.0),
                             eased([(0.0, 0.0), (1.0, 72.0)]),
                             constant(0.0)))
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": TEX_SMOKE},
            uniforms={"SoftDistance": 1.35, "NearFade": 0.9},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.55), (0.5, 1.3), (1.0, 1.8)]),
            noise=dict(frequency=0.42, quality="Noise3D",
                       position=nf3(constant(0.22), constant(0.09), constant(0.22)),
                       size=constant(0.12),
                       remap_curve=FOG_BILLOW_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.42), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.55, *FOG_TEAL), (1.0, *GLI_DEAD)]))
       .with_cull_box(*cull))

    # L2 arm shreds: short-lived rags torn off the slab and thrown outward/up, on a
    # much harsher remap (near-binary noise = the field snaps between lobes). This is
    # the layer that sells MOTION; the slab underneath sells MASS.
    (fx.particle_emitter(
            "arm_shreds",
            duration=200, looping=False,
            start_lifetime=random_between(12, 20),
            start_speed=random_between(1.6, 2.8),      # blk/s
            start_size=nf3(random_between(0.18, 0.36), random_between(0.18, 0.36),
                           random_between(0.18, 0.36)),
            simulation_space="Local", max_particles=40)
       .child_of(pivot)
       .with_emission(rate=constant(0.85))
       .with_shape(mesh(model="eclipse:item/fog_tendril", emit_from="Triangle"),
                   scale=(eased([(0.0, 1.05), (0.4, 0.85), (1.0, 1.1)]),
                          eased([(0.0, 1.0), (0.5, 1.2), (1.0, 0.9)]),
                          eased([(0.0, 1.05), (0.4, 0.85), (1.0, 1.1)])),
                   rotation=(constant(0.0),
                             eased([(0.0, 40.0), (1.0, 118.0)]),  # counter-phase to L1
                             constant(0.0)))
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": TEX_SMOKE},
            uniforms={"SoftDistance": 0.85, "NearFade": 0.55},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(0.3, 1.1), constant(0.0)),
                radial=constant(3.5)),                 # 0.7 blk/s outward drift
            size_over_lifetime=eased([(0.0, 0.4), (0.35, 1.0), (1.0, 0.45)]),
            noise=dict(frequency=1.7, quality="Noise3D",
                       position=nf3(constant(0.34), constant(0.2), constant(0.34)),
                       rotation=constant(0.6),
                       remap_curve=FOG_SHRED_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.34), (0.65, 0.26), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *FOG_TEAL), (1.0, *GLI_DEAD)]))
       .with_cull_box(*cull))

    # L3 ground bank: the fog the arms are FED from. Horizontal quads pooling at the
    # feet and creeping outward — the single biggest soft_particle win in this asset,
    # because a ground-hugging quad clips into every slope it crosses without it.
    # Anchored on the fx root (not the chest pivot) so it stays welded to the floor.
    (fx.particle_emitter(
            "ground_bank",
            duration=200, looping=False,
            start_lifetime=random_between(60, 95),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.7, 2.9), random_between(1.7, 2.9),
                           random_between(1.7, 2.9)),
            simulation_space="Local", max_particles=24)
       .at(0.0, 0.14, 0.0)
       .with_emission(rate=constant(0.32))
       .with_shape(circle(radius=2.6, thickness=0.6))
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": TEX_SMOKE},
            uniforms={"SoftDistance": 1.6, "NearFade": 0.7},
            blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(2.2)),  # 0.44 blk/s creep
            size_over_lifetime=eased([(0.0, 0.6), (0.45, 1.15), (1.0, 1.45)]),
            noise=dict(frequency=0.3, quality="Noise2D",
                       position=nf3(constant(0.16), constant(0.02), constant(0.16)),
                       remap_curve=FOG_BILLOW_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.26), (0.72, 0.2), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.6, *FOG_TEAL), (1.0, *GLI_DEAD)]))
       .with_cull_box(*cull))

    # L4 arm_motes: sparse fog flecks shed off the reaching arms and sinking — the v7
    # second-emitter depth read for a boss-tier hero effect (budget ~10 live).
    (fx.particle_emitter(
            "arm_motes",
            duration=200, looping=False,
            start_lifetime=random_between(18, 28),
            start_speed=random_between(0.2, 0.8),      # blk/s
            start_size=nf3(random_between(0.12, 0.22), random_between(0.12, 0.22),
                           random_between(0.12, 0.22)),
            simulation_space="Local", max_particles=12)
       .child_of(pivot)
       .with_emission(rate=constant(0.4))
       .with_shape(sphere(radius=2.6, thickness=0.25))
       .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": TEX_SMOKE},
            uniforms={"SoftDistance": 0.7, "NearFade": 0.45},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0.0), constant(-0.6),
                                                   constant(0.0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.32), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.6, *FOG_TEAL), (1.0, *GLI_DEAD)]))
       .with_cull_box(*cull))
    return fx


# ---------------------------------------------------------------------------
# 5. eclipse:revenant_fog_ribbons — robe hem wisps + tear-off streamers (loop, 60t)
# ---------------------------------------------------------------------------
def build_revenant_fog_ribbons() -> FxBuilder:
    """IDEAS-mobs #4: the Fog Revenant's CAMPFIRE hem smoke upgraded to lagging robe
    ribbons — a low cylinder-shell wisp emitter whose particles drag short TRAIL-type
    streamers as the noise wobble tears them off the hem. Local space (the aura follows
    the drift); attached by PhotonMobFx at eye −0.9 (hem, not eyes), nearest-4 cap."""
    fx = FxBuilder("revenant_fog_ribbons")

    wisps = (fx.particle_emitter(
            "hem_wisps",
            duration=60, looping=True, prewarm=20,
            start_lifetime=random_between(30, 40),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.26), random_between(0.14, 0.26),
                           random_between(0.14, 0.26)),
            simulation_space="Local", max_particles=64)
        .with_emission(rate=constant(0.6))
        .with_shape(cylinder(radius=0.5, thickness=0.3), scale=(1.0, 0.3, 1.0))
        .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(0.028), constant(0.0)),
                speed_modifier=eased([(0.0, 0.5), (0.6, 1.0), (1.0, 1.2)])),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.02), constant(0.06))),
            size_over_lifetime=eased([(0.0, 0.7), (0.45, 1.0), (1.0, 0.5)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (0.75, 0.28), (1.0, 0.0)],
                [(0.0, *FOG_TEAL), (0.75, *STM_SLATE), (1.0, *GLI_DEAD)]))
        .with_cull_box((-3.0, -1.5, -3.0), (3.0, 3.5, 3.0)))
    # The streamers: short plain-TRAIL strips torn off rising wisps (the "robe ribbon"
    # read — cheap segments, no ara physics on a per-mob loop).
    wisps.with_module("trails", {
        "ratio": F(0.5),
        "lifetime": constant(0.4),
        "inheritParticleColor": B(1),
        "trailType": "TRAIL",
        "config": {
            "time": I(10), "minVertexDistance": F(0.04),
            "widthOverTrail": eased([(0.0, 0.12), (1.0, 0.0)]),
            "colorOverTrail": gradient(
                [(0.0, 0.35), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *GLI_DEAD)]),
            "renderer": ribbon_renderer(
                texture_material(TEX_SMOKE, blend=BLEND_ALPHA), sorting="DISTANCE",
                cull_box=((-3.0, -1.5, -3.0), (3.0, 3.5, 3.0)))}})
    return fx


# ---------------------------------------------------------------------------
# 6. eclipse:glitch_drip — corruption drip loop on glitched mobs (loop, 40t)
# ---------------------------------------------------------------------------
def build_glitch_drip() -> FxBuilder:
    """IDEAS-mobs #5: sparse corruption dripping off the seams — chunky pixel-art
    drops falling off random body offsets (noise-displaced dot emission), accelerating
    down and shrinking out before ground contact (no physics — cheaper). Dark violet
    body with the occasional bright GLI_VIOLET frame via a random gradient pair.
    Attached by PhotonMobFx to every GlitchedMonster kind (Wanderer inherits)."""
    fx = FxBuilder("glitch_drip")

    (fx.particle_emitter(
            "drips",
            duration=40, looping=True,
            start_lifetime=constant(18),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.06, 0.11), random_between(0.06, 0.11),
                           random_between(0.06, 0.11)),
            simulation_space="Local", max_particles=24)
       .with_emission(rate=constant(0.35))
       .with_shape(dot(), position=(0.0, -0.2, 0.0))
       .with_material(texture_material(TEX_SQUARE, hdr=(0.7, 0.4, 1.0),
                                       pixel_art=True, pixel_art_bits=8))
       .with_curves(
            # The "gravity 0.25" read without the physics module: a down-ramp velocity.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(-0.16), constant(0.0)),
                speed_modifier=eased([(0.0, 0.15), (0.5, 0.7), (1.0, 1.4)])),
            noise=dict(frequency=0.3, quality="Noise3D",
                       position=nf3(constant(0.3), constant(0.12), constant(0.3))),
            size_over_lifetime=eased([(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)]),
            color_over_lifetime=random_gradient(
                # a: the common drip — dark violet holding, dying to dead-signal.
                [(0.0, 0.0), (0.15, 0.85), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, *COR_INK), (0.8, *GLI_DEAD), (1.0, *GLI_DEAD)],
                # b: the occasional bright frame — violet flash then the same fade.
                [(0.0, 0.0), (0.12, 0.95), (0.5, 0.6), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (0.55, *COR_INK), (1.0, *GLI_DEAD)]))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0)))
    return fx


# ---------------------------------------------------------------------------
# 7. eclipse:deckhand_soul_flame — hood soul-candle (loop, 40t) + rise flare
# ---------------------------------------------------------------------------
def build_deckhand_soul_flame() -> FxBuilder:
    """IDEAS-mobs below-the-cut: a small quiet soul-flame above each rower's hood — 8
    candles rowing in the dark. Tight cone flame licks (StretchedBillboard 0.6) on the
    soul-blue gradient, lights {blockLight 13} fake glow so the flame reads in limbo's
    dark, faint HDR only on the flame body (low boost — limbo must not blow out), plus
    a 1-quad wick glow bed. PhotonMobFx attaches at eye +0.55 (hood crown)."""
    fx = FxBuilder("deckhand_soul_flame")

    (fx.particle_emitter(
            "flame",
            duration=40, looping=True,
            start_lifetime=random_between(10, 14),
            start_speed=random_between(0.03, 0.06),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="Local", max_particles=14)
       .with_emission(rate=constant(1.2))
       .with_shape(cone(angle=8.0, radius=0.06))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6,
                      length_scale=1.6)
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.5, 0.9, 1.4)))
       .with_lights(sky=0, block=13)
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.6), (0.35, 1.0), (1.0, 0.15)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.65, 0.6), (1.0, 0.0)],
                [(0.0, *SOUL_BLUE), (0.7, *SOUL_DEEP), (1.0, *SAC_VOID)]))
       .with_cull_box((-0.6, -0.5, -0.6), (0.6, 1.0, 0.6)))

    # wick_glow: one soft slow-breathing halo at the flame base — the candle's "bed".
    (fx.particle_emitter(
            "wick_glow",
            duration=40, looping=True,
            start_lifetime=constant(38), start_speed=constant(0.0),
            start_size=nf3(0.14), simulation_space="Local", max_particles=2)
       .with_emission(rate=constant(0.03))
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.4, 0.7, 1.1)))
       .with_lights(sky=0, block=13)
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.7), (0.5, 1.0), (1.0, 0.7)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, *SOUL_BLUE), (1.0, *SOUL_DEEP)]))
       .with_cull_box((-0.6, -0.5, -0.6), (0.6, 1.0, 0.6)))
    return fx


def build_deckhand_soul_flare() -> FxBuilder:
    """The `rise` variant — the candles gutter-and-FLARE when riseHostile turns the
    crew. Fired once per rower on the isHostile() rising edge (PhotonMobFx edge lane,
    sentinel_alert pattern): a 15t 3x-emission cone flare + one bright wink. Kept as
    its own tiny one-shot because an attached loop cannot re-trigger an in-file burst
    on a synced-state edge (executors spawn once)."""
    fx = FxBuilder("deckhand_soul_flare")

    (fx.particle_emitter(
            "flare_licks",
            duration=15, looping=False,
            start_lifetime=random_between(8, 12),
            start_speed=random_between(0.08, 0.14),
            start_size=nf3(random_between(0.06, 0.11), random_between(0.06, 0.11),
                           random_between(0.06, 0.11)),
            simulation_space="Local", max_particles=12)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(4), cycles=3, interval=4)])
       .with_shape(cone(angle=14.0, radius=0.08))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6,
                      length_scale=1.6)
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.7, 1.1, 1.7)))
       .with_lights(sky=0, block=15)
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.7), (0.3, 1.0), (1.0, 0.2)]),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.55, 0.6), (1.0, 0.0)],
                [(0.0, *SAC_HOT), (0.35, *SOUL_BLUE), (1.0, *SOUL_DEEP)]))
       .with_cull_box((-0.8, -0.5, -0.8), (0.8, 1.2, 0.8)))

    # The wink: one 4t bright pop at the wick — "the crew just turned".
    (fx.particle_emitter(
            "flare_wink",
            duration=15, looping=False,
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(0.22), simulation_space="Local", max_particles=1)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 1.5, 2.1)))
       .with_curves(
            size_over_lifetime=eased([(0.0, 1.0), (0.4, 0.8), (1.0, 0.2)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.5), (1.0, 0.0)],
                [(0.0, *GLI_WHITE), (0.6, *SOUL_BLUE), (1.0, *SOUL_DEEP)]))
       .with_cull_box((-0.8, -0.5, -0.8), (0.8, 1.2, 0.8)))
    return fx


# ---------------------------------------------------------------------------
# 8. eclipse:intro_storm_wall — vortex wall lightning (WINDOWED loop, r=22 h=48)
# ---------------------------------------------------------------------------
def build_intro_storm_wall() -> FxBuilder:
    """IDEAS-events #7: ONE looping storm-wall effect for the whole LIGHTNING phase —
    crawling arcs and short-lived beams INSIDE the smoke wall, making the vortex itself
    electric between the Quasar strikes. Authored at the intro vortex's real dimensions
    (r=22, h=48; spawnLoop carries no scale knob and the intro vortex is the only
    TYPE_VORTEX sender). Beams sputter on independent random re-trigger clocks and clip
    against the (hidden-in-smoke) altar/terrain via raycast BLOCKS."""
    fx = FxBuilder("intro_storm_wall")

    # wall_arcs ×3: each chords across the cylinder wall from a different base point;
    # emitRate = random re-trigger interval (sputtering, never synchronized).
    arcs = [("wall_arc_a", (18.0, 3.0, -6.0), (-27.0, 22.0, 14.0)),
            ("wall_arc_b", (-15.0, 8.0, 13.0), (24.0, 18.0, -20.0)),
            ("wall_arc_c", (-4.0, 2.0, -20.0), (16.0, 26.0, 28.0))]
    for name, base, end in arcs:
        (fx.beam_emitter(
                name, duration=40, looping=True,
                end=end, emit_rate=random_between(20, 40),
                width=random_curve(0.08, 0.22,
                                   [(0.0, 1.0, 0.1, 0.4, 0.5, 0.75, 1.0, 0.0)],
                                   [(0.0, 0.6, 0.2, 1.0, 0.55, 0.25, 1.0, 0.0)]),
                raycast="BLOCKS",
                color_nf=gradient(
                    [(0.0, 0.95), (0.35, 0.75), (0.7, 0.4), (1.0, 0.0)],
                    [(0.0, *SAC_HOT), (0.4, *SAC_VIOLET), (1.0, *SAC_DEEP)]))
           .at(*base)
           .with_material(texture_material(TEX_NOISE_STRIP, hdr=(1.8, 1.4, 2.4)))
           .with_uv_animation(tiles=(4, 1), animation="WholeSheet",
                              frame_over_time=curve(0.0, 4.0,
                                                    [(0.0, 0.0, 0.33, 0.33,
                                                      0.66, 0.66, 1.0, 1.0)]))
           .with_cull_box((-26.0, -4.0, -26.0), (26.0, 52.0, 26.0)))

    # wall_glow: soft violet embers whose emission point ORBITS the wall (arcMode Loop)
    # while each ember drifts up it — the wall breathes light between the arcs.
    (fx.particle_emitter(
            "wall_glow",
            duration=60, looping=True, prewarm=30,
            start_lifetime=random_between(30, 50),
            start_speed=constant(0.02),
            start_size=nf3(random_between(0.16, 0.32), random_between(0.16, 0.32),
                           random_between(0.16, 0.32)),
            simulation_space="Local", max_particles=96)
       .with_emission(rate=constant(1.2))
       .with_shape(cylinder(radius=22.0, thickness=0.1, arc_mode="Loop", arc_speed=0.7),
                   scale=(1.0, 3.0, 1.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 0.9, 1.5)))
       .with_lights(sky=12, block=15)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(0.16), constant(0.0)),
                speed_modifier=eased([(0.0, 0.6), (0.5, 1.0), (1.0, 0.8)])),
            size_over_lifetime=eased([(0.0, 0.6), (0.4, 1.0), (1.0, 0.4)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (1.0, *SAC_DEEP)]))
       .with_cull_box((-26.0, -4.0, -26.0), (26.0, 52.0, 26.0)))

    # zenith_bloom: one faint pulsing HDR disc at +52 — the underlit eclipse "eye".
    (fx.particle_emitter(
            "zenith_bloom",
            duration=80, looping=True,
            start_lifetime=constant(78), start_speed=constant(0.0),
            start_size=nf3(7.0), simulation_space="Local", max_particles=2)
       .with_emission(rate=constant(0.0125))
       .with_shape(dot(), position=(0.0, 52.0, 0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.6, 1.2, 2.0)))
       .with_curves(
            size_over_lifetime=eased([(0.0, 0.85), (0.3, 1.0), (0.6, 0.9),
                                      (0.85, 1.0), (1.0, 0.85)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.3), (0.5, 0.22), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, *SAC_VIOLET), (1.0, *SAC_DEEP)]))
       .with_cull_box((-10.0, 44.0, -10.0), (10.0, 60.0, 10.0)))
    return fx


# ---------------------------------------------------------------------------
# 9. eclipse:credits_contrail — flyover debris contrail (entity loop)
# ---------------------------------------------------------------------------
def build_credits_contrail() -> FxBuilder:
    """IDEAS-events #9b: one crisp thin ribbon per credits flyer — the debris field
    becomes a meteor shower over the runners. World-space ara follows the executor's
    per-frame eye anchor; no physics lag (inertia 0) — crisp streaks, deliberately
    distinct from the supply drop's wobbling plasma. Attached to the first 8 nearest
    moving BlockDisplays by CreditsContrailFx; flyer discard auto-destroys it."""
    fx = FxBuilder("credits_contrail")

    (fx.ara_trail_emitter(
            "contrail",
            duration=100, looping=True,
            space="World", alignment="View",
            thickness=0.25, smoothness=3,
            time=0.9, time_interval=0.05,
            thickness_over_length=eased([(0.0, 1.0), (0.6, 0.55), (1.0, 0.05)]),
            color_over_time=gradient(
                [(0.0, 0.85), (0.5, 0.55), (1.0, 0.0)],
                [(0.0, *SAC_GOLD_PALE), (0.55, *RIM_VIOLET), (1.0, *SAC_VOID)]),
            physics=dict(warmup=0.0, gravity=(0.0, 0.0, 0.0), inertia=0.0,
                         velocity_smoothing=0.75, damping=0.75))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.4, 1.2, 1.0)))
       .with_cull_box((-14.0, -14.0, -14.0), (14.0, 14.0, 14.0)))
    return fx


# ---------------------------------------------------------------------------
# 10. eclipse:end_crack_bleed — dragon-death crack light-bleed (one-shot, 36t)
# ---------------------------------------------------------------------------
def build_end_crack_bleed() -> FxBuilder:
    """IDEAS-world #6a Option B: violet light racing UP out of a future seam — three
    slightly splayed HDR bleed shafts flickering out of the fissure plus a burst of
    embers off a seam-aligned edge strip. One per crack-race step (4t apart at
    different seams — dedup a non-issue). Bloom columns, additive."""
    fx = FxBuilder("end_crack_bleed")

    root = fx.empty("bleed_root")

    shafts = [("bleed_shaft_a", (1.5, 26.0, 1.5)),
              ("bleed_shaft_b", (-1.5, 26.0, -1.2)),
              ("bleed_shaft_c", (0.3, 26.0, -1.8))]
    for name, end in shafts:
        (fx.beam_emitter(
                name, duration=36, looping=False, end=end,
                width=random_curve(0.5, 1.1,
                                   [(0.0, 0.7, 0.12, 1.0, 0.6, 0.55, 1.0, 0.0)],
                                   [(0.0, 1.0, 0.2, 0.5, 0.55, 0.9, 1.0, 0.0)]),
                raycast="NONE",
                color_nf=gradient(
                    [(0.0, 0.95), (0.4, 0.7), (0.75, 0.35), (1.0, 0.0)],
                    [(0.0, *BLEED_PALE), (0.6, *BLEED_VIOLET), (1.0, *SAC_VOID)]))
           .child_of(root)
           .with_material(texture_material(TEX_BEAM, hdr=(2.2, 1.5, 3.0)))
           .with_cull_box((-4.0, -1.0, -4.0), (4.0, 30.0, 4.0)))

    # fissure_embers: 30 violet embers off the seam strip (box Edge, 6×0.2×1.2),
    # riding fast up the shafts, easing out with a whisper of gravity.
    (fx.particle_emitter(
            "fissure_embers",
            duration=36, looping=False,
            start_lifetime=random_between(20, 35),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            simulation_space="World", max_particles=34)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30), cycles=1)])
       .with_shape(box(emit_from="Edge"), scale=(6.0, 0.2, 1.2))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.3, 1.0, 1.8)))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(0.4, 0.9), constant(0.0)),
                speed_modifier=eased([(0.0, 1.0), (0.55, 0.7), (1.0, 0.35)])),
            force_over_lifetime=dict(force=(0.0, -0.015, 0.0), simulation_space="World"),
            size_over_lifetime=eased([(0.0, 1.0), (0.7, 0.75), (1.0, 0.2)]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.6, 0.55), (1.0, 0.0)],
                [(0.0, *BLEED_PALE), (0.5, *BLEED_VIOLET), (1.0, *SAC_VOID)]))
       .with_cull_box((-5.0, -1.0, -5.0), (5.0, 30.0, 5.0)))
    return fx


# ---------------------------------------------------------------------------
# 11. eclipse:wizard_hearth — observatory chimney + window ambience (WINDOWED loop)
# ---------------------------------------------------------------------------
def build_wizard_hearth() -> FxBuilder:
    """IDEAS-world #10: cozy-scale charm — gusty hearth sparks curling out of the dome
    seam vent, one thin smoke wisp rising off it, warm dust motes hanging in the
    lantern light inside. Anchored by ObservatoryAmbience at the hut ground center
    (y0), so the offsets below are authored against WizardObservatory.buildAt geometry
    (dome seam ~y0+6.5, interior band y0+1..3). The spec's standalone static
    trail_emitter cannot render (no movement -> no vertices; trail emitters also have
    no shape block to animate), so the wisp is ONE slow carrier particle dragging a
    TRAIL ribbon — the same single-thin-strip read, still the cheapest ribbon here."""
    fx = FxBuilder("wizard_hearth")

    # chimney_sparks: gusty embers out of the dome seam vent. Emission rate is a
    # two-hump curve over the emitter cycle — gusts, not a metronome.
    (fx.particle_emitter(
            "chimney_sparks",
            duration=90, looping=True,
            start_lifetime=random_between(24, 40),
            start_speed=random_between(0.08, 0.18),
            start_size=nf3(random_between(0.04, 0.09), random_between(0.04, 0.09),
                           random_between(0.04, 0.09)),
            simulation_space="World", max_particles=40)
       .at(1.5, 6.5, -1.0)
       .with_emission(rate=eased([(0.0, 0.15), (0.2, 1.2), (0.4, 0.25),
                                  (0.65, 0.9), (0.85, 0.3), (1.0, 0.15)]))
       .with_shape(cone(angle=12.0, radius=0.15))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 0.8, 0.3)))
       .with_lights(sky=0, block=15)
       .with_curves(
            noise=dict(frequency=0.9, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05))),
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-0.02, 0.02), constant(0.06),
                           random_between(-0.02, 0.02))),
            size_over_lifetime=eased([(0.0, 1.0), (0.6, 0.8), (1.0, 0.25)]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.5, 0.7), (1.0, 0.0)],
                [(0.0, *HEARTH_GOLD), (0.55, *HEARTH_EMBER), (1.0, *SAC_VOID)]))
       .with_cull_box((-3.0, -1.5, -3.0), (3.0, 6.0, 3.0)))

    # smoke_wisp: ONE slow rising carrier dragging a thin TRAIL strip — the chimney's
    # single lazy smoke ribbon, swaying on low-frequency noise.
    wisp = (fx.particle_emitter(
            "smoke_wisp",
            duration=90, looping=True,
            start_lifetime=constant(80), start_speed=constant(0.0),
            start_size=nf3(0.09), simulation_space="World", max_particles=2)
        .at(1.5, 6.7, -1.0)
        .with_emission(rate=constant(0.022))
        .with_shape(dot())
        .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.005), constant(0.05), constant(0.0)),
                speed_modifier=eased([(0.0, 0.6), (0.5, 1.0), (1.0, 0.85)])),
            noise=dict(frequency=0.25, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.01), constant(0.05))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.3), (0.8, 0.2), (1.0, 0.0)],
                [(0.0, *SMOKE_DARK), (1.0, *SMOKE_DARK)]))
        .with_cull_box((-3.0, -1.5, -3.0), (3.0, 7.0, 3.0)))
    wisp.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.45),
        "inheritParticleColor": B(0),
        "colorOverLifetime": gradient([(0.0, 0.35), (1.0, 0.0)],
                                      [(0.0, *SMOKE_DARK)]),
        "trailType": "TRAIL",
        "config": {
            "time": I(30), "minVertexDistance": F(0.05),
            "smoothInterpolation": B(1),
            "widthOverTrail": eased([(0.0, 0.25), (0.7, 0.14), (1.0, 0.05)]),
            "colorOverTrail": gradient(
                [(0.0, 0.35), (1.0, 0.0)],
                [(0.0, *SMOKE_DARK), (1.0, *SMOKE_DARK)]),
            "renderer": ribbon_renderer(
                texture_material(TEX_SMOKE, blend=BLEND_ALPHA), sorting="DISTANCE",
                cull_box=((-3.0, -1.5, -3.0), (3.0, 7.0, 3.0)))}})

    # window_motes: warm dust hanging in the lantern light inside the hut, visible
    # through the portholes at night. Noise drift only; faint additive + forced light.
    (fx.particle_emitter(
            "window_motes",
            duration=120, looping=True,
            start_lifetime=random_between(60, 100),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.02, 0.05), random_between(0.02, 0.05),
                           random_between(0.02, 0.05)),
            simulation_space="World", max_particles=50)
       .at(0.0, 1.5, 0.0)
       .with_emission(rate=constant(0.5))
       .with_shape(box(emit_from="Volume"), scale=(3.4, 1.6, 3.4))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.6, 0.5, 0.3)))
       .with_lights(sky=0, block=15)
       .with_curves(
            noise=dict(frequency=0.4, quality="Noise3D",
                       position=nf3(constant(0.02), constant(0.015), constant(0.02))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.35), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, *MOTE_WARM), (1.0, *HEARTH_GOLD)]))
       .with_cull_box((-7.0, -2.0, -7.0), (7.0, 9.0, 7.0)))
    return fx


# ---------------------------------------------------------------------------
# 12. eclipse:era_dust_motes — CRT era dust (WINDOWED player loop, GPU-instanced)
# ---------------------------------------------------------------------------
def build_era_dust_motes() -> FxBuilder:
    """IDEAS-events #10 (law verified — INTEGRATION.md §4 amendment): chunky pixel
    dust hanging in the CRT light cone around the local player inside the xbox
    tutorial dims, plus subliminal single-frame dead-pixel blinks. GPU-instanced +
    parallel (no physics, no level access — parallel-safe), Local space so the volume
    travels with the player like air. ~1% of the 10^4 instancing headroom by design."""
    fx = FxBuilder("era_dust_motes")

    (fx.particle_emitter(
            "motes",
            duration=80, looping=True, prewarm=40,
            start_lifetime=random_between(100, 160),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.03, 0.07), random_between(0.03, 0.07),
                           random_between(0.03, 0.07)),
            # 240 + dead_pixels' 4 = 244: the whole ASSET stays under the amendment's
            # 256 ceiling (steady state is ~156 live at 1.2/t × ~130t anyway).
            simulation_space="Local", max_particles=240,
            parallel_update=True, parallel_rendering=True)
       .with_emission(rate=constant(1.2))
       .with_shape(box(emit_from="Volume"), scale=(24.0, 12.0, 24.0))
       .with_material(texture_material(TEX_SQUARE, blend=BLEND_ALPHA,
                                       pixel_art=True, pixel_art_bits=8))
       .with_renderer(use_gpu_instance=True, shade=True, vertex_sorting="DISTANCE")
       .with_curves(
            noise=dict(frequency=0.4, quality="Noise3D",
                       position=nf3(constant(0.03), constant(0.02), constant(0.03))),
            size_over_lifetime=eased([(0.0, 0.7), (0.4, 1.0), (1.0, 0.7)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.35), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *ERA_AMBER), (0.5, *ERA_CREAM), (1.0, *ERA_SHADOW)]))
       .with_cull_box((-16.0, -8.0, -16.0), (16.0, 8.0, 16.0)))

    # dead_pixels: a 2-tick fullbright green/magenta pixel every ~20s somewhere in the
    # volume — subliminal, the one deliberate CRT defect.
    (fx.particle_emitter(
            "dead_pixels",
            duration=80, looping=True,
            start_lifetime=constant(2), start_speed=constant(0.0),
            start_size=nf3(random_between(0.06, 0.1), random_between(0.06, 0.1),
                           random_between(0.06, 0.1)),
            simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.05))
       .with_shape(box(emit_from="Volume"), scale=(20.0, 10.0, 20.0))
       .with_material(texture_material(TEX_SQUARE, hdr=(1.2, 1.2, 1.2),
                                       pixel_art=True, pixel_art_bits=4))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=random_gradient(
            [(0.0, 0.9), (0.6, 0.9), (1.0, 0.0)],
            [(0.0, 0.0, 1.0, 0.4), (1.0, 0.0, 1.0, 0.4)],       # CRT defect green
            [(0.0, 0.9), (0.6, 0.9), (1.0, 0.0)],
            [(0.0, 1.0, 0.31, 0.847), (1.0, 1.0, 0.31, 0.847)]))  # GLI_MAGENTA
       .with_cull_box((-16.0, -8.0, -16.0), (16.0, 8.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "riss_maw_snap.fx": build_riss_maw_snap,
    "shadow_bolt_impact.fx": build_shadow_bolt_impact,
    "intro_sunrise_rays.fx": build_intro_sunrise_rays,
    "boss/tyrant_fog_arms.fx": build_tyrant_fog_arms,
    "revenant_fog_ribbons.fx": build_revenant_fog_ribbons,
    "glitch_drip.fx": build_glitch_drip,
    "deckhand_soul_flame.fx": build_deckhand_soul_flame,
    "deckhand_soul_flare.fx": build_deckhand_soul_flare,
    "intro_storm_wall.fx": build_intro_storm_wall,
    "credits_contrail.fx": build_credits_contrail,
    "end_crack_bleed.fx": build_end_crack_bleed,
    "wizard_hearth.fx": build_wizard_hearth,
    "era_dust_motes.fx": build_era_dust_motes,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip-validates
        proj_len = builder.write_fxproj(path.with_suffix(".fxproj"))
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B, "
                  f"fxproj {proj_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
