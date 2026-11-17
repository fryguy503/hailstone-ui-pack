# Hailstone UI Pack

Twenty selectable Lua interfaces with source artwork, frames, controls and fonts.
They appear in Hailstone's normal **Interface** list at login and in Options.
No script startup command or Autorun entry is required.

Default, Default Old, AYA, Delta, Drakah Pers Adeptus, Duxa UI, Graphite,
IB, Lodidodi, Lords, Nemesis, PO2, PO2 Alternate, QQ Custom, QQ UI,
SARS, Sparxx, Takus, Vert, WoW

The empty Velious source folder is excluded by request. See [skins.json](skins.json).

## How the conversion works

The installer reads the player's source layouts once and compiles them to Lua
presentation data. The client loads Lua only; it does not load XML interfaces.
Actions and state use the standard `hs.UI` API.

Source presenters use the compiled control geometry for inventory, player,
target, group, chat, hotbars, item displays, buffs, spell gems and extended
targets, alongside the audited dialogs and status windows. Frames retain their
independent corners and edge artwork; captions reserve readable space for the
selected font. Source controls call the host's item, chat, spell and window
services rather than imitating game state.

Additional client features remain reachable through **Client tools...** in a
source window's context menu. Windows without a compatible source presenter keep
their working built-in body with selected frames, fonts and control artwork.
Custom skins inherit missing layout data from Default and functionality from Modern.

First-use HUD placement prefers the source coordinates and moves unsaved windows
to reduce collisions while keeping their computed size and orientation. Saved
window moves take precedence. Small viewports may still require manual adjustment.
Existing saved sizes also take precedence. Use the frame menu's **Reset size**
to restore a skin's source dimensions, or **Reset position** for its initial placement.

This remains a preview. Revised gameplay layouts need fresh visual and interaction
acceptance; earlier login captures do not establish source-body fidelity. Full
original pixel parity is not claimed. The host does not expose an inventory
character-render texture, so the source character-preview area has no fabricated
portrait. Missing original artwork uses diagnosed, coordinated fallbacks where
available; compatible shared resources are identified separately from originals.
See [validation](docs/validation.md) and
[acceptance](docs/acceptance.md).

## Install

Use the modular Lua UI client with `hs.UI.interfaces.LoadBase` and `LoadData`.
See [client requirements](client/README.md); a version string alone is insufficient.

Extract the supplied **private compiled setup bundle**, run `Install-UI-Pack.cmd`,
and choose the Hailstone data folder containing `globalconfig.ini` and `addons`,
outside the source game folder. It contains all twenty local conversions and
preserves existing account configuration and other addons.

Or compile from your own client files:

```powershell
python tools/install.py --client-dir "C:\HailstoneData" --install-dir "C:\Hailstone" --game-dir "C:\Games\Client"
```

Restart Hailstone and choose a skin in its normal Interface list. Options shows
the selected and loaded interface and any load failure. UI addons have **full
client interface access**; install only code you trust.

The installer verifies ownership before replacing files and refuses modified or
unowned conflicts. It never writes to the source game folder. Compiled data lives
in `ui-data/<stable-interface-id>/`, separately from addon code, and survives
addon-manager code updates. Refresh original code without recompiling:

```powershell
python tools/install.py --client-dir "C:\HailstoneData" --runtime-only
```

## Portable addon and local data

The root manifest and `ui-pack-0.2.0-preview.2.zip` contain original Lua code and
descriptors only. Installing them registers the entries; source compilation is
still required before loading. Source layouts, compiled player data, artwork,
accounts and settings are excluded from the public repository and archive.

To create a private compiled setup bundle, add
`--archive "C:\TestPackages\Hailstone-UI-Pack-Local.zip"` during installation.
Do not redistribute source-derived layouts or artwork without permission.

## Build and verify

```powershell
python tools/generate_catalog.py --check
python tools/package_addon.py --out . --root-manifest
python -m unittest discover -s tests -p "test_*.py" -v
```

After a local installation, capture isolated login previews:

```powershell
python tools/preview_matrix.py --client "C:\Hailstone\hailstone.exe" --game-dir "C:\Games\Client" --seed-data "C:\HailstoneData" --output "C:\TestPackages\SkinPreviews"
```

Each capture uses neutral settings and a fresh UI-only registry. It does not copy
accounts or personal settings. These are login-only previews. Gameplay layout
review requires populated window models and separate captures; it must not be
inferred from this command. See [Windows test packaging](docs/windows-preview-package.md).

## License

Original addon code and tools are MIT licensed. Built-in helpers are imported
at runtime and retain the client's license. Game artwork and source layouts
retain their owners' rights and are not supplied by this repository.
