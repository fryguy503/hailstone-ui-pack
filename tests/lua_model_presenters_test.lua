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
currentContext={instance={messages={}}}
local private=original(root.."/shared/model_presenters.lua")
check(private~=M);eq(private.context,currentContext)
eq(original(root.."/shared/model_presenters.lua"),private)
dofile=original
print("Model presenters: "..checks.." assertions passed")
