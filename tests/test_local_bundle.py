"""Private setup bundle validation, using synthetic Lua data and images only."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("local_bundle", ROOT / "tools/local_bundle.py")
bundle = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bundle)


class LocalBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "original-code"
        (self.source / "tools").mkdir(parents=True)
        for name in ["install.py", "ui_registry.py"]:
            (self.source / "tools" / name).write_text("# original synthetic setup tool\n")
        (self.source / "tools/local_bundle.py").write_bytes(Path(bundle.__file__).read_bytes())
        catalog = json.loads((ROOT / "skins.json").read_text())
        self.version = catalog["version"]
        (self.source / "skins.json").write_text(json.dumps(catalog))
        (self.source / "LICENSE").write_text("Synthetic license\n")
        self.code = "ui-addons/ui-pack/ui/default/lib/theme.lua"
        self.data = "ui-data/addon.ui-pack.default/lib/compiled/index.lua"
        self.repair = "servers/bastion/assets/uifiles/delta-stock/target.png"
        png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 8, 16)
        self.plan = {self.code: b"return {original=true}\n", self.data: b"return {localLayout=true}\n",
                     self.repair: png}
        self.report = {"schema": 2, "runtime": "lua", "version": self.version,
                       "source_game_dir": str(self.root / "game"),
                       "skins": [{"id": "default", "present": True}],
                       "asset_repairs": [{"skin": "delta-stock", "target": "target.png",
                                          "sha256": hashlib.sha256(png).hexdigest(), "origin": "synthetic source"}]}
        self.counter = 0

    def write(self, directory=False, plan=None, report=None):
        self.counter += 1
        target = self.root / (f"private-{self.counter}" + ("" if directory else ".zip"))
        bundle.write_bundle(target, self.plan if plan is None else plan,
                            self.report if report is None else report, root=self.source)
        return target

    def mutate(self, source, action, stored=False):
        self.counter += 1
        target = self.root / f"mutated-{self.counter}.zip"
        with zipfile.ZipFile(source) as archive:
            entries = [(item, archive.read(item)) for item in archive.infolist()]
        action(entries)
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED) as archive:
                for item, data in entries:
                    if stored:
                        item.compress_type = zipfile.ZIP_STORED
                    archive.writestr(item, data)
        return target

    @staticmethod
    def edit_metadata(entries, change):
        for i, (item, data) in enumerate(entries):
            if item.filename == bundle.METADATA:
                value = json.loads(data); change(value)
                entries[i] = (item, json.dumps(value).encode())
                return
        raise AssertionError("metadata absent")

    def test_zip_and_extracted_directory_roundtrip_are_identical_and_read_only(self):
        for directory in [False, True]:
            with self.subTest(directory=directory):
                path = self.write(directory)
                before = ({p.relative_to(path).as_posix(): p.read_bytes() for p in path.rglob("*") if p.is_file()}
                          if directory else path.read_bytes())
                plan, report = bundle.read_bundle(path)
                self.assertEqual(plan, self.plan)
                self.assertEqual(report, self.report)
                self.assertFalse(any(p.startswith("addons/") or "account" in p for p in plan))
                after = ({p.relative_to(path).as_posix(): p.read_bytes() for p in path.rglob("*") if p.is_file()}
                         if directory else path.read_bytes())
                self.assertEqual(before, after)
                if directory:
                    command = (path / "Install-UI-Pack.cmd").read_text()
                    self.assertIn("M5-Python312-private-v2", command)
                    self.assertIn("py -3", command)
                    self.assertIn('--bundle "%~dp0."', command)

    def test_portable_companion_artwork_and_exact_notices_roundtrip(self):
        image = "ui-addons/ui-pack/ui/default/assets/" + "a" * 64 + ".png"
        notices = {"ui-addons/ui-pack/ui/default/THIRD_PARTY_NOTICES.md": b"Synthetic notice\n",
                   "ui-addons/ui-pack/ui/default/licenses/Nemesis-GPL-2.0.txt": b"Synthetic license\n"}
        plan = {**self.plan, image: self.plan[self.repair], **notices}
        restored, _ = bundle.read_bundle(self.write(plan=plan))
        self.assertEqual(restored, plan)
        self.assertEqual(bundle._scope(image), "code", "portable art belongs to the verified companion")

    def test_portable_resource_scope_rejects_other_paths_and_disguised_images(self):
        base = "ui-addons/ui-pack/ui/"
        for tail in ("default/assets/not-a-digest.png", "default/assets/" + "a" * 64 + ".jpg",
                     "default/assets/nested/" + "a" * 64 + ".png",
                     "DuxaUI-stock/assets/" + "a" * 64 + ".png",
                     "default/OTHER_NOTICES.md", "default/licenses/other.txt"):
            with self.subTest(tail=tail), self.assertRaisesRegex(ValueError, "outside"):
                self.write(plan={**self.plan, base + tail: b"unapproved resource"})
        image = base + "default/assets/" + "a" * 64 + ".png"
        with self.assertRaisesRegex(ValueError, "supported image"):
            self.write(plan={**self.plan, image: b"MZ disguised executable"})

    def test_profile_remapping_changes_only_repair_destinations(self):
        path = self.write()
        plan, report = bundle.read_bundle(path, "other-profile")
        new = self.repair.replace("/bastion/", "/other-profile/")
        self.assertEqual(plan[self.code], self.plan[self.code])
        self.assertEqual(plan[self.data], self.plan[self.data])
        self.assertEqual(plan[new], self.plan[self.repair])
        self.assertNotIn(self.repair, plan)
        self.assertEqual(report["bundle_profile_remap"], {"from": ["bastion"], "to": "other-profile"})
        self.assertNotIn("bundle_profile_remap", self.report)
        for unsafe in ["../escape", "a/b", "C:", "CON", "bad\nname"]:
            with self.assertRaises(ValueError):
                bundle.read_bundle(path, unsafe)

    def test_runtime_update_plan_can_replace_code_while_retaining_external_data(self):
        first, _ = bundle.read_bundle(self.write())
        retained = {p: v for p, v in first.items() if not p.startswith("ui-addons/ui-pack/")}
        next_plan = {**retained, self.code: b"return {runtimeVersion=2}\n"}
        reread, _ = bundle.read_bundle(self.write(plan=next_plan))
        self.assertEqual(reread[self.data], first[self.data])
        self.assertEqual(reread[self.repair], first[self.repair])
        self.assertNotEqual(reread[self.code], first[self.code])

    def test_writer_rejects_account_registry_executable_and_unknown_pack_paths(self):
        for name in ["accounts.ini", "addons/installed.txt", "ui-addons/ui-pack/run.exe",
                     "ui-addons/ui-pack/ui/default/plugin.dll", "ui-data/addon.ui-pack.unknown/lib/compiled/index.lua",
                     "ui-addons/ui-pack/ui/default/lib/compiled/layout.lua", "ui-data/addon.ui-pack.default/escape.lua"]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.write(plan={name: b"return {}"})

    def test_game_tree_and_existing_output_are_protected(self):
        game = self.root / "game"; (game / "uifiles/default").mkdir(parents=True)
        output = game / "other-folder/private.zip"
        with self.assertRaisesRegex(ValueError, "source game tree"):
            bundle.write_bundle(output, self.plan, self.report, root=self.source)
        self.assertFalse(output.parent.exists())
        output = self.write()
        original = output.read_bytes()
        with self.assertRaisesRegex(ValueError, "fresh"):
            bundle.write_bundle(output, self.plan, self.report, root=self.source)
        self.assertEqual(output.read_bytes(), original)

    def test_plan_limits_and_disguised_binary_are_rejected_before_output(self):
        with mock.patch.object(bundle, "MAX_PAYLOAD_BYTES", 4):
            with self.assertRaisesRegex(ValueError, "byte limit"):
                self.write()
        with mock.patch.object(bundle, "MAX_FILES", 3):
            with self.assertRaisesRegex(ValueError, "count limit"):
                self.write()
        with self.assertRaisesRegex(ValueError, "binary"):
            self.write(plan={self.data: b"\x1bLua\0binary"})
        with self.assertRaisesRegex(ValueError, "supported image"):
            self.write(plan={self.repair: b"MZ executable masquerading as an image"})

    def test_traversal_and_case_duplicates_in_zip_are_rejected(self):
        original = self.write()
        for name in ["files/../../accounts.ini", "files\\escape.lua", "files/C:/escape.lua", "files/a./b.lua", "files/CON.txt"]:
            path = self.mutate(original, lambda rows, n=name: rows.append((zipfile.ZipInfo(n), b"bad")))
            with self.subTest(name=name), self.assertRaises(ValueError):
                bundle.read_bundle(path)
        path = self.mutate(original, lambda rows: rows.append((zipfile.ZipInfo("files/" + self.data.upper()), b"duplicate")))
        with self.assertRaisesRegex(ValueError, "case-colliding"):
            bundle.read_bundle(path)
        path = self.mutate(original, lambda rows: rows.append(copy.copy(rows[0])))
        with self.assertRaisesRegex(ValueError, "duplicate"):
            bundle.read_bundle(path)

    def test_archive_symlink_payload_is_rejected(self):
        original = self.write()
        def change(rows):
            for item, data in rows:
                if item.filename == "files/" + self.data:
                    item.create_system = 3; item.external_attr = (stat.S_IFLNK | 0o777) << 16
        path = self.mutate(original, change)
        with self.assertRaisesRegex(ValueError, "linked"):
            bundle.read_bundle(path)

    @unittest.skipUnless(sys.platform == "win32", "Windows command launcher")
    def test_command_launcher_passes_spaced_trailing_slash_target_without_installing(self):
        (self.source / "tools/install.py").write_text("import json,sys\nprint(json.dumps(sys.argv[1:]))\n")
        folder = self.write(directory=True)
        target = self.root / "data folder"
        command = ["cmd.exe", "/d", "/c", str(folder / "Install-UI-Pack.cmd"), str(target) + "\\"]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        args = json.loads(result.stdout.strip())
        self.assertEqual(args[0], "--client-dir")
        self.assertEqual(Path(args[1]).resolve(), target.resolve())
        self.assertEqual(args[2], "--bundle")
        self.assertEqual(Path(args[3]).resolve(), folder.resolve())
        self.assertFalse(target.exists())

    def test_missing_extra_modified_and_duplicate_metadata_are_rejected(self):
        original = self.write()
        path = self.mutate(original, lambda rows: rows.pop(0))
        with self.assertRaises(ValueError):
            bundle.read_bundle(path)
        path = self.mutate(original, lambda rows: rows.append((zipfile.ZipInfo("unexpected.txt"), b"extra")))
        with self.assertRaises(ValueError):
            bundle.read_bundle(path)
        def modify(rows):
            for i, (item, data) in enumerate(rows):
                if item.filename == "files/" + self.data:
                    rows[i] = (item, bytes([data[0] ^ 1]) + data[1:])
        path = self.mutate(original, modify)
        with self.assertRaisesRegex(ValueError, "hash mismatch"):
            bundle.read_bundle(path)
        def duplicate_json(rows):
            for i, (item, data) in enumerate(rows):
                if item.filename == bundle.METADATA:
                    rows[i] = (item, b'{"schema":1,' + data[1:])
        path = self.mutate(original, duplicate_json)
        with self.assertRaisesRegex(ValueError, "duplicate JSON"):
            bundle.read_bundle(path)

    def test_recomputed_manifest_cannot_authorize_outside_scopes_or_wrong_sizes(self):
        original = self.write()
        def escape(rows):
            for item, _ in rows:
                if item.filename == "files/" + self.data:
                    item.filename = "files/accounts.ini"
            self.edit_metadata(rows, lambda m: m["files"].__setitem__("accounts.ini", m["files"].pop(self.data)))
        with self.assertRaisesRegex(ValueError, "outside"):
            bundle.read_bundle(self.mutate(original, escape))
        path = self.mutate(original, lambda rows: self.edit_metadata(rows, lambda m: m["files"][self.data].__setitem__("size", 1)))
        with self.assertRaisesRegex(ValueError, "size mismatch"):
            bundle.read_bundle(path)

    def test_truncated_and_crc_corrupted_archives_are_rejected(self):
        original = self.write()
        truncated = self.root / "truncated.zip"; truncated.write_bytes(original.read_bytes()[:-13])
        with self.assertRaisesRegex(ValueError, "corrupted"):
            bundle.read_bundle(truncated)
        stored = self.mutate(original, lambda rows: None, stored=True)
        raw = bytearray(stored.read_bytes())
        with zipfile.ZipFile(stored) as archive:
            info = archive.getinfo("files/" + self.data)
            name_size, extra_size = struct.unpack_from("<HH", raw, info.header_offset + 26)
            start = info.header_offset + 30 + name_size + extra_size
        raw[start] ^= 1
        corrupted = self.root / "crc.zip"; corrupted.write_bytes(raw)
        with self.assertRaisesRegex(ValueError, "CRC"):
            bundle.read_bundle(corrupted)

    def test_directory_modification_extra_file_and_links_are_rejected(self):
        folder = self.write(directory=True)
        target = folder / "files" / self.data
        target.write_bytes(b"modified")
        with self.assertRaises(ValueError):
            bundle.read_bundle(folder)
        folder = self.write(directory=True)
        (folder / "unexpected.txt").write_text("extra")
        with self.assertRaises(ValueError):
            bundle.read_bundle(folder)
        folder = self.write(directory=True)
        target = folder / "files" / self.data
        target.unlink()
        outside = self.root / "outside.lua"; outside.write_bytes(self.plan[self.data])
        try:
            target.symlink_to(outside)
        except OSError:
            self.skipTest("host cannot create test symlinks")
        with self.assertRaisesRegex(ValueError, "symlink"):
            bundle.read_bundle(folder)


if __name__ == "__main__":
    unittest.main()
