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

Custom shaders (A0): `material_shader("eclipse:soft_particle", uniforms=..., textures=...)`
attaches a `custom_shader` material; `eclipse:<name>` resolves to
`assets/eclipse/shaders/core/<name>.json` and `validate` fails on unresolvable shader
references or overrides of undeclared uniform/sampler names. House shaders + uniform
tables: docs/plans_v3/session_0730/A0_SHADER_FOUNDATION.md.

CLI:
    python3 tools/photon/fxlib.py selfcheck          # templates + full-tree lint vs baseline
    python3 tools/photon/fxlib.py templates          # (re)generate the two smoke-test .fx assets
    python3 tools/photon/fxlib.py validate <f.fx>…   # parse + structure + round-trip any .fx
    python3 tools/photon/fxlib.py validate --lint [<f.fx>…]   # + the 15 PHOTON-QUALITY §5.2
                                                     # lint rules (no paths = whole FX tree,
                                                     # grandfathered via lint_baseline.txt;
                                                     # NEW error/warn findings fail)
    python3 tools/photon/fxlib.py validate --lint --update-baseline   # re-grandfather
    python3 tools/photon/fxlib.py write_fxproj [--missing | <f.fx>…]  # editor-openable
                                                     # .fxproj sibling(s) (binary-diff law)
    python3 tools/photon/fxlib.py dump <f.fx>        # pretty-print the NBT tree
"""
from __future__ import annotations

import gzip
import io
import json
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


def fxproj_root(fx_compound: dict) -> dict:
    """Wraps a built `.fx` root compound in the `.fxproj` project envelope (§7.1)."""
    return {"meta": {"version": "3.0", "suffix": ".fxproj", "name": "fx_project",
                     "version_num": I(3)},
            "data": {"fx": fx_compound}}


def read_fxproj_file(path) -> dict:
    """Reads an UNCOMPRESSED .fxproj and returns the inner `.fx` root compound."""
    root = read_root(Path(path).read_bytes())
    return root["data"]["fx"]


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


def material_shader(shader, uniforms=None, textures=None, curves=None, gradients=None,
                    blend=None, cull=True, depth_test=True, depth_mask=False):
    """`custom_shader` material — per-emitter GLSL (the A0 shader foundation).

    shader: `<ns>:<name>` core-shader reference; LDLib2 resolves it to
    `assets/<ns>/shaders/core/<name>.json` (jar-verified: `LDShaderInstance.create`
    builds `"shaders/core/" + path + ".json"`). House shaders (uniform knobs, recipes,
    blend guidance: docs/plans_v3/session_0730/A0_SHADER_FOUNDATION.md):

        eclipse:soft_particle      SceneDepth fade at geometry + camera (fog/smoke)
        eclipse:fresnel_shell      force-field: fresnel rim + SceneDepth seam glow
        eclipse:rgb_split_distort  SceneColor chromatic aberration + UV wobble

    uniforms: {name: scalar | (v, ...)} overrides of the JSON defaults, persisted like
    editor knobs (`_additional.shaderData.uniforms`). All-int values write an IntArray
    (int uniforms), anything else a Float list — write floats as floats (1.0, not 1).
    textures: {sampler_name: "<ns>:textures/....png"} for user-assignable samplers
    (names NOT starting with "Sampler", e.g. soft_particle's MainTexture) — persisted
    under `shaderData.samplers`; without an entry the sampler is unbound (black).
    curves / gradients: lists of `curve(...)` / `gradient(...)` NumberFunctions (or
    (alpha_pts, rgb_pts) tuples for gradients), baked row-by-row into the material's
    128x128 LUTs — GLSL reads them via getCurveValue/getGradientValue(row).
    Compile errors fail soft at runtime (fallback photon:hdr_particle + editor error);
    `validate` resolves the reference chain at authoring time instead.
    """
    data = {"shaderLocation": str(shader)}
    if curves:
        rows = []
        for c in curves:
            if not (isinstance(c, dict) and c.get("type") == "curve"
                    and isinstance(c.get("data"), dict)):
                raise ValueError("material_shader curves entries must be curve(...) NFs")
            rows.append(dict(c["data"]))
        data["curveTexture"] = L(rows)  # CurveTexture serializes as a bare ListTag
    if gradients:
        rows = []
        for g in gradients:
            if isinstance(g, dict) and g.get("type") == "gradient" \
                    and isinstance(g.get("data"), dict):
                rows.append(dict(g["data"]["gradientColor"]))
            elif isinstance(g, (list, tuple)) and len(g) == 2:
                rows.append(_gradient_color(g[0], g[1]))
            else:
                raise ValueError("material_shader gradients entries must be gradient(...)"
                                 " NFs or (alpha_pts, rgb_pts) tuples")
        data["gradientTexture"] = L(rows)  # GradientTexture serializes as a bare ListTag
    shader_data = {}
    if uniforms:
        packed = {}
        for name, value in uniforms.items():
            vals = list(value) if isinstance(value, (list, tuple)) else [value]
            if not vals:
                raise ValueError(f"material_shader uniform {name!r} has no values")
            if all(isinstance(v, int) and not isinstance(v, bool) for v in vals):
                packed[name] = IA([int(v) for v in vals])
            else:
                packed[name] = L([F(float(v)) for v in vals])
        shader_data["uniforms"] = packed
    if textures:
        shader_data["samplers"] = {
            str(name): {"type": "texture", "resource": str(rl)}
            for name, rl in textures.items()}
    if shader_data:
        data["_additional"] = {"shaderData": shader_data}
    mat = {"type": "custom_shader", "data": data}
    return _material_entry(mat, blend or BLEND_ALPHA, cull, depth_test, depth_mask)


def custom_shader_material(shader="photon:circle", curves=None, gradients=None,
                           blend=None, cull=True, depth_test=True, depth_mask=False):
    """DEPRECATED pre-A0 alias of material_shader (never shipped in any .fx). Fixed to
    write the jar-true bare-ListTag LUT layout — the old compound layout never loaded.

    curves: raw 8-float segment lists (wrapped as 0..1 lifetime curves); gradients:
    (alpha_pts, rgb_pts) tuples. New code: use material_shader directly.
    """
    return material_shader(
        shader,
        curves=[curve(0.0, 1.0, segs, "lifetime", "value") for segs in curves]
        if curves else None,
        gradients=list(gradients) if gradients else None,
        blend=blend or BLEND_ADDITIVE, cull=cull, depth_test=depth_test,
        depth_mask=depth_mask)


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
# Linear 0 -> 1 ramp. PROTOTYPING ONLY (v7 quality bar §5.1: shipping curves must be
# genuinely eased — see the house segments below).
SEG_LINEAR_UP = (0.0, 0.0, 0.33, 0.33, 0.66, 0.66, 1.0, 1.0)
# Linear 1 -> 0 ramp. PROTOTYPING ONLY (same rule).
SEG_LINEAR_DOWN = (0.0, 1.0, 0.33, 0.66, 0.66, 0.33, 1.0, 0.0)

# v7 house segments (PHOTON-QUALITY.md §5.1 rule 2) — control points genuinely off the
# chord so the lazy-linear lint (tolerance 0.02) never flags them.
# Ease-out crest: fast attack, soft settle at full value.
SEG_EASE_OUT_CREST = (0.0, 0.04, 0.15, 0.9, 0.6, 1.0, 1.0, 1.0)
# Overshoot-settle (iris): pop past the target, relax back to 1.
SEG_OVERSHOOT_SETTLE = (0.0, 0.2, 0.1, 1.15, 0.5, 0.95, 1.0, 1.0)
# Flicker -> commit: hesitate low, then commit to full.
SEG_FLICKER_COMMIT = (0.0, 0.15, 0.55, 0.35, 0.9, 1.0, 1.0, 1.0)
# Smoothstep rise / fall (horizontal tangents at both ends).
SEG_SMOOTH_UP = (0.0, 0.0, 0.33, 0.0, 0.67, 1.0, 1.0, 1.0)
SEG_SMOOTH_DOWN = (0.0, 1.0, 0.33, 1.0, 0.67, 0.0, 1.0, 0.0)
# Ease-in decay: hold near full, then accelerate to zero (soft die-off).
SEG_DECAY_TAIL = (0.0, 1.0, 0.35, 0.9, 0.7, 0.25, 1.0, 0.0)


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

    # Photon deserializes enum strings with valueOf-or-null: an unknown name leaves the
    # field NULL and the client NPE-crashes the first time such a particle renders
    # (TileParticle.renderInternal, "renderMode is null"). Validate at authoring time.
    _RENDER_MODES = {"None", "Billboard", "Horizontal", "Vertical", "VerticalBillboard",
                     "StretchedBillboard", "Model"}
    _FACING_MODES = {"DEFAULT", "ROTATE_Y", "LOOKAT_XYZ", "LOOKAT_Y", "LOOKAT_DIRECTION",
                     "DIRECTION_X", "DIRECTION_Y", "DIRECTION_Z", "EMITTER_TRANSFORM_XY",
                     "EMITTER_TRANSFORM_XZ", "EMITTER_TRANSFORM_YZ"}
    _LAYERS = {"Opaque", "Translucent"}
    _SORT_MODES = {"NONE", "DISTANCE"}

    @staticmethod
    def _enum(allowed, label):
        def conv(v):
            v = str(v)
            if v not in allowed:
                raise ValueError(f"invalid {label} {v!r} (Photon enum: {sorted(allowed)})")
            return v
        return conv

    def with_renderer(self, **kwargs):
        """Overrides renderer fields. Accepted keys (particle emitters unless noted):

        render_mode (None|Billboard|Horizontal|Vertical|VerticalBillboard|
        StretchedBillboard|Model), facing_mode, layer (Opaque|Translucent),
        order_in_layer, vertex_sorting (NONE|DISTANCE), shade, use_block_uv,
        use_gpu_instance, model_pivot (x,y,z), velocity_scale, length_scale.
        """
        m = {"render_mode": ("renderMode", self._enum(self._RENDER_MODES, "render_mode")),
             "facing_mode": ("facingMode", self._enum(self._FACING_MODES, "facing_mode")),
             "layer": ("layer", self._enum(self._LAYERS, "layer")),
             "vertex_sorting": ("vertexSortingMode", self._enum(self._SORT_MODES, "vertex_sorting")),
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
            # width is NF per FX_FORMAT.md §4.1 — accept curves etc., not just scalars.
            "end": L([F(float(v)) for v in end]), "width": _nf(width if _is_nf(width) else float(width)),
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
        """Writes the gzip NBT .fx file; round-trip-validates by default (incl. A0
        custom_shader reference resolution). Returns sizes."""
        raw, gz = self.to_bytes()
        if validate:
            errors = validate_tree(read_root(raw))
            errors.extend(_shader_ref_errors(read_root(raw)))
            if read_root(raw) != self.build() or write_root(read_root(raw)) != raw:
                errors.append("round-trip mismatch (writer/reader disagree)")
            if errors:
                raise ValueError(f"{self.name}: " + "; ".join(errors))
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(gz)
        return len(raw), len(gz)

    def write_fxproj(self, path, validate=True) -> int:
        """Writes the editor-openable `.fxproj` sibling (PHOTON-ADVANCED-1 §7).

        Exact `FXProject`/`ProjectType.saveProjectToFile` format: *** UNCOMPRESSED ***
        NBT (`NbtIo.write`, NOT gzip) wrapping the identical `.fx` compound:

            {meta: {version: "3.0", suffix: ".fxproj", name: "fx_project",
                    version_num: 3}, data: {fx: <the .fx root compound>}}

        `meta.version_num: 3` is the only field the loader reads — always 3, or the
        v1→v2→v3 fixer chain mangles modern data. Openable in-game via
        `/photon_editor` (singleplayer) → File → Open. Returns the byte size.
        """
        root = fxproj_root(self.build())
        raw = write_root(root)
        if validate:
            if read_root(raw) != root or write_root(read_root(raw)) != raw:
                raise ValueError(f"{self.name}: .fxproj round-trip mismatch")
            errors = validate_tree(read_root(raw)["data"]["fx"])
            if errors:
                raise ValueError(f"{self.name}: .fxproj inner fx invalid: " + "; ".join(errors))
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
        return len(raw)


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
    children = {}
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
        child_list = transform.get("_childrenId")
        if isinstance(child_list, L):
            children[oid] = (where, list(child_list.items))
        if fx_type != "empty":
            if not isinstance(data.get("config"), dict):
                errors.append(f"{where}: emitter without config compound")
            version = data.get("version")
            if not isinstance(version, I) or version.v != 2:
                errors.append(f"{where}: emitter version is {version!r}, expected Int 2")
        if isinstance(data.get("config"), dict):
            config_check = {"particle_emitter": _validate_particle_config,
                            "beam_emitter": _validate_beam_config,
                            "trail_emitter": _validate_trail_config,
                            "ara_trail_emitter": _validate_ara_trail_config}.get(fx_type)
            if config_check is not None:
                errors.extend(config_check(data["config"], where))
    for oid, (where, parent_id) in parents.items():
        if parent_id not in ids:
            errors.append(f"{where}: _parentId {parent_id} does not reference any object")
        elif oid not in children.get(parent_id, (None, []))[1]:
            errors.append(f"{where}: not listed in parent {parent_id}'s _childrenId")
        if parent_id == oid:
            errors.append(f"{where}: object is its own parent")
    for oid, (where, child_ids) in children.items():
        for child_id in child_ids:
            if child_id not in ids:
                errors.append(f"{where}: _childrenId {child_id} does not reference any object")
            elif parents.get(child_id, ("", None))[1] != oid:
                errors.append(f"{where}: child {child_id} does not link back via _parentId")
    return errors


def _validate_particle_config(config: dict, where: str) -> list:
    errors = []
    for key in ("emission", "shape"):
        if not isinstance(config.get(key), dict):
            errors.append(f"{where}: config.{key} missing/not a compound")
    for key, value in config.items():
        if isinstance(value, dict) and "_enable" in value and not isinstance(value["_enable"], B):
            errors.append(f"{where}: config.{key}._enable is not a Byte")
    errors.extend(_validate_renderer(config, where))
    errors.extend(_validate_nf_wrappers(config, f"{where}.config"))
    return errors


def _validate_renderer(config: dict, where: str) -> list:
    """renderer + its @ReadOnlyManaged materials list (all four emitter types carry one)."""
    renderer = config.get("renderer")
    if not isinstance(renderer, dict):
        return [f"{where}: config.renderer missing/not a compound"]
    materials = renderer.get("materials")
    if not (isinstance(materials, dict) and isinstance(materials.get("uid"), I)
            and isinstance(materials.get("payload"), L)
            and materials["uid"].v == len(materials["payload"].items)):
        return [f"{where}: renderer.materials is not a consistent ROM list"]
    return []


def _validate_beam_config(config: dict, where: str) -> list:
    """beam_emitter config (FX_FORMAT.md §4.1): end/width/emitRate/raycast shapes."""
    errors = _validate_renderer(config, where)
    end = config.get("end")
    if not (isinstance(end, L) and len(end.items) == 3
            and all(isinstance(v, F) for v in end.items)):
        errors.append(f"{where}: config.end is not a List of 3 Floats")
    for key in ("width", "emitRate"):
        if not _is_nf_wrapper(config.get(key)):
            errors.append(f"{where}: config.{key} is not a NumberFunction wrapper")
    if not isinstance(config.get("raycast"), str):
        errors.append(f"{where}: config.raycast missing/not a String")
    errors.extend(_validate_nf_wrappers(config, f"{where}.config"))
    return errors


def _validate_trail_config(config: dict, where: str) -> list:
    """trail_emitter config (FX_FORMAT.md §4.2): time/minVertexDistance/uvMode/width shapes."""
    errors = _validate_renderer(config, where)
    if not isinstance(config.get("time"), I):
        errors.append(f"{where}: config.time missing/not an Int (ticks)")
    if not isinstance(config.get("minVertexDistance"), F):
        errors.append(f"{where}: config.minVertexDistance missing/not a Float")
    if not isinstance(config.get("uvMode"), str):
        errors.append(f"{where}: config.uvMode missing/not a String")
    if not _is_nf_wrapper(config.get("widthOverTrail")):
        errors.append(f"{where}: config.widthOverTrail is not a NumberFunction wrapper")
    errors.extend(_validate_nf_wrappers(config, f"{where}.config"))
    return errors


def _validate_ara_trail_config(config: dict, where: str) -> list:
    """ara_trail_emitter config (FX_FORMAT.md §4.3). Only non-default keys are written,
    so every check here is presence-optional — but a present key must have the right shape
    (note time/timeInterval/minDistance are Float SECONDS, unlike the tick Ints elsewhere)."""
    errors = _validate_renderer(config, where)
    section = config.get("section")
    if section is not None:
        vertices = section.get("vertices") if isinstance(section, dict) else None
        if not (isinstance(vertices, L) and all(
                isinstance(v, L) and len(v.items) == 2
                and all(isinstance(x, F) for x in v.items) for v in vertices.items)):
            errors.append(f"{where}: config.section.vertices is not a List of [x,y] Float pairs")
    physics = config.get("physicsSetting")
    if physics is not None:
        if not isinstance(physics, dict):
            errors.append(f"{where}: config.physicsSetting is not a compound")
        else:
            for key in ("warmup", "inertia", "velocitySmoothing", "damping"):
                if not isinstance(physics.get(key), F):
                    errors.append(f"{where}: config.physicsSetting.{key} missing/not a Float")
            gravity = physics.get("gravity")
            if not (isinstance(gravity, L) and len(gravity.items) == 3
                    and all(isinstance(v, F) for v in gravity.items)):
                errors.append(f"{where}: config.physicsSetting.gravity is not a List of 3 Floats")
    for key in ("time", "timeInterval", "minDistance"):
        if key in config and not isinstance(config[key], F):
            errors.append(f"{where}: config.{key} is not a Float (seconds)")
    errors.extend(_validate_nf_wrappers(config, f"{where}.config"))
    return errors


_NUM_TAGS = (B, Sh, I, Lg, F, D)


def _is_nf_wrapper(v) -> bool:
    """A {type, data} dict whose type is an NF-family registry key (not shape/material)."""
    return isinstance(v, dict) and v.get("type") in KNOWN_NF_TYPES and "data" in v


def _validate_nf_wrappers(node, path) -> list:
    """Recursively checks every {type, data} dict that looks like a NumberFunction wrapper,
    including the required data members per NF type and the NF3 exactly-3 rule."""
    errors = []
    if isinstance(node, dict):
        if set(node.keys()) == {"type", "data"} and isinstance(node["type"], str):
            nf_type = node["type"]
            if nf_type in KNOWN_NF_TYPES:
                if isinstance(node["data"], dict):
                    errors.extend(_validate_nf_data(nf_type, node["data"], path))
                else:
                    errors.append(f"{path}: NF {nf_type} data is not a compound")
            elif nf_type == "custom_shader":
                if isinstance(node["data"], dict):
                    errors.extend(_validate_custom_shader_data(node["data"], path))
                else:
                    errors.append(f"{path}: custom_shader data is not a compound")
            elif nf_type not in (
                    "dot", "sphere", "circle", "cone", "cylinder", "box", "mesh", "function",
                    "texture", "sprite", "block_atlas"):
                errors.append(f"{path}: unknown {{type,data}} registry key {nf_type!r}")
        for key, value in node.items():
            errors.extend(_validate_nf_wrappers(value, f"{path}.{key}"))
    elif isinstance(node, L):
        # NumberFunction3 = a List whose items are ALL NF wrappers; must be exactly [x, y, z].
        if node.items and all(_is_nf_wrapper(item) for item in node.items) \
                and len(node.items) != 3:
            errors.append(f"{path}: NF3 list has {len(node.items)} entries, expected exactly 3")
        for idx, item in enumerate(node.items):
            errors.extend(_validate_nf_wrappers(item, f"{path}[{idx}]"))
    return errors


def _validate_nf_data(nf_type, data: dict, path) -> list:
    """Required data members + NBT tag shapes per NF type (FX_FORMAT.md §3)."""
    errors = []

    def need(key, kinds, desc):
        if not isinstance(data.get(key), kinds):
            errors.append(f"{path}: {nf_type} data.{key} missing/not {desc}")

    if nf_type == "constant":
        need("number", _NUM_TAGS, "a numeric tag")
    elif nf_type == "random_constant":
        need("a", _NUM_TAGS, "a numeric tag")
        need("b", _NUM_TAGS, "a numeric tag")
    elif nf_type in ("curve", "random_curve"):
        for key in ("min", "max", "lower", "upper"):
            need(key, F, "a Float")
        need("xAxis", str, "a String")
        need("yAxis", str, "a String")
        need("lockControlPoint", B, "a Byte")
        for key in (("curves",) if nf_type == "curve" else ("curves0", "curves1")):
            need(key, L, "a List of 8-float bezier segments")
            segments = data.get(key)
            if isinstance(segments, L) and not all(
                    isinstance(seg, L) and len(seg.items) == 8
                    and all(isinstance(x, F) for x in seg.items) for seg in segments.items):
                errors.append(f"{path}: {nf_type} data.{key} segment is not 8 Floats")
    elif nf_type == "color":
        need("number", I, "an Int (ARGB)")
    elif nf_type == "random_color":
        need("a", I, "an Int (ARGB)")
        need("b", I, "an Int (ARGB)")
    elif nf_type == "gradient":
        errors.extend(_validate_gradient_color(data.get("gradientColor"), f"{path}.gradientColor"))
    elif nf_type == "random_gradient":
        for key in ("gradientColor0", "gradientColor1"):
            errors.extend(_validate_gradient_color(data.get(key), f"{path}.{key}"))
    return errors


def _validate_gradient_color(gc, path) -> list:
    """GradientColor = {a: flat Float (t,alpha) pairs, rgb: flat Float (t,r,g,b) quads}."""
    if not isinstance(gc, dict):
        return [f"{path}: missing/not a compound"]
    errors = []
    for key, stride in (("a", 2), ("rgb", 4)):
        val = gc.get(key)
        if not (isinstance(val, L) and all(isinstance(x, F) for x in val.items)
                and len(val.items) % stride == 0):
            errors.append(f"{path}.{key}: not a flat Float list in strides of {stride}")
    return errors


def _validate_custom_shader_data(data: dict, path) -> list:
    """custom_shader material data (A0, jar-verified layout): `shaderLocation` string,
    bare-ListTag `curveTexture`/`gradientTexture` LUT rows, and the
    `_additional.shaderData.{uniforms,samplers}` override compounds."""
    errors = []
    loc = data.get("shaderLocation")
    if not isinstance(loc, str) or not loc:
        errors.append(f"{path}: custom_shader data.shaderLocation missing/not a String")
    for key in ("curveTexture", "gradientTexture"):
        rows = data.get(key)
        if rows is None:
            continue
        if not isinstance(rows, L):
            errors.append(f"{path}: custom_shader data.{key} is not a bare ListTag "
                          "(the pre-A0 compound layout never loads — regenerate)")
            continue
        for idx, row in enumerate(rows.items):
            if not isinstance(row, dict):
                errors.append(f"{path}: {key}[{idx}] is not a compound")
            elif key == "curveTexture":
                errors.extend(_validate_nf_data("curve", row, f"{path}.{key}[{idx}]"))
            else:
                errors.extend(_validate_gradient_color(row, f"{path}.{key}[{idx}]"))
    additional = data.get("_additional")
    if additional is None:
        return errors
    shader_data = additional.get("shaderData") if isinstance(additional, dict) else None
    if not isinstance(shader_data, dict):
        errors.append(f"{path}: custom_shader _additional.shaderData missing/not a compound")
        return errors
    uniforms = shader_data.get("uniforms")
    if uniforms is not None and not isinstance(uniforms, dict):
        errors.append(f"{path}: shaderData.uniforms is not a compound")
    elif isinstance(uniforms, dict):
        for name, value in uniforms.items():
            ok = isinstance(value, IA) or (isinstance(value, L) and value.items
                                           and all(isinstance(x, F) for x in value.items))
            if not ok:
                errors.append(f"{path}: shaderData.uniforms.{name} must be a Float List "
                              "(float uniform) or an IntArray (int uniform)")
    samplers = shader_data.get("samplers")
    if samplers is not None and not isinstance(samplers, dict):
        errors.append(f"{path}: shaderData.samplers is not a compound")
    elif isinstance(samplers, dict):
        for name, value in samplers.items():
            if not (isinstance(value, dict) and value.get("type") == "texture"
                    and isinstance(value.get("resource"), str)):
                errors.append(f"{path}: shaderData.samplers.{name} must be "
                              "{type: \"texture\", resource: \"<rl>\"}")
    return errors


#: custom_shader references shipped INSIDE the Photon 2.1.5 jar
#: (`assets/photon/shaders/core/*.json`, jar-verified) — resolvable without our assets.
PHOTON_JAR_SHADERS = {
    "photon:circle", "photon:hdr_particle", "photon:sprite_hdr_particle",
    "photon:pixel_hdr_particle"}


def _walk_shader_materials(node, out):
    """Collects every custom_shader material `data` compound in a tree."""
    if isinstance(node, dict):
        if node.get("type") == "custom_shader" and isinstance(node.get("data"), dict):
            out.append(node["data"])
        for value in node.values():
            _walk_shader_materials(value, out)
    elif isinstance(node, L):
        for item in node.items:
            _walk_shader_materials(item, out)


def _shader_ref_errors(tree) -> list:
    """A0 validate hook — custom_shader references must resolve at authoring time
    (runtime is fail-soft: a missing/broken shader silently renders photon:hdr_particle).

    Per material: `shaderLocation` must be in PHOTON_JAR_SHADERS or resolve to
    `assets/eclipse/shaders/core/<name>.json`; that JSON must parse with vertex+fragment
    programs whose eclipse: files exist; every uniform/texture override must target a
    name declared in the JSON (a typo'd override is a silent no-op in-game)."""
    materials = []
    _walk_shader_materials(tree, materials)
    errors = []
    for data in materials:
        loc = data.get("shaderLocation")
        if not isinstance(loc, str) or not loc:
            continue  # _validate_custom_shader_data already flagged it
        if loc in PHOTON_JAR_SHADERS:
            continue  # jar-shipped; overrides not introspectable from here
        ns, _, name = loc.partition(":")
        if not name:
            ns, name = "minecraft", ns
        if ns != "eclipse":
            errors.append(f"custom_shader {loc!r}: unknown shader reference (known: "
                          f"eclipse:* under assets/eclipse/shaders/core/ or the photon "
                          f"jar set {sorted(PHOTON_JAR_SHADERS)})")
            continue
        json_path = SHADER_ASSETS_DIR / (name + ".json")
        if not json_path.exists():
            errors.append(f"custom_shader {loc!r}: no {name}.json under "
                          f"{SHADER_ASSETS_DIR.relative_to(REPO_ROOT)} "
                          "(runtime fail-soft = falls back to photon:hdr_particle)")
            continue
        try:
            spec = json.loads(json_path.read_text(encoding="utf-8"))
        except Exception as exc:
            errors.append(f"custom_shader {loc!r}: {json_path.name} is not valid JSON: {exc}")
            continue
        for key, ext in (("vertex", ".vsh"), ("fragment", ".fsh"), ("geometry", ".gsh")):
            prog = spec.get(key)
            if prog is None:
                if key != "geometry":  # geometry is the optional LDLib2 extension
                    errors.append(f"custom_shader {loc!r}: {json_path.name} lacks the "
                                  f"required {key!r} program")
                continue
            p_ns, _, p_name = str(prog).partition(":")
            if not p_name:
                p_ns, p_name = "minecraft", p_ns
            if p_ns == "eclipse" and not (SHADER_ASSETS_DIR / (p_name + ext)).exists():
                errors.append(f"custom_shader {loc!r}: {key} program {prog!r} has no "
                              f"{p_name}{ext} under "
                              f"{SHADER_ASSETS_DIR.relative_to(REPO_ROOT)}")
        declared_uniforms = {u.get("name") for u in spec.get("uniforms", ())
                             if isinstance(u, dict)}
        declared_samplers = {s.get("name") for s in spec.get("samplers", ())
                             if isinstance(s, dict)}
        additional = data.get("_additional")
        shader_data = additional.get("shaderData") if isinstance(additional, dict) else None
        shader_data = shader_data if isinstance(shader_data, dict) else {}
        uniforms = shader_data.get("uniforms")
        for uname in (uniforms.keys() if isinstance(uniforms, dict) else ()):
            if uname not in declared_uniforms:
                errors.append(f"custom_shader {loc!r}: uniform override {uname!r} is not "
                              f"declared in {json_path.name} (silent no-op in-game)")
        samplers = shader_data.get("samplers")
        for sname in (samplers.keys() if isinstance(samplers, dict) else ()):
            if sname not in declared_samplers:
                errors.append(f"custom_shader {loc!r}: texture override {sname!r} is not "
                              f"a declared sampler in {json_path.name}")
    return errors


def validate_file(path) -> list:
    """Full check of an on-disk .fx: gzip + parse + structure + shader-reference
    resolution + writer/reader round-trip."""
    try:
        raw = gzip.decompress(Path(path).read_bytes())
    except Exception as exc:
        return [f"not gzip-compressed NBT: {exc}"]
    try:
        tree = read_root(raw)
    except Exception as exc:
        return [f"NBT parse failed: {exc}"]
    errors = validate_tree(tree)
    errors.extend(_shader_ref_errors(tree))
    if write_root(tree) != raw:
        errors.append("round-trip mismatch: re-serialized NBT differs from file bytes")
    return errors


# ---------------------------------------------------------------------------
# Lint — the PHOTON-QUALITY.md §5.2 warning channel (`validate --lint`)
# ---------------------------------------------------------------------------
# Severities: "error"/"warn" findings gate against the committed baseline
# (tools/photon/lint_baseline.txt — current violations grandfathered, NEW ones fail,
# the count may only go down); "info" findings are purely advisory and never fail.
LINT_BASELINE_FILE = Path(__file__).resolve().parent / "lint_baseline.txt"

#: Chord-collinearity tolerance for LINT-LINEAR-CURVE (PHOTON-QUALITY.md method note).
LINEAR_CURVE_TOL = 0.02
#: Sanctioned single-emitter child-file suffixes (LINT-SINGLE-EMITTER allowlist).
CHILD_FILE_SUFFIXES = ("_puff", "_glint", "_sparkle", "_pop", "_trail", "_ribbon")
#: v7 palette tokens, FX-STYLE-GUIDE.md §1 (LINT-PALETTE advisory distance check).
PALETTE_TOKENS = {
    "SAC_HOT": 0xF6EFFF, "SAC_VIOLET": 0xB98CFF, "SAC_DEEP": 0x7B4FD0,
    "SAC_GOLD": 0xFFD166, "SAC_GOLD_PALE": 0xFFE9A8, "SAC_VOID": 0x2E2347,
    "COR_BILE": 0x9BD8B4, "COR_MOSS": 0x6FA98C, "COR_VIOLET": 0x9D4EDD,
    "COR_INK": 0x3C096C, "COR_PALE": 0xD9FFE8,
    "GLI_MAGENTA": 0xFF4FD8, "GLI_CYAN": 0x4FE8FF, "GLI_WHITE": 0xFFFFFF,
    "GLI_VIOLET": 0xB98CFF, "GLI_DEAD": 0x241C38,
    "ERA_CREAM": 0xFFF3C4, "ERA_AMBER": 0xFFB25E, "ERA_EMBER": 0xFF7B3C,
    "ERA_SHADOW": 0x3A3A55,
    "STM_SLATE": 0x3A3A55, "STM_ARC": 0xBFD9FF, "STM_DEEP": 0x5A8DEE,
}
#: Advisory RGB distance (unit cube, Euclidean) beyond which a stop is off-palette.
PALETTE_TOLERANCE = 0.25


class LintFinding:
    """One lint finding. `key` (file-relative id | rule | context) is the stable
    baseline identity — context uses emitter names/paths, never list indices alone,
    so regenerating an unchanged asset keeps its grandfathered entries stable."""

    __slots__ = ("rule", "severity", "file_id", "context", "message")

    def __init__(self, rule, severity, file_id, context, message):
        self.rule = rule
        self.severity = severity
        self.file_id = file_id
        self.context = context
        self.message = message

    @property
    def key(self) -> str:
        return f"{self.file_id}|{self.rule}|{self.context}"

    def __str__(self):
        return f"[{self.severity.upper():5}] {self.rule} {self.file_id} ({self.context}): {self.message}"


def _lint_file_id(path: Path) -> str:
    """Stable per-file baseline id: path relative to FX_ASSETS_DIR when possible."""
    path = Path(path).resolve()
    try:
        return path.relative_to(FX_ASSETS_DIR).as_posix()
    except ValueError:
        return path.name


def _num_val(tag, default=None):
    return tag.v if isinstance(tag, _NUM_TAGS) else default


def _nf_max(nf, default=0.0):
    """Best-effort maximum of a NumberFunction (burst counts: constant / random / curve)."""
    if not _is_nf_wrapper(nf):
        return default
    data = nf.get("data", {})
    if nf["type"] == "constant":
        return _num_val(data.get("number"), default)
    if nf["type"] == "random_constant":
        a = _num_val(data.get("a"), default)
        b = _num_val(data.get("b"), default)
        return max(a, b)
    if nf["type"] in ("curve", "random_curve"):
        return _num_val(data.get("upper"), _num_val(data.get("max"), default))
    return default


def _segment_linear(seg, tol=LINEAR_CURVE_TOL) -> bool:
    """True when both control points sit within `tol` of the p0->p1 chord (normalized xy)."""
    p0x, p0y, c0x, c0y, c1x, c1y, p1x, p1y = (x.v for x in seg.items)
    dx, dy = p1x - p0x, p1y - p0y
    length = math.hypot(dx, dy)
    for cx, cy in ((c0x, c0y), (c1x, c1y)):
        if length < 1e-9:
            dist = math.hypot(cx - p0x, cy - p0y)
        else:
            dist = abs(dy * (cx - p0x) - dx * (cy - p0y)) / length
        if dist > tol:
            return False
    return True


def _curve_all_linear(nf) -> bool:
    """LINT-LINEAR-CURVE core: every bezier segment of the curve (both curves for a
    random_curve) is chord-collinear within tolerance."""
    data = nf.get("data", {})
    keys = ("curves",) if nf["type"] == "curve" else ("curves0", "curves1")
    segments = []
    for key in keys:
        seg_list = data.get(key)
        if isinstance(seg_list, L):
            segments.extend(s for s in seg_list.items
                            if isinstance(s, L) and len(s.items) == 8
                            and all(isinstance(x, F) for x in s.items))
    return bool(segments) and all(_segment_linear(seg) for seg in segments)


def _walk_nf(node, path, out):
    """Collects (path, nf_dict) for every NumberFunction wrapper under `node`."""
    if isinstance(node, dict):
        if _is_nf_wrapper(node):
            out.append((path, node))
            return  # NF data never nests further NFs we lint
        for key, value in node.items():
            _walk_nf(value, f"{path}.{key}", out)
    elif isinstance(node, L):
        for idx, item in enumerate(node.items):
            _walk_nf(item, f"{path}[{idx}]", out)


def _hdr_rgb(material) -> tuple:
    """(r, g, b) of a material's hdr vector, or (0, 0, 0) when absent. custom_shader
    materials report their strongest `*HDR*` vec4 uniform override as rgb * a (the
    house `color.rgb += HDR.a * HDR.rgb` convention), so the bloom lints still bite."""
    if not isinstance(material, dict):
        return (0.0, 0.0, 0.0)
    data = material.get("data", {})
    data = data if isinstance(data, dict) else {}
    hdr = data.get("hdr")
    if isinstance(hdr, L) and len(hdr.items) >= 3 and all(isinstance(x, F) for x in hdr.items[:3]):
        return tuple(x.v for x in hdr.items[:3])
    if material.get("type") == "custom_shader":
        best = (0.0, 0.0, 0.0)
        additional = data.get("_additional")
        shader_data = additional.get("shaderData") if isinstance(additional, dict) else None
        uniforms = shader_data.get("uniforms") if isinstance(shader_data, dict) else None
        for name, value in (uniforms.items() if isinstance(uniforms, dict) else ()):
            if "hdr" not in name.lower() or not isinstance(value, L):
                continue
            vals = [x.v for x in value.items if isinstance(x, F)]
            if len(vals) >= 4:
                boosted = tuple(v * vals[3] for v in vals[:3])
                if max(boosted) > max(best):
                    best = boosted
        return best
    return (0.0, 0.0, 0.0)


def _material_entries(renderer) -> list:
    materials = renderer.get("materials") if isinstance(renderer, dict) else None
    if isinstance(materials, dict) and isinstance(materials.get("payload"), L):
        return [m for m in materials["payload"].items if isinstance(m, dict)]
    return []


def _rgb_dist(argb_a: int, rgb_b: tuple) -> float:
    ra, ga, ba = (argb_a >> 16 & 0xFF) / 255.0, (argb_a >> 8 & 0xFF) / 255.0, (argb_a & 0xFF) / 255.0
    return math.dist((ra, ga, ba), rgb_b)


def _off_palette(rgb: tuple) -> bool:
    return all(_rgb_dist(hexv, rgb) > PALETTE_TOLERANCE for hexv in PALETTE_TOKENS.values())


def _color_stops(nf) -> list:
    """All RGB stops (0..1 floats) carried by a color-family NumberFunction."""
    data = nf.get("data", {})
    stops = []
    if nf["type"] in ("color", "random_color"):
        for key in (("number",) if nf["type"] == "color" else ("a", "b")):
            argb = _num_val(data.get(key))
            if argb is not None:
                argb &= 0xFFFFFFFF
                stops.append(((argb >> 16 & 0xFF) / 255.0, (argb >> 8 & 0xFF) / 255.0,
                              (argb & 0xFF) / 255.0))
    elif nf["type"] in ("gradient", "random_gradient"):
        keys = ("gradientColor",) if nf["type"] == "gradient" \
            else ("gradientColor0", "gradientColor1")
        for key in keys:
            gc = data.get(key)
            rgb = gc.get("rgb") if isinstance(gc, dict) else None
            if isinstance(rgb, L) and all(isinstance(x, F) for x in rgb.items):
                vals = [x.v for x in rgb.items]
                for i in range(0, len(vals) - 3, 4):
                    stops.append((vals[i + 1], vals[i + 2], vals[i + 3]))
    return stops


def _resolve_fx_location(location: str):
    """`eclipse:<path>` → the on-disk .fx Path under FX_ASSETS_DIR, else None."""
    ns, _, rel = location.partition(":")
    if not rel:
        ns, rel = "minecraft", ns
    if ns != "eclipse":
        return None
    return FX_ASSETS_DIR / (rel + ".fx")


def _walk_fx_locations(node, out):
    """Collects every `fxLocation` string (subEmitters rows + any trails child refs)."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "fxLocation" and isinstance(value, str):
                out.append(value)
            else:
                _walk_fx_locations(value, out)
    elif isinstance(node, L):
        for item in node.items:
            _walk_fx_locations(item, out)


def _child_burst_sum(path: Path) -> float:
    """Burst particle total of a sub-emitter child file (count × cycles over every
    particle emitter; cycles 0 = infinite → +inf)."""
    try:
        tree = read_fx_file(path)
    except Exception:
        return 0.0
    total = 0.0
    for wrapper in tree.get("fxData", {}).get("fxObjects", L([])).items:
        if not isinstance(wrapper, dict) or wrapper.get("type") != "particle_emitter":
            continue
        config = wrapper.get("data", {}).get("config", {})
        bursts = config.get("emission", {}).get("bursts", {})
        for row in bursts.get("payload", L([])).items if isinstance(bursts.get("payload"), L) else []:
            if not isinstance(row, dict):
                continue
            cycles = _num_val(row.get("cycles"), 1)
            if cycles == 0:
                return float("inf")
            total += _nf_max(row.get("count"), 0.0) * max(1, cycles)
    return total


def lint_file(path) -> list:
    """The 15 PHOTON-QUALITY.md §5.2 lint rules over one on-disk .fx file.

    Returns a list of LintFinding (severity error/warn/info). Structural validity is
    assumed — run validate_file first; a parse failure yields a single error finding.
    """
    path = Path(path)
    file_id = _lint_file_id(path)
    try:
        tree = read_fx_file(path)
    except Exception as exc:
        return [LintFinding("LINT-PARSE", "error", file_id, "-", f"unreadable .fx: {exc}")]
    findings = []

    # LINT-FXPROJ — binary-diff law: the editor-openable sibling must ship too.
    if not path.with_suffix(".fxproj").exists():
        findings.append(LintFinding("LINT-FXPROJ", "warn", file_id, "-",
                                    "no sibling .fxproj next to the .fx"))

    objects = tree.get("fxData", {}).get("fxObjects", L([]))
    renderable = [w for w in objects.items
                  if isinstance(w, dict) and w.get("type") in KNOWN_TYPES and w["type"] != "empty"]

    # LINT-SINGLE-EMITTER — legal only for sub-emitter children / bare ribbons.
    stem = path.stem
    if len(renderable) == 1 and not stem.endswith(CHILD_FILE_SUFFIXES):
        findings.append(LintFinding(
            "LINT-SINGLE-EMITTER", "info", file_id, "-",
            f"1 renderable object and {stem!r} does not match the child-suffix allowlist "
            f"{'/'.join(CHILD_FILE_SUFFIXES)}"))

    for wrapper in renderable:
        fx_type = wrapper["type"]
        data = wrapper.get("data", {})
        name = data.get("name", "?")
        config = data.get("config", {})
        if not isinstance(config, dict):
            continue
        renderer = config.get("renderer", {})
        renderer = renderer if isinstance(renderer, dict) else {}
        looping = _num_val(config.get("looping"), 1) == 1  # schema default: 1b
        duration = _num_val(config.get("duration"), 100)
        cull_on = isinstance(renderer.get("cull"), dict) \
            and _num_val(renderer["cull"].get("_enable"), 0) == 1

        # LINT-CULL-LOOP (error) — golden rule: every looping emitter carries a cull box.
        if fx_type in ("particle_emitter", "trail_emitter", "ara_trail_emitter") \
                and looping and not cull_on:
            findings.append(LintFinding("LINT-CULL-LOOP", "error", file_id, name,
                                        "looping emitter without renderer.cull._enable: 1b"))

        if fx_type == "particle_emitter":
            max_particles = _num_val(config.get("maxParticles"))
            gpu = _num_val(renderer.get("useGPUInstance"), 0) == 1
            physics = config.get("physics")
            physics_on = isinstance(physics, dict) and _num_val(physics.get("_enable"), 0) == 1
            parallel_update = _num_val(config.get("parallelUpdate"), 0) == 1

            # LINT-MAXP-DEFAULT (error) — the unset 2000 default is never deliberate.
            if max_particles is None or max_particles == 2000:
                findings.append(LintFinding(
                    "LINT-MAXP-DEFAULT", "error", file_id, name,
                    "maxParticles absent or at the 2000 unset default"))
            # LINT-MAXP-CPU (warn) — big emitters must be GPU-instanced.
            if max_particles is not None and max_particles > 512 and not gpu:
                findings.append(LintFinding(
                    "LINT-MAXP-CPU", "warn", file_id, name,
                    f"maxParticles {max_particles} > 512 without useGPUInstance: 1b"))
            # LINT-GPU-PHYSICS (error) — collision physics needs level access.
            if (parallel_update or gpu) and physics_on:
                findings.append(LintFinding(
                    "LINT-GPU-PHYSICS", "error", file_id, name,
                    "parallelUpdate/useGPUInstance together with enabled physics"))
            # LINT-PREWARM (error).
            prewarm = _num_val(config.get("prewarm"), 0)
            if prewarm > duration:
                findings.append(LintFinding(
                    "LINT-PREWARM", "error", file_id, name,
                    f"prewarm {prewarm} > duration {duration}"))
            # LINT-BURST-WINDOW (warn) — one-shot bursts must land inside the window.
            if not looping:
                bursts = config.get("emission", {}).get("bursts", {})
                payload = bursts.get("payload") if isinstance(bursts, dict) else None
                for row in payload.items if isinstance(payload, L) else []:
                    if not isinstance(row, dict):
                        continue
                    time = _num_val(row.get("time"), 0)
                    cycles = _num_val(row.get("cycles"), 1)
                    interval = _num_val(row.get("interval"), 1)
                    last = float("inf") if cycles == 0 else time + (cycles - 1) * interval
                    if last >= duration:
                        findings.append(LintFinding(
                            "LINT-BURST-WINDOW", "warn", file_id, f"{name}:burst@{time}",
                            f"burst time {time} + (cycles-1)*interval reaches tick "
                            f"{last} >= duration {duration} on a one-shot"))

            # LINT-SUBEM-RESOLVE (error) + LINT-SUBEM-FAT (warn).
            locations = []
            _walk_fx_locations(config.get("subEmitters", {}), locations)
            _walk_fx_locations(config.get("trails", {}), locations)
            for location in locations:
                child = _resolve_fx_location(location)
                if child is None or not child.exists():
                    findings.append(LintFinding(
                        "LINT-SUBEM-RESOLVE", "error", file_id, f"{name}:{location}",
                        f"fxLocation {location!r} does not resolve to a file under "
                        f"{FX_ASSETS_DIR.relative_to(REPO_ROOT)} (runtime fail-soft = silent no-op)"))
                else:
                    burst_sum = _child_burst_sum(child)
                    if burst_sum > 8:
                        findings.append(LintFinding(
                            "LINT-SUBEM-FAT", "warn", file_id, f"{name}:{location}",
                            f"sub-emitter child {location!r} burst count sum "
                            f"{burst_sum:g} > 8 (each stamp deep-copies a runtime)"))

        # Material passes (all four renderable kinds carry a renderer).
        sorting = renderer.get("vertexSortingMode", "NONE")
        shade = _num_val(renderer.get("shade"), 0) == 1
        for m_idx, entry in enumerate(_material_entries(renderer)):
            blend_mode = entry.get("blendMode", {})
            blend_mode = blend_mode if isinstance(blend_mode, dict) else {}
            alpha_blended = blend_mode.get("dstColorFactor") == "ONE_MINUS_SRC_ALPHA"
            depth_mask = _num_val(entry.get("depthMask"), 0) == 1
            r, g, b = _hdr_rgb(entry.get("material", {}))
            hdr_on = max(r, g, b) > 0
            # LINT-ALPHA-NOSORT (warn) — translucent quads need ordering or depth writes.
            if alpha_blended and sorting == "NONE" and not depth_mask:
                findings.append(LintFinding(
                    "LINT-ALPHA-NOSORT", "warn", file_id, f"{name}:material[{m_idx}]",
                    "dstColorFactor ONE_MINUS_SRC_ALPHA with vertexSortingMode NONE "
                    "and depthMask 0b"))
            # LINT-HDR-DUST (warn) — world-lit dust must not bloom.
            if hdr_on and alpha_blended and shade:
                findings.append(LintFinding(
                    "LINT-HDR-DUST", "warn", file_id, f"{name}:material[{m_idx}]",
                    f"hdr ({r:g},{g:g},{b:g}) on an alpha-blended material with shade: 1b"))
            # LINT-HDR-CEILING (warn) — ≤ 4.0 pending the Iris pair test.
            if max(r, g, b) > 4.0:
                findings.append(LintFinding(
                    "LINT-HDR-CEILING", "warn", file_id, f"{name}:material[{m_idx}]",
                    f"hdr channel ({r:g},{g:g},{b:g}) exceeds the 4.0 ceiling"))

        # LINT-LINEAR-CURVE (warn) — lazy piecewise-linear envelopes; suppressed for
        # uvAnimation.frameOverTime scans and shape.* arc/animation inputs (spec'd linear).
        nfs = []
        _walk_nf(config, name, nfs)
        for nf_path, nf in nfs:
            if nf["type"] not in ("curve", "random_curve"):
                continue
            if ".uvAnimation." in nf_path and nf_path.endswith("frameOverTime"):
                continue
            if ".shape." in nf_path or nf_path.endswith(".shape"):
                continue
            if _curve_all_linear(nf):
                findings.append(LintFinding(
                    "LINT-LINEAR-CURVE", "warn", file_id, nf_path,
                    "all bezier segments chord-collinear (tol 0.02) — ship an eased "
                    "curve (see FX-STYLE-GUIDE house segments)"))

        # LINT-PALETTE (info, advisory) — startColor/gradient stops vs the §1 tokens.
        off_stops = 0
        for nf_path, nf in nfs:
            if nf["type"] not in ("color", "random_color", "gradient", "random_gradient"):
                continue
            off_stops += sum(1 for stop in _color_stops(nf) if _off_palette(stop))
        if off_stops:
            findings.append(LintFinding(
                "LINT-PALETTE", "info", file_id, name,
                f"{off_stops} RGB stop(s) further than {PALETTE_TOLERANCE} from every "
                "FX-STYLE-GUIDE §1 token (advisory — mids may legitimately pass off-token)"))

    return findings


def read_lint_baseline() -> set:
    """Grandfathered finding keys (empty set when the baseline file is absent)."""
    if not LINT_BASELINE_FILE.exists():
        return set()
    keys = set()
    for line in LINT_BASELINE_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            keys.add(line)
    return keys


def write_lint_baseline(findings) -> int:
    """(Re)writes the grandfather baseline from error/warn findings. Returns the count."""
    keys = sorted({f.key for f in findings if f.severity in ("error", "warn")})
    header = (
        "# fxlib lint baseline — grandfathered PHOTON-QUALITY.md §5.2 violations.\n"
        "# One `<file>|<rule>|<context>` key per line. Entries here PASS `validate --lint`;\n"
        "# NEW violations fail. The count may only go down: fix a violation, then delete\n"
        "# its line (or regenerate via `fxlib.py validate --lint --update-baseline` AFTER\n"
        "# review — never to sneak new violations in). Info-severity findings are advisory\n"
        "# and never listed.\n")
    LINT_BASELINE_FILE.write_text(header + "\n".join(keys) + "\n", encoding="utf-8")
    return len(keys)


def all_fx_files() -> list:
    """Every committed .fx under FX_ASSETS_DIR (sorted, boss/ included)."""
    return sorted(FX_ASSETS_DIR.rglob("*.fx"))


def write_fxproj_sibling(fx_path) -> int:
    """Writes the editor-openable `.fxproj` sibling for an EXISTING on-disk `.fx`
    (uncompressed NBT `{meta, data.fx}` envelope, see FxBuilder.write_fxproj).
    Round-trip-validated; returns the byte size."""
    fx_path = Path(fx_path)
    root = fxproj_root(read_fx_file(fx_path))
    raw = write_root(root)
    if read_root(raw) != root or write_root(read_root(raw)) != raw:
        raise ValueError(f"{fx_path}: .fxproj round-trip mismatch")
    errors = validate_tree(read_root(raw)["data"]["fx"])
    if errors:
        raise ValueError(f"{fx_path}: .fxproj inner fx invalid: " + "; ".join(errors))
    out = fx_path.with_suffix(".fxproj")
    out.write_bytes(raw)
    return len(raw)


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
#: A0 custom-shader home: `eclipse:<name>` <-> `assets/eclipse/shaders/core/<name>.json`
#: (LDLib2 path law, see material_shader / A0_SHADER_FOUNDATION.md).
SHADER_ASSETS_DIR = REPO_ROOT / "src/main/resources/assets/eclipse/shaders/core"


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
    # PHOTON-QUALITY §5.2: the lint set over the whole FX tree, baseline-grandfathered.
    if _cmd_validate([], lint=True) != 0:
        ok = False
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


def _cmd_validate(paths, lint=False, update_baseline=False) -> int:
    rc = 0
    if lint and not paths:
        paths = all_fx_files()
    for p in paths:
        errors = validate_file(p)
        if errors:
            print(f"FAIL {p}:")
            for e in errors:
                print(f"  - {e}")
            rc = 1
        elif not lint:
            print(f"OK   {p}")
    if not lint:
        return rc

    findings = []
    for p in paths:
        findings.extend(lint_file(p))
    if update_baseline:
        count = write_lint_baseline(findings)
        print(f"lint baseline rewritten: {count} grandfathered error/warn finding(s) "
              f"-> {LINT_BASELINE_FILE.relative_to(REPO_ROOT)}")
        return rc

    baseline = read_lint_baseline()
    new, grandfathered, infos = [], [], []
    for finding in findings:
        if finding.severity == "info":
            infos.append(finding)
        elif finding.key in baseline:
            grandfathered.append(finding)
        else:
            new.append(finding)
    for finding in new:
        print(f"NEW  {finding}")
    for finding in infos:
        print(f"     {finding}")
    seen_keys = {f.key for f in findings}
    stale = sorted(k for k in baseline if k not in seen_keys
                   and any(_lint_file_id(Path(p)) == k.split("|", 1)[0] for p in paths))
    if stale:
        print(f"lint: {len(stale)} baseline entr(ies) no longer fire — prune them from "
              f"{LINT_BASELINE_FILE.name}:")
        for key in stale:
            print(f"  - {key}")
    print(f"lint: {len(paths)} file(s), {len(new)} NEW error/warn, "
          f"{len(grandfathered)} grandfathered, {len(infos)} advisory info")
    if new:
        print("lint FAILED (new violations — fix them or, for a sanctioned exception, "
              "add the key to lint_baseline.txt with a review note)")
        return 1
    return rc


def _cmd_write_fxproj(args) -> int:
    if args == ["--missing"]:
        targets = [p for p in all_fx_files() if not p.with_suffix(".fxproj").exists()]
        if not targets:
            print("write_fxproj: every .fx already has a sibling .fxproj")
            return 0
    else:
        targets = [Path(a) for a in args]
    rc = 0
    for fx_path in targets:
        try:
            size = write_fxproj_sibling(fx_path)
        except Exception as exc:
            print(f"FAIL {fx_path}: {exc}")
            rc = 1
            continue
        out = fx_path.with_suffix(".fxproj")
        try:
            rel = out.relative_to(REPO_ROOT)
        except ValueError:
            rel = out
        print(f"WROTE {rel} ({size} B, uncompressed NBT) — valid")
    return rc


def main(argv) -> int:
    if len(argv) >= 1 and argv[0] == "selfcheck":
        return _cmd_selfcheck()
    if len(argv) >= 1 and argv[0] == "templates":
        return _cmd_templates()
    if len(argv) >= 1 and argv[0] == "validate":
        rest = argv[1:]
        lint = "--lint" in rest
        update_baseline = "--update-baseline" in rest
        rest = [a for a in rest if a not in ("--lint", "--update-baseline")]
        if not lint and (update_baseline or not rest):
            print("validate: pass .fx paths, or use --lint for the whole FX tree")
            return 2
        return _cmd_validate(rest, lint=lint, update_baseline=update_baseline)
    if len(argv) >= 2 and argv[0] == "write_fxproj":
        return _cmd_write_fxproj(argv[1:])
    if len(argv) == 2 and argv[0] == "dump":
        print(dump(read_fx_file(argv[1])))
        return 0
    print(__doc__.split("CLI:")[1].strip())
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
