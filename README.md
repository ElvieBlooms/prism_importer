# Prism Importer

Sprites from your own Diamond, Pearl, Platinum, HeartGold, SoulSilver, Black 2 and White 2 dumps, for other gen1recomp mods to use. It doesn't change anything in the game on its own: it's a provider, like the engine's own Black/White importer. Nothing from the games ships with it.

## Setup

1. Install Prism Importer and turn it on.
2. In its imports, pick whichever dumps you have (`.nds`, any region):
   - **Diamond, Pearl or Platinum.** Platinum has the most: its extra forms, trainers and people.
   - **HeartGold or SoulSilver.** Adds the walking Pokémon.
   - **Black 2 or White 2.** NDSi-enhanced dumps work.
3. Start any game. The sprites are pulled out once, a little each frame while you play, and kept in the mod's cache. Replacing a dump pulls it out again.

## What comes out

| Pack | Diamond/Pearl/Platinum, HeartGold/SoulSilver | Black 2/White 2 |
| --- | --- | --- |
| `battle_sprites` | every Pokémon's front and back, normal and shiny, female pictures, alternate forms and eggs (80x80 frames) | every Pokémon's front and back, normal and shiny, female pictures and alternate forms, with their idle animation |
| `trainer_pics` | every trainer class by name (`front/leader_whitney`), and the players' backs (`back/00`...) | every trainer picture and back, animated, by name (`front/leader_elesa`, `back/hero`) |
| `overworld` | every overworld sheet by the game's own name (`hero`, `ookido`) | every overworld sheet by name where it has one (`hero`, `nurse`), otherwise by its object code (`080`) |
| `walking_pokemon` | HeartGold/SoulSilver's walking Pokémon (`normal/025`, `shiny/201/form/b`) | the walking Pokémon of the Entree Forest, Hidden Grottoes and Game Sync (`normal/025`, `normal/003/female`, `normal/201/form/5`) |

Battle sprite ids match the engine's Black/White pack: `normal/025/front`, `shiny/025/back/female`, and forms as `normal/386/front/form/attack` (Gen 4, by name) or `normal/386/front/form/1` (Black 2/White 2, by number).

## For mod authors

Add `"optional_dependencies": ["prism_importer"]`, then:

```lua
local importer = mod.find("prism_importer")
local api = importer and importer.exports
if api and api.apiVersion == 1 then
  local games = api.games()         -- { dppt = { name, family, packs = { battle_sprites = 4250, ... } }, ... }
  local image, entry = api.image("hgss", "battle_sprites", "normal/025/front")
  -- entry = { width, height, frames, sprite = { width, height, columns, frames, ... } }
end
```

- `api.status()` gives each dump's progress: `absent`, `pending`, `running`, `ready` or `failed`, with `done`, `total` and `message`.
- `api.entries(game, pack)` lists a pack.
- `api.imageData(game, pack, id)` returns a fresh ImageData.
- Games are `dppt`, `hgss` and `bw2`.
- Sheets run left to right in frames of `sprite.width` x `sprite.height`, wrapping at `sprite.columns`. Black 2/White 2 animations also carry `durations` (in 60ths of a second) and `loopStartFrame`, as the engine's Black/White pack does.

## Notes

- Black 2/White 2 pictures are put together with the engine's own Black/White importer code, so it needs gen1recomp 0.3.98 or newer.
- Arceus's types are colour changes in Black 2/White 2, so only its base picture is pulled out.
- A few Black 2/White 2 animations run longer than the engine's exporter allows; those come out as a single still frame (`frames = 1`).
- Pulling everything out takes a while the first time: roughly 10 to 15 minutes per Gen 4 game and longer for Black 2/White 2, spread over play so the game doesn't stutter. `api.status()` reports the progress.
- Trainer class, form and walking Pokémon names follow pret's pokediamond, pokeplatinum and pokeheartgold projects. Black 2/White 2's trainer and overworld names follow the pokebw2 decompilation's lists, and its walking Pokémon are read from the game's own table, by species, sex and form number. Some Black 2/White 2 people aren't named there yet, so they keep their object code's number.
- When the engine gets importers of its own for these games, Prism Importer can step aside.

## Credits

By Elvie. Decoding notes from pret's Gen 4 projects and the engine's AnimaEngine-based Black/White importer. Black 2/White 2 names and table layouts from [pokebw2](https://github.com/fuddlesworth/pokebw2) by fuddlesworth and its contributors (names only; `tools/bw2_names.py` writes them).
