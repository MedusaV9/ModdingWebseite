#!/usr/bin/env python3
"""P5-W7 step 3 - TRIM + BAKE the upgraded worlds (plan SS2.13.1 steps 3-4, SS2.14).

Per world (input <workDir>/upgraded/<id>, output <workDir>/baked/<id>):

TRIM
  * overworld only (upgrade step already pruned DIM-1/DIM1/poi),
  * chunk purge: drop chunks with InhabitedTime == 0 that lie outside the
    |dx|,|dz| <= trimChunkRadius (27) chunk box around the level.dat spawn,
  * drop chunks whose status is not minecraft:full (proto chunks would try to
    resume generation with the void generator),
  * drop fully-air chunks anywhere (void backfill renders identically),
  * drop sections outside Y 0..15 (dimension_type xbox_classic is min_y 0,
    height 256; non-air content found there is reported loudly),
  * strip per-chunk derived/vanilla-upgrade data: Heightmaps, light arrays +
    isLightOn (recomputed on load), structures, PostProcessing, UpgradeData,
    blending_data, below_zero_retrogen, fluid_ticks, block_ticks.

BAKE
  * palette remap minecraft:X -> eclipse:classic_X per the FROZEN scheme in
    mclib/palette.py (air passthrough, water/lava -> propertyless FLUID_SOLID
    ids, waterlogged forced to "false"); fail-loud on any non-vanilla id,
  * chest/container contents -> loot manifest (vanilla ItemStack JSON codec
    shape: {"id","count","components"}), then ALL block entities are blanked
    (classic blocks have no block entities, SS2.14),
  * entities: keep only paintings + (glow) item frames,
  * spawn: verified against the baked blocks (feet/head must be air, floor
    solid); Y is auto-adjusted if the recorded spawn is obstructed,
  * palette scan report for P5-W8 (distinct ids + counts + property values).

Deterministic: same input -> byte-identical region files (sorted chunk order,
zlib-9, zeroed timestamps, gzip mtime=0). Never touches the game at runtime -
this is the offline replacement for the plan's `/dev xboxevent bake` wrapper.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import nbt, region, palette  # noqa: E402

CFG_PATH = os.path.join(HERE, "worlds.json")

# Non-solid floor heuristic for the spawn check only (vanilla path names).
NONSOLID_FLOOR_PATHS = {
    "torch", "wall_torch", "rail", "powered_rail", "detector_rail", "activator_rail",
    "short_grass", "grass", "tall_grass", "fern", "large_fern", "dead_bush", "seagrass",
    "dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip",
    "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy", "sunflower", "lilac",
    "rose_bush", "peony", "brown_mushroom", "red_mushroom", "wheat", "carrots",
    "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "attached_melon_stem",
    "attached_pumpkin_stem", "sugar_cane", "vine", "lily_pad", "nether_wart",
    "redstone_wire", "repeater", "comparator", "lever", "tripwire", "tripwire_hook",
    "stone_button", "oak_button", "stone_pressure_plate", "oak_pressure_plate",
    "light_weighted_pressure_plate", "heavy_weighted_pressure_plate", "snow",
    "oak_sign", "oak_wall_sign", "ladder", "cobweb", "fire", "sapling",
    "oak_sapling", "spruce_sapling", "birch_sapling", "jungle_sapling", "cocoa",
}

AIR = palette.AIR_PASSTHROUGH


def to_plain(value):
    """NBT -> JSON-compatible python (used for item components / loot manifest)."""
    t = type(value)
    if t in (nbt.Byte, nbt.Short, nbt.Int, nbt.Long):
        return int(value)
    if t in (nbt.Float, nbt.Double):
        return float(value)
    if t is str:
        return value
    if t is nbt.ByteArray:
        return list(value)
    if t in (nbt.IntArray, nbt.LongArray):
        return list(value)
    if t is nbt.TagList:
        return [to_plain(v) for v in value]
    if t is nbt.Compound:
        return {k: to_plain(v) for k, v in value.items()}
    raise TypeError(f"unexpected NBT type {t!r}")


def item_to_json(item: nbt.Compound) -> dict:
    """Vanilla ItemStack JSON-codec shape: P5-W9 can decode with ItemStack.CODEC."""
    out = {"id": item["id"], "count": int(item.get("count", nbt.Int(1)))}
    comps = item.get("components")
    if comps:
        out["components"] = to_plain(comps)
    return out


class WorldBaker:
    def __init__(self, cfg: dict, wid: str, in_dir: str, out_dir: str):
        self.cfg = cfg
        self.wid = wid
        self.in_dir = in_dir
        self.out_dir = out_dir
        self.radius = int(cfg["trimChunkRadius"])
        self.keep_entity_ids = set(cfg["keepEntityIds"])
        self.expected_dv = int(cfg["targetDataVersion"])

        # stats / outputs
        self.stats = collections.Counter()
        self.block_counts: collections.Counter[str] = collections.Counter()  # vanilla id -> blocks
        self.prop_values: dict[str, dict[str, set]] = {}  # vanilla id -> prop -> values
        self.be_hist: collections.Counter[str] = collections.Counter()
        self.entity_kept: collections.Counter[str] = collections.Counter()
        self.entity_dropped: collections.Counter[str] = collections.Counter()
        self.loot: list[dict] = []
        self.nonair_dropped_sections: list[dict] = []
        self.kept_chunks: dict[tuple[int, int], bytes] = {}
        self.spawn_column_secs: dict[int, tuple[list[str], list[int] | None]] = {}
        self.spawn = (0, 0, 0)
        self.spawn_angle = 0.0

    # ---------------- level.dat ----------------

    def read_level_dat(self) -> None:
        _, root = nbt.load_gzipped(os.path.join(self.in_dir, "level.dat"))
        data = root["Data"]
        if int(data["DataVersion"]) != self.expected_dv:
            raise SystemExit(f"{self.wid}: level.dat DataVersion "
                             f"{int(data['DataVersion'])} != {self.expected_dv}")
        self.spawn = (int(data["SpawnX"]), int(data["SpawnY"]), int(data["SpawnZ"]))
        self.spawn_angle = float(data.get("SpawnAngle", nbt.Float(0.0)))
        self.level_root = root

    def write_level_dat(self, spawn: tuple[int, int, int]) -> None:
        data = self.level_root["Data"]
        data["SpawnX"] = nbt.Int(spawn[0])
        data["SpawnY"] = nbt.Int(spawn[1])
        data["SpawnZ"] = nbt.Int(spawn[2])
        data["SpawnAngle"] = nbt.Float(self.spawn_angle)
        data["allowCommands"] = nbt.Byte(1)  # dev-client convenience; W9 ignores level.dat
        data.pop("Player", None)
        nbt.save_gzipped(os.path.join(self.out_dir, "level.dat"), self.level_root, "")

    # ---------------- sections ----------------

    def _record_stats(self, palette_list, counts) -> None:
        for entry, n in zip(palette_list, counts):
            if n == 0:
                continue
            name = entry["Name"]
            self.block_counts[name] += n
            props = entry.get("Properties")
            if props:
                slot = self.prop_values.setdefault(name, {})
                for k, v in props.items():
                    slot.setdefault(k, set()).add(v)

    def _bake_section(self, sec: nbt.Compound, is_spawn_chunk: bool):
        """Returns (new_section, nonair_count) or (None, 0) when dropped."""
        y = int(sec["Y"])
        bs = sec.get("block_states")
        if y < 0 or y > 15:
            # outside the xbox_classic dimension range (min_y 0, height 256)
            if bs is not None:
                pal = bs["palette"]
                if not all(e["Name"] in AIR for e in pal):
                    counts = (palette.count_indices(bs.get("data", []), len(pal))
                              if "data" in bs else [4096])
                    dropped = {e["Name"]: n for e, n in zip(pal, counts)
                               if n and e["Name"] not in AIR}
                    if dropped:
                        self.nonair_dropped_sections.append({"sectionY": y, "blocks": dropped})
                        self.stats["sectionsDroppedNonAir"] += 1
                        return None, 0
            self.stats["sectionsDroppedAirOutsideRange"] += 1
            return None, 0

        if bs is None:
            raise SystemExit(f"{self.wid}: full chunk section Y={y} without block_states")
        pal = bs["palette"]
        data = bs.get("data")
        counts = palette.count_indices(data, len(pal)) if data is not None else [4096]
        self._record_stats(pal, counts)
        nonair = sum(n for e, n in zip(pal, counts) if e["Name"] not in AIR)

        # remap palette
        new_entries = []
        for entry in pal:
            new_entry, info = palette.map_palette_entry(entry)
            if info["fluid"]:
                self.stats["fluidPaletteEntriesNormalized"] += 1
            if info["waterlogged_flip"]:
                self.stats["waterloggedForcedFalse"] += 1
            new_entries.append(new_entry)

        # dedup (fluid normalization can collapse water[level=*] entries)
        keyed = [(e["Name"], tuple(sorted(e.get("Properties", {}).items())))
                 for e in new_entries]
        unique: dict[tuple, int] = {}
        order: list[nbt.Compound] = []
        idx_map: list[int] = []
        for key, entry in zip(keyed, new_entries):
            if key not in unique:
                unique[key] = len(order)
                order.append(entry)
            idx_map.append(unique[key])

        new_bs = nbt.Compound()
        if len(order) == len(new_entries):
            new_bs["palette"] = nbt.TagList(nbt.TAG_COMPOUND, new_entries)
            if data is not None:
                new_bs["data"] = data  # indices unchanged
            indices_for_spawn = (palette.decode_indices(data, len(pal))
                                 if (is_spawn_chunk and data is not None) else None)
        else:
            self.stats["sectionsRepacked"] += 1
            old_indices = (palette.decode_indices(data, len(pal))
                           if data is not None else [0] * 4096)
            new_indices = [idx_map[i] for i in old_indices]
            new_bs["palette"] = nbt.TagList(nbt.TAG_COMPOUND, order)
            if len(order) > 1:
                new_bs["data"] = palette.encode_indices(new_indices, len(order))
            indices_for_spawn = new_indices if is_spawn_chunk else None

        new_sec = nbt.Compound()
        new_sec["Y"] = nbt.Byte(y)
        new_sec["block_states"] = new_bs
        if "biomes" in sec:
            new_sec["biomes"] = sec["biomes"]

        if is_spawn_chunk:
            names = [e["Name"] for e in new_bs["palette"]]
            self.spawn_column_secs[y] = (names, indices_for_spawn)
        return new_sec, nonair

    # ---------------- chunks ----------------

    def _extract_loot(self, be: nbt.Compound) -> None:
        be_id = be.get("id", "?")
        pos = [int(be.get("x", nbt.Int(0))), int(be.get("y", nbt.Int(0))),
               int(be.get("z", nbt.Int(0)))]
        items = []
        if "Items" in be:
            for item in sorted(be["Items"], key=lambda i: int(i.get("Slot", nbt.Byte(0)))):
                items.append(item_to_json(item))
        if "RecordItem" in be:  # jukebox: the disc is loot too
            items.append(item_to_json(be["RecordItem"]))
        if items:
            self.loot.append({"pos": pos, "block": be_id, "items": items})
            self.stats["lootContainers"] += 1

    # Statuses at or after "initialize_light": every terrain-generation step is
    # complete. Old console conversions typically surface as "minecraft:spawn"
    # (pre-1.13 `TerrainPopulated=1, LightPopulated=0` -> DFU `mobs_spawned` ->
    # renamed `spawn`); the bake strips light anyway (relit at load), so these
    # chunks are baked as full - no runtime generation in the void dimension.
    CONTENT_COMPLETE_STATUSES = frozenset({
        "minecraft:initialize_light", "minecraft:light", "minecraft:spawn",
        "minecraft:full",
    })

    def bake_chunk(self, cx: int, cz: int, raw: bytes, center: tuple[int, int]) -> None:
        _, root = nbt.loads(raw)
        self.stats["chunksIn"] += 1
        dv = int(root.get("DataVersion", -1))
        if dv != self.expected_dv:
            raise SystemExit(f"{self.wid}: chunk ({cx},{cz}) DataVersion {dv} != {self.expected_dv}")
        if root.get("xPos") is not None and (int(root["xPos"]) != cx or int(root["zPos"]) != cz):
            raise SystemExit(f"{self.wid}: chunk coord mismatch at region slot ({cx},{cz}): "
                             f"NBT says ({int(root['xPos'])},{int(root['zPos'])})")
        status = root.get("Status", "")
        if status not in self.CONTENT_COMPLETE_STATUSES:
            self.stats["chunksDroppedIncompleteStatus"] += 1
            return
        if status != "minecraft:full":
            self.stats["statusForcedFull"] += 1

        # Purge box: centered on the world's chunk footprint (the console worlds
        # are exactly 864x864 blocks = 54x54 chunks; radius 27 covers precisely
        # that). Centering on the spawn instead (plan letter) would slice built
        # map edges off TU12, whose spawn is ~6 chunks off-center - the plan's
        # stated intent is "drop empty OUTER chunks", which the all-air drop
        # below plus this footprint cap implement. Deviation documented.
        dist = max(abs(cx - center[0]), abs(cz - center[1]))
        inhabited = int(root.get("InhabitedTime", nbt.Long(0)))
        if inhabited == 0 and dist > self.radius:
            self.stats["chunksPurgedOutsideRadius"] += 1
            return

        is_spawn_chunk = (cx == self.spawn[0] >> 4 and cz == self.spawn[2] >> 4)
        new_sections = nbt.TagList(nbt.TAG_COMPOUND)
        nonair_total = 0
        for sec in root.get("sections", nbt.TagList()):
            new_sec, nonair = self._bake_section(sec, is_spawn_chunk)
            if new_sec is not None:
                new_sections.append(new_sec)
                nonair_total += nonair

        if nonair_total == 0:
            self.stats["chunksDroppedAllAir"] += 1
            if is_spawn_chunk:
                raise SystemExit(f"{self.wid}: spawn chunk is all air?!")
            return

        for be in root.get("block_entities", nbt.TagList()):
            self.be_hist[be.get("id", "?")] += 1
            self._extract_loot(be)

        out = nbt.Compound()
        out["DataVersion"] = nbt.Int(self.expected_dv)
        out["xPos"] = nbt.Int(cx)
        out["yPos"] = nbt.Int(0)  # sections are 0..15 after the trim
        out["zPos"] = nbt.Int(cz)
        out["Status"] = "minecraft:full"
        out["LastUpdate"] = root.get("LastUpdate", nbt.Long(0))
        out["InhabitedTime"] = root.get("InhabitedTime", nbt.Long(0))
        out["sections"] = new_sections
        out["block_entities"] = nbt.TagList(nbt.TAG_COMPOUND)
        out["block_ticks"] = nbt.TagList(nbt.TAG_COMPOUND)
        out["fluid_ticks"] = nbt.TagList(nbt.TAG_COMPOUND)
        # intentionally dropped: Heightmaps, isLightOn, light arrays, structures,
        # PostProcessing, UpgradeData, blending_data, below_zero_retrogen
        self.kept_chunks[(cx, cz)] = nbt.dumps(out)
        self.stats["chunksKept"] += 1

    # ---------------- entities ----------------

    def bake_entities(self) -> dict[tuple[int, int], bytes]:
        out: dict[tuple[int, int], bytes] = {}
        ent_dir = os.path.join(self.in_dir, "entities")
        if not os.path.isdir(ent_dir):
            return out
        for cx, cz, raw in region.iter_world_chunks(ent_dir):
            _, root = nbt.loads(raw)
            pos = root.get("Position")
            if pos is not None:
                cx, cz = int(pos[0]), int(pos[1])
            if (cx, cz) not in self.kept_chunks:
                for e in root.get("Entities", nbt.TagList()):
                    self.entity_dropped[e.get("id", "?")] += 1
                continue
            kept = nbt.TagList(nbt.TAG_COMPOUND)
            for e in root.get("Entities", nbt.TagList()):
                eid = e.get("id", "?")
                if eid in self.keep_entity_ids:
                    kept.append(e)
                    self.entity_kept[eid] += 1
                else:
                    self.entity_dropped[eid] += 1
            if not kept:
                continue
            src_dv = int(root.get("DataVersion", nbt.Int(self.expected_dv)))
            if src_dv > self.expected_dv:
                raise SystemExit(f"{self.wid}: entity chunk ({cx},{cz}) DataVersion "
                                 f"{src_dv} is NEWER than target {self.expected_dv}")
            self.stats[f"entityChunkDataVersion.{src_dv}"] += 1
            ent = nbt.Compound()
            # Preserve the SOURCE DataVersion: --forceUpgrade only rewrites entity
            # chunks DFU changed, and the game DFUs entity chunks at load anyway.
            # Stamping the target version on unchanged NBT would skip those fixes.
            ent["DataVersion"] = nbt.Int(src_dv)
            ent["Position"] = nbt.IntArray([cx, cz])
            ent["Entities"] = kept
            out[(cx, cz)] = nbt.dumps(ent)
        return out

    # ---------------- spawn verification ----------------

    def _block_at(self, x: int, y: int, z: int) -> str:
        if not (0 <= y <= 255):
            return "minecraft:air"
        sec = self.spawn_column_secs.get(y >> 4)
        if sec is None:
            return "minecraft:air"
        names, indices = sec
        if indices is None:
            return names[0]
        return names[indices[((y & 15) << 8) | ((z & 15) << 4) | (x & 15)]]

    @staticmethod
    def _vanilla_path(name: str) -> str:
        path = name.split(":", 1)[1]
        if path.startswith("classic_"):
            path = path[len("classic_"):]
        return path

    @classmethod
    def _passable(cls, name: str) -> bool:
        # air or a non-colliding deco block (flowers, grass, ...) is fine for feet/head
        return name in AIR or cls._vanilla_path(name) in NONSOLID_FLOOR_PATHS

    @classmethod
    def _solid_floor(cls, name: str) -> bool:
        if name in AIR:
            return False
        return cls._vanilla_path(name) not in NONSOLID_FLOOR_PATHS

    def verify_spawn(self) -> tuple[tuple[int, int, int], dict]:
        x, y, z = self.spawn
        col = {yy: self._block_at(x, yy, z) for yy in range(max(0, y - 2), min(256, y + 3))}
        ok = (self._passable(self._block_at(x, y, z))
              and self._passable(self._block_at(x, y + 1, z))
              and self._solid_floor(self._block_at(x, y - 1, z)))
        detail = {"recordedSpawn": [x, y, z], "column": {str(k): v for k, v in sorted(col.items())},
                  "recordedSpawnOk": ok, "adjusted": False}
        if ok:
            return (x, y, z), detail
        candidates = []
        for yy in range(1, 255):
            if (self._passable(self._block_at(x, yy, z))
                    and self._passable(self._block_at(x, yy + 1, z))
                    and self._solid_floor(self._block_at(x, yy - 1, z))):
                candidates.append(yy)
        if not candidates:
            raise SystemExit(f"{self.wid}: no standable spawn Y found in column ({x},{z})")
        best = min(candidates, key=lambda yy: (abs(yy - y), yy))
        detail["adjusted"] = True
        detail["adjustedSpawn"] = [x, best, z]
        self.stats["spawnAdjusted"] += 1
        return (x, best, z), detail

    # ---------------- driver ----------------

    def run(self) -> dict:
        self.read_level_dat()
        # pass 1: world chunk footprint -> purge-box center (see bake_chunk note)
        chunks = list(region.iter_world_chunks(os.path.join(self.in_dir, "region")))
        if not chunks:
            raise SystemExit(f"{self.wid}: no chunks in input")
        xs = [c[0] for c in chunks]
        zs = [c[1] for c in chunks]
        center = ((min(xs) + max(xs)) // 2, (min(zs) + max(zs)) // 2)
        # pass 2: trim + bake
        for cx, cz, raw in chunks:
            self.bake_chunk(cx, cz, raw, center)
        if not self.kept_chunks:
            raise SystemExit(f"{self.wid}: no chunks survived the trim - config wrong?")

        spawn, spawn_detail = self.verify_spawn()
        ent_chunks = self.bake_entities()

        # write world
        if os.path.exists(self.out_dir):
            shutil.rmtree(self.out_dir)
        os.makedirs(os.path.join(self.out_dir, "region"))
        by_region: dict[tuple[int, int], dict] = collections.defaultdict(dict)
        for (cx, cz), raw in self.kept_chunks.items():
            by_region[(cx >> 5, cz >> 5)][(cx & 31, cz & 31)] = raw
        for (rx, rz), chunk_map in sorted(by_region.items()):
            region.write_region(os.path.join(self.out_dir, "region",
                                             region.region_file_name(rx, rz)), chunk_map)
        if ent_chunks:
            os.makedirs(os.path.join(self.out_dir, "entities"))
            by_region.clear()
            for (cx, cz), raw in ent_chunks.items():
                by_region[(cx >> 5, cz >> 5)][(cx & 31, cz & 31)] = raw
            for (rx, rz), chunk_map in sorted(by_region.items()):
                region.write_region(os.path.join(self.out_dir, "entities",
                                                 region.region_file_name(rx, rz)), chunk_map)
        self.write_level_dat(spawn)

        xs = [c[0] for c in self.kept_chunks]
        zs = [c[1] for c in self.kept_chunks]
        bounds = {
            "chunkMin": [min(xs), min(zs)], "chunkMax": [max(xs), max(zs)],
            "blockMin": [min(xs) * 16, 0, min(zs) * 16],
            "blockMax": [max(xs) * 16 + 15, 255, max(zs) * 16 + 15],
        }
        inventory = {}
        for vid, n in sorted(self.block_counts.items()):
            cid = palette.classic_id_for(vid)
            inventory[vid] = {"classicId": cid if cid else vid, "count": n}

        report = {
            "worldId": self.wid,
            "dataVersion": self.expected_dv,
            "spawn": list(spawn),
            "spawnYaw": self.spawn_angle,
            "spawnCheck": spawn_detail,
            "bounds": bounds,
            "stats": dict(sorted(self.stats.items())),
            "blockEntityHistogram": dict(sorted(self.be_hist.items())),
            "entitiesKept": dict(sorted(self.entity_kept.items())),
            "entitiesDropped": dict(sorted(self.entity_dropped.items())),
            "nonAirSectionsDroppedOutsideRange": self.nonair_dropped_sections,
            "blockInventory": inventory,
        }
        loot_doc = {
            "worldId": self.wid,
            "dataVersion": self.expected_dv,
            "note": "items use the vanilla ItemStack JSON codec shape "
                    "({id,count,components}); ids are the ORIGINAL vanilla ids - "
                    "P5-W9 decides at spill time what stays vanilla (music discs) "
                    "vs maps to classic items (SS2.14 chest loot).",
            "containers": sorted(self.loot, key=lambda c: (c["pos"][0], c["pos"][1],
                                                           c["pos"][2])),
        }
        prop_report = {
            vid: {k: sorted(v) for k, v in sorted(props.items())}
            for vid, props in sorted(self.prop_values.items())
        }
        return {"report": report, "loot": loot_doc, "properties": prop_report,
                "blockCounts": dict(self.block_counts)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--worlds", default=None, help="comma-separated subset of world ids")
    args = ap.parse_args()

    cfg = json.load(open(CFG_PATH))
    world_ids = list(cfg["worlds"])
    if args.worlds:
        world_ids = [w for w in args.worlds.split(",") if w]

    work = cfg["workDir"]
    rep_dir = os.path.join(work, "reports")
    os.makedirs(rep_dir, exist_ok=True)

    for wid in world_ids:
        print(f"\n=== bake {wid} ===")
        in_dir = os.path.join(work, "upgraded", wid)
        out_dir = os.path.join(work, "baked", wid)
        if not os.path.isdir(in_dir):
            raise SystemExit(f"{in_dir} missing - run upgrade.py first")
        baker = WorldBaker(cfg, wid, in_dir, out_dir)
        result = baker.run()

        with open(os.path.join(rep_dir, f"{wid}_bake.json"), "w") as f:
            json.dump(result["report"], f, indent=2, sort_keys=False)
            f.write("\n")
        with open(os.path.join(rep_dir, f"{wid}_loot.json"), "w") as f:
            json.dump(result["loot"], f, indent=2, sort_keys=False, ensure_ascii=False)
            f.write("\n")
        with open(os.path.join(rep_dir, f"{wid}_palette.json"), "w") as f:
            json.dump({"blockCounts": dict(sorted(result["blockCounts"].items())),
                       "properties": result["properties"]}, f, indent=2)
            f.write("\n")

        s = result["report"]["stats"]
        print(f"  chunks: in={s.get('chunksIn', 0)} kept={s.get('chunksKept', 0)} "
              f"purged={s.get('chunksPurgedOutsideRadius', 0)} "
              f"allAir={s.get('chunksDroppedAllAir', 0)} "
              f"nonFull={s.get('chunksDroppedNonFull', 0)}")
        print(f"  spawn: {result['report']['spawn']} "
              f"(adjusted={result['report']['spawnCheck']['adjusted']})")
        print(f"  loot containers: {s.get('lootContainers', 0)}; "
              f"distinct vanilla block ids: {len(result['blockCounts'])}")
        if result["report"]["nonAirSectionsDroppedOutsideRange"]:
            print("  !! non-air sections outside Y 0..255 were dropped - REVIEW REPORT")

    print(f"\nbake reports written to {rep_dir}")


if __name__ == "__main__":
    main()
