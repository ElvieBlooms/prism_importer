#!/usr/bin/env python3
"""Writes src/gen5/names.lua from a checkout of pokebw2 (fuddlesworth/pokebw2):
the trainer sprites' and back sprites' names in archive order, and the people's
object codes. Only names are taken, nothing else from the project. -Elvie

usage: tools/bw2_names.py <pokebw2 checkout> > src/gen5/names.lua"""
import subprocess, sys
from pathlib import Path


def constants(path, prefix):
    out, value = {}, 0
    for line in path.read_text().splitlines():
        line = line.split("#")[0].strip()
        if not line:
            continue
        if "=" in line:
            name, number = (s.strip() for s in line.split("="))
            value = int(number, 0)
        else:
            name = line
        out[value] = name.removeprefix(prefix).lower()
        value += 1
    return out


def lua_list(names):
    items = [f'"{names[i]}"' for i in sorted(names)]
    lines, line = [], "   "
    for item in items:
        if len(line) + len(item) + 2 > 100:
            lines.append(line)
            line = "   "
        line += " " + item + ","
    lines.append(line)
    return "\n".join(lines)


root = Path(sys.argv[1])
gen = root / "generated"
fronts = constants(gen / "trainer_sprites.txt", "TRAINER_SPRITE_")
backs = constants(gen / "trainer_back_sprites.txt", "TRAINER_BACK_SPRITE_")
codes = constants(gen / "obj_codes.txt", "OBJ_CODE_")
people = {k: v for k, v in codes.items() if k < 0x1000 and not v.isdigit()}
commit = subprocess.run(["git", "-C", str(root), "log", "-1", "--format=%h"], capture_output=True, text=True).stdout.strip()
assert sorted(fronts) == list(range(len(fronts))) and sorted(backs) == list(range(len(backs)))

print(f"""-- Black 2/White 2 names, from pokebw2's generated lists (fuddlesworth/pokebw2,
-- commit {commit}), written by tools/bw2_names.py. Names only. -Elvie
local Names = {{}}

-- the trainer sprites (a/0/7/1) and back sprites (a/0/7/2), in archive order
Names.FRONTS = {{
{lua_list({i + 1: fronts[i] for i in fronts})}
}}
Names.BACKS = {{
{lua_list({i + 1: backs[i] for i in backs})}
}}

-- the people's and objects' object codes that have names; the rest are numbered
Names.PEOPLE = {{""")
for k in sorted(people):
    print(f'  [{k}] = "{people[k]}",')
print("""}

return Names""")
