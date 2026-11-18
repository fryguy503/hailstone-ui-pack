-- Inherit window ownership, movement, resizing, Escape, menus and persistence.
-- Source control graphs supply authored bodies; richer client presentations
-- keep their existing behavior and share this skin's frame/control helpers.
local context = dofile("lib/pack_context.lua")
local base = hs.UI.interfaces.LoadBase("lib/hud.lua")
if base._skinContext == context then return base end
base._skinContext = context
local API, R, instance = hs.UI, context.renderer, context.instance
instance.hud=base
local function presentationPath(screen,path,reason)
  if not screen or context.paths[screen]==path then return end
  context.paths[screen]=path
  if reason and path~="source" then
    instance.messages=instance.messages or {}
    instance.messages["presenter:"..screen]=tostring(reason)
  end
  local log=rawget(ui,"Log")
  if type(log)=="function" then
    log("UI skin presentation: "..screen.."="..path..(reason and "; "..tostring(reason) or ""))
  end
end
local nativeWindow=base.Window
local source
do
  local ok,result=pcall(dofile,"lib/pack_source_presenters.lua")
  if ok then source=result
  else
    if instance.messages then instance.messages.presenter=tostring(result) end
    source={Handles=function()return false end,OpenTools=function()end,Tools=function()end}
  end
end
local generic={CanDraw=function(screen,plan) return R.CanDraw(plan,instance,screen) end,
  Draw=function(screen,plan,owner,box) return R.Draw(screen,plan,owner,box) end}
local sourceChrome=type(rawget(R,"ChromeInsets"))=="function" and type(rawget(R,"WindowChrome"))=="function"
local status
do
  local ok,result=pcall(dofile,"lib/pack_status_presenters.lua")
  if ok then status=result end
end
local models
do
  local ok,result=pcall(dofile,"lib/pack_model_presenters.lua")
  if ok then models=result end
end
local function finishManaged(previous,ok,...)
  context.managedChrome=previous
  if not ok then error((...),0) end
  return ...
end
local function managed(fn,...)
  local previous=context.managedChrome
  context.managedChrome={pending=true}
  local scope=_G.hailstone_skin_managed_begin
  if type(scope)=="function" then return finishManaged(previous,pcall(scope,fn,...)) end
  return finishManaged(previous,pcall(fn,...))
end
local function finishSource(previous,ok,...)
  context.sourceManagedPanel=previous
  if not ok then error((...),0) end
  return ...
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
    local hostShown=screen and API.windows.Shown(screen)
    local shown=screen and (options.shown==true or hostShown)
    if kind=="dialog" and options.shown~=nil then shown=options.shown end
    if screen then R.TrackWindow(screen,shown,instance) end
    -- The base still records the visibility transition. There is no draw
    -- callback to decorate for an explicitly closed native window.
    if screen and not shown and (hostShown==false or kind=="dialog" and options.shown==false) then
      if context.paths[screen] then presentationPath(screen,"adapted") end
      return original(screen,title,options,body)
    end
    -- Keep lazy plans lazy: the base also claims its hidden windows, as before.
    if screen and shown then
      appearance = R.Resolve(screen, instance)
    end
    local presenter
    if appearance then
      if status and status.Handles(screen) then presenter=status
      elseif source.Handles(screen) then presenter=source
      elseif models and models.Handles(screen) then presenter=models end
      if presenter then
        local ok,reason=presenter.CanDraw(screen,appearance,instance)
        if not ok then presenter=nil;why=reason end
      end
      -- A typed presenter supplies its own compatibility checks. Audit the
      -- raw graph only when the generic renderer can actually be selected.
      if not (presenter and sourceChrome) and not preserve(screen) then
        local ok,reason=R.CanDraw(appearance,instance,screen)
        if ok then
          plan=appearance
          presenter=presenter or generic
        elseif not why then why=reason end
      end
    end
    if presenter and sourceChrome then
      local opts={};for key,value in pairs(options) do opts[key]=value end
      local layout=presenter==source and {} or nil
      local originalSize=options.size or function() return appearance.rect.w,appearance.rect.h end
      local fields=appearance.fields or {}
      local designW,designH,sourceFit=appearance.rect.w,appearance.rect.h,1
      local initialInsets=R.ChromeInsets(appearance,instance,1)
      local function fit(w,h,s)
        local io=ui.GetIO()
        local W,H=tonumber(io.width),tonumber(io.height)
        local ratio=1
        if W and W>0 then ratio=math.min(ratio,math.max(1,W-12*s)/(math.max(1,w)*s)) end
        if H and H>0 then ratio=math.min(ratio,math.max(1,H-12*s)/(math.max(1,h)*s)) end
        return math.max(1/s,w*ratio),math.max(1/s,h*ratio),ratio
      end
      opts.size=function(s)
        -- Some bases can limit preparation to their own body. Client tools
        -- still calls the original size before drawing that body.
        if options.bodyOnlySize~=true then originalSize(s) end
        if presenter.Size then designW,designH=presenter.Size(screen,appearance,instance,R,layout)
        else designW,designH=appearance.rect.w,appearance.rect.h end
        local w,h;w,h,sourceFit=fit(math.max(1,designW),math.max(1,designH),s)
        opts.titleHeight=initialInsets.titleHeight*sourceFit
        return w,h
      end
      opts.fit=false -- the selected source's outer rectangle is its initial size
      opts.grow=function(w,h,s) return fit(w,h,s) end -- fit saved sizes without rewriting them
      if presenter.Resize and opts.onResize then
        opts.onResize=function(w,h) return presenter.Resize(screen,appearance,instance,R,w/sourceFit,h/sourceFit) end
      end
      opts.panel=false
      opts.onClose=nil -- the source close box below owns its art and hit rectangle
      opts.titleHeight=initialInsets.titleHeight
      opts.rollup=opts.rollup and initialInsets.titleHeight>0
      opts.place=function(W,H,w,h,s)
        local x,y=(appearance.rect.x or 0)*s,(appearance.rect.y or 0)*s
        if options.place then return options.place(W,H,w,h,s,x,y) end
        return x,y
      end
      if fields.Style_Sizable==false then opts.resizable=nil end
      if opts.resizable then
        opts.resizable={math.min(appearance.rect.w,opts.resizable[1]),math.min(appearance.rect.h,opts.resizable[2])}
      end
      local oldMenu=options.menu
      opts.menu=function(...)
        if oldMenu then oldMenu(...) end
        if body and ui.MenuItem("Client tools...") then source.OpenTools(screen) end
      end
      presentationPath(screen,"source")
      local retired=false
      local function current()
        if hostShown==true and API.windows.Shown(screen)==false then retired=true end
        if retired and screen then R.TrackWindow(screen,false,instance) end
        return not retired
      end
      local function authored(x,y,w,h,s)
        if not current() then return end
        context.sourceManagedPanel=false -- the inherited outer panel has already been skipped
        options.rolled=opts.rolled
        local sourceScale=s*sourceFit
        local io=ui.GetIO()
        ui.SetWindowFontScale(sourceScale/(io.uiScale or 1))
        local success,failure=pcall(function()
        local outer={x=x,y=y,w=w,h=h,s=sourceScale}
        local insets=R.ChromeInsets(appearance,instance,sourceScale)
        local close=insets.close
        local hovered,pressed,clicked=false,false,false
        if close then
          local cx,cy=x+w-close.right-close.width,y+close.top
          clicked=base.T.Hit("##source-close",cx,cy,cx+close.width,cy+close.height)
          hovered,pressed=ui.IsItemHovered(),ui.IsItemActive()
        end
        ui.PushClipRect(x,y,x+w,y+h,false)
        local chromeOk,chromeError=pcall(R.WindowChrome,appearance,title,outer,instance,{closeHovered=hovered,closePressed=pressed})
        ui.PopClipRect()
        if not chromeOk then error(chromeError,0) end
        if clicked then
          if options.onClose then options.onClose() else API.windows.Show(screen,false) end
          retired=true
          current()
          return -- close may destroy or reassign the model before its body runs
        end
        if not current() then return end
        if not opts.rolled then
          local client={x=x+insets.left,y=y+insets.top,w=math.max(1,w-insets.left-insets.right),
            h=math.max(1,h-insets.top-insets.bottom),s=sourceScale}
          local scrollX,scrollY=fields.Style_HScroll==true,fields.Style_VScroll==true
          local child=false
          local ownsScroll=presenter.OwnsScroll and presenter.OwnsScroll(screen,appearance,instance)==true
          if (scrollX or scrollY) and not ownsScroll then
            local virtualW=math.max(client.w,designW*sourceScale-insets.left-insets.right)
            local virtualH=math.max(client.h,designH*sourceScale-insets.top-insets.bottom)
            if presenter.ContentSize then
              local cw,ch=presenter.ContentSize(screen,appearance,instance,R)
              virtualW=math.max(virtualW,(cw or 0)*sourceScale)
              virtualH=math.max(virtualH,(ch or 0)*sourceScale)
            end
            ui.SetCursorScreenPos(client.x,client.y)
            child=true
            local visible=ui.BeginChild("##source-client",client.w,client.h,false,
              scrollX and ui.WindowFlags.HorizontalScrollbar or 0)
            local cx,cy=ui.GetCursorScreenPos()
            client={x=cx,y=cy,w=scrollX and virtualW or client.w,h=scrollY and virtualH or client.h,s=sourceScale}
            if not visible then ui.EndChild();return end
          end
          local ok,drawn,reason,closed=pcall(presenter.Draw,screen,appearance,instance,client,R,layout)
          if child then
            ui.SetCursorScreenPos(client.x,client.y);ui.Dummy(client.w,client.h)
            ui.EndChild()
          end
          if not ok then
            instance.messages=instance.messages or {}
            instance.messages["presenter:"..screen]=tostring(drawn)
            error(drawn,0)
          end
          if closed==true then retired=true end
          if not current() then return end
          if drawn==false then
            local message="Source presenter failed for "..tostring(screen)..": "..tostring(reason or "no reason returned")
            instance.messages=instance.messages or {}
            instance.messages["presenter:"..screen]=message
            error(message,0)
          end
          if instance.messages then instance.messages["presenter:"..screen]=nil end
        end
        end)
        -- Chrome, glyphs and source hit rectangles share one effective scale.
        -- The separate Client tools body keeps its inherited font/geometry scale.
        ui.SetWindowFontScale(s/(io.uiScale or 1))
        if not success then error(failure,0) end
        if current() then source.Tools(screen,title,body,originalSize,s) end
      end
      local previous=context.sourceManagedPanel
      context.sourceManagedPanel=true
      return finishSource(previous,pcall(managed,nativeWindow,screen,title,opts,authored))
    end
    local opts = options
    if plan and (plan.rect or {}).w and (plan.rect or {}).h then
      opts = {}; for key,value in pairs(options) do opts[key]=value end
      opts.size = function() return math.max(32,plan.rect.w), math.max(24,plan.rect.h) end
      if opts.resizable then opts.resizable={math.min(plan.rect.w,opts.resizable[1]),math.min(plan.rect.h,opts.resizable[2])} end
    end
    presentationPath(screen or title,plan and "source" or "adapted",why)
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
