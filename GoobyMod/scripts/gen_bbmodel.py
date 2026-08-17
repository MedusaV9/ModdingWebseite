#!/usr/bin/env python3
"""Erzeugt Blockbench-Quellprojekte (.bbmodel) aus den Runtime-Assets.

Die .bbmodel-Dateien unter assets_src/blockbench/ werden deterministisch
aus geo/gooby.geo.json, geo/gooby_baby.geo.json und
animations/gooby.animation.json abgeleitet — Bone-Namen, Pivots, UVs und
Keyframes bleiben damit garantiert synchron zu den Runtime-Assets.

Koordinaten-Konvention (Bedrock -> Blockbench):
    cube:  from = [-(ox+sx), oy, oz], to = [-ox, oy+sy, oz+sz]
    bone:  origin = [-px, py, pz],   rotation = [-rx, -ry, rz]
    animation: rotation unveraendert, position x negiert

Zusaetzlich (Explorer-Outfit v5.4): Java-Block/Item-Projekte fuer die
handgeschriebenen 3D-Accessoire-Itemmodelle (flower_crown,
adventure_bandana, picnic_backpack). Quelle der Wahrheit sind die
models/item/*.json — Elemente, Rotationen, Face-UVs (skaliert auf die
Texturaufloesung), Tints und Display-Transforms werden 1:1 uebernommen,
validate_assets.py prueft die Konsistenz fail-closed.

Aufruf:  python3 scripts/gen_bbmodel.py
"""
from __future__ import annotations

import base64
import json
import os
import uuid

ROOT = os.path.join(os.path.dirname(__file__), "..")
ASSETS = os.path.join(ROOT, "src", "main", "resources", "assets", "goobymod")
OUT_DIR = os.path.join(ROOT, "assets_src", "blockbench")

NAMESPACE = uuid.UUID("8b1084f2-9f38-4a6c-9d3e-6c1a54a1b0ab")


def stable_uuid(*parts):
    return str(uuid.uuid5(NAMESPACE, "/".join(str(p) for p in parts)))


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def mirror_pivot(pivot):
    return [-pivot[0], pivot[1], pivot[2]]


def mirror_rotation(rotation):
    return [-rotation[0], -rotation[1], rotation[2]]


def cube_element(model, bone, cube, index):
    origin = cube["origin"]
    size = cube["size"]
    from_pt = [-(origin[0] + size[0]), origin[1], origin[2]]
    to_pt = [-origin[0], origin[1] + size[1], origin[2] + size[2]]
    element = {
        "name": bone["name"] if index == 0 else f"{bone['name']}_{index}",
        "box_uv": not isinstance(cube.get("uv"), dict),
        "rescale": False,
        "locked": False,
        "render_order": "default",
        "allow_mirror_modeling": True,
        "from": from_pt,
        "to": to_pt,
        "autouv": 0,
        "color": index % 8,
        "inflate": cube.get("inflate", 0),
        "origin": mirror_pivot(bone.get("pivot", [0, 0, 0])),
        "type": "cube",
        "uuid": stable_uuid(model, bone["name"], "cube", index),
    }
    uv = cube.get("uv")
    if isinstance(uv, dict):
        faces = {}
        for face in ("north", "east", "south", "west", "up", "down"):
            spec = uv.get(face)
            if spec is None:
                faces[face] = {"uv": [0, 0, 0, 0], "texture": None}
            else:
                u, v = spec["uv"]
                us, vs = spec["uv_size"]
                faces[face] = {"uv": [u, v, u + us, v + vs], "texture": 0}
        element["faces"] = faces
    else:
        element["uv_offset"] = list(uv)
    return element


def build_outliner(model, bones_by_parent, bone, elements_of):
    group = {
        "name": bone["name"],
        "origin": mirror_pivot(bone.get("pivot", [0, 0, 0])),
        "rotation": mirror_rotation(bone.get("rotation", [0, 0, 0])),
        "bedrock_binding": "",
        "color": 0,
        "uuid": stable_uuid(model, "group", bone["name"]),
        "export": True,
        "mirror_uv": False,
        "isOpen": True,
        "locked": False,
        "visibility": True,
        "autouv": 0,
        "children": [],
    }
    group["children"].extend(elements_of.get(bone["name"], []))
    for child in bones_by_parent.get(bone["name"], []):
        group["children"].append(
            build_outliner(model, bones_by_parent, child, elements_of))
    return group


def texture_entry(model, texture_file):
    path = os.path.join(ASSETS, "textures", "entity", texture_file)
    with open(path, "rb") as handle:
        payload = base64.b64encode(handle.read()).decode("ascii")
    return {
        "path": f"textures/entity/{texture_file}",
        "name": texture_file,
        "folder": "entity",
        "namespace": "goobymod",
        "id": "0",
        "group": "",
        "width": 64,
        "height": 64,
        "uv_width": 64,
        "uv_height": 64,
        "particle": False,
        "use_as_default": False,
        "layers_enabled": False,
        "sync_to_project": "",
        "render_mode": "default",
        "render_sides": "auto",
        "frame_time": 1,
        "frame_order_type": "loop",
        "frame_order": "",
        "frame_interpolate": False,
        "visible": True,
        "internal": True,
        "saved": True,
        "uuid": stable_uuid(model, "texture", texture_file),
        "relative_path": f"../../src/main/resources/assets/goobymod/textures/entity/{texture_file}",
        "source": f"data:image/png;base64,{payload}",
    }


def keyframe_points(entry):
    """Normalisiert einen GeckoLib-Keyframe zu (vector, interpolation, easing)."""
    if isinstance(entry, list):
        return entry, "linear", None
    vector = entry.get("vector", entry.get("post", entry.get("pre")))
    if entry.get("lerp_mode") == "catmullrom":
        return vector, "catmullrom", None
    easing = entry.get("easing")
    if easing and easing != "linear":
        return vector, "linear", easing
    return vector, "linear", None


def animation_entry(model, clip_name, clip, group_uuid_of):
    animators = {}
    for bone_name, channels in clip.get("bones", {}).items():
        group_uuid = group_uuid_of[bone_name]
        keyframes = []
        for channel, frames in channels.items():
            if not isinstance(frames, dict):
                frames = {"0.0": frames}
            for time_key, entry in sorted(frames.items(), key=lambda kv: float(kv[0])):
                vector, interpolation, easing = keyframe_points(entry)
                x, y, z = vector
                if channel == "position":
                    x = -x
                keyframe = {
                    "channel": channel,
                    "data_points": [{"x": x, "y": y, "z": z}],
                    "uuid": stable_uuid(model, clip_name, bone_name, channel, time_key),
                    "time": float(time_key),
                    "color": -1,
                    "uniform": False,
                    "interpolation": interpolation,
                    "bezier_linked": True,
                    "bezier_left_time": [-0.1, -0.1, -0.1],
                    "bezier_left_value": [0, 0, 0],
                    "bezier_right_time": [0.1, 0.1, 0.1],
                    "bezier_right_value": [0, 0, 0],
                }
                if easing:
                    keyframe["easing"] = easing
                keyframes.append(keyframe)
        animators[group_uuid] = {
            "name": bone_name,
            "type": "bone",
            "rotation_global": False,
            "keyframes": keyframes,
        }
    if "sound_effects" in clip:
        effect_frames = []
        for time_key, spec in sorted(clip["sound_effects"].items(),
                                     key=lambda kv: float(kv[0])):
            effect_frames.append({
                "channel": "sound",
                "data_points": [{"effect": spec.get("effect", ""), "file": ""}],
                "uuid": stable_uuid(model, clip_name, "sound", time_key),
                "time": float(time_key),
                "color": -1,
                "interpolation": "linear",
            })
        animators["effects"] = {"name": "Effects", "type": "effect",
                                "keyframes": effect_frames}
    return {
        "uuid": stable_uuid(model, "animation", clip_name),
        "name": clip_name,
        "loop": "loop" if clip.get("loop") else "once",
        "override": False,
        "length": clip.get("animation_length", 0),
        "snapping": 20,
        "selected": False,
        "anim_time_update": "",
        "blend_weight": "",
        "start_delay": "",
        "loop_delay": "",
        "animators": animators,
    }


def build_project(model, geo_path, texture_file, animation_path=None):
    geometry = load(geo_path)["minecraft:geometry"][0]
    description = geometry["description"]
    bones = geometry["bones"]

    elements = []
    elements_of = {}
    for bone in bones:
        for index, cube in enumerate(bone.get("cubes", [])):
            element = cube_element(model, bone, cube, index)
            elements.append(element)
            elements_of.setdefault(bone["name"], []).append(element["uuid"])

    bones_by_parent = {}
    roots = []
    for bone in bones:
        parent = bone.get("parent")
        if parent is None:
            roots.append(bone)
        else:
            bones_by_parent.setdefault(parent, []).append(bone)
    outliner = [build_outliner(model, bones_by_parent, bone, elements_of)
                for bone in roots]

    project = {
        "meta": {
            "format_version": "4.10",
            "model_format": "bedrock",
            "box_uv": True,
        },
        "name": model,
        "model_identifier": description["identifier"].removeprefix("geometry."),
        "geometry_name": description["identifier"].removeprefix("geometry."),
        "visible_box": [
            description.get("visible_bounds_width", 2),
            description.get("visible_bounds_height", 2),
            description.get("visible_bounds_offset", [0, 0, 0])[1],
        ],
        "variable_placeholders": "",
        "variable_placeholder_buttons": [],
        "unhandled_root_fields": {},
        "resolution": {
            "width": description["texture_width"],
            "height": description["texture_height"],
        },
        "elements": elements,
        "outliner": outliner,
        "textures": [texture_entry(model, texture_file)],
    }

    if animation_path is not None:
        group_uuid_of = {bone["name"]: stable_uuid(model, "group", bone["name"])
                         for bone in bones}
        clips = load(animation_path)["animations"]
        project["animations"] = [
            animation_entry(model, clip_name, clip, group_uuid_of)
            for clip_name, clip in clips.items()
        ]
    return project


# ---------------------------------------------------------------------------
# Explorer-Outfit: Java-Block/Item-Projekte aus models/item/*.json
# ---------------------------------------------------------------------------

ITEM_ACCESSORY_JOBS = [
    ("flower_crown", 16),
    ("adventure_bandana", 16),
    ("picnic_backpack", 32),
]

FACE_ORDER = ("north", "east", "south", "west", "up", "down")


def item_texture_entry(model, texture_file, size):
    path = os.path.join(ASSETS, "textures", "item", texture_file)
    with open(path, "rb") as handle:
        payload = base64.b64encode(handle.read()).decode("ascii")
    return {
        "path": f"textures/item/{texture_file}",
        "name": texture_file,
        "folder": "item",
        "namespace": "goobymod",
        "id": "0",
        "group": "",
        "width": size,
        "height": size,
        "uv_width": size,
        "uv_height": size,
        "particle": True,
        "use_as_default": False,
        "layers_enabled": False,
        "sync_to_project": "",
        "render_mode": "default",
        "render_sides": "auto",
        "frame_time": 1,
        "frame_order_type": "loop",
        "frame_order": "",
        "frame_interpolate": False,
        "visible": True,
        "internal": True,
        "saved": True,
        "uuid": stable_uuid(model, "texture", texture_file),
        "relative_path": f"../../src/main/resources/assets/goobymod/textures/item/{texture_file}",
        "source": f"data:image/png;base64,{payload}",
    }


def item_element(model, element, index, scale):
    entry = {
        "name": element.get("name", f"cube_{index}"),
        "box_uv": False,
        "rescale": False,
        "locked": False,
        "render_order": "default",
        "allow_mirror_modeling": True,
        "from": list(element["from"]),
        "to": list(element["to"]),
        "autouv": 0,
        "color": index % 8,
        "origin": list(element.get("rotation", {}).get("origin", [8, 8, 8])),
        "type": "cube",
        "uuid": stable_uuid(model, "element", index),
    }
    rotation = element.get("rotation")
    if rotation:
        vector = [0.0, 0.0, 0.0]
        vector["xyz".index(rotation["axis"])] = rotation["angle"]
        entry["rotation"] = vector
    faces = {}
    for face in FACE_ORDER:
        spec = element.get("faces", {}).get(face)
        if spec is None:
            faces[face] = {"uv": [0, 0, 0, 0], "texture": None}
            continue
        entry_face = {"uv": [value * scale for value in spec["uv"]], "texture": 0}
        if "tintindex" in spec:
            entry_face["tint"] = spec["tintindex"]
        faces[face] = entry_face
    entry["faces"] = faces
    return entry


def build_item_project(model, resolution):
    document = load(os.path.join(ASSETS, "models", "item", f"{model}.json"))
    scale = resolution / 16.0
    elements = [item_element(model, element, index, scale)
                for index, element in enumerate(document["elements"])]
    group = {
        "name": model,
        "origin": [8, 8, 8],
        "rotation": [0, 0, 0],
        "bedrock_binding": "",
        "color": 0,
        "uuid": stable_uuid(model, "group", model),
        "export": True,
        "mirror_uv": False,
        "isOpen": True,
        "locked": False,
        "visibility": True,
        "autouv": 0,
        "children": [element["uuid"] for element in elements],
    }
    return {
        "meta": {
            "format_version": "4.10",
            "model_format": "java_block",
            "box_uv": False,
        },
        "name": model,
        "parent": document.get("parent", ""),
        "ambientocclusion": True,
        "front_gui_light": False,
        "visible_box": [1, 1, 0],
        "variable_placeholders": "",
        "variable_placeholder_buttons": [],
        "unhandled_root_fields": {},
        "resolution": {"width": resolution, "height": resolution},
        "elements": elements,
        "outliner": [group],
        "textures": [item_texture_entry(model, f"{model}.png", resolution)],
        "display": document.get("display", {}),
    }


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    jobs = [
        ("gooby", "geo/gooby.geo.json", "gooby.png", "animations/gooby.animation.json"),
        ("gooby_baby", "geo/gooby_baby.geo.json", "gooby_baby.png", None),
    ]
    for model, geo_rel, texture_file, anim_rel in jobs:
        project = build_project(
            model,
            os.path.join(ASSETS, geo_rel),
            texture_file,
            os.path.join(ASSETS, anim_rel) if anim_rel else None,
        )
        out_path = os.path.join(OUT_DIR, f"{model}.bbmodel")
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(project, handle, indent=1)
            handle.write("\n")
        print(f"geschrieben: assets_src/blockbench/{model}.bbmodel "
              f"({len(project['elements'])} Cubes, "
              f"{len(project.get('animations', []))} Clips)")

    for model, resolution in ITEM_ACCESSORY_JOBS:
        project = build_item_project(model, resolution)
        out_path = os.path.join(OUT_DIR, f"{model}.bbmodel")
        with open(out_path, "w", encoding="utf-8") as handle:
            json.dump(project, handle, indent=1)
            handle.write("\n")
        print(f"geschrieben: assets_src/blockbench/{model}.bbmodel "
              f"({len(project['elements'])} Elemente, java_block)")


if __name__ == "__main__":
    main()
