#!/usr/bin/env python3
"""Plan optional same-name repairs from player-owned UI resources.

This tool does not copy assets or edit game directories. Its report includes
local machine paths and belongs in a local output folder, never the repository.
A unique same-name candidate is a possible repair, not proof of original art.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import struct
import sys
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_sources import (
    _file_index, _is_link, _local_tag, _piece_name, _read_xml, _uifiles,
    audit_sources,
)


def image_dimensions(path: str | Path) -> tuple[int, int] | None:
    """Read dimensions from PNG, DDS, BMP, or TGA headers without decoding art."""
    path = Path(path)
    with path.open("rb") as source:
        header = source.read(128)
    if header.startswith(b"\x89PNG\r\n\x1a\n") and len(header) >= 24 and header[12:16] == b"IHDR":
        width, height = struct.unpack_from(">II", header, 16)
    elif header.startswith(b"DDS ") and len(header) >= 20:
        height, width = struct.unpack_from("<II", header, 12)
    elif header.startswith(b"BM") and len(header) >= 26:
        dib_size = struct.unpack_from("<I", header, 14)[0]
        if dib_size == 12:
            width, height = struct.unpack_from("<HH", header, 18)
        elif dib_size >= 40:
            width, height = struct.unpack_from("<ii", header, 18)
            height = abs(height)
        else:
            return None
    elif path.suffix.casefold() == ".tga" and len(header) >= 18 and header[2] in {1, 2, 3, 9, 10, 11}:
        width, height = struct.unpack_from("<HH", header, 12)
    else:
        return None
    return (width, height) if width > 0 and height > 0 else None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def texture_usage(game_dir: str | Path, skin: str, audit: dict[str, Any] | None = None) -> dict[str, Any]:
    """Conservative XML reachability; this does not establish live rendering."""
    if audit is None:
        audit = audit_sources(game_dir, [skin])["skins"][0]
    root = _uifiles(game_dir)
    dirs = {entry.name.casefold(): entry for entry in root.iterdir()
            if entry.is_dir() and not _is_link(entry)}
    effective = {}
    for name in ["default", skin.casefold()]:
        if name in dirs:
            effective.update(_file_index(dirs[name])[0])
    nodes: dict[str, list[Any]] = defaultdict(list)
    screen_names = set()
    expected_sizes: dict[str, set[tuple[int, int]]] = defaultdict(set)
    for entry in audit["active_xml"]:
        key = entry["file"].casefold()
        if key not in effective:
            continue
        tree = _read_xml(effective[key][1])
        for definition in tree:
            item = definition.attrib.get("item")
            if not item:
                continue
            nodes[item.casefold()].append(definition)
            tag = _local_tag(definition.tag)
            if tag == "Screen":
                screen_names.add(item.casefold())
            if tag == "TextureInfo":
                try:
                    width = int(definition.findtext("Size/CX", "0"))
                    height = int(definition.findtext("Size/CY", "0"))
                except ValueError:
                    continue
                if width > 0 and height > 0:
                    expected_sizes[item.casefold()].add((width, height))
    edges: dict[str, set[str]] = defaultdict(set)
    for key, definitions in nodes.items():
        for definition in definitions:
            for field in definition.iter():
                if field.text:
                    text = _piece_name(field.text).casefold()
                    if text in nodes and text != key:
                        edges[key].add(text)
    reachable = set()
    pending = list(screen_names)
    while pending:
        key = pending.pop()
        if key in reachable:
            continue
        reachable.add(key)
        pending.extend(edges[key] - reachable)
    return {
        item["file"].casefold(): {
            "static_reachability": "screen_referenced" if item["file"].casefold() in reachable else "not_reachable_in_xml",
            "declared_sizes": [list(size) for size in sorted(expected_sizes[item["file"].casefold()])],
        }
        for item in audit["missing_texture_files"]
    }


def resolve_assets(game_dir: str | Path, skins: list[str] | None = None,
                   search_roots: tuple[str | Path, ...] | list[str | Path] = ()) -> dict[str, Any]:
    """Find exact-basename candidates, grouped by identical content and dimensions.

    A candidate is unique only when every exact-name match has one hash and
    dimensions agree. Ambiguous matches are never selected. A unique hash does
    not prove that another skin's artwork is the intended original.
    """
    audit = audit_sources(game_dir, skins)
    requested = {asset["file"].casefold() for skin in audit["skins"] for asset in skin["missing_texture_files"]}
    roots = [(_uifiles(game_dir)).resolve()]
    for value in search_roots:
        path = Path(value).resolve()
        if not path.is_dir():
            raise FileNotFoundError(f"Asset search directory is missing: {path}")
        if path not in roots:
            roots.append(path)
    candidates: dict[str, list[Path]] = defaultdict(list)
    seen_paths = set()
    for root in roots:
        stack = [root]
        while stack:
            directory = stack.pop()
            for entry in sorted(directory.iterdir(), key=lambda item: item.name.casefold()):
                if _is_link(entry):
                    continue
                if entry.is_dir():
                    stack.append(entry)
                elif entry.is_file() and entry.name.casefold() in requested:
                    path = entry.resolve()
                    if path not in seen_paths:
                        seen_paths.add(path)
                        candidates[entry.name.casefold()].append(path)
    assets = {}
    for name in sorted(requested):
        grouped: dict[str, dict[str, Any]] = {}
        for path in candidates[name]:
            digest = _sha256(path)
            dimensions = image_dimensions(path)
            group = grouped.setdefault(digest, {
                "sha256": digest, "bytes": path.stat().st_size,
                "dimensions": list(dimensions) if dimensions else None,
                "paths": [],
            })
            group["paths"].append(str(path))
        groups = [grouped[key] for key in sorted(grouped)]
        assets[name] = {
            "status": "unresolved" if not groups else "unique_same_name_candidate" if len(groups) == 1 else "ambiguous",
            "candidate_groups": groups,
        }
    requests = []
    for skin in audit["skins"]:
        usage = texture_usage(game_dir, skin["name"], skin)
        for texture in skin["missing_texture_files"]:
            key = texture["file"].casefold()
            asset = assets[key]
            declared = usage[key]["declared_sizes"]
            candidate_dimensions = asset["candidate_groups"][0]["dimensions"] if len(asset["candidate_groups"]) == 1 else None
            dimension_match = all(candidate_dimensions == size for size in declared) if declared and candidate_dimensions else None
            requests.append({
                "skin": skin["name"], "file": texture["file"], "asset_key": key,
                **usage[key], "candidate_dimensions_match": dimension_match,
                "repair_eligible": asset["status"] == "unique_same_name_candidate" and dimension_match is True,
            })
    return {
        "schema_version": 1,
        "purpose": "local optional same-name repair plan; not original-art fidelity proof",
        "game_directory": str(_uifiles(game_dir).resolve().parent),
        "search_roots": [str(root) for root in roots],
        "warnings": [
            "This local report contains machine paths; do not commit or publish it.",
            "Static XML reachability does not establish live rendering. Engine-loaded animations and custom code may use additional art.",
            "Unique candidates come from other player-owned sources and may differ from the intended original skin; review before using them.",
            "Assets with divergent content, missing dimensions, or mismatched declared dimensions are not eligible for automatic repair.",
        ],
        "assets": assets, "requests": requests,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", nargs="?", help="Player-owned game folder or its uifiles directory")
    parser.add_argument("--game-dir", dest="game_dir_option", help="Player-owned game folder or its uifiles directory")
    parser.add_argument("--skin", action="append")
    parser.add_argument("--search-root", action="append", default=[], type=Path)
    parser.add_argument("--output", type=Path, help="Local JSON report outside all source directories")
    args = parser.parse_args()
    if bool(args.source_dir) == bool(args.game_dir_option):
        parser.error("Provide a game directory, either positionally or with --game-dir")
    game_dir = args.game_dir_option or args.source_dir
    try:
        if args.output:
            output = args.output.resolve()
            sources = [_uifiles(game_dir).resolve().parent,
                       *(path.resolve() for path in args.search_root)]
            if any(output == source or source in output.parents for source in sources):
                parser.error("The report output must be outside all source directories")
        plan = resolve_assets(game_dir, args.skin, args.search_root)
        serialized = json.dumps(plan, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
            print(f"Planned {len(plan['requests'])} missing texture requests; report written to {args.output}")
        else:
            print(serialized, end="")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Asset resolution failed: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
