"""The release builder reads data literals without executing conversion input."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("portable_layouts", ROOT / "tools/portable_layouts.py")
portable = importlib.util.module_from_spec(spec)
spec.loader.exec_module(portable)


class PortableLiteralTests(unittest.TestCase):
    def test_literal_roundtrip_preserves_quoted_control_and_unicode_text(self):
        value = {"caption": 'Quotes " and \\ paths\n\t\x00\x7f, café',
                 "keys": {"end": "reserved", "with spaces": "label"},
                 "sizes": [12, -2.5, True, False]}
        self.assertEqual(portable.LiteralReader("-- layout data\nreturn " + portable.literal(value)).read(),
                         value)

    def test_executable_input_is_rejected_instead_of_evaluated(self):
        for text in ("return os.execute('echo unsafe')", "return {hook=function() end}",
                     "return (function() return {} end)()", "local x = {}; return x",
                     "return require('module')", "return setmetatable({}, {})"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                portable.LiteralReader(text).read()

    def test_data_followed_by_code_is_rejected(self):
        for text in ("return {}; os.execute('echo unsafe')", "return {} return {}",
                     "return {1, 2}()"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                portable.LiteralReader(text).read()

    def test_duplicate_keys_are_rejected_in_all_literal_forms(self):
        for text in ('return {skin="one",skin="two"}',
                     'return {["skin"]="one",["skin"]="two"}',
                     'return {skin="one",["skin"]="two"}',
                     'return {[1]="one",[1]="two"}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                portable.LiteralReader(text).read()

    def test_malformed_or_unbounded_data_is_rejected(self):
        for text in ('return {"unterminated}', 'return {one=1', 'return 1e999',
                     'return {true, named=false}', 'return {"\\999"}',
                     'return1', 'return "raw\nline"', 'return "raw\rline"',
                     "return " + "{" * 258 + "}" * 258):
            with self.subTest(text=text[:60]), self.assertRaises(ValueError):
                portable.LiteralReader(text).read()

    def test_read_lua_rejects_files_larger_than_client_source_limit(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "oversized.lua"
            path.write_bytes(b"--" + b" " * (4 * 1024 * 1024) + b"\nreturn {}")
            with self.assertRaisesRegex(ValueError, "file limit"):
                portable.read_lua(path)


if __name__ == "__main__":
    unittest.main()
