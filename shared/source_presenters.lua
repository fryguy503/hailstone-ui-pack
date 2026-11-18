-- Source geometry and host behavior are independent: these presenters supply the
-- five main window families without replacing their inherited registration lifecycle.
local context=dofile("lib/pack_context.lua")
local previous=rawget(_G,"hailstone_skin_presenters")
if previous and previous.context==context then return previous end
local API=hs.UI
local P={context=context}
rawset(_G,"hailstone_skin_presenters",P)
local chats,toolsOpen,hotbars={},{},{}
local itemLayouts,itemLayoutScreens,itemSources={},{},setmetatable({},{__mode="k"})
local listed,lastFrame,lastName,lastAtSelect={},-1,nil,false
local libraries={}
local measured=setmetatable({},{__mode="k"})
local repaired=setmetatable({},{__mode="k"})
local function lib(name)
  if libraries[name]==nil then
    local ok,result=pcall(dofile,"lib/"..name..".lua")
    libraries[name]=ok and result or false
  end
  return libraries[name] or nil
end
local function call(module,member,...)
  local source=API[module];local fn=source and source[member]
  if type(fn)=="function" then return fn(...) end
  return nil
end
local function id(node) return tostring(node.name or node.item or "") end
local function family(screen)
  if screen=="InventoryWindow" or screen=="PlayerWindow" then return screen end
  if screen:match("^Chat%d+$") then return "ChatWindow" end
  if screen=="HotButtonWnd" or screen:match("^HotButtonWnd%d+$") then return "HotButtonWnd" end
  if screen=="ItemDisplayWindow" or screen:match("^ItemDisplayWindow#%d+$") then return "ItemDisplayWindow" end
end
local optionalInventoryLists={Merc_Slot_List="Mercenary inventory is unavailable.",Merc_Stance_List="Mercenary stances are unavailable here.",Mounts_MountList="Mount collection is unavailable.",
  Mounts_KeyRingList="Mount collection is unavailable."}
function P.Handles(screen) return type(screen)=="string" and family(screen)~=nil end
function P.Frame()
  local frame=ui.GetFrameCount()
  if frame==lastFrame then return end
  lastFrame=frame
  local state=call("session","GameState")
  local selecting=state==1 or state==2
  local name=call("character","Name");if name=="" then name=nil end
  if selecting and not lastAtSelect or name and lastName and name~=lastName then chats={};itemLayouts={};itemLayoutScreens={} end
  lastAtSelect=selecting
  if selecting then lastName=nil elseif name then lastName=name end
  listed={}
  for _,window in ipairs(call("chat","Windows") or {}) do listed["Chat"..window.slot]=window end
  for screen in pairs(chats) do if not listed[screen] then chats[screen]=nil end end
end
local inventoryActions={IW_Destroy=true,IW_Tinting=true,IW_FacePick=true,IW_AltAdvBtn=true,IW_Skills=true,
  DoneButton=true,IW_DoneButton=true,AltCurr_DisplayMissingButton=true,AltCurr_CreateItemButton=true,
  AltCurr_ReclaimButton=true,IW_CharacterView=true,Hailstone_AutoInventory=true}
local playerActions={PlayerHP=true,PlayerMana=true,PlayerFatigue=true,PetHP=true,
  GroupRoleTank=true,GroupRoleAssist=true,GroupRolePuller=true}
local hotActions={HB_PageUpButton=true,HB_PageDownButton=true,HB_PageLeftButton=true,HB_PageRightButton=true}
local function slot(node)
  local value=node.slot
  if type(value)=="number" then return value>=0 and value<=32 and value%1==0 and value or nil end
  if type(value)~="string" then return nil end
  local equip=value:match("^inventory/Equip (%d+)$")
  local bag=value:match("^inventory/General (%d+)$")
  local n=tonumber(equip or value:match("^%d+$"))
  if bag then n=tonumber(bag);n=n and n<=9 and 23+n or nil end
  return n and n>=0 and n<=32 and n%1==0 and n or nil
end
P.InventorySlot=slot
local function nativeAction(screen,node)
  local key,name=family(screen),id(node)
  if key=="InventoryWindow" then return inventoryActions[name] or name:match("^IW_Money[0-3]$")~=nil end
  if key=="PlayerWindow" then return playerActions[name]==true end
  if key=="HotButtonWnd" then return hotActions[name] or name:match("^HB_Button%d+$")~=nil end
  if key=="ItemDisplayWindow" then
    return name=="IconButton" or name=="IDW_ModButton" or name=="Hailstone_EvolvingFinalResult" or name=="IDW_Appearance_Socket_Buy_Button"
      or name:match("^IDW_Socket_Slot_[1-6]_Item$")~=nil or name=="IDW_Appearance_Socket_Item"
  end
  return false
end
function P.Enabled(screen,node)
  if not P.Handles(screen) then return end
  if family(screen)=="PlayerWindow" and id(node)=="PW_CombatStateAnim" then return true end
  if node.type=="Button" and not nativeAction(screen,node) then return false end
end
function P.Click(screen,node)
  if family(screen)=="PlayerWindow" and id(node)=="PW_CombatStateAnim" then return true end
end
function P.Events(screen,node)
  if nativeAction(screen,node) then
    if family(screen)=="PlayerWindow" then return {left=true,right=id(node)=="PlayerHP"} end
    return {left=true,right=true,phases=family(screen)=="ItemDisplayWindow"}
  end
end
function P.CanDraw(screen,plan)
  if not P.Handles(screen) or type(plan)~="table" or plan.type~="Screen" then return false,"No source presenter" end
  local key=family(screen)
  local needs=key=="ChatWindow" and {{"chat","Windows"},{"chat","Text"},{"chat","Submit"},{"chat","TakeFocus"}}
    or key=="HotButtonWnd" and {{"hotbars","Info"},{"hotbars","Click"},{"cursor","PickUp"}}
    or key=="InventoryWindow" and {{"inventory","Item"},{"inventory","ClickSlot"},{"character","Label"}}
    or {{"windows","ClickChild"},{"character","Gauge"}}
  for _,need in ipairs(needs) do
    if not API[need[1]] or type(API[need[1]][need[2]])~="function" then
      return false,"Source presenter needs "..need[1].."."..need[2]
    end
  end
  if key=="ChatWindow" and (not lib("stml") or not lib("chatlinks")) then return false,"Chat text helpers unavailable" end
  if key=="InventoryWindow" and not lib("items") then return false,"Inventory gesture helper unavailable" end
  local supported={Screen=true,Page=true,LayoutBox=true,HorizontalLayoutBox=true,VerticalLayoutBox=true,
    TileLayoutBox=true,TemplateContainer=true,Label=true,Gauge=true,Button=true,InvSlot=true,HotButton=true,
    StaticAnimation=true,StaticTintedBlendAnimation=true,StaticFrame=true,StaticText=true,StaticHeader=true,
    STMLbox=true,Editbox=true,TabBox=true,Listbox=true}
  local function check(node,depth)
    if key=="HotButtonWnd" and node.type=="SpellGem" and id(node):match("^HB_SpellGem%d+$") and not tonumber(node.eqType) then return true end
    if depth>64 or not supported[node.type] then return false,"Source control adapter unavailable: "..tostring(node.type) end
    if call("windows","ChildShown",screen,id(node))==false then return true end
    if key~="ChatWindow" and node.type=="Editbox" then return false,"Source text-entry adapter unavailable" end
    if node.type=="TabBox" then
      if key~="InventoryWindow" and key~="ItemDisplayWindow" and key~="HotButtonWnd" then return false,"Source tabs are not presentation-only" end
      if not API.windows.SetTabPage then return false,"Source tab service unavailable" end
    elseif node.type=="Listbox" then
      local name=id(node)
      if key~="InventoryWindow" then return false,"Source list adapter unavailable: "..name end
      if name=="AltCurr_PointList" then
        if not API.windows.ListClick or not API.windows.ListRow or type((call("windows","ListInfo",screen,name)))~="number" then
          return false,"Alternate-currency list unavailable"
        end
      elseif name~="EI_ItemList" and name~="ProgressionList" and not optionalInventoryLists[name] then return false,"Source list adapter unavailable: "..name end
    end
    for _,child in ipairs(node.children or {}) do local ok,why=check(child,depth+1);if not ok then return false,why end end
    return true
  end
  local ok,why=check(plan,0);if not ok then return false,why end
  return true
end
local function walk(node,fn)
  fn(node)
  for _,child in ipairs(node.children or {}) do walk(child,fn) end
end
local function slotIdentity(key,node,screen)
  if key=="InventoryWindow" and node.type=="InvSlot" then return slot(node) end
  if key=="HotButtonWnd" and node.type=="HotButton" then
    -- Legacy names such as HB1_Button1 still address the same native slot.
    -- Use the renderer's mapping so coverage and clicks agree.
    local bar,button=lib("pack_bindings").HotTarget(screen,node)
    return bar==screen and tonumber(button:match("%d+$")) or nil
  end
  if key=="ItemDisplayWindow" and (node.type=="Button"or node.type=="InvSlot") then
    local name=id(node)
    if name:match("^IDW_Socket_Slot_[1-6]_Item$") or name=="IDW_Appearance_Socket_Item"then return name end
  end
end
local function reference(plan,instance,R)
  local base=measured[plan]or plan.rect or {w=320,h=200}
  local inset=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or {left=0,right=0,top=0,bottom=0}
  return {x=0,y=0,w=math.max(1,base.w-inset.left-inset.right),h=math.max(1,base.h-inset.top-inset.bottom),s=1}
end
local function missing(screen,plan,instance,R)
  local seen,template,templates,pageOf,placed,prototypes={},nil,{},{},{},{}
  local key=family(screen)
  local base=reference(plan,instance,R)
  local function index(node,page,parent,inFlow)
    if node.type=="Page"then page=node end
    pageOf[node]=page or false
    local at=parent
    if node~=plan then
      if R and R.Geometry then at=R.Geometry(node,parent)
      else local r=node.rect or {};at={x=parent.x+(r.x or 0),y=parent.y+(r.y or 0),w=r.w or 0,h=r.h or 0,s=1}end
    end
    local n=slotIdentity(key,node,screen)
    if n~=nil then
      template=template or node;templates[n]=templates[n]or node
      if key=="ItemDisplayWindow"and not inFlow and at.w>0 and at.h>0 then
        prototypes[#prototypes+1]={key=n,box=at,page=pageOf[node]}
      end
    end
    local f=node.fields or {}
    local flow=inFlow or node.type=="TileLayoutBox"or node.type=="HorizontalLayoutBox"or node.type=="VerticalLayoutBox"
      or type(f.Layout)=="string"and f.Layout~=""
    for _,child in ipairs(node.children or{})do index(child,page,at,flow)end
  end
  index(plan,nil,base,false)
  if R and R.VisitChildren then
    R.VisitChildren(screen,plan,instance,reference(plan,instance,R),function(node,at,visible)
      local n=slotIdentity(key,node,screen)
      if n~=nil then
        seen[n]=true
        if key=="ItemDisplayWindow"then placed[#placed+1]={key=n,box=visible or at,page=pageOf[node]}end
      end
    end,{allPages=true})
  else walk(plan,function(node)local n=slotIdentity(key,node,screen);if n~=nil then seen[n]=true end end)end
  -- Some source files provide socket prototypes at one shared origin; native
  -- code originally positioned them. Separate live sockets must never share
  -- an input target. Keep distinct selectable pages independent.
  local function overlaps(records)
  for a=1,#records do for b=a+1,#records do
    local one,two=records[a],records[b]
    if one.key~=two.key and one.page==two.page then
      local p,q=one.box,two.box
      local overlap=math.max(0,math.min(p.x+p.w,q.x+q.w)-math.max(p.x,q.x))
        *math.max(0,math.min(p.y+p.h,q.y+q.h)-math.max(p.y,q.y))
      if overlap>math.min(p.w*p.h,q.w*q.h)*.5 then seen[one.key],seen[two.key]=nil,nil end
    end
  end end
  end
  overlaps(placed)
  -- Classify the authored prototype group even when only one host socket is
  -- currently shown. Hidden sibling prototypes do not become live controls.
  overlaps(prototypes)
  local out={}
  if key=="InventoryWindow" then for n=0,32 do if not seen[n] then out[#out+1]=n end end
  elseif key=="HotButtonWnd" then for n=1,12 do if not seen[n] then out[#out+1]=n end end
  elseif key=="ItemDisplayWindow" then
    for n=1,7 do
      local name=n==7 and "IDW_Appearance_Socket_Item"or "IDW_Socket_Slot_"..n.."_Item"
      if call("windows","ChildShown",screen,name)==true and not seen[name]then out[#out+1]=name end
    end
  end
  return out,template,templates
end
local function extrasHeight(screen,plan,instance,R)
  local absent,template=missing(screen,plan,instance,R)
  if #absent==0 then return 0 end
  local size=math.max(24,math.min(48,tonumber((template and template.rect or {}).h) or 40))
  local per=math.max(1,math.floor(reference(plan,instance,R).w/(size+4)))
  return math.ceil(#absent/per)*(size+4)+4
end
local function tabsHeight(screen)
  local window=listed[screen]
  return window and #(window.tabs or {})>1 and 24 or 0
end
local function transferHeight(screen)
  return family(screen)=="ItemDisplayWindow" and call("evolving","CanTransferDisplayed",screen) and 28 or 0
end
local function copy(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value) do out[k]=copy(v) end
  local meta=getmetatable(value);if type(meta)=="table"then setmetatable(out,meta)end
  return out
end
local function itemSource(plan)
  if type(plan)~="table"then return end
  local saved=itemSources[plan];if saved then return saved end
  local nodes,descriptionPage,tab={}
  local function index(node,page,owner)
    if node.type=="Page"then page=node end
    if node.type=="TabBox"then owner=node end
    nodes[id(node)]=node
    if id(node)=="ItemDescription"then descriptionPage,tab=page,owner end
    for _,child in ipairs(node.children or{})do index(child,page,owner)end
  end
  index(plan)
  if not nodes.IconButton or not nodes.IDW_ItemInfo1 or not nodes.ItemDescription or not descriptionPage then return end
  saved={nodes=nodes,page=descriptionPage,tab=tab};itemSources[plan]=saved;return saved
end
local function itemPlain(value)
  return tostring(value or""):gsub("\r",""):gsub("<[Bb][Rr]%s*/?>","\n"):gsub("</?[Pp]>","\n"):gsub("<[^>]*>","")
    :gsub("&nbsp;"," "):gsub("&lt;","<"):gsub("&gt;",">"):gsub("&quot;",'"'):gsub("&apos;","'"):gsub("&amp;","&")
end
local function itemMeasure(R,instance,node,value,s)
  local w,h
  if R and R.MeasureText then w,h=R.MeasureText(instance,node,value)
  else w,h=ui.CalcTextSize(value)end
  return math.max(0,tonumber(w)or 0)/s,math.max(1,tonumber(h)or 12)/s
end
local function itemWrap(R,instance,node,value,width,s)
  value=tostring(value or"");width=math.max(1,width)
  local lines={}
  local function append(word,line)
    local candidate=line==""and word or line.." "..word
    if itemMeasure(R,instance,node,candidate,s)<=width then return candidate end
    if line~=""then lines[#lines+1]=line end
    local part=""
    for character in word:gmatch(".[\128-\191]*")do
      if part~=""and itemMeasure(R,instance,node,part..character,s)>width then lines[#lines+1]=part;part=""end
      part=part..character
    end
    return part
  end
  for paragraph in (value.."\n"):gmatch("(.-)\n")do
    local line=""
    for word in paragraph:gmatch("%S+")do line=append(word,line)end
    lines[#lines+1]=line
  end
  local _,lineHeight=itemMeasure(R,instance,node,"Ag",s)
  return table.concat(lines,"\n"),math.max(1,#lines)*lineHeight,math.max(1,#lines)
end
local function itemAbsolute(node,x,y,w,h)
  node.rect={x=x,y=y,w=math.max(1,w),h=math.max(1,h)}
  node.anchors={explicit={left=false,right=false,top=false,bottom=false}}
  node.fields=copy(node.fields or{})
  for _,name in ipairs({"LeftAnchorOffset","RightAnchorOffset","TopAnchorOffset","BottomAnchorOffset",
    "LeftAnchorToLeft","RightAnchorToLeft","TopAnchorToTop","BottomAnchorToTop","Layout"})do node.fields[name]=nil end
  return node
end

local playerPanels = {
  ["drakah-pers-adeptus-stock"] = {height = 22},
  ["nemesis-stock"] = {height = 48, move = {PlayerHP = true, PlayerMana = true, PetHP = true}},
}
local preparedPlayers = setmetatable({}, {__mode = "k"})

local function playerPanel(screen, instance)
  local profile = instance and instance.profile
  if screen == "PlayerWindow" and profile then return playerPanels[tostring(profile.id):lower()] end
end

local function playerBody(plan, panel)
  local saved = preparedPlayers[plan]
  if saved then return saved.body, saved.gauges end

  local body, gauges = copy(plan), {}
  local function prepare(parent)
    local children = {}
    for _, node in ipairs(parent.children or {}) do
      local name = id(node)
      if node.type == "Gauge" and panel.move and panel.move[name] then
        gauges[name] = node
      else
        if node.type == "Gauge" and name == "PlayerHP" then
          -- The legacy name rectangle extends above the window. Keep the bar
          -- and its hit target at the authored track inside the body.
          local rect, fields = node.rect, node.fields or {}
          local offset = tonumber(fields.GaugeOffsetY) or 0
          itemAbsolute(node, rect.x, rect.y + offset, rect.w, rect.h - offset)
          node.fields.GaugeOffsetY = 0
          node.sourceGaugeCaption = ""
        end
        prepare(node)
        children[#children + 1] = node
      end
    end
    parent.children = children
  end
  prepare(body)
  preparedPlayers[plan] = {body = body, gauges = gauges}
  return body, gauges
end

local function drawPlayer(screen, plan, instance, box, R, panel)
  local body, gauges = playerBody(plan, panel)
  local scale = box.s or 1
  local header = math.min(panel.height * scale, math.max(0, box.h - scale))
  local inset = math.min(4 * scale, box.w / 8)
  local card = {x = box.x + inset, y = box.y, w = box.w - inset * 2, h = header, s = scale}
  local fraction, gaugeName, raw, r, g, b = call("character", "Gauge", 1)
  local name = call("character", "Name")
  if not name or name == "" then name = gaugeName or "" end
  local tint = r and {r, g, b, 1}
  if header > 0 then
    R.PaintHealthBox(instance, card, (raw == nil or raw >= 0) and fraction or nil, tint)
    local caption = {type = "Label", name = "Hailstone_SelfName", font = gauges.PlayerHP and gauges.PlayerHP.font or 3,
      fields = {Style_HCenter = true, Style_VCenter = true}}
    local title = {x = card.x + inset, y = card.y, w = card.w - inset * 2, h = math.min(20 * scale, header), s = scale}
    ui.PushClipRect(title.x, title.y, title.x + title.w, title.y + title.h, true)
    local ok, errorText = pcall(R.PaintControl, screen, caption, title, instance,
      {caption = name:match("^[^\r\n]*"), tint = instance.palette.text})
    ui.PopClipRect()
    if not ok then error(errorText, 0) end
    if panel.move then
      local rows, y = {}, 20 * scale
      for _, key in ipairs({"PlayerHP", "PlayerMana", "PetHP"}) do
        local node = gauges[key]
        if node and call("windows", "ChildShown", screen, key) ~= false and y + 7 * scale <= header then
          local row = itemAbsolute(copy(node), inset / scale, y / scale, title.w / scale, 7)
          row.fields.GaugeOffsetX, row.fields.GaugeOffsetY = 0, 0
          row.sourceGaugeCaption = ""
          rows[#rows + 1] = row
          y = y + 9 * scale
        end
      end
      R.DrawChildren(screen, {children = rows}, instance, card)
    end
  end
  return R.Draw(screen, body, instance, {x = box.x, y = box.y + header, w = box.w,
    h = math.max(1, box.h - header), s = scale}, P)
end
local function managedItemNode(name)
  return name=="IconButton"or name=="ItemDescription"or name=="IDW_ModButton"or name=="IDW_ModButtonLabel"
    or name=="Hailstone_EvolvingFinalResult"or name:match("^IDW_ItemInfo%d+$")or name:match("^IDW_Row%d+Col%d+[A-Za-z]+$")
    or name:match("^IDW_Heroic%d+$")or name:match("^IDW_Socket_Slot_[1-6]_Screen$")or name=="IDW_Appearance_Socket_Screen"
    or name:match("^IDW_ClassTitle%d*$")or name:match("^IDW_RaceTitle%d*$")or name=="IDW_DeityTitle"
    or name=="IDW_CollectedLabel"or name=="IDW_ConvertButton"or name=="IDW_ConvertButtonLabel"
end
-- These source nodes are runtime-positioned prototypes: the original item
-- builder placed info lines, shared stat/value boxes and socket rows after it
-- knew the item. Reconstruct that responsibility using the selected skin's
-- fonts, icon size, margins, column proportions and control artwork.
function P.ItemLayout(screen,plan,instance,R,width,height,s)
  if type(screen)~="string"or family(screen)~="ItemDisplayWindow"or not API.windows or type(API.windows.Text)~="function"then return plan end
  local source=itemSource(plan);if not source then return plan end
  s=math.max(.01,tonumber(s)or 1);width=math.max(1,tonumber(width)or 400);height=math.max(1,tonumber(height)or 200)
  local live,signature={}, {tostring(width),tostring(height),tostring(s),tostring(call("settings","Option","font_face"))}
  local function read(name)
    if live[name]then return live[name]end
    local shown=call("windows","ChildShown",screen,name)
    local value,supplied=call("windows","Text",screen,name)
    local record={shown=shown~=false,text=tostring(value or""),supplied=supplied}
    live[name]=record;signature[#signature+1]=name..":"..tostring(shown)..":"..#record.text..":"..record.text
    return record
  end
  local infos,cells,heroics,sockets={},{},{},{}
  for n=1,13 do local name="IDW_ItemInfo"..n;local value=read(name)
    if value.shown and value.text~=""then infos[#infos+1]={name=name,text=value.text}end
  end
  for row=1,26 do cells[row]={}
    for col=1,3 do
      local prefix="IDW_Row"..row.."Col"..col
      local label,value=read(prefix.."Stat"),read(prefix.."Value")
      if label.shown and label.text~=""then
        local x,y,w=call("windows","ChildRect",screen,prefix.."Stat")
        cells[row][col]={label=prefix.."Stat",value=prefix.."Value",text=label.text,valueText=value.shown and value.text or"",x=x,y=y,w=w}
      end
    end
  end
  for n=1,13 do local name="IDW_Heroic"..n;local value=read(name)
    if value.shown and value.text~=""then
      local x,y=call("windows","ChildRect",screen,name)
      signature[#signature+1]=tostring(x)..":"..tostring(y)
      local owner,distance
      if x and y then for row=1,26 do for col=1,3 do local cell=cells[row][col]
        if cell and cell.x and cell.y and math.abs(y-cell.y)<1 then
          local delta=math.abs(x-cell.x-(cell.w or 0))
          if not distance or delta<distance then owner,distance=cell,delta end
        end
      end end end
      local entry={name=name,text=value.text};heroics[#heroics+1]=entry
      if owner then owner.heroic=entry;entry.assigned=true end
    end
  end
  for n=1,7 do
    local prefix=n==7 and"IDW_Appearance_Socket"or"IDW_Socket_Slot_"..n
    local screenShown=call("windows","ChildShown",screen,prefix.."_Screen")
    signature[#signature+1]=prefix..":"..tostring(screenShown)
    -- The screen is authoritative. An item child may retain its default shown
    -- state while its parent socket screen is hidden by the live model.
    if screenShown==true or screenShown==nil and call("windows","ChildShown",screen,prefix.."_Item")==true then
      local description=read(prefix.."_Description")
      local buy=n==7 and call("windows","ChildShown",screen,prefix.."_Buy_Button")==true
      local buyText=buy and read(prefix.."_Buy_Button").text or""
      signature[#signature+1]=tostring(buy)
      sockets[#sockets+1]={prefix=prefix,text=description.text,appearance=n==7,buy=buy,buyText=buyText}
    end
  end
  local modifier,description,final=read("IDW_ModButtonLabel"),read("ItemDescription"),read("Hailstone_EvolvingFinalResult")
  local fonts={}
  for _,node in pairs(source.nodes)do if not fonts[node.font or 3]then
    fonts[node.font or 3]=true;local fw,fh=itemMeasure(R,instance,node,"Wg",s)
    signature[#signature+1]=tostring(node.font or 3)..":"..tostring(fw)..":"..tostring(fh)
  end end
  local key=table.concat(signature,"\31");local cache=itemLayouts[screen]
  for index,name in ipairs(itemLayoutScreens)do if name==screen then table.remove(itemLayoutScreens,index);break end end
  table.insert(itemLayoutScreens,1,screen)
  -- Retain current and recent display instances without keeping every closed
  -- inspect window alive when a host allocates monotonically increasing ids.
  if #itemLayoutScreens>12 then itemLayouts[table.remove(itemLayoutScreens)]=nil end
  if not cache or cache.source~=plan or cache.instance~=instance then
    cache={source=plan,instance=instance,entries={}};itemLayouts[screen]=cache
  end
  for index,entry in ipairs(cache.entries)do if entry.key==key then
    table.remove(cache.entries,index);table.insert(cache.entries,1,entry)
    return entry.plan,entry.height
  end end
  local prepared=copy(plan);local nodes={};walk(prepared,function(node)nodes[id(node)]=node end)
  local page=nodes[id(source.page)];local tab=source.tab and nodes[id(source.tab)]
  local function prune(node)
    local children={}
    for _,child in ipairs(node.children or{})do
      if not managedItemNode(id(child))then prune(child);children[#children+1]=child end
    end
    node.children=children
  end
  prune(page)
  local function take(name,fallback,kind)
    local node=nodes[name]or copy(fallback or source.nodes.IDW_ItemInfo1)
    node.name=name;node.item=name;node.children={};node.sourceReplaced=nil
    if kind then node.type=kind end
    return node
  end
  local tabBox=tab and R and R.Geometry and R.Geometry(source.tab,{x=0,y=0,w=width,h=height,s=1})or{x=0,y=0}
  local left,top=math.max(0,tabBox.x or 0),math.max(0,tabBox.y or 0)
  left=math.min(left,math.max(0,(width-1)/2))
  local pageWidth=math.max(1,width-2*left)
  local tabHeight=tab and tonumber((tab.fields or{}).TabHeight)or 22
  local sourceIcon=source.nodes.IconButton
  local icon=R and R.Geometry and R.Geometry(sourceIcon,{x=0,y=0,w=pageWidth,h=height,s=1})or sourceIcon.rect or{}
  local first=source.nodes.IDW_ItemInfo1
  local margin=math.max(0,math.min(10,tonumber((source.nodes.IDW_Row1Col1Stat or first).rect.x)or 10,pageWidth/8))
  local gap=math.max(2,math.min(4,(tonumber((first.rect or{}).h)or 20)/5))
  local iconX=math.min(math.max(margin,icon.x or margin),math.max(0,pageWidth-1))
  local iconSize=math.max(1,math.min(math.max(20,math.min(icon.w or 44,icon.h or 44)),pageWidth-iconX-margin))
  local headerY=math.max(0,(first.rect or{}).y or 0)
  local iconY=math.max(headerY,icon.y or headerY)
  local textX=math.max(iconX+iconSize+gap,(first.rect or{}).x or 60)
  if pageWidth-margin-textX<40 then textX=margin;headerY=iconY+iconSize+gap end
  local textWidth=math.max(1,pageWidth-margin-textX)
  local iconNode=take("IconButton",sourceIcon,"Button")
  page.children[#page.children+1]=itemAbsolute(iconNode,iconX,iconY,iconSize,iconSize)
  local y=headerY
  local function label(name,value,x,atY,w,fallback)
    local node=take(name,fallback,"Label")
    local wrapped,h=itemWrap(R,instance,node,value,w,s)
    node.sourceItemText=wrapped;itemAbsolute(node,x,atY,w,h)
    page.children[#page.children+1]=node;return h,node
  end
  for _,entry in ipairs(infos)do
    local h=label(entry.name,entry.text,textX,y,textWidth,first);y=y+h+gap
  end
  y=math.max(y,iconY+iconSize)+gap
  local available=math.max(1,pageWidth-2*margin)
  local per=math.max(1,math.min(3,math.floor(available/100)))
  local columnGap
  for col=1,2 do
    local one,two=source.nodes["IDW_Row1Col"..col.."Stat"],source.nodes["IDW_Row1Col"..(col+1).."Stat"]
    if one and two then
      local authored=(two.rect.x or 0)-(one.rect.x or 0)-(one.rect.w or 0)
      if authored>0 then columnGap=math.min(columnGap or authored,authored)end
    end
  end
  columnGap=math.max(gap,math.min(columnGap or gap,math.max(gap,(available-per*85)/math.max(1,per-1))))
  for band=1,3,per do
    local last=math.min(3,band+per-1);local columns,total={},0
    for col=band,last do
      local sourceStat=source.nodes["IDW_Row1Col"..col.."Stat"]or first
      local weight=math.max(1,tonumber((sourceStat.rect or{}).w)or 100)
      columns[col]={weight=weight};total=total+weight
    end
    local hasBand=false;for row=1,26 do for col=band,last do if cells[row][col]then hasBand=true end end end
    if hasBand then
      local lastRow
      for row=1,26 do
        local any=false;for col=band,last do if cells[row][col]then any=true end end
        if any then
          if lastRow and row>lastRow+1 then y=y+gap*2 end
          local rowHeight,x=0,margin
          for col=band,last do
            local columnWidth=(available-columnGap*(last-band))*columns[col].weight/total
            local cell=cells[row][col]
            if cell then
              local stat=source.nodes[cell.label]or first
              local valueNode=source.nodes[cell.value]or stat
              local heroic=cell.heroic
              local heroicWidth=heroic and math.min(columnWidth*.3,math.max(14,itemMeasure(R,instance,source.nodes[heroic.name]or stat,heroic.text,s)))or 0
              local valueWidth=math.min(columnWidth*.45,math.max(22,itemMeasure(R,instance,valueNode,cell.valueText,s)))
              if columnWidth<85 then
                local h=label(cell.label,cell.text,x,y,columnWidth,stat)
                local vh=label(cell.value,cell.valueText,x,y+h+gap,math.max(1,columnWidth-heroicWidth-gap),valueNode)
                local hh=heroic and label(heroic.name,heroic.text,x+columnWidth-heroicWidth,y+h+gap,heroicWidth,stat)or 0
                rowHeight=math.max(rowHeight,h+gap+math.max(vh,hh))
              else
                local labelWidth=math.max(1,columnWidth-valueWidth-heroicWidth-gap*(heroic and 2 or 1))
                local h=label(cell.label,cell.text,x,y,labelWidth,stat)
                local vh=label(cell.value,cell.valueText,x+labelWidth+gap,y,valueWidth,valueNode)
                local hh=heroic and label(heroic.name,heroic.text,x+columnWidth-heroicWidth,y,heroicWidth,stat)or 0
                rowHeight=math.max(rowHeight,h,vh,hh)
              end
            end
            x=x+columnWidth+columnGap
          end
          y=y+rowHeight+gap;lastRow=row
        end
      end
      y=y+gap
    end
  end
  for _,entry in ipairs(heroics)do if not entry.assigned then y=y+label(entry.name,entry.text,margin,y,available,first)+gap end end
  if modifier.shown and modifier.text~=""then
    local button=take("IDW_ModButton",{type="Button",font=first.font,fields={}},"Button")
    local size=math.max(12,math.min(20,(button.rect or{}).h or 15))
    page.children[#page.children+1]=itemAbsolute(button,margin,y,size,size)
    local h=label("IDW_ModButtonLabel",modifier.text,margin+size+gap,y,math.max(1,available-size-gap),first)
    y=y+math.max(size,h)+gap*2
  end
  for _,entry in ipairs(sockets)do
    local prefix=entry.prefix
    local group=take(prefix.."_Screen",{type="Screen",font=first.font,fields={}},"Screen")
    local button=take(prefix.."_Item",source.nodes.IDW_Socket_Slot_1_Item or sourceIcon,"Button")
    local details=take(prefix.."_Description",source.nodes.IDW_Socket_Slot_1_Description or source.nodes.ItemDescription,"STMLbox")
    local size=math.max(20,math.min(48,(button.rect or{}).h or(entry.appearance and 40 or 20),available))
    if not source.nodes[prefix.."_Item"]and not source.nodes.IDW_Socket_Slot_1_Item then
      -- Older skins have no socket prototype. Their item-icon placeholder is
      -- not an empty augment slot; use selected button chrome and live art.
      button.art={};button.fields=copy(button.fields or{})
      button.fields.ButtonDrawTemplate=nil
      button.fields.DecalSize={CX=size,CY=size};button.fields.DecalOffset={X=0,Y=0}
    end
    local descriptionX=size+gap*2
    local buyWidth=entry.buy and math.min(100,math.max(64,itemMeasure(R,instance,first,entry.buyText~=""and entry.buyText or"Buy Now",s)+12))or 0
    local buyBelow=entry.buy and available-descriptionX-buyWidth-gap<70
    local descriptionWidth=math.max(1,available-descriptionX-(entry.buy and not buyBelow and buyWidth+gap or 0))
    local _,descriptionHeight,descriptionLines=itemWrap(R,instance,details,itemPlain(entry.text),descriptionWidth,s)
    local lineSpacing=4*(tonumber(ui.GetIO().uiScale)or 1)/s
    local rowHeight=math.max(size,tonumber((group.rect or{}).h)or 0,descriptionHeight+descriptionLines*lineSpacing+gap*2)
    group.children={itemAbsolute(button,0,0,size,size),itemAbsolute(details,descriptionX,0,descriptionWidth,rowHeight)}
    if entry.buy then
      local buy=take(prefix.."_Buy_Button",{type="Button",font=first.font,fields={Style_HCenter=true,Style_VCenter=true}},"Button")
      local caption=entry.buyText~=""and entry.buyText or buy.text~=""and buy.text or"Buy Now"
      local buyHeight
      buy.sourceItemCaption,buyHeight=itemWrap(R,instance,buy,caption,buyBelow and available or buyWidth,s)
      buyHeight=math.max(22,buyHeight+8)
      local buyY=buyBelow and rowHeight+gap or 0
      group.children[#group.children+1]=itemAbsolute(buy,buyBelow and 0 or available-buyWidth,buyY,buyBelow and available or buyWidth,buyHeight)
      rowHeight=math.max(rowHeight,buyY+buyHeight)
    end
    page.children[#page.children+1]=itemAbsolute(group,margin,y,available,rowHeight)
    y=y+rowHeight+gap*2
  end
  if final.shown and final.text~=""then
    local button=take("Hailstone_EvolvingFinalResult",{type="Button",font=first.font,fields={Style_HCenter=true,Style_VCenter=true}},"Button")
    local h;button.sourceItemCaption,h=itemWrap(R,instance,button,final.text,available,s);h=math.max(24,h+8)
    page.children[#page.children+1]=itemAbsolute(button,margin,y,available,h);y=y+h+gap
  end
  local descriptionHeight=math.max(80,height-top-tabHeight-y-gap)
  local body=take("ItemDescription",source.nodes.ItemDescription,"STMLbox")
  page.children[#page.children+1]=itemAbsolute(body,margin,y,available,descriptionHeight)
  local fullHeight=top+tabHeight+y+descriptionHeight+gap
  itemAbsolute(page,0,0,pageWidth,fullHeight-top-tabHeight)
  if tab then itemAbsolute(tab,left,top,pageWidth,fullHeight-top)end
  prepared.rect={x=0,y=0,w=width,h=fullHeight};prepared.sourceItemLayout=true
  table.insert(cache.entries,1,{key=key,plan=prepared,height=fullHeight})
  if #cache.entries>4 then table.remove(cache.entries)end
  return prepared,fullHeight
end
function P.OwnsScroll(screen,plan)
  return type(screen)=="string"and family(screen)=="ItemDisplayWindow"and itemSource(plan)~=nil
    and API.windows and type(API.windows.Text)=="function"or false
end
local function hotPlan(screen,plan,instance,R)
  if family(screen)~="HotButtonWnd" then return plan end
  local bar=tonumber(screen:match("(%d+)$")) or 1
  local percent=math.max(40,math.min(175,tonumber(call("hotbars","Setting",bar,"PercentSize")) or 100))/100
  local spinner=call("hotbars","Setting",bar,"ShowSpinner")~=false
  local columns=tonumber(ui.GetSetting("hud.perRow."..screen))
  if columns then columns=math.max(1,math.min(12,math.floor(columns))) end
  local key=tostring(percent)..":"..tostring(spinner)..":"..tostring(columns)
  local record=hotbars[screen]
  if record and record.source==plan and record.key==key then return record.plan end
  record={source=plan,key=key,spinner=spinner,plan=copy(plan)};hotbars[screen]=record
  local tile,first,templates={},nil,{}
  walk(record.plan,function(node)
    if node.type=="Button" then
      local n=tonumber(id(node):match("^HB_Button(%d+)$"))
      if n and n>=1 and n<=12 then node.type="HotButton" end
    end
    if node.type=="TileLayoutBox" and id(node)=="HB_HotButtonLayout" then tile=node end
    if node.type=="HotButton" then first=first or node end
    if id(node):match("^HB_.*BarTemplate$") then templates[id(node)]=node end
  end)
  if not tile.type then tile=nil end
  local insets=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1) or {left=0,right=0,top=0,bottom=0}
  if columns and tile and first then
    local rows=math.ceil(12/columns)
    record.vertical=rows>columns
    local template=templates[not spinner and "HB_NoSpinnerBarTemplate"
      or record.vertical and "HB_VerticalBarTemplate" or "HB_HorizontalBarTemplate"]
    if template then tile.anchors=copy(template.anchors);tile.fields=copy(tile.fields)
      for _,name in ipairs({"TopAnchorOffset","BottomAnchorOffset","LeftAnchorOffset","RightAnchorOffset"}) do
        tile.fields[name]=(template.fields or {})[name]
      end
    end
    local f=tile.fields or {};f.HorizontalFirst=true;tile.fields=f
    local gap=tonumber(f.Spacing) or 5;local secondary=tonumber(f.SecondarySpacing) or 5
    local sw,sh=first.rect.w,first.rect.h
    local a=tile.anchors or {}
    local left,right=tonumber(a.left) or 0,tonumber(a.right) or 0
    local top,bottom=tonumber(a.top) or 0,tonumber(a.bottom) or 0
    record.plan.rect.w=insets.left+insets.right+left+right+columns*sw+(columns-1)*gap
    record.plan.rect.h=insets.top+insets.bottom+top+bottom+rows*sh+(rows-1)*secondary
  else
    record.vertical=plan.rect.h>plan.rect.w
    if tile and first and R and R.Geometry then
      local at=R.Geometry(tile,{x=0,y=0,w=plan.rect.w-insets.left-insets.right,
        h=plan.rect.h-insets.top-insets.bottom,s=1})
      local gap=tonumber((tile.fields or {}).Spacing) or 5
      record.columns=math.max(1,math.min(12,math.floor((at.w+gap)/(first.rect.w+gap))))
    end
  end
  record.columns=columns or record.columns or (record.vertical and 1 or 12)
  -- PercentSize is a host setting for the authored control grid, not a switch
  -- back to the inherited presenter's button dimensions or arrangement.
  if percent~=1 then
    walk(record.plan,function(node)
      if node~=record.plan then
        for _,name in ipairs({"x","y","w","h"}) do if node.rect and node.rect[name] then node.rect[name]=node.rect[name]*percent end end
        for _,name in ipairs({"left","right","top","bottom"}) do if node.anchors and node.anchors[name] then node.anchors[name]=node.anchors[name]*percent end end
        for _,name in ipairs({"Spacing","SecondarySpacing","PaddingLeft","PaddingRight","PaddingTop","PaddingBottom",
          "TopAnchorOffset","BottomAnchorOffset","LeftAnchorOffset","RightAnchorOffset"}) do
          if node.fields and tonumber(node.fields[name]) then node.fields[name]=node.fields[name]*percent end
        end
      end
    end)
    record.plan.rect.w=insets.left+insets.right+math.max(1,record.plan.rect.w-insets.left-insets.right)*percent
    record.plan.rect.h=insets.top+insets.bottom+math.max(1,record.plan.rect.h-insets.top-insets.bottom)*percent
  end
  return record.plan
end
function P.Shown(screen,node)
  if node.sourceReplaced then return false end
  if family(screen)=="InventoryWindow" and optionalInventoryLists[id(node)] then
    return call("windows","ListInfo",screen,id(node))~=nil
  end
  local record=hotbars[screen]
  if not record then return end
  local name=id(node)
  if name=="HB_InvSlot" or name:match("^HB_InvSlot%d+$") or name:match("^HB_SpellGem%d+$") then return false end
  if name=="HB_VerticalBarPageButtons" then return record.spinner and record.vertical end
  if name=="HB_HorizontalBarPageButtons" then return record.spinner and not record.vertical end
  if name:match("^HB_.*BarTemplate$") then return false end
end
function P.Resize(screen,plan,instance,R,w,h)
  if family(screen)~="HotButtonWnd" then return end
  local prepared=hotPlan(screen,plan,instance,R)
  local first,tile
  walk(prepared,function(node)
    if node.type=="HotButton" then first=first or node end
    if node.type=="TileLayoutBox" and id(node)=="HB_HotButtonLayout" then tile=node end
  end)
  if not first or not tile then return end
  local gap=tonumber((tile.fields or {}).Spacing) or 5
  local secondary=tonumber((tile.fields or {}).SecondarySpacing) or 5
  local current=hotbars[screen].columns
  local columns
  if math.abs(w-prepared.rect.w)>=math.abs(h-prepared.rect.h) then
    local inset=prepared.rect.w-(current*(first.rect.w+gap)-gap)
    columns=math.floor((w-inset+gap)/(first.rect.w+gap)+.5)
  else
    local insets=R.ChromeInsets(plan,instance,1)
    local rows=math.max(1,math.floor((h-insets.top-insets.bottom)/(first.rect.h+secondary)+.5))
    columns=math.ceil(12/rows)
  end
  ui.SetSetting("hud.perRow."..screen,math.max(1,math.min(12,columns)))
end
function P.Size(screen,plan,instance,R)
  P.Frame()
  plan=hotPlan(screen,plan,instance,R)
  local w,h=(plan.rect or {}).w or 320,(plan.rect or {}).h or 200
  if family(screen)=="ItemDisplayWindow"and itemSource(plan)and API.windows and API.windows.Text then
    if w<=0 then
      w=320
      for col=1,3 do local node=itemSource(plan).nodes["IDW_Row1Col"..col.."Stat"]
        if node then w=math.max(w,(node.rect.x or 0)+(node.rect.w or 0)+20)end
      end
    end
    h=math.max(230,h)
    local inset=R and R.ChromeInsets and R.ChromeInsets(plan,instance,1)or{left=0,right=0,top=0,bottom=0}
    local io=ui.GetIO();local scale=math.max(.01,tonumber(io.uiScale)or 1)
    local _,natural=P.ItemLayout(screen,plan,instance,R,math.max(1,w-inset.left-inset.right),
      math.max(1,h-inset.top-inset.bottom),scale)
    if natural then
      local limit=math.max(120,(tonumber(io.height)or 1080)/scale*.8)
      return w,math.min(limit,math.max(h,natural+inset.top+inset.bottom+transferHeight(screen)))
    end
  end
  if R and R.MeasureChildren and R.ChromeInsets then
    local inset=R.ChromeInsets(plan,instance,1)
    local key=table.concat({inset.left,inset.right,inset.top,inset.bottom},":")
    local saved=measured[plan]
    if not saved or saved.key~=key then
      local cw,ch=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=math.max(1,w-inset.left-inset.right),
        h=math.max(1,h-inset.top-inset.bottom),s=1})
      -- Absolute controls parked outside a source window stay clipped. Only
      -- compensate its chrome here; generated host extras are added explicitly.
      saved={key=key,w=math.max(w,math.min(cw,w)+inset.left+inset.right),
        h=math.max(h,math.min(ch,h)+inset.top+inset.bottom)}
      measured[plan]=saved
    end
    w,h=saved.w,saved.h
  end
  local panel = playerPanel(screen, instance)
  return w,h+extrasHeight(screen,plan,instance,R)+tabsHeight(screen)+transferHeight(screen)+(panel and panel.height or 0)
end
local function chat(screen)
  local value=chats[screen]
  if not value then
    local index=tonumber(screen:match("^Chat(%d+)$"))
    value={slot=index,input="",links={},version=-1,lines={},follow=true}
    value.onLink=function(link) call("chat","Link",index,link[1],link[2]) end
    value.inputOpts={history=function(older)
      local text=call("chat","History",index,older)
      if text~=nil then value.links={};return lib("chatlinks").Collapse(value.links,text,0) end
    end,tab=function(text,back)
      local result=call("chat","CycleReply",lib("chatlinks").Expand(value.links,text),back)
      if result~=nil then value.links={} end
      return result
    end}
    chats[screen]=value
  end
  return value
end
local function chatOutput(screen,node,box)
  local c,stml=chat(screen),lib("stml")
  local window=listed[screen]
  if window and c.tab~=window.tab then c.tab=window.tab;c.version=-1;c.follow=true end
  local version,lines,reset,count=call("chat","Text",c.slot,c.version,true,ui.GetSetting("chat.timestamps")=="1",true)
  if version~=c.version and lines then
    c.version=version
    if reset then stml.UpdateLines(c,lines,{1,1,1,1}) else stml.AppendLines(c,lines,count,{1,1,1,1}) end
  end
  local font=call("chat","Info",c.slot) or 3
  ui.SetCursorScreenPos(box.x,box.y);ui.PushChatFont(math.max(0,math.min(10,font)))
  ui.BeginChild("##source-chat-output",box.w,box.h,false,0)
  local bottom=ui.GetScrollY()>=ui.GetScrollMaxY()-2
  local width,height=ui.GetContentRegionAvail();local pw,ph=ui.CalcTextSize("Wg il")
  stml.DrawLines(c,width,height,tostring(width)..":"..tostring(pw*4096+ph),c.onLink)
  local page=call("chat","Page",c.slot)
  if page then ui.SetScrollY(math.max(0,ui.GetScrollY()+page*math.max(1,height-8*(box.s or 1))))
  elseif bottom or c.follow then ui.SetScrollHereY(1) end
  c.follow=false
  ui.EndChild();ui.PopFont()
end
local function chatInput(screen,node,box)
  local c,links=chat(screen),lib("chatlinks")
  local taken,replace=call("chat","TakeFocus",c.slot,links.Expand(c.links,c.input))
  if taken then
    if replace then c.input="";c.links={} end
    c.input=c.input..links.Collapse(c.links,taken,#c.input);c.focus=30
  end
  ui.SetCursorScreenPos(box.x,box.y);ui.SetNextItemWidth(box.w)
  if (c.focus or 0)>0 and not ui.IsMouseDown(ui.Mouse.Left) then ui.SetKeyboardFocusHere();c.focus=c.focus-1 end
  local flags=(ui.InputTextFlags or {}).EnterReturnsTrue or 0
  c.inputOpts.moveToEnd=(c.focus or 0)>0
  local text,enter=ui.InputText("##source-chat-input",c.input,2048,flags,c.inputOpts)
  if ui.IsItemActive() then c.focus=0 end
  c.input=text
  if text=="" then c.links={} end
  if enter then
    local expanded,why=links.ForSubmit(c.links,text)
    if expanded then
      if expanded~="" then call("chat","Submit",c.slot,expanded) end
      c.input="";c.links={};c.follow=true;c.error=nil
    else c.error=why end
  end
  if c.error then ui.SetTooltip(c.error) end
end

local function drawChatTabs(window, box, instance, R)
  local s = box.s or 1
  local gap, height = 3 * s, 20 * s
  local labels, widths = {}, {}
  local total = 0
  for index, tab in ipairs(window.tabs) do
    local title = tab.title
    if not title or title == "" then title = "Chat " .. index end
    labels[index] = (tab.unread and "* " or "") .. title
    widths[index] = ui.CalcTextSize(labels[index]) + 10 * s
    total = total + widths[index] + (index > 1 and gap or 0)
  end

  if total > box.w then
    local token = R.PushStyle(instance)
    ui.SetCursorScreenPos(box.x, box.y)
    ui.SetNextItemWidth(box.w)
    if ui.BeginCombo("##source-chat-tabs", labels[window.tab] or labels[1]) then
      for index, label in ipairs(labels) do
        local selected = index == window.tab
        if ui.Selectable(label .. "##source-tab" .. index, selected) and not selected then
          call("chat", "SelectTab", window.slot, index)
        end
        if selected then ui.SetItemDefaultFocus() end
      end
      ui.EndCombo()
    end
    R.PopStyle(token)
    return
  end

  local x = box.x
  for index, label in ipairs(labels) do
    local width = widths[index]
    ui.SetCursorScreenPos(x, box.y)
    if ui.Button(label .. "##source-tab" .. index, width, height) and index ~= window.tab then
      call("chat", "SelectTab", window.slot, index)
    end
    if index == window.tab then
      local accent = instance.palette.accent or instance.palette.text
      if accent then
        local y = box.y + height - 2 * s
        ui.DrawLine(x + 3 * s, y, x + width - 3 * s, y, accent[1], accent[2], accent[3], accent[4] or 1, s)
      end
    end
    x = x + width + gap
  end
end

function P.DrawControl(screen,node,box,instance,R)
  local key,name=family(screen),id(node)
  if key=="ItemDisplayWindow"and node.sourceItemCaption~=nil and R.DrawButton then
    R.DrawButton(screen,node,box,instance,node.sourceItemCaption);return true
  elseif key=="ItemDisplayWindow"and node.sourceItemText~=nil and R.PaintText then
    R.PaintText(screen,node,box,instance,node.sourceItemText);return true
  elseif key=="ChatWindow" then
    if name=="CWChatInput" or node.type=="Editbox" then chatInput(screen,node,box);return true end
    if name=="CWChatOutput" or node.type=="STMLbox" then chatOutput(screen,node,box);return true end
  elseif key=="InventoryWindow" then
    if node.type=="Listbox" and (name=="EI_ItemList" or name=="ProgressionList") then
      ui.SetCursorScreenPos(box.x,box.y)
      ui.TextDisabled(name=="EI_ItemList" and "Equipment sets are unavailable." or "Progression information is unavailable.")
      return true
    end
    local n=node.type=="InvSlot" and slot(node)
    if n then
      local items=lib("items")
      local previous=instance.sourceSlotNode
      instance.sourceSlotNode=node
      local ok,why=pcall(items.InvSlot,n,nil,box.x,box.y,math.min(box.w,box.h),box.s or 1,nil)
      instance.sourceSlotNode=previous
      if not ok then error(why,0) end
      return true
    end
    if name=="IW_CharacterView" then
      R.PaintControl(screen,node,box,instance)
      -- The current host has no inventory actor texture. Keep the real doll-drop
      -- action; never substitute the unrelated item-preview actor or a fake portrait.
      ui.SetCursorScreenPos(box.x,box.y)
      if ui.InvisibleButton("##source-doll",math.max(1,box.w),math.max(1,box.h)) then call("windows","ClickChild",screen,name,"left") end
      if ui.IsItemHovered() then ui.SetTooltip("Drop held equipment here. Character preview is unavailable in this client.") end
      return true
    end
  end
  return false
end
local function extraSlots(screen,plan,instance,box,R,absent,template,templates)
  if #absent==0 then return end
  local s=box.s or 1
  local size=math.max(24,math.min(48,tonumber((template and template.rect or {}).h) or 40))
  local per=math.max(1,math.floor(box.w/((size+4)*s)))
  for index,n in ipairs(absent) do
    local node={};for k,v in pairs(templates[n]or template or {}) do node[k]=v end
    local key=family(screen)
    node.name=key=="InventoryWindow" and "InvSlot"..n or key=="HotButtonWnd"and "HB_Button"..n or n
    node.type=key=="InventoryWindow" and "InvSlot" or key=="HotButtonWnd"and "HotButton"or "Button"
    if key=="HotButtonWnd"then node.eqType=nil end -- the new slot uses its own canonical name
    node.slot=key=="InventoryWindow"and n or nil;node.children={};node.rect={x=0,y=0,w=size,h=size};node.anchors={};node.fields={}
    local at={x=box.x+((index-1)%per)*(size+4)*s,y=box.y+((index-1)//per)*(size+4)*s,w=size*s,h=size*s,s=s}
    if not P.DrawControl(screen,node,at,instance,R) then
      R.DrawChildren(screen,{children={node}},instance,{x=at.x,y=at.y,w=at.w,h=at.h,s=s})
    end
  end
end
local function replaceUnreachable(screen,plan,absent)
  if #absent==0 then return plan end
  local key=table.concat(absent,",")
  local cached=repaired[plan]
  if cached and cached.key==key then return cached.plan end
  local identities={};for _,n in ipairs(absent)do identities[n]=true end
  local function clone(node)
    local out={};for k,v in pairs(node)do out[k]=v end
    out.children={};for _,child in ipairs(node.children or {})do out.children[#out.children+1]=clone(child)end
    if identities[slotIdentity(family(screen),node,screen)]then out.sourceReplaced=true end
    return out
  end
  local result=clone(plan);repaired[plan]={key=key,plan=result};return result
end
function P.Draw(screen,plan,instance,box,R)
  P.Frame()
  plan=hotPlan(screen,plan,instance,R)
  local panel = playerPanel(screen, instance)
  if panel and R.PaintHealthBox then return drawPlayer(screen, plan, instance, box, R, panel) end
  if family(screen)=="ItemDisplayWindow"then
    local s=box.s or 1;local transfer=transferHeight(screen)*s
    local availableHeight=math.max(1,box.h-transfer)
    local prepared,extent=P.ItemLayout(screen,plan,instance,R,box.w/s,availableHeight/s,s)
    if prepared.sourceItemLayout then
      local child=extent*s>availableHeight+.01
      local content={x=box.x,y=box.y,w=box.w,h=math.max(availableHeight,extent*s),s=s}
      local visible=true
      if child then
        ui.SetCursorScreenPos(box.x,box.y)
        visible=ui.BeginChild("##source-item-layout",box.w,availableHeight,false,0)
        local x,y=ui.GetCursorScreenPos();local w,h=ui.GetContentRegionAvail()
        prepared,extent=P.ItemLayout(screen,plan,instance,R,w/s,h/s,s)
        content={x=x,y=y,w=w,h=math.max(h,extent*s),s=s}
      end
      local ok,drawn,why=true,true,nil
      if visible then ok,drawn,why=pcall(R.Draw,screen,prepared,instance,content,P)end
      if child then
        if visible then ui.SetCursorScreenPos(content.x,content.y);ui.Dummy(content.w,content.h)end
        ui.EndChild()
      end
      if not ok then error(drawn,0)end
      if drawn==false then return false,why end
      if transfer>0 then
        ui.SetCursorScreenPos(box.x,box.y+box.h-transfer)
        if ui.Button("Transfer evolving experience##source-transfer",box.w,math.max(1,transfer-4*s))then
          call("evolving","OpenFromDisplay",screen)
        end
      end
      return true
    end
  end
  local absent,template,templates=missing(screen,plan,instance,R)
  local extra=extrasHeight(screen,plan,instance,R)*(box.s or 1)
  local tabs=tabsHeight(screen)*(box.s or 1)
  local transfer=transferHeight(screen)*(box.s or 1)
  if tabs>0 then drawChatTabs(listed[screen],box,instance,R) end
  local content={x=box.x,y=box.y+tabs,w=box.w,h=math.max(1,box.h-extra-tabs-transfer),s=box.s}
  local drawn,why=R.Draw(screen,replaceUnreachable(screen,plan,absent),instance,content,P)
  if not drawn then return false,why end
  if extra>0 then extraSlots(screen,plan,instance,{x=box.x,y=box.y+tabs+content.h,w=box.w,h=extra,s=box.s},R,absent,template,templates) end
  if transfer>0 then
    ui.SetCursorScreenPos(box.x,box.y+box.h-transfer)
    if ui.Button("Transfer evolving experience##source-transfer",box.w,math.max(1,transfer-4*(box.s or 1))) then
      call("evolving","OpenFromDisplay",screen)
    end
  end
  if family(screen)=="ChatWindow" and ui.IsWindowHovered((ui.HoveredFlags or {}).ChildWindows or 0) then
    if ui.IsMouseClicked(ui.Mouse.Left) then call("chat","Activate",chat(screen).slot) end
    if ui.IsMouseClicked(ui.Mouse.Right) and not ui.GetIO().alt then
      call("chat","Menu",chat(screen).slot)
      local hud=lib("hud");if hud and hud.T then hud.T.TakeRightClick() end
    end
  end
  return true
end
function P.OpenTools(screen) toolsOpen[screen]=true end
function P.Tools(screen,title,body,size,s)
  if not toolsOpen[screen] or not body then return end
  local w,h=size(s)
  ui.SetNextWindowSize(math.max(240,w*s+24*s),math.max(180,h*s+48*s),(ui.Cond or {}).FirstUseEver or 0)
  local visible,open=ui.Begin("Client tools: "..title.."###source-tools:"..screen,true,0)
  toolsOpen[screen]=open
  local success,why=true,nil
  if visible then
    ui.SetWindowFontScale(s/(ui.GetIO().uiScale or 1))
    local x,y=ui.GetCursorScreenPos();local width,height=ui.GetContentRegionAvail()
    success,why=pcall(body,x,y,width,height,s)
    ui.SetWindowFontScale(1)
  end
  ui.End()
  if not success then error(why,0) end
end
return P
