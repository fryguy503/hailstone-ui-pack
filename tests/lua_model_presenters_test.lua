-- Pure contract fixtures exercise the real adapter and dispatchers. They do not
-- claim GPU/art validation; the native capture matrix supplies that evidence.
local root=arg[1] or "."
local checks=0
local function eq(a,b)checks=checks+1;assert(a==b,tostring(a).." ~= "..tostring(b))end
local function check(value)eq(value and true or false,true)end
local calls,actions,missingList,modelPresent={},0,nil,true
local bagCount,combine=12,false
local currentContext={instance={messages={}}}
local function event(name,...)
  calls[#calls+1]={name,...}
end
local function action(...)actions=actions+1;event("action",...);return true end
local modules={
  ["lib/stml.lua"]={DrawLines=function()error("Preflight must not draw")end},
  ["lib/items.lua"]={Tooltip=function(...)event("tooltip",...)end},
  ["lib/extensions.lua"]={RaidContext=function()event("context");return {selection={name="Current member"}}end,
    Draw=function(...)event("extensions",...)end}
}
hs={UI={Supports=function()return true end,
  windows={ChildState=function()if modelPresent then return true,false,7,101,false end end,
    ChildShown=function()return nil end,ClickChild=action,
    Text=function()return "live",true end,SetText=action,
    ListInfo=function(_,name)event("list",name);if name~=missingList then return 3,2,-1,{"Name","Value"},{100,40}end end,
    ListRow=function()return {"row","value"}end,ListClick=action,ListHeaderClick=action,
    ComboInfo=function()return {"One","Two"},0 end,ComboSelect=action,
    TabPage=function()return 0 end,SetTabPage=action,SetSlider=action,StmlLink=action},
  inventory={SlotItem=function(_,name)return {name=name,icon=1}end,
    BagInfo=function()return "A real bag",bagCount,combine end,
    BagSlotItem=function(_,n)return n==0 and {name="First",icon=1} or nil end,BagSlotClick=action},
  compare={SlotItem=function()return {source="slot"}end,BagSlotItem=function()return {source="bag"}end},
  extensions={ListActions=function(_,_,ctx)eq(ctx.selection.name,"Current member");return {{handle="opaque",enabled=true}}end}
}}
ui={IsItemHovered=function()return true end,SetCursorScreenPos=function(...)event("cursor",...)end,
  BeginChild=function(...)event("begin",...);return true end,EndChild=function()event("end")end}
local original=dofile
dofile=function(path)
  if path=="lib/pack_context.lua"then return currentContext end
  if modules[path]then return modules[path]end
  error("Unexpected adapter import: "..path)
end
local M=original(root.."/shared/model_presenters.lua")
local B=original(root.."/shared/bindings.lua")
local function node(kind,name,children)
  return {type=kind,name=name,item=name,rect={x=0,y=0,w=40,h=40},fields={},anchors={},children=children or {}}
end
local function plan(children)
  local p=node("Screen","Source",children);p.rect={x=0,y=0,w=300,h=220};return p
end
local instance=currentContext.instance
local cases={
  {"BankWnd",{node("InvSlot","BW_BankSlot0"),node("Button","BW_Money0"),node("Button","DoneButton")}},
  {"BigBankWnd",{node("InvSlot","BIGB_SharedBankSlot0")}},
  {"GiveWnd",{node("InvSlot","GVW_MyItemSlot0"),node("Button","GVW_Give_Button")}},
  {"TradeWnd",{node("InvSlot","TRDW_TradeSlot15"),node("Button","TRDW_Trade_Button")}},
  {"LootWnd",{node("InvSlot","LW_LootSlot0"),node("Button","LootAllButton")}},
  {"MerchantWnd",{node("Listbox","ItemList"),node("Editbox","MW_Send_To_Edit"),node("TabBox","MW_MerchantSubwindows")}},
  {"TradeskillWnd",{node("Listbox","RecipeList"),node("Editbox","SearchTextEdit"),node("Button","CombineButton")}},
  {"SkillsWindow",{node("Listbox","SkillList"),node("Button","MakeHotKeyButton")}},
  {"TrainWindow",{node("Listbox","SkillList"),node("Button","TrainButton")}},
  {"AAWindow",{node("Listbox","List1"),node("Listbox","List4"),node("TabBox","Subwindows"),node("Button","HotButton")}},
  {"SpellBookWnd",{node("Button","SBW_Spell0"),node("Button","SBW_Spell15"),node("Button","SBW_PageUp_Button")}},
  {"TaskWnd",{node("Listbox","TASK_TaskList"),node("Listbox","TASK_TaskElementList"),node("STMLbox","TASK_Description"),node("TabBox","TaskSubwindows")}},
  {"RaidWindow",{node("Listbox","RAID_PlayerList"),node("Listbox","RAID_NotInGroupPlayerList"),node("Editbox","MOTDInput")}},
  {"RaidOptionsWindow",{node("Combobox","RAIDOPTIONS_SetLootTypeCombo"),node("Button","RAIDOPTIONS_ClassColor0")}},
  {"RealEstateManageWnd",{node("Listbox","REMW_Name_List"),node("Combobox","REMW_Access_Combobox"),node("Combobox","REMW_Groups_Combobox")}},
  {"GuildManagementWnd",{node("Listbox","MemberList"),node("Editbox","PublicInput"),node("Button","InviteButton")}},
  {"QuantityWnd",{node("Slider","QTYW_Slider"),node("Editbox","QTYW_SliderInput")}},
}
for _,case in ipairs(cases)do
  check(M.Handles(case[1]));local ok,why=M.CanDraw(case[1],plan(case[2]),instance);check(ok or error(why))
end
eq(actions,0) -- listing/admission performs no gameplay action or display callback
check(#M.Coverage()>=60)
for _,screen in ipairs({"MapViewWnd","WebBrowserWnd","OptionsWindow","ObjectPreviewWnd","ItemExpTransferWnd","UnregisteredWindow"})do
  eq(M.Handles(screen),false);eq(M.CanDraw(screen,plan({}),instance),false)
end
modelPresent=false;eq(M.CanDraw("BankWnd",plan({}),instance),false);modelPresent=true
missingList="SkillList";eq(M.CanDraw("SkillsWindow",plan({node("Listbox","SkillList")}),instance),false);missingList=nil
eq(M.CanDraw("SkillsWindow",plan({node("Listbox","InventedList")}),instance),false)
eq(M.CanDraw("SkillsWindow",plan({node("Editbox","InventedEdit")}),instance),false)
eq(M.CanDraw("SkillsWindow",plan({node("TreeView","UnknownTree")}),instance),false)
local unavailable=hs.UI.windows.ListRow;hs.UI.windows.ListRow=nil
eq(M.CanDraw("SkillsWindow",plan({node("Listbox","SkillList")}),instance),false);hs.UI.windows.ListRow=unavailable
eq(M.CanDraw("BankWnd",plan({node("Button","InventedAction")}),instance),true)
eq(B.State("BankWnd",node("Button","InventedAction")),false)
check(instance.messages["source-control:BankWnd:InventedAction"])
eq(M.Events("BankWnd",node("InvSlot","BW_BankSlot0")).phases,true)
eq(M.Events("BankWnd",node("InvSlot","BW_BankSlot16")),nil)
eq(M.Events("SpellBookWnd",node("Button","SBW_Spell0")).phases,true)
eq(M.Events("SpellBookWnd",node("Button","SBW_Spell16")),nil)
hs.UI.hotbars={Info=function()return {}end,Click=action}
local pickups={}
hs.UI.cursor={HoldingButton=function()return false end,PickUp=function(...)pickups[#pickups+1]={...};return true end}
local hot=node("HotButton","Embedded");hot.eqType="hotbutton/Bar 8/0"
eq(M.CanDraw("BandolierWnd",plan({hot}),instance),true)
hot.eqType="hotbutton/Bar 10/0";eq(M.CanDraw("BandolierWnd",plan({hot}),instance),false)
ui.IsItemActive=function()return true end;ui.IsMouseDragging=function()return true end;ui.Mouse={Left=0}
check(B.Drag("SkillsWindow",node("Listbox","SkillList"),0));eq(pickups[1][3],1)
check(B.Drag("SkillsWindow",node("Listbox","SkillList"),1));eq(pickups[2][3],2)
hot.eqType="hotbutton/Bar 8/0";check(B.Drag("BandolierWnd",hot))
eq(pickups[3][1],"HotButtonWnd9");eq(pickups[3][2],"HB_Button1");eq(pickups[3][3],nil)
local inactive=node("Listbox","UnknownHiddenList");inactive.fields.Visible=false
eq(M.CanDraw("SkillsWindow",plan({inactive}),instance),true)
eq(M.CanDraw("GuildManagementWnd",plan({node("Combobox","GT_Ranks_Combobox")}),instance),true)
eq(M.Shown("GuildManagementWnd",node("Combobox","GT_Ranks_Combobox")),false)
eq(B.Input("TradeskillWnd",node("Editbox","SearchTextEdit")).enter,true)
eq(B.Input("QuantityWnd",node("Editbox","QTYW_SliderInput")).enter,true)
eq(B.Item("BankWnd",node("InvSlot","BW_BankSlot0")).name,"BW_BankSlot0")
eq(actions,0)
check(B.Click("BankWnd",node("Button","DoneButton"),"left"));eq(actions,1)
check(B.Click("TradeskillWnd",node("Editbox","SearchTextEdit"),"left"));eq(actions,2)
eq(calls[#calls][3],"SearchButton")

-- Containers copy their authored slot prototype into the selected source tile;
-- slots remain bag-owned, not aliased to inventory slots with the same number.
local container=plan({node("InvSlot","Container_Slot"),node("TileLayoutBox","ContainerStandard_Items"),
  node("TileLayoutBox","ContainerStandardWithDone_Items"),node("TileLayoutBox","ContainerCombine_Items"),
  node("Button","Container_Combine"),node("Button","StandardDoneButton"),node("Button","CombineDoneButton")})
local R={ChromeInsets=function()return {left=3,right=3,top=20,bottom=4,titleHeight=20}end,
  MeasureChildren=function(_,prepared,_,box)event("measure",prepared);return box.w,box.h end,
  Draw=function(screen,prepared,owner,box,adapter)
    eq(adapter,M);event("draw",screen,prepared,box);return true
  end}
local w,h=M.Size("Bag1",container,instance,R);eq(w,300);eq(h,220)
eq(M.CanDraw("Bag1",container,instance),true)
eq(B.Shown("Bag1",node("InvSlot","Container_Slot")),false)
eq(B.Shown("Bag1",node("TileLayoutBox","ContainerStandardWithDone_Items")),true)
eq(B.Shown("Bag1",node("TileLayoutBox","ContainerCombine_Items")),false)
eq(B.Item("Bag1",node("InvSlot","Container_Slot:0")).name,"First")
eq(B.Item("Bag1",node("InvSlot","Container_Slot:1")),nil)
check(B.ItemClick("Bag1",node("InvSlot","Container_Slot:0"),"rightheld",true));eq(actions,3)
local last=calls[#calls];eq(last[2],"Bag1");eq(last[3],0);eq(last[4],"rightheld");eq(last[5],true)
M.AfterControl("Bag1",node("InvSlot","Container_Slot:0"),{},instance)
last=calls[#calls];eq(last[1],"tooltip");eq(last[4].source,"bag")
M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
last=calls[#calls];eq(last[1],"draw")
local tile=last[3].children[3];eq(#tile.children,12);eq(tile.children[1].name,"Container_Slot:0")
eq(#container.children[3].children,0)
local property=plan({node("Combobox","REPW_Price_Combobox"),node("Button","REPW_Purchase_Button")})
eq(M.CanDraw("RealEstatePurchaseWnd",property,instance),true)
M.Draw("RealEstatePurchaseWnd",property,instance,{x=0,y=0,w=300,h=220,s=1},R)
local prepared=calls[#calls][3]
eq(prepared.children[1].name,"PriceCombo");eq(prepared.children[2].name,"PurchaseButton")
eq(property.children[1].name,"REPW_Price_Combobox")
local manage=plan({node("Listbox","REMW_Name_List"),node("Combobox","REMW_Access_Combobox"),node("Combobox","REMW_Groups_Combobox")})
M.Draw("RealEstateManageWnd",manage,instance,{x=0,y=0,w=300,h=220,s=1},R)
prepared=calls[#calls][3]
eq(prepared.children[1].name,"MemberList");eq(prepared.children[2].name,"MemberGroupCombo")
eq(prepared.children[3].name,"REMW_Groups_Combobox") -- never borrow the membership-edit handler
local book=plan({node("Editbox","Page0"),node("Editbox","Page1")})
eq(M.CanDraw("BookWindow",book,instance),true)
M.Draw("BookWindow",book,instance,{x=0,y=0,w=300,h=220,s=1},R)
eq(calls[#calls][3].children[1].fields.Style_ReadOnly,true)
eq(book.children[1].fields.Style_ReadOnly,nil)
bagCount=4;combine=true;M.Size("Bag1",container,instance,R)
eq(B.Shown("Bag1",node("TileLayoutBox","ContainerCombine_Items")),true)
eq(B.Shown("Bag1",node("InvSlot","Container_Slot:4")),false)
bagCount=0;eq(M.CanDraw("Bag1",container,instance),false);bagCount=4

-- Resolve the shipped source graph and exercise its real vertical/tile flow.
-- The live slot tile must reserve its complete last row before Done is placed;
-- large bags scroll at their authored scale instead of shrinking every slot.
do
  local skins={"default","default_old","aya-stock","delta-stock","drakah-pers-adeptus-stock","DuxaUI-stock",
    "Graphite-stock","ib-stock","lodidodi-stock","Lords-stock","Nemesis-stock","po2-stock","po2alt-stock",
    "qqcustom-stock","qqui-stock","sars-stock","Sparxx-stock","Takus-stock","vert-stock","wow-stock"}
  local skin="default"
  local savedDofile,owner,interfaces=dofile,currentContext.instance,hs.UI.interfaces
  local savedCount,savedCombine=bagCount,combine
  dofile=function(path)
    if path=="lib/pack_bindings.lua"then return B end
    if path:sub(1,12)=="lib/layouts/"then return original(root.."/layouts/"..skin.."/"..path:sub(13))end
    return savedDofile(path)
  end
  hs.UI.interfaces={LoadBase=function(path)return original(root.."/layouts/default/"..path:sub(13))end}
  local actual=original(root.."/shared/renderer.lua")
  actual.ChromeInsets=function()return {left=2,right=2,top=18,bottom=2}end
  local save={io=ui.GetIO,begin=ui.BeginChild,finish=ui.EndChild,pos=ui.SetCursorScreenPos,get=ui.GetCursorScreenPos,
    avail=ui.GetContentRegionAvail,dummy=ui.Dummy,flags=ui.WindowFlags,style=ui.StyleVar}
  ui.GetIO=function()return {width=1280,height=720,uiScale=1}end
  local defaultPlan,defaultInstance
  for _,name in ipairs(skins)do
    skin=name
    local profile=original(root.."/ui/"..skin.."/lib/pack_profile.lua")
    local live=actual.New(profile);local source=actual.Resolve("ContainerWindow",live);check(source)
    local slotHeight
    local function slotPrototype(n)
      if n.name=="Container_Slot"then slotHeight=n.rect.h end
      for _,child in ipairs(n.children or{})do slotPrototype(child)end
    end
    slotPrototype(source);check(slotHeight and slotHeight>0)
    currentContext.instance=live
    for _,count in ipairs({10,80,200})do
      bagCount=count;combine=false
      local outerW,outerH=M.Size("Bag1",source,live,actual)
      local fullW,fullH=M.ContentSize("Bag1",source,live,actual)
      local prepared=live.modelPresenters.Bag1.plan
      local slots,footer,bottom=0,nil,0
      actual.VisitChildren("Bag1",prepared,live,{x=0,y=0,w=fullW,h=fullH,s=1},function(n,at,visible)
        if (n.name or""):match("^Container_Slot:%d+$")then
          slots=slots+1;eq(at.h,slotHeight);eq(visible.h,at.h);eq(visible.w,at.w)
          bottom=math.max(bottom,at.y+at.h)
        elseif n.name=="StandardDoneButton"then footer=at end
      end)
      eq(slots,count)
      if footer then check(bottom<=footer.y+.00001);check(footer.y+footer.h<=fullH+.00001)end
      if count>=80 then check(fullH+20>outerH);check(outerH<=576)end
      check(M.OwnsScroll("Bag1",source))
    end
    local function pristine(n)
      if n.name=="ContainerStandardWithDone_Items"then eq(#n.children,0)end
      for _,child in ipairs(n.children or{})do pristine(child)end
    end
    pristine(source)
    if name=="default"then defaultPlan,defaultInstance=source,live end
  end
  currentContext.instance=defaultInstance;bagCount=200
  local depth,offset,canvas,extent=0,0,nil,nil
  ui.StyleVar=nil;ui.WindowFlags={HorizontalScrollbar=2048}
  ui.SetCursorScreenPos=function()end;ui.GetCursorScreenPos=function()return 10,20-offset end
  ui.GetContentRegionAvail=function()return 97,540 end
  ui.BeginChild=function(name,w,h)eq(name,"##source-container-client");eq(w,111);eq(h,540);depth=depth+1;return true end
  ui.EndChild=function()depth=depth-1 end;ui.Dummy=function(w,h)extent={w,h}end
  actual.Draw=function(_,_,_,at)canvas=at;return true end
  local beforeActions=actions
  M.Draw("Bag1",defaultPlan,defaultInstance,{x=10,y=20,w=111,h=540,s=1},actual)
  eq(depth,0);check(canvas.h>540);eq(canvas.s,1);eq(extent[2],canvas.h)
  offset=1000
  M.Draw("Bag1",defaultPlan,defaultInstance,{x=10,y=20,w=111,h=540,s=1},actual)
  eq(canvas.y,-980);eq(depth,0);eq(actions,beforeActions)
  actual.Draw=function()error("controlled bag paint failure")end
  local ok,why=pcall(M.Draw,"Bag1",defaultPlan,defaultInstance,{x=10,y=20,w=111,h=540,s=1},actual)
  eq(ok,false);check(tostring(why):find("controlled bag paint failure",1,true));eq(depth,0)
  eq(B.Shown("Bag1",node("InvSlot","Container_Slot:199")),true)
  eq(B.Shown("Bag1",node("InvSlot","Container_Slot:200")),false)
  local slotClick,clicked=hs.UI.inventory.BagSlotClick
  hs.UI.inventory.BagSlotClick=function(screen,n,phase)clicked={screen,n,phase};return true end
  check(B.ItemClick("Bag1",node("InvSlot","Container_Slot:199"),"rightheld"))
  eq(clicked[1],"Bag1");eq(clicked[2],199);eq(clicked[3],"rightheld")
  hs.UI.inventory.BagSlotClick=slotClick
  ui.GetIO,ui.BeginChild,ui.EndChild,ui.SetCursorScreenPos,ui.GetCursorScreenPos=save.io,save.begin,save.finish,save.pos,save.get
  ui.GetContentRegionAvail,ui.Dummy,ui.WindowFlags,ui.StyleVar=save.avail,save.dummy,save.flags,save.style
  currentContext.instance=owner;hs.UI.interfaces=interfaces;dofile=savedDofile;bagCount,combine=savedCount,savedCombine
end

-- The source Raid body retains the existing named addon section in a scrolling
-- footer. Metadata/preflight never invoke its display or action callbacks.
local before=#calls
M.Size("RaidWindow",plan({}),instance,R)
for n=before+1,#calls do eq(calls[n][1]~="extensions",true)end
M.Draw("RaidWindow",plan({}),instance,{x=10,y=20,w=300,h=332,s=1},R)
local drawn,section
for _,entry in ipairs(calls)do if entry[1]=="draw" and entry[2]=="RaidWindow"then drawn=entry end
  if entry[1]=="extensions"then section=entry end end
eq(drawn[4].h,220);eq(section[2],"RaidWindow");eq(section[3],"member_actions")
eq(calls[#calls][1],"end");eq(actions,3)
-- The actual HUD dispatcher chooses the model adapter before the older generic
-- audit gate, retains initializer side effects, and does not paint Modern body.
local preparedCount,modernBody=0,0
local sourcePlan=plan({node("Listbox","SkillList"),node("Button","MakeHotKeyButton")})
currentContext.renderer=R;currentContext.paths={}
R.Resolve=function()return sourcePlan end;R.TrackWindow=function()end;R.CanDraw=function()return false,"old audit gate"end
R.WindowChrome=function()eq(currentContext.sourceManagedPanel,false)end
local base={T={Hit=function()return false end}}
base.Window=function(screen,title,opts,body)local width,height=opts.size(1);body(0,0,width,height,1)end
base.Dialog=function()error("Model source body must use full outer frame")end
hs.UI.windows.Shown=function()return true end
hs.UI.interfaces={LoadBase=function(path)eq(path,"lib/hud.lua");return base end}
modules["lib/pack_source_presenters.lua"]={Handles=function()return false end,OpenTools=function()end,Tools=function()end}
modules["lib/pack_model_presenters.lua"]=M
ui.GetIO=function()return {width=1280,height=720,uiScale=1}end
ui.SetWindowFontScale=function()end;ui.PushClipRect=function()end;ui.PopClipRect=function()end
local H=original(root.."/shared/hud.lua")
H.Dialog("SkillsWindow","Skills",{size=function()preparedCount=preparedCount+1;return 500,600 end},function()modernBody=modernBody+1 end)
eq(preparedCount,1);eq(modernBody,0);eq(currentContext.paths.SkillsWindow,"source")
eq(currentContext.sourceManagedPanel,nil)

-- Host bag indices compact on close: Bag1 may immediately refer to the next
-- bag even though its visibility and capacity did not change.
do
  local saved={draw=R.Draw,info=hs.UI.inventory.BagInfo,item=hs.UI.inventory.BagSlotItem,
    slotClick=hs.UI.inventory.BagSlotClick,click=hs.UI.windows.ClickChild,shown=hs.UI.windows.Shown}
  local open={name="Same bag name",count=8,slot=23,combine=false}
  local live=true
  local clickCount,slotClicks,drawCount,itemReads=0,0,0,0
  hs.UI.windows.Shown=function()return live end
  hs.UI.inventory.BagInfo=function()
    if open then return open.name,open.count,open.combine,"inventory",open.slot end
  end
  hs.UI.inventory.BagSlotItem=function()itemReads=itemReads+1;return nil end -- an empty bag still has all of its slots
  hs.UI.inventory.BagSlotClick=function()slotClicks=slotClicks+1;return true end
  hs.UI.windows.ClickChild=function()
    clickCount=clickCount+1
    open={name="Same bag name",count=8,slot=24,combine=false}
    return true
  end
  M.Size("Bag1",container,instance,R)
  R.Draw=function()
    drawCount=drawCount+1
    eq(B.Item("Bag1",node("InvSlot","Container_Slot:0")),nil)
    check(B.Click("Bag1",node("Button","StandardDoneButton"),"left"))
    eq(M.Shown("Bag1",node("Button","StandardDoneButton")),false)
    eq(B.Click("Bag1",node("Button","StandardDoneButton"),"left"),false)
    eq(B.ItemClick("Bag1",node("InvSlot","Container_Slot:0"),"left"),false)
    eq(B.Item("Bag1",node("InvSlot","Container_Slot:0")),nil)
    local before=#calls
    M.AfterControl("Bag1",node("InvSlot","Container_Slot:0"),{},instance)
    eq(#calls,before);eq(itemReads,1)
    return true
  end
  local ok,why,closed=M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
  eq(ok,true);eq(why,nil);eq(closed,true);eq(clickCount,1);eq(slotClicks,0);eq(drawCount,1)
  check(live) -- closure cannot be inferred from Shown alone
  M.Size("Bag1",container,instance,R)
  R.Draw=function()
    drawCount=drawCount+1
    check(B.ItemClick("Bag1",node("InvSlot","Container_Slot:0"),"left"))
    return true
  end
  check(M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R));eq(slotClicks,1)
  -- Destruction/zoning between sizing and drawing quietly retires that frame.
  live=false;open=nil
  ok,why,closed=M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
  eq(ok,true);eq(closed,true);eq(drawCount,2)
  live=true;open={name="Reopened",count=4,slot=25,combine=true}
  M.Size("Bag1",container,instance,R)
  eq(M.Shown("Bag1",node("TileLayoutBox","ContainerCombine_Items")),true)
  check(M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R));eq(slotClicks,2)
  -- Another action may reassign a bag before a later held/release event.
  R.Draw=function()
    open={name="Reopened",count=4,slot=26,combine=true}
    eq(B.ItemClick("Bag1",node("InvSlot","Container_Slot:0"),"leftheld"),false)
    return false,"Container contents unavailable"
  end
  ok,why,closed=M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
  eq(ok,true);eq(closed,true);eq(slotClicks,2)
  M.Size("Bag1",container,instance,R)
  R.Draw=function()return false,"A specific adapter failure" end
  ok,why=M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
  eq(ok,false);eq(why,"A specific adapter failure")
  R.Draw=function()live=false;error("original renderer failure",0)end
  ok,why=pcall(M.Draw,"Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)
  eq(ok,false);eq(why,"original renderer failure") -- real errors are never hidden by a simultaneous close
  live=true
  R.Draw=function()return true end
  check(M.Draw("Bag1",container,instance,{x=0,y=0,w=300,h=220,s=1},R)) -- scope recovered after the error
  for _,screen in ipairs({"Bag36","WorldContainer"})do
    live=true;open={name="Last container",count=10,slot=-1,combine=true}
    M.Size(screen,container,instance,R)
    hs.UI.windows.ClickChild=function()clickCount=clickCount+1;open=nil;live=false;return true end
    R.Draw=function()
      check(B.Click(screen,node("Button","CombineDoneButton"),"left"))
      eq(B.ItemClick(screen,node("InvSlot","Container_Slot:0"),"rightup"),false)
      return true
    end
    ok,why,closed=M.Draw(screen,container,instance,{x=0,y=0,w=300,h=220,s=1},R)
    eq(ok,true);eq(closed,true);eq(slotClicks,2)
  end
  R.Draw,hs.UI.inventory.BagInfo,hs.UI.inventory.BagSlotItem=saved.draw,saved.info,saved.item
  hs.UI.inventory.BagSlotClick,hs.UI.windows.ClickChild,hs.UI.windows.Shown=saved.slotClick,saved.click,saved.shown
end

-- The actual shared HUD closes before its source body, keeps scopes balanced,
-- skips tools after retirement, and retains actionable renderer diagnostics.
do
  local saved={draw=R.Draw,insets=R.ChromeInsets,track=R.TrackWindow,shown=hs.UI.windows.Shown,
    hit=base.T.Hit,tools=modules["lib/pack_source_presenters.lua"].Tools,resolve=R.Resolve,ownsScroll=M.OwnsScroll}
  local shown,closeHit,ownsScroll=true,false,false
  local scroll=container.fields.Style_VScroll
  container.fields.Style_VScroll=true
  local closes,draws,tools,clips,children,fontScale,childBegins=0,0,0,0,0,1,0
  hs.UI.windows.Shown=function()return shown end
  hs.UI.windows.Show=function(_,value)shown=value;closes=closes+1 end
  base.T.Hit=function()return closeHit end
  R.Resolve=function()return container end
  R.ChromeInsets=function()return {left=3,right=3,top=20,bottom=4,titleHeight=20,
    close={right=3,top=2,width=12,height=12}}end
  R.TrackWindow=function()end
  M.OwnsScroll=function(screen)return ownsScroll and screen=="Bag1"end
  modules["lib/pack_source_presenters.lua"].Tools=function()tools=tools+1 end
  ui.PushClipRect=function()clips=clips+1 end;ui.PopClipRect=function()clips=clips-1 end
  ui.SetWindowFontScale=function(value)fontScale=value end
  ui.BeginChild=function()children=children+1;childBegins=childBegins+1;return true end
  ui.EndChild=function()children=children-1 end
  ui.GetCursorScreenPos=function()return 0,0 end
  ui.Dummy=function()end
  R.Draw=function()draws=draws+1;return true end
  local function window(opts)
    return H.Dialog("Bag1","A real bag",opts or {size=function()return 300,220 end},function()modernBody=modernBody+1 end)
  end
  local function balanced()
    eq(clips,0);eq(children,0);eq(fontScale,1)
    eq(currentContext.managedChrome,nil);eq(currentContext.sourceManagedPanel,nil)
  end
  bagCount=4;closeHit=true
  window({size=function()return 300,220 end,onClose=function()closes=closes+1;shown=false;bagCount=0 end})
  eq(closes,1);eq(draws,0);eq(tools,0);balanced()
  -- Closing Bag1 can leave Bag1 shown because another open bag replaced it.
  shown=true;bagCount=4
  window({size=function()return 300,220 end,onClose=function()closes=closes+1 end})
  eq(closes,2);eq(draws,0);eq(tools,0);balanced()
  window() -- no custom close callback uses windows.Show, once
  eq(closes,3);eq(shown,false);eq(draws,0);balanced()
  shown=true;bagCount=4;closeHit=false
  window();eq(draws,1);eq(tools,1);check(childBegins>0);balanced() -- reopen, including an empty bag, is still drawable
  local before=childBegins
  ownsScroll=true;window();eq(childBegins,before);eq(draws,2);eq(tools,2);balanced()
  ownsScroll=false;window();check(childBegins>before);eq(draws,3);eq(tools,3);balanced()
  window({size=function()shown=false;bagCount=0;return 300,220 end})
  eq(draws,3);eq(tools,3);balanced() -- close/destruction during inherited initialization
  shown=true;bagCount=4
  R.Draw=function()return false,"Container model detailed reason" end
  local ok,why=pcall(window)
  eq(ok,false);check(why:find("Container model detailed reason",1,true));check(why:find("Bag1",1,true))
  check(instance.messages["presenter:Bag1"]:find("Container model detailed reason",1,true));balanced()
  R.Draw=function()error("original source file.lua:42: draw failed",0)end
  ok,why=pcall(window)
  eq(ok,false);eq(why,"original source file.lua:42: draw failed")
  eq(instance.messages["presenter:Bag1"],why);balanced()
  R.Draw=function()shown=false;return false,"Model retired during draw" end
  check(pcall(window));eq(tools,3);balanced()
  shown=true;R.Draw=function()return true end
  window();eq(instance.messages["presenter:Bag1"],nil);eq(tools,4);balanced()
  -- Explicit custom-dialog visibility is not a transition to a closed model.
  shown=false;R.Resolve=function()return sourcePlan end
  H.Dialog("SkillsWindow","Custom dialog",{shown=true,size=function()return 300,220 end},function()end)
  eq(tools,5);balanced()
  container.fields.Style_VScroll=scroll
  R.Draw,R.ChromeInsets,R.TrackWindow=saved.draw,saved.insets,saved.track
  hs.UI.windows.Shown,base.T.Hit=saved.shown,saved.hit
  modules["lib/pack_source_presenters.lua"].Tools,R.Resolve=saved.tools,saved.resolve
  M.OwnsScroll=saved.ownsScroll
end
-- A vertical source Trade layout can require more client height than its old
-- root size after frame insets. Retain one column and scroll narrow saves.
do
  local source=plan({});source.rect={x=0,y=0,w=188,h=473}
  local flow=node("TileLayoutBox","TradePanes",{node("Screen","HisPane"),node("Screen","MyPane")})
  flow.fields={HorizontalFirst=false,FirstPieceTemplate=false,SnapToChildren=true,Spacing=8}
  for _,pane in ipairs(flow.children)do pane.rect={x=0,y=0,w=176,h=232}end
  source.children={flow}
  local T={ChromeInsets=function()return{left=4,right=4,top=17,bottom=4}end,
    Geometry=function(_,at)return{x=2,y=2,w=at.w-4,h=at.h-4,s=at.s}end}
  local drawn,childSize,extent,depth
  local save={begin=ui.BeginChild,finish=ui.EndChild,pos=ui.SetCursorScreenPos,get=ui.GetCursorScreenPos,
    dummy=ui.Dummy,flags=ui.WindowFlags,avail=ui.GetContentRegionAvail,style=ui.StyleVar,
    shown=hs.UI.windows.Shown,childShown=hs.UI.windows.ChildShown}
  ui.WindowFlags={HorizontalScrollbar=256};depth=0
  ui.SetCursorScreenPos=function()end;ui.GetCursorScreenPos=function()return 10,20 end
  ui.StyleVar=nil
  ui.GetContentRegionAvail=function()return childSize[1]-14,childSize[2]-14 end
  ui.BeginChild=function(name,w,h,_,flags)eq(name,"##source-trade-client");eq(flags,256);childSize={w,h};depth=depth+1;return true end
  ui.EndChild=function()depth=depth-1 end;ui.Dummy=function(w,h)extent={w,h}end
  hs.UI.windows.Shown=function()return true end;hs.UI.windows.ChildShown=function()return nil end
  T.Draw=function(screen,p,owner,at,adapter)
    eq(screen,"TradeWnd");eq(p,source);eq(adapter,M);drawn=at;return true
  end
  local before=actions
  local w,h=M.Size("TradeWnd",source,instance,T);eq(w,188);eq(h,497)
  check(M.OwnsScroll("TradeWnd",source))
  M.Draw("TradeWnd",source,instance,{x=0,y=0,w=180,h=476,s=1},T)
  eq(drawn.w,180);eq(drawn.h,476);eq(childSize,nil,"natural-size trades do not acquire a child or scrollbar gutter");eq(depth,0)
  M.Draw("TradeWnd",source,instance,{x=0,y=0,w=90,h=180},T)
  eq(drawn.w,180);eq(drawn.h,476);eq(drawn.s,1);eq(childSize[1],90);eq(childSize[2],180)
  eq(extent[1],180);eq(extent[2],476);eq(depth,0)
  T.Draw=function()error("controlled trade paint failure")end
  local ok,why=pcall(M.Draw,"TradeWnd",source,instance,{x=0,y=0,w=90,h=180,s=1},T)
  eq(ok,false);check(tostring(why):find("controlled trade paint failure",1,true));eq(depth,0)
  eq(actions,before);eq(source.rect.h,473);eq(flow.children[2].rect.h,232)
  flow.fields.SnapToChildren=false;eq(M.OwnsScroll("TradeWnd",source),false)
  ui.BeginChild,ui.EndChild,ui.SetCursorScreenPos,ui.GetCursorScreenPos=save.begin,save.finish,save.pos,save.get
  ui.Dummy,ui.WindowFlags,ui.GetContentRegionAvail,ui.StyleVar=save.dummy,save.flags,save.avail,save.style
  hs.UI.windows.Shown,hs.UI.windows.ChildShown=save.shown,save.childShown
end
-- Only the authored nested Loot viewport scrolls. Footers stay outside it;
-- child slot IDs and positions retain the native Loot model's own actions.
do
  local pane=node("Screen","LootInvWnd",{node("InvSlot","LW_LootSlot0"),node("InvSlot","LW_LootSlot33")})
  pane.fields.Style_VScroll=true
  local save={begin=ui.BeginChild,finish=ui.EndChild,pos=ui.SetCursorScreenPos,get=ui.GetCursorScreenPos,
    avail=ui.GetContentRegionAvail,dummy=ui.Dummy,flags=ui.WindowFlags,style=ui.StyleVar,shown=hs.UI.windows.Shown}
  local depth,scroll,painted,childDraws,canvas,footers,parentClip=0,0,0,0,nil,0,false
  ui.StyleVar=nil;ui.WindowFlags={NoBackground=128,HorizontalScrollbar=2048}
  ui.SetCursorScreenPos=function()end;ui.GetCursorScreenPos=function()return 10,20-scroll end
  ui.GetContentRegionAvail=function()return 90,100 end;ui.Dummy=function(w,h)eq(w,90);eq(h,700)end
  ui.BeginChild=function(name,w,h,_,flags)
    eq(parentClip,false,"nested child starts only after the parent graph restores its clips")
    eq(name,"##source-loot-slots");eq(w,110);eq(h,100);eq(flags,128);depth=depth+1;return true
  end
  ui.EndChild=function()depth=depth-1 end
  local T={PaintControl=function(_,n)eq(n,pane);painted=painted+1 end,
    MeasureChildren=function(screen,n,owner,at)eq(screen,"LootWnd");eq(n,pane);eq(at.s,1);return 85,700 end,
    DrawChildren=function(screen,n,owner,at)
      eq(screen,"LootWnd");eq(n.children[2].name,"LW_LootSlot33");eq(footers,childDraws+1)
      canvas=at;childDraws=childDraws+1
    end}
  local before=actions;local at={x=10,y=20,w=110,h=100,s=1}
  local source=plan({pane})
  T.Draw=function()
    parentClip=true
    check(M.DrawControl("LootWnd",pane,at,instance,T));eq(depth,0)
    footers=footers+1 -- the original graph draws its Link/Loot/Done siblings
    parentClip=false
    return true
  end
  hs.UI.windows.Shown=function()return true end
  check(M.Draw("LootWnd",source,instance,at,T));eq(canvas.y,20);eq(canvas.h,700);eq(canvas.w,90)
  scroll=600;check(M.Draw("LootWnd",source,instance,at,T));eq(canvas.y,-580);eq(depth,0)
  eq(painted,2);eq(childDraws,2);eq(actions,before)
  T.DrawChildren=function()error("controlled loot paint failure")end
  local ok,why=pcall(M.Draw,"LootWnd",source,instance,at,T)
  eq(ok,false);check(tostring(why):find("controlled loot paint failure",1,true));eq(depth,0)
  eq(M.DrawControl("LootWnd",pane,at,instance,T),false,"an error restores the owned model draw scope")
  pane.fields.Style_VScroll=false;eq(M.DrawControl("LootWnd",pane,at,instance,T),false)
  pane.fields.Style_VScroll=true;eq(M.DrawControl("BankWnd",pane,at,instance,T),false)
  ui.BeginChild,ui.EndChild,ui.SetCursorScreenPos,ui.GetCursorScreenPos=save.begin,save.finish,save.pos,save.get
  ui.GetContentRegionAvail,ui.Dummy,ui.WindowFlags,ui.StyleVar=save.avail,save.dummy,save.flags,save.style
  hs.UI.windows.Shown=save.shown
end
currentContext={instance={messages={}}}
local private=original(root.."/shared/model_presenters.lua")
check(private~=M);eq(private.context,currentContext)
eq(original(root.."/shared/model_presenters.lua"),private)
dofile=original
print("Model presenters: "..checks.." assertions passed")
