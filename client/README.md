# Lua client support

The twenty interfaces use the modular `hs.UI` API. The client provides approved
base-helper imports (`interfaces.LoadBase`), separately stored presentation
modules (`interfaces.LoadData`), image lookup, window actions and the generic
nameplate canvas. The API client is developed and validated independently of
this addon; installing the addon does not modify the client executable.

The portable manager package contains original Lua code and twenty interface
descriptors. The local installer reads the player's UI layouts offline and
generates data-only Lua modules under `ui-data/`. Original artwork stays in the
game installation; reviewed image repairs use a local server-assets overlay.
The running presentations load Lua modules and image resources.

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
license covers this addon's original code and tools. Player-derived layouts and
artwork are excluded from the public portable package and repository.
