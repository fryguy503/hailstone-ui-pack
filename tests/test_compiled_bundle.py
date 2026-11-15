import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("compiled_bundle", ROOT / "tools/compiled_bundle.py")
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


class BundleTests(unittest.TestCase):
    def test_unchanged_parent_plan_is_inherited_and_changed_plan_is_retained(self):
        first = "lib/compiled/windows/" + "0" * 24 + ".lua"
        second = "lib/compiled/windows/" + "1" * 24 + ".lua"
        index = bundle.HEADER + b'{["version"]=2,["windows"]={}}\n'
        base = {bundle.INDEX:index, first:bundle.HEADER+b'{"one"}\n', second:bundle.HEADER+b'{"two"}\n'}
        own = {**base, second:bundle.HEADER+b'{"changed"}\n'}
        output, report = bundle.bundle(own, base)
        self.assertEqual(report["inherited_windows"], 1)
        self.assertEqual(report["owned_windows"], 1)
        self.assertNotIn(first.encode(), b"".join(output.values()))
        self.assertIn(second.encode(), b"".join(output.values()))
        self.assertIn(b'{"changed"}', b"".join(output.values()))
        self.assertIn(b'buckets-v1', output[bundle.INDEX])

    def test_invalid_chunks_and_paths_cannot_be_coalesced(self):
        index = bundle.HEADER + b'{["version"]=2}\n'
        for path, data in (("../escape.lua",bundle.HEADER+b'{}\n'),
                           ("lib/compiled/windows/"+"1"*24+".lua",b'return os.execute("bad")')):
            with self.assertRaises(ValueError):
                bundle.bundle({bundle.INDEX:index,path:data})

    def test_bucket_size_limit_is_checked_before_installation(self):
        path = "lib/compiled/windows/"+"1"*24+".lua"
        with self.assertRaisesRegex(ValueError,"exceeds"):
            bundle.bundle({bundle.INDEX:bundle.HEADER+b'{}\n',path:bundle.HEADER+b'{"'+b'x'*(4*1024*1024)+b'"}\n'})


if __name__ == "__main__": unittest.main()
