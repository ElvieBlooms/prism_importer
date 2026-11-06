-- DS Imports: sprites from the player's own DS dumps, for other mods.
-- Import a Diamond/Pearl/Platinum, HeartGold/SoulSilver or Black 2/White 2
-- dump in this mod's imports; the sprites are pulled out once, a little each
-- frame, into this mod's cache, and handed out through mod.exports. Nothing
-- from the games ships with the mod. -Elvie
local mod = ...
-- loaded on first use (the extractor pulls in the engine's Gen 5 readers)
local Extract = setmetatable({}, { __index = function(self, k)
  local real = require("mods.ds_imports.src.extract")
  setmetatable(self, { __index = real })
  return real[k]
end })

local GAMES = { "dppt", "hgss", "bw2" }
local BUDGET = 0.005 -- seconds of extraction a frame

local state = {
  games = {},      -- game -> loaded index
  status = {},     -- game -> { state, done, total, message }
  job = nil,       -- { game, co }
  images = {},     -- "game/pack/id" -> love Image
  checkedAt = -1,
}

local function log(fmt, ...) mod.log:info(fmt, ...) end

local function readerFor(game)
  return function(offset, length)
    local bytes, err = mod.imports:read(game, offset, length)
    if not bytes then error("import read failed: " .. tostring(err), 0) end
    return bytes
  end
end

-- the cache is current for this import when its stamp matches the import's
local function stampOf(info)
  return ("%s|%s|%s"):format(Extract.VERSION, tostring(info.size), tostring(info.modtime))
end

local function loadIndex(game)
  local ok, src = pcall(mod.cache.read, mod.cache, game .. "/index.lua")
  if not (ok and type(src) == "string") then return nil end
  local chunk = load(src, "=" .. game .. "/index", "t", {})
  local okRun, index = pcall(chunk or error)
  if okRun and type(index) == "table" and index.version == Extract.VERSION then return index end
end

local function stamp(game)
  local ok, src = pcall(mod.cache.read, mod.cache, game .. "/stamp.txt")
  return ok and src or nil
end

local function check()
  for _, game in ipairs(GAMES) do
    local okInfo, info = pcall(mod.imports.info, mod.imports, game)
    local st = state.status[game] or {}
    state.status[game] = st
    if not (okInfo and type(info) == "table") then
      st.state, st.message = "absent", nil
      state.games[game] = nil
    elseif not (state.job and state.job.game == game) then
      if stamp(game) == stampOf(info) then
        if not state.games[game] then state.games[game] = loadIndex(game) end
        st.state = state.games[game] and "ready" or "pending"
      elseif st.state ~= "failed" or st.stamp ~= stampOf(info) then
        st.state, st.stamp = "pending", stampOf(info)
      end
    end
  end
end

local function startNext()
  for _, game in ipairs(GAMES) do
    local st = state.status[game]
    if st and st.state == "pending" then
      local info = mod.imports:info(game)
      local co = coroutine.create(function()
        return Extract.run({ game = game, read = readerFor(game), cache = mod.cache })
      end)
      state.job = { game = game, co = co, stamp = stampOf(info) }
      st.state, st.done, st.total, st.message = "running", 0, 1, "Starting"
      state.games[game] = nil
      log("extracting %s", game)
      return
    end
  end
end

local function pump()
  local job = state.job
  if not job then return end
  local st = state.status[job.game]
  local clock = love.timer.getTime
  local deadline = clock() + BUDGET
  repeat
    local ok, value = coroutine.resume(job.co)
    if not ok then
      st.state, st.message = "failed", tostring(value)
      mod.log:warn("%s: %s", job.game, tostring(value))
      state.job = nil
      return
    end
    if coroutine.status(job.co) == "dead" then
      state.games[job.game] = value
      mod.cache:write(job.game .. "/stamp.txt", job.stamp)
      st.state, st.message = "ready", nil
      state.images = {}
      log("%s ready: %s", job.game, value.source and value.source.name or "")
      state.job = nil
      return
    end
    if type(value) == "table" and value.total then
      if math.floor(value.done / 500) ~= math.floor((st.done or 0) / 500) then
        log("%s: %d of %d (%s)", job.game, value.done, value.total, tostring(value.status))
      end
      st.done, st.total, st.message = value.done, value.total, value.status
    end
  until clock() >= deadline
end

mod.hooks:wrap("core.update", function(nextFn, game, dt, ...)
  local now = love.timer.getTime()
  if not state.job and now - state.checkedAt > 2 then
    state.checkedAt = now
    pcall(check)
    startNext()
  end
  pump()
  return nextFn(game, dt, ...)
end)

---------------------------------------------------------------- exports

mod.exports.apiVersion = 1

-- { game = { name, packs = { pack = count } } } for every dump that's ready
function mod.exports.games()
  local out = {}
  for game, index in pairs(state.games) do
    local packs = {}
    for pack, entries in pairs(index.packs or {}) do
      local n = 0
      for _ in pairs(entries) do n = n + 1 end
      packs[pack] = n
    end
    out[game] = { name = index.source and index.source.name, family = index.source and index.source.family, packs = packs }
  end
  return out
end

-- { game = { state = absent|pending|running|ready|failed, done, total, message } }
function mod.exports.status()
  local out = {}
  for game, st in pairs(state.status) do
    out[game] = { state = st.state, done = st.done, total = st.total, message = st.message }
  end
  return out
end

-- id -> { file, width, height, frames, sprite = { width, height, columns, frames, ... } }
function mod.exports.entries(game, pack)
  local index = state.games[game]
  return index and index.packs[pack] or nil
end

function mod.exports.entry(game, pack, id)
  local entries = mod.exports.entries(game, pack)
  return entries and entries[id] or nil
end

-- a new ImageData of the entry's whole sheet, or nil
function mod.exports.imageData(game, pack, id)
  local e = mod.exports.entry(game, pack, id)
  if not e then return nil end
  local ok, bytes = pcall(mod.cache.read, mod.cache, e.file)
  if not (ok and type(bytes) == "string") then return nil end
  local okData, data = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, "sprite.png"))
  return okData and data or nil, e
end

-- a shared Image (nearest filtering) of the entry's sheet, and its entry
function mod.exports.image(game, pack, id)
  local key = game .. "/" .. pack .. "/" .. id
  local image = state.images[key]
  if image then return image, mod.exports.entry(game, pack, id) end
  local data, e = mod.exports.imageData(game, pack, id)
  if not data then return nil end
  image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  state.images[key] = image
  return image, e
end

pcall(check)
