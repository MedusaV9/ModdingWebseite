#!/usr/bin/env python3
"""C17 step 8 (+V5 P-MISC, +TUT2 rework) — derive the TU19 / TU31 / TU69 / TU75
tutorial-world VARIANTS from the committed TU12 payload (no network, no server
jar — pure region-file surgery).

WHY derived, not fetched: theminecraftarchitect.com hosts no "JE Latest" zips
for TU19/TU31/TU75 (probed 404, TU69 was never archived there either), and more
full 54x54-chunk bakes (~6.5 MB each) would blow the 30 MB orchestrator size
gate.

TUT2 REWORK — "the tutorial worlds are all the same". The first cut derived all
four variants from the SAME inner 36x36 box around the TU12 footprint center and
copied TU12's spawn verbatim, so every era loaded identical terrain seen from an
identical spawn view; the only difference was a sparse palette recolor that never
touched a surface block (tu12 vs tu19 rendered PIXEL-IDENTICAL from above). Each
variant now takes its OWN 26x26-chunk WINDOW of the 864x864 map — a different
corner with a different biome mix, height profile and skyline — plus its own
auto-verified spawn inside that window, an era block pass that also rewrites
SURFACE blocks and tree species, and an era biome remap (biome drives sky/fog
color, so the worlds read differently the moment you arrive).

  tu19 (2014) — NORTH SHORE, the plains/swamp coast around the tutorial build.
                Era read: the "only oaks" world — every birch/spruce/jungle tree
                is oaked, cobble lightly mossed, first cracked stone bricks.
  tu31 (2015) — SOUTH-WEST DESERT, the dune sea and its outpost. Era read: the
                renovation era — spruce-plank rebuilds, stone-brick patches,
                grass creeping back to sand, dead bushes; savanna/desert sky.
  tu69 (2018) — EAST HIGHLANDS, the windswept hill coast. Era read: the
                aquatic-preview twilight — spruce forests on half the hills,
                gravel beaches, deep moss and ferns, poppies; cool ocean sky.
  tu75 (2019) — SOUTH-EAST FROST, the taiga/jungle border under snow. Era read:
                the console sunset — heavy moss and overgrowth, snowed-over
                ground, iced-over water; snowy biome sky.

Every block remap target is part of the frozen 156-id classic palette contract
(docs/plans_v3/xbox_palette.json), so P5-W8's registered classic block set covers
the variants with zero additions. Property-carrying remaps (logs/leaves/stairs)
keep their property compound verbatim and only ever pair same-shape blocks.

Inputs (committed, sha-stable):  src/main/resources/assets/eclipse/xboxworlds/tu12.zip
                                 src/main/resources/data/eclipse/xboxworlds/tu12_loot.json
Outputs (deterministic bytes):   .../xboxworlds/{tu19,tu31,tu69,tu75}.zip
                                 .../xboxworlds/{tu19,tu31,tu69,tu75}_loot.json
                                 .../xboxworlds/manifest.json (variant entries appended)

Re-run `frames.py` afterwards — the frames pass targets the final loot JSONs.
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import random
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import nbt, palette, region  # noqa: E402

PROJECT_ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/assets/eclipse/xboxworlds")
DATA_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/data/eclipse/xboxworlds")

SOURCE_ID = "tu12"
ZIP_DATE = (2026, 1, 1, 0, 0, 0)  # keep package.py's deterministic-zip contract
AIR = set(palette.AIR_PASSTHROUGH)

C = "eclipse:classic_"


def rule(src, dst, p, props="drop", chunk_p=1.0, where="any", patch=1):
    """One era remap rule.

    src/dst  classic ids (without the shared `eclipse:classic_` prefix)
    p        per-block probability
    props    "drop" = only propertyless palette entries flip (safe default);
             "keep" = the property compound is carried over verbatim (ONLY pair
             same-shape blocks: log→log, leaves→leaves, stairs→stairs …);
             "any"  = the source may carry properties, the target is emitted
             propertyless (grass_block[snowy] → sand and friends — without this
             mode the whole ground-cover pass silently no-ops on grass)
    chunk_p  per-CHUNK gate rolled once, so e.g. a species swap stays coherent
             inside a forest instead of speckling single trees
    where    "any" = the whole volume; "surface" = only the topmost solid block
             of a column (ground cover: snow caps, gravel beaches, sand creep)
    patch    surface rules only: the roll is shared by a patch x patch block
             tile, so ground cover lands as BLOTCHES instead of the salt-and-
             pepper speckle a per-block roll produces on an open landscape
    """
    return {"from": C + src, "to": C + dst, "p": p, "props": props,
            "chunkP": chunk_p, "where": where, "patch": max(1, patch)}


# Trees of one species → oak, keeping axis/distance/persistent properties.
def oak_trees(prob=1.0, chunk_p=1.0):
    out = []
    for species in ("birch", "spruce", "jungle"):
        out.append(rule(f"{species}_log", "oak_log", prob, "keep", chunk_p))
        out.append(rule(f"{species}_leaves", "oak_leaves", prob, "keep", chunk_p))
    return out


VARIANTS = {
    "tu19": {
        "year": 2014,
        "displayName": {"en_us": "Tutorial World (TU19) — 2014",
                        "de_de": "Tutorial-Welt (TU19) — 2014"},
        # North shore: the plains/swamp/ocean coast that holds the tutorial build.
        "box": (-18, 7, -26, -1),
        "spawnAnchor": (-4, -8),
        "biomes": {},
        "remap": oak_trees() + [
            rule("cobblestone", "mossy_cobblestone", 0.18),
            rule("stone_bricks", "cracked_stone_bricks", 0.10),
            rule("short_grass", "dandelion", 0.06),
        ],
    },
    "tu31": {
        "year": 2015,
        "displayName": {"en_us": "Tutorial World (TU31) — 2015",
                        "de_de": "Tutorial-Welt (TU31) — 2015"},
        # South-west dune sea + the desert outpost.
        "box": (-27, -2, 0, 25),
        "spawnAnchor": (-18, 16),
        "biomes": {"minecraft:plains": "minecraft:savanna",
                   "minecraft:forest": "minecraft:savanna_plateau",
                   "minecraft:swamp": "minecraft:desert",
                   "minecraft:jungle": "minecraft:savanna_plateau"},
        "remap": oak_trees() + [
            rule("oak_planks", "spruce_planks", 0.30),
            rule("cobblestone", "stone_bricks", 0.10),
            rule("short_grass", "dead_bush", 0.22),
            rule("fern", "dead_bush", 0.30),
            rule("grass_block", "sand", 0.30, "any", where="surface", patch=4),
            rule("dirt", "sand", 0.25, "any", where="surface", patch=4),
        ],
    },
    "tu69": {
        "year": 2018,
        "displayName": {"en_us": "Tutorial World (TU69) — 2018",
                        "de_de": "Tutorial-Welt (TU69) — 2018"},
        # East highlands: the windswept hill coast (a genuinely different height profile).
        "box": (1, 26, -20, 5),
        "spawnAnchor": (14, -8),
        "biomes": {"minecraft:plains": "minecraft:beach",
                   "minecraft:river": "minecraft:lukewarm_ocean",
                   "minecraft:swamp": "minecraft:lukewarm_ocean"},
        "remap": [
            # Half the hills go conifer — rolled per chunk so whole stands convert.
            rule("oak_log", "spruce_log", 1.0, "keep", chunk_p=0.5),
            rule("oak_leaves", "spruce_leaves", 1.0, "keep", chunk_p=0.5),
            rule("cobblestone", "mossy_cobblestone", 0.34),
            rule("stone_bricks", "mossy_stone_bricks", 0.20),
            rule("short_grass", "fern", 0.34),
            rule("dandelion", "poppy", 0.30),
            rule("sand", "gravel", 0.45, where="surface", patch=3),
            rule("grass_block", "gravel", 0.10, "any", where="surface", patch=3),
        ],
    },
    "tu75": {
        "year": 2019,
        "displayName": {"en_us": "Tutorial World (TU75) — 2019",
                        "de_de": "Tutorial-Welt (TU75) — 2019"},
        # South-east frost: the taiga/jungle border, snowed under.
        "box": (0, 25, 1, 26),
        "spawnAnchor": (12, 14),
        "biomes": {"minecraft:plains": "minecraft:snowy_plains",
                   "minecraft:taiga": "minecraft:snowy_taiga",
                   "minecraft:forest": "minecraft:snowy_taiga",
                   "minecraft:jungle": "minecraft:snowy_taiga",
                   "minecraft:river": "minecraft:frozen_river",
                   "minecraft:ocean": "minecraft:frozen_ocean",
                   "minecraft:beach": "minecraft:snowy_beach",
                   "minecraft:windswept_hills": "minecraft:snowy_slopes"},
        "remap": [
            rule("jungle_log", "spruce_log", 1.0, "keep"),
            rule("jungle_leaves", "spruce_leaves", 1.0, "keep"),
            rule("cobblestone", "mossy_cobblestone", 0.40),
            rule("stone_bricks", "mossy_stone_bricks", 0.25),
            rule("short_grass", "fern", 0.40),
            rule("dandelion", "poppy", 0.50),
            rule("grass_block", "snow_block", 0.70, "any", where="surface", patch=4),
            rule("sand", "snow_block", 0.45, where="surface", patch=4),
            rule("gravel", "snow_block", 0.45, where="surface", patch=4),
            rule("water", "ice", 0.65, where="surface", patch=6),
        ],
    },
}

# --- base worlds: spawn re-anchor -------------------------------------------------------
# TU12 and TU14 are two SEPARATE authentic downloads, but TU14 is the console's TU12 map
# after a content update, so ~79% of their surface columns still render identically and
# package.py had derived the SAME spawn (97, 72, -106) for both — arriving in either one
# looked like arriving in the same world. The variants get their own windows above; the
# base worlds keep their full authentic map and are instead re-anchored so each one opens
# on a different landmark. The anchor chunk below is the densest TU12↔TU14 delta region
# (the forest belt TU14 regrew), ~390 blocks from the TU12 spawn.
#
# Manifest-only: the zip bytes (and therefore the sha256 / size / authenticity of the
# committed download) are untouched — XboxEventService teleports to manifest `spawn`.
BASE_RESPAWN = {"tu14": (4, 17)}

# Blocks a player may be teleported onto (spawn search).
SPAWN_FLOOR = {C + path for path in (
    "grass_block", "dirt", "sand", "sandstone", "stone", "cobblestone", "gravel",
    "snow_block", "oak_planks", "spruce_planks", "birch_planks", "jungle_planks",
    "stone_bricks", "mossy_cobblestone", "mossy_stone_bricks", "bricks", "clay",
    "coarse_dirt", "farmland", "smooth_stone_slab",
)}
SPAWN_SEARCH_RADIUS = 40  # blocks around the anchor chunk center


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def chunk_rng(variant: str, cx: int, cz: int, salt: str = "") -> random.Random:
    """Deterministic per-chunk RNG (stable across runs and Python versions)."""
    return random.Random(zlib.crc32(f"{variant}:{cx}:{cz}:{salt}".encode()))


def load_source_zip(world_id: str = SOURCE_ID) -> tuple[
        dict[tuple[int, int], bytes], dict[tuple[int, int], bytes], bytes]:
    """Returns (region_chunks, entity_chunks, level_dat_bytes) keyed by chunk coords."""
    path = os.path.join(ASSETS_DIR, f"{world_id}.zip")
    regions: dict[tuple[int, int], bytes] = {}
    entities: dict[tuple[int, int], bytes] = {}
    level_dat = b""
    with zipfile.ZipFile(path) as zf:
        for name in zf.namelist():
            if name == "level.dat":
                level_dat = zf.read(name)
                continue
            kind = "region" if name.startswith("region/") else (
                "entities" if name.startswith("entities/") else None)
            if kind is None or not name.endswith(".mca"):
                continue
            data = zf.read(name)
            tmp = os.path.join("/tmp", os.path.basename(name))
            with open(tmp, "wb") as f:
                f.write(data)
            reader = region.RegionReader(tmp)
            for lx, lz, raw in reader.chunks():
                key = (reader.rx * 32 + lx, reader.rz * 32 + lz)
                (regions if kind == "region" else entities)[key] = raw
            os.remove(tmp)
    if not regions or not level_dat:
        raise SystemExit(f"{path} is missing its region payload or level.dat")
    return regions, entities, level_dat


def in_box(cx: int, cz: int, box: tuple[int, int, int, int]) -> bool:
    x0, x1, z0, z1 = box
    return x0 <= cx <= x1 and z0 <= cz <= z1


# ---------------------------------------------------------------- chunk surgery

def decode_sections(root) -> dict[int, list]:
    """{sectionY: [palette_entries, indices, dirty]} for every block section."""
    out = {}
    for sec in root.get("sections", []):
        bs = sec.get("block_states")
        if bs is None:
            continue
        pal = list(bs["palette"])
        out[int(sec["Y"])] = [pal, palette.decode_indices(bs.get("data", []), len(pal)), False]
    return out


def encode_sections(root, sections: dict[int, list]) -> None:
    for sec in root.get("sections", []):
        bs = sec.get("block_states")
        if bs is None:
            continue
        pal, indices, dirty = sections[int(sec["Y"])]
        if not dirty:
            continue
        bs["palette"] = nbt.TagList(nbt.TAG_COMPOUND, pal)
        if len(pal) > 1:
            bs["data"] = palette.encode_indices(indices, len(pal))
        elif "data" in bs:
            del bs["data"]


def entry_index(pal: list, name: str, props) -> int:
    """Index of {name, props} in the palette, appending it when missing."""
    for i, entry in enumerate(pal):
        if entry["Name"] != name:
            continue
        existing = entry.get("Properties")
        if props is None and existing is None:
            return i
        if props is not None and existing is not None and dict(existing) == dict(props):
            return i
    entry = nbt.Compound()
    entry["Name"] = name
    if props is not None:
        copy = nbt.Compound()
        for key, value in props.items():
            copy[key] = value
        entry["Properties"] = copy
    pal.append(entry)
    return len(pal) - 1


def flip_map(pal: list, rules: list) -> dict[int, list]:
    """{palette index: [(target index, probability), …]} for the given rules."""
    out: dict[int, list] = {}
    for i, entry in enumerate(list(pal)):
        name = entry["Name"]
        props = entry.get("Properties")
        for spec in rules:
            if spec["from"] != name:
                continue
            if spec["props"] == "drop" and props is not None:
                continue
            target = entry_index(pal, spec["to"], props if spec["props"] == "keep" else None)
            out.setdefault(i, []).append((target, spec["p"]))
            break
    return out


def apply_volume(variant, cx, cz, sections, rules, stats) -> None:
    active = [r for r in rules
              if r["chunkP"] >= 1.0
              or chunk_rng(variant, cx, cz, r["from"] + ">" + r["to"]).random() < r["chunkP"]]
    if not active:
        return
    for sy, section in sections.items():
        pal, indices, _ = section
        flips = flip_map(pal, active)
        if not flips:
            continue
        rng = chunk_rng(variant, cx, cz, f"vol{sy}")
        flipped = 0
        for pos in range(4096):
            hit = flips.get(indices[pos])
            if hit is None:
                continue
            target, prob = hit[0]
            if rng.random() < prob:
                indices[pos] = target
                flipped += 1
        if flipped:
            section[2] = True
            stats["blocksRemapped"] = stats.get("blocksRemapped", 0) + flipped


def apply_surface(variant, cx, cz, sections, rules, stats) -> None:
    """Rewrites the topmost solid block of every column (ground cover pass)."""
    if not rules:
        return
    air_by_section = {sy: {i for i, e in enumerate(sec[0]) if e["Name"] in AIR}
                      for sy, sec in sections.items()}

    def roll(spec, wx, wz) -> bool:
        """Patch-coherent 0..1 roll on WORLD coordinates (chunk-border safe)."""
        patch = spec["patch"]
        key = f"{variant}:{spec['from']}>{spec['to']}:{wx // patch}:{wz // patch}"
        return zlib.crc32(key.encode()) / 4294967296.0 < spec["p"]

    for z in range(16):
        for x in range(16):
            for sy in sorted(sections, reverse=True):
                pal, indices, _ = sections[sy]
                air = air_by_section[sy]
                found = False
                for y in range(15, -1, -1):
                    pos = (y << 8) | (z << 4) | x
                    idx = indices[pos]
                    if idx in air:
                        continue
                    found = True
                    entry = pal[idx]
                    name = entry["Name"]
                    props = entry.get("Properties")
                    for spec in rules:
                        if spec["from"] != name:
                            continue
                        if spec["props"] == "drop" and props is not None:
                            continue
                        if roll(spec, cx * 16 + x, cz * 16 + z):
                            indices[pos] = entry_index(
                                pal, spec["to"], props if spec["props"] == "keep" else None)
                            sections[sy][2] = True
                            stats["surfaceRemapped"] = stats.get("surfaceRemapped", 0) + 1
                        break
                    break
                if found:
                    break


def apply_biomes(root, biome_map: dict[str, str], stats) -> None:
    if not biome_map:
        return
    for sec in root.get("sections", []):
        bio = sec.get("biomes")
        if bio is None:
            continue
        pal = bio["palette"]
        changed = False
        new_pal = nbt.TagList(nbt.TAG_STRING)
        for name in pal:
            target = biome_map.get(str(name), str(name))
            changed = changed or target != str(name)
            new_pal.append(target)
        if changed:
            bio["palette"] = new_pal
            stats["biomeSections"] = stats.get("biomeSections", 0) + 1


def transform_chunk(variant, cx, cz, raw, spec, stats) -> bytes:
    _, root = nbt.loads(raw)
    sections = decode_sections(root)
    volume = [r for r in spec["remap"] if r["where"] == "any"]
    surface = [r for r in spec["remap"] if r["where"] == "surface"]
    apply_volume(variant, cx, cz, sections, volume, stats)
    apply_surface(variant, cx, cz, sections, surface, stats)
    encode_sections(root, sections)
    apply_biomes(root, spec.get("biomes", {}), stats)
    return nbt.dumps(root)


# ---------------------------------------------------------------- spawn search

def find_spawn(chunks: dict[tuple[int, int], bytes], anchor: tuple[int, int],
               box: tuple[int, int, int, int]) -> tuple[list[int], str]:
    """A verified stand-up spot: solid floor, two air cells above, near the anchor."""
    decoded: dict[tuple[int, int], dict[int, tuple[list, list]]] = {}

    def column(cx, cz):
        cached = decoded.get((cx, cz))
        if cached is None:
            raw = chunks.get((cx, cz))
            cached = {}
            if raw is not None:
                _, root = nbt.loads(raw)
                for sec in root.get("sections", []):
                    bs = sec.get("block_states")
                    if bs is None:
                        continue
                    pal = [e["Name"] for e in bs["palette"]]
                    cached[int(sec["Y"])] = (
                        pal, palette.decode_indices(bs.get("data", []), len(pal)))
            decoded[(cx, cz)] = cached
        return cached

    def block(x, y, z):
        if not 0 <= y <= 255:
            return "minecraft:air"
        sections = column(x >> 4, z >> 4)
        sec = sections.get(y >> 4)
        if sec is None:
            return "minecraft:air"
        pal, idx = sec
        return pal[idx[((y & 15) << 8) | ((z & 15) << 4) | (x & 15)]]

    ax, az = anchor[0] * 16 + 8, anchor[1] * 16 + 8
    x0, x1, z0, z1 = box
    best = None
    for radius in range(0, SPAWN_SEARCH_RADIUS + 1, 2):
        for dz in range(-radius, radius + 1, 2):
            for dx in range(-radius, radius + 1, 2):
                if max(abs(dx), abs(dz)) != radius:
                    continue
                x, z = ax + dx, az + dz
                if not (x0 * 16 + 8 <= x <= x1 * 16 + 7 and z0 * 16 + 8 <= z <= z1 * 16 + 7):
                    continue
                for y in range(140, 50, -1):
                    top = block(x, y, z)
                    if top in AIR:
                        continue
                    # First solid block from the top: it must be walkable ground with
                    # head room — anything else (water, leaves, a roof) rejects the column.
                    if top in SPAWN_FLOOR and block(x, y + 1, z) in AIR \
                            and block(x, y + 2, z) in AIR:
                        best = ([x, y + 1, z], top)
                    break
                if best:
                    return best
    raise SystemExit(f"no spawn spot found near chunk {anchor} inside {box}")


# ---------------------------------------------------------------- packaging

def write_regions(out_dir: str, chunks: dict[tuple[int, int], bytes]) -> None:
    per_region: dict[tuple[int, int], dict[tuple[int, int], bytes]] = {}
    for (cx, cz), raw in chunks.items():
        rx, rz = cx >> 5, cz >> 5
        per_region.setdefault((rx, rz), {})[(cx & 31, cz & 31)] = raw
    os.makedirs(out_dir, exist_ok=True)
    for (rx, rz), chunk_map in sorted(per_region.items()):
        region.write_region(os.path.join(out_dir, region.region_file_name(rx, rz)), chunk_map)


def variant_level_dat(level_dat: bytes, variant: str, spawn: list[int]) -> bytes:
    """Same level.dat with a variant LevelName + spawn (dev-client sugar)."""
    import gzip as gz
    name, root = nbt.loads(gz.decompress(level_dat))
    root["Data"]["LevelName"] = f"Eclipse Xbox {variant.upper()}"
    root["Data"]["SpawnX"] = nbt.Int(spawn[0])
    root["Data"]["SpawnY"] = nbt.Int(spawn[1])
    root["Data"]["SpawnZ"] = nbt.Int(spawn[2])
    raw = nbt.dumps(root, name)
    buf = io.BytesIO()
    with gz.GzipFile(fileobj=buf, mode="wb", compresslevel=9, mtime=0) as f:
        f.write(raw)
    return buf.getvalue()


def deterministic_zip(src_dir: str, dest_zip: str) -> None:
    entries = []
    for root_dir, dirs, files in os.walk(src_dir):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root_dir, name)
            entries.append((os.path.relpath(full, src_dir).replace(os.sep, "/"), full))
    entries.sort()
    with zipfile.ZipFile(dest_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for arcname, full in entries:
            info = zipfile.ZipInfo(arcname, date_time=ZIP_DATE)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as f:
                zf.writestr(info, f.read(), compresslevel=9)


def variant_loot(variant: str, source_loot: dict, box: tuple[int, int, int, int]) -> dict:
    """TU12 loot filtered to the variant window (frames are added by frames.py)."""
    x0, x1, z0, z1 = box
    containers = [c for c in source_loot["containers"]
                  if x0 * 16 <= c["pos"][0] <= x1 * 16 + 15
                  and z0 * 16 <= c["pos"][2] <= z1 * 16 + 15]
    return {
        "worldId": variant,
        "dataVersion": source_loot["dataVersion"],
        "note": (f"derived from tu12_loot.json by tools/xboxworlds/variants.py (TUT2): "
                 f"containers inside the per-era window "
                 f"chunks x{x0}..{x1} z{z0}..{z1}; "
                 + source_loot.get("note", "")),
        "containers": containers,
    }


def main() -> None:
    regions, entities, level_dat = load_source_zip()
    source_loot = json.load(open(os.path.join(DATA_DIR, f"{SOURCE_ID}_loot.json")))
    manifest_path = os.path.join(ASSETS_DIR, "manifest.json")
    manifest = json.load(open(manifest_path))
    tu12_entry = next(w for w in manifest["worlds"] if w["worldId"] == SOURCE_ID)
    # idempotent re-run: drop any previously generated variant entries
    manifest["worlds"] = [w for w in manifest["worlds"] if w["worldId"] not in VARIANTS]

    total_bytes = sum(w["sizeBytes"] for w in manifest["worlds"])
    for variant, spec in VARIANTS.items():
        stats: dict = {}
        box = spec["box"]
        kept_regions = {key: transform_chunk(variant, key[0], key[1], raw, spec, stats)
                        for key, raw in sorted(regions.items()) if in_box(*key, box)}
        kept_entities = {key: raw for key, raw in sorted(entities.items()) if in_box(*key, box)}
        spawn, floor = find_spawn(kept_regions, spec["spawnAnchor"], box)

        build = os.path.join("/tmp/xboxworlds", "variants", variant)
        if os.path.isdir(build):
            import shutil
            shutil.rmtree(build)
        write_regions(os.path.join(build, "region"), kept_regions)
        if kept_entities:
            write_regions(os.path.join(build, "entities"), kept_entities)
        with open(os.path.join(build, "level.dat"), "wb") as f:
            f.write(variant_level_dat(level_dat, variant, spawn))

        zip_path = os.path.join(ASSETS_DIR, f"{variant}.zip")
        deterministic_zip(build, zip_path)
        digest = sha256_of(zip_path)
        size = os.path.getsize(zip_path)
        total_bytes += size

        loot = variant_loot(variant, source_loot, box)
        with open(os.path.join(DATA_DIR, f"{variant}_loot.json"), "w") as f:
            json.dump(loot, f, indent=2, ensure_ascii=False)
            f.write("\n")

        x0, x1, z0, z1 = box
        manifest["worlds"].append({
            "worldId": variant,
            "displayName": spec["displayName"],
            "zip": f"assets/eclipse/xboxworlds/{variant}.zip",
            "zipEntries": tu12_entry["zipEntries"],
            "spawn": spawn,
            "spawnYaw": tu12_entry["spawnYaw"],
            "dataVersion": tu12_entry["dataVersion"],
            "sha256": digest,
            "sizeBytes": size,
            "chunkCount": len(kept_regions),
            "bounds": {
                "chunkMin": [x0, z0],
                "chunkMax": [x1, z1],
                "blockMin": [x0 * 16, 0, z0 * 16],
                "blockMax": [x1 * 16 + 15, 255, z1 * 16 + 15],
            },
            "lootManifest": f"data/eclipse/xboxworlds/{variant}_loot.json",
        })
        print(f"[{variant}] {zip_path}  {size} bytes  chunks={len(kept_regions)}  "
              f"window x{x0}..{x1} z{z0}..{z1}  spawn={spawn} on {floor}  "
              f"volume={stats.get('blocksRemapped', 0)} surface={stats.get('surfaceRemapped', 0)} "
              f"biomeSections={stats.get('biomeSections', 0)}  sha256={digest}")

    for world_id, anchor in BASE_RESPAWN.items():
        entry = next((w for w in manifest["worlds"] if w["worldId"] == world_id), None)
        if entry is None:
            continue
        base_regions, _, _ = load_source_zip(world_id)
        bounds = entry["bounds"]
        box = (bounds["chunkMin"][0], bounds["chunkMax"][0],
               bounds["chunkMin"][1], bounds["chunkMax"][1])
        spawn, floor = find_spawn(base_regions, anchor, box)
        print(f"[{world_id}] re-anchored spawn {entry['spawn']} -> {spawn} on {floor} "
              f"(anchor chunk {anchor})")
        entry["spawn"] = spawn

    manifest["worlds"].sort(key=lambda w: (len(w["worldId"]), w["worldId"]))
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nTOTAL bundled worlds: {total_bytes} bytes ({total_bytes / 1048576:.2f} MiB) "
          f"for {len(manifest['worlds'])} worlds (30 MB gate: "
          f"{'WITHIN' if total_bytes <= 30 * 1024 * 1024 else 'OVER'})")
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    main()
