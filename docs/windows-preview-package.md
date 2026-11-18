# Preparing a Windows test bundle

Run the required client tests first, then package a clean build and verified
local conversion:

```powershell
python tools/package_preview.py `
  --client-dir "C:\Work\hailstone\build-msvc\hailstone" `
  --client-source "C:\Work\hailstone" `
  --client-revision "<full tested client commit>" `
  --compiled-data-dir "C:\HailstoneData" `
  --crt-dir "C:\Runtime\Microsoft.VC145.CRT" `
  --out "C:\TestPackages"
```

Optional `--client-sha256` pins the executable bytes. `--game-dir` overrides the
artwork pointer; otherwise the verified conversion report supplies it.

The allowlist includes the executable, SDL3/zlib and four app-local Microsoft
runtime DLLs, licenses/notices, compiled shaders, Modern and Gamepad, and
source-matching icons, pictures and flora. The verified seed supplies original
addon Lua code, compiled presentation data and reviewed image repairs only.
Every entry is checked against the local installation ledger before packaging.

A fresh UI-only registry and ownership ledger are generated. Neutral settings
disable updates and select Default. `Play-UI-Pack.cmd` keeps data in the extracted
folder. Existing seed settings, accounts, server profiles, other addons, scripts,
logs, caches, maps and debug files are excluded. The original game installation
is read-only and is never bundled.

This legacy developer preview carries local conversion provenance and must not
be published as the portable addon. The normal addon already contains the
portable Lua layout set; users install it through Add-ons without this tool.
The client API source remains a separate repository.

This private workflow retains its 64 MiB payload limit. A full historical
conversion plus the current portable companion can exceed that limit. Use normal
addon installation for the portable pack rather than expanding the limit.

The archive includes a preview README and a manifest with file hashes and the
exact client revision. The browser helper is disabled in this test build.
CRC and SHA checks establish archive integrity; they are not release signatures
or evidence of live gameplay acceptance.
