"""Compact locally generated Lua plans into inheritable, data-only buckets."""
from __future__ import annotations

import re

PREFIX = "lib/compiled/windows/"
INDEX = "lib/compiled/index.lua"
WINDOW = re.compile(r"lib/compiled/windows/([0-9a-f]{24})\.lua\Z")
HEADER = b"-- Generated locally from player-owned files. Do not redistribute.\nreturn "


def bundle(files: dict[str, bytes], base: dict[str, bytes] | None = None) -> tuple[dict[str, bytes], dict]:
    """Omit identical parent windows and group remaining tables in 32 buckets.

    Virtual window paths remain stable in the index. The runtime resolves an
    omitted entry from its approved base interface, retaining selected artwork.
    Only compiler-produced literals are accepted; no input Lua is executed.
    """
    if INDEX not in files or not files[INDEX].startswith(HEADER + b"{"):
        raise ValueError("compiled index is missing or has an unsupported format")
    buckets: dict[int, list[tuple[str, bytes]]] = {}
    inherited = 0
    for name, data in sorted(files.items()):
        if name == INDEX:
            continue
        match = WINDOW.fullmatch(name)
        if not match or not data.startswith(HEADER + b"{") or not data.endswith(b"}\n"):
            raise ValueError(f"unexpected compiled window format: {name}")
        if base and base.get(name) == data:
            inherited += 1
            continue
        bucket = int(match.group(1)[:2], 16) % 32
        buckets.setdefault(bucket, []).append((name, data[len(HEADER):].strip()))
    index = files[INDEX].replace(HEADER + b"{", HEADER + b'{["storage"]="buckets-v1",', 1)
    result = {INDEX: index}
    for number, windows in buckets.items():
        entries = [b'["' + name.encode("ascii") + b'"]=' + literal for name, literal in windows]
        result[f"lib/compiled/buckets/{number:02x}.lua"] = HEADER + b"{" + b",".join(entries) + b"}\n"
    if any(len(data) > 4 * 1024 * 1024 for data in result.values()):
        raise ValueError("compiled Lua chunk exceeds the client limit")
    return result, {"storage": "buckets-v1", "files": len(result), "bytes": sum(map(len, result.values())),
                    "inherited_windows": inherited, "owned_windows": len(files) - 1 - inherited}
