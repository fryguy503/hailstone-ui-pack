#!/usr/bin/env python3
"""Build the install-ready Lua UI addon, including layouts and UI artwork."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
VERSION = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?")
RUNTIME = {"lib/pack_renderer.lua": "shared/renderer.lua",
           "lib/pack_bindings.lua": "shared/bindings.lua",
           "lib/pack_context.lua": "shared/context.lua",
           "lib/theme.lua": "shared/theme.lua",
           "lib/style.lua": "shared/style.lua",
           "lib/hud.lua": "shared/hud.lua",
           "lib/layout.lua": "shared/layout.lua",
           "lib/pregame.lua": "shared/pregame.lua",
           "lib/pack_source_windows.lua": "shared/source_windows.lua",
           "lib/pack_source_presenters.lua": "shared/source_presenters.lua",
           "lib/pack_status_presenters.lua": "shared/status_presenters.lua",
           "lib/pack_model_presenters.lua": "shared/model_presenters.lua",
           "menus.lua": "shared/menus.lua",
           "zz_pack.lua": "shared/bootstrap.lua"}


def _owned(root, path):
    if (not path.is_file() or path.is_symlink()
            or not path.resolve().is_relative_to(root.resolve())):
        raise ValueError(f"Missing addon source: {path.relative_to(root)}")
    return path


def _presentation_only(value, literals):
    if isinstance(value, str):
        if "bastion" in value.casefold():
            raise ValueError("Private reference in portable layout data")
    elif isinstance(value, dict):
        metadata = {name.casefold() for name in literals.META}
        for key, item in value.items():
            if isinstance(key, str) and key.casefold() in metadata:
                raise ValueError("Private build metadata in portable layout data")
            _presentation_only(key, literals)
            _presentation_only(item, literals)
    elif isinstance(value, list):
        for item in value:
            _presentation_only(item, literals)


def _asset_inventory(root):
    path = root / "assets/manifest.json"
    if not path.exists():
        return None
    inventory = json.loads(_owned(root, path).read_text(encoding="utf-8"))
    if (not isinstance(inventory, dict) or inventory.get("schema") != 1
            or inventory.get("kind") != "portable-ui-raster-art"
            or not isinstance(inventory.get("assets"), dict)
            or not isinstance(inventory.get("resources"), dict)
            or not isinstance(inventory.get("unresolved"), list)):
        raise ValueError("Invalid UI artwork inventory")
    unresolved = set()
    for entry in inventory["unresolved"]:
        if (not isinstance(entry, dict) or not isinstance(entry.get("logical"), str)
                or entry["logical"] in unresolved or entry["logical"] in inventory["resources"]):
            raise ValueError("Invalid unresolved UI artwork resource")
        unresolved.add(entry["logical"])
    for logical, entry in inventory["resources"].items():
        if (not isinstance(logical, str) or not isinstance(entry, dict)
                or not isinstance(entry.get("interface_path"), str)
                or not re.fullmatch(r"assets/[0-9a-f]{64}\.png", entry["interface_path"])):
            raise ValueError("Invalid resolved UI artwork resource")
    for name, entry in inventory["assets"].items():
        if (not re.fullmatch(r"[0-9a-f]{64}\.png", name) or not isinstance(entry, dict)
                or not isinstance(entry.get("sha256"), str)
                or not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"])):
            raise ValueError("Invalid UI artwork asset record")
    return inventory, unresolved


def _portable_sources(root, catalog):
    spec = importlib.util.spec_from_file_location("ui_pack_layout_literals", ROOT / "tools/portable_layouts.py")
    literals = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(literals)
    entries, indices, plans, image_paths, logical_images = {}, {}, {}, set(), set()
    inventory_info = _asset_inventory(root)
    inventory, unresolved = inventory_info if inventory_info else (None, set())
    virtual = re.compile(r"lib/layouts/windows/[0-9a-f]{24}\.lua\Z")
    for skin in catalog["skins"]:
        folder = root / "layouts" / skin["id"]
        index_path = _owned(root, folder / "index.lua")
        files = [index_path, *sorted((folder / "buckets").glob("*.lua"))]
        own = {}
        for path in files:
            _owned(root, path)
            if path.stat().st_size > 4 * 1024 * 1024:
                raise ValueError(f"Lua file exceeds the client limit: {path.relative_to(root)}")
            data = path.read_bytes()
            if b"\0" in data or data.startswith(b"\x1bLua") or b"bastion" in data.lower():
                raise ValueError(f"Invalid portable layout content: {path.relative_to(root)}")
            value = literals.read_lua(path)
            if not isinstance(value, dict):
                raise ValueError(f"Invalid portable layout table: {path.relative_to(root)}")
            _presentation_only(value, literals)
            if path == index_path:
                index = value
            else:
                if not re.fullmatch(r"[01][0-9a-f]\.lua", path.name):
                    raise ValueError("Invalid layout bucket filename")
                for key, plan in value.items():
                    if (not virtual.fullmatch(key) or int(key.rsplit("/", 1)[1][:2], 16) % 32 != int(path.stem, 16)
                            or not isinstance(plan, list) or not plan or plan[0] != "Screen"):
                        raise ValueError(f"Invalid layout bucket entry: {key}")
                    if key in own:
                        raise ValueError(f"Duplicate layout definition: {key}")
                    own[key] = plan
            name = f"ui/{skin['id']}/lib/layouts/" + path.relative_to(folder).as_posix()
            entries[name] = path
        if (index.get("version") != 2 or index.get("portable") != 1 or index.get("storage") != "buckets-v1"
                or index.get("encoding") != "node-tuples-v1" or index.get("skin", "").casefold() != skin["source"].casefold()
                or not isinstance(index.get("windows"), dict) or not index["windows"]):
            raise ValueError(f"Invalid packaged layout index: {skin['id']}")
        for name in index["windows"].values():
            if not isinstance(name, str) or not virtual.fullmatch(name):
                raise ValueError(f"Invalid packaged window path: {skin['id']}")
        for image in index.get("images", {}).values():
            logical = image.get("path")
            if logical:
                logical_images.add(logical)
            if inventory:
                resource = inventory["resources"].get(logical)
                expected = resource["interface_path"] if resource else None
                if image.get("interface_path") != expected or logical and not resource and logical not in unresolved:
                    raise ValueError(f"UI artwork index differs from inventory: {skin['id']}/{logical}")
            if image.get("interface_path"):
                relative = image["interface_path"]
                if not re.fullmatch(r"assets/[0-9a-f]{64}\.png", relative):
                    raise ValueError("Invalid packaged image path")
                image_paths.add(relative)
        indices[skin["id"]], plans[skin["id"]] = index, own
    base = plans.get("default", {})
    for skin, index in indices.items():
        for name, path in index["windows"].items():
            if path not in plans[skin] and path not in base:
                raise ValueError(f"Missing packaged layout bucket/definition: {skin}/{name}")
    if image_paths and inventory is None:
        raise ValueError("Missing UI artwork inventory")
    if inventory:
        if logical_images != set(inventory["resources"]) | unresolved:
            raise ValueError("UI artwork inventory differs from layout resources")
        if image_paths != {"assets/" + name for name in inventory["assets"]}:
            raise ValueError("UI artwork inventory differs from packaged images")
    for name in sorted(image_paths):
        path = _owned(root, root / name)
        details = _png(path)
        expected = inventory["assets"][path.name]
        if any(expected.get(key) != value for key, value in details.items()):
            raise ValueError(f"UI PNG differs from artwork inventory: {name}")
        entries["ui/default/" + name] = path
    return entries


def _png(path):
    if path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("UI PNG exceeds the client limit")
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"Invalid UI PNG: {path.name}")
    offset, dimensions, pixels, compressed = 8, False, False, []
    while offset + 12 <= len(data):
        length = int.from_bytes(data[offset:offset+4], "big")
        kind = data[offset+4:offset+8]
        end = offset + 12 + length
        if end > len(data) or zlib.crc32(data[offset+4:end-4]) != int.from_bytes(data[end-4:end], "big"):
            raise ValueError(f"Corrupt UI PNG: {path.name}")
        if kind == b"IHDR":
            if offset != 8 or length != 13:
                raise ValueError("Invalid UI PNG header")
            w, h, depth, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", data[offset+8:offset+21])
            if not w or not h or w > 16384 or h > 16384 or w * h > 8192 * 8192:
                raise ValueError("UI PNG dimensions exceed the client limit")
            if (depth, color, compression, filtering, interlace) != (8, 6, 0, 0, 0):
                raise ValueError("UI PNG must use noninterlaced RGBA8 pixels")
            dimensions = True
        elif kind == b"IDAT":
            if not dimensions:
                raise ValueError("UI PNG pixels precede the header")
            pixels = True
            compressed.append(data[offset+8:end-4])
        elif kind == b"IEND":
            if length or end != len(data) or not dimensions or not pixels:
                raise ValueError("Incomplete UI PNG")
            _png_pixels(b"".join(compressed), w, h)
            return {"width": w, "height": h, "bytes": len(data),
                    "sha256": hashlib.sha256(data).hexdigest()}
        else:
            raise ValueError("UI PNG contains unsupported metadata or chunks")
        offset = end
    raise ValueError("Incomplete UI PNG")


def _png_pixels(compressed, width, height):
    decoder = zlib.decompressobj()
    stride, total = 1 + 4 * width, 0
    expected = stride * height
    try:
        pending = compressed
        while pending:
            output = decoder.decompress(pending, min(65536, expected - total + 1))
            for offset in range((-total) % stride, len(output), stride):
                if output[offset] > 4:
                    raise ValueError("Invalid UI PNG scanline filter")
            total += len(output)
            if total > expected or decoder.unused_data:
                raise ValueError("UI PNG decoded pixels exceed its dimensions")
            tail = decoder.unconsumed_tail
            if tail and len(tail) == len(pending) and not output:
                raise ValueError("UI PNG decompression made no progress")
            pending = tail
    except zlib.error as error:
        raise ValueError("Invalid UI PNG compressed pixels") from error
    if not decoder.eof or total != expected:
        raise ValueError("Incomplete UI PNG decoded pixels")


def sources(root=ROOT):
    spec = importlib.util.spec_from_file_location("ui_pack_descriptors", ROOT / "tools/generate_catalog.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    expected = generator.generated_files(root)
    entries = {name: root / name for name in [*expected, "LICENSE"]}
    for name in generator.descriptors(root):
        pack = name.rsplit("/", 1)[0]
        entries.update({pack + "/" + target: root / source for target, source in RUNTIME.items()})
    catalog = json.loads((root / "skins.json").read_text(encoding="utf-8"))
    entries.update(_portable_sources(root, catalog))
    has_artwork = (root / "assets/manifest.json").exists()
    for name in ("THIRD_PARTY_NOTICES.md", "licenses/Nemesis-GPL-2.0.txt"):
        path = root / name
        if has_artwork or path.exists():
            entries["ui/default/" + name] = _owned(root, path)
    for name, path in entries.items():
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Missing addon source: {name}")
        if name in expected and path.read_text(encoding="utf-8") != expected[name]:
            raise ValueError(f"Regenerate the UI descriptor: {name}")
        if path.suffix == ".lua" and path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError(f"Lua file exceeds the client limit: {name}")
    if sum(path.stat().st_size for path in entries.values()) > 64 * 1024 * 1024:
        raise ValueError("UI package exceeds the client limit")
    if len(entries) > 4096:
        raise ValueError("UI package exceeds the client file-count limit")
    return sorted(entries.items())


def package(version, out, root=ROOT):
    if not VERSION.fullmatch(version):
        raise ValueError("Use a semantic version, such as 0.1.0-preview.1")
    entries = sources(root)
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    archive = out / f"ui-pack-{version}.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, path in entries:
            item = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            item.create_system = 3
            item.external_attr = 0o100644 << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(item, path.read_bytes())
    data = archive.read_bytes()
    manifest = out / "hailstone-addon.txt"
    manifest.write_text(
        "hailstone-addon 1\nname ui-pack\nkind ui\n"
        f"version {version}\n"
        "min_client 0.7.1-beta\n"
        "author Fryguy\n"
        "description Twenty ready-to-use Lua interfaces with bundled layouts and UI artwork.\n"
        "caps none\n"
        f"package any {len(data)} {hashlib.sha256(data).hexdigest()} {archive.name}\n",
        encoding="utf-8", newline="\n")
    return manifest, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default=json.loads((ROOT / "skins.json").read_text(encoding="utf-8"))["version"])
    parser.add_argument("--out", type=Path, default=ROOT / "artifacts" / "addon")
    parser.add_argument("--root-manifest", action="store_true",
                        help="Copy the matching manifest to the repository root for release preparation")
    args = parser.parse_args()
    try:
        manifest, archive = package(args.version, args.out)
        if args.root_manifest:
            (ROOT / "hailstone-addon.txt").write_bytes(manifest.read_bytes())
        print(manifest)
        print(archive)
        print("Unsigned local preview. Publish the manifest and matching archive together to install from a release.")
    except (OSError, ValueError) as error:
        parser.exit(1, f"Package failed: {error}\n")


if __name__ == "__main__":
    main()
