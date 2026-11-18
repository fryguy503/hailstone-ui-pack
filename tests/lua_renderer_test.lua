-- Synthetic layout/action fixtures. No source game layouts or artwork are used.
local realDofile=dofile
local passed,assertions=0,0
local S,files,parentFiles
local function check(ok,message) assertions=assertions+1;assert(ok,message or "check failed") end
local function equal(a,b,message) check(a==b,(message or "values differ")..": "..tostring(a).." / "..tostring(b)) end
local function record(kind,...) S.events[#S.events+1]={kind=kind,args=table.pack(...)} end
local function disabled() for _,v in ipairs(S.disabled) do if v then return true end end return false end
local function action(module,name,...) record("action",module,name,...) end
local function reset()
  S={events={},draws={},texts={},disabled={},clips=0,fonts=0,colors=0,vars=0,children=0,tables=0,windows=0,
    click={},mouse={},released={},down={},active={},frame=1,time=0,x=0,y=0,text={},states={},io={},rows=0,scroll=0,reads=0,headers=0,
    art={},under={},rects={},visibleChildren={}}
end
reset()
local api={}
local function apiModule(name,methods)
  api[name]=setmetatable(methods,{__index=function(_,key) error("Unregistered API "..name.."."..key) end})
end
api.Supports=function(module,member) return api[module]~=nil and (not member or rawget(api[module],member)~=nil) end
apiModule("assets",{InterfaceImage=function(path)
  record("interfaceAsset",path)
  if S.interfaceImages and S.interfaceImages[path] then return table.unpack(S.interfaceImages[path]) end
end,Image=function(path) record("asset",path)
  if S.assetInfo and S.assetInfo[path]~=nil then
    local v=S.assetInfo[path];if v==false then return nil end;return table.unpack(v)
  end
  if path:find("missing",1,true) then return nil end;return S.imageHandle or "tex:"..path,64,32 end,
  ItemIcon=function(id)return "icon:"..id,0,0,1,1 end})
apiModule("interfaces",{
 LoadBase=function(path)
   if S.bundled then record("base",path);return parentFiles and parentFiles[path] end
   error("Compiled layouts must not use the code-base loader")
 end,
 LoadData=function(path,baseOnly)
   check(not S.bundled,"Bundled layouts must never read private data")
   record("data",path,baseOnly==true,S.caller)
   local source=baseOnly and parentFiles or files
   return source and source[path]
 end,
})
apiModule("windows",{
 ChildState=function(screen,id) if screen=="Unknown" then return nil end;local t=S.states[id] or {}
   if screen=="TextEntryWnd" and id=="OK" and S.minimum then return #((S.text.Entry or {})[1] or "")>=S.minimum end
   return t.enabled~=false,t.checked,t.value,t.count,t.action end,
 ChildShown=function(_,id) if S.visibleChildren[id]~=nil then return S.visibleChildren[id]end;return id~="Hidden" end,
 ChildUnder=function(_,id)return S.under[id]end,
 ChildArt=function(_,id,part)local a=S.art[id..":"..part];if a then return table.unpack(a,1,a.n) end end,
 ChildRect=function(_,id)local a=S.rects[id];if a then return table.unpack(a)end end,
 Text=function(_,id) local t=S.text[id];return t and t[1] or "",t and t[2] or false end,
 ChildColor=function()end,ChildTooltip=function() return "tip" end,
 ChildGauge=function()if S.noChildGauge then return nil,"" end;return 0.5,"50%" end,
 ClickChild=function(screen,id,phase,outside)
   action("windows","ClickChild",screen,id,phase,outside)
   if screen=="TextEntryWnd" and (id=="Entry" or id=="OK") and #((S.text.Entry or {})[1] or "")>=(S.minimum or 0) then S.accepted=true end
   if screen=="ConfirmationDialogBox" and phase=="left" then S.answered=true;S.answer=id=="Yes_Button" end
   return true end,
 SetText=function(screen,id,value)action("windows","SetText",screen,id,value)
   if S.applyText then if S.maximum then value=value:sub(1,S.maximum)end;S.text[id]={value,true}end end,
 SetSlider=function(...)action("windows","SetSlider",...) end,
 ComboInfo=function(_,id) if id:find(":",1,true) then return {"CellA","CellB"},0 end;return {"A","B"},0 end,
 ComboSelect=function(...)action("windows","ComboSelect",...)end,
 ListInfo=function()if S.noList then return nil end;return S.rows,2,0,{"Name","Value"},{40,80},S.multi end,
 ListRow=function(_,_,row)S.reads=S.reads+1;return {"Row"..row,"Value",disabled=S.rowDisabled} end,
 ListClick=function(...)action("windows","ListClick",...) end,ListHeaderClick=function(...)action("windows","ListHeaderClick",...) end,
 TabPage=function()return S.tab or 0 end,SetTabPage=function(...)action("windows","SetTabPage",...)end,
 StmlLink=function(...)action("windows","StmlLink",...)end,
 Replace=function()return S.shown~=false,20,30,200,100,false,false end,
 Title=function()return "Test"end,Show=function(...)action("windows","Show",...)end,Placed=function(...)action("windows","Placed",...)end,
})
apiModule("character",{Label=function(n)return "Label"..n end,Gauge=function()
  if S.unavailableGauge then return nil,"Hidden",-1 end
  if S.specialGauge then return 1,"Special",-2,0.5,0,0 end
  return S.air or 0.25,""
end})
apiModule("inventory",{SlotItem=function()return S.item end,Item=function(slot)record("itemLookup",slot);return S.inventoryItem or S.item end,
 ClickSlot=function(...)action("inventory","ClickSlot",...);return S.leftMade or false end})
apiModule("cursor",{HoldingButton=function()return S.holdingButton end,PickUp=function(...)action("cursor","PickUp",...);S.holdingButton=S.pickupMade;return S.pickupMade or false end})
apiModule("spells",{GemInfo=function()return S.gemInfo or {tex={},u0=0,u1=1,v0=0,v1=1,tooltip="Spell"}end,
 GemOverlay=function()end,GemClick=function(...)action("spells","GemClick",...)end,
 ButtonCoolDown=function()if S.cooldownTop then return S.cooldownTop,0.2,0.3,0.4,0.5 end end})
apiModule("hotbars",{Button=function()return "spell","Hot"end,Click=function(...)action("hotbars","Click",...)end,
 Info=function()return S.hotInfo or {tex={},enabled=true}end})
hs={UI=api}
ui={Col={Text=1,TextDisabled=2,FrameBg=3,Button=4,ButtonHovered=5,ButtonActive=6,Header=7,HeaderHovered=8,HeaderActive=9,Border=10},
  StyleVar={FrameRounding=1,WindowRounding=2,ChildRounding=3,PopupRounding=4,TabRounding=5,GrabRounding=6,ScrollbarRounding=7,WindowPadding=8},Mouse={Left=0,Right=1},HoveredFlags={AllowWhenDisabled=1},
  Cond={Always=1,FirstUseEver=2},InputTextFlags={ReadOnly=1,Password=2,EnterReturnsTrue=4},
  SelectableFlags={SpanAllColumns=1,AllowDoubleClick=2},TableFlags={ScrollY=1,RowBg=2,Resizable=4},TableColumnFlags={WidthFixed=1}}
ui.window=function() error("The renderer must not register/intercept UI windows") end
local originalWindow=ui.window
ui.GetFrameCount=function()return S.frame end;ui.GetTime=function()return S.time end
ui.GetIO=function()return S.io end
ui.CalcTextSize=function(value)check(type(value)=="string","text must be a string");return #value*7,14 end
ui.PushFont=function()S.fonts=S.fonts+1 end;ui.PopFont=function()S.fonts=S.fonts-1;check(S.fonts>=0)end
ui.PushClipRect=function(...)S.clips=S.clips+1;record("clip",...)end;ui.PopClipRect=function()S.clips=S.clips-1;check(S.clips>=0)end
ui.PushStyleColor=function()S.colors=S.colors+1 end;ui.PopStyleColor=function(n)S.colors=S.colors-n;check(S.colors>=0)end
ui.PushStyleVar=function(key,x,y)S.vars=S.vars+1;if key==ui.StyleVar.WindowPadding then S.zeroChildPadding=x==0 and y==0 end end
ui.PopStyleVar=function(n)S.vars=S.vars-n;check(S.vars>=0)end
ui.BeginDisabled=function(value)S.disabled[#S.disabled+1]=value end;ui.EndDisabled=function()check(#S.disabled>0);table.remove(S.disabled)end
ui.DrawImage=function(...)S.draws[#S.draws+1]=table.pack(...)end
ui.DrawRect=function(...)record("border",...)end;ui.DrawRectFilled=function(...)record("fill",...)end
ui.DrawRectGradient=function(...)record("gradient",...)end
ui.DrawText=function(...)local a=table.pack(...);S.texts[#S.texts+1]=a end
ui.SetCursorScreenPos=function(x,y)S.x,S.y=x,y end;ui.GetCursorScreenPos=function()return S.x,S.y end
ui.GetWindowPos=function()return 0,0 end;ui.GetWindowSize=function()return 200,100 end
ui.GetContentRegionAvail=function()if S.children>0 and S.childAvail then return table.unpack(S.childAvail)end;return 200,100 end
ui.SetNextWindowPos=function(...)record("windowpos",...)end;ui.SetNextWindowSize=function(...)record("windowsize",...)end
ui.Begin=function()S.windows=S.windows+1;return true,true end;ui.End=function()S.windows=S.windows-1;check(S.windows>=0)end
ui.InvisibleButton=function(id,w,h)S.last=id;record("hit",id,S.x,S.y,w,h);return not disabled() and S.click[id] or false end
ui.IsItemHovered=function()return S.hover~=false end
ui.IsItemActive=function()return not disabled() and S.active[S.last] or false end
ui.IsItemClicked=function(button)return not disabled() and S.mouse[button] and S.mouse[button][S.last] or false end
ui.IsMouseDown=function(button)return S.down[button] or false end
ui.IsMouseReleased=function(button)return S.released[button] or false end
ui.IsMouseClicked=function(button)return S.mouseClicked==button end
ui.IsMouseDoubleClicked=function()return S.double or false end
ui.IsMouseDragging=function()return S.drag or false end
ui.GetMousePos=function()return S.mx or 0,S.my or 0 end
ui.SetTooltip=function(...)record("tooltip",...)end
ui.SetNextItemWidth=function(...)record("width",...)end
ui.SetKeyboardFocusHere=function()record("focus")end
ui.InputText=function(id,value,capacity,flags)
  S.last=id;record("input",id,capacity,flags)
  local changed=not disabled() and S.input~=nil
  if flags&ui.InputTextFlags.EnterReturnsTrue~=0 then changed=not disabled() and S.enter==true end
  return S.input or value,changed
end
ui.InputTextMultiline=function(id,value,capacity,w,h,flags)record("multiline",id,capacity,w,h,flags);return S.input or value,not disabled() and S.input~=nil end
ui.BeginCombo=function(id)S.last=id;return S.combo==true and not disabled()end;ui.EndCombo=function()end
ui.Selectable=function(id,selected,flags)S.last=id;record("selectable",id,flags);return not disabled() and S.click[id] or false end
ui.BeginTable=function()S.tables=S.tables+1;return true end;ui.EndTable=function()S.tables=S.tables-1;check(S.tables>=0)end
ui.TableSetupColumn=function()end;ui.TableNextRow=function()end;ui.TableNextColumn=function()end
ui.TableHeadersRow=function()S.headers=S.headers+1 end;ui.TableHeadersRowClicked=function()S.headers=S.headers+1;return -1 end
ui.TableGetHoveredColumn=function()return 1 end
ui.GetScrollY=function()return S.scroll end;ui.SetScrollY=function(y)S.scroll=y;record("scroll",y)end
ui.Dummy=function(...)record("dummy",...)end;ui.Image=function(...)record("inlineimage",...)end;ui.SameLine=function()end;ui.TextColored=function(...)record("cell",...)end
ui.BeginChild=function()S.children=S.children+1;S.beginChildZeroPadding=S.zeroChildPadding;return true end;ui.EndChild=function()S.children=S.children-1;check(S.children>=0)end
setmetatable(ui,{__index=function(_,key)error("Unregistered UI function "..key)end})

local stml={Lines=function(raw)return {{raw}}end,DrawLines=function(view,width,height,key,callback)
  check(type(key)=="number");S.stmlView=view;S.stmlArgs={width,height,key}
  if S.stmlError then error("synthetic STML draw failure")end
  if S.stmlLink then callback({27,"item:123"})end
end}
dofile=function(path)
  if path:match("^lib/compiled/") then error("Compiled layouts must not use the code-root loader") end
  if path=="lib/pack_bindings.lua" then return realDofile("shared/bindings.lua") end
  if path=="lib/pack_renderer.lua" then return realDofile("shared/renderer.lua") end
  if path=="lib/stml.lua" then return stml end
  if files and files[path] then if S.bundled then record("selected",path)end;return files[path] end
  error("Fixture file does not exist: "..path)
end
local function syntheticRenderer(renderer)
  renderer.testProductionCompatible=renderer.Bindings.Compatible
  local screens={Test=true,InventoryWindow=true,ActionsWindow=true,Bag3=true,CastSpellWnd=true,HotButtonWnd2=true,["ItemDisplayWindow#3"]=true}
  -- Semantic control fixtures explicitly opt in their fake models. The shipped
  -- bindings retain their conservative audit gate; no synthetic IDs are shipped.
  renderer.Bindings.Compatible=function(screen,p,instance)
    if screens[screen] then return true end
    return renderer.testProductionCompatible(screen,p,instance)
  end
  return renderer
end
local R=syntheticRenderer(realDofile("shared/renderer.lua"))
local serial=0
local function fixture(index)
  serial=serial+1
  index=index or {version=2,windows={},images={},animations={},templates={}}
  files={["lib/compiled/index.lua"]=index};parentFiles={}
  return R.New({id="fixture"..serial,index="lib/compiled/index.lua"}),index
end
local function node(kind,id,x,y,w,h,fields)
  return {type=kind,name=id,item=id,text=id,rect={x=x or 0,y=y or 0,w=w or 80,h=h or 20},
    fields=fields or {},font=3,colors={},art={},children={}}
end
local function plan(...)
  local p=node("Screen","Test",0,0,200,100);p.children={...};return p
end
local box={x=10,y=20,w=200,h=100,s=1}
local function actions(module,name)
  local out={};for _,event in ipairs(S.events)do if event.kind=="action" and event.args[1]==module and event.args[2]==name then out[#out+1]=event.args end end;return out
end
local function run(name,body)
  reset()
  local ok,why=xpcall(body,debug.traceback)
  if not ok then error(name..": "..why,0)end
  equal(S.clips,0,"clip stack");equal(S.fonts,0,"font stack");equal(S.colors,0,"color stack");equal(S.vars,0,"style stack")
  equal(#S.disabled,0,"disabled stack");equal(S.children,0,"child stack");equal(S.tables,0,"table stack");equal(S.windows,0,"window stack")
  equal(ui.window,originalWindow,"UI registration remains untouched")
  passed=passed+1
end

run("exact geometry and explicit anchors",function()
  local n=node("Button","Anchored",5,6,50,20);n.anchors={leftToLeft=true,rightToLeft=false,topToTop=true,bottomToTop=true,left=8,right=12,top=4,explicit={left=true,right=true,top=true}}
  local r=R.Geometry(n,{x=100,y=200,w=300,h=160,s=2})
  equal(r.x,116);equal(r.y,208);equal(r.w,260);equal(r.h,40)
end)
run("atlas crop and animated frame",function()
  local I=fixture({version=2,windows={},images={atlas={path="uifiles/test/atlas.tga"}},animations={A={frames={{image="atlas",rect={x=16,y=8,w=16,h=8},duration=100},{image="atlas",rect={x=32,y=0,w=16,h=8},duration=100}},cycle=true}}})
  S.time=0.05;check(R.Animation(I,"A",box));equal(S.draws[1][6],0.25);equal(S.draws[1][7],0.25);equal(S.draws[1][8],0.5);equal(S.draws[1][9],0.5)
  S.frame=2;S.time=0.15;R.Animation(I,"A",box);equal(S.draws[2][6],0.5)
end)
run("source nine-slice frame",function()
  local I=fixture({version=2,windows={},images={atlas={path="uifiles/test/atlas.tga"}},animations={A={frames={{image="atlas",rect={x=0,y=0,w=8,h=8}}}}},templates={F={fields={TopLeft="A",Top="A",TopRight="A",Left="A",Middle="A",Right="A",BottomLeft="A",Bottom="A",BottomRight="A"}}}})
  check(R.Frame(I,"F",box));equal(#S.draws,9);equal(S.draws[2][2],18);equal(S.draws[2][4],202)
end)
run("disabled buttons cannot act",function()
  local I=fixture();S.states.Save={enabled=false};S.click["##pack:Save"]=true;S.mouse[1]={["##pack:Save"]=true}
  check(R.Draw("Test",plan(node("Button","Save")),I,box));equal(#actions("windows","ClickChild"),0)
end)
run("buttons act on the exact instance",function()
  local I=fixture();S.click["##pack:Save"]=true
  R.Draw("ItemDisplayWindow#3",plan(node("Button","Save")),I,box)
  local a=actions("windows","ClickChild");equal(#a,1);equal(a[1][3],"ItemDisplayWindow#3");equal(a[1][4],"Save");equal(a[1][5],"left")
end)
run("explicit empty labels replace source text",function()
  local I=fixture();S.text.Caption={"",true};R.Draw("Test",plan(node("Label","Caption")),I,box);equal(#S.texts,0)
end)
run("edit text and default zero capacity",function()
  local I=fixture();S.input="new text";R.Draw("Test",plan(node("Editbox","Edit",0,0,100,20,{MaxChars=0})),I,box)
  equal(actions("windows","SetText")[1][5],"new text")
  for _,e in ipairs(S.events)do if e.kind=="input"then equal(e.args[2],4096)end end
end)
run("slider uses model step count and source geometry",function()
  local I=fixture();S.states.Slider={value=1,count=11};S.active["##slider:Slider"]=true;S.mx=110;S.my=20
  R.Draw("Test",plan(node("Slider","Slider",0,0,100,20)),I,box);equal(actions("windows","SetSlider")[1][5],10)
end)
run("combobox dispatches selected zero-based row",function()
  local I=fixture();S.combo=true;S.click["B##2"]=true
  R.Draw("Test",plan(node("Combobox","Pick")),I,box);equal(actions("windows","ComboSelect")[1][5],1)
end)
run("large list is virtual and retains disabled row rules",function()
  local I=fixture();S.rows=1000;S.scroll=1600;S.rowDisabled=true;S.click["##row:99"]=true
  R.Draw("Test",plan(node("Listbox","List",0,0,200,64)),I,box)
  check(S.reads<15,"visible-row budget");equal(S.headers,1);equal(#actions("windows","ListClick"),0)
end)
run("tab page actions and selected contents",function()
  local I=fixture();local tabs=node("TabBox","Tabs",0,0,200,100)
  tabs.children={node("Page","One"),node("Page","Two")};tabs.children[2].children={node("Label","Second")};S.click["##tab:Tabs:2"]=true
  R.Draw("Test",plan(tabs),I,box);equal(actions("windows","SetTabPage")[1][5],1)
  check(#S.texts>=3)
end)
run("STML links keep host screen child message and identity",function()
  local I=fixture();S.stmlLink=true;R.Draw("Test",plan(node("STMLbox","Description")),I,box)
  local a=actions("windows","StmlLink")[1];equal(a[3],"Test");equal(a[4],"Description");equal(a[5],27);equal(a[6],"item:123")
end)
run("item held phases preserve slot zero and avoid release double action",function()
  local I=fixture();local slot=node("InvSlot","Charm");slot.slot=0;local p=plan(slot)
  S.mouse[0]={["##slot:Charm"]=true};S.down[0]=true;R.Draw("InventoryWindow",p,I,box)
  S.mouse={};S.time=0.4;R.Draw("InventoryWindow",p,I,box)
  S.down[0]=false;S.released[0]=true;S.time=0.5;R.Draw("InventoryWindow",p,I,box)
  local a=actions("inventory","ClickSlot");equal(#a,2);equal(a[1][3],0);equal(a[1][5],"leftheld");equal(a[2][5],"left")
end)
run("unsupported graphs fall back before any action",function()
  local I=fixture();local p=plan(node("Button","Save"),node("HtmlComponent","Browser"));S.click["##pack:Save"]=true
  local ok,why=R.Draw("Test",p,I,box);equal(ok,false);check(why:find("adapter",1,true));equal(#actions("windows","ClickChild"),0)
  local count=0;local wrapped=R.Wrap("Test",function()count=count+1;return 17 end,I.profile,"Unknown")
  equal(wrapped(),17);equal(count,1);check(#R.Diagnostics(I)>0)
end)
run("lazy bucket inheritance and sparse defaults",function()
  local path="lib/compiled/windows/ab123456.lua";local bucket="lib/compiled/buckets/0b.lua"
  local I,index=fixture({version=2,storage="buckets-v1",windows={Base=path},defaults={Button={MaxChars=12}},images={},animations={},templates={}})
  files[bucket]={};parentFiles[bucket]={[path]=plan(node("Button","Save"))}
  local p=R.Resolve("Base",I);check(p);equal(p.children[1].fields.MaxChars,12);equal(R.Resolve("Base",I),p)
end)
run("parent index fills missing screen and resources",function()
  serial=serial+1;local p=plan(node("Button","Save"));local path="lib/compiled/windows/aa1234.lua"
  files={["lib/compiled/index.lua"]={version=2,windows={},images={A={path="uifiles/selected/a.png"}}},[path]=p}
  parentFiles={["lib/compiled/index.lua"]={version=2,windows={OnlyParent=path},images={B={path="uifiles/default/b.png"}}}}
  local I=R.New({id="inherited"..serial,index="lib/compiled/index.lua"});equal(R.Resolve("OnlyParent",I),p)
  equal(I.index.images.A.path,"uifiles/selected/a.png");equal(I.index.images.B.path,"uifiles/default/b.png")
end)
run("fallback theme draws selected frame and button artwork",function()
  local I=fixture({version=2,windows={},images={atlas={path="uifiles/test/atlas.tga"}},animations={A={frames={{image="atlas",rect={x=0,y=0,w=8,h=8}}}}},templates={W={fields={Background="A"}},B={fields={Normal="A",Pressed="A"}},G={fields={Background="A",Fill="A"}}},style={frame={template="W"},button={template="B"},gauge={template="G"}}})
  local T={};R.StyleTheme(T,I);T.Panel(0,0,200,100,1);S.click.Press=true;check(T.Button("Press",0,0,80,20,1,"Action",{}));T.Bar("hp",0,30,100,40,1,0.5,nil,{center="Half"})
  check(#S.draws>=4,"selected art, not just colors");equal(#S.texts,2)
end)
run("standalone model window has balanced lifetime",function()
  local I=fixture();R.Draw("Test",plan(node("Label","Caption")),I);equal(#actions("windows","Placed"),1)
end)

run("compact tuple plans retain source fields anchors and byte colors",function()
  local path="lib/compiled/windows/ab123456.lua"
  local I=fixture({version=2,encoding="node-tuples-v1",windows={Test=path},defaults={Button={Enabled=false}},images={},animations={},templates={}})
  files[path]={"Screen","Test",false,"source",{0,0,200,100},{true,true,true,true,0,0,0,0,0},"Title",3,{}, {},"",{}, {
    {"Button","SourceButton","Save","child-source",{1,2,80,20},{true,true,true,false,4,0,8,12,13},"Save",5,
      {TextColor={255,128,0,255}},{"A","B","C","D"},0,{Checked=true},{},0,7}}}
  local p=R.Resolve("Test",I);check(p);equal(p.name,"Test");local n=p.children[1]
  equal(n.name,"Save");equal(n.source,"child-source");equal(n.rect.w,80);equal(n.fields.Enabled,false);equal(n.fields.Checked,true)
  check(n.anchors.explicit.top);check(n.anchors.explicit.left);check(n.anchors.explicit.right);equal(n.anchors.explicit.bottom,false)
  equal(n.colors.TextColor[1],1);equal(n.colors.TextColor[2],128/255);equal(n.art.drawTemplate,"D");equal(n.slot,0);equal(n.gaugeEqType,7)
end)

local function artFixture()
  local index={version=2,windows={},images={atlas={path="uifiles/test/atlas.tga"}},animations={},templates={},style={}}
  for n,name in ipairs({"A","B","C","D","E","F","G"}) do index.animations[name]={frames={{image="atlas",rect={x=(n-1)*8,y=0,w=8,h=8}}}} end
  local I=fixture(index);return I,index
end
run("dynamic static artwork hides replaces and draws live atlas cells",function()
  local I=artFixture();local n=node("StaticAnimation","Indicator");n.art.animation="A";local p=plan(n)
  S.art["Indicator:decal"]=table.pack(false);R.Draw("Test",p,I,box);equal(#S.draws,0,"explicitly hidden")
  S.art={};R.Draw("Test",p,I,box);equal(S.draws[1][6],0,"nil uses selected compiled default")
  S.draws={};S.art["Indicator:decal"]=table.pack("B");R.Draw("Test",p,I,box);equal(S.draws[1][6],8/64,"live animation")
  S.draws={};local texture={};S.art["Indicator:decal"]=table.pack(texture,0.2,0.3,0.4,0.5)
  R.Draw("Test",p,I,box);equal(S.draws[1][1],texture);equal(S.draws[1][7],0.3);equal(S.draws[1][9],0.5)
  S.draws={};S.art["Indicator:decal"]=table.pack("MissingDynamicState");R.Draw("Test",p,I,box)
  equal(#S.draws,0,"missing new state must not freeze the previous authored state");check(#R.Diagnostics(I)>0)
end)
run("host underlay ordering preserves authored child geometry",function()
  local I=fixture();S.under.B=true;S.rects.A={12,14,30,16,true,6,8}
  R.Draw("Test",plan(node("Label","A"),node("Label","B"),node("Label","C")),I,box)
  equal(S.texts[1][7],"B");equal(S.texts[2][7],"A");equal(S.texts[3][7],"C")
  equal(S.texts[2][1],10);equal(S.texts[2][2],20)
end)
run("only an explicit dynamic adapter may borrow host child geometry",function()
  local I=fixture();S.rects.A={12,14,30,16,true,6,8}
  local original=R.Bindings.UseHostRect
  R.Bindings.UseHostRect=function(screen,n) return screen=="Test" and n.name=="A" end
  R.Draw("Test",plan(node("Label","A")),I,box)
  R.Bindings.UseHostRect=original
  equal(S.texts[1][1],22);equal(S.texts[1][2],34)
end)
run("custom source drawing requires a presenter preflight",function()
  local I=fixture();local p=plan(node("Button","Unsupported"))
  local events=#S.events
  equal(R.Draw("Test",p,I,box,true),false)
  local called=0
  local denied={CanDraw=function()called=called+1;return false,"data unavailable" end}
  local ok,why=R.Draw("Test",p,I,box,denied)
  equal(ok,false);equal(why,"data unavailable");equal(called,1);equal(#S.events,events)
end)
run("paint-only source controls never register input or actions",function()
  local I=fixture();local n=node("Button","Paint")
  R.PaintControl("Test",n,box,I,{caption="Paint only",hovered=true})
  for _,event in ipairs(S.events)do check(event.kind~="hit" and event.kind~="action") end
  equal(S.texts[#S.texts][7],"Paint only")
end)
run("frame side-only templates retain source cap dimensions",function()
  local I,index=artFixture();index.templates.F={fields={Left="A",Middle="B",Right="C"}}
  check(R.Frame(I,"F",box));equal(#S.draws,3);equal(S.draws[1][4]-S.draws[1][2],8);equal(S.draws[3][4]-S.draws[3][2],8)
end)
run("theme panels retain attack glow width and fade alpha",function()
  local I=fixture();local T={};R.StyleTheme(T,I);T.Panel(10,20,110,80,2,{glow={1,0.2,0.1,0.5},glowWidth=3,alpha=0.25})
  local e=S.events[#S.events];equal(e.kind,"border");equal(e.args[10],6);equal(e.args[8],0.125);equal(e.args[1],7)
end)
run("theme gauge keys select distinct selected-source templates",function()
  local I,index=artFixture();index.style.gauges={}
  local roles={hp="A",mana="B",endurance="C",experience="D",casting="E",target="F"}
  for role,anim in pairs(roles)do index.templates[role]={fields={Background=anim,Fill=anim}};index.style.gauges[role]={template=role}end
  local T={};R.StyleTheme(T,I)
  for n,key in ipairs({"hp","mana","endurance","xp","cast","target"})do
    S.draws={};T.Bar(key,0,0,100,10,1,0.5,nil,{});equal(S.draws[1][6],(n-1)*8/64,key)
  end
  S.draws={};T.Bar("aa",0,0,100,10,1,0.5,nil,{});equal(S.draws[1][6],24/64)
end)
run("primitive decorations preserve original item and action identity",function()
  local I,index=artFixture();index.templates.B={fields={Normal="A",Pressed="B",Flyby="C"}}
  index.templates.C={fields={Normal="D",Pressed="E"}};index.templates.S={fields={Background="A",Thumb={Normal="B",Flyby="C",Pressed="D",PressedFlyby="E"}}}
  index.style.button={template="B"};index.style.checkbox={template="C"};index.style.slider={template="S"}
  S.last="OriginalItem";S.x=123;S.y=456
  check(R.DecorateWidget(I,"Button",box,{caption="Save##hidden",hovered=true}));equal(S.draws[1][6],16/64);equal(S.texts[1][7],"Save")
  S.draws={};check(R.DecorateWidget(I,"Checkbox",box,{checked=true,caption="Choice"}));equal(S.draws[1][6],32/64)
  S.draws={};check(R.DecorateWidget(I,"SliderInt",box,{fraction=0.75,hovered=true,active=true,valueText="75"}));equal(S.draws[2][6],32/64)
  equal(S.last,"OriginalItem");equal(S.x,123);equal(S.y,456);equal(#actions("windows","ClickChild"),0)
  for _,e in ipairs(S.events)do check(e.kind~="hit","decoration must not create input targets") end
end)
run("texture handles are reacquired after another frame evicts the sheet",function()
  local I=artFixture();local old,new={},{}
  S.imageHandle=old;R.Animation(I,"A",box);equal(S.draws[1][1],old)
  S.imageHandle=new;R.Animation(I,"A",box);equal(S.draws[2][1],old,"same-frame lookup is shared")
  S.frame=S.frame+1;R.Animation(I,"A",box);equal(S.draws[3][1],new,"reopened/evicted texture must recover")
  local lookups=0;for _,e in ipairs(S.events)do if e.kind=="asset" then lookups=lookups+1 end end;equal(lookups,2)
end)
run("draggable action buttons do not also activate when released",function()
  local I=fixture();local p=plan(node("Button","Ability"));S.active["##pack:Ability"]=true;S.drag=true;S.pickupMade=true
  R.Draw("ActionsWindow",p,I,box);equal(#actions("cursor","PickUp"),1)
  S.active={};S.drag=false;S.click["##pack:Ability"]=true;R.Draw("ActionsWindow",p,I,box)
  equal(#actions("windows","ClickChild"),0)
end)
run("item long right press retains held display and outside release phases",function()
  local I=fixture();local p=plan(node("InvSlot","Item"));S.mouse[1]={["##slot:Item"]=true};S.down[1]=true
  R.Draw("Bag3",p,I,box);S.mouse={};S.time=0.6;R.Draw("Bag3",p,I,box)
  S.down[1]=false;S.released[1]=true;S.hover=false;R.Draw("Bag3",p,I,box)
  local a=actions("windows","ClickChild");equal(#a,3);equal(a[1][3],"Bag3");equal(a[1][5],"rightdown");equal(a[2][5],"rightheld");equal(a[3][5],"rightupheld");equal(a[3][6],true)
end)
run("spell gem right hold and hotbutton disabled state preserve semantics",function()
  local I=fixture();local p=plan(node("SpellGem","CSPW_Spell0"));S.mouse[1]={["##gem:CSPW_Spell0"]=true};S.down[1]=true
  R.Draw("CastSpellWnd",p,I,box);S.mouse={};S.time=0.6;R.Draw("CastSpellWnd",p,I,box)
  S.down[1]=false;S.released[1]=true;R.Draw("CastSpellWnd",p,I,box)
  local a=actions("spells","GemClick");equal(#a,3);equal(a[1][3],"CSPW_Spell0");equal(a[2][4],"rightheld");equal(a[3][4],"rightupheld")
  S.hotInfo={enabled=false,label="Disabled",cooldown=0.5};S.click["##hot:HB_Button1"]=true
  R.Draw("HotButtonWnd2",plan(node("HotButton","HB_Button1")),I,box);equal(#actions("hotbars","Click"),0)
end)
run("theme buttons retain the inherited overlap-aware hit function",function()
  local I=fixture();local calls=0;local T={Hit=function(id,x0,y0,x1,y1)calls=calls+1;equal(id,"KeepHit");return true end}
  local original=T.Hit;R.StyleTheme(T,I);check(T.Button("KeepHit",0,0,80,20,1,"Action",{}));equal(calls,1);equal(T.Hit,original)
end)
run("hotbuttons distinguish a quick right release from one held activation",function()
  local I=fixture();local p=plan(node("HotButton","HB_Button1"))
  S.mouse[1]={["##hot:HB_Button1"]=true};S.down[1]=true
  R.Draw("HotButtonWnd2",p,I,box);equal(#actions("hotbars","Click"),0)
  S.mouse={};S.time=0.1;S.down[1]=false;S.released[1]=true
  R.Draw("HotButtonWnd2",p,I,box)
  local a=actions("hotbars","Click");equal(#a,1);equal(a[1][5],"right")
  S.events={};S.released={};S.mouse[1]={["##hot:HB_Button1"]=true};S.down[1]=true;S.time=1
  R.Draw("HotButtonWnd2",p,I,box);S.mouse={};S.time=1.6;R.Draw("HotButtonWnd2",p,I,box)
  S.time=1.8;R.Draw("HotButtonWnd2",p,I,box)
  S.down[1]=false;S.released[1]=true;R.Draw("HotButtonWnd2",p,I,box)
  a=actions("hotbars","Click");equal(#a,1);equal(a[1][5],"rightheld")
end)
run("hotbuttons keep icon tint cooldown direction and mapped key text",function()
  local I=fixture();local p=plan(node("HotButton","HB_Button1",0,0,40,40))
  local tex={};S.hotInfo={tex=tex,tint={0.2,0.3,0.4,0.5},cooldown=0.25,overlay="7"}
  S.text.HB_Button1={"Ctrl+1",true};R.Draw("HotButtonWnd2",p,I,box)
  local drawn;for _,v in ipairs(S.draws) do if v[1]==tex then drawn=v end end
  check(drawn);equal(drawn[10],0.2);equal(drawn[11],0.3);equal(drawn[12],0.4);equal(drawn[13],0.5)
  local cooldown=false;for _,e in ipairs(S.events) do
    if e.kind=="fill" and e.args[2]==30 and e.args[4]==60 then cooldown=true end
  end
  check(cooldown,"cooldown covers the bottom 75 percent")
  local key=false;for _,v in ipairs(S.texts) do if v[7]=="Ctrl+1" then key=true end end
  check(key,"configured hotkey caption survives source presentation")
end)
run("per-instance authored hotbar layouts resolve before the shared family",function()
  local generic,specific=plan(node("Button","Wide")),plan(node("Button","Tall"))
  local a,b="lib/compiled/windows/generic.lua","lib/compiled/windows/specific.lua"
  local I=fixture({version=2,windows={HotButtonWnd=a,HotButtonWnd2=b}})
  files[a]=generic;files[b]=specific
  equal(R.Resolve("HotButtonWnd2",I),specific);equal(R.Resolve("HotButtonWnd3",I),generic)
end)
run("after-control enrichment stays clipped and unwinds failures",function()
  local I=fixture();local previous=R.Bindings.AfterControl
  R.Bindings.AfterControl=function(screen,n,b,owner,renderer)
    equal(screen,"Test");equal(n.name,"Slot");equal(owner,I);equal(renderer,R);check(S.clips>0)
    error("enrichment failure")
  end
  local ok,why=pcall(R.Draw,"Test",plan(node("InvSlot","Slot")),I,box)
  R.Bindings.AfterControl=previous
  equal(ok,false);check(why:find("enrichment failure",1,true));equal(S.clips,0)
end)
run("unavailable native gauges paint nothing while special bands retain fill",function()
  local I=fixture();local g=node("Gauge","Missing");g.gaugeEqType=16;S.noChildGauge=true;S.unavailableGauge=true
  R.Draw("Test",plan(g),I,box);equal(#S.draws,0);equal(#S.texts,0)
  for _,e in ipairs(S.events) do check(e.kind~="fill" and e.kind~="border","unavailable track must remain hidden") end
  S.unavailableGauge=false;S.specialGauge=true;S.events={};R.Draw("Test",plan(g),I,box)
  local painted=false;for _,e in ipairs(S.events) do if e.kind=="fill" and e.args[5]==0.5 then painted=true end end
  check(painted,"native special negative values already supply a visible fill")
end)
run("gauge offsets caps fill lines and caption use source geometry",function()
  local I,index=artFixture();index.templates.G={fields={Background="A",Fill="B",Lines="C",LinesFill="D",EndCapLeft="E",EndCapRight="F"}}
  local gauge=node("Gauge","HP",0,0,100,30,{GaugeOffsetX=3,GaugeOffsetY=16,TextOffsetX=7,TextOffsetY=2,DrawLinesFill=true})
  gauge.art.drawTemplate="G";R.Draw("Test",plan(gauge),I,box)
  equal(S.draws[1][2],13);equal(S.draws[1][3],36);equal(S.draws[1][5]-S.draws[1][3],8)
  equal(#S.draws,6);equal(S.texts[1][1],17);equal(S.texts[1][2],22)
end)
run("partial gauge templates preserve transparent draw layers",function()
  local I,index=artFixture()
  index.templates.TrackOnly={fields={Background="A"}}
  index.templates.FillOnly={fields={Fill="B"}}
  index.templates.FrameOnly={fields={Lines="C"}}
  for _, template in ipairs({"TrackOnly", "FillOnly", "FrameOnly"}) do
    local gauge=node("Gauge",template,0,0,80,16)
    gauge.art.drawTemplate=template
    S.events,S.draws={},{}
    R.PaintControl("Test",gauge,box,I,{fraction=0.6,caption=""})
    equal(#S.draws,1,"only the authored gauge layer is drawn")
    for _, event in ipairs(S.events) do check(event.kind~="fill","omitted layers remain transparent") end
  end
  local gauge=node("Gauge","Name",0,0,80,16)
  S.events,S.draws={},{}
  R.PaintControl("Test",gauge,box,I,{caption="Group member",textOnly=true})
  equal(#S.draws,0)
  equal(#S.events,0)
  equal(S.texts[#S.texts][7],"Group member")
end)
run("health boxes shade downward and keep unavailable status distinct",function()
  local I=fixture()
  local function shade(fraction, tint)
    S.events={}
    R.PaintHealthBox(I,box,fraction,tint)
    local paint=S.events[1]
    equal(paint.kind,"gradient")
    equal(paint.args[1],box.x);equal(paint.args[4],box.y+box.h)
    equal(S.events[2].kind,"border")
    return paint.args
  end
  local healthy=shade(1)
  local wounded=shade(0)
  local neutral=shade(nil)
  local remote=shade(nil,{0.5,0,0.5,1})
  check(healthy[6]>healthy[5] and healthy[6]>healthy[10],"healthy green darkens down the box")
  check(wounded[5]>wounded[6] and wounded[5]>wounded[9],"low HP red darkens down the box")
  equal(neutral[5],neutral[9]);equal(neutral[6],neutral[10])
  check(remote[7]>remote[6] and remote[7]>remote[11],"explicit status tint takes precedence")
end)
run("linear layout skips hidden children and fills remaining client extent",function()
  local I=fixture();local flow=node("HorizontalLayoutBox","Flow",0,0,200,50,{Spacing=5,PaddingLeft=4,PaddingRight=6,PaddingTop=2,PaddingBottom=3,Style_Dividers=false})
  flow.children={node("Button","A",99,99,40,20),node("Button","Hidden",0,0,40,20),node("Button","B",99,99,30,20)}
  R.Draw("Test",plan(flow),I,box)
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[#hits+1]=e.args end end
  equal(#hits,2);equal(hits[1][2],14);equal(hits[1][3],22);equal(hits[1][5],45)
  equal(hits[2][2],59);equal(hits[2][4],145)
end)
run("tile flow wraps and honors reverse source anchors",function()
  local I=fixture();local flow=node("TileLayoutBox","Tiles",0,0,100,70,{Spacing=5,SecondarySpacing=7,AnchorToLeft=false,AnchorToTop=false,FirstPieceTemplate=true})
  flow.children={node("Button","A",0,0,40,20),node("Button","B",0,0,90,90),node("Button","C",0,0,12,10)}
  R.Draw("Test",plan(flow),I,box)
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[#hits+1]=e.args end end
  equal(#hits,3,"the first real gem or buff remains visible")
  equal(hits[1][1],"##pack:A");equal(hits[1][2],70);equal(hits[1][3],70);equal(hits[2][2],25)
  equal(hits[2][4],40);equal(hits[3][2],70);equal(hits[3][3],43)
end)
run("explicitly hidden prototypes still supply cell size without occupying space",function()
  local I=fixture();local flow=node("TileLayoutBox","Tiles",0,0,100,70,{Spacing=5,FirstPieceTemplate=true})
  flow.children={node("Button","Prototype",0,0,40,20),node("Button","A",0,0,90,90),node("Button","B",0,0,12,10)}
  S.visibleChildren.Prototype=false
  R.Draw("Test",plan(flow),I,box)
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[#hits+1]=e.args end end
  equal(#hits,2);equal(hits[1][1],"##pack:A");equal(hits[1][2],10);equal(hits[1][4],40)
  equal(hits[2][2],55);equal(hits[2][4],40)
end)
run("source layout strategies use padding and fail before unsupported parent resizing",function()
  local I,index=fixture();index.templates.Flow={type="LayoutVertical",fields={Padding=3}}
  local flow=node("LayoutBox","Flow",0,0,100,70,{Layout="Flow",Spacing=4})
  flow.children={node("Label","A",33,33,30,10),node("Label","B",33,33,30,10)}
  R.Draw("Test",plan(flow),I,box);equal(S.texts[1][1],13);equal(S.texts[1][2],23);equal(S.texts[2][2],37)
  index.templates.Resize={type="LayoutHorizontal",fields={ResizeVertical=true}};flow.fields.Layout="Resize"
  local p=plan(flow);local ok,why=R.CanDraw(p,I,"Test");equal(ok,false);check(why:find("Parent-size",1,true))
end)
run("linear dividers resize neighbors without changing host action targets",function()
  local I=fixture();local flow=node("HorizontalLayoutBox","Flow",0,0,200,40,{Spacing=5,ResizeLast=true,Style_Dividers=true})
  flow.children={node("Button","A",0,0,50,40,{MinHSize=20}),node("Button","B",0,0,50,40,{MinHSize=30})}
  local p=plan(flow);S.active["##divider:Flow:1"]=true;S.mx=60;S.down[0]=true;R.Draw("Test",p,I,box)
  S.mx=85;R.Draw("Test",p,I,box);S.active={};S.down={};S.events={};R.Draw("Test",p,I,box)
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[#hits+1]=e.args end end
  equal(hits[1][1],"##pack:A");equal(hits[1][4],75);equal(hits[2][1],"##pack:B");equal(hits[2][4],120)
  equal(#actions("windows","ClickChild"),0)
end)
run("compiled data survives code updates and retains the current caller",function()
  local path="lib/compiled/windows/ab123456.lua"
  local index={version=2,windows={Test=path},images={},animations={},templates={}}
  local I=fixture(index);files[path]=plan(node("Button","SavedLayout"));S.caller="plugin.fixture"
  local first=R.Resolve("Test",I);check(first);equal(first.children[1].name,"SavedLayout")
  -- No generated file is available to dofile; replacing the presentation module
  -- leaves the independent LoadData store and its selected layout untouched.
  local updated=syntheticRenderer(realDofile("shared/renderer.lua"))
  local after=updated.New({id=I.profile.id,index="lib/compiled/index.lua",revision="new-code"})
  equal(updated.Resolve("Test",after).children[1].name,"SavedLayout")
  S.click["##pack:SavedLayout"]=true;updated.Draw("Test",updated.Resolve("Test",after),after,box)
  equal(actions("windows","ClickChild")[1][4],"SavedLayout")
  local sawOwn,sawBase=false,false
  for _,event in ipairs(S.events) do
    if event.kind=="data" and event.args[3]=="plugin.fixture" then
      if event.args[2] then sawBase=true else sawOwn=true end
    end
  end
  check(sawOwn);check(sawBase);equal(S.caller,"plugin.fixture")
end)
run("inventory slot parsing is bounded and preserves raw source identity",function()
  local B=R.Bindings
  for n=0,32 do equal(B.InventorySlot(n),n);equal(B.InventorySlot("inventory/Equip "..n),n);equal(B.InventorySlot(tostring(n)),n) end
  for n=0,9 do equal(B.InventorySlot("inventory/General "..n),23+n) end
  local bad=table.pack(nil,false,{},-1,33,1.5,math.huge,0/0,"", "-1","33","1.5","1e1",
    "inventory/Equip -1","inventory/Equip 33","inventory/Equip 1 suffix","inventory/Equip1",
    "inventory/General 10","inventory/General -1","bank/Equip 0"," inventory/Equip 0","inventory/Equip 0 ")
  for n=1,bad.n do equal(B.InventorySlot(bad[n]),nil,"invalid source slot") end
  local slot=node("InvSlot","InvSlot32");slot.slot="inventory/Equip 32";S.inventoryItem={name="Carried item"}
  equal(B.Item("InventoryWindow",slot),S.inventoryItem)
  B.ItemClick("InventoryWindow",slot,"rightupheld",true)
  local a=actions("inventory","ClickSlot")[1];equal(a[3],32);equal(a[5],"rightupheld");equal(a[6],true)
  equal(slot.slot,"inventory/Equip 32","the raw compiled field is not rewritten")
  slot.slot="inventory/Equip 33";B.ItemClick("InventoryWindow",slot,"left",false);equal(#actions("inventory","ClickSlot"),1)
end)
run("themed icon wells use source artwork UV opacity and square semantic rings",function()
  local I,index=artFixture();index.animations.A_InvSlot=index.animations.B
  local T={};R.StyleTheme(T,I);local texture={};S.last="ExistingSlot";S.x=91;S.y=92
  check(T.Icon(10,20,40,2,texture,0.1,0.2,0.7,0.8,{1,0.3,0.2,0.6},{alpha=0.5,wellAlpha=0.25}))
  equal(S.draws[1][6],8/64);equal(S.draws[1][13],0.25,"well opacity")
  equal(S.draws[2][1],texture);equal(S.draws[2][2],13);equal(S.draws[2][6],0.1);equal(S.draws[2][9],0.8);equal(S.draws[2][13],0.5,"icon opacity")
  local ring=S.events[#S.events];equal(ring.kind,"border");equal(ring.args[8],0.3);equal(ring.args[9],0,"source square geometry");equal(ring.args[10],3)
  equal(S.last,"ExistingSlot");equal(S.x,91);equal(S.y,92);equal(#actions("windows","ClickChild"),0)
end)
run("icon frame fallback and hover cues retain existing input registration",function()
  local I,index=artFixture();index.templates.B={fields={Normal="C"}};index.style.button={template="B"}
  local T={};R.StyleTheme(T,I);S.last="HoveredSlot";S.hover=true
  equal(T.Icon(0,0,40,1,nil,nil,nil,nil,nil,nil,{}),false);equal(S.draws[1][6],16/64)
  T.HoverFx(0,0,40,40,1,8);local e=S.events[#S.events];equal(e.kind,"border");equal(e.args[9],0);equal(S.last,"HoveredSlot")
  S.active.HoveredSlot=true;T.HoverFx(0,0,40,40,1,8);e=S.events[#S.events];equal(e.kind,"fill");equal(e.args[8],0.25);equal(e.args[9],0)
  for _,event in ipairs(S.events)do check(event.kind~="hit","theme drawing must not register an item")end
end)
run("source checkbox decals retain checked hover and disabled states",function()
  local I,index=artFixture();index.templates.Check={fields={NormalDecal="A",PressedDecal="B",DisabledDecal="C",PressedDisabledDecal="D",
    FlybyDecal="E",PressedFlybyDecal="F"}};index.style.checkbox={template="Check"}
  local cases={{checked=false,expected=0},{checked=true,expected=8},{enabled=false,expected=16},
    {enabled=false,checked=true,expected=24},{hovered=true,expected=32},{hovered=true,checked=true,expected=40}}
  for _,opts in ipairs(cases)do
    S.draws={};opts.caption="Setting";R.DecorateWidget(I,"Checkbox",box,opts)
    equal(#S.draws,1);equal(S.draws[1][6],opts.expected/64)
  end
  index.templates.Check.fields.PressedFlybyDecal="";S.draws={}
  R.DecorateWidget(I,"Checkbox",box,{checked=true,hovered=true});equal(S.draws[1][6],8/64,"empty schema hover default retains checked artwork")
end)
run("button base and decal layers remain independent with model overrides",function()
  local I,index=artFixture();index.templates.Button={fields={Normal="A",Pressed="B",Disabled="C",PressedDisabled="D",NormalDecal="E",PressedDecal="F"}}
  local n=node("Button","Setting");n.art.drawTemplate="Button";S.hover=false;S.states.Setting={checked=true}
  R.Draw("Test",plan(n),I,box);equal(#S.draws,2);equal(S.draws[1][6],8/64);equal(S.draws[2][6],40/64)
  S.draws={};S.states.Setting={enabled=false,checked=true};R.Draw("Test",plan(n),I,box);equal(S.draws[1][6],24/64)
  S.draws={};S.states.Setting={checked=false};S.art["Setting:decal"]=table.pack(false)
  R.Draw("Test",plan(n),I,box);equal(#S.draws,1,"explicit model-hidden decal must not show the source default")
  S.draws={};S.art["Setting:decal"]=nil;S.art["Setting:background"]=table.pack("G")
  R.Draw("Test",plan(n),I,box);equal(#S.draws,2);equal(S.draws[1][6],48/64);equal(S.draws[2][6],32/64)
end)
run("nonsquare button decals retain source offset size scale and state",function()
  local I,index=artFixture()
  index.templates.Coin={fields={Normal="A",Pressed="B",Disabled="C",Flyby="D",NormalDecal="E",PressedDecal="F",DisabledDecal="G"}}
  local n=node("Button","Money",5,6,70,24,{DecalOffset={X=1,Y=3},DecalSize={CX=18,CY=18}})
  n.art.drawTemplate="Coin"
  for _,case in ipairs({{base=0,decal=32},{checked=true,base=8,decal=40},{enabled=false,base=16,decal=48},{hover=true,base=24,decal=32}})do
    S.draws={};S.events={};S.hover=case.hover==true;S.states.Money={enabled=case.enabled,checked=case.checked}
    R.Draw("Test",plan(n),I,{x=10,y=20,w=400,h=200,s=2})
    equal(#S.draws,2);local base,decal=S.draws[1],S.draws[2]
    equal(base[2],20);equal(base[3],32);equal(base[4]-base[2],140);equal(base[5]-base[3],48)
    equal(decal[2],22);equal(decal[3],38);equal(decal[4]-decal[2],36);equal(decal[5]-decal[3],36)
    equal(base[6],case.base/64);equal(decal[6],case.decal/64)
    local target;for _,e in ipairs(S.events)do if e.kind=="hit"then target=e.args end end
    equal(target[4],140);equal(target[5],48,"decal bounds must not shrink the input target")
  end
end)
run("live button atlas cells use decal bounds and retain model hide semantics",function()
  local I,index=artFixture();index.templates.Coin={fields={Normal="A",NormalDecal="E"}}
  local n=node("Button","Money",5,6,70,24,{DecalOffset={X=1,Y=3},DecalSize={CX=18,CY=18}})
  n.art.drawTemplate="Coin";local texture={};S.hover=false
  S.art["Money:decal"]=table.pack(texture,0.2,0.3,0.4,0.5)
  R.Draw("Test",plan(n),I,box);equal(#S.draws,2)
  local decal=S.draws[2];equal(decal[1],texture);equal(decal[2],16);equal(decal[3],29)
  equal(decal[4],34);equal(decal[5],47);equal(decal[6],0.2);equal(decal[9],0.5)
  S.draws={};S.art["Money:decal"]=table.pack(false);R.Draw("Test",plan(n),I,box)
  equal(#S.draws,1,"explicitly hidden live decal must not resurrect the source default")
  S.draws={};S.art["Money:decal"]=table.pack("F");R.Draw("Test",plan(n),I,box)
  equal(S.draws[2][2],16);equal(S.draws[2][4],34);equal(S.draws[2][6],40/64)
  n.fields.DecalSize={CX=0,CY=0};S.draws={};R.Draw("Test",plan(n),I,box)
  equal(#S.draws,1,"explicit zero-sized prototype decals remain hidden")
end)
run("live item icons replace grid prototype backdrops and preserve state layers",function()
  local I,index=artFixture()
  index.animations.RedIconBackground=index.animations.A;index.animations.A_InvSlot=index.animations.B
  index.animations.BuffIcons={grid=true,frames={}}
  index.templates.Item={fields={Normal="RedIconBackground",NormalDecal="BuffIcons",Flyby="C",Pressed="D"}}
  local n=node("Button","IconButton",0,0,44,44,{DecalOffset={X=2,Y=2},DecalSize={CX=40,CY=40}})
  n.art.drawTemplate="Item";local texture={};S.art["IconButton:decal"]=table.pack(texture,0.1,0.2,0.3,0.4);S.hover=false
  R.Draw("Test",plan(n),I,box);equal(#S.draws,2);equal(S.draws[1][6],8/64,"selected neutral item well replaces prototype red")
  equal(S.draws[2][1],texture);equal(S.draws[2][2],12);equal(S.draws[2][3],22);equal(S.draws[2][4],52);equal(S.draws[2][5],62)
  S.draws={};S.hover=true;R.Draw("Test",plan(n),I,box);equal(S.draws[1][6],16/64,"authored hover overlay stays independent")
  S.draws={};S.hover=false;S.states.IconButton={checked=true};R.Draw("Test",plan(n),I,box)
  equal(S.draws[1][6],24/64,"authored checked overlay stays independent")
  S.draws={};S.states={};S.art["IconButton:background"]=table.pack("RedIconBackground");R.Draw("Test",plan(n),I,box)
  equal(#S.draws,2);equal(S.draws[1][6],0,"explicit host red background is real state, not a placeholder")
  S.draws={};S.art["IconButton:background"]=nil;S.art["IconButton:decal"]=nil;R.Draw("Test",plan(n),I,box)
  equal(S.draws[1][6],0,"source artwork remains authoritative without a live replacement")
end)
run("button captions retain source alignment and offsets separately from decals",function()
  local I=artFixture();S.text.Money={"123",true};S.hover=false
  local n=node("Button","Money",0,0,70,24,{TextAlignCenter=true,TextAlignVCenter=true,TextOffsetX=2,TextOffsetY=-1})
  R.Draw("Test",plan(n),I,box);equal(S.texts[1][1],10+(70-21)/2+2);equal(S.texts[1][2],24)
  S.texts={};n.fields.TextAlignRight=true;R.Draw("Test",plan(n),I,box)
  equal(S.texts[1][1],61,"right alignment overrides the schema's centered default")
end)
run("prepared wrapped button captions reuse the exact input and action path once",function()
  local I,index=artFixture();index.templates.Buy={fields={Normal="A",Pressed="B"}}
  local id="IDW_Appearance_Socket_Buy_Button"
  local n=node("Button",id,0,0,100,40);n.art.drawTemplate="Buy";n.sourceItemCaption="Buy\nAppearance Slot"
  S.text[id]={"Unwrapped live caption",true};S.click["##pack:"..id]=true;S.hover=false
  local original=R.Bindings.DrawControl
  R.Bindings.DrawControl=function(screen,child,at,instance,renderer)
    if child.sourceItemCaption~=nil then renderer.DrawButton(screen,child,at,instance,child.sourceItemCaption);return true end
    return original(screen,child,at,instance,renderer)
  end
  R.Draw("ItemDisplayWindow#3",plan(n),I,box)
  R.Bindings.DrawControl=original
  equal(#S.texts,1);equal(S.texts[1][7],n.sourceItemCaption,"explicit line breaks must reach native text painting")
  local clicked=actions("windows","ClickChild");equal(#clicked,1);equal(clicked[1][3],"ItemDisplayWindow#3");equal(clicked[1][4],id);equal(clicked[1][5],"left")
  local hits=0;for _,event in ipairs(S.events)do if event.kind=="hit"then hits=hits+1 end end
  equal(hits,1,"the presenter wrapper must not recursively register another button")
  equal(S.draws[1][6],0,"the prepared caption retains source button artwork")
  S.texts={};S.click={};R.DrawButton("ItemDisplayWindow#3",n,box,I,"");equal(#S.texts,0,"empty override hides the host caption")
  R.DrawButton("ItemDisplayWindow#3",n,box,I);equal(S.texts[1][7],"Unwrapped live caption","nil keeps the normal live caption")
end)
run("dynamic presenters measure and paint the selected source font without input changes",function()
  local I=artFixture();local n=node("Label","Detail",0,0,80,20,{AlignRight=true});n.font=5;n.colors.TextColor={0.2,0.3,0.4,1}
  local original=ui.PushFont;local selected
  ui.PushFont=function(value)selected=value;original(value)end
  local w,h=R.MeasureText(I,n,"Detail");equal(w,42);equal(h,14);equal(selected,5)
  S.mx=15;S.my=25;R.PaintText("Test",n,{x=10,y=20,w=80,h=20,s=1},I,"Value")
  equal(selected,5);equal(S.texts[1][1],55);equal(S.texts[1][3],0.2);equal(S.texts[1][7],"Value")
  for _,e in ipairs(S.events)do check(e.kind~="hit","paint-only text must not steal input")end
  S.texts={};S.states.Detail={enabled=false};R.PaintText("Test",n,box,I,"Disabled")
  equal(S.texts[1][3],I.palette.disabled[1])
  ui.PushFont=original
  local previous=ui.CalcTextSize;ui.CalcTextSize=function()error("synthetic measurement failure")end
  check(not pcall(R.MeasureText,I,n,"Failure"));equal(S.fonts,0,"measurement errors must restore the font stack")
  ui.CalcTextSize=previous
end)
run("dialog frame-only chrome cannot paint a background middle or titlebar",function()
  local I,index=artFixture()
  index.templates.Border={fields={TopLeft="A",Top="A",TopRight="A",Left="A",Middle="C",Right="A",BottomLeft="A",Bottom="A",BottomRight="A"}}
  index.templates.Title={fields={Middle="D"}}
  index.templates.Window={fields={Background="B",Border="Border",Titlebar="Title"}}
  index.style.frame={template="Window"}
  check(R.Chrome(I,box,{frameOnly=true,titleHeight=30}));equal(#S.draws,8)
  for _,draw in ipairs(S.draws)do equal(draw[6],0,"only source edge pieces")end
  for _,event in ipairs(S.events)do check(event.kind~="fill","outer frame must not wipe existing controls")end
  local token=R.PushStyle(I);equal(token.vars,7,"window popup tab grab and scrollbar geometry are square");R.PopStyle(token)
end)
run("dialog background-only chrome excludes frame titlebar and fallback borders",function()
  local I,index=artFixture()
  index.templates.Border={fields={Top="A",Middle="C"}};index.templates.Title={fields={Middle="D"}}
  index.templates.Window={fields={Background="B",Border="Border",Titlebar="Title"}};index.style.frame={template="Window"}
  check(R.Chrome(I,box,{backgroundOnly=true,titleHeight=30}));equal(#S.draws,1);equal(S.draws[1][6],8/64)
  for _,event in ipairs(S.events)do check(event.kind~="border","body must not draw a duplicate frame")end
  local missing=fixture();S.events={};R.Chrome(missing,box,{backgroundOnly=true})
  equal(#S.events,1);equal(S.events[1].kind,"fill","missing image still has a coherent plain background")
end)
run("unindexed item atlases are never stretched over ordinary buttons",function()
  local I,index=artFixture();index.animations.Icons={grid=true,frames={{image="atlas",rect={x=0,y=0,w=64,h=32}}},fields={CellWidth=8,CellHeight=8}}
  equal(R.Animation(I,"Icons",box),false);equal(#S.draws,0);check(#R.Diagnostics(I)>0)
  index.templates.B={fields={Normal="A",NormalDecal="Icons"}};index.style.button={template="B"}
  R.DecorateWidget(I,"Button",box,{caption="Save"});equal(#S.draws,1);equal(S.draws[1][6],0)
end)
run("existing host models and familiar source IDs cannot authorize unaudited behavior",function()
  local I,index=fixture();local p=plan(node("Button","Save"));S.click["##pack:Save"]=true
  local ok,why=R.Draw("GroupWindow",p,I,box);equal(ok,false);check(why:find("not audited",1,true));equal(#actions("windows","ClickChild"),0)
  equal(R.testProductionCompatible("InventoryWindow",p),false)
  equal(R.CanDraw(plan(node("Label","GroupMember1")),I,"GroupWindow"),false,"a label may own target clicks")
  local path="lib/compiled/windows/ab123456.lua";index.windows.GroupWindow=path;files[path]=p
  local called=0;local wrapped=R.Wrap("Group",function()called=called+1;return 41 end,I.profile,"GroupWindow")
  equal(wrapped(),41);equal(called,1);equal(#actions("windows","ClickChild"),0)
end)
run("audited read-only air meter retains real air percentage and critical warning",function()
  local I=fixture();local gauge=node("Gauge","Gauge",0,0,100,10);gauge.gaugeEqType=8
  local p=plan(gauge);p.name="BreathWindow";p.item="BreathWindow"
  S.noChildGauge=true;S.air=0.2;check(R.CanDraw(p,I,"BreathWindow"));check(R.Draw("BreathWindow",p,I,box));equal(S.texts[1][7],"20%")
  equal(S.texts[1][8],10,"critical percentage fits the source's narrow air gauge")
  local first;for _,event in ipairs(S.events)do if event.kind=="fill"then first=event.args end end
  check(first);local initial=first[8];S.events={};S.time=math.pi/10;R.Draw("BreathWindow",p,I,box)
  for _,event in ipairs(S.events)do if event.kind=="fill"then check(event.args[8]<=initial)end end
  p.children[2]=node("Button","CustomAction");equal(R.testProductionCompatible("BreathWindow",p),false)
  p.children[2]=nil;p.fields.DefaultControl="CustomAction";equal(R.testProductionCompatible("BreathWindow",p),false)
  p.fields.DefaultControl=nil;gauge.gaugeEqType=1;equal(R.testProductionCompatible("BreathWindow",p),false)
end)
run("theme bar explicit opacity multiplies artwork and caption once",function()
  local I,index=artFixture();index.templates.G={fields={Background="A",Fill="B"}};index.style.gauge={template="G"}
  local T={};R.StyleTheme(T,I);T.Bar("breath",0,0,100,10,1,0.5,{1,0.2,0.3,1},{alpha=0.4,center="Half"})
  equal(S.draws[1][13],0.4);equal(S.draws[2][13],0.4);equal(S.texts[1][6],0.4)
  equal(I.palette.text[4],1,"shared palette alpha is not mutated")
end)
run("audited casting and aggro graphs accept only verified live value types",function()
  local I,index=fixture()
  local cast=node("Gauge","Gauge");cast.gaugeEqType=7
  local name=node("Label","Casting_SpellName");name.eqType=134
  local p=plan(cast,name);check(R.CanDraw(p,I,"CastingWindow"));check(R.Draw("CastingWindow",p,I,box))
  local gauge=node("Gauge","AggroGauge");gauge.gaugeEqType=149
  local controls={gauge}
  for _,kind in ipairs({302,303,305,307})do local label=node("Label","Value"..kind);label.eqType=kind;controls[#controls+1]=label end
  controls[#controls+1]=node("Label","LiteralPercent");controls[#controls].eqType="";controls[#controls].text="%"
  local aggro=plan(table.unpack(controls));check(R.CanDraw(aggro,I,"AggroMeterWnd"));check(R.Draw("AggroMeterWnd",aggro,I,box))
  controls[2].eqType=999;equal(R.testProductionCompatible("AggroMeterWnd",aggro,I),false)
  name.eqType=305;equal(R.testProductionCompatible("CastingWindow",p,I),false)
  name.eqType=134;p.children[3]=node("Editbox","UnauditedInput");equal(R.testProductionCompatible("CastingWindow",p,I),false)
  p.children[3]=nil;local art=node("StaticAnimation","SpellAtlas");art.art.animation="Grid"
  index.animations.Grid={grid=true};p.children[3]=art;equal(R.testProductionCompatible("CastingWindow",p,I),false)
  check(R.CanDraw(plan(name),I,"CastingWindow"),"authored label-only cast layout still reads its live spell name")
  local percentage=node("Label","Percent");percentage.eqType=305;check(R.CanDraw(plan(percentage),I,"AggroMeterWnd"))
  equal(R.CanDraw(plan(node("Label","Literal")),I,"CastingWindow"),false,"literal-only status cannot replace live data")
end)
run("audited aura list routes removal and reserves Alt right click for the frame menu",function()
  local I=fixture();local p=plan(node("Listbox","AuraList",0,0,180,80));S.rows=1
  S.mouse[1]={["##row:0"]=true};check(R.CanDraw(p,I,"AuraWindow"));check(R.Draw("AuraWindow",p,I,box))
  local calls=actions("windows","ListClick");equal(#calls,1);equal(calls[1][3],"AuraWindow");equal(calls[1][4],"AuraList");equal(calls[1][5],0);equal(calls[1][6],"right")
  S.events={};S.io.alt=true;R.Draw("AuraWindow",p,I,box);equal(#actions("windows","ListClick"),0)
  S.noList=true;local ok,why=R.CanDraw(p,I,"AuraWindow");equal(ok,false);check(why:find("data unavailable",1,true))
  S.noList=false;p.children[1].name="UnknownAuraList";equal(R.testProductionCompatible("AuraWindow",p,I),false)
end)
run("audited respawn keeps selection timer disabled rows and exact button identity",function()
  local I=fixture();local gauge=node("Gauge","TimeGauge");gauge.gaugeEqType=28
  local select=node("Button","SelectButton");local list=node("Listbox","OptionsList",0,25,200,50)
  local p=plan(gauge,list,select);S.rows=1;S.rowDisabled=true;S.click["##row:0"]=true;S.states.SelectButton={enabled=false};S.click["##pack:SelectButton"]=true
  check(R.Draw("RespawnWnd",p,I,box));equal(#actions("windows","ListClick"),0);equal(#actions("windows","ClickChild"),0)
  S.rowDisabled=false;S.states.SelectButton={enabled=true};S.events={};R.Draw("RespawnWnd",p,I,box)
  local a=actions("windows","ClickChild");equal(#a,1);equal(a[1][3],"RespawnWnd");equal(a[1][4],"SelectButton");equal(a[1][5],"left")
  p.children[4]=node("Button","UnknownRespawnButton");equal(R.testProductionCompatible("RespawnWnd",p,I),false)
end)
run("audited label action aliases dispatch only documented phases",function()
  local I=fixture();local gauge=node("Gauge","TimeGauge");gauge.gaugeEqType=28
  local p=plan(gauge,node("Listbox","OptionsList"),node("Label","SelectButton"));S.click["##label:SelectButton"]=true;S.mouse[1]={["##label:SelectButton"]=true}
  check(R.Draw("RespawnWnd",p,I,box));local a=actions("windows","ClickChild");equal(#a,1);equal(a[1][4],"SelectButton");equal(a[1][5],"left")
end)
run("list double-click is registered and a drag cannot also activate a row",function()
  local I=fixture();local p=plan(node("Listbox","List",0,0,200,80));S.rows=1;S.click["##row:0"]=true;S.double=true
  R.Draw("Test",p,I,box);local a=actions("windows","ListClick");equal(#a,2);equal(a[1][6],"left");equal(a[2][6],"double")
  local flags;for _,event in ipairs(S.events)do if event.kind=="selectable" and event.args[1]=="##row:0" then flags=event.args[2]end end
  check(flags&ui.SelectableFlags.AllowDoubleClick~=0)
  S.events={};S.active["##row:0"]=true;S.drag=true;S.pickupMade=true;R.Draw("Test",p,I,box)
  equal(#actions("windows","ListClick"),0);equal(#actions("cursor","PickUp"),1)
end)
run("selected source identity cannot silently borrow an uncompiled parent's index",function()
  serial=serial+1;files={["lib/compiled/index.lua"]={version=2,skin="default",windows={Test="lib/compiled/windows/a.lua"}}}
  parentFiles={["lib/compiled/index.lua"]=files["lib/compiled/index.lua"]}
  local missing=R.New({id="missing-selected"..serial,source="aya-stock",index="lib/compiled/index.lua"})
  equal(next(missing.index.windows),nil);check(R.Diagnostics(missing)[1]:find("does not match the selected interface",1,true))
  files["lib/compiled/index.lua"]={version=2,skin="AYA-STOCK",windows={},images={},animations={},templates={}}
  local own=R.New({id="correct-selected"..serial,source="aya-stock",index="lib/compiled/index.lua"})
  check(own.index.windows.Test,"a verified selected index can still inherit sparse Default maps")
end)
run("invalid atlas crops never wrap arbitrary texture pixels",function()
  local I,index=artFixture();index.animations.Bad={frames={{image="atlas",rect={x=60,y=0,w=8,h=8}}}}
  equal(R.Animation(I,"Bad",box),false);equal(#S.draws,0);check(#R.Diagnostics(I)>0)
  for _,crop in ipairs({{x=-1,y=0,w=8,h=8},{x=0,y=0,w=0,h=8},{x=0,y=0,w=8,h=math.huge}})do
    index.animations.Bad.frames[1].rect=crop;equal(R.Animation(I,"Bad",box),false)
  end
  check(R.Animation(I,"A",box));equal(#S.draws,1,"valid atlas drawing remains usable")
end)
local function textPrompt()
  S.text.Prompt={"Enter a name",true};S.text.Entry={"",true};S.applyText=true
  return plan(node("Label","Prompt"),node("Editbox","Entry",0,25,160,20),node("Button","OK",0,50,70,20),node("Button","Cancel",80,50,70,20))
end
run("text entry focuses each opening and writes text before Enter validation",function()
  local I=fixture();local p=textPrompt();S.minimum=3;S.maximum=5;S.input="xy";S.enter=true
  R.TrackWindow("TextEntryWnd",true,I);check(R.Draw("TextEntryWnd",p,I,box));equal(S.accepted,nil,"backend minimum is not bypassed")
  local focus=0;local setAt,clickAt
  for n,event in ipairs(S.events)do
    if event.kind=="focus"then focus=focus+1 end
    if event.kind=="input"then equal(event.args[2],256);check(event.args[3]&ui.InputTextFlags.EnterReturnsTrue~=0)end
    if event.kind=="action" and event.args[2]=="SetText"then setAt=n end
    if event.kind=="action" and event.args[2]=="ClickChild"then clickAt=n end
  end
  equal(focus,1);check(setAt<clickAt);equal(actions("windows","ClickChild")[1][4],"Entry")
  S.events={};S.input="valid_name";R.TrackWindow("TextEntryWnd",true,I);R.Draw("TextEntryWnd",p,I,box)
  equal(S.accepted,true);equal(S.text.Entry[1],"valid","model owns the request maximum")
  for _,event in ipairs(S.events)do check(event.kind~="focus","focus is not stolen every frame")end
  R.TrackWindow("TextEntryWnd",false,I);R.TrackWindow("TextEntryWnd",true,I);S.events={};S.enter=false;S.input=nil
  R.Draw("TextEntryWnd",p,I,box);focus=0;for _,event in ipairs(S.events)do if event.kind=="focus"then focus=focus+1 end end;equal(focus,1)
end)
run("text entry obeys disabled OK and never dispatches Enter from another model",function()
  local I=fixture();local p=textPrompt();S.minimum=2;S.click["##pack:OK"]=true;S.enter=false
  check(R.Draw("TextEntryWnd",p,I,box));equal(#actions("windows","ClickChild"),0);equal(S.accepted,nil)
  p.children[2].fields.Style_Multiline=true;equal(R.testProductionCompatible("TextEntryWnd",p,I),false)
  p.children[2].fields.Style_Multiline=false;S.text.Entry={"",false};equal(R.CanDraw(p,I,"TextEntryWnd"),false,"a familiar ID without supplied model text is unavailable")
end)
run("text entry refocuses after a hidden presenter skips HUD entirely",function()
  local I=fixture();local p=textPrompt()
  local function frame(n)
    S.frame=n;S.events={};R.TrackWindow("TextEntryWnd",true,I);check(R.Draw("TextEntryWnd",p,I,box))
    local focused=0;for _,event in ipairs(S.events)do if event.kind=="focus"then focused=focused+1 end end
    return focused
  end
  equal(frame(10),1);equal(frame(11),0)
  -- The original callback returns before HUD on frames 12 and 13.
  equal(frame(14),1);equal(frame(15),0)
end)
local function confirmation()
  S.text.TextOutput={"<c \"#ffffff\">Question</c>",true}
  S.visibleChildren={Yes_Button=true,No_Button=true,OK_Button=false,Cancel_Button=false}
  return plan(node("STMLbox","TextOutput",0,0,200,60),node("Button","Yes_Button",0,65,60,20),
    node("Button","No_Button",70,65,60,20),node("Button","OK_Button",0,65,60,20),node("Button","Cancel_Button",140,65,60,20))
end
run("confirmation uses backend modes without any implicit Enter acceptance",function()
  local I=fixture();local p=confirmation();S.enter=true
  check(R.Draw("ConfirmationDialogBox",p,I,box));equal(S.answered,nil);equal(#actions("windows","ClickChild"),0)
  S.click["##pack:Yes_Button"]=true;R.Draw("ConfirmationDialogBox",p,I,box);equal(S.answered,true);equal(S.answer,true)
  S.events={};S.answered=nil;S.answer=nil;S.visibleChildren={Yes_Button=false,No_Button=false,OK_Button=true,Cancel_Button=false}
  S.click["##pack:OK_Button"]=true;R.Draw("ConfirmationDialogBox",p,I,box)
  local a=actions("windows","ClickChild");equal(#a,1);equal(a[1][4],"OK_Button");equal(S.answer,false,"OK intentionally uses the backend false answer")
  S.text.TextOutput={"",false};S.events={};equal(R.Draw("ConfirmationDialogBox",p,I,box),false,"expired/closed model cannot remain as a blank source question")
  equal(#actions("windows","ClickChild"),0)
end)
run("confirmation rejects missing mode controls or a visible unsupported Cancel",function()
  local I=fixture();local p=confirmation();S.visibleChildren.Cancel_Button=true
  equal(R.CanDraw(p,I,"ConfirmationDialogBox"),false)
  S.visibleChildren.Cancel_Button=false;p.children[4]=nil;p.children[5]=nil
  equal(R.testProductionCompatible("ConfirmationDialogBox",p,I),false)
end)
run("STML uses the real link-table contract and resets new questions to the top",function()
  local I=fixture();local p=confirmation();S.stmlLink=true;S.scroll=150
  check(R.Draw("ConfirmationDialogBox",p,I,box));equal(S.scroll,0)
  local a=actions("windows","StmlLink")[1];equal(a[3],"ConfirmationDialogBox");equal(a[4],"TextOutput");equal(a[5],27);equal(a[6],"item:123")
  S.stmlView.cum={1,2};S.stmlView.cumKey=13;S.text.TextOutput={"A different question",true};S.scroll=80
  R.Draw("ConfirmationDialogBox",p,I,box);equal(S.scroll,0);equal(S.stmlView.cum,nil)
end)
run("STML draw failures restore child font and clipping before propagating",function()
  local I=fixture();S.stmlError=true
  local ok,why=pcall(R.Draw,"Test",plan(node("STMLbox","Description")),I,box)
  equal(ok,false);check(why:find("synthetic STML draw failure",1,true));equal(S.children,0);equal(S.fonts,0);equal(S.clips,0)
end)
run("narrow STML source rows remove implicit padding and wrap to the real child viewport",function()
  local I=fixture();local p=plan(node("STMLbox","SocketDescription",0,0,90,18))
  S.childAvail={74,18};S.text.SocketDescription={"General: empty",true}
  R.Draw("Test",p,I,box)
  check(S.beginChildZeroPadding,"a source text row must not lose16 pixels to inherited child padding")
  equal(S.stmlArgs[1],74,"wrapping uses content width after actual scrollbars, not the90-pixel source box")
  equal(S.stmlArgs[2],18,"the full source row remains available for a native14-pixel font")
  check(S.stmlArgs[2]>=select(2,ui.CalcTextSize("Wg il")),"one native text line must fit without tiny scrollbars")
  local key=S.stmlArgs[3];S.scroll=37;S.childAvail={58,18};R.Draw("Test",p,I,box)
  equal(S.scroll,37,"resizing preserves the reader's scroll position");check(S.stmlArgs[3]~=key,"width changes invalidate cached line heights")
  key=S.stmlArgs[3];R.Draw("Test",p,I,box);equal(S.stmlArgs[3],key,"stable viewport and font reuse wrapped heights")
  local previous=ui.CalcTextSize;ui.CalcTextSize=function(value)return #value*8,16 end
  R.Draw("Test",p,I,box);check(S.stmlArgs[3]~=key,"actual font metrics invalidate wrapped heights")
  ui.CalcTextSize=previous
end)
run("STML retains a bounded viewport when WindowPadding is unavailable",function()
  local padding=ui.StyleVar.WindowPadding;ui.StyleVar.WindowPadding=nil
  local I=fixture();S.childAvail={46,14};R.Draw("Test",plan(node("STMLbox","Description",0,0,80,30)),I,box)
  equal(S.stmlArgs[1],46);equal(S.stmlArgs[2],14)
  ui.StyleVar.WindowPadding=padding
end)
run("named vertical strategy retains anchor-sized zero-Size gem containers",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Vertical={type="LayoutVertical",fields={Padding=2,ResizeHorizontal=true,ResizeVertical=true}}}})
  local root=plan();root.fields.Layout="Vertical"
  local tile=node("TileLayoutBox","Gems",0,0,0,0,{AutoStretch=true,Spacing=2,SecondarySpacing=2,HorizontalFirst=true,FirstPieceTemplate=true})
  tile.anchors={leftToLeft=true,rightToLeft=false,topToTop=true,bottomToTop=false,explicit={}}
  tile.children={node("Button","Gem0",0,0,20,10),node("Button","Gem1",0,0,20,10),node("Button","Gem2",0,0,20,10)}
  root.children={tile}
  local at={x=10,y=20,w=100,h=60,s=1}
  local w,h=R.MeasureChildren("Test",root,I,at);equal(w,98);equal(h,58)
  R.DrawChildren("Test",root,I,at)
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[e.args[1]]=e.args end end
  equal(hits["##pack:Gem0"][2],12);equal(hits["##pack:Gem0"][3],22)
  equal(hits["##pack:Gem1"][2],34);equal(hits["##pack:Gem2"][2],56)
  equal(hits["##pack:Gem0"][4],20);equal(hits["##pack:Gem0"][5],10)
  equal(tile.rect.w,0,"source geometry is not rewritten");equal(tile.rect.h,0)
end)
run("named strategies resize requested axes and retain excluded anchored children",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Horizontal={type="LayoutHorizontal",fields={Padding=2,ResizeHorizontal=false,ResizeVertical=true}}}})
  local root=plan();root.fields={Layout="Horizontal",Spacing=4}
  root.children={node("Button","A",0,0,30,10,{AutoStretchVertical=true}),node("Button","B",0,0,40,20),
    node("Button","OutsideFlow",1,3,8,9,{UseInLayoutHorizontal=false})}
  R.DrawChildren("Test",root,I,{x=10,y=20,w=100,h=60,s=1})
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[e.args[1]]=e.args end end
  equal(hits["##pack:A"][2],12);equal(hits["##pack:A"][3],22);equal(hits["##pack:A"][4],30);equal(hits["##pack:A"][5],56)
  equal(hits["##pack:B"][2],46);equal(hits["##pack:B"][5],20,"fixed child height is retained")
  equal(hits["##pack:OutsideFlow"][2],11);equal(hits["##pack:OutsideFlow"][3],23)
  S.events={};I.index.templates.Horizontal.fields.ResizeVertical=false
  R.DrawChildren("Test",root,I,{x=10,y=20,w=100,h=60,s=1})
  for _,e in ipairs(S.events)do if e.kind=="hit"and e.args[1]=="##pack:A"then equal(e.args[5],10,"disabled resize axis keeps authored height")end end
end)
run("named vertical strategy shares only its remaining span among stretch children",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Vertical={type="LayoutVertical",fields={Padding=2,ResizeHorizontal=true,ResizeVertical=true}}}})
  local root=plan();root.fields={Layout="Vertical",Spacing=4}
  root.children={node("Button","A",0,0,0,0,{AutoStretch=true}),node("Button","B",0,0,0,0,{AutoStretch=true}),node("Button","Fixed",0,0,30,10)}
  R.DrawChildren("Test",root,I,{x=10,y=20,w=100,h=80,s=1})
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[e.args[1]]=e.args end end
  equal(hits["##pack:A"][5],29);equal(hits["##pack:B"][5],29)
  equal(hits["##pack:A"][4],96);equal(hits["##pack:Fixed"][4],30)
  equal(hits["##pack:B"][3],55);equal(hits["##pack:Fixed"][3],88)
end)
run("source gauge caption offsets retain the enclosing client clip",function()
  local I=fixture();S.text={}
  local g=node("Gauge","OffsetGauge",20,25,90,18,{TextOffsetX=-3,TextOffsetY=-2})
  R.Draw("Test",plan(g),I,box)
  local clip
  for _,e in ipairs(S.events) do
    if e.kind=="clip" and e.args[1]==27 and e.args[2]==43 then clip=e.args;break end
  end
  check(clip,"the logical gauge clip must include the negative caption offset")
  equal(clip[3],120);equal(clip[4],63);equal(clip[5],true,"parent window clipping remains authoritative")
end)
run("source gauges retain authored caption color independently of fill tint",function()
  local I=fixture();local g=node("Gauge","ColoredGauge")
  g.colors.TextColor={0,0,0,1};g.colors.FillTint={0,1,0,1}
  R.Draw("Test",plan(g),I,box)
  equal(#S.texts,1);equal(S.texts[1][3],0);equal(S.texts[1][4],0);equal(S.texts[1][5],0)
  equal(S.texts[1][7],"50%")
end)
run("inherited inventory gestures can select per-cell source artwork without creating input",function()
  local I=artFixture();local T={};R.StyleTheme(T,I)
  local n=node("InvSlot","SourceEar");n.art.background="A";I.sourceSlotNode=n
  T.Icon(10,20,40,1,nil,0,0,1,1,nil,{wellAlpha=1})
  equal(#S.draws,1);equal(S.draws[1][6],0);equal(S.draws[1][8],8/64)
  for _,e in ipairs(S.events)do check(e.kind~="hit" and e.kind~="action","visual scope cannot consume inventory input")end
  I.sourceSlotNode=nil
end)
run("embedded source hotbuttons use their declared canonical bar for actions and drags",function()
  local I=fixture();local old=R.Bindings.HotTarget
  R.Bindings.HotTarget=function(screen,n)equal(screen,"Test");equal(n.name,"Embedded");return "HotButtonWnd9","HB_Button2" end
  S.click["##hot:Embedded"]=true
  local ok,why=pcall(R.Draw,"Test",plan(node("HotButton","Embedded")),I,box)
  R.Bindings.HotTarget=old;check(ok,why)
  local a=actions("hotbars","Click");equal(#a,1);equal(a[1][3],"HotButtonWnd9");equal(a[1][4],"HB_Button2")
  R.Bindings.HotTarget=function()return "HotButtonWnd9","HB_Button2" end
  S.events={};S.click={};S.active["##hot:Embedded"]=true;S.drag=true;S.pickupMade=true
  ok,why=pcall(R.Draw,"Test",plan(node("HotButton","Embedded")),I,box)
  R.Bindings.HotTarget=old;check(ok,why)
  a=actions("cursor","PickUp");equal(#a,1);equal(a[1][3],"HotButtonWnd9");equal(a[1][4],"HB_Button2")
  equal(#actions("hotbars","Click"),0)
end)
run("decorative nested screens paint their own template while clipping masks stay bare",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Inner={type="WindowDrawTemplate",fields={}}}})
  local previous=R.WindowChrome;local calls={}
  R.WindowChrome=function(n,title,at,owner,opts)
    calls[#calls+1]={node=n,title=title,at=at,owner=owner,opts=opts}
    check(S.clips>0,"nested chrome stays inside the source parent clip")
  end
  local panel=node("Screen","InnerPanel",5,6,80,50,{Style_Border=true,Style_Transparent=false})
  panel.art.drawTemplate="Inner";panel.children={node("Label","Child",0,0,30,12)}
  local mask=node("Screen","GaugeMask",90,0,25,10,{Style_Border=false,Style_Transparent=true})
  mask.art.drawTemplate="Inner";mask.children={node("Gauge","Oversized",0,0,8000,8)}
  local unstyled=node("Screen","LayoutOnly",0,70,30,12,{Style_Border=true})
  R.DrawChildren("Test",plan(panel,mask,unstyled),I,box)
  equal(#calls,1);equal(calls[1].node.name,"InnerPanel");equal(calls[1].node.art.drawTemplate,"Inner")
  equal(calls[1].at.x,15);equal(calls[1].at.y,26);equal(calls[1].opts.close,false)
  equal(mask.rect.w,25);equal(mask.children[1].rect.w,8000,"mask geometry remains authored")
  S.events={};calls={};panel.fields.Style_Transparent=true
  R.DrawChildren("Test",plan(panel),I,box)
  equal(#calls,1,"transparent background can still have its authored border")
  equal(calls[1].node.fields.Style_Transparent,true);equal(calls[1].node.fields.Style_Border,true)
  R.WindowChrome=previous
end)
run("selected source pages paint once before their children without changing tab actions",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Inner={type="WindowDrawTemplate",fields={}}}})
  local previous=R.WindowChrome;local count=0
  R.WindowChrome=function()count=count+1 end
  local page=node("Page","Page",0,0,100,80,{Style_Border=true,Style_Transparent=true})
  page.art.drawTemplate="Inner";page.children={node("Label","Child",2,3,30,12)}
  local tab=node("TabBox","Tabs",0,0,100,100);tab.children={page}
  R.DrawChildren("Test",plan(tab),I,box);equal(count,1)
  count=0;R.DrawChildren("Test",page,I,box);equal(count,1)
  equal(#actions("windows","SetTabPage"),0,"painting never selects a page")
  R.WindowChrome=previous
end)
run("opaque nested window backgrounds underlay target siblings and paint only once",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Inner={type="WindowDrawTemplate",fields={Background="opaque.tga"}}}})
  local prior=R.WindowChrome;local painted=0;local textCount
  R.WindowChrome=function()painted=painted+1;textCount=#S.texts;record("nested-background")end
  local label=node("Label","TargetName",3,0,108,14);label.text="Guard Bob"
  local container=node("Screen","BuffWindow",0,0,0,0,{Style_Border=false,Style_Titlebar=false,Style_Transparent=false})
  container.art.drawTemplate="Inner"
  container.anchors={rightToLeft=false,bottomToTop=false,explicit={left=true,top=true,right=true,bottom=true}}
  container.children={node("Button","Buff0",0,30,24,24)}
  R.DrawChildren("Test",plan(label,container),I,box)
  equal(painted,1,"the source background is retained without a second foreground repaint")
  equal(textCount,0,"the opaque background is painted before preceding source labels")
  local found=false;for _,t in ipairs(S.texts)do if t[7]=="Guard Bob"then found=true end end
  check(found,"target label retains its authored text")
  local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[#hits+1]=e.args[1]end end
  equal(hits[1],"##pack:Buff0","container inputs and children retain their source order")
  R.WindowChrome=prior
end)
run("nested chrome underlay failures restore clipping and leave source geometry unchanged",function()
  local I=fixture({version=2,windows={},images={},animations={},templates={Inner={type="WindowDrawTemplate",fields={}}}})
  local prior=R.WindowChrome;local p=node("Screen","Panel",4,5,60,20,{Style_Border=true})
  p.art.drawTemplate="Inner";R.WindowChrome=function()error("synthetic chrome failure")end
  local ok,why=pcall(R.DrawChildren,"Test",plan(p),I,box)
  R.WindowChrome=prior
  equal(ok,false);check(tostring(why):find("synthetic chrome failure",1,true)~=nil)
  equal(S.clips,0);equal(p.rect.x,4);equal(p.paintedChromeNode,nil,"paint bookkeeping stays on ephemeral rectangles")
  R.DrawChildren("Test",plan(p),I,box)
end)
run("presenter coverage uses anchored geometry and parent clips without drawing or actions",function()
  local I=fixture();local anchored=node("SpellGem","Anchored",0,0,0,0)
  anchored.anchors={leftToLeft=true,topToTop=true,rightToLeft=false,bottomToTop=false,
    explicit={left=true,top=true,right=true,bottom=true}}
  local panel=node("Screen","Clip",50,0,20,20)
  panel.children={node("Button","Outside",30,0,10,10),node("Gauge","Long",15,0,8000,8)}
  local root=plan(anchored,node("Button","Zero",0,0,0,0),node("Button","Hidden"),panel)
  local seen={};R.VisitChildren("Test",root,I,{x=0,y=0,w=100,h=80,s=1},function(n,r,v)seen[n.name]={r,v}end)
  equal(seen.Anchored[1].w,100);equal(seen.Anchored[1].h,80)
  equal(seen.Zero,nil);equal(seen.Hidden,nil);equal(seen.Outside,nil)
  equal(seen.Long[1].w,8000);equal(seen.Long[2].w,5,"intrinsic width cannot escape its clipping parent")
  equal(#S.draws,0);equal(#S.texts,0)
  for _,e in ipairs(S.events)do check(e.kind~="hit"and e.kind~="action","coverage traversal is read only")end
end)
run("presenter coverage may include reachable inactive pages without changing selected tabs",function()
  local I=fixture();local a=node("Page","PageA");a.children={node("Button","SlotA",0,0,20,12)}
  local b=node("Page","PageB");b.children={node("Button","SlotB",0,0,20,12)}
  local tabs=node("TabBox","Tabs",0,0,80,60);tabs.children={a,b}
  local root=plan(tabs);local selected={}
  R.VisitChildren("Test",root,I,box,function(n)selected[n.name]=true end)
  check(selected.SlotA);equal(selected.SlotB,nil)
  local all={};R.VisitChildren("Test",root,I,box,function(n)all[n.name]=true end,{allPages=true})
  check(all.SlotA and all.SlotB);equal(#actions("windows","SetTabPage"),0);equal(#S.draws,0)
end)
run("scroll content coverage preserves authored geometry and nested clipping",function()
  local I=fixture();local below=node("Gauge","Below",10,140,0,20)
  below.anchors={leftToLeft=true,rightToLeft=false,topToTop=true,bottomToTop=true,
    left=10,right=5,top=140,bottom=160,explicit={left=true,right=true,top=true,bottom=true}}
  local panel=node("Screen","Panel",0,180,100,20)
  panel.children={node("Gauge","NestedClipped",0,30,80,15)}
  local root=plan(below,panel);local client={x=0,y=0,w=100,h=80,s=1}
  local seen={};R.VisitChildren("Test",root,I,client,function(n)seen[n.name]=true end)
  equal(seen.Below,nil)
  seen={};R.VisitChildren("Test",root,I,client,function(n,r)seen[n.name]=r end,
    {clip={x=0,y=0,w=100,h=400,s=1}})
  equal(seen.Below.w,85,"virtual clipping cannot stretch the source geometry box")
  equal(seen.Below.y,140);equal(seen.NestedClipped,nil,"fixed nested panels still clip their descendants")
  equal(#S.draws,0);equal(#S.texts,0)
end)
run("noninteger scaled exact-fit tiles keep five pieces per row or column",function()
  local scale=1.5*((720-12*1.5)/(550*1.5))
  for _,horizontal in ipairs{true,false}do
    local I=fixture();local tile=node("TileLayoutBox","ExactFit",0,0,200,200,
      {HorizontalFirst=horizontal,Spacing=0,SecondarySpacing=0})
    for n=1,6 do tile.children[n]=node("Button","Piece"..n,0,0,40,40)end
    -- Resolve a 200-design-pixel region against the far edge of a larger
    -- parent, just like a right/bottom anchored inventory tile. Subtraction
    -- introduces a different rounding path than multiplying each 40px piece.
    tile.rect.w,tile.rect.h=horizontal and 200 or 120,horizontal and 120 or 200
    tile.anchors=horizontal and{leftToLeft=false,left=200,rightToLeft=false,right=0,explicit={left=true,right=true}}
      or{topToTop=false,top=200,bottomToTop=false,bottom=0,explicit={top=true,bottom=true}}
    local at=R.Geometry(tile,{x=0,y=0,w=520*scale,h=520*scale,s=scale})
    S.events={};R.DrawChildren("Test",tile,I,at)
    local hits={};for _,e in ipairs(S.events)do if e.kind=="hit"then hits[e.args[1]]=e.args end end
    local axis=horizontal and 3 or 2
    local start=horizontal and at.y or at.x
    equal(hits["##pack:Piece5"][axis],start,"the fifth piece exactly fits the first span")
    equal(hits["##pack:Piece6"][axis],start+40*scale,"the sixth piece starts the next span")
    local seen={};R.VisitChildren("Test",tile,I,at,function(n,r)seen[n.name]=r end)
    equal(horizontal and seen.Piece5.y or seen.Piece5.x,start)
    equal(horizontal and seen.Piece6.y or seen.Piece6.x,start+40*scale,"paint and coverage share the exact-fit decision")
    -- A real subpixel deficit is much larger than the arithmetic error bound.
    if horizontal then at.w=at.w-0.0000001 else at.h=at.h-0.0000001 end
    seen={};R.VisitChildren("Test",tile,I,at,function(n,r)seen[n.name]=r end)
    equal(horizontal and seen.Piece5.y or seen.Piece5.x,start+40*scale,"genuine overflow still wraps")
  end
end)
run("verified shared artwork is used only when its selected original is missing",function()
  for _,entry in ipairs({
    {"uifiles/qqcustom-stock/CS_Buttons.bmp","uifiles/qqui-stock/CS_Buttons.bmp",256,256,4,4,124,20},
    {"uifiles/qqui-stock/Buff_Background.tga","uifiles/DuxaUI-stock/Buff_Background.tga",64,128,1,1,24,124},
  })do
    local original,shared,w,h=table.unpack(entry)
    local I=fixture({version=2,windows={},images={Sheet={path=original}},animations={Shared={frames={{image="Sheet",rect={x=entry[5],y=entry[6],w=entry[7],h=entry[8]}}}}}})
    S.assetInfo={[original]=false,[shared]={"shared",w,h}};S.draws={}
    check(R.Animation(I,"Shared",box));equal(S.draws[1][1],"shared");equal(S.draws[1][6],entry[5]/w)
    local reported=false;for _,message in ipairs(R.Diagnostics(I))do if message:find("compatible shared artwork",1,true)then reported=true end end
    check(reported,"fallback provenance remains explicit")
    S.frame=S.frame+1;S.assetInfo[original]={"original",w,h};S.events={};S.draws={}
    check(R.Animation(I,"Shared",box));equal(S.draws[1][1],"original")
    for _,event in ipairs(S.events)do if event.kind=="asset"then equal(event.args[1],original,"recovered originals take precedence")end end
  end
end)
run("shared artwork with incompatible dimensions never substitutes a sheet",function()
  local original,shared="uifiles/qqcustom-stock/CS_Buttons.bmp","uifiles/qqui-stock/CS_Buttons.bmp"
  local I=fixture({version=2,windows={},images={Sheet={path=original}}})
  S.assetInfo={[original]=false,[shared]={"wrong",512,256}}
  equal(R.Animation(I,"Sheet",box),false);equal(#S.draws,0)
end)
run("ambiguous same-name source atlases keep their diagnosed themed fallback",function()
  local original="uifiles/Graphite-stock/window_pieces21.tga"
  local I=fixture({version=2,windows={},images={Sheet={path=original}}});S.assetInfo={[original]=false}
  equal(R.Animation(I,"Sheet",box),false)
  local calls=0;for _,event in ipairs(S.events)do if event.kind=="asset"then calls=calls+1;equal(event.args[1],original)end end
  equal(calls,1);equal(#S.draws,0)
end)
run("packaged layouts load selected code and the approved default base",function()
  S.bundled=true
  local own="lib/layouts/windows/00112233445566778899aabb.lua"
  local base="lib/layouts/windows/01112233445566778899aabb.lua"
  local selected,shared=plan(),plan()
  files={["lib/layouts/index.lua"]={version=2,storage="buckets-v1",windows={Selected=own}},
    ["lib/layouts/buckets/00.lua"]={[own]=selected}}
  parentFiles={["lib/layouts/index.lua"]={version=2,storage="buckets-v1",windows={Inherited=base}},
    ["lib/layouts/buckets/01.lua"]={[base]=shared}}
  local I=R.New({id="packaged",index="lib/layouts/index.lua"})
  equal(R.Resolve("Selected",I),selected);equal(R.Resolve("Inherited",I),shared)
  local baseIndex,baseBucket=false,false
  for _,event in ipairs(S.events)do
    check(event.kind~="data","the bundled loader does not inspect external data")
    if event.kind=="base" then
      baseIndex=baseIndex or event.args[1]=="lib/layouts/index.lua"
      baseBucket=baseBucket or event.args[1]=="lib/layouts/buckets/01.lua"
    end
  end
  check(baseIndex and baseBucket,"both inherited index and bucket use the approved base")
end)
run("bundled artwork takes precedence and is looked up once per frame",function()
  local atlas="assets/"..string.rep("a",64)..".png"
  local original="uifiles/test/atlas.tga"
  local I=fixture({version=2,windows={},images={Sheet={path=original,interface_path=atlas}}})
  S.interfaceImages={[atlas]={"bundled",64,32}}
  check(R.Animation(I,"Sheet",box));check(R.Animation(I,"Sheet",box))
  equal(S.draws[1][1],"bundled");equal(S.draws[2][1],"bundled")
  local calls=0
  for _,event in ipairs(S.events)do
    check(event.kind~="asset","available bundled artwork needs no game-file lookup")
    if event.kind=="interfaceAsset"then calls=calls+1;equal(event.args[1],atlas)end
  end
  equal(calls,1)
  S.frame=S.frame+1;S.interfaceImages={};S.assetInfo={[original]={"game",64,32}};S.draws={}
  check(R.Animation(I,"Sheet",box));equal(S.draws[1][1],"game","missing bundled art retains game fallback")
end)
run("older UI APIs keep game artwork without an InterfaceImage method",function()
  local method=rawget(api.assets,"InterfaceImage");rawset(api.assets,"InterfaceImage",nil)
  local ok,why=xpcall(function()
    local atlas="assets/"..string.rep("b",64)..".png"
    local I=fixture({version=2,windows={},images={Sheet={path="uifiles/test/atlas.tga",interface_path=atlas}}})
    check(R.Animation(I,"Sheet",box));equal(S.draws[1][1],"tex:uifiles/test/atlas.tga")
  end,debug.traceback)
  rawset(api.assets,"InterfaceImage",method);assert(ok,why)
end)
print(string.format("Lua renderer: %d cases, %d assertions passed",passed,assertions))
