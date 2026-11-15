#!/usr/bin/env python3
"""Inspect a player's SIDL sources without copying their layouts or artwork.

Only names, counts, dependency provenance, and diagnostics enter the report.
The player's source tree is opened read-only. This module has no dependencies
outside Python's standard library and can also be imported by pack builders.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path, PurePosixPath
from typing import Any
import xml.etree.ElementTree as ET

SCHEMA_VERSION = 1
_BASE_SKINS = {"default", "default_old"}
_IGNORED_PREFIX = "._"
MAX_XML_BYTES = 64 * 1024 * 1024


def _is_link(path: Path) -> bool:
    return path.is_symlink() or getattr(path, "is_junction", lambda: False)()


class _SidlTreeBuilder(ET.TreeBuilder):
    def doctype(self, name: str, pubid: str | None, system: str | None) -> None:
        raise ET.ParseError("DTD declarations are not supported in UI sources")


def _read_xml(path: Path) -> ET.Element:
    if path.stat().st_size > MAX_XML_BYTES:
        raise ET.ParseError("UI XML exceeds the 64 MiB audit limit")
    # Reject DTDs before content expansion; never load external entities.
    return ET.parse(path, parser=ET.XMLParser(target=_SidlTreeBuilder())).getroot()


def _uifiles(game_dir: str | Path) -> Path:
    source = Path(game_dir)
    if source.name.casefold() == "uifiles":
        return source
    direct = source / "uifiles"
    if direct.is_dir():
        return direct
    # Windows filenames are case-insensitive; retain that behavior on Linux.
    if source.is_dir():
        for child in source.iterdir():
            if child.name.casefold() == "uifiles" and child.is_dir():
                return child
    raise FileNotFoundError("Expected a game directory containing uifiles, or uifiles itself")


def discover_skins(game_dir: str | Path) -> list[str]:
    """Return requested source directories, excluding the empty Velious source."""
    return sorted(
        (child.name for child in _uifiles(game_dir).iterdir()
         if child.is_dir() and not _is_link(child)
         and (child.name.casefold() in _BASE_SKINS
              or child.name.casefold().endswith("-stock"))),
        key=str.casefold,
    )


def _relative_name(value: str) -> str | None:
    """Normalize an include without permitting access outside the UI folder."""
    value = value.strip().replace("\\", "/")
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ":" in value or ".." in path.parts:
        return None
    return str(path)


def _file_index(folder: Path) -> tuple[dict[str, tuple[str, Path]], list[str]]:
    index: dict[str, tuple[str, Path]] = {}
    collisions: list[str] = []
    # Do not follow links into another folder. Nothing in the stock UI needs it.
    stack = [folder]
    while stack:
        current = stack.pop()
        for child in sorted(current.iterdir(), key=lambda entry: entry.name.casefold()):
            if _is_link(child) or child.name.startswith(_IGNORED_PREFIX):
                continue
            if child.is_dir():
                stack.append(child)
            elif child.is_file():
                relative = child.relative_to(folder).as_posix()
                key = relative.casefold()
                if key in index:
                    collisions.append(relative)
                else:
                    index[key] = (relative, child)
    return index, sorted(collisions, key=str.casefold)


def _local_tag(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _piece_name(value: str) -> str:
    # SIDL accepts both "ControlName" and "ControlType:ControlName".
    return value.strip().split(":", 1)[-1]


def audit_skin(game_dir: str | Path, skin: str) -> dict[str, Any]:
    """Audit selected->default resolution and the active EQUI.xml include graph.

    Paths in the result are relative UI resource names, never machine paths.
    Declared textures are reported separately from missing includes: an unused
    texture declaration is not evidence that a visible control is broken.
    Unknown behavior is left unclassified instead of declared fully supported.
    """
    if not skin or skin in {".", ".."} or skin != Path(skin).name or "/" in skin or "\\" in skin or ":" in skin:
        raise ValueError("skin must be one UI directory name")
    root = _uifiles(game_dir)
    directories = {entry.name.casefold(): entry for entry in root.iterdir()
                   if entry.is_dir() and not _is_link(entry)}
    default_dir = directories.get("default")
    selected_dir = directories.get(skin.casefold())
    base, base_collisions = _file_index(default_dir) if default_dir else ({}, [])
    own, own_collisions = _file_index(selected_dir) if selected_dir else ({}, [])
    # Keep source provenance while resolving each filename independently.
    effective = {key: (name, path, "default") for key, (name, path) in base.items()}
    effective.update({key: (name, path, selected_dir.name if selected_dir else skin)
                      for key, (name, path) in own.items()})
    report: dict[str, Any] = {
        "name": selected_dir.name if selected_dir else skin,
        "source_present": selected_dir is not None,
        "source_empty": not own,
        "source_file_count": len(own),
        "source_xml_count": sum(key.endswith(".xml") for key in own),
        "source_extensions": dict(sorted(Counter(Path(name).suffix.casefold() or "(none)"
                                                  for name, _ in own.values()).items())),
        "active_xml_count": 0,
        "inherited_xml_count": 0,
        "screen_count": 0,
        "root_screen_count": 0,
        "definitions_by_type": {},
        "active_xml": [],
        "source_xml": sorted((name for key, (name, _) in own.items() if key.endswith(".xml")),
                             key=str.casefold),
        "unreferenced_source_xml": [],
        "missing_includes": [],
        "invalid_includes": [],
        "include_cycles": [],
        "malformed_xml": [],
        "missing_texture_files": [],
        "missing_piece_references": [],
        "case_collisions": {"default": base_collisions, "selected": own_collisions},
        "warnings": [],
    }
    parsed: dict[str, ET.Element | None] = {}
    active: dict[str, ET.Element] = {}
    visiting: set[str] = set()

    def parse(key: str, active_source: bool) -> ET.Element | None:
        if key not in parsed:
            name, path, origin = effective[key]
            try:
                parsed[key] = _read_xml(path)
            except (ET.ParseError, OSError, ValueError) as exc:
                parsed[key] = None
                report["malformed_xml"].append({
                    "file": name, "origin": origin,
                    "error": str(exc) if isinstance(exc, ET.ParseError) else type(exc).__name__,
                    "active": active_source,
                })
        elif active_source and parsed[key] is None:
            for diagnostic in report["malformed_xml"]:
                if diagnostic["file"].casefold() == key:
                    diagnostic["active"] = True
        return parsed[key]

    def load(requested: str, requested_by: str | None = None, depth: int = 0) -> None:
        relative = _relative_name(requested)
        if relative is None:
            report["invalid_includes"].append({"file": requested, "from": requested_by})
            return
        key = relative.casefold()
        if key in visiting:
            report["include_cycles"].append({"file": relative, "from": requested_by})
            return
        if key in active:
            return
        if depth > 64 or len(active) >= 4096:
            report["invalid_includes"].append({
                "file": relative, "from": requested_by,
                "reason": "include closure exceeds the audit depth or document limit",
            })
            return
        if key not in effective:
            report["missing_includes"].append({"file": relative, "from": requested_by})
            return
        tree = parse(key, True)
        if tree is None:
            return
        visiting.add(key)
        active[key] = tree
        name, _, origin = effective[key]
        report["active_xml"].append({"file": name, "origin": origin})
        for entry in tree.iter():
            if _local_tag(entry.tag) == "Include" and entry.text:
                load(entry.text, name, depth + 1)
        visiting.remove(key)

    load("EQUI.xml")
    # Audit optional source files too, while marking errors outside the active graph.
    for key in sorted(own):
        if key.endswith(".xml"):
            parse(key, key in active)

    definitions: list[tuple[str, ET.Element]] = []
    for key, tree in active.items():
        for entry in tree:
            if entry.attrib.get("item"):
                definitions.append((effective[key][0], entry))
    by_type = Counter(_local_tag(entry.tag) for _, entry in definitions)
    item_names = {entry.attrib["item"].casefold() for _, entry in definitions}
    piece_refs: set[str] = set()
    missing_refs: set[tuple[str, str]] = set()
    for source, entry in definitions:
        for field in entry.iter():
            if _local_tag(field.tag) not in {"Pieces", "ScreenPieces"} or not field.text:
                continue
            ref = _piece_name(field.text)
            piece_refs.add(ref.casefold())
            if ref.casefold() not in item_names:
                missing_refs.add((source, field.text.strip()))
    screens = [entry for _, entry in definitions if _local_tag(entry.tag) == "Screen"]
    report["screen_count"] = len(screens)
    report["root_screen_count"] = sum(entry.attrib["item"].casefold() not in piece_refs for entry in screens)
    report["definitions_by_type"] = dict(sorted(by_type.items()))
    report["missing_piece_references"] = [{"file": source, "reference": reference}
                                              for source, reference in sorted(missing_refs)]
    texture_refs: set[str] = set()
    for tree in active.values():
        for entry in tree.iter():
            if _local_tag(entry.tag) == "Texture" and entry.text:
                texture_refs.add(entry.text.strip().casefold())
    missing_textures: dict[str, dict[str, Any]] = {}
    for source, entry in definitions:
        if _local_tag(entry.tag) != "TextureInfo":
            continue
        name = entry.attrib["item"]
        relative = _relative_name(name)
        if relative is None or relative.casefold() not in effective:
            diagnostic = missing_textures.setdefault(name.casefold(), {
                "file": name, "declared_in": [],
                "referenced_by_animation": name.casefold() in texture_refs,
            })
            diagnostic["declared_in"].append(source)
    report["missing_texture_files"] = [missing_textures[key] for key in sorted(missing_textures)]
    report["active_xml_count"] = len(active)
    report["inherited_xml_count"] = sum(origin == "default" and skin.casefold() != "default"
                                          for _, _, origin in (effective[key] for key in active))
    report["unreferenced_source_xml"] = sorted((name for key, (name, _) in own.items()
                                                if key.endswith(".xml") and key not in active), key=str.casefold)
    if not default_dir:
        report["warnings"].append("Default fallback directory is missing.")
    if not selected_dir:
        report["warnings"].append("Requested source directory is missing; counts show default fallback only.")
    elif not own:
        report["warnings"].append("Requested source directory is empty; counts show default fallback only.")
    if report["missing_texture_files"]:
        report["warnings"].append("Unresolved declared textures may be optional or unused; inspect visible controls before treating them as defects.")
    if report["unreferenced_source_xml"]:
        report["warnings"].append("Some source XML is outside the EQUI.xml include graph; alternate layouts and application-loaded windows need separate review.")
    report["warnings"].append("A dependency audit does not verify appearance, input handling, game behavior, or support in the Hailstone runtime.")
    return report


def audit_sources(game_dir: str | Path, skins: list[str] | None = None) -> dict[str, Any]:
    selected = skins if skins is not None else discover_skins(game_dir)
    return {
        "schema_version": SCHEMA_VERSION,
        "resolution": "case-insensitive selected skin, then default, per relative resource path",
        "entry_point": "EQUI.xml",
        "excluded_sources": ["rof2velious"],
        "skin_count": len(selected),
        "skins": [audit_skin(game_dir, skin) for skin in selected],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", nargs="?", help="Player-owned game folder or its uifiles directory")
    parser.add_argument("--game-dir", dest="game_dir_option", help="Player-owned game folder or its uifiles directory")
    parser.add_argument("--skin", action="append", help="Audit only this source (repeatable)")
    parser.add_argument("--output", type=Path, help="Write diagnostics JSON outside the source game tree")
    args = parser.parse_args()
    if bool(args.source_dir) == bool(args.game_dir_option):
        parser.error("Provide a game directory, either positionally or with --game-dir")
    game_dir = args.game_dir_option or args.source_dir
    try:
        if args.output:
            output = args.output.resolve()
            source = _uifiles(game_dir).resolve().parent
            if output == source or source in output.parents:
                parser.error("The audit output must be outside the player's game folder")
        report = audit_sources(game_dir, args.skin)
        serialized = json.dumps(report, indent=2, ensure_ascii=True) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
            print(f"Audited {report['skin_count']} skins; report written to {args.output}")
        else:
            print(serialized, end="")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Source audit failed: {exc}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
