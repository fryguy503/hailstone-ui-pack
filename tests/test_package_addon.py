import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package_addon", ROOT / "tools" / "package_addon.py")
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class PackageTests(unittest.TestCase):
    def test_repository_download_matches_manifest_and_sources(self):
        text = (ROOT / "hailstone-addon.txt").read_text()
        version = json.loads((ROOT / "skins.json").read_text())["version"]
        self.assertIn("version " + version + "\n", text,
                      "Refresh the repository portable archive/manifest after freezing the Lua runtime")
        self.assertIn("kind ui\n", text)
        records = [line.split() for line in text.splitlines() if line.startswith("package ")]
        self.assertEqual(len(records), 1)
        _, platform, size, sha, name = records[0]
        self.assertEqual(platform, "any")
        self.assertEqual(Path(name).name, name)
        archive = ROOT / name
        data = archive.read_bytes()
        self.assertEqual(len(data), int(size))
        self.assertEqual(hashlib.sha256(data).hexdigest(), sha)
        sources = dict(packager.sources(ROOT))
        with zipfile.ZipFile(archive) as z:
            self.assertIsNone(z.testzip())
            self.assertEqual(sorted(z.namelist()), sorted(sources))
            for member, path in sources.items():
                self.assertEqual(z.read(member), path.read_bytes(), member)

    def test_manifest_hash_and_determinism(self):
        with tempfile.TemporaryDirectory() as tmp:
            version = json.loads((ROOT / "skins.json").read_text())["version"]
            manifest, archive = packager.package(version, Path(tmp) / "one")
            _, other = packager.package(version, Path(tmp) / "two")
            self.assertEqual(archive.read_bytes(), other.read_bytes())
            text = manifest.read_text()
            self.assertIn(f"package any {archive.stat().st_size} {hashlib.sha256(archive.read_bytes()).hexdigest()} {archive.name}", text)
            self.assertIn("kind ui\n", text)
            self.assertIn("caps none\n", text)
            self.assertNotIn("signature", text)
            with zipfile.ZipFile(archive) as z:
                self.assertEqual(len(z.namelist()), len(packager.sources(ROOT)))
                self.assertGreater(len(z.namelist()), 1 + 20 * (2 + len(packager.RUNTIME)))
                self.assertNotIn("init.lua", z.namelist())
                self.assertIn("ui/DuxaUI-stock/ui.ini", z.namelist())
                self.assertIn("ui/default/lib/pregame.lua", z.namelist())
                self.assertIn("ui/default/lib/pack_source_windows.lua", z.namelist())
                self.assertEqual(len([n for n in z.namelist() if n.endswith("/ui.ini")]), 20)
                self.assertEqual(len([n for n in z.namelist() if n.endswith("/lib/pack_profile.lua")]), 20)
                self.assertEqual(sum(n.endswith("/lib/layouts/index.lua") for n in z.namelist()), 20)
                self.assertGreater(sum("/lib/layouts/buckets/" in n for n in z.namelist()), 0)
                inventory = json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))
                expected_images = {"ui/default/assets/" + name for name in inventory["assets"]}
                self.assertTrue(expected_images, "the portable release must include its UI artwork")
                self.assertEqual({name for name in z.namelist() if name.endswith(".png")}, expected_images)
                notices = {"ui/default/THIRD_PARTY_NOTICES.md",
                           "ui/default/licenses/Nemesis-GPL-2.0.txt"}
                self.assertTrue(all(n == "LICENSE" or n in notices or n.endswith(("/ui.ini", ".lua"))
                                    or n.startswith("ui/default/assets/") and n.endswith(".png")
                                    for n in z.namelist()))
                self.assertFalse(any("/compiled/" in n or n.startswith("ui-data/") for n in z.namelist()))
                self.assertLessEqual(len(z.namelist()), 4096)
                self.assertLessEqual(sum(i.file_size for i in z.infolist()), 64 * 1024 * 1024)
                self.assertTrue(all(i.file_size <= 4 * 1024 * 1024 for i in z.infolist()
                                    if i.filename.endswith(".lua")))
                for name in z.namelist():
                    if name.endswith(".png"):
                        self.assertTrue(z.read(name).startswith(b"\x89PNG\r\n\x1a\n"), name)
                        self.assertEqual(hashlib.sha256(z.read(name)).hexdigest(),
                                         inventory["assets"][Path(name).name]["sha256"], name)
                self.assertIn(b"base=default\n", z.read("ui/DuxaUI-stock/ui.ini"))
                self.assertIn(b"base=builtin:modern\n", z.read("ui/default/ui.ini"))
                for name in z.namelist():
                    if name.endswith("/ui.ini"):
                        self.assertNotIn(b"runtime=sidl", z.read(name))
                        self.assertNotIn(b"skin=", z.read(name))
                self.assertTrue(all(i.date_time == (1980, 1, 1, 0, 0, 0) for i in z.infolist()))

    def test_bad_version_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                packager.package("../../bad", Path(tmp))


if __name__ == "__main__":
    unittest.main()
