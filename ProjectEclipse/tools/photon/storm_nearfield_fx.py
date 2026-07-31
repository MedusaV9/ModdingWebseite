#!/usr/bin/env python3
"""storm_nearfield_fx — F-034 LOD-handover near-field suite + F-033 burst shockwave.

Committed fxlib source of truth (binary-blob diff law, FX_FORMAT.md §7) for the four
`.fx` blobs consumed by `stormfx/StormNearfieldFx.java` (rows registered by
`veilfx/StormNearfieldFxRows.java`), plus the editor-openable `.fxproj` sibling of
every blob (PHOTON-ADVANCED-1 §7):

  eclipse:storm_nearfield_wisps  WINDOWED loop — horizontal fog streaks RACING around
                                 the wall (fast counter-rotating ara-trail racers at
                                 1.04r + slow soft veil billboards), the transition-zone
                                 hero that fades in as the volumetric does (150-250).
  eclipse:storm_ground_scud      WINDOWED loop — ragged ground-hugging cloud shreds +
                                 low grit skimming the base ring (0.9-1.15r, y < 2.5).
  eclipse:storm_updraft_motes    WINDOWED loop — three standing updraft columns INSIDE
                                 the wall (bearing-quantized function shape at 0.55r):
                                 slow climbing motes + sparse HDR glints.
  eclipse:storm_burst_shockwave  ONE-SHOT (~50 t) — F-033 stage 2: double HDR ground
                                 ring + outward dust rim + flung sparks. Authored at
                                 the REFERENCE radius 24 (StormRegistry.DEFAULT_RADIUS);
                                 StormNearfieldFxRows' custom leg passes the live
                                 `radius / 24` through SpawnOptions.withScale, so this
                                 asset must NOT use the eclStormR expression shapes
                                 (executor scale x expression radius would double-scale).

RADIUS/HEIGHT ADAPTATION (PHOTON-ADVANCED-2 §1 Channel B): the three loops author
their rings as `function` shapes over the GLOBAL expression variables `eclStormR` /
`eclStormH` (letters only — Bacon `expr`); `StormPhotonFx.pushExprVars` keeps both
fresh (StormNearfieldFx shares the same pusher — single last-value cache, no fights).
Without Java (bare `/photon fx` preview) the `max(var, floor)` fallbacks give an
8-block dev ring.

PARALLAX SYNC (STORM-MASS B8): a third variable `eclStormSpin` carries the volume
raymarcher's rim rotation angle (0.07 rad/s + B7 churn escalation). Every bearing
term SUBTRACTS it (sign law in StormPhotonFx.stormSpinAngle) so spawns land in the
volume's rotating frame; the bearing-QUANTIZED emitters (updraft columns, the new
`rain_curtain` sheets) visibly orbit with the mass, uniform rings are unaffected.

LIVE DISTANCE BLENDING (PHOTON-ADVANCED-2 §1 Channel A): BASE_RATES below is the
frozen contract with `StormNearfieldFx.TUNED_BASE_RATES` — the manager multiplies
these authored per-emitter rates by the 250→150 handover ease x storm visibility and
restores pristine rates on release. Keep the two tables in sync when retuning.

Quality bar (v7, PHOTON-QUALITY.md): every curve is EASED (never collinear presets),
every loop carries a cull box + hard maxParticles, hero effects carry >= 2 emitters.
`main()` self-lints all three rules after building.

Run:  python3 tools/photon/storm_nearfield_fx.py

Deps: stdlib only.
"""
from fxlib import *  # noqa: F401,F403 - the authoring DSL is the point
from fxlib import B, I, L  # explicit for the raw module compounds

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
RING_SOFT = "eclipse:textures/particle/ring_soft.png"

# FX-STYLE-GUIDE §1 storm palette tokens (same table as build_storm_fx.py).
STM_SLATE = (0.227, 0.227, 0.333)   # #3A3A55
STM_ARC = (0.749, 0.851, 1.0)       # #BFD9FF
STM_DEEP = (0.353, 0.553, 0.933)    # #5A8DEE
FOG_GREEN = (0.455, 0.714, 0.580)   # interior-fog green family

# Channel-B expression variables (letters only) with dev fallbacks (8-block ring).
R_EXPR = "max(eclStormR,8)"
H_EXPR = "max(eclStormH,12)"
# STORM-MASS B8 parallax clock: continuous orbit angle (radians) at the volume's
# mid-strata RIM rate 0.07 rad/s (+ B7 churn escalation), pushed per tick by
# StormPhotonFx.stormSpinAngle(); un-driven previews read 0 (bands simply stand).
# SIGN LAW (jar-verified, see StormPhotonFx.stormSpinAngle): the raymarcher's world
# features turn by −spin in atan2(z,x) and Photon's AngularVelocity also turns θ by
# −orbital·0.05/tick (orbital is rad/SECOND) — so spawn bearings SUBTRACT the spin
# and the synced emitters carry POSITIVE orbital rates.
SPIN_EXPR = "eclStormSpin"
# The two sanctioned sync rates (Photon knows no differential rotation — one band =
# one angular rate): 1× rim for the rain curtain, 2× for upper-strata shreds.
SPIN_RIM = 0.07
SPIN_UPPER = 0.14

# The one-shot's authored reference radius — StormRegistry.DEFAULT_RADIUS.
REF_RADIUS = 24.0
# Central-axis updraft footprint of the burst (authored blocks, executor-scaled with
# everything else in the one-shot — never an eclStormR expression).
UPDRAFT_RADIUS = 0.9
# Cull top of the whole one-shot: the updraft slugs throw ~20 blocks, the dust wall ~12.
SHOCK_CULL_TOP = 40.0

# Frozen Channel-A contract with StormNearfieldFx.TUNED_BASE_RATES (see docstring).
# Rates are per-TICK (polish pass: rate x mean lifetime stays under maxParticles —
# racers 0.07x90=6.3/8, veils 0.10x115=11.5/14, shreds 0.35x60=21/26,
# grit 0.9x27=24/30, motes 0.65x75=49/60, glints 0.2x50=10/12).
BASE_RATES = {
    "storm_nearfield_wisps": {"wisp_racers": 0.07, "wisp_veils": 0.10,
                              "rain_curtain": 0.30},
    "storm_ground_scud": {"scud_shreds": 0.35, "scud_grit": 0.9},
    "storm_updraft_motes": {"updraft_motes": 0.65, "updraft_glints": 0.2},
}


# ---------------------------------------------------------------------------
# Eased-curve helpers (the v7 quality bar — build_storm_fx.py table)
# ---------------------------------------------------------------------------
def eased(points, mode="inout"):
    """NF curve through (t, value) points with genuinely eased bezier segments."""
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
    """RendererSetting compound for an EMBEDDED araConfig (build_storm_fx pattern)."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


def ring_shape(radius_factor, y_expr, radial_jitter):
    """Function shape: spawn points on the eclStormR-scaled ring at y_expr.

    B8: the bearing subtracts eclStormSpin so every spawn lands in the volume's
    rotating frame (structurally neutral for uniform-random bearings, but it keeps
    ALL bearing terms on the one shared clock)."""
    r = f"({R_EXPR}*{radius_factor}+(randomB-0.5)*{radial_jitter})"
    b = f"(randomA*2*PI-{SPIN_EXPR})"
    return function_shape(x=f"cos({b})*{r}",
                          z=f"sin({b})*{r}",
                          y=y_expr)


def fixed_ring_shape(radius, radial_jitter, y_expr):
    """Function shape ring at a FIXED authored radius (the one-shot: executor-scaled)."""
    r = f"({radius}+(randomB-0.5)*{radial_jitter})"
    return function_shape(x=f"cos(randomA*2*PI)*{r}",
                          z=f"sin(randomA*2*PI)*{r}",
                          y=y_expr)


# ---------------------------------------------------------------------------
# 1. storm_nearfield_wisps — racing wall streaks (F-034 transition-zone hero)
# ---------------------------------------------------------------------------
def build_storm_nearfield_wisps() -> FxBuilder:
    """eclipse:storm_nearfield_wisps — anchored by StormNearfieldFx at the storm base.

    `wisp_racers`: 8 fast carriers on 1.04r (counter-rotating against belt_low, -0.095
    rad/t — at r=24 that is ~2.3 blocks/t, they visibly RACE) each dragging a thin
    1.4 s slate→fog-green ara ribbon. `wisp_veils`: slow soft smoke billboards on the
    same band for body, alpha ceiling 0.22 (fill-rate law). `rain_curtain` (STORM-MASS
    B8): four falling streak-sheet cells at 0.92r locked to the volume rotation via
    eclStormSpin — the parallax-sandwich hero of this row."""
    fx = FxBuilder("storm_nearfield_wisps")
    root = fx.empty("nearfield_root")

    racers = (fx.particle_emitter(
            "wisp_racers",
            duration=110, looping=True,
            start_lifetime=random_between(70, 110), start_speed=constant(0),
            start_size=nf3(random_between(0.14, 0.22), random_between(0.14, 0.22),
                           random_between(0.14, 0.22)),
            start_color=color(0xFFAEC4B6),  # pale fog-green carrier
            simulation_space="World", max_particles=8)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_nearfield_wisps"]["wisp_racers"]))
        .with_shape(ring_shape(1.04, "3.0+randomC*11.0", 2.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.095), constant(0))),
            # vertical shudder so the streaks undulate against the wall shear
            noise=dict(frequency=0.45, quality="Noise2D",
                       position=nf3(constant(0.02), constant(0.07), constant(0.02))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.10, 0.9), (0.85, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.88, 0.95, 0.9)]),
            size_over_lifetime=eased([(0.0, 0.5), (0.15, 1.0), (0.85, 0.9), (1.0, 0.3)], "out"))
        .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        # LINT-ALPHA-NOSORT: alpha-blended carriers need per-frame ordering (8 quads —
        # the sort is free; additive would wash the fog-green carriers to white).
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-60.0, -4.0, -60.0), (60.0, 40.0, 60.0)))
    racers.with_module("trails", {
        "ratio": F(1.0), "lifetime": constant(1.0),
        "dieWithParticles": B(0), "sizeAffectsWidth": B(0),
        "inheritParticleColor": B(1),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.22), "smoothness": I(5),
            "highQualityCorners": B(1),
            # 0.9 s at ~2.3 blk/t orbital speed = ~20-block streak (polish pass:
            # 1.4 s drew near-half-circumference banners at the r=24 dev ring).
            "time": F(0.9), "timeInterval": F(0.05), "minDistance": F(0.1),
            "thicknessOverLength": eased([(0.0, 1.0), (0.4, 0.5), (1.0, 0.0)], "out"),
            "colorOverLength": gradient(
                [(0.0, 0.7), (0.5, 0.45), (1.0, 0.0)],
                [(0.0, 0.72, 0.82, 0.76), (0.55, FOG_GREEN[0], FOG_GREEN[1], FOG_GREEN[2]),
                 (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])]),
            "physicsSetting": {  # limp streamer whip, softer than the debris belts
                "warmup": F(0.0), "gravity": L([F(0.0), F(-0.01), F(0.0)]),
                "inertia": F(0.28), "velocitySmoothing": F(0.8), "damping": F(0.82)},
            "renderer": ribbon_renderer(texture_material(CIRCLE, blend=BLEND_ALPHA)),
        }})

    (fx.particle_emitter(
            "wisp_veils",
            duration=110, looping=True, prewarm=50,
            start_lifetime=random_between(90, 140), start_speed=constant(0),
            start_size=nf3(random_between(2.2, 3.8), random_between(2.2, 3.8),
                           random_between(2.2, 3.8)),
            start_color=color(0xFF97A8A0), simulation_space="World", max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_nearfield_wisps"]["wisp_veils"]))
        .with_shape(ring_shape(1.02, "2.0+randomC*9.0", 3.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(-0.05), constant(0))),
            noise=dict(frequency=0.2, quality="Noise3D",
                       position=nf3(constant(0.06), constant(0.04), constant(0.06))),
            color_over_lifetime=gradient(  # alpha ceiling 0.22 — it is fog, not a wall
                [(0.0, 0.0), (0.18, 0.22), (0.8, 0.18), (1.0, 0.0)],
                [(0.0, 0.78, 0.86, 0.82), (1.0, 0.5, 0.55, 0.6)]),
            size_over_lifetime=eased([(0.0, 0.7), (0.55, 1.05), (1.0, 1.15)]))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        # LINT-ALPHA-NOSORT: big overlapping veils are the worst-case popping source —
        # DISTANCE sorting keeps the layered fog read (dark veils cannot go additive).
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-60.0, -4.0, -60.0), (60.0, 40.0, 60.0)))

    # STORM-MASS B8 `rain_curtain`: falling streak sheets just INSIDE the wall (0.92r).
    # Four bearing-quantized curtain cells (~50 deg sheets with gaps — quantization is
    # what makes the rotation READABLE; a uniform ring + spin is statistically
    # invisible) locked to the volume's rotating frame: spawn bearing subtracts
    # eclStormSpin, orbital +SPIN_RIM (rad/s) continues the same rate after spawn.
    # Fall speed is linear velocity in BLOCKS/SECOND (the jar multiplies by 0.05/t);
    # −8..−11 b/s over a 40–60 t life drops a sheet 16–33 blocks — spawn heights are
    # min-capped so big site storms stay inside the shared cull box.
    curtain_b = f"((floor(randomA*4)+0.5+(randomD-0.5)*0.55)/4*2*PI-{SPIN_EXPR})"
    curtain_r = f"({R_EXPR}*0.92+(randomB-0.5)*2.5)"
    (fx.particle_emitter(
            "rain_curtain",
            duration=110, looping=True,
            start_lifetime=random_between(40, 60), start_speed=constant(0),
            start_size=nf3(random_between(0.10, 0.18), random_between(0.10, 0.18),
                           random_between(0.10, 0.18)),
            start_color=color(0xFF8CA0D6),  # rain-lit slate blue (STM_DEEP family)
            simulation_space="World", max_particles=24)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_nearfield_wisps"]["rain_curtain"]))
        .with_shape(function_shape(
            x=f"cos({curtain_b})*{curtain_r}",
            z=f"sin({curtain_b})*{curtain_r}",
            y=f"min({H_EXPR}*0.62,34)*(0.35+randomC*0.65)"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-11.0, -8.0), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(SPIN_RIM), constant(0))),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.0), constant(0.03))),
            color_over_lifetime=gradient(  # alpha ceiling 0.30 — sheets, not walls
                [(0.0, 0.0), (0.12, 0.30), (0.80, 0.26), (1.0, 0.0)],
                [(0.0, 0.48, 0.58, 0.83), (1.0, 0.28, 0.30, 0.45)]),
            size_over_lifetime=eased([(0.0, 0.7), (0.25, 1.0), (1.0, 0.85)], "out"))
        .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        # LINT-ALPHA-NOSORT: alpha streaks sort like the sibling veils; stretched
        # along the fall velocity so each quad reads as a rain streak, not a dot.
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=2.0,
                       length_scale=1.8, vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-60.0, -4.0, -60.0), (60.0, 40.0, 60.0)))
    return fx


# ---------------------------------------------------------------------------
# 2. storm_ground_scud — base-ring shreds + grit (F-034)
# ---------------------------------------------------------------------------
def build_storm_ground_scud() -> FxBuilder:
    """eclipse:storm_ground_scud — ragged low scraps skimming the base (0.9-1.15r,
    y < 2.5) with a slow outward creep, plus fast dark grit skimming even lower.
    Both LDR + terrain-lit (never fullbright fog at ground level)."""
    fx = FxBuilder("storm_ground_scud")
    root = fx.empty("scud_root")

    (fx.particle_emitter(
            "scud_shreds",
            duration=110, looping=True, prewarm=40,
            start_lifetime=random_between(45, 75), start_speed=constant(0),
            start_size=nf3(random_between(1.3, 2.4), random_between(1.3, 2.4),
                           random_between(1.3, 2.4)),
            start_color=color(0xFF8A8AA0),  # dusty slate
            simulation_space="World", max_particles=26)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_ground_scud"]["scud_shreds"]))
        .with_shape(ring_shape(1.0, "0.5+randomC*1.8", 3.5))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.07), constant(0)),
                radial=constant(0.06)),  # slow creep OUT of the wall foot
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.08), constant(0.02), constant(0.08))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.3), (0.8, 0.24), (1.0, 0.0)],
                [(0.0, 0.66, 0.66, 0.76), (1.0, 0.44, 0.44, 0.56)]),
            size_over_lifetime=eased([(0.0, 0.65), (0.4, 1.0), (1.0, 1.25)], "out"))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=7, block=2)
        # LINT-ALPHA-NOSORT: dusty slate shreds MUST stay alpha (additive would glow at
        # ground level) — DISTANCE sorting fixes the overlap ordering instead.
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-62.0, -6.0, -62.0), (62.0, 14.0, 62.0)))

    (fx.particle_emitter(
            "scud_grit",
            duration=110, looping=True,
            start_lifetime=random_between(20, 35), start_speed=constant(0),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            start_color=color(0xFF54546A),  # dark slate grit
            simulation_space="World", max_particles=30)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_ground_scud"]["scud_grit"]))
        .with_shape(ring_shape(1.02, "0.3+randomC*1.0", 3.0))
        .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.09), constant(0))),
            noise=dict(frequency=0.9, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.03), constant(0.06))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.42, 0.42, 0.55), (1.0, 0.3, 0.3, 0.42)]),
            size_over_lifetime=eased([(0.0, 1.0), (0.7, 0.8), (1.0, 0.35)], "in"))
        .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
        .with_lights(sky=7, block=2)
        # LINT-ALPHA-NOSORT: dark grit is the textbook "needs alpha + sorting" case.
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-62.0, -6.0, -62.0), (62.0, 14.0, 62.0)))
    return fx


# ---------------------------------------------------------------------------
# 3. storm_updraft_motes — standing interior updraft columns (F-034)
# ---------------------------------------------------------------------------
# Bearing-quantized function shape: floor(randomA*3)/3 pins every spawn onto one of
# THREE fixed bearings, so the columns read as columns (they don't smear into a ring)
# while the orbital swirl twists each column around its own vertical. B8: the cells
# subtract eclStormSpin — the three columns now PRECESS with the volume rotation
# (rim rate, full lap ~90 s) instead of standing while the mass turns behind them;
# their existing 0.05 rad/s orbital is close enough to the 0.07 rim rate that spawn
# and drift stay coherent over a mote lifetime.
COLUMN_BEARING = f"(floor(randomA*3)/3*2*PI-{SPIN_EXPR})"


def build_storm_updraft_motes() -> FxBuilder:
    """eclipse:storm_updraft_motes — three standing mote columns at 0.55r inside the
    wall: slow pale-green climbers (the mass) + sparse HDR arc glints (the beacon
    read that survives the interior fog)."""
    fx = FxBuilder("storm_updraft_motes")
    root = fx.empty("updraft_root")
    col_r = f"({R_EXPR}*0.55)"
    col_x = f"cos({COLUMN_BEARING})*{col_r}+(randomB-0.5)*2.5"
    col_z = f"sin({COLUMN_BEARING})*{col_r}+(randomC-0.5)*2.5"

    (fx.particle_emitter(
            "updraft_motes",
            duration=110, looping=True, prewarm=60,
            start_lifetime=random_between(60, 90), start_speed=constant(0),
            start_size=nf3(random_between(0.14, 0.24), random_between(0.14, 0.24),
                           random_between(0.14, 0.24)),
            start_color=color(0xFFBFD9CE),  # pale green-white
            simulation_space="World", max_particles=60)
        .child_of(root)
        .with_emission(rate=constant(BASE_RATES["storm_updraft_motes"]["updraft_motes"]))
        .with_shape(function_shape(x=col_x, z=col_z, y="0.5+randomD*3.0"))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.32, 0.5), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0))),
            noise=dict(frequency=0.3, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.0), constant(0.04))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.75), (0.75, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (1.0, 0.75, 0.9, 0.84)]),
            size_over_lifetime=eased([(0.0, 0.6), (0.3, 1.0), (1.0, 0.7)], "out"))
        .with_material(texture_material(CIRCLE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=3)
        # LINT-ALPHA-NOSORT: the mote columns are LDR mass (stacking law) — keep alpha,
        # sort the ≤60 quads (the sibling HDR glints stay additive-default unsorted).
        .with_renderer(vertex_sorting="DISTANCE")
        .with_cull_box((-48.0, -4.0, -48.0), (48.0, 50.0, 48.0)))

    (fx.particle_emitter(
            "updraft_glints",
            duration=110, looping=True,
            start_lifetime=random_between(40, 60), start_speed=constant(0),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            start_color=color(0xFFBFD9FF),  # STM_ARC
            simulation_space="World", max_particles=12)
        .child_of(root)
        .with_shape(function_shape(x=col_x, z=col_z, y="1.0+randomD*4.0"))
        .with_emission(rate=constant(BASE_RATES["storm_updraft_motes"]["updraft_glints"]))
        .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.6, 0.8), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.07), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.9), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, 0.95, 0.97, 1.0), (1.0, STM_DEEP[0], STM_DEEP[1], STM_DEEP[2])]),
            size_over_lifetime=eased([(0.0, 0.5), (0.2, 1.0), (1.0, 0.0)], "out"))
        .with_material(texture_material(CIRCLE, hdr=(1.5, 1.6, 1.9)))
        .with_renderer(vertex_sorting="NONE")
        .with_cull_box((-48.0, -4.0, -48.0), (48.0, 50.0, 48.0)))
    return fx


# ---------------------------------------------------------------------------
# 4. storm_burst_shockwave — F-033 stage 2 one-shot (~50 t, reference r = 24)
# ---------------------------------------------------------------------------
def build_storm_burst_shockwave() -> FxBuilder:
    """eclipse:storm_burst_shockwave — fired ONCE at the burst release moment by
    StormNearfieldFx (custom row leg scales by radius/24). Double HDR ground ring
    (main + 6 t echo — the double-pulse read) + outward dust rim + flung sparks."""
    fx = FxBuilder("storm_burst_shockwave")
    root = fx.empty("shock_root")

    # Main ring: horizontal ring_soft quad exploding 6 -> ~120 blocks across ~34 t.
    (fx.particle_emitter(
            "shock_ring",
            duration=50, looping=False,
            start_lifetime=constant(34), start_speed=constant(0),
            start_size=nf3(120.0), start_color=color(0xFFD8DEFF),
            simulation_space="World", max_particles=2)
        .child_of(root).at(0.0, 4.0, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1), cycles=1)])
        .with_shape(dot())
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.55, 0.5), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, STM_DEEP[0], STM_DEEP[1], STM_DEEP[2])]),
            size_over_lifetime=eased([(0.0, 0.05), (0.35, 0.75), (1.0, 1.0)], "out"))
        .with_material(texture_material(RING_SOFT, hdr=(1.9, 1.7, 2.6), blend=BLEND_ADDITIVE,
                                        depth_mask=False))
        .with_renderer(render_mode="Horizontal", shade=False, vertex_sorting="NONE")
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))

    # Echo ring: fainter, 6 t late, slightly slower — sells the double pulse.
    (fx.particle_emitter(
            "shock_ring_echo",
            duration=50, looping=False,
            start_lifetime=constant(30), start_speed=constant(0),
            start_size=nf3(90.0), start_color=color(0xFFAEB8E6),
            simulation_space="World", max_particles=2)
        .child_of(root).at(0.0, 3.0, 0.0)
        .with_emission(rate=constant(0.0), bursts=[burst(time=6, count=constant(1), cycles=1)])
        .with_shape(dot())
        .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.45), (0.6, 0.25), (1.0, 0.0)],
                [(0.0, 0.85, 0.88, 1.0), (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])]),
            size_over_lifetime=eased([(0.0, 0.04), (0.4, 0.7), (1.0, 1.0)], "out"))
        .with_material(texture_material(RING_SOFT, hdr=(1.4, 1.3, 2.0), blend=BLEND_ADDITIVE,
                                        depth_mask=False))
        .with_renderer(render_mode="Horizontal", shade=False, vertex_sorting="NONE")
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))

    # Dust rim: smoke kicked outward from the authored wall foot (radial velocity).
    (fx.particle_emitter(
            "shock_dust",
            duration=50, looping=False,
            start_lifetime=random_between(26, 40), start_speed=constant(0),
            start_size=nf3(random_between(1.6, 2.8), random_between(1.6, 2.8),
                           random_between(1.6, 2.8)),
            start_color=color(0xFF9A9AB8), simulation_space="World", max_particles=28)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=4, count=constant(26), cycles=1)])
        .with_shape(fixed_ring_shape(REF_RADIUS, 3.0, "0.6+randomC*2.0"))
        .with_curves(
            velocity_over_lifetime=dict(radial=constant(0.9)),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.03), constant(0.06))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.35), (0.75, 0.22), (1.0, 0.0)],
                [(0.0, 0.72, 0.72, 0.84), (1.0, 0.45, 0.45, 0.58)]),
            size_over_lifetime=eased([(0.0, 0.6), (0.45, 1.15), (1.0, 1.45)], "out"))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        # LINT-ALPHA-NOSORT: matches the sibling shock_dust_wall/shock_updraft, which
        # already sorted their dark alpha smoke by DISTANCE.
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))

    # Spark fling: HDR arc sparks riding the wavefront out + slightly up.
    (fx.particle_emitter(
            "shock_sparks",
            duration=50, looping=False,
            start_lifetime=random_between(18, 30), start_speed=constant(0),
            start_size=nf3(random_between(0.1, 0.2), random_between(0.1, 0.2),
                           random_between(0.1, 0.2)),
            start_color=color(0xFFBFD9FF),  # STM_ARC
            simulation_space="World", max_particles=20)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(18), cycles=1)])
        .with_shape(fixed_ring_shape(REF_RADIUS - 2.0, 2.0, "1.5+randomC*4.0"))
        .with_curves(
            velocity_over_lifetime=dict(
                radial=constant(1.3),
                linear=nf3(constant(0), random_between(0.1, 0.25), constant(0))),
            noise=dict(frequency=1.0, quality="Noise2D", position=nf3(constant(0.08))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 0.95, 0.97, 1.0), (1.0, 0.6, 0.58, 0.95)]),
            size_over_lifetime=eased([(0.0, 1.0), (0.5, 0.8), (1.0, 0.0)], "in"))
        .with_material(texture_material(CIRCLE, hdr=(2.2, 2.0, 3.0)))
        .with_renderer(vertex_sorting="NONE")
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))

    # Dust wall: 30 sprites off the SAME authored reference ring as the rim (no
    # eclStormR — the row leg's radius/24 executor scale carries this asset), but thrown
    # UP on an eased 0.5 -> 0 updraft (~12 blocks) while they swell 1.2 -> 2.6. The rim
    # says how far the wave went; the wall says how hard it hit. Alpha ceiling 0.32.
    (fx.particle_emitter(
            "shock_dust_wall",
            duration=50, looping=False,
            start_lifetime=random_between(34, 46), start_speed=constant(0),
            start_size=nf3(random_between(1.7, 2.9), random_between(1.7, 2.9),
                           random_between(1.7, 2.9)),
            start_color=color(0xFF3A3A55),  # STM_SLATE birth tint
            simulation_space="World", max_particles=32)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=3, count=constant(30), cycles=1)])
        .with_shape(fixed_ring_shape(REF_RADIUS, 3.0, "0.4+randomC*1.6"))
        .with_curves(
            velocity_over_lifetime=dict(  # kicked up, then stalled by its own mass
                linear=nf3(constant(0),
                           eased([(0.0, 0.5), (0.55, 0.42), (1.0, 0.0)], "out"),
                           constant(0))),
            noise=dict(frequency=0.3, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.32), (0.7, 0.22), (1.0, 0.0)],
                [(0.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2]), (1.0, 0.16, 0.16, 0.24)]),
            size_over_lifetime=eased([(0.0, 1.2), (0.5, 2.0), (1.0, 2.6)], "out"))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        .with_renderer(vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))

    # Central updraft: a dozen dark slugs racing up the axis to ~20 blocks — the burst
    # venting straight up out of the eye. Twelve particles and an alpha ceiling of 0.42
    # keep the stacking law: this layer is MASS, so it stays dark and LDR (the two HDR
    # rings above own all the light in this asset).
    (fx.particle_emitter(
            "shock_updraft",
            duration=50, looping=False,
            start_lifetime=random_between(11, 16),
            start_speed=random_between(4.0, 6.0),
            start_size=nf3(random_between(0.9, 1.7), random_between(0.9, 1.7),
                           random_between(0.9, 1.7)),
            start_color=color(0xFF2E2E44), simulation_space="World", max_particles=14)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(12), cycles=1)])
        # A near-zero-angle cone IS the tight central cylinder here: it launches along
        # +Y, where a `cylinder` shape would fire the slugs radially outward instead.
        .with_shape(cone(angle=4.0, radius=UPDRAFT_RADIUS))
        .with_curves(
            velocity_over_lifetime=dict(  # spent fast, then hangs at the top
                speed_modifier=eased([(0.0, 1.0), (0.55, 0.3), (1.0, 0.04)], "out")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.1, 0.42), (0.65, 0.3), (1.0, 0.0)],
                [(0.0, 0.18, 0.18, 0.27), (1.0, 0.1, 0.1, 0.16)]),
            size_over_lifetime=eased([(0.0, 0.6), (0.35, 1.0), (1.0, 0.55)], "out"))
        .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
        .with_lights(sky=8, block=2)
        .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                       length_scale=2.4, vertex_sorting="DISTANCE", shade=True)
        .with_cull_box((-150.0, -6.0, -150.0), (150.0, SHOCK_CULL_TOP, 150.0)))
    return fx


# ---------------------------------------------------------------------------
# Quality-bar self-lint (build_storm_fx.py table)
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
    if emitters < 2:
        problems.append(f"{name}: hero effect with < 2 emitters")
    return problems


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "storm_nearfield_wisps.fx": build_storm_nearfield_wisps,
    "storm_ground_scud.fx": build_storm_ground_scud,
    "storm_updraft_motes.fx": build_storm_updraft_motes,
    "storm_burst_shockwave.fx": build_storm_burst_shockwave,
}


def main(argv) -> int:
    rc = 0
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
