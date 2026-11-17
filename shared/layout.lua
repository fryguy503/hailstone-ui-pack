-- Only unsaved default positions come from source plans. hud.Window applies
-- the player's saved hud.pos before asking this solver for a starting place.
local context=dofile("lib/pack_context.lua")
local base=hs.UI.interfaces.LoadBase("lib/layout.lua")
if base._sourceContext==context then return base end
local solve=base.Solve
base._sourceContext=context
local hud={PlayerWindow=1,TargetWindow=2,GroupWindow=3,ExtendedTargetWnd=4,CastSpellWnd=5,
  BuffWindow=20,ShortDurationBuffWindow=21,CompassWindow=22,TargetOfTargetWindow=23,BreathWindow=24}
local function priority(screen)
  if hud[screen] then return hud[screen] end
  if screen=="HotButtonWnd" then return 6 end
  local hot=tonumber(screen:match("^HotButtonWnd(%d+)$"));if hot then return 6+hot/20 end
  local chat=tonumber(screen:match("^Chat(%d+)$"));if chat then return 30+chat/100 end
end
local function overlap(a,b)
  return math.max(0,math.min(a.x+a.w,b.x+b.w)-math.max(a.x,b.x))
    *math.max(0,math.min(a.y+a.h,b.y+b.h)-math.max(a.y,b.y))
end
base.Solve=function(W,H,s,frames)
  local result=solve(W,H,s,frames)
  local pending,placed={},{}
  for screen,frame in pairs(frames) do
    local plan=context.renderer.Resolve(screen,context.instance)
    local source=plan and plan.rect
    if source then
      local x,y=(tonumber(source.x) or 0)*s,(tonumber(source.y) or 0)*s
      local offset=tonumber(screen:match("^Chat(%d+)$") or screen:match("^ItemDisplayWindow#(%d+)$"))
      if offset and offset>1 then x=x+(offset-1)*20*s;y=y+(offset-1)*20*s end
      local at={x=math.max(0,math.min(x,math.max(0,W-frame.w))),
        y=math.max(0,math.min(y,math.max(0,H-frame.h))),w=frame.w,h=frame.h}
      result[screen]=at
      if priority(screen) then
        local saved=ui.GetSetting("hud.pos."..screen)
        local sx,sy=(saved or ""):match("^(-?[%d.]+),(-?[%d.]+)$")
        if sx and sy then
          placed[#placed+1]={x=math.max(0,math.min(tonumber(sx),math.max(0,W-frame.w))),
            y=math.max(0,math.min(tonumber(sy),math.max(0,H-frame.h))),w=frame.w,h=frame.h}
        else pending[#pending+1]={screen=screen,rect=at} end
      end
    end
  end
  -- Source coordinates are a preference, not permission to cover another HUD
  -- frame. Dialogs and transient overlays keep their own layering. Saved moves
  -- remain authoritative; only unsaved defaults are packed around them.
  for screen,frame in pairs(frames) do
    if not priority(screen) and (screen=="Minimap" or screen=="Menu") then
      local at=result[screen]
      if at then placed[#placed+1]={x=at.x,y=at.y,w=frame.w,h=frame.h} end
    end
  end
  table.sort(pending,function(a,b)
    local pa,pb=priority(a.screen),priority(b.screen)
    if pa~=pb then return pa<pb end;return a.screen<b.screen
  end)
  local gap=6*s
  for _,entry in ipairs(pending) do
    local at=entry.rect
    local xs,ys={at.x,0,math.max(0,W-at.w)},{at.y,0,math.max(0,H-at.h)}
    for _,other in ipairs(placed) do
      xs[#xs+1]=math.max(0,math.min(other.x+other.w+gap,math.max(0,W-at.w)))
      xs[#xs+1]=math.max(0,math.min(other.x-at.w-gap,math.max(0,W-at.w)))
      ys[#ys+1]=math.max(0,math.min(other.y+other.h+gap,math.max(0,H-at.h)))
      ys[#ys+1]=math.max(0,math.min(other.y-at.h-gap,math.max(0,H-at.h)))
    end
    local best,area,distance=nil,math.huge,math.huge
    for _,x in ipairs(xs)do for _,y in ipairs(ys)do
      local candidate={x=x,y=y,w=at.w,h=at.h}
      local covered=0;for _,other in ipairs(placed)do covered=covered+overlap(candidate,other)end
      local d=(x-at.x)^2+(y-at.y)^2
      if covered<area or covered==area and d<distance then best,area,distance=candidate,covered,d end
    end end
    result[entry.screen]=best;placed[#placed+1]=best
  end
  return result
end
return base
