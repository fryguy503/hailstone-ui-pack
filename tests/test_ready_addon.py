"""Exercise the real downloadable addon with an empty user-data installation."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LUA = os.environ.get("HAILSTONE_LUA") or shutil.which("lua5.4") or shutil.which("lua54") or shutil.which("lua")


@unittest.skipUnless(LUA, "Lua interpreter unavailable; set HAILSTONE_LUA")
class ReadyAddonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("ready_package", ROOT / "tools/package_addon.py")
        cls.packager = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.packager)
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.catalog = json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))
        _, cls.archive = cls.packager.package(cls.catalog["version"], cls.root / "download")

    def boot(self, data, *, poison=False):
        addon = data / "ui-addons/ui-pack"
        addon.mkdir(parents=True)
        with zipfile.ZipFile(self.archive) as archive:
            # The package builder supplies the validated list of scoped paths.
            self.assertEqual(set(archive.namelist()), set(dict(self.packager.sources(ROOT))))
            for entry in archive.infolist():
                destination = addon / entry.filename
                self.assertTrue(destination.resolve().is_relative_to(addon.resolve()))
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(entry))
        before = {str(p.relative_to(data)): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in data.rglob("*") if p.is_file()}
        if poison:
            for skin in self.catalog["skins"]:
                for prefix in ("lib/compiled", "lib/layouts"):
                    path = data / "ui-data" / ("addon.ui-pack." + skin["id"].lower()) / prefix / "index.lua"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text('error("stale private layout must never be loaded")\n', encoding="utf-8")
            before = {str(p.relative_to(data)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in data.rglob("*") if p.is_file()}
        else:
            self.assertFalse((data / "ui-data").exists())
        self.assertFalse((data / "uifiles").exists(), "fixture must not provide game XML")
        completed = subprocess.run(
            [LUA, str(ROOT / "tests/lua_clean_addon_boot_test.lua"), str(addon),
             ",".join(skin["id"] for skin in self.catalog["skins"])],
            cwd=data, capture_output=True, text=True, encoding="utf-8", timeout=120)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertRegex(completed.stdout, r"Clean addon boot: 20 skins, \d+ layouts, \d+ assertions passed")
        after = {str(p.relative_to(data)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in data.rglob("*") if p.is_file()}
        self.assertEqual(before, after, "startup must not generate or rewrite local layout data")
        return completed.stdout

    def test_normal_addon_download_bootstraps_all_twenty_skins_without_setup(self):
        self.boot(self.root / "fresh-install")

    def test_stale_private_layouts_cannot_replace_the_installed_addon_definitions(self):
        self.boot(self.root / "old-private-install", poison=True)


if __name__ == "__main__":
    unittest.main()
