#!/usr/bin/env python3
"""Maintainer-only lossless PNG packaging for portable UI presentation assets.

Only images referenced by the sanitized layout library are considered. Source
paths never enter the public manifest; logical game paths and content hashes
retain resource attribution and allow audits. No player install is modified.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import sys

from portable_layouts import HEADER, PRIVATE, ROOT, literal, read_lua, strings

IMAGE_TYPES = {".png", ".tga", ".dds", ".bmp", ".jpg", ".jpeg"}
SHARED = {
    "uifiles/qqcustom-stock/cs_buttons.bmp": ("uifiles/qqui-stock/CS_Buttons.bmp", (256, 256)),
    "uifiles/qqui-stock/buff_background.tga": ("uifiles/DuxaUI-stock/Buff_Background.tga", (64, 128)),
    "uifiles/qqcustom-stock/classic_pieces01.tga": ("uifiles/qqui-stock/classic_pieces01.tga", (256, 256)),
    "uifiles/aya-stock/dragitem5.tga": ("uifiles/default/dragitem5.dds", (256, 256)),
    "uifiles/sars-stock/dragitem5.tga": ("uifiles/default/dragitem5.dds", (256, 256)),
    "uifiles/qqui-stock/dragitem29.tga": ("uifiles/default/dragitem29.dds", (256, 256)),
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_image(root: Path, logical: str) -> Path | None:
    relative = Path(logical)
    if relative.is_absolute() or ".." in relative.parts or ":" in logical or "\\" in logical:
        raise ValueError("unsafe image resource path")
    path = root / relative
    if not path.is_file():
        return None
    if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
        raise ValueError("linked or escaping source image")
    if path.suffix.casefold() not in IMAGE_TYPES or path.stat().st_size > 64 * 1024 * 1024:
        raise ValueError("unsupported or oversized source image")
    return path


def image_bytes(path: Path):
    from PIL import Image
    with Image.open(path) as source:
        if source.width <= 0 or source.height <= 0 or source.width * source.height > 16 * 1024 * 1024:
            raise ValueError("source image dimensions exceed the resource limit")
        rgba = source.convert("RGBA")
        pixels = rgba.tobytes()
        rgba.info.clear()  # Pillow otherwise copies embedded ICC/EXIF into PNG.
        pixel_hash = sha(struct.pack("<II", rgba.width, rgba.height) + pixels)
        output = io.BytesIO()
        rgba.save(output, format="PNG", optimize=True, compress_level=9)
        encoded = output.getvalue()
        # The packaging transform must be pixel-lossless, including alpha.
        with Image.open(io.BytesIO(encoded)) as decoded:
            if decoded.size != rgba.size or decoded.convert("RGBA").tobytes() != pixels:
                raise ValueError("PNG conversion changed source pixels")
        return encoded, pixel_hash, rgba.size


def verify_shared(logical: str, target: str, indices: dict) -> dict:
    """Require an exact counterpart for every named animation using an alias.

    This checks all frame rectangles, durations, hotspots, cycling and grid
    semantics before permitting a shared-image recovery. Filename similarity
    or a matching image size alone is deliberately insufficient.
    """
    def signature(value, index, replace_missing):
        if isinstance(value, list):
            return [signature(item, index, replace_missing) for item in value]
        if isinstance(value, dict):
            result = {}
            for key, item in value.items():
                if key == "image" and isinstance(item, str):
                    path = index.get("images", {}).get(item, {}).get("path", item)
                    result[key] = target if replace_missing and path.casefold() == logical.casefold() else path
                else:
                    result[key] = signature(item, index, replace_missing)
            return result
        return value
    required = []
    for index in indices.values():
        names = {name for name, entry in index.get("images", {}).items()
                 if entry.get("path", "").casefold() == logical.casefold()}
        for name, entry in index.get("animations", {}).items():
            if any(item in names for item in strings(entry)):
                required.append([name, signature(entry, index, True)])
    if not required:
        raise ValueError("shared recovery has no referenced animation contract")
    for name, expected in required:
        if not any(name in index.get("animations", {})
                   and signature(index["animations"][name], index, False) == expected
                   for index in indices.values()):
            raise ValueError("shared recovery does not match its complete animation/crop contract")
    required.sort(key=literal)
    return {"animations_checked": len(required), "contract_sha256": sha(literal(required).encode())}


def build(layouts: Path, game: Path, seed: Path, output: Path, report_file: Path) -> dict:
    indices = {folder.name: read_lua(folder / "index.lua") for folder in sorted(layouts.iterdir()) if folder.is_dir()}
    if len(indices) != 20:
        raise ValueError("all twenty portable layouts are required")
    overlays = sorted((seed / "servers").glob("*/assets")) if seed else []
    refs: dict[str, set[str]] = {}
    for skin, index in indices.items():
        for entry in index.get("images", {}).values():
            logical = entry.get("path")
            if logical:
                if PRIVATE.search(logical):
                    raise ValueError("private resource escaped layout sanitation")
                refs.setdefault(logical, set()).add(skin)
    assets, resources, unresolved = {}, {}, []
    source_cache: dict[str, tuple] = {}
    for logical, skins in sorted(refs.items()):
        source = next((path for base in [*overlays, game] if (path := safe_image(base, logical)) is not None), None)
        kind, shared_from = "source-artwork", None
        expected, contract = None, None
        if source is None and logical.casefold() in SHARED:
            shared_from, expected = SHARED[logical.casefold()]
            contract = verify_shared(logical, shared_from, indices)
            source = safe_image(game, shared_from)
            kind = "compatible-shared-artwork"
        if source is None:
            unresolved.append({"logical": logical, "skins": sorted(skins),
                               "behavior": "selected-palette procedural control fallback; no guessed atlas substitution"})
            continue
        cache_key = str(source.resolve())
        if cache_key not in source_cache:
            source_cache[cache_key] = (*image_bytes(source), sha(source.read_bytes()))
        encoded, pixel_hash, size, original_hash = source_cache[cache_key]
        if expected and size != expected:
            raise ValueError("compatible shared artwork has unexpected dimensions")
        name = pixel_hash + ".png"
        if name not in assets:
            assets[name] = {"sha256": sha(encoded), "pixel_sha256": pixel_hash, "width": size[0], "height": size[1],
                            "bytes": len(encoded), "resources": []}
            output.mkdir(parents=True, exist_ok=True)
            (output / name).write_bytes(encoded)
        assets[name]["resources"].append(logical)
        resources[logical] = {"interface_path": "assets/" + name, "kind": kind,
                              "source_sha256": original_hash, "skins": sorted(skins)}
        if shared_from:
            resources[logical]["shared_from"] = shared_from
            resources[logical]["compatibility"] = contract
    for skin, index in indices.items():
        for entry in index["images"].values():
            resource = resources.get(entry.get("path"))
            if resource:
                entry["interface_path"] = resource["interface_path"]
        path = layouts / skin / "index.lua"
        raw = (HEADER + literal(index) + "\n").encode("utf-8")
        if len(raw) > 4 * 1024 * 1024:
            raise ValueError("portable index exceeds the host limit")
        staged = path.with_suffix(".lua.building")
        staged.write_bytes(raw)
        staged.replace(path)
    manifest = {"schema": 1, "kind": "portable-ui-raster-art", "transform": "lossless RGBA PNG, metadata removed",
                "assets": assets, "resources": resources, "unresolved": unresolved,
                "rights": "Third-party UI and game artwork retains its original owners' rights; see THIRD_PARTY_NOTICES.md."}
    output.mkdir(parents=True, exist_ok=True)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    report = {"schema": 1, "kind": "portable-assets-build", "logical_resources": len(refs),
              "resolved_resources": len(resources), "unique_pngs": len(assets),
              "png_bytes": sum(row["bytes"] for row in assets.values()), "unresolved": unresolved,
              "asset_manifest_sha256": sha((output / "manifest.json").read_bytes()),
              "source_files": {str(Path(name).relative_to(game)) if Path(name).is_relative_to(game) else str(Path(name).relative_to(seed)): details[3]
                               for name, details in source_cache.items()},
              "layout_indices": {skin: sha((layouts / skin / "index.lua").read_bytes()) for skin in indices}}
    report_file.parent.mkdir(parents=True, exist_ok=True)
    report_file.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--layouts", type=Path, default=ROOT / "layouts")
    parser.add_argument("--game-dir", type=Path, required=True)
    parser.add_argument("--seed", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "assets")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output must be a fresh maintainer-owned directory")
    try:
        result = build(args.layouts.resolve(), args.game_dir.resolve(), args.seed.resolve(), args.output.resolve(), args.report.resolve())
        print(json.dumps({key: result[key] for key in ("logical_resources", "resolved_resources", "unique_pngs", "png_bytes")}))
    except (OSError, ValueError, ImportError) as exc:
        parser.exit(1, f"Portable asset build failed: {exc}\n")


if __name__ == "__main__":
    main()
