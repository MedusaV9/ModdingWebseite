#!/usr/bin/env python3
"""wand2_fx — F-038/F-039 wand spell-system Photon `.fx` assets (the 6 highlight cues).

Authors the second wave of wand effect files programmatically via fxlib (the repo's
diffable source of truth for these binary assets — regenerate, never hand-edit). Every
asset is LAYER garnish over the photon-less Quasar/vanilla baseline composed server-side
in `wand/WandSpellEffects`; rows live in `client/wand/WandPhotonFxRows`, cue ids in
`network/fx/FxCues` (CUE_WAND_*):

  eclipse:wand_umbra_implosion   Umbra-Lanze (riss.umbralanze, F-038) endpoint void bite:
                                 inhale streaks -> void core swell -> HDR bite at t=+3
                                 (UMBRA_BITE_TICKS syncs the server's damage schedule).
  eclipse:wand_event_horizon     Ereignishorizont (riss.ereignishorizont) standing vortex:
                                 accretion streak spiral + in-fall motes + slow core disc,
                                 HORIZON_WINDOW baked to the shipped durationTicks default.
  eclipse:wand_sonnenkern        Sonnenkern (glut.sonnenkern) solar detonation. The WHOLE
                                 asset is setDelay(a = telegraphTicks)ed caller-side so
                                 t=0 here IS the damage tick (stern_komet_impact pattern).
  eclipse:wand_inferno_pillar    Inferno (glut.inferno) fire-storm: rotating ember cyclone
                                 + flickering heat core + zone embers + ash, one-shot over
                                 INFERNO_WINDOW (the shipped durationTicks default).
  eclipse:wand_star_dome         Sternenschild/Novawächter (stern.*) shield IGNITION beat
                                 on the caster (entity lane): star-weave dome + ring shock;
                                 the sustained shield stays the Quasar constellation.
  eclipse:wand_judgment_finale   Himmelsgericht (stern.himmelsgericht) verdict: sky lance
                                 beam + zone ring + star burst. The WHOLE asset is
                                 setDelay(a = finaleDelay)ed caller-side — t=0 here IS the
                                 verdict damage tick.

Budgets: no loops (all one-shots — no cull-box law), maxParticles always explicit,
HDR <= 4.0, eased house curves only. Textures: Photon circle/smoke plus the repo's
identity sheets (star_2x2, square_4x4, ring_soft, dome_faint, beam_core).

Run:  python3 tools/photon/wand2_fx.py          # writes + validates all 6 assets
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"   # glitch identity squares
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"       # 4-point-star twinkle flipbook
RING_SOFT = "eclipse:textures/particle/ring_soft.png"     # soft annulus (ground rings)
DOME_FAINT = "eclipse:textures/particle/dome_faint.png"   # faint hemisphere shell
BEAM_CORE = "eclipse:textures/particle/beam_core.png"     # hot beam cross-section strip

# --- sync contracts (keep in step with the Java side) -----------------------------
# WandSpellEffects.castUmbralanze schedules the implosion damage +3t after the cue.
UMBRA_BITE_TICKS = 3
# WandSpells riss.ereignishorizont "durationTicks" default — the vortex window baked
# here. The collapse SNAP is NOT baked: WandPhotonFxRows delays a riss_maw_snap spawn
# by the cue's live `a` so the snap always lands on the real finale tick.
HORIZON_WINDOW = 120
# WandSpells glut.inferno "durationTicks" default — the fire-storm window baked here.
INFERNO_WINDOW = 140

# The 2x2 star-sheet twinkle tracks (wand_idle_stern's steppy off-chord re-picks).
TWINKLE_FRAMES = dict(
    tiles=(2, 2), animation="WholeSheet",
    frame_over_time=random_curve(
        0.0, 1.0,
        [(0.0, 0.05, 0.25, 0.9, 0.45, 0.1, 0.65, 0.7),
         (0.65, 0.7, 0.75, 0.0, 0.9, 0.95, 1.0, 0.25)],
        [(0.0, 0.6, 0.2, 0.05, 0.4, 1.0, 0.55, 0.15),
         (0.55, 0.15, 0.7, 0.85, 0.85, 0.05, 1.0, 0.5)],
        "lifetime"),
    start_frame=random_between(0.0, 3.0), cycle=3.0)


def rand_size3(lo, hi):
    """Per-axis random start size (the house nf3(random, random, random) idiom)."""
    return nf3(random_between(lo, hi), random_between(lo, hi), random_between(lo, hi))


# ---------------------------------------------------------------------------
# eclipse:wand_umbra_implosion — F-038 Umbra-Lanze endpoint (one-shot, ~26t)
# ---------------------------------------------------------------------------
def build_wand_umbra_implosion() -> FxBuilder:
    """Inhale (negative radial streaks) -> void-core swell -> HDR bite on the damage
    tick (start_delay = UMBRA_BITE_TICKS) with glitch-square shrapnel."""
    fx = FxBuilder("wand_umbra_implosion")
    root = fx.empty("umbra")

    # Streaks sucked into the endpoint from a 2.2-block shell (the inhale).
    (fx.particle_emitter("inhale_streaks",
            duration=26, looping=False, start_lifetime=random_between(4, 7),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(0xFF7B4FD0, 0xFF4FE8FF),  # SAC_DEEP <-> GLI_CYAN
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(20)),
                              burst(time=2, count=constant(14))])
       .with_shape(sphere(radius=2.2, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(0.9, 1.2, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.2)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-1.1)),  # the implosion pull
            color_over_lifetime=gradient([(0.0, 0.0), (0.3, 1.0), (1.0, 0.55)],
                                         [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # Void core: a DARK alpha-blended swirl that swells while inhaling, then collapses
    # to nothing exactly on the bite (additive can't go dark — this can).
    (fx.particle_emitter("void_core",
            duration=26, looping=False, start_lifetime=constant(UMBRA_BITE_TICKS + 7),
            start_speed=constant(0), start_size=nf3(1.0),
            start_color=color(0xFF2E2347),  # SAC_VOID
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(9.0)),
            size_over_lifetime=curve(  # swell to full by the bite, then snap shut
                0.0, 1.9, [(0.0, 0.25, 0.12, 0.95, 0.3, 1.0, 0.42, 1.0),
                           (0.42, 1.0, 0.6, 0.95, 0.85, 0.1, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.18, 0.14, 0.28), (1.0, 0.1, 0.07, 0.18)])))

    # The bite: single-frame white-cyan HDR slice on the server's damage tick.
    (fx.particle_emitter("bite_flash",
            duration=26, looping=False, start_delay=constant(UMBRA_BITE_TICKS),
            start_lifetime=constant(10), start_speed=constant(0), start_size=nf3(1.7),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.7, 2.4, 2.8), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Glitch-square shrapnel spat from the closing bite.
    (fx.particle_emitter("bite_shards",
            duration=26, looping=False, start_delay=constant(UMBRA_BITE_TICKS),
            start_lifetime=random_between(8, 14), start_speed=random_between(0.3, 0.7),
            start_size=rand_size3(0.05, 0.11),
            start_color=random_color(0xFF4FE8FF, 0xFFFF4FD8),  # GLI_CYAN <-> GLI_MAGENTA
            simulation_space="World", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10))])
       .with_shape(sphere(radius=0.25, thickness=0.0))
       .with_material(texture_material(SQUARE_4X4, hdr=(1.0, 1.3, 1.4), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=False, gravity=0.18, bounce_chance=0.0)
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            size_over_lifetime=curve(0.2, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_event_horizon — standing vortex (one-shot, HORIZON_WINDOW ticks)
# ---------------------------------------------------------------------------
def build_wand_event_horizon() -> FxBuilder:
    """Accretion-disc spiral: orbital streaks bleeding inward, motes falling to the
    center, one slow dark core swirl. The collapse snap is a delayed caller-side
    riss_maw_snap spawn (WandPhotonFxRows), never baked here."""
    fx = FxBuilder("wand_event_horizon")
    root = fx.empty("horizon")

    # Orbiting streaks born on the rim, dragged inward — the accretion disc.
    (fx.particle_emitter("accretion",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=random_between(20, 30), start_speed=constant(0),
            start_size=rand_size3(0.1, 0.2),
            start_color=random_color(0xFFB98CFF, 0xFF4FE8FF),  # SAC_VIOLET <-> GLI_CYAN
            simulation_space="Local", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(1.2))
       .with_shape(circle(radius=7.0, thickness=0.15))
       .with_material(texture_material(CIRCLE, hdr=(0.9, 1.1, 1.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.4)
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(1.5), constant(0)),
                radial=constant(-0.26)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.95), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)]))
       .with_lights(sky=15, block=15))

    # Motes spiraling down the gravity well from a wider shell, dying at the center.
    (fx.particle_emitter("infall_motes",
            duration=HORIZON_WINDOW, looping=False, start_lifetime=constant(12),
            start_speed=constant(0),
            start_size=rand_size3(0.05, 0.1),
            start_color=random_color(0xFF7B4FD0, 0xFF37E6E6),
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(2.0))
       .with_shape(sphere(radius=6.0, thickness=0.3))
       .with_material(texture_material(CIRCLE, hdr=(0.8, 1.0, 1.2), blend=BLEND_ADDITIVE))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.5)),
            color_over_lifetime=gradient([(0.0, 0.0), (0.3, 0.9), (1.0, 0.1)],
                                         [(0.0, 1.0, 1.0, 1.0)])))

    # Slow dark core swirl (the hole itself) — alpha-blended so it reads DARK.
    (fx.particle_emitter("core_swirl",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=constant(HORIZON_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(2.6),
            start_color=color(0xFF2E2347),  # SAC_VOID
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(3.0)),
            size_over_lifetime=curve(0.6, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.8), (0.85, 0.7), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (1.0, 0.1, 0.07, 0.18)])))

    # Faint horizontal event-horizon ring hovering at the rim.
    (fx.particle_emitter("horizon_ring",
            duration=HORIZON_WINDOW, looping=False,
            start_lifetime=constant(HORIZON_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(11.0),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(0.7, 0.9, 1.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(1.2)),
            size_over_lifetime=curve(0.85, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.85, 0.4), (1.0, 0.0)],
                [(0.0, 0.65, 0.55, 1.0), (1.0, 0.35, 0.55, 0.9)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_sonnenkern — solar detonation (one-shot ~45t; caller delays by telegraph)
# ---------------------------------------------------------------------------
def build_wand_sonnenkern() -> FxBuilder:
    """t=0 IS the damage tick (the row setDelay(a)s the whole spawn). White-gold core
    pop + light pillar + ground ring + physics ember debris chaining the shipped
    glut_splash/glut_ember_die children + smoke afterglow."""
    fx = FxBuilder("wand_sonnenkern")
    root = fx.empty("sonnenkern")

    (fx.particle_emitter("core_flash",
            duration=45, looping=False, start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(2.6), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(2.6, 1.8, 0.6), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Vertical solar pillar: stretched along a slow upward velocity.
    (fx.particle_emitter("pillar",
            duration=45, looping=False, start_lifetime=constant(16),
            start_speed=constant(0.45), start_size=nf3(1.0), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(cone(angle=0.5, radius=0.05))
       .with_material(texture_material(CIRCLE, hdr=(2.0, 1.4, 0.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=4.5)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)], [(0.0, 1.0, 0.9, 0.65)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("ground_ring",
            duration=45, looping=False, start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.5, 1.0, 0.35), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 11.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.85), (1.0, 0.0)], [(0.0, 1.0, 0.9, 0.6)])))

    # Physics ember debris — bounces chain the SHIPPED glut children (splash / fizzle).
    (fx.particle_emitter("solar_debris",
            duration=45, looping=False, start_lifetime=random_between(22, 36),
            start_speed=random_between(0.5, 1.1),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(0xFFFFE9A8, 0xFFFF7B3C),  # SAC_GOLD_PALE <-> ERA_EMBER
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(22))])
       .with_shape(sphere(radius=0.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 0.9, 0.3), blend=BLEND_ADDITIVE))
       .with_physics(collision=True, friction=0.98, collided_friction=0.6, gravity=0.42,
                     bounce_chance=0.6, bounce_rate=0.4, bounce_spread=0.12)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.75), (0.45, 1.0, 0.55, 0.2), (1.0, 0.45, 0.12, 0.04)]))
       .with_sub_emitters(
            sub_emitter("eclipse:glut_splash", event="Collision", probability=0.4),
            sub_emitter("eclipse:glut_ember_die", event="Death", probability=0.3))
       .with_lights(sky=15, block=15))

    # Afterglow smoke dome so the bloom decays instead of cutting.
    (fx.particle_emitter("smoke_dome",
            duration=45, looping=False, start_delay=constant(3), start_lifetime=constant(32),
            start_speed=constant(0), start_size=nf3(2.2), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.3, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.35), (1.0, 0.0)],
                [(0.0, 0.6, 0.42, 0.28), (1.0, 0.25, 0.16, 0.1)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_inferno_pillar — fire-storm (one-shot, INFERNO_WINDOW ticks)
# ---------------------------------------------------------------------------
def build_wand_inferno_pillar() -> FxBuilder:
    """Rotating ember cyclone (shapeArc Loop sweep) + flickering heat core + sparse zone
    embers + ash. The per-eruption ground beats stay the server's Quasar baseline."""
    fx = FxBuilder("wand_inferno_pillar")
    root = fx.empty("inferno")

    # The cyclone wall: embers born sweeping around a 2.2-radius column, rising.
    (fx.particle_emitter("fire_cyclone",
            duration=INFERNO_WINDOW, looping=False,
            start_lifetime=random_between(24, 34), start_speed=constant(0),
            start_size=rand_size3(0.08, 0.16),
            start_color=random_color(0xFFFFC873, 0xFFFF7B3C),  # warm ERA ambers
            simulation_space="Local", max_particles=128)
       .child_of(root)
       .with_emission(rate=constant(3.0))
       .with_shape(cylinder(radius=2.2, thickness=0.12, arc_mode="Loop", arc_speed=1.1))
       .with_material(texture_material(CIRCLE, hdr=(1.5, 0.8, 0.25), blend=BLEND_ADDITIVE))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.12, 0.22), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(1.1), constant(0))),
            color_over_lifetime=gradient(  # white-hot -> amber -> deep red -> 0
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.92, 0.75), (0.4, 1.0, 0.5, 0.15), (1.0, 0.4, 0.08, 0.02)]))
       .with_lights(sky=15, block=15))

    # Flickering heat core: sparse tall stretched flames standing in the middle.
    (fx.particle_emitter("heat_core",
            duration=INFERNO_WINDOW, looping=False, start_lifetime=constant(18),
            start_speed=constant(0.5), start_size=nf3(0.8), simulation_space="Local",
            max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.15))
       .with_shape(cone(angle=1.0, radius=0.2))
       .with_material(texture_material(CIRCLE, hdr=(1.9, 1.1, 0.35), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=5.0)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.2, 1.0), (0.75, 0.7), (1.0, 0.0)], [(0.0, 1.0, 0.85, 0.55)]))
       .with_lights(sky=15, block=15))

    # Sparse embers drifting up across the whole eruption zone (radius ~8).
    (fx.particle_emitter("zone_embers",
            duration=INFERNO_WINDOW, looping=False,
            start_lifetime=random_between(20, 30),
            start_speed=random_between(0.02, 0.06),
            start_size=rand_size3(0.04, 0.09),
            simulation_space="Local", max_particles=64)
       .child_of(root)
       .with_emission(rate=constant(1.6))
       .with_shape(circle(radius=8.0, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.2, 0.6, 0.18), blend=BLEND_ADDITIVE))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.14), constant(0))),
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.04), constant(0.01), constant(0.04)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.7, 0.3), (1.0, 0.5, 0.15, 0.04)]))
       .with_lights(sky=15, block=15))

    # Ash column shading the cyclone (dark alpha smoke, sorted).
    (fx.particle_emitter("ash",
            duration=INFERNO_WINDOW, looping=False, start_lifetime=constant(36),
            start_speed=random_between(0.05, 0.1),
            start_size=rand_size3(0.5, 0.9),
            simulation_space="Local", max_particles=24)
       .child_of(root)
       .with_emission(rate=constant(0.5))
       .with_shape(cone(angle=18.0, radius=1.6))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.1, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (1.0, 0.0)],
                [(0.0, 0.32, 0.24, 0.2), (1.0, 0.12, 0.09, 0.08)])))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_star_dome — shield ignition on the caster (entity one-shot, ~55t)
# ---------------------------------------------------------------------------
def build_wand_star_dome() -> FxBuilder:
    """Dome shell + woven star sprites + feet ring shock + ignition pop. Anchored on the
    caster (entity lane, body-center offset in the row); the SUSTAINED shield stays the
    server's Quasar constellation baseline."""
    fx = FxBuilder("wand_star_dome")
    root = fx.empty("dome")

    # The faint hemisphere shell blooming out and settling around the caster.
    (fx.particle_emitter("dome_shell",
            duration=55, looping=False, start_lifetime=constant(50), start_speed=constant(0),
            start_size=nf3(3.2), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, hdr=(0.9, 1.0, 1.5), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(0.35, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.75), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, 0.75, 0.85, 1.0), (1.0, 0.55, 0.65, 1.0)])))

    # The star weave: 4-point-star sprites on the shell, slowly orbiting + twinkling.
    (fx.particle_emitter("star_weave",
            duration=55, looping=False, start_lifetime=random_between(30, 46),
            start_speed=constant(0),
            start_size=rand_size3(0.07, 0.12),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(0.35),
                      bursts=[burst(time=0, count=constant(16))])
       .with_shape(sphere(radius=1.6, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.0, 1.0, 1.6), blend=BLEND_ADDITIVE))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.25), constant(0))),
            size_over_lifetime=curve(  # double-hump twinkle
                0.3, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)]))
       .with_lights(sky=15, block=15))

    # Ring shock at the feet (anchor = body center, so the ring sits ~1 block down).
    (fx.particle_emitter("feet_ring",
            duration=55, looping=False, start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .at(0.0, -0.9, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.0, 1.1, 1.7), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.8, 5.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)])))

    # Ignition pop — brief HDR bloom as the shield snaps on.
    (fx.particle_emitter("ignition_flash",
            duration=55, looping=False, start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(1.4), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.6, 1.7, 2.4), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.35, 0.08, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# eclipse:wand_judgment_finale — the verdict (one-shot ~50t; caller delays by finaleDelay)
# ---------------------------------------------------------------------------
def build_wand_judgment_finale() -> FxBuilder:
    """t=0 IS the verdict damage tick (the row setDelay(a)s the whole spawn). One sky
    lance beam slamming the zone + white-gold verdict flash + zone-wide ring + star
    shard burst + afterglow dome."""
    fx = FxBuilder("wand_judgment_finale")
    root = fx.empty("judgment")

    # The lance: a 24-block vertical beam flashing down onto the zone center.
    lance = fx.beam_emitter("sky_lance",
            end=(0.0, -24.0, 0.0), width=curve(0.0, 1.4, [SEG_POP_SHRINK], "duration"),
            duration=16, looping=False, raycast="NONE",
            color_nf=gradient([(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
                              [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.8, 1.0)]))
    lance.child_of(root).at(0.0, 24.0, 0.0)
    lance.with_material(texture_material(BEAM_CORE, hdr=(1.8, 1.8, 2.6), blend=BLEND_ADDITIVE))
    lance.with_lights(sky=15, block=15)

    (fx.particle_emitter("verdict_flash",
            duration=50, looping=False, start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(3.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(2.2, 2.2, 3.0), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Zone-wide judgment ring (zoneRadius default 9 -> ~18-block diameter sweep).
    (fx.particle_emitter("zone_ring",
            duration=50, looping=False, start_lifetime=constant(16), start_speed=constant(0),
            start_size=nf3(1.5), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=(1.3, 1.3, 1.9), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 12.0, [(0.0, 0.0, 0.18, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)], [(0.0, 0.9, 0.92, 1.0)])))

    # Star shards blown outward by the verdict — actual 4-point stars, twinkling out.
    (fx.particle_emitter("star_burst",
            duration=50, looping=False, start_lifetime=random_between(20, 32),
            start_speed=random_between(0.4, 0.9),
            start_size=rand_size3(0.07, 0.13),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(sphere(radius=0.6, thickness=0.0))
       .with_material(texture_material(STAR_2X2, hdr=(1.1, 1.1, 1.7), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.12, bounce_chance=0.0)
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(0.3, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.7, 0.8, 1.0)]))
       .with_lights(sky=15, block=15))

    # Afterglow dome so the verdict bloom decays instead of cutting.
    (fx.particle_emitter("afterglow",
            duration=50, looping=False, start_delay=constant(4), start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(2.4), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 1.8, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.35), (1.0, 0.0)],
                [(0.0, 0.7, 0.75, 1.0), (1.0, 0.45, 0.55, 0.85)])))
    return fx


BUILDERS = {
    "wand_umbra_implosion.fx": build_wand_umbra_implosion,
    "wand_event_horizon.fx": build_wand_event_horizon,
    "wand_sonnenkern.fx": build_wand_sonnenkern,
    "wand_inferno_pillar.fx": build_wand_inferno_pillar,
    "wand_star_dome.fx": build_wand_star_dome,
    "wand_judgment_finale.fx": build_wand_judgment_finale,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
