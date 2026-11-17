-- Source-shaped HUD controls with the same domain actions as the built-in presenters.
-- Compiled plans are data; live values and every action remain owned by hs.UI.
local API = hs.UI
local M = {}
local families={TargetWindow=true,GroupWindow=true,BuffWindow=true,ShortDurationBuffWindow=true,
  CastSpellWnd=true,ExtendedTargetWnd=true}
local function fn(module,name)
  local t=API[module]
  if API.Supports and not API.Supports(module,name) then return nil end
  return t and type(t[name])=="function" and t[name] or nil
end
local function call(module,name,...)
  local f=fn(module,name);if f then return f(...) end
end
local function id(node) return tostring(node.name or node.item or "") end
local function number(n,default) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n or default or 0 end
local function clone(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value)do out[k]=clone(v)end
  return setmetatable(out,getmetatable(value))
end
local function walk(node,visit,depth)
  depth=depth or 0;if depth>64 then return false end
  if visit(node)==false then return false end
  for _,child in ipairs(node.children or {})do if not walk(child,visit,depth+1)then return false end end
  return true
end
local function state(instance,screen)
  instance.statusPresenters=instance.statusPresenters or {}
  local s=instance.statusPresenters[screen]
  if not s then s={controls={},diagnostics={}};instance.statusPresenters[screen]=s end
  return s
end
local function diagnostic(instance,screen,key,text)
  local s=state(instance,screen)
  if s.diagnostics[key] then return end
  s.diagnostics[key]=text
  if type(ui.Log)=="function"then ui.Log("UI source status: "..screen..": "..text)end
end
local function consume(instance)
  local t=instance.theme
  if t and t.TakeRightClick then t.TakeRightClick()end
end
local function shown(screen,child)
  return call("windows","ChildShown",screen,child)~=false
end
local function enabled(screen,child)
  return call("windows","ChildState",screen,child)~=false
end
local function hit(screen,child,box,on)
  ui.SetCursorScreenPos(box.x,box.y)
  ui.BeginDisabled(on==false)
  local clicked=ui.InvisibleButton("##source-status:"..screen..":"..child,math.max(1,box.w),math.max(1,box.h))
  local hover=ui.IsItemHovered()
  ui.EndDisabled()
  return clicked,hover
end
local function caption(node,box,text,color,align)
  if text==nil or text==""then return end
  text=tostring(text);color=color or {1,1,1,1}
  ui.PushFont(math.max(1,math.min(6,number(node.font,3))))
  local w,h=ui.CalcTextSize(text)
  local x=box.x;if align=="right"then x=x+box.w-w elseif align=="center"then x=x+(box.w-w)/2 end
  ui.DrawText(x,box.y+math.max(0,box.h-h)/2,color[1],color[2],color[3],color[4] or 1,text)
  ui.PopFont()
end
local function texture(R,instance,value,box,u0,v0,u1,v1,tint)
  if not value or value==false then return false end
  tint=tint or {1,1,1,1}
  if type(value)=="string"then return R.Animation(instance,value,box,tint)end
  ui.DrawImage(value,box.x,box.y,box.x+box.w,box.y+box.h,u0 or 0,v0 or 0,u1 or 1,v1 or 1,
    tint[1],tint[2],tint[3],tint[4] or 1)
  return true
end
local function tooltip(screen,child,extra)
  local value=call("windows","ChildTooltip",screen,child) or ""
  if extra and extra~=""then value=value~="" and value.."\n"..extra or extra end
  if value~=""then ui.SetTooltip(value)end
end
local function buffIndex(screen,node)
  if screen~="TargetWindow" and screen~="BuffWindow" and screen~="ShortDurationBuffWindow"then return nil end
  if node.type~="Button"then return nil end
  local n=id(node):match("^Buff(%d+)$")
  n=tonumber(n)
  local maximum=screen=="TargetWindow"and 85 or screen=="BuffWindow"and 42 or 30
  return n and n>=0 and n<maximum and n or nil
end
local function buffLabel(screen,node)
  if node.type~="Label"or(screen~="BuffWindow"and screen~="ShortDurationBuffWindow")then return nil end
  local eq=tonumber(node.eqType)
  local first=screen=="BuffWindow"and 500 or 600
  local old=screen=="BuffWindow"and 45 or 80
  local oldCount=screen=="BuffWindow"and 15 or 6
  local limit=screen=="BuffWindow"and 42 or 30
  if eq and eq>=first and eq<first+limit then return eq-first,"name",eq<first+(screen=="BuffWindow"and 42 or 20)end
  if eq and eq>=old and eq<old+oldCount then return eq-old,"name",true end
  for _,name in ipairs{id(node),tostring(node.item or"")}do
    local lower=name:lower()
    local n=tonumber(lower:match("buff(%d+)")or lower:match("song(%d+)")or lower:match("number(%d+)"))
    if n and n<limit then
      if lower:find("number",1,true)or lower:find("place",1,true)then return n,"number"end
      if lower:find("label",1,true)or lower:find("_text",1,true)then return n,"name",false end
    end
  end
end
local function buffRectangles(screen,plan,instance,client,R)
  local s=state(instance,screen);s.buffRects={}
  if screen~="BuffWindow"and screen~="ShortDurationBuffWindow"then return end
  if not R.Geometry then return end
  local function visit(parent,box,depth)
    if depth>64 then return end
    local f=parent.fields or{}
    -- Shared source background strips use absolute row rectangles. A flow
    -- container owns its own placement and must not be approximated here.
    if parent.type=="TileLayoutBox"or parent.type=="HorizontalLayoutBox"or parent.type=="VerticalLayoutBox"
      or f.Layout and f.Layout~=""then return end
    for _,n in ipairs(parent.children or{})do
      if shown(screen,id(n))then
        local at=R.Geometry(n,box);local slot=buffIndex(screen,n)
        if slot then s.buffRects[#s.buffRects+1]={slot=slot,box=at}end
        if #(n.children or{})>0 then visit(n,at,depth+1)end
      end
    end
  end
  visit(plan,client,0)
end
local function buffDecoration(screen,node,box,instance,R)
  if node.type~="StaticAnimation"and node.type~="StaticTintedBlendAnimation"then return false end
  if screen~="BuffWindow"and screen~="ShortDurationBuffWindow"then return false end
  local matches,clips={},{}
  local maxW,maxH=0,0
  for _,entry in ipairs(state(instance,screen).buffRects or{})do
    local at=entry.box
    local x,y=math.max(box.x,at.x),math.max(box.y,at.y)
    local right,bottom=math.min(box.x+box.w,at.x+at.w),math.min(box.y+box.h,at.y+at.h)
    if right>x and bottom>y then
      matches[#matches+1]=entry;maxW=math.max(maxW,at.w);maxH=math.max(maxH,at.h)
      if call("buffs","Slot",screen,"Buff"..entry.slot)then clips[#clips+1]={x,y,right,bottom}end
    end
  end
  local name=(id(node).." "..tostring((node.art or{}).animation or"").." "..tostring(node.item or"")):lower()
  local named=name:find("buffbackground",1,true)or name:find("buff_background",1,true)or name:find("buff_back",1,true)
  if #matches==0 or not(named or #matches>=2 and(box.w<=2*maxW or box.h<=2*maxH))then return false end
  -- Crop a shared multi-row sprite at the active rows; never stretch the whole
  -- strip into one icon or leave its numbered empty frames visible.
  for _,clip in ipairs(clips)do
    ui.PushClipRect(clip[1],clip[2],clip[3],clip[4],true)
    local ok,why=pcall(R.PaintControl,screen,node,box,instance)
    ui.PopClipRect()
    if not ok then error(why,0)end
  end
  return true
end
local function gemIndex(node)
  local n=tonumber(id(node):match("^CSPW_Spell(%d+)$"))
  return n and n<12 and n or nil
end
local function rowFor(screen,node)
  local name=id(node)
  if screen=="GroupWindow"then
    for _,prefix in ipairs{"Gauge","HPLabel","HPPercLabel","ManaGauge","ManaLabel","ManaPercLabel",
      "STAGauge","STALabel","STAPercLabel","PetGauge","GroupRoleTank","GroupRoleAssist","GroupRolePuller","GW_AggroPctPlayer"}do
      local n=tonumber(name:match("^"..prefix.."(%d+)$"))
      if n and n>=1 and n<=5 then return n,"Gauge"..n end
    end
    local eq=tonumber(node.gaugeEqType or node.eqType)
    if node.type=="Gauge"and eq then
      for _,base in ipairs{10,16,30,35}do if eq>base and eq<=base+5 then return eq-base,"Gauge"..(eq-base)end end
    end
  elseif screen=="ExtendedTargetWnd"then
    local n=tonumber(name:match("^ETW_[%a]+(%d+)$"))
    if n and n>=0 and n<20 then return n,"ETW_Gauge"..n end
    local eq=tonumber(node.gaugeEqType or node.eqType)
    if node.type=="Gauge"and eq then
      for _,base in ipairs{42,62,82}do if eq>=base and eq<base+20 then return eq-base,"ETW_Gauge"..(eq-base)end end
    end
  end
end

function M.Handles(screen)return families[screen]==true end
function M.Shown(screen,node)if node.statusReplaced then return false end end
function M.CanDraw(screen,plan,instance)
  if not M.Handles(screen)then return false,"Not a source status presenter"end
  if type(plan)~="table"or plan.type~="Screen"or type(plan.children)~="table"then return false,"Missing source status graph"end
  for _,need in ipairs{{"windows","ChildShown"},{"windows","ChildState"},{"windows","ClickChild"},
    {"windows","ChildArt"},{"character","Gauge"},{"character","Label"}}do
    if not fn(need[1],need[2])then return false,"Status service unavailable: "..need[1].."."..need[2]end
  end
  if screen=="CastSpellWnd"then
    for _,name in ipairs{"GemInfo","GemOverlay","GemClick","BookState","BookMemorize","Sets","MemorizeSet"}do
      if not fn("spells",name)then return false,"Spell status service unavailable: "..name end
    end
  elseif screen=="TargetWindow"or screen=="BuffWindow"or screen=="ShortDurationBuffWindow"then
    if not fn("buffs","Slot")then return false,"Buff status service unavailable"end
    if not fn("spells","Show")then return false,"Spell display service unavailable"end
    if screen~="TargetWindow"and not fn("windows","SetText")then return false,"Blocked-buff entry service unavailable"end
    if screen~="TargetWindow"and not fn("windows","Button")then return false,"Buff removal service unavailable"end
  end
  local count=0
  if not walk(plan,function(node)
    count=count+1
    return count<=8192 and type(node)=="table"and type(node.type)=="string"and type(node.children or {})=="table"
  end)then return false,"Status graph exceeds supported bounds"end
  return true
end

-- Keep every authored node in place. Extra usable gems/buffs/target rows use a
-- source control's artwork in an appended area instead of silently disappearing.
local function prepare(screen,plan,instance,R)
  local s=state(instance,screen);local frame=ui.GetFrameCount()
  if s.prepared and s.frame==frame and s.original==plan then return s.prepared,s.width,s.height end
  s.original,s.frame=plan,frame
  local prepared={};for k,v in pairs(plan)do prepared[k]=v end
  prepared.children={};for _,v in ipairs(plan.children)do prepared.children[#prepared.children+1]=v end
  local insets=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or{}
  local insetW=number(insets.left)+number(insets.right)
  local insetH=number(insets.top)+number(insets.bottom)
  local width=math.max(1,number((plan.rect or {}).w,200)-insetW)
  local height=math.max(1,number((plan.rect or {}).h,100)-insetH)
  if screen=="CastSpellWnd"and R and R.MeasureChildren then
    local snap=false
    walk(plan,function(n)
      local f=n.fields or {}
      if n.type=="TileLayoutBox"and f.SnapToChildren==true then snap=true end
    end)
    if snap then
      local w,h=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=width,h=height,s=1})
      width,height=math.max(width,w),math.max(height,h)
    end
  end
  local baseHeight=height;local covered,first,sourceKeys,replaced={},{},{},{}
  local function sourceKey(n,key)
    sourceKeys[n]=sourceKeys[n]or{};sourceKeys[n][key]=true
  end
  local function choose(role,n)
    local old=first[role]
    if not old or number((old.rect or{}).w)<=0 or number((old.rect or{}).h)<=0 then first[role]=n end
  end
  walk(plan,function(n)
    local bi=buffIndex(screen,n)
    if bi then choose("buff",n);sourceKey(n,"buff:"..bi)end
    if screen=="CastSpellWnd"and n.type=="SpellGem"then
      local gi=gemIndex(n);if gi then choose("gem",n);sourceKey(n,"gem:"..gi)end
    end
    if screen=="ExtendedTargetWnd"and n.type=="Gauge"then
      local row=rowFor(screen,n);if row then choose("row",n);sourceKey(n,"row:"..row)end
    end
    if n.type=="Gauge"then choose("gauge",n);sourceKey(n,"gauge:"..tostring(n.gaugeEqType or n.eqType))end
    if id(n)=="CSPW_SpellBookV"or id(n)=="CSPW_SpellBookH"then sourceKey(n,"book")end
  end)
  local function cover(n)
    local bi=buffIndex(screen,n);if bi then covered["buff:"..bi]=true end
    local gi=screen=="CastSpellWnd"and n.type=="SpellGem"and gemIndex(n)
    if gi then covered["gem:"..gi]=true end
    local row=screen=="ExtendedTargetWnd"and n.type=="Gauge"and rowFor(screen,n)
    if row then covered["row:"..row]=true end
    if n.type=="Gauge"then covered["gauge:"..tostring(n.gaugeEqType or n.eqType)]=true end
    if id(n)=="CSPW_SpellBookV"or id(n)=="CSPW_SpellBookH"then covered.book=true end
  end
  if R and R.VisitChildren then
    R.VisitChildren(screen,plan,instance,{x=0,y=0,w=width,h=height,s=1},cover)
  else
    -- Isolated presenter fixtures may not provide the renderer traversal.
    -- A real source graph is always checked through resolved placements.
    walk(plan,function(n)if shown(screen,id(n))and number((n.rect or{}).w)>0 and number((n.rect or{}).h)>0 then cover(n)end end)
  end
  local extraX,extraY,extraHeight=0,baseHeight,0
  local function fallback(kind)
    local chosen=instance.style and instance.style.button
    chosen=type(chosen)=="table"and chosen.template or chosen
    return {type=kind,item="",name="",rect={x=0,y=0,w=kind=="Gauge"and math.max(80,width)or 24,h=24},
      art={animation="",background="",template="",drawTemplate=""},font=3,colors={},children={},text="",
      fields={ButtonDrawTemplate=chosen,SpellGemDrawTemplate={Holder="A_SpellGemHolder",Background="A_SpellGemBackground",Highlight="A_SpellGemHighlight"}}}
  end
  local function append(template,name,kind,eq,key)
    if not template then
      diagnostic(instance,screen,"missing-template:"..key,"Additional "..key.." uses this skin's shared control artwork")
      template=fallback(kind or "Button")
    end
    local n=clone(template);n.name,n.item,n.type=name,name,kind or template.type;n.children={}
    n.eqType,n.gaugeEqType=eq or "",eq or ""
    n.fields=n.fields or {};n.fields.ScreenID=name;n.fields.Visible=true
    local w=math.max(12,number((template.rect or {}).w,24));local h=math.max(12,number((template.rect or {}).h,24))
    if extraX>0 and extraX+w>width then extraX=0;extraY=extraY+extraHeight+3;extraHeight=0 end
    n.rect={x=extraX,y=extraY,w=w,h=h}
    n.anchors={topToTop=true,bottomToTop=true,leftToLeft=true,rightToLeft=true,top=0,bottom=0,left=0,right=0,
      explicit={top=false,bottom=false,left=false,right=false}}
    n.statusExtra=key
    prepared.children[#prepared.children+1]=n;extraX=extraX+w+3;extraHeight=math.max(extraHeight,h)
    width=math.max(width,n.rect.x+w);height=math.max(height,n.rect.y+h)
  end
  if screen=="TargetWindow"or screen=="BuffWindow"or screen=="ShortDurationBuffWindow"then
    local limit=screen=="TargetWindow"and 85 or screen=="BuffWindow"and 42 or 30
    for n=0,limit-1 do
      if not covered["buff:"..n]and call("buffs","Slot",screen,"Buff"..n)then
        replaced["buff:"..n]=true;append(first.buff,"Buff"..n,"Button",nil,"buff")
      end
    end
  elseif screen=="CastSpellWnd"then
    for n=0,11 do
      if not covered["gem:"..n]then
        local info=call("spells","GemInfo",screen,"CSPW_Spell"..n)
        if info and info.shown~=false then replaced["gem:"..n]=true;append(first.gem,"CSPW_Spell"..n,"SpellGem",nil,"gem")end
      end
    end
    if not covered.book then
      replaced.book=true
      append(first.gem,"CSPW_SpellBookV","Button",nil,"book")
      prepared.children[#prepared.children].text="Spell book"
    end
  elseif screen=="ExtendedTargetWnd"then
    for n=0,19 do
      if not covered["row:"..n]and shown(screen,"ETW_Gauge"..n)then
        replaced["row:"..n]=true;append(first.row,"ETW_Gauge"..n,"Gauge",42+n,"target row")
      end
    end
  end
  if screen=="TargetWindow"then
    local _,name,raw=call("character","Gauge",27)
    if not covered["gauge:27"]and raw and raw~=-1 and name and name~=""then
      replaced["gauge:27"]=true;append(first.gauge,"Hailstone_TargetOfTarget","Gauge",27,"target of target")
    end
    local _,_,aggro=call("character","Gauge",149)
    if not covered["gauge:149"]and aggro and aggro~=-1
      and call("character","Label",302)==call("character","Label",28)then
      replaced["gauge:149"]=true
      append(first.gauge,"Hailstone_TargetAggro","Gauge",149,"target aggro")
    end
  end
  -- Growing a source client for extra slots must not resurrect an earlier
  -- clipped/hidden definition of the same control and create duplicate input.
  -- Copy only affected paths; original compiled nodes remain immutable.
  local function suppress(n)
    local hidden=false;for key in pairs(sourceKeys[n]or{})do if replaced[key]then hidden=true;break end end
    local children,changed={},hidden
    for _,child in ipairs(n.children or{})do
      local value=suppress(child);children[#children+1]=value;changed=changed or value~=child
    end
    if not changed then return n end
    local out={};for k,v in pairs(n)do out[k]=v end
    out.children=children;out.statusReplaced=hidden or n.statusReplaced
    return out
  end
  for i,n in ipairs(prepared.children)do prepared.children[i]=suppress(n)end
  s.prepared,s.width,s.height=prepared,width+insetW,height+insetH
  return prepared,s.width,s.height
end
function M.Size(screen,plan,instance,R)
  local _,w,h=prepare(screen,plan,instance,R);return w,h
end
function M.ContentSize(screen,plan,instance,R)
  local prepared,w,h=prepare(screen,plan,instance,R)
  local inset=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or{}
  w,h=math.max(1,w-number(inset.left)-number(inset.right)),math.max(1,h-number(inset.top)-number(inset.bottom))
  if R and R.MeasureChildren then
    local mw,mh=R.MeasureChildren(screen,prepared,instance,{x=0,y=0,w=w,h=h,s=1})
    w,h=math.max(w,mw),math.max(h,mh)
  end
  return w,h
end

local function drawBuff(screen,node,box,instance,R)
  local child=id(node)
  local spell,ms,name,good,fade,counter,cr,cg,cb,limit=call("buffs","Slot",screen,child,true)
  if not spell then return true end -- the host explicitly clears both art layers for an empty slot
  local alpha=math.max(0,math.min(1,number(fade,1)))
  R.PaintControl(screen,node,box,instance,{skipDecal=true,caption="",tint={1,1,1,alpha}})
  R.Animation(instance,good and "BlueIconBackground"or "RedIconBackground",box,{1,1,1,alpha})
  local tex,u0,v0,u1,v1=call("windows","ChildArt",screen,child,"decal")
  local painted=texture(R,instance,tex,box,u0,v0,u1,v1,{1,1,1,alpha})
  if not painted then caption(node,box,name or tostring(spell),instance.palette and instance.palette.text,"center")end
  local _,hover=hit(screen,child,box,enabled(screen,child))
  if hover then
    local time=ms and ms>=0 and (math.floor(ms/60000)..":"..string.format("%02d",math.floor(ms/1000)%60))or ""
    ui.SetTooltip(tostring(name or spell)..(time~=""and "\n"..time or "").."\nRight-click for spell actions")
    if not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
      state(instance,screen).buffMenu={id=child,spell=spell,name=name or tostring(spell),remove=screen~="TargetWindow"}
      ui.OpenPopup("##source-buff-actions");consume(instance)
    end
  end
  if counter then caption(node,{x=box.x,y=box.y,w=box.w,h=12*(box.s or 1)},counter,{cr or 1,cg or 1,cb or 1,1},"right")end
  if limit then caption(node,{x=box.x,y=box.y+math.max(0,box.h-12*(box.s or 1)),w=box.w,h=12*(box.s or 1)},limit,{1,.8,.25,1})end
  if ms and ms>=0 and ms<60000 then
    caption(node,{x=box.x,y=box.y+math.max(0,box.h-12*(box.s or 1)),w=box.w,h=12*(box.s or 1)},math.floor(ms/1000),nil,"right")
  end
  return true
end
local function buffMenu(screen,instance)
  if not ui.BeginPopup("##source-buff-actions")then return end
  local b=state(instance,screen).buffMenu
  if b then
    ui.TextDisabled(b.name)
    if ui.MenuItem("Spell Info")then call("spells","Show",b.spell)end
    if b.remove then
      if ui.MenuItem("Add to Blocked Buffs")then
        call("windows","SetText","BlockedBuffWnd","BW_EditSpellToBlock",tostring(b.spell))
        call("windows","ClickChild","BlockedBuffWnd","BW_AddSpellToBlock","left")
      end
      if ui.MenuItem("Remove")and call("buffs","Slot",screen,b.id)==b.spell then
        call("windows","Button",screen,b.id,3)
      end
    end
  end
  ui.EndPopup()
end
local function drawRow(screen,node,box,instance,R,row,canonical)
  R.PaintControl(screen,node,box,instance)
  local click,hover=hit(screen,id(node),box,enabled(screen,canonical))
  local s=state(instance,screen);local rec=s.controls[canonical]or{};s.controls[canonical]=rec
  if ui.IsItemClicked(ui.Mouse.Left)then rec.dragged=false end
  if ui.IsItemActive()and ui.IsMouseDragging(ui.Mouse.Left)then rec.dragged=true end
  if instance.hud and instance.hud.DragItem and instance.hud.DragItem()then rec.dragged=true end
  if click and not rec.dragged then call("windows","ClickChild",screen,canonical,"left")end
  if hover then
    if not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
      call("windows","ClickChild",screen,screen=="GroupWindow"and canonical or "ETW_Role"..row,
        screen=="GroupWindow"and "right"or "rightup")
      consume(instance)
    end
    if screen=="GroupWindow"then
      local tips={}
      for _,prefix in ipairs{"GroupRoleTank","GroupRoleAssist","GroupRolePuller"}do
        local tip=shown(screen,prefix..row)and call("windows","ChildTooltip",screen,prefix..row)
        if tip and tip~=""then tips[#tips+1]=tip end
      end
      tooltip(screen,canonical,table.concat(tips,"\n"))
    else tooltip(screen,"ETW_Role"..row)end
  end
  return true
end
local function overSpellDisplay(spell)
  local title=call("spells","Details",spell)
  if not title or not ui.FindWindowRect then return false end
  local mx,my=ui.GetMousePos()
  for n=1,6 do
    local screen=n==1 and "SpellDisplayWindow"or "SpellDisplayWindow#"..n
    if call("windows","Shown",screen)and call("windows","Title",screen)==title then
      local x,y,w,h=ui.FindWindowRect("###modern."..screen)
      if x and mx>=x and mx<x+w and my>=y and my<y+h then return true end
    end
  end
  return false
end
local function spellInGem(index)
  local book=call("spells","BookState");return book and book.gems and book.gems[index+1]
end
local function drawGem(screen,node,box,instance,R,index)
  local child=id(node);local info=call("spells","GemInfo",screen,child)or{}
  if info.shown==false then return true end
  local f=node.fields or {};local t=f.SpellGemDrawTemplate or {}
  local scale=box.s or 1
  R.Animation(instance,t.Holder,box)
  R.Animation(instance,t.Background,box,{info.tintR or 1,info.tintG or 1,info.tintB or 1,1})
  local ox,oy=number(f.SpellIconOffsetX)*scale,number(f.SpellIconOffsetY)*scale
  local icon={x=box.x+ox,y=box.y+oy,w=math.max(1,box.w-2*ox),h=math.max(1,box.h-2*oy),s=scale}
  texture(R,instance,info.tex,icon,info.u0,info.v0,info.u1,info.v1,{1,1,1,info.tintA or 1})
  local top,r,g,b,a=call("spells","GemOverlay",screen,child,icon.y,icon.y+icon.h)
  if top and top<icon.y+icon.h then ui.DrawRectFilled(icon.x,math.max(icon.y,top),icon.x+icon.w,icon.y+icon.h,r or 0,g or 0,b or 0,a or .65)end
  local on=enabled(screen,child);local click,hover=hit(screen,child,box,on)
  if hover then R.Animation(instance,t.Highlight,box);if info.tooltip and info.tooltip~=""then ui.SetTooltip(info.tooltip)end end
  local rec=state(instance,screen).controls[child]or{};state(instance,screen).controls[child]=rec
  local frame=ui.GetFrameCount()
  if rec.frame and frame>rec.frame+1 then rec.right=nil;rec.dragged=false end
  rec.frame=frame
  if ui.IsItemClicked(ui.Mouse.Left)then rec.dragged=false end
  if on and ui.IsItemActive()and ui.IsMouseDragging(ui.Mouse.Left)and not call("cursor","HoldingButton")then
    if call("cursor","PickUp",screen,child)then rec.dragged=true end
  end
  if on and click and not rec.dragged then call("spells","GemClick",child,"left")end
  local drag=modern_spell_drag_frame==frame and modern_spell_drag or nil
  if on and drag and not drag.gem and ui.IsMouseHoveringRect(box.x,box.y,box.x+box.w,box.y+box.h)
    and ui.IsWindowHovered((ui.HoveredFlags.ChildWindows or 0)|(ui.HoveredFlags.AllowWhenBlockedByActiveItem or 0))
    and ui.IsMouseReleased(ui.Mouse.Left)then call("spells","BookMemorize",drag.slot,index)end
  if on and not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
    rec.right={time=ui.GetTime(),spell=spellInGem(index),held=false}
    call("spells","GemClick",child,"rightdown");consume(instance)
  end
  local press=rec.right
  if press then
    if not on or press.spell~=spellInGem(index)then rec.right=nil
    elseif ui.IsMouseDown(ui.Mouse.Right)and not press.held and ui.GetTime()-press.time>=.5 then
      press.held=true;call("spells","GemClick",child,"rightheld")
    elseif ui.IsMouseReleased(ui.Mouse.Right)then
      local keep=press.held and press.spell and press.spell~=-1 and overSpellDisplay(press.spell)
      if press.held or hover then call("spells","GemClick",child,press.held and "rightupheld"or "rightup",not hover)end
      if keep then call("spells","Show",press.spell)end
      rec.right=nil
    elseif not ui.IsMouseDown(ui.Mouse.Right)then rec.right=nil end
  end
  return true
end
local function drawBook(screen,node,box,instance,R)
  R.PaintControl(screen,node,box,instance)
  local click,hover=hit(screen,id(node),box,enabled(screen,id(node)))
  if click then call("windows","ClickChild",screen,id(node),"left")end
  if hover then
    ui.SetTooltip("Spell book\nRight-click for spell sets")
    if not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then ui.OpenPopup("##source-spell-sets");consume(instance)end
  end
  return true
end
local function spellSets(screen)
  if not ui.BeginPopup("##source-spell-sets")then return end
  ui.TextDisabled("Spell sets")
  local any=false
  for n,set in ipairs(call("spells","Sets")or{})do
    if set.inUse then any=true;if ui.MenuItem("Memorize "..set.name.."##"..n)then call("spells","MemorizeSet",n)end end
  end
  if not any then ui.TextDisabled("(none saved)")end
  if ui.MenuItem("Save or manage sets...")then modern_book_tab="sets";call("windows","ClickChild",screen,"CSPW_SpellBookV","left")end
  ui.EndPopup()
end
function M.DrawControl(screen,node,box,instance,R)
  if not M.Handles(screen)then return false end
  if node.statusReplaced then return true end
  if screen=="GroupWindow"and node.type=="InvSlot"then
    local value=node.slot
    local slot=type(value)=="number"and value or type(value)=="string"and tonumber(value:match("^%d+$"))
    if slot and slot>=0 and slot<=32 and slot%1==0 then
      local s=state(instance,screen)
      if s.items==nil then
        local ok,result=pcall(dofile,"lib/items.lua");s.items=ok and result or false
      end
      if s.items and s.items.InvSlot then
        local previous=instance.sourceSlotNode;instance.sourceSlotNode=node
        local ok,why=pcall(s.items.InvSlot,slot,nil,box.x,box.y,math.min(box.w,box.h),box.s or 1,nil)
        instance.sourceSlotNode=previous
        if not ok then error(why,0)end
        return true
      end
      diagnostic(instance,screen,"inventory-helper","The inventory interaction helper is unavailable")
      return false
    end
  end
  local label,role,native=buffLabel(screen,node)
  if label then
    local spell,_,name=call("buffs","Slot",screen,"Buff"..label)
    if spell then
      R.PaintControl(screen,node,box,instance,role=="name"and not native and{caption=name or""}or nil)
    end
    return true
  end
  if buffDecoration(screen,node,box,instance,R)then return true end
  if buffIndex(screen,node)then return drawBuff(screen,node,box,instance,R)end
  local row,canonical=rowFor(screen,node)
  if row then return drawRow(screen,node,box,instance,R,row,canonical)end
  if screen=="CastSpellWnd"then
    local index=node.type=="SpellGem"and gemIndex(node)
    if index then return drawGem(screen,node,box,instance,R,index)end
    if id(node)=="CSPW_SpellBookV"or id(node)=="CSPW_SpellBookH"then return drawBook(screen,node,box,instance,R)end
  elseif screen=="TargetWindow"and node.type=="Gauge"and tonumber(node.gaugeEqType or node.eqType)==6 then
    R.PaintControl(screen,node,box,instance)
    local clicked=hit(screen,id(node),box,enabled(screen,"TargetHP"))
    if clicked then call("windows","ClickChild",screen,"TargetHP","left")end
    return true
  end
  return false
end
function M.Draw(screen,plan,instance,client,R)
  local ok,why=M.CanDraw(screen,plan,instance);if not ok then return false,why end
  local s=state(instance,screen);local frame=ui.GetFrameCount()
  if s.drawFrame and frame>s.drawFrame+1 then s.buffMenu=nil;s.controls={}end
  s.drawFrame=frame
  local prepared=prepare(screen,plan,instance,R)
  buffRectangles(screen,prepared,instance,client,R)
  local drawn,reason=R.Draw(screen,prepared,instance,client,M)
  if not drawn then return false,reason end
  if screen=="BuffWindow"or screen=="ShortDurationBuffWindow"or screen=="TargetWindow"then buffMenu(screen,instance)
  elseif screen=="CastSpellWnd"then spellSets(screen)end
  return true
end
rawset(_G,"hailstone_skin_status_presenters",M)
return M
