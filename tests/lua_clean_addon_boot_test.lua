-- Runs the actual installed bootstrap and every bundled plan without ui-data,
-- a compiler, a source-game directory, or a graphical client. UI/base stubs only
-- register inactive callbacks; the package's code and presentation data are real.
local packageRoot,ids=assert(arg[1],"package root required"),assert(arg[2],"skin IDs required")
local realLoadfile=loadfile
local checked,plans,baseReads,codeReads,dataReads=0,0,0,0,0
local identities={}
local function check(ok,message)checked=checked+1;assert(ok,message)end
local function exists(path)local f=io.open(path,"rb");if f then f:close();return true end;return false end
local function logical(path)
  check(type(path)=="string"and path:match("%.lua$")~=nil,"only Lua modules may load")
  check(not path:find("..",1,true)and not path:find("\\",1,true)and not path:find(":",1,true)
    and path:sub(1,1)~="/","module path must remain in the addon")
end
for skin in ids:gmatch("[^,]+")do
  local selected=packageRoot.."/ui/"..skin
  local defaults=packageRoot.."/ui/default"
  local cache,callbacks,logs={},{},{}
  local privateReads=0
  local env={}
  for _,key in ipairs{"assert","error","ipairs","pairs","next","pcall","xpcall","select","tostring","tonumber",
    "type","rawget","rawset","setmetatable","getmetatable","rawequal","math","string","table","utf8","_VERSION"}do
    env[key]=_G[key]
  end
  env._G=env
  local baseHud={T={},Window=function()error("inactive bootstrap must not draw windows")end,
    Dialog=function()error("inactive bootstrap must not draw dialogs")end}
  local function read(path)
    if cache[path]~=nil then return cache[path]end
    local isData=path:find("/lib/layouts/",1,true)~=nil
    local fn,why=realLoadfile(path,"t",isData and{}or env)
    check(fn~=nil,why or("module unavailable: "..path))
    local result=fn()
    if isData then
      dataReads=dataReads+1;check(type(result)=="table","layout modules must return literal tables")
    else codeReads=codeReads+1 end
    if result~=nil then cache[path]=result end
    return result
  end
  local api={
    interfaces={
      LoadData=function()
        privateReads=privateReads+1
        error("bundled addon must not read private ui-data or invoke the old compiler loader")
      end,
      LoadBase=function(path)
        logical(path)
        if path:match("^lib/layouts/")then
          baseReads=baseReads+1
          check(skin~="default","Default must not borrow an undeclared layout base")
          return read(defaults.."/"..path)
        end
        if path=="lib/hud.lua"then return baseHud end
        if path=="lib/layout.lua"then return {Solve=function()return{}end}end
        error("unexpected base-code dependency during bootstrap: "..path)
      end,
      Image=function()return nil end,
    },
    session={InGame=function()return false end,GameState=function()return 0 end},
    character={Name=function()return nil end},chat={Windows=function()return{}end},
  }
  api.Supports=function(module,member)
    return api[module]~=nil and(member==nil or type(api[module][member])=="function")
  end
  env.hs={UI=api}
  env.ui={Col={},WindowFlags={NoBackground=1,NoInputs=2},
    GetFrameCount=function()return 0 end,
    window=function(name,callback)callbacks[#callbacks+1]={name=name,callback=callback}end,
    Log=function(text)logs[#logs+1]=text end,
    Begin=function()error("inactive bootstrap must not begin native windows")end}
  for _,kind in ipairs{"Button","SmallButton","Checkbox","SliderInt","SliderFloat"}do
    env.ui[kind]=function()error("inactive bootstrap must not activate widgets")end
  end
  env.dofile=function(path)
    logical(path)
    local own=selected.."/"..path
    if exists(own)then return read(own)end
    if skin~="default"and exists(defaults.."/"..path)then return read(defaults.."/"..path)end
    error("missing packaged module: "..skin.."/"..path)
  end
  env.dofile("zz_pack.lua")
  local context=rawget(env,"hailstone_skin_context")
  check(type(context)=="table","real bootstrap did not create its context")
  check(context.profile.id==skin,"selected profile changed identity")
  check(type(context.instance.index.skin)=="string"and
    context.instance.index.skin:lower()==context.profile.source:lower(),"selected skin did not load its own layout index")
  check(context.profile.index=="lib/layouts/index.lua","normal addon still depends on private compiler paths")
  check(not identities[context.profile.id:lower()],"duplicate interface identity")
  identities[context.profile.id:lower()]=true
  local count=0
  for screen in pairs(context.instance.index.windows)do
    local plan=context.renderer.Resolve(screen,context.instance)
    check(type(plan)=="table"and plan.type=="Screen","unresolved installed layout: "..skin.."/"..screen)
    count=count+1
  end
  check(count>=20,"normal addon contains only a scaffold instead of real window data")
  for _,screen in ipairs{"InventoryWindow","PlayerWindow","HotButtonWnd","ChatWindow","ItemDisplayWindow",
    "TargetWindow","GroupWindow","BuffWindow","ShortDurationBuffWindow","CastSpellWnd","ExtendedTargetWnd"}do
    check(context.renderer.Resolve(screen,context.instance)~=nil,"primary window data missing: "..skin.."/"..screen)
  end
  check(#callbacks>0,"actual bootstrap did not register its UI callbacks")
  for _,entry in ipairs(callbacks)do entry.callback()end
  check(privateReads==0,"startup attempted the stale private-data loader, even if an error was swallowed")
  check(#logs==0,"inactive bootstrap reported an unexpected UI error")
  plans=plans+count
end
local total=0;for _ in pairs(identities)do total=total+1 end
check(total==20,"all twenty installed interfaces must bootstrap")
check(baseReads>0,"custom skins must exercise the packaged Default inheritance path")
check(dataReads>20,"real lazy layout buckets were not loaded")
print(string.format("Clean addon boot: %d skins, %d layouts, %d assertions passed; %d code and %d data reads",
  total,plans,checked,codeReads,dataReads))
