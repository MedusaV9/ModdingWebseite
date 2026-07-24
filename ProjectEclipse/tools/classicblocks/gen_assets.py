#!/usr/bin/env python3
"""P5-W8 — generate all classic-block assets from manifest.py.

Emits (deterministically, sorted keys, so re-runs are byte-identical):
  src/generated/resources/assets/eclipse/blockstates/classic_*.json
  src/generated/resources/assets/eclipse/models/block/classic/*.json
  src/generated/resources/assets/eclipse/models/item/classic_*.json
  src/generated/resources/data/eclipse/loot_table/blocks/classic_*.json
  src/generated/resources/data/minecraft/tags/block/{mineable/*,needs_*,climbable}.json
  docs/plans_v3/langdrop/P5-W8.json
  src/main/java/dev/projecteclipse/eclipse/classicblocks/ClassicBlockList.java

`src/generated/resources` is already a resource source dir (build.gradle line
~21), so no gradle changes are needed; this replaces gradle datagen per the
worker instructions (no runData, no build.gradle edits).

State->model rotation tables for the complex shapes (stairs, doors, trapdoors,
rails, panes, fences, vine, wire, lever, buttons, pistons, ...) are remapped
from the vanilla client resources (purely functional data), read from the
moddev artifact jar, so orientations are guaranteed correct.
"""

import glob
import json
import os
import shutil
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest
import texplan

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "src/generated/resources")
ASSETS = os.path.join(GEN, "assets/eclipse")
DATA = os.path.join(GEN, "data")
JAVA_LIST = os.path.join(
    ROOT, "src/main/java/dev/projecteclipse/eclipse/classicblocks/ClassicBlockList.java")

P = manifest.PREFIX  # "classic_"


def T(name):
    return f"eclipse:block/classic/{name}"


def M(name):
    return f"eclipse:block/classic/{name}"


def find_vanilla_jar():
    pats = glob.glob(os.path.join(ROOT, "build/moddev/artifacts/*client-extra*.jar"))
    if not pats:
        raise SystemExit("vanilla client resources jar not found under build/moddev/artifacts "
                         "(run any gradle task once to materialize it)")
    return pats[0]


class Vanilla:
    def __init__(self):
        self.zip = zipfile.ZipFile(find_vanilla_jar())

    def blockstate(self, block_id):
        return json.loads(self.zip.read(f"assets/minecraft/blockstates/{block_id}.json"))


VAN = None  # lazy


def remap_blockstate(vanilla_id, model_map):
    """Load the vanilla state table and swap model references via model_map."""
    bs = VAN.blockstate(vanilla_id)

    def remap_apply(a):
        out = dict(a)
        ref = out["model"].split(":", 1)[-1].removeprefix("block/")
        if ref not in model_map:
            raise SystemExit(f"no model mapping for {out['model']} (mirror {vanilla_id})")
        out["model"] = model_map[ref]
        return out

    if "variants" in bs:
        return {"variants": {
            k: ([remap_apply(v) for v in vv] if isinstance(vv, list) else remap_apply(vv))
            for k, vv in bs["variants"].items()}}
    parts = []
    for part in bs["multipart"]:
        a = part["apply"]
        np = {"apply": [remap_apply(v) for v in a] if isinstance(a, list) else remap_apply(a)}
        if "when" in part:
            np["when"] = part["when"]
        parts.append(np)
    return {"multipart": parts}


# ---------------------------------------------------------------------------
# output helpers
# ---------------------------------------------------------------------------
FILES = {}


def emit(relpath, obj):
    if relpath in FILES:
        raise SystemExit(f"duplicate output file {relpath}")
    FILES[relpath] = obj


def model(name, parent, textures=None, render=None, extra=None):
    m = {"parent": parent}
    if textures:
        m["textures"] = textures
    if render:
        m["render_type"] = f"minecraft:{render}"
    if extra:
        m.update(extra)
    emit(f"assets/eclipse/models/block/classic/{name}.json", m)
    return M(name)


def blockstate(bid, obj):
    emit(f"assets/eclipse/blockstates/{P}{bid}.json", obj)


def item_model(bid, obj):
    emit(f"assets/eclipse/models/item/{P}{bid}.json", obj)


def loot_self(bid, name=None):
    item = f"eclipse:{P}{name or bid}"
    return {
        "type": "minecraft:block",
        "pools": [{
            "rolls": 1.0, "bonus_rolls": 0.0,
            "entries": [{"type": "minecraft:item", "name": item}],
            "conditions": [{"condition": "minecraft:survives_explosion"}],
        }],
        "random_sequence": f"eclipse:blocks/{P}{bid}",
    }


def loot_slab(bid):
    item = f"eclipse:{P}{bid}"
    return {
        "type": "minecraft:block",
        "pools": [{
            "rolls": 1.0, "bonus_rolls": 0.0,
            "entries": [{
                "type": "minecraft:item", "name": item,
                "functions": [
                    {"function": "minecraft:set_count",
                     "count": 2.0,
                     "conditions": [{
                         "condition": "minecraft:block_state_property",
                         "block": f"eclipse:{P}{bid}",
                         "properties": {"type": "double"}}]},
                    {"function": "minecraft:explosion_decay"},
                ],
            }],
        }],
        "random_sequence": f"eclipse:blocks/{P}{bid}",
    }


def loot_door(bid):
    item = f"eclipse:{P}{bid}"
    return {
        "type": "minecraft:block",
        "pools": [{
            "rolls": 1.0, "bonus_rolls": 0.0,
            "entries": [{"type": "minecraft:item", "name": item}],
            "conditions": [
                {"condition": "minecraft:block_state_property",
                 "block": f"eclipse:{P}{bid}",
                 "properties": {"half": "lower"}},
                {"condition": "minecraft:survives_explosion"},
            ],
        }],
        "random_sequence": f"eclipse:blocks/{P}{bid}",
    }


def loot_bed(bid):
    # vanilla parity: only the head half rolls the drop (breaking either half
    # removes both, so exactly one item drops per bed)
    item = f"eclipse:{P}{bid}"
    return {
        "type": "minecraft:block",
        "pools": [{
            "rolls": 1.0, "bonus_rolls": 0.0,
            "entries": [{"type": "minecraft:item", "name": item}],
            "conditions": [
                {"condition": "minecraft:block_state_property",
                 "block": f"eclipse:{P}{bid}",
                 "properties": {"part": "head"}},
                {"condition": "minecraft:survives_explosion"},
            ],
        }],
        "random_sequence": f"eclipse:blocks/{P}{bid}",
    }


# ---------------------------------------------------------------------------
# per-kind generators
# ---------------------------------------------------------------------------

def gen_block(b):
    bid = b["id"]
    kind = b["model"]
    tx = texplan.slots_for(b)
    render = b["render"]

    def t(slot):
        return T(tx[slot])

    if kind == "cube_all":
        m = model(bid, "minecraft:block/cube_all", {"all": t("all")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "cube_bottom_top":
        m = model(bid, "minecraft:block/cube_bottom_top",
                  {"top": t("top"), "bottom": t("bottom"), "side": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "cube_column_static":
        m = model(bid, "minecraft:block/cube_column", {"end": t("end"), "side": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "pillar":
        m = model(bid, "minecraft:block/cube_column", {"end": t("end"), "side": t("side")}, render)
        mh = model(f"{bid}_horizontal", "minecraft:block/cube_column_horizontal",
                   {"end": t("end"), "side": t("side")}, render)
        blockstate(bid, {"variants": {
            "axis=x": {"model": mh, "x": 90, "y": 90},
            "axis=y": {"model": m},
            "axis=z": {"model": mh, "x": 90}}})
    elif kind == "grass_block":
        m = model(bid, "minecraft:block/cube_bottom_top",
                  {"top": t("top"), "bottom": t("bottom"), "side": t("side")})
        ms = model(f"{bid}_snow", "minecraft:block/cube_bottom_top",
                   {"top": t("top"), "bottom": t("bottom"), "side": t("snow_side")})
        blockstate(bid, remap_blockstate("grass_block", {
            "grass_block": m, "grass_block_snow": ms}))
    elif kind == "leaves":
        m = model(bid, "minecraft:block/leaves", {"all": t("all")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "crafting_table":
        m = model(bid, "minecraft:block/cube", {
            "particle": t("front"), "down": t("bottom"), "up": t("top"),
            "north": t("front"), "south": t("front"),
            "east": t("side"), "west": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "chest":
        m = model(bid, "minecraft:block/orientable",
                  {"front": t("front"), "side": t("side"), "top": t("top")}, render)
        blockstate(bid, {"variants": {
            "facing=north": {"model": m},
            "facing=south": {"model": m, "y": 180},
            "facing=west": {"model": m, "y": 270},
            "facing=east": {"model": m, "y": 90}}})
    elif kind == "furnace":
        m = model(bid, "minecraft:block/orientable",
                  {"front": t("front"), "side": t("side"), "top": t("top")}, render)
        mo = model(f"{bid}_on", "minecraft:block/orientable",
                   {"front": t("front_on"), "side": t("side"), "top": t("top")}, render)
        blockstate(bid, remap_blockstate("furnace", {"furnace": m, "furnace_on": mo}))
    elif kind == "dispenser":
        m = model(bid, "minecraft:block/orientable",
                  {"front": t("front"), "side": t("side"), "top": t("top")}, render)
        mv = model(f"{bid}_vertical", "minecraft:block/orientable_vertical",
                   {"front": t("front_vertical"), "side": t("top")}, render)
        blockstate(bid, remap_blockstate("dispenser", {"dispenser": m, "dispenser_vertical": mv}))
    elif kind == "jukebox":
        m = model(bid, "minecraft:block/cube_bottom_top",
                  {"top": t("top"), "bottom": t("side"), "side": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "tnt":
        m = model(bid, "minecraft:block/cube_bottom_top",
                  {"top": t("top"), "bottom": t("bottom"), "side": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "slab":
        m = model(bid, "minecraft:block/slab",
                  {"bottom": t("bottom"), "top": t("top"), "side": t("side")}, render)
        mt = model(f"{bid}_top", "minecraft:block/slab_top",
                   {"bottom": t("bottom"), "top": t("top"), "side": t("side")}, render)
        double_ref = M(b["param"])
        blockstate(bid, {"variants": {
            "type=bottom": {"model": m},
            "type=top": {"model": mt},
            "type=double": {"model": double_ref}}})
    elif kind == "stairs":
        m = model(bid, "minecraft:block/stairs",
                  {"bottom": t("bottom"), "top": t("top"), "side": t("side")}, render)
        mi = model(f"{bid}_inner", "minecraft:block/inner_stairs",
                   {"bottom": t("bottom"), "top": t("top"), "side": t("side")}, render)
        mo = model(f"{bid}_outer", "minecraft:block/outer_stairs",
                   {"bottom": t("bottom"), "top": t("top"), "side": t("side")}, render)
        blockstate(bid, remap_blockstate("oak_stairs", {
            "oak_stairs": m, "oak_stairs_inner": mi, "oak_stairs_outer": mo}))
    elif kind == "fence":
        mp = model(f"{bid}_post", "minecraft:block/fence_post", {"texture": t("texture")}, render)
        ms = model(f"{bid}_side", "minecraft:block/fence_side", {"texture": t("texture")}, render)
        model(f"{bid}_inventory", "minecraft:block/fence_inventory", {"texture": t("texture")}, render)
        blockstate(bid, remap_blockstate("oak_fence", {
            "oak_fence_post": mp, "oak_fence_side": ms}))
    elif kind == "pane":
        names = {}
        for part in ("post", "side", "side_alt", "noside", "noside_alt"):
            names[f"glass_pane_{part}"] = model(
                f"{bid}_{part}", f"minecraft:block/template_glass_pane_{part}",
                {"pane": t("pane"), "edge": t("edge")}, render)
        blockstate(bid, remap_blockstate("glass_pane", names))
    elif kind == "ladder":
        m = model(bid, "minecraft:block/ladder",
                  {"texture": t("texture"), "particle": t("texture")}, render)
        blockstate(bid, remap_blockstate("ladder", {"ladder": m}))
    elif kind == "door":
        names = {}
        for part in ("bottom_left", "bottom_left_open", "bottom_right", "bottom_right_open",
                     "top_left", "top_left_open", "top_right", "top_right_open"):
            names[f"oak_door_{part}"] = model(
                f"{bid}_{part}", f"minecraft:block/door_{part}",
                {"top": t("top"), "bottom": t("bottom")}, render)
        blockstate(bid, remap_blockstate("oak_door", names))
    elif kind == "trapdoor":
        names = {}
        for part in ("bottom", "top", "open"):
            names[f"oak_trapdoor_{part}"] = model(
                f"{bid}_{part}", f"minecraft:block/template_trapdoor_{part}",
                {"texture": t("texture")}, render)
        blockstate(bid, remap_blockstate("oak_trapdoor", names))
    elif kind == "torch":
        m = model(bid, "minecraft:block/template_torch", {"torch": t("torch")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "wall_torch":
        m = model(bid, "minecraft:block/template_torch_wall", {"torch": t("torch")}, render)
        blockstate(bid, remap_blockstate("wall_torch", {"wall_torch": m}))
    elif kind == "rs_torch":
        mon = model(bid, "minecraft:block/template_torch", {"torch": t("on")}, render)
        moff = model(f"{bid}_off", "minecraft:block/template_torch", {"torch": t("off")}, render)
        blockstate(bid, {"variants": {
            "lit=true": {"model": mon}, "lit=false": {"model": moff}}})
    elif kind == "rs_wall_torch":
        mon = model(bid, "minecraft:block/template_torch_wall", {"torch": t("on")}, render)
        moff = model(f"{bid}_off", "minecraft:block/template_torch_wall", {"torch": t("off")}, render)
        blockstate(bid, remap_blockstate("redstone_wall_torch", {
            "redstone_wall_torch": mon, "redstone_wall_torch_off": moff}))
    elif kind == "cross":
        m = model(bid, "minecraft:block/cross", {"cross": t("cross")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "crop8":
        variants = {}
        for i in range(8):
            mi = model(f"{bid}_stage{i}", "minecraft:block/crop", {"crop": t(f"stage{i}")}, render)
            variants[f"age={i}"] = {"model": mi}
        blockstate(bid, {"variants": variants})
    elif kind == "stem":
        variants = {}
        for i in range(8):
            mi = model(f"{bid}_stage{i}", f"minecraft:block/stem_growth{i}", {"stem": t("stem")}, render)
            variants[f"age={i}"] = {"model": mi}
        blockstate(bid, {"variants": variants})
    elif kind == "attached_stem":
        m = model(bid, "minecraft:block/stem_fruit",
                  {"stem": t("stem"), "upperstem": t("upperstem")}, render)
        van = "attached_pumpkin_stem" if bid.startswith("attached_pumpkin") else "attached_melon_stem"
        blockstate(bid, remap_blockstate(van, {van: m}))
    elif kind == "farmland":
        m = model(bid, "minecraft:block/template_farmland", {"dirt": t("dirt"), "top": t("top")}, render)
        mm = model(f"{bid}_moist", "minecraft:block/template_farmland",
                   {"dirt": t("dirt"), "top": t("moist")}, render)
        blockstate(bid, remap_blockstate("farmland", {"farmland": m, "farmland_moist": mm}))
    elif kind == "snow_layer":
        names = {}
        for h in range(2, 16, 2):
            names[f"snow_height{h}"] = model(
                f"{bid}_height{h}", f"minecraft:block/snow_height{h}",
                {"texture": t("texture"), "particle": t("texture")}, render)
        names["snow_block"] = M("snow_block")  # layers=8 -> our full snow block model
        blockstate(bid, remap_blockstate("snow", names))
    elif kind == "orientable":
        m = model(bid, "minecraft:block/orientable",
                  {"front": t("front"), "side": t("side"), "top": t("top")}, render)
        blockstate(bid, remap_blockstate("carved_pumpkin", {"carved_pumpkin": m}))
    elif kind == "rail_full":
        mf = model(bid, "minecraft:block/rail_flat", {"rail": t("flat")}, render)
        mc = model(f"{bid}_corner", "minecraft:block/rail_curved", {"rail": t("corner")}, render)
        mn = model(f"{bid}_raised_ne", "minecraft:block/template_rail_raised_ne", {"rail": t("flat")}, render)
        ms = model(f"{bid}_raised_sw", "minecraft:block/template_rail_raised_sw", {"rail": t("flat")}, render)
        blockstate(bid, remap_blockstate("rail", {
            "rail": mf, "rail_corner": mc, "rail_raised_ne": mn, "rail_raised_sw": ms}))
    elif kind == "rail_straight":
        mf = model(bid, "minecraft:block/rail_flat", {"rail": t("flat")}, render)
        mon = model(f"{bid}_on", "minecraft:block/rail_flat", {"rail": t("flat_on")}, render)
        mn = model(f"{bid}_raised_ne", "minecraft:block/template_rail_raised_ne", {"rail": t("flat")}, render)
        ms = model(f"{bid}_raised_sw", "minecraft:block/template_rail_raised_sw", {"rail": t("flat")}, render)
        mon_n = model(f"{bid}_on_raised_ne", "minecraft:block/template_rail_raised_ne", {"rail": t("flat_on")}, render)
        mon_s = model(f"{bid}_on_raised_sw", "minecraft:block/template_rail_raised_sw", {"rail": t("flat_on")}, render)
        blockstate(bid, remap_blockstate("powered_rail", {
            "powered_rail": mf, "powered_rail_on": mon,
            "powered_rail_raised_ne": mn, "powered_rail_raised_sw": ms,
            "powered_rail_on_raised_ne": mon_n, "powered_rail_on_raised_sw": mon_s}))
    elif kind == "lever":
        m = model(bid, "minecraft:block/lever",
                  {"base": t("base"), "lever": t("lever"), "particle": t("base")}, render)
        # deco simplification: same model for both powered states
        blockstate(bid, remap_blockstate("lever", {"lever": m, "lever_on": m}))
    elif kind == "button":
        m = model(bid, "minecraft:block/button", {"texture": t("texture")}, render)
        mp = model(f"{bid}_pressed", "minecraft:block/button_pressed", {"texture": t("texture")}, render)
        model(f"{bid}_inventory", "minecraft:block/button_inventory", {"texture": t("texture")}, render)
        blockstate(bid, remap_blockstate("stone_button", {
            "stone_button": m, "stone_button_pressed": mp}))
    elif kind == "plate":
        m = model(bid, "minecraft:block/pressure_plate_up", {"texture": t("texture")}, render)
        md = model(f"{bid}_down", "minecraft:block/pressure_plate_down", {"texture": t("texture")}, render)
        blockstate(bid, remap_blockstate("oak_pressure_plate", {
            "oak_pressure_plate": m, "oak_pressure_plate_down": md}))
    elif kind == "wire":
        common = {"overlay": T(tx["overlay"]), "particle": T(tx["dot"])}
        names = {}
        names["redstone_dust_dot"] = model(
            f"{bid}_dot", "minecraft:block/redstone_dust_dot",
            dict(common, line=T(tx["dot"])), render)
        for van, line in (("side0", "line0"), ("side_alt0", "line0"),
                          ("side1", "line1"), ("side_alt1", "line1"), ("up", "line0")):
            names[f"redstone_dust_{van}"] = model(
                f"{bid}_{van}", f"minecraft:block/redstone_dust_{van}",
                dict(common, line=T(tx[line])), render)
        blockstate(bid, remap_blockstate("redstone_wire", names))
    elif kind == "repeater":
        def repeater_model(name, top):
            return model(name, None if False else "minecraft:block/thin_block", None, render, extra={
                "textures": {"particle": T(tx["stone"]), "top": T(top),
                             "stone": T(tx["stone"])},
                "elements": [{
                    "from": [0, 0, 0], "to": [16, 2, 16],
                    "faces": {
                        "down": {"uv": [0, 0, 16, 16], "texture": "#stone", "cullface": "down"},
                        "up": {"uv": [0, 0, 16, 16], "texture": "#top"},
                        "north": {"uv": [0, 14, 16, 16], "texture": "#stone", "cullface": "north"},
                        "south": {"uv": [0, 14, 16, 16], "texture": "#stone", "cullface": "south"},
                        "west": {"uv": [0, 14, 16, 16], "texture": "#stone", "cullface": "west"},
                        "east": {"uv": [0, 14, 16, 16], "texture": "#stone", "cullface": "east"},
                    },
                }],
            })
        m = repeater_model(bid, tx["off"])
        mon = repeater_model(f"{bid}_on", tx["on"])
        variants = {}
        for facing, y in (("south", 0), ("west", 90), ("north", 180), ("east", 270)):
            for powered, mm in (("false", m), ("true", mon)):
                v = {"model": mm}
                if y:
                    v["y"] = y
                variants[f"facing={facing},powered={powered}"] = v
        blockstate(bid, {"variants": variants})
    elif kind == "piston":
        m = model(bid, "minecraft:block/piston",
                  {"platform": t("platform"), "side": t("side"), "bottom": t("bottom"),
                   "particle": t("side")}, render)
        mb = model(f"{bid}_base", "minecraft:block/piston_base",
                   {"inside": t("inner"), "side": t("side"), "bottom": t("bottom"),
                    "particle": t("side")}, render)
        model(f"{bid}_inventory", "minecraft:block/cube_bottom_top",
              {"top": t("platform"), "bottom": t("bottom"), "side": t("side")}, render)
        blockstate(bid, remap_blockstate("piston", {"piston": m, "piston_base": mb}))
    elif kind == "piston_head":
        m = model(bid, "minecraft:block/piston_head",
                  {"platform": t("platform"), "side": t("side"), "unsticky": t("platform"),
                   "particle": t("platform")}, render)
        ms = model(f"{bid}_sticky", "minecraft:block/piston_head_sticky",
                   {"platform": t("sticky"), "side": t("side"), "unsticky": t("platform"),
                    "particle": t("platform")}, render)
        blockstate(bid, remap_blockstate("piston_head", {
            "piston_head": m, "piston_head_sticky": ms,
            "piston_head_short": m, "piston_head_short_sticky": ms}))
    elif kind == "vine":
        m = model(bid, "minecraft:block/vine", {"vine": t("vine"), "particle": t("vine")}, render)
        blockstate(bid, remap_blockstate("vine", {"vine": m}))
    elif kind == "lily":
        m = model(bid, "minecraft:block/lily_pad",
                  {"texture": t("texture"), "particle": t("texture")}, render)
        blockstate(bid, {"variants": {"": [
            {"model": m}, {"model": m, "y": 90}, {"model": m, "y": 180}, {"model": m, "y": 270}]}})
    elif kind == "cactus":
        m = model(bid, "minecraft:block/cactus",
                  {"top": t("top"), "side": t("side"), "bottom": t("bottom"),
                   "particle": t("side")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    # --- palette reconciliation kinds ------------------------------------------
    elif kind == "mycelium":
        m = model(bid, "minecraft:block/cube_bottom_top",
                  {"top": t("top"), "bottom": t("bottom"), "side": t("side")}, render)
        # snowy=true reuses the classic grass snow-side model, exactly like vanilla
        blockstate(bid, remap_blockstate("mycelium", {
            "mycelium": m, "grass_block_snow": M("grass_block_snow")}))
    elif kind == "cube_all_inner":
        m = model(bid, "minecraft:block/cube_all_inner_faces", {"all": t("all")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "wall":
        mp = model(f"{bid}_post", "minecraft:block/template_wall_post", {"wall": t("wall")}, render)
        ms = model(f"{bid}_side", "minecraft:block/template_wall_side", {"wall": t("wall")}, render)
        mt = model(f"{bid}_side_tall", "minecraft:block/template_wall_side_tall", {"wall": t("wall")}, render)
        model(f"{bid}_inventory", "minecraft:block/wall_inventory", {"wall": t("wall")}, render)
        blockstate(bid, remap_blockstate(b["mirror"], {
            f"{b['mirror']}_post": mp, f"{b['mirror']}_side": ms,
            f"{b['mirror']}_side_tall": mt}))
    elif kind == "carpet":
        m = model(bid, "minecraft:block/carpet", {"wool": t("wool"), "particle": t("wool")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "anvil":
        m = model(bid, "minecraft:block/template_anvil",
                  {"top": t("top"), "body": t("body"), "particle": t("body")}, render)
        blockstate(bid, remap_blockstate("anvil", {"anvil": m}))
    elif kind == "brewing_stand":
        names = {"brewing_stand": model(bid, "minecraft:block/brewing_stand",
                 {"base": t("base"), "stand": t("stand"), "particle": t("stand")}, render)}
        for part in ("bottle0", "bottle1", "bottle2", "empty0", "empty1", "empty2"):
            names[f"brewing_stand_{part}"] = model(
                f"{bid}_{part}", f"minecraft:block/brewing_stand_{part}",
                {"stand": t("stand"), "particle": t("stand")}, render)
        blockstate(bid, remap_blockstate("brewing_stand", names))
    elif kind == "enchanting_table":
        m = model(bid, "minecraft:block/enchanting_table",
                  {"top": t("top"), "side": t("side"), "bottom": t("bottom"),
                   "particle": t("bottom")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "end_portal_frame":
        m = model(bid, "minecraft:block/end_portal_frame",
                  {"top": t("top"), "side": t("side"), "bottom": t("bottom"),
                   "particle": t("side")}, render)
        mf = model(f"{bid}_filled", "minecraft:block/end_portal_frame_filled",
                   {"top": t("top"), "side": t("side"), "bottom": t("bottom"),
                    "eye": t("eye"), "particle": t("side")}, render)
        blockstate(bid, remap_blockstate("end_portal_frame", {
            "end_portal_frame": m, "end_portal_frame_filled": mf}))
    elif kind == "rs_lamp":
        m = model(bid, "minecraft:block/cube_all", {"all": t("off")}, render)
        mon = model(f"{bid}_on", "minecraft:block/cube_all", {"all": t("on")}, render)
        blockstate(bid, remap_blockstate("redstone_lamp", {
            "redstone_lamp": m, "redstone_lamp_on": mon}))
    elif kind == "nether_portal":
        mew = model(f"{bid}_ew", "minecraft:block/nether_portal_ew",
                    {"portal": t("portal"), "particle": t("portal")}, render)
        mns = model(f"{bid}_ns", "minecraft:block/nether_portal_ns",
                    {"portal": t("portal"), "particle": t("portal")}, render)
        blockstate(bid, remap_blockstate("nether_portal", {
            "nether_portal_ew": mew, "nether_portal_ns": mns}))
    elif kind == "fire":
        names = {}
        for part in ("floor0", "floor1", "side0", "side1", "side_alt0", "side_alt1",
                     "up0", "up1", "up_alt0", "up_alt1"):
            slot = "fire0" if part.endswith("0") else "fire1"
            names[f"fire_{part}"] = model(f"{bid}_{part}", f"minecraft:block/fire_{part}",
                                          {"fire": t(slot)}, render)
        blockstate(bid, remap_blockstate("fire", names))
    elif kind == "fence_gate":
        names = {}
        for suffix in ("", "_open", "_wall", "_wall_open"):
            names[f"oak_fence_gate{suffix}"] = model(
                f"{bid}{suffix}", f"minecraft:block/template_fence_gate{suffix}",
                {"texture": t("texture")}, render)
        blockstate(bid, remap_blockstate("oak_fence_gate", names))
    elif kind == "crop4":
        names = {}
        for i in range(4):
            names[f"{bid}_stage{i}"] = model(f"{bid}_stage{i}", "minecraft:block/crop",
                                             {"crop": t(f"stage{i}")}, render)
        blockstate(bid, remap_blockstate(b["mirror"], names))
    elif kind == "cocoa":
        names = {}
        for i in range(3):
            names[f"cocoa_stage{i}"] = model(
                f"{bid}_stage{i}", f"minecraft:block/cocoa_stage{i}",
                {"cocoa": t(f"stage{i}"), "particle": t(f"stage{i}")}, render)
        blockstate(bid, remap_blockstate("cocoa", names))
    elif kind == "mushroom":
        m = model(bid, "minecraft:block/template_single_face", {"texture": t("outside")}, render)
        blockstate(bid, remap_blockstate(b["mirror"], {
            b["mirror"]: m, "mushroom_block_inside": M("mushroom_block_inside")}))
    elif kind == "tripwire":
        names = {}
        for part in ("n", "ne", "ns", "nse", "nsew"):
            names[f"tripwire_{part}"] = model(
                f"{bid}_{part}", f"minecraft:block/tripwire_{part}",
                {"texture": t("texture"), "particle": t("texture")}, render)
            names[f"tripwire_attached_{part}"] = model(
                f"{bid}_attached_{part}", f"minecraft:block/tripwire_attached_{part}",
                {"texture": t("texture"), "particle": t("texture")}, render)
        blockstate(bid, remap_blockstate("tripwire", names))
    elif kind == "tripwire_hook":
        m = model(bid, "minecraft:block/tripwire_hook",
                  {"hook": t("hook"), "wood": t("wood"), "particle": t("wood")}, render)
        ma = model(f"{bid}_attached", "minecraft:block/tripwire_hook_attached",
                   {"hook": t("hook"), "wood": t("wood"), "tripwire": t("tripwire"),
                    "particle": t("wood")}, render)
        # deco simplification: powered states reuse the unpowered visuals
        blockstate(bid, remap_blockstate("tripwire_hook", {
            "tripwire_hook": m, "tripwire_hook_attached": ma,
            "tripwire_hook_on": m, "tripwire_hook_attached_on": ma}))
    elif kind == "cauldron":
        names = {}
        for van, tmpl in (("water_cauldron_level1", "template_cauldron_level1"),
                          ("water_cauldron_level2", "template_cauldron_level2"),
                          ("water_cauldron_full", "template_cauldron_full")):
            names[van] = model(f"{bid}_{van.rsplit('_', 1)[1]}", f"minecraft:block/{tmpl}",
                               {"top": t("top"), "bottom": t("bottom"), "side": t("side"),
                                "inside": t("inside"), "content": t("content"),
                                "particle": t("side")}, render)
        blockstate(bid, remap_blockstate("water_cauldron", names))
    elif kind == "potted":
        m = model(bid, "minecraft:block/flower_pot_cross",
                  {"plant": t("plant"), "flowerpot": t("flowerpot"), "dirt": t("dirt"),
                   "particle": t("flowerpot")}, render)
        blockstate(bid, {"variants": {"": {"model": m}}})
    elif kind == "skull":
        variants = _gen_skull(bid, t, render)
        blockstate(bid, {"variants": variants})
    elif kind == "bed":
        mh = _gen_bed_half(f"{bid}_head", t, render, head=True)
        mf = _gen_bed_half(f"{bid}_foot", t, render, head=False)
        variants = {}
        for facing, y in (("north", 0), ("east", 90), ("south", 180), ("west", 270)):
            for part, mm in (("head", mh), ("foot", mf)):
                v = {"model": mm}
                if y:
                    v["y"] = y
                variants[f"facing={facing},part={part}"] = v
        blockstate(bid, {"variants": variants})
    elif kind == "wall_sign":
        m = _gen_wall_sign(bid, t, render)
        variants = {}
        for facing, y in (("north", 0), ("east", 90), ("south", 180), ("west", 270)):
            v = {"model": m}
            if y:
                v["y"] = y
            variants[f"facing={facing}"] = v
        blockstate(bid, {"variants": variants})
    else:
        raise SystemExit(f"no generator for model kind {kind} ({bid})")


def _gen_skull(bid, t, render):
    """Vanilla skulls are BER-rendered (no JSON). Classic skulls are a UV-mapped
    8x8x8 cube over a 32x16 head crop of the era skin (u scale 0.5/px, v 1/px).

    ROTATION_16 (0 = facing south, clockwise) decomposes into a 90-degree
    blockstate rotation plus an element sub-rotation of 0/-22.5/-45/+22.5
    (element angles are counter-clockwise, blockstate y is clockwise).
    """
    def skull_model(name, angle):
        el = {
            "from": [4, 0, 4], "to": [12, 8, 12],
            "faces": {
                "up": {"uv": [4, 0, 8, 8], "texture": "#skin"},
                "down": {"uv": [8, 0, 12, 8], "texture": "#skin"},
                "south": {"uv": [4, 8, 8, 16], "texture": "#skin"},   # face
                "north": {"uv": [12, 8, 16, 16], "texture": "#skin"},
                "west": {"uv": [0, 8, 4, 16], "texture": "#skin"},
                "east": {"uv": [8, 8, 12, 16], "texture": "#skin"},
            },
        }
        if angle:
            el["rotation"] = {"origin": [8, 0, 8], "axis": "y", "angle": angle}
        return model(name, "minecraft:block/block",
                     {"skin": t("skin"), "particle": t("skin")}, render,
                     extra={"elements": [el]})

    models = [skull_model(bid, 0), skull_model(f"{bid}_r22", -22.5),
              skull_model(f"{bid}_r45", -45), skull_model(f"{bid}_r68", 22.5)]
    variants = {}
    for r in range(16):
        base, frac = (r // 4) * 90, r % 4
        y = base if frac < 3 else (base + 90) % 360
        v = {"model": models[frac]}
        if y:
            v["y"] = y
        variants[f"rotation={r}"] = v
    return variants


def _gen_bed_half(name, t, render, head):
    """Beds are BER-rendered in vanilla; classic beds are two flat JSON boxes
    UV-mapped into the pack's 64x64 bed sheet (u/v scale 0.25/px).

    Model space: facing=north / y=0, pillow end at z=0 (north). Region offsets
    follow the vanilla bed entity texture layout (head @0,0 / foot @0,22).
    """
    if head:
        top = [1.5, 1.5, 5.5, 5.5]       # px (6,6)-(22,22)
        end = [1.5, 0, 5.5, 1.5]         # px (6,0)-(22,6)
        west = [0, 1.5, 1.5, 5.5]        # px (0,6)-(6,22)
        east = [5.5, 1.5, 7, 5.5]        # px (22,6)-(28,22)
        legs_z = (0, 3)
    else:
        top = [1.5, 7, 5.5, 11]          # px (6,28)-(22,44)
        end = [1.5, 5.5, 5.5, 7]         # px (6,22)-(22,28)
        west = [0, 7, 1.5, 11]
        east = [5.5, 7, 7, 11]
        legs_z = (13, 16)
    leg_uv = [12.75, 0.75, 13.5, 1.5]    # px (51,3)-(54,6), dark leg wood
    mattress = {
        "from": [0, 3, 0], "to": [16, 9, 16],
        "faces": {
            "up": {"uv": top, "texture": "#sheet"},
            "down": {"uv": top, "texture": "#sheet"},
            "north": {"uv": end, "texture": "#sheet"},
            "south": {"uv": end, "texture": "#sheet"},
            "west": {"uv": west, "texture": "#sheet", "rotation": 90},
            "east": {"uv": east, "texture": "#sheet", "rotation": 270},
        },
    }
    legs = []
    for x0 in (0, 13):
        legs.append({
            "from": [x0, 0, legs_z[0]], "to": [x0 + 3, 3, legs_z[1]],
            "faces": {f: {"uv": leg_uv, "texture": "#sheet"}
                      for f in ("north", "south", "east", "west", "down")},
        })
    return model(name, "minecraft:block/block",
                 {"sheet": t("sheet"), "particle": t("sheet")}, render,
                 extra={"elements": [mattress] + legs})


def _gen_wall_sign(bid, t, render):
    """Wall signs are BER-rendered in vanilla; classic signs are a flat board
    UV-mapped into the 64x16 crop of the pack's sign entity texture
    (u scale 0.25/px, v scale 1/px). Model faces north (board near z=16)."""
    board = {
        "from": [0, 4.5, 14], "to": [16, 12.5, 16],
        "faces": {
            "north": {"uv": [0.5, 2, 6.5, 14], "texture": "#board"},
            "south": {"uv": [6.5, 2, 12.5, 14], "texture": "#board"},
            "up": {"uv": [0.5, 0, 6.5, 2], "texture": "#board"},
            "down": {"uv": [6.5, 0, 12.5, 2], "texture": "#board"},
            "west": {"uv": [0, 2, 0.5, 14], "texture": "#board"},
            "east": {"uv": [0, 2, 0.5, 14], "texture": "#board"},
        },
    }
    return model(bid, "minecraft:block/block",
                 {"board": t("board"), "particle": t("board")}, render,
                 extra={"elements": [board]})


def gen_extra_models():
    # double-slab full model for smooth_stone_slab (no full block twin exists)
    model("smooth_stone_slab_double", "minecraft:block/cube_column",
          {"end": T("smooth_stone"), "side": T("smooth_stone_slab_side")})
    # pore face shared by all three huge-mushroom blocks
    model("mushroom_block_inside", "minecraft:block/template_single_face",
          {"texture": T("mushroom_block_inside")})


def gen_item(b):
    bid = b["id"]
    item = b["item"]
    if item == "none":
        return
    if isinstance(item, str) and item.startswith("generated:"):
        ref = item.split(":", 1)[1]
        item_model(bid, {"parent": "minecraft:item/generated",
                         "textures": {"layer0": f"eclipse:{ref}"}})
        return
    if item == "tall":
        item_model(bid, {"parent": "minecraft:item/generated",
                         "textures": {"layer0": f"eclipse:item/classic/{b['tex']['item']}"}})
        return
    if isinstance(item, str) and item.startswith("standing_wall:"):
        tx = texplan.slots_for(b)
        layer = tx.get("torch") or tx.get("on")
        item_model(bid, {"parent": "minecraft:item/generated",
                         "textures": {"layer0": T(layer)}})
        return
    if item == "inventory":
        item_model(bid, {"parent": M(f"{bid}_inventory")})
        return
    # default: parent a block model
    kind = b["model"]
    ref = {
        "trapdoor": f"{bid}_bottom",
        "snow_layer": f"{bid}_height2",
    }.get(kind, bid)
    item_model(bid, {"parent": M(ref)})


def gen_loot(b):
    bid = b["id"]
    loot = b["loot"]
    if loot == "self":
        obj = loot_self(bid)
    elif loot == "empty":
        obj = {"type": "minecraft:block", "pools": []}
    elif loot == "slab":
        obj = loot_slab(bid)
    elif loot == "door":
        obj = loot_door(bid)
    elif loot == "bed":
        obj = loot_bed(bid)
    elif loot.startswith("drop:"):
        obj = loot_self(bid, loot.split(":", 1)[1])
    else:
        raise SystemExit(f"unknown loot kind {loot} for {bid}")
    emit(f"data/eclipse/loot_table/blocks/{P}{bid}.json", obj)


def gen_tags():
    tags = {
        "mineable/pickaxe": [], "mineable/axe": [], "mineable/shovel": [], "mineable/hoe": [],
        "needs_stone_tool": [], "needs_iron_tool": [], "needs_diamond_tool": [],
        "climbable": [], "fences": [], "wooden_fences": [], "snow": [], "walls": [],
    }
    for b in manifest.BLOCKS:
        rid = f"eclipse:{P}{b['id']}"
        if b["tool"]:
            tags[f"mineable/{b['tool']}"].append(rid)
        if b["tier"]:
            tags[f"needs_{b['tier']}_tool"].append(rid)
        if b["climbable"]:
            tags["climbable"].append(rid)
        # FenceBlock#connectsTo consults BLOCK tags minecraft:fences /
        # minecraft:wooden_fences (isSameFence) — without membership, baked
        # fence runs would visually disconnect on the first neighbor update.
        # Block tags only; recipes use ITEM tags, which classic blocks never join.
        if b["shape"] == "fence":
            tags["fences"].append(rid)
            if b["sound"] == "WOOD":
                tags["wooden_fences"].append(rid)
        # WallBlock#connectsTo consults minecraft:walls the same way — baked wall
        # runs must keep their low-wall connections after neighbor updates.
        if b["shape"] == "wall":
            tags["walls"].append(rid)
        # ClassicSnowyBlock toggles its snowy cap via the minecraft:snow BLOCK tag
        # (covers vanilla grass under classic snow too). Visual-only tag.
        if b["id"] in ("snow", "snow_block"):
            tags["snow"].append(rid)
    for name, values in tags.items():
        if values:
            emit(f"data/minecraft/tags/block/{name}.json",
                 {"replace": False, "values": values})


def gen_langdrop():
    en, de = {}, {}
    for b in manifest.BLOCKS:
        key = f"block.eclipse.{P}{b['id']}"
        en[key] = f"Classic — {b['en']}"
        de[key] = f"Klassisch — {b['de']}"
    en[manifest.TAB_KEY] = manifest.TAB_EN
    de[manifest.TAB_KEY] = manifest.TAB_DE
    path = os.path.join(ROOT, manifest.LANGDROP)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"en_us": dict(sorted(en.items())), "de_de": dict(sorted(de.items()))},
                  f, indent=2, ensure_ascii=False)
        f.write("\n")
    return len(en)


# ---------------------------------------------------------------------------
# ClassicBlockList.java generation
# ---------------------------------------------------------------------------
JAVA_HEADER = '''\
// GENERATED FILE — do not edit by hand.
// Source of truth: tools/classicblocks/manifest.py  (regen: python3 tools/classicblocks/gen_assets.py)
package dev.projecteclipse.eclipse.classicblocks;

import java.util.List;

import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.material.MapColor;

/**
 * P5-W8 manifest of every {@code eclipse:classic_*} block (frozen naming scheme:
 * vanilla {@code minecraft:<path>} maps to {@code eclipse:classic_<path>}, identical
 * blockstate properties — P5-W7's region baker relies on these ids verbatim).
 *
 * <p>Assets (blockstates/models/loot/tags/lang) are generated from the same manifest
 * by {@code tools/classicblocks/gen_assets.py} into {@code src/generated/resources}.
 */
public final class ClassicBlockList {

    /** How an entry registers (see {@link ClassicBlocks#create}). */
    public enum Shape {
        SIMPLE, GRASS, PILLAR, LEAVES, SLAB, STAIRS, FENCE, PANE, LADDER, DOOR, TRAPDOOR,
        TORCH, WALL_TORCH, RS_TORCH, RS_WALL_TORCH, CROSS, SAPLING, CROP8, CANE, CACTUS,
        STEM, ATTACHED_STEM, FARMLAND, SNOW_LAYER, FLUID, CHEST, FURNACE_LIKE, DISPENSER,
        JUKEBOX, NOTE_BLOCK, TNT, RS_ORE, LEVER, BUTTON, PLATE, WIRE, REPEATER, PISTON,
        PISTON_HEAD, RAIL_FULL, RAIL_STRAIGHT, VINE, LILY, HORIZONTAL,
        // palette reconciliation (xbox_palette.json)
        WALL, CARPET, ANVIL, BREWING_STAND, ENCHANTING_TABLE, END_PORTAL_FRAME, ENDER_CHEST,
        RS_LAMP, NETHER_PORTAL, FIRE, FENCE_GATE, WALL_SIGN, BED, COCOA, MUSHROOM, TRIPWIRE,
        TRIPWIRE_HOOK, CAULDRON, POTTED, SKULL
    }

    /** How the matching item registers (never: recipes, fuel, vanilla tabs). */
    public enum ItemKind { BLOCK, NONE, TALL, STANDING_WALL }

    /**
     * @param id        path without the {@code classic_} prefix (vanilla twin's path)
     * @param shape     registration kind
     * @param hardness  destroy time (vanilla twin's value; -1 = unbreakable)
     * @param resistance explosion resistance
     * @param light     constant light emission (state-dependent light lives in the shape classes)
     * @param requiresTool vanilla twin's requiresCorrectToolForDrops
     * @param sound     vanilla twin's sound type
     * @param mapColor  vanilla twin's map color
     * @param noOcclusion true for glassy/leafy blocks
     * @param itemKind  BLOCK = plain BlockItem, TALL = door item, STANDING_WALL = torch-style,
     *                  NONE = technical block without an item
     * @param itemParam wall-block id for STANDING_WALL items
     * @param param     shape-specific extra (stairs base block, door set type, "slippery", ...)
     */
    public record Entry(String id, Shape shape, float hardness, float resistance, int light,
                        boolean requiresTool, SoundType sound, MapColor mapColor,
                        boolean noOcclusion, ItemKind itemKind, String itemParam, String param) {

        public String blockId() {
            return "classic_" + id;
        }
    }

    private static Entry e(String id, Shape shape, float hardness, float resistance, int light,
                           boolean requiresTool, SoundType sound, MapColor mapColor,
                           boolean noOcclusion, ItemKind itemKind, String itemParam, String param) {
        return new Entry(id, shape, hardness, resistance, light, requiresTool, sound, mapColor,
                noOcclusion, itemKind, itemParam, param);
    }

    /** Every classic block, in stable registration order. */
    public static final List<Entry> ENTRIES = List.of(
'''

JAVA_FOOTER = '''\
    );

    private ClassicBlockList() {}
}
'''

SHAPE_JAVA = {
    "simple": "SIMPLE", "grass": "GRASS", "pillar": "PILLAR", "leaves": "LEAVES",
    "slab": "SLAB", "stairs": "STAIRS", "fence": "FENCE", "pane": "PANE",
    "ladder": "LADDER", "door": "DOOR", "trapdoor": "TRAPDOOR", "torch": "TORCH",
    "wall_torch": "WALL_TORCH", "rs_torch": "RS_TORCH", "rs_wall_torch": "RS_WALL_TORCH",
    "cross": "CROSS", "sapling": "SAPLING", "crop8": "CROP8", "cane": "CANE",
    "cactus": "CACTUS", "stem": "STEM", "attached_stem": "ATTACHED_STEM",
    "farmland": "FARMLAND", "snow_layer": "SNOW_LAYER", "fluid": "FLUID",
    "chest": "CHEST", "furnace_like": "FURNACE_LIKE", "dispenser": "DISPENSER",
    "jukebox": "JUKEBOX", "note_block": "NOTE_BLOCK", "tnt": "TNT", "rs_ore": "RS_ORE",
    "lever": "LEVER", "button": "BUTTON", "plate": "PLATE", "wire": "WIRE",
    "repeater": "REPEATER", "piston": "PISTON", "piston_head": "PISTON_HEAD",
    "rail_full": "RAIL_FULL", "rail_straight": "RAIL_STRAIGHT", "vine": "VINE",
    "lily": "LILY", "horizontal": "HORIZONTAL",
    "wall": "WALL", "carpet": "CARPET", "anvil": "ANVIL", "brewing_stand": "BREWING_STAND",
    "enchanting_table": "ENCHANTING_TABLE", "end_portal_frame": "END_PORTAL_FRAME",
    "ender_chest": "ENDER_CHEST", "rs_lamp": "RS_LAMP", "nether_portal": "NETHER_PORTAL",
    "fire": "FIRE", "fence_gate": "FENCE_GATE", "wall_sign": "WALL_SIGN", "bed": "BED",
    "cocoa": "COCOA", "mushroom": "MUSHROOM", "tripwire": "TRIPWIRE",
    "tripwire_hook": "TRIPWIRE_HOOK", "cauldron": "CAULDRON", "potted": "POTTED",
    "skull": "SKULL",
}


def jf(v):
    if v == int(v) and abs(v) < 1e7:
        return f"{v:.1f}F"
    return f"{v}F"


def gen_java():
    lines = []
    for b in manifest.BLOCKS:
        item = b["item"]
        if item == "none":
            ik, ip = "NONE", None
        elif item == "tall":
            ik, ip = "TALL", None
        elif isinstance(item, str) and item.startswith("standing_wall:"):
            ik, ip = "STANDING_WALL", item.split(":", 1)[1]
        else:
            ik, ip = "BLOCK", None
        param = b["param"]
        lines.append(
            "            e({id}, Shape.{shape}, {hard}, {res}, {light}, {req}, SoundType.{sound}, "
            "MapColor.{color}, {noocc}, ItemKind.{ik}, {ip}, {param})".format(
                id=json.dumps(b["id"]), shape=SHAPE_JAVA[b["shape"]], hard=jf(b["hard"]),
                res=jf(b["res"]), light=b["light"], req=str(b["req"]).lower(),
                sound=b["sound"], color=b["color"], noocc=str(b["noocc"]).lower(),
                ik=ik, ip=json.dumps(ip) if ip else "null",
                param=json.dumps(param) if param else "null"))
    body = ",\n".join(lines) + "\n"
    os.makedirs(os.path.dirname(JAVA_LIST), exist_ok=True)
    with open(JAVA_LIST, "w", encoding="utf-8") as f:
        f.write(JAVA_HEADER + body + JAVA_FOOTER)


# ---------------------------------------------------------------------------
def main():
    global VAN
    VAN = Vanilla()

    gen_extra_models()
    for b in manifest.BLOCKS:
        gen_block(b)
        gen_item(b)
        gen_loot(b)
    gen_tags()
    keys = gen_langdrop()
    gen_java()

    # wipe + rewrite generated tree (only our own subfolders)
    roots = [
        os.path.join(ASSETS, "blockstates"),
        os.path.join(ASSETS, "models/block/classic"),
        os.path.join(ASSETS, "models/item"),
        os.path.join(DATA, "eclipse/loot_table/blocks"),
        os.path.join(DATA, "minecraft/tags/block"),
    ]
    for r in roots:
        if os.path.isdir(r):
            shutil.rmtree(r)
    for rel, obj in sorted(FILES.items()):
        path = os.path.join(GEN, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, indent=2, sort_keys=True)
            f.write("\n")

    n = {"blockstates": 0, "block models": 0, "item models": 0, "loot": 0, "tags": 0}
    for rel in FILES:
        if rel.startswith("assets/eclipse/blockstates/"):
            n["blockstates"] += 1
        elif rel.startswith("assets/eclipse/models/block/"):
            n["block models"] += 1
        elif rel.startswith("assets/eclipse/models/item/"):
            n["item models"] += 1
        elif "loot_table" in rel:
            n["loot"] += 1
        elif "/tags/" in rel:
            n["tags"] += 1
    print(f"emitted {sum(n.values())} JSON files: {n}")
    print(f"langdrop: {keys} keys per language -> {manifest.LANGDROP}")
    print(f"java list -> {os.path.relpath(JAVA_LIST, ROOT)}")


if __name__ == "__main__":
    main()
