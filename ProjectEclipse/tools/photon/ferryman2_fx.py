#!/usr/bin/env python3
"""FERRYMAN2 — authors the finale-arc Photon assets (F-044/F-045/F-045b/F-046/F-046b)
with fxlib:

  eclipse:day_rift_maw        F-044 dawn rift over the center island: DELIBERATELY the
                              anti-thesis of expansion_rift_glow — sluggish, dark,
                              pulsing violet (slow smoke vortex + heartbeat pulses +
                              dripping motes), 600t ≈ the 30 s rift window
  eclipse:portal_soul_veil    F-045 portal interior: flat vertical shimmer plane of
                              rising soul motes + faint smoke (100t one-shot, re-fired
                              on the sustain cadence — the kneel-corona law)
  eclipse:key_trail           F-045b key flight ribbon: gold-violet ara trail, LOOPING —
                              entity-attached only (shard-trail exemption: Photon
                              auto-destroys the runtime with the key entity)
  eclipse:arena_mist_wall     F-046 arena fog bank segment (140t, re-fired at the four
                              perimeter anchors while the fight runs)
  eclipse:ferry_harvest_ring  F-046b (a) Seelenernte telegraph: a violet floor ring that
                              contracts onto the boss over the 40t warning
  eclipse:ferry_wave_crest    F-046b (b) Ruderschlag-Welle crest: directional spray +
                              crest streaks authored toward LOCAL -Z (the oar-tear
                              rotation law: the Java leg rotates 180° − yaw about Y)
  eclipse:wisp_gush           F-045b breach burst: violet wisps + smoke shoved out of
                              the opened gate (authored toward local -Z, same leg)

Usage:  python3 tools/photon/ferryman2_fx.py            # write + validate all seven
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, box, burst, circle, cone,
    constant, curve, dot, function_shape, gradient, nf3, random_between, sphere,
    texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# The finale palette: near-black violet body, #9C7BE0 mid, #D0B3FF hot, gold accents.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
GOLD = (0.98, 0.82, 0.45)


# ---------------------------------------------------------------------------
# 1. eclipse:day_rift_maw — F-044 (slow, dark, pulsing — NOT the structure rift)
# ---------------------------------------------------------------------------
# Underhang bell geometry: the curtain sags UNDERHANG_DEPTH blocks below the rift
# plane and widens from UNDERHANG_R0 to UNDERHANG_R0 + UNDERHANG_R_GROWTH on the way
# down (one randomC drives both, so depth and radius stay coupled = a bell, not a tube).
UNDERHANG_DEPTH = 10.0
UNDERHANG_R0 = 4.5
UNDERHANG_R_GROWTH = 4.0
# One shared cull envelope for the whole asset — it must clear the bell's sag, else the
# underside pops away the moment the camera swings below the rift.
MAW_CULL_MIN = (-14.0, -28.0, -14.0)
MAW_CULL_MAX = (14.0, 8.0, 14.0)


def build_day_rift_maw() -> FxBuilder:
    fx = FxBuilder("day_rift_maw")
    root = fx.empty("maw_root")

    # Sluggish near-black smoke vortex — the rift's body. Alpha-blended (dark, not
    # additive) so it reads as a WOUND in the sky rather than a glow.
    (fx.particle_emitter(
            "maw_smoke",
            duration=560, looping=False, start_lifetime=random_between(70, 110),
            start_speed=constant(0.02),
            start_size=nf3(random_between(1.6, 3.2), random_between(1.6, 3.2),
                           random_between(1.6, 3.2)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.8))
        .with_shape(circle(radius=4.5, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.22), constant(0)),  # SLUGGISH swirl
                radial=constant(-0.03)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.55), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, 0.16, 0.09, 0.22), (1.0, 0.08, 0.04, 0.13)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Underhang bell: a widening curtain sagging BELOW the rift, turning at ~half the
    # body's orbital rate (0.1 vs 0.22). That LAG is the whole point — the underside
    # drags behind the mouth, so the maw reads as a heavy hanging mass instead of a
    # painted hole. Alpha ceiling 0.30: it darkens the sky under the rift, nothing more.
    (fx.particle_emitter(
            "maw_underhang",
            duration=560, looping=False, start_lifetime=random_between(80, 120),
            start_speed=constant(0),
            start_size=nf3(random_between(2.0, 3.6), random_between(2.0, 3.6),
                           random_between(2.0, 3.6)),
            simulation_space="Local", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.6))
        .with_shape(function_shape(
            x=f"cos(randomA*2*PI)*({UNDERHANG_R0}+randomC*{UNDERHANG_R_GROWTH})",
            y=f"-(randomC*{UNDERHANG_DEPTH})",
            z=f"sin(randomA*2*PI)*({UNDERHANG_R0}+randomC*{UNDERHANG_R_GROWTH})"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.08, -0.04), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.1), constant(0))),  # HALF the body
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.3), (0.8, 0.22), (1.0, 0.0)],
                [(0.0, 0.1, 0.08, 0.16), (1.0, 0.05, 0.04, 0.09)]),
            size_over_lifetime=curve(
                0.8, 1.4, [(0.0, 0.0, 0.25, 0.45, 0.6, 0.92, 1.0, 1.0)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Heartbeat pulses: one soft violet bloom every ~2.5 s — the "pulsierend lila".
    (fx.particle_emitter(
            "maw_pulse",
            duration=560, looping=False, start_lifetime=constant(34),
            start_speed=constant(0), start_size=nf3(3.0), max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=10, count=constant(1), cycles=11, interval=50)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(0.9, 0.6, 1.5)))
        .with_curves(
            # Swell-and-die bloom: the pulse breathes OUT slowly (trägheit).
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.25, 0.35, 1.0, 0.7, 0.85, 1.0, 0.3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.35, 0.2, 0.55)]))
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Dripping motes: sparse violet droplets sinking out of the maw (the debris seam —
    # the real block displays fall through this curtain).
    (fx.particle_emitter(
            "maw_drip",
            duration=560, looping=False, start_lifetime=random_between(50, 90),
            start_speed=constant(0),
            start_size=nf3(random_between(0.12, 0.3), random_between(0.12, 0.3),
                           random_between(0.12, 0.3)),
            simulation_space="World", max_particles=70)
        .child_of(root)
        .with_emission(rate=constant(1.0))
        .with_shape(circle(radius=3.5, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.22, -0.1), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.4, 0.25, 0.65)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.1, 0.8, 1.7)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                       length_scale=1.8, vertex_sorting="NONE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:portal_soul_veil — F-045 portal interior (sustain one-shot)
# ---------------------------------------------------------------------------
def build_portal_soul_veil() -> FxBuilder:
    fx = FxBuilder("portal_soul_veil")

    # Rising soul motes inside the door plane (flat box: x = width, y = height).
    (fx.particle_emitter(
            "veil_motes",
            duration=100, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0),
            start_size=nf3(random_between(0.08, 0.22), random_between(0.08, 0.22),
                           random_between(0.08, 0.22)),
            simulation_space="Local", max_particles=80)
        .with_emission(rate=constant(1.4))
        .with_shape(box(), scale=(6.5, 9.0, 0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.09), constant(0))),
            noise=dict(frequency=0.5, position=nf3(0.03)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.816, 0.702, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.4, 1.0, 2.2)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-6.0, -6.0, -4.0), (6.0, 12.0, 4.0)))

    # Faint wafting smoke sheet behind the motes — the "wabern".
    (fx.particle_emitter(
            "veil_smoke",
            duration=100, looping=False, start_lifetime=random_between(55, 85),
            start_speed=constant(0.01),
            start_size=nf3(random_between(1.2, 2.2), random_between(1.2, 2.2),
                           random_between(1.2, 2.2)),
            simulation_space="Local", max_particles=30)
        .with_emission(rate=constant(0.5))
        .with_shape(box(), scale=(6.0, 8.5, 0.4))
        .with_curves(
            noise=dict(frequency=0.35, position=nf3(0.05)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.35), (0.8, 0.25), (1.0, 0.0)],
                [(0.0, 0.24, 0.12, 0.36), (1.0, 0.12, 0.06, 0.2)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-6.0, -6.0, -4.0), (6.0, 12.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:key_trail — F-045b key flight ribbon (entity-attached loop)
# ---------------------------------------------------------------------------
def build_key_trail() -> FxBuilder:
    fx = FxBuilder("key_trail")

    # Gold-violet ara ribbon lagging behind the flying key (shard-trail pattern).
    (fx.ara_trail_emitter(
            "key_ribbon",
            duration=100, looping=True,
            space="World", alignment="View",
            thickness=0.45, smoothness=5, corner_roundness=6,
            time=1.1, time_interval=0.05,
            color_over_length=gradient(
                [(0.0, 0.95), (1.0, 0.0)],
                [(0.0, 0.98, 0.82, 0.45), (0.45, 0.816, 0.702, 1.0),
                 (1.0, 0.4, 0.25, 0.65)]),
            thickness_over_length=curve(
                0.0, 1.0, [(0.0, 1.0, 0.3, 0.9, 0.7, 0.35, 1.0, 0.1)]),
            physics=dict(inertia=0.3, velocity_smoothing=0.75, damping=0.72))
        .with_material(texture_material(CIRCLE_TEX, hdr=(2.2, 1.7, 1.1)))
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))

    # Loose gold sparks shed along the path (World space: they stay behind).
    (fx.particle_emitter(
            "key_sparks",
            duration=20, looping=True, start_lifetime=random_between(14, 26),
            start_speed=constant(0.03),
            start_size=nf3(random_between(0.05, 0.12), random_between(0.05, 0.12),
                           random_between(0.05, 0.12)),
            simulation_space="World", max_particles=60, parallel_update=True)
        .with_emission(rate=constant(1.2))
        .with_shape(sphere(radius=0.4, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.04, -0.01), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)],
                [(0.0, 0.98, 0.82, 0.45), (1.0, 0.816, 0.702, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.8, 1.4, 0.9)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:arena_mist_wall — F-046 fog bank segment (perimeter sustain)
# ---------------------------------------------------------------------------
def build_arena_mist_wall() -> FxBuilder:
    fx = FxBuilder("arena_mist_wall")

    # One long low fog bank (anchored at a perimeter midpoint; four anchors ring the
    # arena). World sim space: puffs hang where emitted while the anchor re-fires.
    (fx.particle_emitter(
            "mist_bank",
            duration=140, looping=False, start_lifetime=random_between(90, 130),
            start_speed=constant(0.008),
            start_size=nf3(random_between(2.2, 4.0), random_between(2.2, 4.0),
                           random_between(2.2, 4.0)),
            simulation_space="World", max_particles=70, parallel_update=True)
        .with_emission(rate=constant(0.5))
        .with_shape(box(), scale=(46.0, 5.0, 6.0))
        .with_curves(
            noise=dict(frequency=0.3, position=nf3(0.04)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.4), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, 0.32, 0.24, 0.45), (1.0, 0.18, 0.12, 0.3)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-28.0, -6.0, -8.0), (28.0, 12.0, 8.0)))

    # Sparse violet embers drifting up out of the fog crest.
    (fx.particle_emitter(
            "mist_embers",
            duration=140, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0),
            start_size=nf3(random_between(0.06, 0.14), random_between(0.06, 0.14),
                           random_between(0.06, 0.14)),
            simulation_space="World", max_particles=40, parallel_update=True)
        .with_emission(rate=constant(0.4))
        .with_shape(box(), scale=(44.0, 2.0, 4.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.07), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.35, 0.2, 0.55)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 0.9, 1.8)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-28.0, -6.0, -8.0), (28.0, 14.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# 5. eclipse:ferry_harvest_ring — F-046b (a) Seelenernte telegraph (40t + hit)
# ---------------------------------------------------------------------------
def build_ferry_harvest_ring() -> FxBuilder:
    fx = FxBuilder("ferry_harvest_ring")

    # The contracting warning ring: particles born on the r=10 floor circle and pulled
    # inward — the ring visibly CLOSES onto the boss over the telegraph.
    (fx.particle_emitter(
            "harvest_ring",
            duration=44, looping=False, start_lifetime=constant(38),
            start_speed=constant(0),
            start_size=nf3(random_between(0.18, 0.3), random_between(0.18, 0.3),
                           random_between(0.18, 0.3)),
            simulation_space="Local", max_particles=90)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(80), cycles=1)])
        .with_shape(circle(radius=10.0, thickness=0.05, arc_mode="BurstSpread"))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.26)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.85, 0.9), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (0.85, 0.816, 0.702, 1.0),
                 (1.0, 1.0, 1.0, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.6, 1.1, 2.4)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-12.0, -2.0, -12.0), (12.0, 4.0, 12.0)))

    # Floor glow disc under the boss — reads even when the ring particles are occluded.
    (fx.particle_emitter(
            "harvest_glow",
            duration=44, looping=False, start_lifetime=constant(40),
            start_speed=constant(0), start_size=nf3(4.5), max_particles=1)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
        .with_shape(dot())
        .at(0.0, 0.1, 0.0)
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.0, 0.7, 1.6)))
        .with_renderer(render_mode="Horizontal")
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.4, 0.3, 1.0, 0.8, 0.9, 1.0, 0.5)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (1.0, 0.0)],
                [(0.0, 0.45, 0.28, 0.7), (1.0, 0.612, 0.482, 0.878)]))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 4.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# 6. eclipse:ferry_wave_crest — F-046b (b) wave crest (aimed via the yaw leg)
# ---------------------------------------------------------------------------
def build_ferry_wave_crest() -> FxBuilder:
    fx = FxBuilder("ferry_wave_crest")

    # Crest streaks: a fan of water-white streaks racing toward LOCAL -Z (the Java leg
    # rotates the executor by 180° − yaw so -Z is the boss's facing).
    (fx.particle_emitter(
            "crest_streaks",
            duration=30, looping=False, start_lifetime=random_between(18, 30),
            start_speed=random_between(0.7, 1.1),
            start_size=nf3(random_between(0.15, 0.3), random_between(0.15, 0.3),
                           random_between(0.15, 0.3)),
            max_particles=50)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(36), cycles=1)])
        .with_shape(cone(angle=18.0, radius=1.6))
        .rotated(-90.0, 0.0, 0.0)  # cone fires +Y by default; pitch it onto -Z
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.6, 2.2)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                       length_scale=2.8, vertex_sorting="NONE")
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 0.75, 0.85, 1.0), (1.0, 0.5, 0.45, 0.85)]))
        .with_cull_box((-8.0, -3.0, -28.0), (8.0, 6.0, 4.0)))

    # Churned spray mist kicked up along the wave's launch line.
    (fx.particle_emitter(
            "crest_spray",
            duration=30, looping=False, start_lifetime=random_between(20, 34),
            start_speed=random_between(0.2, 0.45),
            start_size=nf3(random_between(0.5, 0.9), random_between(0.5, 0.9),
                           random_between(0.5, 0.9)),
            max_particles=26)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(18), cycles=1)])
        .with_shape(cone(angle=32.0, radius=1.8))
        .rotated(-90.0, 0.0, 0.0)
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.5), (0.6, 0.35), (1.0, 0.0)],
            [(0.0, 0.55, 0.62, 0.75), (1.0, 0.35, 0.38, 0.52)]))
        .with_cull_box((-8.0, -3.0, -22.0), (8.0, 6.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 7. eclipse:wisp_gush — F-045b breach burst out of the opened gate
# ---------------------------------------------------------------------------
def build_wisp_gush() -> FxBuilder:
    fx = FxBuilder("wisp_gush")

    # Violet wisps shoved out of the doorway (local -Z = out of the gate front).
    (fx.particle_emitter(
            "gush_wisps",
            duration=80, looping=False, start_lifetime=random_between(30, 55),
            start_speed=random_between(0.35, 0.8),
            start_size=nf3(random_between(0.2, 0.45), random_between(0.2, 0.45),
                           random_between(0.2, 0.45)),
            max_particles=70)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(30), cycles=3, interval=8)])
        .with_shape(cone(angle=40.0, radius=2.6))
        .rotated(-90.0, 0.0, 0.0)
        .with_curves(
            noise=dict(frequency=0.7, position=nf3(0.06)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.45, 0.28, 0.7)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.7, 1.2, 2.6)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-10.0, -6.0, -20.0), (10.0, 10.0, 6.0)))

    # Cold violet smoke rolling low out of the threshold.
    (fx.particle_emitter(
            "gush_smoke",
            duration=80, looping=False, start_lifetime=random_between(45, 75),
            start_speed=random_between(0.12, 0.3),
            start_size=nf3(random_between(0.9, 1.7), random_between(0.9, 1.7),
                           random_between(0.9, 1.7)),
            max_particles=34)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(12), cycles=3, interval=10)])
        .with_shape(cone(angle=55.0, radius=2.8))
        .rotated(-90.0, 0.0, 0.0)
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.2, 0.45), (0.8, 0.3), (1.0, 0.0)],
            [(0.0, 0.28, 0.16, 0.4), (1.0, 0.14, 0.08, 0.22)]))
        .with_cull_box((-10.0, -6.0, -18.0), (10.0, 8.0, 6.0)))
    return fx


BUILDERS = {
    "day_rift_maw.fx": build_day_rift_maw,
    "portal_soul_veil.fx": build_portal_soul_veil,
    "key_trail.fx": build_key_trail,
    "arena_mist_wall.fx": build_arena_mist_wall,
    "ferry_harvest_ring.fx": build_ferry_harvest_ring,
    "ferry_wave_crest.fx": build_ferry_wave_crest,
    "wisp_gush.fx": build_wisp_gush,
}


def main() -> int:
    rc = 0
    for name, builder in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        b = builder()
        raw_len, gz_len = b.write(path)  # write() round-trip-validates
        b.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
