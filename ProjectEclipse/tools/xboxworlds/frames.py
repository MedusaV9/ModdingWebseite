#!/usr/bin/env python3
"""C17 step 3 — populate the optional `frames` section of every committed
`<id>_loot.json` (pos + facing + period-correct display item), consumed at
event start by `XboxWorldInstaller.decorate`.

Spots are found by scanning the COMMITTED world zips (the exact bytes the
installer extracts): an air cell with a solid full-cube classic wall behind
it, near spawn at sign height, away from chests and from the item frames /
paintings that survived the bake. `facing` is the direction the frame LOOKS
(away from its wall), matching `new ItemFrame(level, pos, facing)`.

The display set is a little era museum — items that existed on the Xbox-360
console era only (no post-era items; plan C17 "period-correct"). Block items
are classic-mapped at spawn time by the installer (same rule as chest loot);
music discs and tools stay vanilla (playable/usable souvenirs, §2.14).

Deterministic: same zips ⇒ same spots ⇒ byte-identical loot JSONs. Run after
`variants.py` (which rewrites the variant loot JSONs without frames).
"""

from __future__ import annotations

import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import nbt, palette, region  # noqa: E402

PROJECT_ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/assets/eclipse/xboxworlds")
DATA_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/data/eclipse/xboxworlds")

FRAMES_PER_WORLD = 8
# (Chebyshev radius, extra Y band) ladder, widened step by step until spots are
# found — the TUT2 per-era windows drop some spawns on open ground (tu31 arrives on
# a dune ~14 blocks above its outpost), and XboxEraWorldGameTests asserts every
# world keeps a non-empty frames section.
SEARCH_STEPS = ((32, 0), (64, 12), (96, 32))
MIN_SPACING = 4             # Manhattan distance between chosen frames
Y_BELOW, Y_ABOVE = 0, 3     # candidate band relative to spawn feet Y

# Era-museum display set, cycled per world in this order (all pre-2013 items;
# ids are ORIGINAL vanilla ids — blocks get classic-mapped by the installer).
DISPLAY_ITEMS = [
    "minecraft:iron_sword",
    "minecraft:diamond",
    "minecraft:clock",
    "minecraft:music_disc_cat",
    "minecraft:bread",
    "minecraft:compass",
    "minecraft:iron_pickaxe",
    "minecraft:golden_apple",
    "minecraft:bow",
    "minecraft:tnt",
]

# Solid full-cube classic ids a frame may hang on (subset of the frozen palette).
SOLID_WALLS = {f"eclipse:classic_{path}" for path in (
    "stone", "cobblestone", "mossy_cobblestone", "stone_bricks", "mossy_stone_bricks",
    "cracked_stone_bricks", "chiseled_stone_bricks", "bricks", "oak_planks",
    "spruce_planks", "birch_planks", "jungle_planks", "sandstone", "cut_sandstone",
    "chiseled_sandstone", "smooth_stone_slab", "bookshelf", "white_wool", "red_wool",
    "orange_wool", "yellow_wool", "lime_wool", "cyan_wool", "blue_wool", "gray_wool",
    "light_gray_wool", "black_wool", "quartz_block", "gold_block", "iron_block",
)}
AIR = set(palette.AIR_PASSTHROUGH)

# facing = away from the wall; wall sits at pos - facing_vector
FACINGS = {"south": (0, 0, -1), "north": (0, 0, 1), "east": (-1, 0, 0), "west": (1, 0, 0)}


class WorldBlocks:
    """Lazy block-id lookup over a committed world zip (region files only)."""

    def __init__(self, zip_path: str):
        self.chunks: dict[tuple[int, int], object] = {}
        self.entity_positions: list[tuple[float, float, float]] = []
        with zipfile.ZipFile(zip_path) as zf:
            for name in zf.namelist():
                if not name.endswith(".mca"):
                    continue
                tmp_dir = "/tmp/xboxworlds/frames_scan"
                os.makedirs(tmp_dir, exist_ok=True)
                tmp = os.path.join(tmp_dir, os.path.basename(name))
                with open(tmp, "wb") as f:
                    f.write(zf.read(name))
                reader = region.RegionReader(tmp)
                for lx, lz, raw in reader.chunks():
                    key = (reader.rx * 32 + lx, reader.rz * 32 + lz)
                    if name.startswith("region/"):
                        self.chunks[key] = raw
                    else:  # entities/ — collect surviving frame/painting positions
                        _, root = nbt.loads(raw)
                        for entity in root.get("Entities", []):
                            pos = entity.get("Pos")
                            if pos is not None:
                                self.entity_positions.append(
                                    (float(pos[0]), float(pos[1]), float(pos[2])))
                os.remove(tmp)
        self._decoded: dict[tuple[int, int], dict[int, tuple[list, list]]] = {}

    def block_id(self, x: int, y: int, z: int) -> str:
        key = (x >> 4, z >> 4)
        raw = self.chunks.get(key)
        if raw is None or not 0 <= y <= 255:
            return "minecraft:air"
        sections = self._decoded.get(key)
        if sections is None:
            sections = {}
            _, root = nbt.loads(raw)
            for sec in root.get("sections", []):
                bs = sec.get("block_states")
                if bs is not None:
                    pal = [entry["Name"] for entry in bs["palette"]]
                    idx = palette.decode_indices(bs.get("data", []), len(pal))
                    sections[int(sec["Y"])] = (pal, idx)
            self._decoded[key] = sections
        sec = sections.get(y >> 4)
        if sec is None:
            return "minecraft:air"
        pal, idx = sec
        return pal[idx[((y & 15) << 8) | ((z & 15) << 4) | (x & 15)]]


def find_spots(world: WorldBlocks, spawn: list[int]) -> list[dict]:
    for radius, extra_y in SEARCH_STEPS:
        spots = find_spots_within(world, spawn, radius, extra_y)
        if spots:
            return spots
    return []


def find_spots_within(world: WorldBlocks, spawn: list[int], radius: int,
                      extra_y: int = 0) -> list[dict]:
    sx, sy, sz = spawn
    candidates = []
    for y in range(sy - Y_BELOW - extra_y, sy + Y_ABOVE + extra_y + 1):
        for dz in range(-radius, radius + 1):
            for dx in range(-radius, radius + 1):
                x, z = sx + dx, sz + dz
                if world.block_id(x, y, z) not in AIR:
                    continue
                for facing, (wx, _, wz) in sorted(FACINGS.items()):
                    if world.block_id(x + wx, y, z + wz) in SOLID_WALLS:
                        # prefer sign height (spawn+1), then proximity to spawn
                        score = (abs(y - (sy + 1)), abs(dx) + abs(dz))
                        candidates.append((score, x, y, z, facing))
                        break
    candidates.sort()
    chosen: list[dict] = []
    for _, x, y, z, facing in candidates:
        if len(chosen) >= FRAMES_PER_WORLD:
            break
        if any(abs(x - c["pos"][0]) + abs(y - c["pos"][1]) + abs(z - c["pos"][2]) < MIN_SPACING
               for c in chosen):
            continue
        if any(abs(x - ex) < 2 and abs(y - ey) < 2 and abs(z - ez) < 2
               for ex, ey, ez in world.entity_positions):
            continue
        chosen.append({"pos": [x, y, z], "facing": facing})
    return chosen


def main() -> None:
    manifest = json.load(open(os.path.join(ASSETS_DIR, "manifest.json")))
    for entry in manifest["worlds"]:
        world_id = entry["worldId"]
        loot_path = os.path.join(DATA_DIR, f"{world_id}_loot.json")
        loot = json.load(open(loot_path))
        world = WorldBlocks(os.path.join(ASSETS_DIR, f"{world_id}.zip"))

        chest_positions = [tuple(c["pos"]) for c in loot["containers"]]
        spots = [s for s in find_spots(world, entry["spawn"])
                 if all(abs(s["pos"][0] - cx) + abs(s["pos"][1] - cy) + abs(s["pos"][2] - cz) > 1
                        for cx, cy, cz in chest_positions)]

        frames = []
        for i, spot in enumerate(spots):
            frames.append({
                "pos": spot["pos"],
                "facing": spot["facing"],
                "item": {"id": DISPLAY_ITEMS[i % len(DISPLAY_ITEMS)], "count": 1},
            })
        loot["frames"] = frames
        with open(loot_path, "w") as f:
            json.dump(loot, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"[{world_id}] {len(frames)} display frames -> {loot_path}")


if __name__ == "__main__":
    main()
