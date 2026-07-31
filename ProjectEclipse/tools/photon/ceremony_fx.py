#!/usr/bin/env python3
"""ceremony_fx — NEWFX-B Photon `.fx` assets (altar, souls & ceremonies), via fxlib.

Generates the PLAN-NEWFX §2 B-package effects plus the FX-Wave-13 B6 additions (into
`src/main/resources/assets/eclipse/fx/`, id = `eclipse:<name>`):

    eclipse:dawn_toll_bloom       B1 dawn-toll sky petals, paced to the 3x8t bell rhythm
    eclipse:dawn_toll_rift        B6/W13 escalation overlay — the sky tears wider by day
    eclipse:rebirth_starfall      B2 star-converge + wing-shell rebirth ceremony (REPLACE)
    eclipse:offering_gutter       B3 altar rejection tell (cold ember + falling ash)
    eclipse:ghost_soul_departure  B4 permanent-death mist peel + soul ribbon + glitch pop
    eclipse:revive_thunderbloom   B5 revive completion white collapse + violet lightning ring
    eclipse:revive_soul_thread_1  N9 revive soul thread, stage 1 (slack, the ritual begins)
    eclipse:revive_soul_thread_2  N9 stage 2 (drawing taut)
    eclipse:revive_soul_thread_3  N9 stage 3 (a plucked string — the return is imminent)

These files are fxlib-generated (this script IS the committed source). Regenerate with:

    python3 tools/photon/ceremony_fx.py
    python3 tools/photon/fxlib.py validate --lint

Style-guide conformance (FX-STYLE-GUIDE.md):
  - Palette: SACRED tokens only (§1.1) + the sanctioned GLI_* split pair on B4's tear
    (§1.3 — magenta/cyan appear ONLY as a pair displaced along one axis). Every gradient
    ends on SAC_VOID #2E2347, never transparent-black RGB.
  - Motion: sacred verbs (§2) — slow orbits/verticals, smoothstep-ish curves; nothing
    sacred moves fast except the first 2-4t of an impact. B4's tear uses glitch verbs:
    NO easing, constant sizes, 45-degree rotation snaps, hold-then-pop.
  - Timing: 8-12t anticipation / 2-4t impact / 20-40t settle spines (§3).
  - Budgets: every one-shot stays under ~90 particles; gold stays <= 35% of any
    settle population (§1.1 rule); B3 is deliberately HDR-free (anti-climax).

FX-WAVE-13 B6 PASS — what changed and WHY (census §2 "the levers that are still 0"):

  1. UNITS. Photon reads `startSpeed` and `velocityOverLifetime.linear` in blocks per
     SECOND (`×0.05`/tick), `radial` in `×0.01`/tick and `orbital` in rad/SECOND. The
     shipped file was authored as if all three were per-TICK, i.e. 20x/100x below the
     perception floor: `rebirth_starfall`'s star ring travelled 0.45 of its 8 authored
     blocks, `ghost_soul_departure`'s soul ribbon rose 0.8 blocks under a `tear_pop`
     parked at y = 9, `revive_thunderbloom`'s lightning ring crawled 0.4 blocks across
     the witness circle and `offering_gutter`'s wisps retreated 1.4 CENTIMETRES into the
     stone. Every velocity below is now back-solved from the distance its own comment
     promises (`blocks = v × 0.05 × lifetimeTicks`).
  2. `random_gradient` (via `varied()`) on every emitter with more than a couple of
     particles — the clone look was the loudest "this is a canned effect" tell.
  3. `colorBySpeed` wherever movement IS the statement (star streaks, wing fire, the
     soul ribbon, the lightning filaments, bell dust, the N9 thread motes). The module
     MULTIPLIES the lifetime colour and reads |realVelocity| × 20, so every ramp's hot
     end sits at/near white; `speedRange` is an LDLib2 `Range` whose codec fields are
     `a`/`b`, NOT the `min`/`max` pair `fxlib._min_max` writes (A1/A3 finding) — hence
     the raw `with_module` attach.
  4. Dark birth tints + wider shells (V2.1 stacking law): many ALPHA/ADDITIVE sprites
     inside one half-block converge to their own colour, so every ramp OPENS on
     SAC_VOID/deep and only licks hot at its peak, and the populations that used to be
     born on top of each other (glitter r1.4, lightning r1.2, heart motes r1.8) are born
     on broader shells instead of getting more particles.
  5. HDR clamped to the wave-13 stacking ceiling 1.45 (hue ratio preserved).
  6. Timing snap — `SEG_SNAP_SWELL`/`SEG_SNAP_FLASH`: attack 8t -> 3-5t, decay longer.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import (  # noqa: E402
    B, BLEND_ADDITIVE, BLEND_ALPHA, F, FX_ASSETS_DIR, FxBuilder, I, L, REPO_ROOT,
    SEG_DECAY_TAIL, SEG_SMOOTH_UP, aabb, box, burst, circle, cone, constant, curve,
    function_shape, gradient, nf3, random_between, random_gradient, rom, sphere,
    texture_material, validate_file,
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

#: `photon:.../smoke.png` is a 2x2 FLIPBOOK — drawn without a `uvAnimation` module every
#: particle renders all four puffs as a square (the N4 grave-lantern finding). Holding
#: `frameOverTime` at 0 with a random `startFrame` picks ONE per particle, which doubles
#: as free silhouette variety on the mist/ash banks.
SMOKE_TILES = dict(tiles=(2, 2), animation="WholeSheet", frame_over_time=constant(0.0),
                   start_frame=random_between(0.0, 3.99), cycle=1.0)

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

#: Birth tint (V2.1 stacking law): darker than SAC_VOID so a shell of additive quads
#: opens as a bruise instead of a white ball and only brightens on its own beat.
SAC_BIRTH = (0.13, 0.10, 0.21)
#: Warm birth tint for the gold voices — same law, ember side of the palette.
GOLD_BIRTH = (0.20, 0.15, 0.07)

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4 / §2 "HDR ~1.45").
HDR_CEILING = 1.45

#: `colorBySpeed` cool ends. The module MULTIPLIES the lifetime colour, so the hot end
#: has to sit at/near white or fast particles simply go dark.
COOL_SACRED = (0.46, 0.34, 0.72)   # slow = deep violet drag
COOL_ASH = (0.42, 0.40, 0.46)      # slow = cold gray (B3 only)
HOT_WHITE = (1.0, 1.0, 1.0)
HOT_VIOLET_WHITE = (0.97, 0.94, 1.0)


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/second (|realVelocity| × 20); the result MULTIPLIES the lifetime
    colour. `speedRange` is an LDLib2 `Range`, whose codec record fields are `a`/`b` —
    NOT the `min`/`max` pair `fxlib._min_max` writes, so this never goes through
    `with_curves(color_by_speed=...)` (fxlib is A0 ground this wave).
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling inside the same palette;
    each particle rolls its own memoized lerp, so no two read identical (the A1 idiom)."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED trail/ara configs (trails module, FX_FORMAT §4.2).

    fxlib's `_RendererMixin` only serves standalone emitters; an embedded AraTrailConfig
    carries its own renderer block and falls back to the MISSING (pink) material without
    one (the A4/A8/N4 finding).
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


def lerp(a, b, t):
    return a + (b - a) * t


# ---------------------------------------------------------------------------
# House curve segments. Sacred easing — nothing here may be chord-collinear
# (LINT-LINEAR-CURVE, tolerance 0.02).
# ---------------------------------------------------------------------------
# Smoothstep-ish bloom: ease in, hold, ease out (sacred easing — nothing linear).
SEG_BLOOM = (0.0, 0.0, 0.25, 0.05, 0.35, 1.0, 1.0, 1.0)
# Pop to full in ~15% then gently decay to 0 (impact frames + settle).
SEG_FLASH = (0.0, 0.2, 0.08, 1.0, 0.5, 0.6, 1.0, 0.0)
# Ease-out shrink (retreating wisps / collapsing shells).
SEG_SHRINK = (0.0, 1.0, 0.4, 0.9, 0.8, 0.3, 1.0, 0.0)
# sin(pi*t)-like swell: rise to full at midlife, sink back (petal breath, §2 SACRED).
SEG_SWELL = (0.0, 0.0, 0.35, 1.05, 0.65, 1.05, 1.0, 0.0)
# WAVE-13 timing snap: full open by ~t=0.30 (was ~0.5), then a long sacred exhale.
SEG_SNAP_SWELL = [(0.0, 0.0, 0.05, 0.66, 0.15, 1.04, 0.3, 1.0),
                  (0.3, 1.0, 0.56, 0.88, 0.84, 0.28, 1.0, 0.0)]
# WAVE-13 impact envelope: 2t attack, 30t tail (the money frame keeps its afterglow).
SEG_SNAP_FLASH = (0.0, 0.22, 0.045, 1.0, 0.4, 0.52, 1.0, 0.0)
# Hold-then-draw: near-still for the first half of life, then yanked (B4 kneel -> rise).
SEG_HOLD_DRAW = (0.0, 0.02, 0.42, 0.03, 0.72, 0.66, 1.0, 1.0)


def sz(lo, hi, seg, x_axis="lifetime"):
    """NF3 size_over_lifetime from one shared bezier segment (or segment list)."""
    segs = seg if isinstance(seg, list) else [seg]
    return nf3(*[curve(lo, hi, segs, x_axis, "size") for _ in range(3)])


# ---------------------------------------------------------------------------
# B1 eclipse:dawn_toll_bloom — three god-ray petals synced to the descending bells
# ---------------------------------------------------------------------------
# DawnCeremony.dawnToll(): TOLL_PITCHES fire at +0/+8/+16 (TOLL_SPACING_TICKS = 8),
# drone tail at +24. The cue is sent the same tick as bell 0, so petal k OPENS on
# bell k (startDelay k*8) and its bloom-in (the §3 anticipation) peaks exactly as
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
        # W13: the swell snaps open in ~10t instead of 17 and exhales for the rest, and
        # the two ramps of the random_gradient split the triangle into a violet-leaning
        # and a gold-leaning voice — three petals, three different colours every dawn.
        (fx.particle_emitter(
                f"petal_{k}",
                duration=40 + delay, looping=False, start_delay=constant(delay),
                start_lifetime=constant(34), start_speed=constant(0.0),
                start_size=nf3(1.0), simulation_space="World", max_particles=2)
           .child_of(root)
           .at(px, py, pz).rotated(0.0, k * 60.0, tilt)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
           .with_shape(circle(radius=0.01, thickness=0.0))
           .with_material(texture_material(TEX_PETAL, hdr=hdr(1.1, 1.0, 1.4),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
           .with_curves(
                size_over_lifetime=sz(0.0, 3.6, SEG_SNAP_SWELL),
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.12, 0.9), (0.42, 0.55), (1.0, 0.0)],
                    [(0.0,) + SAC_BIRTH, (0.18,) + SAC_HOT, (0.5,) + SAC_VIOLET,
                     (1.0,) + SAC_VOID],
                    [(0.0,) + SAC_BIRTH, (0.2,) + SAC_GOLD_PALE, (0.52,) + SAC_VIOLET,
                     (1.0,) + SAC_VOID])))
        # Bell-glint dust shed by the petal: SINKS, never rises (§2 "veils fall").
        # Gold is rationed (§1.1 rule, <= 35%): 3 gold chime-glints ride 6 violet ones.
        #
        # W13 units: the shipped sink was −0.055..−0.03 blocks/SECOND, i.e. 0.05 blocks
        # over a 30t life — dust that hung in the air like a photograph. −1.6..−0.9 b/s
        # drops it 1.4-2.4 blocks under the petal, which is the "veil falling" read, and
        # colorBySpeed then turns the drop itself into the colour story: the freshly-shed
        # fast grains glint white, the ones that have stalled sit deep violet.
        for suffix, count, head, hdr_rgb, alt in (
                ("v", 6, SAC_HOT, (0.85, 0.8, 1.0), SAC_VIOLET),
                ("g", 3, SAC_GOLD_PALE, (1.0, 0.9, 0.55), SAC_GOLD)):
            (fx.particle_emitter(
                    f"glint_{k}{suffix}",
                    duration=40 + delay, looping=False, start_delay=constant(delay + 5),
                    start_lifetime=random_between(24, 36),
                    start_speed=random_between(0.4, 1.1),
                    start_size=nf3(random_between(0.1, 0.18)),
                    simulation_space="World", max_particles=count + 3)
               .child_of(root)
               .at(px, py - 0.6, pz)
               .with_emission(rate=constant(0.0),
                              bursts=[burst(time=0, count=constant(count))])
               .with_shape(circle(radius=1.35, thickness=0.35, arc_mode="BurstSpread"))
               .with_material(texture_material(TEX_CIRCLE, hdr=hdr(*hdr_rgb),
                                               blend=BLEND_ADDITIVE))
               .with_renderer(vertex_sorting="NONE")
               .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 0.5, 2.6))
               .with_curves(
                    color_over_lifetime=varied(
                        [(0.0, 0.0), (0.1, 0.85), (0.62, 0.42), (1.0, 0.0)],
                        [(0.0,) + SAC_BIRTH, (0.2,) + head, (0.5,) + SAC_VIOLET,
                         (1.0,) + SAC_VOID],
                        [(0.0,) + SAC_BIRTH, (0.24,) + alt, (0.56,) + SAC_DEEP,
                         (1.0,) + SAC_VOID]),
                    velocity_over_lifetime=dict(
                        linear=nf3(constant(0), random_between(-1.6, -0.9), constant(0)),
                        orbital_mode="AngularVelocity",
                        orbital=nf3(constant(0), random_between(0.5, 1.1), constant(0))),
                    size_over_lifetime=sz(0.35, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# B6/W13 eclipse:dawn_toll_rift — the escalation overlay of the daily rift moment
# ---------------------------------------------------------------------------
# The census asks for a dawn beat that can ESCALATE ("the sky should get worse every
# day"). Executor `scale` is the wrong lever: it does not scale the World-space
# velocities the bloom is built on. So escalation is COUNT — `CeremonyPhotonFxRows`
# spawns 0/1/2/3 of these, golden-angle apart and 7t staggered, off the synced day
# number. One instance = one tear: a black-violet seam rips open overhead, bleeds a
# short curtain of ember-cold ash, and shuts again inside the bell window.
RIFT_Y = 13.0


def build_dawn_toll_rift() -> FxBuilder:
    fx = FxBuilder("dawn_toll_rift")
    root = fx.empty("rift_root").at(0.0, RIFT_Y, -5.0)

    # 1. The seam. A tall thin quad that snaps open (3t) and closes slowly — the sacred
    #    grammar of the rebirth seam, but VOID-first: the tear is a hole, not a flash.
    (fx.particle_emitter(
            "rift_seam",
            duration=46, looping=False, start_lifetime=constant(30),
            start_speed=constant(0.0),
            start_size=nf3(constant(0.5), constant(4.2), constant(0.5)),
            simulation_space="World", max_particles=2)
       .child_of(root).rotated(0.0, 0.0, 8.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_BEAM_CORE, hdr=hdr(1.3, 1.1, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.05, 1.0, SEG_SNAP_FLASH),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.08, 0.95), (0.45, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.16,) + SAC_HOT, (0.55,) + SAC_VIOLET,
                 (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.2,) + SAC_VIOLET, (0.6,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]))
       .with_lights(sky=15, block=15))

    # 2. The bleed. Ash-cold motes spill OUT of the seam and fall — the physical proof
    #    that something opened. colorBySpeed reads the fall: the ones still accelerating
    #    out of the tear are hot, the settled ones are void-dark.
    (fx.particle_emitter(
            "rift_bleed",
            duration=46, looping=False, start_delay=constant(3),
            start_lifetime=random_between(26, 40),
            start_speed=random_between(1.2, 3.4),
            start_size=nf3(random_between(0.07, 0.15)),
            simulation_space="World", max_particles=22)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(9)),
                                                  burst(time=6, count=constant(7))])
       .with_shape(box(emit_from="Volume"), scale=(0.22, 3.4, 0.22))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(0.9, 0.7, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=2.4,
                      velocity_scale=0.35, vertex_sorting="NONE")
       .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 0.8, 5.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-2.6, -1.2), constant(0)),
                speed_modifier=curve(0.15, 1.0, [SEG_SHRINK], "lifetime", "value")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.8), (0.66, 0.4), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.24,) + SAC_HOT, (0.6,) + SAC_DEEP,
                 (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.3,) + SAC_VIOLET, (0.7,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.3, 1.0, SEG_SHRINK))
       .with_lights(sky=14, block=14))

    # 3. The shroud. A wide dark ALPHA bank around the seam so the tear reads as a hole
    #    in something instead of a glowing stick — this is the layer that makes the sky
    #    look BRUISED, and it is deliberately the darkest thing in the file.
    (fx.particle_emitter(
            "rift_shroud",
            duration=46, looping=False,
            start_lifetime=random_between(30, 44),
            start_speed=random_between(0.3, 0.9),
            start_size=nf3(random_between(1.5, 2.6)),
            simulation_space="World", max_particles=10)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=1.5, thickness=0.7))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            uv_animation=SMOKE_TILES,
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.5, 0.2), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), random_between(-0.3, 0.3), constant(0))),
            size_over_lifetime=sz(0.75, 1.35, SEG_BLOOM),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.16, 0.4), (0.7, 0.28), (1.0, 0.0)],
                [(0.0, 0.09, 0.07, 0.14), (0.5, 0.2, 0.15, 0.32), (1.0,) + SAC_VOID],
                [(0.0, 0.07, 0.06, 0.12), (0.5, 0.26, 0.18, 0.38), (1.0,) + SAC_VOID])))
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
    #
    # W13 units: 8 blocks of inward travel in an 18t life needs 0.44 b/t = 8.9 blocks per
    # SECOND, not the shipped 0.55 b/s (which covered 0.45 blocks — the "convergence"
    # never happened). The descent is the same story: 7.4 blocks in 18t = 8.2 b/s, and
    # it ACCELERATES (curve reads `lower` at t=0 with SEG_SMOOTH_UP) so the stars fall
    # like stars instead of drifting like snow. colorBySpeed then pays that motion off:
    # a streak is white-hot while it is still diving and violet once it has arrived.
    (fx.particle_emitter(
            "star_streaks",
            duration=24, looping=False,
            start_lifetime=random_between(16, 20),
            start_speed=random_between(-10.5, -8.5),  # radially INWARD off the ring
            start_size=nf3(random_between(0.22, 0.34)),
            simulation_space="World", max_particles=8)
       .at(0.0, 7.0, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(circle(radius=8.0, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.5, 1.35, 1.7),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=6.0,
                      velocity_scale=0.35, vertex_sorting="NONE")
       .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 4.0, 16.0))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.14, 1.0), (0.85, 0.72), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.2,) + SAC_HOT, (0.6,) + SAC_VIOLET,
                 (0.85,) + SAC_DEEP, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.22,) + SAC_GOLD_PALE, (0.6,) + SAC_VIOLET,
                 (0.85,) + SAC_DEEP, (1.0,) + SAC_VOID]),
            # Descent: the ring is +7.4 over the chest; 5 -> 11 b/s over ~18t = 7.5 blocks.
            velocity_over_lifetime=dict(linear=nf3(
                constant(0), curve(-5.0, -11.0, [SEG_SMOOTH_UP], "lifetime", "velocity"),
                constant(0))))
       .with_lights(sky=15, block=15))

    # L2 indraw shell: a breath of motes collapsing to the seam (8t anticipation).
    # r = 1.7 in 8 ticks = 0.21 b/t = 4.3 b/s (shipped: 0.24 b/s = 0.1 blocks).
    (fx.particle_emitter(
            "indraw_shell",
            duration=26, looping=False, start_delay=constant(16),
            start_lifetime=constant(8), start_speed=constant(-4.6),
            start_size=nf3(random_between(0.1, 0.16)),
            simulation_space="World", max_particles=16)
       .child_of(chest)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(sphere(radius=1.7, thickness=0.0))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(0.8, 0.7, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.2), (0.8, 0.95), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.35,) + SAC_DEEP, (0.75,) + SAC_VIOLET,
                 (1.0,) + SAC_HOT],
                [(0.0,) + SAC_BIRTH, (0.4,) + SAC_VIOLET, (0.8,) + SAC_HOT,
                 (1.0,) + SAC_HOT]),
            size_over_lifetime=sz(1.0, 0.3, SEG_DECAY_TAIL)))

    # L3 the blinding seam (IMPACT, 3t): one vertical hairline flaring open.
    (fx.particle_emitter(
            "seam_flash",
            duration=30, looping=False, start_delay=constant(24),
            start_lifetime=constant(5), start_speed=constant(0.0),
            start_size=nf3(constant(0.55), constant(2.4), constant(0.55)),
            simulation_space="World", max_particles=2)
       .child_of(chest)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(circle(radius=0.01, thickness=0.0))
       .with_material(texture_material(TEX_BEAM_CORE, hdr=hdr(2.2, 2.0, 2.6),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard", vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.5,) + SAC_HOT, (1.0,) + SAC_VIOLET]),
            size_over_lifetime=sz(0.3, 1.0, SEG_SNAP_FLASH))
       .with_lights(sky=15, block=15))

    # L4 wing shell: two mirrored fans of violet fire snapping open off the shoulders.
    # 8-13 b/s decayed by the speedModifier covers ~3.5 blocks in 16t — a wing you can
    # see open. colorBySpeed sells the snap: white at the leading edge, deep where the
    # fire has already stalled (§2 "only impacts are fast").
    for name, zrot in (("wing_l", 55.0), ("wing_r", -55.0)):
        (fx.particle_emitter(
                name,
                duration=50, looping=False, start_delay=constant(26),
                start_lifetime=random_between(12, 20),
                start_speed=random_between(8.0, 13.0),
                start_size=nf3(random_between(0.22, 0.4)),
                simulation_space="World", max_particles=20)
           .child_of(chest)
           .at(0.0, 0.2, 0.0).rotated(0.0, 0.0, zrot)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(16))])
           .with_shape(cone(angle=24.0, radius=0.22, thickness=0.4,
                            arc_mode="BurstSpread"))
           .with_material(texture_material(TEX_WISP, hdr=hdr(1.3, 1.1, 1.7),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(render_mode="StretchedBillboard", length_scale=2.6,
                          velocity_scale=0.2, vertex_sorting="NONE")
           .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_VIOLET_WHITE,
                                                       1.0, 11.0))
           .with_curves(
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.1, 1.0), (0.55, 0.8), (1.0, 0.0)],
                    [(0.0,) + SAC_BIRTH, (0.18,) + SAC_HOT, (0.5,) + SAC_VIOLET,
                     (0.78,) + SAC_DEEP, (1.0,) + SAC_VOID],
                    [(0.0,) + SAC_BIRTH, (0.22,) + SAC_VIOLET, (0.55,) + SAC_DEEP,
                     (1.0,) + SAC_VOID]),
                # Fire decelerates fast after the 2-4t snap.
                velocity_over_lifetime=dict(
                    linear=nf3(0), speed_modifier=curve(0.12, 1.0, [SEG_SHRINK],
                                                        "lifetime", "value")),
                size_over_lifetime=sz(0.5, 1.1, SEG_SHRINK)))

    # L5 ash-glitter rain (settle): violet body + a smaller gold voice (<= ~30%).
    # Shell widened 1.4 -> 2.1 instead of adding particles (stacking law: 25 additive
    # grains born inside one half-block converge to a white smudge), 1.0-2.6 b/s of
    # initial scatter and real gravity so it RAINS.
    for name, count, cols, cols_alt, hdr_rgb in (
            ("glitter_violet", 18,
             [(0.0,) + SAC_BIRTH, (0.22,) + SAC_HOT, (0.55,) + SAC_VIOLET, (1.0,) + SAC_VOID],
             [(0.0,) + SAC_BIRTH, (0.26,) + SAC_VIOLET, (0.6,) + SAC_DEEP, (1.0,) + SAC_VOID],
             (0.7, 0.6, 0.9)),
            ("glitter_gold", 7,
             [(0.0,) + GOLD_BIRTH, (0.2,) + SAC_GOLD, (0.55,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID],
             [(0.0,) + GOLD_BIRTH, (0.24,) + SAC_GOLD_PALE, (0.6,) + SAC_GOLD, (1.0,) + SAC_VOID],
             (1.0, 0.9, 0.5))):
        (fx.particle_emitter(
                name,
                duration=40, looping=False, start_delay=constant(28),
                start_lifetime=random_between(28, 42),
                start_speed=random_between(1.0, 2.6),
                start_size=nf3(random_between(0.07, 0.13)),
                simulation_space="World", max_particles=count + 4)
           .child_of(chest)
           .at(0.0, 1.0, 0.0)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(count))])
           .with_shape(sphere(radius=2.1, thickness=0.7, arc=180.0))
           .with_material(texture_material(TEX_CIRCLE, hdr=hdr(*hdr_rgb),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_physics(collision=True, removed_when_collided=False, friction=0.99,
                         collided_friction=0.6, gravity=0.11, bounce_chance=0.25,
                         bounce_rate=0.25, bounce_spread=0.05)
           .with_curves(
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.1, 0.9), (0.62, 0.45), (1.0, 0.0)], cols, cols_alt),
                size_over_lifetime=sz(0.3, 1.0, SEG_SHRINK)))
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
    # 0.8-1.8 b/s of initial cough (was 0.04-0.09 b/s, i.e. nothing) under the shipped
    # gravity; colorBySpeed keeps it COLD — the ash never brightens, it only greys as it
    # slows, which is exactly the anti-climax read. HDR stays off (B3 law).
    (fx.particle_emitter(
            "ash_cough",
            duration=24, looping=False, start_delay=constant(10),
            start_lifetime=random_between(18, 26),
            start_speed=random_between(0.8, 1.8),
            start_size=nf3(random_between(0.09, 0.16)),
            simulation_space="World", max_particles=10)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(7))])
       .with_shape(sphere(radius=0.28, thickness=0.7, arc=180.0))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_physics(collision=True, removed_when_collided=False, friction=0.985,
                     collided_friction=0.7, gravity=0.14, bounce_chance=0.0,
                     bounce_rate=0.0)
       .with_module("colorBySpeed", color_by_speed(COOL_ASH, (0.78, 0.76, 0.82), 0.4, 3.0))
       .with_curves(
            uv_animation=SMOKE_TILES,
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.7), (0.62, 0.42), (1.0, 0.0)],
                [(0.0, 0.54, 0.52, 0.58), (0.5, 0.35, 0.33, 0.4), (1.0,) + SAC_VOID],
                [(0.0, 0.46, 0.45, 0.52), (0.5, 0.3, 0.28, 0.36), (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.6, 1.15, SEG_BLOOM)))
    # L3 two dim wisps retreating INTO the stone (radial inward + sinking, shrink out).
    # `radial` is ×0.01/tick, so the shipped −0.1 moved 1.4 CENTIMETRES over 14 ticks.
    # −3.9 pulls the wisps the full 0.55 r into the crown; −1.2 b/s sinks them 0.84.
    (fx.particle_emitter(
            "wisp_retreat",
            duration=30, looping=False, start_delay=constant(12),
            start_lifetime=constant(14), start_speed=constant(0.0),
            start_size=nf3(random_between(0.14, 0.2)),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(sphere(radius=0.55, thickness=0.0, arc=180.0,
                          arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_WISP, blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.22, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.45,) + SAC_DEEP, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.45,) + SAC_VIOLET, (1.0,) + SAC_VOID]),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), constant(-1.2), constant(0)),
                radial=constant(-3.9)),
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
#: Where the tear fires. The ribbon's draw curve below is back-solved to put the head
#: here at t=56, which the shipped units missed by a factor of 20 (the pop went off in
#: empty air 8 blocks above a ribbon that had risen 0.8 blocks).
TEAR_Y = 9.4


def build_ghost_soul_departure() -> FxBuilder:
    fx = FxBuilder("ghost_soul_departure")
    # L1 mist silhouette: kneeling-height alpha-mist, holds, then is drawn up late.
    (fx.particle_emitter(
            "mist_silhouette",
            duration=16, looping=False,
            start_lifetime=random_between(44, 56),
            start_speed=random_between(0.1, 0.3),
            start_size=nf3(random_between(0.28, 0.44)),
            simulation_space="World", max_particles=26)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(22))])
       .with_shape(box(emit_from="Volume"), position=(0.0, 0.55, 0.0),
                   scale=(0.55, 1.1, 0.4))
       .with_material(texture_material(TEX_SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            uv_animation=SMOKE_TILES,
            # Ghost-pale: desaturated HOT at low alpha; fade lands on VOID. The second
            # ramp is a colder, bluer ghost so the 22 mist quads stop reading as clones.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.16, 0.32), (0.55, 0.26), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.3,) + SAC_HOT, (0.6, 0.72, 0.66, 0.86),
                 (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.3, 0.66, 0.7, 0.88), (0.62, 0.5, 0.52, 0.72),
                 (1.0,) + SAC_VOID]),
            # The kneel-hold: near-zero rise for ~55% of life, then drawn skyward
            # (0.05 -> 2.6 b/s = ~1.6 blocks of late lift on a 50t mist).
            velocity_over_lifetime=dict(linear=nf3(
                constant(0),
                curve(0.05, 2.6, [SEG_HOLD_DRAW], "lifetime", "value"),
                constant(0))),
            size_over_lifetime=sz(0.7, 1.15, SEG_BLOOM)))
    # L2 soul ribbon: stretched wisps accelerating skyward off the chest (24->56).
    (fx.particle_emitter(
            "soul_ribbon",
            duration=20, looping=False, start_delay=constant(24),
            start_lifetime=random_between(26, 32),
            start_speed=random_between(0.3, 0.8),
            start_size=nf3(random_between(0.14, 0.22)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4)),
                                                  burst(time=6, count=constant(3)),
                                                  burst(time=12, count=constant(3))])
       .with_shape(sphere(radius=0.25, thickness=0.5), position=(0.0, 1.0, 0.0))
       .with_material(texture_material(TEX_WISP, hdr=hdr(1.1, 1.0, 1.3),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=5.0,
                      velocity_scale=0.5, vertex_sorting="NONE")
       # The draw IS the emotion, so it gets the colorBySpeed: a wisp that is still
       # being pulled reads white-hot, one that has slipped the pull cools to violet.
       .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 1.0, 11.0))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.14, 0.9), (0.8, 0.55), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.22,) + SAC_HOT, (0.55,) + SAC_VIOLET,
                 (0.82,) + SAC_DEEP, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.26,) + SAC_VIOLET, (0.6,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            # 1.2 -> 10.5 blocks/SECOND over each wisp's ~29t life = ~8.5 blocks of
            # stretch off the y=1.0 chest, which parks the head at TEAR_Y on the tear
            # tick. The shipped 0.05 -> 1.05 was blocks/TICK maths: 0.8 blocks total.
            velocity_over_lifetime=dict(linear=nf3(
                constant(0),
                curve(1.2, 10.5, [SEG_SMOOTH_UP], "lifetime", "value"),
                constant(0))))
       .with_lights(sky=13, block=13))
    # L3 the tear (t=56, where the accelerating rise puts the ribbon head at TEAR_Y):
    # GLITCH verbs — a 2t white pop plus a magenta/cyan split pair displaced along X.
    # Deliberately NOT touched by the wave-13 easing/variation pass: glitch grammar is
    # "no easing, no variation, hard on/off" (§2), and a random_gradient here would
    # soften exactly the thing that makes the tear read as a broken frame.
    (fx.particle_emitter(
            "tear_pop",
            duration=62, looping=False, start_delay=constant(56),
            start_lifetime=constant(2), start_speed=constant(0.0),
            start_size=nf3(0.8), simulation_space="World", max_particles=2)
       .at(0.0, TEAR_Y, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(2.0, 2.0, 2.0),
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
           .at(off_x, TEAR_Y, 0.0)
           .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
           .with_shape(box(emit_from="Volume"), scale=(0.05, 0.6, 0.05))
           .with_material(texture_material(TEX_STATIC, hdr=hdr(1.2, 1.2, 1.2),
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
        width=curve(0.12, 1.0, [SEG_DECAY_TAIL], "duration"),
        raycast="NONE",
        color_nf=gradient(
            [(0.0, 0.9), (0.7, 0.7), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.6,) + SAC_HOT, (1.0,) + SAC_VIOLET])
    ).with_material(texture_material(TEX_BEAM_CORE, hdr=hdr(2.0, 1.9, 2.4),
                                     blend=BLEND_ADDITIVE))
    # L1b indraw motes: the witness ring pulled into the sigil (12t anticipation).
    # r = 3.4 in ~10t = 0.34 b/t = 6.8 b/s (shipped 0.35 b/s moved 0.2 blocks).
    (fx.particle_emitter(
            "sigil_indraw",
            duration=12, looping=False,
            start_lifetime=random_between(9, 12), start_speed=random_between(-8.0, -6.0),
            start_size=nf3(random_between(0.09, 0.15)),
            simulation_space="World", max_particles=14)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6)),
                                                  burst(time=4, count=constant(6))])
       .with_shape(circle(radius=3.4, thickness=0.25, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(0.8, 0.7, 1.0),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=2.2,
                      velocity_scale=0.3, vertex_sorting="NONE")
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.15), (0.75, 0.9), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.35,) + SAC_DEEP, (0.7,) + SAC_VIOLET,
                 (1.0,) + SAC_HOT],
                [(0.0,) + SAC_BIRTH, (0.4,) + SAC_VIOLET, (1.0,) + SAC_HOT])))
    # L2 bloom flash (IMPACT): a soft expanding ring quad, 3t of money frames.
    (fx.particle_emitter(
            "bloom_flash",
            duration=18, looping=False, start_delay=constant(12),
            start_lifetime=constant(7), start_speed=constant(0.0),
            start_size=nf3(1.0), simulation_space="World", max_particles=2)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_material(texture_material(TEX_RING_SOFT, hdr=hdr(2.2, 2.0, 2.5),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal", vertex_sorting="NONE")
       .with_curves(
            size_over_lifetime=sz(0.4, 5.5, SEG_SNAP_FLASH),
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.5, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0), (0.4,) + SAC_HOT, (1.0,) + SAC_VIOLET]))
       .with_lights(sky=15, block=15))
    # L3 the lightning ring: fast-out filaments hugging the ground, noise-crackled.
    # FX-Wave-11 stacking-law pass: 26 additive filaments born on a 0.4 r shell all
    # overlapped at the sigil for the first ticks. Count 26->14 on a 1.2 r shell.
    # FX-Wave-13: shell 1.2 -> 1.9 (born further apart instead of dimmer), 9-13 b/s
    # decayed by the speedModifier = ~4.5 blocks of reach across the witness circle
    # (shipped 0.5-0.65 b/s reached 0.4 blocks), dark birth tint so the 14 filaments do
    # NOT re-add the white ball the wave-11 pass removed, and colorBySpeed to make the
    # race legible: white while the filament runs, violet the instant it stalls.
    (fx.particle_emitter(
            "lightning_ring",
            duration=20, looping=False, start_delay=constant(12),
            start_lifetime=random_between(12, 18),
            start_speed=random_between(9.0, 13.0),
            start_size=nf3(random_between(0.16, 0.26)),
            simulation_space="World", max_particles=30)
       .at(0.0, 0.15, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(circle(radius=1.9, thickness=0.0, arc_mode="BurstSpread"))
       .with_material(texture_material(TEX_LASER, hdr=hdr(1.2, 1.0, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=3.2,
                      velocity_scale=0.4, vertex_sorting="NONE")
       .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 1.5, 12.0))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.1, 0.68), (0.5, 0.5), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.2,) + SAC_HOT, (0.45,) + SAC_VIOLET,
                 (0.78,) + SAC_DEEP, (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.24,) + SAC_VIOLET, (0.6,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            # Impact-fast for 2-4t, then the filaments stall and crackle out (§2).
            velocity_over_lifetime=dict(
                linear=nf3(0), speed_modifier=curve(0.08, 1.0, [SEG_SHRINK],
                                                    "lifetime", "value")),
            noise=dict(frequency=2.6, quality="Noise2D",
                       position=nf3(constant(0.16), constant(0.03), constant(0.16)),
                       rotation=constant(0), size=constant(0)))
       .with_lights(sky=15, block=15))
    # L4 heart motes: the settle — slow risers, violet body + a small gold voice.
    # 0.6-1.8 b/s of rise over a ~37t life = ~1.2 blocks; orbital 1.1 rad/s turns them
    # ~2 radians over that life, which is the slow sacred spiral the shipped 0.6 rad/s
    # only hinted at while the linear rise (0.03-0.05 b/s) held them frozen.
    for name, count, cols, cols_alt, hdr_rgb in (
            ("heart_motes", 12,
             [(0.0,) + SAC_BIRTH, (0.24,) + SAC_HOT, (0.55,) + SAC_VIOLET, (1.0,) + SAC_VOID],
             [(0.0,) + SAC_BIRTH, (0.28,) + SAC_VIOLET, (0.6,) + SAC_DEEP, (1.0,) + SAC_VOID],
             (0.8, 0.7, 1.0)),
            ("heart_glints", 4,
             [(0.0,) + GOLD_BIRTH, (0.22,) + SAC_GOLD_PALE, (0.55,) + SAC_GOLD, (1.0,) + SAC_VOID],
             [(0.0,) + GOLD_BIRTH, (0.26,) + SAC_GOLD, (0.62,) + SAC_GOLD_PALE, (1.0,) + SAC_VOID],
             (0.9, 0.8, 0.5))):
        (fx.particle_emitter(
                name,
                duration=30, looping=False, start_delay=constant(15),
                start_lifetime=random_between(30, 44),
                start_speed=random_between(0.4, 1.1),
                start_size=nf3(random_between(0.09, 0.15)),
                simulation_space="World", max_particles=count + 4)
           .at(0.0, 0.3, 0.0)
           .with_emission(rate=constant(0.0),
                          bursts=[burst(time=0, count=constant(count))])
           .with_shape(circle(radius=2.4, thickness=0.75))
           .with_material(texture_material(TEX_CIRCLE, hdr=hdr(*hdr_rgb),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_curves(
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.12, 0.85), (0.66, 0.45), (1.0, 0.0)], cols, cols_alt),
                velocity_over_lifetime=dict(
                    linear=nf3(constant(0), random_between(0.6, 1.8), constant(0)),
                    orbital_mode="AngularVelocity",
                    orbital=nf3(constant(0), random_between(0.8, 1.4), constant(0))),
                size_over_lifetime=sz(0.4, 1.0, SEG_SHRINK)))
    return fx


# ---------------------------------------------------------------------------
# N9 eclipse:revive_soul_thread_1/2/3 — the soul thread of the revive ritual
# ---------------------------------------------------------------------------
# Census §6 row N9: "while the revive ritual runs, a glowing Ara thread spans from the
# grave to the sigil and pulls taut as it progresses."
#
# GEOMETRY. Anchored at the SIGIL (altar crown, where the ritualist and the witness
# circle stand) with the asset's local +Z aimed at the grave — the server pre-computes
# the X/Y Euler pair off the sigil->grave vector and ships it as the cue's a/b
# (`PlayerFxPhotonRows.heartTheftArc` aim convention: JOML rotationXYZ maps +Z to
# (sin ay, −sin ax·cos ay, cos ax·cos ay)). The span is BAKED at THREAD_SPAN, NOT
# executor-scaled: `setScale` scales the transform, not the World-space carrier
# velocities the ribbons are dragged by, so a scaled thread would tear itself apart.
# The ribbon's colorOverLength therefore fades to nothing at the far end and the thread
# reads as "reaching out of the dark toward the grave" at any real grave distance.
#
# WHY CARRIERS, NOT `ara_trail_emitter`. A standalone ara emitter sits at the anchor and
# draws nothing (the A8/N4 finding); an Ara ribbon needs a MOVING point. Three
# near-invisible carriers run the span from the grave end INTO the sigil, dragging one
# ribbon layer each — so the thread is not just present, it visibly flows homeward. Two
# to three carriers per layer are alive at any time (`rate = CONCURRENT / travel`), whose
# staggered completion fractions overlap into one continuous, shimmering strand.
#
# WHY THREE FILES. `section` cross-section tubes are broken in Photon 2.1.5, so a thick
# thread has to be a RIBBON STACK; and the taut-ness has to change over a 3-minute
# ritual, which no single asset parameter can do from the client side. The auftrag
# explicitly allows staged cue re-sends, so tautness is baked into three stages and
# `ReviveRitual` re-sends the matching cue every SOUL_THREAD_INTERVAL_TICKS.
#
# WHAT ACTUALLY TIGHTENS (all three lerp from slack -> locked on `taut`):
#   * ara physics — gravity/inertia/damping fall away, so the ribbon stops sagging and
#     lagging and starts standing like a plucked string,
#   * carrier travel time 36t -> 20t, so the flow speeds up,
#   * ribbon alpha + mote density/speed rise, so the thread gets BRIGHTER and busier,
#   * the sigil-end arrival glints appear only from stage 2 (the pull becomes visible).
#: Baked span of the thread along local +Z, in blocks.
THREAD_SPAN = 11.0
#: One asset runtime. `ReviveRitual` re-sends every 40t, so 44 leaves a 4t crossfade
#: (the row leg forces allowMulti — without it Photon's same-anchor dedup would eat
#: every re-send and the thread would blink out after the first 44 ticks).
THREAD_DURATION = 44
#: Concurrent carriers per ribbon layer — the continuity knob (the N4 thread lesson:
#: one carrier shows a stub that grows and vanishes, three overlap into a strand).
THREAD_CONCURRENT = 3.0


def _thread_taper():
    """Ribbon width over length: a hair at the sigil head, full through the middle,
    out to a true point at the grave end (so any real grave distance reads)."""
    return curve(0.0, 1.0,
                 [(0.0, 0.55, 0.12, 0.95, 0.3, 1.0, 0.5, 0.98),
                  (0.5, 0.98, 0.72, 0.8, 0.9, 0.26, 1.0, 0.0)],
                 "length", "thickness")


def _thread_ribbon(thickness, smoothness, color_over_length, hdr_rgb, physics):
    """One layer of the 3-ribbon stack as an EMBEDDED `trails` module compound.

    `trails.lifetime` is a FRACTION of the carrier's lifetime (A8 finding: `araConfig.time`
    is dead for embedded trails — `TrailsSetting.setup` always installs a lifetimeSupplier
    of `trails.lifetime × particle.getLifetime() / 20` seconds), so 1.0 = the ribbon spans
    the whole path by the moment its carrier reaches the sigil.
    `dieWithParticles` OFF: the strand keeps fading after its carrier arrives, which is
    what hides the hand-over between overlapping carriers.
    `highQualityCorners` OFF: its miter compensation divides thickness by max(dot, 0.15)
    and shreds a densely-sampled slow ribbon into a comb of spikes (the A4 derivation).
    """
    return {
        "ratio": F(1.0), "lifetime": constant(1.0),
        "dieWithParticles": B(0), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
        "inheritParticleColor": B(0),
        "colorOverLifetime": gradient([(0.0, 1.0), (1.0, 1.0)], [(0.0, 1.0, 1.0, 1.0)]),
        "trailType": "ARA_TRAIL",
        "araConfig": {
            # `section` and `physicsSetting` are LDLib2 ToggleGroups whose deserializeNBT
            # reads `_enable` FIRST and short-circuits — without the flag the whole
            # physics block is silently dropped (A4/A8 `ara_toggles_on`). `section` stays
            # OUT entirely: cross-section tubes are broken in 2.1.5, hence the stack.
            "thickness": F(thickness), "smoothness": I(smoothness),
            "minDistance": F(0.05), "timeInterval": F(0.04),
            "alignment": "View", "space": "World", "sorting": "NewerOnTop",
            "textureMode": "Stretch", "highQualityCorners": B(0),
            "thicknessOverLength": _thread_taper(),
            "colorOverLength": color_over_length,
            "physicsSetting": {
                "_enable": B(1),
                "warmup": F(0.0),
                "gravity": L([F(0.0), F(physics["gravity"]), F(0.0)]),
                "inertia": F(physics["inertia"]),
                "velocitySmoothing": F(physics["velocity_smoothing"]),
                "damping": F(physics["damping"])},
            "renderer": ribbon_renderer(
                texture_material(TEX_CIRCLE, hdr=hdr(*hdr_rgb), blend=BLEND_ADDITIVE))}}


def _thread_carrier(fx, name, ribbon, travel_ticks):
    """A near-invisible particle whose only job is to drag one ribbon layer home.

    Born at the grave end of the span and pushed down local −Z at exactly
    THREAD_SPAN / travel blocks per second. The cone shape fountains +Y, so the emitter is
    pivoted −90 deg about X to aim it at local −Z: Photon feeds transform rotations through
    JOML's right-handed `rotationXYZ`, whose Rx(θ) maps (0,1,0) to (0, cos θ, sin θ), so
    θ = −90 is the one that lands on −Z (the ferryman2 / wave13_cutscene convention; the
    `-90 -> +Z` comment in wandfx2 has the sign backwards). Direction is taken from the
    SHAPE and not from `velocityOverLifetime.linear` on purpose: the executor's aim
    rotation turns the shape with it, while a linear vector is a world-space bearing that
    would ignore the aim entirely and send every thread the same way.
    """
    speed = THREAD_SPAN / travel_ticks * 20.0  # blocks per SECOND
    return (fx.particle_emitter(
                name,
                duration=THREAD_DURATION, looping=False,
                start_lifetime=constant(travel_ticks), start_speed=constant(speed),
                start_size=nf3(0.02), simulation_space="World",
                max_particles=6)
            .at(0.0, 0.0, THREAD_SPAN).rotated(-90.0, 0.0, 0.0)
            .with_emission(rate=constant(THREAD_CONCURRENT / travel_ticks))
            .with_shape(cone(angle=0.6, radius=0.05))
            # The ribbon is the show, not the carrier: alpha 0x10 keeps the head from
            # reading as a bead running down the thread.
            .with_material(texture_material(TEX_CIRCLE, hdr=(0.0, 0.0, 0.0),
                                            blend=BLEND_ADDITIVE))
            .with_renderer(vertex_sorting="NONE")
            .with_curves(color_over_lifetime=gradient(
                [(0.0, 0.06), (1.0, 0.0)], [(0.0,) + SAC_VIOLET]))
            .with_module("trails", ribbon))


def build_revive_soul_thread(stage: int) -> FxBuilder:
    """Stage 1 (slack) .. 3 (locked). `taut` drives every knob in this file."""
    taut = (stage - 1) / 2.0
    fx = FxBuilder(f"revive_soul_thread_{stage}")
    travel = int(round(lerp(36.0, 20.0, taut)))

    def physics(g_slack, g_taut, i_slack, i_taut, d_slack, d_taut, smooth):
        return dict(gravity=lerp(g_slack, g_taut, taut),
                    inertia=lerp(i_slack, i_taut, taut),
                    damping=lerp(d_slack, d_taut, taut),
                    velocity_smoothing=smooth)

    # Layer 1 — the veil. Fat, dim, the saggiest: this is the halo that gives the thread
    # a body at 20 blocks and the layer that visibly stops hanging as the ritual runs.
    _thread_carrier(fx, "thread_veil", _thread_ribbon(
        thickness=lerp(0.30, 0.22, taut), smoothness=3,
        color_over_length=gradient(
            [(0.0, lerp(0.16, 0.30, taut)), (0.35, lerp(0.11, 0.22, taut)),
             (0.8, lerp(0.03, 0.08, taut)), (1.0, 0.0)],
            [(0.0,) + SAC_VIOLET, (0.45,) + SAC_DEEP, (1.0,) + SAC_VOID]),
        hdr_rgb=(0.4, 0.26, 0.78),
        physics=physics(-2.2, -0.35, 0.60, 0.12, 0.92, 0.35, lerp(0.55, 0.85, taut))
    ), travel)

    # Layer 2 — the core. THE string: the line the eye actually follows.
    _thread_carrier(fx, "thread_core", _thread_ribbon(
        thickness=lerp(0.095, 0.075, taut), smoothness=5,
        color_over_length=gradient(
            [(0.0, lerp(0.55, 0.95, taut)), (0.3, lerp(0.4, 0.8, taut)),
             (0.75, lerp(0.14, 0.34, taut)), (1.0, 0.0)],
            [(0.0,) + SAC_HOT, (0.3,) + SAC_VIOLET, (0.75,) + SAC_DEEP, (1.0,) + SAC_VOID]),
        hdr_rgb=(0.95, 0.78, 1.4),
        physics=physics(-1.1, -0.10, 0.40, 0.04, 0.88, 0.15, lerp(0.6, 0.88, taut))
    ), travel)

    # Layer 3 — the current. A hairline of white running INSIDE the core; at stage 1 it
    # is a flicker, at stage 3 it is a live wire.
    _thread_carrier(fx, "thread_spark", _thread_ribbon(
        thickness=lerp(0.035, 0.05, taut), smoothness=4,
        color_over_length=gradient(
            [(0.0, lerp(0.3, 0.9, taut)), (0.42, lerp(0.16, 0.6, taut)), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.5,) + SAC_HOT, (1.0,) + SAC_VIOLET]),
        hdr_rgb=(1.45, 1.4, 1.45),
        physics=physics(-0.6, 0.0, 0.30, 0.0, 0.80, 0.0, lerp(0.65, 0.9, taut))
    ), travel)

    # The flow. Motes born ALONG the whole span (function shape: z = randomA × span, so
    # the density is uniform over the thread instead of beading at the ends) and pulled
    # to the sigil. This is where colorBySpeed earns its keep: at stage 1 the motes
    # crawl at ~5 b/s and read as dim violet embers on a slack rope; at stage 3 they run
    # at ~16 b/s and the same ramp turns them white — the thread does not just LOOK
    # tighter, the light in it visibly speeds up.
    mote_speed = lerp(5.0, 16.0, taut)
    (fx.particle_emitter(
            "thread_motes",
            duration=THREAD_DURATION, looping=False,
            start_lifetime=random_between(10, 24),
            start_speed=random_between(mote_speed * 0.75, mote_speed),
            start_size=nf3(random_between(0.045, 0.1)),
            simulation_space="World", max_particles=int(round(lerp(16, 30, taut))))
       .with_emission(rate=constant(lerp(0.5, 1.3, taut)))
       .with_shape(function_shape(
            x="0.13*(randomB - 0.5)",
            y="0.13*(randomC - 0.5)",
            z=f"{THREAD_SPAN}*randomA",
            # Direction only — `Function.nextPosVel` normalises and startSpeed carries
            # the magnitude. Homeward down −Z with a breath of scatter.
            speed_x="0.22*(randomD - 0.5)", speed_y="0.22*(randomE - 0.5)",
            speed_z="-1.0"))
       .with_material(texture_material(TEX_CIRCLE, hdr=hdr(0.95, 0.8, 1.4),
                                       blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", length_scale=2.0,
                      velocity_scale=0.4, vertex_sorting="NONE")
       .with_module("colorBySpeed", color_by_speed(COOL_SACRED, HOT_WHITE, 3.0, 18.0))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, lerp(0.55, 0.95, taut)), (0.7, 0.4), (1.0, 0.0)],
                [(0.0,) + SAC_BIRTH, (0.2,) + SAC_HOT, (0.6,) + SAC_VIOLET,
                 (1.0,) + SAC_VOID],
                [(0.0,) + SAC_BIRTH, (0.24,) + SAC_VIOLET, (0.65,) + SAC_DEEP,
                 (1.0,) + SAC_VOID]),
            size_over_lifetime=sz(0.35, 1.0, SEG_SHRINK))
       .with_lights(sky=15, block=15))

    # Arrival. From stage 2 on, the sigil end answers: a small glint pops where the
    # thread lands, so the ritual reads as RECEIVING something rather than just glowing.
    if stage >= 2:
        (fx.particle_emitter(
                "sigil_catch",
                duration=THREAD_DURATION, looping=False,
                start_lifetime=random_between(6, 12),
                start_speed=random_between(0.6, 2.2),
                start_size=nf3(random_between(0.06, 0.13)),
                simulation_space="World", max_particles=12)
           .at(0.0, 0.0, 0.15)
           .with_emission(rate=constant(lerp(0.0, 0.55, taut) + 0.25))
           .with_shape(sphere(radius=0.22, thickness=1.0))
           .with_material(texture_material(TEX_CIRCLE, hdr=hdr(1.1, 0.95, 1.45),
                                           blend=BLEND_ADDITIVE))
           .with_renderer(vertex_sorting="NONE")
           .with_curves(
                color_over_lifetime=varied(
                    [(0.0, 0.0), (0.14, 0.9), (1.0, 0.0)],
                    [(0.0,) + SAC_BIRTH, (0.3,) + SAC_HOT, (1.0,) + SAC_VIOLET],
                    [(0.0,) + SAC_BIRTH, (0.3,) + SAC_GOLD_PALE, (1.0,) + SAC_VIOLET]),
                size_over_lifetime=sz(0.25, 1.0, SEG_SHRINK))
           .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# main — write + validate every asset (+ the binary-diff law's .fxproj sibling)
# ---------------------------------------------------------------------------
BUILDERS = {
    "dawn_toll_bloom.fx": build_dawn_toll_bloom,
    "dawn_toll_rift.fx": build_dawn_toll_rift,
    "rebirth_starfall.fx": build_rebirth_starfall,
    "offering_gutter.fx": build_offering_gutter,
    "ghost_soul_departure.fx": build_ghost_soul_departure,
    "revive_thunderbloom.fx": build_revive_thunderbloom,
    "revive_soul_thread_1.fx": lambda: build_revive_soul_thread(1),
    "revive_soul_thread_2.fx": lambda: build_revive_soul_thread(2),
    "revive_soul_thread_3.fx": lambda: build_revive_soul_thread(3),
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
            print(f"FAIL {path}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B)"
                  " — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
