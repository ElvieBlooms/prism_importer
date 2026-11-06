-- Prism Importer: sprites from the player's own DS dumps, for other mods.
-- Pick a Diamond/Pearl/Platinum, HeartGold/SoulSilver or Black 2/White 2
-- dump in this mod's imports, then import it from the IMPORTER page in
-- PRISM. The import runs on its own thread (the "compute" permission) into
-- this mod's cache, and the sprites are handed out through mod.exports.
-- Nothing from the games ships with the mod. -Elvie
local mod = ...
-- loaded on first use (the extractor pulls in the engine's Gen 5 readers)
local Extract = setmetatable({}, { __index = function(self, k)
  local real = require("mods.prism_importer.src.extract")
  setmetatable(self, { __index = real })
  return real[k]
end })

local GAMES = { "dppt", "hgss", "bw2" }
-- Without a thread, the import runs a slice of each frame instead: this
-- much of it, in seconds. -Elvie
local BUDGET = 0.005

-- state per dump: absent (none picked), needed (picked, not imported yet,
-- or picked again), queued, running, ready, failed -Elvie
local state = {
  games = {},      -- game -> loaded index
  status = {},     -- game -> { state, done, total, message, stamp }
  queue = {},      -- games the player asked for, in order
  job = nil,       -- { game, stamp, thread, out, control } or { game, stamp, co }
  images = {},     -- "game/pack/id" -> love Image
  checkedAt = -1,
  game = nil,      -- the running game, for the loader
  threadNote = nil,
}
local jobs = 0

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
  return ("%s|%s|%s"):format(Extract.VERSION, tostring(info.size), tostring(info.modtime or info.md5))
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

local function queued(game)
  for _, g in ipairs(state.queue) do if g == game then return true end end
  return false
end

local function check()
  for _, game in ipairs(GAMES) do
    local okInfo, info = pcall(mod.imports.info, mod.imports, game)
    local st = state.status[game] or {}
    state.status[game] = st
    if not (okInfo and type(info) == "table") then
      st.state, st.message, st.stamp = "absent", nil, nil
      state.games[game] = nil
    elseif not (state.job and state.job.game == game) then
      local now = stampOf(info)
      if stamp(game) == now then
        if not state.games[game] then state.games[game] = loadIndex(game) end
        st.state = state.games[game] and "ready" or "needed"
      elseif st.state == "failed" and st.stamp == now then
        -- stays failed until it's asked for again -Elvie
      else
        st.state, st.stamp = queued(game) and "queued" or "needed", now
      end
    end
  end
end

-- plain data as JSON, for the worker (it reads it with the engine's
-- decoder) -Elvie
local function menuJson(v)
  local t = type(v)
  if t == "string" then
    return '"' .. v:gsub('[%c"\\]', function(c) return ("\\u%04x"):format(c:byte()) end) .. '"'
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t ~= "table" then return "null" end
  if #v > 0 or next(v) == nil then
    local out = {}
    for i = 1, #v do out[i] = menuJson(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  local out = {}
  for k, x in pairs(v) do out[#out + 1] = menuJson(tostring(k)) .. ":" .. menuJson(x) end
  return "{" .. table.concat(out, ",") .. "}"
end

-- The worker gets the same import/cache descriptor the engine's own
-- background jobs get, built from this mod's manifest. -Elvie
local function descriptor()
  local loader = state.game and state.game.mods
  local entry = type(loader) == "table" and type(loader.mods) == "table" and loader.mods[mod.id]
  if not (type(entry) == "table" and type(entry.manifest) == "table") then return nil, "no manifest" end
  local okJ, JobAssetIO = pcall(require, "src.mods.JobAssetIO")
  if not okJ then return nil, "no job I/O" end
  local d, err = JobAssetIO.descriptor(entry.manifest, entry.path or mod.path)
  if not d then return nil, err end
  return menuJson(d)
end

local function startThread(game)
  local okT, thread = pcall(function() return love.thread.newThread(mod.path .. "/src/worker.lua") end)
  if not okT or not thread then return nil, tostring(thread) end
  local d, err = descriptor()
  if not d then return nil, err end
  jobs = jobs + 1
  local outName, controlName = ("prism_importer_out_%d"):format(jobs), ("prism_importer_control_%d"):format(jobs)
  local out, control = love.thread.getChannel(outName), love.thread.getChannel(controlName)
  out:clear(); control:clear()
  thread:start(mod.id, mod.path, game, d, outName, controlName)
  return { thread = thread, out = out, control = control }
end

local function startNext()
  local game = table.remove(state.queue, 1)
  if not game then return end
  local st = state.status[game]
  if not (st and (st.state == "queued" or st.state == "needed" or st.state == "failed")) then return startNext() end
  local okInfo, info = pcall(mod.imports.info, mod.imports, game)
  if not (okInfo and type(info) == "table") then return startNext() end
  local job, why = startThread(game)
  if job then
    log("importing %s on its own thread", game)
  else
    if state.threadNote ~= why then
      state.threadNote = why
      log("no thread (%s): importing a little each frame", tostring(why))
    end
    job = { co = coroutine.create(function()
      return Extract.run({ game = game, read = readerFor(game), cache = mod.cache })
    end) }
  end
  job.game, job.stamp = game, stampOf(info)
  state.job = job
  st.state, st.done, st.total, st.message = "running", 0, 1, "Starting"
  state.games[game] = nil
end

local function finish(job, ok, message)
  local st = state.status[job.game]
  state.job = nil
  if ok then
    state.games[job.game] = loadIndex(job.game)
    mod.cache:write(job.game .. "/stamp.txt", job.stamp)
    st.state, st.message = state.games[job.game] and "ready" or "failed", nil
    if not state.games[job.game] then st.message = "the import's index didn't load" end
    state.images = {}
    log("%s imported", job.game)
  else
    st.state, st.message = "failed", tostring(message)
    mod.log:warn("%s: %s", job.game, tostring(message))
  end
end

local function pump()
  local job = state.job
  if not job then return end
  local st = state.status[job.game]
  if job.thread then
    while true do
      local msg = job.out:pop()
      if not msg then break end
      if msg.kind == "progress" then
        st.done, st.total, st.message = msg.done, msg.total, msg.status
      elseif msg.kind == "done" then
        return finish(job, true)
      elseif msg.kind == "failed" then
        return finish(job, false, msg.message)
      elseif msg.kind == "stopped" then
        state.job, st.state = nil, "needed"
        return
      end
    end
    local err = job.thread:getError()
    if err then return finish(job, false, err) end
    return
  end
  local clock = love.timer.getTime
  local deadline = clock() + BUDGET
  repeat
    local ok, value = coroutine.resume(job.co)
    if not ok then return finish(job, false, value) end
    if coroutine.status(job.co) == "dead" then return finish(job, true) end
    if type(value) == "table" and value.total then
      st.done, st.total, st.message = value.done, value.total, value.status
    end
  until clock() >= deadline
end

mod.hooks:wrap("core.update", function(nextFn, game, dt, ...)
  if type(game) == "table" then state.game = game end
  local now = love.timer.getTime()
  if now - state.checkedAt > 2 and not state.job then
    state.checkedAt = now
    pcall(check)
  end
  if not state.job then startNext() end
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

-- { game = { state = absent|needed|queued|running|ready|failed, done, total, message } }
function mod.exports.status()
  local out = {}
  for game, st in pairs(state.status) do
    out[game] = { state = st.state, done = st.done, total = st.total, message = st.message }
  end
  return out
end

-- Import a dump (or every dump that needs it, with no game); returns how
-- many were queued. -Elvie
function mod.exports.start(game)
  pcall(check)
  local n = 0
  for _, g in ipairs(GAMES) do
    local st = state.status[g]
    if (game == nil or game == g) and st and (st.state == "needed" or st.state == "failed") and not queued(g) then
      state.queue[#state.queue + 1] = g
      st.state, st.message = "queued", nil
      n = n + 1
    end
  end
  return n
end

-- Import a dump again, though it's imported already -Elvie
function mod.exports.reimport(game)
  if state.job and state.job.game == game then return 0 end
  pcall(mod.cache.write, mod.cache, game .. "/stamp.txt", "")
  state.games[game] = nil
  local st = state.status[game]
  if st then st.state = "needed" end
  return mod.exports.start(game)
end

-- what's importing now: { game, done, total } or nil -Elvie
function mod.exports.current()
  local job = state.job
  if not job then return nil end
  local st = state.status[job.game] or {}
  return { game = job.game, done = st.done or 0, total = st.total or 1, threaded = job.thread ~= nil }
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

do
  local ok, err = pcall(function() require("mods.prism_importer.src.menu").start(mod, mod.exports, GAMES) end)
  if not ok then mod.log:warn("IMPORTER isn't in PRISM: %s", tostring(err)) end
end
