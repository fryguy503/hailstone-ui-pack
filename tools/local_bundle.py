#!/usr/bin/env python3
"""Private local-conversion setup bundles; never part of a public release.

The archive carries a scoped install plan and original setup tools. Reading is
side-effect free: it verifies every entry before returning bytes to the separate
installer, which merges ownership instead of replacing account configuration.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import re
import stat
from typing import Any
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
METADATA = "LOCAL-INSTALL.json"
MAX_FILES = 4096
MAX_PAYLOAD_BYTES = 64 * 1024 * 1024
MAX_METADATA_BYTES = 8 * 1024 * 1024
MAX_LUA_BYTES = 4 * 1024 * 1024
SUPPORT = {"tools/install.py", "tools/ui_registry.py", "tools/local_bundle.py",
           "skins.json", "LICENSE", "Install-UI-Pack.cmd"}
CATALOG = {name.casefold(): name for name in (
    "default", "default_old", "aya-stock", "delta-stock", "drakah-pers-adeptus-stock",
    "DuxaUI-stock", "Graphite-stock", "ib-stock", "lodidodi-stock", "Lords-stock",
    "Nemesis-stock", "po2-stock", "po2alt-stock", "qqcustom-stock", "qqui-stock",
    "sars-stock", "Sparxx-stock", "Takus-stock", "vert-stock", "wow-stock")}
IMAGE_EXTENSIONS = {".tga", ".dds", ".png", ".bmp", ".jpg", ".jpeg"}
VERSION = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _link(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


def _relative(value: str) -> str:
    if (not isinstance(value, str) or not value or len(value) > 1024 or value.startswith("/")
            or any(ord(c) < 32 or ord(c) == 127 or c in "\\:" for c in value)):
        raise ValueError("unsafe bundle path")
    for part in value.split("/"):
        if not part or part in {".", ".."} or part.endswith((".", " ")):
            raise ValueError("unsafe bundle path")
        stem = part.split(".", 1)[0].rstrip(" ").casefold()
        if stem in {"con", "prn", "aux", "nul", "conin$", "conout$"} or (
            stem[:3] in {"com", "lpt"} and stem[3:] in {"1", "2", "3", "4", "5", "6", "7", "8", "9", "¹", "²", "³"}):
            raise ValueError("Windows device path in bundle")
    return value


def _profile(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", value):
        raise ValueError("profile must be a safe server folder ID")
    _relative(value)
    return value


def _scope(name: str) -> str:
    parts = _relative(name).split("/")
    if parts[:2] == ["ui-addons", "ui-pack"]:
        tail = parts[2:]
        if tail == ["LICENSE"]:
            return "code"
        if (len(tail) >= 3 and tail[0] == "ui" and tail[1].casefold() in CATALOG
                and "compiled" not in {part.casefold() for part in tail[2:]}):
            if tail[2:] == ["ui.ini"] or Path(tail[-1]).suffix.casefold() == ".lua":
                return "code"
    if (len(parts) >= 5 and parts[0] == "ui-data" and parts[1].startswith("addon.ui-pack.")
            and parts[1][len("addon.ui-pack."):] in CATALOG
            and parts[2:4] == ["lib", "compiled"] and Path(parts[-1]).suffix.casefold() == ".lua"):
        return "data"
    if (len(parts) >= 6 and parts[0] == "servers" and parts[2:4] == ["assets", "uifiles"]
            and parts[4].casefold() in CATALOG and Path(parts[-1]).suffix.casefold() in IMAGE_EXTENSIONS):
        _profile(parts[1])
        return "image"
    raise ValueError("bundle install path is outside the UI pack scopes: " + name)


def _spelling(names: list[str]) -> None:
    seen, prefixes = set(), {}
    for name in names:
        _relative(name)
        folded = name.casefold()
        if folded in seen:
            raise ValueError("duplicate or case-colliding bundle path")
        seen.add(folded)
        parts = name.split("/")
        for i in range(1, len(parts) + 1):
            prefix = "/".join(parts[:i]); key = prefix.casefold()
            if key in prefixes and prefixes[key] != prefix:
                raise ValueError("case-colliding bundle directory")
            prefixes[key] = prefix
    # A file must never also be the parent directory of another file.
    for name in names:
        parts = name.split("/")
        if any("/".join(parts[:i]).casefold() in seen for i in range(1, len(parts))):
            raise ValueError("bundle file is also a directory")


def _text(data: bytes) -> None:
    if b"\0" in data or data.startswith(b"\x1bLua"):
        raise ValueError("binary or executable content in text-only bundle entry")
    try:
        data.decode("utf-8")
    except UnicodeError as exc:
        raise ValueError("bundle text must be UTF-8") from exc


def _image(data: bytes, suffix: str) -> None:
    valid = ((suffix == ".png" and len(data) >= 24 and data.startswith(b"\x89PNG\r\n\x1a\n") and data[12:16] == b"IHDR")
             or (suffix == ".dds" and len(data) >= 128 and data.startswith(b"DDS "))
             or (suffix == ".bmp" and len(data) >= 26 and data.startswith(b"BM"))
             or (suffix in {".jpg", ".jpeg"} and len(data) >= 4 and data.startswith(b"\xff\xd8\xff"))
             or (suffix == ".tga" and len(data) >= 18 and data[2] in {1, 2, 3, 9, 10, 11}
                 and data[16] in {8, 15, 16, 24, 32}
                 and int.from_bytes(data[12:14], "little") > 0 and int.from_bytes(data[14:16], "little") > 0))
    if not valid:
        raise ValueError("repair payload is not a supported image")


def _plan(plan: dict[str, bytes]) -> None:
    if not isinstance(plan, dict) or not plan:
        raise ValueError("bundle needs a nonempty install plan")
    _spelling(list(plan))
    if len(plan) + len(SUPPORT) + 1 > MAX_FILES:
        raise ValueError("bundle exceeds file count limit")
    if any(not isinstance(data, bytes) for data in plan.values()):
        raise ValueError("bundle plan contents must be bytes")
    if sum(map(len, plan.values())) > MAX_PAYLOAD_BYTES:
        raise ValueError("bundle exceeds payload byte limit")
    for name, data in plan.items():
        kind = _scope(name)
        if kind == "image":
            _image(data, Path(name).suffix.casefold())
        else:
            _text(data)
            if Path(name).suffix.casefold() == ".lua" and len(data) > MAX_LUA_BYTES:
                raise ValueError("bundle Lua file exceeds client limit")


def _unique_object(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key in bundle metadata")
        result[key] = value
    return result


def _json(data: bytes) -> dict:
    try:
        result = json.loads(data.decode("utf-8"), object_pairs_hook=_unique_object)
    except (UnicodeError, json.JSONDecodeError, RecursionError) as exc:
        raise ValueError("invalid bundle metadata JSON") from exc
    if not isinstance(result, dict):
        raise ValueError("bundle metadata must be an object")
    return result


def _catalog(data: bytes, version: str | None = None) -> None:
    catalog = _json(data)
    skins = catalog.get("skins")
    if catalog.get("schema") != 1 or not isinstance(skins, list) or len(skins) != len(CATALOG):
        raise ValueError("bundle catalog must contain the twenty known skins")
    names = []
    for row in skins:
        if (not isinstance(row, dict) or not isinstance(row.get("id"), str)
                or row["id"].casefold() not in CATALOG
                or row.get("source") != CATALOG[row["id"].casefold()]):
            raise ValueError("unknown bundle catalog skin")
        names.append(row["id"].casefold())
    if set(names) != set(CATALOG):
        raise ValueError("duplicate or missing bundle catalog skin")
    if version is not None and catalog.get("version") != version:
        raise ValueError("bundle catalog version mismatch")


def _bounded_file(path: Path, limit: int) -> bytes:
    with path.open("rb") as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError("bundle file grew beyond its declared limit")
    return data


def _launcher() -> bytes:
    return ("@echo off\r\nsetlocal DisableDelayedExpansion\r\n"
            "set \"TARGET=%~1\"\r\n"
            "if not defined TARGET set /p \"TARGET=Hailstone data folder: \"\r\n"
            "if not defined TARGET exit /b 2\r\n"
            "set \"TARGET=%TARGET:\"=%\"\r\n"
            "if exist \"F:\\EQ1\\Tools\\M5-Python312-private-v2\\python.exe\" (\r\n"
            "  \"F:\\EQ1\\Tools\\M5-Python312-private-v2\\python.exe\" \"%~dp0tools\\install.py\" --client-dir \"%TARGET%\\.\" --bundle \"%~dp0.\"\r\n"
            ") else (\r\n"
            "  py -3 \"%~dp0tools\\install.py\" --client-dir \"%TARGET%\\.\" --bundle \"%~dp0.\"\r\n"
            ")\r\nset \"RESULT=%ERRORLEVEL%\"\r\n"
            "if not \"%RESULT%\"==\"0\" echo Installation stopped. Review the message above.\r\n"
            "exit /b %RESULT%\r\n").encode("ascii")


def _output(path: Path, report: dict, root: Path) -> None:
    if path.exists() or _link(path):
        raise ValueError("bundle output must use a fresh destination")
    resolved = path.resolve(); repository = root.resolve()
    if resolved.is_relative_to(repository) and ".local" not in resolved.relative_to(repository).parts:
        raise ValueError("private bundle output must be outside tracked repository paths")
    source = report.get("source_game_dir", report.get("game_dir"))
    if source:
        source = Path(source).resolve()
        if source.name.casefold() == "uifiles":
            source = source.parent
        if resolved.is_relative_to(source) or source.is_relative_to(resolved):
            raise ValueError("bundle output must be outside the source game tree")
    for parent in (path, *path.parents):
        if parent.is_dir() and any(p.name.casefold() == "uifiles" and p.is_dir() for p in parent.iterdir()):
            raise ValueError("bundle output must be outside the source game tree")


def write_bundle(path: str | Path, plan: dict[str, bytes], report: dict, root: str | Path = ROOT) -> Path:
    """Write a fresh private ZIP ('.zip') or extracted setup directory otherwise."""
    path, root = Path(path), Path(root)
    if not isinstance(report, dict) or not isinstance(report.get("version"), str) or not VERSION.fullmatch(report["version"]):
        raise ValueError("bundle report needs a semantic version")
    _output(path, report, root)
    _plan(plan)
    support = {"Install-UI-Pack.cmd": _launcher()}
    for name in SUPPORT - support.keys():
        source = root / name
        if _link(source) or not source.is_file() or not source.resolve().is_relative_to(root.resolve()):
            raise ValueError("missing or linked setup source: " + name)
        support[name] = _bounded_file(source, MAX_METADATA_BYTES)
        _text(support[name])
    _catalog(support["skins.json"], report["version"])
    metadata = {"schema": 1, "kind": "ui-pack-local-conversion", "version": report["version"], "report": report,
                "files": {name: {"size": len(data), "sha256": _sha(data)} for name, data in sorted(plan.items())},
                "support_files": {name: {"size": len(data), "sha256": _sha(data)} for name, data in sorted(support.items())}}
    try:
        encoded = (json.dumps(metadata, separators=(",", ":"), allow_nan=False) + "\n").encode("utf-8")
    except (TypeError, ValueError, RecursionError) as exc:
        raise ValueError("bundle report must contain finite JSON data") from exc
    if len(encoded) + sum(map(len, support.values())) > MAX_METADATA_BYTES:
        raise ValueError("bundle exceeds metadata/setup byte limit")
    entries = {"files/" + name: data for name, data in plan.items()}
    entries.update(support); entries[METADATA] = encoded
    _spelling(list(entries))
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.casefold() == ".zip":
        with zipfile.ZipFile(path, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for name, data in sorted(entries.items()):
                item = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                item.create_system = 3; item.external_attr = 0o100644 << 16
                item.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(item, data)
    else:
        path.mkdir()
        for name, data in sorted(entries.items()):
            target = path / name
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.resolve().is_relative_to(path.resolve()) or any(_link(p) for p in (target, *target.parents) if p != path.parent):
                raise ValueError("linked output directory")
            with target.open("xb") as output:
                output.write(data)
    read_bundle(path)
    return path


def _validate(metadata: dict, names: set[str], read: Any, sizes: dict[str, int], profile: str | None) -> tuple[dict[str, bytes], dict]:
    if metadata.get("schema") != 1 or metadata.get("kind") != "ui-pack-local-conversion":
        raise ValueError("unsupported local bundle format")
    version, report = metadata.get("version"), metadata.get("report")
    if not isinstance(version, str) or not VERSION.fullmatch(version) or not isinstance(report, dict) or report.get("version") != version:
        raise ValueError("invalid bundle version/report")
    files, support = metadata.get("files"), metadata.get("support_files")
    if not isinstance(files, dict) or not files or not isinstance(support, dict) or set(support) != SUPPORT:
        raise ValueError("invalid bundle file manifests")
    _spelling(list(files)); _spelling(list(support))
    expected = {METADATA, *support, *("files/" + name for name in files)}
    if names != expected or len(names) > MAX_FILES:
        raise ValueError("bundle has missing, extra or too many files")
    for name in files:
        _scope(name)
    if sum(sizes["files/" + name] for name in files) > MAX_PAYLOAD_BYTES or sum(sizes[name] for name in support) + sizes[METADATA] > MAX_METADATA_BYTES:
        raise ValueError("bundle exceeds payload or metadata byte limit")
    plan = {}
    support_contents = {}
    for records, prefix, destination in [(files, "files/", plan), (support, "", support_contents)]:
        for name, entry in records.items():
            if (not isinstance(entry, dict) or type(entry.get("size")) is not int or entry["size"] < 0
                    or not isinstance(entry.get("sha256"), str) or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])):
                raise ValueError("invalid bundle hash/size record")
            actual = prefix + name
            if sizes[actual] != entry["size"]:
                raise ValueError("bundle file size mismatch: " + name)
            data = read(actual)
            if len(data) != entry["size"] or _sha(data) != entry["sha256"]:
                raise ValueError("bundle file hash mismatch: " + name)
            destination[name] = data
    _plan(plan)
    for data in support_contents.values():
        _text(data)
    _catalog(support_contents["skins.json"], version)
    report = copy.deepcopy(report)
    if profile is not None:
        target_profile = _profile(profile)
        remapped, old_profiles = {}, set()
        for name, data in plan.items():
            if _scope(name) == "image":
                parts = name.split("/"); old_profiles.add(parts[1]); parts[1] = target_profile; name = "/".join(parts)
            if name in remapped:
                raise ValueError("profile remapping collides with another repair")
            remapped[name] = data
        _plan(remapped)
        if old_profiles:
            report["bundle_profile_remap"] = {"from": sorted(old_profiles), "to": target_profile}
        plan = remapped
    return plan, report


def read_bundle(path: str | Path, profile: str | None = None) -> tuple[dict[str, bytes], dict]:
    """Verify a ZIP or extracted directory completely; never install or execute it."""
    path = Path(path)
    if profile is not None:
        _profile(profile)
    if _link(path):
        raise ValueError("linked bundle root")
    try:
        if path.is_dir():
            root = path.resolve(); inventory = {}; directories = set(); stack = [path]
            while stack:
                folder = stack.pop()
                for entry in folder.iterdir():
                    if _link(entry) or not entry.resolve().is_relative_to(root):
                        raise ValueError("symlink or escaped directory in bundle")
                    name = _relative(entry.relative_to(path).as_posix())
                    if entry.is_dir():
                        directories.add(name); stack.append(entry)
                    elif entry.is_file():
                        inventory[name] = entry
                    else:
                        raise ValueError("special file in bundle")
                    if len(inventory) + len(directories) > MAX_FILES * 16:
                        raise ValueError("bundle directory count exceeds limit")
            _spelling(list(inventory))
            sizes = {name: p.stat().st_size for name, p in inventory.items()}
            if METADATA not in sizes or sizes[METADATA] > MAX_METADATA_BYTES:
                raise ValueError("missing or oversized local bundle metadata")
            if len(inventory) > MAX_FILES or sum(sizes.values()) > MAX_PAYLOAD_BYTES + MAX_METADATA_BYTES:
                raise ValueError("bundle exceeds size/count limits")
            approved_directories = {"/".join(name.split("/")[:i]) for name in inventory for i in range(1, len(name.split("/")))}
            if not directories <= approved_directories:
                raise ValueError("extra directory in bundle")
            def read(name):
                target = inventory[name]
                if _link(target) or not target.resolve().is_relative_to(root):
                    raise ValueError("bundle changed to a linked file")
                data = _bounded_file(target, sizes[name])
                if not target.resolve().is_relative_to(root) or _link(target):
                    raise ValueError("bundle file changed to an outside link")
                return data
            return _validate(_json(read(METADATA)), set(inventory), read, sizes, profile)
        if path.stat().st_size > MAX_PAYLOAD_BYTES + MAX_METADATA_BYTES + MAX_FILES * 2048:
            raise ValueError("bundle archive exceeds byte limit")
        with zipfile.ZipFile(path) as archive:
            inventory = {}; directories = set()
            for entry in archive.infolist():
                name = _relative(entry.filename[:-1] if entry.is_dir() else entry.filename)
                mode = stat.S_IFMT(entry.external_attr >> 16)
                if mode not in {0, stat.S_IFREG, stat.S_IFDIR} or entry.external_attr & 0x400 or entry.flag_bits & 1:
                    raise ValueError("linked, special or encrypted ZIP entry")
                if (mode == stat.S_IFDIR and not entry.is_dir()) or (mode == stat.S_IFREG and entry.is_dir()):
                    raise ValueError("ZIP file/directory mode mismatch")
                if entry.compress_type not in {zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED}:
                    raise ValueError("unsupported ZIP compression")
                if name in inventory or name in directories:
                    raise ValueError("duplicate ZIP entry")
                if entry.is_dir():
                    if entry.file_size != 0 or entry.CRC != 0:
                        raise ValueError("ZIP directory contains a payload")
                    directories.add(name)
                else:
                    inventory[name] = entry
                if len(inventory) + len(directories) > MAX_FILES * 16:
                    raise ValueError("bundle ZIP entry count exceeds limit")
            _spelling(list(inventory))
            sizes = {name: entry.file_size for name, entry in inventory.items()}
            if METADATA not in sizes or sizes[METADATA] > MAX_METADATA_BYTES:
                raise ValueError("missing or oversized local bundle metadata")
            if len(inventory) > MAX_FILES or sum(sizes.values()) > MAX_PAYLOAD_BYTES + MAX_METADATA_BYTES:
                raise ValueError("bundle exceeds size/count limits")
            approved_directories = {"/".join(name.split("/")[:i]) for name in inventory for i in range(1, len(name.split("/")))}
            if not directories <= approved_directories:
                raise ValueError("extra ZIP directory")
            def read(name):
                return archive.read(inventory[name])  # ZipFile verifies decompression and CRC.
            return _validate(_json(read(METADATA)), set(inventory), read, sizes, profile)
    except (zipfile.BadZipFile, zipfile.LargeZipFile, EOFError, RuntimeError, zlib.error) as exc:
        raise ValueError("invalid or corrupted bundle ZIP: " + str(exc)) from exc
