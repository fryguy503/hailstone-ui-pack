local load=loadfile
local cases,assertions=0,0
local function check(ok,message)assertions=assertions+1;assert(ok,message or "check failed")end
local function equal(a,b,message)check(a==b,(message or "values differ")..": "..tostring(a).." / "..tostring(b))end
local function run(name,callback)
  local ok,why=xpcall(callback,debug.traceback)
  if not ok then error(name..": "..why,0) end
  cases=cases+1
end
local function packEqual(got,want)
  equal(got.n,want.n)
  for i=1,want.n do equal(got[i],want[i]) end
end

local function fixture(nested)
  local state={registrations={},fills={},chrome={},clips=0,logs={},imports=0,owner="selected/menus.lua"}
  local context={instance={palette={background={0.2,0.3,0.4,1}}},renderer={}}
  local UI={}
  local function registrar(...)
    local values=table.pack(...)
    state.registrations[values[1]]={values=values,owner=state.owner}
    return "registered",nil,17
  end
  UI.window=registrar
  UI.DrawRectFilled=function(...)state.fills[#state.fills+1]=table.pack(...);return "original fill" end
  UI.PushClipRect=function(x0,y0,x1,y1,intersect)
    equal(intersect,true);check(x1>x0 and y1>y0);state.clips=state.clips+1
  end
  UI.PopClipRect=function()check(state.clips>0);state.clips=state.clips-1 end
  UI.GetIO=function()return {uiScale=1.5}end
  UI.Log=function(text)state.logs[#state.logs+1]=text end
  local originalFill=UI.DrawRectFilled
  context.renderer.Chrome=function(instance,box,opts)
    equal(instance,context.instance);equal(state.clips,1)
    state.chrome[#state.chrome+1]={box=box,opts=opts}
    -- Chrome also fills the same background: the guard must prevent recursion.
    UI.DrawRectFilled(box.x,box.y,box.x+box.w,box.y+box.h,0.2,0.3,0.4,1,9)
    if state.artError then error("synthetic art error") end
    return false -- coherent fallback drawing is still a successful decoration
  end
  local environment={ui=UI,hs={UI={interfaces={}}},dofile=function(path)
    equal(path,"lib/pack_context.lua");return context
  end}
  environment._G=environment
  setmetatable(environment,{__index=_G})
  local function source()
    local chunk,why=load("shared/menus.lua","t",environment);assert(chunk,why)
    return chunk()
  end
  environment.hs.UI.interfaces.LoadBase=function(path)
    equal(path,"menus.lua");state.imports=state.imports+1
    if nested and state.imports==1 then return source() end
    if state.importError then error(state.importError) end
    local ordinary=function(...)state.ordinaryArgs=table.pack(...);return "ordinary",nil,3 end
    state.ordinary=ordinary
    local manual=function(...)
      state.callbackArgs=table.pack(...)
      state.actions=(state.actions or 0)+1
      if state.beforeDraw then state.beforeDraw() end
      UI.DrawRectFilled(10,20,210,120,0.2,0.3,0.4,0.98,9)
      if state.callbackError then error(state.callbackError) end
      return "manual",nil,8
    end
    state.manual=manual
    packEqual(table.pack(UI.window("Game Menus",ordinary,"ordinary-extra")),table.pack("registered",nil,17))
    packEqual(table.pack(UI.window("EQ Menu",manual,"manual-extra",nil,23)),table.pack("registered",nil,17))
    local foreign=function()return "foreign"end
    state.foreign=foreign
    UI.window("Unrelated callback",foreign)
    return "loaded",nil,29
  end
  return state,context,UI,source,registrar,originalFill
end

run("scoped registration preserves names arguments ownership and results",function()
  local S,C,UI,source,registrar,fill=fixture(false)
  packEqual(table.pack(source()),table.pack("loaded",nil,29))
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill);equal(C.menuImporting,nil)
  equal(S.registrations["Game Menus"].values[2],S.ordinary)
  equal(S.registrations["Unrelated callback"].values[2],S.foreign)
  local registered=S.registrations["EQ Menu"]
  equal(registered.owner,"selected/menus.lua");equal(registered.values.n,5)
  equal(registered.values[3],"manual-extra");equal(registered.values[4],nil);equal(registered.values[5],23)
  check(registered.values[2]~=S.manual)
  packEqual(table.pack(registered.values[2]("argument",nil,31)),table.pack("manual",nil,8))
  packEqual(S.callbackArgs,table.pack("argument",nil,31))
  equal(S.actions,1);equal(#S.chrome,1);equal(#S.fills,1);equal(S.clips,0)
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill)
  local decorated=S.chrome[1];equal(decorated.box.x,10);equal(decorated.box.w,200)
  equal(decorated.box.s,1.5);equal(decorated.opts.alpha,0.98)
end)

run("nested selected Default Modern imports decorate exactly once and reload registers again",function()
  local S,C,UI,source,registrar,fill=fixture(true)
  source();equal(S.imports,2);equal(UI.window,registrar);equal(C.menuImporting,nil)
  local first=S.registrations["EQ Menu"].values[2]
  first();equal(#S.chrome,1);equal(#S.fills,1);equal(S.actions,1)
  -- A real entry reload clears its registrations while retaining VM globals.
  S.registrations={};S.imports=0
  source();local second=S.registrations["EQ Menu"].values[2]
  check(second~=first);second();equal(#S.chrome,2);equal(#S.fills,2)
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill);equal(C.menuImporting,nil);equal(S.clips,0)
end)

run("unrelated drawing and fade highlights retain exact original calls",function()
  local S,_,UI,source,_,fill=fixture(false)
  source()
  local expected={
    table.pack(1,2,3,4,0.2,0.3,0.4,0.49,9),
    table.pack(1,2,3,4,0.9,0.3,0.4,1,9),
    table.pack(1,2,3,4,0.2,0.3,0.4,1,0),
    table.pack(1,2,3,4,0.2,0.3,0.4,1,9,"extra"),
  }
  S.beforeDraw=function()
    for i=1,3 do UI.DrawRectFilled(table.unpack(expected[i],1,expected[i].n)) end
  end
  S.registrations["EQ Menu"].values[2]()
  for i=1,3 do packEqual(S.fills[i],expected[i]) end
  equal(#S.chrome,1);equal(UI.DrawRectFilled,fill)
  -- No decorator survives into an unrelated callback or later direct drawing.
  UI.DrawRectFilled(table.unpack(expected[4],1,expected[4].n));packEqual(S.fills[#S.fills],expected[4])
end)

run("art failure fails open restores clip and does not repeat actions",function()
  local S,_,UI,source,registrar,fill=fixture(false)
  source();S.artError=true
  local callback=S.registrations["EQ Menu"].values[2]
  packEqual(table.pack(callback()),table.pack("manual",nil,8))
  equal(S.actions,1);equal(S.clips,0);equal(#S.chrome,1);equal(#S.fills,2);equal(#S.logs,1)
  equal(S.fills[2][8],0.98)
  callback();equal(S.actions,2);equal(#S.chrome,1);equal(#S.fills,3);equal(#S.logs,1)
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill)
end)

run("callback errors retain identity after restoring functions and clip",function()
  local S,_,UI,source,registrar,fill=fixture(false)
  source();local problem={reason="original menu error"};S.callbackError=problem
  local ok,why=pcall(S.registrations["EQ Menu"].values[2])
  equal(ok,false);equal(why,problem);equal(S.actions,1);equal(S.clips,0)
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill)
end)

run("nested import errors restore marker and registrar and permit retry",function()
  local S,C,UI,source,registrar,fill=fixture(true)
  local problem={reason="import error"};S.importError=problem
  local ok,why=pcall(source);equal(ok,false);equal(why,problem)
  equal(UI.window,registrar);equal(UI.DrawRectFilled,fill);equal(C.menuImporting,nil)
  S.imports=0;S.importError=nil
  packEqual(table.pack(source()),table.pack("loaded",nil,29))
  check(S.registrations["EQ Menu"]);equal(UI.window,registrar);equal(C.menuImporting,nil)
end)

print(string.format("Lua menus: %d cases, %d assertions passed",cases,assertions))
