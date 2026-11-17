#!/usr/bin/env python3
"""Build the portable Lua UI addon; player layout data and art stay local."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import zipfile

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


def sources(root=ROOT):
    spec = importlib.util.spec_from_file_location("ui_pack_descriptors", ROOT / "tools/generate_catalog.py")
    generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(generator)
    expected = generator.generated_files(root)
    entries = {name: root / name for name in [*expected, "LICENSE"]}
    for name in generator.descriptors(root):
        pack = name.rsplit("/", 1)[0]
        entries.update({pack + "/" + target: root / source for target, source in RUNTIME.items()})
    for name, path in entries.items():
        if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError(f"Missing addon source: {name}")
        if name in expected and path.read_text(encoding="utf-8") != expected[name]:
            raise ValueError(f"Regenerate the UI descriptor: {name}")
        if path.suffix == ".lua" and path.stat().st_size > 4 * 1024 * 1024:
            raise ValueError(f"Lua file exceeds the client limit: {name}")
    if sum(path.stat().st_size for path in entries.values()) > 64 * 1024 * 1024:
        raise ValueError("UI package exceeds the client limit")
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
        "description Twenty Lua interfaces. Run local source-layout compilation after installing the addon.\n"
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
