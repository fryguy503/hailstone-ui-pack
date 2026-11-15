"""Client-compatible Ui ownership records for local installs and clean previews."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
HEADER = "hailstone-addons 1"
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}")
HASH = re.compile(r"[0-9a-fA-F]{64}")
VERSION = re.compile(r"[0-9A-Za-z.+-]+")


def safe_path(value):
    # Match core/zip_read.cpp and core/windows_names.h on every platform.
    if not value or value.startswith("/") or any(
            ord(c) < 32 or ord(c) == 127 or c in "\\:" for c in value):
        return False
    for part in value.removesuffix("/").split("/"):
        if not part or part in {".", ".."} or part.endswith((".", " ")):
            return False
        stem = part.split(".", 1)[0].rstrip(" ").lower()
        if stem in {"con", "prn", "aux", "nul", "conin$", "conout$"}:
            return False
        if stem[:3] in {"com", "lpt"} and stem[3:] in "123456789\u00b9\u00b2\u00b3" and len(stem) == 4:
            return False
    return True


def records(existing):
    """Fail closed on damaged/newer registries; preserve unrelated record text."""
    if existing is None:
        return []
    text = existing.decode("utf-8")
    lines = [line.removesuffix("\r") for line in text.split("\n")]
    content = [line for line in lines if line and not line.startswith("#")]
    if not content or content[0] != HEADER:
        raise ValueError("addon registry is damaged or newer; repair it in Hailstone first")
    result, block = [], []
    header_seen = False
    for line in lines:
        if not header_seen:
            if line == HEADER:
                header_seen = True
            continue
        if line.startswith("addon "):
            if block:
                result.append(block)
            block = [line]
        elif block:
            block.append(line)
        elif line and not line.startswith("#"):
            raise ValueError("addon registry has fields outside a record")
    if block:
        result.append(block)
    names = set()
    for block in result:
        # The client registry reader uses literal single-space separators.
        # General whitespace splitting would accept records it marks unreadable.
        words = block[0].split(" ")
        if (len(words) != 3 or not NAME.fullmatch(words[1])
                or words[2] not in {"script", "plugin", "tool", "upscaler", "ui"}
                or words[1].casefold() in names):
            raise ValueError("addon registry has an invalid or duplicate identity")
        names.add(words[1].casefold())
        files = set()
        for line in block[1:]:
            if line.startswith("key ") and not HASH.fullmatch(line[4:]):
                raise ValueError("addon registry has an invalid signing key")
            if not line.startswith("file "):
                continue
            fields = line.split(" ", 3)
            if (len(fields) != 4 or not HASH.fullmatch(fields[1])
                    or not re.fullmatch(r"[0-9]{1,20}", fields[2]) or int(fields[2]) > 2**64 - 1
                    or not safe_path(fields[3]) or fields[3].casefold() in files):
                raise ValueError("addon registry has an invalid file record")
            files.add(fields[3].casefold())
    return result


def managed_files(existing):
    """Return only the installed Ui package's owned relative hashes."""
    for block in records(existing):
        words = block[0].split()
        if words[1].casefold() != "ui-pack":
            continue
        if words[2] != "ui":
            raise ValueError(f"uninstall the existing ui-pack {words[2]} addon before installing the UI addon")
        return {line.split(" ", 3)[3]: line.split(" ", 3)[1].lower()
                for line in block[1:] if line.startswith("file ")}
    return {}


def merge_registry(entries, version, existing=None):
    """Merge one trusted Ui record, retaining unrelated records and signer pins."""
    if not VERSION.fullmatch(version):
        raise ValueError("invalid local addon version")
    old = records(existing)
    managed_files(existing)  # rejects a script/plugin/tool/upscaler to Ui kind change
    previous = next((block for block in old if block[0].split()[1].casefold() == "ui-pack"), [])
    # Like parse_registry(), the last valid key field is the installed pin.
    key = next((line for line in reversed(previous) if line.startswith("key ")), None)
    # Local previews keep explicit updates so their data/compiler version is deliberate.
    row = ["addon ui-pack ui", "source fryguy503/hailstone-ui-pack", f"version {version}", "caps none"]
    if key:
        row.append(key)
    row += ["autoupdate 0", "author Fryguy",
            "description Twenty coordinated interface skins."]
    for name, data in sorted(entries.items()):
        if not safe_path(name):
            raise ValueError("unsafe UI ownership path")
        row.append(f"file {hashlib.sha256(data).hexdigest()} {len(data)} {name}")
    blocks = [block for block in old if block[0].split()[1].casefold() != "ui-pack"]
    blocks.append(row)
    return ("# The add-ons Hailstone installed (docs/addons.md). Written by the client.\n"
            + HEADER + "\n\n" + "\n\n".join("\n".join(block).rstrip() for block in blocks) + "\n").encode("utf-8")


def record_bytes(root=ROOT, version=None):
    """Full installed.txt bytes for a clean bundle containing only this UI addon."""
    root = Path(root)
    if version is None:
        version = json.loads((root / "skins.json").read_text(encoding="utf-8"))["version"]
    spec = importlib.util.spec_from_file_location("ui_pack_sources", ROOT / "tools/package_addon.py")
    packager = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(packager)
    return merge_registry({name: path.read_bytes() for name, path in packager.sources(root)}, version)
