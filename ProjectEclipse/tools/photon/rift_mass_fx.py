#!/usr/bin/env python3
"""RIFT-MASS (F-102 team B) — authors the day-rift Photon assets with fxlib.

Supersedes the two day_rift builders that lived in `tools/photon/ferryman2_fx.py`
(surgically removed there; every other ferryman2 asset stays in that generator).
User brief: "Die Rifts sehen nicht heftig und nicht groß genug aus und die müssen
auch so volumetrisch 3d sein statt nur so Scheiben. Ich will Sachen mit Masse und
Tiefe damit man denkt oha was ist das denn."

  eclipse:day_rift_maw        F-044 dawn rift over the center island. v3 "SCHLUND":
                              the FX-W11/W13 maw (sluggish mouth vortex + bell-curtain
                              underhang + real 72-block mote rain + rim rgb tears) is
                              KEPT and built on — what changes is that the flat mouth
                              disc becomes a deep multi-shell THROAT:
                                * mouth widened 4.5 -> 7.0 blocks radius ("nicht groß
                                  genug"),
                                * three ring shells STACKED UP INTO the rift at +2.6 /
                                  +5.2 / +7.8 blocks with shrinking radius, sinking
                                  brightness and per-shell counter-rotation — from the
                                  island 72 blocks below they read as concentric rings
                                  receding into a funnel (overlap + size + brightness
                                  staffelung = depth in ONE still frame),
                                * a near-black smoke CORE plugging the far end of the
                                  shaft (the dark Schlund behind the bright Saum),
                                * an emissive RIM RING on the mouth edge — the one hot
                                  element the eye measures the dark depth against,
                                * heartbeat pulses now RISE up the shaft while
                                  shrinking (perspective read: the pulse travels away
                                  from the viewer, into the depth),
                                * every structural emitter fires an opening burst at
                                  t=0, so the maw is readable from FRAME 1 (the CullBox/
                                  Prewarm doctrine applied to one-shots: bursts, since
                                  prewarm only exists for loops).
  eclipse:day_rift_dust_puff  W13 FirstCollision child of the maw's rain — carried over
                              1:1 from ferryman2_fx (budget-frozen at the LINT-SUBEM-FAT
                              line: 6 burst particles, deep-copied per stamp).

House laws honored: V2.1 stacking (dark birth tints on every alpha pass, HDR clamped
to 1.45 via hdr()), speed units are BLOCKS PER SECOND (ferryman2 header note §1),
alpha passes sort DISTANCE, collision emitters keep parallelUpdate OFF.

Usage:  python3 tools/photon/rift_mass_fx.py            # write + validate both
Round-trip validation is fxlib's default; the CLI `validate --lint` re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, burst, circle, cone,
    constant, curve, dot, function_shape, gradient, material_shader, nf3,
    random_between, random_gradient, sub_emitter, texture_material,
    validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"

# Finale palette (ferryman2 lineage): near-black violet body, #9C7BE0 mid, #D0B3FF hot.
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
# FX-STYLE-GUIDE §1 dark stacking bases.
SAC_VOID = (0.180, 0.137, 0.278)     # #2E2347
STM_SLATE = (0.227, 0.227, 0.333)    # #3A3A55

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45

#: colorBySpeed cool end (module MULTIPLIES lifetime color; hot end stays near white).
COOL_SOUL = (0.52, 0.40, 0.78)
HOT_WHITE = (1.0, 1.0, 1.0)


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
    """`colorBySpeed` module body (LDLib2 Range codec fields are a/b — ferryman2 note)."""
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — authored ramp plus a sibling ramp inside the same palette."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


#: Noise remap (ferryman2 GUST_REMAP): squash the calm middle of the Perlin band so the
#: smoke reads as GUSTS instead of an even shimmer.
GUST_REMAP = curve(-1.0, 1.0, [(0.0, 0.0, 0.34, 0.06, 0.68, 0.94, 1.0, 1.0)],
                   "base noise", "remap result")


# ---------------------------------------------------------------------------
# 1. eclipse:day_rift_dust_puff — W13 FirstCollision child of the maw's rain
# ---------------------------------------------------------------------------
# Carried over unchanged from ferryman2_fx (see module doc). Kept deliberately at the
# LINT-SUBEM-FAT budget (6 burst particles total): the maw rains for ~28 s, so this file
# is deep-copied into a fresh runtime a few times a second. NO hdr anywhere — a dust
# kick is dust, and it must never bloom under the rift's glow.
def build_day_rift_dust_puff() -> FxBuilder:
    fx = FxBuilder("day_rift_dust_puff")
    cull = ((-3.5, -1.5, -3.5), (3.5, 3.5, 3.5))

    # The stamp itself: one flat slate ring blooming across whatever the mote hit.
    (fx.particle_emitter(
            "kick_ring",
            duration=16, looping=False, max_particles=2,
            start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(0.7, 0.7, 0.7), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(RING_SOFT, blend=BLEND_ALPHA))
        .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE")
        .with_cull_box(*cull)
        .with_curves(
            size_over_lifetime=curve(0.3, 2.6, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.4), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *SAC_VOID)])))

    # Five grit flicks off the contact point. No collision module: the mote that spawned
    # this already resolved the surface, so these only need gravity to fold back down.
    (fx.particle_emitter(
            "kick_grit",
            duration=16, looping=False, max_particles=8,
            start_lifetime=random_between(9, 17), start_speed=random_between(2.4, 5.0),
            start_size=rand_size3(0.04, 0.09), simulation_space="World")
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
        .with_shape(cone(angle=64.0, radius=0.12))
        .with_material(texture_material(CIRCLE_TEX, blend=BLEND_ALPHA))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.35,
                       length_scale=1.4, vertex_sorting="DISTANCE")
        .with_physics(collision=False, gravity=0.55, bounce_chance=0.0)
        .with_cull_box(*cull)
        .with_curves(
            size_over_lifetime=curve(0.45, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.7), (0.7, 0.4), (1.0, 0.0)],
                [(0.0, *STM_SLATE), (1.0, *SAC_VOID)],
                [(0.0, 0.30, 0.22, 0.42), (1.0, 0.12, 0.07, 0.19)])))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:day_rift_maw — F-044, v3 "Schlund" (deep multi-shell throat)
# ---------------------------------------------------------------------------
#: Mouth radius (was 4.5 pre-F-102 — "nicht groß genug").
MOUTH_R = 7.0
#: Underhang bell geometry (FX-W11 lineage, deepened/widened with the mouth): the
#: curtain sags UNDERHANG_DEPTH blocks below the rift plane and widens from
#: UNDERHANG_R0 to UNDERHANG_R0 + UNDERHANG_R_GROWTH on the way down (one randomC
#: drives both, so depth and radius stay coupled = a bell, not a tube).
UNDERHANG_DEPTH = 14.0
UNDERHANG_R0 = 6.5
UNDERHANG_R_GROWTH = 5.0
#: Throat shells: (y up into the rift, ring radius, orbital deg-analog rate, alpha
#: peak, body tint). Radius shrinks and brightness sinks with depth — the funnel;
#: alternating orbital sign = counter-rotation parallax between the strata. The rate
#: also SLOWS with depth (the FX-W11 "schwere Platten tief + langsam" stratification,
#: mapped onto the shaft: deep = ponderous).
THROAT_SHELLS = (
    ("throat_low",  2.6, 5.6,  0.16, 0.46, (0.150, 0.095, 0.230)),
    ("throat_mid",  5.2, 4.0, -0.11, 0.40, (0.110, 0.070, 0.175)),
    ("throat_high", 7.8, 2.7,  0.07, 0.34, (0.080, 0.050, 0.130)),
)
#: One shared cull envelope for the maw BODY — clears the deepened bell sag below AND
#: the throat/core column above, else the shaft pops the moment the camera swings
#: under or beside the rift.
MAW_CULL_MIN = (-16.0, -22.0, -16.0)
MAW_CULL_MAX = (16.0, 13.0, 16.0)
#: The rain keeps its own (much taller) envelope: DayRiftOrbits.RIFT_ABOVE_TOP puts the
#: maw 72 blocks over the island top, and the motes really cover that drop.
RAIN_DROP = 72.0
RAIN_CULL_MIN = (-18.0, -(RAIN_DROP + 24.0), -18.0)
RAIN_CULL_MAX = (18.0, 10.0, 18.0)


def _soft_smoke(soft_distance):
    """The house soft_particle smoke material (A0): falling DayRiftOrbits block-displays
    slice THROUGH the smoke instead of cutting a hard silhouette line into it."""
    return material_shader(
        "eclipse:soft_particle",
        textures={"MainTexture": SMOKE_TEX},
        uniforms={"SoftDistance": soft_distance, "NearFade": 0.8},
        blend=BLEND_ALPHA)


def build_day_rift_maw() -> FxBuilder:
    fx = FxBuilder("day_rift_maw")
    root = fx.empty("maw_root")

    # Mouth vortex — the rift's body at the tear plane. Sluggish near-black smoke,
    # alpha-blended (dark, not additive) so it reads as a WOUND in the sky. Widened to
    # the new mouth radius; the t=0 burst makes the mouth exist on frame 1 instead of
    # fading in over the first two seconds of a 30 s window.
    (fx.particle_emitter(
            "maw_smoke",
            duration=560, looping=False, start_lifetime=random_between(70, 110),
            start_speed=constant(0.4),
            start_size=rand_size3(1.8, 3.6),
            simulation_space="Local", max_particles=80)
        .child_of(root)
        .with_emission(rate=constant(0.7),
                       bursts=[burst(time=0, count=constant(24))])
        .with_shape(circle(radius=MOUTH_R, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.22), constant(0)),  # SLUGGISH swirl
                # Iteration 2: −1.6 b/s over the ~4.5 s life dragged every sprite all
                # the way to the axis, congesting the very zone the dark throat_core
                # must read through from the island below. −1.1 dies at ~radius 2:
                # converging vortex kept, center kept open for the core.
                radial=constant(-1.1)),
            noise=dict(frequency=0.16, position=nf3(0.06), remap_curve=GUST_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.55), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, 0.16, 0.09, 0.22), (1.0, 0.08, 0.04, 0.13)]))
        .with_material(_soft_smoke(2.2))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Underhang bell (FX-W11, KEPT and deepened): a widening curtain sagging BELOW the
    # rift, turning at ~half the body's orbital rate — the LAG is the point: the
    # underside drags behind the mouth, so the maw reads as a heavy hanging mass.
    # Alpha ceiling 0.30: it darkens the sky under the rift, nothing more.
    (fx.particle_emitter(
            "maw_underhang",
            duration=560, looping=False, start_lifetime=random_between(80, 120),
            start_speed=constant(0),
            start_size=rand_size3(2.2, 3.8),
            simulation_space="Local", max_particles=66)
        .child_of(root)
        .with_emission(rate=constant(0.55),
                       bursts=[burst(time=0, count=constant(14))])
        .with_shape(function_shape(
            x=f"cos(randomA*2*PI)*({UNDERHANG_R0}+randomC*{UNDERHANG_R_GROWTH})",
            y=f"-(randomC*{UNDERHANG_DEPTH})",
            z=f"sin(randomA*2*PI)*({UNDERHANG_R0}+randomC*{UNDERHANG_R_GROWTH})"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.5, -0.25), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.1), constant(0))),  # HALF the body
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.3), (0.8, 0.22), (1.0, 0.0)],
                [(0.0, 0.1, 0.08, 0.16), (1.0, 0.05, 0.04, 0.09)]),
            size_over_lifetime=curve(
                0.8, 1.4, [(0.0, 0.0, 0.25, 0.45, 0.6, 0.92, 1.0, 1.0)]))
        .with_material(_soft_smoke(2.6))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # v3 — THE THROAT: three ring shells stacked up INTO the rift. Viewed from the
    # island below they nest as concentric rings shrinking toward the dark core —
    # overlap + size staffelung + brightness staffelung, the three still-frame depth
    # cues at once. Viewed from the side they stack into a chimney over the bell.
    # Real world-position staggering (emitter .at offsets), so any camera drift adds
    # true parallax between the strata; alternating orbital signs add it even for a
    # fixed camera. All alpha smoke with DARK birth tints (V2.1 stacking law).
    for name, y_off, radius, orbital_rate, alpha_peak, body in THROAT_SHELLS:
        (fx.particle_emitter(
                name,
                duration=560, looping=False, start_lifetime=random_between(70, 105),
                start_speed=constant(0),
                start_size=rand_size3(1.2, 2.3),
                simulation_space="Local", max_particles=24)
            .child_of(root)
            .at(0.0, y_off, 0.0)
            .with_emission(rate=constant(0.2),
                           bursts=[burst(time=0, count=constant(9))])
            .with_shape(circle(radius=radius, thickness=0.3))
            .with_curves(
                velocity_over_lifetime=dict(
                    orbital_mode="AngularVelocity",
                    orbital=nf3(constant(0), constant(orbital_rate), constant(0)),
                    radial=constant(-0.5)),
                noise=dict(frequency=0.2, position=nf3(0.04), remap_curve=GUST_REMAP),
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.25, alpha_peak), (0.75, alpha_peak * 0.72), (1.0, 0.0)],
                    [(0.0, *body), (1.0, body[0] * 0.55, body[1] * 0.55, body[2] * 0.55)]))
            .with_material(_soft_smoke(1.8))
            .with_renderer(vertex_sorting="DISTANCE")
            .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # v3 — THE CORE: a near-black smoke plug at the far end of the shaft. This is the
    # "dunkler Schlund-Kern hinter hellem Saum": whatever sky/cloud sits behind the
    # rift, the shaft visibly ends in MASS, not in daylight. Few, huge, almost-black
    # sprites; alpha 0.55 peak is the darkest thing in the whole asset by design.
    (fx.particle_emitter(
            "throat_core",
            duration=560, looping=False, start_lifetime=random_between(100, 140),
            start_speed=constant(0),
            start_size=rand_size3(3.2, 4.6),
            simulation_space="Local", max_particles=10)
        .child_of(root)
        .at(0.0, 8.2, 0.0)
        .with_emission(rate=constant(0.06),
                       bursts=[burst(time=0, count=constant(4))])
        .with_shape(function_shape(
            x="cos(randomA*2*PI)*(randomB*1.6)",
            y="randomC*1.8",
            z="sin(randomA*2*PI)*(randomB*1.6)"))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.45), (1.0, 0.0)],
                [(0.0, 0.05, 0.03, 0.09), (1.0, 0.03, 0.02, 0.06)]))
        .with_material(_soft_smoke(2.0))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # v3 — THE RIM: an emissive violet ring of small hot sprites crawling the mouth
    # edge. The ONE bright element (HDR clamped to the 1.45 stacking ceiling): the eye
    # measures the dark throat against this ring, which is what makes the depth read
    # in a single frame. Slow orbital crawl matches the maw's sluggish tempo.
    (fx.particle_emitter(
            "mouth_rim",
            duration=560, looping=False, start_lifetime=random_between(20, 34),
            start_speed=constant(0),
            start_size=rand_size3(0.10, 0.22),
            simulation_space="Local", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(1.2),
                       bursts=[burst(time=0, count=constant(22))])
        .with_shape(circle(radius=MOUTH_R + 0.2, thickness=0.12))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.3), constant(0))),
            size_over_lifetime=curve(0.5, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, *VIOLET_HOT), (1.0, *VIOLET_MID)],
                [(0.0, 0.7, 0.58, 0.95), (1.0, 0.45, 0.32, 0.7)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.85, 1.45)))
        .with_lights(sky=15, block=15)
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Heartbeat pulses, re-aimed (v3): the violet bloom now RISES up the shaft while
    # shrinking — the pulse visibly travels AWAY from the viewer below, into the depth
    # (the perspective cue on top of the static staffelung). Cadence unchanged (~2.5 s).
    (fx.particle_emitter(
            "maw_pulse",
            duration=560, looping=False, start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(3.4), max_particles=14)
        .child_of(root)
        .at(0.0, 0.5, 0.0)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=10, count=constant(1), cycles=11, interval=50)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.9, 0.6, 1.5)))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(4.5), constant(0))),  # up the shaft
            # Swell fast, then SHRINK while rising: reads as receding into the throat.
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.55, 0.2, 1.0, 0.6, 0.55, 1.0, 0.2)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, 0.35, 0.2, 0.55)]))
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # The rain (W13, KEPT): real 22-34 b/s fall covering the 72 blocks to the island,
    # vanilla collision sweep, FirstCollision -> day_rift_dust_puff stamp. v3: the
    # birth annulus widens with the mouth (1.5-6.0 was 1.0-3.8) so the rain visibly
    # pours out of the WHOLE mouth, not a narrow core. parallelUpdate stays OFF
    # (collision needs level access — FX_FORMAT §3.1 / LINT-GPU-PHYSICS).
    (fx.particle_emitter(
            "maw_drip",
            duration=560, looping=False, start_lifetime=random_between(70, 110),
            start_speed=random_between(22.0, 34.0),
            start_size=rand_size3(0.12, 0.3),
            simulation_space="World", max_particles=48, parallel_update=False)
        .child_of(root)
        .with_emission(rate=constant(0.6))
        .with_shape(function_shape(
            x="cos(randomA*2*PI)*(1.5+randomB*4.5)",
            z="sin(randomA*2*PI)*(1.5+randomB*4.5)",
            speed_y="-1"))
        .with_physics(collision=True, removed_when_collided=True, gravity=0.22,
                      friction=1.0, bounce_chance=0.0)
        .with_sub_emitters(sub_emitter("eclipse:day_rift_dust_puff",
                                       event="FirstCollision", probability=0.3))
        .with_module("colorBySpeed", color_by_speed(COOL_SOUL, HOT_WHITE, 18.0, 46.0))
        .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.9), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.4, 0.25, 0.65)],
                [(0.0, 0.7, 0.58, 0.95), (1.0, 0.3, 0.18, 0.5)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.8, 1.7)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.55,
                       length_scale=2.0, vertex_sorting="NONE")
        .with_cull_box(RAIN_CULL_MIN, RAIN_CULL_MAX))

    # Rim reality tears (W13, KEPT): a handful of tiny rgb-split tears — moved out to
    # the new mouth radius. Still the ONE screen-space accent of the finale package
    # (stacking more would not compose: the sampler is a pre-particle copy).
    (fx.particle_emitter(
            "maw_tear",
            duration=560, looping=False, start_lifetime=random_between(16, 28),
            start_speed=constant(0), start_size=rand_size3(0.8, 1.7),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=40, count=random_between(1, 2),
                                     cycles=10, interval=48)])
        .with_shape(circle(radius=MOUTH_R - 0.3, thickness=0.35))
        .with_material(material_shader(
            "eclipse:rgb_split_distort",
            uniforms={"SplitStrength": 0.0035, "WobbleAmp": 0.003,
                      "WobbleSpeed": 1.0,
                      "TintColor": (*VIOLET_MID, 0.16)},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX)
        .with_curves(
            size_over_lifetime=curve(0.5, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, *VIOLET_HOT)])))
    return fx


# The dust puff leads: it is a sub-emitter target, and LINT-SUBEM-RESOLVE wants the
# child on disk before the maw that references it is linted.
BUILDERS = {
    "day_rift_dust_puff.fx": build_day_rift_dust_puff,
    "day_rift_maw.fx": build_day_rift_maw,
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
