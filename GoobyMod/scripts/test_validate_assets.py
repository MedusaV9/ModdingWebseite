#!/usr/bin/env python3
"""Unit-Tests fuer den fail-closed Asset-Validator (scripts/validate_assets.py)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import validate_assets


def adult_geo():
    return {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {"identifier": "geometry.gooby",
                            "texture_width": 16, "texture_height": 16},
            "bones": [
                {"name": "root", "pivot": [0, 0, 0]},
                {"name": "body", "parent": "root", "pivot": [0, 1, 0],
                 "cubes": [{"origin": [0, 0, 0], "size": [2, 2, 2], "uv": [0, 0]}]},
                {"name": "hat_anchor", "parent": "body", "pivot": [0, 2, 0]},
                {"name": "neck_anchor", "parent": "body", "pivot": [0, 2, -1]},
                {"name": "back_anchor", "parent": "body", "pivot": [0, 1, 1]},
            ],
        }],
    }


def baby_geo():
    return {
        "format_version": "1.12.0",
        "minecraft:geometry": [{
            "description": {"identifier": "geometry.gooby_baby",
                            "texture_width": 16, "texture_height": 16},
            "bones": [
                {"name": "root", "pivot": [0, 0, 0]},
                {"name": "body", "parent": "root", "pivot": [0, 1, 0],
                 "cubes": [{"origin": [0, 0, 0], "size": [2, 2, 2], "uv": [0, 0]}]},
                {"name": "hat_anchor", "parent": "body", "pivot": [0, 2, 0]},
            ],
        }],
    }


def animation_doc():
    return {
        "format_version": "1.8.0",
        "animations": {
            "animation.gooby.idle": {
                "loop": True,
                "animation_length": 1.0,
                "bones": {
                    "body": {
                        "rotation": {
                            "0.0": [0, 0, 0],
                            "0.5": {"post": [0, 2, 0], "lerp_mode": "catmullrom"},
                            "1.0": {"vector": [0, 0, 5],
                                    "easing": "easeInOutSine"},
                        }
                    }
                },
            }
        },
    }


def bbmodel_doc(geo):
    geometry = geo["minecraft:geometry"][0]
    bones = geometry["bones"]
    elements = []
    groups = {}
    for bone in bones:
        groups[bone["name"]] = {
            "name": bone["name"], "origin": [0, 0, 0], "uuid": f"g-{bone['name']}",
            "children": [],
        }
        for index, _cube in enumerate(bone.get("cubes", [])):
            uuid = f"e-{bone['name']}-{index}"
            elements.append({"name": bone["name"], "uuid": uuid,
                             "from": [0, 0, 0], "to": [2, 2, 2],
                             "uv_offset": [0, 0], "type": "cube"})
            groups[bone["name"]]["children"].append(uuid)
    outliner = []
    for bone in bones:
        node = groups[bone["name"]]
        parent = bone.get("parent")
        if parent is None or parent not in groups:
            outliner.append(node)
        else:
            groups[parent]["children"].append(node)
    return {
        "meta": {"format_version": "4.10", "model_format": "bedrock",
                 "box_uv": True},
        "name": geometry["description"]["identifier"],
        "resolution": {"width": 16, "height": 16},
        "elements": elements,
        "outliner": outliner,
    }


class ValidatorFixtureTest(unittest.TestCase):
    """Baut einen synthetischen Asset-Baum und bricht gezielt Einzelteile."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.geo_dir = self.root / validate_assets.ASSET_BASE / "geo"
        self.anim_dir = self.root / validate_assets.ASSET_BASE / "animations"
        self.tex_dir = (self.root / validate_assets.ASSET_BASE
                        / "textures" / "entity")
        self.bb_dir = self.root / "assets_src" / "blockbench"
        for directory in (self.geo_dir, self.anim_dir, self.tex_dir, self.bb_dir):
            directory.mkdir(parents=True)

        self.adult = adult_geo()
        self.baby = baby_geo()
        self.animation = animation_doc()
        self.write_all()

    def tearDown(self):
        self.temporary.cleanup()

    def write_all(self):
        (self.geo_dir / "gooby.geo.json").write_text(json.dumps(self.adult))
        (self.geo_dir / "gooby_baby.geo.json").write_text(json.dumps(self.baby))
        (self.anim_dir / "gooby.animation.json").write_text(
            json.dumps(self.animation))
        for names in validate_assets.GEO_TEXTURES.values():
            for name in names:
                Image.new("RGBA", (16, 16), (200, 160, 110, 255)).save(
                    self.tex_dir / name)
        (self.bb_dir / "gooby.bbmodel").write_text(
            json.dumps(bbmodel_doc(self.adult)))
        (self.bb_dir / "gooby_baby.bbmodel").write_text(
            json.dumps(bbmodel_doc(self.baby)))

    def run_validator(self):
        return validate_assets.run(str(self.root))

    def assert_failure_containing(self, snippet):
        errors, _passed = self.run_validator()
        self.assertTrue(any(snippet in error for error in errors),
                        f"Kein Fehler enthaelt '{snippet}': {errors}")

    # --- Happy path -------------------------------------------------------

    def test_valid_fixture_passes(self):
        errors, passed = self.run_validator()
        self.assertEqual(errors, [])
        self.assertGreaterEqual(len(passed), 10)

    def test_main_exit_codes(self):
        self.assertEqual(validate_assets.main(["--root", str(self.root)]), 0)
        (self.geo_dir / "gooby.geo.json").write_text("{kaputt")
        self.assertNotEqual(validate_assets.main(["--root", str(self.root)]), 0)

    # --- JSON / Geo -------------------------------------------------------

    def test_broken_json_fails(self):
        (self.geo_dir / "gooby.geo.json").write_text("{nicht json")
        self.assert_failure_containing("JSON-Parse-Fehler")

    def test_broken_bbmodel_json_fails(self):
        (self.bb_dir / "gooby.bbmodel").write_text("]]]")
        self.assert_failure_containing("JSON-Parse-Fehler")

    def test_duplicate_bone_names_fail(self):
        self.adult["minecraft:geometry"][0]["bones"].append(
            {"name": "body", "parent": "root", "pivot": [0, 0, 0]})
        self.write_all()
        self.assert_failure_containing("doppelte Bone-Namen")

    def test_unknown_parent_fails(self):
        self.adult["minecraft:geometry"][0]["bones"][1]["parent"] = "geist"
        self.write_all()
        self.assert_failure_containing("unbekannten Parent")

    def test_missing_anchor_fails(self):
        bones = self.adult["minecraft:geometry"][0]["bones"]
        self.adult["minecraft:geometry"][0]["bones"] = [
            bone for bone in bones if bone["name"] != "hat_anchor"]
        self.write_all()
        self.assert_failure_containing("Pflicht-Anker fehlen")

    def test_uv_out_of_bounds_fails(self):
        cube = self.adult["minecraft:geometry"][0]["bones"][1]["cubes"][0]
        cube["uv"] = [12, 12]  # Box-UV einer 2x2x2-Box braucht 8x4 Texel
        self.write_all()
        self.assert_failure_containing("verlaesst die 16x16-Textur")

    def test_per_face_uv_out_of_bounds_fails(self):
        cube = self.adult["minecraft:geometry"][0]["bones"][1]["cubes"][0]
        cube["uv"] = {"north": {"uv": [14, 14], "uv_size": [4, 4]}}
        self.write_all()
        self.assert_failure_containing("verlaesst die 16x16-Textur")

    # --- Animationen ------------------------------------------------------

    def test_unknown_animation_bone_fails(self):
        self.animation["animations"]["animation.gooby.idle"]["bones"]["floof"] = {
            "rotation": {"0.0": [0, 0, 0]}}
        self.write_all()
        self.assert_failure_containing("Bone 'floof' existiert nicht")

    def test_bone_missing_in_baby_geo_fails(self):
        # neck_anchor gibt es nur im Adult-Geo — Referenz muss abgelehnt werden.
        self.animation["animations"]["animation.gooby.idle"]["bones"][
            "neck_anchor"] = {"rotation": {"0.0": [0, 0, 0]}}
        self.write_all()
        self.assert_failure_containing("existiert nicht in gooby_baby.geo.json")

    def test_bad_easing_fails(self):
        clip = self.animation["animations"]["animation.gooby.idle"]
        clip["bones"]["body"]["rotation"]["1.0"] = {
            "vector": [0, 0, 5], "easing": "easeSuperBounce"}
        self.write_all()
        self.assert_failure_containing("unbekanntes Easing")

    def test_bad_lerp_mode_fails(self):
        clip = self.animation["animations"]["animation.gooby.idle"]
        clip["bones"]["body"]["rotation"]["0.5"] = {
            "post": [0, 0, 0], "lerp_mode": "hermite"}
        self.write_all()
        self.assert_failure_containing("unbekannter lerp_mode")

    def test_keyframe_beyond_length_fails(self):
        clip = self.animation["animations"]["animation.gooby.idle"]
        clip["bones"]["body"]["rotation"]["7.5"] = [0, 0, 0]
        self.write_all()
        self.assert_failure_containing("Zeit ausserhalb")

    def test_bad_vector_fails(self):
        clip = self.animation["animations"]["animation.gooby.idle"]
        clip["bones"]["body"]["rotation"]["0.0"] = [0, 0]
        self.write_all()
        self.assert_failure_containing("muss 3 Zahlen haben")

    # --- Texturen ---------------------------------------------------------

    def test_missing_texture_fails(self):
        (self.tex_dir / "gooby_cocoa.png").unlink()
        self.assert_failure_containing("Textur fehlt")

    def test_wrong_png_dimensions_fail(self):
        Image.new("RGBA", (32, 32), (200, 160, 110, 255)).save(
            self.tex_dir / "gooby.png")
        self.assert_failure_containing("Groesse (32, 32)")

    def test_alpha_hole_in_used_region_fails(self):
        image = Image.new("RGBA", (16, 16), (200, 160, 110, 255))
        # Box-UV der 2x2x2-Box bei (0,0) belegt (0,0)-(8,4): Loch mittenrein.
        for x in range(2, 6):
            for y in range(2, 4):
                image.putpixel((x, y), (0, 0, 0, 0))
        image.save(self.tex_dir / "gooby.png")
        self.assert_failure_containing("deckend")

    # --- Blockbench -------------------------------------------------------

    def test_bbmodel_missing_group_fails(self):
        project = bbmodel_doc(self.adult)
        project["outliner"][0]["children"] = [
            child for child in project["outliner"][0]["children"]
            if not (isinstance(child, dict) and child["name"] == "body")]
        (self.bb_dir / "gooby.bbmodel").write_text(json.dumps(project))
        self.assert_failure_containing("Outliner-Gruppen fehlen")

    def test_bbmodel_element_count_mismatch_fails(self):
        project = bbmodel_doc(self.adult)
        project["elements"].append({"name": "geist", "uuid": "e-geist",
                                    "type": "cube"})
        (self.bb_dir / "gooby.bbmodel").write_text(json.dumps(project))
        self.assert_failure_containing("Cubes im Geo")

    def test_bbmodel_wrong_resolution_fails(self):
        project = bbmodel_doc(self.adult)
        project["resolution"] = {"width": 64, "height": 64}
        (self.bb_dir / "gooby.bbmodel").write_text(json.dumps(project))
        self.assert_failure_containing("resolution")


class RealRepositoryTest(unittest.TestCase):
    """Die eingecheckten Assets muessen den Validator immer bestehen."""

    def test_repository_assets_pass(self):
        root = Path(__file__).resolve().parent.parent
        errors, passed = validate_assets.run(str(root))
        self.assertEqual(errors, [], f"Repo-Assets invalide: {errors}")
        self.assertGreaterEqual(len(passed), 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
