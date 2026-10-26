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
			ow.map_pal_offset = 0
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
				await GB.frames(60)
				await _white_out_delay3()
				return "close"
			await Text.print_text("_CannotUseTeleportNowText")
			return "loop"
		"CUT":
			if not badges & (1 << CASCADE):
				return await _new_badge_required()
		"FLY":
			if not badges & (1 << THUNDER):
				return await _new_badge_required()
		"SURF":
			if not badges & (1 << SOUL):
				return await _new_badge_required()
		"STRENGTH":
			if not badges & (1 << RAINBOW):
				return await _new_badge_required()
	# the moves of later chapters
	await Text.print_text("_ItemUseNotTimeText")
	return "loop"


## ItemUseEscapeRope (Dig uses it as a pseudo item: nothing is removed and the map view
## is not reloaded). Only in the FOREST, CEMETERY, CAVERN, FACILITY and INTERIOR tilesets.
static func escape_rope(state: GameState, ow, pseudo: String = "") -> bool:
	if ow.map_id == "AGATHAS_ROOM" or not ow.map["tileset"] in ["FOREST", "CEMETERY", "CAVERN", "FACILITY", "INTERIOR"]:
		await Text.print_text("_ItemUseNotTimeText")
		return false
	ow.fly_warp = true
	ow.escape_warp = true
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
