-- Source-shaped HUD controls with the same domain actions as the built-in presenters.
-- Compiled plans are data; live values and every action remain owned by hs.UI.
local context=rawget(_G,"hailstone_skin_context")
local previous=rawget(_G,"hailstone_skin_status_presenters")
if context and previous and previous.context==context then return previous end
local API = hs.UI
local hitRect=rawget(ui,"HitRect")
local windowHovered=rawget(ui,"IsWindowHovered")
local M = {context=context,BorrowsDrawRects=true}
local families={TargetWindow=true,GroupWindow=true,BuffWindow=true,ShortDurationBuffWindow=true,
  CastSpellWnd=true,ExtendedTargetWnd=true}
local buffSlots={TargetWindow=85,BuffWindow=42,ShortDurationBuffWindow=30}
local buffIds,buffKeys={},{}
for slot=0,buffSlots.TargetWindow-1 do
  buffIds[slot],buffKeys[slot]="Buff"..slot,"buff:"..slot
end
local WHITE={1,1,1,1}
local EMPTY={}
local groupGaugeSlots,groupNames,groupRoles={},{},{}
for row=1,5 do
  groupGaugeSlots[10+row]={row,1,5}
  groupGaugeSlots[30+row]={row,2,5}
  groupGaugeSlots[35+row]={row,3,5}
  groupGaugeSlots[16+row]={row,4,6}
  groupNames[row]="Gauge"..row
  groupRoles[row]={"GroupRoleTank"..row,"GroupRoleAssist"..row,"GroupRolePuller"..row}
end
local groupFontSamples={{font=1},{font=2},{font=3}}
local extendedRows={}
for row=0,19 do
  extendedRows[row+1]={name="ETW_Gauge"..row,key="row:"..row,eq=42+row,bit=1<<row}
end
local gemIds,gemKeys={},{}
for gem=0,11 do gemIds[gem],gemKeys[gem]="CSPW_Spell"..gem,"gem:"..gem end
local gemOrientationChildren={CSPW_HorizontalOrientationBook=true,CSPW_HorizontalOrientationTemplate=true,
  CSPW_VerticalOrientationTemplate=true}
local retainedCallObserver
local function fn(module,name)
  local t=API[module]
  if API.Supports and not API.Supports(module,name) then return nil end
  return t and type(t[name])=="function" and t[name] or nil
end
local function call(module,name,...)
  local methods=API[module]
  local f=methods and rawget(methods,name)
  if type(f)~="function"then f=fn(module,name)end
  if type(f)=="function"then
    -- Gauge and visibility snapshots record from their scope caches below.
    if retainedCallObserver and name~="Gauge" and name~="ChildShown" then return retainedCallObserver(module,name,f,...) end
    return f(...)
  end
end
local function id(node) return tostring(node.name or node.item or "") end
local extendedSlots=setmetatable({},{__mode="k"})
local castNativeVisibility=setmetatable({},{__mode="k"})
local extendedNativeVisibility=setmetatable({},{__mode="k"})
local function nativeVisibility(screen,node)
  local cache=screen=="CastSpellWnd" and castNativeVisibility or extendedNativeVisibility
  local value=cache[node]
  if value~=nil then return value end
  local name=id(node)
  if screen=="CastSpellWnd"then
    local gem=tonumber(name:match("^CSPW_Spell(-?%d+)$"))
    value=gemOrientationChildren[name]==true or gem~=nil and gem>=0 and gem<12
  else
    value=name:match("^ETW_.*%d$")~=nil
  end
  cache[node]=value
  return value
end
local function nativeExtendedSlot(node)
  local slot=extendedSlots[node]
  if slot==nil then
    -- The host uses the ETW_ prefix and trailing decimal slot index.
    local name=id(node)
    local index=name:sub(1,4)=="ETW_" and tonumber(name:match("(%d+)$"))
    slot=index and extendedRows[index+1]or false
    extendedSlots[node]=slot
  end
  return slot
end
local function number(n,default) return type(n)=="number" and n==n and n~=math.huge and n~=-math.huge and n or default or 0 end
local function clone(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value)do out[k]=clone(v)end
  local meta=getmetatable(value);if type(meta)=="table"then setmetatable(out,meta)end;return out
end
local function walk(node,visit,depth,parent)
  depth=depth or 0;if depth>64 then return false end
  if visit(node,parent)==false then return false end
  for _,child in ipairs(node.children or EMPTY)do if not walk(child,visit,depth+1,node)then return false end end
  return true
end
local snapShapes=setmetatable({},{__mode="k"})
local function snapSize(screen,plan,instance,R,width,height)
  if not R or not R.MeasureChildren then return width,height end
  if screen~="CastSpellWnd"and screen~="GroupWindow"and screen~="ExtendedTargetWnd"then return width,height end
  if screen=="GroupWindow"or screen=="ExtendedTargetWnd"then
    -- This source uses a named stretch strategy around wrapping tiles. Other
    -- skins contain parked pieces which must not determine the outer size.
    local profile=instance and instance.profile
    if not profile or tostring(profile.id):lower()~="sars-stock"then return width,height end
  end
  local snap=snapShapes[plan]
  if snap==nil then
    snap=false
    walk(plan,function(n)
      if n.type=="TileLayoutBox" and (n.fields or EMPTY).SnapToChildren==true then snap=true;return false end
    end)
    if plan._packColorsNormalized then snapShapes[plan]=snap end
  end
  if snap then
    local w,h=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=width,h=height,s=1})
    width,height=math.max(width,w),math.max(height,h)
  end
  return width,height
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
local drawReads
local readPool={}
local unconstrained={}
local function wipe(map)
  for key in pairs(map)do map[key]=nil end
end
local function clearReads(reads)
  wipe(reads.shown);wipe(reads.enabled);wipe(reads.buffs);wipe(reads.gauges)
  wipe(reads.buffVisible);wipe(reads.childGauges);wipe(reads.groupMembers)
  reads.resultCount,reads.occupiedLow,reads.occupiedHigh=0,nil,nil
  reads.groupDragMoved=nil
  reads.extendedShown,reads.extendedDragMoved=nil,nil
  reads.castShown=nil
end
local function resetReads()
  local reads=drawReads
  while reads do
    if reads.extendedState then reads.extendedState.extendedShownValid=false end
    if reads.castState then reads.castState.castShownValid=false end
    clearReads(reads)
    reads=reads.previous
  end
end
local function readResult(reads)
  local n=reads.resultCount+1
  reads.resultCount=n
  local result=reads.results[n]
  if result then return result end
  result={}
  -- Bound retained tuples by the largest status window. Map keys are cleared
  -- each draw, so authored aliases and temporary plans cannot accumulate.
  if n<=buffSlots.TargetWindow then reads.results[n]=result end
  return result
end
local function childShown(screen,child)
  local reads=drawReads
  if not reads or reads.screen~=screen then return call("windows","ChildShown",screen,child)end
  local value=reads.shown[child]
  if value==nil and reads.extendedShown then value=reads.extendedShown[child]end
  if value==nil and reads.castShown then value=reads.castShown[child]end
  if value==nil then
    value=call("windows","ChildShown",screen,child)
    reads.shown[child]=value==nil and unconstrained or value
  elseif value==unconstrained then value=nil end
  if reads.retainWatch then reads.retainWatch.shown[child]=value==nil and unconstrained or value end
  return value
end
local function shown(screen,child)
  return childShown(screen,child)~=false
end
local function nodeShown(screen,node)
  local visible=childShown(screen,id(node))
  if visible==nil then return not node.fields or node.fields.Visible~=false end
  return visible~=false
end
local function enabled(screen,child)
  local reads=drawReads
  if not reads or reads.screen~=screen then return call("windows","ChildState",screen,child)~=false end
  local value=reads.enabled[child]
  if value==nil then
    value=call("windows","ChildState",screen,child)~=false
    reads.enabled[child]=value
  end
  return value
end
local function occupiedBuffs(screen)
  local f=API.buffs and API.buffs.Occupied
  if type(f)~="function"then return nil end
  local low,high=f(screen)
  if math.type(low)=="integer" and math.type(high)=="integer" then return low,high end
end
local function occupiedSlot(low,high,slot)
  if slot<64 then return low & (1<<slot)~=0 end
  return high & (1<<(slot-64))~=0
end
local function readOccupied(reads,screen)
  if reads.occupiedLow==nil then
    local low,high=occupiedBuffs(screen)
    reads.occupiedLow,reads.occupiedHigh=low or false,high
  end
  return reads.occupiedLow,reads.occupiedHigh
end
local function buffInfo(screen,child,overlays,slot)
  local reads=drawReads
  if not reads or reads.screen~=screen then return call("buffs","Slot",screen,child,overlays)end
  local info=reads.buffs[child]
  if info==nil then
    local low,high=readOccupied(reads,screen)
    if slot and low~=false and not occupiedSlot(low,high,slot)then
      reads.buffs[child]=false
      return nil
    end
    local spell,ms,name,good,fade,counter,cr,cg,cb,limit,lr,lg,lb=call("buffs","Slot",screen,child,true)
    if spell then
      info=readResult(reads)
      info[1],info[2],info[3],info[4],info[5],info[6],info[7]=spell,ms,name,good,fade,counter,cr
      info[8],info[9],info[10],info[11],info[12],info[13]=cg,cb,limit,lr,lg,lb
    else info=false end
    reads.buffs[child]=info
  end
  if info then return table.unpack(info,1,overlays and 13 or 5)end
end
local function gaugeInfo(screen,kind)
  local reads=drawReads
  if not reads or reads.screen~=screen then return call("character","Gauge",kind)end
  local info=reads.gauges[kind]
  if info then
    if reads.retainWatch then reads.retainWatch.gauges[kind]=info end
    return table.unpack(info,1,6)
  end
  local slot=screen=="GroupWindow" and groupGaugeSlots[kind]
  local groupGauges=slot and API.character and API.character.GroupGauges
  if type(groupGauges)=="function"then
    local row=slot[1]
    local member=reads.groupMembers[row]
    if member==nil then
      local hp,mana,endurance,pet,name,petName=groupGauges(row)
      if type(hp)=="number" and type(mana)=="number" and type(endurance)=="number" and type(pet)=="number"then
        member=readResult(reads)
        member[1],member[2],member[3],member[4],member[5],member[6]=hp,mana,endurance,pet,name,petName
      else member=false end
      reads.groupMembers[row]=member
    end
    if member then
      local raw,text=member[slot[2]],member[slot[3]]
      if raw==-2 then return 1,text,raw,128/255,0,0 end
      return raw>=0 and raw/1000 or nil,text,raw
    end
  end
  info=readResult(reads)
  info[1],info[2],info[3],info[4],info[5],info[6]=call("character","Gauge",kind)
  reads.gauges[kind]=info
  if reads.retainWatch then reads.retainWatch.gauges[kind]=info end
  return table.unpack(info,1,6)
end
local function hit(screen,child,box,on,withActive,hitId)
  local id=hitId or "##source-status:"..screen..":"..child
  local w,h=math.max(1,box.w),math.max(1,box.h)
  if hitRect then return hitRect(id,box.x,box.y,w,h,on)end
  ui.SetCursorScreenPos(box.x,box.y)
  if on==false then ui.BeginDisabled(true)end
  local clicked=ui.InvisibleButton(id,w,h)
  local hover=ui.IsItemHovered()
  if on==false then ui.EndDisabled()end
  return clicked,hover,withActive and ui.IsItemActive()
end
local function caption(node,box,text,color,align)
  if text==nil or text==""then return end
  text=tostring(text);color=color or WHITE
  ui.PushFont(math.max(1,math.min(6,number(node.font,3))))
  local w,h=ui.CalcTextSize(text)
  local x=box.x;if align=="right"then x=x+box.w-w elseif align=="center"then x=x+(box.w-w)/2 end
  ui.DrawText(x,box.y+math.max(0,box.h-h)/2,color[1],color[2],color[3],color[4] or 1,text)
  ui.PopFont()
end
local function texture(R,instance,value,box,u0,v0,u1,v1,tint)
  if not value or value==false then return false end
  tint=tint or WHITE
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
  local maximum=buffSlots[screen]
  if not maximum then return nil end
  if node.type~="Button"then return nil end
  local n=id(node):match("^Buff(%d+)$")
  n=tonumber(n)
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
local function buffGeometry(screen,plan,client,R)
  local layout={plan=plan,geometry=R.Geometry,w=client.w,h=client.h,s=client.s,slots={},decorations={}}
  local function visit(parent,box,path,depth)
    if depth>64 then return end
    local f=parent.fields or EMPTY
    -- Shared strips are interpreted only against slots in authored absolute
    -- layouts. Placement in a flow group belongs to the renderer.
    if parent.type=="TileLayoutBox" or parent.type=="HorizontalLayoutBox" or parent.type=="VerticalLayoutBox"
      or f.Layout and f.Layout~=""then return end
    for _,node in ipairs(parent.children or EMPTY)do
      local slot=buffIndex(screen,node)
      local children=node.children and #node.children>0
      if slot or children then
        local at=R.Geometry(node,box)
        local nextPath={name=id(node),parent=path}
        if slot then layout.slots[#layout.slots+1]={child=buffIds[slot],slot=slot,box=at,path=nextPath}end
        if children then visit(node,at,nextPath,depth+1)end
      end
    end
  end
  visit(plan,{x=0,y=0,w=client.w,h=client.h,s=client.s},nil,0)
  return layout
end

local function setBuffGeometry(screen,plan,instance,client,R)
  if (screen~="BuffWindow" and screen~="ShortDurationBuffWindow") or not R.Geometry then return end
  local s=state(instance,screen)
  local layout=plan._packColorsNormalized and s.buffGeometry
  if not layout or layout.plan~=plan or layout.geometry~=R.Geometry
    or layout.w~=client.w or layout.h~=client.h or layout.s~=client.s then
    layout=buffGeometry(screen,plan,client,R)
    if plan._packColorsNormalized then s.buffGeometry=layout end
  end
  drawReads.buffLayout,drawReads.buffX,drawReads.buffY=layout,client.x,client.y
end

local function decorativeClips(layout,node,x,y,w,h)
  local cached=layout.decorations[node]
  if cached and cached.x==x and cached.y==y and cached.w==w and cached.h==h then return cached.clips end
  local clips={}
  for _,entry in ipairs(layout.slots)do
    local at=entry.box
    local left,top=math.max(x,at.x),math.max(y,at.y)
    local right,bottom=math.min(x+w,at.x+at.w),math.min(y+h,at.y+at.h)
    if right>left and bottom>top then
      clips[#clips+1]={left,top,right,bottom,entry.child,entry.path,slot=entry.slot,thin=w<=2*at.w or h<=2*at.h}
    end
  end
  layout.decorations[node]={x=x,y=y,w=w,h=h,clips=clips}
  return clips
end

local function buffPathShown(reads,path)
  local visible=reads.buffVisible[path]
  if visible~=nil then return visible end
  visible=(not path.parent or buffPathShown(reads,path.parent)) and shown(reads.screen,path.name)
  reads.buffVisible[path]=visible
  return visible
end

local function buffDecoration(screen,node,box,instance,R,named)
  local reads=drawReads
  if not reads or reads.screen~=screen or not reads.buffLayout then return false end
  local ox,oy=reads.buffX,reads.buffY
  local clips=decorativeClips(reads.buffLayout,node,box.x-ox,box.y-oy,box.w,box.h)
  if #clips<(named and 1 or 2)then return false end
  local shownCount,thin=0,false
  for _,clip in ipairs(clips)do
    if buffPathShown(reads,clip[6])then
      shownCount=shownCount+1
      thin=thin or clip.thin
    end
  end
  if shownCount==0 or not(named or shownCount>=2 and thin)then return false end
  -- Crop a shared multi-row sprite at the active rows; never stretch the whole
  -- strip into one icon or leave its numbered empty frames visible.
  for _,clip in ipairs(clips)do
    if buffPathShown(reads,clip[6]) and buffInfo(screen,clip[5],false,clip.slot)then
      ui.PushClipRect(clip[1]+ox,clip[2]+oy,clip[3]+ox,clip[4]+oy,true)
      local ok,why=pcall(R.PaintControl,screen,node,box,instance)
      ui.PopClipRect()
      if not ok then error(why,0)end
    end
  end
  return true
end
local function gemIndex(node)
  local n=tonumber(id(node):match("^CSPW_Spell(%d+)$"))
  return n and n<12 and n or nil
end
local function rowFor(screen,node)
  if screen=="GroupWindow"and node.statusGroupRow then return node.statusGroupRow,groupNames[node.statusGroupRow],node.statusGroupRole end
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
    if node.type=="Screen"or node.type=="LayoutBox"or node.type=="TileLayoutBox"
      or node.type=="HorizontalLayoutBox"or node.type=="VerticalLayoutBox"or node.type=="TemplateContainer"then return nil end
    local n=tonumber(name:match("^ETW_[%a]+(%d+)$"))
    if n and n>=0 and n<20 then return n,"ETW_Gauge"..n end
    local eq=tonumber(node.gaugeEqType or node.eqType)
    if node.type=="Gauge"and eq then
      for _,base in ipairs{42,62,82}do if eq>=base and eq<base+20 then return eq-base,"ETW_Gauge"..(eq-base)end end
    end
  end
end

local function targetHealthRow(node)
  if node.type~="Gauge"then return nil end
  local eq=tonumber(node.gaugeEqType or node.eqType)
  if id(node):match("^ETW_Gauge%d+$")or eq and eq>=42 and eq<62 then
    return rowFor("ExtendedTargetWnd",node)
  end
end
local function compoundKind(node)
  if node._packColorsNormalized and node.type=="Gauge"and #(node.children or EMPTY)==0 then
    local row=tonumber(id(node):match("^ETW_Gauge(%d+)_[1-4][AB]$"))
    local kind=tonumber(node.gaugeEqType or node.eqType)
    if row and row<20 and kind==42+row then return kind end
  end
end
local function indexCompoundGauges(source)
  local layout=(source.fields or EMPTY).Layout
  if layout and layout~=""then return nil end
  local pieces,kinds
  for _,node in ipairs(source.children)do
    local leaf=node
    if node.type=="Screen"and #(node.children or EMPTY)==1 then
      local art,fields=node.art or EMPTY,node.fields or EMPTY
      local own=art.drawTemplate
      if not own or own==""then own=fields.DrawTemplate end
      if (not own or own=="")and (not fields.Layout or fields.Layout=="")then
        leaf=node.children[1]
      end
    end
    local kind=compoundKind(leaf)
    if kind then
      pieces,kinds=pieces or {},kinds or {}
      local bit=1<<(kind-42)
      kinds[kind],pieces[node]=bit,bit
    end
  end
  if pieces then return {pieces=pieces,kinds=kinds}end
end
local function groupRole(node)
  local name=id(node):gsub("^GW_","")
  local lower=name:lower();local eq=tonumber(node.gaugeEqType or node.eqType)
  local n=tonumber(lower:match("petgauge(%d+)$"))
  if n and n>=1 and n<=5 then return n,"pet","PetGauge"..n,16+n end
  if node.type=="Gauge"then
    if eq and eq>=31 and eq<=35 then n=eq-30;return n,"mana","ManaGauge"..n,eq end
    if eq and eq>=36 and eq<=40 then n=eq-35;return n,"endurance","STAGauge"..n,eq end
    if eq and eq>=17 and eq<=21 then n=eq-16;return n,"pet","PetGauge"..n,eq end
    if eq and eq>=11 and eq<=15 then n=eq-10;return n,"hp","Gauge"..n,eq end
  end
  for _,entry in ipairs{{"hplabel","percent","HPLabel"},{"hpperclabel","unit","HPPercLabel"},
    {"manalabel","label","ManaLabel"},{"manaperclabel","label","ManaPercLabel"},
    {"stalabel","label","STALabel"},{"staperclabel","label","STAPercLabel"},
    {"grouproletank","role","GroupRoleTank"},{"grouproleassist","role","GroupRoleAssist"},
    {"grouprolepuller","role","GroupRolePuller"},{"aggropctplayer","label","GW_AggroPctPlayer"}}do
    n=tonumber(lower:match("^"..entry[1].."(%d+)$"))
    if n and n>=1 and n<=5 then return n,entry[2],entry[3]..n end
  end
  if node.type=="Label"and name=="TargetPercentage"and eq and eq>=35 and eq<=39 then
    n=eq-34;return n,"percent","HPLabel"..n
  end
end
local function absolute(node,at)
  node.rect={x=at.x,y=at.y,w=math.max(0,at.w),h=math.max(0,at.h)}
  node.anchors={explicit={left=false,right=false,top=false,bottom=false}}
  node.fields=clone(node.fields or{})
  for _,key in ipairs{"LeftAnchorOffset","RightAnchorOffset","TopAnchorOffset","BottomAnchorOffset","Layout"}do node.fields[key]=nil end
end
-- Normalize shared group semantics without changing the skin's resources.
-- Only boxed layouts that cannot fit their own resource strips need reflow.
function M.GroupLayout(plan,instance,R,clientWidth,clientHeight,scale)
  local s=state(instance,"GroupWindow");scale=math.max(.01,number(scale,1))
  local profile=instance.profile or{}
  local source=tostring(profile.source or profile.id or""):lower()
  local boxedProfile=source=="drakah-pers-adeptus-stock"or source=="nemesis-stock"
  local insets=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or{}
  local designW,designH=math.max(1,number((plan.rect or{}).w,200)),math.max(1,number((plan.rect or{}).h,100))
  local width=math.max(1,number(clientWidth,designW-number(insets.left)-number(insets.right)))
  local height=math.max(1,number(clientHeight,designH-number(insets.top)-number(insets.bottom)))
  width,height=snapSize("GroupWindow",plan,instance,R,width,height)
  local face,w1,h1,w2,h2,w3,h3
  if boxedProfile and R and R.MeasureText then
    face=tostring(call("settings","Option","font_face") or "")
    w1,h1=R.MeasureText(instance,groupFontSamples[1],"Wg")
    w2,h2=R.MeasureText(instance,groupFontSamples[2],"Wg")
    w3,h3=R.MeasureText(instance,groupFontSamples[3],"Wg")
    w1,h1,w2,h2,w3,h3=w1/scale,h1/scale,w2/scale,h2/scale,w3/scale,h3/scale
  end
  s.groupCache=s.groupOriginal==plan and s.groupCache or{};s.groupOriginal=plan
  for index,record in ipairs(s.groupCache)do
    if record.clientWidth==width and record.clientHeight==height and record.source==source and record.fontFace==face
      and record.w1==w1 and record.h1==h1 and record.w2==w2 and record.h2==h2 and record.w3==w3 and record.h3==h3
      and record.renderer==R then
      if index>1 then table.remove(s.groupCache,index);table.insert(s.groupCache,1,record)end
      s.groupOwnsScroll=record.plan.statusGroupReflow
      return record.plan,record.width,record.height
    end
  end
  local prepared=clone(plan);local rows,nodes={},{};local nested=false
  local repairFixed=source=="takus-stock"
  local function geometry(node,parent)
    if R and R.Geometry then
      local at=R.Geometry(node,parent);local r=node.rect or{};local f=node.fields or{};local repaired=false
      if f.AutoStretch~=true then
        if number(r.w)>0 and at.w<=0 then at.x,at.w=parent.x+number(r.x),r.w;repaired=true end
        if number(r.h)>0 and at.h<=0 then at.y,at.h=parent.y+number(r.y),r.h;repaired=true end
      end
      return at,repaired
    end
    local r=node.rect or{};return{x=parent.x+number(r.x),y=parent.y+number(r.y),w=number(r.w),h=number(r.h),s=1}
  end
  local function index(node,parent,depth)
    depth=depth or 0;if depth>1 then nested=true end
    local at,repaired
    if node==prepared then at=parent else at,repaired=geometry(node,parent)end
    if repaired and repairFixed then
      -- Fixed source cells also declare zero opposing anchors. Persist the
      -- resolved fallback in the drawing graph, not only its measurement.
      local sourceRect=node.rect or{}
      absolute(node,{x=number(sourceRect.x),y=number(sourceRect.y),
        w=number(sourceRect.w,at.w),h=number(sourceRect.h,at.h)})
      at=geometry(node,parent)
    end
    if node~=prepared then nodes[#nodes+1]={node=node,at=at,depth=depth}end
    local row,role,native,eq=groupRole(node)
    if row then
      node.statusGroupRow,node.statusGroupRole,node.statusNativeName=row,role,native
      if eq then node.gaugeEqType,node.eqType=eq,eq end
      rows[row]=rows[row]or{nodes={}};local record={node=node,at=at,role=role}
      rows[row].nodes[#rows[row].nodes+1]=record
      if role=="percent"then rows[row].percent=record end
      if role=="hp"then
        local f=node.fields or{};local score=(id(node)=="Gauge"..row and 4 or 0)+(at.x>=0 and 2 or 0)
          +(number(f.TextOffsetY)>-20 and 2 or 0)+(number(f.TextOffsetX)>=0 and 2 or 0)
        if not rows[row].score or score>rows[row].score then rows[row].primary=record;rows[row].score=score end
      elseif role=="mana"or role=="endurance"or role=="pet"then rows[row][role]=record end
    end
    for _,child in ipairs(node.children or{})do index(child,at,depth+1)end
  end
  index(prepared,{x=0,y=0,w=designW,h=designH,s=1})
  local boxes,adapt={},{}
  for row,record in pairs(rows)do
    local primary,percent=record.primary,record.percent
    if primary then
      local own=(primary.node.fields or{}).GaugeDrawTemplate
      record.nameOnly=own==nil or own==""or type(own)=="table"and next(own)==nil
      local negative
      for _,entry in ipairs(record.nodes)do
        if entry.role=="hp"and number((entry.node.rect or{}).x)<0 then negative=entry end
      end
      if boxedProfile and percent and(record.nameOnly or negative)then
        local p=percent.at;local cell
        if record.nameOnly then
          cell={x=primary.at.x,y=primary.at.y,w=math.min(primary.at.h,primary.at.w),h=primary.at.h}
        else
          cell={x=math.max(0,p.x),y=negative.at.y,w=math.min(p.x+p.w,primary.at.x-2)-math.max(0,p.x),h=negative.at.h}
        end
        if cell.w>0 and cell.h>0 then boxes[row]=cell;adapt[row]=true end
      end
      for _,entry in ipairs(record.nodes)do
        local n=entry.node
        if n.type=="Gauge"and entry~=primary then n.sourceGaugeCaption="";n.statusGroupQuiet=true end
      end
      primary.node.statusGroupName=true;primary.node.statusGroupNameOnly=record.nameOnly
    end
  end
  -- Some compact group skins include the player's own leading health cell.
  -- It is not a sixth group member and retains the source's self controls.
  local selfPercent,selfLayer
  for _,entry in ipairs(nodes)do
    local eq=tonumber(entry.node.gaugeEqType or entry.node.eqType)
    if entry.node.type=="Label"and id(entry.node)=="TargetPercentage"and eq==19 then selfPercent=entry end
    if boxedProfile and entry.node.type=="Gauge"and eq==1 and number((entry.node.rect or{}).x)<0 then selfLayer=entry;entry.node.statusReplaced=true end
    if entry.node.type=="Gauge"and(eq==2 or eq==3 or eq==16)then entry.node.sourceGaugeCaption=""end
  end
  if selfPercent and selfLayer then
    boxes[0]={x=math.max(0,selfPercent.at.x),y=selfLayer.at.y,w=math.min(34,selfPercent.at.w),h=selfLayer.at.h}
    selfPercent.node.statusHealthPercentGauge=1
  end
  local reflow=next(adapt)~=nil and not nested
  local naturalH=height
  if reflow then
    local ordered={};for row=1,5 do if rows[row]and rows[row].primary then ordered[#ordered+1]=row end end
    local extra,bottom=0,0
    local function track(entry)
      if R and R.GaugeTrackRect then return R.GaugeTrackRect(entry.node,entry.at,instance)end
      local f=entry.node.fields or{};return{x=entry.at.x,y=entry.at.y+number(f.GaugeOffsetY),w=entry.at.w,h=math.max(1,entry.at.h-number(f.GaugeOffsetY))}
    end
    for index,row in ipairs(ordered)do
      local record=rows[row];local originalTop=record.primary.at.y
      for _,entry in ipairs(record.nodes)do if entry~=record.primary then entry.node.statusGroupPaintOnly=true end end
      if record.percent then record.percent.node.statusHealthPercentGauge=10+row end
      local top=math.max(originalTop+extra,bottom>0 and bottom+2 or originalTop)
      local delta=top-originalTop
      for _,entry in ipairs(record.nodes)do entry.at.y=entry.at.y+delta end
      local primary=record.primary;local f=primary.node.fields or{}
      local _,textH=12,12
      if R and R.MeasureText then _,textH=R.MeasureText(instance,primary.node,"Ag");textH=textH/scale end
      local nameBottom=primary.at.y+math.max(0,number(f.TextOffsetY))+textH
      local hp
      for _,entry in ipairs(record.nodes)do if entry.role=="hp"and entry.at.x>=0 and(not record.nameOnly or entry~=primary)then hp=entry;break end end
      local endY=nameBottom
      if hp then local band=track(hp)
        if band.y<nameBottom+1 then hp.at.y=hp.at.y+nameBottom+1-band.y;band=track(hp)end
        endY=math.max(endY,band.y+band.h)
      end
      local mana,endurance=record.mana,record.endurance
      if mana and endurance then
        local left=math.min(mana.at.x,endurance.at.x);local right=math.max(mana.at.x+mana.at.w,endurance.at.x+endurance.at.w)
        local half=math.max(1,(right-left-2)/2)
        mana.at.x,mana.at.w=left,half;endurance.at.x,endurance.at.w=left+half+2,half
        local first,second=track(mana),track(endurance);local y=math.max(endY+1,math.min(first.y,second.y))
        mana.at.y=mana.at.y+y-first.y;endurance.at.y=endurance.at.y+y-second.y
        endY=math.max(y+first.h,y+second.h)
      else
        local resource=mana or endurance
        if resource then local band=track(resource);local y=math.max(endY+1,band.y);resource.at.y=resource.at.y+y-band.y;endY=y+band.h end
      end
      if record.pet then local band=track(record.pet);local y=math.max(endY+1,band.y);record.pet.at.y=record.pet.at.y+y-band.y;endY=y+band.h end
      if boxes[row]then boxes[row].y=boxes[row].y+delta;endY=math.max(endY,boxes[row].y+boxes[row].h)end
      bottom=math.max(endY,primary.at.y+primary.at.h)
      record.primary.node.statusGroupHit={x=boxes[row]and boxes[row].x or primary.at.x,y=top,
        w=primary.at.x+primary.at.w-(boxes[row]and boxes[row].x or primary.at.x),h=bottom-top}
      local nextRow=ordered[index+1]
      if nextRow then extra=math.max(extra,bottom+2-rows[nextRow].primary.at.y)end
    end
    local footerTop=bottom+4
    for _,entry in ipairs(nodes)do
      local n=entry.node;local name=id(n)
      if not n.statusGroupRow and(name=="LFGButton"or(name=="InviteButton"or name=="DisbandButton"or name=="FollowButton"or name=="DeclineButton")and entry.at.y>designH*.6)then
        entry.at.y=math.max(footerTop,entry.at.y+extra)
        if entry.at.y>designH*1.5 then entry.at.y=footerTop end
        naturalH=math.max(naturalH,entry.at.y+entry.at.h+6)
      end
    end
    naturalH=math.max(naturalH,bottom+6)
    local xScale=width/designW
    for _,entry in ipairs(nodes)do
      if entry.node.statusGroupRow then
        if entry.node.type=="Gauge"and number((entry.node.rect or{}).x)<0 and boxes[entry.node.statusGroupRow]then entry.node.statusReplaced=true end
      end
      local at=entry.at
      at.x,at.w=at.x*xScale,at.w*xScale
      if entry.node.statusGroupName then
        entry.node.fields=clone(entry.node.fields or{})
        entry.node.fields.TextOffsetX=number(entry.node.fields.TextOffsetX)*xScale
      end
      if entry.node.type=="StaticAnimation"and at.y==0 and number((entry.node.rect or{}).h)>=designH*.8 then at.w=width;at.h=math.max(height,naturalH)end
      absolute(entry.node,at)
      local hit=entry.node.statusGroupHit
      if hit then hit.x,hit.w=hit.x*xScale,hit.w*xScale end
    end
    local overlays={}
    local maskLeft,maskTop,maskRight,maskBottom=width,height,0,0
    for row,cell in pairs(boxes)do
      local marker={type="StaticFrame",name="Hailstone_GroupHealthBox"..row,item="",children={},fields={},font=2,
        statusHealthRow=row,rect={x=cell.x*xScale,y=cell.y,w=cell.w*xScale,h=cell.h},anchors={explicit={left=false,right=false,top=false,bottom=false}}}
      overlays[#overlays+1]=marker
      maskLeft=math.min(maskLeft,cell.x*xScale-1);maskRight=math.max(maskRight,(cell.x+cell.w)*xScale+1)
      maskTop=math.min(maskTop,cell.y-1);maskBottom=math.max(maskBottom,cell.y+cell.h+1)
    end
    if #overlays>0 then
      table.insert(overlays,1,{type="StaticFrame",name="Hailstone_GroupHealthColumn",item="",children={},fields={},
        statusHealthColumn=true,rect={x=math.max(0,maskLeft),y=math.max(0,maskTop),w=maskRight-math.max(0,maskLeft),h=maskBottom-math.max(0,maskTop)},
        anchors={explicit={left=false,right=false,top=false,bottom=false}}})
    end
    local after=0;for index,n in ipairs(prepared.children)do if n.type=="StaticAnimation"then after=index end end
    for index,n in ipairs(overlays)do table.insert(prepared.children,after+index,n)end
  end
  if not reflow and not nested then
    for _,entry in ipairs(nodes)do
      local at=geometry(entry.node,{x=0,y=0,w=width,h=height,s=1})
      for k,v in pairs(at)do entry.at[k]=v end
    end
  end
  if not nested then
    for row,record in pairs(rows)do if record.primary then
      local primary=record.primary;local left,top,right,bottom=primary.at.x,primary.at.y,primary.at.x+primary.at.w,primary.at.y+primary.at.h
      for _,entry in ipairs(record.nodes)do
        if not entry.node.statusReplaced and entry.at.x>=0 then
          local at=entry.at
          if entry.node.type=="Gauge"and entry~=primary and R and R.GaugeTrackRect then at=R.GaugeTrackRect(entry.node,entry.at,instance)end
          left,top=math.min(left,at.x),math.min(top,at.y);right,bottom=math.max(right,at.x+at.w),math.max(bottom,at.y+at.h)
        end
      end
      if boxes[row]then left=math.min(left,boxes[row].x*width/designW)end
      for _,entry in ipairs(nodes)do if id(entry.node)=="GW_Voice"..row then right=math.min(right,entry.at.x)end end
      primary.node.statusGroupOrigin={x=primary.at.x,y=primary.at.y}
      primary.node.statusGroupHit={x=left,y=top,w=math.max(1,right-left),h=math.max(1,bottom-top)}
      local f=primary.node.fields or{};local textStart=primary.at.x+math.max(0,number(f.TextOffsetX))
      local textRight=math.min(primary.at.x+primary.at.w,right)
      for _,entry in ipairs(record.nodes)do if entry.role=="role"then textRight=math.min(textRight,entry.at.x-2)end end
      primary.node.statusGroupTextWidth=math.max(1,textRight-textStart)
      primary.node.statusGroupFitName=reflow
      if reflow then primary.node.statusGroupPaintBox=clone(primary.at);absolute(primary.node,primary.node.statusGroupHit)end
    end end
  end
  prepared.statusGroupLayout=true;prepared.statusGroupReflow=reflow;prepared.rect={x=0,y=0,w=width,h=math.max(height,naturalH)}
  if R and R.RetainLayout then R.RetainLayout(prepared)end
  s.groupOwnsScroll=reflow
  local record={clientWidth=width,clientHeight=height,source=source,fontFace=face,renderer=R,plan=prepared,
    w1=w1,h1=h1,w2=w2,h2=h2,w3=w3,h3=h3,
    width=width+number(insets.left)+number(insets.right),height=math.max(height,naturalH)+number(insets.top)+number(insets.bottom)}
  table.insert(s.groupCache,1,record);if #s.groupCache>4 then table.remove(s.groupCache)end
  return prepared,record.width,record.height
end

function M.Handles(screen)return families[screen]==true end
function M.Shown(screen,node)
  if node.statusReplaced then return false end
  if screen=="GroupWindow"and node.statusNativeName then
    local visible=childShown(screen,node.statusNativeName)
    if visible~=nil then return visible end
  end
  if drawReads and drawReads.screen==screen then
    if node._packColorsNormalized and (screen=="ExtendedTargetWnd"or screen=="CastSpellWnd")then
      -- Only numeric slots and spell orientation placeholders have native
      -- visibility for these screens. Artwork uses its authored visibility.
      if not nativeVisibility(screen,node)then return (node.fields or EMPTY).Visible~=false end
      if screen=="ExtendedTargetWnd"then
        local slot=nativeExtendedSlot(node)
        if slot and childShown(screen,slot.name)==false then return false end
      end
    end
    return nodeShown(screen,node)
  end
end
-- Generic buttons stay native. A click may change the model before later
-- controls run, so those controls must read again.
function M.Click()resetReads()end
local statusServices={{"windows","ChildShown"},{"windows","ChildState"},{"windows","ClickChild"},
  {"windows","ChildArt"},{"character","Gauge"},{"character","Label"}}
local spellServices={"GemInfo","GemOverlay","GemClick","BookState","BookMemorize","Sets","MemorizeSet"}
local validGraphs=setmetatable({},{__mode="k"})
function M.CanDraw(screen,plan,instance)
  if not M.Handles(screen)then return false,"Not a source status presenter"end
  if type(plan)~="table"or plan.type~="Screen"or type(plan.children)~="table"then return false,"Missing source status graph"end
  for _,need in ipairs(statusServices)do
    if not fn(need[1],need[2])then return false,"Status service unavailable: "..need[1].."."..need[2]end
  end
  if screen=="CastSpellWnd"then
    for _,name in ipairs(spellServices)do
      if not fn("spells",name)then return false,"Spell status service unavailable: "..name end
    end
  elseif screen=="TargetWindow"or screen=="BuffWindow"or screen=="ShortDurationBuffWindow"then
    if not fn("buffs","Slot")then return false,"Buff status service unavailable"end
    if not fn("spells","Show")then return false,"Spell display service unavailable"end
    if screen~="TargetWindow"and not fn("windows","SetText")then return false,"Blocked-buff entry service unavailable"end
    if screen~="TargetWindow"and not fn("windows","Button")then return false,"Buff removal service unavailable"end
  end
  -- Resolved and prepared graphs are retained by identity. Cache their shape
  -- only; host capabilities above are rechecked on each call.
  if not validGraphs[plan]then
    local count=0
    if not walk(plan,function(node)
      count=count+1
      return count<=8192 and type(node)=="table"and type(node.type)=="string"
        and (not node.children or type(node.children)=="table")
    end)then return false,"Status graph exceeds supported bounds"end
    validGraphs[plan]=true
  end
  return true
end

local function indexSource(screen,plan,instance)
  local source=plan
  local profile=instance.profile or{}
  if screen=="ExtendedTargetWnd"and tostring(profile.source or profile.id or""):lower()=="sparxx-stock"then
    source=clone(plan)
    walk(source,function(n)
      if n.type=="Label"and (id(n):match("^ETW_HPLabel%d+$")or id(n):match("^ETW_HPPercLabel%d+$"))then
        local at=n.rect or{}
        if number(at.w)>0 and number(at.h)>0 then absolute(n,at)end
      end
    end)
  end
  local first,keys,targetRows={},{},{}
  local isCast,isExtended=screen=="CastSpellWnd",screen=="ExtendedTargetWnd"
  local coverage=buffSlots[screen] and {allNodes={},activeNodes={},leaves={},parents={}} or nil
  local castNodes,castParents,castAliases={},{},{}
  local extendedNodes,extendedParents={},{}
  local stableGeometry=source._packColorsNormalized and (isCast or isExtended)
  local fixedExtended=isExtended and stableGeometry
  local function sourceKey(n,key)
    local list=keys[n]
    if not list then list={};keys[n]=list end
    list[#list+1]=key
  end
  local function choose(role,n)
    local old=first[role]
    if not old or number((old.rect or{}).w)<=0 or number((old.rect or{}).h)<=0 then first[role]=n end
  end
  local function coverageLeaf(n,slot)
    coverage.leaves[#coverage.leaves+1]={node=n,slot=slot}
    while n and not coverage.allNodes[n]do coverage.allNodes[n]=true;n=coverage.parents[n]end
  end
  local function castLeaf(n)
    while n and not castNodes[n]do castNodes[n]=true;n=castParents[n]end
  end
  walk(source,function(n,parent)
    local fields=n.fields or EMPTY
    if stableGeometry and (n.type=="TabBox" or fields.Style_Dividers~=false and
      (n.type=="HorizontalLayoutBox" or n.type=="VerticalLayoutBox"))then stableGeometry=false end
    if coverage then coverage.parents[n]=parent end
    local bi=buffIndex(screen,n)
    if bi then choose("buff",n);sourceKey(n,buffKeys[bi]);coverageLeaf(n,bi)end
    if isCast then
      castParents[n]=parent
      local name=id(n)
      local gi=gemIndex(n)
      if gi and n.type=="SpellGem"then choose("gem",n);sourceKey(n,gemKeys[gi]);castLeaf(n)end
      if name=="CSPW_SpellBookV"or name=="CSPW_SpellBookH"then sourceKey(n,"book");castLeaf(n)end
      if gemOrientationChildren[name] or gi and name~=gemIds[gi]then castAliases[name]=true end
    end
    if isExtended then
      extendedParents[n]=parent
      if fixedExtended and (fields.Layout and fields.Layout~="" or n.type=="TileLayoutBox" or
        n.type=="HorizontalLayoutBox" or n.type=="VerticalLayoutBox" or n.type=="TabBox")then fixedExtended=false end
      local row=targetHealthRow(n)
      if row then
        choose("row",n);targetRows[n]=true;sourceKey(n,"row:"..row)
        local entry=n
        while entry and not extendedNodes[entry]do extendedNodes[entry]=true;entry=extendedParents[entry]end
      end
    end
    if n.type=="Gauge"then
      choose("gauge",n)
      local gaugeKey="gauge:"..tostring(n.gaugeEqType or n.eqType)
      sourceKey(n,gaugeKey)
      if coverage and (gaugeKey=="gauge:27" or gaugeKey=="gauge:149")then coverageLeaf(n)end
    end
  end)
  local fields=source.fields or{}
  local extendedFlat=screen=="ExtendedTargetWnd" and source._packColorsNormalized
    and (not fields.Layout or fields.Layout=="")
  if extendedFlat then
    for _,node in ipairs(source.children)do
      if node.children and #node.children>0 then extendedFlat=false;break end
    end
  end
  if fixedExtended then
    for n in pairs(extendedNodes)do
      local name=id(n)
      if name:find("^ETW_Role") or name:find("^ETW_HPLabel") or name:find("^ETW_HPPercLabel")
        or name:find("^ETW_ManaGauge") or name:find("^ETW_STAGauge") or name:find("^ETW_AggroPct")then
        fixedExtended=false;break
      end
    end
  end
  local castVisibility
  if isCast and stableGeometry then
    castVisibility={}
    for gem=0,11 do castVisibility[#castVisibility+1]=gemIds[gem]end
    for name in pairs(castAliases)do castVisibility[#castVisibility+1]=name end
    -- A packed graph with many extra aliases can use the general traversal.
    if #castVisibility>25 then stableGeometry=false end
  end
  return {plan=source,original=plan,first=first,keys=keys,targetRows=targetRows,extendedFlat=extendedFlat,
    coverage=coverage,castNodes=isCast and castNodes or nil,castVisibility=castVisibility,
    stableGeometry=stableGeometry,fixedExtended=fixedExtended,extendedNodes=isExtended and extendedNodes or nil,
    compound=isExtended and stableGeometry and indexCompoundGauges(source)}
end

-- Scope a coverage walk to controls which could satisfy a current live slot
-- or a supplemental target gauge, while retaining their ancestor placement.
local function buffCoverage(coverage,low,high)
  if not coverage then return nil end
  if low==nil then return coverage.allNodes end
  if coverage.low~=low or coverage.high~=high then
    coverage.low,coverage.high=low,high
    local nodes=coverage.activeNodes
    wipe(nodes)
    for _,entry in ipairs(coverage.leaves)do
      if not entry.slot or occupiedSlot(low,high,entry.slot) then
        local node=entry.node
        while node and not nodes[node]do nodes[node]=true;node=coverage.parents[node]end
      end
    end
  end
  return coverage.activeNodes
end

local function fixedBuffCoverage(coverage,source,keys,R,w,h)
  if not coverage or not source._packColorsNormalized or not R or not R.RetainLayout or not R.Geometry then return end
  if coverage.fixed==nil then
    coverage.fixed=true
    for node in pairs(coverage.allNodes)do
      local kind,fields=node.type,node.fields or EMPTY
      if kind=="TileLayoutBox" or kind=="HorizontalLayoutBox" or kind=="VerticalLayoutBox"
        or kind=="TabBox" or fields.Layout and fields.Layout~="" then
        coverage.fixed=false
        break
      end
    end
  end
  if not coverage.fixed then return end
  local current=coverage.fixedLayout
  if current and current.w==w and current.h==h and current.geometry==R.Geometry then return current.nodes end
  -- Measure immutable bounds once. Apply current authored/native visibility
  -- later, including when a parent or a previously hidden alias changes.
  local function children(parent,box,x0,y0,x1,y1)
    local list={}
    for _,node in ipairs(parent.children or EMPTY)do
      if coverage.allNodes[node] then
        local at=R.Geometry(node,box)
        local l,t=math.max(x0,at.x),math.max(y0,at.y)
        local r,b=math.min(x1,at.x+at.w),math.min(y1,at.y+at.h)
        if r>l and b>t then
          local entry={node=node,keys=keys[node],name=id(node),shown=(node.fields or EMPTY).Visible~=false}
          if node.children and #node.children>0 then entry.children=children(node,at,l,t,r,b)end
          list[#list+1]=entry
        end
      end
    end
    return list
  end
  local nodes=children(source,{x=0,y=0,w=w,h=h,s=1},0,0,w,h)
  coverage.fixedLayout={w=w,h=h,geometry=R.Geometry,nodes=nodes}
  return nodes
end

local function liveBuffCoverage(screen,nodes,projection,covered)
  for _,entry in ipairs(nodes)do
    local n=entry.node
    if projection[n] and not n.statusReplaced then
      local visible=childShown(screen,entry.name)
      if visible or visible==nil and entry.shown then
        if entry.keys then for _,key in ipairs(entry.keys)do covered[key]=true end end
        if entry.children then liveBuffCoverage(screen,entry.children,projection,covered)end
      end
    end
  end
end

local function sameExtras(previous,extras,button)
  if not previous or previous.button~=button or #previous.extras~=#extras then return false end
  for i,extra in ipairs(extras)do
    local old=previous.extras[i]
    if old.name~=extra.name or old.template~=extra.template or old.kind~=extra.kind or old.eq~=extra.eq
      or old.key~=extra.key or old.x~=extra.x or old.y~=extra.y or old.w~=extra.w or old.h~=extra.h then return false end
  end
  return true
end

-- The common shipped Extended Target layout places every control directly in
-- the window, without visibility-dependent flow. Resolve its static anchors
-- once at the design size. Complex or developer-edited layouts keep the full
-- coverage and measurement paths.
local function extendedGeometry(record,plan,R,width,height)
  if record and record.plan==plan and record.geometry==R.Geometry
    and record.width==width and record.height==height then return record end
  local entries={}
  local client={x=0,y=0,w=width,h=height,s=1}
  for _,node in ipairs(plan.children)do
    local at=R.Geometry(node,client)
    entries[#entries+1]={node=node,at=at,slot=nativeExtendedSlot(node)}
  end
  return {plan=plan,geometry=R.Geometry,width=width,height=height,entries=entries}
end

local function extendedCoverage(record,metadata,scroll)
  if record.coverage then return record.coverage end
  local width,height=record.width,record.height
  if scroll then width,height=math.huge,math.huge end
  local coverage={}
  for _,entry in ipairs(record.entries)do
    local at=entry.at
    if metadata.targetRows[entry.node] and at.w>0 and at.h>0 and at.x<width and at.y<height
      and at.x+at.w>0 and at.y+at.h>0 then coverage[#coverage+1]=entry end
  end
  record.coverage=coverage
  return coverage
end

local function extendsBounds(record)
  if record.right then return record.right,record.bottom end
  local right,bottom={},{}
  for _,entry in ipairs(record.entries)do
    local at=entry.at
    entry.right,entry.bottom=at.x+at.w,at.y+at.h
    if entry.right>record.width then right[#right+1]=entry end
    if entry.bottom>record.height then bottom[#bottom+1]=entry end
  end
  table.sort(right,function(a,b)return a.right>b.right end)
  table.sort(bottom,function(a,b)return a.bottom>b.bottom end)
  record.right,record.bottom=right,bottom
  return right,bottom
end

local function extendedActiveRows(screen,overrides)
  local active,explicit=0,0
  for _,row in ipairs(extendedRows)do
    local value=childShown(screen,row.name)
    if value~=false then active=active|row.bit end
    if overrides then
      overrides[row.name]=value==nil and unconstrained or value
      if value==true then explicit=explicit|row.bit end
    end
  end
  return active,explicit
end

local function castVisibility(screen,children,visibility)
  local stamp=0
  for i,name in ipairs(children)do
    local shown=childShown(screen,name)
    visibility[name]=shown==nil and unconstrained or shown
    -- nil leaves the source's Visible flag in force. True can override it.
    local override=shown==nil and 0 or shown and 1 or 2
    stamp=stamp | (override << ((i-1)*2))
  end
  return stamp
end

local function geometryMatches(cache,stamp,R,w,h,button)
  return cache and cache.stamp==stamp and cache.renderer==R and cache.visit==R.VisitChildren
    and cache.measure==R.MeasureChildren and cache.geometry==R.Geometry and cache.designW==w
    and cache.designH==h and cache.button==button
end

-- Keep every authored node in place. Resolve live coverage every frame and
-- reuse the drawing graph when the actual synthesized placements still match.
local function prepare(screen,plan,instance,R)
  if screen=="GroupWindow"then return M.GroupLayout(plan,instance,R)end
  local s=state(instance,screen);local frame=ui.GetFrameCount()
  if s.prepared and s.frame==frame and s.original==plan then return s.prepared,s.width,s.height end
  s.original,s.frame=plan,frame
  local metadata=s.sourceMetadata
  if not metadata or metadata.original~=plan then
    metadata=indexSource(screen,plan,instance);s.sourceMetadata=metadata;s.generated=nil;s.layout=nil
    if s.castShown then wipe(s.castShown);s.castShownValid=false end
  end
  local source,first,sourceKeys=metadata.plan,metadata.first,metadata.keys
  local insets=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or{}
  local insetW=number(insets.left)+number(insets.right)
  local insetH=number(insets.top)+number(insets.bottom)
  local width=math.max(1,number((plan.rect or {}).w,200)-insetW)
  local height=math.max(1,number((plan.rect or {}).h,100)-insetH)
  local activeRows,explicitRows
  if screen=="ExtendedTargetWnd"then
    if not s.extendedShown then s.extendedShown={} end
    activeRows,explicitRows=extendedActiveRows(screen,s.extendedShown)
    s.extendedActiveRows=activeRows
    s.extendedShownValid=true
  end
  local stamp
  -- These packed graphs have no user-movable split or page selection.
  -- Their extent depends only on native visibility and authored geometry.
  if metadata.stableGeometry and R and R.RetainLayout then
    if screen=="CastSpellWnd"then
      if not s.castShown then s.castShown={} end
      stamp=castVisibility(screen,metadata.castVisibility,s.castShown)
      s.castShownValid=true
    elseif metadata.fixedExtended then stamp=activeRows | (explicitRows<<#extendedRows)
    elseif activeRows==0 and not metadata.extendedFlat then stamp=0 end
  end
  local button=instance.style and instance.style.button
  button=type(button)=="table"and button.template or button
  if stamp and geometryMatches(s.layout,stamp,R,width,height,button)then
    local layout=s.layout
    s.prepared,s.width,s.height=layout.plan,layout.width+insetW,layout.height+insetH
    return s.prepared,s.width,s.height
  end
  local designW,designH=width,height
  s.layout=nil
  width,height=snapSize(screen,plan,instance,R,width,height)
  local covered,replaced={},{}
  local firstRow,rowRect=first.row,nil
  local occupiedLow,occupiedHigh
  if buffSlots[screen]then occupiedLow,occupiedHigh=occupiedBuffs(screen)end
  local coverageNodes=metadata.castNodes or metadata.extendedNodes or buffCoverage(metadata.coverage,occupiedLow,occupiedHigh)
  -- Coverage only decides where to add missing live rows. When the host has
  -- no rows, draw the authored graph normally without walking it twice.
  if (not activeRows or activeRows~=0) and (not coverageNodes or coverageNodes[source]) then
    local function cover(n,at)
      local keys=sourceKeys[n]
      if not keys then return end
      for _,key in ipairs(keys)do covered[key]=true end
      if at and not rowRect and metadata.targetRows[n]then firstRow,rowRect=n,at end
    end
    local fixed=fixedBuffCoverage(metadata.coverage,source,sourceKeys,R,width,height)
    local flat=metadata.extendedFlat and R and R.Geometry
      and extendedGeometry(metadata.extendedGeometry,source,R,width,height)
    if fixed then
      liveBuffCoverage(screen,fixed,coverageNodes,covered)
    elseif flat then
      metadata.extendedGeometry=flat
      for _,entry in ipairs(extendedCoverage(flat,metadata,(source.fields or{}).Style_VScroll==true))do
        if (not entry.slot or activeRows&entry.slot.bit~=0) and nodeShown(screen,entry.node) then
          cover(entry.node,entry.at)
        end
      end
    elseif R and R.VisitChildren then
      local client={x=0,y=0,w=width,h=height,s=1}
      local opts=coverageNodes and {nodes=coverageNodes}or nil
      if metadata.coverage then opts.nodesOnly=true end
      if screen=="ExtendedTargetWnd"and (source.fields or{}).Style_VScroll==true then
        -- Existing offscreen rows are reachable by the inherited scroll child.
        -- Do not replace their anchored rectangles with small duplicate gauges.
        opts={nodes=coverageNodes,clip={x=0,y=0,w=math.huge,h=math.huge,s=1}}
      end
      R.VisitChildren(screen,source,instance,client,cover,opts)
    else
      -- Isolated presenter fixtures may not provide the renderer traversal.
      -- A real source graph is always checked through resolved placements.
      walk(source,function(n)if shown(screen,id(n))and number((n.rect or{}).w)>0 and number((n.rect or{}).h)>0 then cover(n)end end)
    end
  end
  local extraX,extraY,extraHeight=0,height,0
  local extras={}
  local function append(template,name,kind,eq,key)
    local measured=key=="target row"and rowRect or template and template.rect
    local fallbackW=not template and kind=="Gauge"and math.max(80,width)or 24
    local w=math.max(12,number(measured and measured.w,fallbackW))
    local h=math.max(12,number(measured and measured.h,24))
    if extraX>0 and extraX+w>width then extraX=0;extraY=extraY+extraHeight+3;extraHeight=0 end
    extras[#extras+1]={template=template,name=name,kind=kind,eq=eq,key=key,x=extraX,y=extraY,w=w,h=h}
    width=math.max(width,extraX+w);height=math.max(height,extraY+h)
    extraX=extraX+w+3;extraHeight=math.max(extraHeight,h)
  end
  local limit=buffSlots[screen]
  if limit then
    for n=0,limit-1 do
      local key,child=buffKeys[n],buffIds[n]
      if not covered[key] and (occupiedLow and occupiedSlot(occupiedLow,occupiedHigh,n)
        or occupiedLow==nil and call("buffs","Slot",screen,child))then
        replaced[key]=true;append(first.buff,child,"Button",nil,"buff")
      end
    end
  elseif screen=="CastSpellWnd"then
    for n=0,11 do
      if not covered[gemKeys[n]]then
        local info=call("spells","GemInfo",screen,gemIds[n])
        if info and info.shown~=false then replaced[gemKeys[n]]=true;append(first.gem,gemIds[n],"SpellGem",nil,"gem")end
      end
    end
    if not covered.book then
      replaced.book=true
      append(first.gem,"CSPW_SpellBookV","Button",nil,"book")
    end
  elseif screen=="ExtendedTargetWnd"then
    for _,row in ipairs(extendedRows)do
      if activeRows&row.bit~=0 and not covered[row.key]then
        replaced[row.key]=true;append(firstRow,row.name,"Gauge",row.eq,"target row")
      end
    end
  end
  if screen=="TargetWindow"then
    if not covered["gauge:27"]then
      local _,name,raw=call("character","Gauge",27)
      if raw and raw~=-1 and name and name~=""then
        replaced["gauge:27"]=true;append(first.gauge,"Hailstone_TargetOfTarget","Gauge",27,"target of target")
      end
    end
    if not covered["gauge:149"]then
      local _,_,aggro=call("character","Gauge",149)
      if aggro and aggro~=-1 and call("character","Label",302)==call("character","Label",28)then
        replaced["gauge:149"]=true
        append(first.gauge,"Hailstone_TargetAggro","Gauge",149,"target aggro")
      end
    end
  end
  -- Growing a source client for extra slots must not resurrect an earlier
  -- clipped/hidden definition of the same control and create duplicate input.
  -- Copy only affected paths; original compiled nodes remain immutable.
  local prepared=source
  if #extras==0 then s.generated=nil
  elseif sameExtras(s.generated,extras,button)then prepared=s.generated.plan
  else
    prepared={};for k,v in pairs(source)do prepared[k]=v end
    prepared.children={}
    local function suppress(n)
      local hidden=false
      local keys=sourceKeys[n]
      if keys then for _,key in ipairs(keys)do if replaced[key]then hidden=true;break end end end
      local oldChildren,children=n.children,nil
      if oldChildren then
        for i,child in ipairs(oldChildren)do
          local value=suppress(child)
          if value~=child and not children then
            children={}
            for j=1,i-1 do children[j]=oldChildren[j]end
          end
          if children then children[i]=value end
        end
      end
      if not hidden and not children then return n end
      local out={};for k,v in pairs(n)do out[k]=v end
      out.children=children or oldChildren;out.statusReplaced=hidden or n.statusReplaced
      return out
    end
    for i,n in ipairs(source.children)do prepared.children[i]=suppress(n)end
    for _,extra in ipairs(extras)do
      local n
      if extra.template then n=clone(extra.template)
      else
        diagnostic(instance,screen,"missing-template:"..extra.key,"Additional "..extra.key.." uses this skin's shared control artwork")
        n={art={animation="",background="",template="",drawTemplate=""},font=3,colors={},text="",
          fields={ButtonDrawTemplate=button,SpellGemDrawTemplate={Holder="A_SpellGemHolder",Background="A_SpellGemBackground",Highlight="A_SpellGemHighlight"}}}
      end
      n.name,n.item,n.type=extra.name,extra.name,extra.kind;n.children={}
      n.eqType,n.gaugeEqType=extra.eq or "",extra.eq or ""
      n.fields=n.fields or {};n.fields.ScreenID=extra.name;n.fields.Visible=true
      n.rect={x=extra.x,y=extra.y,w=extra.w,h=extra.h}
      n.anchors={topToTop=true,bottomToTop=true,leftToLeft=true,rightToLeft=true,top=0,bottom=0,left=0,right=0,
        explicit={top=false,bottom=false,left=false,right=false}}
      n.statusExtra=extra.key
      if extra.key=="book"then n.text="Spell book"end
      prepared.children[#prepared.children+1]=n
    end
    s.generated={plan=prepared,extras=extras,button=button}
    if R and R.RetainLayout then R.RetainLayout(prepared)end
  end
  s.prepared,s.width,s.height=prepared,width+insetW,height+insetH
  if stamp then
    s.layout={stamp=stamp,renderer=R,visit=R.VisitChildren,measure=R.MeasureChildren,geometry=R.Geometry,
      designW=designW,designH=designH,button=button,plan=prepared,width=width,height=height,
      contentStable=not activeRows or activeRows==0}
  end
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
    if screen=="ExtendedTargetWnd"then
      local s=state(instance,screen)
      local flat=s.sourceMetadata.extendedFlat and R.Geometry and extendedGeometry(s.extendedExtent,prepared,R,w,h)
      if flat then
        s.extendedExtent=flat
        local right,bottom=extendsBounds(flat)
        local active=(#right>0 or #bottom>0) and extendedActiveRows(screen) or 0
        for _,entry in ipairs(right)do
          if (not entry.slot or active&entry.slot.bit~=0) and nodeShown(screen,entry.node) then w=entry.right;break end
        end
        for _,entry in ipairs(bottom)do
          if (not entry.slot or active&entry.slot.bit~=0) and nodeShown(screen,entry.node) then h=entry.bottom;break end
        end
        return w,h
      end
    end
    local s=instance.statusPresenters and instance.statusPresenters[screen]
    local layout=s and s.layout and s.layout.contentStable and s.layout
    if layout and layout.plan==prepared and layout.measure==R.MeasureChildren and layout.contentW then
      return layout.contentW,layout.contentH
    end
    local mw,mh=R.MeasureChildren(screen,prepared,instance,{x=0,y=0,w=w,h=h,s=1})
    w,h=math.max(w,mw),math.max(h,mh)
    if layout and layout.plan==prepared then layout.contentW,layout.contentH=w,h end
  end
  return w,h
end

local buffLimitTint={1,.8,.25,1}
local function drawBuff(screen,node,box,instance,R,control)
  local child=control.name
  local spell,ms,name,good,fade,counter,cr,cg,cb,limit=buffInfo(screen,child,true,control.buff)
  if not spell then return true end -- the host explicitly clears both art layers for an empty slot
  local reads=drawReads
  if reads and reads.screen~=screen then reads=nil end
  local paint=reads and reads.buffPaint or {skipDecal=true,caption="",tint={1,1,1,1}}
  local tint=paint.tint
  tint[4]=math.max(0,math.min(1,number(fade,1)))
  local nativeEnabled,nativeChecked=call("windows","ChildState",screen,child)
  local fields=node.fields or EMPTY
  paint.enabled,paint.checked=nativeEnabled,nativeChecked
  if nativeEnabled==nil then paint.enabled=fields.Enabled~=false end
  if nativeChecked==nil then paint.checked=fields.Checked==true end
  R.PaintControl(screen,node,box,instance,paint)
  R.Animation(instance,good and "BlueIconBackground"or "RedIconBackground",box,tint)
  local tex,u0,v0,u1,v1=call("windows","ChildArt",screen,child,"decal")
  local painted=texture(R,instance,tex,box,u0,v0,u1,v1,tint)
  if not painted then caption(node,box,name or tostring(spell),instance.palette and instance.palette.text,"center")end
  local hover
  if not reads or reads.buffInteractive~=false then
    local _,wasHovered,active=hit(screen,child,box,nativeEnabled~=false,true,control.hitId)
    hover=wasHovered
    if active and reads then reads.buffActive=true end
  end
  if hover then
    local time=ms and ms>=0 and (math.floor(ms/60000)..":"..string.format("%02d",math.floor(ms/1000)%60))or ""
    ui.SetTooltip(tostring(name or spell)..(time~=""and "\n"..time or "").."\nRight-click for spell actions")
    if not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
      state(instance,screen).buffMenu={id=child,spell=spell,name=name or tostring(spell),remove=screen~="TargetWindow"}
      ui.OpenPopup("##source-buff-actions");consume(instance)
    end
  end
  local timer=ms and ms>=0 and ms<60000
  if counter or limit or timer then
    local overlay=reads and reads.buffOverlayBox or {}
    overlay.x,overlay.y,overlay.w,overlay.h=box.x,box.y,box.w,12*(box.s or 1)
    if counter then
      local ink=reads and reads.buffCounterTint or {1,1,1,1}
      ink[1],ink[2],ink[3]=cr or 1,cg or 1,cb or 1
      caption(node,overlay,counter,ink,"right")
    end
    overlay.y=box.y+math.max(0,box.h-overlay.h)
    if limit then caption(node,overlay,limit,buffLimitTint)end
    if timer then caption(node,overlay,math.floor(ms/1000),nil,"right")end
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
        resetReads()
        call("windows","SetText","BlockedBuffWnd","BW_EditSpellToBlock",tostring(b.spell))
        call("windows","ClickChild","BlockedBuffWnd","BW_AddSpellToBlock","left")
      end
      if ui.MenuItem("Remove")and call("buffs","Slot",screen,b.id)==b.spell then
        resetReads()
        call("windows","Button",screen,b.id,3)
      end
    end
  end
  ui.EndPopup()
end
local noGaugeCaption={caption=""}
local function paintStatusGauge(screen,node,box,instance,R,options,extendedKind)
  local reads=drawReads
  if not R.PaintGauge or node.type~="Gauge" or not reads or reads.screen~=screen then
    return R.PaintControl(screen,node,box,instance,options)
  end
  local fraction,text,r,g,b,raw
  if extendedKind then fraction,text,raw,r,g,b=gaugeInfo(screen,extendedKind)
  else
    local child=id(node)
    local values=reads.childGauges[child]
    if values==nil then
      local f,t,cr,cg,cb=call("windows","ChildGauge",screen,child)
      if f~=nil or t and t~="" or cr then
        values=readResult(reads)
        values[1],values[2],values[3],values[4],values[5]=f,t,cr,cg,cb
      else values=false end
      reads.childGauges[child]=values
    end
    if values then fraction,text,r,g,b=table.unpack(values,1,5)end
    local kind=tonumber(node.gaugeEqType or node.eqType)
    if fraction==nil and kind then fraction,text,raw,r,g,b=gaugeInfo(screen,kind)end
  end
  local view=reads.gaugeView
  if raw==-1 then view.fraction=nil else view.fraction=fraction or 0 end
  view.caption=text or ""
  if raw~=-1 and r then
    local color=reads.gaugeTint
    color[1],color[2],color[3]=r,g,b
    view.tint=color
  else view.tint=nil end
  return R.PaintGauge(screen,node,box,instance,view,options)
end

local function fitGroupName(R,instance,node,record,name,available)
  if not R.MeasureText then return name end
  local previous=record.fittedName
  if previous and previous.node==node and previous.measure==R.MeasureText and
    previous.text==name and previous.available==available then return previous.result end
  local fitted=name
  if R.MeasureText(instance,node,name)>available then
    if R.MeasureText(instance,node,"...")>available then fitted=""
    else
      local result=""
      for letter in name:gmatch(".[\128-\191]*")do
        if R.MeasureText(instance,node,result..letter.."...")>available then break end
        result=result..letter
      end
      fitted=result.."..."
    end
  end
  record.fittedName={node=node,measure=R.MeasureText,text=name,available=available,result=fitted}
  return fitted
end

local function rowRecord(instance,screen,canonical)
  local controls=state(instance,screen).controls
  local record=controls[canonical]
  if not record then record={};controls[canonical]=record end
  return record
end
local function drawRow(screen,node,box,instance,R,row,canonical,hpLabel,extendedKind,hitId)
  local group=screen=="GroupWindow"
  local reads=drawReads and drawReads.screen==screen and drawReads
  local rec
  local paintBox=box;local sourceBox=node.statusGroupPaintBox
  if sourceBox then
    local s=box.s or 1;local at=node.rect
    paintBox=reads and node._packColorsNormalized and reads.groupPaintBox or {}
    paintBox.x,paintBox.y=box.x+(sourceBox.x-at.x)*s,box.y+(sourceBox.y-at.y)*s
    paintBox.w,paintBox.h,paintBox.s=sourceBox.w*s,sourceBox.h*s,s
  end
  local options
  if hpLabel then
    options={caption=call("character","Label",151+row)or""}
  elseif group and node.statusGroupName and node.statusGroupFitName then
    rec=rowRecord(instance,screen,canonical)
    local _,name,raw=gaugeInfo(screen,10+row)
    name=raw==-1 and""or tostring(name or""):match("^[^\n]*")
    local available=number(node.statusGroupTextWidth,paintBox.w/(box.s or 1))*(box.s or 1)
    name=fitGroupName(R,instance,node,rec,name,available)
    options=rec.nameOptions
    if not options or options.caption~=name or options.textOnly~=(node.statusGroupNameOnly==true)then
      options={caption=name,textOnly=node.statusGroupNameOnly==true};rec.nameOptions=options
    end
  elseif group and node.statusGroupQuiet then options=noGaugeCaption
  elseif extendedKind and reads and reads.extendedBottom then
    local fields=node.fields or EMPTY
    local offset=number(fields.TextOffsetY)
    if offset>0 and not fields.Style_VCenter and box.y+offset*(box.s or 1)>=reads.extendedBottom then
      -- Some compound gauges keep their caption intentionally below the
      -- client clip. Their track still paints at its original coordinates.
      options=noGaugeCaption
    end
  end
  if group or node._packColorsNormalized and node.type=="Gauge"then
    paintStatusGauge(screen,node,paintBox,instance,R,options,extendedKind)
  else R.PaintControl(screen,node,paintBox,instance,options)end
  if reads and (group and reads.groupInteractive==false or not group and reads.extendedInteractive==false)then return true end
  rec=rec or rowRecord(instance,screen,canonical)
  local click,hover,active=hit(screen,not hitId and id(node),box,enabled(screen,canonical),true,hitId)
  if active and reads then
    if group then reads.groupActive=true else reads.extendedActive=true end
  end
  if (not group or hover) and ui.IsItemClicked(ui.Mouse.Left)then rec.dragged=false end
  if active and ui.IsMouseDragging(ui.Mouse.Left)then rec.dragged=true end
  local drag=instance.hud and instance.hud.DragItem
  if drag then
    if group and reads then
      if reads.groupDragMoved==nil or active or click then reads.groupDragMoved=not not drag() end
      if reads.groupDragMoved then rec.dragged=true end
    elseif reads then
      if reads.extendedDragMoved==nil or active or click then reads.extendedDragMoved=not not drag()end
      if reads.extendedDragMoved then rec.dragged=true end
    elseif drag()then rec.dragged=true end
  end
  if click and not rec.dragged then
    resetReads();call("windows","ClickChild",screen,canonical,"left")
  end
  if hover then
    if not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
      resetReads()
      call("windows","ClickChild",screen,group and canonical or "ETW_Role"..row,group and "right"or "rightup")
      consume(instance)
    end
    if group then
      local tips=""
      for _,name in ipairs(groupRoles[row] or EMPTY)do
        local tip=shown(screen,name)and call("windows","ChildTooltip",screen,name)
        if tip and tip~=""then tips=tips=="" and tip or tips.."\n"..tip end
      end
      tooltip(screen,canonical,tips)
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
  local child=id(node)
  local controls=state(instance,screen).controls
  local rec=controls[child]
  if not rec then
    rec={info={},icon={},backgroundTint={1,1,1,1},iconTint={1,1,1,1},hitId="##source-status:"..screen..":"..child}
    controls[child]=rec
  end
  local f=node.fields or EMPTY;local t=f.SpellGemDrawTemplate or EMPTY
  local scale=box.s or 1
  local ox,oy=number(f.SpellIconOffsetX)*scale,number(f.SpellIconOffsetY)*scale
  local icon=rec.icon
  icon.x,icon.y,icon.w,icon.h,icon.s=box.x+ox,box.y+oy,math.max(1,box.w-2*ox),math.max(1,box.h-2*oy),scale
  local info=call("spells","GemInfo",screen,child,rec.info,icon.y,icon.y+icon.h)or EMPTY
  if info.shown==false then return true end
  R.Animation(instance,t.Holder,box)
  local tint=rec.backgroundTint
  tint[1],tint[2],tint[3]=info.tintR or 1,info.tintG or 1,info.tintB or 1
  R.Animation(instance,t.Background,box,tint)
  rec.iconTint[4]=info.tintA or 1
  texture(R,instance,info.tex,icon,info.u0,info.v0,info.u1,info.v1,rec.iconTint)
  local top,r,g,b,a=info.top,info.coolR,info.coolG,info.coolB,info.coolA
  if info~=rec.info or info.overlay~=nil and top==nil then
    top,r,g,b,a=call("spells","GemOverlay",screen,child,icon.y,icon.y+icon.h)
  end
  if top and top<icon.y+icon.h then ui.DrawRectFilled(icon.x,math.max(icon.y,top),icon.x+icon.w,icon.y+icon.h,r or 0,g or 0,b or 0,a or .65)end
  local reads=drawReads and drawReads.screen==screen and drawReads
  if reads and reads.castInteractive==false then return true end
  -- The native spell-gem model uses the same usable-gem state for both.
  local on
  if reads and node._packColorsNormalized and info.shown==true then on=true
  else on=enabled(screen,child)end
  local click,hover,active=hit(screen,child,box,on,true,rec.hitId)
  if hover then R.Animation(instance,t.Highlight,box);if info.tooltip and info.tooltip~=""then ui.SetTooltip(info.tooltip)end end
  local frame=reads and reads.castFrame or ui.GetFrameCount()
  if rec.frame and frame>rec.frame+1 then rec.right=nil;rec.dragged=false end
  rec.frame=frame
  if ui.IsItemClicked(ui.Mouse.Left)then rec.dragged=false end
  if on and active and ui.IsMouseDragging(ui.Mouse.Left)and not call("cursor","HoldingButton")then
    resetReads()
    if call("cursor","PickUp",screen,child)then rec.dragged=true end
  end
  if on and click and not rec.dragged then resetReads();call("spells","GemClick",child,"left")end
  local drag=modern_spell_drag_frame==frame and modern_spell_drag or nil
  if on and drag and not drag.gem and ui.IsMouseHoveringRect(box.x,box.y,box.x+box.w,box.y+box.h)
    and ui.IsWindowHovered((ui.HoveredFlags.ChildWindows or 0)|(ui.HoveredFlags.AllowWhenBlockedByActiveItem or 0))
    and ui.IsMouseReleased(ui.Mouse.Left)then resetReads();call("spells","BookMemorize",drag.slot,index)end
  if on and hover and not ui.GetIO().alt and ui.IsItemClicked(ui.Mouse.Right)then
    rec.right={time=ui.GetTime(),spell=spellInGem(index),held=false}
    resetReads();call("spells","GemClick",child,"rightdown");consume(instance)
  end
  local press=rec.right
  if press then
    if not on or press.spell~=spellInGem(index)then rec.right=nil
    elseif ui.IsMouseDown(ui.Mouse.Right)and not press.held and ui.GetTime()-press.time>=.5 then
      press.held=true;resetReads();call("spells","GemClick",child,"rightheld")
    elseif ui.IsMouseReleased(ui.Mouse.Right)then
      local keep=press.held and press.spell and press.spell~=-1 and overSpellDisplay(press.spell)
      if press.held or hover then
        resetReads();call("spells","GemClick",child,press.held and "rightupheld"or "rightup",not hover)
      end
      if keep then call("spells","Show",press.spell)end
      rec.right=nil
    elseif not ui.IsMouseDown(ui.Mouse.Right)then rec.right=nil end
  end
  if reads and (active or rec.right)then reads.castHeld=true end
  return true
end
local function drawBook(screen,node,box,instance,R)
  R.PaintControl(screen,node,box,instance)
  local reads=drawReads and drawReads.screen==screen and drawReads
  if reads and reads.castInteractive==false then return true end
  local child=id(node)
  local click,hover,active=hit(screen,child,box,enabled(screen,child),reads~=nil)
  if reads and active then reads.castHeld=true end
  if click then resetReads();call("windows","ClickChild",screen,child,"left")end
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
local drawMetadata={}
for screen in pairs(families)do drawMetadata[screen]=setmetatable({},{__mode="k"})end
local function classifyDraw(screen,node,cache)
  local result=cache[node]
  if result~=nil then return result end
  local label,role,native=buffLabel(screen,node)
  local buff=buffIndex(screen,node)
  local row,canonical=rowFor(screen,node)
  local name=id(node)
  local gem=screen=="CastSpellWnd"and node.type=="SpellGem"and gemIndex(node)
  local book=screen=="CastSpellWnd"and(name=="CSPW_SpellBookV"or name=="CSPW_SpellBookH")
  local target=screen=="TargetWindow"and node.type=="Gauge"and tonumber(node.gaugeEqType or node.eqType)==6
  local decorate=(screen=="BuffWindow"or screen=="ShortDurationBuffWindow")
    and (node.type=="StaticAnimation"or node.type=="StaticTintedBlendAnimation")
  if label or buff or row or gem or book or target or decorate then
    result={label=label,buff=buff,row=row,canonical=canonical,gem=gem,book=book,target=target,decorate=decorate,
      foreignName=role=="name"and not native,
      hpLabel=screen=="ExtendedTargetWnd"and node.type=="Label"and row and name=="ETW_HPLabel"..row}
    if screen=="ExtendedTargetWnd"and node._packColorsNormalized and node.type=="Gauge"then
      -- This native window provides slot visibility, tint and decals.
      -- Authored EQType gauges take their values from the character model.
      local kind=tonumber(node.gaugeEqType or node.eqType)
      if kind and kind>=42 and kind<102 then result.extendedKind=kind end
    end
    if buff or target or row and screen=="GroupWindow" then
      result.name,result.hitId=name,"##source-status:"..screen..":"..name
    end
    if decorate then
      local art=(name.." "..tostring((node.art or{}).animation or"").." "..tostring(node.item or"")):lower()
      result.named=art:find("buffbackground",1,true)or art:find("buff_background",1,true)or art:find("buff_back",1,true)
    end
  else result=false end
  cache[node]=result
  return result
end
local function skipEmptyBuff(screen,node)
  local reads=drawReads
  if not reads or reads.screen~=screen or not buffSlots[screen] then return false end
  local controls=drawMetadata[screen]
  local control=controls[node]
  if control==nil then control=classifyDraw(screen,node,controls) end
  local slot=control and (control.label or control.buff)
  if not slot then return false end
  local low,high=readOccupied(reads,screen)
  return low~=false and not occupiedSlot(low,high,slot)
end
function M.DrawControl(screen,node,box,instance,R)
  local metadata=drawMetadata[screen]
  if not metadata then return false end
  if node.statusReplaced then return true end
  if screen=="GroupWindow"then
    if node.statusHealthColumn then
      local c=instance.palette.background or{.08,.08,.09,1}
      ui.DrawRectFilled(box.x,box.y,box.x+box.w,box.y+box.h,c[1],c[2],c[3],1);return true
    end
    if node.statusHealthRow~=nil then
      local gauge=node.statusHealthRow==0 and 1 or 10+node.statusHealthRow
      local fraction,_,raw,r,g,b=gaugeInfo(screen,gauge)
      if raw==-1 then fraction=nil end
      if R.PaintHealthBox then R.PaintHealthBox(instance,box,fraction,raw and raw< -1 and r and{r,g,b,1}or nil)end
      return true
    end
    if node.statusHealthPercentGauge then
      local gauge=node.statusHealthPercentGauge
      local fraction,_,raw=gaugeInfo(screen,gauge)
      if raw~=-1 and fraction then
        local value=tostring(math.floor(math.max(0,math.min(1,fraction))*100+.5))
        if R.PaintText then R.PaintText(screen,node,box,instance,value)
        else caption(node,box,value,instance.palette.text,"center")end
      end
      return true
    end
    if node.statusGroupPaintOnly then
      paintStatusGauge(screen,node,box,instance,R,node.type=="Gauge"and noGaugeCaption or nil);return true
    end
  end
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
  local control=classifyDraw(screen,node,metadata)
  if not control then return false end
  if control.label then
    local spell,_,name=buffInfo(screen,buffIds[control.label],false,control.label)
    if spell then
      R.PaintControl(screen,node,box,instance,control.foreignName and{caption=name or""}or nil)
    end
    return true
  end
  if control.decorate and buffDecoration(screen,node,box,instance,R,control.named)then return true end
  if control.buff then return drawBuff(screen,node,box,instance,R,control)end
  if control.row then
    return drawRow(screen,node,box,instance,R,control.row,control.canonical,control.hpLabel,control.extendedKind,control.hitId)
  end
  if control.gem then return drawGem(screen,node,box,instance,R,control.gem)end
  if control.book then return drawBook(screen,node,box,instance,R)end
  if control.target then
    R.PaintControl(screen,node,box,instance)
    local reads=drawReads
    if reads and reads.screen~=screen then reads=nil end
    if not reads or reads.buffInteractive~=false then
      local clicked,_,active=hit(screen,control.name,box,enabled(screen,"TargetHP"),true,control.hitId)
      if active and reads then reads.buffActive=true end
      if clicked then resetReads();call("windows","ClickChild",screen,"TargetHP","left")end
    end
    return true
  end
  return false
end
local function passiveExtendedPlan(screen,plan,instance,R)
  if screen~="ExtendedTargetWnd"or not windowHovered or not R.RetainLayout or not R.PaintGauge then return plan end
  local s=state(instance,screen)
  local compound=s.sourceMetadata and s.sourceMetadata.compound
  if not compound or drawReads.extendedInteractive then return plan end
  -- These source pieces are several clipped gauges sharing one model value.
  -- They have no named native gauge state. A raw -1 paints nothing, and an
  -- invisible button cannot begin interaction outside its hovered window.
  local absent=0
  for kind,bit in pairs(compound.kinds)do
    local _,_,raw=gaugeInfo(screen,kind)
    if raw==-1 then absent=absent|bit end
  end
  local rows=s.extendedShownValid and s.extendedActiveRows or extendedActiveRows(screen)
  local cached=s.compoundProjection
  if cached and cached.plan==plan and cached.absent==absent and cached.rows==rows then return cached.visible end
  local visible,children=plan
  for i,node in ipairs(plan.children)do
    local fragment=compound.pieces[node]
    local slot=node._packColorsNormalized and nativeExtendedSlot(node)
    local omit=fragment and absent&fragment~=0 or slot and rows and rows&slot.bit==0
    if omit and not children then
      children={}
      for j=1,i-1 do children[j]=plan.children[j]end
    elseif not omit and children then children[#children+1]=node end
  end
  if children then
    visible={}
    for key,value in pairs(plan)do visible[key]=value end
    visible.children=children
    R.RetainLayout(visible)
  end
  s.compoundProjection={plan=plan,absent=absent,rows=rows,visible=visible}
  return visible
end

-- A quiet Extended Target body is a good candidate for retaining its exact
-- draw commands. Interactive frames and changing model values still use the
-- original presenter, which owns layout, order, actions and texture lookup.
local retainedTypes={Screen=true,Page=true,LayoutBox=true,TemplateContainer=true,
  Label=true,StaticText=true,StaticHeader=true,StaticFrame=true,
  StaticAnimation=true,StaticTintedBlendAnimation=true,Gauge=true,TileLayoutBox=true}
local retainedGraphs=setmetatable({},{__mode="k"})
local nativeReplay,nextReplayProbe

local function findNativeReplay(frame)
  if nativeReplay then return nativeReplay end
  if nextReplayProbe and frame<nextReplayProbe then return end
  nextReplayProbe=frame+60
  local plugins=API.plugins
  local plugin=plugins and plugins.Get and plugins.Get("plugin:ui-pack-native")
  if not plugin or type(plugin.Version)~="function" or plugin.Version()~=2 then return end
  local capture,finish,begin,replay=plugin.BeginCapture,plugin.EndCapture,plugin.BeginReplay,plugin.EndReplay
  if type(capture)~="function" or type(finish)~="function" or type(begin)~="function" or type(replay)~="function" then return end
  nativeReplay={capture=capture,finish=finish,begin=begin,replay=replay}
  return nativeReplay
end

local function retainedGraph(plan)
  local validated=retainedGraphs[plan]
  if validated~=nil then return validated end
  validated=plan._packColorsNormalized==true and walk(plan,function(node)
    if retainedTypes[node.type] then return true end
    if node.type=="Button" and rowFor("ExtendedTargetWnd",node) then return true end
    return (node.type=="VerticalLayoutBox" or node.type=="HorizontalLayoutBox")
      and (node.fields or EMPTY).Style_Dividers==false
  end)
  retainedGraphs[plan]=validated
  return validated
end

local observableCalls={windows={Text=true,ChildColor=true,ChildUnder=true,ChildArt=true,
    ChildGauge=true,ChildShown=true,ChildState=true},character={Label=true,Gauge=true}}
local function watchCall(record,module,member,fn,...)
  if module=="assets" and (member=="InterfaceImage" or member=="Image") then return fn(...) end
  if not (observableCalls[module] and observableCalls[module][member]) or select("#",...)>3 then
    record.bad=true
    return fn(...)
  end
  local args=table.pack(...)
  local key=module.."\0"..member.."\0"..args.n
  for i=1,args.n do
    local arg,kind=args[i],type(args[i])
    if (kind=="string" and arg:find("\0",1,true))
      or (kind~="string" and kind~="number" and kind~="boolean" and kind~="nil") then
      record.bad=true
      return fn(...)
    end
    key=key.."\0"..kind..":"..tostring(arg)
  end
  local result=table.pack(fn(...))
  if result.n>6 then record.bad=true end
  for i=1,result.n do
    local kind=type(result[i])
    if kind=="userdata" and module=="windows" and member=="ChildArt" and i==1 then
      record.extraTextures[result[i]]=true
    elseif kind~="boolean" and kind~="string" and kind~="number" and kind~="nil" then record.bad=true end
  end
  local previous=record.seen[key]
  if previous then
    for i=1,6 do if previous.result[i]~=result[i] then record.bad=true end end
  elseif #record.calls<384 then
    record.methods[module.."\0"..member]={module,member,fn}
    local entry={fn=fn,args=args,result=result}
    record.seen[key]=entry
    record.calls[#record.calls+1]=entry
  else
    record.bad=true
  end
  return table.unpack(result,1,result.n)
end

local function sameValues(expected,a,b,c,d,e,f)
  return expected[1]==a and expected[2]==b and expected[3]==c
    and expected[4]==d and expected[5]==e and expected[6]==f
end

local function validRetained(record,plan,client,font)
  if record.plan~=plan or record.x~=client.x or record.y~=client.y or record.w~=client.w
    or record.h~=client.h or record.s~=client.s or record.font~=font then return false end
  for _,method in pairs(record.methods)do
    local group=API[method[1]]
    if not group or group[method[2]]~=method[3] then return false end
  end
  for name,expected in pairs(record.shown)do
    local actual=childShown("ExtendedTargetWnd",name)
    if expected~=(actual==nil and unconstrained or actual) then return false end
  end
  for kind,expected in pairs(record.gauges)do
    if not sameValues(expected,gaugeInfo("ExtendedTargetWnd",kind))then return false end
  end
  for _,entry in ipairs(record.calls)do
    local args=entry.args
    if not sameValues(entry.result,entry.fn(table.unpack(args,1,args.n))) then return false end
  end
  return true
end

local function probeRetainedArt(record,R,instance)
  if not R.ProbeArtwork(instance,record.artwork) then return false end
  for texture in pairs(record.extraTextures)do ui.DrawImage(texture,0,0,0,0) end
  return true
end

local function tryRetained(replay,record,R,instance)
  if not replay.begin(record.token) then return false end
  -- Normal Lua image submission is the client’s texture validation gate.
  -- These empty-clip probes never reach the backend as draw calls.
  ui.PushClipRect(0,0,0,0,true)
  local ok,ready=pcall(probeRetainedArt,record,R,instance)
  ui.PopClipRect()
  if not ok or not ready then replay.replay(0);return false end
  return replay.replay(record.token)==true
end

local function drawRetainedExtended(plan,instance,client,R)
  local reads=drawReads
  local s=reads.extendedState
  if reads.extendedInteractive~=false
    or not R.CaptureArtwork or not R.EndArtworkCapture
    or not R.ProbeArtwork or not R.Bindings or not R.Bindings.WatchCalls then
    return R.Draw("ExtendedTargetWnd",plan,instance,client,M)
  end
  local native=findNativeReplay(s.drawFrame)
  if not native or s.retainedRetry and s.drawFrame<s.retainedRetry or not retainedGraph(plan) then
    return R.Draw("ExtendedTargetWnd",plan,instance,client,M)
  end
  local record=s.retainedBody
  local font=call("settings","Option","font_face")
  if record and validRetained(record,plan,client,font) then
    if tryRetained(native,record,R,instance) then
      s.retainedHits=(s.retainedHits or 0)+1
      record.hits=record.hits+1
      if record.hits==4 then s.retainedCooldown=nil end
      return true
    end
    -- Unload, atlas replacement, or a changed clip invalidates the snapshot.
    s.retainedRejects=(s.retainedRejects or 0)+1
  elseif record then
    s.retainedReadChanges=(s.retainedReadChanges or 0)+1
  end
  s.retainedBody=nil
  if record and record.hits<4 then
    -- Capturing costs more than a normal draw. Avoid repeating it during
    -- combat if health or occupancy keeps changing before it pays for itself.
    local cooldown=math.min(64,(s.retainedCooldown or 2)*2)
    s.retainedCooldown=cooldown
    s.retainedRetry=s.drawFrame+cooldown
    return R.Draw("ExtendedTargetWnd",plan,instance,client,M)
  end
  if native.capture()~=true then
    nativeReplay=nil
    return R.Draw("ExtendedTargetWnd",plan,instance,client,M)
  end
  record={plan=plan,x=client.x,y=client.y,w=client.w,h=client.h,s=client.s,font=font,
    calls={},methods={},seen={},shown={},gauges={},extraTextures={},hits=0}
  local function observer(...)return watchCall(record,...)end
  local prior=R.Bindings.WatchCalls(observer)
  local previous=retainedCallObserver
  local artwork=R.CaptureArtwork()
  retainedCallObserver=observer
  reads.retainWatch=record
  local ok,drawn,why=pcall(R.Draw,"ExtendedTargetWnd",plan,instance,client,M)
  reads.retainWatch=nil
  retainedCallObserver=previous
  R.Bindings.WatchCalls(prior)
  R.EndArtworkCapture(artwork)
  local token=native.finish()
  if not ok then error(drawn,0) end
  if drawn and type(token)=="number" and not record.bad and not artwork.bad then
    for kind,live in pairs(record.gauges)do record.gauges[kind]=table.pack(table.unpack(live,1,6)) end
    record.token,record.artwork,record.seen=token,artwork,nil
    s.retainedBody=record
    s.retainedCaptures=(s.retainedCaptures or 0)+1
  else
    s.retainedRetry=s.drawFrame+90
  end
  return drawn,why
end

local function paintPrepared(screen,plan,instance,client,R)
  plan=passiveExtendedPlan(screen,plan,instance,R)
  setBuffGeometry(screen,plan,instance,client,R)
  if screen=="ExtendedTargetWnd" then return drawRetainedExtended(plan,instance,client,R) end
  if not buffSlots[screen] then return R.Draw(screen,plan,instance,client,M)end
  local s=state(instance,screen)
  local reads=drawReads
  -- These items use only mouse input. Still submit a held item when the
  -- pointer leaves the window, so releasing it follows ImGui's normal path.
  reads.buffInteractive=not plan._packColorsNormalized or not windowHovered or s.buffHeld or windowHovered()
  reads.buffActive=nil
  local skip=API.buffs and type(API.buffs.Occupied)=="function" and skipEmptyBuff or nil
  local drawn,why=R.Draw(screen,plan,instance,client,M,skip)
  s.buffHeld=reads.buffActive
  return drawn,why
end
local function drawPrepared(screen,plan,instance,client,R)
  local index=#readPool
  local reads=readPool[index]
  if reads then readPool[index]=nil
  else reads={shown={},enabled={},buffs={},gauges={},buffVisible={},results={},resultCount=0,
    childGauges={},groupMembers={},groupPaintBox={},gaugeView={},gaugeTint={0,0,0,1},
    buffPaint={skipDecal=true,caption="",tint={1,1,1,1}},buffOverlayBox={},buffCounterTint={1,1,1,1}}end
  reads.screen,reads.previous=screen,drawReads
  if screen=="ExtendedTargetWnd"then
    local s=state(instance,screen)
    reads.extendedState=s
    reads.extendedShown=s.extendedShownValid and s.extendedShown or nil
    reads.extendedInteractive=not plan._packColorsNormalized or not windowHovered or s.extendedActive or windowHovered()
    reads.extendedBottom=client.y+client.h
  elseif screen=="CastSpellWnd"then
    local s=state(instance,screen)
    reads.castState,reads.castFrame=s,s.drawFrame
    reads.castShown=s.castShownValid and s.castShown or nil
    reads.castInteractive=not plan._packColorsNormalized or not windowHovered or s.castHeld
      or modern_spell_drag~=nil and modern_spell_drag_frame==s.drawFrame or windowHovered()
  elseif screen=="GroupWindow" then
    local s=state(instance,screen)
    reads.groupState=s
    -- A held row still needs its release and drag handling outside the window.
    reads.groupInteractive=not plan._packColorsNormalized or not windowHovered or s.groupHeld or windowHovered()
  end
  drawReads=reads
  local ok,drawn,why=pcall(paintPrepared,screen,plan,instance,client,R)
  if reads.extendedState then
    reads.extendedState.extendedActive=reads.extendedActive
    reads.extendedState,reads.extendedInteractive,reads.extendedActive=nil,nil,nil
    reads.extendedBottom=nil
  elseif reads.castState then
    reads.castState.castHeld=reads.castHeld
    reads.castState,reads.castFrame,reads.castHeld,reads.castInteractive=nil,nil,nil,nil
  elseif reads.groupState then
    reads.groupState.groupHeld=reads.groupActive
    reads.groupState,reads.groupActive,reads.groupInteractive=nil,nil,nil
  end
  drawReads=reads.previous
  reads.screen,reads.previous,reads.buffLayout=nil,nil,nil
  clearReads(reads)
  if #readPool<4 then readPool[#readPool+1]=reads end
  if not ok then error(drawn,0)end
  return drawn,why
end
function M.Draw(screen,plan,instance,client,R)
  local ok,why=M.CanDraw(screen,plan,instance);if not ok then return false,why end
  local s=state(instance,screen);local frame=ui.GetFrameCount()
  if s.drawFrame and frame>s.drawFrame+1 then
    s.buffMenu=nil;s.controls={};s.extendedActive,s.buffHeld,s.castHeld,s.groupHeld=nil,nil,nil,nil
  end
  s.drawFrame=frame
  local prepared
  if screen=="GroupWindow"then
    local scale=client.s or 1
    prepared=M.GroupLayout(plan,instance,R,client.w/scale,client.h/scale,scale)
    if prepared.statusGroupReflow and prepared.rect.h*scale>client.h+.01 then
      ui.SetCursorScreenPos(client.x,client.y)
      local visible=ui.BeginChild("##source-group-rows",client.w,client.h,false,0)
      local x,y=ui.GetCursorScreenPos();local width,height=ui.GetContentRegionAvail()
      prepared=M.GroupLayout(plan,instance,R,width/scale,height/scale,scale)
      local virtual={x=x,y=y,w=width,h=math.max(height,prepared.rect.h*scale),s=scale}
      local success,drawn,reason=true,true,nil
      if visible then success,drawn,reason=pcall(drawPrepared,screen,prepared,instance,virtual,R)end
      if visible then ui.SetCursorScreenPos(x,y);ui.Dummy(virtual.w,virtual.h)end
      ui.EndChild()
      if not success then error(drawn,0)end
      return drawn,reason
    end
  else prepared=prepare(screen,plan,instance,R)end
  local drawn,reason=drawPrepared(screen,prepared,instance,client,R)
  if not drawn then return false,reason end
  if screen=="BuffWindow"or screen=="ShortDurationBuffWindow"or screen=="TargetWindow"then buffMenu(screen,instance)
  elseif screen=="CastSpellWnd"then spellSets(screen)end
  return true
end
function M.OwnsScroll(screen,plan,instance,R)
  if screen~="GroupWindow"then return false end
  local s=state(instance,screen)
  if s.groupOriginal==plan and s.groupOwnsScroll~=nil then return s.groupOwnsScroll end
  local prepared=M.GroupLayout(plan,instance,R)
  return prepared.statusGroupReflow==true
end
rawset(_G,"hailstone_skin_status_presenters",M)
return M
