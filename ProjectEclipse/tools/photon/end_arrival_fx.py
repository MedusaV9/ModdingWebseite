#!/usr/bin/env python3
"""end_arrival_fx — F-077 "Der Altar ruft das End" Photon `.fx` assets.

The End-arrival cinematic (sequence/endarrival/EndArrivalSequence): when the End-disc
trigger fires, the altar summons a violet pillar into the sky, a giant End-rift tears
open under the disc band, and hundreds of end-stone block displays pour out of it and
assemble into the sky archipelago while the real chunks materialize underneath.

Rows live in the NEW registrar `veilfx/EndArrivalFxRows`; cue ids in
`sequence/endarrival/EndArrivalFxCues` (built via FxCues.cue(...) — FxCues.java itself
stays untouched per the parallel-agent file locks). Everything here is the Photon hero
layer; the photon-less baseline is the server's own vanilla particle + Quasar-fallback
composition in EndArrivalSequence (REVERSE_PORTAL suction, END_ROD columns, PORTAL
bursts) — REPLACE rows fall back to shipped Quasar emitters.

Palette: SAC violet family (SAC_HOT F6EFFF / SAC_VIOLET B98CFF / SAC_DEEP 7B4FD0 /
SAC_VOID 2E2347) with GLI_MAGENTA/GLI_CYAN void-spark accents — the End is a wound in
the day sky, dark-on-bright, so the maw body is alpha-blended near-black like
`day_rift_maw` (ferryman2_fx.py) and only the energy reads additive/HDR.

Assets (all ONE-SHOTS — no loops, so no windowed-loop controller is needed; long
durations lean on Photon's allowMulti=false dedup for the sequence's re-fire cadence):

  end_arrival_suction     Phase-1 omen (~90t): violet in-fall streaks collapsing onto
                          the altar from a 16-block shell + a swelling core glow.
  end_arrival_rings       Phase-2 charge (~60t): three flat energy rings climbing the
                          altar column, plus a glyph-dust sleeve.
  end_arrival_pillar      Phases 2-3 (620t): THE column — an HDR beam core 260 blocks
                          tall + climbing streak traffic + base flare. The client row
                          Y-scales the executor to the real altar->rift gap (payload a).
  end_arrival_maw         Phases 2-4 (560t): the giant End-rift. Scaled-up sibling of
                          day_rift_maw: near-black smoke vortex r=14, violet heartbeat
                          pulses, orbiting rim streaks, void-spark glitch squares,
                          sinking drip motes (the debris curtain seam).
  end_arrival_wisp        Phase-3 garnish (~60t): 2-3 curling Endergeist streaks
                          (purple_wisp) with noise-driven dance.
  end_arrival_puff        Phase-3 arrival stamp (~30t): small violet implosion where a
                          debris chunk snaps into the forming island silhouette.
  end_arrival_implosion   Phase-4 rift close (~70t): one big inhale of streaks, an HDR
                          white-violet flash, an expanding horizontal shock ring and a
                          glitch-shard scatter.
  end_arrival_glitter     Phase-4 (~140t): the pillar dissolves — a 240-block column of
                          falling star glitter fading out.

FX-WAVE-13 C5 PASS — what changed and WHY (census §7 line C5):

  1. UNITS. Photon reads `startSpeed` and `velocityOverLifetime.linear`/`orbital` per
     SECOND (`×0.05`/tick) and `radial` at `×0.01`/tick. This file was authored per TICK
     throughout — `climb_streaks` even says so out loud ("lifetime 130 x ~2 b/t ≈ the
     full climb"), and at 2 blocks/SECOND that climb was 13 blocks of a 260-block pillar.
     The same slip B6 found in `ceremony_fx.py` and C4 across `worldevents_fx.py`:

       climb_streaks   260-block column, climbed 9-18 blocks -> 143-270.
       indraw_streaks  in-fall onto the altar off an r=16 shell: 0.33 blocks -> 9.5-20.
       inhale          "racing INTO the mouth" off an r=17 shell in 16t: 0.4 -> 17.
       snap_in         collapse of an r=2.2 shell: 0.16 blocks -> 2.4.
       maw_drip        the debris seam curtain (-40 cull): 1.35 blocks -> 12-30.
       glitter_fall    a 240-block glitter column (-30 cull): 2.75 blocks -> 12-30.
       climb_rings     rings riding up the altar (+16 cull): 0.71 blocks -> 12-14.
       sleeve_dust     a "spiraling" sleeve: 0.68 blocks and 46 deg -> 6-13 and ~1.5 turns.

     Every number is back-solved from the distance its own comment promises,
     `blocks = v × 0.05 × lifetimeTicks` (`radial` = `×0.01`), via `speed_for`/`radial_for`.
     `rim_streaks` and `geist_curl` orbitals were CHECKED and left alone — at 57-180 deg
     over a life they already read as authored.
  2. `random_gradient` (via `varied()`) on every emitter carrying a crowd — this file had
     ZERO across 20 emitters, so 340 glitter stars were one colour.
  3. Dark birth tints (V2.1 stacking law): ramps OPEN below their own fade target.
  4. HDR clamped to the wave-13 stacking ceiling 1.45, hue ratio preserved (the implosion
     flash sat at 4.0).

Run:  python3 tools/photon/end_arrival_fx.py     # writes + validates all 8 assets
(write() round-trip-validates; every .fx gets its .fxproj sibling — binary-diff law.)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
BEAM_CORE = "eclipse:textures/particle/beam_core.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"
PURPLE_WISP = "eclipse:textures/particle/purple_wisp.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"

# --- palette (FX-STYLE-GUIDE §1 SAC family + GLI accents) --------------------------
HOT = (0.965, 0.937, 1.0)          # SAC_HOT F6EFFF
VIOLET = (0.725, 0.549, 1.0)       # SAC_VIOLET B98CFF
DEEP = (0.482, 0.310, 0.816)       # SAC_DEEP 7B4FD0
VOID = (0.180, 0.137, 0.278)       # SAC_VOID 2E2347
MAGENTA = (1.0, 0.310, 0.847)      # GLI_MAGENTA FF4FD8
CYAN = (0.310, 0.910, 1.0)         # GLI_CYAN 4FE8FF

# --- sync contracts (keep in step with EndArrivalSequence / EndArrivalFxRows) ------
# The pillar asset is authored 260 blocks tall; the client row scales the executor's Y
# by (payload a / PILLAR_MODEL_HEIGHT) so it exactly bridges altar top -> rift mouth.
PILLAR_MODEL_HEIGHT = 260.0
# One-shot lifespans mirror the sequence beats (20 t/s): pillar 200->820, maw 240->800.
PILLAR_TICKS = 620
MAW_TICKS = 560


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
CYAN_ALT = (0.380, 0.820, 0.960)
DEEP_ALT = (0.400, 0.260, 0.720)


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
# 1. eclipse:end_arrival_suction — Phase-1 omen in-fall (anchor = altar top)
# -----------------------------------------------------------------------------------
def build_suction() -> FxBuilder:
    fx = FxBuilder("end_arrival_suction")
    root = fx.empty("suction_root")

    # In-fall streaks: born on a wide shell, dragged INTO the altar (negative radial).
    (fx.particle_emitter(
            "indraw_streaks",
            duration=90, looping=False, start_lifetime=random_between(26, 44),
            start_speed=constant(0.0),
            start_size=rand_size3(0.10, 0.24),
            simulation_space="Local", max_particles=180)
        .child_of(root)
        .with_emission(rate=constant(3.2))
        .with_shape(sphere(radius=16.0, thickness=0.12))
        .with_curves(
            # Draw 7.3-12.9 blocks in off the 14.1-16-block shell over a 26-44t life, so
            # a streak dies on or just short of the altar — the in-fall read (it used to
            # travel 33 cm and simply hang out on the shell; radial is ×0.01/tick). The
            # 12.9 is the shell's INNER edge minus a 1.2-block margin: `radial` follows
            # a localPos that re-normalizes every tick, so crossing r=0 turns the in-fall
            # into an out-spray.
            velocity_over_lifetime=dict(
                radial=random_between(-radial_for(12.9, 44), -radial_for(7.3, 26)),
                speed_modifier=constant(1.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2,) + VIOLET, (0.7,) + DEEP, (1.0,) + HOT],
                [(0.0,) + VOID_BIRTH, (0.24,) + VIOLET_ALT, (0.7,) + DEEP_ALT,
                 (1.0,) + HOT_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 0.9, 1.9)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=2.4, vertex_sorting="NONE")
        .with_cull_box((-18.0, -18.0, -18.0), (18.0, 18.0, 18.0)))

    # Swelling core glow at the altar — where all the streaks arrive.
    (fx.particle_emitter(
            "core_swell",
            duration=90, looping=False, start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(1.4), max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=8, count=constant(1), cycles=5, interval=18)])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_OVERSHOOT_SETTLE]),
            # Five swells overlap on one spot — a birth tint keeps the stack from
            # converging on a white ball.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.35, 0.8), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.35,) + HOT, (1.0,) + DEEP]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.2, 2.6)))
        .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0)))
    return fx


# -----------------------------------------------------------------------------------
# 2. eclipse:end_arrival_rings — Phase-2 climbing energy rings (anchor = altar base)
# -----------------------------------------------------------------------------------
def build_rings() -> FxBuilder:
    fx = FxBuilder("end_arrival_rings")
    root = fx.empty("rings_root")

    # Three flat rings, staggered, riding up the altar column while expanding.
    (fx.particle_emitter(
            "climb_rings",
            duration=60, looping=False, start_lifetime=constant(34),
            start_speed=constant(0), start_size=nf3(2.4), max_particles=6)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(1), cycles=3, interval=12)])
        .with_shape(dot())
        .with_curves(
            # Climb 12-14 blocks over the ring's 34t life — the +16 cull lid is the
            # altar column the rings are supposed to ride up (they managed 71 cm).
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(12.0, 34), speed_for(14.0, 34)),
                           constant(0))),
            size_over_lifetime=curve(0.4, 1.6, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.9), (0.85, 0.5), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.15,) + HOT, (0.5,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + DEEP_BIRTH, (0.18,) + HOT_ALT, (0.5,) + VIOLET_ALT,
                 (1.0,) + DEEP_ALT]))
        .with_material(texture_material(RING_SOFT, hdr=hdr(1.5, 1.1, 2.4)))
        .with_renderer(render_mode="Horizontal")
        .with_cull_box((-5.0, -1.0, -5.0), (5.0, 16.0, 5.0)))

    # Glyph-dust sleeve: fine motes spiraling up around the column.
    (fx.particle_emitter(
            "sleeve_dust",
            duration=60, looping=False, start_lifetime=random_between(24, 40),
            # ~0.6 blocks of outward creep off the r=1.6 sleeve.
            start_speed=constant(speed_for(0.6, 32)),
            start_size=rand_size3(0.06, 0.14),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(1.8))
        .with_shape(cylinder(radius=1.6, thickness=0.2))
        .with_curves(
            # A real spiral: 6-13 blocks of climb (+14 cull) and ~1.5 turns of orbit
            # over a 24-40t life. The old numbers bought 68 cm and 46 degrees.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(6.0, 24), speed_for(13.0, 40)),
                           constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(spin_for(9.4, 32)), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.9), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.25,) + VIOLET, (1.0,) + MAGENTA],
                [(0.0,) + VOID_BIRTH, (0.3,) + VIOLET_ALT, (1.0,) + MAGENTA_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.8, 1.8)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-4.0, -1.0, -4.0), (4.0, 14.0, 4.0)))
    return fx


# -----------------------------------------------------------------------------------
# 3. eclipse:end_arrival_pillar — the altar->rift column (anchor = altar top)
# -----------------------------------------------------------------------------------
def build_pillar() -> FxBuilder:
    fx = FxBuilder("end_arrival_pillar")
    root = fx.empty("pillar_root")

    # The core: one vertical HDR beam, 260 blocks, breathing width. The row Y-scales
    # the executor onto the real gap; keep everything else near the axis so the
    # stretch stays invisible.
    (fx.beam_emitter(
            "pillar_beam",
            end=(0.0, PILLAR_MODEL_HEIGHT, 0.0),
            width=curve(3.2, 5.4, [SEG_EASE_OUT_CREST, SEG_DECAY_TAIL]),
            duration=PILLAR_TICKS, looping=False, raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.0), (0.06, 0.9), (0.9, 0.75), (1.0, 0.0)],
                [(0.0,) + HOT, (0.4,) + VIOLET, (1.0,) + DEEP]))
        .child_of(root)
        .with_material(texture_material(BEAM_CORE, hdr=hdr(1.8, 1.3, 3.0),
                                        blend=BLEND_ADDITIVE, cull=False))
        .with_lights(sky=15, block=15))

    # Climbing streak traffic: fast violet sparks racing up inside the column. The
    # "~2 b/t" the old comment claimed was authored into a blocks/SECOND field, so the
    # traffic climbed 13 blocks of the 260 and the rest of the pillar was an empty beam.
    (fx.particle_emitter(
            "climb_streaks",
            duration=PILLAR_TICKS, looping=False,
            start_lifetime=random_between(110, 150),
            start_speed=constant(0.0),
            start_size=rand_size3(0.14, 0.30),
            simulation_space="Local", max_particles=220)
        .child_of(root)
        .with_emission(rate=constant(1.5))
        .with_shape(cylinder(radius=2.2, thickness=0.4))
        .with_curves(
            # 143-270 blocks of climb over a 110-150t life (the +270 cull lid is the
            # authored column), with ~2 turns of helix on the way up.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(143.0, 110), speed_for(270.0, 150)),
                           constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(spin_for(12.6, 130)), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.95), (0.85, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.1,) + HOT, (0.5,) + VIOLET, (1.0,) + MAGENTA],
                [(0.0,) + VOID_BIRTH, (0.12,) + HOT_ALT, (0.5,) + VIOLET_ALT,
                 (1.0,) + MAGENTA_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.5, 1.1, 2.6)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                       length_scale=2.6, vertex_sorting="NONE")
        .with_cull_box((-6.0, -2.0, -6.0), (6.0, PILLAR_MODEL_HEIGHT + 10.0, 6.0)))

    # Base flare: slow bright churn where the pillar leaves the altar.
    (fx.particle_emitter(
            "base_flare",
            duration=PILLAR_TICKS, looping=False,
            start_lifetime=random_between(30, 50),
            # 1-2.5 blocks of outward churn off the r=2.6 collar.
            start_speed=random_between(speed_for(1.0, 30), speed_for(2.5, 50)),
            start_size=rand_size3(0.5, 1.1),
            simulation_space="Local", max_particles=70)
        .child_of(root)
        .with_emission(rate=constant(0.9))
        .with_shape(circle(radius=2.6, thickness=0.6))
        .with_curves(
            # Lift 1.5-4 blocks over a 30-50t life — inside the +6 cull, so the flare
            # stays a collar at the altar instead of the 13 cm smear it was.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(1.5, 30), speed_for(4.0, 50)),
                           constant(0))),
            size_over_lifetime=curve(0.5, 1.0, [SEG_SMOOTH_DOWN]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.7), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.24,) + VIOLET_ALT, (1.0,) + DEEP_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 0.9, 2.0)))
        .with_cull_box((-5.0, -2.0, -5.0), (5.0, 6.0, 5.0)))
    return fx


# -----------------------------------------------------------------------------------
# 4. eclipse:end_arrival_maw — the giant End-rift (anchor = rift mouth, high sky)
# -----------------------------------------------------------------------------------
def build_maw() -> FxBuilder:
    fx = FxBuilder("end_arrival_maw")
    root = fx.empty("maw_root")

    # Near-black smoke vortex — the wound. Alpha-blended so it DARKENS the day sky
    # (the day_rift_maw read, tripled in size: r=14 vs 4.5).
    (fx.particle_emitter(
            "maw_smoke",
            duration=MAW_TICKS, looping=False, start_lifetime=random_between(70, 110),
            # ~0.8 blocks of outward breath — the vortex body must stay a wound, not
            # spread, so this is deliberately the slowest speed in the maw.
            start_speed=constant(speed_for(0.8, 90)),
            start_size=rand_size3(4.0, 8.0),
            simulation_space="Local", max_particles=150)
        .child_of(root)
        .with_emission(rate=constant(1.6))
        .with_shape(circle(radius=14.0, thickness=0.5))
        .with_curves(
            # A vortex has to turn: ~1.2 revolutions and 2.5 blocks of inward creep over
            # the smoke's 70-110t life (it managed 52 degrees and 5 cm before).
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(spin_for(7.54, 90)), constant(0)),
                radial=constant(-radial_for(2.5, 90))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.6), (0.75, 0.45), (1.0, 0.0)],
                [(0.0,) + SMOKE_BIRTH, (0.25, 0.13, 0.08, 0.20), (1.0, 0.07, 0.04, 0.12)],
                [(0.0,) + SMOKE_BIRTH, (0.25, 0.10, 0.06, 0.17), (1.0, 0.05, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-30.0, -22.0, -30.0), (30.0, 16.0, 30.0)))

    # Violet heartbeat pulses — the "lila-schwarzes Wabern" energy read.
    (fx.particle_emitter(
            "maw_pulse",
            duration=MAW_TICKS, looping=False, start_lifetime=constant(38),
            start_speed=constant(0), start_size=nf3(9.0), max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=10, count=constant(1), cycles=13, interval=42)])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(
                0.3, 1.0, [(0.0, 0.3, 0.3, 1.0, 0.7, 0.9, 1.0, 0.35)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.75), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.3,) + VIOLET, (1.0, 0.35, 0.2, 0.55)],
                [(0.0,) + VOID_BIRTH, (0.3,) + VIOLET_ALT, (1.0, 0.28, 0.16, 0.48)]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 0.7, 1.8)))
        .with_cull_box((-16.0, -12.0, -16.0), (16.0, 12.0, 16.0)))

    # Rim streaks: bright violet arcs orbiting the mouth — sells the giant diameter.
    (fx.particle_emitter(
            "rim_streaks",
            duration=MAW_TICKS, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0.0),
            start_size=rand_size3(0.25, 0.55),
            simulation_space="Local", max_particles=140)
        .child_of(root)
        .with_emission(rate=constant(1.8))
        .with_shape(circle(radius=13.5, thickness=0.08))
        .with_curves(
            # UNITS CHECKED, LEFT ALONE: 0.5-0.9 rad/SECOND is 57-180 deg over a 40-70t
            # life, i.e. 13-42 blocks of arc on the r=13.5 rim — exactly the "sells the
            # giant diameter" read. Read as rad/tick these would be 3-10 full turns.
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.5, 0.9), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.95), (0.85, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.15,) + HOT, (0.5,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.18,) + HOT_ALT, (0.5,) + VIOLET_ALT,
                 (1.0,) + DEEP_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.2, 2.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                       length_scale=3.0, vertex_sorting="NONE")
        .with_cull_box((-18.0, -6.0, -18.0), (18.0, 6.0, 18.0)))

    # Void sparks: glitch squares popping around the rim (magenta/cyan accents).
    (fx.particle_emitter(
            "void_sparks",
            duration=MAW_TICKS, looping=False, start_lifetime=random_between(10, 22),
            # 1-2.5 blocks of pop off the r=13 rim over a 10-22t life.
            start_speed=random_between(speed_for(1.0, 10), speed_for(2.5, 22)),
            start_size=rand_size3(0.15, 0.4),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="Local", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(1.4))
        .with_shape(circle(radius=13.0, thickness=0.25))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.1,) + MAGENTA, (0.5,) + CYAN, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.12,) + MAGENTA_ALT, (0.5,) + CYAN_ALT,
                 (1.0,) + DEEP_ALT]))
        .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.8, 1.4, 2.6)))
        .with_cull_box((-16.0, -6.0, -16.0), (16.0, 6.0, 16.0)))

    # Drip motes: sinking violet droplets — the seam the block-display debris falls
    # through (day_rift_maw's curtain, widened).
    (fx.particle_emitter(
            "maw_drip",
            duration=MAW_TICKS, looping=False, start_lifetime=random_between(50, 90),
            start_speed=constant(0),
            start_size=rand_size3(0.15, 0.35),
            simulation_space="World", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(1.4))
        .with_shape(circle(radius=11.0, thickness=1.0))
        .with_curves(
            # Fall 12-30 blocks over a 50-90t life — the -40 cull floor is the curtain
            # depth this seam was always budgeted for (it used to drip 1.35 blocks).
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(-speed_for(30.0, 90), -speed_for(12.0, 50)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.9), (0.85, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2, 0.816, 0.702, 1.0), (1.0, 0.4, 0.25, 0.65)],
                [(0.0,) + VOID_BIRTH, (0.24, 0.72, 0.62, 0.96), (1.0, 0.33, 0.2, 0.58)]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.8, 1.7)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                       length_scale=1.8, vertex_sorting="NONE")
        .with_cull_box((-16.0, -40.0, -16.0), (16.0, 8.0, 16.0)))
    return fx


# -----------------------------------------------------------------------------------
# 5. eclipse:end_arrival_wisp — Endergeist streak dance (anchor = midair spot)
# -----------------------------------------------------------------------------------
def build_wisp() -> FxBuilder:
    fx = FxBuilder("end_arrival_wisp")

    (fx.particle_emitter(
            "geist_curl",
            duration=60, looping=False, start_lifetime=random_between(30, 50),
            # 1.35-2.75 blocks of drift inside the ±4 cull the wisp lives in.
            start_speed=random_between(speed_for(1.5, 30), speed_for(2.5, 50)),
            start_size=rand_size3(0.35, 0.7),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="Local", max_particles=24)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=random_between(2, 3), cycles=4,
                                     interval=12)])
        .with_shape(sphere(radius=1.2, thickness=0.6))
        .with_curves(
            noise=dict(frequency=0.6, quality="Noise3D",
                       position=nf3(constant(0.16), constant(0.10), constant(0.16))),
            # UNITS CHECKED, LEFT ALONE: 0.6-1.1 rad/SECOND is 52-158 deg of curl over a
            # 30-50t life, which is the "curling streak" read the comment asks for.
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(0.6, 1.1), constant(0))),
            size_over_lifetime=curve(0.3, 1.0, [SEG_OVERSHOOT_SETTLE]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.5), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2,) + VIOLET, (0.6,) + MAGENTA, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.24,) + VIOLET_ALT, (0.6,) + MAGENTA_ALT,
                 (1.0,) + DEEP_ALT]))
        .with_material(texture_material(PURPLE_WISP, hdr=hdr(1.3, 0.9, 2.0)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))

    # A pinch of trailing dust so the streaks leave residue.
    (fx.particle_emitter(
            "geist_dust",
            duration=60, looping=False, start_lifetime=random_between(16, 28),
            # 0.5-1 block of residue drift inside the ±3 cull.
            start_speed=random_between(speed_for(0.5, 16), speed_for(1.0, 28)),
            start_size=rand_size3(0.06, 0.12),
            simulation_space="Local", max_particles=40)
        .with_emission(rate=constant(0.8))
        .with_shape(sphere(radius=1.4, thickness=1.0))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.3,) + HOT, (1.0,) + VIOLET],
                [(0.0,) + DEEP_BIRTH, (0.34,) + HOT_ALT, (1.0,) + VIOLET_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 0.7, 1.6)))
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))
    return fx


# -----------------------------------------------------------------------------------
# 6. eclipse:end_arrival_puff — debris arrival implosion stamp (anchor = arrival spot)
# -----------------------------------------------------------------------------------
def build_puff() -> FxBuilder:
    fx = FxBuilder("end_arrival_puff")

    # Quick inward snap: streaks born on a small shell collapsing to the point.
    (fx.particle_emitter(
            "snap_in",
            duration=30, looping=False, start_lifetime=constant(10),
            start_speed=constant(0.0),
            start_size=rand_size3(0.08, 0.18),
            simulation_space="Local", max_particles=14)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
        .with_shape(sphere(radius=2.2, thickness=0.0))
        .with_curves(
            # Collapse the r=2.2 shell onto the point inside the 10t life — the "snap"
            # only reads if the streaks actually arrive (they moved 16 cm). 2.1, not
            # 2.4: overshooting r=0 makes `radial` flip along the re-normalized localPos
            # and the streaks spray back out of the point they just snapped into.
            velocity_over_lifetime=dict(radial=constant(-radial_for(2.1, 10))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)],
                [(0.0,) + DEEP_BIRTH, (0.2,) + VIOLET, (1.0,) + HOT],
                [(0.0,) + DEEP_BIRTH, (0.24,) + VIOLET_ALT, (1.0,) + HOT_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 1.0, 2.2)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                       length_scale=2.2, vertex_sorting="NONE"))

    # The pop at arrival — one soft flash as the chunk "snaps" into the island.
    (fx.particle_emitter(
            "arrive_pop",
            duration=30, looping=False, start_delay=constant(8),
            start_lifetime=constant(9), start_speed=constant(0),
            start_size=nf3(1.1), max_particles=2)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.4, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0,) + HOT, (1.0,) + VIOLET]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.8, 1.4, 2.8))))
    return fx


# -----------------------------------------------------------------------------------
# 7. eclipse:end_arrival_implosion — Phase-4 rift close (anchor = rift mouth)
# -----------------------------------------------------------------------------------
def build_implosion() -> FxBuilder:
    fx = FxBuilder("end_arrival_implosion")
    root = fx.empty("implode_root")

    # The inhale: long streaks from a wide shell racing INTO the mouth (18t).
    (fx.particle_emitter(
            "inhale",
            duration=70, looping=False, start_lifetime=constant(16),
            start_speed=constant(0.0),
            start_size=rand_size3(0.2, 0.45),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(40)),
                               burst(time=6, count=constant(40))])
        .with_shape(sphere(radius=17.0, thickness=0.1))
        .with_curves(
            # Cross 14.1 of the shell's 15.3-17 blocks inside the 16t life, so the
            # inhale arrives on the mouth exactly as `close_flash` fires at +18t (it
            # used to move 0.4 blocks, leaving the flash to go off inside a shell that
            # had not moved). The 14.1 is the INNER shell edge minus a 1.2-block margin:
            # `radial` re-normalizes localPos every tick, so a streak that crosses r=0
            # flips direction and flies back out — an exhale in the middle of an inhale.
            velocity_over_lifetime=dict(radial=constant(-radial_for(14.1, 16))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.2,) + DEEP, (0.6,) + VIOLET, (1.0,) + HOT],
                [(0.0,) + VOID_BIRTH, (0.24,) + DEEP_ALT, (0.6,) + VIOLET_ALT,
                 (1.0,) + HOT_ALT]))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.5, 1.1, 2.4)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=3.2, vertex_sorting="NONE")
        .with_cull_box((-20.0, -20.0, -20.0), (20.0, 20.0, 20.0)))

    # The flash: one huge HDR white-violet bloom right after the inhale converges.
    (fx.particle_emitter(
            "close_flash",
            duration=70, looping=False, start_delay=constant(18),
            start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(10.0), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.35, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)],
                [(0.0,) + HOT, (1.0,) + VIOLET]))
        .with_material(texture_material(CIRCLE, hdr=hdr(3.0, 2.4, 4.0))))

    # The shock ring: one flat annulus expanding across the sky plane.
    (fx.particle_emitter(
            "shock_ring",
            duration=70, looping=False, start_delay=constant(20),
            start_lifetime=constant(26), start_speed=constant(0),
            start_size=nf3(6.0), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.2, 8.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.6, 0.45), (1.0, 0.0)],
                [(0.0,) + HOT, (1.0,) + VIOLET]))
        .with_material(texture_material(RING_SOFT, hdr=hdr(1.8, 1.4, 2.8)))
        .with_renderer(render_mode="Horizontal"))

    # Glitch-shard scatter: the rift's last void sparks thrown outward.
    (fx.particle_emitter(
            "shard_scatter",
            duration=70, looping=False, start_delay=constant(18),
            start_lifetime=random_between(14, 26),
            # Throw 6-16 blocks over a 14-26t life, so the rift's last sparks actually
            # scatter away from the closing mouth instead of nudging 2 blocks.
            start_speed=random_between(speed_for(6.0, 14), speed_for(16.0, 26)),
            start_size=rand_size3(0.14, 0.32),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="Local", max_particles=50)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(36))])
        .with_shape(sphere(radius=1.5, thickness=0.0))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0,) + CYAN, (0.5,) + MAGENTA, (1.0,) + DEEP],
                [(0.0,) + CYAN_ALT, (0.5,) + MAGENTA_ALT, (1.0,) + DEEP_ALT]))
        .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.8, 1.4, 2.6))))
    return fx


# -----------------------------------------------------------------------------------
# 8. eclipse:end_arrival_glitter — the pillar dissolves (anchor = altar top)
# -----------------------------------------------------------------------------------
def build_glitter() -> FxBuilder:
    fx = FxBuilder("end_arrival_glitter")

    # Falling star glitter born along the whole (former) pillar column.
    (fx.particle_emitter(
            "glitter_fall",
            duration=140, looping=False, start_lifetime=random_between(60, 110),
            start_speed=constant(0),
            start_size=rand_size3(0.12, 0.28),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=340)
        .with_emission(rate=constant(3.4))
        .with_shape(box(), scale=(5.0, 240.0, 5.0), position=(0.0, 120.0, 0.0))
        .with_curves(
            # Fall 12-30 blocks with ~1 block of lateral wander over a 60-110t life —
            # the -30 cull floor is the budget. The old numbers dropped a "falling star"
            # by 2.75 blocks inside a 240-block column, so the glitter just hung there.
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-speed_for(1.0, 85), speed_for(1.0, 85)),
                           random_between(-speed_for(30.0, 110), -speed_for(12.0, 60)),
                           random_between(-speed_for(1.0, 85), speed_for(1.0, 85)))),
            noise=dict(frequency=0.4, quality="Noise2D", position=nf3(0.04)),
            uv_animation=dict(
                tiles=(2, 2), animation="WholeSheet",
                frame_over_time=random_curve(
                    0.0, 1.0,
                    [(0.0, 0.05, 0.25, 0.9, 0.45, 0.1, 0.65, 0.7),
                     (0.65, 0.7, 0.75, 0.0, 0.9, 0.95, 1.0, 0.25)],
                    [(0.0, 0.6, 0.2, 0.05, 0.4, 1.0, 0.55, 0.15),
                     (0.55, 0.15, 0.7, 0.85, 0.85, 0.05, 1.0, 0.5)],
                    "lifetime"),
                start_frame=random_between(0.0, 3.0), cycle=3.0),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0,) + VOID_BIRTH, (0.12,) + HOT, (0.5,) + VIOLET, (1.0,) + DEEP],
                [(0.0,) + VOID_BIRTH, (0.15,) + HOT_ALT, (0.5,) + VIOLET_ALT,
                 (1.0,) + DEEP_ALT]))
        .with_material(texture_material(STAR_2X2, hdr=hdr(1.5, 1.2, 2.4)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-6.0, -30.0, -6.0), (6.0, 250.0, 6.0)))
    return fx


BUILDERS = (
    build_suction, build_rings, build_pillar, build_maw,
    build_wisp, build_puff, build_implosion, build_glitter,
)


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
