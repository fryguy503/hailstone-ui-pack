"""Archive listing fixtures contain only original synthetic names and metadata."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from scan_archives import discover_archives, inspect_archive, inventory_requests, member_skin, parse_listing, scan_archives


LISTING = """Path = Game\\UIFiles\\one-stock
Folder = +
Size = 0

Path = Game\\UIFiles\\ONE-stock\\Missing.PNG
Size = 123
CRC = ABCD1234

Path = Game/UIFiles/other-stock/missing.png
Folder = -
Size = 456
CRC = FF001122

Path = Game/UIFiles/one-stock/nested.zip
Size = 20

Path = unrelated.png
Size = 8
"""


class ArchiveScanTest(unittest.TestCase):
    def test_missing_names_are_basename_exact_and_case_insensitive(self):
        requests = inventory_requests({"skins": [{"name": "one-stock", "missing_texture_files": [
            {"file": "subfolder/Missing.PNG"}, {"file": "other.dds"}]}]}, ["Extra.TGA", "missing.png"])
        self.assertEqual(sorted(requests), ["extra.tga", "missing.png", "other.dds"])
        self.assertEqual(requests["missing.png"], [{"skin": "one-stock", "file": "subfolder/Missing.PNG"}])

    def test_listing_ignores_directories_and_preserves_member_metadata(self):
        members = parse_listing(LISTING)
        self.assertEqual(len(members), 4)
        self.assertEqual(members[0], {"member": "Game\\UIFiles\\ONE-stock\\Missing.PNG", "bytes": 123, "crc": "ABCD1234"})
        self.assertEqual(member_skin(members[0]["member"]), "ONE-stock")
        self.assertIsNone(member_skin("unrelated.png"))

    def test_listing_does_not_confuse_matching_basename_with_matching_skin(self):
        requests = {"missing.png": [{"skin": "one-stock", "file": "missing.png"}]}
        completed = subprocess.CompletedProcess([], 0, LISTING, "")
        with patch("scan_archives.subprocess.run", return_value=completed) as run:
            result = inspect_archive(Path("original.zip"), requests, "7z")
        self.assertEqual(result["member_count"], 4)
        self.assertEqual(len(result["matches"]), 2)
        self.assertEqual(len(result["matches"][0]["same_skin_requests"]), 1)
        self.assertEqual(result["matches"][1]["same_skin_requests"], [])
        self.assertEqual(result["nested_archives"], ["Game/UIFiles/one-stock/nested.zip"])
        self.assertEqual(run.call_args.args[0][1], "l")
        self.assertEqual(run.call_args.kwargs["input"], "")

    def test_overlapping_search_roots_deduplicate_archives_and_keep_failures_visible(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "one.zip").write_bytes(b"synthetic")
            (root / "skip.png").write_bytes(b"synthetic")
            self.assertEqual(discover_archives([root, root / "one.zip"]), [root / "one.zip"])
            with patch("scan_archives.subprocess.run", side_effect=subprocess.TimeoutExpired("7z", 2)):
                result = scan_archives([root], {"missing.png": []}, "7z", workers=1, timeout=2)
            self.assertEqual(result["successful_archives"], 0)
            self.assertEqual(result["missing_basenames"], ["missing.png"])
            self.assertIn("timed out", result["archives"][0]["error"])
            with self.assertRaises(ValueError):
                scan_archives([root], {}, "7z", workers=0)


if __name__ == "__main__":
    unittest.main()
