#!/usr/bin/env python3
"""Shadow Bolt texture driver (P6-W910, MB3 polish).

The Eclipse Cultist's (and Rift Warden's) projectile: a tiny spike-orb — a 3px
violet-white flame core (`glow_core`) skewered by three dark obsidian spike shafts
whose tips pick up the core's light. Canvas 32x32; the whole entity renders
fullbright + glow-layered (`ShadowBoltRenderer`), so the albedo IS the look.

MB3 added the flight silhouette: the spear on the nose (the `glow_lance` collar stepping
down into the thinner `glow_tip` needle, together reaching ~2.5px past the spike shafts
— any longer and the bolt reads as a rocket rather than an orb) and the two
`glow_wake_*` shards that trail off the back. All of them are painted along the model's
Z axis — hot at the -Z (nose) end, cold at +Z — so the continuous `spin` never flickers
between a hot and a cold face.

Emissive (glowmask): the core (auto via `glow_` prefix), the spike tip pixels
(custom glow painter), the lance and the wake shards (custom painters with an alpha
ramp along Z: the glow layer blends SRC_ALPHA/ONE_MINUS_SRC_ALPHA, so glowmask alpha
is a real strength dial — unlike the albedo, which the entity render type
(`entityCutoutNoCull`) alpha-TESTS, i.e. treats as on/off).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/shadow_bolt.py
Writes src/main/resources/assets/eclipse/textures/entity/shadow_bolt.png + _glowmask.png.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, flame, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/shadow_bolt.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/shadow_bolt.png"

SEED = 0x5AD00B17  # shadow bolt

CORE = hexc("#EFE3FF")
CORE_TIP = hexc("#B98CFF")
SPIKE = hexc("#232030")
SPIKE_TIP = hexc("#B98CFF")
LANCE_HOT = hexc("#E4D5FF")
LANCE_MID = hexc("#9F6EEB")
LANCE_COLD = hexc("#3B2861")
WAKE_HOT = hexc("#C6A6FF")
WAKE_COLD = hexc("#2A1D45")


def _z_t(px):
    """Position along the model Z axis: 1.0 at the -Z nose, 0.0 at the +Z tail.

    The face->axis mapping is measured, not assumed: the MB3 harness dumps every baked
    GeoQuad's texU/texV against its vertex positions, and for a box-UV cube it reports
    +fy -> -Z on `up`/`down`, +fx -> -Z on `east`, +fx -> +Z on `west`, with `north`
    the -Z cap and `south` the +Z cap. Painting the whole longitudinal ramp off this
    one helper is what keeps the spinning lance from strobing.
    """
    if px.face == "north":
        return 1.0
    if px.face == "south":
        return 0.0
    if px.face in ("up", "down"):
        span, i = px.fh, px.fy
    else:
        span, i = px.fw, px.fx
    if span <= 1:
        return 0.5
    t = i / (span - 1.0)
    return 1.0 - t if px.face == "west" else t


def _is_tip(px):
    """Tip pixels: the extreme cells along each spike's long axis (fw==6 rects run
    along the shaft; 1x1 end caps are tips outright)."""
    if px.fw >= 6:
        return px.fx == 0 or px.fx == px.fw - 1
    if px.fh >= 6:
        return px.fy == 0 or px.fy == px.fh - 1
    return px.fw <= 1 and px.fh <= 1


def spike(px):
    """Obsidian spike shaft: near-black with a violet-lit tip on both ends."""
    if _is_tip(px):
        return mix(SPIKE_TIP, CORE, 0.3)
    col = mul(SPIKE, 0.85 + px.noise(13) * 0.3)
    return col


def spike_glow(px):
    """Glowmask: only the spike tips catch the core light."""
    if _is_tip(px):
        return with_alpha(SPIKE_TIP, 210)
    return None


def lance(t0, t1):
    """The nose spear: white-hot at the point, cooling to bruised violet where it sinks
    into the core, with a darker heat band so the spin reads as rotation and not a
    smooth blur.

    The spear is two bones — the `glow_lance` collar and the thinner `glow_tip` needle —
    so each gets the slice `[t0, t1]` of ONE continuous ramp. Painting each cube 0..1 in
    isolation would put a cold seam where the needle meets the collar.
    """
    def fn(px):
        t = t0 + (t1 - t0) * _z_t(px)
        col = mix(LANCE_COLD, LANCE_MID, min(1.0, t * 1.2))
        # Only the front third goes pale. The glow layer adds on top of the albedo, so a
        # spear painted white along its whole length composites to a solid white baton
        # and the mob stops reading as a SHADOW bolt (caught on the MB3 flight render).
        if t > 0.7:
            col = mix(col, LANCE_HOT, (t - 0.7) / 0.3)
        # Heat band one texel back from the point, so the spin reads as rotation rather
        # than a smooth blur. Needs a face at least 3 texels long — on the 2-texel
        # collar/needle it would land ON the hot tip and mute it instead.
        if px.face in ("up", "down", "east", "west") and px.fw > 2 and px.fh > 2:
            ring = px.fy if px.face in ("up", "down") else px.fx
            if ring == 1:
                col = mul(col, 0.86)
        return mul(col, 0.93 + px.noise(31) * 0.14)
    fn.shadeless = True
    return fn


def lance_glow(t0, t1):
    """Glowmask for one slice of the spear: burns hardest at the point and fades out
    towards the core, where `glow_core` already carries the brightness."""
    def fn(px):
        t = t0 + (t1 - t0) * _z_t(px)
        return with_alpha(mix(LANCE_MID, LANCE_HOT, t), int(50 + t * 165))
    return fn


def wake(px):
    """Trailing shard: bright where it peels off the bolt (-Z), guttering to a nearly
    black violet at the far end. No alpha ramp — the albedo is alpha-TESTED, so a
    partial alpha would render fully opaque anyway; the fade lives in the glowmask."""
    t = _z_t(px)
    return mul(mix(WAKE_COLD, WAKE_HOT, t * t), 0.92 + px.noise(37) * 0.16)


wake.shadeless = True


def wake_glow(px):
    """Glowmask: a steep ramp so the shard reads as a spark being left behind rather
    than a solid bar welded to the bolt."""
    t = _z_t(px)
    return with_alpha(mix(WAKE_COLD, WAKE_HOT, t), int(30 + t * t * 200))


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("glow_core", flame(CORE, CORE_TIP))
    painter.set_material("spikes", spike)
    painter.set_material("glow_lance", lance(0.30, 0.62))
    painter.set_material("glow_tip", lance(0.62, 1.0))
    painter.set_material("glow_wake_*", wake)
    painter.set_glow_painter("spikes", spike_glow)
    painter.set_glow_painter("glow_lance", lance_glow(0.30, 0.62))
    painter.set_glow_painter("glow_tip", lance_glow(0.62, 1.0))
    painter.set_glow_painter("glow_wake_*", wake_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
