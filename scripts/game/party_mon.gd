## A party Pokémon with Generation 1 stat calculation.
class_name PartyMon
extends RefCounted

## Status condition bits (constants/status_constants.asm): the low three bits
## count the remaining sleep turns.
const SLP_MASK := 0x07
const PSN := 0x08
const BRN := 0x10
const FRZ := 0x20
const PAR := 0x40

var species := ""
var level := 5
var dvs := {"atk": 8, "def": 8, "spd": 8, "spc": 8}
var hp := 0
var max_hp := 0
var stats := {}       # atk, def, spd, spc
var moves: Array = [] # [{"move": "TACKLE", "pp": 35, "max_pp": 35}]
var stat_exp := {"hp": 0, "atk": 0, "def": 0, "spd": 0, "spc": 0}   # MON_HP_EXP..MON_SPC_EXP (max 65535)
var exp := 0
var status := 0
var nickname := ""
var ot_name := ""      # MON_OT name; "" = the player (wPlayerName)
var ot_id := -1        # MON_OTID; -1 = the player (wPlayerID)


static func create(sp: String, lv: int, random_dvs: bool = true) -> PartyMon:
	var m := PartyMon.new()
	m.species = sp
	m.level = lv
	if random_dvs:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		m.dvs = {"atk": rng.randi_range(0, 15), "def": rng.randi_range(0, 15), "spd": rng.randi_range(0, 15), "spc": rng.randi_range(0, 15)}
	else:
		m.dvs = {"atk": 9, "def": 8, "spd": 8, "spc": 8}
	m.nickname = GameData.mon_name(sp)
	var data: Dictionary = GameData.pokemon[sp]
	for mv in data["moves"]:
		m.moves.append({"move": mv, "pp": GameData.moves[mv]["pp"], "max_pp": GameData.moves[mv]["pp"]})
	# WriteMonMoves: each learnset move up to the level; with four moves the first one
	# is dropped, so the last four learned are kept
	for entry in data["learnset"]:
		if entry[0] <= lv and not m.has_move(entry[1]):
			if m.moves.size() >= 4:
				m.moves.pop_front()
			m.moves.append({"move": entry[1], "pp": GameData.moves[entry[1]]["pp"], "max_pp": GameData.moves[entry[1]]["pp"]})
	m.exp = exp_for_level(data["growth"], lv)
	m.recalc_stats()
	m.hp = m.max_hp
	return m


func to_dict() -> Dictionary:
	return {"species": species, "level": level, "dvs": dvs, "hp": hp, "max_hp": max_hp, "stats": stats,
		"moves": moves, "exp": exp, "status": status, "nickname": nickname, "stat_exp": stat_exp,
		"ot_name": ot_name, "ot_id": ot_id}


static func from_dict(d: Dictionary) -> PartyMon:
	var m := PartyMon.new()
	m.species = str(d["species"])
	m.level = int(d["level"])
	m.dvs = d["dvs"]
	m.moves = d["moves"]
	m.exp = int(d["exp"])
	m.status = int(d["status"])
	m.nickname = str(d["nickname"])
	if d.has("stat_exp"):
		for k in m.stat_exp.keys():
			m.stat_exp[k] = int(d["stat_exp"].get(k, 0))
	m.recalc_stats()
	m.hp = clampi(int(d["hp"]), 0, m.max_hp)
	m.ot_name = str(d.get("ot_name", ""))
	m.ot_id = int(d.get("ot_id", -1))
	return m


func has_move(mv: String) -> bool:
	for m in moves:
		if m.move == mv:
			return true
	return false


func hp_dv() -> int:
	return ((dvs.atk & 1) << 3) | ((dvs.def & 1) << 2) | ((dvs.spd & 1) << 1) | (dvs.spc & 1)


## CalcStat (home/move_mon.asm): ((base + dv) * 2 + ceil(sqrt(stat exp)) / 4) * level / 100
## + 5 (+ level + 5 for HP). The square root is capped at 255 like the original loop.
func recalc_stats() -> void:
	var data: Dictionary = GameData.pokemon[species]
	max_hp = (((data["hp"] + hp_dv()) * 2 + _stat_exp_bonus(int(stat_exp["hp"]))) * level) / 100 + level + 10
	stats = {}
	for k in ["atk", "def", "spd", "spc"]:
		stats[k] = (((data[k] + dvs[k]) * 2 + _stat_exp_bonus(int(stat_exp[k]))) * level) / 100 + 5


static func _stat_exp_bonus(v: int) -> int:
	var b := 0
	while b < 255 and b * b < v:
		b += 1
	return b / 4


static func exp_for_level(growth: String, lv: int) -> int:
	var n := lv
	match growth:
		"GROWTH_MEDIUM_SLOW":
			return (6 * n * n * n) / 5 - 15 * n * n + 100 * n - 140
		"GROWTH_SLIGHTLY_FAST":
			return (3 * n * n * n) / 4 + 10 * n * n - 30
		"GROWTH_SLIGHTLY_SLOW":
			return (3 * n * n * n) / 4 + 20 * n * n - 70
		"GROWTH_FAST":
			return (4 * n * n * n) / 5
		"GROWTH_SLOW":
			return (5 * n * n * n) / 4
	return n * n * n
