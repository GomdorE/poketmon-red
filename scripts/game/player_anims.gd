## The player's map enter/leave animations (engine/overworld/player_animations.asm):
## the teleport spin (Teleport, Dig, Escape Rope, blackout-free warps) and the Fly bird.
## The player sprite is drawn from Overworld.player_anim while one runs.
class_name PlayerAnims
extends RefCounted

# PlayerSpinningFacingOrder
const SPIN_ORDER := [Overworld.FACE_DOWN, Overworld.FACE_LEFT, Overworld.FACE_UP, Overworld.FACE_RIGHT]

# FlyAnimationEnterScreenCoords / FlyAnimationScreenCoords1 / 2: [y, x]
const FLY_ENTER := [[0x05, 0x98], [0x0F, 0x90], [0x18, 0x88], [0x20, 0x80], [0x27, 0x78], [0x2D, 0x70],
	[0x32, 0x68], [0x36, 0x60], [0x39, 0x58], [0x3B, 0x50], [0x3C, 0x48], [0x3C, 0x40]]
const FLY_LEAVE_1 := [[0x3C, 0x48], [0x3C, 0x50], [0x3B, 0x58], [0x3A, 0x60], [0x39, 0x68], [0x37, 0x70],
	[0x37, 0x78], [0x33, 0x80], [0x30, 0x88], [0x2D, 0x90], [0x2A, 0x98], [0x27, 0xA0]]
const FLY_LEAVE_2 := [[0x1A, 0x90], [0x19, 0x80], [0x17, 0x70], [0x15, 0x60], [0x12, 0x50], [0x0F, 0x40],
	[0x0C, 0x30], [0x09, 0x20], [0x05, 0x10], [0x00, 0x00], [0xF0, 0x00]]

var ow: Overworld
var spin_index := 0          # position in wFacingDirectionList
var saved_facing := 0        # wSavedPlayerFacingDirection
var anim := {}               # {sheet, facing, frame, x, y} -> ow.player_anim


func _init(o: Overworld) -> void:
	ow = o


## GetPlayerTeleportAnimFrameDelay: 2 frames on SGB, 3 otherwise.
static func _frame_delay() -> int:
	return 2 if GB.screen.sgb_on else 3


func _show() -> void:
	ow.player_anim = anim
	ow._render()


## InitFacingDirectionList (also saves the facing and the screen Y).
func _init_facing_list() -> void:
	saved_facing = ow.player.facing
	spin_index = SPIN_ORDER.find(ow.player.facing)
	anim = {"sheet": "spr_red", "facing": ow.player.facing, "frame": 0, "x": 0x40, "y": 0x3C}


## SpinPlayerSprite: the next direction of the list.
func _spin() -> void:
	anim.facing = SPIN_ORDER[spin_index % 4]
	spin_index += 1
	_show()


## PlayerSpinInPlace.
func _spin_in_place(delay: int, delta: int, end_value: int, sound: String) -> void:
	while true:
		_spin()
		var c := delay
		if c & 3 == 0 and sound != "":
			Sound.play_sfx(sound)
		delay = (c + delta) & 0xFF
		if delay == end_value:
			return
		await GB.frames(delay)


## PlayerSpinWhileMovingUpOrDown (byte arithmetic on the screen Y).
func _spin_moving(delta_y: int, max_y: int) -> void:
	var y: int = anim.y & 0xFF
	while true:
		_spin()
		y = (y + delta_y) & 0xFF
		anim.y = y - 256 if y >= 0xC0 else y
		_show()
		if y == max_y:
			return
		await GB.frames(_frame_delay())


## RestoreFacingDirectionAndYScreenPos: back to the normal player sprite.
func _restore() -> void:
	ow.player.facing = saved_facing
	ow.player_anim = {}
	ow._render()


## DoFlyAnimation: the bird flaps (image index ^ 1) every 3 frames, moving along `coords`
## unless it flaps in place.
func _fly(counter: int, facing: int, coords: Array) -> void:
	var frame := 0
	var i := 0
	while counter > 0:
		frame ^= 1
		anim.sheet = "spr_bird"
		anim.facing = facing
		anim.frame = frame
		_show()
		await GB.delay3()
		if not coords.is_empty():
			var c: Array = coords[i]
			i += 1
			anim.y = int(c[0]) - 256 if int(c[0]) >= 0xC0 else int(c[0])
			anim.x = int(c[1])
			_show()
		counter -= 1


## _LeaveMapAnim (no warp pads or holes yet): the escape spin, or the Fly take-off.
func leave_map(escape: bool) -> void:
	_init_facing_list()
	if escape:
		# StopMusic $4
		Sound.fade_out_then(4)
		while Sound.fade_out_control != 0:
			await GB.frame
		Sound.stop_all_sound()
		await _spin_in_place(16, -1, 0, "SFX_TELEPORT_EXIT_2")
		# .spinWhileMovingUp
		Sound.play_sfx("SFX_TELEPORT_EXIT_1")
		await _spin_moving(-0x10, 0xEC)
		await GB.frames(10)
		await Intro.fade_out_to_white()
		_restore()
		return
	# .flyAnimation
	await _fly(8, Overworld.FACE_RIGHT, [])
	Sound.play_sfx("SFX_FLY")
	await _fly(12, Overworld.FACE_RIGHT, FLY_LEAVE_1)
	await GB.frames(40)
	await _fly(11, Overworld.FACE_LEFT, FLY_LEAVE_2)
	await Intro.fade_out_to_white()
	_restore()


## EnterMapAnim (after a fly / escape warp): the player drops in spinning, or the bird
## flies in; then the default music.
func enter_map(used_fly: bool) -> void:
	_init_facing_list()
	anim.y = 0xEC - 256
	_show()
	await GB.delay3()
	await Intro.fade_in_from_white()
	if used_fly:
		Sound.play_sfx("SFX_FLY")
		await _fly(12, Overworld.FACE_LEFT, FLY_ENTER)
	else:
		Sound.play_sfx("SFX_TELEPORT_ENTER_1")
		await _spin_moving(0x10, 0x3C)
		Sound.play_sfx("SFX_TELEPORT_ENTER_2")
		await _spin_in_place(0, 1, 8, "")
	await Sound.play_default_music()
	_restore()
