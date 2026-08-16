#!/usr/bin/env python3
"""Fail-closed Asset-Validator fuer die Gooby-Premium-Assets.

Prueft (Exit-Code != 0 bei jedem Fehler):
  1. JSON-Parse aller Geos, der Animationsdatei und der .bbmodel-Quellen.
  2. Geo-Bones: eindeutige Namen, existierende Parents, Pflicht-Anker.
  3. Animations-Bone-Referenzen: jede referenzierte Bone existiert im
     Adult- UND Baby-Geo (beide werden von derselben Datei getrieben);
     Keyframes, Easing-Namen und lerp_mode sind GeckoLib-4-gueltig.
  4. UV-Bounds: jede Cube-Face liegt innerhalb der Texturaufloesung.
  5. Textur-Referenzen: alle vom Renderer benutzten Entity-Sheets liegen vor
     (Mapping siehe GoobyModel.java / GoobyCoatVariant.java).
  6. PNG-Dimensionen == texture_width/height des Geos.
  7. Alpha-Coverage: jede belegte UV-Region ist auf jedem zugehoerigen
     Sheet deckend bemalt (>= 95 % Alpha), damit keine Loecher im Fell sind.
  8. .bbmodel-Konsistenz: Aufloesung, Bone-/Gruppen-Namen, Element-Refs.
  9. Explorer-Accessoire-Itemmodelle (flower_crown, adventure_bandana,
     picnic_backpack): Element-/UV-/Rotations-Grenzen, Displays
     (gui/ground/head), Tint-Policy, Textur-Dimension + Alpha-Coverage der
     Face-UV-Fenster sowie 1:1-Abgleich mit den java_block-.bbmodel-Quellen
     unter assets_src/blockbench/.

Aufruf:  python3 scripts/validate_assets.py [--root PFAD]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

from PIL import Image

ASSET_BASE = os.path.join("src", "main", "resources", "assets", "goobymod")

# Sheets pro Geo — Mapping aus GoobyModel.java + GoobyCoatVariant.java.
GEO_TEXTURES = {
    "gooby.geo.json": ["gooby.png", "gooby_cream.png", "gooby_cocoa.png",
                       "gooby_spotted.png"],
    "gooby_baby.geo.json": ["gooby_baby.png"],
}
REQUIRED_ANCHORS = {
    "gooby.geo.json": {"hat_anchor", "neck_anchor", "back_anchor", "mouth_anchor"},
    "gooby_baby.geo.json": {"hat_anchor", "mouth_anchor"},
}
BBMODEL_FOR_GEO = {
    "gooby.geo.json": "gooby.bbmodel",
    "gooby_baby.geo.json": "gooby_baby.bbmodel",
}

# Von GeckoLib 4.x registrierte Easing-Namen (EasingType, lowercase).
GECKOLIB_EASINGS = {
    "linear", "step", "catmullrom",
    "easeinsine", "easeoutsine", "easeinoutsine",
    "easeinquad", "easeoutquad", "easeinoutquad",
    "easeincubic", "easeoutcubic", "easeinoutcubic",
    "easeinquart", "easeoutquart", "easeinoutquart",
    "easeinquint", "easeoutquint", "easeinoutquint",
    "easeinexpo", "easeoutexpo", "easeinoutexpo",
    "easeincirc", "easeoutcirc", "easeinoutcirc",
    "easeinback", "easeoutback", "easeinoutback",
    "easeinelastic", "easeoutelastic", "easeinoutelastic",
    "easeinbounce", "easeoutbounce", "easeinoutbounce",
}
KEYFRAME_KEYS = {"vector", "pre", "post", "easing", "easingArgs", "lerp_mode"}
ALPHA_COVERAGE_MIN = 0.95
ALPHA_THRESHOLD = 8

# Explorer-Outfit v5.4: handgeschriebene 3D-Itemmodelle + java_block-Quellen.
ITEM_ACCESSORIES = {
    "flower_crown": {"resolution": 16, "tintable": False, "min_elements": 6},
    "adventure_bandana": {"resolution": 16, "tintable": True, "min_elements": 4},
    "picnic_backpack": {"resolution": 32, "tintable": False, "min_elements": 6},
}
REQUIRED_ITEM_DISPLAYS = {"gui", "ground", "head"}
VALID_ELEMENT_ANGLES = {-45.0, -22.5, 0.0, 22.5, 45.0}
FACE_ORDER = ("north", "east", "south", "west", "up", "down")


class ValidationError(Exception):
    """Datei ist so kaputt, dass Folge-Checks sinnlos sind."""


# ---------------------------------------------------------------------------
# Geo
# ---------------------------------------------------------------------------

def load_json(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError as error:
        raise ValidationError(f"Datei fehlt: {path}") from error
    except json.JSONDecodeError as error:
        raise ValidationError(f"JSON-Parse-Fehler in {path}: {error}") from error


def box_uv_faces(u0, v0, w, h, d):
    return {
        "up": (u0 + d, v0, u0 + d + w, v0 + d),
        "down": (u0 + d + w, v0, u0 + d + 2 * w, v0 + d),
        "east": (u0, v0 + d, u0 + d, v0 + d + h),
        "north": (u0 + d, v0 + d, u0 + d + w, v0 + d + h),
        "west": (u0 + d + w, v0 + d, u0 + d + w + d, v0 + d + h),
        "south": (u0 + 2 * d + w, v0 + d, u0 + 2 * d + 2 * w, v0 + d + h),
    }


def cube_face_rects(cube):
    """{face: (x0, y0, x1, y1)} in float-Texeln; leere Faces entfallen."""
    uv = cube.get("uv")
    w, h, d = cube["size"]
    if isinstance(uv, dict):
        rects = {}
        for face, spec in uv.items():
            u, v = spec["uv"]
            us, vs = spec["uv_size"]
            if us > 0 and vs > 0:
                rects[face] = (u, v, u + us, v + vs)
        return rects
    return {face: rect for face, rect in box_uv_faces(uv[0], uv[1], w, h, d).items()
            if rect[2] > rect[0] and rect[3] > rect[1]}


def parse_geo(path):
    document = load_json(path)
    geometries = document.get("minecraft:geometry")
    if not geometries:
        raise ValidationError(f"{path}: minecraft:geometry fehlt oder leer")
    geometry = geometries[0]
    description = geometry.get("description", {})
    if "texture_width" not in description or "texture_height" not in description:
        raise ValidationError(f"{path}: texture_width/texture_height fehlen")
    return geometry


def validate_geo(path, filename):
    errors = []
    geometry = parse_geo(path)
    description = geometry["description"]
    width, height = description["texture_width"], description["texture_height"]
    bones = geometry.get("bones", [])
    names = [bone.get("name") for bone in bones]

    for name in names:
        if not name:
            errors.append(f"{filename}: Bone ohne Namen")
    duplicates = {name for name in names if names.count(name) > 1}
    if duplicates:
        errors.append(f"{filename}: doppelte Bone-Namen: {sorted(duplicates)}")

    name_set = set(names)
    for bone in bones:
        parent = bone.get("parent")
        if parent is not None and parent not in name_set:
            errors.append(f"{filename}: Bone '{bone.get('name')}' referenziert "
                          f"unbekannten Parent '{parent}'")

    missing_anchors = REQUIRED_ANCHORS.get(filename, set()) - name_set
    if missing_anchors:
        errors.append(f"{filename}: Pflicht-Anker fehlen: {sorted(missing_anchors)}")

    for bone in bones:
        for index, cube in enumerate(bone.get("cubes", [])):
            tag = f"{filename}: {bone.get('name')}[{index}]"
            if "size" not in cube or "origin" not in cube or "uv" not in cube:
                errors.append(f"{tag}: origin/size/uv unvollstaendig")
                continue
            for face, (x0, y0, x1, y1) in cube_face_rects(cube).items():
                if x0 < 0 or y0 < 0 or x1 > width or y1 > height:
                    errors.append(f"{tag}.{face}: UV ({x0},{y0})-({x1},{y1}) "
                                  f"verlaesst die {width}x{height}-Textur")
    return errors, geometry


# ---------------------------------------------------------------------------
# Animationen
# ---------------------------------------------------------------------------

def validate_keyframe_value(tag, entry, errors):
    if isinstance(entry, list):
        if len(entry) != 3 or not all(isinstance(v, (int, float)) for v in entry):
            errors.append(f"{tag}: Keyframe-Vektor muss 3 Zahlen haben: {entry}")
        return
    if isinstance(entry, dict):
        unknown = set(entry) - KEYFRAME_KEYS
        if unknown:
            errors.append(f"{tag}: unbekannte Keyframe-Felder {sorted(unknown)}")
        vector = entry.get("vector", entry.get("post", entry.get("pre")))
        if vector is None:
            errors.append(f"{tag}: Keyframe-Objekt ohne vector/pre/post")
        else:
            validate_keyframe_value(tag, vector, errors)
        easing = entry.get("easing")
        if easing is not None and str(easing).lower() not in GECKOLIB_EASINGS:
            errors.append(f"{tag}: unbekanntes Easing '{easing}'")
        lerp = entry.get("lerp_mode")
        if lerp is not None and lerp != "catmullrom":
            errors.append(f"{tag}: unbekannter lerp_mode '{lerp}'")
        return
    errors.append(f"{tag}: Keyframe hat unerwarteten Typ {type(entry).__name__}")


def validate_animations(path, bone_sets):
    """bone_sets: {geo-dateiname: set(bones)} — Refs muessen ueberall existieren."""
    errors = []
    document = load_json(path)
    animations = document.get("animations")
    if not isinstance(animations, dict) or not animations:
        return [f"{os.path.basename(path)}: 'animations' fehlt oder ist leer"]

    for clip_name, clip in animations.items():
        length = clip.get("animation_length", 0)
        if not isinstance(length, (int, float)) or length <= 0:
            errors.append(f"{clip_name}: animation_length fehlt oder <= 0")
            length = math.inf
        loop = clip.get("loop", False)
        if not isinstance(loop, bool):
            errors.append(f"{clip_name}: loop muss bool sein")

        for bone_name, channels in clip.get("bones", {}).items():
            for geo_name, bones in bone_sets.items():
                if bone_name not in bones:
                    errors.append(f"{clip_name}: Bone '{bone_name}' existiert "
                                  f"nicht in {geo_name}")
            for channel, frames in channels.items():
                if channel not in ("rotation", "position", "scale"):
                    errors.append(f"{clip_name}/{bone_name}: unbekannter "
                                  f"Channel '{channel}'")
                    continue
                if not isinstance(frames, dict):
                    validate_keyframe_value(
                        f"{clip_name}/{bone_name}/{channel}", frames, errors)
                    continue
                for time_key, entry in frames.items():
                    tag = f"{clip_name}/{bone_name}/{channel}@{time_key}"
                    try:
                        time_value = float(time_key)
                    except ValueError:
                        errors.append(f"{tag}: Zeitstempel ist keine Zahl")
                        continue
                    if time_value < 0 or time_value > length + 1e-6:
                        errors.append(f"{tag}: Zeit ausserhalb 0..{length}")
                    validate_keyframe_value(tag, entry, errors)

        for time_key in clip.get("sound_effects", {}):
            try:
                float(time_key)
            except ValueError:
                errors.append(f"{clip_name}: sound_effects-Zeit '{time_key}' "
                              f"ist keine Zahl")
    return errors


# ---------------------------------------------------------------------------
# Texturen
# ---------------------------------------------------------------------------

def inward(rect):
    x0, y0, x1, y1 = rect
    return (math.ceil(x0), math.ceil(y0), math.floor(x1), math.floor(y1))


def validate_texture_for_geo(texture_path, geometry, filename, texture_name):
    errors = []
    if not os.path.isfile(texture_path):
        return [f"{filename}: referenzierte Textur fehlt: "
                f"textures/entity/{texture_name}"]
    description = geometry["description"]
    expected = (description["texture_width"], description["texture_height"])
    with Image.open(texture_path) as handle:
        image = handle.convert("RGBA")
    if image.size != expected:
        errors.append(f"{texture_name}: Groesse {image.size} != erwartet {expected}")
        return errors

    pixels = image.load()
    for bone in geometry.get("bones", []):
        for index, cube in enumerate(bone.get("cubes", [])):
            for face, rect in cube_face_rects(cube).items():
                x0, y0, x1, y1 = inward(rect)
                # Ausserhalb liegende UVs meldet bereits der Geo-Check.
                x0, y0 = max(0, x0), max(0, y0)
                x1, y1 = min(image.width, x1), min(image.height, y1)
                if x1 <= x0 or y1 <= y0:
                    continue
                total = (x1 - x0) * (y1 - y0)
                opaque = sum(1 for x in range(x0, x1) for y in range(y0, y1)
                             if pixels[x, y][3] >= ALPHA_THRESHOLD)
                if opaque / total < ALPHA_COVERAGE_MIN:
                    errors.append(
                        f"{texture_name}: UV-Region {bone['name']}[{index}].{face} "
                        f"({x0},{y0})-({x1},{y1}) nur {opaque}/{total} px deckend")
    return errors


# ---------------------------------------------------------------------------
# Blockbench-Quellen
# ---------------------------------------------------------------------------

def collect_outliner(nodes, groups, element_refs):
    for node in nodes:
        if isinstance(node, dict):
            groups.append(node)
            collect_outliner(node.get("children", []), groups, element_refs)
        else:
            element_refs.append(node)


def validate_bbmodel(path, geometry, filename):
    errors = []
    project = load_json(path)
    for key in ("meta", "elements", "outliner", "resolution"):
        if key not in project:
            errors.append(f"{filename}: Pflichtfeld '{key}' fehlt")
    if errors:
        return errors
    meta = project["meta"]
    if "format_version" not in meta or "model_format" not in meta:
        errors.append(f"{filename}: meta.format_version/model_format fehlen")

    description = geometry["description"]
    resolution = project["resolution"]
    if (resolution.get("width"), resolution.get("height")) != (
            description["texture_width"], description["texture_height"]):
        errors.append(f"{filename}: resolution {resolution} passt nicht zur "
                      f"Geo-Textur {description['texture_width']}x"
                      f"{description['texture_height']}")

    groups, element_refs = [], []
    collect_outliner(project["outliner"], groups, element_refs)
    group_names = {group.get("name") for group in groups}
    bone_names = {bone["name"] for bone in geometry.get("bones", [])}
    if group_names != bone_names:
        missing = bone_names - group_names
        extra = group_names - bone_names
        if missing:
            errors.append(f"{filename}: Outliner-Gruppen fehlen: {sorted(missing)}")
        if extra:
            errors.append(f"{filename}: Outliner-Gruppen ohne Geo-Bone: "
                          f"{sorted(extra)}")

    element_uuids = [element.get("uuid") for element in project["elements"]]
    cube_count = sum(len(bone.get("cubes", []))
                     for bone in geometry.get("bones", []))
    if len(element_uuids) != cube_count:
        errors.append(f"{filename}: {len(element_uuids)} Elemente, aber "
                      f"{cube_count} Cubes im Geo")
    for ref in element_refs:
        if ref not in element_uuids:
            errors.append(f"{filename}: Outliner referenziert unbekanntes "
                          f"Element {ref}")
    unreferenced = set(element_uuids) - set(element_refs)
    if unreferenced:
        errors.append(f"{filename}: Elemente haengen nicht im Outliner: "
                      f"{len(unreferenced)} Stueck")

    for animation in project.get("animations", []):
        for animator in animation.get("animators", {}).values():
            if animator.get("type") == "bone" \
                    and animator.get("name") not in bone_names:
                errors.append(f"{filename}: Animation '{animation.get('name')}' "
                              f"animiert unbekannte Bone "
                              f"'{animator.get('name')}'")
    return errors


# ---------------------------------------------------------------------------
# Explorer-Accessoire-Itemmodelle (v5.4)
# ---------------------------------------------------------------------------

def validate_item_model(document, name, config):
    """Struktur-Checks des handgeschriebenen Itemmodells; Rueckgabe Fehlerliste."""
    errors = []
    elements = document.get("elements")
    if not isinstance(elements, list) or len(elements) < config["min_elements"]:
        return [f"{name}.json: erwartet >= {config['min_elements']} Elemente, "
                f"gefunden {0 if not isinstance(elements, list) else len(elements)}"]
    textures = document.get("textures", {})
    if "particle" not in textures:
        errors.append(f"{name}.json: particle-Textur fehlt")
    for index, element in enumerate(elements):
        tag = f"{name}.json[{index}]"
        source = element.get("from")
        target = element.get("to")
        if (not isinstance(source, list) or not isinstance(target, list)
                or len(source) != 3 or len(target) != 3):
            errors.append(f"{tag}: from/to unvollstaendig")
            continue
        for axis in range(3):
            if not (-16 <= source[axis] <= 32 and -16 <= target[axis] <= 32):
                errors.append(f"{tag}: Koordinate ausserhalb [-16,32]")
                break
            if source[axis] > target[axis]:
                errors.append(f"{tag}: from > to auf Achse {axis}")
                break
        rotation = element.get("rotation")
        if rotation is not None:
            if rotation.get("axis") not in ("x", "y", "z"):
                errors.append(f"{tag}: Rotationsachse '{rotation.get('axis')}' ungueltig")
            if float(rotation.get("angle", 0)) not in VALID_ELEMENT_ANGLES:
                errors.append(f"{tag}: Rotationswinkel {rotation.get('angle')} "
                              f"nicht in 22.5er-Schritten")
            origin = rotation.get("origin")
            if not isinstance(origin, list) or len(origin) != 3:
                errors.append(f"{tag}: Rotations-Origin fehlt")
        faces = element.get("faces", {})
        if not faces:
            errors.append(f"{tag}: keine Faces definiert")
        for face, spec in faces.items():
            face_tag = f"{tag}.{face}"
            if face not in FACE_ORDER:
                errors.append(f"{face_tag}: unbekannte Face-Richtung")
                continue
            uv = spec.get("uv")
            if not isinstance(uv, list) or len(uv) != 4:
                errors.append(f"{face_tag}: uv fehlt (Pflicht fuer .bbmodel-Abgleich)")
                continue
            if not all(0 <= value <= 16 for value in uv):
                errors.append(f"{face_tag}: uv {uv} verlaesst 0..16")
            if uv[0] >= uv[2] or uv[1] >= uv[3]:
                errors.append(f"{face_tag}: uv {uv} ist leer oder gespiegelt")
            texture_ref = spec.get("texture", "")
            if not texture_ref.startswith("#") or texture_ref[1:] not in textures:
                errors.append(f"{face_tag}: Texturref '{texture_ref}' unaufgeloest")
            has_tint = "tintindex" in spec
            if config["tintable"] and (not has_tint or spec["tintindex"] != 0):
                errors.append(f"{face_tag}: faerbbares Accessoire braucht tintindex 0")
            if not config["tintable"] and has_tint:
                errors.append(f"{face_tag}: tintindex ohne registrierten Farb-Handler")
    display = document.get("display", {})
    missing = REQUIRED_ITEM_DISPLAYS - set(display)
    if missing:
        errors.append(f"{name}.json: Display-Sektionen fehlen: {sorted(missing)}")
    return errors


def validate_item_texture(document, texture_path, name, config):
    """Dimension + Alpha-Coverage aller referenzierten Face-UV-Fenster."""
    if not os.path.isfile(texture_path):
        return [f"{name}: Textur fehlt: textures/item/{name}.png"]
    errors = []
    resolution = config["resolution"]
    with Image.open(texture_path) as handle:
        image = handle.convert("RGBA")
    if image.size != (resolution, resolution):
        return [f"{name}.png: Groesse {image.size} != erwartet "
                f"({resolution}, {resolution})"]
    pixels = image.load()
    scale = resolution / 16.0
    for index, element in enumerate(document.get("elements", [])):
        for face, spec in element.get("faces", {}).items():
            uv = spec.get("uv")
            if not isinstance(uv, list) or len(uv) != 4:
                continue
            x0, y0, x1, y1 = inward((uv[0] * scale, uv[1] * scale,
                                     uv[2] * scale, uv[3] * scale))
            x0, y0 = max(0, x0), max(0, y0)
            x1, y1 = min(image.width, x1), min(image.height, y1)
            if x1 <= x0 or y1 <= y0:
                continue
            total = (x1 - x0) * (y1 - y0)
            opaque = sum(1 for x in range(x0, x1) for y in range(y0, y1)
                         if pixels[x, y][3] >= ALPHA_THRESHOLD)
            if opaque / total < ALPHA_COVERAGE_MIN:
                errors.append(f"{name}.png: UV-Fenster [{index}].{face} "
                              f"({x0},{y0})-({x1},{y1}) nur {opaque}/{total} px deckend")
    return errors


def validate_item_bbmodel(document, bbmodel_path, name, config):
    """1:1-Abgleich Itemmodell <-> java_block-Blockbench-Quelle."""
    errors = []
    project = load_json(bbmodel_path)
    filename = f"{name}.bbmodel"
    meta = project.get("meta", {})
    if meta.get("model_format") != "java_block":
        errors.append(f"{filename}: model_format '{meta.get('model_format')}' "
                      f"!= 'java_block'")
    resolution = project.get("resolution", {})
    expected = config["resolution"]
    if (resolution.get("width"), resolution.get("height")) != (expected, expected):
        errors.append(f"{filename}: resolution {resolution} != {expected}x{expected}")
    model_elements = document.get("elements", [])
    project_elements = project.get("elements", [])
    if len(model_elements) != len(project_elements):
        return errors + [f"{filename}: {len(project_elements)} Elemente, aber "
                         f"{len(model_elements)} im Itemmodell"]
    scale = expected / 16.0
    for index, (model_element, project_element) in enumerate(
            zip(model_elements, project_elements)):
        tag = f"{filename}[{index}]"
        for key in ("from", "to"):
            expected_vec = [float(v) for v in model_element[key]]
            actual_vec = [float(v) for v in project_element.get(key, [])]
            if len(actual_vec) != 3 or any(
                    abs(a - b) > 1e-6 for a, b in zip(expected_vec, actual_vec)):
                errors.append(f"{tag}: {key} {actual_vec} != Itemmodell {expected_vec}")
        rotation = model_element.get("rotation")
        project_rotation = project_element.get("rotation", [0, 0, 0])
        expected_rotation = [0.0, 0.0, 0.0]
        if rotation is not None:
            expected_rotation["xyz".index(rotation["axis"])] = float(rotation["angle"])
        if any(abs(float(a) - b) > 1e-6
               for a, b in zip(project_rotation, expected_rotation)):
            errors.append(f"{tag}: rotation {project_rotation} != {expected_rotation}")
        project_faces = project_element.get("faces", {})
        for face, spec in model_element.get("faces", {}).items():
            face_tag = f"{tag}.{face}"
            project_face = project_faces.get(face)
            if project_face is None:
                errors.append(f"{face_tag}: fehlt in der Blockbench-Quelle")
                continue
            expected_uv = [float(v) * scale for v in spec["uv"]]
            actual_uv = [float(v) for v in project_face.get("uv", [])]
            if len(actual_uv) != 4 or any(
                    abs(a - b) > 1e-6 for a, b in zip(expected_uv, actual_uv)):
                errors.append(f"{face_tag}: uv {actual_uv} != skaliert {expected_uv}")
            expected_tint = spec.get("tintindex", -1)
            if project_face.get("tint", -1) != expected_tint:
                errors.append(f"{face_tag}: tint {project_face.get('tint', -1)} "
                              f"!= {expected_tint}")
    element_uuids = [element.get("uuid") for element in project_elements]
    groups, element_refs = [], []
    collect_outliner(project.get("outliner", []), groups, element_refs)
    if sorted(filter(None, element_refs)) != sorted(filter(None, element_uuids)):
        errors.append(f"{filename}: Outliner-Referenzen decken die Elemente "
                      f"nicht exakt ab")
    display = project.get("display", {})
    if set(display) != set(document.get("display", {})):
        errors.append(f"{filename}: Display-Sektionen {sorted(display)} != "
                      f"Itemmodell {sorted(document.get('display', {}))}")
    return errors


# ---------------------------------------------------------------------------
# Orchestrierung
# ---------------------------------------------------------------------------

def run(root):
    """Fuehrt alle Checks aus; Rueckgabe (fehlerliste, ok-liste)."""
    errors, passed = [], []
    geo_dir = os.path.join(root, ASSET_BASE, "geo")
    texture_dir = os.path.join(root, ASSET_BASE, "textures", "entity")
    animation_path = os.path.join(root, ASSET_BASE, "animations",
                                  "gooby.animation.json")
    bbmodel_dir = os.path.join(root, "assets_src", "blockbench")

    geometries = {}
    for filename in GEO_TEXTURES:
        path = os.path.join(geo_dir, filename)
        try:
            geo_errors, geometry = validate_geo(path, filename)
        except ValidationError as error:
            errors.append(str(error))
            continue
        if geo_errors:
            errors.extend(geo_errors)
        else:
            passed.append(f"Geo ok: {filename}")
        geometries[filename] = geometry

    if len(geometries) == len(GEO_TEXTURES):
        bone_sets = {filename: {bone["name"] for bone in geometry["bones"]}
                     for filename, geometry in geometries.items()}
        try:
            animation_errors = validate_animations(animation_path, bone_sets)
        except ValidationError as error:
            animation_errors = [str(error)]
        if animation_errors:
            errors.extend(animation_errors)
        else:
            passed.append("Animationen ok: gooby.animation.json "
                          "(Bones, Keyframes, Easings)")

    for filename, geometry in geometries.items():
        for texture_name in GEO_TEXTURES[filename]:
            texture_errors = validate_texture_for_geo(
                os.path.join(texture_dir, texture_name), geometry,
                filename, texture_name)
            if texture_errors:
                errors.extend(texture_errors)
            else:
                passed.append(f"Textur ok: {texture_name} "
                              f"(Dimension + Alpha-Coverage fuer {filename})")

    for filename, geometry in geometries.items():
        bbmodel_name = BBMODEL_FOR_GEO[filename]
        bbmodel_path = os.path.join(bbmodel_dir, bbmodel_name)
        try:
            bbmodel_errors = validate_bbmodel(bbmodel_path, geometry, bbmodel_name)
        except ValidationError as error:
            bbmodel_errors = [str(error)]
        if bbmodel_errors:
            errors.extend(bbmodel_errors)
        else:
            passed.append(f"Blockbench-Quelle ok: {bbmodel_name}")

    item_model_dir = os.path.join(root, ASSET_BASE, "models", "item")
    item_texture_dir = os.path.join(root, ASSET_BASE, "textures", "item")
    for name, config in ITEM_ACCESSORIES.items():
        try:
            document = load_json(os.path.join(item_model_dir, f"{name}.json"))
        except ValidationError as error:
            errors.append(str(error))
            continue
        model_errors = validate_item_model(document, name, config)
        texture_errors = validate_item_texture(
            document, os.path.join(item_texture_dir, f"{name}.png"), name, config)
        try:
            bbmodel_errors = validate_item_bbmodel(
                document, os.path.join(bbmodel_dir, f"{name}.bbmodel"), name, config)
        except ValidationError as error:
            bbmodel_errors = [str(error)]
        if model_errors or texture_errors or bbmodel_errors:
            errors.extend(model_errors + texture_errors + bbmodel_errors)
        else:
            passed.append(f"Explorer-Accessoire ok: {name} "
                          f"(Itemmodell + Textur + Blockbench-Quelle)")

    return errors, passed


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=os.path.join(
        os.path.dirname(os.path.abspath(__file__)), ".."),
        help="Repo-Wurzel (Default: eine Ebene ueber scripts/)")
    args = parser.parse_args(argv)

    errors, passed = run(os.path.abspath(args.root))
    for line in passed:
        print(f"[OK]   {line}")
    for line in errors:
        print(f"[FAIL] {line}")
    if errors:
        print(f"\nAsset-Validierung FEHLGESCHLAGEN: {len(errors)} Fehler.")
        return 1
    print(f"\nAsset-Validierung bestanden ({len(passed)} Checks).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
