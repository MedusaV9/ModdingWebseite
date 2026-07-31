#!/usr/bin/env python3
"""Sunmote texture driver (MC3 GeckoLib conversion, F-098 wave M-C).

Design sheet (docs/ideas/04_content.md §1.5 + census §2): the altar swarm wisp — a
captured spark of daylight orbiting the sanctum altar. The conversion replaces the
3-cube code model with a mini geo (10 bones): a `glow_core` shell with a `glow_kernel`
heartbeat nested inside it, an eight-point ray wreath (`glow_crown` carries the four
short 45° spikes as cubes, `glow_ray_a..d` are the four long individually-shimmering
rays) and a `halo` ring plate.

Palette (kept from the old art brief so the mote still reads the same at distance):
core `#FFF2C0` -> `#FFD98A`, kernel `#FFFBE8`, rays `#FFD874` -> `#FFC24A`, halo
`#FFC24A` / `#E08A22`.

Emissive: the Sunmote is a LIGHT BEING and — census falle F-7 — had no glowmask at all
before this pass (the old renderer faked it with a whole-model `RenderType.eyes` pass).
Everything under a `glow_` bone is auto-emissive at full painted brightness; the halo is
deliberately NOT (a custom glow painter lights only its inner edge + a speckled outer
rim, so the ring reads as metal CATCHING the core's light instead of a second sun).

Two geometry notes the materials depend on:
* The long faces of the ray/spike cubes are 1 texel tall (`1x1x3` / `1x1x2` cubes), and a
  Bedrock box-UV strip runs AROUND the cube — which end of a face is the outer tip flips
  per face. The ray material is therefore authored SYMMETRIC along its length (hot in the
  middle, cooling to both ends); that reads identically from every angle and can never be
  mirrored the wrong way round.
* The halo's up/down faces are painted as an ANNULUS (transparent core + cut corners), so
  the plate reads as a ring around the core rather than a lid on top of it. Alpha-0 texels
  are free here: the renderer stays on the cutout path (no `withTranslucency()`).

Run from the ProjectEclipse root (deterministic — reruns are byte-identical):
    python3 scripts/geckolib_gen/mobs/sunmote.py
Writes src/main/resources/assets/eclipse/textures/entity/sunmote.png + _glowmask.png.
"""

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import GeoPainter, hexc, mix, mul, with_alpha  # noqa: E402

ROOT = Path(__file__).resolve().parents[3]
GEO = ROOT / "src/main/resources/assets/eclipse/geo/entity/sunmote.geo.json"
OUT = ROOT / "src/main/resources/assets/eclipse/textures/entity/sunmote.png"

SEED = 0x0FFC24A5  # sunmote (halo amber)

KERNEL = hexc("#FFFBE8")
CORE_HOT = hexc("#FFF2C0")
CORE_EDGE = hexc("#FFD98A")
RAY_HOT = hexc("#FFE9A8")
RAY = hexc("#FFD874")
RAY_TIP = hexc("#FFC24A")
HALO = hexc("#FFC24A")
HALO_DEEP = hexc("#E08A22")
HALO_GLOW = hexc("#FFE29A")


def corona(px):
    """Core shell: a radial daylight gradient with a few hotter flare specks.

    Emissive regions must stay bright in the ALBEDO too (Iris dims glow layers to the
    albedo, P6 conventions §6), hence no dark pixels anywhere on this cube."""
    cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
    d = math.hypot((px.fx - cx) / max(cx, 0.5), (px.fy - cy) / max(cy, 0.5))
    col = mix(CORE_HOT, CORE_EDGE, min(1.0, d * 0.8))
    if px.noise(41) > 0.86:
        col = mix(col, KERNEL, 0.6)  # flare speck
    return col


corona.shadeless = True


def kernel(px):
    """Heartbeat kernel: near-white and uniform — it is only ever seen mid-flare, when
    the pulse scales it out THROUGH the core shell, so texture detail would just alias."""
    return KERNEL if px.noise(43) > 0.25 else mix(KERNEL, CORE_HOT, 0.35)


kernel.shadeless = True


def ray(px):
    """Wreath ray/spike: hottest along the middle of its length, cooling to both ends.
    The 1x1 end caps are the tips — always hot.

    NOTE: no alpha dropouts here. These faces are 2-3 texels long and 1 texel thin, so a
    single dropped texel is a THIRD of the ray missing on that face while the opposite
    face keeps it — that reads as broken geometry, not as flicker. The flicker lives in
    the animation (per-ray scale shimmer, 90°-phase-staggered) instead."""
    long_axis_len = max(px.fw, px.fh)
    if long_axis_len <= 1:
        return RAY_HOT  # 1x1 end cap
    pos = px.fx if px.fw >= px.fh else px.fy
    center = (long_axis_len - 1) / 2.0
    t = abs(pos - center) / max(center, 0.5)
    col = mix(RAY_HOT, mix(RAY, RAY_TIP, min(1.0, t * 1.4)), t)
    return col if px.noise(47) > 0.78 else mul(col, 1.08)


ray.shadeless = True


def halo_ring(px):
    """Halo plate as an ANNULUS: the 5x5 up/down faces get a transparent core and cut
    corners (so the ring is round, not square); the 5x1 side faces are the ring's rim."""
    if px.fw >= 4 and px.fh >= 4:
        cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
        d = math.hypot(px.fx - cx, px.fy - cy)
        if d < 1.35 or d > 2.35:
            return None  # inner opening / rounded-off corners
        col = mix(HALO, HALO_DEEP, (d - 1.35) / 1.0)
        return col if px.noise(53) > 0.2 else mul(col, 1.14)
    return mix(HALO, HALO_DEEP, px.noise(53) * 0.65)


def halo_glow(px):
    """Glowmask for the halo: only the ring's INNER edge burns (the side facing the
    core) plus a sparse speckle on the rim — the halo catches light, it is not a
    second sun. Runs instead of an albedo copy; texels the material dropped stay dark."""
    if px.fw >= 4 and px.fh >= 4:
        cx, cy = (px.fw - 1) / 2.0, (px.fh - 1) / 2.0
        d = math.hypot(px.fx - cx, px.fy - cy)
        if d < 1.35 or d > 2.35:
            return None
        if d < 1.9:
            return with_alpha(HALO_GLOW, 215)  # inner edge, lit by the core
        return with_alpha(HALO_GLOW, 90) if px.noise(59) > 0.55 else None
    return with_alpha(HALO_GLOW, 120) if px.noise(59) > 0.6 else None


def main():
    painter = GeoPainter(GEO, seed=SEED)
    painter.set_material("glow_core", corona)
    painter.set_material("glow_kernel", kernel)
    painter.set_material("glow_crown", ray)   # the four 45° short spikes
    painter.set_material("glow_ray_*", ray)   # the four long rays
    painter.set_material("halo", halo_ring)
    # glow_* bones are auto-included in the glowmask; the halo gets the catch-light
    # painter instead of an albedo copy.
    painter.set_glow_painter("halo", halo_glow)
    painter.paint(OUT)


if __name__ == "__main__":
    main()
