#!/usr/bin/env python3
"""CREDITS3 (F-072 V3) — authors the credits V3 polish Photon assets with fxlib:

  eclipse:credits3_precrack  F-072 V3 island pre-crack veil ("Vorriss-Phase"): the
                             island's seams GLOW before anything moves — pulsing
                             violet crack-line motes hugging the surface, fine dust
                             TRICKLING DOWN off the underside, and two tiny seam pops
                             — fired once by CreditsSequence at the island center
                             ~50t BEFORE the break beat (~70t one-shot; the break's
                             credits_collapse veil takes over on the same center)
  eclipse:credits3_nebula    F-072 V3 space atmosphere for the black-hole tele shot:
                             far, huge, near-static nebula swaths (very low alpha
                             smoke sheets on a wide shell) + RARE subtle shooting
                             stars (fast stretched streaks, ~4 per re-fire) around
                             the maw anchor (~340t one-shot, re-fired by
                             CreditsSequence on the maw's 300t cadence — the
                             kneel-corona sustain law keeps the seam gapless)

Authored scale: the nebula shell sits 55–80 blocks off the maw anchor (well outside
the ~26-block maw so the swaths never muddy the accretion read); the pre-crack veil
covers the island's ~16-block ellipse like the collapse veil it precedes.

Java-side tick contract (F-072 V3): CreditsSequence.T_SHATTER_PRECRACK fires the
pre-crack veil exactly 50t before T_SHATTER_BREAK — the veil's build-up gradient is
authored against that gap (glow peaks right as the break lands).

Usage:  python3 tools/photon/credits3_fx.py            # write + validate both
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
# 1. eclipse:credits3_precrack — F-072 V3 (the island GLOWS before it breaks)
# ---------------------------------------------------------------------------
def build_credits3_precrack() -> FxBuilder:
    fx = FxBuilder("credits3_precrack")
    root = fx.empty("precrack_root")

    # Crack-line glow: small hot motes hugging the island surface on a flat ring band
    # — near-static (the CRACKS glow, nothing flies yet), alpha building toward the
    # break beat (glow peaks right as credits_collapse lands 50t after the fire).
    (fx.particle_emitter(
            "precrack_glow",
            duration=64, looping=False, start_lifetime=random_between(30, 50),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.35, 0.8)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(1.3))
        .with_shape(cylinder(radius=12.0, thickness=0.9))
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.35, 0.35), (0.8, 0.75), (1.0, 0.0)],  # builds, then breaks
                [(0.0, *VIOLET_MID), (0.7, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 0.95, 1.7)))
        .with_cull_box((-20.0, -6.0, -20.0), (20.0, 10.0, 20.0)))

    # Dust trickle: fine near-black dust SINKING off the underside — "Staub rieselt"
    # before the first fragment ever moves (the reverse of the collapse updraft).
    (fx.particle_emitter(
            "precrack_dust",
            duration=64, looping=False, start_lifetime=random_between(40, 65),
            start_speed=constant(0.02),
            start_size=nf3(random_between(0.8, 1.6), random_between(0.8, 1.6),
                           random_between(0.8, 1.6)),
            simulation_space="Local", max_particles=70)
        .child_of(root)
        .with_emission(rate=constant(1.0))
        .with_shape(cylinder(radius=11.0, thickness=0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.22, -0.1), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, 0.13, 0.07, 0.18), (1.0, 0.06, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-18.0, -22.0, -18.0), (18.0, 6.0, 18.0)))

    # Seam pops: two tiny sharp flashes as the cracks jump wider — the audible crack
    # beats' visual halves (the server pairs quiet stone cracks on the same window).
    (fx.particle_emitter(
            "precrack_pops",
            duration=64, looping=False, start_lifetime=constant(12),
            start_speed=constant(0), start_size=nf3(1.8), max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=18, count=constant(1)),
                               burst(time=38, count=constant(1))])
        .with_shape(circle(radius=8.0, thickness=0.2))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.4, 1.1, 1.9)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.6, [(0.0, 0.4, 1.0, 1.0, 0.35, 1.0, 1.0, 0.5)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-14.0, -4.0, -14.0), (14.0, 8.0, 14.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:credits3_nebula — F-072 V3 (far nebula swaths + rare shooting stars)
# ---------------------------------------------------------------------------
def build_credits3_nebula() -> FxBuilder:
    fx = FxBuilder("credits3_nebula")
    root = fx.empty("nebula_root")

    # Nebula swaths: HUGE, whisper-alpha smoke sheets parked on a wide shell around
    # the maw anchor, drifting almost imperceptibly — distant gas seen past the disc.
    # Radius 55–80 keeps them far outside the ~26-block maw (they frame, never muddy).
    (fx.particle_emitter(
            "nebula_swaths",
            duration=340, looping=False, start_lifetime=random_between(180, 300),
            start_speed=constant(0.0),
            start_size=nf3(random_between(9.0, 16.0), random_between(9.0, 16.0),
                           random_between(9.0, 16.0)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.14))
        .with_shape(sphere(radius=68.0, thickness=0.35))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.012), constant(0))),  # near-static
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.16), (0.75, 0.12), (1.0, 0.0)],  # whisper alpha
                [(0.0, 0.24, 0.13, 0.38), (0.6, 0.14, 0.08, 0.24), (1.0, 0.07, 0.04, 0.13)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-90.0, -90.0, -90.0), (90.0, 90.0, 90.0)))

    # Shooting stars: RARE and subtle — four per re-fire window, fast stretched
    # streaks skimming tangentially across the far shell (never toward the camera,
    # never near the disc), burning out in under 1.5 s.
    (fx.particle_emitter(
            "nebula_shooting_stars",
            duration=340, looping=False, start_lifetime=random_between(18, 28),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.24)), max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=45, count=constant(1)),
                               burst(time=130, count=constant(1)),
                               burst(time=210, count=constant(1)),
                               burst(time=295, count=constant(1))])
        .with_shape(sphere(radius=74.0, thickness=0.06))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(1.7), constant(0))),  # the skim
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.7), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, 0.85, 0.78, 1.0), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=(1.2, 1.05, 1.6)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.4,
                       length_scale=2.2)
        .with_cull_box((-90.0, -90.0, -90.0), (90.0, 90.0, 90.0)))
    return fx


BUILDERS = {
    "credits3_precrack.fx": build_credits3_precrack,
    "credits3_nebula.fx": build_credits3_nebula,
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
