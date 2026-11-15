# Lua conversion validation

All twenty selected skins compile offline to Lua data consumed through
`hs.UI.interfaces.LoadData`. No XML renderer is shipped or used.

## Measured source coverage

- 3,409 original input files were hashed before and after compilation, unchanged.
- 9,224 expanded screen plans plus twenty indices were generated.
- Plans contain 183,803 expanded control instances.
- All 128 literal client window models and dynamic Chat/Bag families were compared
  with source screens. Default has 123 exact literal matches; other skins have
  122. Newer or differently named windows use styled built-in presenters.
- Data uses bounded buckets and Default deduplication. Files stay below the
  client's 4 MiB source limit and installation data below 64 MiB.

Source quirks produce diagnostics: duplicate singleton locations/sizes use the
last declaration; backup definitions cannot override active definitions;
malformed numeric/boolean suffixes are reported. Legitimate repeated fields
retain their order.

## Rendering and compatibility

Checks cover templates, texture coordinates, child artwork, anchors, gauges,
slots, gems, lists, tabs, text inputs, sliders, state changes and safe adaptation
for unsupported layouts. Helper wrappers preserve return values, IDs, disabled
state, ImGui stacks and context ownership. The API audit checks referenced
methods against actual client bindings.

Pregame cards and inherited dialogs receive selected source frames. Inventory,
spell book, chat, maps, tasks and buff menus preserve enhanced client behavior
with selected styling. A conservative compatibility gate currently permits seven
audited model families: air, casting, aggro, auras, respawn, text prompts and
confirmations. A real-plan audit draws 137 of 140 model/skin combinations; three
unusual status layouts safely retain their functional alternatives. Other compiled
layouts supply per-window artwork and remain available as data while their working
client bodies are retained. Full original geometry conversion remains open.

## Executed checks

- Windows Python suite: 101 tests passed, with two host symlink-privilege skips.
- Linux Python suite: 101 tests passed; the Windows launcher and three standalone
  Lua runners were skipped. Native symlink/path cases ran successfully; Lua
  renderer/helper/menu suites ran on Windows.
- Lua renderer: 61 cases / 1,804 assertions; inherited helpers: 24 / 981;
  menu adapter: six / 233.
- Actual Windows Vulkan login captures: all twenty selected interfaces loaded
  correctly using client `3cb82fa2`, with no UI or artwork errors. The 815 seed
  files and executable remained unchanged.
- All twenty captures were reviewed as a contact sheet; Default, Default Old,
  Duxa and Graphite were also inspected at full size after the selector fixes.

These counts describe the frozen preview, independently from future client API
extensions. Capture reports and hashes accompany local artifacts.

## Missing original artwork

Delta's `DX_Target.png` was recovered from a matching downloaded variant and is
hash-verified before installing a server-local overlay. AYA's `border.dds` and
Duxa's `default_book01.tga` through `default_book04.tga` remain missing. They use
coherent selected-skin fallback styling with explicit diagnostics. Unrelated
same-name files are not counted as original art.

## Validation boundaries

The final artifact report records executed Python/Lua checks, GPU login captures
and the exact client revision. Login captures exercise Lua loading, artwork and
the account screen; they do not exercise live inventory, combat, zoning or
controller navigation. Those remain in the [acceptance matrix](acceptance.md).

Git contains original Lua/tooling only. Private compiled setup bundles and
screenshots are separate local artifacts. No player layouts, account records
or client API patch are included.
