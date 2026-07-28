#!/usr/bin/env python3
"""ceremony_fx — NEWFX-B Photon `.fx` assets (altar, souls & ceremonies), via fxlib.

Generates the five PLAN-NEWFX §2 B-package effects (into
`src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

    eclipse:dawn_toll_bloom       B1 dawn-toll sky petals, paced to the 3x8t bell rhythm
    eclipse:rebirth_starfall      B2 star-converge + wing-shell rebirth ceremony (REPLACE)
    eclipse:offering_gutter       B3 altar rejection tell (cold ember + falling ash)
    eclipse:ghost_soul_departure  B4 permanent-death mist peel + soul ribbon + glitch pop
    eclipse:revive_thunderbloom   B5 revive completion white collapse + violet lightning ring

These files are fxlib-generated (this script IS the committed source — the binary-diff
law's `.fxproj` requirement applies to editor exports only, tools/photon precedent).
Regenerate + validate with:

    python3 tools/photon/ceremony_fx.py
    python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/{dawn_toll_bloom,rebirth_starfall,offering_gutter,ghost_soul_departure,revive_thunderbloom}.fx

Style-guide conformance (FX-STYLE-GUIDE.md):
  - Palette: SACRED tokens only (§1.1) + the sanctioned GLI_* split pair on B4's tear
    (§1.3 — magenta/cyan appear ONLY as a pair displaced along one axis). Every gradient
    ends on SAC_VOID #2E2347, never transparent-black RGB.
  - Motion: sacred verbs (§2) — slow orbits/verticals, smoothstep-ish curves; nothing
    sacred moves fast except the first 2-4t of an impact. B4's tear uses glitch verbs:
    NO easing, constant sizes, 45-degree rotation snaps, hold-then-pop.
  - Timing: 8-12t anticipation / 2-4t impact / 20-40t settle spines (§3); B1 repeats a
    soft spine per bell toll (staged via startDelay); B2 is a SEQUENCE-class ceremony
    whose star-fall pre-beat feeds the 6t indraw anticipation.
  - Budgets: every one-shot stays under ~90 particles; gold stays <= 35% of any
    settle population (§1.1 rule); B3 is deliberately HDR-free (anti-climax).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, REPO_ROOT,
    SEG_LINEAR_DOWN, SEG_LINEAR_UP, burst, circle, cone, constant, curve, gradient,
    nf3, random_between, sphere, box, texture_material, validate_file,
)

# Photon's shipped particle set + the eclipse-owned soft sprites (all already in-repo).
TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING = "photon:textures/particle/ring.png"
TEX_LASER = "photon:textures/particle/laser.png"
TEX_PETAL = "eclipse:textures/particle/petal_soft.png"
TEX_WISP = "eclipse:textures/particle/wisp_white.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_BEAM_CORE = "eclipse:textures/particle/beam_core.png"
TEX_STATIC = "eclipse:textures/particle/static_4x4.png"

# ---------------------------------------------------------------------------
# FX-STYLE-GUIDE §1.1 SACRED tokens (rgb 0..1 for gradients) + §1.3 GLITCH pair
# ---------------------------------------------------------------------------
def rgb(hexcode: int):
    return ((hexcode >> 16 & 0xFF) / 255.0, (hexcode >> 8 & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


SAC_HOT = rgb(0xF6EFFF)        # white-violet cores, first 2-4t of any impact
SAC_VIOLET = rgb(0xB98CFF)     # THE purple, mid-life of every sacred particle
SAC_DEEP = rgb(0x7B4FD0)       # tails, outer glow
SAC_GOLD = rgb(0xFFD166)       # divinity accents, impact frames only
SAC_GOLD_PALE = rgb(0xFFE9A8)  # gold afterglow, chime swells
SAC_VOID = rgb(0x2E2347)       # fade-out target (never fade to black)
GLI_MAGENTA = rgb(0xFF4FD8)    # + channel fringe (B4 tear only, paired)
GLI_CYAN = rgb(0x4FE8FF)       # - channel fringe (always opposite magenta)

# The sanctum HOT->VIOLET->DEEP->VOID lifetime run (§1.1 rule), reused everywhere.
def sacred_run(a0=1.0, a_mid=0.8):
    return gradient(
        [(0.0, a0), (0.55, a_mid), (1.0, 0.0)],
        [(0.0,) + SAC_HOT, (0.35,) + SAC_VIOLET, (0.75,) + SAC_DEEP, (1.0,) + SAC_VOID])


# Smoothstep-ish bloom: ease in, hold, ease out (sacred easing — nothing linear).
SEG_BLOOM = (0.0, 0.0, 0.25, 0.05, 0.35, 1.0, 1.0, 1.0)
# Pop to full in ~15% then gently decay to 0 (impact frames + settle).
SEG_FLASH = (0.0, 0.2, 0.08, 1.0, 0.5, 0.6, 1.0, 0.0)
# Ease-out shrink (retreating wisps / collapsing shells).
SEG_SHRINK = (0.0, 1.0, 0.4, 0.9, 0.8, 0.3, 1.0, 0.0)
# sin(pi*t)-like swell: rise to full at midlife, sink back (petal breath, §2 SACRED).
SEG_SWELL = (0.0, 0.0, 0.35, 1.05, 0.65, 1.05, 1.0, 0.0)


def sz(lo, hi, seg, x_axis="lifetime"):
    """NF3 size_over_lifetime from one shared bezier segment."""
    return nf3(*[curve(lo, hi, [seg], x_axis, "size") for _ in range(3)])


# ---------------------------------------------------------------------------
# B1 eclipse:dawn_toll_bloom — three god-ray petals synced to the descending bells
# ---------------------------------------------------------------------------
# DawnCeremony.dawnToll(): TOLL_PITCHES fire at +0/+8/+16 (TOLL_SPACING_TICKS = 8),
# drone tail at +24. The cue is sent the same tick as bell 0, so petal k OPENS on
# bell k (startDelay k*8) and its ~8t bloom-in (the §3 anticipation) peaks exactly as
# the next sound lands — petal 0 full on bell 1, petal 1 on bell 2, petal 2 on the
# drone tail. Each strike is answered by light; 20-30t of glint dust settles after.
BELL_SPACING = 8


def build_dawn_toll_bloom() -> FxBuilder:
    """Entity-anchored on the receiving player (personal sky ceremony). ~40 particles.
    Sky read: petals hang 7-8 blocks over the eye in a loose cathedral triangle."""
    fx = FxBuilder("dawn_toll_bloom")
    root = fx.empty("dawn_root").at(0.0, 7.0, 0.0)
    # Petal placement: a descending arc — each later (deeper) bell blooms lower.
    petal_spots = [(0.0, 1.2, -2.6, -18.0), (2.4, 0.4, 1.4, 14.0), (-2.4, -0.4, 1.4, -10.0)]
    for k, (px, py, pz, tilt) in enumerate(petal_spots):
        delay = k * BELL_SPACING
        # God-ray petal: one big soft vertical quad blooming open on the bell strike.
        (fx.particle_emitter(
                f"petal_{k}",
                duration=40 + delay, looping=False, start_delay=constant(delay),
                start_lifetime=constant(34), start_speed=constant(0.0),
                start_size=nf3(1.0), simulation_space="World", max_particles=2)
           .child_of(root)
           .at(px, py, pz).rotated(0.0, k * 60.0, tilt)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
           .with_shape(circle(radius=0.01, thickness=0.0))
           .with_material(texture_material(TEX_PETAL, hdr=(1.1, 1.0, 1.4),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
           .with_curves(
                # 8t bloom-in (anticipation ending on the strike), swell, sink to VOID.
                size_over_lifetime=sz(0.0, 3.4, SEG_SWELL),
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.24, 0.85), (0.6, 0.5), (1.0, 0.0)],
                    [(0.0,) + SAC_HOT, (0.4,) + SAC_VIOLET, (1.0,) + SAC_VOID])))
        # Bell-glint dust ring shed by the petal: sinks, never rises (§2 "veils fall").
        # Gold is rationed (§1.1 rule, <= 35%): 3 gold chime-glints ride 6 violet ones.
        for suffix, count, head, hdr in (("v", 6, SAC_HOT, (0.85, 0.8, 1.0)),
                                         ("g", 3, SAC_GOLD_PALE, (1.0, 0.9, 0.55))):
            (fx.particle_emitter(
                    f"glint_{k}{suffix}",
                    duration=40 + delay, looping=False, start_delay=constant(delay + 6),
                    start_lifetime=random_between(24, 36),
                    start_speed=random_between(0.02, 0.05),
                    start_size=nf3(random_between(0.1, 0.18)),
                    simulation_space="World", max_particles=count + 3)
               .child_of(root)
               .at(px, py - 0.6, pz)
               .with_emission(rate=constant(0.0),
                              bursts=[burst(time=0, count=constant(count))])
               .with_shape(circle(radius=1.1, thickness=0.2, arc_mode="BurstSpread"))
               .with_material(texture_material(TEX_CIRCLE, hdr=hdr,
                                               blend=BLEND_ADDITIVE))
               .with_renderer(vertex_sorting="NONE")
               .with_curves(
                    color_over_lifetime=gradient(
                        [(0.0, 0.0), (0.15, 0.8), (0.7, 0.4), (1.0, 0.0)],
                        [(0.0,) + head, (0.45,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
                    velocity_over_lifetime=dict(
                        linear=nf3(constant(0), random_between(-0.055, -0.03), constant(0)),
                        orbital=nf3(constant(0), constant(0.5), constant(0))),
                    size_over_lifetime=sz(0.4, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# B2 eclipse:rebirth_starfall — star converge -> indraw seam -> wing shell + ash rain
# ---------------------------------------------------------------------------
# REPLACE-mode hero (the Photon file IS the choreography). Entity-anchored on the
# reborn player (eye anchor; shells authored around chest = eye - 0.4). Timeline:
#   0->20   6 slow star-streaks fall inward from a wide sky ring (the hush)
#   16->24  indraw shell collapses to the seam (anticipation proper)
#   24->27  blinding seam flash (IMPACT, 3t)
#   26->46  wing-shell of violet fire snaps open (two mirrored fans)
#   28->70  ash-glitter rain settles (gold <= ~30% of the rain)
def build_rebirth_starfall() -> FxBuilder:
    fx = FxBuilder("rebirth_starfall")
    chest = fx.empty("rebirth_chest").at(0.0, -0.4, 0.0)

    # L1 star streaks: ring radius 8 at +7 over the eye, drifting inward + down so the
    # streak heads converge into the player. StretchedBillboard = the streak read.
    (fx.particle_emitter(
            "star_streaks",
            duration=24, looping=False,
            start_lifetime=random_between(16, 20),
            start_speed=random_between(-0.6, -0.5),  # radially INWARD off the ring
            start_size=nf3(random_between(0.22, 0.34)),
            simulation_space="World", max_particles=8)
       .at(0.0, 7.0, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(circle(radius=8.0, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.35, 1.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=6.0,
                      velocity_scale=0.35, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 1.0), (0.85, 0.8), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.55,) + SAC_VIOLET, (0.85,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            # Descent: the ring is +7.4 over the chest, ~18t of fall.
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(-0.42), constant(0))))
       .with_lights(sky=15, block=15))

    # L2 indraw shell: a breath of motes collapsing to the seam (6t anticipation).
    (fx.particle_emitter(
            "indraw_shell",
            duration=26, looping=False, start_delay=constant(16),
            start_lifetime=constant(8), start_speed=constant(-0.24),
            start_size=nf3(random_between(0.1, 0.16)),
            simulation_space="World", max_particles=16)
       .child_of(chest)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(sphere(radius=1.7, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.8, 0.7, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.3), (0.8, 0.95), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (0.7,) + SAC_VIOLET, (1.0,) + SAC_HOT]),
            size_over_lifetime=sz(1.0, 0.3, SEG_LINEAR_DOWN)))

    # L3 the blinding seam (IMPACT, 3t): one vertical hairline flaring open.
    (fx.particle_emitter(
            "seam_flash",
            duration=30, looping=False, start_delay=constant(24),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(constant(0.55), constant(2.4), constant(0.55)),
            simulation_space="World", max_particles=2)
       .child_of(chest)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_BEAM_CORE, hdr=(2.2, 2.0, 2.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.5,) + SAC_HOT, (1.0,) + SAC_VIOLET]),
            size_over_lifetime=sz(0.3, 1.0, SEG_FLASH))
       .with_lights(sky=15, block=15))

    # L4 wing shell: two mirrored fans of violet fire snapping open off the shoulders.
    for name, zrot in (("wing_l", 55.0), ("wing_r", -55.0)):
        (fx.particle_emitter(
                name,
                duration=50, looping=False, start_delay=constant(26),
                start_lifetime=random_between(12, 20),
                start_speed=random_between(0.45, 0.8),
                start_size=nf3(random_between(0.22, 0.4)),
                simulation_space="World", max_particles=20)
           .child_of(chest)
           .at(0.0, 0.2, 0.0).rotated(0.0, 0.0, zrot)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
           .with_shape(cone(angle=24.0, radius=0.22, thickness=0.4,
                            arc_mode="BurstSpread"))
           .with_material(texture_material(TEX_WISP, hdr=(1.3, 1.1, 1.7),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="StretchedBillboard", length_scale=2.6,
                          velocity_scale=0.2, vertex_sorting="NONE")
           .with_curves(
                color_over_lifetime=sacred_run(1.0, 0.85),
                # Fire decelerates fast after the 2-4t snap (sacred: only impacts are fast).
                velocity_over_lifetime=dict(
                    linear=nf3(0), speed_modifier=curve(0.15, 1.0, [SEG_SHRINK],
                                                        "lifetime", "value")),
                size_over_lifetime=sz(0.5, 1.1, SEG_SHRINK)))

    # L5 ash-glitter rain (settle): violet body + a smaller gold voice (<= ~30%).
    for name, count, cols, hdr in (
            ("glitter_violet", 18,
             [(0.0,) + SAC_HOT, (0.4,) + SAC_VIOLET, (1.0,) + SAC_VOID], (0.7, 0.6, 0.9)),
            ("glitter_gold", 7,
             [(0.0,) + SAC_GOLD, (0.5,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID], (1.0, 0.9, 0.5))):
        (fx.particle_emitter(
                name,
                duration=40, looping=False, start_delay=constant(28),
                start_lifetime=random_between(28, 42),
                start_speed=random_between(0.04, 0.1),
                start_size=nf3(random_between(0.07, 0.13)),
                simulation_space="World", max_particles=count + 4)
           .child_of(chest)
           .at(0.0, 1.0, 0.0)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(count))])
           .with_shape(sphere(radius=1.4, thickness=0.5, arc=180.0))
           .with_material(texture_material(TEX_CIRCLE, hdr=hdr, blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                         collided_friction=0.6, gravity=0.045, bounce_chance=0.25,
                         bounce_rate=0.25, bounce_spread=0.05)
           .with_curves(
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.12, 0.9), (0.7, 0.5), (1.0, 0.0)], cols),
                size_over_lifetime=sz(0.35, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# B3 eclipse:offering_gutter — the rejection anti-climax (~25t, deliberately muted)
# ---------------------------------------------------------------------------
# Position-anchored at the altar crown. No HDR, no lights, nothing rises except
# nothing: the flame goes cold (shrink), one gray ash cough FALLS, and two dim
# violet wisps retreat INTO the stone. Refusal read in one glance, values secret.
def build_offering_gutter() -> FxBuilder:
    fx = FxBuilder("offering_gutter")
    # L1 cold ember: the crown flame shrinking to a dim point (8-10t anticipation).
    (fx.particle_emitter(
            "cold_ember",
            duration=20, looping=False,
            start_lifetime=constant(14), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_WISP, blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.06, 0.55, SEG_SHRINK),
            color_over_lifetime=gradient(
                [(0.0, 0.75), (0.5, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_VIOLET, (0.45, 0.42, 0.39, 0.46), (1.0,) + SAC_VOID])))
    # L2 the cough (the anti-impact, t=10): one gray ash puff that only ever falls.
    (fx.particle_emitter(
            "ash_cough",
            duration=24, looping=False, start_delay=constant(10),
            start_lifetime=random_between(18, 26),
            start_speed=random_between(0.04, 0.09),
            start_size=nf3(random_between(0.09, 0.16)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=0.18, thickness=0.6, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_physics(collision=True, removed_when_collided=False, friction=0.985,
                     collided_friction=0.7, gravity=0.14, bounce_chance=0.0,
                     bounce_rate=0.0)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.7), (0.65, 0.45), (1.0, 0.0)],
                [(0.0, 0.54, 0.52, 0.58), (0.5, 0.35, 0.33, 0.4), (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.6, 1.15, SEG_LINEAR_UP)))
    # L3 two dim wisps retreating INTO the stone (radial inward + sinking, shrink out).
    (fx.particle_emitter(
            "wisp_retreat",
            duration=30, looping=False, start_delay=constant(12),
            start_lifetime=constant(14), start_speed=constant(-0.001),
            start_size=nf3(random_between(0.14, 0.2)),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(sphere(radius=0.55, thickness=0.0, arc=180.0,
                          arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_WISP, blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (1.0,) + SAC_VOID]),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(-0.06), constant(0)),
                radial=constant(-0.1)),
            size_over_lifetime=sz(0.2, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# B4 eclipse:ghost_soul_departure — mist peel, kneel-hold, skyward tear (~70t)
# ---------------------------------------------------------------------------
# Position-anchored at the corpse (feet). Timeline:
#   0->24   pale mist silhouette peels off the corpse and KNEELS (near-still hold)
#   24->56  the silhouette + a stretching soul-ribbon are drawn skyward, accelerating
#   56->60  the ribbon TEARS: 1-2t white pop + magenta/cyan split pair (glitch verbs:
#           zero easing, hard quads, 45-degree snaps — §1.3/§2 GLITCH)
def build_ghost_soul_departure() -> FxBuilder:
    fx = FxBuilder("ghost_soul_departure")
    # L1 mist silhouette: kneeling-height alpha-mist, holds, then is drawn up late.
    (fx.particle_emitter(
            "mist_silhouette",
            duration=16, looping=False,
            start_lifetime=random_between(44, 56),
            start_speed=random_between(0.005, 0.015),
            start_size=nf3(random_between(0.28, 0.44)),
            simulation_space="World", max_particles=26)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(22))])
       .with_shape(box(emit_from="Volume"), position=(0.0, 0.55, 0.0),
                   scale=(0.55, 1.1, 0.4))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            # Ghost-pale: desaturated HOT at low alpha; fade lands on VOID.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.3), (0.55, 0.26), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.6, 0.72, 0.66, 0.86), (1.0,) + SAC_VOID]),
            # The kneel-hold: near-zero rise for ~55% of life, then drawn skyward.
            velocity_over_lifetime=dict(linear=nf3(
                constant(0),
                curve(0.0, 0.5, [(0.0, 0.02, 0.5, 0.02, 0.7, 0.6, 1.0, 1.0)],
                      "lifetime", "value"),
                constant(0))),
            size_over_lifetime=sz(0.7, 1.15, SEG_LINEAR_UP)))
    # L2 soul ribbon: stretched wisps accelerating skyward off the chest (24->56).
    (fx.particle_emitter(
            "soul_ribbon",
            duration=20, looping=False, start_delay=constant(24),
            start_lifetime=random_between(26, 32),
            start_speed=random_between(0.01, 0.03),
            start_size=nf3(random_between(0.14, 0.22)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4)),
                                                  burst(time=6, count=constant(3)),
                                                  burst(time=12, count=constant(3))])
       .with_shape(sphere(radius=0.25, thickness=0.5), position=(0.0, 1.0, 0.0))
       .with_material(texture_material(TEX_WISP, hdr=(1.1, 1.0, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=5.0,
                      velocity_scale=0.5, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.6), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.5,) + SAC_VIOLET, (0.8,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            # The draw: 0.05 -> 1.05 blk/t upward over each wisp's life (stretching).
            velocity_over_lifetime=dict(linear=nf3(
                constant(0),
                curve(0.05, 1.05, [SEG_LINEAR_UP], "lifetime", "value"),
                constant(0))))
       .with_lights(sky=13, block=13))
    # L3 the tear (t=56, where ~28t of accelerating rise puts the ribbon head ~9 up):
    # GLITCH verbs — a 2t white pop plus a magenta/cyan split pair displaced along X.
    (fx.particle_emitter(
            "tear_pop",
            duration=62, looping=False, start_delay=constant(56),
            start_lifetime=constant(2), start_speed=constant(0.0),
            start_size=nf3(0.8), simulation_space="World", max_particles=2)
       .at(0.0, 9.0, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.0, 2.0, 2.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0)])))
    for name, off_x, col in (("tear_fringe_m", 0.14, GLI_MAGENTA),
                             ("tear_fringe_c", -0.14, GLI_CYAN)):
        (fx.particle_emitter(
                name,
                duration=64, looping=False, start_delay=constant(56),
                start_lifetime=constant(5), start_speed=constant(0.0),
                # Glitch grammar: constant size, 45-degree rotation, NO easing anywhere.
                start_size=nf3(0.22), start_rotation=nf3(constant(0), constant(0),
                                                         constant(45.0)),
                simulation_space="World", max_particles=4)
           .at(off_x, 9.0, 0.0)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
           .with_shape(box(emit_from="Volume"), scale=(0.05, 0.6, 0.05))
           .with_material(texture_material(TEX_STATIC, hdr=(1.2, 1.2, 1.2),
                                           discard=0.2, blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_curves(color_over_lifetime=gradient(
                [(0.0, 1.0), (0.79, 1.0), (0.8, 0.0), (1.0, 0.0)],  # snap-off, no fade
                [(0.0,) + col, (1.0,) + col])))
    return fx


# ---------------------------------------------------------------------------
# B5 eclipse:revive_thunderbloom — white collapse -> violet lightning ring (~60t)
# ---------------------------------------------------------------------------
# Position-anchored at the altar crown. Timeline:
#   0->12   white beam snap + motes indraw into the sigil (anticipation)
#   12->15  bloom flash (IMPACT, 3t)
#   12->30  ground-hugging ring of violet lightning filaments races outward
#   15->58  heart motes rise and settle (violet body + <= 25% gold glints)
def build_revive_thunderbloom() -> FxBuilder:
    fx = FxBuilder("revive_thunderbloom")
    # L1a the beams "snap to white": one hot vertical column collapsing into the sigil.
    fx.beam_emitter(
        "white_snap", end=(0.0, 22.0, 0.0), duration=13, looping=False,
        width=curve(0.12, 1.0, [SEG_LINEAR_DOWN], "duration"),
        raycast="NONE",
        color_nf=gradient(
            [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.6,) + SAC_HOT, (1.0,) + SAC_VIOLET])
    ).with_material(texture_material(TEX_BEAM_CORE, hdr=(2.0, 1.9, 2.4),
                                     blend=BLEND_ADDITIVE))
    # L1b indraw motes: the witness ring pulled into the sigil (12t anticipation).
    (fx.particle_emitter(
            "sigil_indraw",
            duration=12, looping=False,
            start_lifetime=random_between(9, 12), start_speed=random_between(-0.4, -0.3),
            start_size=nf3(random_between(0.09, 0.15)),
            simulation_space="World", max_particles=14)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6)),
                                                  burst(time=4, count=constant(6))])
       .with_shape(circle(radius=3.4, thickness=0.15, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.8, 0.7, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.2), (0.75, 0.9), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (0.7,) + SAC_VIOLET, (1.0,) + SAC_HOT])))
    # L2 bloom flash (IMPACT): a soft expanding ring quad, 3t of money frames.
    (fx.particle_emitter(
            "bloom_flash",
            duration=18, looping=False, start_delay=constant(12),
            start_lifetime=constant(6), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_RING_SOFT, hdr=(2.2, 2.0, 2.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.4, 5.5, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.4,) + SAC_HOT, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    # L3 the lightning ring: fast-out filaments hugging the ground, noise-crackled.
    # FX-Wave-11 stacking-law pass: 26 additive filaments born on a 0.4 r shell all
    # overlapped at the sigil for the first ticks, adding a second white ball right
    # after the bloom flash. Count 26->14 on a 1.2 r shell, hdr ~1.45, crest 1.0->0.65.
    (fx.particle_emitter(
            "lightning_ring",
            duration=20, looping=False, start_delay=constant(12),
            start_lifetime=random_between(12, 18),
            start_speed=random_between(0.5, 0.65),
            start_size=nf3(random_between(0.16, 0.26)),
            simulation_space="World", max_particles=30)
       .at(0.0, 0.15, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(circle(radius=1.2, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_LASER, hdr=(1.2, 1.0, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=3.2,
                      velocity_scale=0.4, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.65), (0.5, 0.52), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.35,) + SAC_VIOLET, (0.75,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            # Impact-fast for 2-4t, then the filaments stall and crackle out (§2).
            velocity_over_lifetime=dict(
                linear=nf3(0), speed_modifier=curve(0.1, 1.0, [SEG_SHRINK],
                                                    "lifetime", "value")),
            noise=dict(frequency=2.6, quality="Noise2D",
                       position=nf3(constant(0.16), constant(0.03), constant(0.16)),
                       rotation=constant(0), size=constant(0)))
       .with_lights(sky=15, block=15))
    # L4 heart motes: the settle — slow risers, violet body + a small gold voice.
    for name, count, cols, hdr in (
            ("heart_motes", 12,
             [(0.0,) + SAC_HOT, (0.4,) + SAC_VIOLET, (1.0,) + SAC_VOID], (0.8, 0.7, 1.0)),
            ("heart_glints", 4,
             [(0.0,) + SAC_GOLD_PALE, (0.5,) + SAC_GOLD, (1.0,) + SAC_VOID], (0.9, 0.8, 0.5))):
        (fx.particle_emitter(
                name,
                duration=30, looping=False, start_delay=constant(15),
                start_lifetime=random_between(30, 44),
                start_speed=random_between(0.02, 0.05),
                start_size=nf3(random_between(0.09, 0.15)),
                simulation_space="World", max_particles=count + 4)
           .at(0.0, 0.3, 0.0)
           .with_emission(rate=constant(0.0),
                          bursts=[burst(time=0, count=constant(count))])
           .with_shape(circle(radius=1.8, thickness=0.6))
           .with_material(texture_material(TEX_CIRCLE, hdr=hdr, blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_curves(
                color_over_lifetime=gradient(
                    [(0.0, 0.0), (0.15, 0.85), (0.7, 0.45), (1.0, 0.0)], cols),
                velocity_over_lifetime=dict(
                    linear=nf3(constant(0), random_between(0.03, 0.05), constant(0)),
                    orbital=nf3(constant(0), constant(0.6), constant(0))),
                size_over_lifetime=sz(0.4, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# main — write + validate all five
# ---------------------------------------------------------------------------
BUILDERS = {
    "dawn_toll_bloom.fx": build_dawn_toll_bloom,
    "rebirth_starfall.fx": build_rebirth_starfall,
    "offering_gutter.fx": build_offering_gutter,
    "ghost_soul_departure.fx": build_ghost_soul_departure,
    "revive_thunderbloom.fx": build_revive_thunderbloom,
}


def main() -> int:
    rc = 0
    for name, builder_fn in BUILDERS.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)  # write() round-trip-validates
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
