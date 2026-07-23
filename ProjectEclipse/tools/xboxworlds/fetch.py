#!/usr/bin/env python3
"""P5-W7 step 1 - fetch the Xbox-360 tutorial world conversions + vanilla server jar.

Sources (verified July 2026, see README.md for the full license notes):
  * theminecraftarchitect.com "JE Latest" zips (DataVersion 3839 = 1.20.6,
    modern region/entities/poi layout). Direct links live on the CDN host
    `downloads.theminecraftarchitect.com` and are pinned in worlds.json.
  * Mojang piston-data: official vanilla 1.21.1 server.jar (used ONLY as the
    local DFU upgrade tool via --forceUpgrade; it is never redistributed).

Integrity: world zips are pinned by sha256 in worlds.json (trust-on-first-use:
run with --pin once to record fresh hashes); server.jar is verified against the
official sha1 from Mojang's version manifest.

Everything lands in <workDir>/downloads. Idempotent - existing files that pass
their hash check are not re-downloaded. A pre-existing planner download at
/tmp/tu12_je_latest.zip is adopted if its hash matches (or --pin records it).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CFG_PATH = os.path.join(HERE, "worlds.json")
LEGACY_TU12 = "/tmp/tu12_je_latest.zip"  # planner's verified first download
UA = "Mozilla/5.0 (compatible; EclipseXboxPipeline/1.0; ProjectEclipse dev tool)"
VERSION_MANIFEST = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def sha1_of(path: str) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def download(url: str, dest: str, attempts: int = 3) -> None:
    tmp = dest + ".part"
    last_err: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as resp, open(tmp, "wb") as out:
                shutil.copyfileobj(resp, out, 1 << 20)
            os.replace(tmp, dest)
            return
        except Exception as e:  # noqa: BLE001 - retry then fall back to curl
            last_err = e
            print(f"  attempt {attempt} failed: {e}", flush=True)
            time.sleep(2 * attempt)
    # curl fallback (some CDNs dislike urllib)
    print("  falling back to curl ...", flush=True)
    r = subprocess.run(["curl", "-fL", "--retry", "3", "-A", UA, "-o", tmp, url])
    if r.returncode == 0:
        os.replace(tmp, dest)
        return
    raise RuntimeError(f"download failed for {url}: {last_err}")


def fetch_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def fetch_worlds(cfg: dict, downloads: str, pin: bool) -> bool:
    changed = False
    for world_id, world in cfg["worlds"].items():
        url = world["source"]["url"]
        pinned = world["source"].get("sha256")
        dest = os.path.join(downloads, f"{world_id}_je_latest.zip")

        if not os.path.exists(dest) and world_id == "tu12" and os.path.exists(LEGACY_TU12):
            print(f"[{world_id}] adopting planner download {LEGACY_TU12}")
            shutil.copy2(LEGACY_TU12, dest)

        if os.path.exists(dest):
            digest = sha256_of(dest)
            if pinned and digest != pinned:
                print(f"[{world_id}] cached file hash mismatch, re-downloading")
                os.remove(dest)
            else:
                print(f"[{world_id}] cached  sha256={digest}  ({os.path.getsize(dest)} bytes)")
                if not pinned and pin:
                    world["source"]["sha256"] = digest
                    changed = True
                continue

        print(f"[{world_id}] downloading {url}")
        download(url, dest)
        digest = sha256_of(dest)
        size = os.path.getsize(dest)
        print(f"[{world_id}] done  sha256={digest}  ({size} bytes)")
        if pinned:
            if digest != pinned:
                raise SystemExit(
                    f"[{world_id}] SHA256 MISMATCH!\n  expected {pinned}\n  actual   {digest}\n"
                    "Source may have changed - re-verify manually, then update worlds.json.")
        elif pin:
            world["source"]["sha256"] = digest
            changed = True
        else:
            print(f"[{world_id}] WARNING: no pinned sha256 in worlds.json (run with --pin to record)")
    return changed


def fetch_server_jar(cfg: dict, downloads: str) -> str:
    version = cfg["minecraftVersion"]
    dest = os.path.join(downloads, f"server-{version}.jar")
    meta_cache = os.path.join(downloads, f"server-{version}.meta.json")

    if os.path.exists(dest) and os.path.exists(meta_cache):
        meta = json.load(open(meta_cache))
        if sha1_of(dest) == meta["sha1"]:
            print(f"[server] cached  sha1={meta['sha1']}  ({os.path.getsize(dest)} bytes)")
            return dest
        print("[server] cached jar failed sha1 check, re-downloading")

    print(f"[server] resolving vanilla {version} via {VERSION_MANIFEST}")
    manifest = fetch_json(VERSION_MANIFEST)
    entry = next((v for v in manifest["versions"] if v["id"] == version), None)
    if entry is None:
        raise SystemExit(f"version {version} not present in Mojang version manifest")
    version_meta = fetch_json(entry["url"])
    server_info = version_meta["downloads"]["server"]
    print(f"[server] downloading {server_info['url']}  ({server_info['size']} bytes)")
    download(server_info["url"], dest)
    actual = sha1_of(dest)
    if actual != server_info["sha1"]:
        raise SystemExit(f"[server] SHA1 MISMATCH: expected {server_info['sha1']}, got {actual}")
    json.dump({"sha1": server_info["sha1"], "url": server_info["url"],
               "size": server_info["size"], "version": version},
              open(meta_cache, "w"), indent=2)
    print(f"[server] done  sha1={actual}")
    return dest


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pin", action="store_true",
                    help="record freshly computed sha256 hashes back into worlds.json")
    ap.add_argument("--worlds", default=None,
                    help="comma-separated subset of world ids (default: all)")
    args = ap.parse_args()

    cfg = json.load(open(CFG_PATH))
    if args.worlds:
        keep = set(args.worlds.split(","))
        unknown = keep - set(cfg["worlds"])
        if unknown:
            raise SystemExit(f"unknown world ids: {sorted(unknown)}")
        cfg["worlds"] = {k: v for k, v in cfg["worlds"].items() if k in keep}

    downloads = os.path.join(cfg["workDir"], "downloads")
    os.makedirs(downloads, exist_ok=True)

    changed = fetch_worlds(cfg, downloads, args.pin)
    fetch_server_jar(cfg, downloads)

    if changed:
        full = json.load(open(CFG_PATH))
        for wid, w in cfg["worlds"].items():
            full["worlds"][wid]["source"]["sha256"] = w["source"]["sha256"]
        with open(CFG_PATH, "w") as f:
            json.dump(full, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"pinned new hashes into {CFG_PATH}")

    print("\nNOTE: the tutorial worlds are Mojang/4J Studios copyrighted content; the Java\n"
          "conversions are courtesy of theminecraftarchitect.com. Private-event use only,\n"
          "full credit in CREDITS.md - see README.md 'Sources & licenses' (plan SS5 R5).")


if __name__ == "__main__":
    main()
