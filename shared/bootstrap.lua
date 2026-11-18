-- The interface loader runs this entry; no ScriptHost startup or window interception.
local context = dofile("lib/pack_context.lua")
assert(next(context.instance.index.windows or {}),
  "The UI pack installation is incomplete. Reinstall ui-pack in Add-ons.")
do
  local widgets = rawget(_G,"hailstone_skin_widgets")
  if type(widgets)~="table" then
    widgets={originals={}}
    rawset(_G,"hailstone_skin_widgets",widgets)
  end
  context.decorationError=nil
  context.windowDecorationError=nil
  -- One transient scope shared by the actual Begin wrapper, including calls
  -- from plugin-private helper environments. The host keeps the caller's owner.
  rawset(_G,"hailstone_skin_managed_begin",function(fn,...)
    local previous=widgets.managed
    widgets.managed={pending=true}
    local result=table.pack(pcall(fn,...))
    widgets.managed=previous
    if not result[1] then error(result[2],0) end
    return table.unpack(result,2,result.n)
  end)
  local function decorate(kind, label, arguments, result)
    label=tostring(label or "")
    local x0,y0,x1,y1=ui.GetItemRect()
    local totalRight=x1
    local options={id=label,caption=(label:match("^(.-)##") or label),
      hovered=ui.IsItemHovered(),active=ui.IsItemActive(),enabled=not ui.IsItemDisabled()}
    if kind=="Checkbox" then options.checked=result[1] end
    if kind=="SliderInt" or kind=="SliderFloat" then
      x0,y0,x1,y1=ui.GetItemRect(true)
      local lo,hi=tonumber(arguments[2]) or 0,tonumber(arguments[3]) or 1
      options.fraction=hi>lo and math.max(0,math.min(1,(result[1]-lo)/(hi-lo))) or 0
      local format=arguments[4]
      local ok,text=pcall(string.format,type(format)=="string" and format or (kind=="SliderInt" and "%d" or "%.2f"),result[1])
      options.valueText=ok and text or tostring(result[1])
    end
    context.renderer.DecorateWidget(context.instance,kind,
      {x=x0,y=y0,w=x1-x0,h=y1-y0,s=ui.GetIO().uiScale or 1},options)
    if (kind=="SliderInt" or kind=="SliderFloat") and options.caption~="" then
      local width,height=ui.CalcTextSize(options.caption)
      local tint=options.enabled and context.instance.palette.text or context.instance.palette.disabled
      ui.DrawText(totalRight-width,y0+(y1-y0-height)/2,tint[1],tint[2],tint[3],tint[4],options.caption)
    end
  end
  local invisible={Button={"Button","ButtonHovered","ButtonActive","Text","Border","BorderShadow"},
    SmallButton={"Button","ButtonHovered","ButtonActive","Text","Border","BorderShadow"},
    Checkbox={"FrameBg","FrameBgHovered","FrameBgActive","CheckMark","Text","Border"},
    SliderInt={"FrameBg","FrameBgHovered","FrameBgActive","SliderGrab","SliderGrabActive","Text","Border"},
    SliderFloat={"FrameBg","FrameBgHovered","FrameBgActive","SliderGrab","SliderGrabActive","Text","Border"}}
  for _,kind in ipairs({"Button","SmallButton","Checkbox","SliderInt","SliderFloat"}) do
    local original=widgets.originals[kind] or ui[kind]
    widgets.originals[kind]=original
    ui[kind]=function(label,...)
      if context.decorationError then return original(label,...) end
      local arguments=table.pack(...)
      local colors=0
      for _,name in ipairs(invisible[kind]) do
        if ui.Col[name] then ui.PushStyleColor(ui.Col[name],0,0,0,0);colors=colors+1 end
      end
      local result=table.pack(original(label,table.unpack(arguments,1,arguments.n)))
      ui.PopStyleColor(colors)
      local ok,why=pcall(decorate,kind,label,arguments,result)
      if not ok and not context.decorationError then
        context.decorationError=tostring(why)
        ui.Log("UI skin artwork fallback: "..context.decorationError)
        local x0,y0,x1,y1=ui.GetItemRect()
        ui.DrawRectFilled(x0,y0,x1,y1,0.12,0.12,0.12,1,0)
        local caption=tostring(label or ""):match("^(.-)##") or tostring(label or "")
        ui.DrawText(x0+4,y0+2,1,1,1,1,caption)
      end
      return table.unpack(result,1,result.n)
    end
  end
  local originalBegin=widgets.originals.Begin or ui.Begin
  widgets.originals.Begin=originalBegin
  ui.Begin=function(name,...)
    local arguments=table.pack(...)
    local token=widgets.managed
    local managed=token and token.pending
    if managed then token.pending=false end
    local result=table.pack(originalBegin(name,table.unpack(arguments,1,arguments.n)))
    local flags=tonumber(arguments[2]) or 0
    local noBackground=ui.WindowFlags.NoBackground or 0
    local noInputs=ui.WindowFlags.NoInputs or 0
    if not result[1] or managed or context.windowDecorationError
        or noBackground~=0 and flags&noBackground~=0 or noInputs~=0 and flags&noInputs==noInputs then
      return table.unpack(result,1,result.n)
    end
    local function decorateWindow()
      local selected
      if tostring(name)=="Options##hailstone" then
        local plan=context.renderer.Resolve("OptionsWindow",context.instance)
        local art=plan and plan.art or {}
        selected=art.drawTemplate
        if not selected or selected=="" then selected=art.template end
        if selected=="" then selected=nil end
      end
      local x,y=ui.GetWindowPos();local w,h=ui.GetWindowSize();local s=ui.GetIO().uiScale or 1
      local cx,cy=ui.GetCursorScreenPos();local cw,ch=ui.GetContentRegionAvail()
      -- Raw/native Begin has already drawn its caption and close button. Its
      -- compatibility decoration must not cover those pixels or hit targets.
      -- Source-owned presenters instead use WindowChrome before their body.
      ui.PushClipRect(x,math.max(y,math.min(y+h,cy)),x+w,y+h,false)
      local ok,why=pcall(context.renderer.Chrome,context.instance,{x=x,y=y,w=w,h=h,s=s},
        {template=selected,frameOnly=true})
      ui.PopClipRect()
      if not ok then error(why,0) end
      context.renderer.Chrome(context.instance,{x=cx,y=cy,w=math.max(0,cw),h=math.max(0,ch),s=s},
        {template=selected,backgroundOnly=true})
    end
    local ok,why=pcall(decorateWindow)
    if not ok then
      context.windowDecorationError=tostring(why)
      ui.Log("UI skin artwork fallback: "..context.windowDecorationError)
    end
    return table.unpack(result,1,result.n)
  end
end
dofile("lib/pack_source_windows.lua")
