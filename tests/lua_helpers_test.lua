-- Strict synthetic helper fixtures; no game layouts, textures or client process.
local load=loadfile
local passed,assertions=0,0
local function check(ok,message)assertions=assertions+1;assert(ok,message or "check failed")end
local function equal(a,b,message)check(a==b,(message or "values differ")..": "..tostring(a).." / "..tostring(b))end
local function strict(values,label)
  return setmetatable(values,{__index=function(_,key)error("Unregistered "..label.."."..tostring(key),2)end})
end
local function env(values,parent)
  values=values or {};values._G=values
  return setmetatable(values,{__index=parent or _G})
end
local function module(path,environment)
  local chunk,why=load(path,"t",environment);assert(chunk,why);return chunk()
end
local function run(name,body)
  local ok,why=xpcall(body,debug.traceback)
  if not ok then error(name..": "..why,0)end
  passed=passed+1
end

local function widgets()
  local S={events={},colors={},depth=0,last=nil,decorations={},rectCalls={},texts={},logs={},fills={},windows=0,clips=0,chrome={},nativeBegins=0}
  local function event(kind,...)S.events[#S.events+1]={kind=kind,args=table.pack(...)}end
  local cols={};for n,name in ipairs({"Button","ButtonHovered","ButtonActive","Text","Border","BorderShadow",
    "FrameBg","FrameBgHovered","FrameBgActive","CheckMark","SliderGrab","SliderGrabActive"})do cols[name]=n end
  local UI={Col=strict(cols,"ui.Col"),WindowFlags=strict({NoBackground=1,NoInputs=6},"WindowFlags")}
  local function original(kind,label,...)
    event("original",kind,label,S.depth,...)
    for _,c in ipairs(S.colors)do equal(c[2],0);equal(c[3],0);equal(c[4],0);equal(c[5],0)end
    S.last=kind..":"..tostring(label)
    if kind=="Checkbox"then return S.checked==nil and false or S.checked,true end
    if kind=="SliderInt" or kind=="SliderFloat"then return S.slider or 5,true end
    return true
  end
  for _,kind in ipairs({"Button","SmallButton","Checkbox","SliderInt","SliderFloat"})do
    UI[kind]=function(label,...)return original(kind,label,...)end
  end
  UI.window=function()error("Helper code must never register or intercept a window")end
  local originalWindow=UI.window
  UI.Begin=function(name,...)
    if S.failBegin then error("native begin failure")end
    S.nativeBegins=S.nativeBegins+1;S.windows=S.windows+1;S.last="title:"..tostring(name);S.beginArgs=table.pack(name,...)
    if S.beginResult then return table.unpack(S.beginResult,1,S.beginResult.n)end
    if select(1,...)~=nil then return S.visible~=false,S.open~=false end
    return S.visible~=false
  end
  UI.End=function()S.windows=S.windows-1;check(S.windows>=0)end
  UI.GetWindowPos=function()return 10,20 end;UI.GetWindowSize=function()return 210,160 end
  UI.GetCursorScreenPos=function()return 20,50 end;UI.GetContentRegionAvail=function()return 190,120 end
  UI.PushClipRect=function(...)S.clips=S.clips+1;event("windowclip",...)end
  UI.PopClipRect=function()S.clips=S.clips-1;check(S.clips>=0)end
  UI.PushStyleColor=function(...)local c={...};S.colors[#S.colors+1]=c;S.depth=S.depth+1;event("push",...)end
  UI.PopStyleColor=function(n)for _=1,n do check(S.depth>0);table.remove(S.colors);S.depth=S.depth-1 end;event("pop",n)end
  UI.GetItemRect=function(controlOnly)
    S.rectCalls[#S.rectCalls+1]=controlOnly==true
    if controlOnly then return 10,20,150,40 end
    return 10,20,210,40
  end
  UI.IsItemHovered=function()return true end
  UI.IsItemActive=function()return S.active==true end
  UI.IsItemDisabled=function()return S.disabled==true end
  UI.GetIO=function()return {uiScale=2}end
  UI.CalcTextSize=function(text)check(type(text)=="string");return #text*6,12 end
  UI.DrawText=function(...)S.texts[#S.texts+1]=table.pack(...);event("text",...)end
  UI.DrawRectFilled=function(...)S.fills[#S.fills+1]=table.pack(...);event("fill",...)end
  UI.Log=function(text)S.logs[#S.logs+1]=text end
  strict(UI,"ui")
  local instance={index={windows={Synthetic="lib/compiled/windows/aa.lua"}},palette={text={1,1,1,1},disabled={0.4,0.4,0.4,1}}}
  local renderer=strict({Resolve=function(screen,actual)equal(actual,instance);S.resolved=screen;return S.appearance end,
  Chrome=function(actual,rect,opts)
    equal(actual,instance);S.chrome[#S.chrome+1]={rect=rect,opts=opts};S.chromeItem=S.last
    if S.failChrome then error("synthetic chrome failure")end
  end,DecorateWidget=function(actual,kind,rect,opts)
    equal(actual,instance);equal(S.depth,0,"colors restored before drawing")
    equal(S.last,kind..":"..opts.id,"original item identity survives")
    S.decorations[#S.decorations+1]={kind=kind,rect=rect,opts=opts}
    if S.fail then error("synthetic decoration failure")end
  end},"renderer")
  local context={instance=instance,renderer=renderer}
  local environment=env({ui=UI,dofile=function(path)
    if path=="lib/pack_source_windows.lua" then S.sourceImports=(S.sourceImports or 0)+1;return end
    equal(path,"lib/pack_context.lua");return context
  end})
  module("shared/bootstrap.lua",environment)
  return S,UI,context,environment,originalWindow
end

run("checkbox returns and item identity remain original",function()
  local S,UI,_,environment,originalWindow=widgets();S.checked=false
  local checked,changed=UI.Checkbox("Flag##stable",true)
  equal(checked,false);equal(changed,true);equal(S.last,"Checkbox:Flag##stable");equal(S.depth,0)
  local drawing=S.decorations[1];equal(drawing.opts.checked,false);equal(drawing.opts.caption,"Flag")
  equal(drawing.opts.id,"Flag##stable");equal(drawing.rect.w,200);equal(drawing.rect.s,2)
  equal(UI.window,originalWindow)
  local current=UI.Checkbox;module("shared/bootstrap.lua",environment);check(UI.Checkbox~=current,"reload installs a fresh decorator")
  local before=#S.decorations;local c,v=UI.Checkbox("After reload",true);equal(c,false);equal(v,true);equal(#S.decorations,before+1)
  local originals=0;for _,event in ipairs(S.events)do if event.kind=="original"then originals=originals+1 end end
  equal(originals,2,"reload does not call an earlier widget wrapper");equal(S.depth,0);equal(#S.logs,0)
end)
run("slider values control bounds formatting and outside caption are preserved",function()
  local S,UI,_,_,originalWindow=widgets();S.slider=7
  local value,changed=UI.SliderInt("Volume##stable",3,0,10,"%d dB")
  equal(value,7);equal(changed,true);equal(S.last,"SliderInt:Volume##stable");equal(S.depth,0)
  equal(#S.rectCalls,2);equal(S.rectCalls[1],false);equal(S.rectCalls[2],true)
  local drawing=S.decorations[1];equal(drawing.rect.w,140);equal(drawing.opts.fraction,0.7);equal(drawing.opts.valueText,"7 dB")
  equal(S.texts[1][7],"Volume");equal(S.texts[1][1],174);equal(S.texts[1][2],24);equal(UI.window,originalWindow)
end)
run("floating sliders keep disabled state and numeric labels are accepted",function()
  local S,UI=widgets();S.slider=0.125;S.disabled=true
  local value,changed=UI.SliderFloat(123,0,0,1,"%.3f")
  equal(value,0.125);equal(changed,true)
  equal(S.decorations[1].opts.caption,"123");equal(S.decorations[1].opts.id,"123")
  equal(S.decorations[1].opts.valueText,"0.125");equal(S.decorations[1].opts.enabled,false)
  equal(S.texts[1][7],"123");equal(#S.logs,0);equal(S.depth,0)
end)
run("transparent colors exist only during the original widget",function()
  local S,UI=widgets();check(UI.Button("Action"));equal(S.depth,0)
  local original
  for _,e in ipairs(S.events)do if e.kind=="original"then original=e end end
  check(original);equal(original.args[3],6);equal(#S.decorations,1)
  equal(S.events[#S.events].kind,"pop")
end)
run("decoration error paints a visible fallback then stops hiding widgets",function()
  local S,UI,context,environment,originalWindow=widgets();S.fail=true
  equal(UI.Button("Recover##id"),true);check(context.decorationError);equal(#S.logs,1)
  equal(#S.fills,1);equal(S.texts[1][7],"Recover");equal(S.depth,0);equal(S.last,"Button:Recover##id")
  S.fail=false;equal(UI.SmallButton("Still usable"),true);equal(#S.decorations,1);equal(#S.logs,1)
  local last;for _,e in ipairs(S.events)do if e.kind=="original"then last=e end end
  equal(last.args[3],0,"later original is fully visible");equal(UI.window,originalWindow)
  module("shared/bootstrap.lua",environment);equal(context.decorationError,nil,"a fixed module can retry after reload")
  equal(UI.SmallButton("Recovered"),true);equal(#S.decorations,2);equal(#S.logs,1);equal(S.depth,0)
  last=nil;for _,event in ipairs(S.events)do if event.kind=="original"then last=event end end
  equal(last.args[3],6,"recovered widget hides only its original drawing again")
end)
run("repeated bootstrap reloads keep saved native originals and balanced stacks",function()
  local S,UI,_,E=widgets();local native=rawget(E,"hailstone_skin_widgets").originals.Button
  for n=1,5 do
    module("shared/bootstrap.lua",E);equal(rawget(E,"hailstone_skin_widgets").originals.Button,native)
    check(UI.Button("Reload"..n));equal(S.depth,0);equal(#S.decorations,n);equal(#S.logs,0)
  end
  local originals=0;for _,event in ipairs(S.events)do if event.kind=="original"then originals=originals+1 end end
  equal(originals,5,"each user widget call reaches the native function exactly once")
end)
run("raw Begin decoration preserves exact returns native item state and content clip",function()
  local S,UI,_,_,window=widgets();S.beginResult=table.pack(true,false,nil,27)
  local values=table.pack(UI.Begin("Raw",true,0,true));equal(values.n,4);equal(values[1],true);equal(values[2],false);equal(values[3],nil);equal(values[4],27)
  equal(S.nativeBegins,1);equal(S.beginArgs[4],true);equal(S.last,"title:Raw");equal(S.chromeItem,S.last)
  equal(#S.chrome,2);equal(S.chrome[1].opts.frameOnly,true);equal(S.chrome[1].rect.w,210)
  equal(S.chrome[2].opts.backgroundOnly,true);equal(S.chrome[2].rect.x,20);equal(S.chrome[2].rect.y,50);equal(S.chrome[2].rect.w,190)
  equal(S.clips,0);equal(S.depth,0);equal(UI.window,window);UI.End();equal(S.windows,0)
end)
run("raw Begin excludes hidden no-background and no-input overlays",function()
  local S,UI=widgets();S.visible=false;equal(UI.Begin("Hidden"),false);UI.End();equal(#S.chrome,0)
  S.visible=true;UI.Begin("Overlay",nil,UI.WindowFlags.NoBackground);UI.End()
  UI.Begin("No inputs",nil,UI.WindowFlags.NoInputs);UI.End();equal(#S.chrome,0)
  UI.Begin("Partial input flag",nil,2);UI.End();equal(#S.chrome,2,"a partial NoInputs mask still has mouse interaction")
  equal(S.windows,0);equal(S.clips,0)
end)
run("raw Options uses authored appearance and chrome errors fail open without clip leaks",function()
  local S,UI,context,E=widgets();S.appearance={art={drawTemplate="SourceOptions",template="Other"}}
  UI.Begin("Options##hailstone",true);UI.End();equal(S.resolved,"OptionsWindow");equal(S.chrome[1].opts.template,"SourceOptions")
  S.failChrome=true;UI.Begin("Broken",true);UI.End();equal(S.clips,0);check(context.windowDecorationError);equal(#S.logs,1)
  local before=#S.chrome;UI.Begin("Usable native frame",true);UI.End();equal(#S.chrome,before)
  S.failChrome=false;module("shared/bootstrap.lua",E);equal(context.windowDecorationError,nil)
  UI.Begin("Recovered",true);UI.End();equal(#S.chrome,before+2);equal(S.windows,0)
end)
run("shared managed Begin scope handles nested windows errors and reloads",function()
  local S,UI,_,E=widgets();local scope=E.hailstone_skin_managed_begin
  local values=table.pack(scope(function()
    UI.Begin("Managed",true);equal(#S.chrome,0)
    UI.Begin("Nested raw",true);equal(#S.chrome,2);UI.End();UI.End();return "kept",nil,42
  end))
  equal(values.n,3);equal(values[1],"kept");equal(values[2],nil);equal(values[3],42)
  equal(rawget(E,"hailstone_skin_widgets").managed,nil);equal(S.windows,0)
  equal(scope(function()return "hidden early return"end),"hidden early return")
  local ok,why=pcall(scope,function()error("managed failure")end);equal(ok,false);check(why:find("managed failure",1,true))
  equal(rawget(E,"hailstone_skin_widgets").managed,nil)
  S.failBegin=true;ok,why=pcall(scope,UI.Begin,"Fails before paint",true);equal(ok,false);check(why:find("native begin failure",1,true))
  equal(rawget(E,"hailstone_skin_widgets").managed,nil);S.failBegin=false
  module("shared/bootstrap.lua",E);local before=#S.chrome
  scope(function()UI.Begin("Old scoped reference",true);UI.End()end);equal(#S.chrome,before,"saved scope and new wrapper share pending state")
  UI.Begin("Normal again",true);UI.End();equal(#S.chrome,before+2);equal(S.windows,0);equal(S.clips,0)
end)
run("plugin-private helpers use shared Begin scope without borrowing root caches",function()
  local S,UI,rootContext,rootEnv=widgets();local privateInstance={};local sentinel={owner="plugin"}
  local privateContext={instance=privateInstance,paths={},managedChrome=sentinel}
  local paints=0
  privateContext.renderer=strict({Resolve=function()return nil end,CanDraw=function()return false end,TrackWindow=function()end,
    Chrome=function(actual)equal(actual,privateInstance);paints=paints+1 end},"plugin renderer")
  local base={}
  base.Window=function(screen,title,opts,body)
    if S.failBase then error("plugin base failure")end
    if S.hiddenBase then return "hidden"end
    local visible=UI.Begin(title,true,0)
    if visible then body(20,50,180,80,2)end
    UI.End();return "preserved",nil,17
  end
  base.Dialog=base.Window
  local P={Begin=function(key)if S.failPregame then error("pregame failure")end;return UI.Begin(key,true,0)end,End=UI.End}
  local pluginUI=setmetatable({},{__index=UI,__newindex=function()error("plugin ui is read-only")end})
  local plugin=env({ui=pluginUI,hs={UI={windows=strict({Shown=function()return not S.hiddenBase end},"windows"),
    interfaces=strict({LoadBase=function(path)if path=="lib/pregame.lua"then return P end;equal(path,"lib/hud.lua");return base end},"interfaces")}},
    dofile=function(path)equal(path,"lib/pack_context.lua");return privateContext end},rootEnv)
  local H=module("shared/hud.lua",plugin)
  local returned=table.pack(H.Window("CustomPlugin","Plugin HUD",{size=function()return 100,50 end},function()end))
  equal(returned.n,3);equal(returned[1],"preserved");equal(returned[2],nil);equal(returned[3],17)
  equal(paints,1);equal(#S.chrome,0,"root Begin does not duplicate private helper chrome")
  equal(privateContext.managedChrome,sentinel);equal(rawget(rootEnv,"hailstone_skin_widgets").managed,nil)
  equal(rootContext.managedChrome,nil);equal(S.windows,0)
  S.failBase=true;local ok,why=pcall(H.Window,"CustomPlugin","Plugin HUD",{},function()end)
  equal(ok,false);check(why:find("plugin base failure",1,true));equal(privateContext.managedChrome,sentinel)
  equal(rawget(rootEnv,"hailstone_skin_widgets").managed,nil);S.failBase=false
  S.hiddenBase=true;equal(H.Window("CustomPlugin","Plugin HUD",{},function()end),"hidden");S.hiddenBase=false
  UI.Begin("Raw after hidden helper",true);UI.End();equal(#S.chrome,2,"hidden helper cannot leave a stale suppression token")
  local Q=module("shared/pregame.lua",plugin);local before=#S.chrome;local endFunction=Q.End
  check(Q.Begin("Plugin pregame"));equal(#S.chrome,before);equal(privateContext.managedChrome,sentinel);Q.End()
  equal(endFunction,UI.End);equal(S.clips,0);equal(S.windows,0)
  S.failPregame=true;ok,why=pcall(Q.Begin,"Plugin pregame");equal(ok,false);check(why:find("pregame failure",1,true))
  equal(privateContext.managedChrome,sentinel);equal(rawget(rootEnv,"hailstone_skin_widgets").managed,nil)
end)

local function hudFixture()
  local S={shown={},plans={},resolved={},checks={},draws={},chrome={},baseCalls={},bodies=0,clips=0,clipCalls={}}
  local instance={}
  local R=strict({Resolve=function(screen,actual)
    equal(actual,instance);S.resolved[#S.resolved+1]=screen;return S.plans[screen]
  end,TrackWindow=function(screen,shown,actual)equal(actual,instance);S.tracked={screen,shown}end,
  CanDraw=function(plan,actual,screen)
    equal(actual,instance);S.checks[#S.checks+1]=screen;return not S.unsupported,"unsupported fixture"
  end,Draw=function(screen,plan,actual,rect)
    equal(actual,instance);S.draws[#S.draws+1]={screen=screen,plan=plan,rect=rect};return true
  end,Chrome=function(actual,rect,opts)
    equal(actual,instance);equal(S.clips,opts.frameOnly and 1 or 0,"outer frame clip is restored before body")
    S.chrome[#S.chrome+1]={rect=rect,opts=opts}
  end},"renderer")
  local context={renderer=R,instance=instance,paths={}}
  local base={}
  local function original(kind,screen,title,opts,body)
    S.baseCalls[#S.baseCalls+1]={kind=kind,screen=screen,title=title,opts=opts}
    if S.shown[screen or title]==false and opts.shown~=true then return "hidden"end
    local w,h=opts.size(2)
    return body(10,20,w*2,h*2,2)
  end
  base.Window=function(...)return original("Window",...)end
  base.Dialog=function(...)return original("Dialog",...)end
  local api=strict({windows=strict({Shown=function(screen)return S.shown[screen]~=false end},"windows"),
    interfaces=strict({LoadBase=function(path)equal(path,"lib/hud.lua");return base end},"interfaces")},"API")
  local UI=strict({GetWindowPos=function()return 1,2 end,GetWindowSize=function()return 420,260 end,
    PushClipRect=function(...)S.clips=S.clips+1;S.clipCalls[#S.clipCalls+1]=table.pack(...)end,
    PopClipRect=function()S.clips=S.clips-1;check(S.clips>=0)end},"ui")
  local environment=env({ui=UI,hs={UI=api},dofile=function(path)equal(path,"lib/pack_context.lua");return context end})
  local wrapped=module("shared/hud.lua",environment)
  local function body()S.bodies=S.bodies+1;return "functional body"end
  local function opts()return {size=function()return 180,90 end,resizable={150,75},onClose=function()end}end
  return S,wrapped,body,opts,context,environment
end
run("complex inventory chat details and all buff menus retain their complete bodies",function()
  local S,H,body,opts,context=hudFixture()
  for _,screen in ipairs({"OptionsWindow","InventoryWindow","SpellBookWnd","MapViewWnd","TaskWnd","ItemDisplayWindow",
    "ItemDisplayWindow#3","Chat1","Chat42","PetInfoWindow","TargetWindow","BuffWindow","ShortDurationBuffWindow",
    "ExtendedTargetWnd","ExtendedTargetWindow"})do
    S.plans[screen]={rect={w=50,h=50},children={}}
    equal(H.Window(screen,screen,opts(),body),"functional body");equal(context.paths[screen],"adapted")
  end
  equal(#S.resolved,15);equal(#S.checks,0,"appearance lookup must not enable a generic body");equal(#S.draws,0);equal(S.bodies,15);equal(#S.chrome,15)
end)
run("hidden authored plans stay lazy",function()
  local S,H,body,opts=hudFixture();S.shown.Hidden=false;S.plans.Hidden={rect={w=120,h=80}}
  equal(H.Window("Hidden","Hidden",opts(),body),"hidden")
  equal(#S.resolved,0);equal(#S.draws,0);equal(S.bodies,0);equal(#S.chrome,0)
end)
run("source-compatible windows use authored size without mutating original options",function()
  local S,H,body,opts,context=hudFixture();S.plans.Source={rect={w=120,h=60},children={}}
  local options=opts();local originalSize=options.size
  H.Dialog("Source","Source",options,body)
  equal(#S.resolved,1);equal(#S.checks,1);equal(#S.draws,1);equal(S.bodies,0)
  local call=S.baseCalls[1];check(call.opts~=options);equal(call.opts.onClose,options.onClose)
  local w,h=call.opts.size(2);equal(w,120);equal(h,60);equal(call.opts.resizable[1],120);equal(call.opts.resizable[2],60)
  equal(options.size,originalSize);equal(options.resizable[1],150);equal(options.resizable[2],75)
  equal(S.draws[1].rect.w,240);equal(S.draws[1].rect.h,120);equal(S.draws[1].rect.s,2);equal(context.paths.Source,"source")
end)
run("unknown new windows keep their functional body inside selected chrome",function()
  local S,H,body,opts,context=hudFixture()
  equal(H.Window("NewClientFeature","New client feature",opts(),body),"functional body")
  equal(S.bodies,1);equal(#S.chrome,1);equal(#S.draws,0);equal(context.paths.NewClientFeature,"adapted")
  equal(S.chrome[1].rect.w,360);equal(S.chrome[1].opts.alpha,1)
  equal(H.Window(nil,"Custom addon",opts(),body),"functional body");equal(context.paths["Custom addon"],"adapted")
end)
run("unsupported source controls fall back before replacing geometry or interactions",function()
  local S,H,body,opts=hudFixture();S.unsupported=true;S.plans.Unsafe={rect={w=120,h=60}}
  local options=opts();equal(H.Dialog("Unsafe","Unsafe",options,body),"functional body")
  equal(S.baseCalls[1].opts,options);equal(S.bodies,1);equal(#S.draws,0);equal(#S.chrome,2)
end)
run("layered helpers wrap an imported base only once per context",function()
  local S,H,body,opts,_,environment=hudFixture();local current=H.Window
  equal(module("shared/hud.lua",environment),H);equal(H.Window,current)
  H.Window("NewClientFeature","New client feature",opts(),body);equal(#S.chrome,1);equal(S.bodies,1)
end)
run("preserved dialogs use their own authored frame outside the original functional body",function()
  local S,H,body,opts,context=hudFixture()
  S.plans.InventoryWindow={rect={w=123,h=45},art={drawTemplate="InventorySourceWDT",template="OtherFrame"}}
  equal(H.Dialog("InventoryWindow","Inventory",opts(),body),"functional body")
  equal(#S.resolved,1);equal(#S.draws,0);equal(S.bodies,1);equal(#S.chrome,2);equal(S.clips,0)
  local outer,inner=S.chrome[1],S.chrome[2]
  equal(outer.opts.template,"InventorySourceWDT");equal(outer.opts.frameOnly,true)
  equal(outer.rect.x,1);equal(outer.rect.y,2);equal(outer.rect.w,420);equal(outer.rect.h,260)
  equal(inner.opts.template,"InventorySourceWDT");equal(inner.opts.backgroundOnly,true);equal(inner.rect.x,10);equal(inner.rect.y,20)
  equal(inner.rect.w,360);equal(inner.rect.h,180);equal(context.paths.InventoryWindow,"adapted")
  equal(#S.clipCalls,1);equal(S.clipCalls[1][1],1);equal(S.clipCalls[1][3],421);equal(S.clipCalls[1][5],false)
end)

run("context rawget owns a plugin-local cache rather than the inherited root view",function()
  local created=0
  local function contextEnvironment(parent)
    local E=env({},parent)
    E.hs={UI=strict({Supports=function(owner,member)
      return owner=="interfaces" and (member=="LoadBase" or member=="LoadData")
    end},"API")}
    E.dofile=function(path)
      if path=="lib/pack_profile.lua"then return {id="same-selected-skin"}end
      equal(path,"lib/pack_renderer.lua")
      return strict({New=function(profile)created=created+1;return {owner=E,profile=profile,index={windows={}}}end},"renderer")
    end
    return E
  end
  local root=contextEnvironment();local rootContext=module("shared/context.lua",root)
  rootContext.paths.root=true
  local plugin=contextEnvironment(root);equal(rawget(plugin,"hailstone_skin_context"),nil)
  equal(plugin.hailstone_skin_context,rootContext,"the inherited value is present")
  local pluginContext=module("shared/context.lua",plugin)
  check(pluginContext~=rootContext);check(pluginContext.instance~=rootContext.instance);equal(pluginContext.instance.owner,plugin)
  equal(rootContext.instance.owner,root);equal(rawget(plugin,"hailstone_skin_context"),pluginContext)
  pluginContext.paths.plugin=true;equal(rootContext.paths.plugin,nil)
  equal(module("shared/context.lua",plugin),pluginContext);equal(module("shared/context.lua",root),rootContext);equal(created,2)
end)

local function pregameFixture()
  local S={visible=true,windows=0,clips=0,chrome=0,events={}}
  local instance={}
  local P={}
  P.Begin=function(...)
    S.args=table.pack(...);S.windows=S.windows+1;S.events[#S.events+1]="begin";return S.visible
  end
  P.End=function()S.windows=S.windows-1;S.events[#S.events+1]="end"end
  local originalEnd=P.End
  local context={instance=instance,renderer=strict({Chrome=function(actual,rect,opts)
    equal(actual,instance);equal(S.windows,1);equal(S.clips,1,"frame drawing temporarily widens the content clip")
    S.chrome=S.chrome+1;S.rect=rect;S.opts=opts;S.events[#S.events+1]="chrome"
    if S.paintError then error("pregame chrome failure")end
  end},"renderer")}
  S.context=context
  local UI=strict({GetWindowPos=function()return 20,30 end,GetWindowSize=function()return 462,300 end,
    GetIO=function()return {uiScale=2}end,
    PushClipRect=function(x0,y0,x1,y1,intersect)
      equal(x0,20);equal(y0,30);equal(x1,482);equal(y1,330);equal(intersect,false)
      S.clips=S.clips+1;S.events[#S.events+1]="clip"
    end,PopClipRect=function()S.clips=S.clips-1;S.events[#S.events+1]="unclip"end,
    Log=function(text)S.logged=text end},"ui")
  local E=env({ui=UI,hs={UI={interfaces=strict({LoadBase=function(path)equal(path,"lib/pregame.lua");return P end},"interfaces")}},
    dofile=function(path)equal(path,"lib/pack_context.lua");return context end})
  return S,module("shared/pregame.lua",E),originalEnd,E
end
run("pregame source chrome follows Begin and precedes content without changing End",function()
  local S,P,originalEnd=pregameFixture()
  check(P.Begin("login",4,5,420,1.25));equal(S.args.n,5);equal(S.args[1],"login");equal(S.args[4],420);equal(S.args[5],1.25)
  equal(S.rect.x,20);equal(S.rect.w,462);equal(S.rect.h,300);equal(S.rect.s,2);equal(S.opts.opaque,true)
  equal(table.concat(S.events,","),"begin,clip,chrome,unclip")
  equal(S.clips,0,"the original inner clip is restored before controls");equal(P.End,originalEnd)
  S.events[#S.events+1]="body";P.End();equal(S.windows,0);equal(S.events[#S.events],"end")
end)
run("hidden pregame cards still close the original window without extra drawing",function()
  local S,P,originalEnd=pregameFixture();S.visible=false
  equal(P.Begin("login",0,0,420,1),false);equal(S.chrome,0);equal(S.clips,0);equal(S.windows,1)
  equal(P.End,originalEnd);P.End();equal(S.windows,0)
end)
run("Default pregame inheritance paints once when the selected helper loads again",function()
  local S,P,_,E=pregameFixture();local begin=P.Begin
  equal(module("shared/pregame.lua",E),P);equal(P.Begin,begin)
  P.Begin("serverselect",0,0,420,1);P.End();equal(S.chrome,1);equal(S.clips,0);equal(S.windows,0)
end)
run("pregame decoration failure restores clipping and preserves the native End path",function()
  local S,P,originalEnd=pregameFixture();S.paintError=true
  check(P.Begin("login",0,0,420,1));equal(S.clips,0);check(S.context.windowDecorationError);check(S.logged)
  equal(P.End,originalEnd);P.End();equal(S.windows,0)
  local before=S.chrome;check(P.Begin("login",0,0,420,1));P.End();equal(S.chrome,before,"broken art fails open")
  S.paintError=false;S.context.windowDecorationError=nil;check(P.Begin("login",0,0,420,1));P.End();equal(S.chrome,before+1)
end)
run("standalone source status windows require session visibility plan and audited behavior",function()
  local S={registrations=0,shown={},plans={},compatible={},resolved={},calls={},shownCalls=0,callbacks={}}
  local instance={}
  local context={instance=instance,renderer=strict({Resolve=function(screen,actual)
    equal(actual,instance);S.resolved[#S.resolved+1]=screen;return S.plans[screen]
  end,CanDraw=function(plan,actual,screen)equal(actual,instance);return S.compatible[screen]==true end},"renderer")}
  local hud=strict({Window=function(screen,title,opts,body)
    S.calls[#S.calls+1]={screen=screen,title=title,opts=opts};equal(type(body),"function")
  end},"hud")
  local api=strict({session=strict({InGame=function()return S.inGame end},"session"),
    windows=strict({Shown=function(screen)S.shownCalls=S.shownCalls+1;return S.shown[screen]end},"windows")},"API")
  local window=function(name,callback)
    equal(name,"Skin status windows");S.registrations=S.registrations+1;S.callback=callback;S.callbacks[name]=callback
  end
  local UI=strict({window=window},"ui")
  local E=env({hs={UI=api},ui=UI,dofile=function(path)
    if path=="lib/pack_context.lua" then return context end
    equal(path,"lib/hud.lua");return hud
  end})
  module("shared/source_windows.lua",E);equal(S.registrations,1);equal(UI.window,window)
  S.callback();equal(S.shownCalls,0);equal(#S.resolved,0);equal(#S.calls,0)
  S.inGame=true;S.shown.CastingWindow=true;S.plans.CastingWindow={};S.compatible.CastingWindow=true
  S.callback();equal(#S.calls,1);equal(S.calls[1].screen,"CastingWindow");equal(S.calls[1].opts.closable,false)
  local w,h=S.calls[1].opts.size();equal(w,260);equal(h,72)
  S.shown.AggroMeterWnd=true;S.plans.CastingWindow=nil;S.plans.AggroMeterWnd={};S.compatible.AggroMeterWnd=false
  S.callback();equal(#S.calls,1,"missing/unverified graphs never open a blank replacement")
  S.compatible.AggroMeterWnd=true;S.callback();equal(#S.calls,2);equal(S.calls[2].screen,"AggroMeterWnd");equal(S.calls[2].opts.closable,true)
  local previous=S.callback;module("shared/source_windows.lua",E);equal(S.registrations,2,"registration replaces the same owner/name")
  check(S.callback~=previous);local count=0;for _ in pairs(S.callbacks)do count=count+1 end;equal(count,1)
  -- Host load_file removes callbacks owned by the reloaded entry, while globals
  -- and context survive. The import must restore its callback rather than skip.
  S.callbacks["Skin status windows"]=nil;S.callback=nil
  module("shared/source_windows.lua",E);equal(S.registrations,3);check(S.callbacks["Skin status windows"])
  S.shown={};local before=#S.calls;S.callback();equal(#S.calls,before);equal(UI.window,window)
end)

print(string.format("Lua helpers: %d cases, %d assertions passed",passed,assertions))
