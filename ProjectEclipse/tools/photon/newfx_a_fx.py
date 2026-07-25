#!/usr/bin/env python3
"""newfx_a_fx — NEWFX-A Photon `.fx` assets (progression & personal celebration), via fxlib.

Generates the eight PLAN-NEWFX §2 A-package assets (into
`src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`), consumed by the
`veilfx/ProgressionPhotonFxRows` registrar:

    eclipse:quest_sigil_burst         A1 chest rune-ring snap + gold-violet glyph shatter
    eclipse:quest_sigil_pillar        A1 MAIN-goal one-beat light pillar (feet anchor;
                                      startDelay 8 lands it ON the shatter impact frame)
    eclipse:collection_tier_halo      A2 boot->crown glint-halo rise + crown flash
    eclipse:collection_tier_gold_rain A2 tier>=4 brief overhead gold rain (C2 GOLD RUSH
                                      license: collection tier-up is a reward moment)
    eclipse:skill_spend_glint         A3 near-invisible lens glint + constellation flicker
    eclipse:landmark_flare            A4 compass-rose reveal + sinking map-ink motes
    eclipse:landmark_echo             A4 discoverer's small personal glint echo
    eclipse:wizard_catalyst_handover  A5 shard indraw -> fuse flash -> star-trail drop

These files are fxlib-generated (this script IS the committed source — the binary-diff
law's `.fxproj` requirement applies to editor exports only, tools/photon precedent).
Regenerate + validate with:

    python3 tools/photon/newfx_a_fx.py
    python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/{quest_sigil_burst,quest_sigil_pillar,collection_tier_halo,collection_tier_gold_rain,skill_spend_glint,landmark_flare,landmark_echo,wizard_catalyst_handover}.fx

Style-guide conformance (FX-STYLE-GUIDE.md):
  - Palette: SACRED tokens (§1.1) everywhere except A3, which borrows the STORM support
    blues (§1.5 — the plan's "cyan sparks" ARE the skill-tree constellation family,
    `stern_constellation` precedent; GLI_CYAN is illegal outside a split pair). Every
    settle gradient ends on the context VOID token (`SAC_VOID` #2E2347 / `STM_SLATE`),
    never transparent-black. Gold stays <= 35% of any settle population except the
    tier>=4 gold rain, which rides the §5 C2 "one licensed gold lead" reward license.
  - Motion: sacred verbs (§2) — slow orbits + verticals, smoothstep-family bezier
    curves, nothing linear; only impact frames (first 2-4t) move fast (A4's compass
    needles shoot then stall via an eased speed_modifier decay).
  - Timing: every one-shot scans to the §3 spine — 8-12t anticipation / 2-4t impact /
    20-40t settle. A1: 8/3/~24. A2: 10/3/~30. A4: 12/3/~44. A5: 12/3/~30. A3 and the
    two garnish assets (pillar, echo) are sub-spine accents by design (<=1 beat).
  - Budget: every asset stays under ~40 live particles (worst A1+A2 stack ~60 << the
    §6.6 frame budget); every emitter ships a cull box; one dynamic-light-ish `lights`
    module only on impact-frame emitters.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ADDITIVE, BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, I, L, REPO_ROOT,
    aabb, burst, circle, cone, constant, curve, gradient, nf3, random_between,
    rom, sphere, texture_material, validate_file,
)

# Photon's shipped particle set + the eclipse-owned soft sprites (all already in-repo).
TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_SHARD = "eclipse:textures/particle/glitch_shard.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_BEAM_CORE = "eclipse:textures/particle/beam_core.png"
TEX_WISP = "eclipse:textures/particle/wisp_white.png"


# ---------------------------------------------------------------------------
# FX-STYLE-GUIDE §1.1 SACRED tokens (rgb 0..1 for gradients) + §1.5 STORM blues
# ---------------------------------------------------------------------------
def rgb(hexcode: int):
    return ((hexcode >> 16 & 0xFF) / 255.0, (hexcode >> 8 & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


SAC_HOT = rgb(0xF6EFFF)        # white-violet cores, first 2-4t of any impact
SAC_VIOLET = rgb(0xB98CFF)     # THE purple, mid-life of every sacred particle
SAC_DEEP = rgb(0x7B4FD0)       # tails, outer glow
SAC_GOLD = rgb(0xFFD166)       # divinity/reward accents, impact frames + glints
SAC_GOLD_PALE = rgb(0xFFE9A8)  # gold afterglow
SAC_VOID = rgb(0x2E2347)       # fade-out target (never fade to black)
GLI_WHITE = rgb(0xFFFFFF)      # 1-2t flash frames only
STM_ARC = rgb(0xBFD9FF)        # A3 skill sparks — the stern/constellation blue
STM_DEEP = rgb(0x5A8DEE)       # A3 tails
STM_SLATE = rgb(0x3A3A55)      # A3 fade target (STORM's void analog)

# Shared eased bezier segments (§2 sacred easing — nothing linear).
# Smoothstep-ish bloom: ease in, hold, ease out.
SEG_BLOOM = (0.0, 0.0, 0.25, 0.05, 0.35, 1.0, 1.0, 1.0)
# Pop to full in ~15% then gently decay to 0 (impact frames).
SEG_FLASH = (0.0, 0.2, 0.08, 1.0, 0.5, 0.6, 1.0, 0.0)
# Ease-out shrink (retreating / stalling motion).
SEG_SHRINK = (0.0, 1.0, 0.4, 0.9, 0.8, 0.3, 1.0, 0.0)
# sin(pi*t)-like swell: rise to full at midlife, sink back (§2 SACRED swells).
SEG_SWELL = (0.0, 0.0, 0.35, 1.05, 0.65, 1.05, 1.0, 0.0)
# Smoothstep 0 -> 1 (eased ramps, e.g. the A2 halo rise picking up speed).
SEG_EASE_UP = (0.0, 0.0, 0.45, 0.0, 0.55, 1.0, 1.0, 1.0)


def sz(lo, hi, seg, x_axis="lifetime"):
    """NF3 size_over_lifetime from one shared bezier segment."""
    return nf3(*[curve(lo, hi, [seg], x_axis, "size") for _ in range(3)])


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED ara configs (trails module, FX_FORMAT §4.3).

    fxlib's _RendererMixin only serves standalone emitters; embedded AraTrailConfig
    carries its own renderer block — written explicitly so the A5 star trail never
    falls back to the MISSING (pink) material (gen_player_fx precedent).
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# A1 eclipse:quest_sigil_burst — rune ring snaps open, shatters into glyph shards
# ---------------------------------------------------------------------------
# Spine 8 / 3 / ~24 (total ~32t). Chest-anchored (registrar CHEST_OFFSET); MAIN goals
# scale the whole executor 1.25x and layer quest_sigil_pillar (its own asset below).
def build_quest_sigil_burst() -> FxBuilder:
    fx = FxBuilder("quest_sigil_burst")
    box = ((-1.6, -1.4, -1.6), (1.6, 2.6, 1.6))
    # ANTICIPATION 0->8: the rune ring writes itself in around the chest (arc sweep —
    # the ALTAR pen-tip verb), motes hold still and brighten until the snap.
    (fx.particle_emitter(
            "rune_write",
            duration=8, looping=False,
            start_lifetime=random_between(10, 16), start_speed=constant(0.0),
            start_size=nf3(random_between(0.09, 0.14)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=constant(1.7))
       .with_shape(circle(radius=0.55, thickness=0.05, arc_mode="Loop", arc_speed=1.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.7, 0.6, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (0.7, 0.75), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (0.55,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.55, 1.0, SEG_BLOOM)))
    # IMPACT 8->11: the snap-open money frames — hot flash + one expanding ring quad.
    (fx.particle_emitter(
            "snap_flash",
            duration=14, looping=False, start_delay=constant(8),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(0.5), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 1.6, 1.9),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.35, 1.8, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.7), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.55,) + SAC_GOLD, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    (fx.particle_emitter(
            "snap_ring",
            duration=16, looping=False, start_delay=constant(8),
            start_lifetime=constant(7), start_speed=constant(0.0),
            start_size=nf3(0.6), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_RING_SOFT, hdr=(1.0, 0.9, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.5, 2.8, SEG_BLOOM),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (1.0, 0.0)],
                [(0.0,) + SAC_VIOLET, (0.6,) + SAC_DEEP, (1.0,) + SAC_VOID])))
    # SETTLE 8->~32: the ring shatters UPWARD into glyph shards (gold <= 35%: 6/19).
    for name, count, cols, hdr in (
            ("glyph_shards", 13,
             [(0.0,) + SAC_HOT, (0.3,) + SAC_VIOLET, (0.7,) + SAC_DEEP, (1.0,) + SAC_VOID],
             (0.9, 0.8, 1.2)),
            ("glyph_shards_gold", 6,
             [(0.0,) + SAC_GOLD, (0.55,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID],
             (1.2, 1.0, 0.6))):
        (fx.particle_emitter(
                name,
                duration=10, looping=False, start_delay=constant(8),
                start_lifetime=random_between(20, 28),
                start_speed=random_between(0.45, 0.75),
                start_size=nf3(random_between(0.07, 0.12)),
                start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
                simulation_space="World", max_particles=count + 3)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(count))])
           .with_shape(cone(angle=16.0, radius=0.28, thickness=0.4))
           .with_material(texture_material(TEX_SHARD, hdr=hdr, blend=BLEND_ADDITIVE))
           .with_cull_box(*box)
           .with_physics(collision=False, gravity=0.3)
           .with_curves(
                color_over_lifetime=gradient(
                    [(0.0, 1.0), (0.6, 0.8), (1.0, 0.0)], cols),
                rotation_over_lifetime=random_between(-140.0, 140.0),
                size_over_lifetime=sz(0.4, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# A1 eclipse:quest_sigil_pillar — MAIN-goal 2-block light pillar, ONE beat
# ---------------------------------------------------------------------------
# Feet-anchored (registrar FEET_OFFSET). startDelay 8 lands the pillar exactly on the
# burst asset's shatter impact frame; total on-screen time ~10t (one beat), per the
# A1 spec "MAIN goals add a 2-block light pillar for one beat".
def build_quest_sigil_pillar() -> FxBuilder:
    fx = FxBuilder("quest_sigil_pillar")
    (fx.beam_emitter(
            "pillar", end=(0.0, 2.1, 0.0), duration=10, looping=False, start_delay=8,
            width=curve(0.0, 0.5, [SEG_FLASH], "duration"),
            raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.95), (0.6, 0.7), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.45,) + SAC_HOT, (1.0,) + SAC_GOLD_PALE]))
       .with_material(texture_material(TEX_BEAM_CORE, hdr=(1.8, 1.7, 2.1),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box((-1.2, -0.4, -1.2), (1.2, 2.6, 1.2))
       .with_lights(sky=15, block=15))
    # Base glints: five motes breathe up out of the ground for the beat.
    (fx.particle_emitter(
            "base_glints",
            duration=6, looping=False, start_delay=constant(8),
            start_lifetime=random_between(8, 12), start_speed=random_between(0.04, 0.08),
            start_size=nf3(random_between(0.07, 0.11)),
            simulation_space="World", max_particles=7)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(circle(radius=0.4, thickness=0.3))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.0, 0.9, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box((-1.2, -0.4, -1.2), (1.2, 2.6, 1.2))
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD_PALE, (0.6,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.5, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# A2 eclipse:collection_tier_halo — glint halo rises boot->head, crown flash
# ---------------------------------------------------------------------------
# Spine 10 / 3 / ~30 (total ~42t). Feet-anchored (registrar FEET_OFFSET + tier scale).
def build_collection_tier_halo() -> FxBuilder:
    fx = FxBuilder("collection_tier_halo")
    box = ((-1.5, -0.3, -1.5), (1.5, 2.8, 1.5))
    # ANTICIPATION 0->10: a horizontal halo of item-glint motes rises and tightens
    # (eased vertical + slow orbit — §2 sacred verbs; radial pull-in = the tightening).
    (fx.particle_emitter(
            "halo_rise",
            duration=4, looping=False,
            start_lifetime=random_between(11, 13), start_speed=constant(0.02),
            start_size=nf3(random_between(0.06, 0.11)),
            simulation_space="World", max_particles=18)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
       .with_shape(circle(radius=0.72, thickness=0.1))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.9, 0.8, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(0.06, 0.22, [SEG_EASE_UP], "lifetime", "velocity"),
                           constant(0)),
                orbital=nf3(constant(0), constant(0.55), constant(0)),
                radial=constant(-0.025)),
            # INVERTED sacred run (DEEP -> HOT): this is an anticipation that builds
            # INTO the crown impact and dies on it — it never settles, so it brightens
            # instead of fading to VOID (§1.1's run governs settle fades).
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.8, 0.75), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (0.5,) + SAC_VIOLET, (1.0,) + SAC_HOT]),
            size_over_lifetime=sz(0.6, 1.0, SEG_BLOOM)))
    # IMPACT 10->13: crown flash at head height.
    (fx.particle_emitter(
            "crown_flash",
            duration=14, looping=False, start_delay=constant(10),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(0.5), simulation_space="World", max_particles=2)
       .at(0.0, 1.72, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.9, 1.7, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.35, 1.7, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.55, 0.7), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.4,) + SAC_GOLD, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    (fx.particle_emitter(
            "crown_ring",
            duration=16, looping=False, start_delay=constant(10),
            start_lifetime=constant(8), start_speed=constant(0.0),
            start_size=nf3(0.6), simulation_space="World", max_particles=2)
       .at(0.0, 1.72, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_RING_SOFT, hdr=(1.2, 1.0, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.55, 1.9, SEG_BLOOM),
            color_over_lifetime=gradient(
                [(0.0, 0.8), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD, (0.55,) + SAC_VIOLET, (1.0,) + SAC_VOID])))
    # SETTLE 12->~42: gold crown glints sink softly (7/23 gold = 30% <= 35%).
    (fx.particle_emitter(
            "crown_glints",
            duration=6, looping=False, start_delay=constant(12),
            start_lifetime=random_between(22, 30), start_speed=random_between(0.02, 0.05),
            start_size=nf3(random_between(0.05, 0.09)),
            simulation_space="World", max_particles=9)
       .at(0.0, 1.8, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=0.35, thickness=0.4))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.9, 0.8, 0.5),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.035, -0.015), constant(0)),
                orbital=nf3(constant(0), constant(0.5), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.7, 0.45), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD_PALE, (0.5,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.45, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# A2 eclipse:collection_tier_gold_rain — brief overhead gold rain (tier >= 4)
# ---------------------------------------------------------------------------
# Overhead-anchored (registrar OVERHEAD_OFFSET). All-gold by design: the shard-paying
# tiers ride the §5 C2 GOLD RUSH license (the one gold-dominant reward accent).
def build_collection_tier_gold_rain() -> FxBuilder:
    fx = FxBuilder("collection_tier_gold_rain")
    # startDelay 12 sheds the rain AFTER the halo asset's crown flash lands (t=10+3):
    # the crown overflows into rain — never rain before the crown exists (§3 spine).
    (fx.particle_emitter(
            "gold_rain",
            duration=12, looping=False, start_delay=constant(12),
            start_lifetime=random_between(16, 24), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.09)),
            simulation_space="World", max_particles=18)
       .with_emission(rate=constant(1.3))
       .with_shape(circle(radius=0.8, thickness=0.5))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 0.95, 0.55),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box((-1.6, -3.2, -1.6), (1.6, 0.6, 1.6))
       .with_physics(collision=False, gravity=0.22)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.9), (0.7, 0.6), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD, (0.5,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.55, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# A3 eclipse:skill_spend_glint — the near-invisible lens accent over the hand
# ---------------------------------------------------------------------------
# Hand-anchored (registrar HAND_OFFSET + cost scale). Deliberately small: the Quasar
# spark orbit (skill_spend_spark.json) is the composition; this is only the garnish.
# STORM support blues per §1.5 — the skill tree IS the stern constellation family.
def build_skill_spend_glint() -> FxBuilder:
    fx = FxBuilder("skill_spend_glint")
    box = ((-0.8, -0.8, -0.8), (0.8, 0.8, 0.8))
    # One soft lens glint swelling over the hand (sin(pi*t) swell, alpha <= 0.45).
    (fx.particle_emitter(
            "lens_glint",
            duration=10, looping=False,
            start_lifetime=constant(9), start_speed=constant(0.0),
            start_size=nf3(0.3), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.5, 0.6, 0.8),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.25, 1.1, SEG_SWELL),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.35, 0.45), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.45,) + STM_ARC, (1.0,) + STM_DEEP])))
    # A hint of the skill-tree constellation flickers over the forearm for 10t.
    (fx.particle_emitter(
            "constellation",
            duration=4, looping=False,
            start_lifetime=constant(10), start_speed=constant(0.005),
            start_size=nf3(random_between(0.03, 0.05)),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
       .with_shape(sphere(radius=0.18, thickness=0.2))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.4, 0.5, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            # Twinkle: alpha hops between quiet levels — a constellation, not a burst.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.5), (0.3, 0.12), (0.5, 0.55),
                 (0.7, 0.15), (0.85, 0.4), (1.0, 0.0)],
                [(0.0,) + STM_ARC, (0.6,) + STM_DEEP, (1.0,) + STM_SLATE])))
    return fx


# ---------------------------------------------------------------------------
# A4 eclipse:landmark_flare — compass-rose reveal over the charted site
# ---------------------------------------------------------------------------
# Spine 12 / 3 / ~44 (total ~60t). Position-lane at the landmark center (the seam
# hovers the anchor FLARE_HOVER over the surface); range 128 — a shared reveal.
def build_landmark_flare() -> FxBuilder:
    fx = FxBuilder("landmark_flare")
    box = ((-3.4, -2.5, -3.4), (3.4, 2.5, 3.4))
    # ANTICIPATION 0->12: the compass ring writes itself in (arc sweep, near-still
    # parchment-light motes lying flat like map ink catching light).
    (fx.particle_emitter(
            "rose_write",
            duration=12, looping=False,
            start_lifetime=random_between(12, 18), start_speed=constant(0.0),
            start_size=nf3(random_between(0.12, 0.18)),
            simulation_space="World", max_particles=20)
       .with_emission(rate=constant(1.4))
       .with_shape(circle(radius=2.1, thickness=0.04, arc_mode="Loop", arc_speed=1.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.9, 0.8, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_cull_box(*box)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.85), (0.7, 0.7), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.5,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.6, 1.0, SEG_BLOOM)))
    # IMPACT 12->15: the rose unfurls — four cardinal needles shoot out and stall
    # (impact-fast for 2-4t only, then the eased stall — §2 sacred exception),
    # under a single hot flash frame.
    (fx.particle_emitter(
            "rose_needles",
            duration=14, looping=False, start_delay=constant(12),
            start_lifetime=random_between(12, 14),
            start_speed=constant(0.55),
            start_size=nf3(0.1),
            simulation_space="World", max_particles=6)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(circle(radius=0.35, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 1.0, 0.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=3.4,
                      velocity_scale=0.5)
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(0),
                speed_modifier=curve(0.05, 1.0, [SEG_SHRINK], "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.75), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD, (0.55,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID])))
    (fx.particle_emitter(
            "reveal_flash",
            duration=18, looping=False, start_delay=constant(12),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(0.7), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.9, 1.7, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.4, 2.0, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.55, 0.7), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.4,) + SAC_GOLD, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    # SETTLE 15->~60: the rose dissolves into drifting map-ink motes that sink toward
    # the site (alpha-blend matte ink, DEEP -> VOID, gentle noise wander).
    (fx.particle_emitter(
            "ink_motes",
            duration=6, looping=False, start_delay=constant(15),
            start_lifetime=random_between(30, 40), start_speed=constant(0.01),
            start_size=nf3(random_between(0.14, 0.22)),
            simulation_space="World", max_particles=18)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
       .with_shape(circle(radius=2.3, thickness=0.8))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0),
                           curve(-0.055, -0.015, [SEG_EASE_UP], "lifetime", "velocity"),
                           constant(0))),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.01), constant(0.03)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (0.75, 0.35), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.7, 1.0, SEG_BLOOM)))
    return fx


# ---------------------------------------------------------------------------
# A4 eclipse:landmark_echo — the discoverer's small personal glint (Photon-only)
# ---------------------------------------------------------------------------
# Chest-anchored (registrar CHEST_OFFSET). Photon-only garnish BY DESIGN: reducedFx
# and photon-less clients get no echo per the A4 reduced spec — the shared flare
# already carries the moment. Kept tiny: one blink + six orbiting glints.
def build_landmark_echo() -> FxBuilder:
    fx = FxBuilder("landmark_echo")
    box = ((-0.9, -0.9, -0.9), (0.9, 1.3, 0.9))
    (fx.particle_emitter(
            "echo_blink",
            duration=4, looping=False,
            start_lifetime=constant(3), start_speed=constant(0.0),
            start_size=nf3(0.3), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.1, 1.0, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.4, 1.4, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD_PALE, (1.0,) + SAC_VIOLET])))
    (fx.particle_emitter(
            "echo_glints",
            duration=4, looping=False,
            start_lifetime=random_between(14, 20), start_speed=random_between(0.02, 0.04),
            start_size=nf3(random_between(0.04, 0.07)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(sphere(radius=0.3, thickness=0.2))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.9, 0.8, 0.6),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.04), constant(0)),
                orbital=nf3(constant(0), constant(0.7), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.75, 0.4), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD_PALE, (0.55,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.5, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# A5 eclipse:wizard_catalyst_handover — shard indraw -> fuse flash -> star-trail drop
# ---------------------------------------------------------------------------
# Spine 12 / 3 / ~30 (total ~48t). Staff-tip-anchored on Orin (registrar STAFF_OFFSET),
# delay-choreographed to the `trade` anim; the vanilla END_ROD puff above stays as the
# photon-less floor. The Quasar indraw half is quality-gated by the registrar leg.
def build_wizard_catalyst_handover() -> FxBuilder:
    fx = FxBuilder("wizard_catalyst_handover")
    box = ((-2.0, -1.8, -2.0), (2.0, 1.4, 2.0))
    # ANTICIPATION 0->12: amethyst + umbral shards spiral in from the player's side
    # (§1.2-style interleave: bright violet and matte dark alternate, never blend).
    (fx.particle_emitter(
            "indraw_amethyst",
            duration=6, looping=False,
            start_lifetime=random_between(10, 13),
            start_speed=random_between(-0.3, -0.22),
            start_size=nf3(random_between(0.07, 0.11)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(9)),
                                                  burst(time=4, count=constant(5))])
       .with_shape(sphere(radius=1.5, thickness=0.0))
       .with_material(texture_material(TEX_SHARD, hdr=(0.8, 0.7, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            # INVERTED run (DEEP -> HOT): anticipation building into the fuse impact
            # (same license as the A2 halo rise); sizes shrink approaching the staff
            # tip — the C6 suction verb — on a smooth ease.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (1.0, 0.85)],
                [(0.0,) + SAC_DEEP, (0.55,) + SAC_VIOLET, (1.0,) + SAC_HOT]),
            rotation_over_lifetime=random_between(-120.0, 120.0),
            size_over_lifetime=sz(1.0, 0.55, SEG_EASE_UP)))
    (fx.particle_emitter(
            "indraw_umbral",
            duration=6, looping=False, start_delay=constant(2),
            start_lifetime=random_between(9, 12),
            start_speed=random_between(-0.26, -0.18),
            start_size=nf3(random_between(0.08, 0.13)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=9)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=1.3, thickness=0.0))
       .with_material(texture_material(TEX_SHARD, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box(*box)
       .with_curves(
            # The matte dark half of the interleave: rises to DEEP then sinks back
            # to the VOID token as it reaches the fuse (never dark -> light).
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.6), (0.75, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_DEEP, (0.6,) + SAC_DEEP, (1.0,) + SAC_VOID]),
            rotation_over_lifetime=random_between(-90.0, 90.0)))
    # IMPACT 12->15: the fuse — one white-violet flash frame at the staff tip.
    (fx.particle_emitter(
            "fuse_flash",
            duration=16, looping=False, start_delay=constant(12),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(0.4), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.2, 2.0, 2.6),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            size_over_lifetime=sz(0.3, 2.0, SEG_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.8), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.35,) + SAC_HOT, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    # SETTLE 15->~46: the catalyst drops out riding a tiny star trail (physics fall,
    # gentle bounce), plus a soft sparkle wake around the staff tip.
    (fx.particle_emitter(
            "catalyst_drop",
            duration=6, looping=False, start_delay=constant(15),
            start_lifetime=constant(26), start_speed=constant(0.05),
            start_size=nf3(0.09), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(sphere(radius=0.02, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.4, 1.8),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_physics(collision=True, removed_when_collided=False, friction=0.9,
                     collided_friction=0.6, gravity=0.3, bounce_chance=0.5,
                     bounce_rate=0.35, bounce_spread=0.05)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.75, 0.85), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.6,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.7, 1.0, SEG_SWELL))
       .with_module("trails", {
            "ratio": F(1.0), "lifetime": constant(1.0),
            "dieWithParticles": B(0), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "colorOverLifetime": gradient([(0.0, 0.9), (1.0, 0.0)],
                                          [(0.0, 1.0, 1.0, 1.0)]),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "thickness": F(0.04), "time": F(0.45),
                "alignment": "View", "space": "World",
                "colorOverLength": gradient(
                    [(0.0, 0.9), (1.0, 0.0)],
                    [(0.0,) + SAC_HOT, (0.5,) + SAC_VIOLET, (1.0,) + SAC_DEEP]),
                "physicsSetting": {
                    "warmup": F(0.0), "gravity": L([F(0.0), F(0.0), F(0.0)]),
                    "inertia": F(0.2), "velocitySmoothing": F(0.75),
                    "damping": F(0.8)},
                "renderer": ribbon_renderer(
                    texture_material(TEX_CIRCLE, hdr=(1.2, 1.1, 1.5),
                                     blend=BLEND_ADDITIVE),
                    cull_box=box)}}))
    (fx.particle_emitter(
            "fuse_sparkles",
            duration=6, looping=False, start_delay=constant(14),
            start_lifetime=random_between(20, 30), start_speed=random_between(0.03, 0.07),
            start_size=nf3(random_between(0.04, 0.07)),
            simulation_space="World", max_particles=9)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=0.25, thickness=0.3))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.9, 0.8, 1.2),
                                       blend=BLEND_ADDITIVE))
       .with_cull_box(*box)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.015, 0.035), constant(0)),
                orbital=nf3(constant(0), constant(0.5), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.8), (0.7, 0.4), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.5,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.5, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# main — write + validate all eight
# ---------------------------------------------------------------------------
BUILDERS = {
    "quest_sigil_burst.fx": build_quest_sigil_burst,
    "quest_sigil_pillar.fx": build_quest_sigil_pillar,
    "collection_tier_halo.fx": build_collection_tier_halo,
    "collection_tier_gold_rain.fx": build_collection_tier_gold_rain,
    "skill_spend_glint.fx": build_skill_spend_glint,
    "landmark_flare.fx": build_landmark_flare,
    "landmark_echo.fx": build_landmark_echo,
    "wizard_catalyst_handover.fx": build_wizard_catalyst_handover,
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
