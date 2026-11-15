"""Package-boundary checks; synthetic modules do not establish renderer parity."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


generator = module("generate_catalog")
packager = module("package_addon")


class LuaScaffoldTests(unittest.TestCase):
    def fixture(self, root, runtime=True):
        (root / "skins.json").write_bytes((ROOT / "skins.json").read_bytes())
        (root / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
        for name, content in generator.generated_files(root).items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
        if runtime:
            for name in packager.RUNTIME.values():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("-- Synthetic package fixture, no renderer implementation.\nreturn {}\n",
                                encoding="utf-8", newline="\n")

    def test_twenty_lua_entries_use_modern_base_and_original_profile_metadata(self):
        entries = generator.descriptors()
        self.assertEqual(len(entries), 20)
        for name, text in entries.items():
            self.assertIn("base=builtin:modern\n" if name == "ui/default/ui.ini" else "base=default\n", text)
            self.assertNotIn("runtime=sidl", text)
            self.assertNotIn("skin=", text)
        profiles = generator.generated_files()
        self.assertEqual(len(profiles), 40)
        self.assertIn('source="DuxaUI-stock"', profiles["ui/DuxaUI-stock/lib/pack_profile.lua"])
        self.assertIn('index="lib/compiled/index.lua"', profiles["ui/default/lib/pack_profile.lua"])

    def test_incomplete_runtime_cannot_be_packaged_as_a_finished_ui(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root, runtime=False)
            with self.assertRaisesRegex(ValueError, "Missing addon source"):
                packager.sources(root)

    def test_portable_lua_package_excludes_player_compilation_and_art(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            private = root / "ui/default/lib/compiled/index.lua"
            private.parent.mkdir(parents=True)
            private.write_text("return {player_layout=true}\n")
            (root / "ui/default/source.xml").write_text("synthetic local layout")
            (root / "ui/default/art.tga").write_bytes(b"synthetic local art")
            _, archive = packager.package("0.2.0-preview.1", root / "output", root)
            with zipfile.ZipFile(archive) as z:
                self.assertIsNone(z.testzip())
                self.assertEqual(len(z.namelist()), 241)
                self.assertIn("ui/default/lib/pack_renderer.lua", z.namelist())
                self.assertIn("ui/default/zz_pack.lua", z.namelist())
                self.assertNotIn("ui/default/lib/compiled/index.lua", z.namelist())
                self.assertNotIn("ui/default/source.xml", z.namelist())
                self.assertNotIn("ui/default/art.tga", z.namelist())


if __name__ == "__main__":
    unittest.main()
