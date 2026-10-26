## The two status screen pages (engine/pokemon/status_screen.asm StatusScreen and
## StatusScreen2) for a party Pokémon.
class_name StatusScreen
extends RefCounted


## Tiles $62-$7f while the status screen is up: LoadHpBarAndStatusTilePatterns puts
## font_battle_extra there, then BattleHudTiles1 ($6d-$6f), BattleHudTiles2 ($78),
## BattleHudTiles3 ($76-$77) and the bold P ($72) are copied over the same glyphs.
static func _t(id: int) -> int:
	var S: GBScreen = GB.screen
	if id >= 0x6D and id <= 0x6F:
		return S.tile("battle_hud_1", id - 0x6D)
	if id == 0x78:
		return S.tile("battle_hud_2", 0)
	if id == 0x76 or id == 0x77:
		return S.tile("battle_hud_3", id - 0x76)
	if id == 0x72:
		return S.tile("font_p", 0)
	return MonHud.hp_tile(id)


## PlaceString with the $62-$7f codes ("<ID>", "№", "<to>") taken from the loaded tiles.
## Right-aligned text ending at column 19 (Korean status screen values).
static func _place_right(y: int, s: String) -> void:
	var w := 0
	for code in Text.encode(s):
		w += 2 if code >= 0x100 else 1
	Text.place_string(maxi(0, 20 - w), y, s)


static func _place(x: int, y: int, s: String) -> void:
	var S: GBScreen = GB.screen
	var cx := x
	var cy := y
	for code in Text.encode(s):
		if code == Text.CODE_NEXT:
			cy += 2
			cx = x
		elif code >= 0x62 and code <= 0x7F:
			S.set_bg(cx, cy, _t(code))
			cx += 1
		else:
			Text.put(cx, cy, code)
			cx += 1


## DrawLineBox: b vertical bars down from (x, y), the corner, c horizontal bars
## leftwards and the half-arrow line end.
static func _line_box(x: int, y: int, b: int, c: int) -> void:
	var S: GBScreen = GB.screen
	for k in b:
		S.set_bg(x, y + k, _t(0x78))
	S.set_bg(x, y + b, _t(0x77))
	for k in c:
		S.set_bg(x - 1 - k, y + b, _t(0x76))
	S.set_bg(x - 1 - c, y + b, _t(0x6F))


static func show(state: GameState, index: int) -> void:
	var S: GBScreen = GB.screen
	var m: PartyMon = state.party[index]
	var ko := GameData.lang == "ko"
	var data: Dictionary = GameData.pokemon[m.species]
	# GBPalWhiteOutWithDelay3, ClearScreen
	S.white_out()
	await GB.delay3()
	Text.clear_screen()
	S.clear_sprites()
	# page 1
	_line_box(19, 1, 6, 10)
	S.set_bg(1, 7, _t(0x74))   # №
	Text.put(2, 7, 0xF2)       # <DOT>
	_line_box(19, 9, 8, 6)
	# Korean: the 8x16 labels sit on rows 9-16 (top halves on the odd rows) with the
	# values beside them instead of below (the Korean ROM overlaps them)
	if ko:
		_place(10, 10, "타입1<NEXT>타입2<NEXT>번호<NEXT>어버이")
	else:
		_place(10, 9, "TYPE1/<NEXT>TYPE2/<NEXT><ID>№/<NEXT>OT/")
	var px := MonHud.hp_pixels(m.hp, m.max_hp)
	MonHud.draw_hp_bar(11, 3, px, false)
	Text.place_string(12, 4, "%3d/%3d" % [m.hp, m.max_hp])
	SGB.run("STATUS_SCREEN", {"species": m.species, "hp": MonHud.bar_color(px)})
	var st := MonHud.status_text(m)
	Text.place_string(16, 6, st if st != "" else ("정상" if ko else "OK"))
	Text.place_string(9, 6, "상태/" if ko else "STATUS/")
	MonHud.draw_level(14, 2, m.level)
	Text.place_string(3, 7, "%03d" % int(data["dex"]))
	# PrintMonType
	var types: Array = data["types"]
	if ko:
		# values right-aligned beside the labels; a six-tile type name covers the label's digit
		_place_right(10, GameData.type_name(types[0]))
		if types[1] != types[0]:
			_place_right(12, GameData.type_name(types[1]))
		_place_right(14, "%05d" % state.player_id)
		_place_right(16, state.player_name)
	else:
		Text.place_string(11, 10, GameData.type_name(types[0]))
		if types[1] != types[0]:
			Text.place_string(11, 12, GameData.type_name(types[1]))
		Text.place_string(12, 16, state.player_name)
		Text.place_string(12, 14, "%05d" % state.player_id)
	Text.place_string(9, 1, m.nickname)
	# PrintStatsBox (STATUS_SCREEN_STATS_BOX)
	Menu.draw_box(0, 8, 8, 8)
	var names := ["공격", "방어", "스피드", "특수"] if ko else ["ATTACK", "DEFENSE", "SPEED", "SPECIAL"]
	var keys := ["atk", "def", "spd", "spc"]
	for i in 4:
		if ko:
			# labels one row lower (top halves on the odd rows), values right-aligned beside them
			Text.place_string(1, 10 + i * 2, names[i])
			var v := str(int(m.stats[keys[i]]))
			Text.place_string(9 - v.length(), 10 + i * 2, v)
		else:
			Text.place_string(1, 9 + i * 2, names[i])
			Text.place_string(6, 10 + i * 2, "%3d" % int(m.stats[keys[i]]))
	await GB.delay3()
	S.normal_pals()
	Title.draw_mon_pic(S, m.species, 1, 1, true)
	Sound.play_cry(m.species)
	await Sound.wait_for_sfx()
	await Text.wait_scroll_button(false)
	# page 2 (StatusScreen2)
	Text.clear_area(9, 2, 10, 5)
	S.set_bg(19, 3, _t(0x78))
	Menu.draw_box(0, 8, 18, 8)
	for i in 4:
		var y := 9 + i * 2
		if i < m.moves.size():
			var mv: Dictionary = m.moves[i]
			Text.place_string(2, y, GameData.move_name(mv.move))
			S.set_bg(11, y + 1, _t(0x72))
			S.set_bg(12, y + 1, _t(0x72))
			Text.place_string(14, y + 1, "%2d/%2d" % [int(mv.pp), int(mv.max_pp)])
		else:
			Text.place_string(2, y, "-")
			Text.place_string(11, y + 1, "--")
	Text.place_string(12, 4, "%7d" % m.exp)
	var to_next := 0
	if m.level < 100:
		to_next = PartyMon.exp_for_level(data["growth"], m.level + 1) - m.exp
	if ko:
		# "경험치" on rows 2-3, "다음레벨" on rows 5-6, the next-level line on row 7
		Text.place_string(9, 3, "경험치")
		Text.place_string(9, 6, "다음레벨")
		S.set_bg(14, 7, _t(0x70))   # <to>
		MonHud.draw_level(16, 7, mini(m.level + 1, 100))
		Text.place_string(8, 7, "%6d" % to_next)
	else:
		Text.place_string(9, 3, "EXP POINTS<NEXT>LEVEL UP")
		S.set_bg(14, 6, _t(0x70))   # <to>
		MonHud.draw_level(16, 6, mini(m.level + 1, 100))
		Text.place_string(7, 6, "%7d" % to_next)
	Text.clear_area(9, 0, 10, 2)
	Text.place_string(9, 1, GameData.mon_name(m.species))
	await GB.delay3()
	await Text.wait_scroll_button(false)
	S.white_out()
	Text.clear_screen()
