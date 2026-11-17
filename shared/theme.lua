-- Reuse the inherited mechanics and text helpers; apply this skin's source art.
local context = dofile("lib/pack_context.lua")
local T = hs.UI.interfaces.LoadBase("lib/theme.lua")
if T._skinContext == context then return T end
T._skinContext = context
local palette = context.instance.palette
local bg, fg = palette.background, palette.text
local edge = palette.border
local function blend(a, b, amount, alpha)
  return {a[1] * (1 - amount) + b[1] * amount, a[2] * (1 - amount) + b[2] * amount,
          a[3] * (1 - amount) + b[3] * amount, alpha or 1}
end
local roles = {
  text=fg, muted=blend(fg,bg,0.25), faint=blend(fg,bg,0.42), heading=fg,
  panel=bg, panelTop=blend(bg,fg,0.06), window=bg, popup=bg, inset=blend(bg,{0,0,0},0.25),
  title=blend(bg,edge,0.15), titleActive=blend(bg,edge,0.3), border=edge, borderHi=fg,
  frame=blend(bg,fg,0.05), frameHover=blend(bg,edge,0.3), frameActive=blend(bg,edge,0.48),
  frameBorder=blend(bg,fg,0.32), separator=blend(bg,edge,0.45), accent=palette.accent or edge,
  shadow={0,0,0,0.65}, textShadow={0,0,0,0.9}, ink=fg, chatBg=bg, chatText=fg,
  mapBg=bg, hp=palette.hp, hpLow=palette.hp, mana=palette.mana, endurance=palette.endurance,
  xp=palette.experience, aa=palette.experience, cast=palette.casting,
}
for name, value in pairs(roles) do
  if value then
    local target = T.color[name] or {}
    for i=1,4 do target[i] = value[i] or (i==4 and 1 or 0) end
    T.color[name] = target
  end
end
modern_palette_gen = (modern_palette_gen or 0) + 1
local fonts = context.instance.style.fonts or {}
local byType = fonts.byType or {}
local function sourceFont(value, fallback)
  value=tonumber(value)
  return value and value>=1 and value<=6 and value%1==0 and value or fallback
end
local normal = sourceFont(fonts.text or byType.Label,3)
T.font.normal, T.font.small = normal, sourceFont(fonts.small,normal)
T.font.tiny = sourceFont(fonts.small,normal)
T.font.large, T.font.huge = sourceFont(fonts.title,normal), sourceFont(fonts.title,normal)
local selection = {{id=context.profile.id, name=context.profile.label,
  description="The selected interface's artwork, fonts and control styling"}}
T.palettes = {default=context.profile.id, list=selection}
T.Palette = function() return context.profile.id end
T.SetPalette = function() end
T.TestPaletteCycle = function() end
ui_palette = {list=function() return selection end, current=T.Palette, set=T.SetPalette}
context.renderer.StyleTheme(T, context.instance)
local panel=T.Panel
T.Panel=function(...)
  -- The source-owned HUD bridge draws exactly one complete outer frame. Its
  -- inherited movement/resize mechanics must not paint a second generic panel.
  if context.sourceManagedPanel then return false end
  return panel(...)
end
return T
