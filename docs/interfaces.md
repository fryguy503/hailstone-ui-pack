# Interface selection and extension

This is a `ui` addon. The native addon registry discovers twenty `ui.ini` entries.
Stable IDs are lower-case, for example `addon.ui-pack.duxaui-stock`. Default
inherits `builtin:modern`; the other nineteen inherit Default. There is no startup
script, slash command or XML runtime.

Code and presentation data belong to the installed addon under
`ui-addons/ui-pack/`. Each interface owns `lib/layouts/index.lua` and its bounded
lazy buckets. Normal startup loads these Lua table modules directly from the
interface's code root. `hs.UI.interfaces.LoadBase` imports approved code helpers
and Default's layout buckets. Caller authority and window ownership remain intact.
Legacy `ui-data/<stable-interface-id>/` output is not read by these portable
profiles and cannot override the installed layout set.

Each entry supplies profile metadata and shared Lua helpers. The runtime loads
one bundled data index and only the buckets needed. Release preparation resolves
layout facts, templates, attributes, resources and anchors ahead of time.
Identical plans are shared with Default and grouped into bounded files. A release
build fails if an index or referenced bucket is absent; players never run this build step.

Source controls bind to `hs.UI.windows` models and domain APIs. Body replacement
requires an explicit per-model behavioral audit; API availability and a known
control name alone cannot prove that an action is handled.

The source presenters cover inventory and its slot gestures, player and target
status, group rows, chat output and links, hotbar grids, item displays, buffs,
spell gems and extended targets. Audited air, casting, aggro, aura, respawn,
text-entry and confirmation presentations remain available. Source geometry,
anchors and flow strategies place the controls; live host state supplies values,
visibility and actions. Missing capabilities or unsupported graphs retain a
working inherited presentation and a diagnostic.

Item-display files contain templates that the original window code positioned
at runtime. The shared item presenter performs that placement from the live
`hs.UI.windows` values, retaining each source's typography, tabs, icon dimensions
and column proportions. It measures and wraps headers, stat values, socket
descriptions and action captions; one responsive viewport owns scrolling.
Prepared layouts use bounded caches keyed by content, width, font and scale.

The source window's context menu exposes **Client tools...** for additional
client functionality through its inherited body. New or unmatched windows also
keep their built-in body with the selected source frame, palette, typography and
control decoration. Decorations preserve widget IDs, inputs, return values and
disabled state. They do not intercept window registration.

Chrome and content share one outer rectangle. Natural artwork dimensions are
independent for every corner and side cap; a wide corner does not stretch the
side strip. A short ornamental title strip does not force seven-pixel captions:
the selected font reserves its own readable band while the artwork keeps its
natural height. Source titlebar/border flags remain effective.

Source coordinates are preferred initial placement data. The unsaved HUD solver
uses a deterministic priority order and packs main HUD windows around saved
`hud.pos` rectangles, the minimap and the menu. This placement step preserves the
computed window dimensions and orientation; it does not rearrange the controls
inside them. Dialog and transient-overlay layering is unchanged. Saved moves
remain authoritative. When the viewport cannot fit everything, the solver chooses
the least-overlapping candidate rather than promising an overlap-free layout.
Moving or resizing windows keeps per-character UI state, so fresh-install captures
must be distinguished from an existing player's saved layout.

The current host has no inventory character-render texture. The source character
area keeps its real equipment-drop action without substituting an item-preview
actor or an invented portrait. An available compiled graph is not proof of pixel
parity or of every live interaction.

Maintainers add skins through the catalogue, generated profiles, portable Lua
layouts and visual resources, then verify clean addon startup, model bindings,
visual states and live interactions. New features
can use new `hs.UI` methods while inherited presenters remain available.

The client distinguishes requested selection, loaded selection and errors.
Missing or failed entries remain visible with their status. A parsed source
layout is not proof of working interactions.

Every UI addon has full client interface access, including account and game
actions. `caps none` denotes no ScriptHost capability requests; it does not
mean presentation code is sandboxed. Loose folders do not grant registry ownership.
