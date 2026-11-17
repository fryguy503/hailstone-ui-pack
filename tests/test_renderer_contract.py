"""Check the Lua renderer against the real host's published registrations.

Set HAILSTONE_CLIENT_ROOT for a checkout outside the usual sibling worktree.
These checks do not inspect game data or execute the client.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
CLIENT = Path(os.environ.get("HAILSTONE_CLIENT_ROOT", ROOT.parent / "hailstone-branches" / "modular-ui-api"))
LUA = os.environ.get("HAILSTONE_LUA") or shutil.which("lua5.4") or shutil.which("lua54") or shutil.which("lua")


def code(path: Path) -> str:
    # Runtime files have line comments, not long comments. Keep string arguments
    # because they specify the canonical module/member used by B.Call.
    return re.sub(r"--[^\n]*", "", path.read_text(encoding="utf-8"))


@unittest.skipUnless((CLIENT / "src/ui/lua/lua_imgui.cpp").is_file(), "live client checkout not supplied")
class RendererContractTest(unittest.TestCase):
    def test_renderer_uses_registered_imgui_calls(self):
        host = (CLIENT / "src/ui/lua/lua_imgui.cpp").read_text(encoding="utf-8")
        registration = re.search(r"static const luaL_Reg fns\[\]\s*=\s*\{(.*?)\{nullptr, nullptr\}", host, re.S)
        self.assertIsNotNone(registration, "locate the actual ui function registry")
        exported = set(re.findall(r'\{"(\w+)"\s*,', registration[1]))
        loader = (CLIENT / "src/ui/lua/lua_host.cpp").read_text(encoding="utf-8")
        extra = re.search(r'register_ui_api\(L\).*?std::initializer_list.*?\{(.*?)\}\)\s*\{', loader, re.S)
        self.assertIsNotNone(extra, "locate the loader's ui helper registration")
        exported.update(re.findall(r'\{"(\w+)"\s*,\s*&lua_', extra[1]))
        calls = set()
        for path in (ROOT / "shared").glob("*.lua"):
            calls.update(re.findall(r"\bui\.(\w+)\s*\(", code(path)))
        self.assertGreater(len(calls), 30, "audit must cover the runtime's real call sites")
        self.assertFalse(calls - exported, f"unregistered ui calls: {sorted(calls - exported)}")

    def test_renderer_uses_canonical_host_members(self):
        catalog = (CLIENT / "src/app/lua_ui_api.inc").read_text(encoding="utf-8")
        exported = set(re.findall(r'UI_METHOD\("[^\"]+",\s*"(\w+)",\s*"(\w+)"', catalog))
        calls = set()
        for path in (ROOT / "shared").glob("*.lua"):
            text = code(path)
            calls.update(re.findall(r'B\.(?:Call|Function)\("(\w+)"\s*,\s*"(\w+)"', text))
            # Presenter modules use the same guarded two-part call convention.
            calls.update(re.findall(r'\b(?:call|has)\("(\w+)"\s*,\s*"(\w+)"', text))
            calls.update(re.findall(r'\b(?:API|hs\.UI)\.(\w+)\.(\w+)\s*\(', text))
            # B.Requirements declares dynamically checked dependencies this way.
            required = re.search(r"local required\s*=\s*\{(.*?)\nfunction B.Requirements", text, re.S)
            if required:
                calls.update(re.findall(r'\{\s*"(\w+)"\s*,\s*"(\w+)"\s*\}', required[1]))
        self.assertGreater(len(calls), 20, "audit must include semantic action adapters")
        self.assertFalse(calls - exported, f"unregistered hs.UI members: {sorted(calls - exported)}")


@unittest.skipUnless(LUA, "Lua interpreter unavailable; set HAILSTONE_LUA")
class LuaRuntimeTest(unittest.TestCase):
    def run_fixture(self, name: str, label: str, pattern: str | None = None):
        completed = subprocess.run([LUA, str(ROOT / "tests" / name)], cwd=ROOT,
                                   capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        self.assertRegex(completed.stdout, pattern or rf"Lua {label}: \d+ cases, \d+ assertions passed")

    def test_renderer_runtime(self):
        self.run_fixture("lua_renderer_test.lua", "renderer")

    def test_helpers_runtime(self):
        self.run_fixture("lua_helpers_test.lua", "helpers")

    def test_chrome_geometry_runtime(self):
        self.run_fixture("lua_chrome_geometry_test.lua", "chrome geometry")

    def test_source_presenters_runtime(self):
        self.run_fixture("lua_source_presenters_test.lua", "source presenters", r"Source presenters: \d+ assertions passed")

    def test_status_presenters_runtime(self):
        self.run_fixture("lua_status_presenters_test.lua", "status presenters", r"source status presenters: \d+ assertions passed")

    def test_model_presenters_runtime(self):
        self.run_fixture("lua_model_presenters_test.lua", "model presenters", r"Model presenters: \d+ assertions passed")


if __name__ == "__main__":
    unittest.main()
