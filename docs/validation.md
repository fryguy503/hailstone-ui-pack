# Lua conversion validation

The normal addon ships all twenty Lua layout sets. Startup uses its installed
`lib/layouts/` modules and approved Default inheritance, without a local compiler
or private `ui-data/` setup. No XML renderer is shipped or used.

## Clean addon installation

Release checks build and extract the actual archive into an otherwise empty
installation, then run every real `zz_pack.lua` entry and resolve its bundled
window graphs. The test also places poisoned old local-conversion files in
`ui-data/` and verifies that startup never reads them. Indexes and referenced
buckets are mandatory package inputs. These tests establish startup/package
completeness; their inactive UI/base stubs do not establish native rendering or
live gameplay acceptance.

The portable dataset contains 491 Lua modules and 3,281 effective window graphs
across twenty skins, including Default inheritance. An independent comparison
with the verified preceding conversion preserved the public presentation fields:
geometry, anchors, control order, text, fonts, colors, semantic IDs, slots,
artwork references and type defaults. Provenance and private diagnostics are
excluded from the portable tables.

Artwork packaging preserves decoded RGBA pixels, including alpha, in 457 shared
PNG files totaling 15,129,355 bytes. Of 559 logical resource references, 547 resolve
to bundled artwork; twelve absent originals retain the selected styling
fallback. The [resource inventory](../assets/manifest.json) records those cases
and six compatible shared-art aliases. These are package and data checks,
not a new twenty-skin native visual pass.

The final Windows suite ran 126 tests: 124 passed and two skipped because the
host could not create test symlinks. This includes the actual extracted-addon
clean/poisoned-data startup tests for all twenty skins, release determinism,
required artwork/inventory checks and the client API contracts. The renderer
fixture passed 90 cases and 2,690 assertions against the UI API 1.7 client.

## Preceding source-layout preview validation

The preceding source-layout revision added presenters for primary gameplay windows:
inventory, player, target, group, chat, hotbars, item displays, buffs, spell gems
and extended targets. Source frames now preserve independent corner and side-cap
sizes. Readable caption metrics are separate from ornamental title-strip height.
Additional inherited behavior remains accessible through **Client tools...**.
Unsaved HUD placement prefers source coordinates and packs around saved window
positions, the minimap and menu. It preserves the computed sizes/orientation and
leaves dialog layering intact; limited viewport space can still require manual
adjustment. Saved positions take precedence.

The Windows suite has 105 tests: 103 pass and two skip for host symlink permissions.
The standalone Lua fixtures include renderer 87 cases / 2,451 assertions,
chrome 16 / 574, inherited helpers 24 / 974, source presenters 268 assertions,
status presenters 158 and stock-model presenters 140. Checks cover asymmetric
frames, short title strips, per-slot art, nested background layering, source
geometry, action phases, list drag indices and cleanup after Lua errors.

The final CPU rendering audit paints 220 unique skin/window graphs in 378 runs:
200 primary-family runs, 40 single-live-socket variants and 138 status-window
runs. All stacks balance and no action callbacks execute. Canonical hit checks
verify reachable inventory/hotbar slots and nonoverlapping augment sockets;
437 populated buff/gem slots appear exactly once and 230 group/extended-target
row checks pass. This caught and corrected named-but-clipped slots, zero-size
templates, overlapping socket prototypes and fractional-scale wrapping.

The private gallery uses 273 local artwork files and verifies source, payload,
trace and output hashes. Its fonts, host values and item/spell icon handles are
approximations or synthetic fixtures. It uses independent gallery placement,
not the native HUD solver. These CPU images establish source-painter geometry
and artwork evidence; they do not establish native readability or interaction.

A structural sweep uses the real compiled graphs with explicitly synthesized
typed host responses. All 100 primary-family graphs across twenty skins pass.
The broader sweep admits 1,516 of 1,560 graphs across 74 model contracts plus
the five primary families. Forty-four graphs require controls not published by
the host; those retain themed working client presenters. Twenty unavailable
source roots are recorded separately. This sweep dispatches no actions and
does not establish real-model admission or visual acceptance.

Native checks on the preceding C5 Lua runtime accepted Default and Duxa HUD and
inventory captures. Both recorded actual source admission for the seven visible
primary/status windows, without Lua or artwork errors. Earlier captures exposed
placement, clipping and nested background ordering problems; those candidates
were rejected and corrected before these accepted checkpoints.

Nemesis produced source-layout pixels, but its capture failed the foreground
guard. One unchanged retry stopped during character-select scene loading with
Vulkan `VkResult -4` before gameplay. Further GPU launches were stopped; the
full twenty-skin native matrix, smaller viewport cases and ItemDisplay captures
were **not completed**. This is limited native evidence, not full acceptance.
The exact client and all 895 C5 payload files remained unchanged. The final C6
slot/accessibility fixes and shared-art fallbacks have CPU validation only.

The capture fixture uses an unchanged client, real ImGui/Vulkan rendering and
local game textures, with synthetic loopback-only gameplay models and fresh data.
It copies no real accounts or saved player layouts. Gameplay, viewport and
controller acceptance remain separate checks; the twenty-skin native matrix
must be completed before claiming a pack-wide native visual pass.

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

## Earlier preview: rendering and compatibility

Checks cover templates, texture coordinates, child artwork, anchors, gauges,
slots, gems, lists, tabs, text inputs, sliders, state changes and safe adaptation
for unsupported layouts. Helper wrappers preserve return values, IDs, disabled
state, ImGui stacks and context ownership. The API audit checks referenced
methods against actual client bindings.

In the earlier frozen preview, pregame cards and inherited dialogs received selected source frames. Inventory,
spell book, chat, maps, tasks and buff menus preserve enhanced client behavior
with selected styling. Its conservative compatibility gate permitted seven
audited model families: air, casting, aggro, auras, respawn, text prompts and
confirmations. A real-plan audit draws 137 of 140 model/skin combinations; three
unusual status layouts safely retain their functional alternatives. Other compiled
layouts supplied per-window artwork while their working client bodies were retained.
These seven-family results do not describe the revised gameplay presenters above.

## Earlier frozen preview: executed checks

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

These counts describe the earlier `0.2.0-preview.1` runtime, independently from the
new source-layout revision or subsequent client API extensions. Its twenty login
captures are startup/artwork evidence, not acceptance of the revised gameplay
bodies. Capture reports and hashes accompany local artifacts.

## Missing original artwork

Delta's `DX_Target.png` was recovered from a matching downloaded variant and is
included in the portable PNG resources. AYA's `border.dds` and
Duxa's `default_book01.tga` through `default_book04.tga` remain missing. They use
coherent selected-skin fallback styling with explicit diagnostics. Unrelated
same-name files are not counted as original art.

QQ Custom's missing `CS_Buttons.bmp` uses QQUI's compatible 256-by-256 sheet;
QQUI's missing `Buff_Background.tga` uses Duxa's compatible 64-by-128 sheet.
Their referenced animation definitions and crop pixels were compared. These
are shared-art fallbacks, not recovered same-skin originals. Existing originals
always take precedence and mismatched fallback dimensions are rejected.
QQ Custom's missing `classic_pieces01.tga` uses QQUI's sheet after matching all
21 named animation/crop contracts. AYA and SARS use Default's drag-item sheet
for the matching platinum frame; QQUI uses Default's sheet for both matching
crystal frames. These recoveries are restricted to the verified source contracts.
Graphite's missing `window_pieces21.tga` remains diagnosed: candidate atlases
have different or transparent role-icon cells and are not substituted.
The resource inventory also lists other absent legacy sheets rather than
treating an unrelated same-name file as the original.

## Validation boundaries

The artifact report records executed Python/Lua checks, the scene captured and
the exact client revision. Login captures exercise Lua loading, artwork and
the account screen; they do not exercise live inventory, combat, zoning or
controller navigation. Synthetic gameplay captures exercise populated models and
actual rendered pixels, but do not prove live combat, server workflows or every
gesture. Those remain in the [acceptance matrix](acceptance.md). The inventory
character preview remains an explicit host-API gap.

Git contains the Lua runtime, portable presentation tables and the resources
required by the addon. Private development snapshots and screenshots remain
separate local artifacts. No player layouts, account records or client API patch
are included.
