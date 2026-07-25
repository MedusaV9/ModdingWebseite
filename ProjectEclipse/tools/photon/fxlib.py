#!/usr/bin/env python3
"""fxlib — author Photon `.fx` effect files (gzip-compressed NBT) from Python.

Schema source of truth: docs/plans_v3/plans_v5/photon/FX_FORMAT.md (reverse-engineered
from photon-neoforge-1.21.1-2.1.5 bytecode, PHOTON-EXPLORE-2). This library ports and
expands the validated /tmp/build_fx.py generator: everything it writes matches the field
names, NBT tag types and enum constant strings read from the jar. Absent keys keep the
Java defaults, so files stay minimal; every module you enable writes `_enable: 1b`.

Quick start (see tools/photon/README.md for the full API table):

    from fxlib import *
    fx = FxBuilder("my_burst")
    (fx.particle_emitter("sparks", duration=40, looping=False, max_particles=256,
                         start_lifetime=random_between(18, 32),
                         start_speed=random_between(0.35, 0.85),
                         start_size=random_between(0.08, 0.16),
                         simulation_space="World")
       .with_emission(rate=0.0, bursts=[burst(time=0, count=40)])
       .with_shape(sphere(radius=0.35, thickness=0.0))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       hdr=(2.0, 1.2, 0.4), blend=BLEND_ADDITIVE))
       .with_curves(color_over_lifetime=gradient([(0, 1), (1, 0)], [(0, 1, 1, 1)]),
                    size_over_lifetime=curve(0.0, 1.5, [SEG_POP_SHRINK]))
       .with_physics(gravity=0.35, bounce_chance=0.6)
       .with_lights(15, 15))
    fx.write("src/main/resources/assets/eclipse/fx/my_burst.fx")   # validates round-trip

File id contract: `assets/eclipse/fx/<path>.fx`  <->  ResourceLocation `eclipse:<path>`
(loaded by Photon's FXHelper through the vanilla ResourceManager; no registration call).

CLI:
    python3 tools/photon/fxlib.py selfcheck          # build+round-trip both templates in temp
    python3 tools/photon/fxlib.py templates          # (re)generate the two smoke-test .fx assets
    python3 tools/photon/fxlib.py validate <f.fx>…   # parse + structure + round-trip any .fx
    python3 tools/photon/fxlib.py dump <f.fx>        # pretty-print the NBT tree
"""
from __future__ import annotations

import gzip
import io
import math
import struct
import sys
import uuid as _uuid
from pathlib import Path

# ---------------------------------------------------------------------------
# NBT tag model (wrapper classes preserve the exact tag type through round-trips)
# ---------------------------------------------------------------------------
TAG_END, TAG_BYTE, TAG_SHORT, TAG_INT, TAG_LONG, TAG_FLOAT, TAG_DOUBLE = 0, 1, 2, 3, 4, 5, 6
TAG_BYTE_ARRAY, TAG_STRING, TAG_LIST, TAG_COMPOUND, TAG_INT_ARRAY, TAG_LONG_ARRAY = 7, 8, 9, 10, 11, 12


class _Num:
    __slots__ = ("v",)

    def __init__(self, v):
        self.v = v

    def __eq__(self, other):
        return type(self) is type(other) and self.v == other.v

    def __hash__(self):
        return hash((type(self), self.v))

    def __repr__(self):
        return f"{type(self).__name__}({self.v})"


class B(_Num):
    """NBT Byte (also booleans: 0/1)."""


class Sh(_Num):
    """NBT Short."""


class I(_Num):  # noqa: E742 - matches the validated generator's naming
    """NBT Int."""


class Lg(_Num):
    """NBT Long."""


class F(_Num):
    """NBT Float (value quantized to float32 so round-trip comparisons are exact)."""

    def __init__(self, v):
        super().__init__(struct.unpack(">f", struct.pack(">f", v))[0])


class D(_Num):
    """NBT Double."""


class BA(_Num):
    """NBT ByteArray (v = bytes)."""


class IA(_Num):
    """NBT IntArray (v = list[int])."""


class LA(_Num):
    """NBT LongArray (v = list[int])."""


class L:
    """NBT List (homogeneous)."""

    __slots__ = ("items",)

    def __init__(self, items):
        self.items = list(items)

    def __eq__(self, other):
        return isinstance(other, L) and self.items == other.items

    def __repr__(self):
        return f"L({self.items!r})"


def tag_type(v):
    if isinstance(v, B):
        return TAG_BYTE
    if isinstance(v, Sh):
        return TAG_SHORT
    if isinstance(v, I):
        return TAG_INT
    if isinstance(v, Lg):
        return TAG_LONG
    if isinstance(v, F):
        return TAG_FLOAT
    if isinstance(v, D):
        return TAG_DOUBLE
    if isinstance(v, BA):
        return TAG_BYTE_ARRAY
    if isinstance(v, str):
        return TAG_STRING
    if isinstance(v, L):
        return TAG_LIST
    if isinstance(v, dict):
        return TAG_COMPOUND
    if isinstance(v, IA):
        return TAG_INT_ARRAY
    if isinstance(v, LA):
        return TAG_LONG_ARRAY
    raise TypeError(f"not an NBT value: {v!r} ({type(v).__name__})")


# ---------------------------------------------------------------------------
# NBT writer
# ---------------------------------------------------------------------------
def _write_payload(out, v):
    t = tag_type(v)
    if t == TAG_BYTE:
        out.write(struct.pack(">b", v.v))
    elif t == TAG_SHORT:
        out.write(struct.pack(">h", v.v))
    elif t == TAG_INT:
        out.write(struct.pack(">i", v.v))
    elif t == TAG_LONG:
        out.write(struct.pack(">q", v.v))
    elif t == TAG_FLOAT:
        out.write(struct.pack(">f", v.v))
    elif t == TAG_DOUBLE:
        out.write(struct.pack(">d", v.v))
    elif t == TAG_BYTE_ARRAY:
        out.write(struct.pack(">i", len(v.v)))
        out.write(bytes(v.v))
    elif t == TAG_STRING:
        b = v.encode("utf-8")
        out.write(struct.pack(">H", len(b)))
        out.write(b)
    elif t == TAG_LIST:
        et = tag_type(v.items[0]) if v.items else TAG_END
        out.write(struct.pack(">bi", et, len(v.items)))
        for it in v.items:
            if tag_type(it) != et:
                raise TypeError(f"heterogeneous NBT list: {v.items!r}")
            _write_payload(out, it)
    elif t == TAG_COMPOUND:
        for k, val in v.items():
            out.write(struct.pack(">b", tag_type(val)))
            kb = k.encode("utf-8")
            out.write(struct.pack(">H", len(kb)))
            out.write(kb)
            _write_payload(out, val)
        out.write(b"\x00")
    elif t == TAG_INT_ARRAY:
        out.write(struct.pack(">i", len(v.v)))
        for x in v.v:
            out.write(struct.pack(">i", x))
    elif t == TAG_LONG_ARRAY:
        out.write(struct.pack(">i", len(v.v)))
        for x in v.v:
            out.write(struct.pack(">q", x))


def write_root(compound: dict) -> bytes:
    """Serializes a root compound to raw (uncompressed) NBT bytes (nameless root, like NbtIo)."""
    out = io.BytesIO()
    out.write(struct.pack(">b", TAG_COMPOUND))
    out.write(struct.pack(">H", 0))
    _write_payload(out, compound)
    return out.getvalue()


# ---------------------------------------------------------------------------
# NBT reader (round-trip validation; also parses editor-exported .fx files)
# ---------------------------------------------------------------------------
def _read_payload(buf: io.BytesIO, t: int):
    if t == TAG_BYTE:
        return B(struct.unpack(">b", buf.read(1))[0])
    if t == TAG_SHORT:
        return Sh(struct.unpack(">h", buf.read(2))[0])
    if t == TAG_INT:
        return I(struct.unpack(">i", buf.read(4))[0])
    if t == TAG_LONG:
        return Lg(struct.unpack(">q", buf.read(8))[0])
    if t == TAG_FLOAT:
        return F(struct.unpack(">f", buf.read(4))[0])
    if t == TAG_DOUBLE:
        return D(struct.unpack(">d", buf.read(8))[0])
    if t == TAG_BYTE_ARRAY:
        n = struct.unpack(">i", buf.read(4))[0]
        return BA(buf.read(n))
    if t == TAG_STRING:
        n = struct.unpack(">H", buf.read(2))[0]
        return buf.read(n).decode("utf-8")
    if t == TAG_LIST:
        et, n = struct.unpack(">bi", buf.read(5))
        return L([_read_payload(buf, et) for _ in range(n)])
    if t == TAG_COMPOUND:
        result = {}
        while True:
            ct = struct.unpack(">b", buf.read(1))[0]
            if ct == TAG_END:
                return result
            kn = struct.unpack(">H", buf.read(2))[0]
            key = buf.read(kn).decode("utf-8")
            result[key] = _read_payload(buf, ct)
    if t == TAG_INT_ARRAY:
        n = struct.unpack(">i", buf.read(4))[0]
        return IA([struct.unpack(">i", buf.read(4))[0] for _ in range(n)])
    if t == TAG_LONG_ARRAY:
        n = struct.unpack(">i", buf.read(4))[0]
        return LA([struct.unpack(">q", buf.read(8))[0] for _ in range(n)])
    raise ValueError(f"unknown NBT tag type {t}")


def read_root(raw: bytes) -> dict:
    """Parses raw NBT bytes back into the wrapper-class tree (inverse of write_root)."""
    buf = io.BytesIO(raw)
    t = struct.unpack(">b", buf.read(1))[0]
    if t != TAG_COMPOUND:
        raise ValueError(f"root tag is {t}, expected compound")
    name_len = struct.unpack(">H", buf.read(2))[0]
    buf.read(name_len)
    root = _read_payload(buf, TAG_COMPOUND)
    if buf.read(1):
        raise ValueError("trailing bytes after root compound")
    return root


def read_fx_file(path) -> dict:
    """Reads a gzip-compressed .fx file into the wrapper-class tree."""
    return read_root(gzip.decompress(Path(path).read_bytes()))


# ---------------------------------------------------------------------------
# Value coercion + NumberFunction helpers (registry photon:number_function)
# ---------------------------------------------------------------------------
def _num(v):
    """Python number -> NBT numeric tag (int -> Int, float -> Float); wrappers pass through."""
    if isinstance(v, (B, Sh, I, Lg, F, D)):
        return v
    if isinstance(v, bool):
        return B(1 if v else 0)
    if isinstance(v, int):
        return I(v)
    if isinstance(v, float):
        return F(v)
    raise TypeError(f"not a number: {v!r}")


def _signed32(argb: int) -> int:
    """0xFFFFFFFF-style unsigned ARGB -> Java signed int."""
    argb &= 0xFFFFFFFF
    return argb - 0x100000000 if argb > 0x7FFFFFFF else argb


def _bool(v) -> B:
    return B(1 if v else 0)


def constant(n):
    """NumberFunction `constant` — fixed value (Int/Float tag type preserved)."""
    return {"type": "constant", "data": {"number": _num(n)}}


def random_between(a, b):
    """NumberFunction `random_constant` — uniform random in [a,b], memoized per particle."""
    return {"type": "random_constant", "data": {"a": _num(a), "b": _num(b)}}


def curve(lower, upper, segments, x_axis="duration", y_axis="value", lock=True):
    """NumberFunction `curve`: value = lower + (upper-lower) * bezierY(t).

    segments: list of 8-float tuples (p0x,p0y,c0x,c0y,c1x,c1y,p1x,p1y), x/y normalized 0..1.
    """
    return {"type": "curve", "data": {
        "min": F(float(lower)), "max": F(float(upper)),
        "lower": F(float(lower)), "upper": F(float(upper)),
        "xAxis": x_axis, "yAxis": y_axis, "lockControlPoint": _bool(lock),
        "curves": L([L([F(float(x)) for x in seg]) for seg in segments])}}


def random_curve(lower, upper, segments0, segments1, x_axis="duration", y_axis="value", lock=True):
    """NumberFunction `random_curve` — random lerp between two curves (roll memoized per particle)."""
    return {"type": "random_curve", "data": {
        "min": F(float(lower)), "max": F(float(upper)),
        "lower": F(float(lower)), "upper": F(float(upper)),
        "xAxis": x_axis, "yAxis": y_axis, "lockControlPoint": _bool(lock),
        "curves0": L([L([F(float(x)) for x in seg]) for seg in segments0]),
        "curves1": L([L([F(float(x)) for x in seg]) for seg in segments1])}}


def color(argb=0xFFFFFFFF):
    """NumberFunction `color` — fixed ARGB tint (-1 / 0xFFFFFFFF = opaque white)."""
    return {"type": "color", "data": {"number": I(_signed32(argb))}}


def random_color(argb_a, argb_b):
    """NumberFunction `random_color` — random ARGB lerp between two colors."""
    return {"type": "random_color", "data": {"a": I(_signed32(argb_a)), "b": I(_signed32(argb_b))}}


def _gradient_color(alpha_pts, rgb_pts) -> dict:
    """GradientColor: a = flat (t, alpha) pairs; rgb = flat (t, r, g, b) — floats 0..1."""
    a, rgb = [], []
    for t, al in alpha_pts:
        a += [F(float(t)), F(float(al))]
    for t, r, g, b_ in rgb_pts:
        rgb += [F(float(t)), F(float(r)), F(float(g)), F(float(b_))]
    return {"a": L(a), "rgb": L(rgb)}


def gradient(alpha_pts, rgb_pts):
    """NumberFunction `gradient` — color over the module's input axis.

    alpha_pts: [(t, alpha), ...]; rgb_pts: [(t, r, g, b), ...] — all floats 0..1.
    """
    return {"type": "gradient", "data": {"gradientColor": _gradient_color(alpha_pts, rgb_pts)}}


def random_gradient(alpha_pts0, rgb_pts0, alpha_pts1, rgb_pts1):
    """NumberFunction `random_gradient` — random lerp between two gradients."""
    return {"type": "random_gradient", "data": {
        "gradientColor0": _gradient_color(alpha_pts0, rgb_pts0),
        "gradientColor1": _gradient_color(alpha_pts1, rgb_pts1)}}


def _is_nf(v) -> bool:
    return isinstance(v, dict) and "type" in v and "data" in v


def _nf(v):
    """Coerces a python scalar or an NF dict into a NumberFunction wrapper."""
    if _is_nf(v):
        return v
    return constant(v)


def nf3(x, y=None, z=None):
    """NumberFunction3 = List of exactly 3 NF wrappers (x, y, z).

    Accepts: nf3(scalar) uniform, nf3(x, y, z) with scalars or NF dicts, or an existing
    3-item list/tuple. NOTE: passing ONE random NF as a uniform value copies it per axis,
    which Photon rolls independently — build three identical dicts deliberately if wanted.
    """
    if isinstance(x, L):
        return x
    if y is None and z is None:
        if isinstance(x, (list, tuple)):
            if len(x) != 3:
                raise ValueError(f"nf3 needs exactly 3 entries, got {len(x)}")
            return L([_nf(v) for v in x])
        return L([_nf(x), _nf(x), _nf(x)])
    return L([_nf(x), _nf(y), _nf(z)])


ZERO3 = None  # placeholder; use nf3(0) at call sites (kept for readability of ports)


# ---------------------------------------------------------------------------
# Shapes (registry photon:shape) — emission volume + initial velocity direction
# ---------------------------------------------------------------------------
def _shape_arc(mode="Random", spread=0.0, speed=1.0):
    """arcMode: Random | Loop | PingPong | BurstSpread (Unity arc emission modes)."""
    return {"arcMode": mode, "arcSpread": F(float(spread)), "arcSpeed": _nf(speed)}


def dot():
    """Point emission, zero spread."""
    return {"type": "dot", "data": {}}


def sphere(radius=0.5, thickness=1.0, arc=360.0, arc_mode="Random", arc_spread=0.0, arc_speed=1.0):
    """Sphere volume/shell (thickness 0 = surface only); velocity = radial."""
    return {"type": "sphere", "data": {
        "radius": F(float(radius)), "radiusThickness": F(float(thickness)), "arc": F(float(arc)),
        "shapeArc": _shape_arc(arc_mode, arc_spread, arc_speed)}}


def circle(radius=0.5, thickness=1.0, arc=360.0, arc_mode="Random", arc_spread=0.0, arc_speed=1.0):
    """XZ ring/disc."""
    return {"type": "circle", "data": {
        "radius": F(float(radius)), "radiusThickness": F(float(thickness)), "arc": F(float(arc)),
        "shapeArc": _shape_arc(arc_mode, arc_spread, arc_speed)}}


def cone(angle=25.0, radius=0.5, thickness=1.0, arc=360.0, arc_mode="Random", arc_spread=0.0, arc_speed=1.0):
    """Classic fountain cone."""
    return {"type": "cone", "data": {
        "angle": F(float(angle)), "radius": F(float(radius)),
        "radiusThickness": F(float(thickness)), "arc": F(float(arc)),
        "shapeArc": _shape_arc(arc_mode, arc_spread, arc_speed)}}


def cylinder(radius=0.5, thickness=1.0, arc=360.0, arc_mode="Random", arc_spread=0.0, arc_speed=1.0):
    """Volume column (thin thickness = ring wall)."""
    return {"type": "cylinder", "data": {
        "radius": F(float(radius)), "radiusThickness": F(float(thickness)), "arc": F(float(arc)),
        "shapeArc": _shape_arc(arc_mode, arc_spread, arc_speed)}}


def box(emit_from="Volume"):
    """Unit cube scaled by the shape scale. emit_from: Volume | Shell | Edge."""
    return {"type": "box", "data": {"emitFrom": emit_from}}


def mesh(model="block/stone", emit_from="Triangle"):
    """Emit from a baked block/item model's geometry. emit_from: Vertex | Edge | Triangle."""
    return {"type": "mesh", "data": {"type": emit_from, "meshData": {"modelLocation": model}}}


def function_shape(x="0", y="0", z="0", speed_x="0", speed_y="0", speed_z="0"):
    """Math-expression shape (photon expr language: t, PI, randomA..E, sin/cos/…, ?:).

    Example spiral: function_shape(x="0.8*cos(t*2*PI)", z="0.8*sin(t*2*PI)", y="t*2").
    """
    return {"type": "function", "data": {
        "x": x, "y": y, "z": z, "speedX": speed_x, "speedY": speed_y, "speedZ": speed_z}}


# ---------------------------------------------------------------------------
# Materials (registry photon:material) + blend modes
# ---------------------------------------------------------------------------
def blend(src_color="SRC_ALPHA", dst_color="ONE", src_alpha="ONE", dst_alpha="ZERO",
          func="ADD", enable=True):
    """GL blend state; factor names are GL enum strings, func: ADD|SUB|REVERSE_SUB|MIN|MAX."""
    return {"enableBlend": _bool(enable),
            "srcColorFactor": src_color, "dstColorFactor": dst_color,
            "srcAlphaFactor": src_alpha, "dstAlphaFactor": dst_alpha, "blendFunc": func}


BLEND_ADDITIVE = blend("SRC_ALPHA", "ONE", "ONE", "ZERO", "ADD")
BLEND_ALPHA = blend("SRC_ALPHA", "ONE_MINUS_SRC_ALPHA", "ONE", "ZERO", "ADD")


def _hdr_vec(hdr) -> L:
    """hdr: None -> off, (r,g,b) -> [r,g,b,1], (r,g,b,a) -> as-is. RGB boost feeds bloom."""
    if hdr is None:
        return L([F(0.0), F(0.0), F(0.0), F(1.0)])
    vals = list(hdr) + [1.0] * (4 - len(hdr))
    return L([F(float(v)) for v in vals[:4]])


def _material_entry(material, blend_mode, cull, depth_test, depth_mask):
    return {"material": material,
            "blendMode": dict(blend_mode),
            "cull": _bool(cull), "depthTest": _bool(depth_test), "depthMask": _bool(depth_mask)}


def texture_material(texture="photon:textures/particle/circle.png", discard=0.05,
                     hdr=None, hdr_mode="ADDITIVE", pixel_art=False, pixel_art_bits=8,
                     blend=None, cull=True, depth_test=True, depth_mask=False):
    """Standalone PNG material. `hdr=(r,g,b)` boosts emission into the bloom pipeline."""
    pa = {"_enable": _bool(pixel_art)}
    if pixel_art:
        pa["bits"] = I(int(pixel_art_bits))
    mat = {"type": "texture", "data": {
        "texture": texture, "discardThreshold": F(float(discard)),
        "hdr": _hdr_vec(hdr), "hdrMode": hdr_mode, "pixelArt": pa}}
    return _material_entry(mat, blend or BLEND_ADDITIVE, cull, depth_test, depth_mask)


def sprite_material(sprite, discard=0.05, hdr=None, hdr_mode="ADDITIVE",
                    blend=None, cull=True, depth_test=True, depth_mask=False):
    """Atlas sprite material (supports animated .mcmeta sprites)."""
    mat = {"type": "sprite", "data": {
        "spriteLocation": sprite, "discardThreshold": F(float(discard)),
        "hdr": _hdr_vec(hdr), "hdrMode": hdr_mode}}
    return _material_entry(mat, blend or BLEND_ADDITIVE, cull, depth_test, depth_mask)


def block_atlas_material(blend=None, cull=True, depth_test=True, depth_mask=False):
    """Vanilla block atlas (pair with use_block_uv=True + render_mode='Model')."""
    mat = {"type": "block_atlas", "data": {}}
    return _material_entry(mat, blend or BLEND_ALPHA, cull, depth_test, depth_mask)


def custom_shader_material(shader="photon:circle", curves=None, gradients=None,
                           blend=None, cull=True, depth_test=True, depth_mask=False):
    """Own fragment shader; authored curves/gradients upload as 128x128 LUT textures.

    curves: list of `curve(...)['data']['curves']`-style segment lists; gradients: list of
    (alpha_pts, rgb_pts) tuples.
    """
    data = {"shaderLocation": shader}
    if curves is not None:
        data["curveTexture"] = {"curves": L([L([L([F(float(x)) for x in seg]) for seg in c]) for c in curves])}
    if gradients is not None:
        data["gradientTexture"] = {"gradients": L([_gradient_color(a, rgb) for a, rgb in gradients])}
    mat = {"type": "custom_shader", "data": data}
    return _material_entry(mat, blend or BLEND_ADDITIVE, cull, depth_test, depth_mask)


# ---------------------------------------------------------------------------
# Misc schema helpers
# ---------------------------------------------------------------------------
def rom(items):
    """@ReadOnlyManaged list encoding: {uid: Int(count), payload: List<Compound>}."""
    items = list(items)
    return {"uid": I(len(items)), "payload": L(items)}


def burst(time=0, count=10, cycles=1, interval=1, probability=1.0):
    """Emission burst row (time = tick within the cycle; cycles 0 = infinite)."""
    return {"time": I(int(time)), "count": _nf(count), "cycles": I(int(cycles)),
            "interval": I(int(interval)), "probability": F(float(probability))}


def sub_emitter(fx_location, event="Birth", probability=1.0, tick_interval=1,
                inherit=()):
    """subEmitters row — spawns ANOTHER .fx file on particle events.

    event: Birth | Death | Collision | FirstCollision | Tick.
    inherit: any of "Color", "Size", "Rotation", "Lifetime", "Duration".
    """
    row = {"fxLocation": fx_location, "event": event,
           "emitProbability": _nf(probability), "tickInterval": I(int(tick_interval))}
    for key in ("Color", "Size", "Rotation", "Lifetime", "Duration"):
        row["inherit" + key] = _bool(key in inherit)
    return row


def aabb(mn, mx):
    """AABB: {min: List<Double>[3], max: List<Double>[3]}."""
    return {"min": L([D(float(v)) for v in mn]), "max": L([D(float(v)) for v in mx])}


def _quat_xyz_deg(x_deg, y_deg, z_deg):
    """JOML Quaternionf.rotationXYZ(radians) — the editor's transform rotation convention."""
    ax, ay, az = (math.radians(a) * 0.5 for a in (x_deg, y_deg, z_deg))
    sx, cx = math.sin(ax), math.cos(ax)
    sy, cy = math.sin(ay), math.cos(ay)
    sz, cz = math.sin(az), math.cos(az)
    return (sx * cy * cz + cx * sy * sz,
            cx * sy * cz - sx * cy * sz,
            cx * cy * sz + sx * sy * cz,
            cx * cy * cz - sx * sy * sz)


# A reusable "pop in then shrink to zero" bezier segment (x: 0..1 lifetime, y: 0..1).
SEG_POP_SHRINK = (0.0, 0.66, 0.1, 1.0, 0.9, 0.2, 1.0, 0.0)
# Linear 0 -> 1 ramp.
SEG_LINEAR_UP = (0.0, 0.0, 0.33, 0.33, 0.66, 0.66, 1.0, 1.0)
# Linear 1 -> 0 ramp.
SEG_LINEAR_DOWN = (0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.0)


# ---------------------------------------------------------------------------
# Emitter builders
# ---------------------------------------------------------------------------
class _FxObject:
    """Base: transform handling + UUID parent linking shared by every fx object kind."""

    def __init__(self, fx_type: str, name: str):
        self.fx_type = fx_type
        self.name = name
        self.uuid = str(_uuid.uuid4())
        self._position = (0.0, 0.0, 0.0)
        self._rotation = (0.0, 0.0, 0.0, 1.0)
        self._scale = (1.0, 1.0, 1.0)
        self._parent_id = None
        self._children_ids = []

    # -- transform ----------------------------------------------------------
    def at(self, x, y, z):
        """Local position (blocks, relative to parent / executor anchor)."""
        self._position = (float(x), float(y), float(z))
        return self

    def rotated(self, x_deg, y_deg, z_deg):
        """Local rotation, XYZ euler degrees (stored as a quaternion like the editor)."""
        self._rotation = _quat_xyz_deg(x_deg, y_deg, z_deg)
        return self

    def scaled(self, x, y=None, z=None):
        """Local scale (uniform when y/z omitted)."""
        if y is None:
            y = z = x
        self._scale = (float(x), float(y), float(z))
        return self

    def child_of(self, parent: "_FxObject"):
        """Transform parent linking: nests this object under `parent` (UUID relink)."""
        if self._parent_id is not None:
            raise ValueError(f"{self.name!r} already has a parent")
        self._parent_id = parent.uuid
        parent._children_ids.append(self.uuid)
        return self

    def _transform(self) -> dict:
        t = {"id": self.uuid,
             "localPosition": L([F(v) for v in self._position]),
             "localRotation": L([F(v) for v in self._rotation]),
             "localScale": L([F(v) for v in self._scale])}
        if self._parent_id is not None:
            t["_parentId"] = self._parent_id
        t["_childrenId"] = L(list(self._children_ids))
        return t

    def build(self) -> dict:
        raise NotImplementedError


class EmptyObject(_FxObject):
    """`empty` — grouping/pivot node (no rendering); nest emitters under it via child_of."""

    def __init__(self, name):
        super().__init__("empty", name)

    def build(self):
        return {"type": "empty", "data": {"name": self.name, "transform": self._transform()}}


class _RendererMixin:
    """Shared renderer block (particle/trail/beam/ara all carry `renderer`)."""

    def _init_renderer(self, particle=True):
        self._materials = []
        self._renderer = {
            "layer": "Translucent", "cull": {"_enable": B(0)}, "orderInLayer": I(0),
            "vertexSortingMode": "NONE"}
        if particle:
            self._renderer.update({
                "renderMode": "Billboard", "shade": B(0), "useBlockUV": B(0),
                "modelPivot": L([F(0.0), F(0.0), F(0.0)]),
                "velocityScale": F(0.0), "lengthScale": F(2.0), "useGPUInstance": B(0),
                "facingMode": "DEFAULT"})

    def with_material(self, material_entry):
        """Appends one material pass (texture_material/sprite_material/... helpers)."""
        self._materials.append(material_entry)
        return self

    def with_renderer(self, **kwargs):
        """Overrides renderer fields. Accepted keys (particle emitters unless noted):

        render_mode (None|Billboard|Horizontal|Vertical|VerticalBillboard|
        StretchedBillboard|Model), facing_mode, layer (Opaque|Translucent),
        order_in_layer, vertex_sorting (NONE|DISTANCE), shade, use_block_uv,
        use_gpu_instance, model_pivot (x,y,z), velocity_scale, length_scale.
        """
        m = {"render_mode": ("renderMode", str), "facing_mode": ("facingMode", str),
             "layer": ("layer", str), "vertex_sorting": ("vertexSortingMode", str),
             "order_in_layer": ("orderInLayer", lambda v: I(int(v))),
             "shade": ("shade", _bool), "use_block_uv": ("useBlockUV", _bool),
             "use_gpu_instance": ("useGPUInstance", _bool),
             "model_pivot": ("modelPivot", lambda v: L([F(float(x)) for x in v])),
             "velocity_scale": ("velocityScale", lambda v: F(float(v))),
             "length_scale": ("lengthScale", lambda v: F(float(v)))}
        for key, value in kwargs.items():
            if key not in m:
                raise KeyError(f"unknown renderer key {key!r} (known: {sorted(m)})")
            nbt_key, conv = m[key]
            self._renderer[nbt_key] = conv(value)
        return self

    def with_cull_box(self, mn, mx):
        """Render-culling AABB (local blocks) — cheap off-screen skip for loops."""
        self._renderer["cull"] = {"_enable": B(1), "cullBox": aabb(mn, mx)}
        return self

    def _renderer_block(self, default_material=True) -> dict:
        materials = list(self._materials)
        if not materials and default_material:
            materials = [texture_material()]
        out = {"materials": rom(materials)}
        out.update(self._renderer)
        return out


class ParticleEmitter(_FxObject, _RendererMixin):
    """`particle_emitter` — the Unity-style billboard/model particle system."""

    _MAIN_KEYS = {
        "duration": lambda v: I(int(v)), "looping": _bool, "prewarm": lambda v: I(int(v)),
        "start_delay": _nf, "start_lifetime": _nf, "start_speed": _nf,
        "start_size": nf3, "start_rotation": nf3, "start_color": lambda v: v if _is_nf(v) else color(v),
        "simulation_space": str, "max_particles": lambda v: I(int(v)),
        "parallel_update": _bool, "parallel_rendering": _bool}
    _MAIN_NBT = {
        "duration": "duration", "looping": "looping", "prewarm": "prewarm",
        "start_delay": "startDelay", "start_lifetime": "startLifetime",
        "start_speed": "startSpeed", "start_size": "startSize",
        "start_rotation": "startRotation", "start_color": "startColor",
        "simulation_space": "simulationSpace", "max_particles": "maxParticles",
        "parallel_update": "parallelUpdate", "parallel_rendering": "parallelRendering"}
    # Toggle-module snake_case -> NBT key (with_curves / with_module).
    _MODULE_KEYS = {
        "physics": "physics", "lights": "lights",
        "velocity_over_lifetime": "velocityOverLifetime", "inherit_velocity": "inheritVelocity",
        "lifetime_by_emitter_speed": "lifetimeByEmitterSpeed",
        "force_over_lifetime": "forceOverLifetime", "color_over_lifetime": "colorOverLifetime",
        "color_by_speed": "colorBySpeed", "size_over_lifetime": "sizeOverLifetime",
        "size_by_speed": "sizeBySpeed", "rotation_over_lifetime": "rotationOverLifetime",
        "rotation_by_speed": "rotationBySpeed", "noise": "noise", "uv_animation": "uvAnimation",
        "trails": "trails", "sub_emitters": "subEmitters",
        "additional_gpu_data": "additionalGPUDataSetting"}

    def __init__(self, name, **main):
        _FxObject.__init__(self, "particle_emitter", name)
        self._init_renderer(particle=True)
        # Structurally-complete main block (the PHOTON-EXPLORE-2-validated baseline).
        self._main = {
            "duration": I(100), "looping": B(1), "prewarm": I(0),
            "startDelay": constant(0), "startLifetime": constant(100),
            "startSpeed": constant(1), "startSize": nf3(0.1), "startRotation": nf3(0),
            "startColor": color(0xFFFFFFFF), "simulationSpace": "Local",
            "maxParticles": I(2000)}
        self._emission = {
            "emissionRate": constant(0.5), "distanceRate": constant(0),
            "emissionMode": "Exacting", "bursts": rom([])}
        self._shape = {
            "shape": dot(),
            "position": nf3(0), "rotation": nf3(0), "scale": nf3(1)}
        self._modules = {}  # NBT key -> compound (insertion order preserved)
        self.main(**main)

    # -- main block ---------------------------------------------------------
    def main(self, **kwargs):
        """Sets main-block values (duration, looping, prewarm, start_delay, start_lifetime,
        start_speed, start_size, start_rotation, start_color, simulation_space,
        max_particles, parallel_update, parallel_rendering)."""
        for key, value in kwargs.items():
            if key not in self._MAIN_KEYS:
                raise KeyError(f"unknown main key {key!r} (known: {sorted(self._MAIN_KEYS)})")
            self._main[self._MAIN_NBT[key]] = self._MAIN_KEYS[key](value)
        return self

    def with_emission(self, rate=None, distance_rate=None, mode=None, bursts=None):
        """Emission: rate = particles/tick (NF or scalar), distance_rate = per block moved,
        mode = Exacting|Random, bursts = [burst(...), ...]."""
        if rate is not None:
            self._emission["emissionRate"] = _nf(float(rate) if isinstance(rate, int) else rate)
        if distance_rate is not None:
            self._emission["distanceRate"] = _nf(distance_rate)
        if mode is not None:
            self._emission["emissionMode"] = mode
        if bursts is not None:
            self._emission["bursts"] = rom(bursts)
        return self

    def with_shape(self, shape, position=None, rotation=None, scale=None):
        """Emission shape (sphere/circle/cone/cylinder/box/mesh/function_shape/dot helpers)
        plus optional animatable NF3 origin position/rotation(deg)/scale over emitter t."""
        self._shape["shape"] = shape
        if position is not None:
            self._shape["position"] = nf3(position)
        if rotation is not None:
            self._shape["rotation"] = nf3(rotation)
        if scale is not None:
            self._shape["scale"] = nf3(scale)
        return self

    # -- toggle modules -----------------------------------------------------
    def with_module(self, key, compound):
        """Raw escape hatch: attaches a toggle-module compound under its snake_case or NBT
        key; `_enable: 1b` is added when missing."""
        nbt_key = self._MODULE_KEYS.get(key, key)
        body = dict(compound)
        body.setdefault("_enable", B(1))
        # _enable leads, matching editor-written module compounds.
        self._modules[nbt_key] = {"_enable": body.pop("_enable"), **body}
        return self

    def with_curves(self, **modules):
        """Attaches over-lifetime/by-speed animation modules. Accepted keys:

        color_over_lifetime = NF color-family (gradient/color/random_*)
        size_over_lifetime / size_by_speed = NF or NF3 multiplier
        rotation_over_lifetime / rotation_by_speed = NF roll (deg/tick) or dict(roll=, pitch=, yaw=)
        color_by_speed = dict(color=NF-color, range=(min, max))
        velocity_over_lifetime = dict(linear=NF3, orbital=NF3, orbital_mode=..., offset=NF3,
                                      radial=NF, speed_modifier=NF)
        force_over_lifetime = dict(force=NF3, simulation_space="Local"|"World")
        noise = dict(frequency=, quality="Noise1D|2D|3D", position=NF3, rotation=NF, size=NF,
                     remap_curve=NF-curve)
        uv_animation = dict(tiles=(cols, rows), animation="WholeSheet"|"SingleRow",
                            frame_over_time=NF, start_frame=NF, cycle=1.0)
        Anything else raises — use with_module(key, {...}) for exotic modules.
        """
        for key, value in modules.items():
            if key == "color_over_lifetime":
                self.with_module("colorOverLifetime", {"color": value})
            elif key == "size_over_lifetime":
                self.with_module("sizeOverLifetime", {"size": nf3(value)})
            elif key == "size_by_speed":
                body = {"size": nf3(value["size"]), "speedRange": _min_max(value.get("range", (0, 1)))} \
                    if isinstance(value, dict) else {"size": nf3(value), "speedRange": _min_max((0, 1))}
                self.with_module("sizeBySpeed", body)
            elif key in ("rotation_over_lifetime", "rotation_by_speed"):
                spin = value if isinstance(value, dict) else {"roll": value}
                body = {"roll": _nf(spin.get("roll", 0)), "pitch": _nf(spin.get("pitch", 0)),
                        "yaw": _nf(spin.get("yaw", 0))}
                if key == "rotation_by_speed":
                    body["speedRange"] = _min_max(spin.get("range", (0, 1)))
                self.with_module(self._MODULE_KEYS[key], body)
            elif key == "color_by_speed":
                self.with_module("colorBySpeed", {
                    "color": value["color"], "speedRange": _min_max(value.get("range", (0, 1)))})
            elif key == "velocity_over_lifetime":
                v = value
                self.with_module("velocityOverLifetime", {
                    "linear": nf3(v.get("linear", 0)),
                    "orbitalMode": v.get("orbital_mode", "AngularVelocity"),
                    "orbital": nf3(v.get("orbital", 0)), "offset": nf3(v.get("offset", 0)),
                    "radial": _nf(v.get("radial", 0.0)),
                    "speedModifier": _nf(v.get("speed_modifier", 1))})
            elif key == "force_over_lifetime":
                self.with_module("forceOverLifetime", {
                    "force": nf3(value.get("force", 0)),
                    "simulationSpace": value.get("simulation_space", "Local")})
            elif key == "noise":
                v = value
                remap = {"_enable": B(1), "remapCurve": v["remap_curve"]} \
                    if "remap_curve" in v else {"_enable": B(0)}
                self.with_module("noise", {
                    "frequency": F(float(v.get("frequency", 1.0))),
                    "quality": v.get("quality", "Noise2D"), "remap": remap,
                    "position": nf3(v.get("position", 0.1)),
                    "rotation": _nf(v.get("rotation", 0)), "size": _nf(v.get("size", 0))})
            elif key == "uv_animation":
                v = value
                self.with_module("uvAnimation", {
                    "tiles": L([I(int(v.get("tiles", (1, 1))[0])), I(int(v.get("tiles", (1, 1))[1]))]),
                    "animation": v.get("animation", "WholeSheet"),
                    "frameOverTime": _nf(v.get("frame_over_time", 0)),
                    "startFrame": _nf(v.get("start_frame", 0)),
                    "cycle": F(float(v.get("cycle", 1.0)))})
            else:
                raise KeyError(f"unknown with_curves key {key!r} — use with_module for raw modules")
        return self

    def with_physics(self, collision=True, removed_when_collided=False, friction=1.0,
                     collided_friction=0.7, gravity=0.0, bounce_chance=1.0,
                     bounce_rate=1.0, bounce_spread=0.0):
        """Real world-collision physics; gravity in blocks/tick² (applied x0.04)."""
        return self.with_module("physics", {
            "hasCollision": _bool(collision), "removedWhenCollided": _bool(removed_when_collided),
            "friction": _nf(float(friction)), "collidedFriction": _nf(float(collided_friction)),
            "gravity": _nf(float(gravity)), "bounceChance": _nf(float(bounce_chance)),
            "bounceRate": _nf(float(bounce_rate)), "bounceSpreadRate": _nf(float(bounce_spread))})

    def with_lights(self, sky=15, block=15):
        """Forced lightmap over particle lifetime (fake glow — NOT a dynamic light)."""
        return self.with_module("lights", {"skyLight": _nf(sky), "blockLight": _nf(block)})

    def with_sub_emitters(self, *rows):
        """Attaches sub_emitter(...) rows — each spawns a whole other .fx on particle events."""
        return self.with_module("subEmitters", {"emitters": rom(list(rows))})

    def build(self):
        config = dict(self._main)
        config["emission"] = self._emission
        config["shape"] = self._shape
        config["renderer"] = self._renderer_block()
        config.update(self._modules)
        return {"type": "particle_emitter", "data": {
            "version": I(2), "name": self.name, "transform": self._transform(),
            "config": config}}


def _min_max(pair) -> dict:
    return {"min": F(float(pair[0])), "max": F(float(pair[1]))}


class BeamEmitter(_FxObject, _RendererMixin):
    """`beam_emitter` — start->end quad with optional raycast clipping (BLOCKS/ENTITIES)."""

    def __init__(self, name, end=(0.0, 0.0, -3.0), width=0.2, duration=100, looping=True,
                 start_delay=0, emit_rate=0, raycast="NONE", raycast_block_mode=None,
                 raycast_fluid_mode=None, color_nf=None):
        _FxObject.__init__(self, "beam_emitter", name)
        self._init_renderer(particle=False)
        self._config = {
            "duration": I(int(duration)), "looping": _bool(looping),
            "startDelay": I(int(start_delay)),
            "end": L([F(float(v)) for v in end]), "width": _nf(float(width)),
            "emitRate": _nf(emit_rate), "raycast": raycast}
        if raycast_block_mode is not None:
            self._config["raycastBlockMode"] = raycast_block_mode  # ClipContext.Block, e.g. "VISUAL"
        if raycast_fluid_mode is not None:
            self._config["raycastFluidMode"] = raycast_fluid_mode  # ClipContext.Fluid, e.g. "NONE"
        if color_nf is not None:
            self._config["color"] = color_nf
        self._modules = {}

    def with_lights(self, sky=15, block=15):
        self._modules["lights"] = {"_enable": B(1), "skyLight": _nf(sky), "blockLight": _nf(block)}
        return self

    def with_uv_animation(self, tiles=(1, 1), animation="WholeSheet", frame_over_time=0,
                          start_frame=0, cycle=1.0):
        self._modules["uvAnimation"] = {
            "_enable": B(1), "tiles": L([I(int(tiles[0])), I(int(tiles[1]))]),
            "animation": animation, "frameOverTime": _nf(frame_over_time),
            "startFrame": _nf(start_frame), "cycle": F(float(cycle))}
        return self

    def build(self):
        config = dict(self._config)
        config["renderer"] = self._renderer_block()
        config.update(self._modules)
        return {"type": "beam_emitter", "data": {
            "version": I(2), "name": self.name, "transform": self._transform(),
            "config": config}}


class TrailEmitter(_FxObject, _RendererMixin):
    """`trail_emitter` — emitter-following trail strip (segment retention = `time` ticks)."""

    def __init__(self, name, duration=100, looping=True, start_delay=0, time=20,
                 min_vertex_distance=0.05, smooth=False, uv_mode="Stretch",
                 width=0.2, color_nf=None):
        _FxObject.__init__(self, "trail_emitter", name)
        self._init_renderer(particle=False)
        self._config = {
            "duration": I(int(duration)), "looping": _bool(looping),
            "startDelay": I(int(start_delay)), "time": I(int(time)),
            "minVertexDistance": F(float(min_vertex_distance)),
            "smoothInterpolation": _bool(smooth), "uvMode": uv_mode,
            "widthOverTrail": _nf(float(width) if isinstance(width, int) else width)}
        if color_nf is not None:
            self._config["colorOverTrail"] = color_nf
        self._modules = {}

    def with_lights(self, sky=15, block=15):
        self._modules["lights"] = {"_enable": B(1), "skyLight": _nf(sky), "blockLight": _nf(block)}
        return self

    def build(self):
        config = dict(self._config)
        config["renderer"] = self._renderer_block()
        config.update(self._modules)
        return {"type": "trail_emitter", "data": {
            "version": I(2), "name": self.name, "transform": self._transform(),
            "config": config}}


class AraTrailEmitter(_FxObject, _RendererMixin):
    """`ara_trail_emitter` — physics-lagged ribbon with custom cross-section polygon.

    Only non-default fields are written (missing keys keep the Java defaults, §4.3):
    section = [(x, y), ...] cross-section vertices; time/time_interval/min_distance in
    SECONDS (unlike everything else!); physics = dict(warmup=, gravity=(x,y,z), inertia=,
    velocity_smoothing=, damping=).
    """
    _SIMPLE = {
        "space": ("space", str), "alignment": ("alignment", str), "sorting": ("sorting", str),
        "thickness": ("thickness", lambda v: F(float(v))),
        "smoothness": ("smoothness", lambda v: I(int(v))),
        "smoothing_distance": ("smoothingDistance", lambda v: F(float(v))),
        "high_quality_corners": ("highQualityCorners", _bool),
        "corner_roundness": ("cornerRoundness", lambda v: I(int(v))),
        "emit": ("emit", _bool),
        "initial_thickness": ("initialThickness", lambda v: F(float(v))),
        "initial_color": ("initialColor", lambda v: I(_signed32(v))),
        "initial_velocity": ("initialVelocity", lambda v: L([F(float(x)) for x in v])),
        "time_interval": ("timeInterval", lambda v: F(float(v))),
        "min_distance": ("minDistance", lambda v: F(float(v))),
        "time": ("time", lambda v: F(float(v))),
        "texture_mode": ("textureMode", str),
        "uv_factor": ("uvFactor", lambda v: F(float(v))),
        "uv_width_factor": ("uvWidthFactor", lambda v: F(float(v))),
        "tile_anchor": ("tileAnchor", lambda v: F(float(v))),
        "thickness_over_length": ("thicknessOverLength", _nf),
        "thickness_over_time": ("thicknessOverTime", _nf),
        "thickness_over_segment_time": ("thicknessOverSegmentTime", _nf),
        "color_over_length": ("colorOverLength", lambda v: v),
        "color_over_time": ("colorOverTime", lambda v: v),
        "color_over_segment_time": ("colorOverSegmentTime", lambda v: v)}

    def __init__(self, name, duration=100, looping=True, start_delay=0, section=None,
                 physics=None, **kwargs):
        _FxObject.__init__(self, "ara_trail_emitter", name)
        self._init_renderer(particle=False)
        self._config = {"duration": I(int(duration)), "looping": _bool(looping),
                        "startDelay": I(int(start_delay))}
        if section is not None:
            self._config["section"] = {
                "vertices": L([L([F(float(x)), F(float(y))]) for x, y in section])}
        if physics is not None:
            p = physics
            self._config["physicsSetting"] = {
                "warmup": F(float(p.get("warmup", 0.0))),
                "gravity": L([F(float(v)) for v in p.get("gravity", (0, 0, 0))]),
                "inertia": F(float(p.get("inertia", 0.0))),
                "velocitySmoothing": F(float(p.get("velocity_smoothing", 0.75))),
                "damping": F(float(p.get("damping", 0.75)))}
        for key, value in kwargs.items():
            if key not in self._SIMPLE:
                raise KeyError(f"unknown ara_trail key {key!r} (known: {sorted(self._SIMPLE)})")
            nbt_key, conv = self._SIMPLE[key]
            self._config[nbt_key] = conv(value)

    def build(self):
        config = dict(self._config)
        config["renderer"] = self._renderer_block()
        return {"type": "ara_trail_emitter", "data": {
            "version": I(2), "name": self.name, "transform": self._transform(),
            "config": config}}


# ---------------------------------------------------------------------------
# FxBuilder — the file-level entry point
# ---------------------------------------------------------------------------
class FxBuilder:
    """Builds one `.fx` file: a flat list of fx objects (hierarchy via UUID relinking).

    fx = FxBuilder("altar_levelup")            # -> eclipse:altar_levelup
    pivot = fx.empty("root").at(0, 1, 0)
    fx.particle_emitter("ring", ...).child_of(pivot)...
    fx.write(FX_ASSETS_DIR / "altar_levelup.fx")
    """

    def __init__(self, name: str):
        self.name = name
        self.objects: list[_FxObject] = []

    def _add(self, obj):
        self.objects.append(obj)
        return obj

    def particle_emitter(self, name, **main) -> ParticleEmitter:
        return self._add(ParticleEmitter(name, **main))

    def trail_emitter(self, name, **kwargs) -> TrailEmitter:
        return self._add(TrailEmitter(name, **kwargs))

    def ara_trail_emitter(self, name, **kwargs) -> AraTrailEmitter:
        return self._add(AraTrailEmitter(name, **kwargs))

    def beam_emitter(self, name, **kwargs) -> BeamEmitter:
        return self._add(BeamEmitter(name, **kwargs))

    def empty(self, name) -> EmptyObject:
        return self._add(EmptyObject(name))

    def build(self) -> dict:
        """Root compound: {fxData: {fxObjects: [{type, data}, ...]}} (flat, all objects)."""
        if not self.objects:
            raise ValueError(f"FxBuilder({self.name!r}) has no objects")
        return {"fxData": {"fxObjects": L([o.build() for o in self.objects])}}

    def to_bytes(self) -> tuple[bytes, bytes]:
        """(raw NBT bytes, gzip bytes) — gzip mtime pinned to 0 for reproducible files."""
        raw = write_root(self.build())
        return raw, gzip.compress(raw, compresslevel=6, mtime=0)

    def write(self, path, validate=True) -> tuple[int, int]:
        """Writes the gzip NBT .fx file; round-trip-validates by default. Returns sizes."""
        raw, gz = self.to_bytes()
        if validate:
            errors = validate_tree(read_root(raw))
            if read_root(raw) != self.build() or write_root(read_root(raw)) != raw:
                errors.append("round-trip mismatch (writer/reader disagree)")
            if errors:
                raise ValueError(f"{self.name}: " + "; ".join(errors))
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(gz)
        return len(raw), len(gz)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
KNOWN_TYPES = {"particle_emitter", "trail_emitter", "ara_trail_emitter", "beam_emitter", "empty"}
KNOWN_NF_TYPES = {"constant", "random_constant", "curve", "random_curve",
                  "color", "random_color", "gradient", "random_gradient"}


def validate_tree(root: dict) -> list:
    """Structural checks against the FX_FORMAT.md schema; returns a list of error strings."""
    errors = []
    fx_data = root.get("fxData")
    if not isinstance(fx_data, dict):
        return [f"missing/invalid fxData ({type(fx_data).__name__})"]
    objects = fx_data.get("fxObjects")
    if not isinstance(objects, L):
        return ["fxData.fxObjects is not a List"]
    ids = {}
    parents = {}
    for idx, wrapper in enumerate(objects.items):
        where = f"fxObjects[{idx}]"
        if not isinstance(wrapper, dict) or "type" not in wrapper or "data" not in wrapper:
            errors.append(f"{where}: not a {{type, data}} wrapper")
            continue
        fx_type = wrapper["type"]
        if fx_type not in KNOWN_TYPES:
            errors.append(f"{where}: unknown type {fx_type!r}")
        data = wrapper["data"]
        if not isinstance(data, dict):
            errors.append(f"{where}: data is not a compound")
            continue
        transform = data.get("transform")
        if not isinstance(transform, dict) or "id" not in transform:
            errors.append(f"{where}: missing transform.id")
            continue
        oid = transform["id"]
        try:
            _uuid.UUID(oid)
        except Exception:
            errors.append(f"{where}: transform.id {oid!r} is not a UUID")
        if oid in ids:
            errors.append(f"{where}: duplicate transform.id {oid}")
        ids[oid] = where
        if "_parentId" in transform:
            parents[oid] = (where, transform["_parentId"])
        if fx_type != "empty":
            if not isinstance(data.get("config"), dict):
                errors.append(f"{where}: emitter without config compound")
            version = data.get("version")
            if not isinstance(version, I) or version.v != 2:
                errors.append(f"{where}: emitter version is {version!r}, expected Int 2")
        if fx_type == "particle_emitter" and isinstance(data.get("config"), dict):
            errors.extend(_validate_particle_config(data["config"], where))
    for oid, (where, parent_id) in parents.items():
        if parent_id not in ids:
            errors.append(f"{where}: _parentId {parent_id} does not reference any object")
        if parent_id == oid:
            errors.append(f"{where}: object is its own parent")
    return errors


def _validate_particle_config(config: dict, where: str) -> list:
    errors = []
    for key in ("emission", "shape", "renderer"):
        if not isinstance(config.get(key), dict):
            errors.append(f"{where}: config.{key} missing/not a compound")
    for key, value in config.items():
        if isinstance(value, dict) and "_enable" in value and not isinstance(value["_enable"], B):
            errors.append(f"{where}: config.{key}._enable is not a Byte")
    renderer = config.get("renderer")
    if isinstance(renderer, dict):
        materials = renderer.get("materials")
        if not (isinstance(materials, dict) and isinstance(materials.get("uid"), I)
                and isinstance(materials.get("payload"), L)
                and materials["uid"].v == len(materials["payload"].items)):
            errors.append(f"{where}: renderer.materials is not a consistent ROM list")
    errors.extend(_validate_nf_wrappers(config, f"{where}.config"))
    return errors


def _validate_nf_wrappers(node, path) -> list:
    """Recursively checks every {type, data} dict that looks like a NumberFunction wrapper."""
    errors = []
    if isinstance(node, dict):
        if set(node.keys()) == {"type", "data"} and isinstance(node["type"], str):
            if node["type"] not in KNOWN_NF_TYPES and node["type"] not in (
                    "dot", "sphere", "circle", "cone", "cylinder", "box", "mesh", "function",
                    "texture", "sprite", "block_atlas", "custom_shader"):
                errors.append(f"{path}: unknown {{type,data}} registry key {node['type']!r}")
        for key, value in node.items():
            errors.extend(_validate_nf_wrappers(value, f"{path}.{key}"))
    elif isinstance(node, L):
        for idx, item in enumerate(node.items):
            errors.extend(_validate_nf_wrappers(item, f"{path}[{idx}]"))
    return errors


def validate_file(path) -> list:
    """Full check of an on-disk .fx: gzip + parse + structure + writer/reader round-trip."""
    try:
        raw = gzip.decompress(Path(path).read_bytes())
    except Exception as exc:
        return [f"not gzip-compressed NBT: {exc}"]
    try:
        tree = read_root(raw)
    except Exception as exc:
        return [f"NBT parse failed: {exc}"]
    errors = validate_tree(tree)
    if write_root(tree) != raw:
        errors.append("round-trip mismatch: re-serialized NBT differs from file bytes")
    return errors


# ---------------------------------------------------------------------------
# SNBT-ish dump (debugging aid)
# ---------------------------------------------------------------------------
def dump(node, indent=0) -> str:
    pad = "  " * indent
    if isinstance(node, dict):
        if not node:
            return "{}"
        inner = ",\n".join(f"{pad}  {k}: {dump(v, indent + 1)}" for k, v in node.items())
        return "{\n" + inner + "\n" + pad + "}"
    if isinstance(node, L):
        if not node.items:
            return "[]"
        if all(isinstance(x, (B, Sh, I, Lg, F, D)) for x in node.items):
            return "[" + ", ".join(dump(x) for x in node.items) + "]"
        inner = ",\n".join(f"{pad}  {dump(x, indent + 1)}" for x in node.items)
        return "[\n" + inner + "\n" + pad + "]"
    if isinstance(node, B):
        return f"{node.v}b"
    if isinstance(node, Sh):
        return f"{node.v}s"
    if isinstance(node, I):
        return str(node.v)
    if isinstance(node, Lg):
        return f"{node.v}L"
    if isinstance(node, F):
        return f"{node.v}f"
    if isinstance(node, D):
        return f"{node.v}d"
    if isinstance(node, str):
        return f'"{node}"'
    return repr(node)


# ---------------------------------------------------------------------------
# Smoke-test templates (ports of the PHOTON-EXPLORE-2-validated /tmp/build_fx.py)
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).resolve().parents[2]
FX_ASSETS_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/fx"


def build_template_burst() -> FxBuilder:
    """eclipse:template_burst — one-shot radial spark burst with collision physics."""
    fx = FxBuilder("template_burst")
    (fx.particle_emitter(
            "spark_burst",
            duration=40, looping=False, prewarm=0, start_delay=constant(0),
            start_lifetime=random_between(18, 32),
            start_speed=random_between(0.35, 0.85),
            start_size=nf3(random_between(0.08, 0.16), random_between(0.08, 0.16),
                           random_between(0.08, 0.16)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=color(0xFFFFFFFF), simulation_space="World", max_particles=256)
       .with_emission(rate=constant(0.0), distance_rate=constant(0), mode="Exacting",
                      bursts=[burst(time=0, count=constant(40), cycles=1, interval=1,
                                    probability=1.0)])
       .with_shape(sphere(radius=0.35, thickness=0.0))
       .with_material(texture_material("photon:textures/particle/circle.png",
                                       blend=BLEND_ADDITIVE))
       .with_physics(collision=True, removed_when_collided=False, friction=0.98,
                     collided_friction=0.6, gravity=0.35, bounce_chance=0.6,
                     bounce_rate=0.4, bounce_spread=0.1)
       .with_curves(
            color_over_lifetime=gradient(
                [(0.0, 1.0), (0.6, 0.9), (1.0, 0.0)],
                [(0.0, 1.0, 0.95, 0.7), (0.5, 1.0, 0.65, 0.2), (1.0, 0.6, 0.1, 0.05)]),
            size_over_lifetime=nf3(
                curve(0.0, 1.5, [SEG_POP_SHRINK], "lifetime", "size"),
                curve(0.0, 1.5, [SEG_POP_SHRINK], "lifetime", "size"),
                curve(0.0, 1.5, [SEG_POP_SHRINK], "lifetime", "size")))
       .with_lights(sky=15, block=15))
    return fx


def build_template_loop() -> FxBuilder:
    """eclipse:template_loop — looping violet aura ring (WINDOWED-loop smoke test)."""
    fx = FxBuilder("template_loop")
    em = (fx.particle_emitter(
            "aura_loop",
            duration=60, looping=True, prewarm=20, start_delay=constant(0),
            start_lifetime=random_between(40, 60),
            start_speed=random_between(0.05, 0.15),
            start_size=nf3(random_between(0.15, 0.3), random_between(0.15, 0.3),
                           random_between(0.15, 0.3)),
            start_rotation=nf3(constant(0), constant(0), random_between(0.0, 360.0)),
            start_color=color(0xFFFFFFFF), simulation_space="Local", max_particles=400)
       .with_emission(rate=constant(1.5), distance_rate=constant(0), mode="Exacting", bursts=[])
       .with_shape(cylinder(radius=0.9, thickness=0.15, arc_mode="Loop", arc_speed=0.5))
       .with_material(texture_material("photon:textures/particle/smoke.png",
                                       blend=BLEND_ALPHA))
       .with_renderer(vertex_sorting="DISTANCE")
       .with_cull_box((-2.0, -0.5, -2.0), (2.0, 3.0, 2.0))
       .with_curves(
            velocity_over_lifetime=dict(
                linear=nf3(constant(0), random_between(0.02, 0.06), constant(0)),
                orbital_mode="AngularVelocity",
                orbital=nf3(constant(0), constant(0.8), constant(0)),
                offset=nf3(0), radial=constant(0.0), speed_modifier=constant(1)),
            noise=dict(frequency=0.8, quality="Noise2D",
                       position=nf3(constant(0.05), constant(0.02), constant(0.05)),
                       rotation=constant(0), size=constant(0)),
            color_over_lifetime=gradient(
                [(0.0, 0.0), (0.2, 0.7), (0.8, 0.55), (1.0, 0.0)],
                [(0.0, 0.55, 0.35, 0.9), (1.0, 0.3, 0.15, 0.6)])))
    em._modules["uvAnimation"] = {"_enable": B(0)}  # parity with the validated generator
    return fx


TEMPLATES = {
    "template_burst.fx": build_template_burst,
    "template_loop.fx": build_template_loop,
}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _cmd_selfcheck() -> int:
    import tempfile
    ok = True
    with tempfile.TemporaryDirectory() as tmp:
        for name, builder_fn in TEMPLATES.items():
            fx = builder_fn()
            path = Path(tmp) / name
            try:
                raw_len, gz_len = fx.write(path)  # write() validates the in-memory tree
            except ValueError as exc:
                print(f"FAIL {name}: {exc}")
                ok = False
                continue
            errors = validate_file(path)
            if errors:
                print(f"FAIL {name}: " + "; ".join(errors))
                ok = False
            else:
                print(f"OK   {name}: raw NBT {raw_len} bytes, gzip {gz_len} bytes, "
                      "round-trip byte-identical")
    print("selfcheck " + ("PASSED" if ok else "FAILED"))
    return 0 if ok else 1


def _cmd_templates() -> int:
    rc = 0
    for name, builder_fn in TEMPLATES.items():
        path = FX_ASSETS_DIR / name
        raw_len, gz_len = builder_fn().write(path)
        errors = validate_file(path)
        if errors:
            print(f"FAIL {path}: " + "; ".join(errors))
            rc = 1
        else:
            print(f"WROTE {path.relative_to(REPO_ROOT)} (raw {raw_len} B, gzip {gz_len} B) — valid")
    return rc


def _cmd_validate(paths) -> int:
    rc = 0
    for p in paths:
        errors = validate_file(p)
        if errors:
            print(f"FAIL {p}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        else:
            print(f"OK   {p}")
    return rc


def main(argv) -> int:
    if len(argv) >= 1 and argv[0] == "selfcheck":
        return _cmd_selfcheck()
    if len(argv) >= 1 and argv[0] == "templates":
        return _cmd_templates()
    if len(argv) >= 2 and argv[0] == "validate":
        return _cmd_validate(argv[1:])
    if len(argv) == 2 and argv[0] == "dump":
        print(dump(read_fx_file(argv[1])))
        return 0
    print(__doc__.split("CLI:")[1].strip())
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
