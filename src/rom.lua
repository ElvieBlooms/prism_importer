-- A DS card image read in pieces: the header, then the file name and
-- allocation tables, then only the files asked for. `read(offset, length)`
-- is mod.imports:read for one import (8 MiB a call), so a 512 MiB Black 2
-- dump is never held whole. Same layout as the engine's
-- src/import/gen5/Nds.lua. -Elvie
local Rom = { CHUNK = 8 * 1024 * 1024 }

local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a + b * 256 end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
Rom.u16, Rom.u32 = u16, u32

function Rom.open(read)
  local header = read(0, 512)
  assert(type(header) == "string" and #header == 512, "truncated DS header")
  local rom = { code = header:sub(13, 16), title = header:sub(1, 12):gsub("%z+$", "") }
  local fo, fl, ao, al = u32(header, 0x40), u32(header, 0x44), u32(header, 0x48), u32(header, 0x4c)
  assert(fl >= 8 and fl <= Rom.CHUNK and al > 0 and al % 8 == 0 and al <= Rom.CHUNK, "invalid DS filesystem")
  local fnt, fat = read(fo, fl), read(ao, al)
  assert(#fnt == fl and #fat == al, "truncated DS filesystem")
  local count = u16(fnt, 6)
  assert(count > 0 and count <= 4096 and count * 8 <= fl, "invalid DS directory table")

  -- offset and length of `path` ("/a/0/0/4")
  function rom.find(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do parts[#parts + 1] = part end
    local dir = 0
    for i, part in ipairs(parts) do
      local pos, id = u32(fnt, dir * 8), u16(fnt, dir * 8 + 4)
      local found = false
      while pos < fl do
        local control = fnt:byte(pos + 1); pos = pos + 1
        if control == 0 then break end
        local length, isDir = control % 128, control >= 128
        local name = fnt:sub(pos + 1, pos + length); pos = pos + length
        local child
        if isDir then child = u16(fnt, pos); pos = pos + 2 end
        if name == part then
          if i == #parts then
            if isDir then return nil, "not a file: " .. path end
            local first, last = u32(fat, id * 8), u32(fat, id * 8 + 4)
            return first, last - first
          end
          if not isDir then return nil, "not a folder: " .. path end
          dir, found = child - 0xf000, true
          break
        end
        if not isDir then id = id + 1 end
      end
      if not found then return nil, "not found: " .. path end
    end
  end

  -- the whole file, read in 8 MiB pieces
  function rom.file(path)
    local offset, length = rom.find(path)
    if not offset then error(length, 0) end
    local pieces, done = {}, 0
    while done < length do
      local n = math.min(Rom.CHUNK, length - done)
      local piece = read(offset + done, n)
      assert(type(piece) == "string" and #piece == n, "short read in " .. path)
      pieces[#pieces + 1] = piece
      done = done + n
    end
    return table.concat(pieces)
  end
  return rom
end

return Rom
