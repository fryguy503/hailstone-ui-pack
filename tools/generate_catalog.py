#!/usr/bin/env python3
"""Generate the twenty Lua interface descriptors and original identity metadata."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,31}")


def descriptors(root=ROOT):
    catalog = json.loads((root / "skins.json").read_text(encoding="utf-8"))
    skins = catalog["skins"]
    if catalog.get("schema") != 1 or len(skins) != 20:
        raise ValueError("the pack requires its twenty schema-1 catalog entries")
    ids = [skin["id"].casefold() for skin in skins]
    if len(set(ids)) != len(ids):
        raise ValueError("duplicate skin ID")
    result = {}
    for skin in skins:
        if not ID.fullmatch(skin["id"]) or not ID.fullmatch(skin["source"]):
            raise ValueError("skin IDs and source folders must be safe addon components")
        if any(not isinstance(value, str) or not value.isascii() or "\n" in value
               or "\r" in value for value in skin.values()):
            raise ValueError("catalog values must be single-line ASCII")
        result[f"ui/{skin['id']}/ui.ini"] = (
            f"name={skin['label']}\n"
            f"description={skin['label']} artwork, frames and controls across the interface.\n" +
            ("base=builtin:modern\n" if skin["id"] == "default" else "base=default\n") +
            "input=mouse\n"
            "game_art=all\n")
    return result


def generated_files(root=ROOT):
    result = descriptors(root)
    catalog = json.loads((root / "skins.json").read_text(encoding="utf-8"))
    for skin in catalog["skins"]:
        identity = {"schema": 1, "id": skin["id"], "label": skin["label"], "source": skin["source"],
                    "index": "lib/layouts/index.lua"}
        fields = ", ".join(f"{key}={json.dumps(value)}" for key, value in identity.items())
        result[f"ui/{skin['id']}/lib/pack_profile.lua"] = "return {" + fields + "}\n"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, content in generated_files().items():
        target = ROOT / name
        if args.check:
            if not target.is_file() or target.read_text(encoding="utf-8") != content:
                parser.exit(1, f"{name} needs regeneration\n")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
