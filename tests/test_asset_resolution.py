"""Exact-name candidate plans use synthetic metadata and image headers only."""

from pathlib import Path
import struct
import sys
import subprocess
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from resolve_assets import image_dimensions, resolve_assets


def tga(width, height, marker=0):
    header = bytearray(18)
    header[2] = 2
    struct.pack_into("<HH", header, 12, width, height)
    header[16] = 32
    return bytes(header) + bytes([marker])


class AssetResolutionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / "game"
        self.default = self.game / "uifiles" / "default"
        self.default.mkdir(parents=True)
        self.search = self.root / "candidate-sources"
        self.search.mkdir()
        (self.default / "EQUI.xml").write_text('''<XML>
          <TextureInfo item="missing.tga"><Size><CX>8</CX><CY>4</CY></Size></TextureInfo>
          <TextureInfo item="dormant.tga"><Size><CX>8</CX><CY>4</CY></Size></TextureInfo>
          <Ui2DAnimation item="Used"><Frames><Texture>missing.tga</Texture></Frames></Ui2DAnimation>
          <Ui2DAnimation item="Unused"><Frames><Texture>dormant.tga</Texture></Frames></Ui2DAnimation>
          <Screen item="Main"><Animation>Used</Animation></Screen>
        </XML>''', encoding="utf-8")

    def asset(self, name, content):
        path = self.search / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def test_identical_content_is_one_candidate_group_and_reachability_is_static(self):
        self.asset("first/MISSING.TGA", tga(8, 4))
        self.asset("second/missing.tga", tga(8, 4))
        plan = resolve_assets(self.game, search_roots=[self.search])
        asset = plan["assets"]["missing.tga"]
        self.assertEqual(asset["status"], "unique_same_name_candidate")
        self.assertEqual(len(asset["candidate_groups"]), 1)
        self.assertEqual(len(asset["candidate_groups"][0]["paths"]), 2)
        used = next(request for request in plan["requests"] if request["file"] == "missing.tga")
        dormant = next(request for request in plan["requests"] if request["file"] == "dormant.tga")
        self.assertEqual(used["static_reachability"], "screen_referenced")
        self.assertTrue(used["repair_eligible"])
        self.assertEqual(dormant["static_reachability"], "not_reachable_in_xml")
        self.assertFalse(dormant["repair_eligible"])

    def test_distinct_content_is_ambiguous_even_when_dimensions_match(self):
        self.asset("first/missing.tga", tga(8, 4, 0))
        self.asset("second/missing.tga", tga(8, 4, 1))
        plan = resolve_assets(self.game, search_roots=[self.search])
        self.assertEqual(plan["assets"]["missing.tga"]["status"], "ambiguous")
        self.assertFalse(any(request["repair_eligible"] for request in plan["requests"]))

    def test_lookalike_names_and_wrong_dimensions_are_not_eligible(self):
        self.asset("missing-other.tga", tga(8, 4))
        plan = resolve_assets(self.game, search_roots=[self.search])
        self.assertEqual(plan["assets"]["missing.tga"]["status"], "unresolved")
        self.asset("missing.tga", tga(16, 16))
        plan = resolve_assets(self.game, search_roots=[self.search])
        used = next(request for request in plan["requests"] if request["file"] == "missing.tga")
        self.assertFalse(used["candidate_dimensions_match"])
        self.assertFalse(used["repair_eligible"])

    def test_header_dimensions_and_invalid_headers(self):
        self.assertEqual(image_dimensions(self.asset("size.tga", tga(37, 29))), (37, 29))
        png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 30, 20)
        self.assertEqual(image_dimensions(self.asset("size.png", png)), (30, 20))
        dds = b"DDS " + struct.pack("<IIII", 124, 0, 11, 17)
        self.assertEqual(image_dimensions(self.asset("size.dds", dds)), (17, 11))
        self.assertIsNone(image_dimensions(self.asset("broken.tga", b"not an image")))

    def test_documented_game_dir_option_and_read_only_output_guard(self):
        tool = Path(__file__).resolve().parents[1] / "tools" / "resolve_assets.py"
        result = subprocess.run([sys.executable, str(tool), "--game-dir", str(self.game)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.game / "candidates.json"
        result = subprocess.run([sys.executable, str(tool), "--game-dir", str(self.game),
                                 "--output", str(output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
