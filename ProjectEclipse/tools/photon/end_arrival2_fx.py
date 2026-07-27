#!/usr/bin/env python3
"""end_arrival2_fx — F-077 V2 "GIGANTISMUS" Photon `.fx` assets.

The End-arrival V2 upgrade pass (docs/plans_v3/feedback3/PLAN-F077-end-erscheinen-
cutscene.md): four NEW assets layered on top of the shipped end_arrival_* suite
(end_arrival_fx.py — untouched, the `end_arrival2_` prefix rule). Rows live in
`veilfx/EndArrivalFxRows`; cue ids in `sequence/endarrival/EndArrivalFxCues`.

Palette: the same SAC violet family + GLI accents as end_arrival_fx.py — one look,
one event.

Assets (all ONE-SHOTS — the long-lived trail/ambient lean on Photon's
allowMulti=false dedup for the sequence's / EndRiftAmbient's re-fire cadence):

  end_arrival2_glyphs        Beat-1 omen (~80t, anchor = altar top + 40): a rune ring
                             of glitch squares gathering on a r=12 circle, slowly
                             contracting while orbiting, plus converging HOT motes.
                             Dies naturally ON the t=160 erupt beat.
  end_arrival2_strand_trail  Beat-3 (620t, anchor = altar top, authored 260 tall):
                             the comet-trail sheath around the three debris helix
                             strands — braided streak traffic climbing the column
                             at the strands' radius, with falling residue dust. The
                             client row Y-scales the executor onto the real
                             altar->rift gap (payload a), the end_arrival_pillar law.
  end_arrival2_island_ring   Beat-3 wave stamp (~50t, anchor = disc center at surface
                             height, authored radius 60): one giant flat HDR shock
                             ring expanding across the assembly annulus + an outward
                             spark scatter. The client row XZ-scales by (payload a /
                             60) so the ring lands on the completing wave's radius.
  end_arrival2_rift_ambient  Permanent (~660t one-shot, anchor = disc center + 40):
                             the SUBTLE end-rift residue that stays over the disc
                             forever — a faint dark shimmer vortex, sparse violet
                             motes and rare falling star sparks. worldgen/end/
                             EndRiftAmbient re-fires it every 600t (dedup absorbs).

Run:  python3 tools/photon/end_arrival2_fx.py     # writes + validates all 4 assets
(write() round-trip-validates; every .fx gets its .fxproj sibling — binary-diff law.)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"

# --- palette (FX-STYLE-GUIDE §1 SAC family + GLI accents; == end_arrival_fx.py) ----
HOT = (0.965, 0.937, 1.0)          # SAC_HOT F6EFFF
VIOLET = (0.725, 0.549, 1.0)       # SAC_VIOLET B98CFF
DEEP = (0.482, 0.310, 0.816)       # SAC_DEEP 7B4FD0
VOID = (0.180, 0.137, 0.278)       # SAC_VOID 2E2347
MAGENTA = (1.0, 0.310, 0.847)      # GLI_MAGENTA FF4FD8
CYAN = (0.310, 0.910, 1.0)         # GLI_CYAN 4FE8FF

# --- sync contracts (keep in step with EndArrivalSequence / EndArrivalFxRows) ------
# The strand trail is authored 260 blocks tall like end_arrival_pillar; the client row
# scales the executor's Y by (payload a / TRAIL_MODEL_HEIGHT).
TRAIL_MODEL_HEIGHT = 260.0
TRAIL_TICKS = 620
# The island ring is authored at radius 60; the row XZ-scales by (payload a / 60).
RING_MODEL_RADIUS = 60.0
# The ambient one-shot outlives the 600t EndRiftAmbient re-fire cadence.
AMBIENT_TICKS = 660


def rand_size3(lo, hi):
    """Per-axis random start size (the house nf3(random, random, random) idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


# -----------------------------------------------------------------------------------
# 1. eclipse:end_arrival2_glyphs — Beat-1 rune ring (anchor = altar top + 40)
# -----------------------------------------------------------------------------------
def build_glyphs() -> FxBuilder:
    fx = FxBuilder("end_arrival2_glyphs")
    root = fx.empty("glyph_root")

    # The rune ring: glitch squares born on a r=12 circle, orbiting while the ring
    # slowly contracts (negative radial) — "sky rift glyphs gather over the altar".
    (fx.particle_emitter(
            "glyph_ring",
            duration=80, looping=False, start_lifetime=random_between(40, 64),
            start_speed=constant(0.0),
            start_size=rand_size3(0.5, 0.9),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="Local", max_particles=48)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(8), cycles=4, interval=14)])
        .with_shape(circle(radius=12.0, thickness=0.05))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.22, 0.38), constant(0)),
                radial=random_between(-0.14, -0.06)),
            size_over_lifetime=curve(0.2, 1.0, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.95), (0.8, 0.65), (1.0, 0.0)],
                [(0.0,) + MAGENTA, (0.5,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(SQUARE_4X4, hdr=(1.7, 1.3, 2.5)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-15.0, -4.0, -15.0), (15.0, 4.0, 15.0)))

    # Converging motes: fine HOT dust drifting from the ring toward the center —
    # the "gathering" read between the runes.
    (fx.particle_emitter(
            "gather_motes",
            duration=80, looping=False, start_lifetime=random_between(22, 38),
            start_speed=constant(0.0),
            start_size=rand_size3(0.08, 0.16),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(1.6))
        .with_shape(circle(radius=11.0, thickness=0.4))
        .with_curves(
            velocity_over_lifetime=dict(radial=random_between(-0.40, -0.22)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)],
                [(0.0,) + HOT, (1.0,) + VIOLET]))
        .with_material(texture_material(CIRCLE, hdr=(1.3, 1.0, 2.0)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                       length_scale=2.0, vertex_sorting="NONE")
        .with_cull_box((-13.0, -3.0, -13.0), (13.0, 3.0, 13.0)))
    return fx


# -----------------------------------------------------------------------------------
# 2. eclipse:end_arrival2_strand_trail — the helix comet sheath (anchor = altar top)
# -----------------------------------------------------------------------------------
def build_strand_trail() -> FxBuilder:
    fx = FxBuilder("end_arrival2_strand_trail")
    root = fx.empty("trail_root")

    # Braided streak traffic: born on the strands' helix radius, orbiting WITH the
    # debris spin (EndArrivalDebrisFx STRAND_SPIN ≈ 0.26 rad/t) while racing up the
    # column — long stretched billboards read as comet tails on the three streams.
    (fx.particle_emitter(
            "braid_streaks",
            duration=TRAIL_TICKS, looping=False,
            start_lifetime=random_between(110, 150),
            start_speed=constant(0.0),
            start_size=rand_size3(0.18, 0.38),
            simulation_space="Local", max_particles=260)
        .child_of(root)
        .with_emission(rate=constant(1.9))
        .with_shape(cylinder(radius=3.0, thickness=0.15))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.7, 2.3), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.22, 0.30), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 0.9), (0.85, 0.55), (1.0, 0.0)],
                [(0.0,) + HOT, (0.45,) + VIOLET, (1.0,) + MAGENTA]))
        .with_material(texture_material(CIRCLE, hdr=(1.6, 1.2, 2.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                       length_scale=3.4, vertex_sorting="NONE")
        .with_cull_box((-7.0, -2.0, -7.0), (7.0, TRAIL_MODEL_HEIGHT + 10.0, 7.0)))

    # Residue dust: slow embers the comet tails shed, sinking back down the column.
    (fx.particle_emitter(
            "trail_residue",
            duration=TRAIL_TICKS, looping=False,
            start_lifetime=random_between(40, 70),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            simulation_space="World", max_particles=160)
        .child_of(root)
        .with_emission(rate=constant(1.2))
        .with_shape(box(), scale=(7.0, TRAIL_MODEL_HEIGHT, 7.0),
                    position=(0.0, TRAIL_MODEL_HEIGHT / 2.0, 0.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-0.03, 0.03), random_between(-0.30, -0.12),
                           random_between(-0.03, 0.03))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.7), (1.0, 0.0)],
                [(0.0,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=(1.1, 0.8, 1.7)))
        .with_cull_box((-8.0, -30.0, -8.0), (8.0, TRAIL_MODEL_HEIGHT + 10.0, 8.0)))
    return fx


# -----------------------------------------------------------------------------------
# 3. eclipse:end_arrival2_island_ring — wave-complete shock ring (anchor = disc center)
# -----------------------------------------------------------------------------------
def build_island_ring() -> FxBuilder:
    fx = FxBuilder("end_arrival2_island_ring")
    root = fx.empty("ring_root")

    # THE ring: one flat HDR annulus expanding from the disc center out across the
    # completing wave (start size 15 -> x8 = 120 blocks across = authored radius 60).
    (fx.particle_emitter(
            "wave_ring",
            duration=50, looping=False, start_lifetime=constant(34),
            start_speed=constant(0), start_size=nf3(15.0), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.125, 8.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.55, 0.5), (1.0, 0.0)],
                [(0.0,) + HOT, (0.5,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(RING_SOFT, hdr=(2.0, 1.5, 3.0)))
        .with_renderer(render_mode="Horizontal")
        .with_cull_box((-70.0, -4.0, -70.0), (70.0, 4.0, 70.0)))

    # Rim sparks: one outward scatter of stretched sparks riding the ring's launch.
    (fx.particle_emitter(
            "rim_scatter",
            duration=50, looping=False, start_lifetime=random_between(14, 26),
            start_speed=constant(0.0),
            start_size=rand_size3(0.16, 0.34),
            simulation_space="Local", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(30)),
                               burst(time=10, count=constant(20))])
        .with_shape(circle(radius=8.0, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(radial=random_between(1.4, 2.4)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.7, 0.6), (1.0, 0.0)],
                [(0.0,) + HOT, (0.6,) + MAGENTA, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=(1.6, 1.2, 2.6)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                       length_scale=2.8, vertex_sorting="NONE")
        .with_cull_box((-70.0, -4.0, -70.0), (70.0, 4.0, 70.0)))
    return fx


# -----------------------------------------------------------------------------------
# 4. eclipse:end_arrival2_rift_ambient — the permanent rift residue (anchor = disc + 40)
# -----------------------------------------------------------------------------------
def build_rift_ambient() -> FxBuilder:
    fx = FxBuilder("end_arrival2_rift_ambient")
    root = fx.empty("ambient_root")

    # Faint dark shimmer vortex: the healed scar of the maw — alpha-blended smoke,
    # very low alpha, slow orbit. Deliberately SUBTLE (it plays forever).
    (fx.particle_emitter(
            "scar_shimmer",
            duration=AMBIENT_TICKS, looping=False,
            start_lifetime=random_between(90, 140),
            start_speed=constant(0.02),
            start_size=rand_size3(2.5, 5.0),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.3))
        .with_shape(circle(radius=10.0, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.06), constant(0)),
                radial=constant(-0.02)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.22), (0.75, 0.16), (1.0, 0.0)],
                [(0.0, 0.13, 0.08, 0.20), (1.0, 0.09, 0.05, 0.15)]))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-16.0, -8.0, -16.0), (16.0, 8.0, 16.0)))

    # Sparse violet motes drifting in the scar.
    (fx.particle_emitter(
            "scar_motes",
            duration=AMBIENT_TICKS, looping=False,
            start_lifetime=random_between(50, 90),
            start_speed=random_between(0.01, 0.04),
            start_size=rand_size3(0.08, 0.18),
            simulation_space="Local", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(0.25))
        .with_shape(sphere(radius=9.0, thickness=0.8))
        .with_curves(
            noise=dict(frequency=0.3, quality="Noise2D", position=nf3(0.03)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (1.0, 0.0)],
                [(0.0,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=(1.1, 0.8, 1.7)))
        .with_cull_box((-12.0, -10.0, -12.0), (12.0, 10.0, 12.0)))

    # Rare falling star sparks: one every few seconds slipping out of the scar.
    (fx.particle_emitter(
            "scar_starfall",
            duration=AMBIENT_TICKS, looping=False,
            start_lifetime=random_between(50, 80),
            start_speed=constant(0),
            start_size=rand_size3(0.12, 0.22),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=12)
        .child_of(root)
        .with_emission(rate=constant(0.08))
        .with_shape(circle(radius=7.0, thickness=0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-0.03, 0.03), random_between(-0.35, -0.18),
                           random_between(-0.03, 0.03))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.9), (0.8, 0.5), (1.0, 0.0)],
                [(0.0,) + HOT, (0.6,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(STAR_2X2, hdr=(1.4, 1.1, 2.2)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-10.0, -45.0, -10.0), (10.0, 8.0, 10.0)))
    return fx


BUILDERS = (build_glyphs, build_strand_trail, build_island_ring, build_rift_ambient)


def main() -> int:
    rc = 0
    for build in BUILDERS:
        fx = build()
        fx_path = FX_ASSETS_DIR / (fx.name + ".fx")
        raw_len, gz_len = fx.write(fx_path)          # round-trip-validates
        proj_len = fx.write_fxproj(fx_path.with_suffix(".fxproj"))
        errors = validate_file(fx_path)
        if errors:
            print(f"FAIL {fx_path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {fx_path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B, "
                  f"fxproj {proj_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
