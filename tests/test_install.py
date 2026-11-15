import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pack_install", ROOT / "tools/install.py")
install = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = install
spec.loader.exec_module(install)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_local_conversion_uses_lua_and_inherits_missing_windows_without_xml_overlays(self):
        game, client = self.root / "game", self.root / "client"
        default, custom = game / "uifiles/default", game / "uifiles/aya-stock"
        default.mkdir(parents=True)
        custom.mkdir(parents=True)
        (client / "ui/modern").mkdir(parents=True)
        (client / "ui/modern/ui.ini").write_text("name=Modern\n")
        (default / "EQUI.xml").write_text('<XML><Composite><Include>base.xml</Include><Include>new.xml</Include></Composite></XML>')
        (default / "base.xml").write_text('<XML><Screen item="Base"/></XML>')
        (default / "new.xml").write_text('<XML><Screen item="New"/></XML>')
        authored = b'<XML><Composite><Include>base.xml</Include></Composite></XML>'
        (custom / "EQUI.xml").write_bytes(authored)
        plan, report = install.build_plan(client, game)
        self.assertEqual(sum(row["present"] for row in report["skins"]), 2)
        own = "ui-addons/ui-pack/ui/aya-stock/"
        self.assertIn(b'base=default', plan[own+"ui.ini"])
        self.assertIn(b'buckets-v1', plan["ui-data/addon.ui-pack.aya-stock/lib/compiled/index.lua"])
        self.assertIn(b'New', plan["ui-data/addon.ui-pack.aya-stock/lib/compiled/index.lua"])
        self.assertFalse(any(name.endswith(".xml") or name.startswith("servers/") for name in plan))
        self.assertEqual((custom / "EQUI.xml").read_bytes(), authored)

    def test_preflight_conflict_writes_nothing(self):
        target = self.root / "client"
        target.mkdir()
        (target / "existing.lua").write_text("local changes")
        with self.assertRaisesRegex(ValueError, "refusing to overwrite"):
            install.apply_plan(target, {"new.lua": b"new", "existing.lua": b"replacement"}, {"version": "test"})
        self.assertFalse((target / "new.lua").exists())
        self.assertEqual((target / "existing.lua").read_text(), "local changes")

    def test_compiled_bundle_cannot_install_inside_game_tree(self):
        game = self.root / "game"
        (game / "uifiles").mkdir(parents=True)
        target = game / "nested/data"
        with self.assertRaisesRegex(ValueError, "source game"):
            install.apply_plan(target, {"new.lua": b"new"}, {"version":"test"})
        self.assertFalse(target.exists())
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            install.apply_plan(game.parent, {"new.lua": b"new"},
                               {"version":"test", "source_game_dir":str(game)})
        self.assertFalse((game.parent / "new.lua").exists())

    def test_upgrade_is_idempotent_and_preserves_modified_files(self):
        target = self.root / "client"
        report = {"version": "one"}
        install.apply_plan(target, {"scripts/ui-pack/init.lua": b"one"}, report)
        install.apply_plan(target, {"scripts/ui-pack/init.lua": b"one"}, report)
        install.apply_plan(target, {"scripts/ui-pack/init.lua": b"two"}, {"version": "two"})
        path = target / "scripts/ui-pack/init.lua"
        self.assertEqual(path.read_bytes(), b"two")
        path.write_bytes(b"user change")
        with self.assertRaises(ValueError):
            install.apply_plan(target, {"scripts/ui-pack/init.lua": b"three"}, report)
        self.assertEqual(path.read_bytes(), b"user change")
        ledger = json.loads((target / install.LEDGER).read_text())
        self.assertEqual(ledger["version"], "two")

    def test_destination_path_escape_is_rejected(self):
        with self.assertRaises(ValueError):
            install.inside(self.root, "../escape.lua")
        with self.assertRaises(ValueError):
            install.inside(self.root, "C:/escape.lua")

    def test_separate_data_directory_and_source_overlap(self):
        game = self.root / "game"
        defaults = game / "uifiles/default"
        defaults.mkdir(parents=True)
        source = defaults / "EQUI.xml"
        source.write_bytes(b'<XML><Screen item="Fixture"/></XML>')
        binaries = self.root / "binaries"
        modern = binaries / "ui/modern"
        modern.mkdir(parents=True)
        (modern / "ui.ini").write_text("name=Modern\n")
        plan, report = install.build_plan(self.root / "data", game, install_dir=binaries)
        self.assertTrue(plan["ui-addons/ui-pack/ui/default/ui.ini"])
        self.assertFalse(any(name.startswith("scripts/") for name in plan))
        self.assertEqual(sum(row["present"] for row in report["skins"]), 1)
        self.assertEqual(source.read_bytes(), b'<XML><Screen item="Fixture"/></XML>')
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            install.build_plan(self.root, game, install_dir=binaries)
        with self.assertRaisesRegex(ValueError, "must not overlap"):
            install.build_plan(game / "client", game, install_dir=binaries)

    def test_reviewed_asset_map_copies_only_to_local_overlay_and_verifies_hash(self):
        game = self.root / "game"
        defaults = game / "uifiles/default"
        defaults.mkdir(parents=True)
        (defaults / "EQUI.xml").write_text('<XML><Screen item="Fixture"/></XML>')
        client = self.root / "client"
        (client / "ui/modern").mkdir(parents=True)
        (client / "ui/modern/ui.ini").write_text("name=Modern\n")
        candidate = self.root / "original.tga"
        candidate.write_bytes(b"synthetic image bytes")
        mapping = {"schema": 1, "assets": [{"skin": "default", "target": "original.tga",
                   "file": str(candidate), "sha256": install.digest(candidate.read_bytes()),
                   "origin": "synthetic archive: uifiles/default/original.tga"}]}
        path = self.root / "map.json"
        path.write_text(json.dumps(mapping))
        plan, report = install.build_plan(client, game, "test", asset_map=path)
        install.apply_plan(client, plan, report)
        self.assertEqual((client / "servers/test/assets/uifiles/default/original.tga").read_bytes(), candidate.read_bytes())
        self.assertFalse((defaults / "original.tga").exists())
        with self.assertRaisesRegex(ValueError, "requires --profile"):
            install.build_plan(client, game, asset_map=path)
        candidate.write_bytes(b"changed after review")
        with self.assertRaisesRegex(ValueError, "hash"):
            install.build_plan(client, game, "test", asset_map=path)

    def test_registered_interface_install_preserves_other_addons_and_hash_ownership(self):
        target = self.root / "client"
        registry = install.inside(target, install.REGISTRY)
        registry.parent.mkdir(parents=True)
        other = b"hailstone-addons 1\n\naddon sentinel script\nsource owner/sentinel\nversion 1.0.0\ncaps ui\nautoupdate 1\n"
        registry.write_bytes(other)
        plan = {"ui-addons/ui-pack/ui/default/ui.ini": b"name=Default\nbase=builtin:modern\n"}
        install.apply_plan(target, plan, {"version": "0.1.0-preview.2"})
        text = registry.read_text()
        self.assertIn("addon sentinel script\nsource owner/sentinel", text)
        self.assertIn("addon ui-pack ui\n", text)
        self.assertIn("caps none\n", text)
        self.assertIn("autoupdate 0\n", text)
        self.assertIn(f"file {install.digest(next(iter(plan.values())))} 33 ui/default/ui.ini", text)
        self.assertEqual(registry.read_bytes(), (target / install.REGISTRY_BACKUP).read_bytes())
        self.assertFalse((target / "scripts").exists())
        # The manager's file list is sufficient ownership even without the local ledger.
        (target / install.LEDGER).unlink()
        updated = {next(iter(plan)): b"name=New\n"}
        install.apply_plan(target, updated, {"version": "0.1.0-preview.2"})
        self.assertEqual((target / next(iter(plan))).read_bytes(), b"name=New\n")

    def test_old_managed_script_and_damaged_registry_are_rejected_before_files_change(self):
        for contents in (b"hailstone-addons 1\naddon ui-pack script\ncaps commands,ui\n",
                         b"hailstone-addons 2\n", b"damaged\n"):
            target = self.root / str(len(contents))
            path = target / install.REGISTRY
            path.parent.mkdir(parents=True)
            path.write_bytes(contents)
            with self.assertRaises(ValueError):
                install.apply_plan(target, {"ui-addons/ui-pack/ui/default/ui.ini": b"name=Default\n"},
                                   {"version": "0.1.0-preview.2"})
            self.assertFalse((target / "ui-addons").exists())
            self.assertEqual(path.read_bytes(), contents)

    def test_legacy_retirement_keeps_modified_and_unowned_scripts_without_autorun_edits(self):
        target = self.root / "client"
        old = {"scripts/ui-pack/init.lua": b"old", "scripts/ui-pack/catalog.lua": b"catalog"}
        install.apply_plan(target, old, {"version": "0.1.0-preview.1"})
        (target / "scripts/ui-pack/init.lua").write_bytes(b"local change")
        (target / "scripts/ui-pack/user.lua").write_bytes(b"unowned")
        settings = target / "scripts/autorun.ini"
        settings.write_bytes(b"ui-pack=1\n")
        report = {"version": "0.1.0-preview.2"}
        install.apply_plan(target, {"ui-addons/ui-pack/ui/default/ui.ini": b"name=Default\n"}, report)
        self.assertEqual((target / "scripts/ui-pack/init.lua").read_bytes(), b"local change")
        self.assertEqual((target / "scripts/ui-pack/user.lua").read_bytes(), b"unowned")
        self.assertFalse((target / "scripts/ui-pack/catalog.lua").exists())
        self.assertEqual(settings.read_bytes(), b"ui-pack=1\n")
        self.assertEqual(report["legacy_script_files_preserved"], ["scripts/ui-pack/init.lua"])

    def test_registration_refuses_unowned_presentations_in_package_folder(self):
        target = self.root / "client"
        evil = target / "ui-addons/ui-pack/ui/unowned/ui.ini"
        evil.parent.mkdir(parents=True)
        evil.write_text("name=Unowned\n")
        with self.assertRaisesRegex(ValueError, "unowned files"):
            install.apply_plan(target, {"ui-addons/ui-pack/ui/default/ui.ini": b"name=Default\n"},
                               {"version": "0.1.0-preview.2"})
        self.assertFalse((target / install.REGISTRY).exists())


if __name__ == "__main__":
    unittest.main()
