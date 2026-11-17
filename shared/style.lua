-- Standard menus and fields use the same palette and square frame geometry.
local context = dofile("lib/pack_context.lua")
local base = hs.UI.interfaces.LoadBase("lib/style.lua")
if base._skinContext == context then return base end
base._skinContext = context
local push, pop = base.Push, base.Pop
local stack = {}
base.Push = function(...)
  push(...)
  stack[#stack+1] = context.renderer.PushStyle(context.instance)
  local fonts=context.instance.style.fonts or {}
  local normal=tonumber(fonts.text or (fonts.byType or {}).Label) or 3
  if normal<1 or normal>6 or normal%1~=0 then normal=3 end
  ui.PushFont(normal)
end
base.Pop = function(...)
  local token = stack[#stack]
  if token then ui.PopFont();context.renderer.PopStyle(token); stack[#stack] = nil end
  return pop(...)
end
return base
