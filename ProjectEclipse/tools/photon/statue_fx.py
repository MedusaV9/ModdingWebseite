#!/usr/bin/env python3
"""statue_fx — F-081 generator: the Tyrant Statue idle-aura Photon `.fx` asset.

Authors (via fxlib, see tools/photon/README.md) the one asset behind
`FxCues.CUE_TYRANT_STATUE_IDLE` (registered in `veilfx/BossPhotonFxRows`, fired by
`entity/boss/fog/TyrantStatue.ensureArmed` on its 40t armed-lair cadence):

    eclipse:boss/tyrant_statue_idle   slow ember orbit up the statue column + faint
                                      crown sparks + a plinth mist skirt — the statue
                                      must READ as interactive ("strike me") inside the
                                      dark storm without stealing the storm's show.

Timing law (the CUE_TYRANT_FOG_ARMS sustain pattern): the asset runs 200t and the
server re-sends the cue every 40t; 40 divides 200, so each mid-run re-send is a silent
dedup no-op and the loop sustains seamlessly. NOT a Photon loop row — position lane,
one-shot duration=200 emitters.

Geometry: the cue fires at the statue's FX center = statue base + 1.7 (see
`TyrantStatue.fxCenter`), so local y = -1.7 is the plinth base and the crown accent
tops out around local y = +1.6.

Style-guide conformance (FX-STYLE-GUIDE.md §1): fog-family desaturated slate-teal for
the mist (alpha-blend, shade, no bloom — fog is weather); the embers/sparks take the
tyrant's electric white-teal at gentle HDR (the crown IS a lightning rod). Ambient
read: alpha peaks stay low, budgets small (this idles for minutes).

This script IS the authoring source for the binary .fx blob (fxlib generator in place
of an editor .fxproj; the .fxproj sibling ships beside it — binary-diff law). Run:
python3 tools/photon/statue_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, circle, constant, gradient, nf3, random_between, sphere,
    texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"

# FX-STYLE-GUIDE §1 tokens (shared with backlog_fx.py's fog family).
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38
SPARK_WHITE = (0.9, 1.0, 1.0)         # electric white-teal (crown accent)

CULL = ((-3.0, -2.5, -3.0), (3.0, 3.0, 3.0))


def build_tyrant_statue_idle() -> FxBuilder:
    """F-081 statue idle aura: embers orbit the column bottom-to-crown, the crown
    spits faint electric flecks, a mist skirt grounds the plinth in the fog."""
    fx = FxBuilder("boss/tyrant_statue_idle")

    # L1 ember orbit: born on a ring at the plinth, spiralling slowly up the column
    # (orbital + linear up-drift), fading out as they clear the crown.
    (fx.particle_emitter(
            "ember_orbit",
            duration=200, looping=False, max_particles=40,
            start_lifetime=random_between(45, 60), start_speed=constant(0),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="Local")
       .at(0.0, -1.4, 0.0)
       .with_emission(rate=constant(0.5))
       .with_shape(circle(radius=0.9))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 1.5, 1.5),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0), random_between(1.0, 1.8), constant(0)),
                linear=nf3(constant(0.0), constant(0.055), constant(0.0)),
                radial=constant(-0.012)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (0.6, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L2 crown sparks: sparse electric flecks popping off the lightning-rod accent.
    (fx.particle_emitter(
            "crown_sparks",
            duration=200, looping=False, max_particles=8,
            start_lifetime=random_between(8, 14), start_speed=random_between(0.06, 0.16),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="Local")
       .at(0.0, 1.35, 0.0)
       .with_emission(rate=constant(0.25))
       .with_shape(sphere(radius=0.3, thickness=0.2))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 2.0, 2.2),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (1.0, *FOG_TEAL)])))

    # L3 plinth mist: a faint fog skirt pooling around the base (fog is weather:
    # alpha-blend, shaded, no bloom, alpha peak 0.22).
    (fx.particle_emitter(
            "plinth_mist",
            duration=200, looping=False, max_particles=14,
            start_lifetime=random_between(28, 40), start_speed=random_between(0.01, 0.03),
            start_size=nf3(random_between(0.35, 0.6), random_between(0.35, 0.6),
                           random_between(0.35, 0.6)),
            simulation_space="Local")
       .at(0.0, -1.55, 0.0)
       .with_emission(rate=constant(0.3))
       .with_shape(circle(radius=1.1))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(0.008), constant(0.0)),
                radial=constant(0.015)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.22), (0.75, 0.15), (1.0, 0.0)],
                [(0.0, *FOG_TEAL), (0.7, *STM_SLATE), (1.0, *GLI_DEAD)])))
    return fx


BUILDERS = {
    "boss/tyrant_statue_idle.fx": build_tyrant_statue_idle,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
