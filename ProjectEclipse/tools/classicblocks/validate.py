#!/usr/bin/env python3
"""P5-W8 — validate generated classic-block assets against the manifest, the Java
manifest list and the vanilla client resources.

Checks (all must pass; exit 1 on any failure):
  1. every generated JSON parses
  2. every vanilla twin id exists in vanilla (blockstate present in client jar)
  3. blockstate model refs resolve to generated models
  4. model parent/texture refs resolve (eclipse: -> generated/bundled, minecraft: -> client jar)
  5. property names in MY blockstates are a subset of the Java block's property set
  6. property names in the VANILLA twin blockstate are a subset too (W7 bake parity:
     every visual state distinction vanilla makes is representable by the classic block)
  7. item models exist exactly for entries with an item; loot tables exist for all blocks
     and only reference classic ids that have items (or vanilla ids)
  8. tags only reference manifest ids; mineable/needs_tool coverage matches the manifest
  9. langdrop has exactly one key per block + the tab key, en/de, correct prefixes
 10. no orphan bundled textures, no orphan generated models
 11. ClassicBlockList.java is in sync (count + ids in manifest order)
"""

import json
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import manifest
from gen_assets import find_vanilla_jar

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GEN = os.path.join(ROOT, "src/generated/resources")
ASSETS = os.path.join(GEN, "assets/eclipse")
TEXTURES = os.path.join(ROOT, "src/main/resources/assets/eclipse/textures")
P = manifest.PREFIX

ERRORS = []


def err(msg):
    ERRORS.append(msg)


# Java-side property sets per shape (source of truth: classicblocks/block/*.java).
EXPECTED_PROPS = {
    "simple": set(), "grass": {"snowy"}, "pillar": {"axis"},
    "leaves": {"distance", "persistent", "waterlogged"},
    "slab": {"type", "waterlogged"}, "stairs": {"facing", "half", "shape", "waterlogged"},
    "fence": {"north", "east", "south", "west", "waterlogged"},
    "pane": {"north", "east", "south", "west", "waterlogged"},
    "ladder": {"facing", "waterlogged"},
    "door": {"facing", "half", "hinge", "open", "powered"},
    "trapdoor": {"facing", "half", "open", "powered", "waterlogged"},
    "torch": set(), "wall_torch": {"facing"}, "rs_torch": {"lit"},
    "rs_wall_torch": {"facing", "lit"}, "cross": set(), "sapling": {"stage"},
    "crop8": {"age"}, "cane": {"age"}, "cactus": {"age"}, "stem": {"age"},
    "attached_stem": {"facing"}, "farmland": {"moisture"}, "snow_layer": {"layers"},
    "fluid": set(), "chest": {"facing", "type", "waterlogged"},
    "furnace_like": {"facing", "lit"}, "dispenser": {"facing", "triggered"},
    "jukebox": {"has_record"}, "note_block": {"instrument", "note", "powered"},
    "tnt": {"unstable"}, "rs_ore": {"lit"}, "lever": {"face", "facing", "powered"},
    "button": {"face", "facing", "powered"}, "plate": {"powered"},
    "wire": {"north", "east", "south", "west", "power"},
    "repeater": {"facing", "delay", "locked", "powered"},
    "piston": {"facing", "extended"}, "piston_head": {"facing", "type", "short"},
    "rail_full": {"shape", "waterlogged"},
    "rail_straight": {"shape", "powered", "waterlogged"},
    "vine": {"up", "north", "south", "east", "west"}, "lily": set(),
    "horizontal": {"facing"},
    # palette reconciliation shapes
    "wall": {"north", "east", "south", "west", "up", "waterlogged"},
    "carpet": set(), "anvil": {"facing"},
    "brewing_stand": {"has_bottle_0", "has_bottle_1", "has_bottle_2"},
    "enchanting_table": set(), "end_portal_frame": {"eye", "facing"},
    "ender_chest": {"facing", "waterlogged"}, "rs_lamp": {"lit"},
    "nether_portal": {"axis"},
    "fire": {"age", "up", "north", "east", "south", "west"},
    "fence_gate": {"facing", "in_wall", "open", "powered"},
    "wall_sign": {"facing", "waterlogged"},
    "bed": {"facing", "part", "occupied"},
    "cocoa": {"age", "facing"},
    "mushroom": {"up", "down", "north", "east", "south", "west"},
    "tripwire": {"attached", "disarmed", "east", "north", "south", "west", "powered"},
    "tripwire_hook": {"attached", "facing", "powered"},
    "cauldron": {"level"}, "potted": set(),
    "skull": {"rotation", "powered"},
}


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as exc:  # parse errors are validation failures
        err(f"JSON parse failed: {os.path.relpath(path, ROOT)}: {exc}")
        return None


def blockstate_props(bs):
    """All property names a blockstate file distinguishes."""
    props = set()
    if bs is None:
        return props
    for key in bs.get("variants", {}):
        for part in filter(None, key.split(",")):
            props.add(part.split("=", 1)[0])
    for entry in bs.get("multipart", []):
        conds = entry.get("when", {})
        for grp in (conds.get("OR") or conds.get("AND") or [conds]):
            props.update(k for k in grp if k not in ("OR", "AND"))
    return props


def iter_models(bs):
    if bs is None:
        return
    for value in bs.get("variants", {}).values():
        for v in (value if isinstance(value, list) else [value]):
            yield v["model"]
    for entry in bs.get("multipart", []):
        apply_ = entry["apply"]
        for v in (apply_ if isinstance(apply_, list) else [apply_]):
            yield v["model"]


def main():
    van = zipfile.ZipFile(find_vanilla_jar())
    van_names = set(van.namelist())

    blocks = manifest.BLOCKS
    by_id = {b["id"]: b for b in blocks}
    print(f"manifest blocks: {len(blocks)}")

    # --- generated file inventories -------------------------------------------------
    bs_dir = os.path.join(ASSETS, "blockstates")
    bm_dir = os.path.join(ASSETS, "models/block/classic")
    im_dir = os.path.join(ASSETS, "models/item")
    loot_dir = os.path.join(GEN, "data/eclipse/loot_table/blocks")
    tag_dir = os.path.join(GEN, "data/minecraft/tags/block")

    block_models = {f[:-5] for f in os.listdir(bm_dir) if f.endswith(".json")}
    item_models = {f[:-5] for f in os.listdir(im_dir) if f.endswith(".json")}
    block_tex = {f[:-4] for f in os.listdir(os.path.join(TEXTURES, "block/classic")) if f.endswith(".png")}
    item_tex = {f[:-4] for f in os.listdir(os.path.join(TEXTURES, "item/classic")) if f.endswith(".png")}

    referenced_models = set()
    referenced_block_tex = set()
    referenced_item_tex = set()

    # --- 2-6: per-block checks -------------------------------------------------------
    for b in blocks:
        bid, shape = b["id"], b["shape"]
        # vanilla twin must exist (frozen naming scheme)
        if f"assets/minecraft/blockstates/{bid}.json" not in van_names:
            err(f"{bid}: vanilla twin blockstate missing (naming scheme violation)")
            continue
        my_path = os.path.join(bs_dir, f"{P}{bid}.json")
        if not os.path.isfile(my_path):
            err(f"{bid}: generated blockstate missing")
            continue
        mine = load_json(my_path)
        vanilla = json.loads(van.read(f"assets/minecraft/blockstates/{bid}.json"))

        allowed = EXPECTED_PROPS[shape]
        mine_props = blockstate_props(mine)
        if not mine_props <= allowed:
            err(f"{bid}: blockstate uses properties {mine_props - allowed} not on the Java block")
        van_props = blockstate_props(vanilla)
        if not van_props <= allowed:
            err(f"{bid}: vanilla twin distinguishes {van_props - allowed} not on the Java block")

        for model in iter_models(mine):
            if not model.startswith("eclipse:block/classic/"):
                err(f"{bid}: blockstate references non-classic model {model}")
                continue
            name = model.split("/")[-1]
            referenced_models.add(name)
            if name not in block_models:
                err(f"{bid}: blockstate references missing model {model}")

    # --- 4: model parent/texture refs + orphan tracking ------------------------------
    def check_model(path, name, kind):
        m = load_json(path)
        if m is None:
            return
        parent = m.get("parent", "")
        if parent.startswith("eclipse:"):
            pname = parent.split("/")[-1]
            referenced_models.add(pname)
            if pname not in block_models:
                err(f"model {name}: missing eclipse parent {parent}")
        elif parent.startswith("minecraft:") or (parent and ":" not in parent):
            ppath = parent.split(":", 1)[-1]
            if f"assets/minecraft/models/{ppath}.json" not in van_names:
                err(f"model {name}: missing vanilla parent {parent}")
        for slot, tex in m.get("textures", {}).items():
            if tex.startswith("#"):
                continue
            ns_path = tex.split(":", 1)[-1]
            if tex.startswith("eclipse:"):
                if ns_path.startswith("block/classic/"):
                    tname = ns_path.split("/")[-1]
                    referenced_block_tex.add(tname)
                    if tname not in block_tex:
                        err(f"model {name}: missing block texture {tex}")
                elif ns_path.startswith("item/classic/"):
                    tname = ns_path.split("/")[-1]
                    referenced_item_tex.add(tname)
                    if tname not in item_tex:
                        err(f"model {name}: missing item texture {tex}")
                else:
                    err(f"model {name}: unexpected eclipse texture path {tex}")
            else:
                if f"assets/minecraft/textures/{ns_path}.png" not in van_names:
                    err(f"model {name}: missing vanilla texture {tex}")

    for name in sorted(block_models):
        check_model(os.path.join(bm_dir, f"{name}.json"), f"block/classic/{name}", "block")
    for name in sorted(item_models):
        check_model(os.path.join(im_dir, f"{name}.json"), f"item/{name}", "item")

    # --- 7: item models + loot -------------------------------------------------------
    with_item = {b["id"] for b in blocks if b["item"] != "none"}
    for b in blocks:
        want = b["id"] in with_item
        have = f"{P}{b['id']}" in item_models
        if want != have:
            err(f"{b['id']}: item model {'missing' if want else 'present but block has no item'}")
        # item models must parent block models or use item textures — covered by check_model
        loot_path = os.path.join(loot_dir, f"{P}{b['id']}.json")
        loot = load_json(loot_path)
        if loot is None:
            err(f"{b['id']}: loot table missing/unreadable")
            continue
        for pool in loot.get("pools", []):
            for entry in pool.get("entries", []):
                for name in re.findall(r'"name":\s*"([^"]+)"', json.dumps({"e": entry})) or [entry.get("name", "")]:
                    if not name:
                        continue
                    if name.startswith("eclipse:"):
                        rid = name.split(":", 1)[1]
                        if not rid.startswith(P) or rid[len(P):] not in by_id:
                            err(f"{b['id']}: loot references unknown {name}")
                        elif by_id[rid[len(P):]]["item"] == "none":
                            err(f"{b['id']}: loot drops itemless block {name}")

    # extra models referenced only as loot/parents (e.g. double slab) are fine if reachable
    for name in sorted(block_models - referenced_models):
        err(f"orphan generated model: block/classic/{name}")
    for name in sorted(block_tex - referenced_block_tex):
        err(f"orphan bundled block texture: {name}.png")
    for name in sorted(item_tex - referenced_item_tex):
        err(f"orphan bundled item texture: {name}.png")

    # --- 8: tags ----------------------------------------------------------------------
    tag_files = {}
    for dirpath, _dirs, files in os.walk(tag_dir):
        for f in files:
            rel = os.path.relpath(os.path.join(dirpath, f), tag_dir)[:-5]
            tag_files[rel] = load_json(os.path.join(dirpath, f))
    for tag, data in tag_files.items():
        if data is None:
            continue
        if data.get("replace") is not False:
            err(f"tag {tag}: must not replace")
        for rid in data.get("values", []):
            if not rid.startswith(f"eclipse:{P}") or rid.split(":", 1)[1][len(P):] not in by_id:
                err(f"tag {tag}: unknown id {rid}")
    for b in blocks:
        rid = f"eclipse:{P}{b['id']}"
        if b["tool"]:
            if rid not in (tag_files.get(f"mineable/{b['tool']}") or {}).get("values", []):
                err(f"{b['id']}: missing from mineable/{b['tool']}")
        if b["tier"]:
            if rid not in (tag_files.get(f"needs_{b['tier']}_tool") or {}).get("values", []):
                err(f"{b['id']}: missing from needs_{b['tier']}_tool")

    # --- 9: langdrop ------------------------------------------------------------------
    lang = load_json(os.path.join(ROOT, manifest.LANGDROP))
    if lang:
        for code, prefix in (("en_us", "Classic — "), ("de_de", "Klassisch — ")):
            keys = set(lang[code])
            want = {f"block.eclipse.{P}{b['id']}" for b in blocks} | {manifest.TAB_KEY}
            if keys != want:
                err(f"langdrop {code}: key set mismatch (missing {want - keys}, extra {keys - want})")
            for k, v in lang[code].items():
                if k.startswith("block.") and not v.startswith(prefix):
                    err(f"langdrop {code}: {k} does not start with '{prefix}'")

    # --- 11: ClassicBlockList.java sync ------------------------------------------------
    java = open(os.path.join(
        ROOT, "src/main/java/dev/projecteclipse/eclipse/classicblocks/ClassicBlockList.java"),
        encoding="utf-8").read()
    java_ids = re.findall(r'\n            e\("([a-z0-9_]+)"', java)
    if java_ids != [b["id"] for b in blocks]:
        err("ClassicBlockList.java out of sync with manifest (regenerate)")

    # --- 12: W7 palette cross-check ------------------------------------------------------
    # docs/plans_v3/xbox_palette.json is the authoritative block list for the baked
    # tutorial worlds: every id must exist, and every property the bake recorded must
    # exist on the classic block (identical property sets = palette resolves verbatim).
    pal_path = os.path.join(ROOT, "docs/plans_v3/xbox_palette.json")
    if os.path.isfile(pal_path):
        pal = load_json(pal_path)
        pal_n = 0
        for entry in pal["entries"]:
            vid = entry["vanillaId"].split(":", 1)[1]
            if vid == "air":
                continue
            pal_n += 1
            if vid not in by_id:
                err(f"palette: {entry['vanillaId']} has no classic twin in the manifest")
                continue
            if entry["classicId"] != f"eclipse:{P}{vid}":
                err(f"palette: {entry['classicId']} violates the frozen naming scheme")
            allowed = EXPECTED_PROPS[by_id[vid]["shape"]]
            extra = set(entry.get("properties", {})) - allowed
            if extra:
                err(f"palette: {vid} bakes properties {extra} the classic block lacks")
        # W7 wiring: classic_water/classic_lava must be PROPERTYLESS
        for fid in ("water", "lava"):
            if EXPECTED_PROPS[by_id[fid]["shape"]]:
                err(f"palette: classic_{fid} must have no blockstate properties")
        print(f"palette cross-check: {pal_n} baked ids covered")
    else:
        err("docs/plans_v3/xbox_palette.json missing (W7 hand-off)")

    # --- report ------------------------------------------------------------------------
    total_tex_kb = sum(
        os.path.getsize(os.path.join(TEXTURES, sub, f))
        for sub in ("block/classic", "item/classic")
        for f in os.listdir(os.path.join(TEXTURES, sub))) / 1024
    print(f"blockstates: {len(blocks)} checked | block models: {len(block_models)} | "
          f"item models: {len(item_models)} | textures: {len(block_tex)}+{len(item_tex)} "
          f"({total_tex_kb:.0f} KiB) | tags: {len(tag_files)}")
    if ERRORS:
        print(f"\nFAIL — {len(ERRORS)} problem(s):")
        for e in ERRORS:
            print(f"  - {e}")
        sys.exit(1)
    print("OK — all validation checks passed")


if __name__ == "__main__":
    main()
