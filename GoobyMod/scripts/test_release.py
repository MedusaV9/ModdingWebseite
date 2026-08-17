#!/usr/bin/env python3
"""Focused tests for the fail-closed release metadata gate."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release


class ReleaseValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "src/main/resources/assets/goobymod/lang").mkdir(parents=True)
        (self.root / "docs/handbuch").mkdir(parents=True)
        (self.root / "gradle.properties").write_text("mod_version=3.0.0\n", encoding="utf-8")
        (self.root / "README.md").write_text(
            "# Gooby Mod\n\n- **Version:** 3.0.0\n", encoding="utf-8")
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\n## 3.0.0 (2026-08-11)\n", encoding="utf-8")
        for language in ("en_us.json", "de_de.json"):
            (self.root / "src/main/resources/assets/goobymod/lang" / language).write_text(
                json.dumps({"test.key": "text"}), encoding="utf-8")
        for manual in release.MANUALS:
            (self.root / manual).write_text("# Gooby manual v3.0.0\n", encoding="utf-8")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def test_missing_patchnotes_section_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v2.0.0\n", encoding="utf-8")
        with self.assertRaisesRegex(release.ReleaseError, "no v3.0.0 section"):
            release.validate(self.root, "3.0.0")

    def test_stale_readme_version_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        (self.root / "README.md").write_text(
            "# Gooby Mod\n\n- **Version:** 2.0.0\n", encoding="utf-8")
        with self.assertRaisesRegex(release.ReleaseError, r"README\.md does not declare"):
            release.validate(self.root, "3.0.0")

    def test_missing_readme_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        (self.root / "README.md").unlink()
        with self.assertRaisesRegex(release.ReleaseError, r"README\.md is missing"):
            release.validate(self.root, "3.0.0")

    def test_missing_changelog_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        (self.root / "CHANGELOG.md").unlink()
        with self.assertRaisesRegex(release.ReleaseError, r"CHANGELOG\.md is missing"):
            release.validate(self.root, "3.0.0")

    def test_stale_changelog_section_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        (self.root / "CHANGELOG.md").write_text(
            "# Changelog\n\n## 2.0.0 (2026-08-10)\n", encoding="utf-8")
        with self.assertRaisesRegex(release.ReleaseError, "CHANGELOG.md has no 3.0.0 section"):
            release.validate(self.root, "3.0.0")

    def test_missing_manual_update_refuses_release(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        stale = self.root / release.MANUALS[0]
        stale.write_text("# Gooby manual v2.0.0\n", encoding="utf-8")
        with self.assertRaisesRegex(release.ReleaseError, "missing its v3.0.0 update"):
            release.validate(self.root, "3.0.0")

    def test_current_version_is_roadmap_release(self) -> None:
        self.assertIn("5.2.0", release.ROADMAP_VERSIONS)
        (self.root / "gradle.properties").write_text("mod_version=5.2.0\n", encoding="utf-8")
        self.assertEqual(release.read_version(self.root), "5.2.0")

    def test_unknown_version_refuses_release(self) -> None:
        (self.root / "gradle.properties").write_text("mod_version=9.9.9\n", encoding="utf-8")
        with self.assertRaisesRegex(release.ReleaseError, "not a roadmap release"):
            release.read_version(self.root)

    def test_complete_metadata_passes(self) -> None:
        (self.root / "PATCHNOTES.md").write_text("## v3.0.0\n", encoding="utf-8")
        release.validate(self.root, "3.0.0")


if __name__ == "__main__":
    unittest.main()
