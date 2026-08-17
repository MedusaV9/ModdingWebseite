#!/usr/bin/env python3
"""Fail closed on engine failures hidden behind a zero Godot exit code."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
UNEXPECTED = (
    re.compile(r"(?m)^\s*SCRIPT ERROR:"),
    re.compile(r"(?m)^\s*USER ERROR:"),
    re.compile(r"(?m)^\s*ERROR:"),
    re.compile(r"(?m)^\s*SKIP(?:\s|:)"),
    re.compile(r"(?im)^.*(?:RID allocations|ObjectDB instances|Resources still in use).*(?:leak|at exit).*$"),
    re.compile(r"(?im)^.*\bRIDs?\b.*\bleak(?:ed)?\b.*$"),
    re.compile(r"(?im)^.*(?:leaked instance|orphan node).*$"),
)


def allowed_patterns(path: Path | None) -> list[re.Pattern[str]]:
    if path is None:
        return []
    patterns: list[re.Pattern[str]] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        try:
            patterns.append(re.compile(line))
        except re.error as error:
            raise SystemExit(f"FEHLER: ungültige Allowlist-RegEx {path}:{number}: {error}")
    return patterns


def unexpected_lines(text: str, allow: list[re.Pattern[str]]) -> list[str]:
    clean = ANSI.sub("", text)
    hits: list[str] = []
    for line in clean.splitlines():
        if not any(pattern.search(line) for pattern in UNEXPECTED):
            continue
        if any(pattern.fullmatch(line) for pattern in allow):
            continue
        if line not in hits:
            hits.append(line)
    return hits


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print(f"Aufruf: {sys.argv[0]} <godot-log> [allowlist-regex-datei]", file=sys.stderr)
        return 2
    log = Path(sys.argv[1])
    allow_path = Path(sys.argv[2]) if len(sys.argv) == 3 else None
    if not log.is_file():
        print(f"FEHLER: Godot-Log fehlt: {log}", file=sys.stderr)
        return 2
    if allow_path is not None and not allow_path.is_file():
        print(f"FEHLER: Allowlist fehlt: {allow_path}", file=sys.stderr)
        return 2
    hits = unexpected_lines(log.read_text(encoding="utf-8", errors="replace"), allowed_patterns(allow_path))
    if hits:
        print(f"GODOT-LOG ROT: {len(hits)} unerwartete Fehler/Leaks/Skips:", file=sys.stderr)
        for line in hits:
            print(f"  {line}", file=sys.stderr)
        return 1
    print("GODOT-LOG PASS: 0 unerwartete SCRIPT ERROR/ERROR/Leaks/Skips")
    return 0


if __name__ == "__main__":
    sys.exit(main())
