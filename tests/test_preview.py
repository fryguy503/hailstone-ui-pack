from contextlib import redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("preview_matrix", ROOT / "tools/preview_matrix.py")
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)


class PreviewSourceProtectionTests(unittest.TestCase):
    def fixture(self, root):
        self.game, self.seed, self.output = root / "game", root / "seed", root / "previews"
        self.client = root / "client/fake-client.exe"
        self.client.parent.mkdir()
        self.client.write_bytes(b"explicit fake client identity")
        self.game.mkdir()
        self.seed.mkdir()
        self.owned = {"ui-addons/ui-pack/LICENSE": b"Synthetic license fixture"}
        for skin in ("default", "default_old"):
            self.owned["ui-addons/ui-pack/ui/" + skin + "/ui.ini"] = b"name=Synthetic\nbase=builtin:modern\n"
            self.owned["ui-addons/ui-pack/ui/" + skin + "/lib/pack_profile.lua"] = b"return {}\n"
            self.owned["ui-data/addon.ui-pack." + skin + "/lib/compiled/index.lua"] = b"return {version=2}\n"
        image = "servers/preview/assets/uifiles/delta-stock/reviewed.png"
        self.owned[image] = b"synthetic reviewed image bytes"
        self.ledger = {"schema": 1, "version": "0.2.0-preview.1", "files": {}, "report": {
            "schema": 2, "runtime": "lua", "asset_repairs": [{"skin": "delta-stock", "target": "reviewed.png",
                "sha256": hashlib.sha256(self.owned[image]).hexdigest(), "origin": "synthetic reviewed fixture"}]}}
        for name, data in self.owned.items():
            target = self.seed / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            self.ledger["files"][name] = hashlib.sha256(data).hexdigest()
        self.write_ledger()
        for name in ("hailstone.ini", "accounts.ini", "servers/preview/server.ini", "logs/hailstone.log",
                     "scripts/private/init.lua", "addons/installed.txt"):
            target = self.seed / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("PRIVATE PLAYER DATA\n", encoding="utf-8")
        return ["--client", str(self.client), "--game-dir", str(self.game), "--seed-data", str(self.seed),
                "--output", str(self.output)]

    def write_ledger(self):
        path = self.seed / preview.LEDGER
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(self.ledger), encoding="utf-8")

    def invoke(self, args, fake):
        with patch.object(preview.subprocess, "run", side_effect=fake), redirect_stdout(io.StringIO()):
            return preview.main(args)

    def fake_client(self, command, *, cwd, env, capture_output, timeout, **options):
        self.assertEqual(Path(cwd), self.client.parent)
        self.assertTrue(capture_output)
        self.assertNotIn("--ui-demo", command)
        self.assertNotIn("--ui-skin", command)
        self.assertNotIn("--ui-screen", command)
        self.assertIn("--no-audio", command)
        self.assertEqual(Path(command[command.index("--game-dir") + 1]), self.game)
        data = Path(env["HAILSTONE_DATA_DIR"])
        skin = data.parent.name
        self.assertTrue(data.is_relative_to(self.output))
        text = (data / "hailstone.ini").read_text()
        for line in ("ui.name=addon.ui-pack." + skin.lower(), "update.check=0", "update.download=0", "update.install_on_quit=0"):
            self.assertIn(line, text)
        for name in ("accounts.ini", "servers/preview/server.ini", "logs/hailstone.log", "scripts/private/init.lua"):
            self.assertFalse((data / name).exists(), name)
        registration = (data / "addons/installed.txt").read_text()
        self.assertIn("addon ui-pack ui", registration)
        self.assertIn("autoupdate 0", registration)
        self.assertNotIn("PRIVATE PLAYER DATA", registration)
        self.assertEqual((data / "addons/installed.txt").read_bytes(), (data / "addons/installed.bak.txt").read_bytes())
        for name, content in self.owned.items():
            self.assertEqual((data / name).read_bytes(), content)
        screenshot = Path(command[command.index("--screenshot") + 1])
        screenshot.write_bytes(b"\x89PNG\r\n\x1a\nsynthetic screenshot fixture")
        line = "ui: Lua started, scripts in " + str(data / "ui-addons/ui-pack/ui" / skin)
        return subprocess.CompletedProcess(command, 0, stdout=line.encode(), stderr=b"")

    def test_parallel_fixtures_keep_data_isolated_and_record_one_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            args = self.fixture(Path(folder))
            before = {name: path.read_bytes() for name in self.owned for path in [self.seed/name]}
            rendezvous = threading.Barrier(2, timeout=5)
            directories, lock = [], threading.Lock()

            def client(command, **options):
                result = self.fake_client(command, **options)
                data = Path(options["env"]["HAILSTONE_DATA_DIR"])
                with lock:
                    directories.append(data)
                (data / "fixture-marker.txt").write_text(data.parent.name)
                rendezvous.wait()
                if data.parent.name == "default":
                    time.sleep(0.03)
                else:
                    result.returncode = 7
                    result.stderr = b"ui script error: synthetic failure"
                return result

            result = self.invoke(args + ["--skin", "default", "--skin", "default", "--skin", "default_old",
                                         "--jobs", "2", "--timeout", "10"], client)
            self.assertEqual(result, 1)
            self.assertEqual(len(set(directories)), 2)
            report = json.loads((self.output / "preview-results.json").read_text())
            self.assertEqual(report["mode"], "lua-login")
            self.assertEqual(report["client_sha256"], hashlib.sha256(self.client.read_bytes()).hexdigest())
            self.assertEqual([row["skin"] for row in report["fixtures"]], ["default", "default_old"])
            self.assertTrue(report["fixtures"][0]["rendered"])
            self.assertFalse(report["fixtures"][1]["rendered"])
            self.assertEqual(report["fixtures"][1]["exit_code"], 7)
            self.assertEqual(report["fixtures"][1]["errors"], ["ui script error: synthetic failure"])
            self.assertTrue(report["seed"]["unchanged"])
            self.assertTrue(report["seed"]["client_unchanged"])
            self.assertTrue((self.output / preview.MARKER).is_file())
            self.assertFalse(list(self.output.glob(".preview-results-*.tmp")))
            self.assertEqual(list(self.game.iterdir()), [])
            for name, content in before.items():
                self.assertEqual((self.seed/name).read_bytes(), content)
            for skin in ("default", "default_old"):
                self.assertEqual((self.output/skin/"data/fixture-marker.txt").read_text(), skin)

    def test_source_client_seed_and_tracked_paths_cannot_hold_output(self):
        with tempfile.TemporaryDirectory() as folder:
            args = self.fixture(Path(folder))
            for output in (self.game/"preview", self.seed/"preview", self.client.parent/"preview", ROOT/"tools/preview-test-output"):
                with self.subTest(output=output), patch.object(preview.subprocess, "run") as run:
                    with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                        preview.main(args[:-1] + [str(output), "--skin", "default"])
                    run.assert_not_called()
                    self.assertFalse(output.exists())

    def test_existing_output_is_never_reused(self):
        with tempfile.TemporaryDirectory() as folder:
            args = self.fixture(Path(folder));self.output.mkdir()
            sentinel = self.output / "private.txt";sentinel.write_text("keep")
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()), patch.object(preview.subprocess, "run") as run:
                preview.main(args + ["--skin", "default"])
            run.assert_not_called();self.assertEqual(sentinel.read_text(), "keep")

    def test_changed_or_unreviewed_owned_files_are_rejected_before_creation(self):
        for damage in ("hash", "path", "image"):
            with self.subTest(damage=damage), tempfile.TemporaryDirectory() as folder:
                args = self.fixture(Path(folder))
                if damage == "hash":
                    (self.seed / "ui-data/addon.ui-pack.default/lib/compiled/index.lua").write_bytes(b"changed")
                elif damage == "path":
                    self.ledger["files"]["accounts.ini"] = hashlib.sha256((self.seed/"accounts.ini").read_bytes()).hexdigest()
                else:
                    self.ledger["report"]["asset_repairs"] = []
                self.write_ledger()
                with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()), patch.object(preview.subprocess, "run") as run:
                    preview.main(args + ["--skin", "default"])
                run.assert_not_called();self.assertFalse(self.output.exists())

    def test_links_cannot_escape_seed_or_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);args=self.fixture(root)
            owned=self.seed/"ui-data/addon.ui-pack.default/lib/compiled/index.lua"
            outside=root/"outside.lua";outside.write_bytes(owned.read_bytes());owned.unlink()
            try:
                owned.symlink_to(outside)
            except OSError:
                self.skipTest("creating a symlink is unavailable on this host")
            with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()), patch.object(preview.subprocess, "run") as run:
                preview.main(args + ["--skin", "default"])
            run.assert_not_called();self.assertFalse(self.output.exists())

    def test_copy_fallback_does_not_share_mutable_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            args=self.fixture(Path(folder))
            with patch.object(preview.os, "link", side_effect=OSError("no hard links")):
                self.assertEqual(self.invoke(args + ["--skin", "default"], self.fake_client), 0)
            report=json.loads((self.output/"preview-results.json").read_text())
            self.assertEqual(report["fixtures"][0]["seeded"], {"link":0,"copy":len(self.owned)})
            self.assertEqual((self.seed/"hailstone.ini").read_text(), "PRIVATE PLAYER DATA\n")

    def test_windows_junction_guard_checks_seed_ancestors_without_link_privileges(self):
        with tempfile.TemporaryDirectory() as folder:
            args=self.fixture(Path(folder))
            blocked=self.seed/"ui-data/addon.ui-pack.default"
            actual=getattr(Path,"is_junction",lambda path:False)
            def is_junction(path):
                return path==blocked or actual(path)
            with patch.object(Path,"is_junction",is_junction,create=True):
                with self.assertRaises(SystemExit),redirect_stderr(io.StringIO()),patch.object(preview.subprocess,"run") as run:
                    preview.main(args+["--skin","default"])
            run.assert_not_called();self.assertFalse(self.output.exists())

    def test_later_interface_switch_or_generated_profile_cannot_hide_fallback(self):
        for mode in ("switch", "profile", "artwork", "missing-art", "wrong-root"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as folder:
                args=self.fixture(Path(folder))
                def client(command, **options):
                    result=self.fake_client(command, **options)
                    if mode=="switch":result.stdout+=b"\nuser interface: modern"
                    elif mode=="artwork":result.stderr=b"ui skin artwork fallback: synthetic failure"
                    elif mode=="missing-art":result.stderr=b"ui art: uifiles/synthetic/missing.png is missing"
                    elif mode=="wrong-root":result.stdout=b"ui: Lua started, scripts in wrong/ui/modern"
                    else:
                        target=Path(options["env"]["HAILSTONE_DATA_DIR"])/"servers/generated/server.ini"
                        target.parent.mkdir(parents=True,exist_ok=True);target.write_text("ui.name=modern\n")
                    return result
                self.assertEqual(self.invoke(args+["--skin","default"],client),1)
                row=json.loads((self.output/"preview-results.json").read_text())["fixtures"][0]
                self.assertFalse(row["rendered"]);self.assertTrue(row["errors"])

    def test_timeout_is_a_recorded_failure_not_an_unbounded_wait(self):
        with tempfile.TemporaryDirectory() as folder:
            args=self.fixture(Path(folder))
            def client(command, **options):raise subprocess.TimeoutExpired(command,options["timeout"],output=b"partial log")
            self.assertEqual(self.invoke(args+["--skin","default","--timeout","1"],client),1)
            row=json.loads((self.output/"preview-results.json").read_text())["fixtures"][0]
            self.assertEqual(row["exit_code"],-1);self.assertFalse(row["rendered"])
            self.assertIn("partial log",(self.output/"default/client-output.log").read_text())

    def test_seed_change_after_initial_verification_cannot_launch_unverified_code(self):
        with tempfile.TemporaryDirectory() as folder:
            args=self.fixture(Path(folder));read=preview.seed_payload
            def changed(seed):
                result=read(seed)
                (seed/"ui-data/addon.ui-pack.default/lib/compiled/index.lua").write_bytes(b"changed after validation")
                return result
            with patch.object(preview,"seed_payload",side_effect=changed),patch.object(preview.subprocess,"run") as run,redirect_stdout(io.StringIO()):
                self.assertEqual(preview.main(args+["--skin","default"]),1)
            run.assert_not_called()
            report=json.loads((self.output/"preview-results.json").read_text())
            self.assertFalse(report["seed"]["unchanged"])
            self.assertIn("seed changed after verification",report["fixtures"][0]["errors"][0])

    def test_invalid_limits_and_obsolete_render_flags_are_rejected(self):
        base=["--client","unused.exe","--game-dir","unused-game","--seed-data","unused-seed","--output","unused-output"]
        for option,value in (("--frames","0"),("--timeout","-1"),("--jobs","0"),("--jobs","5"),
                             ("--ui-demo","native"),("--ui-skin","default"),("--ui-screen","game")):
            with self.subTest(option=option),patch.object(preview.subprocess,"run") as run:
                with self.assertRaises(SystemExit) as error,redirect_stderr(io.StringIO()):preview.main(base+[option,value])
                self.assertEqual(error.exception.code,2);run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
