#!/usr/bin/env python3
"""woah_gravity_fx — WOAH-02 Gravitationsbruch Photon `.fx` assets (plan §4.2).

The bamboo-jungle gravity-rift particle layer: amethyst-violet rift identity with
bioluminescent jungle-green accents (the Pandora read of the crater bowl). Rows live
in `woah.gravityrift.client.GravityRiftFxRows`; the two WINDOWED loop handles are
owned by `woah.gravityrift.client.GravityRiftAmbience` (hysteresis attach/release —
never payload-fired, the STORM_CROWN_HALO law).

Executor contracts (must match GravityRiftFxRows / GravityRiftAmbience /
GravityRiftService — every cue anchors at the HEART CENTER, which floats
`GravityRiftZone.HEART_HEIGHT` = 3.2 blocks above the crater floor):

  gravity_light_column   Loop (WINDOWED, attach <=150). The 90-block far-field
                         beacon over the heart: breathing HDR beam + rising streak
                         motes + crown glints at the head. <=30 particles.
  gravity_core_motes     Loop (WINDOWED, attach <=52). The near-field "dust falls
                         upward" bowl read: grey motes over a 32x10x32 box, violet
                         glint stars, jungle-green spore accents. <=44 particles.
  gravity_pulse_ring     One-shot 110 t, STAGED IN-ASSET (the CUE_DAWN_TOLL law):
                         sent 30 t before the launch beat. t 0-30 converging
                         telegraph shimmer; t=30 the beat: ground shock ring
                         (r 4->34 over 30 t), 80-t standing 90-block light column,
                         60-mote dust kick off the bowl floor.
  gravity_invert_burst   One-shot 60 t: REVERSE_SUB dark maw + inward-collapsing
                         amethyst shell, then at t=20 the ADD re-expand shatter +
                         rising debris sheet (riss_maw/tyrant_death_implosion
                         vocabulary). The cooldown dud is the SAME asset scaled
                         0.35x by the row leg (PhotonBridge SpawnOptions).
  gravity_resolve_wave   One-shot 50 t: settling downward glitter (gravity returns),
                         soft floor ring, heart re-light flash.

Run:  python3 tools/photon/woah_gravity_fx.py   # writes + validates all 5 assets
(write() round-trip-validates; every .fx gets its .fxproj sibling — binary-diff law.)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"
WISP = "eclipse:textures/particle/wisp_white.png"
SHARD = "eclipse:textures/particle/glitch_shard.png"

# --- palette (rift identity: amethyst violet + violet-white; jungle-green accents) --
AMETHYST = 0xFFB07CFF
DEEP_VIOLET = 0xFF8A5CF6
PALE_VIOLET = 0xFFEAE0FF
JUNGLE_GLOW = 0xFF8CF0B4
DUST_GREY = 0xB4A9A5B4
VOID_INK = 0xE0100614

# Heart floats 3.2 blocks over the crater floor — floor-hugging emitters sit at this
# local offset (GravityRiftZone.HEART_HEIGHT; all cues anchor at the heart center).
FLOOR_Y = -3.2

# The 2x2 star-sheet twinkle track (house pattern from wandfx2/chrono/resonance_fx).
TWINKLE_FRAMES = dict(
    tiles=(2, 2), animation="WholeSheet",
    frame_over_time=random_curve(
        0.0, 1.0,
        [(0.0, 0.05, 0.25, 0.9, 0.45, 0.1, 0.65, 0.7),
         (0.65, 0.7, 0.75, 0.0, 0.9, 0.95, 1.0, 0.25)],
        [(0.0, 0.6, 0.2, 0.05, 0.4, 1.0, 0.55, 0.15),
         (0.55, 0.15, 0.7, 0.85, 0.85, 0.05, 1.0, 0.5)],
        "lifetime"),
    start_frame=random_between(0.0, 3.0), cycle=3.0)


# ===========================================================================
# Loops (both WINDOWED — GravityRiftAmbience owns the hysteresis windows)
# ===========================================================================
def build_light_column() -> FxBuilder:
    """The 90-block landmark beacon (plan §1 'Blickfang aus 200 Blöcken'): one
    breathing hair-thin HDR beam + rising streaks hugging it + crown glints."""
    fx = FxBuilder("gravity_light_column")
    root = fx.empty("column")

    # (a) the standing beam: width breathes 0.6->1.1 on a 6-s loop.
    beam = (fx.beam_emitter("column_beam",
            duration=120, looping=True, end=(0.0, 90.0, 0.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.45), (0.5, 0.65), (1.0, 0.45)],
                [(0.0, 0.69, 0.49, 1.0), (0.5, 0.80, 0.62, 1.0), (1.0, 0.69, 0.49, 1.0)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(1.9, 1.7, 2.2),
                                       blend=BLEND_ADDITIVE)))
    # BeamConfig.width is an NF (altar_aura_pillar precedent): one smooth breath.
    beam._config["width"] = curve(
        0.6, 1.1,
        [(0.0, 0.0, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5), (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.0)])
    # LINT-CULL-LOOP (loop beams cull too): the 90-block shaft plus margin — tighter
    # than rise_streaks' ±5 box because the beam never leaves the axis (width ≤ 1.1).
    beam.with_cull_box((-2.0, -1.0, -2.0), (2.0, 92.0, 2.0))
    beam.with_lights(sky=15, block=15)

    # (b) rising streaks: fast up-drifting stretched motes hugging the beam shaft —
    # the "gravity points UP here" tell readable from mid-distance.
    (fx.particle_emitter("rise_streaks",
            duration=60, looping=True, prewarm=60,
            start_lifetime=random_between(30, 50),
            start_speed=constant(0),
            start_size=nf3(random_between(0.14, 0.24)),
            start_color=random_color(AMETHYST, PALE_VIOLET),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .with_emission(rate=constant(0.3))
       .with_shape(cylinder(radius=1.3, thickness=0.0),
                   position=(0.0, 20.0, 0.0), scale=(1.0, 38.0, 1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.6, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-5.0, -4.0, -5.0), (5.0, 94.0, 5.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0),
                                                   curve(0.5, 0.9, [SEG_SMOOTH_UP]),
                                                   constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (c) crown glints winking around the column head.
    (fx.particle_emitter("crown_glints",
            duration=80, looping=True, prewarm=80,
            start_lifetime=random_between(24, 40),
            start_speed=constant(0),
            start_size=nf3(random_between(0.6, 1.1)),
            start_color=random_color(PALE_VIOLET, AMETHYST),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.06))
       .with_shape(circle(radius=2.2, thickness=0.6, arc=360.0, arc_mode="Loop",
                          arc_speed=0.2),
                   position=(0.0, 88.0, 0.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.2, 2.0, 2.4), blend=BLEND_ADDITIVE))
       .with_cull_box((-5.0, 84.0, -5.0), (5.0, 93.0, 5.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.3, 0.8), (0.7, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_lights(sky=15, block=15))
    return fx


def build_core_motes() -> FxBuilder:
    """Near-field bowl ambience (plan §4.2 `dust_rise` spec): grey dust motes
    drifting UP through a 32x10x32 box over the crater floor (anti-gravity via a
    rising velocity curve — keeps GPU instancing legal, LINT-GPU-PHYSICS), violet
    glint stars, and bioluminescent jungle spores (the bamboo-jungle Pandora vibe)."""
    fx = FxBuilder("gravity_core_motes")
    root = fx.empty("motes")

    # (a) dust motes: rate 0.12/t, life 80-140 t, up-drift accelerating 0.02->0.05.
    (fx.particle_emitter("dust_motes",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(80, 140),
            start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.12)),
            start_color=color(DUST_GREY),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .with_emission(rate=constant(0.12))
       .with_shape(box(), position=(0.0, FLOOR_Y + 4.0, 0.0), scale=(32.0, 10.0, 32.0))
       .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
       # alpha blend needs DISTANCE sorting (LINT-ALPHA-NOSORT); 24 motes CPU-sort fine.
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-18.0, -6.0, -18.0), (18.0, 14.0, 18.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), curve(0.02, 0.05, [SEG_SMOOTH_UP]), constant(0)),
                orbital=nf3(constant(0), constant(0.04), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.7), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=12, block=10))

    # (b) violet-white glints: sparse additive HDR stars riding the same updraft.
    (fx.particle_emitter("dust_glints",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(60, 100),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.18)),
            start_color=random_color(PALE_VIOLET, AMETHYST),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.04))
       .with_shape(box(), position=(0.0, FLOOR_Y + 4.0, 0.0), scale=(28.0, 9.0, 28.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.0, 1.8, 2.2), blend=BLEND_ADDITIVE))
       .with_cull_box((-18.0, -6.0, -18.0), (18.0, 14.0, 18.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.035), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (0.75, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_lights(sky=15, block=13))

    # (c) jungle spores: soft green wisps loosed from the mossy floes, tumbling up
    # slower than the dust (parallax depth between the two layers).
    (fx.particle_emitter("jungle_spores",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(90, 130),
            start_speed=constant(0),
            start_size=nf3(random_between(0.08, 0.16)),
            start_color=random_color(JUNGLE_GLOW, 0xFF5CC98A),
            simulation_space="Local", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.05))
       .with_shape(cylinder(radius=13.0, thickness=0.35),
                   position=(0.0, FLOOR_Y + 2.0, 0.0), scale=(1.0, 5.0, 1.0))
       .with_material(texture_material(WISP, hdr=(1.2, 1.5, 1.25), blend=BLEND_ADDITIVE))
       .with_cull_box((-18.0, -6.0, -18.0), (18.0, 14.0, 18.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.022), constant(0)),
                orbital=nf3(constant(0), constant(-0.03), constant(0))),
            noise=dict(frequency=0.5, position=nf3(0.02)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=13, block=12))
    return fx


# ===========================================================================
# One-shots (payload-fired through the GravityRiftFxRows rows)
# ===========================================================================
def build_pulse_ring() -> FxBuilder:
    """The 45-s gravitational pulse, STAGED IN-ASSET (cue arrives 30 t pre-beat):
    t 0-30 a converging telegraph shimmer breathes IN toward the heart; t=30 the
    beat fires the expanding ground shock ring (r 4->34 over 30 t, plan §4.2), an
    80-t standing 90-block light column (boss_summon_beacon recipe) and a 60-mote
    dust kick off the bowl floor."""
    fx = FxBuilder("gravity_pulse_ring")
    root = fx.empty("pulse")

    # (a) t 0-30 — telegraph: shimmer ring r~8 converging on the heart (function
    # shape sweeps the circle; negative radial speed pulls every mote inward).
    (fx.particle_emitter("telegraph_indraw",
            duration=30, looping=False,
            start_lifetime=random_between(22, 30),
            start_speed=constant(1.0),
            start_size=nf3(random_between(0.12, 0.22)),
            start_color=random_color(AMETHYST, PALE_VIOLET),
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(1.2))
       .with_shape(function_shape(
            x="8*cos(t*24*PI)", y="0.4*sin(t*10*PI)", z="8*sin(t*24*PI)",
            speed_x="-0.24*cos(t*24*PI)", speed_y="0", speed_z="-0.24*sin(t*24*PI)"))
       .with_material(texture_material(CIRCLE, hdr=(1.9, 1.7, 2.1), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-10.0, -2.0, -10.0), (10.0, 3.0, 10.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.3, 0.9), (0.9, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (b) t=30 — the BEAT: ground shock ring expanding r 4->34 over 30 t (start
    # billboard 8 blocks wide, size curve x8.5 -> 68-block diameter).
    (fx.particle_emitter("ground_ring",
            duration=40, looping=False, start_delay=constant(30),
            start_lifetime=constant(30),
            start_speed=constant(0),
            start_size=nf3(constant(8.0), constant(2.4), constant(8.0)),
            start_color=color(DEEP_VIOLET),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot(), position=(0.0, FLOOR_Y + 0.6, 0.0))
       .with_material(texture_material(RING_SOFT, hdr=(2.4, 2.1, 2.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-36.0, -5.0, -36.0), (36.0, 2.0, 36.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 8.5, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.6, 0.5), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # (c) t=30 — the 90-block column stands for 4 s (80 t): pop -> slow decay.
    beam = (fx.beam_emitter("beat_column",
            duration=80, looping=False, start_delay=30, end=(0.0, 90.0, 0.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.95), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 0.86, 0.75, 1.0), (0.5, 0.69, 0.49, 1.0), (1.0, 0.55, 0.87, 0.71)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(2.8, 2.5, 3.0),
                                       blend=BLEND_ADDITIVE)))
    beam._config["width"] = curve(0.0, 2.2, [SEG_POP_SHRINK])
    beam.with_lights(sky=15, block=15)

    # (d) t=30 — dust kick: 60 motes hurled UP off the bowl floor (the launch pad
    # read; decaying up-velocity so they hang, then the updraft owns them).
    (fx.particle_emitter("dust_kick",
            duration=40, looping=False, start_delay=constant(30),
            start_lifetime=random_between(20, 36),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.20)),
            start_color=random_color(AMETHYST, JUNGLE_GLOW),
            simulation_space="World", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(60))])
       .with_shape(circle(radius=7.0, thickness=1.0), position=(0.0, FLOOR_Y + 0.8, 0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.9, 1.8, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-12.0, -5.0, -12.0), (12.0, 16.0, 12.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), curve(0.15, 0.85, [SEG_POP_SHRINK]), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.7, 0.7), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))
    return fx


def build_invert_burst() -> FxBuilder:
    """Heart-hit inversion (60 t, riss_maw/tyrant_death_implosion vocabulary):
    REVERSE_SUB dark maw + amethyst shell collapsing INTO the heart, then at t=20
    the ADD re-expand shatter (glitch shards) + a rising debris sheet. The cooldown
    dud is this same asset at 0.35x executor scale (row leg)."""
    fx = FxBuilder("gravity_invert_burst")
    root = fx.empty("invert")

    # (a) t=0 — dark maw: REVERSE_SUB subtracts scene color around the heart.
    (fx.particle_emitter("dark_maw",
            duration=20, looping=False,
            start_lifetime=random_between(12, 18),
            start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(1.0, 1.8)),
            start_color=color(VOID_INK),
            simulation_space="Local", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(sphere(radius=1.6, thickness=0.4))
       .with_material(texture_material(SMOKE,
                                       blend=blend("SRC_ALPHA", "ONE", "ONE", "ZERO",
                                                   "REVERSE_SUB")))
       .with_cull_box((-5.0, -4.0, -5.0), (5.0, 6.0, 5.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.25, 0.85), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    # (b) t=0 — collapsing shell: sparks born at r~6 fall INWARD (negative RADIAL
    # velocity — the explicit velocityOverLifetime.radial field) and die at the core.
    (fx.particle_emitter("collapse_shell",
            duration=20, looping=False,
            start_lifetime=random_between(14, 18),
            start_speed=constant(0),
            start_size=nf3(random_between(0.12, 0.22)),
            start_color=random_color(DEEP_VIOLET, AMETHYST),
            simulation_space="Local", max_particles=44)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(40))])
       .with_shape(sphere(radius=6.0, thickness=0.15))
       .with_material(texture_material(CIRCLE, hdr=(2.0, 1.8, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-7.0, -7.0, -7.0), (7.0, 7.0, 7.0))
       .with_curves(
            velocity_over_lifetime=dict(radial=random_between(-0.42, -0.3)),
            color_over_lifetime=gradient(
                [(0.0, 0.4), (0.6, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (c) t=20 — the RE-EXPAND: amethyst shatter volley (glitch_shard billboards
    # tumbling out) + star glints, light gravity so the shards arc down.
    # FX-Wave-11 stacking-law pass: 34 additive shards born on one 1.2 r SURFACE at
    # hdr 2.4 re-lit the heart as a white ball at the exact re-expand beat. Count
    # 34->18, the shell given 0.3 thickness so births spread through the volume,
    # hdr nerfed to ~1.45 and the alpha crest 1.0->0.7.
    (fx.particle_emitter("shatter_shards",
            duration=40, looping=False, start_delay=constant(20),
            start_lifetime=random_between(20, 32),
            start_speed=random_between(0.45, 0.95),
            start_size=nf3(random_between(0.14, 0.28)),
            start_rotation=nf3(constant(0), constant(0), random_between(0, 360)),
            start_color=random_color(AMETHYST, PALE_VIOLET),
            simulation_space="World", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(sphere(radius=1.2, thickness=0.3))
       .with_material(texture_material(SHARD, hdr=(1.45, 1.3, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-8.0, -6.0, -8.0), (8.0, 10.0, 8.0))
       .with_physics(collision=False, gravity=0.25)
       .with_curves(
            rotation_over_lifetime=dict(roll=random_between(-160, 160)),
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.7, 0.56), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # (c2) t=12 — retro swirl (W13-C3 inversion beat): a mote ring orbiting BACKWARD
    # around the heart while the BlockDisplay orbit grinds through its mass-inertia
    # reversal — the particles tell the same direction-flip story on the same beat.
    # Negative orbital velocity (rad-equivalent x0.01/t house rule), modest HDR 1.9.
    (fx.particle_emitter("retro_swirl",
            duration=48, looping=False, start_delay=constant(12),
            start_lifetime=random_between(30, 44),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.18)),
            start_color=random_color(AMETHYST, JUNGLE_GLOW),
            simulation_space="Local", max_particles=20)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(circle(radius=9.5, thickness=0.35))
       .with_material(texture_material(CIRCLE, hdr=(1.9, 1.7, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.3,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-12.0, -4.0, -12.0), (12.0, 8.0, 12.0))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0), constant(-0.05), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (d) t=20 — rising debris sheet: a wide mote curtain lifting off the bowl
    # floor while the inversion holds ("everything loose goes up").
    (fx.particle_emitter("debris_sheet",
            duration=40, looping=False, start_delay=constant(20),
            start_lifetime=random_between(24, 38),
            start_speed=constant(0),
            start_size=nf3(random_between(0.08, 0.18)),
            start_color=random_color(DUST_GREY, JUNGLE_GLOW),
            simulation_space="World", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(1.0))
       .with_shape(circle(radius=6.5, thickness=1.0), position=(0.0, FLOOR_Y + 0.8, 0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 1.5, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-10.0, -5.0, -10.0), (10.0, 14.0, 10.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0),
                                                   curve(0.12, 0.3, [SEG_SMOOTH_UP]),
                                                   constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.8, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=14, block=13))
    return fx


def build_resolve_wave() -> FxBuilder:
    """Inversion end (50 t): gravity comes home — glitter settles DOWN out of the
    air, a soft floor ring breathes once, the heart re-lights with a star flash."""
    fx = FxBuilder("gravity_resolve_wave")
    root = fx.empty("resolve")

    # (a) settle rain: born overhead, drifting gently DOWN (the counter-read to
    # every other emitter in this feature — that reversal IS the resolve tell).
    (fx.particle_emitter("settle_rain",
            duration=30, looping=False,
            start_lifetime=random_between(26, 40),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.18)),
            start_color=random_color(PALE_VIOLET, AMETHYST),
            simulation_space="World", max_particles=56)
       .child_of(root)
       .with_emission(rate=constant(1.6))
       .with_shape(cylinder(radius=7.0, thickness=1.0),
                   position=(0.0, 7.0, 0.0), scale=(1.0, 4.0, 1.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.9, 1.7, 2.1), blend=BLEND_ADDITIVE))
       .with_cull_box((-10.0, -6.0, -10.0), (10.0, 12.0, 10.0))
       .with_physics(collision=False, gravity=0.12)
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.15, 0.9), (0.8, 0.7), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (b) one soft floor ring breathing out (half the pulse ring's reach).
    (fx.particle_emitter("floor_ring",
            duration=30, looping=False,
            start_lifetime=constant(22),
            start_speed=constant(0),
            start_size=nf3(constant(4.0), constant(1.4), constant(4.0)),
            start_color=color(JUNGLE_GLOW),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot(), position=(0.0, FLOOR_Y + 0.6, 0.0))
       .with_material(texture_material(RING_SOFT, hdr=(1.7, 2.0, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-12.0, -5.0, -12.0), (12.0, 2.0, 12.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 4.5, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (c) heart re-light: one bright flash + 10 glints popping off the core.
    (fx.particle_emitter("relight_flash",
            duration=20, looping=False,
            start_lifetime=random_between(8, 16),
            start_speed=random_between(0.1, 0.35),
            start_size=nf3(random_between(0.2, 0.5)),
            start_color=random_color(PALE_VIOLET, AMETHYST),
            simulation_space="Local", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(10))])
       .with_shape(sphere(radius=0.8, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.6, 2.3, 2.8), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-3.0, -3.0, -3.0), (3.0, 4.0, 3.0))
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "gravity_light_column.fx": build_light_column,
    "gravity_core_motes.fx": build_core_motes,
    "gravity_pulse_ring.fx": build_pulse_ring,
    "gravity_invert_burst.fx": build_invert_burst,
    "gravity_resolve_wave.fx": build_resolve_wave,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip-validates
        builder.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B)"
                  " — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
