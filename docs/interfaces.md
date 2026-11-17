# Interface selection and extension

This is a `ui` addon. The native addon registry discovers twenty `ui.ini` entries.
Stable IDs are lower-case, for example `addon.ui-pack.duxaui-stock`. Default
inherits `builtin:modern`; the other nineteen inherit Default. There is no startup
script, slash command or XML runtime.

Code belongs under `ui-addons/ui-pack/`; player-derived presentation data belongs
under `ui-data/<stable-interface-id>/`. `hs.UI.interfaces.LoadBase` imports approved
base helpers. `LoadData` imports text-only local presentation data from the
effective interface and approved base buckets. Caller authority and window
ownership remain intact.

Each entry supplies profile metadata and shared Lua helpers. The runtime loads
one data index and only the buckets needed. The offline compiler resolves source
includes, templates, attributes, resources and anchors. Identical plans are
shared with Default and grouped into bounded files.

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

To add a skin, extend `skins.json`, regenerate profiles, compile its source,
then verify model bindings, visual states and live interactions. New features
can use new `hs.UI` methods while inherited presenters remain available.

The client distinguishes requested selection, loaded selection and errors.
Missing or failed entries remain visible with their status. A parsed source
layout is not proof of working interactions.

Every UI addon has full client interface access, including account and game
actions. `caps none` denotes no ScriptHost capability requests; it does not
mean presentation code is sandboxed. Loose folders do not grant registry ownership.
