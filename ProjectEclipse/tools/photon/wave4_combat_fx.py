#!/usr/bin/env python3
"""WAVE4-COMBAT (F-104 Team A "Combat Feel") — one NEW cue family, four assets, all
one-shots on combat beats (client rows: veilfx/Wave4CombatFxRows.java):

  eclipse:wave4_crit_gleam    A3 crit sparkle: a lean gold glint fan popping at the
                              victim's chest the tick a player crit connects
                              (CombatFeedbackFx.onCriticalHit) — LAYERED over the
                              vanilla crit stars + the impact_light Quasar pop, so
                              it must stay the cheapest asset here (13 sprites).
  eclipse:wave4_heavy_impact  A4 damage-magnitude payoff: the >=8-damage bucket
                              (CombatFeedbackFx.onLivingDamagePost) lands an
                              amber-ember streak flower + core flash + a flat
                              payout ring at the victim's chest, scaled by damage.
  eclipse:wave4_stagger_arc   A6 hound stagger tell: a 40t asset window — exactly
                              ChargedLungeGoal.STAGGER_TICKS — of cyan crackle +
                              one dizzy orbit halo around the whiffed hound's head
                              (StormHoundRenderer rising-edge dispatch, entity-
                              attached so it wobbles with the hound).
  eclipse:wave4_dissolve_motes  A2 glitch de-rez: as a GLITCHED corpse opens its
                              last-10t alpha fade, cyan/magenta pixel motes lift
                              off the body volume under a shrinking near-black
                              veil — the body scatters INTO the motes
                              (GlitchedGeoRenderer fade-start dispatch, position-
                              anchored: an entity attach would die with the poof).

House laws applied (wave3_fx.py precedent, wave-13 C5 audit baked in):

  1. UNITS. `linear`/`orbital` are blocks (rad) per SECOND (x0.05/tick), `radial` is
     x0.01/tick — every motion number below is back-solved from the distance its own
     comment promises (`blocks = v x 0.05 x life` linear, `x 0.01 x life` radial).
  2. `random_gradient` (via `varied()`) on every emitter with a real population —
     the dissolve motes lean on it hardest (primary ramp cyan, sibling magenta:
     every pixel rolls its own corruption hue).
  3. V2.1 stacking law: dark birth tints on all stacking layers, broad shells,
     counts trimmed; HDR clamped to the 1.45 ceiling with the hue ratio preserved.
  4. arc_mode stays the fxlib default "Random"; render modes only from fxlib's
     validated enum set (Billboard / StretchedBillboard / Horizontal).
  5. One-shots only — no loops, no prewarm; every emitter carries a cull box sized
     for its own longest advertised flight.
  6. Palette tokens reuse the FX-STYLE-GUIDE §1 anchors already minted by wave3
     (SAC gold, ERA amber/ember, GLI cyan/magenta, GLI_DEAD births) — no new
     palette entries, no new LINT-PALETTE advisories.

Usage:  python3 tools/photon/wave4_combat_fx.py        # write + validate all four
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
UUIDs are uuid5-deterministic (FxBuilder) — a double run is byte-identical.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, SEG_DECAY_TAIL, SEG_EASE_OUT_CREST,
    SEG_POP_SHRINK, burst, circle, constant, curve, dot, nf3, random_between,
    random_gradient, sphere, texture_material, validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# ---------------------------------------------------------------------------
# Palettes — the wave3 FX-STYLE-GUIDE §1 anchors, verbatim (LINT-PALETTE hygiene).
# Birth tints (V2.1 stacking law) start DARK so stacked additive sprites open out
# of near-black instead of converging to the sprite's own colour.
# ---------------------------------------------------------------------------
# Crit gleam: sacred gold with a pale-cream flash (the vanilla crit-star language).
GOLD_BIRTH = (0.14, 0.09, 0.03)
GOLD_MID = (1.0, 0.820, 0.4)          # SAC_GOLD FFD166
GOLD_PALE = (1.0, 0.914, 0.659)       # SAC_GOLD_PALE FFE9A8
# Heavy impact: forge amber/ember (the "you hit something MASSIVE" heat read).
AMBER_BIRTH = (0.13, 0.08, 0.03)
AMBER_MID = (1.0, 0.698, 0.369)       # ERA_AMBER FFB25E
AMBER_HOT = (1.0, 0.953, 0.769)       # ERA_CREAM FFF3C4
EMBER_MID = (1.0, 0.482, 0.235)       # ERA_EMBER FF7B3C
# Stagger arc: glitch cyan / storm arc (the hound's own spine-glow palette).
CYAN_BIRTH = (0.03, 0.10, 0.12)
CYAN_MID = (0.310, 0.910, 1.0)        # GLI_CYAN 4FE8FF
CYAN_ALT = (0.749, 0.851, 1.0)        # STM_ARC BFD9FF
# Dissolve motes: the GLITCHED corruption split — cyan vs magenta out of GLI_DEAD.
GLITCH_BIRTH = (0.141, 0.110, 0.220)  # GLI_DEAD 241C38
MAGENTA_MID = (1.0, 0.310, 0.847)     # GLI_MAGENTA FF4FD8
VIOLET_DEEP = (0.180, 0.137, 0.278)   # SAC_VOID 2E2347
DUST_BIRTH_COOL = (0.03, 0.03, 0.05)

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
# 1. eclipse:wave4_crit_gleam — A3 crit sparkle (the LEAN one: every crit fires it)
# ---------------------------------------------------------------------------
def build_wave4_crit_gleam() -> FxBuilder:
    fx = FxBuilder("wave4_crit_gleam")
    root = fx.empty("crit_gleam_root")

    # Glint fan: twelve gold streaks out of a tight chest shell — 2.4-3.6 b/s x 0.05 x
    # 8-13t = 0.96-2.34 blocks of flight; the velocity stretch draws each as a short
    # hot line (the crit-star language, but authored). Cheapest possible: crits are
    # the highest-frequency wave4 moment and this LAYERS over vanilla crit stars +
    # the impact_light Quasar pop.
    (fx.particle_emitter(
            "gleam_glints",
            duration=30, looping=False, start_lifetime=random_between(8, 13),
            start_speed=random_between(2.4, 3.6),
            start_size=nf3(random_between(0.09, 0.14)),
            simulation_space="Local", max_particles=12)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
        .with_shape(sphere(radius=0.28, thickness=0.6))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.7), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, *GOLD_BIRTH), (0.15, *GOLD_PALE), (0.6, *GOLD_MID),
                 (1.0, *GOLD_BIRTH)],
                [(0.0, *GOLD_BIRTH), (0.15, *GOLD_MID), (0.6, *GOLD_PALE),
                 (1.0, *GOLD_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.19, 0.58)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=1.1)
        .with_cull_box((-5.0, -5.0, -5.0), (5.0, 5.0, 5.0)))

    # Gleam flash: one pale pop sprite dying inside 11t — the "ding" under the fan.
    (fx.particle_emitter(
            "gleam_flash",
            duration=30, looping=False, start_lifetime=random_between(8, 11),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.9, 1.2), random_between(0.9, 1.2),
                           random_between(0.9, 1.2)),
            simulation_space="Local", max_particles=1)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.8), (0.6, 0.3), (1.0, 0.0)],
                [(0.0, *GOLD_BIRTH), (0.2, *GOLD_PALE), (1.0, *GOLD_MID)],
                [(0.0, *GOLD_BIRTH), (0.2, *GOLD_MID), (1.0, *GOLD_PALE)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.3, 0.85)))
        .with_cull_box((-3.0, -3.0, -3.0), (3.0, 3.0, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:wave4_heavy_impact — A4 >=8-damage bucket (the meaty payoff)
# ---------------------------------------------------------------------------
def build_wave4_heavy_impact() -> FxBuilder:
    fx = FxBuilder("wave4_heavy_impact")
    root = fx.empty("heavy_impact_root")

    # Streak flower: eighteen amber-ember streaks out of a broad chest shell in every
    # direction — 3.0-4.4 b/s x 0.05 x 12-18t = 1.8-3.96 blocks of radial flight.
    (fx.particle_emitter(
            "impact_streaks",
            duration=40, looping=False, start_lifetime=random_between(12, 18),
            start_speed=random_between(3.0, 4.4),
            start_size=nf3(random_between(0.10, 0.16)),
            simulation_space="Local", max_particles=18)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
        .with_shape(sphere(radius=0.4, thickness=0.6))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.7), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, *AMBER_BIRTH), (0.15, *AMBER_HOT), (0.6, *AMBER_MID),
                 (1.0, *EMBER_MID)],
                [(0.0, *AMBER_BIRTH), (0.15, *AMBER_MID), (0.6, *EMBER_MID),
                 (1.0, *AMBER_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.05, 0.5)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.7,
                       length_scale=1.15)
        .with_cull_box((-7.0, -7.0, -7.0), (7.0, 7.0, 7.0)))

    # Impact flash: one hot cream core popping and dying inside 14t.
    (fx.particle_emitter(
            "impact_flash",
            duration=40, looping=False, start_lifetime=random_between(10, 14),
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
                [(0.0, *AMBER_BIRTH), (0.2, *AMBER_HOT), (1.0, *EMBER_MID)],
                [(0.0, *AMBER_BIRTH), (0.2, *EMBER_MID), (1.0, *AMBER_HOT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.3, 0.85)))
        .with_cull_box((-4.0, -4.0, -4.0), (4.0, 4.0, 4.0)))

    # Payout ring: a flat halo rolling 2.4 blocks out of the chest plane over ~30t
    # (8.0 x 0.01 x 30) — the "that one COUNTED" read, coin-drop flat (Horizontal).
    (fx.particle_emitter(
            "impact_ring",
            duration=40, looping=False, start_lifetime=random_between(24, 30),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.20)),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(10))])
        .with_shape(circle(radius=0.5, thickness=0.1))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(radial_for(2.4, 30))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.55), (0.7, 0.25), (1.0, 0.0)],
                [(0.0, *AMBER_BIRTH), (0.2, *AMBER_MID), (0.7, *AMBER_HOT),
                 (1.0, *AMBER_BIRTH)],
                [(0.0, *AMBER_BIRTH), (0.2, *AMBER_HOT), (0.7, *AMBER_MID),
                 (1.0, *AMBER_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.15, 0.55)))
        .with_renderer(render_mode="Horizontal")
        .with_cull_box((-5.0, -3.0, -5.0), (5.0, 3.0, 5.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:wave4_stagger_arc — A6 hound stagger tell (40t = STAGGER_TICKS window)
# ---------------------------------------------------------------------------
def build_wave4_stagger_arc() -> FxBuilder:
    fx = FxBuilder("wave4_stagger_arc")
    root = fx.empty("stagger_arc_root")

    # Crackle sputter: cyan arc-lets fizzing off the head shell over the WHOLE 40t
    # stagger window (rate 0.45/t ~= 18 total) — 0.9-1.5 b/s x 0.05 x 5-9t = 0.2-0.7
    # blocks of jitter, short and spitting (the discharge bleeding off harmlessly).
    (fx.particle_emitter(
            "stagger_crackle",
            duration=40, looping=False, start_lifetime=random_between(5, 9),
            start_speed=random_between(0.9, 1.5),
            start_size=nf3(random_between(0.08, 0.13)),
            simulation_space="Local", max_particles=20)
        .child_of(root)
        .with_emission(rate=constant(0.45))
        .with_shape(sphere(radius=0.5, thickness=0.35))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.7), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, *CYAN_BIRTH), (0.2, *CYAN_MID), (0.6, *CYAN_ALT),
                 (1.0, *CYAN_BIRTH)],
                [(0.0, *CYAN_BIRTH), (0.2, *CYAN_ALT), (0.6, *CYAN_MID),
                 (1.0, *CYAN_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.6, 1.25, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                       length_scale=1.0)
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))

    # Dizzy halo: eight motes orbiting the head at 4.6 rad/s (~0.23 rad/t — about 1.3
    # turns over the 30-36t life, the cartoon "seeing stars" ring); born at t=2 and
    # dying just as the 40t stagger window closes.
    (fx.particle_emitter(
            "stagger_halo",
            duration=40, looping=False, start_lifetime=random_between(30, 36),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.11, 0.16)),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(8))])
        .with_shape(circle(radius=0.55, thickness=0.08))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(4.6), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_EASE_OUT_CREST]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.6), (0.75, 0.3), (1.0, 0.0)],
                [(0.0, *CYAN_BIRTH), (0.25, *CYAN_ALT), (0.7, *CYAN_MID),
                 (1.0, *CYAN_BIRTH)],
                [(0.0, *CYAN_BIRTH), (0.25, *CYAN_MID), (0.7, *CYAN_ALT),
                 (1.0, *CYAN_BIRTH)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.85, 1.3, 1.45)))
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:wave4_dissolve_motes — A2 glitch de-rez (fired at the fade start)
# ---------------------------------------------------------------------------
def build_wave4_dissolve_motes() -> FxBuilder:
    fx = FxBuilder("wave4_dissolve_motes")
    root = fx.empty("dissolve_motes_root")

    # Pixel motes: the body scattering into its own colour channels — 24 points off
    # the corpse volume in two waves, drifting up 0.65 b/s x 0.05 x 16-26t = 0.52-0.85
    # blocks. The random_gradient split is the whole point here: primary ramp cyan,
    # sibling magenta — every mote rolls one of the two corruption channels, so the
    # de-rez reads as the datamosh texture unweaving (not a single-hue puff). Lives
    # 6-16t past the corpse's own poof: the motes ARE what's left.
    (fx.particle_emitter(
            "dissolve_pixels",
            duration=30, looping=False, start_lifetime=random_between(16, 26),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.07, 0.12)),
            simulation_space="Local", max_particles=26)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(14)),
                               burst(time=5, count=constant(10))])
        .with_shape(sphere(radius=0.55, thickness=0.8))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.65), constant(0))),
            size_over_lifetime=curve(0.0, 1.0, [SEG_DECAY_TAIL]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.6), (0.7, 0.3), (1.0, 0.0)],
                [(0.0, *GLITCH_BIRTH), (0.2, *CYAN_MID), (0.7, *CYAN_ALT),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *GLITCH_BIRTH), (0.2, *MAGENTA_MID), (0.7, *CYAN_MID),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 1.2, 1.45)))
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))

    # Shrinking veil: two near-black smoke sheets collapsing over the corpse as the
    # alpha fade opens (SEG_POP_SHRINK — a brief swell, then the shrink INTO nothing);
    # whisper alpha 0.12, alpha-blended so it must be DISTANCE-sorted.
    (fx.particle_emitter(
            "dissolve_veil",
            duration=30, looping=False, start_lifetime=random_between(12, 18),
            start_speed=constant(0.0),
            start_size=nf3(random_between(1.4, 1.8), random_between(1.4, 1.8),
                           random_between(1.4, 1.8)),
            simulation_space="Local", max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
        .with_shape(sphere(radius=0.4, thickness=0.5))
        .with_curves(
            size_over_lifetime=curve(0.0, 1.0, [SEG_POP_SHRINK]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.12), (0.75, 0.07), (1.0, 0.0)],
                [(0.0, *DUST_BIRTH_COOL), (0.3, *VIOLET_DEEP), (1.0, *GLITCH_BIRTH)],
                [(0.0, *DUST_BIRTH_COOL), (0.3, 0.10, 0.12, 0.20),
                 (1.0, *GLITCH_BIRTH)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-4.0, -3.0, -4.0), (4.0, 4.0, 4.0)))
    return fx


BUILDERS = {
    "wave4_crit_gleam.fx": build_wave4_crit_gleam,
    "wave4_heavy_impact.fx": build_wave4_heavy_impact,
    "wave4_stagger_arc.fx": build_wave4_stagger_arc,
    "wave4_dissolve_motes.fx": build_wave4_dissolve_motes,
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
