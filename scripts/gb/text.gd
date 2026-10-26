## Text engine: the charmap, PlaceString and the text command processor
## (home/text.asm, home/print_text.asm). Autoloaded as `Text`.
##
## Hangul (codes >= 0x100) is drawn 8x16: the top half goes on the row above
## the cursor row, exactly like the Korean fork's KoreanRenderGlyph.
extends Node

const CODE_NEXT := 0x4E
const CODE_LINE := 0x4F
const CODE_END := 0x50      # "@"
const CODE_PARA := 0x51
const CODE_TARGET := 0x59
const CODE_USER := 0x5A
const CODE_PLAYER := 0x52
const CODE_RIVAL := 0x53
const CODE_POKE := 0x54      # "#" -> POKé
const CODE_CONT := 0x55
const CODE_DOTS := 0x56      # "<……>"
const CODE_DONE := 0x57
const CODE_PROMPT := 0x58
const CODE_PC := 0x5B
const CODE_TM := 0x5C
const CODE_TRAINER := 0x5D
const CODE_ROCKET := 0x5E
const CODE_PKMN := 0x4A
const CODE_SCROLL := 0x4C
const CODE__CONT := 0x4B
const CODE_PAGE := 0x49
const SPACE := 0x7F
const ARROW_DOWN := 0xEE
const CURSOR := 0xED

var _codes := {}
var _maxlen := 1
var vars := {"PLAYER": "RED", "RIVAL": "BLUE"}
var ram := {}                     # wNameBuffer, wTrainerName, ... -> String
var no_delay := false             # BIT_NO_TEXT_DELAY
var single_spaced := false        # BIT_SINGLE_SPACED_LINES
var in_link_battle := false
var cursor := Vector2i(1, 14)
var last_end := Vector2i(1, 14)   # position after the last PlaceString
var _S: GBScreen
var _down_arrow_count1 := 0
var _down_arrow_count2 := 6


func _ready() -> void:
	_codes = GameData.charmap
	for k in _codes.keys():
		_maxlen = maxi(_maxlen, k.length())
	# tokens the fork spells differently from the English charmap
	if not _codes.has("<……>"):
		_codes["<……>"] = CODE_DOTS


func _screen() -> GBScreen:
	if _S == null:
		_S = GB.screen
	return _S


# --- encoding ---------------------------------------------------------------

## Longest-match tokenizer over the charmap.
func encode(s: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := 0
	var n := s.length()
	while i < n:
		var found := false
		var maxl := mini(_maxlen, n - i)
		for l in range(maxl, 0, -1):
			var tok := s.substr(i, l)
			if _codes.has(tok):
				out.append(_codes[tok])
				i += l
				found = true
				break
		if not found:
			push_warning("no charmap entry for %s" % s[i])
			out.append(SPACE)
			i += 1
	return out


## Packed tile value for a one-byte character code.
func code_tile(code: int) -> int:
	var S := _screen()
	if code >= 0x80:
		return S.tile("font", code - 0x80)
	if code >= 0x60:
		return S.tile("font_extra", code - 0x60)
	return GBScreen.BLANK


## Write one character at (x, y) on the background map.
## Atlas tile of the top half of a Hangul glyph. The font pages start at code
## $0100, so glyph index = code - 256 (128 glyphs per atlas row, two tile rows each).
static func _hangul_top_tile(code: int) -> int:
	var g := code - 256
	return (g / 128) * 256 + (g % 128)


func put(x: int, y: int, code: int) -> void:
	var S := _screen()
	if code >= 0x100:
		var top := _hangul_top_tile(code)
		S.set_bg(x, y - 1, S.tile("korean_font", top))
		S.set_bg(x, y, S.tile("korean_font", top + 128))
	else:
		S.set_bg(x, y, code_tile(code))


func put_win(x: int, y: int, code: int) -> void:
	var S := _screen()
	if code >= 0x100:
		var top := _hangul_top_tile(code)
		S.set_win(x, y - 1, S.tile("korean_font", top))
		S.set_win(x, y, S.tile("korean_font", top + 128))
	else:
		S.set_win(x, y, code_tile(code))


func put_str(x: int, y: int, s: String) -> void:
	place_string(x, y, s)


func clear_area(x: int, y: int, w: int, h: int) -> void:
	_screen().fill_bg(x, y, w, h, code_tile(SPACE))


func clear_screen() -> void:
	_screen().clear_bg(code_tile(SPACE))


## PlaceString: writes until "@" (or end of string). Returns the end position.
## Does not wait; used for menus, names and labels.
func place_string(x: int, y: int, s: String) -> Vector2i:
	var codes := encode(s)
	return place_codes(x, y, codes)


func place_codes(x: int, y: int, codes: PackedInt32Array) -> Vector2i:
	var cx := x
	var cy := y
	var row_start := x
	for code in codes:
		match code:
			CODE_END:
				break
			CODE_NEXT:
				cy += 1 if single_spaced else 2
				cx = row_start
			CODE_LINE:
				cx = 1
				cy = 16
			_:
				var expanded := _expand(code)
				if expanded.is_empty():
					put(cx, cy, code)
					cx += 1
				else:
					for c in expanded:
						put(cx, cy, c)
						cx += 1
	last_end = Vector2i(cx, cy)
	return last_end


## Dictionary characters that expand to several tiles.
func _expand(code: int) -> PackedInt32Array:
	match code:
		CODE_POKE:
			return encode("POKé")
		CODE_PLAYER:
			return encode(vars["PLAYER"])
		CODE_RIVAL:
			return encode(vars["RIVAL"])
		CODE_USER:
			# <USER>: the attacking mon ("Enemy " + nick when the enemy moves)
			return encode(vars.get("USER", ""))
		CODE_TARGET:
			return encode(vars.get("TARGET", ""))
		CODE_PC:
			return encode("PC" if GameData.lang == "en" else "컴퓨터")
		CODE_TM:
			return encode("TM" if GameData.lang == "en" else "기술머신")
		CODE_TRAINER:
			return encode("TRAINER" if GameData.lang == "en" else "트레이너")
		CODE_ROCKET:
			return encode("ROCKET" if GameData.lang == "en" else "로켓단")
		CODE_PKMN:
			return PackedInt32Array([0xE1, 0xE2])
		CODE_DOTS:
			return PackedInt32Array([0x75, 0x75])
	return PackedInt32Array()


# --- text command processor -------------------------------------------------

## PrintText: draw the message box, Delay3, then run the label at (1, 14).
func print_text(label: String) -> void:
	Menu.message_box()
	await GB.delay3()
	await print_text_no_box(label)


func print_text_no_box(label: String) -> void:
	cursor = Vector2i(1, 14)
	await run_commands(GameData.text(label))


## Run a text command list (see tools/export_data.py for the format).
func run_commands(cmds: Array) -> void:
	for cmd in cmds:
		var op: String = cmd[0]
		var arg: String = cmd[1]
		match op:
			"text", "raw":
				await _type(arg)
			"line":
				cursor = Vector2i(1, 16)
				await _type(arg)
			"next":
				cursor = Vector2i(1 if cursor.x == 1 else cursor.x, cursor.y + (1 if single_spaced else 2))
				await _type(arg)
			"cont":
				await _cont()
				await _type(arg)
			"para":
				await _para()
				await _type(arg)
			"page":
				await _page()
				await _type(arg)
			"prompt":
				await _prompt()
				return
			"done", "text_end", "text_asm":
				return
			"far":
				await run_commands(GameData.text(arg))
			"ram":
				await _type(ram.get(arg, ""))
			"text_decimal", "text_bcd":
				var var_name := arg.get_slice(",", 0).strip_edges()
				await _type(str(ram.get(var_name, "")))
			"sound":
				await Sound.text_sound(arg)
			"text_pause":
				await _pause()
			"text_low":
				cursor = Vector2i(1, 16)


## Type a string at the cursor with the letter delay.
func _type(s: String) -> void:
	var codes := encode(s)
	for code in codes:
		match code:
			CODE_END:
				return
			CODE_NEXT:
				cursor = Vector2i(1, cursor.y + (1 if single_spaced else 2))
			CODE_LINE:
				cursor = Vector2i(1, 16)
			CODE_PARA:
				await _para()
			CODE_CONT:
				await _cont()
			CODE_PROMPT:
				await _prompt()
				return
			CODE_DONE:
				return
			CODE_SCROLL:
				await _scroll_lines()
			_:
				var expanded := _expand(code)
				if expanded.is_empty():
					put(cursor.x, cursor.y, code)
					cursor.x += 1
					await _letter_delay()
				else:
					for c in expanded:
						put(cursor.x, cursor.y, c)
						cursor.x += 1
						await _letter_delay()


## PrintLetterDelay with the default options: 3 frames per letter, none while
## A or B is held, none at all when BIT_NO_TEXT_DELAY is set.
func _letter_delay() -> void:
	if no_delay:
		return
	if GB.held & (GB.A | GB.B):
		return
	await GB.frames(Settings.text_delay())   # wOptions text speed: 1 / 3 / 5 frames


func _show_arrow() -> void:
	put(18, 16, ARROW_DOWN)


func _hide_arrow() -> void:
	put(18, 16, SPACE)


## ManualTextScroll (play_sound) / WaitForTextScrollButtonPress: blink timing of the
## down arrow is reproduced exactly (it is effectively static), then wait for A or B.
func wait_scroll_button(play_sound: bool = true) -> void:
	if in_link_battle:
		await GB.frames(65)
		return
	var S := _screen()
	_down_arrow_count1 = 0
	_down_arrow_count2 = 6
	while true:
		await GB.frame
		_handle_down_arrow_blink()
		if GB.joy5 & (GB.A | GB.B):
			break
	if play_sound:
		Sound.play_sfx("SFX_PRESS_AB")


func _handle_down_arrow_blink() -> void:
	var S := _screen()
	var on := S.get_bg(18, 16) == code_tile(ARROW_DOWN)
	if on:
		_down_arrow_count1 = (_down_arrow_count1 - 1) & 0xFF
		if _down_arrow_count1 != 0:
			return
		_down_arrow_count2 -= 1
		if _down_arrow_count2 != 0:
			return
		_hide_arrow()
		_down_arrow_count1 = 0xFF
		_down_arrow_count2 = 6
	else:
		if _down_arrow_count1 == 0:
			return
		_down_arrow_count1 -= 1
		if _down_arrow_count1 != 0:
			return
		_down_arrow_count1 = (_down_arrow_count1 - 1) & 0xFF
		_down_arrow_count2 -= 1
		if _down_arrow_count2 != 0:
			return
		_down_arrow_count2 = 6
		_show_arrow()


func _prompt() -> void:
	if not in_link_battle:
		_show_arrow()
	await GB.delay3()
	await wait_scroll_button()
	_hide_arrow()


func _para() -> void:
	_show_arrow()
	await GB.delay3()
	await wait_scroll_button()
	clear_area(1, 13, 18, 4)
	await GB.frames(20)
	cursor = Vector2i(1, 14)


func _page() -> void:
	_show_arrow()
	await GB.delay3()
	await wait_scroll_button()
	clear_area(1, 10, 18, 7)
	await GB.frames(20)
	cursor = Vector2i(1, 11)


func _cont() -> void:
	_show_arrow()
	await GB.delay3()
	await wait_scroll_button()
	_hide_arrow()
	await _scroll_lines()


func _scroll_lines() -> void:
	await scroll_text_up_one_line()
	await scroll_text_up_one_line()
	cursor = Vector2i(1, 16)


## ScrollTextUpOneLine: rows 14-16 move up one row, row 16 is cleared, 5 frames.
func scroll_text_up_one_line() -> void:
	var S := _screen()
	for y in range(13, 16):
		for x in 20:
			S.set_bg(x, y, S.get_bg(x, y + 1))
	for x in range(1, 19):
		S.set_bg(x, 16, code_tile(SPACE))
	await GB.frames(5)


func _pause() -> void:
	if GB.held & (GB.A | GB.B):
		return
	await GB.frames(30)


## HoldTextDisplayOpen: keep the box while A is held (used after DisplayTextID).
func hold_text_display_open() -> void:
	while GB.held & GB.A:
		await GB.frame
