#!/usr/bin/env python3
"""WAVE3 (F-103 Team C "noch mehr Veil×Photon") — three NEW cue families, seven assets,
all one-shots docking onto EXISTING triggers (client rows: veilfx/Wave3FxRows.java):

  eclipse:wave3_buy_team      F-074 AltarBuyCeremony TEAM purchase (Eclipse's Favor /
  eclipse:wave3_buy_gear      Double XP / Supply Beacon), GEAR purchase (item offers)
  eclipse:wave3_buy_heart     and HEART purchase (vitae shard): one category-tinted
                              Photon bloom over the altar crown, fired by the ceremony's
                              shared t=0 beat (beatOpening, cue a = Category ordinal).
                              TEAM = violet helix + the gold ankle wave (burst ticks 16
                              and 52 mirror the ceremony's own FX_SHOCKWAVE sends);
                              GEAR = anvil-spark fan + gleam column + a hover orbit at
                              the gift's spin spot (burst tick 30 = GEAR_RISE_END_TICK);
                              HEART = rose ember fountain + three halo pulses on the
                              bell ticks 24/44/64 (HEART_BELL_TICKS).
  eclipse:wave3_vein_jackpot_warm   W4-FEEL vein-clear payoff: the moment the LAST block
  eclipse:wave3_vein_jackpot_cool   of a tracked ore vein breaks (MiningFeelService,
                              scan.present()==1), a compact spark jackpot pops at the
                              closing block — warm (coal/copper/iron/gold/redstone) or
                              cool (lapis/diamond/emerald/fallback) picked client-side
                              from the cue's packed ore RGB (b), scaled by vein size (a).
  eclipse:wave3_omen_pale     Night-event onset (EclipseSpawner.announceNightEvent):
  eclipse:wave3_omen_umbral   a personal omen at each player's OWN feet on the
                              sendFxEventTo lane (CUE_DAWN_TOLL personal-ceremony law).
                              Pale Night = ivory motes rising out of a ghost-veil;
                              Umbral Night = a reverse gulp — violet motes dragged DOWN
                              into the ground under a creeping near-black fog ring.

House laws applied (wave-13 C5 audit baked in, credits5_fx.py precedent):

  1. UNITS. `linear`/`orbital` are blocks (rad) per SECOND (x0.05/tick), `radial` is
     x0.01/tick — every motion number below is back-solved from the distance its own
     comment promises (`blocks = v x 0.05 x life` linear, `x 0.01 x life` radial).
  2. `radial` follows normalize(localPos) and flips sign across r=0: the umbral gulp
     (the only inward pull here) keeps a birth-shell margin — the longest-lived mote
     born on the ring's r~1.95 inner edge dies at r~0.45, nothing ever bounces out.
  3. `random_gradient` (via `varied()`) on every emitter with a real population.
  4. V2.1 stacking law: dark birth tints on all stacking layers, broad shells, counts
     trimmed; HDR clamped to the 1.45 ceiling with the hue ratio preserved.
  5. arc_mode stays the fxlib default "Random" everywhere; render modes only from
     fxlib's validated enum set (Billboard / StretchedBillboard / Horizontal).
  6. One-shots only — no loops, so no prewarm; every emitter still carries a cull box
     (the credits5 convention, and the LINT-CULL-LONGSHOT margin is thin on the
     120t-duration heart bloom).

Usage:  python3 tools/photon/wave3_fx.py            # write + validate all seven
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
UUIDs are uuid5-deterministic (FxBuilder) — a double run is byte-identical.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, SEG_DECAY_TAIL, SEG_EASE_OUT_CREST,
    SEG_POP_SHRINK, burst, circle, cone, constant, curve, dot, nf3, random_between,
    random_gradient, sphere, texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# ---------------------------------------------------------------------------
# Palettes — anchored on the FX-STYLE-GUIDE §1 tokens (LINT-PALETTE hygiene).
# Birth tints (V2.1 stacking law) start DARK so stacked additive sprites open out
# of near-black instead of converging to the sprite's own colour.
# ---------------------------------------------------------------------------
# TEAM purchase: sacred violet body with the gold colour-wave accent.
VIOLET_BIRTH = (0.10, 0.06, 0.19)     # dark pre-SAC_VOID
VIOLET_MID = (0.725, 0.549, 1.0)      # SAC_VIOLET B98CFF
VIOLET_MID_ALT = (0.482, 0.310, 0.816)  # SAC_DEEP 7B4FD0
VIOLET_HOT = (0.965, 0.937, 1.0)      # SAC_HOT F6EFFF
VIOLET_DEEP = (0.180, 0.137, 0.278)   # SAC_VOID 2E2347
GOLD_BIRTH = (0.14, 0.09, 0.03)
GOLD_MID = (1.0, 0.820, 0.4)          # SAC_GOLD FFD166
GOLD_PALE = (1.0, 0.914, 0.659)       # SAC_GOLD_PALE FFE9A8
# GEAR purchase: forge amber/cream.
AMBER_BIRTH = (0.13, 0.08, 0.03)
AMBER_MID = (1.0, 0.698, 0.369)       # ERA_AMBER FFB25E
AMBER_HOT = (1.0, 0.953, 0.769)       # ERA_CREAM FFF3C4
EMBER_MID = (1.0, 0.482, 0.235)       # ERA_EMBER FF7B3C
# HEART purchase: rose-magenta with a white-hot core.
ROSE_BIRTH = (0.10, 0.03, 0.08)
ROSE_MID = (1.0, 0.310, 0.847)        # GLI_MAGENTA FF4FD8
ROSE_MID_ALT = (0.86, 0.30, 0.70)     # GLI_MAGENTA leaning warm
ROSE_HOT = (0.965, 0.937, 1.0)        # SAC_HOT (white-hot core)
# Vein jackpot cool half: glitch cyan / storm arc.
CYAN_BIRTH = (0.03, 0.10, 0.12)
CYAN_MID = (0.310, 0.910, 1.0)        # GLI_CYAN 4FE8FF
CYAN_ALT = (0.749, 0.851, 1.0)        # STM_ARC BFD9FF
# Pale Night omen: ivory/arc-silver out of era-shadow.
PALE_BIRTH = (0.11, 0.11, 0.17)       # dark pre-ERA_SHADOW
PALE_MID = (0.749, 0.851, 1.0)        # STM_ARC BFD9FF
PALE_HOT = (0.965, 0.937, 1.0)        # SAC_HOT F6EFFF
PALE_DIM = (0.227, 0.227, 0.333)      # ERA_SHADOW 3A3A55
# Umbral Night omen: corrupted violet sinking into ink.
UMBRA_BIRTH = (0.141, 0.110, 0.220)   # GLI_DEAD 241C38
UMBRA_MID = (0.616, 0.306, 0.867)     # COR_VIOLET 9D4EDD
UMBRA_INK = (0.235, 0.035, 0.424)     # COR_INK 3C096C
# Near-black alpha-haze births (the credits5 DUST_BIRTH split).
DUST_BIRTH_COOL = (0.03, 0.03, 0.05)
DUST_BIRTH_VIOLET = (0.022, 0.012, 0.038)

# ---------------------------------------------------------------------------
# WAVE-13 C5 levers (the B6/C4/C5 helper set, copied per generator by design —
# fxlib is FROZEN, and local copies keep the generators from blocking each other).
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


def radial_for(blocks, lifetime_ticks):
    """Authored `velocityOverLifetime.radial` carrying a particle `blocks` far over
    its life — Photon applies radial at x0.01/tick (5x the linear factor)."""
    return round(blocks / (RADIAL_TICK * lifetime_ticks), 1)


def linear_for(blocks, lifetime_ticks):
    """Authored `velocityOverLifetime.linear` (blocks/SECOND) carrying a particle
    `blocks` far over its life — Photon applies linear at x0.05/tick."""
    return round(blocks / (TICK_SECONDS * lifetime_ticks), 2)


# ---------------------------------------------------------------------------
# 1. eclipse:wave3_buy_team — F-074 TEAM purchase (violet helix + gold wave)
# ---------------------------------------------------------------------------
def build_wave3_buy_team() -> FxBuilder:
    fx = FxBuilder("wave3_buy_team")
    root = fx.empty("buy_team_root")

    # Helix: violet motes born on the ceremony's own spiral radius (TEAM_SPIRAL_RADIUS
    # 1.25) swirling up around the vanilla spiral — 1.6 b/s x 0.05 x 50-70t = 4.0-5.6
    # blocks of rise (the scripted spiral tops out at TEAM_SPIRAL_HEIGHT 6.0), with
    # 2.4 rad/s of orbit (~1.1 turns over a 60t life). Emitter stops at t=80, the
    # ceremony's TEAM_SPIRAL_END_TICK, so Photon lets go exactly when the script does.
    (fx.particle_emitter(
            "team_helix",
            duration=80, looping=False, start_lifetime=random_between(50, 70),
            start_speed=constant(0.0),  # orbital+linear below own ALL motion
            start_size=nf3(random_between(0.14, 0.24)),
            simulation_space="Local", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.6))
        .with_shape(circle(radius=1.25, thickness=0.2))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(2.4), constant(0)),
                linear=nf3(constant(0), constant(1.6), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.55), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID), (0.65, *VIOLET_HOT),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID_ALT), (0.65, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 0.95, 1.45)))
        .with_cull_box((-10.0, -2.0, -10.0), (10.0, 9.0, 10.0)))

    # Gold ankle wave: two ring bursts on the ceremony's OWN colour-wave beats (t=16 =
    # TEAM_WAVE_TICK, t=52 = TEAM_WAVE2_TICK — the FX_SHOCKWAVE sends land on the same
    # ticks, so screen ring and physical gold ring read as one event). Radial carries
    # the motes 6.5 blocks out over the 50t life (13.0 x 0.01 x 50), just inside the
    # scripted dust ring's TEAM_RING_MAX_RADIUS 8.0.
    (fx.particle_emitter(
            "team_wave_gold",
            duration=100, looping=False, start_lifetime=random_between(40, 50),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.16, 0.26)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=16, count=constant(20)),
                               burst(time=52, count=constant(14))])
        .with_shape(circle(radius=1.5, thickness=0.12))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(6.5, 50))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.6), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *GOLD_BIRTH), (0.2, *GOLD_MID), (0.7, *GOLD_PALE),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *GOLD_BIRTH), (0.2, *GOLD_PALE), (0.7, *GOLD_MID),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.19, 0.58)))
        .with_cull_box((-10.0, -2.0, -10.0), (10.0, 4.0, 10.0)))

    # Crown flash: two soft violet-white glows blooming once at t=0 under the altar
    # beam and dying — the "the altar answers" accent over beatOpening's chime.
    (fx.particle_emitter(
            "team_crown_glow",
            duration=45, looping=False, start_lifetime=random_between(30, 40),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.8, 2.4), random_between(1.8, 2.4),
                           random_between(1.8, 2.4)),
            simulation_space="Local", max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.7, 0.25), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_HOT), (0.7, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_MID), (0.7, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.95, 1.4)))
        .with_cull_box((-6.0, -3.0, -6.0), (6.0, 6.0, 6.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:wave3_buy_gear — F-074 GEAR purchase (forge sparks + hover orbit)
# ---------------------------------------------------------------------------
def build_wave3_buy_gear() -> FxBuilder:
    fx = FxBuilder("wave3_buy_gear")
    root = fx.empty("buy_gear_root")

    # Anvil-spark fan: a fast double burst out of the crown the moment the altar
    # answers — 2.8-4.4 b/s along a 34-deg up-cone x 0.05 x 14-22t = 2.0-4.8 blocks of
    # streaked flight; the velocity stretch draws each spark as a short hot line.
    (fx.particle_emitter(
            "gear_sparks",
            duration=92, looping=False, start_lifetime=random_between(14, 22),
            start_speed=random_between(2.8, 4.4),
            start_size=nf3(random_between(0.10, 0.16)),
            simulation_space="Local", max_particles=34)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(22)),
                               burst(time=4, count=constant(10))])
        .with_shape(cone(angle=34.0, radius=0.3, thickness=1.0))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.7), (0.65, 0.35), (1.0, 0.0)],
                [(0.0, *AMBER_BIRTH), (0.15, *AMBER_HOT), (0.6, *AMBER_MID),
                 (1.0, *EMBER_MID)],
                [(0.0, *AMBER_BIRTH), (0.15, *AMBER_MID), (0.6, *EMBER_MID),
                 (1.0, *AMBER_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.05, 0.5)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.8,
                       length_scale=1.2)
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 8.0, 8.0)))

    # Gleam column: gold-pale motes climbing the gift's own rise path — 0.9 b/s x
    # 0.05 x 30-44t = 1.35-2.0 blocks, the ceremony's GEAR_RISE_HEIGHT 1.35 plus a
    # little overshoot; the emitter's 60t window covers rise + hover-in.
    (fx.particle_emitter(
            "gear_gleam",
            duration=60, looping=False, start_lifetime=random_between(30, 44),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.12, 0.20)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .with_emission(rate=constant(0.5))
        .with_shape(circle(radius=0.42, thickness=0.4))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.9), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.25), (1.0, 0.0)],
                [(0.0, *GOLD_BIRTH), (0.25, *GOLD_PALE), (0.7, *GOLD_MID),
                 (1.0, *EMBER_MID)],
                [(0.0, *GOLD_BIRTH), (0.25, *GOLD_MID), (0.7, *AMBER_MID),
                 (1.0, *EMBER_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.42, 1.2, 0.62)))
        .with_cull_box((-6.0, -2.0, -6.0), (6.0, 6.0, 6.0)))

    # Hover orbit: ten sparks ringing the gift's spin spot (1.35 above the crown =
    # GEAR_RISE_HEIGHT), born at t=30 (GEAR_RISE_END_TICK — the tick the item parks)
    # and orbiting 3.4 rad/s (~0.17 rad/t) until just before the flight beat at 58.
    (fx.particle_emitter(
            "gear_orbit",
            duration=92, looping=False, start_lifetime=random_between(24, 30),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.13, 0.18)),
            simulation_space="Local", max_particles=12)
        .child_of(root)
        .at(0.0, 1.35, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=30, count=constant(10))])
        .with_shape(circle(radius=0.75, thickness=0.08))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(3.4), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.65), (0.75, 0.35), (1.0, 0.0)],
                [(0.0, *GOLD_BIRTH), (0.2, *GOLD_MID), (0.7, *AMBER_HOT),
                 (1.0, *AMBER_MID)],
                [(0.0, *GOLD_BIRTH), (0.2, *AMBER_HOT), (0.7, *GOLD_MID),
                 (1.0, *AMBER_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.22, 0.6)))
        .with_cull_box((-5.0, -3.0, -5.0), (5.0, 4.0, 5.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:wave3_buy_heart — F-074 HEART purchase (ember fountain + bell halos)
# ---------------------------------------------------------------------------
def build_wave3_buy_heart() -> FxBuilder:
    fx = FxBuilder("wave3_buy_heart")
    root = fx.empty("buy_heart_root")

    # Ember fountain: rose motes riding a narrow 15-deg up-cone — 1.5-2.1 b/s x 0.05 x
    # 46-70t = 3.5-7.3 blocks of climb under the ceremony's own light fountain. The
    # emitter window is 90t = HEART_FOUNTAIN_END_TICK, so both fountains stop together.
    (fx.particle_emitter(
            "heart_fountain",
            duration=90, looping=False, start_lifetime=random_between(46, 70),
            start_speed=random_between(1.5, 2.1),
            start_size=nf3(random_between(0.13, 0.22)),
            simulation_space="Local", max_particles=56)
        .child_of(root)
        .with_emission(rate=constant(0.5))
        .with_shape(cone(angle=15.0, radius=0.35, thickness=1.0))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.5), (0.7, 0.28), (1.0, 0.0)],
                [(0.0, *ROSE_BIRTH), (0.2, *ROSE_MID), (0.65, *ROSE_HOT),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *ROSE_BIRTH), (0.2, *ROSE_MID_ALT), (0.65, *ROSE_MID),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 0.75, 1.1)))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 10.0, 8.0)))

    # Bell halos: three ring pulses at chest height ON the ceremony's bell ticks
    # (HEART_BELL_TICKS 24/44/64 — each pulse lands with a chime). Radial carries a
    # pulse 3.0 blocks out over its 44t life (6.8 x 0.01 x 44).
    (fx.particle_emitter(
            "heart_bells",
            duration=120, looping=False, start_lifetime=random_between(36, 44),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.20)),
            simulation_space="Local", max_particles=40)
        .child_of(root)
        .at(0.0, 1.5, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=24, count=constant(12)),
                               burst(time=44, count=constant(12)),
                               burst(time=64, count=constant(12))])
        .with_shape(circle(radius=0.7, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(3.0, 44))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.55), (0.7, 0.25), (1.0, 0.0)],
                [(0.0, *ROSE_BIRTH), (0.2, *ROSE_HOT), (0.7, *ROSE_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *ROSE_BIRTH), (0.2, *ROSE_MID), (0.7, *ROSE_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.4, 0.72, 1.05)))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 6.0, 8.0)))

    # Heart glow: two dim rose blooms at the crown at t=0 and one echo at t=60 —
    # deliberately soft (peak alpha 0.4): the scripted pillars carry the brightness,
    # this is the warmth underneath them.
    (fx.particle_emitter(
            "heart_glow",
            duration=120, looping=False, start_lifetime=random_between(50, 70),
            start_speed=constant(0.0),
            start_size=nf3(random_between(2.2, 3.0), random_between(2.2, 3.0),
                           random_between(2.2, 3.0)),
            simulation_space="Local", max_particles=3)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(2)),
                               burst(time=60, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.4), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, *ROSE_BIRTH), (0.3, *ROSE_MID), (0.75, *ROSE_MID_ALT),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *ROSE_BIRTH), (0.3, *ROSE_MID_ALT), (0.75, *ROSE_MID),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 0.68, 1.0)))
        .with_cull_box((-7.0, -3.0, -7.0), (7.0, 7.0, 7.0)))
    return fx


# ---------------------------------------------------------------------------
# 4/5. eclipse:wave3_vein_jackpot_{warm,cool} — W4-FEEL vein-clear payoff
# ---------------------------------------------------------------------------
def _build_vein_jackpot(name, birth, mid, hot, spark_hdr, flash_hdr) -> FxBuilder:
    """Shared jackpot skeleton — warm/cool differ only in palette+HDR. Counts stay
    lean (33 sprites total): vein clears are the highest-frequency wave3 moment
    (several per mining trip), so the pop must be cheap enough to never fatigue."""
    fx = FxBuilder(name)
    root = fx.empty(name + "_root")

    # Spark burst: twenty streaks out of a broad shell around the closing block —
    # 2.6-4.0 b/s x 0.05 x 15-24t = 2.0-4.8 blocks of flight in every direction.
    (fx.particle_emitter(
            name + "_sparks",
            duration=60, looping=False, start_lifetime=random_between(15, 24),
            start_speed=random_between(2.6, 4.0),
            start_size=nf3(random_between(0.10, 0.16)),
            simulation_space="Local", max_particles=22)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(20))])
        .with_shape(sphere(radius=0.45, thickness=0.6))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.7), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, *birth), (0.15, *hot), (0.6, *mid), (1.0, *birth)],
                [(0.0, *birth), (0.15, *mid), (0.6, *hot), (1.0, *birth)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=spark_hdr))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=1.1)
        .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0)))

    # Jackpot flash: one hot core sprite popping and dying inside 14t — the "ding".
    (fx.particle_emitter(
            name + "_flash",
            duration=60, looping=False, start_lifetime=random_between(10, 14),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.5, 1.9), random_between(1.5, 1.9),
                           random_between(1.5, 1.9)),
            simulation_space="Local", max_particles=1)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.85), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, *birth), (0.2, *hot), (1.0, *mid)],
                [(0.0, *birth), (0.2, *mid), (1.0, *hot)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=flash_hdr))
        .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0)))

    # Coin ring: a flat halo rolling 2.2 blocks out of the block face over ~30t
    # (6.9 x 0.01 x 32) — the jackpot's "payout table" read, ground-plane like a
    # dropped coin (Horizontal render mode).
    (fx.particle_emitter(
            name + "_ring",
            duration=60, looping=False, start_lifetime=random_between(26, 32),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.15, 0.22)),
            simulation_space="Local", max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(12))])
        .with_shape(circle(radius=0.5, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(2.2, 32))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.55), (0.7, 0.25), (1.0, 0.0)],
                [(0.0, *birth), (0.2, *mid), (0.7, *hot), (1.0, *birth)],
                [(0.0, *birth), (0.2, *hot), (0.7, *mid), (1.0, *birth)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=spark_hdr))
        .with_renderer(render_mode="Horizontal")
        .with_cull_box((-5.0, -3.0, -5.0), (5.0, 3.0, 5.0)))
    return fx


def build_wave3_vein_jackpot_warm() -> FxBuilder:
    return _build_vein_jackpot(
        "wave3_vein_jackpot_warm", AMBER_BIRTH, GOLD_MID, AMBER_HOT,
        spark_hdr=hdr(1.45, 1.15, 0.55), flash_hdr=hdr(1.45, 1.3, 0.85))


def build_wave3_vein_jackpot_cool() -> FxBuilder:
    return _build_vein_jackpot(
        "wave3_vein_jackpot_cool", CYAN_BIRTH, CYAN_MID, CYAN_ALT,
        spark_hdr=hdr(0.6, 1.25, 1.45), flash_hdr=hdr(0.85, 1.3, 1.45))


# ---------------------------------------------------------------------------
# 6. eclipse:wave3_omen_pale — Pale Night onset (personal, at the player's feet)
# ---------------------------------------------------------------------------
def build_wave3_omen_pale() -> FxBuilder:
    fx = FxBuilder("wave3_omen_pale")
    root = fx.empty("omen_pale_root")

    # Rising motes: ivory points drifting up out of the ground around the player —
    # 0.55 b/s x 0.05 x 70-90t = 1.9-2.5 blocks of rise on a broad 1.7-radius shell.
    # Deliberately quiet: peak alpha 0.38 (an omen whispers, the announcement shouts).
    (fx.particle_emitter(
            "pale_motes",
            duration=100, looping=False, start_lifetime=random_between(70, 90),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.10, 0.18)),
            simulation_space="Local", max_particles=38)
        .child_of(root)
        .with_emission(rate=constant(0.32))
        .with_shape(circle(radius=1.7, thickness=0.55))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.55), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.38), (0.75, 0.2), (1.0, 0.0)],
                [(0.0, *PALE_BIRTH), (0.3, *PALE_MID), (0.7, *PALE_HOT),
                 (1.0, *PALE_DIM)],
                [(0.0, *PALE_BIRTH), (0.3, *PALE_HOT), (0.7, *PALE_MID),
                 (1.0, *PALE_DIM)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 1.2, 1.35)))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 7.0, 8.0)))

    # Halo: one thin ring exhaling at chest height — 3.5 blocks out over its 60t life
    # (5.8 x 0.01 x 60), a slow cold breath rolling away from the player.
    (fx.particle_emitter(
            "pale_halo",
            duration=100, looping=False, start_lifetime=random_between(50, 60),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.20)),
            simulation_space="Local", max_particles=18)
        .child_of(root)
        .at(0.0, 1.25, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=10, count=constant(16))])
        .with_shape(circle(radius=0.9, thickness=0.08))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(3.5, 60))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.3), (0.7, 0.15), (1.0, 0.0)],
                [(0.0, *PALE_BIRTH), (0.25, *PALE_HOT), (0.75, *PALE_MID),
                 (1.0, *PALE_DIM)],
                [(0.0, *PALE_BIRTH), (0.25, *PALE_MID), (0.75, *PALE_HOT),
                 (1.0, *PALE_DIM)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 1.15, 1.3)))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 4.0, 8.0)))

    # Ghost veil: three whisper-alpha smoke sheets lifting off the ground — the body
    # of the omen under the mote points (alpha-blended, so DISTANCE-sorted).
    (fx.particle_emitter(
            "pale_veil",
            duration=100, looping=False, start_lifetime=random_between(70, 90),
            start_speed=constant(0.0),
            start_size=nf3(random_between(2.6, 3.6), random_between(2.6, 3.6),
                           random_between(2.6, 3.6)),
            simulation_space="Local", max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
        .with_shape(sphere(radius=1.2, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.25), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.12), (0.75, 0.08), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH_COOL), (0.3, 0.30, 0.33, 0.42), (1.0, *PALE_DIM)],
                [(0.0, *DUST_BIRTH_COOL), (0.3, 0.25, 0.28, 0.38), (1.0, *PALE_DIM)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 8.0, 8.0)))
    return fx


# ---------------------------------------------------------------------------
# 7. eclipse:wave3_omen_umbral — Umbral Night onset (the reverse gulp)
# ---------------------------------------------------------------------------
def build_wave3_omen_umbral() -> FxBuilder:
    fx = FxBuilder("wave3_omen_umbral")
    root = fx.empty("omen_umbral_root")

    # Reverse gulp: violet motes born on a broad chest-height ring (a circle, not a
    # sphere — a shell around a ground anchor would waste a third of its births
    # underground) and dragged down-inward toward the player. The radial pulls 1.5
    # blocks in over the longest 68t life (-2.2 x 0.01 x 68), so a birth at the ring's
    # r~1.95 inner edge still dies at r~0.45: safely outside the r=0 radial flip
    # (nothing ever bounces out — the sink below is vertical and cannot close the
    # horizontal distance). The -0.55 b/s sink (1.4-1.9 blocks over the life) folds
    # the ring from chest height down INTO the ground: the night swallowing the light.
    (fx.particle_emitter(
            "umbral_gulp",
            duration=100, looping=False, start_lifetime=random_between(50, 68),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.12, 0.20)),
            simulation_space="Local", max_particles=42)
        .child_of(root)
        .at(0.0, 0.9, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(22)),
                               burst(time=22, count=constant(16))])
        .with_shape(circle(radius=2.6, thickness=0.25))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=constant(-radial_for(1.5, 68)),
                linear=nf3(constant(0), constant(-0.55), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.75, 0.28), (1.0, 0.0)],
                [(0.0, *UMBRA_BIRTH), (0.25, *UMBRA_MID), (0.75, *UMBRA_INK),
                 (1.0, *UMBRA_BIRTH)],
                [(0.0, *UMBRA_BIRTH), (0.25, *UMBRA_INK), (0.75, *UMBRA_MID),
                 (1.0, *UMBRA_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 0.85, 1.45)))
        .with_cull_box((-8.0, -3.0, -8.0), (8.0, 6.0, 8.0)))

    # Creeping fog: a near-black violet ground ring breathing 2.5 blocks outward over
    # its 80-105t life (2.4 x 0.01 x 105) — the dark that arrives with the night
    # (alpha-blended body layer, DISTANCE-sorted, whisper alpha).
    (fx.particle_emitter(
            "umbral_fog",
            duration=100, looping=False, start_lifetime=random_between(80, 105),
            start_speed=constant(0.0),
            start_size=nf3(random_between(2.2, 3.2), random_between(2.2, 3.2),
                           random_between(2.2, 3.2)),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(4)),
                               burst(time=30, count=constant(3))])
        .with_shape(circle(radius=1.1, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(2.5, 105))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.14), (0.75, 0.09), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH_VIOLET), (0.3, *VIOLET_DEEP), (1.0, *UMBRA_BIRTH)],
                [(0.0, *DUST_BIRTH_VIOLET), (0.3, 0.14, 0.10, 0.24),
                 (1.0, *UMBRA_BIRTH)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-9.0, -2.0, -9.0), (9.0, 5.0, 9.0)))

    # Rising dread: a dim violet halo climbing from the ankles to the chest — 0.5 b/s
    # x 0.05 x 55-70t = 1.4-1.75 blocks, the "it is looking at you" line of the omen.
    (fx.particle_emitter(
            "umbral_rise",
            duration=100, looping=False, start_lifetime=random_between(55, 70),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.13, 0.19)),
            simulation_space="Local", max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=6, count=constant(12))])
        .with_shape(circle(radius=0.95, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.5), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.35), (0.75, 0.2), (1.0, 0.0)],
                [(0.0, *UMBRA_BIRTH), (0.3, *UMBRA_MID), (0.75, *UMBRA_INK),
                 (1.0, *UMBRA_BIRTH)],
                [(0.0, *UMBRA_BIRTH), (0.3, *UMBRA_INK), (0.75, *UMBRA_MID),
                 (1.0, *UMBRA_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 0.8, 1.4)))
        .with_cull_box((-7.0, -2.0, -7.0), (7.0, 5.0, 7.0)))
    return fx


BUILDERS = {
    "wave3_buy_team.fx": build_wave3_buy_team,
    "wave3_buy_gear.fx": build_wave3_buy_gear,
    "wave3_buy_heart.fx": build_wave3_buy_heart,
    "wave3_vein_jackpot_warm.fx": build_wave3_vein_jackpot_warm,
    "wave3_vein_jackpot_cool.fx": build_wave3_vein_jackpot_cool,
    "wave3_omen_pale.fx": build_wave3_omen_pale,
    "wave3_omen_umbral.fx": build_wave3_omen_umbral,
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
