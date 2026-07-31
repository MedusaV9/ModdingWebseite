#!/usr/bin/env python3
"""wand_overcharge_fx — FX-Wave-13 N5 "Wand-Overcharge-Bögen" (census §6 row N5).

Three per-path assets, one WINDOWED entity loop each:

    eclipse:wand_overcharge_riss    void arcs   (deep violet -> glitch cyan/magenta)
    eclipse:wand_overcharge_glut    ember arcs  (white-gold -> amber -> deep red)
    eclipse:wand_overcharge_stern   star arcs   (ice white -> star cyan -> pale gold)

The client controller is `client/wand/WandOverchargeClient`: it keeps ONE of these
attached to the local player via `PhotonBridge.ensureAttachedFx` while the wand's Veil
charge is FULL (hysteresis: on at 100 %, off below 95 %), picking the asset from the
stack's synced `WAND_PATH` component.

THE HAND POINT LIVES IN THIS FILE, NOT IN THE CONTROLLER (the in-game finding that cost
the first N5 pass). Photon's `EntityEffectExecutor` places the effect at
`entity.getEyePosition() + executor.offset` with the offset in WORLD AXES, and
`AutoRotate.LOOK` only rotates the effect ROOT — it does NOT rotate the spawn offset.
A constant spawn offset is therefore a fixed COMPASS direction off the eye: it happens to
sit at the hand while the caster faces one way and swings out to the other side when they
turn (and lands behind the camera in first person, i.e. invisible). A persistent loop
cannot re-spawn on every yaw change, so the offset is baked into the emitters' local
positions instead and Photon's own root rotation carries it.

The LOOK frame's axes (read off `EntityEffectExecutor.updateFXObjectFrame`, which rotates
by `atan2(-look.z, look.x)` about Y) are: local +X = FORWARD, local +Z = RIGHT,
local +Y = up. {HAND_LOCAL} is therefore the same hand point `WandPowers.castFlourish`
fires the muzzle from (`eye + look*0.55 + side*0.35 - 0.25y`), expressed in that frame.

WHY THE ARCS ARE RIBBONS, NOT SPRITES: a lightning arc is a PATH. Photon can only draw a
path as a trail, so every bolt here is a near-invisible carrier mote whipped around the
hand by a fast orbital + a high-frequency `noise` position offset, dragging a short, hard
ARA_TRAIL ribbon behind it. The jitter IS the zig-zag; the carrier is deliberately dim
(the ribbon is the effect). Bolt lifetimes are 5-9 ticks, so the read is a STROBE of
short arcs rather than a continuous glow — an overcharge should look unstable.

MOVEMENT (`inheritVelocity`, the wave-13 A1 package): all three assets are LOCAL-space —
the arcs must stay welded to the hand. On a Local-space emitter the particle already
rides the executor transform, so the drag knob is a NEGATIVE multiply: the bolts lag ~40 %
of the caster's travel and smear backwards while sprinting ("die Bögen reißen mit"), then
snap back onto the hand when the player stops. `emission.distanceRate` tops the bolt count
up with travel for the same reason — both modules read the executor's per-tick position
delta, which an entity-attached executor actually has (a fixed world anchor does not).

BUDGET: this is a DAUER-PRÄSENZ effect — it is on for as long as the player walks around
with a full wand. Every asset stays under ~20 live particles, all emitters are cull-boxed,
HDR is capped at the wave-13 stacking ceiling ({HDR_CEILING}) and every ramp is born dark.

Run:  python3 tools/photon/wand_overcharge_fx.py
Then: python3 tools/photon/fxlib.py validate --lint
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fxlib import *  # noqa: F401,F403 - fxlib is the sanctioned star-import API

CIRCLE = "photon:textures/particle/circle.png"
STAR_2X2 = "eclipse:textures/particle/star_2x2.png"

#: Stacking-law HDR ceiling (FX_CENSUS_WAVE13 §8.4).
HDR_CEILING = 1.45
#: One loop cycle in ticks (short: the whole asset is a strobe).
LOOP_TICKS = 40
#: The casting hand in Photon's LOOK frame (+X forward, +Z right, +Y up — see the module
#: docstring). Every emitter is authored here so the arcs ride the hand through a turn.
HAND_LOCAL = (0.55, -0.25, 0.35)
#: Local cull AABB — the arcs never leave a ~1.5 b bubble around the hand.
CULL = ((-1.0, -1.75, -1.15), (2.1, 1.25, 1.85))
#: Local-space drag multiply — the bolts lag this share of the caster's travel.
DRAG = -0.4
#: Blocks of caster travel per extra bolt (`emission.distanceRate`, blocks/particle).
BOLT_PER_BLOCK = 0.55
#: Shed-spark launch speed range (blocks/s). Bounded by the first-person near plane — see
#: the `arc_sparks` emitter comment. A range, not a value: each asset builds its own
#: `random_between` from it so the three never share one mutable node.
SPARK_SPEED = (1.1, 2.3)


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
    Negative multiply on a Local-space emitter = drag: the particle lags the transform it
    is already glued to (see the module docstring).
    """
    return {"mode": mode, "multiply": constant(float(multiply))}


def ribbon_renderer(material_entry, cull_box=None):
    """Renderer compound for EMBEDDED ara configs (trails module, FX_FORMAT §4.3).

    fxlib's `_RendererMixin` only serves standalone emitters; without this block the
    embedded ribbon falls back to the MISSING (pink) material.
    """
    cull = {"_enable": B(0)} if cull_box is None else {"_enable": B(1), "cullBox": aabb(*cull_box)}
    return {"materials": rom([material_entry]), "layer": "Translucent",
            "cull": cull, "orderInLayer": I(0), "vertexSortingMode": "NONE"}


# ---------------------------------------------------------------------------
# Shared envelopes. All control points sit genuinely off their chord so the lazy-linear
# lint (tolerance 0.02) never fires — and, more importantly, so an arc actually STROBES.
# ---------------------------------------------------------------------------
#: Bolt thickness over its own length: fat at the head, pinched, fat again, out to a point.
_BOLT_TAPER = [(0.0, 1.0, 0.1, 0.62, 0.24, 0.95, 0.42, 0.44),
               (0.42, 0.44, 0.6, 0.9, 0.84, 0.16, 1.0, 0.0)]
#: Bolt thickness over TIME: a hard on/off duty cycle — the arc breaks and re-strikes.
_BOLT_STRIKE = [(0.0, 1.0, 0.08, 0.24, 0.2, 0.9, 0.36, 0.18),
                (0.36, 0.18, 0.54, 1.0, 0.78, 0.1, 1.0, 0.55)]
#: Two out-of-phase pulse shapes for the halo (random_curve lerps per particle).
_PULSE_A = [(0.0, 0.3, 0.08, 1.0, 0.26, 0.55, 0.5, 0.92),
            (0.5, 0.92, 0.66, 0.4, 0.84, 1.0, 1.0, 0.18)]
_PULSE_B = [(0.0, 0.16, 0.14, 0.82, 0.34, 0.28, 0.55, 1.0),
            (0.55, 1.0, 0.7, 0.34, 0.88, 0.76, 1.0, 0.12)]


def build_overcharge(name, bolt_hdr, spark_hdr, halo_hdr, bolt_ramp, spark_ramp, halo_ramp,
                     spark_texture=CIRCLE) -> FxBuilder:
    """One per-path overcharge asset: bolt ribbons + shed sparks + a full-charge halo.

    `*_hdr` are authored HDR triples (clamped here), `*_ramp` the (alpha_pts, rgb_pts)
    pairs of the path's identity gradient — every one born dark, per the birth-tint law.
    """
    fx = FxBuilder(name)

    # ------------------------------------------------------------------ bolt ribbons
    # The arcs. Carrier motes are whipped around the hand by a fast orbital and a
    # high-frequency noise offset; the ARA_TRAIL they drag IS the bolt. Short lives +
    # the strike duty cycle make them flicker instead of glow.
    (fx.particle_emitter(
            "arc_bolts",
            duration=LOOP_TICKS, looping=True, prewarm=10,
            start_lifetime=random_between(5, 9), start_speed=constant(0.0),
            start_size=nf3(0.02), start_color=color(0x30FFFFFF),
            simulation_space="Local", max_particles=8)
       .at(*HAND_LOCAL)
       .with_emission(rate=constant(0.5), distance_rate=constant(BOLT_PER_BLOCK))
       .with_shape(sphere(radius=0.16, thickness=1.0))
       .with_material(texture_material(CIRCLE, blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_module("inheritVelocity", inherit_velocity(DRAG))
       .with_curves(
            velocity_over_lifetime=dict(
                orbital_mode="AngularVelocity",
                orbital=nf3(random_between(-2.4, 2.4), random_between(-3.6, 3.6),
                            random_between(-2.4, 2.4)),
                offset=nf3(0), radial=random_between(-1.6, 2.4)),
            # THE zig-zag: a strong, fast 3-D noise offset on a 5-9 tick life reads as a
            # jagged discharge path once the ribbon draws it.
            noise=dict(frequency=2.6, quality="Noise3D",
                       position=nf3(constant(0.16), constant(0.16), constant(0.16))))
       .with_module("trails", {
            "ratio": F(1.0),
            "lifetime": constant(0.45),
            "dieWithParticles": B(1),
            "sizeAffectsWidth": B(0),
            "sizeAffectsLifetime": B(0),
            "inheritParticleColor": B(0),
            "trailType": "ARA_TRAIL",
            "araConfig": {
                "space": "Local",
                "alignment": "View",
                "thickness": F(0.035),
                "smoothness": I(2),
                # highQualityCorners OFF: its miter compensation divides thickness by
                # max(dot, 0.15) and shreds a jittering path into vertical spikes
                # (the herald_shard_trail derivation — no ara trail in the tree uses it).
                "highQualityCorners": B(0),
                "time": F(0.3),           # SECONDS (the ara exception) — a 6-tick whip
                "minDistance": F(0.02),
                "textureMode": "Stretch",
                "thicknessOverLength": curve(0.0, 1.0, _BOLT_TAPER, "length", "thickness"),
                "thicknessOverTime": curve(0.15, 1.0, _BOLT_STRIKE),
                "colorOverLength": gradient(*bolt_ramp),
                "renderer": ribbon_renderer(
                    texture_material(CIRCLE, hdr=hdr(*bolt_hdr), blend=BLEND_ADDITIVE),
                    cull_box=CULL)}}))

    # ------------------------------------------------------------------ shed sparks
    # Every discharge throws a few stretched streaks off the hand. StretchedBillboard so
    # they read as motion, not as dots; they die in a third of a second.
    #
    # The speed is capped by the FIRST-PERSON camera, not by taste: the hand sits ~0.7 b
    # from the eye, so a spark that outruns that distance crosses the near plane and
    # smears a huge white streak across the middle of the screen. At 1.6-3.2 b/s over a
    # 3-7 tick life the reach is ~0.25-1.1 b — lively around the hand, and it never
    # reaches the face of a player who walks around like this all day.
    (fx.particle_emitter(
            "arc_sparks",
            duration=LOOP_TICKS, looping=True, prewarm=10,
            start_lifetime=random_between(3, 7), start_speed=random_between(*SPARK_SPEED),
            start_size=nf3(random_between(0.03, 0.06), random_between(0.03, 0.06),
                           random_between(0.03, 0.06)),
            simulation_space="Local", max_particles=14)
       .at(*HAND_LOCAL)
       .with_emission(rate=constant(0.8), distance_rate=constant(BOLT_PER_BLOCK))
       .with_shape(sphere(radius=0.12, thickness=1.0))
       .with_material(texture_material(spark_texture, hdr=hdr(*spark_hdr), blend=BLEND_ADDITIVE))
       .with_renderer(render_mode="StretchedBillboard", velocity_scale=0.55, length_scale=2.4,
                      vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_module("inheritVelocity", inherit_velocity(DRAG))
       .with_curves(
            velocity_over_lifetime=dict(speed_modifier=curve(
                0.15, 1.0, [SEG_DECAY_TAIL], "lifetime", "value")),
            size_over_lifetime=curve(0.2, 1.0, [SEG_POP_SHRINK], "lifetime", "size"),
            color_over_lifetime=gradient(*spark_ramp))
       .with_lights(sky=15, block=15))

    # ------------------------------------------------------------------ full-charge halo
    # The steady state signal: one soft pulsing bloom on the hand that says "the wand is
    # FULL" even while no bolt happens to be striking. Dim — the bolts are the show.
    #
    # THE SIZE IS SET BY THE FIRST-PERSON CAMERA, not by how it reads in F5. The hand sits
    # ~0.7 b from the eye, so an additive sprite of edge length s covers ~s/0.7 rad — at
    # the 0.5 b this emitter first shipped with, that is 40° of a 70° FOV and the "small
    # permanent garnish" turns into a white bloom over a quarter of the wielder's screen
    # (in F5, at ~4.5 b, the same sprite is a tasteful 60 px dot — which is exactly how the
    # bug got authored). {LOOP_TICKS}-tick lives at this size keep at most 4 of them
    # stacked, so the additive core no longer clips to white either.
    (fx.particle_emitter(
            "charge_halo",
            duration=LOOP_TICKS, looping=True, prewarm=10,
            start_lifetime=random_between(12, 20), start_speed=constant(0.0),
            start_size=nf3(random_between(0.15, 0.22)),
            simulation_space="Local", max_particles=4)
       .at(*HAND_LOCAL)
       .with_emission(rate=constant(0.24))
       .with_shape(sphere(radius=0.04, thickness=1.0))
       .with_material(texture_material(CIRCLE, hdr=hdr(*halo_hdr), blend=BLEND_ADDITIVE))
       .with_renderer(vertex_sorting="NONE")
       .with_cull_box(*CULL)
       .with_module("inheritVelocity", inherit_velocity(DRAG * 0.5))
       .with_curves(
            size_over_lifetime=random_curve(0.7, 1.12, _PULSE_A, _PULSE_B, "lifetime", "size"),
            color_over_lifetime=gradient(*halo_ramp))
       .with_lights(sky=15, block=15))
    return fx


# ---------------------------------------------------------------------------
# The three path identities (F-070 palette, mirrored from wandfx2_fx.py's header).
# ---------------------------------------------------------------------------
def build_overcharge_riss() -> FxBuilder:
    """RISS: void discharge — deep violet body, glitch-cyan head, magenta bite."""
    return build_overcharge(
        "wand_overcharge_riss",
        bolt_hdr=(1.0, 1.35, 1.45), spark_hdr=(0.95, 1.25, 1.45), halo_hdr=(0.72, 0.5, 1.2),
        bolt_ramp=([(0.0, 0.95), (0.35, 0.7), (0.78, 0.3), (1.0, 0.0)],
                   [(0.0, 0.86, 1.0, 1.0), (0.32, 0.31, 0.91, 1.0),
                    (0.72, 0.48, 0.31, 0.82), (1.0, 0.18, 0.08, 0.32)]),
        spark_ramp=([(0.0, 0.0), (0.14, 0.9), (0.7, 0.5), (1.0, 0.0)],
                    [(0.0, 0.16, 0.1, 0.28), (0.3, 0.7, 0.98, 1.0), (1.0, 0.48, 0.31, 0.82)]),
        halo_ramp=([(0.0, 0.0), (0.24, 0.34), (0.74, 0.24), (1.0, 0.0)],
                   [(0.0, 0.18, 0.14, 0.28), (0.4, 0.73, 0.55, 1.0), (1.0, 0.48, 0.31, 0.82)]))


def build_overcharge_glut() -> FxBuilder:
    """GLUT: ember discharge — white-gold core, amber body, deep-red decay."""
    return build_overcharge(
        "wand_overcharge_glut",
        bolt_hdr=(1.45, 0.95, 0.4), spark_hdr=(1.45, 0.85, 0.32), halo_hdr=(1.3, 0.62, 0.22),
        bolt_ramp=([(0.0, 0.95), (0.35, 0.72), (0.78, 0.32), (1.0, 0.0)],
                   [(0.0, 1.0, 0.96, 0.82), (0.3, 1.0, 0.7, 0.28),
                    (0.72, 0.72, 0.24, 0.06), (1.0, 0.26, 0.06, 0.02)]),
        spark_ramp=([(0.0, 0.0), (0.14, 0.92), (0.7, 0.48), (1.0, 0.0)],
                    [(0.0, 0.3, 0.14, 0.05), (0.28, 1.0, 0.88, 0.6), (1.0, 0.62, 0.14, 0.03)]),
        halo_ramp=([(0.0, 0.0), (0.24, 0.32), (0.74, 0.22), (1.0, 0.0)],
                   [(0.0, 0.26, 0.12, 0.04), (0.4, 1.0, 0.7, 0.36), (1.0, 0.72, 0.26, 0.08)]))


def build_overcharge_stern() -> FxBuilder:
    """STERN: starlight discharge — ice-white bolts, star-cyan body, pale-gold sparks."""
    return build_overcharge(
        "wand_overcharge_stern",
        bolt_hdr=(1.1, 1.28, 1.45), spark_hdr=(1.2, 1.24, 1.45), halo_hdr=(0.9, 1.02, 1.35),
        bolt_ramp=([(0.0, 0.95), (0.35, 0.72), (0.78, 0.3), (1.0, 0.0)],
                   [(0.0, 1.0, 1.0, 1.0), (0.34, 0.5, 0.9, 1.0),
                    (0.74, 0.62, 0.68, 0.94), (1.0, 0.2, 0.24, 0.42)]),
        spark_ramp=([(0.0, 0.0), (0.14, 0.9), (0.7, 0.46), (1.0, 0.0)],
                    [(0.0, 0.18, 0.2, 0.3), (0.3, 0.95, 0.98, 1.0), (1.0, 0.97, 0.89, 0.69)]),
        halo_ramp=([(0.0, 0.0), (0.24, 0.32), (0.74, 0.22), (1.0, 0.0)],
                   [(0.0, 0.16, 0.18, 0.28), (0.4, 0.8, 0.9, 1.0), (1.0, 0.56, 0.7, 0.94)]),
        spark_texture=STAR_2X2)


BUILDERS = {
    "wand_overcharge_riss.fx": build_overcharge_riss,
    "wand_overcharge_glut.fx": build_overcharge_glut,
    "wand_overcharge_stern.fx": build_overcharge_stern,
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
