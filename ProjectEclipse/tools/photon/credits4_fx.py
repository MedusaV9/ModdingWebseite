#!/usr/bin/env python3
"""CREDITS4 (F-090/F-093 "Map-Zerreißen V3") — authors the map-rip Photon assets:

  eclipse:credits4_crackfront  crack-front propagation step: violet glow motes hugging
                               the glowing seam slats + a rising dust curtain + a short
                               upward debris jet — fired by CreditsSequence.mapRipBeats
                               at every propagation step's segment midpoint (~40t
                               one-shot; 3 fronts × 6 steps = 18 fires per run, each on
                               a fresh midpoint marching hole → camera)
  eclipse:credits4_platebreak  mid-air sub-fracture snap: one sharp hot split flash +
                               a handful of slow dark shard puffs kicked outward —
                               fired once per plate at lift+40t (~30t one-shot; ≈40
                               fires, de-phased by the per-plate lift jitter)
  eclipse:credits4_jetburst    jet shred: two opposed fast particle streams racing up/
                               down the maw's polar axis + a few long stretched sparks
                               — fired at the fx anchor whenever a shredded sub-plate
                               sprays along the jet axis (~60t one-shot, paired with
                               the S2CCreditsJetPayload shader strobe)

Authored scale (anchor frame, ~4.3× at map read through the crushed FOV): a crack
step's segment is ~13 anchor-blocks, so the crackfront veil covers a 6–8-block seam
band; a plate silhouette is 8–20 blocks, so the platebreak flash pops at ~3 and its
puffs ride a 6-block shell; the jets must clear the ~26-block maw — the streams reach
~40 blocks along ±Y (the disc minor axis: the same columns black_hole.fsh strobes).

Java-side tick contract: CreditsMapRipAct's CRACK_STEP_TICKS = 15 (the veil's motes
outlive one step, so consecutive steps chain into one racing front); FRACTURE_SNAP
window 4t (the flash is authored to peak inside it); JET_SPRAY_TICKS = 50 (the streams
die just after the display spray drains).

Usage:  python3 tools/photon/credits4_fx.py            # write + validate all three
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, burst, circle, cone, constant, curve,
    cylinder, gradient, nf3, random_between, sphere, texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Finale palette (the ferryman2 law): near-black violet body, mid, hot white-violet.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)


# ---------------------------------------------------------------------------
# 1. eclipse:credits4_crackfront — a propagation step of a racing crack front
# ---------------------------------------------------------------------------
def build_credits4_crackfront() -> FxBuilder:
    fx = FxBuilder("credits4_crackfront")
    root = fx.empty("crackfront_root")

    # Seam glow: small hot motes hugging the freshly opened seam band — near-static
    # (the CRACK glows, the slat displays carry the hard line), front-loaded so each
    # step reads as one bright pop that hands over to the next step's midpoint.
    (fx.particle_emitter(
            "crackfront_glow",
            duration=40, looping=False, start_lifetime=random_between(18, 30),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.3, 0.7)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.6),
                       bursts=[burst(time=0, count=constant(10))])
        .with_shape(cylinder(radius=6.0, thickness=0.8))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.85), (0.6, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (0.6, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.0, 1.8)))
        .with_cull_box((-12.0, -6.0, -12.0), (12.0, 10.0, 12.0)))

    # Dust curtain: a low smoke sheet RISING off the tearing seam — the crust exhales
    # as the crack jumps (the reverse of the precrack trickle).
    (fx.particle_emitter(
            "crackfront_dust",
            duration=40, looping=False, start_lifetime=random_between(26, 40),
            start_speed=constant(0.03),
            start_size=nf3(random_between(1.2, 2.4), random_between(1.2, 2.4),
                           random_between(1.2, 2.4)),
            simulation_space="Local", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(0.5),
                       bursts=[burst(time=0, count=constant(8))])
        .with_shape(cylinder(radius=7.0, thickness=0.7))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.1, 0.24), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.38), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, 0.16, 0.09, 0.24), (1.0, 0.07, 0.04, 0.12)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-14.0, -4.0, -14.0), (14.0, 16.0, 14.0)))

    # Debris jet: a short sharp spray of fast splinters kicked UP out of the seam the
    # instant the step lands — the physical half of the per-step shake pulse.
    (fx.particle_emitter(
            "crackfront_debris",
            duration=40, looping=False, start_lifetime=random_between(10, 18),
            start_speed=random_between(0.7, 1.2),
            start_size=nf3(random_between(0.12, 0.24)), max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(12))])
        .with_shape(cone(angle=16.0, radius=2.2, thickness=0.4))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.8), (0.65, 0.4), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.3, 1.05, 1.7)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=1.4)
        .with_cull_box((-10.0, -2.0, -10.0), (10.0, 20.0, 10.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:credits4_platebreak — a plate snapping into sub-plates mid-air
# ---------------------------------------------------------------------------
def build_credits4_platebreak() -> FxBuilder:
    fx = FxBuilder("credits4_platebreak")
    root = fx.empty("platebreak_root")

    # Split flash: ONE sharp hot pop at the fracture line — authored to peak inside
    # the act's 4t snap window (the visual crack of the audible crack SFX).
    (fx.particle_emitter(
            "platebreak_flash",
            duration=30, looping=False, start_lifetime=constant(10),
            start_speed=constant(0), start_size=nf3(2.6), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(1)),
                               burst(time=3, count=constant(1))])
        .with_shape(circle(radius=1.6, thickness=0.3))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.5, 1.15, 2.0)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.7, [(0.0, 0.35, 1.0, 1.0, 0.3, 1.0, 1.0, 0.45)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.9), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-10.0, -6.0, -10.0), (10.0, 10.0, 10.0)))

    # Shard puffs: a handful of slow dark chips kicked outward off the split seam,
    # sinking as they fade — the small-mass echo of the sub-plates shearing apart.
    (fx.particle_emitter(
            "platebreak_shards",
            duration=30, looping=False, start_lifetime=random_between(16, 26),
            start_speed=random_between(0.25, 0.5),
            start_size=nf3(random_between(0.2, 0.45)), max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(14))])
        .with_shape(sphere(radius=6.0, thickness=0.25))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.16, -0.06), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.65), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.1, 0.9, 1.4)))
        .with_cull_box((-14.0, -12.0, -14.0), (14.0, 12.0, 14.0)))

    # Fracture dust: one soft smoke exhale along the split — mass without noise.
    (fx.particle_emitter(
            "platebreak_dust",
            duration=30, looping=False, start_lifetime=random_between(18, 28),
            start_speed=constant(0.06),
            start_size=nf3(random_between(1.4, 2.6), random_between(1.4, 2.6),
                           random_between(1.4, 2.6)),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=1, count=constant(8))])
        .with_shape(sphere(radius=4.0, thickness=0.4))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.3), (0.7, 0.16), (1.0, 0.0)],
                [(0.0, 0.15, 0.08, 0.22), (1.0, 0.06, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-12.0, -8.0, -12.0), (12.0, 10.0, 12.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:credits4_jetburst — the relativistic jets shred a sub-plate
# ---------------------------------------------------------------------------
def _jet_stream(fx: FxBuilder, root, name: str, down: bool):
    """One fast particle stream racing out along the jet axis (±Y off the anchor)."""
    emitter = (fx.particle_emitter(
            name,
            duration=60, looping=False, start_lifetime=random_between(22, 34),
            start_speed=random_between(1.1, 1.6),
            start_size=nf3(random_between(0.25, 0.5)), max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.45),
                       bursts=[burst(time=0, count=constant(14)),
                               burst(time=10, count=constant(9)),
                               burst(time=22, count=constant(6))])
        .with_shape(cone(angle=7.0, radius=1.6, thickness=0.5))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.85), (0.6, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (0.55, *VIOLET_MID), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.35, 1.1, 1.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                       length_scale=1.8)
        .with_cull_box((-16.0, -55.0, -16.0), (16.0, 55.0, 16.0)))
    if down:
        emitter.rotated(180.0, 0.0, 0.0)
    return emitter


def build_credits4_jetburst() -> FxBuilder:
    fx = FxBuilder("credits4_jetburst")
    root = fx.empty("jetburst_root")

    # Two opposed streams: the up (approaching, Doppler-bright in the shader) jet and
    # the down (receding) jet — speed × lifetime reaches ~40 blocks, clearing the
    # ~26-block maw so the streams visibly extend the strobing shader columns.
    _jet_stream(fx, root, "jetburst_up", down=False)
    _jet_stream(fx, root, "jetburst_down", down=True)

    # Stretched sparks: a handful of LONG hot streaks riding the same axis — the
    # display spray's brightest siblings (rare, so they read as events, not noise).
    (fx.particle_emitter(
            "jetburst_sparks",
            duration=60, looping=False, start_lifetime=random_between(14, 22),
            start_speed=random_between(1.6, 2.2),
            start_size=nf3(random_between(0.4, 0.7)), max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(4)),
                               burst(time=16, count=constant(3)),
                               burst(time=32, count=constant(2))])
        .with_shape(cone(angle=4.0, radius=1.0, thickness=0.3, arc_mode="Random"))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 1.0), (0.5, 0.55), (1.0, 0.0)],
                [(0.0, 0.9, 0.82, 1.0), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.5, 1.2, 2.0)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.8,
                       length_scale=2.6)
        .with_cull_box((-12.0, -60.0, -12.0), (12.0, 60.0, 12.0)))

    # Axis glow: a faint violet haze hugging the launch throat so the burst has a
    # body at the anchor (the shader's jet root sits on the same screen spot).
    (fx.particle_emitter(
            "jetburst_throat",
            duration=60, looping=False, start_lifetime=random_between(20, 32),
            start_speed=constant(0.05),
            start_size=nf3(random_between(2.0, 3.4), random_between(2.0, 3.4),
                           random_between(2.0, 3.4)),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(6))])
        .with_shape(sphere(radius=3.0, thickness=0.5))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.3), (0.7, 0.16), (1.0, 0.0)],
                [(0.0, 0.3, 0.18, 0.45), (1.0, 0.12, 0.06, 0.2)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-10.0, -10.0, -10.0), (10.0, 10.0, 10.0)))
    return fx


BUILDERS = {
    "credits4_crackfront.fx": build_credits4_crackfront,
    "credits4_platebreak.fx": build_credits4_platebreak,
    "credits4_jetburst.fx": build_credits4_jetburst,
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
