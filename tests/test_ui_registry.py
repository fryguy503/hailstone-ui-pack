import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ui_registry", ROOT / "tools/ui_registry.py")
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class UiRegistryTests(unittest.TestCase):
    def test_clean_record_owns_all_twenty_actual_descriptors_without_startup_script(self):
        data = registry.record_bytes()
        blocks = registry.records(data)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0][0], "addon ui-pack ui")
        self.assertIn("autoupdate 0", blocks[0])
        catalog = json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))
        self.assertIn("version " + catalog["version"], blocks[0])
        owned = registry.managed_files(data)
        self.assertEqual(sum(name.endswith("/ui.ini") for name in owned), 20)
        self.assertTrue(all(name=="LICENSE" or name.startswith("ui/") for name in owned))
        self.assertIn("ui/default/zz_pack.lua", owned)
        with zipfile.ZipFile(ROOT / ("ui-pack-"+catalog["version"]+".zip")) as archive:
            self.assertEqual(set(owned), set(archive.namelist()))
            for name, checksum in owned.items():
                self.assertEqual(checksum, hashlib.sha256(archive.read(name)).hexdigest(), name)
        for skin in catalog["skins"]:
            name = f"ui/{skin['id']}/ui.ini"
            self.assertEqual(owned[name], hashlib.sha256((ROOT / name).read_bytes()).hexdigest())

    def test_merge_preserves_unrelated_records_and_signer_pin_but_disables_preview_updates(self):
        existing = ("hailstone-addons 1\n\naddon other plugin\nsource owner/other\n"
                    "notes do not alter me\ncaps ui\n\naddon UI-Pack ui\nsource owner/old\n"
                    f"key {'a' * 64}\nautoupdate 1\n").encode()
        merged = registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2", existing)
        self.assertIn(b"addon other plugin\nsource owner/other\nnotes do not alter me\ncaps ui", merged)
        self.assertIn(("key " + "a" * 64).encode(), merged)
        self.assertEqual(merged.count(b"addon ui-pack ui"), 1)
        self.assertNotIn(b"autoupdate 1", merged)

    def test_upscaler_ownership_and_pin_are_preserved_without_allowing_a_kind_change(self):
        provider = ("addon xess upscaler\nsource owner/xess\nversion 1.0.0\ncaps none\n"
                    f"key {'b' * 64}\nautoupdate 1\n"
                    f"file {'c' * 64} 128 xess.dll\n"
                    f"file {'d' * 64} 256 runtime.dll\n").encode()
        merged = registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2",
                                         b"hailstone-addons 1\n\n" + provider)
        self.assertIn(provider, merged)
        blocks = registry.records(merged)
        self.assertEqual([block[0] for block in blocks], ["addon xess upscaler", "addon ui-pack ui"])
        self.assertEqual(set(registry.managed_files(merged)), {"ui/test/ui.ini"})
        with self.assertRaisesRegex(ValueError, "existing ui-pack upscaler"):
            registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2",
                                    b"hailstone-addons 1\n\n" + provider.replace(b"addon xess ", b"addon ui-pack "))

    def test_malformed_ownership_records_and_kind_changes_fail_closed(self):
        malformed = [b"hailstone-addons 2\n", b"broken\n",
                     b"hailstone-addons 1\naddon ui-pack script\n",
                     b"hailstone-addons 1\naddon other plugin\nkey bad\n",
                     ("hailstone-addons 1\naddon other plugin\nfile " + "a" * 64 + " 1 ../escape\n").encode(),
                     b"hailstone-addons 1\naddon other plugin\naddon OTHER script\n"]
        for data in malformed:
            with self.subTest(data=data), self.assertRaises(ValueError):
                registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2", data)

    def test_existing_file_paths_and_sizes_match_client_registry_boundaries(self):
        paths = ["ui//empty.ini", "/absolute", "ui/trailing./test", "ui/trailing /test",
                 "ui/nul .txt", "ui/COM1.lua", "ui/lpt\u00b2.txt", "ui/CONOUT$.txt",
                 "ui/control\x01.ini", "ui/delete\x7f.ini", "ui/back\\slash", "ui/C:drive"]
        for path in paths:
            text = f"hailstone-addons 1\naddon other plugin\nfile {'a' * 64} 1 {path}\n".encode()
            with self.subTest(path=path), self.assertRaises(ValueError):
                registry.records(text)
        for size in ("18446744073709551616", "-1", "+1", "\u0661"):
            text = f"hailstone-addons 1\naddon other plugin\nfile {'a' * 64} {size} valid.ini\n".encode()
            with self.subTest(size=size), self.assertRaises(ValueError):
                registry.records(text)
        valid = f"hailstone-addons 1\naddon other plugin\nfile {'a' * 64} 18446744073709551615 valid.ini\n".encode()
        self.assertEqual(len(registry.records(valid)), 1)

    def test_identity_spacing_cannot_preserve_records_the_client_marks_unreadable(self):
        for identity in ("addon other  script", "addon  other script", "addon other script ",
                         "addon other\t script", "addon other script\t"):
            text = f"hailstone-addons 1\n{identity}\n".encode()
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2", text)

    def test_repeated_key_uses_the_same_final_pin_as_the_client_reader(self):
        old = (f"hailstone-addons 1\naddon ui-pack ui\nkey {'a' * 64}\nkey {'b' * 64}\n").encode()
        merged = registry.merge_registry({"ui/test/ui.ini": b"name=Test\n"}, "0.1.0-preview.2", old)
        self.assertNotIn(("key " + "a" * 64).encode(), merged)
        self.assertIn(("key " + "b" * 64).encode(), merged)


if __name__ == "__main__":
    unittest.main()
