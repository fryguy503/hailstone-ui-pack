#!/usr/bin/env python3
"""Compile player-owned layouts offline and install selectable Lua interfaces."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LEDGER = "addons/ui-pack-local-install.json"
UI_PREFIX = "ui-addons/ui-pack/"
DATA_PREFIX = "ui-data/"
REGISTRY = "addons/installed.txt"
REGISTRY_BACKUP = "addons/installed.bak.txt"


def tool(name):
    spec = importlib.util.spec_from_file_location("ui_pack_" + name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def relative(value: str) -> str:
    parts = value.replace("\\", "/").split("/")
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or not value or any(p in ("..", ".", "") or ":" in p for p in parts):
        raise ValueError(f"unsafe relative path: {value}")
    return path.as_posix()


def inside(root: Path, value: str) -> Path:
    path = root / relative(value)
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"path leaves installation: {value}")
    return path


def build_plan(client: Path, game: Path, profile: str | None = None,
               install_dir: Path | None = None, asset_map: Path | None = None) -> tuple[dict[str, bytes], dict]:
    catalog = json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))
    if client.resolve().is_relative_to(game.resolve()) or game.resolve().is_relative_to(client.resolve()):
        raise ValueError("Hailstone's data folder and source game folder must not overlap")
    if profile is not None and (not re.fullmatch(r"[A-Za-z0-9_-]+", profile) or profile in (".", "..")):
        raise ValueError("profile must be a safe server folder ID")
    if not ((install_dir or client) / "ui/modern/ui.ini").is_file():
        raise ValueError("Hailstone needs the modular Lua UI client with interfaces.LoadBase")
    compiler = tool("compile_skin")
    bundler = tool("compiled_bundle")
    repairs = json.loads(asset_map.read_text(encoding="utf-8")) if asset_map else None
    if repairs is not None and not profile:
        raise ValueError("--asset-map requires --profile for a Hailstone-local image overlay")
    if repairs is not None and (not isinstance(repairs, dict) or repairs.get("schema") != 1 or not isinstance(repairs.get("assets"), list)):
        raise ValueError("asset map must have schema 1 and an assets list")
    folders = {p.name.casefold(): p for p in (game / "uifiles").iterdir() if p.is_dir() and not p.is_symlink()}
    report = {"schema": 2, "runtime": "lua", "version": catalog["version"], "skins": [], "asset_repairs": [],
              "source_game_dir": str(game.resolve())}
    compiled = {}
    for skin in catalog["skins"]:
        row = {"id": skin["id"], "source": skin["source"], "present": skin["source"].casefold() in folders}
        if row["present"]:
            try:
                result = compiler.compile_skin(game, skin["source"], repairs)
                compiled[skin["id"]] = result
                row["compilation"] = result["report"]
            except (OSError, ValueError, KeyError) as error:
                row["error"] = str(error)
        report["skins"].append(row)
    errors = [row for row in report["skins"] if row.get("error")]
    if errors:
        raise ValueError("; ".join(row["id"] + ": " + row["error"] for row in errors))
    if "default" not in compiled:
        raise ValueError("Default UI is missing, empty or cannot be compiled")
    plan = {}
    for name, source in tool("package_addon").sources(ROOT):
        parts = name.split("/")
        if parts[0] == "ui" and parts[1] not in compiled:
            continue
        plan[UI_PREFIX + name] = source.read_bytes()
    for row in report["skins"]:
        if row["id"] not in compiled:
            continue
        files, stats = bundler.bundle(compiled[row["id"]]["files"],
                                      compiled["default"]["files"] if row["id"] != "default" else None)
        row["bundle"] = stats
        for name, data in files.items():
            plan[DATA_PREFIX + "addon.ui-pack." + row["id"].lower() + "/" + name] = data
    if repairs:
        known = {s["id"].casefold(): s for s in catalog["skins"] if s["id"] in compiled}
        for repair in repairs["assets"]:
            if not isinstance(repair, dict):
                raise ValueError("each asset repair must be an object")
            skin = known.get(str(repair.get("skin", "")).casefold())
            if not skin:
                raise ValueError("asset repair must name an installed catalog skin")
            target = relative(str(repair.get("target", "")))
            if Path(target).suffix.casefold() not in (".tga", ".dds", ".png", ".bmp", ".jpg", ".jpeg"):
                raise ValueError("asset repairs may supply image resources only")
            source = Path(str(repair.get("file", "")))
            if not source.is_file() or source.is_symlink() or source.stat().st_size > 64 * 1024 * 1024:
                raise ValueError(f"invalid asset candidate: {target}")
            content = source.read_bytes()
            expected = str(repair.get("sha256", "")).casefold()
            if not re.fullmatch(r"[0-9a-f]{64}", expected) or digest(content) != expected:
                raise ValueError(f"asset candidate hash does not match the reviewed map: {target}")
            origin = str(repair.get("origin", "")).strip()
            if not origin:
                raise ValueError("asset repairs require their original-pack provenance")
            name = "servers/" + profile + "/assets/uifiles/" + skin["source"] + "/" + target
            if name in plan:
                raise ValueError(f"duplicate repaired resource: {target}")
            plan[name] = content
            report["asset_repairs"].append({"skin": skin["id"], "target": target, "sha256": expected, "origin": origin})
    managed = {k: v for k, v in plan.items() if k.startswith(UI_PREFIX)}
    if len(managed) > 4096 or sum(map(len, plan.values())) > 64 * 1024 * 1024:
        raise ValueError("compiled addon exceeds client package limits")
    report["payload_files"] = len(managed)
    report["payload_bytes"] = sum(map(len, plan.values()))
    report["data_files"] = sum(name.startswith(DATA_PREFIX) for name in plan)
    return plan, report


def runtime_plan(client: Path) -> tuple[dict[str, bytes], dict]:
    """Update original Lua code while retaining verified local compilation."""
    ledger = json.loads(inside(client, LEDGER).read_text(encoding="utf-8"))
    report = ledger.get("report", {})
    if report.get("runtime") != "lua" or report.get("schema") != 2:
        raise ValueError("a full local Lua conversion is required before a runtime-only update")
    plan = {}
    for name, expected in ledger.get("files", {}).items():
        path = inside(client, name)
        if not path.is_file() or digest(path.read_bytes()) != expected:
            raise ValueError(f"installed file has local changes: {name}")
        if name.startswith(UI_PREFIX+"ui/") and "/lib/compiled/" in name:
            parts=name[len(UI_PREFIX):].split("/")
            plan[DATA_PREFIX+"addon.ui-pack."+parts[1].lower()+"/"+"/".join(parts[2:])]=path.read_bytes()
        elif not name.startswith(UI_PREFIX):
            plan[name] = path.read_bytes()
    present = {row["id"] for row in report["skins"] if row["present"] and not row.get("error")}
    for name, path in tool("package_addon").sources(ROOT):
        parts = name.split("/")
        if parts[0] != "ui" or parts[1] in present:
            plan[UI_PREFIX + name] = path.read_bytes()
    report["version"] = json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))["version"]
    report["payload_files"] = sum(name.startswith(UI_PREFIX) for name in plan)
    report["payload_bytes"] = sum(map(len,plan.values()))
    report["data_files"] = sum(name.startswith(DATA_PREFIX) for name in plan)
    return plan, report


def apply_plan(client: Path, plan: dict[str, bytes], report: dict):
    resolved = client.resolve()
    source = report.get("source_game_dir")
    if source and (resolved.is_relative_to(Path(source).resolve()) or Path(source).resolve().is_relative_to(resolved)):
        raise ValueError("Hailstone's data folder and source game folder must not overlap")
    for ancestor in (resolved, *resolved.parents):
        if ((ancestor / "uifiles").is_dir() or (ancestor / "eqgame.exe").is_file()):
            raise ValueError("the destination is inside a source game installation")
    ledger_path = inside(client, LEDGER)
    previous = json.loads(ledger_path.read_text(encoding="utf-8")) if ledger_path.exists() else {"files": {}}
    existing = dict(previous.get("files", {}))
    entries = {name[len(UI_PREFIX):]: data for name, data in plan.items() if name.startswith(UI_PREFIX)}
    registry = tool("ui_registry")
    registry_path = inside(client, REGISTRY)
    old_registry = registry_path.read_bytes() if registry_path.exists() else None
    registration = None
    if entries:
        if old_registry is None and inside(client, REGISTRY_BACKUP).exists():
            saved = inside(client, REGISTRY_BACKUP).read_bytes()
            # A first local install can stop between its two registry writes.
            # Only its exact prospective clean record is safe to resume here;
            # any older/shared backup needs the client's recovery procedure.
            if saved != registry.merge_registry(entries, report["version"]):
                raise ValueError("addon registry is missing; repair it in Hailstone before local installation")
        registration = registry.merge_registry(entries, report["version"], old_registry)
        owned_ui = registry.managed_files(old_registry)
        existing.update({UI_PREFIX + name: value for name, value in owned_ui.items()})
        # Registry ownership authorizes every presentation in this addon root.
        # Do not turn unrelated pre-existing code into a trusted interface.
        if not owned_ui:
            folder = inside(client, UI_PREFIX.rstrip("/"))
            for path in folder.rglob("*") if folder.exists() else ():
                if not path.is_file():
                    continue
                name = path.relative_to(client).as_posix()
                if name not in plan or digest(path.read_bytes()) != digest(plan[name]):
                    raise ValueError(f"unowned files are present in the UI addon folder: {name}")
    # Validate *every* destination before writing any file. Unowned differing
    # files and locally changed installed files must never be overwritten.
    for name, data in plan.items():
        target = inside(client, name)
        if target.exists():
            current = digest(target.read_bytes())
            if current != digest(data) and current != existing.get(name):
                raise ValueError(f"refusing to overwrite a local file: {name}")
    obsolete = set(existing) - set(plan)
    for name in list(obsolete):
        target = inside(client, name)
        if target.exists() and digest(target.read_bytes()) != existing[name]:
            if name.startswith("scripts/ui-pack/"):
                # A legacy chooser may have local edits. Retire only unchanged,
                # ledger-owned files, and relinquish ownership of the remainder.
                report.setdefault("legacy_script_files_preserved", []).append(name)
                obsolete.remove(name)
                continue
            raise ValueError(f"installed file has local changes: {name}")
    # Stage all content before replacing destinations; os.replace is atomic per
    # file. An interruption is recoverable by rerunning the identical install.
    new_ledger = {"schema": 1, "version": report["version"],
                  "files": {name: digest(data) for name, data in sorted(plan.items())}, "report": report}
    writes = dict(plan)
    if registration is not None:
        writes[REGISTRY_BACKUP] = registration
        writes[REGISTRY] = registration
    writes[LEDGER] = (json.dumps(new_ledger, indent=2) + "\n").encode("utf-8")
    staged = []
    try:
        for name, data in writes.items():
            target = inside(client, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix=".ui-pack-", dir=target.parent)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            staged.append((Path(tmp), target))
        # Commit ownership last, after obsolete files are gone. A failed cleanup
        # leaves the prior ledger available so a retry can still identify them.
        if entries and (registry_path.read_bytes() if registry_path.exists() else None) != old_registry:
            raise ValueError("addon registry changed during installation; close Hailstone and retry")
        for temp, target in staged[:-1]:
            os.replace(temp, target)
        for name in obsolete:
            inside(client, name).unlink(missing_ok=True)
        os.replace(staged[-1][0], staged[-1][1])
    finally:
        for temp, _ in staged:
            temp.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-dir", required=True, type=Path, help="Hailstone data folder, outside game sources")
    parser.add_argument("--game-dir", type=Path)
    parser.add_argument("--bundle", type=Path, help="install an already compiled private bundle ZIP or extracted folder")
    parser.add_argument("--install-dir", type=Path, help="executable folder if separate from the data folder")
    parser.add_argument("--asset-map", type=Path, help="reviewed local image repair map, with --profile")
    parser.add_argument("--profile", help="server folder ID for repaired image resources")
    parser.add_argument("--archive", type=Path, help="also write a private compiled UI addon ZIP; do not redistribute source-derived plans")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--runtime-only", action="store_true", help="update original Lua code, preserving verified local plans")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        if args.runtime_only and args.bundle:
            raise ValueError("choose --runtime-only or --bundle")
        if not args.runtime_only and not args.bundle and not args.game_dir:
            raise ValueError("--game-dir is required for local conversion")
        for output in (args.report, args.archive):
            if output and args.game_dir and output.resolve().is_relative_to(args.game_dir.resolve()):
                raise ValueError("outputs must be outside the read-only source game directory")
        if args.bundle:
            plan,report=tool("local_bundle").read_bundle(args.bundle,args.profile)
        elif args.runtime_only:
            plan,report=runtime_plan(args.client_dir)
            if args.game_dir:
                report["source_game_dir"] = str(args.game_dir.resolve())
        else:
            plan,report=build_plan(args.client_dir,args.game_dir,args.profile,args.install_dir,args.asset_map)
        print("Full client interface access: UI addons can call host interface, account and game actions.")
        if not args.dry_run:
            apply_plan(args.client_dir, plan, report)
            if args.archive:
                tool("local_bundle").write_bundle(args.archive,plan,report)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(("Planned" if args.dry_run else "Installed") + f" {len(plan)} files; "
              + f"{sum(row['present'] for row in report['skins'])}/{len(report['skins'])} source skins present.")
        print("Restart Hailstone and select the UI in its normal Interface list. No Lua startup command is required.")
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Installation stopped: {error}\n")


if __name__ == "__main__":
    main()
