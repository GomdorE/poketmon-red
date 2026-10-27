"""Build the .2bpp / .1bpp graphics of ../pokered-master without make or a C compiler.

The disassembly only ships .png sources; tools/export_data.py reads the built files.
This follows the pokered Makefile: `rgbgfx --colors dmg $(RGBGFXFLAGS)` for every
INCBIN'd .2bpp / .1bpp, then the file-specific tools/gfx steps (tools/gfx.c, ported
below). Usage: python tools/build_pokered_gfx.py <path to rgbgfx.exe> (RGBDS 1.0.4).
"""
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
MASTER = (PROJECT.parent / "pokered-master").resolve()

# Makefile "Misc file-specific graphics rules"
COLUMNS = {
    "gfx/intro/blue_jigglypuff_1.2bpp", "gfx/intro/blue_jigglypuff_2.2bpp", "gfx/intro/blue_jigglypuff_3.2bpp",
    "gfx/intro/red_nidorino_1.2bpp", "gfx/intro/red_nidorino_2.2bpp", "gfx/intro/red_nidorino_3.2bpp",
    "gfx/intro/gengar.2bpp",
}


def gfx_options(rel: str) -> dict:
    o = {"trim": False, "interleave": False, "dedupe": False, "preserve": []}
    if rel in ("gfx/battle/move_anim_0.2bpp", "gfx/battle/move_anim_1.2bpp",
               "gfx/slots/red_slots_1.2bpp", "gfx/slots/blue_slots_1.2bpp"):
        o["trim"] = True
    if rel == "gfx/intro/gengar.2bpp":
        o["dedupe"] = True
        o["preserve"] = [0x19, 0x76]
    if rel == "gfx/credits/the_end.2bpp":
        o["interleave"] = True
    if rel.startswith("gfx/tilesets/") and rel.endswith(".2bpp"):
        o["trim"] = True
    if rel == "gfx/tilesets/reds_house.2bpp":
        o["preserve"] = [0x48]
    if rel == "gfx/trade/game_boy.2bpp":
        o["dedupe"] = True
    return o


# --- tools/gfx.c -------------------------------------------------------------------

def trim_whitespace(data: bytes, tile_size: int, preserved: list) -> bytes:
    size = len(data)
    i = size - tile_size
    while i > 0:
        if not any(data[i:i + tile_size]) and (i // tile_size) not in preserved:
            size = i
        else:
            break
        i -= tile_size
    return data[:size]


def interleave(data: bytes, tile_size: int, width: int) -> bytes:
    width_tiles = width // 8
    num_tiles = len(data) // tile_size
    out = bytearray(len(data))
    for i in range(num_tiles):
        row = i // width_tiles
        tile = i * 2 - (width_tiles * (row + 1) - 1 if row % 2 else width_tiles * row)
        out[tile * tile_size:(tile + 1) * tile_size] = data[i * tile_size:(i + 1) * tile_size]
    return bytes(out[:num_tiles * tile_size])


def remove_duplicates(data: bytes, tile_size: int, preserved: list) -> bytes:
    buf = bytearray(data[:len(data) & ~(tile_size - 1)])
    size = len(buf)
    num_tiles = 0

    def exists(j: int) -> bool:
        tile = buf[j:j + tile_size]
        return any(buf[k * tile_size:(k + 1) * tile_size] == tile for k in range(num_tiles))

    i = j = d = 0
    while i < size and j < size:
        while j < size and exists(j):
            if (j // tile_size - d) in preserved:
                break
            for p in range(len(preserved)):
                if preserved[p] >= j // tile_size - d:
                    preserved[p] -= 1
            j += tile_size
            d += 1
        if j >= size:
            break
        if j > i:
            buf[i:i + tile_size] = buf[j:j + tile_size]
        num_tiles += 1
        i += tile_size
        j += tile_size
    return bytes(buf[:num_tiles * tile_size])


def png_width(path: Path) -> int:
    return int.from_bytes(path.read_bytes()[16:20], "big")


# --- build ------------------------------------------------------------------------

def targets() -> list:
    found = set()
    for asm in MASTER.rglob("*.asm"):
        for m in re.finditer(r'INCBIN\s+"([^"]+\.(?:2bpp|1bpp))"', asm.read_text(encoding="utf-8", errors="replace")):
            found.add(m.group(1))
    return sorted(found)


def main() -> None:
    rgbgfx = sys.argv[1]
    built = 0
    for rel in targets():
        out = MASTER / rel
        png = out.with_suffix(".png")
        if not png.exists():
            print("no source for", rel)
            continue
        depth = 1 if rel.endswith(".1bpp") else 2
        cmd = [rgbgfx, "--colors", "dmg"]
        if rel in COLUMNS:
            cmd.append("--columns")
        if depth == 1:
            cmd += ["--depth", "1"]
        cmd += ["-o", str(out), str(png)]
        subprocess.run(cmd, check=True)
        o = gfx_options(rel)
        if o["trim"] or o["interleave"] or o["dedupe"]:
            data = out.read_bytes()
            tile_size = depth * 8
            preserved = list(o["preserve"])
            if o["trim"]:
                data = trim_whitespace(data, tile_size, preserved)
            if o["interleave"]:
                data = interleave(data, tile_size, png_width(png))
            if o["dedupe"]:
                data = remove_duplicates(data, depth * (16 if o["interleave"] else 8), preserved)
            out.write_bytes(data)
        built += 1
    print(f"built {built} graphics")


if __name__ == "__main__":
    main()
