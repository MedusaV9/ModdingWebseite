#!/usr/bin/env python3
"""gen_player_fx — PH-PLAYER's Photon `.fx` assets (IDEAS-player.md concepts 1/2/4/5/6).

Authors the wand + player-attached effect files programmatically via fxlib (the repo's
diffable source of truth for these binary assets — regenerate, never hand-edit):

  concept 1  eclipse:wand_soulbind_flash   soulbind ceremony HDR bloom pop (entity one-shot)
  concept 2  eclipse:stern_komet_fall      Kometenschlag descent head + ara ribbon (+ Tick sub)
             eclipse:stern_komet_sparkle     glitter motes shed by the falling head
             eclipse:stern_komet_impact    delayed HDR detonation (setDelay(telegraph) caller-side)
  concept 4  eclipse:riss_schlag_maw       maw implosion: negative radial + Death sub-chain
             eclipse:riss_glitch_pop         3-particle static burst (sub-emitter target)
  concept 5  eclipse:glut_sprung_crater    eruption: 14 physics colliders + Collision/Death subs
             eclipse:glut_splash             per-bounce ember splash (Collision target)
             eclipse:glut_ember_die          2-particle fizzle (Death target)
  concept 6  eclipse:wand_idle_riss        scanline ara ribbon orbit + pixel squares (loop)
             eclipse:wand_idle_glut        ember ring, shapeArc Loop sweep (loop)
             eclipse:wand_idle_stern       tilted star halo + hairline trails (loop)

Every loop ships a renderer cull box + modest maxParticles (INTEGRATION.md §4 loop law);
one-shots stay inside the budgets quoted per concept in IDEAS-player.md. Textures are
limited to the two Photon-bundled particles (circle.png / smoke.png).

Run:  python3 tools/photon/gen_player_fx.py          # writes + validates all assets
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"

# Ticks the komet head needs to cover its baked ~18-block descent. MUST stay in sync with
# WandPhotonFxRows.KOMET_FALL_TICKS (the client subtracts it from the telegraph delay).
KOMET_FALL_TICKS = 13


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED trail/ara configs (trails module, FX_FORMAT §4.2/4.3).

    fxlib's _RendererMixin only serves standalone emitters; embedded TrailConfig/AraTrailConfig
    carry their own renderer block — written explicitly so ribbons never fall back to the
    MISSING (pink) material.
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# Concept 1 — eclipse:wand_soulbind_flash (one-shot, ~50t tree, <= 33 live particles)
# ---------------------------------------------------------------------------
def build_wand_soulbind_flash() -> FxBuilder:
    fx = FxBuilder("wand_soulbind_flash")
    root = fx.empty("soulbind")

    # True HDR bloom pop on the flash tick — the one thing Quasar cannot do (FX_FORMAT §7.1).
    (fx.particle_emitter("core_flash",
            duration=50, looping=False, start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(1.6), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(2.5, 2.2, 3.5), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(  # 0.2 -> 1.0 pop-in by ~2t, decay to 0 by 12t
            0.0, 1.0, [(0.0, 0.2, 0.08, 1.0, 0.72, 0.55, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("ring_shock",
            duration=50, looping=False, start_delay=constant(1), start_lifetime=constant(14),
            start_speed=constant(0), start_size=nf3(0.4), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.0, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard")
       .with_curves(
            size_over_lifetime=curve(  # 0.4 -> 3.2 ease-out expansion
                1.0, 8.0, [(0.0, 0.0, 0.18, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    (fx.particle_emitter("sparks",
            duration=50, looping=False, start_delay=constant(1),
            start_lifetime=random_between(20, 30), start_speed=random_between(0.3, 0.7),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(sphere(radius=0.3, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.1, 1.0, 1.4), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.15, bounce_chance=0.0)
       .with_curves(color_over_lifetime=gradient(  # white -> path-agnostic violet -> 0
            [(0.0, 1.0), (0.55, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.5, 0.75, 0.55, 1.0), (1.0, 0.45, 0.25, 0.8)]))
       .with_lights(sky=15, block=15))

    # Soft afterglow covers the bloom falloff so the pop doesn't "cut".
    (fx.particle_emitter("afterglow",
            duration=50, looping=False, start_delay=constant(4), start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(1.2), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.2, [SEG_LINEAR_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.35), (1.0, 0.0)],
                [(0.0, 0.7, 0.55, 0.95), (1.0, 0.4, 0.3, 0.6)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 2 — eclipse:stern_komet_fall / _sparkle / _impact
# ---------------------------------------------------------------------------
def build_stern_komet_fall() -> FxBuilder:
    """One falling HDR head dragging an ara ribbon: ~18 blocks in KOMET_FALL_TICKS ticks.

    Spawned by the client at target + (0, 18, 0); the descent velocity is baked here so the
    server owns only the telegraph timing (delay = telegraph - KOMET_FALL_TICKS).
    """
    fx = FxBuilder("stern_komet_fall")
    (fx.particle_emitter("head",
            duration=20, looping=False, start_lifetime=constant(KOMET_FALL_TICKS),
            start_speed=constant(0), start_size=nf3(0.9), simulation_space="World",
            max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.8, 1.8, 2.6), blend=BLEND_ADDITIVE))
       .with_curves(velocity_over_lifetime=dict(  # eases in to ~-1.9 blocks/t; ~18 over 13t
            linear=nf3(constant(0),
                       curve(-1.9, -0.9, [SEG_LINEAR_DOWN], "lifetime", "velocity"),
                       constant(0))))
       .with_module("trails", {
            "ratio": F(1.0), "lifetime": constant(1.0),
            "dieWithParticles": B(0), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "colorOverLifetime": gradient([(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)]),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "thickness": F(0.35), "time": F(0.9), "alignment": "View", "space": "World",
                "colorOverLength": gradient(  # white core -> transparent blue tail
                    [(0.0, 1.0), (1.0, 0.0)],
                    [(0.0, 1.0, 1.0, 1.0), (0.4, 0.75, 0.85, 1.0), (1.0, 0.45, 0.6, 1.0)]),
                "physicsSetting": {"warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                                   "inertia": F(0.25), "velocitySmoothing": F(0.75),
                                   "damping": F(0.8)},
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=(1.2, 1.3, 1.9), blend=BLEND_ADDITIVE))}})
       .with_sub_emitters(sub_emitter("eclipse:stern_komet_sparkle", event="Tick",
                                      probability=1.0, tick_interval=2))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_sparkle() -> FxBuilder:
    """Tiny 4-mote glitter burst inheriting the falling head's position (Tick sub-target)."""
    fx = FxBuilder("stern_komet_sparkle")
    (fx.particle_emitter("glitter",
            duration=8, looping=False, start_lifetime=random_between(8, 14),
            start_speed=random_between(0.02, 0.08),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(sphere(radius=0.25, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.2, 1.7), blend=BLEND_ADDITIVE))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_impact() -> FxBuilder:
    """HDR detonation on the damage tick — caller applies setDelay(telegraph)."""
    fx = FxBuilder("stern_komet_impact")
    root = fx.empty("impact")

    (fx.particle_emitter("core_flash",
            duration=40, looping=False, start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(2.4), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(2.2, 2.0, 3.0), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    # Vertical light pillar: stretched along a slow upward velocity.
    (fx.particle_emitter("pillar",
            duration=40, looping=False, start_lifetime=constant(16),
            start_speed=constant(0.4), start_size=nf3(0.9), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(cone(angle=0.5, radius=0.05))
       .with_material(texture_material(CIRCLE, hdr=(1.6, 1.6, 2.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=4.0)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)], [(0.0, 0.9, 0.95, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("ground_ring",
            duration=40, looping=False, start_lifetime=constant(14), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.2, 1.2, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 9.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.85), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    (fx.particle_emitter("debris",
            duration=40, looping=False, start_lifetime=random_between(20, 35),
            start_speed=random_between(0.4, 1.0),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30))])
       .with_shape(sphere(radius=0.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.1, 1.1, 1.5), blend=BLEND_ADDITIVE))
       .with_physics(collision=True, friction=0.98, collided_friction=0.6, gravity=0.4,
                     bounce_chance=0.5, bounce_rate=0.35, bounce_spread=0.1)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (1.0, 0.55, 0.65, 1.0)]))
       .with_lights(sky=15, block=15))

    # Slow afterglow dome so the bloom decays instead of cutting.
    (fx.particle_emitter("dome",
            duration=40, looping=False, start_delay=constant(2), start_lifetime=constant(30),
            start_speed=constant(0), start_size=nf3(2.0), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.4, [SEG_LINEAR_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.3), (1.0, 0.0)],
                [(0.0, 0.75, 0.8, 1.0), (1.0, 0.45, 0.55, 0.85)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 4 — eclipse:riss_schlag_maw + eclipse:riss_glitch_pop (two files)
# ---------------------------------------------------------------------------
def build_riss_schlag_maw() -> FxBuilder:
    """Implosion: shell-spawned streaks sucked INWARD (negative radial), Death sub-chain."""
    fx = FxBuilder("riss_schlag_maw")
    root = fx.empty("maw")

    (fx.particle_emitter("maw_suck",
            duration=25, looping=False, start_lifetime=random_between(5, 8),
            start_speed=constant(0),
            start_size=nf3(random_between(0.1, 0.2), random_between(0.1, 0.2),
                           random_between(0.1, 0.2)),
            simulation_space="Local", max_particles=96)
       .child_of(root)
       .with_emission(rate=constant(3.0))
       .with_shape(sphere(radius=3.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=(0.9, 1.3, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.0)
       .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0))
       .main(start_color=random_color(0xFF37E6E6, 0xFFE23AE2))  # glitch cyan <-> magenta
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-0.9)),  # the implosion
            color_over_lifetime=gradient([(0.0, 0.0), (0.25, 1.0), (1.0, 0.6)],
                                         [(0.0, 1.0, 1.0, 1.0)]))
       .with_sub_emitters(sub_emitter("eclipse:riss_glitch_pop", event="Death",
                                      probability=0.35, inherit=("Color",)))
       .with_lights(sky=15, block=15))

    # Broken-TV lip ring: slow roll + 2x2 flipbook flicker over the soft dot = datamosh bands.
    (fx.particle_emitter("lip_ring",
            duration=25, looping=False, start_lifetime=constant(25), start_speed=constant(0),
            start_size=nf3(6.5), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(0.8, 1.4, 1.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0))
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(4.0)),
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=curve(0.0, 4.0, [SEG_LINEAR_UP]), cycle=5.0),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.7), (0.85, 0.55), (1.0, 0.0)],
                [(0.0, 0.55, 0.95, 1.0), (1.0, 0.85, 0.4, 1.0)])))
    return fx


def build_riss_glitch_pop() -> FxBuilder:
    """3-particle hard-additive static burst (pixelArt bits=4) — Death sub-emitter target."""
    fx = FxBuilder("riss_glitch_pop")
    (fx.particle_emitter("static",
            duration=6, looping=False, start_lifetime=constant(4),
            start_speed=random_between(0.02, 0.1),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
       .with_shape(sphere(radius=0.15, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.0, 1.4, 1.5), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .main(start_color=random_color(0xFF66FFFF, 0xFFFFFFFF))
       .with_curves(color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
                                                 [(0.0, 1.0, 1.0, 1.0)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 5 — eclipse:glut_sprung_crater + glut_splash + glut_ember_die
# ---------------------------------------------------------------------------
def build_glut_sprung_crater() -> FxBuilder:
    """Eruption with REAL world-collision debris. 14 colliders (physics is Photon's most
    expensive module, FX_FORMAT §9 — never raise this burst above ~24)."""
    fx = FxBuilder("glut_sprung_crater")
    root = fx.empty("eruption")

    (fx.particle_emitter("magma_chunks",
            duration=50, looping=False, start_lifetime=random_between(30, 45),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.12, 0.28), random_between(0.12, 0.28),
                           random_between(0.12, 0.28)),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(cone(angle=40.0, radius=0.4))
       .with_material(texture_material(CIRCLE, hdr=(1.6, 0.8, 0.25), blend=BLEND_ADDITIVE))
       .main(start_color=random_color(0xFFFFC873, 0xFFFF7B3C))
       .with_physics(collision=True, friction=0.99, collided_friction=0.6, gravity=0.5,
                     bounce_chance=0.8, bounce_rate=0.45, bounce_spread=0.15)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.75, 0.85), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.8), (0.4, 1.0, 0.55, 0.2), (1.0, 0.45, 0.12, 0.04)]))
       .with_sub_emitters(
            sub_emitter("eclipse:glut_splash", event="Collision", probability=0.5),
            sub_emitter("eclipse:glut_ember_die", event="Death", probability=0.3))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("crater_flash",
            duration=50, looping=False, start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(1.8), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(2.0, 1.1, 0.3), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.35, 0.08, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("ground_ring",
            duration=50, looping=False, start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(0.8), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=(1.4, 0.7, 0.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 7.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 0.8, 0.5)])))

    (fx.particle_emitter("smoke",
            duration=50, looping=False, start_lifetime=constant(40),
            start_speed=random_between(0.03, 0.08),
            start_size=nf3(random_between(0.4, 0.7), random_between(0.4, 0.7),
                           random_between(0.4, 0.7)),
            simulation_space="World", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(cone(angle=25.0, radius=0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.0, [SEG_LINEAR_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.45), (1.0, 0.0)],
                [(0.0, 0.35, 0.28, 0.25), (1.0, 0.15, 0.12, 0.1)])))
    return fx


def build_glut_splash() -> FxBuilder:
    """5 tiny embers per terrain bounce (Collision sub-emitter target)."""
    fx = FxBuilder("glut_splash")
    (fx.particle_emitter("splash",
            duration=10, looping=False, start_lifetime=constant(8),
            start_speed=random_between(0.15, 0.35),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(cone(angle=55.0, radius=0.1))
       .with_material(texture_material(CIRCLE, hdr=(1.4, 0.7, 0.2), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.3, bounce_chance=0.0)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 0.7, 0.3), (1.0, 0.6, 0.2, 0.05)]))
       .with_lights(sky=15, block=15))
    return fx


def build_glut_ember_die() -> FxBuilder:
    """2-particle fizzle when a magma chunk expires (Death sub-emitter target)."""
    fx = FxBuilder("glut_ember_die")
    (fx.particle_emitter("fizzle",
            duration=8, looping=False, start_lifetime=constant(6),
            start_speed=random_between(0.01, 0.05),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="World", max_particles=6)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(sphere(radius=0.08, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(1.1, 0.5, 0.15), blend=BLEND_ADDITIVE))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (1.0, 0.0)], [(0.0, 1.0, 0.55, 0.2), (1.0, 0.4, 0.12, 0.03)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 6 — per-path idle hand auras (WINDOWED loops; WandAuraClient owns the window)
# All: looping, prewarm 10, Local space, cull box +-2, maxParticles <= 48.
# ---------------------------------------------------------------------------
def build_wand_idle_riss() -> FxBuilder:
    """Glitch scanline ribbon circling the hand + sparse 2-px squares (Photon-only combo:
    ara ribbon + pixelArt). Orbit pattern: one near-invisible mote dragged around by
    orbital velocity, its ARA_TRAIL ribbon draws the scanline circle (concept-7 pattern)."""
    fx = FxBuilder("wand_idle_riss")
    (fx.particle_emitter("orbiter",
            duration=40, looping=True, prewarm=10, start_lifetime=constant(40),
            start_speed=constant(0), start_size=nf3(0.02),
            start_color=color(0x30FFFFFF),  # the ribbon is the show, not the mote
            simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.25, thickness=0.0, arc_mode="Loop", arc_speed=1.0))
       .with_material(texture_material(CIRCLE, blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(velocity_over_lifetime=dict(
            orbital_mode="AngularVelocity",
            orbital=nf3(constant(0), constant(0.3), constant(0))))
       .with_module("trails", {
            "ratio": F(1.0), "lifetime": constant(1.0),
            "dieWithParticles": B(1), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "colorOverLifetime": gradient([(0.0, 0.9), (1.0, 0.6)], [(0.0, 1.0, 1.0, 1.0)]),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "thickness": F(0.05), "time": F(0.5), "alignment": "View", "space": "Local",
                # hard color steps = glitch bands; flickering thickness = scanline read
                "colorOverTime": gradient(
                    [(0.0, 0.85), (1.0, 0.5)],
                    [(0.0, 0.22, 0.9, 0.9), (0.48, 0.22, 0.9, 0.9),
                     (0.52, 0.89, 0.23, 0.89), (1.0, 0.89, 0.23, 0.89)]),
                "thicknessOverTime": curve(
                    0.4, 1.0, [(0.0, 1.0, 0.25, 0.1, 0.75, 0.9, 1.0, 0.3)]),
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=(0.9, 1.2, 1.2), blend=BLEND_ADDITIVE),
                    cull_box=((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0)))}}))

    (fx.particle_emitter("squares",
            duration=40, looping=True, prewarm=10, start_lifetime=random_between(8, 14),
            start_speed=random_between(0.01, 0.04),
            start_size=nf3(random_between(0.03, 0.05), random_between(0.03, 0.05),
                           random_between(0.03, 0.05)),
            start_color=random_color(0xFF37E6E6, 0xFFE23AE2),
            simulation_space="Local", max_particles=24)
       .with_emission(rate=constant(0.3))
       .with_shape(sphere(radius=0.3, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=(0.8, 1.0, 1.0), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))
    return fx


def build_wand_idle_glut() -> FxBuilder:
    """Ember ring: emission point orbits a cylinder shell (Template B shapeArc Loop)."""
    fx = FxBuilder("wand_idle_glut")
    (fx.particle_emitter("ember_ring",
            duration=60, looping=True, prewarm=10, start_lifetime=random_between(20, 30),
            start_speed=constant(0),
            start_size=nf3(random_between(0.04, 0.09), random_between(0.04, 0.09),
                           random_between(0.04, 0.09)),
            simulation_space="Local", max_particles=48)
       .with_emission(rate=constant(0.8))
       .with_shape(cylinder(radius=0.35, thickness=0.1, arc_mode="Loop", arc_speed=0.6))
       .with_material(texture_material(CIRCLE, hdr=(1.3, 0.5, 0.15), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.02), constant(0))),
            color_over_lifetime=gradient(  # white-hot -> deep red -> 0
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.92, 0.75), (0.4, 1.0, 0.45, 0.12), (1.0, 0.35, 0.05, 0.02)]))
       .with_lights(sky=15, block=15))
    return fx


def build_wand_idle_stern() -> FxBuilder:
    """Star halo: tilted circle of near-static twinkling motes with hairline trails
    drawing constellation lines between slow drifters."""
    fx = FxBuilder("wand_idle_stern")
    (fx.particle_emitter("star_halo",
            duration=60, looping=True, prewarm=10, start_lifetime=random_between(30, 45),
            start_speed=random_between(0.01, 0.03),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            simulation_space="Local", max_particles=32)
       .with_emission(rate=constant(0.4))
       .with_shape(circle(radius=0.4, thickness=0.3), rotation=nf3(20.0, 0.0, 0.0))
       .with_material(texture_material(CIRCLE, hdr=(1.0, 1.0, 1.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.01), constant(0.01), constant(0.01)),
                       rotation=constant(0), size=constant(0)),
            size_over_lifetime=curve(  # double-hump twinkle
                0.3, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)]))
       .with_module("trails", {
            "ratio": F(0.3), "lifetime": constant(1.0),
            "dieWithParticles": B(1), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "colorOverLifetime": gradient([(0.0, 0.5), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)]),
            "trailType": "TRAIL",
            "config": {
                "time": I(10), "minVertexDistance": F(0.02),
                "widthOverTrail": constant(0.02),
                "colorOverTrail": gradient([(0.0, 0.5), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)]),
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=(0.9, 0.9, 1.3), blend=BLEND_ADDITIVE),
                    cull_box=((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0)))}}))
    return fx


BUILDERS = {
    "wand_soulbind_flash.fx": build_wand_soulbind_flash,
    "stern_komet_fall.fx": build_stern_komet_fall,
    "stern_komet_sparkle.fx": build_stern_komet_sparkle,
    "stern_komet_impact.fx": build_stern_komet_impact,
    "riss_schlag_maw.fx": build_riss_schlag_maw,
    "riss_glitch_pop.fx": build_riss_glitch_pop,
    "glut_sprung_crater.fx": build_glut_sprung_crater,
    "glut_splash.fx": build_glut_splash,
    "glut_ember_die.fx": build_glut_ember_die,
    "wand_idle_riss.fx": build_wand_idle_riss,
    "wand_idle_glut.fx": build_wand_idle_glut,
    "wand_idle_stern.fx": build_wand_idle_stern,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
