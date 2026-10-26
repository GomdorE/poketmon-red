## The Pokédex list (engine/menus/pokedex.asm ShowPokedexMenu / HandlePokedexListMenu /
## HandlePokedexSideMenu): seen names, owned balls, SEEN/OWN counts and the
## DATA / CRY / AREA / QUIT side menu.
class_name PokedexMenu
extends RefCounted


static func _dex_tile(t: int) -> int:
	return GB.screen.tile("pokedex_tiles", t - 0x60)


## Species key by Pokédex number.
static func _by_dex() -> Dictionary:
	var out := {}
	for sp in GameData.pokemon:
		out[int(GameData.pokemon[sp]["dex"])] = sp
	return out


## DrawPokedexVerticalLine: 9 rows alternating the line tile ($71) and the box tile ($70).
static func _vertical_line(x: int, y: int) -> void:
	var S: GBScreen = GB.screen
	var t := 0x71
	for k in 9:
		S.set_bg(x, y + k, _dex_tile(t))
		t ^= 1


## The frame, counts and the side menu labels (HandlePokedexListMenu before the list loop).
static func _draw_statics(state: GameState) -> void:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	for x in range(15, 20):
		S.set_bg(x, 8, MonHud.hp_tile(0x7A))   # '─' from the HP bar / status font loaded at $62
	S.set_bg(14, 0, _dex_tile(0x71))
	_vertical_line(14, 1)
	_vertical_line(14, 9)
	Text.place_string(16, 3, "%3d" % state.pokedex_seen.size())
	Text.place_string(16, 6, "%3d" % state.pokedex_owned.size())
	Text.place_string(16, 2, "발견" if ko else "SEEN")
	Text.place_string(16, 5, "잡음" if ko else "OWN")
	Text.place_string(1, 1, "목록" if ko else "CONTENTS")
	Text.place_string(16, 10, "데이터<NEXT>울음<NEXT>분포<NEXT>종료" if ko else "DATA<NEXT>CRY<NEXT>AREA<NEXT>QUIT")


## wDexMaxSeenMon: the highest Pokédex number seen.
static func _max_seen(state: GameState) -> int:
	var m := 0
	for sp in state.pokedex_seen:
		if GameData.pokemon.has(sp):
			m = maxi(m, int(GameData.pokemon[sp]["dex"]))
	return m


## The list rows: number on row 2i+2, ball and name on row 2i+3.
static func _draw_list(state: GameState, offset: int, rows: int, by_dex: Dictionary) -> void:
	var S: GBScreen = GB.screen
	Text.clear_area(4, 2, 10, 14)
	for i in rows:
		var n := offset + i + 1
		var sp: String = str(by_dex.get(n, ""))
		Text.place_string(1, 2 + i * 2, "%03d" % n)
		if sp != "" and state.pokedex_owned.has(sp):
			S.set_bg(3, 3 + i * 2, _dex_tile(0x72))
		else:
			Text.put(3, 3 + i * 2, Text.SPACE)
		if sp != "" and state.pokedex_seen.has(sp):
			Text.place_string(4, 3 + i * 2, GameData.mon_name(sp))
		else:
			Text.place_string(4, 3 + i * 2, "----------")


## ShowPokedexMenu. Leaves the screen whited out with the default palette command
## run; the caller reloads the map (ReloadMapData).
static func show(state: GameState) -> void:
	var S: GBScreen = GB.screen
	var by_dex := _by_dex()
	var offset := 0   # wListScrollOffset
	var cur := 0      # wCurrentMenuItem
	var setup := true
	var quit := false
	while not quit:
		if setup:
			# .setUpGraphics
			S.white_out()
			Text.clear_screen()
			S.clear_sprites()
			SGB.run("GENERIC")
			_draw_statics(state)
			setup = false
		var max_seen := maxi(_max_seen(state), 1)
		var rows := mini(max_seen, 7)
		cur = mini(cur, rows - 1)
		var redraw := true
		var chose := false
		while true:
			if redraw:
				_draw_list(state, offset, rows, by_dex)
				await GB.delay3()
				S.normal_pals()
				Menu.place_cursor(0, 3 + cur * 2)
				redraw = false
			await GB.frame
			var keys := GB.joy5
			if keys == 0:
				continue
			if keys & GB.B:
				Sound.play_sfx("SFX_PRESS_AB")
				quit = true
				break
			if keys & GB.A:
				Sound.play_sfx("SFX_PRESS_AB")
				chose = true
				break
			if keys & GB.UP:
				if cur > 0:
					Text.put(0, 3 + cur * 2, Text.SPACE)
					cur -= 1
					Menu.place_cursor(0, 3 + cur * 2)
				elif offset > 0:
					offset -= 1
					redraw = true
			elif keys & GB.DOWN:
				if cur < rows - 1:
					Text.put(0, 3 + cur * 2, Text.SPACE)
					cur += 1
					Menu.place_cursor(0, 3 + cur * 2)
				elif max_seen >= 7 and offset < max_seen - 7:
					offset += 1
					redraw = true
			elif keys & GB.RIGHT:
				if max_seen >= 7:
					offset = mini(offset + 7, max_seen - 7)
					redraw = true
			elif keys & GB.LEFT:
				offset = maxi(offset - 7, 0)
				redraw = true
		if quit:
			break
		# HandlePokedexSideMenu
		Menu.cursor_pos = Vector2i(-1, -1)
		Text.put(0, 3 + cur * 2, 0xEC)   # ▷
		var n := offset + cur + 1
		var sp: String = str(by_dex.get(n, ""))
		if sp == "" or not state.pokedex_seen.has(sp):
			for k in 13:
				Text.put(0, 3 + k, Text.SPACE)
			continue
		var side := 0
		while true:
			var keys := await Menu.handle_input(15, 10, 4, GB.A | GB.B, 2, side)
			side = Menu.current
			Menu.erase_cursor()
			if keys & GB.B:
				for k in 7:
					Text.put(15, 10 + k, Text.SPACE)
				for k in 13:
					Text.put(0, 3 + k, Text.SPACE)
				break
			if side == 0:
				await PokedexPage.new().show(sp)
				setup = true
				break
			if side == 1:
				Sound.play_cry(sp)
				continue
			if side == 2:
				await TownMap.show_nest(state, sp)
				setup = true
				break
			quit = true
			break
	# .exitPokedex: GBPalWhiteOutWithDelay3, RunDefaultPaletteCommand
	S.white_out()
	await GB.delay3()
	S.clear_sprites()
	SGB.run("DEFAULT")
