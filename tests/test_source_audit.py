"""Synthetic source trees exercise fallback and diagnostics without game assets."""

from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from audit_sources import audit_skin, discover_skins


class SourceAuditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.ui = self.game / "uifiles"
        self.ui.mkdir()

    def write(self, skin, relative, text):
        path = self.ui / skin / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def test_case_insensitive_nested_fallback_and_typed_pieces(self):
        self.write("default", "EQUI.xml", '<XML><Composite><Include>Nested/window.xml</Include></Composite></XML>')
        self.write("default", "nested/Window.xml", '<XML><Screen item="Main"><Pieces>Screen:Inner</Pieces></Screen><Screen item="Inner"/></XML>')
        self.write("one-stock", "NESTED/window.XML", '<XML><Screen item="Main"><Pieces>Screen:Inner</Pieces></Screen><Screen item="Inner"/><Label item="Extra"/></XML>')
        result = audit_skin(self.game, "ONE-STOCK")
        self.assertEqual(result["name"], "one-stock")
        self.assertEqual(result["active_xml_count"], 2)
        self.assertEqual(result["inherited_xml_count"], 1)
        self.assertEqual(result["screen_count"], 2)
        self.assertEqual(result["root_screen_count"], 1)
        self.assertEqual(result["missing_piece_references"], [])
        self.assertEqual(result["definitions_by_type"]["Label"], 1)
        self.assertNotIn(str(self.game), str(result))

    def test_cycle_missing_include_and_traversal_are_reported(self):
        self.write("default", "EQUI.xml", '<XML><Composite><Include>A.xml</Include><Include>missing.xml</Include><Include>../outside.xml</Include></Composite></XML>')
        self.write("default", "a.xml", '<XML><Composite><Include>EQUI.xml</Include></Composite></XML>')
        result = audit_skin(self.game, "default")
        self.assertEqual(result["active_xml_count"], 2)
        self.assertEqual(result["missing_includes"], [{"file": "missing.xml", "from": "EQUI.xml"}])
        self.assertEqual(len(result["invalid_includes"]), 1)
        self.assertEqual(len(result["include_cycles"]), 1)

    def test_optional_parse_errors_and_texture_diagnostics(self):
        self.write("default", "EQUI.xml", '<XML><TextureInfo item="missing.tga"/><Ui2DAnimation item="Anim"><Frames><Texture>missing.tga</Texture></Frames></Ui2DAnimation><Screen item="Main"><Pieces>Button:Absent</Pieces></Screen></XML>')
        self.write("test-stock", "unused.xml", '<XML><Broken></XML>')
        result = audit_skin(self.game, "test-stock")
        self.assertEqual(result["malformed_xml"][0]["active"], False)
        self.assertEqual(result["missing_texture_files"][0]["file"], "missing.tga")
        self.assertEqual(result["missing_texture_files"][0]["referenced_by_animation"], True)
        self.assertEqual(result["missing_piece_references"], [{"file": "EQUI.xml", "reference": "Button:Absent"}])

    def test_empty_source_is_explicit_and_discovery_filters(self):
        self.write("default", "EQUI.xml", '<XML><Screen item="Main"/></XML>')
        for name in ["default_old", "rof2velious", "test-stock", "unrelated"]:
            (self.ui / name).mkdir()
        self.assertEqual(discover_skins(self.game), ["default", "default_old", "test-stock"])
        result = audit_skin(self.game, "rof2velious")
        self.assertTrue(result["source_empty"])
        self.assertEqual(result["screen_count"], 1)
        self.assertTrue(any("empty" in item for item in result["warnings"]))

    def test_missing_source_does_not_claim_fidelity(self):
        self.write("default", "EQUI.xml", '<XML/>')
        result = audit_skin(self.game, "missing-stock")
        self.assertFalse(result["source_present"])
        self.assertTrue(any("missing" in item for item in result["warnings"]))
        with self.assertRaises(ValueError):
            audit_skin(self.game, "../default")

    def test_dtd_and_entities_are_rejected_before_expansion(self):
        self.write("default", "EQUI.xml", '<!DOCTYPE XML [<!ENTITY sample "expanded">]><XML><Label item="Text">&sample;</Label></XML>')
        result = audit_skin(self.game, "default")
        self.assertEqual(result["active_xml_count"], 0)
        self.assertEqual(len(result["malformed_xml"]), 1)
        self.assertIn("DTD", result["malformed_xml"][0]["error"])

    def test_documented_game_dir_option_and_read_only_output_guard(self):
        self.write("default", "EQUI.xml", '<XML/>')
        tool = Path(__file__).resolve().parents[1] / "tools" / "audit_sources.py"
        result = subprocess.run([sys.executable, str(tool), "--game-dir", str(self.game)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.game / "report.json"
        result = subprocess.run([sys.executable, str(tool), "--game-dir", str(self.game),
                                 "--output", str(output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_include_depth_is_bounded_and_reported(self):
        self.write("default", "EQUI.xml", '<XML><Include>part0.xml</Include></XML>')
        for index in range(70):
            self.write("default", f"part{index}.xml", f'<XML><Include>part{index + 1}.xml</Include></XML>')
        result = audit_skin(self.game, "default")
        self.assertEqual(len(result["invalid_includes"]), 1)
        self.assertIn("limit", result["invalid_includes"][0]["reason"])
        self.assertLess(result["active_xml_count"], 70)


if __name__ == "__main__":
    unittest.main()
