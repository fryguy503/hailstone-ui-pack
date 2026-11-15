-- Import the built-in menus without copying their input, actions or lifecycle.
-- Only this trusted entry's synchronous import captures its registrations.
local context = dofile("lib/pack_context.lua")
local API = hs.UI
if context.menuImporting then return API.interfaces.LoadBase("menus.lua") end

local function finite(value)
  return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function panel(x0,y0,x1,y1,r,g,b,a,radius)
  local palette=context.instance and context.instance.palette
  local background=palette and palette.background
  if type(background)~="table" or not finite(background[1]) or not finite(background[2])
    or not finite(background[3]) or not finite(a) or a<0.9 or a>1 or not finite(radius) or radius<=0 then return false end
  if not finite(x0) or not finite(y0) or not finite(x1) or not finite(y1)
    or not finite(r) or not finite(g) or not finite(b) then return false end
  return x1>x0 and y1>y0 and math.abs(r-background[1])<0.00001
    and math.abs(g-background[2])<0.00001 and math.abs(b-background[3])<0.00001
end

local function decorate(callback)
  local failed=false
  return function(...)
    local original=ui.DrawRectFilled
    local painting=false
    ui.DrawRectFilled=function(x0,y0,x1,y1,r,g,b,a,radius,...)
      if not failed and not painting and panel(x0,y0,x1,y1,r,g,b,a,radius) then
        painting=true
        ui.PushClipRect(x0,y0,x1,y1,true)
        local ok,why=pcall(function()
          return context.renderer.Chrome(context.instance,
            {x=x0,y=y0,w=x1-x0,h=y1-y0,s=ui.GetIO().uiScale or 1},
            {color={r,g,b,1},alpha=a})
        end)
        ui.PopClipRect()
        painting=false
        if ok then return end
        failed=true
        if type(ui.Log)=="function" then pcall(ui.Log,"UI menu artwork fallback: "..tostring(why)) end
      end
      return original(x0,y0,x1,y1,r,g,b,a,radius,...)
    end
    local result=table.pack(pcall(callback,...))
    ui.DrawRectFilled=original
    if not result[1] then error(result[2],0) end
    return table.unpack(result,2,result.n)
  end
end

local registrar=ui.window
local previous=context.menuImporting
context.menuImporting=true
local capturing=false
local imported=table.pack(pcall(function()
  ui.window=function(name,callback,...)
    -- The ordinary context menus already use the shared Begin decorator.
    -- The cascade draws its own opaque cards in NoBackground windows.
    if name=="EQ Menu" and type(callback)=="function" then callback=decorate(callback) end
    return registrar(name,callback,...)
  end
  capturing=true
  return API.interfaces.LoadBase("menus.lua")
end))
if capturing then ui.window=registrar end
context.menuImporting=previous
if not imported[1] then error(imported[2],0) end
return table.unpack(imported,2,imported.n)
