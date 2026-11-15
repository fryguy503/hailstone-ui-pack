"""Exercise the scoped menu adapter without game assets or copying a presenter."""
from pathlib import Path
import os
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = os.environ.get("HAILSTONE_LUA") or shutil.which("lua5.4") or shutil.which("lua54") or shutil.which("lua")


@unittest.skipUnless(LUA, "Lua interpreter unavailable; set HAILSTONE_LUA")
class MenusContractTest(unittest.TestCase):
    def test_scoped_adapter_lifetime_and_input_contract(self):
        result = subprocess.run([LUA, str(ROOT / "tests/lua_menus_test.lua")], cwd=ROOT,
                                capture_output=True, text=True, encoding="utf-8", timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertRegex(result.stdout, r"Lua menus: \d+ cases, \d+ assertions passed")


if __name__ == "__main__":
    unittest.main()
