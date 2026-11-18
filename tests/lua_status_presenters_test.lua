-- Synthetic source-shaped controls: no game layouts or artwork are distributed.
local total=0
local function check(value,message)total=total+1;assert(value,message or "check failed")end
local function equal(a,b,message)check(a==b,(message or "values differ")..": "..tostring(a).." / "..tostring(b))end
local S
local function reset()
  S={events={},paint={},text={},images={},animations={},frame=1,time=0,click=false,right=false,hover=true,
    down=false,released=false,active=false,drag=false,book={},gems={},buffs={},shown={},io={},popup=nil,choice=nil}
  modern_spell_drag_frame,modern_spell_drag=nil,nil
end
reset()
local function event(name,...)S.events[#S.events+1]={name,...};return true end
local function events(name)
  local out={};for _,e in ipairs(S.events)do if e[1]==name then out[#out+1]=e end end;return out
end
local windows={
  ChildShown=function(_,child)if S.shown[child]~=nil then return S.shown[child]end;return true end,
  ChildState=function(_,child)return S.enabled~=false end,
  ChildArt=function()return S.art end,
  ChildTooltip=function(_,child)return S.tips and S.tips[child]or child end,
  ClickChild=function(...)return event("click",...)end,
  Button=function(...)return event("button",...)end,
  SetText=function(...)return event("setText",...)end,
  Shown=function(child)return S.displayShown==child end,Title=function()return "Fire"end,
}
local spells={
  Show=function(...)return event("spellShow",...)end,
  GemInfo=function(_,child)return S.gems[child]or{shown=false}end,
  GemOverlay=function()if S.overlay then return S.overlay,0,0,0,.6 end end,
  GemClick=function(...)return event("gemClick",...)end,
  BookState=function()return{gems=S.book}end,
  BookMemorize=function(...)return event("memorize",...)end,
  Sets=function()return S.sets or{}end,MemorizeSet=function(...)return event("set",...)end,
  Details=function()return "Fire"end,
}
hs={UI={windows=windows,spells=spells,character={Gauge=function(kind)
  local v=S.gauges and S.gauges[kind];if v then return table.unpack(v)end;return 0,"",-1 end,
  Label=function(kind)return S.labels and S.labels[kind]or""end},
  buffs={Slot=function(screen,child)
    local b=S.buffs[screen..":"..child];if b then return table.unpack(b,1,b.n or #b)end
  end},cursor={HoldingButton=function()return S.holding end,PickUp=function(...)S.holding=true;return event("pickup",...)end}}}
hs.UI.Supports=function(module,name)return hs.UI[module]and type(hs.UI[module][name])=="function"end
ui={Mouse={Left=0,Right=1},HoveredFlags={ChildWindows=1,AllowWhenBlockedByActiveItem=2},
  GetFrameCount=function()return S.frame end,GetTime=function()return S.time end,GetIO=function()return S.io end,
  SetCursorScreenPos=function(x,y)S.x,S.y=x,y end,BeginDisabled=function(on)S.disabled=on end,EndDisabled=function()S.disabled=false end,
  InvisibleButton=function(name,w,h)S.last=name;S.hit={S.x,S.y,w,h};return not S.disabled and S.click end,
  IsItemHovered=function()return S.hover end,IsItemActive=function()return S.active end,
  IsItemClicked=function(button)return not S.disabled and(button==1 and S.right or button==0 and S.pressed)end,
  IsMouseDown=function(button)return button==1 and S.down end,IsMouseReleased=function(button)return button==1 and S.released or button==0 and S.leftReleased end,
  IsMouseDragging=function()return S.drag end,IsMouseHoveringRect=function()return S.hoverRect~=false end,
  IsWindowHovered=function()return S.windowHovered~=false end,
  DrawImage=function(...)S.images[#S.images+1]=table.pack(...)end,
  DrawRectFilled=function(...)event("fill",...)end,
  PushClipRect=function(...)S.clipDepth=(S.clipDepth or 0)+1;event("clip",...)end,
  PopClipRect=function()S.clipDepth=S.clipDepth-1 end,
  DrawText=function(...)S.text[#S.text+1]=table.pack(...)end,
  PushFont=function()S.fonts=(S.fonts or 0)+1 end,PopFont=function()S.fonts=S.fonts-1 end,
  CalcTextSize=function(text)return #tostring(text)*7,12 end,
  SetTooltip=function(t)S.tooltip=t end,OpenPopup=function(name)S.popup=name end,
  BeginPopup=function(name)return S.popup==name end,EndPopup=function()end,TextDisabled=function()end,
  MenuItem=function(name)return S.choice==name end,
  FindWindowRect=function()return 10,10,100,100 end,GetMousePos=function()return 20,20 end,
  Log=function(text)event("diagnostic",text)end,
}
local M=dofile("shared/status_presenters.lua")
equal(rawget(_G,"hailstone_skin_status_presenters"),M)
local function node(kind,name,x,y,w,h,eq)
  return{type=kind,name=name,item=name,rect={x=x or 0,y=y or 0,w=w or 24,h=h or 24},font=3,
    fields={},art={},colors={},children={},eqType=eq or"",gaugeEqType=eq or""}
end
local function plan(children,w,h)return node("Screen","Source",0,0,w or 100,h or 50)end
local function instance()return{palette={text={1,1,1,1}},style={button={template="SkinButton"}},theme={TakeRightClick=function()event("consume")end}}end
local R={}
function R.PaintControl(screen,n,box,inst,opts)S.paint[#S.paint+1]={screen=screen,node=n,box=box,opts=opts}end
function R.Animation(_,name,box,tint)S.animations[#S.animations+1]={name=name,box=box,tint=tint};return name~=nil and name~=""end
function R.Draw(screen,p,inst,box,adapter)
  equal(adapter,M,"explicit adapter required")
  local function draw(n,parent)
    for _,c in ipairs(n.children)do
      local at={x=parent.x+c.rect.x,y=parent.y+c.rect.y,w=c.rect.w,h=c.rect.h,s=parent.s}
      if not M.DrawControl(screen,c,at,inst,R)then R.PaintControl(screen,c,at,inst)end
      draw(c,at)
    end
  end
  draw(p,box);S.drawn=p;return true
end
local box={x=10,y=20,w=24,h=24,s=1}

-- Capability/graph admission never invokes an action or guesses a model from a source ID.
do
  reset();local p=plan();p.children={node("Label","Decorative",1,2,30,12)}
  for _,screen in ipairs{"TargetWindow","GroupWindow","BuffWindow","ShortDurationBuffWindow","CastSpellWnd","ExtendedTargetWnd"}do check(M.CanDraw(screen,p,instance()))end
  equal(#S.events,0);check(not M.CanDraw("MerchantWnd",p,instance()))
  local original=spells.BookMemorize;spells.BookMemorize=nil;check(not M.CanDraw("CastSpellWnd",p,instance()));spells.BookMemorize=original
  local cycle=plan();cycle.children={cycle};check(not M.CanDraw("GroupWindow",cycle,instance()))
end

-- Group actions use the model's member ID even for a source-specific gauge name.
do
  reset();local inst=instance();local n=node("Gauge","CustomMana",2,3,80,7,32)
  S.click=true;M.DrawControl("GroupWindow",n,box,inst,R)
  equal(events("click")[1][3],"Gauge2");equal(events("click")[1][4],"left")
  equal(S.paint[1].node,n);equal(S.paint[1].box.x,10)
  reset();S.right=true;M.DrawControl("GroupWindow",n,box,instance(),R)
  equal(events("click")[1][4],"right");equal(#events("consume"),1)
  reset();S.right=true;S.io.alt=true;M.DrawControl("GroupWindow",n,box,instance(),R);equal(#events("click"),0)
  reset();S.active=true;S.drag=true;S.click=true;M.DrawControl("GroupWindow",n,box,instance(),R);equal(#events("click"),0)
  reset();S.click=true;local moving=instance();moving.hud={DragItem=function()return true end}
  M.DrawControl("GroupWindow",n,box,moving,R);equal(#events("click"),0)
end

-- Empty extended-target rows keep their role menu; the host owns selection/type semantics.
do
  reset();S.right=true;local n=node("Gauge","ETW_Gauge0",0,0,100,12,42)
  M.DrawControl("ExtendedTargetWnd",n,box,instance(),R)
  equal(events("click")[1][3],"ETW_Role0");equal(events("click")[1][4],"rightup")
  reset();S.click=true;M.DrawControl("ExtendedTargetWnd",n,box,instance(),R)
  equal(events("click")[1][3],"ETW_Gauge0");equal(events("click")[1][4],"left")
end

-- Buff menus snapshot their spell; removing cannot silently cancel a replacement.
do
  reset();local inst=instance();local n=node("Button","Buff0")
  S.buffs['BuffWindow:Buff0']={11,50000,"Ward",true,.5,"3",1,0,0,"2"};S.right=true;S.art={}
  check(M.DrawControl("BuffWindow",n,box,inst,R));equal(S.paint[1].opts.skipDecal,true)
  equal(S.images[1][13],.5);equal(S.popup,"##source-buff-actions");check(S.tooltip:find("Ward",1,true))
  S.right=false;S.buffs['BuffWindow:Buff0']={12,50000,"Replacement",true};S.choice="Remove"
  local p=plan();p.children={n};check(M.Draw("BuffWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R))
  equal(#events("button"),0)
  S.buffs['BuffWindow:Buff0']={11,50000,"Ward",true};S.frame=2
  check(M.Draw("BuffWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R))
  equal(events("button")[1][3],"Buff0");equal(events("button")[1][4],3)
  S.choice="Add to Blocked Buffs";S.frame=3;M.Draw("BuffWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R)
  equal(events("setText")[1][4],"11")
end

-- Unknown icon resources retain text and spell info without inventing a cancellation action on targets.
do
  reset();S.buffs['TargetWindow:Buff0']={44,10000,"Fire",false};S.right=true
  local inst=instance();local n=node("Button","Buff0");M.DrawControl("TargetWindow",n,box,inst,R)
  check(#S.text>0);S.right=false;S.choice="Remove"
  local p=plan();p.children={n};M.Draw("TargetWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R)
  equal(#events("button"),0)
  S.choice="Spell Info";M.Draw("TargetWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R)
  equal(events("spellShow")[1][2],44)
end

-- Missing source slots are appended using source art; authored geometry stays exact.
do
  reset();local p=plan();local n=node("Button","Buff0",7,9,24,24);p.children={n}
  S.buffs['BuffWindow:Buff37']={77,100000,"Extra",true};local inst=instance()
  local w,h=M.Size("BuffWindow",p,inst);equal(w,100);equal(h,74)
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(#p.children,1);equal(n.rect.x,7);equal(n.rect.y,9)
  equal(#S.drawn.children,2);equal(S.drawn.children[2].name,"Buff37");equal(S.drawn.children[2].rect.y,50)
  S.buffs={};S.frame=2;local _,emptyH=M.Size("BuffWindow",p,inst);equal(emptyH,50)
end

-- Appended controls fit the client after source frame/title insets, not behind its bottom border.
do
  reset();local p=plan();p.children={node("Button","Buff0",0,0,24,24)}
  S.buffs['BuffWindow:Buff37']={77,100000,"Extra",true};local inst=instance()
  R.ChromeInsets=function()return{left=5,right=5,top=10,bottom=4}end
  local w,h=M.Size("BuffWindow",p,inst,R)
  M.Draw("BuffWindow",p,inst,{x=5,y=10,w=w-10,h=h-14,s=1},R)
  equal(w,100);equal(h,74);equal(S.drawn.children[2].rect.y,36)
  check(S.drawn.children[2].rect.y+S.drawn.children[2].rect.h<=h-14)
  R.ChromeInsets=nil
end

-- A source with no buff buttons still exposes live target buffs in selected shared artwork.
do
  reset();local p=plan();p.children={};S.buffs['TargetWindow:Buff3']={44,100000,"Extra",true}
  local inst=instance();local _,h=M.Size("TargetWindow",p,inst)
  M.Draw("TargetWindow",p,inst,{x=0,y=0,w=100,h=h,s=1},R)
  equal(#S.drawn.children,1);equal(S.drawn.children[1].name,"Buff3")
  equal(S.drawn.children[1].fields.ButtonDrawTemplate,"SkinButton")
end

-- Source number/name labels and shared multi-row backgrounds follow their own live buff slot.
do
  reset();local p=plan({},200,125);local inst=instance()
  local strip=node("StaticAnimation","BW_BuffBackground0",175,1,24,124);strip.art.animation="Buff_BackgroundLong"
  local number0=node("Label","BW_Number0Label",175,7,24,12);number0.text="1"
  local number1=node("Label","BW_Number1Label",175,32,24,12);number1.text="2"
  local name=node("Label","Buff0Label",30,6,142,12,500);name.text="Source placeholder"
  p.children={strip,number0,number1,name,node("Button","Buff0",175,1,24,24),node("Button","Buff1",175,26,24,24)}
  R.Geometry=function(n,parent)return{x=parent.x+n.rect.x,y=parent.y+n.rect.y,w=n.rect.w,h=n.rect.h,s=parent.s}end
  S.buffs['BuffWindow:Buff0']={44,100000,"Spirit of Wolf",true}
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  local drawn={};for _,v in ipairs(S.paint)do drawn[v.node.name]=true end
  check(drawn.BW_Number0Label);check(drawn.Buff0Label);check(drawn.Buff0)
  check(not drawn.BW_Number1Label);check(not drawn.Buff1)
  local clips=events("clip");equal(#clips,1);equal(clips[1][2],175);equal(clips[1][3],1);equal(clips[1][4],199);equal(clips[1][5],25)
  equal(S.clipDepth,0)
  S.paint={};S.events={};S.buffs={};S.frame=2
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  equal(#S.paint,0,"empty source decorations stay hidden");equal(#events("clip"),0)
  S.buffs['BuffWindow:Buff1']={45,100000,"Second slot",true};S.frame=3
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  clips=events("clip");equal(clips[1][3],26);equal(clips[1][5],50,"the source strip is cropped, not squeezed or moved")
  local paint=R.PaintControl
  R.PaintControl=function()error("background paint failed")end
  S.frame=4;local ok,why=pcall(M.Draw,"BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  check(not ok and why:find("background paint failed",1,true));equal(S.clipDepth,0)
  R.PaintControl=paint;R.Geometry=nil
end

-- Source measurement owns wrapping/SnapToChildren; do not replace it with a guessed linear layout.
do
  reset();local p=plan();local tile=node("TileLayoutBox","Gems",0,0,100,50)
  tile.fields={SnapToChildren=true,HorizontalFirst=true};tile.children={node("SpellGem","CSPW_Spell0")}
  p.children={tile,node("Button","CSPW_SpellBookV")}
  S.gems.CSPW_Spell0={shown=true}
  local reads=0
  R.MeasureChildren=function(screen,which,inst,at)
    reads=reads+1;equal(screen,"CastSpellWnd");check(at.s==1);return 120,240
  end
  local inst=instance();local w,h=M.Size("CastSpellWnd",p,inst,R)
  equal(w,120);equal(h,240);equal(reads,1);equal(#S.events,0)
  local cw,ch=M.ContentSize("CastSpellWnd",p,inst,R);equal(cw,120);equal(ch,240)
  R.MeasureChildren=nil
end

-- A fixed-height scrolling source keeps its window size and exposes measured virtual content.
do
  reset();local p=plan();p.children={};local inst=instance()
  R.MeasureChildren=function()return 80,180 end
  local w,h=M.Size("BuffWindow",p,inst,R);equal(w,100);equal(h,50)
  local cw,ch=M.ContentSize("BuffWindow",p,inst,R);equal(cw,100);equal(ch,180)
  R.MeasureChildren=nil
end

-- An empty native buff explicitly has no visual or input, even if the source defines a button template.
do
  reset();check(M.DrawControl("BuffWindow",node("Button","Buff0"),box,instance(),R))
  equal(#S.paint,0);equal(#S.animations,0);equal(S.hit,nil)
end

-- Hidden UI/window gaps retire a menu before a new frame can act on the same spell in that slot.
do
  reset();local p=plan();p.children={node("Button","Buff0")};local inst=instance()
  S.buffs['BuffWindow:Buff0']={11,100000,"Ward",true};S.right=true
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R)
  S.right=false;S.frame=4;S.choice="Remove"
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},R)
  equal(#events("button"),0)
end

-- Delta's source Group window contains real inventory slots; reuse the complete item interaction helper.
do
  reset();local original=dofile
  local n=node("InvSlot","DXInvSlot0");n.slot=0
  local inst=instance();local previous={old=true};inst.sourceSlotNode=previous
  dofile=function(path)
    equal(path,"lib/items.lua")
    return{InvSlot=function(...)
      equal(inst.sourceSlotNode,n);equal(select('#',...),7);equal(select(7,...),nil,"no invented numeric placeholder")
      event("itemSlot",...)
    end}
  end
  check(M.DrawControl("GroupWindow",n,box,inst,R));equal(inst.sourceSlotNode,previous)
  equal(events("itemSlot")[1][2],0);equal(events("itemSlot")[1][4],10);equal(events("itemSlot")[1][5],20)
  n.slot=33;check(not M.DrawControl("GroupWindow",n,box,instance(),R))
  n.slot=0;local failing=instance();failing.sourceSlotNode=previous
  dofile=function()return{InvSlot=function()error("item draw failed")end}end
  local ok,why=pcall(M.DrawControl,"GroupWindow",n,box,failing,R)
  check(not ok and why:find("item draw failed",1,true));equal(failing.sourceSlotNode,previous)
  dofile=original
end

-- Gem holder, actual spell-icon inset, cooldown, drag-to-hotbutton and source hit rectangle.
local function gemFixture()
  local n=node("SpellGem","CSPW_Spell0",0,0,40,32)
  n.fields={SpellIconOffsetX=8,SpellIconOffsetY=4,SpellGemDrawTemplate={Holder="Holder",Background="Back",Highlight="Highlight"}}
  S.gems.CSPW_Spell0={shown=true,tex={},tooltip="Fire",tintA=.75};S.book[1]=90
  return n,{x=100,y=200,w=40,h=32,s=1},instance()
end
do
  reset();local n,b,inst=gemFixture();S.click=true;S.overlay=215
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(S.images[1][2],108);equal(S.images[1][3],204);equal(S.images[1][4],132);equal(S.images[1][5],228)
  equal(events("fill")[1][3],215);equal(events("gemClick")[1][3],"left")
  equal(S.hit[1],100);equal(S.hit[3],40)
  reset();n,b,inst=gemFixture();S.active=true;S.drag=true;S.click=true
  M.DrawControl("CastSpellWnd",n,b,inst,R);equal(#events("pickup"),1);equal(#events("gemClick"),0)
  reset();n,b,inst=gemFixture();modern_spell_drag_frame=1;modern_spell_drag={slot=14};S.leftReleased=true
  M.DrawControl("CastSpellWnd",n,b,inst,R);equal(events("memorize")[1][2],14);equal(events("memorize")[1][3],0)
  reset();n,b,inst=gemFixture();S.gems.CSPW_Spell0.tex=nil
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(#S.text,0,"empty gem does not duplicate authored slot labels")
end

-- Quick outside release does not forget; held release keeps the shown spell display.
do
  reset();local n,b,inst=gemFixture();S.right=true;S.down=true
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  S.right=false;S.down=false;S.released=true;S.hover=false;S.time=.1;S.frame=2
  M.DrawControl("CastSpellWnd",n,b,inst,R);equal(#events("gemClick"),1)
  reset();n,b,inst=gemFixture();S.right=true;S.down=true;M.DrawControl("CastSpellWnd",n,b,inst,R)
  S.right=false;S.time=.6;S.frame=2;M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(events("gemClick")[2][3],"rightheld")
  S.down=false;S.released=true;S.frame=3;S.displayShown="SpellDisplayWindow"
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(events("gemClick")[3][3],"rightupheld");equal(events("spellShow")[1][2],90)
end

-- A changed slot or hidden-frame gap cannot release a stale press into a new gem.
do
  reset();local n,b,inst=gemFixture();S.right=true;S.down=true;M.DrawControl("CastSpellWnd",n,b,inst,R)
  S.right=false;S.down=false;S.released=true;S.book[1]=91;S.frame=2
  M.DrawControl("CastSpellWnd",n,b,inst,R);equal(#events("gemClick"),1)
  reset();n,b,inst=gemFixture();S.right=true;S.down=true;M.DrawControl("CastSpellWnd",n,b,inst,R)
  S.right=false;S.down=false;S.released=true;S.frame=4
  M.DrawControl("CastSpellWnd",n,b,inst,R);equal(#events("gemClick"),1)
end

-- Book actions and saved sets remain available in the source button.
do
  reset();local p=plan();p.children={node("Button","CSPW_SpellBookV",0,0,24,24)}
  S.right=true;S.sets={{inUse=true,name="Travel"}};S.choice="Memorize Travel##1"
  M.Draw("CastSpellWnd",p,instance(),{x=0,y=0,w=100,h=50,s=1},R)
  equal(events("set")[1][2],1)
end
-- Presence in a source file is not usable coverage: zero/hidden/clipped slots
-- are appended only when the host says they are live; anchored controls count.
do
  reset();local p=plan({},100,50)
  local anchored=node("SpellGem","CSPW_Spell0",0,0,0,0)
  local hidden=node("SpellGem","CSPW_Spell1",0,0,24,24);hidden.fields.Visible=false
  local clipped=node("SpellGem","CSPW_Spell2",0,60,24,24)
  p.children={anchored,hidden,clipped,node("Button","CSPW_SpellBookV")}
  for n=0,2 do S.gems["CSPW_Spell"..n]={shown=true}end
  R.VisitChildren=function(screen,source,inst,at,visit)
    equal(screen,"CastSpellWnd");equal(source,p);equal(at.w,100)
    visit(anchored,{x=0,y=0,w=100,h=50,s=1},{x=0,y=0,w=100,h=50,s=1})
    visit(p.children[4])
  end
  local originalHit=ui.InvisibleButton;local hits={}
  ui.InvisibleButton=function(name,...)
    hits[name]=(hits[name]or 0)+1;return originalHit(name,...)
  end
  local inst=instance();M.Draw("CastSpellWnd",p,inst,{x=0,y=0,w=100,h=100,s=1},R)
  ui.InvisibleButton=originalHit
  equal(#S.drawn.children,6);equal(S.drawn.children[5].name,"CSPW_Spell1");equal(S.drawn.children[6].name,"CSPW_Spell2")
  equal(S.drawn.children[5].fields.Visible,true);equal(hidden.fields.Visible,false)
  equal(S.drawn.children[1],anchored,"an anchored source slot must not be duplicated")
  equal(hits["##source-status:CastSpellWnd:CSPW_Spell1"],1)
  equal(hits["##source-status:CastSpellWnd:CSPW_Spell2"],1,"client growth cannot revive a second input for the replaced slot")
  equal(clipped.statusReplaced,nil);equal(S.drawn.children[3].statusReplaced,true)
  R.VisitChildren=nil
end
do
  reset();local p=plan({},100,50);local unused=node("Button","Buff0",0,0,0,0)
  local usable=node("Button","Buff4",0,0,24,24);usable.art.background="SelectedSkinBuff"
  p.children={unused,usable};S.buffs['TargetWindow:Buff0']={44,100000,"Live",true}
  R.VisitChildren=function(screen,source,inst,at,visit)visit(usable)end
  M.Draw("TargetWindow",p,instance(),{x=0,y=0,w=100,h=100,s=1},R)
  equal(#S.drawn.children,3);equal(S.drawn.children[3].name,"Buff0")
  equal(S.drawn.children[3].rect.w,24);equal(S.drawn.children[3].art.background,"SelectedSkinBuff")
  equal(unused.rect.w,0,"the source's unused placeholder stays untouched")
  R.VisitChildren=nil
end
-- Populated group contracts: authored fixtures carry only layout facts and
-- symbolic resource names. No game bitmap is created or copied by these tests.
local GR={};for key,value in pairs(R)do GR[key]=value end
function GR.Geometry(n,parent)
  local r=n.rect or{};return{x=parent.x+(r.x or 0)*(parent.s or 1),y=parent.y+(r.y or 0)*(parent.s or 1),
    w=(r.w or 0)*(parent.s or 1),h=(r.h or 0)*(parent.s or 1),s=parent.s or 1}
end
function GR.GaugeTrackRect(n,at)
  local y=(n.fields.GaugeOffsetY or 0)*(at.s or 1)
  return{x=at.x,y=at.y+y,w=at.w,h=math.max(0,at.h-y),s=at.s or 1}
end
function GR.MeasureText(_,n,text)return #tostring(text)*7,12 end
function GR.PaintText(_,n,at,_,text)
  S.captions=S.captions or{};S.captions[n.name]={text=text,at=at}
  S.captionList=S.captionList or{};S.captionList[#S.captionList+1]={node=n,text=text}
end
function GR.PaintHealthBox(_,at,fraction,tint)
  S.health=S.health or{};S.health[#S.health+1]={at=at,fraction=fraction,tint=tint}
end
function GR.Draw(screen,p,inst,at)
  local function visit(parent,box)
    for _,n in ipairs(parent.children or{})do
      local visible=M.Shown(screen,n)
      if visible~=false and(visible~=nil or windows.ChildShown(screen,n.name)~=false)then
        local child=GR.Geometry(n,box)
        if not M.DrawControl(screen,n,child,inst,GR)then GR.PaintControl(screen,n,child,inst)end
        visit(n,child)
      end
    end
  end
  S.drawn=p;visit(p,at);return true
end
local function groups(kind)
  local p=plan({},kind=="compact"and 180 or 155,kind=="compact"and 168 or 205)
  p.children={node("StaticAnimation","FixturePanel",0,0,p.rect.w,p.rect.h)}
  local function add(n)p.children[#p.children+1]=n;return n end
  if kind=="compact"then
    add(node("Gauge","Gauge0",37,-4,100,24,1)).fields={GaugeOffsetY=16,GaugeDrawTemplate={Fill="FixtureHP"},TextOffsetX=300}
    add(node("Label","TargetPercentage",-2,9,34,14,19))
    for _,x in ipairs{-21,-45,-69}do
      add(node("Gauge","TK_gauge",x,5,95,21,1)).fields={GaugeDrawTemplate={Fill="FixturePlate"}}
    end
  end
  for row=1,5 do
    local top=kind=="compact"and 36+(row-1)*24 or 15+(row-1)*30
    local primary=add(node("Gauge","Gauge"..row,kind=="compact"and 37 or 11,top,kind=="compact"and 100 or 137,kind=="compact"and 21 or 26,10+row))
    primary.fields=kind=="compact"and{GaugeOffsetY=16,TextOffsetX=3,TextOffsetY=3,GaugeDrawTemplate={Fill="FixtureHP"}}or{TextOffsetX=40}
    if kind=="compact"then
      for _,x in ipairs{-21,-45,-69}do add(node("Gauge","TK_gauge",x,top+6,95,21,10+row)).fields={GaugeDrawTemplate={Fill="FixturePlate"}}end
      add(node("Label","TargetPercentage",-2,top+10,34,14,34+row))
    else
      add(node("Gauge","GW_Gauge"..row,38,top+14,108,8,10+row)).fields={GaugeOffsetY=0,TextOffsetY=-100,GaugeDrawTemplate={Fill="FixtureHP"}}
      add(node("Label","HPLabel"..row,13,top+8,21,12,34+row))
    end
    local resourceY=top+(kind=="compact"and 21 or 23)
    add(node("Gauge",kind=="compact"and"ManaGauge1"or"ManaGauge"..row,37,resourceY,100,kind=="compact"and 3 or 4,30+row)).fields={GaugeOffsetY=kind=="compact"and -2 or 0,GaugeDrawTemplate={Fill="FixtureMana"}}
    add(node("Gauge","GW_STAGauge"..row,37,resourceY+(kind=="compact"and 3 or 0),100,kind=="compact"and 3 or 4,35+row)).fields={GaugeOffsetY=kind=="compact"and -2 or 0,GaugeDrawTemplate={Fill="FixtureEndurance"}}
    add(node("Gauge","PetGauge"..row,37,top+(kind=="compact"and 27 or 20),100,kind=="compact"and 2 or 3,kind=="compact"and 39+row or 16+row)).fields={GaugeOffsetY=kind=="compact"and -2 or 0,GaugeDrawTemplate={Fill="FixturePet"}}
    add(node("Button","GroupRoleTank"..row,114,top,15,15))
  end
  add(node("Button","InviteButton",11,168,50,26));add(node("Button","DisbandButton",93,168,50,26))
  add(node("Button","LFGButton",64,kind=="compact"and 268 or 168,26,26))
  return p
end
local function members()
  S.gauges={[1]={.75,"Self",75},[11]={1,"FixtureOne",100},[12]={.55,"FixtureTwo",55},
    [13]={1,"RemoteMember",-2,.3,.1,.1},[14]={0,"",-1},[15]={0,"DeadMember",-3,.4,0,0}}
  for row=1,5 do
    S.gauges[30+row]={.5,"Member resource",50};S.gauges[35+row]={.4,"Member resource",40};S.gauges[16+row]={.6,"Companion",60}
  end
  S.shown.ManaGauge1=false;S.shown.ManaGauge2=true
end
local function collect(p)
  local out={};local function visit(n)
    out[n.name]=out[n.name]or{};out[n.name][#out[n.name]+1]=n
    for _,child in ipairs(n.children or{})do visit(child)end
  end
  visit(p);return out
end
do
  reset();members();local p=plan({},147,260);p.children={}
  for _,spec in ipairs{{"Gauge1",11,2,35},{"ManaGauge1",31,28,8},{"STAGauge1",36,32,4},{"PetGauge1",17,37,6}}do
    local n=node("Gauge",spec[1],20,spec[3],127,spec[4],spec[2]);n.fields.GaugeDrawTemplate={Fill="FixtureBar"};p.children[#p.children+1]=n
  end
  local inst=instance();inst.profile={source="default"}
  local prepared,w,h=M.GroupLayout(p,inst,GR);equal(w,147);equal(h,260);check(not prepared.statusGroupReflow)
  for index,n in ipairs(prepared.children)do
    for _,key in ipairs{"x","y","w","h"}do equal(n.rect[key],p.children[index].rect[key],"stock geometry")end
  end
  M.Draw("GroupWindow",p,inst,{x=0,y=0,w=147,h=260,s=1},GR)
  for _,paint in ipairs(S.paint)do
    if paint.node.name=="Gauge1"then equal(paint.opts,nil,"stock caption keeps native placement/text")
    else equal(paint.opts.caption,"","supplemental tracks never repeat member/pet names")end
  end
  GR.ChromeInsets=function()return{left=4,right=4,top=20,bottom=4}end
  local _,outerW,outerH=M.GroupLayout(p,instance(),GR);equal(outerW,147);equal(outerH,260,"chrome counted once")
  GR.ChromeInsets=nil
end
for _,entry in ipairs{{"portrait","drakah-pers-adeptus-stock"},{"compact","Nemesis-stock"}}do
  reset();members();local p=groups(entry[1]);local inst=instance();inst.profile={source=entry[2]}
  local prepared,w,h=M.GroupLayout(p,inst,GR);local by=collect(prepared)
  check(prepared.statusGroupReflow);check(h>=p.rect.h);check(M.OwnsScroll("GroupWindow",p,inst))
  local lastBottom=0;local boxCount=0
  for row=1,5 do
    local primary=by["Gauge"..row][1]
    check(primary.rect.y>=lastBottom);lastBottom=primary.rect.y+primary.rect.h
    check(lastBottom<=h);check(primary.statusGroupPaintBox~=nil)
    equal(primary.statusGroupNameOnly,entry[1]=="portrait")
    local health=by["Hailstone_GroupHealthBox"..row][1];boxCount=boxCount+1
    check(health.rect.x>=0 and health.rect.x+health.rect.w<=w)
  end
  equal(boxCount,5);check(by.InviteButton[1].rect.y>=lastBottom)
  check(by.DisbandButton[1].rect.y+by.DisbandButton[1].rect.h<=h)
  local mana2
  for _,n in ipairs(by[entry[1]=="compact"and"ManaGauge1"or"ManaGauge2"])do if n.statusGroupRow==2 then mana2=n end end
  check(mana2~=nil);equal(mana2.statusNativeName,"ManaGauge2");equal(M.Shown("GroupWindow",mana2),true)
  for _,n in ipairs(by.ManaGauge1)do if n.statusGroupRow==1 then equal(M.Shown("GroupWindow",n),false)end end
  equal(by.PetGauge2[1].gaugeEqType,18,"legacy pet IDs map to current pet contract")
  for _,list in pairs(by)do for _,n in ipairs(list)do
    if n.type=="Gauge"and n.statusGroupPaintOnly then equal(n.sourceGaugeCaption,"")end
    if n.name=="TK_gauge"then equal(n.statusReplaced,true)end
  end end
  local oldPrimary=collect(p).Gauge1[1];equal(oldPrimary.statusGroupName,nil,"source plan remains immutable")
  M.Draw("GroupWindow",p,inst,{x=0,y=0,w=w,h=h,s=1},GR)
  equal(#S.health,entry[1]=="compact"and 6 or 5)
  local neutral,remote=false,false
  for _,health in ipairs(S.health)do
    if health.fraction==nil then neutral=true end
    if health.tint and health.tint[1]==.3 then remote=true end
  end
  check(neutral);check(remote)
  if entry[1]=="compact"then
    local selfPercent,secondPercent
    for _,paint in ipairs(S.captionList)do
      if paint.node.statusHealthPercentGauge==1 then selfPercent=paint.text end
      if paint.node.statusHealthPercentGauge==12 then secondPercent=paint.text end
    end
    equal(selfPercent,"75");equal(secondPercent,"55")
  end
  S.click=true;local primary=by.Gauge2[1]
  M.DrawControl("GroupWindow",primary,{x=primary.rect.x,y=primary.rect.y,w=primary.rect.w,h=primary.rect.h,s=1},inst,GR)
  equal(events("click")[1][3],"Gauge2");equal(events("click")[1][4],"left")
  S.click=false;S.right=true
  M.DrawControl("GroupWindow",primary,{x=primary.rect.x,y=primary.rect.y,w=primary.rect.w,h=primary.rect.h,s=1},inst,GR)
  equal(events("click")[2][3],"Gauge2");equal(events("click")[2][4],"right")
  S.right=false
  equal(M.GroupLayout(p,inst,GR),prepared,"default size key remains cached")
  local resized=M.GroupLayout(p,inst,GR,w+20,h,1)
  equal(M.GroupLayout(p,inst,GR),prepared,"size/draw cache keys coexist")
  equal(M.GroupLayout(p,inst,GR,w+20,h,1),resized)
  for n=1,5 do M.GroupLayout(p,inst,GR,w+n,h,1)end
  check(M.GroupLayout(p,inst,GR)~=prepared,"resize history is bounded")
end
do
  reset();members();local p=groups("portrait");local inst=instance();inst.profile={source="drakah-pers-adeptus-stock"}
  local opened,closed=0,0
  ui.BeginChild=function()opened=opened+1;return true end
  ui.EndChild=function()closed=closed+1 end
  ui.GetCursorScreenPos=function()return 0,0 end
  ui.GetContentRegionAvail=function()return 143,100 end
  ui.Dummy=function()end
  check(M.Draw("GroupWindow",p,inst,{x=0,y=0,w=155,h=100,s=1},GR))
  equal(opened,1);equal(closed,1)
  local draw=GR.Draw;GR.Draw=function()error("controlled group drawing failure")end
  check(not pcall(M.Draw,"GroupWindow",p,inst,{x=0,y=0,w=155,h=100,s=1},GR))
  equal(opened,2);equal(closed,2,"scroll scope closes before error propagation")
  GR.Draw=draw
end

-- Resolve all twenty actual portable group graphs. Caption suppression and
-- aliases are shared; procedural cells/reflow are limited to selected profiles.
do
  local originalDofile=dofile;local selected="default"
  dofile=function(path)
    if path=="lib/pack_bindings.lua"then return originalDofile("shared/bindings.lua")end
    if path:sub(1,12)=="lib/layouts/"then return originalDofile("layouts/"..selected.."/"..path:sub(13))end
    return originalDofile(path)
  end
  hs.UI.interfaces={LoadBase=function(path)return originalDofile("layouts/default/"..path:sub(13))end}
  local real=originalDofile("shared/renderer.lua")
  local skins={"default","default_old","aya-stock","delta-stock","drakah-pers-adeptus-stock","DuxaUI-stock",
    "Graphite-stock","ib-stock","lodidodi-stock","Lords-stock","Nemesis-stock","po2-stock","po2alt-stock",
    "qqcustom-stock","qqui-stock","sars-stock","Sparxx-stock","Takus-stock","vert-stock","wow-stock"}
  for _,skin in ipairs(skins)do
    reset();members();selected=skin
    local inst=real.New(originalDofile("ui/"..skin.."/lib/pack_profile.lua"));local source=real.Resolve("GroupWindow",inst)
    check(source~=nil)
    local prepared,w,h=M.GroupLayout(source,inst,real)
    local adapted=skin=="drakah-pers-adeptus-stock"or skin=="Nemesis-stock"
    equal(prepared.statusGroupReflow,adapted,skin)
    local markers,quiet=0,0
    for _,list in pairs(collect(prepared))do for _,n in ipairs(list)do
      if n.statusHealthRow~=nil then markers=markers+1;check(n.rect.w>0 and n.rect.h>0)end
      if n.statusGroupQuiet then equal(n.sourceGaugeCaption,"");quiet=quiet+1 end
      if n.statusNativeName=="ManaGauge2"then equal(M.Shown("GroupWindow",n),true)end
    end end
    if adapted then equal(markers,skin=="Nemesis-stock"and 6 or 5);check(h>0 and w>0)
    else equal(markers,0);equal(w,source.rect.w);equal(h,source.rect.h)end
    check(quiet>=5,skin.." retains quiet resource strips")
  end
  dofile=originalDofile
end
equal(S.fonts or 0,0,"font stack")
print("source status presenters: "..total.." assertions passed")
