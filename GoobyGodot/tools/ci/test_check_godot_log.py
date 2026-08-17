#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import re
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check_godot_log.py")
SPEC = importlib.util.spec_from_file_location("check_godot_log", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CheckGodotLogTests(unittest.TestCase):
    def test_clean_log_passes(self) -> None:
        text = "Godot Engine v4.4.1\n  PASS test_example\n== Ergebnis: tests=1, failed=0 ==\n"
        self.assertEqual(MODULE.unexpected_lines(text, []), [])

    def test_engine_errors_skips_and_leaks_fail(self) -> None:
        text = "\n".join(
            (
                "SCRIPT ERROR: Invalid access to property.",
                "ERROR: Parameter material is null.",
                "  SKIP test_net — node fehlt",
                "WARNING: ObjectDB instances leaked at exit (run with --verbose for details).",
                "2 RID allocations of type 'Texture' were leaked at exit.",
            )
        )
        hits = MODULE.unexpected_lines(text, [])
        self.assertEqual(len(hits), 5)

    def test_allowlist_requires_full_line_match(self) -> None:
        text = "ERROR: erwarteter Negativtest\nERROR: erwarteter Negativtest plus Überraschung"
        allow = [re.compile(r"ERROR: erwarteter Negativtest")]
        self.assertEqual(
            MODULE.unexpected_lines(text, allow),
            ["ERROR: erwarteter Negativtest plus Überraschung"],
        )

    def test_project_allowlist_is_limited_to_known_negative_tests(self) -> None:
        allow = MODULE.allowed_patterns(MODULE_PATH.with_name("godot-log-allowlist.txt"))
        known = "\n".join(
            (
                "ERROR: AppSettings.value_of: unbekannter Key 'gibt.es.nicht'.",
                (
                    "ERROR: [save_manager] Save fehlgeschlagen: Schreiben nach "
                    "user://w1d_tests/mgr_123_4/save_v5.json.tmp fehlgeschlagen "
                    "(store_string unvollständig — volle Platte?)"
                ),
            )
        )
        self.assertEqual(MODULE.unexpected_lines(known, allow), [])
        self.assertEqual(
            MODULE.unexpected_lines(
                "ERROR: [save_manager] Save fehlgeschlagen: Produktion kaputt", allow
            ),
            ["ERROR: [save_manager] Save fehlgeschlagen: Produktion kaputt"],
        )

    def test_ansi_colours_do_not_hide_error(self) -> None:
        self.assertEqual(
            MODULE.unexpected_lines("\x1b[31mERROR: sichtbar rot\x1b[0m", []),
            ["ERROR: sichtbar rot"],
        )


if __name__ == "__main__":
    unittest.main()
