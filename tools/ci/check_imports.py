#!/usr/bin/env python3
"""Prueft, ob Godot wirklich ALLE Ressourcen importiert hat.

Hintergrund: `godot --headless --import` gibt beim Start Autoload-Fehler aus
("Failed loading resource ... Make sure resources have been imported"), weil die
Autoloads laufen, BEVOR der Import fertig ist. Auf diese Zeilen zu greppen ist
deshalb wertlos - der Lauf sieht auch dann rot aus, wenn er erfolgreich war.

Stattdessen wird hier faktisch geprueft: jede `*.import`-Datei nennt ihre
erzeugten Zieldateien unter `[deps] dest_files=[...]`. Fehlt eine davon, wurde
die Ressource nicht importiert und der Export wuerde eine kaputte .ipa bauen.

Aufruf: python3 tools/ci/check_imports.py GOOBY-GODOT
Exit 0 = alles importiert, Exit 1 = fehlende Ziele (werden aufgelistet).
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path


def dest_files(import_file: Path) -> list[str]:
    """Liest die `dest_files`-Liste aus einer .import-Datei."""
    text = import_file.read_text(encoding="utf-8", errors="replace")
    marker = "dest_files="
    start = text.find(marker)
    if start == -1:
        return []
    start += len(marker)
    end = text.find("]", start)
    if end == -1:
        return []
    try:
        return [str(p) for p in ast.literal_eval(text[start : end + 1])]
    except (ValueError, SyntaxError):
        return []


def main() -> int:
    project = Path(sys.argv[1] if len(sys.argv) > 1 else "GOOBY-GODOT").resolve()
    if not (project / "project.godot").exists():
        print(f"FEHLER: {project} ist kein Godot-Projekt")
        return 2

    missing: list[tuple[str, str]] = []
    checked = 0
    for import_file in project.rglob("*.import"):
        for dest in dest_files(import_file):
            if not dest.startswith("res://"):
                continue
            checked += 1
            if not (project / dest[len("res://") :]).exists():
                missing.append((str(import_file.relative_to(project)), dest))

    print(f"Import-Ziele geprueft: {checked}, fehlend: {len(missing)}")
    if missing:
        for src, dest in missing[:40]:
            print(f"  FEHLT {dest}  (aus {src})")
        if len(missing) > 40:
            print(f"  ... und {len(missing) - 40} weitere")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
