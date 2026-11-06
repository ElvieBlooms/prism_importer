-- Gen 4 battle and trainer pictures: an NCGR of 4bpp pixels in reading order
-- (character type 1), scrambled with the games' 16-bit stream cipher. The seed
-- is the first or the last 16-bit word, and the stream runs front to back or
-- back to front; which one varies by archive, so both are tried and the one
-- that leaves the most transparent pixels wins (a picture is mostly
-- background). Palettes are ordinary NCLRs, read by gen5 Graphics.
local Binary=require("src.import.gen5.Binary")
local Graphics=require("src.import.gen5.Graphics")
local Lz=require("src.import.gen5.Lz")

local Pictures={MAX_PIXELS=256*256}

local function section(r,magic)
  local pos=r.u16(12)
  while pos+8<=r.size do
    local size=r.u32(pos+4)
    assert(size>=8,"invalid Nitro section length")
    if r.sub(pos,4)==magic then return pos,size end
    pos=pos+size
  end
  error("missing Nitro section "..magic,0)
end

-- Unscramble a list of 16-bit words; direction 1 seeds from the first word
-- and walks forward, -1 seeds from the last and walks back.
-- 16-bit xor without the bit library
local function xor16(a,b)
  local r,p=0,1
  for _=1,16 do
    local x,y=a%2,b%2
    if x~=y then r=r+p end
    a,b,p=(a-x)/2,(b-y)/2,p*2
  end
  return r
end
Pictures.xor16=xor16

local function unscramble(words,direction)
  local n=#words
  local out={}
  local seed=direction==1 and words[1] or words[n]
  local first,last=1,n
  if direction==-1 then first,last=n,1 end
  for i=first,last,direction do
    out[i]=xor16(words[i],seed%65536)
    -- seed = seed * 0x41C64E6D + 0x6073 (mod 2^32), kept exact in doubles
    local lo,hi=seed%65536,math.floor(seed/65536)
    local mlo,mhi=0x4E6D,0x41C6
    local low=lo*mlo
    local mid=(lo*mhi+hi*mlo)%65536
    seed=(low+mid*65536+0x6073)%4294967296
  end
  return out
end
Pictures.unscramble=unscramble

local function zeros(words)
  local count=0
  for i=1,#words do
    local w=words[i]
    for _=1,4 do
      if w%16==0 then count=count+1 end
      w=math.floor(w/16)
    end
  end
  return count
end

-- Returns { width, height, pixels = {index 0-15 per pixel, 1-based} } in
-- reading order. A 0-byte member (no female picture) returns nil.
function Pictures.decode(data)
  if data==nil or #data==0 then return nil end
  local r=Binary.reader(data)
  assert(r.sub(0,4)=="RGCN","invalid NCGR signature")
  local pos,size=section(r,"RAHC")
  local tilesHigh,tilesWide=r.u16(pos+8),r.u16(pos+10)
  local depth=r.u32(pos+12)
  local length=r.u32(pos+24)
  assert(depth==3,"Gen 4 pictures are 4bpp")
  assert(length>0 and length<=size-0x20 and length%2==0,"invalid NCGR length")
  local width,height=tilesWide*8,tilesHigh*8
  assert(width*height==length*2 and width*height<=Pictures.MAX_PIXELS,"unexpected NCGR size")
  local words={}
  for i=0,length/2-1 do words[i+1]=r.u16(pos+0x20+i*2) end
  local best,bestZeros
  for _,candidate in ipairs({words,unscramble(words,1),unscramble(words,-1)}) do
    local z=zeros(candidate)
    if not best or z>bestZeros then best,bestZeros=candidate,z end
  end
  local pixels={}
  for i,w in ipairs(best) do
    local b=(i-1)*4
    pixels[b+1]=w%16
    pixels[b+2]=math.floor(w/16)%16
    pixels[b+3]=math.floor(w/256)%16
    pixels[b+4]=math.floor(w/4096)%16
  end
  return {width=width,height=height,pixels=pixels}
end

function Pictures.palette(data)
  return Graphics.parsePalette(Lz.decode(data))
end

-- How many 80x80 frames side by side hold any ink (Diamond/Pearl backs have
-- one, everything else two).
function Pictures.frames(picture,frameWidth)
  local count=0
  for f=0,math.floor(picture.width/frameWidth)-1 do
    local ink=false
    for y=0,picture.height-1 do
      for x=f*frameWidth,(f+1)*frameWidth-1 do
        if picture.pixels[y*picture.width+x+1]~=0 then ink=true break end
      end
      if ink then break end
    end
    if ink then count=f+1 end
  end
  return math.max(count,1)
end

-- An ImageData of the first `frames` frames, colour 0 see-through.
function Pictures.image(picture,palette,frameWidth,frames)
  assert(love and love.image,"LÖVE image module required for sprite import")
  local width=math.min(picture.width,frameWidth*frames)
  local image=love.image.newImageData(width,picture.height)
  for y=0,picture.height-1 do
    for x=0,width-1 do
      local index=picture.pixels[y*picture.width+x+1]
      if index~=0 then
        local c=palette.colors[index+1]
        if c then image:setPixel(x,y,c.r/255,c.g/255,c.b/255,1) end
      end
    end
  end
  return image
end

return Pictures
