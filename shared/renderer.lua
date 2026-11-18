-- Lua presentation engine for bundled, data-only layouts.
-- No XML reader and no interception of ui.window or plugin registrations.
local B = dofile("lib/pack_bindings.lua")
local R = {}
local instances = {} -- private to this renderer module/environment; never write a plugin's inherited globals
local unpack = table.unpack
local WHITE = {1, 1, 1, 1}
local DEFAULT = {text={0.92,0.92,0.9,1}, disabled={0.5,0.5,0.5,1}, background={0.08,0.08,0.09,0.96},
                 border={0.42,0.42,0.4,1}, hp={0.68,0.13,0.1,1}, mana={0.12,0.25,0.72,1}}
local supported = {Screen=true, Page=true, TabBox=true, Label=true, StaticText=true, Button=true, Gauge=true,
  InvSlot=true, SpellGem=true, HotButton=true, Editbox=true, Slider=true, Listbox=true, Combobox=true,
  STMLbox=true, StaticAnimation=true, StaticTintedBlendAnimation=true, StaticFrame=true, StaticHeader=true,
  LayoutBox=true, HorizontalLayoutBox=true, VerticalLayoutBox=true, TileLayoutBox=true, TemplateContainer=true}

local function number(value, default)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return default or 0 end
  return n
end
local function clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function truth(value) return value == true or value == 1 or value == "true" end
local function color(value, default)
  if type(value) ~= "table" then return default or WHITE end
  local r,g,b,a = number(value.r or value.R or value[1]), number(value.g or value.G or value[2]),
    number(value.b or value.B or value[3]), value.a or value.Alpha or value[4]
  if a~=nil then a=number(a) end
  local unit = math.max(r,g,b, a or 0) > 1 and 255 or 1
  return {r/unit,g/unit,b/unit,(a == nil and unit or a)/unit}
end
local function flag(group, member) return ui[group] and ui[group][member] or 0 end
local function emit(instance, key, message)
  if not instance.messages[key] then instance.messages[key] = message end
end
local function find(instance, category, name)
  if type(name) ~= "string" or name == "" then return nil end
  local entries = instance.index and instance.index[category]
  if not entries then return nil end
  if entries[name] then return entries[name] end
  local folded = instance.folded[category]
  if not folded then
    folded = {}; instance.folded[category] = folded
    for key, value in pairs(entries) do folded[key:lower()] = value end
  end
  return folded[name:lower()]
end
local function load(instance, path, baseOnly)
  local root=instance.dataRoot or "lib/compiled"
  if type(path) ~= "string" or path:sub(1,#root+1)~=root.."/"
      or not path:match("^lib/[%w_./-]+%.lua$")
      or path:find("..",1,true) or path:find("//",1,true) then
    return nil, "Invalid layout-data path"
  end
  local ok,data
  if root=="lib/layouts" then
    if baseOnly then ok,data=pcall(B.Call,"interfaces","LoadBase",path)
    else ok,data=pcall(dofile,path) end
  else
    -- Explicit developer profiles can still use the optional local data service.
    -- Shipped profiles always use lib/layouts and never inspect stale ui-data.
    ok,data=pcall(B.Call,"interfaces","LoadData",path,baseOnly==true)
  end
  if not ok or type(data) ~= "table" then return nil, "Cannot load packaged layout: " .. path end
  return data
end
local function inflate(node,depth)
  if type(node)~="table" or (depth or 0)>64 then return nil end
  if node.type then return node end
  if type(node[1])~="string" then return nil end
  local r,a,art=node[5] or {},node[6] or {},node[10] or {}
  local mask=number(a[9])
  local result={type=node[1],item=node[2],name=node[3] or node[2],source=node[4],
    rect={x=r[1],y=r[2],w=r[3],h=r[4]},
    anchors={topToTop=a[1],bottomToTop=a[2],leftToLeft=a[3],rightToLeft=a[4],
      top=a[5],bottom=a[6],left=a[7],right=a[8],
      explicit={top=mask&1~=0,bottom=mask&2~=0,left=mask&4~=0,right=mask&8~=0}},
    text=node[7],font=node[8],colors=node[9] or {},
    art={animation=art[1],background=art[2],template=art[3],drawTemplate=art[4]},
    eqType=node[11],fields=node[12] or {},children={},slot=node[14],gaugeEqType=node[15]}
  for _,child in ipairs(node[13] or {}) do
    local expanded=inflate(child,(depth or 0)+1);if not expanded then return nil end
    result.children[#result.children+1]=expanded
  end
  return result
end

function R.New(profile)
  profile = profile or {}
  local key = tostring(profile.id or profile.source or profile) .. "\n" .. tostring(profile.index)
    .. "\n" .. tostring(profile.revision or profile.generation or "")
  if instances[key] then return instances[key] end
  local instance = {profile=profile, messages={}, folded={}, plans={}, textures={}, controls={}, preflight={},buckets={},baseBuckets={}}
  instance.dataRoot=type(profile.index)=="string" and profile.index:match("^(lib/layouts)/") or "lib/compiled"
  local index, why = load(instance, profile.index or "lib/compiled/index.lua")
  if index and profile.source~=nil and (type(profile.source)~="string" or type(index.skin)~="string"
      or index.skin:lower()~=profile.source:lower()) then
    why="Packaged layout data does not match the selected interface: "..tostring(profile.source)
    index=nil -- inherited Default data cannot stand in for an uncompiled selected skin
  end
  if index and (index.version == 1 or index.version == 2) then
    if profile.id~="default" and B.Function("interfaces",instance.dataRoot=="lib/layouts" and "LoadBase" or "LoadData") then
      local parent=load(instance,profile.index or "lib/compiled/index.lua",true)
      if type(parent)=="table" and (parent.version==1 or parent.version==2) then
        for _,category in ipairs({"windows","images","animations","templates","defaults","sources"}) do
          local merged,keys={},{}
          for name,value in pairs(parent[category] or {}) do merged[name]=value;keys[name:lower()]=name end
          for name,value in pairs(index[category] or {}) do
            local previous=keys[name:lower()];if previous then merged[previous]=nil end
            merged[name]=value;keys[name:lower()]=name
          end
          index[category]=merged
        end
      end
    end
    instance.index = index
    for n, item in ipairs(index.diagnostics or {}) do
      emit(instance,"compile:"..n, tostring(item.kind or "source") .. ": " .. tostring(item.name or item.message or item.file or ""))
    end
  else
    instance.index = {windows={},images={},animations={},templates={},style={}}
    emit(instance,"layout",why or "Unsupported layout-data version; reinstall the UI pack in Add-ons")
  end
  instance.style = instance.index.style or {}
  for _,entry in pairs(instance.index.templates or {}) do
    local defaults=(instance.index.defaults or {})[entry.type]
    if defaults then entry.fields=setmetatable(entry.fields or {},{__index=defaults}) end
  end
  instance.palette = {}
  for name, value in pairs(DEFAULT) do instance.palette[name] = value end
  for name, value in pairs(instance.style.palette or {}) do instance.palette[name] = color(value) end
  instances[key] = instance
  return instance
end

function R.Resolve(screen, instance)
  if not instance then return nil end
  local alias = (instance.profile.screenAliases or {})[screen]
    or (find(instance,"windows",screen) and screen) or B.Template(screen)
  if instance.plans[alias] ~= nil then return instance.plans[alias] or nil end
  local path = find(instance, "windows", alias)
  if not path then
    emit(instance,"screen:"..alias,"No authored layout for "..alias.."; using the themed functional presentation")
    instance.plans[alias] = false; return nil
  end
  local plan,why
  if instance.index.storage=="buckets-v1" then
    local hash=path:match("/([%x]+)%.lua$")
    if hash then
      local bucket=string.format(instance.dataRoot.."/buckets/%02x.lua",tonumber(hash:sub(1,2),16)%32)
      if instance.buckets[bucket]==nil then instance.buckets[bucket]=load(instance,bucket) or false end
      plan=instance.buckets[bucket] and instance.buckets[bucket][path]
      if not plan then
        if instance.baseBuckets[bucket]==nil then
          instance.baseBuckets[bucket]=load(instance,bucket,true) or false
        end
        plan=instance.baseBuckets[bucket] and instance.baseBuckets[bucket][path]
      end
    end
    why="Cannot find compiled window in its own or inherited bucket: "..tostring(alias)
  else plan,why=load(instance,path) end
  if not plan then emit(instance,"plan:"..alias,why); instance.plans[alias]=false; return nil end
  if instance.index.encoding=="node-tuples-v1" then
    plan=inflate(plan,0)
    if not plan then emit(instance,"plan:"..alias,"Malformed compact control graph: "..alias);instance.plans[alias]=false;return nil end
  end
  local function hydrate(node)
    local defaults=(instance.index.defaults or {})[node.type]
    if defaults then node.fields=setmetatable(node.fields or {},{__index=defaults}) end
    if not node._packColorsNormalized then
      for name,c in pairs(node.colors or {}) do
        node.colors[name]={number(c.r or c.R or c[1])/255,number(c.g or c.G or c[2])/255,
          number(c.b or c.B or c[3])/255,number(c.a or c.Alpha or c[4],255)/255}
      end
      node._packColorsNormalized=true
    end
    for _,child in ipairs(node.children or {}) do hydrate(child) end
  end
  hydrate(plan)
  instance.plans[alias] = plan
  return plan
end

function R.Diagnostics(instance)
  if not instance or not instance.messages then instance = R.New(instance) end
  local out = {}
  for _, message in pairs(instance.messages) do out[#out+1] = message end
  table.sort(out)
  return out
end

local function selector(instance, role)
  local chosen = instance.style[role]
  return type(chosen)=="table" and chosen.template or chosen
end
local function gaugeRole(name)
  name=tostring(name):lower()
  if name:find("target",1,true) then return "target" end
  if name:find("mana",1,true) then return "mana" end
  if name:find("endur",1,true) or name:find("stamina",1,true) then return "endurance" end
  if name:find("cast",1,true) then return "casting" end
  if name:find("experience",1,true) or name:find("xp",1,true) or name=="aa" or name:find(".aa",1,true) then return "experience" end
  return "hp"
end
local function template(instance, reference, depth)
  if type(reference)=="table" then return reference.fields or reference end
  if not reference or reference=="" then return nil end
  depth = depth or 0
  if depth > 8 then emit(instance,"template-cycle:"..reference,"Cyclic artwork template: "..reference); return nil end
  local entry = find(instance,"templates",reference)
  if not entry then return nil end
  local fields = entry.fields or entry
  if fields.Template and fields.Template~=reference then
    local base = template(instance,fields.Template,depth+1)
    if base then local merged = {}; for k,v in pairs(base) do merged[k]=v end; for k,v in pairs(fields) do merged[k]=v end; return merged end
  end
  return fields
end
local function nodeTemplate(instance, node, role)
  local a,f = node.art or {}, node.fields or {}
  local chosen
  if role=="Gauge" then
    local entry=(instance.style.gauges or {})[gaugeRole(node.name)]
    chosen=type(entry)=="table" and entry.template or entry
  end
  return template(instance,a.drawTemplate) or template(instance,f[role.."DrawTemplate"])
    or template(instance,a.template) or template(instance,chosen) or template(instance,selector(instance,role:lower()))
end
local function frame(instance, animation, at)
  local entry = find(instance,"animations",animation)
  if not entry then return nil end
  local frames = entry.frames or {}
  if #frames==0 then return nil end
  if at then return frames[clamp(math.floor(at)+1,1,#frames)] end
  if not truth(entry.cycle) or #frames==1 then return frames[1] end
  local total=0; for _, part in ipairs(frames) do total=total+math.max(1,number(part.duration,1000)) end
  local clock=(ui.GetTime()*1000)%total
  for _, part in ipairs(frames) do clock=clock-math.max(1,number(part.duration,1000)); if clock<0 then return part end end
  return frames[#frames]
end
-- These local resources share the selected source's exact animation crops and
-- dimensions. They are compatible artwork fallbacks, not recovered originals.
-- Keep unrelated same-name atlases out: their cells can have different meanings.
local sharedImages={
  ["uifiles/qqcustom-stock/cs_buttons.bmp"]={path="uifiles/qqui-stock/CS_Buttons.bmp",w=256,h=256},
  ["uifiles/qqui-stock/buff_background.tga"]={path="uifiles/DuxaUI-stock/Buff_Background.tga",w=64,h=128},
}
local function image(instance, name)
  local entry = find(instance,"images",name)
  if not entry or not (entry.path or entry.interface_path) then
    emit(instance,"image:"..tostring(name),"Missing compiled image reference: "..tostring(name)); return nil
  end
  local clock=ui.GetFrameCount()
  local cacheKey=entry.interface_path or entry.path
  local cached=instance.textures[cacheKey]
  if cached and cached.frame==clock then return cached.texture,cached.w,cached.h end
  local texture,w,h
  if entry.interface_path then texture,w,h=B.Call("assets","InterfaceImage",entry.interface_path) end
  if not texture and entry.path then texture,w,h=B.Call("assets","Image",entry.path) end
  local shared=not texture and entry.path and sharedImages[entry.path:lower()]
  if shared then
    local fallback,fw,fh=B.Call("assets","Image",shared.path)
    if fallback and fw==shared.w and fh==shared.h then
      texture,w,h=fallback,fw,fh
      emit(instance,"shared-image:"..name,"Missing original artwork: "..entry.path
        .."; using compatible shared artwork: "..shared.path)
    end
  end
  instance.textures[cacheKey]={frame=clock,texture=texture,w=w,h=h}
  if not texture then emit(instance,"image:"..name,"Missing artwork: "..tostring(entry.path or entry.interface_path)); return nil end
  return texture,w,h
end

function R.Animation(instance, name, rect, tint, at)
  if type(name)~="string" or name=="" or rect.w<=0 or rect.h<=0 then return false end
  local animation=find(instance,"animations",name)
  if animation and truth(animation.grid) then
    emit(instance,"grid:"..name,"Grid artwork requires a resolved host cell: "..name)
    return false -- ItemIcon/ChildArt/GemInfo provide actual cells; never paint a whole item atlas.
  end
  local part=frame(instance,name,at)
  local imageName=part and part.image or name
  local texture,w,h=image(instance,imageName)
  if not texture or not w or not h or w<=0 or h<=0 then return false end
  local crop=part and part.rect or {x=0,y=0,w=w,h=h}
  local function finite(value) local n=tonumber(value);return n and n==n and n~=math.huge and n~=-math.huge and n or nil end
  local cx,cy=finite(crop.x),finite(crop.y)
  local cw,ch=finite(crop.w),finite(crop.h)
  if not cx or not cy or not cw or not ch or cx<0 or cy<0 or cw<=0 or ch<=0 or cx+cw>w or cy+ch>h then
    emit(instance,"crop:"..tostring(name),"Artwork crop is outside its actual texture: "..tostring(name));return false
  end
  local c=color(tint)
  ui.DrawImage(texture,rect.x,rect.y,rect.x+rect.w,rect.y+rect.h,
    cx/w,cy/h,(cx+cw)/w,(cy+ch)/h,unpack(c))
  return true
end
local function natural(instance, animation)
  local part=frame(instance,animation,0)
  if part then return math.max(0,number(part.rect.w)),math.max(0,number(part.rect.h)) end
  local entry=find(instance,"images",animation)
  return entry and math.max(0,number(entry.width or entry.declaredWidth)) or 0,
    entry and math.max(0,number(entry.height or entry.declaredHeight)) or 0
end
local function rect(x,y,w,h) return {x=x,y=y,w=math.max(0,w),h=math.max(0,h)} end

function R.Frame(instance, reference, box, tint, scale, edgesOnly)
  local f=template(instance,reference)
  if not f or box.w<=0 or box.h<=0 then return false end
  scale=math.max(0,number(scale,1))
  local x,y,w,h=box.x,box.y,box.w,box.h
  local function size(name) local a,b=natural(instance,name);return a*scale,b*scale end
  local tl,tr,bl,br=f.TopLeft,f.TopRight,f.BottomLeft,f.BottomRight
  local tlw,tlh=size(tl);local trw,trh=size(tr)
  local blw,blh=size(bl);local brw,brh=size(br)
  local lw=size(f.Left);local rw=size(f.Right)
  local _,th=size(f.Top);local _,bh=size(f.Bottom)
  local ltw,lth=size(f.LeftTop);local lbw,lbh=size(f.LeftBottom)
  local rtw,rth=size(f.RightTop);local rbw,rbh=size(f.RightBottom)
  local ol,ot=number(f.OverlapLeft)*scale,number(f.OverlapTop)*scale
  local oright,ob=number(f.OverlapRight)*scale,number(f.OverlapBottom)*scale
  -- Caps are independent artwork. Only the middle strips stretch; a wide
  -- ornamental corner must never widen a narrow vertical strip or its caps.
  local leftTop=tlh+lth;local leftBottom=blh+lbh
  local rightTop=trh+rth;local rightBottom=brh+rbh
  local parts={{tl,rect(x,y,tlw,tlh)},
    {f.Top,rect(x+tlw-ol,y,w-tlw-trw+ol+oright,th)},
    {tr,rect(x+w-trw,y,trw,trh)},
    {f.Left,rect(x,y+leftTop-ot,lw,h-leftTop-leftBottom+ot+ob)},
    {f.Middle or f.Center,rect(x+lw-ol,y+th-ot,w-lw-rw+ol+oright,h-th-bh+ot+ob),true},
    {f.Right,rect(x+w-rw,y+rightTop-ot,rw,h-rightTop-rightBottom+ot+ob)},
    {bl,rect(x,y+h-blh,blw,blh)},
    {f.Bottom,rect(x+blw-ol,y+h-bh,w-blw-brw+ol+oright,bh)},
    {br,rect(x+w-brw,y+h-brh,brw,brh)},
    {f.LeftTop,rect(x,y+tlh,ltw,lth)},
    {f.LeftBottom,rect(x,y+h-blh-lbh,lbw,lbh)},
    {f.RightTop,rect(x+w-rtw,y+trh,rtw,rth)},
    {f.RightBottom,rect(x+w-rbw,y+h-brh-rbh,rbw,rbh)}}
  -- Three-piece horizontal/vertical templates use the full destination cross
  -- axis, while retaining the end pieces' natural length on the stretch axis.
  if not tl and not tr and not bl and not br and not f.Top and not f.Bottom
      and not f.LeftTop and not f.LeftBottom and not f.RightTop and not f.RightBottom then
    parts={{f.Left,rect(x,y,lw,h)},{f.Middle or f.Center,rect(x+lw-ol,y,w-lw-rw+ol+oright,h),true},
      {f.Right,rect(x+w-rw,y,rw,h)}}
  elseif not tl and not tr and not bl and not br and not f.Left and not f.Right
      and not f.LeftTop and not f.LeftBottom and not f.RightTop and not f.RightBottom then
    parts={{f.Top,rect(x,y,w,th)},{f.Middle or f.Center,rect(x,y+th-ot,w,h-th-bh+ot+ob),true},
      {f.Bottom,rect(x,y+h-bh,w,bh)}}
  end
  local any=false
  ui.PushClipRect(x,y,x+w,y+h,true)
  local ok,why=pcall(function()
    for _,p in ipairs(parts) do
      if not (edgesOnly and p[3])
          and R.Animation(instance,p[1],p[2],tint) then any=true end
    end
  end)
  ui.PopClipRect()
  if not ok then error(why,0) end
  return any
end

local function filled(box,c) if box.w>0 and box.h>0 then ui.DrawRectFilled(box.x,box.y,box.x+box.w,box.y+box.h,unpack(c)) end end
local function border(box,c) ui.DrawRect(box.x,box.y,box.x+box.w,box.y+box.h,c[1],c[2],c[3],c[4],0,1) end

function R.Chrome(instance, box, opts)
  opts=opts or {}; local scale=opts.s or box.s or 1
  local c=color(opts.color,instance.palette.background); c={c[1],c[2],c[3],(opts.opaque and 0.97 or c[4])*(opts.alpha or 1)}
  if not opts.frameOnly then filled(box,c) end
  local f=template(instance,opts.template or selector(instance,"frame"))
  local any,framed=false,false
  if f then
    if not opts.frameOnly then any=R.Animation(instance,f.Background,box,{1,1,1,opts.alpha or 1}) end
    if not opts.backgroundOnly and opts.border~=false then
      framed=R.Frame(instance,f.Border,box,{1,1,1,opts.alpha or 1},scale,opts.frameOnly)
      any=framed or any
    end
    if not opts.frameOnly and not opts.backgroundOnly and opts.titleHeight and f.Titlebar then
      any=R.Frame(instance,f.Titlebar,rect(box.x,box.y,box.w,opts.titleHeight),WHITE,scale) or any
    end
  end
  if not framed and not opts.backgroundOnly and opts.border~=false then
    border(box,instance.palette.border)
    emit(instance,"frame-art","The selected frame has incomplete artwork; using a coherent border fallback")
  end
  if opts.glow and not opts.backgroundOnly then
    local glow=color(opts.glow);local width=(opts.glowWidth or 1.5)*scale
    ui.DrawRect(box.x-width/2,box.y-width/2,box.x+box.w+width/2,box.y+box.h+width/2,
      glow[1],glow[2],glow[3],glow[4]*(opts.alpha or 1),(opts.radius or 0)*scale,width)
  end
  return any
end

local function windowTemplate(plan,instance)
  local art=plan and plan.art or {};local fields=plan and plan.fields or {}
  return template(instance,art.drawTemplate) or template(instance,fields.DrawTemplate)
    or template(instance,art.template) or template(instance,selector(instance,"frame"))
end
local function windowFlag(plan,name,default)
  local value=plan and plan.fields and plan.fields[name]
  if value==nil then return default end
  return truth(value)
end
-- Nominal pixel heights of the host's public ui1..ui6 font indices. Keeping
-- these in design pixels avoids measuring a previous window's font scale.
local chromeFontHeights={10,12,13,14,16,20}
local function chromeFont(plan,instance,override)
  local selected=number(override or (plan or {}).font,0)
  if not chromeFontHeights[selected] then selected=number((instance.style.fonts or {}).title,3) end
  if not chromeFontHeights[selected] then selected=3 end
  return selected,chromeFontHeights[selected]
end

-- Physical pixels, relative to a complete source window's outer rectangle.
-- Decorative corner widths do not become client padding: the native edge
-- strips define the left/right margins, while the title reserves its height.
function R.ChromeInsets(plan,instance,scale,opts)
  scale=math.max(0,number(scale,1))
  local f=windowTemplate(plan,instance) or {}
  local b=windowFlag(plan,"Style_Border",true) and template(instance,f.Border) or nil
  local t=windowFlag(plan,"Style_Titlebar",false) and template(instance,f.Titlebar) or nil
  local function size(name) local w,h=natural(instance,name);return w*scale,h*scale end
  local left,right,top,bottom=0,0,0,0
  if b then
    left=size(b.Left or b.LeftTop or b.LeftBottom)
    right=size(b.Right or b.RightTop or b.RightBottom)
    local _,a=size(b.Top);local _,c=size(b.TopLeft);local _,d=size(b.TopRight);top=math.max(a,c,d)
    local _,e=size(b.Bottom);local _,g=size(b.BottomLeft);local _,h=size(b.BottomRight);bottom=math.max(e,g,h)
  end
  local titleHeight,titleLeft,titleRight=0,0,0
  if t then
    for _,name in ipairs({"Left","Middle","Right","TopLeft","Top","TopRight"}) do
      local _,h=size(t[name]);titleHeight=math.max(titleHeight,h)
    end
    titleLeft=size(t.Left or t.TopLeft);titleRight=size(t.Right or t.TopRight)
  end
  local titleArtHeight=titleHeight
  local selectedFont,fontHeight=chromeFont(plan,instance,opts and opts.font)
  -- A short strip is ornament, not a request for seven-pixel text. Reserve a
  -- readable selected-font band; never enlarge or squash the strip itself.
  if titleArtHeight>0 then titleHeight=math.max(titleArtHeight,(fontHeight+4)*scale) end
  local result={left=left,right=right,top=math.max(top,titleHeight),bottom=bottom,
    titleHeight=titleHeight,titleArtHeight=titleArtHeight,titleFont=selectedFont,
    titleLeft=titleLeft,titleRight=titleRight}
  local close=windowFlag(plan,"Style_Closebox",false) and template(instance,f.CloseBox) or nil
  if close and titleHeight>0 then
    local w,h=size(close.Normal)
    if w>0 and h>0 then
      result.close={width=w,height=h,right=math.max(0,(titleRight-w)/2),top=math.max(0,(titleHeight-h)/2)}
    end
  end
  return result
end

-- Pure drawing only. The owner registers movement/close inputs before calling
-- this, then places its content inside ChromeInsets. No native title is covered.
function R.WindowChrome(plan,title,outer,instance,opts)
  opts=opts or {};local s=opts.s or outer.s or 1
  local f=windowTemplate(plan,instance) or {}
  local metrics=R.ChromeInsets(plan,instance,s,opts)
  local chrome={s=s,template=f,border=windowFlag(plan,"Style_Border",true),
    alpha=opts.alpha,opaque=opts.opaque,color=opts.color}
  if windowFlag(plan,"Style_Transparent",false) then chrome.frameOnly=true end
  R.Chrome(instance,outer,chrome)
  local tint={1,1,1,opts.alpha or 1}
  if metrics.titleHeight>0 then
    R.Frame(instance,f.Titlebar,rect(outer.x,outer.y,outer.w,metrics.titleArtHeight),tint,s)
    local close=metrics.close
    if close and opts.close~=false then
      local c=template(instance,f.CloseBox) or {}
      local state=opts.closeEnabled==false and c.Disabled
        or opts.closePressed and (opts.closeHovered and c.PressedFlyby or c.Pressed)
        or opts.closeHovered and c.Flyby or c.Normal
      R.Animation(instance,state or c.Normal,rect(outer.x+outer.w-close.right-close.width,
        outer.y+close.top,close.width,close.height),tint)
    end
    if title and title~="" then
      ui.PushFont(metrics.titleFont)
      local ok,why=pcall(function()
        local tw,th=ui.CalcTextSize(tostring(title))
        local l=math.max(metrics.left,metrics.titleLeft)
        local r=math.max(metrics.right,metrics.titleRight,close and close.right+close.width or 0)
        local x=outer.x+l;local width=math.max(0,outer.w-l-r)
        ui.PushClipRect(x,outer.y,x+width,outer.y+metrics.titleHeight,true)
        local c=color(opts.titleColor or (plan and plan.colors or {}).Text,instance.palette.text)
        local success,errorText=pcall(ui.DrawText,x+math.max(0,(width-tw)/2),
          outer.y+math.max(0,(metrics.titleHeight-th)/2),c[1],c[2],c[3],c[4]*(opts.alpha or 1),tostring(title))
        ui.PopClipRect()
        if not success then error(errorText,0) end
      end)
      ui.PopFont()
      if not ok then error(why,0) end
    end
  end
  return metrics
end

function R.Geometry(node,parent)
  local n,a,f=node.rect or {},node.anchors or {},node.fields or {}
  local s=parent.s or 1
  local x,y,w,h=number(n.x)*s,number(n.y)*s,number(n.w)*s,number(n.h)*s
  local e=a.explicit or {}
  local function specified(side,field) return e[side]==true or (e[side]==nil and number(f[field])~=0) end
  if specified("left","LeftAnchorOffset") then x=(a.leftToLeft==false and parent.w or 0)+number(a.left)*(a.leftToLeft==false and -s or s)
  elseif a.leftToLeft==false then x=parent.w+x end
  if specified("top","TopAnchorOffset") then y=(a.topToTop==false and parent.h or 0)+number(a.top)*(a.topToTop==false and -s or s)
  elseif a.topToTop==false then y=parent.h+y end
  if specified("right","RightAnchorOffset") or a.rightToLeft==false then
    local right=(a.rightToLeft==false and parent.w or 0)+number(a.right)*(a.rightToLeft==false and -s or s)
    w=right-x
  end
  if specified("bottom","BottomAnchorOffset") or a.bottomToTop==false then
    local bottom=(a.bottomToTop==false and parent.h or 0)+number(a.bottom)*(a.bottomToTop==false and -s or s)
    h=bottom-y
  end
  if #(node.children or {})>0 and (node.type=="Page" or node.type=="LayoutBox" or node.type=="TemplateContainer"
      or node.type=="HorizontalLayoutBox" or node.type=="VerticalLayoutBox" or node.type=="TileLayoutBox") then
    if w==0 then w=math.max(0,parent.w-x) end
    if h==0 then h=math.max(0,parent.h-y) end
  end
  return {x=parent.x+x,y=parent.y+y,w=math.max(0,w),h=math.max(0,h),s=s}
end

local function font(instance, node)
  local value=number(node.font,3)
  if value<1 or value>6 then emit(instance,"font:"..value,"Unsupported source font "..value.."; using host font 3"); return 3 end
  return math.floor(value)
end
local function text(instance, node, box, value, tint, fitHeight)
  value=tostring(value or ""); if value=="" then return end
  ui.PushFont(font(instance,node))
  -- HUD helpers already apply the window's font scale; multiplying it by layout scale repeats that scale.
  local tw,th=ui.CalcTextSize(value)
  local size
  if fitHeight and box.h>0 and th>box.h then
    size=box.h;tw=tw*box.h/th;th=box.h
  end
  local f=node.fields or {}; local x,y=box.x,box.y
  local button=node.type=="Button"
  if button and truth(f.TextAlignRight) then x=x+box.w-tw
  elseif truth(f.Style_HCenter) or truth(f.AlignCenter) or f.Align=="Center" or button and truth(f.TextAlignCenter) then x=x+(box.w-tw)/2
  elseif truth(f.Style_RightJustify) or truth(f.AlignRight) or f.Align=="Right" then x=x+box.w-tw end
  if truth(f.Style_VCenter) or button and truth(f.TextAlignVCenter) then y=y+(box.h-th)/2 end
  if button then x=x+number(f.TextOffsetX)*(box.s or 1);y=y+number(f.TextOffsetY)*(box.s or 1) end
  local c=color(tint,instance.palette.text)
  ui.DrawText(x,y,c[1],c[2],c[3],c[4],value,size)
  ui.PopFont()
end
function R.MeasureText(instance,node,value)
  ui.PushFont(font(instance,node))
  local ok,w,h=pcall(ui.CalcTextSize,tostring(value or ""))
  ui.PopFont()
  if not ok then error(w,0) end
  return w,h -- physical pixels, including the host's current window font scale
end
function R.PaintText(screen,node,box,instance,value)
  local caption,tint=B.Text(screen,node)
  local enabled=B.State(screen,node)
  text(instance,node,box,value~=nil and value or caption,enabled==false and instance.palette.disabled
    or B.Color(screen,node) or tint or color((node.colors or {}).TextColor,instance.palette.text))
  local mx,my=ui.GetMousePos()
  if mx>=box.x and mx<box.x+box.w and my>=box.y and my<box.y+box.h then
    local tip=B.Tooltip(screen,node);if tip~="" then ui.SetTooltip(tip) end
  end
end
local function decalRect(node,box)
  local f=node.fields or {};local offset,size=f.DecalOffset,f.DecalSize
  local s=box.s or 1
  local x=type(offset)=="table" and number(offset.X or offset.x or offset[1])*s or 0
  local y=type(offset)=="table" and number(offset.Y or offset.y or offset[2])*s or 0
  local w=type(size)=="table" and number(size.CX or size.cx or size[1])*s or box.w
  local h=type(size)=="table" and number(size.CY or size.cy or size[2])*s or box.h
  return {x=box.x+x,y=box.y+y,w=math.max(0,w),h=math.max(0,h),s=s}
end
local function point(box) ui.SetCursorScreenPos(box.x,box.y) end
local function hit(id,box,enabled)
  point(box); ui.BeginDisabled(enabled==false)
  local clicked=ui.InvisibleButton(id,math.max(1,box.w),math.max(1,box.h))
  local hover,active=ui.IsItemHovered(),ui.IsItemActive()
  ui.EndDisabled()
  return clicked,hover,active
end
local function tooltip(screen,node)
  if ui.IsItemHovered(flag("HoveredFlags","AllowWhenDisabled")) then
    local tip=B.Tooltip(screen,node);if tip~="" then ui.SetTooltip(tip) end
  end
end
local function state(instance,screen,node)
  local key=screen.."\n"..B.Id(node);local record=instance.controls[key]
  if not record then record={};instance.controls[key]=record end
  return record
end
function R.TrackWindow(screen,shown,instance)
  if not screen then return end
  local record=state(instance,screen,{name="/visibility"})
  local frame=ui.GetFrameCount()
  -- Inherited presenters may return before calling HUD while hidden. A gap in
  -- draws is therefore also an opening transition, without polling or changing
  -- the model's visibility on behalf of its presenter.
  if shown and (not record.shown or record.frame and frame>record.frame+1) then record.focusPending=true end
  if not shown then record.focusPending=false end
  record.shown=shown and true or false
  record.frame=frame
end
local function consumeRight(instance)
  local theme=instance.theme
  if theme then
    local fn=ui.GetIO().alt and theme.TakeAltRightClick or theme.TakeRightClick
    if fn then fn() end
  end
end

local function buttonArt(instance,node,box,hover,pressed,checked,enabled,tint,overrides)
  local f=nodeTemplate(instance,node,"Button")
  local function selected(suffix)
    if not f then return nil end
    local function art(state)
      local value=f[state..suffix]
      return type(value)=="string" and value~="" and value or nil
    end
    local down=pressed or checked
    if not enabled then
      return down and art("PressedDisabled") or art("Disabled") or art("Normal")
    end
    return down and (hover and art("PressedFlyby") or art("Pressed"))
      or hover and art("Flyby") or art("Normal")
  end
  overrides=overrides or {}
  local base=selected("")
  local placeholder=f and find(instance,"animations",f.NormalDecal)
  local baseName=type(base)=="string" and base:lower()
  local replacePlaceholder=overrides.liveIcon and placeholder and truth(placeholder.grid)
    and (baseName=="rediconbackground" or baseName=="blueiconbackground")
  -- BuffIcons is a source prototype, not an item's backdrop. An actual live
  -- item cell uses the selected skin's neutral item well; explicit host buff
  -- backgrounds and independent pressed/hover artwork retain their meaning.
  if replacePlaceholder then base="A_InvSlot" end
  if not overrides.background and not R.Animation(instance,base,box,tint) then
    filled(box,pressed and instance.palette.border or instance.palette.background);border(box,instance.palette.border)
  end
  if not overrides.decal then R.Animation(instance,selected("Decal"),decalRect(node,box),tint) end
end

local function sliderArt(instance,node,box,fraction,hover,pressed,enabled)
  local t=nodeTemplate(instance,node,"Slider") or {}
  local vertical=truth((node.fields or {}).Vertical)
  local left,right=t.EndCapLeft,t.EndCapRight
  local lw,lh=natural(instance,left);local rw,rh=natural(instance,right)
  local s=box.s or 1
  local track=rect(box.x,box.y,box.w,box.h)
  if not vertical then
    lw=math.min(lw*s,box.w/2);rw=math.min(rw*s,box.w-lw)
    track=rect(box.x+lw,box.y,box.w-lw-rw,box.h)
    R.Animation(instance,left,rect(box.x,box.y,lw,box.h))
    R.Animation(instance,right,rect(box.x+box.w-rw,box.y,rw,box.h))
  end
  if not R.Animation(instance,t.Background or t.Middle,track) then filled(track,instance.palette.background);border(track,instance.palette.border) end
  local thumb=type(t.Thumb)=="table" and t.Thumb or {Normal=t.Thumb or t.Normal}
  local art=(enabled==false and thumb.Disabled) or pressed and (hover and thumb.PressedFlyby or thumb.Pressed)
    or hover and thumb.Flyby or thumb.Normal
  art=art or thumb.Normal
  local nw,nh=natural(instance,art)
  local knob=math.min(vertical and box.h or box.w,math.max(8*s,(vertical and nh or nw)*s))
  if nw==0 and nh==0 then knob=math.min(vertical and box.h or box.w,math.max(8*s,vertical and box.w or box.h)) end
  fraction=clamp(number(fraction),0,1)
  local handle=vertical and rect(box.x,box.y+(box.h-knob)*fraction,box.w,knob)
    or rect(box.x+(box.w-knob)*fraction,box.y,knob,box.h)
  if not R.Animation(instance,art,handle) then filled(handle,instance.palette.border) end
end
local dynamicArt,phases
local function drawButton(instance,screen,node,box,captionOverride)
  local enabled,checked,_,_,action=B.State(screen,node)
  local clicked,hover,pressed=hit("##pack:"..B.Id(node),box,enabled or action)
  local background=dynamicArt(instance,screen,node,box,"background")
  local decal=table.pack(B.Call("windows","ChildArt",screen,B.Id(node),"decal"))
  local hasDecal=decal[1]~=nil
  local liveIcon=hasDecal and decal[1]~=false and type(decal[1])~="string"
  buttonArt(instance,node,box,hover,pressed,checked,enabled,nil,{background=background,decal=hasDecal,liveIcon=liveIcon})
  dynamicArt(instance,screen,node,box,"decal",decal)
  local top,r,g,b,a=B.Call("spells","ButtonCoolDown",screen,B.Id(node),box.y,box.y+box.h)
  if top then filled(rect(box.x,math.max(top,box.y),box.w,math.max(0,box.y+box.h-math.max(top,box.y))),{r or 0,g or 0,b or 0,a or 0.6}) end
  local caption=captionOverride
  if caption==nil then caption=B.Text(screen,node) end
  text(instance,node,box,caption,enabled and B.Color(screen,node) or instance.palette.disabled)
  local rec=state(instance,screen,node)
  if ui.IsItemClicked(ui.Mouse.Left) then rec.dragged=false end
  if enabled and B.Drag(screen,node) then rec.dragged=true end
  local events=B.Events(screen,node)
  if events and events.phases then
    phases(instance,screen,node,box,function(phase,outside)
      if phase:sub(1,4)=="left" and not enabled then return false end
      if phase:sub(1,5)=="right" and not (enabled or action) then return false end
      return B.Click(screen,node,phase,outside)
    end)
  else
    if clicked and enabled and not rec.dragged then
      if B.Click(screen,node,"left")==false then emit(instance,"action:"..screen..B.Id(node),"No host action for "..screen.."/"..B.Id(node)) end
    end
    if (enabled or action) and ui.IsItemClicked(ui.Mouse.Right) then B.Click(screen,node,"right");consumeRight(instance) end
  end
  tooltip(screen,node)
end
function R.DrawButton(screen,node,box,instance,caption)
  return drawButton(instance,screen,node,box,caption)
end

local function gaugeArt(instance,node,box,fraction,tint,alpha)
  alpha=number(alpha,1)
  local function faded(value)
    local c=color(value);return {c[1],c[2],c[3],c[4]*alpha}
  end
  local f=nodeTemplate(instance,node,"Gauge")
  if not f or not R.Animation(instance,f.Background,box,{1,1,1,alpha}) then filled(box,faded(instance.palette.background)) end
  local fraction=clamp(number(fraction),0,1)
  local vertical=truth((node.fields or {}).Vertical)
  local clip=vertical and rect(box.x,box.y+box.h*(1-fraction),box.w,box.h*fraction) or rect(box.x,box.y,box.w*fraction,box.h)
  ui.PushClipRect(clip.x,clip.y,clip.x+clip.w,clip.y+clip.h,true)
  local fill=tint or instance.palette[gaugeRole(node.name)] or instance.palette.hp
  if not f or not R.Animation(instance,f.Fill or f.Gauge,box,faded(fill)) then filled(box,faded(fill)) end
  if f and truth((node.fields or {}).DrawLinesFill) then R.Animation(instance,f.LinesFill,box,faded(color((node.colors or {}).LinesFillTint,tint))) end
  ui.PopClipRect()
  if f then
    R.Animation(instance,f.Lines,box,{1,1,1,alpha}); R.Frame(instance,f.Border,box,{1,1,1,alpha},box.s)
    local lw=natural(instance,f.EndCapLeft);local rw=natural(instance,f.EndCapRight);local s=box.s or 1
    R.Animation(instance,f.EndCapLeft,rect(box.x,box.y,math.min(box.w,lw*s),box.h),{1,1,1,alpha})
    R.Animation(instance,f.EndCapRight,rect(box.x+math.max(0,box.w-rw*s),box.y,math.min(box.w,rw*s),box.h),{1,1,1,alpha})
  end
end
local function drawGauge(instance,screen,node,box,options)
  local fraction,caption,tint=B.Gauge(screen,node)
  options=options or {}
  if options.fraction~=nil then fraction=options.fraction end
  if options.caption~=nil then caption=options.caption end
  if fraction==nil then return end
  tint=options.tint or tint
  local alpha=1
  if screen=="BreathWindow" and tonumber(node.gaugeEqType or node.eqType)==8 then
    local air={0.3,0.85,0.95};local danger=(instance.theme and instance.theme.color or {}).danger or instance.palette.hp
    local remaining=clamp(number(fraction),0,1);local blend=clamp(remaining*2,0,1)
    tint={};for channel=1,3 do tint[channel]=danger[channel]*(1-blend)+air[channel]*blend end;tint[4]=1
    if remaining<0.25 then alpha=0.825+0.175*math.cos(ui.GetTime()*10) end
    caption=string.format("%d%%",math.floor(remaining*100+0.5))
  end
  local f=node.fields or {};local s=box.s or 1
  local t=nodeTemplate(instance,node,"Gauge") or {};local _,height=natural(instance,t.Background or t.Fill)
  local offsetX,offsetY=number(f.GaugeOffsetX)*s,number(f.GaugeOffsetY)*s
  local track={x=box.x+offsetX,y=box.y+offsetY,w=math.max(0,box.w-offsetX),h=math.max(0,box.h-offsetY),s=s}
  if height>0 then track.h=math.min(track.h,height*s) end
  gaugeArt(instance,node,track,fraction,tint or color((node.colors or {}).FillTint,instance.palette.hp),alpha)
  if caption~="" then
    local label=rect(box.x+number(f.TextOffsetX)*s,box.y+number(f.TextOffsetY)*s,box.w,box.h)
    text(instance,node,label,caption,B.Color(screen,node,"text")
      or color((node.colors or {}).TextColor,instance.palette.text),screen=="BreathWindow")
  end
end

phases=function(instance,screen,node,box,click)
  local rec=state(instance,screen,node);local now=ui.GetTime()
  local hovered=ui.IsItemHovered()
  if ui.IsItemClicked(ui.Mouse.Left) then rec.left={start=now,tried=false} end
  if rec.left then
    if not rec.left.tried and ui.IsMouseDown(ui.Mouse.Left) and now-rec.left.start>=0.35 then
      rec.left.tried=true;rec.left.made=click("leftheld",not hovered)==true
    end
    if ui.IsMouseReleased(ui.Mouse.Left) then
      if hovered and not rec.left.made then click("left",false) end
      rec.left=nil
    elseif not ui.IsMouseDown(ui.Mouse.Left) then rec.left=nil end
  end
  if ui.IsItemClicked(ui.Mouse.Right) then rec.right={start=now,held=false};click("rightdown",false);consumeRight(instance) end
  if rec.right then
    if ui.IsMouseDown(ui.Mouse.Right) and not rec.right.held and now-rec.right.start>=0.5 then
      rec.right.held=true;click("rightheld",not hovered)
    end
    if ui.IsMouseReleased(ui.Mouse.Right) then
      click(rec.right.held and "rightupheld" or "rightup",not hovered);rec.right=nil
    elseif not ui.IsMouseDown(ui.Mouse.Right) then rec.right=nil end
  end
end
local function drawSlot(instance,screen,node,box)
  local enabled=B.State(screen,node)
  local _,hover=hit("##slot:"..B.Id(node),box,enabled)
  local f=nodeTemplate(instance,node,"Button")
  local art=(node.art or {}).background
  if not art or art=="" then art=f and f.Normal end
  if not R.Animation(instance,art,box) then filled(box,instance.palette.background);border(box,instance.palette.border) end
  local item=B.Item(screen,node)
  local texture,u0,v0,u1,v1=B.Icon(item)
  if texture then ui.DrawImage(texture,box.x,box.y,box.x+box.w,box.y+box.h,u0,v0,u1,v1,1,1,1,1) end
  if item and item.cooldown then filled(rect(box.x,box.y+box.h*item.cooldown,box.w,box.h*(1-item.cooldown)),{0,0,0,0.6}) end
  if item and item.stackable and item.count then
    local countNode={font=node.font,fields={Style_RightJustify=true}};text(instance,countNode,rect(box.x,box.y+math.max(0,box.h-16*box.s),box.w,16*box.s),item.count)
  end
  if enabled then phases(instance,screen,node,box,function(phase,outside) return B.ItemClick(screen,node,phase,outside) end) end
  if hover then
    if item and item.name then ui.SetTooltip(item.name) else tooltip(screen,node) end
  end
end
local function drawGem(instance,screen,node,box)
  local enabled=B.State(screen,node)
  local clicked,hover=hit("##gem:"..B.Id(node),box,enabled)
  local info=B.Call("spells","GemInfo",screen,B.Id(node)) or {}
  buttonArt(instance,node,box,hover,ui.IsItemActive(),false,enabled)
  if type(info.tex)=="string" then R.Animation(instance,info.tex,box,{info.tintR or 1,info.tintG or 1,info.tintB or 1,info.tintA or 1})
  elseif info.tex then ui.DrawImage(info.tex,box.x,box.y,box.x+box.w,box.y+box.h,info.u0 or 0,info.v0 or 0,info.u1 or 1,info.v1 or 1,
      info.tintR or 1,info.tintG or 1,info.tintB or 1,info.tintA or 1) end
  local top,r,g,b,a=B.Call("spells","GemOverlay",screen,B.Id(node),box.y,box.y+box.h)
  if top then filled(rect(box.x,math.max(top,box.y),box.w,box.y+box.h-math.max(top,box.y)),{r or 0,g or 0,b or 0,a or 0.65}) end
  local dragged=B.Drag(screen,node)
  if clicked and enabled and not dragged then B.Call("spells","GemClick",B.Id(node),"left") end
  if enabled then
    local rec=state(instance,screen,node)
    if ui.IsItemClicked(ui.Mouse.Right) then rec.right={start=ui.GetTime(),held=false};B.Call("spells","GemClick",B.Id(node),"rightdown");consumeRight(instance) end
    if rec.right then
      if ui.IsMouseDown(ui.Mouse.Right) and not rec.right.held and ui.GetTime()-rec.right.start>=0.5 then
        rec.right.held=true;B.Call("spells","GemClick",B.Id(node),"rightheld")
      end
      if ui.IsMouseReleased(ui.Mouse.Right) then B.Call("spells","GemClick",B.Id(node),rec.right.held and "rightupheld" or "rightup",not hover);rec.right=nil
      elseif not ui.IsMouseDown(ui.Mouse.Right) then rec.right=nil end
    end
  end
  if hover then local tip=info.tooltip or B.Tooltip(screen,node);if tip~="" then ui.SetTooltip(tip) end end
end

local function drawHot(instance,screen,node,box)
  local targetScreen,targetId
  if B.HotTarget then targetScreen,targetId=B.HotTarget(screen,node) end
  targetScreen,targetId=targetScreen or screen,targetId or B.Id(node)
  local info=B.Call("hotbars","Info",targetScreen,targetId) or {}
  local enabled=info.enabled~=false
  local clicked,hover,pressed=hit("##hot:"..B.Id(node),box,enabled)
  buttonArt(instance,node,box,hover,pressed,info.checked,enabled)
  local tint=info.tint or {1,1,1,info.iconAlpha or 1}
  if type(info.tex)=="string" then R.Animation(instance,info.tex,box,tint)
  elseif info.tex then ui.DrawImage(info.tex,box.x,box.y,box.x+box.w,box.y+box.h,info.u0 or 0,info.v0 or 0,info.u1 or 1,info.v1 or 1,unpack(tint))
  else text(instance,node,box,info.label or "",info.social and info.color or nil) end
  if info.cooldown~=nil then
    local top=box.y+box.h*clamp(info.cooldown,0,1)
    filled(rect(box.x,top,box.w,math.max(0,box.y+box.h-top)),{0,0,0,0.6})
  end
  if info.social and info.faceCooldown and info.faceCooldown>0 then
    local top=box.y+box.h*(1-clamp(info.faceCooldown,0,1))
    filled(rect(box.x,top,box.w,box.y+box.h-top),{0,0,0,0.5})
  end
  if info.overlay and info.overlay~="" then
    text(instance,{font=1,fields={Style_RightJustify=true}},
      rect(box.x,box.y+math.max(0,box.h-14*box.s),box.w,14*box.s),info.overlay)
  end
  local key=B.Call("windows","Text",targetScreen,targetId)
  if key and key~="" then text(instance,{font=1,fields={Style_RightJustify=true}},box,key,instance.palette.disabled) end
  local rec=state(instance,screen,node)
  if ui.IsItemClicked(ui.Mouse.Left) then rec.dragged=false end
  if enabled and B.Drag(targetScreen,targetScreen==screen and targetId==B.Id(node) and node or {name=targetId}) then rec.dragged=true end
  if clicked and enabled and not rec.dragged then B.Call("hotbars","Click",targetScreen,targetId,"left")
  elseif enabled and B.Call("cursor","HoldingButton") and ui.IsMouseReleased(ui.Mouse.Left) and hover then
    B.Call("hotbars","Click",targetScreen,targetId,"left")
  end
  if enabled and ui.IsItemClicked(ui.Mouse.Right) and not ui.GetIO().alt then
    rec.right={start=ui.GetTime(),held=false};consumeRight(instance)
  end
  if rec.right then
    if not enabled then rec.right=nil
    elseif ui.IsMouseDown(ui.Mouse.Right) and not rec.right.held and ui.GetTime()-rec.right.start>=0.5 then
      rec.right.held=true;B.Call("hotbars","Click",targetScreen,targetId,"rightheld")
    elseif ui.IsMouseReleased(ui.Mouse.Right) then
      if not rec.right.held and hover then B.Call("hotbars","Click",targetScreen,targetId,"right") end
      rec.right=nil
    elseif not ui.IsMouseDown(ui.Mouse.Right) then rec.right=nil end
  end
  if hover and not ui.IsMouseDown(ui.Mouse.Right) then
    local tip=info.tooltip or info.label or B.Tooltip(screen,node)
    if tip and tip~="" then ui.SetTooltip(tip) end
  end
end

function R.PushStyle(instance)
  local token={colors=0,vars=0}
  local p=instance.palette
  local field={}; local outline={}
  for i=1,3 do
    field[i]=p.background[i]*0.9+p.text[i]*0.1
    outline[i]=p.background[i]*0.68+p.text[i]*0.32
  end
  field[4],outline[4]=1,1
  for _,entry in ipairs({{"Text",p.text},{"TextDisabled",p.disabled},{"FrameBg",field},
      {"Button",p.background},{"ButtonHovered",p.border},{"ButtonActive",p.border},
      {"Header",p.border},{"HeaderHovered",p.border},{"HeaderActive",p.border},{"Border",outline}}) do
    if ui.Col and ui.Col[entry[1]] then ui.PushStyleColor(ui.Col[entry[1]],unpack(entry[2]));token.colors=token.colors+1 end
  end
  for _,name in ipairs({"FrameRounding","WindowRounding","ChildRounding","PopupRounding","TabRounding","GrabRounding","ScrollbarRounding"}) do
    if ui.StyleVar and ui.StyleVar[name] then ui.PushStyleVar(ui.StyleVar[name],0);token.vars=token.vars+1 end
  end
  return token
end
function R.PopStyle(token)
  if token and token.vars>0 then ui.PopStyleVar(token.vars) end
  if token and token.colors>0 then ui.PopStyleColor(token.colors) end
end

local function drawEdit(instance,screen,node,box)
  local enabled=B.State(screen,node);local f=node.fields or {};point(box);ui.SetNextItemWidth(box.w)
  local token=R.PushStyle(instance);ui.BeginDisabled(not enabled)
  local value,changed
  local current=B.Text(screen,node)
  local capacity=number(f.MaxChars,4096);if capacity<=0 then capacity=4096 end;capacity=clamp(capacity,1,65535)
  local behavior=B.Input(screen,node)
  if behavior and behavior.capacity then capacity=behavior.capacity end
  if behavior and behavior.focusOnOpen then
    local window=state(instance,screen,{name="/visibility"})
    if window.shown==nil then window.shown=true;window.focusPending=true end
    if window.focusPending then ui.SetKeyboardFocusHere();window.focusPending=false end
  end
  if truth(f.Style_Multiline) or truth(f.Multiline) then
    value,changed=ui.InputTextMultiline("##edit:"..B.Id(node),current,capacity,box.w,box.h,
      truth(f.Style_ReadOnly) and flag("InputTextFlags","ReadOnly") or 0)
  else
    local flags=truth(f.Style_Password) and flag("InputTextFlags","Password") or 0
    if truth(f.Style_ReadOnly) then flags=flags|flag("InputTextFlags","ReadOnly") end
    if behavior and behavior.enter then flags=flags|flag("InputTextFlags","EnterReturnsTrue") end
    value,changed=ui.InputText("##edit:"..B.Id(node),current,capacity,flags)
  end
  if value~=current and enabled then B.Call("windows","SetText",screen,B.Id(node),value) end
  if behavior and behavior.enter and changed and enabled then B.Click(screen,node,"left") end
  ui.EndDisabled();R.PopStyle(token);tooltip(screen,node)
end
local function drawSlider(instance,screen,node,box)
  local enabled,_,value,count=B.State(screen,node)
  local f=node.fields or {};value=value or number(f.Value);count=count or number(f.NumTicks,101)
  local chosen=clamp(number(value),0,math.max(0,count-1))
  local _,hover,active=hit("##slider:"..B.Id(node),box,enabled)
  local vertical=truth(f.Vertical)
  local fraction=count>1 and chosen/(count-1) or 0
  sliderArt(instance,node,box,fraction,hover,active,enabled)
  if enabled and (ui.IsItemActive() or hover and ui.IsMouseClicked(ui.Mouse.Left)) then
    local x,y=ui.GetMousePos();local distance=vertical and box.h or box.w
    local position=vertical and y-box.y or x-box.x
    local nextValue=math.floor(clamp(position/math.max(1,distance),0,1)*math.max(0,count-1)+0.5)
    if nextValue~=chosen then B.Call("windows","SetSlider",screen,B.Id(node),nextValue) end
  end
  tooltip(screen,node)
end

local function drawCombo(instance,screen,node,box)
  local choices,picked=B.Call("windows","ComboInfo",screen,B.Id(node));choices=choices or {};picked=picked or -1
  local enabled=B.State(screen,node);point(box);ui.SetNextItemWidth(box.w)
  local token=R.PushStyle(instance);ui.BeginDisabled(not enabled)
  if ui.BeginCombo("##combo:"..B.Id(node),choices[picked+1] or B.Text(screen,node)) then
    for i,caption in ipairs(choices) do
      if ui.Selectable(tostring(caption).."##"..i,i-1==picked) and enabled then B.Call("windows","ComboSelect",screen,B.Id(node),i-1) end
    end
    ui.EndCombo()
  end
  ui.EndDisabled();R.PopStyle(token);tooltip(screen,node)
end
local function listRow(instance,screen,node,row,selected,multi,columns,box,height)
  local texts,r,g,b,texture,u0,v0,u1,v1=B.Call("windows","ListRow",screen,B.Id(node),row)
  if not texts then return end
  ui.TableNextRow()
  ui.TableNextColumn()
  local on=multi and multi[row] or row==selected
  ui.BeginDisabled(texts.disabled==true)
  local clicked=ui.Selectable("##row:"..row,on,flag("SelectableFlags","SpanAllColumns")|flag("SelectableFlags","AllowDoubleClick"),0,height)
  local hover=ui.IsItemHovered();local column=ui.TableGetHoveredColumn()
  local drag=state(instance,screen,{name=B.Id(node)..":row:"..row})
  if ui.IsItemClicked(ui.Mouse.Left) then drag.made=false end
  if not texts.disabled and B.Drag(screen,node,row) then drag.made=true end
  if clicked and not texts.disabled and not drag.made then
    local io=ui.GetIO();local modifiers=(io.shift and 1 or 0)|(io.ctrl and 2 or 0)
    B.Call("windows","ListClick",screen,B.Id(node),row,"left",column,modifiers)
    if ui.IsMouseDoubleClicked(ui.Mouse.Left) then B.Call("windows","ListClick",screen,B.Id(node),row,"double",column,modifiers) end
  end
  if hover and not texts.disabled and ui.IsItemClicked(ui.Mouse.Right) and (not ui.GetIO().alt or texts.altRight) then
    B.Call("windows","ListClick",screen,B.Id(node),row,"right",column);consumeRight(instance)
  end
  if hover and screen=="AuraWindow" and B.Id(node)=="AuraList" then ui.SetTooltip(tostring(texts[1] or "").."\nRemove with right click") end
  for c=1,columns do
    if c>1 then ui.TableNextColumn() end
    if texture and (texts.iconColumn or 0)==c-1 then ui.Image(texture,height,height,u0,v0,u1,v1);ui.SameLine() end
    if texts.comboColumn==c-1 then
      local child=B.Id(node)..":"..row;local choices,picked=B.Call("windows","ComboInfo",screen,child)
      if choices and ui.BeginCombo("##cellcombo:"..row,choices[(picked or -1)+1] or "") then
        for i,caption in ipairs(choices) do if ui.Selectable(tostring(caption),i-1==picked) and not texts.disabled then B.Call("windows","ComboSelect",screen,child,i-1) end end
        ui.EndCombo()
      end
    else
      local tint=texts.colors and texts.colors[c] or r and {r,g,b,1} or instance.palette.text
      ui.TextColored(tint[1],tint[2],tint[3],tint[4] or 1,tostring(texts[c] or ""))
    end
  end
  ui.EndDisabled()
end
local function drawList(instance,screen,node,box)
  local rows,columns,selected,labels,widths,multi=B.Call("windows","ListInfo",screen,B.Id(node))
  rows=number(rows);columns=math.max(1,number(columns,1));labels=labels or {};widths=widths or {}
  local token=R.PushStyle(instance);point(box);ui.BeginDisabled(B.State(screen,node)==false)
  local flags=flag("TableFlags","ScrollY")|flag("TableFlags","RowBg")|flag("TableFlags","Resizable")
  if ui.BeginTable("##list:"..B.Id(node),columns,flags,box.w,box.h) then
    for c=1,columns do
      local width=number(widths[c])*box.s
      ui.TableSetupColumn(tostring(labels[c] or ""),width>0 and flag("TableColumnFlags","WidthFixed") or 0,width)
    end
    local header,wantHeader
    for _,value in ipairs(labels)do if value~="" then wantHeader=true;break end end
    if wantHeader then if ui.TableHeadersRowClicked then header=ui.TableHeadersRowClicked() else ui.TableHeadersRow() end end
    if type(header)=="number" and header>=0 then B.Call("windows","ListHeaderClick",screen,B.Id(node),header) end
    local _,lineHeight=ui.CalcTextSize("Ag");local height=lineHeight+4*box.s
    -- Exact visible rows only; large merchants/markets never rebuild every row in Lua.
    local first=math.min(math.max(0,rows-1),math.max(0,math.floor(ui.GetScrollY()/math.max(1,height))-1))
    local last=math.min(rows-1,first+math.ceil(box.h/math.max(1,height))+3)
    if first>0 then ui.TableNextRow();ui.TableNextColumn();ui.Dummy(0,first*height) end
    for row=first,last do listRow(instance,screen,node,row,selected,multi,columns,box,height) end
    if last<rows-1 then ui.TableNextRow();ui.TableNextColumn();ui.Dummy(0,(rows-last-1)*height) end
    ui.EndTable()
  end
  ui.EndDisabled();R.PopStyle(token)
end
local function drawStml(instance,screen,node,box)
  -- This helper is loaded only while drawing, after the host theme finished initializing.
  if not instance.stml then local ok,lib=pcall(dofile,"lib/stml.lua");if ok then instance.stml=lib end end
  if not instance.stml or not instance.stml.DrawLines then
    emit(instance,"stml","The functional STML helper is unavailable; use the inherited presentation")
    error("STML helper unavailable",0)
  end
  local record=state(instance,screen,node);local raw=B.Text(screen,node)
  local changed=record.raw~=raw
  if record.raw~=raw then record.raw=raw;record.lines=instance.stml.Lines(raw,instance.palette.text);record.cum=nil;record.cumKey=nil end
  point(box)
  ui.PushFont(font(instance,node))
  local padding=ui.StyleVar and ui.StyleVar.WindowPadding
  if padding then ui.PushStyleVar(padding,0,0) end -- source rectangles already reserve their own text padding
  local visible=ui.BeginChild("##stml:"..B.Id(node),box.w,box.h,false,0)
  local ok,why=pcall(function()
    if visible then
      if changed then ui.SetScrollY(0) end
      local width,height=ui.GetContentRegionAvail()
      width,height=math.max(0,number(width)),math.max(0,number(height))
      local fw,fh=ui.CalcTextSize("Wg il")
      if record.stmlWidth~=width or record.stmlFontW~=fw or record.stmlFontH~=fh then
        record.stmlWidth,record.stmlFontW,record.stmlFontH=width,fw,fh
        record.stmlKey=(record.stmlKey or 0)+1 -- invalidate wrapped heights on width as well as font changes
      end
      if width>0 and height>0 then
        instance.stml.DrawLines(record,width,height,record.stmlKey,function(link)
          B.Call("windows","StmlLink",screen,B.Id(node),link[1],link[2])
        end)
      end
    end
  end)
  ui.EndChild()
  if padding then ui.PopStyleVar(1) end
  ui.PopFont()
  if not ok then error(why,0) end
end

local drawNode
local function placements(instance,screen,node,box)
  local all={};local s=box.s or 1;local f=node.fields or {}
  local resource=find(instance,"templates",f.Layout);local strategy=resource and (resource.fields or {}) or {}
  local horizontal=node.type=="HorizontalLayoutBox" or resource and resource.type=="LayoutHorizontal"
  local vertical=node.type=="VerticalLayoutBox" or resource and resource.type=="LayoutVertical"
  local tile=node.type=="TileLayoutBox"
  local linear=node.type=="HorizontalLayoutBox" or node.type=="VerticalLayoutBox"
  local strategyFlow=resource and (resource.type=="LayoutHorizontal" or resource.type=="LayoutVertical") and not linear
  local padding=number(strategy.Padding)*s
  local left,right=number(f.PaddingLeft)*s+padding,number(f.PaddingRight)*s+padding
  local top,bottom=number(f.PaddingTop)*s+padding,number(f.PaddingBottom)*s+padding
  local gap=number(f.Spacing,5)*s;local secondary=number(f.SecondarySpacing,5)*s
  local horizontalFirst=f.HorizontalFirst~=false
  local record=state(instance,screen,node);record.flowSizes=record.flowSizes or {}
  local flow={}
  local sizePiece=tile and truth(f.FirstPieceTemplate) and (node.children or {})[1]
  local first=sizePiece and {w=number((sizePiece.rect or {}).w)*s,h=number((sizePiece.rect or {}).h)*s}
  for _,child in ipairs(node.children or {}) do
    -- FirstPieceTemplate is also a real first gem/buff in many layouts. Only
    -- a model's explicit visibility rule may hide a nonsemantic prototype.
    if B.Shown(screen,child) then
      local at=R.Geometry(child,box)
      -- Model rectangles describe the built-in presentation, not the selected
      -- author's layout. Only an explicit dynamic adapter may borrow them.
      local x,y,w,h,relative,anchorRight,anchorBottom
      if B.UseHostRect and B.UseHostRect(screen,child)==true then
        x,y,w,h,relative,anchorRight,anchorBottom=B.Call("windows","ChildRect",screen,B.Id(child))
      end
      local live=x~=nil
      if live then
        at={x=box.x+number(x)*s,y=box.y+number(y)*s,w=number(w)*s,h=number(h)*s,s=s}
        if anchorRight~=nil then at.w=math.max(0,box.w-number(x)*s-number(anchorRight)*s) end
        if anchorBottom~=nil then at.h=math.max(0,box.h-number(y)*s-number(anchorBottom)*s) end
      end
      local item={node=child,rect=at,live=live}
      local cf=child.fields or {}
      if not live and (tile or horizontal and cf.UseInLayoutHorizontal~=false or vertical and cf.UseInLayoutVertical~=false) then
        -- A named layout strategy positions existing child windows. Their
        -- anchors may supply the entire size (a spell-gem tile has no Size).
        -- Concrete layout boxes instead start with their pieces' natural sizes.
        local natural=child.rect or {}
        if not strategyFlow then at.w=math.max(0,number(natural.w)*s);at.h=math.max(0,number(natural.h)*s) end
        local saved=record.flowSizes[B.Id(child)]
        if saved then if vertical then at.h=saved*s else at.w=saved*s end end
        flow[#flow+1]=item
      end
      all[#all+1]=item
    end
  end
  local x,y,rowHeight,columnWidth=left,top,0,0
  local availableW,availableH=math.max(0,box.w-left-right),math.max(0,box.h-top-bottom)
  if strategyFlow then
    local flexible,fixed={},0
    for _,item in ipairs(flow)do
      local at,cf=item.rect,item.node.fields or {}
      local natural=item.node.rect or {}
      local resizeMain=vertical and truth(strategy.ResizeVertical)or horizontal and truth(strategy.ResizeHorizontal)
      local stretchMain=truth(cf.AutoStretch)or vertical and truth(cf.AutoStretchVertical)or horizontal and truth(cf.AutoStretchHorizontal)
      local naturalMain=number(vertical and natural.h or horizontal and natural.w)
      local resolvedMain=vertical and at.h or at.w
      local fillMain=resizeMain and (stretchMain or naturalMain<=0 and resolvedMain>0)
      if fillMain then flexible[#flexible+1]=item else fixed=fixed+resolvedMain end
      -- Resize permission does not turn every fixed-size caption/icon into a
      -- full-width/height item; the child must request stretching or have none.
      if vertical and truth(strategy.ResizeHorizontal)
        and (truth(cf.AutoStretch)or truth(cf.AutoStretchHorizontal)or at.w<=0)then at.w=availableW
      elseif horizontal and truth(strategy.ResizeVertical)
        and (truth(cf.AutoStretch)or truth(cf.AutoStretchVertical)or at.h<=0)then at.h=availableH end
    end
    if #flexible>0 then
      local available=vertical and availableH or availableW
      local share=math.max(0,available-fixed-gap*math.max(0,#flow-1))/#flexible
      for _,item in ipairs(flexible)do
        local cf=item.node.fields or {}
        local minimum=number(vertical and cf.MinVSize or horizontal and cf.MinHSize)*s
        local maximum=number(vertical and cf.MaxVSize or horizontal and cf.MaxHSize)*s
        local value=math.max(minimum,share)
        if maximum>0 then value=math.min(value,maximum)end
        if vertical then item.rect.h=value else item.rect.w=value end
      end
    end
  end
  local function pastTileEdge(value,edge,n)
    -- Repeated additions and the independently scaled client edge can differ
    -- by a few double-precision ulps at an exact fit. This error bound stays
    -- far below a physical pixel and does not admit a genuinely wider piece.
    local epsilon=8*2.220446049250313e-16*(n+2)*math.max(1,math.abs(value),math.abs(edge))
    return value>edge+epsilon
  end
  for n,item in ipairs(flow) do
    local at=item.rect
    if tile and truth(f.FirstPieceTemplate) and first then at.w,at.h=first.w,first.h end
    if linear then
      if vertical then
        at.w=availableW
        if n==#flow and f.ResizeLast~=false then at.h=math.max(0,box.h-bottom-y) end
      else
        at.h=availableH
        if n==#flow and f.ResizeLast~=false then at.w=math.max(0,box.w-right-x) end
      end
    elseif tile then
      if horizontalFirst and pastTileEdge(x+at.w,box.w-right,n) and x>left then x=left;y=y+rowHeight+secondary;rowHeight=0
      elseif not horizontalFirst and pastTileEdge(y+at.h,box.h-bottom,n) and y>top then y=top;x=x+columnWidth+secondary;columnWidth=0 end
    end
    local px,py=x,y
    if tile and f.AnchorToLeft==false then px=box.w-right-(x-left)-at.w end
    if tile and f.AnchorToTop==false then py=box.h-bottom-(y-top)-at.h end
    at.x,at.y=box.x+px,box.y+py
    if vertical or tile and not horizontalFirst then y=y+at.h+gap else x=x+at.w+gap end
    rowHeight=math.max(rowHeight,at.h);columnWidth=math.max(columnWidth,at.w)
  end
  return all,linear and f.Style_Dividers~=false and flow or nil,vertical,record
end

function R.MeasureChildren(screen,plan,instance,box)
  box=box or {x=0,y=0,w=number((plan.rect or {}).w),h=number((plan.rect or {}).h),s=1}
  local right,bottom=box.x,box.y
  local function visit(node,parent,depth)
    if depth>64 then error("Source measurement exceeds the depth limit",0) end
    local entries=placements(instance,screen,node,parent)
    for _,entry in ipairs(entries) do
      local at=entry.rect
      right=math.max(right,at.x+at.w);bottom=math.max(bottom,at.y+at.h)
      if #(entry.node.children or {})>0 then visit(entry.node,at,depth+1) end
    end
  end
  visit(plan,box,0)
  return math.max(0,right-box.x),math.max(0,bottom-box.y)
end
local function dividers(instance,screen,node,box,flow,vertical,record)
  if not flow then return end
  local s=box.s or 1
  for n=1,#flow-1 do
    local before,after=flow[n],flow[n+1];local a,b=before.rect,after.rect
    local thickness=math.max(3*s,(vertical and b.y-a.y-a.h or b.x-a.x-a.w))
    local at=vertical and rect(a.x,a.y+a.h,a.w,thickness) or rect(a.x+a.w,a.y,thickness,a.h)
    local _,hover,active=hit("##divider:"..B.Id(node)..":"..n,at,true)
    filled(at,instance.palette.border)
    if active then
      local mx,my=ui.GetMousePos();local position=vertical and my or mx
      local drag=record.divider
      if not drag or drag.index~=n then
        drag={index=n,start=position,first=vertical and a.h or a.w,second=vertical and b.h or b.w};record.divider=drag
      end
      local af,bf=before.node.fields or {},after.node.fields or {}
      local minA=number(vertical and af.MinVSize or af.MinHSize,1)*s
      local minB=number(vertical and bf.MinVSize or bf.MinHSize,1)*s
      local delta=clamp(position-drag.start,minA-drag.first,math.max(minA-drag.first,drag.second-minB))
      record.flowSizes[B.Id(before.node)]=(drag.first+delta)/s
      record.flowSizes[B.Id(after.node)]=(drag.second-delta)/s
    elseif record.divider and record.divider.index==n and not ui.IsMouseDown(ui.Mouse.Left) then record.divider=nil end
  end
end
-- Private presenter traversal: use actual flow/anchors and ancestor clipping,
-- without painting, creating input items, or dispatching control actions.
function R.VisitChildren(screen,plan,instance,box,visit,opts)
  opts=opts or{}
  local count=0
  local function walk(parent,at,clip,depth)
    if depth>64 then return end
    local entries=placements(instance,screen,parent,at)
    for _,entry in ipairs(entries)do
      count=count+1;if count>8192 then return end
      local n,r=entry.node,entry.rect
      local x,y=math.max(clip.x,r.x),math.max(clip.y,r.y)
      local right,bottom=math.min(clip.x+clip.w,r.x+r.w),math.min(clip.y+clip.h,r.y+r.h)
      if r.w>0 and r.h>0 and right>x and bottom>y then
        local visible={x=x,y=y,w=right-x,h=bottom-y,s=r.s}
        visit(n,r,visible)
        if n.type=="TabBox"then
          local record=state(instance,screen,n)
          local picked=B.Call("windows","TabPage",screen,B.Id(n))
          if picked==nil then picked=record.page or 0 end
          local pages=n.children or{}
          local function pageChildren(page)
            local header=number((n.fields or{}).TabHeight,22)*r.s
            local body={x=r.x,y=r.y+header,w=r.w,h=math.max(0,r.h-header),s=r.s}
            local cy=math.max(visible.y,body.y)
            local bottomEdge=math.min(visible.y+visible.h,body.y+body.h)
            if bottomEdge>cy then walk(page,body,{x=visible.x,y=cy,w=visible.w,h=bottomEdge-cy,s=r.s},depth+1)end
          end
          if opts.allPages then
            for _,page in ipairs(pages)do pageChildren(page)end
          elseif pages[picked+1]then pageChildren(pages[picked+1])end
        else walk(n,r,visible,depth+1)end
      end
    end
  end
  walk(plan,box,box,0)
end
local function children(instance,screen,node,box)
  local ordered,over={},{}
  local entries,flow,vertical,record=placements(instance,screen,node,box)
  for _,entry in ipairs(entries) do
    local list=B.Call("windows","ChildUnder",screen,B.Id(entry.node)) and ordered or over
    list[#list+1]=entry
  end
  for _,entry in ipairs(over)do ordered[#ordered+1]=entry end
  -- Child window backgrounds belong behind sibling controls, even when the
  -- source lists an anchored layout screen after its target gauges/labels.
  -- Preserve the authored ordering of all input items and child contents.
  for _,entry in ipairs(ordered)do
    local child,at=entry.node,entry.rect
    if (child.type=="Screen"or child.type=="Page")and at.w>0 and at.h>0 and B.Shown(screen,child)then
      ui.PushClipRect(at.x,at.y,at.x+at.w,at.y+at.h,true)
      local ok,painted=pcall(R.PaintControl,screen,child,at,instance)
      ui.PopClipRect()
      if not ok then error(painted,0)end
      if painted then at.paintedChromeNode=child end
    end
  end
  for _,entry in ipairs(ordered)do drawNode(instance,screen,entry.node,entry.rect) end
  dividers(instance,screen,node,box,flow,vertical,record)
end
dynamicArt=function(instance,screen,node,box,part,supplied)
  local value,u0,v0,u1,v1
  if supplied then value,u0,v0,u1,v1=table.unpack(supplied,1,5)
  else value,u0,v0,u1,v1=B.Call("windows","ChildArt",screen,B.Id(node),part) end
  if value==false then return true end -- the model explicitly draws nothing
  if value==nil then return false end
  if part=="decal" then box=decalRect(node,box) end
  if box.w<=0 or box.h<=0 then return true end
  if type(value)=="string" then R.Animation(instance,value,box,B.Color(screen,node,part));return true end
  ui.DrawImage(value,box.x,box.y,box.x+box.w,box.y+box.h,u0 or 0,v0 or 0,u1 or 1,v1 or 1,1,1,1,1)
  return true
end
local function drawTabs(instance,screen,node,box)
  local record=state(instance,screen,node)
  local hostPage=B.Call("windows","TabPage",screen,B.Id(node))
  local picked=hostPage~=nil and hostPage or record.page or 0
  local pages=node.children or {};local f=node.fields or {};local header=number(f.TabHeight,22)*box.s
  local x=box.x
  for n,page in ipairs(pages) do
    local caption=(page.text and page.text~="") and page.text or (page.fields or {}).TabText or page.item or tostring(n)
    ui.PushFont(font(instance,page));local width=ui.CalcTextSize(caption);ui.PopFont();width=math.max(32*box.s,width+20*box.s)
    local tab=rect(x,box.y,math.min(width,box.x+box.w-x),header);tab.s=box.s
    if tab.w>0 then
      local clicked,hover,pressed=hit("##tab:"..B.Id(node)..":"..n,tab,true)
      buttonArt(instance,node,tab,hover,pressed,n-1==picked,true);text(instance,page,tab,caption)
      if clicked then
        B.Call("windows","SetTabPage",screen,B.Id(node),n-1)
        record.page=n-1;picked=n-1
      end
    end
    x=x+width
  end
  local page=pages[picked+1]
  if page then
    local body={x=box.x,y=box.y+header,w=box.w,h=math.max(0,box.h-header),s=box.s}
    -- Page Location/Size are already relative to the tab's client in the authored plan.
    R.PaintControl(screen,page,body,instance)
    children(instance,screen,page,body)
  end
end

local function controlEvents(instance,screen,node,box)
  local events=B.Events(screen,node)
  if not events then return end
  local enabled,_,_,_,action=B.State(screen,node)
  local clicked=hit("##value:"..B.Id(node),box,enabled or action)
  if events.phases then
    phases(instance,screen,node,box,function(phase,outside)
      if phase:sub(1,4)=="left" and not enabled then return false end
      return B.Click(screen,node,phase,outside)
    end)
  else
    if clicked and enabled and events.left then B.Click(screen,node,"left") end
    if (enabled or action) and events.right and ui.IsItemClicked(ui.Mouse.Right) then
      B.Click(screen,node,"right");consumeRight(instance)
    end
  end
  tooltip(screen,node)
end

drawNode=function(instance,screen,node,box)
  if box.w<=0 or box.h<=0 or not B.Shown(screen,node) then return end
  local x0,y0,x1,y1=box.x,box.y,box.x+box.w,box.y+box.h
  if node.type=="Gauge" then
    -- A source gauge can deliberately place its caption outside its track.
    -- Retain the enclosing client clip while allowing the authored text offset.
    local fields=node.fields or {};local s=box.s or 1
    local dx,dy=number(fields.TextOffsetX)*s,number(fields.TextOffsetY)*s
    x0,y0=math.min(x0,x0+dx),math.min(y0,y0+dy)
    x1,y1=math.max(x1,x1+dx),math.max(y1,y1+dy)
  end
  ui.PushClipRect(x0,y0,x1,y1,true)
  local ok,why=pcall(function()
  if B.DrawControl and B.DrawControl(screen,node,box,instance,R)==true then return end
  local kind=node.type
  if kind=="Label" or kind=="StaticText" or kind=="StaticHeader" then
    local events=B.Events(screen,node)
    local enabled=true
    if events then
      enabled=B.State(screen,node)
      local clicked=hit("##label:"..B.Id(node),box,enabled)
      if clicked and enabled and events.left then B.Click(screen,node,"left") end
      if enabled and events.right and ui.IsItemClicked(ui.Mouse.Right) then B.Click(screen,node,"right");consumeRight(instance) end
      tooltip(screen,node)
    end
    local caption,tint=B.Text(screen,node);text(instance,node,box,caption,not enabled and instance.palette.disabled or B.Color(screen,node) or tint or color((node.colors or {}).TextColor,instance.palette.text))
  elseif kind=="Button" then drawButton(instance,screen,node,box)
  elseif kind=="Gauge" then drawGauge(instance,screen,node,box);controlEvents(instance,screen,node,box)
  elseif kind=="InvSlot" then drawSlot(instance,screen,node,box)
  elseif kind=="SpellGem" then drawGem(instance,screen,node,box)
  elseif kind=="HotButton" then drawHot(instance,screen,node,box)
  elseif kind=="Editbox" then drawEdit(instance,screen,node,box)
  elseif kind=="Slider" then drawSlider(instance,screen,node,box)
  elseif kind=="Combobox" then drawCombo(instance,screen,node,box)
  elseif kind=="Listbox" then drawList(instance,screen,node,box)
  elseif kind=="STMLbox" then drawStml(instance,screen,node,box)
  elseif kind=="TabBox" then drawTabs(instance,screen,node,box)
  elseif kind=="StaticAnimation" or kind=="StaticTintedBlendAnimation" then
    if not dynamicArt(instance,screen,node,box,"decal") and not dynamicArt(instance,screen,node,box,"background") then
      local a=node.art or {};R.Animation(instance,(a.animation and a.animation~="") and a.animation or a.background,box,B.Color(screen,node,"decal") or color((node.colors or {}).Tint))
    end
    controlEvents(instance,screen,node,box)
  elseif kind=="StaticFrame" then
    local a=node.art or {};R.Frame(instance,a.template~="" and a.template or a.drawTemplate,box,WHITE,box.s)
  elseif kind=="Screen" or kind=="Page" then
    R.PaintControl(screen,node,box,instance)
    children(instance,screen,node,box)
  else children(instance,screen,node,box) end
  if B.AfterControl then B.AfterControl(screen,node,box,instance,R) end
  end)
  ui.PopClipRect()
  if not ok then error(why,0) end
end

-- Specialized presenters retain the same geometry and artwork while owning a
-- control's full domain interaction (chat, buffs, inventory drag/drop, etc.).
-- This helper deliberately creates no input item and dispatches no action.
function R.PaintControl(screen,node,box,instance,options)
  options=options or {}
  local kind=node.type
  if kind=="Gauge" then drawGauge(instance,screen,node,box,options)
  elseif kind=="Label" or kind=="StaticText" or kind=="StaticHeader" then
    local caption,tint=B.Text(screen,node)
    text(instance,node,box,options.caption~=nil and options.caption or caption,
      options.tint or B.Color(screen,node) or tint or color((node.colors or {}).TextColor,instance.palette.text))
  elseif kind=="Button" or kind=="InvSlot" or kind=="HotButton" or kind=="SpellGem" then
    local enabled,checked=B.State(screen,node)
    if options.enabled~=nil then enabled=options.enabled end
    if options.checked~=nil then checked=options.checked end
    buttonArt(instance,node,box,options.hovered==true,options.active==true,checked,enabled,options.tint,
      {decal=options.skipDecal==true})
    if options.caption~=nil then text(instance,node,box,options.caption,options.tint) end
  elseif kind=="StaticAnimation" or kind=="StaticTintedBlendAnimation" then
    if not options.skipDecal then
      if dynamicArt(instance,screen,node,box,"decal") or dynamicArt(instance,screen,node,box,"background") then return true end
      local art=node.art or {}
      R.Animation(instance,(art.animation and art.animation~="") and art.animation or art.background,box,
        options.tint or B.Color(screen,node,"decal") or color((node.colors or {}).Tint))
    end
  elseif kind=="StaticFrame" then
    local art=node.art or {}
    R.Frame(instance,art.template~="" and art.template or art.drawTemplate,box,options.tint or WHITE,box.s)
  elseif kind=="Screen"or kind=="Page"then
    if box.paintedChromeNode==node then return true end
    local art,fields=node.art or{},node.fields or{}
    local reference=art.drawTemplate
    if not reference or reference==""then reference=fields.DrawTemplate end
    -- A clipping/layout screen must never acquire the selected outer frame by
    -- fallback. Only its own authored draw template can decorate this region.
    if not reference or reference==""or not template(instance,reference)then return false end
    local bordered,titled,transparent=truth(fields.Style_Border),truth(fields.Style_Titlebar),truth(fields.Style_Transparent)
    if transparent and not bordered and not titled then return false end
    local own={};for key,value in pairs(node)do own[key]=value end
    own.fields=setmetatable({Style_Border=bordered,Style_Titlebar=titled,Style_Transparent=transparent},{__index=fields})
    own.art={drawTemplate=reference}
    R.WindowChrome(own,node.text,box,instance,{close=false,alpha=options.alpha})
  else return false end
  return true
end

function R.DrawChildren(screen,plan,instance,box)
  if plan.type=="Page"then R.PaintControl(screen,plan,box,instance)end
  return children(instance,screen,plan,box)
end

function R.CanDraw(plan,instance,screen)
  if type(plan)~="table" or type(plan.children)~="table" then return false,"No compiled control graph" end
  local function check(node,depth)
    if depth>64 then return false,"Control graph exceeds the supported depth" end
    if not supported[node.type] then return false,"Control adapter required: "..tostring(node.type).."/"..B.Id(node) end
    local fields=node.fields or {}
    if node.type=="TileLayoutBox" and truth(fields.SnapToChildren) then
      return false,"Parent-size adapter required for SnapToChildren: "..B.Id(node)
    end
    if fields.Layout and fields.Layout~="" then
      local strategy=find(instance,"templates",fields.Layout)
      if not strategy then return false,"Missing authored layout strategy: "..tostring(fields.Layout) end
      local config=strategy.fields or {}
      if truth(config.ResizeHorizontal) or truth(config.ResizeVertical) then
        return false,"Parent-size adapter required for layout strategy: "..tostring(fields.Layout)
      end
    end
    for _,need in ipairs(B.Requirements(node.type)) do
      if not B.Function(need[1],need[2]) then return false,"Host API unavailable: "..need[1].."."..need[2] end
    end
    if node.type=="STMLbox" and instance and not instance.stml then
      local ok,lib=pcall(dofile,"lib/stml.lua")
      if not ok or type(lib)~="table" or not lib.DrawLines then return false,"Functional STML helper unavailable" end
      instance.stml=lib
    end
    for _,child in ipairs(node.children or {}) do local ok,why=check(child,depth+1);if not ok then return false,why end end
    return true
  end
  local cached=instance and instance.preflight[plan]
  local ok,why
  if cached then ok,why=cached[1],cached[2]
  else ok,why=check(plan,0);if instance then instance.preflight[plan]={ok,why} end end
  if ok and screen and not B.Model(screen) then ok=false;why="No host model for "..screen end
  if ok then ok,why=B.Compatible(screen or plan.name or plan.item,plan,instance) end
  if not ok and instance then emit(instance,"adapter:"..tostring(screen or plan.item),why.."; using the themed functional presentation") end
  return ok,why
end

function R.Draw(screen,plan,instance,target,adapter)
  local ok,why
  if adapter~=nil then
    if type(adapter)~="table" or type(adapter.CanDraw)~="function" then
      return false,"An audited source presenter is required"
    end
    ok,why=adapter.CanDraw(screen,plan,instance)
  else ok,why=R.CanDraw(plan,instance,screen) end
  if not ok then return false,why end
  local owned=false
  if not target then
    local shown,x,y,w,h,sized,place=B.Call("windows","Replace",screen,true)
    if not shown then return true end
    local design=plan.rect or {}
    ui.SetNextWindowPos(x or number(design.x),y or number(design.y),place and flag("Cond","Always") or flag("Cond","FirstUseEver"))
    ui.SetNextWindowSize(sized and w or math.max(32,number(design.w)),sized and h or math.max(32,number(design.h)),place and flag("Cond","Always") or flag("Cond","FirstUseEver"))
    local visible,open=ui.Begin((B.Call("windows","Title",screen) or plan.text or screen).."###pack:"..screen,true,0)
    owned=true
    if not open then B.Call("windows","Show",screen,false) end
    if not visible then ui.End();return true end
    local px,py=ui.GetCursorScreenPos();local pw,ph=ui.GetContentRegionAvail()
    target={x=px,y=py,w=pw,h=ph,s=(ui.GetIO().uiScale or 1)}
  end
  target.s=target.s or target.scale or 1
  local token=R.PushStyle(instance)
  ui.PushClipRect(target.x,target.y,target.x+target.w,target.y+target.h,true)
  local success,drawError=pcall(children,instance,screen,plan,target)
  ui.PopClipRect();R.PopStyle(token)
  if owned then
    local x,y=ui.GetWindowPos();local w,h=ui.GetWindowSize();B.Call("windows","Placed",screen,x,y,w,h,true)
    ui.End()
  end
  if not success then error(drawError,0) end -- never invoke a second body after partial host actions
  return true
end

-- Decoration runs AFTER an inherited widget. It must never register an item, move the
-- cursor, inspect input or dispatch an action: the original widget owns all interaction.
function R.DecorateWidget(instance,kind,box,opts)
  opts=opts or {};box.s=box.s or box.scale or 1
  local enabled=opts.enabled~=false
  local f=instance.style.fonts or {}
  local caption=tostring(opts.caption or ""):gsub("##.*$","")
  local node={name=opts.id or kind,type="Button",font=f.button or f.text or 3,fields={Style_HCenter=true,Style_VCenter=true}}
  local tint=opts.danger and (instance.palette.danger or instance.palette.hp) or nil
  if kind=="Button" or kind=="SmallButton" then
    buttonArt(instance,node,box,opts.hovered or opts.primary,opts.active,opts.checked,enabled,tint)
    if opts.primary or opts.checked then border(box,instance.palette.text) end
    text(instance,node,box,caption,enabled and instance.palette.text or instance.palette.disabled)
  elseif kind=="Checkbox" then
    node.art={drawTemplate=selector(instance,"checkbox")}
    ui.PushFont(font(instance,node));local _,height=ui.CalcTextSize("Ag");ui.PopFont()
    local size=math.min(box.h,height+4*box.s)
    local marker={x=box.x,y=box.y+(box.h-size)/2,w=size,h=size,s=box.s}
    buttonArt(instance,node,marker,opts.hovered,opts.active,opts.checked,enabled,tint)
    if opts.checked and not nodeTemplate(instance,node,"Button") then
      filled(rect(marker.x+size*0.25,marker.y+size*0.25,size*0.5,size*0.5),enabled and instance.palette.text or instance.palette.disabled)
    end
    node.fields.Style_HCenter=false
    text(instance,node,rect(box.x+size+5*box.s,box.y,math.max(0,box.w-size-5*box.s),box.h),caption,enabled and instance.palette.text or instance.palette.disabled)
  elseif kind=="SliderInt" or kind=="SliderFloat" or kind=="Slider" then
    node.type="Slider";node.fields.Vertical=opts.vertical
    sliderArt(instance,node,box,opts.fraction,opts.hovered,opts.active,enabled)
    text(instance,node,box,opts.valueText or caption,enabled and instance.palette.text or instance.palette.disabled)
  else return false end
  return true
end

function R.StyleTheme(T,instance)
  if T._packStyled==instance then return T end
  T._packStyled=instance
  instance.theme=T
  T.Panel=function(x0,y0,x1,y1,s,opts)
    opts=opts or {};R.Chrome(instance,{x=x0,y=y0,w=x1-x0,h=y1-y0,s=s},opts)
  end
  T.Button=function(id,x0,y0,x1,y1,s,caption,opts)
    opts=opts or {};local box={x=x0,y=y0,w=x1-x0,h=y1-y0,s=s}
    local clicked,hover,pressed
    if T.Hit then
      ui.BeginDisabled(opts.enabled==false);clicked=T.Hit(id,x0,y0,x1,y1)
      hover,pressed=ui.IsItemHovered(),ui.IsItemActive();ui.EndDisabled()
    else clicked,hover,pressed=hit(id,box,opts.enabled~=false) end
    local node={name=id,type="Button",font=(instance.style.fonts or {}).button or 3,fields={Style_HCenter=true,Style_VCenter=true}}
    local tint=opts.danger and (instance.palette.danger or instance.palette.hp) or nil
    buttonArt(instance,node,box,hover or opts.primary,pressed,opts.checked,opts.enabled~=false,tint)
    if opts.primary or opts.checked then border(box,instance.palette.text) end
    text(instance,node,box,caption,opts.enabled==false and instance.palette.disabled or instance.palette.text)
    if hover and opts.tooltip then ui.SetTooltip(opts.tooltip) end
    return clicked and opts.enabled~=false
  end
  T.Bar=function(key,x0,y0,x1,y1,s,fraction,tint,opts)
    opts=opts or {};local box={x=x0,y=y0,w=x1-x0,h=y1-y0,s=s}
    gaugeArt(instance,{name=key,type="Gauge",fields={}},box,fraction,tint,opts.alpha)
    local f=opts.font or (instance.style.fonts or {}).small or 2
    local c=color(opts.textColor,instance.palette.text);local ink={c[1],c[2],c[3],c[4]*number(opts.alpha,1)}
    if opts.center then text(instance,{font=f,fields={Style_HCenter=true,Style_VCenter=true}},box,opts.center,ink) end
    if opts.left or opts.text then text(instance,{font=f,fields={Style_VCenter=true}},box,opts.left or opts.text,ink) end
    if opts.right then text(instance,{font=f,fields={Style_RightJustify=true,Style_VCenter=true}},box,opts.right,ink) end
  end
  T.Icon=function(x,y,size,s,texture,u0,v0,u1,v1,ring,opts)
    opts=opts or {};local box={x=x,y=y,w=size,h=size,s=s}
    local alpha=number(opts.alpha,1);local well=number(opts.wellAlpha,1)
    -- Domain helpers still own inventory gestures, marks and rich tooltips.
    -- A scoped source node supplies the particular slot's artwork, rather than
    -- flattening every authored equipment cell to the theme's generic well.
    local source=instance.sourceSlotNode
    local chosen=source and (source.art or {}).background or instance.style.slot
    local animation=type(chosen)=="table" and (chosen.animation or chosen.background) or chosen
    local sourceButton=source and nodeTemplate(instance,source,"Button")
    if not animation or animation=="" then animation=sourceButton and sourceButton.Normal end
    if not animation then
      for _,candidate in ipairs({"A_InvSlot","A_RecessedBox"}) do
        if find(instance,"animations",candidate) or find(instance,"images",candidate) then animation=candidate;break end
      end
    end
    local painted=R.Animation(instance,animation,box,{1,1,1,well})
    if not painted then
      local button=nodeTemplate(instance,{type="Button",fields={}},"Button")
      painted=button and R.Animation(instance,button.Normal,box,{1,1,1,well})
    end
    if not painted then
      local background=instance.palette.background
      filled(box,{background[1],background[2],background[3],background[4]*well})
    end
    if source and not texture then
      R.Animation(instance,sourceButton and sourceButton.NormalDecal,box,{1,1,1,well})
    end
    if texture then
      local p=1.5*s
      if type(texture)=="string" then R.Animation(instance,texture,rect(x+p,y+p,math.max(0,size-2*p),math.max(0,size-2*p)),{1,1,1,alpha})
      else ui.DrawImage(texture,x+p,y+p,x+size-p,y+size-p,u0 or 0,v0 or 0,u1 or 1,v1 or 1,1,1,1,alpha) end
    end
    local ink=color(ring,instance.palette.border)
    if ring or not source or not painted then
      ui.DrawRect(x,y,x+size,y+size,ink[1],ink[2],ink[3],ink[4]*alpha,0,(ring and 1.5 or 1)*s)
    end
    return texture~=nil
  end
  T.HoverFx=function(x0,y0,x1,y1,s)
    if ui.IsItemActive() then ui.DrawRectFilled(x0,y0,x1,y1,0,0,0,0.25,0)
    elseif ui.IsItemHovered() then
      local ink=instance.palette.accent or instance.palette.text
      ui.DrawRectFilled(x0,y0,x1,y1,ink[1],ink[2],ink[3],0.08,0)
      ui.DrawRect(x0,y0,x1,y1,ink[1],ink[2],ink[3],0.9,0,1.5*s)
    end
  end
  return T
end

function R.Wrap(title,original,profile,screen)
  local instance=R.New(profile)
  return function(...)
    local plan=screen and R.Resolve(screen,instance)
    if plan and R.CanDraw(plan,instance,screen) then return R.Draw(screen,plan,instance) end
    local token=R.PushStyle(instance)
    local result=table.pack(pcall(original,...));R.PopStyle(token)
    if not result[1] then error(result[2],0) end
    return unpack(result,2,result.n)
  end
end

R.Bindings=B
return R
