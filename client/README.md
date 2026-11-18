# Lua client support

The twenty interfaces use the modular `hs.UI` API. The client provides approved
base-helper imports (`interfaces.LoadBase`), image lookup, window actions and the generic
nameplate canvas. The API client is developed and validated independently of
this addon; installing the addon does not modify the client executable.

The manager package includes all twenty interface descriptors and their Lua
presentation modules. They are ready after normal addon installation. No Python,
compiler, game XML parser or separate player-data setup is needed. Presentation
data is owned by the installed addon under `ui/<skin>/lib/layouts/`.
The running interfaces load these tables through their own module root and the
approved Default base. They do not read the old private `ui-data/` conversions.

Bundled-art rendering requires client UI API 1.7 and
`hs.UI.assets.InterfaceImage`. Earlier modular clients remain usable through
configured game-art lookup or selected-theme drawing when artwork is unavailable.
The guarded fallback does not require a separate layout compilation step.

Use a client that supports the current modular API, then select an installed
interface through the normal Interface list. UI addons are full client
interfaces and can call host interface, account and game actions. No ScriptHost
startup or autorun command is required.

A separate private Windows test preview can include the verified client,
original builtin interfaces, original addon code and locally compiled data.
Its fresh launcher uses an isolated portable data folder; account settings,
server configuration, personal scripts and logs are never copied from an
existing installation. The preview manifest records exact source revision and
file hashes. It is review metadata, not a release signature.

Build and automated checks establish the recorded offline behavior. Live play,
physical-controller operation and complete visual parity require their own
acceptance checks. The client retains its own license; the repository-root
license covers this addon's original code and tools. Imported helpers and visual
resources retain their respective licenses. Player accounts, settings and logs
are excluded from the addon and its repository.
