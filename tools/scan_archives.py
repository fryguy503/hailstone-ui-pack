#!/usr/bin/env python3
"""Find missing UI resource basenames in player-owned archives without extracting.

Uses the 7-Zip listing command only. Results contain local paths and candidate
provenance, not artwork, and belong outside the source folders. A matching name
or CRC is not proof that another skin's artwork matches the intended original.
"""

from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_sources import _is_link

ARCHIVE_SUFFIXES = {".zip", ".7z", ".rar", ".tar", ".tgz", ".gz", ".bz2", ".xz", ".cab"}


def resource_basename(value: str) -> str:
    return PurePosixPath(value.replace("\\", "/")).name.casefold()


def inventory_requests(inventory: dict[str, Any], extra: list[str] | tuple[str, ...] = ()) -> dict[str, list[dict[str, str]]]:
    requests: dict[str, list[dict[str, str]]] = {}
    for skin in inventory.get("skins", []):
        for texture in skin.get("missing_texture_files", []):
            name = resource_basename(texture["file"])
            if name:
                requests.setdefault(name, []).append({"skin": skin["name"], "file": texture["file"]})
    for name in extra:
        if resource_basename(name):
            requests.setdefault(resource_basename(name), [])
    return requests


def discover_archives(roots: list[str | Path]) -> list[Path]:
    archives: set[Path] = set()
    for value in roots:
        root = Path(value).resolve()
        if _is_link(Path(value)):
            continue
        if root.is_file():
            if root.suffix.casefold() not in ARCHIVE_SUFFIXES:
                raise ValueError(f"Unsupported archive filename: {root.name}")
            archives.add(root)
            continue
        if not root.is_dir():
            raise FileNotFoundError(f"Archive search root is missing: {root}")
        for directory, dirs, files in os.walk(root, followlinks=False):
            base = Path(directory)
            dirs[:] = sorted((name for name in dirs if not _is_link(base / name)), key=str.casefold)
            for name in files:
                path = base / name
                if path.suffix.casefold() in ARCHIVE_SUFFIXES and not _is_link(path):
                    archives.add(path.resolve())
    return sorted(archives, key=lambda path: str(path).casefold())


def parse_listing(listing: str) -> list[dict[str, Any]]:
    """Parse 7z l -slt -ba output, retaining only file records and useful metadata."""
    records: list[dict[str, Any]] = []
    fields: dict[str, str] = {}

    def finish() -> None:
        if "Path" not in fields or fields.get("Folder") == "+":
            return
        if fields.get("Attributes", "").startswith("D"):
            return
        size = fields.get("Size", "")
        records.append({"member": fields["Path"], "bytes": int(size) if size.isdecimal() else None,
                        "crc": fields.get("CRC") or None})

    for line in [*listing.splitlines(), ""]:
        if not line.strip():
            finish()
            fields = {}
            continue
        if " = " not in line:
            continue
        name, value = line.split(" = ", 1)
        if name == "Path" and "Path" in fields:
            finish()
            fields = {}
        fields[name] = value
    return records


def member_skin(member: str) -> str | None:
    parts = PurePosixPath(member.replace("\\", "/")).parts
    for index, part in enumerate(parts[:-2]):
        if part.casefold() == "uifiles":
            return parts[index + 1]
    return None


def inspect_archive(archive: Path, requests: dict[str, list[dict[str, str]]], seven_zip: str,
                    timeout: float = 60) -> dict[str, Any]:
    row: dict[str, Any] = {"archive": str(archive), "exit_code": None, "member_count": 0,
                           "matches": [], "nested_archives": [], "error": ""}
    try:
        completed = subprocess.run([seven_zip, "l", "-slt", "-ba", "-sccUTF-8", "--", str(archive)],
                                   input="", capture_output=True, encoding="utf-8", errors="replace", timeout=timeout)
        row["exit_code"] = completed.returncode
        row["error"] = completed.stderr.strip()[:2000]
        members = parse_listing(completed.stdout)
        row["member_count"] = len(members)
        for member in members:
            path = member["member"]
            if PurePosixPath(path.replace("\\", "/")).suffix.casefold() in ARCHIVE_SUFFIXES:
                row["nested_archives"].append(path)
            key = resource_basename(path)
            if key not in requests:
                continue
            skin = member_skin(path)
            same = [request for request in requests[key] if skin and request["skin"].casefold() == skin.casefold()]
            row["matches"].append({**member, "basename": key, "archive_skin": skin,
                                   "requested_by": requests[key], "same_skin_requests": same})
    except (OSError, subprocess.TimeoutExpired) as exc:
        row["error"] = str(exc)
    return row


def scan_archives(roots: list[str | Path], requests: dict[str, list[dict[str, str]]], seven_zip: str,
                  workers: int = 8, timeout: float = 60) -> dict[str, Any]:
    if not 1 <= workers <= 32 or timeout <= 0:
        raise ValueError("Use 1..32 workers and a positive archive timeout")
    archives = discover_archives(roots)
    with ThreadPoolExecutor(max_workers=workers) as pool:
        rows = list(pool.map(lambda path: inspect_archive(path, requests, seven_zip, timeout), archives))
    found = {member["basename"] for row in rows for member in row["matches"]}
    return {
        "schema_version": 1, "purpose": "read-only archive candidate inventory; no extraction or repair",
        "warnings": ["This report contains local machine paths; do not commit or publish it.",
                     "A basename, location or CRC match alone does not establish artwork fidelity.",
                     "Nested archives are reported as members; extract a selected nested archive locally and scan it explicitly if needed."],
        "search_roots": [str(Path(root).resolve()) for root in roots], "targets": sorted(requests),
        "archive_count": len(rows), "archive_extensions": dict(sorted(Counter(path.suffix.casefold() for path in archives).items())),
        "successful_archives": sum(row["exit_code"] == 0 for row in rows),
        "member_count": sum(row["member_count"] for row in rows), "found_basenames": sorted(found),
        "missing_basenames": sorted(set(requests) - found), "archives": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("roots", nargs="+", type=Path, help="Player-owned directories or individual archives")
    parser.add_argument("--inventory", type=Path, default=Path(__file__).resolve().parents[1] / "docs/source-inventory.json")
    parser.add_argument("--target", action="append", default=[], help="Additional exact resource basename; repeatable")
    parser.add_argument("--seven-zip", default=shutil.which("7z") or shutil.which("7zz"), help="7-Zip command-line program")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--timeout", type=float, default=60)
    parser.add_argument("--output", type=Path, help="Local JSON report outside all search roots")
    args = parser.parse_args()
    if not args.seven_zip:
        parser.error("7-Zip is not on PATH; provide --seven-zip with its executable path")
    try:
        if args.output:
            output = args.output.resolve()
            for value in args.roots:
                root = value.resolve()
                protected = root.parent if root.is_file() else root
                if output == protected or protected in output.parents:
                    raise ValueError("The report must be outside archive search directories")
        inventory = json.loads(args.inventory.read_text(encoding="utf-8-sig"))
        requests = inventory_requests(inventory, args.target)
        if not requests:
            parser.error("The inventory has no missing resource names; provide --target to search additional names")
        report = scan_archives(args.roots, requests, args.seven_zip, args.workers, args.timeout)
        serialized = json.dumps(report, indent=2) + "\n"
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(serialized, encoding="utf-8")
            print(f"Listed {report['archive_count']} archives; found {len(report['found_basenames'])} basenames; report: {args.output}")
        else:
            print(serialized, end="")
        return 0 if report["successful_archives"] == report["archive_count"] else 1
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Archive scan failed: {exc}\n")


if __name__ == "__main__":
    raise SystemExit(main())
