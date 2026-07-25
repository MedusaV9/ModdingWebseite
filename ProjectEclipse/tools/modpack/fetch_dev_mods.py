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

# NOTE: EMI (1.1.24+1.21.1) and Mouse Tweaks (1.21-2.26.1-neoforge) are deliberately NOT
# fetched here — both are jarJar-embedded in the eclipse jar itself (build.gradle /
# docs/BUNDLING.md), so the dev runs pick them up without a mods-folder copy.
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

# OPTIONAL extras (D12): fetched on a best-effort basis; a miss is reported but never
# fails the run. Photon is the optional VFX enhancement layer consumed by
# veilfx/PhotonBridge (reflection, isLoaded-guarded); its mods.toml requires LDLib2
# (Modrinth slug "ldlib", mod id "ldlib2"). PH-CORE: the pair goes into BOTH
# run/mods-client AND run/mods (dedicated server) per INTEGRATION.md §2 Verdict C —
# photon+ldlib2 register NON-optional network channels, so a Photon-equipped client is
# NOTE: MUST be the Modrinth "-all" fat jar (bundles META-INF/jarjar/taffy-1.1.4.jar etc.);
# the slim maven jar crashes at mod construction with NoClassDefFoundError dev/vfyjxf/taffy.
# disconnected during handshake by a photon-less server; the server-side install is
# crash-safe (Verdict B: photon's mixins are all client-array, GL feature side-aware).
OPTIONAL = [
    ("photon-editor", "photon-neoforge-1.21.1-2.1.5.jar", MODS_CLIENT),
    ("ldlib", "ldlib2-neoforge-1.21.1-2.2.29-all.jar", MODS_CLIENT),
    ("photon-editor", "photon-neoforge-1.21.1-2.1.5.jar", MODS),
    ("ldlib", "ldlib2-neoforge-1.21.1-2.2.29-all.jar", MODS),
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


def fetch_list(entries, failures) -> None:
    for slug, jar_name, target_dir in entries:
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


def main() -> int:
    MODS.mkdir(parents=True, exist_ok=True)
    MODS_CLIENT.mkdir(parents=True, exist_ok=True)
    failures = []
    fetch_list(WANTED, failures)
    optional_failures = []
    fetch_list(OPTIONAL, optional_failures)
    if optional_failures:
        print("\nOPTIONAL (skipped, not fatal):")
        for jar_name, why in optional_failures:
            print(f"  {jar_name}: {why}")
    if failures:
        print("\nFAILURES:")
        for jar_name, why in failures:
            print(f"  {jar_name}: {why}")
        return 1
    print("\nAll required mods fetched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
