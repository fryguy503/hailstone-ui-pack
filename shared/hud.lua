-- Inherit window ownership, movement, resizing, Escape, menus and persistence.
-- Source control graphs supply authored bodies; richer client presentations
-- keep their existing behavior and share this skin's frame/control helpers.
local context = dofile("lib/pack_context.lua")
local base = hs.UI.interfaces.LoadBase("lib/hud.lua")
if base._skinContext == context then return base end
base._skinContext = context
local API, R, instance = hs.UI, context.renderer, context.instance
local function managed(fn,...)
  local previous=context.managedChrome
  context.managedChrome={pending=true}
  local scope=_G.hailstone_skin_managed_begin
  local result
  if type(scope)=="function" then result=table.pack(pcall(scope,fn,...))
  else result=table.pack(pcall(fn,...)) end
  context.managedChrome=previous
  if not result[1] then error(result[2],0) end
  return table.unpack(result,2,result.n)
end
local enhanced = {OptionsWindow=true, InventoryWindow=true, SpellBookWnd=true, MapViewWnd=true,
  TaskWnd=true, ItemDisplayWindow=true, PluginConsent=true, WebBrowserWnd=true,
  PetInfoWindow=true, TargetWindow=true, BuffWindow=true, ShortDurationBuffWindow=true,
  ExtendedTargetWnd=true, ExtendedTargetWindow=true}
local function preserve(screen)
  return not screen or enhanced[screen] or screen:match("^Chat%d+$")
    or screen:match("^ItemDisplayWindow#")
end
local function bridge(original, kind)
  return function(screen, title, options, body)
    options = options or {}
    local plan, appearance, why
    local shown=screen and (options.shown==true or API.windows.Shown(screen))
    if kind=="dialog" and options.shown~=nil then shown=options.shown end
    if screen then R.TrackWindow(screen,shown,instance) end
    -- Keep lazy plans lazy: the base also claims its hidden windows, as before.
    if screen and shown then
      appearance = R.Resolve(screen, instance)
      if not preserve(screen) then plan = appearance end
      if plan then
        local ok
        ok, why = R.CanDraw(plan, instance, screen)
        if not ok then plan = nil end
      end
    end
    local opts = options
    if plan and (plan.rect or {}).w and (plan.rect or {}).h then
      opts = {}; for key,value in pairs(options) do opts[key]=value end
      opts.size = function() return math.max(32,plan.rect.w), math.max(24,plan.rect.h) end
      if opts.resizable then opts.resizable={math.min(plan.rect.w,opts.resizable[1]),math.min(plan.rect.h,opts.resizable[2])} end
    end
    context.paths[screen or title] = plan and "source" or "adapted"
    local art = appearance and appearance.art or {}
    local selected = art.drawTemplate
    if not selected or selected=="" then selected=art.template end
    if selected=="" then selected=nil end
    local function draw(x,y,w,h,s)
      local rect={x=x,y=y,w=w,h=h,s=s}
      if kind=="dialog" then
        local wx,wy=ui.GetWindowPos()
        local ww,wh=ui.GetWindowSize()
        ui.PushClipRect(wx,wy,wx+ww,wy+wh,false)
        R.Chrome(instance,{x=wx,y=wy,w=ww,h=wh,s=s},
          {alpha=1,template=selected,frameOnly=true})
        ui.PopClipRect()
      end
      R.Chrome(instance,rect,{alpha=1,template=selected,backgroundOnly=kind=="dialog"})
      if plan then
        local drawn, reason = R.Draw(screen,plan,instance,rect)
        if drawn then return end
        why=reason
      end
      if body then return body(x,y,w,h,s) end
    end
    return managed(original,screen,title,opts,draw)
  end
end
base.Window = bridge(base.Window,"window")
base.Dialog = bridge(base.Dialog,"dialog")
return base
