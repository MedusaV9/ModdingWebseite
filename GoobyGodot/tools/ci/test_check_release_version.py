#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("check_release_version.py")
SPEC = importlib.util.spec_from_file_location("check_release_version", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class CheckReleaseVersionTests(unittest.TestCase):
    def test_reads_strict_project_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory, "project.godot")
            project.write_text('[application]\nconfig/version="5.1.0"\n', encoding="utf-8")
            self.assertEqual(MODULE.project_version(project), "5.1.0")

    def test_tag_and_dispatch_version_sources(self) -> None:
        self.assertEqual(MODULE.requested_release("refs/tags/ipa-v5.1.0", "9.9.9"), "5.1.0")
        self.assertEqual(MODULE.requested_release("refs/heads/main", "5.2.0"), "5.2.0")

    def test_mismatch_and_non_semver_fail(self) -> None:
        with self.assertRaisesRegex(ValueError, "stimmt nicht"):
            MODULE.validate("5.1.0", "5.2.0")
        with self.assertRaisesRegex(ValueError, "striktes Semver"):
            MODULE.validate("5.1.0", "5.1")

    def test_normal_build_without_release_is_valid(self) -> None:
        MODULE.validate("5.1.0", "")


if __name__ == "__main__":
    unittest.main()
