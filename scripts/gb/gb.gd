## Game Boy frame clock, joypad and palette. Autoloaded as `GB`.
##
## Everything in the game waits in Game Boy frames (59.7275 Hz), never in
## seconds, so the timings copied from the disassembly stay exact.
extends Node

signal frame

const FPS := 59.7275

# joypad bits, same layout as the hardware register in pokered (PAD_*)
const A := 0x01
const B := 0x02
const SELECT := 0x04
const START := 0x08
const RIGHT := 0x10
const LEFT := 0x20
const UP := 0x40
const DOWN := 0x80
const CTRL_PAD := RIGHT | LEFT | UP | DOWN
const BUTTONS := A | B | SELECT | START

const PALETTES := {
	"gray": [Color("ffffff"), Color("aaaaaa"), Color("555555"), Color("000000")],
	"dmg": [Color("9bbc0f"), Color("8bac0f"), Color("306230"), Color("0f380f")],
	"sgb": [Color("ffffff"), Color("aaaaaa"), Color("555555"), Color("000000")],   # Super Game Boy colours (SGB autoload)
}
const PALETTE_ORDER := ["gray", "dmg", "sgb"]

var screen: Node2D
var frame_count := 0
# wPlayTime* (engine/play_time.asm): counted in VBlank while BIT_GAME_TIMER_COUNTING is set
var play_time_counting := false
var play_time_frames := 0
var play_time_seconds := 0
var play_time_minutes := 0
var play_time_hours := 0
var play_time_maxed := false
var held := 0        # hJoyHeld
var pressed := 0     # hJoyPressed (newly pressed this frame)
var released := 0
var joy5 := 0        # JoypadLowSensitivity output
var _repeat_counter := 0
var speed := 1.0        # game speed multiplier (1.0 = real time)
var fast_speed := 8.0   # what the F key toggles to
var paused := false        # the settings overlay is open
var user_paused := false   # menu bar: pause
var menu_open := false     # a menu bar popup is open
var palette_name := "sgb"
var _acc := 0.0
var quit_requested := false


func _ready() -> void:
	process_priority = -100


func _process(delta: float) -> void:
	if paused or user_paused or menu_open:
		return
	_acc += delta * FPS * speed
	var n := int(_acc)
	_acc -= n
	n = mini(n, int(ceil(speed)) + 4)
	for i in n:
		_tick()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Settings.toggle_overlay()
		elif event.keycode == KEY_P:
			Settings.set_palette(PALETTE_ORDER[(PALETTE_ORDER.find(palette_name) + 1) % PALETTE_ORDER.size()])
		elif event.keycode == KEY_F:
			speed = 1.0 if speed > 1.0 else fast_speed


func set_palette_name(name: String) -> void:
	palette_name = name
	if screen:
		screen.set_palette(PALETTES[name])
		screen.set_sgb_on(name == "sgb")
		if name == "sgb":
			SGB.apply()


## Test input: "frame:KEY[:holdframes],..." presses KEY (a, b, start, select, up,
## down, left, right) at that frame for holdframes (default 2) frames.
var _key_script: Array = []


func load_key_script(spec: String) -> void:
	var names := {"a": A, "b": B, "start": START, "select": SELECT, "up": UP, "down": DOWN, "left": LEFT, "right": RIGHT}
	for part in spec.split(","):
		var f := part.split(":")
		if f.size() >= 3 and f[0] == "every" and names.has(f[2]):
			# "every:N:KEY[:from]": press KEY for 2 frames every N frames (from frame `from` on)
			_key_script.append({"every": int(f[1]), "key": names[f[2]], "from": int(f[3]) if f.size() > 3 else 0})
		elif f.size() >= 2 and names.has(f[1]):
			_key_script.append({"frame": int(f[0]), "key": names[f[1]], "hold": int(f[2]) if f.size() > 2 else 2})


func _scripted_keys() -> int:
	var h := 0
	for e in _key_script:
		if e.has("every"):
			if frame_count >= e.from and ((frame_count - e.from) % e.every) < 2:
				h |= e.key
		elif frame_count >= e.frame and frame_count < e.frame + e.hold:
			h |= e.key
	return h


func _tick() -> void:
	frame_count += 1
	_track_play_time()
	var h := _scripted_keys()
	if Input.is_action_pressed("gb_a"): h |= A
	if Input.is_action_pressed("gb_b"): h |= B
	if Input.is_action_pressed("gb_select"): h |= SELECT
	if Input.is_action_pressed("gb_start"): h |= START
	if Input.is_action_pressed("gb_right"): h |= RIGHT
	if Input.is_action_pressed("gb_left"): h |= LEFT
	if Input.is_action_pressed("gb_up"): h |= UP
	if Input.is_action_pressed("gb_down"): h |= DOWN
	# the real hardware cannot report opposite directions at once
	if h & UP and h & DOWN: h &= ~DOWN
	if h & LEFT and h & RIGHT: h &= ~RIGHT
	pressed = h & ~held
	released = held & ~h
	held = h
	_update_low_sensitivity()
	Sound.vblank()   # VBlank: FadeOutAudio + UpdateMusic before the game code runs
	frame.emit()
	if screen:
		screen.queue_redraw()


## JoypadLowSensitivity: newly pressed keys are reported at once; a key that
## stays held is reported again after 30 frames and then every 5 frames
## (only the control pad repeats; buttons must be re-pressed).
func _update_low_sensitivity() -> void:
	if pressed != 0:
		joy5 = held
		_repeat_counter = 30
		return
	if held == 0:
		joy5 = 0
		_repeat_counter = 0
		return
	_repeat_counter -= 1
	if _repeat_counter <= 0:
		joy5 = held & CTRL_PAD
		_repeat_counter = 5
	else:
		joy5 = 0


func _track_play_time() -> void:
	if not play_time_counting or play_time_maxed:
		return
	play_time_frames += 1
	if play_time_frames < 60:
		return
	play_time_frames = 0
	play_time_seconds += 1
	if play_time_seconds < 60:
		return
	play_time_seconds = 0
	play_time_minutes += 1
	if play_time_minutes < 60:
		return
	play_time_minutes = 0
	play_time_hours += 1
	if play_time_hours >= 0xFF:
		play_time_maxed = true


## Wait n Game Boy frames.
func frames(n: int) -> void:
	for i in n:
		await frame


func delay3() -> void:
	await frames(3)


## CheckForUserInterruption: wait up to c frames, returning true when
## A or Start (or Up+Select+B) is pressed.
func check_interrupt(c: int) -> bool:
	for i in c:
		await frame
		if held == UP | SELECT | B:
			return true
		if joy5 & (START | A):
			return true
	return false


## Wait until one of the keys in mask is newly pressed (hJoy5 based).
func wait_press(mask: int) -> int:
	while true:
		await frame
		if joy5 & mask:
			return joy5 & mask
	return 0


func palette() -> Array:
	return PALETTES[palette_name]


func screenshot(path: String, scale: int = 3) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = screen.get_viewport().get_texture().get_image()
	if scale > 1:
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
