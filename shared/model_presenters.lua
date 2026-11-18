-- Stock-model contracts: source controls keep their authored geometry while
-- typed host queries and actions retain the client's guards and lifecycle.
local context=dofile("lib/pack_context.lua")
local cached=rawget(_G,"hailstone_skin_model_presenters")
if cached and cached.context==context then return cached end
local API=hs.UI
local M={context=context}
rawset(_G,"hailstone_skin_model_presenters",M)
local activeDraws={}
local contracts={}
local function words(text)
  local out={};for name in (text or ""):gmatch("%S+") do out[name]=true end;return out
end
local function model(name,buttons,lists,edits,combos,tabs,sliders)
  contracts[name]={buttons=words(buttons),lists=words(lists),edits=words(edits),combos=words(combos),
    tabs=words(tabs),sliders=words(sliders)}
end
-- These IDs are the published StockWindow handlers in the matching client
-- model files. Unknown source buttons are displayed disabled, never tested by
-- clicking them. A typed input without a model handler rejects the source body.
model("BankWnd","AutoButton DoneButton Hailstone_AutoInventory")
model("BigBankWnd","AutoButton DoneButton Hailstone_AutoInventory")
model("GiveWnd","GVW_Give_Button GVW_Cancel_Button")
model("TradeWnd","TRDW_Trade_Button TRDW_Cancel_Button")
model("LootWnd","BroadcastButton LootAllButton DoneButton")
model("MerchantWnd","MW_Buy_Button MW_Sell_Button MW_Send_Button MW_UsableButton MW_Done_Button MW_Inspect_Button MW_Preview_Button",
  "ItemList","MW_Send_To_Edit MW_Note_Edit",nil,"MW_MerchantSubwindows")
model("TradeskillWnd","ContainerIcon SearchButton ShowFavoritesButton AddFavoriteButton RemoveFavoriteButton CombineButton CombineOneButton CombineCountButton CombineAllButton CombineStopButton AutoInvButton ExperimentButton CloseButton",
  "ComponentList RecipeList","MinTrivialEdit MaxTrivialEdit SearchTextEdit CombineCountEdit")
model("SkillsWindow","DoneButton MakeHotKeyButton","SkillList")
model("SkillsSelectWindow",nil,"SKSW_SkillSelectorList")
model("TrainWindow","DoneButton TrainButton","SkillList")
model("AAWindow","CanPurchaseFilter TrainAllButton TrainButton HotButton LessExpButton MoreExpButton DoneButton",
  "List1 List2 List3 List4 ModernList",nil,nil,"Subwindows")
model("SpellBookWnd","SBW_PageUp_Button SBW_PageDown_Button DoneButton")
model("TaskSelectWnd","AcceptButton TSEL_PreviewRewardButton DeclineButton","TaskList")
model("TaskWnd","TASK_AbandonButton TASK_PreviewRewardButton TASK_MonsterButton STASK_AddPlayerButton STASK_RemovePlayerButton STASK_MakeLeaderButton STASK_InviteRaidButton STASK_InviteExpedButton",
  "TASK_TaskList TASK_TaskElementList QUEST_TaskList QUEST_TaskElementList STASK_MemberList",nil,nil,"TaskSubwindows")
model("RaidWindow","RAID_InviteButton RAID_DisbandButton RAID_AcceptButton RAID_DeclineButton RAID_LockButton RAID_UnlockButton RAID_OptionsButton UpdateMOTDButton NoteUpdateButton RAID_DumpButton RAID_MakeLeaderButton RAID_AddLooterButton RAID_RemoveLooterButton RAID_MainAssistButton RAID_MarkNPCButton RAID_FindPCButton RAID_MemberActionsButton RAID_InviteExpedButton RAID_InviteTaskButton RAID_RemoveLeaderButton RAID_NoGroupButton",
  "RAID_NoteList RAID_PlayerList RAID_NotInGroupPlayerList","NoteEdit MOTDInput",nil,"Subwindows")
model("RaidOptionsWindow",nil,"RAIDOPTIONS_LooterList",nil,"RAIDOPTIONS_SetLootTypeCombo")
model("GuildManagementWnd","InviteButton RemoveButton MakeLeaderButton PromoteButton DemoteButton AltFlagButton UpdatePublicButton UpdatePersonalButton DumpButton UpdateMOTDButton UpdateURL UpdateChannel GotoURL JoinChannel ShowOfflineButton HideAltButton TributeOptOutButton TrophyTributeOptOutButton ShowAllPossibleBannersButton RefreshBannerListButton GT_ViewMembers_Btn GT_ViewRanks_Btn",
  "MemberList NoteList TributeList BannerKitList GT_Rank_List GT_Member_List GT_Permissions_List","PersonalInput PublicInput MOTDInput URLInput ChannelInput",nil,"Subwindows")
model("GuildBankWnd","DepositButton ViewItemButton PromoteButton MergeButton SplitButton WithdrawButton ChangeTargetButton",
  "ItemList DepositList",nil,"FilterCombo PermissionCombo")
model("FriendsWindow","AddButton DeleteButton IgnoreAddButton IgnoreDeleteButton WhoButton","FriendsList IgnoreList","NameInput IgnoreNameInput",nil,"Subwindows")
model("BandolierWnd","AutoSwapButton AddButton DeleteButton UseButton MkHotButton DisplayButton","WeaponSetList")
model("TrackingWnd","TRW_TrackButton DoneButton TRW_AutoUpdateButton TRW_TrackPetsCheckbox TRW_TrackMercsCheckbox","TRW_TrackingList",nil,"TRW_TrackSortCombobox TRW_TrackPlayersCombobox")
model("CombatAbilityWnd","CAW_CombatEffectButton CAW_OpenCombatSkillSelectWnd")
model("CombatSkillSelectWnd","CSSW_MakeHotkeyButton","CSSW_SkillSelectorList")
model("InspectWnd","DoneButton",nil,"INSW_Edit")
model("BookWindow","RightButton LeftButton DoneButton CastSpellButton ScribeButton")
model("NoteWindow","DoneButton CastSpellButton ScribeButton")
model("PlayerNotesWindow",nil,nil,"PlayerNotesInput")
model("HelpWindow","Contents BackButton TipsButton CustomerServiceButton")
model("StoryWnd","AutomaticButton CloseButton","StoryList")
model("LargeDialogWindow","LDW_OkButton LDW_YesButton LDW_NoButton LDW_ReplayButton LDW_MuteButton")
model("TitleWnd","Title_NotifyNewTitles Title_ChangeTitlePrefix Title_ChangeTitleSuffix Title_ClearTitlePrefix Title_ClearTitleSuffix","Title_AvailableSuffixes Title_AvailableTitles")
model("QuantityWnd","QTYW_Accept_Button QTYW_SliderInput",nil,"QTYW_SliderInput",nil,nil,"QTYW_Slider")
model("GroupMentorWindow","GM_AcceptButton GM_SliderInput",nil,"GM_SliderInput","GM_SelectPlayer",nil,"GM_Slider")
model("AlarmWnd","ALRW_OkButton ALRW_CancelButton",nil,"ALRW_HoursEditbox ALRW_MinutesEditbox")
model("FeedbackWindow","FBKW_SendButton FBKW_CancelButton",nil,"FBKW_FeedbackInput")
model("BugReportWindow","DupButton CrashButton TargetButton FlagsButton LocationButton SendButton CancelButton DoneButton",nil,"Edit","BugTypes")
model("CrashReportWindow","SaveNoteButton CloseButton",nil,"Edit")
model("ClaimWnd","ClaimRefreshButton ClaimClaimButton ClaimCancelButton","ClaimFeatureList ClaimItemList")
model("FellowshipWnd","CreateFellowshipButton UpdateMOTDButton InviteMemberButton ToggleExpSharingButton CreateCampsite RefreshListButton ShowAllButton MakeLeaderButton RemoveMemberButton LeaveFellowshipButton EndFellowshipButton DestroyCampsite",
  "MemberList CampsiteKitList","MOTDInput","CampsiteFilter")
model("AlertHistoryWnd",nil,"AH_Closed_Alert_List")
model("TributeTrophyWnd","TTW_ViewPersonal_Btn TTW_ViewGuild_Btn","TTW_AvailableTrophyBenefitList TTW_ActiveTrophyBenefitList")
model("TributeMasterWnd","TMW_LockButton TMW_UpgradeButton TMW_DowngradeButton TMW_StatusButton TMW_DonateButton TMW_CoinButton TMW_SelectedItem","TMW_AvailableBenefitList TMW_ActiveBenefitList")
model("TributeBenefitWnd","ActivateButton GuildActivateButton OptOutButton","GuildBenefitList ActiveBenefitList")
model("LeadershipWindow","LEW_OnButton LEW_OffButton LEW_PurchaseButton LEW_DoneButton LEW_GroupMentoring","LEList2 LEList1")
model("DynamicZoneWnd","DZ_Quit DZ_Leader_Add DZ_Leader_Remove DZ_Leader_MakeLeader DZ_Leader_InviteRaid DZ_Leader_InviteTask","DZ_MemberList DZ_TimerList")
model("DynamicZoneSwitchListWnd","DZSwitchList_OK DZSwitchList_Cancel","DZSwitchList_List")
model("AdventureRequestWnd","AdvRqst_RequestButton AdvRqst_AcceptButton AdvRqst_DeclineButton AdvRqst_LeaveButton AdvRqst_ViewStatsButton",nil,nil,"AdvRqst_TypeCombobox AdvRqst_RiskCombobox")
model("AdventureStatsWnd","AdvStats_RefreshButton AdvStats_LeaderboardButton AdvStats_DoneButton","AdvStats_ThemeList")
model("AdventureLeaderboardWnd","AdvLeaderboard_RefreshButton AdvLeaderboard_DoneButton","AdvLeaderboard_LeaderList",nil,"AdvLeaderboard_SelectCombobox AdvLeaderboard_RiskCombobox")
model("PvPStatsWnd","PvpStats_RefreshButton PvpStats_LeaderboardButton PvpStats_DoneButton","PvpStats_LastKillList PvpStats_LastDeathList PvpStats_KillsList")
model("PvpLeaderboardWnd","PvpLeaderboard_RefreshButton PvpLeaderboard_DoneButton","PvpLeaderboard_LeaderList",nil,"PvpLeaderboard_SelectCombobox")
model("BazaarWnd","BZW_SetPrice_Button BZW_Clear_Button BZW_Start_Button BZW_End_Button BZW_Add_Button BZW_Remove_Button BZW_List_Button BZW_OfflineMode_Button")
model("BazaarSearchWnd","BZR_QueryButton BZR_WelcomeButton BZR_UpdatePlayerButton BZR_Default BZR_RequestItemButton BZR_BuyButton BZR_RequestPreviewButton BZR_FindTraderButton BZR_HideTradersButton","BZR_ItemList",
  "BZR_ItemNameInput BZR_MaxPriceInput BZR_MinPriceInput","BZR_ItemTypeCombobox BZR_ClassSlotCombobox BZR_RaceSlotCombobox BZR_StatSlotCombobox BZR_ItemSlotCombobox BZR_ItemPrestigeCombobox BZR_ItemAugmentCombobox BZR_PlayersCombobox")
model("BazaarConfirmationWnd","BZC_UseTokenButton BZC_UsePlatButton BZC_CancelButton")
model("BarterMerchantWnd","SellButton","BuyLineList DetailList")
model("BarterSearchWnd","SearchButton RefreshInventoryButton WelcomeButton GreetingButton FindButton BuyLineInspectButton CompensationInspectButton HideButton CompensationPreviewButton","InventoryList BuyLineList DetailsList","ItemSearchEdit","PlayerCombo")
model("BarterWnd","ItemSearchButton InventoryAddButton InventoryRemoveButton BuyLineAddButton BuyLineModifyButton BuyLineRemoveButton BuyLineActiveButton ListLinesButton ClearStatusButton UpdateWelcomeButton StartStopButton InventoryRefreshButton OfflineModeButton","ItemSearchList InventoryList CompensationList BuyLineList","ItemSearchEdit CountEdit WelcomeEdit")
model("PointMerchantWnd","PointMerchant_PurchaseButton PointMerchant_SellButton PointMerchant_DoneButton PointMerchant_EquipButton","PointMerchant_ItemList PointMerchant_PointList")
model("NewPointMerchantWnd","NewPointMerchant_PurchaseButton NewPointMerchant_SellButton NewPointMerchant_DoneButton NewPointMerchant_EquipButton","NewPointMerchant_ItemList")
model("MMTW_MerchantWnd","HireButton","SubtypeListBox StanceListBox",nil,"TypeComboBox")
model("MMGW_ManageWnd","SuspendButton DismissButton CallForAssistButton AssistModeCheckbox SetActiveStanceButton SetOwnerButton InfoButton SwitchButton","StanceListBox OwnedListBox")
model("MIW_InfoWnd")
model("JournalNPCWnd",nil,"NPCList DialogList",nil,"CategoryFilter CategorySelect")
model("JournalCatWnd","DeleteButton AddButton UpdateButton","CategoryList","NameInput DescInput","DefaultChooser")
model("LayoutCopyWindow","LC_CopyHotButtonCheckBox LC_CopyHotButtonLoadoutsCheckBox LC_CopySocialsCheckBox LC_CopyChatCheckBox LC_CopyOptionsCheckBox LC_OfferCheckBox LC_CopyButton","LC_LayoutsList")
model("LoadskinWnd","INIButton LoadButton","SkinList")
model("VideoModesWindow","VIDW_AcceptButton","VIDW_VideoResolutionsList",nil,"VIDW_RefreshRateCombobox VIDW_BitDepthCombobox")
model("RealEstatePurchaseWnd","PurchaseButton SellButton TransferButton ManageButton ItemsButton OptOutCheck",nil,nil,"PriceCombo UpkeepCombo")
model("RealEstateManageWnd","DepositButton AddDayButton AddWeekButton WithdrawAllButton WithdrawButton TransferButton AddMemberButton RemoveMemberButton","MemberList BalanceList UpkeepList",nil,"UpkeepCombo MemberGroupCombo")
model("RealEstateItemsWnd","InventoryButton ClosetButton ShedButton CrateButton InspectButton StowButton PackButton UnpackButton","ItemList")
model("RealEstateNeighborhoodWnd","GoButton MyPlotsButton MyItemsButton","NeighborhoodList PlayerList GuildList")
model("RealEstatePlotSearchWnd","SearchButton GoButton","PlotList","NameEdit")

local function call(module,member,...)
  local object=API[module];local fn=object and object[member]
  if type(fn)=="function" then return fn(...) end
  return nil
end
local function has(module,member)
  return (not API.Supports or API.Supports(module,member)) and API[module] and type(API[module][member])=="function"
end
local function id(node)return tostring(node.name or node.item or "")end
local function family(screen)
  if contracts[screen] then return screen end
  if screen:match("^Bag%d+$") or screen=="WorldContainer" then return "ContainerWindow" end
  if screen=="SpellDisplayWindow" or screen:match("^SpellDisplayWindow#%d+$") then return "SpellDisplayWindow" end
end
local function containerIdentity(screen)
  local name,count,combine,where,slot=call("inventory","BagInfo",screen)
  if not name or type(count)~="number" or count<1 then return nil end
  return {name=name,count=count,combine=combine,where=where,slot=slot}
end
local function sameContainer(a,b)
  return a and b and a.name==b.name and a.count==b.count and a.combine==b.combine
    and a.where==b.where and a.slot==b.slot
end
local function stillCurrent(screen,scope)
  if scope.retired then return false end
  if scope.shown==true and call("windows","Shown",screen)==false
    or scope.container and not sameContainer(scope.container,containerIdentity(screen)) then
    scope.retired=true
  end
  return not scope.retired
end
model("ContainerWindow","StandardDoneButton CombineDoneButton Container_Combine")
model("SpellDisplayWindow")
-- These source pages change presentation only; their native models do not
-- maintain a page index. Renderer-owned tab state never changes game authority.
local presentationTabs={FellowshipWnd=words("Subwindows"),LeadershipWindow=words("LEW_Subwindows"),
  MMGW_ManageWnd=words("MMGW_Subwindows"),TitleWnd=words("Title_TitleSheet"),
  TributeBenefitWnd=words("Subwindows"),RealEstateItemsWnd=words("REIW_Subwindows"),
  RealEstateManageWnd=words("REMW_Subwindows")}
local unavailable={
  AAWindow={PassiveFilter="All abilities",ExpansionFilter="All expansions",CategoryFilter="All categories",CatigoryFilter="All categories",List5="Monster abilities are unavailable."},
  MerchantWnd={MW_ItemListRecovery="Buyback is unavailable.",MW_ParcelsList="Parcel retrieval is in Client tools.",MW_ItemListMail="Parcel retrieval is in Client tools.",MW_Note_Edit_Dummy="Parcel notes are in Client tools."},
  LargeDialogWindow={LDW_SoundVolumeSlider="Volume controls are unavailable."},
  RealEstateItemsWnd={REIW_LayoutList="No saved property layouts are available.",REIW_LayoutName_EditBox="Property layout saving is unavailable.",REIW_LayoutRotateYard_Combobox="Property layout rotation is unavailable."},
  RealEstateManageWnd={REMW_Name_EditBox="Property renaming is unavailable.",REMW_Groups_Combobox="Permission overview is in Client tools."},
  RealEstateNeighborhoodWnd={RENW_Search_EditBox="Neighborhood filtering is in Client tools."},
  TributeBenefitWnd={ActiveTrophyBenefitList="No personal trophy benefits are available.",GuildTrophyBenefitList="No guild trophy benefits are available."},
  TributeMasterWnd={BenefitMasterList="No trophy benefits are available."},
  BandolierWnd={Merc_Stance_List="Mercenary stances are in Mercenary management."},
  FriendsWindow={MutedList="Muted contacts are unavailable."},GuildManagementWnd={BannerFilter="All banners",InviteCombobox="Use Invite to invite a member."}}
contracts.BazaarSearchWnd.edits.BZR_MaxLevelInput=true
contracts.BazaarSearchWnd.edits.BZR_MinLevelInput=true
contracts.BazaarSearchWnd.edits.BZR_MaxResultsPerTraderInput=true
contracts.BookWindow.edits.Page0=true;contracts.BookWindow.edits.Page1=true
local aliases={MMGW_ManageWnd={Merc_Stance_List="StanceListBox",Merc_Slot_List="OwnedListBox"},
  RealEstatePurchaseWnd={REPW_Price_Combobox="PriceCombo",REPW_Upkeep_Combobox="UpkeepCombo"},
  RealEstateManageWnd={REMW_Upkeep_Combobox="UpkeepCombo",REMW_MemberGroup_Combobox="MemberGroupCombo",REMW_Access_Combobox="MemberGroupCombo",REMW_Name_List="MemberList",REMW_Balance_List="BalanceList",REMW_Upkeep_List="UpkeepList"},
  RealEstateItemsWnd={REIW_ItemList="ItemList"},
  RealEstateNeighborhoodWnd={RENW_NeighborhoodList="NeighborhoodList",RENW_GuildList="GuildList",RENW_PlayerList="PlayerList"},
  RealEstatePlotSearchWnd={REPSW_Search_EditBox="NameEdit",REPSW_PlotList="PlotList"},
  TributeMasterWnd={ActiveBenefitList="TMW_ActiveBenefitList"}}
local function aliasPairs(screen,text)
  aliases[screen]=aliases[screen]or {}
  for from,to in text:gmatch("(%S+)=(%S+)")do aliases[screen][from]=to end
end
aliasPairs("GuildManagementWnd","GT_InviteButton=InviteButton GT_RemoveButton=RemoveButton GT_MakeLeaderButton=MakeLeaderButton GT_PromoteButton=PromoteButton GT_DemoteButton=DemoteButton GT_AltFlagButton=AltFlagButton GT_DumpButton=DumpButton GT_ShowOfflineButton=ShowOfflineButton GT_HideAltButton=HideAltButton")
aliasPairs("RealEstatePurchaseWnd","REPW_Purchase_Button=PurchaseButton REPW_Sell_Button=SellButton REPW_Transfer_Button=TransferButton REPW_Manage_Button=ManageButton REPW_Items_Button=ItemsButton REPW_OptOut_Checkbox=OptOutCheck")
aliasPairs("RealEstateManageWnd","REMW_Deposit_Button=DepositButton REMW_AddDay_Button=AddDayButton REMW_AddWeek_Button=AddWeekButton REMW_WithdrawAll_Button=WithdrawAllButton REMW_Withdraw_Button=WithdrawButton REMW_Transfer_Button=TransferButton REMW_AddMember_Button=AddMemberButton REMW_RemoveMember_Button=RemoveMemberButton")
aliasPairs("RealEstateItemsWnd","REIW_Inventory_Button=InventoryButton REIW_Closet_Button=ClosetButton REIW_Shed_Button=ShedButton REIW_Crate_Button=CrateButton REIW_Inspect_Button=InspectButton REIW_Stow_Button=StowButton REIW_Pack_Button=PackButton REIW_Unpack_Button=UnpackButton")
aliasPairs("RealEstatePlotSearchWnd","REPSW_Search_Button=SearchButton REPSW_Go_Button=GoButton")
aliasPairs("RealEstateNeighborhoodWnd","RENW_Go_Button=GoButton RENW_MyPlots_Button=MyPlotsButton RENW_MyItems_Button=MyItemsButton")
local function nativeName(screen,node)
  local names=aliases[screen]
  return names and names[id(node)] or id(node)
end
local function suffix(name,prefix,maximum)
  if name:sub(1,#prefix)~=prefix then return nil end
  local text=name:sub(#prefix+1)
  if not text:match("^%d+$") then return nil end
  local n=tonumber(text);return n and n<maximum and n or nil
end
local function slot(screen,name)
  if screen=="BankWnd" then return suffix(name,"BW_BankSlot",16) or suffix(name,"BW_SharedBankSlot",2) end
  if screen=="BigBankWnd" then return suffix(name,"BIGB_BankSlot",24) or suffix(name,"BIGB_SharedBankSlot",2) end
  if screen=="GiveWnd" then return suffix(name,"GVW_MyItemSlot",8) end
  if screen=="TradeWnd" then return suffix(name,"TRDW_TradeSlot",16) end
  if screen=="LootWnd" then return suffix(name,"LW_LootSlot",256) end
  if screen=="InspectWnd" then return suffix(name,"InvSlot",23) end
  if screen=="BazaarWnd" then return suffix(name,"BZR_BazaarSlot",80) end
  if family(screen)=="ContainerWindow" then return suffix(name,"Container_Slot:",256) end
end
local function action(screen,node)
  local name,key=nativeName(screen,node),family(screen)
  local contract=key and contracts[key]
  if not contract then return false end
  if contract.buttons[name] or slot(screen,name)~=nil then return true end
  if screen=="BankWnd" then return suffix(name,"BW_Money",4)~=nil or name=="BW_SharedMoney0" end
  if screen=="BigBankWnd" then return suffix(name,"BIGB_Money",4)~=nil or name=="BIGB_SharedMoney0" end
  if screen=="GiveWnd" then return suffix(name,"GVW_MyMoney",4)~=nil end
  if screen=="TradeWnd" then return suffix(name,"TRDW_MyMoney",4)~=nil end
  if screen=="SpellBookWnd" then return suffix(name,"SBW_Spell",16)~=nil end
  if screen=="RaidOptionsWindow" then return suffix(name,"RAIDOPTIONS_ClassColor",16)~=nil end
  if screen=="TradeskillWnd" then return suffix(name,"RequiredIcon",10)~=nil end
  if screen=="BazaarWnd" then return suffix(name,"BZW_Money",4)~=nil end
  return false
end
function M.Handles(screen)return type(screen)=="string" and family(screen)~=nil end
function M.Enabled(screen,node)
  if node.type=="Button" or node.type=="InvSlot" then return action(screen,node) end
end
function M.Events(screen,node)
  if not action(screen,node) then return end
  return {left=true,right=slot(screen,id(node))~=nil or screen=="SpellBookWnd",phases=slot(screen,id(node))~=nil or screen=="SpellBookWnd"}
end
function M.Input(screen,node)
  local c=contracts[family(screen)]
  if c and c.edits[id(node)] then
    return {capacity=screen=="MailCompositionWindow" and 8192 or 2048,
      enter=screen=="QuantityWnd" or screen=="GroupMentorWindow" or screen=="TradeskillWnd" and id(node)=="SearchTextEdit"}
  end
end
function M.Click(screen,node,phase)
  local scope=activeDraws[screen]
  if scope and not stillCurrent(screen,scope) then return false end
  if family(screen)=="ContainerWindow" and phase=="left" then
    local name=id(node)
    if name=="StandardDoneButton" or name=="CombineDoneButton" or name=="Container_Combine" then
      local result=call("windows","ClickChild",screen,name,phase)
      -- Bag indices compact immediately on close. The same screen may already
      -- refer to another open bag, so visibility alone cannot retire this draw.
      if scope and result and name~="Container_Combine" then scope.retired=true end
      if scope then stillCurrent(screen,scope) end
      return result
    end
  end
  if screen=="TradeskillWnd" and id(node)=="SearchTextEdit" and phase=="left" then
    return call("windows","ClickChild",screen,"SearchButton","left")
  end
end
local libraries={}
local function lib(name)
  if libraries[name]==nil then local ok,value=pcall(dofile,"lib/"..name..".lua");libraries[name]=ok and value or false end
  return libraries[name] or nil
end
local supported={Screen=true,Page=true,LayoutBox=true,HorizontalLayoutBox=true,VerticalLayoutBox=true,
  TileLayoutBox=true,TemplateContainer=true,TabBox=true,Label=true,Button=true,Gauge=true,InvSlot=true,
  Editbox=true,Slider=true,Listbox=true,Combobox=true,STMLbox=true,StaticAnimation=true,HotButton=true,
  StaticTintedBlendAnimation=true,StaticFrame=true,StaticText=true,StaticHeader=true}
local needs={Listbox={"ListInfo","ListRow","ListClick"},Editbox={"Text","SetText"},
  Slider={"ChildState","SetSlider"},Combobox={"ComboInfo","ComboSelect"},TabBox={"TabPage","SetTabPage"},
  InvSlot={"ClickChild"},STMLbox={"Text","StmlLink"},Button={"ClickChild"}}
function M.CanDraw(screen,plan,instance)
  local key=family(screen);local contract=key and contracts[key]
  if not contract or type(plan)~="table" or plan.type~="Screen" then return false,"No audited stock model" end
  if not has("windows","ChildState") or call("windows","ChildState",screen,"")==nil then return false,"Stock model unavailable" end
  if key=="ContainerWindow" then
    for _,member in ipairs({"BagInfo","BagSlotItem","BagSlotClick"})do
      if not has("inventory",member)then return false,"Missing inventory."..member end
    end
    local _,count=call("inventory","BagInfo",screen)
    if type(count)~="number" or count<1 then return false,"Container contents unavailable" end
  end
  local function check(node,depth)
    if depth>64 or not supported[node.type] then return false,"Source control needs a typed adapter: "..tostring(node.type).."/"..id(node) end
    local shown=call("windows","ChildShown",screen,nativeName(screen,node))
    if shown==false or shown==nil and (node.fields or {}).Visible==false or M.Shown and M.Shown(screen,node)==false then return true end
    for _,member in ipairs(needs[node.type] or {}) do if not has("windows",member) then return false,"Missing windows."..member end end
    local name=nativeName(screen,node)
    if unavailable[key] and unavailable[key][name] then return true end
    if node.type=="HotButton" then
      local bar,button=tostring(node.eqType or ""):match("^hotbutton/Bar (%d+)/(%d+)$")
      bar,button=tonumber(bar),tonumber(button)
      if not bar or not button or bar>9 or button>11 then return false,"Hotbutton target is not an authored host slot" end
      for _,need in ipairs({{"hotbars","Info"},{"hotbars","Click"},{"cursor","PickUp"}})do
        if not has(need[1],need[2])then return false,"Hotbutton services unavailable" end
      end
    elseif node.type=="Listbox" then
      if not contract.lists[name] then return false,"List handler not audited: "..name end
      local rows,columns=call("windows","ListInfo",screen,name)
      if type(rows)~="number" or type(columns)~="number" then return false,"List data unavailable: "..name end
    elseif node.type=="Editbox" then
      local _,supplied=call("windows","Text",screen,name)
      local readOnly=(node.fields or {}).Style_ReadOnly==true
      if (not contract.edits[name] and not readOnly) or supplied~=true then return false,"Text-entry handler unavailable: "..name end
    elseif node.type=="Slider" then
      local _,_,value,count=call("windows","ChildState",screen,name)
      if not contract.sliders[name] or type(value)~="number" or type(count)~="number" then return false,"Slider handler unavailable: "..name end
    elseif node.type=="Combobox" then
      if not contract.combos[name] or type((call("windows","ComboInfo",screen,name)))~="table" then return false,"Combo handler unavailable: "..name end
    elseif node.type=="TabBox" then
      local localPages=not contract.tabs[name] or presentationTabs[key] and presentationTabs[key][name]
      if not localPages and (not contract.tabs[name] or type((call("windows","TabPage",screen,name)))~="number") then return false,"Tab handler unavailable: "..name end
    elseif node.type=="InvSlot" then
      if key~="ContainerWindow" and not has("inventory","SlotItem") then return false,"Slot item service unavailable" end
    elseif node.type=="STMLbox" and not lib("stml") then return false,"STML links helper unavailable" end
    if (node.type=="Button" or node.type=="InvSlot") and not action(screen,node) and instance then
      instance.messages=instance.messages or {}
      instance.messages["source-control:"..screen..":"..name]="Source control has no host action: "..name.."; use Client tools for additional client features"
    end
    for _,child in ipairs(node.children or {}) do local ok,why=check(child,depth+1);if not ok then return false,why end end
    return true
  end
  return check(plan,0)
end
local function copy(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value)do out[k]=copy(v)end
  return setmetatable(out,getmetatable(value))
end
local function walk(node,visit)
  visit(node);for _,child in ipairs(node.children or {})do walk(child,visit)end
end
local function state(instance,screen)
  instance.modelPresenters=instance.modelPresenters or {}
  local value=instance.modelPresenters[screen]
  if not value then value={};instance.modelPresenters[screen]=value end
  return value
end
local function prepare(screen,plan,instance)
  if family(screen)~="ContainerWindow" then
    if not aliases[screen] and screen~="BookWindow" then return plan end
    local s=state(instance,screen)
    if s.source~=plan then
      s.source=plan;s.plan=copy(plan)
      walk(s.plan,function(node)
        node.name=nativeName(screen,node)
        if screen=="BookWindow" and (node.name=="Page0" or node.name=="Page1") then
          node.fields=copy(node.fields or {});node.fields.Style_ReadOnly=true
        end
      end)
    end
    return s.plan
  end
  local identity=containerIdentity(screen)
  local count,combine=identity and identity.count,identity and identity.combine
  count=math.max(0,math.min(256,tonumber(count) or 0))
  local s=state(instance,screen)
  s.container=identity
  local key=tostring(count)..":"..tostring(combine)
  if s.source==plan and s.key==key then return s.plan end
  s.source,s.key,s.count,s.combine=plan,key,count,combine
  s.plan=copy(plan)
  local template,tile,standard,done,combineTile
  walk(s.plan,function(node)
    local name=id(node)
    if name=="Container_Slot" and node.type=="InvSlot" then template=node end
    if name=="ContainerStandard_Items" then standard=node end
    if name=="ContainerStandardWithDone_Items" then done=node end
    if name=="ContainerCombine_Items" then combineTile=node end
  end)
  tile=combine and combineTile or done or standard
  if template and tile then
    s.tile=id(tile);tile.children={}
    for n=0,count-1 do
      local child=copy(template);child.name="Container_Slot:"..n;child.item=child.name
      child.rect.x,child.rect.y=0,0;child.children={};tile.children[#tile.children+1]=child
    end
  else s.tile=nil end
  return s.plan
end
local function fitContainer(screen,plan,instance,R,width,height)
  if family(screen)~="ContainerWindow"or not R.MeasureChildren then return plan end
  local s=state(instance,screen);local tile
  walk(plan,function(node)if id(node)==s.tile then tile=node end end)
  if not tile or #(tile.children or{})==0 then return plan end
  local box={x=0,y=0,w=math.max(1,width),h=math.max(1,height),s=1}
  local at=R.Geometry and R.Geometry(tile,box)or box
  -- The named vertical strategy otherwise treats a zero-height slot tile as
  -- flexible and gives the Done button part of its last row. Snap the live
  -- tile to its contents first; the parent can then reserve its footer/gaps.
  local _,needed=R.MeasureChildren(screen,tile,instance,{x=0,y=0,w=math.max(1,at.w),h=math.max(1,at.h),s=1})
  if type(needed)=="number"and needed>0 then
    tile.rect=copy(tile.rect or{});tile.rect.h=needed
    tile.fields=copy(tile.fields or{});tile.fields.AutoStretch=false;tile.fields.AutoStretchVertical=false
    tile.fields.BottomAnchorOffset=nil;tile.fields.BottomAnchorToTop=true
    tile.anchors=copy(tile.anchors or{});tile.anchors.bottomToTop=true
    tile.anchors.explicit=copy(tile.anchors.explicit or{});tile.anchors.explicit.bottom=false
  end
  return plan
end
function M.Shown(screen,node)
  if activeDraws[screen] and activeDraws[screen].retired then return false end
  -- The guild model uses this source combo only as the template for per-row
  -- rank controls (GT_Member_List:<row>); it is not another actionable combo.
  if screen=="GuildManagementWnd" and id(node)=="GT_Ranks_Combobox" then return false end
  if family(screen)~="ContainerWindow" then return end
  local s=context.instance.modelPresenters and context.instance.modelPresenters[screen]
  if not s then return end
  local name=id(node)
  if name=="Container_Slot" or name=="StandardSize" or name=="CombineSize" then return false end
  if name=="ContainerCombine_Icon" or name=="Container_Combine" or name=="CombineDoneButton" then return s.combine==true end
  if name=="StandardDoneButton" then return s.combine~=true end
  if name=="ContainerStandard_Items" or name=="ContainerStandardWithDone_Items" or name=="ContainerCombine_Items" then return name==s.tile end
  local n=suffix(name,"Container_Slot:",256);if n then return n<s.count end
end
function M.Item(screen,node)
  if family(screen)~="ContainerWindow" then return false end
  if activeDraws[screen] and activeDraws[screen].retired then return true,nil end
  local n=suffix(id(node),"Container_Slot:",256)
  if n then return true,call("inventory","BagSlotItem",screen,n) end
  return false
end
function M.ItemClick(screen,node,phase,outside)
  if family(screen)~="ContainerWindow" then return end
  local scope=activeDraws[screen]
  if scope and not stillCurrent(screen,scope) then return false end
  local n=suffix(id(node),"Container_Slot:",256)
  if n then
    local result=call("inventory","BagSlotClick",screen,n,phase,outside==true)
    if scope then stillCurrent(screen,scope) end
    return result
  end
end
function M.AfterControl(screen,node,box,instance)
  if activeDraws[screen] and activeDraws[screen].retired then return end
  if node.type~="InvSlot" or not ui.IsItemHovered() then return end
  local own,item=M.Item(screen,node)
  if not own then item=call("inventory","SlotItem",screen,id(node)) end
  local items=lib("items")
  if item and items and items.Tooltip then
    local comparison
    if own then comparison=call("compare","BagSlotItem",screen,suffix(id(node),"Container_Slot:",256))
    else comparison=call("compare","SlotItem",screen,id(node)) end
    items.Tooltip(item,"",comparison)
  end
end
local function extensionHeight(screen)
  if screen~="RaidWindow" or not has("extensions","ListActions") then return 0 end
  local extensions=lib("extensions")
  if not extensions then return 0 end
  local actions=call("extensions","ListActions",screen,"member_actions",extensions.RaidContext()) or {}
  return (#actions>0 or #(actions.sections or {})>0) and 112 or 0
end
local function tradeFlow(screen,plan)
  if screen~="TradeWnd"then return nil end
  for _,node in ipairs(plan.children or{})do
    local f=node.fields or{}
    if node.type=="TileLayoutBox"and f.SnapToChildren==true and f.HorizontalFirst==false
      and f.FirstPieceTemplate~=true and #(node.children or{})>=2 then
      local fixed=true
      for _,piece in ipairs(node.children)do
        local r=piece.rect or{}
        if (tonumber(r.w)or 0)<=0 or(tonumber(r.h)or 0)<=0 then fixed=false;break end
      end
      if fixed then return node end
    end
  end
end
local function tradeCanvas(screen,plan,instance,R)
  local flow=tradeFlow(screen,plan)
  if not flow or not R.Geometry then return nil end
  local inset=R.ChromeInsets(plan,instance,1)
  local w=math.max(1,plan.rect.w-inset.left-inset.right)
  local h=math.max(1,plan.rect.h-inset.top-inset.bottom)
  local f=flow.fields or{}
  local naturalW,naturalH,count=0,0,0
  for _,piece in ipairs(flow.children)do
    local visible=call("windows","ChildShown",screen,nativeName(screen,piece))
    if visible~=false and(visible~=nil or(piece.fields or{}).Visible~=false)then
      naturalW=math.max(naturalW,piece.rect.w);naturalH=naturalH+piece.rect.h;count=count+1
    end
  end
  naturalW=naturalW+(tonumber(f.PaddingLeft)or 0)+(tonumber(f.PaddingRight)or 0)
  naturalH=naturalH+math.max(0,count-1)*(tonumber(f.Spacing)or 5)
    +(tonumber(f.PaddingTop)or 0)+(tonumber(f.PaddingBottom)or 0)
  local at=R.Geometry(flow,{x=0,y=0,w=w,h=h,s=1})
  return w+math.max(0,naturalW-at.w),h+math.max(0,naturalH-at.h),inset
end
function M.OwnsScroll(screen,plan)return family(screen)=="ContainerWindow"or tradeFlow(screen,plan)~=nil end
local function drawContainer(screen,plan,instance,box,R)
  if not R.MeasureChildren then return R.Draw(screen,plan,instance,box,M)end
  local scale=box.s or 1
  local w,h=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=box.w/scale,h=box.h/scale,s=1})
  if w*scale<=box.w+.01 and h*scale<=box.h+.01 then return R.Draw(screen,plan,instance,box,M)end
  ui.SetCursorScreenPos(box.x,box.y)
  local padded=ui.StyleVar and ui.StyleVar.WindowPadding
  if padded then ui.PushStyleVar(padded,0,0)end
  local visible=ui.BeginChild("##source-container-client",box.w,box.h,false,
    w*scale>box.w and ui.WindowFlags and ui.WindowFlags.HorizontalScrollbar or 0)
  local ok,drawn,why=true,true,nil
  if visible then
    ok,drawn,why=pcall(function()
      local x,y=ui.GetCursorScreenPos();local availableW,availableH=ui.GetContentRegionAvail()
      fitContainer(screen,plan,instance,R,availableW/scale,availableH/scale)
      w,h=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=availableW/scale,h=availableH/scale,s=1})
      local canvas={x=x,y=y,w=math.max(availableW,w*scale),h=math.max(availableH,h*scale),s=scale}
      local result,reason=R.Draw(screen,plan,instance,canvas,M)
      ui.SetCursorScreenPos(x,y);ui.Dummy(canvas.w,canvas.h)
      return result,reason
    end)
  end
  ui.EndChild();if padded then ui.PopStyleVar(1)end
  if not ok then error(drawn,0)end
  return drawn,why
end
local function drawGraph(screen,plan,instance,box,R)
  if family(screen)=="ContainerWindow"then return drawContainer(screen,plan,instance,box,R)end
  local w,h=tradeCanvas(screen,plan,instance,R)
  if not w then return R.Draw(screen,plan,instance,box,M)end
  local scale=math.max(.01,tonumber(box.s)or 1)
  if w*scale<=box.w+.000001*scale and h*scale<=box.h+.000001*scale then
    return R.Draw(screen,plan,instance,box,M)
  end
  -- Fixed source panes retain their scale and vertical flow. A smaller saved
  -- window scrolls this canvas instead of wrapping its second pane sideways.
  ui.SetCursorScreenPos(box.x,box.y)
  local padded=ui.StyleVar and ui.StyleVar.WindowPadding
  if padded then ui.PushStyleVar(padded,0,0)end
  local visible=ui.BeginChild("##source-trade-client",box.w,box.h,false,
    ui.WindowFlags and ui.WindowFlags.HorizontalScrollbar or 0)
  local ok,drawn,why=true,true,nil
  if visible then
    local x,y=ui.GetCursorScreenPos()
    local availableW,availableH=ui.GetContentRegionAvail()
    local canvas={x=x,y=y,w=math.max(availableW,w*scale),h=math.max(availableH,h*scale),s=scale}
    ok,drawn,why=pcall(function()
      local result,reason=R.Draw(screen,plan,instance,canvas,M)
      ui.SetCursorScreenPos(canvas.x,canvas.y);ui.Dummy(canvas.w,canvas.h)
      return result,reason
    end)
  end
  ui.EndChild();if padded then ui.PopStyleVar(1)end
  if not ok then error(drawn,0)end
  return drawn,why
end
function M.ContentSize(screen,plan,instance,R)
  plan=prepare(screen,plan,instance)
  local insets=R.ChromeInsets(plan,instance,1)
  local w,h=math.max(1,plan.rect.w-insets.left-insets.right),math.max(1,plan.rect.h-insets.top-insets.bottom)
  plan=fitContainer(screen,plan,instance,R,w,h)
  if R.MeasureChildren then w,h=R.MeasureChildren(screen,plan,instance,{x=0,y=0,w=w,h=h,s=1}) end
  if family(screen)~="ContainerWindow" then
    -- Source-only parked controls do not enlarge a stock dialog. Container
    -- slot rows are an explicit live expansion and retain their flow extent.
    w,h=math.min(w,plan.rect.w),math.min(h,plan.rect.h)
  end
  return w,h+extensionHeight(screen)
end
function M.Size(screen,plan,instance,R)
  local tw,th,inset=tradeCanvas(screen,plan,instance,R)
  if tw then return math.max(plan.rect.w,tw+inset.left+inset.right),math.max(plan.rect.h,th+inset.top+inset.bottom)end
  local w,h=M.ContentSize(screen,plan,instance,R)
  local insets=R.ChromeInsets(plan,instance,1)
  local width,height=math.max(plan.rect.w,w+insets.left+insets.right),math.max(plan.rect.h,h+insets.top+insets.bottom)
  if family(screen)=="ContainerWindow"and ui.GetIO then
    local io=ui.GetIO();local viewport=tonumber(io.height)
    if viewport and viewport>0 then height=math.min(height,math.max(plan.rect.h,viewport/math.max(.01,tonumber(io.uiScale)or 1)*.8))end
  end
  return width,height
end
local function drawLootPane(screen,node,box,instance,R)
  local fields=node.fields or{}
  ui.SetCursorScreenPos(box.x,box.y)
  local padded=ui.StyleVar and ui.StyleVar.WindowPadding
  if padded then ui.PushStyleVar(padded,0,0)end
  local flags=ui.WindowFlags or{}
  local visible=ui.BeginChild("##source-loot-slots",box.w,box.h,false,
    (flags.NoBackground or 0)|(fields.Style_HScroll==true and(flags.HorizontalScrollbar or 0)or 0))
  local ok,why=true,nil
  if visible then
    ok,why=pcall(function()
      local x,y=ui.GetCursorScreenPos();local w,h=ui.GetContentRegionAvail()
      local extentW,extentH=R.MeasureChildren(screen,node,instance,{x=0,y=0,w=w,h=h,s=box.s or 1})
      local canvas={x=x,y=y,w=fields.Style_HScroll==true and math.max(w,extentW)or w,
        h=math.max(h,extentH),s=box.s or 1}
      R.DrawChildren(screen,node,instance,canvas)
      ui.SetCursorScreenPos(x,y);ui.Dummy(canvas.w,canvas.h)
    end)
  end
  ui.EndChild();if padded then ui.PopStyleVar(1)end
  if not ok then error(why,0)end
end
function M.DrawControl(screen,node,box,instance,R)
  local fields=node.fields or{}
  local scope=activeDraws[screen]
  if screen=="LootWnd"and node.type=="Screen"and id(node)=="LootInvWnd"
    and fields.Style_VScroll==true and R and R.MeasureChildren and R.DrawChildren and scope then
    R.PaintControl(screen,node,box,instance)
    -- Finish the parent graph and all footer clips before switching draw lists.
    -- Older hosts account Lua clip pushes only on the most recent draw list.
    scope.lootPanes=scope.lootPanes or{}
    scope.lootPanes[#scope.lootPanes+1]={node=node,box=box}
    return true
  end
  local message=unavailable[family(screen)] and unavailable[family(screen)][id(node)]
  if not message then return false end
  ui.SetCursorScreenPos(box.x,box.y)
  ui.TextDisabled(message)
  return true
end
function M.Draw(screen,plan,instance,box,R)
  local scope={shown=call("windows","Shown",screen)}
  if family(screen)=="ContainerWindow" then
    scope.container=containerIdentity(screen)
    local previous=instance.modelPresenters and instance.modelPresenters[screen]
    if not scope.container or previous and previous.source==plan and not sameContainer(previous.container,scope.container) then
      return true,nil,true
    end
  end
  if not stillCurrent(screen,scope) then return true,nil,true end
  local prepared=prepare(screen,plan,instance)
  local extra=extensionHeight(screen)*(box.s or 1)
  local area={x=box.x,y=box.y,w=box.w,h=math.max(1,box.h-extra),s=box.s}
  prepared=fitContainer(screen,prepared,instance,R,area.w/(area.s or 1),area.h/(area.s or 1))
  local previous=activeDraws[screen]
  activeDraws[screen]=scope
  local success,ok,why=pcall(function()
    local drawn,reason=drawGraph(screen,prepared,instance,area,R)
    if drawn then
      for _,pane in ipairs(scope.lootPanes or{})do
        if not stillCurrent(screen,scope)then break end
        drawLootPane(screen,pane.node,pane.box,instance,R)
      end
    end
    return drawn,reason
  end)
  activeDraws[screen]=previous
  if not success then error(ok,0) end
  if not stillCurrent(screen,scope) then return true,nil,true end
  if not ok then return false,why end
  if extra>0 then
    local extensions=lib("extensions")
    if extensions then
      ui.SetCursorScreenPos(box.x,box.y+area.h)
      local visible=ui.BeginChild("##source-raid-extensions",box.w,extra,false,0)
      local success,failure=true,nil
      if visible then success,failure=pcall(extensions.Draw,"RaidWindow","member_actions",extensions.RaidContext()) end
      ui.EndChild()
      if not success then error(failure,0) end
    end
  end
  return true
end
function M.Coverage()
  local names={};for name in pairs(contracts)do names[#names+1]=name end;table.sort(names)
  return names
end
return M
