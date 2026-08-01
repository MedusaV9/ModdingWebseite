#!/usr/bin/env python3
"""CREDITS5 (F-102 "Credits-Tausende") — authors the sky-contraction / eclipse-vanish
Photon assets with fxlib:

  eclipse:credits5_skydrain   F-102 "Himmel-Kontraktion": the particle half of the
                              sky pulling itself into the black hole — long inward
                              streak trails born on a wide far dome around the maw
                              anchor (57-88 blocks out, well outside the ~26-block
                              maw) that curl and POUR toward the center, over a
                              whisper-alpha haze shell creeping the same way. Fired
                              by CreditsSequence at the maw anchor every 150t across
                              reveal+560..+1220 (~150t one-shot, back-to-back fires
                              seam like the maw's kneel-corona sustain law); the
                              display half is CreditsBlackHoleAct's sky-drain
                              streams on the same window.
  eclipse:credits5_lastlight  F-102 "Eclipse-Verschwinden" seal: the eclipse's LAST
                              LIGHT — one dim, slow center flare blooming softly and
                              dying, a thin exhaling halo ring and a handful of final
                              ember motes (~120t one-shot, fired ONCE at
                              reveal+1270, 30t before the T_FINALE_DARK melt).
                              Deliberately QUIET: the beat is a vanish, not a burst.

Java-side tick contract (F-102): SKYDRAIN_CUE_FROM=560 / PERIOD=150 / UNTIL=1220 and
ECLIPSE_LASTLIGHT_AT=1270 in CreditsSequence (offsets from T_FINALE_REVEAL); the
ECLIPSE_FADE_AT intensity walk-down (1140/1220/1290) runs UNDER both cues, so the
lastlight flare is authored dim — it must read against an already-darkening sky
without re-brightening it.

House laws applied (the wave-13 C5 audit is baked in from the start):

  1. UNITS. `linear`/`orbital` are blocks (rad) per SECOND (x0.05/tick), `radial` is
     x0.01/tick — every motion number below is back-solved from the distance its own
     comment promises (`blocks = v x 0.05 x life` linear, `x 0.01` radial).
  2. `radial` follows normalize(localPos) and flips sign across r=0, so every inward
     pull keeps a birth-shell margin: the longest-lived streak dies at r~12, nothing
     ever bounces back out.
  3. `random_gradient` (via `varied()`) on every emitter with a real population.
  4. V2.1 stacking law: dark birth tints on all stacking layers, broad shells, HDR
     clamped to the 1.45 ceiling with the hue ratio preserved.
  5. arc_mode stays the fxlib default "Random" everywhere ("Uniform" = client crash).
  6. F-103 camera lune: both skydrain spawn shells cut a +-48 deg azimuth lune around
     world +Z (the run-invariant camera side of the anchor) via the native sphere
     `arc` wedge + shape-rotation yaw, so no haze/streak quad is ever BORN near the
     crushed-FOV view axis in the near foreground (CAMERA_LUNE_* derivation below).

Usage:  python3 tools/photon/credits5_fx.py            # write + validate both
Round-trip validation is fxlib's default; the CLI `validate` pass re-checks on disk.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, burst, circle, constant, curve, dot,
    gradient, nf3, random_between, random_gradient, sphere, texture_material,
    validate_file)

CIRCLE_TEX = "photon:textures/particle/circle.png"
SMOKE_TEX = "photon:textures/particle/smoke.png"

# Finale palette (the credits2/3/4 law): near-black violet body, mid, hot white-violet.
VIOLET_DEEP = (0.18, 0.08, 0.28)
VIOLET_MID = (0.612, 0.482, 0.878)
VIOLET_HOT = (0.816, 0.702, 1.0)
VIOLET_MID_ALT = (0.52, 0.44, 0.86)
VIOLET_HOT_ALT = (0.90, 0.76, 0.98)
#: Birth tints (V2.1 stacking law): additive layers open out of deep violet, the
#: near-black alpha haze out of its own darkness (see credits3_fx.py for the split).
VIOLET_BIRTH = (0.12, 0.06, 0.20)
DUST_BIRTH = (0.022, 0.012, 0.038)

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


# ---------------------------------------------------------------------------
# F-103 camera lune (CREDITS_RISK_CLOSEOUT §risk-3): the skydrain dome vs. the camera.
#
# Geometry (all by CreditsBlackHoleAct construction, run-invariant): the vantage is
# ALWAYS exactly VANTAGE_SOUTH south of the hole column (dir.x == 0), the fx anchor
# sits ANCHOR_AHEAD=110 blocks along the view ray, and the cue spawns the emitter
# UNROTATED (PhotonBridge.spawn without SpawnOptions) — so in the emitter's local
# frame the anchor->camera axis is ALWAYS world +Z (azimuth 90 deg), pitched up by
# the shot pitch (~10-26 deg, islandTop-dependent). The full 57-88 spawn sphere puts
# its camera-side pole ~22 blocks in front of the camera DEAD CENTER of the crushed
# ~17deg-FOV frame — a 7-12-block whisper-haze quad there fills the whole screen.
#
# Fix: cut a VERTICAL LUNE (all elevations) of +-CAMERA_LUNE_HALF deg azimuth around
# +Z out of both spawn shells via the native sphere `arc` wedge + a shape-rotation
# yaw. Jar-read semantics (photon 2.1.5 Sphere.nextPosVel + ShapeSetting +
# Vector3fHelper.rotateYXY, JOML rotateY shifts azimuth by MINUS the angle):
# sampled azimuth [0, arc) -> world azimuth [-yaw, arc-yaw); with arc = 360-2*48 =
# 264 and yaw = arc/2 + 90 = 222 the kept band is [138deg, 42deg] and the gap is
# (42deg, 138deg) — centered on +Z, verified numerically against the shipped JOML.
# Because the lune spans ALL elevations, the fix is PITCH-INDEPENDENT (the islandTop
# uncertainty vanishes). Every spawn is then >= ~40deg off the true camera axis: the
# nearest haze-quad edge stays >= ~18deg outside the <=17deg crushed-FOV half-frame
# for its whole alpha-carrying life (the haze has NO orbital — its azimuth never
# changes), and streaks that curl (<=0.6 rad) toward the axis only enter the frame
# >= ~80 blocks out as the authored thin center-converging threads. Choreo-neutral:
# radii/timing/velocities/colors untouched; the removed 96/360 of spawn directions
# were off-screen at birth by construction (only ever visible as foreground smears).
CAMERA_LUNE_HALF = 48.0
CAMERA_LUNE_ARC = 360.0 - 2.0 * CAMERA_LUNE_HALF   # 264
CAMERA_LUNE_YAW = CAMERA_LUNE_ARC / 2.0 + 90.0     # 222 (gap center -> +Z)


# ---------------------------------------------------------------------------
# 1. eclipse:credits5_skydrain — F-102 (the sky pours itself into the hole)
# ---------------------------------------------------------------------------
def build_credits5_skydrain() -> FxBuilder:
    fx = FxBuilder("credits5_skydrain")
    root = fx.empty("skydrain_root")

    # Drain streaks: stretched-billboard trails born on the far dome (57-88 blocks,
    # the display streams' 58-96 band) that curl and pour toward the hole. The pull:
    # 45 blocks over the longest 70t life — a birth at the 57-block inner edge dies
    # at r~12, well clear of the r=0 radial flip (no bounce, ever). At 0.64 b/t the
    # velocity stretch draws a 1.6-2.1-block line, longer than the per-tick travel,
    # so each trail reads as a continuous falling thread, not a dotted strobe.
    (fx.particle_emitter(
            "skydrain_streaks",
            duration=150, looping=False, start_lifetime=random_between(40, 70),
            start_speed=constant(0.0),  # the radial pull below owns ALL motion
            start_size=nf3(random_between(0.18, 0.32)),
            simulation_space="Local", max_particles=80)
        .child_of(root)
        .with_emission(rate=constant(1.0))
        # F-103 camera lune: +-48deg azimuth around +Z (the camera side) never spawns.
        .with_shape(sphere(radius=88.0, thickness=0.35, arc=CAMERA_LUNE_ARC),
                    rotation=(0.0, CAMERA_LUNE_YAW, 0.0))
        .with_curves(
            velocity_over_lifetime=dict(
                # 0.35-0.6 rad (20-34 deg) of curl on the way in — the streams bend
                # like the display drains' swirl, never a ruler line (rad/SECOND).
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.17), constant(0)),
                radial=constant(-radial_for(45.0, 70))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.55), (0.8, 0.35), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID), (0.7, *VIOLET_HOT),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID_ALT), (0.7, *VIOLET_HOT_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.15, 0.95, 1.45)))
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.4,
                       length_scale=1.5)
        .with_cull_box((-100.0, -100.0, -100.0), (100.0, 100.0, 100.0)))

    # Contraction haze: whisper-alpha smoke sheets on the same dome creeping inward a
    # visible 8-12 blocks — the sky's BODY moving, the read under the streak threads.
    (fx.particle_emitter(
            "skydrain_haze",
            duration=150, looping=False, start_lifetime=random_between(90, 140),
            start_speed=constant(0.0),
            start_size=nf3(random_between(7.0, 12.0), random_between(7.0, 12.0),
                           random_between(7.0, 12.0)),
            simulation_space="Local", max_particles=36)
        .child_of(root)
        .with_emission(rate=constant(0.24))
        # F-103 camera lune: the haze is the §risk-3 offender (7-12-block BLEND_ALPHA
        # quads) — same +-48deg +Z cutout; with no orbital its azimuth is life-constant.
        .with_shape(sphere(radius=84.0, thickness=0.3, arc=CAMERA_LUNE_ARC),
                    rotation=(0.0, CAMERA_LUNE_YAW, 0.0))
        .with_curves(
            velocity_over_lifetime=dict(
                # Creeps 8-12 blocks inward over the 90-140t life (radial x0.01/tick).
                radial=constant(-radial_for(12.0, 140))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.13), (0.75, 0.09), (1.0, 0.0)],  # whisper alpha
                [(0.0, *DUST_BIRTH), (0.3, 0.2, 0.11, 0.32), (1.0, 0.07, 0.04, 0.12)],
                [(0.0, *DUST_BIRTH), (0.3, 0.16, 0.09, 0.27), (1.0, 0.05, 0.03, 0.1)]))
        .with_material(texture_material(SMOKE_TEX, blend=BLEND_ALPHA))
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-100.0, -100.0, -100.0), (100.0, 100.0, 100.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. eclipse:credits5_lastlight — F-102 (the eclipse's last light winks out)
# ---------------------------------------------------------------------------
def build_credits5_lastlight() -> FxBuilder:
    fx = FxBuilder("credits5_lastlight")
    root = fx.empty("lastlight_root")

    # The flare: two big soft glows at the center blooming once and dying — DIM by
    # design (peak alpha 0.45, HDR well under the ceiling): the sky's intensity
    # walk-down runs underneath, and this beat is a farewell, not a re-ignition.
    (fx.particle_emitter(
            "lastlight_flare",
            duration=130, looping=False, start_lifetime=random_between(80, 100),
            start_speed=constant(0.0),
            start_size=nf3(random_between(6.0, 9.0), random_between(6.0, 9.0),
                           random_between(6.0, 9.0)),
            simulation_space="Local", max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=0, count=constant(2))])
        .with_shape(dot())
        .with_curves(
            size_over_lifetime=curve(
                0.0, 1.0, [(0.0, 0.4, 1.0, 1.0, 0.3, 1.0, 1.0, 0.25)]),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.45), (0.7, 0.28), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_HOT), (0.7, *VIOLET_MID),
                 (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.25, *VIOLET_HOT_ALT), (0.7, *VIOLET_MID_ALT),
                 (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.05, 0.9, 1.35)))
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))

    # The halo: one thin ring of motes exhaling outward 7 blocks and fading — the
    # eclipse's corona letting go (a breath out, mirroring the devour's pull in).
    (fx.particle_emitter(
            "lastlight_halo",
            duration=130, looping=False, start_lifetime=random_between(60, 80),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.5, 0.9)),
            simulation_space="Local", max_particles=26)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=6, count=constant(24))])
        .with_shape(circle(radius=5.0, thickness=0.15))
        .with_curves(
            velocity_over_lifetime=dict(
                # Exhales 5-7 blocks outward over the 60-80t life (radial x0.01/tick).
                radial=constant(radial_for(7.0, 80))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.35), (0.75, 0.18), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID), (1.0, *VIOLET_DEEP)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_MID_ALT), (1.0, *VIOLET_DEEP)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.0, 0.85, 1.3)))
        .with_cull_box((-16.0, -16.0, -16.0), (16.0, 16.0, 16.0)))

    # Final embers: a handful of tiny motes drifting up and out as the light dies —
    # the very last thing the eclipse sheds before the black melt takes the frame.
    (fx.particle_emitter(
            "lastlight_embers",
            duration=130, looping=False, start_lifetime=random_between(50, 80),
            # 1.5-2.4 blocks of slow scatter over the life (linear = blocks/SECOND).
            start_speed=random_between(0.4, 0.6),
            start_size=nf3(random_between(0.12, 0.22)), max_particles=12)
        .child_of(root)
        .with_emission(rate=constant(0.0),
                       bursts=[burst(time=10, count=constant(6)),
                               burst(time=34, count=constant(4))])
        .with_shape(sphere(radius=3.0, thickness=0.5))
        .with_curves(
            velocity_over_lifetime=dict(
                # Rises 2-3.2 blocks over the 50-80t life — embers, not fireworks.
                linear=nf3(constant(0), constant(0.8), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.5), (0.8, 0.25), (1.0, 0.0)],
                [(0.0, *VIOLET_BIRTH), (0.2, *VIOLET_HOT), (1.0, *VIOLET_MID)]))
        .with_material(texture_material(CIRCLE_TEX, hdr=hdr(1.1, 0.95, 1.4)))
        .with_cull_box((-12.0, -8.0, -12.0), (12.0, 14.0, 12.0)))
    return fx


BUILDERS = {
    "credits5_skydrain.fx": build_credits5_skydrain,
    "credits5_lastlight.fx": build_credits5_lastlight,
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
