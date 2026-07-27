#!/usr/bin/env python3
"""echo_grove_fx — WOAH-05 Echo-Grove Photon `.fx` assets (plan §4.2).

The misty hollow's particle layer: cold silver-blue at rest, gold while a memory
flood shows the past. Rows live in `client.echo.EchoPhotonFxRows`; the loop
windows are driven by `client.echo.EchoGroveFx` (grove loops) and
`client.echo.EchoOrbGlowFx` (orb attach loops).

Assets (plan §4.2 table; the `_lite`/`_lit` files are the sanctioned variants):

  echo_ground_fog      Loop, WINDOWED. Two layers of broad, slow fog schwaden
                       flat over the bowl floor (Horizontal billboards, 56x2x56
                       box, 12-18 s lives, weak 1D noise with a remap curve for
                       drift), 110 max, lights sky=6. Quasar fallback:
                       limbo_fogbank (REPLACE row).
  echo_spores          Loop, WINDOWED. GPU-instanced dust motes filling the
                       hollow (64x14x64 box, 1400 max — tier-2), tiny HDR ~1.6,
                       slow orbital drift + noise, size pulse, lights block=10.
  echo_spores_lite     The tier-0/1 variant: 400 max, lower rate (the row picks
                       the file at client-setup off FxBudget.qualityTier()).
  echo_tree_lights     Loop, WINDOWED. Memory-tree lights: (a) gold motes rising
                       through a r=3 h=10 cylinder at ~4/s, (b) star-glint winks
                       at 10 hashed crown offsets (function shape), HDR 2.0.
  echo_flood_bloom     One-shot ~160t. The flood's light: an HDR column of
                       vertically-stretched shafts over the tree (rise/hold/
                       decay alpha matching the flood timeline) + crown glint
                       bursts every 20t.
  echo_ash_fall        One-shot ~80t. The decay beat: gray flakes sifting down
                       from crown height (44x1x44 box, soft -Y force, slow roll,
                       physics OFF — they fall through the overlay displays).
  echo_bloom_rain      One-shot ~600t (finale). Petal rain over the tree
                       (petal_soft sprites — the mobs_fx petal school), physics
                       ON + removedWhenCollided, colorBySpeed gold->white.
  echo_whisper_wisp    One-shot 40t, ENTITY lane. Six soul wisps circling out
                       of a clicked orb, radial->orbital, alpha fade.
  echo_orb_glow        Attach-loop (EchoOrbGlowFx). Soft halo + two spark
                       orbits, 20 max — the cold waiting-orb look.
  echo_orb_glow_lit    The DATA_LIT variant: warmer gold, slightly livelier.
  echo_orb_collect     One-shot 20t. Collect implosion: an inverted sphere
                       shell (negative radial velocity), 40 glints, HDR 1.8.

Run:  python3 tools/photon/echo_grove_fx.py       # writes + validates all 11
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
PETAL = "eclipse:textures/particle/petal_soft.png"
WISP = "eclipse:textures/particle/wisp_white.png"

# --- palette (melancholic-beautiful: pale silver-blue rest / warm gold past) --------
MIST_WHITE = 0xFFE4EDF4
PALE_BLUE = 0xFFB8CCE0
SLATE_BLUE = 0xFF8FA3BC
GOLD_WARM = 0xFFE8C878
GOLD_BRIGHT = 0xFFF6DFA4
ASH_GRAY = 0xB0A9A6A0
ASH_DARK = 0x90807C76
PETAL_ROSE = 0xFFF4D8DC
PETAL_WHITE = 0xFFFDF6EE

# The 2x2 star-sheet twinkle track (house pattern from wandfx2/chrono).
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

# 10 hashed crown-light offsets (deterministic — mirrors the terraformer's static
# glimmer displays; x/z within the crown, y just under the leaf ball).
CROWN_OFFSETS = [
    (2.2, 9.4, -1.1), (-1.8, 10.2, 2.4), (0.6, 11.0, -2.6), (-2.9, 9.8, -0.7),
    (1.4, 10.6, 2.9), (3.1, 8.9, 1.6), (-0.9, 11.4, 0.3), (-2.2, 8.6, -2.3),
    (0.2, 9.1, 3.3), (2.7, 10.9, -2.0)]


def _crown_function_shape():
    """function_shape cycling the 10 hashed offsets off the emitter clock (t in
    ticks): a step-select via nested floor/mod keeps it pure-expression."""
    xs = "+".join(f"({x})*(floor(mod(t,10))=={i})" for i, (x, _, _) in enumerate(CROWN_OFFSETS))
    ys = "+".join(f"({y})*(floor(mod(t,10))=={i})" for i, (_, y, _) in enumerate(CROWN_OFFSETS))
    zs = "+".join(f"({z})*(floor(mod(t,10))=={i})" for i, (_, _, z) in enumerate(CROWN_OFFSETS))
    return function_shape(x=xs, y=ys, z=zs)


# ===========================================================================
# Loops (all WINDOWED — EchoGroveFx / EchoOrbGlowFx own the hysteresis windows)
# ===========================================================================
def build_ground_fog() -> FxBuilder:
    """Bowl mist: two layers of broad, slow-breathing schwaden hugging the floor.
    Horizontal render mode (the billboards LIE on the ground), weak 1D noise with
    a remap curve so banks drift instead of jittering."""
    fx = FxBuilder("echo_ground_fog")
    root = fx.empty("fog")

    (fx.particle_emitter("banks",
            duration=200, looping=True, prewarm=200,
            start_lifetime=random_between(240, 360),   # 12-18 s (plan §4.2 #1)
            start_speed=constant(0),
            start_size=nf3(random_between(5.0, 9.0)),
            start_color=random_color(MIST_WHITE, PALE_BLUE),
            simulation_space="World", max_particles=80)
       .child_of(root)
       .with_emission(rate=constant(0.22))            # ~4.4/s of 12-18 s lives
       .with_shape(box(), position=(0.0, 0.6, 0.0), scale=(56.0, 2.0, 56.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_cull_box((-32.0, -4.0, -32.0), (32.0, 32.0, 32.0))
       .with_curves(
            noise=dict(frequency=0.35, quality="Noise1D", position=(0.06, 0.0, 0.06),
                       remap_curve=curve(
                           0.0, 1.0,
                           [(0.0, 0.2, 0.35, 0.75, 0.65, 0.3, 1.0, 0.8)],
                           "lifetime")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.16), (0.85, 0.16), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=6, block=4))

    (fx.particle_emitter("wisps",
            duration=200, looping=True, prewarm=200,
            start_lifetime=random_between(160, 260),
            start_speed=constant(0),
            start_size=nf3(random_between(2.0, 3.6)),
            start_color=random_color(PALE_BLUE, SLATE_BLUE),
            simulation_space="World", max_particles=30)
       .child_of(root)
       .with_emission(rate=constant(0.12))
       .with_shape(box(), position=(0.0, 1.2, 0.0), scale=(44.0, 2.0, 44.0))
       .with_material(texture_material(WISP, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_cull_box((-32.0, -4.0, -32.0), (32.0, 32.0, 32.0))
       .with_curves(
            noise=dict(frequency=0.5, quality="Noise1D", position=(0.04, 0.0, 0.04)),
            rotation_over_lifetime=random_between(-0.12, 0.12),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.12), (0.8, 0.12), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=6, block=4))
    return fx


def _spores(name: str, max_particles: int, rate: float) -> FxBuilder:
    """Shared spore-mote recipe (full + _lite tiers, plan §4.2 #2)."""
    fx = FxBuilder(name)
    root = fx.empty("spores")

    (fx.particle_emitter("motes",
            duration=180, looping=True, prewarm=180,
            start_lifetime=random_between(140, 240),
            start_speed=constant(0),
            start_size=nf3(random_between(0.02, 0.045)),
            start_color=random_color(MIST_WHITE, PALE_BLUE),
            simulation_space="World", max_particles=max_particles)
       .child_of(root)
       .with_emission(rate=constant(rate))
       .with_shape(box(), position=(0.0, 6.0, 0.0), scale=(64.0, 14.0, 64.0))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 1.6, 1.7), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-34.0, -4.0, -34.0), (34.0, 16.0, 34.0))
       .with_curves(
            velocity_over_lifetime=dict(orbital=(0.0, 0.02, 0.0), linear=(0.0, 0.008, 0.0)),
            noise=dict(frequency=0.4, quality="Noise2D", position=(0.02, 0.01, 0.02)),
            size_over_lifetime=curve(
                0.0, 1.0,
                [(0.0, 0.0, 0.12, 1.0, 0.5, 0.55, 0.75, 0.9),
                 (0.75, 0.9, 0.85, 0.6, 0.95, 0.2, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.75), (0.85, 0.75), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=8, block=10))
    return fx


def build_spores() -> FxBuilder:
    return _spores("echo_spores", 1400, 6.0)


def build_spores_lite() -> FxBuilder:
    return _spores("echo_spores_lite", 400, 1.8)


def build_tree_lights() -> FxBuilder:
    """Memory-tree lights: gold motes rising through the trunk column + star-glint
    winks at the 10 hashed crown offsets (the static glimmer displays' sparkle)."""
    fx = FxBuilder("echo_tree_lights")
    root = fx.empty("tree")

    (fx.particle_emitter("rising_motes",
            duration=160, looping=True, prewarm=160,
            start_lifetime=random_between(60, 110),
            start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.08)),
            start_color=random_color(GOLD_WARM, GOLD_BRIGHT),
            simulation_space="World", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.2))             # ~4/s (plan §4.2 #3a)
       .with_shape(cylinder(radius=3.0, thickness=1.0),
                   position=(0.0, 0.0, 0.0), scale=(1.0, 10.0, 1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.9, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-6.0, -8.0, -6.0), (6.0, 10.0, 6.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=(0.0, 0.035, 0.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("crown_glints",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(20, 34),
            start_speed=constant(0),
            start_size=nf3(random_between(0.08, 0.14)),
            start_color=color(GOLD_BRIGHT),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=6, count=constant(1), cycles=16, interval=6,
                                    probability=0.8)])
       .with_shape(_crown_function_shape())
       .with_material(texture_material(STAR_2X2, hdr=(1.9, 2.0, 2.1), blend=BLEND_ADDITIVE))
       .with_cull_box((-6.0, -8.0, -6.0), (6.0, 14.0, 6.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ===========================================================================
# One-shots (cue lane)
# ===========================================================================
def build_flood_bloom() -> FxBuilder:
    """The flood's light (plan §4.2 #4): a soft HDR column of vertically-stretched
    shafts standing over the memory tree for the whole 160t window (rise/hold/
    decay via the emission envelope + per-particle fades) plus gold crown-glint
    bursts every 20t. The frozen-shaft trick: startSpeed 0 + startSize3D stretch
    (StretchedBillboard would need velocity — there is none)."""
    fx = FxBuilder("echo_flood_bloom")
    root = fx.empty("bloom")

    (fx.particle_emitter("light_column",
            duration=160, looping=False,
            start_lifetime=random_between(50, 80),
            start_speed=constant(0),
            start_size=nf3(constant(0.35), random_between(8.0, 14.0), constant(0.35)),
            start_color=random_color(GOLD_WARM, GOLD_BRIGHT),
            simulation_space="World", max_particles=40)
       .child_of(root)
       # Rise: front bursts; hold: steady trickle; decay: emission ends ~t120 and
       # the last 50-80t lives carry the fade past t140 (the ash beat).
       .with_emission(rate=curve(
                0.0, 0.5,
                [(0.0, 0.7, 0.2, 0.5, 0.75, 0.4, 1.0, 0.0)], "duration"),
            bursts=[burst(time=0, count=constant(8)), burst(time=10, count=constant(6))])
       .with_shape(cylinder(radius=2.2, thickness=1.0),
                   position=(0.0, 15.0, 0.0), scale=(1.0, 30.0, 1.0))
       .with_material(texture_material(CIRCLE, hdr=(2.0, 2.2, 2.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", use_gpu_instance=True)
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 34.0, 8.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("crown_glints",
            duration=160, looping=False,
            start_lifetime=random_between(16, 28),
            start_speed=random_between(0.02, 0.06),
            start_size=nf3(random_between(0.1, 0.18)),
            start_color=color(GOLD_BRIGHT),
            simulation_space="World", max_particles=60)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(6), cycles=7, interval=20)])
       .with_shape(box(), position=(0.0, 11.0, 0.0), scale=(10.0, 3.0, 10.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.9, 2.0, 2.1), blend=BLEND_ADDITIVE))
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 34.0, 8.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_ash_fall() -> FxBuilder:
    """The decay beat (plan §4.2 #5): gray ash sifting down from crown height while
    the overlays shrink home. Physics OFF on purpose — flakes must fall THROUGH
    the parked display shells; a soft -Y force + slow roll instead."""
    fx = FxBuilder("echo_ash_fall")
    root = fx.empty("ash")

    (fx.particle_emitter("flakes",
            duration=80, looping=False,
            start_lifetime=random_between(50, 80),
            start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.09)),
            start_color=random_color(ASH_GRAY, ASH_DARK),
            simulation_space="World", max_particles=300)
       .child_of(root)
       .with_emission(rate=constant(1.5),
                      bursts=[burst(time=0, count=constant(90)),
                              burst(time=10, count=constant(60))])
       .with_shape(box(), scale=(44.0, 1.0, 44.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-24.0, -22.0, -24.0), (24.0, 4.0, 24.0))
       .with_curves(
            force_over_lifetime=dict(force=(0.0, -0.012, 0.0), simulation_space="World"),
            rotation_over_lifetime=random_between(-0.35, 0.35),
            noise=dict(frequency=0.6, quality="Noise1D", position=(0.02, 0.0, 0.02)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.6), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=10, block=6))
    return fx


def build_bloom_rain() -> FxBuilder:
    """Finale petal rain (plan §4.2 #6): pink-white petals sailing down over the
    tree for ~30 s, dying where they land (physics + removedWhenCollided);
    colorBySpeed leans the fast ones gold, the drifting ones white."""
    fx = FxBuilder("echo_bloom_rain")
    root = fx.empty("rain")

    (fx.particle_emitter("petals",
            duration=600, looping=False,
            start_lifetime=random_between(80, 160),
            start_speed=constant(0),
            start_size=nf3(random_between(0.07, 0.13)),
            start_color=random_color(PETAL_ROSE, PETAL_WHITE),
            simulation_space="World", max_particles=220)
       .child_of(root)
       .with_emission(rate=curve(
                0.0, 1.6,
                [(0.0, 0.5, 0.1, 1.0, 0.8, 0.8, 1.0, 0.0)], "duration"),
            bursts=[burst(time=0, count=constant(30))])
       .with_shape(box(), position=(0.0, 14.0, 0.0), scale=(20.0, 1.0, 20.0))
       .with_material(texture_material(PETAL, blend=BLEND_ALPHA))
       # No GPU instancing: LINT-GPU-PHYSICS — collision physics runs CPU-side.
       .with_renderer(vertex_sorting="DISTANCE")
       .with_physics(collision=True, removed_when_collided=True, gravity=0.10,
                     friction=1.0)
       .with_cull_box((-14.0, -18.0, -14.0), (14.0, 16.0, 14.0))
       .with_curves(
            rotation_over_lifetime=random_between(-1.2, 1.2),
            noise=dict(frequency=0.5, quality="Noise2D", position=(0.05, 0.0, 0.05)),
            color_by_speed=dict(
                color=gradient([(0.0, 1.0)], [(0.0, 1.0, 0.98, 0.94), (1.0, 0.95, 0.82, 0.55)]),
                range=(0.02, 0.3)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.06, 0.95), (0.9, 0.95), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=13, block=10))
    return fx


def build_whisper_wisp() -> FxBuilder:
    """Orb whisper (plan §4.2 #7, ENTITY lane — rides the clicked orb): six soul
    wisps easing out radially, then curling into a small orbit as they fade."""
    fx = FxBuilder("echo_whisper_wisp")
    root = fx.empty("whisper")

    (fx.particle_emitter("wisps",
            duration=40, looping=False,
            start_lifetime=random_between(24, 36),
            start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.16)),
            start_color=random_color(MIST_WHITE, PALE_BLUE),
            simulation_space="World", max_particles=6)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(sphere(radius=0.15, thickness=0.0))
       .with_material(texture_material(WISP, hdr=(1.3, 1.4, 1.5), blend=BLEND_ADDITIVE))
       .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0))
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(0.0, 0.08,
                             [(0.0, 1.0, 0.4, 0.35, 0.7, 0.1, 1.0, 0.0)], "lifetime"),
                orbital=(0.0, 0.10, 0.0)),
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.4, 0.25, 1.0, 0.75, 0.8, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def _orb_glow(name: str, halo_argb: int, spark_a: int, spark_b: int,
              orbital_speed: float) -> FxBuilder:
    """Shared orb-glow recipe (cold + _lit variants, plan §4.2 #8): one breathing
    halo sprite + two spark orbits, 20 particles hard max."""
    fx = FxBuilder(name)
    root = fx.empty("glow")

    (fx.particle_emitter("halo",
            duration=80, looping=True, prewarm=80,
            start_lifetime=constant(40),
            start_speed=constant(0),
            start_size=nf3(random_between(0.5, 0.6)),
            start_color=color(halo_argb),
            simulation_space="World", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.05))
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.4, 1.5, 1.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0,
                [(0.0, 0.55, 0.25, 1.0, 0.6, 0.7, 1.0, 0.55)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("spark_orbits",
            duration=80, looping=True, prewarm=80,
            start_lifetime=random_between(30, 50),
            start_speed=constant(0),
            start_size=nf3(random_between(0.03, 0.06)),
            start_color=random_color(spark_a, spark_b),
            simulation_space="Local", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.3))
       .with_shape(circle(radius=0.4, thickness=0.2))
       .with_material(texture_material(STAR_2X2, hdr=(1.6, 1.7, 1.8), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            velocity_over_lifetime=dict(orbital=(0.0, orbital_speed, 0.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_orb_glow() -> FxBuilder:
    return _orb_glow("echo_orb_glow", 0x66B8CCE0, MIST_WHITE, PALE_BLUE, 0.10)


def build_orb_glow_lit() -> FxBuilder:
    return _orb_glow("echo_orb_glow_lit", 0x77E8C878, GOLD_WARM, GOLD_BRIGHT, 0.16)


def build_orb_collect() -> FxBuilder:
    """Collect implosion (plan §4.2 #9): a sphere shell of glints RUSHING INWARD
    (negative radial velocity) and a soft center pop as the memory becomes a mote."""
    fx = FxBuilder("echo_orb_collect")
    root = fx.empty("collect")

    (fx.particle_emitter("indraw",
            duration=20, looping=False,
            start_lifetime=random_between(10, 16),
            start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.10)),
            start_color=random_color(MIST_WHITE, GOLD_BRIGHT),
            simulation_space="World", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(40))])
       .with_shape(sphere(radius=1.2, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.7, 1.8, 1.9), blend=BLEND_ADDITIVE))
       .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            velocity_over_lifetime=dict(
                radial=curve(-0.22, 0.0,
                             [(0.0, 0.6, 0.25, 0.35, 0.6, 0.1, 1.0, 0.0)], "lifetime")),
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 1.0, 0.4, 0.85, 0.7, 0.6, 1.0, 0.1)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.8, 0.7), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("pop",
            duration=20, looping=False,
            start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(0.45), start_color=color(GOLD_BRIGHT),
            simulation_space="World", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=6, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.7, 1.8, 1.9), blend=BLEND_ADDITIVE))
       .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0))
       .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.2, 0.2, 0.9, 0.5, 1.0, 1.0, 0.0)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "echo_ground_fog.fx": build_ground_fog,
    "echo_spores.fx": build_spores,
    "echo_spores_lite.fx": build_spores_lite,
    "echo_tree_lights.fx": build_tree_lights,
    "echo_flood_bloom.fx": build_flood_bloom,
    "echo_ash_fall.fx": build_ash_fall,
    "echo_bloom_rain.fx": build_bloom_rain,
    "echo_whisper_wisp.fx": build_whisper_wisp,
    "echo_orb_glow.fx": build_orb_glow,
    "echo_orb_glow_lit.fx": build_orb_glow_lit,
    "echo_orb_collect.fx": build_orb_collect,
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
