"""Export the Super Game Boy colour data of pokered (Red).

Usage (from pokered-godot):  python tools/export_sgb.py

Writes assets/data/sgb.json:
  palettes      PAL_* order (data/sgb/sgb_palettes.asm), 4 x [r, g, b] (0-255)
  pal_names     PAL_* name -> index
  mon_palettes  dex number -> palette index (data/pokemon/palettes.asm, 0 = MISSINGNO)
  pal_packets   PalPacket_* name -> 4 palette indices
  blk_packets   BlkPacket_* name -> [[regions, inside, line, outside, x1, y1, x2, y2], ...]
  map_ids       map name -> id, with num_city_maps / first_indoor_map (constants/map_constants.asm)
and assets/gb/sgb_border.png: the 256x224 red SGB border rendered from
gfx/sgb/red_border.{2bpp,tilemap} and the BorderPalettes (colour 0 transparent).

PH-INTENT: the Godot palette commands (scripts/gb/sgb.gd) interpret these packets with
the semantics of engine/gfx/palettes.asm; no colour is chosen by hand.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
MASTER = (PROJECT.parent / "pokered-master").resolve()
OUT_JSON = PROJECT / "assets" / "data" / "sgb.json"
OUT_BORDER = PROJECT / "assets" / "gb" / "sgb_border.png"


def rgb5(v: int) -> int:
    return round(v * 255 / 31)


def red_only(text: str) -> str:
    """Drop IF DEF(_BLUE) blocks and unwrap IF DEF(_RED) blocks."""
    out = []
    skip = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("IF DEF(_BLUE)"):
            skip = True
            continue
        if s.startswith("IF DEF(_RED)"):
            continue
        if s.startswith("ENDC"):
            skip = False
            continue
        if not skip:
            out.append(line)
    return "\n".join(out)


def parse_constants() -> dict[str, int]:
    names: dict[str, int] = {}
    value = 0
    for raw in (MASTER / "constants" / "palette_constants.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"const_def\s*(\d+)?", line)
        if m:
            value = int(m.group(1) or 0)
            continue
        m = re.match(r"const\s+([A-Z0-9_]+)", line)
        if m:
            names[m.group(1)] = value
            value += 1
    return names


def parse_palettes() -> list[list[list[int]]]:
    text = red_only((MASTER / "data" / "sgb" / "sgb_palettes.asm").read_text(encoding="utf-8"))
    pals = []
    for raw in text.splitlines():
        line = raw.split(";")[0].strip()
        if line.startswith("RGB"):
            nums = [int(x) for x in re.findall(r"\d+", line)]
            pals.append([[rgb5(nums[i]), rgb5(nums[i + 1]), rgb5(nums[i + 2])] for i in range(0, 12, 3)])
    return pals


def parse_mon_palettes(names: dict[str, int]) -> list[int]:
    out = []
    for raw in (MASTER / "data" / "pokemon" / "palettes.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*db\s+(PAL_[A-Z0-9_]+)", raw)
        if m:
            out.append(names[m.group(1)])
    return out


def parse_packets(names: dict[str, int]) -> tuple[dict, dict]:
    pal_packets: dict[str, list[int]] = {}
    blk_packets: dict[str, list] = {}
    current = None
    for raw in (MASTER / "data" / "sgb" / "sgb_packets.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"^(BlkPacket_[A-Za-z0-9_]+):", line)
        if m:
            current = m.group(1)
            blk_packets[current] = []
            continue
        m = re.match(r"^(PalPacket_[A-Za-z0-9_]+):\s*PAL_SET\s+(.*)$", line)
        if m:
            pal_packets[m.group(1)] = [names[t.strip()] if t.strip().startswith("PAL_") else int(t) for t in m.group(2).split(",")]
            continue
        m = re.match(r"^ATTR_BLK_DATA\s+%([01]{3}),\s*(\d+),(\d+),(\d+),\s*(\d+),(\d+),\s*(\d+),(\d+)", line)
        if m and current:
            regions = int(m.group(1), 2)
            blk_packets[current].append([regions] + [int(m.group(i)) for i in range(2, 9)])
    return pal_packets, blk_packets


def parse_map_ids() -> dict:
    ids: dict[str, int] = {}
    num_city = None
    first_indoor = None
    for raw in (MASTER / "constants" / "map_constants.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"map_const\s+([A-Z0-9_]+),", line)
        if m:
            ids[m.group(1)] = len(ids)
            continue
        if line.startswith("DEF NUM_CITY_MAPS"):
            num_city = len(ids)
        elif line.startswith("DEF FIRST_INDOOR_MAP"):
            first_indoor = len(ids)
    return {"ids": ids, "num_city_maps": num_city, "first_indoor_map": first_indoor}


def render_border() -> None:
    tilemap = (MASTER / "gfx" / "sgb" / "red_border.tilemap").read_bytes()
    tiles = (MASTER / "gfx" / "sgb" / "red_border.2bpp").read_bytes()
    text = red_only((MASTER / "data" / "sgb" / "sgb_border.asm").read_text(encoding="utf-8"))
    pals = []
    cur: list = []
    for raw in text.splitlines():
        line = raw.split(";")[0].strip()
        if line.startswith("RGB"):
            r, g, b = [int(x) for x in re.findall(r"\d+", line)]
            cur.append((rgb5(r), rgb5(g), rgb5(b)))
            if len(cur) == 4:
                pals.append(cur)
                cur = []
    img = Image.new("RGBA", (256, 224), (0, 0, 0, 0))
    px = img.load()
    for i in range(32 * 28):
        entry = tilemap[i * 2] | (tilemap[i * 2 + 1] << 8)
        tile = entry & 0x3FF
        pal = ((entry >> 10) & 7) - 4
        xflip = (entry >> 14) & 1
        yflip = (entry >> 15) & 1
        tx = (i % 32) * 8
        ty = (i // 32) * 8
        if pal < 0 or pal >= len(pals):
            continue
        base = tile * 16
        for y in range(8):
            lo = tiles[base + y * 2]
            hi = tiles[base + y * 2 + 1]
            for x in range(8):
                bit = 7 - x
                c = ((lo >> bit) & 1) | (((hi >> bit) & 1) << 1)
                if c == 0:
                    continue
                dx = 7 - x if xflip else x
                dy = 7 - y if yflip else y
                px[tx + dx, ty + dy] = pals[pal][c] + (255,)
    # the game screen area is always transparent
    for y in range(40, 184):
        for x in range(48, 208):
            px[x, y] = (0, 0, 0, 0)
    img.save(OUT_BORDER)


def main() -> None:
    names = parse_constants()
    palettes = parse_palettes()
    pal_names = {k: v for k, v in names.items() if k.startswith("PAL_") and v < len(palettes)}
    pal_packets, blk_packets = parse_packets(names)
    data = {
        "palettes": palettes,
        "pal_names": pal_names,
        "mon_palettes": parse_mon_palettes(names),
        "pal_packets": pal_packets,
        "blk_packets": blk_packets,
        "map_ids": parse_map_ids(),
    }
    OUT_JSON.write_text(json.dumps(data), encoding="utf-8")
    render_border()
    print(f"sgb: {len(palettes)} palettes, {len(data['mon_palettes'])} mon palettes, {len(pal_packets)} pal packets, {len(blk_packets)} blk packets")
    print("PAL_PALLET", palettes[pal_names["PAL_PALLET"]], "PAL_REDMON", palettes[pal_names["PAL_REDMON"]])
    print("Battle blk", blk_packets["BlkPacket_Battle"])
    print("map ids", {k: data["map_ids"]["ids"][k] for k in ("PALLET_TOWN", "ROUTE_1", "REDS_HOUSE_1F", "OAKS_LAB")}, data["map_ids"]["num_city_maps"], data["map_ids"]["first_indoor_map"])


if __name__ == "__main__":
    main()
