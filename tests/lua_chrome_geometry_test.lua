-- Synthetic frame geometry only: no game layouts, texture bytes, or inputs.
local realDofile=dofile
local cases,assertions=0,0
local draws,clips,texts,fonts,fills,borders,clipHistory
local function check(value,why) assertions=assertions+1;assert(value,why or "check failed") end
local function equal(a,b,why)check(a==b,(why or "values differ")..": "..tostring(a).." / "..tostring(b))end
local function reset()draws={};clips=0;texts={};fonts=0;fills=0;borders=0;clipHistory={}end
reset()
ui={
 GetFrameCount=function()return 1 end,GetTime=function()return 0 end,
 DrawImage=function(texture,x0,y0,x1,y1,...)
  draws[#draws+1]={name=texture:sub(5),x=x0,y=y0,w=x1-x0,h=y1-y0,uv=table.pack(...)}
 end,
 PushClipRect=function(...)clips=clips+1;clipHistory[#clipHistory+1]=table.pack(...)end,
 PopClipRect=function()clips=clips-1;check(clips>=0,"clip underflow")end,
 DrawRectFilled=function()fills=fills+1 end,DrawRect=function()borders=borders+1 end,
 PushFont=function()fonts=fonts+1 end,PopFont=function()fonts=fonts-1;check(fonts>=0)end,
 CalcTextSize=function(text)return #text*7,12 end,
 DrawText=function(...)texts[#texts+1]=table.pack(...)end,
}
setmetatable(ui,{__index=function(_,key)error("Chrome attempted a non-drawing UI operation: "..key)end})
dofile=function(path)
 if path=="lib/pack_bindings.lua" then return {Call=function(module,method,path)
  equal(module,"assets");equal(method,"Image");return "tex:"..path,512,512
 end}end
 error("Unexpected dependency "..path)
end
local R=realDofile("shared/renderer.lua")
dofile=realDofile
local function fixture()
 local index={images={},animations={},templates={}}
 local I={index=index,folded={},textures={},messages={},style={frame={template="Window"},fonts={title=3}},
  palette={text={1,1,1,1},background={0,0,0,1},border={1,1,1,1}}}
 local function art(name,w,h)
  index.images[name]={path=name,width=512,height=512}
  index.animations[name]={frames={{image=name,rect={x=0,y=0,w=w,h=h}}}}
  return name
 end
 local border={TopLeft=art("TL",5,3),Top=art("T",4,3),TopRight=art("TR",40,3),
  LeftTop=art("LT",5,36),Left=art("L",5,2),LeftBottom=art("LB",5,12),
  RightTop=art("RT",5,36),Right=art("R",5,2),RightBottom=art("RB",5,2),
  BottomLeft=art("BL",18,5),Bottom=art("B",4,5),BottomRight=art("BR",26,5)}
 index.templates.Border={fields=border}
 index.templates.Title={fields={Left=art("titleL",12,18),Middle=art("titleM",4,18),Right=art("titleR",30,18)}}
 index.templates.Window={fields={Border="Border",Titlebar="Title",Background=art("background",16,16),
  CloseBox={Normal=art("close",10,10),Flyby=art("closeH",10,10),Pressed=art("closeP",10,10),PressedFlyby=art("closePH",10,10)}}}
 return I,index,border,art
end
local box={x=100,y=200,w=200,h=150,s=1}
local function drawn(name)
 for _,d in ipairs(draws)do if d.name==name then return d end end
 error("Missing draw "..name)
end
local function noDraw(name)
 for _,d in ipairs(draws)do check(d.name~=name,"Unexpected draw "..name)end
end
local function bounds(name,x,y,w,h)
 local d=drawn(name);equal(d.x,x,name.." x");equal(d.y,y,name.." y");equal(d.w,w,name.." w");equal(d.h,h,name.." h")
end
local function run(name,fn)
 reset();local ok,why=pcall(fn);if not ok then error(name..": "..why,0)end
 equal(clips,0,"balanced clips");equal(fonts,0,"balanced fonts");cases=cases+1
end
run("independent ornamental corners and native-width side caps",function()
 local I=fixture();check(R.Frame(I,"Border",box));equal(#draws,12)
 bounds("TL",100,200,5,3);bounds("TR",260,200,40,3)
 bounds("BL",100,345,18,5);bounds("BR",274,345,26,5)
 bounds("LT",100,203,5,36);bounds("LB",100,333,5,12)
 bounds("RT",295,203,5,36);bounds("RB",295,343,5,2)
 bounds("L",100,239,5,94);bounds("R",295,239,5,104)
 bounds("T",105,200,155,3);bounds("B",118,345,156,5)
end)
run("scale changes physical dimensions once",function()
 local I=fixture();R.Frame(I,"Border",{x=0,y=0,w=400,h=300},nil,2)
 bounds("TL",0,0,10,6);bounds("TR",320,0,80,6);bounds("RB",390,286,10,4)
 bounds("L",0,78,10,188)
end)
run("tiny windows clip natural corners instead of widening or squashing them",function()
 local I=fixture();R.Frame(I,"Border",{x=10,y=20,w=8,h=6})
 bounds("TR",-22,20,40,3);bounds("BL",10,21,18,5)
 equal(#clipHistory,1);equal(clipHistory[1][1],10);equal(clipHistory[1][3],18)
 equal(clipHistory[1][5],true,"never escape parent clip")
 noDraw("L");noDraw("R");noDraw("T");noDraw("B")
end)
run("horizontal title caps retain their own width and common title height",function()
 local I=fixture();R.Frame(I,"Title",{x=1,y=2,w=100,h=18})
 bounds("titleL",1,2,12,18);bounds("titleM",13,2,58,18);bounds("titleR",71,2,30,18)
end)
run("source title and border flags control client insets",function()
 local I=fixture();local p={art={drawTemplate="Window"},fields={Style_Titlebar=true,Style_Border=true,Style_Closebox=true}}
 local m=R.ChromeInsets(p,I,2)
 equal(m.left,10);equal(m.right,10);equal(m.top,36);equal(m.bottom,10);equal(m.titleHeight,36)
 equal(m.close.width,20);equal(m.close.height,20);equal(m.close.right,20);equal(m.close.top,8)
 p.fields.Style_Titlebar=false;m=R.ChromeInsets(p,I,1);equal(m.top,3);equal(m.titleHeight,0);equal(m.close,nil)
 p.fields.Style_Border=false;m=R.ChromeInsets(p,I,1);equal(m.left,0);equal(m.right,0);equal(m.top,0);equal(m.bottom,0)
end)
run("one complete source frame paints before reserved title content",function()
 local I=fixture();local p={art={drawTemplate="Window"},fields={Style_Titlebar=true,Style_Border=true,Style_Closebox=true}}
 local m=R.WindowChrome(p,"A source title",box,I,{closeHovered=true,closePressed=true})
 equal(m.top,18);equal(#texts,1);drawn("closePH");noDraw("close");equal(fills,1)
 bounds("titleL",100,200,12,18);bounds("closePH",280,204,10,10)
 equal(texts[1][2],203);equal(clipHistory[#clipHistory][1],112);equal(clipHistory[#clipHistory][3],270)
end)
run("NoTitle source never receives synthetic caption close or title pixels",function()
 local I=fixture();local p={art={drawTemplate="Window"},fields={Style_Titlebar=false,Style_Closebox=true}}
 R.WindowChrome(p,"Do not draw this caption",box,I)
 equal(#texts,0);noDraw("titleL");noDraw("titleM");noDraw("titleR");noDraw("close")
end)
run("scaled caption keeps its selected font instead of shrinking to strip pixels",function()
 local I=fixture();local p={fields={Style_Titlebar=true}}
 local calc=ui.CalcTextSize;ui.CalcTextSize=function(text)return #text*3.5,6 end
 R.WindowChrome(p,"Scaled",{x=0,y=0,w=100,h=70,s=0.5},I)
 ui.CalcTextSize=calc
 equal(texts[1][2],1.5);equal(texts[1][8],nil)
end)
run("short ornamental title strips reserve readable source font without stretching art",function()
 local I,index,_,art=fixture()
 index.templates.Title.fields={Left=art("shortL",14,7),Middle=art("shortM",6,7),Right=art("shortR",12,7)}
 local p={font=3,fields={Style_Titlebar=true,Style_Closebox=true}}
 local m=R.WindowChrome(p,"Readable source caption",box,I)
 equal(m.titleArtHeight,7);equal(m.titleHeight,17);equal(m.top,17);equal(m.titleFont,3)
 bounds("shortL",100,200,14,7);bounds("shortM",114,200,174,7);bounds("shortR",288,200,12,7)
 equal(texts[1][8],nil,"caption uses selected font at its real current scale")
 equal(texts[1][2],202.5);equal(m.close.top,3.5)
 local large=R.ChromeInsets({font=6,fields={Style_Titlebar=true}},I,1)
 equal(large.titleHeight,24);equal(large.titleArtHeight,7)
 local scaled=R.ChromeInsets(p,I,1.5);equal(scaled.titleHeight,25.5);equal(scaled.titleArtHeight,10.5)
end)
run("borderless transparent source leaves the scene untouched",function()
 local I=fixture();R.WindowChrome({fields={Style_Border=false,Style_Titlebar=false,Style_Transparent=true}},"",box,I)
 equal(fills,0);equal(#draws,0)
end)
run("available background cannot conceal a missing frame fallback",function()
 local I,index=fixture();index.templates.Window.fields.Border="missing"
 R.WindowChrome({fields={Style_Titlebar=false}},"",box,I)
 drawn("background");equal(borders,1);check(I.messages["frame-art"])
end)
run("title draw exceptions cannot leak font or clip stacks",function()
 local I=fixture();local original=ui.DrawText;ui.DrawText=function()error("synthetic title failure")end
 local ok,why=pcall(R.WindowChrome,{fields={Style_Titlebar=true}},"title",box,I)
 ui.DrawText=original;equal(ok,false);check(why:find("synthetic title failure",1,true))
end)
run("frame draw exceptions cannot leak clip stacks",function()
 local I=fixture();local original=ui.DrawImage;ui.DrawImage=function()error("synthetic image failure")end
 local ok=pcall(R.Frame,I,"Border",box);ui.DrawImage=original;equal(ok,false)
end)
run("edge-only frame omits its middle even when all pieces share one animation",function()
 local I,index=fixture();index.templates.Same={fields={TopLeft="TL",Top="TL",TopRight="TL",Left="TL",Middle="TL",Right="TL",BottomLeft="TL",Bottom="TL",BottomRight="TL"}}
 R.Frame(I,"Same",box,nil,1,true);equal(#draws,8)
end)
run("raw Begin compatibility chrome never paints over an existing native caption",function()
 local paints,last,depth={},nil,0
 local UI={WindowFlags={NoBackground=1,NoInputs=6},Col={}}
 for _,kind in ipairs({"Button","SmallButton","Checkbox","SliderInt","SliderFloat"})do UI[kind]=function()error("No item registration during Begin chrome")end end
 UI.Begin=function()last="native caption/close item";return true,false,nil,42 end
 UI.GetWindowPos=function()return 10,20 end;UI.GetWindowSize=function()return 210,160 end
 UI.GetCursorScreenPos=function()return 20,50 end;UI.GetContentRegionAvail=function()return 190,120 end
 UI.GetIO=function()return {uiScale=1}end
 UI.PushClipRect=function(x0,y0,x1,y1)depth=depth+1;paints[#paints+1]={"clip",x0,y0,x1,y1}end
 UI.PopClipRect=function()depth=depth-1 end
 setmetatable(UI,{__index=function(_,name)error("Unexpected Begin operation "..name)end})
 local context={instance={index={windows={Synthetic="test"}}},renderer={
  Chrome=function(_,r,opts)paints[#paints+1]={"chrome",r,opts};equal(last,"native caption/close item")end}}
 local E=setmetatable({ui=UI},{__index=_G});E._G=E
 E.dofile=function(path)
  if path=="lib/pack_context.lua"then return context end
  equal(path,"lib/pack_source_windows.lua")
 end
 assert(loadfile("shared/bootstrap.lua","t",E))()
 local result=table.pack(UI.Begin("Native title",true,0))
 equal(result.n,4);equal(result[1],true);equal(result[2],false);equal(result[3],nil);equal(result[4],42)
 equal(paints[1][1],"clip");equal(paints[1][3],50,"source edges start below existing native caption")
 equal(paints[2][3].frameOnly,true);equal(paints[3][3].backgroundOnly,true);equal(depth,0)
 local count=#paints
 E.hailstone_skin_managed_begin(function()UI.Begin("Source-managed full outer")end)
 equal(#paints,count,"source WindowChrome owns managed frame without a second overlay")
end)
run("theme uses source fonts and suppresses only source-managed duplicate panels",function()
 local painted=0
 local T={color={},font={}}
 local context={instance={style={fonts={text=2,title=4,small=1}},palette={background={0,0,0,1},text={1,1,1,1},border={1,1,1,1}}},
  profile={id="synthetic",label="Synthetic"},renderer={StyleTheme=function(actual)
   equal(actual,T);T.Panel=function()painted=painted+1;return "painted"end
  end}}
 local E=setmetatable({hs={UI={interfaces={LoadBase=function(path)equal(path,"lib/theme.lua");return T end}}},
  dofile=function(path)equal(path,"lib/pack_context.lua");return context end},{__index=_G});E._G=E
 local result=assert(loadfile("shared/theme.lua","t",E))()
 equal(result,T);equal(T.font.normal,2);equal(T.font.small,1);equal(T.font.huge,4)
 equal(T.Panel(),"painted");equal(painted,1)
 context.sourceManagedPanel=true;equal(T.Panel(),false);equal(painted,1)
 context.sourceManagedPanel=nil;equal(T.Panel(),"painted");equal(painted,2)
 equal(assert(loadfile("shared/theme.lua","t",E))(),T,"reloading same context does not wrap panels repeatedly")
end)
print(string.format("Lua chrome geometry: %d cases, %d assertions passed",cases,assertions))
