#!/usr/bin/env python3
"""build_storm_fx — STORM 2.0 W-C Photon suite (PLAN-STORM2 §W-C, IDEAS-STORM-2 #3/#8).

Committed fxlib source of truth (binary-blob diff law, FX_FORMAT.md §7) for the five
`.fx` blobs consumed by `stormfx/StormPhotonFx.java`, plus the 4x4 cloud-puff flipbook
atlas (IDEAS-STORM-2 #3) and the editor-openable `.fxproj` sibling of every blob
(PHOTON-ADVANCED-1 §7 — plain uncompressed-NBT wrapper via `FxBuilder.write_fxproj`):

  eclipse:storm_debris_belt   WINDOWED loop — 3 counter-rotating ara_trail debris ribbon
                              belts (LOW skirt 0.95r/y3, MID band 0.75r/0.45h, HIGH crown
                              approach 0.55r/0.8h), slate-violet -> fog-green ->
                              violet-white, opposite orbital directions per belt.
  eclipse:storm_cloud_belt    WINDOWED loop — GPU-instanced cloud clump belt: 3 latitude
                              bands, ~1080 steady / 1200 cap instanced billboard puffs,
                              4x4 SingleRow flipbook boil off storm_puff_atlas.png,
                              alpha blend + vertexSorting NONE (belt sits OUTSIDE the
                              alpha shells by design — IDEAS-STORM-2 #8).
  eclipse:storm_vein_bolt     ONE-SHOT — HDR intra-wall lightning vein (3-segment beam
                              zig + spark scatter + core flash, life ~8 t) fired by
                              StormPhotonFx on a fresh StormWeatherFx.innerFlashSerial().
  eclipse:storm_skirt_dust    WINDOWED loop — heavy base-ring motes with REAL collision
                              whose FirstCollision sub-emitter stamps storm_dust_puff
                              where they strike terrain (supply_landing_dust pattern).
  eclipse:storm_dust_puff     sub-emitter child — flat Horizontal ground puff + grit.

RADIUS/HEIGHT ADAPTATION (PHOTON-ADVANCED-2 §1 Channel B): `PhotonBridge.spawnLoop`
exposes no `SpawnOptions`, so instead of executor `setScale` the ring shapes are
authored as `function` shapes over the GLOBAL expression variables `eclStormR` /
`eclStormH` (Darius Bacon `expr`: unknown identifiers auto-create `expr.Variable`s,
letters only — no underscores). StormPhotonFx writes both variables reflectively
BEFORE every spawn and keeps them fresh per tick; without Java (e.g. a bare
`/photon fx` preview) the `max(var, floor)` fallbacks give an 8-block dev ring.
STORM-MASS B8 adds a third variable `eclStormSpin` (the volume-rim parallax clock —
see storm_nearfield_fx.py header note for the sign law and the two sync rates).

LIVE EMISSION TUNING (PHOTON-ADVANCED-2 §1 Channel A): the BASE_RATES table below is
the frozen contract with `StormPhotonFx.TUNED_*` — the manager multiplies these
authored per-emitter rates by the live storm-intensity/distance scale and restores
them (from an isolated `FXHelper.getFX(loc, false)` snapshot) on release. Keep the
two tables in sync when retuning.

Quality bar (v7, PHOTON-QUALITY.md): every curve is EASED (never the collinear
SEG_LINEAR presets), every loop carries a cull box + hard maxParticles, hero effects
carry >= 2 emitters. `main()` self-lints all three rules after building.

Run:  python3 tools/photon/build_storm_fx.py            # atlas (if missing) + 5 fx + fxproj
      python3 tools/photon/build_storm_fx.py --atlas    # force-regenerate the atlas PNG

Deps: stdlib + Pillow/numpy for the atlas only (same toolbox as tools/art/*).
"""
from fxlib import *  # noqa: F401,F403 - the authoring DSL is the point
from fxlib import B, F, I, L  # explicit for the raw module compounds

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
BEAM_CORE = "eclipse:textures/particle/beam_core.png"
PUFF_ATLAS = "eclipse:textures/particle/storm_puff_atlas.png"
PUFF_ATLAS_PATH = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/storm_puff_atlas.png"

# FX-STYLE-GUIDE §1 storm palette tokens.
STM_SLATE = (0.227, 0.227, 0.333)   # #3A3A55
STM_ARC = (0.749, 0.851, 1.0)       # #BFD9FF
STM_DEEP = (0.353, 0.553, 0.933)    # #5A8DEE
FOG_GREEN = (0.455, 0.714, 0.580)   # interior-fog green family

# Channel-B expression variables (letters only — Bacon `expr` identifiers) with dev
# fallbacks: an un-driven preview reads r=8/h=12 instead of collapsing to a point.
R_EXPR = "max(eclStormR,8)"
H_EXPR = "max(eclStormH,12)"
# STORM-MASS B8 parallax clock (see storm_nearfield_fx.py header note for the full
# sign law): continuous volume-rim orbit angle in radians, pushed per tick by
# StormPhotonFx.stormSpinAngle(); un-driven previews read 0. Bearings SUBTRACT it;
# synced emitters carry POSITIVE orbital rates (rad/s) — 2× rim = upper strata.
SPIN_EXPR = "eclStormSpin"
SPIN_UPPER = 0.14

# Frozen Channel-A contract with StormPhotonFx.TUNED_* (see module docstring).
BASE_RATES = {
    "storm_debris_belt": {"belt_low": 0.04, "belt_mid": 0.04, "belt_high": 0.04},
    "storm_cloud_belt": {"band_low": 2.0, "band_mid": 2.0, "band_high": 2.0,
                         "shred_racers": 0.5},
    "storm_skirt_dust": {"skirt_motes": 0.7, "skirt_haze": 0.06},
}


# ---------------------------------------------------------------------------
# Eased-curve helpers (the v7 quality bar: no collinear control points)
# ---------------------------------------------------------------------------
def eased(points, mode="inout"):
    """NF curve through (t, value) points with genuinely eased bezier segments.

    mode: "inout" = horizontal tangents (hesitate-commit), "out" = fast attack / soft
    settle, "in" = slow start / late commit. Flat holds stay flat (legitimate).
    """
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        dx, dy = x1 - x0, y1 - y0
        if mode == "out":
            c = (x0 + dx * 0.12, y0 + dy * 0.62, x0 + dx * 0.55, y1)
        elif mode == "in":
            c = (x0 + dx * 0.45, y0, x1 - dx * 0.12, y1 - dy * 0.62)
        else:
            c = (x0 + dx / 3.0, y0, x1 - dx / 3.0, y1)
        segments.append((x0, y0, c[0], c[1], c[2], c[3], x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments)


def ribbon_renderer(material_entry):
    """RendererSetting compound for an EMBEDDED araConfig (build_world_fx pattern);
    written explicitly so ribbons never fall back to the MISSING (pink) material."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


def ring_shape(radius_factor, y_expr, radial_jitter):
    """Function shape: spawn points on the eclStormR-scaled belt ring at y_expr.

    randomA = bearing, randomB = radial jitter, randomC is left to y_expr. Velocity
    comes from velocityOverLifetime (orbital), never the shape speed fields — the six
    expressions each re-roll randomA..E, so correlated speeds are unsafe (§1 Channel B).
    B8: the bearing subtracts eclStormSpin (structurally neutral for uniform-random
    bearings, but every bearing term stays on the one shared parallax clock).
    """
    r = f"({R_EXPR}*{radius_factor}+(randomB-0.5)*{radial_jitter})"
    b = f"(randomA*2*PI-{SPIN_EXPR})"
    return function_shape(x=f"cos({b})*{r}",
                          z=f"sin({b})*{r}",
                          y=y_expr)


# ---------------------------------------------------------------------------
# storm_puff_atlas.png — 1024², 4x4 (IDEAS-STORM-2 #3)
# ---------------------------------------------------------------------------
def generate_puff_atlas(path, size=1024, grid=4, seed=20260725):
    """16 soft cloud puffs: each ROW is one puff variant boiling through a seamless
    4-frame loop (blob offsets are 2π-periodic in the frame phase), for Photon
    `uvAnimation {tiles:[4,4], animation:SingleRow}` — the memoized random row picks
    the variant, frameOverTime plays the boil. RGB bakes top-light/bottom-shadow;
    rows alternate the spec'd green/violet temperature casts. Deterministic seed."""
    import numpy as np
    from PIL import Image

    rng = np.random.default_rng(seed)
    cell = size // grid
    img = np.zeros((size, size, 4), np.float32)
    yy, xx = (np.mgrid[0:cell, 0:cell].astype(np.float32) + 0.5) / cell

    def smoothstep(a, b, x):
        t = np.clip((x - a) / (b - a), 0.0, 1.0)
        return t * t * (3.0 - 2.0 * t)

    # Transparent margin so bilinear/mip sampling never bleeds across cells.
    edge = np.minimum(np.minimum(xx, 1.0 - xx), np.minimum(yy, 1.0 - yy))
    margin = smoothstep(0.015, 0.09, edge)

    for row in range(grid):
        # Wide flat cluster of small blobs -> lumpy cauliflower silhouette that fills
        # most of the cell (billboard quads waste no fill on empty margin).
        nblobs = 19
        ang = rng.uniform(0.0, 2.0 * np.pi, nblobs)
        dist = rng.uniform(0.0, 1.0, nblobs) ** 0.55
        bx = 0.5 + 0.335 * dist * np.cos(ang)
        by = 0.52 + 0.20 * dist * np.sin(ang)         # squashed: wider than tall
        br = rng.uniform(0.075, 0.125, nblobs) * (1.2 - 0.45 * dist)  # small rim lobes
        bw = rng.uniform(0.6, 1.0, nblobs)
        ph = rng.uniform(0.0, 2.0 * np.pi, (nblobs, 2))
        amp = rng.uniform(0.025, 0.055, nblobs)
        ramp = rng.uniform(0.10, 0.18, nblobs)
        cast = np.array((0.97, 1.035, 0.99), np.float32) if row % 2 == 0 \
            else np.array((1.0, 0.975, 1.06), np.float32)
        for frame in range(grid):
            phase = 2.0 * np.pi * frame / grid
            density = np.zeros((cell, cell), np.float32)
            for i in range(nblobs):
                cx = bx[i] + amp[i] * np.sin(phase + ph[i, 0])
                cy = by[i] + amp[i] * np.cos(phase + ph[i, 1])
                r = br[i] * (1.0 + ramp[i] * np.sin(phase + ph[i, 0] + ph[i, 1]))
                density += bw[i] * np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2.0 * r * r))
            density /= np.percentile(density, 99.2)
            alpha = smoothstep(0.26, 0.66, density) * margin
            light = (0.58 + 0.36 * (1.0 - yy)) * (0.80 + 0.24 * np.clip(density, 0.0, 1.0))
            rgb = light[..., None] * cast[None, None, :]
            tile = np.concatenate([np.clip(rgb, 0.0, 1.0), alpha[..., None]], axis=-1)
            img[row * cell:(row + 1) * cell, frame * cell:(frame + 1) * cell] = tile

    out = (np.clip(img, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out, "RGBA").save(path, optimize=True)
    return path.stat().st_size


# ---------------------------------------------------------------------------
# 1. storm_debris_belt — 3 counter-rotating ara_trail ribbon belts (PLAN-STORM2 C2)
# ---------------------------------------------------------------------------
# (name, radius factor, y expression, orbital rad/t, ribbon thickness, ribbon time s,
#  carrier tint ARGB, HDR, ribbon gradient rgb stops)
DEBRIS_BELTS = (
    ("belt_low", 0.95, "2.2+randomC*1.8", 0.045, 0.40, 1.3,
     0xFF9C9CC4, (1.0, 0.95, 1.45),
     [(0.0, 0.61, 0.61, 0.77), (0.55, 0.42, 0.42, 0.62), (1.0, 0.30, 0.30, 0.48)]),
    ("belt_mid", 0.75, f"{H_EXPR}*0.45+(randomC-0.5)*4.0", -0.058, 0.34, 1.15,
     0xFFA8D0B6, (0.8, 1.3, 1.05),
     [(0.0, 0.66, 0.9, 0.76), (0.55, 0.46, 0.71, 0.58), (1.0, 0.30, 0.50, 0.42)]),
    ("belt_high", 0.55, f"{H_EXPR}*0.80+(randomC-0.5)*3.0", 0.072, 0.28, 1.0,
     0xFFD8DEFF, (1.7, 1.5, 2.3),
     [(0.0, 0.92, 0.93, 1.0), (0.55, 0.75, 0.75, 1.0), (1.0, 0.55, 0.53, 0.93)]),
)


def build_storm_debris_belt() -> FxBuilder:
    """eclipse:storm_debris_belt — anchored by StormPhotonFx at the storm base center.

    Three carrier-mote rings on the eclStormR/eclStormH function shapes, opposite
    orbital directions per belt (counter-rotation reads as the shells' shear), each
    carrier dragging a physics-lagged ARA_TRAIL ribbon (sky_launch_charge pattern).
    ~4-5 live ribbons per belt; maxParticles 5x3=15 (plan cap <= 24)."""
    fx = FxBuilder("storm_debris_belt")
    root = fx.empty("debris_root")

    for name, rf, y_expr, omega, thickness, time_s, tint, hdr, rgb in DEBRIS_BELTS:
        carrier = (fx.particle_emitter(
                name,
                duration=120, looping=True,
                start_lifetime=random_between(95, 135), start_speed=constant(0),
                start_size=nf3(random_between(0.13, 0.21), random_between(0.13, 0.21),
                               random_between(0.13, 0.21)),
                start_color=color(tint), simulation_space="World", max_particles=5)
            .child_of(root)
            .with_emission(rate=constant(BASE_RATES["storm_debris_belt"][name]))
            .with_shape(ring_shape(rf, y_expr, 1.5))
            .with_curves(
                velocity_over_lifetime=dict(
                    orbital_mode="AngularVelocity",
                    orbital=nf3(constant(0), constant(omega), constant(0))),
                # gentle vertical bob so the ribbons undulate instead of drawing circles
                noise=dict(frequency=0.3, quality="Noise2D",
                           position=nf3(constant(0.015), constant(0.05), constant(0.015))),
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.12, 0.95), (0.82, 0.85), (1.0, 0.0)],
                    [(0.0, 1.0, 1.0, 1.0), (1.0, 0.85, 0.85, 0.95)]),
                size_over_lifetime=eased([(0.0, 0.6), (0.2, 1.0), (0.85, 0.95), (1.0, 0.4)], "out"))
            .with_material(texture_material(CIRCLE, hdr=hdr))
            .with_renderer(vertex_sorting="NONE")
            # cull ~= 2.2 * authored r=24 (plan C2); covers site storms up to r~48
            .with_cull_box((-56.0, -4.0, -56.0), (56.0, 44.0, 56.0)))
        carrier.with_module("trails", {
            "ratio": F(1.0), "lifetime": constant(1.0),
            "dieWithParticles": B(0), "sizeAffectsWidth": B(0),
            "inheritParticleColor": B(1),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "space": "World", "alignment": "View",
                "thickness": F(thickness), "smoothness": I(5),
                "highQualityCorners": B(1),
                "time": F(time_s), "timeInterval": F(0.05), "minDistance": F(0.1),
                # widthOverTrail taper 0.5 -> 0 (plan C2), eased ease-out
                "thicknessOverLength": eased([(0.0, 1.0), (0.35, 0.55), (1.0, 0.0)], "out"),
                "colorOverLength": gradient(
                    [(0.0, 0.85), (0.55, 0.6), (1.0, 0.0)], rgb),
                "physicsSetting": {  # ribbons sag + whip in the churn
                    "warmup": F(0.0), "gravity": L([F(0.0), F(-0.02), F(0.0)]),
                    "inertia": F(0.35), "velocitySmoothing": F(0.75), "damping": F(0.78)},
                "renderer": ribbon_renderer(texture_material(CIRCLE, hdr=hdr)),
            }})
    return fx


# ---------------------------------------------------------------------------
# 2. storm_cloud_belt — GPU-instanced clump belt (IDEAS-STORM-2 #8)
# ---------------------------------------------------------------------------
# (name, latitude fraction, dome-contour radius factor ~= 1.06*cos(lat*PI/2),
#  orbital rad/t, size range, band tint ARGB)
CLOUD_BANDS = (
    ("band_low", 0.16, 1.03, 0.010, (2.8, 5.2), 0xFF9A9ABB),   # slate
    ("band_mid", 0.42, 0.84, -0.013, (2.4, 4.4), 0xFFA2C6B0),  # fog-green cast
    ("band_high", 0.66, 0.54, 0.016, (2.0, 3.6), 0xFFC9CFF2),  # violet-white
)


def build_storm_cloud_belt() -> FxBuilder:
    """eclipse:storm_cloud_belt — 3 counter-rotating latitude bands of GPU-instanced
    billboard puffs hugging the dome contour just OUTSIDE the shell (factors ~=
    1.06*cos(lat*PI/2), sphere storms have h == r), ~1080 steady / 1200 hard cap.

    IDEAS-STORM-2 #8 verbatim: useGPUInstance + parallelUpdate + parallelRendering
    (legal: no physics, no level access), alpha blend with vertexSorting NONE because
    the belt never sits between alpha shells, shade 0b, LDR only (no HDR on fog),
    lights module ENABLED at dim sky-light so puffs never render fullbright.
    Flipbook: SingleRow row = puff variant (memoized per particle), frameOverTime
    plays the 4-frame boil loop, startFrame desyncs the phase.

    STORM-MASS B8 adds `shred_racers`: three bearing-quantized shred packs at 1.02r
    orbiting at 2x the volume rim rate (spawn -2*eclStormSpin + orbital SPIN_UPPER) —
    the fast upper-strata layer of the parallax sandwich."""
    fx = FxBuilder("storm_cloud_belt")
    root = fx.empty("cloud_root")

    for name, lat, rf, omega, (s0, s1), tint in CLOUD_BANDS:
        (fx.particle_emitter(
                name,
                duration=100, looping=True, prewarm=60,  # warm start; prewarm < duration (hygiene law)
                start_lifetime=random_between(150, 210), start_speed=constant(0),
                start_size=nf3(random_between(s0, s1), random_between(s0, s1),
                               random_between(s0, s1)),
                start_color=color(tint), simulation_space="World",
                max_particles=400, parallel_update=True, parallel_rendering=True)
            .child_of(root)
            .with_emission(rate=constant(BASE_RATES["storm_cloud_belt"][name]))
            .with_shape(ring_shape(rf, f"{H_EXPR}*{lat}+(randomC-0.5)*3.0", 3.0))
            .with_curves(
                velocity_over_lifetime=dict(
                    orbital_mode="AngularVelocity",
                    orbital=nf3(constant(0), constant(omega), constant(0))),
                noise=dict(frequency=0.22, quality="Noise3D",
                           position=nf3(constant(0.12), constant(0.06), constant(0.12))),
                uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                                  frame_over_time=eased([(0.0, 0.0), (1.0, 1.0)]),
                                  start_frame=random_between(0, 4), cycle=4.0),
                color_over_lifetime=gradient(  # alpha ceiling 0.32 (fill-rate law)
                    [(0.0, 0.0), (0.14, 0.32), (0.82, 0.27), (1.0, 0.0)],
                    [(0.0, 1.0, 1.0, 1.0), (1.0, 0.92, 0.92, 0.97)]),
                size_over_lifetime=eased([(0.0, 0.82), (0.5, 1.0), (1.0, 0.9)]))
            .with_material(texture_material(PUFF_ATLAS, discard=0.02,
                                            blend=BLEND_ALPHA, depth_mask=False))
            .with_lights(sky=8, block=2)
            .with_renderer(use_gpu_instance=True, shade=False, vertex_sorting="NONE")
            .with_cull_box((-60.0, -6.0, -60.0), (60.0, 42.0, 60.0)))

    # STORM-MASS B8 `shred_racers`: ragged cloud scraps racing the UPPER strata just
    # outside the wall (1.02r) at 2× the rim rate — the second (and last) sanctioned
    # sync rate. Three bearing-quantized shred packs; spawn subtracts 2·eclStormSpin
    # and the +SPIN_UPPER orbital (rad/s) continues the same rate, so the packs track
    # the volume's fast upper strata while the slower bands drift beneath them — the
    # depth-parallax read of the B8 sandwich. Spawn heights min-capped into the box.
    shred_b = f"((floor(randomA*3)+0.5+(randomD-0.5)*0.60)/3*2*PI-2*{SPIN_EXPR})"
    shred_r = f"({R_EXPR}*1.02+(randomB-0.5)*2.0)"
    (fx.particle_emitter(
            "shred_racers",
            duration=100, looping=True, prewarm=30,
            start_lifetime=random_between(32, 52), start_speed=constant(0),
            start_size=nf3(random_between(1.1, 2.0), random_between(1.1, 2.0),
                           random_between(1.1, 2.0)),
            start_color=color(0xFF9AA0C0),  # pale slate carrier
            simulation_space="World", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_cloud_belt"]["shred_racers"]))
        .with_shape(function_shape(
            x=f"cos({shred_b})*{shred_r}",
            z=f"sin({shred_b})*{shred_r}",
            y=f"min({H_EXPR}*0.62,36)*(0.52+randomC*0.48)"))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(SPIN_UPPER), constant(0))),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.03), constant(0.06))),
            uv_animation=dict(tiles=(4, 4), animation="SingleRow",
                              frame_over_time=eased([(0.0, 0.0), (1.0, 1.0)]),
                              start_frame=random_between(0, 4), cycle=4.0),
            color_over_lifetime=gradient(  # alpha ceiling 0.30 (fill-rate law)
                [(0.0, 0.0), (0.14, 0.30), (0.78, 0.24), (1.0, 0.0)],
                [(0.0, 0.35, 0.36, 0.47), (1.0, 0.25, 0.26, 0.38)]),
            size_over_lifetime=eased([(0.0, 0.7), (0.4, 1.05), (1.0, 1.2)], "out"))
        .with_material(texture_material(PUFF_ATLAS, discard=0.02,
                                        blend=BLEND_ALPHA, depth_mask=False))
        .with_lights(sky=8, block=2)
        # LINT-ALPHA-NOSORT: unlike the GPU-instanced bands (grandfathered NONE by
        # design), the shreds are 30 CPU quads — DISTANCE sorting is free and keeps
        # the dark alpha scraps ordered against the bands behind them.
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-60.0, -6.0, -60.0), (60.0, 42.0, 60.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. storm_vein_bolt — HDR intra-wall lightning vein (PLAN-STORM2 C3, one-shot)
# ---------------------------------------------------------------------------
# 3-segment zig chained tip-to-tail in local space; StormPhotonFx anchors the fx at
# the W-B flash cell (0.92r on the flash bearing at latFrac*h) and yaws it so local
# +Z faces radially OUT of the storm — the zig plane (X/Y) lies tangent to the wall.
VEIN_SEGMENTS = (
    # (position, end, width, hdr)
    ((0.0, -5.2, 0.0), (1.5, 4.6, -0.7), 0.34, (2.3, 1.9, 3.2)),
    ((1.5, -0.6, -0.7), (-2.1, 4.4, 0.9), 0.30, (2.0, 1.7, 2.9)),
    ((-0.6, 3.8, 0.2), (1.3, 3.8, -0.9), 0.24, (1.8, 1.5, 2.6)),
)


def build_storm_vein_bolt() -> FxBuilder:
    """eclipse:storm_vein_bolt — fired once per fresh innerFlashSerial() when the flash
    belongs to the managed nearest storm; life ~8 t on an eased attack/decay width
    spike. Photon-less baseline = W-B's embedded ribbon + W-A's shell pulse (LAYER)."""
    fx = FxBuilder("storm_vein_bolt")
    root = fx.empty("vein_root")

    for idx, (pos, end, width, hdr) in enumerate(VEIN_SEGMENTS):
        (fx.beam_emitter(
                f"vein_seg{idx}",
                end=end, duration=8, looping=False,
                width=eased([(0.0, 0.0), (0.18, width), (0.45, width * 0.8), (1.0, 0.0)], "out"),
                color_nf=gradient(
                    [(0.0, 1.0), (0.55, 0.85), (1.0, 0.0)],
                    [(0.0, 0.93, 0.92, 1.0), (1.0, STM_DEEP[0], STM_DEEP[1], STM_DEEP[2])]))
            .child_of(root)
            .at(*pos)
            .with_material(texture_material(BEAM_CORE, hdr=hdr))
            .with_cull_box((-8.0, -7.0, -8.0), (8.0, 9.0, 8.0)))

    # Spark scatter along the vein line — randomA spans the vertical extent.
    (fx.particle_emitter(
            "vein_sparks",
            duration=10, looping=False,
            start_lifetime=random_between(5, 9), start_speed=constant(0),
            start_size=nf3(random_between(0.07, 0.15), random_between(0.07, 0.15),
                           random_between(0.07, 0.15)),
            start_color=color(0xFFBFD9FF),  # STM_ARC
            simulation_space="World", max_particles=16)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14), cycles=1)])
        .with_shape(function_shape(x="(randomB-0.5)*2.2",
                                   y="(randomA-0.5)*10.5",
                                   z="(randomC-0.5)*1.6"))
        .with_curves(
            noise=dict(frequency=1.1, quality="Noise2D", position=nf3(constant(0.08))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.75), (1.0, 0.0)],
                [(0.0, 0.93, 0.95, 1.0), (1.0, 0.65, 0.62, 1.0)]),
            size_over_lifetime=eased([(0.0, 0.55), (0.15, 1.0), (1.0, 0.0)], "out"))
        .with_material(texture_material(CIRCLE, hdr=(2.0, 1.8, 2.8)))
        .with_cull_box((-8.0, -7.0, -8.0), (8.0, 9.0, 8.0)))

    # One soft core flash centered on the cell — sells the inside-the-mass glow.
    (fx.particle_emitter(
            "core_glow",
            duration=8, looping=False,
            start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(3.4), start_color=color(0xFFB9C4FF),
            simulation_space="World", max_particles=2)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
        .with_shape(dot())
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (1.0, 0.0)],
                [(0.0, 0.92, 0.93, 1.0), (1.0, 0.62, 0.6, 1.0)]),
            size_over_lifetime=eased([(0.0, 0.7), (0.45, 1.15), (1.0, 1.0)], "out"))
        .with_material(texture_material(CIRCLE, hdr=(1.5, 1.3, 2.2)))
        .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0)))
    return fx


# ---------------------------------------------------------------------------
# 4. storm_skirt_dust — FirstCollision ground skirt (PLAN-STORM2 C4)
# ---------------------------------------------------------------------------
def build_storm_skirt_dust() -> FxBuilder:
    """eclipse:storm_skirt_dust — sparse heavy motes dropped just outside the wall base
    that fall with REAL collision and FirstCollision-stamp eclipse:storm_dust_puff on
    whatever terrain they strike (supply_drop_contrail ember pattern; parallelUpdate
    stays 0b — collision does level queries, FX_FORMAT §3.1). A faint ground-hug haze
    ring keeps the skirt from reading as disconnected dots."""
    fx = FxBuilder("storm_skirt_dust")
    root = fx.empty("skirt_root")

    (fx.particle_emitter(
            "skirt_motes",
            duration=120, looping=True,
            start_lifetime=random_between(26, 50), start_speed=constant(0),
            start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                           random_between(0.12, 0.2)),
            start_color=color(0xFF6E6E8C),  # dark slate grit
            simulation_space="World", max_particles=40,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_skirt_dust"]["skirt_motes"]))
        .with_shape(ring_shape(1.0, "2.6+randomC*1.6", 2.5))
        .with_physics(collision=True, removed_when_collided=True, gravity=0.5,
                      friction=0.98, collided_friction=0.6)
        .with_sub_emitters(sub_emitter("eclipse:storm_dust_puff",
                                       event="FirstCollision", probability=0.8))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(0.08)),  # kicked outward
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.8), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 0.52, 0.52, 0.66), (1.0, 0.36, 0.36, 0.5)]),
            size_over_lifetime=eased([(0.0, 0.7), (0.25, 1.0), (1.0, 0.85)], "out"))
        .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
        .with_lights(sky=7, block=2)
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-58.0, -12.0, -58.0), (58.0, 12.0, 58.0)))

    (fx.particle_emitter(
            "skirt_haze",
            duration=120, looping=True, prewarm=40,
            start_lifetime=random_between(90, 140), start_speed=constant(0),
            start_size=nf3(random_between(2.0, 3.4), random_between(2.0, 3.4),
                           random_between(2.0, 3.4)),
            start_color=color(0xFF7A7A99), simulation_space="World", max_particles=12)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_skirt_dust"]["skirt_haze"]))
        .with_shape(ring_shape(0.98, "0.4+randomC*1.4", 4.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.02), constant(0))),
            color_over_lifetime=gradient(  # alpha ceiling 0.12 — it is fog, not a wall
                [(0.0, 0.0), (0.2, 0.12), (0.8, 0.1), (1.0, 0.0)],
                [(0.0, 0.62, 0.62, 0.75), (1.0, 0.45, 0.45, 0.6)]),
            size_over_lifetime=eased([(0.0, 0.75), (0.6, 1.1), (1.0, 1.2)]))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=7, block=2)
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-58.0, -12.0, -58.0), (58.0, 12.0, 58.0)))
    return fx


# ---------------------------------------------------------------------------
# 5. storm_dust_puff — the FirstCollision stamp child
# ---------------------------------------------------------------------------
def build_storm_dust_puff() -> FxBuilder:
    """eclipse:storm_dust_puff — flat Horizontal ground puff + a pinch of grit, stamped
    by storm_skirt_dust motes where they strike terrain. Kept light: ~7 particles per
    stamp at <= ~0.6 stamps/s steady."""
    fx = FxBuilder("storm_dust_puff")

    (fx.particle_emitter(
            "puff",
            duration=20, looping=False,
            start_lifetime=random_between(16, 26), start_speed=random_between(0.05, 0.15),
            start_size=nf3(random_between(1.1, 1.9), random_between(1.1, 1.9),
                           random_between(1.1, 1.9)),
            start_color=color(0xFF8C8CA8), simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4), cycles=1)])
       .with_shape(circle(radius=0.35, thickness=1.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_lights(sky=8, block=3)
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.35), (1.0, 0.0)],
                [(0.0, 0.6, 0.6, 0.72), (1.0, 0.42, 0.42, 0.56)]),
            size_over_lifetime=eased([(0.0, 0.55), (0.55, 1.25), (1.0, 1.5)], "out"))
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 3.0, 4.0)))

    (fx.particle_emitter(
            "grit",
            duration=14, looping=False,
            start_lifetime=random_between(8, 14), start_speed=random_between(0.25, 0.5),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            start_color=color(0xFF5E5E78), simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3), cycles=1)])
       .with_shape(cone(angle=30.0, radius=0.25))
       .with_physics(collision=False, gravity=0.4)
       .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
       .with_lights(sky=8, block=3)
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, 0.45, 0.45, 0.58), (1.0, 0.32, 0.32, 0.45)]),
            size_over_lifetime=eased([(0.0, 1.0), (1.0, 0.35)], "in"))
       .with_cull_box((-3.0, -1.0, -3.0), (3.0, 3.0, 3.0)))
    return fx


# ---------------------------------------------------------------------------
# Quality-bar self-lint (PHOTON-QUALITY.md: eased curves, cull boxes, budgets)
# ---------------------------------------------------------------------------
def _iter_curve_segs(node):
    if isinstance(node, dict):
        if node.get("type") in ("curve", "random_curve"):
            data = node["data"]
            for key in ("curves", "curves0", "curves1"):
                if key in data:
                    yield [tuple(f.v for f in seg.items) for seg in data[key].items]
        for v in node.values():
            yield from _iter_curve_segs(v)
    elif isinstance(node, L):
        for v in node.items:
            yield from _iter_curve_segs(v)


def _is_lazy_linear(segs, tol=0.02):
    """True when EVERY bezier segment's control points are collinear with endpoints."""
    for (x0, y0, cx0, cy0, cx1, cy1, x1, y1) in segs:
        for cx, cy in ((cx0, cy0), (cx1, cy1)):
            dx, dy = x1 - x0, y1 - y0
            if abs(dx * (cy - y0) - dy * (cx - x0)) > tol and abs(dy) > tol:
                return False
    return True


def lint_tree(name, tree) -> list:
    problems = []
    emitters = 0
    for obj in tree["fxData"]["fxObjects"].items:
        kind, data = obj["type"], obj["data"]
        if kind == "empty":
            continue
        emitters += 1
        config = data["config"]
        where = f"{name}:{data['name']}"
        looping = config.get("looping", B(1)) == B(1)
        renderer = config.get("renderer", {})
        if looping and renderer.get("cull", {}).get("_enable") != B(1):
            problems.append(f"{where}: looping without a cull box")
        if kind == "particle_emitter":
            max_p = config.get("maxParticles", I(2000))
            if max_p.v >= 2000:
                problems.append(f"{where}: maxParticles at the 2000 default")
            if config.get("prewarm", I(0)).v > config.get("duration", I(100)).v:
                problems.append(f"{where}: prewarm > duration")
        for segs in _iter_curve_segs(obj):
            if _is_lazy_linear(segs):
                problems.append(f"{where}: lazy piecewise-linear curve")
    if emitters < 2 and name not in ("storm_dust_puff",):  # children may be minimal
        problems.append(f"{name}: hero effect with < 2 emitters")
    return problems


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "storm_debris_belt.fx": build_storm_debris_belt,
    "storm_cloud_belt.fx": build_storm_cloud_belt,
    "storm_vein_bolt.fx": build_storm_vein_bolt,
    "storm_skirt_dust.fx": build_storm_skirt_dust,
    "storm_dust_puff.fx": build_storm_dust_puff,
}


def main(argv) -> int:
    rc = 0
    if "--atlas" in argv or not PUFF_ATLAS_PATH.exists():
        size = generate_puff_atlas(PUFF_ATLAS_PATH)
        print(f"WROTE {PUFF_ATLAS_PATH.relative_to(REPO_ROOT)} ({size} B, 1024x1024 4x4)")
    for name, builder_fn in BUILDERS.items():
        builder = builder_fn()
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder.write(path)  # write() round-trip-validates
        proj_len = builder.write_fxproj(path.with_suffix(".fxproj"))
        errors = validate_file(path) + lint_tree(builder.name, read_fx_file(path))
        if errors:
            print(f"FAIL  {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B, "
                  f"fxproj {proj_len} B) — valid")
    return rc


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv[1:]))
