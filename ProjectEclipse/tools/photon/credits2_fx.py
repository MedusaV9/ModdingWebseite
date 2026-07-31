#!/usr/bin/env python3
"""CREDITS2 (F-056/F-058, polished by F-068) — authors the credits finale-rework Photon
assets with fxlib:

  eclipse:credits_collapse   F-058 island-shatter collapse veil over the breaking
                             sanctum island: a sluggish dark dust updraft, sparse
                             violet ember motes rising with the debris, one soft
                             expanding shock ring at the break beat — plus the F-068
                             polish layers: delayed trailing dust chasing the climbing
                             debris, two aftershock rings baked on the SAME act ticks
                             CreditsShatterAct kicks its fragments (AFTERSHOCK_AT =
                             150/300), and the altar-core flash + spark burst baked on
                             CORE_BREAK_TICK = 270 (~460t one-shot, fired once by
                             CreditsSequence at the island center)
  eclipse:black_hole_maw     F-056 the black-hole maw: two counter-rotating accretion
                             swirls (fast inner / lazy outer), infalling particle
                             streams pulled out of a wide shell, a thin hot
                             photon-ring rim glow — plus the F-068 polish layers:
                             stretched-billboard EMBER TRAILS dragging around the disc
                             rim and fast stretched STAR STREAKS pulled in from a wide
                             shell (the Photon-space cousins of the post shader's
                             Doppler ring + streak layers) (~340t one-shot, re-fired by
                             CreditsBlackHoleAct on a 300t cadence — the kneel-corona
                             sustain law keeps the seam gapless)

Authored scale: the maw is built around a ~26-block accretion radius (the act's
BLACK-HOLE visual radius); the collapse veil around the island's ~16-block ellipse.

Java-side tick contract (F-068): the baked burst times below MUST stay in lockstep with
CreditsShatterAct.AFTERSHOCK_AT ({150, 300}) and CreditsShatterAct.CORE_BREAK_TICK (270)
— the server fires the matching shake/flash beats on those exact act ticks.

FX-WAVE-13 C5 PASS — what changed and WHY (census §7 line C5, §2 rows credits/maw):

  1. UNITS. Photon (jar `VelocityOverLifetimeSetting.getVelocity`) applies `linear` and
     `orbital` at `×0.05`/tick — i.e. authored in blocks (rad) per SECOND — but `radial`
     at `×0.01`/tick. Every motion number in this file was authored as if it were
     blocks/TICK, which is the systematic slip B6 found in `ceremony_fx.py` and C4 across
     `worldevents_fx.py`. The headline case is `maw_infall`: it is documented as "motes
     pulled from a wide shell straight into the center", it is born on a 32-block shell,
     and at `radial -0.5` over a 50–90t life it travelled 0.25–0.45 blocks. The infalling
     streams of the black hole moved 1 % of the way in — a static shell of dots. Second
     worst: `collapse_trail_dust` is the curtain "chasing the debris", its own cull box is
     sized to +52 for it, and it climbed 1.1–2.9 blocks. Every velocity below is now
     back-solved from the distance its own comment (or cull box) promises:
     `blocks = v × 0.05 × lifeTicks` for linear, `× 0.01` for radial.
  2. STRETCHED BILLBOARDS were the collateral damage of (1). `TileParticle` draws them at
     `stretch = lengthScale + |velocity| × velocityScale` with `|velocity|` in blocks per
     TICK, so `maw_star_streaks` — the "hard pull" layer — got 0.01 b/t out of its radial
     and rendered as a slow orbital smudge with no infall at all. The fixed radial gives
     it 0.74 b/t, and its drawn length (0.75–1.65 blocks) now covers its own per-tick
     travel, so the streak reads continuous instead of stroboscopic.
  3. `random_gradient` (via `varied()`) on every emitter carrying a real population —
     this file had ZERO, so all 160 infall motes were the same colour.
  4. Dark birth tints (V2.1 stacking law): ramps OPEN below their own fade target, so an
     additive shell born inside half a block stops converging on a white ball.
  5. HDR clamped to the wave-13 stacking ceiling 1.45, hue ratio preserved — the core
     flash sat at 2.2, the rim glow and the inner swirl at 1.8–2.0.

Usage:  python3 tools/photon/credits2_fx.py            # write + validate both
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, burst, circle, constant, curve, cylinder,
    dot, gradient, nf3, random_between, random_gradient, sphere, texture_material,
    validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Finale palette (the ferryman2 law): near-black violet body, mid, hot white-violet.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
# Sibling tints for `varied()` — inside the same palette, so the roll reads as variety
# rather than as a second colour.
VIOLET_MID_ALT = (0.52, 0.44, 0.86)
VIOLET_HOT_ALT = (0.90, 0.76, 0.98)
#: Birth tints (V2.1 stacking law): a ramp must OPEN below its OWN fade target, so the
#: near-black dust ramps (which fade to ~0.04–0.05 luma) need a darker birth than the
#: additive violet ones — one shared birth tint would be a brightening, not a tint.
VIOLET_BIRTH = (0.12, 0.06, 0.20)
DUST_BIRTH = (0.022, 0.012, 0.038)

# ---------------------------------------------------------------------------
# WAVE-13 C5 levers. Local by design: `fxlib.py` is A0 ground this wave, so this is the
# same helper set B6 landed in `ceremony_fx.py` and C4 in `worldevents_fx.py`, copied
# rather than shared so the generators can never block each other.
# ---------------------------------------------------------------------------
#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45").
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
    """`random_gradient` — the authored ramp plus a sibling inside the same palette;
    each particle rolls its own memoized lerp, so no two read identical."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def speed_for(blocks, lifetime_ticks):
    """Authored `startSpeed`/`linear` carrying a particle `blocks` far over its life."""
    return round(blocks / (TICK_SECONDS * lifetime_ticks), 2)


def radial_for(blocks, lifetime_ticks):
    """Same, for `velocityOverLifetime.radial` — Photon applies that one at ×0.01/tick,
    so a radial number is always 5× the linear one for the same distance."""
    return round(blocks / (RADIAL_TICK * lifetime_ticks), 1)


def spin_for(radians, lifetime_ticks):
    """Authored orbital angular velocity (rad/SECOND) sweeping `radians` over a life."""
    return round(radians / (TICK_SECONDS * lifetime_ticks), 2)


# ---------------------------------------------------------------------------
# 1. eclipse:credits_collapse — F-058 (dark, slow — the island exhales as it breaks)
# ---------------------------------------------------------------------------
def build_credits_collapse() -> FxBuilder:
    fx = FxBuilder("credits_collapse")
    root = fx.empty("collapse_root")

    # Dust updraft: a wide, slow column of near-black dust rising off the whole island
    # footprint — the debris displays climb through this curtain.
    (fx.particle_emitter(
            "collapse_dust",
            duration=440, looping=False, start_lifetime=random_between(80, 130),
            # ~0.8 blocks of outward creep off the 15-block footprint ring.
            start_speed=constant(speed_for(0.8, 105)),
            start_size=nf3(random_between(2.0, 4.0), random_between(2.0, 4.0),
                           random_between(2.0, 4.0)),
            simulation_space="Local", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(0.9))
        .with_shape(cylinder(radius=15.0, thickness=0.8))
        .with_curves(
            # Climb 5.0-9.0 blocks over the 80-130t life, i.e. a curtain the rising
            # fragment field actually passes through (blocks/SECOND: the old 0.14 lifted
            # it 0.6-0.9 blocks, so it hugged the deck). Stays under the +30 cull lid.
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 0.3-0.5 rad (18-29 deg) of lazy swirl over the same life.
                orbital=nf3(constant(0), constant(spin_for(0.40, 105)), constant(0)),
                linear=nf3(constant(0),
                           random_between(speed_for(5.0, 80), speed_for(9.0, 130)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.5), (0.75, 0.35), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.25, 0.14, 0.08, 0.2), (1.0, 0.07, 0.04, 0.12)],
                [(0.0, *DUST_BIRTH), (0.25, 0.11, 0.07, 0.17), (1.0, 0.05, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-24.0, -6.0, -24.0), (24.0, 30.0, 24.0)))

    # Ember motes: sparse violet sparks drifting up between the fragments.
    (fx.particle_emitter(
            "collapse_motes",
            duration=440, looping=False, start_lifetime=random_between(60, 100),
            # 0.5-1.5 blocks of lateral scatter off the 13-block spawn cylinder.
            start_speed=random_between(speed_for(0.5, 60), speed_for(1.5, 100)),
            start_size=nf3(random_between(0.12, 0.3)), max_particles=140)
        .child_of(root)
        .with_emission(rate=constant(1.6))
        .with_shape(cylinder(radius=13.0, thickness=1.0))
        .with_curves(
            # Rise 8.0-16.0 blocks over the 60-100t life — sparks that travel WITH the
            # debris field instead of hovering (the old 0.12-0.3 bought 0.4-1.5 blocks).
            # 16 blocks of climb sits inside the +28 cull lid.
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(8.0, 60), speed_for(16.0, 100)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID), (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID_ALT), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.85, 1.6)))
        .with_cull_box((-22.0, -6.0, -22.0), (22.0, 28.0, 22.0)))

    # One soft shock ring at the break beat: a single expanding disc flash.
    (fx.particle_emitter(
            "collapse_ring",
            duration=60, looping=False, start_lifetime=constant(36),
            start_speed=constant(0), start_size=nf3(8.0), max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.9, 0.65, 1.4)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 6.0, [(0.0, 0.12, 1.0, 1.0, 0.35, 0.6, 1.0, 1.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.65), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-30.0, -6.0, -30.0), (30.0, 12.0, 30.0)))

    # F-068 trailing dust: a delayed, taller, longer-lived curtain chasing the debris
    # up — the "nachziehender Staub" behind the rising fragment field.
    (fx.particle_emitter(
            "collapse_trail_dust",
            duration=380, looping=False, start_delay=constant(40),
            start_lifetime=random_between(110, 170),
            # ~0.6 blocks of outward creep — the curtain widens, it does not spray.
            start_speed=constant(speed_for(0.6, 140)),
            start_size=nf3(random_between(2.6, 4.6), random_between(2.6, 4.6),
                           random_between(2.6, 4.6)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.55))
        .with_shape(cylinder(radius=12.0, thickness=0.7))
        .with_curves(
            # THE headline fix of this veil: "chases the debris" up a shaft whose own
            # cull lid is +52, but at 0.2-0.34 it climbed 1.1-2.9 blocks and never left
            # the island. Now 26-46 blocks over the 110-170t life — the trailing curtain
            # actually follows CreditsShatterAct's fragments, and still clears the lid.
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 0.3-0.45 rad (18-26 deg) of drift over the same life.
                orbital=nf3(constant(0), constant(spin_for(0.35, 140)), constant(0)),
                linear=nf3(constant(0),
                           random_between(speed_for(26.0, 110), speed_for(46.0, 170)),
                           constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.4), (0.8, 0.28), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.3, 0.11, 0.06, 0.16), (1.0, 0.05, 0.03, 0.09)],
                [(0.0, *DUST_BIRTH), (0.3, 0.09, 0.05, 0.14), (1.0, 0.04, 0.02, 0.08)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-20.0, -6.0, -20.0), (20.0, 52.0, 20.0)))

    # F-068 aftershock rings: two softer echoes of the break ring, baked on the exact
    # act ticks CreditsShatterAct steps its fragments outward (AFTERSHOCK_AT = 150/300;
    # the server pairs them with shake + thunder on the same ticks).
    (fx.particle_emitter(
            "collapse_aftershock",
            duration=340, looping=False, start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(6.0), max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=150, count=constant(1)),
                               burst(time=300, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.8, 0.6, 1.25)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 4.5, [(0.0, 0.15, 1.0, 1.0, 0.35, 0.65, 1.0, 1.0)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-26.0, -6.0, -26.0), (26.0, 12.0, 26.0)))

    # F-068 altar-core flash: the heart of the island breaks LAST — one hot white-violet
    # pop over the dais, baked on CORE_BREAK_TICK = 270 (the server's light-flash beat).
    (fx.particle_emitter(
            "collapse_core_flash",
            duration=320, looping=False, start_lifetime=constant(24),
            start_speed=constant(0), start_size=nf3(3.0), max_particles=2)
        .child_of(root)
        .at(0.0, 5.0, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=270, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.6, 1.25, 2.2)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 3.2, [(0.0, 0.2, 1.0, 1.0, 0.3, 1.0, 1.0, 0.55)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.95), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-12.0, -2.0, -12.0), (12.0, 16.0, 12.0)))

    # F-068 core sparks: a single spray of hot motes ejecting with the core fragments.
    (fx.particle_emitter(
            "collapse_core_sparks",
            duration=320, looping=False, start_lifetime=random_between(30, 55),
            # 4.0-11.0 blocks of throw off the 1.6-block core shell over a 30-55t life
            # — a spray that clears the dais (the old 0.35-0.75 moved it 0.5-2.0).
            start_speed=random_between(speed_for(4.0, 30), speed_for(11.0, 55)),
            start_size=nf3(random_between(0.12, 0.28)), max_particles=30)
        .child_of(root)
        .at(0.0, 5.0, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=270, count=constant(26))])
        .with_shape(sphere(radius=1.6, thickness=0.5))
        .with_curves(
            # A 1.0-3.0-block updraft rides on top of the spray (blocks/SECOND).
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           random_between(speed_for(1.0, 30), speed_for(3.0, 55)),
                           constant(0))),
            # 26 motes are born inside a 1.6-block shell on the SAME tick — without a
            # birth tint that stack sums to one white ball on the dais.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.9), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.12, *VIOLET_HOT), (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.12, *VIOLET_HOT_ALT), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.0, 1.9)))
        .with_cull_box((-16.0, -4.0, -16.0), (16.0, 20.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:black_hole_maw — F-056 (rotating accretion swirls + infalling streams)
# ---------------------------------------------------------------------------
def build_black_hole_maw() -> FxBuilder:
    fx = FxBuilder("black_hole_maw")
    root = fx.empty("maw_root")

    # Inner accretion swirl: fast, hot, tight — the bright disc hugging the horizon.
    (fx.particle_emitter(
            "maw_swirl_inner",
            duration=340, looping=False, start_lifetime=random_between(40, 70),
            # The disc's own motion is the orbital + radial pair below; the shape's
            # outward kick would fight the infall, so it is explicitly zero.
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.2, 2.4), random_between(1.2, 2.4),
                           random_between(1.2, 2.4)),
            simulation_space="Local", max_particles=120)
        .child_of(root)
        .with_emission(rate=constant(2.2))
        .with_shape(circle(radius=14.0, thickness=0.45))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 1.7-2.9 rad (97-168 deg) of drag over the 40-70t life — already in
                # rad/SECOND, so this one was authored right; kept and now documented.
                orbital=nf3(constant(0), constant(0.85), constant(0)),
                # Falls 3.0-5.2 blocks inward off the 7.7-14-block spawn band, i.e. it
                # visibly spirals toward the horizon. radial runs at ×0.01/tick, so the
                # old -0.16 dropped it by 0.06-0.11 blocks: a stationary ring.
                # Back-solved from the INNER edge of the spawn band (7.7) so the
                # longest-lived mote still dies at r~2.5 — `radial` follows
                # normalize(localPos), so anything that reaches r=0 flips sign and flies
                # back OUT at the same rate, which reads as a bounce off the horizon.
                radial=constant(-radial_for(5.2, 70))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_HOT), (0.6, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_HOT_ALT), (0.6, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.0, 1.8)))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-30.0, -12.0, -30.0), (30.0, 12.0, 30.0)))

    # Outer accretion swirl: lazy, dark, wide — counter-rotating smoke band.
    (fx.particle_emitter(
            "maw_swirl_outer",
            duration=340, looping=False, start_lifetime=random_between(70, 110),
            start_speed=constant(0.0),  # same as the inner swirl: orbital/radial own it
            start_size=nf3(random_between(2.2, 4.0), random_between(2.2, 4.0),
                           random_between(2.2, 4.0)),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.9))
        .with_shape(circle(radius=26.0, thickness=0.4))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # -1.0..-1.5 rad (-56..-87 deg) over the 70-110t life: the lazy
                # counter-turn against the inner disc. Authored right, kept.
                orbital=nf3(constant(0), constant(-0.28), constant(0)),
                # Creeps 3.1-4.8 blocks inward off the 26-block band — a wide smoke
                # ring that slowly tightens (the old -0.07 moved it 5 cm).
                radial=constant(-radial_for(4.0, 90))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.55), (0.8, 0.35), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH), (0.3, 0.2, 0.1, 0.3), (1.0, 0.08, 0.04, 0.14)],
                [(0.0, *DUST_BIRTH), (0.3, 0.16, 0.09, 0.26), (1.0, 0.06, 0.03, 0.12)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-36.0, -14.0, -36.0), (36.0, 14.0, 36.0)))

    # Infalling streams: motes pulled from a wide shell straight into the center.
    (fx.particle_emitter(
            "maw_infall",
            duration=340, looping=False, start_lifetime=random_between(50, 90),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.15, 0.4)), max_particles=160)
        .child_of(root)
        .with_emission(rate=constant(2.0))
        .with_shape(sphere(radius=32.0, thickness=0.25))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 0.9-1.6 rad (50-89 deg) of curl on the way down: a spiral, not a
                # straight drop. rad/SECOND, authored right, kept.
                orbital=nf3(constant(0), constant(0.35), constant(0)),
                # THE headline fix of this maw: "straight into the center" off a 24-32
                # block shell. radial runs at ×0.01/tick, so -0.5 pulled these motes
                # 0.25-0.45 blocks — 1 % of the way in, i.e. a frozen dot shell. Now
                # 11-20 blocks over the 50-90t life: the short-lived ones fade mid-fall
                # at r~13-21, the long-lived ones arrive at r~4 and die on the disc.
                # The 20 is back-solved from the shell's INNER edge (24) minus a 4-block
                # margin: `radial` follows normalize(localPos), so a mote that reaches
                # r=0 flips sign and flies back out — a bounce, not an accretion.
                radial=constant(-radial_for(20.0, 90))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.8), (0.9, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_MID), (1.0, *VIOLET_HOT)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_MID_ALT), (1.0, *VIOLET_HOT_ALT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.9, 1.7)))
        .with_cull_box((-36.0, -36.0, -36.0), (36.0, 36.0, 36.0)))

    # Photon-ring rim glow: slow hot pulses hugging the event horizon.
    (fx.particle_emitter(
            "maw_rim",
            duration=340, looping=False, start_lifetime=constant(46),
            start_speed=constant(0), start_size=nf3(5.5), max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=6, count=constant(1), cycles=8, interval=42)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.4, 1.05, 2.0)))
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.4, [(0.0, 0.55, 0.8, 1.0, 0.6, 0.9, 1.0, 0.65)]),
            # The 46t pulse outlives its own 42t re-fire interval, so two rim discs
            # always overlap for 4t — a birth tint keeps that seam from flashing white.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.3, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_cull_box((-12.0, -12.0, -12.0), (12.0, 12.0, 12.0)))

    # F-068 ember trails: stretched-billboard embers dragging around the disc RIM —
    # fast orbital motion + a slow radial leak inward; the velocity stretch turns each
    # mote into a short glowing trail hugging the accretion edge.
    (fx.particle_emitter(
            "maw_ember_trails",
            duration=340, looping=False, start_lifetime=random_between(45, 75),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.22, 0.45)),
            simulation_space="Local", max_particles=110)
        .child_of(root)
        .with_emission(rate=constant(1.7))
        .with_shape(circle(radius=25.0, thickness=0.12))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 1.4-2.3 rad (80-131 deg) of rim drag. At r=25 that is 0.78 blocks per
                # TICK, which is what feeds the stretch below — this layer's trail was
                # the one thing in the maw the unit slip never broke.
                orbital=nf3(constant(0), constant(0.62), constant(0)),
                # Leaks 2.3-3.8 blocks inward over the 45-75t life (the old -0.06 was
                # 3 cm, so the "leak" never happened).
                radial=constant(-radial_for(3.0, 60))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.9), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.15, *VIOLET_HOT), (0.6, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.15, *VIOLET_HOT_ALT), (0.6, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.35, 1.05, 1.9)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=2.6, vertex_sorting="DISTANCE")
        .with_cull_box((-32.0, -12.0, -32.0), (32.0, 12.0, 32.0)))

    # F-068 star streaks: fast stretched motes ripped out of a WIDE shell straight into
    # the center — the Photon-space cousin of the post shader's streak layer (stars
    # being pulled in from the space dome).
    (fx.particle_emitter(
            "maw_star_streaks",
            duration=340, looping=False, start_lifetime=random_between(28, 46),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.1, 0.22)), max_particles=120)
        .child_of(root)
        .with_emission(rate=constant(1.5))
        .with_shape(sphere(radius=36.0, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                # 0.3-0.4 rad (14-23 deg): just enough curve that the streak is not a
                # ruler-straight line to the middle.
                orbital=nf3(constant(0), constant(0.18), constant(0)),
                # The hard pull, and the layer that shows why the unit slip mattered
                # TWICE: at -1.05 the radial contributed 0.01 blocks/tick, so
                # `stretch = lengthScale + |v| x velocityScale` never grew and the
                # "streak" was a slow orbital smudge that also never fell. At 16.7-27.4
                # blocks over the 28-46t life it now carries 0.6 blocks/tick, drawing a
                # 0.7-1.5-block streak — longer than its own per-tick travel, so the
                # line reads continuous instead of stroboscopic. The 27.4 is the shell's
                # inner edge (32.4) minus a 5-block margin, so the streak burns out ON
                # the disc instead of crossing r=0 and flying back out (see maw_infall).
                radial=constant(-radial_for(27.4, 46))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.85, 0.55), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, 0.82, 0.72, 1.0), (1.0, *VIOLET_MID)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_HOT_ALT), (1.0, *VIOLET_MID_ALT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.25, 1.05, 1.8)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.2,
                       length_scale=2.0)
        .with_cull_box((-40.0, -40.0, -40.0), (40.0, 40.0, 40.0)))
    return fx


BUILDERS = {
    "credits_collapse.fx": build_credits_collapse,
    "black_hole_maw.fx": build_black_hole_maw,
}


def main() -> int:
    rc = 0
    for name, builder in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        b = builder()
        raw_len, gz_len = b.write(path)  # write() round-trip-validates
        b.write_fxproj(path.with_suffix(".fxproj"))  # binary-diff law sibling
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
