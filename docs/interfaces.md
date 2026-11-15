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
control name alone cannot prove that an action is handled. Audits currently cover
air, casting, aggro, auras, respawn, text prompts and confirmations. Other layouts
retain working client presenters.
Enhanced dialogs, inventory, chat,
buffs and custom windows retain their behavior and receive selected frames,
palette, typography and control decoration. Decorations preserve widget IDs,
inputs, return values and disabled state.

To add a skin, extend `skins.json`, regenerate profiles, compile its source,
then verify model bindings, visual states and live interactions. New features
can use new `hs.UI` methods while inherited presenters remain available.

The client distinguishes requested selection, loaded selection and errors.
Missing or failed entries remain visible with their status. A parsed source
layout is not proof of working interactions.

Every UI addon has full client interface access, including account and game
actions. `caps none` denotes no ScriptHost capability requests; it does not
mean presentation code is sandboxed. Loose folders do not grant registry ownership.
