#!/usr/bin/env python3
"""worldevents_fx — NEWFX-C Photon `.fx` assets (world events & contests), via fxlib.

Generates the thirteen effects of PLAN-NEWFX §2 C1–C5 (rows registered by
`veilfx/WorldEventPhotonFxRows.java`; cues in `network/fx/FxCues.java`):

    eclipse:boss_summon_beacon_0..3   C1 mile-high summon column, boss-tinted x4
                                         (0 Herald SACRED-violet / 1 Ferryman
                                         SACRED-gold / 2 Fog Tyrant STORM /
                                         3 Rift Warden GLITCH split-pair)
    eclipse:contract_omen_ripple      C2 open — crimson ankle-height world ring + cinders
    eclipse:contract_omen_release     C2 close — cinders reverse, gray exhale snuff
    eclipse:minigame_gate_fanfare     C3a open — frame edge-runner + confetti sparks
    eclipse:minigame_gate_collapse    C3a close — frame light unwinds, implodes to a point
    eclipse:race_finish_ribbon        C3b — ring flash + checkered light-ribbon spiral
    eclipse:race_finish_ribbon_gold   C3b podium-1 variant — gold burst added
    eclipse:supply_herald             C4 — sky shimmer, white slit tear, falling ember
    eclipse:dungeon_maw_breath        C5 one-shot — cold dust exhale + two eye glints
    eclipse:dungeon_maw_idle          C5 WINDOWED loop — periodic breath + heartbeat glow
    eclipse:rim_recede                F-092 — the rim wall receding: slate dust curtain
                                         sinking, heavy rock motes sagging outward/down,
                                         a few pale edge glints

fxlib-generated (this script IS the committed source — the binary-diff law's `.fxproj`
requirement applies to editor exports only). Regenerate + validate:

    python3 tools/photon/worldevents_fx.py
    python3 tools/photon/fxlib.py validate src/main/resources/assets/eclipse/fx/*.fx

Style-guide conformance (FX-STYLE-GUIDE.md):
- Palettes are §1 tokens only. C2's crimson body is the shipped contract blood-orange
  family (`contract_mark` 0xFFE05A28 precedent) fading to `COR_INK` #3C096C — dread is
  eclipse-stuff gone sour, never transparent-black.
- Every one-shot scans to the §3 spine (ANTICIPATION 8–12t / IMPACT 2–4t / SETTLE
  20–40t); C1 stretches SETTLE for its scripted 3 s hold (SEQUENCE-channel license).
- Motion verbs: C1 SACRED slow orbits + verticals; C3 collapse is an unwind (reverse
  trace), not a glitch snap; C5 ERA-adjacent drift ≤0.05 blk/t cold dust.
- Budgets: every one-shot ≤ ~120 spawned particles; the idle loop carries a cull box +
  modest maxParticles per the WINDOWED-loop law (INTEGRATION.md §4).
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    BLEND_ADDITIVE, BLEND_ALPHA, FX_ASSETS_DIR, FxBuilder, REPO_ROOT, burst, circle,
    cone, constant, curve, dot, function_shape, gradient, nf3, random_between,
    random_color, sphere, texture_material, validate_file,
)

TEX_CIRCLE = "photon:textures/particle/circle.png"
TEX_SMOKE = "photon:textures/particle/smoke.png"
TEX_RING = "photon:textures/particle/ring.png"
TEX_LASER = "photon:textures/particle/laser.png"
TEX_RING_SOFT = "eclipse:textures/particle/ring_soft.png"
TEX_SQUARE = "eclipse:textures/particle/square_4x4.png"
TEX_WISP = "eclipse:textures/particle/wisp_white.png"

# ---------------------------------------------------------------------------
# Shared timing segments (8-float beziers, x/y normalized 0..1)
# ---------------------------------------------------------------------------
# Smoothstep in (SACRED easing law: nothing linear).
SEG_EASE_IN_OUT_UP = (0.0, 0.0, 0.4, 0.0, 0.6, 1.0, 1.0, 1.0)
# Smoothstep out.
SEG_EASE_IN_OUT_DOWN = (0.0, 1.0, 0.4, 1.0, 0.6, 0.0, 1.0, 0.0)
# Fast ease-out pop (ripple ring expansion — a dropped stone's first wave).
SEG_EASE_OUT = (0.0, 0.0, 0.08, 0.7, 0.45, 0.95, 1.0, 1.0)
# Pop to full then shrink out late.
SEG_HOLD_SHRINK = (0.0, 1.0, 0.6, 1.0, 0.85, 0.5, 1.0, 0.0)

# C1 beacon column width envelope over the 100t duration: dead until the t=10 punch
# (ANTICIPATION), snap to full in 3t (IMPACT), ease to a hold through t=70 (the 3 s
# scripted hold), fray to nothing by t=100 (SETTLE).
BEACON_WIDTH_SEGS = [
    (0.00, 0.0, 0.04, 0.0, 0.08, 0.0, 0.10, 0.0),
    (0.10, 0.0, 0.105, 0.9, 0.115, 1.0, 0.13, 1.0),
    (0.13, 1.0, 0.30, 0.62, 0.50, 0.55, 0.70, 0.50),
    (0.70, 0.5, 0.80, 0.42, 0.90, 0.14, 1.00, 0.0),
]
# C1 orbit-spark emission window: silent through the punch, breathes during the hold,
# closed before the fray finishes (sparks live ~40t past their spawn).
BEACON_SPARK_RATE_SEGS = [
    (0.00, 0.0, 0.08, 0.0, 0.11, 0.0, 0.14, 0.0),
    (0.14, 0.0, 0.18, 0.8, 0.25, 1.0, 0.45, 1.0),
    (0.45, 1.0, 0.55, 0.9, 0.62, 0.4, 0.72, 0.0),
]
# C5 idle breath: one slow exhale hump in the front third of the 68t cycle, then rest.
MAW_BREATH_SEGS = [
    (0.00, 0.0, 0.06, 0.1, 0.12, 0.9, 0.22, 1.0),
    (0.22, 1.0, 0.30, 0.7, 0.38, 0.15, 0.48, 0.0),
    (0.48, 0.0, 0.65, 0.0, 0.85, 0.0, 1.00, 0.0),
]

# ---------------------------------------------------------------------------
# C1 — eclipse:boss_summon_beacon_<kind> (mile-high boss-tinted light column)
# ---------------------------------------------------------------------------
# Authored column height (blocks). "Mile-high": tops out over the build limit so the
# fray reads sky-bound from anywhere; the row's leg distance-scales X/Z only.
BEACON_HEIGHT = 420.0

# Per-kind §1 palettes: (hot rgb, body rgb, deep rgb, hdr boost) — floats 0..1.
# 0 Herald: SACRED violet · 1 Ferryman: SACRED gold (the licensed gold lead) ·
# 2 Fog Tyrant: STORM arc-blue · 3 Rift Warden: GLITCH white core (split pair below).
BEACON_PALETTES = {
    0: ((0.965, 0.937, 1.0), (0.725, 0.549, 1.0), (0.482, 0.310, 0.816), (1.6, 1.2, 2.0)),
    1: ((1.0, 0.914, 0.659), (1.0, 0.820, 0.4), (0.482, 0.310, 0.816), (2.0, 1.6, 0.8)),
    2: ((1.0, 1.0, 1.0), (0.749, 0.851, 1.0), (0.353, 0.553, 0.933), (1.2, 1.5, 2.0)),
    3: ((1.0, 1.0, 1.0), (1.0, 1.0, 1.0), (0.725, 0.549, 1.0), (2.0, 2.0, 2.0)),
}
# SAC_VOID / STM_SLATE fade targets per kind (never fade to black).
BEACON_VOIDS = {
    0: (0.180, 0.137, 0.278), 1: (0.180, 0.137, 0.278),
    2: (0.227, 0.227, 0.333), 3: (0.141, 0.110, 0.220),  # 3: GLI_DEAD
}


def _beacon_column(fx: FxBuilder, name: str, x_off: float, width_peak: float,
                   rgb, hdr) -> None:
    """One vertical hairline beam: width rides BEACON_WIDTH_SEGS, color fades to void."""
    (fx.beam_emitter(
            name, end=(0.0, BEACON_HEIGHT, 0.0),
            width=curve(0.0, width_peak, BEACON_WIDTH_SEGS, "duration", "value"),
            duration=100, looping=False, raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.0), (0.10, 0.0), (0.13, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.13, rgb[0], rgb[1], rgb[2]),
                 (1.0, rgb[0], rgb[1], rgb[2])]))
       .at(x_off, 0.0, 0.0)
       .with_material(texture_material(TEX_LASER, hdr=hdr, blend=BLEND_ADDITIVE,
                                       cull=False))
       # The plan's "cull box sized accordingly": cover the WHOLE column so any
       # visible slice keeps the beam rendered from across the disc.
       .with_cull_box((-8.0, -2.0, -8.0), (8.0, BEACON_HEIGHT + 8.0, 8.0))
       .with_lights(sky=15, block=15))


def build_summon_beacon(kind: int) -> FxBuilder:
    """eclipse:boss_summon_beacon_<kind> — one-shot ~100t, SEQUENCE. Layers:
    L0 ground indraw (ANTICIPATION 0→10), L1 hair-thin column punch (IMPACT 10→13,
    hold →70, fray →100), L2 slow orbit sparks during the hold (SACRED verb),
    L3 base flare ring at the punch. Kind 3 renders the column as a GLITCH split
    pair: white core + magenta/cyan fringes displaced along X (§1.3 law)."""
    hot, body, deep, hdr = BEACON_PALETTES[kind]
    void = BEACON_VOIDS[kind]
    fx = FxBuilder(f"boss_summon_beacon_{kind}")

    # L0 — anticipation indraw: 14 motes pulled into the socket before the punch.
    (fx.particle_emitter(
            "indraw", duration=100, looping=False,
            start_lifetime=constant(10), start_speed=constant(0.0),
            start_size=nf3(random_between(0.08, 0.14), random_between(0.08, 0.14),
                           random_between(0.08, 0.14)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(circle(radius=2.2, thickness=0.0, arc_mode="BurstSpread"))
       .with_curves(
            velocity_over_lifetime=dict(radial=curve(-0.9, -0.1, [SEG_EASE_IN_OUT_DOWN],
                                                     "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.7), (1.0, 0.0)],
                [(0.0, body[0], body[1], body[2]), (1.0, hot[0], hot[1], hot[2])]))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.0, 1.0, 1.2)))
       .with_cull_box((-6.0, -1.0, -6.0), (6.0, 8.0, 6.0)))

    # L1 — the column. Kind 3 = GLITCH split pair (white core, magenta/cyan fringes
    # displaced along one axis); every other kind is a single tinted hairline.
    if kind == 3:
        _beacon_column(fx, "core", 0.0, 0.30, (1.0, 1.0, 1.0), (2.0, 2.0, 2.0))
        _beacon_column(fx, "fringe_magenta", 0.14, 0.16, (1.0, 0.310, 0.847),
                       (1.2, 0.4, 1.0))
        _beacon_column(fx, "fringe_cyan", -0.14, 0.16, (0.310, 0.910, 1.0),
                       (0.4, 1.1, 1.2))
    else:
        _beacon_column(fx, "core", 0.0, 0.34, hot, hdr)
        _beacon_column(fx, "sheath", 0.0, 0.9, body, (hdr[0] * 0.4, hdr[1] * 0.4,
                                                      hdr[2] * 0.4))

    # L2 — slow orbit sparks shed during the hold (0.6 rad/s Y orbit, +0.05 blk/t rise).
    (fx.particle_emitter(
            "orbit_sparks", duration=100, looping=False,
            start_lifetime=random_between(30, 44),
            start_speed=constant(0.0),
            start_size=nf3(random_between(0.10, 0.18), random_between(0.10, 0.18),
                           random_between(0.10, 0.18)),
            simulation_space="Local", max_particles=48)
       .with_emission(rate=curve(0.0, 1.6, BEACON_SPARK_RATE_SEGS, "duration", "value"))
       .with_shape(sphere(radius=1.2, thickness=0.15))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.03, 0.06), constant(0)),
                orbital=nf3(constant(0), constant(0.6), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (0.75, 0.5), (1.0, 0.0)],
                [(0.0, hot[0], hot[1], hot[2]), (0.4, body[0], body[1], body[2]),
                 (1.0, void[0], void[1], void[2])]))
       .with_material(texture_material(TEX_CIRCLE, hdr=(hdr[0] * 0.7, hdr[1] * 0.7,
                                                        hdr[2] * 0.7)))
       .with_renderer(vertex_sorting="NONE")
       .with_lights(sky=15, block=15)
       .with_cull_box((-4.0, -1.0, -4.0), (4.0, 10.0, 4.0)))

    # L3 — base flare: one horizontal ring quad popping open on the punch frame.
    (fx.particle_emitter(
            "base_flare", duration=100, looping=False,
            start_lifetime=constant(18), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=10, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING, hdr=hdr, blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.6, 7.0, [SEG_EASE_OUT], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.5, 0.4), (1.0, 0.0)],
                [(0.0, hot[0], hot[1], hot[2]), (1.0, body[0], body[1], body[2])])))
    return fx


# ---------------------------------------------------------------------------
# C2 — eclipse:contract_omen_ripple / contract_omen_release
# ---------------------------------------------------------------------------
# Contract blood family (contract_mark 0xFFE05A28 precedent) fading to COR_INK.
BLOOD_HOT = (1.0, 0.69, 0.61)      # pale blood flash
BLOOD_BODY = (0.878, 0.353, 0.157)  # the contract blood-orange
BLOOD_DEEP = (0.69, 0.137, 0.188)   # crimson
COR_INK = (0.235, 0.035, 0.424)     # §1.2 fade target
GRAY_EXHALE = (0.604, 0.604, 0.639)
STM_SLATE = (0.227, 0.227, 0.333)


def build_contract_omen_ripple() -> FxBuilder:
    """eclipse:contract_omen_ripple — open, ~50t, SEQUENCE. Fired at EACH client's own
    feet (anonymity law). L0 dimple shimmer (0→8), L1 crimson ankle ring ripples out
    (8→34, ease-out — the dropped stone), L1b echo wave at +8t, L2 red cinders drift
    2 s (settle to COR_INK)."""
    fx = FxBuilder("contract_omen_ripple")

    # L0 — anticipation dimple: a faint blood glow gathering underfoot.
    (fx.particle_emitter(
            "dimple", duration=50, looping=False,
            start_lifetime=constant(10), start_speed=constant(0.0),
            start_size=nf3(1.2), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING_SOFT, hdr=(0.8, 0.2, 0.15),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(1.6, 0.4, [SEG_EASE_IN_OUT_DOWN],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.6, 0.55), (1.0, 0.8)],
                [(0.0, BLOOD_DEEP[0], BLOOD_DEEP[1], BLOOD_DEEP[2])])))

    # L1 — the ripple: two flat ring quads at ankle height (main + echo at +8t),
    # expanding ease-out through the world like a stone dropped in blood.
    for name, t0, reach, alpha in (("ring_main", 8, 26.0, 0.9), ("ring_echo", 16, 14.0, 0.5)):
        (fx.particle_emitter(
                name, duration=50, looping=False,
                start_lifetime=constant(26), start_speed=constant(0.0),
                start_size=nf3(1.0), simulation_space="World", max_particles=2)
           .with_emission(rate=constant(0.0), bursts=[burst(time=t0, count=constant(1))])
           .with_shape(dot(), position=nf3(constant(0.0), constant(0.15), constant(0.0)))
           .with_material(texture_material(TEX_RING, hdr=(1.3, 0.35, 0.3),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
           .with_curves(
                size_over_lifetime=nf3(*[curve(0.5, reach, [SEG_EASE_OUT],
                                               "lifetime", "size") for _ in range(3)]),
                color_over_lifetime=gradient(
                    [(0.0, alpha), (0.12, alpha * 0.85), (1.0, 0.0)],
                    [(0.0, BLOOD_HOT[0], BLOOD_HOT[1], BLOOD_HOT[2]),
                     (0.3, BLOOD_DEEP[0], BLOOD_DEEP[1], BLOOD_DEEP[2]),
                     (1.0, COR_INK[0], COR_INK[1], COR_INK[2])])))

    # L2 — drifting red cinders: 2 s of slow-rising embers left by the wave.
    (fx.particle_emitter(
            "cinders", duration=50, looping=False,
            start_lifetime=random_between(30, 44),
            start_speed=random_between(0.02, 0.05),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=40)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=9, count=constant(20)),
                              burst(time=15, count=constant(16))])
       .with_shape(circle(radius=5.0, thickness=0.6))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.05), constant(0))),
            noise=dict(frequency=0.6, position=nf3(0.04)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.7, 0.4), (1.0, 0.0)],
                [(0.0, BLOOD_HOT[0], BLOOD_HOT[1], BLOOD_HOT[2]),
                 (0.35, BLOOD_DEEP[0], BLOOD_DEEP[1], BLOOD_DEEP[2]),
                 (1.0, COR_INK[0], COR_INK[1], COR_INK[2])]))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.2, 0.3, 0.25)))
       .with_lights(sky=13, block=13))
    return fx


def build_contract_omen_release() -> FxBuilder:
    """eclipse:contract_omen_release — close, ~30t, SEQUENCE. The cinders reverse
    (indraw spiral, 0→12) and snuff in one cold gray exhale (12→30) — crimson
    desaturating to slate, no impact frame (a release, not a hit)."""
    fx = FxBuilder("contract_omen_release")

    # Reversed cinders: embers converging on the player column, dimming as they arrive.
    (fx.particle_emitter(
            "reverse_cinders", duration=30, looping=False,
            start_lifetime=constant(14), start_speed=constant(0.0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(26))])
       .with_shape(circle(radius=3.5, thickness=0.3))
       .with_curves(
            velocity_over_lifetime=dict(radial=curve(-0.5, -0.15, [SEG_EASE_IN_OUT_DOWN],
                                                     "lifetime", "value")),
            color_over_lifetime=gradient(
                [(0.0, 0.7), (0.7, 0.45), (1.0, 0.0)],
                [(0.0, BLOOD_DEEP[0], BLOOD_DEEP[1], BLOOD_DEEP[2]),
                 (1.0, GRAY_EXHALE[0], GRAY_EXHALE[1], GRAY_EXHALE[2])]))
       .with_material(texture_material(TEX_CIRCLE, hdr=(0.8, 0.25, 0.2))))

    # The gray exhale: one soft alpha-blend breath drifting up and out, to slate.
    (fx.particle_emitter(
            "gray_exhale", duration=30, looping=False,
            start_lifetime=random_between(14, 20),
            start_speed=random_between(0.04, 0.08),
            start_size=nf3(random_between(0.5, 0.9), random_between(0.5, 0.9),
                           random_between(0.5, 0.9)),
            simulation_space="World", max_particles=16)
       .with_emission(rate=constant(0.0), bursts=[burst(time=12, count=constant(10))])
       .with_shape(sphere(radius=0.6, thickness=0.4, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.7, 1.6, [SEG_EASE_IN_OUT_UP],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.5), (1.0, 0.0)],
                [(0.0, GRAY_EXHALE[0], GRAY_EXHALE[1], GRAY_EXHALE[2]),
                 (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])])))
    return fx


# ---------------------------------------------------------------------------
# C3a — eclipse:minigame_gate_fanfare / minigame_gate_collapse
# ---------------------------------------------------------------------------
# The portal frame is 3 wide x 4 high (MinigamePortal); the cue anchors at its center.
# Edge-runner traces an oval inscribed in the frame (robust at any yaw, reads at 96).
SAC_HOT = (0.965, 0.937, 1.0)
SAC_VIOLET = (0.725, 0.549, 1.0)
SAC_DEEP = (0.482, 0.310, 0.816)
SAC_GOLD = (1.0, 0.820, 0.4)
SAC_VOID = (0.180, 0.137, 0.278)


def build_minigame_gate_fanfare() -> FxBuilder:
    """eclipse:minigame_gate_fanfare — open, ~60t, BURST. L0 seam glow (0→8), L1 two
    edge-running lights ignite the frame oval (8→48, two laps), L2 confetti sparks
    leap off the frame with real physics (12→50, gold ≤35 %), L3 center bloom pop
    (IMPACT 10→13)."""
    fx = FxBuilder("minigame_gate_fanfare")

    # L0/L3 — center bloom: soft anticipation glow that pops on the impact frame.
    (fx.particle_emitter(
            "center_bloom", duration=60, looping=False,
            start_lifetime=constant(16), start_speed=constant(0.0),
            start_size=nf3(0.8), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=8, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING_SOFT, hdr=(1.4, 1.1, 1.8),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.5, 3.4, [SEG_EASE_OUT], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.9), (0.35, 0.5), (1.0, 0.0)],
                [(0.0, SAC_HOT[0], SAC_HOT[1], SAC_HOT[2]),
                 (1.0, SAC_VIOLET[0], SAC_VIOLET[1], SAC_VIOLET[2])])))

    # L1 — edge runners: the emission POINT itself laps the frame oval; short-lived
    # near-still particles leave a fading light trail along the edge. Two runners,
    # half a lap apart.
    for name, phase in (("runner_a", ""), ("runner_b", "+PI")):
        (fx.particle_emitter(
                name, duration=48, looping=False,
                start_lifetime=constant(10), start_speed=constant(0.0),
                start_size=nf3(random_between(0.12, 0.2), random_between(0.12, 0.2),
                               random_between(0.12, 0.2)),
            simulation_space="World", max_particles=30)
           .with_emission(rate=curve(0.0, 1.1, [(0.0, 0.0, 0.1, 0.0, 0.16, 1.0, 0.3, 1.0),
                                                (0.3, 1.0, 0.7, 1.0, 0.9, 0.6, 1.0, 0.0)],
                                     "duration", "value"))
           .with_shape(function_shape(x=f"1.3*cos(t*4*PI{phase})",
                                      y=f"1.8*sin(t*4*PI{phase})", z="0"))
           .with_material(texture_material(TEX_CIRCLE, hdr=(1.5, 1.2, 2.0)))
           .with_renderer(vertex_sorting="NONE")
           .with_lights(sky=15, block=15)
           .with_curves(color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.6), (1.0, 0.0)],
                [(0.0, SAC_HOT[0], SAC_HOT[1], SAC_HOT[2]),
                 (0.5, SAC_VIOLET[0], SAC_VIOLET[1], SAC_VIOLET[2]),
                 (1.0, SAC_DEEP[0], SAC_DEEP[1], SAC_DEEP[2])])))

    # L2 — confetti sparks leaping off the frame. Two emitters keep the §1.1 gold
    # quota honest: a violet-white majority (32) and a gold minority (10 ≈ 24 %)
    # that only fires on the impact/early-settle beats.
    for name, tint_a, tint_b, hdr, bursts_ in (
            ("confetti_violet", 0xFFF6EFFF, 0xFFB98CFF, (1.2, 1.0, 1.6),
             [burst(time=12, count=constant(14)), burst(time=24, count=constant(10)),
              burst(time=36, count=constant(8))]),
            ("confetti_gold", 0xFFFFE9A8, 0xFFFFD166, (1.8, 1.4, 0.7),
             [burst(time=12, count=constant(6)), burst(time=24, count=constant(4))])):
        (fx.particle_emitter(
                name, duration=60, looping=False,
                start_lifetime=random_between(22, 36),
                start_speed=random_between(0.25, 0.55),
                start_size=nf3(random_between(0.07, 0.14), random_between(0.07, 0.14),
                               random_between(0.07, 0.14)),
                start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
                start_color=random_color(tint_a, tint_b),
                simulation_space="World", max_particles=36,
                parallel_update=False)  # collision law (FX_FORMAT §3.1)
           .with_emission(rate=constant(0.0), bursts=bursts_)
           .with_shape(circle(radius=1.55, thickness=0.1, arc_mode="BurstSpread"))
           .with_physics(collision=True, removed_when_collided=False, gravity=0.14,
                         bounce_chance=0.5, bounce_rate=0.35, collided_friction=0.7)
           .with_material(texture_material(TEX_SQUARE, hdr=hdr))
           .with_curves(
                rotation_over_lifetime=dict(roll=random_between(-6.0, 6.0)),
                color_over_lifetime=gradient(
                    [(0.0, 1.0), (0.7, 0.7), (1.0, 0.0)],
                    [(0.0, 1.0, 1.0, 1.0), (1.0, SAC_VOID[0], SAC_VOID[1], SAC_VOID[2])]))
           .with_lights(sky=15, block=15))
    return fx


def build_minigame_gate_collapse() -> FxBuilder:
    """eclipse:minigame_gate_collapse — close, ~40t, BURST. The frame light unwinds
    (reverse trace shrinking inward, 0→28) and implodes to one point (IMPACT flash at
    28→31, then 9t of settle sparks). An unwind, not a glitch snap — smooth easing."""
    fx = FxBuilder("minigame_gate_collapse")

    # Unwind runner: reverse lap on a shrinking oval — the frame light being reeled in.
    (fx.particle_emitter(
            "unwind", duration=28, looping=False,
            start_lifetime=constant(8), start_speed=constant(0.0),
            start_size=nf3(random_between(0.1, 0.18), random_between(0.1, 0.18),
                           random_between(0.1, 0.18)),
            simulation_space="World", max_particles=36)
       .with_emission(rate=constant(1.6))
       .with_shape(function_shape(x="1.3*(1-t)*cos(0-t*4*PI)",
                                  y="1.8*(1-t)*sin(0-t*4*PI)", z="0"))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.3, 1.0, 1.8)))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.9), (0.6, 0.5), (1.0, 0.0)],
            [(0.0, SAC_VIOLET[0], SAC_VIOLET[1], SAC_VIOLET[2]),
             (1.0, SAC_DEEP[0], SAC_DEEP[1], SAC_DEEP[2])])))

    # Implosion point: one HOT flash quad + a soft void afterimage, then done.
    (fx.particle_emitter(
            "implosion_flash", duration=40, looping=False,
            start_lifetime=constant(12), start_speed=constant(0.0),
            start_size=nf3(0.9), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=28, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.0, 1.7, 2.4)))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.2, 1.4, [SEG_HOLD_SHRINK],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.2, 0.8), (1.0, 0.0)],
                [(0.0, SAC_HOT[0], SAC_HOT[1], SAC_HOT[2]),
                 (0.6, SAC_VIOLET[0], SAC_VIOLET[1], SAC_VIOLET[2]),
                 (1.0, SAC_VOID[0], SAC_VOID[1], SAC_VOID[2])])))

    # Settle: 8 dim sparks drifting off the implosion point.
    (fx.particle_emitter(
            "settle_sparks", duration=40, looping=False,
            start_lifetime=random_between(8, 12),
            start_speed=random_between(0.1, 0.25),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.0), bursts=[burst(time=29, count=constant(8))])
       .with_shape(sphere(radius=0.15, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.0, 0.8, 1.3)))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.8), (1.0, 0.0)],
            [(0.0, SAC_VIOLET[0], SAC_VIOLET[1], SAC_VIOLET[2]),
             (1.0, SAC_VOID[0], SAC_VOID[1], SAC_VOID[2])])))
    return fx


# ---------------------------------------------------------------------------
# C3b — eclipse:race_finish_ribbon (+ _gold podium-1 variant)
# ---------------------------------------------------------------------------
def _finish_ribbon_base(fx: FxBuilder, ribbon_rgb_hi, ribbon_rgb_lo, flash_hdr) -> None:
    """Shared finish composition: ring flash (IMPACT 0→3) + checkered ribbon spiral
    shedding upward off the ring (3→30, square_4x4 checker read). Sized to the REAL
    course ring (ElytraRace.RING_RADIUS = 5): the flash blooms to the ring's 10-block
    diameter, the spiral sheds off its rim."""
    # Ring flash: the start/finish ring itself lighting up.
    (fx.particle_emitter(
            "ring_flash", duration=30, looping=False,
            start_lifetime=constant(12), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(TEX_RING, hdr=flash_hdr, blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(5.0, 10.5, [SEG_EASE_OUT], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.25, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0),
                 (1.0, ribbon_rgb_hi[0], ribbon_rgb_hi[1], ribbon_rgb_hi[2])])))

    # Checkered light-ribbon: quads spiraling up out of the ring plane; the 4x4
    # checker texture + roll spin gives the racing-flag read.
    (fx.particle_emitter(
            "checker_ribbon", duration=30, looping=False,
            start_lifetime=random_between(16, 24), start_speed=constant(0.0),
            start_size=nf3(random_between(0.22, 0.36), random_between(0.22, 0.36),
                           random_between(0.22, 0.36)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=44)
       .with_emission(rate=curve(0.0, 2.0, [(0.0, 0.2, 0.08, 1.0, 0.5, 0.9, 0.75, 0.0),
                                            (0.75, 0.0, 0.85, 0.0, 0.95, 0.0, 1.0, 0.0)],
                                 "duration", "value"))
       .with_shape(function_shape(x="4.5*cos(t*6*PI)", z="4.5*sin(t*6*PI)", y="t*5.5"))
       .with_material(texture_material(TEX_SQUARE, hdr=(1.1, 1.1, 1.3),
                                       blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=random_between(-4.0, 4.0)),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.06, 0.12), constant(0))),
            size_over_lifetime=nf3(*[curve(0.4, 1.0, [SEG_HOLD_SHRINK],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.95), (0.7, 0.7), (1.0, 0.0)],
                [(0.0, ribbon_rgb_hi[0], ribbon_rgb_hi[1], ribbon_rgb_hi[2]),
                 (1.0, ribbon_rgb_lo[0], ribbon_rgb_lo[1], ribbon_rgb_lo[2])]))
       .with_lights(sky=15, block=15))


def build_race_finish_ribbon() -> FxBuilder:
    """eclipse:race_finish_ribbon — later finishers, ~30t, BURST: violet-white checker
    spiral off the ring (SACRED body; no gold — gold is podium 1's license)."""
    fx = FxBuilder("race_finish_ribbon")
    _finish_ribbon_base(fx, SAC_VIOLET, SAC_DEEP, (1.4, 1.2, 2.0))
    return fx


def build_race_finish_ribbon_gold() -> FxBuilder:
    """eclipse:race_finish_ribbon_gold — podium 1, ~30t, BURST: the same spiral gone
    gold + a one-time gold spark burst at the flash frame (impact-slot gold, §1.1)."""
    fx = FxBuilder("race_finish_ribbon_gold")
    _finish_ribbon_base(fx, SAC_GOLD, SAC_DEEP, (2.0, 1.6, 0.8))
    (fx.particle_emitter(
            "gold_burst", duration=30, looping=False,
            start_lifetime=random_between(12, 20),
            start_speed=random_between(0.35, 0.7),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=26)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(24))])
       .with_shape(cone(angle=30.0, radius=4.5, thickness=0.0))
       .with_physics(collision=False, gravity=0.08)
       .with_material(texture_material(TEX_CIRCLE, hdr=(2.0, 1.6, 0.8)))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.6, 0.6), (1.0, 0.0)],
            [(0.0, 1.0, 0.914, 0.659), (0.5, SAC_GOLD[0], SAC_GOLD[1], SAC_GOLD[2]),
             (1.0, SAC_VOID[0], SAC_VOID[1], SAC_VOID[2])]))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# C4 — eclipse:supply_herald (sky tear pre-beat, anchored at surface+70 by the leg)
# ---------------------------------------------------------------------------
ERA_EMBER = (1.0, 0.482, 0.235)
STM_ARC = (0.749, 0.851, 1.0)


def build_supply_herald() -> FxBuilder:
    """eclipse:supply_herald — one-shot ~60t, SEQUENCE, sky-anchored. L1 shimmer patch
    (ANTICIPATION 0→12), L2 white slit tears open (IMPACT 12→15, vertical hairline
    beam), L3 ONE ember streak coughed straight down the crate's future line (14→58),
    L4 tear-edge wisps (settle). The crate + beam arrive ~3 s after the cue."""
    fx = FxBuilder("supply_herald")

    # L1 — shimmer: a 3-block patch of near-still arc-pale motes, barely-there.
    (fx.particle_emitter(
            "shimmer", duration=60, looping=False,
            start_lifetime=random_between(14, 22),
            start_speed=random_between(0.01, 0.03),
            start_size=nf3(random_between(0.3, 0.55), random_between(0.3, 0.55),
                           random_between(0.3, 0.55)),
            simulation_space="World", max_particles=24)
       .with_emission(rate=curve(0.0, 1.4, [(0.0, 0.4, 0.05, 1.0, 0.15, 0.8, 0.25, 0.0),
                                            (0.25, 0.0, 0.5, 0.0, 0.75, 0.0, 1.0, 0.0)],
                                 "duration", "value"))
       .with_shape(sphere(radius=1.6, thickness=0.5))
       .with_material(texture_material(TEX_WISP, hdr=(0.9, 1.0, 1.2), blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.4, 0.4), (1.0, 0.0)],
            [(0.0, STM_ARC[0], STM_ARC[1], STM_ARC[2]),
             (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])])))

    # L2 — the slit: a vertical hairline of white torn open for a few frames.
    (fx.beam_emitter(
            "slit", end=(0.0, 5.0, 0.0),
            width=curve(0.0, 0.5, [(0.0, 0.0, 0.15, 0.0, 0.19, 0.0, 0.20, 0.0),
                                   (0.20, 0.0, 0.21, 1.0, 0.24, 1.0, 0.26, 0.9),
                                   (0.26, 0.9, 0.35, 0.3, 0.42, 0.1, 0.50, 0.0)],
                        "duration", "value"),
            duration=60, looping=False, raycast="NONE",
            color_nf=gradient(
                [(0.0, 0.0), (0.2, 1.0), (0.4, 0.7), (0.5, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.45, 0.965, 0.937, 1.0)]))
       .at(0.0, -2.5, 0.0)
       .with_material(texture_material(TEX_LASER, hdr=(2.0, 2.0, 2.0), cull=False))
       .with_lights(sky=15, block=15))

    # L3 — the ember streak: ONE stretched spark falling straight down the drop line
    # (1.8 blk/t x 44t ≈ 79 blocks — past the surface point the leg re-anchored +70).
    (fx.particle_emitter(
            "ember_streak", duration=60, looping=False,
            start_lifetime=constant(44), start_speed=constant(0.0),
            start_size=nf3(0.16), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=14, count=constant(1))])
       .with_shape(dot())
       .with_curves(
            velocity_over_lifetime=dict(linear=nf3(constant(0.0), constant(-1.8),
                                                   constant(0.0))),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.8, 0.85), (1.0, 0.0)],
                [(0.0, 1.0, 0.914, 0.659), (0.25, ERA_EMBER[0], ERA_EMBER[1], ERA_EMBER[2]),
                 (1.0, 0.69, 0.137, 0.188)]))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.8, 1.0, 0.5)))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5,
                      length_scale=3.0, vertex_sorting="NONE")
       .with_lights(sky=15, block=15)
       .with_cull_box((-2.0, -84.0, -2.0), (2.0, 4.0, 2.0)))

    # L4 — tear-edge wisps: a handful of pale shreds drifting off the closing slit.
    (fx.particle_emitter(
            "tear_wisps", duration=60, looping=False,
            start_lifetime=random_between(18, 28),
            start_speed=random_between(0.04, 0.1),
            start_size=nf3(random_between(0.2, 0.4), random_between(0.2, 0.4),
                           random_between(0.2, 0.4)),
            simulation_space="World", max_particles=14)
       .with_emission(rate=constant(0.0), bursts=[burst(time=15, count=constant(10))])
       .with_shape(sphere(radius=0.3, thickness=0.6))
       .with_material(texture_material(TEX_WISP, hdr=(1.1, 1.1, 1.3), blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.06), constant(0))),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.3, 0.55), (1.0, 0.0)],
                [(0.0, 0.965, 0.937, 1.0),
                 (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])])))
    return fx


# ---------------------------------------------------------------------------
# C5 — eclipse:dungeon_maw_breath (one-shot) + dungeon_maw_idle (WINDOWED loop)
# ---------------------------------------------------------------------------
ERA_SHADOW = (0.227, 0.227, 0.333)
COR_BILE = (0.608, 0.847, 0.706)


def build_dungeon_maw_breath() -> FxBuilder:
    """eclipse:dungeon_maw_breath — discovery one-shot ~50t, BURST. L1 a slow bank of
    cold dust exhaled from the entrance (drift ≤0.05 blk/t after the first push, shade
    on — real cave air), L2 two eye-glint sparks blinking deep in the dark (16→36).
    No impact frame: the discovery is a held breath, not a hit."""
    fx = FxBuilder("dungeon_maw_breath")

    # L1 — the dust bank: heavy alpha smoke rolling out and settling.
    (fx.particle_emitter(
            "dust_bank", duration=50, looping=False,
            start_lifetime=random_between(30, 46),
            start_speed=random_between(0.06, 0.12),
            start_size=nf3(random_between(0.6, 1.1), random_between(0.6, 1.1),
                           random_between(0.6, 1.1)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(14)),
                              burst(time=8, count=constant(10))])
       .with_shape(sphere(radius=1.2, thickness=0.5, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.7, 1.8, [SEG_EASE_IN_OUT_UP],
                                           "lifetime", "size") for _ in range(3)]),
            noise=dict(frequency=0.5, position=nf3(0.03)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.55), (1.0, 0.0)],
                [(0.0, 0.42, 0.44, 0.52),
                 (1.0, ERA_SHADOW[0], ERA_SHADOW[1], ERA_SHADOW[2])])))

    # L2 — the eyes: two dim bile-green glints, a blink apart, deep in the maw.
    for name, t0, x_off in (("eye_left", 16, -0.35), ("eye_right", 19, 0.35)):
        (fx.particle_emitter(
                name, duration=50, looping=False,
                start_lifetime=constant(18), start_speed=constant(0.0),
                start_size=nf3(0.09), simulation_space="World", max_particles=2)
           .with_emission(rate=constant(0.0), bursts=[burst(time=t0, count=constant(1))])
           .with_shape(dot(), position=nf3(constant(x_off), constant(0.4), constant(0.0)))
           .with_material(texture_material(TEX_CIRCLE, hdr=(0.5, 0.9, 0.6)))
           .with_renderer(vertex_sorting="NONE")
           .with_curves(color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.9), (0.5, 0.35), (0.7, 0.8), (1.0, 0.0)],
                [(0.0, COR_BILE[0], COR_BILE[1], COR_BILE[2])])))
    return fx


def build_dungeon_maw_idle() -> FxBuilder:
    """eclipse:dungeon_maw_idle — WINDOWED loop (REPLACE row; DungeonMawIdle window).
    68t cycle: one faint dust exhale in the front third (rate rides MAW_BREATH_SEGS)
    + a heartbeat double-thump glow (bursts at t0/t7, the contract_mark cadence).
    Cull box + maxParticles 40 per the loop law; materialize ramp is the breath's own
    ease-in (≤20t), release fade is the executor's graceful stop."""
    fx = FxBuilder("dungeon_maw_idle")

    # Breath dust: sparse, cold, ≤0.05 blk/t — "this hole is authored", nothing more.
    (fx.particle_emitter(
            "breath_dust", duration=68, looping=True, prewarm=0,
            start_lifetime=random_between(28, 40),
            start_speed=random_between(0.03, 0.05),
            start_size=nf3(random_between(0.4, 0.8), random_between(0.4, 0.8),
                           random_between(0.4, 0.8)),
            simulation_space="World", max_particles=40)
       .with_emission(rate=curve(0.0, 0.9, MAW_BREATH_SEGS, "duration", "value"))
       .with_shape(sphere(radius=1.0, thickness=0.5, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_curves(
            noise=dict(frequency=0.4, position=nf3(0.02)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.4), (1.0, 0.0)],
                [(0.0, 0.4, 0.42, 0.5),
                 (1.0, ERA_SHADOW[0], ERA_SHADOW[1], ERA_SHADOW[2])]))
       .with_cull_box((-4.0, -1.5, -4.0), (4.0, 4.0, 4.0)))

    # Heartbeat glow: one soft quad, double-thump per cycle, heartbeat-dim (α ≤ 0.3).
    (fx.particle_emitter(
            "heartbeat_glow", duration=68, looping=True,
            start_lifetime=constant(22), start_speed=constant(0.0),
            start_size=nf3(0.9), simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(1)),
                              burst(time=7, count=constant(1))])
       .with_shape(dot(), position=nf3(constant(0.0), constant(0.3), constant(0.0)))
       .with_material(texture_material(TEX_RING_SOFT, hdr=(0.4, 0.7, 0.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=nf3(*[curve(0.7, 1.15, [SEG_EASE_IN_OUT_UP],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.3), (0.55, 0.08), (1.0, 0.0)],
                [(0.0, COR_BILE[0], COR_BILE[1], COR_BILE[2]),
                 (1.0, ERA_SHADOW[0], ERA_SHADOW[1], ERA_SHADOW[2])]))
       .with_cull_box((-2.0, -1.0, -2.0), (2.0, 2.5, 2.0)))
    return fx


# ---------------------------------------------------------------------------
# F-092 — eclipse:rim_recede (the rim wall letting go)
# ---------------------------------------------------------------------------
# Call contract (veilfx/WorldEventPhotonFxRows, row CUE_RIM_RECEDE — the DEFAULT
# position leg, so the asset gets NO scale/rotation/entity and cannot read the
# payload floats): `ExpansionBorderFx.Gate.release` fires one cue per player at
# `pos` = that player's nearest point of the OLD rim, y = `profile.surfaceBaseY()`
# (ground), `a` = the old ring radius (informational only), `b` = 0. The beat runs
# against the BOULDER_SINK_TICKS = 16t monolith sink and the
# ExpansionTiming.BORDER_RELEASE_LERP_MS = 10 s SoftBorder glide, so the asset is
# authored at RIM_DURATION ticks — long enough to outlive the sink and carry the
# first half of the glide, short enough that the curtain is gone before the new
# silhouette ring settles.
#
# Because the leg passes no yaw, every layer is authored RADIALLY SYMMETRIC about
# the anchor (rings, `BurstSpread` arcs): the curtain reads as a wall from any
# viewing angle, which is exactly what a per-player rim point needs. Sizes are
# rim-scale — the monoliths it garnishes are 6–14 blocks tall
# (ExpansionBorderFx.HEIGHT_MIN/MAX) and watchers read this from 100+ blocks away.
#
# Stacking law (the tyrant_step V2.1 finding): ALPHA sprites born inside one
# another converge to their own tint, so birth tints start DARK (slate, never the
# pale dust white), alpha peaks stay ≤ 0.34, birth shells are metres apart
# (BurstSpread rings), counts are trimmed to ~119 spawned particles total, and
# HDR lives only on the seven tiny glints at ≤ 1.45. Heavy elements (rock motes,
# ground bank) sit LOW and move SLOW; only the light haze travels.
RIM_DURATION = 130
# Ring radii (blocks) of the curtain layers around the anchor.
RIM_VEIL_R = 24.0
RIM_CURTAIN_R = 22.0
RIM_BANK_R = 20.0
RIM_MOTE_R = 16.0
RIM_GLINT_R = 18.0
RIM_CULL = ((-34.0, -26.0, -34.0), (34.0, 30.0, 34.0))
# Slate dust family: STM_SLATE body -> a bruised mid -> GLI_DEAD fade target
# (§1.5 storm slate + §1.3 dead indigo — never fade to black).
RIM_BRUISE = (0.278, 0.259, 0.337)
GLI_DEAD = (0.141, 0.110, 0.220)
# Pale edge light catching a receding rock face (STM_ARC dimmed, not white).
RIM_GLINT = (0.816, 0.855, 0.949)
# Sink envelope: nothing, then a soft swell, then a long thinning settle.
SEG_DUST_SWELL = (0.0, 0.0, 0.12, 0.55, 0.35, 0.9, 1.0, 1.0)


def build_rim_recede() -> FxBuilder:
    """eclipse:rim_recede — F-092 release beat, ~130t, SEQUENCE. The giant rim rocks
    pull back and the frontier's held dust falls out of the air. L0 a huge, very
    faint back-wall haze marking where the wall STOOD (8 bodies, sinking slowest),
    L1 the slate dust curtain sinking off a 22-block ring (48 bodies in three
    waves), L2 the ground bank rolling outward over the old rim line (34 bodies,
    floor-hugging), L3 heavy rock motes sagging outward and down under gravity
    (22 hard quads, the mass read), L4 seven pale edge glints as the last light
    slides off the receding faces. No impact frame — a release, not a hit."""
    fx = FxBuilder("rim_recede")

    # L0 — back-wall haze: a handful of enormous soft bodies on the outermost ring,
    # barely-there (α ≤ 0.16) and sinking at ~1.6 blk/s. This is the silhouette the
    # far camera actually reads; 8 bodies 19 blocks apart never stack.
    (fx.particle_emitter(
            "wall_haze", duration=RIM_DURATION, looping=False,
            start_lifetime=random_between(64, 90), start_speed=constant(0.0),
            start_size=nf3(random_between(9.0, 14.0), random_between(9.0, 14.0),
                           random_between(9.0, 14.0)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(circle(radius=RIM_VEIL_R, thickness=0.2, arc_mode="BurstSpread"),
                   position=nf3(constant(0.0), constant(12.0), constant(0.0)))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*RIM_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(-2.0, -1.2), constant(0.0)),
                radial=constant(0.35)),
            size_over_lifetime=nf3(*[curve(0.7, 1.0, [SEG_DUST_SWELL], "lifetime", "size")
                                     for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.18, 0.16), (0.7, 0.11), (1.0, 0.0)],
                [(0.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2]),
                 (0.55, RIM_BRUISE[0], RIM_BRUISE[1], RIM_BRUISE[2]),
                 (1.0, GLI_DEAD[0], GLI_DEAD[1], GLI_DEAD[2])])))

    # L1 — the curtain: three waves of broad slate bodies born 17 blocks up on the
    # rim ring, sinking 9–20 blocks and spreading as they fall. THE beat.
    (fx.particle_emitter(
            "dust_curtain", duration=RIM_DURATION, looping=False,
            start_lifetime=random_between(46, 70), start_speed=constant(0.0),
            start_size=nf3(random_between(3.4, 5.6), random_between(3.4, 5.6),
                           random_between(3.4, 5.6)),
            simulation_space="World", max_particles=56)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(20)),
                              burst(time=10, count=constant(16)),
                              burst(time=22, count=constant(12))])
       .with_shape(circle(radius=RIM_CURTAIN_R, thickness=0.35,
                          arc_mode="BurstSpread", arc_spread=0.02),
                   position=nf3(constant(0.0), constant(17.0), constant(0.0)))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*RIM_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(-5.0, -3.0), constant(0.0)),
                radial=constant(0.8)),
            size_over_lifetime=nf3(*[curve(0.55, 1.0, [SEG_DUST_SWELL], "lifetime", "size")
                                     for _ in range(3)]),
            noise=dict(frequency=0.35, position=nf3(0.05)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.34), (0.65, 0.22), (1.0, 0.0)],
                [(0.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2]),
                 (0.5, RIM_BRUISE[0], RIM_BRUISE[1], RIM_BRUISE[2]),
                 (1.0, GLI_DEAD[0], GLI_DEAD[1], GLI_DEAD[2])])))

    # L2 — ground bank: what the curtain leaves on the floor, rolling OUTWARD over
    # the abandoned rim line as the border glides away. Horizontal quads, α ≤ 0.26.
    (fx.particle_emitter(
            "ground_bank", duration=RIM_DURATION, looping=False,
            start_lifetime=random_between(50, 72), start_speed=constant(0.0),
            start_size=nf3(random_between(2.6, 4.2), random_between(2.6, 4.2),
                           random_between(2.6, 4.2)),
            simulation_space="World", max_particles=40)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=26, count=constant(14)),
                              burst(time=40, count=constant(12)),
                              burst(time=56, count=constant(8))])
       .with_shape(circle(radius=RIM_BANK_R, thickness=0.5, arc_mode="BurstSpread"),
                   position=nf3(constant(0.0), constant(0.6), constant(0.0)))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(render_mode="Horizontal", vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*RIM_CULL)
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(1.2)),
            size_over_lifetime=nf3(*[curve(0.6, 1.0, [SEG_EASE_IN_OUT_UP],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.26), (0.7, 0.17), (1.0, 0.0)],
                [(0.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2]),
                 (1.0, GLI_DEAD[0], GLI_DEAD[1], GLI_DEAD[2])])))

    # L3 — rock motes: hard dark quads shed off the sinking monoliths, thrown a
    # little outward and dragged down by real gravity (physics = the weight read,
    # FX_FORMAT §3.1 collision law keeps parallelUpdate off). Born LOW (+6) and
    # slow — heavy things stay near the ground (stacking law's mass clause).
    (fx.particle_emitter(
            "rock_motes", duration=RIM_DURATION, looping=False,
            start_lifetime=random_between(30, 48),
            start_speed=random_between(1.5, 3.5),
            start_size=nf3(random_between(0.5, 1.1), random_between(0.5, 1.1),
                           random_between(0.5, 1.1)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            simulation_space="World", max_particles=26, parallel_update=False)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=4, count=constant(12)),
                              burst(time=16, count=constant(10))])
       .with_shape(circle(radius=RIM_MOTE_R, thickness=0.6, arc_mode="BurstSpread"),
                   position=nf3(constant(0.0), constant(6.0), constant(0.0)))
       .with_physics(collision=True, removed_when_collided=False, gravity=0.55,
                     bounce_chance=0.25, bounce_rate=0.2, collided_friction=0.55)
       .with_material(texture_material(TEX_SQUARE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE", shade=True)
       .with_cull_box(*RIM_CULL)
       .with_curves(
            rotation_over_lifetime=dict(roll=random_between(-3.0, 3.0)),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.72, 0.6), (1.0, 0.0)],
                [(0.0, RIM_BRUISE[0], RIM_BRUISE[1], RIM_BRUISE[2]),
                 (1.0, GLI_DEAD[0], GLI_DEAD[1], GLI_DEAD[2])])))

    # L4 — edge glints: the ONLY bright elements. Seven small additive sparks at
    # HDR 1.45 max, the last daylight sliding off a rock face as it drops away.
    (fx.particle_emitter(
            "edge_glints", duration=RIM_DURATION, looping=False,
            start_lifetime=random_between(12, 20), start_speed=constant(0.0),
            start_size=nf3(random_between(0.28, 0.5), random_between(0.28, 0.5),
                           random_between(0.28, 0.5)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=8, count=constant(4)),
                              burst(time=30, count=constant(3))])
       .with_shape(circle(radius=RIM_GLINT_R, thickness=0.5, arc_mode="BurstSpread"),
                   position=nf3(constant(0.0), constant(8.0), constant(0.0)))
       .with_material(texture_material(TEX_CIRCLE, hdr=(1.25, 1.3, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*RIM_CULL)
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0.0), random_between(-2.2, -1.0), constant(0.0))),
            size_over_lifetime=nf3(*[curve(0.35, 1.0, [SEG_HOLD_SHRINK],
                                           "lifetime", "size") for _ in range(3)]),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.5), (0.6, 0.28), (1.0, 0.0)],
                [(0.0, RIM_GLINT[0], RIM_GLINT[1], RIM_GLINT[2]),
                 (1.0, STM_SLATE[0], STM_SLATE[1], STM_SLATE[2])])))
    return fx


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
BUILDERS = {
    "boss_summon_beacon_0.fx": lambda: build_summon_beacon(0),
    "boss_summon_beacon_1.fx": lambda: build_summon_beacon(1),
    "boss_summon_beacon_2.fx": lambda: build_summon_beacon(2),
    "boss_summon_beacon_3.fx": lambda: build_summon_beacon(3),
    "contract_omen_ripple.fx": build_contract_omen_ripple,
    "contract_omen_release.fx": build_contract_omen_release,
    "minigame_gate_fanfare.fx": build_minigame_gate_fanfare,
    "minigame_gate_collapse.fx": build_minigame_gate_collapse,
    "race_finish_ribbon.fx": build_race_finish_ribbon,
    "race_finish_ribbon_gold.fx": build_race_finish_ribbon_gold,
    "supply_herald.fx": build_supply_herald,
    "dungeon_maw_breath.fx": build_dungeon_maw_breath,
    "dungeon_maw_idle.fx": build_dungeon_maw_idle,
    "rim_recede.fx": build_rim_recede,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


if __name__ == "__main__":
    sys.exit(main())
