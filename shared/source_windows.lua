-- Restore separate source status windows whose values the base UI aggregates.
local context = dofile("lib/pack_context.lua")
local API, R, instance = hs.UI, context.renderer, context.instance
local hud = dofile("lib/hud.lua")
local entries = {
  {screen="CastingWindow", title="Casting", closable=false},
  {screen="AggroMeterWnd", title="Aggro", closable=true},
}
for _,entry in ipairs(entries) do
  entry.options = {closable=entry.closable, size=function() return 260,72 end}
end
ui.window("Skin status windows", function()
  if not API.session.InGame() then return end
  for _,entry in ipairs(entries) do
    if API.windows.Shown(entry.screen) then
      local plan = R.Resolve(entry.screen,instance)
      if plan and R.CanDraw(plan,instance,entry.screen) then
        hud.Window(entry.screen,entry.title,entry.options,function() end)
      end
    end
  end
end)
