#!/usr/bin/env python3
"""tyrant_step_fx — FX-Wave-10 generator: Fog Tyrant storm-step Photon assets.

Authors (via fxlib, see tools/photon/README.md) the two assets behind the
storm-step cue pair (registered in `veilfx/BossPhotonFxRows`, fired by
`entity/boss/fog/FogTyrantEntity`):

    eclipse:boss/tyrant_step_out   the FOG FOLD swallowing the tyrant at vanish
                                   time: shell motes sucked INWARD, a dark core
                                   that swells then snaps shut with an electric
                                   fleck burst, and a ground dust skirt.
    eclipse:boss/tyrant_step_in    the reappear SHOCKWAVE on the flank: an
                                   expanding fog shell + ground ring + brief
                                   wisp pillar + falling electric embers.

Both are one-shot BURST-channel layers over the shipped vanilla `fogBurstFx`
CLOUD puffs (LAYER law — photon-less clients keep the old read). Step-out runs
~14t against the {@code STEP_OUT_TICKS}=10t vanish so the snap lands right as
the body teleports; step-in runs ~24t so the wake lingers a beat after the
reappear melee threat is live.

Geometry: both cues fire at body center (+1.5 above feet, the existing
fogBurstFx anchor), so local y = -1.6 is the arena floor.

Style-guide conformance (FX-STYLE-GUIDE.md §1): fog-family slate-teal for every
mist body (alpha blend, shade, no bloom), the tyrant's electric white-teal only
on the fleck accents and the one snap/land flash quad (additive, gentle HDR) —
the step must read as FOG FOLDING, not as a firework.

V2 punch pass: the V1 bodies (0.28-0.44 blk) drowned inside the 30-40 vanilla
CLOUD puffs fired by the same beat — the layer read as "more of the same smoke".
V2 doubles the mote sizes, pushes the fog bodies DARK (slate→dead-indigo against
the white vanilla baseline), and adds a single 1.5-1.7 blk electric flash quad
at the snap/land tick so the teleport reads from across the arena. Vanilla
baseline counts drop 30/40 → 16/20 in the entity so the dark layer dominates
while photon-less clients keep a read.

V2.1 stacking law (isolated /dev photon test finding): dozens of ALPHA-blended
sprites born inside the same half-block converge to the sprite's own tint —
birth tint FOG_TEAL (light) stacked 90x read as a giant WHITE ball, exactly the
supernova the style guide forbids. Fix: birth tints start at STM_SLATE (dark —
stacking now converges to dark slate), alpha peaks 0.85→0.55, birth shells
widened (0.5→1.5 r) and counts trimmed so overlap stays sane. The only bright
elements are the tiny fleck accents + the one small flash quad.

This script IS the authoring source for the binary .fx blobs. Run:
python3 tools/photon/tyrant_step_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, constant, curve, gradient, nf3, random_between,
    sphere, cylinder, texture_material, validate_file,
)


def _size3(lower, upper, segments):
    """Uniform xyz size_over_lifetime from one bezier curve spec."""
    c = curve(lower, upper, segments, "lifetime", "size")
    return nf3(c, curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"))

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"

# FX-STYLE-GUIDE §1 tokens (the statue_fx.py fog family).
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38 (deep dead indigo)
SPARK_WHITE = (0.9, 1.0, 1.0)         # electric white-teal accent

CULL = ((-9.0, -2.5, -9.0), (9.0, 6.0, 9.0))


def build_step_out() -> FxBuilder:
    """Vanish beat: the fog folds shut around the tyrant — inward shell gulp,
    swelling dark core, snap-flash, dust skirt kicked off the floor."""
    fx = FxBuilder("boss/tyrant_step_out")

    # L1 fold gulp: motes born on a wide shell, dragged hard INTO the fold
    # center (negative radial), shrinking as they go — the fog eats the body.
    # V2: 0.65-1.0 blk bodies, alpha peak 0.85, slate→indigo fast (dark against
    # the white vanilla puffs instead of vanishing among them).
    (fx.particle_emitter(
            "fold_gulp",
            duration=14, looping=False, max_particles=70,
            start_lifetime=random_between(8, 12), start_speed=constant(0),
            start_size=nf3(random_between(0.65, 1.0), random_between(0.65, 1.0),
                           random_between(0.65, 1.0)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=0, count=56)])
       .with_shape(sphere(radius=4.2, thickness=0.25))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-7.5)),
            size_over_lifetime=_size3(
                0.2, 1.0, [(0.0, 1.0, 0.35, 0.8, 0.7, 0.35, 1.0, 0.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.6, *STM_SLATE), (1.0, *GLI_DEAD)])))

    # L2 fold core: big indigo bodies that swell as the gulp feeds them, then
    # collapse to nothing right at the teleport tick. V2.1: 2 bodies born a
    # block apart (stacking law) at alpha 0.55 — a dark mass, not a lightbulb.
    (fx.particle_emitter(
            "fold_core",
            duration=14, looping=False, max_particles=3,
            start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(constant(2.2), constant(2.2), constant(2.2)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=0, count=2)])
       .with_shape(sphere(radius=0.9))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(
                0.05, 1.0,
                [(0.0, 0.53, 0.2, 0.75, 0.4, 1.0, 0.55, 1.0),
                 (0.55, 1.0, 0.7, 0.95, 0.9, 0.45, 1.0, 0.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (0.8, 0.4), (1.0, 0.0)],
                [(0.0, *GLI_DEAD), (1.0, *GLI_DEAD)])))

    # L3 fold snap: a late fleck burst as the fold snaps shut — V2: 20 flecks
    # at 0.16-0.26 blk, thrown 4.5-7.5 blk/s so the snap sprays past the fold.
    (fx.particle_emitter(
            "fold_snap",
            duration=14, looping=False, max_particles=24,
            start_lifetime=random_between(4, 6), start_speed=random_between(4.5, 7.5),
            start_size=nf3(random_between(0.16, 0.26), random_between(0.16, 0.26),
                           random_between(0.16, 0.26)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=8, count=20)])
       .with_shape(sphere(radius=0.3))
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.2, 2.6, 2.6),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (1.0, *FOG_TEAL)])))

    # L3b snap flash: ONE 1.5 blk electric quad popping right at the teleport
    # tick — the unmistakable "it is gone NOW" read from across the arena.
    # (V2.1: 2.8 blk @ HDR 2.4 read as a screen-filling supernova at the 9-14
    # blk fight distance — half the size, gentle HDR, half the alpha.)
    (fx.particle_emitter(
            "snap_flash",
            duration=14, looping=False, max_particles=2,
            start_lifetime=constant(3), start_speed=constant(0),
            start_size=nf3(constant(1.5), constant(1.5), constant(1.5)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=8, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.25, 1.45, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(
                0.3, 1.0, [(0.0, 1.0, 0.5, 0.75, 0.8, 0.35, 1.0, 0.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.5), (0.5, 0.3), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (1.0, *STM_SLATE)])))

    # L4 ground skirt: dust ring kicked outward along the floor (V2: 0.55-0.85
    # blk bodies so the skirt reads as displaced mass, not lint).
    (fx.particle_emitter(
            "ground_skirt",
            duration=14, looping=False, max_particles=26,
            start_lifetime=random_between(8, 12), start_speed=random_between(4.0, 5.5),
            start_size=nf3(random_between(0.55, 0.85), random_between(0.55, 0.85),
                           random_between(0.55, 0.85)),
            simulation_space="Local")
       .at(0.0, -1.5, 0.0)
       .with_emission(bursts=[burst(time=0, count=22)])
       .with_shape(circle(radius=1.6))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *GLI_DEAD)])))
    return fx


def build_step_in() -> FxBuilder:
    """Reappear beat: the fold bursts open on the flank — expanding fog shell,
    ground shock ring, a brief wisp pillar and falling electric embers."""
    fx = FxBuilder("boss/tyrant_step_in")

    # L0 land flash: ONE 1.7 blk electric quad at the reappear tick — mirrors
    # the vanish snap so both ends of the teleport carry the same signature.
    # (V2.1: same supernova nerf as snap_flash — see step_out.)
    (fx.particle_emitter(
            "land_flash",
            duration=24, looping=False, max_particles=2,
            start_lifetime=constant(3), start_speed=constant(0),
            start_size=nf3(constant(1.7), constant(1.7), constant(1.7)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=0, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.25, 1.45, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(
                0.25, 1.0, [(0.0, 1.0, 0.45, 0.7, 0.75, 0.3, 1.0, 0.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.45, 0.35), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (1.0, *STM_SLATE)])))

    # L1 burst shell: motes explode outward from the fold point and drag to a
    # hang, leaving a slowly thinning fog sphere around the reappeared body.
    # V2.1: born on a 1.5 r shell at alpha 0.55, slate from birth — the burst
    # reads as a dark shockwave shell, not a white ball (stacking law).
    (fx.particle_emitter(
            "burst_shell",
            duration=24, looping=False, max_particles=60,
            start_lifetime=random_between(12, 18), start_speed=random_between(5.5, 8.5),
            start_size=nf3(random_between(0.5, 0.9), random_between(0.5, 0.9),
                           random_between(0.5, 0.9)),
            simulation_space="Local")
       .with_emission(bursts=[burst(time=0, count=48)])
       .with_shape(sphere(radius=1.5, thickness=0.5))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-2.2)),
            size_over_lifetime=_size3(
                0.4, 1.0,
                [(0.0, 0.17, 0.15, 0.7, 0.25, 1.0, 0.35, 1.0),
                 (0.35, 1.0, 0.6, 1.0, 0.85, 0.6, 1.0, 0.58)]),
            color_over_lifetime=gradient(
                [(0.0, 0.55), (0.45, 0.4), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *STM_SLATE), (1.0, *GLI_DEAD)])))

    # L2 ground ring: the shock ring racing outward along the arena floor
    # (V2: 0.55-0.9 blk, 9.5-12.5 blk/s — a wave, not a ripple).
    (fx.particle_emitter(
            "burst_ring",
            duration=24, looping=False, max_particles=38,
            start_lifetime=random_between(9, 13), start_speed=random_between(9.5, 12.5),
            start_size=nf3(random_between(0.55, 0.9), random_between(0.55, 0.9),
                           random_between(0.55, 0.9)),
            simulation_space="Local")
       .at(0.0, -1.5, 0.0)
       .with_emission(bursts=[burst(time=0, count=28)])
       .with_shape(circle(radius=1.2))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.55), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.6, *STM_SLATE), (1.0, *GLI_DEAD)])))

    # L3 wisp pillar: a short-lived rising column marking WHERE it landed
    # (fairness echo of the vanish-window gather cue). V2: 0.35-0.55 blk.
    (fx.particle_emitter(
            "burst_pillar",
            duration=24, looping=False, max_particles=36,
            start_lifetime=random_between(10, 15), start_speed=constant(0),
            start_size=nf3(random_between(0.35, 0.55), random_between(0.35, 0.55),
                           random_between(0.35, 0.55)),
            simulation_space="Local")
       .at(0.0, -1.2, 0.0)
       .with_emission(bursts=[burst(time=0, count=14), burst(time=4, count=12)])
       .with_shape(cylinder(radius=1.1))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(3.0, 4.5), constant(0.0)),
                radial=constant(0.4)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.45), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *STM_SLATE)])))

    # L4 ember spray: electric flecks thrown up that fall back under gravity —
    # the accent that sells the impact mass (V2: 0.12-0.2 blk, 20 flecks).
    (fx.particle_emitter(
            "burst_embers",
            duration=24, looping=False, max_particles=24,
            start_lifetime=random_between(10, 16), start_speed=random_between(4.0, 6.0),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            simulation_space="Local")
       .with_physics(gravity=0.5, collision=False)
       .with_emission(bursts=[burst(time=0, count=20)])
       .with_shape(sphere(radius=0.4, thickness=1.0, arc=360.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 2.2, 2.2),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.7, 0.4), (1.0, 0.0)],
                [(0.0, *SPARK_WHITE), (1.0, *FOG_TEAL)])))
    return fx


BUILDERS = {
    "boss/tyrant_step_out.fx": build_step_out,
    "boss/tyrant_step_in.fx": build_step_in,
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
