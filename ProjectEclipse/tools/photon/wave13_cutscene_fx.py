#!/usr/bin/env python3
"""WAVE13-CUTSCENE (team B7) — one Photon garnish beat per cutscene sequence, filling
the "weakest beat" gaps from FX_CENSUS_WAVE13 §5. All cues are Photon-only LAYER rows
registered in veilfx/CutsceneBeatFxRows.java; timings live in
docs/plans_v3/session_0730/B7_CUTSCENE_REPORT.md.

  eclipse:beat_intro_windshear    IntroSequence FLIGHT/APPROACH (660t sustain, re-fired
                                  every 220t): wind-shear streamers born on a 30-58
                                  block ring around the vortex column, condensing
                                  inward (radial -6 -> -15) while orbiting with the
                                  storm; the escalation into the long glide is an
                                  emissionRate CURVE (world-anchored emitter =>
                                  accumulatedDistance stays 0, distanceRate would be
                                  dead — the wave-13 anchor law).
  eclipse:beat_monolith_pulse     ExpansionSequence FLYOVER: a distant monolith
                                  silhouette pulse — six shaft slats flare violet up a
                                  14-block spine, crown glints pop off the tip. Fired
                                  at the far frontier anchors while the camera skims.
  eclipse:beat_flyover_shadow     ExpansionSequence FLYOVER: the growth front's shadow
                                  RUNS — a dark soft-particle band marching 44 blocks
                                  along local -Z at 10 b/s (ferry_wave_crest build:
                                  burst on launch tick + World-space march; the Java
                                  leg yaw-rotates the executor outward), dust wake and
                                  sparse violet rim glints riding the leading edge.
  eclipse:beat_nether_ember_tear  NetherOpeningSequence AFTERMATH: the "first ember
                                  tear" — ONE lava crack creeps away from the crater
                                  rim (90t of births at the origin, 1.6-3.2 b/s along
                                  local -Z decaying to a crawl: slow ones stay near,
                                  fast ones reach ~12 blocks => the LINE grows), a
                                  glowing tear head, thin fumaroles rising where the
                                  crack has passed, and the t=30 aftershock dust ring
                                  the server doubles with its RUMBLE broadcast.
  eclipse:beat_finale_keyglyphs   FinaleSequence UNLOCK: the key turning made visible.
                                  Three click-beats (t=8/22/36 — the server clicks sit
                                  on the same ticks) each snap 18 beard-glyphs onto a
                                  vertical ring in the gate plane (radial -40 pull that
                                  ARRESTS = the snap), the third click flashes the
                                  ring, then the portal veil INHALES (indraw motes
                                  t=38-58). Authored facing local -Z for the house
                                  yaw leg (180 deg - a).
  eclipse:beat_credits_afterglow  CreditsSequence WHITEOUT->BEACH: the afterglow
                                  bridge — white ash motes trickle down through the
                                  beach stillness for 10 s. The crossfade is BAKED:
                                  emissionRate ramps in over 40t, holds, and releases
                                  from t=140 so the last motes die exactly with the
                                  200t window. Deliberately NO hdr anywhere
                                  (LINT-HDR-DUST: ash does not bloom).

End-Arrival CHARGE re-cues the existing eclipse:end_crack_bleed asset (default leg,
positions on a golden-angle spiral) — no new asset, see the report §1 row 4.

House laws honoured here (FX_CENSUS_WAVE13 §8, ferryman2_fx.py precedents):
speeds are BLOCKS/SECOND (radial x0.01/t), HDR_CEILING 1.45 via the local hdr()
clamp, every alpha-blended pass sorts DISTANCE, no section-tubes, all curves
genuinely eased (LINT-LINEAR-CURVE).

Usage:  python3 tools/photon/wave13_cutscene_fx.py       # write + validate all six
Testers: Photon caches .fx statically — run /photon_client clear_client_fx_cache
after every rebuild (+ F3+T when dropping in as a resource pack).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, burst, circle, cone, constant,
    curve, dot, function_shape, gradient, material_shader, nf3, random_between,
    random_gradient, sphere, texture_material, validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_FLICKER_COMMIT, SEG_OVERSHOOT_SETTLE,
    SEG_POP_SHRINK, SEG_SMOOTH_DOWN, SEG_SMOOTH_UP)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"

# FX-STYLE-GUIDE §1 dark stacking bases + the sequence palettes these beats sit inside.
STM_SLATE = (0.227, 0.227, 0.333)     # #3A3A55 — storm slate (intro sky, shadows)
SAC_VOID = (0.180, 0.137, 0.278)      # #2E2347 — void violet base
VIOLET_MID = (0.612, 0.482, 0.878)    # #9C7BE0 — expansion/finale violet
VIOLET_HOT = (0.816, 0.702, 1.0)      # #D0B3FF
GOLD = (0.98, 0.82, 0.45)             # finale key gold
EMBER_HOT = (1.0, 0.56, 0.20)         # nether lava tear
EMBER_DEEP = (0.42, 0.13, 0.05)
ASH_WHITE = (0.93, 0.94, 0.97)        # credits afterglow (deliberately un-bloomed)
ASH_DIM = (0.62, 0.63, 0.70)

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def rand_size3(lo, hi):
    """Per-axis random start size (the house nf3(random, random, random) idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` module body (ferryman2 pattern — LDLib2 Range fields are a/b)."""
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — authored ramp plus a sibling ramp in the same palette."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def ring_shape(r_lo, r_hi, y_expr="0"):
    """Uniform bearing on a flat ring band r_lo..r_hi (storm_nearfield house idiom)."""
    r = f"({r_lo}+randomB*{r_hi - r_lo})"
    return function_shape(x=f"cos(randomA*2*PI)*{r}",
                          z=f"sin(randomA*2*PI)*{r}",
                          y=y_expr)


# ---------------------------------------------------------------------------
# 1. eclipse:beat_intro_windshear — Intro FLIGHT/APPROACH (660t sustain window)
# ---------------------------------------------------------------------------
# The camera glides for ~700 ticks with nothing new after the vortex stands. This is
# the wind the vortex should be DRINKING: streamers born far out on the ring, dragged
# inward and around. Escalation is the emissionRate curve 0.3 -> 1.4 across the 660t —
# by the APPROACH the air visibly thickens. Re-fires every 220t are dedup-safe.
WINDSHEAR_DURATION = 660
WINDSHEAR_CULL = ((-62.0, -8.0, -62.0), (62.0, 44.0, 62.0))


def build_beat_intro_windshear() -> FxBuilder:
    fx = FxBuilder("beat_intro_windshear")

    # Hero pass: stretched shear streamers. radial is x0.01/t, so the -6 -> -15 curve
    # is 0.06 -> 0.15 b/t of condensation (5-12 blocks over a life) while the orbital
    # term (rad/s, jar-verified: AngularVelocity applies n*0.05 rad/t) swings them with
    # the storm at 4-10 b/s tangential on the band — together they read as wind
    # SPIRALLING into the column, not particles falling toward a point.
    (fx.particle_emitter(
            "shear_streamers",
            duration=WINDSHEAR_DURATION, looping=False,
            start_lifetime=random_between(60, 96), start_speed=constant(0),
            start_size=rand_size3(0.12, 0.24),
            simulation_space="Local", max_particles=96)
        .with_emission(rate=curve(0.3, 1.4, [SEG_SMOOTH_UP], "duration", "rate"))
        .with_shape(ring_shape(30.0, 58.0, y_expr="4+randomC*30"))
        .with_module("colorBySpeed", color_by_speed(STM_SLATE, (1.0, 1.0, 1.0), 3.0, 11.0))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-6.0, -15.0, [SEG_SMOOTH_UP], "lifetime", "value"),
                orbital=nf3(constant(0), random_between(0.10, 0.22), constant(0)),
                linear=nf3(constant(0), random_between(0.2, 0.9), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.85), (0.75, 0.55), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (0.75, 0.62, 0.68, 0.85), (1.0, 0.82, 0.88, 1.0)],
                [(0.0, 0.19, 0.20, 0.30), (1.0, 0.68, 0.75, 0.94)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 1.2, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.7,
                       length_scale=2.6, vertex_sorting="NONE")
        .with_lights(sky=15, block=15)
        .with_cull_box(*WINDSHEAR_CULL))

    # Body pass: sparse soft motes drifting on the same band — the streaks alone read
    # as scratches; these give the wind a BODY. soft_particle so the band survives
    # crossing the terrain silhouettes under the flight path.
    (fx.particle_emitter(
            "shear_motes",
            duration=WINDSHEAR_DURATION, looping=False,
            start_lifetime=random_between(50, 86), start_speed=constant(0),
            start_size=rand_size3(0.9, 1.8),
            simulation_space="Local", max_particles=40)
        .with_emission(rate=curve(0.12, 0.5, [SEG_SMOOTH_UP], "duration", "rate"))
        .with_shape(ring_shape(32.0, 56.0, y_expr="2+randomC*26"))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-3.0, -8.0, [SEG_SMOOTH_UP], "lifetime", "value"),
                orbital=nf3(constant(0), random_between(0.05, 0.11), constant(0))),
            noise=dict(frequency=0.5, position=nf3(0.05)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.3), (0.8, 0.2), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, 0.30, 0.32, 0.44)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 1.2, "NearFade": 0.7},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*WINDSHEAR_CULL))
    return fx


# ---------------------------------------------------------------------------
# 2a. eclipse:beat_monolith_pulse — Expansion FLYOVER distant monolith flare
# ---------------------------------------------------------------------------
# Fired at frontier anchors 60-100 blocks off the camera line: it must read as ONE
# bright vertical gesture at distance, so the shaft slats are big, few and HDR-violet,
# and everything else is restraint. 70t: flare, crown pops, decay.
MONOLITH_CULL = ((-6.0, -2.0, -6.0), (6.0, 20.0, 6.0))


def build_beat_monolith_pulse() -> FxBuilder:
    fx = FxBuilder("beat_monolith_pulse")

    # Six shaft slats stacked up the 14-block spine; alpha runs FLICKER_COMMIT so the
    # monolith hesitates before committing to the flare — the census note asked for a
    # pulse, not a lamp turning on.
    (fx.particle_emitter(
            "pulse_shaft",
            duration=70, looping=False, start_lifetime=random_between(44, 58),
            start_speed=constant(0),
            start_size=nf3(random_between(1.6, 2.4), random_between(3.4, 5.0),
                           random_between(1.6, 2.4)),
            simulation_space="Local", max_particles=10)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
        .with_shape(function_shape(x="(randomB-0.5)*0.9", y="1+randomA*12",
                                   z="(randomC-0.5)*0.9"))
        .with_curves(
            size_over_lifetime=curve(0.7, 1.15, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.28, 0.28), (0.5, 0.95), (0.78, 0.5), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (0.5, *VIOLET_MID), (1.0, *VIOLET_HOT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 0.95, 1.45)))
        .with_lights(sky=15, block=15)
        .with_cull_box(*MONOLITH_CULL))

    # Crown glints popping off the tip on the commit beat (t=28 = the alpha crest).
    (fx.particle_emitter(
            "pulse_crown",
            duration=70, looping=False, start_lifetime=random_between(18, 30),
            start_speed=random_between(2.0, 4.5),
            start_size=rand_size3(0.14, 0.26),
            simulation_space="Local", max_particles=8)
        .with_emission(rate=constant(0.0), bursts=[burst(time=28, count=constant(7))])
        .with_shape(cone(angle=24.0, radius=0.5))
        .at(0.0, 14.0, 0.0)
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.2, [SEG_SMOOTH_DOWN], "lifetime")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 1.0, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6,
                       length_scale=1.8, vertex_sorting="NONE")
        .with_lights(sky=15, block=15)
        .with_cull_box(*MONOLITH_CULL))
    return fx


# ---------------------------------------------------------------------------
# 2b. eclipse:beat_flyover_shadow — Expansion FLYOVER ground shadow run
# ---------------------------------------------------------------------------
# ferry_wave_crest build: burst on the launch tick, then a World-space march along
# local -Z. The Java leg points -Z radially OUTWARD from the growth front, so the
# shadow band races the same direction the border is growing — the front made kinetic.
SHADOW_SPEED_BPS = 10.0        # 0.5 b/t; x 88t life = the 44-block run
SHADOW_LIFE = 88
SHADOW_CULL = ((-11.0, -3.0, -50.0), (11.0, 8.0, 6.0))


def build_beat_flyover_shadow() -> FxBuilder:
    fx = FxBuilder("beat_flyover_shadow")

    # The band itself: a lane of dark soft quads hugging the ground, launched together
    # so they stay a FRONT (three staggered bursts thicken it without smearing it).
    (fx.particle_emitter(
            "shadow_band",
            duration=110, looping=False,
            start_lifetime=random_between(SHADOW_LIFE - 6, SHADOW_LIFE + 2),
            start_speed=random_between(SHADOW_SPEED_BPS - 0.5, SHADOW_SPEED_BPS + 0.5),
            start_size=rand_size3(1.6, 2.8),
            simulation_space="World", max_particles=40)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(18)),
                               burst(time=3, count=constant(12)),
                               burst(time=7, count=constant(8))])
        .with_shape(function_shape(x="(randomA-0.5)*16.0", y="0.4+randomB*1.0",
                                   speed_z="-1"))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 1.2, "NearFade": 0.7},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_curves(
            size_over_lifetime=curve(0.6, 1.2, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.14, 0.5), (0.8, 0.32), (1.0, 0.0)],
                [(0.0, 0.10, 0.10, 0.16), (1.0, 0.06, 0.06, 0.11)],
                [(0.0, 0.13, 0.12, 0.20), (1.0, 0.08, 0.07, 0.14)]))
        .with_cull_box(*SHADOW_CULL))

    # Dust wake kicked up behind the front — cycles of small cone kicks re-fired down
    # the run so the band leaves a settling trace instead of sliding sterile.
    (fx.particle_emitter(
            "shadow_dust",
            duration=110, looping=False, start_lifetime=random_between(18, 30),
            start_speed=random_between(SHADOW_SPEED_BPS - 1.0, SHADOW_SPEED_BPS + 1.0),
            start_size=rand_size3(0.5, 0.9),
            simulation_space="World", max_particles=30)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=4, count=constant(6), cycles=5, interval=16)])
        .with_shape(function_shape(x="(randomA-0.5)*13.0", y="0.3+randomB*0.7",
                                   speed_z="-1"))
        .with_curves(
            velocity_over_lifetime=dict(
                speed_modifier=curve(1.0, 0.25, [SEG_SMOOTH_DOWN], "lifetime"),
                linear=nf3(constant(0), random_between(0.3, 0.9), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.34), (0.75, 0.22), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *SAC_VOID)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.9, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*SHADOW_CULL))

    # Sparse violet rim glints riding the leading edge — the only emissive pass, so
    # the shadow stays a shadow but its edge belongs to the expansion palette.
    (fx.particle_emitter(
            "shadow_glints",
            duration=110, looping=False, start_lifetime=random_between(20, 34),
            start_speed=random_between(SHADOW_SPEED_BPS, SHADOW_SPEED_BPS + 2.0),
            start_size=rand_size3(0.08, 0.16),
            simulation_space="World", max_particles=16)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(5), cycles=3, interval=24)])
        .with_shape(function_shape(x="(randomA-0.5)*15.0", y="0.5+randomB*0.9",
                                   speed_z="-1"))
        .with_module("colorBySpeed", color_by_speed(SAC_VOID, VIOLET_HOT, 4.0, 12.0))
        .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.2, 0.9), (0.7, 0.45), (1.0, 0.0)],
            [(0.0, *VIOLET_MID), (1.0, *SAC_VOID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.9, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.2,
                       length_scale=2.2, vertex_sorting="NONE")
        .with_lights(sky=15, block=15)
        .with_cull_box(*SHADOW_CULL))
    return fx


# ---------------------------------------------------------------------------
# 3. eclipse:beat_nether_ember_tear — Nether AFTERMATH "first ember tear"
# ---------------------------------------------------------------------------
# The crack GROWS because birth stays at the origin while speed varies 1.6-3.2 b/s and
# decays: slow embers pile up near the rim, fast ones crawl out to ~12 blocks before
# their speed dies — the visible line lengthens over the 90t birth window without any
# emitter motion. Local -Z; the Java hook rolls a crawl yaw away from the crater.
EMBER_CULL = ((-4.0, -2.0, -16.0), (4.0, 5.0, 3.0))


def build_beat_nether_ember_tear() -> FxBuilder:
    fx = FxBuilder("beat_nether_ember_tear")

    # The molten seam. Births taper off after ~60% of the 140t (the crack "seals"),
    # long dim tails keep the cooled line readable to the end.
    (fx.particle_emitter(
            "tear_crawl",
            duration=140, looping=False, start_lifetime=random_between(60, 110),
            start_speed=random_between(1.6, 3.2),
            start_size=rand_size3(0.10, 0.22),
            simulation_space="World", max_particles=64)
        .with_emission(rate=curve(
            0.0, 0.7,
            [(0.0, 0.9, 0.2, 1.0, 0.45, 0.85, 0.62, 0.0),
             (0.62, 0.0, 0.75, 0.0, 0.9, 0.0, 1.0, 0.0)], "duration", "rate"))
        .with_shape(cone(angle=7.0, radius=0.18))
        .rotated(-90.0, 0.0, 0.0)  # cone fires +Y by default; pitch it onto -Z
        .at(0.0, 0.15, 0.0)
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.12, [SEG_DECAY_TAIL], "lifetime")),
            noise=dict(frequency=0.8, position=nf3(0.015, 0.0, 0.015)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 1.0), (0.55, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.86, 0.5), (0.35, *EMBER_HOT), (1.0, *EMBER_DEEP)],
                [(0.0, 1.0, 0.74, 0.36), (0.4, 0.9, 0.42, 0.12), (1.0, 0.3, 0.08, 0.03)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 0.9, 0.4)))
        .with_lights(sky=15, block=15)
        .with_cull_box(*EMBER_CULL))

    # The tear head: a handful of bigger, brighter blobs at the fast end of the speed
    # roll — they ARE the creeping tip the eye follows.
    (fx.particle_emitter(
            "tear_head",
            duration=140, looping=False, start_lifetime=random_between(70, 100),
            start_speed=random_between(2.8, 3.4),
            start_size=rand_size3(0.3, 0.45),
            simulation_space="World", max_particles=6)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=2, count=constant(2)),
                               burst(time=30, count=constant(2)),
                               burst(time=60, count=constant(2))])
        .with_shape(cone(angle=4.0, radius=0.1))
        .rotated(-90.0, 0.0, 0.0)
        .at(0.0, 0.2, 0.0)
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.15, [SEG_DECAY_TAIL], "lifetime")),
            size_over_lifetime=curve(0.8, 1.15, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.08, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 1.0, 0.9, 0.6), (0.4, *EMBER_HOT), (1.0, *EMBER_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.0, 0.45)))
        .with_lights(sky=15, block=15)
        .with_cull_box(*EMBER_CULL))

    # Thin fumaroles rising where the crack has already passed — the rate ramps IN as
    # the seam lengthens (there is nothing to smoke over before the tear exists).
    (fx.particle_emitter(
            "tear_fumaroles",
            duration=140, looping=False, start_lifetime=random_between(30, 55),
            start_speed=constant(0),
            start_size=rand_size3(0.3, 0.6),
            simulation_space="World", max_particles=20)
        .with_emission(rate=curve(0.0, 0.24, [SEG_SMOOTH_UP], "duration", "rate"))
        .with_shape(function_shape(x="(randomB-0.5)*0.7", y="0.2",
                                   z="0-randomA*11.0"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.5, 1.2), constant(0))),
            noise=dict(frequency=0.6, position=nf3(0.04)),
            size_over_lifetime=curve(0.5, 1.5, [SEG_SMOOTH_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.3), (0.75, 0.18), (1.0, 0.0)],
                [(0.0, 0.30, 0.16, 0.10), (1.0, 0.14, 0.10, 0.10)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.8, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*EMBER_CULL))

    # t=30 aftershock: one dark dust ring shoved outward from the origin — the server
    # doubles this exact tick with a 0.45-strength RUMBLE broadcast (report §1 row 3).
    (fx.particle_emitter(
            "tear_aftershock",
            duration=140, looping=False, start_lifetime=random_between(22, 32),
            start_speed=constant(0),
            start_size=rand_size3(0.5, 0.9),
            simulation_space="Local", max_particles=26)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=30, count=constant(24))])
        .with_shape(circle(radius=1.4, thickness=0.1, arc_mode="BurstSpread"))
        .at(0.0, 0.4, 0.0)
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(26.0, 5.0, [SEG_SMOOTH_DOWN], "lifetime", "value"),
                linear=nf3(constant(0), random_between(0.2, 0.6), constant(0))),
            size_over_lifetime=curve(0.6, 1.6, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.7, 0.28), (1.0, 0.0)],
                [(0.0, 0.36, 0.22, 0.14), (1.0, 0.16, 0.11, 0.10)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.9, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(*EMBER_CULL))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:beat_finale_keyglyphs — Ferryman finale UNLOCK key-photon
# ---------------------------------------------------------------------------
# Circle shapes lie in XZ; rotated(90,0,0) stands the ring up into the gate plane
# (normal = local Z). The Java leg is the house yaw leg (180 deg - gateYaw), the same
# convention as wisp_gush / ferry_wave_crest, so "gate plane" is authored once here.
KEYGLYPH_CULL = ((-6.0, -5.0, -6.0), (6.0, 6.0, 6.0))
SNAP_TICKS = (8, 22, 36)  # server clicks sit on these; BREACH_AT_TICK 50 stays free


def build_beat_finale_keyglyphs() -> FxBuilder:
    fx = FxBuilder("beat_finale_keyglyphs")

    # Three click-beats x 18 beard-glyphs. Born just OUTSIDE the rest ring, radial
    # -40 (0.4 b/t) that ARRESTS within ~3 ticks (the curve floors to 0) = the snap;
    # the long tail of the 14-18t life is the glyph HOLDING its seat, so each click
    # visibly densifies the lock ring.
    (fx.particle_emitter(
            "glyph_rings",
            duration=60, looping=False, start_lifetime=random_between(14, 18),
            start_speed=constant(0),
            start_size=rand_size3(0.16, 0.3),
            simulation_space="Local", max_particles=54)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=SNAP_TICKS[0], count=constant(18)),
                               burst(time=SNAP_TICKS[1], count=constant(18)),
                               burst(time=SNAP_TICKS[2], count=constant(18))])
        .with_shape(circle(radius=3.1, thickness=0.06, arc_mode="BurstSpread"))
        .rotated(90.0, 0.0, 0.0)  # stand the ring up into the gate plane
        .with_curves(
            velocity_over_lifetime=dict(radial=curve(
                -40.0, 0.0, [(0.0, 0.0, 0.06, 0.7, 0.16, 1.0, 1.0, 1.0)],
                "lifetime", "value")),
            rotation_over_lifetime=random_between(-4.0, 4.0),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 1.0), (0.3, 0.7), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 0.8), (0.3, *GOLD), (1.0, 0.72, 0.55, 0.3)],
                [(0.0, 1.0, 0.9, 0.7), (0.35, 0.9, 0.72, 0.4), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.45, 1.25, 0.75)))
        .with_lights(sky=15, block=15)
        .with_cull_box(*KEYGLYPH_CULL))

    # After the third click the veil INHALES: motes born on a shell around the gate
    # center race inward (radial -30 -> -50) — the portal drawing breath before the
    # t=50 breach the server owns. Tight lifetimes: the inhale must be DONE when the
    # wisp_gush exhale takes the doorway (only the last stragglers overlap it).
    (fx.particle_emitter(
            "veil_indraw",
            duration=60, looping=False, start_lifetime=random_between(8, 12),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            simulation_space="Local", max_particles=40)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=36, count=constant(12), cycles=3, interval=5)])
        .with_shape(sphere(radius=3.4, thickness=0.15))
        .with_module("colorBySpeed", color_by_speed(SAC_VOID, VIOLET_HOT, 3.0, 11.0))
        .with_curves(
            velocity_over_lifetime=dict(radial=curve(
                -30.0, -50.0, [SEG_SMOOTH_UP], "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.95), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, *VIOLET_HOT)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 1.0, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.0,
                       length_scale=2.2, vertex_sorting="NONE")
        .with_lights(sky=15, block=15)
        .with_cull_box(*KEYGLYPH_CULL))

    # The third click's ring flash: two stacked pops at the gate center — the "unlocked"
    # exclamation mark right before the indraw starts. Deliberately a camera-facing
    # billboard: render modes ignore the executor rotation, so a Horizontal quad would
    # lie flat on the deck instead of standing in the gate.
    (fx.particle_emitter(
            "ring_flash",
            duration=60, looping=False, start_lifetime=constant(12),
            start_speed=constant(0), start_size=nf3(2.4, 2.4, 2.4),
            simulation_space="Local", max_particles=2)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=SNAP_TICKS[2], count=constant(2))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(0.4, 1.8, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.8), (0.35, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.97, 0.85), (1.0, *GOLD)]))
        .with_material(texture_material(RING_SOFT, hdr=hdr(1.45, 1.3, 0.8)))
        .with_lights(sky=15, block=15)
        .with_cull_box(*KEYGLYPH_CULL))
    return fx


# ---------------------------------------------------------------------------
# 5. eclipse:beat_credits_afterglow — Credits WHITEOUT -> BEACH afterglow bridge
# ---------------------------------------------------------------------------
# 200t = the full 10 s bridge. The crossfade is in the RATE curve: ~40t ease-in out
# of the whiteout, a long hold, release from t~140 so the last 55-75t motes die with
# the window. NO hdr anywhere and the palette stays within two grays: this beat is
# the quietest thing in the whole mod and must never bloom against the beach sky.
AFTERGLOW_CULL = ((-17.0, -11.0, -14.0), (17.0, 4.0, 14.0))


def build_beat_credits_afterglow() -> FxBuilder:
    fx = FxBuilder("beat_credits_afterglow")

    # White ash motes over the 30x24 surf field (anchor sits 9 blocks up — they sink
    # 2.2-3.2 b/s, so a mote crosses most of the drop in its life and fades before
    # the sand). shade=True lets the beach dawn actually light them.
    (fx.particle_emitter(
            "afterglow_ash",
            duration=200, looping=False, start_lifetime=random_between(55, 75),
            start_speed=constant(0),
            start_size=rand_size3(0.07, 0.15),
            simulation_space="Local", max_particles=90)
        .with_emission(rate=curve(
            0.0, 0.62,
            [(0.0, 0.0, 0.07, 0.6, 0.14, 1.0, 0.2, 1.0),
             (0.2, 1.0, 0.4, 1.0, 0.55, 1.0, 0.7, 1.0),
             (0.7, 1.0, 0.78, 0.85, 0.9, 0.25, 1.0, 0.0)], "duration", "rate"))
        .with_shape(function_shape(x="(randomA-0.5)*30.0", y="randomC*3.0",
                                   z="(randomB-0.5)*24.0"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-0.3, 0.3), random_between(-3.2, -2.2),
                           random_between(-0.3, 0.3))),
            noise=dict(frequency=0.4, position=nf3(0.03, 0.008, 0.03)),
            rotation_over_lifetime=random_between(-2.0, 2.0),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.6), (0.75, 0.42), (1.0, 0.0)],
                [(0.0, *ASH_WHITE), (1.0, *ASH_DIM)],
                [(0.0, 0.88, 0.90, 0.94), (1.0, 0.55, 0.57, 0.64)]))
        .with_material(texture_material(CIRCLE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(*AFTERGLOW_CULL))

    # A few slow glints inside the fall — the "afterglow" of the whiteout cooling in
    # the air. Additive but textureless-white and rare, still no hdr.
    (fx.particle_emitter(
            "afterglow_glints",
            duration=200, looping=False, start_lifetime=random_between(40, 60),
            start_speed=constant(0),
            start_size=rand_size3(0.05, 0.1),
            simulation_space="Local", max_particles=12)
        .with_emission(rate=curve(
            0.0, 0.08,
            [(0.0, 0.0, 0.1, 0.7, 0.2, 1.0, 0.65, 1.0),
             (0.65, 1.0, 0.75, 0.7, 0.9, 0.2, 1.0, 0.0)], "duration", "rate"))
        .with_shape(function_shape(x="(randomA-0.5)*26.0", y="randomC*2.5",
                                   z="(randomB-0.5)*20.0"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-2.6, -1.8), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.7), (0.7, 0.35), (1.0, 0.0)],
                [(0.0, 1.0, 0.99, 0.94), (1.0, *ASH_WHITE)]))
        .with_material(texture_material(CIRCLE_TEX))
        .with_lights(sky=15, block=13)
        .with_cull_box(*AFTERGLOW_CULL))
    return fx


BUILDERS = {
    "beat_intro_windshear.fx": build_beat_intro_windshear,
    "beat_monolith_pulse.fx": build_beat_monolith_pulse,
    "beat_flyover_shadow.fx": build_beat_flyover_shadow,
    "beat_nether_ember_tear.fx": build_beat_nether_ember_tear,
    "beat_finale_keyglyphs.fx": build_beat_finale_keyglyphs,
    "beat_credits_afterglow.fx": build_beat_credits_afterglow,
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
