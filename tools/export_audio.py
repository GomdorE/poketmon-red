"""Export the pokered sound data (music, sfx, cries) for the Godot sound engine.

Usage (from pokered-godot):  python tools/export_audio.py

Writes assets/data/audio.json:
  cmds      flat list of every audio command of every music/sfx file
  labels    label -> index into cmds (sound_call / sound_loop targets are resolved to indices)
  banks     per audio bank (1-3): {id: {"name", "channels": [[software_channel, cmd_index], ...]}}
  sounds    constant name (MUSIC_*, SFX_*) -> {"bank": n, "id": k} (ids are shared across banks
            for sounds that exist in several banks)
  cries     internal mon id (1-based) -> [cry_index, pitch, tempo]
  move_sfx  move id (1-based) -> [sfx constant, pitch, tempo]
  waves     the five channel 3 wave patterns
  notes     the 12 base frequencies (octave 8)
  ranges    id ranges used by the engine (cries, noise instruments, battle sfx)

PH-INTENT: the Godot engine interprets exactly these commands with the semantics of
audio/engine_1.asm; nothing is re-sequenced by hand.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
MASTER = (PROJECT.parent / "pokered-master").resolve()
OUT = PROJECT / "assets" / "data" / "audio.json"

PITCHES = {"C_": 0, "C#": 1, "D_": 2, "D#": 3, "E_": 4, "F_": 5, "F#": 6, "G_": 7, "G#": 8, "A_": 9, "A#": 10, "B_": 11}

cmds: list = []
labels: dict[str, int] = {}
pending_refs: list = []  # (cmd index, arg position, label, scope)


def num(tok: str) -> int:
    tok = tok.strip()
    neg = tok.startswith("-")
    if neg:
        tok = tok[1:]
    if tok.startswith("$"):
        v = int(tok[1:], 16)
    elif tok.startswith("%"):
        v = int(tok[1:], 2)
    elif tok in PITCHES:
        v = PITCHES[tok]
    else:
        v = int(tok)
    return -v if neg else v


def parse_file(path: Path) -> None:
    scope = ""
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r"^(\.?[A-Za-z0-9_]+)::?\s*$", line)
        if m:
            name = m.group(1)
            if name.startswith("."):
                labels[scope + name] = len(cmds)
            else:
                scope = name
                labels[name] = len(cmds)
            continue
        parts = line.strip().split(None, 1)
        op = parts[0]
        args = [a.strip() for a in parts[1].split(",")] if len(parts) > 1 else []
        idx = len(cmds)
        if op == "tempo":
            cmds.append(["tempo", num(args[0])])
        elif op == "volume":
            cmds.append(["volume", num(args[0]), num(args[1])])
        elif op == "duty_cycle":
            cmds.append(["duty", num(args[0])])
        elif op == "duty_cycle_pattern":
            a = [num(x) for x in args]
            cmds.append(["dutypat", (a[0] << 6) | (a[1] << 4) | (a[2] << 2) | a[3]])
        elif op == "note_type":
            cmds.append(["notetype", num(args[0]), num(args[1]), num(args[2])])
        elif op == "drum_speed":
            cmds.append(["drumspeed", num(args[0])])
        elif op == "octave":
            cmds.append(["octave", num(args[0])])
        elif op == "note":
            cmds.append(["note", num(args[0]), num(args[1])])
        elif op == "rest":
            cmds.append(["rest", num(args[0])])
        elif op == "drum_note":
            cmds.append(["drum", num(args[0]), num(args[1])])
        elif op == "drum_note_short":
            cmds.append(["drum", num(args[0]), num(args[1])])
        elif op == "sound_call":
            cmds.append(["call", -1])
            pending_refs.append((idx, 1, args[0], scope))
        elif op == "sound_loop":
            cmds.append(["loop", num(args[0]), -1])
            pending_refs.append((idx, 2, args[1], scope))
        elif op == "sound_ret":
            cmds.append(["ret"])
        elif op == "vibrato":
            cmds.append(["vibrato", num(args[0]), num(args[1]), num(args[2])])
        elif op == "pitch_slide":
            cmds.append(["slide", num(args[0]), num(args[1]), num(args[2])])
        elif op == "toggle_perfect_pitch":
            cmds.append(["perfect"])
        elif op == "stereo_panning":
            cmds.append(["pan", (num(args[0]) << 4) | num(args[1])])
        elif op == "execute_music":
            cmds.append(["exec"])
        elif op == "square_note":
            cmds.append(["sq", num(args[0]), num(args[1]), num(args[2]), num(args[3])])
        elif op == "noise_note":
            cmds.append(["noise", num(args[0]), num(args[1]), num(args[2]), num(args[3])])
        elif op == "pitch_sweep":
            cmds.append(["sweep", num(args[0]), num(args[1])])
        elif op == "unknownmusic0xef":
            cmds.append(["m0xef", num(args[0])])
        elif op in ("dn", "db", "dw", "INCLUDE", "SECTION", "table_width", "assert_table_length"):
            continue
        else:
            print(f"unknown audio op {op!r} in {path.name}: {line.strip()}")


def resolve_refs() -> None:
    for idx, pos, label, scope in pending_refs:
        key = scope + label if label.startswith(".") else label
        if key not in labels:
            sys.exit(f"unresolved audio label {key}")
        cmds[idx][pos] = labels[key]


def parse_headers(path: Path, start_id: int) -> tuple[dict, int]:
    """Return {id: {name, channels}} for one header file; ids start at start_id."""
    out = {}
    cur = None
    next_id = start_id
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"^([A-Za-z0-9_]+)::\s*$", line)
        if m:
            cur = {"name": m.group(1), "channels": []}
            continue
        if line.startswith("db $ff, $ff, $ff"):
            next_id += 1  # padding entry
            continue
        m = re.match(r"^channel_count\s+(\d+)", line)
        if m and cur is not None:
            cur["count"] = int(m.group(1))
            cur["id"] = next_id
            out[next_id] = cur
            next_id += int(m.group(1))
            continue
        m = re.match(r"^channel\s+(\d+),\s*([A-Za-z0-9_.]+)", line)
        if m and cur is not None:
            label = m.group(2)
            if label not in labels:
                sys.exit(f"header references unknown label {label}")
            cur["channels"].append([int(m.group(1)) - 1, labels[label]])
    return out, next_id


def main() -> None:
    for path in sorted((MASTER / "audio" / "sfx").glob("*.asm")) + sorted((MASTER / "audio" / "music").glob("*.asm")):
        parse_file(path)
    resolve_refs()
    banks = {}
    name_to_bank_id: dict[str, tuple[int, int]] = {}
    for bank in (1, 2, 3):
        sfx, nxt = parse_headers(MASTER / "audio" / "headers" / f"sfxheaders{bank}.asm", 0)
        music, _ = parse_headers(MASTER / "audio" / "headers" / f"musicheaders{bank}.asm", nxt)
        allh = {**sfx, **music}
        banks[bank] = {str(k): {"name": v["name"], "channels": v["channels"]} for k, v in allh.items()}
        for k, v in allh.items():
            name_to_bank_id.setdefault(v["name"], (bank, k))
    # constant names -> (bank, id)
    sounds = {}
    for raw in (MASTER / "constants" / "music_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*music_const\s+([A-Z0-9_]+),\s*([A-Za-z0-9_]+)", raw.split(";")[0])
        if m:
            label = m.group(2)
            if label not in name_to_bank_id:
                sys.exit(f"music_const label not found in headers: {label}")
            bank, sid = name_to_bank_id[label]
            sounds[m.group(1)] = {"bank": bank, "id": sid}
    # cries: internal id order
    cries = []
    for raw in (MASTER / "data" / "pokemon" / "cries.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*mon_cry\s+SFX_CRY_([0-9A-F]+),\s*\$([0-9A-Fa-f]+),\s*\$([0-9A-Fa-f]+)", raw)
        if m:
            cries.append([int(m.group(1), 16), int(m.group(2), 16), int(m.group(3), 16)])
    move_sfx = []
    for raw in (MASTER / "data" / "moves" / "sfx.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*db\s+(SFX_[A-Z0-9_]+),\s*\$([0-9A-Fa-f]+),\s*\$([0-9A-Fa-f]+)", raw.split(";")[0])
        if m:
            move_sfx.append([m.group(1), int(m.group(2), 16), int(m.group(3), 16)])
    waves = []
    for raw in (MASTER / "audio" / "wave_samples.asm").read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("dn"):
            waves.append([int(x) for x in line[2:].split(",")])
    notes = []
    for raw in (MASTER / "audio" / "notes.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*dw\s+\$([0-9A-Fa-f]+)", raw)
        if m:
            notes.append(int(m.group(1), 16))
    ranges = {
        "cry_start": sounds["SFX_CRY_00"]["id"],
        "cry_end": sounds["SFX_CRY_25"]["id"] + 3,
        "noise_start": sounds["SFX_NOISE_INSTRUMENT01"]["id"],
        "noise_end": sounds["SFX_NOISE_INSTRUMENT19"]["id"] + 1,
        "battle_start": sounds["SFX_PECK"]["id"],
        "battle_end": sounds["SFX_TRAINER_APPEARED"]["id"] + 1,
        "max_sfx": {"1": sounds["SFX_SAFARI_ZONE_PA"]["id"], "2": sounds["SFX_TRAINER_APPEARED"]["id"], "3": sounds["SFX_SHOOTING_STAR"]["id"]},
    }
    map_music = {}
    for raw in (MASTER / "data" / "maps" / "songs.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*db\s+(MUSIC_[A-Z0-9_]+),\s*BANK\([A-Za-z_0-9]+\)\s*;\s*([A-Z0-9_]+)", raw)
        if m:
            map_music[m.group(2)] = m.group(1)
    data = {
        "cmds": cmds, "labels": labels, "banks": banks, "sounds": sounds, "cries": cries,
        "move_sfx": move_sfx, "waves": waves, "notes": notes, "ranges": ranges, "map_music": map_music,
    }
    OUT.write_text(json.dumps(data), encoding="utf-8")
    print(f"audio: {len(cmds)} commands, {len(labels)} labels, {len(sounds)} sounds, {len(cries)} cries, {len(move_sfx)} move sfx")
    for k in ("MUSIC_PALLET_TOWN", "SFX_PRESS_AB", "SFX_CRY_00", "SFX_LEVEL_UP", "SFX_INTRO_HIP", "MUSIC_TRAINER_BATTLE", "MUSIC_TITLE_SCREEN"):
        print(k, sounds[k])
    print("ranges", ranges)


if __name__ == "__main__":
    main()
