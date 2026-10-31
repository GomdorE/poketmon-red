## Field moves from the start menu's POKéMON list (engine/menus/start_sub_menus.asm
## StartMenu_Pokemon .choseOutOfBattleMove, engine/menus/text_box.asm
## DisplayFieldMoveMonMenu / GetMonFieldMoves).
class_name FieldMoves
extends RefCounted

# FieldMoveDisplayData: move -> [FieldMoveNames index, leftmost X]
const DISPLAY := {
	"CUT": [1, 0x0C], "FLY": [2, 0x0C], "SURF": [4, 0x0C], "STRENGTH": [5, 0x0A],
	"FLASH": [6, 0x0C], "DIG": [7, 0x0C], "TELEPORT": [8, 0x0A], "SOFTBOILED": [9, 0x08],
}
const NAMES_EN := ["", "CUT", "FLY", "", "SURF", "STRENGTH", "FLASH", "DIG", "TELEPORT", "SOFTBOILED"]
const NAMES_KO := ["", "풀베기", "공중날기", "", "파도타기", "괴력", "플래시", "구멍파기", "순간이동", "알낳기"]
# wObtainedBadges bits
const BOULDER := 0
const CASCADE := 1
const THUNDER := 2
const RAINBOW := 3
const SOUL := 4


## GetMonFieldMoves: the field moves of a party mon in move order, and the leftmost X.
static func of(mon: PartyMon) -> Dictionary:
	var moves: Array = []
	var left := 12
	for m in mon.moves:
		var mv: String = m.move
		if DISPLAY.has(mv) and moves.size() < 4:
			moves.append(mv)
			left = mini(left, int(DISPLAY[mv][1]))
	return {"moves": moves, "left": left}


static func name_of(move: String) -> String:
	var i: int = DISPLAY[move][0]
	return NAMES_KO[i] if GameData.lang == "ko" else NAMES_EN[i]


## The FIELD_MOVE_MON_MENU box: field move names above STATS / SWITCH / CANCEL.
## Returns the cursor X and the top item Y.
static func draw_menu(fm: Dictionary) -> Vector2i:
	var ko := GameData.lang == "ko"
	var entries := ["상태", "교체", "취소"] if ko else ["STATS", "SWITCH", "CANCEL"]
	var n: int = fm.moves.size()
	if n == 0:
		Menu.draw_box(11, 11, 7, 5)
		for i in 3:
			Text.place_string(13, 12 + i * 2, entries[i])
		return Vector2i(12, 12)
	var left: int = fm.left
	# hlcoord (left - 1, 11), moved up 2 rows per field move and one more; b = 5 + 2n + 1, c = 18 - (left - 1)
	var top := 11 - 2 * n - 1
	Menu.draw_box(left - 1, top, 18 - (left - 1), 5 + 2 * n + 1)
	var y := 12 - 2 * n
	for mv in fm.moves:
		Text.place_string(left + 1, y, name_of(mv))
		y += 2
	for i in 3:
		Text.place_string(left + 1, 12 + i * 2, entries[i])
	return Vector2i(left, 12 - 2 * n)


## .choseOutOfBattleMove. Returns "close" when the start menu closes (back to the map),
## "loop" to return to the party menu.
static func use(state: GameState, ow, idx: int, move: String) -> String:
	var mon: PartyMon = state.party[idx]
	Text.ram["wNameBuffer"] = mon.nickname
	var badges := state.badges
	match move:
		"FLASH":
			if not badges & (1 << BOULDER):
				return await _new_badge_required()
			ow.set_map_pal_offset(0)
			await Text.print_text("_FlashLightsAreaText")
			await _white_out_delay3()
			return "close"
		"DIG":
			if not await escape_rope(state, ow, "DIG"):
				return "loop"
			await _white_out_delay3()
			return "close"
		"TELEPORT":
			if ow.is_outside_map():
				await Text.print_text("_WarpToLastPokemonCenterText")
				ow.fly_warp = true
				ow.escape_warp = true
				ow.no_battles = false
				await GB.frames(60)
				await _white_out_delay3()
				return "close"
			await Text.print_text("_CannotUseTeleportNowText")
			return "loop"
		"CUT":
			if not badges & (1 << CASCADE):
				return await _new_badge_required()
			return "close" if await used_cut(ow) else "loop"
		"FLY":
			if not badges & (1 << THUNDER):
				return await _new_badge_required()
			if not ow.is_outside_map():
				await Text.print_text("_CannotFlyHereText")
				return "loop"
			# ChooseFlyDestination
			ow.no_battles = false
			var dest: String = await TownMap.choose_fly_destination(state, ow)
			if dest != "":
				ow.fly_destination = dest
				ow.fly_warp = true
				return "close"
			SGB.run("DEFAULT")
			return "fresh"
		"SURF":
			if not badges & (1 << SOUL):
				return await _new_badge_required()
			# IsSurfingAllowed: not while forced to ride the bike (Seafoam's current: a later chapter)
			if state.always_on_bike:
				await Text.print_text("_CyclingIsFunText")
				return "loop"
			if not await use_surfboard(state, ow):
				return "loop"
			await _white_out_delay3()
			return "close"
		"STRENGTH":
			if not badges & (1 << RAINBOW):
				return await _new_badge_required()
			# PrintStrengthText: UsedStrengthText (+ the mon's cry), CanMoveBouldersText
			ow.strength_active = true
			await Text.print_text("_UsedStrengthText")
			Sound.play_cry(mon.species)
			await GB.delay3()
			await Text.print_text("_CanMoveBouldersText")
			await _white_out_delay3()
			return "close"
	# the moves of later chapters
	await Text.print_text("_ItemUseNotTimeText")
	return "loop"


# data/tilesets/cut_tree_blocks.asm: block with the tree -> block after the cut
const CUT_TREE_BLOCK_SWAPS := {0x32: 0x6D, 0x33: 0x6C, 0x34: 0x6F, 0x35: 0x4C, 0x60: 0x6E, 0x0B: 0x0A,
	0x3C: 0x35, 0x3F: 0x35, 0x3D: 0x36}
# CutAnimationOffsets [x, y] from the player's sprite, by facing
const CUT_OFFSETS := {Overworld.FACE_DOWN: [8, 36], Overworld.FACE_UP: [8, 4], Overworld.FACE_LEFT: [-8, 20], Overworld.FACE_RIGHT: [24, 20]}


static func _byte_pal(b: int) -> PackedInt32Array:
	return PackedInt32Array([b & 3, (b >> 2) & 3, (b >> 4) & 3, (b >> 6) & 3])


## UsedCut (engine/overworld/cut.asm + cut2.asm AnimCut): a cuttable tree ($3D) or grass
## ($52) on the overworld tileset, the gym tree ($50) on the gym tileset. The text, the
## OAM animation (tree halves split / leaves scatter, OBP1 flickering), the block swap
## (in the loaded map only: trees grow back when the map is reloaded) and SFX_CUT.
static func used_cut(ow) -> bool:
	var S: GBScreen = GB.screen
	var d: Vector2i = ow._facing_delta()
	var front: int = ow._tile_id_under(ow.player.x + d.x, ow.player.y + d.y)
	var ts: String = ow.map["tileset"]
	var can := (ts == "OVERWORLD" and (front == 0x3D or front == 0x52)) or (ts == "GYM" and front == 0x50)
	if not can:
		await Text.print_text("_NothingToCutText")
		return false
	var grass := front == 0x52
	Text.no_delay = true
	S.white_out()
	await GB.delay3()
	# RestoreScreenTilesAndReloadTilePatterns (RunDefaultPaletteCommand), LoadGBPal, the map view
	S.clear_sprites()
	ow._render()
	SGB.run("DEFAULT")
	await GB.delay3()
	S.normal_pals()
	await GB.delay3()
	await Text.print_text("_UsedCutText")
	Text.no_delay = false
	ow._render()
	# InitCutAnimOAM + WriteCutOrBoulderDustAnimationOAMBlock (OAM 36-39)
	S.obp1 = _byte_pal(0xE4)
	var off: Array = CUT_OFFSETS[ow.player.facing]
	var x: int = 0x40 + int(off[0]) - 8
	var y: int = 0x3C + int(off[1]) - 16
	var spr: Array = []
	if grass:
		var leaf := S.tile("move_anim_1", 6)
		var flips := [[true, false], [false, true], [true, false], [false, true]]
		for i in 4:
			spr.append({"x": x + (i % 2) * 8, "y": y + (i / 2) * 8, "v": leaf, "xf": flips[i][0], "yf": flips[i][1]})
	else:
		var tiles := [0x2D, 0x2E, 0x3D, 0x3E]
		for i in 4:
			spr.append({"x": x + (i % 2) * 8, "y": y + (i / 2) * 8, "v": S.tile(ow.ts_sheet, tiles[i]), "xf": false, "yf": false})
	# ReplaceTreeTileBlock + RedrawMapView
	var bx: int = (ow.player.x + d.x) >> 1
	var by: int = (ow.player.y + d.y) >> 1
	var w: int = ow.map["width"]
	var block: int = ow.map["blocks"][by * w + bx]
	if ow.cut_blocks.has(Vector2i(bx, by)):
		block = ow.cut_blocks[Vector2i(bx, by)]
	if CUT_TREE_BLOCK_SWAPS.has(block):
		var nb: int = CUT_TREE_BLOCK_SWAPS[block]
		ow.cut_blocks[Vector2i(bx, by)] = nb
		ow._put_block(bx, by, nb, ow.tileset)
	ow._render()
	_draw_cut_oam(S, spr)
	# AnimCut
	if grass:
		for k in 2:
			for half in 2:
				for f in 8:
					var dx := [1, 2, -2, -1]
					for i in 4:
						spr[i].x += dx[i]
					S.obp1 = _byte_pal(_pal_byte(S.obp1) ^ 0x64)
					_draw_cut_oam(S, spr)
					await GB.frame
				# AnimCut_SwapOAMEntries: 36/37 <-> 38/39
				spr = [spr[2], spr[3], spr[0], spr[1]]
				_draw_cut_oam(S, spr)
			for i in 4:
				spr[i].y += 2
			_draw_cut_oam(S, spr)
	else:
		for f in 8:
			spr[0].x += 1
			spr[1].x += 1
			spr[2].x -= 1
			spr[3].x -= 1
			S.obp1 = _byte_pal(_pal_byte(S.obp1) ^ 0x64)
			_draw_cut_oam(S, spr)
			await GB.frame
	Sound.play_sfx("SFX_CUT")
	for i in 4:
		S.set_sprite(36 + i, -16, -16, GBScreen.BLANK)
	S.normal_pals()
	ow._render()
	return true


static func _pal_byte(p: PackedInt32Array) -> int:
	return p[0] | (p[1] << 2) | (p[2] << 4) | (p[3] << 6)


static func _draw_cut_oam(S: GBScreen, spr: Array) -> void:
	for i in 4:
		var e: Dictionary = spr[i]
		S.set_sprite(36 + i, int(e.x), int(e.y), int(e.v), 1, bool(e.xf), bool(e.yf))


# data/tilesets/water_tilesets.asm
const WATER_TILESETS := ["OVERWORLD", "FOREST", "DOJO", "GYM", "SHIP", "SHIP_PORT", "CAVERN", "FACILITY", "PLATEAU"]


## IsNextTileShoreOrWater.
static func is_next_tile_shore_or_water(ow) -> bool:
	var d: Vector2i = ow._facing_delta()
	var front: int = ow._tile_id_under(ow.player.x + d.x, ow.player.y + d.y)
	var ts: String = ow.map["tileset"]
	return ts in WATER_TILESETS and (front == 0x14 or (ts != "SHIP_PORT" and (front == 0x48 or front == 0x32)))


## ItemUseBicycle: on or off the bike (not while surfing), the bike music, the text.
static func use_bicycle(state: GameState, ow) -> bool:
	if state.walk_bike_surf == 2:
		await Text.print_text("_ItemUseNotTimeText")
		return false
	Text.ram["wStringBuffer"] = GameData.item_name("BICYCLE")
	var cmds: Array
	if state.walk_bike_surf == 1:
		ow.reload_map_view()
		ow.set_walk_bike_surf(0)
		await Sound.play_default_music()
		cmds = [["far", "_GotOffBicycleText1"], ["text_low", ""], ["far", "_GotOffBicycleText2"], ["text_end", ""]]
	else:
		if not ow.is_bike_riding_allowed():
			await Text.print_text("_NoCyclingAllowedHereText")
			return false
		ow.reload_map_view()
		ow.set_walk_bike_surf(1)
		await Sound.play_default_music()
		cmds = [["far", "_GotOnBicycleText1"], ["text_low", ""], ["far", "_GotOnBicycleText2"], ["text_end", ""]]
	ow._render()
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(cmds)
	return true


## ItemUseSurfboard: onto the water in front (one simulated step, the surf music,
## "<PLAYER> got on <MON>!"), or ashore when already surfing.
static func use_surfboard(state: GameState, ow) -> bool:
	var d: Vector2i = ow._facing_delta()
	var front: int = ow._tile_id_under(ow.player.x + d.x, ow.player.y + d.y)
	var standing: int = ow._tile_id_under(ow.player.x, ow.player.y)
	var dir: int = {Overworld.FACE_UP: GB.UP, Overworld.FACE_DOWN: GB.DOWN, Overworld.FACE_LEFT: GB.LEFT}.get(ow.player.facing, GB.RIGHT)
	if state.walk_bike_surf == 2:
		# .tryToStopSurfing
		if ow._sprite_blocks(ow.player.x + d.x, ow.player.y + d.y) \
				or ow._tile_pair_collision(standing, front, Overworld.TILE_PAIR_COLLISIONS_WATER) \
				or not front in ow.tileset["collision"]:
			await Text.print_text("_SurfingNoPlaceToGetOffText")
			return false
		ow.simulate([dir])
		ow.set_walk_bike_surf(0)
		ow.joy_ignore = 0xFF
		await Sound.play_default_music()
		return true
	# IsNextTileShoreOrWater
	var ts: String = ow.map["tileset"]
	var water := ts in WATER_TILESETS and (front == 0x14 or (ts != "SHIP_PORT" and (front == 0x48 or front == 0x32)))
	if not water or ow._tile_pair_collision(standing, front, Overworld.TILE_PAIR_COLLISIONS_WATER):
		await Text.print_text("_NoSurfingHereText")
		return false
	ow.simulate([dir])
	ow.set_walk_bike_surf(2)
	await Sound.play_default_music()
	await Text.print_text("_SurfingGotOnText")
	return true


## ItemUseEscapeRope (Dig uses it as a pseudo item: nothing is removed and the map view
## is not reloaded). Only in the FOREST, CEMETERY, CAVERN, FACILITY and INTERIOR tilesets.
static func escape_rope(state: GameState, ow, pseudo: String = "") -> bool:
	if ow.map_id == "AGATHAS_ROOM" or not ow.map["tileset"] in ["FOREST", "CEMETERY", "CAVERN", "FACILITY", "INTERIOR"]:
		await Text.print_text("_ItemUseNotTimeText")
		return false
	ow.fly_warp = true
	ow.escape_warp = true
	ow.no_battles = false
	state.events.erase("EVENT_IN_SAFARI_ZONE")
	if pseudo != "":
		return true
	ow.reload_map_view()
	await GB.frames(30)
	state.remove_item("ESCAPE_ROPE", 1)
	return true


static func _new_badge_required() -> String:
	await Text.print_text("_NewBadgeRequiredText")
	return "loop"


## GBPalWhiteOutWithDelay3.
static func _white_out_delay3() -> void:
	GB.screen.white_out()
	await GB.delay3()
