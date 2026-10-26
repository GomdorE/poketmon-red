## Engine-level settings that the original game never had (window scale, fullscreen,
## palette, volume, key bindings) plus the original wOptions byte (text speed, battle
## animation, battle style). Persisted in user://settings.cfg. Autoloaded as `Settings`;
## Esc opens the overlay (scripts/engine/settings_overlay.gd).
extends Node

const PATH := "user://settings.cfg"
const ACTIONS := ["gb_a", "gb_b", "gb_start", "gb_select", "gb_up", "gb_down", "gb_left", "gb_right"]
const DEFAULT_KEYS := {
	"gb_a": [KEY_Z, KEY_SPACE], "gb_b": [KEY_X], "gb_start": [KEY_ENTER], "gb_select": [KEY_SHIFT],
	"gb_up": [KEY_UP], "gb_down": [KEY_DOWN], "gb_left": [KEY_LEFT], "gb_right": [KEY_RIGHT],
}
# wOptions (constants/ram_constants.asm)
const TEXT_DELAY_FAST := 1
const TEXT_DELAY_MEDIUM := 3
const TEXT_DELAY_SLOW := 5
const TEXT_DELAY_MASK := 7
const BIT_BATTLE_SHIFT := 0x40       # set = "SET" style
const BIT_BATTLE_ANIMATION := 0x80   # set = animations off
const MIN_SCALE := 2
const MAX_SCALE := 8
const WINDOW_FRAME := 40   # title bar height allowance when fitting the window to the screen

signal changed

var scale := 6
var fullscreen := false
var palette := "sgb"   # Super Game Boy colours by default
var volume := 1.0
var muted := false
var options := TEXT_DELAY_MEDIUM
var overlay: SettingsOverlay
var menu_bar: EngineMenuBar


func _ready() -> void:
	load_settings()
	apply_all()
	menu_bar = EngineMenuBar.new()
	add_child(menu_bar)
	overlay = SettingsOverlay.new()
	add_child(overlay)


# --- persistence ----------------------------------------------------------------------

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	scale = clampi(int(cf.get_value("display", "scale", scale)), MIN_SCALE, MAX_SCALE)
	fullscreen = bool(cf.get_value("display", "fullscreen", fullscreen))
	palette = str(cf.get_value("display", "palette", palette))
	if not GB.PALETTES.has(palette):
		palette = "gray"
	volume = clampf(float(cf.get_value("audio", "volume", volume)), 0.0, 1.0)
	muted = bool(cf.get_value("audio", "muted", muted))
	options = int(cf.get_value("game", "options", options)) & 0xFF
	for action in ACTIONS:
		var list: Array = cf.get_value("input", action, [])
		if list.size() > 0:
			_apply_binding_list(action, list)


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "scale", scale)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "palette", palette)
	cf.set_value("audio", "volume", volume)
	cf.set_value("audio", "muted", muted)
	cf.set_value("game", "options", options)
	for action in ACTIONS:
		cf.set_value("input", action, _binding_list(action))
	cf.save(PATH)
	changed.emit()


# --- original options ---------------------------------------------------------------------

func text_delay() -> int:
	var d := options & TEXT_DELAY_MASK
	return d if d > 0 else TEXT_DELAY_MEDIUM


func battle_animation_on() -> bool:
	return (options & BIT_BATTLE_ANIMATION) == 0


func battle_style_shift() -> bool:
	return (options & BIT_BATTLE_SHIFT) == 0


func set_options(v: int) -> void:
	if v == options:
		return
	options = v & 0xFF
	save()


# --- display / audio ----------------------------------------------------------------------

func apply_all() -> void:
	apply_window()
	GB.set_palette_name(palette)
	Sound.set_volume(0.0 if muted else volume)


func apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := Vector2i(base_size().x * effective_scale(usable.size), base_size().y * effective_scale(usable.size) + EngineMenuBar.HEIGHT)
	if DisplayServer.window_get_size() == size:
		return
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


## The chosen scale, reduced until the window (with its title bar) fits the screen.
func effective_scale(usable: Vector2i) -> int:
	var base := base_size()
	var k := scale
	while k > 1 and (base.x * k > usable.x or base.y * k + EngineMenuBar.HEIGHT + WINDOW_FRAME > usable.y):
		k -= 1
	return k


## The game area in Game Boy pixels: the screen, or the SGB border around it.
func base_size() -> Vector2i:
	return Vector2i(256, 224) if palette == "sgb" else Vector2i(GBScreen.W, GBScreen.H)


func set_scale(k: int) -> void:
	scale = clampi(k, MIN_SCALE, MAX_SCALE)
	apply_window()
	save()


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_window()
	save()


func set_palette(name: String) -> void:
	if not GB.PALETTES.has(name):
		return
	palette = name
	GB.set_palette_name(name)
	apply_window()
	save()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	Sound.set_volume(0.0 if muted else volume)
	save()


func set_muted(on: bool) -> void:
	muted = on
	Sound.set_volume(0.0 if muted else volume)
	save()


func toggle_overlay() -> void:
	if overlay.visible:
		overlay.close()
	else:
		overlay.open()


# --- key bindings -------------------------------------------------------------------------

## Replace an action's bindings with one key or joypad button.
func bind(action: String, event: InputEvent) -> void:
	if not action in ACTIONS:
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, _normalized(event))
	save()


func reset_bindings() -> void:
	for action in ACTIONS:
		InputMap.action_erase_events(action)
		for key in DEFAULT_KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	save()


## Human-readable name of an action's first binding.
func key_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "-"
	var names: Array = []
	for ev in events:
		if ev is InputEventKey:
			var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			var label := DisplayServer.keyboard_get_keycode_from_physical(code) if ev.physical_keycode != 0 else code
			names.append(OS.get_keycode_string(label))
		elif ev is InputEventJoypadButton:
			names.append("Pad %d" % ev.button_index)
	return " / ".join(names)


func _normalized(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var ev := InputEventKey.new()
		ev.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return ev
	if event is InputEventJoypadButton:
		var ev := InputEventJoypadButton.new()
		ev.button_index = event.button_index
		return ev
	return event


func _binding_list(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append("key:%d" % (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode))
		elif ev is InputEventJoypadButton:
			out.append("pad:%d" % ev.button_index)
	return out


func _apply_binding_list(action: String, list: Array) -> void:
	InputMap.action_erase_events(action)
	for item in list:
		var s := str(item)
		var n := int(s.get_slice(":", 1))
		if s.begins_with("key:"):
			var ev := InputEventKey.new()
			ev.physical_keycode = n
			InputMap.action_add_event(action, ev)
		elif s.begins_with("pad:"):
			var ev := InputEventJoypadButton.new()
			ev.button_index = n
			InputMap.action_add_event(action, ev)
