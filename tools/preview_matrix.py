#!/usr/bin/env python3
"""Capture isolated offline Lua login previews from a verified local install.

Only ledger-owned code, compiled Lua data and reviewed image overlays are seeded.
Screenshots establish startup appearance, not gameplay or full visual parity.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
LEDGER = "addons/ui-pack-local-install.json"
MARKER = ".ui-pack-preview.json"


def tool(name):
    spec = importlib.util.spec_from_file_location("preview_" + name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def no_links(path):
    for part in (path, *path.parents):
        if part.is_symlink() or getattr(part, "is_junction", lambda: False)():
            raise ValueError("preview paths must not contain symbolic links or junctions")


def safe_destination(target, output):
    no_links(target)
    if not target.resolve().is_relative_to(output):
        raise ValueError("preview destination leaves its owned output folder")


def overlap(a, b):
    return a.is_relative_to(b) or b.is_relative_to(a)


def seed_payload(seed):
    ledger_path = seed / LEDGER
    no_links(ledger_path)
    if not ledger_path.is_file() or ledger_path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("seed needs a local UI installer ownership ledger")
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    report = ledger.get("report", {})
    if ledger.get("schema") != 1 or report.get("schema") != 2 or report.get("runtime") != "lua":
        raise ValueError("seed must be a current local Lua conversion")
    ownership = ledger.get("files")
    if not isinstance(ownership, dict) or not ownership or len(ownership) > 4096:
        raise ValueError("seed ownership ledger has no files or too many files")
    bundle = tool("local_bundle")
    bundle._spelling(list(ownership))
    payload, total = [], 0
    for name, expected in sorted(ownership.items()):
        kind = bundle._scope(name)
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise ValueError("seed ledger has an invalid file hash")
        path = seed / name
        no_links(path)
        if not path.resolve().is_relative_to(seed) or not path.is_file() or sha(path) != expected:
            raise ValueError("seed file is missing, linked or locally modified: " + name)
        if kind == "image":
            parts = name.split("/")
            if not any(row.get("skin", "").casefold() == parts[4].casefold()
                       and row.get("target") == "/".join(parts[5:]) and row.get("sha256") == expected
                       and row.get("origin") for row in report.get("asset_repairs", [])):
                raise ValueError("seed image is not in the reviewed repair report: " + name)
        total += path.stat().st_size
        payload.append((name, path, expected, kind))
    if total > 64 * 1024 * 1024:
        raise ValueError("seed payload exceeds the local conversion limit")
    entries = {name[len("ui-addons/ui-pack/"):]: path.read_bytes()
               for name, path, _, kind in payload if kind == "code"}
    registration = tool("ui_registry").merge_registry(entries, ledger.get("version"))
    identity = hashlib.sha256(json.dumps(ownership, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return payload, registration, {"ledger_sha256": sha(ledger_path), "owned_files": len(payload),
                                   "owned_manifest_sha256": identity, "version": ledger.get("version")}


def write_results(output, executable_hash, seed_info, results):
    target = output / "preview-results.json"
    safe_destination(target, output)
    fd, temporary = tempfile.mkstemp(prefix=".preview-results-", suffix=".tmp", dir=output)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            json.dump({"schema": 2, "mode": "lua-login", "client_sha256": executable_hash,
                       "seed": seed_info, "fixtures": results}, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def immutable_copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        if source.stat().st_dev == target.parent.stat().st_dev:
            os.link(source, target)
            return "link"
    except OSError:
        pass
    shutil.copy2(source, target)
    return "copy"


def selection_from_log(log, code_root, ui_id):
    explicit = re.findall(r"user interface:\s*([^\s]+)", log, re.I)
    started = re.findall(r"ui:\s*Lua started, scripts in\s+([^\r\n]+)", log, re.I)
    expected = str(code_root).replace("\\", "/").casefold()
    selected = bool(started and started[-1].strip().strip('"').replace("\\", "/").casefold() == expected)
    return selected and (not explicit or explicit[-1].casefold() == ui_id), explicit, started


def ini_value(path, key):
    if not path.is_file():
        return None
    values = [line.split("=", 1)[1].strip() for line in path.read_text(encoding="utf-8").splitlines()
              if line.strip().startswith(key + "=")]
    return values[-1] if values else None


def run_fixture(client, game, output, skin, frames, timeout, payload, registration):
    fixture = output / skin
    safe_destination(fixture, output)
    fixture.mkdir()
    data, screenshot, log_path = fixture / "data", fixture / "login.png", fixture / "client-output.log"
    data.mkdir()
    counts = {"link": 0, "copy": 0}
    for name, source, expected, kind in payload:
        target = data / name
        safe_destination(target, output)
        no_links(source)
        if not source.is_file() or sha(source) != expected:
            raise ValueError("seed changed after verification: " + name)
        counts[immutable_copy(source, target)] += 1
        if sha(target) != expected:
            raise ValueError("seed changed while staging presentation data: " + name)
    for name in ("installed.txt", "installed.bak.txt"):
        target = data / "addons" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(registration)
    ui_id = "addon.ui-pack." + skin.lower()
    config = ("# Generated isolated Lua login preview\nupdate.check=0\nupdate.download=0\n"
              "update.install_on_quit=0\nui.name=" + ui_id + "\nassets.path=" + str(game) +
              "\nlogin.eqhost_imported=1\naudio.pregame_music=0\n")
    (data / "hailstone.ini").write_text(config, encoding="utf-8", newline="\n")
    env = dict(os.environ, HAILSTONE_DATA_DIR=str(data))
    command = [str(client), "--game-dir", str(game), "--frames", str(frames), "--no-audio",
               "--window-size", "1600x1000", "--screenshot", str(screenshot)]
    options = {}
    if os.name == "nt":
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 0
        options.update(startupinfo=startup, creationflags=subprocess.CREATE_NO_WINDOW)
    start = time.monotonic()
    try:
        process = subprocess.run(command, cwd=client.parent, env=env, capture_output=True, timeout=timeout, **options)
        parts, code = (process.stdout, process.stderr), process.returncode
    except subprocess.TimeoutExpired as error:
        parts, code = (error.stdout, error.stderr, str(error)), -1
    except OSError as error:
        parts, code = (str(error),), -2
    log = "\n".join(part.decode("utf-8", errors="replace") if isinstance(part, bytes) else str(part)
                     for part in parts if part)
    for path in sorted((data / "logs").glob("*.log")):
        safe_destination(path, output)
        log += "\n" + path.read_text(encoding="utf-8", errors="replace")
    safe_destination(log_path, output)
    log_path.write_text(log, encoding="utf-8")
    safe_destination(screenshot, output)
    errors = [line for line in log.splitlines() if re.search(
        r"ui (?:script|window) error|ui skin artwork fallback|fatal:|Load(?:Base|Data):|source layouts are not compiled"
        r"|ui art:|ui textures:|imgui vulkan backend|UI font.*(?:not found|could not|using.*built-in)",
        line, re.I)]
    selected, explicit, started = selection_from_log(log, data / "ui-addons/ui-pack/ui" / skin, ui_id)
    if not selected:
        errors.append("client did not confirm the requested Lua interface")
    for path in [data / "hailstone.ini", *sorted((data / "servers").glob("*/server.ini"))]:
        safe_destination(path, output)
        value = ini_value(path, "ui.name")
        if value and value.casefold() != ui_id:
            errors.append("generated configuration changed the selected interface: " + path.relative_to(data).as_posix())
    for name, source, expected, kind in payload:
        target = data / name
        safe_destination(target, output)
        if not target.is_file() or sha(target) != expected:
            errors.append("client changed an immutable owned presentation file: " + name)
    valid_image = screenshot.is_file() and screenshot.stat().st_size > 8
    if valid_image:
        with screenshot.open("rb") as stream:
            valid_image = stream.read(8) == b"\x89PNG\r\n\x1a\n"
    return {"skin": skin, "scene": "login", "interface": ui_id, "selection_matched": selected,
            "interfaces_seen": explicit, "lua_roots_seen": started, "exit_code": code,
            "screenshot": screenshot.relative_to(output).as_posix(), "screenshot_sha256": sha(screenshot) if valid_image else None,
            "log": log_path.relative_to(output).as_posix(), "log_sha256": sha(log_path),
            "rendered": code == 0 and valid_image and not errors, "seconds": round(time.monotonic()-start, 2),
            "seeded": counts, "errors": errors}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", required=True, type=Path)
    parser.add_argument("--game-dir", required=True, type=Path)
    parser.add_argument("--seed-data", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--skin", action="append", help="Repeat exact catalog IDs; default all twenty")
    parser.add_argument("--frames", type=positive_int, default=12)
    parser.add_argument("--timeout", type=positive_int, default=90)
    parser.add_argument("--jobs", type=int, choices=range(1, 5), default=1)
    args = parser.parse_args(argv)
    try:
        ids = [row["id"] for row in json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))["skins"]]
        if args.skin and any(name not in ids for name in args.skin):
            raise ValueError("--skin must be an exact catalog ID")
        for path in (args.output.absolute(), args.client.absolute(), args.game_dir.absolute(), args.seed_data.absolute()):
            no_links(path)
        output, client, game, seed = (p.resolve() for p in (args.output, args.client, args.game_dir, args.seed_data))
        for source in (game, client.parent, seed):
            if overlap(output, source):
                raise ValueError("preview output and source game/client/seed folders must not overlap")
        if overlap(output, ROOT) and (not output.is_relative_to(ROOT) or output.relative_to(ROOT).parts[:1] not in [(".local",), ("artifacts",)]):
            raise ValueError("preview output must not overlap repository tracked paths")
        if output.exists():
            raise ValueError("preview output must be a fresh, nonexistent folder")
        if not client.is_file() or not game.is_dir() or not seed.is_dir():
            raise ValueError("client executable, game folder and seed data folder must exist")
        payload, registration, seed_info = seed_payload(seed)
        fixtures = list(dict.fromkeys(args.skin or ids))
        owned = {name for name, _, _, _ in payload}
        for skin in fixtures:
            if "ui-addons/ui-pack/ui/" + skin + "/ui.ini" not in owned or "ui-data/addon.ui-pack." + skin.lower() + "/lib/compiled/index.lua" not in owned:
                raise ValueError("seed lacks code or local data for selected skin: " + skin)
        executable_hash = sha(client)
        output.mkdir(parents=True)
        (output / MARKER).write_text(json.dumps({"schema": 1, "kind": "ui-pack-lua-login-preview", "client_sha256": executable_hash})+"\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    results, failed = {}, False
    write_results(output, executable_hash, seed_info, [])
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        pending = {pool.submit(run_fixture, client, game, output, skin, args.frames, args.timeout, payload, registration): (n,skin)
                   for n,skin in enumerate(fixtures)}
        for future in as_completed(pending):
            index, skin = pending[future]
            try:
                result = future.result()
            except Exception as error:
                result = {"skin":skin, "scene":"login", "rendered":False, "exit_code":-2, "seconds":0, "errors":[str(error)]}
            results[index] = result
            failed |= not result["rendered"]
            write_results(output, executable_hash, seed_info, [results[n] for n in sorted(results)])
            print(f"{'PASS' if result['rendered'] else 'FAIL'} {skin}-login ({result['seconds']}s)", flush=True)
    seed_info["unchanged"] = all(path.is_file() and sha(path) == expected for _,path,expected,_ in payload)
    seed_info["client_unchanged"] = sha(client) == executable_hash
    failed |= not seed_info["unchanged"] or not seed_info["client_unchanged"]
    write_results(output, executable_hash, seed_info, [results[n] for n in sorted(results)])
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
