#!/usr/bin/env python3
"""P5-W7 step 4 - package baked worlds + produce all manifests (plan SS2.13.1 step 5).

Outputs:

  STAGING (binaries - the orchestrator gates the commit, plan W7 "commit gate"):
    /workspace/xbox_staging/<id>.zip            deterministic world payload
    /workspace/xbox_staging/manifest.json       copy of the mod-facing manifest
    /workspace/xbox_staging/<id>_manifest.json  per-world detail (spawn, bounds,
                                                full block-id inventory)
    /workspace/xbox_staging/reports/            bake/upgrade reports, sources

  REPOSITORY (small text files, committed by W7):
    src/main/resources/assets/eclipse/xboxworlds/manifest.json   (frozen path;
        after the gate the zips land NEXT TO it as <id>.zip)
    src/main/resources/data/eclipse/xboxworlds/<id>_loot.json    (chest loot)
    docs/plans_v3/xbox_palette.json                              (P5-W8 input)

Zip layout (frozen for P5-W9's XboxWorldInstaller): entries `region/r.X.Z.mca`,
optional `entities/r.X.Z.mca`, and `level.dat` at the archive ROOT - extract
straight into `<world>/dimensions/eclipse/xbox_<id>/`. level.dat is only there
so the baked world can also be opened directly in a dev client; the installer
may skip it. Zips are deterministic (sorted entries, fixed timestamps) so a
re-bake of identical input yields an identical sha256.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import palette  # noqa: E402

CFG_PATH = os.path.join(HERE, "worlds.json")
PROJECT_ROOT = os.path.dirname(os.path.dirname(HERE))  # .../ProjectEclipse
REPO_ASSETS_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/assets/eclipse/xboxworlds")
REPO_DATA_DIR = os.path.join(PROJECT_ROOT, "src/main/resources/data/eclipse/xboxworlds")
REPO_PALETTE = os.path.join(PROJECT_ROOT, "docs/plans_v3/xbox_palette.json")
ZIP_DATE = (2026, 1, 1, 0, 0, 0)  # fixed -> deterministic archives


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def deterministic_zip(src_dir: str, dest_zip: str) -> None:
    entries = []
    for root, dirs, files in os.walk(src_dir):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root, name)
            entries.append((os.path.relpath(full, src_dir).replace(os.sep, "/"), full))
    entries.sort()
    with zipfile.ZipFile(dest_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for arcname, full in entries:
            info = zipfile.ZipInfo(arcname, date_time=ZIP_DATE)
            info.external_attr = 0o644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as f:
                zf.writestr(info, f.read(), compresslevel=9)


def load_report(rep_dir: str, wid: str, kind: str) -> dict:
    path = os.path.join(rep_dir, f"{wid}_{kind}.json")
    if not os.path.exists(path):
        raise SystemExit(f"{path} missing - run bake.py first")
    return json.load(open(path))


def build_palette_report(cfg: dict, rep_dir: str, world_ids: list[str]) -> dict:
    per_world_counts: dict[str, dict[str, int]] = {}
    merged_props: dict[str, dict[str, set]] = {}
    for wid in world_ids:
        pal = load_report(rep_dir, wid, "palette")
        per_world_counts[wid] = pal["blockCounts"]
        for vid, props in pal["properties"].items():
            slot = merged_props.setdefault(vid, {})
            for k, values in props.items():
                slot.setdefault(k, set()).update(values)

    all_ids = sorted({vid for counts in per_world_counts.values() for vid in counts})
    entries = []
    for vid in all_ids:
        if vid in palette.AIR_PASSTHROUGH:
            continue
        cid = palette.classic_id_for(vid)
        props = merged_props.get(vid, {})
        if vid in palette.FLUID_SOLID:
            baked_props: dict[str, list[str]] = {}  # FLUID_SOLID entries are propertyless
        else:
            baked_props = {k: (["false"] if k == "waterlogged" else sorted(v))
                           for k, v in sorted(props.items())}
        per_world = {wid: per_world_counts[wid].get(vid, 0) for wid in world_ids
                     if per_world_counts[wid].get(vid, 0)}
        entries.append({
            "vanillaId": vid,
            "classicId": cid,
            "count": sum(per_world.values()),
            "perWorld": per_world,
            "properties": baked_props,
        })
    air_counts = {vid: {wid: per_world_counts[wid].get(vid, 0) for wid in world_ids
                        if per_world_counts[wid].get(vid, 0)}
                  for vid in sorted(palette.AIR_PASSTHROUGH)
                  if any(per_world_counts[w].get(vid, 0) for w in world_ids)}
    return {
        "_generated": "tools/xboxworlds/package.py (P5-W7) - do not hand-edit; "
                      "re-run the pipeline instead",
        "purpose": "authoritative block list for P5-W8 ClassicBlockList "
                   "(plan SS2.14 'Block list generation'); every entry below occurs "
                   "in the shipped baked region files with the listed classicId",
        "namingScheme": "minecraft:<path> -> eclipse:classic_<path>",
        "exceptions": {
            "airPassthrough": sorted(palette.AIR_PASSTHROUGH),
            "airCountsInBakedWorlds": air_counts,
            "fluidSolid": dict(palette.FLUID_SOLID),
            "fluidSolidNote": "water/lava palette entries are baked PROPERTYLESS "
                              "(level=* collapsed); register classic_water/"
                              "classic_lava without blockstate properties",
            "waterloggedNote": "the bake forces waterlogged=false everywhere; "
                               "waterloggable base classes are fine (default state "
                               "matches), no fluid exists in the baked worlds",
        },
        "propertiesNote": "'properties' lists every property VALUE present in the "
                          "baked palettes per id; classic blocks MUST declare "
                          "identical property sets (vanilla base classes provide "
                          "them, SS2.14 shape kinds)",
        "worlds": world_ids,
        "distinctBlockCount": len(entries),
        "entries": entries,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--worlds", default=None, help="comma-separated subset of world ids")
    ap.add_argument("--budget-mb", type=float, default=30.0,
                    help="orchestrator size gate for the sum of all zips (default 30)")
    args = ap.parse_args()

    cfg = json.load(open(CFG_PATH))
    world_ids = list(cfg["worlds"])
    if args.worlds:
        world_ids = [w for w in args.worlds.split(",") if w]

    work = cfg["workDir"]
    rep_dir = os.path.join(work, "reports")
    staging = cfg["stagingDir"]
    os.makedirs(staging, exist_ok=True)
    os.makedirs(os.path.join(staging, "reports"), exist_ok=True)
    os.makedirs(REPO_ASSETS_DIR, exist_ok=True)
    os.makedirs(REPO_DATA_DIR, exist_ok=True)

    manifest_worlds = []
    total_bytes = 0
    for wid in world_ids:
        baked = os.path.join(work, "baked", wid)
        if not os.path.isdir(baked):
            raise SystemExit(f"{baked} missing - run bake.py first")
        report = load_report(rep_dir, wid, "bake")
        loot = load_report(rep_dir, wid, "loot")

        zip_path = os.path.join(staging, f"{wid}.zip")
        deterministic_zip(baked, zip_path)
        digest = sha256_of(zip_path)
        size = os.path.getsize(zip_path)
        total_bytes += size
        print(f"[{wid}] {zip_path}  {size} bytes  sha256={digest}")

        entry = {
            "worldId": wid,
            "displayName": cfg["worlds"][wid]["displayName"],
            "zip": f"assets/eclipse/xboxworlds/{wid}.zip",
            "zipEntries": ["region/*.mca", "entities/*.mca (optional)", "level.dat (dev-client only)"],
            "spawn": report["spawn"],
            "spawnYaw": report["spawnYaw"],
            "dataVersion": report["dataVersion"],
            "sha256": digest,
            "sizeBytes": size,
            "chunkCount": report["stats"].get("chunksKept", 0),
            "bounds": report["bounds"],
            "lootManifest": f"data/eclipse/xboxworlds/{wid}_loot.json",
        }
        manifest_worlds.append(entry)

        # per-world detail manifest (staging): + full block-id inventory
        detail = dict(entry)
        detail["blockInventory"] = report["blockInventory"]
        detail["spawnCheck"] = report["spawnCheck"]
        detail["stats"] = report["stats"]
        with open(os.path.join(staging, f"{wid}_manifest.json"), "w") as f:
            json.dump(detail, f, indent=2, ensure_ascii=False)
            f.write("\n")

        # repo loot manifest
        with open(os.path.join(REPO_DATA_DIR, f"{wid}_loot.json"), "w") as f:
            json.dump(loot, f, indent=2, ensure_ascii=False)
            f.write("\n")

        # copy raw reports for the orchestrator
        for kind in ("bake", "loot", "palette"):
            shutil.copy2(os.path.join(rep_dir, f"{wid}_{kind}.json"),
                         os.path.join(staging, "reports", f"{wid}_{kind}.json"))

    manifest = {
        "formatVersion": 1,
        "_generated": "tools/xboxworlds/package.py (P5-W7) - do not hand-edit",
        "note": "world zips are staged in /workspace/xbox_staging until the "
                "orchestrator approves the size gate (plan SS3 P5-W7); after "
                "approval they are copied NEXT TO this manifest as <worldId>.zip",
        "worlds": manifest_worlds,
    }
    for dest in (os.path.join(REPO_ASSETS_DIR, "manifest.json"),
                 os.path.join(staging, "manifest.json")):
        with open(dest, "w") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")

    pal_report = build_palette_report(cfg, rep_dir, world_ids)
    with open(REPO_PALETTE, "w") as f:
        json.dump(pal_report, f, indent=2, ensure_ascii=False)
        f.write("\n")
    shutil.copy2(REPO_PALETTE, os.path.join(staging, "reports", "xbox_palette.json"))

    if os.path.exists(os.path.join(rep_dir, "upgrade_report.json")):
        shutil.copy2(os.path.join(rep_dir, "upgrade_report.json"),
                     os.path.join(staging, "reports", "upgrade_report.json"))

    budget = int(args.budget_mb * 1024 * 1024)
    print(f"\nTOTAL staged: {total_bytes} bytes ({total_bytes / 1048576:.2f} MiB) "
          f"for {len(world_ids)} world(s); budget {args.budget_mb} MB -> "
          f"{'WITHIN' if total_bytes <= budget else 'OVER'} budget")
    print(f"manifest: {os.path.join(REPO_ASSETS_DIR, 'manifest.json')}")
    print(f"palette report: {REPO_PALETTE}")
    print(f"staging: {staging}")


if __name__ == "__main__":
    main()
