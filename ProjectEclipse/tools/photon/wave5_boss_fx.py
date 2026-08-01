#!/usr/bin/env python3
"""wave5_boss_fx — WAVE5 (F-105 A) A6 generator: the boss-trophy wisp Photon asset.

Authors (via fxlib, see tools/photon/README.md) the one asset behind the four
`veilfx/Wave5BossFxRows` WINDOWED loop rows (`eclipse:fx/cue/wave5_trophy_<boss>`,
anchored on the `FxAnchors` anchors the boss death scripts publish at monument
placement — see `placeTrophyMonument` in the four boss entities):

    eclipse:wave5_trophy_wisp   a quiet two-layer soul wisp over a boss trophy
                                monument — 2-3 motes on a slow orbit plus one
                                breathing halo crown. "Trophäen-Resonanz": the
                                monument hums, it does not perform.

The SAME asset serves all four monuments (amethyst cluster / obsidian+end rod /
lightning rod / soul lantern): the wisp is the soul residue of a fallen boss, not a
boss-specific effect, and one shared blob keeps the Photon budget at one executor
per open window.

Loop law (INTEGRATION.md §4): looping=True asset, WINDOWED-only — never payload
fired; `Wave5BossFxRows` drives `PhotonFxRegistry.ensureLoop/releaseLoop` from a
hysteresis band. Cull box + modest maxParticles per the golden rules; prewarm covers
the longest particle life so an opened window never reads as "filling up".

Style-guide conformance (FX-STYLE-GUIDE.md §1, V2.1 stacking law): GLI_DEAD dark
birth tints (alpha AND rgb rise from the dead-violet floor), glint-family cyan/white
peaks, additive at gentle HDR <= 1.45 — the wisp must read in the dark without
blooming over its own monument.

This script IS the authoring source for the binary .fx blob (fxlib generator in
place of an editor .fxproj; the .fxproj sibling ships beside it — binary-diff law;
node UUIDs are uuid5-deterministic inside fxlib, so a double run is byte-identical).
Run: python3 tools/photon/wave5_boss_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, circle, constant, curve, gradient, nf3, random_between,
    sphere, texture_material, validate_file,
    SEG_DECAY_TAIL,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"

# FX-STYLE-GUIDE §1 tokens (glint family — soul-cyan accents on the dead-violet floor).
GLI_CYAN = (0.310, 0.910, 1.0)        # #4FE8FF — soul-flame accent
GLI_WHITE = (1.0, 1.0, 1.0)           # #FFFFFF — mote peak
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38 — dark birth tint (V2.1 stacking law)

# The whole set lives within ~a block of the monument cap; the loop cull box hugs it.
CULL = ((-1.5, -1.0, -1.5), (1.5, 2.2, 1.5))

#: Loop cycle length (ticks). Prewarm >= the longest particle life (70 t) so a
#: freshly-opened window shows the settled wisp, not an empty ramp-up.
LOOP_DURATION = 100
PREWARM = 70


def build_trophy_wisp() -> FxBuilder:
    """A6 trophy resonance: two layers, ~8 live particles, one executor.

    wisp_orbit   2-3 small motes born on a tight ring just above the monument cap,
                 spiralling slowly upward (orbital + gentle linear lift) and dying
                 ~1.3 blocks up — the classic soul-wisp read.
    crown_halo   one soft breathing glow hovering over the cap (near-zero speed,
                 slow swell-and-fade size curve) — the "someone fell here" beacon
                 that still reads when the orbit motes are between births.
    """
    fx = FxBuilder("wave5_trophy_wisp")

    # L1 wisp orbit: born dark on a r=0.3 ring, alpha and rgb rise off the GLI_DEAD
    # floor mid-life (dark birth tint), gone before y+1.5. Speeds sit just above the
    # perception floor (Photon linear x0.05/t = blocks/SECOND).
    (fx.particle_emitter(
            "wisp_orbit",
            duration=LOOP_DURATION, looping=True, prewarm=PREWARM, max_particles=6,
            start_lifetime=random_between(50, 70), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="Local")
       .at(0.0, 0.25, 0.0)
       .with_emission(rate=constant(0.06))
       .with_shape(circle(radius=0.3))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 1.35, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0.0), random_between(0.8, 1.4), constant(0.0)),
                linear=nf3(constant(0.0), constant(0.4), constant(0.0)),
                radial=constant(0.3)),
            size_over_lifetime=nf3(curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, *GLI_DEAD), (0.45, *GLI_CYAN), (0.85, *GLI_WHITE), (1.0, *GLI_DEAD)])))

    # L2 crown halo: a single soft glow breathing over the cap. Alpha peak stays low
    # (0.3) — this idles for minutes next to whatever fight comes back here.
    (fx.particle_emitter(
            "crown_halo",
            duration=LOOP_DURATION, looping=True, prewarm=PREWARM, max_particles=2,
            start_lifetime=constant(60), start_speed=constant(0.0),
            start_size=nf3(random_between(0.24, 0.32), random_between(0.24, 0.32),
                           random_between(0.24, 0.32)),
            simulation_space="Local")
       .at(0.0, 0.55, 0.0)
       .with_emission(rate=constant(0.034))
       .with_shape(sphere(radius=0.08))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.05, 1.25, 1.35),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.5, 1.0, [(0.0, 0.5, 0.2, 1.05, 0.42, 1.0, 0.55, 0.95),
                                 (0.55, 0.95, 0.72, 0.85, 0.88, 0.35, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.5, 1.0, [(0.0, 0.5, 0.2, 1.05, 0.42, 1.0, 0.55, 0.95),
                                 (0.55, 0.95, 0.72, 0.85, 0.88, 0.35, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.5, 1.0, [(0.0, 0.5, 0.2, 1.05, 0.42, 1.0, 0.55, 0.95),
                                 (0.55, 0.95, 0.72, 0.85, 0.88, 0.35, 1.0, 0.0)],
                      "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.35, 0.3), (0.75, 0.18), (1.0, 0.0)],
                [(0.0, *GLI_DEAD), (0.5, *GLI_CYAN), (1.0, *GLI_DEAD)])))
    return fx


BUILDERS = {
    "wave5_trophy_wisp.fx": build_trophy_wisp,
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
