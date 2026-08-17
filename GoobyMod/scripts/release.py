#!/usr/bin/env python3
"""Fail-closed local release helper for Gooby Mod roadmap releases."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
from pathlib import Path


ROADMAP_VERSIONS = (
    "3.0.0", "3.1.0", "3.2.0", "3.3.0", "3.4.0",
    "3.5.0", "3.6.0", "3.7.0", "3.8.0", "3.9.0",
    "4.0.0", "4.1.0", "4.2.0", "4.3.0", "5.0.0",
    "5.0.1", "5.0.2", "5.1.0", "5.2.0",
)
MANUALS = (
    "docs/HANDBUCH_DE.md",
    "docs/MANUAL_EN.md",
    "docs/handbuch/HANDBUCH_DE.md",
    "docs/handbuch/MANUAL_EN.md",
)


class ReleaseError(RuntimeError):
    """A release invariant was not met."""


def read_version(root: Path) -> str:
    properties = (root / "gradle.properties").read_text(encoding="utf-8")
    match = re.search(r"^mod_version=(\d+\.\d+\.\d+)$", properties, re.MULTILINE)
    if not match:
        raise ReleaseError("gradle.properties has no valid mod_version")
    version = match.group(1)
    if version not in ROADMAP_VERSIONS:
        raise ReleaseError(f"{version} is not a roadmap release")
    return version


def validate(root: Path, version: str) -> None:
    patchnotes = (root / "PATCHNOTES.md").read_text(encoding="utf-8")
    if not re.search(rf"^## v{re.escape(version)}\b", patchnotes, re.MULTILINE):
        raise ReleaseError(f"PATCHNOTES.md has no v{version} section")

    changelog_path = root / "CHANGELOG.md"
    if not changelog_path.is_file():
        raise ReleaseError("CHANGELOG.md is missing")
    changelog = changelog_path.read_text(encoding="utf-8")
    if not re.search(rf"^## {re.escape(version)}\b", changelog, re.MULTILINE):
        raise ReleaseError(f"CHANGELOG.md has no {version} section")

    readme_path = root / "README.md"
    if not readme_path.is_file():
        raise ReleaseError("README.md is missing")
    readme = readme_path.read_text(encoding="utf-8")
    if f"**Version:** {version}" not in readme:
        raise ReleaseError(
            f"README.md does not declare '**Version:** {version}' (stale version line?)")

    language_dir = root / "src/main/resources/assets/goobymod/lang"
    english = json.loads((language_dir / "en_us.json").read_text(encoding="utf-8"))
    german = json.loads((language_dir / "de_de.json").read_text(encoding="utf-8"))
    if english.keys() != german.keys():
        only_english = sorted(english.keys() - german.keys())
        only_german = sorted(german.keys() - english.keys())
        raise ReleaseError(f"language parity failed; EN-only={only_english}, DE-only={only_german}")

    for relative in MANUALS:
        manual = root / relative
        if not manual.is_file() or f"v{version}" not in manual.read_text(encoding="utf-8"):
            raise ReleaseError(f"{relative} is missing its v{version} update")


def build(root: Path) -> Path:
    subprocess.run(
        ["./gradlew", "build", "--no-daemon", "--max-workers=2"],
        cwd=root,
        check=True,
    )
    version = read_version(root)
    jar = root / "build/libs" / f"goobymod-{version}.jar"
    if not jar.is_file():
        raise ReleaseError(f"build succeeded but {jar.relative_to(root)} is missing")
    return jar


def archive(root: Path, version: str, jar: Path) -> tuple[Path, Path]:
    ordinal = ROADMAP_VERSIONS.index(version) + 1
    archive_dir = root / "versions"
    archive_dir.mkdir(exist_ok=True)
    numbered = archive_dir / f"{ordinal:02d}-goobymod-{version}.jar"
    compatibility = archive_dir / f"goobymod-{version}.jar"
    shutil.copy2(jar, numbered)
    shutil.copy2(jar, compatibility)
    return numbered, compatibility


def print_rubric() -> None:
    print("\nRelease polish rubric (score each 0-2; gate >=18/20, no zero):")
    for index, title in enumerate((
            "Animation fidelity", "Animation variety", "Sound design",
            "AI believability", "Interaction feedback", "Multiplayer correctness",
            "Persistence", "Performance", "i18n & accessibility",
            "Docs & release hygiene"), start=1):
        print(f"  R{index}: [ ] {title}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check-only", action="store_true",
                        help="validate release metadata without building or copying")
    args = parser.parse_args()
    root = args.root.resolve()

    try:
        version = read_version(root)
        validate(root, version)
        if args.check_only:
            print(f"Release metadata for v{version}: OK")
        else:
            jar = build(root)
            numbered, compatibility = archive(root, version, jar)
            print(f"Archived {numbered.relative_to(root)}")
            print(f"Archived {compatibility.relative_to(root)}")
        print_rubric()
        return 0
    except (OSError, ValueError, subprocess.CalledProcessError, ReleaseError) as exception:
        print(f"RELEASE REFUSED: {exception}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
