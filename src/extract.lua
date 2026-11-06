-- Pulls the sprites out of one DS dump into the mod's cache, as PNGs and an
-- index. Runs as a coroutine: it yields between pictures (and inside long
-- animations) so the game keeps running while it works.
--
--   battle_sprites   Pokemon front and back, normal and shiny, female
--                    pictures and alternate forms (Gen 4: two 80x80 frames;
--                    Black 2/White 2: the idle animation, as the engine's
--                    Black/White importer makes it)
--   trainer_pics     trainer classes' pictures and the players' backs
--   overworld        overworld sprite sheets
--   walking_pokemon  HeartGold/SoulSilver's and Black 2/White 2's walking Pokemon
--
-- Ids follow the engine's gen5_bw pack: normal/025/front, shiny/025/back/female.
-- -Elvie
local Narc = require("src.import.gen5.Narc")
local Lz = require("src.import.gen5.Lz")
local Graphics = require("src.import.gen5.Graphics")
local Cells = require("src.import.gen5.Cells")
local Animation = require("src.import.gen5.Animation")
local Bw = require("src.import.gen5.BwImport")
local Rom = require("mods.prism_importer.src.rom")
local Pictures = require("mods.prism_importer.src.gen4.pictures")
local Btx = require("mods.prism_importer.src.gen4.btx")
local Names = require("mods.prism_importer.src.gen4.names")
local Bw2Names = require("mods.prism_importer.src.gen5.names")

local Extract = { VERSION = "1.1.0", FRAME = 80 }

Extract.GAMES = {
  dppt = { name = "Diamond, Pearl or Platinum",
    codes = { ADA = { "dp", "Diamond" }, APA = { "dp", "Pearl" }, CPU = { "pt", "Platinum" } } },
  hgss = { name = "HeartGold or SoulSilver",
    codes = { IPK = { "hgss", "HeartGold" }, IPG = { "hgss", "SoulSilver" } } },
  bw2 = { name = "Black 2 or White 2",
    codes = { IRE = { "bw2", "Black 2" }, IRD = { "bw2", "White 2" } } },
}

Extract.PATHS = {
  dp = { pokemon = "/poketool/pokegra/pokegra.narc", forms = "/poketool/pokegra/otherpoke.narc",
    trainers = "/poketool/trgra/trfgra.narc", backs = "/poketool/trgra/trbgra.narc",
    stride = 2, graphics = 0, palette = 1, overworld = "/data/mmodel/mmodel.narc" },
  pt = { pokemon = "/poketool/pokegra/pl_pokegra.narc", forms = "/poketool/pokegra/pl_otherpoke.narc",
    trainers = "/poketool/trgra/trfgra.narc", backs = "/poketool/trgra/trbgra.narc",
    stride = 5, graphics = 4, palette = 1, overworld = "/data/mmodel/mmodel.narc" },
  hgss = { pokemon = "/a/0/0/4", forms = "/a/1/1/4", trainers = "/a/0/5/8", backs = "/a/0/0/6",
    stride = 5, graphics = 4, palette = 1, overworld = "/a/0/8/1", walking = "tsure_poke" },
  -- Black 2/White 2: Pokemon (20 members each; forms from slot 685 on, as
  -- the personal data's form sprite start says), trainers and backs (8
  -- members each), overworld textures and the model table that names them,
  -- the walking Pokemon's table, personal data
  bw2 = { pokemon = "/a/0/0/4", trainers = "/a/0/7/1", backs = "/a/0/7/2", overworld = "/a/0/4/8",
    models = "/a/0/4/7", walking = "/a/2/0/8", personal = "/a/0/1/6", formBase = 685, count = 649 },
}

-- which family a dump is, from its game code
function Extract.identify(game, read)
  local ok, rom = pcall(Rom.open, read)
  if not ok then return nil, tostring(rom) end
  local spec = Extract.GAMES[game] and Extract.GAMES[game].codes[rom.code:sub(1, 3)]
  if not spec then
    return nil, ("this is %s (%s), not %s"):format(rom.title, rom.code, Extract.GAMES[game].name)
  end
  return { family = spec[1], name = "Pokemon " .. spec[2] .. " (" .. rom.code .. ")", code = rom.code }, rom
end

local function dex3(n) return ("%03d"):format(n) end

local function png(image)
  local encoded = image:encode("png")
  local bytes = encoded:getString()
  if encoded.release then encoded:release() end
  image:release()
  return bytes
end

-- a plain-data table as Lua source
local function serialize(value, indent)
  indent = indent or ""
  local t = type(value)
  if t == "string" then return ("%q"):format(value) end
  if t ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local inner = indent .. "  "
  local out = { "{" }
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. k .. "]") or ("[%q]"):format(k)
    out[#out + 1] = inner .. key .. " = " .. serialize(value[k], inner) .. ","
  end
  out[#out + 1] = indent .. "}"
  return table.concat(out, "\n")
end
Extract.serialize = serialize

-- Gen 4 form palettes: the form's own pair, or its species' first
function Extract.formPalette(family, name)
  local species, form = name:match("^([^/]+)/([^/]+)")
  local count = Names.FORM_COUNTS[family]
  local limit = ({ dp = 74, pt = 94, hgss = 98 })[family]
  local own, first, single
  for i = 1, limit do
    local s, f, side = Names.FORM_PALETTES[i]:match("^([^/]+)/([^/]+)/?(%a*)$")
    if s == species then
      if side == "" then
        if f == form then single = count + i - 1 end
      else
        if f == form and side == "front" then own = count + i - 1 end
        if not first and side == "front" then first = count + i - 1 end
      end
    end
  end
  if single then return single, nil end
  local normal = own or first
  return normal, normal and normal + 1
end

function Extract.formId(name, palette)
  local species, form, side = name:match("^([^/]+)/([^/]+)/(%a+)$")
  if not species then
    local s, f = name:match("^([^/]+)/([^/]+)$")
    return palette .. "/" .. s .. "/" .. f
  end
  return ("%s/%s/%s/form/%s"):format(palette, dex3(Names.SPECIES[species]), side, form)
end

-- ctx = { game, read, cache, budget }. Returns the index it wrote.
function Extract.run(ctx)
  local source, rom = Extract.identify(ctx.game, ctx.read)
  assert(source, rom)
  local family = source.family
  local paths = Extract.PATHS[family]
  local root = ctx.game .. "/"
  local packs = {}
  local done, total = 0, 1
  local function step(status)
    done = done + 1
    coroutine.yield({ done = done, total = total, status = status })
  end
  local function entry(pack, id, bytes, meta)
    local file = root .. pack .. "/" .. id .. ".png"
    local ok, err = ctx.cache:write(file, bytes)
    assert(ok, err)
    meta.file, meta.size = file, #bytes
    packs[pack] = packs[pack] or {}
    packs[pack][id] = meta
  end
  local function alias(pack, id, from)
    local copy = {}
    for k, v in pairs(packs[pack][from]) do copy[k] = v end
    packs[pack][id] = copy
  end
  local function archive(path) return Narc.open(rom.file(path)) end

  if family == "bw2" then
    Extract.gen5(ctx, rom, paths, entry, alias, packs, step, function(n) total = n end)
  else
    Extract.gen4(ctx, rom, family, paths, archive, entry, alias, packs, step, function(n) total = total + n end)
  end

  local index = { version = Extract.VERSION, source = source, packs = {} }
  for pack, entries in pairs(packs) do index.packs[pack] = entries end
  local ok, err = ctx.cache:write(root .. "index.lua", "return " .. serialize(index) .. "\n")
  assert(ok, err)
  return index
end

---------------------------------------------------------------- Gen 4

function Extract.gen4(ctx, rom, family, paths, archive, entry, alias, packs, step, add)
  local pokemon, forms = archive(paths.pokemon), archive(paths.forms)
  local trainers, backs = archive(paths.trainers), archive(paths.backs)
  local overworld = archive(paths.overworld)
  local trainerCount = math.floor(trainers.count / paths.stride)
  local backCount = math.floor(backs.count / paths.stride)
  add(493 * 4 + Names.FORM_COUNTS[family] + trainerCount + backCount + overworld.count)

  local function picture(pack, id, graphics, normal, shiny)
    local pic = Pictures.decode(graphics)
    if not pic then return false end
    local frames = Pictures.frames(pic, Extract.FRAME)
    for _, pal in ipairs({ { "normal", normal }, { "shiny", shiny } }) do
      if pal[2] then
        local image = Pictures.image(pic, Pictures.palette(pal[2]), Extract.FRAME, frames)
        local w, h = image:getDimensions()
        entry(pack, (id:gsub("^PAL", pal[1])), png(image), { width = w, height = h, frames = frames,
          sprite = { width = Extract.FRAME, height = h, columns = frames, frames = frames } })
      end
    end
    return true
  end

  for dex = 1, 493 do
    local m = dex * 6
    for _, side in ipairs({ "front", "back" }) do
      for _, female in ipairs({ false, true }) do
        local member = (side == "back" and 0 or 2) + (female and 0 or 1)
        local id = ("PAL/%s/%s%s"):format(dex3(dex), side, female and "/female" or "")
        picture("battle_sprites", id, pokemon.member(m + member), pokemon.member(m + 4), pokemon.member(m + 5))
        step(("Pokemon %03d"):format(dex))
      end
    end
  end
  -- a species with one picture uses it for both
  for dex = 1, 493 do
    for _, side in ipairs({ "front", "back" }) do
      for _, p in ipairs({ "normal", "shiny" }) do
        local male = ("%s/%s/%s"):format(p, dex3(dex), side)
        local female = male .. "/female"
        local have = packs.battle_sprites or {}
        if have[male] and not have[female] then alias("battle_sprites", female, male)
        elseif have[female] and not have[male] then alias("battle_sprites", male, female) end
      end
    end
  end
  for i = 1, Names.FORM_COUNTS[family] do
    local name = Names.FORMS[i]
    local normal, shiny = Extract.formPalette(family, name)
    if normal then
      picture("battle_sprites", Extract.formId(name, "PAL"), forms.member(i - 1),
        forms.member(normal), shiny and forms.member(shiny))
    end
    step("Form " .. name)
  end

  local classes = Names.TRAINERS[family]
  local function trainer(id, arc, i)
    local b = i * paths.stride
    picture("trainer_pics", "PAL/" .. id, arc.member(b + paths.graphics), arc.member(b + paths.palette))
  end
  for i = 0, trainerCount - 1 do
    trainer("front/" .. (classes[i + 1] or ("%03d"):format(i)), trainers, i)
    step("Trainer " .. i)
  end
  for i = 0, backCount - 1 do
    trainer(("back/%02d"):format(i), backs, i)
    step("Trainer back " .. i)
  end
  if packs.trainer_pics then
    local renamed = {}
    for id, v in pairs(packs.trainer_pics) do renamed[(id:gsub("^normal/", ""))] = v end
    packs.trainer_pics = renamed
  end

  local walking, seen = {}, {}
  for i = 0, overworld.count - 1 do
    local data = overworld.member(i)
    if data:sub(1, 4) == "BTX0" then
      local tex = Btx.parse(data)
      local frames, model = Btx.frames(tex)
      if #frames > 0 and #tex.palettes > 0 then
        if paths.walking and model == paths.walking then
          walking[#walking + 1] = { tex = tex, frames = frames }
        else
          local id = (model:lower():gsub("[^%l%d_%-]", "_"))
          if seen[id] then id = id .. "_" .. i end
          seen[id] = true
          Extract.sheet(entry, "overworld", id, tex, frames, i)
        end
      end
    end
    step("Overworld " .. i)
  end

  if #walking > 0 then
    add(#walking)
    local count = {}
    for k, w in ipairs(walking) do
      local id, plain
      local spec = k > Names.FOLLOWERS_FIRST and Names.FOLLOWERS[k - Names.FOLLOWERS_FIRST]
      if spec then
        local dex, variant = spec:match("^(%d+):?(.*)$")
        dex = tonumber(dex)
        if variant == "" then id = dex3(dex)
        elseif variant == "f" and dex ~= 201 then id = dex3(dex) .. "/female"
        else id = dex3(dex) .. "/form/" .. variant end
        count[dex] = (count[dex] or 0) + 1
        if variant ~= "" and variant ~= "f" and count[dex] == 1 then plain = dex3(dex) end
      else
        id = ("extra/%d"):format(k)
      end
      local fw, fh = w.frames[1].width, w.frames[1].height
      for p, pal in ipairs(w.tex.palettes) do
        local palette = p == 1 and "normal" or p == 2 and "shiny" or ("alt" .. (p - 1))
        local image = love.image.newImageData(fw * #w.frames, fh)
        for f, t in ipairs(w.frames) do Btx.draw(w.tex, t, pal, image, (f - 1) * fw, 0) end
        local width, height = image:getDimensions()
        entry("walking_pokemon", palette .. "/" .. id, png(image), { width = width, height = height,
          frames = #w.frames, sprite = { width = fw, height = fh, columns = #w.frames, frames = #w.frames } })
        if plain then alias("walking_pokemon", palette .. "/" .. plain, palette .. "/" .. id) end
      end
      step("Walking Pokemon " .. id)
    end
  end
end

-- an overworld sheet: frames left to right, 16 to a row; one entry per palette
function Extract.sheet(entry, pack, id, tex, frames, member)
  local fw, fh = frames[1].width, frames[1].height
  local columns = math.min(16, #frames)
  local rows = math.ceil(#frames / columns)
  for p, pal in ipairs(tex.palettes) do
    local image = love.image.newImageData(fw * columns, fh * rows)
    for f, t in ipairs(frames) do
      if t.width == fw and t.height == fh then
        Btx.draw(tex, t, pal, image, (f - 1) % columns * fw, math.floor((f - 1) / columns) * fh)
      end
    end
    local w, h = image:getDimensions()
    entry(pack, p == 1 and id or (id .. "/alt" .. (p - 1)), png(image), { width = w, height = h,
      frames = #frames, sprite = { width = fw, height = fh, columns = columns, frames = #frames, member = member } })
  end
end

---------------------------------------------------------------- Black 2 / White 2

-- one animated picture from a Gen 5 member set, as the engine's
-- BwImport.readPokemon reads a Pokemon's (without its dex limit)
local function sprite(member, first, graphics, normal, shiny)
  local function m(i) return Lz.decode(member(i)) end
  local s = { graphics = Graphics.parseGraphics(m(graphics)), cells = Cells.parse(m(first)),
    nanr = assert(Animation.nanr(m(first + 1))), nmcr = assert(Animation.nmcr(m(first + 2))),
    nmar = assert(Animation.nmar(m(first + 3))), normal = Graphics.parsePalette(m(normal)),
    shiny = shiny and Graphics.parsePalette(m(shiny)) or nil }
  s.map, s.animation = Animation.idle(s.nmar)
  assert(s.animation ~= nil, "missing idle animation")
  return s
end

-- one still pose (tick 0), for an animation the engine's exporter won't take
-- (an introduction longer than its 240-tick bound)
local function still(s)
  local Composer = require("src.import.gen5.Composer")
  local pixels, width, _, bounds = Composer.renderIndexed(s.graphics, s.normal, s.cells, s.nanr, s.nmcr, s.map, 0)
  local visible = {}
  local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
  for offset, color in pairs(pixels) do
    local x = (offset - 1) % width + bounds.min_x
    local y = math.floor((offset - 1) / width) + bounds.min_y
    visible[#visible + 1] = { x = x, y = y, color = color }
    minx, miny, maxx, maxy = math.min(minx, x), math.min(miny, y), math.max(maxx, x + 1), math.max(maxy, y + 1)
  end
  assert(minx < maxx, "no visible pixels")
  return { frames = { visible }, durations = { 1 }, width = maxx - minx, height = maxy - miny,
    min_x = minx, min_y = miny, loopStartFrame = 0, ticks = 1, cycleCapped = false }
end

local function animated(entry, pack, id, s, palettes)
  local ok, poses = pcall(Bw.poses, s, function(d, n) if d % 16 == 0 then coroutine.yield() end end)
  if not ok then poses = still(s) end
  for _, p in ipairs(palettes) do
    if s[p[2]] then
      local image, meta = Bw.image(poses, s[p[2]])
      local w, h = image:getDimensions()
      entry(pack, (id:gsub("^PAL", p[1])), png(image), { width = w, height = h, frames = #poses.frames, sprite = meta })
    end
  end
end

function Extract.gen5(ctx, rom, paths, entry, alias, packs, step, setTotal)
  local pokemon = Narc.open(rom.file(paths.pokemon))
  local trainers = Narc.open(rom.file(paths.trainers))
  local backs = Narc.open(rom.file(paths.backs))
  local overworld = Narc.open(rom.file(paths.overworld))
  local personal = Narc.open(rom.file(paths.personal))
  local forms = {}
  for dex = 1, paths.count do
    local p = personal.member(dex)
    if #p >= 0x21 then
      local start, count = Rom.u16(p, 0x1E), p:byte(0x21)
      -- Arceus' and Genesect's forms are palette changes, not pictures
      if count > 1 and not (start == 0 and dex ~= 201) then forms[#forms + 1] = { dex = dex, start = start, count = count } end
    end
  end
  local formTotal = 0
  for _, f in ipairs(forms) do formTotal = formTotal + (f.count - 1) * 2 end
  setTotal(paths.count * 4 + formTotal + math.floor(trainers.count / 8) + math.floor(backs.count / 8) + overworld.count)
  local both = { { "normal", "normal" }, { "shiny", "shiny" } }

  local function pokemonAt(slot, dex, side, female, formId)
    local base = slot * 20
    local graphicsAt = side == "front" and 2 or 11
    if female then
      if #pokemon.member(base + graphicsAt + 1) == 0 then return false end
      graphicsAt = graphicsAt + 1
    end
    if #pokemon.member(base + graphicsAt) == 0 then return false end
    local first = side == "front" and 4 or 13
    local ok, s = pcall(sprite, function(i) return pokemon.member(base + i) end, first, graphicsAt, 18, 19)
    if not ok then return false end
    local id = ("PAL/%s/%s%s%s"):format(dex3(dex), side, formId and ("/form/" .. formId) or "", female and "/female" or "")
    return (pcall(animated, entry, "battle_sprites", id, s, both))
  end

  for dex = 1, paths.count do
    for _, side in ipairs({ "front", "back" }) do
      for _, female in ipairs({ false, true }) do
        pokemonAt(dex, dex, side, female)
        step(("Pokemon %03d"):format(dex))
      end
      for _, p in ipairs({ "normal", "shiny" }) do
        local male = ("%s/%s/%s"):format(p, dex3(dex), side)
        local have = packs.battle_sprites or {}
        if have[male] and not have[male .. "/female"] then alias("battle_sprites", male .. "/female", male) end
      end
    end
  end
  for _, f in ipairs(forms) do
    for form = 1, f.count - 1 do
      for _, side in ipairs({ "front", "back" }) do
        pokemonAt(paths.formBase + f.start + form - 1, f.dex, side, false, tostring(form))
        step(("Pokemon %03d form %d"):format(f.dex, form))
      end
    end
  end

  local function person(arc, i, id)
    local b = i * 8
    local ok, s = pcall(sprite, function(k) return arc.member(b + k) end, 2, 1, 7)
    if ok then pcall(animated, entry, "trainer_pics", "PAL/" .. id, s, { { "", "normal" } }) end
  end
  -- named as pokebw2's lists name them; any past the lists by number
  for i = 0, math.floor(trainers.count / 8) - 1 do
    person(trainers, i, "front/" .. (Bw2Names.FRONTS[i + 1] or ("%03d"):format(i)))
    step("Trainer " .. i)
  end
  for i = 0, math.floor(backs.count / 8) - 1 do
    person(backs, i, "back/" .. (Bw2Names.BACKS[i + 1] or ("%02d"):format(i)))
    step("Trainer back " .. i)
  end
  if packs.trainer_pics then
    local renamed = {}
    for id, v in pairs(packs.trainer_pics) do renamed[(id:gsub("^/", ""))] = v end
    packs.trainer_pics = renamed
  end

  local owners = Extract.bw2Owners(rom, paths)
  local walkingSeen = {}
  for i = 0, overworld.count - 1 do
    local data = overworld.member(i)
    if data:sub(1, 4) == "BTX0" then
      local ok, tex = pcall(Btx.parse, data)
      if ok then
        local frames = Btx.frames(tex)
        if #frames > 0 and #tex.palettes > 0 then
          local list = owners[i] or { { id = ("member_%03d"):format(i) } }
          local first = { overworld = nil, walking_pokemon = nil }
          for _, owner in ipairs(list) do
            if owner.walking then
              if not walkingSeen[owner.id] then
                walkingSeen[owner.id] = true
                if first.walking_pokemon then
                  for _, palette in ipairs({ "normal", "shiny" }) do
                    if packs.walking_pokemon[palette .. "/" .. first.walking_pokemon] then
                      alias("walking_pokemon", palette .. "/" .. owner.id, palette .. "/" .. first.walking_pokemon)
                    end
                  end
                else
                  Extract.walkingSheet(entry, owner.id, tex, frames, i)
                  first.walking_pokemon = owner.id
                end
              end
            elseif not (packs.overworld and packs.overworld[owner.id]) then
              if first.overworld then
                alias("overworld", owner.id, first.overworld)
              else
                Extract.sheet(entry, "overworld", owner.id, tex, frames, i)
                first.overworld = owner.id
              end
            end
          end
        end
      end
    end
    step("Overworld " .. i)
  end
end

-- graphics member -> { { id, walking } } from the model table (a/0/4/7: a
-- count, then 28-byte records of object code, type, ..., graphics member at
-- 16) and the walking Pokemon's table (a/2/0/8: species, sex, form, object
-- code). Sprites are type 1. Layouts follow pokebw2's notes. -Elvie
function Extract.bw2Owners(rom, paths)
  local walkingByCode = {}
  local okW, walking = pcall(function() return Narc.open(rom.file(paths.walking)).member(0) end)
  if okW then
    for o = 0, #walking - 8, 8 do
      local species, sex, form, code = Rom.u16(walking, o), Rom.u16(walking, o + 2), Rom.u16(walking, o + 4), Rom.u16(walking, o + 6)
      local id = dex3(species)
      if form > 0 then id = id .. "/form/" .. form
      elseif sex == 1 then id = id .. "/female" end
      walkingByCode[code] = walkingByCode[code] or id
    end
  end
  local owners = {}
  local okT, models = pcall(function() return Narc.open(rom.file(paths.models)).member(0) end)
  if not okT or #models < 4 then return owners end
  local count = Rom.u32(models, 0)
  for r = 0, count - 1 do
    local o = 4 + r * 28
    if o + 28 > #models then break end
    local code, kind, member = Rom.u16(models, o), models:byte(o + 3), Rom.u16(models, o + 16)
    if kind == 1 then
      local owner
      if code >= 0x1000 and code < 0x2000 then
        owner = walkingByCode[code] and { id = walkingByCode[code], walking = true }
      end
      owner = owner or { id = Bw2Names.PEOPLE[code] or ("%03d"):format(code) }
      owners[member] = owners[member] or {}
      table.insert(owners[member], owner)
    end
  end
  return owners
end

-- a walking Pokemon: its frames in one row, normal then shiny palettes
function Extract.walkingSheet(entry, id, tex, frames, member)
  local fw, fh = frames[1].width, frames[1].height
  for p, pal in ipairs(tex.palettes) do
    local palette = p == 1 and "normal" or p == 2 and "shiny" or ("alt" .. (p - 1))
    local image = love.image.newImageData(fw * #frames, fh)
    for f, t in ipairs(frames) do
      if t.width == fw and t.height == fh then Btx.draw(tex, t, pal, image, (f - 1) * fw, 0) end
    end
    local width, height = image:getDimensions()
    entry("walking_pokemon", palette .. "/" .. id, png(image), { width = width, height = height,
      frames = #frames, sprite = { width = fw, height = fh, columns = #frames, frames = #frames, member = member } })
  end
end

return Extract
