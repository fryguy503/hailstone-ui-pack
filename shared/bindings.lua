-- Semantic adapters only. Layout, artwork and XML interpretation do not belong here.
-- All actions use the public host contract; no invented commands or window owners.
local API = hs.UI
local B = {}

function B.Function(module, member)
  local t = API[module]
  if not t then return nil end
  if API.Supports and not API.Supports(module, member) then return nil end
  return type(t[member]) == "function" and t[member] or nil
end

function B.Call(module, member, ...)
  local fn = B.Function(module, member)
  if fn then return fn(...) end
end

function B.Id(node) return tostring(node.name or node.item or "") end
function B.Model(screen) return B.Call("windows", "ChildState", screen, "") ~= nil end

function B.State(screen, node)
  local enabled, checked, value, count, action = B.Call("windows", "ChildState", screen, B.Id(node))
  local fields = node.fields or {}
  if enabled == nil then enabled = fields.Enabled ~= false end
  if checked == nil then checked = fields.Checked == true end
  return enabled, checked, value, count, action
end

function B.Shown(screen, node)
  local shown = B.Call("windows", "ChildShown", screen, B.Id(node))
  if shown == nil then return (node.fields or {}).Visible ~= false end
  return shown ~= false
end

function B.Text(screen, node)
  local text, supplied = B.Call("windows", "Text", screen, B.Id(node))
  if supplied then return text or "" end -- explicitly empty text must hide the authored caption
  if node.type == "Label" then
    local eqType = tonumber(node.eqType)
    if eqType then
      local label, r, g, b = B.Call("character", "Label", eqType)
      if label ~= nil then return label, r and {r, g, b, 1} or nil end
    end
  end
  return node.text or ""
end

function B.Color(screen, node, part)
  local r, g, b, a = B.Call("windows", "ChildColor", screen, B.Id(node), part or "")
  return r and {r, g, b, a or 1} or nil
end

function B.Gauge(screen, node)
  local fraction, text, r, g, b = B.Call("windows", "ChildGauge", screen, B.Id(node))
  if fraction == nil and tonumber(node.gaugeEqType or node.eqType) then
    local unused
    fraction, text, unused, r, g, b = B.Call("character", "Gauge", tonumber(node.gaugeEqType or node.eqType))
  end
  return fraction or 0, text or "", r and {r, g, b, 1} or nil
end

function B.Click(screen, node, phase, outside)
  return B.Call("windows", "ClickChild", screen, B.Id(node), phase or "left", outside == true)
end

function B.InventorySlot(value)
  local slot
  if type(value)=="number" then slot=value
  elseif type(value)=="string" then
    local equip=value:match("^inventory/Equip (%d+)$")
    local general=value:match("^inventory/General (%d+)$")
    if equip then slot=tonumber(equip)
    elseif general then
      local index=tonumber(general)
      if index and index<=9 then slot=23+index end
    elseif value:match("^%d+$") then slot=tonumber(value) end
  end
  if slot and slot>=0 and slot<=32 and slot%1==0 then return slot end
end

function B.Item(screen, node)
  local item = B.Call("inventory", "SlotItem", screen, B.Id(node))
  if item then return item end
  local slot=B.InventorySlot(node.slot)
  if screen == "InventoryWindow" and slot then
    return B.Call("inventory", "Item", slot)
  end
end

function B.ItemClick(screen, node, phase, outside)
  local slot=B.InventorySlot(node.slot)
  if screen == "InventoryWindow" and slot then
    return B.Call("inventory", "ClickSlot", slot, nil, phase, outside == true)
  end
  return B.Click(screen, node, phase, outside)
end

function B.Icon(item)
  if item and item.icon then return B.Call("assets", "ItemIcon", item.icon) end
end

function B.Tooltip(screen, node)
  local tip = B.Call("windows", "ChildTooltip", screen, B.Id(node))
  if tip and tip ~= "" then return tip end
  return (node.fields or {}).Tooltip or ""
end

function B.Drag(screen, node, row)
  if ui.IsItemActive() and ui.IsMouseDragging(ui.Mouse.Left) and not B.Call("cursor", "HoldingButton") then
    return B.Call("cursor", "PickUp", screen, B.Id(node), row)
  end
  return false
end

-- These resolve presentation templates only. Host calls always keep the actual instance name.
function B.Template(screen)
  if screen:match("^Chat%d+$") then return "ChatWindow" end
  if screen:match("^Bag%d+$") then return "ContainerWindow" end
  if screen:match("^ItemDisplayWindow#?%d+$") then return "ItemDisplayWindow" end
  if screen:match("^HotButtonWnd%d+$") then return "HotButtonWnd" end
  return screen
end

-- Geometry replacement is opt-in. A model's existence, a familiar source ID or
-- ChildState's enabled default does not prove its actions, menus or key routing.
-- Unverified models retain the complete inherited presenter with skin artwork.
local audits={
  -- These model classes implement visibility only; values come from the
  -- character service. No source child can invent a game action here.
  BreathWindow={gauges={[8]=true},labels={},requiredGauge=true},
  CastingWindow={gauges={[7]=true},labels={[134]=true},requiredValue=true},
  AggroMeterWnd={gauges={[149]=true},labels={[302]=true,[303]=true,[305]=true,[307]=true},requiredValue=true},
  -- Aura has only its icon/name list; its model removes the right-clicked row.
  AuraWindow={gauges={},labels={},controls={AuraList={types={Listbox=true},query="ListInfo"}},required={"AuraList"}},
  -- The model owns selection, unavailable-row colours, delay and the server
  -- response. The inherited presenter retains resurrection-dialog focus routing.
  RespawnWnd={gauges={[28]=true},labels={},requiredGauge=true,controls={
    OptionsList={types={Listbox=true},query="ListInfo"},
    SelectButton={types={Button=true,Label=true},click={left=true}}},required={"OptionsList","SelectButton"}},
  TextEntryWnd={gauges={},labels={},controls={
    Prompt={types={Label=true},query="Text",supplied=true},
    Entry={types={Editbox=true},query="Text",supplied=true,focusOnOpen=true,enter=true,capacity=256,click={left=true}},
    OK={types={Button=true,Label=true},click={left=true}},Cancel={types={Button=true,Label=true},click={left=true}}},
    required={"Prompt","Entry","OK","Cancel"}},
  ConfirmationDialogBox={gauges={},labels={},confirmation=true,controls={
    TextOutput={types={STMLbox=true},query="Text",supplied=true},
    Yes_Button={types={Button=true,Label=true},click={left=true}},No_Button={types={Button=true,Label=true},click={left=true}},
    OK_Button={types={Button=true,Label=true},click={left=true}},Cancel_Button={types={Button=true},hidden=true}},
    required={"TextOutput","Yes_Button","No_Button","OK_Button"}},
}
local containers={Screen=true,Page=true,LayoutBox=true,HorizontalLayoutBox=true,VerticalLayoutBox=true,
  TileLayoutBox=true,TemplateContainer=true}
local statics={StaticAnimation=true,StaticTintedBlendAnimation=true,StaticFrame=true,StaticText=true,StaticHeader=true}

function B.Compatible(screen, plan, instance)
  local audit=audits[screen]
  if not audit then return false,"Behavior adapter not audited for "..tostring(screen) end
  if not B.Function("character","Gauge") or not B.Function("character","Label") then
    return false,"Audited read-only value service unavailable"
  end
  if type(plan)~="table" or plan.type~="Screen" then return false,"Audited model requires a screen plan" end
  local gauges,values,seen=0,0,{}
  local function check(node,depth)
    if depth>64 then return false,"Audited control graph exceeds depth limit" end
    for _,name in ipairs({"DefaultControl","DefaultButton","CancelButton"}) do
      local value=(node.fields or {})[name]
      if value and value~="" then return false,"Unaudited keyboard action: "..B.Id(node) end
    end
    local rule=(audit.controls or {})[B.Id(node)]
    if rule then
      if not rule.types[node.type] then return false,"Unaudited control type for "..B.Id(node) end
      seen[B.Id(node)]=true
      if rule.query then
        local value,supplied=B.Call("windows",rule.query,screen,B.Id(node))
        if not B.Function("windows",rule.query) or value==nil or rule.supplied and supplied~=true then
          return false,"Audited control data unavailable: "..B.Id(node)
        end
      end
      if rule.hidden and B.Call("windows","ChildShown",screen,B.Id(node))~=false then return false,"Unaudited visible control: "..B.Id(node) end
      if rule.enter then
        local fields=node.fields or {}
        if fields.Style_Multiline==true or fields.Multiline==true or fields.Style_ReadOnly==true then
          return false,"Unaudited text-entry input mode"
        end
      end
    elseif node.type=="Gauge" then
      local kind=tonumber(node.gaugeEqType) or tonumber(node.eqType)
      if not audit.gauges[kind] then return false,"Unaudited gauge value: "..tostring(kind) end
      gauges=gauges+1;values=values+1
    elseif node.type=="Label" then
      if node.eqType~=nil and node.eqType~="" and not audit.labels[tonumber(node.eqType)] then
        return false,"Unaudited label value: "..tostring(node.eqType)
      end
      if node.eqType~=nil and node.eqType~="" then values=values+1 end
    elseif not containers[node.type] and not statics[node.type] then
      return false,"Unaudited control in model: "..B.Id(node)
    elseif node.eqType~=nil and node.eqType~="" then
      return false,"Unaudited dynamic value on "..tostring(node.type)
    end
    if node.type=="StaticAnimation" or node.type=="StaticTintedBlendAnimation" then
      for _,name in ipairs({(node.art or {}).animation or "",(node.art or {}).background or ""}) do
        if name~="" then
          local animations=instance and instance.index and instance.index.animations or {}
          local animation=animations[name]
          if not animation then for key,value in pairs(animations)do if key:lower()==name:lower() then animation=value;break end end end
          if animation and (animation.grid==true or animation.grid==1) then return false,"Grid artwork requires an audited host cell: "..name end
        end
      end
    end
    for _,child in ipairs(node.children or {})do local ok,why=check(child,depth+1);if not ok then return false,why end end
    return true
  end
  local ok,why=check(plan,0)
  if ok and audit.requiredGauge and gauges==0 then return false,"Audited model requires its live gauge" end
  if ok and audit.requiredValue and values==0 then return false,"Audited model requires a live value" end
  if ok then
    for _,id in ipairs(audit.required or {})do if not seen[id] then return false,"Audited control missing: "..id end end
    if audit.confirmation then
      local yes=B.Call("windows","ChildShown",screen,"Yes_Button")
      local no=B.Call("windows","ChildShown",screen,"No_Button")
      local accept=B.Call("windows","ChildShown",screen,"OK_Button")
      if not (yes==true and no==true and accept==false or yes==false and no==false and accept==true) then
        return false,"Audited confirmation mode unavailable"
      end
    end
  end
  return ok,why
end

function B.Events(screen,node)
  local audit=audits[screen]
  local rule=audit and (audit.controls or {})[B.Id(node)]
  return rule and rule.click
end

function B.Input(screen,node)
  local audit=audits[screen]
  return audit and (audit.controls or {})[B.Id(node)]
end

local required = {
  Button = {{"windows", "ClickChild"}}, InvSlot = {{"inventory", "SlotItem"}, {"windows", "ClickChild"}},
  SpellGem = {{"spells", "GemInfo"}, {"spells", "GemClick"}},
  HotButton = {{"hotbars", "Info"}, {"hotbars", "Click"}},
  Editbox = {{"windows", "Text"}, {"windows", "SetText"}}, Slider = {{"windows", "SetSlider"}},
  Listbox = {{"windows", "ListInfo"}, {"windows", "ListRow"}, {"windows", "ListClick"}},
  Combobox = {{"windows", "ComboInfo"}, {"windows", "ComboSelect"}},
  TabBox = {{"windows", "TabPage"}, {"windows", "SetTabPage"}},
  STMLbox = {{"windows", "StmlLink"}},
}

function B.Requirements(kind) return required[kind] or {} end
return B
