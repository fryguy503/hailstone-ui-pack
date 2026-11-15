#!/usr/bin/env python3
"""Compile player-owned UI sources into local, data-only Lua presentation plans.

XML is an offline input only. The returned files are installation output, not
redistributable sources. This module never writes the game directory or copies
artwork. The renderer consumes the generated Lua tables without an XML parser.
"""
from __future__ import annotations

import argparse
from collections import Counter
import copy
import hashlib
import json
import math
from pathlib import Path
import re
import statistics
import struct
import sys
from typing import Any
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_sources import _file_index, _is_link, _local_tag, _read_xml, _relative_name, _uifiles
from resolve_assets import image_dimensions

VERSION = 2
MAX_DOCUMENTS = 4096
MAX_DEFINITIONS = 100000
MAX_CONTROLS = 200000
MAX_DEPTH = 64
MAX_TOTAL_XML_BYTES = 256 * 1024 * 1024
CONTROL_TYPES = {
    "Screen", "Page", "TabBox", "Label", "Button", "Gauge", "InvSlot",
    "SpellGem", "Editbox", "Slider", "Listbox", "Combobox", "STMLbox",
    "TreeView", "StaticAnimation", "StaticTintedBlendAnimation", "StaticText",
    "StaticFrame", "StaticHeader", "LayoutBox", "HorizontalLayoutBox",
    "VerticalLayoutBox", "TileLayoutBox", "FinderBox", "TemplateContainer",
    "HotButton", "HtmlComponent",
}
ALWAYS_ARRAY = {"Pieces", "ScreenPieces", "Pages", "Frames", "Columns", "Shading", "Specular", "Templates", "TemplatePieces"}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _scalar(text: str | None, kind: str | None = None) -> Any:
    text = text or ""
    stripped = text.strip()
    # Strings such as labels, texture names and EQType must retain whitespace,
    # leading zeros, and textual 'true'. Schema information prevents guessing.
    if kind in {"string", "wstring"} or (kind and ":" in kind):
        return text
    if kind in {"int", "float", "double"} and stripped.casefold() in {"true", "false"}:
        return text  # malformed numeric input is diagnosed by the typed reader
    if stripped.casefold() in {"true", "false"}:
        return stripped.casefold() == "true"
    if re.fullmatch(r"[-+]?\d+", stripped):
        return int(stripped)
    if re.fullmatch(r"[-+]?(?:\d+\.\d*|\d*\.\d+)(?:[eE][-+]?\d+)?", stripped):
        number = float(stripped)
        return number if math.isfinite(number) else text
    return text


def lua_literal(value: Any) -> str:
    """Serialize literals only, using fixed-width byte escapes for control bytes."""
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("non-finite Lua number")
        return repr(value)
    if isinstance(value, str):
        out = []
        for ch in value:
            n = ord(ch)
            out.append("\\\\" if ch == "\\" else '\\"' if ch == '"'
                       else f"\\{n:03d}" if n < 32 or n == 127 else ch)
        return '"' + "".join(out) + '"'
    if isinstance(value, (tuple, list)):
        return "{" + ",".join(lua_literal(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + lua_literal(str(key)) + "]=" + lua_literal(item)
                               for key, item in sorted(value.items())) + "}"
    raise TypeError(f"unsupported Lua literal: {type(value).__name__}")


def _lua(data: Any) -> bytes:
    return ("-- Generated locally from player-owned files. Do not redistribute.\nreturn "
            + lua_literal(data) + "\n").encode("utf-8")


def _rect(fields: dict) -> dict:
    loc, size = fields.get("Location", {}), fields.get("Size", {})
    loc = loc if isinstance(loc, dict) else {}
    size = size if isinstance(size, dict) else {}
    return {"x": loc.get("X", 0), "y": loc.get("Y", 0),
            "w": size.get("CX", 0), "h": size.get("CY", 0)}


def pack_node(node: dict) -> list:
    """Lossless node-tuples-v1; keep unknown typed fields intact in slot twelve."""
    rect, anchors, art = node["rect"], node["anchors"], node["art"]
    mask = sum(bit for edge, bit in (("top", 1), ("bottom", 2), ("left", 4), ("right", 8))
               if anchors["explicit"][edge])
    return [node["type"], node["item"], node["name"] if node["name"] != node["item"] else False,
            node["source"], [rect[key] for key in ("x", "y", "w", "h")],
            [anchors[key] for key in ("topToTop", "bottomToTop", "leftToLeft", "rightToLeft",
                                      "top", "bottom", "left", "right")] + [mask],
            node["text"], node["font"],
            {name: [color[key] for key in ("r", "g", "b", "a")] for name, color in node["colors"].items()},
            [art[key] for key in ("animation", "background", "template", "drawTemplate")],
            node["eqType"], node["fields"], [pack_node(child) for child in node["children"]],
            node.get("slot"), node.get("gaugeEqType")]


def sample_image_rgba(path: Path, crop: dict | None = None) -> list[float] | None:
    """Median painted pixels, with bounded TGA decoding and optional Pillow.

    Only a small color sample is returned; no artwork is emitted. Transparent
    pixels do not vote, avoiding invisible atlas padding and sentinel colors.
    """
    dimensions = image_dimensions(path)
    if dimensions is None or dimensions[0] * dimensions[1] > 16 * 1024 * 1024:
        return None
    width, height = dimensions
    crop = crop or {"x": 0, "y": 0, "w": width, "h": height}
    x0, y0 = max(0, int(crop["x"])), max(0, int(crop["y"]))
    x1, y1 = min(width, x0 + int(crop["w"])), min(height, y0 + int(crop["h"]))
    if x1 <= x0 or y1 <= y0:
        return None
    stride = max(1, math.ceil(math.sqrt((x1 - x0) * (y1 - y0) / 16384)))
    pixels = []
    if path.suffix.casefold() == ".tga":
        if path.stat().st_size > 64 * 1024 * 1024:
            return None
        data = path.read_bytes()
        if len(data) < 18 or data[1] != 0 or data[2] not in {2, 3, 10, 11} or data[16] not in {8, 16, 24, 32}:
            return None
        depth, pixel_size, position = data[16], (data[16] + 7) // 8, 18 + data[0]

        def pixel(raw: bytes) -> tuple:
            if data[2] in {3, 11}:
                return (raw[0], raw[0], raw[0], raw[1] if depth == 16 else 255)
            if depth == 16:
                word = struct.unpack("<H", raw)[0]
                return (((word >> 10) & 31) * 255 / 31, ((word >> 5) & 31) * 255 / 31,
                        (word & 31) * 255 / 31, (255 if word & 32768 else 0) if data[17] & 15 else 255)
            if depth in {24, 32}:
                return (raw[2], raw[1], raw[0], raw[3] if depth == 32 else 255)
            return (raw[0], raw[0], raw[0], 255)

        def accept(index: int, rgba: tuple) -> None:
            raw_y, raw_x = divmod(index, width)
            y = raw_y if data[17] & 32 else height - 1 - raw_y
            x = width - 1 - raw_x if data[17] & 16 else raw_x
            if x0 <= x < x1 and y0 <= y < y1 and (x - x0) % stride == (y - y0) % stride == 0 and rgba[3] >= 32:
                pixels.append(rgba)
        if data[2] in {2, 3}:
            for y in range(y0, y1, stride):
                for x in range(x0, x1, stride):
                    raw_y = y if data[17] & 32 else height - 1 - y
                    raw_x = width - 1 - x if data[17] & 16 else x
                    start = position + (raw_y * width + raw_x) * pixel_size
                    raw = data[start:start + pixel_size]
                    if len(raw) != pixel_size:
                        return None
                    rgba = pixel(raw)
                    if rgba[3] >= 32:
                        pixels.append(rgba)
        else:
            index = 0
            while index < width * height:
                if position >= len(data):
                    return None
                packet = data[position]; position += 1
                count = (packet & 127) + 1
                if index + count > width * height:
                    return None
                if packet & 128:
                    raw = data[position:position + pixel_size]; position += pixel_size
                    if len(raw) != pixel_size:
                        return None
                    rgba = pixel(raw)
                    for _ in range(count):
                        accept(index, rgba); index += 1
                else:
                    for _ in range(count):
                        raw = data[position:position + pixel_size]; position += pixel_size
                        if len(raw) != pixel_size:
                            return None
                        accept(index, pixel(raw)); index += 1
    else:
        try:
            from PIL import Image
            with Image.open(path) as image:
                image = image.convert("RGBA")
                for y in range(y0, y1, stride):
                    for x in range(x0, x1, stride):
                        rgba = image.getpixel((x, y))
                        if rgba[3] >= 32:
                            pixels.append(rgba)
        except (ImportError, OSError, ValueError):
            return None
    return [statistics.median(p[c] for p in pixels) / 255 for c in range(4)] if pixels else None


def compile_skin(game_dir: str | Path, skin_source: str,
                 asset_map: dict | None = None, *, include_plans: bool = False) -> dict[str, Any]:
    """Return {'files': {pack-relative-name: bytes}, 'report': {...}}.

    Active selected includes are completed by Default's include closure, then
    otherwise-unreferenced selected XML contributes custom definitions. Each
    filename resolves selected -> Default case-insensitively. Diagnostics never
    imply that an unknown control has a working semantic action adapter.
    """
    if (not skin_source or skin_source in {".", ".."} or any(
            c in skin_source for c in "/\\:") or any(ord(c) < 32 for c in skin_source)):
        raise ValueError("skin_source must be one safe UI folder name")
    root = _uifiles(game_dir).resolve()
    folders = {p.name.casefold(): p for p in root.iterdir() if p.is_dir() and not _is_link(p)}
    selected = folders.get(skin_source.casefold())
    default = folders.get("default")
    if selected is None or default is None:
        raise ValueError("selected and Default UI directories must both exist")
    own, own_collisions = _file_index(selected)
    base, base_collisions = _file_index(default)
    if own_collisions or base_collisions:
        raise ValueError("ambiguous case-insensitive UI resource filenames")
    if not own:
        raise ValueError("selected UI directory is empty")
    effective = {k: (n, p, default.name) for k, (n, p) in base.items()}
    effective.update({k: (n, p, selected.name) for k, (n, p) in own.items()})
    diagnostics: list[dict] = []
    provenance: list[dict] = []
    documents: dict[str, ET.Element] = {}
    supplemental_documents: set[str] = set()
    unreferenced_documents: set[str] = set()
    order: list[str] = []
    visiting: set[str] = set()
    total_bytes = 0

    def visit(name: str, depth: int = 0, supplemental: bool = False, unreferenced: bool = False) -> None:
        nonlocal total_bytes
        relative = _relative_name(name)
        if relative is None:
            raise ValueError(f"unsafe UI include: {name!r}")
        key = relative.casefold()
        if key in visiting:
            raise ValueError(f"UI include cycle: {relative}")
        if key in documents:
            return
        if depth > MAX_DEPTH or len(documents) >= MAX_DOCUMENTS:
            raise ValueError("UI include graph exceeds limits")
        if key not in effective:
            raise ValueError(f"missing UI include: {relative}")
        filename, path, origin = effective[key]
        if not path.resolve().is_relative_to(root):
            raise ValueError("UI source leaves game uifiles")
        total_bytes += path.stat().st_size
        if total_bytes > MAX_TOTAL_XML_BYTES:
            raise ValueError("UI XML exceeds aggregate size limit")
        try:
            tree = _read_xml(path)
        except (ET.ParseError, OSError) as exc:
            raise ValueError(f"invalid UI XML {filename}: {exc}") from exc
        documents[key] = tree
        if supplemental:
            supplemental_documents.add(key)
        if unreferenced:
            unreferenced_documents.add(key)
        visiting.add(key)
        provenance.append({"file": filename, "origin": origin,
                           "sha256": _sha(path.read_bytes()), "supplemental": supplemental})
        for node in tree.iter():
            if _local_tag(node.tag) == "Include" and (node.text or "").strip():
                visit(node.text.strip(), depth + 1, supplemental, unreferenced)
        visiting.remove(key)
        order.append(key)

    visit("EQUI.xml")
    # Complete omitted original windows while retaining selected per-file art.
    default_root = _read_xml(base["equi.xml"][1]) if "equi.xml" in base else None
    if default_root is None:
        raise ValueError("Default UI has no EQUI.xml")
    for node in default_root.iter():
        if _local_tag(node.tag) == "Include" and (node.text or "").strip():
            visit(node.text.strip(), supplemental=True)
    for key in sorted(own):
        if key.endswith(".xml") and key not in documents:
            try:
                visit(own[key][0], supplemental=True, unreferenced=True)
            except ValueError as exc:
                diagnostics.append({"kind": "unreferenced_xml", "file": own[key][0], "message": str(exc)})

    schemas: dict[str, ET.Element] = {}
    definitions: dict[str, tuple[ET.Element, dict]] = {}
    for key in order:
        filename, _, origin = effective[key]
        for node in documents[key].iter():
            if _local_tag(node.tag) == "ElementType" and node.get("name"):
                schemas[node.get("name")] = node
        for node in documents[key]:
            item = node.get("item")
            if item:
                key_item = item.casefold()
                if key_item in definitions:
                    previous_source = definitions[key_item][1]
                    preserve = (key in unreferenced_documents
                                or previous_source["origin"].casefold() == selected.name.casefold() != origin.casefold()
                                or (key in supplemental_documents and not previous_source.get("supplemental", False)
                                    and previous_source["origin"].casefold() == origin.casefold()))
                    diagnostics.append({"kind": "duplicate_definition", "name": item,
                                        "file": filename, "message": "active/selected definition retained" if preserve else "last include-order definition used"})
                    if preserve:
                        continue
                definitions[key_item] = (node, {"file": filename, "origin": origin,
                                                "supplemental": key in supplemental_documents,
                                                "unreferenced": key in unreferenced_documents})
                if len(definitions) > MAX_DEFINITIONS:
                    raise ValueError("UI definition count exceeds limit")

    schema_cache: dict[str, dict] = {}

    def schema(kind: str, chain: tuple = ()) -> dict:
        if kind in schema_cache:
            return schema_cache[kind]
        if kind in chain or len(chain) > MAX_DEPTH:
            raise ValueError("UI schema inheritance cycle or depth limit")
        result = {}
        node = schemas.get(kind)
        if node is not None:
            for child in node:
                if _local_tag(child.tag) == "superType":
                    result.update(schema(child.get("type", ""), chain + (kind,)))
            for child in node:
                if _local_tag(child.tag) == "element" and child.get("name"):
                    result[child.get("name")] = child
        schema_cache[kind] = result
        return result

    def fields(node: ET.Element, kind: str | None = None, depth: int = 0, context: str = "") -> Any:
        if depth > MAX_DEPTH:
            raise ValueError("UI property depth exceeds limit")
        if not len(node) and node.get("item") is None and kind not in schemas:
            scalar = _scalar(node.text, kind)
            if kind == "boolean" and str(node.text or "").strip() in {"0", "1"}:
                return str(node.text).strip() == "1"
            if kind == "boolean" and not isinstance(scalar, bool):
                prefix = re.match(r"^(true|false|0|1)\b", str(node.text or "").strip(), re.I)
                diagnostics.append({"kind": "invalid_boolean", "property": context, "value": node.text or "",
                                    "message": "boolean prefix used" if prefix else "false used"})
                return bool(prefix and prefix.group(1).casefold() in {"true", "1"})
            if kind in {"int", "float", "double"} and isinstance(scalar, str):
                prefix = re.match(r"^[\s]*([-+]?\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)", scalar)
                number = float(prefix.group(1)) if prefix else 0.0
                number = number if math.isfinite(number) else 0.0
                diagnostics.append({"kind": "invalid_numeric", "property": context, "value": scalar,
                                    "message": "numeric prefix used" if prefix else "zero used"})
                return int(number) if kind == "int" else number
            return scalar
        spec = schema(kind or _local_tag(node.tag))
        result: dict = {}
        for name, declaration in spec.items():
            default_node = next((d for d in declaration if _local_tag(d.tag) == "default"), None)
            if default_node is not None:
                result[name] = _scalar(default_node.text, declaration.get("type"))
        counts = Counter(_local_tag(c.tag) for c in node)
        for child in node:
            name = _local_tag(child.tag)
            declaration = spec.get(name)
            child_kind = declaration.get("type") if declaration is not None else name
            value = fields(child, child_kind, depth + 1, context + "/" + name)
            repeated = name in ALWAYS_ARRAY or (declaration is not None and
                declaration.get("maxOccurs", declaration.get("maxOccur", "1")) != "1")
            if repeated:
                if name not in result or not isinstance(result[name], list):
                    result[name] = []
                result[name].append(value)
            else:
                if counts[name] > 1 and name not in result:
                    diagnostics.append({"kind": "duplicate_property", "property": context + "/" + name,
                                        "occurrences": counts[name], "message": "last declaration used"})
                result[name] = value
        # Preserve inline attributes without allowing them to become Lua code.
        attrs = {k: v for k, v in node.attrib.items() if k != "item"}
        if attrs:
            result["attributes"] = attrs
        return result

    compiled_fields = {key: fields(node, _local_tag(node.tag), context=node.get("item", ""))
                       for key, (node, _) in definitions.items()}
    defaults = {}
    for kind in sorted(set(schemas) | {_local_tag(node.tag) for node, _ in definitions.values()}):
        values = {}
        for name, declaration in schema(kind).items():
            default_node = next((d for d in declaration if _local_tag(d.tag) == "default"), None)
            if default_node is not None:
                values[name] = _scalar(default_node.text, declaration.get("type"))
        defaults[kind] = values

    def sparse(values: dict, kind: str) -> dict:
        return {key: value for key, value in values.items()
                if key not in defaults.get(kind, {}) or defaults[kind][key] != value}

    sources = {}
    for _, source in definitions.values():
        identifier = _sha(source["file"].casefold().encode())[:16]
        metadata = next((p for p in provenance if p["file"] == source["file"] and p["origin"] == source["origin"]), {})
        sources[identifier] = {**source, "sha256": metadata.get("sha256", "")}
    images: dict = {}
    animations: dict = {}
    templates: dict = {}
    textures: dict[str, tuple[str, dict]] = {}
    for key, (node, _) in definitions.items():
        if _local_tag(node.tag) == "TextureInfo":
            textures[key] = (node.get("item"), compiled_fields[key])
        for descendant in node.iter():
            text = (descendant.text or "").strip()
            if text and (_local_tag(descendant.tag) == "Texture" or
                         (not len(descendant) and Path(text).suffix.casefold() in {".tga", ".dds", ".png", ".bmp", ".jpg", ".jpeg"}
                          and _relative_name(text) is not None)):
                textures.setdefault(text.casefold(), (text, {}))

    repairs: dict = {}
    if asset_map is not None:
        if asset_map.get("schema") != 1 or not isinstance(asset_map.get("assets"), list):
            raise ValueError("asset_map needs schema 1 and an assets list")
        for row in asset_map["assets"]:
            if row.get("skin", "").casefold() != selected.name.casefold():
                continue
            target = _relative_name(row.get("target", ""))
            if target is None or target.casefold() in repairs:
                raise ValueError("unsafe or duplicate asset repair target")
            path = Path(row.get("file", ""))
            if _is_link(path) or not path.is_file() or _sha(path.read_bytes()) != row.get("sha256"):
                raise ValueError("asset repair file/hash mismatch")
            repairs[target.casefold()] = row

    for key, (name, values) in sorted(textures.items()):
        relative = _relative_name(name)
        if relative is None:
            diagnostics.append({"kind": "unsafe_texture", "name": name})
            images[name] = {"missing": True}
            continue
        size = values.get("Size", {})
        image = {"declaredWidth": size.get("CX", 0), "declaredHeight": size.get("CY", 0)}
        resource = effective.get(relative.casefold())
        if resource:
            actual, path, origin = resource
            dimensions = image_dimensions(path)
            image.update({"path": f"uifiles/{origin}/{actual}", "sha256": _sha(path.read_bytes()), "missing": False})
        elif key in repairs:
            row = repairs[key]
            dimensions = image_dimensions(row["file"])
            image.update({"path": f"uifiles/{selected.name}/{relative}", "sha256": row["sha256"],
                          "missing": False, "repair": True})
        else:
            dimensions = None
            image.update({"path": f"uifiles/{selected.name}/{relative}", "missing": True})
            diagnostics.append({"kind": "missing_texture", "name": name})
        image["width"], image["height"] = dimensions or (image["declaredWidth"], image["declaredHeight"])
        if dimensions and all((image["declaredWidth"], image["declaredHeight"])) and dimensions != (image["declaredWidth"], image["declaredHeight"]):
            diagnostics.append({"kind": "texture_size_mismatch", "name": name,
                                "declared": [image["declaredWidth"], image["declaredHeight"]], "actual": list(dimensions)})
        images[name] = image

    for key, (node, _) in definitions.items():
        kind, name, values = _local_tag(node.tag), node.get("item"), compiled_fields[key]
        if kind == "Ui2DAnimation":
            frames = []
            for frame in values.get("Frames", []):
                if not isinstance(frame, dict):
                    continue
                hotspot = frame.get("Hotspot", {})
                frames.append({"image": str(frame.get("Texture", "")).strip(), "rect": _rect(frame),
                               "duration": frame.get("Duration", 1000),
                               "hotspot": {"x": hotspot.get("X", 0), "y": hotspot.get("Y", 0)}})
            animations[name] = {"name": name, "type": kind, "frames": frames,
                                "cycle": values.get("Cycle", False), "grid": values.get("Grid", False), "fields": values}
        elif "Template" in kind or kind in {"Font", "LayoutStrategy", "LayoutVertical", "LayoutHorizontal"}:
            templates[name] = {"name": name, "type": kind, "fields": sparse(values, kind),
                               "provenance": definitions[key][1]}

    referenced_pieces = {(child.text or "").strip().split(":", 1)[-1].casefold()
                         for node, _ in definitions.values() for child in node
                         if _local_tag(child.tag) in {"Pieces", "ScreenPieces", "Pages"}}

    def style_selector(control_kind: str, field: str, checkbox: bool | None = None,
                       eq_type: str | None = None) -> dict:
        candidates = []
        usage = Counter()
        for key, (node, source) in definitions.items():
            if _local_tag(node.tag) != control_kind:
                continue
            value = compiled_fields[key]
            if checkbox is not None and bool(value.get("Style_Checkbox", False)) != checkbox:
                continue
            if eq_type is not None and str(value.get("EQType", "")).strip() != eq_type:
                continue
            art = value.get(field)
            if not art:
                continue
            if control_kind == "Button" and checkbox is False:
                # A fallback text button must not inherit an item/buff slot's
                # atlas decal, even when that slot happens to be a Button.
                if not str(value.get("Text", "")).strip():
                    continue
                template_name = str(art) if isinstance(art, str) else ""
                compact_name = re.sub(r"[^a-z0-9]", "", template_name.casefold())
                if any(word in compact_name for word in ("drag", "icon", "buff", "gem", "hotbutton", "invslot")):
                    continue
                template = (next((record["fields"] for name, record in templates.items()
                                  if name.casefold() == template_name.strip().casefold()), {})
                            if isinstance(art, str) else art)

                def has_grid_reference(node: Any) -> bool:
                    if isinstance(node, str):
                        animation = next((record for name, record in animations.items()
                                          if name.casefold() == node.strip().split(":", 1)[-1].casefold()), None)
                        return bool(animation and animation.get("grid"))
                    if isinstance(node, dict):
                        return any(has_grid_reference(v) for v in node.values())
                    if isinstance(node, list):
                        return any(has_grid_reference(v) for v in node)
                    return False
                if has_grid_reference(template):
                    continue
            signature = lua_literal(art)
            usage[(source["origin"].casefold() == selected.name.casefold(), signature)] += 1
            candidates.append((key, art, signature))
        if not candidates:
            return {}
        if control_kind == "Screen":
            outer = [row for row in candidates if row[0] not in referenced_pieces]
            if outer:
                candidates = outer
            selected_outer = [row for row in candidates
                              if definitions[row[0]][1]["origin"].casefold() == selected.name.casefold()]
            if selected_outer:
                candidates = selected_outer
            preferred = {name.casefold(): i for i, name in enumerate(
                ("InventoryWindow", "PlayerWindow", "MerchantWnd", "OptionsWindow"))}
            preferred_candidates = [row for row in candidates if row[0] in preferred]
            if preferred_candidates:
                candidates = sorted(preferred_candidates, key=lambda row: preferred[row[0]])[:1]
        candidates.sort(key=lambda row: (-int(definitions[row[0]][1]["origin"].casefold() == selected.name.casefold()),
                         -usage[(definitions[row[0]][1]["origin"].casefold() == selected.name.casefold(), row[2])], row[0]))
        key, art, _ = candidates[0]
        provenance = {**definitions[key][1], "control": definitions[key][0].get("item")}
        if isinstance(art, dict):
            name = "@style/" + field + "/" + _sha(lua_literal(art).encode())[:20]
            templates[name] = {"name": name, "type": field, "fields": art,
                               "synthetic": True, "provenance": provenance}
        else:
            name = str(art).strip()
            canonical = next((n for n in templates if n.casefold() == name.casefold()), None)
            if canonical is None:
                diagnostics.append({"kind": "missing_style_template", "name": name, "control": provenance["control"]})
                return {}
            name = canonical
        return {"template": name, "provenance": provenance}

    style = {"frame": style_selector("Screen", "DrawTemplate"),
             "button": style_selector("Button", "Template", checkbox=False),
             "checkbox": style_selector("Button", "Template", checkbox=True),
             "slider": style_selector("Slider", "SliderDrawTemplate"),
             "gauge": style_selector("Gauge", "GaugeDrawTemplate"), "gauges": {},
             "fonts": {"used": [], "byType": {}}, "palette": {}, "paletteOrigins": {}}
    for name, identifier in {"hp": "1", "mana": "2", "endurance": "3", "experience": "4", "target": "6", "casting": "7"}.items():
        selector = style_selector("Gauge", "GaugeDrawTemplate", eq_type=identifier)
        if selector:
            style["gauges"][name] = selector
    if style["gauges"].get("hp"):
        style["gauge"] = style["gauges"]["hp"]
    if not style["button"]:
        style["button"] = style_selector("Button", "ButtonDrawTemplate", checkbox=False)
    if not style["checkbox"]:
        style["checkbox"] = style_selector("Button", "ButtonDrawTemplate", checkbox=True)
    if not style["slider"]:
        style["slider"] = style_selector("Slider", "Template")
    font_counts: dict[str, Counter] = {}
    font_own: dict[str, Counter] = {}
    palette_counts: dict[str, Counter] = {}
    palette_values: dict = {}
    for key, (node, source) in definitions.items():
        kind, values = _local_tag(node.tag), compiled_fields[key]
        if kind not in CONTROL_TYPES:
            continue
        font = values.get("Font")
        if isinstance(font, (int, float)) and not isinstance(font, bool):
            font_counts.setdefault(kind, Counter())[int(font)] += 1
            if source["origin"].casefold() == selected.name.casefold():
                font_own.setdefault(kind, Counter())[int(font)] += 1
        color_fields = {"TextColor": "text", "DisabledColor": "disabled", "HighlightColor": "selection"}
        if kind == "Gauge":
            token = {"1": "hp", "2": "mana", "3": "endurance", "4": "experience", "6": "target", "7": "casting"}.get(str(values.get("EQType", "")).strip())
            if token:
                color_fields["FillTint"] = token
        for field, token in color_fields.items():
            color = values.get(field)
            if not isinstance(color, dict) or not any(c in color for c in ("R", "G", "B")):
                continue
            rgba = tuple(max(0, min(255, float(color.get(c, 255 if c == "Alpha" else 0)))) / 255 for c in ("R", "G", "B", "Alpha"))
            own_color = source["origin"].casefold() == selected.name.casefold()
            palette_counts.setdefault(token, Counter())[(own_color, rgba)] += 1
            palette_values[(token, own_color, rgba)] = {**source, "control": node.get("item"), "field": field}
    for kind, counts in font_counts.items():
        style["fonts"]["byType"][kind] = (font_own.get(kind) or counts).most_common(1)[0][0]
    style["fonts"]["used"] = sorted({font for counts in font_counts.values() for font in counts})
    style["fonts"].update({"text": style["fonts"]["byType"].get("Label", 3),
                           "button": style["fonts"]["byType"].get("Button", 3),
                           "title": style["fonts"]["byType"].get("Screen", 3),
                           "small": min(style["fonts"]["used"], default=1)})
    for token, counts in palette_counts.items():
        own_color, rgba = sorted(counts, key=lambda v: (-int(v[0]), -counts[v], v[1]))[0]
        style["palette"][token] = list(rgba)
        style["paletteOrigins"][token] = palette_values[(token, own_color, rgba)]

    def frame_color(reference: Any) -> tuple[list | None, dict]:
        if not isinstance(reference, str) or not reference.strip():
            return None, {}
        reference = reference.strip()
        animation = next((value for name, value in animations.items() if name.casefold() == reference.casefold()), None)
        crop = None
        if animation and animation["frames"]:
            frame = animation["frames"][0]
            reference, crop = frame["image"], frame["rect"]
        record = next((value for name, value in images.items() if name.casefold() == reference.casefold()), None)
        if not record or record.get("missing"):
            return None, {}
        relative = _relative_name(reference)
        resource = effective.get(relative.casefold()) if relative else None
        path = resource[1] if resource else Path(repairs[relative.casefold()]["file"]) if relative and relative.casefold() in repairs else None
        if path is None:
            return None, {}
        color = sample_image_rgba(path, crop)
        return color, {"method": "opaque atlas-pixel median", "image": reference,
                       "path": record["path"], "sha256": record.get("sha256"), "crop": crop}

    frame_fields = templates.get(style["frame"].get("template", ""), {}).get("fields", {})
    frame_border = frame_fields.get("Border", {})
    frame_border = frame_border if isinstance(frame_border, dict) else {}
    frame_titlebar = frame_fields.get("Titlebar", {})
    frame_titlebar = frame_titlebar if isinstance(frame_titlebar, dict) else {}
    for token, references, neutral in [
        ("background", [frame_fields.get("Background")], [0.06, 0.065, 0.08, 1]),
        ("border", [frame_border.get(key) for key in ("Top", "Middle", "Left", "TopLeft")], [0.25, 0.27, 0.32, 1]),
        ("accent", [frame_titlebar.get(key) for key in ("Middle", "Left", "Right")], [0.55, 0.60, 0.70, 1]),
    ]:
        sampled = [(color, origin) for reference in references
                   for color, origin in [frame_color(reference)] if color is not None]
        if sampled:
            style["palette"][token], style["paletteOrigins"][token] = sampled[0]
        else:
            style["palette"][token] = neutral
            style["paletteOrigins"][token] = {"method": "neutral contrast fallback", "frame": style["frame"]}
            diagnostics.append({"kind": "palette_neutral_fallback", "token": token,
                                "message": "no decodable painted outer-frame atlas crop"})

    expanded = 0
    kinds = Counter()

    def control(key: str, chain: tuple = ()) -> dict:
        nonlocal expanded
        if key in chain or len(chain) > MAX_DEPTH:
            raise ValueError("UI control reference cycle or depth limit")
        expanded += 1
        if expanded > MAX_CONTROLS:
            raise ValueError("expanded UI controls exceed limit")
        node, source = definitions[key]
        kind, item, value = _local_tag(node.tag), node.get("item"), compiled_fields[key]
        kinds[kind] += 1
        value = copy.deepcopy(value)
        anchors = {"topToTop": value.get("TopAnchorToTop", True),
                   "bottomToTop": value.get("BottomAnchorToTop", True),
                   "leftToLeft": value.get("LeftAnchorToLeft", True),
                   "rightToLeft": value.get("RightAnchorToLeft", True),
                   "top": value.get("TopAnchorOffset", 0), "bottom": value.get("BottomAnchorOffset", 0),
                   "left": value.get("LeftAnchorOffset", 0), "right": value.get("RightAnchorOffset", 0)}
        raw_fields = {_local_tag(child.tag) for child in node}
        anchors["explicit"] = {edge: edge.title() + "AnchorOffset" in raw_fields
                               for edge in ("top", "bottom", "left", "right")}
        colors = {}
        for name, color in value.items():
            if isinstance(color, dict) and any(c in color for c in ("R", "G", "B")):
                colors[name] = {"r": color.get("R", 0), "g": color.get("G", 0),
                                "b": color.get("B", 0), "a": color.get("Alpha", 255)}
        result = {"name": value.get("ScreenID") or item, "item": item, "type": kind,
                  "source": _sha(source["file"].casefold().encode())[:16], "rect": _rect(value), "anchors": anchors,
                  "text": str(value.get("Text", "")), "font": value.get("Font", 3), "colors": colors,
                  "art": {"animation": value.get("Animation", ""), "background": value.get("Background", ""),
                          "template": value.get("Template", ""), "drawTemplate": value.get("DrawTemplate", "")},
                  "eqType": value.get("EQType", ""), "fields": sparse(value, kind), "children": []}
        if kind == "InvSlot":
            result["slot"] = value.get("EQType", "")
        if kind in {"Gauge", "Label"}:
            result["gaugeEqType"] = value.get("EQType", "")
        # Preserve the authored interleaving of Pieces/ScreenPieces/Pages.
        for child in node:
            if _local_tag(child.tag) not in {"Pieces", "ScreenPieces", "Pages"}:
                continue
            ref = (child.text or "").strip().split(":", 1)[-1].casefold()
            if ref in definitions:
                result["children"].append(control(ref, chain + (key,)))
            elif ref:
                diagnostics.append({"kind": "missing_control", "name": item, "reference": (child.text or "").strip()})
        if kind not in CONTROL_TYPES:
            diagnostics.append({"kind": "control_adapter_required", "name": item, "type": kind})
        return result

    files: dict[str, bytes] = {}
    windows = {}
    plans = {} if include_plans else None
    for key, (node, _) in sorted(definitions.items()):
        if _local_tag(node.tag) != "Screen":
            continue
        name = node.get("item")
        path = "lib/compiled/windows/" + _sha(name.encode("utf-8"))[:24] + ".lua"
        windows[name] = path
        plan = control(key)
        if plans is not None:
            plans[name] = plan
        files[path] = _lua(pack_node(plan))
    if not windows:
        raise ValueError("selected UI resolves no Screen definitions")
    index = {"version": VERSION, "encoding": "node-tuples-v1", "skin": selected.name, "windows": windows,
             "images": images, "animations": animations, "templates": templates,
             "style": style, "sources": sources, "defaults": defaults, "diagnostics": diagnostics}
    files["lib/compiled/index.lua"] = _lua(index)
    report = {"schema": VERSION, "skin": selected.name, "source_xml": provenance,
              "screen_count": len(windows), "definition_count": len(definitions),
              "expanded_control_count": expanded, "control_types": dict(sorted(kinds.items())),
              "image_count": len(images), "animation_count": len(animations), "template_count": len(templates),
              "style": style, "compiled_bytes": sum(map(len, files.values())),
              "diagnostics": diagnostics, "files": {name: {"bytes": len(data), "sha256": _sha(data)}
                                                       for name, data in sorted(files.items())}}
    result = {"files": files, "report": report}
    if include_plans:
        result.update({"plans": plans, "index": index})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-dir", required=True, type=Path)
    parser.add_argument("--skin", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--asset-map", type=Path)
    args = parser.parse_args()
    # Only a fresh output directory is owned by this invocation. Never overwrite
    # or put generated data inside player sources or the compiler repository.
    output = args.output.resolve()
    sources = _uifiles(args.game_dir).resolve()
    source_game = sources.parent
    repository = Path(__file__).resolve().parents[1]
    if output.is_relative_to(source_game) or source_game.is_relative_to(output) or (output.is_relative_to(repository) and ".local" not in output.relative_to(repository).parts):
        parser.error("output must be local generated data outside game sources and tracked repository paths")
    if output.exists():
        parser.error("output must be a fresh directory")
    result = compile_skin(args.game_dir, args.skin,
                          json.loads(args.asset_map.read_text(encoding="utf-8")) if args.asset_map else None)
    output.mkdir(parents=True)
    for relative, data in result["files"].items():
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    (output / "compile-report.json").write_text(json.dumps(result["report"], indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"skin": args.skin, "screens": result["report"]["screen_count"], "files": len(result["files"])}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
