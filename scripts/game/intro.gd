## Gengar vs Nidorino opening scene (engine/movie/intro.asm PlayIntroScene).
class_name Intro
extends RefCounted

const ANIM1 := [[0, 0], [-2, 2], [-1, 2], [1, 2], [2, 2]]
const ANIM2 := [[0, 0], [-2, -2], [-1, -2], [1, -2], [2, -2]]
const ANIM3 := [[0, 0], [-12, 6], [-8, 6], [8, 6], [12, 6]]
const ANIM4 := [[0, 0], [-8, -4], [-4, -4], [4, -4], [8, -4]]
const ANIM5 := [[0, 0], [-8, 4], [-4, 4], [4, 4], [8, 4]]
const ANIM6 := [[0, 0], [2, 0], [2, 0], [0, 0]]
const ANIM7 := [[-8, -16], [-7, -14], [-6, -12], [-4, -10]]

var S: GBScreen
var gengar_maps: Array = []
var nidorino_sheet := "nidorino_1"


func run() -> void:
	S = GB.screen
	_load_gengar_tilemaps()
	var interrupted := await _play_scene()
	# PlayIntro: GBFadeOutToWhite, then clear
	await fade_out_to_white()
	S.scx = 0
	S.clear_sprites()
	S.clear_bg(GBScreen.BLANK)
	await GB.frame


func _load_gengar_tilemaps() -> void:
	# the exact bytes of gfx/intro/gengar_{1,2,3}.tilemap (7x7, tile ids into gengar.2bpp)
	gengar_maps = [
		[0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,0x00,0x19,0x00, 0x02,0x06,0x0b,0x10,0x14,0x1a,0x00, 0x00,0x07,0x0c,0x11,0x15,0x1b,0x00, 0x03,0x08,0x0d,0x12,0x16,0x1c,0x00, 0x04,0x09,0x0e,0x13,0x17,0x1d,0x1f, 0x05,0x0a,0x0f,0x01,0x18,0x1e,0x20],
		[0x00,0x00,0x00,0x30,0x00,0x37,0x00, 0x00,0x00,0x2b,0x31,0x34,0x38,0x3d, 0x21,0x26,0x2c,0x01,0x35,0x39,0x3e, 0x22,0x27,0x2d,0x32,0x36,0x01,0x00, 0x23,0x28,0x2e,0x33,0x01,0x3a,0x00, 0x24,0x29,0x2f,0x01,0x01,0x3b,0x00, 0x25,0x2a,0x01,0x01,0x01,0x3c,0x00],
		[0x00,0x00,0x00,0x00,0x00,0x00,0x00, 0x00,0x00,0x47,0x4d,0x00,0x00,0x00, 0x00,0x00,0x48,0x4e,0x52,0x56,0x5b, 0x3f,0x43,0x49,0x4f,0x53,0x57,0x5c, 0x40,0x44,0x4a,0x50,0x54,0x58,0x00, 0x41,0x45,0x4b,0x51,0x4c,0x59,0x5d, 0x42,0x46,0x4c,0x4c,0x55,0x5a,0x5e],
	]


## IntroCopyTiles: 7x7 gengar tilemap at (13, 7).
func _copy_gengar(which: int) -> void:
	var m: Array = gengar_maps[which]
	for row in 7:
		for col in 7:
			var t: int = m[row * 7 + col]
			S.set_bg(13 + col, 7 + row, GBScreen.BLANK if t == 0 else S.tile("gengar", t))


## Returns true if interrupted.
func _play_scene() -> bool:
	SGB.run("NIDORINO_INTRO")
	S.set_all_pals(GBScreen.pal(3, 2, 1, 0))
	S.scx = 0
	_copy_gengar(0)
	# InitIntroNidorinoOAM: 6x6 sprites, OAM X = 0 + col*8, Y = 80 + 8 + row*8
	_init_nidorino_oam(0, 80)
	if await _move_mon(40, "nidorino_right"):
		return true
	# hip, hop
	nidorino_sheet = "nidorino_1"
	Sound.play_sfx("SFX_INTRO_HIP")
	await _animate_nidorino(ANIM1)
	Sound.play_sfx("SFX_INTRO_HOP")
	await _animate_nidorino(ANIM2)
	if await GB.check_interrupt(10):
		return true
	Sound.play_sfx("SFX_INTRO_HIP")
	await _animate_nidorino(ANIM1)
	Sound.play_sfx("SFX_INTRO_HOP")
	await _animate_nidorino(ANIM2)
	if await GB.check_interrupt(30):
		return true
	# raise
	_copy_gengar(1)
	Sound.play_sfx("SFX_INTRO_RAISE")
	if await _move_mon(4, "gengar_left"):
		return true
	if await GB.check_interrupt(30):
		return true
	# slash
	_copy_gengar(2)
	Sound.play_sfx("SFX_INTRO_CRASH")
	if await _move_mon(8, "gengar_right"):
		return true
	Sound.play_sfx("SFX_INTRO_HIP")
	nidorino_sheet = "nidorino_2"
	await _animate_nidorino(ANIM3)
	if await GB.check_interrupt(30):
		return true
	if await _move_mon(4, "gengar_left"):
		return true
	_copy_gengar(0)
	if await GB.check_interrupt(60):
		return true
	# hip, hop
	nidorino_sheet = "nidorino_1"
	Sound.play_sfx("SFX_INTRO_HIP")
	await _animate_nidorino(ANIM4)
	Sound.play_sfx("SFX_INTRO_HOP")
	await _animate_nidorino(ANIM5)
	if await GB.check_interrupt(20):
		return true
	nidorino_sheet = "nidorino_2"
	await _animate_nidorino(ANIM6)
	if await GB.check_interrupt(30):
		return true
	# lunge
	Sound.play_sfx("SFX_INTRO_LUNGE")
	nidorino_sheet = "nidorino_3"
	await _animate_nidorino(ANIM7)
	return false


func _init_nidorino_oam(base_x: int, base_y: int) -> void:
	S.clear_sprites()
	var t := 0
	for col in 6:
		for row in 6:
			var oam_y := base_y + 8 + row * 8
			var oam_x := base_x + col * 8
			S.set_sprite(t, oam_x - 8, oam_y - 16, S.tile(nidorino_sheet, t), 0, false, false, true)
			t += 1


## UpdateIntroNidorinoOAM: add (dy, dx) to every sprite and reload the tiles.
func _update_nidorino(dy: int, dx: int) -> void:
	for t in 36:
		var s: Dictionary = S.oam[t]
		s.y += dy
		s.x += dx
		s.v = S.tile(nidorino_sheet, t)


func _animate_nidorino(anim: Array) -> void:
	for step in anim:
		_update_nidorino(step[0], step[1])
		await GB.frames(5)


## IntroMoveMon: d moves of 2 pixels, 2 frames each. Returns true if interrupted.
func _move_mon(d: int, how: String) -> bool:
	for i in d:
		match how:
			"nidorino_right":
				_update_nidorino(0, 2)
			"gengar_left":
				S.scx = (S.scx + 2) & 0xFF
			"gengar_right":
				S.scx = (S.scx - 2) & 0xFF
		if await GB.check_interrupt(2):
			return true
	return false


## GBFadeOutToWhite: FadePal6, FadePal7, FadePal8, 8 frames each.
static func fade_out_to_white() -> void:
	var S: GBScreen = GB.screen
	var pals := [
		[GBScreen.pal(2, 1, 0, 0), GBScreen.pal(2, 0, 0, 0), GBScreen.pal(2, 1, 0, 0)],
		[GBScreen.pal(1, 0, 0, 0), GBScreen.pal(1, 0, 0, 0), GBScreen.pal(1, 0, 0, 0)],
		[GBScreen.pal(0, 0, 0, 0), GBScreen.pal(0, 0, 0, 0), GBScreen.pal(0, 0, 0, 0)],
	]
	for p in pals:
		S.bgp = p[0]
		S.obp0 = p[1]
		S.obp1 = p[2]
		await GB.frames(8)


## GBFadeInFromWhite: FadePal7, FadePal6, FadePal5, 8 frames each.
static func fade_in_from_white() -> void:
	var S: GBScreen = GB.screen
	var pals := [
		[GBScreen.pal(1, 0, 0, 0), GBScreen.pal(1, 0, 0, 0), GBScreen.pal(1, 0, 0, 0)],
		[GBScreen.pal(2, 1, 0, 0), GBScreen.pal(2, 0, 0, 0), GBScreen.pal(2, 1, 0, 0)],
		[GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 1, 0, 0), GBScreen.pal(3, 2, 0, 0)],
	]
	for p in pals:
		S.bgp = p[0]
		S.obp0 = p[1]
		S.obp1 = p[2]
		await GB.frames(8)


## GBFadeOutToBlack: FadePal4 ... FadePal1 reversed (3,3,3,3), 8 frames each.
static func fade_out_to_black() -> void:
	var S: GBScreen = GB.screen
	var pals := [
		[GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 1, 0, 0), GBScreen.pal(3, 2, 0, 0)],
		[GBScreen.pal(3, 3, 2, 1), GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 2, 1, 0)],
		[GBScreen.pal(3, 3, 3, 2), GBScreen.pal(3, 3, 3, 2), GBScreen.pal(3, 3, 2, 0)],
		[GBScreen.pal(3, 3, 3, 3), GBScreen.pal(3, 3, 3, 3), GBScreen.pal(3, 3, 3, 3)],
	]
	for p in pals:
		S.bgp = p[0]
		S.obp0 = p[1]
		S.obp1 = p[2]
		await GB.frames(8)


## GBFadeInFromBlack: FadePal2 ... FadePal5, 8 frames each.
static func fade_in_from_black() -> void:
	var S: GBScreen = GB.screen
	var pals := [
		[GBScreen.pal(3, 3, 3, 2), GBScreen.pal(3, 3, 3, 2), GBScreen.pal(3, 3, 2, 0)],
		[GBScreen.pal(3, 3, 2, 1), GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 2, 1, 0)],
		[GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 1, 0, 0), GBScreen.pal(3, 2, 0, 0)],
		[GBScreen.pal(3, 2, 1, 0), GBScreen.pal(3, 1, 0, 0), GBScreen.pal(3, 2, 0, 0)],
	]
	for p in pals:
		S.bgp = p[0]
		S.obp0 = p[1]
		S.obp1 = p[2]
		await GB.frames(8)
