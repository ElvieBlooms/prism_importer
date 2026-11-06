# Changelog

## 0.3.0

- Nothing imports by itself any more. A new **IMPORTER** page in PRISM (START or OPTION menu, in every game) lists each dump as IMPORT, QUEUED, a percentage, IMPORTED, FAILED or NO DUMP, with a bar for the one importing. A imports one, ALL imports every one waiting, and an imported one can be imported again.
- PRISM's list shows "2 TO IMPORT" while dumps are waiting.
- Imports run on a thread of their own (the new `compute` permission), so the game no longer slows down while they work, and they're much quicker: about a minute for all three on the test machine instead of most of an hour.
- `api.start`, `api.reimport` and `api.current`; `api.status` has `needed` and `queued` in place of `pending`.

## 0.2.0

- Black 2/White 2 trainer pictures are named (`front/leader_elesa`, `back/hero`), from the pokebw2 decompilation's lists.
- Black 2/White 2 overworld sheets are named after the people who use them (`hero`, `nurse`, `youngster`), read through the game's model table; the ones pokebw2 hasn't named yet go by their object code.
- Black 2/White 2's walking Pokémon move into `walking_pokemon`, by species, sex and form, as HeartGold/SoulSilver's are.
- Black 2/White 2 dumps are pulled out again once, for the new names.

## 0.1.0

First test release.

- Imports for Diamond/Pearl/Platinum, HeartGold/SoulSilver and Black 2/White 2 dumps (`.nds`, any region). Each is pulled out once, a little each frame, into the mod's cache.
- Packs: `battle_sprites` (with forms and female pictures; Black 2/White 2 animated), `trainer_pics`, `overworld`, and HeartGold/SoulSilver's `walking_pokemon`.
- `mod.exports` for other mods: `games`, `status`, `entries`, `entry`, `image` and `imageData`.
