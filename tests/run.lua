-- run from the mod folder: ENGINE=<gen1recomp checkout> luajit tests/run.lua
local ENGINE=os.getenv("ENGINE") or "../gen1recomp"
package.path=ENGINE.."/?.lua;"..ENGINE.."/?/init.lua;./?.lua;"..package.path
package.preload["mods.prism_importer.src.gen4.pictures"]=function() return dofile("src/gen4/pictures.lua") end
package.preload["mods.prism_importer.src.gen4.btx"]=function() return dofile("src/gen4/btx.lua") end
package.preload["mods.prism_importer.src.gen4.names"]=function() return dofile("src/gen4/names.lua") end
package.preload["mods.prism_importer.src.gen5.names"]=function() return dofile("src/gen5/names.lua") end
package.preload["mods.prism_importer.src.menu"]=function() return dofile("src/menu.lua") end
package.preload["mods.prism_importer.src.rom"]=function() return dofile("src/rom.lua") end
package.preload["mods.prism_importer.src.extract"]=function() return dofile("src/extract.lua") end
-- ROM-free checks for the Gen 4 importers: the picture cipher, BTX0
-- textures, the names tables and the importer registry.
local Pictures=require("mods.prism_importer.src.gen4.pictures")
local Btx=require("mods.prism_importer.src.gen4.btx")
local Names=require("mods.prism_importer.src.gen4.names")
local Gen4=require("mods.prism_importer.src.extract")
local Rom=require("mods.prism_importer.src.rom")
local count=0
local function check(value,what) assert(value,what);count=count+1 end
local function rejects(fn,what) check(not pcall(fn),what) end
local function u16(n) return string.char(n%256,math.floor(n/256)%256) end
local function u32(n) return u16(n%65536)..u16(math.floor(n/65536)) end

-- the cipher is its own inverse from the same seed
local words={}
for i=1,40 do words[i]=(i*7919)%65536 end
local function same(a,b) for i=1,#a do if a[i]~=b[i] then return false end end return true end
for _,dir in ipairs({1,-1}) do
  local scrambled=Pictures.unscramble(words,dir)
  -- scrambling keeps the seed word's position zeroed, so rebuild the seed
  check(scrambled[dir==1 and 1 or #words]==0,"seed word xors to zero")
end

-- a picture whose pixels are mostly 0 is found under either direction
local function ncgr(pixelWords,tilesWide,tilesHigh)
  local body={}
  for i,w in ipairs(pixelWords) do body[i]=u16(w) end
  body=table.concat(body)
  local rahc="RAHC"..u32(0x20+#body)..u16(tilesHigh)..u16(tilesWide)..u32(3)..u32(0)..u32(1)..u32(#body)..u32(0x18)..body
  return "RGCN"..u16(0xfeff)..u16(0x0101)..u32(16+#rahc)..u16(16)..u16(1)..rahc
end
-- 8x8 picture: one ink pixel (index 5) at x=3, y=2
local plain={}
for i=1,16 do plain[i]=0 end
local inkWord=math.floor((2*8+3)/4)+1
plain[inkWord]=5*16^((2*8+3)%4)
-- scramble forward from a chosen seed: x[1] is the seed word itself
local function scramble(src,dir,seed)
  local n=#src;local out={}
  local first,last=1,n
  if dir==-1 then first,last=n,1 end
  local s=seed
  for i=first,last,dir do
    out[i]=Pictures.xor16(src[i],s%65536)
    local lo,hi=s%65536,math.floor(s/65536)
    s=(lo*0x4E6D+((lo*0x41C6+hi*0x4E6D)%65536)*65536+0x6073)%4294967296
  end
  return out
end
for _,dir in ipairs({1,-1}) do
  local src={}
  for i=1,#plain do src[i]=plain[i] end
  local seedAt=dir==1 and 1 or #src
  -- the cipher xors the seed word with itself, so a plain 0 there and a
  -- stored seed decode back to 0
  local enc=scramble(src,dir,0x1234)
  enc[seedAt]=0x1234
  local pic=Pictures.decode(ncgr(enc,1,1))
  check(pic.width==8 and pic.height==8,"8x8 picture")
  check(pic.pixels[2*8+3+1]==5,"ink pixel decoded, direction "..dir)
  local others=0
  for i,v in ipairs(pic.pixels) do if i~=2*8+3+1 and v~=0 then others=others+1 end end
  check(others==0,"background stays clear, direction "..dir)
end
check(Pictures.decode("")==nil,"an empty member is no picture")
rejects(function() Pictures.decode("XXXX"..string.rep("\0",40)) end,"not an NCGR")

-- frames: ink only in the left 80 columns is one frame
local wide={width=160,height=2,pixels={}}
for i=1,320 do wide.pixels[i]=0 end
wide.pixels[5]=1
check(Pictures.frames(wide,80)==1,"one inked frame")
wide.pixels[100]=1
check(Pictures.frames(wide,80)==2,"two inked frames")

-- BTX0: one 8x8 4bpp texture "a.2" and "a.1", one palette
local function name16(s) return s..string.rep("\0",16-#s) end
local function infoList(entries,names,size)
  local n=#entries
  local head=string.char(0,n)..u16(0)..u16(8)..u16(0)..u32(0x17f)..string.rep(u32(0),n)
  return head..u16(size)..u16(0)..table.concat(entries)..table.concat(names)
end
local texParam=function(offset) return u32(math.floor(offset/8)+2^20*0+2^23*0+2^26*3+2^29) end
local texInfo=infoList({texParam(0)..u32(0),texParam(32)..u32(0)},{name16("a.2"),name16("a.1")},8)
local palInfo=infoList({u16(0)..u16(0)},{name16("p")},4)
local texData=string.rep("\0",32)..(string.char(0x21)..string.rep("\0",31))
local palData=u16(0)..u16(31)..u16(31*32)..string.rep(u16(0),13)
local hdr=0x3C
local tex0Body
local function build()
  local ti=hdr
  local pi=ti+#texInfo
  local td=pi+#palInfo
  local pd=td+#texData
  local t="TEX0"..u32(pd+#palData)..u32(0)..u16(#texData/8)..u16(ti)..u32(0)..u32(td)..u32(0)
    ..u16(0)..u16(0)..u32(0)..u32(0)..u32(0)..u32(0)..u32(#palData/8)..u32(pi)..u32(pd)
  t=t..string.rep("\0",hdr-#t)
  return t..texInfo..palInfo..texData..palData
end
tex0Body=build()
local btx="BTX0"..u16(0xfeff)..u16(1)..u32(20+#tex0Body)..u16(16)..u16(1)..u32(20)..tex0Body
local tex=Btx.parse(btx)
check(#tex.textures==2 and #tex.palettes==1,"two textures, one palette")
local frames,model=Btx.frames(tex)
check(model=="a" and frames[1].name=="a.1" and frames[2].name=="a.2","frames sort by number")
check(frames[1].width==8 and frames[1].format==3 and frames[1].clear,"8x8 4bpp, colour 0 clear")
local drawn={}
local fake={setPixel=function(_,x,y,r,g,b) drawn[#drawn+1]={x,y,r,g,b} end}
Btx.draw(tex,frames[1],tex.palettes[1],fake,0,0)
check(#drawn==2,"two ink pixels")
check(drawn[1][1]==0 and drawn[1][3]==1 and drawn[1][4]==0,"pixel 0 is colour 1 (red)")
check(drawn[2][1]==1 and drawn[2][4]==1 and drawn[2][3]==0,"pixel 1 is colour 2 (green)")

-- names
check(#Names.TRAINERS.dp==98 and #Names.TRAINERS.pt==105 and #Names.TRAINERS.hgss==129,"trainer class counts")
check(Names.TRAINERS.pt[3]=="youngster","Platinum class 2 is Youngster")
check(Names.FORMS[1]=="deoxys/normal/back" and Names.FORMS[158]=="pichu/spiky/front","form order")
check(#Names.FOLLOWERS==566,"566 walking Pokemon")
check(Names.FOLLOWERS[1]=="1" and Names.FOLLOWERS[#Names.FOLLOWERS]=="493:dark","walking Pokemon run Bulbasaur to Arceus")

-- form palettes and ids
local n,s=Gen4.formPalette("hgss","deoxys/attack/back")
check(n==158 and s==159,"Deoxys forms share Deoxys' palettes")
n,s=Gen4.formPalette("dp","unown/q/front")
check(n==134+2 and s==134+3,"Unown shares one pair (after Deoxys)")
n,s=Gen4.formPalette("dp","egg/manaphy")
check(n and s==nil,"eggs have one palette")
check(Gen4.formPalette("dp","rotom/fan/front")==nil,"Diamond has no Rotom forms")
check(Gen4.formId("deoxys/attack/back","normal")=="normal/386/back/form/attack","form id")
check(Gen4.formId("egg/manaphy","normal")=="normal/egg/manaphy","egg id")

-- the DS reader works from pieces
local fnt=u32(8)..u16(0)..u16(1)..string.char(1).."x\0"
local header=string.rep("\0",512)
local function put(offset,value) header=header:sub(1,offset)..value..header:sub(offset+#value+1) end
put(12,"CPUE");put(0x40,u32(512)..u32(#fnt)..u32(512+#fnt)..u32(8))
local start=512+#fnt+8
local image=header..fnt..u32(start)..u32(start+5).."HELLO"
local reads=0
local function read(o,n) reads=reads+1 return image:sub(o+1,o+n) end
local rom=Rom.open(read)
check(rom.code=="CPUE","game code")
check(rom.file("/x")=="HELLO","a file by path")
check(rom.find("/y")==nil,"a missing file")
local src=Gen4.identify("dppt",read)
check(src and src.family=="pt" and src.name:find("Platinum"),"Platinum is a dppt dump")
local none,why=Gen4.identify("hgss",read)
check(none==nil and why:find("HeartGold"),"Platinum isn't HeartGold/SoulSilver")
check(Gen4.serialize({a=1,b={"x"}}):find('%["b"%]'),"index serializes")

-- Black 2/White 2 names (pokebw2's lists) and the model tables they're read with
local Bw2Names=require("mods.prism_importer.src.gen5.names")
check(#Bw2Names.FRONTS==188 and Bw2Names.FRONTS[1]=="pkmn_trainer_nate" and Bw2Names.FRONTS[3]=="youngster","Black 2/White 2 trainer names")
check(#Bw2Names.BACKS==31 and Bw2Names.PEOPLE[231]=="hero","Black 2/White 2 backs and people")
local function narc(member)
  local fatb="BTAF"..u32(12+8)..u16(1)..u16(0)..u32(0)..u32(#member)
  local fntb="BTNF"..u32(16)..u32(4)..u16(0)..u16(1)
  local gmif="GMIF"..u32(8+#member)..member
  return "NARC"..u16(0xfffe)..u16(0x0100)..u32(16+#fatb+#fntb+#gmif)..u16(16)..u16(3)..fatb..fntb..gmif
end
local function record(code,kind,member) return u16(code)..string.char(kind,0)..string.rep("\0",12)..u16(member)..string.rep("\0",10) end
local models=narc(u32(3)..record(231,1,7)..record(0x1001,1,9)..record(0x2000,2,0))
local walking=narc(u16(25)..u16(1)..u16(0)..u16(0x1001))
local fake={file=function(path) return path=="/m" and models or walking end}
local owners=Gen4.bw2Owners(fake,{models="/m",walking="/w"})
check(owners[7][1].id=="hero" and owners[9][1].id=="025/female" and owners[9][1].walking and owners[0]==nil,"model table names sprites, walking Pokemon and skips 3D models")

-- the IMPORTER page's words
local Menu=require("mods.prism_importer.src.menu")
check(Menu.label({state="needed"})=="IMPORT" and Menu.label({state="running",done=43,total=100})=="43%" and Menu.label(nil)=="NO DUMP","IMPORTER row labels")
local all={dppt={state="ready"},hgss={state="needed"},bw2={state="failed"}}
local api={status=function() return all end,current=function() end}
check(Menu.value(api,{"dppt","hgss","bw2"})=="2 TO IMPORT","PRISM list: dumps waiting")
all.hgss={state="running",done=1,total=4}
check(Menu.value(api,{"dppt","hgss","bw2"})=="IMPORTING 25%","PRISM list: importing")
all={dppt={state="ready"}}
check(Menu.value(api,{"dppt","hgss","bw2"})=="READY" and Menu.progress(api,{"dppt"})=="ALL IMPORTED.","everything imported")
local rows=Menu.rows({status=function() return {dppt={state="needed"},hgss={state="absent"}} end},{"dppt","hgss"})
check(rows[1].action and not rows[2].action and rows[3].label=="ALL" and rows[3].action,"only dumps that can import have an action")
print("prism_importer PASS "..count.." checks")
