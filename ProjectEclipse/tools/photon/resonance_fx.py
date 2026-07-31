#!/usr/bin/env python3
"""resonance_fx — WOAH-04 Resonanzfeld Photon `.fx` assets (plan §4.3).

The singing-crystal valley's particle layer: violet→cyan "resonance" identity.
Rows live in `woah.resonance.client.ResonancePhotonFxRows`; the WINDOWED loop
handles are owned by `woah.resonance.client.ResonanceFieldFx` (never registry
loop rows — the STORM_CROWN_HALO law).

Executor contracts (must match ResonanceFieldFx / ResonancePhotonFxRows):

  resonance_crystal_aura  Loop, per-crystal. Authored for a 20-block crystal at
                          bottom-center; the client scales y by height/20 and
                          x/z by girth class. Cylinder-shell mist + facet glints.
  resonance_bahn          Loop, per-edge. Beam end local (0,0,-1) + motes gliding
                          local z 0→−1; the client rotates 180°−yaw about Y and
                          stretches z by the edge length (unit-Z contract).
  resonance_strike_burst  One-shot 30 t at a crystal top: glitter volley, foot
                          ring, short vertical flash beam. allowMulti via row leg.
  resonance_pulse_hop     One-shot 12 t: one bright bead sliding local z 0→−1
                          (+4 trail glints); executor yaw = 180°−a, z-scale = b
                          (hop length in blocks).
  resonance_fail_flicker  One-shot 20 t at the altar: REVERSE_SUB dark pass, red
                          double ring flicker, falling sparks (GLITCH palette).
  resonance_finale_column One-shot 160 t at the altar: 120-block beam, 6-s glitter
                          rain (collide+die), ground shock ring, crown starburst —
                          pacing staged INSIDE the asset (0/10/10/20 t delays).
  resonance_far_shaft     Loop, far-LOD. Hair-thin 60-block HDR shaft + 2 lazy
                          orbit glints; client scales y by height×2/60 and width
                          by distance (CUE_SUMMON_BEACON recipe). ≤10 particles.
  resonance_far_pulse     Loop, far-LOD. 8-s sky-dome pulse over the valley
                          (ring r 40, slow expansion + fade). ≤12 particles.
  resonance_wave_ring     One-shot 90 t (W13-C3). The resonance-wave front: ground
                          ring expanding r 0→36 over 80 t (0.45 blocks/t — EXACTLY
                          the ResonanceWaveFx server front that makes the monoliths
                          tremble) + glint fringe born ON the moving front
                          (function shape, t-swept radius). HDR ≤ 1.45.

Run:  python3 tools/photon/resonance_fx.py       # writes + validates all 9 assets
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

# --- palette (resonance identity: deep violet body, cyan accents, pale glints) -----
DEEP_VIOLET = 0xFF8A5CF6
VIOLET = 0xFFB07CFF
CYAN = 0xFF7FE8F0
PALE_LILAC = 0xFFEAE0FF
# GLITCH palette for the FAIL sting (FX-STYLE-GUIDE §1.3).
GLITCH_RED = 0xFFFF4A55
EMBER_RED = 0xFFE8402E
VOID_INK = 0xE0100614

# The 2x2 star-sheet twinkle track (house pattern from wandfx2/chrono_fx).
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
# Loops (all WINDOWED — ResonanceFieldFx owns the hysteresis windows)
# ===========================================================================
def build_crystal_aura() -> FxBuilder:
    """Per-crystal idle aura: a slow violet mist climbing a 20-block cylinder shell
    (executor-scaled per crystal class) + sparse facet glints winking on the faces."""
    fx = FxBuilder("resonance_crystal_aura")
    root = fx.empty("aura")

    # (a) shell mist: r≈1.6 cylinder shell hugging the monolith, drifting +0.12y.
    (fx.particle_emitter("shell_mist",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(60, 90),
            start_speed=constant(0),
            start_size=nf3(random_between(0.14, 0.26)),
            start_color=random_color(DEEP_VIOLET, VIOLET),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.25))                       # 5/s (plan §4.3)
       .with_shape(cylinder(radius=1.6, thickness=0.0),
                   position=(0.0, 10.0, 0.0), scale=(1.0, 18.0, 1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 1.15, 1.4), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-3.0, -1.0, -3.0), (3.0, 22.0, 3.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.12), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=13, block=12))

    # (b) facet glints: 3-burst every 2 s, twinkling stars on the crystal faces.
    (fx.particle_emitter("facet_glints",
            duration=40, looping=True, prewarm=40,
            start_lifetime=random_between(14, 24),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.20)),
            start_color=random_color(PALE_LILAC, CYAN),
            simulation_space="Local", max_particles=20)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
       .with_shape(cylinder(radius=1.4, thickness=0.0),
                   position=(0.0, 11.0, 0.0), scale=(1.0, 16.0, 1.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.2, 1.9, 2.4), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-3.0, -1.0, -3.0), (3.0, 22.0, 3.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_lights(sky=15, block=14))
    return fx


def build_bahn() -> FxBuilder:
    """Per-edge light path: a unit-Z beam (executor stretches z to the edge length)
    breathing on a 40 t loop, plus light motes wandering source→target."""
    fx = FxBuilder("resonance_bahn")
    root = fx.empty("bahn")

    # (a) the path beam: end local (0,0,-1); width pulses 0.22→0.42 on the 40 t loop.
    beam = (fx.beam_emitter("path_beam",
            duration=40, looping=True, end=(0.0, 0.0, -1.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.5), (0.5, 0.75), (1.0, 0.5)],
                [(0.0, 0.69, 0.49, 1.0), (0.5, 0.5, 0.91, 0.94), (1.0, 0.69, 0.49, 1.0)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(1.7, 1.6, 1.9),
                                       blend=BLEND_ADDITIVE)))
    # BeamConfig.width is an NF (the altar_aura_pillar precedent): one smooth breath.
    beam._config["width"] = curve(
        0.22, 0.42,
        [(0.0, 0.0, 0.2, 1.0, 0.3, 1.0, 0.5, 0.5), (0.5, 0.5, 0.7, 0.0, 0.8, 0.0, 1.0, 0.0)])
    # LINT-CULL-LOOP (loop beams cull too): identical to path_motes' box so the whole
    # edge FX culls as one unit — local space is the unit-Z edge the executor stretches.
    beam.with_cull_box((-2.0, -2.0, -1.1), (2.0, 2.0, 0.1))
    beam.with_lights(sky=14, block=13)

    # (b) wandering motes: spawn along z 0→−1 (emitter-t sweep), drifting toward the
    # target so the path reads directional even mid-loop.
    (fx.particle_emitter("path_motes",
            duration=40, looping=True, prewarm=40,
            start_lifetime=random_between(16, 26),
            start_speed=constant(1.0),
            start_size=nf3(random_between(0.10, 0.18)),
            start_color=random_color(VIOLET, CYAN),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.4))                        # 8/s (plan §4.3)
       .with_shape(function_shape(x="0", y="0", z="-t",
                                  speed_x="0", speed_y="0", speed_z="-0.012"))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.7, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-2.0, -2.0, -1.1), (2.0, 2.0, 0.1))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.25, 0.9), (0.75, 0.9), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=14, block=13))
    return fx


def build_far_shaft() -> FxBuilder:
    """Far-LOD shaft (160–400 blocks): one hair-thin 60-block HDR beam over a tall
    crystal + 2 lazy orbit glints. The client scales width by distance."""
    fx = FxBuilder("resonance_far_shaft")
    root = fx.empty("shaft")

    beam = (fx.beam_emitter("far_beam",
            duration=120, looping=True, end=(0.0, 60.0, 0.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.4), (0.5, 0.6), (1.0, 0.4)],
                [(0.0, 0.72, 0.55, 1.0), (1.0, 0.72, 0.55, 1.0)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(1.9, 1.7, 2.2),
                                       blend=BLEND_ADDITIVE)))
    beam._config["width"] = curve(
        0.5, 0.9,
        [(0.0, 0.5, 0.25, 1.0, 0.4, 1.0, 0.5, 0.5), (0.5, 0.5, 0.75, 0.0, 0.9, 0.0, 1.0, 0.5)])
    # LINT-CULL-LOOP (loop beams cull too): the 60-block shaft plus margin — tighter
    # than orbit_glints' ±5 ring box because the beam stays on the axis (width ≤ 0.9).
    beam.with_cull_box((-2.0, -1.0, -2.0), (2.0, 62.0, 2.0))
    beam.with_lights(sky=15, block=15)

    # 2 orbit glints circling the shaft mid-height (arc Loop = steady procession).
    (fx.particle_emitter("orbit_glints",
            duration=160, looping=True, prewarm=160,
            start_lifetime=constant(160),
            start_speed=constant(0),
            start_size=nf3(random_between(0.8, 1.2)),
            start_color=random_color(PALE_LILAC, VIOLET),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.0125))                     # ~2 alive at a time
       .with_shape(circle(radius=2.5, thickness=0.0, arc=360.0, arc_mode="Loop",
                          arc_speed=0.25),
                   position=(0.0, 30.0, 0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.6, 2.0), blend=BLEND_ADDITIVE))
       .with_cull_box((-5.0, -2.0, -5.0), (5.0, 62.0, 5.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.15, 0.7), (0.85, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_far_pulse() -> FxBuilder:
    """Far-LOD sky pulse: every 8 s one faint dome ring blooms over the valley
    (r 40 → slow expansion + fade) — the 'something breathes there' tell."""
    fx = FxBuilder("resonance_far_pulse")
    root = fx.empty("pulse")

    (fx.particle_emitter("dome_ring",
            duration=160, looping=True,
            start_lifetime=constant(100),
            start_speed=constant(0),
            start_size=nf3(constant(80.0), constant(20.0), constant(80.0)),
            start_color=color(DEEP_VIOLET),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.3, 1.2, 1.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-60.0, -20.0, -60.0), (60.0, 20.0, 60.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 1.5, [SEG_SMOOTH_UP]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.35), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=12))

    # a few high glints riding the pulse (keeps the dome from reading flat).
    (fx.particle_emitter("sky_glints",
            duration=160, looping=True, prewarm=160,
            start_lifetime=random_between(60, 110),
            start_speed=constant(0),
            start_size=nf3(random_between(0.9, 1.6)),
            start_color=random_color(PALE_LILAC, CYAN),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.05))
       .with_shape(circle(radius=32.0, thickness=0.4))
       .with_material(texture_material(STAR_2X2, hdr=(1.6, 1.5, 1.8), blend=BLEND_ADDITIVE))
       .with_cull_box((-60.0, -20.0, -60.0), (60.0, 20.0, 60.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.3, 0.6), (0.7, 0.6), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_lights(sky=15, block=12))
    return fx


# ===========================================================================
# One-shots (payload-fired through the ResonancePhotonFxRows rows)
# ===========================================================================
def build_strike_burst() -> FxBuilder:
    """Strike on a crystal top (30 t): 10-glitter volley with light gravity, one
    horizontal foot ring, one short vertical flash beam (8 blocks, 6 t)."""
    fx = FxBuilder("resonance_strike_burst")
    root = fx.empty("strike")

    # (a) the glitter volley — StretchedBillboard streaks, gentle fall.
    # FX-Wave-11 stacking-law pass: 22 additive streaks born inside a 0.6 r shell at
    # hdr 2.6 fused into one white blob on the crystal tip. Count 22->10 on a 1.0 r
    # shell, hdr nerfed to ~1.45, alpha crest 1.0->0.7.
    (fx.particle_emitter("glitter",
            duration=30, looping=False,
            start_lifetime=random_between(16, 26),
            start_speed=random_between(0.35, 0.75),
            start_size=nf3(random_between(0.10, 0.20)),
            start_color=random_color(VIOLET, CYAN),
            simulation_space="World", max_particles=24)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
       .with_shape(sphere(radius=1.0, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.45, 1.3, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-5.0, -6.0, -5.0), (5.0, 9.0, 5.0))
       .with_physics(collision=False, gravity=0.35)
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.7, 0.56), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (b) foot ring at the cue anchor.
    (fx.particle_emitter("foot_ring",
            duration=30, looping=False,
            start_lifetime=constant(14),
            start_speed=constant(0),
            start_size=nf3(constant(1.6), constant(0.5), constant(1.6)),
            start_color=color(VIOLET),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(2.0, 1.8, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 2.0, 4.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 2.6, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (c) the 8-block flash beam, 6 t only.
    beam = (fx.beam_emitter("flash_beam",
            duration=6, looping=False, end=(0.0, 8.0, 0.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, 0.86, 0.75, 1.0), (1.0, 0.5, 0.91, 0.94)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(2.4, 2.2, 2.6),
                                       blend=BLEND_ADDITIVE)))
    beam._config["width"] = curve(0.0, 0.7, [SEG_POP_SHRINK])
    beam.with_lights(sky=15, block=15)
    return fx


def build_pulse_hop() -> FxBuilder:
    """Cascade hop bead (12 t): one bright bead slides local z 0→−1 (executor scales
    z to the hop length, rotates to the target yaw) + 4 trail glints in its wake."""
    fx = FxBuilder("resonance_pulse_hop")
    root = fx.empty("hop")

    # The bead: velocity carries it 0→−1 local z over ~10 t (0.1/t × 10 t; the
    # executor z-scale turns that into the real hop length).
    (fx.particle_emitter("bead",
            duration=12, looping=False,
            start_lifetime=constant(10),
            start_speed=constant(1.0),
            start_size=nf3(random_between(0.30, 0.38)),
            start_color=color(PALE_LILAC),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(function_shape(x="0", y="0", z="0",
                                  speed_x="0", speed_y="0", speed_z="-0.1"))
       .with_material(texture_material(CIRCLE, hdr=(2.6, 2.3, 2.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-1.5, -1.5, -1.1), (1.5, 1.5, 0.1))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.15, 1.0), (0.85, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # 4 trail glints strewn along the path as the emitter time sweeps t 0→1.
    (fx.particle_emitter("trail_glints",
            duration=10, looping=False,
            start_lifetime=random_between(6, 9),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.16)),
            start_color=random_color(VIOLET, CYAN),
            simulation_space="Local", max_particles=6)
       .child_of(root)
       .with_emission(rate=constant(0.4))
       .with_shape(function_shape(x="0", y="0", z="-t"))
       .with_material(texture_material(CIRCLE, hdr=(2.0, 1.8, 2.2), blend=BLEND_ADDITIVE))
       .with_cull_box((-1.5, -1.5, -1.1), (1.5, 1.5, 0.1))
       .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=gradient(
                [(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))
    return fx


def build_fail_flicker() -> FxBuilder:
    """Fail sting at the altar (20 t): REVERSE_SUB dark pass ('the song curdles'),
    two red ring flickers, falling dissonance sparks — GLITCH palette."""
    fx = FxBuilder("resonance_fail_flicker")
    root = fx.empty("fail")

    # (a) the dark pass: REVERSE_SUB subtracts scene color under the smoke alpha.
    (fx.particle_emitter("dark_pass",
            duration=20, looping=False,
            start_lifetime=random_between(10, 16),
            start_speed=random_between(0.05, 0.15),
            start_size=nf3(random_between(0.9, 1.5)),
            start_color=color(VOID_INK),
            simulation_space="Local", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(sphere(radius=1.4, thickness=0.4))
       .with_material(texture_material(SMOKE,
                                       blend=blend("SRC_ALPHA", "ONE", "ONE", "ZERO",
                                                   "REVERSE_SUB")))
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 5.0, 4.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    # (b) red ring flicker — two pulses (t=0 and t=8).
    (fx.particle_emitter("red_rings",
            duration=20, looping=False,
            start_lifetime=constant(8),
            start_speed=constant(0),
            start_size=nf3(constant(2.2), constant(0.6), constant(2.2)),
            start_color=color(GLITCH_RED),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(1)),
                              burst(time=8, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(2.2, 0.7, 0.7), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 2.0, 4.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 1.8, [SEG_FLICKER_COMMIT]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.5, 0.3), (0.7, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=13))

    # (c) falling sparks — the melody drops dead to the ground.
    (fx.particle_emitter("dead_sparks",
            duration=20, looping=False,
            start_lifetime=random_between(12, 18),
            start_speed=random_between(0.15, 0.35),
            start_size=nf3(random_between(0.08, 0.14)),
            start_color=random_color(GLITCH_RED, EMBER_RED),
            simulation_space="World", max_particles=14)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(12))])
       .with_shape(sphere(radius=1.0, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 0.6, 0.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.0,
                      vertex_sorting="NONE", shade=False)
       .with_cull_box((-4.0, -3.0, -4.0), (4.0, 3.0, 4.0))
       .with_physics(collision=False, gravity=0.9)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=14, block=12))
    return fx


def build_finale_column() -> FxBuilder:
    """The finale mega-cue (160 t, staged in-asset 0/10/10/20 t): 120-block light
    column, 6-s glitter rain over the valley floor (collide + die), ground shock
    ring, crown starburst at the column head. maxParticles ≈ 700 total."""
    fx = FxBuilder("resonance_finale_column")
    root = fx.empty("finale")

    # (a) t=0 — the 120-block column, width 3→0 over the full 160 t.
    beam = (fx.beam_emitter("light_column",
            duration=160, looping=False, end=(0.0, 120.0, 0.0),
            emit_rate=constant(0), raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.95), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 0.86, 0.75, 1.0), (0.5, 0.62, 0.87, 1.0), (1.0, 0.5, 0.91, 0.94)]))
       .child_of(root)
       .with_material(texture_material(CIRCLE, discard=0.02, hdr=(3.0, 2.7, 3.2),
                                       blend=BLEND_ADDITIVE)))
    beam._config["width"] = curve(0.0, 3.0, [SEG_DECAY_TAIL])
    beam.with_lights(sky=15, block=15)

    # (b) t=10 — glitter rain: circle r=26 overhead, 5/t for 120 t (≈100/s · 6 s),
    # physics collide + removedWhenCollided (the rain LANDS — plan §4.3).
    (fx.particle_emitter("glitter_rain",
            duration=120, looping=False, start_delay=constant(10),
            start_lifetime=random_between(50, 90),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.22)),
            start_color=random_color(VIOLET, PALE_LILAC),
            # 480 ≤ the 512 CPU-sim comfort cap (LINT-MAXP-CPU) — physics forbids
            # GPU instancing, and 5/t × ~70 t life ≈ 350 alive keeps headroom anyway.
            simulation_space="World", max_particles=480)
       .child_of(root)
       .with_emission(rate=constant(5.0))
       .with_shape(circle(radius=26.0, thickness=1.0), position=(0.0, 34.0, 0.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.0, 1.8, 2.2), blend=BLEND_ADDITIVE))
       # NOTE: no use_gpu_instance here — physics (collide+die) and GPU instancing
       # are mutually exclusive (LINT-GPU-PHYSICS).
       .with_cull_box((-30.0, -4.0, -30.0), (30.0, 40.0, 30.0))
       .with_physics(collision=True, removed_when_collided=True, gravity=0.5)
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.1, 1.0), (0.9, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=14))

    # (c) t=10 — ground shock ring sweeping the valley floor.
    (fx.particle_emitter("shock_ring",
            duration=40, looping=False, start_delay=constant(10),
            start_lifetime=constant(24),
            start_speed=constant(0),
            start_size=nf3(constant(4.0), constant(1.2), constant(4.0)),
            start_color=color(CYAN),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot(), position=(0.0, 0.3, 0.0))
       .with_material(texture_material(RING_SOFT, hdr=(2.4, 2.2, 2.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-30.0, -2.0, -30.0), (30.0, 4.0, 30.0))
       .with_curves(
            size_over_lifetime=curve(1.0, 10.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # (d) t=20 — crown starburst at the column head (120 blocks up).
    (fx.particle_emitter("crown_burst",
            duration=60, looping=False, start_delay=constant(20),
            start_lifetime=random_between(24, 40),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.3, 0.6)),
            start_color=random_color(PALE_LILAC, CYAN),
            simulation_space="World", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(40))])
       .with_shape(sphere(radius=1.5, thickness=0.0), position=(0.0, 120.0, 0.0))
       .with_material(texture_material(STAR_2X2, hdr=(2.6, 2.4, 2.8), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-10.0, 110.0, -10.0), (10.0, 130.0, 10.0))
       .with_physics(collision=False, gravity=0.12)
       .with_curves(uv_animation=TWINKLE_FRAMES)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_wave_ring() -> FxBuilder:
    """W13-C3 resonance-wave front (90 t): one ground ring whose radius mirrors the
    server tremor front EXACTLY (0.45 blocks/t → r 36 at t 80, the ResonanceWaveFx
    contract) + a glint fringe born ON the moving front (function shape, t-swept
    radius). Pure ambient garnish — HDR capped at 1.45 (stacking law)."""
    fx = FxBuilder("resonance_wave_ring")
    root = fx.empty("wave")

    # (a) the front ring: diameter 2×(0→36) over the 80 t life — radius grows
    # 0.45 blocks/t, in lockstep with the server front that triggers the tremors.
    # NEAR-linear ease (LINT-LINEAR-CURVE): control points ride 0.035 off the chord —
    # curve deviation from the exact server front stays ≤ 0.6 blocks of radius.
    seg_front = (0.0, 0.0, 0.25, 0.30, 0.75, 0.70, 1.0, 1.0)
    (fx.particle_emitter("front_ring",
            duration=90, looping=False,
            start_lifetime=constant(80),
            start_speed=constant(0),
            start_size=nf3(constant(2.0), constant(0.6), constant(2.0)),
            start_color=color(DEEP_VIOLET),
            simulation_space="Local", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot(), position=(0.0, 0.3, 0.0))
       .with_material(texture_material(RING_SOFT, hdr=(1.4, 1.3, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-38.0, -3.0, -38.0), (38.0, 4.0, 38.0))
       .with_curves(
            size_over_lifetime=curve(0.0, 36.0, [seg_front], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.75, 0.40), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=13))

    # (b) glint fringe riding the front: motes born AT radius t·36 (the emitter-t
    # sweep matches the ring's linear growth), winking out within ~15 t so the wake
    # stays clean. ~7 alive at a time.
    (fx.particle_emitter("front_glints",
            duration=80, looping=False,
            start_lifetime=random_between(10, 18),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.18)),
            start_color=random_color(VIOLET, CYAN),
            simulation_space="Local", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.5))
       .with_shape(function_shape(
            x="cos(randomA*2*PI)*t*36",
            y="0.2+randomB*0.8",
            z="sin(randomA*2*PI)*t*36"))
       .with_material(texture_material(STAR_2X2, hdr=(1.45, 1.35, 1.45), blend=BLEND_ADDITIVE))
       .with_cull_box((-38.0, -2.0, -38.0), (38.0, 3.0, 38.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            size_over_lifetime=curve(0.0, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=13))
    return fx


BUILDERS = {
    "resonance_crystal_aura.fx": build_crystal_aura,
    "resonance_bahn.fx": build_bahn,
    "resonance_strike_burst.fx": build_strike_burst,
    "resonance_pulse_hop.fx": build_pulse_hop,
    "resonance_fail_flicker.fx": build_fail_flicker,
    "resonance_finale_column.fx": build_finale_column,
    "resonance_far_shaft.fx": build_far_shaft,
    "resonance_far_pulse.fx": build_far_pulse,
    "resonance_wave_ring.fx": build_wave_ring,
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
