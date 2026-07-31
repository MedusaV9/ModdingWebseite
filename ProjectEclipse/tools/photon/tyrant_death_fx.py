#!/usr/bin/env python3
"""tyrant_death_fx — WAVE-13/A5 generator: the Fog Tyrant DEATH IMPLOSION cascade.

Authors the four assets behind `FxCues.CUE_TYRANT_DEATH_IMPLOSION` (row in
`veilfx/BossPhotonFxRows`, fired by `FogTyrantEntity.tickDeath` at
`DEATH_THUNDERCLAP_TICK`, body centre +1.5, range 96):

    eclipse:boss/tyrant_death_collapse   ROOT. The storm falls INTO the corpse:
                                         a heavy slate slab shell, faster shreds
                                         and a floor drag, all on negative radial
                                         speeds, converging on a seed particle.
    eclipse:boss/tyrant_collapse_core    stage 1 (Birth child of the seed): the
                                         collapse point — fresnel dome snap +
                                         last gulp motes.
    eclipse:boss/tyrant_shock_ring       stage 2 (Birth child of the dome): the
                                         ground shock ring + its dust crown.
    eclipse:boss/tyrant_soul_wisp        stage 3 (Birth child of the ring dust):
                                         a soul wisp rising off the ring.

Why a NEW root instead of editing `boss/tyrant_death_implosion`: conflict law §7.1 —
one .fx belongs to exactly one generator, and the shipped implosion is authored by
`boss_b_fx.py` (team A4's file this wave). The A5 row repoint in `BossPhotonFxRows`
swings the cue onto this cascade; the legacy asset stays on disk, unreferenced,
until its owning generator can retire it.


================  BIRTH-SUB-EMITTER CHAIN — the repo's first  ================

Census gap "Birth-SubEmitter 0": all 11 shipped `subEmitters` rows fire on
Death/Collision/FirstCollision/Tick. This is the blueprint for Birth chains; copy
the shape, not the numbers.

HOW IT WORKS (jar-verified against photon-neoforge-1.21.1-2.1.5):

  * `TileParticle.updateTick()` fires `subEmitters.triggerEvent(this, Event.Birth)`
    on the FIRST tick a particle is alive (`age == 0`, after the spawn delay has
    run out) — before ageing, before the physics/velocity update.
  * `SubEmittersSetting$Emitter.spawnEmitter(p)` then: `age % tickInterval != 0` →
    skip; `random.nextFloat() >= emitProbability` → skip; else
    `FXHelper.getFX(fxLocation)` → `FX.createRuntime()` →
    `runtime.root.updatePos(p.getWorldPos())`. So the child is a WHOLE .fx file
    stamped at the parent particle's birth position, running its own timeline.

CONSEQUENCES THAT SHAPE THE AUTHORING (all of them bit us while tuning):

  1. Birth position == the emission-shape point, NOT wherever the particle ends up.
     A chain link that must fan out in space has to be born already fanned out
     (`ring_dust` is born on a r=5.5 circle for exactly this reason) — you cannot
     let it travel first, because Birth has already fired.
  2. The child does not inherit timing. Sequencing a cascade = staggering the
     PARENT particles' birth times (the root's seed particle is burst at t=30, so
     stage 1 lands when the in-fall converges), not delaying the child.
  3. Every stamp deep-copies an FX runtime, so fan-out is multiplicative. This
     chain is deliberately 1 → 1 → ~3: seed(1) → dome(1) → ring(1) → 6 dust ×
     p=0.55 ≈ 3 wisps × 7 particles. `fxlib` lints child burst sums > 8
     (LINT-SUBEM-FAT) — keep every link under it.
  4. `emitProbability` is a NumberFunction evaluated at the parent's t, so a curve
     there varies the fan-out over the emitter's life. Constants here: the beat is
     a one-shot, there is nothing to vary against.
  5. Failure is silent: an unresolvable `fxLocation` is a no-op (lint rule
     LINT-SUBEM-RESOLVE catches it at authoring time instead).

Speeds are Photon units, NOT blocks/tick: `startSpeed`/`linear` × 0.05 per tick
(= 1 unit ≈ 1 block/SECOND), `radial` × 0.01 per tick (= 1 unit ≈ 0.2 block/s).
An in-fall that has to cross 10 blocks in ~28 t therefore needs radial ≈ −36, not
−0.4 — the pre-wave assets that used −0.4 moved a tenth of a block and read as
static.

Style-guide conformance (FX-STYLE-GUIDE §1 / wave-13 stacking law): fog family
stays desaturated slate (birth tint STM_SLATE / GLI_DEAD — never a light birth
tint, dozens of alpha quads converge to it), alpha peaks ≤ 0.45, HDR ≤ 1.45 and
only on the dome rim and the soul glints, every alpha pass sorts DISTANCE, all
fog bodies run the A0 `eclipse:soft_particle` shader so the collapse does not saw
through the arena floor.

This script IS the authoring source for the binary .fx blobs. Run:
python3 tools/photon/tyrant_death_fx.py
python3 tools/photon/fxlib.py validate --lint
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, constant, curve, gradient, material_shader, nf3,
    random_between, sphere, sub_emitter, texture_material, validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_OVERSHOOT_SETTLE,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING = "photon:textures/particle/ring.png"

# FX-STYLE-GUIDE §1 tokens (the tyrant fog family + the storm blues for the souls).
FOG_TEAL = (0.55, 0.66, 0.65)         # desaturated grey-teal fog body
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55 — the dark birth tint
GLI_DEAD = (0.141, 0.110, 0.220)      # #241C38 — deep dead indigo
STM_ARC = (0.749, 0.851, 1.0)         # #BFD9FF — electric pale (souls, rim)
STM_DEEP = (0.353, 0.553, 0.933)      # #5A8DEE

# The cue fires at body centre (+1.5 above the feet): local y = -1.5 IS the floor.
FLOOR_Y = -1.5

ROOT_CULL = ((-14.0, -4.0, -14.0), (14.0, 10.0, 14.0))
CHILD_CULL = ((-16.0, -4.0, -16.0), (16.0, 9.0, 16.0))
WISP_CULL = ((-4.0, -3.0, -4.0), (4.0, 8.0, 4.0))


def _size3(lower, upper, segments):
    """Uniform xyz size_over_lifetime from one bezier curve spec."""
    return nf3(curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"),
               curve(lower, upper, segments, "lifetime", "size"))


def _soft(texture, soft=1.2, near=0.7):
    """The A0 soft-particle fog material at the wave-13 fog settings."""
    return material_shader("eclipse:soft_particle",
                           textures={"MainTexture": texture},
                           uniforms={"SoftDistance": soft, "NearFade": near},
                           blend=BLEND_ALPHA)


# ---------------------------------------------------------------------------
# stage 3 — eclipse:boss/tyrant_soul_wisp (Birth child of the ring dust)
# ---------------------------------------------------------------------------
def build_soul_wisp() -> FxBuilder:
    """One soul torn loose where the shock ring passed: a slow pale wisp climbing
    out of the fog with a few glints trailing it. Stamped ~3x around the ring, so
    the whole beat reads as the storm's dead giving up their light.

    Chain terminus — carries NO sub-emitters of its own (rule 3: the fan-out has
    to stop somewhere, and this is the leaf)."""
    fx = FxBuilder("boss/tyrant_soul_wisp")

    # The wisp body: born at floor level, rising ~3 blocks over its life while it
    # thins out. Soft-particle so it does not razor-cut the ground it climbs from.
    (fx.particle_emitter(
            "wisp_rise",
            duration=50, looping=False, max_particles=6,
            start_lifetime=random_between(38, 50), start_speed=constant(0.0),
            start_size=nf3(random_between(0.4, 0.7), random_between(0.4, 0.7),
                           random_between(0.4, 0.7)),
            simulation_space="World")
       .at(0.0, 0.2, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=3)])
       .with_shape(sphere(radius=0.45, thickness=0.7))
       .with_material(_soft(TEX_SMOKE, soft=0.8, near=0.5))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*WISP_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(1.2, 1.9), constant(0.0)),
                orbital=nf3(constant(0.0), random_between(-0.5, 0.5), constant(0.0))),
            size_over_lifetime=_size3(0.35, 1.25, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.4), (0.7, 0.24), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.45, *STM_DEEP), (1.0, *GLI_DEAD)])))

    # Glints riding the wisp — the only bright element in the leaf (HDR 1.45 cap).
    (fx.particle_emitter(
            "wisp_glints",
            duration=50, looping=False, max_particles=8,
            start_lifetime=random_between(20, 34), start_speed=random_between(0.2, 0.6),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World")
       .at(0.0, 0.35, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=4)])
       .with_shape(sphere(radius=0.35, thickness=0.5))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.15, 1.3, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*WISP_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(0.9, 1.6), constant(0.0))),
            size_over_lifetime=_size3(0.2, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.75), (0.7, 0.4), (1.0, 0.0)],
                [(0.0, *STM_ARC), (0.6, *STM_DEEP), (1.0, *GLI_DEAD)])))
    return fx


# ---------------------------------------------------------------------------
# stage 2 — eclipse:boss/tyrant_shock_ring (Birth child of the dome snap)
# ---------------------------------------------------------------------------
def build_shock_ring() -> FxBuilder:
    """The floor answer to the collapse: one horizontal ring sheet blowing out to
    ~24 blocks plus a low dust crown — and the crown is where the chain branches.

    CHAIN NOTE (rule 1): `ring_dust` is born ON a r=5.5 circle, not at the centre,
    precisely because Birth fires at the birth position. Spread the PARENTS to
    spread the children; letting the dust travel outward first would stamp every
    wisp on top of the corpse."""
    fx = FxBuilder("boss/tyrant_shock_ring")

    # The ring sheet. soft_particle turns the classic hard "decal slicing through
    # the terrain" edge into a ground-hugging intersection glow (a wide SoftDistance
    # is what makes the sheet kiss slopes instead of cutting them).
    (fx.particle_emitter(
            "ring_sheet",
            duration=30, looping=False, max_particles=2,
            start_lifetime=constant(28), start_speed=constant(0.0),
            start_size=nf3(constant(1.0), constant(1.0), constant(1.0)),
            simulation_space="World")
       .at(0.0, FLOOR_Y + 0.12, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(_soft(TEX_RING, soft=1.8, near=0.6))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_cull_box(*CHILD_CULL)
       .with_curves(
            size_over_lifetime=_size3(0.6, 24.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.45), (0.62, 0.24), (1.0, 0.0)],
                [(0.0, *STM_ARC), (0.4, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # The dust crown — 6 low fog puffs already sitting on the ring's path. Each one
    # is a Birth parent for stage 3 (p 0.55 => ~3 wisps, rule 3's fan-out budget).
    (fx.particle_emitter(
            "ring_dust",
            duration=30, looping=False, max_particles=8,
            start_lifetime=random_between(24, 34), start_speed=random_between(1.0, 2.2),
            start_size=nf3(random_between(0.8, 1.4), random_between(0.8, 1.4),
                           random_between(0.8, 1.4)),
            simulation_space="World")
       .at(0.0, FLOOR_Y + 0.4, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=6)])
       .with_shape(circle(radius=5.5, thickness=0.35))
       .with_material(_soft(TEX_SMOKE, soft=1.3, near=0.6))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CHILD_CULL)
       .with_sub_emitters(sub_emitter("eclipse:boss/tyrant_soul_wisp",
                                      event="Birth", probability=0.55))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(9.0)),   # 1.8 blk/s outward
            size_over_lifetime=_size3(0.5, 1.7, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.4), (0.7, 0.26), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *FOG_TEAL), (1.0, *GLI_DEAD)])))
    return fx


# ---------------------------------------------------------------------------
# stage 1 — eclipse:boss/tyrant_collapse_core (Birth child of the root's seed)
# ---------------------------------------------------------------------------
def build_collapse_core() -> FxBuilder:
    """The collapse point itself: the in-fall arrives, folds into a dark dome that
    snaps open once (A0 `eclipse:fresnel_shell` — transparent face, glowing rim,
    a lit seam where it cuts the arena floor) and swallows the last gulp motes.

    The dome particle is the chain's stage-1 → stage-2 link: ONE particle, Birth
    probability 1.0, so exactly one shock ring is ever stamped."""
    fx = FxBuilder("boss/tyrant_collapse_core")

    # The dome. Overshoot-settle size so it punches out and relaxes; rim HDR sits
    # exactly on the wave-13 1.45 ceiling (rgb x a), the face stays near-transparent
    # so it never reads as a white balloon over the corpse.
    (fx.particle_emitter(
            "dome_snap",
            duration=26, looping=False, max_particles=2,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(constant(4.2), constant(4.2), constant(4.2)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.34, 0.38, 0.52, 0.7),
                      "RimHDRColor": (1.1, 1.25, 1.45, 1.0),
                      "FresnelPower": 2.8, "FaceAlpha": 0.05,
                      "IntersectWidth": 0.45},
            blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*CHILD_CULL)
       .with_sub_emitters(sub_emitter("eclipse:boss/tyrant_shock_ring",
                                      event="Birth", probability=1.0))
       .with_curves(
            size_over_lifetime=_size3(0.12, 1.0, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 1.0), (0.72, 0.8), (1.0, 0.0)],
                [(0.0, *STM_ARC), (0.55, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # The last gulp: what the in-fall could not swallow gets pulled the final metre.
    (fx.particle_emitter(
            "gulp_motes",
            duration=26, looping=False, max_particles=8,
            start_lifetime=random_between(14, 20), start_speed=constant(0.0),
            start_size=nf3(random_between(0.3, 0.55), random_between(0.3, 0.55),
                           random_between(0.3, 0.55)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=6)])
       .with_shape(sphere(radius=2.4, thickness=0.3))
       .with_material(_soft(TEX_SMOKE, soft=0.9, near=0.5))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*CHILD_CULL)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-26.0)),  # 5.2 blk/s inward
            size_over_lifetime=_size3(0.1, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.45), (0.75, 0.28), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *FOG_TEAL), (1.0, *GLI_DEAD)])))
    return fx


# ---------------------------------------------------------------------------
# ROOT — eclipse:boss/tyrant_death_collapse
# ---------------------------------------------------------------------------
def build_death_collapse() -> FxBuilder:
    """C8 thunderclap, wave-13 form: the storm the tyrant WAS falls into the hole
    where it stood, then the hole answers in three beats.

    Layering follows the mass law (heavy = low + slow):
      L1 slab_infall   r=10 shell, big slow bodies, radial ramping -14 -> -52
                       (2.8 -> 10.4 blk/s) so the collapse ACCELERATES.
      L2 shred_infall  r=6.5, small fast rags at a flat -40 (8 blk/s).
      L3 floor_drag    horizontal sheets scraped inward across the arena floor.
      L4 collapse_seed ONE particle at the convergence point, burst at t=30 —
                       the Birth link that fires the whole cascade (rule 2: the
                       cascade is sequenced by WHEN this parent is born).
    """
    fx = FxBuilder("boss/tyrant_death_collapse")

    # L1 — the slab. This is the mass: 34 fat slate bodies from a 10-block shell,
    # accelerating inward (SEG_DECAY_TAIL on the radial curve holds them slow, then
    # drops them into the throat).
    (fx.particle_emitter(
            "slab_infall",
            duration=34, looping=False, max_particles=40,
            start_lifetime=random_between(26, 33), start_speed=constant(0.0),
            start_size=nf3(random_between(1.1, 2.0), random_between(1.1, 2.0),
                           random_between(1.1, 2.0)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=34)])
       .with_shape(sphere(radius=10.0, thickness=0.22))
       .with_material(_soft(TEX_SMOKE, soft=1.5, near=0.9))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*ROOT_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-52.0, -14.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            size_over_lifetime=_size3(0.25, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.45), (0.72, 0.3), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.55, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L2 — the rags. Faster, smaller, born closer: they arrive first and give the
    # slab something to be slow against (the depth stratification of the fog arms,
    # replayed as a collapse).
    (fx.particle_emitter(
            "shred_infall",
            duration=34, looping=False, max_particles=32,
            start_lifetime=random_between(14, 19), start_speed=constant(0.0),
            start_size=nf3(random_between(0.28, 0.6), random_between(0.28, 0.6),
                           random_between(0.28, 0.6)),
            simulation_space="World")
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=2, count=13, cycles=2, interval=9)])
       .with_shape(sphere(radius=6.5, thickness=0.5))
       .with_material(_soft(TEX_SMOKE, soft=0.9, near=0.5))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*ROOT_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=constant(-40.0),                # 8 blk/s inward, flat
                linear=nf3(constant(0.0), random_between(-0.4, 0.8), constant(0.0))),
            size_over_lifetime=_size3(0.2, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.16, 0.4), (0.68, 0.24), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.5, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L3 — the floor drag: the ground fog is scraped inward too, so the collapse
    # owns the whole arena floor and not just the air above it.
    (fx.particle_emitter(
            "floor_drag",
            duration=34, looping=False, max_particles=20,
            start_lifetime=random_between(22, 30), start_speed=constant(0.0),
            start_size=nf3(random_between(1.6, 2.6), random_between(1.6, 2.6),
                           random_between(1.6, 2.6)),
            simulation_space="World")
       .at(0.0, FLOOR_Y + 0.18, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=16)])
       .with_shape(circle(radius=9.0, thickness=0.3))
       .with_material(_soft(TEX_SMOKE, soft=1.7, near=0.7))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*ROOT_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-38.0, -12.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            size_over_lifetime=_size3(0.4, 1.1, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.34), (0.75, 0.22), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.55, *FOG_TEAL), (1.0, *GLI_DEAD)])))

    # L4 — the seed. One particle, born at t=30 exactly where the in-fall meets,
    # and the only thing in this file that knows about the chain. Everything after
    # this point is stamped by Photon, not by the server.
    (fx.particle_emitter(
            "collapse_seed",
            duration=40, looping=False, max_particles=2,
            start_lifetime=constant(9), start_speed=constant(0.0),
            start_size=nf3(constant(1.1), constant(1.1), constant(1.1)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=30, count=1)])
       .with_shape(sphere(radius=0.05))
       .with_material(_soft(TEX_SMOKE, soft=0.8, near=0.4))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*ROOT_CULL)
       .with_sub_emitters(sub_emitter("eclipse:boss/tyrant_collapse_core",
                                      event="Birth", probability=1.0))
       .with_curves(
            size_over_lifetime=_size3(0.15, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.45), (1.0, 0.0)],
                [(0.0, *GLI_DEAD), (1.0, *GLI_DEAD)])))
    return fx


# ---------------------------------------------------------------------------
# main — children first so the parents' fxLocation refs always resolve on a
# clean checkout (LINT-SUBEM-RESOLVE reads them off disk).
# ---------------------------------------------------------------------------
BUILDERS = {
    "boss/tyrant_soul_wisp.fx": build_soul_wisp,
    "boss/tyrant_shock_ring.fx": build_shock_ring,
    "boss/tyrant_collapse_core.fx": build_collapse_core,
    "boss/tyrant_death_collapse.fx": build_death_collapse,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        builder = builder_fn()
        raw_len, gz_len = builder.write(path)  # write() round-trip + shader-ref validates
        proj_len = builder.write_fxproj(path.with_suffix(".fxproj"))
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B, "
                  f"fxproj {proj_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
