## Super Game Boy palette commands (engine/gfx/palettes.asm RunPaletteCommand):
## each SET_PAL_* picks four of the SuperPalettes and an ATTR_BLK packet that says
## which screen cells use which of the four. Autoloaded as `SGB`; the commands are
## always tracked so switching to SGB colours mid-game shows the right palettes.
extends Node

var palettes: Array = []        # PAL_* -> 4 x [r, g, b]
var pal_names := {}
var mon_palettes: Array = []    # dex number -> PAL_*
var pal_packets := {}
var blk_packets := {}
var map_ids := {}
var num_city_maps := 11
var first_indoor_map := 37

var default_cmd := "GENERIC"    # wDefaultPaletteCommand
var _ctx := {}                  # last context per command (species, HP colours, map)
var _pals := [16, 0, 0, 0]      # the four palette ids in effect
var _blk := "BlkPacket_WholeScreen"
var _blk_custom: Array = []     # ATTR_BLK entries built at run time (the party menu HP bars)


func _ready() -> void:
	var f := FileAccess.open("res://assets/data/sgb.json", FileAccess.READ)
	assert(f != null, "missing sgb.json (run tools/export_sgb.py)")
	var data: Dictionary = GameData._intify(JSON.parse_string(f.get_as_text()))
	palettes = data["palettes"]
	pal_names = data["pal_names"]
	mon_palettes = data["mon_palettes"]
	pal_packets = data["pal_packets"]
	blk_packets = data["blk_packets"]
	map_ids = data["map_ids"]["ids"]
	num_city_maps = int(data["map_ids"]["num_city_maps"])
	first_indoor_map = int(data["map_ids"]["first_indoor_map"])


func pal(name: String) -> int:
	return int(pal_names[name])


## MonsterPalettes by species key (DeterminePaletteIDOutOfBattle).
func mon_pal(species: String) -> int:
	if species == "":
		return pal("PAL_MEWMON")
	var dex := int(GameData.pokemon[species]["dex"])
	return int(mon_palettes[dex])


## RunPaletteCommand. ctx: BATTLE {player, enemy (species), player_hp, enemy_hp (0 green, 1 yellow,
## 2 red)}, POKEDEX {species}, OVERWORLD {map, last_map}, STATUS_SCREEN {species, hp},
## PARTY_MENU {hp_colors: [0/1/2 per party member]}, TOWN_MAP, POKEMON_WHOLE_SCREEN {species, black}.
func run(cmd: String, ctx: Dictionary = {}) -> void:
	if cmd == "DEFAULT":
		cmd = default_cmd
		ctx = _ctx.get(cmd, {})
	_ctx[cmd] = ctx
	match cmd:
		"BATTLE_BLACK":
			_pals = pal_packets["PalPacket_Black"].duplicate()
			_blk = "BlkPacket_Battle"
		"BATTLE":
			_pals = [
				pal("PAL_GREENBAR") + int(ctx.get("player_hp", 0)),
				pal("PAL_GREENBAR") + int(ctx.get("enemy_hp", 0)),
				mon_pal(ctx.get("player", "")),
				mon_pal(ctx.get("enemy", "")),
			]
			_blk = "BlkPacket_Battle"
			default_cmd = "BATTLE"
		"POKEDEX":
			_pals = pal_packets["PalPacket_Pokedex"].duplicate()
			_pals[1] = mon_pal(ctx.get("species", ""))
			_blk = "BlkPacket_Pokedex"
		"TITLE_SCREEN":
			_pals = pal_packets["PalPacket_Titlescreen"].duplicate()
			_blk = "BlkPacket_Titlescreen"
		"GENERIC":
			_pals = pal_packets["PalPacket_Generic"].duplicate()
			_blk = "BlkPacket_WholeScreen"
		"TRAINER_CARD":
			_pals = pal_packets["PalPacket_TrainerCard"].duplicate()
			_blk = "BlkPacket_TrainerCard"
		"SLOTS":
			_pals = pal_packets["PalPacket_Slots"].duplicate()
			_blk = "BlkPacket_Slots"
		"NIDORINO_INTRO":
			_pals = pal_packets["PalPacket_NidorinoIntro"].duplicate()
			_blk = "BlkPacket_NidorinoIntro"
		"GAME_FREAK_INTRO":
			_pals = pal_packets["PalPacket_GameFreakIntro"].duplicate()
			_blk = "BlkPacket_GameFreakIntro"
			default_cmd = "GENERIC"
		"OVERWORLD":
			_pals = [_overworld_pal(ctx.get("map", "PALLET_TOWN"), ctx.get("last_map", "PALLET_TOWN")), 0, 0, 0]
			_blk = "BlkPacket_WholeScreen"
			default_cmd = "OVERWORLD"
		"STATUS_SCREEN":
			# SetPal_StatusScreen: PalPacket_Empty with the HP bar colour in slot 0 and the mon in slot 2
			_pals = [pal("PAL_GREENBAR") + int(ctx.get("hp", 0)), 0, mon_pal(ctx.get("species", "")), 0]
			_blk = "BlkPacket_StatusScreen"
		"PARTY_MENU":
			# SetPal_PartyMenu + UpdatePartyMenuBlkPacket: each HP bar row gets pal 1/2/3 (green/yellow/red)
			_pals = pal_packets["PalPacket_PartyMenu"].duplicate()
			var entries: Array = blk_packets["BlkPacket_PartyMenu"].duplicate(true)
			var colors: Array = ctx.get("hp_colors", [])
			var bar_x: Array = ctx.get("bar_x", [])
			for i in colors.size():
				if i + 1 < entries.size():
					var e: Array = entries[i + 1]
					e[1] = int(colors[i]) + 1
					e[2] = int(colors[i]) + 1
					if bar_x.size() == 2:
						# Korean layout: the bar sits further right than BlkPacket_PartyMenu assumes
						e[4] = int(bar_x[0])
						e[6] = int(bar_x[1])
			_blk = ""
			_blk_custom = entries
		"TOWN_MAP":
			_pals = pal_packets["PalPacket_TownMap"].duplicate()
			_blk = "BlkPacket_WholeScreen"
		"POKEMON_WHOLE_SCREEN":
			# SetPal_PokemonWholeScreen: the species' palette (or PAL_BLACK) on the whole screen
			var p0 := pal("PAL_BLACK") if ctx.get("black", false) else mon_pal(ctx.get("species", ""))
			_pals = [p0, 0, 0, 0]
			_blk = "BlkPacket_WholeScreen"
		_:
			push_warning("SGB: unknown palette command " + cmd)
			return
	apply()


## SetPal_Overworld: towns use PAL_<town> (map id + 1), routes PAL_ROUTE, indoor maps the
## palette of the town or route they belong to (wLastMap).
func _overworld_pal(map: String, last_map: String) -> int:
	var id := int(map_ids.get(map, 0))
	if id >= first_indoor_map:
		id = int(map_ids.get(last_map, 0))
	if id < num_city_maps:
		return id + 1
	return pal("PAL_ROUTE")


## Push the palettes and attribute map to the screen (only visible while SGB colours are on).
func apply() -> void:
	var screen: GBScreen = GB.screen
	if screen == null:
		return
	var cols := PackedColorArray()
	for p in _pals:
		var entry: Array = palettes[int(p)]
		for c in entry:
			cols.append(Color8(int(c[0]), int(c[1]), int(c[2])))
	screen.set_sgb_colors(cols)
	screen.set_attr_blk(_blk_custom if _blk == "" else blk_packets[_blk])
