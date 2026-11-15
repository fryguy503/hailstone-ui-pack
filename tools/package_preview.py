#!/usr/bin/env python3
"""Create a private Windows preview with twenty verified local Lua interfaces."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DLLS = ("SDL3.dll", "zlib1.dll")
CRT_DLLS = ("msvcp140.dll", "msvcp140_atomic_wait.dll", "vcruntime140.dll", "vcruntime140_1.dll")
LEGAL_FILES = ("LICENSE", "NOTICE.md", "THIRD_PARTY.md", "CHANGELOG.md")
PACKS = ("modern", "gamepad")
DATA_SUFFIXES = {"icons": {".png"}, "pictures": {".png", ".jpg", ".jpeg"}, "flora": {".txt"}}
PRIVATE_PARTS = {"settings", "servers", "scripts", "addons", "ui-addons", "plugins", "logs", "screenshots", "cache",
                 "userdata", "loadingbackgrounds", "bug-reports", "uifiles", "maps", "ui-data", "compiled"}


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def file_inside(path: Path, root: Path) -> Path:
    if (not path.is_file() or any(p.is_symlink() or getattr(p, "is_junction", lambda: False)()
                                for p in (path, *path.parents))
            or not path.resolve().is_relative_to(root.resolve())):
        raise ValueError(f"Missing or unsafe shipped file: {path.name}")
    return path


def reject_game_folder(path: Path):
    resolved = path.resolve()
    for parent in {path, *path.parents, resolved, *resolved.parents}:
        if (parent.name.casefold() == "uifiles" or (parent / "uifiles").is_dir()
                or (parent / "eqgame.exe").is_file() or (parent / "spells_us.txt").is_file()):
            raise ValueError("Game artwork/source directories cannot be preview input or output")


def pe_x64(path: Path):
    with path.open("rb") as stream:
        header = stream.read(64)
        if len(header) != 64 or header[:2] != b"MZ":
            raise ValueError(f"Not a Windows program/library: {path.name}")
        offset = struct.unpack_from("<I", header, 60)[0]
        if offset > 1024 * 1024:
            raise ValueError(f"Invalid Windows program/library header: {path.name}")
        stream.seek(offset)
        pe = stream.read(6)
        if pe[:4] != b"PE\0\0" or len(pe) != 6 or struct.unpack_from("<H", pe, 4)[0] != 0x8664:
            raise ValueError(f"Not a Windows x64 program/library: {path.name}")


def shipped_files(client: Path, source: Path, crt_dir: Path | None = None) -> dict[str, Path]:
    """Enumerate safe shipped paths; nothing is recursively copied from the run folder."""
    if not client.is_dir() or not source.is_dir() or client.resolve() == source.resolve():
        raise ValueError("Use a built client folder and its separate owning source checkout")
    reject_game_folder(client)
    reject_game_folder(source)
    entries = {}
    for name in ("hailstone.exe", *RUNTIME_DLLS):
        path = file_inside(client / name, client)
        pe_x64(path)
        entries[name] = path
    crt = Path(crt_dir) if crt_dir is not None else client
    reject_game_folder(crt)
    for name in CRT_DLLS:
        path = file_inside(crt / name, crt)
        pe_x64(path)
        entries[name] = path
    # Licensing comes from the owning source checkout, never an unrelated addon's MIT license.
    for name in LEGAL_FILES:
        entries[name] = file_inside(source / name, source)
    for pack in PACKS:
        folder = source / "ui" / pack
        file_inside(folder / "ui.ini", source)
        for original in sorted(folder.rglob("*")):
            if not original.is_file():
                continue
            relative = original.relative_to(source)
            if any(p.casefold() in PRIVATE_PARTS or p.startswith(".") for p in relative.parts):
                continue
            if original.suffix.casefold() != ".lua" and original.name != "ui.ini":
                continue
            file_inside(original, source)
            built = file_inside(client / relative, client)
            if digest(original) != digest(built):
                raise ValueError(f"Built UI differs from its source; synchronize the build first: {relative.as_posix()}")
            entries[relative.as_posix()] = built
    for folder_name, suffixes in DATA_SUFFIXES.items():
        folder = source / folder_name
        if not folder.is_dir():
            raise ValueError(f"Missing shipped source data folder: {folder_name}")
        for original in sorted(folder.rglob("*")):
            if not original.is_file() or original.suffix.casefold() not in suffixes:
                continue
            relative = original.relative_to(source)
            if any(p.startswith(".") or p.casefold() in PRIVATE_PARTS for p in relative.parts):
                continue
            file_inside(original, source)
            built = file_inside(client / relative, client)
            if digest(original) != digest(built):
                raise ValueError(f"Built data differs from its source: {relative.as_posix()}")
            entries[relative.as_posix()] = built
    shaders = client / "shaders"
    for path in sorted(shaders.glob("*.spv")):
        file_inside(path, client)
        with path.open("rb") as stream:
            if stream.read(4) != b"\x03\x02\x23\x07":
                raise ValueError(f"Invalid compiled shader: {path.name}")
        entries["shaders/" + path.name] = path
    if not any(name.startswith("shaders/") for name in entries):
        raise ValueError("Built client has no compiled shaders")
    return entries


def tool_module(name: str):
    spec = importlib.util.spec_from_file_location("ui_pack_" + name, ROOT / "tools" / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def companion_files(root: Path) -> dict[str, Path]:
    module = tool_module("package_addon")
    return {"ui-addons/ui-pack/" + name: file_inside(path, root) for name, path in module.sources(root)}


def compiled_files(seed: Path, addon_root: Path = ROOT) -> tuple[dict[str, Path], bytes, bytes, dict]:
    """Verify an explicit installed ledger without copying any player state."""
    seed = Path(seed).resolve()
    reject_game_folder(seed)
    matrix = tool_module("preview_matrix")
    try:
        payload, registration, identity = matrix.seed_payload(seed)
    except (TypeError, KeyError, AttributeError) as error:
        raise ValueError("Compiled seed has invalid ownership/report metadata") from error
    original = companion_files(addon_root)
    code = {name: path for name, path, _, kind in payload if kind == "code"}
    if set(code) != set(original) or any(digest(code[name]) != digest(original[name]) for name in code):
        raise ValueError("Compiled seed code differs from current addon sources; run a runtime-only refresh")
    catalog = json.loads((addon_root / "skins.json").read_text(encoding="utf-8"))
    ledger = json.loads((seed / matrix.LEDGER).read_text(encoding="utf-8"))
    report = ledger["report"]
    if identity["version"] != catalog["version"] or report.get("version") != catalog["version"]:
        raise ValueError("Compiled seed version differs from the current addon")
    present = {row.get("id", "").casefold() for row in report.get("skins", [])
               if row.get("present") and not row.get("error")}
    wanted = {row["id"].casefold() for row in catalog["skins"]}
    if len(wanted) != 20 or present != wanted:
        raise ValueError("Preview seed must contain all twenty successfully compiled skins")
    entries = {name: path for name, path, _, _ in payload}
    for skin in wanted:
        if "ui-data/addon.ui-pack." + skin + "/lib/compiled/index.lua" not in entries:
            raise ValueError("Preview seed is missing a compiled interface index")
    bundle = tool_module("local_bundle")
    for name, path, _, kind in payload:
        content = path.read_bytes()
        if kind == "image":
            bundle._image(content, path.suffix.casefold())
        else:
            bundle._text(content)
            if path.suffix.casefold() == ".lua" and len(content) > bundle.MAX_LUA_BYTES:
                raise ValueError("Seed Lua file exceeds client limit")
    # Rebuild an ownership-only ledger. Never carry arbitrary report fields,
    # local paths, account data or the seed's shared installed.txt registry.
    repairs = []
    for name, _, expected, kind in payload:
        if kind != "image":
            continue
        parts = name.split("/")
        row = next(row for row in report["asset_repairs"]
                   if row.get("skin", "").casefold() == parts[4].casefold()
                   and row.get("target") == "/".join(parts[5:]) and row.get("sha256") == expected)
        origin = row["origin"]
        if not isinstance(origin, str) or len(origin) > 4096 or any(ord(c) < 32 for c in origin):
            raise ValueError("Seed repair provenance must be a short text record")
        repairs.append({"skin": row["skin"], "target": row["target"], "sha256": expected, "origin": origin})
    clean_report = {"schema": 2, "runtime": "lua", "version": catalog["version"],
                    "skins": [{"id": row["id"], "source": row["source"], "present": True}
                              for row in catalog["skins"]],
                    "asset_repairs": repairs}
    clean_ledger = {"schema": 1, "version": catalog["version"],
                    "files": {name: expected for name, _, expected, _ in payload}, "report": clean_report}
    encoded = (json.dumps(clean_ledger, indent=2) + "\n").encode("utf-8")
    return entries, registration, encoded, {**identity, "interfaces": 20,
                                          "data_files": sum(kind == "data" for _, _, _, kind in payload),
                                          "reviewed_images": sum(kind == "image" for _, _, _, kind in payload)}


def support_metadata(root: Path) -> dict | None:
    path = root / "client" / "support.json"
    if not path.is_file():
        return None
    file_inside(path, root)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("client/support.json must contain an object")
    # Carry source hashes, while excluding machine paths, remote URLs and unrelated personal metadata.
    result = {key: value for key, value in data.items() if isinstance(value, str)
              and re.fullmatch(r"[0-9a-fA-F]{40}|[0-9a-fA-F]{64}", value)
              and re.search(r"(?:commit|sha256|revision|base)", key, re.I)}
    return result


def readme(revision: str) -> bytes:
    return f"""Hailstone UI Pack - Windows test preview

Client revision: {revision}

This is a private, locally compiled preview. Keep it local: the presentation
data was generated from the player's installed UI layouts.

Extract into a new writable folder and start Play-UI-Pack.cmd. It uses that
folder for fresh portable client data. A newly generated configuration selects
the Default interface, disables automatic updates, and points to the known
source game installation for artwork. Change that folder in the normal asset
picker if needed. The twenty Lua interfaces and their compiled
presentation modules are already installed and registered. Choose one from
the Interface list at login or Options > Display > Interface in game. Options
shows the selected and loaded interface, source and loading diagnostics.
Gamepad has the same information on its Interface page. No script startup is
needed. Source-derived windows and inherited windows share the chosen skin's
frames, controls and artwork. UI layouts are converted offline; the running
interfaces load Lua presentation data through hs.UI.

The browser helper is not included. Browser-dependent features
are unavailable in this bundle. This archive does not establish live gameplay,
visual parity or controller acceptance; those require separate verification.

preview-manifest.json lists exact file hashes and available source-support
commit/hash metadata. It is local review metadata, not a release signature.
The client LICENSE/NOTICE/THIRD_PARTY files govern the client distribution.
The UI addon has its own MIT license at ui-addons/ui-pack/LICENSE.
""".encode("utf-8")


def neutral_config(game: Path | None) -> bytes:
    values = ["# Fresh private UI preview configuration; no player settings copied.",
              "update.check=0", "update.download=0", "update.install_on_quit=0",
              "ui.name=addon.ui-pack.default", "login.eqhost_imported=1", "audio.pregame_music=0"]
    if game is not None:
        game = Path(game).resolve()
        if any(ord(c) < 32 for c in str(game)) or not game.is_dir() or not (game / "uifiles").is_dir():
            raise ValueError("Preview artwork pointer must name the source game directory")
        values.append("assets.path=" + str(game))
    return ("\n".join(values) + "\n").encode("utf-8")


def launcher() -> bytes:
    return ("@echo off\r\nsetlocal DisableDelayedExpansion\r\n"
            "set \"HAILSTONE_DATA_DIR=%~dp0.\"\r\n"
            "start \"\" /wait \"%~dp0hailstone.exe\" %*\r\nexit /b %ERRORLEVEL%\r\n").encode("ascii")


def package(client: Path, source: Path, revision: str, out: Path, addon_root: Path = ROOT,
            compiled_data_dir: Path | None = None, crt_dir: Path | None = None,
            client_sha256: str | None = None, game_dir: Path | None = None) -> Path:
    if not re.fullmatch(r"[0-9a-fA-F]{40}", revision):
        raise ValueError("--client-revision must be the full verified 40-character client commit")
    client, source, out, addon_root = map(Path, (client, source, out, addon_root))
    if compiled_data_dir is None:
        raise ValueError("An explicit verified compiled_data_dir seed is required")
    compiled_data_dir = Path(compiled_data_dir)
    reject_game_folder(out)
    protected = [client, source, addon_root, compiled_data_dir]
    if crt_dir is not None:
        protected.append(Path(crt_dir))
    if any(out.resolve().is_relative_to(p.resolve()) or p.resolve().is_relative_to(out.resolve()) for p in protected):
        raise ValueError("Preview output must be outside the client, source and addon repositories")
    tool_module("preview_matrix").no_links(out)
    entries = shipped_files(client, source, crt_dir)
    if client_sha256 is not None and (not re.fullmatch(r"[0-9a-fA-F]{64}", client_sha256)
                                      or digest(entries["hailstone.exe"]) != client_sha256.lower()):
        raise ValueError("Built client does not match the expected SHA256")
    presentation, registry, ledger, seed = compiled_files(compiled_data_dir, addon_root)
    if set(entries) & set(presentation):
        raise ValueError("Shipped client and compiled seed paths collide")
    entries.update(presentation)
    if game_dir is None:
        seed_ledger = json.loads((compiled_data_dir / "addons/ui-pack-local-install.json").read_text(encoding="utf-8"))
        known = seed_ledger.get("report", {}).get("source_game_dir")
        game_dir = Path(known) if known else None
    if game_dir is not None:
        game = Path(game_dir).resolve()
        if out.resolve().is_relative_to(game) or game.is_relative_to(out.resolve()):
            raise ValueError("Preview output must be outside the source game directory")
    config = neutral_config(game_dir)
    support = support_metadata(addon_root)
    expected = {str(value).lower() for key, value in (support or {}).items()
                if key in {"feature_commit", "client_commit", "client_revision", "integrated_commit", "target_commit"}}
    if expected and revision.lower() not in expected:
        raise ValueError("Client revision disagrees with the companion's support metadata")
    generated = {"README-UI-PACK-PREVIEW.txt": readme(revision.lower()),
                 "addons/installed.txt": registry, "addons/installed.bak.txt": registry,
                 "addons/ui-pack-local-install.json": ledger,
                 "hailstone.ini": config, "Play-UI-Pack.cmd": launcher()}
    file_hashes = {name: {"size": path.stat().st_size, "sha256": digest(path)}
                   for name, path in sorted(entries.items())}
    file_hashes.update({name: {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
                        for name, data in generated.items()})
    manifest = {"schema": 1, "kind": "windows-ui-pack-test-preview", "client_revision": revision.lower(),
                "browser_helper_enabled": False, "live_gameplay_verified": False, "client_support": support,
                "private_local_conversion": True, "compiled_seed": seed, "builtin_interfaces": list(PACKS),
                "files": dict(sorted(file_hashes.items()))}
    generated["preview-manifest.json"] = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
    archive = out / f"Hailstone-UI-Pack-Preview-Windows-x64-{revision[:8].lower()}.zip"
    if archive.exists() or archive.with_suffix(".zip.sha256").exists():
        raise ValueError("Preview archive and checksum need fresh destinations")
    out.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=9, allowZip64=False) as z:
        for name in sorted(set(entries) | set(generated)):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            if name in generated:
                z.writestr(info, generated[name])
            else:
                with entries[name].open("rb") as stream, z.open(info, "w") as target:
                    shutil.copyfileobj(stream, target, 1024 * 1024)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None:
            raise ValueError("Preview archive CRC verification failed")
        for name, expected in file_hashes.items():
            content = z.read(name)
            if len(content) != expected["size"] or hashlib.sha256(content).hexdigest() != expected["sha256"]:
                raise ValueError("Source changed during preview packaging: " + name)
    archive.with_suffix(".zip.sha256").write_text(f"{digest(archive)}  {archive.name}\n", encoding="utf-8")
    return archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client-dir", type=Path, required=True, help="Built Windows Hailstone run folder")
    parser.add_argument("--client-source", type=Path, required=True, help="Owning client source checkout")
    parser.add_argument("--client-revision", required=True, help="Full verified client commit, recorded without inference")
    parser.add_argument("--client-sha256", help="Expected SHA256 of the verified final hailstone.exe")
    parser.add_argument("--compiled-data-dir", required=True, type=Path, help="Verified local installer data folder with its ownership ledger")
    parser.add_argument("--crt-dir", type=Path, help="Explicit Windows x64 Microsoft CRT redistributable folder")
    parser.add_argument("--game-dir", type=Path, help="Artwork pointer for fresh config; default seed source_game_dir")
    parser.add_argument("--out", type=Path, required=True, help="Output folder outside the repositories and game files")
    args = parser.parse_args()
    try:
        print(package(args.client_dir, args.client_source, args.client_revision, args.out,
                      compiled_data_dir=args.compiled_data_dir, crt_dir=args.crt_dir,
                      client_sha256=args.client_sha256, game_dir=args.game_dir))
    except (OSError, ValueError, json.JSONDecodeError, zipfile.LargeZipFile) as error:
        parser.exit(1, f"Preview package failed: {error}\n")


if __name__ == "__main__":
    main()
