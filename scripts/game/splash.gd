## Copyright screen and the Game Freak shooting star
## (engine/movie/intro.asm PlayShootingStar, engine/movie/splash.asm).
class_name Splash
extends RefCounted

var S: GBScreen
var skipped := false


func run() -> void:
	S = GB.screen
	# PlayShootingStar
	SGB.run("GAME_FREAK_INTRO")
	_load_copyright_screen()
	S.set_all_pals(GBScreen.pal(3, 2, 1, 0))
	await GB.frames(180)
	Text.clear_screen()
	S.clear_sprites()
	S.lcd_on = false
	_draw_black_bars()
	S.lcd_on = true
	await GB.frames(64)
	skipped = await _animate_shooting_star()
	if not skipped:
		await GB.frames(40)
	# the intro music starts in audio bank 3; clear the middle of the screen for the scene
	Sound.set_audio_bank(3)
	Sound.play_new_sound("MUSIC_INTRO_BATTLE")
	S.fill_bg(0, 4, 20, 10, GBScreen.BLANK)
	S.clear_sprites()
	await GB.delay3()


## LoadCopyrightAndTextBoxTiles: three lines of ©'95.'96.'98 at (2, 7), (2, 9), (2, 11).
func _load_copyright_screen() -> void:
	Text.clear_screen()
	var cr := func(t: int) -> int: return S.tile("copyright", t)
	var gf := func(t: int) -> int: return S.tile("gamefreak_inc", t)
	# tiles $60-$72 come from copyright.2bpp, $73-$7B from gamefreak_inc.2bpp
	var line1 := [0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A]
	var line2 := [0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x71, 0x72]
	var line3 := [0x60, 0x61, 0x62, 0x61, 0x63, 0x61, 0x64, 0x7F, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x7B]
	var rows := [[7, line1], [9, line2], [11, line3]]
	for row in rows:
		var y: int = row[0]
		var x := 2
		for code in row[1]:
			if code == 0x7F:
				S.set_bg(x, y, GBScreen.BLANK)
			elif code >= 0x73:
				S.set_bg(x, y, gf.call(code - 0x73))
			else:
				S.set_bg(x, y, cr.call(code - 0x60))
			x += 1


## IntroDrawBlackBars: rows 0-3 and 14-17 are solid black (gengar tile 1).
func _draw_black_bars() -> void:
	S.clear_bg(GBScreen.BLANK)
	var black := S.tile("gengar", 1)
	S.fill_bg(0, 0, 32, 4, black)
	S.fill_bg(0, 14, 32, 4, black)


## AnimateShootingStar. Returns true if the user interrupted it.
func _animate_shooting_star() -> bool:
	Sound.play_sfx("SFX_SHOOTING_STAR")
	S.obp0 = GBScreen.pal_byte(0xF9)
	S.obp1 = GBScreen.pal_byte(0xA4)
	var star_tl := S.tile("move_anim_1", 3)    # MoveAnimationTiles1 tile 3
	var star_bl := S.tile("move_anim_1", 19)   # tile 19
	var small_star := S.tile("falling_star", 0)
	var logo := func(t: int) -> int: return S.tile("gamefreak_logo", t)
	var presents := func(t: int) -> int: return S.tile("gamefreak_presents", t)
	S.clear_sprites()
	# GameFreakShootingStarOAMData: sprites 0-3, 2x2 big star at tile (20, 0)
	# dbsprite x_tile, y_tile, x_off, y_off -> screen x = x_tile*8 + x_off, y = y_tile*8 + y_off
	var big := [
		[160, 0, star_tl, false], [168, 0, star_tl, true],
		[160, 8, star_bl, false], [168, 8, star_bl, true],
	]
	for i in 4:
		S.set_sprite(i, big[i][0], big[i][1], big[i][2], 1, big[i][3])
	# sprites 4-23 are unused until the small stars; GameFreakLogoOAMData at 24-39
	var logo_oam := [
		[10, 9, 0x8D], [11, 9, 0x8E], [10, 10, 0x8F], [11, 10, 0x90], [10, 11, 0x91], [11, 11, 0x92],
		[6, 12, 0x80], [7, 12, 0x81], [8, 12, 0x82], [9, 12, 0x83], [10, 12, 0x93], [11, 12, 0x84],
		[12, 12, 0x85], [13, 12, 0x83], [14, 12, 0x81], [15, 12, 0x86],
	]
	for i in logo_oam.size():
		var e: Array = logo_oam[i]
		var t: int = e[2]
		var v: int
		if t == 0x93:
			v = GBScreen.BLANK
		elif t >= 0x8D:
			v = logo.call(t - 0x8D)
		else:
			v = presents.call(t - 0x80)
		S.set_sprite(24 + i, e[0] * 8, e[1] * 8, v, 0)

	# Move the big star down and left across the screen until its Y reaches 160.
	while true:
		for i in 4:
			S.oam[i].y += 4
			S.oam[i].x -= 4
		if await GB.check_interrupt(1):
			return true
		if S.oam[0].y + 16 == 160:
			break
	for i in 4:
		S.oam[i].y = 160
	# Make the Game Freak logo flash (rotate OBP0 right by two bits, three times).
	var obp := 0xF9
	for i in 3:
		obp = ((obp >> 2) | ((obp & 3) << 6)) & 0xFF
		S.obp0 = GBScreen.pal_byte(obp)
		if await GB.check_interrupt(10):
			return true
	# 24 small star OAM entries, initially off screen
	var stars: Array = []
	for i in 24:
		stars.append({"y": 0, "x": 0})
	var waves := [
		[[0x68, 0x30], [0x68, 0x40], [0x68, 0x58], [0x68, 0x78]],
		[[0x68, 0x38], [0x68, 0x48], [0x68, 0x60], [0x68, 0x70]],
		[[0x68, 0x34], [0x68, 0x4C], [0x68, 0x54], [0x68, 0x64]],
		[[0x68, 0x3C], [0x68, 0x5C], [0x68, 0x6C], [0x68, 0x74]],
		[], [],
	]
	var move_down_count := 0
	var obp1 := 0xA4
	for wave in waves:
		if wave.size() > 0:
			for i in 4:
				stars[20 + i] = {"y": wave[i][0], "x": wave[i][1]}
			if move_down_count != 24:
				move_down_count += 6
		# MoveDownSmallStars: 8 iterations of 3 frames
		for it in 8:
			var idx := 23
			for c in move_down_count:
				if idx >= 0:
					stars[idx].y += 1
				idx -= 1
			obp1 ^= 0xA0
			S.obp1 = GBScreen.pal_byte(obp1)
			_apply_small_stars(stars, small_star)
			if await GB.check_interrupt(3):
				return true
		# shift the existing OAM entries down to make room for the next wave
		for i in 20:
			stars[i] = stars[i + 4].duplicate()
	return false


func _apply_small_stars(stars: Array, v: int) -> void:
	for i in 24:
		var st: Dictionary = stars[i]
		# OAM coordinates: screen y = Y - 16, screen x = X - 8
		S.set_sprite(i, st.x - 8, st.y - 16, v, 1, false, false, true)
