#!/usr/bin/env python3
"""FERRYMAN2 — authors the finale-arc Photon assets (F-044/F-045/F-045b/F-046/F-046b)
with fxlib. FX-WAVE-13 team A3 pass ("Ferryman/Arena/Tagesriss") layered on top:

  eclipse:day_rift_maw        F-044 dawn rift over the center island: DELIBERATELY the
                              anti-thesis of expansion_rift_glow — sluggish, dark,
                              pulsing violet (slow smoke vortex + heartbeat pulses +
                              raining motes), 560t ~ the 30 s rift window. W13: the
                              body/underhang smoke are SOFT particles, the motes now
                              really FALL the 72 blocks onto the island and stamp
                              `day_rift_dust_puff` on FirstCollision, and the mouth rim
                              carries a handful of tiny rgb-split tears.
  eclipse:day_rift_dust_puff  W13 FirstCollision child of the maw's rain: a flat slate
                              dust ring + five grit flicks where a mote lands.
  eclipse:portal_soul_veil    F-045 portal interior: rising soul motes + faint smoke
                              (100t one-shot, re-fired on the sustain cadence — the
                              kneel-corona law). W13: a real `eclipse:fresnel_shell`
                              force field fills the doorway and the view THROUGH the
                              veil wavers (rgb_split ripples).
  eclipse:key_trail           F-045b key flight ribbon: gold-violet ara trail, LOOPING —
                              entity-attached only (shard-trail exemption: Photon
                              auto-destroys the runtime with the key entity)
  eclipse:arena_mist_wall     F-046 arena fog bank segment (140t, re-fired at the four
                              perimeter anchors every 120t while the fight runs). W13:
                              three SOFT-particle parallax curtains at different depths
                              and drift rates over a dark slate base, plus sparse rim
                              glints.
  eclipse:ferry_harvest_ring  F-046b (a) Seelenernte telegraph: a violet floor ring that
                              contracts onto the boss over the 40t warning — W13 makes
                              the contraction REAL (it lands on the 4.5 b strike radius)
                              and adds the soul mist + pull streaks of the yank.
  eclipse:ferry_wave_crest    F-046b (b) Ruderschlag-Welle crest: authored toward LOCAL
                              -Z (the oar-tear rotation law: the Java leg rotates the
                              executor by 180 deg - yaw about Y). W13: the asset now
                              follows the SERVER wall — gather during the 24t stance,
                              then a crest that marches 26 blocks at 0.55 b/t.
  eclipse:wisp_gush           F-045b breach burst: violet wisps + smoke shoved out of
                              the opened gate (authored toward local -Z, same leg)

--------------------------------------------------------------------------------------
FX-WAVE-13 (A3) house notes — the two things that were silently wrong before
--------------------------------------------------------------------------------------
1. SPEED UNITS. Photon's `Function.nextPosVel` normalises the birth direction to 0.05
   and `TileParticle` multiplies by `startSpeed`, and `VelocityOverLifetimeSetting`
   scales `linear` by 0.05 and `radial` by 0.01 per tick (jar-verified with `javap` on
   2.1.5). So: **start_speed / linear are BLOCKS PER SECOND**, and one `radial` unit is
   only 0.2 b/s. Every motion number in this file was authored an order of magnitude
   below the perception floor (the harvest ring "contracted" 0.1 blocks over its whole
   telegraph, the wave crest travelled 1 block); they are retuned here. Same correction
   class as `boss_b_fx.warden_laser_probe` and the A1 wand pass.
2. HDR CEILING. The wave-13 stacking law caps emissive materials at `HDR_CEILING`
   (1.45); several assets here sat at 2.2-2.6 and bleached whatever they stacked with.
   `hdr()` clamps while preserving the channel ratio (= the hue).

A0 custom shaders (`assets/eclipse/shaders/core/`) are consumed through
`fxlib.material_shader`; `soft_particle` needs `MainTexture`, `fresnel_shell` and
`rgb_split_distort` are textureless. All three are alpha-blended, so every pass that
uses them sorts DISTANCE (LINT-ALPHA-NOSORT).

Usage:  python3 tools/photon/ferryman2_fx.py            # write + validate all eight
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, box, burst, circle, cone,
    constant, curve, dot, function_shape, gradient, material_shader, nf3,
    random_between, random_gradient, sphere, sub_emitter, texture_material,
    validate_file,
    SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_FLICKER_COMMIT, SEG_OVERSHOOT_SETTLE,
    SEG_SMOOTH_DOWN)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"

# The finale palette: near-black violet body, #9C7BE0 mid, #D0B3FF hot, gold accents.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
GOLD = (0.98, 0.82, 0.45)
# FX-STYLE-GUIDE §1 dark stacking bases (the wave-13 "dunkle Birth-Tints" law).
SAC_VOID = (0.180, 0.137, 0.278)     # #2E2347
STM_SLATE = (0.227, 0.227, 0.333)    # #3A3A55
SLATE_DEEP = (0.129, 0.133, 0.196)   # half-slate — the deepest curtain body

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4) — many sprites inside one half-block
#: converge to white above this, so every emissive material here is clamped to it.
HDR_CEILING = 1.45

#: colorBySpeed cool ends. The module MULTIPLIES the lifetime color, so the hot end must
#: stay at/near white or fast particles simply go dark.
COOL_SOUL = (0.52, 0.40, 0.78)    # slow = deep violet drag
COOL_WATER = (0.34, 0.44, 0.62)   # slow = dark cold water
HOT_WHITE = (1.0, 1.0, 1.0)
HOT_FOAM = (0.90, 0.97, 1.0)


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
    """`colorBySpeed` module body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/second (|realVelocity| * 20), output MULTIPLIES the lifetime color.
    `speedRange` is an LDLib2 `Range`, whose codec record fields are `a`/`b` — NOT the
    `min`/`max` pair `fxlib._min_max` writes, so this rides `with_module` (fxlib is
    team-A0 property).
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same palette
    identity; each particle rolls its own memoized lerp between the two."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


#: Noise remap for the fog curtains: squash the calm middle of the Perlin band and let
#: only the extremes through — the noise stops reading as an even shimmer and starts
#: reading as GUSTS. Curve input is the raw noise (-1..1), output the remapped value.
GUST_REMAP = curve(-1.0, 1.0, [(0.0, 0.0, 0.34, 0.06, 0.68, 0.94, 1.0, 1.0)],
                   "base noise", "remap result")


# ---------------------------------------------------------------------------
# 1. eclipse:day_rift_dust_puff — W13 FirstCollision child of the maw's rain
# ---------------------------------------------------------------------------
# Kept deliberately at the LINT-SUBEM-FAT budget (6 burst particles total): the maw
# rains for 28 s, so this file is deep-copied into a fresh runtime a few times a second.
# NO hdr anywhere — a dust kick is dust, and it must never bloom under the rift's glow.
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
# 2. eclipse:day_rift_maw — F-044 (slow, dark, pulsing — NOT the structure rift)
# ---------------------------------------------------------------------------
# Underhang bell geometry: the curtain sags UNDERHANG_DEPTH blocks below the rift
# plane and widens from UNDERHANG_R0 to UNDERHANG_R0 + UNDERHANG_R_GROWTH on the way
# down (one randomC drives both, so depth and radius stay coupled = a bell, not a tube).
UNDERHANG_DEPTH = 10.0
UNDERHANG_R0 = 4.5
UNDERHANG_R_GROWTH = 4.0
# One shared cull envelope for the maw BODY — it must clear the bell's sag, else the
# underside pops away the moment the camera swings below the rift.
MAW_CULL_MIN = (-14.0, -28.0, -14.0)
MAW_CULL_MAX = (14.0, 8.0, 14.0)
# The rain gets its own (much taller) envelope: DayRiftOrbits.RIFT_ABOVE_TOP puts the maw
# 72 blocks over the island top, and the motes now really cover that drop.
RAIN_DROP = 72.0
RAIN_CULL_MIN = (-18.0, -(RAIN_DROP + 24.0), -18.0)
RAIN_CULL_MAX = (18.0, 10.0, 18.0)


def build_day_rift_maw() -> FxBuilder:
    fx = FxBuilder("day_rift_maw")
    root = fx.empty("maw_root")

    # Sluggish near-black smoke vortex — the rift's body. Alpha-blended (dark, not
    # additive) so it reads as a WOUND in the sky rather than a glow. W13: soft_particle,
    # so the falling DayRiftOrbits block-displays slice THROUGH the smoke instead of
    # cutting a hard silhouette line into every puff they pass.
    (fx.particle_emitter(
            "maw_smoke",
            duration=560, looping=False, start_lifetime=random_between(70, 110),
            start_speed=constant(0.4),
            start_size=rand_size3(1.6, 3.2),
            simulation_space="Local", max_particles=90)
        .child_of(root)
        .with_emission(rate=constant(0.8))
        .with_shape(circle(radius=4.5, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.22), constant(0)),  # SLUGGISH swirl
                radial=constant(-1.4)),
            noise=dict(frequency=0.16, position=nf3(0.06), remap_curve=GUST_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.55), (0.75, 0.4), (1.0, 0.0)],
                [(0.0, 0.16, 0.09, 0.22), (1.0, 0.08, 0.04, 0.13)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 2.2, "NearFade": 0.8},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Underhang bell: a widening curtain sagging BELOW the rift, turning at ~half the
    # body's orbital rate (0.1 vs 0.22). That LAG is the whole point — the underside
    # drags behind the mouth, so the maw reads as a heavy hanging mass instead of a
    # painted hole. Alpha ceiling 0.30: it darkens the sky under the rift, nothing more.
    (fx.particle_emitter(
            "maw_underhang",
            duration=560, looping=False, start_lifetime=random_between(80, 120),
            start_speed=constant(0),
            start_size=rand_size3(2.0, 3.6),
            simulation_space="Local", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(0.6))
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
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 2.6, "NearFade": 0.8},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # Heartbeat pulses: one soft violet bloom every ~2.5 s — the "pulsierend lila".
    (fx.particle_emitter(
            "maw_pulse",
            duration=560, looping=False, start_lifetime=constant(34),
            start_speed=constant(0), start_size=nf3(3.0), max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=10, count=constant(1), cycles=11, interval=50)])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(0.9, 0.6, 1.5)))
        .with_curves(
            # Swell-and-die bloom: the pulse breathes OUT slowly (trägheit).
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.25, 0.35, 1.0, 0.7, 0.85, 1.0, 0.3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.35, 0.2, 0.55)]))
        .with_cull_box(MAW_CULL_MIN, MAW_CULL_MAX))

    # W13 — the rain, and the whole point of the A3 collision beat. These were authored
    # as `linear y = -0.22 b/s` motes, i.e. ONE block of sink over their entire life:
    # the "drips" never left the mouth. They are now a real fall at 22-34 b/s (1.1-1.7
    # b/t), which clears the RAIN_DROP 72 blocks down to the island inside a 70-110t
    # life, with vanilla `Entity.collideBoundingBox` sweeping the movement vector (no
    # tunnelling at that step size). `removedWhenCollided` + a FirstCollision sub-emitter
    # turns every landing into a `day_rift_dust_puff` stamp — the debris seam finally
    # touches the ground the block-displays are falling onto.
    # parallelUpdate stays OFF: collision needs level access (FX_FORMAT §3.1 /
    # LINT-GPU-PHYSICS), and the emission rate x probability keeps the stamp cadence at
    # ~4/s so the deep-copied child runtimes stay cheap.
    (fx.particle_emitter(
            "maw_drip",
            duration=560, looping=False, start_lifetime=random_between(70, 110),
            start_speed=random_between(22.0, 34.0),
            start_size=rand_size3(0.12, 0.3),
            simulation_space="World", max_particles=48, parallel_update=False)
        .child_of(root)
        .with_emission(rate=constant(0.6))
        .with_shape(function_shape(
            x="cos(randomA*2*PI)*(1.0+randomB*2.8)",
            z="sin(randomA*2*PI)*(1.0+randomB*2.8)",
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

    # W13 — a handful of tiny reality tears on the mouth rim (A0 rgb_split_distort over
    # SamplerSceneColor). Deliberately at the edge of perception: ~1 tear every 2.4 s,
    # under 2 blocks wide, a slow wobble that matches the maw's sluggish tempo. This is
    # the ONE screen-space accent the finale package gets — stacking more of them would
    # not even compose (the sampler is a copy from BEFORE the particle pass).
    (fx.particle_emitter(
            "maw_tear",
            duration=560, looping=False, start_lifetime=random_between(16, 28),
            start_speed=constant(0), start_size=rand_size3(0.8, 1.7),
            simulation_space="Local", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=40, count=random_between(1, 2),
                                     cycles=10, interval=48)])
        .with_shape(circle(radius=4.2, thickness=0.35))
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


# ---------------------------------------------------------------------------
# 3. eclipse:portal_soul_veil — F-045 portal interior (sustain one-shot)
# ---------------------------------------------------------------------------
VEIL_CULL_MIN = (-7.0, -6.0, -5.0)
VEIL_CULL_MAX = (7.0, 13.0, 5.0)


def build_portal_soul_veil() -> FxBuilder:
    fx = FxBuilder("portal_soul_veil")

    # W13 — the veil is now an actual FORCE FIELD, not a flat alpha quad stack: ONE
    # `eclipse:fresnel_shell` impostor, sized 6.8 x 9.6 so the sphere impostor's UV disc
    # stretches into a door-shaped ellipse. The face stays at FaceAlpha (you can see the
    # gate through it), the silhouette carries the HDR rim, and the shader's SceneDepth
    # seam lights the line where the shell cuts the door frame and the deck. Billboard
    # facing on purpose: the shell has to read from every approach angle, and the A0 doc
    # calls the billboard impostor the sanctioned force-field recipe.
    (fx.particle_emitter(
            "veil_field",
            duration=100, looping=False, start_lifetime=constant(96),
            start_speed=constant(0), start_size=nf3(6.8, 9.6, 6.8),
            simulation_space="Local", max_particles=2)
        .at(0.0, 4.4, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_material(material_shader(
            "eclipse:fresnel_shell",
            uniforms={"ShellColor": (0.42, 0.28, 0.68, 0.82),
                      "RimHDRColor": (1.16, 0.87, 1.45, 1.0),
                      "FresnelPower": 2.2, "FaceAlpha": 0.10,
                      "IntersectWidth": 0.45},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(VEIL_CULL_MIN, VEIL_CULL_MAX)
        .with_curves(
            size_over_lifetime=curve(0.55, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.14, 1.0), (0.86, 0.92), (1.0, 0.0)],
                [(0.0, *VIOLET_MID), (1.0, *VIOLET_HOT)])))

    # Rising soul motes inside the door plane (flat box: x = width, y = height).
    # Speed retune: 1.2-2.6 b/s = 0.06-0.13 b/t, so a mote crosses 3-9 of the door's
    # 9 blocks over its life. At the old 0.03-0.09 b/s the souls did not visibly rise.
    (fx.particle_emitter(
            "veil_motes",
            duration=100, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.22),
            simulation_space="Local", max_particles=80)
        .with_emission(rate=constant(1.4))
        .with_shape(box(), scale=(6.5, 9.0, 0.6))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.2, 2.6), constant(0))),
            noise=dict(frequency=0.5, position=nf3(0.03)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.816, 0.702, 1.0)],
                [(0.0, 0.45, 0.34, 0.72), (1.0, 0.72, 0.6, 0.95)]))
        .with_module("colorBySpeed", color_by_speed(COOL_SOUL, HOT_WHITE, 0.8, 3.2))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.4, 1.0, 2.2)))
        .with_lights(sky=15, block=15)
        .with_cull_box(VEIL_CULL_MIN, VEIL_CULL_MAX))

    # Faint wafting smoke sheet behind the motes — the "wabern". W13: soft_particle, so
    # the sheet feathers into the door frame and the deck instead of ending on the
    # frame's edge with a razor line.
    (fx.particle_emitter(
            "veil_smoke",
            duration=100, looping=False, start_lifetime=random_between(55, 85),
            start_speed=constant(0.2),
            start_size=rand_size3(1.2, 2.2),
            simulation_space="Local", max_particles=30)
        .with_emission(rate=constant(0.5))
        .with_shape(box(), scale=(6.0, 8.5, 0.4))
        .with_curves(
            noise=dict(frequency=0.35, position=nf3(0.05), remap_curve=GUST_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.35), (0.8, 0.25), (1.0, 0.0)],
                [(0.0, 0.24, 0.12, 0.36), (1.0, 0.12, 0.06, 0.2)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.9, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(VEIL_CULL_MIN, VEIL_CULL_MAX))

    # W13 — "the view THROUGH the veil wavers": two small rgb_split decals per beat drift
    # up the door plane. Tiny and short by design (the census idea is a SceneColor
    # shimmer, not a glitch effect) and they never stack — the sampler is a pre-particle
    # copy, so overlapping decals cannot compound each other's distortion anyway.
    (fx.particle_emitter(
            "veil_ripple",
            duration=100, looping=False, start_lifetime=random_between(30, 50),
            start_speed=constant(0), start_size=rand_size3(1.1, 2.0),
            simulation_space="Local", max_particles=8)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=6, count=constant(2), cycles=4, interval=22)])
        .with_shape(box(), scale=(5.0, 7.0, 0.3))
        .at(0.0, 3.8, 0.0)
        .with_material(material_shader(
            "eclipse:rgb_split_distort",
            uniforms={"SplitStrength": 0.0035, "WobbleAmp": 0.005,
                      "WobbleSpeed": 0.9,
                      "TintColor": (*VIOLET_HOT, 0.14)},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(VEIL_CULL_MIN, VEIL_CULL_MAX)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.5, 1.1), constant(0))),
            size_over_lifetime=curve(0.6, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.8), (0.75, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, *VIOLET_HOT)])))
    return fx


# ---------------------------------------------------------------------------
# 4. eclipse:key_trail — F-045b key flight ribbon (entity-attached loop)
# ---------------------------------------------------------------------------
def build_key_trail() -> FxBuilder:
    fx = FxBuilder("key_trail")

    # Gold-violet ara ribbon lagging behind the flying key (shard-trail pattern).
    (fx.ara_trail_emitter(
            "key_ribbon",
            duration=100, looping=True,
            space="World", alignment="View",
            thickness=0.45, smoothness=5, corner_roundness=6,
            time=1.1, time_interval=0.05,
            color_over_length=gradient(
                [(0.0, 0.95), (1.0, 0.0)],
                [(0.0, 0.98, 0.82, 0.45), (0.45, 0.816, 0.702, 1.0),
                 (1.0, 0.4, 0.25, 0.65)]),
            thickness_over_length=curve(
                0.0, 1.0, [(0.0, 1.0, 0.3, 0.9, 0.7, 0.35, 1.0, 0.1)]),
            physics=dict(inertia=0.3, velocity_smoothing=0.75, damping=0.72))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(2.2, 1.7, 1.1)))
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))

    # Loose gold sparks shed along the path (World space: they stay behind).
    (fx.particle_emitter(
            "key_sparks",
            duration=20, looping=True, start_lifetime=random_between(14, 26),
            start_speed=constant(0.6),
            start_size=rand_size3(0.05, 0.12),
            simulation_space="World", max_particles=60, parallel_update=True)
        .with_emission(rate=constant(1.2))
        .with_shape(sphere(radius=0.4, thickness=1.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.8, -0.2), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (1.0, 0.0)],
                [(0.0, 0.98, 0.82, 0.45), (1.0, 0.816, 0.702, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.8, 1.4, 0.9)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# 5. eclipse:arena_mist_wall — F-046 fog bank segment (perimeter sustain)
# ---------------------------------------------------------------------------
# W13 A3 — soft-particle consumer number one. The bank used to be ONE flat curtain of
# alpha smoke that sliced a hard line into the deck aprons and the mast pillars; it is
# now three depth-staggered curtains, each on `eclipse:soft_particle` with a SoftDistance
# scaled to its own puff size, each drifting ALONG the wall at a different rate.
#
# Why lateral drift and not an orbital: the four anchors sit at the perimeter midpoints
# (ArenaMorphLayer.mistWall) and only the two long sides get an OUTWARD yaw — the bow and
# stern caps come in yaw-flipped, so any signed local-Z or orbital-about-the-anchor
# authoring would read differently on two of the four segments. Drift along the bank's
# long axis is orientation-agnostic, and with the segments joined into a ring it IS the
# ring turning: three concentric shells at 0.30 / -0.55 / 0.95 b/s, counter-rotating.
# Counts came DOWN (98 steady vs. 110 before) even though a layer was added.
ARENA_CULL_MIN = (-34.0, -9.0, -11.0)
ARENA_CULL_MAX = (34.0, 15.0, 11.0)


def _mist_layer(fx, name, *, y, scale, size_lo, size_hi, life_lo, life_hi,
                max_particles, rate, drift, soft, alpha, body, tail):
    """One parallax curtain of the wall. `drift` is the along-wall speed in b/s (sign =
    turn direction), `soft` the SceneDepth fade distance in blocks (~half the puff)."""
    return (fx.particle_emitter(
            name,
            duration=140, looping=False,
            start_lifetime=random_between(life_lo, life_hi),
            start_speed=constant(0),
            start_size=rand_size3(size_lo, size_hi),
            simulation_space="World", max_particles=max_particles,
            parallel_update=True)
        .at(0.0, y, 0.0)
        .with_emission(rate=constant(rate))
        .with_shape(box(), scale=scale)
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(drift), random_between(-0.12, 0.2), constant(0))),
            noise=dict(frequency=0.22, position=nf3(0.07), remap_curve=GUST_REMAP),
            size_over_lifetime=curve(0.7, 1.15, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.22, alpha), (0.78, alpha * 0.72), (1.0, 0.0)],
                [(0.0, *body), (1.0, *tail)],
                [(0.0, *tail), (1.0, *SAC_VOID)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": soft, "NearFade": 0.7},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box(ARENA_CULL_MIN, ARENA_CULL_MAX))


def build_arena_mist_wall() -> FxBuilder:
    fx = FxBuilder("arena_mist_wall")

    # Shell 1 — the far body: biggest, darkest, slowest. Sits high and deep so it closes
    # the horizon behind everything else.
    _mist_layer(fx, "mist_deep", y=1.1, scale=(50.0, 7.0, 7.5),
                size_lo=3.0, size_hi=5.0, life_lo=110, life_hi=150,
                max_particles=30, rate=0.24, drift=0.30, soft=2.4,
                alpha=0.30, body=SLATE_DEEP, tail=SAC_VOID)
    # Shell 2 — the readable middle, counter-turning against both neighbours.
    _mist_layer(fx, "mist_mid", y=0.1, scale=(46.0, 4.6, 4.6),
                size_lo=2.0, size_hi=3.4, life_lo=90, life_hi=130,
                max_particles=26, rate=0.24, drift=-0.55, soft=1.6,
                alpha=0.34, body=STM_SLATE, tail=SAC_VOID)
    # Shell 3 — low tongues crawling over the apron, fastest, thinnest. Its SoftDistance
    # is the smallest of the three: these puffs LIVE on the deck and would otherwise be
    # the ones showing the clip line.
    _mist_layer(fx, "mist_near", y=-0.9, scale=(43.0, 2.4, 2.2),
                size_lo=1.1, size_hi=2.1, life_lo=70, life_hi=100,
                max_particles=22, rate=0.26, drift=0.95, soft=1.0,
                alpha=0.26, body=STM_SLATE, tail=(0.20, 0.15, 0.30))

    # Sparse violet rim glints riding the fog crest — the ONLY emissive pass on the wall,
    # deliberately thin (steady ~11 particles/segment) and clamped to the 1.45 ceiling so
    # four segments of them never add up to a bright band around the arena.
    (fx.particle_emitter(
            "mist_glints",
            duration=140, looping=False, start_lifetime=random_between(45, 75),
            start_speed=constant(0),
            start_size=rand_size3(0.05, 0.12),
            simulation_space="World", max_particles=16, parallel_update=True)
        .with_emission(rate=constant(0.18))
        .with_shape(box(), scale=(44.0, 2.0, 4.0))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(random_between(-0.3, 0.3), random_between(0.4, 1.4),
                           constant(0))),
            size_over_lifetime=curve(0.35, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (1.0, 0.35, 0.2, 0.55)],
                [(0.0, 0.45, 0.35, 0.7), (1.0, 0.24, 0.14, 0.4)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.2, 0.9, 1.8)))
        .with_lights(sky=15, block=15)
        .with_cull_box(ARENA_CULL_MIN, ARENA_CULL_MAX))
    return fx


# ---------------------------------------------------------------------------
# 6. eclipse:ferry_harvest_ring — F-046b (a) Seelenernte telegraph (40t + hit)
# ---------------------------------------------------------------------------
# Java contract (FerrymanSpecialAttacks): HARVEST_TELEGRAPH_TICKS 40 (30 enraged), then
# everyone inside HARVEST_PULL_RADIUS 12 is yanked in and HARVEST_STRIKE_RADIUS 4.5 takes
# the damage. The ring is the FAIRNESS read, so it must land on 4.5 — see the radial
# note below.
HARVEST_CULL_MIN = (-13.0, -3.0, -13.0)
HARVEST_CULL_MAX = (13.0, 6.0, 13.0)


def build_ferry_harvest_ring() -> FxBuilder:
    fx = FxBuilder("ferry_harvest_ring")

    # The contracting warning ring. W13: it actually contracts. `radial` is scaled by
    # 0.01 per tick, so the old constant(-0.26) moved the ring 0.1 BLOCKS over the whole
    # telegraph — the "closing" read never existed. The curve runs -10 -> -22 (0.10 ->
    # 0.22 b/t) over a 38t life, i.e. ~5.4 blocks of travel: born on r=10, arriving at
    # r≈4.6 = the strike radius, accelerating as it closes.
    (fx.particle_emitter(
            "harvest_ring",
            duration=44, looping=False, start_lifetime=constant(38),
            start_speed=constant(0),
            start_size=rand_size3(0.18, 0.3),
            simulation_space="Local", max_particles=72)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(64), cycles=1)])
        .with_shape(circle(radius=10.0, thickness=0.05, arc_mode="BurstSpread"))
        .with_module("colorBySpeed", color_by_speed(COOL_SOUL, HOT_WHITE, 1.8, 4.6))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-10.0, -22.0, [SEG_FLICKER_COMMIT], "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 1.0), (0.85, 0.9), (1.0, 0.0)],
                [(0.0, 0.612, 0.482, 0.878), (0.85, 0.816, 0.702, 1.0),
                 (1.0, 1.0, 1.0, 1.0)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.6, 1.1, 2.4)))
        .with_lights(sky=15, block=15)
        .with_cull_box(HARVEST_CULL_MIN, HARVEST_CULL_MAX))

    # Floor glow disc under the boss — reads even when the ring particles are occluded.
    # NOTE: deliberately NOT a soft_particle. A Horizontal disc lying ON the deck has a
    # scene depth equal to its own, so the SceneDepth fade would erase exactly the pass
    # it is supposed to save. Soft particles are for quads that CROSS geometry.
    (fx.particle_emitter(
            "harvest_glow",
            duration=44, looping=False, start_lifetime=constant(40),
            start_speed=constant(0), start_size=nf3(4.5), max_particles=1)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
        .with_shape(dot())
        .at(0.0, 0.1, 0.0)
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.0, 0.7, 1.6)))
        .with_renderer(render_mode="Horizontal")
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.4, 0.3, 1.0, 0.8, 0.9, 1.0, 0.5)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (1.0, 0.0)],
                [(0.0, 0.45, 0.28, 0.7), (1.0, 0.612, 0.482, 0.878)]))
        .with_cull_box((-8.0, -2.0, -8.0), (8.0, 4.0, 8.0)))

    # W13 — the soul mist the harvest drags off the deck. Dark violet ground haze born
    # out on the pull radius and sucked inward with the ring; soft_particle, because
    # these puffs stand ON the planks and are exactly the ones that used to show the cut.
    (fx.particle_emitter(
            "harvest_soulmist",
            duration=44, looping=False, start_lifetime=random_between(26, 40),
            start_speed=constant(0),
            start_size=rand_size3(1.0, 1.9),
            simulation_space="Local", max_particles=22)
        .with_emission(rate=constant(0.9),
                       bursts=[burst(time=0, count=constant(8), cycles=1)])
        .with_shape(circle(radius=11.0, thickness=0.45))
        .at(0.0, 0.5, 0.0)
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-8.0, -20.0, [SEG_FLICKER_COMMIT], "lifetime", "value"),
                linear=nf3(constant(0), random_between(0.1, 0.5), constant(0))),
            noise=dict(frequency=0.4, position=nf3(0.05), remap_curve=GUST_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (0.8, 0.28), (1.0, 0.0)],
                [(0.0, *SAC_VOID), (1.0, 0.11, 0.06, 0.18)]))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 1.0, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box(HARVEST_CULL_MIN, HARVEST_CULL_MAX))

    # W13 — the yank made visible. The server pulls at HARVEST_STRIKE_DELAY-ish timing,
    # so these streaks fire on the back half of the telegraph and race inward much faster
    # than the ring: souls being ripped off the deck ahead of the players.
    (fx.particle_emitter(
            "harvest_pull",
            duration=44, looping=False, start_lifetime=random_between(14, 22),
            start_speed=constant(0),
            start_size=rand_size3(0.1, 0.2),
            simulation_space="Local", max_particles=30)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=18, count=constant(9), cycles=3, interval=8)])
        .with_shape(circle(radius=11.5, thickness=0.6))
        .at(0.0, 0.8, 0.0)
        .with_module("colorBySpeed", color_by_speed(COOL_SOUL, HOT_WHITE, 3.0, 13.0))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=curve(-26.0, -58.0, [SEG_EASE_OUT_CREST], "lifetime", "value"),
                linear=nf3(constant(0), random_between(0.3, 1.2), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.18, 0.95), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.45, 0.28, 0.7)],
                [(0.0, 0.7, 0.56, 0.95), (1.0, 0.33, 0.2, 0.55)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 0.95, 1.9)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7,
                       length_scale=2.4, vertex_sorting="NONE")
        .with_lights(sky=15, block=15)
        .with_cull_box(HARVEST_CULL_MIN, HARVEST_CULL_MAX))
    return fx


# ---------------------------------------------------------------------------
# 7. eclipse:ferry_wave_crest — F-046b (b) wave crest (aimed via the yaw leg)
# ---------------------------------------------------------------------------
# Java contract (FerrymanSpecialAttacks): the cue fires at the START of the stance, the
# wall LAUNCHES WAVE_TELEGRAPH_TICKS 24 ticks later and then marches WAVE_SPEED 0.55 b/t
# (= 11 b/s) out to WAVE_RANGE 26 blocks, half-width 3. Before W13 the asset was a single
# 30t burst at t=0 with start_speed 0.7-1.1 — read as b/s that is 0.04 b/t, so the whole
# "wave" travelled about one block and expired 20 ticks before the wall even launched.
# The asset now mirrors the server: gather during the stance, launch on tick 24, and the
# crest body flies at the wall's own speed for the wall's own distance.
WAVE_LAUNCH_TICK = 24
WAVE_SPEED_BPS = 11.0          # WAVE_SPEED 0.55 b/t x 20
WAVE_TRAVEL_TICKS = 48         # 26 blocks / 0.55 b/t
WAVE_CULL_MIN = (-9.0, -4.0, -32.0)
WAVE_CULL_MAX = (9.0, 8.0, 5.0)


def build_ferry_wave_crest() -> FxBuilder:
    fx = FxBuilder("ferry_wave_crest")
    duration = WAVE_LAUNCH_TICK + WAVE_TRAVEL_TICKS + 4

    # Stance beat: dark water wells up around the oar and hangs in the lane mouth, so the
    # 24t telegraph has something to look at before the crest exists. soft_particle keeps
    # the gather from cutting into the deck it is welling out of.
    (fx.particle_emitter(
            "crest_gather",
            duration=WAVE_LAUNCH_TICK, looping=False,
            start_lifetime=random_between(20, 34), start_speed=random_between(1.0, 2.4),
            start_size=rand_size3(0.6, 1.2),
            max_particles=24)
        .with_emission(rate=constant(0.8))
        .with_shape(cone(angle=46.0, radius=1.4))
        .rotated(-90.0, 0.0, 0.0)  # cone fires +Y by default; pitch it onto -Z
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.8, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.15, [SEG_SMOOTH_DOWN], "lifetime")),
            size_over_lifetime=curve(0.5, 1.25, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.42), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, 0.16, 0.20, 0.30), (1.0, 0.10, 0.12, 0.20)]))
        .with_cull_box((-6.0, -4.0, -10.0), (6.0, 6.0, 5.0)))

    # W13 — the wall itself: a soft-particle face spanning the WAVE_HALF_WIDTH 3 lane,
    # launched on the server's launch tick and flying at the server's speed for the
    # server's distance. This is the pass that makes the attack dodgeable by eye.
    (fx.particle_emitter(
            "crest_wall",
            duration=duration, looping=False,
            start_lifetime=random_between(WAVE_TRAVEL_TICKS - 8, WAVE_TRAVEL_TICKS + 2),
            start_speed=random_between(WAVE_SPEED_BPS - 0.6, WAVE_SPEED_BPS + 0.6),
            start_size=rand_size3(1.5, 2.6),
            simulation_space="World", max_particles=34, parallel_update=True)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=WAVE_LAUNCH_TICK, count=constant(16)),
                               burst(time=WAVE_LAUNCH_TICK + 3, count=constant(10)),
                               burst(time=WAVE_LAUNCH_TICK + 7, count=constant(6))])
        .with_shape(function_shape(
            x="(randomA-0.5)*6.0", y="randomB*1.6", speed_z="-1"))
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 1.3, "NearFade": 0.7},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_curves(
            size_over_lifetime=curve(0.55, 1.2, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.16, 0.5), (0.8, 0.34), (1.0, 0.0)],
                [(0.0, 0.20, 0.26, 0.38), (1.0, 0.12, 0.15, 0.24)],
                [(0.0, 0.26, 0.31, 0.44), (1.0, 0.15, 0.17, 0.27)]))
        .with_cull_box(WAVE_CULL_MIN, WAVE_CULL_MAX))

    # Crest streaks: the water-white spearhead riding the wall's front. colorBySpeed
    # keeps the fastest streaks white and lets the stragglers cool into the wall body.
    (fx.particle_emitter(
            "crest_streaks",
            duration=duration, looping=False,
            start_lifetime=random_between(WAVE_TRAVEL_TICKS - 14, WAVE_TRAVEL_TICKS),
            start_speed=random_between(WAVE_SPEED_BPS, WAVE_SPEED_BPS + 3.0),
            start_size=rand_size3(0.15, 0.3),
            simulation_space="World", max_particles=48)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=WAVE_LAUNCH_TICK, count=constant(26)),
                               burst(time=WAVE_LAUNCH_TICK + 5, count=constant(14))])
        .with_shape(cone(angle=13.0, radius=1.6))
        .rotated(-90.0, 0.0, 0.0)
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.3, 1.6, 2.2)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                       length_scale=2.8, vertex_sorting="NONE")
        .with_module("colorBySpeed", color_by_speed(COOL_WATER, HOT_FOAM, 6.0, 15.0))
        .with_curves(color_over_lifetime=varied(
            [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 0.75, 0.85, 1.0), (1.0, 0.5, 0.45, 0.85)],
            [(0.0, 0.62, 0.78, 1.0), (1.0, 0.4, 0.38, 0.72)]))
        .with_cull_box(WAVE_CULL_MIN, WAVE_CULL_MAX))

    # Churned spray thrown off the crest as it passes — soft, so the spray dies into the
    # deck instead of hanging through it.
    (fx.particle_emitter(
            "crest_spray",
            duration=duration, looping=False, start_lifetime=random_between(20, 34),
            start_speed=random_between(3.0, 6.5),
            start_size=rand_size3(0.5, 0.9),
            simulation_space="World", max_particles=26)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=WAVE_LAUNCH_TICK, count=constant(10),
                                     cycles=4, interval=9)])
        .with_shape(cone(angle=38.0, radius=1.8))
        .rotated(-90.0, 0.0, 0.0)
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 0.9, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.2, [SEG_SMOOTH_DOWN], "lifetime")),
            color_over_lifetime=gradient(
                [(0.0, 0.5), (0.6, 0.35), (1.0, 0.0)],
                [(0.0, 0.55, 0.62, 0.75), (1.0, 0.35, 0.38, 0.52)]))
        .with_cull_box(WAVE_CULL_MIN, WAVE_CULL_MAX))
    return fx


# ---------------------------------------------------------------------------
# 8. eclipse:wisp_gush — F-045b breach burst out of the opened gate
# ---------------------------------------------------------------------------
def build_wisp_gush() -> FxBuilder:
    fx = FxBuilder("wisp_gush")

    # Violet wisps shoved out of the doorway (local -Z = out of the gate front).
    # Speed retune: 7-16 b/s = 0.35-0.8 b/t, so a wisp clears 10-40 blocks of threshold
    # over its life. The old numbers were the same digits read as b/t — one block total.
    (fx.particle_emitter(
            "gush_wisps",
            duration=80, looping=False, start_lifetime=random_between(30, 55),
            start_speed=random_between(7.0, 16.0),
            start_size=rand_size3(0.2, 0.45),
            max_particles=70)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(30), cycles=3, interval=8)])
        .with_shape(cone(angle=40.0, radius=2.6))
        .rotated(-90.0, 0.0, 0.0)
        .with_module("colorBySpeed", color_by_speed(COOL_SOUL, HOT_WHITE, 4.0, 16.0))
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.25, [SEG_SMOOTH_DOWN], "lifetime")),
            noise=dict(frequency=0.7, position=nf3(0.06)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.816, 0.702, 1.0), (1.0, 0.45, 0.28, 0.7)],
                [(0.0, 0.68, 0.56, 0.95), (1.0, 0.32, 0.2, 0.52)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.7, 1.2, 2.6)))
        .with_lights(sky=15, block=15)
        .with_cull_box((-10.0, -6.0, -20.0), (10.0, 10.0, 6.0)))

    # Cold violet smoke rolling low out of the threshold. soft_particle: this roll hugs
    # the floor of the gate and used to end on a straight line across the threshold.
    (fx.particle_emitter(
            "gush_smoke",
            duration=80, looping=False, start_lifetime=random_between(45, 75),
            start_speed=random_between(2.4, 6.0),
            start_size=rand_size3(0.9, 1.7),
            max_particles=34)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(12), cycles=3, interval=10)])
        .with_shape(cone(angle=55.0, radius=2.8))
        .rotated(-90.0, 0.0, 0.0)
        .with_material(material_shader(
            "eclipse:soft_particle",
            textures={"MainTexture": SMOKE_TEX},
            uniforms={"SoftDistance": 1.1, "NearFade": 0.6},
            blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                1.0, 0.2, [SEG_SMOOTH_DOWN], "lifetime")),
            noise=dict(frequency=0.3, position=nf3(0.05), remap_curve=GUST_REMAP),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.45), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, 0.28, 0.16, 0.4), (1.0, 0.14, 0.08, 0.22)]))
        .with_cull_box((-10.0, -6.0, -18.0), (10.0, 8.0, 6.0)))
    return fx


# The dust puff leads: it is a sub-emitter target, and LINT-SUBEM-RESOLVE wants the
# child on disk before the maw that references it is linted.
BUILDERS = {
    "day_rift_dust_puff.fx": build_day_rift_dust_puff,
    "day_rift_maw.fx": build_day_rift_maw,
    "portal_soul_veil.fx": build_portal_soul_veil,
    "key_trail.fx": build_key_trail,
    "arena_mist_wall.fx": build_arena_mist_wall,
    "ferry_harvest_ring.fx": build_ferry_harvest_ring,
    "ferry_wave_crest.fx": build_ferry_wave_crest,
    "wisp_gush.fx": build_wisp_gush,
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
