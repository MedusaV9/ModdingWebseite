#!/usr/bin/env python3
"""build_world_fx — PH-WORLD Photon assets (IDEAS-world.md #4, #5, #6b, #7, #8-crown).

Committed fxlib source of truth (binary-blob diff law, FX_FORMAT.md §7) for the eight
landmark/world `.fx` blobs:

  concept 4  eclipse:supply_drop_contrail  crate-entity ara ribbon + ember shed whose
                                           FirstCollision sub-emitter stamps the dust ring
             eclipse:supply_landing_dust     the stamped ring (also usable standalone)
  concept 5  eclipse:sky_launch_charge     3 carriers FLY the golden-angle helix
                                           (function shape t*4*PI r1.4 = the server
                                           spiral) dragging ara ribbons + apex burst
             eclipse:sky_launch_contrail   launched-player ara ribbon + slip rings
  concept 7  eclipse:breach_ash_geyser     WINDOWED loop: breathing ash geyser with REAL
                                           lip-collision bounce (parallelUpdate 0b law)
             eclipse:breach_ember_updraft  WINDOWED loop: 4 corkscrew ember ribbon risers
  concept 6b eclipse:end_void_wisps        WINDOWED loop: 1200 GPU-instanced void wisps
                                           in the rim-band cylinder (parallel both paths)
  concept 8  eclipse:storm_crown_halo      WINDOWED loop: shapeArc Loop pearl-string ring
                                           above sphere-storm crowns

Every loop carries a renderer cull box + hard maxParticles (INTEGRATION.md §4 loop law);
collision emitters keep parallelUpdate 0b (FX_FORMAT §3.1/§3.3 — collision does real
level queries, forbidden on the parallel path). Textures are limited to the two
Photon-bundled particles (circle.png / smoke.png).

Run:  python3 tools/photon/build_world_fx.py     # writes + validates all 8 assets

FX-WAVE-13 C4 PASS — SCOPED TO CONCEPTS 4 AND 5 ONLY (`supply_drop_contrail`,
`supply_landing_dust`, `sky_launch_charge`, `sky_launch_contrail`). `breach_*` is A6's,
`end_void_wisps` is C1's GPU-instancing work and `storm_crown_halo` is F-096's; all four
are byte-identical after this pass (verified by regenerating and diffing). Changes:

  1. UNITS. `startSpeed`, `velocityOverLifetime.linear` and `orbital` are per-SECOND
     (Photon applies them as `value x 0.05` per tick) — the slip B6 found in
     `ceremony_fx.py`. `sky_launch_charge` was the headline: `HELIX_VY`/`HELIX_OMEGA`
     were derived per-TICK straight out of `SkyLauncher.tickCharges`, so the three
     carriers climbed 12.5 cm of the server spiral's 2.5 blocks and swept 0.63 rad of
     its 4*PI — the "solid triple helix" the docstring promises was a 12 cm stub around
     the pad. Both constants now divide by `CHARGE_TICKS * 0.05`, which reproduces the
     server spiral exactly. The landing skirt, the apex burst and the shed embers are
     likewise back-solved from the distance their own comments promise.
  2. `random_gradient` (via `varied()`) on every crowded emitter here: 60 shed embers,
     the 36-quad dust skirt, the 20-streak apex burst and the 60 slip-ring quads.
  3. Dark birth tints (V2.1 stacking law) on those same four.
  4. HDR clamped to the wave-13 ceiling 1.45, hue ratio preserved (the wind-light
     carriers, their ribbon, the apex burst and the pop sparks sat at 1.6-2.2).
  5. Timing snap: these four are travel-driven (ara ribbons + ballistic bursts) rather
     than envelope-driven; the units fix IS the attack fix, so no curve was re-cut.
"""
from fxlib import *  # noqa: F401,F403 - the authoring DSL is the point
from fxlib import B, F, I, L  # explicit for the raw module compounds

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"

# ---------------------------------------------------------------------------
# WAVE-13 C4 levers — supply_* / sky_launch_* ONLY (concepts 4 and 5). The breach_*
# (A6), end_void_wisps (C1) and storm_crown_halo (F-096) builders below belong to
# other wave-13 teams and are byte-identical after this pass, so these helpers are
# scoped by use, not by file. Same idiom B6 landed in `ceremony_fx.py`.
# ---------------------------------------------------------------------------
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


#: Birth tints (V2.1 stacking law): darker than the ramp's own fade target, so the
#: shed embers / dust skirt / apex burst open on a bruise instead of a white bead.
EMBER_BIRTH = (0.18, 0.08, 0.03)   # supply ember family, below 0xFFBF59
EARTH_BIRTH = (0.14, 0.12, 0.09)   # landing dust — damp soil, not gray fog
WIND_BIRTH = (0.07, 0.14, 0.18)    # sky-launch cold wind-light, below 0x7FE7FF


def pts_curve(points, lock=True):
    """NF curve through (t, value) points — linear bezier segments (build_rift_fx helper)."""
    lo = min(v for _, v in points)
    hi = max(v for _, v in points)
    span = (hi - lo) or 1.0
    norm = [(t, (v - lo) / span) for t, v in points]
    segments = []
    for (x0, y0), (x1, y1) in zip(norm, norm[1:]):
        segments.append((x0, y0,
                         x0 + (x1 - x0) / 3.0, y0 + (y1 - y0) / 3.0,
                         x0 + 2.0 * (x1 - x0) / 3.0, y0 + 2.0 * (y1 - y0) / 3.0,
                         x1, y1))
    return curve(lo, hi if hi != lo else lo + 1.0, segments, lock=lock)


def ribbon_renderer(material_entry):
    """RendererSetting compound for an EMBEDDED araConfig (mirrors fxlib._init_renderer);
    written explicitly so ribbons never fall back to the MISSING (pink) material."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# Concept 4 — supply drop: descent contrail + landing dust ring
# ---------------------------------------------------------------------------
def build_supply_drop_contrail() -> FxBuilder:
    """eclipse:supply_drop_contrail — attached to the falling crate entity
    (PhotonBridge.spawnOnEntity from SupplyBeamClient); the EntityEffectExecutor
    auto-destroys the runtime when the crate dies on landing, so looping is safe."""
    fx = FxBuilder("supply_drop_contrail")

    # Main contrail: a world-space ara ribbon sagging behind the crate.
    (fx.ara_trail_emitter(
            "crate_ribbon",
            duration=160, looping=True,
            space="World", alignment="View", thickness=0.4, smoothness=4,
            time=1.4, time_interval=0.05, min_distance=0.05,
            texture_mode="Stretch",
            thickness_over_length=pts_curve([(0.0, 1.0), (1.0, 0.1)]),
            # #FFE2B0 -> #B37DFF -> transparent
            color_over_length=gradient(
                [(0.0, 0.9), (0.55, 0.65), (1.0, 0.0)],
                [(0.0, 1.0, 0.886, 0.69), (0.5, 0.702, 0.49, 1.0),
                 (1.0, 0.702, 0.49, 1.0)]),
            # tail sags — reads like a real drop streamer
            physics=dict(gravity=(0.0, -0.02, 0.0), inertia=0.2, damping=0.8))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.2, 1.0)))
       # Entity-local box: the tail hangs ABOVE the falling anchor (crate drops ~60).
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 40.0, 8.0)))

    # Sparse embers shed off the crate — these carry the landing detection: the first
    # ones to strike the ground FirstCollision-stamp the dust ring exactly where the
    # crate lands (even down a ravine). removedWhenCollided keeps post-landing cost 0.
    (fx.particle_emitter(
            "ember_shed",
            duration=160, looping=True,
            start_lifetime=random_between(30, 50),
            # WAVE-13 units: blocks/SECOND. 0.05-0.15 shed the embers 7-37 cm, i.e. they
            # stayed welded to the crate hull. The shed scatter wants ~0.5-1.5 blocks
            # across a 30-50t life (the fall itself comes from inheritVelocity+gravity,
            # so this stays small on purpose): 0.3-0.8 x 0.05 x 30..50t = 0.45..2.0.
            start_speed=random_between(0.3, 0.8),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=60,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=constant(0.8))
       .with_shape(sphere(radius=0.5))
       .with_module("inheritVelocity",
                    {"mode": "CURRENT", "multiply": constant(0.85)})  # fall WITH the crate
       .with_physics(collision=True, removed_when_collided=True, gravity=0.12)
       .with_sub_emitters(sub_emitter("eclipse:supply_landing_dust",
                                      event="FirstCollision", probability=0.12))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 0.9, 0.5)))
       # 60 embers trailing one crate: birth tint + a cooler sibling ramp so the shed
       # reads as individual sparks instead of one amber smear behind the hull.
       .with_curves(color_over_lifetime=varied(  # amber -> red -> out
            [(0.0, 0.9), (0.7, 0.75), (1.0, 0.0)],
            [(0.0, *EMBER_BIRTH), (0.15, 1.0, 0.75, 0.35), (0.6, 0.9, 0.3, 0.12),
             (1.0, 0.5, 0.1, 0.05)],
            [(0.0, *EMBER_BIRTH), (0.3, 0.9, 0.3, 0.12), (1.0, *EMBER_BIRTH)],
            alpha_alt=[(0.0, 0.7), (0.55, 0.8), (1.0, 0.0)]))
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, 64.0, 8.0)))
    return fx


def build_supply_landing_dust() -> FxBuilder:
    """eclipse:supply_landing_dust — stamped BY the contrail's FirstCollision sub-emitter
    at the landing surface (no landing packet exists and none is needed)."""
    fx = FxBuilder("supply_landing_dust")

    # Radial dust skirt (cheap: no collision needed on dust).
    (fx.particle_emitter(
            "dust_ring",
            duration=20, looping=False,
            start_lifetime=random_between(16, 26),
            # WAVE-13 units: a crate hitting the ground throws its skirt 1-3 blocks, not
            # the 0.4-1.2 the old blocks/SECOND value bought off an r=0.8 ring.
            # 1.2-2.2 x 0.05 x 16..26t = 0.96..2.86 blocks.
            start_speed=random_between(1.2, 2.2),
            start_size=nf3(random_between(0.16, 0.3), random_between(0.16, 0.3),
                           random_between(0.16, 0.3)),
            simulation_space="World", max_particles=40)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(36), cycles=1)])
       .with_shape(circle(radius=0.8, thickness=0.0))
       .with_physics(collision=False, gravity=0.06)
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       # 36 overlapping alpha smoke quads off one ring: without per-particle ramps the
       # skirt banks into a single flat disc of dust.
       .with_curves(color_over_lifetime=varied(  # earth tones in-hold-out
            [(0.0, 0.0), (0.15, 0.7), (1.0, 0.0)],
            [(0.0, *EARTH_BIRTH), (0.2, 0.45, 0.38, 0.3), (1.0, 0.3, 0.25, 0.2)],
            [(0.0, *EARTH_BIRTH), (0.3, 0.3, 0.25, 0.2), (1.0, *EARTH_BIRTH)],
            alpha_alt=[(0.0, 0.0), (0.25, 0.55), (1.0, 0.0)])))

    # 10 additive HDR pop sparks, cone up.
    (fx.particle_emitter(
            "pop_sparks",
            duration=20, looping=False,
            start_lifetime=random_between(8, 14),
            # WAVE-13 units: 0.16-0.63 blocks was a pop that never left the dust ring.
            # 2.0-4.0 x 0.05 x 8..14t = 0.8..2.8 blocks up the 25-degree cone.
            start_speed=random_between(2.0, 4.0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10), cycles=1)])
       .with_shape(cone(angle=25.0, radius=0.3))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.8, 1.4, 0.9)))
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (1.0, 0.0)],
            [(0.0, *EMBER_BIRTH), (0.12, 1.0, 0.9, 0.6), (1.0, 0.85, 0.4, 0.15)],
            [(0.0, *EMBER_BIRTH), (0.2, 0.85, 0.4, 0.15), (1.0, *EMBER_BIRTH)],
            alpha_alt=[(0.0, 0.8), (0.4, 0.7), (1.0, 0.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 5 — sky launcher: charge helix + launch contrail
# ---------------------------------------------------------------------------
# SkyLauncher.CHARGE_TICKS — the asset duration IS the charge window (cancel needs no
# stop wiring: a walk-off simply means the server never sends the launch cue).
CHARGE_TICKS = 15
# Server spiral (SkyLauncher.tickCharges): angle = progress*4*PI, r 1.4, y progress*2.5.
# WAVE-13 units: `velocityOverLifetime.linear` and `orbital` are both applied as
# value x 0.05 per TICK, i.e. they are per-SECOND quantities. Authoring them per-TICK
# (the old two lines) ran the whole helix at 1/20 speed: the carriers climbed 12.5 cm
# of the server spiral's 2.5 blocks and swept 0.63 rad of its 4*PI, so the ribbons drew
# a stub instead of the triple helix. TICKS_PER_SECOND back-converts both.
TICK_SECONDS = 0.05
HELIX_VY = 2.5 / (CHARGE_TICKS * TICK_SECONDS)            # blocks/SECOND straight up
HELIX_OMEGA = 4.0 * 3.14159265 / (CHARGE_TICKS * TICK_SECONDS)  # rad/SECOND (4 PI/charge)


def build_sky_launch_charge() -> FxBuilder:
    """eclipse:sky_launch_charge — block-anchored at the pad; 3 carriers born on the
    r=1.4 ring via the function shape (the exact server-spiral expressions), then FLOWN
    up the golden-angle helix by orbital+linear velocity so their ara ribbons draw the
    solid triple-helix the END_ROD dots only sketch."""
    fx = FxBuilder("sky_launch_charge")

    carriers = (fx.particle_emitter(
            "helix_carriers",
            duration=CHARGE_TICKS, looping=False,
            start_lifetime=constant(CHARGE_TICKS), start_speed=constant(0.01),
            start_size=nf3(0.12), simulation_space="World", max_particles=3)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3), cycles=1)])
        # FX_FORMAT §6 expression shape: the server spiral verbatim; randomA*2*PI stands
        # in for the three golden-angle arm phases (burst t=0 evaluates t=0).
        .with_shape(function_shape(
            x="1.4*cos(t*4*PI + randomA*2*PI)",
            z="1.4*sin(t*4*PI + randomA*2*PI)",
            y="t*2.5"))
        # Fly the helix: 4PI sweep + 2.5 climb over the 15t charge = the server spiral.
        .with_curves(velocity_over_lifetime=dict(
            linear=nf3(constant(0), constant(HELIX_VY), constant(0)),
            orbital_mode="AngularVelocity",
            orbital=nf3(constant(0), constant(HELIX_OMEGA), constant(0))))
        .with_material(texture_material(CIRCLE, hdr=hdr(1.5, 2.2, 2.0)))  # cold wind-light
        .with_cull_box((-6.0, -1.0, -6.0), (6.0, 8.0, 6.0)))
    carriers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(1.0),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.22),
            "smoothness": I(6),
            "highQualityCorners": B(1),
            "time": F(0.8), "timeInterval": F(0.05),
            # #E8FFF6 -> #7FE7FF -> transparent
            "colorOverLength": gradient(
                [(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)],
                [(0.0, 0.91, 1.0, 0.965), (0.5, 0.498, 0.906, 1.0),
                 (1.0, 0.498, 0.906, 1.0)]),
            "physicsSetting": {
                "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                "inertia": F(0.15), "velocitySmoothing": F(0.75), "damping": F(0.85)},
            "renderer": ribbon_renderer(texture_material(CIRCLE, hdr=hdr(1.5, 2.2, 2.0))),
        }})

    # Release flash at t=14, synced to the throw (charge fires at tick 15).
    (fx.particle_emitter(
            "apex_burst",
            duration=CHARGE_TICKS, looping=False,
            start_lifetime=random_between(8, 14),
            # WAVE-13 units: the release flash must clear the pad by a few blocks to
            # sell the throw; 1.2-2.0 blocks/SECOND only bought 0.48-1.4 over an 8-14t
            # life. 4.0-8.0 x 0.05 x 8..14t = 1.6..5.6 blocks up the cone. This also
            # feeds the StretchedBillboard velocityScale, so the streaks now HAVE length.
            start_speed=random_between(4.0, 8.0),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=24)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=CHARGE_TICKS - 1, count=constant(20), cycles=1)])
       .with_shape(cone(angle=20.0, radius=0.4))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 2.0, 2.2)))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.6,
                      length_scale=2.4, vertex_sorting="NONE")
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (1.0, 0.0)],
            [(0.0, *WIND_BIRTH), (0.1, 1.0, 1.0, 1.0), (1.0, 0.55, 0.9, 1.0)],
            [(0.0, *WIND_BIRTH), (0.18, 0.55, 0.9, 1.0), (1.0, *WIND_BIRTH)],
            alpha_alt=[(0.0, 0.75), (0.5, 0.6), (1.0, 0.0)]))
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 8.0, 6.0)))
    return fx


def build_sky_launch_contrail() -> FxBuilder:
    """eclipse:sky_launch_contrail — attached to the launched player (entity executor
    auto-cleans if they die mid-flight); finite 70t so no stop wiring is needed."""
    fx = FxBuilder("sky_launch_contrail")

    (fx.ara_trail_emitter(
            "launch_ribbon",
            duration=70, looping=False,
            space="World", alignment="View", thickness=0.5, smoothness=5,
            time=1.8, time_interval=0.05,
            thickness_over_length=pts_curve([(0.0, 1.0), (1.0, 0.05)]),
            # white -> #9BE8FF -> transparent
            color_over_length=gradient(
                [(0.0, 0.95), (0.6, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.45, 0.608, 0.91, 1.0),
                 (1.0, 0.608, 0.91, 1.0)]),
            physics=dict(gravity=(0.0, -0.01, 0.0), inertia=0.25, damping=0.8))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.3, 1.9, 2.1)))
       # The flyer climbs fast — the world-space tail hangs BELOW the anchor.
       .with_cull_box((-10.0, -48.0, -10.0), (10.0, 10.0, 10.0)))

    # Speed rings slipping past the flyer: one 6-particle ring burst every 6t, Local
    # space shell so each ring is laid at the flyer's position and left behind visually
    # by the climb (no inheritVelocity by design).
    (fx.particle_emitter(
            "slip_rings",
            duration=70, looping=False,
            start_lifetime=random_between(10, 16), start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="Local", max_particles=60)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(6), cycles=10, interval=6)])
       .with_shape(circle(radius=0.7, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 1.1, 1.2)))
       # 10 stacked rings x 6 = 60 quads laid along one climb line: per-particle ramps
       # keep the rings distinguishable as they slip past the flyer.
       .with_curves(color_over_lifetime=varied(
            [(0.0, 0.0), (0.25, 0.7), (1.0, 0.0)],
            [(0.0, *WIND_BIRTH), (0.3, 0.75, 0.95, 1.0), (1.0, 0.55, 0.8, 1.0)],
            [(0.0, *WIND_BIRTH), (0.4, 0.55, 0.8, 1.0), (1.0, *WIND_BIRTH)],
            alpha_alt=[(0.0, 0.0), (0.35, 0.55), (1.0, 0.0)]))
       .with_cull_box((-10.0, -48.0, -10.0), (10.0, 10.0, 10.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept 7 — nether breach: ash geyser + ember ribbon updrafts (WINDOWED loops)
# ---------------------------------------------------------------------------
# Two eruption "breaths" per 8s cycle: shared emitter-t envelope for speed AND rate.
GEYSER_HUMPS = [(0.0, 0.2, 0.15, 1.0, 0.3, 0.25, 0.5, 0.2),
                (0.5, 0.2, 0.62, 0.9, 0.8, 0.2, 1.0, 0.1)]


def build_breach_ash_geyser() -> FxBuilder:
    """eclipse:breach_ash_geyser — anchored at the chimney mouth (centerX, lipY-6,
    centerZ) by BreachAmbience. Ash arcs out of the throat, clips the overhanging lip
    ring / funnel wall (REAL Photon collision — the module Quasar can't match) and
    scatters over the crimson-creep halo. The bounce IS the effect."""
    fx = FxBuilder("breach_ash_geyser")

    (fx.particle_emitter(
            "geyser_core",
            duration=160, looping=True, prewarm=0,
            start_lifetime=random_between(40, 70),
            start_speed=curve(0.3, 1.6, GEYSER_HUMPS),  # two eruption breaths / cycle
            start_size=nf3(random_between(0.15, 0.35), random_between(0.15, 0.35),
                           random_between(0.15, 0.35)),
            simulation_space="World", max_particles=220,
            parallel_update=False)  # collision law (FX_FORMAT §3.1) — NEVER parallel
       # rate pulses WITH the speed envelope = geyser breath; no bursts (loop-safe).
       .with_emission(rate=curve(0.4, 6.0, GEYSER_HUMPS))
       .with_shape(cylinder(radius=2.2, thickness=0.35))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.11,
                     friction=0.985, collided_friction=0.6, bounce_chance=0.75,
                     bounce_rate=0.35, bounce_spread=0.25)
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)  # lit like real ash
       .with_curves(color_over_lifetime=gradient(  # #5A4A46 -> #2B2224
            [(0.0, 0.0), (0.15, 0.8), (1.0, 0.0)],
            [(0.0, 0.353, 0.29, 0.275), (1.0, 0.169, 0.133, 0.141)]))
       .with_cull_box((-24.0, -10.0, -24.0), (24.0, 26.0, 24.0)))

    # Cheap soul-fire shimmer parked in the throat — the light read under the geyser.
    (fx.particle_emitter(
            "vent_glow",
            duration=160, looping=True,
            start_lifetime=random_between(20, 30),
            start_speed=random_between(0.02, 0.06),
            start_size=nf3(random_between(0.1, 0.2), random_between(0.1, 0.2),
                           random_between(0.1, 0.2)),
            simulation_space="World", max_particles=24)
       .with_emission(rate=constant(0.6))
       .with_shape(sphere(radius=1.6))
       .with_material(texture_material(CIRCLE, hdr=(0.8, 1.3, 1.6)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
            [(0.0, 0.45, 0.85, 1.0), (1.0, 0.2, 0.5, 0.7)]))
       .with_cull_box((-4.0, -8.0, -4.0), (4.0, 8.0, 4.0)))
    return fx


def build_breach_ember_updraft() -> FxBuilder:
    """eclipse:breach_ember_updraft — same anchor: 4 ember carriers corkscrew up the
    thermal out of the bowl, dragging lagging ara ribbons that whip in the updraft."""
    fx = FxBuilder("breach_ember_updraft")

    risers = (fx.particle_emitter(
            "ember_risers",
            duration=200, looping=True,
            start_lifetime=constant(190), start_speed=constant(0),
            start_size=nf3(0.1), simulation_space="World", max_particles=4)
        .with_emission(rate=constant(0.021))  # ~ one new riser as one dies
        .with_shape(circle(radius=3.5, thickness=0.2))
        .with_curves(
            velocity_over_lifetime=dict(  # corkscrew thermal
                linear=nf3(constant(0), random_between(0.12, 0.2), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.5), constant(0))),
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.06), constant(0.06), constant(0.06))))
        .with_material(texture_material(CIRCLE, hdr=(1.7, 0.9, 0.4)))  # ember bloom
        .with_lights(sky=15, block=15)
        .with_cull_box((-10.0, -2.0, -10.0), (10.0, 44.0, 10.0)))
    risers.with_module("trails", {
        "ratio": F(1.0),
        "lifetime": constant(0.35),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            "space": "World", "alignment": "View",
            "thickness": F(0.18),
            "smoothness": I(4),
            "time": F(1.2), "timeInterval": F(0.05),
            # #FF9E4A -> #6B1E10 -> transparent
            "colorOverLength": gradient(
                [(0.0, 0.9), (0.6, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.62, 0.29), (0.55, 0.42, 0.118, 0.063),
                 (1.0, 0.42, 0.118, 0.063)]),
            "physicsSetting": {  # ribbons lag + whip in the updraft
                "warmup": F(0.0), "gravity": L([F(0.0), F(-0.05), F(0.0)]),
                "inertia": F(0.4), "velocitySmoothing": F(0.75), "damping": F(0.7)},
            "renderer": ribbon_renderer(texture_material(CIRCLE, hdr=(1.7, 0.9, 0.4))),
        }})
    return fx


# ---------------------------------------------------------------------------
# Concept 6b — end disc void wisps (the GPU-instancing showcase, WINDOWED loop)
# ---------------------------------------------------------------------------
def build_end_void_wisps() -> FxBuilder:
    """eclipse:end_void_wisps — ghost-light plankton drifting in the void around the
    disc rim; anchored at (END_DISC_CENTER_X, END_DISC_SURFACE_Y-6, END_DISC_CENTER_Z)
    by EndVoidWisps. 1200 GPU-instanced billboards, parallel update+render (LEGAL here:
    no physics, no level access — FX_FORMAT §3.1), one draw call, cull box for free
    off-screen skips. If min-spec profiling complains, halve emissionRate — density is
    the only knob that matters."""
    fx = FxBuilder("end_void_wisps")

    (fx.particle_emitter(
            "void_wisps",
            duration=100, looping=True, prewarm=40,
            start_lifetime=random_between(120, 220), start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.1), random_between(0.04, 0.1),
                           random_between(0.04, 0.1)),
            simulation_space="World", max_particles=1200,
            parallel_update=True, parallel_rendering=True)
       .with_emission(rate=constant(8.0))  # ~1200 steady-state at ~150t mean life
       # Thin torus-ish band hugging the rim (disc radius 96 + margin), squashed flat.
       .with_shape(cylinder(radius=104.0, thickness=0.12), scale=[1.0, 0.25, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(0.9, 0.7, 1.4)))
       .with_renderer(use_gpu_instance=True)
       .with_curves(
            noise=dict(frequency=0.35, quality="Noise3D",  # the whole motion
                       position=nf3(constant(0.08), constant(0.08), constant(0.08))),
            color_over_lifetime=gradient(  # in-hold-out, #8F7BD9 -> #4B3B8C
                [(0.0, 0.0), (0.4, 0.5), (1.0, 0.0)],
                [(0.0, 0.561, 0.482, 0.851), (1.0, 0.294, 0.231, 0.549)]),
            # Smooth in-hold-out breathe (QUALITY §2 row 12): flat tangents at both
            # ends — 1200 wisps swelling organically, not on straight ramps.
            size_over_lifetime=curve(
                0.6, 1.0,
                [(0.0, 0.25, 0.15, 0.25, 0.3, 1.0, 0.45, 1.0),
                 (0.45, 1.0, 0.65, 1.0, 0.85, 0.0, 1.0, 0.0)]))
       .with_cull_box((-110.0, -20.0, -110.0), (110.0, 30.0, 110.0)))
    return fx


# ---------------------------------------------------------------------------
# Concept 8 (crown only) — storm crown halo (WINDOWED loop, one per sphere storm)
# ---------------------------------------------------------------------------
def build_storm_crown_halo() -> FxBuilder:
    """eclipse:storm_crown_halo — parked above the sphere-storm shell top by
    StormFxClient (center + [0, height+2, 0]). shapeArc Loop makes the emission point
    ORBIT the r=8 ring, laying a slowly rotating pearl-string crown; laid pearls keep
    revolving via orbital velocity. Authored at the unit storm (radius-8 wall) — reads
    fine parked over all current storm sizes (IDEAS-world #8)."""
    fx = FxBuilder("storm_crown_halo")

    (fx.particle_emitter(
            "halo_ring",
            duration=120, looping=True,
            start_lifetime=constant(110), start_speed=constant(0),
            start_size=nf3(random_between(0.15, 0.3), random_between(0.15, 0.3),
                           random_between(0.15, 0.3)),
            simulation_space="World", max_particles=90)
       .with_emission(rate=constant(0.9))
       .with_shape(circle(radius=8.0, thickness=0.05, arc_mode="Loop", arc_speed=0.4))
       .with_curves(
            velocity_over_lifetime=dict(  # laid pearls keep revolving
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.25), constant(0))),
            color_over_lifetime=gradient(  # violet in-hold-out
                [(0.0, 0.0), (0.15, 0.8), (0.85, 0.65), (1.0, 0.0)],
                [(0.0, 0.79, 0.7, 1.0), (1.0, 0.56, 0.44, 0.88)]))
       .with_material(texture_material(CIRCLE, hdr=(1.1, 0.9, 1.8)))
       .with_cull_box((-12.0, -4.0, -12.0), (12.0, 6.0, 12.0)))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "supply_drop_contrail.fx": build_supply_drop_contrail,
    "supply_landing_dust.fx": build_supply_landing_dust,
    "sky_launch_charge.fx": build_sky_launch_charge,
    "sky_launch_contrail.fx": build_sky_launch_contrail,
    "breach_ash_geyser.fx": build_breach_ash_geyser,
    "breach_ember_updraft.fx": build_breach_ember_updraft,
    "end_void_wisps.fx": build_end_void_wisps,
    "storm_crown_halo.fx": build_storm_crown_halo,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    import sys
    sys.exit(main())
