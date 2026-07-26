#!/usr/bin/env python3
"""nether_open_fx — Photon assets for the day-2 NETHER OPENING sequence.

Committed fxlib source of truth (binary-blob diff law, FX_FORMAT.md §7) for the four
`.fx` blobs of `sequence/NetherOpeningSequence`:

  phase 1 OMEN      eclipse:nether_omen_ash        one-shot 240t: ash column creeping out
                                                   of the un-broken ground + lava glints
                                                   seeping from the ritzen + a flat ground
                                                   seep skirt
  phase 2 TREMOR    eclipse:nether_quake_fissure   one-shot 140t: ONE glowing ground crack
                                                   (jagged randomA line) + its dust lift;
                                                   the client stamps several around the rim
  phase 3 RUPTURE   eclipse:nether_eruption        one-shot 200t: fire column + colliding
                                                   ember shrapnel + smoke pillar + the
                                                   ground shock ring
  phase 4 AFTERMATH eclipse:nether_pit_plume       WINDOWED loop: the permanent smoke cloud
                                                   hanging over the pit — dense dark swathes
                                                   rotating slowly, orange fire tongues
                                                   glowing THROUGH them from the inside,
                                                   periodic spark spurts and a faint heat
                                                   glow (no real refraction — Photon has no
                                                   distortion module, the ask's "sonst
                                                   weglassen" branch)

Loop law (INTEGRATION.md §4): the plume carries a renderer cull box + hard maxParticles on
every emitter. Collision emitters keep parallelUpdate 0b (FX_FORMAT §3.1/§3.3 — collision
does real level queries and is forbidden on the parallel path). Textures stay on the two
Photon-bundled particles (circle.png / smoke.png).

Run:  python3 tools/photon/nether_open_fx.py     # writes + validates all 4 assets
"""
from fxlib import *  # noqa: F401,F403 - the authoring DSL is the point
from fxlib import B, F, I, L  # explicit for the raw module compounds

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"

# Crater geometry the assets are authored against (BreachGeometry): mouth r 16, creep halo
# r 28. Cull boxes are sized off the halo so nothing pops while the camera orbits the rim.
CRATER_R = 16.0
HALO_R = 28.0

# Phase lengths in ticks — MUST stay in sync with NetherOpeningSequence's tick table
# (the assets are finite one-shots; a shorter asset would die mid-phase).
OMEN_TICKS = 240
FISSURE_TICKS = 140
ERUPTION_TICKS = 200


#: Eased 0->1 swell over the emitter lifetime (LINT-LINEAR-CURVE: never ship chord-collinear
#: segments — the ramp must breathe, FX-STYLE-GUIDE house segments).
SEG_SWELL = (0.0, 0.0, 0.32, 0.04, 0.62, 0.96, 1.0, 1.0)
#: Eased 1->0 decay with a held head — a crack tears open hard, then only creeps.
SEG_TEAR_OFF = (0.0, 1.0, 0.1, 1.0, 0.3, 0.22, 1.0, 0.0)


def swell(lower, upper):
    """Eased emission/speed ramp from `lower` to `upper` over the emitter's own lifetime."""
    return curve(lower, upper, [SEG_SWELL])


def tear_off(lower, upper):
    """Eased front-loaded decay from `upper` down to `lower` (the tearing envelope)."""
    return curve(lower, upper, [SEG_TEAR_OFF])


def ribbon_renderer(material_entry):
    """RendererSetting compound for an EMBEDDED araConfig (mirrors fxlib._init_renderer);
    written explicitly so ribbons never fall back to the MISSING (pink) material."""
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": {"_enable": B(0)}, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# Phase 1 — OMEN: something under the desert is breathing
# ---------------------------------------------------------------------------
def build_nether_omen_ash() -> FxBuilder:
    """eclipse:nether_omen_ash — block-anchored at the future crater centre on the STILL
    CLOSED surface (BreachGeometry.centerX/lipY/centerZ). Nothing erupts yet: ash wells up
    out of the sand over the whole mouth footprint, a low skirt creeps outward over the
    halo, and single lava glints wink in the hairline cracks. Ramped in over the first
    ~third so the phase starts almost imperceptibly."""
    fx = FxBuilder("nether_omen_ash")

    # Ash welling up out of the ground: rate RAMPS over the phase (the omen builds).
    (fx.particle_emitter(
            "ash_rise",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(70, 130),
            start_speed=random_between(0.03, 0.12),
            start_size=nf3(random_between(0.5, 1.4), random_between(0.5, 1.4),
                           random_between(0.5, 1.4)),
            simulation_space="World", max_particles=170)
       .with_emission(rate=swell(0.6, 4.0))
       .with_shape(cylinder(radius=CRATER_R - 2.0, thickness=1.0))
       .with_curves(
            velocity_over_lifetime=dict(  # thermal lift + a lazy swirl
                linear=nf3(constant(0), random_between(0.05, 0.13), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.06), constant(0))),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.03), constant(0.05))),
            color_over_lifetime=gradient(  # #5A4A46 -> #2B2224, in-hold-out
                [(0.0, 0.0), (0.2, 0.55), (1.0, 0.0)],
                [(0.0, 0.353, 0.29, 0.275), (1.0, 0.169, 0.133, 0.141)]),
            size_over_lifetime=curve(
                0.7, 1.8,
                [(0.0, 0.0, 0.2, 0.35, 0.5, 0.9, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -6.0, -HALO_R), (HALO_R, 46.0, HALO_R)))

    # Lava glints seeping from hairline cracks: tiny, bright, short, all over the halo.
    (fx.particle_emitter(
            "crack_glints",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(18, 34),
            start_speed=random_between(0.02, 0.09),
            start_size=nf3(random_between(0.05, 0.13), random_between(0.05, 0.13),
                           random_between(0.05, 0.13)),
            simulation_space="World", max_particles=70)
       .with_emission(rate=swell(0.3, 2.4))
       .with_shape(cylinder(radius=HALO_R - 6.0, thickness=1.0), scale=[1.0, 0.05, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(2.0, 0.85, 0.3)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(  # #FFB25E -> #FF7B3C -> out
            [(0.0, 0.0), (0.25, 0.95), (1.0, 0.0)],
            [(0.0, 1.0, 0.698, 0.369), (1.0, 1.0, 0.482, 0.235)]))
       .with_cull_box((-HALO_R, -4.0, -HALO_R), (HALO_R, 12.0, HALO_R)))

    # Flat seep skirt hugging the sand out to the creep halo — the "ground is venting" read.
    (fx.particle_emitter(
            "ground_seep",
            duration=OMEN_TICKS, looping=False,
            start_lifetime=random_between(50, 90),
            start_speed=random_between(0.12, 0.3),
            start_size=nf3(random_between(0.7, 1.6), random_between(0.7, 1.6),
                           random_between(0.7, 1.6)),
            simulation_space="World", max_particles=90)
       .with_emission(rate=swell(0.4, 2.0))
       .with_shape(cone(angle=82.0, radius=CRATER_R * 0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(color_over_lifetime=gradient(  # dusty sand-grey, very soft
            [(0.0, 0.0), (0.25, 0.38), (1.0, 0.0)],
            [(0.0, 0.42, 0.36, 0.31), (1.0, 0.22, 0.18, 0.17)]))
       .with_cull_box((-HALO_R - 6.0, -4.0, -HALO_R - 6.0), (HALO_R + 6.0, 14.0, HALO_R + 6.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 2 — TREMOR: the ground cracks
# ---------------------------------------------------------------------------
def build_nether_quake_fissure() -> FxBuilder:
    """eclipse:nether_quake_fissure — ONE ground crack, stamped several times around the
    rim by the client (each stamp gets its own yaw through SpawnOptions.withRotationDeg, so
    one asset covers the whole star of fissures). The crack itself is a jagged randomA line
    of glowing embers laid flat on the surface; grey dust lifts off it as it "tears"."""
    fx = FxBuilder("nether_quake_fissure")

    # The glowing seam: randomA walks the particle along a 22-block line, the sin term
    # jitters it sideways so the crack reads jagged instead of ruler-straight.
    (fx.particle_emitter(
            "fissure_seam",
            duration=FISSURE_TICKS, looping=False,
            start_lifetime=random_between(60, FISSURE_TICKS),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.18, 0.42), random_between(0.18, 0.42),
                           random_between(0.18, 0.42)),
            simulation_space="World", max_particles=120)
       # Front races outward along the seam over the first ~40 %: the crack TEARS open.
       .with_emission(rate=tear_off(0.6, 8.0))
       .with_shape(function_shape(
            x="(randomA*2-1)*11",
            y="0.06",
            z="sin(randomA*37)*0.55 + (randomB*2-1)*0.25"))
       .with_material(texture_material(CIRCLE, hdr=(2.2, 0.9, 0.28)))
       .with_lights(sky=15, block=15)
       .with_curves(
            velocity_over_lifetime=dict(  # the seam breathes upward, barely
                linear=nf3(constant(0), random_between(0.005, 0.03), constant(0))),
            color_over_lifetime=gradient(  # #FFF3C4 core -> #FF7B3C -> #6B1E10 out
                [(0.0, 0.0), (0.1, 1.0), (0.75, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.35, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)]),
            size_over_lifetime=curve(
                0.35, 1.0,
                [(0.0, 0.0, 0.15, 0.9, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.7, 1.0, 0.85, 0.1, 1.0, 0.0)]))
       .with_cull_box((-16.0, -4.0, -16.0), (16.0, 12.0, 16.0)))

    # Dust lifting off the tearing seam (no collision: it is born ON the surface).
    (fx.particle_emitter(
            "fissure_dust",
            duration=FISSURE_TICKS, looping=False,
            start_lifetime=random_between(30, 60),
            start_speed=random_between(0.15, 0.45),
            start_size=nf3(random_between(0.35, 0.9), random_between(0.35, 0.9),
                           random_between(0.35, 0.9)),
            simulation_space="World", max_particles=80)
       .with_emission(rate=tear_off(0.2, 5.0))
       .with_shape(function_shape(
            x="(randomA*2-1)*11",
            y="0.1",
            z="sin(randomA*37)*0.55"))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.16), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.6), (1.0, 0.0)],
                [(0.0, 0.44, 0.38, 0.33), (1.0, 0.2, 0.16, 0.15)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-16.0, -4.0, -16.0), (16.0, 18.0, 16.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 3 — RUPTURE: the hole is torn open
# ---------------------------------------------------------------------------
# One violent throat-punch, then a long tail: shared emitter-t envelope for the fire and
# smoke rates so the whole eruption breathes as ONE event.
ERUPT_HUMPS = [(0.0, 1.0, 0.04, 1.0, 0.1, 0.55, 0.22, 0.42),
               (0.22, 0.42, 0.4, 0.3, 0.6, 0.16, 1.0, 0.05)]


def build_nether_eruption() -> FxBuilder:
    """eclipse:nether_eruption — block-anchored at the crater centre on the lip plane, fired
    the tick the block-display fountain launches and the server starts carving. Fire column
    up the middle, colliding ember shrapnel raining onto the creep halo, a slow black smoke
    pillar that hands over to the permanent plume, and a ground-hugging shock ring."""
    fx = FxBuilder("nether_eruption")

    # Fire column: stretched billboards so the flames read as tongues, not dots.
    (fx.particle_emitter(
            "fire_column",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(26, 56),
            start_speed=random_between(1.1, 2.6),
            start_size=nf3(random_between(0.6, 1.7), random_between(0.6, 1.7),
                           random_between(0.6, 1.7)),
            simulation_space="World", max_particles=200)
       .with_emission(rate=curve(0.4, 14.0, ERUPT_HUMPS))
       .with_shape(cone(angle=14.0, radius=CRATER_R * 0.4))
       .with_material(texture_material(CIRCLE, hdr=(2.4, 1.15, 0.4)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.4,
                      length_scale=2.2, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(  # #FFF3C4 -> #FFB25E -> #FF7B3C -> out
                [(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.4, 1.0, 0.698, 0.369),
                 (1.0, 1.0, 0.482, 0.235)]),
            size_over_lifetime=curve(
                0.2, 1.0,
                [(0.0, 0.4, 0.1, 1.0, 0.25, 1.0, 0.45, 1.0),
                 (0.45, 1.0, 0.65, 0.8, 0.85, 0.1, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -20.0, -HALO_R), (HALO_R, 70.0, HALO_R)))

    # Ember shrapnel: REAL collision, so glowing chunks skitter over the crimson creep
    # halo and the crater lip instead of sinking through it (parallelUpdate stays off).
    (fx.particle_emitter(
            "ember_shrapnel",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(45, 95),
            start_speed=random_between(1.4, 3.2),
            start_size=nf3(random_between(0.1, 0.28), random_between(0.1, 0.28),
                           random_between(0.1, 0.28)),
            simulation_space="World", max_particles=150,
            parallel_update=False)  # collision law (FX_FORMAT §3.1)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(60), cycles=1),
                              burst(time=14, count=constant(34), cycles=3, interval=26)])
       .with_shape(cone(angle=46.0, radius=CRATER_R * 0.35))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.34,
                     friction=0.98, collided_friction=0.55, bounce_chance=0.65,
                     bounce_rate=0.3, bounce_spread=0.3)
       .with_material(texture_material(CIRCLE, hdr=(2.2, 1.0, 0.35)))
       .with_lights(sky=15, block=15)
       .with_curves(color_over_lifetime=gradient(  # cooling ember
            [(0.0, 1.0), (0.7, 0.85), (1.0, 0.0)],
            [(0.0, 1.0, 0.86, 0.55), (0.5, 1.0, 0.482, 0.235),
             (1.0, 0.42, 0.118, 0.063)]))
       .with_cull_box((-HALO_R - 10.0, -24.0, -HALO_R - 10.0),
                      (HALO_R + 10.0, 60.0, HALO_R + 10.0)))

    # Black smoke pillar — the visual handover to the permanent plume: it climbs to roughly
    # the plume's hover height and is still fading when the loop window materialises.
    (fx.particle_emitter(
            "smoke_pillar",
            duration=ERUPTION_TICKS, looping=False,
            start_lifetime=random_between(90, 170),
            start_speed=random_between(0.5, 1.3),
            start_size=nf3(random_between(1.6, 3.4), random_between(1.6, 3.4),
                           random_between(1.6, 3.4)),
            simulation_space="World", max_particles=180)
       .with_emission(rate=curve(0.8, 8.0, ERUPT_HUMPS))
       .with_shape(cone(angle=22.0, radius=CRATER_R * 0.5))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.18), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.12), constant(0))),
            noise=dict(frequency=0.4, quality="Noise2D",
                       position=nf3(constant(0.07), constant(0.04), constant(0.07))),
            color_over_lifetime=gradient(  # lit-from-below grey -> soot black
                [(0.0, 0.0), (0.12, 0.75), (1.0, 0.0)],
                [(0.0, 0.4, 0.31, 0.28), (0.45, 0.24, 0.18, 0.18),
                 (1.0, 0.12, 0.098, 0.11)]),
            size_over_lifetime=curve(
                0.8, 2.4,
                [(0.0, 0.0, 0.25, 0.4, 0.55, 0.85, 1.0, 1.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 8.0, -20.0, -HALO_R - 8.0), (HALO_R + 8.0, 80.0, HALO_R + 8.0)))

    # Ground shock ring: one flat dust wave racing out over the halo at t=0.
    (fx.particle_emitter(
            "shock_ring",
            duration=60, looping=False,
            start_lifetime=random_between(24, 42),
            start_speed=random_between(1.6, 2.6),
            start_size=nf3(random_between(0.9, 2.0), random_between(0.9, 2.0),
                           random_between(0.9, 2.0)),
            simulation_space="World", max_particles=90)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(72), cycles=1)])
       .with_shape(circle(radius=CRATER_R * 0.6, thickness=0.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.04), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.65), (1.0, 0.0)],
                [(0.0, 0.47, 0.4, 0.34), (1.0, 0.24, 0.19, 0.18)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R - 16.0, -6.0, -HALO_R - 16.0), (HALO_R + 16.0, 20.0, HALO_R + 16.0)))
    return fx


# ---------------------------------------------------------------------------
# Phase 4 — AFTERMATH: the permanent plume (WINDOWED loop, NetherPitPlume owns it)
# ---------------------------------------------------------------------------
# Spark spurts: two gusts per 10 s cycle, shared by the spark rate and its speed.
SPURT_HUMPS = [(0.0, 0.05, 0.08, 0.9, 0.16, 0.35, 0.45, 0.05),
               (0.45, 0.05, 0.55, 0.85, 0.66, 0.3, 1.0, 0.05)]


def build_nether_pit_plume() -> FxBuilder:
    """eclipse:nether_pit_plume — the permanent cloud hanging over the opened pit, anchored
    by NetherPitPlume at (centerX, lipY + PLUME_HOVER, centerZ). Four layers: dense dark
    swathes turning slowly around the axis, orange fire tongues burning INSIDE them (lit +
    HDR, so they glow through the smoke), periodic spark spurts, and a faint wide heat glow.
    A real heat-shimmer refraction is NOT possible (Photon ships no distortion module) — the
    glow layer is the sanctioned stand-in."""
    fx = FxBuilder("nether_pit_plume")

    # Layer 1 — the smoke body: big soft swathes, slow orbital turn, noise churn.
    (fx.particle_emitter(
            "smoke_swathes",
            duration=200, looping=True, prewarm=60,
            start_lifetime=random_between(180, 300),
            start_speed=random_between(0.01, 0.06),
            start_size=nf3(random_between(2.2, 5.0), random_between(2.2, 5.0),
                           random_between(2.2, 5.0)),
            simulation_space="World", max_particles=110)
       .with_emission(rate=constant(0.5))
       .with_shape(cylinder(radius=CRATER_R * 0.72, thickness=0.75), scale=[1.0, 0.45, 1.0])
       .with_curves(
            velocity_over_lifetime=dict(  # the cloud ROTATES; it barely climbs
                linear=nf3(constant(0), random_between(0.004, 0.022), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.085), constant(0))),
            noise=dict(frequency=0.22, quality="Noise3D",
                       position=nf3(constant(0.05), constant(0.025), constant(0.05))),
            color_over_lifetime=gradient(  # #4A3B38 -> #241C1D soot
                [(0.0, 0.0), (0.18, 0.72), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.29, 0.231, 0.22), (1.0, 0.141, 0.11, 0.114)]),
            size_over_lifetime=curve(
                0.75, 1.35,
                [(0.0, 0.0, 0.12, 0.55, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.72, 1.0, 0.88, 0.15, 1.0, 0.0)]))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 30.0, HALO_R)))

    # Layer 2 — fire tongues burning INSIDE the cloud: same orbital rate as the smoke, so
    # they ride WITH the swathes instead of drifting out of them.
    (fx.particle_emitter(
            "inner_fire",
            duration=200, looping=True, prewarm=30,
            start_lifetime=random_between(45, 95),
            start_speed=random_between(0.05, 0.2),
            start_size=nf3(random_between(0.5, 1.5), random_between(0.5, 1.5),
                           random_between(0.5, 1.5)),
            simulation_space="World", max_particles=56)
       .with_emission(rate=constant(0.75))
       .with_shape(sphere(radius=CRATER_R * 0.42, thickness=0.85), scale=[1.0, 0.5, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(2.3, 1.0, 0.32)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.9,
                      length_scale=1.8, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.09), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.085), constant(0))),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.03), constant(0.04))),
            color_over_lifetime=gradient(  # #FFB25E -> #FF7B3C -> #6B1E10
                [(0.0, 0.0), (0.14, 0.95), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.698, 0.369), (0.45, 1.0, 0.482, 0.235),
                 (1.0, 0.42, 0.118, 0.063)]),
            size_over_lifetime=curve(
                0.25, 1.0,
                [(0.0, 0.15, 0.1, 0.95, 0.25, 1.0, 0.45, 1.0),
                 (0.45, 1.0, 0.66, 0.85, 0.86, 0.12, 1.0, 0.0)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 26.0, HALO_R)))

    # Layer 3 — spark spurts: two gusts per cycle punched up through the cloud.
    (fx.particle_emitter(
            "spark_spurts",
            duration=200, looping=True,
            start_lifetime=random_between(30, 65),
            start_speed=curve(0.3, 1.5, SPURT_HUMPS),
            start_size=nf3(random_between(0.07, 0.18), random_between(0.07, 0.18),
                           random_between(0.07, 0.18)),
            simulation_space="World", max_particles=44)
       .with_emission(rate=curve(0.0, 3.4, SPURT_HUMPS))  # no bursts: loop-safe
       .with_shape(cone(angle=26.0, radius=CRATER_R * 0.3))
       .with_material(texture_material(CIRCLE, hdr=(2.1, 1.1, 0.5)))
       .with_lights(sky=15, block=15)
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=1.5,
                      length_scale=2.0, vertex_sorting="NONE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.03, 0.02), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.65, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.953, 0.769), (0.4, 1.0, 0.698, 0.369),
                 (1.0, 1.0, 0.482, 0.235)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 40.0, HALO_R)))

    # Layer 4 — heat glow: a few huge, almost invisible additive sheets breathing under the
    # cloud. Not refraction (Photon has no distortion module) — it fakes the hot-air haze by
    # washing the pit mouth in a dull orange bloom.
    (fx.particle_emitter(
            "heat_glow",
            duration=200, looping=True, prewarm=40,
            start_lifetime=random_between(120, 200),
            start_speed=constant(0.0),
            start_size=nf3(random_between(5.0, 9.0), random_between(5.0, 9.0),
                           random_between(5.0, 9.0)),
            simulation_space="World", max_particles=18)
       .with_emission(rate=constant(0.12))
       .with_shape(cylinder(radius=CRATER_R * 0.5, thickness=1.0), scale=[1.0, 0.3, 1.0])
       .with_material(texture_material(CIRCLE, hdr=(0.9, 0.42, 0.16)))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.008, 0.03), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.05), constant(0))),
            color_over_lifetime=gradient(  # very low alpha throughout — this is a wash
                [(0.0, 0.0), (0.3, 0.14), (0.7, 0.12), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.25), (1.0, 0.65, 0.25, 0.12)]),
            size_over_lifetime=curve(
                0.85, 1.25,
                [(0.0, 0.2, 0.15, 0.2, 0.3, 1.0, 0.5, 1.0),
                 (0.5, 1.0, 0.7, 1.0, 0.85, 0.2, 1.0, 0.2)]))
       .with_cull_box((-HALO_R, -26.0, -HALO_R), (HALO_R, 24.0, HALO_R)))
    return fx


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
BUILDERS = {
    "nether_omen_ash.fx": build_nether_omen_ash,
    "nether_quake_fissure.fx": build_nether_quake_fissure,
    "nether_eruption.fx": build_nether_eruption,
    "nether_pit_plume.fx": build_nether_pit_plume,
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
