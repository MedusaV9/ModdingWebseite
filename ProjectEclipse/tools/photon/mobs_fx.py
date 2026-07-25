#!/usr/bin/env python3
"""mobs_fx — PH-MOBS generator: custom-mob + celebration Photon `.fx` assets.

Authors (via fxlib, see tools/photon/README.md) the IDEAS-mobs.md concepts owned by
worker PH-MOBS (docs/plans_v3/plans_v5/photon/IDEAS-mobs.md #1, #3, #4 hound half, #5 pop,
#6 ribbon, #7, #8, #9, #10 — #2 offering ribbon is PH-ALTAR's):

    eclipse:boss_intro_shockwave     (#1  name-lock ground ring + dust + crack beams)
    eclipse:award_star_shower        (#3  model-particle star rain w/ collision bounce)
    eclipse:award_star_glint         (#3  Collision sub-emitter child)
    eclipse:sentinel_alert           (#7  freeze camera-flash petal puff, one-shot)
    eclipse:sentinel_petal_orbit     (#7  frozen-statue petal halo, loop)
    eclipse:gazer_gaze_beam          (#9  raycast gaze thread + hypnosis rings, loop)
    eclipse:glitch_pop               (#5  REVERSE_SUB+ADD datamosh blink pop)
    eclipse:shadow_bolt_ribbon       (#6  projectile ara ribbon + wither motes, loop)
    eclipse:hound_lunge_windup       (#4  20t collapsing spiral telegraph + release pop)
    eclipse:hound_dash_trail         (#4  bare ara ribbon laid along the dash)
    eclipse:other_dread_aura         (#8  light-eating REVERSE_SUB shroud, loop)
    eclipse:wanderer_static_shroud   (#10 shade:1b flicker-synced paint haze, loop)

Plus the deterministic textures (safe to re-run; static_4x4 is the shared #5/#10
flipbook the IDEAS-mobs delta table calls for):

    assets/eclipse/textures/particle/static_4x4.png  (4x4 white-noise flipbook frames)
    assets/eclipse/textures/particle/square_4x4.png  (4x4 identical soft squares — the
        glitch_pop REVERSE_SUB pass shares the emitter uvAnimation, so its texture must
        tile the same grid)
    assets/eclipse/textures/particle/petal_soft.png  (single soft petal, tinted at runtime)

This script IS the authoring source for these binary .fx blobs (fxlib generator in place
of an editor .fxproj). Run: python3 tools/photon/mobs_fx.py
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT, SEG_LINEAR_DOWN, SEG_LINEAR_UP,
    FxBuilder, blend, block_atlas_material, box, burst, circle, cone, constant, curve,
    cylinder, dot, function_shape, gradient, mesh, nf3, random_between, random_color,
    sphere, sub_emitter, texture_material, validate_file,
)

TEXTURE_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle"
CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING = "photon:textures/particle/ring.png"
BEAM_CORE = "eclipse:textures/particle/beam_core.png"  # shared, authored by boss_b_fx.py
STATIC_4X4 = "eclipse:textures/particle/static_4x4.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"
PETAL = "eclipse:textures/particle/petal_soft.png"

# The IDEAS-mobs #5 two-pass law: pass 1 rips light out of the framebuffer (dst - src,
# factors ONE/ONE per the spec) — works with bloom off, no dark-bloom dependency.
BLEND_REVERSE_SUB = blend("ONE", "ONE", "ONE", "ZERO", "REVERSE_SUB")

# Rise-then-fall bezier pair (0 -> 1 -> 0 across the axis) for breathing curves.
SEGS_BREATHE = [(0.0, 0.0, 0.17, 0.6, 0.33, 1.0, 0.5, 1.0),
                (0.5, 1.0, 0.67, 1.0, 0.83, 0.6, 1.0, 0.0)]


# ---------------------------------------------------------------------------
# Concept #1 — eclipse:boss_intro_shockwave (one-shot, spawned with setDelay(decodeEnd))
# ---------------------------------------------------------------------------
def build_boss_intro_shockwave() -> FxBuilder:
    """The instant the intro card locks the boss name: bloom-crested particle ring
    expanding from the summon point, world-lit dust grounding it, and 4 raycast-clipped
    crack-glow beams bleeding along the ground seams."""
    fx = FxBuilder("boss_intro_shockwave")
    cull = ((-6.0, -2.0, -6.0), (6.0, 4.0, 6.0))

    # The particles ARE the ring: circle-shell burst launched radially at 2.2 b/t.
    (fx.particle_emitter(
            "ring",
            duration=30, looping=False, max_particles=96,
            start_lifetime=random_between(16, 22), start_speed=constant(2.2),
            start_size=nf3(random_between(0.14, 0.24), random_between(0.14, 0.24),
                           random_between(0.14, 0.24)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(90))])
       .with_shape(circle(radius=0.4, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(CIRCLE, hdr=(1.6, 1.2, 2.4), blend=BLEND_ADDITIVE))
       .with_lights()
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_LINEAR_DOWN], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.85), (1.0, 0.0)],
                [(0.0, 0.95, 0.9, 1.0), (1.0, 0.6, 0.4, 0.95)])))

    # World-lit dust kick that grounds the bloom flash (shade samples the lightmap).
    (fx.particle_emitter(
            "dust_kick",
            duration=30, looping=False, max_particles=32,
            start_lifetime=random_between(18, 26), start_speed=random_between(0.15, 0.4),
            start_size=nf3(random_between(0.25, 0.45), random_between(0.25, 0.45),
                           random_between(0.25, 0.45)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(cone(angle=30.0, radius=0.6))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_physics(collision=False, gravity=0.12, bounce_chance=0.0)
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(1.0, 1.8, [SEG_LINEAR_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, 0.65, 0.6, 0.7), (1.0, 0.45, 0.4, 0.55)])))

    # Light bleeding along the ground cracks: 4 short radial beams, clipped by terrain.
    pivot = fx.empty("crack_pivot")
    for i in range(4):
        ang = math.radians(90.0 * i)
        end = (2.5 * math.sin(ang), -0.35, -2.5 * math.cos(ang))
        (fx.beam_emitter(
                f"crack_glow_{i}",
                end=end, width=0.12, duration=12, looping=False, emit_rate=0,
                raycast="BLOCKS", raycast_block_mode="VISUAL", raycast_fluid_mode="NONE",
                color_nf=gradient([(0.0, 0.9), (1.0, 0.0)],
                                  [(0.0, 0.85, 0.7, 1.0), (1.0, 0.5, 0.3, 0.9)]))
           .child_of(pivot)
           .with_material(texture_material(BEAM_CORE, hdr=(1.5, 1.1, 2.2),
                                           blend=BLEND_ADDITIVE))
           .with_cull_box((-3.0, -1.5, -3.0), (3.0, 1.5, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept #3 — eclipse:award_star_shower (+ award_star_glint Collision child)
# ---------------------------------------------------------------------------
def build_award_star_shower() -> FxBuilder:
    """Podium moment: spinning nether-star MODEL particles rain from +5, bounce off the
    real floor (the one collision-physics concept in the batch) and glint on impact."""
    fx = FxBuilder("award_star_shower")
    cull = ((-5.0, -1.0, -5.0), (5.0, 7.0, 5.0))

    # renderMode Model renders each particle as the mesh shape's baked model; the shape
    # scale (3, 0.5, 3) spreads emission points like the spec's 3x0.5x3 drop box.
    (fx.particle_emitter(
            "star_fall",
            duration=50, looping=False, max_particles=64,
            start_lifetime=random_between(30, 45), start_speed=constant(0.05),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            start_rotation=nf3(constant(0), random_between(0.0, 360.0),
                               random_between(0.0, 360.0)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[
            burst(time=0, count=constant(14)),
            burst(time=6, count=constant(14)),
            burst(time=12, count=constant(14))])
       .with_shape(mesh(model="item/nether_star", emit_from="Triangle"),
                   position=nf3(0.0, 5.0, 0.0), scale=nf3(3.0, 0.5, 3.0))
       # block_atlas + useBlockUV: each particle IS the baked nether-star model with its
       # real sprite (the HDR celebration light rides the glint sub-emitter instead).
       .with_material(block_atlas_material(blend=BLEND_ALPHA))
       .with_renderer(render_mode="Model", use_block_uv=True)
       .with_lights()
       .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                     collided_friction=0.6, gravity=0.5, bounce_chance=0.85,
                     bounce_rate=0.45, bounce_spread=0.15)
       .with_sub_emitters(sub_emitter("eclipse:award_star_glint",
                                      event="Collision", probability=0.5))
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=constant(14.0),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.85, 0.95), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 0.75), (1.0, 0.95, 0.8, 0.45)])))

    # Soft additive gold veil around the winner (no physics; pure celebration light).
    (fx.particle_emitter(
            "gold_haze",
            duration=50, looping=False, max_particles=24,
            start_lifetime=random_between(28, 40), start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.35, 0.6), random_between(0.35, 0.6),
                           random_between(0.35, 0.6)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=1.1, thickness=0.4))
       .at(0.0, 1.2, 0.0)
       .with_material(texture_material(CIRCLE, hdr=(1.1, 0.95, 0.5), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.02), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.85, 0.45), (1.0, 0.85, 0.6, 0.25)])))
    return fx


def build_award_star_glint() -> FxBuilder:
    """Collision sub-emitter child: a 4-particle HDR micro-spark at every star bounce."""
    fx = FxBuilder("award_star_glint")
    (fx.particle_emitter(
            "glint",
            duration=10, looping=False, max_particles=8,
            start_lifetime=random_between(4, 7), start_speed=random_between(0.05, 0.18),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(sphere(radius=0.08))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.5, 0.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-1.0, -1.0, -1.0), (1.0, 1.0, 1.0))
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_LINEAR_DOWN], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 0.95, 0.7)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #7 — eclipse:sentinel_alert + eclipse:sentinel_petal_orbit
# (anchored by PhotonMobFx at body center: entity eye - 0.9)
# ---------------------------------------------------------------------------
def build_sentinel_alert() -> FxBuilder:
    """DATA_FROZEN rising edge: a petal-flash cracks off the statue + one mid-bright HDR
    wink at the chest — the 'caught you looking' camera flash."""
    fx = FxBuilder("sentinel_alert")
    cull = ((-2.0, -1.5, -2.0), (2.0, 2.0, 2.0))

    (fx.particle_emitter(
            "petal_puff",
            duration=10, looping=False, max_particles=24,
            start_lifetime=random_between(6, 10), start_speed=random_between(0.3, 0.55),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=random_color(0xFFFFFFFF, 0xFFF3C4D8),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
       .with_shape(sphere(radius=0.45, thickness=0.25), scale=nf3(1.0, 2.2, 1.0))
       .with_material(texture_material(PETAL, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            rotation_over_lifetime=random_between(-30.0, 30.0),
            color_over_lifetime=gradient([(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))

    # Single chest-height HDR wink (mid-bright: a flash, not a flare).
    (fx.particle_emitter(
            "wink",
            duration=10, looping=False, max_particles=2,
            start_lifetime=constant(6), start_speed=constant(0),
            start_size=nf3(0.5, 0.5, 0.5), simulation_space="World")
       .at(0.0, 0.35, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.0, 0.9), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_LINEAR_DOWN], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 0.95, 0.9)])))
    return fx


def build_sentinel_petal_orbit() -> FxBuilder:
    """WINDOWED loop while frozen: a slow halo of pale petals orbits the statue, lit by a
    forced lightmap so they read at night without bloom. destroy(false) on thaw."""
    fx = FxBuilder("sentinel_petal_orbit")
    (fx.particle_emitter(
            "petal_halo",
            duration=80, looping=True, prewarm=30, max_particles=48,
            start_lifetime=random_between(50, 70), start_speed=constant(0.02),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=random_color(0xFFFFFFFF, 0xFFEFBFD4),
            simulation_space="Local")
       .with_emission(rate=constant(0.55))
       .with_shape(cylinder(radius=1.1, thickness=0.0, arc_mode="Loop", arc_speed=0.4),
                   scale=nf3(1.0, 1.8, 1.0))
       .with_material(texture_material(PETAL, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_lights(sky=15, block=10)
       .with_cull_box((-2.5, -1.8, -2.5), (2.5, 3.0, 2.5))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0), constant(0.5), constant(0)),
                orbital_mode="AngularVelocity"),
            rotation_over_lifetime=random_between(-8.0, 8.0),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.95, 0.85, 0.92)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #9 — eclipse:gazer_gaze_beam (loop; AutoRotate.LOOK aims local -Z)
# ---------------------------------------------------------------------------
def build_gazer_gaze_beam() -> FxBuilder:
    """Almost-subliminal gaze thread (raycast-terminated on the first block/entity in the
    stare line) + two counter-rotating hypnosis rings around the hood."""
    fx = FxBuilder("gazer_gaze_beam")
    cull_beam = ((-1.0, -1.5, -15.0), (1.0, 1.5, 1.0))

    thread = fx.beam_emitter(
        "gaze_thread",
        end=(0.0, 0.0, -14.0), width=0.035, duration=60, looping=True, emit_rate=0,
        raycast="BLOCKS_AND_ENTITIES", raycast_block_mode="VISUAL",
        raycast_fluid_mode="NONE",
        # Brighter at the gazer end, fading to nothing toward the watched player: a
        # thread you *sense*, not a laser (design caution in IDEAS-mobs #9).
        color_nf=gradient([(0.0, 0.32), (0.6, 0.12), (1.0, 0.0)],
                          [(0.0, 0.5, 0.35, 0.65), (1.0, 0.3, 0.2, 0.45)]))
    (thread.with_material(texture_material(BEAM_CORE, blend=BLEND_ADDITIVE))
           .with_uv_animation(tiles=(1, 4), animation="SingleRow",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]), cycle=2.0)
           .with_cull_box(*cull_beam))

    for name, arc_speed in (("hypnosis_ring", 0.6), ("hypnosis_ring_counter", -0.6)):
        (fx.particle_emitter(
                name,
                duration=60, looping=True, prewarm=20, max_particles=12,
                start_lifetime=constant(20), start_speed=constant(0.01),
                start_size=nf3(0.05, 0.05, 0.05), simulation_space="Local")
           .with_emission(rate=constant(0.5))
           .with_shape(circle(radius=0.45, thickness=0.0, arc_mode="Loop",
                              arc_speed=arc_speed))
           .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
           # The ring plane faces along the gaze (-Z): emitter-transform XY billboard.
           .with_renderer(facing_mode="EMITTER_TRANSFORM_XY", vertex_sorting="DISTANCE")
           .with_cull_box((-1.0, -1.0, -1.0), (1.0, 1.0, 1.0))
           .with_curves(
                rotation_over_lifetime=random_between(-6.0, 6.0),
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.3, 0.35), (1.0, 0.0)],
                    [(0.0, 0.55, 0.4, 0.7), (1.0, 0.35, 0.25, 0.5)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #5 — eclipse:glitch_pop (the code-reserved GlitchedMonster.tryBlink slot)
# ---------------------------------------------------------------------------
def build_glitch_pop() -> FxBuilder:
    """Datamosh blink pop: ONE emitter, TWO material passes on the same quads — pass 1
    REVERSE_SUB (ONE/ONE) rips a dark decompression hole out of the framebuffer, pass 2
    ADD scatters RGB-split static shards (4x4 flipbook). World space: the hole hangs in
    the air after the mob is gone. allowMulti=true at the call site (origin + exit can
    share a BlockPos)."""
    fx = FxBuilder("glitch_pop")
    (fx.particle_emitter(
            "datamosh",
            duration=14, looping=False, max_particles=32,
            start_lifetime=random_between(6, 10), start_speed=random_between(0.05, 0.25),
            start_size=nf3(random_between(0.14, 0.3), random_between(0.14, 0.3),
                           random_between(0.14, 0.3)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            # Chromatic-aberration split: pure-red .. pure-blue lerp per particle. The
            # SUB pass eats that channel (cyan/yellow shadow), the ADD pass re-emits it.
            start_color=random_color(0xFFFF2A2A, 0xFF2A2AFF),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(box(emit_from="Shell"), scale=nf3(0.8, 1.9, 0.8))
       # Pass 1: the dark rip. Both passes share the emitter uvAnimation, so this
       # texture is a 4x4 sheet of identical soft squares (square_4x4.png).
       .with_material(texture_material(SQUARE_4X4, blend=BLEND_REVERSE_SUB))
       # Pass 2: hot static shards over the hole.
       .with_material(texture_material(STATIC_4X4, hdr=(1.2, 1.2, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")  # REVERSE_SUB is order-independent vs itself
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 3.0, 2.0))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              cycle=2.0),
            size_over_lifetime=curve(0.4, 1.0, [SEG_LINEAR_DOWN], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (0.7, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #6 — eclipse:shadow_bolt_ribbon (loop; entity executor auto-destroys with bolt)
# ---------------------------------------------------------------------------
def build_shadow_bolt_ribbon() -> FxBuilder:
    """Wither-violet ara ribbon dragged by the homing bolt (World-space segments lag
    behind the eye anchor every frame) + a drip of wither motes inheriting bolt speed."""
    fx = FxBuilder("shadow_bolt_ribbon")
    cull = ((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0))

    (fx.ara_trail_emitter(
            "bolt_ribbon",
            duration=100, looping=True,
            space="World", alignment="View", thickness=0.16,
            time=0.45, time_interval=0.05, min_distance=0.05,
            thickness_over_length=curve(0.0, 1.0, [SEG_LINEAR_DOWN], "length", "thickness"),
            # Violet core fading to black edge along the tail; the faint HDR on the
            # material is a bright-violet bloom thread (NOT a dark bloom).
            color_over_length=gradient(
                [(0.0, 0.85), (0.6, 0.4), (1.0, 0.0)],
                [(0.0, 0.5, 0.2, 0.65), (1.0, 0.06, 0.02, 0.1)]),
            physics=dict(inertia=0.4, velocity_smoothing=0.8, damping=0.7))
       .with_material(texture_material(CIRCLE, hdr=(0.9, 0.4, 1.3), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull))

    (fx.particle_emitter(
            "wither_motes",
            duration=100, looping=True, max_particles=12,
            start_lifetime=random_between(8, 14), start_speed=constant(0.02),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="World")
       .with_emission(rate=constant(0.5))
       .with_shape(sphere(radius=0.12))
       .with_module("inheritVelocity", {"mode": "CURRENT", "multiply": constant(0.3)})
       .with_material(texture_material(CIRCLE, hdr=(0.8, 0.35, 1.1), blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)],
                                         [(0.0, 0.55, 0.25, 0.7), (1.0, 0.2, 0.05, 0.3)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #4 (hound half) — eclipse:hound_lunge_windup + eclipse:hound_dash_trail
# ---------------------------------------------------------------------------
def build_hound_lunge_windup() -> FxBuilder:
    """20t = ChargedLungeGoal.WINDUP_TICKS: an electric spiral collapses inward onto the
    rooted hound (function shape over emitter t), crest blooming as the glow-spine anim
    peaks, then a 16-burst release pop at t=19 (spawns at the spiral's collapsed center)."""
    fx = FxBuilder("hound_lunge_windup")
    (fx.particle_emitter(
            "charge_spiral",
            duration=20, looping=False, max_particles=80,
            start_lifetime=random_between(6, 10), start_speed=constant(1.0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="Local")
       .with_emission(rate=constant(3.0), bursts=[burst(time=19, count=constant(16))])
       .with_shape(function_shape(
            x="(1-t)*1.2*cos(t*6*PI)", z="(1-t)*1.2*sin(t*6*PI)", y="0.2+t*0.6",
            speed_x="0-x*0.35", speed_y="0.05", speed_z="0-z*0.35"))
       .with_material(texture_material(CIRCLE, hdr=(0.8, 1.0, 1.4), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            color_by_speed=dict(
                color=gradient([(0.0, 1.0), (1.0, 1.0)],
                               [(0.0, 0.55, 0.75, 1.0), (1.0, 1.0, 1.0, 1.0)]),
                range=(0.0, 0.5)),
            color_over_lifetime=gradient([(0.0, 1.0), (0.75, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))
    return fx


def build_hound_dash_trail() -> FxBuilder:
    """One-shot 16t ~= MAX_DASH_TICKS: a bare physics-lagged ara ribbon (fat -> nothing)
    whipped and settled behind the dash line. Attached AutoRotate.FORWARD."""
    fx = FxBuilder("hound_dash_trail")
    (fx.ara_trail_emitter(
            "dash_ribbon",
            duration=16, looping=False,
            space="World", alignment="Velocity", thickness=0.35,
            time=0.7, time_interval=0.05, min_distance=0.05,
            thickness_over_length=curve(0.0, 1.0, [SEG_LINEAR_DOWN], "length", "thickness"),
            # Fog-grey with a transparent tail.
            color_over_length=gradient(
                [(0.0, 0.5), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, 0.62, 0.66, 0.7), (1.0, 0.42, 0.46, 0.52)]),
            physics=dict(inertia=0.55, velocity_smoothing=0.8, damping=0.7))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 3.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept #8 — eclipse:other_dread_aura (loop; 24-block attach gate lives in PhotonMobFx)
# ---------------------------------------------------------------------------
def build_other_dread_aura() -> FxBuilder:
    """Slow-breathing shroud that visibly EATS light: large soft REVERSE_SUB quads hug the
    body (~12% luminance subtraction, 5 s sine breath — photosensitivity-safe) while
    desaturated violet motes fall (dread falls, not rises). No hdr anywhere: darkness
    comes from subtraction, never from bloom."""
    fx = FxBuilder("other_dread_aura")
    cull = ((-2.0, -1.5, -2.0), (2.0, 3.0, 2.0))

    (fx.particle_emitter(
            "light_eater",
            duration=100, looping=True, prewarm=50, max_particles=8,
            start_lifetime=random_between(90, 110), start_speed=constant(0.005),
            start_size=nf3(random_between(0.9, 1.3), random_between(0.9, 1.3),
                           random_between(0.9, 1.3)),
            # ~12% grey: with ONE/ONE REVERSE_SUB this subtracts a subtle dimming veil.
            start_color=0xFF1F1F26,
            simulation_space="Local")
       .with_emission(rate=constant(0.08))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.7, 1.8, 0.7))
       .with_material(texture_material(CIRCLE, blend=BLEND_REVERSE_SUB))
       .with_renderer(order_in_layer=-1)  # shroud draws before other translucents
       .with_cull_box(*cull)
       .with_curves(
            size_over_lifetime=curve(0.85, 1.0, SEGS_BREATHE, "lifetime", "size")))

    (fx.particle_emitter(
            "violet_motes",
            duration=100, looping=True, prewarm=30, max_particles=16,
            start_lifetime=constant(40), start_speed=constant(0.01),
            start_size=nf3(random_between(0.06, 0.1), random_between(0.06, 0.1),
                           random_between(0.06, 0.1)),
            simulation_space="Local")
       .with_emission(rate=constant(0.4))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.9, 1.9, 0.9))
       .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(-0.025), constant(0))),
            # Greyed violet, luminance far below the bloom threshold (no hdr at all).
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (1.0, 0.0)],
                [(0.0, 0.353, 0.306, 0.4), (1.0, 0.227, 0.196, 0.267)])))
    return fx


# ---------------------------------------------------------------------------
# Concept #10 — eclipse:wanderer_static_shroud (loop; shade:1b IS the concept)
# ---------------------------------------------------------------------------
def build_wanderer_static_shroud() -> FxBuilder:
    """Backrooms Wanderer: mono-yellow paint haze with shade:1b — every particle samples
    the world lightmap, so the shroud dims in perfect sync with tickFlicker's real dark
    windows, zero sync code. The sparse REVERSE_SUB static flecks keep shade:0b: they are
    the thing that does NOT obey the lights."""
    fx = FxBuilder("wanderer_static_shroud")
    cull = ((-2.0, -1.5, -2.0), (2.0, 3.0, 2.0))

    (fx.particle_emitter(
            "paint_haze",
            duration=50, looping=True, prewarm=25, max_particles=32,
            start_lifetime=random_between(25, 35), start_speed=constant(0.02),
            start_size=nf3(random_between(0.14, 0.24), random_between(0.14, 0.24),
                           random_between(0.14, 0.24)),
            simulation_space="Local")
       .with_emission(rate=constant(0.8))
       .with_shape(box(emit_from="Volume"), scale=nf3(0.8, 1.9, 0.8))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)  # the whole concept
       .with_cull_box(*cull)
       .with_curves(
            noise=dict(frequency=0.7, quality="Noise2D", position=nf3(0.05)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (0.8, 0.35), (1.0, 0.0)],
                # Mono-yellow "wet paint" (Backrooms texture-sheet palette).
                [(0.0, 0.85, 0.76, 0.35), (1.0, 0.7, 0.6, 0.25)])))

    (fx.particle_emitter(
            "static_seams",
            duration=50, looping=True, max_particles=8,
            start_lifetime=random_between(10, 16), start_speed=constant(0.01),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=0xFF9A9A9A,
            simulation_space="Local")
       .with_emission(rate=constant(0.2))
       .with_shape(box(emit_from="Shell"), scale=nf3(0.85, 1.95, 0.85))
       .with_material(texture_material(STATIC_4X4, blend=BLEND_REVERSE_SUB))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=curve(0.0, 1.0, [SEG_LINEAR_UP]),
                              cycle=3.0),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Textures (deterministic; PIL)
# ---------------------------------------------------------------------------
def write_textures() -> list:
    from PIL import Image, ImageDraw

    written = []

    # static_4x4.png — the shared #5/#10 flipbook: 4x4 grid of 16x16 white-noise frames
    # (WholeSheet uvAnimation steps through them for the datamosh shimmer).
    rng = random.Random(0x574471C)
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for fy in range(4):
        for fx_ in range(4):
            for x in range(16):
                for y in range(16):
                    v = rng.random()
                    a = int(255 * v * v) if v > 0.45 else 0
                    px[fx_ * 16 + x, fy * 16 + y] = (255, 255, 255, a)
    path = TEXTURE_DIR / "static_4x4.png"
    img.save(path)
    written.append(path)

    # square_4x4.png — 16 identical soft squares on the same 4x4 grid, so the glitch_pop
    # REVERSE_SUB pass survives the shared emitter uvAnimation unchanged.
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    px = img.load()
    for fy in range(4):
        for fx_ in range(4):
            for x in range(16):
                for y in range(16):
                    dx = abs(x - 7.5) / 8.0
                    dy = abs(y - 7.5) / 8.0
                    d = max(dx, dy)
                    a = 0.0 if d > 0.95 else min(1.0, (0.95 - d) / 0.3)
                    px[fx_ * 16 + x, fy * 16 + y] = (255, 255, 255, int(a * 255))
    path = TEXTURE_DIR / "square_4x4.png"
    img.save(path)
    written.append(path)

    # petal_soft.png — one soft cherry-ish petal (white; tinted by startColor at runtime):
    # an ellipse pinched to a point at the stem end, soft alpha falloff.
    size = 32
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    for x in range(size):
        for y in range(size):
            # Normalized coords, petal axis along +y.
            nx = (x - size / 2 + 0.5) / (size / 2)
            ny = (y - size / 2 + 0.5) / (size / 2)
            # Width envelope: 0 at the stem (ny=-0.9), widest around ny=0.3.
            tt = (ny + 0.9) / 1.7
            if tt <= 0.0 or tt > 1.0:
                continue
            width = 0.62 * math.sin(min(1.0, tt) * math.pi) ** 0.8
            if width < 1e-3:
                continue
            d = abs(nx) / width
            if d >= 1.0:
                continue
            a = (1.0 - d * d) * min(1.0, (1.0 - abs(ny)) * 3.0)
            px[x, y] = (255, 255, 255, int(max(0.0, min(1.0, a)) * 255))
    path = TEXTURE_DIR / "petal_soft.png"
    img.save(path)
    written.append(path)
    return written


BUILDERS = {
    "boss_intro_shockwave.fx": build_boss_intro_shockwave,
    "award_star_shower.fx": build_award_star_shower,
    "award_star_glint.fx": build_award_star_glint,
    "sentinel_alert.fx": build_sentinel_alert,
    "sentinel_petal_orbit.fx": build_sentinel_petal_orbit,
    "gazer_gaze_beam.fx": build_gazer_gaze_beam,
    "glitch_pop.fx": build_glitch_pop,
    "shadow_bolt_ribbon.fx": build_shadow_bolt_ribbon,
    "hound_lunge_windup.fx": build_hound_lunge_windup,
    "hound_dash_trail.fx": build_hound_dash_trail,
    "other_dread_aura.fx": build_other_dread_aura,
    "wanderer_static_shroud.fx": build_wanderer_static_shroud,
}


def main() -> int:
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    for path in write_textures():
        print(f"WROTE {path.relative_to(REPO_ROOT)}")
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
