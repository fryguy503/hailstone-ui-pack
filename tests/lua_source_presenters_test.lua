local root=arg[1] or "."
local checks=0
local function eq(actual,expected)
  checks=checks+1;assert(actual==expected,tostring(actual).." ~= "..tostring(expected))
end
local calls,frame,character,state={},1,"Tester",3
local windows={{slot=1,tab=1,tabs={{title="Main"},{title="Combat"}}}}
local input,enter,active,focus,clicked="",false,false,0,false
local left,right=false,false
local settings,viewport={}, {width=1920,height=1080,uiScale=1,alt=false}
local context={instance={palette={},profile={}},paths={}}
local modules={}
local function record(name,...)
  calls[#calls+1]={name,...}
end
local function count(name)
  local n=0;for _,call in ipairs(calls) do if call[1]==name then n=n+1 end end;return n
end
hs={UI={
  session={GameState=function()return state end},character={Name=function()return character end,
    Gauge=function()return .5 end,Label=function()return "live" end},
  windows={ClickChild=function(...)record("click",...);return true end,ChildState=function()return true,false,17,99,false end},
  inventory={Item=function()return {name="Item"} end,ClickSlot=function(...)record("slotclick",...);return true end,
    SlotName=function(slot)return "Slot "..slot end},
  cursor={PickUp=function()return true end},hotbars={Info=function()return {}end,Click=function()return true end},
  chat={Windows=function()return windows end,Text=function(_,version)return version+1,{"line"},true,1 end,
    Submit=function(...)record("submit",...)end,TakeFocus=function()local value=focus;focus=nil;return value end,
    Info=function()return 3 end,Page=function()return nil end,History=function()return "history" end,
    CycleReply=function()return "/tell Next " end,Link=function(...)record("link",...)end,
    Activate=function(...)record("activate",...)end,Menu=function(...)record("menu",...)end,
    SelectTab=function(...)record("tab",...)end},
  evolving={CanTransferDisplayed=function(screen)return screen=="ItemDisplayWindow#2" end,
    OpenFromDisplay=function(...)record("transfer",...)end}
}}
ui={InputTextFlags={EnterReturnsTrue=1},HoveredFlags={ChildWindows=1},Mouse={Left=0,Right=1},Cond={FirstUseEver=1},
  GetFrameCount=function()return frame end,GetSetting=function(key)return settings[key]end,
  SetSetting=function(key,value)settings[key]=value end,
  SetCursorScreenPos=function(x,y)record("cursor",x,y)end,SetNextItemWidth=function()end,
  SetKeyboardFocusHere=function()record("focus")end,IsMouseDown=function()return false end,
  InputText=function(_,current,_,_,opts)record("input",current,opts);return input,enter end,
  IsItemActive=function()return active end,IsItemHovered=function()return false end,
  SetTooltip=function()end,InvisibleButton=function()return clicked end,
  PushChatFont=function()record("pushfont")end,PopFont=function()record("popfont")end,
  BeginChild=function(...)record("beginchild",...);return true end,EndChild=function()record("endchild")end,
  GetScrollY=function()return 0 end,GetScrollMaxY=function()return 0 end,
  GetContentRegionAvail=function()return 320,180 end,CalcTextSize=function()return 24,12 end,
  SetScrollHereY=function()record("follow")end,SetScrollY=function()end,
  SameLine=function()end,Button=function(label)record("button",label);return clicked end,
  IsWindowHovered=function()return true end,IsMouseClicked=function(which)return which==0 and left or which==1 and right end,
  GetIO=function()return viewport end,
  SetNextWindowSize=function(w,h)record("toolsize",w,h)end,
  Begin=function()record("begin");return true,true end,End=function()record("end")end,
  SetWindowFontScale=function(scale)record("fontscale",scale)end,GetCursorScreenPos=function()return 30,40 end,
  Dummy=function(w,h)record("extent",w,h)end,WindowFlags={HorizontalScrollbar=256}
}
modules["lib/items.lua"]={InvSlot=function(...)record("invslot",...)end}
modules["lib/chatlinks.lua"]={Collapse=function(links,text)return text end,Expand=function(links,text)return text end,
  ForSubmit=function(links,text)if text=="ambiguous"then return nil,"unresolved link"end;return text end}
modules["lib/stml.lua"]={UpdateLines=function(c,lines)c.lines=lines;record("update")end,
  AppendLines=function()record("append")end,DrawLines=function(c,w,h,key,onLink)record("lines",w,h);onLink({27,"tag"})end}
modules["lib/hud.lua"]={T={TakeRightClick=function()record("righttaken")end}}
modules["lib/pack_context.lua"]=context
local originalDofile=dofile
dofile=function(path)if modules[path]then return modules[path]end;return originalDofile(path)end
rawset(_G,"hailstone_skin_presenters",nil)
local P=originalDofile(root.."/shared/source_presenters.lua")
local B=originalDofile(root.."/shared/bindings.lua")
for _,screen in ipairs({"InventoryWindow","PlayerWindow","HotButtonWnd","HotButtonWnd10","Chat32","ItemDisplayWindow#6"})do eq(P.Handles(screen),true)end
eq(P.Handles("OtherWindow"),false)
local plan={type="Screen",rect={w=300,h=200},children={}}
for _,screen in ipairs({"InventoryWindow","PlayerWindow","HotButtonWnd","Chat1","ItemDisplayWindow"})do
  local ok=P.CanDraw(screen,plan,context.instance);eq(ok,true)
end
local inventoryTabs=hs.UI.windows.TabPage
hs.UI.windows.TabPage=function(_,name)if name=="IW_Subwindows"then return 0 end end
hs.UI.windows.SetTabPage=function()record("unexpected-tab-action")end
hs.UI.windows.ListInfo=function(_,name)if name=="AltCurr_PointList"then return 0,3 end end
hs.UI.windows.ListRow=function()return {}end
hs.UI.windows.ListClick=function()record("unexpected-list-action")end
local inventoryPlan={type="Screen",rect={w=428,h=500},children={{type="TabBox",name="IW_Subwindows",children={
  {type="Page",children={{type="Listbox",name="EI_ItemList"},{type="Listbox",name="ProgressionList"},
    {type="Listbox",name="AltCurr_PointList"}}}}}}}
eq(P.CanDraw("InventoryWindow",inventoryPlan,context.instance),true)
eq(count("unexpected-tab-action"),0);eq(count("unexpected-list-action"),0)
inventoryPlan.children[1].name="InventedTabs"
eq(P.CanDraw("InventoryWindow",inventoryPlan,context.instance),true) -- visual tabs may keep local state
inventoryPlan.children[1].name="IW_Subwindows"
eq(count("click"),0);eq(count("submit"),0)
eq(P.InventorySlot({slot="inventory/Equip 0"}),0)
eq(P.InventorySlot({slot="inventory/General 9"}),32)
eq(P.InventorySlot({slot="inventory/General 10"}),nil)
eq(P.InventorySlot({slot=-1}),nil)
eq(B.UseHostRect("ItemDisplayWindow",{name="IDW_ModButton"}),false)
local enabled,checked,value,maximum=B.State("InventoryWindow",{name="IW_Destroy",fields={}})
eq(enabled,true);eq(checked,false);eq(value,17);eq(maximum,99)
eq(B.State("InventoryWindow",{name="UnknownAction",type="Button"}),false)
eq(B.Events("PlayerWindow",{name="PlayerHP"}).right,true)
eq(B.Events("PlayerWindow",{name="PlayerMana"}).left,true)
eq(B.DrawControl("InventoryWindow",{type="InvSlot",slot="inventory/Equip 13"},{x=9,y=11,w=40,h=40,s=1},context.instance,{}),true)
eq(calls[#calls][1],"invslot");eq(calls[#calls][2],13);eq(calls[#calls][4],9);eq(calls[#calls][5],11)
eq(calls[#calls][8],nil);eq(context.instance.sourceSlotNode,nil)
local invSlot=modules["lib/items.lua"].InvSlot
context.instance.sourceSlotNode="outer-slot"
modules["lib/items.lua"].InvSlot=function()error("slot helper failure")end
eq(pcall(P.DrawControl,"InventoryWindow",{type="InvSlot",slot=13},{x=0,y=0,w=40,h=40,s=1},context.instance,{}),false)
eq(context.instance.sourceSlotNode,"outer-slot")
context.instance.sourceSlotNode=nil;modules["lib/items.lua"].InvSlot=invSlot
local doll={type="Screen",name="IW_CharacterView",fields={Style_Border=true}}
local dollPaints=0
eq(P.DrawControl("InventoryWindow",doll,{x=9,y=11,w=40,h=60,s=1},context.instance,
  {PaintControl=function(screen,node,at,owner)
    eq(screen,"InventoryWindow");eq(node,doll);eq(at.x,9);eq(owner,context.instance);dollPaints=dollPaints+1
  end}),true)
eq(dollPaints,1)
local box={x=12,y=30,w=300,h=120,s=1}
P.Frame();focus="/tell Friend ";input="hello";enter=true
eq(P.DrawControl("Chat1",{name="CWChatInput",type="Editbox"},box,context.instance,{}),true)
eq(count("submit"),1);eq(count("focus"),1)
local submitted=calls[#calls];eq(submitted[1],"submit");eq(submitted[2],1);eq(submitted[3],"hello")
input="ambiguous";enter=true
P.DrawControl("Chat1",{name="CWChatInput",type="Editbox"},box,context.instance,{})
eq(count("submit"),1)
P.DrawControl("Chat1",{name="CWChatOutput",type="STMLbox"},box,context.instance,{})
eq(count("link"),1);eq(count("pushfont"),count("popfont"));eq(count("beginchild"),count("endchild"))
local R={Draw=function(screen,p,instance,content,adapter)
  eq(context.sourceManagedPanel==true,false)
  eq(adapter,P);record("sourcebody",content.x,content.y,content.w,content.h,content.s);return true
end,DrawChildren=function(screen,p)record("extra",p.children[1].name)end}
local _,height=P.Size("Chat1",plan);eq(height,224)
P.Draw("Chat1",plan,context.instance,{x=12,y=30,w=300,h=224,s=1},R)
local body;for _,call in ipairs(calls)do if call[1]=="sourcebody"then body=call end end
eq(body[3],54);eq(body[5],200)
clicked=true
P.Draw("ItemDisplayWindow#2",plan,context.instance,{x=0,y=0,w=300,h=228,s=1},R)
eq(count("transfer"),1);eq(P.Size("ItemDisplayWindow#2",plan),300)
P.OpenTools("InventoryWindow")
P.Tools("InventoryWindow","Inventory",function(x,y,w,h,s)record("tools",x,y,w,h,s)end,function()return 500,600 end,1)
eq(count("begin"),1);eq(count("end"),1);eq(count("tools"),1)
local toolsSize;for _,call in ipairs(calls)do if call[1]=="toolsize"then toolsSize=call end end
eq(toolsSize[2],524);eq(toolsSize[3],648)
P.OpenTools("PlayerWindow")
local ok=pcall(P.Tools,"PlayerWindow","Player",function()error("controlled")end,function()return 100,100 end,1)
eq(ok,false);eq(count("begin"),count("end"))

-- Exercise the actual bridge rather than substituting the existing Modern body:
-- source outer size, physical chrome insets and original size preparation coexist.
local sizes,fallbacks,panels,clipDepth=0,0,0,0
local chromeError=false
local nativeOptions,savedSize,placed=false,nil,false
local authoredPlan={type="Screen",rect={x=11,y=13,w=300,h=200},fields={Style_Titlebar=true},children={}}
context.renderer=R
R.Resolve=function()return authoredPlan end
R.TrackWindow=function()end
R.CanDraw=function()return false,"generic path must not replace the major presenter"end
R.ChromeInsets=function(_,_,s)return {left=3*s,right=5*s,top=17*s,bottom=7*s,titleHeight=17*s}end
R.WindowChrome=function(_,title,outer)
  record("chrome",outer.x,outer.y,outer.w,outer.h,outer.s)
  if chromeError then error("chrome failure")end
end
hs.UI.windows.Shown=function()return true end
ui.PushClipRect=function()clipDepth=clipDepth+1 end
ui.PopClipRect=function()clipDepth=clipDepth-1 end
ui.MenuItem=function()return false end
local base={T={Hit=function()return false end}}
base.Window=function(screen,title,opts,body)
  nativeOptions=opts
  local w,h=opts.size(1.5)
  if savedSize and opts.grow then w,h=opts.grow(savedSize[1],savedSize[2],1.5)end
  if opts.panel~=false then panels=panels+1 end
  opts.rolled=false
  local x,y=20,30
  if opts.place then
    local px,py=opts.place(viewport.width,viewport.height,w*1.5,h*1.5,1.5)
    if placed then x=math.max(0,math.min(px,viewport.width-w*1.5));y=math.max(0,math.min(py,viewport.height-h*1.5))
    else eq(px,16.5);eq(py,19.5)end
  end
  body(x,y,w*1.5,h*1.5,1.5)
end
base.Dialog=function()fallbacks=fallbacks+1 end
hs.UI.interfaces={LoadBase=function(path)eq(path,"lib/hud.lua");return base end}
modules["lib/pack_context.lua"]=context
modules["lib/pack_source_presenters.lua"]=P
local hud=originalDofile(root.."/shared/hud.lua")
local opts={size=function()sizes=sizes+1;return 500,600 end,resizable={240,180},
  place=function(W,H,w,h,s,x,y)return x,y end}
hud.Dialog("ItemDisplayWindow","Item",opts,function()fallbacks=fallbacks+1 end)
eq(sizes,1);eq(fallbacks,0);eq(panels,0);eq(context.paths.ItemDisplayWindow,"source")
eq(context.sourceManagedPanel,nil);eq(clipDepth,0)
for _,entry in ipairs(calls)do if entry[1]=="sourcebody"then body=entry end end
eq(body[2],24.5);eq(body[3],55.5);eq(body[4],438);eq(body[5],264)
context.sourceManagedPanel="outer owner"
chromeError=true
ok=pcall(hud.Dialog,"ItemDisplayWindow","Item",opts,function()fallbacks=fallbacks+1 end)
eq(ok,false);eq(context.sourceManagedPanel,"outer owner");eq(clipDepth,0);eq(fallbacks,0)

-- Tall authored hotbars fit with one scale shared by chrome, source hits and
-- glyphs. The source plan itself and saved dimensions remain untouched.
chromeError=false;placed=true;context.sourceManagedPanel=nil
viewport={width=1280,height=720,uiScale=1.5,alt=false}
authoredPlan={type="Screen",rect={x=11,y=13,w=61,h=506},fields={},children={}}
for n=1,12 do authoredPlan.children[n]={type="HotButton",name="HB_Button"..n,rect={x=0,y=(n-1)*40,w=40,h=40}}end
hud.Window("HotButtonWnd","Hotbuttons",{size=function()return 620,58 end},function()error("Modern primary body must not draw")end)
local chrome
for _,entry in ipairs(calls)do
  if entry[1]=="sourcebody"then body=entry elseif entry[1]=="chrome"then chrome=entry end
end
eq(math.floor(chrome[5]+.5),702)
eq(chrome[3]+chrome[5]<=viewport.height,true)
eq(chrome[6],body[6]);eq(math.abs(chrome[6]-702/506)<.000001,true)
eq(authoredPlan.rect.h,506);eq(nativeOptions.fit,false)
local restored=calls[#calls];eq(restored[1],"fontscale");eq(restored[2],1)

-- Scroll-capable authored bodies preserve their virtual extent when a player
-- has saved a smaller frame; all child and font scopes close on draw failure.
authoredPlan={type="Screen",rect={x=0,y=0,w=300,h=400},fields={Style_VScroll=true,Style_HScroll=true},children={}}
savedSize={200,160}
local childBefore=count("beginchild")
hud.Dialog("ItemDisplayWindow","Item",{size=function()return 500,600 end,resizable={32,32}},function()end)
eq(count("beginchild"),childBefore+1);eq(count("beginchild"),count("endchild"))
local extent
for _,entry in ipairs(calls)do if entry[1]=="extent"then extent=entry end end
eq(extent[2],438);eq(extent[3],564)
local draw=R.Draw
R.Draw=function()error("controlled source failure")end
ok=pcall(hud.Dialog,"ItemDisplayWindow","Item",{size=function()return 1,1 end,resizable={32,32}},function()end)
eq(ok,false);eq(count("beginchild"),count("endchild"));eq(context.sourceManagedPanel,nil)
restored=calls[#calls];eq(restored[1],"fontscale");eq(restored[2],1)
R.Draw=draw;savedSize=nil
local before=count("beginchild")
P.ContentSize=function()error("controlled content query")end
ok=pcall(hud.Dialog,"ItemDisplayWindow","Item",{size=function()return 1,1 end,resizable={32,32}},function()end)
eq(ok,false);eq(count("beginchild"),before);eq(count("beginchild"),count("endchild"))
eq(context.sourceManagedPanel,nil)
restored=calls[#calls];eq(restored[1],"fontscale");eq(restored[2],1)
P.ContentSize=nil

-- The real source solver overrides inherited defaults without overwriting a
-- player's settings. Unknown future windows retain the inherited solver result.
local inherited={Solve=function()return {PlayerWindow={x=900,y=600},FutureWindow={x=70,y=80}}end}
hs.UI.interfaces.LoadBase=function(path)eq(path,"lib/layout.lua");return inherited end
R.Resolve=function(screen)if screen=="PlayerWindow"then return {rect={x=17,y=23,w=200,h=100}}end end
local layout=originalDofile(root.."/shared/layout.lua")
local positions=layout.Solve(1280,720,1.5,{PlayerWindow={w=300,h=150},FutureWindow={w=20,h=20}})
eq(positions.PlayerWindow.x,25.5);eq(positions.PlayerWindow.y,34.5);eq(positions.FutureWindow.x,70)
eq(originalDofile(root.."/shared/layout.lua"),layout)
local locations={PlayerWindow={x=3,y=0},TargetWindow={x=3,y=95},GroupWindow={x=3,y=135},
  ExtendedTargetWnd={x=148,y=135},CastSpellWnd={x=0,y=25},HotButtonWnd={x=0,y=230},Chat1={x=95,y=280}}
R.Resolve=function(screen)local at=locations[screen];return at and {rect=at}end
local frames={PlayerWindow={w=160,h=95},TargetWindow={w=150,h=40},GroupWindow={w=145,h=260},
  ExtendedTargetWnd={w=145,h=260},CastSpellWnd={w=55,h=373},HotButtonWnd={w=525,h=53},Chat1={w=421,h=200}}
local function noOverlap(rects)
  for a,one in pairs(rects)do if frames[a] then
    eq(one.x>=0 and one.y>=0 and one.x+one.w<=1280 and one.y+one.h<=720,true)
    for b,two in pairs(rects)do if frames[b] and a<b then
      eq(one.x+one.w<=two.x or two.x+two.w<=one.x or one.y+one.h<=two.y or two.y+two.h<=one.y,true)
    end end
  end end
end
positions=layout.Solve(1280,720,1,frames);noOverlap(positions)
local again=layout.Solve(1280,720,1,frames)
for name,at in pairs(positions)do if frames[name]then eq(at.x,again[name].x);eq(at.y,again[name].y)end end
settings["hud.pos.GroupWindow"]="900,200"
positions=layout.Solve(1280,720,1,frames)
-- The real HUD uses the setting directly; solver leaves it unchanged and packs
-- unsaved peers around that actual saved rectangle rather than its source root.
eq(settings["hud.pos.GroupWindow"],"900,200")
positions.GroupWindow={x=900,y=200,w=145,h=260};noOverlap(positions)
settings["hud.pos.GroupWindow"]=nil

-- Source hotbar settings reshape the actual authored grid. A vertical source
-- does not become the inherited 12-column layout merely by opening the window.
local hot={type="Screen",rect={w=54,h=500},fields={},children={
  {type="TileLayoutBox",name="HB_HotButtonLayout",rect={x=4,y=4,w=40,h=488},anchors={},
    fields={Spacing=4,SecondarySpacing=4},children={}}
}}
for n=1,12 do hot.children[1].children[n]={type="HotButton",name="HB_Button"..n,rect={x=0,y=0,w=36,h=36}}end
local hr={ChromeInsets=function()return {left=2,right=2,top=2,bottom=2}end,
  Geometry=function(node)return node.rect end}
hs.UI.hotbars.Setting=function(_,key)if key=="PercentSize"then return 100 end;return true end
settings["hud.perRow.HotButtonWnd2"]=nil
local hw,hh=P.Size("HotButtonWnd2",hot,context.instance,hr);eq(hw,54);eq(hh,500)
eq(B.Shown("HotButtonWnd2",{name="HB_VerticalBarPageButtons"}),true)
eq(B.Shown("HotButtonWnd2",{name="HB_HorizontalBarPageButtons"}),false)
eq(B.Shown("HotButtonWnd2",{name="HB_InvSlot"}),false)
hs.UI.windows.ChildShown=function()return true end
eq(B.Shown("CastSpellWnd",{name="CSPW_Spell0"}),true)
eq(B.Shown("BuffWindow",{name="Buff0"}),true)
settings["hud.perRow.HotButtonWnd2"]=4
hw,hh=P.Size("HotButtonWnd2",hot,context.instance,hr);eq(hw,160);eq(hh,120)
hs.UI.hotbars.Setting=function(_,key)if key=="PercentSize"then return 150 end;return false end
hw,hh=P.Size("HotButtonWnd2",hot,context.instance,hr);eq(hw,238);eq(hh,178)
eq(B.Shown("HotButtonWnd2",{name="HB_VerticalBarPageButtons"}),false)
eq(B.Shown("HotButtonWnd2",{name="HB_HorizontalBarPageButtons"}),false)
eq(hot.rect.w,54);eq(hot.children[1].children[1].rect.w,36)
local oldHot={type="Screen",rect={w=300,h=100},children={{type="Button",name="HB_Button1",rect={w=36,h=36},fields={}},
  {type="SpellGem",name="HB_SpellGem1",rect={w=36,h=36},eqType="",fields={}}}}
eq(P.CanDraw("HotButtonWnd3",oldHot,context.instance),true)
P.Size("HotButtonWnd3",oldHot,context.instance,hr)
eq(B.Shown("HotButtonWnd3",oldHot.children[2]),false)
eq(oldHot.children[1].type,"Button")
local target,control=B.HotTarget("BandolierWnd",{type="HotButton",eqType="hotbutton/Bar 8/0"})
eq(target,"HotButtonWnd9");eq(control,"HB_Button1")
eq(B.HotTarget("BandolierWnd",{type="HotButton",eqType="hotbutton/Bar 10/0"}),nil)
eq(B.HotTarget("BandolierWnd",{type="HotButton",eqType="hotbutton/Bar 0/12"}),nil)
-- Reachability uses resolved/clipped placements, including selectable pages;
-- hidden/zero-sized authored controls cannot suppress a live fallback slot.
local flow={type="Screen",rect={w=100,h=100},children={}}
for n=1,12 do flow.children[n]={type="HotButton",name="HB_Button"..n,rect={w=40,h=40},unreachable=n>=11}end
local placedDraws,extraNames={},{}
local reach={ChromeInsets=function()return {left=10,right=10,top=10,bottom=10}end,
  VisitChildren=function(screen,p,owner,at,visit,options)
    eq(options.allPages,true)
    local function scan(node)
      for _,child in ipairs(node.children or {})do
        if not child.unreachable and not child.sourceReplaced then visit(child,{x=0,y=0,w=40,h=40,s=1},{x=0,y=0,w=40,h=40,s=1})end
        scan(child)
      end
    end
    scan(p)
  end,
  Draw=function(screen,p)placedDraws[#placedDraws+1]=p;return true end,
  DrawChildren=function(screen,p)extraNames[#extraNames+1]=p.children[1].name end}
hs.UI.hotbars.Setting=function(_,key)if key=="PercentSize"then return 100 end;return true end
local fw,fh=P.Size("HotButtonWnd4",flow,context.instance,reach)
eq(fw,100);eq(fh,192) -- client80 fits one44px cell per row, not two from outer100
P.Draw("HotButtonWnd4",flow,context.instance,{x=0,y=0,w=80,h=172,s=1},reach)
eq(#extraNames,2);eq(extraNames[1],"HB_Button11");eq(extraNames[2],"HB_Button12")
eq(placedDraws[#placedDraws].children[11].sourceReplaced,true)
eq(P.Shown("HotButtonWnd4",placedDraws[#placedDraws].children[11]),false)
eq(flow.children[11].sourceReplaced,nil)
local socketPlan={type="Screen",rect={w=100,h=100},children={{type="Button",name="IDW_Socket_Slot_1_Item",rect={w=40,h=40},unreachable=true}}}
hs.UI.windows.ChildShown=function(_,name)return name=="IDW_Socket_Slot_1_Item"or name=="IDW_Appearance_Socket_Item"end
extraNames={}
fw,fh=P.Size("ItemDisplayWindow#9",socketPlan,context.instance,reach)
eq(fh,192)
P.Draw("ItemDisplayWindow#9",socketPlan,context.instance,{x=0,y=0,w=80,h=172,s=1},reach)
eq(#extraNames,2);eq(extraNames[1],"IDW_Socket_Slot_1_Item");eq(extraNames[2],"IDW_Appearance_Socket_Item")
eq(P.Events("ItemDisplayWindow#9",{name=extraNames[1]}).phases,true)
eq(P.Events("ItemDisplayWindow#9",{name=extraNames[2]}).phases,true)
eq(placedDraws[#placedDraws].children[1].sourceReplaced,true)
eq(socketPlan.children[1].sourceReplaced,nil)
local collisions={type="Screen",rect={w=100,h=100},children={}}
for n=1,6 do collisions.children[n]={type="Button",name="IDW_Socket_Slot_"..n.."_Item",rect={w=40,h=40}}end
hs.UI.windows.ChildShown=function(_,name)return name:match("^IDW_Socket_Slot_[1-6]_Item$")~=nil end
extraNames={}
fw,fh=P.Size("ItemDisplayWindow#10",collisions,context.instance,reach)
eq(fh,368)
P.Draw("ItemDisplayWindow#10",collisions,context.instance,{x=0,y=0,w=80,h=348,s=1},reach)
eq(#extraNames,6)
for _,node in ipairs(placedDraws[#placedDraws].children)do eq(node.sourceReplaced,true)end
for _,node in ipairs(collisions.children)do eq(node.sourceReplaced,nil)end
local single={};for k,v in pairs(reach)do single[k]=v end
single.VisitChildren=function(screen,p,owner,at,visit,options)
  eq(options.allPages,true)
  visit(p.children[1],{x=0,y=0,w=40,h=40,s=1},{x=0,y=0,w=40,h=40,s=1})
end
hs.UI.windows.ChildShown=function(_,name)return name=="IDW_Socket_Slot_1_Item"end
extraNames={}
fw,fh=P.Size("ItemDisplayWindow#11",collisions,context.instance,single)
eq(fh,148)
P.Draw("ItemDisplayWindow#11",collisions,context.instance,{x=0,y=0,w=80,h=128,s=1},single)
eq(#extraNames,1);eq(extraNames[1],"IDW_Socket_Slot_1_Item")
local inTabs={type="Screen",rect={w=100,h=100},children={}}
for n=0,32 do inTabs.children[#inTabs.children+1]={type="InvSlot",name="InvSlot"..n,slot=n,rect={w=40,h=40},inactive=n==0}end
fw,fh=P.Size("InventoryWindow",inTabs,context.instance,reach)
eq(fh,100) -- allPages exposes the still-selectable inactive page, so no duplicate
-- Use all twenty actual portable plans, with populated model contracts rather
-- than empty startup windows. Text metrics here are deterministic fixtures;
-- native ImGui/font/pixel acceptance is a separate CPU capture pass.
local skins={"default","default_old","aya-stock","delta-stock","drakah-pers-adeptus-stock","DuxaUI-stock",
  "Graphite-stock","ib-stock","lodidodi-stock","Lords-stock","Nemesis-stock","po2-stock","po2alt-stock",
  "qqcustom-stock","qqui-stock","sars-stock","Sparxx-stock","Takus-stock","vert-stock","wow-stock"}
local currentSkin,model,metricScale,fontFace="default",nil,1,"face-a"
local fonts,currentFont={},3
local originalMeasure,originalPop=ui.CalcTextSize,ui.PopFont
ui.PushFont=function(font)fonts[#fonts+1]=currentFont;currentFont=font end
ui.PopFont=function()currentFont=table.remove(fonts)or 3 end
ui.CalcTextSize=function(value)
  local longest,rows=0,0
  for line in (tostring(value).."\n"):gmatch("(.-)\n")do
    local characters=0;for _ in line:gmatch(".[\128-\191]*")do characters=characters+1 end
    longest=math.max(longest,characters);rows=rows+1
  end
  local pixels=({10,12,14,16,19,22})[currentFont]or 14
  local faceFactor=fontFace=="face-b"and value~="Wg"and 1.2 or 1
  return longest*pixels*.55*metricScale*faceFactor,math.max(1,rows)*pixels*metricScale
end
local fixtureDofile=dofile
dofile=function(path)
  if path=="lib/pack_bindings.lua"then return B end
  if path:sub(1,12)=="lib/layouts/"then
    return originalDofile(root.."/layouts/"..currentSkin.."/"..path:sub(13))
  end
  return fixtureDofile(path)
end
hs.UI.interfaces={LoadBase=function(path)return originalDofile(root.."/layouts/default/"..path:sub(13))end}
hs.UI.settings={Option=function(name)if name=="font_face"then return fontFace end end}
local realR=originalDofile(root.."/shared/renderer.lua")
hs.UI.windows.Text=function(_,name)
  local value=model and model.text[name]
  return value or"",value~=nil
end
hs.UI.windows.ChildShown=function(_,name)
  if not model then return false end
  if model.shown[name]~=nil then return model.shown[name]end
  return name=="IconButton"or name=="ItemDescription"or name=="ItemDescriptionTabBox"
    or name=="ItemDescriptionTab"or name=="ItemLoreTab"or name=="ItemLore"
end
hs.UI.windows.ChildRect=function(_,name)
  local row,col=name:match("^IDW_Row(%d+)Col(%d+)Stat$")
  if row then return 10+(tonumber(col)-1)*130,100+(tonumber(row)-1)*16,100,20 end
  local heroic=tonumber(name:match("^IDW_Heroic(%d+)$"))
  if heroic and model.heroic[heroic]then
    local at=model.heroic[heroic];return 110+(at.col-1)*130,100+(at.row-1)*16,40,20
  end
end
local function populated(dense)
  local value={text={},shown={},heroic={}}
  local function text(name,caption)value.text[name]=caption;value.shown[name]=true end
  text("IDW_ItemInfo1",dense and"Ancient Mantle of the Celestial Dragon Protector of the Eternal Multiverse with an UnbreakableÜberlangenGegenstandsbezeichnung"
    or"Belt of the Four Winds")
  text("IDW_ItemInfo2","Magic, Lore, No Trade, Heirloom, Quest, Augmentation")
  text("IDW_ItemInfo3","Class: WAR CLR PAL RNG SHD DRU MNK BRD ROG SHM NEC WIZ MAG ENC BST BER")
  text("IDW_ItemInfo4","Race: HUM BAR ERU ELF HIE DEF DWF TRL OGR HFL GNM IKS VAH FRG DRK")
  text("IDW_ItemInfo5","Slots: Charm Ear Head Face Neck Shoulder Arms Back Wrist Range Hands Primary Secondary Finger Chest Legs Feet Waist Power Source Ammo")
  if dense then text("IDW_ItemInfo6","Deity: Rodcet Nife, The Tribunal, Brell Serilis, Tunare, Veeshan")end
  for row=1,dense and 26 or 5 do for col=1,3 do
    if dense or col<3 then
      local prefix="IDW_Row"..row.."Col"..col
      text(prefix.."Stat",dense and("Recommended effectiveness statistic "..row..":"..col)or({"Size:","Weight:","Strength:","Stamina:","Dexterity:"})[row])
      text(prefix.."Value",dense and("-123456789."..row..col)or(row==1 and"MEDIUM"or"25"))
      if dense and #value.heroic<13 then
        local n=#value.heroic+1;value.heroic[n]={row=row,col=col};text("IDW_Heroic"..n,"+123")
      end
    end
  end end
  text("IDW_ModButtonLabel","Unmodified");value.shown.IDW_ModButton=true
  text("ItemDescription","ilvl: 151<BR><c '#ffff00'>Long effect text.</c><BR>Additional details and comparison text.")
  for n=1,7 do
    local prefix=n==7 and"IDW_Appearance_Socket"or"IDW_Socket_Slot_"..n
    local shown=dense or n==1
    value.shown[prefix.."_Screen"]=shown
    -- A hidden parent can retain a true child default in the native model.
    value.shown[prefix.."_Item"]=true
    if shown then
      text(prefix.."_Description","Slot "..n..", type 7 (General: Group): <a WndNotify=\"0,0^0\">An extraordinarily long augment description with all of its original linked text retained</a>")
    end
  end
  if dense then
    value.shown.IDW_Appearance_Socket_Buy_Button=true
    text("IDW_Appearance_Socket_Buy_Button","Jetzt diese Erscheinungsfassung freischalten")
    text("Hailstone_EvolvingFinalResult","Vollständiges Entwicklungsergebnis dieses Gegenstands anzeigen")
  end
  return value
end
local function inspectItem(plan,instance,width,height,s)
  local prepared,extent=P.ItemLayout("ItemDisplayWindow",plan,instance,realR,width,height,s)
  eq(prepared.sourceItemLayout,true);eq(plan.sourceItemLayout,nil);eq(#fonts,0)
  eq(P.OwnsScroll("ItemDisplayWindow",plan),true);eq(P.OwnsScroll("InventoryWindow",plan),false)
  local seen,rects={},{}
  realR.VisitChildren("ItemDisplayWindow",prepared,instance,{x=0,y=0,w=width*s,h=extent*s,s=s},function(node,at,visible)
    local name=node.name or node.item
    local semantic=node.sourceItemText~=nil or node.sourceItemCaption~=nil or name=="IconButton"or name=="IDW_ModButton"
      or name=="ItemDescription"or name:match("^IDW_.*Socket.*_Item$")or name:match("^IDW_.*Socket.*_Description$")
    if semantic then
      eq(seen[name],nil);seen[name]=node
      eq(math.abs(visible.w-at.w)<.00001,true);eq(math.abs(visible.h-at.h)<.00001,true)
      eq(at.x>=-.00001 and at.y>=-.00001 and at.x+at.w<=width*s+.00001 and at.y+at.h<=extent*s+.00001,true)
      if node.sourceItemText or node.sourceItemCaption then
        local tw,th=realR.MeasureText(instance,node,node.sourceItemText or node.sourceItemCaption)
        eq(tw<=at.w+.00001,true);eq(th<=at.h+.00001,true)
      end
      for _,other in ipairs(rects)do
        local overlap=math.max(0,math.min(at.x+at.w,other.x+other.w)-math.max(at.x,other.x))
          *math.max(0,math.min(at.y+at.h,other.y+other.h)-math.max(at.y,other.y))
        eq(overlap<.00001,true)
      end
      rects[#rects+1]=at
    end
  end,{allPages=true})
  for name,caption in pairs(model.text)do
    if caption~=""and name~="IDW_Appearance_Socket_Buy_Button"then eq(seen[name]~=nil,true)end
  end
  eq(seen.IDW_Socket_Slot_1_Item~=nil,true)
  eq(seen.IDW_Socket_Slot_2_Item~=nil,model.shown.IDW_Socket_Slot_2_Screen)
  local originalInfo
  local function original(node)
    if node.name=="IDW_ItemInfo1"then originalInfo=node end
    for _,child in ipairs(node.children or{})do original(child)end
  end
  original(plan);eq(seen.IDW_ItemInfo1.font,originalInfo.font)
  local inherited=getmetatable(originalInfo.fields)
  if inherited then eq(getmetatable(seen.IDW_ItemInfo1.fields),inherited)end
  return prepared,extent,seen
end
local matrix=0
local cachePlan,cacheInstance
for _,skin in ipairs(skins)do
  currentSkin=skin
  local profile=originalDofile(root.."/ui/"..skin.."/lib/pack_profile.lua")
  local instance=realR.New(profile);local source=realR.Resolve("ItemDisplayWindow",instance)
  eq(source~=nil,true)
  for _,dense in ipairs({false,true})do
    model=populated(dense)
    for _,width in ipairs({220,400,640})do for _,scale in ipairs({.75,1.5})do
      metricScale=scale
      local prepared,extent,seen=inspectItem(source,instance,width,240,scale)
      eq(extent>240,true);matrix=matrix+1
      if dense then
        if width==220 then eq(seen.Hailstone_EvolvingFinalResult.sourceItemCaption:find("\n",1,true)~=nil,true)end
        eq(seen.IDW_Appearance_Socket_Buy_Button~=nil,true)
      end
    end end
  end
  if skin=="default"then cachePlan,cacheInstance=source,instance end
end
eq(matrix,240)
currentSkin="default";model=populated(true);metricScale=1
local authored=P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,400,200,1)
local resized=P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,500,350,1)
local scrollbar=P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,486,350,1)
eq(P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,400,200,1),authored)
eq(P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,500,350,1),resized)
eq(P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,486,350,1),scrollbar)
for n=1,5 do P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,500+n,350,1)end
eq(P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,400,200,1)~=authored,true)
local other=P.ItemLayout("ItemDisplayWindow#2",cachePlan,cacheInstance,realR,400,200,1)
eq(other~=authored,true)
local oldText=other.children[1].children[1].children[#other.children[1].children[1].children].name
eq(oldText,"ItemDescription")
model.text.IDW_ItemInfo1="A different inspected item"
local changed=P.ItemLayout("ItemDisplayWindow#2",cachePlan,cacheInstance,realR,400,200,1)
eq(changed~=other,true)
fontFace="face-b"
eq(P.ItemLayout("ItemDisplayWindow#2",cachePlan,cacheInstance,realR,400,200,1)~=changed,true)
fontFace="face-a"
local recent=P.ItemLayout("ItemDisplayWindow#200",cachePlan,cacheInstance,realR,400,200,1)
for n=201,212 do P.ItemLayout("ItemDisplayWindow#"..n,cachePlan,cacheInstance,realR,400,200,1)end
eq(P.ItemLayout("ItemDisplayWindow#200",cachePlan,cacheInstance,realR,400,200,1)~=recent,true)
local beforeSelect=P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,400,200,1)
state=1;frame=frame+1;P.Frame();state=3;frame=frame+1;P.Frame()
eq(P.ItemLayout("ItemDisplayWindow",cachePlan,cacheInstance,realR,400,200,1)~=beforeSelect,true)
local paint,buttons=0,0
local captionNode={type="Button",name="Hailstone_EvolvingFinalResult",sourceItemCaption="Wrapped\ncaption"}
eq(P.DrawControl("ItemDisplayWindow",captionNode,{x=0,y=0,w=100,h=40,s=1},cacheInstance,
  {DrawButton=function(_,node,_,_,caption)eq(node,captionNode);eq(caption,"Wrapped\ncaption");buttons=buttons+1 end}),true)
eq(buttons,1)
local labelNode={type="Label",name="IDW_ItemInfo1",sourceItemText="Wrapped\nname"}
eq(P.DrawControl("ItemDisplayWindow",labelNode,{x=0,y=0,w=100,h=40,s=1},cacheInstance,
  {PaintText=function(_,node,_,_,caption)eq(node,labelNode);eq(caption,"Wrapped\nname");paint=paint+1 end}),true)
eq(paint,1)
local drawnItem,childBefore=0,count("endchild")
local probeR={};for name,fn in pairs(realR)do probeR[name]=fn end
probeR.Draw=function(_,prepared)eq(prepared.sourceItemLayout,true);drawnItem=drawnItem+1;return true end
P.Draw("ItemDisplayWindow",cachePlan,cacheInstance,{x=0,y=0,w=220,h=180,s=1},probeR)
eq(drawnItem,1);eq(count("endchild"),childBefore+1)
probeR.Draw=function()error("populated item draw failure")end
eq(pcall(P.Draw,"ItemDisplayWindow",cachePlan,cacheInstance,{x=0,y=0,w=220,h=180,s=1},probeR),false)
eq(count("endchild"),childBefore+2)
eq(#fonts,0)

-- Legacy self panels keep their source body while putting the clipped name
-- and parked vital gauges inside the frame at different HUD scales.
do
  local oldGauge,oldShown=hs.UI.character.Gauge,hs.UI.windows.ChildShown
  hs.UI.character.Gauge=function(kind)eq(kind,1);return .76,"Tester\nSurname",760 end
  hs.UI.windows.ChildShown=function(_,name)if name=="PetHP" then return false end end
  for _,skin in ipairs({"drakah-pers-adeptus-stock","Nemesis-stock"}) do
    currentSkin=skin
    local profile=originalDofile(root.."/ui/"..skin.."/lib/pack_profile.lua")
    local instance=realR.New(profile)
    local source=assert(realR.Resolve("PlayerWindow",instance))
    local sourceHP
    for _,node in ipairs(source.children) do if node.name=="PlayerHP" then sourceHP=node end end
    local originalY=assert(sourceHP).rect.y
    local sizeW,sizeH=P.Size("PlayerWindow",source,instance,realR)
    local panelHeight=skin=="Nemesis-stock" and 48 or 22
    eq(sizeH>=source.rect.h+panelHeight,true)
    for _,scale in ipairs({0.75,1.5}) do
      local card,caption,drawn,rows
      local probe={
        PaintHealthBox=function(owner,at,fraction,tint)
          eq(owner,instance);eq(fraction,.76);eq(tint,nil);card=at
        end,
        PaintControl=function(_,_,at,_,options)
          caption=options.caption;eq(at.y,card.y);eq(at.w<=card.w,true)
        end,
        Draw=function(_,body,_,client)
          eq(client.y,card.y+panelHeight*scale)
          for _,node in ipairs(body.children) do
            if node.name=="PlayerHP" then
              eq(skin,"drakah-pers-adeptus-stock");eq(node.rect.y,21)
              eq(node.rect.h,8);eq(node.sourceGaugeCaption,"")
              drawn=true
            end
          end
          return true
        end,
        DrawChildren=function(_,container,_,parent)
          rows=container.children
          eq(#rows,2);eq(rows[1].name,"PlayerHP");eq(rows[2].name,"PlayerMana")
          local first=realR.Geometry(rows[1],parent)
          local second=realR.Geometry(rows[2],parent)
          eq(first.y+first.h<=second.y,true);eq(second.y+second.h<=parent.y+parent.h,true)
        end,
      }
      eq(P.Draw("PlayerWindow",source,instance,{x=10,y=30,w=sizeW*scale,h=sizeH*scale,s=scale},probe),true)
      eq(caption,"Tester");eq(card.h,panelHeight*scale);eq(clipDepth,0)
      eq(drawn==true,skin=="drakah-pers-adeptus-stock")
      eq(rows~=nil,skin=="Nemesis-stock");eq(sourceHP.rect.y,originalY)
    end
  end
  hs.UI.character.Gauge,hs.UI.windows.ChildShown=oldGauge,oldShown
end
dofile=fixtureDofile;ui.CalcTextSize=originalMeasure;ui.PopFont=originalPop
local private={instance={},renderer=R}
modules["lib/pack_context.lua"]=private
local privateP=originalDofile(root.."/shared/source_presenters.lua")
eq(privateP~=P,true);eq(privateP.context,private)
eq(originalDofile(root.."/shared/source_presenters.lua"),privateP)
dofile=originalDofile
print("Source presenters: "..checks.." assertions passed; "..matrix.." populated item layouts across 20 skins")
