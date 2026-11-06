-- Gen 4 overworld sprites: each archive member is a BTX0 holding one TEX0
-- block of textures (one per frame, named "<model>.<frame>") and one or more
-- palettes (a second is a shiny or alternate colour). Textures here are
-- 4bpp (format 3) or 2bpp (format 2), colour 0 see-through when the
-- texture's flag says so.
local Binary=require("src.import.gen5.Binary")

local Btx={MAX_SIDE=256}

-- A 3D info list: count, then (after a header and per-entry words) entries of
-- `size` bytes, then 16-byte names.
local function list(r,pos)
  local count=r.u8(pos+1)
  local p=pos+4+8+4*count
  local size=r.u16(p)
  p=p+4
  local entries,names={},{}
  for i=0,count-1 do entries[i+1]=p+i*size end
  p=p+size*count
  for i=0,count-1 do
    local name=r.sub(p+i*16,16):gsub("%z.*$","")
    names[i+1]=name
  end
  return entries,names,count
end

function Btx.parse(data)
  local r=Binary.reader(data)
  assert(r.sub(0,4)=="BTX0","invalid BTX0 signature")
  local t=r.u32(16)
  assert(r.sub(t,4)=="TEX0","missing TEX0 block")
  local texInfo=r.u16(t+0x0E)
  local texData=r.u32(t+0x14)
  local palInfo=r.u32(t+0x34)
  local palData=r.u32(t+0x38)
  local result={textures={},palettes={}}
  local entries,names=list(r,t+texInfo)
  for i,e in ipairs(entries) do
    local word=r.u32(e)
    local offset=(word%65536)*8
    local w=8*2^(math.floor(word/2^20)%8)
    local h=8*2^(math.floor(word/2^23)%8)
    local format=math.floor(word/2^26)%8
    local clear=math.floor(word/2^29)%2==1
    assert(w<=Btx.MAX_SIDE and h<=Btx.MAX_SIDE,"texture too large")
    result.textures[i]={name=names[i],offset=t+texData+offset,width=w,height=h,format=format,clear=clear}
  end
  entries,names=list(r,t+palInfo)
  for i,e in ipairs(entries) do
    result.palettes[i]={name=names[i],offset=t+palData+r.u16(e)*8}
  end
  result.reader=r
  return result
end

-- "<model>.<n>" -> model, n; frames sort by n, not by name.
function Btx.frames(tex)
  local list={}
  local model
  for _,t in ipairs(tex.textures) do
    local base,n=t.name:match("^(.-)%.(%d+)$")
    base=base or t.name
    model=model or base
    list[#list+1]={texture=t,n=tonumber(n) or 0}
  end
  table.sort(list,function(a,b) return a.n<b.n end)
  local out={}
  for i,f in ipairs(list) do out[i]=f.texture end
  return out,model
end

local function expand(v) return v*8+math.floor(v/4) end

-- Draws texture `t` with palette `p` into `image` at (ox, oy).
function Btx.draw(tex,t,p,image,ox,oy)
  local r=tex.reader
  local bits=t.format==3 and 4 or t.format==2 and 2 or t.format==4 and 8 or nil
  assert(bits,"unsupported texture format "..tostring(t.format))
  local perByte=8/bits
  local mask=2^bits
  r.bounds(t.offset,t.width*t.height/perByte)
  for i=0,t.width*t.height-1 do
    local byte=r.u8(t.offset+math.floor(i/perByte))
    local index=math.floor(byte/2^((i%perByte)*bits))%mask
    if not (index==0 and t.clear) then
      local v=r.u16(p.offset+index*2)
      image:setPixel(ox+i%t.width,oy+math.floor(i/t.width),
        expand(v%32)/255,expand(math.floor(v/32)%32)/255,expand(math.floor(v/1024)%32)/255,1)
    end
  end
end

return Btx
