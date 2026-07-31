#!/usr/bin/env python3
"""gen_player_fx — PH-PLAYER's Photon `.fx` assets (IDEAS-player.md concepts 1/2/4/5/6).

Authors the wand + player-attached effect files programmatically via fxlib (the repo's
diffable source of truth for these binary assets — regenerate, never hand-edit):

  concept 1  eclipse:wand_soulbind_flash   soulbind ceremony HDR bloom pop (entity one-shot)
  concept 2  eclipse:stern_komet_fall      Kometenschlag descent head, 3-ribbon ara stack,
                                           speed-coupled spark wake (+ Tick/FirstCollision subs)
             eclipse:stern_komet_sparkle     glitter motes shed by the falling head (Tick)
             eclipse:stern_komet_touchdown   FirstCollision stamp where the head hits terrain
             eclipse:stern_komet_impact    delayed HDR detonation (setDelay(telegraph) caller-side)
             eclipse:stern_komet_crater_glow  Birth stage 1 — crater glow + rim seeds
             eclipse:stern_komet_ember_motes  Birth stage 2 — rising ember motes
             eclipse:stern_komet_star_glint   Birth stage 3 — fading star glints (chain leaf)
  concept 4  eclipse:riss_schlag_maw       maw implosion: negative radial + Death sub-chain
             eclipse:riss_glitch_pop         3-particle static burst (sub-emitter target)
  concept 5  eclipse:glut_sprung_crater    eruption: 14 physics colliders + Collision/Death subs
             eclipse:glut_splash             per-bounce ember splash (Collision target)
             eclipse:glut_ember_die          2-particle fizzle (Death target)
  concept 6  eclipse:wand_idle_riss        scanline ara ribbon orbit + pixel squares (loop)
             eclipse:wand_idle_glut        ember ring, shapeArc Loop sweep (loop)
             eclipse:wand_idle_stern       tilted star halo + hairline trails (loop)

Every loop ships a renderer cull box + modest maxParticles (INTEGRATION.md §4 loop law);
one-shots stay inside the budgets quoted per concept in IDEAS-player.md. Textures:
Photon-bundled circle.png/smoke.png, the worker-authored square_4x4.png (mobs_fx.py —
the glitch identity sheet), and star_2x2.png authored HERE (4-point-star twinkle
flipbook, deterministic stdlib writer).

Run:  python3 tools/photon/gen_player_fx.py          # writes + validates all assets
"""
import math
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
SMOKE = "photon:textures/particle/smoke.png"
# Identity textures (PHOTON-QUALITY §5.1 rule 6 — circle.png is for generic sparks only).
SQUARE_4X4 = "eclipse:textures/particle/square_4x4.png"  # mobs_fx.py, 4x4 hard squares
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"      # authored below
STAR_TEXTURE = REPO_ROOT / "src/main/resources/assets/eclipse/textures/particle/star_2x2.png"


# ---------------------------------------------------------------------------
# star_2x2.png — 2x2 sheet of 4-point-star frames (128x128, 64 px frames). The four
# frames vary arm length + gain so the WholeSheet uvAnimation IS the twinkle
# (IDEAS-player #6 STERN: "4-point-star sprite, uvAnimation 2x2 flipbook twinkle").
# White-RGB alpha mask — tint rides startColor/gradients at runtime.
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, data: bytes) -> bytes:
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def write_star_2x2(path: Path, frame: int = 64) -> None:
    frames = [(1.0, 1.0), (0.78, 0.88), (0.92, 0.97), (0.66, 0.8)]  # (arm length, gain)
    size = frame * 2
    rows = []
    for y in range(size):
        row = bytearray([0])  # filter 0 (None)
        for x in range(size):
            arm, gain = frames[(y // frame) * 2 + (x // frame)]
            nx = ((x % frame) + 0.5) / frame * 2.0 - 1.0
            ny = ((y % frame) + 0.5) / frame * 2.0 - 1.0
            ax, ay = abs(nx) / arm, abs(ny) / arm
            # Soft diamond core + thin axis-aligned rays = the classic 4-point star.
            core = max(0.0, 1.0 - (ax + ay) / 0.42) ** 1.5
            ray_x = max(0.0, 1.0 - ax) ** 3.0 * math.exp(-((ay / 0.075) ** 2))
            ray_y = max(0.0, 1.0 - ay) ** 3.0 * math.exp(-((ax / 0.075) ** 2))
            a = min(1.0, core + ray_x + ray_y) * gain
            row += bytes((255, 255, 255, int(round(255.0 * a))))
        rows.append(bytes(row))
    png = (b"\x89PNG\r\n\x1a\n"
           + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
           + _png_chunk(b"IDAT", zlib.compress(b"".join(rows), 9))
           + _png_chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)

# Ticks the komet head needs to cover its baked ~18-block descent. MUST stay in sync with
# WandPhotonFxRows.KOMET_FALL_TICKS (the client subtracts it from the telegraph delay).
KOMET_FALL_TICKS = 13

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4). Many additive quads converge to white
#: above it, and the komet stacks head + 3 ribbons + wake inside one half-block.
HDR_CEILING = 1.45


def hdr(r, g, b):
    """Clamps an HDR triple to `HDR_CEILING`, keeping the channel ratio (= the hue)."""
    peak = max(r, g, b)
    if peak <= HDR_CEILING:
        return (r, g, b)
    k = HDR_CEILING / peak
    return (round(r * k, 3), round(g * k, 3), round(b * k, 3))


def ara_toggles_on(compound):
    """Marks an ara config's `section` / `physicsSetting` toggle groups as enabled.

    Both extend LDLib2's `ToggleGroup`, whose `deserializeNBT` reads `_enable` FIRST and
    then short-circuits (`if (!isEnable() && skipDisableSerialize()) return;`, the latter
    hard-coded true) — a compound written without the flag deserialises DISABLED and its
    payload is never read. `AraTrailParticle.updatePhysics` gates the whole integrator on
    `config.physicsSetting.isEnable()`, so the lag/gravity block below is inert without it.
    A4 (`fx_boss_herald_ferryman.ara_toggles_on`) patches its standalone emitters; the komet
    ribbons are EMBEDDED ara configs (see `_komet_ribbon`), so the flag is stamped on the
    `araConfig` compound instead. fxlib is A0 ground this wave — patch here, not there.
    """
    for key in ("section", "physicsSetting"):
        block = compound.get(key)
        if isinstance(block, dict):
            block["_enable"] = B(1)
    return compound


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED trail/ara configs (trails module, FX_FORMAT §4.2/4.3).

    fxlib's _RendererMixin only serves standalone emitters; embedded TrailConfig/AraTrailConfig
    carry their own renderer block — written explicitly so ribbons never fall back to the
    MISSING (pink) material.
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# --------------------------------------------------------------------------- wave-13 B6
# The three wave-13 movement/variance levers, ported from the A1 wandfx2 package so the
# non-komet half of this file speaks the same dialect as the komet chain above.
# ---------------------------------------------------------------------------
def color_by_speed(cool_rgb, hot_rgb, lo_bps, hi_bps):
    """`colorBySpeed` module body — ColorBySpeedSetting{color, speedRange}.

    Input is blocks/SECOND (`|realVelocity| × 20`), output MULTIPLIES the lifetime color,
    so the ramp reads as "fast = the hot tint, slow = the cool tint". `speedRange` is an
    LDLib2 `Range`, whose codec fields are `a`/`b` — fxlib's `_min_max` writes `min`/`max`
    and would deserialise to the 0..1 default, hence the hand-rolled compound.
    """
    return {"color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, *cool_rgb), (1.0, *hot_rgb)]),
            "speedRange": {"a": F(float(lo_bps)), "b": F(float(hi_bps))}}


def varied(alpha_pts, rgb_pts, rgb_alt, alpha_alt=None):
    """`random_gradient` — the authored ramp plus a sibling ramp inside the same path
    identity; each particle rolls its own memoized lerp between the two, which is what
    breaks the clone look on a 24-particle burst without adding a single particle."""
    return random_gradient(alpha_pts, rgb_pts, alpha_alt or alpha_pts, rgb_alt)


def inherit_velocity(multiply, mode="CURRENT"):
    """`inheritVelocity` module body — InheritVelocitySetting{mode, multiply}.

    CURRENT re-reads the emitter velocity every tick (INITIAL freezes it at birth). On a
    LOCAL-space, entity-attached emitter the particle is already welded to the transform,
    so a NEGATIVE multiply is the drag knob: the aura lags this share of the player's
    travel and smears backwards while sprinting, then snaps back onto the hand on a stop.
    Only legal because `WandAuraClient` spawns the idle loops through
    `PhotonBridge.ensureAttachedFx` — a world-anchored executor has no velocity to inherit.
    """
    return {"mode": mode, "multiply": constant(float(multiply))}


#: Local-space drag multiply for the hand auras (the A1 `wand_overcharge` value — deep
#: enough to read at sprint speed, shallow enough that the aura never leaves the hand).
IDLE_DRAG = -0.4
#: Blocks of player travel per extra particle on the idle loops (`emission.distanceRate`).
#: Standing still costs nothing; walking thickens the aura — the loops stop looking like
#: a static decal welded to the hand.
IDLE_PER_BLOCK = 0.6


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
       .with_material(texture_material(CIRCLE, hdr=hdr(2.5, 2.2, 3.5), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 1.0, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="VerticalBillboard")
       .with_curves(
            size_over_lifetime=curve(  # 0.4 -> 3.2 ease-out expansion
                1.0, 8.0, [(0.0, 0.0, 0.18, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.9), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    # Wave-13 B6: the sparks were authored as blocks/TICK (0.3–0.7), which Photon reads as
    # blocks/SECOND — 24 sparks crawling 0.3–1.0 blocks over their whole 20–30 t life, i.e.
    # a static clump. Re-solved for the ~2.5 block spray the ceremony wants, and the birth
    # shell widened 0.3 -> 0.75 so 24 additive quads no longer stack inside one half-block
    # (the V2.1 stacking law: overlapping ALPHA sprites converge to their own colour, so a
    # tight white-born burst bleaches to a single blob).
    (fx.particle_emitter("sparks",
            duration=50, looping=False, start_delay=constant(1),
            start_lifetime=random_between(20, 30), start_speed=random_between(2.5, 5.0),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=32)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(24))])
       .with_shape(sphere(radius=0.75, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.0, 1.4), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.15, bounce_chance=0.0)
       # The spray decelerates hard, so speed IS the phase of the ceremony: the shot-out
       # sparks are white-hot, the ones already settling have gone violet.
       .with_module("colorBySpeed", color_by_speed((0.55, 0.35, 0.9), (1.0, 1.0, 1.0),
                                                   1.0, 6.0))
       .with_curves(
            velocity_over_lifetime=dict(
                speed_modifier=curve(0.1, 1.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            color_over_lifetime=varied(  # born dark -> white flash -> violet -> 0
                [(0.0, 0.0), (0.1, 1.0), (0.55, 0.8), (1.0, 0.0)],
                [(0.0, 0.16, 0.1, 0.28), (0.18, 1.0, 1.0, 1.0),
                 (0.6, 0.75, 0.55, 1.0), (1.0, 0.45, 0.25, 0.8)],
                [(0.0, 0.12, 0.08, 0.22), (0.22, 0.92, 0.88, 1.0),
                 (0.62, 0.55, 0.4, 0.95), (1.0, 0.3, 0.16, 0.6)]))
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
            size_over_lifetime=curve(1.0, 2.2, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.35), (1.0, 0.0)],
                [(0.0, 0.7, 0.55, 0.95), (1.0, 0.4, 0.3, 0.6)])))
    return fx


# ---------------------------------------------------------------------------
# Concept 2 — the Stern-Komet chain (FX census wave 13 / team A8)
#
# The census asks for the first 3-stage Birth/Collision chain on the PLAYER side, so the
# Kometenschlag set-piece is now a seven-file tree instead of two flat one-shots:
#
#   eclipse:stern_komet_fall                    Row CUE_STERN_KOMET, spawned at aim+18y,
#   │                                           delay = telegraph − KOMET_FALL_TICKS
#   │  head  ── Tick/4 ─────────► eclipse:stern_komet_sparkle
#   │        └─ FirstCollision ─► eclipse:stern_komet_touchdown   (flash+ring+splinters)
#   │  tail_veil / tail_ribbon / tail_core      3-layer embedded ara stack (A4 pattern)
#   │  spark_wake                               speed-coupled shed sparks + colorBySpeed
#   │
#   eclipse:stern_komet_impact                  same Row, spawned at aim, delay = telegraph
#      core_flash ── Birth ─────► eclipse:stern_komet_crater_glow
#                                    rim_seeds ── Birth p0.5 ─► eclipse:stern_komet_ember_motes
#                                                                  motes ── Birth p0.45 ─►
#                                                                     eclipse:stern_komet_star_glint
#
# Fan-out (A5 consequence 3, every stamp deep-copies a runtime): 1 → 1 → 6×0.5 = 3 →
# 3×4×0.45 ≈ 5.4 → ×3 glints ≈ 16 particles. Every child file's burst sum stays ≤ 8
# (LINT-SUBEM-FAT): touchdown 1+1+6 = 8, crater_glow 1+6 = 7, ember_motes 4+2 = 6,
# star_glint 3.
#
# FOUR RUNTIME FACTS THIS SECTION IS BUILT ON (photon-neoforge-1.21.1-2.1.5, decompiled):
#
#  1. `distanceRate` CANNOT drive the spark wake here. `EmissionSetting.getEmissionCount`
#     reads `particleEmitter.getAccumulatedDistance()`, which `ParticleEmitter.emitParticle`
#     grows by `getVelocity().length()` — and `Emitter.updateTick` derives that velocity
#     from `transform.position()` deltas of the EMITTER. A `BlockEffectExecutor` root never
#     moves, so the accumulator stays 0.0 and `distanceRate` is a silent no-op on every
#     world-anchored asset (it only works on entity-followed FX, e.g. A1's wandfx2 trails).
#     What the census actually wants — constant spark density per BLOCK travelled — is
#     reproduced exactly by an `emissionRate` curve proportional to |v| (see `_WAKE_*`).
#  2. The particle, not the emitter, is what moves. So the ribbons ride EMBEDDED
#     `trails/araConfig` blocks on carrier particles; standalone `ara_trail_emitter`s (A4's
#     shape) would sit still at the anchor.
#  3. `araConfig.time` is dead for embedded trails: `AraTrailParticle.updateDynamicData`
#     takes `lifetimeSupplier` when present, and `TrailsSetting.setup` always installs one
#     (`trails.lifetime × particle.getLifetime() / 20` SECONDS). Ribbon length is therefore
#     tuned through `trails.lifetime`, and `time` is left out entirely.
#  4. `removedWhenCollided` fires Death AND Collision AND FirstCollision from the same
#     `TileParticle.updateCollisionBounce` call, so the head hangs its touchdown on
#     FirstCollision only — a Death row would double-stamp.
# ---------------------------------------------------------------------------
#: Baked descent. `SEG_KOMET_GRAV` runs 1 → 0, so `curve(lower, upper, …)` reads `upper`
#: (slow) at t=0 and `lower` (fast) at t=1: an ACCELERATING fall, not a constant ramp.
#: Photon linear velocity is blocks/SECOND (`VelocityOverLifetimeSetting` × 0.05/tick), so
#: −16.0 → −56.66 b/s integrates over the 13 discrete emitter ticks to exactly 18.000
#: blocks — the KOMET_SPAWN_HEIGHT the registrar offsets the root by.
SEG_KOMET_GRAV = (0.0, 1.0, 0.30, 0.98, 0.62, 0.72, 1.0, 0.0)
KOMET_V_TOP = -16.0
KOMET_V_FLOOR = -56.66
KOMET_FALL_BLOCKS = 18.0

#: Spark-wake emission origin. `Function` (shape type `function`) evaluates x/y/z per
#: PARTICLE with `t` = the emitter's t and fresh `randomA..E` rolls, so this is the exact
#: closed form of the head's discrete descent (Faulhaber sum of the GRAV cubic, quartic in
#: t) plus a `randomA` smear across the block band the head sweeps during that tick. Sparks
#: therefore land ON the swept path with no beading and no gaps; the ±0.5 recentring keeps
#: them straddling the nucleus whichever of the two emitters the render queue ticks first.
#: Verified against Photon's own bundled `expr.Parser`: y(1.0) = −18.0003.
_WAKE_FALL = "10.3578*t + 0.069591*t*t + 6.11933*t*t*t + 1.45359*t*t*t*t"
_WAKE_STEP = "0.8 + 0.12198*t + 1.46376*t*t + 0.44726*t*t*t"     # blocks fallen this tick
#: `step(t)` endpoints — blocks the head covers during the first and the last emitter tick.
#: `step` is affine in the GRAV bezier, so `curve(lower, upper, [SEG_KOMET_GRAV])` reproduces
#: it exactly; scaling both ends by WAKE_PER_BLOCK gives a rate curve that emits a CONSTANT
#: number of sparks per BLOCK — the density `distanceRate` would have produced if the
#: accumulator were not pinned at zero on a static anchor (≈23 sparks over the 18 blocks).
WAKE_STEP_TOP = 0.800      # step(0), = |KOMET_V_TOP| × 0.05
WAKE_STEP_FLOOR = 2.833    # step(1), = |KOMET_V_FLOOR| × 0.05
WAKE_PER_BLOCK = 1.30


def _komet_descent() -> dict:
    """The shared 18-blocks-in-13-ticks velocity ramp (head + all three ribbon carriers)."""
    return dict(linear=nf3(constant(0),
                           curve(KOMET_V_FLOOR, KOMET_V_TOP, [SEG_KOMET_GRAV],
                                 "lifetime", "velocity"),
                           constant(0)))


def _komet_taper(knee: float) -> dict:
    """Ribbon width over length: full at the nucleus, `knee` at mid-tail, out to a point."""
    return curve(0.0, 1.0,
                 [(0.0, 1.0, 0.16, 0.98, 0.4, knee + 0.16, 0.52, knee),
                  (0.52, knee, 0.72, knee * 0.5, 0.89, 0.05, 1.0, 0.0)],
                 "length", "thickness")


def _komet_ribbon(thickness, smoothness, trail_lifetime, color_over_length,
                  knee, hdr_rgb, physics):
    """One layer of the 3-ribbon ara stack as an embedded `trails` module compound.

    `highQualityCorners` stays OFF on purpose (A4 finding): `appendFlatTrail` compensates
    miter joins with `thickness / max(bitangent · nextBitangent, 0.15)`, i.e. up to 6.67x
    over-thick on the near-degenerate segments a 2.5 blocks/tick head produces — a comb of
    spikes instead of a band. `dieWithParticles` stays OFF too, so the ribbon keeps fading
    after the head is removed by its terrain collision instead of blinking out with it.
    """
    return {
        "ratio": F(1.0), "lifetime": constant(trail_lifetime),
        "dieWithParticles": B(0), "sizeAffectsWidth": B(0), "sizeAffectsLifetime": B(0),
        "inheritParticleColor": B(0),
        "colorOverLifetime": gradient([(0.0, 1.0), (1.0, 1.0)], [(0.0, 1.0, 1.0, 1.0)]),
        "trailType": "ARA_TRAIL",
        "araConfig": ara_toggles_on({
            "thickness": F(thickness), "smoothness": I(smoothness),
            "minDistance": F(0.07), "timeInterval": F(0.04),
            "alignment": "View", "space": "World", "sorting": "NewerOnTop",
            "textureMode": "Stretch", "highQualityCorners": B(0),
            "thicknessOverLength": _komet_taper(knee),
            "colorOverLength": color_over_length,
            "physicsSetting": {
                "warmup": F(0.0),
                "gravity": L([F(0.0), F(physics["gravity"]), F(0.0)]),
                "inertia": F(physics["inertia"]),
                "velocitySmoothing": F(physics["velocity_smoothing"]),
                "damping": F(physics["damping"])},
            "renderer": ribbon_renderer(
                texture_material(CIRCLE, hdr=hdr(*hdr_rgb), blend=BLEND_ADDITIVE))})}


def _komet_carrier(fx, name, ribbon):
    """A near-invisible particle whose only job is to drag one ribbon layer down the path.

    Carries the head's physics as well so the ribbon stops where the terrain does (the
    carrier dies on contact; `dieWithParticles: 0b` lets its tail keep fading).
    """
    return (fx.particle_emitter(name,
                duration=20, looping=False, start_lifetime=constant(KOMET_FALL_TICKS),
                start_speed=constant(0), start_size=nf3(0.02),
                start_color=color(0x14FFFFFF),  # the ribbon is the show, not the carrier
                simulation_space="World", max_particles=4)
            .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
            .with_shape(dot())
            .with_material(texture_material(CIRCLE, blend=BLEND_ADDITIVE))
            .with_physics(collision=True, removed_when_collided=True, friction=1.0,
                          gravity=0.0, bounce_chance=0.0)
            .with_curves(velocity_over_lifetime=_komet_descent())
            .with_module("trails", ribbon))


def build_stern_komet_fall() -> FxBuilder:
    """The descent: HDR nucleus + 3-layer ara tail + speed-coupled spark wake.

    Spawned by the client at target + (0, 18, 0); the descent velocity is baked here so the
    server owns only the telegraph timing (delay = telegraph − KOMET_FALL_TICKS). Object
    order matters: `head` is declared first so it is registered — and therefore ticked —
    ahead of the wake (`FXRuntime.objects` is a LinkedHashMap fed in file order).
    """
    fx = FxBuilder("stern_komet_fall")

    # 1. The nucleus. hasCollision + removedWhenCollided is what turns "a sprite that
    #    reaches y+0" into a real terrain hit: `TileParticle.updatePositionAndInternalVelocity`
    #    sweeps the 0.9-block box with `Entity.collideBoundingBox` (peak step 56.66 b/s ×
    #    0.05 = 2.83 b/t → v² = 8.0, far under the 10000 MAXIMUM_COLLISION_VELOCITY_SQUARED
    #    bail-out that would silently skip the sweep on the fastest ticks), and the
    #    clamp fires FirstCollision wherever the ground actually is — a ceiling, a roof, or
    #    the aim point. The delayed `stern_komet_impact` stays the guaranteed detonation.
    (fx.particle_emitter("head",
            duration=20, looping=False, start_lifetime=constant(KOMET_FALL_TICKS),
            start_speed=constant(0), start_size=nf3(0.9), simulation_space="World",
            max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.8, 1.8, 2.6), blend=BLEND_ADDITIVE))
       .with_physics(collision=True, removed_when_collided=True, friction=1.0,
                     gravity=0.0, bounce_chance=0.0)
       .with_curves(
            velocity_over_lifetime=_komet_descent(),
            # Compression heating: the head swells and whitens as it dives.
            size_over_lifetime=curve(1.0, 1.35, [SEG_SMOOTH_UP], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.85), (0.25, 1.0), (1.0, 1.0)],
                [(0.0, 0.62, 0.74, 1.0), (0.45, 0.86, 0.92, 1.0), (1.0, 1.0, 1.0, 1.0)]))
       .with_sub_emitters(
            sub_emitter("eclipse:stern_komet_touchdown", event="FirstCollision",
                        probability=1.0),
            # Kept from the shipped asset but halved in cadence — the dense wake below now
            # owns the streak, the sparkle is the slower glitter shed on top of it.
            sub_emitter("eclipse:stern_komet_sparkle", event="Tick",
                        probability=1.0, tick_interval=4))
       .with_lights(sky=15, block=15))

    # 2. Three co-located carriers, staggered by ara physics so the layers separate.
    #    `inertia` is the fraction of the head's velocity each freshly emitted trail point
    #    keeps (`AraTrailParticle.emitPoint`), `damping`/`gravity` then drive
    #    `physicsStep` — the veil smears and lifts like shed coma gas, the core stays
    #    welded to the nucleus with no physics at all.
    _komet_carrier(fx, "tail_veil", _komet_ribbon(
        thickness=0.85, smoothness=3, trail_lifetime=1.0, knee=0.68,
        color_over_length=gradient(
            [(0.0, 0.34), (0.4, 0.26), (0.78, 0.11), (1.0, 0.0)],
            [(0.0, 0.62, 0.74, 1.0), (0.45, 0.34, 0.42, 0.9), (1.0, 0.16, 0.19, 0.52)]),
        hdr_rgb=(0.5, 0.62, 1.05),
        physics=dict(gravity=1.1, inertia=0.45, velocity_smoothing=0.6, damping=0.9)))

    _komet_carrier(fx, "tail_ribbon", _komet_ribbon(
        thickness=0.40, smoothness=6, trail_lifetime=0.72, knee=0.5,
        color_over_length=gradient(
            [(0.0, 0.92), (0.3, 0.78), (0.75, 0.36), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.3, 0.78, 0.88, 1.0),
             (0.72, 0.42, 0.6, 1.0), (1.0, 0.2, 0.26, 0.66)]),
        hdr_rgb=(0.95, 1.1, 1.45),
        physics=dict(gravity=0.35, inertia=0.2, velocity_smoothing=0.7, damping=0.84)))

    _komet_carrier(fx, "tail_core", _komet_ribbon(
        thickness=0.13, smoothness=4, trail_lifetime=0.38, knee=0.4,
        color_over_length=gradient(
            [(0.0, 1.0), (0.42, 0.66), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (1.0, 0.78, 0.88, 1.0)]),
        hdr_rgb=(1.45, 1.45, 1.45),
        physics=dict(gravity=0.0, inertia=0.0, velocity_smoothing=0.75, damping=0.0)))

    # 3. The spark wake. duration == KOMET_FALL_TICKS so the emitter's t IS the descent
    #    parameter the `function` shape and the rate curve are written against; the emitter
    #    dies at t=1 while `Emitter.isAlive` keeps the runtime up for the live sparks.
    #    `start_speed` is sampled at the EMITTER's t (`TileParticle.setup`), so it tracks
    #    the nucleus (6 → 34 b/s vs. the head's 16 → 56.66) — which is what finally gives
    #    `colorBySpeed` a real signal to read: sparks shed late streak out white-hot, the
    #    early slow ones stay deep star-blue.
    (fx.particle_emitter("spark_wake",
            duration=KOMET_FALL_TICKS, looping=False,
            start_lifetime=random_between(7, 15),
            start_speed=curve(34.0, 6.0, [SEG_KOMET_GRAV], "emitter lifetime", "speed"),
            start_size=nf3(random_between(0.05, 0.11), random_between(0.05, 0.11),
                           random_between(0.05, 0.11)),
            simulation_space="World", max_particles=32)
       .with_emission(rate=curve(WAKE_PER_BLOCK * WAKE_STEP_FLOOR,
                                 WAKE_PER_BLOCK * WAKE_STEP_TOP,
                                 [SEG_KOMET_GRAV], "emitter lifetime", "particles/tick"))
       .with_shape(function_shape(
            x="0.42*(randomB - 0.5)",
            y=f"-(({_WAKE_FALL}) + (randomA - 0.5)*({_WAKE_STEP}))",
            z="0.42*(randomC - 0.5)",
            # Direction only — `Function.nextPosVel` normalises the speed vector and lets
            # startSpeed carry the magnitude. Mostly down, scattered sideways.
            speed_x="1.6*(randomD - 0.5)", speed_y="-1.0", speed_z="1.6*(randomE - 0.5)"))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.2, 1.7), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.5, length_scale=1.6)
       # Snuffed out by terrain instead of sinking through it (cheapest collision mode:
       # no bounce maths, and the head's own touchdown owns the ground read).
       .with_physics(collision=True, removed_when_collided=True, friction=0.9,
                     gravity=0.25, bounce_chance=0.0)
       # colorBySpeed MULTIPLIES the lifetime colour and reads |realVelocity| × 20 (b/s),
       # and its `speedRange` is an LDLib2 `Range` whose codec fields are a/b — NOT the
       # min/max pair `fxlib._min_max` writes, hence the raw module (A3 finding).
       .with_module("colorBySpeed", {
            "color": gradient([(0.0, 1.0), (1.0, 1.0)],
                              [(0.0, 0.34, 0.46, 1.0), (1.0, 1.0, 1.0, 1.0)]),
            "speedRange": {"a": F(4.0), "b": F(32.0)}})
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.55, 0.72), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.5, 0.7, 0.82, 1.0), (1.0, 0.3, 0.4, 0.9)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_sparkle() -> FxBuilder:
    """Tiny 4-mote glitter burst inheriting the falling head's position (Tick sub-target)."""
    fx = FxBuilder("stern_komet_sparkle")
    (fx.particle_emitter("glitter",
            duration=8, looping=False, start_lifetime=random_between(8, 14),
            start_speed=random_between(0.4, 1.6),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(4))])
       .with_shape(sphere(radius=0.25, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 1.2, 1.7), blend=BLEND_ADDITIVE))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (1.0, 0.0)], [(0.0, 0.85, 0.9, 1.0)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_touchdown() -> FxBuilder:
    """Terrain contact stamp — the head's FirstCollision child (burst sum 1+1+6 = 8 ≤ 8).

    Fires wherever the 0.9-block head box is actually stopped, which is NOT necessarily the
    aim point: a roof, an overhang or a cliff face terminates the descent early and this is
    what sells that the comet hit SOMETHING. The delayed `stern_komet_impact` remains the
    guaranteed detonation on the damage tick.
    """
    fx = FxBuilder("stern_komet_touchdown")
    root = fx.empty("touchdown")

    (fx.particle_emitter("flash",
            duration=30, looping=False, start_lifetime=constant(7), start_speed=constant(0),
            start_size=nf3(1.7), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 1.4, 1.45), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.25, 0.06, 1.0, 0.68, 0.45, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("shockring",
            duration=30, looping=False, start_lifetime=constant(13), start_speed=constant(0),
            start_size=nf3(0.6), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 1.1, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                1.0, 11.0, [(0.0, 0.0, 0.16, 0.86, 0.5, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0), (1.0, 0.42, 0.58, 1.0)])))

    # Splinters. Photon start_speed is blocks/SECOND (×0.05 per tick): the census reference
    # figure — 24 blocks of reach in 10 ticks — is 48.0, not 2.4. Damped by friction 0.92
    # plus gravity they land ~9-13 blocks out, which matches the 5-block damage radius plus
    # the splinter follow-ups the server throws.
    (fx.particle_emitter("splinters",
            duration=30, looping=False, start_lifetime=random_between(14, 26),
            start_speed=random_between(34.0, 48.0),
            start_size=nf3(random_between(0.07, 0.14), random_between(0.07, 0.14),
                           random_between(0.07, 0.14)),
            simulation_space="World", max_particles=8)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(6))])
       .with_shape(cone(angle=62.0, radius=0.2))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.05, 1.1, 1.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.7, length_scale=2.2)
       .with_physics(collision=True, friction=0.92, collided_friction=0.55, gravity=0.55,
                     bounce_chance=0.55, bounce_rate=0.3, bounce_spread=0.12)
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 1.0), (0.65, 0.72), (1.0, 0.0)],
            [(0.0, 1.0, 1.0, 1.0), (0.55, 0.66, 0.8, 1.0), (1.0, 0.24, 0.3, 0.7)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_impact() -> FxBuilder:
    """HDR detonation on the damage tick — caller applies setDelay(telegraph).

    `core_flash` is a single burst particle, so its Birth row stamps the afterglow cascade
    exactly once (A5 consequence 2: children inherit position, never timing — the cascade is
    sequenced by staggering the PARENT bursts inside each stage, not by delaying children).
    """
    fx = FxBuilder("stern_komet_impact")
    root = fx.empty("impact")

    (fx.particle_emitter("core_flash",
            duration=40, looping=False, start_lifetime=constant(10), start_speed=constant(0),
            start_size=nf3(2.4), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(2.2, 2.0, 3.0), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.3, 0.06, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_sub_emitters(sub_emitter("eclipse:stern_komet_crater_glow", event="Birth",
                                      probability=1.0))
       .with_lights(sky=15, block=15))

    # Vertical light pillar: stretched along a slow upward velocity.
    (fx.particle_emitter("pillar",
            duration=40, looping=False, start_lifetime=constant(16),
            start_speed=constant(4.0), start_size=nf3(0.9), simulation_space="Local",
            max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(cone(angle=0.5, radius=0.05))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 1.6, 2.2), blend=BLEND_ADDITIVE))
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
       .with_material(texture_material(CIRCLE, hdr=hdr(1.2, 1.2, 1.8), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 9.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.85), (1.0, 0.0)], [(0.0, 1.0, 1.0, 1.0)])))

    (fx.particle_emitter("debris",
            duration=40, looping=False, start_lifetime=random_between(20, 35),
            # Blocks/SECOND again: the shipped 0.4-1.0 was 0.02-0.05 blocks/TICK, i.e.
            # debris that never left the crater (the same unit slip A1/A3/A4 corrected
            # across the tree). 6-16 b/s = 0.3-0.8 b/t, damped onto the ground by
            # friction 0.98 + gravity 0.4 inside the impact's 5-block damage radius.
            start_speed=random_between(6.0, 16.0),
            start_size=nf3(random_between(0.06, 0.12), random_between(0.06, 0.12),
                           random_between(0.06, 0.12)),
            simulation_space="World", max_particles=48)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(30))])
       .with_shape(sphere(radius=0.5, thickness=0.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 1.1, 1.5), blend=BLEND_ADDITIVE))
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
            size_over_lifetime=curve(1.0, 2.4, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.25, 0.3), (1.0, 0.0)],
                [(0.0, 0.75, 0.8, 1.0), (1.0, 0.45, 0.55, 0.85)])))
    return fx


# --- Birth cascade: crater glow -> ember motes -> star glints -----------------
def build_stern_komet_crater_glow() -> FxBuilder:
    """Afterglow stage 1 — scorched crater disc plus the six rim seeds that carry stage 2.

    A5 consequence 1: Birth fires on the particle's FIRST tick, at its EMISSION point, so a
    link that must fan out in space has to be BORN fanned out — the seeds are burst on a
    r=2.4 circle rather than travelling there. Their burst sits at tick 6, which is the only
    way to sequence a cascade (children never inherit timing). Burst sum 1 + 6 = 7 ≤ 8.
    """
    fx = FxBuilder("stern_komet_crater_glow")

    (fx.particle_emitter("crater",
            duration=70, looping=False, start_lifetime=constant(55), start_speed=constant(0),
            start_size=nf3(1.6), simulation_space="Local", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(0.85, 0.62, 0.45), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(1.0, 3.1, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            # Dark birth tint (stacking law): the glow OPENS deep ember-brown and only
            # briefly licks warm, so 40+ overlapping afterglow quads never converge to white.
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.12, 0.55), (0.5, 0.34), (1.0, 0.0)],
                [(0.0, 0.34, 0.14, 0.1), (0.3, 0.86, 0.44, 0.2),
                 (1.0, 0.26, 0.12, 0.14)])))

    (fx.particle_emitter("rim_seeds",
            duration=70, looping=False, start_lifetime=random_between(26, 38),
            start_speed=random_between(0.6, 2.2),
            start_size=nf3(random_between(0.09, 0.16), random_between(0.09, 0.16),
                           random_between(0.09, 0.16)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=6, count=constant(6))])
       .with_shape(circle(radius=2.4, thickness=0.35))
       .with_material(texture_material(CIRCLE, hdr=hdr(0.95, 0.7, 0.5), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.08, bounce_chance=0.0)
       .with_sub_emitters(sub_emitter("eclipse:stern_komet_ember_motes", event="Birth",
                                      probability=0.5))
       .with_curves(color_over_lifetime=gradient(
            [(0.0, 0.0), (0.18, 0.8), (1.0, 0.0)],
            [(0.0, 0.3, 0.15, 0.12), (0.35, 1.0, 0.66, 0.34), (1.0, 0.4, 0.16, 0.1)]))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_ember_motes() -> FxBuilder:
    """Afterglow stage 2 — heavy soot settles, light embers rise (burst sum 2 + 4 = 6 ≤ 8).

    Mass law (census §8.4): the soot is the heavy element, so it sits LOW and SLOW under the
    motes that carry stage 3 upward.
    """
    fx = FxBuilder("stern_komet_ember_motes")

    (fx.particle_emitter("soot",
            duration=60, looping=False, start_lifetime=random_between(30, 44),
            start_speed=random_between(0.3, 0.9),
            start_size=nf3(random_between(0.22, 0.4), random_between(0.22, 0.4),
                           random_between(0.22, 0.4)),
            simulation_space="World", max_particles=4)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(cone(angle=32.0, radius=0.25))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 1.9, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.22, 0.34), (1.0, 0.0)],
                [(0.0, 0.2, 0.15, 0.14), (1.0, 0.1, 0.08, 0.09)])))

    (fx.particle_emitter("motes",
            duration=60, looping=False, start_lifetime=random_between(34, 48),
            start_speed=random_between(1.4, 3.4),
            start_size=nf3(random_between(0.05, 0.1), random_between(0.05, 0.1),
                           random_between(0.05, 0.1)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=5, count=constant(4))])
       .with_shape(cone(angle=22.0, radius=0.4))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.0, 0.66, 0.34), blend=BLEND_ADDITIVE))
       .with_curves(
            # Thermal wander on the way up so the embers do not read as a straight fountain.
            noise=dict(frequency=0.35, quality="Noise2D",
                       position=nf3(constant(0.035), constant(0.012), constant(0.035)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.15, 0.85), (0.7, 0.5), (1.0, 0.0)],
                [(0.0, 0.36, 0.16, 0.1), (0.3, 1.0, 0.7, 0.36), (1.0, 0.42, 0.14, 0.08)]))
       .with_sub_emitters(sub_emitter("eclipse:stern_komet_star_glint", event="Birth",
                                      probability=0.45))
       .with_lights(sky=15, block=15))
    return fx


def build_stern_komet_star_glint() -> FxBuilder:
    """Afterglow stage 3, chain leaf — three fading star glints (burst sum 3 ≤ 8).

    The path identity closes the loop: real 4-point-star sprites off star_2x2.png with the
    2x2 flipbook AS the twinkle, same as the Stern idle aura.
    """
    fx = FxBuilder("stern_komet_star_glint")
    (fx.particle_emitter("glints",
            duration=40, looping=False, start_lifetime=random_between(20, 32),
            start_speed=random_between(0.4, 1.3),
            start_size=nf3(random_between(0.09, 0.17), random_between(0.09, 0.17),
                           random_between(0.09, 0.17)),
            simulation_space="World", max_particles=6)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
       .with_shape(sphere(radius=0.5, thickness=1.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.05, 1.45),
                                       blend=BLEND_ADDITIVE))
       .with_curves(
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=curve(0.0, 4.0, [SEG_FLICKER_COMMIT]),
                              start_frame=random_between(0.0, 3.0), cycle=2.0),
            size_over_lifetime=curve(0.25, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.9), (1.0, 0.0)],
                [(0.0, 0.24, 0.2, 0.4), (0.4, 0.9, 0.94, 1.0), (1.0, 0.4, 0.5, 0.95)]))
       .with_lights(sky=15, block=15))
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
       .with_material(texture_material(CIRCLE, hdr=hdr(0.9, 1.3, 1.5), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.6, length_scale=2.0)
       .with_cull_box((-6.0, -6.0, -6.0), (6.0, 6.0, 6.0))
       .main(start_color=random_color(0xFF37E6E6, 0xFFE23AE2))  # glitch cyan <-> magenta
       .with_curves(
            # THE fix in this file. `radial` is scaled by 0.01/tick, so the authored −0.9
            # moved each streak 0.05 blocks over its 5–8 t life: the maw did not implode,
            # it sat on its own 3.5-block shell. −34 -> −74 (accelerating, SEG_SMOOTH_UP)
            # covers ~3.5 blocks in 6.5 t — the streaks actually reach the throat, and the
            # acceleration is what sells it as suction rather than a collapse.
            velocity_over_lifetime=dict(
                radial=curve(-34.0, -74.0, [SEG_SMOOTH_UP], "lifetime", "value")),
            # Speed is the whole story of an implosion, so let it write the colour: the
            # streaks whiten as the maw takes them.
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.25, 1.0), (1.0, 0.6)],
                [(0.0, 0.2, 0.35, 0.4), (0.3, 1.0, 1.0, 1.0), (1.0, 1.0, 1.0, 1.0)],
                [(0.0, 0.28, 0.16, 0.3), (0.35, 0.9, 1.0, 1.0), (1.0, 0.85, 0.95, 1.0)]))
       .with_module("colorBySpeed", color_by_speed((0.45, 0.5, 0.6), (1.0, 1.0, 1.0),
                                                   4.0, 15.0))
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
       .with_material(texture_material(CIRCLE, hdr=hdr(0.8, 1.4, 1.6), blend=BLEND_ADDITIVE))
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
    """3-particle hard-additive static burst (pixelArt bits=4) — Death sub-emitter target.
    Spec read is "hard additive SQUARES" (QUALITY §2 row 9): square_4x4.png via a 4x4
    uvAnimation tile-picker, plus an eased pop-shrink size envelope so the pop doesn't
    blink out linearly."""
    fx = FxBuilder("riss_glitch_pop")
    # Wave-13 B6: 0.02–0.1 b/s over 4 t is 0.02 blocks of travel — the "burst" never
    # burst. 1.2–3.2 b/s scatters the three bits ~0.25–0.65 blocks, which is a pop at the
    # scale of a 0.15-block birth sphere.
    (fx.particle_emitter("static",
            duration=6, looping=False, start_lifetime=constant(4),
            start_speed=random_between(1.2, 3.2),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            simulation_space="World", max_particles=8)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(3))])
       .with_shape(sphere(radius=0.15, thickness=1.0))
       .with_material(texture_material(SQUARE_4X4, hdr=hdr(1.0, 1.4, 1.5), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .main(start_color=random_color(0xFF66FFFF, 0xFFFFFFFF))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            size_over_lifetime=curve(0.2, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 1.0), (1.0, 0.0)],
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

    # Wave-13 B6: 0.5–1.1 b/s against gravity 0.5 (×0.04 = 0.02 b/t²) is a chunk that
    # leaves the ground by ~4 cm and immediately falls back — an eruption that never
    # erupts. 5–9 b/s apexes at 1.5–5 blocks after 12–22 t, which is what the collision
    # physics, the bounce chance and the Collision sub-emitter were all authored for.
    (fx.particle_emitter("magma_chunks",
            duration=50, looping=False, start_lifetime=random_between(30, 45),
            start_speed=random_between(5.0, 9.0),
            start_size=nf3(random_between(0.12, 0.28), random_between(0.12, 0.28),
                           random_between(0.12, 0.28)),
            simulation_space="World", max_particles=16)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(14))])
       .with_shape(cone(angle=40.0, radius=0.4))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.6, 0.8, 0.25), blend=BLEND_ADDITIVE))
       .main(start_color=random_color(0xFFFFC873, 0xFFFF7B3C))
       .with_physics(collision=True, friction=0.99, collided_friction=0.6, gravity=0.5,
                     bounce_chance=0.8, bounce_rate=0.45, bounce_spread=0.15)
       # Molten rock cools as it slows: the launch is white-hot, the apex hang and the
       # post-bounce crawl are deep red. The ramp does the work a second emitter would.
       .with_module("colorBySpeed", color_by_speed((0.5, 0.16, 0.06), (1.0, 1.0, 0.95),
                                                   1.0, 9.0))
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (0.75, 0.85), (1.0, 0.0)],
            [(0.0, 1.0, 0.95, 0.8), (0.4, 1.0, 0.55, 0.2), (1.0, 0.45, 0.12, 0.04)],
            [(0.0, 1.0, 0.8, 0.5), (0.45, 0.95, 0.36, 0.1), (1.0, 0.3, 0.07, 0.02)]))
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
       .with_material(texture_material(CIRCLE, hdr=hdr(2.0, 1.1, 0.3), blend=BLEND_ADDITIVE))
       .with_curves(size_over_lifetime=curve(
            0.0, 1.0, [(0.0, 0.35, 0.08, 1.0, 0.7, 0.5, 1.0, 0.0)], "lifetime", "size"))
       .with_lights(sky=15, block=15))

    (fx.particle_emitter("ground_ring",
            duration=50, looping=False, start_lifetime=constant(12), start_speed=constant(0),
            start_size=nf3(0.8), simulation_space="Local", max_particles=4)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(1))])
       .with_shape(dot())
       .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 0.7, 0.2), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="Horizontal")
       .with_curves(
            size_over_lifetime=curve(
                0.5, 7.0, [(0.0, 0.0, 0.2, 0.85, 0.55, 1.0, 1.0, 1.0)], "lifetime", "size"),
            color_over_lifetime=gradient([(0.0, 0.8), (1.0, 0.0)], [(0.0, 1.0, 0.8, 0.5)])))

    # Wave-13 B6: 0.03–0.08 b/s lifted the plume 0.16 blocks in 40 t — the eruption had no
    # column. 0.5–1.1 b/s carries it 1–2.2 blocks. The size ramp swaps SEG_LINEAR_UP for a
    # crest ease (the three LINT-LINEAR-CURVE grandfathers on this emitter are retired
    # with it): smoke billows fast and then only creeps, it does not grow at a constant
    # rate for two seconds.
    (fx.particle_emitter("smoke",
            duration=50, looping=False, start_lifetime=constant(40),
            start_speed=random_between(0.5, 1.1),
            start_size=nf3(random_between(0.4, 0.7), random_between(0.4, 0.7),
                           random_between(0.4, 0.7)),
            simulation_space="World", max_particles=12)
       .child_of(root)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(8))])
       .with_shape(cone(angle=25.0, radius=0.5))
       .with_material(texture_material(SMOKE, blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_curves(
            size_over_lifetime=curve(1.0, 2.0, [SEG_EASE_OUT_CREST], "lifetime", "size"),
            velocity_over_lifetime=dict(
                speed_modifier=curve(0.2, 1.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 0.45), (1.0, 0.0)],
                [(0.0, 0.35, 0.28, 0.25), (1.0, 0.15, 0.12, 0.1)],
                [(0.0, 0.24, 0.18, 0.16), (1.0, 0.1, 0.08, 0.07)])))
    return fx


def build_glut_splash() -> FxBuilder:
    """5 tiny embers per terrain bounce (Collision sub-emitter target)."""
    fx = FxBuilder("glut_splash")
    # Wave-13 B6: 0.15–0.35 b/s = 0.06–0.14 blocks over the 8 t life. A splash has to
    # LEAVE the bounce point; 1.5–3.5 b/s throws the embers 0.5–1.2 blocks.
    (fx.particle_emitter("splash",
            duration=10, looping=False, start_lifetime=constant(8),
            start_speed=random_between(1.5, 3.5),
            start_size=nf3(random_between(0.04, 0.08), random_between(0.04, 0.08),
                           random_between(0.04, 0.08)),
            simulation_space="World", max_particles=12)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(5))])
       .with_shape(cone(angle=55.0, radius=0.1))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.4, 0.7, 0.2), blend=BLEND_ADDITIVE))
       .with_physics(collision=False, gravity=0.3, bounce_chance=0.0)
       .with_curves(color_over_lifetime=varied(
            [(0.0, 1.0), (1.0, 0.0)],
            [(0.0, 1.0, 0.7, 0.3), (1.0, 0.6, 0.2, 0.05)],
            [(0.0, 1.0, 0.5, 0.15), (1.0, 0.4, 0.1, 0.02)]))
       .with_lights(sky=15, block=15))
    return fx


def build_glut_ember_die() -> FxBuilder:
    """2-particle fizzle when a magma chunk expires (Death sub-emitter target)."""
    fx = FxBuilder("glut_ember_die")
    # Wave-13 B6: a fizzle should still DRIFT (0.4–1.2 b/s = 0.12–0.36 blocks over 6 t);
    # the authored 0.01–0.05 b/s pinned it in place and read as a texture pop.
    (fx.particle_emitter("fizzle",
            duration=8, looping=False, start_lifetime=constant(6),
            start_speed=random_between(0.4, 1.2),
            start_size=nf3(random_between(0.05, 0.09), random_between(0.05, 0.09),
                           random_between(0.05, 0.09)),
            simulation_space="World", max_particles=6)
       .with_emission(rate=constant(0.0), bursts=[burst(time=0, count=constant(2))])
       .with_shape(sphere(radius=0.08, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.1, 0.5, 0.15), blend=BLEND_ADDITIVE))
       .with_curves(color_over_lifetime=varied(
            [(0.0, 0.9), (1.0, 0.0)],
            [(0.0, 1.0, 0.55, 0.2), (1.0, 0.4, 0.12, 0.03)],
            [(0.0, 1.0, 0.36, 0.1), (1.0, 0.28, 0.07, 0.02)])))
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
       # Wave-13 B6: `orbital` is rad/SECOND (AngularVelocity applies n×0.05 rad/tick,
       # jar-verified). 0.3 swept 0.6 rad = 34 deg over the 40 t loop, so the "scanline
       # circle" this emitter's docstring promises was a short arc that never closed and
       # never repeated. pi rad/s = exactly one full turn per 40 t loop cycle, so the
       # ribbon closes on its own head and the orbit reads as a ring.
       .with_curves(velocity_over_lifetime=dict(
            orbital_mode="AngularVelocity",
            orbital=nf3(constant(0), constant(math.pi), constant(0))))
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
                # 2-segment scanline flicker (IDEAS-player #6 RISS): dies mid-orbit,
                # snaps back hard, cuts out again — a broken-signal duty cycle.
                "thicknessOverTime": curve(
                    0.4, 1.0, [(0.0, 1.0, 0.1, 0.15, 0.3, 0.9, 0.5, 0.25),
                               (0.5, 0.25, 0.6, 1.0, 0.85, 0.05, 1.0, 0.8)]),
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=(0.9, 1.2, 1.2), blend=BLEND_ADDITIVE),
                    cull_box=((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0)))}}))

    # Wave-13 B6 movement pass. The loop is entity-attached (`WandAuraClient` →
    # `ensureAttachedFx`), which is the precondition for BOTH levers below:
    #   * `distanceRate` tops the bit count up with travel — the glitch gets noisier the
    #     faster the caster moves, and costs nothing while they stand still,
    #   * `inheritVelocity` at a negative multiply drags the bits backwards out of the
    #     hand while sprinting (A1's `wand_overcharge` pattern) instead of leaving them
    #     welded to it like a decal.
    # Speed 0.01–0.04 b/s was another blocks/tick slip (0.03 blocks of drift over a whole
    # life); 0.2–0.6 b/s gives the bits a visible sputter away from the hand.
    (fx.particle_emitter("squares",
            duration=40, looping=True, prewarm=10, start_lifetime=random_between(8, 14),
            start_speed=random_between(0.2, 0.6),
            start_size=nf3(random_between(0.03, 0.05), random_between(0.03, 0.05),
                           random_between(0.03, 0.05)),
            start_color=random_color(0xFF37E6E6, 0xFFE23AE2),
            simulation_space="Local", max_particles=24)
       .with_emission(rate=constant(0.3), distance_rate=constant(1.0 / IDLE_PER_BLOCK))
       .with_module("inheritVelocity", inherit_velocity(IDLE_DRAG))
       .with_shape(sphere(radius=0.3, thickness=1.0))
       # HARD squares (square_4x4.png was authored for exactly this read — QUALITY §2
       # row 8); the 4x4 uvAnimation samples one square per particle (frames identical,
       # so no flipbook divergence — the §4 shared-sheet trick).
       .with_material(texture_material(SQUARE_4X4, hdr=(0.8, 1.0, 1.0), blend=BLEND_ADDITIVE,
                                       pixel_art=True, pixel_art_bits=4))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            uv_animation=dict(tiles=(4, 4), animation="WholeSheet",
                              frame_over_time=constant(0),
                              start_frame=random_between(0.0, 15.0)),
            color_over_lifetime=gradient(
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
       # Wave-13 B6: distanceRate + inheritVelocity drag (entity-attached loop — see
       # wand_idle_riss for the derivation); the ring thickens and smears when the caster
       # runs, and re-forms into a clean ring the moment they stop.
       .with_emission(rate=constant(0.8), distance_rate=constant(1.0 / IDLE_PER_BLOCK))
       .with_module("inheritVelocity", inherit_velocity(IDLE_DRAG))
       .with_shape(cylinder(radius=0.35, thickness=0.1, arc_mode="Loop", arc_speed=0.6))
       .with_material(texture_material(CIRCLE, hdr=hdr(1.3, 0.5, 0.15), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            # 0.02 b/s lifted an ember 0.03 blocks over 25 t — the ring was flat. 0.35 b/s
            # carries it ~0.4 blocks, so the embers visibly peel UP off the ring.
            velocity_over_lifetime=dict(linear=nf3(constant(0), constant(0.35), constant(0))),
            color_over_lifetime=varied(  # white-hot -> deep red -> 0
                [(0.0, 0.0), (0.15, 1.0), (0.8, 0.7), (1.0, 0.0)],
                [(0.0, 1.0, 0.92, 0.75), (0.4, 1.0, 0.45, 0.12), (1.0, 0.35, 0.05, 0.02)],
                [(0.0, 1.0, 0.72, 0.4), (0.45, 0.95, 0.3, 0.06), (1.0, 0.22, 0.03, 0.01)]))
       .with_lights(sky=15, block=15))
    return fx


def build_wand_idle_stern() -> FxBuilder:
    """Star halo: tilted circle of near-static twinkling motes with hairline trails
    drawing constellation lines between slow drifters. Identity read (IDEAS-player #6 /
    PHOTON-QUALITY §2 row 2): actual 4-point-star sprites off star_2x2.png with the 2x2
    uvAnimation flipbook AS the twinkle — the hairlines now connect stars, not dots."""
    fx = FxBuilder("wand_idle_stern")
    # Wave-13 B6: this asset's headline feature — the constellation hairlines — could not
    # draw. The TRAIL config wants 0.02 blocks between vertices, and 0.01–0.03 b/s is
    # 0.0005–0.0015 blocks per tick: one vertex every 13–40 ticks, i.e. no line. 0.25–0.6
    # b/s (still a drift, ~0.4–0.7 blocks over the whole life) puts a vertex down roughly
    # every tick and the halo finally draws lines between its stars. `inheritVelocity`
    # drag then turns those lines into motion streaks while the caster runs. (The trail's
    # own `time` is left alone: `TrailsSetting.setup` always installs a lifetimeSupplier
    # of `trails.lifetime × particleLifetime / 20` s, so the hairline already spans the
    # star's whole path — the missing ingredient was only ever the vertices.)
    (fx.particle_emitter("star_halo",
            duration=60, looping=True, prewarm=10, start_lifetime=random_between(30, 45),
            start_speed=random_between(0.2, 0.5),
            start_size=nf3(random_between(0.05, 0.08), random_between(0.05, 0.08),
                           random_between(0.05, 0.08)),
            simulation_space="Local", max_particles=32)
       .with_emission(rate=constant(0.4), distance_rate=constant(1.0 / IDLE_PER_BLOCK))
       .with_module("inheritVelocity", inherit_velocity(IDLE_DRAG))
       .with_shape(circle(radius=0.4, thickness=0.3), rotation=nf3(20.0, 0.0, 0.0))
       .with_material(texture_material(STAR_2X2, hdr=hdr(1.0, 1.0, 1.6), blend=BLEND_ADDITIVE))
       .with_cull_box((-2.0, -2.0, -2.0), (2.0, 2.0, 2.0))
       .with_curves(
            # Flipbook twinkle: steppy off-chord tracks re-pick the 4 star frames on a
            # per-particle rhythm (frames vary arm length + gain — the sparkle itself).
            uv_animation=dict(tiles=(2, 2), animation="WholeSheet",
                              frame_over_time=random_curve(
                                  0.0, 1.0,
                                  [(0.0, 0.05, 0.25, 0.9, 0.45, 0.1, 0.65, 0.7),
                                   (0.65, 0.7, 0.75, 0.0, 0.9, 0.95, 1.0, 0.25)],
                                  [(0.0, 0.6, 0.2, 0.05, 0.4, 1.0, 0.55, 0.15),
                                   (0.55, 0.15, 0.7, 0.85, 0.85, 0.05, 1.0, 0.5)],
                                  "lifetime"),
                              start_frame=random_between(0.0, 3.0), cycle=3.0),
            noise=dict(frequency=0.5, quality="Noise2D",
                       position=nf3(constant(0.01), constant(0.01), constant(0.01)),
                       rotation=constant(0), size=constant(0)),
            size_over_lifetime=curve(  # double-hump twinkle
                0.3, 1.0, [(0.0, 0.4, 0.2, 1.0, 0.3, 0.2, 0.5, 0.9),
                           (0.5, 0.9, 0.7, 0.1, 0.9, 1.0, 1.0, 0.2)], "lifetime", "size"),
            color_over_lifetime=varied(
                [(0.0, 0.0), (0.2, 1.0), (0.8, 0.8), (1.0, 0.0)],
                [(0.0, 0.95, 0.95, 1.0), (1.0, 0.75, 0.85, 1.0)],
                [(0.0, 0.8, 0.86, 1.0), (1.0, 0.95, 0.8, 0.7)]))
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
    "stern_komet_touchdown.fx": build_stern_komet_touchdown,
    "stern_komet_impact.fx": build_stern_komet_impact,
    "stern_komet_crater_glow.fx": build_stern_komet_crater_glow,
    "stern_komet_ember_motes.fx": build_stern_komet_ember_motes,
    "stern_komet_star_glint.fx": build_stern_komet_star_glint,
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
    write_star_2x2(STAR_TEXTURE)
    print(f"WROTE {STAR_TEXTURE.relative_to(REPO_ROOT)}")
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
