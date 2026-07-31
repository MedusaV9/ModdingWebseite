#!/usr/bin/env python3
"""Shared painting helpers for the GLITCHED family (P6-W8 — glitched_husk/hound/tick).

Design language (plan §2.3 "glitched"): desaturated `#4A4A52`-family bodies with 1px
RGB-split fringes (`#FF3B6B` magenta / `#37F2E5` cyan) on cube edges; the `_alt.png`
flicker variant of every texture re-runs the SAME materials with ``alt=True``, which
adds hue-shifted magenta/cyan scanline bands and horizontal scanline-displacement
blocks so the renderer's 2–4 tick texture swap reads as a datamosh/corruption glitch
rather than a palette swap. Emissive: `glow_seam`/`glow_core` bones use the shadeless
:func:`seam` material; the magenta heart-core shining through torso cracks is a glow
painter (:func:`heart_glow`) stamped onto the body bone's glowmask.

MOB-GLITCH v2 additions (docs/plans_v3/plans_v5/fxteams/MOB-GLITCH.md):
:func:`glitch_body` gained datamosh run-length streaks (row segments locked to a stale
bright/dark value) and rare checkerboard corruption patches (4x4 macro-cells collapsing
into a 1px magenta/cyan checker — heavier on the alt frame); :func:`dropout` fakes
missing polygons via alpha holes (hound); :func:`glitch_scars` stamps sparse emissive
scar slivers into glowmasks; :func:`combine_glow` stacks glow painters per bone.

MB4 (F-098) addition — the FAMILY JITTER CLOCK: the one shared tremor frequency that
makes husk/hound/tick read as ONE corruption (census §5 row MB4, "Familien-Kohärenz").
:data:`GLITCH_JITTER_FREQ` is the canonical Molang frequency (``math.sin`` works in
DEGREES, ``query.anim_time`` in seconds — 720 °/s = 2.0 Hz) and
:func:`assert_family_jitter` is the enforcement gate every glitch driver runs before
painting, so a drifted animation file fails the deterministic painter run loudly.

Not a driver — imported by `glitched_husk.py` / `glitched_hound.py` /
`glitched_tick.py` (each still writes its own 4 PNGs deterministically).
"""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from paint_lib import hexc, mix, mul, with_alpha  # noqa: E402

MAGENTA = hexc("#FF3B6B")
CYAN = hexc("#37F2E5")
WHITE = hexc("#F4F0FF")
HEART_CORE = hexc("#FF6BF2")
HEART_HALO = hexc("#C13BFF")

# ---------------------------------------------------------------------------
# family jitter clock (MB4) — the ANIMATION-side family contract
# ---------------------------------------------------------------------------
# One tremor clock for the whole family: 2.0 Hz. In GeckoLib Molang terms
# (math.sin takes DEGREES, query.anim_time is SECONDS) that is 720 °/s; the
# period is 0.5 s. Every glitch loop length sits on that 0.5-s grid (husk
# idle 3.0 / walk 1.0, hound idle 2.5 / walk 0.5, tick idle 2.0 / walk 0.5),
# so the shared tremor closes seamlessly in ALL of them. Fine rattles may use
# integer harmonics (1440 = 4 Hz); slow per-mob sway channels stay free but
# MUST close their own loop (freq multiple of 360/length — the MA6 lesson).
GLITCH_JITTER_HZ = 2.0
GLITCH_JITTER_FREQ = 360.0 * GLITCH_JITTER_HZ   # 720.0 — use THIS in Molang sin()
GLITCH_JITTER_PERIOD = 1.0 / GLITCH_JITTER_HZ   # 0.5 s — loop lengths sit on this grid
# Molang channels at/above this rate are "jitter class" and must be exact
# integer harmonics of GLITCH_JITTER_FREQ; slower ones are per-mob sway.
_JITTER_CLASS_MIN_FREQ = 300.0

_ANIM_DIR = Path(__file__).resolve().parents[3] \
    / "src/main/resources/assets/eclipse/animations/entity"
GLITCH_FAMILY_ANIMS = tuple(
    _ANIM_DIR / f"glitched_{kind}.animation.json" for kind in ("husk", "hound", "tick"))
_FREQ_RE = re.compile(r"query\.anim_time\s*\*\s*(-?\d+(?:\.\d+)?)")


def _molang_freqs(node):
    """All `query.anim_time * F` frequencies (absolute) in a channel subtree."""
    if isinstance(node, str):
        return [abs(float(f)) for f in _FREQ_RE.findall(node)]
    if isinstance(node, list):
        return [f for item in node for f in _molang_freqs(item)]
    if isinstance(node, dict):
        return [f for item in node.values() for f in _molang_freqs(item)]
    return []


def assert_family_jitter(paths=GLITCH_FAMILY_ANIMS):
    """Family-coherence gate (MB4): every glitch driver calls this before painting.

    Checks, for every ``loop: true`` animation of the family sheets:
      1. the loop length is an integer multiple of :data:`GLITCH_JITTER_PERIOD`;
      2. every Molang ``query.anim_time * F`` channel CLOSES the loop
         (``F * length ≡ 0 (mod 360)`` — otherwise the loop seam pops);
      3. every jitter-class frequency (≥ 300 °/s) is an exact integer harmonic
         of :data:`GLITCH_JITTER_FREQ` (720/1440/… — ONE family clock);
      4. the family tremor never sleeps: at least one channel per loop runs at a
         :data:`GLITCH_JITTER_FREQ` harmonic.

    Raises ``AssertionError`` with the offending animation/frequency."""
    problems = []
    for path in paths:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        for anim_name, anim in data.get("animations", {}).items():
            if anim.get("loop") is not True:
                continue  # one-shots don't loop — no seam/grid constraints
            length = float(anim.get("animation_length", 0.0))
            grid = length / GLITCH_JITTER_PERIOD
            if abs(grid - round(grid)) > 1e-6:
                problems.append(f"{anim_name}: length {length}s off the "
                                f"{GLITCH_JITTER_PERIOD}s family jitter grid")
            freqs = [f for bone in anim.get("bones", {}).values()
                     for channel in bone.values() for f in _molang_freqs(channel)]
            for freq in freqs:
                if abs((freq * length) % 360.0) > 1e-4 \
                        and abs((freq * length) % 360.0 - 360.0) > 1e-4:
                    problems.append(f"{anim_name}: sin freq {freq} does not close "
                                    f"the {length}s loop (seam pop)")
                if freq >= _JITTER_CLASS_MIN_FREQ:
                    harmonic = freq / GLITCH_JITTER_FREQ
                    if abs(harmonic - round(harmonic)) > 1e-6 or round(harmonic) < 1:
                        problems.append(f"{anim_name}: jitter-class freq {freq} is not "
                                        f"a harmonic of {GLITCH_JITTER_FREQ}")
            if not any(abs(f / GLITCH_JITTER_FREQ - round(f / GLITCH_JITTER_FREQ)) < 1e-6
                       and round(f / GLITCH_JITTER_FREQ) >= 1 for f in freqs):
                problems.append(f"{anim_name}: no channel on the family jitter clock "
                                f"({GLITCH_JITTER_FREQ} °/s)")
    if problems:
        raise AssertionError("family jitter contract violated:\n  "
                             + "\n  ".join(problems))
    return True


def glitch_body(base, salt=31, alt=False, tint=None):
    """Desaturated glitch flesh/hide with RGB-split edge fringes.

    ``alt=True`` = the flicker frame: scanline rows are horizontally displaced in
    blocks (noise re-sampled at a shifted x) and whole 2px bands hue-crush toward
    magenta/cyan. ``tint`` pre-mixes the base (used for displaced shard bones so the
    broken-off geometry reads corrupted even on the calm frame)."""
    if tint is not None:
        base = mix(base, tint, 0.14)

    def fn(px):
        gx = px.gx
        if alt:
            band = px.gy // 2
            roll = px.noise(salt + 9, x=band, y=0)
            if roll > 0.45:
                gx = px.gx + int(roll * 9.0) - 4  # displaced scanline block
        streak = px.noise(salt, x=gx, y=px.gy // 3)
        fine = px.noise(salt + 1, x=gx)
        col = mul(base, 1.0 + (0.7 * streak + 0.3 * fine - 0.5) * 0.34)
        # Datamosh run-length streak: an 8px row segment locks to one stale
        # bright/dark value, as if a macroblock row kept sliding with old motion
        # vectors. Row parity decides the direction so adjacent hits read smeared.
        run = px.noise(salt + 17, x=gx // 8, y=px.gy)
        if run > (0.80 if alt else 0.90):
            col = mul(col, 1.22 if px.gy % 2 == 0 else 0.78)
        # Checkerboard corruption patch: a 4x4 macro-cell collapses into a 1px
        # magenta/cyan checker — the classic corrupted-block read. Rare on the calm
        # frame (~3% of cells), a real infestation on the datamosh frame.
        cell = px.noise(salt + 23, x=px.gx // 4, y=px.gy // 4)
        if cell > (0.88 if alt else 0.97):
            checker = MAGENTA if (px.gx + px.gy) % 2 == 0 else CYAN
            col = mix(col, checker, 0.60 if alt else 0.45)
        if alt:
            band_t = px.noise(salt + 13, x=px.gy // 2, y=0)
            if band_t > 0.70:
                col = mix(col, MAGENTA, 0.42)
            elif band_t < 0.22:
                col = mix(col, CYAN, 0.38)
        edge_chance = 0.50 if alt else 0.82
        if px.fx == 0 and px.noise(salt + 3) > edge_chance:
            col = mix(col, CYAN, 0.65)
        elif px.fx == px.fw - 1 and px.noise(salt + 4) > edge_chance:
            col = mix(col, MAGENTA, 0.65)
        return col

    return fn


def dropout(fn, salt=71, alt=False, chance=0.05, alt_chance=0.11, block=3, keep_faces=()):
    """Missing-polygon corruption (hound): hash-gated ``block``x``block`` texel holes
    (returns None -> alpha 0). The family renders cutout + no-cull, so the discarded
    texels expose the cube's inner back faces — the model reads as if polygons failed
    to upload. Hole layout is IDENTICAL on both frames (keyed off the block grid, not
    ``alt``) so the damage feels structural; the alt frame only ADDS extra holes.
    ``keep_faces`` exempts faces that must stay watertight (eye rows, inner mouth)."""
    gate = alt_chance if alt else chance

    def wrapped(px):
        if px.face not in keep_faces \
                and px.noise(salt, x=px.gx // block, y=px.gy // block) < gate:
            return None
        return fn(px)

    return wrapped


def glitch_scars(salt=67, alt=False):
    """Glow painter: sparse emissive glitch scars — 1px vertical slivers (5px lane
    segments, ~4% of columns) in the seam palette at partial alpha, flaring brighter
    and denser on the datamosh frame. Stack onto body/limb bones via
    :func:`combine_glow` so the corruption looks carved in, not stickered on."""

    def fn(px):
        seg = px.noise(salt, x=px.gx, y=px.gy // 5)
        if seg < (0.93 if alt else 0.958):
            return None
        col = MAGENTA if px.noise(salt + 1, x=px.gx, y=px.gy // 5) > 0.5 else CYAN
        return with_alpha(mix(col, WHITE, 0.15), 170 if alt else 120)

    return fn


def combine_glow(*fns):
    """First-non-None glow-painter combinator (the painter resolves ONE glow painter
    per bone — this lets e.g. the heart-core and the scar pass share the body)."""

    def fn(px):
        for candidate in fns:
            got = candidate(px)
            if got is not None:
                return got
        return None

    return fn


def seam(alt=False, salt=41):
    """Emissive seam-sliver material for `glow_*` bones: magenta/cyan interleave,
    white-hot flecks. Shadeless — these pixels are the chromatic edge the flicker
    renderer leans on, and they must survive Iris albedo-dimming."""

    def fn(px):
        t = px.noise(salt, x=px.gy // 2, y=0)
        col = mix(MAGENTA, CYAN, 0.15 if t < 0.55 else 0.85)
        if alt:
            col = mix(col, WHITE, 0.30)
        return mix(col, WHITE, 0.10 + px.noise(salt + 2) * 0.25)

    fn.shadeless = True
    return fn


def heart_glow(face="north", cy_frac=0.45, radius=0.34, salt=47, alt=False):
    """Glow painter: the magenta heart-core visible THROUGH cracks in the given face
    (hash-gated so it reads as shine-through, not a sticker)."""

    def fn(px):
        if px.face != face:
            return None
        nx = (px.fx + 0.5) / px.fw - 0.5
        ny = (px.fy + 0.5) / px.fh - cy_frac
        d = (nx * nx + ny * ny) ** 0.5
        if d > radius:
            return None
        if px.noise(salt) < (0.28 if alt else 0.40):
            return None  # the crack gate — most pixels stay dark
        col = mix(HEART_CORE, HEART_HALO, min(1.0, d / radius))
        return with_alpha(col, int(255 * (1.0 - 0.6 * d / radius)))

    return fn


def glow_eyes(pixels, color=CYAN, salt=53):
    """Glow painter for pinpoint eyes: ``pixels`` = [(face, fx, fy), ...]."""
    wanted = set(pixels)

    def fn(px):
        if (px.face, px.fx, px.fy) in wanted:
            return mix(color, WHITE, 0.35)
        return None

    return fn
