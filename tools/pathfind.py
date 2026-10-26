"""Shortest walking path on an exported map, using the game's collision rule.
Usage: python tools/pathfind.py MAP x1 y1 x2 y2   -> prints a string of U/D/L/R steps"""
import json, sys
from collections import deque
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
maps = json.load(open(ROOT / "assets/data/maps.json"))
tilesets = json.load(open(ROOT / "assets/data/tilesets.json"))

def walkable(m, ts, x, y):
    if x < 0 or y < 0 or x >= m["width"] * 2 or y >= m["height"] * 2:
        return False
    bx, by = x // 2, y // 2
    block = ts["blocks"][m["blocks"][by * m["width"] + bx]]
    tx, ty = (x % 2) * 2, (y % 2) * 2 + 1
    return block[ty * 4 + tx] in ts["collision"]

def path(mid, sx, sy, tx, ty):
    m = maps[mid]; ts = tilesets[m["tileset"]]
    blocked = {(o["x"], o["y"]) for o in m["objects"]}
    q = deque([(sx, sy)]); prev = {(sx, sy): None}
    while q:
        x, y = q.popleft()
        if (x, y) == (tx, ty):
            break
        for d, dx, dy in (("U", 0, -1), ("D", 0, 1), ("L", -1, 0), ("R", 1, 0)):
            n = (x + dx, y + dy)
            if n in prev or not walkable(m, ts, *n) or (n in blocked and n != (tx, ty)):
                continue
            prev[n] = ((x, y), d); q.append(n)
    if (tx, ty) not in prev:
        return None
    out = []; cur = (tx, ty)
    while prev[cur]:
        cur, d = prev[cur]; out.append(d)
    return "".join(reversed(out))

if __name__ == "__main__":
    print(path(sys.argv[1], *map(int, sys.argv[2:6])))
