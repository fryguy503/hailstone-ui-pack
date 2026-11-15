import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package_preview", ROOT / "tools" / "package_preview.py")
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
REVISION = "a" * 40


def write(path, data=b"fixture"):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def pe():
    data = bytearray(128)
    data[:2] = b"MZ"
    struct.pack_into("<I", data, 60, 64)
    data[64:68] = b"PE\0\0"
    struct.pack_into("<H", data, 68, 0x8664)
    return bytes(data)


class PreviewPackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source, self.client, self.addon, self.out, self.seed, self.crt, self.game = (
            root / x for x in ("source", "build", "addon", "output", "seed", "crt", "game"))
        for name in ("hailstone.exe", "SDL3.dll", "zlib1.dll"):
            write(self.client / name, pe())
        for name in preview.CRT_DLLS:
            write(self.crt / name, pe())
        for name in preview.LEGAL_FILES:
            write(self.source / name, b"Client GPL license and notices")
        for pack in preview.PACKS:
            for name, data in (("ui.ini", b"name=Fixture\n"),
                               ("window.lua", b"return true\n"), ("lib/drawing.lua", b"return {}\n")):
                write(self.source / "ui" / pack / name, data)
                write(self.client / "ui" / pack / name, data)
        for name in ("icons/logo.png", "pictures/loading.jpg", "flora/default.txt"):
            write(self.source / name)
            write(self.client / name)
        write(self.client / "shaders/actor.vert.spv", b"\x03\x02\x23\x07fixture")
        catalog = json.loads((ROOT / "skins.json").read_text())
        write(self.addon / "skins.json", json.dumps(catalog).encode())
        for skin in catalog["skins"]:
            for name in ("ui.ini", "lib/pack_profile.lua"):
                relative = Path("ui") / skin["id"] / name
                write(self.addon / relative, (ROOT / relative).read_bytes())
        for name in preview.tool_module("package_addon").RUNTIME.values():
            write(self.addon / name, (ROOT / name).read_bytes())
        write(self.addon / "LICENSE", b"Companion MIT license")
        write(self.game / "uifiles/default/EQUI.xml", b"unshipped synthetic game layout")
        plan = {name: path.read_bytes() for name, path in preview.companion_files(self.addon).items()}
        for skin in catalog["skins"]:
            prefix = "ui-data/addon.ui-pack." + skin["id"].lower() + "/lib/compiled/"
            plan[prefix + "index.lua"] = b'return {version=2,storage="buckets-v1",windows={}}\n'
            plan[prefix + "buckets/00.lua"] = b"return {}\n"
        self.repair = "servers/test/assets/uifiles/delta-stock/target.png"
        plan[self.repair] = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 8, 8)
        self.report = {"schema": 2, "runtime": "lua", "version": catalog["version"],
                       "source_game_dir": str(self.game), "personal_config": "private fixture content",
                       "skins": [{"id": skin["id"], "source": skin["source"], "present": True} for skin in catalog["skins"]],
                       "asset_repairs": [{"skin": "delta-stock", "target": "target.png",
                                          "sha256": hashlib.sha256(plan[self.repair]).hexdigest(), "origin": "reviewed synthetic image"}]}
        self.ledger = {"schema": 1, "version": catalog["version"], "report": self.report,
                       "files": {name: hashlib.sha256(data).hexdigest() for name, data in plan.items()}}
        for name, data in plan.items():
            write(self.seed / name, data)
        self.write_ledger()

    def write_ledger(self):
        write(self.seed / "addons/ui-pack-local-install.json", json.dumps(self.ledger).encode())

    def package(self, **kwargs):
        return preview.package(self.client, self.source, REVISION, kwargs.get("out", self.out), self.addon,
                               compiled_data_dir=kwargs.get("compiled_data_dir", self.seed), crt_dir=self.crt,
                               client_sha256=kwargs.get("client_sha256"))

    def test_only_shipped_allowlisted_paths_and_companion_are_packaged(self):
        for name in ("hailstone.ini", "servers/private/server.ini", "servers/private/characters/Player/UI.ini",
                     "scripts/personal/init.lua", "plugins/private.dll", "addons/installed.txt", "logs/hailstone.log",
                     "screenshots/avatar.png", "cache/session.bin", "settings/passwords.json", "credentials.key",
                     "hailstone.pdb", "hailstone.ilk", "private.dll", "maps/personal.txt", "source.cpp",
                     "icons/personal.png", "pictures/personal.jpg", "flora/custom.txt", "ui/custom/personal.lua",
                     "ui/modern/passwords.txt", "ui/modern/settings/private.lua"):
            write(self.client / name, b"private fixture content")
        # Even settings accidentally present in the source tree are outside the shipped UI allowlist.
        write(self.source / "ui/modern/settings/private.lua", b"private fixture content")
        write(self.addon / "init.lua", b"private fixture content")
        for name in ("hailstone.ini", "addons/installed.txt", "settings/passwords.json", "servers/private/server.ini", "logs/private.log"):
            write(self.seed / name, b"private fixture content")
        write(self.client / "LICENSE", b"Wrong unrelated MIT license")
        archive = self.package()
        with zipfile.ZipFile(archive) as z:
            names = set(z.namelist())
            self.assertIn("hailstone.exe", names)
            self.assertEqual({name.split("/")[1] for name in names if name.startswith("ui/")}, {"modern", "gamepad"})
            self.assertTrue(set(preview.CRT_DLLS) <= names)
            self.assertIn("ui-addons/ui-pack/ui/default/ui.ini", names)
            self.assertFalse(any(name.startswith("scripts/") for name in names))
            self.assertEqual(len([name for name in names if name.startswith("ui-addons/") and name.endswith("/ui.ini")]), 20)
            expected_code = 1 + 20 * (2 + len(preview.tool_module("package_addon").RUNTIME))
            self.assertEqual(len([name for name in names if name.startswith("ui-addons/ui-pack/")]), expected_code)
            self.assertEqual(len([name for name in names if name.startswith("ui-data/")]), 40)
            self.assertIn(self.repair, names)
            self.assertEqual(z.read("LICENSE"), b"Client GPL license and notices")
            self.assertEqual(z.read("ui-addons/ui-pack/LICENSE"), b"Companion MIT license")
            registry = z.read("addons/installed.txt")
            self.assertEqual(registry, z.read("addons/installed.bak.txt"))
            self.assertIn(b"addon ui-pack ui\n", registry)
            self.assertIn(b"autoupdate 0\n", registry)
            self.assertNotIn(b"kind script", registry)
            for line in registry.decode().splitlines():
                if not line.startswith("file "):
                    continue
                _, digest, size, path = line.split(" ", 3)
                data = z.read("ui-addons/ui-pack/" + path)
                self.assertEqual(hashlib.sha256(data).hexdigest(), digest)
                self.assertEqual(len(data), int(size))
            self.assertTrue(all(b"private fixture content" not in z.read(name) for name in names))
            self.assertNotIn("maps/personal.txt", names)
            metadata = json.loads(z.read("preview-manifest.json"))
            self.assertEqual(metadata["client_revision"], REVISION)
            self.assertIsNone(metadata["client_support"])
            self.assertFalse(metadata["browser_helper_enabled"])
            self.assertFalse(metadata["live_gameplay_verified"])
            self.assertIn(b"browser helper is not included", z.read("README-UI-PACK-PREVIEW.txt"))
            self.assertIn("Play-UI-Pack.cmd", names)
            config = z.read("hailstone.ini")
            self.assertIn(b"ui.name=addon.ui-pack.default\n", config)
            self.assertIn(str(self.game.resolve()).encode(), config)
            copied_ledger = json.loads(z.read("addons/ui-pack-local-install.json"))
            self.assertNotIn("personal_config", copied_ledger["report"])
            self.assertNotIn("source_game_dir", copied_ledger["report"])
            self.assertEqual(copied_ledger["files"], self.ledger["files"])
            self.assertEqual(metadata["compiled_seed"]["interfaces"], 20)
            for name, entry in metadata["files"].items():
                self.assertEqual(entry["sha256"], hashlib.sha256(z.read(name)).hexdigest())
                self.assertEqual(entry["size"], len(z.read(name)))

    def test_support_hashes_and_deterministic_archive(self):
        support = {"base_commit": "b" * 40, "feature_commit": REVISION, "patch_sha256": "c" * 64,
                   "private_url": "https://private.example.invalid", "local_path": "C:/Users/Someone"}
        write(self.addon / "client/support.json", json.dumps(support).encode())
        first = self.package()
        second = self.package(out=self.out.parent / "other-output")
        self.assertEqual(first.read_bytes(), second.read_bytes())
        self.assertIn(hashlib.sha256(first.read_bytes()).hexdigest(), first.with_suffix(".zip.sha256").read_text())
        with zipfile.ZipFile(first) as z:
            metadata = json.loads(z.read("preview-manifest.json"))
            self.assertEqual(metadata["client_support"], {key: support[key] for key in ("base_commit", "feature_commit", "patch_sha256")})
            self.assertTrue(all(i.date_time == (1980, 1, 1, 0, 0, 0) for i in z.infolist()))

    def test_game_artwork_input_and_output_directories_are_refused(self):
        write(self.client / "uifiles/default/EQUI.xml", b"source game layout")
        write(self.client / "uifiles/default/background.tga", b"source game artwork")
        with self.assertRaisesRegex(ValueError, "Game artwork"):
            self.package()
        self.assertFalse(self.out.exists())
        game = self.out.parent / "game"
        write(game / "uifiles/default/EQUI.xml")
        with self.assertRaisesRegex(ValueError, "Game artwork"):
            self.package(out=game / "packages")

    def test_source_artwork_under_ui_is_not_copied(self):
        for name in ("ui/default/EQUI.xml", "ui/modern/background.tga", "ui/other/EQUI.xml"):
            write(self.source / name, b"unshipped source artwork")
            write(self.client / name, b"unshipped source artwork")
        with zipfile.ZipFile(self.package()) as z:
            self.assertTrue(all(b"unshipped source artwork" not in z.read(name) for name in z.namelist()))

    def test_unsynchronized_build_missing_revision_and_unsafe_output_fail_before_writing(self):
        write(self.client / "ui/modern/window.lua", b"locally modified")
        with self.assertRaisesRegex(ValueError, "differs from its source"):
            self.package()
        self.assertFalse(self.out.exists())
        with self.assertRaisesRegex(ValueError, "full verified"):
            preview.package(self.client, self.source, "unknown", self.out, self.addon,
                            compiled_data_dir=self.seed, crt_dir=self.crt)
        with self.assertRaisesRegex(ValueError, "outside"):
            self.package(out=self.addon / "artifacts")

    def test_missing_runtime_and_non_x64_binary_rejected(self):
        (self.client / "SDL3.dll").unlink()
        with self.assertRaisesRegex(ValueError, "Missing or unsafe"):
            self.package()
        write(self.client / "SDL3.dll", b"not a DLL")
        with self.assertRaisesRegex(ValueError, "Windows program"):
            self.package()

    def test_compiled_seed_is_required_complete_and_unmodified(self):
        with self.assertRaisesRegex(ValueError, "explicit"):
            self.package(compiled_data_dir=None)
        target = self.seed / "ui-data/addon.ui-pack.default/lib/compiled/index.lua"
        original = target.read_bytes(); target.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "locally modified"):
            self.package()
        self.assertFalse(self.out.exists())
        target.write_bytes(original)
        self.ledger["report"]["skins"][0]["present"] = False; self.write_ledger()
        with self.assertRaisesRegex(ValueError, "twenty"):
            self.package()

    def test_seed_code_must_match_current_originals_and_images_must_be_reviewed(self):
        name = "ui-addons/ui-pack/ui/default/lib/pack_profile.lua"
        changed = b"return {stale=true}\n"; write(self.seed / name, changed)
        self.ledger["files"][name] = hashlib.sha256(changed).hexdigest(); self.write_ledger()
        with self.assertRaisesRegex(ValueError, "runtime-only refresh"):
            self.package()
        expected = preview.companion_files(self.addon)[name].read_bytes(); write(self.seed / name, expected)
        self.ledger["files"][name] = hashlib.sha256(expected).hexdigest()
        self.ledger["report"]["asset_repairs"] = []; self.write_ledger()
        with self.assertRaisesRegex(ValueError, "reviewed repair"):
            self.package()

    def test_expected_executable_hash_and_all_four_crt_files_are_required(self):
        with self.assertRaisesRegex(ValueError, "expected SHA256"):
            self.package(client_sha256="0" * 64)
        self.assertFalse(self.out.exists())
        missing = self.crt / preview.CRT_DLLS[-1]; original = missing.read_bytes(); missing.unlink()
        with self.assertRaisesRegex(ValueError, "Missing or unsafe"):
            self.package()
        missing.write_bytes(original)
        archive = self.package(client_sha256=hashlib.sha256(pe()).hexdigest())
        with zipfile.ZipFile(archive) as z:
            self.assertTrue(set(preview.CRT_DLLS) <= set(z.namelist()))


if __name__ == "__main__":
    unittest.main()
