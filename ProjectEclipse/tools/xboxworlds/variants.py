#!/usr/bin/env python3
"""C17 step 8 (+V5 P-MISC) — derive the TU19 / TU31 / TU69 / TU75 tutorial-world
VARIANTS from the committed TU12 payload (no network, no server jar — pure
region-file surgery).

WHY derived, not fetched: theminecraftarchitect.com hosts no "JE Latest" zips
for TU19/TU31/TU75 (probed 404, TU69 was never archived there either), and more
full 54x54-chunk bakes (~6.5 MB each) would blow the 30 MB orchestrator size
gate. The user-visible promise is "more TU worlds with era-correct palette
differences" — so each variant reuses the TU12 tutorial LAYOUT (it is the same
4J map across those title updates), trimmed to the inner 36x36 chunks (TU69:
30x30 — the size gate had ~2.3 MB of headroom left when it was added, so the
newest variant takes the tighter trim), with a deterministic era-aging palette
pass:

  tu19 (2014) — lightly weathered: some cobble mossed over, first cracked
                stone bricks (the map as it looked after two years of TUs).
  tu31 (2015) — the renovation era: spruce-plank rebuilds, stone-brick
                patches in the cobble, ferns creeping into the grass.
  tu69 (2018) — the aquatic-preview twilight: deep moss and ferns, gravel
                creeping into the beaches (the Update-Aquatic era read),
                poppies displacing the dandelions.
  tu75 (2019) — the console sunset: heavily mossed + overgrown (the last
                Xbox-360 title update; the world nobody resets anymore).

Every remap target is PROPERTYLESS → PROPERTYLESS and already part of the
frozen 156-id classic palette contract (docs/plans_v3/xbox_palette.json), so
P5-W8's registered classic block set covers the variants with zero additions.

Inputs (committed, sha-stable):  src/main/resources/assets/eclipse/xboxworlds/tu12.zip
                                 src/main/resources/data/eclipse/xboxworlds/tu12_loot.json
Outputs (deterministic bytes):   .../xboxworlds/{tu19,tu31,tu75}.zip
                                 .../xboxworlds/{tu19,tu31,tu75}_loot.json
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
# Inner 36x36-chunk box around the TU12 footprint center (full map is [-27..26];
# spawn chunk (6,-7) stays well inside). 1296 of 2916 chunks ≈ 2.8 MB per zip.
CHUNK_MIN, CHUNK_MAX = -18, 17
ZIP_DATE = (2026, 1, 1, 0, 0, 0)  # keep package.py's deterministic-zip contract

# (source classic id, target classic id, per-block probability) — all propertyless.
# Optional per-variant "box": (chunkMin, chunkMax) trim override — MUST contain the
# TU12 spawn chunk (6, -7). Default is the shared 36x36 box above.
VARIANTS = {
    "tu19": {
        "year": 2014,
        "displayName": {"en_us": "Tutorial World (TU19) — 2014",
                        "de_de": "Tutorial-Welt (TU19) — 2014"},
        "remap": [
            ("eclipse:classic_cobblestone", "eclipse:classic_mossy_cobblestone", 0.18),
            ("eclipse:classic_stone_bricks", "eclipse:classic_cracked_stone_bricks", 0.10),
        ],
    },
    "tu31": {
        "year": 2015,
        "displayName": {"en_us": "Tutorial World (TU31) — 2015",
                        "de_de": "Tutorial-Welt (TU31) — 2015"},
        "remap": [
            ("eclipse:classic_oak_planks", "eclipse:classic_spruce_planks", 0.30),
            ("eclipse:classic_cobblestone", "eclipse:classic_stone_bricks", 0.10),
            ("eclipse:classic_short_grass", "eclipse:classic_fern", 0.25),
        ],
    },
    # V5 P-MISC: the explicitly requested TU69 (~2018, the aquatic-preview console
    # twilight — between TU31's renovation and TU75's sunset). Smaller 30x30 trim box:
    # when TU69 was added the 30 MB gate had only ~2.3 MB of headroom left.
    "tu69": {
        "year": 2018,
        "displayName": {"en_us": "Tutorial World (TU69) — 2018",
                        "de_de": "Tutorial-Welt (TU69) — 2018"},
        "box": (-15, 14),
        "remap": [
            ("eclipse:classic_cobblestone", "eclipse:classic_mossy_cobblestone", 0.34),
            ("eclipse:classic_stone_bricks", "eclipse:classic_mossy_stone_bricks", 0.20),
            ("eclipse:classic_short_grass", "eclipse:classic_fern", 0.34),
            ("eclipse:classic_sand", "eclipse:classic_gravel", 0.12),
            ("eclipse:classic_dandelion", "eclipse:classic_poppy", 0.30),
        ],
    },
    "tu75": {
        "year": 2019,
        "displayName": {"en_us": "Tutorial World (TU75) — 2019",
                        "de_de": "Tutorial-Welt (TU75) — 2019"},
        "remap": [
            ("eclipse:classic_cobblestone", "eclipse:classic_mossy_cobblestone", 0.40),
            ("eclipse:classic_stone_bricks", "eclipse:classic_mossy_stone_bricks", 0.25),
            ("eclipse:classic_short_grass", "eclipse:classic_fern", 0.40),
            ("eclipse:classic_dandelion", "eclipse:classic_poppy", 0.50),
        ],
    },
}


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def block_rng(variant: str, cx: int, cz: int, section_y: int) -> random.Random:
    """Deterministic per-section RNG (stable across runs and Python versions)."""
    seed = zlib.crc32(f"{variant}:{cx}:{cz}:{section_y}".encode())
    return random.Random(seed)


def load_source_zip() -> tuple[dict[tuple[int, int], bytes], dict[tuple[int, int], bytes], bytes]:
    """Returns (region_chunks, entity_chunks, level_dat_bytes) keyed by chunk coords."""
    path = os.path.join(ASSETS_DIR, f"{SOURCE_ID}.zip")
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


def in_box(cx: int, cz: int, box: tuple[int, int] = (CHUNK_MIN, CHUNK_MAX)) -> bool:
    return box[0] <= cx <= box[1] and box[0] <= cz <= box[1]


def remap_chunk(variant: str, cx: int, cz: int, raw: bytes, recipe, stats: dict) -> bytes:
    """Applies the per-block probabilistic era remap to every section; deterministic."""
    _, root = nbt.loads(raw)
    sources = {src: (dst, prob) for src, dst, prob in recipe}
    changed = False
    for sec in root.get("sections", []):
        bs = sec.get("block_states")
        if bs is None:
            continue
        pal = bs["palette"]
        names = [entry["Name"] for entry in pal]
        if not any(name in sources for name in names):
            continue
        rng = block_rng(variant, cx, cz, int(sec["Y"]))
        indices = palette.decode_indices(bs.get("data", []), len(pal))
        new_pal = list(pal)
        target_idx: dict[str, int] = {}

        def index_of(target: str) -> int:
            if target in target_idx:
                return target_idx[target]
            for i, entry in enumerate(new_pal):
                if entry["Name"] == target and "Properties" not in entry:
                    target_idx[target] = i
                    return i
            entry = nbt.Compound()
            entry["Name"] = target
            new_pal.append(entry)
            target_idx[target] = len(new_pal) - 1
            return target_idx[target]

        flip_from: dict[int, tuple[int, float]] = {}
        for i, entry in enumerate(pal):
            name = entry["Name"]
            if name in sources and "Properties" not in entry:
                dst, prob = sources[name]
                flip_from[i] = (index_of(dst), prob)
        if not flip_from:
            continue
        flipped = 0
        for pos in range(4096):
            hit = flip_from.get(indices[pos])
            if hit is not None and rng.random() < hit[1]:
                indices[pos] = hit[0]
                flipped += 1
        if flipped == 0:
            continue
        bs["palette"] = nbt.TagList(nbt.TAG_COMPOUND, new_pal)
        bs["data"] = palette.encode_indices(indices, len(new_pal))
        stats["blocksRemapped"] = stats.get("blocksRemapped", 0) + flipped
        changed = True
    if changed:
        stats["chunksTouched"] = stats.get("chunksTouched", 0) + 1
    return nbt.dumps(root)


def write_regions(out_dir: str, chunks: dict[tuple[int, int], bytes]) -> None:
    per_region: dict[tuple[int, int], dict[tuple[int, int], bytes]] = {}
    for (cx, cz), raw in chunks.items():
        rx, rz = cx >> 5, cz >> 5
        per_region.setdefault((rx, rz), {})[(cx & 31, cz & 31)] = raw
    os.makedirs(out_dir, exist_ok=True)
    for (rx, rz), chunk_map in sorted(per_region.items()):
        region.write_region(os.path.join(out_dir, region.region_file_name(rx, rz)), chunk_map)


def variant_level_dat(level_dat: bytes, variant: str) -> bytes:
    """Same level.dat with a variant LevelName (dev-client sugar; deterministic gzip)."""
    import gzip as gz
    name, root = nbt.loads(gz.decompress(level_dat))
    root["Data"]["LevelName"] = f"Eclipse Xbox {variant.upper()}"
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


def variant_loot(variant: str, source_loot: dict, box: tuple[int, int]) -> dict:
    """TU12 loot filtered to the trim box (frames are added later by frames.py)."""
    lo, hi = box[0] * 16, box[1] * 16 + 15
    containers = [c for c in source_loot["containers"]
                  if lo <= c["pos"][0] <= hi and lo <= c["pos"][2] <= hi]
    return {
        "worldId": variant,
        "dataVersion": source_loot["dataVersion"],
        "note": (f"derived from tu12_loot.json by tools/xboxworlds/variants.py (C17): "
                 f"containers inside the {box[1] - box[0] + 1}x"
                 f"{box[1] - box[0] + 1}-chunk trim box; "
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
        box = spec.get("box", (CHUNK_MIN, CHUNK_MAX))
        kept_regions = {key: remap_chunk(variant, key[0], key[1], raw, spec["remap"], stats)
                        for key, raw in sorted(regions.items()) if in_box(*key, box)}
        kept_entities = {key: raw for key, raw in sorted(entities.items()) if in_box(*key, box)}

        build = os.path.join("/tmp/xboxworlds", "variants", variant)
        if os.path.isdir(build):
            import shutil
            shutil.rmtree(build)
        write_regions(os.path.join(build, "region"), kept_regions)
        if kept_entities:
            write_regions(os.path.join(build, "entities"), kept_entities)
        with open(os.path.join(build, "level.dat"), "wb") as f:
            f.write(variant_level_dat(level_dat, variant))

        zip_path = os.path.join(ASSETS_DIR, f"{variant}.zip")
        deterministic_zip(build, zip_path)
        digest = sha256_of(zip_path)
        size = os.path.getsize(zip_path)
        total_bytes += size

        loot = variant_loot(variant, source_loot, box)
        with open(os.path.join(DATA_DIR, f"{variant}_loot.json"), "w") as f:
            json.dump(loot, f, indent=2, ensure_ascii=False)
            f.write("\n")

        manifest["worlds"].append({
            "worldId": variant,
            "displayName": spec["displayName"],
            "zip": f"assets/eclipse/xboxworlds/{variant}.zip",
            "zipEntries": tu12_entry["zipEntries"],
            "spawn": tu12_entry["spawn"],
            "spawnYaw": tu12_entry["spawnYaw"],
            "dataVersion": tu12_entry["dataVersion"],
            "sha256": digest,
            "sizeBytes": size,
            "chunkCount": len(kept_regions),
            "bounds": {
                "chunkMin": [box[0], box[0]],
                "chunkMax": [box[1], box[1]],
                "blockMin": [box[0] * 16, 0, box[0] * 16],
                "blockMax": [box[1] * 16 + 15, 255, box[1] * 16 + 15],
            },
            "lootManifest": f"data/eclipse/xboxworlds/{variant}_loot.json",
        })
        print(f"[{variant}] {zip_path}  {size} bytes  chunks={len(kept_regions)}  "
              f"remapped={stats.get('blocksRemapped', 0)} blocks in "
              f"{stats.get('chunksTouched', 0)} chunks  sha256={digest}")

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"\nTOTAL bundled worlds: {total_bytes} bytes ({total_bytes / 1048576:.2f} MiB) "
          f"for {len(manifest['worlds'])} worlds (30 MB gate: "
          f"{'WITHIN' if total_bytes <= 30 * 1024 * 1024 else 'OVER'})")
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    main()
