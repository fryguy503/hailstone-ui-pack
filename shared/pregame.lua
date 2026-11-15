-- Keep the client's account, server and character flows inside the selected skin.
local context = dofile("lib/pack_context.lua")
local P = hs.UI.interfaces.LoadBase("lib/pregame.lua")
if P._skinContext == context then return P end
P._skinContext = context
local begin = P.Begin
P.Begin = function(...)
  local previous=context.managedChrome
  context.managedChrome={pending=true}
  local scope=_G.hailstone_skin_managed_begin
  local result
  if type(scope)=="function" then result=table.pack(pcall(scope,begin,...))
  else result=table.pack(pcall(begin,...)) end
  context.managedChrome=previous
  if not result[1] then error(result[2],0) end
  local visible=result[2]
  if visible and not context.windowDecorationError then
    local x, y = ui.GetWindowPos()
    local w, h = ui.GetWindowSize()
    ui.PushClipRect(x, y, x+w, y+h, false)
    local ok,why=pcall(context.renderer.Chrome,context.instance,
      {x=x, y=y, w=w, h=h, s=ui.GetIO().uiScale or 1}, {opaque=true})
    ui.PopClipRect()
    if not ok then
      context.windowDecorationError=tostring(why)
      ui.Log("UI skin artwork fallback: "..context.windowDecorationError)
    end
  end
  return table.unpack(result,2,result.n)
end
return P
