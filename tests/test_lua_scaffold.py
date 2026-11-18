"""Package-boundary checks; synthetic modules do not establish renderer parity."""
import importlib.util
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "tools" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


generator = module("generate_catalog")
packager = module("package_addon")
layout_literals = module("portable_layouts")
fixture_spec = importlib.util.spec_from_file_location("portable_fixture", ROOT / "tests/portable_fixture.py")
portable_fixture = importlib.util.module_from_spec(fixture_spec)
fixture_spec.loader.exec_module(portable_fixture)


class LuaScaffoldTests(unittest.TestCase):
    def fixture(self, root, runtime=True):
        (root / "skins.json").write_bytes((ROOT / "skins.json").read_bytes())
        (root / "LICENSE").write_bytes((ROOT / "LICENSE").read_bytes())
        for name, content in generator.generated_files(root).items():
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
        portable_fixture.layouts(root)
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
        self.assertIn('index="lib/layouts/index.lua"', profiles["ui/default/lib/pack_profile.lua"])

    def test_incomplete_runtime_cannot_be_packaged_as_a_finished_ui(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root, runtime=False)
            with self.assertRaisesRegex(ValueError, "Missing addon source"):
                packager.sources(root)

    def test_portable_package_includes_layouts_without_local_compilation_or_private_files(self):
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
                self.assertEqual(len(z.namelist()), 1 + 20 * (4 + len(packager.RUNTIME)))
                self.assertIn("ui/default/lib/pack_renderer.lua", z.namelist())
                self.assertIn("ui/default/zz_pack.lua", z.namelist())
                self.assertIn("ui/default/lib/layouts/index.lua", z.namelist())
                self.assertEqual(sum(name.endswith("/lib/layouts/index.lua") for name in z.namelist()), 20)
                self.assertEqual(sum("/lib/layouts/buckets/" in name for name in z.namelist()), 20)
                self.assertNotIn("ui/default/lib/compiled/index.lua", z.namelist())
                self.assertNotIn("ui/default/source.xml", z.namelist())
                self.assertNotIn("ui/default/art.tga", z.namelist())

    def test_missing_packaged_index_is_rejected_before_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            (root / "layouts/default/index.lua").unlink()
            with self.assertRaises((ValueError, FileNotFoundError)):
                packager.package("0.2.0-preview.3", root / "output", root)

    def test_missing_referenced_bucket_is_rejected_before_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            bucket = next((root / "layouts/default/buckets").glob("*.lua"))
            bucket.unlink()
            with self.assertRaises((ValueError, FileNotFoundError)):
                packager.package("0.2.0-preview.3", root / "output", root)

    def referenced_image(self, root):
        index_path = root / "layouts/default/index.lua"
        index = layout_literals.read_lua(index_path)
        logical, name = "uifiles/test.png", "a" * 64 + ".png"
        relative = "assets/" + name
        index["images"] = {"WindowArt": {"path": logical, "interface_path": relative}}
        index_path.write_text("return " + layout_literals.literal(index) + "\n", encoding="utf-8")
        data = self.png()
        manifest = {"schema": 1, "kind": "portable-ui-raster-art", "unresolved": [],
                    "assets": {name: {"width": 1, "height": 1, "bytes": len(data),
                                      "sha256": hashlib.sha256(data).hexdigest()}},
                    "resources": {logical: {"interface_path": relative}}}
        (root / "assets").mkdir()
        (root / "assets/manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        for notice in ("THIRD_PARTY_NOTICES.md", "licenses/Nemesis-GPL-2.0.txt"):
            path = root / notice
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("Synthetic fixture attribution.\n", encoding="utf-8")
        return root / relative

    @staticmethod
    def png(raw=b"\0\0\0\0\0", compressed=None):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw) if compressed is None else compressed) + chunk(b"IEND", b""))

    def test_missing_referenced_png_is_rejected_before_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            self.referenced_image(root)
            with self.assertRaisesRegex(ValueError, "Missing addon source"):
                packager.package("0.2.0-preview.3", root / "output", root)

    def test_corrupt_referenced_png_is_rejected_before_publishing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            image = self.referenced_image(root)
            image.write_bytes(b"\x89PNG\r\n\x1a\ntruncated")
            with self.assertRaisesRegex(ValueError, "Incomplete UI PNG"):
                packager.package("0.2.0-preview.3", root / "output", root)

    def test_crc_correct_corrupt_png_pixels_are_rejected(self):
        payload = b"retained source metadata"
        metadata = (struct.pack(">I", len(payload)) + b"iCCP" + payload
                    + struct.pack(">I", zlib.crc32(b"iCCP" + payload)))
        plain = self.png()
        cases = {"bad-zlib": self.png(compressed=b"not zlib"),
                 "bad-filter": self.png(raw=b"\x05\0\0\0\0"),
                 "short-pixels": self.png(raw=b"\0\0\0\0"),
                 "extra-pixels": self.png(raw=b"\0\0\0\0\0\0"),
                 "trailing-stream": self.png(compressed=zlib.compress(b"\0" * 5) + b"trailing"),
                 "retained-metadata": plain[:-12] + metadata + plain[-12:]}
        for name, data in cases.items():
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmp:
                image = Path(tmp) / "image.png"
                image.write_bytes(data)
                with self.assertRaisesRegex(ValueError, "UI PNG"):
                    packager._png(image)

    def test_valid_rgba_png_pixels_are_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            image = Path(tmp) / "image.png"
            image.write_bytes(self.png())
            self.assertEqual(packager._png(image)["width"], 1)

    def test_artwork_cannot_be_silently_dropped_from_an_index(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            self.referenced_image(root).write_bytes(self.png())
            path = root / "layouts/default/index.lua"
            index = layout_literals.read_lua(path)
            del index["images"]["WindowArt"]["interface_path"]
            path.write_text("return " + layout_literals.literal(index), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from inventory"):
                packager.sources(root)

    def test_png_hash_must_match_artwork_inventory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            self.referenced_image(root).write_bytes(self.png())
            path = root / "assets/manifest.json"
            manifest = json.loads(path.read_text())
            next(iter(manifest["assets"].values()))["sha256"] = "0" * 64
            path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "differs from artwork inventory"):
                packager.sources(root)

    def test_artwork_requires_attribution_inputs(self):
        for notice in ("THIRD_PARTY_NOTICES.md", "licenses/Nemesis-GPL-2.0.txt"):
            with self.subTest(notice=notice), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                self.fixture(root)
                self.referenced_image(root).write_bytes(self.png())
                (root / notice).unlink()
                with self.assertRaisesRegex(ValueError, "Missing addon source"):
                    packager.sources(root)

    def test_escaped_private_reference_is_rejected_after_literal_decoding(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            path = root / "layouts/default/index.lua"
            index = layout_literals.read_lua(path)
            index["caption"] = "bastion"
            text = layout_literals.literal(index).replace('"bastion"', '"\\098astion"')
            path.write_text("return " + text, encoding="utf-8")
            self.assertNotIn(b"bastion", path.read_bytes().lower())
            with self.assertRaisesRegex(ValueError, "Private reference"):
                packager.sources(root)

    def test_private_build_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.fixture(root)
            path = root / "layouts/default/index.lua"
            index = layout_literals.read_lua(path)
            index["provenance"] = {"source_xml": "original.xml"}
            path.write_text("return " + layout_literals.literal(index), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "Private build metadata"):
                packager.sources(root)


if __name__ == "__main__":
    unittest.main()
