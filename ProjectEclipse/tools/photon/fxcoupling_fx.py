#!/usr/bin/env python3
"""fxcoupling_fx — POLISH1 "FX-Kopplungswelle": die drei SPEC-ONLY Photon-Kopplungen.

Authors (via fxlib, see tools/photon/README.md) the three couplings the F-099 eval round
found specified-but-never-built, one asset family per mob report:

    eclipse:wizard_star_call        MB2 §7.4 — Orin's star_call Dirigier-Child-fx:
                                    Staff-Tip-Mote-Säule (raise) + Gather-Indraw,
                                    Release-Ring/Beam auf dem 26t-Beat, Dirigier-Drizzle
                                    solange die Bolts fallen (Entity-Lane, XROT).
    eclipse:wizard_star_call_fast   MB2 §9.2 follow-up variant, release beat at 19t
                                    (unveiled telegraph) + 70t shower (14 bolts). The
                                    WizardFxRows leg picks it off the cue's `a` param —
                                    the "Anim-Akzent kommt 0.35s zu spät" honesty gap
                                    is closed instead of documented.
    eclipse:lantern_flicker_dip     MC3 §7 — the CAGE light-collapse the baked glowmask
                                    cannot do: REVERSE_SUB shadow gulp at the cage
                                    center + falling soot flecks. Executor-scaled by
                                    the timeline keyframe's scale factor.
    eclipse:lantern_flicker_surge   MC3 §7 — the 0.58s overshoot: recovery flash +
                                    cage re-light sheet + soul-mote puff.
    eclipse:stalker_sprint_smear    MC2 §0/§9.4.6 — sprint smear off the fx_smear_l/r
                                    anchor bones: two short-lived dark ara wisp ribbons
                                    at the flank pivots + distanceRate umbral flecks
                                    (per BLOCK travelled — the smear scales with real
                                    speed for free). PhotonMobFx loop, AutoRotate.XROT.

ANCHOR MATH (all three ride EntityEffectExecutor = eye pos + world-space offset, local
axes rotated by AutoRotate):

  * XROT (bytecode-verified, EntityEffectExecutor tick branch 3): rotation =
    rotateY(toRadians(-90 - visualBodyYaw)) → effect-local +X = entity FORWARD,
    +Z = entity RIGHT, +Y = up. Geo-space mapping (Bedrock geo faces -Z, +X = entity
    LEFT): geo (gx, gy, gz) → local (x = -gz/16, z = -gx/16), y via the eye offset.
  * Orin (eye 1.80): staff tip geo x -5 px = 0.3125 b entity-RIGHT → local z +0.31;
    MB2 anchor height y +1.40 over foot → row offset (0, -0.40, 0).
  * Drift Lantern (eye 0.75): cage center y ≈ 12 px = 0.75 b → offset null; the pulse
    anchors EXACTLY at the cage, per MC3 §7 Randbedingung 4.
  * Umbral Stalker (eye 0.85): fx_smear_l geo (+3.5, 11, -2) → local (+0.125, 0, -0.219),
    fx_smear_r → (+0.125, 0, +0.219); pivot height 0.6875 b → row offset (0, -0.1625, 0).

V2.1-Stacking-Law: additive ramps are born DARK (birth tints under their own fade
target), shells stay broad (indraw r 0.85, drizzle r 1.6), counts trimmed (worst case
star_call ≈ 70 live, lantern pulses ≤ 12, smear ≤ 30 + 2 ribbons). HDR capped at the
wave-13 ceiling 1.45. The dip/smear darkness comes from REVERSE_SUB / dark ALPHA quads,
never from dark bloom.

Photon caches .fx statically — after regenerating run `/photon_client
clear_client_fx_cache` in a live client (F3+T alone does NOT reload them).

Run:  python3 tools/photon/fxcoupling_fx.py
Then: python3 tools/photon/fxlib.py validate --lint
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, REPO_ROOT, blend, burst,
    circle, cone, constant, curve, gradient, nf3, random_between, random_gradient,
    sphere, texture_material, validate_file,
)

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"   # shared, authored by gen_player_fx.py
BEAM_CORE = "eclipse:textures/particle/beam_core.png"  # shared, authored by boss_b_fx.py
WISP = "eclipse:textures/particle/wisp_white.png"      # shared, authored by newfx_a assets

#: `photon:.../smoke.png` is a 2x2 flipbook (grave_lantern finding): hold one random
#: frame per particle or every quad renders the whole 4-puff sheet.
SMOKE_ONE_FRAME = dict(tiles=(2, 2), animation="WholeSheet",
                       frame_over_time=constant(0.0),
                       start_frame=random_between(0.0, 3.99), cycle=1.0)

# IDEAS-mobs #5 two-pass law: dst - src, works with bloom off (no dark-bloom dependency).
BLEND_REVERSE_SUB = blend("ONE", "ONE", "ONE", "ZERO", "REVERSE_SUB")

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def eased(points, lock=True, x_axis="duration", y_axis="value"):
    """NF curve through (t, value) points with smoothstep tangents — every non-flat
    segment carries genuinely off-chord control points (LINT-LINEAR-CURVE clean)."""
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        third = (x1 - x0) / 3.0
        segments.append((x0, y0, x0 + third, y0, x1 - third, y1, x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments, x_axis, y_axis, lock=lock)


def sz(lo, hi, points):
    """size_over_lifetime shorthand — eased (t, value) points on the lifetime axis."""
    return eased(points, x_axis="lifetime", y_axis="size") if isinstance(points, list) \
        else curve(lo, hi, [points], "lifetime", "size")


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def inherit_velocity(multiply, mode="CURRENT"):
    """`inheritVelocity` body — see mobs_fx.py: World-space + positive = wake drag."""
    return {"mode": mode, "multiply": constant(float(multiply))}


def ara_toggles_on(emitter):
    """Marks an ara trail's `section`/`physicsSetting` ToggleGroups `_enable: 1b`
    (LDLib2 deserialises them DISABLED otherwise — the W13/B2 finding)."""
    for key in ("section", "physicsSetting"):
        block = emitter._config.get(key)
        if isinstance(block, dict):
            block["_enable"] = B(1)
    return emitter


def rgb(hexcode: int):
    return ((hexcode >> 16 & 0xFF) / 255.0, (hexcode >> 8 & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


# ---------------------------------------------------------------------------
# Palettes
# ---------------------------------------------------------------------------
# MB2 §7.4 staff-tip emissive family + FX-STYLE-GUIDE SACRED void fade target.
STAR_HOT = rgb(0xEAF6FF)       # staff-tip emissive core
STAR_EDGE = rgb(0xBFE2FF)      # staff-tip emissive rim
FLASH_CORE = rgb(0xFFF7DC)     # release flash core (MB2 table)
FLASH_RIM = rgb(0x9FC4FF)      # release flash rim (MB2 table)
DRIZZLE = rgb(0xF5E6B8)        # conducting drizzle, dimmed (alpha ≤ 0.63 = the α160)
SAC_VOID = rgb(0x2E2347)       # fade-out target (never fade to black)
STAR_BIRTH = (0.10, 0.12, 0.18)  # V2.1 birth tint, darker than SAC_VOID

# Drift-lantern soul-flame family (SCULK_SOUL teal — the mob's own server particles).
LAN_HOT = rgb(0xD4FAF2)        # recovery-flash core
LAN_TEAL = rgb(0x4DD9C7)       # THE lantern teal
LAN_DEEP = rgb(0x216B73)       # tails
STM_SLATE = rgb(0x3A3A55)      # fade target (STORM void analog, backlog_fx precedent)
LAN_BIRTH = (0.06, 0.12, 0.12)  # dark teal birth tint
SOOT = (0.10, 0.10, 0.13)      # gutter debris (ALPHA, darkens)
# The gulp's REVERSE_SUB subtraction amount (~9% luminance) rides its startColor
# (0xFF17181D) — colorOverLifetime MULTIPLIES startColor (glitch_pop law), so the
# ramp must stay a white alpha envelope or the subtraction squares itself to nothing.

# Umbral family (mobs_fx tokens): the smear is a SHADOW — dark ALPHA + rare violet glints.
GLI_DEAD = (0.141, 0.110, 0.220)   # #241C38
COR_VIOLET = (0.616, 0.306, 0.867)  # #9D4EDD
COR_INK = (0.235, 0.035, 0.424)    # #3C096C
SMEAR_DARK = (0.055, 0.04, 0.10)   # ribbon body (ALPHA quad = darkens what's behind)


# ---------------------------------------------------------------------------
# 1) eclipse:wizard_star_call[_fast] — MB2 §7.4 (entity lane on Orin, XROT,
#    row offset (0, -0.40, 0) → anchor 1.40 b over foot; staff tip local z +0.31)
# ---------------------------------------------------------------------------
#: Anim beats (wizard_orin.animation.json star_call, one 3.6 s sheet for both casts):
#: crouch dip 0.18 s, raise 0.55 s — absolute, they do NOT scale with the telegraph.
CROUCH_T = 3.6   # ticks
RAISE_T = 11.0   # ticks
#: local z of the staff tip (geo x -5 px = 0.3125 b entity-right → +Z under XROT).
TIP_Z = 0.31


def build_wizard_star_call(fast: bool = False) -> FxBuilder:
    """MB2 §7.4 three-emitter table + one polish addition (gather_indraw: the raise
    should read as CALLING starlight, so sparks converge onto the tip before the
    release — the multi-stage "gather" the quality bar asks for).

    Base: release beat 26t = STAR_CALL_TELEGRAPH_TICKS+1 (the sender fires on the
    telegraph-START tick, the release lands when the timer hits -1), shower 50t =
    10 bolts × 5t. Fast (unveiled): 19t / 70t = 14 × 5t. The zone (`starZone`, may be
    24+ blocks away) stays TABU — the server's END_ROD/Firework impacts own it."""
    name = "wizard_star_call_fast" if fast else "wizard_star_call"
    release_t = 19 if fast else 26
    shower_t = 70 if fast else 50
    fx = FxBuilder(name)
    cull = ((-2.6, -2.0, -2.6), (2.6, 6.5, 2.6))

    # RAISE 0→release: narrow rising mote column at the staff tip (r 0.15, drift
    # +0.8 b/s, life 0.5 s). Rate 6→22 p/s with the 0.7× crouch dip and the full ramp
    # from the raise beat (MB2 numbers verbatim; beats normalized onto the variant's
    # own release window).
    (fx.particle_emitter(
            "raise_motes",
            duration=release_t, looping=False, max_particles=16,
            start_lifetime=constant(10), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.07), random_between(0.05, 0.07),
                           random_between(0.05, 0.07)),
            simulation_space="Local")
       .at(0.0, 0.0, TIP_Z)
       .with_emission(rate=eased([(0.0, 6.0), (CROUCH_T / release_t, 4.2),
                                  (RAISE_T / release_t, 8.0), (1.0, 22.0)]))
       .with_shape(circle(radius=0.15, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.25, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(0.0, 0.8, 0.0)),
            # MB2 size taper 0.06→0.02 = ×0.33 over life.
            size_over_lifetime=sz(0.33, 1.0, (0.0, 1.0, 0.3, 0.95, 0.7, 0.5, 1.0, 0.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.85), (1.0, 0.0)],
                [(0.0,) + STAR_BIRTH, (0.35,) + STAR_HOT, (1.0,) + STAR_EDGE],
                [(0.0,) + STAR_BIRTH, (0.4,) + STAR_EDGE, (1.0,) + SAC_VOID])))

    # GATHER raise→release (polish): sparks born on a broad 0.85 b shell converge onto
    # the tip — starlight being PULLED in, the anticipation half of the release flash.
    gather_window = release_t - int(RAISE_T)
    (fx.particle_emitter(
            "gather_indraw",
            duration=gather_window, looping=False, start_delay=constant(int(RAISE_T)),
            max_particles=8,
            start_lifetime=random_between(6, 8), start_speed=random_between(-2.6, -1.9),
            start_size=nf3(random_between(0.035, 0.055), random_between(0.035, 0.055),
                           random_between(0.035, 0.055)),
            simulation_space="Local")
       .at(0.0, 0.1, TIP_Z)
       .with_emission(rate=eased([(0.0, 3.0), (0.6, 6.0), (1.0, 11.0)]))
       .with_shape(sphere(radius=0.85, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 1.15, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            # Inverted run (dark → hot): anticipation building into the release
            # (the A5 indraw license), sizes shrinking toward the tip.
            size_over_lifetime=sz(0.5, 1.0, (0.0, 1.0, 0.35, 0.9, 0.75, 0.65, 1.0, 0.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.35, 0.8), (1.0, 0.9)],
                [(0.0,) + STAR_BIRTH, (0.5,) + STAR_EDGE, (1.0,) + STAR_HOT],
                [(0.0,) + STAR_BIRTH, (0.55,) + FLASH_RIM, (1.0,) + STAR_HOT])))

    # RELEASE at the beat: 24-point radial ring r 0.5→2.2 in 0.3 s (5.7 b/s × 6t).
    (fx.particle_emitter(
            "release_ring",
            duration=8, looping=False, start_delay=constant(release_t),
            max_particles=24,
            start_lifetime=constant(6), start_speed=constant(5.7),
            start_size=nf3(0.09), simulation_space="Local")
       .at(0.0, 0.0, TIP_Z)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(24), cycles=1)])
       # BurstSpread = Unity's even-around-the-arc distribution for burst counts —
       # exactly the 24-point radial ring. ("Uniform" is NOT a ShapeArcMode; Photon
       # valueOf-or-null'd it to null and the first ring particle NPE-crashed the
       # client render thread. Caught in the F-101 live acceptance pass.)
       .with_shape(circle(radius=0.5, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.45, 1.4, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_lights(sky=15, block=15)
       .with_curves(
            size_over_lifetime=sz(0.4, 1.0, (0.0, 1.0, 0.2, 0.9, 0.7, 0.55, 1.0, 0.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.5, 0.6), (1.0, 0.0)],
                [(0.0,) + FLASH_CORE, (0.45,) + FLASH_RIM, (1.0,) + SAC_VOID])))

    # RELEASE vertical beam pulse: h 6 b, 0.15 s — matches glow_staff_tip 1.9→2.6×
    # (sheet keys 1.25/1.3) and the 1.45 arm snap.
    (fx.beam_emitter(
            "release_beam", end=(0.0, 6.0, 0.0), duration=4, looping=False,
            start_delay=release_t, raycast="NONE",
            width=curve(0.0, 0.34, [(0.0, 0.1, 0.06, 1.0, 0.4, 0.7, 1.0, 0.0)]),
            color_nf=gradient(
                [(0.0, 0.9), (0.6, 0.55), (1.0, 0.0)],
                [(0.0,) + FLASH_CORE, (0.5,) + FLASH_RIM, (1.0,) + SAC_VOID]))
       .at(0.0, 0.0, TIP_Z)
       .with_material(texture_material(BEAM_CORE, hdr=hdr(1.4, 1.35, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_lights(sky=15, block=15))

    # CONDUCT release→release+shower: soft star-dust cone around Orin (r 1.6 b, fall
    # -0.4 b/s, 8 p/s), twinkling off the star_2x2 flipbook (~3 Hz over the 24t life).
    # World space: existing dust must not swirl when the rooted wizard turns his torso.
    # The emission window ends HARD with the last bolt (duration = bolts × 5t).
    (fx.particle_emitter(
            "conducting_drizzle",
            duration=shower_t, looping=False, start_delay=constant(release_t),
            max_particles=16,
            start_lifetime=random_between(20, 26), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.075), random_between(0.05, 0.075),
                           random_between(0.05, 0.075)),
            simulation_space="World")
       .at(0.0, 0.6, 0.0)  # 2.0 b over foot: born just over the hat, sinks to chest
       .with_emission(rate=constant(8.0))
       .with_shape(circle(radius=1.6, thickness=1.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.2, 1.1, 0.9),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*cull)
       .with_curves(
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=eased([(0.0, 0.0), (1.0, 3.99)],
                                                    x_axis="lifetime"),
                              start_frame=random_between(0.0, 3.0), cycle=4.0),
            velocity_over_lifetime=dict(linear=nf3(0.0, -0.4, 0.0)),
            # Dimmed #F5E6B8 α160 (= 0.63 peak) with the twinkle riding the alpha bumps.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.63), (0.35, 0.25), (0.55, 0.6),
                 (0.75, 0.28), (1.0, 0.0)],
                [(0.0,) + STAR_BIRTH, (0.3,) + DRIZZLE, (1.0,) + SAC_VOID],
                [(0.0,) + STAR_BIRTH, (0.35,) + STAR_EDGE, (1.0,) + SAC_VOID])))
    return fx


# ---------------------------------------------------------------------------
# 2) eclipse:lantern_flicker_dip / _surge — MC3 §7 (entity lane, NONE, offset null →
#    anchor = eye 0.75 = the cage center; executor scale carries the keyframe factor)
# ---------------------------------------------------------------------------
LANTERN_CULL = ((-1.3, -1.3, -1.3), (1.3, 1.4, 1.3))


def build_lantern_flicker_dip() -> FxBuilder:
    """The SCHEIN collapsing, not the flame (that one the sheet already shrinks): a
    REVERSE_SUB shadow gulp swallowing the cage glow for ~0.3 s + two soot flecks
    guttering off the flame. Spawned per timeline dip keyframe (0.06/0.26/0.46 s),
    allowMulti (three dips overlap inside one entity dedup window), executor-scaled
    deeper = bigger (DriftLanternFx maps factor 0.30→×1.25 … 0.48→×1.07)."""
    fx = FxBuilder("lantern_flicker_dip")

    # The gulp: one soft dark quad, dst−src, briefly eating ~9% luminance off the
    # glass. Local space — it must ride the drifting lantern for its 7t life.
    (fx.particle_emitter(
            "light_gulp",
            duration=2, looping=False, max_particles=1,
            start_lifetime=constant(7), start_speed=constant(0.0),
            start_size=nf3(1.05), start_color=0xFF17181D,
            simulation_space="Local")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(CIRCLE, blend=BLEND_REVERSE_SUB))
       .with_renderer(order_in_layer=-1)  # the shadow draws before other translucents
       .with_cull_box(*LANTERN_CULL)
       .with_curves(
            size_over_lifetime=sz(0.7, 1.0, (0.0, 0.6, 0.25, 1.0, 0.7, 0.95, 1.0, 0.4)),
            # colorOverLifetime MULTIPLIES startColor (glitch_pop law) — the GULP
            # amount lives in startColor, the ramp is a white alpha envelope with a
            # fast tail so the 0.46 s gulp is mostly gone under the 0.58 s surge.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)])))

    # Gutter debris: two soot flecks dropping off the choking flame. World space —
    # they fall out of the lantern's drift, ALPHA (dark against the glow).
    (fx.particle_emitter(
            "soot_flecks",
            duration=2, looping=False, max_particles=3,
            start_lifetime=random_between(8, 12), start_speed=random_between(0.15, 0.3),
            start_size=nf3(random_between(0.03, 0.05), random_between(0.03, 0.05),
                           random_between(0.03, 0.05)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(cone(angle=40.0, radius=0.08, thickness=1.0))
       .rotated(180.0, 0.0, 0.0)  # cone aimed DOWN: soot falls, never rises
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*LANTERN_CULL)
       .with_physics(collision=False, gravity=0.05, bounce_chance=0.0)
       .with_curves(
            uv_animation=SMOKE_ONE_FRAME,
            size_over_lifetime=sz(0.5, 1.0, (0.0, 1.0, 0.3, 0.85, 0.7, 0.6, 1.0, 0.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.65), (1.0, 0.0)],
                [(0.0,) + SOOT, (1.0,) + SOOT])))
    return fx


def build_lantern_flicker_surge() -> FxBuilder:
    """The 0.58 s overshoot (sheet scale 1.2): the flame snapping back — a 5t recovery
    flash at the cage, a wide re-light sheet on the glass, and a 4-mote soul puff
    (the client-side echo of the server's SCULK_SOUL trigger puff, but ON the beat)."""
    fx = FxBuilder("lantern_flicker_surge")

    (fx.particle_emitter(
            "recovery_flash",
            duration=2, looping=False, max_particles=1,
            start_lifetime=constant(5), start_speed=constant(0.0),
            start_size=nf3(0.55), simulation_space="Local")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.45, 1.4),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*LANTERN_CULL)
       .with_lights(sky=15, block=15)
       .with_curves(
            size_over_lifetime=sz(0.55, 1.0, (0.0, 0.4, 0.12, 1.0, 0.5, 0.8, 1.0, 0.3)),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.5, 0.55), (1.0, 0.0)],
                [(0.0,) + LAN_HOT, (0.5,) + LAN_TEAL, (1.0,) + LAN_DEEP])))

    # The glass re-lighting: one broad soft teal sheet, no HDR (glow, not bloom),
    # born dark (V2.1) so it swells out of the gulp's shadow instead of popping white.
    (fx.particle_emitter(
            "cage_relight",
            duration=2, looping=False, max_particles=1,
            start_lifetime=constant(9), start_speed=constant(0.0),
            start_size=nf3(1.2), simulation_space="Local")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(CIRCLE, blend=BLEND_ADDITIVE))
       .with_cull_box(*LANTERN_CULL)
       .with_curves(
            size_over_lifetime=sz(0.75, 1.0, (0.0, 0.5, 0.3, 1.0, 0.7, 0.9, 1.0, 0.5)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.28), (1.0, 0.0)],
                [(0.0,) + LAN_BIRTH, (0.45,) + LAN_TEAL, (1.0,) + STM_SLATE])))

    # Soul puff: four motes float up and out of the overshooting flame. World space —
    # they hang in the air while the lantern drifts on.
    (fx.particle_emitter(
            "soul_puff",
            duration=2, looping=False, max_particles=4,
            start_lifetime=random_between(12, 16), start_speed=random_between(0.5, 1.0),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(cone(angle=18.0, radius=0.08, thickness=1.0))
       .at(0.0, 0.1, 0.0)
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.3, 1.25),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*LANTERN_CULL)
       .with_curves(
            size_over_lifetime=sz(0.4, 1.0, (0.0, 1.0, 0.3, 0.9, 0.7, 0.6, 1.0, 0.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.8), (0.6, 0.5), (1.0, 0.0)],
                [(0.0,) + LAN_BIRTH, (0.35,) + LAN_HOT, (0.7,) + LAN_TEAL,
                 (1.0,) + STM_SLATE],
                [(0.0,) + LAN_BIRTH, (0.4,) + LAN_TEAL, (1.0,) + LAN_DEEP])))
    return fx


# ---------------------------------------------------------------------------
# 3) eclipse:stalker_sprint_smear — MC2 §0/§9.4.6 (PhotonMobFx loop, XROT,
#    row offset (0, -0.1625, 0) → anchor at the fx_smear pivot height 0.6875 b)
# ---------------------------------------------------------------------------
#: fx_smear bone pivots in effect-local space (see the anchor-math header).
SMEAR_FWD = 0.125    # geo z -2 px → 0.125 b toward the muzzle (shoulder line)
SMEAR_SIDE = 0.219   # geo x ±3.5 px → 0.219 b off the spine
SMEAR_CULL = ((-5.0, -1.2, -5.0), (5.0, 1.6, 5.0))


def build_stalker_sprint_smear() -> FxBuilder:
    """Sprint smear off the two empty fx_smear anchor bones: a SHADOW being dragged,
    not a glow — two short-lived dark ara wisp ribbons whipping off the flank pivots
    (World-space segment lag + inertia physics = they tear and settle behind the
    gallop) plus umbral flecks shed per BLOCK TRAVELLED (distanceRate: a faster
    stalker smears harder, for free) with a rare dim violet glint so the trail reads
    umbral, not sooty. Attach/detach = UmbralStalkerEntity.isSprintSmearing() via the
    PhotonMobFx row; graceful release fades the ribbons out mid-stride."""
    fx = FxBuilder("stalker_sprint_smear")

    for suffix, side in (("l", -SMEAR_SIDE), ("r", +SMEAR_SIDE)):
        ribbon = (fx.ara_trail_emitter(
                f"smear_ribbon_{suffix}",
                duration=40, looping=True,
                space="World", alignment="View", thickness=0.11,
                time=0.45, time_interval=0.05, min_distance=0.05,
                # Short-lived directional wisp: holds a body off the shoulder, then
                # tears to nothing (eased, LINT-LINEAR-CURVE clean).
                thickness_over_length=eased([(0.0, 1.0), (0.4, 0.72), (1.0, 0.0)]),
                # A dark ALPHA ribbon DARKENS what is behind it — the smear is the
                # night smearing, never a light source (no additive, no HDR).
                color_over_length=gradient(
                    [(0.0, 0.5), (0.55, 0.28), (1.0, 0.0)],
                    [(0.0,) + SMEAR_DARK, (1.0,) + GLI_DEAD]),
                physics=dict(gravity=(0.0, -0.35, 0.0), inertia=0.5,
                             velocity_smoothing=0.75, damping=0.68))
           .at(SMEAR_FWD, 0.0, side)
           .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
           .with_renderer(vertex_sorting="DISTANCE")
           .with_cull_box(*SMEAR_CULL))
        ara_toggles_on(ribbon)

    # Umbral flecks: shed along the gallop line, per block moved. They launch in the
    # wake (positive inheritVelocity) and sink — shadow falling off the body.
    (fx.particle_emitter(
            "umbral_flecks",
            duration=40, looping=True, max_particles=20,
            start_lifetime=random_between(7, 12), start_speed=random_between(0.05, 0.2),
            start_size=nf3(random_between(0.035, 0.06), random_between(0.035, 0.06),
                           random_between(0.035, 0.06)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), distance_rate=constant(0.45))
       .with_shape(sphere(radius=0.28, thickness=0.6))
       .with_module("inheritVelocity", inherit_velocity(0.3))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*SMEAR_CULL)
       .with_physics(collision=False, gravity=0.04, bounce_chance=0.0)
       .with_curves(
            uv_animation=SMOKE_ONE_FRAME,
            size_over_lifetime=sz(0.45, 1.0, (0.0, 1.0, 0.3, 0.85, 0.7, 0.55, 1.0, 0.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.55), (1.0, 0.0)],
                [(0.0,) + SMEAR_DARK, (0.6,) + GLI_DEAD, (1.0,) + SMEAR_DARK],
                [(0.0,) + SMEAR_DARK, (0.5,) + COR_INK, (1.0,) + SMEAR_DARK])))

    # Dim violet glints, ~1 per 2 blocks of sprint: the NIGHT read. The stalker hunts
    # at light 0 where a dark ALPHA ribbon has nothing to darken, so these tiny sparks
    # (spine-glow palette, dark-born, low HDR) are what tags the smear as umbral in
    # the dark — while staying far too dim to ever brighten the shadow by day.
    (fx.particle_emitter(
            "violet_glints",
            duration=40, looping=True, max_particles=8,
            start_lifetime=random_between(5, 8), start_speed=constant(0.02),
            start_size=nf3(random_between(0.03, 0.055), random_between(0.03, 0.055),
                           random_between(0.03, 0.055)),
            simulation_space="World")
       .with_emission(rate=constant(0.0), distance_rate=constant(0.5))
       .with_shape(sphere(radius=0.22, thickness=0.4))
       .with_module("inheritVelocity", inherit_velocity(0.2))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.7, 0.4, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*SMEAR_CULL)
       .with_curves(
            size_over_lifetime=sz(0.4, 1.0, (0.0, 1.0, 0.25, 0.9, 0.7, 0.5, 1.0, 0.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
                [(0.0,) + SMEAR_DARK, (0.5,) + COR_VIOLET, (1.0,) + COR_INK],
                [(0.0,) + SMEAR_DARK, (0.55,) + COR_INK, (1.0,) + SMEAR_DARK])))
    return fx


# ---------------------------------------------------------------------------
BUILDERS = {
    "wizard_star_call.fx": lambda: build_wizard_star_call(fast=False),
    "wizard_star_call_fast.fx": lambda: build_wizard_star_call(fast=True),
    "lantern_flicker_dip.fx": build_lantern_flicker_dip,
    "lantern_flicker_surge.fx": build_lantern_flicker_surge,
    "stalker_sprint_smear.fx": build_stalker_sprint_smear,
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
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} "
                  f"(raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
