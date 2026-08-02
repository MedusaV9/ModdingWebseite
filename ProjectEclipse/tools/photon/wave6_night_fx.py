#!/usr/bin/env python3
"""wave6_night_fx — WAVE6 (F-106 Team A "Umbral-Uhr & Nacht-Dread") generator: the two
night-loop one-shot assets behind `veilfx/Wave6NightFxRows.java`:

  eclipse:wave6_pack_land     A4 — the landed Umbral Stalker pack's stage (fired by
                              EclipseSpawner.spawnStalkerPack on the shared cue lane,
                              range = the howl's 64 blocks): a low, near-black violet
                              ground-fog ring breathing outward + 3-4 brief eye-glint
                              points blinking at stalker eye height inside the fog.
                              One-shot <= 60 t (last birth t14 + 22 t life = 36 t for
                              the glints, t8 + 52 t = 60 t for the fog) — the plan's
                              hard one-shot budget for the beat.
  eclipse:wave6_dawn_release  A6 — the morning release, the INVERSE of wave3_omen_
                              umbral's reverse gulp (personal sendFxEventTo lane at
                              the receiving player's feet, EclipseSpawner.clear-
                              NightEvent): an ivory mote ring rising OUT of the ground
                              and dissolving toward bone-white, under one soft exhale
                              halo rolling off the chest. ~5 s one-shot (the
                              wave3_night_omen personal-lane duration precedent).

House laws applied (wave3_fx.py / credits5 precedent, V2.1 stacking law):

  1. UNITS. `linear` is blocks per SECOND (x0.05/tick), `radial` is x0.01/tick —
     every motion number below is back-solved from the distance its own comment
     promises.
  2. Dark birth tints on every stacking layer (alpha AND rgb rise off a near-black
     floor); HDR clamped to the 1.45 ceiling with the hue ratio preserved.
  3. `random_gradient` (via `varied()`) on every emitter with a real population.
  4. arc_mode stays the fxlib default "Random"; alpha-blended smoke is
     DISTANCE-sorted; every emitter carries a cull box.
  5. One-shots only — no loops, no prewarm; Photon's same-anchor dedup stays on
     registry-side (Wave6NightFxRows keeps allowMulti=false).

This script IS the authoring source for the binary .fx blobs (never hand-edit the
gzip-NBT); the .fxproj siblings ship beside them (binary-diff law). Node UUIDs are
uuid5-deterministic inside fxlib, so a double run is byte-identical.
Run: python3 tools/photon/wave6_night_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, constant, curve, nf3, random_between,
    random_gradient, texture_material, validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_POP_SHRINK,
)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# ---------------------------------------------------------------------------
# Palettes — FX-STYLE-GUIDE §1 tokens, local copies per generator (fxlib frozen).
# Birth tints start DARK (V2.1 stacking law).
# ---------------------------------------------------------------------------
UMBRA_BIRTH = (0.141, 0.110, 0.220)   # GLI_DEAD 241C38 — dark birth floor
UMBRA_MID = (0.616, 0.306, 0.867)     # COR_VIOLET 9D4EDD
UMBRA_INK = (0.235, 0.035, 0.424)     # COR_INK 3C096C
GLI_CYAN = (0.310, 0.910, 1.0)        # 4FE8FF — the stalker glowmask's shard light
GLI_WHITE = (0.965, 0.937, 1.0)       # SAC_HOT F6EFFF — glint/mote peak
PALE_BIRTH = (0.11, 0.11, 0.17)       # dark pre-ERA_SHADOW
PALE_MID = (0.749, 0.851, 1.0)        # STM_ARC BFD9FF
PALE_DIM = (0.227, 0.227, 0.333)      # ERA_SHADOW 3A3A55 — the bone-white fade-out
DUST_BIRTH_VIOLET = (0.022, 0.012, 0.038)  # near-black alpha-haze birth (credits5)

#: Stacking-law HDR ceiling (V2.1 — "HDR ~1.45").
HDR_CEILING = 1.45
#: Photon's authored-unit -> per-tick factors (jar: VelocityOverLifetimeSetting).
TICK_SECONDS = 0.05
RADIAL_TICK = 0.01


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def radial_for(blocks, lifetime_ticks):
    """Authored `velocityOverLifetime.radial` carrying a particle `blocks` far over
    `lifetime_ticks` (radial unit = x0.01 blocks/tick)."""
    return round(blocks / (lifetime_ticks * RADIAL_TICK), 2)


# ---------------------------------------------------------------------------
# 1. eclipse:wave6_pack_land — A4 stalker-pack landing stage (<= 60 t one-shot)
# ---------------------------------------------------------------------------
def build_pack_land() -> FxBuilder:
    fx = FxBuilder("wave6_pack_land")
    root = fx.empty("pack_land_root")

    # Ground fog: a near-black violet ring hugging the grass and breathing 2.2 blocks
    # outward over its 40-52t life (4.23 x 0.01 x 52 = 2.2) — the pack's arrival
    # exhaled into the night. Whisper alpha (peak 0.16), alpha-blended body layer,
    # DISTANCE-sorted. Last birth t8 + 52t = 60t: the plan's one-shot ceiling.
    (fx.particle_emitter(
            "land_fog_ring",
            duration=60, looping=False, start_lifetime=random_between(40, 52),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.8, 2.6), random_between(1.8, 2.6),
                           random_between(1.8, 2.6)),
            simulation_space="Local", max_particles=9)
        .child_of(root)
        .at(0.0, 0.25, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(5)),
                               burst(time=8, count=constant(3))])
        .with_shape(circle(radius=1.6, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(2.2, 52))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.16), (0.7, 0.1), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH_VIOLET), (0.3, *UMBRA_INK), (1.0, *UMBRA_BIRTH)],
                [(0.0, *DUST_BIRTH_VIOLET), (0.3, 0.16, 0.08, 0.28),
                 (1.0, *UMBRA_BIRTH)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-6.5, -2.0, -6.5), (6.5, 4.0, 6.5)))

    # Eye glints: 3-4 blinking point-pairs at stalker eye height inside the fog —
    # born dark, popping to a cyan-white pinprick (the glowmask shard palette) and
    # gone in 14-22t (SEG_POP_SHRINK). Two staggered bursts read as the pack turning
    # its heads toward you one by one. Near-zero drift: eyes hold still and STARE.
    (fx.particle_emitter(
            "land_eye_glints",
            duration=60, looping=False, start_lifetime=random_between(14, 22),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.07, 0.11), random_between(0.07, 0.11),
                           random_between(0.07, 0.11)),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .at(0.0, 0.85, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=6, count=constant(4)),
                               burst(time=14, count=constant(3))])
        .with_shape(circle(radius=2.3, thickness=0.35))
        .with_curves(
            size_over_lifetime=nf3(curve(0.0, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
                                   curve(0.0, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
                                   curve(0.0, 1.0, [SEG_POP_SHRINK], "lifetime", "size")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.75), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, *UMBRA_BIRTH), (0.35, *GLI_CYAN), (0.7, *GLI_WHITE),
                 (1.0, *UMBRA_BIRTH)],
                [(0.0, *UMBRA_BIRTH), (0.35, *UMBRA_MID), (0.7, *GLI_CYAN),
                 (1.0, *UMBRA_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 1.35, 1.45),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box((-6.5, -2.0, -6.5), (6.5, 4.0, 6.5)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:wave6_dawn_release — A6 morning release (the omen, inverted; ~5 s)
# ---------------------------------------------------------------------------
def build_dawn_release() -> FxBuilder:
    fx = FxBuilder("wave6_dawn_release")
    root = fx.empty("dawn_release_root")

    # Rising mote ring: the umbral gulp ran DOWN into the ground — the release runs
    # back UP: ivory motes born at the ankles on a r=1.5 ring, rising 1.8-2.4 blocks
    # (0.6 b/s x 0.05 x 60-80t) with a gentle 0.8-block outward drift (1.14 x 0.01 x
    # 70) — the ring opens as it lifts, "the night letting go of you". Brightens off
    # the dark floor to a bone-white peak, then dissolves (SEG_DECAY_TAIL).
    (fx.particle_emitter(
            "release_motes",
            duration=100, looping=False, start_lifetime=random_between(60, 80),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.11, 0.18)),
            simulation_space="Local", max_particles=34)
        .child_of(root)
        .at(0.0, 0.15, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(18)),
                               burst(time=14, count=constant(12))])
        .with_shape(circle(radius=1.5, thickness=0.35))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.6), constant(0)),
                radial=constant(radial_for(0.8, 70))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.45), (0.75, 0.22), (1.0, 0.0)],
                [(0.0, *PALE_BIRTH), (0.35, *PALE_MID), (0.7, *GLI_WHITE),
                 (1.0, *PALE_DIM)],
                [(0.0, *PALE_BIRTH), (0.35, *GLI_WHITE), (0.7, *PALE_MID),
                 (1.0, *PALE_DIM)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 1.25, 1.4),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box((-6.0, -2.0, -6.0), (6.0, 6.0, 6.0)))

    # Exhale halo: one thin chest-height ring breathing 2.8 blocks outward over its
    # 44-52t life (5.38 x 0.01 x 52) — the held breath of the night released in one
    # slow roll (the pale_halo inversion: warm-white instead of cold arc-silver).
    (fx.particle_emitter(
            "release_halo",
            duration=100, looping=False, start_lifetime=random_between(44, 52),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.13, 0.19)),
            simulation_space="Local", max_particles=14)
        .child_of(root)
        .at(0.0, 1.25, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=8, count=constant(12))])
        .with_shape(circle(radius=0.9, thickness=0.08))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(2.8, 52))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.22), (0.7, 0.12), (1.0, 0.0)],
                [(0.0, *PALE_BIRTH), (0.25, *GLI_WHITE), (0.75, *PALE_MID),
                 (1.0, *PALE_DIM)],
                [(0.0, *PALE_BIRTH), (0.25, *PALE_MID), (0.75, *GLI_WHITE),
                 (1.0, *PALE_DIM)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 1.15, 1.3),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box((-6.0, -2.0, -6.0), (6.0, 4.0, 6.0)))

    # Lift glows: three big soft lights drifting up 0.9-1.2 blocks (0.35 b/s x 0.05 x
    # 50-70t) and dissolving — the body of the release under the mote points, easing
    # in (SEG_EASE_OUT_CREST) so the dissolve reads as a swell, not a pop.
    (fx.particle_emitter(
            "release_lift",
            duration=100, looping=False, start_lifetime=random_between(50, 70),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.9, 1.3), random_between(0.9, 1.3),
                           random_between(0.9, 1.3)),
            simulation_space="Local", max_particles=4)
        .child_of(root)
        .at(0.0, 0.6, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=4, count=constant(3))])
        .with_shape(circle(radius=0.7, thickness=0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.35), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.35, 0.12), (0.75, 0.07), (1.0, 0.0)],
                [(0.0, *PALE_BIRTH), (0.4, *PALE_MID), (1.0, *PALE_DIM)],
                [(0.0, *PALE_BIRTH), (0.4, 0.85, 0.88, 1.0), (1.0, *PALE_DIM)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.05, 1.1, 1.25),
                                        blend=BLEND_ADDITIVE))
        .with_cull_box((-6.0, -2.0, -6.0), (6.0, 6.0, 6.0)))
    return fx


BUILDERS = {
    "wave6_pack_land.fx": build_pack_land,
    "wave6_dawn_release.fx": build_dawn_release,
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
