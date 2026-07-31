#!/usr/bin/env python3
"""sig_fx — V7-SIGCOMP signature-composition assets (FX-STYLE-GUIDE.md §5), via fxlib.

Photon `.fx` (into `src/main/resources/assets/eclipse/fx/sig/`, id = `eclipse:sig/<name>`;
each gets an editor-openable `.fxproj` sibling — §4 naming law + binary-diff law):

    eclipse:sig/crown_verdict       C11 boss-defeat coda, full form (L1 world indraw at
                                    t=0→12, L2 verdict white-out flash at t=12, L3 gold
                                    ash rain 15→60). The shockwave/grade/halo/sound
                                    beats live in java `veilfx/SignatureCompositions`.
    eclipse:sig/crown_verdict_coda  C11 coda-only form for hosts that ship their own
                                    indraw (the Fog Tyrant's 24t implosion): flash at
                                    t=24, ash 27→72 — re-timed onto the host's suck.
    eclipse:sig/gold_rush           C2 reward burst, impact-anchored (java delays the
                                    spawn 8t behind the Quasar glint gather): flash
                                    frame 0→2, physics star shards + glint-rain trails
                                    0→28. Scaled per context via SpawnOptions.
    eclipse:sig/sanctum_bloom       C1 consecration Photon half (L3 light pillar +
                                    L4 bloom burst), startDelay 10 baked in so the
                                    impact lands with the glyph write-in completion.
    eclipse:sig/deep_rumble_bed     C10 dread-bed loop (WINDOWED-only): sparse ceiling
                                    dust + pebble hops. Deliberately sub-visual — the
                                    rumble SOUND is the composition (DeepRumbleFx).

Quasar emitters (into `src/main/resources/assets/eclipse/quasar/emitters/`):

    sig_crown_verdict_burst   C11 row fallback / demoted sketch — gold exhale burst
    sig_crown_verdict_halo    C11 L4 crown halo — one soft expanding gold ring
    sig_gold_rush_glints      C2 L1 glint gather — 8 gold sparks arcing inward
    sig_sanctum_glyph         C1 L1 ground glyph — violet ring patch, vortex write-in
    sig_sanctum_orbit         C1 L5 settle orbit motes — rise + orbit, fade to VOID
    sig_deep_rumble_motes     C10 tier-1 loop stand-in — grey dust trickle (loop:true)

These files are fxlib/JSON-generated (this script IS the committed source). Regenerate +
validate with:

    python3 tools/photon/sig_fx.py
    python3 tools/photon/fxlib.py validate --lint src/main/resources/assets/eclipse/fx/sig/*.fx

Style-guide conformance (FX-STYLE-GUIDE.md):
  - Palette §1.1: SACRED tokens; C11/C2 are the licensed gold leads; every gradient ends
    on SAC_VOID #2E2347 (never transparent black). C10 is palette-neutral ERA_SHADOW dust.
  - Motion §2: sacred verbs — indraw converge, slow orbits/verticals; only the 2-4t
    impact frames are fast. C10 uses era/neutral gravity verbs (dust falls, pebbles hop).
  - Timing §3: C11 spine 12/3/40+ (coda form 24/3/40+), C2 8/2/28 (the 8t anticipation
    is the java-side Quasar gather), C1 10/3/36 (pillar startDelay 10 = the write-in).
  - Budgets: one-shots ≤ ~90 particles; loops are sparse + cull-boxed (LINT-CULL-LOOP);
    every maxParticles explicit; HDR ≤ 4.0; no linear shipped curves (house segments).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, F, FX_ASSETS_DIR, FxBuilder, REPO_ROOT, TrailEmitter,
    BLEND_ADDITIVE, BLEND_ALPHA, SEG_DECAY_TAIL, SEG_EASE_OUT_CREST, SEG_SMOOTH_UP,
    box, burst, circle, constant, curve, cylinder, gradient, nf3, random_between,
    random_gradient, sphere, texture_material, validate_file,
)

SIG_DIR = FX_ASSETS_DIR / "sig"
QUASAR_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/quasar/emitters"

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_SHARD = "eclipse:textures/particle/glitch_shard.png"
TEX_WISP = "eclipse:textures/particle/wisp_white.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_BEAM_CORE = "eclipse:textures/particle/beam_core.png"
TEX_SQUARE = "eclipse:textures/particle/square_4x4.png"


# ---------------------------------------------------------------------------
# FX-STYLE-GUIDE §1.1 tokens (rgb 0..1 for photon gradients, #hex for quasar)
# ---------------------------------------------------------------------------
def rgb(hexcode: int):
    return ((hexcode >> 16 & 0xFF) / 255.0, (hexcode >> 8 & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


SAC_HOT = rgb(0xF6EFFF)
SAC_VIOLET = rgb(0xB98CFF)
SAC_DEEP = rgb(0x7B4FD0)
SAC_GOLD = rgb(0xFFD166)
SAC_GOLD_PALE = rgb(0xFFE9A8)
SAC_VOID = rgb(0x2E2347)
GLI_WHITE = rgb(0xFFFFFF)
ERA_SHADOW = rgb(0x3A3A55)

# Impact flash: pop to full in ~8% of life, decay to 0 (money frames, §3 IMPACT).
SEG_FLASH = (0.0, 0.2, 0.08, 1.0, 0.5, 0.6, 1.0, 0.0)
# Ease-out shrink (settling shards / dying motes).
SEG_SHRINK = (0.0, 1.0, 0.4, 0.9, 0.8, 0.3, 1.0, 0.0)
# Pillar width envelope: snap to the 0.9 peak inside 3t, relax to the 0.35 tail
# (0.15 + 0.75*y: y=1 -> 0.9 peak, y=0.27 -> ~0.35 hold).
SEG_PILLAR = (0.0, 0.0, 0.05, 1.05, 0.4, 0.5, 1.0, 0.27)
# WAVE-13 impact envelope: ~2t attack, long afterglow tail (replaces SEG_FLASH's 8t).
SEG_SNAP_FLASH = (0.0, 0.22, 0.045, 1.0, 0.4, 0.52, 1.0, 0.0)

# ---------------------------------------------------------------------------
# WAVE-13 C4 levers (local — `fxlib.py` is A0 ground this wave).
# ---------------------------------------------------------------------------
#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45"). NOTE this file's
#: own header still documents the OLD per-asset budget "HDR <= 4.0" — wave 13 lowers
#: the ceiling globally because the stacking law changed, not because these were wrong.
HDR_CEILING = 1.45


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


#: Birth tints (V2.1 stacking law): below each ramp's own fade target.
SAC_BIRTH = (0.13, 0.10, 0.21)
GOLD_BIRTH = (0.20, 0.15, 0.07)
DUST_BIRTH = (0.13, 0.13, 0.19)


def sz(lo, hi, seg, x_axis="lifetime"):
    """NF3 size_over_lifetime from one shared bezier segment."""
    return nf3(*[curve(lo, hi, [seg], x_axis, "size") for _ in range(3)])


def embedded_trail_config(material_entry, **kwargs):
    """Full TrailConfig compound for the `trails` module's embedded `config`
    (fx_altar.py precedent, FX_FORMAT.md §4.2)."""
    t = TrailEmitter("_embedded", **kwargs)
    t.with_material(material_entry)
    return t.build()["data"]["config"]


# ---------------------------------------------------------------------------
# C11 eclipse:sig/crown_verdict(_coda) — the boss defeat coda (S-MAX)
# ---------------------------------------------------------------------------
# Shared layer builders; `impact` = 12 (full form) or 24 (coda riding the host's
# tyrant_death_implosion 24t suck — the L1 indraw is then the HOST's, not ours).
def _crown_flash(fx: FxBuilder, impact: int):
    """L2 verdict flash: one 3t GLI_WHITE -> SAC_GOLD white-out quad (the java half
    adds the shipped shockwave at strength 1.0 — the v3 double-pulse earner)."""
    (fx.particle_emitter(
            "verdict_flash",
            duration=impact + 10, looping=False, start_delay=constant(impact),
            start_lifetime=constant(4), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(2.6, 2.3, 1.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.5, 5.2, SEG_SNAP_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.45, 0.85), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.4,) + SAC_GOLD, (1.0,) + SAC_GOLD_PALE]))
       .with_lights(sky=15, block=15))


def _crown_ash(fx: FxBuilder, impact: int):
    """L3 gold ash rain: 40 slow-falling flakes — the world is gilded for a breath
    (40t+ tail). Physics drift so flakes rest on the arena floor."""
    (fx.particle_emitter(
            "gold_ash",
            duration=impact + 20, looping=False, start_delay=constant(impact + 3),
            start_lifetime=random_between(34, 48),
            start_speed=random_between(0.2, 0.8),
            start_size=nf3(random_between(0.06, 0.12)),
            simulation_space="World", max_particles=44)
       .at(0.0, 3.6, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(24)),
                              burst(time=6, count=constant(16))])
       .with_shape(cylinder(radius=3.2, thickness=0.8))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.1, 0.95, 0.55),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                     collided_friction=0.7, gravity=0.055, bounce_chance=0.15,
                     bounce_rate=0.2, bounce_spread=0.05)
       # UNITS: the fall is gravity-driven (0.055), so `startSpeed` is only the initial
       # scatter — rescaled to b/s for consistency, not to change the rain's read.
       # W13: 40 additive flakes inside one 3.2-block cylinder used to be born on the
       # SAME pale gold; the dark birth + sibling ramp break the sheet into flakes.
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.85), (0.65, 0.5), (1.0, 0.0)],
                [(0.0,) + GOLD_BIRTH, (0.18,) + SAC_GOLD_PALE, (0.5,) + SAC_GOLD,
                 (1.0,) + SAC_VOID],
                [(0.0,) + GOLD_BIRTH, (0.22,) + SAC_GOLD, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.45, 1.0, SEG_SHRINK),
            # Sideways drift breath so the rain shimmers instead of plumb-falling.
            noise=dict(frequency=0.6, quality="Noise2D",
                       position=nf3(constant(0.03), constant(0.0), constant(0.03)),
                       rotation=constant(0), size=constant(0))))


def build_crown_verdict() -> FxBuilder:
    """Full form (impact t=12). L1 world indraw: motes off a 6-block shell converge
    at ~0.4 blk/t into the corpse, SAC_DEEP brightening to SAC_HOT as they arrive."""
    fx = FxBuilder("crown_verdict")
    (fx.particle_emitter(
            "world_indraw",
            duration=14, looping=False,
            start_lifetime=random_between(10, 13),
            start_speed=random_between(-11.0, -9.0),
            start_size=nf3(random_between(0.1, 0.18)),
            simulation_space="World", max_particles=28)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(14)),
                              burst(time=4, count=constant(10))])
       .with_shape(sphere(radius=6.0, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(0.9, 0.75, 1.15),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=3.4,
                      velocity_scale=0.3, vertex_sorting="NONE")
       # UNITS: this docstring's own "~0.4 blk/t" IS 8 b/s — written as 0.4 b/s the
       # motes crossed 23 cm of their 6-block shell, so the verdict flash fired over
       # an untouched ring. 6 / (0.05 x 11.5) ~= 10 b/s puts them on the corpse.
       .with_curves(
            # Converge-brighten: DEEP tails -> VIOLET -> HOT arrival (§2 indraw verb).
            color_over_lifetime=varied(
                [(0.0, 0.15), (0.75, 0.95), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.3,) + SAC_DEEP, (0.7,) + SAC_VIOLET,
                 (1.0,) + SAC_HOT],
                [(0.0,) + SAC_BIRTH, (0.45,) + SAC_VIOLET, (1.0,) + SAC_HOT]),
            size_over_lifetime=sz(0.5, 1.05, SEG_SMOOTH_UP)))
    _crown_flash(fx, 12)
    _crown_ash(fx, 12)
    return fx


def build_crown_verdict_coda() -> FxBuilder:
    """Coda-only form (impact t=24): the host seam already plays its own indraw
    (Tyrant implosion) — the verdict adds only the flash + gilding, re-timed."""
    fx = FxBuilder("crown_verdict_coda")
    _crown_flash(fx, 24)
    _crown_ash(fx, 24)
    return fx


# ---------------------------------------------------------------------------
# C2 eclipse:sig/gold_rush — the reusable reward burst (A-class)
# ---------------------------------------------------------------------------
# Impact-anchored: java plays the sig_gold_rush_glints gather first and spawns this
# file 8t later, so t=0 here IS the C2 impact frame. Whole file scales per context
# (podium 1.15 / collection 0.55+ / altar milestone 0.7+) via SpawnOptions.
def build_gold_rush() -> FxBuilder:
    fx = FxBuilder("gold_rush")
    # L2 flash frame: 1 quad, 2t money frame, GLI_WHITE -> SAC_GOLD, hdr 2.0, size 1.4.
    (fx.particle_emitter(
            "flash_frame",
            duration=8, looping=False,
            start_lifetime=constant(3), start_speed=constant(0.0),
            start_size=nf3(1.4), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(2.0, 1.8, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.45, 1.0, SEG_SNAP_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.8), (1.0, 0.0)],
                [(0.0,) + GLI_WHITE, (0.55,) + SAC_GOLD, (1.0,) + SAC_GOLD_PALE]))
       .with_lights(sky=15, block=15))
    # L3 star shards: burst 30 with real physics (template_burst numbers) + L4 the
    # glint rain — `trails` ratio 0.4, short inherit-color ribbons.
    ribbon_mat = texture_material(TEX_CIRCLE, hdr=hdr(1.3, 1.1, 0.6),
                                  blend=BLEND_ADDITIVE)
    # UNITS: 0.35-0.8 b/s threw the reward burst 31-112 cm — from any distance that
    # is a stationary gold dot. 2.5-5.0 b/s gives 2.2-7.0 blocks of throw before
    # gravity 0.35 arcs the shards down; a full x20 would fling them out of the arena.
    (fx.particle_emitter(
            "star_shards",
            duration=30, looping=False,
            start_lifetime=random_between(18, 28),
            start_speed=random_between(2.5, 5.0),
            start_size=nf3(random_between(0.09, 0.16)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=34)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30))])
       .with_shape(sphere(radius=0.3, thickness=0.4))
       .with_material(texture_material(TEX_SHARD, discard=0.15,
                                       hdr=hdr(1.5, 1.25, 0.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_physics(collision=True, removed_when_collided=False, friction=0.98,
                     collided_friction=0.6, gravity=0.35, bounce_chance=0.6,
                     bounce_rate=0.4, bounce_spread=0.1)
       .with_module("trails", {
            "ratio": F(0.4),
            "lifetime": constant(0.4),
            "inheritParticleColor": B(1),
            "trailType": "TRAIL",
            "config": embedded_trail_config(
                ribbon_mat, time=6, min_vertex_distance=0.05,
                width=curve(0.0, 0.07, [SEG_DECAY_TAIL]),
                color_nf=gradient(
                    [(0.0, 0.85), (1.0, 0.0)],
                    [(0.0,) + SAC_GOLD, (1.0,) + SAC_VOID]))})
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.55, 0.8), (1.0, 0.0)],
                [(0.0,) + SAC_GOLD, (0.5,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_GOLD_PALE, (0.45,) + SAC_GOLD, (1.0,) + SAC_VOID]),
            rotation_over_lifetime=dict(roll=random_between(-10.0, 10.0)),
            size_over_lifetime=sz(0.5, 1.0, SEG_SHRINK))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# C1 eclipse:sig/sanctum_bloom — the consecration Photon half (L3 + L4)
# ---------------------------------------------------------------------------
# Spawned by SignatureCompositions.sanctumBloomLayer at glyph write-in start; the
# baked startDelay 10 lands the pillar/burst exactly on the ceremony impact. The
# glyph (L1), ceremony indraw (L2), orbit settle (L5) and chime (L7) live outside.
def build_sanctum_bloom() -> FxBuilder:
    fx = FxBuilder("sanctum_bloom")
    # L3 light pillar, SAC_HOT core: width 0.15 -> 0.9 flash peak -> 0.35 hold.
    fx.beam_emitter(
        "pillar_core", end=(0.0, 14.0, 0.0), duration=36, looping=False,
        start_delay=10, width=curve(0.15, 0.9, [SEG_PILLAR], "duration"),
        raycast="NONE",
        color_nf=gradient(
            [(0.0, 0.95), (0.25, 0.8), (1.0, 0.0)],
            [(0.0,) + SAC_HOT, (0.55,) + SAC_VIOLET, (1.0,) + SAC_DEEP])
    ).with_material(texture_material(TEX_BEAM_CORE, hdr=hdr(1.6, 1.5, 1.8),
                                     blend=BLEND_ADDITIVE))
    # L3 gold sheath: same envelope, 1.8x wider, softer gold voice.
    fx.beam_emitter(
        "pillar_sheath", end=(0.0, 14.0, 0.0), duration=36, looping=False,
        start_delay=10, width=curve(0.27, 1.62, [SEG_PILLAR], "duration"),
        raycast="NONE",
        color_nf=gradient(
            [(0.0, 0.5), (0.3, 0.35), (1.0, 0.0)],
            [(0.0,) + SAC_GOLD, (0.6,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID])
    ).with_material(texture_material(TEX_BEAM_CORE, hdr=hdr(1.4, 1.2, 0.7),
                                     blend=BLEND_ADDITIVE))
    # L4 bloom burst: 26 motes off a tight shell at the impact frame, HOT -> GOLD_PALE.
    (fx.particle_emitter(
            "bloom_burst",
            duration=24, looping=False, start_delay=constant(10),
            start_lifetime=random_between(10, 14),
            start_speed=random_between(6.0, 10.0),
            start_size=nf3(random_between(0.1, 0.18)),
            simulation_space="World", max_particles=30)
       .at(0.0, 1.0, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(26))])
       .with_shape(sphere(radius=0.4, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_WISP, hdr=hdr(1.5, 1.35, 1.1),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       # UNITS: the consecration bloom expanded 15-35 cm around a 14-block pillar.
       # 6-10 b/s x the ~0.55 average of its own decay curve = 1.7-3.9 blocks, which
       # is a bloom you can read from the sanctum rim.
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 1.0), (0.5, 0.75), (1.0, 0.0)],
                [(0.0,) + SAC_HOT, (0.55,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_GOLD_PALE, (0.5,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.0, 1.1, SEG_EASE_OUT_CREST),
            # The burst decelerates into the settle (sacred: only impacts are fast).
            velocity_over_lifetime=dict(
                linear=nf3(0), speed_modifier=curve(0.1, 1.0, [SEG_SHRINK],
                                                    "lifetime", "value")))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# C10 eclipse:sig/deep_rumble_bed — the dread-bed loop (WINDOWED-only)
# ---------------------------------------------------------------------------
# Anchored on the player by DeepRumbleFx (re-anchored on travel). Deliberately fails
# the "did you see it?" test: greys, no HDR, tiny counts. The rumble sound and the
# 1% frame breathing live in java; this file is only the dust-and-pebbles garnish.
def build_deep_rumble_bed() -> FxBuilder:
    fx = FxBuilder("deep_rumble_bed")
    # L1 ceiling dust: sparse trickle sifting down from overhead, dies on the floor.
    (fx.particle_emitter(
            "ceiling_dust",
            duration=60, looping=True,
            start_lifetime=random_between(36, 56),
            start_speed=random_between(0.0, 0.01),
            start_size=nf3(random_between(0.05, 0.1)),
            simulation_space="World", max_particles=48)
       .at(0.0, 3.4, 0.0)
       .with_emission(rate=constant(0.22))
       .with_shape(box(emit_from="Volume"), scale=(9.0, 0.4, 9.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-6.0, -5.0, -6.0), (6.0, 1.5, 6.0))
       .with_physics(collision=True, removed_when_collided=True, friction=0.995,
                     collided_friction=0.8, gravity=0.055, bounce_chance=0.0,
                     bounce_rate=0.0)
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.32), (0.7, 0.24), (1.0, 0.0)],
                [(0.0,) + DUST_BIRTH, (0.25, 0.42, 0.41, 0.5), (0.7,) + ERA_SHADOW,
                 (1.0,) + SAC_VOID],
                [(0.0,) + DUST_BIRTH, (0.3,) + ERA_SHADOW, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.6, 1.0, SEG_SMOOTH_UP)))
    # L2 pebble hop: every ~30t a 3-pebble micro-burst hops off the shivering floor.
    (fx.particle_emitter(
            "pebble_hops",
            duration=30, looping=True,
            start_lifetime=random_between(10, 16),
            start_speed=random_between(1.0, 1.8),
            start_size=nf3(random_between(0.035, 0.06)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=12)
       .at(0.0, 0.15, 0.0)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=8, count=constant(3), probability=0.85)])
       .with_shape(box(emit_from="Volume"), scale=(6.0, 0.1, 6.0))
       .with_material(texture_material(TEX_SQUARE, discard=0.2, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-4.0, -1.5, -4.0), (4.0, 1.5, 4.0))
       .with_physics(collision=True, removed_when_collided=False, friction=0.98,
                     collided_friction=0.55, gravity=0.5, bounce_chance=1.0,
                     bounce_rate=0.35, bounce_spread=0.1)
       # UNITS: the pebbles "hop off the shivering floor" — at 0.13 b/s they twitched
       # 13 cm and never left the ground plane. 1.0-1.8 b/s throws them 0.5-1.4
       # blocks, which gravity 0.5 turns back into a hop inside the 1.5-block box.
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 0.55), (0.8, 0.4), (1.0, 0.0)],
                [(0.0,) + ERA_SHADOW, (1.0,) + SAC_VOID],
                [(0.0,) + DUST_BIRTH, (0.5,) + ERA_SHADOW, (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.8, 1.0, SEG_DECAY_TAIL)))
    return fx


# ---------------------------------------------------------------------------
# Quasar emitters (schema: the shipped quasar/emitters/*.json precedents)
# ---------------------------------------------------------------------------
def _color_module(rgb_points, alpha_points):
    return {"module": "veil:color",
            "gradient": {
                "rgb_points": [{"percent": p, "color": c} for p, c in rgb_points],
                "alpha_points": [{"percent": p, "alpha": a} for p, a in alpha_points]},
            "interpolant": "q.agePercent"}


def _emitter(max_lifetime, loop, rate, count, shape, dimensions, from_surface,
             speed, size, size_var, lifetime, lifetime_var, direction=(0.0, 1.0, 0.0),
             random_direction=True, additive=True, sprite="eclipse:textures/particle/purple_wisp.png",
             face_velocity=False, stretch=0.0, collide=False, modules=()):
    return {
        "max_lifetime": max_lifetime,
        "loop": loop,
        "rate": rate,
        "count": count,
        "emitter_settings": {
            "shape": {
                "shape": shape,
                "dimensions": list(dimensions),
                "rotation": [0.0, 0.0, 0.0],
                "from_surface": from_surface,
            },
            "particle_settings": {
                "particle_speed": speed,
                "random_speed": True,
                "base_particle_size": size,
                "particle_size_variation": size_var,
                "particle_lifetime": lifetime,
                "particle_lifetime_variation": lifetime_var,
                "initial_direction": list(direction),
                "random_initial_direction": random_direction,
                "random_initial_rotation": True,
                "random_size": True,
                "random_lifetime": True,
            },
            "force_spawn": False,
        },
        "particle_data": {
            "render_style": "veil:billboard",
            "additive": additive,
            "should_collide": collide,
            "face_velocity": face_velocity,
            "velocity_stretch_factor": stretch,
            "sprite_data": {
                "sprite": sprite,
                "frame_count": 1,
                "frame_time": 1,
                "stretch_to_lifetime": False,
            },
            "modules": list(modules),
        },
    }


# C11 row fallback / §6.1 demoted sketch: one gold exhale burst — motes leap and
# sink back gilded (heart_burst verbs, altar_orbit_burst point_force read).
SIG_CROWN_VERDICT_BURST = _emitter(
    max_lifetime=4, loop=False, rate=2, count=10,
    shape="veil:sphere", dimensions=[0.6, 0.6, 0.6], from_surface=True,
    speed=0.4, size=0.14, size_var=0.05, lifetime=22, lifetime_var=6,
    face_velocity=True, stretch=0.5,
    modules=[
        {"module": "veil:gravity", "strength": 0.22},
        {"module": "veil:drag", "strength": 0.08},
        _color_module(
            [(0.0, "#FFFFFF"), (0.25, "#FFD166"), (0.7, "#FFE9A8"), (1.0, "#2E2347")],
            [(0.0, 0.95), (0.6, 0.6), (1.0, 0.0)]),
    ])

# C11 L4 crown halo: ONE soft gold ring overhead expanding via the size expression.
SIG_CROWN_VERDICT_HALO = _emitter(
    max_lifetime=2, loop=False, rate=1, count=1,
    shape="veil:sphere", dimensions=[0.05, 0.05, 0.05], from_surface=False,
    speed=0.0, size=1.4, size_var=0.0, lifetime=30, lifetime_var=0,
    random_direction=False, sprite="eclipse:textures/particle/ring_soft.png",
    modules=[
        {"module": "veil:size", "size": "1.4 + q.agePercent * 4.6"},
        _color_module(
            [(0.0, "#FFE9A8"), (0.4, "#FFD166"), (1.0, "#2E2347")],
            [(0.0, 0.85), (0.55, 0.45), (1.0, 0.0)]),
    ])

# C2 L1 glint gather: 8 gold sparks arcing inward (altar_indraw vortex+attractor
# verbs = the golden-angle spiral read) over the 8t anticipation.
SIG_GOLD_RUSH_GLINTS = _emitter(
    max_lifetime=8, loop=False, rate=4, count=2,
    shape="veil:sphere", dimensions=[1.7, 1.2, 1.7], from_surface=True,
    speed=0.08, size=0.11, size_var=0.04, lifetime=10, lifetime_var=3,
    face_velocity=True, stretch=0.6,
    modules=[
        {"module": "veil:vortex", "vortex_axis": [0.0, 1.0, 0.0],
         "vortex_center": [0.0, 0.0, 0.0], "local_position": True,
         "range": 6.0, "strength": 1.3},
        {"module": "veil:point_attractor", "position": [0.0, 0.0, 0.0],
         "localPosition": True, "range": 6.0, "strength": 2.6,
         "strengthByDistance": False, "invertDistanceModifier": False},
        {"module": "veil:drag", "strength": 0.1},
        _color_module(
            [(0.0, "#FFE9A8"), (0.5, "#FFD166"), (1.0, "#2E2347")],
            [(0.0, 0.0), (0.2, 0.9), (0.8, 0.6), (1.0, 0.0)]),
    ])

# C1 L1 ground glyph: violet ring patch, vortex-swept write-in (glyph_greet clone,
# one-shot); completion lands on the ceremony impact 10t later.
SIG_SANCTUM_GLYPH = _emitter(
    max_lifetime=10, loop=False, rate=2, count=3,
    shape="veil:torus", dimensions=[0.85, 0.06, 0.85], from_surface=True,
    speed=0.015, size=0.16, size_var=0.05, lifetime=26, lifetime_var=6,
    random_direction=False,
    modules=[
        {"module": "veil:vortex", "vortex_axis": [0.0, 1.0, 0.0],
         "vortex_center": [0.0, 0.0, 0.0], "local_position": True,
         "range": 2.5, "strength": 1.6},
        {"module": "veil:drag", "strength": 0.25},
        _color_module(
            [(0.0, "#B98CFF"), (0.6, "#7B4FD0"), (1.0, "#2E2347")],
            [(0.0, 0.0), (0.3, 0.7), (0.75, 0.55), (1.0, 0.0)]),
    ])

# C1 L5 settle orbit: cylinder-shell motes, orbit 0.7 + rise 0.04, fade to VOID.
SIG_SANCTUM_ORBIT = _emitter(
    max_lifetime=6, loop=False, rate=2, count=4,
    shape="veil:cylinder", dimensions=[1.2, 0.5, 1.2], from_surface=True,
    speed=0.04, size=0.12, size_var=0.04, lifetime=30, lifetime_var=6,
    random_direction=False,
    modules=[
        {"module": "veil:vortex", "vortex_axis": [0.0, 1.0, 0.0],
         "vortex_center": [0.0, 0.0, 0.0], "local_position": True,
         "range": 3.0, "strength": 0.7},
        {"module": "veil:drag", "strength": 0.12},
        _color_module(
            [(0.0, "#F6EFFF"), (0.35, "#B98CFF"), (1.0, "#2E2347")],
            [(0.0, 0.0), (0.2, 0.75), (0.7, 0.45), (1.0, 0.0)]),
    ])

# C10 tier-1 loop stand-in: grey dust trickle (loop:true — LoopState-managed via
# PhotonFxRegistry.ensureLoop; AMBIENT channel halves its rate under reducedFx).
SIG_DEEP_RUMBLE_MOTES = _emitter(
    max_lifetime=40, loop=True, rate=4, count=1,
    shape="veil:cylinder", dimensions=[4.5, 0.4, 4.5], from_surface=False,
    speed=0.01, size=0.07, size_var=0.03, lifetime=40, lifetime_var=10,
    random_direction=False, additive=False,
    sprite="eclipse:textures/particle/wisp_white.png",
    modules=[
        {"module": "veil:gravity", "strength": 0.05},
        {"module": "veil:drag", "strength": 0.3},
        _color_module(
            [(0.0, "#3A3A55"), (1.0, "#2E2347")],
            [(0.0, 0.0), (0.25, 0.3), (0.75, 0.22), (1.0, 0.0)]),
    ])


# ---------------------------------------------------------------------------
# main — write + validate everything
# ---------------------------------------------------------------------------
FX_BUILDERS = {
    "crown_verdict.fx": build_crown_verdict,
    "crown_verdict_coda.fx": build_crown_verdict_coda,
    "gold_rush.fx": build_gold_rush,
    "sanctum_bloom.fx": build_sanctum_bloom,
    "deep_rumble_bed.fx": build_deep_rumble_bed,
}

QUASAR_EMITTERS = {
    "sig_crown_verdict_burst.json": SIG_CROWN_VERDICT_BURST,
    "sig_crown_verdict_halo.json": SIG_CROWN_VERDICT_HALO,
    "sig_gold_rush_glints.json": SIG_GOLD_RUSH_GLINTS,
    "sig_sanctum_glyph.json": SIG_SANCTUM_GLYPH,
    "sig_sanctum_orbit.json": SIG_SANCTUM_ORBIT,
    "sig_deep_rumble_motes.json": SIG_DEEP_RUMBLE_MOTES,
}


def main() -> int:
    rc = 0
    for name, builder_fn in FX_BUILDERS.items():
        path = SIG_DIR / name
        fx = builder_fn()
        raw_len, gz_len = fx.write(path)  # write() round-trip-validates
        fx.write_fxproj(path.with_suffix(".fxproj"))
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (+.fxproj) "
                  f"(raw {raw_len} B, gzip {gz_len} B) — valid")
    for name, data in QUASAR_EMITTERS.items():
        path = QUASAR_DIR / name
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        json.loads(path.read_text(encoding="utf-8"))  # parse check
        print(f"WROTE {path.relative_to(REPO_ROOT)} — valid JSON")
    return rc


if __name__ == "__main__":
    sys.exit(main())
