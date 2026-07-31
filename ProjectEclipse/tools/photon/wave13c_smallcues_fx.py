#!/usr/bin/env python3
"""wave13c_smallcues_fx — FX-WAVE-13 team C4's two NEW Photon assets (census §6).

    eclipse:contract_seal_brand   N8  — the contract's seal glyph SEARS itself into the
                                        ground at the resolution and glimmers for a full
                                        60 s afterwards. Fired per online player at that
                                        player's own feet from `ContractService`'s single
                                        resolution funnel (`finishWindow`), beside the
                                        existing `CUE_CONTRACT_OMEN` release ripple.
    eclipse:sanctum_confession    N14 — entering the L5 Sanctum, script glyphs rise out
                                        of the crater like prayers and are drunk by the
                                        Lightfall column. Anchored at the SAME point
                                        `client/sanctum/SanctumLightfall` pours its
                                        column from (altar anchor − 13), so the glyphs
                                        climb the real column, not an invented one.

Rows for both live in `veilfx/SmallCueFxRows.java` (C4's own registrar; the N14 window
controller is a nested class there, mirroring `WorldEventPhotonFxRows.DungeonMawIdle`).

This script IS the committed source of the two blobs — re-run it instead of hand-editing
the gzip-NBT, and it writes the editor-openable `.fxproj` sibling beside every `.fx`
(v7 bar §5.1 rule 8 / binary-diff law):

    python3 tools/photon/wave13c_smallcues_fx.py
    python3 tools/photon/fxlib.py validate --lint src/main/resources/assets/eclipse/fx/*.fx

WAVE-13 laws applied at birth (these two assets were authored AFTER the census, so they
never carried the legacy debt the polish pass had to undo elsewhere):

  1. UNITS. `startSpeed` / `velocityOverLifetime.linear` / `orbital` are per SECOND
     (Photon applies `value × 0.05` per tick); `radial` is `value × 0.01` per tick.
     Every velocity below is written as `distance / (0.05 × lifetimeTicks)` with the
     target distance named in the comment, so the numbers are auditable.
  2. `random_gradient` on every emitter that spawns more than a couple of particles.
  3. Dark birth tints (V2.1 stacking law) — additive ramps OPEN on a bruise.
  4. HDR ceiling 1.45 (`hdr()` clamps and keeps the channel ratio = the hue).
  5. Timing snap — `SEG_SNAP_*`: 2-4t attacks, long decays.

Style-guide conformance (FX-STYLE-GUIDE.md):
  - N8 rides the shipped contract blood-orange family (the `contract_mark` 0xFFE05A28
    precedent → ERA_EMBER / ERA_AMBER) cooling into COR_INK #3C096C — contract dread is
    eclipse-stuff gone sour, never transparent black.
  - N14 is pure SACRED (SAC_HOT / SAC_VIOLET / SAC_DEEP), fading to SAC_VOID #2E2347.
  - Motion verbs: N8 is a BURN (sear in fast, then almost nothing moves for a minute);
    N14 is a sacred vertical — slow rise, slow orbit, radial convergence into the column.
  - Budgets: N8 spends ~150 particles across its whole 60 s (≈2.5/s); N14 ~130 across
    10 s. Both carry cull boxes on every emitter despite being one-shots — a 60 s brand
    parked in the world must not cost anything once the camera turns away.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, REPO_ROOT, burst, circle,
    constant, curve, dot, gradient, nf3, random_between, random_curve, random_gradient,
    texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_GLYPH = "eclipse:textures/particle/herald_glyph.png"   # fx_herald_summon.py's rune
TEX_WISP = "eclipse:textures/particle/wisp_white.png"


def rgb(hexcode: int):
    """FX-STYLE-GUIDE §1 token hex → the 0..1 triple photon gradients want."""
    return ((hexcode >> 16 & 0xFF) / 255.0, (hexcode >> 8 & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


# §1 SACRED (N14) and the contract/ERA family (N8).
SAC_HOT = rgb(0xF6EFFF)
SAC_VIOLET = rgb(0xB98CFF)
SAC_DEEP = rgb(0x7B4FD0)
SAC_VOID = rgb(0x2E2347)
ERA_CREAM = rgb(0xFFF3C4)
ERA_AMBER = rgb(0xFFB25E)
ERA_EMBER = rgb(0xFF7B3C)
COR_INK = rgb(0x3C096C)
#: The shipped contract brand hue (`contract_mark` 0xFFE05A28) — inside §1 tolerance
#: of ERA_EMBER, and the colour players already read as "a contract touched this".
SEAL_BLOOD = rgb(0xE05A28)

#: Birth tints (V2.1 stacking law): darker than every ramp's own fade target.
BLOOD_BIRTH = (0.16, 0.05, 0.04)
SAC_BIRTH = (0.13, 0.10, 0.21)
ASH_BIRTH = (0.12, 0.11, 0.13)

# ---------------------------------------------------------------------------
# Timing segments (8-float beziers, x/y normalized 0..1)
# ---------------------------------------------------------------------------
#: WAVE-13 impact envelope: ~2t attack, long afterglow tail.
SEG_SNAP_FLASH = (0.0, 0.22, 0.045, 1.0, 0.4, 0.52, 1.0, 0.0)
#: WAVE-13 ring expansion: 90 % of the reach inside the first third, then a slow creep.
SEG_SNAP_OUT = (0.0, 0.0, 0.05, 0.55, 0.28, 0.94, 1.0, 1.0)
#: WAVE-13 swell: full open by t ≈ 0.30, then a long exhale.
SEG_SNAP_SWELL = [(0.0, 0.0, 0.05, 0.66, 0.15, 1.04, 0.3, 1.0),
                  (0.3, 1.0, 0.56, 0.88, 0.84, 0.28, 1.0, 0.0)]
#: N8 brand life (gradient ALPHA stops over the 1200t): sear to full inside the first
#: 10 ticks, cool hard, then glimmer irregularly for the whole minute and let go over
#: the last ~5 %. The uneven plateau IS the "glimmt 60 s nach" spec — a brand that
#: pulsed on a countable beat would read as a machine, not as a burn.
SEG_BRAND_ALPHA = [(0.0, 0.0), (0.008, 1.0), (0.04, 0.78), (0.12, 0.6),
                   (0.3, 0.54), (0.42, 0.66), (0.55, 0.5), (0.68, 0.61),
                   (0.8, 0.47), (0.9, 0.53), (0.96, 0.3), (1.0, 0.0)]
#: N14 prayer rise: a glyph leaves the crater floor reluctantly, then is DRUNK by the
#: column — slow start, hard acceleration into the last third.
SEG_PRAYER_PULL = (0.0, 0.0, 0.35, 0.08, 0.72, 0.55, 1.0, 1.0)

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45").
HDR_CEILING = 1.45


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


# ---------------------------------------------------------------------------
# N8 — eclipse:contract_seal_brand
# ---------------------------------------------------------------------------
#: The brand's whole life (60 s, the census §6 N8 spec). Every emitter shares it so the
#: runtime dies in one piece instead of leaving a stray sub-emitter parked in the world.
BRAND_TICKS = 1200
#: Radius the seal is burned at (the glyph quad is 3.2 blocks across; the ember crawl
#: and the scorch ring are sized off this).
SEAL_RADIUS = 1.6


def build_contract_seal_brand() -> FxBuilder:
    """N8 — one-shot, 60 s, ~150 particles total (≈2.5/s: cheaper than the omen ripple
    it follows). Spawned at a player's feet, horizontal: the brand lies ON the ground.

    Read: 3t sear flash → the glyph is simply THERE, white-hot → it cools over ~4 s to a
    deep ember and then glimmers, irregularly, for the rest of the minute → the last 5 s
    let go. Smoke only exists for the first 6 s (a burn stops smoking); the ember crawl
    and the lift motes carry the remaining 54 s on a trickle."""
    fx = FxBuilder("contract_seal_brand")

    # --- the sear: 3t impact ring, the frame the brand is BORN in -----------
    (fx.particle_emitter(
            "sear_flash",
            duration=BRAND_TICKS, looping=False, start_delay=constant(0),
            start_lifetime=constant(26), start_speed=constant(0.0),
            start_size=nf3(SEAL_RADIUS * 0.5), simulation_space="World", max_particles=2)
       .at(0.0, 0.06, 0.0)  # hair above the surface: no z-fight with the ground quad
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING_SOFT, hdr=hdr(1.9, 1.1, 0.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 4.0, 6.0))
       .with_lights(sky=15, block=15)
       .with_curves(
            size_over_lifetime=nf3(*[curve(SEAL_RADIUS * 0.5, SEAL_RADIUS * 2.6,
                                           [SEG_SNAP_OUT], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 1.0), (0.45, 0.42), (1.0, 0.0)],
                [(0.0, *ERA_CREAM), (0.35, *ERA_AMBER), (1.0, *SEAL_BLOOD)])))

    # --- the brand itself: ONE glyph quad, alive for the whole minute -------
    # The hero. A single particle by design (a "seal" that is 20 stacked quads is a
    # smear, not a sigil), so it takes the authored gradient rather than random_gradient
    # — and its glimmer rides the LIGHTS module instead: two re-rolled 4..15 lightmap
    # tracks with long dim stretches, i.e. the brand pulses on its own broken rhythm
    # for 60 s and never on a countable beat (ADVANCED-1 §2).
    (fx.particle_emitter(
            "seal_glyph",
            duration=BRAND_TICKS, looping=False, start_delay=constant(0),
            start_lifetime=constant(BRAND_TICKS), start_speed=constant(0.0),
            start_size=nf3(SEAL_RADIUS * 2.0), simulation_space="World", max_particles=2)
       .at(0.0, 0.04, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_GLYPH, hdr=hdr(1.5, 0.85, 0.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 4.0, 6.0))
       .with_lights(
            sky=15,
            block=random_curve(
                4.0, 15.0,
                # Track A: white-hot, a fast cool, then two slow swells and a long dim.
                [(0.0, 1.0, 0.02, 0.95, 0.05, 0.55, 0.12, 0.42),
                 (0.12, 0.42, 0.3, 0.7, 0.45, 0.34, 0.6, 0.5),
                 (0.6, 0.5, 0.72, 0.28, 0.86, 0.46, 1.0, 0.12)],
                # Track B: same birth, a different minute — never in phase with A.
                [(0.0, 1.0, 0.03, 0.9, 0.07, 0.4, 0.18, 0.55),
                 (0.18, 0.55, 0.34, 0.3, 0.52, 0.62, 0.68, 0.32),
                 (0.68, 0.32, 0.8, 0.52, 0.92, 0.22, 1.0, 0.1)],
                "lifetime"))
       .with_curves(
            # A brand does not breathe in SIZE — it only cools. The 2 % overshoot is the
            # sear pushing the char outward before the glyph settles into the ground.
            size_over_lifetime=nf3(*[curve(SEAL_RADIUS * 1.9, SEAL_RADIUS * 2.05,
                                           [(0.0, 0.4, 0.01, 1.0, 0.05, 0.85, 0.2, 0.72),
                                            (0.2, 0.72, 0.5, 0.66, 0.8, 0.62, 1.0, 0.6)],
                                           "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                SEG_BRAND_ALPHA,
                [(0.0, *ERA_CREAM), (0.03, *ERA_AMBER), (0.12, *SEAL_BLOOD),
                 (0.8, *SEAL_BLOOD), (1.0, *COR_INK)])))

    # --- the char: a dark scorch disc UNDER the glyph -----------------------
    # Alpha-blended and DISTANCE-sorted (LINT-ALPHA-NOSORT); the only non-additive
    # element, and the reason the brand reads as burned INTO the ground rather than
    # projected onto it.
    (fx.particle_emitter(
            "scorch",
            duration=BRAND_TICKS, looping=False, start_delay=constant(0),
            start_lifetime=constant(BRAND_TICKS), start_speed=constant(0.0),
            start_size=nf3(SEAL_RADIUS * 2.4), simulation_space="World", max_particles=2)
       .at(0.0, 0.02, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING_SOFT, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 4.0, 6.0))
       .with_curves(
            size_over_lifetime=nf3(*[curve(SEAL_RADIUS * 1.2, SEAL_RADIUS * 2.6,
                                           [SEG_SNAP_OUT], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.03, 0.58), (0.7, 0.46), (0.94, 0.3), (1.0, 0.0)],
                [(0.0, 0.09, 0.07, 0.06), (1.0, 0.13, 0.09, 0.08)])))

    # --- the burn smoke: the first 6 s only ---------------------------------
    # 1.4 blocks of lift over a 70-100t life ⇒ 1.4 / (0.05 × 85) ≈ 0.33 b/s, plus a
    # 0.2-0.5 b/s birth scatter off the ring (0.7-2.5 blocks — smoke off a 1.6-block
    # brand must stay over the brand; anything faster reads as wind, not as a burn).
    (fx.particle_emitter(
            "burn_smoke",
            duration=BRAND_TICKS, looping=False, start_delay=constant(0),
            start_lifetime=random_between(70, 100), start_speed=random_between(0.2, 0.5),
            start_size=nf3(random_between(0.4, 0.8), random_between(0.4, 0.8),
                           random_between(0.4, 0.8)),
            simulation_space="World", max_particles=28)
       # Rate curve, not a burst: the smoke swells for ~1 s and is gone by t=120 (6 s).
       .with_emission(rate=curve(0.0, 0.55,
                                 [(0.0, 0.1, 0.004, 0.95, 0.012, 1.0, 0.03, 0.85),
                                  (0.03, 0.85, 0.055, 0.5, 0.08, 0.16, 0.1, 0.0),
                                  (0.1, 0.0, 0.4, 0.0, 0.7, 0.0, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=SEAL_RADIUS * 0.9, thickness=0.5))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 8.0, 6.0))
       .with_curves(
            noise=dict(frequency=0.4, position=nf3(0.06)),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(0.33), constant(0))),
            size_over_lifetime=nf3(*[curve(1.0, 2.1, [SEG_SNAP_SWELL[0]], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.4), (0.7, 0.24), (1.0, 0.0)],
                [(0.0, *ASH_BIRTH), (0.3, 0.31, 0.26, 0.25), (1.0, 0.17, 0.15, 0.16)],
                [(0.0, *ASH_BIRTH), (0.4, 0.24, 0.2, 0.2), (1.0, *ASH_BIRTH)],
                alpha_alt=[(0.0, 0.0), (0.25, 0.3), (0.75, 0.3), (1.0, 0.0)])))

    # --- the 54 s afterglow: embers crawling the seal rim -------------------
    # 0.55 blocks of lift over an 80-130t life ⇒ 0.55 / (0.05 × 105) ≈ 0.1 b/s; the
    # crawl itself is orbital (0.28 rad/s ≈ 1 turn per 22 s — a drift, not a carousel)
    # with a slight radial tuck so an ember drifts toward the glyph as it dies.
    (fx.particle_emitter(
            "ember_crawl",
            duration=BRAND_TICKS, looping=False, start_delay=constant(8),
            start_lifetime=random_between(80, 130), start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="World", max_particles=40)
       # Dense while the burn is fresh, a bare trickle for the rest of the minute, out
       # before the brand lets go (so the last thing to die is the glyph itself).
       .with_emission(rate=curve(0.0, 0.6,
                                 [(0.0, 0.2, 0.01, 1.0, 0.03, 0.7, 0.08, 0.3),
                                  (0.08, 0.3, 0.3, 0.16, 0.6, 0.13, 0.88, 0.1),
                                  (0.88, 0.1, 0.93, 0.04, 0.97, 0.0, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=SEAL_RADIUS, thickness=0.35))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.5, 0.8, 0.4),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 5.0, 6.0))
       .with_lights(sky=15, block=12)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.14), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.28), constant(0)),
                # −0.25 blocks over ~105t ⇒ 0.25 / (0.01 × 105) ≈ 0.24, inward. (The
                # seal ring is only 1.6 blocks across: a 2.4 here would fire every
                # ember straight through the glyph and out the far side.)
                radial=constant(-0.24)),
            size_over_lifetime=nf3(*[curve(0.35, 1.0, [SEG_SNAP_SWELL[1]], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.85), (0.65, 0.5), (1.0, 0.0)],
                [(0.0, *BLOOD_BIRTH), (0.2, *ERA_AMBER), (1.0, *SEAL_BLOOD)],
                [(0.0, *BLOOD_BIRTH), (0.3, *SEAL_BLOOD), (1.0, *COR_INK)],
                alpha_alt=[(0.0, 0.0), (0.22, 0.6), (0.7, 0.42), (1.0, 0.0)])))

    # --- the last grain: single sparks lifting off the glyph strokes --------
    # 1.1 blocks over a 55-80t life ⇒ 1.1 / (0.05 × 68) ≈ 0.32 b/s.
    (fx.particle_emitter(
            "seal_motes",
            duration=BRAND_TICKS, looping=False, start_delay=constant(20),
            start_lifetime=random_between(55, 80), start_speed=random_between(0.15, 0.35),
            start_size=nf3(random_between(0.03, 0.07), random_between(0.03, 0.07),
                           random_between(0.03, 0.07)),
            simulation_space="World", max_particles=24)
       .with_emission(rate=curve(0.0, 0.22,
                                 [(0.0, 0.35, 0.04, 1.0, 0.12, 0.6, 0.25, 0.42),
                                  (0.25, 0.42, 0.5, 0.5, 0.75, 0.3, 0.9, 0.16),
                                  (0.9, 0.16, 0.94, 0.06, 0.97, 0.0, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=SEAL_RADIUS * 0.75, thickness=1.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.3, 0.9, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 6.0, 6.0))
       .with_curves(
            noise=dict(frequency=0.7, position=nf3(0.05)),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.24, 0.42), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.7), (1.0, 0.0)],
                [(0.0, *BLOOD_BIRTH), (0.25, *ERA_CREAM), (1.0, *ERA_EMBER)],
                [(0.0, *BLOOD_BIRTH), (0.35, *ERA_AMBER), (1.0, *COR_INK)],
                alpha_alt=[(0.0, 0.0), (0.3, 0.5), (1.0, 0.0)])))
    return fx


# ---------------------------------------------------------------------------
# N14 — eclipse:sanctum_confession
# ---------------------------------------------------------------------------
#: The confession runs 10 s and is anchored where SanctumLightfall's column STARTS
#: (`FxAnchors.ALTAR_CENTER` − `AltarSanctumBuilder.ALTAR_ABOVE_GROUND + 9` = −13).
CONFESSION_TICKS = 200
#: Crater floor relative to that anchor: the updraft source sits at anchor−20, i.e.
#: 7 below the column head. Prayers are born there.
CRATER_FLOOR_Y = -7.0
#: The column is a thin pour — glyphs converge to roughly this radius as they arrive.
COLUMN_RADIUS = 0.8
#: Glyphs are born spread across the bowl.
BOWL_RADIUS = 3.4


def build_sanctum_confession() -> FxBuilder:
    """N14 — one-shot, 10 s, ~130 particles. Anchored at the Lightfall column head.

    Read: the crater exhales → script glyphs peel off the bowl floor and climb, turning
    slowly, converging on the column as they rise (`radial` does the funnel work) → the
    column drinks them at the top, where each one blooms out and is gone. A whispered
    version of the Sanctum Bloom, not a second one: no flash frame, no shockwave, and
    the loudest thing in it is a 1.45-HDR quad the size of a book page."""
    fx = FxBuilder("sanctum_confession")

    # --- the exhale that starts it: the bowl breathes out -------------------
    # 5 blocks of lift over a 90-130t life ⇒ 5 / (0.05 × 110) ≈ 0.9 b/s.
    (fx.particle_emitter(
            "bowl_exhale",
            duration=CONFESSION_TICKS, looping=False, start_delay=constant(0),
            start_lifetime=random_between(90, 130), start_speed=random_between(0.2, 0.5),
            start_size=nf3(random_between(0.7, 1.4), random_between(0.7, 1.4),
                           random_between(0.7, 1.4)),
            simulation_space="World", max_particles=32)
       .at(0.0, CRATER_FLOOR_Y, 0.0)
       .with_emission(rate=curve(0.0, 0.5,
                                 [(0.0, 0.15, 0.05, 1.0, 0.18, 0.8, 0.35, 0.45),
                                  (0.35, 0.45, 0.6, 0.28, 0.8, 0.08, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=BOWL_RADIUS, thickness=0.8))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-8.0, -10.0, -8.0), (8.0, 8.0, 8.0))
       .with_curves(
            noise=dict(frequency=0.35, position=nf3(0.05)),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.7, 1.1), constant(0)),
                # Converge from the 3.4 bowl toward the 0.8 column: −2.6 blocks over
                # ~110t ⇒ 2.6 / (0.01 × 110) ≈ 2.4, inward.
                radial=constant(-2.4)),
            size_over_lifetime=nf3(*[curve(0.8, 1.5, [SEG_SNAP_SWELL[0]], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.16), (0.75, 0.11), (1.0, 0.0)],
                [(0.0, *SAC_BIRTH), (0.35, *SAC_DEEP), (1.0, *SAC_VOID)],
                [(0.0, *SAC_BIRTH), (0.45, *SAC_VOID), (1.0, *SAC_BIRTH)],
                alpha_alt=[(0.0, 0.0), (0.3, 0.12), (0.8, 0.14), (1.0, 0.0)])))

    # --- THE PRAYERS: script glyphs climbing into the column ----------------
    # The climb must cover exactly the crater-floor→column-head span (7 blocks). The
    # rate is a 0.35→2.6 b/s curve, and SEG_PRAYER_PULL's mean height is ≈0.37, so the
    # mean speed is 0.35 + 0.37×2.25 ≈ 1.18 b/s ⇒ 1.18 × 0.05 × 120t ≈ 7.1 blocks: a
    # glyph reaches the column head just as its size curve tears it wide. The easing is
    # the point — the first half is a reluctant lift, the last third is the column
    # visibly PULLING. (Peak-rate arithmetic would read 2.6 × 0.05 × 140 = 18 blocks;
    # that is the bound, not the travel.) The glyph quad
    # faces the camera (LOOKAT_XYZ): a rune the player cannot read edge-on is not a
    # confession. Radial funnels 3.4 → ~0.8 on the way up.
    (fx.particle_emitter(
            "prayer_glyphs",
            duration=CONFESSION_TICKS, looping=False, start_delay=constant(10),
            start_lifetime=random_between(100, 140), start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(0.5, 0.95), random_between(0.5, 0.95),
                           random_between(0.5, 0.95)),
            simulation_space="World", max_particles=36)
       .at(0.0, CRATER_FLOOR_Y, 0.0)
       .with_emission(rate=curve(0.0, 0.42,
                                 [(0.0, 0.05, 0.06, 0.85, 0.15, 1.0, 0.32, 0.9),
                                  (0.32, 0.9, 0.55, 0.72, 0.75, 0.3, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=BOWL_RADIUS, thickness=0.6))
       .with_material(texture_material(TEX_GLYPH, hdr=hdr(1.45, 1.2, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(facing_mode="LOOKAT_XYZ", vertex_sorting="NONE")
       .with_cull_box((-8.0, -10.0, -8.0), (8.0, 10.0, 8.0))
       .with_lights(sky=15, block=13)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(0.35, 2.6, [SEG_PRAYER_PULL], "lifetime", "value"),
                           constant(0)),
                orbital_mode="AngularVelocity",
                # 0.22 rad/s over ~6 s ≈ 75° of turn: the glyphs drift around the column
                # rather than ride a visible carousel (SACRED motion verb).
                orbital=nf3(constant(0), constant(0.22), constant(0)),
                # 2.6 blocks of funnel over ~120t ⇒ 2.6 / (0.01 × 120) ≈ 2.2, inward.
                radial=constant(-2.2)),
            # Written small, opened by the climb, then torn wide in the last 15 % as the
            # column takes it — the "drunk by the light" frame.
            size_over_lifetime=nf3(*[curve(0.55, 1.9,
                                           [(0.0, 0.28, 0.08, 0.62, 0.3, 0.72, 0.6, 0.78),
                                            (0.6, 0.78, 0.78, 0.86, 0.88, 1.0, 1.0, 0.0)],
                                           "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.62), (0.62, 0.8), (0.9, 0.55), (1.0, 0.0)],
                [(0.0, *SAC_BIRTH), (0.2, *SAC_DEEP), (0.72, *SAC_VIOLET),
                 (1.0, *SAC_HOT)],
                [(0.0, *SAC_BIRTH), (0.3, *SAC_VIOLET), (0.8, *SAC_HOT), (1.0, *SAC_VOID)],
                alpha_alt=[(0.0, 0.0), (0.18, 0.5), (0.66, 0.72), (0.92, 0.4), (1.0, 0.0)])))

    # --- the column answering: it brightens as the prayers arrive -----------
    # Three tall vertical quads at the column head. No motion at all — the whole beat is
    # in the alpha, which swells as the first glyphs reach the top (~t=90) and relaxes.
    (fx.particle_emitter(
            "column_answer",
            duration=CONFESSION_TICKS, looping=False, start_delay=constant(30),
            start_lifetime=constant(150), start_speed=constant(0.0),
            start_size=nf3(COLUMN_RADIUS * 2.2, 7.4, COLUMN_RADIUS * 2.2),
            simulation_space="World", max_particles=4)
       .at(0.0, CRATER_FLOOR_Y / 2.0, 0.0)  # centred on the crater-floor→head span
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_WISP, hdr=hdr(1.3, 1.15, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(facing_mode="ROTATE_Y", vertex_sorting="NONE")
       .with_cull_box((-8.0, -10.0, -8.0), (8.0, 10.0, 8.0))
       .with_lights(sky=15, block=14)
       .with_curves(
            size_over_lifetime=nf3(
                curve(0.75, 1.25, [SEG_SNAP_SWELL[0]], "lifetime", "size"),
                curve(0.95, 1.05, [(0.0, 0.2, 0.3, 0.9, 0.6, 1.0, 1.0, 0.6)],
                      "lifetime", "size"),
                curve(0.75, 1.25, [SEG_SNAP_SWELL[0]], "lifetime", "size")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.18), (0.45, 0.34), (0.7, 0.26), (1.0, 0.0)],
                [(0.0, *SAC_DEEP), (0.5, *SAC_VIOLET), (1.0, *SAC_HOT)])))

    # --- the swallow: each arrival sparkles out at the column head ----------
    # 1.6 blocks of scatter over a 20-34t life ⇒ 1.6 / (0.05 × 27) ≈ 1.2 b/s; the sparks
    # are born ON the column head (the small sphere), so they read as the glyph coming
    # apart rather than as a burst fired at it.
    (fx.particle_emitter(
            "arrival_sparks",
            duration=CONFESSION_TICKS, looping=False, start_delay=constant(80),
            start_lifetime=random_between(20, 34), start_speed=random_between(0.9, 1.8),
            start_size=nf3(random_between(0.04, 0.09), random_between(0.04, 0.09),
                           random_between(0.04, 0.09)),
            simulation_space="World", max_particles=48)
       .with_emission(rate=curve(0.0, 0.7,
                                 [(0.0, 0.1, 0.08, 0.9, 0.2, 1.0, 0.45, 0.72),
                                  (0.45, 0.72, 0.66, 0.4, 0.85, 0.1, 1.0, 0.0)],
                                 "duration", "rate"))
       .with_shape(circle(radius=COLUMN_RADIUS, thickness=1.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.45, 1.3, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box((-8.0, -6.0, -8.0), (8.0, 8.0, 8.0))
       .with_lights(sky=15, block=15)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.3, 0.5), constant(0))),
            size_over_lifetime=nf3(*[curve(0.3, 1.0, [SEG_SNAP_FLASH], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=varied(
                [(0.0, 0.95), (0.5, 0.6), (1.0, 0.0)],
                [(0.0, *SAC_BIRTH), (0.1, *SAC_HOT), (1.0, *SAC_VIOLET)],
                [(0.0, *SAC_BIRTH), (0.18, *SAC_VIOLET), (1.0, *SAC_VOID)],
                alpha_alt=[(0.0, 0.7), (0.4, 0.72), (1.0, 0.0)])))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "contract_seal_brand.fx": build_contract_seal_brand,
    "sanctum_confession.fx": build_sanctum_confession,
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
            print(f"FAIL  {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} "
                  f"(raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
