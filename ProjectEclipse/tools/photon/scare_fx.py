#!/usr/bin/env python3
"""SCARE (F-064/F-065) — authors the two camera-anchored Photon assets the client
ScareDirector spawns right in front of the player's face (client/scare/ScareScripts):

  eclipse:scare_swarm    a soul-green mote SWARM that erupts and buzzes around a point
                         2.5-4 blocks ahead of the camera — a tight chittering core
                         cloud, stretched rush-streaks blowing outward PAST the camera,
                         one dark announcing puff, and a few lingering stragglers.
                         Fired by the `swarm` jumpscare (twice, staggered) and once,
                         smaller, by `soul_leak` (~70 t one-shot).
  eclipse:scare_wraith   a pale fleeting apparition for `phantom_swoop`: a bone-white
                         smoke smear that SURGES upward through the view with whipping
                         stretched streaks, one hot core pop, then dark tatters sinking
                         away (~55 t one-shot).

Authoring constraints (why these look the way they do):
  * ScareDirector.spawnPhoton places the FX at camera + view offsets but does NOT
    rotate it toward the camera — the world orientation vs. the view is unknown. So
    both effects only use camera-safe motion: radial bursts (read from any angle) and
    vertical surges (up is up for every camera). No lateral "screen-space" sweeps.
  * Spawned 2.5-4.0 blocks ahead at script scale 0.6-1.2 → authored radii stay ≤ ~2.5
    blocks so the cloud fills the view without clipping into the near plane.
  * Both are ONE-SHOTS (looping=False + bursts) — the scare system never loops FX.

Usage:  python3 tools/photon/scare_fx.py            # write + validate both
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, SEG_DECAY_TAIL, SEG_EASE_OUT_CREST,
    SEG_POP_SHRINK, burst, constant, curve, dot, gradient, nf3, random_between,
    sphere, texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Swarm palette — soul-fire green/cyan, sits with the `swarm` script's green outline
# pulse AND `soul_leak`'s cyan void grade.
SOUL_HOT = (0.45, 1.0, 0.82)
SOUL_MID = (0.14, 0.55, 0.42)
SOUL_DEEP = (0.03, 0.16, 0.11)

# Wraith palette — cold bone-white with a blue-violet edge (the smear_ghost overlay
# that follows it in `phantom_swoop` is the same family).
BONE_HOT = (0.92, 0.95, 1.0)
BONE_MID = (0.55, 0.58, 0.74)
BONE_DEEP = (0.09, 0.09, 0.16)


# ---------------------------------------------------------------------------
# 1. eclipse:scare_swarm — chittering mote swarm rushing the camera
# ---------------------------------------------------------------------------
def build_scare_swarm() -> FxBuilder:
    fx = FxBuilder("scare_swarm")
    root = fx.empty("swarm_root")

    # Core cloud: a dense burst of small motes that BUZZ around the anchor point —
    # high orbital drag + strong noise keeps them milling chaotically right in front
    # of the face instead of dispersing.
    # FX-Wave-11 stacking-law pass: 52 motes born inside a 0.5 r ball right in the
    # camera's face stacked their green hdr into one glowing blob. Opening burst
    # 52->24 over a 1.2 r volume, hdr green 1.9->1.45, alpha crest 0.95->0.6.
    (fx.particle_emitter(
            "swarm_motes",
            duration=70, looping=False, start_lifetime=random_between(26, 44),
            start_speed=random_between(0.12, 0.3),
            start_size=nf3(random_between(0.05, 0.14)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(24)),
                               burst(time=10, count=constant(24))])
        .with_shape(sphere(radius=1.2, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(1.2, 2.4), constant(0)),
                radial=random_between(-0.12, 0.1)),          # breathing, not fleeing
            noise=dict(frequency=1.6, position=nf3(0.22)),   # the chitter jitter
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.6), (0.75, 0.55), (1.0, 0.0)],
                [(0.0, *SOUL_HOT), (0.55, *SOUL_MID), (1.0, *SOUL_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 1.45, 1.45)))
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 3.0, 4.0)))

    # Rush streaks: fast stretched motes exploding OUT of the core — at 2.5-4 blocks
    # ahead, a radial burst means a fistful of them blow straight past the camera.
    # Two waves so the second script burst (`swarm` re-fires at t+17) overlaps live ones.
    # FX-Wave-11 stacking-law pass: births widened 0.25 -> 0.8 r and the green hdr
    # nerfed to ~1.45 so the two waves read as separate streaks, not a green flash.
    (fx.particle_emitter(
            "swarm_rush",
            duration=70, looping=False, start_lifetime=random_between(10, 18),
            start_speed=random_between(2.2, 4.2),
            start_size=nf3(random_between(0.06, 0.12)), max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(22)),
                               burst(time=14, count=constant(16))])
        .with_shape(sphere(radius=0.8, thickness=0.4))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 1.0), (0.6, 0.5), (1.0, 0.0)],
                [(0.0, *SOUL_HOT), (1.0, *SOUL_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.45, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.8,
                       length_scale=2.4)
        .with_cull_box((-6.0, -5.0, -6.0), (6.0, 5.0, 6.0)))

    # Announcing puff: one near-black soot pop the instant the swarm appears — the
    # dark mass the motes seem to pour out of.
    (fx.particle_emitter(
            "swarm_puff",
            duration=40, looping=False, start_lifetime=constant(22),
            start_speed=constant(0.04),
            start_size=nf3(random_between(0.9, 1.4), random_between(0.9, 1.4),
                           random_between(0.9, 1.4)),
            simulation_space="Local", max_particles=6)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(4))])
        .with_shape(sphere(radius=0.3, thickness=1.0))
        .with_curves(
            size_over_lifetime=curve(0.6, 1.5, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.6), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, 0.05, 0.12, 0.09), (1.0, *SOUL_DEEP)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))

    # Stragglers: a handful of slow, long-lived motes that keep drifting after the
    # rush — the tail `soul_leak` reads as souls leaking out of the player.
    (fx.particle_emitter(
            "swarm_stragglers",
            duration=70, looping=False, start_lifetime=random_between(45, 65),
            start_speed=random_between(0.05, 0.14),
            start_size=nf3(random_between(0.04, 0.09)), max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=4, count=constant(10))])
        .with_shape(sphere(radius=0.8, thickness=0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.09), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.4, 0.9), constant(0))),
            noise=dict(frequency=0.9, position=nf3(0.08)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.7), (0.8, 0.4), (1.0, 0.0)],
                [(0.0, *SOUL_MID), (1.0, *SOUL_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.1, 1.6, 1.4)))
        .with_cull_box((-4.0, -2.0, -4.0), (4.0, 5.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:scare_wraith — pale apparition surging up through the view
# ---------------------------------------------------------------------------
def build_scare_wraith() -> FxBuilder:
    fx = FxBuilder("scare_wraith")
    root = fx.empty("wraith_root")

    # Body: a few big pale smoke quads that SURGE upward fast and tear apart — the
    # smear of the wraith itself. Vertical motion reads from every camera angle.
    (fx.particle_emitter(
            "wraith_body",
            duration=55, looping=False, start_lifetime=random_between(16, 26),
            start_speed=constant(0.05),
            start_size=nf3(random_between(0.8, 1.5), random_between(1.2, 2.2),
                           random_between(0.8, 1.5)),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .at(0.0, -0.8, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(6))])
        .with_shape(sphere(radius=0.4, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.9, 1.6), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.5, 1.1), constant(0))),
            size_over_lifetime=curve(0.5, 1.6, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.75), (0.6, 0.4), (1.0, 0.0)],
                [(0.0, *BONE_HOT), (0.5, *BONE_MID), (1.0, *BONE_DEEP)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -2.0, -3.0), (3.0, 8.0, 3.0)))

    # Veil streaks: stretched pale whips riding up with the body — the "swoop" lines.
    (fx.particle_emitter(
            "wraith_veil",
            duration=55, looping=False, start_lifetime=random_between(10, 16),
            start_speed=random_between(0.3, 0.7),
            start_size=nf3(random_between(0.08, 0.16)), max_particles=40)
        .child_of(root)
        .at(0.0, -0.8, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(18)),
                               burst(time=6, count=constant(12))])
        .with_shape(sphere(radius=0.5, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.4, 2.6), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 0.95), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, *BONE_HOT), (1.0, *BONE_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.6, 1.7, 2.0)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=3.0)
        .with_cull_box((-3.0, -2.0, -3.0), (3.0, 9.0, 3.0)))

    # Core pop: ONE hot flash right as it passes (t=2) — the moment the swoop sound
    # lands in the `phantom_swoop` script.
    (fx.particle_emitter(
            "wraith_core",
            duration=30, looping=False, start_lifetime=constant(10),
            start_speed=constant(0), start_size=nf3(1.4), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=(2.0, 2.1, 2.6)))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.8, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (1.0, 0.0)],
                [(0.0, *BONE_HOT), (1.0, *BONE_MID)]))
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))

    # Tatters: dark scraps left behind, sinking slowly — the wraith is already gone.
    (fx.particle_emitter(
            "wraith_tatters",
            duration=55, looping=False, start_delay=constant(6),
            start_lifetime=random_between(22, 36), start_speed=constant(0.06),
            start_size=nf3(random_between(0.3, 0.6), random_between(0.5, 0.9),
                           random_between(0.3, 0.6)),
            simulation_space="Local", max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(9))])
        .with_shape(sphere(radius=0.9, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.22, -0.08), constant(0))),
            noise=dict(frequency=0.7, position=nf3(0.06)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *BONE_DEEP), (1.0, 0.04, 0.04, 0.08)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-3.0, -6.0, -3.0), (3.0, 3.0, 3.0)))
    return fx


BUILDERS = {
    "scare_swarm.fx": build_scare_swarm,
    "scare_wraith.fx": build_scare_wraith,
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
