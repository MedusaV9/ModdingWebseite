#!/usr/bin/env python3
"""wave6_dragon_fx — WAVE6 (F-106 B) generator: the day-13 dragon-stage Photon assets.

Authors (via fxlib, see tools/photon/README.md) the two assets behind
`veilfx/Wave6DragonFxRows` (server hooks in `worldgen/end/EclipseDragonFight`):

    eclipse:wave6_crystal_burst  B2 one-shot at a destroyed spire crystal — a cold
                                 End bloom snapping open plus rising splinters and
                                 lingering frost motes. Splinter/mote lifetimes run
                                 60-90 t, so the beat holds a photographable still
                                 image >= 3 s (llvmpipe law) after the vanilla
                                 crystal explosion (the photon-less baseline) clears.

    eclipse:wave6_dragon_wisp    B4 victory requiem loop — a quiet two-layer End
                                 wisp breathing over the dragon egg. WINDOWED-only
                                 (hysteresis 28/36 in Wave6DragonFxRows.DragonWisp,
                                 anchored on the FxAnchors egg anchor the victory
                                 path publishes and every boot re-publishes).

Loop law (INTEGRATION.md §4): the wisp is looping=True and never payload-fired;
prewarm covers the longest particle life so an opened window never reads as
"filling up". The burst is a plain payload one-shot (BURST channel row).

Style-guide conformance (FX-STYLE-GUIDE.md §1, V2.1 stacking law): dark birth
tints (alpha AND rgb rise from the dead-violet floor), cold ice/violet peaks,
additive at gentle HDR <= 1.45, CullBox on every emitter, counts trimmed.

This script IS the authoring source for the binary .fx blobs (fxlib generator in
place of an editor .fxproj; the .fxproj siblings ship beside them — binary-diff
law; node UUIDs are uuid5-deterministic inside fxlib, so a double run is
byte-identical). Run: python3 tools/photon/wave6_dragon_fx.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, FX_ASSETS_DIR, REPO_ROOT,
    FxBuilder, burst, circle, cone, constant, curve, gradient, nf3,
    random_between, sphere, texture_material, validate_file,
    SEG_DECAY_TAIL,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_SHARD = "eclipse:textures/particle/glitch_shard.png"

# FX-STYLE-GUIDE §1 tokens — the cold End family on the dead-violet floor.
END_DEAD = (0.141, 0.110, 0.220)      # #241C38 — dark birth tint (V2.1 stacking law)
END_ICE = (0.620, 0.820, 1.0)         # #9ED1FF — cold crystal-face cyan
END_VIOLET = (0.720, 0.480, 1.0)      # #B87AFF — End purple
END_PALE = (0.950, 0.780, 1.0)        # #F2C7FF — pale requiem pink-white
END_WHITE = (1.0, 1.0, 1.0)

# ---------------------------------------------------------------------------
# B2 eclipse:wave6_crystal_burst — cold End bloom + rising splinters (one-shot)
# ---------------------------------------------------------------------------
# The splinters climb ~1-2.4 blocks over their 60-80 t lives; the cull box hugs that.
BURST_CULL = ((-2.4, -0.9, -2.4), (2.4, 3.4, 2.4))


def build_crystal_burst() -> FxBuilder:
    """B2 spire-crystal death beat: 4 layers, ~26 live particles, one executor.

    bloom_core    one soft cold bloom snapping open where the crystal stood and
                  decaying slowly (70 t) — the "standbild" heart of the beat.
    burst_ring    one horizontal soft ring expanding fast (22 t impact accent).
    splinters     14 crystal shards thrown upward on a tight cone, tumbling and
                  cooling from ice-white to the dead floor over 60-80 t.
    frost_motes   8 tiny motes drifting outward at the perception floor, alive to
                  90 t — they carry the still image after the ring is gone.
    """
    fx = FxBuilder("wave6_crystal_burst")

    # L1 bloom core: born dark, blooms to the cold peak by 20%, decays to the floor.
    (fx.particle_emitter(
            "bloom_core",
            duration=8, looping=False, max_particles=2,
            start_lifetime=constant(70), start_speed=constant(0.0),
            start_size=nf3(constant(0.55), constant(0.55), constant(0.55)),
            simulation_space="World")
       .at(0.0, 0.9, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 1.3, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*BURST_CULL)
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.6, 1.0, [(0.0, 0.6, 0.06, 1.05, 0.14, 1.0, 0.3, 0.95),
                                 (0.3, 0.95, 0.55, 0.8, 0.85, 0.4, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.6, 0.06, 1.05, 0.14, 1.0, 0.3, 0.95),
                                 (0.3, 0.95, 0.55, 0.8, 0.85, 0.4, 1.0, 0.0)],
                      "lifetime", "size"),
                curve(0.6, 1.0, [(0.0, 0.6, 0.06, 1.05, 0.14, 1.0, 0.3, 0.95),
                                 (0.3, 0.95, 0.55, 0.8, 0.85, 0.4, 1.0, 0.0)],
                      "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.85), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, *END_DEAD), (0.15, *END_ICE), (0.45, *END_VIOLET),
                 (1.0, *END_DEAD)])))

    # L2 impact ring: one horizontal soft ring, 22 t, expanding 0.5 -> ~2.6 blocks.
    (fx.particle_emitter(
            "burst_ring",
            duration=8, looping=False, max_particles=2,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(constant(0.9), constant(0.9), constant(0.9)),
            simulation_space="World")
       .at(0.0, 0.35, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_RING_SOFT, hdr=(1.0, 1.15, 1.35),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*BURST_CULL)
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.5, 2.9, [(0.0, 0.17, 0.25, 0.75, 0.6, 0.95, 1.0, 1.0)],
                      "lifetime", "size"),
                curve(0.5, 2.9, [(0.0, 0.17, 0.25, 0.75, 0.6, 0.95, 1.0, 1.0)],
                      "lifetime", "size"),
                curve(0.5, 2.9, [(0.0, 0.17, 0.25, 0.75, 0.6, 0.95, 1.0, 1.0)],
                      "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.5, 0.35), (1.0, 0.0)],
                [(0.0, *END_ICE), (0.55, *END_VIOLET), (1.0, *END_DEAD)])))

    # L3 splinters: 14 shards thrown upward on a tight cone (0.35-0.6 b/s carries
    # them ~1-2.4 blocks over 60-80 t — inside the cull box, no gravity: they RISE).
    (fx.particle_emitter(
            "splinters",
            duration=8, looping=False, max_particles=18,
            start_lifetime=random_between(60, 80),
            start_speed=random_between(0.35, 0.6),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_rotation=nf3(constant(0.0), constant(0.0), random_between(0.0, 360.0)),
            simulation_space="World")
       .at(0.0, 0.7, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(cone(angle=14.0, radius=0.55, thickness=0.5))
       .with_material(texture_material(TEX_SHARD, hdr=(1.15, 1.25, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*BURST_CULL)
       .with_curves(
            rotation_over_lifetime=random_between(-120.0, 120.0),
            size_over_lifetime=nf3(curve(0.45, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.45, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.45, 1.0, [SEG_DECAY_TAIL], "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.95), (0.6, 0.55), (1.0, 0.0)],
                [(0.0, *END_DEAD), (0.12, *END_WHITE), (0.4, *END_ICE),
                 (0.75, *END_VIOLET), (1.0, *END_DEAD)])))

    # L4 frost motes: 8 tiny slow drifters alive to 90 t — the >= 3 s still image.
    (fx.particle_emitter(
            "frost_motes",
            duration=8, looping=False, max_particles=10,
            start_lifetime=random_between(70, 90),
            start_speed=random_between(0.06, 0.12),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            simulation_space="World")
       .at(0.0, 1.0, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(sphere(radius=0.5))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.05, 1.2, 1.4),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*BURST_CULL)
       .with_curves(
            size_over_lifetime=nf3(curve(0.5, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.5, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.5, 1.0, [SEG_DECAY_TAIL], "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.45), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *END_DEAD), (0.4, *END_ICE), (1.0, *END_DEAD)])))
    return fx


# ---------------------------------------------------------------------------
# B4 eclipse:wave6_dragon_wisp — requiem loop over the egg (WINDOWED-only)
# ---------------------------------------------------------------------------
# The whole set lives within ~a block of the egg; the loop cull box hugs it.
WISP_CULL = ((-1.5, -1.0, -1.5), (1.5, 2.4, 1.5))

#: Loop cycle length (ticks). Prewarm >= the longest particle life (70 t) so a
#: freshly-opened window shows the settled wisp, not an empty ramp-up.
LOOP_DURATION = 100
PREWARM = 70


def build_dragon_wisp() -> FxBuilder:
    """B4 requiem resonance (wave5_trophy_wisp sibling, End palette): two layers,
    ~8 live particles, one executor.

    wisp_orbit   2-3 small motes born on a tight ring just above the egg,
                 spiralling slowly upward and dying ~1.3 blocks up.
    crown_halo   one soft breathing glow hovering over the egg — the "the dragon
                 fell here" read between mote births.
    """
    fx = FxBuilder("wave6_dragon_wisp")

    # L1 wisp orbit: born dark on a r=0.35 ring, alpha and rgb rise off the END_DEAD
    # floor mid-life, gone before y+1.5. Speeds sit just above the perception floor.
    (fx.particle_emitter(
            "wisp_orbit",
            duration=LOOP_DURATION, looping=True, prewarm=PREWARM, max_particles=6,
            start_lifetime=random_between(50, 70), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="Local")
       .at(0.0, 0.3, 0.0)
       .with_emission(rate=constant(0.06))
       .with_shape(circle(radius=0.35))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.15, 1.1, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*WISP_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital=nf3(constant(0.0), random_between(0.8, 1.4), constant(0.0)),
                linear=nf3(constant(0.0), constant(0.4), constant(0.0)),
                radial=constant(0.25)),
            size_over_lifetime=nf3(curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
                                   curve(0.4, 1.0, [SEG_DECAY_TAIL], "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, *END_DEAD), (0.45, *END_VIOLET), (0.85, *END_PALE),
                 (1.0, *END_DEAD)])))

    # L2 crown halo: a single soft glow breathing over the egg. Alpha peak stays low
    # (0.3) — this idles for minutes over the portal podium.
    (fx.particle_emitter(
            "crown_halo",
            duration=LOOP_DURATION, looping=True, prewarm=PREWARM, max_particles=2,
            start_lifetime=constant(60), start_speed=constant(0.0),
            start_size=nf3(random_between(0.24, 0.32), random_between(0.24, 0.32),
                           random_between(0.24, 0.32)),
            simulation_space="Local")
       .at(0.0, 0.6, 0.0)
       .with_emission(rate=constant(0.034))
       .with_shape(sphere(radius=0.08))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 1.05, 1.35),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*WISP_CULL)
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
                [(0.0, *END_DEAD), (0.5, *END_VIOLET), (1.0, *END_DEAD)])))
    return fx


BUILDERS = {
    "wave6_crystal_burst.fx": build_crystal_burst,
    "wave6_dragon_wisp.fx": build_dragon_wisp,
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
