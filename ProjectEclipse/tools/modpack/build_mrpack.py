#!/usr/bin/env python3
"""Builds the distributable Modrinth modpack (.mrpack) for the Eclipse event pack.

Reads tools/modpack/pack_manifest.json (single source of truth: exact versions, jar
filenames, client/server env flags — see docs/BUNDLING.md "Modrinth pack (.mrpack)").
Every 'modrinth' entry is resolved against the Modrinth API by exact jar filename, so the
.mrpack REFERENCES official downloads (URL + sha1/sha512 + size) instead of redistributing
jars — no ARR file is ever embedded. The overrides/ folder carries only redistributable
content: the Eclipse jar itself (ours) and the default config/eclipse seeds. 'manual'
entries (Aeronautics bundle, Sable) land in a generated overrides/MANUAL_INSTALL.md.

Also regenerates tools/modpack/mods_manifest.json: the committed, human/machine-readable
inventory (exact name + version + URL + sha512 per mod) that answers "just give me a zip"
without redistributing anything.

Usage:
  python3 tools/modpack/build_mrpack.py                 # build dist/eclipse-event-<v>.mrpack
  python3 tools/modpack/build_mrpack.py --verify        # additionally sha512-check every file
                                                        # (uses run/mods* copies when present)
  python3 tools/modpack/build_mrpack.py --out X.mrpack  # custom output path
  python3 tools/modpack/build_mrpack.py --no-config-seeds --allow-missing-jar
"""
import argparse
import hashlib
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).resolve().parent / "pack_manifest.json"
MODS_MANIFEST = Path(__file__).resolve().parent / "mods_manifest.json"
DIST = ROOT / "dist"
LOCAL_JAR_DIRS = [ROOT / "run/mods", ROOT / "run/mods-client"]

API = "https://api.modrinth.com/v2"
UA = {"User-Agent": "ProjectEclipse-mrpack-builder/1.0 (tools/modpack/build_mrpack.py)"}


def fetch_json(url: str):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def resolve_modrinth(entry: dict) -> dict:
    """Exact-filename resolution against the Modrinth API → url/hashes/size/version page."""
    slug = entry["slug"]
    game_versions = urllib.parse.quote('["1.21.1"]')
    loaders = urllib.parse.quote('["neoforge"]')
    versions = fetch_json(f"{API}/project/{slug}/version?game_versions={game_versions}&loaders={loaders}")
    for version in versions:
        for file in version.get("files", []):
            if file["filename"] == entry["filename"]:
                return {
                    "url": file["url"],
                    "sha1": file["hashes"]["sha1"],
                    "sha512": file["hashes"]["sha512"],
                    "size": file["size"],
                    "version_page": f"https://modrinth.com/mod/{slug}/version/"
                                    + urllib.parse.quote(version["version_number"], safe=""),
                }
    nearest = [f["filename"] for v in versions[:5] for f in v.get("files", [])]
    raise RuntimeError(f"{entry['filename']}: exact jar not found on Modrinth; nearest: {nearest[:5]}")


def sha512_of(path: Path) -> str:
    digest = hashlib.sha512()
    with open(path, "rb") as handle:
        while chunk := handle.read(1 << 16):
            digest.update(chunk)
    return digest.hexdigest()


def sha512_of_url(url: str) -> str:
    digest = hashlib.sha512()
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as resp:
        while chunk := resp.read(1 << 16):
            digest.update(chunk)
    return digest.hexdigest()


def manual_install_md(manual_entries: list) -> str:
    lines = [
        "# Manual installs (not referenced by the .mrpack)",
        "",
        "These mods are not on a public CDN and/or their license policy makes an external,",
        "operator-supplied install the safe path (see docs/BUNDLING.md in the Eclipse repo).",
        "Drop the exact jars below into this instance's `mods/` folder before joining:",
        "",
    ]
    for entry in manual_entries:
        lines.append(f"- **{entry['name']}** {entry['version']} — `{entry['filename']}`")
        if entry.get("note"):
            lines.append(f"  - {entry['note']}")
    lines += [
        "",
        "Everything else (including EMI, Mouse Tweaks, Veil and GeckoLib) is either referenced",
        "by the pack index or already embedded inside the Eclipse jar — install NOTHING else.",
        "",
    ]
    return "\n".join(lines)


def build(args) -> int:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    pack_version = manifest["packVersion"]
    out_path = Path(args.out) if args.out else DIST / f"eclipse-event-{pack_version}.mrpack"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    modrinth_entries = [m for m in manifest["mods"] if m["source"] == "modrinth"]
    manual_entries = [m for m in manifest["mods"] if m["source"] == "manual"]
    embedded_entries = [m for m in manifest["mods"] if m["source"] == "embedded"]

    # --- resolve download references ------------------------------------------------
    files = []
    inventory = []
    failures = []
    for entry in modrinth_entries:
        try:
            resolved = resolve_modrinth(entry)
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{entry['id']}: {exc}")
            continue
        print(f"RESOLVED {entry['filename']} <- {resolved['url']}")
        files.append({
            "path": f"mods/{entry['filename']}",
            "hashes": {"sha1": resolved["sha1"], "sha512": resolved["sha512"]},
            "env": {"client": entry["client"], "server": entry["server"]},
            "downloads": [resolved["url"]],
            "fileSize": resolved["size"],
        })
        inventory.append({
            "id": entry["id"],
            "name": entry["name"],
            "version": entry["version"],
            "filename": entry["filename"],
            "source": "modrinth",
            "url": resolved["url"],
            "page": resolved["version_page"],
            "sha512": resolved["sha512"],
            "env": {"client": entry["client"], "server": entry["server"]},
            **({"note": entry["note"]} if entry.get("note") else {}),
        })
    if failures:
        print("\nFAILURES while resolving Modrinth references:")
        for failure in failures:
            print(f"  {failure}")
        return 1

    for entry in manual_entries:
        inventory.append({
            "id": entry["id"], "name": entry["name"], "version": entry["version"],
            "filename": entry["filename"], "source": "manual",
            "url": "operator-supplied (see docs/BUNDLING.md)",
            "env": {"client": entry["client"], "server": entry["server"]},
            "note": entry.get("note", ""),
        })
    for entry in embedded_entries:
        inventory.append({
            "id": entry["id"], "name": entry["name"], "version": entry["version"],
            "source": "embedded-in-eclipse-jar", "note": entry.get("note", ""),
        })

    # --- optional verification --------------------------------------------------------
    if args.verify:
        print("\nVerifying sha512 of every referenced file...")
        for file, entry in zip(files, modrinth_entries):
            local = next((d / entry["filename"] for d in LOCAL_JAR_DIRS
                          if (d / entry["filename"]).is_file()), None)
            actual = sha512_of(local) if local else sha512_of_url(file["downloads"][0])
            source = f"local {local}" if local else "download"
            if actual != file["hashes"]["sha512"]:
                print(f"  MISMATCH {entry['filename']} ({source})")
                return 1
            print(f"  OK {entry['filename']} ({source})")

    # --- overrides ---------------------------------------------------------------------
    eclipse_jar = ROOT / manifest["eclipseJar"]
    if not eclipse_jar.is_file():
        message = (f"Eclipse jar not found at {eclipse_jar} — run './gradlew build' first"
                   " (or pass --allow-missing-jar for an index-only pack).")
        if not args.allow_missing_jar:
            print(message)
            return 1
        print(f"WARN {message}")
        eclipse_jar = None

    config_seeds = ROOT / manifest["configSeeds"]
    seed_files = []
    if not args.no_config_seeds:
        if config_seeds.is_dir():
            seed_files = sorted(p for p in config_seeds.rglob("*") if p.is_file())
        else:
            print(f"WARN config seeds dir {config_seeds} missing — pack ships without config overrides")

    # --- write the .mrpack ---------------------------------------------------------------
    index = {
        "formatVersion": 1,
        "game": "minecraft",
        "versionId": pack_version,
        "name": manifest["name"],
        "summary": manifest["summary"],
        "files": files,
        "dependencies": {
            "minecraft": manifest["minecraft"],
            "neoforge": manifest["neoforge"],
        },
    }
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as pack:
        pack.writestr("modrinth.index.json", json.dumps(index, indent=2))
        pack.writestr("overrides/MANUAL_INSTALL.md", manual_install_md(manual_entries))
        if eclipse_jar is not None:
            pack.write(eclipse_jar, f"overrides/mods/{eclipse_jar.name}")
        for seed in seed_files:
            pack.write(seed, f"overrides/config/eclipse/{seed.relative_to(config_seeds).as_posix()}")

    # --- committed inventory (the honest "zip" substitute) ------------------------------
    MODS_MANIFEST.write_text(json.dumps({
        "_comment": "Generated by tools/modpack/build_mrpack.py — the committed per-mod inventory "
                    "(exact name+version+URL+sha512). Regenerate after editing pack_manifest.json.",
        "pack": {"name": manifest["name"], "version": pack_version,
                 "minecraft": manifest["minecraft"], "neoforge": manifest["neoforge"]},
        "mods": inventory,
    }, indent=2) + "\n", encoding="utf-8")

    size_mb = out_path.stat().st_size / (1 << 20)
    print(f"\nWROTE {out_path} ({size_mb:.1f} MiB): {len(files)} referenced mods, "
          f"{len(manual_entries)} manual, {len(embedded_entries)} embedded, "
          f"{len(seed_files)} config seeds"
          + (", + eclipse jar" if eclipse_jar is not None else ""))
    print(f"WROTE {MODS_MANIFEST}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", help="output .mrpack path (default dist/eclipse-event-<v>.mrpack)")
    parser.add_argument("--verify", action="store_true",
                        help="sha512-check every referenced file (local run/mods copy when present)")
    parser.add_argument("--no-config-seeds", action="store_true",
                        help="skip bundling run/config/eclipse defaults into overrides/")
    parser.add_argument("--allow-missing-jar", action="store_true",
                        help="build an index-only pack when build/libs/eclipse-*.jar is absent")
    return build(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
