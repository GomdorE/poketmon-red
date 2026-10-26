"""Export the battle animation tables of pokered to assets/data/battle_anims.json.

Sources (engine/battle/animations.asm and friends):
  data/moves/animations.asm           AttackAnimationPointers + the battle_anim command streams
  data/battle_anims/subanimations.asm SubanimationPointers + subanim entries (type, [frame block, base coord, mode])
  data/battle_anims/frame_blocks.asm  FrameBlockPointers + dbsprite lists ([y, x, tile, flags])
  data/battle_anims/base_coords.asm   FrameBlockBaseCoords ([y, x])
  constants/move_constants.asm        move ids (= animation ids), the extra animation ids after NUM_ATTACKS
  constants/move_animation_constants.asm  SE_*, SUBANIM_*, FRAMEBLOCK_*, BASECOORD_*, FRAMEBLOCKMODE_*, SUBANIMTYPE_*

Output:
  anim_ids:    name -> id (moves and *_ANIM ids)
  anims:       id -> [cmd, ...]; cmd = {"sound": move id or 0, "se": name} | {"sound", "sub": id, "tileset": n, "delay": d}
  subanims:    [ {"type": SUBANIMTYPE name, "entries": [[frame block, base coord, mode], ...]}, ... ]
  frame_blocks:[ [[y, x, tile, flags], ...], ... ]   (y/x are OAM values: + base coordinate)
  base_coords: [[y, x], ...]
  se_names:    value -> SE name
  anim_special_effects: anim id -> special effect routine name (AnimationIdSpecialEffects)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
MASTER = ROOT.parent / "pokered-master"
OUT = ROOT / "assets" / "data" / "battle_anims.json"


def read(rel: str) -> list[str]:
    return (MASTER / rel).read_text(encoding="utf-8").splitlines()


def strip(line: str) -> str:
    return line.split(";")[0].strip()


def parse_consts(rel: str) -> dict[str, int]:
    """A small rgbds const_def / const / const_skip evaluator."""
    out: dict[str, int] = {}
    value = 0
    for raw in read(rel):
        code = strip(raw)
        m = re.match(r"const_def(?:\s+(\$?[0-9A-Fa-f]+))?$", code)
        if m:
            value = int(m.group(1).replace("$", ""), 16 if m.group(1) and m.group(1).startswith("$") else 10) if m.group(1) else 0
            continue
        m = re.match(r"const_skip(?:\s+(\$?[0-9A-Fa-f]+))?$", code)
        if m:
            n = m.group(1)
            value += (int(n.replace("$", ""), 16) if n and n.startswith("$") else int(n)) if n else 1
            continue
        m = re.match(r"const\s+([A-Za-z0-9_]+)$", code)
        if m:
            out[m.group(1)] = value
            value += 1
            continue
        m = re.match(r"DEF\s+([A-Za-z0-9_]+)\s+EQU\s+const_value", code)
        if m:
            out[m.group(1)] = value
    return out


def parse_pointer_table(lines: list[str], label: str) -> list[str]:
    names: list[str] = []
    inside = False
    for raw in lines:
        code = strip(raw)
        if code == label + ":":
            inside = True
            continue
        if not inside:
            continue
        m = re.match(r"dw\s+([A-Za-z0-9_]+)", code)
        if m:
            names.append(m.group(1))
        elif code.startswith("assert_table_length") or code.startswith("table_width"):
            continue   # the move table has an assert in the middle (NUM_ATTACKS) and one at the end
        elif code and names:
            break
    return names


def parse_labelled_blocks(lines: list[str]) -> dict[str, list[str]]:
    """label -> code lines until the next label (labels sharing a body get the same lines)."""
    blocks: dict[str, list[str]] = {}
    current: list[str] = []
    cur_labels: list[str] = []
    for raw in lines:
        code = strip(raw)
        m = re.match(r"([A-Za-z0-9_]+):+$", code)
        if m:
            if current and cur_labels:
                for lb in cur_labels:
                    blocks[lb] = current
                cur_labels = []
                current = []
            cur_labels.append(m.group(1))
            continue
        if code:
            current.append(code)
    if cur_labels:
        for lb in cur_labels:
            blocks[lb] = current
    return blocks


def main() -> None:
    moves = parse_consts("constants/move_constants.asm")
    anim_consts = parse_consts("constants/move_animation_constants.asm")
    oam_flags = {"OAM_XFLIP": 0x20, "OAM_YFLIP": 0x40, "OAM_BEHIND_BG": 0x80, "OAM_OBP1": 0x10}

    def anim_value(tok: str) -> int:
        tok = tok.strip()
        if tok in moves:
            return moves[tok]
        if tok in anim_consts:
            return anim_consts[tok]
        if tok.startswith("$"):
            return int(tok[1:], 16)
        return int(tok)

    se_names = {v: k for k, v in anim_consts.items() if k.startswith("SE_")}

    # --- animations ---------------------------------------------------------
    anim_lines = read("data/moves/animations.asm")
    anim_table = parse_pointer_table(anim_lines, "AttackAnimationPointers")
    blocks = parse_labelled_blocks(anim_lines)
    anims: dict[int, list[dict]] = {}
    for idx, label in enumerate(anim_table):
        anim_id = idx + 1
        cmds: list[dict] = []
        for code in blocks.get(label, []):
            m = re.match(r"battle_anim\s+(.+)$", code)
            if not m:
                continue
            parts = [p.strip() for p in m.group(1).split(",")]
            sound = moves.get(parts[0], 0)
            if len(parts) == 4:
                cmds.append({"sound": sound, "sub": anim_consts[parts[1]], "tileset": int(parts[2]), "delay": int(parts[3])})
            else:
                cmds.append({"sound": sound, "se": parts[1]})
        anims[anim_id] = cmds

    anim_ids = {k: v for k, v in moves.items() if 0 < v <= anim_consts.get("NUM_ATTACK_ANIMS", moves.get("BAIT_ANIM", 0))}

    # --- subanimations ------------------------------------------------------
    sub_lines = read("data/battle_anims/subanimations.asm")
    sub_table = parse_pointer_table(sub_lines, "SubanimationPointers")
    sub_blocks = parse_labelled_blocks(sub_lines)
    subanims: list[dict] = []
    for label in sub_table:
        body = sub_blocks[label]
        head = re.match(r"subanim\s+([A-Z_]+),\s*(\d+)", body[0])
        entries: list[list[int]] = []
        for code in body[1:]:
            m = re.match(r"db\s+([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)", code)
            if m:
                entries.append([anim_consts[m.group(1)], anim_consts[m.group(2)], anim_consts[m.group(3)]])
        assert len(entries) == int(head.group(2)), (label, len(entries), head.group(2))
        subanims.append({"type": head.group(1), "entries": entries})

    # --- frame blocks -------------------------------------------------------
    fb_lines = read("data/battle_anims/frame_blocks.asm")
    fb_table = parse_pointer_table(fb_lines, "FrameBlockPointers")
    fb_blocks = parse_labelled_blocks(fb_lines)
    frame_blocks: list[list[list[int]]] = []
    for label in fb_table:
        sprites: list[list[int]] = []
        count = 0
        for code in fb_blocks[label]:
            m = re.match(r"db\s+(\d+)", code)
            if m and not sprites:
                count = int(m.group(1))
                continue
            m = re.match(r"dbsprite\s+(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(-?\d+),\s*(\$?[0-9A-Fa-f]+),\s*(.+)$", code)
            if m:
                xt, yt, xp, yp = (int(m.group(i)) for i in range(1, 5))
                tile = anim_value(m.group(5))
                flags = 0
                for f in m.group(6).split("|"):
                    f = f.strip()
                    flags |= oam_flags.get(f, int(f) if f.isdigit() else 0)
                sprites.append([(yt * 8 + yp) % 256, (xt * 8 + xp) % 256, tile, flags])
        if len(sprites) != count:
            # FrameBlock62 lists one sprite more than its count; DrawFrameBlock only uses `count`
            print(f"note: {label} has {len(sprites)} sprites, count {count} (using the count)")
            sprites = sprites[:count]
        frame_blocks.append(sprites)

    # --- base coordinates ---------------------------------------------------
    base_coords: list[list[int]] = []
    for raw in read("data/battle_anims/base_coords.asm"):
        m = re.match(r"db\s+\$([0-9A-Fa-f]+),\s*\$([0-9A-Fa-f]+)", strip(raw))
        if m:
            base_coords.append([int(m.group(1), 16), int(m.group(2), 16)])

    # --- AnimationIdSpecialEffects -----------------------------------------
    special: dict[int, str] = {}
    for raw in read("data/battle_anims/special_effects.asm"):
        m = re.match(r"anim_special_effect\s+([A-Z0-9_]+),\s*([A-Za-z0-9_]+)", strip(raw))
        if m:
            special[moves[m.group(1)]] = m.group(2)

    data = {
        "anim_ids": anim_ids,
        "anims": {str(k): v for k, v in anims.items()},
        "subanims": subanims,
        "frame_blocks": frame_blocks,
        "base_coords": base_coords,
        "se_names": {str(k): v for k, v in se_names.items()},
        "anim_special_effects": {str(k): v for k, v in special.items()},
    }
    OUT.write_text(json.dumps(data), encoding="utf-8")
    print(f"battle anims: {len(anims)} anims, {len(subanims)} subanims, {len(frame_blocks)} frame blocks, "
          f"{len(base_coords)} base coords, {len(special)} special effects -> {OUT}")


if __name__ == "__main__":
    sys.exit(main())
