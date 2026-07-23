#!/usr/bin/env python3
"""Validator/linter for GeckoLib assets in Blockbench Bedrock-model format (P6-W1).

Validates `.geo.json` geometry files and `.animation.json` animation files exactly as
GeckoLib 4.9.2 + Blockbench 4.x consume them (see
`docs/plans_v3/handoff/P6_geckolib_conventions.md`):

* geometry: `format_version` 1.12.0, `minecraft:geometry` list, description identifier
  `geometry.<id>` + `texture_width/height`, bones (unique names, resolvable acyclic
  parents, pivot/rotation arity), cubes (origin/size arity, non-negative size, box-UV
  face rects or per-face UV rects fully inside the texture canvas).
* animation: `format_version` 1.8.0, `animations` map keyed `animation.<entity>.<name>`,
  loop flag sanity (`true`/`false`/`"hold_on_last_frame"`), `animation_length` vs last
  keyframe, channel names, keyframe shapes (`[x,y,z]`, molang strings, `pre`/`post`
  dicts, `lerp_mode`), sorted non-negative timestamps.
* cross-check: every animated bone must exist in the geometry (pass the geo file in the
  same invocation; otherwise the bone check is skipped with a warning).

Prints an ASCII bone tree (`glow_`-prefixed bones flagged as emissive) plus cube/keyframe
counts. Exit code 0 = no errors (warnings allowed), 1 = at least one error.

Usage (from the ProjectEclipse root):
    python3 scripts/geckolib_gen/validate_geo.py \
        src/main/resources/assets/eclipse/geo/entity/drift_lantern.geo.json \
        src/main/resources/assets/eclipse/animations/entity/drift_lantern.animation.json

Stdlib only (the painter `paint_lib.py` imports the parsing helpers from here).
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

GEO_FORMAT_VERSION = "1.12.0"
ANIM_FORMAT_VERSION = "1.8.0"
FACES = ("north", "south", "east", "west", "up", "down")
CHANNELS = ("rotation", "position", "scale")
LERP_MODES = ("linear", "catmullrom")
# Loose molang sanity: only characters that appear in Blockbench-authored expressions.
MOLANG_RE = re.compile(r"^[\w\s\.\+\-\*/%\(\),<>=!&\|\?:']+$")


# ---------------------------------------------------------------------------
# shared box-UV math (imported by paint_lib.py — keep signatures stable)
# ---------------------------------------------------------------------------

def box_uv_rects(u, v, w, h, d):
    """Face pixel rects of a Bedrock box-UV cube: `{face: (x0, y0, x1, y1)}`.

    Same strip convention as the repo's `EntitySkinArtist.java` (verified against
    `docs/uv/sunmote.md`): row 1 = top/bottom, row 2 = east, north, west, south.
    Right/bottom edges are exclusive. Fractional sizes keep exact float bounds.
    """
    return {
        "up": (u + d, v, u + d + w, v + d),
        "down": (u + d + w, v, u + d + 2 * w, v + d),
        "east": (u, v + d, u + d, v + d + h),
        "north": (u + d, v + d, u + d + w, v + d + h),
        "west": (u + d + w, v + d, u + d + w + d, v + d + h),
        "south": (u + d + w + d, v + d, u + 2 * d + 2 * w, v + d + h),
    }


def cube_face_rects(cube):
    """All face rects of a cube dict (box UV or per-face UV): `{face: rect}`.

    Per-face UVs with negative `uv_size` (Blockbench flips) are normalised to
    min/max bounds. Faces absent from a per-face map are omitted.
    """
    size = cube.get("size", [0, 0, 0])
    uv = cube.get("uv")
    if isinstance(uv, (list, tuple)):
        return box_uv_rects(uv[0], uv[1], size[0], size[1], size[2])
    rects = {}
    if isinstance(uv, dict):
        for face, spec in uv.items():
            if not isinstance(spec, dict) or "uv" not in spec:
                continue
            fu, fv = spec["uv"]
            fw, fh = spec.get("uv_size", (0, 0))
            rects[face] = (min(fu, fu + fw), min(fv, fv + fh), max(fu, fu + fw), max(fv, fv + fh))
    return rects


def load_geo(path):
    """Parses a geo file into `(identifier, tex_w, tex_h, bones)` without validating.

    `bones` is the raw bone dict list. Raises on malformed JSON / missing geometry —
    run the validator first; this helper is for the painter.
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    geometry = data["minecraft:geometry"][0]
    description = geometry.get("description", {})
    return (
        description.get("identifier", "geometry.unknown"),
        int(description.get("texture_width", 64)),
        int(description.get("texture_height", 64)),
        geometry.get("bones", []),
    )


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------

class Report:
    def __init__(self, label):
        self.label = label
        self.errors = []
        self.warnings = []
        self.infos = []

    def error(self, msg):
        self.errors.append(msg)

    def warn(self, msg):
        self.warnings.append(msg)

    def info(self, msg):
        self.infos.append(msg)

    def dump(self):
        print(f"\n=== {self.label}")
        for line in self.infos:
            print(f"    {line}")
        for line in self.warnings:
            print(f"  WARN  {line}")
        for line in self.errors:
            print(f"  ERROR {line}")
        print(f"  -> {'FAIL' if self.errors else 'PASS'}"
              f" ({len(self.errors)} error(s), {len(self.warnings)} warning(s))")


def _is_num(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_vec3(value):
    return isinstance(value, (list, tuple)) and len(value) == 3 and all(_is_num(n) for n in value)


def _check_molang(expr, where, report):
    if not expr.strip():
        report.error(f"{where}: empty molang expression")
        return
    if expr.count("(") != expr.count(")"):
        report.error(f"{where}: unbalanced parentheses in molang '{expr}'")
    if not MOLANG_RE.match(expr):
        report.warn(f"{where}: molang '{expr}' contains unusual characters")


def _check_value_component(value, where, report):
    """One axis component of a keyframe value: number or molang string."""
    if _is_num(value):
        return
    if isinstance(value, str):
        _check_molang(value, where, report)
        return
    report.error(f"{where}: expected number or molang string, got {type(value).__name__}")


# ---------------------------------------------------------------------------
# geometry validation
# ---------------------------------------------------------------------------

def validate_geo(path, report):
    """Full geometry validation. Returns the set of bone names (empty on hard failure)."""
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        report.error(f"cannot read/parse: {exc}")
        return set()

    fmt = data.get("format_version")
    if fmt is None:
        report.error("missing format_version (Blockbench writes \"1.12.0\")")
    elif fmt != GEO_FORMAT_VERSION:
        report.warn(f"format_version is '{fmt}' (expected '{GEO_FORMAT_VERSION}')")

    geometries = data.get("minecraft:geometry")
    if not isinstance(geometries, list) or not geometries:
        report.error("missing/empty 'minecraft:geometry' array")
        return set()
    if len(geometries) > 1:
        report.warn(f"{len(geometries)} geometries in one file — GeckoLib uses the first")
    geometry = geometries[0]

    description = geometry.get("description", {})
    identifier = description.get("identifier", "")
    if not identifier.startswith("geometry."):
        report.error(f"description.identifier '{identifier}' must start with 'geometry.'")
    tex_w = description.get("texture_width")
    tex_h = description.get("texture_height")
    for name, value in (("texture_width", tex_w), ("texture_height", tex_h)):
        if not isinstance(value, int) or value <= 0:
            report.error(f"description.{name} must be a positive integer (got {value!r})")
    if not isinstance(tex_w, int) or not isinstance(tex_h, int):
        return set()

    bones = geometry.get("bones", [])
    if not isinstance(bones, list) or not bones:
        report.error("no bones — GeckoLib needs at least one bone")
        return set()

    names = []
    cube_total = 0
    for i, bone in enumerate(bones):
        label = f"bone[{i}]"
        name = bone.get("name")
        if not isinstance(name, str) or not name:
            report.error(f"{label}: missing name")
            continue
        label = f"bone '{name}'"
        if name in names:
            report.error(f"{label}: duplicate bone name")
        names.append(name)
        if not _is_vec3(bone.get("pivot", [0, 0, 0])):
            report.error(f"{label}: pivot must be [x, y, z]")
        if "rotation" in bone and not _is_vec3(bone["rotation"]):
            report.error(f"{label}: rotation must be [x, y, z] degrees")
        for j, cube in enumerate(bone.get("cubes", [])):
            cube_total += 1
            _validate_cube(cube, f"{label} cube[{j}]", tex_w, tex_h, report)

    by_name = {bone.get("name"): bone for bone in bones if isinstance(bone.get("name"), str)}
    roots = 0
    for bone in bones:
        name = bone.get("name", "?")
        parent = bone.get("parent")
        if parent is None:
            roots += 1
            continue
        if parent not in by_name:
            report.error(f"bone '{name}': parent '{parent}' does not exist")
            continue
        # cycle walk (parents are already validated to exist)
        seen, cursor = {name}, parent
        while cursor is not None:
            if cursor in seen:
                report.error(f"bone '{name}': parent chain loops at '{cursor}'")
                break
            seen.add(cursor)
            cursor = by_name.get(cursor, {}).get("parent")
    if roots == 0:
        report.error("no root bone (every bone has a parent — cycle?)")

    if "head" not in by_name:
        report.info("note: no 'head' bone — auto head-tracking unavailable (fine for non-tracking mobs)")

    report.info(f"identifier {identifier}  canvas {tex_w}x{tex_h}  "
                f"{len(names)} bones  {cube_total} cubes")
    for line in _bone_tree_lines(bones, by_name):
        report.info(line)
    return set(names)


def _validate_cube(cube, label, tex_w, tex_h, report):
    origin, size = cube.get("origin"), cube.get("size")
    if not _is_vec3(origin):
        report.error(f"{label}: origin must be [x, y, z]")
    if not _is_vec3(size) or any(n < 0 for n in size):
        report.error(f"{label}: size must be [w, h, d] with w/h/d >= 0")
        return
    if "inflate" in cube and not _is_num(cube["inflate"]):
        report.error(f"{label}: inflate must be a number")
    if "rotation" in cube:
        if not _is_vec3(cube["rotation"]):
            report.error(f"{label}: rotation must be [x, y, z] degrees")
        if "pivot" in cube and not _is_vec3(cube["pivot"]):
            report.error(f"{label}: pivot must be [x, y, z]")

    uv = cube.get("uv")
    if uv is None:
        report.error(f"{label}: missing uv")
        return
    if isinstance(uv, (list, tuple)):
        if len(uv) != 2 or not all(_is_num(n) for n in uv):
            report.error(f"{label}: box uv must be [u, v]")
            return
    elif isinstance(uv, dict):
        unknown = [face for face in uv if face not in FACES]
        if unknown:
            report.error(f"{label}: unknown uv faces {unknown} (allowed: {list(FACES)})")
        for face, spec in uv.items():
            if not isinstance(spec, dict) or "uv" not in spec:
                report.error(f"{label}: per-face uv '{face}' needs an 'uv' entry")
                return
    else:
        report.error(f"{label}: uv must be [u, v] (box) or a per-face map")
        return

    for face, (x0, y0, x1, y1) in cube_face_rects(cube).items():
        if x0 < 0 or y0 < 0 or x1 > tex_w or y1 > tex_h:
            report.error(f"{label}: {face} uv rect ({x0},{y0})-({x1},{y1}) "
                         f"outside {tex_w}x{tex_h} canvas")
        if any(n != int(n) for n in (x0, y0, x1, y1)):
            report.warn(f"{label}: {face} uv rect ({x0},{y0})-({x1},{y1}) is fractional "
                        f"(painter rounds outward)")


def _bone_tree_lines(bones, by_name):
    children = {}
    for bone in bones:
        children.setdefault(bone.get("parent"), []).append(bone)

    lines = []

    def descend(bone, prefix, is_last):
        name = bone.get("name", "?")
        cubes = len(bone.get("cubes", [])) or 0
        pivot = bone.get("pivot", [0, 0, 0])
        tags = []
        if cubes:
            tags.append(f"{cubes} cube{'s' if cubes != 1 else ''}")
        if name.startswith("glow_"):
            tags.append("emissive")
        if name == "head":
            tags.append("head-tracked")
        joint = "" if prefix == "" and not is_last else ("└─ " if is_last else "├─ ")
        suffix = f"  (pivot {pivot[0]},{pivot[1]},{pivot[2]}" + (f" · {' · '.join(tags)})" if tags else ")")
        lines.append(f"{prefix}{joint}{name}{suffix}")
        kids = children.get(name, [])
        for k, kid in enumerate(kids):
            ext = "" if prefix == "" and joint == "" else ("   " if is_last else "│  ")
            descend(kid, prefix + ext, k == len(kids) - 1)

    for r, root in enumerate(children.get(None, [])):
        descend(root, "", r == len(children.get(None, [])) - 1)
    return lines


# ---------------------------------------------------------------------------
# animation validation
# ---------------------------------------------------------------------------

def validate_animation(path, known_bones, report):
    try:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        report.error(f"cannot read/parse: {exc}")
        return

    fmt = data.get("format_version")
    if fmt is None:
        report.error("missing format_version (Blockbench writes \"1.8.0\")")
    elif fmt != ANIM_FORMAT_VERSION:
        report.warn(f"format_version is '{fmt}' (expected '{ANIM_FORMAT_VERSION}')")

    animations = data.get("animations")
    if not isinstance(animations, dict) or not animations:
        report.error("missing/empty 'animations' map")
        return
    if known_bones is None:
        report.warn("no geo file passed in the same invocation — bone-name cross-check skipped")

    for anim_name, anim in animations.items():
        _validate_one_animation(anim_name, anim, known_bones, report)
    report.info(f"{len(animations)} animation(s): {', '.join(animations)}")


def _validate_one_animation(anim_name, anim, known_bones, report):
    label = f"'{anim_name}'"
    if not anim_name.startswith("animation."):
        report.warn(f"{label}: name should follow 'animation.<entity_path>.<name>'")
    if not isinstance(anim, dict):
        report.error(f"{label}: animation must be an object")
        return

    loop = anim.get("loop")
    if loop not in (None, True, False, "hold_on_last_frame"):
        report.error(f"{label}: loop must be true/false/\"hold_on_last_frame\" (got {loop!r})")
    length = anim.get("animation_length")
    if length is not None and (not _is_num(length) or length <= 0):
        report.error(f"{label}: animation_length must be a positive number (got {length!r})")

    for key in anim:
        if key not in ("loop", "animation_length", "bones", "sound_effects",
                       "particle_effects", "timeline", "override_previous_animation",
                       "start_delay", "loop_delay", "anim_time_update", "blend_weight"):
            report.warn(f"{label}: key '{key}' is not validated (passed through)")
    for key in ("sound_effects", "particle_effects", "timeline"):
        if key in anim:
            report.warn(f"{label}: '{key}' present — GeckoLib keyframe handlers must be "
                        f"wired in the controller for it to do anything")

    bones = anim.get("bones", {})
    if not isinstance(bones, dict) or not bones:
        report.warn(f"{label}: no bone channels (empty animation)")
        return

    last_time = 0.0
    frame_count = 0
    for bone_name, channels in bones.items():
        if known_bones is not None and bone_name not in known_bones:
            report.error(f"{label}: bone '{bone_name}' does not exist in the geometry")
        if not isinstance(channels, dict):
            report.error(f"{label}: bone '{bone_name}' must map channels to keyframes")
            continue
        for channel, value in channels.items():
            where = f"{label} {bone_name}.{channel}"
            if channel not in CHANNELS:
                report.warn(f"{where}: channel not in {CHANNELS} — GeckoLib ignores it")
                continue
            bone_last, frames = _validate_channel(value, where, report)
            last_time = max(last_time, bone_last)
            frame_count += frames

    if length is not None and _is_num(length) and last_time > length + 1e-6:
        report.error(f"{label}: last keyframe at {last_time}s is beyond "
                     f"animation_length {length}s")
    if length is None and last_time > 0:
        report.warn(f"{label}: no animation_length — GeckoLib derives {last_time}s "
                    f"from the last keyframe")
    report.info(f"{label}: loop={loop!r} length={length!r} "
                f"bones={len(bones)} keyframes={frame_count} last_key={last_time}s")


def _validate_channel(value, where, report):
    """Validates one channel; returns (last_keyframe_time, keyframe_count)."""
    # Static forms: single molang/number, or a [x, y, z] triple.
    if isinstance(value, (str, int, float)) and not isinstance(value, bool):
        _check_value_component(value, where, report)
        return 0.0, 1
    if isinstance(value, list):
        if len(value) != 3:
            report.error(f"{where}: static value must be [x, y, z]")
        else:
            for component in value:
                _check_value_component(component, where, report)
        return 0.0, 1
    if not isinstance(value, dict):
        report.error(f"{where}: unsupported keyframe container {type(value).__name__}")
        return 0.0, 0

    times = []
    for stamp, frame in value.items():
        try:
            t = float(stamp)
        except (TypeError, ValueError):
            report.error(f"{where}: timestamp '{stamp}' is not a number")
            continue
        if t < 0:
            report.error(f"{where}: negative timestamp {t}")
        times.append(t)
        _validate_keyframe_value(frame, f"{where}@{stamp}", report)
    if times != sorted(times):
        report.warn(f"{where}: timestamps not in ascending order (Blockbench sorts them)")
    return (max(times) if times else 0.0), len(times)


def _validate_keyframe_value(frame, where, report):
    if isinstance(frame, (str, int, float)) and not isinstance(frame, bool):
        _check_value_component(frame, where, report)
        return
    if isinstance(frame, list):
        if len(frame) != 3:
            report.error(f"{where}: keyframe array must be [x, y, z]")
            return
        for component in frame:
            _check_value_component(component, where, report)
        return
    if isinstance(frame, dict):
        if "post" not in frame and "pre" not in frame:
            report.error(f"{where}: keyframe object needs 'pre' and/or 'post'")
        for key in ("pre", "post"):
            if key in frame:
                _validate_keyframe_value(frame[key], f"{where}.{key}", report)
        if "lerp_mode" in frame and frame["lerp_mode"] not in LERP_MODES:
            report.error(f"{where}: lerp_mode '{frame['lerp_mode']}' not in {LERP_MODES}")
        for key in frame:
            if key not in ("pre", "post", "lerp_mode"):
                report.warn(f"{where}: unknown keyframe key '{key}'")
        return
    report.error(f"{where}: unsupported keyframe value {type(frame).__name__}")


# ---------------------------------------------------------------------------
# entry point
# ---------------------------------------------------------------------------

def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    geo_files = [a for a in argv[1:] if a.endswith(".geo.json")]
    anim_files = [a for a in argv[1:] if a.endswith(".animation.json")]
    unknown = [a for a in argv[1:] if a not in geo_files and a not in anim_files]
    if unknown:
        print(f"ERROR unrecognized inputs (want *.geo.json / *.animation.json): {unknown}")
        return 2

    reports = []
    known_bones = set()
    for path in geo_files:
        report = Report(f"GEO  {path}")
        known_bones |= validate_geo(path, report)
        reports.append(report)
    for path in anim_files:
        report = Report(f"ANIM {path}")
        validate_animation(path, known_bones if geo_files else None, report)
        reports.append(report)

    for report in reports:
        report.dump()
    failed = sum(1 for r in reports if r.errors)
    print(f"\n{'=' * 60}\nvalidate_geo: {len(reports) - failed}/{len(reports)} file(s) passed"
          + (f", {failed} FAILED" if failed else " — all good"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
