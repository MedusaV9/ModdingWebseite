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

FX-WAVE-13 C5 PASS — what changed and WHY (census §7 line C5, §2 row 30):

  1. UNITS — the B6/C4 slip, and this file had the worst case in the credits/end corner.
     Photon reads `startSpeed` and `velocityOverLifetime.linear`/`orbital` per SECOND
     (`×0.05`/tick) and `radial` at `×0.01`/tick, so every authored number here was 20×
     (linear/orbital) or 100× (radial) short of the motion its own comment promises:

       braid_streaks  a comet sheath around a 260-BLOCK column climbed 9-17 blocks, i.e.
                      all ~250 live streaks piled into the bottom 6 % of the column and
                      the other 94 % of the "sheath" was empty sky. Now 143-270 blocks.
       braid_streaks  orbital 0.22-0.30 was authored against `EndArrivalDebrisFx`'s
                      STRAND_SPIN = 0.26 rad/TICK — in rad/second that is 5.2, so the
                      sheath counter-slipped its own strands by a factor of 20.
       gather_motes   "drifting toward the center" off an r=11 ring: 0.15 blocks.
       glyph_ring     "slowly contracting" ring: 0.09 blocks of contraction on r=12.
       trail_residue  "sinking back down the column" (cull lip at -30): 1.05 blocks.
       rim_scatter    an outward scatter riding a ring that opens to radius 60: 0.6 b.
       scar_starfall  "falling star sparks" with a -45 cull floor: 1.4 blocks.

     Every velocity below is now back-solved from the distance its own comment promises,
     `blocks = v × 0.05 × lifetimeTicks` (`radial` = `×0.01`), via `speed_for`/`radial_for`.
  2. `random_gradient` (via `varied()`) on every emitter that carries a crowd — this file
     had ZERO, so all 260 braid streaks were the same colour.
  3. Dark birth tints (V2.1 stacking law): ramps OPEN below their own fade target.
  4. HDR clamped to the wave-13 stacking ceiling 1.45, hue ratio preserved — the ring sat
     at 3.0 and the braid streaks at 2.8.

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


# --- wave-13 C5 levers -------------------------------------------------------------
# Local by design: `fxlib.py` is A0 ground this wave, so these are the same helpers B6
# landed in `ceremony_fx.py` and C4 in `worldevents_fx.py`, copied rather than shared so
# the generators can never block each other.
#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45").
HDR_CEILING = 1.45
#: Photon's authored-unit -> per-tick factors (jar: ShapeSetting/VelocityOverLifetime).
TICK_SECONDS = 0.05
RADIAL_TICK = 0.01
#: Birth tints (V2.1 stacking law): a ramp must OPEN below its OWN fade target, so the
#: near-black smoke ramps (which fade to ~0.05 luma) need a darker birth than the
#: additive SAC ones — one shared void birth would be a brightening, not a tint.
VOID_BIRTH = (0.08, 0.05, 0.14)
DEEP_BIRTH = (0.12, 0.07, 0.22)
SMOKE_BIRTH = (0.022, 0.012, 0.038)
#: Sibling tints for `varied()` — inside the SAC/GLI palette, so the roll reads as
#: variety rather than as a second colour.
VIOLET_ALT = (0.640, 0.470, 0.960)
HOT_ALT = (0.900, 0.870, 1.0)
MAGENTA_ALT = (0.900, 0.360, 0.800)
#: `EndArrivalDebrisFx.STRAND_SPIN` (rad/TICK) and the ±10 % lane jitter it rolls.
STRAND_SPIN_RAD_PER_TICK = 0.26


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette;
    each particle rolls its own memoized lerp, so no two read identical."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def speed_for(blocks, lifetime_ticks):
    """Authored linear/orbital speed carrying a particle `blocks` far over its life."""
    return round(blocks / (TICK_SECONDS * lifetime_ticks), 2)


def radial_for(blocks, lifetime_ticks):
    """Same, for `velocityOverLifetime.radial` — Photon applies that one at ×0.01/tick,
    so a radial number is always 5× the linear one for the same distance."""
    return round(blocks / (RADIAL_TICK * lifetime_ticks), 1)


def spin_for(radians, lifetime_ticks):
    """Authored orbital angular velocity (rad/SECOND) sweeping `radians` over a life."""
    return round(radians / (TICK_SECONDS * lifetime_ticks), 2)


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
            # A quarter to a half turn of orbit and 2.5-4.5 blocks of contraction over
            # the rune's 40-64t life: the ring visibly closes on the altar instead of
            # creeping the 9 cm the pre-wave-13 numbers bought (radial is ×0.01/tick).
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0),
                            random_between(spin_for(1.6, 64), spin_for(3.2, 40)),
                            constant(0)),
                radial=random_between(-radial_for(4.5, 64), -radial_for(2.5, 40))),
            size_over_lifetime=curve(0.2, 1.0, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.95), (0.8, 0.65), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.15,) + MAGENTA, (0.5,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.18,) + MAGENTA_ALT, (0.5,) + VIOLET_ALT,
                 (1.0,) + DEEP]))
        .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.7, 1.3, 2.5)))
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
            # Converge 2.8-5.0 blocks off the 6.6-11-block ring band over a 22-38t life
            # — a mote covers most of the way in and fades there (it used to travel
            # 15 cm and simply hang on the ring). Back-solved against the band's INNER
            # edge (6.6), not its nominal r=11: `radial` follows normalize(localPos) and
            # re-normalizes every tick, so a mote that crosses r=0 flips direction and
            # flies back OUT — the innermost-spawned mote sets the ceiling for all of them.
            velocity_over_lifetime=dict(
                radial=random_between(-radial_for(5.0, 38), -radial_for(2.8, 22))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.25,) + HOT, (1.0,) + VIOLET],
                [(0.0,) + DEEP_BIRTH, (0.3,) + HOT_ALT, (1.0,) + VIOLET_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.3, 1.0, 2.0)))
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
            # Climb 143-270 blocks over the streak's 110-150t life, i.e. the sheath now
            # populates the whole authored 260-block column (and stays inside its own
            # +270 cull lid) instead of piling into the bottom 17 blocks. The orbit is
            # locked to STRAND_SPIN with the same ±10 % lane jitter the debris rolls, in
            # rad/SECOND — the sheath co-rotates with the strands it sheathes.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(143.0, 110), speed_for(270.0, 150)),
                           constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0),
                            random_between(
                                round(STRAND_SPIN_RAD_PER_TICK * 0.9 / TICK_SECONDS, 2),
                                round(STRAND_SPIN_RAD_PER_TICK * 1.1 / TICK_SECONDS, 2)),
                            constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.08, 0.9), (0.85, 0.55), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.08,) + HOT, (0.45,) + VIOLET, (1.0,) + MAGENTA],
                [(0.0,) + VOID_BIRTH, (0.1,) + HOT_ALT, (0.45,) + VIOLET_ALT,
                 (1.0,) + MAGENTA_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.2, 2.8)))
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
            # Sink 8-25 blocks (the -30 cull lip is the budget) with ~1 block of lateral
            # wander over a 40-70t life — an ember that visibly falls out of the braid.
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-speed_for(1.0, 55), speed_for(1.0, 55)),
                           random_between(-speed_for(25.0, 70), -speed_for(8.0, 40)),
                           random_between(-speed_for(1.0, 55), speed_for(1.0, 55)))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.7), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.24,) + VIOLET_ALT, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.8, 1.7)))
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
            # Single quad — no stacking partner, so it keeps its plain gradient; only the
            # HDR comes down to the wave-13 ceiling.
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.55, 0.5), (1.0, 0.0)],
                [(0.0,) + HOT, (0.5,) + VIOLET, (1.0,) + DEEP]))
        .with_material(texture_material(RING_SOFT, hdr=hdr(2.0, 1.5, 3.0)))
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
            # Ride the ring: +17 to +49 blocks off the r=8 launch circle over a 14-26t
            # life, so a spark ends up between r=25 and r=57 while the ring itself opens
            # to r=60. Radial is ×0.01/tick, hence the big authored numbers — 190 radial
            # is 1.9 blocks/tick, which is the ring's own 1.5 blocks/tick crest speed.
            velocity_over_lifetime=dict(
                radial=random_between(radial_for(17.0, 14), radial_for(49.0, 26))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 1.0), (0.7, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.15,) + HOT, (0.6,) + MAGENTA, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.18,) + HOT_ALT, (0.6,) + MAGENTA_ALT,
                 (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.2, 2.6)))
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
            # ~0.5 blocks of outward breath over a 115t life — deliberately the slowest
            # thing in the file, but no longer 3 cm.
            start_speed=constant(speed_for(0.5, 115)),
            start_size=rand_size3(2.5, 5.0),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.3))
        .with_shape(circle(radius=10.0, thickness=0.5))
        .with_curves(
            # A third of a turn and 1.5 blocks of inward creep over the shimmer's life:
            # the scar turns slowly enough to read as a permanent residue, fast enough
            # that a standing player can see it is alive at all.
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(spin_for(2.1, 115)), constant(0)),
                radial=constant(-radial_for(1.5, 115))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.22), (0.75, 0.16), (1.0, 0.0)],
                [(0.0,) + SMOKE_BIRTH, (0.3, 0.13, 0.08, 0.20), (1.0, 0.09, 0.05, 0.15)],
                [(0.0,) + SMOKE_BIRTH, (0.3, 0.10, 0.06, 0.17), (1.0, 0.07, 0.04, 0.12)]))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-16.0, -8.0, -16.0), (16.0, 8.0, 16.0)))

    # Sparse violet motes drifting in the scar.
    (fx.particle_emitter(
            "scar_motes",
            duration=AMBIENT_TICKS, looping=False,
            start_lifetime=random_between(50, 90),
            # 0.6-1.4 blocks of drift over a 50-90t life.
            start_speed=random_between(speed_for(0.6, 50), speed_for(1.4, 90)),
            start_size=rand_size3(0.08, 0.18),
            simulation_space="Local", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(0.25))
        .with_shape(sphere(radius=9.0, thickness=0.8))
        .with_curves(
            noise=dict(frequency=0.3, quality="Noise2D", position=nf3(0.03)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.55), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.3,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + DEEP_BIRTH, (0.34,) + VIOLET_ALT, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.8, 1.7)))
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
            # Fall 18-40 blocks over a 50-80t life — the -45 cull floor is what the
            # emitter was always budgeted for; the old numbers dropped a "falling star"
            # by 1.4 blocks, so it read as a hovering speck.
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-speed_for(1.5, 65), speed_for(1.5, 65)),
                           random_between(-speed_for(40.0, 80), -speed_for(18.0, 50)),
                           random_between(-speed_for(1.5, 65), speed_for(1.5, 65)))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.9), (0.8, 0.5), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.15,) + HOT, (0.6,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.18,) + HOT_ALT, (0.6,) + VIOLET_ALT,
                 (1.0,) + DEEP]))
        .with_material(texture_material(STAR_2X2, hdr=hdr(1.4, 1.1, 2.2)))
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
