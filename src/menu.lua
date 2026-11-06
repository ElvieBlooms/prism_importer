-- The IMPORTER page: each dump with what it's doing, A to import it, and a
-- bar for the one importing now. Opened from PRISM in the START and OPTION
-- menus, in the Gen 3 games and the Game Boy games, like the visuals mods'
-- pages; PRISM's list shows "2 TO IMPORT" while dumps are waiting, so the
-- player knows to come here. Nothing imports until they ask. -Elvie
-- --------------------------------------------------

local menu = {}

local COLOUR = { 60, 160, 150 } -- teal -Elvie
local SHORT = { dppt = "DPPT", hgss = "HGSS", bw2 = "B2W2" }
local LONG = {
  dppt = "Diamond, Pearl or Platinum",
  hgss = "HeartGold or SoulSilver",
  bw2 = "Black 2 or White 2",
}

local function engine(name)
  local ok, m = pcall(require, name)
  return ok and m or nil
end

local function percent(st)
  local total, done = tonumber(st.total) or 0, tonumber(st.done) or 0
  if total <= 0 then return 0 end
  return math.floor(100 * math.min(done, total) / total)
end

-- what a dump's row says -Elvie
function menu.label(st)
  local s = st and st.state
  if s == "ready" then return "IMPORTED"
  elseif s == "needed" then return "IMPORT"
  elseif s == "queued" then return "QUEUED"
  elseif s == "running" then return percent(st) .. "%"
  elseif s == "failed" then return "FAILED"
  end
  return "NO DUMP"
end

-- PRISM's list value: what's going on, or how many are waiting -Elvie
function menu.value(api, games)
  local ok, all = pcall(api.status)
  if not (ok and type(all) == "table") then return "" end
  local waiting, ready, any = 0, 0, false
  for _, g in ipairs(games) do
    local st = all[g] or {}
    if st.state == "running" then return "IMPORTING " .. percent(st) .. "%" end
    if st.state == "needed" or st.state == "failed" then waiting = waiting + 1 end
    if st.state == "queued" then return "QUEUED" end
    if st.state == "ready" then ready = ready + 1 end
    if st.state and st.state ~= "absent" then any = true end
  end
  if waiting > 0 then return waiting .. " TO IMPORT" end
  if ready > 0 then return "READY" end
  return any and "" or "NO DUMPS"
end

-- the line over the bar -Elvie
function menu.progress(api, games)
  local okC, cur = pcall(api.current)
  if okC and type(cur) == "table" then
    return ("IMPORTING %s  %d / %d"):format(SHORT[cur.game] or cur.game, cur.done or 0, cur.total or 1), cur
  end
  local okS, all = pcall(api.status)
  all = okS and type(all) == "table" and all or {}
  local waiting, ready = 0, 0
  for _, g in ipairs(games) do
    local s = (all[g] or {}).state
    if s == "needed" or s == "failed" then waiting = waiting + 1 end
    if s == "ready" then ready = ready + 1 end
  end
  if waiting > 0 then return waiting == 1 and "1 DUMP TO IMPORT." or (waiting .. " DUMPS TO IMPORT.") end
  if ready > 0 then return "ALL IMPORTED." end
  return "NO DUMPS PICKED."
end

-- the selected row's lines under the rows -Elvie
function menu.about(api, game)
  local okS, all = pcall(api.status)
  local st = okS and type(all) == "table" and all[game] or {}
  if game == "all" then
    return { { text = "Imports every dump that's waiting," }, { text = "one after another." } }
  end
  local s = st.state
  local name = LONG[game] or game
  if s == "ready" then return { { text = name .. "." }, { text = "Imported. A redoes it." } } end
  if s == "needed" then return { { text = name .. "." }, { text = "Press A to import it." } } end
  if s == "queued" then return { { text = name .. "." }, { text = "Waiting its turn." } } end
  if s == "running" then return { { text = name .. "." }, { text = tostring(st.message or "Importing.") } } end
  if s == "failed" then
    return { { text = "Failed. A tries again.", red = true },
      { text = tostring(st.message or ""), red = true } }
  end
  return { { text = name .. "." }, { text = "Pick its dump in MODS first." } }
end

function menu.drawBar(x0, y, x1, h, pct)
  local c = COLOUR
  love.graphics.setColor(0.25, 0.25, 0.3, 1)
  love.graphics.rectangle("fill", x0, y, x1 - x0, h)
  love.graphics.setColor(0.93, 0.93, 0.9, 1)
  love.graphics.rectangle("fill", x0 + 1, y + 1, x1 - x0 - 2, h - 2)
  local w = math.floor((x1 - x0 - 2) * math.max(0, math.min(100, pct)) / 100)
  if w > 0 then
    love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, 1)
    love.graphics.rectangle("fill", x0 + 1, y + 1, w, h - 2)
    love.graphics.setColor(1, 1, 1, 0.45)
    love.graphics.rectangle("fill", x0 + 1, y + 1, w, 1)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- rows: one per dump, then IMPORT ALL -Elvie
function menu.rows(api, games)
  local okS, all = pcall(api.status)
  all = okS and type(all) == "table" and all or {}
  local out = {}
  local waiting = 0
  for _, g in ipairs(games) do
    local st = all[g] or {}
    if st.state == "needed" or st.state == "failed" then waiting = waiting + 1 end
    local startable = st.state == "needed" or st.state == "failed" or st.state == "ready"
    out[#out + 1] = { label = SHORT[g] or g, who = g, valueLabel = menu.label(st),
      action = startable and function() menu.begin(api, g, st.state == "ready") end or nil }
  end
  out[#out + 1] = { label = "ALL", who = "all", valueLabel = waiting > 0 and "IMPORT" or "-",
    action = waiting > 0 and function() menu.begin(api, nil) end or nil }
  return out
end

function menu.begin(api, game, again)
  if again and type(api.reimport) == "function" then return pcall(api.reimport, game) end
  return pcall(api.start, game)
end

-- The Gen 3 page, through the same screen code as the visuals mods'. -Elvie
local function gba(mod, api, games, liveGame)
  local BAR_X0, BAR_X1, BAR_Y, BAR_H = 16, 224, 128, 8
  local M = { layer = "prism_importer" }
  function M.title() return "IMPORTER" end
  function M.set() end
  function M.rows() return menu.rows(api, games) end
  function M.preview(who) return { lines = menu.about(api, who) } end
  function M.draw()
    local text, cur = menu.progress(api, games)
    local Window, FrlgFont = engine("src.ui.game3.window"), engine("src.ui.game3.frlg_font")
    if Window and FrlgFont then
      pcall(Window.printPx, text, BAR_X0, BAR_Y - 14, { colors = FrlgFont.COLOR.NORMAL })
    end
    menu.drawBar(BAR_X0, BAR_Y, BAR_X1, BAR_H, cur and percent(cur) or 0)
  end
  function M.credits() return {} end
  local screen = require("mods.prism_importer.src.screen").new(mod, M)
  local prism = require("mods.prism_importer.src.prism")
  local picker = prism.picker()
  local entry = { id = "prism_importer", label = "IMPORTER", short = "IMPORTER",
    about = "Sprites from your own DS games.",
    colour = COLOUR, order = 30,
    value = function() return menu.value(api, games) end,
    draw = function(area)
      if type(area) ~= "table" then return end
      local _, cur = menu.progress(api, games)
      local y = math.floor((area.y0 + area.y1) / 2) - 4
      menu.drawBar(area.x0 + 30, y, area.x1 - 10, 9, cur and percent(cur) or 0)
    end,
    open = function(g) screen.open(liveGame(g)) end,
  }
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local out = nextFn()
    if type(out) ~= "table" then return out end
    local StartMenu = package.loaded["src.ui.game3.start_menu"]
    if StartMenu and StartMenu._tutorial then return out end
    return prism.addStart(out, entry, picker, game)
  end)
  mod.hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    local out = nextFn()
    if type(out) ~= "table" then return out end
    return prism.addOption(out, entry, picker, game)
  end)
end

-- The Game Boy page: the game's own box and font, like PRISM there. -Elvie
local function gb(mod, api, games, liveGame)
  if not (mod.content and mod.content.screens and mod.ui and mod.ui.Font) then return end
  local Font = mod.ui.Font
  local pageId = mod.id .. "_page"
  mod.content.screens:register(pageId, {
    new = function(game)
      local self = { isOpaque = true, index = 1 }
      function self:update()
        local input = game.input
        local list = menu.rows(api, games)
        if self.index > #list then self.index = #list end
        if input:wasPressed("b") or input:wasPressed("start") then game.stack:pop() return end
        if input:wasPressed("down") then self.index = self.index % #list + 1 end
        if input:wasPressed("up") then self.index = (self.index - 2) % #list + 1 end
        if input:wasPressed("a") or input:wasPressed("right") then
          local row = list[self.index]
          if row and row.action then row.action() end
        end
      end
      function self:draw()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("IMPORTER", 8, 8)
        local list = menu.rows(api, games)
        for i, row in ipairs(list) do
          local y = 24 + (i - 1) * 12
          if i == self.index then
            local Theme = mod.ui.Theme
            if Theme and Theme.cursor and Font.drawCode then Font.drawCode(Theme.cursor, 8, y)
            else Font.draw(">", 8, y) end
          end
          Font.draw(row.label, 16, y)
          Font.draw(row.valueLabel, 64, y)
        end
        local picked = list[self.index]
        local lines = picked and menu.about(api, picked.who) or {}
        local n = 0
        for _, line in ipairs(lines) do
          local cur = ""
          for word in tostring(line.text):upper():gmatch("%S+") do
            if #cur > 0 and #cur + 1 + #word > 18 then
              if n < 4 then Font.draw(cur, 8, 80 + n * 8) end
              n = n + 1; cur = word
            else
              cur = #cur > 0 and (cur .. " " .. word) or word
            end
          end
          if #cur > 0 and n < 4 then Font.draw(cur, 8, 80 + n * 8); n = n + 1 end
        end
        local text, cur = menu.progress(api, games)
        if cur then text = ("%s %d%%"):format(SHORT[cur.game] or cur.game, percent(cur)) end
        Font.draw(tostring(text):sub(1, 18), 8, 116)
        menu.drawBar(8, 127, 152, 6, cur and percent(cur) or 0)
      end
      return self
    end,
  })
  local prism = require("mods.prism_importer.src.prism")
  local prismScreen = prism.registerGb(mod)
  local entry = { id = "prism_importer", label = "IMPORTER", short = "IMPORTER",
    about = "Sprites from your own DS games.", colour = COLOUR, order = 30,
    value = function() return menu.value(api, games) end,
    open = function(g) mod.ui.push(liveGame(g), pageId) end,
  }
  mod.hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    local got = nextFn(game, items)
    if type(got) ~= "table" then return got end
    return prism.addStartGb(mod, got, entry, liveGame(game), prismScreen)
  end)
  mod.hooks:wrap("ui.options.rows", function(nextFn, game, list)
    local got = nextFn(game, list)
    if type(got) ~= "table" then return got end
    return prism.addOptionGb(mod, got, entry, liveGame(game), prismScreen)
  end)
end

function menu.start(mod, api, games)
  if not (mod.hooks and type(mod.hooks.wrap) == "function") then return end
  local function liveGame(game)
    if type(game) == "table" then return game end
    local ok, g = pcall(function() return mod.game end)
    return ok and type(g) == "table" and g or nil
  end
  local GameVersion = engine("src.core.GameVersion")
  local gen
  if GameVersion and type(GameVersion.generation) == "function" then
    local ok, g = pcall(GameVersion.generation)
    gen = ok and tonumber(g) or nil
  end
  if gen == 1 or gen == 2 then return gb(mod, api, games, liveGame) end
  return gba(mod, api, games, liveGame)
end

return menu
