"""Small authored data fixtures for package-boundary tests, not visual parity."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import struct
import zlib


def literal(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(literal(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + literal(key) + "]=" + literal(item)
                               for key, item in sorted(value.items())) + "}"
    raise TypeError(type(value))


def layouts(root: Path):
    """Write a complete twenty-entry fixture with one reachable screen each."""
    skins = json.loads((root / "skins.json").read_text(encoding="utf-8"))["skins"]
    digest = hashlib.sha256(b"Test").hexdigest()[:24]
    virtual = "lib/layouts/windows/" + digest + ".lua"
    bucket = f"buckets/{int(digest[:2], 16) % 32:02x}.lua"
    plan = ["Screen", "Test", "Test", "", [0, 0, 160, 100],
            [True, True, True, True, 0, 0, 0, 0, 0], "Test", 3,
            {}, ["", "", "", ""], "", {}, [], "", ""]
    result = []
    for skin in skins:
        folder = root / "layouts" / skin["id"]
        files = {
            "index.lua": {"version": 2, "portable": 1, "encoding": "node-tuples-v1",
                          "storage": "buckets-v1", "skin": skin["source"],
                          "windows": {"Test": virtual}, "images": {},
                          "animations": {}, "templates": {}, "style": {}, "defaults": {}},
            bucket: {virtual: plan},
        }
        for name, value in files.items():
            path = folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("-- Authored synthetic test layout.\nreturn " + literal(value) + "\n",
                            encoding="utf-8", newline="\n")
            result.append(path)
    return result


def rgba_png():
    """One transparent RGBA pixel, with a complete PNG/zlib stream."""
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0" * 5)) + chunk(b"IEND", b""))
