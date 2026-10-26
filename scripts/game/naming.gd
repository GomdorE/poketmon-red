## The alphabet naming screen (engine/menus/naming_screen.asm).
class_name NamingScreen
extends RefCounted

enum Kind { PLAYER, RIVAL, MON }

const UPPER := ["ABCDEFGHI", "JKLMNOPQR", "STUVWXYZ ", "×():;[]<PK><MN>", "-?!♂♀/<DOT>,<ED>"]
const LOWER := ["abcdefghi", "jklmnopqr", "stuvwxyz ", "×():;[]<PK><MN>", "-?!♂♀/<DOT>,<ED>"]
const ED_CODE := 0xF0
const UNDERSCORE := 0x76
const RAISED_UNDERSCORE := 0x77

var S: GBScreen
var kind := Kind.PLAYER
var lower_case := false
var name_codes := PackedInt32Array()
var row := 1        # wCurrentMenuItem: 1-5 letters, 6 case switch
var col_x := 1      # wTopMenuItemX: 1, 3, ... 17
var max_len := 7    # PLAYER_NAME_LENGTH - 1
var submit := false
var letters: Array = []   # 5 rows of 9 codes
var mon_species := ""     # wCurPartySpecies for NAME_MON_SCREEN


func run(which: Kind, species: String = "") -> String:
	S = GB.screen
	kind = which
	mon_species = species
	max_len = 10 if kind == Kind.MON else 7
	Text.no_delay = true
	S.white_out()
	await GB.delay3()
	Text.clear_screen()
	S.clear_sprites()
	SGB.run("GENERIC")
	Menu.draw_box(0, 4, 18, 9)
	_print_naming_text()
	row = 1
	col_x = 1
	name_codes = PackedInt32Array()
	submit = false
	lower_case = false
	await _print_alphabet()
	S.normal_pals()
	while true:
		if submit:
			break
		_print_nickname_and_underscores()
		Menu.place_cursor(col_x, 3 + 2 * row)
		# input loop
		var keys := 0
		while keys == 0:
			await GB.frame
			keys = GB.joy5
		if keys & GB.A:
			_pressed_a()
		elif keys & GB.B:
			if name_codes.size() > 0:
				name_codes.resize(name_codes.size() - 1)
		elif keys & GB.START:
			submit = true
		elif keys & GB.SELECT:
			lower_case = not lower_case
			Menu.erase_cursor()
			await _print_alphabet()
			continue
		elif keys & GB.RIGHT:
			if row != 6:
				col_x = 1 if col_x == 17 else col_x + 2
		elif keys & GB.LEFT:
			if row != 6:
				col_x = 17 if col_x == 1 else col_x - 2
		elif keys & GB.UP:
			row -= 1
			if row == 0:
				row = 6
				col_x = 1
		elif keys & GB.DOWN:
			row += 1
			if row == 7:
				row = 1
			elif row == 6:
				col_x = 1
		if keys & GB.A and _case_switched:
			_case_switched = false
			Menu.erase_cursor()
			await _print_alphabet()
			continue
		Menu.erase_cursor()
	# .submitNickname
	S.white_out()
	await GB.delay3()
	Text.clear_screen()
	S.clear_sprites()
	S.normal_pals()
	Text.no_delay = false
	SGB.run("DEFAULT")
	return _codes_to_string()


var _case_switched := false


func _pressed_a() -> void:
	if row == 5 and col_x == 17:
		submit = true
		return
	if row == 6 and col_x == 1:
		lower_case = not lower_case
		_case_switched = true
		return
	var code: int = letters[row - 1][(col_x - 1) / 2]
	if name_codes.size() < max_len:
		name_codes.append(code)
		Sound.play_sfx("SFX_PRESS_AB")


func _print_naming_text() -> void:
	if kind == Kind.MON:
		# PrintNamingText (NAME_MON_SCREEN): the species name at (4, 1), "NICKNAME?" at (1, 3);
		# the party icon sprite of the species sits at (0, 1)
		Text.place_string(4, 1, GameData.mon_name(mon_species))
		Text.place_string(1, 3, "별명?" if GameData.lang == "ko" else "NICKNAME?")
		return
	if GameData.lang == "ko":
		var head := "당신의 " if kind == Kind.PLAYER else "라이벌의 "
		var end := Text.place_string(0, 1, head)
		Text.place_string(end.x, 1, "이름?")
	else:
		var head := "YOUR " if kind == Kind.PLAYER else "RIVAL's "
		var end := Text.place_string(0, 1, head)
		Text.place_string(end.x, 1, "NAME?")


## PrintAlphabet: 5 rows of 9 letters at (2, 5), one blank column between
## letters, two rows apart; then the case switch label at (2, 15).
func _print_alphabet() -> void:
	var rows: Array = LOWER if lower_case else UPPER
	letters = []
	for r in 5:
		var codes := Text.encode(rows[r])
		letters.append(codes)
		for c in 9:
			var code: int = codes[c]
			var tile: int
			if code == ED_CODE:
				tile = S.tile("font_ed", 0)
			else:
				tile = Text.code_tile(code)
			S.set_bg(2 + c * 2, 5 + r * 2, tile)
	Text.clear_area(2, 15, 12, 1)
	Text.place_string(2, 15, "lower case" if not lower_case else "UPPER CASE")
	await GB.delay3()


## PrintNicknameAndUnderscores: the name at (10, 2), underscores at (10, 3).
func _print_nickname_and_underscores() -> void:
	Text.clear_area(10, 2, 10, 1)
	var x := 10
	for code in name_codes:
		Text.put(x, 2, code)
		x += 1
	for i in max_len:
		S.set_bg(10 + i, 3, Text.code_tile(UNDERSCORE))
	if name_codes.size() == max_len:
		# all spaces filled: force the cursor onto ED, keep the last underscore raised
		Menu.erase_cursor()
		col_x = 17
		row = 5
		S.set_bg(10 + max_len - 1, 3, Text.code_tile(RAISED_UNDERSCORE))
	else:
		S.set_bg(10 + name_codes.size(), 3, Text.code_tile(RAISED_UNDERSCORE))


func _codes_to_string() -> String:
	# map codes back to charmap tokens
	var rev := {}
	for k in GameData.charmap.keys():
		var v: int = GameData.charmap[k]
		if not rev.has(v) or k.length() < rev[v].length():
			rev[v] = k
	var out := ""
	for code in name_codes:
		out += rev.get(code, "?")
	return out
