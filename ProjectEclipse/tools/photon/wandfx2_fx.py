#!/usr/bin/env python3
"""wandfx2_fx — F-070 wand spell VISUAL OVERHAUL Photon `.fx` assets (third wave).

Completes the per-spell three-phase FX contract (muzzle -> trail/channel -> impact)
for the 30-spell F-039 ladder. Everything here is LAYER garnish over the photon-less
Quasar/vanilla baseline composed server-side in `wand/WandSpellEffects`/`wand/WandPowers`;
rows live in the NEW registrar `client/wand/WandFx2PhotonRows`, cue ids at the END of
`network/fx/FxCues` (CUE_WANDFX2_*). The six F-038/F-039 highlight assets from
`wand2_fx.py` stay untouched — this wave fills the gaps around them.

F-070 PATH VISUAL IDENTITY (mirrored in the WandSpells javadoc — keep in sync):
  RISS  — void/glitch. Deep violet -> glitch cyan/magenta, hot white-cyan accents.
          Form language: SHARP/crystalline — hard stretched streaks, glitch squares,
          implosion snaps; motion is INWARD (negative radial, orbital drag).
  GLUT  — ember/magma. White-gold core -> amber -> deep red, ash gray shadow.
          Form language: FLOWING/billowing — rising embers, heat columns, smoke,
          physics debris; motion is UPWARD + OUTWARD (gravity, bounces).
  STERN — starlight/marks. Ice white/star cyan with pale gold. Form language:
          RADIANT/geometric — 4-point stars, rings, beams, domes; motion is
          DOWNWARD from the sky + slow ORBITS, always twinkling.

WAVE-13 A1 MOVEMENT PACKAGE (this pass) — the four motion capabilities from
`docs/plans_v3/PHOTON_EDITOR_CAPABILITIES.md` §5, wired with the NBT field names verified
against `run/mods/photon-neoforge-1.21.1-2.1.5.jar` (javap):

  `emission.distanceRate`  EmissionSetting.distanceRate — getEmissionCount() adds
                           floor(accumulatedDistance / distanceRate) particles, so the
                           value is BLOCKS PER PARTICLE (smaller = denser) and
                           accumulatedDistance grows by |emitter velocity| per tick.
                           Only bites where the EXECUTOR moves: the entity-lane assets
                           (echo_blade / guardian / bless) and the muzzles, which
                           `WandFx2PhotonRows` now rides on the casting player.
  `inheritVelocity`        InheritVelocitySetting{mode: CURRENT|INITIAL, multiply: NF}.
                           TileParticle.getRealVelocity() adds emitterVelocity*multiply in
                           WORLD space every tick. On a World-space emitter a POSITIVE
                           multiply carries the particle along with the caster (wake); on
                           a Local-space emitter the particle already rides the transform,
                           so a NEGATIVE multiply is the drag/lag knob there.
  `colorBySpeed`           ColorBySpeedSetting{color: NF, speedRange: Range}. The input is
                           |getRealVelocity()| * 20, i.e. BLOCKS PER SECOND, and the result
                           MULTIPLIES the lifetime color — hence every ramp here ends at
                           white and only cools the slow end. NOTE: `Range` serialises
                           through `Range.CODEC`, whose record fields are `a`/`b` — NOT the
                           `min`/`max` pair `fxlib._min_max` writes — so colorBySpeed is
                           attached via `with_module` (fxlib belongs to team A0).
  `random_gradient`        Two gradient ramps, lerped per particle off the memoized
                           TileParticle roll — no two casts (and no two particles) read
                           identical any more.

The same pass retunes the `velocityOverLifetime` magnitudes, which were authored an order
of magnitude below the perception floor: Photon scales `linear` by 0.05 and `radial` by
0.01 per tick, so a `linear` unit is ~1 block/s but a `radial` unit is only 0.2 block/s —
the old radial "inhales" moved ~0.1 block over their whole life. HDR is capped at the
wave-13 stacking ceiling (`HDR_CEILING`, hue ratio preserved).

Assets (all one-shots, no loops; maxParticles explicit; HDR <= 1.45; house curves):

  wandfx2_muzzle_riss / _glut / _stern   Phase-1 cast flash at the wand hand, fired on
                                         EVERY successful cast (CUE_WANDFX2_MUZZLE,
                                         a = path id, b = tier — the row tier-scales the
                                         executor so T5 casts flare visibly bigger).
  wandfx2_glut_comet                     Feuerball flight comet: streak bundle + head
                                         flare flying along local +Z; the row rotates
                                         the executor onto the cast ray (heart-theft
                                         +Z-aim convention). Baked to the shipped
                                         speed/range defaults (1.4 b/t, 28 blocks).
  wandfx2_glut_burst                     Shared GLUT detonation payoff (Feuerball
                                         impact, Eruptionslinie steps, Flammenfächer
                                         mid-arc) — core pop, ember physics debris
                                         chaining the shipped glut children, fire ring.
  wandfx2_glut_aschesturm                Aschesturm channel zone: billowing ash bank
                                         (noise + remap gusts), ember swirl, dim coals.
  wandfx2_riss_well                      Gravitationsbrunnen channel well —
                                         orbital streak disc + infall motes + dark core
                                         (the event-horizon's smaller sibling, ~80t).
  wandfx2_riss_maelstrom                 Leerensog/Zugfeld/Schattenriss void crunch:
                                         one fast inhale -> HDR bite -> glitch shards.
  wandfx2_riss_echo_blade                Echoklinge sweep: one horizontal blade ring +
                                         streak arc around the caster (entity lane,
                                         re-sent per beat with allowMulti).
  wandfx2_stern_seal                     Wurzelgriff/Sternenbann binding seal: ground
                                         ring + orbiting glyph stars + root filaments.
  wandfx2_stern_guardian                 Nova-Wächter guardian: one bright orbiting
                                         star + twinkle dust riding the caster ~120t
                                         (entity lane; strikes stay the Quasar beats).
  wandfx2_stern_bless                    Lichtsegen blessing: descending light shafts
                                         + star-mote rain + soft dome on the caster.

Run:  python3 tools/photon/wandfx2_fx.py          # writes + validates all 12 assets
(write() round-trip-validates; every .fx gets its .fxproj sibling — binary-diff law.)
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

# --- palette anchors (path identity — see module docstring) ------------------------
RISS_DEEP = 0xFF7B4FD0     # SAC_DEEP violet
RISS_VIOLET = 0xFFB98CFF   # SAC_VIOLET (HUD tint)
RISS_CYAN = 0xFF4FE8FF     # GLI_CYAN
RISS_MAGENTA = 0xFFFF4FD8  # GLI_MAGENTA
GLUT_GOLD = 0xFFFFE9A8     # white-gold core
GLUT_AMBER = 0xFFFFC873    # warm amber
GLUT_EMBER = 0xFFFF7B3C    # ERA_EMBER (HUD tint family)
STERN_WHITE = 0xFFF2F6FF   # ice white
STERN_CYAN = 0xFF7FE7FF    # star cyan (HUD tint)
STERN_GOLD = 0xFFF7E3B0    # pale gold

# --- wave-13 movement package ------------------------------------------------------
#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4) — many ALPHA/ADDITIVE sprites inside
#: one half-block converge to white above this, so every material here is clamped to it.
HDR_CEILING = 1.45

#: colorBySpeed cool ends (per path) and hot ends. The module MULTIPLIES the lifetime
#: color, so the hot end must stay at/near white or fast particles simply go dark.
COOL_RISS = (0.55, 0.42, 0.85)    # slow = deep violet drag
COOL_GLUT = (0.85, 0.34, 0.10)    # slow = cooled ember
COOL_STERN = (0.56, 0.70, 0.94)   # slow = dim star blue
HOT_WHITE = (1.0, 1.0, 1.0)
HOT_CYAN = (0.86, 1.0, 1.0)
HOT_GOLD = (1.0, 0.96, 0.80)

# --- sync contracts (keep in step with the Java side) ------------------------------
# WandSpells glut.feuerball defaults: speed 1.4 b/t over range 28 -> <=20 flight ticks.
COMET_SPEED = 1.4
COMET_FLIGHT_TICKS = 20
# WandSpells riss.gravitationsbrunnen "durationTicks" default — the well window.
WELL_WINDOW = 80
# WandSpells stern.novawaechter "durationTicks" default — the guardian orbit window.
GUARDIAN_WINDOW = 120
# WandSpells glut.aschesturm "durationTicks" default — the ash-bank window.
ASH_WINDOW = 60

# The 2x2 star-sheet twinkle track (the wand2_fx / wand_idle_stern house pattern).
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


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def inherit_velocity(multiply, mode="CURRENT"):
    """`inheritVelocity` module body — InheritVelocitySetting{mode, multiply}.

    CURRENT re-reads the emitter velocity every tick (INITIAL freezes it at birth).
    Positive multiply on a World-space emitter = the particle rides the caster's wake;
    negative multiply on a Local-space emitter = drag, the particle lags the transform
    it is already glued to.
    """
    return {"mode": mode, "multiply": constant(float(multiply))}


def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` module body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/second (|realVelocity| * 20), output MULTIPLIES the lifetime color.
    `speedRange` is an LDLib2 `Range`, whose codec fields are `a`/`b`.
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same path
    identity; each particle rolls its own memoized lerp between the two."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def flash(fx, root, name, size, bloom, lifetime=8, delay=0):
    """One single-frame HDR bloom pop — the shared 'money tick' primitive.
    `bloom` is the authored HDR triple; it is clamped to the stacking ceiling here."""
    emitter = (fx.particle_emitter(name,
            duration=max(20, lifetime + delay + 2), looping=False,
            start_delay=constant(delay), start_lifetime=constant(lifetime),
            start_speed=constant(0), start_size=nf3(size),
            simulation_space="Local", max_particles=4)
        .child_of(root)
        .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
        .with_shape(dot())
        .with_material(texture_material(CIRCLE, hdr=hdr(*bloom), blend=BLEND_ADDITIVE))
        .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
        .with_lights(sky=15, block=15))
    return emitter


# ===========================================================================
# Phase 1 — the three per-path MUZZLE flashes (tier-scaled by the row)
# ===========================================================================
def build_muzzle_riss() -> FxBuilder:
    """RISS cast flash: a razor inhale of violet-cyan streaks snapping INTO the hand,
    one glitch-square blink, one small hot pop. Sharp, fast, inward.

    A1: the streaks now live in WORLD space and inherit 45 % of the caster's motion, so a
    strafing cast smears them into a wake instead of teleporting them with the hand;
    `distanceRate` adds one extra streak per half block the hand travels."""
    fx = FxBuilder("wandfx2_muzzle_riss")
    root = fx.empty("muzzle")

    # Inward streaks: born on a small shell, sucked into the birth point of the cast.
    # Radial retuned -0.9 -> -18: the old value was 0.18 block/s, i.e. ~0.05 block of
    # travel over the whole 4-6t life on a 0.9 shell (the "inhale" never moved).
    (fx.particle_emitter("inhale",
            duration=14, looping=False, start_lifetime=random_between(4, 6),
            start_speed=constant(0),
            start_size=rand_size3(0.04, 0.09),
            start_color=random_color(RISS_DEEP, RISS_CYAN),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), distance_rate=constant(0.5),
                      bursts=[burst(time=0, count=constant(14))])
       .with_shape(sphere(radius=0.9, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.2, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.0)
       .with_module("inheritVelocity", inherit_velocity(0.45))
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.0, 8.0))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-18.0)),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 1.0), (1.0, 0.4)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.78, 0.62, 1.0), (1.0, 0.45, 0.92, 1.0)]))
       .with_lights(sky=15, block=15))

    # Glitch blink: 3 squares flicker around the hand for a frame or two. Stays LOCAL —
    # the blink has to read as pinned to the wand, not as debris.
    (fx.particle_emitter("glitch_blink",
            duration=14, looping=False, start_lifetime=random_between(3, 5),
            start_speed=constant(0), start_size=rand_size3(0.05, 0.1),
            start_color=random_color(RISS_CYAN, RISS_MAGENTA),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(3)),
                                                  burst(time=3, count=constant(2))])
       .with_shape(sphere(radius=0.35, thickness=0.0))
       .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.0, 1.3, 1.4), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            color_over_lifetime=varied([(0.0, 1.0), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 1.0, 0.55, 0.92), (1.0, 0.5, 0.95, 1.0)])))

    flash(fx, root, "pop", 0.55, (1.3, 1.8, 2.2), lifetime=6, delay=2)
    return fx


def build_muzzle_glut() -> FxBuilder:
    """GLUT cast flash: a compressed ember whoosh rolling off the hand — cone spray with
    gravity, one heat puff, one white-gold pop. Flowing, warm, outward.

    A1: the spray inherits 55 % of the caster's motion (embers get BLOWN off a running
    caster) and `distanceRate` thickens it with travel; `colorBySpeed` keeps the launch
    sparks white-hot and lets the ones that lose their speed sag into deep red."""
    fx = FxBuilder("wandfx2_muzzle_glut")
    root = fx.empty("muzzle")

    # Ember spray: short-lived sparks fountaining out of the hand, falling.
    (fx.particle_emitter("ember_spray",
            duration=16, looping=False, start_lifetime=random_between(5, 9),
            start_speed=random_between(0.25, 0.5),
            start_size=rand_size3(0.03, 0.07),
            start_color=random_color(GLUT_GOLD, GLUT_EMBER),
            simulation_space="World", max_particles=36)
       .child_of(root)
       .with_emission(rate=constant(0.0), distance_rate=constant(0.5),
                      bursts=[burst(time=0, count=constant(16)),
                              burst(time=2, count=constant(8))])
       .with_shape(cone(angle=32.0, radius=0.12))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 0.8, 0.25), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.22, bounce_chance=0.0)
       .with_module("inheritVelocity", inherit_velocity(0.55))
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 3.0, 13.0))
       .with_curves(
            color_over_lifetime=varied(  # white-hot -> amber -> deep red -> out
                [(0.0, 1.0), (0.7, 0.75), (1.0, 0.0)],
                [(0.0, 1.0, 0.92, 0.7), (0.5, 1.0, 0.55, 0.2), (1.0, 0.45, 0.1, 0.03)],
                [(0.0, 1.0, 0.78, 0.42), (0.5, 0.95, 0.4, 0.11), (1.0, 0.34, 0.07, 0.02)]))
       .with_lights(sky=15, block=15))

    # Heat puff: one soft alpha smoke breath so the flash has body, not just light.
    (fx.particle_emitter("heat_puff",
            duration=16, looping=False, start_lifetime=constant(11),
            start_speed=constant(0.06), start_size=nf3(0.5),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=1, count=constant(2))])
       .with_shape(sphere(radius=0.15, thickness=1.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.2, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.35), (1.0, 0.0)],
                [(0.0, 0.5, 0.34, 0.22), (1.0, 0.2, 0.12, 0.08)],
                [(0.0, 0.38, 0.3, 0.28), (1.0, 0.14, 0.11, 0.11)])))

    flash(fx, root, "pop", 0.6, (2.0, 1.3, 0.4), lifetime=7, delay=1)
    return fx


def build_muzzle_stern() -> FxBuilder:
    """STERN cast flash: a small star ring blooming out of the hand + twinkle motes
    rising, one ice-white pop. Radiant, geometric, upward.

    A1: the motes are World-space now and keep 40 % of the caster's motion, so they hang
    in the air behind a moving caster and keep CLIMBING — the lift was retuned from
    0.05-0.12 (= 0.05-0.12 block/s, invisible) to a readable 0.8-1.6 block/s."""
    fx = FxBuilder("wandfx2_muzzle_stern")
    root = fx.empty("muzzle")

    # Star motes: real 4-point stars lifting off the hand, twinkling out.
    (fx.particle_emitter("star_motes",
            duration=18, looping=False, start_lifetime=random_between(7, 12),
            start_speed=random_between(0.08, 0.18),
            start_size=rand_size3(0.04, 0.08),
            simulation_space="World", max_particles=28)
       .child_of(root)
       .with_emission(rate=constant(0.0), distance_rate=constant(0.5),
                      bursts=[burst(time=0, count=constant(12))])
       .with_shape(cone(angle=40.0, radius=0.15))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.1, 1.6), blend=BLEND_ADDITIVE))
       .with_module("inheritVelocity", inherit_velocity(0.4))
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 1.0, 6.0))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.8, 1.6), constant(0))),
            size_over_lifetime=curve(0.35, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.95, 0.96, 1.0), (1.0, 0.97, 0.89, 0.69)],
                [(0.0, 0.78, 0.93, 1.0), (1.0, 0.85, 0.93, 1.0)]))
       .with_lights(sky=15, block=15))

    # Hand halo ring: one soft annulus blooming to ~1 block and gone.
    (fx.particle_emitter("halo_ring",
            duration=18, looping=False, start_lifetime=constant(9), start_speed=constant(0),
            start_size=nf3(0.3), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.0, 1.1, 1.7), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(
                0.3, 1.1, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=varied([(0.0, 0.8), (1.0, 0.0)],
                                       [(0.0, 0.85, 0.9, 1.0)],
                                       [(0.0, 0.97, 0.93, 0.78)])))

    flash(fx, root, "pop", 0.5, (1.4, 1.5, 2.2), lifetime=6, delay=1)
    return fx


# ===========================================================================
# GLUT — Feuerball comet (phase 2) + shared detonation (phase 3) + Aschesturm
# ===========================================================================
def build_glut_comet() -> FxBuilder:
    """Feuerball flight: an ember streak bundle + head flare flying along local +Z at
    the shipped projectile speed. The row rotates the executor onto the cast ray
    (server pre-computes the X/Y Euler pair, the heart-theft +Z-aim convention); the
    vanilla FLAME march in WandSpellEffects stays the photon-less trail baseline.

    A1 note: `CUE_WANDFX2_GLUT_COMET` is a POSITION cue (WandSpellEffects sends the cast
    origin — the feuerball is a server-side ballistic trace, not an entity), so the
    executor never moves and `distanceRate`/`inheritVelocity` would both be no-ops here.
    What the comet does get is the set's best `colorBySpeed` showcase: the streaks leave
    at ~28 block/s white-hot, and `cinder_wake`'s speedModifier decay drags the shed
    cinders down to ~1 block/s, so they visibly cool from white through amber to red."""
    fx = FxBuilder("wandfx2_glut_comet")
    root = fx.empty("comet")

    # Streak bundle: tight cone of stretched embers launched down +Z, fading with range.
    (fx.particle_emitter("flight_streaks",
            duration=COMET_FLIGHT_TICKS + 4, looping=False,
            start_lifetime=random_between(10, COMET_FLIGHT_TICKS),
            start_speed=random_between(COMET_SPEED * 0.85, COMET_SPEED),
            start_size=rand_size3(0.08, 0.16),
            start_color=random_color(GLUT_GOLD, GLUT_EMBER),
            start_rotation=nf3(constant(90.0), constant(0.0), constant(0.0)),
            simulation_space="Local", max_particles=36)
       .child_of(root)
       .rotated(-90.0, 0.0, 0.0)  # cone fountains +Y; pivot it onto local +Z
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(10)),
                                                  burst(time=2, count=constant(8)),
                                                  burst(time=4, count=constant(6))])
       .with_shape(cone(angle=1.5, radius=0.12))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 0.9, 0.3), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5, length_scale=2.6)
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 10.0, 28.0))
       .with_curves(
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 0.9, 0.65), (0.5, 1.0, 0.55, 0.2), (1.0, 0.5, 0.12, 0.04)],
                [(0.0, 1.0, 0.75, 0.38), (0.5, 0.94, 0.38, 0.1), (1.0, 0.36, 0.08, 0.02)]))
       .with_lights(sky=15, block=15))

    # Falling cinders shed along the flight line (world space, so they hang behind).
    (fx.particle_emitter("cinder_wake",
            duration=COMET_FLIGHT_TICKS + 4, looping=False,
            start_lifetime=random_between(8, 14),
            start_speed=random_between(COMET_SPEED * 0.9, COMET_SPEED),
            start_size=rand_size3(0.03, 0.06),
            simulation_space="World", max_particles=24)
       .child_of(root)
       .rotated(-90.0, 0.0, 0.0)
       .with_emission(rate=constant(0.9))
       .with_shape(cone(angle=2.0, radius=0.1))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.6, 0.18), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.1, bounce_chance=0.0)
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 2.0, 26.0))
       .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                0.05, 1.0, [SEG_SMOOTH_DOWN], "lifetime")),  # cinders stall + drop out
            color_over_lifetime=varied(
                [(0.0, 0.9), (0.6, 0.55), (1.0, 0.0)],
                [(0.0, 1.0, 0.7, 0.3), (1.0, 0.45, 0.1, 0.03)],
                [(0.0, 1.0, 0.86, 0.55), (1.0, 0.32, 0.07, 0.02)]))
       .with_lights(sky=15, block=15))

    flash(fx, root, "launch_flare", 0.7, (1.8, 1.1, 0.35), lifetime=6)
    return fx


def build_glut_burst() -> FxBuilder:
    """Shared GLUT detonation (Feuerball impact / Eruptionslinie steps / Flammenfächer):
    white-gold core pop + fire ring + physics ember debris chaining the SHIPPED glut
    children + one ash breath. Authored at radius ~3 (the feuerball default); the row
    scales the executor by the cue's live radius.

    A1: a position cue, so the movement pair stays out — but the debris is the one place
    in the set where particles both accelerate away and get STOPPED by real geometry, so
    `colorBySpeed` turns the bounce into a visible cool-down from white-gold to coal."""
    fx = FxBuilder("wandfx2_glut_burst")
    root = fx.empty("burst")

    flash(fx, root, "core_pop", 1.6, (2.2, 1.5, 0.5), lifetime=9)

    # Ground fire ring rolling out to the AoE edge (~3 blocks authored).
    (fx.particle_emitter("fire_ring",
            duration=30, looping=False, start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(0.8), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.5, 0.9, 0.3), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.4, 6.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=varied([(0.0, 0.85), (1.0, 0.0)],
                                       [(0.0, 1.0, 0.8, 0.45)],
                                       [(0.0, 1.0, 0.58, 0.22)])))

    # Ember debris: physics chunks bouncing away, chaining the shipped glut children.
    (fx.particle_emitter("ember_debris",
            duration=30, looping=False, start_lifetime=random_between(14, 24),
            start_speed=random_between(0.4, 0.85),
            start_size=rand_size3(0.06, 0.13),
            start_color=random_color(GLUT_GOLD, GLUT_EMBER),
            simulation_space="World", max_particles=26)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(18))])
       .with_shape(sphere(radius=0.4, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.5, 0.9, 0.3), blend=BLEND_ADDITIVE))
       .with_physics(collision=True, friction=0.98, collided_friction=0.6, gravity=0.38,
                     bounce_chance=0.55, bounce_rate=0.4, bounce_spread=0.12)
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 1.5, 16.0))
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (0.7, 0.8), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.72), (0.45, 1.0, 0.55, 0.2), (1.0, 0.45, 0.12, 0.04)],
            [(0.0, 1.0, 0.8, 0.44), (0.45, 0.94, 0.38, 0.11), (1.0, 0.33, 0.08, 0.02)]))
       .with_sub_emitters(
            sub_emitter("eclipse:glut_splash", event="Collision", probability=0.35),
            sub_emitter("eclipse:glut_ember_die", event="Death", probability=0.25))
       .with_lights(sky=15, block=15))

    # Ash breath so the payoff decays instead of cutting (identity: GLUT leaves residue).
    (fx.particle_emitter("ash_breath",
            duration=30, looping=False, start_delay=constant(3), start_lifetime=constant(20),
            start_speed=random_between(0.04, 0.09), start_size=rand_size3(0.4, 0.7),
            simulation_space="Local", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(sphere(radius=0.6, thickness=1.0))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.4), (1.0, 0.0)],
                [(0.0, 0.32, 0.24, 0.2), (1.0, 0.12, 0.09, 0.08)],
                [(0.0, 0.24, 0.21, 0.22), (1.0, 0.08, 0.07, 0.09)])))
    return fx


def build_glut_aschesturm() -> FxBuilder:
    """Aschesturm channel zone (~60t): a billowing dark ash bank rolling around the
    zone (noise with a REMAP gust curve — PHOTON_EDITOR_CAPABILITIES idea 17), a lazy
    ember swirl inside it and dim coals glowing at the floor. Authored radius ~6.

    A1: a position cue again, so the lift values carry the movement work — the bank rose
    at 0.02-0.06 block/s and the embers at 0.04-0.1, i.e. under a block over the whole
    60t window. Retuned to 0.35-0.8 and 0.8-1.8 block/s so the carousel actually
    BILLOWS; `colorBySpeed` makes the embers that catch the gust flare."""
    fx = FxBuilder("wandfx2_glut_aschesturm")
    root = fx.empty("aschesturm")

    # The ash bank: large alpha smoke bodies drifting in a slow gusty carousel.
    (fx.particle_emitter("ash_bank",
            duration=ASH_WINDOW, looping=False, start_lifetime=random_between(24, 38),
            start_speed=constant(0.03),
            start_size=rand_size3(1.2, 2.2),
            simulation_space="Local", max_particles=44)
       .child_of(root)
       .with_emission(rate=constant(1.3))
       .with_shape(cylinder(radius=5.0, thickness=0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.35), constant(0)),
                linear=nf3(constant(0), random_between(0.35, 0.8), constant(0))),
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.1), constant(0.03), constant(0.1)),
                       rotation=constant(0), size=constant(0),
                       remap=curve(0.0, 1.0, [SEG_FLICKER_COMMIT], "value")),
            size_over_lifetime=curve(0.7, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.5), (0.8, 0.35), (1.0, 0.0)],
                [(0.0, 0.2, 0.15, 0.13), (1.0, 0.1, 0.07, 0.06)],
                [(0.0, 0.26, 0.19, 0.14), (1.0, 0.07, 0.06, 0.07)])))

    # Ember swirl: sparse hot flecks circling through the bank.
    (fx.particle_emitter("ember_swirl",
            duration=ASH_WINDOW, looping=False, start_lifetime=random_between(16, 26),
            start_speed=constant(0.02),
            start_size=rand_size3(0.04, 0.08),
            start_color=random_color(GLUT_AMBER, GLUT_EMBER),
            simulation_space="Local", max_particles=40)
       .child_of(root)
       .with_emission(rate=constant(1.8))
       .with_shape(cylinder(radius=4.5, thickness=0.8))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 0.65, 0.2), blend=BLEND_ADDITIVE))
       .with_module("colorBySpeed", color_by_speed(COOL_GLUT, HOT_GOLD, 0.5, 3.5))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.55), constant(0)),
                linear=nf3(constant(0), random_between(0.8, 1.8), constant(0))),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 1.0), (0.8, 0.5), (1.0, 0.0)],
                [(0.0, 1.0, 0.7, 0.3), (1.0, 0.5, 0.14, 0.04)],
                [(0.0, 1.0, 0.52, 0.16), (1.0, 0.38, 0.09, 0.03)]))
       .with_lights(sky=15, block=15))

    # Floor coals: near-static dim glows breathing at ankle height.
    (fx.particle_emitter("floor_coals",
            duration=ASH_WINDOW, looping=False, start_lifetime=random_between(20, 32),
            start_speed=constant(0), start_size=rand_size3(0.1, 0.2),
            simulation_space="Local", max_particles=20)
       .child_of(root)
       .at(0.0, -0.3, 0.0)
       .with_emission(rate=constant(0.7))
       .with_shape(circle(radius=4.5, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 0.5, 0.15), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(  # double-hump breathing
                0.4, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                [(0.0, 1.0, 0.55, 0.2), (1.0, 0.55, 0.15, 0.05)],
                [(0.0, 0.86, 0.32, 0.09), (1.0, 0.4, 0.1, 0.03)]))
       .with_lights(sky=15, block=15))
    return fx


# ===========================================================================
# RISS — channel well (phase 2) + violent crunch + echo blade (phase 2/3)
# ===========================================================================
def build_riss_well() -> FxBuilder:
    """Gravitationsbrunnen gravity well (~80t): the event-horizon's smaller
    sibling — orbital streak disc bleeding inward, infall motes, one dark core swirl.
    Authored radius ~5; the row scales by the cue's live radius.

    A1: the well now actually falls IN. The old radial values (-0.22 / -0.42 = 0.04 /
    0.08 block/s) moved a mote ~0.05 block over its whole life, so the disc read as a
    static ring; the accretion radial is a CURVE that plunges from 1.2 to 7 block/s over
    the particle's life (the real accretion read — slow drift at the rim, a snap at the
    horizon) and `colorBySpeed` makes exactly that plunge glow."""
    fx = FxBuilder("wandfx2_riss_well")
    root = fx.empty("well")

    (fx.particle_emitter("accretion",
            duration=WELL_WINDOW, looping=False,
            start_lifetime=random_between(16, 24), start_speed=constant(0),
            start_size=rand_size3(0.07, 0.14),
            start_color=random_color(RISS_VIOLET, RISS_CYAN),
            simulation_space="Local", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(1.4))
       .with_shape(circle(radius=4.5, thickness=0.15))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.1, 1.4), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.2)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.0, 9.0))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(1.3), constant(0)),
                radial=curve(-35.0, -6.0, [SEG_SMOOTH_DOWN], "lifetime")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.9), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.74, 0.58, 1.0), (1.0, 0.42, 0.91, 1.0)]))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("infall_motes",
            duration=WELL_WINDOW, looping=False, start_lifetime=constant(11),
            start_speed=constant(0), start_size=rand_size3(0.04, 0.08),
            start_color=random_color(RISS_DEEP, RISS_CYAN),
            simulation_space="Local", max_particles=36)
       .child_of(root)
       .with_emission(rate=constant(1.8))
       .with_shape(sphere(radius=4.0, thickness=0.3))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 1.0, 1.2), blend=BLEND_ADDITIVE))
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 1.5, 7.0))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-27.0)),
            color_over_lifetime=varied([(0.0, 0.0), (0.3, 0.85), (1.0, 0.1)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.66, 0.5, 1.0), (1.0, 0.5, 0.88, 1.0)])))

    # Dark core: the well's mouth — alpha-blended so it reads DARK against additive.
    (fx.particle_emitter("core_swirl",
            duration=WELL_WINDOW, looping=False, start_lifetime=constant(WELL_WINDOW - 4),
            start_speed=constant(0), start_size=nf3(1.7),
            start_color=color(0xFF2E2347),  # SAC_VOID
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(4.0)),
            size_over_lifetime=curve(0.55, 1.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.75), (0.85, 0.6), (1.0, 0.0)],
                [(0.0, 0.16, 0.12, 0.26), (1.0, 0.1, 0.07, 0.18)],
                [(0.0, 0.11, 0.09, 0.21), (1.0, 0.07, 0.05, 0.14)])))
    return fx


def build_riss_maelstrom() -> FxBuilder:
    """Leerensog / Zugfeld / Schattenriss violent void crunch (~32t): a hard inhale of streaks
    from a wide shell -> dark core swell -> HDR bite + glitch shard spray on the
    server's crunch tick (+6t, matching castLeerensog's damage schedule).

    A1: the "hard inhale" was radial -1.5 = 0.3 block/s, so the streaks crossed 0.1 of the
    4.5-block shell before dying — the crunch had no drag at all. At -55 (11 block/s) they
    cover ~3.3 blocks in their 5-8t life and arrive at the core on the bite tick, and
    `colorBySpeed` whitens them as they accelerate in."""
    fx = FxBuilder("wandfx2_riss_maelstrom")
    root = fx.empty("maelstrom")
    crunch_tick = 6  # WandSpellEffects.castLeerensog schedules the crunch at +6t

    (fx.particle_emitter("inhale",
            duration=32, looping=False, start_lifetime=random_between(5, 8),
            start_speed=constant(0),
            start_size=rand_size3(0.08, 0.18),
            start_color=random_color(RISS_DEEP, RISS_CYAN),
            simulation_space="Local", max_particles=56)
       .child_of(root)
       .with_emission(rate=constant(0.0),
                      bursts=[burst(time=0, count=constant(24)),
                              burst(time=3, count=constant(18))])
       .with_shape(sphere(radius=4.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.2, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.4)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.0, 12.0))
       .with_curves(
            velocity_over_lifetime=dict(radial=constant(-55.0)),  # the drag
            color_over_lifetime=varied([(0.0, 0.0), (0.3, 1.0), (1.0, 0.5)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.72, 0.55, 1.0), (1.0, 0.48, 0.93, 1.0)]))
       .with_lights(sky=15, block=15))

    # Void core swelling toward the crunch, snapping shut on it.
    (fx.particle_emitter("void_core",
            duration=32, looping=False, start_lifetime=constant(crunch_tick + 8),
            start_speed=constant(0), start_size=nf3(1.4),
            start_color=color(0xFF2E2347),
            simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            rotation_over_lifetime=dict(roll=constant(8.0)),
            size_over_lifetime=curve(
                0.0, 2.4, [(0.0, 0.25, 0.15, 0.95, 0.32, 1.0, 0.45, 1.0),
                           (0.45, 1.0, 0.62, 0.9, 0.85, 0.1, 1.0, 0.0)],
                "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.85), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.18, 0.14, 0.28), (1.0, 0.1, 0.07, 0.18)],
                [(0.0, 0.12, 0.1, 0.22), (1.0, 0.06, 0.05, 0.13)])))

    flash(fx, root, "bite_flash", 2.0, (1.7, 2.4, 2.8), lifetime=10, delay=crunch_tick)

    # Glitch shards spat outward by the bite (pixel squares, gravity, quick fade).
    (fx.particle_emitter("bite_shards",
            duration=32, looping=False, start_delay=constant(crunch_tick),
            start_lifetime=random_between(8, 14), start_speed=random_between(0.35, 0.8),
            start_size=rand_size3(0.05, 0.11),
            start_color=random_color(RISS_CYAN, RISS_MAGENTA),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(12))])
       .with_shape(sphere(radius=0.3, thickness=0.0))
       .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.0, 1.3, 1.4), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_physics(collision=False, gravity=0.16, bounce_chance=0.0)
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 2.0, 15.0))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            size_over_lifetime=curve(0.2, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=varied([(0.0, 1.0), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 1.0, 0.52, 0.9), (1.0, 0.48, 0.95, 1.0)])))
    return fx


def build_riss_echo_blade() -> FxBuilder:
    """Echoklinge sweep (~20t, entity lane on the caster, re-sent per beat): one thin
    horizontal blade ring snapping outward + a Loop-arc streak sweep — the phase blade
    made visible. Sharp and short so three beats read as three distinct slices.

    A1 (ENTITY lane — the executor rides the caster, so the movement pair bites here):
    `distanceRate` 0.4 packs one extra streak into every 0.4 block the caster covers, so
    slicing while sprinting draws a dense ribbon instead of a dotted line, and a NEGATIVE
    `inheritVelocity` multiply drags the streaks behind the (Local-space) blade so the arc
    smears into the direction of travel."""
    fx = FxBuilder("wandfx2_riss_echo_blade")
    root = fx.empty("echo")

    # The blade ring: razor annulus popping to the hit radius (~4.5) and gone.
    (fx.particle_emitter("blade_ring",
            duration=20, looping=False, start_lifetime=constant(8), start_speed=constant(0),
            start_size=nf3(1.0), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.2, 1.6, 2.0), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                1.0, 9.0, [(0.0, 0.0, 0.15, 0.9, 0.5, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.9), (1.0, 0.0)],
                [(0.0, 0.75, 0.9, 1.0), (1.0, 0.55, 0.4, 0.85)],
                [(0.0, 0.62, 0.55, 1.0), (1.0, 0.85, 0.45, 0.95)])))

    # Sweep streaks: emission points RACING around the circle (Loop arc) — the cut.
    # Radial retuned 0.35 -> 7 (0.07 -> 1.4 block/s): the blade now visibly widens as it
    # cuts instead of tracing a fixed 2.2-block circle.
    (fx.particle_emitter("sweep_streaks",
            duration=20, looping=False, start_lifetime=random_between(4, 7),
            start_speed=constant(0), start_size=rand_size3(0.06, 0.12),
            start_color=random_color(RISS_VIOLET, RISS_CYAN),
            simulation_space="Local", max_particles=36)
       .child_of(root)
       .with_emission(rate=constant(1.4), distance_rate=constant(0.4))
       .with_shape(circle(radius=2.2, thickness=0.1, arc_mode="Loop", arc_speed=2.5))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 1.3, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5, length_scale=2.0)
       .with_module("inheritVelocity", inherit_velocity(-0.4))
       .with_module("colorBySpeed", color_by_speed(COOL_RISS, HOT_CYAN, 1.5, 7.0))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(2.2), constant(0)),
                radial=constant(7.0)),
            color_over_lifetime=varied([(0.0, 0.0), (0.25, 1.0), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.7, 0.55, 1.0), (1.0, 0.45, 0.92, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


# ===========================================================================
# STERN — binding seal + guardian orbit + blessing (phases 2/3)
# ===========================================================================
def build_stern_seal() -> FxBuilder:
    """Wurzelgriff/Sternenbann binding seal (~50t): ground ring + counter-orbiting
    glyph stars + root filaments of light climbing out of the circle. Authored
    radius ~4.5; the row scales by the cue's live radius.

    A1: a position cue (the seal pins to the ground, by design), so the movement work is
    in the filaments — they climbed at 0.1-0.2 block/s, i.e. under 0.2 block over their
    whole life, and now climb at 1-2 block/s so the binding visibly GROWS out of the
    circle; `colorBySpeed` puts the highlight on the fastest ones."""
    fx = FxBuilder("wandfx2_stern_seal")
    root = fx.empty("seal")

    # Seal ring: one soft annulus blooming to the zone edge, holding, fading.
    (fx.particle_emitter("seal_ring",
            duration=50, looping=False, start_lifetime=constant(44), start_speed=constant(0),
            start_size=nf3(1.5), simulation_space="Local", max_particles=4)
       .child_of(root)
       .at(0.0, -0.2, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(RING_SOFT, hdr=hdr(1.0, 1.1, 1.6), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(1.5, 9.0, [SEG_OVERSHOOT_SETTLE], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.12, 0.75), (0.8, 0.45), (1.0, 0.0)],
                [(0.0, 0.85, 0.92, 1.0), (1.0, 0.97, 0.89, 0.69)],
                [(0.0, 0.72, 0.9, 1.0), (1.0, 0.92, 0.95, 0.88)])))

    # Glyph stars: 4-point stars pacing the ring rim in a slow orbit, twinkling.
    (fx.particle_emitter("glyph_stars",
            duration=50, looping=False, start_lifetime=random_between(22, 36),
            start_speed=constant(0), start_size=rand_size3(0.08, 0.14),
            simulation_space="Local", max_particles=28)
       .child_of(root)
       .with_emission(rate=constant(0.4), bursts=[burst(time=0, count=constant(12))])
       .with_shape(circle(radius=4.0, thickness=0.1))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.1, 1.6), blend=BLEND_ADDITIVE))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.4), constant(0))),
            size_over_lifetime=curve(  # double-hump twinkle
                0.35, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                            (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 0.95, 0.96, 1.0), (1.0, 0.97, 0.89, 0.69)],
                [(0.0, 0.76, 0.92, 1.0), (1.0, 1.0, 0.94, 0.8)]))
       .with_lights(sky=15, block=15))

    # Root filaments: thin light lines climbing out of the seal — the binding itself.
    (fx.particle_emitter("root_filaments",
            duration=50, looping=False, start_lifetime=random_between(10, 16),
            start_speed=random_between(0.12, 0.24),
            start_size=rand_size3(0.04, 0.07),
            start_color=random_color(STERN_WHITE, STERN_CYAN),
            simulation_space="Local", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(1.2))
       .with_shape(circle(radius=3.5, thickness=0.6))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 1.1, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=3.2)
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 1.5, 6.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(1.0, 2.0), constant(0))),
            color_over_lifetime=varied([(0.0, 0.0), (0.3, 0.9), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.75, 0.92, 1.0), (1.0, 0.98, 0.92, 0.76)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_guardian() -> FxBuilder:
    """Nova-Wächter guardian (~120t, entity lane on the caster): ONE bright star pacing
    a head-height orbit (Loop-arc circle — the emission point IS the guardian) with
    twinkle dust shed along its path. Strike beats stay the server's Quasar baseline.

    A1 (ENTITY lane): the star itself stays Local — it IS the guardian and must hold its
    orbit — but the dust it sheds moves to WORLD space with a 0.3 `inheritVelocity`, so a
    walking caster leaves a genuine trail of motes hanging in the air behind them instead
    of dragging the same 32 sprites along. `distanceRate` 0.6 tops the trail up with
    travel, and the sink rate went from 0.02-0.06 to 0.35-0.9 block/s so the motes
    actually fall out of the orbit plane."""
    fx = FxBuilder("wandfx2_stern_guardian")
    root = fx.empty("guardian")

    # The guardian star: short-lived bright stars re-emitted along the orbiting arc
    # point — reads as one continuous circling star (steady rate + Loop arc).
    (fx.particle_emitter("orbit_star",
            duration=GUARDIAN_WINDOW, looping=False, start_lifetime=constant(4),
            start_speed=constant(0), start_size=nf3(0.22),
            simulation_space="Local", max_particles=16)
       .child_of(root)
       .at(0.0, 1.5, 0.0)
       .with_emission(rate=constant(3.5))
       .with_shape(circle(radius=1.4, thickness=0.0, arc_mode="Loop", arc_speed=1.1))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.3, 1.4, 2.0), blend=BLEND_ADDITIVE))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            size_over_lifetime=curve(0.6, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.6), (0.5, 1.0), (1.0, 0.3)],
                [(0.0, 0.95, 0.96, 1.0), (1.0, 0.97, 0.89, 0.69)],
                [(0.0, 0.78, 0.93, 1.0), (1.0, 1.0, 0.95, 0.82)]))
       .with_lights(sky=15, block=15))

    # Twinkle dust: faint motes the guardian sheds, left behind in world space.
    (fx.particle_emitter("orbit_dust",
            duration=GUARDIAN_WINDOW, looping=False, start_lifetime=random_between(8, 14),
            start_speed=constant(0), start_size=rand_size3(0.03, 0.06),
            start_color=random_color(STERN_WHITE, STERN_CYAN),
            simulation_space="World", max_particles=40)
       .child_of(root)
       .at(0.0, 1.5, 0.0)
       .with_emission(rate=constant(1.6), distance_rate=constant(0.6))
       .with_shape(circle(radius=1.4, thickness=0.05, arc_mode="Loop", arc_speed=1.1))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.0, 1.3), blend=BLEND_ADDITIVE))
       .with_module("inheritVelocity", inherit_velocity(0.3))
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 0.3, 4.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-0.9, -0.35), constant(0))),
            size_over_lifetime=curve(0.3, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied([(0.0, 0.0), (0.3, 0.8), (1.0, 0.0)],
                                       [(0.0, 1.0, 1.0, 1.0)],
                                       [(0.0, 0.72, 0.9, 1.0), (1.0, 0.96, 0.9, 0.72)])))

    flash(fx, root, "summon_pop", 0.8, (1.3, 1.4, 2.0), lifetime=7)
    return fx


def build_stern_bless() -> FxBuilder:
    """Lichtsegen blessing (~40t, entity lane on the caster): three descending light
    shafts + a star-mote rain settling onto the blessed + one faint dome breath.
    Healing must read soft — no hard pops, everything eases.

    A1 (ENTITY lane): the rain has to STAY on the blessed, so it keeps Local space and
    takes the drag knob instead — a negative `inheritVelocity` multiply lets the motes
    fall behind the moving target by ~35 % of its travel, which reads as the blessing
    streaming off a running player. `distanceRate` thickens it with travel, and the fall
    rate went from 0.08-0.16 to 1.1-2.2 block/s (it was a hovering cloud, not rain)."""
    fx = FxBuilder("wandfx2_stern_bless")
    root = fx.empty("bless")

    # Light shafts: tall stretched beams sliding DOWN onto the target.
    (fx.particle_emitter("light_shafts",
            duration=40, looping=False, start_lifetime=constant(14),
            start_speed=constant(-0.5),  # cone fountains +Y; negative speed = descend
            start_size=nf3(0.6), simulation_space="Local", max_particles=8)
       .child_of(root)
       .at(0.0, 3.2, 0.0)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2)),
                                                  burst(time=5, count=constant(2)),
                                                  burst(time=10, count=constant(2))])
       .with_shape(cone(angle=4.0, radius=0.7))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 1.2, 1.7), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.0, length_scale=5.0)
       .with_curves(color_over_lifetime=varied(
            [(0.0, 0.0), (0.25, 0.85), (0.75, 0.55), (1.0, 0.0)],
            [(0.0, 0.95, 0.96, 1.0), (1.0, 0.97, 0.89, 0.69)],
            [(0.0, 0.79, 0.93, 1.0), (1.0, 1.0, 0.95, 0.83)]))
       .with_lights(sky=15, block=15))

    # Star-mote rain: twinkles drifting down over the blessed silhouette.
    (fx.particle_emitter("mote_rain",
            duration=40, looping=False, start_lifetime=random_between(14, 22),
            start_speed=constant(0), start_size=rand_size3(0.04, 0.08),
            simulation_space="Local", max_particles=44)
       .child_of(root)
       .at(0.0, 2.4, 0.0)
       .with_emission(rate=constant(1.5), distance_rate=constant(0.5),
                      bursts=[burst(time=0, count=constant(10))])
       .with_shape(cylinder(radius=1.1, thickness=1.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.05, 1.5), blend=BLEND_ADDITIVE))
       .with_module("inheritVelocity", inherit_velocity(-0.35))
       .with_module("colorBySpeed", color_by_speed(COOL_STERN, HOT_WHITE, 0.5, 4.0))
       .with_curves(
            uv_animation=dict(TWINKLE_FRAMES),
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(-2.2, -1.1), constant(0))),
            size_over_lifetime=curve(0.35, 1.0, [SEG_DECAY_TAIL], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.95), (0.8, 0.6), (1.0, 0.0)],
                [(0.0, 0.95, 0.96, 1.0), (1.0, 0.97, 0.89, 0.69)],
                [(0.0, 0.77, 0.92, 1.0), (1.0, 1.0, 0.94, 0.79)]))
       .with_lights(sky=15, block=15))

    # Dome breath: a faint hemisphere breathing once around the group.
    (fx.particle_emitter("dome_breath",
            duration=40, looping=False, start_lifetime=constant(30), start_speed=constant(0),
            start_size=nf3(2.4), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=2, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(DOME_FAINT, hdr=hdr(0.8, 0.9, 1.3), blend=BLEND_ADDITIVE))
       .with_curves(
            size_over_lifetime=curve(0.7, 1.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 0.5), (0.8, 0.3), (1.0, 0.0)],
                [(0.0, 0.8, 0.88, 1.0), (1.0, 0.6, 0.7, 0.95)],
                [(0.0, 0.9, 0.93, 0.98), (1.0, 0.72, 0.79, 0.9)])))
    return fx


BUILDERS = {
    "wandfx2_muzzle_riss.fx": build_muzzle_riss,
    "wandfx2_muzzle_glut.fx": build_muzzle_glut,
    "wandfx2_muzzle_stern.fx": build_muzzle_stern,
    "wandfx2_glut_comet.fx": build_glut_comet,
    "wandfx2_glut_burst.fx": build_glut_burst,
    "wandfx2_glut_aschesturm.fx": build_glut_aschesturm,
    "wandfx2_riss_well.fx": build_riss_well,
    "wandfx2_riss_maelstrom.fx": build_riss_maelstrom,
    "wandfx2_riss_echo_blade.fx": build_riss_echo_blade,
    "wandfx2_stern_seal.fx": build_stern_seal,
    "wandfx2_stern_guardian.fx": build_stern_guardian,
    "wandfx2_stern_bless.fx": build_stern_bless,
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
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B)"
                  " — valid, + .fxproj")
    return rc


if __name__ == "__main__":
    sys.exit(main())
