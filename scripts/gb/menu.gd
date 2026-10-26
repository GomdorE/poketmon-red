## Text boxes and cursor menus (home/text.asm TextBoxBorder, home/window.asm
## HandleMenuInput, home/yes_no.asm). Autoloaded as `Menu`.
extends Node

const TOP_LEFT := 0x79
const HORIZ := 0x7A
const TOP_RIGHT := 0x7B
const VERT := 0x7C
const BOTTOM_LEFT := 0x7D
const BOTTOM_RIGHT := 0x7E
const SPACE := 0x7F

var current := 0          # wCurrentMenuItem
var last := 0             # wLastMenuItem
var cursor_x := 1
var cursor_y := 2
var wrap := false         # wMenuWrappingEnabled
var cursor_pos := Vector2i(-1, -1)


## TextBoxBorder: a box with inner size w x h whose top-left corner is (x, y).
func draw_box(x: int, y: int, w: int, h: int) -> void:
	Text.put(x, y, TOP_LEFT)
	for i in w:
		Text.put(x + 1 + i, y, HORIZ)
	Text.put(x + w + 1, y, TOP_RIGHT)
	for j in h:
		Text.put(x, y + 1 + j, VERT)
		for i in w:
			Text.put(x + 1 + i, y + 1 + j, SPACE)
		Text.put(x + w + 1, y + 1 + j, VERT)
	Text.put(x, y + h + 1, BOTTOM_LEFT)
	for i in w:
		Text.put(x + 1 + i, y + h + 1, HORIZ)
	Text.put(x + w + 1, y + h + 1, BOTTOM_RIGHT)


## The standard dialogue box (MESSAGE_BOX: 0,12 - 19,17).
func message_box() -> void:
	draw_box(0, 12, 18, 4)


func place_cursor(x: int, y: int) -> void:
	cursor_pos = Vector2i(x, y)
	Text.put(x, y, Text.CURSOR)


func erase_cursor() -> void:
	if cursor_pos.x >= 0:
		Text.put(cursor_pos.x, cursor_pos.y, SPACE)
		cursor_pos = Vector2i(-1, -1)


var no_button_sound := false   # wMiscFlags BIT_NO_MENU_BUTTON_SOUND


## HandleMenuInput: a vertical cursor menu. `items` is the number of entries,
## `watched` the keys that end the menu (returned as a mask). The cursor is
## left on screen; call erase_cursor() when the menu closes.
func handle_input(x: int, y: int, items: int, watched: int, spacing: int = 2, start: int = 0, positions: Array = []) -> int:
	cursor_x = x
	cursor_y = y
	current = start
	last = start
	var pos := positions.duplicate()
	if pos.is_empty():
		for i in items:
			pos.append(Vector2i(x, y + spacing * i))
	place_cursor(pos[current].x, pos[current].y)
	while true:
		await GB.frame
		var keys := GB.joy5
		if keys == 0:
			continue
		if keys & GB.UP:
			if current > 0:
				current -= 1
			elif wrap:
				current = items - 1
		elif keys & GB.DOWN:
			if current < items - 1:
				current += 1
			elif wrap:
				current = 0
		if current != last:
			Text.put(pos[last].x, pos[last].y, SPACE)
			place_cursor(pos[current].x, pos[current].y)
			last = current
		if keys & watched:
			if keys & (GB.A | GB.B) and not no_button_sound:
				Sound.play_sfx("SFX_PRESS_AB")
			return keys & watched
	return 0


## A move list as the original places it (single-spaced names at (x + 1, y + i),
## the cursor in column x) and the cursor position of each entry.
## PH-INTENT: the Korean 8x16 Hangul glyphs need two rows, so single-spaced names
## overwrite each other (the Korean ROM does exactly that and the user counts it as
## broken). In Korean the four moves go into a 2x2 grid inside the same 4-row box:
## rows y + 1 and y + 3, the second column starting at x + 7 (moved left/right when a
## 7-letter name needs it). Up/Down still walk the list in order (column by column).
func place_move_list(x: int, y: int, names: Array) -> Array:
	var pos: Array = []
	if GameData.lang != "ko":
		Text.single_spaced = true
		for i in names.size():
			Text.place_string(x + 1, y + i, str(names[i]))
			pos.append(Vector2i(x, y + i))
		Text.single_spaced = false
		return pos
	var len0 := 0
	var len1 := 0
	for i in names.size():
		var n := Text.encode(str(names[i])).size()
		if i < 2:
			len0 = maxi(len0, n)
		else:
			len1 = maxi(len1, n)
	var c1 := clampi(x + 7, x + 1 + len0, x + 13 - len1)
	for i in names.size():
		var cx := x if i < 2 else c1
		var cy := y + 1 + 2 * (i % 2)
		Text.place_string(cx + 1, cy, str(names[i]))
		pos.append(Vector2i(cx, cy))
	return pos


## YesNoChoice: two option box at (14, 7). Returns true for YES.
func yes_no(x: int = 14, y: int = 7, heal_cancel: bool = false) -> bool:
	var S: GBScreen = GB.screen
	var saved := S.snapshot_bg()
	var ko := GameData.lang == "ko"
	if heal_cancel:
		# HEAL_CANCEL_MENU (the Pokémon Center)
		draw_box(x, y, 6, 3)
		Text.place_string(x + 2, y + 1, "회복" if ko else "HEAL")
		Text.place_string(x + 2, y + 3, "취소" if ko else "CANCEL")
	else:
		draw_box(x, y, 4, 3)
		Text.place_string(x + 2, y + 1, "예" if ko else "YES")
		Text.place_string(x + 2, y + 3, "아니오" if ko else "NO")
	var keys := await handle_input(x + 1, y + 1, 2, GB.A | GB.B)
	var yes := (keys & GB.A) != 0 and current == 0
	erase_cursor()
	S.restore_bg(saved)
	return yes
