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
    FxBuilder, burst, circle, constant, curve, gradient, material_shader, nf3,
    random_between, random_gradient, sphere, texture_material, validate_file,
    SEG_DECAY_TAIL, SEG_FLICKER_COMMIT,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"

# FX-STYLE-GUIDE §1 tokens (shared with backlog_fx.py's fog family).
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55
STM_ARC = (0.749, 0.851, 1.0)         # #BFD9FF — electric pale
STM_DEEP = (0.353, 0.553, 0.933)      # #5A8DEE
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38
SPARK_WHITE = (0.9, 1.0, 1.0)         # electric white-teal (crown accent)

# The idle set reaches further than the statue itself now (r=4.5 in-draw shell,
# ground cracks out to r=2.4), so the cull box grows with it.
CULL = ((-6.0, -2.5, -6.0), (6.0, 3.5, 6.0))

#: Emitter-duration ramp: near-flat for the first third, then commits. Every knob
#: that has to "load" over the 200 t arc (in-draw speed/rate, pulse size) rides it.
CHARGE_RAMP = SEG_FLICKER_COMMIT


def _size3(lower, upper, segments):
    """Uniform xyz size_over_lifetime from one bezier curve spec."""
    return nf3(curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"))


def _charge3(lower, upper):
    """Uniform xyz start_size that grows over the EMITTER's duration (not the
    particle's life) — later pulses are born bigger than earlier ones."""
    return nf3(curve(lower, upper, [CHARGE_RAMP], "duration", "size"),
               curve(lower, upper, [CHARGE_RAMP], "duration", "size"),
               curve(lower, upper, [CHARGE_RAMP], "duration", "size"))


def _soft(texture, soft=1.2, near=0.6, blend=None):
    """A0 soft-particle material — the ground-contact layers stop clipping into
    the plinth and the terrain the statue is planted in."""
    return material_shader("eclipse:soft_particle",
                           textures={"MainTexture": texture},
                           uniforms={"SoftDistance": soft, "NearFade": near},
                           blend=blend or BLEND_ALPHA)


def build_tyrant_statue_idle() -> FxBuilder:
    """F-081 statue idle aura: embers orbit the column bottom-to-crown, the crown
    spits faint electric flecks, a mist skirt grounds the plinth in the fog.

    WAVE-13/A5 "the statue LOADS" pass — three added layers, zero new cues:

      charge_core    a heartbeat core inside the chest, five pulses across the arc,
                     each born bigger than the last (`startSize` on a duration-axis
                     curve, so the ramp is over EMITTER time, not particle life).
      crack_glimmer  the plinth's floor cracks light up from below, per-particle
                     flicker via `random_gradient`. soft_particle, so the quads
                     lie in the ground instead of slicing through it.
      indraw_motes   motes off a r=4.5 shell falling INTO the statue, with the pull
                     strengthening across the arc (negative `startSpeed` on a
                     duration-axis curve + a negative radial on top).

    WHY THE RAMP IS ASSET-LOCAL, and why that is still correct: the awaken timeline
    lives entirely in `TyrantStatue` (60 t of jitter + spark column + rising
    resonate chime) and it does NOT send an FX cue — `ensureArmed` only stamps
    `CUE_TYRANT_STATUE_IDLE` while the lair is ARMED, and the strike disarms it. So
    there is nothing to hang a "20 t before the summon" beat on without inventing a
    cue, which this wave forbids. Instead the asset's own 200 t window IS the charge
    cycle: the cue is re-sent every 40 t (`SLOW_CADENCE_TICKS`), 40 divides 200, so
    mid-run re-sends dedup to no-ops and the arc restarts cleanly every 10 s. The
    statue therefore reads as something that keeps winding itself up and never
    fires — and when a player finally strikes, the executor is at most 40 t old, so
    the in-draw and the core pulse carry straight through the whole awaken window
    underneath the vanilla telegraph."""
    fx = FxBuilder("boss/tyrant_statue_idle")

    # L1 ember orbit: born on a ring at the plinth, spiralling slowly up the column
    # (orbital + linear up-drift), fading out as they clear the crown.
    (fx.particle_emitter(
            "ember_orbit",
            duration=200, looping=False, max_particles=30,
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
    # alpha-blend, shaded, no bloom, alpha peak 0.22). Now on soft_particle — the
    # skirt sits ON whatever the statue is planted in instead of cutting into it,
    # and the speeds are back above the perception floor (Photon linear/startSpeed
    # x0.05 per tick = blocks/SECOND; 0.008 was 8 mm/s).
    (fx.particle_emitter(
            "plinth_mist",
            duration=200, looping=False, max_particles=14,
            start_lifetime=random_between(28, 40), start_speed=random_between(0.1, 0.35),
            start_size=nf3(random_between(0.35, 0.6), random_between(0.35, 0.6),
                           random_between(0.35, 0.6)),
            simulation_space="Local")
       .at(0.0, -1.55, 0.0)
       .with_emission(rate=constant(0.3))
       .with_shape(circle(radius=1.1))
       .with_material(_soft(TEX_SMOKE, soft=1.4, near=0.55))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), constant(0.16), constant(0.0)),
                radial=constant(1.2)),                 # 0.24 blk/s outward creep
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.22), (0.75, 0.15), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.55, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L4 charge core: the heartbeat in the chest. Five pulses across the 200 t arc
    # (burst cycles), each born larger than the last — the growth is a curve on the
    # EMITTER's duration axis, which is the only ramp in Photon that outlives an
    # individual particle. Two humps per life = a doubled heartbeat, not a blink.
    (fx.particle_emitter(
            "charge_core",
            duration=200, looping=False, max_particles=3,
            start_lifetime=constant(42), start_speed=constant(0.0),
            start_size=_charge3(0.55, 1.45),
            simulation_space="Local")
       .at(0.0, -0.05, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=6, count=1, cycles=5, interval=40)])
       .with_shape(sphere(radius=0.12))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.15, 1.35, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(0.25, 1.0, [
                (0.0, 0.1, 0.06, 0.95, 0.22, 0.9, 0.34, 0.35),
                (0.34, 0.35, 0.44, 0.4, 0.5, 1.0, 0.62, 1.0),
                (0.62, 1.0, 0.78, 0.85, 0.9, 0.2, 1.0, 0.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 0.55), (0.34, 0.2), (0.62, 0.7), (1.0, 0.0)],
                [(0.0, *STM_ARC), (0.5, *STM_DEEP), (1.0, *GLI_DEAD)])))

    # L5 crack glimmer: light bleeding up out of the floor cracks around the plinth.
    # Horizontal additive quads laid ON the ground — only survivable with the A0
    # SceneDepth fade, otherwise every quad shows its rectangle edge in the stone.
    # random_gradient gives each crack its own flicker profile, so the ring never
    # pulses in unison.
    (fx.particle_emitter(
            "crack_glimmer",
            duration=200, looping=False, max_particles=10,
            start_lifetime=random_between(26, 44), start_speed=constant(0.0),
            start_size=nf3(random_between(0.5, 1.15), random_between(0.5, 1.15),
                           random_between(0.5, 1.15)),
            simulation_space="Local")
       .at(0.0, -1.66, 0.0)
       .with_emission(rate=curve(0.1, 0.3, [CHARGE_RAMP], "duration", "rate"))
       .with_shape(circle(radius=1.7, thickness=0.75))
       .with_material(_soft(TEX_CIRCLE, soft=1.5, near=0.5, blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_cull_box(*CULL)
       .with_curves(
            size_over_lifetime=_size3(0.6, 1.25, [SEG_DECAY_TAIL]),
            color_over_lifetime=random_gradient(
                [(0.0, 0.0), (0.2, 0.34), (0.45, 0.1), (0.7, 0.26), (1.0, 0.0)],
                [(0.0, *STM_ARC), (0.6, *STM_DEEP), (1.0, *GLI_DEAD)],
                [(0.0, 0.0), (0.35, 0.16), (0.6, 0.4), (1.0, 0.0)],
                [(0.0, *STM_DEEP), (0.7, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L6 in-draw motes: the statue eats the fog around it, harder as the arc loads.
    # NEGATIVE startSpeed = along the shape normal, inward (the shell emits outward),
    # ramped over the emitter duration; the radial adds an accelerating tug on top so
    # the motes speed up on the last blocks instead of arriving at a crawl.
    #
    # SIGN TRAP: `curve(lower, upper, ...)` evaluates to lower + (upper-lower)*bezierY,
    # and CHARGE_RAMP rises 0.15 -> 1.0, so the ramp always runs lower -> upper. With
    # NEGATIVE speeds that means the STRONGER pull has to be `upper`, not `lower` —
    # written the other way round the statue inhales hardest at t=0 and lets go as the
    # awaken approaches, i.e. exactly backwards.
    #
    # Budget (Photon startSpeed x0.05/tick = blk/s, radial x0.01/tick = 0.2 blk/s per
    # unit): the shell is r=4.5 and lives are 42-62 t (~2.1-3.1 s). The radial alone
    # averages ~0.95 blk/s => ~2.5 blocks. Early arc adds 0.42 blk/s (~1.1 blocks), so
    # those motes dissolve ~1 block short — the statue reaches and misses. Late arc
    # adds 1.05 blk/s (~2.7 blocks), which just crosses the shell radius: the mote is
    # swallowed. Anything much stronger shoots THROUGH the statue and out the far side.
    (fx.particle_emitter(
            "indraw_motes",
            duration=200, looping=False, max_particles=18,
            start_lifetime=random_between(42, 62),
            start_speed=curve(-0.31, -1.05, [CHARGE_RAMP], "duration", "speed"),
            start_size=nf3(random_between(0.07, 0.14), random_between(0.07, 0.14),
                           random_between(0.07, 0.14)),
            simulation_space="Local")
       .at(0.0, -0.2, 0.0)
       .with_emission(rate=curve(0.16, 0.42, [CHARGE_RAMP], "duration", "rate"))
       .with_shape(sphere(radius=4.5, thickness=0.3))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.0, 1.2, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-9.0, -2.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            size_over_lifetime=_size3(0.25, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.42), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.45, *STM_DEEP), (1.0, *STM_ARC)])))
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
