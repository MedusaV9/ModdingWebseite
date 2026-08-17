#!/usr/bin/env python3
"""Keep the release ref/input, Godot version and exported IPA version aligned."""

from __future__ import annotations

import argparse
import os
import re
from pathlib import Path

SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
PROJECT_VERSION = re.compile(r'(?m)^config/version="([^"]+)"$')


def project_version(project_file: Path) -> str:
    match = PROJECT_VERSION.search(project_file.read_text(encoding="utf-8"))
    if match is None:
        raise ValueError(f"config/version fehlt in {project_file}")
    version = match.group(1)
    if SEMVER.fullmatch(version) is None:
        raise ValueError(f"Projektversion ist kein striktes Semver: {version!r}")
    return version


def requested_release(github_ref: str, input_version: str) -> str:
    if github_ref.startswith("refs/tags/ipa-v"):
        return github_ref.removeprefix("refs/tags/ipa-v")
    return input_version.strip()


def validate(project: str, requested: str) -> None:
    if requested and SEMVER.fullmatch(requested) is None:
        raise ValueError(f"Release-Version ist kein striktes Semver: {requested!r}")
    if requested and requested != project:
        raise ValueError(
            f"Release-Version {requested} stimmt nicht mit project.godot {project} überein"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default="GOOBY-GODOT/project.godot")
    parser.add_argument("--github-output", default="")
    args = parser.parse_args()

    try:
        project = project_version(Path(args.project))
        requested = requested_release(
            os.environ.get("GITHUB_REF", ""), os.environ.get("INPUT_VERSION", "")
        )
        validate(project, requested)
    except ValueError as error:
        print(f"RELEASE-VERSION ROT: {error}")
        return 1

    effective = requested or project
    if args.github_output:
        with Path(args.github_output).open("a", encoding="utf-8") as handle:
            handle.write(f"version={effective}\n")
    mode = "Release" if requested else "normaler Build"
    print(f"RELEASE-VERSION PASS: {mode} = {effective}; project.godot = {project}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
