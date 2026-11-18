# Hailstone UI Pack

Twenty selectable Lua interfaces with source artwork, frames, controls and fonts.
They appear in Hailstone's normal **Interface** list at login and in Options.
No script startup command or Autorun entry is required.

Default, Default Old, AYA, Delta, Drakah Pers Adeptus, Duxa UI, Graphite,
IB, Lodidodi, Lords, Nemesis, PO2, PO2 Alternate, QQ Custom, QQ UI,
SARS, Sparxx, Takus, Vert, WoW

The empty Velious source folder is excluded by request. See [skins.json](skins.json).

## Install

Install `fryguy503/hailstone-ui-pack` through Hailstone's **Add-ons** window.
Then choose a skin from the normal **User Interface** list at login or in
Options. All twenty interfaces are included in the addon download.

No Python, source-layout compiler, local installer, `/lua` command or Autorun
entry is required. Updates and reinstalling use the same Add-ons window.
Existing accounts, other addons, saved window positions and sizes remain intact.
Use the frame menu's **Reset size** or **Reset position** to restore authored defaults.

Use the modular Lua UI client described in [client requirements](client/README.md).
UI addons have full client interface access; install only code you trust.

## How the interfaces work

The package includes its Lua presentation tables, PNG artwork and shared rendering helpers.
The client loads Lua directly; it does not parse the source game's XML or build
layouts in the player's data folder. Actions and state use the standard `hs.UI` API.

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

## Package contents

The root manifest names the matching `ui-pack-<version>.zip`. It contains twenty
interface descriptors, shared Lua code, shared PNG artwork and bounded Lua layout
modules under each interface's `lib/layouts/` directory. Missing layout modules
or referenced image files prevent a
release from being built. Normal startup never reads a private `ui-data/`
conversion, so an earlier local conversion cannot silently replace the installed layouts.

Raw XML, accounts, server settings, private plugins, caches and logs are not
addon payloads. Legacy local conversion and preview tools remain available to
maintainers; they are not an installation step for players.

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
at runtime and retain the client's license. Visual resources retain their
respective rights; the addon code license does not relicense those resources.
