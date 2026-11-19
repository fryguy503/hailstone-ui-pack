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
  reset();local p=plan();local reads=0;local label=node("Label","Decorative",1,2,30,12)
  label.type=nil
  setmetatable(label,{__index=function(_,key)if key=="type"then reads=reads+1;return "Label"end end})
  p.children={label}
  for _,screen in ipairs{"TargetWindow","GroupWindow","BuffWindow","ShortDurationBuffWindow","CastSpellWnd","ExtendedTargetWnd"}do check(M.CanDraw(screen,p,instance()))end
  equal(reads,1,"retained graph shape only needs one walk")
  equal(#S.events,0);check(not M.CanDraw("MerchantWnd",p,instance()))
  local original=spells.BookMemorize;spells.BookMemorize=nil;check(not M.CanDraw("CastSpellWnd",p,instance()));spells.BookMemorize=original
  local cycle=plan();cycle.children={cycle};check(not M.CanDraw("GroupWindow",cycle,instance()))
end

-- With no appended controls, there is no need to traverse the graph to hide replacements.
do
  reset();local p=plan();local reads=0;local n=node("Button","Buff0");n.children=nil
  setmetatable(n,{__index=function(_,key)if key=="children"then reads=reads+1;return {}end end})
  p.children={n}
  local w,h=M.Size("BuffWindow",p,instance(),{VisitChildren=function()end})
  equal(w,100);equal(h,50);equal(reads,1)
end

-- Group actions use the model's member ID even for a source-specific gauge name.
do
  reset();local inst=instance();local n=node("Gauge","CustomMana",2,3,80,7,32)
  local checks=0;local originalSupport=hs.UI.Supports
  hs.UI.Supports=function(...)checks=checks+1;return originalSupport(...)end
  S.click=true;M.DrawControl("GroupWindow",n,box,inst,R)
  equal(checks,0,"live status draws do not repeat capability queries")
  hs.UI.Supports=originalSupport
  equal(events("click")[1][3],"Gauge2");equal(events("click")[1][4],"left")
  equal(S.paint[1].node,n);equal(S.paint[1].box.x,10)
  reset();S.right=true;M.DrawControl("GroupWindow",n,box,instance(),R)
  equal(events("click")[1][4],"right");equal(#events("consume"),1)
  reset();S.right=true;S.io.alt=true;M.DrawControl("GroupWindow",n,box,instance(),R);equal(#events("click"),0)
  reset();S.active=true;S.drag=true;S.click=true;M.DrawControl("GroupWindow",n,box,instance(),R);equal(#events("click"),0)
  reset();S.click=true;local moving=instance();moving.hud={DragItem=function()return true end}
  M.DrawControl("GroupWindow",n,box,moving,R);equal(#events("click"),0)
end

-- One draw reuses a row's read until its action makes a fresh read necessary.
do
  reset();local p=plan();local n=node("Gauge","CustomMana",2,3,80,7,32)
  n.statusNativeName="ManaGauge2";n.fields.Visible=false
  local originalState,originalClick,originalShown=windows.ChildState,windows.ClickChild,windows.ChildShown
  local stateReads,visibilityReads=0,0
  windows.ChildState=function(screen,child)
    if screen=="GroupWindow"and child=="Gauge2"then stateReads=stateReads+1 end
    return originalState(screen,child)
  end
  windows.ChildShown=function(screen,child)
    if screen=="GroupWindow"and(child=="ManaGauge2"or child=="CustomMana")then
      visibilityReads=visibilityReads+1;return S.shown[child]
    end
    return originalShown(screen,child)
  end
  windows.ClickChild=function(...)
    S.enabled=false;S.shown.ManaGauge2=true;return originalClick(...)
  end
  local adapter={Draw=function(screen,_,inst,client,presenter)
    equal(presenter.Shown(screen,n),false,"an unconstrained native alias uses authored visibility")
    equal(presenter.Shown(screen,n),false)
    equal(visibilityReads,2,"an unconstrained native result is reused within the draw")
    presenter.DrawControl(screen,n,client,inst,R)
    presenter.DrawControl(screen,n,client,inst,R)
    equal(stateReads,1,"matching rows share a live state read")
    S.click=true;presenter.DrawControl(screen,n,client,inst,R)
    presenter.DrawControl(screen,n,client,inst,R)
    equal(stateReads,2,"an action invalidates the row read")
    equal(presenter.Shown(screen,n),true,"the next visibility check also sees the native action")
    equal(visibilityReads,3)
    return true
  end}
  check(M.Draw("GroupWindow",p,instance(),{x=0,y=0,w=120,h=90,s=1},adapter))
  equal(#events("click"),1,"the next control sees the host's new disabled state")
  windows.ChildState,windows.ClickChild,windows.ChildShown=originalState,originalClick,originalShown
end

-- Nested draws keep separate scratch, restore the outer read on errors, and
-- invalidate both scopes when a native action can update their shared model.
do
  reset();local p=plan();local probe=node("Label","VisibilityProbe")
  local outer,inner=instance(),instance()
  local function draw(inst,callback)
    return M.Draw("TargetWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},{Draw=callback})
  end
  S.shown.VisibilityProbe=false
  check(draw(outer,function(screen,_,inst,client,presenter)
    equal(presenter.Shown(screen,probe),false)
    S.shown.VisibilityProbe=true
    local ok,why=pcall(draw,inner,function()
      equal(presenter.Shown(screen,probe),true,"even nested draws of the same screen read fresh state")
      error("nested draw failure")
    end)
    check(not ok and tostring(why):find("nested draw failure",1,true))
    equal(presenter.Shown(screen,probe),false,"the outer draw regains its own reads after the error")
    check(draw(inner,function()
      equal(presenter.Shown(screen,probe),true)
      presenter.Click(screen,probe,"left")
      windows.ClickChild(screen,probe.name,"left")
      return true
    end))
    equal(presenter.Shown(screen,probe),true,"the nested action also clears the outer read")
    return true
  end))
  equal(M.Shown("TargetWindow",probe),nil,"there is no active read scope after drawing")
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

-- A reused tuple clears fields which no longer have an overlay value.
do
  reset();local p=plan();p.children={node("Button","Buff0")};local inst=instance()
  local client={x=0,y=0,w=100,h=50,s=1}
  S.buffs['BuffWindow:Buff0']={21,90000,"Old",true,.25,"2"}
  check(M.Draw("BuffWindow",p,inst,client,R))
  equal(S.paint[1].opts.tint[4],.25);equal(S.text[2][7],"2")
  S.paint={};S.text={};S.buffs['BuffWindow:Buff0']={22,90000,"Current",true}
  check(M.Draw("BuffWindow",p,inst,client,R))
  equal(S.paint[1].opts.tint[4],1);equal(#S.text,1);equal(S.text[1][7],"Current")
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
  local originalSlot=hs.UI.buffs.Slot
  local slotReads=0
  hs.UI.buffs.Slot=function(screen,child,overlays)
    if screen=="BuffWindow"and child=="Buff0"and overlays then slotReads=slotReads+1 end
    return originalSlot(screen,child,overlays)
  end
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  equal(slotReads,1,"the background, number, label and icon share the active buff read")
  local drawn={};for _,v in ipairs(S.paint)do drawn[v.node.name]=true end
  check(drawn.BW_Number0Label);check(drawn.Buff0Label);check(drawn.Buff0)
  check(not drawn.BW_Number1Label);check(not drawn.Buff1)
  local clips=events("clip");equal(#clips,1);equal(clips[1][2],175);equal(clips[1][3],1);equal(clips[1][4],199);equal(clips[1][5],25)
  equal(S.clipDepth,0)
  S.paint={};S.events={};S.buffs={}
  M.Draw("BuffWindow",p,inst,{x=0,y=0,w=200,h=125,s=1},R)
  equal(slotReads,2,"a second draw uses current buff data even in the same frame")
  hs.UI.buffs.Slot=originalSlot
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

-- Authored buff intersections survive movement and follow native visibility.
do
  reset();local p=plan({},100,50);local inst=instance()
  local strip=node("StaticAnimation","BuffBackground",8,5,24,42)
  local group=node("Screen","AbsoluteBuffGroup",8,5,30,40)
  group.children={node("Button","Buff0",0,0,24,24)}
  p.children={strip,group};p._packColorsNormalized=true
  S.buffs["BuffWindow:Buff0"]={44,100000,"Ward",true}
  local calculations=0
  R.Geometry=function(n,parent)
    calculations=calculations+1
    return{x=parent.x+n.rect.x,y=parent.y+n.rect.y,w=n.rect.w,h=n.rect.h,s=parent.s}
  end
  M.Draw("BuffWindow",p,inst,{x=10,y=20,w=100,h=50,s=1},R)
  equal(calculations,2)
  local clips=events("clip")
  equal(#clips,1);equal(clips[1][2],18);equal(clips[1][3],25)
  S.frame=2;S.events={}
  M.Draw("BuffWindow",p,inst,{x=25,y=40,w=100,h=50,s=1},R)
  equal(calculations,2,"moving a window reuses authored slot intersections")
  clips=events("clip")
  equal(#clips,1);equal(clips[1][2],33);equal(clips[1][3],45)
  S.shown.AbsoluteBuffGroup=false;S.frame=3;S.events={}
  M.Draw("BuffWindow",p,inst,{x=25,y=40,w=100,h=50,s=1},R)
  equal(calculations,2);equal(#events("clip"),0,"ancestor visibility remains live")
  S.shown.AbsoluteBuffGroup=true;S.frame=4;S.events={}
  M.Draw("BuffWindow",p,inst,{x=25,y=40,w=101,h=50,s=1},R)
  equal(calculations,4,"resizing re-resolves geometry")
  equal(#events("clip"),1);equal(S.clipDepth,0)
  R.Geometry=nil
end

-- The optional mask projects coverage to live controls while preserving
-- nested ancestors and supplemental effects beyond the first machine word.
do
  reset();local p=plan();local inst=instance()
  local group=node("Screen","TargetIconRows")
  local used=node("Button","Buff63");local empty=node("Button","Buff2")
  local irrelevant=node("Label","Unrelated")
  group.children={used,empty};p.children={group,irrelevant}
  local low,high=1<<63,1<<(70-64)
  hs.UI.buffs.Occupied=function(screen)
    equal(screen,"TargetWindow")
    return low,high
  end
  local originalSlot=hs.UI.buffs.Slot
  local slotReads=0
  hs.UI.buffs.Slot=function(screen,child,...)
    check(child=="Buff63"or child=="Buff70","empty slots avoid native reads")
    slotReads=slotReads+1
    return originalSlot(screen,child,...)
  end
  S.buffs["TargetWindow:Buff63"]={44,100000,"Signed lower word",true}
  S.buffs["TargetWindow:Buff70"]={45,100000,"Second word",true}
  local visits=0
  R.VisitChildren=function(_,root,_,_,visit,options)
    visits=visits+1
    check(options.nodes[root]and options.nodes[group]and options.nodes[used])
    check(not options.nodes[empty]and not options.nodes[irrelevant])
    visit(used)
  end
  local w,h=M.Size("TargetWindow",p,inst,R)
  equal(visits,1);equal(slotReads,0)
  M.Draw("TargetWindow",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(S.drawn.children[3].name,"Buff70")
  equal(slotReads,2)
  low,high=0,0;S.frame=2
  M.Draw("TargetWindow",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(visits,1,"an empty target bypasses coverage")
  equal(slotReads,2,"clearing live occupancy takes effect on the next draw")
  hs.UI.buffs.Occupied=nil;hs.UI.buffs.Slot=originalSlot;R.VisitChildren=nil
end

-- Empty buttons and their labels keep their authored layout but never enter
-- the paint path. A target click invalidates earlier reads in the same draw.
do
  reset();local p,inst=plan(),instance()
  local first=node("Button","Buff0")
  local later=node("Button","Buff4")
  local health=node("Gauge","TargetHP",0,0,72,12,6)
  local label=node("Label","BW_Buff4_Label",0,0,30,12,504)
  local low,reads=0,0
  local originalClick=windows.ClickChild
  windows.ClickChild=function(...)
    low=1<<4
    S.buffs["TargetWindow:Buff4"]={57,100000,"Fresh effect",false}
    return originalClick(...)
  end
  hs.UI.buffs.Occupied=function()reads=reads+1;return low,0 end
  S.click=true
  local probe={Draw=function(screen,_,_,client,_,skip)
    local before=reads
    check(skip(screen,first),"empty first slot skips paint")
    check(skip(screen,later),"sibling shares the native snapshot")
    equal(reads,before+1,"no repeating native poll per empty control")
    check(not skip(screen,health),"target health still owns its input")
    M.DrawControl(screen,health,client,inst,R)
    check(not skip(screen,later),"later controls observe the change made by target input")
    equal(reads,before+2)
    return true
  end}
  M.Draw("TargetWindow",p,inst,box,probe)
  windows.ClickChild=originalClick;low=0
  probe.Draw=function(screen,_,_,_,_,skip)
    check(skip(screen,label),"unoccupied spell names also skip paint")
    hs.UI.buffs.Occupied=function()return nil end
    M.Click()
    check(not skip(screen,label),"unknown occupancy preserves legacy painting")
    return true
  end
  M.Draw("BuffWindow",p,inst,box,probe)
  hs.UI.buffs.Occupied=nil
end

-- Fixed coverage reuses authored clipping while accepting live visibility
-- changes. Supplemental buttons remain reachable on older clients.
do
  reset();local p,inst=plan(),instance()
  p._packColorsNormalized=true
  local panel=node("Screen","BuffPanel",10,0,60,40)
  panel.children={node("Button","Buff0",56,0,20,12),node("Button","Buff1",60,0,20,12)}
  p.children={panel}
  S.buffs["BuffWindow:Buff0"]={44,100000,"Partly visible",true}
  S.buffs["BuffWindow:Buff1"]={45,100000,"Outside parent",true}
  local calls=0
  local compact=setmetatable({RetainLayout=function()end,VisitChildren=function()error("fixed coverage walked the renderer")end,
    Geometry=function(n,parent)
      calls=calls+1
      local at=n.rect
      return{x=parent.x+at.x,y=parent.y+at.y,w=at.w,h=at.h,s=parent.s}
    end},{__index=R})
  M.Draw("BuffWindow",p,inst,box,compact)
  equal(S.drawn.children[2].name,"Buff1")
  equal(S.drawn.children[1].children[1],panel.children[1],"partly visible authored slot is retained")
  local measured=calls
  S.frame=2;S.shown.BuffPanel=false
  M.Draw("BuffWindow",p,inst,box,compact)
  equal(S.drawn.children[2].name,"Buff0","hidden ancestor leaves a supplemental slot")
  equal(S.drawn.children[3].name,"Buff1")
  -- Test the retained size query alone, because changing supplemental nodes
  -- may also rebuild the separate decoration intersections at paint time.
  local measuredAfterPaint=calls
  S.frame=3;S.shown.BuffPanel=true
  local _,height=M.Size("BuffWindow",p,inst,compact)
  check(height>50);equal(calls,measuredAfterPaint,"layout bounds remain retained across occupancy and visibility")
  S.frame=4;p.rect.w=p.rect.w+1
  M.Size("BuffWindow",p,inst,compact)
  equal(calls,measuredAfterPaint+3,"new dimensions acquire new bounds")
  check(measured>=3)
end

-- Passive buff windows paint artwork continuously. The normal mouse item is
-- restored on entry, and also remains registered for a held item's release.
do
  reset();local p,inst=plan(),instance()
  p._packColorsNormalized=true;p.children={node("Button","Buff0")}
  S.buffs["BuffWindow:Buff0"]={44,100000,"Ward",true}
  S.windowHovered=false;S.hover=false
  M.Draw("BuffWindow",p,inst,box,R)
  check(S.animations[1]);equal(S.last,nil)
  S.frame=2;S.windowHovered=true;S.active=true;S.hover=true
  M.Draw("BuffWindow",p,inst,box,R)
  equal(S.last,"##source-status:BuffWindow:Buff0");check(S.tooltip:find("Ward",1,true))
  S.frame=3;S.windowHovered=false;S.active=false;S.hover=false;S.last=nil
  M.Draw("BuffWindow",p,inst,box,R)
  equal(S.last,"##source-status:BuffWindow:Buff0","release remains registered outside the window")
  S.frame=4;S.last=nil
  M.Draw("BuffWindow",p,inst,box,R)
  equal(S.last,nil,"passive items stop when the hold clears")
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

-- Packed spell layouts retain coverage and snapping while usable gem visibility stays stable.
do
  reset()
  local p=plan({},100,50);p._packColorsNormalized=true
  local tile=node("TileLayoutBox","GemTiles",0,0,100,50);tile.fields.SnapToChildren=true
  local gem=node("SpellGem","CSPW_Spell0")
  local holder=node("StaticAnimation","Holder")
  local book=node("Button","CSPW_SpellBookV")
  p.children={tile,book};tile.children={gem,holder}
  for n=0,11 do S.shown["CSPW_Spell"..n]=n==0 end
  local rawShown=windows.ChildShown
  local nextOrientation=false
  p.children[3]=node("Screen","CSPW_HorizontalOrientationBook")
  windows.ChildShown=function(screen,child)
    if child=="CSPW_HorizontalOrientationBook"then return nextOrientation end
    return rawShown(screen,child)
  end
  S.gems.CSPW_Spell0={shown=true}
  local localR,measures,visits={},0,0
  for key,value in pairs(R)do localR[key]=value end
  function localR.RetainLayout()end
  function localR.MeasureChildren(_,_,_,at)
    measures=measures+1
    return at.w,nextOrientation and 90 or 75
  end
  function localR.VisitChildren(_,_,_,_,visit,options)
    visits=visits+1
    check(options.nodes[p] and options.nodes[tile] and options.nodes[gem] and options.nodes[book])
    equal(options.nodes[holder],nil,"decorative pieces do not require replacement coverage")
    visit(gem);visit(book)
  end
  local inst=instance()
  local w,h=M.Size("CastSpellWnd",p,inst,localR)
  equal(w,100);equal(h,75);equal(visits,1);equal(measures,1)
  M.ContentSize("CastSpellWnd",p,inst,localR);equal(measures,2)
  S.frame=2;S.gems.CSPW_Spell0.tooltip="A live spell";S.gems.CSPW_Spell0.tex=41
  M.Draw("CastSpellWnd",p,inst,{x=10,y=10,w=w,h=h,s=1},localR)
  equal(S.images[1][1],41,"reused geometry never retains spell artwork")
  M.ContentSize("CastSpellWnd",p,inst,localR)
  equal(visits,1);equal(measures,2)
  S.frame=3;nextOrientation=true
  w,h=M.Size("CastSpellWnd",p,inst,localR)
  equal(h,90);equal(visits,2);equal(measures,3)
  S.frame=4;S.shown.CSPW_Spell1=true;S.gems.CSPW_Spell1={shown=true}
  w,h=M.Size("CastSpellWnd",p,inst,localR)
  M.Draw("CastSpellWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},localR)
  equal(S.drawn.children[4].name,"CSPW_Spell1","new usable gems trigger coverage for a missing authored slot")
  equal(visits,3);equal(measures,4)
  windows.ChildShown=rawShown
end

-- Passive packed gem frames still draw live artwork. A right press stays in
-- the interaction path until its hold/release completes outside that frame.
do
  reset()
  local p=plan();p._packColorsNormalized=true
  local gem=node("SpellGem","CSPW_Spell0");gem._packColorsNormalized=true
  local book=node("Button","CSPW_SpellBookV");book._packColorsNormalized=true
  local art=node("StaticAnimation","GemArtwork");art._packColorsNormalized=true;art.fields.Visible=false
  p.children={gem,book,art}
  for slot=0,11 do S.shown["CSPW_Spell"..slot]=slot==0 end
  S.gems.CSPW_Spell0={shown=true,tex=99};S.book={45}
  local originalShown,originalDraw,originalRetain=windows.ChildShown,R.Draw,R.RetainLayout
  local gemReads=0
  windows.ChildShown=function(screen,child)
    if child=="GemArtwork"then error("static art has no native visibility")end
    if child=="CSPW_Spell0"then gemReads=gemReads+1 end
    return originalShown(screen,child)
  end
  function R.RetainLayout()end
  -- The mock renderer invokes the presenter visibility before painting.
  function R.Draw(screen,source,inst,at,adapter)
    equal(M.Shown(screen,gem),true)
    equal(M.Shown(screen,art),false)
    return originalDraw(screen,source,inst,at,adapter)
  end
  local inst=instance()
  local at={x=0,y=0,w=100,h=50,s=1}
  local visit=R.VisitChildren
  R.VisitChildren=function(_,_,_,_,callback)callback(gem);callback(book)end
  S.windowHovered=false;S.hover=false
  M.Draw("CastSpellWnd",p,inst,at,R)
  equal(S.hit,nil);equal(S.images[1][1],99);equal(gemReads,1)
  S.frame=2;S.windowHovered=true;S.hover=true;S.right=true;S.down=true
  M.Draw("CastSpellWnd",p,inst,at,R)
  equal(events("gemClick")[1][3],"rightdown")
  S.frame=3;S.windowHovered=false;S.hover=false;S.right=false;S.time=.6
  M.Draw("CastSpellWnd",p,inst,at,R)
  equal(events("gemClick")[2][3],"rightheld")
  S.frame=4;S.down=false;S.released=true
  M.Draw("CastSpellWnd",p,inst,at,R)
  equal(events("gemClick")[3][3],"rightupheld");equal(events("gemClick")[3][4],true)
  R.VisitChildren,R.Draw,R.RetainLayout=visit,originalDraw,originalRetain
  windows.ChildShown=originalShown
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
do
  reset();local n,b,inst=gemFixture();local record,reads=nil,0
  local originalInfo,originalOverlay=spells.GemInfo,spells.GemOverlay
  spells.GemInfo=function(_,name,into,y0,y1)
    reads=reads+1
    equal(name,"CSPW_Spell0");equal(y0,204);equal(y1,228)
    if record then equal(into,record,"the native call reuses the gem record")end
    record=into
    into.shown,into.tex,into.tintA=true,S.gems[name].tex,.75
    into.top,into.overlay=S.overlay,S.overlay and .5 or nil
    into.coolA=S.overlay and .6 or nil
    return into
  end
  spells.GemOverlay=function()error("modern GemInfo already supplied the cooldown")end
  S.overlay=215
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(events("fill")[1][3],215);equal(events("fill")[1][9],.6)
  S.overlay=nil;S.frame=S.frame+1
  M.DrawControl("CastSpellWnd",n,b,inst,R)
  equal(#events("fill"),1,"an idle gem clears the previous frame's cooldown")
  equal(reads,2)
  spells.GemInfo,spells.GemOverlay=originalInfo,originalOverlay
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
do
  reset();local n=node("Label","ETW_HPLabel7",4,3,30,12,155)
  S.labels={[155]="51",[158]="18"}
  M.DrawControl("ExtendedTargetWnd",n,box,instance(),R)
  equal(S.paint[1].opts.caption,"18","a legacy wrong label ID cannot show another target's HP")
  equal(n.eqType,155,"compiled source metadata remains immutable")
end
do
  reset();local container=node("LayoutBox","ETW_Ext0",0,0,127,35)
  container.children={node("Gauge","ETW_Gauge0",18,0,100,32,42)}
  equal(M.DrawControl("ExtendedTargetWnd",container,box,instance(),R),false,
    "a named target container must keep traversing its child gauges")
  equal(#S.paint,0)
end
do
  reset();local p=plan({},120,80);p.fields.Style_VScroll=true
  for index=0,19 do
    local n=node("Gauge","ETW_Gauge"..index,0,0,0,0,42+index)
    n.anchors={top=index*35,bottom=index*35+30}
    p.children[#p.children+1]=n
    S.shown[n.name]=true
  end
  local originalVisit,originalMeasure=R.VisitChildren,R.MeasureChildren
  local extentWalks=0
  R.MeasureChildren=function(_,source,_,at)
    extentWalks=extentWalks+1;equal(#source.children,20);return at.w,695
  end
  R.VisitChildren=function(_,source,_,at,visit,opts)
    equal(source,p);equal(at.h,80,"source anchors use the viewport size")
    check(opts.clip.h>=695,"coverage includes reachable scroll content")
    for _,n in ipairs(source.children)do
      visit(n,{x=10,y=n.anchors.top,w=at.w-20,h=30,s=1})
    end
  end
  local inst=instance();local w,h=M.Size("ExtendedTargetWnd",p,inst,R)
  equal(w,120);equal(h,80,"the source viewport must not grow just to expose scroll content")
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(#S.drawn.children,20,"all20 authored rows remain; no 12px duplicates are appended")
  equal(S.drawn.children[20],p.children[20]);equal(p.children[20].anchors.top,665)
  equal(extentWalks,0)
  local cw,ch=M.ContentSize("ExtendedTargetWnd",p,inst,R)
  equal(cw,120);equal(ch,695,"the last live row remains reachable through the scroll child")
  equal(extentWalks,1)
  R.VisitChildren,R.MeasureChildren=originalVisit,originalMeasure
end
do
  local originalVisit,originalMeasure=R.VisitChildren,R.MeasureChildren
  for _,screen in ipairs{"GroupWindow","ExtendedTargetWnd"}do
    reset();for index=0,19 do S.shown["ETW_Gauge"..index]=false end
    local tile=node("TileLayoutBox","AuthoredFlow");tile.fields.SnapToChildren=true
    local p=plan({},100,50);p.fields.Layout="AuthoredVertical";p.children={tile}
    R.MeasureChildren=function()return 130,175 end
    R.VisitChildren=function()end
    local inst=instance();inst.profile={id="sars-stock"}
    local w,h=M.Size(screen,p,inst,R)
    equal(w,130);equal(h,175,screen.." honors authored SnapToChildren instead of clipping wrapped rows")
    equal(p.rect.h,50,"natural measurement cannot mutate source geometry")
    tile.fields.SnapToChildren=false
    S.frame=S.frame+1
    w,h=M.Size(screen,p,inst,R);equal(w,100);equal(h,50,"fixed source layouts retain their authored size")
  end
  R.VisitChildren,R.MeasureChildren=originalVisit,originalMeasure
end
do
  reset();for index=0,19 do S.shown["ETW_Gauge"..index]=index<2 end
  local anchored=node("Gauge","ETW_Gauge0",0,0,0,0,42)
  local p=plan({},100,50);p.children={anchored}
  local originalVisit=R.VisitChildren
  local width,coverageWalks=80,0
  R.VisitChildren=function(_,_,_,_,visit)
    coverageWalks=coverageWalks+1;visit(anchored,{x=20,y=0,w=width,h=35,s=1})
  end
  local inst=instance();local w,h=M.Size("ExtendedTargetWnd",p,inst,R)
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  local prepared=S.drawn;local extra=prepared.children[2]
  equal(extra.rect.w,80);equal(extra.rect.h,35,"new slots inherit resolved anchor size, not a12px placeholder")
  equal(extra.gaugeEqType,43);equal(anchored.rect.w,0)
  S.frame=2
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(S.drawn,prepared,"matching live extras reuse the prepared graph")
  S.frame=3;width=70
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  check(S.drawn~=prepared);equal(S.drawn.children[2].rect.w,70)
  S.frame=4;S.shown.ETW_Gauge1=false
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(S.drawn,p,"removed live slots stop enlarging the layout")
  local previousWalks=coverageWalks
  S.frame=5;S.shown.ETW_Gauge0=false
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(S.drawn,p,"the empty window still draws the authored graph")
  equal(coverageWalks,previousWalks,"an empty window skips the replacement coverage walk")
  S.frame=6;S.shown.ETW_Gauge1=true
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},R)
  equal(S.drawn.children[2].name,"ETW_Gauge1","a newly active slot still gets an appended row")
  equal(coverageWalks,previousWalks+1)
  R.VisitChildren=originalVisit
end
-- Complex packed Extended Target layouts retain the dormant extent and continue to draw
-- their authored compound gauge aliases. Opening a native slot invalidates the extent.
do
  reset()
  for row=0,19 do S.shown["ETW_Gauge"..row]=false end
  local p=plan({},100,50);p._packColorsNormalized=true
  local nested=node("Screen","DecorativeGaugeWrap",0,80,100,25)
  local alias=node("Gauge","ETW_Gauge0_1A",2,0,70,20,42);alias._packColorsNormalized=true
  local twin=node("Gauge","ETW_Gauge0_1B",75,0,20,20,42);twin._packColorsNormalized=true
  nested.children={alias,twin};p.children={nested};S.hover=false
  local localR,measures,visits,gauges,painted={},0,0,0,0
  for key,value in pairs(R)do localR[key]=value end
  function localR.RetainLayout()end
  function localR.MeasureChildren()
    measures=measures+1
    return 100,S.shown.ETW_Gauge0 and 130 or 105
  end
  function localR.VisitChildren(_,_,_,_,visit)
    visits=visits+1;visit(alias)
  end
  function localR.PaintGauge(_,n,_,_,state)
    check(n==alias or n==twin)
    equal(state.fraction,S.shown.ETW_Gauge0 and .5 or nil)
    painted=painted+1
  end
  local originalPaintGauge=R.PaintGauge
  R.PaintGauge=localR.PaintGauge
  local rawGauge=hs.UI.character.Gauge
  hs.UI.character.Gauge=function(kind)gauges=gauges+1;return rawGauge(kind)end
  local inst=instance()
  local w,h=M.ContentSize("ExtendedTargetWnd",p,inst,localR)
  equal(w,100);equal(h,105);equal(measures,1);equal(visits,0)
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},localR)
  equal(painted,2);equal(gauges,1,"compound gauges share the live fallback value")
  S.frame=2
  w,h=M.ContentSize("ExtendedTargetWnd",p,inst,localR)
  equal(h,105);equal(measures,1);equal(visits,0)
  S.frame=3;S.shown.ETW_Gauge0=true;S.gauges={[42]={.5,"Current target",500}}
  w,h=M.ContentSize("ExtendedTargetWnd",p,inst,localR)
  equal(h,130);equal(measures,2);equal(visits,1)
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=w,h=h,s=1},localR)
  equal(painted,4);equal(gauges,2);equal(S.drawn,p)
  R.PaintGauge=originalPaintGauge
  hs.UI.character.Gauge=rawGauge
end
-- An absent compound gauge is skipped outside the window while a held
-- fragment still receives release after the pointer leaves it.
do
  reset()
  for row=0,19 do S.shown["ETW_Gauge"..row]=false end
  local p=plan({},100,50);p._packColorsNormalized=true
  local inner=node("Gauge","ETW_Gauge0_1A",2,0,50,12,42);inner._packColorsNormalized=true
  local outer=node("Gauge","ETW_Gauge0_1B",25,0,25,12,42);outer._packColorsNormalized=true
  local wrapper=node("Screen","LodidodiClip",0,0,25,12);wrapper.children={inner}
  local unavailable=node("Button","ETW_Role1");unavailable._packColorsNormalized=true
  local decoration=node("StaticAnimation","Decoration")
  p.children={wrapper,outer,unavailable,decoration}
  local retainLayout,paintGauge=R.RetainLayout,R.PaintGauge
  local retained=0
  function R.RetainLayout()retained=retained+1 end
  function R.PaintGauge()end
  local inst=instance()
  local at={x=0,y=0,w=100,h=50,s=1}
  S.windowHovered=false;S.hover=false
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  local projected=S.drawn
  equal(#projected.children,1)
  equal(projected.children[1],decoration);equal(#p.children,4);equal(retained,1)
  S.frame=2
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(S.drawn,projected);equal(retained,1,"static geometry stays retained across idle frames")
  S.frame=3;S.windowHovered=true;S.hover=true;S.active=true;S.right=true
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(S.drawn,p)
  equal(events("click")[1][3],"ETW_Role0","hovered compound aliases retain their context menu")
  S.frame=4;S.windowHovered=false;S.hover=false;S.active=false;S.right=false;S.click=true
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(S.drawn,p,"register the active alias through release outside the window")
  S.frame=5;S.click=false
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(S.drawn,projected)
  S.frame=6;S.gauges={[42]={.4,"Live target",400}}
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(#S.drawn.children,3,"real gauge artwork remains visible outside the hovered window")
  equal(S.drawn.children[1],wrapper);equal(S.drawn.children[2],outer)
  R.RetainLayout,R.PaintGauge=retainLayout,paintGauge
end
-- Fixed populated layouts retain coverage while re-reading the live gauges
-- and visibility-dependent children on every draw.
do
  reset()
  for row=0,19 do S.shown["ETW_Gauge"..row]=row==0 end
  local p=plan({},100,50);p._packColorsNormalized=true
  local wrap=node("Screen","FixedHealth")
  local health=node("Gauge","ETW_Gauge0",0,0,80,12,42);health._packColorsNormalized=true
  local decoration=node("StaticText","Decoration")
  p.children={wrap,decoration};wrap.children={health}
  local retain,visit,draw,paint=R.RetainLayout,R.VisitChildren,R.Draw,R.PaintGauge
  local originalShown=windows.ChildShown
  local coverageReads,shownReads=0,0
  windows.ChildShown=function(screen,child)
    if child=="ETW_Gauge0"then shownReads=shownReads+1 end
    return originalShown(screen,child)
  end
  function R.RetainLayout()end
  function R.VisitChildren(_,_,_,_,callback,options)
    coverageReads=coverageReads+1
    check(options.nodes[p] and options.nodes[wrap] and options.nodes[health])
    equal(options.nodes[decoration],nil)
    callback(health,{x=0,y=0,w=80,h=12,s=1})
  end
  function R.PaintGauge(_,n,_,_,value,options)
    if n==health then S.latestHealth=value.fraction;S.captionOverride=options and options.caption end
  end
  function R.Draw(screen,source,inst,at,adapter)
    equal(M.Shown(screen,health),true)
    return draw(screen,source,inst,at,adapter)
  end
  local inst=instance()
  local at={x=0,y=0,w=100,h=50,s=1}
  S.windowHovered=false;S.hover=false;S.gauges={[42]={.45,"Target",450}}
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(coverageReads,1);equal(shownReads,1);equal(S.latestHealth,.45);equal(S.hit,nil)
  S.frame=2;S.gauges[42]={.75,"Target",750};health.fields.TextOffsetY=8000
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(coverageReads,1);equal(shownReads,2);equal(S.latestHealth,.75);equal(S.hit,nil)
  equal(S.captionOverride,"","only a caption beyond the client's clipping rectangle is skipped")
  S.frame=3;S.shown.ETW_Gauge1=true;S.windowHovered=true;S.hover=true;S.right=true
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(coverageReads,2);equal(S.drawn.children[3].name,"ETW_Gauge1")
  equal(events("click")[1][3],"ETW_Role0","populated rows retain their native context action")
  S.frame=4;at.h=8100;S.right=false
  M.Draw("ExtendedTargetWnd",p,inst,at,R)
  equal(S.captionOverride,nil,"the authored caption returns when its coordinates enter the viewport")
  R.RetainLayout,R.VisitChildren,R.Draw,R.PaintGauge=retain,visit,draw,paint
  windows.ChildShown=originalShown
end
do
  reset()
  for row=0,19 do S.shown["ETW_Gauge"..row]=false end
  local p=plan({},100,50);p._packColorsNormalized=true;p.fields.Style_VScroll=true
  local first=node("Gauge","ETW_Gauge0",10,20,80,20,42)
  local last=node("Gauge","ETW_Gauge12",10,100,80,20,54)
  local mana=node("Gauge","ETW_ManaGauge12",10,120,80,12,74)
  first._packColorsNormalized=true;last._packColorsNormalized=true;mana._packColorsNormalized=true
  p.children={first,last,mana}
  local flatR,geometryReads={},0
  for key,value in pairs(R)do flatR[key]=value end
  function flatR.Geometry(n,at)
    geometryReads=geometryReads+1
    return{x=at.x+n.rect.x,y=at.y+n.rect.y,w=n.rect.w,h=n.rect.h}
  end
  function flatR.VisitChildren()error("flat coverage should not repeat the authored walk")end
  function flatR.MeasureChildren()error("flat extents should not repeat the authored walk")end
  local inst=instance()
  local _,h=M.ContentSize("ExtendedTargetWnd",p,inst,flatR)
  equal(h,50,"role and resource controls cannot expand the empty window")
  S.shown.ETW_Gauge12=true;S.shown.ETW_ManaGauge12=false
  _,h=M.ContentSize("ExtendedTargetWnd",p,inst,flatR)
  equal(h,120,"scroll extent observes the live row even after same-frame sizing")
  S.shown.ETW_ManaGauge12=true
  _,h=M.ContentSize("ExtendedTargetWnd",p,inst,flatR)
  equal(h,132,"secondary visibility still controls its own scroll extent")
  equal(geometryReads,3,"live extent changes reuse the authored geometry")
  S.frame=S.frame+1
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=100,h=132,s=1},flatR)
  equal(S.drawn,p,"reachable offscreen health rows retain their authored layout")
  S.shown.ETW_Gauge2=true
  S.frame=S.frame+1
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=100,h=132,s=1},flatR)
  equal(S.drawn.children[4].name,"ETW_Gauge2","a missing live row still receives an appended control")
  equal(S.drawn.children[4].rect.w,80,"the appended row inherits its authored sibling dimensions")

  flatR.Draw=function()
    equal(M.Shown("ExtendedTargetWnd",mana),true,"the full numeric suffix identifies the live slot")
    S.shown.ETW_Gauge12=false
    M.Click()
    equal(M.Shown("ExtendedTargetWnd",mana),false,"actions invalidate canonical row visibility immediately")
    return true
  end
  M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=100,h=132,s=1},flatR)
end
local GR={};for key,value in pairs(R)do GR[key]=value end
do
  reset();local n=node("Gauge","GW_Gauge1",7,9,100,23,11)
  n.anchors={explicit={left=true,right=true,top=true,bottom=true},left=0,right=0,top=0,bottom=0}
  local p=plan({},150,100);p.children={n};local inst=instance();inst.profile={id="Takus-stock"}
  local renderer={};for key,value in pairs(R)do renderer[key]=value end
  renderer.Geometry=function(child,parent)
    local collapsed=child.anchors and child.anchors.explicit.right
    return{x=parent.x+child.rect.x,y=parent.y+child.rect.y,w=collapsed and 0 or child.rect.w,h=collapsed and 0 or child.rect.h,s=1}
  end
  renderer.MeasureText=function()error("fixed group layouts do not probe font metrics")end
  local prepared=M.GroupLayout(p,inst,renderer)
  local at=renderer.Geometry(prepared.children[1],{x=0,y=0})
  equal(at.w,100);equal(at.h,23,"Takus's measured fixed HP cell must also be drawable")
  equal(at.x,7);equal(at.y,9);equal(n.anchors.explicit.right,true,"source zero-anchor metadata stays unchanged")
end
do
  reset();for index=0,19 do S.shown["ETW_Gauge"..index]=false end
  local n=node("Label","ETW_HPLabel2",21,58,18,12,153)
  n.anchors={explicit={left=true,right=true,top=true,bottom=true},top=90,bottom=102,left=32,right=76}
  local p=plan({},137,305);p.children={n};local inst=instance();inst.profile={id="Sparxx-stock"}
  S.labels={[153]="73"};M.Draw("ExtendedTargetWnd",p,inst,{x=0,y=0,w=137,h=305,s=1},R)
  equal(S.paint[1].box.y,58);equal(S.paint[1].box.x,21)
  equal(S.paint[1].opts.caption,"73");equal(S.paint[1].node.anchors.explicit.top,false)
  equal(n.anchors.top,90,"misplaced source offsets remain immutable")
end
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
  reset();S.hover=false
  local p=plan();p.children={node("Gauge","Gauge1",0,0,60,10,11),
    node("Gauge","ManaGauge1",0,10,60,10,31),node("Gauge","PetGauge1",0,20,60,10,17),
    node("Gauge","GW_Gauge1",0,30,60,8,11),node("Gauge","CustomHP",0,38,60,8,11)}
  local inst=instance();local snapshots,dragChecks,retained=0,0,0
  inst.hud={DragItem=function()dragChecks=dragChecks+1;return false end}
  local hp=720
  hs.UI.character.GroupGauges=function(row)
    equal(row,1);snapshots=snapshots+1
    return hp,-2,310,-1,"Member",""
  end
  windows.ChildGauge=function(_,child)
    if child=="CustomHP"then return .25,"Native override",.2,.4,.6 end
  end
  local painted={}
  local groupRenderer={}
  for key,value in pairs(GR) do groupRenderer[key]=value end
  groupRenderer.RetainLayout=function()retained=retained+1 end
  groupRenderer.PaintGauge=function(_,n,_,_,view)
    painted[#painted+1]={name=n.name,value=view.fraction,caption=view.caption,r=view.tint and view.tint[1]}
  end
  groupRenderer.Draw=function(screen,prepared,owner,at)
    for _,n in ipairs(prepared.children)do M.DrawControl(screen,n,groupRenderer.Geometry(n,at),owner,groupRenderer)end
    hp=250;M.Click();M.DrawControl(screen,prepared.children[1],groupRenderer.Geometry(prepared.children[1],at),owner,groupRenderer)
    return true
  end
  check(M.Draw("GroupWindow",p,inst,{x=0,y=0,w=100,h=50,s=1},groupRenderer))
  equal(painted[1].value,.72);equal(painted[1].caption,"Member")
  equal(painted[2].value,1);equal(painted[2].r,128/255)
  equal(painted[3].value,nil,"an absent pet contributes neither a track nor a caption")
  equal(painted[4].value,.72,"aliased HP tracks share the member snapshot")
  equal(painted[5].value,.25);equal(painted[5].caption,"Native override");equal(painted[5].r,.2)
  equal(painted[6].value,.25,"an action refreshes the row snapshot immediately")
  equal(snapshots,2);equal(dragChecks,2,"idle row controls share one drag check per draw scope")
  equal(retained,1);M.GroupLayout(p,inst,groupRenderer,100,50,1);equal(retained,1)
  hs.UI.character.GroupGauges=nil;windows.ChildGauge=nil
end
do
  reset();local p=plan();p._packColorsNormalized=true
  p.children={node("Gauge","Gauge1",0,0,60,10,11)}
  local inst=instance()
  S.windowHovered,S.hover=false,false
  M.Draw("GroupWindow",p,inst,box,GR)
  check(S.paint[1]);equal(S.last,nil,"passive group draws without creating row input items")
  S.frame=2;S.windowHovered,S.hover,S.active=true,true,true
  M.Draw("GroupWindow",p,inst,box,GR)
  equal(S.last,"##source-status:GroupWindow:Gauge1")
  S.frame=3;S.windowHovered,S.hover,S.active,S.click=false,false,false,true;S.last=nil
  M.Draw("GroupWindow",p,inst,box,GR)
  equal(S.last,"##source-status:GroupWindow:Gauge1","group row receives a held release outside the window")
  equal(events("click")[1][3],"Gauge1")
  S.frame=4;S.click=false;S.last=nil
  M.Draw("GroupWindow",p,inst,box,GR)
  equal(S.last,nil);equal(#events("click"),1)
end
do
  reset();local p=groups("compact");local inst=instance();inst.profile={source="nemesis-stock"}
  local measure=GR.MeasureText
  local delta=0
  GR.MeasureText=function(_,node,text)return #tostring(text)*7+delta*node.font,12 end
  local first=M.GroupLayout(p,inst,GR)
  equal(M.GroupLayout(p,inst,GR),first,"matching font metrics reuse group layout")
  delta=1
  check(M.GroupLayout(p,inst,GR)~=first,"font metric changes reflow the group layout")
  GR.MeasureText=measure
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
    if skin=="Takus-stock"then
      local controls=collect(prepared)
      for row=1,5 do
        local gauge=(controls["GW_Gauge"..row]or controls["Gauge"..row])[1]
        local at=real.Geometry(gauge,{x=0,y=0,w=w,h=h,s=1})
        equal(at.w,120,"Takus repaired cells retain the authored column width")
        equal(at.h,23);equal(at.x,gauge.rect.x);equal(at.y,gauge.rect.y)
      end
    end
    local adapted=skin=="drakah-pers-adeptus-stock"or skin=="Nemesis-stock"
    equal(prepared.statusGroupReflow,adapted,skin)
    local markers,quiet=0,0
    for _,list in pairs(collect(prepared))do for _,n in ipairs(list)do
      if n.statusHealthRow~=nil then markers=markers+1;check(n.rect.w>0 and n.rect.h>0)end
      if n.statusGroupQuiet then equal(n.sourceGaugeCaption,"");quiet=quiet+1 end
      if n.statusNativeName=="ManaGauge2"then equal(M.Shown("GroupWindow",n),true)end
    end end
    if adapted then equal(markers,skin=="Nemesis-stock"and 6 or 5);check(h>0 and w>0)
    else
      equal(markers,0)
      if skin=="sars-stock"then
        check(w>=source.rect.w and h>source.rect.h,"Sars honors its named flow's SnapToChildren")
      else equal(w,source.rect.w);equal(h,source.rect.h)end
    end
    check(quiet>=5,skin.." retains quiet resource strips")
  end
  dofile=originalDofile
end
-- Safe passive layouts use the native renderer regardless of profile name.
-- A changed gauge or interactive frame still runs the source presenter.
do
  reset()
  local captures,replays,draws=0,0,0
  local currentWatch
  local plugin={
    Version=function()return 2 end,
    BeginCapture=function()captures=captures+1;return true end,
    EndCapture=function()return captures end,
    BeginReplay=function(token)check(token>0);return true end,
    EndReplay=function(token)check(token>0);replays=replays+1;return true end,
  }
  hs.UI.plugins={Get=function(key)equal(key,"plugin:ui-pack-native");return plugin end}
  local renderer={}
  for key,value in pairs(R)do renderer[key]=value end
  renderer.Bindings={WatchCalls=function(observer)
    local previous=currentWatch
    currentWatch=observer
    return previous
  end}
  renderer.CaptureArtwork=function()return {}end
  renderer.EndArtworkCapture=function()end
  renderer.ProbeArtwork=function()return true end
  renderer.PaintGauge=function(_,_,_,_,value)S.latestHealth=value.fraction end
  renderer.Draw=function(screen,p,inst,at)
    draws=draws+1
    for _,n in ipairs(p.children)do
      if M.Shown(screen,n)~=false then
        check(M.DrawControl(screen,n,at,inst,renderer))
      end
    end
    return true
  end
  local p=plan()
  local health=node("Gauge","ETW_Gauge0",5,6,80,20,42)
  p._packColorsNormalized,health._packColorsNormalized=true,true
  p.children={health}
  for row=0,19 do S.shown["ETW_Gauge"..row]=row==0 end
  S.windowHovered=false
  for _,profile in ipairs{"default","Graphite-stock"}do
    local inst=instance()
    inst.profile={id=profile}
    S.gauges={[42]={.35,"Target",350}}
    local previousCaptures,previousReplays,previousDraws=captures,replays,draws
    local function draw()
      S.frame=S.frame+1
      check(M.Draw("ExtendedTargetWnd",p,inst,box,renderer))
    end
    draw()
    equal(captures,previousCaptures+1)
    equal(draws,previousDraws+1)
    equal(S.latestHealth,.35)
    equal(currentWatch,nil,"capture restored the binding scope")
    draw()
    equal(replays,previousReplays+1)
    equal(draws,previousDraws+1,"replay avoids the original draw")
    S.windowHovered=true;S.click=true
    draw()
    equal(replays,previousReplays+1)
    equal(events("click")[#events("click")][3],"ETW_Gauge0")
    S.windowHovered=false;S.click=false
    S.gauges[42]={.74,"Target",740}
    draw()
    equal(replays,previousReplays+1)
    equal(S.latestHealth,.74,"a changed gauge paints fresh values")
    S.frame=S.frame+64
  end
  hs.UI.plugins=nil
end
equal(S.fonts or 0,0,"font stack")
print("source status presenters: "..total.." assertions passed")
