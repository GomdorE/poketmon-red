## Professor Oak's introduction (engine/movie/oak_speech/oak_speech.asm,
## oak_speech2.asm): pictures fade or slide in, the player and rival are named,
## then the player shrinks into the overworld sprite.
class_name OakSpeech
extends RefCounted

const PLAYER_NAMES_KO := ["새 이름", "레드", "지우", "잭"]
const RIVAL_NAMES_KO := ["새 이름", "그린", "바람", "존"]
const PLAYER_NAMES_EN := ["NEW NAME", "RED", "ASH", "JACK"]
const RIVAL_NAMES_EN := ["NEW NAME", "BLUE", "GARY", "JOHN"]

var state: GameState
var S: GBScreen


func _init(s: GameState) -> void:
	state = s


func run() -> void:
	S = GB.screen
	Sound.stop_all_sound()
	Sound.play_music("MUSIC_ROUTES2")
	Text.vars["PLAYER"] = state.player_name
	Text.vars["RIVAL"] = state.rival_name
	Text.clear_screen()
	S.clear_sprites()
	S.normal_pals()
	# Oak
	_draw_pic_centered("pic_oak")
	await _fade_in_intro_pic()
	await Text.print_text("_OakSpeechText1")
	await Intro.fade_out_to_white()
	Text.clear_screen()
	# Nidorino, flipped, slides in from the right
	await _move_pic_left(func(): Title.draw_mon_pic(S, "NIDORINO", 6, 4, true))
	# OakSpeechText2: part A, Nidorina's cry, part B
	await Text.print_text("_OakSpeechText2A")
	await Sound.text_sound("sound_cry_nidorina")   # (the original plays Nidorina's cry over Nidorino's picture)
	await Text.run_commands(GameData.text("_OakSpeechText2B"))
	await Intro.fade_out_to_white()
	Text.clear_screen()
	# the player
	await _move_pic_left(func(): _draw_pic_centered("pic_red"))
	await Text.print_text("_IntroducePlayerText")
	await _choose_name(true)
	await Intro.fade_out_to_white()
	Text.clear_screen()
	# the rival
	_draw_pic_centered("pic_rival1")
	await _fade_in_intro_pic()
	await Text.print_text("_IntroduceRivalText")
	await _choose_name(false)
	# the player again, then the shrink
	await Intro.fade_out_to_white()
	Text.clear_screen()
	_draw_pic_centered("pic_red")
	await Intro.fade_in_from_white()
	await Text.print_text("_OakSpeechText3")
	Sound.play_sfx("SFX_SHRINK")
	await GB.frames(4)
	_draw_pic_centered("pic_shrink1")
	await GB.frames(4)
	_draw_pic_centered("pic_shrink2")
	# the music fades out (10 frames per step) and the audio bank becomes Pallet Town's
	Sound.set_audio_bank(1)
	Sound.fade_out_then(10)
	await GB.frames(20)
	Text.clear_area(6, 5, 7, 7)
	# ResetPlayerSpriteData: the overworld sprite appears facing down at (64, 60)
	Overworld.draw_player_sprite_static(S, 64, 60, 0)
	await GB.frames(50)
	await Intro.fade_out_to_white()
	Text.clear_screen()
	S.clear_sprites()
	await GB.frames(20)


## IntroDisplayPicCenteredOrUpperRight with c = 0: 7x7 pic at (6, 4).
func _draw_pic_centered(sheet: String) -> void:
	Title.draw_pic(S, sheet, 6, 4)


## FadeInIntroPic: six BGP steps of 10 frames.
func _fade_in_intro_pic() -> void:
	var pals := [
		GBScreen.pal(1, 1, 1, 0), GBScreen.pal(2, 2, 2, 0), GBScreen.pal(3, 3, 3, 0),
		GBScreen.pal(3, 3, 2, 0), GBScreen.pal(3, 3, 1, 0), GBScreen.pal(3, 2, 1, 0),
	]
	for p in pals:
		S.bgp = p
		await GB.frames(10)


## MovePicLeft: the picture is drawn in the window map, which slides in from
## WX = 119 to WX = 7 by 8 pixels per frame.
func _move_pic_left(draw: Callable) -> void:
	S.clear_win(Text.code_tile(Text.SPACE))
	# draw into the background, then move the result into the window map
	draw.call()
	S.copy_bg_to_win()
	Text.clear_screen()
	S.wy = 0
	S.wx = 119
	S.win_on = true
	await GB.frame
	S.bgp = GBScreen.pal_byte(0xE4)
	while true:
		await GB.frame
		var nwx := S.wx - 8
		if nwx < 0:
			break
		S.wx = nwx
	# leave the picture in the background map and hide the window
	for y in 18:
		for x in 20:
			S.set_bg(x, y, S.win[y * GBScreen.MAP_W + x])
	S.win_on = false
	S.wy = 144
	S.wx = 7


## ChoosePlayerName / ChooseRivalName.
func _choose_name(is_player: bool) -> void:
	await _slide_pic_right()
	var names: Array = (PLAYER_NAMES_KO if is_player else RIVAL_NAMES_KO) if GameData.lang == "ko" else (PLAYER_NAMES_EN if is_player else RIVAL_NAMES_EN)
	var choice := await _display_intro_name_box(names)
	var name := ""
	if choice == 0:
		while name == "":
			name = await NamingScreen.new().run(NamingScreen.Kind.PLAYER if is_player else NamingScreen.Kind.RIVAL)
		Text.clear_screen()
		await GB.delay3()
		_draw_pic_centered("pic_red" if is_player else "pic_rival1")
	else:
		name = names[choice]
		await _slide_pic_left()
	if is_player:
		state.player_name = name
		Text.vars["PLAYER"] = name
		await Text.print_text("_YourNameIsText")
	else:
		state.rival_name = name
		Text.vars["RIVAL"] = name
		await Text.print_text("_HisNameIsText")


## OakSpeechSlidePicRight: the 7x7 picture moves from x=6 to x=12, one tile per 3 frames.
func _slide_pic_right() -> void:
	for step in 6:
		var x := 6 + step
		for row in 7:
			for col in range(6, -1, -1):
				S.set_bg(x + col + 1, 4 + row, S.get_bg(x + col, 4 + row))
			S.set_bg(x, 4 + row, Text.code_tile(Text.SPACE))
		await GB.delay3()


## OakSpeechSlidePicLeft: clear the name box, 10 frames, then slide back to x=6.
func _slide_pic_left() -> void:
	Text.clear_area(0, 0, 11, 12)
	await GB.frames(10)
	await GB.delay3()
	for step in 6:
		var x := 12 - step
		for row in 7:
			for col in 7:
				S.set_bg(x + col - 1, 4 + row, S.get_bg(x + col, 4 + row))
			S.set_bg(x + 6, 4 + row, Text.code_tile(Text.SPACE))
		await GB.delay3()


## DisplayIntroNameTextBox: box at (0, 0) with "NAME" on the border and the
## four choices two rows apart. Returns the selected index.
func _display_intro_name_box(names: Array) -> int:
	Menu.draw_box(0, 0, 9, 10)
	Text.place_string(3, 0, "이름" if GameData.lang == "ko" else "NAME")
	for i in names.size():
		Text.place_string(2, 2 + i * 2, names[i])
	await Menu.handle_input(1, 2, names.size(), GB.A)
	Menu.erase_cursor()
	return Menu.current
