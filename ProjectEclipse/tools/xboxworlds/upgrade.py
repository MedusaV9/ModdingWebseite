#!/usr/bin/env python3
"""P5-W7 step 2 - upgrade each fetched world to 1.21.1 (DataVersion 3955).

Verified one-hop path (plan SS2.13.1 step 2, risk R6): the TMA "JE Latest"
conversions are DataVersion 3839 (1.20.6); the official vanilla 1.21.1
dedicated server upgrades them in a single DFU hop:

    java -jar server-1.21.1.jar --forceUpgrade --nogui

The server has no "upgrade only" mode - after upgrading it finishes booting,
so this script watches stdout for the "Done (...)" line and immediately issues
`stop` on stdin. The world copy the server ran on becomes the upgrade output.

EULA: the script writes `eula=true`; running it means YOU accept the Minecraft
EULA (https://aka.ms/MinecraftEULA). The server jar is a local build tool only
and is never redistributed.

Before the run, each world copy is reduced to a whitelist (level.dat, region/,
entities/): DIM-1 / DIM1 are out of scope (overworld only, SS2.13.1 step 3) and
poi/ is derived data that the bake invalidates anyway (rebuilt lazily by the
game). Less input = faster upgrade.

Output per world: <workDir>/upgraded/<id>/ + a DataVersion verification report.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mclib import nbt, region  # noqa: E402

CFG_PATH = os.path.join(HERE, "worlds.json")
WORLD_WHITELIST = ("level.dat", "region", "entities")
SERVER_PORT = 25599
DONE_MARKERS = ("Done (",)
FATAL_MARKERS = ("FAILED TO BIND TO PORT", "You need to agree to the EULA",
                 "Failed to load properties")
UPGRADE_TIMEOUT_S = 1800


def find_world_root(tree: str) -> str:
    """The TMA zips may nest the world one folder deep - locate level.dat."""
    if os.path.exists(os.path.join(tree, "level.dat")):
        return tree
    candidates = [os.path.join(tree, d) for d in sorted(os.listdir(tree))
                  if os.path.isdir(os.path.join(tree, d))]
    hits = [c for c in candidates if os.path.exists(os.path.join(c, "level.dat"))]
    if len(hits) != 1:
        raise SystemExit(f"could not locate a single world root under {tree}: {hits}")
    return hits[0]


def extract_source(zip_path: str, dest: str) -> str:
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            # zip-slip guard
            target = os.path.realpath(os.path.join(dest, info.filename))
            if not target.startswith(os.path.realpath(dest) + os.sep) \
                    and target != os.path.realpath(dest):
                raise SystemExit(f"zip entry escapes destination: {info.filename}")
        zf.extractall(dest)
    return find_world_root(dest)


def stage_pruned_world(src_root: str, dest: str) -> None:
    """Copy only level.dat + region/ + entities/ (prune dims, poi, player junk)."""
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in WORLD_WHITELIST:
        src = os.path.join(src_root, name)
        if not os.path.exists(src):
            if name == "level.dat":
                raise SystemExit(f"{src_root}: no level.dat")
            print(f"  note: source has no {name}/ (ok)")
            continue
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(dest, name))
        else:
            shutil.copy2(src, os.path.join(dest, name))


def level_dat_data_version(path: str) -> int:
    _, root = nbt.load_gzipped(path)
    return int(root["Data"]["DataVersion"])


def run_force_upgrade(server_dir: str, server_jar: str, level_name: str) -> None:
    os.makedirs(server_dir, exist_ok=True)
    with open(os.path.join(server_dir, "eula.txt"), "w") as f:
        f.write("# accepted by the operator running tools/xboxworlds/upgrade.py\n")
        f.write("eula=true\n")
    with open(os.path.join(server_dir, "server.properties"), "w") as f:
        f.write(
            "# transient config for --forceUpgrade runs (P5-W7 pipeline)\n"
            f"level-name={level_name}\n"
            f"server-port={SERVER_PORT}\n"
            "online-mode=false\n"
            "difficulty=peaceful\n"
            "view-distance=3\n"
            "simulation-distance=3\n"
            "spawn-protection=0\n"
            "enable-rcon=false\n"
            "sync-chunk-writes=false\n"
            "max-players=1\n"
            "motd=eclipse xbox world upgrade\n")

    cmd = ["java", "-Xms512M", "-Xmx2G", "-jar", server_jar, "--forceUpgrade", "--nogui"]
    print(f"  exec: {' '.join(cmd)}  (cwd={server_dir})")
    proc = subprocess.Popen(cmd, cwd=server_dir, stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    log_lines: list[str] = []
    stop_sent = False
    fatal: str | None = None

    def pump() -> None:
        nonlocal stop_sent, fatal
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.rstrip("\n")
            log_lines.append(line)
            if any(m in line for m in FATAL_MARKERS):
                fatal = line
            interesting = ("upgrad" in line.lower() or "Done (" in line
                           or "ERROR" in line or "WARN" in line)
            if interesting and len(log_lines) < 4000:
                print(f"    | {line}")
            if not stop_sent and any(m in line for m in DONE_MARKERS):
                stop_sent = True
                try:
                    assert proc.stdin is not None
                    proc.stdin.write("stop\n")
                    proc.stdin.flush()
                    print("    | -> sent 'stop'")
                except OSError as e:
                    print(f"    | could not send stop: {e}")

    t = threading.Thread(target=pump, daemon=True)
    t.start()
    deadline = time.monotonic() + UPGRADE_TIMEOUT_S
    while proc.poll() is None:
        if fatal:
            proc.kill()
            raise SystemExit(f"server failed: {fatal}")
        if time.monotonic() > deadline:
            proc.kill()
            raise SystemExit(f"forceUpgrade timed out after {UPGRADE_TIMEOUT_S}s "
                             f"(pid was {proc.pid}); see log tail:\n" + "\n".join(log_lines[-30:]))
        time.sleep(1)
    t.join(timeout=10)
    log_path = os.path.join(server_dir, f"upgrade_{level_name}.log")
    with open(log_path, "w") as f:
        f.write("\n".join(log_lines) + "\n")
    if proc.returncode != 0:
        raise SystemExit(f"server exited with {proc.returncode}; log: {log_path}\n"
                         + "\n".join(log_lines[-30:]))
    if not stop_sent:
        raise SystemExit(f"server never reached 'Done' - inspect {log_path}")
    print(f"  server log saved: {log_path}")


def verify_dataversions(world_dir: str, expected: int) -> dict:
    hist: collections.Counter[int] = collections.Counter()
    chunks = 0
    for _cx, _cz, raw in region.iter_world_chunks(os.path.join(world_dir, "region")):
        _, root = nbt.loads(raw)
        hist[int(root.get("DataVersion", -1))] += 1
        chunks += 1
    ent_hist: collections.Counter[int] = collections.Counter()
    ent_dir = os.path.join(world_dir, "entities")
    if os.path.isdir(ent_dir):
        for _cx, _cz, raw in region.iter_world_chunks(ent_dir):
            _, root = nbt.loads(raw)
            ent_hist[int(root.get("DataVersion", -1))] += 1
    level_dv = level_dat_data_version(os.path.join(world_dir, "level.dat"))
    report = {
        "levelDatDataVersion": level_dv,
        "chunkCount": chunks,
        "chunkDataVersionHistogram": dict(sorted(hist.items())),
        "entityChunkDataVersionHistogram": dict(sorted(ent_hist.items())),
        "entityChunkNote": "vanilla --forceUpgrade rewrites entity chunks only when "
                           "DFU changed them, so untouched chunks legitimately keep "
                           "the source DataVersion; the game DFUs entity chunks per "
                           "chunk at load (DataFixTypes.ENTITY_CHUNK), and the bake "
                           "preserves per-chunk DataVersions on the wrappers",
    }
    # Hard requirement (plan acceptance): terrain + level.dat at the target version.
    # Entity chunks may lag behind (<= expected) - runtime DFU covers them.
    bad = [dv for dv in list(hist) + [level_dv] if dv != expected]
    bad += [dv for dv in ent_hist if dv > expected or dv <= 0]
    report["ok"] = not bad
    return report


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--worlds", default=None, help="comma-separated subset of world ids")
    args = ap.parse_args()

    cfg = json.load(open(CFG_PATH))
    world_ids = list(cfg["worlds"])
    if args.worlds:
        world_ids = [w for w in args.worlds.split(",") if w]

    work = cfg["workDir"]
    downloads = os.path.join(work, "downloads")
    server_dir = os.path.join(work, "server")
    server_jar = os.path.join(downloads, f"server-{cfg['minecraftVersion']}.jar")
    if not os.path.exists(server_jar):
        raise SystemExit(f"{server_jar} missing - run fetch.py first")
    expected = int(cfg["targetDataVersion"])

    reports = {}
    for wid in world_ids:
        print(f"\n=== {wid} ===")
        zip_path = os.path.join(downloads, f"{wid}_je_latest.zip")
        if not os.path.exists(zip_path):
            raise SystemExit(f"{zip_path} missing - run fetch.py first")

        src_tree = os.path.join(work, "src", wid)
        world_root = extract_source(zip_path, src_tree)
        dv_before = level_dat_data_version(os.path.join(world_root, "level.dat"))
        print(f"  source DataVersion: {dv_before}")

        level_name = f"{wid}_world"
        staged = os.path.join(server_dir, level_name)
        stage_pruned_world(world_root, staged)

        if dv_before == expected:
            print("  already at target DataVersion - skipping server run")
        else:
            run_force_upgrade(server_dir, server_jar, level_name)

        out_dir = os.path.join(work, "upgraded", wid)
        stage_pruned_world(staged, out_dir)

        rep = verify_dataversions(out_dir, expected)
        reports[wid] = rep
        print(f"  verify: level.dat={rep['levelDatDataVersion']} "
              f"chunks={rep['chunkCount']} hist={rep['chunkDataVersionHistogram']} "
              f"entities={rep['entityChunkDataVersionHistogram']} ok={rep['ok']}")
        if not rep["ok"]:
            raise SystemExit(f"{wid}: DataVersion verification FAILED (expected {expected})")

    os.makedirs(os.path.join(work, "reports"), exist_ok=True)
    rep_path = os.path.join(work, "reports", "upgrade_report.json")
    with open(rep_path, "w") as f:
        json.dump(reports, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"\nall worlds upgraded to DataVersion {expected}; report: {rep_path}")


if __name__ == "__main__":
    main()
