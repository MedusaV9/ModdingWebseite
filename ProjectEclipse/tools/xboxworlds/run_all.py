#!/usr/bin/env python3
"""P5-W7 - run the whole Xbox world pipeline: fetch -> upgrade -> bake -> package.

Usage:
    python3 run_all.py [--worlds tu1,tu12,tu14] [--skip-fetch] [--skip-upgrade]

Each stage is an ordinary script and can be (re)run on its own; see README.md.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def run(script: str, extra: list[str]) -> None:
    cmd = [sys.executable, os.path.join(HERE, script)] + extra
    print(f"\n##### {script} {' '.join(extra)} #####", flush=True)
    r = subprocess.run(cmd)
    if r.returncode != 0:
        raise SystemExit(f"{script} failed with exit code {r.returncode}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--worlds", default=None)
    ap.add_argument("--skip-fetch", action="store_true")
    ap.add_argument("--skip-upgrade", action="store_true")
    ap.add_argument("--pin", action="store_true", help="pass --pin to fetch.py")
    args = ap.parse_args()

    sel = ["--worlds", args.worlds] if args.worlds else []
    if not args.skip_fetch:
        run("fetch.py", sel + (["--pin"] if args.pin else []))
    if not args.skip_upgrade:
        run("upgrade.py", sel)
    run("bake.py", sel)
    run("package.py", sel)
    print("\npipeline complete.")


if __name__ == "__main__":
    main()
