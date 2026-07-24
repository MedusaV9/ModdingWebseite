#!/usr/bin/env python3
"""P5-W7 verification helper - NBT/region spot checks without any game runtime.

Sub-commands:
  level   <level.dat>                      dump level.dat (debug view)
  chunk   <regionDir> <cx> <cz>            dump one chunk's NBT (debug view)
  palette <regionDir> <cx> <cz> [secY]     dump section palettes of a chunk
  block   <worldDir> <x> <y> <z>           resolve the block id at a position
  dvhist  <regionDir>                      DataVersion histogram over all chunks
"""

from __future__ import annotations

import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import nbt, region, palette  # noqa: E402


def read_chunk(region_dir: str, cx: int, cz: int) -> nbt.Compound:
    rx, rz = cx >> 5, cz >> 5
    path = os.path.join(region_dir, region.region_file_name(rx, rz))
    if not os.path.exists(path):
        raise SystemExit(f"no region file {path}")
    for lx, lz, raw in region.RegionReader(path).chunks():
        if lx == (cx & 31) and lz == (cz & 31):
            _, root = nbt.loads(raw)
            return root
    raise SystemExit(f"chunk ({cx},{cz}) not present in {path}")


def cmd_level(args: list[str]) -> None:
    _, root = nbt.load_gzipped(args[0])
    print(json.dumps(nbt.to_debug(root), indent=2, ensure_ascii=False))


def cmd_chunk(args: list[str]) -> None:
    root = read_chunk(args[0], int(args[1]), int(args[2]))
    print(json.dumps(nbt.to_debug(root), indent=2, ensure_ascii=False))


def cmd_palette(args: list[str]) -> None:
    root = read_chunk(args[0], int(args[1]), int(args[2]))
    want = int(args[3]) if len(args) > 3 else None
    for sec in root.get("sections", []):
        y = int(sec["Y"])
        if want is not None and y != want:
            continue
        bs = sec.get("block_states")
        if bs is None:
            print(f"section Y={y}: <no block_states>")
            continue
        pal = bs["palette"]
        counts = (palette.count_indices(bs["data"], len(pal))
                  if "data" in bs else [4096])
        print(f"section Y={y}: {len(pal)} palette entries "
              f"({'packed' if 'data' in bs else 'single'})")
        for entry, n in zip(pal, counts):
            props = entry.get("Properties")
            ps = "[" + ",".join(f"{k}={v}" for k, v in props.items()) + "]" if props else ""
            print(f"    {n:5d} x {entry['Name']}{ps}")


def cmd_block(args: list[str]) -> None:
    world_dir, x, y, z = args[0], int(args[1]), int(args[2]), int(args[3])
    root = read_chunk(os.path.join(world_dir, "region"), x >> 4, z >> 4)
    for sec in root.get("sections", []):
        if int(sec["Y"]) != y >> 4:
            continue
        bs = sec.get("block_states")
        pal = bs["palette"]
        if "data" not in bs:
            entry = pal[0]
        else:
            idx = palette.decode_indices(bs["data"], len(pal))[
                ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)]
            entry = pal[idx]
        props = entry.get("Properties")
        ps = "[" + ",".join(f"{k}={v}" for k, v in props.items()) + "]" if props else ""
        print(f"({x},{y},{z}) = {entry['Name']}{ps}")
        return
    print(f"({x},{y},{z}) = <section absent -> air/void>")


def cmd_dvhist(args: list[str]) -> None:
    hist: collections.Counter[int] = collections.Counter()
    for _cx, _cz, raw in region.iter_world_chunks(args[0]):
        _, root = nbt.loads(raw)
        hist[int(root.get("DataVersion", -1))] += 1
    total = sum(hist.values())
    print(f"{total} chunks: " + ", ".join(f"DataVersion {k}: {v}"
                                          for k, v in sorted(hist.items())))


def main() -> None:
    cmds = {"level": cmd_level, "chunk": cmd_chunk, "palette": cmd_palette,
            "block": cmd_block, "dvhist": cmd_dvhist}
    if len(sys.argv) < 2 or sys.argv[1] not in cmds:
        print(__doc__)
        raise SystemExit(2)
    cmds[sys.argv[1]](sys.argv[2:])


if __name__ == "__main__":
    main()
