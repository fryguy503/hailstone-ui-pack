"""An interrupted obsolete-file cleanup must retain ownership until a retry finishes."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pack_install_recovery", ROOT / "tools" / "install.py")
install = importlib.util.module_from_spec(spec)
spec.loader.exec_module(install)


class RecoveryTests(unittest.TestCase):
    def test_first_ui_registry_write_interruption_resumes_without_losing_other_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "client"
            plan = {"ui-addons/ui-pack/ui/default/ui.ini": b"name=Default\n"}
            replace = install.os.replace

            def interrupted(source, target):
                if target == client / install.REGISTRY:
                    raise PermissionError("simulated registry commit interruption")
                return replace(source, target)

            with patch.object(install.os, "replace", interrupted):
                with self.assertRaises(PermissionError):
                    install.apply_plan(client, plan, {"version": "0.1.0-preview.2"})
            self.assertFalse((client / install.REGISTRY).exists())
            self.assertTrue((client / install.REGISTRY_BACKUP).exists())
            install.apply_plan(client, plan, {"version": "0.1.0-preview.2"})
            self.assertEqual((client / install.REGISTRY).read_bytes(),
                             (client / install.REGISTRY_BACKUP).read_bytes())
            self.assertTrue((client / install.LEDGER).exists())

    def test_failed_obsolete_cleanup_keeps_ledger_and_retry_succeeds(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "client"
            old = {"scripts/ui-pack/keep.lua": b"old", "scripts/ui-pack/obsolete.lua": b"obsolete"}
            new = {"scripts/ui-pack/keep.lua": b"new", "scripts/ui-pack/added.lua": b"added"}
            install.apply_plan(client, old, {"version": "one"})
            obsolete = client / "scripts/ui-pack/obsolete.lua"
            unlink = Path.unlink

            def interrupted(path, *args, **kwargs):
                if path == obsolete:
                    raise PermissionError("simulated obsolete-file cleanup interruption")
                return unlink(path, *args, **kwargs)

            with patch.object(Path, "unlink", interrupted):
                with self.assertRaises(PermissionError):
                    install.apply_plan(client, new, {"version": "two"})
            ledger = json.loads((client / install.LEDGER).read_text())
            self.assertEqual(ledger["version"], "one")
            self.assertIn("scripts/ui-pack/obsolete.lua", ledger["files"])
            install.apply_plan(client, new, {"version": "two"})
            self.assertFalse(obsolete.exists())
            self.assertEqual((client / "scripts/ui-pack/keep.lua").read_bytes(), b"new")
            self.assertEqual(json.loads((client / install.LEDGER).read_text())["version"], "two")

    def test_failed_ledger_commit_after_cleanup_is_recoverable(self):
        with tempfile.TemporaryDirectory() as tmp:
            client = Path(tmp) / "client"
            install.apply_plan(client, {"old.lua": b"old"}, {"version": "one"})
            replace = install.os.replace

            def interrupted(source, target):
                if target == client / install.LEDGER:
                    raise PermissionError("simulated ledger commit interruption")
                return replace(source, target)

            with patch.object(install.os, "replace", interrupted):
                with self.assertRaises(PermissionError):
                    install.apply_plan(client, {"new.lua": b"new"}, {"version": "two"})
            self.assertFalse((client / "old.lua").exists())
            self.assertEqual(json.loads((client / install.LEDGER).read_text())["version"], "one")
            install.apply_plan(client, {"new.lua": b"new"}, {"version": "two"})
            ledger = json.loads((client / install.LEDGER).read_text())
            self.assertEqual(ledger["version"], "two")
            self.assertEqual(set(ledger["files"]), {"new.lua"})


if __name__ == "__main__":
    unittest.main()
