## The TOWN MAP (engine/items/town_map.asm DisplayTownMap and LoadTownMap_Nest).
## Data from assets/data/town_map.json (tools/export_data.py export_town_map).
class_name TownMap
extends RefCounted

static var _data := {}
static var _blink_counter := 0        # wAnimCounter
static var _blink_backup: Array = []  # wShadowOAMBackup


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://assets/data/town_map.json", FileAccess.READ)
		assert(f != null, "missing town_map.json (run tools/export_data.py)")
		_data = GameData._intify(JSON.parse_string(f.get_as_text()))
	return _data


## LoadTownMapEntry: [x, y, name key] of a map (indoor maps use their group's entry).
static func entry(map: String) -> Array:
	var d := data()
	var id := int(d["map_ids"].get(map, 0))
	if id < int(d["first_indoor_map"]):
		return d["external"][id]
	for e in d["internal"]:
		if id < int(e[0]):
			return [e[1], e[2], e[3]]
	return d["external"][0]


static func location_name(key: String) -> String:
	var names: Dictionary = data()["names"].get(key, {})
	return str(names.get(GameData.lang, names.get("en", key)))


## The header row: row 0, or row 1 in Korean so the 8x16 glyphs' top halves fit on row 0.
static func _header_y() -> int:
	return 1 if GameData.lang == "ko" else 0


## Erase the header: row 0 is cleared like the original; Korean also restores row 1 of the map.
static func _clear_header() -> void:
	Text.clear_area(0, 0, 20, 1)
	if GameData.lang == "ko":
		var S: GBScreen = GB.screen
		var tiles: Array = data()["tilemap"]
		for i in range(20, 40):
			S.set_bg(i % 20, i / 20, S.tile("town_map", int(tiles[i])))


## LoadTownMap: white out, clear, the compressed map, SET_PAL_TOWN_MAP.
static func _load_map() -> void:
	var S: GBScreen = GB.screen
	S.white_out()
	await GB.delay3()
	Text.clear_screen()
	S.clear_sprites()
	Menu.draw_box(0, 0, 18, 18)
	var tiles: Array = data()["tilemap"]
	for i in tiles.size():
		S.set_bg(i % 20, i / 20, S.tile("town_map", int(tiles[i])))
	SGB.run("TOWN_MAP")
	await GB.delay3()
	S.normal_pals()
	_blink_counter = 0


## TownMapCoordsToOAMCoords for a 16x16 sprite: screen top-left corner.
static func _sprite_pos(e: Array) -> Vector2i:
	return Vector2i(int(e[0]) * 8 + 12, int(e[1]) * 8 + 4)


## DrawPlayerOrBirdSprite (player): the standing player sprite in OAM 36..39.
static func _draw_player(map: String) -> void:
	var S: GBScreen = GB.screen
	var p := _sprite_pos(entry(map))
	for k in 4:
		S.set_sprite(36 + k, p.x + (k % 2) * 8, p.y + (k / 2) * 8, S.tile("spr_red", k))


## The town map cursor (town_map_cursor.1bpp, four tiles) in OAM 4..7.
static func _draw_cursor(e: Array) -> void:
	var S: GBScreen = GB.screen
	var p := _sprite_pos(e)
	for k in 4:
		S.set_sprite(4 + k, p.x + (k % 2) * 8, p.y + (k / 2) * 8, S.tile("town_map_cursor", k))


## TownMapSpriteBlinkingAnimation: OAM 0..35 hidden on frame 25, back on frame 50.
static func _blink() -> void:
	var S: GBScreen = GB.screen
	_blink_counter += 1
	if _blink_counter == 25:
		_blink_backup = S.oam.duplicate(true)
		for i in mini(36, S.oam.size()):
			if S.oam[i] != null:
				S.oam[i].y = 144
	elif _blink_counter >= 50:
		for i in mini(36, _blink_backup.size()):
			if i < S.oam.size():
				S.oam[i] = _blink_backup[i]
		_blink_counter = 0


## ExitTownMap: white out, clear, no sprites, default palette (the caller redraws the map).
static func _exit() -> void:
	var S: GBScreen = GB.screen
	S.white_out()
	Text.clear_screen()
	S.clear_sprites()
	SGB.run("DEFAULT")


## DisplayTownMap: the player's position, a cursor cycled with Up/Down, A/B closes.
static func show(_state: GameState, ow) -> void:
	var S: GBScreen = GB.screen
	await _load_map()
	var cur_map: String = ow.map_id
	_draw_player(cur_map)
	var order: Array = data()["order"]
	var which := 0           # wWhichTownMapLocation
	var e := entry(cur_map)  # the cursor starts on the current map
	while true:
		_draw_cursor(e)
		Text.place_string(1, _header_y(), location_name(str(e[2])))
		var keys := 0
		while true:
			await GB.frame
			_blink()
			keys = GB.joy5 & (GB.A | GB.B | GB.UP | GB.DOWN)
			if keys != 0:
				break
		Sound.play_sfx("SFX_TINK")
		if keys & GB.UP:
			which = (which + 1) % order.size()
		elif keys & GB.DOWN:
			which = (which + order.size() - 1) % order.size()
		else:
			break
		_clear_header()
		e = entry(str(order[which]))
	_exit()


## LoadTownMap_Nest: nest icons on every map where the species appears, "<MON>'s NEST".
static func show_nest(_state: GameState, species: String) -> void:
	var S: GBScreen = GB.screen
	await _load_map()
	# FindWildLocationsOfMon over the exported wild tables (duplicates per map removed)
	var seen := {}
	var n := 0
	for map in GameData.wild["maps"]:
		var table: Dictionary = GameData.wild["maps"][map]
		var found := false
		for key in ["grass", "water"]:
			for slot in table.get(key, []):
				if slot[1] == species:
					found = true
		if not found or seen.has(map):
			continue
		seen[map] = true
		var e := entry(map)
		if int(e[0]) == 9 and int(e[1]) == 1:
			continue   # Cerulean Cave is never shown
		S.set_sprite(n, int(e[0]) * 8 + 16, int(e[1]) * 8 + 8, S.tile("mon_nest_icon", 0))
		n += 1
	var ko := GameData.lang == "ko"
	if n == 0:
		Menu.draw_box(1, 7, 15, 2)
		Text.place_string(2, 9, " 지역 불명" if ko else " AREA UNKNOWN")
	else:
		_draw_player(_state.cur_map)
	var end := Text.place_string(1, _header_y(), GameData.mon_name(species))
	Text.place_string(end.x, _header_y(), "의 서식지" if ko else "'s NEST")
	# WaitForTextScrollButtonPress while the icons keep blinking
	Text._down_arrow_count1 = 0
	Text._down_arrow_count2 = 6
	while true:
		await GB.frame
		_blink()
		Text._handle_down_arrow_blink()
		if GB.joy5 & (GB.A | GB.B):
			break
	_exit()
