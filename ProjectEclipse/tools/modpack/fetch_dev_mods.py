#!/usr/bin/env python3
"""Fetches the dev server pack (run/mods) and client-only pack (run/mods-client)
from the Modrinth API, matching the exact jar names documented in README
"Server pack". Idempotent: skips files that already exist with plausible size.

Usage: python3 tools/modpack/fetch_dev_mods.py
"""
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODS = ROOT / "run/mods"
MODS_CLIENT = ROOT / "run/mods-client"

API = "https://api.modrinth.com/v2"
UA = {"User-Agent": "ProjectEclipse-dev-setup/1.0 (cursor cloud agent)"}

# (modrinth slug, expected jar filename, target dir)
WANTED = [
    ("create", "create-1.21.1-6.0.10.jar", MODS),
    ("create-aeronautics", "create-aeronautics-bundled-1.21.1-1.3.0.jar", MODS),
    ("sable", "sable-neoforge-1.21.1-2.0.3.jar", MODS),
    ("simple-voice-chat", "voicechat-neoforge-1.21.1-2.6.16.jar", MODS),
    ("farmers-delight", "FarmersDelight-1.21.1-1.3.2.jar", MODS),
    ("supplementaries", "supplementaries-neoforge-1.21.1-3.8.3.jar", MODS),
    ("moonlight", "moonlight-neoforge-1.21.1-3.1.1.jar", MODS),
    ("sophisticated-backpacks", "sophisticatedbackpacks-1.21.1-3.25.71.1997.jar", MODS),
    ("sophisticated-core", "sophisticatedcore-1.21.1-1.4.77.2173.jar", MODS),
    ("createaddition", "createaddition-1.6.0.jar", MODS),
    ("sodium", "sodium-neoforge-0.8.12+mc1.21.1.jar", MODS_CLIENT),
    ("iris", "iris-neoforge-1.8.14-beta.1+mc1.21.1.jar", MODS_CLIENT),
]


def fetch_json(url: str):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def download(url: str, dest: Path):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
        while chunk := resp.read(1 << 16):
            out.write(chunk)


def main() -> int:
    MODS.mkdir(parents=True, exist_ok=True)
    MODS_CLIENT.mkdir(parents=True, exist_ok=True)
    failures = []
    for slug, jar_name, target_dir in WANTED:
        dest = target_dir / jar_name
        if dest.exists() and dest.stat().st_size > 10_000:
            print(f"SKIP {jar_name} (exists)")
            continue
        try:
            q = urllib.parse.quote('["1.21.1"]')
            l = urllib.parse.quote('["neoforge"]')
            versions = fetch_json(f"{API}/project/{slug}/version?game_versions={q}&loaders={l}")
        except Exception as exc:  # noqa: BLE001
            failures.append((jar_name, f"version list failed: {exc}"))
            continue
        chosen = None
        for version in versions:
            for file in version.get("files", []):
                if file["filename"] == jar_name:
                    chosen = file
                    break
            if chosen:
                break
        if not chosen:
            # Fallback: exact-name miss; report the closest available filenames.
            names = [f["filename"] for v in versions[:5] for f in v.get("files", [])]
            failures.append((jar_name, f"exact jar not found; nearest: {names[:5]}"))
            continue
        try:
            print(f"GET  {jar_name} <- {chosen['url']}")
            download(chosen["url"], dest)
            print(f"OK   {jar_name} ({dest.stat().st_size:,} bytes)")
        except Exception as exc:  # noqa: BLE001
            failures.append((jar_name, f"download failed: {exc}"))
    if failures:
        print("\nFAILURES:")
        for jar_name, why in failures:
            print(f"  {jar_name}: {why}")
        return 1
    print("\nAll mods fetched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
