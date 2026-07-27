#!/usr/bin/env python3
"""woah_dome_fx — WOAH-01 MANSION GLITCH DOME Photon `.fx` assets (plan §4.4).

Four assets riding the `DomeCues` cue ids (rows in the NEW registrar
`woah/mansiondome/client/MansionDomeFxRows`, NOT in the frozen FxCues/veilfx files):

  dome_device_idle.fx    LOOP (WINDOWED, 48-block window owned by MansionDomeClient) —
                         green core motes glimmering off the emitter core + short
                         noise-strip arc flickers racing the copper rings. Never
                         payload-fired (WINDOWED law).
  dome_beam_base.fx      LOOP (WINDOWED) — the suction updraft INTO the sky beam:
                         accelerating motes climbing a 0.5-radius column + a faint
                         rotating intake disc at the antenna.
  dome_device_hit.fx     BURST — melee hit feedback: radial glitch-shard sparks
                         (green/white) + ONE 1-frame static billboard. The Java leg
                         layers a second, larger instance when the device is nearly
                         dead (a <= 3/8) or on the death beat (b >= 0.5).
  dome_shatter_burst.fx  BURST — the t30 shell payoff, authored at shell radius 8
                         (DomeCues.SHATTER_AUTHORED_RADIUS); the row scales the
                         executor by a/8 (the CUE_STRUCTURE_SLAM law): horizontal
                         shock ring 4->16, 90-shard cone rain, one dome afterglow.

Identity: dome green (0.30, 0.95, 0.62) — the SAME green as DomeShellRenderer /
DomeBeamRenderer / the glitch_dome + dome_shell pipelines, so every layer of the
feature reads as one energy system.

Run:  python3 tools/photon/woah_dome_fx.py          # writes + validates all 4 assets
(write() round-trip-validates; every .fx gets its .fxproj sibling — binary-diff law.)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

STAR_2X2 = "eclipse:textures/particle/star_2x2.png"       # 4-point-star twinkle flipbook
NOISE_STRIP = "eclipse:textures/particle/noise_strip.png"  # horizontal noise band (arcs)
BEAM_CORE = "eclipse:textures/particle/beam_core.png"      # soft vertical gradient bar
GLITCH_SHARD = "eclipse:textures/particle/glitch_shard.png"  # hard-edged pixel shard
STATIC_4X4 = "eclipse:textures/particle/static_4x4.png"   # 4x4 CRT-static flipbook
RING_SOFT = "eclipse:textures/particle/ring_soft.png"      # soft annulus (shock ring)
DOME_FAINT = "eclipse:textures/particle/dome_faint.png"    # faint hemisphere shell

# --- palette (DomeShellRenderer GREEN_R/G/B = 0.30/0.95/0.62 -> 0x4DF29E) -----------
DOME_GREEN = 0xFF4DF29E   # the shell/beam/pipeline green
DOME_PALE = 0xFFD9FFE8    # COR_PALE — near-white green highlight
DOME_DEEP = 0xFF1E7A50    # shadow green (spark tails)
WHITE_HOT = 0xFFF2FFF8    # hot core white

# --- sync contracts (keep in step with the Java side) ------------------------------
# DomeCues.SHATTER_AUTHORED_RADIUS — the shell radius this file is authored at; the
# MansionDomeFxRows leg scales the executor by (cue a) / AUTHORED_RADIUS.
AUTHORED_RADIUS = 8.0
# MansionDomeService fires CUE_DOME_DEVICE_HIT with a = hitsRemaining / 8.
MAX_HITS = 8

# The 2x2 star-sheet twinkle track (wandfx2 house pattern).
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


def rand_size3(lo, hi):
    """Per-axis random start size (the house nf3(random, random, random) idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


# ===========================================================================
# dome_device_idle — WINDOWED loop: core glimmer + ring arc flickers
# ===========================================================================
def build_device_idle() -> FxBuilder:
    """Idle loop at the emitter device (plan §4.4 row 1): green star motes bleeding
    off the core sphere and drifting up + 1-frame noise-strip arcs whipping around
    the copper rings every half second. Runs ONLY inside the 48-block window."""
    fx = FxBuilder("dome_device_idle")
    root = fx.empty("device_idle")

    # E1 core_motes: born on the core shell (r 0.6 at ring height), rising slowly,
    # twinkling out. Rate 6/s = 0.3/t, life 1.2-1.8 s = 24-36 t.
    (fx.particle_emitter("core_motes",
            duration=60, looping=True, prewarm=20,
            start_lifetime=random_between(24, 36),
            start_speed=random_between(0.005, 0.015),
            start_size=rand_size3(0.05, 0.10),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .at(0.0, 1.6, 0.0)
       .with_emission(rate=constant(0.3))
       .with_shape(sphere(radius=0.6, thickness=0.2))
       .with_material(texture_material(STAR_2X2, hdr=(0.7, 1.6, 1.0), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.5, -2.0, -2.5), (2.5, 3.5, 2.5))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.015, 0.025), constant(0))),
            size_over_lifetime=curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(  # plan: alpha 0 -> 1 -> 0, green
                [(0.0, 0.0), (0.25, 1.0), (0.75, 0.7), (1.0, 0.0)],
                [(0.0, 0.85, 1.0, 0.93), (0.6, 0.30, 0.95, 0.62), (1.0, 0.12, 0.48, 0.31)]))
       .with_lights(sky=15, block=15))

    # E2 ring_arcs: 2 short-lived stretched noise strips whipping around the ring
    # plane every 10 t (0.5 s), orbital velocity around Y — electric arc reads.
    (fx.particle_emitter("ring_arcs",
            duration=60, looping=True, prewarm=0,
            start_lifetime=constant(8), start_speed=constant(0),
            start_size=rand_size3(0.18, 0.30),
            start_color=random_color(DOME_GREEN, DOME_PALE),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .at(0.0, 1.6, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(2), cycles=6, interval=10)])
       .with_shape(circle(radius=0.9, thickness=0.1))
       .with_material(texture_material(NOISE_STRIP, hdr=(0.8, 1.8, 1.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.55, length_scale=2.4)
       .with_cull_box((-2.5, -2.0, -2.5), (2.5, 3.5, 2.5))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(1.6, 2.4), constant(0))),
            size_over_lifetime=curve(0.3, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ===========================================================================
# dome_beam_base — WINDOWED loop: suction updraft into the sky beam
# ===========================================================================
def build_beam_base() -> FxBuilder:
    """Beam-base loop (plan §4.4 row 2): motes born in a 0.5-radius column above the
    antenna, ACCELERATING upward (2.5 -> 6 b/s over life, i.e. 0.125 -> 0.3 b/t) and
    shrinking to nothing — the visual of matter being drunk by the beam — plus a
    faint intake disc spinning at the antenna mouth so the base has a body."""
    fx = FxBuilder("dome_beam_base")
    root = fx.empty("beam_base")

    # E1 updraft: rate 10/s = 0.5/t, life 2.5 s = 50 t, size 0.12 -> 0.
    (fx.particle_emitter("updraft",
            duration=50, looping=True, prewarm=40,
            start_lifetime=constant(50),
            start_speed=constant(0),
            start_size=nf3(0.12),
            start_color=random_color(DOME_GREEN, DOME_PALE),
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .at(0.0, 2.4, 0.0)
       .with_emission(rate=constant(0.5))
       .with_shape(cylinder(radius=0.5, thickness=1.0))
       .with_material(texture_material(BEAM_CORE, hdr=(0.8, 1.9, 1.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.8, length_scale=2.2)
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 14.0, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(0.125, 0.3, [SEG_SMOOTH_UP], "lifetime"),
                           constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.0), (0.15, 0.9), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # E2 intake_disc: one soft ring breathing/rotating at the antenna mouth.
    (fx.particle_emitter("intake_disc",
            duration=50, looping=True, prewarm=10,
            start_lifetime=constant(24), start_speed=constant(0),
            start_size=nf3(1.1),
            start_color=color(DOME_GREEN),
            simulation_space="Local", max_particles=6)
       .child_of(root)
       .at(0.0, 2.45, 0.0)
       .with_emission(rate=constant(0.084))  # ~2 alive: seamless cross-fade
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(0.6, 1.4, 0.9), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 14.0, 2.0))
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(3.0)),
            size_over_lifetime=curve(0.75, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.0), (0.3, 0.35), (0.7, 0.3), (1.0, 0.0)],
                                         [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ===========================================================================
# dome_device_hit — BURST: melee hit sparks + 1-frame static blink
# ===========================================================================
def build_device_hit() -> FxBuilder:
    """Hit feedback (plan §4.4 row 3): 12 radial glitch shards (green/white, gravity,
    0.5-0.8 s) + ONE big single-frame static billboard — the device 'loses signal'
    for a frame. The 'more broken = more sparks' scaling lives in the Java leg
    (MansionDomeFxRows.hitSparks layers a 1.35x second instance), NOT here: Photon
    assets are static."""
    fx = FxBuilder("dome_device_hit")
    root = fx.empty("device_hit")

    # E1 sparks: radial speed 4-7 b/s = 0.2-0.35 b/t off a tight shell, falling.
    (fx.particle_emitter("sparks",
            duration=22, looping=False,
            start_lifetime=random_between(10, 16),
            start_speed=random_between(0.2, 0.35),
            start_size=rand_size3(0.08, 0.16),
            start_color=random_color(DOME_GREEN, WHITE_HOT),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
       .with_shape(sphere(radius=0.4, thickness=0.0))
       .with_material(texture_material(GLITCH_SHARD, hdr=(0.9, 2.0, 1.3), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=False, gravity=0.25, bounce_chance=0.0)
       .with_curves(
            rotation_over_lifetime=dict(roll=random_between(-14.0, 14.0)),
            size_over_lifetime=curve(0.25, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 1.0, 0.97), (0.5, 0.30, 0.95, 0.62), (1.0, 0.12, 0.48, 0.31)]))
       .with_lights(sky=15, block=15))

    # E2 glitch_frame: one 1.4-block static billboard for 3 ticks — the signal drop.
    (fx.particle_emitter("glitch_frame",
            duration=22, looping=False,
            start_lifetime=constant(3), start_speed=constant(0),
            start_size=nf3(1.4),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .at(0.0, 1.6, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(STATIC_4X4, hdr=(0.8, 1.6, 1.1), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)],
                                         [(0.0, 0.55, 1.0, 0.78)])))
    return fx


# ===========================================================================
# dome_shatter_burst — BURST: the t30 shell payoff (authored at radius 8)
# ===========================================================================
def build_shatter_burst() -> FxBuilder:
    """Shell shatter (plan §4.4 row 4), authored at shell radius 8 — the row scales
    the WHOLE executor by shellRadius/8 (a real 48-radius dome plays this 6x):
    E1 horizontal shock ring snapping 4 -> 16 blocks, E2 90 glitch shards fountaining
    up and out of a 40-degree cone and raining back down, E3 one faint dome afterglow
    swelling 10 -> 18 and breathing out over 2 s."""
    fx = FxBuilder("dome_shatter_burst")
    root = fx.empty("shatter")

    # E1 ring_shock: one annulus popping to the authored shell diameter (16).
    (fx.particle_emitter("ring_shock",
            duration=18, looping=False,
            start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(4.0),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.0, 2.4, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.25, 1.0, [(0.0, 0.0, 0.12, 0.85, 0.5, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],  # plan: alpha 1 -> 0
                                         [(0.0, 0.55, 1.0, 0.78), (1.0, 0.30, 0.95, 0.62)]))
       .with_lights(sky=15, block=15))

    # E2 shard_rain: 90 shards, 40-degree cone up, 1.5-2.5 s, gravity, no collision.
    (fx.particle_emitter("shard_rain",
            duration=56, looping=False,
            start_lifetime=random_between(30, 50),
            start_speed=random_between(0.5, 0.9),
            start_size=rand_size3(0.10, 0.22),
            start_color=random_color(DOME_GREEN, DOME_PALE),
            simulation_space="World", max_particles=96)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(60)),
                                                  burst(time=2, count=constant(30))])
       .with_shape(cone(angle=40.0, radius=2.0))
       .with_material(texture_material(GLITCH_SHARD, hdr=(0.9, 2.0, 1.3), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=False, gravity=0.5, bounce_chance=0.0)
       .with_curves(
            rotation_over_lifetime=dict(roll=random_between(-18.0, 18.0)),
            size_over_lifetime=curve(0.3, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.75, 0.7), (1.0, 0.0)],
                [(0.0, 0.9, 1.0, 0.94), (0.5, 0.30, 0.95, 0.62), (1.0, 0.12, 0.48, 0.31)]))
       .with_lights(sky=15, block=15))

    # E3 afterglow: one faint hemisphere swelling 10 -> 18, alpha 0.5 -> 0 over 2 s.
    (fx.particle_emitter("afterglow",
            duration=46, looping=False,
            start_lifetime=constant(40), start_speed=constant(0),
            start_size=nf3(10.0),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, hdr=(0.7, 1.5, 1.0), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(0.556, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.5), (0.6, 0.25), (1.0, 0.0)],
                [(0.0, 0.45, 1.0, 0.7), (1.0, 0.30, 0.95, 0.62)])))
    return fx


BUILDERS = {
    "dome_device_idle.fx": build_device_idle,
    "dome_beam_base.fx": build_beam_base,
    "dome_device_hit.fx": build_device_hit,
    "dome_shatter_burst.fx": build_shatter_burst,
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
