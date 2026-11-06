-- Prism Importer's worker: one dump's import, on its own thread so the game
-- keeps its frame rate. main.lua starts it (the "compute" permission) with
-- the mod's folder, the dump's id and the same import/cache descriptor the
-- engine's own background jobs get, so it reads only this mod's imports and
-- writes only this mod's cache. Progress goes back over a channel. -Elvie
require("love.thread")
require("love.filesystem")
require("love.image")
require("love.data")
require("love.timer")

local modId, modPath, game, descriptorData, outName, controlName = ...
local out = love.thread.getChannel(outName)
local control = love.thread.getChannel(controlName)

-- A new thread has no searcher for the game's own src.* modules, and none
-- for this mod's: add both. -Elvie
table.insert(package.loaders or package.searchers, function(name)
  local own = name:match("^mods%.prism_importer%.(.+)$")
  local path = own and (modPath .. "/" .. own:gsub("%.", "/") .. ".lua") or (name:gsub("%.", "/") .. ".lua")
  if not love.filesystem.getInfo(path) then return nil end
  return love.filesystem.load(path)
end)

local ok, err = pcall(function()
  local JobAssetIO = require("src.mods.JobAssetIO")
  local chunk = load("return " .. descriptorData, "=descriptor", "t", {})
  local descriptor = chunk and chunk()
  local io_, ioErr = JobAssetIO.open(descriptor, love.filesystem, modId)
  if not io_ then error(ioErr or "the import can't be opened", 0) end
  local Extract = require("mods.prism_importer.src.extract")
  local co = coroutine.create(function()
    return Extract.run({
      game = game,
      read = function(offset, length)
        local bytes, readErr = io_.imports:read(game, offset, length)
        if not bytes then error("import read failed: " .. tostring(readErr), 0) end
        return bytes
      end,
      cache = io_.cache,
    })
  end)
  local sent = 0
  while true do
    if control:pop() == "stop" then
      out:push({ kind = "stopped" })
      return
    end
    local okStep, value = coroutine.resume(co)
    if not okStep then error(value, 0) end
    if coroutine.status(co) == "dead" then
      out:push({ kind = "done" })
      return
    end
    if type(value) == "table" and value.total then
      local now = love.timer.getTime()
      if now - sent > 0.1 then
        sent = now
        out:push({ kind = "progress", done = value.done, total = value.total, status = tostring(value.status) })
      end
    end
  end
end)
if not ok then out:push({ kind = "failed", message = tostring(err) }) end
