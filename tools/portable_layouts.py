#!/usr/bin/env python3
"""Build install-ready, literal Lua layouts and their bounded artwork inventory.

This is a maintainer build tool, never an end-user installation step. Inputs are
verified local conversion results; outputs contain UI presentation facts only.
No source XML, executable input Lua, account data or private plugin resources
are copied. Raster packaging is handled separately by portable_assets.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_PREFIX = "ui-data/addon.ui-pack."
OLD_PREFIX = "lib/compiled/"
NEW_PREFIX = "lib/layouts/"
HEADER = "-- Portable Hailstone UI presentation tables.\nreturn "
PRIVATE = re.compile(r"bastion", re.I)
IDENT = re.compile(r"[A-Za-z_]\w*\Z", re.ASCII)
NUMBER = re.compile(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?")
KEY_ASSIGN = re.compile(r"([A-Za-z_]\w*)\s*=", re.ASCII)
RESERVED = set("and break do else elseif end false for function goto if in local nil not or repeat return then true until while".split())
META = {"provenance", "sources", "diagnostics", "source_xml", "paletteOrigins"}
PROMOTED = {"Location", "Size", "Text", "Font", "EQType", "ScreenID", "Pieces", "ScreenPieces", "Pages"}
COLORS = {"TextColor", "DisabledColor", "HighlightColor", "FillTint", "LinesFillTint", "Tint"}
COMMON_ART = {"BlueIconBackground", "RedIconBackground", "A_SpellGemHolder", "A_SpellGemBackground",
              "A_SpellGemHighlight", "A_InvSlot", "A_RecessedBox"}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class LiteralReader:
    """Small parser for compiler literal output; deliberately cannot execute Lua."""
    def __init__(self, text: str):
        self.text, self.at, self.values = text, 0, 0

    def whitespace(self) -> None:
        while self.at < len(self.text):
            if self.text[self.at].isspace():
                self.at += 1
            elif self.text.startswith("--", self.at):
                end = self.text.find("\n", self.at)
                self.at = len(self.text) if end < 0 else end + 1
            else:
                break

    def expect(self, token: str) -> None:
        self.whitespace()
        if not self.text.startswith(token, self.at):
            raise ValueError(f"expected {token!r} at byte {self.at}")
        self.at += len(token)

    def string(self) -> str:
        quote = self.text[self.at]
        self.at += 1
        result: list[str] = []
        escapes = {"a": "\a", "b": "\b", "f": "\f", "n": "\n", "r": "\r", "t": "\t", "v": "\v", "\\": "\\", '"': '"', "'": "'"}
        while self.at < len(self.text):
            c = self.text[self.at]
            self.at += 1
            if c == quote:
                return "".join(result)
            if c != "\\":
                if c in "\r\n":
                    raise ValueError("raw line break in quoted Lua string")
                result.append(c)
                continue
            if self.at >= len(self.text):
                break
            c = self.text[self.at]
            self.at += 1
            if c in escapes:
                result.append(escapes[c])
            elif c.isdigit():
                digits = c
                while self.at < len(self.text) and len(digits) < 3 and self.text[self.at].isdigit():
                    digits += self.text[self.at]
                    self.at += 1
                code = int(digits)
                if code > 255:
                    raise ValueError("invalid Lua byte escape")
                result.append(chr(code))
            else:
                raise ValueError(f"unsupported literal escape {c!r}")
        raise ValueError("unterminated Lua string")

    def value(self, depth: int = 0) -> Any:
        self.values += 1
        if depth > 256 or self.values > 2_000_000:
            raise ValueError("literal table exceeds build limits")
        self.whitespace()
        if self.at >= len(self.text):
            raise ValueError("incomplete literal")
        c = self.text[self.at]
        if c in "\"'":
            return self.string()
        if c == "{":
            self.at += 1
            array, mapping = [], {}
            while True:
                self.whitespace()
                if self.at >= len(self.text):
                    raise ValueError("unterminated literal table")
                if self.text[self.at] == "}":
                    self.at += 1
                    if array and mapping:
                        raise ValueError("mixed literal tables are unsupported")
                    return array if array else mapping
                if self.text[self.at] == "[":
                    self.at += 1
                    key = self.value(depth + 1)
                    self.expect("]")
                    self.expect("=")
                    if not isinstance(key, (str, int)) or isinstance(key, bool) or key in mapping:
                        raise ValueError("invalid or duplicate literal table key")
                    mapping[key] = self.value(depth + 1)
                else:
                    ident = KEY_ASSIGN.match(self.text, self.at)
                    if ident:
                        key = ident[1]
                        self.at = ident.end()
                        if key in mapping:
                            raise ValueError("duplicate literal table key")
                        mapping[key] = self.value(depth + 1)
                    else:
                        array.append(self.value(depth + 1))
                self.whitespace()
                if self.at < len(self.text) and self.text[self.at] in ",;":
                    self.at += 1
                elif self.at >= len(self.text) or self.text[self.at] != "}":
                    raise ValueError("expected literal table separator")
        for keyword, value in (("false", False), ("true", True), ("nil", None)):
            if self.text.startswith(keyword, self.at) and (self.at + len(keyword) == len(self.text) or not self.text[self.at + len(keyword)].isalnum()):
                self.at += len(keyword)
                return value
        match = NUMBER.match(self.text, self.at)
        if match:
            self.at = match.end()
            value = float(match[0]) if any(c in match[0] for c in ".eE") else int(match[0])
            if not math.isfinite(value):
                raise ValueError("non-finite literal")
            return value
        raise ValueError(f"executable/nonliteral Lua at byte {self.at}")

    def read(self) -> Any:
        self.expect("return")
        if self.at < len(self.text) and (self.text[self.at].isalnum() or self.text[self.at] == "_"):
            raise ValueError("return must be a Lua keyword")
        result = self.value()
        self.whitespace()
        if self.at != len(self.text):
            raise ValueError("trailing nonliteral Lua")
        return result


def read_lua(path: Path) -> Any:
    if path.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("input Lua exceeds file limit")
    return LiteralReader(path.read_text(encoding="utf-8")).read()


def literal(value: Any) -> str:
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (float, int)):
        if not math.isfinite(value):
            raise ValueError("non-finite output")
        return repr(value)
    if isinstance(value, str):
        return '"' + "".join("\\\\" if c == "\\" else '\\"' if c == '"' else f"\\{ord(c):03d}" if ord(c) < 32 or ord(c) == 127 else c for c in value) + '"'
    if isinstance(value, list):
        return "{" + ",".join(map(literal, value)) + "}"
    if isinstance(value, dict):
        parts = []
        for key, item in sorted(value.items(), key=lambda row: str(row[0])):
            prefix = key if isinstance(key, str) and IDENT.fullmatch(key) and key not in RESERVED else "[" + literal(key) + "]"
            parts.append(prefix + "=" + literal(item))
        return "{" + ",".join(parts) + "}"
    raise ValueError(f"nonliteral output: {type(value).__name__}")


def strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)


def clean(value: Any, bad: set[str], *, fields: bool = False) -> Any:
    if isinstance(value, dict):
        return {key: clean(item, bad) for key, item in value.items()
                if key not in META and not PRIVATE.search(str(key))
                and (not fields or key not in PROMOTED | COLORS)}
    if isinstance(value, list):
        return [clean(item, bad) for item in value]
    if isinstance(value, str) and (PRIVATE.search(value) or value.casefold() in bad):
        return ""
    return value


def node(value: Any, bad: set[str]) -> list | None:
    if not isinstance(value, list) or len(value) < 13 or not isinstance(value[0], str):
        raise ValueError("unexpected source node tuple")
    if any(PRIVATE.search(str(value[n])) for n in (1, 2)):
        return None
    result = [clean(item, bad) for item in value]
    result[3] = False
    result[11] = clean(value[11], bad, fields=True)
    result[12] = [child for original in value[12] for child in [node(original, bad)] if child is not None]
    return result


def supported_roots(client: Path) -> set[str]:
    names = {"ChatWindow", "ContainerWindow", "ItemDisplayWindow", "HotButtonWnd", "OptionsWindow"}
    for path in (client / "src/app").glob("lua_ui*.cpp"):
        text = path.read_text(encoding="utf-8")
        names.update(re.findall(r'StockWindow\("([A-Za-z0-9_]+)"', text))
        # Factories also pass names to generic constructors (buff windows are
        # one example). Intersect these public identifiers with actual source
        # screen names later instead of assuming every model has a literal ctor.
        names.update(re.findall(r'"([A-Za-z_][A-Za-z0-9_]+)"', text))
    for folder in (client / "ui/modern", client / "ui/gamepad", ROOT / "shared"):
        for path in folder.rglob("*.lua"):
            text = path.read_text(encoding="utf-8")
            names.update(re.findall(r'"([A-Za-z_][A-Za-z0-9_]+)"', text))
            names.update(re.findall(r'(?:WINDOW|SCREEN|WIN)\s*=\s*"([A-Za-z0-9_]+)"', text))
            names.update(re.findall(r'(?:screen|window)\s*=\s*"([A-Za-z0-9_]+)"', text))
            names.update(re.findall(r'(?:Resolve|Window|Dialog|model)\("([A-Za-z0-9_]+)"', text))
    names.update("HotButtonWnd" + str(n) for n in range(2, 11))
    return {name.casefold() for name in names if not PRIVATE.search(name)}


def private_resources(index: dict) -> set[str]:
    result: set[str] = set()
    for category in ("images", "animations", "templates"):
        for name, record in index.get(category, {}).items():
            if PRIVATE.search(name) or any(PRIVATE.search(s) for s in strings(record)):
                result.add(name.casefold())
    for _ in range(32):
        additions = {name.casefold() for category in ("animations", "templates")
                     for name, record in index.get(category, {}).items()
                     if any(s.casefold() in result for s in strings(record))}
        if additions <= result:
            break
        result.update(additions)
    return result


def portable_index(index: dict, windows: dict[str, str], plans: dict, native_names: set[str], dynamic_art: set[str]) -> tuple[dict, dict, dict]:
    bad = private_resources(index)
    selected = {name: path for name, path in windows.items() if name.casefold() in native_names and name.casefold() not in bad}
    output_plans: dict[str, list] = {}
    for name, path in selected.items():
        if path not in plans:
            raise ValueError(f"missing source control graph: {name}")
        result = node(plans[path], bad)
        if result is not None:
            output_plans[path.replace(OLD_PREFIX, NEW_PREFIX, 1)] = result
    selected = {name: path.replace(OLD_PREFIX, NEW_PREFIX, 1) for name, path in selected.items()
                if path.replace(OLD_PREFIX, NEW_PREFIX, 1) in output_plans}
    style = clean(index.get("style", {}), bad)
    resources = {}
    for category in ("images", "animations", "templates"):
        resources[category] = {name: record for name, record in index.get(category, {}).items() if name.casefold() not in bad}
    folded = {key: (category, name) for category, records in resources.items() for name in records for key in [name.casefold()]}
    needed = {"images": set(), "animations": set(), "templates": set()}
    pending = list(strings([output_plans, style])) + list(COMMON_ART) + list(dynamic_art)
    while pending:
        ref = pending.pop().strip().casefold()
        if ref not in folded:
            continue
        category, name = folded[ref]
        if name in needed[category]:
            continue
        needed[category].add(name)
        record = resources[category][name]
        if category == "animations" and record.get("grid"):
            continue
        pending.extend(strings(record.get("fields", record)))
        if category == "animations":
            pending.extend(strings(record.get("frames", {})))
    result = {"version": 2, "portable": 1, "storage": "buckets-v1", "encoding": "node-tuples-v1",
              "skin": index["skin"], "windows": selected, "style": style, "defaults": {}}
    for kind, values in index.get("defaults", {}).items():
        # Defaults are shared with templates and are not node tuples. Preserve
        # their complete semantic fields; only nodes have promoted duplicates.
        result["defaults"][kind] = clean(values, bad)
    result["images"] = {name: {key: record[key] for key in ("path", "width", "height", "declaredWidth", "declaredHeight") if key in record}
                        for name in sorted(needed["images"]) for record in [resources["images"][name]]}
    result["animations"] = {name: {key: clean(record[key], bad) for key in ("frames", "cycle", "grid") if key in record}
                            for name in sorted(needed["animations"]) for record in [resources["animations"][name]]}
    result["templates"] = {name: {key: clean(record[key], bad) for key in ("type", "fields") if key in record}
                           for name in sorted(needed["templates"]) for record in [resources["templates"][name]]}
    # Keep compatibility guards for explicitly referenced grid animations, but
    # never carry icon-atlas bitmaps: live item/spell APIs provide their cells.
    for name, entry in result["animations"].items():
        if entry.get("grid"):
            entry["frames"] = []
    report = {"source_roots": len(windows), "portable_roots": len(selected), "private_resources_removed": len(bad),
              "unsupported_roots_removed": sorted(set(windows) - set(selected)),
              "resources": {k: len(result[k]) for k in ("images", "animations", "templates")}}
    return result, output_plans, report


def audit_layouts(seed: Path, layouts: Path, report_path: Path) -> dict:
    """Compare shipped public graphs against verified source presentation facts.

    Source hashes, private-resource removal and duplicate-field promotion are
    deliberately excluded from the comparison. Rectangles, anchors, control
    order, text, fonts, colors, semantic IDs, artwork references, slots and all
    remaining control fields must be identical. The comparison reads output
    from disk, including its Default inheritance, rather than generator memory.
    """
    ledger = json.loads((seed / "addons/ui-pack-local-install.json").read_text(encoding="utf-8"))["files"]
    source_indices, source_graphs, final_indices, final_graphs = {}, {}, {}, {}
    checked_files = 0
    for folder in sorted(layouts.iterdir()):
        if not folder.is_dir():
            continue
        source = seed / (DATA_PREFIX + folder.name.lower()) / "lib/compiled"
        source_indices[folder.name] = read_lua(source / "index.lua")
        source_graphs[folder.name], final_graphs[folder.name] = {}, {}
        for file in [source / "index.lua", *sorted((source / "buckets").glob("*.lua"))]:
            if sha(file.read_bytes()) != ledger.get(file.relative_to(seed).as_posix()):
                raise ValueError("source hash changed during portable audit")
            checked_files += 1
            if file.name != "index.lua":
                source_graphs[folder.name].update(read_lua(file))
        final_indices[folder.name] = read_lua(folder / "index.lua")
        for file in sorted((folder / "buckets").glob("*.lua")):
            final_graphs[folder.name].update(read_lua(file))

    def project(original: list, bad: set[str], *, source: bool) -> list | None:
        if source and any(PRIVATE.search(str(original[slot])) for slot in (1, 2)):
            return None
        # This projection is intentionally separate from the node emitter.
        # It checks every retained value, rather than selected golden screens.
        result = [original[slot] for slot in range(len(original))]
        result[3] = False
        fields = original[11]
        if source:
            fields = {key: value for key, value in fields.items()
                      if key not in PROMOTED and key not in COLORS}
            fields = clean(fields, bad)
        result[11] = fields
        result[12] = [child for entry in original[12]
                      for child in [project(entry, bad, source=source)] if child is not None]
        if source:
            # All other tuple slots are copied unchanged except private refs.
            for slot in list(range(3)) + list(range(4, 11)) + list(range(13, len(result))):
                result[slot] = clean(result[slot], bad)
        return result

    def merge(base: dict, own: dict) -> dict:
        result = dict(base)
        folded = {name.casefold(): name for name in result}
        for name, value in own.items():
            previous = folded.get(name.casefold())
            if previous is not None:
                del result[previous]
            result[name] = value
            folded[name.casefold()] = name
        return result

    rows = []
    for skin in final_indices:
        source = source_indices[skin]
        final = final_indices[skin]
        source_windows = merge(source_indices["default"]["windows"], source["windows"])
        final_windows = merge(final_indices["default"]["windows"], final["windows"])
        originals = dict(source_graphs["default"])
        originals.update(source_graphs[skin])
        shipped = dict(final_graphs["default"])
        shipped.update(final_graphs[skin])
        bad = private_resources(source)
        before, after = {}, {}
        for screen, path in final_windows.items():
            original_path = source_windows.get(screen)
            if original_path is None or original_path.replace(OLD_PREFIX, NEW_PREFIX, 1) != path:
                raise ValueError(f"source window identity changed: {skin}/{screen}")
            before[screen] = project(originals[original_path], bad, source=True)
            after[screen] = project(shipped[path], set(), source=False)
            if before[screen] != after[screen]:
                raise ValueError(f"public presentation changed: {skin}/{screen}")
        expected_defaults = {name: clean(values, bad) for name, values in source.get("defaults", {}).items()}
        if final["defaults"] != expected_defaults:
            raise ValueError(f"semantic type defaults changed: {skin}")
        before_hash, after_hash = sha(literal(before).encode()), sha(literal(after).encode())
        rows.append({"id": skin, "windows": len(after), "source_presentation_sha256": before_hash,
                     "portable_presentation_sha256": after_hash, "equal": before_hash == after_hash})
    report = {"schema": 1, "kind": "portable-presentation-audit", "verified_source_files": checked_files,
              "skins": rows, "all_equal": all(row["equal"] for row in rows),
              "effective_windows": sum(row["windows"] for row in rows),
              "portable_modules": {file.relative_to(layouts).as_posix(): sha(file.read_bytes())
                                   for file in sorted(layouts.rglob("*.lua"))}}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def build(seed: Path, client: Path, output: Path, report_path: Path) -> dict:
    ledger = json.loads((seed / "addons/ui-pack-local-install.json").read_text(encoding="utf-8"))
    manifest = ledger["files"]
    catalog = json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))["skins"]
    native = supported_roots(client)
    cpp = "\n".join(p.read_text(encoding="utf-8") for p in (client / "src/app").glob("lua_ui*.cpp"))
    dynamic_art = set(re.findall(r'"([A-Za-z_][A-Za-z0-9_./-]+)"', cpp))
    source_data, all_plans, indices = {}, {}, {}
    portable_base: dict[str, list] = {}
    for skin in catalog:
        folder = seed / (DATA_PREFIX + skin["id"].lower()) / "lib/compiled"
        files = [folder / "index.lua", *sorted((folder / "buckets").glob("*.lua"))]
        for path in files:
            rel = path.relative_to(seed).as_posix()
            raw = path.read_bytes()
            if sha(raw) != manifest.get(rel):
                raise ValueError(f"source data hash mismatch: {rel}")
            source_data[rel] = sha(raw)
        indices[skin["id"]] = read_lua(folder / "index.lua")
        plans = {}
        for path in files[1:]:
            plans.update(read_lua(path))
        all_plans[skin["id"]] = plans
    base_plans = all_plans["default"]
    report = {"schema": 1, "kind": "portable-layout-build", "source_files": source_data, "skins": [], "files": {}}
    for skin in catalog:
        own = indices[skin["id"]]
        # Selected indices contain their effective resource maps; sparse graph
        # buckets inherit identical Default plans without copying them again.
        available = dict(base_plans)
        available.update(all_plans[skin["id"]])
        index, plans, item_report = portable_index(own, own["windows"], available, native, dynamic_art)
        owned_plans = plans
        if skin["id"] == "default":
            portable_base = plans
        else:
            owned_plans = {path: value for path, value in plans.items() if portable_base.get(path) != value}
        buckets: dict[int, dict] = {}
        for path, value in sorted(owned_plans.items()):
            number = int(path.rsplit("/", 1)[1][:2], 16) % 32
            buckets.setdefault(number, {})[path] = value
        modules = {"index.lua": index, **{f"buckets/{n:02x}.lua": values for n, values in buckets.items()}}
        for relative, value in sorted(modules.items()):
            data = (HEADER + literal(value) + "\n").encode("utf-8")
            if PRIVATE.search(data.decode("utf-8")) or b".xml" in data.lower() or b"Generated locally" in data:
                raise ValueError(f"private/source provenance escaped into {skin['id']}/{relative}")
            if len(data) > 4 * 1024 * 1024:
                raise ValueError("portable module exceeds the client file limit")
            path = output / skin["id"] / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            report["files"][f"layouts/{skin['id']}/{relative}"] = {"bytes": len(data), "sha256": sha(data)}
        item_report.update(id=skin["id"], geometry_fingerprint=sha(literal(plans).encode()), module_count=len(modules),
                           owned_graphs=len(owned_plans), inherited_graphs=len(plans)-len(owned_plans))
        report["skins"].append(item_report)
    report["total_bytes"] = sum(row["bytes"] for row in report["files"].values())
    report["total_modules"] = len(report["files"])
    report["native_roots"] = sorted(native)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", required=True, type=Path)
    parser.add_argument("--client", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "layouts")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--audit-existing", action="store_true", help="audit an existing portable tree against its verified source")
    args = parser.parse_args()
    if args.output.exists() and not args.audit_existing:
        parser.error("output must be a fresh maintainer-owned directory")
    if not args.audit_existing and not args.client:
        parser.error("--client is required when generating layouts")
    try:
        if args.audit_existing:
            report = audit_layouts(args.seed.resolve(), args.output.resolve(), args.report.resolve())
            print(json.dumps({key: report[key] for key in ("all_equal", "verified_source_files", "effective_windows")}))
        else:
            report = build(args.seed.resolve(), args.client.resolve(), args.output.resolve(), args.report.resolve())
            print(json.dumps({"modules": report["total_modules"], "bytes": report["total_bytes"], "skins": len(report["skins"])}))
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f"Portable layout build failed: {exc}\n")


if __name__ == "__main__":
    main()
