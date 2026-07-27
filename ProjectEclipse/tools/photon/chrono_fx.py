#!/usr/bin/env python3
"""chrono_fx — WOAH-03 Chrono-Stasis Photon `.fx` assets (plan §4.3).

The frozen-time clearing's particle layer. The signature trick everywhere: FROZEN
particles are legal Photon (PHOTON_EDITOR_CAPABILITIES.md §2.2) — `startSpeed 0`, no
velocity/force/noise modules, physics off, `simulationSpace World` → every particle
hangs exactly at its spawn point until its lifetime turns it over (masked by an alpha
fade at both ends). Rows live in `woah.chronostasis.client.ChronoStasisFxRows`; the
loop windows are driven by `woah.chronostasis.client.ChronoRainField`.

Assets:

  chrono_rain_frozen     Loop, WINDOWED. One 24x18x24 world-space box of motionless,
                         vertically-stretched glitter droplets (VerticalBillboard —
                         StretchedBillboard stretches along velocity, and velocity is
                         ZERO here). 320 max; the client holds <=3 handles on a rolling
                         grid (~960 total, GPU-instanced). prewarm: the field stands
                         full the moment the window opens.
  chrono_dust_shimmer    Loop, WINDOWED. "Time dust": a sparse dot-sphere of tiny
                         winking motes around the camera. 60 max.
  chrono_sphere_idle     Loop, WINDOWED. Chronosphere corona: orbiting emission points
                         (circle shape, arc Loop + arcSpeed) painting a slow halo. 48 max.
  chrono_bolt_glow       Loop, WINDOWED. A 40-block glimmer column hugging the frozen
                         lightning bolt (cylinder shape, frozen motes). 90 max.
  chrono_jolt_pulse      One-shot. The time-jolt: an expanding horizontal ring + a
                         spark shell with stretched trails. Reused scaled-down (row
                         a < 0) as the tower-debris dust puff.
  chrono_discharge_burst One-shot. The resolution: multi-material shockwave ring
                         (additive HDR core + alpha smoke rim, shadow_bolt_impact
                         lineage), radial ember jets with physics, FirstCollision
                         sub-emitter chaining the jolt-pulse puff on the ground.
  chrono_rain_release    One-shot, ~4 s. The frozen rain FALLS: same box volume, but
                         the droplets drive hard downward and die on collision.
  chrono_far_pillar      Loop, WINDOWED. The far-tell (§4.5): a slim 60-block shimmer
                         column over the site, big cull box, visible from ~600 blocks.

Run:  python3 tools/photon/chrono_fx.py          # writes + validates all 8 assets
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

# --- palette (cool frozen-time identity: ice white / pale cyan / faint violet) ------
ICE_WHITE = 0xFFEAF4FF
PALE_CYAN = 0xFFB8E4FF
FROST_BLUE = 0xFF7FC4F0
DUSK_VIOLET = 0xFF9FA8E8
EMBER = 0xFFFFB36B
ASH_GRAY = 0xB0AAB2BC

# Rain volume (matches ChronoRainField.RAIN_CELL grid pitch of 16 — boxes overlap a bit).
RAIN_BOX = (24.0, 18.0, 24.0)

# The 2x2 star-sheet twinkle track (house pattern from wandfx2/wand_idle_stern).
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
# Loops (all WINDOWED — ChronoRainField owns the hysteresis windows)
# ===========================================================================
def build_rain_frozen() -> FxBuilder:
    """Motionless droplet field: the rain that never lands. Frozen-particle recipe:
    startSpeed 0, zero motion modules, world space — the turnover hides in a 0.4 s
    alpha ramp at both lifetime ends. Vertically stretched via startSize3D, NOT
    StretchedBillboard (that stretches along velocity — which is zero)."""
    fx = FxBuilder("chrono_rain_frozen")
    root = fx.empty("rain")

    (fx.particle_emitter("droplets",
            duration=160, looping=True, prewarm=160,
            start_lifetime=random_between(120, 200),
            start_speed=constant(0),
            start_size=nf3(constant(0.03), random_between(0.22, 0.34), constant(0.03)),
            start_color=random_color(ICE_WHITE, PALE_CYAN),
            simulation_space="World", max_particles=320)
       .child_of(root)
       .with_emission(rate=constant(2.0))
       .with_shape(box(), scale=RAIN_BOX)
       .with_material(texture_material(CIRCLE, hdr=(1.1, 1.2, 1.3), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", use_gpu_instance=True)
       .with_cull_box((-14.0, -11.0, -14.0), (14.0, 11.0, 14.0))
       .with_curves(
            # 0.4 s ≈ 8 t of a 120–200 t life ≈ 5% — invisible turnover at both ends.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.05, 0.8), (0.95, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=12, block=8))
    return fx


def build_dust_shimmer() -> FxBuilder:
    """Time dust: a sparse sphere of tiny motes around the camera, each pulsing its
    size very slowly. The interior counterpart of the grade's star-hash glitter."""
    fx = FxBuilder("chrono_dust_shimmer")
    root = fx.empty("dust")

    (fx.particle_emitter("motes",
            duration=120, looping=True, prewarm=120,
            start_lifetime=random_between(80, 140),
            start_speed=constant(0),
            start_size=nf3(random_between(0.02, 0.05)),
            start_color=random_color(ICE_WHITE, DUSK_VIOLET),
            simulation_space="World", max_particles=60)
       .child_of(root)
       .with_emission(rate=constant(0.55))
       .with_shape(sphere(radius=9.0, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 1.45, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-10.0, -10.0, -10.0), (10.0, 10.0, 10.0))
       .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0,
                [(0.0, 0.35, 0.2, 1.0, 0.5, 0.4, 0.75, 0.9), (0.75, 0.9, 0.85, 0.3, 0.95, 0.7, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.85, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_sphere_idle() -> FxBuilder:
    """Chronosphere corona: emission points ORBIT the ring plane (circle shape,
    ShapeArcMode Loop + arcSpeed) leaving slow-fading halo motes, plus a faint
    counter-tilted second band — gyroscope optics without an ara emitter."""
    fx = FxBuilder("chrono_sphere_idle")
    root = fx.empty("corona")

    (fx.particle_emitter("halo",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(40, 60),
            start_speed=constant(0),
            start_size=nf3(random_between(0.06, 0.12)),
            start_color=random_color(PALE_CYAN, DUSK_VIOLET),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.45))
       .with_shape(circle(radius=2.2, thickness=0.0, arc=360.0,
                          arc_mode="Loop", arc_speed=0.35))
       .with_material(texture_material(CIRCLE, hdr=(1.6, 1.8, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("band_tilt",
            duration=100, looping=True, prewarm=100,
            start_lifetime=random_between(30, 50),
            start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.08)),
            start_color=color(ICE_WHITE),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.3))
       .with_shape(circle(radius=1.6, thickness=0.0, arc=360.0,
                          arc_mode="Loop", arc_speed=-0.5),
                   rotation=(55.0, 0.0, 0.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.6, 1.8, 2.0), blend=BLEND_ADDITIVE))
       .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_bolt_glow() -> FxBuilder:
    """Glimmer column hugging the frozen bolt: white-blue frozen motes in a 40-block
    cylinder (r 0.8), denser sparkle accents on a thinner core."""
    fx = FxBuilder("chrono_bolt_glow")
    root = fx.empty("column")

    (fx.particle_emitter("glimmer",
            duration=140, looping=True, prewarm=140,
            start_lifetime=random_between(60, 110),
            start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.12)),
            start_color=random_color(ICE_WHITE, FROST_BLUE),
            simulation_space="World", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(0.7))
       .with_shape(cylinder(radius=0.8, thickness=1.0),
                   position=(0.0, 20.0, 0.0), scale=(1.0, 40.0, 1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 1.7, 1.9), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-3.0, -1.0, -3.0), (3.0, 42.0, 3.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.85, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("sparkle",
            duration=140, looping=True, prewarm=140,
            start_lifetime=random_between(24, 40),
            start_speed=constant(0),
            start_size=nf3(random_between(0.06, 0.1)),
            start_color=color(ICE_WHITE),
            simulation_space="World", max_particles=26)
       .child_of(root)
       .with_emission(rate=constant(0.5))
       .with_shape(cylinder(radius=0.35, thickness=1.0),
                   position=(0.0, 20.0, 0.0), scale=(1.0, 40.0, 1.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.8, 2.0, 2.2), blend=BLEND_ADDITIVE))
       .with_cull_box((-3.0, -1.0, -3.0), (3.0, 42.0, 3.0))
       .with_curves(
            uv_animation=TWINKLE_FRAMES,
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ===========================================================================
# One-shots (cue lane)
# ===========================================================================
def build_jolt_pulse() -> FxBuilder:
    """Time-jolt pulse: one expanding horizontal ring at chest height + a spark shell
    snapping outward with short stretched trails + a soft pop. Doubles (scaled-down by
    the row, a < 0) as the tower-debris ground puff."""
    fx = FxBuilder("chrono_jolt_pulse")
    root = fx.empty("pulse")

    # Expanding ring: a single flat ring sprite scaling out (Horizontal render mode).
    (fx.particle_emitter("ring",
            duration=30, looping=False,
            start_lifetime=constant(16), start_speed=constant(0),
            start_size=nf3(1.2),
            start_color=color(PALE_CYAN),
            simulation_space="World", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.6, 1.9, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.0, 6.0, [(0.0, 0.15, 0.2, 0.55, 0.6, 0.9, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # Spark shell: 30 sparks snapping outward, stretched along their velocity.
    (fx.particle_emitter("sparks",
            duration=30, looping=False,
            start_lifetime=random_between(8, 14),
            start_speed=random_between(0.5, 0.9),
            start_size=nf3(random_between(0.04, 0.08)),
            start_color=random_color(ICE_WHITE, FROST_BLUE),
            simulation_space="World", max_particles=30)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30))])
       .with_shape(sphere(radius=0.6, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.4, 1.7, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.2)
       .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                0.0, 1.0, [(0.0, 1.0, 0.4, 0.35, 0.7, 0.15, 1.0, 0.05)], "lifetime")),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.7, 0.6), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # Soft pop at the center.
    (fx.particle_emitter("pop",
            duration=30, looping=False,
            start_lifetime=constant(7), start_speed=constant(0),
            start_size=nf3(0.7), start_color=color(ICE_WHITE),
            simulation_space="World", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.8, 2.1, 2.4), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.3, 0.1, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_discharge_burst() -> FxBuilder:
    """The resolution payoff: shockwave ring (additive HDR core + alpha smoke rim —
    the shadow_bolt_impact multi-material lineage), an upward core flare, radial ember
    jets with physics whose first ground hit chains a jolt-pulse puff."""
    fx = FxBuilder("chrono_discharge_burst")
    root = fx.empty("burst")

    # Shockwave ring: two materials on one emitter — HDR core + soft alpha rim.
    (fx.particle_emitter("shockwave",
            duration=40, looping=False,
            start_lifetime=constant(22), start_speed=constant(0),
            start_size=nf3(2.0), start_color=color(PALE_CYAN),
            simulation_space="World", max_particles=2)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(2.0, 2.4, 2.8), blend=BLEND_ADDITIVE))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(
                0.0, 8.0, [(0.0, 0.1, 0.25, 0.6, 0.6, 0.9, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.5, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.7, 0.75, 0.85)]))
       .with_lights(sky=15, block=15))

    # Core flare: a hot column licking upward for a few ticks.
    (fx.particle_emitter("flare",
            duration=40, looping=False,
            start_lifetime=random_between(8, 14),
            start_speed=random_between(0.4, 0.9),
            start_size=nf3(random_between(0.2, 0.45)),
            start_color=random_color(ICE_WHITE, EMBER),
            simulation_space="World", max_particles=18)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12)),
                                                  burst(time=2, count=constant(6))])
       .with_shape(cone(angle=16.0, radius=0.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.8, 2.2, 2.6), blend=BLEND_ADDITIVE))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.6), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # Ember jets: physics debris fanning radially; the first ground contact chains
    # one scaled jolt-pulse puff (FirstCollision sub-emitter).
    (fx.particle_emitter("ember_jets",
            duration=40, looping=False,
            start_lifetime=random_between(20, 36),
            start_speed=random_between(0.7, 1.3),
            start_size=nf3(random_between(0.06, 0.13)),
            start_color=random_color(EMBER, ASH_GRAY),
            simulation_space="World", max_particles=36)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(24)),
                                                  burst(time=4, count=constant(12))])
       .with_shape(sphere(radius=0.8, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 1.5, 1.7), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5, length_scale=1.8)
       .with_physics(collision=True, removed_when_collided=False, gravity=1.1,
                     bounce_chance=0.35, bounce_rate=0.4)
       # Ground puffs chain the SHIPPED small dust puff (LINT-SUBEM-FAT: each stamp
       # deep-copies a runtime, so the child must stay <=8 burst particles).
       .with_sub_emitters(sub_emitter("eclipse:storm_dust_puff",
                                      event="FirstCollision", probability=0.25))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.75, 0.7), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_rain_release() -> FxBuilder:
    """'The rain falls all at once': the same box volume as the frozen field, but every
    droplet drives hard downward and dies on its first collision (~4 s window,
    front-loaded emission so the sky visibly EMPTIES)."""
    fx = FxBuilder("chrono_rain_release")
    root = fx.empty("release")

    (fx.particle_emitter("falling",
            duration=80, looping=False,
            start_lifetime=random_between(30, 60),
            start_speed=constant(0),
            start_size=nf3(constant(0.03), random_between(0.24, 0.36), constant(0.03)),
            start_color=random_color(ICE_WHITE, PALE_CYAN),
            simulation_space="World", max_particles=300)
       .child_of(root)
       .with_emission(rate=constant(2.0), bursts=[burst(time=0, count=constant(140)),
                                                  burst(time=8, count=constant(60))])
       .with_shape(box(), scale=RAIN_BOX)
       .with_material(texture_material(CIRCLE, hdr=(1.1, 1.2, 1.3), blend=BLEND_ADDITIVE))
       # No GPU instancing here: LINT-GPU-PHYSICS — collision physics runs CPU-side.
       .with_renderer(render_mode="VerticalBillboard")
       .with_cull_box((-14.0, -20.0, -14.0), (14.0, 11.0, 14.0))
       .with_physics(collision=True, removed_when_collided=True, gravity=0.0)
       .with_curves(
            velocity_over_lifetime=dict(linear=(0.0, -0.7, 0.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.06, 0.85), (0.9, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=12, block=8))
    return fx


def build_far_pillar() -> FxBuilder:
    """Far-tell shimmer pillar (§4.5): a slim frozen-mote column reaching 60 blocks over
    the site — Photon executors are client-side, so this reads from ~600 blocks where
    display entities are hard-capped by the 10-chunk tracking horizon."""
    fx = FxBuilder("chrono_far_pillar")
    root = fx.empty("pillar")

    (fx.particle_emitter("column",
            duration=160, looping=True, prewarm=160,
            start_lifetime=random_between(80, 140),
            start_speed=constant(0),
            start_size=nf3(random_between(0.5, 1.1)),
            start_color=random_color(ICE_WHITE, FROST_BLUE),
            simulation_space="World", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.3))
       .with_shape(box(), position=(0.0, 28.0, 0.0), scale=(2.0, 60.0, 2.0))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 1.65, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(use_gpu_instance=True)
       .with_cull_box((-4.0, -4.0, -4.0), (4.0, 60.0, 4.0))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.6), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


BUILDERS = {
    "chrono_rain_frozen.fx": build_rain_frozen,
    "chrono_dust_shimmer.fx": build_dust_shimmer,
    "chrono_sphere_idle.fx": build_sphere_idle,
    "chrono_bolt_glow.fx": build_bolt_glow,
    "chrono_jolt_pulse.fx": build_jolt_pulse,
    "chrono_discharge_burst.fx": build_discharge_burst,
    "chrono_rain_release.fx": build_rain_release,
    "chrono_far_pillar.fx": build_far_pillar,
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
