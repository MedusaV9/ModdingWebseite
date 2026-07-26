#!/usr/bin/env python3
"""CREDITS2 (F-056/F-058, polished by F-068) — authors the credits finale-rework Photon
assets with fxlib:

  eclipse:credits_collapse   F-058 island-shatter collapse veil over the breaking
                             sanctum island: a sluggish dark dust updraft, sparse
                             violet ember motes rising with the debris, one soft
                             expanding shock ring at the break beat — plus the F-068
                             polish layers: delayed trailing dust chasing the climbing
                             debris, two aftershock rings baked on the SAME act ticks
                             CreditsShatterAct kicks its fragments (AFTERSHOCK_AT =
                             150/300), and the altar-core flash + spark burst baked on
                             CORE_BREAK_TICK = 270 (~460t one-shot, fired once by
                             CreditsSequence at the island center)
  eclipse:black_hole_maw     F-056 the black-hole maw: two counter-rotating accretion
                             swirls (fast inner / lazy outer), infalling particle
                             streams pulled out of a wide shell, a thin hot
                             photon-ring rim glow — plus the F-068 polish layers:
                             stretched-billboard EMBER TRAILS dragging around the disc
                             rim and fast stretched STAR STREAKS pulled in from a wide
                             shell (the Photon-space cousins of the post shader's
                             Doppler ring + streak layers) (~340t one-shot, re-fired by
                             CreditsBlackHoleAct on a 300t cadence — the kneel-corona
                             sustain law keeps the seam gapless)

Authored scale: the maw is built around a ~26-block accretion radius (the act's
BLACK-HOLE visual radius); the collapse veil around the island's ~16-block ellipse.

Java-side tick contract (F-068): the baked burst times below MUST stay in lockstep with
CreditsShatterAct.AFTERSHOCK_AT ({150, 300}) and CreditsShatterAct.CORE_BREAK_TICK (270)
— the server fires the matching shake/flash beats on those exact act ticks.

Usage:  python3 tools/photon/credits2_fx.py            # write + validate both
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, burst, circle, constant, curve, cylinder,
    dot, gradient, nf3, random_between, sphere, texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Finale palette (the ferryman2 law): near-black violet body, mid, hot white-violet.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)


# ---------------------------------------------------------------------------
# 1. eclipse:credits_collapse — F-058 (dark, slow — the island exhales as it breaks)
# ---------------------------------------------------------------------------
def build_credits_collapse() -> FxBuilder:
    fx = FxBuilder("credits_collapse")
    root = fx.empty("collapse_root")

    # Dust updraft: a wide, slow column of near-black dust rising off the whole island
    # footprint — the debris displays climb through this curtain.
    (fx.particle_emitter(
            "collapse_dust",
            duration=440, looping=False, start_lifetime=random_between(80, 130),
            start_speed=constant(0.05),
            start_size=nf3(random_between(2.0, 4.0), random_between(2.0, 4.0),
                           random_between(2.0, 4.0)),
            simulation_space="Local", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(0.9))
        .with_shape(cylinder(radius=15.0, thickness=0.8))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.08), constant(0)),  # barely turning
                linear=nf3(constant(0), constant(0.14), constant(0))),  # slow climb
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (0.75, 0.35), (1.0, 0.0)],
                [(0.0, 0.14, 0.08, 0.2), (1.0, 0.07, 0.04, 0.12)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-24.0, -6.0, -24.0), (24.0, 30.0, 24.0)))

    # Ember motes: sparse violet sparks drifting up between the fragments.
    (fx.particle_emitter(
            "collapse_motes",
            duration=440, looping=False, start_lifetime=random_between(60, 100),
            start_speed=random_between(0.08, 0.2),
            start_size=nf3(random_between(0.12, 0.3)), max_particles=140)
        .child_of(root)
        .with_emission(rate=constant(1.6))
        .with_shape(cylinder(radius=13.0, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.12, 0.3), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.1, 0.85, 1.6)))
        .with_cull_box((-22.0, -6.0, -22.0), (22.0, 28.0, 22.0)))

    # One soft shock ring at the break beat: a single expanding disc flash.
    (fx.particle_emitter(
            "collapse_ring",
            duration=60, looping=False, start_lifetime=constant(36),
            start_speed=constant(0), start_size=nf3(8.0), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(0.9, 0.65, 1.4)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 6.0, [(0.0, 0.12, 1.0, 1.0, 0.35, 0.6, 1.0, 1.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.65), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-30.0, -6.0, -30.0), (30.0, 12.0, 30.0)))

    # F-068 trailing dust: a delayed, taller, longer-lived curtain chasing the debris
    # up — the "nachziehender Staub" behind the rising fragment field.
    (fx.particle_emitter(
            "collapse_trail_dust",
            duration=380, looping=False, start_delay=constant(40),
            start_lifetime=random_between(110, 170), start_speed=constant(0.04),
            start_size=nf3(random_between(2.6, 4.6), random_between(2.6, 4.6),
                           random_between(2.6, 4.6)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.55))
        .with_shape(cylinder(radius=12.0, thickness=0.7))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0)),
                linear=nf3(constant(0), random_between(0.2, 0.34), constant(0))),  # chases the debris
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.4), (0.8, 0.28), (1.0, 0.0)],
                [(0.0, 0.11, 0.06, 0.16), (1.0, 0.05, 0.03, 0.09)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-20.0, -6.0, -20.0), (20.0, 52.0, 20.0)))

    # F-068 aftershock rings: two softer echoes of the break ring, baked on the exact
    # act ticks CreditsShatterAct steps its fragments outward (AFTERSHOCK_AT = 150/300;
    # the server pairs them with shake + thunder on the same ticks).
    (fx.particle_emitter(
            "collapse_aftershock",
            duration=340, looping=False, start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(6.0), max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=150, count=constant(1)),
                               burst(time=300, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(0.8, 0.6, 1.25)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 4.5, [(0.0, 0.15, 1.0, 1.0, 0.35, 0.65, 1.0, 1.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-26.0, -6.0, -26.0), (26.0, 12.0, 26.0)))

    # F-068 altar-core flash: the heart of the island breaks LAST — one hot white-violet
    # pop over the dais, baked on CORE_BREAK_TICK = 270 (the server's light-flash beat).
    (fx.particle_emitter(
            "collapse_core_flash",
            duration=320, looping=False, start_lifetime=constant(24),
            start_speed=constant(0), start_size=nf3(3.0), max_particles=2)
        .child_of(root)
        .at(0.0, 5.0, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=270, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.6, 1.25, 2.2)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 3.2, [(0.0, 0.2, 1.0, 1.0, 0.3, 1.0, 1.0, 0.55)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.95), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-12.0, -2.0, -12.0), (12.0, 16.0, 12.0)))

    # F-068 core sparks: a single spray of hot motes ejecting with the core fragments.
    (fx.particle_emitter(
            "collapse_core_sparks",
            duration=320, looping=False, start_lifetime=random_between(30, 55),
            start_speed=random_between(0.35, 0.75),
            start_size=nf3(random_between(0.12, 0.28)), max_particles=30)
        .child_of(root)
        .at(0.0, 5.0, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=270, count=constant(26))])
        .with_shape(sphere(radius=1.6, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.16), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.9), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.0, 1.9)))
        .with_cull_box((-16.0, -4.0, -16.0), (16.0, 20.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:black_hole_maw — F-056 (rotating accretion swirls + infalling streams)
# ---------------------------------------------------------------------------
def build_black_hole_maw() -> FxBuilder:
    fx = FxBuilder("black_hole_maw")
    root = fx.empty("maw_root")

    # Inner accretion swirl: fast, hot, tight — the bright disc hugging the horizon.
    (fx.particle_emitter(
            "maw_swirl_inner",
            duration=340, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0.02),
            start_size=nf3(random_between(1.2, 2.4), random_between(1.2, 2.4),
                           random_between(1.2, 2.4)),
            simulation_space="Local", max_particles=120)
        .child_of(root)
        .with_emission(rate=constant(2.2))
        .with_shape(circle(radius=14.0, thickness=0.45))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.85), constant(0)),  # fast drag
                radial=constant(-0.16)),                                # falling in
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (0.6, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.0, 1.8)))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-30.0, -12.0, -30.0), (30.0, 12.0, 30.0)))

    # Outer accretion swirl: lazy, dark, wide — counter-rotating smoke band.
    (fx.particle_emitter(
            "maw_swirl_outer",
            duration=340, looping=False, start_lifetime=random_between(70, 110),
            start_speed=constant(0.02),
            start_size=nf3(random_between(2.2, 4.0), random_between(2.2, 4.0),
                           random_between(2.2, 4.0)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.9))
        .with_shape(circle(radius=26.0, thickness=0.4))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.28), constant(0)),  # counter-turn
                radial=constant(-0.07)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (0.8, 0.35), (1.0, 0.0)],
                [(0.0, 0.2, 0.1, 0.3), (1.0, 0.08, 0.04, 0.14)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-36.0, -14.0, -36.0), (36.0, 14.0, 36.0)))

    # Infalling streams: motes pulled from a wide shell straight into the center.
    (fx.particle_emitter(
            "maw_infall",
            duration=340, looping=False, start_lifetime=random_between(50, 90),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.15, 0.4)), max_particles=160)
        .child_of(root)
        .with_emission(rate=constant(2.0))
        .with_shape(sphere(radius=32.0, thickness=0.25))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.35), constant(0)),
                radial=constant(-0.5)),                                  # the pull
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (0.9, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, *VIOLET_HOT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.1, 0.9, 1.7)))
        .with_cull_box((-36.0, -36.0, -36.0), (36.0, 36.0, 36.0)))

    # Photon-ring rim glow: slow hot pulses hugging the event horizon.
    (fx.particle_emitter(
            "maw_rim",
            duration=340, looping=False, start_lifetime=constant(46),
            start_speed=constant(0), start_size=nf3(5.5), max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=6, count=constant(1), cycles=8, interval=42)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.4, 1.05, 2.0)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.4, [(0.0, 0.55, 0.8, 1.0, 0.6, 0.9, 1.0, 0.65)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-12.0, -12.0, -12.0), (12.0, 12.0, 12.0)))

    # F-068 ember trails: stretched-billboard embers dragging around the disc RIM —
    # fast orbital motion + a slow radial leak inward; the velocity stretch turns each
    # mote into a short glowing trail hugging the accretion edge.
    (fx.particle_emitter(
            "maw_ember_trails",
            duration=340, looping=False, start_lifetime=random_between(45, 75),
            start_speed=constant(0.02),
            start_size=nf3(random_between(0.22, 0.45)),
            simulation_space="Local", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(1.7))
        .with_shape(circle(radius=25.0, thickness=0.12))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.62), constant(0)),  # the rim drag
                radial=constant(-0.06)),                                 # slow leak in
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (0.6, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.35, 1.05, 1.9)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=2.6, vertex_sorting="DISTANCE")
        .with_cull_box((-32.0, -12.0, -32.0), (32.0, 12.0, 32.0)))

    # F-068 star streaks: fast stretched motes ripped out of a WIDE shell straight into
    # the center — the Photon-space cousin of the post shader's streak layer (stars
    # being pulled in from the space dome).
    (fx.particle_emitter(
            "maw_star_streaks",
            duration=340, looping=False, start_lifetime=random_between(28, 46),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.1, 0.22)), max_particles=120)
        .child_of(root)
        .with_emission(rate=constant(1.5))
        .with_shape(sphere(radius=36.0, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.18), constant(0)),
                radial=constant(-1.05)),                                 # the hard pull
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.85, 0.55), (1.0, 0.0)],
                [(0.0, 0.82, 0.72, 1.0), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.25, 1.05, 1.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.2,
                       length_scale=2.0)
        .with_cull_box((-40.0, -40.0, -40.0), (40.0, 40.0, 40.0)))
    return fx


BUILDERS = {
    "credits_collapse.fx": build_credits_collapse,
    "black_hole_maw.fx": build_black_hole_maw,
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
