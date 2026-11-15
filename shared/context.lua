-- One mutable presentation context per Lua environment. Plugin globals are
-- inherited through views, so rawget prevents borrowing the pack's caches.
local owned = rawget(_G, "hailstone_skin_context")
if owned then return owned end
local API = hs.UI
assert(API and API.Supports("interfaces", "LoadBase") and API.Supports("interfaces", "LoadData"),
  "This UI needs a client with the modular interface base-import service")
local renderer = dofile("lib/pack_renderer.lua")
local profile = dofile("lib/pack_profile.lua")
local context = {renderer = renderer, profile = profile, instance = renderer.New(profile), paths = {}}
rawset(_G, "hailstone_skin_context", context)
return context
