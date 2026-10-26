## Title screen and main menu (engine/movie/title.asm, title2.asm,
## engine/menus/main_menu.asm).
class_name Title
extends RefCounted

const TITLE_MONS := ["CHARMANDER", "SQUIRTLE", "BULBASAUR", "WEEDLE", "NIDORAN_M", "SCYTHER", "PIKACHU",
	"CLEFAIRY", "RHYDON", "ABRA", "GASTLY", "DITTO", "PIDGEOTTO", "ONIX", "PONYTA", "MAGIKARP"]
const BOUNCE := [[-4, 16], [3, 4], [-3, 4], [2, 2], [-2, 2], [1, 2], [-1, 2]]
const SCROLL_IN := [0xA2, 0x94, 0x84, 0x63, 0x52, 0x31, 0x11]
const SCROLL_OUT := [0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x83, 0x93]
const BALL_Y := [0x71, 0x6F, 0x6E, 0x6D, 0x6C, 0x6D, 0x6E, 0x6F, 0x71, 0x74]

var S: GBScreen
var mon := "CHARMANDER"
var rng := RandomNumberGenerator.new()


var choice := ""   # "new_game" or "continue" once the menu is left


func run() -> void:
	S = GB.screen
	rng.randomize()
	while true:
		await _display_title_screen()
		var choice := await _main_menu()
		if choice != "title":
			return


func _display_title_screen() -> void:
	Sound.set_audio_bank(3)   # ld a, BANK(Music_TitleScreen); ld [wAudioROMBank], a
	S.white_out()
	S.clear_sprites()
	S.scx = 0
	S.scy = 0x40
	S.row_scx = PackedInt32Array()
	S.win_on = false
	S.clear_bg(GBScreen.BLANK)
	S.clear_win(GBScreen.BLANK)
	# pokemon logo: rows 1-6 use tiles $80-$DF, the last row $31-$40
	for row in 7:
		for col in 16:
			S.set_bg(2 + col, 1 + row, S.tile("pokemon_logo", row * 16 + col))
	_draw_player_character()
	# copyright line at (2, 17): ©'95.'96.'98 GAME FREAK inc.
	var cr := [0x41, 0x42, 0x43, 0x42, 0x44, 0x42, 0x45]
	for i in cr.size():
		S.set_bg(2 + i, 17, S.tile("copyright", cr[i] - 0x41))
	for i in 9:
		S.set_bg(9 + i, 17, S.tile("gamefreak_inc", i))
	# the first title mon is drawn, but the screen shown during the bounce is the
	# version without it (buffer 2), with the window covering everything below y=64
	mon = "CHARMANDER"
	var without_mon := S.snapshot_bg()
	draw_mon_pic(S, mon, 5, 10)
	var saved_with_mon := S.snapshot_bg()
	S.restore_bg(without_mon)
	S.wy = 0x40
	S.win_on = true
	SGB.run("TITLE_SCREEN")
	S.normal_pals()
	S.obp0 = GBScreen.pal_byte(0xE4)
	# make the pokemon logo bounce up and down
	for step in BOUNCE:
		if step[0] == -3:
			Sound.play_sfx("SFX_INTRO_CRASH")
		for i in step[1]:
			await GB.frame
			S.scy = (S.scy + step[0]) & 0xFF
	S.restore_bg(saved_with_mon)
	await GB.frames(36)
	Sound.play_sfx("SFX_INTRO_WHOOSH")
	# scroll the game version in from the right (rows 8-9 only)
	_print_version()
	S.wy = 144
	S.win_on = false
	var d := 144
	while true:
		S.row_scx = _rows_with(8, 10, d)
		await GB.frame
		d = (d + 4) & 0xFF
		if d == 0:
			break
	S.row_scx = PackedInt32Array()
	await GB.delay3()
	await Sound.wait_for_sfx()
	Sound.play_new_sound("MUSIC_TITLE_SCREEN")
	# keep scrolling in new mons until the user presses A or Start
	while true:
		if await GB.check_interrupt(200):
			break
		await _title_scroll(false)
		if await GB.check_interrupt(1):
			break
		if mon in ["CHARMANDER", "SQUIRTLE", "BULBASAUR"]:
			await _animate_ball()
		await _pick_new_mon()
	Sound.play_cry(mon)
	await Sound.wait_for_sfx()
	# GBPalWhiteOutWithDelay3, clear
	S.white_out()
	await GB.delay3()
	S.clear_sprites()
	S.row_scx = PackedInt32Array()
	S.scy = 0
	S.clear_bg(GBScreen.BLANK)
	await GB.delay3()
	S.normal_pals()


func _rows_with(from_row: int, to_row: int, value: int) -> PackedInt32Array:
	var rows := PackedInt32Array()
	rows.resize(18)
	for i in 18:
		rows[i] = value if i >= from_row and i < to_row else 0
	return rows


## DrawPlayerCharacter: 5x7 sprites at OAM (X=$5A, Y=$60); the ball in sprite 10 sits 4px lower.
func _draw_player_character() -> void:
	S.clear_sprites()
	var t := 0
	for row in 7:
		for col in 5:
			var oam_y := 0x60 + row * 8
			if t == 10:
				oam_y = 0x74
			S.set_sprite(t, 0x5A + col * 8 - 8, oam_y - 16, S.tile("title_player", t), 0)
			t += 1


## LoadFrontSpriteByMonIndex: a 7x7 pic area at (x, y). Smaller pics sit at the
## bottom, horizontally centred. `flipped` mirrors the picture (LoadFlippedFrontSpriteByMonIndex).
static func draw_mon_pic(screen: GBScreen, which: String, x: int, y: int, flipped: bool = false) -> void:
	var p: Dictionary = GameData.pokemon[which]
	draw_pic(screen, p["pic"], x, y, flipped)


## Draw any 7x7 (or smaller) picture sheet into the background map.
static func draw_pic(screen: GBScreen, sheet_name: String, x: int, y: int, flipped: bool = false) -> void:
	var sh := screen.sheet(sheet_name)
	var w := sh.tpr
	var h := sh.rows
	var ox := (7 - w) / 2
	var oy := 7 - h
	for row in 7:
		for col in 7:
			var sx := col - ox
			var sy := row - oy
			if flipped:
				sx = (w - 1) - sx
			if sx < 0 or sy < 0 or sx >= w or sy >= h:
				screen.set_bg(x + col, y + row, GBScreen.BLANK)
			else:
				screen.set_bg(x + col, y + row, screen.pic_tile(sheet_name, sx, sy, 1 if flipped else 0))


## PrintGameVersionOnTitleScreen: tiles $60,$61,' ',$65..$69 at (7, 8).
func _print_version() -> void:
	var ids := [0, 1, -1, 5, 6, 7, 8, 9]
	for i in ids.size():
		var t: int = ids[i]
		S.set_bg(7 + i, 8, GBScreen.BLANK if t < 0 else S.tile("red_version", t))


## TitleScroll: scroll the mon area (rows 9-16) with the speed/duration table.
func _title_scroll(scroll_in: bool) -> void:
	var table: Array = SCROLL_IN if scroll_in else SCROLL_OUT
	var d := 0x88 if scroll_in else 0x00
	for entry in table:
		var speed: int = entry >> 4
		var duration: int = entry & 0xF
		for i in duration:
			S.row_scx = _rows_with(9, 17, d)
			await GB.frame
			d = (d + speed) & 0xFF
	S.row_scx = _rows_with(9, 17, d)
	if scroll_in:
		S.row_scx = PackedInt32Array()


func _animate_ball() -> void:
	for y in BALL_Y:
		S.oam[10].y = y - 16
		await GB.frame


func _pick_new_mon() -> void:
	var next := mon
	while next == mon:
		next = TITLE_MONS[rng.randi_range(0, 15)]
	mon = next
	draw_mon_pic(S, mon, 5, 10)
	await _title_scroll(true)


## MainMenu: NEW GAME / OPTION (there is no save file). Returns "new_game" or "title".
## MainMenu: CONTINUE (when a save file exists) / NEW GAME / OPTION.
func _main_menu() -> String:
	SGB.run("DEFAULT")
	var ko := GameData.lang == "ko"
	while true:
		await GB.frames(20)
		Text.clear_screen()
		var has_save := SaveGame.exists()
		var labels: Array = []
		if has_save:
			labels.append("이어하기" if ko else "CONTINUE")
		labels.append("새 게임" if ko else "NEW GAME")
		labels.append("설정" if ko else "OPTION")
		Menu.draw_box(0, 0, 13, 6 if has_save else 4)
		for i in labels.size():
			Text.place_string(2, 2 + i * 2, labels[i])
		var keys := await Menu.handle_input(1, 2, labels.size(), GB.A | GB.B | GB.START)
		if keys & GB.B:
			return "title"
		await GB.frames(20)
		Menu.erase_cursor()
		var item := Menu.current + (0 if has_save else 1)
		if item == 0:
			if await _continue_game():
				choice = "continue"
				return "continue"
			continue
		if item == 1:
			choice = "new_game"
			return "new_game"
		# OPTION, then back to .mainMenuLoop
		await OptionMenu.run()
	return "title"


## .choseContinue: the info box, then A starts the saved game and B goes back.
func _continue_game() -> bool:
	var state := SaveGame.read()
	SaveGame.print_info_box(state, 4, 7)
	await GB.frames(30)
	while true:
		await GB.frame
		if GB.held & GB.A:
			break
		if GB.held & GB.B:
			return false
	S.white_out()
	await GB.delay3()
	Text.clear_screen()
	await GB.frames(10)
	return true
