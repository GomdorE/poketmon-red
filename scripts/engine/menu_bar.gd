## The emulator-style menu bar above the Game Boy screen (game / display / audio /
## settings). Not part of the original game: drawn at native resolution, usable with
## the mouse at any time, and the game pauses while a menu is open.
class_name EngineMenuBar
extends CanvasLayer

const HEIGHT := 28
const KO := {
	"game": "게임", "pause": "일시정지", "speed": "속도", "restart": "처음부터 다시 시작", "quit": "종료",
	"display": "화면", "fullscreen": "전체화면", "gray": "팔레트: 회색", "dmg": "팔레트: 초록 (게임보이)", "sgb": "팔레트: SGB 컬러 (슈퍼 게임보이)",
	"audio": "소리", "mute": "음소거", "vol": "볼륨 %d%%",
	"settings": "설정", "open": "설정·키 설정…  (Esc)", "reset_keys": "기본 키 복원",
}
const EN := {
	"game": "Game", "pause": "Pause", "speed": "Speed", "restart": "Restart from the beginning", "quit": "Quit",
	"display": "Display", "fullscreen": "Fullscreen", "gray": "Palette: gray", "dmg": "Palette: green (Game Boy)", "sgb": "Palette: SGB colour (Super Game Boy)",
	"audio": "Audio", "mute": "Mute", "vol": "Volume %d%%",
	"settings": "Settings", "open": "Settings & key bindings…  (Esc)", "reset_keys": "Restore default keys",
}
const ID_PAUSE := 1
const ID_SPEED := 100    # + speed * 2
const ID_RESTART := 3
const ID_QUIT := 4
const ID_FULLSCREEN := 20
const ID_GRAY := 30
const ID_DMG := 31
const ID_SGB := 32
const ID_MUTE := 40
const ID_VOL := 50       # + index into VOLUMES
const ID_OPEN := 60
const ID_RESET_KEYS := 61
const VOLUMES := [100, 75, 50, 25]

var _t: Dictionary = KO
var _bar: MenuBar
var _game: PopupMenu
var _display: PopupMenu
var _audio: PopupMenu
var _settings: PopupMenu
var _speed: PopupMenu


func _init() -> void:
	layer = 90


func _ready() -> void:
	_t = KO if GameData.lang == "ko" else EN
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.115, 0.14)
	bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bg.offset_bottom = HEIGHT
	add_child(bg)
	_bar = MenuBar.new()
	_bar.prefer_global_menu = false
	_bar.flat = true
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = HEIGHT
	_bar.offset_left = 6
	_bar.theme = _theme()
	add_child(_bar)

	_game = _menu(_t["game"])
	_game.add_check_item(_t["pause"], ID_PAUSE)
	_game.add_separator()
	_game.add_item(_t["restart"], ID_RESTART)
	_game.add_separator()
	_game.add_item(_t["quit"], ID_QUIT)

	_speed = _menu(_t["speed"])
	for i in range(2, 17):
		var sp := i / 2.0
		_speed.add_radio_check_item(("%d×" % int(sp)) if i % 2 == 0 else ("%.1f×" % sp), ID_SPEED + i)

	_display = _menu(_t["display"])
	for k in range(Settings.MIN_SCALE, Settings.MAX_SCALE + 1):
		_display.add_radio_check_item("×%d  (%d×%d)" % [k, GBScreen.W * k, GBScreen.H * k], k)
	_display.add_separator()
	_display.add_check_item(_t["fullscreen"], ID_FULLSCREEN)
	_display.add_separator()
	_display.add_radio_check_item(_t["gray"], ID_GRAY)
	_display.add_radio_check_item(_t["dmg"], ID_DMG)
	_display.add_radio_check_item(_t["sgb"], ID_SGB)

	_audio = _menu(_t["audio"])
	_audio.add_check_item(_t["mute"], ID_MUTE)
	_audio.add_separator()
	for i in VOLUMES.size():
		_audio.add_radio_check_item(_t["vol"] % VOLUMES[i], ID_VOL + i)

	_settings = _menu(_t["settings"])
	_settings.add_item(_t["open"], ID_OPEN)
	_settings.add_item(_t["reset_keys"], ID_RESET_KEYS)
	Settings.changed.connect(_refresh)
	_refresh()


func _menu(title: String) -> PopupMenu:
	var m := PopupMenu.new()
	m.name = title
	m.theme = _bar.theme
	m.id_pressed.connect(_on_id)
	m.about_to_popup.connect(func() -> void:
		_refresh()
		GB.menu_open = true)
	m.popup_hide.connect(func() -> void: GB.menu_open = false)
	_bar.add_child(m)
	return m


func _refresh() -> void:
	if _game == null:
		return
	_game.set_item_checked(_game.get_item_index(ID_PAUSE), GB.user_paused)
	for i in range(2, 17):
		_speed.set_item_checked(_speed.get_item_index(ID_SPEED + i), is_equal_approx(GB.speed, i / 2.0))
	for k in range(Settings.MIN_SCALE, Settings.MAX_SCALE + 1):
		_display.set_item_checked(_display.get_item_index(k), k == Settings.scale)
	_display.set_item_checked(_display.get_item_index(ID_FULLSCREEN), Settings.fullscreen)
	_display.set_item_checked(_display.get_item_index(ID_GRAY), Settings.palette == "gray")
	_display.set_item_checked(_display.get_item_index(ID_DMG), Settings.palette == "dmg")
	_display.set_item_checked(_display.get_item_index(ID_SGB), Settings.palette == "sgb")
	_audio.set_item_checked(_audio.get_item_index(ID_MUTE), Settings.muted)
	var vol := int(roundf(Settings.volume * 100.0))
	for i in VOLUMES.size():
		_audio.set_item_checked(_audio.get_item_index(ID_VOL + i), VOLUMES[i] == vol)


func _on_id(id: int) -> void:
	match id:
		ID_PAUSE:
			GB.user_paused = not GB.user_paused
		ID_RESTART:
			# a clean restart of the whole process: every autoload and coroutine starts over
			OS.set_restart_on_exit(true, OS.get_cmdline_args())
			get_tree().quit()
		ID_QUIT:
			get_tree().quit()
		ID_FULLSCREEN:
			Settings.set_fullscreen(not Settings.fullscreen)
		ID_GRAY:
			Settings.set_palette("gray")
		ID_DMG:
			Settings.set_palette("dmg")
		ID_SGB:
			Settings.set_palette("sgb")
		ID_MUTE:
			Settings.set_muted(not Settings.muted)
		ID_OPEN:
			Settings.overlay.open()
		ID_RESET_KEYS:
			Settings.reset_bindings()
		_:
			if id >= ID_SPEED + 2 and id <= ID_SPEED + 16:
				GB.speed = (id - ID_SPEED) / 2.0
				if GB.speed > 1.0:
					GB.fast_speed = GB.speed
			elif id >= Settings.MIN_SCALE and id <= Settings.MAX_SCALE:
				Settings.set_scale(id)
			elif id >= ID_VOL and id < ID_VOL + VOLUMES.size():
				Settings.set_volume(VOLUMES[id - ID_VOL] / 100.0)
	_refresh()


func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 14
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(6)
	empty.content_margin_left = 10
	empty.content_margin_right = 10
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.22, 0.24, 0.3)
	hover.set_corner_radius_all(5)
	hover.set_content_margin_all(6)
	hover.content_margin_left = 10
	hover.content_margin_right = 10
	th.set_stylebox("normal", "MenuBar", empty)
	th.set_stylebox("hover", "MenuBar", hover)
	th.set_stylebox("pressed", "MenuBar", hover)
	th.set_stylebox("disabled", "MenuBar", empty)
	th.set_color("font_color", "MenuBar", Color(0.9, 0.9, 0.93))
	th.set_color("font_hover_color", "MenuBar", Color.WHITE)
	th.set_color("font_pressed_color", "MenuBar", Color.WHITE)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.13, 0.135, 0.165)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(6)
	panel.border_color = Color(0.25, 0.26, 0.32)
	panel.set_border_width_all(1)
	th.set_stylebox("panel", "PopupMenu", panel)
	var item_hover := StyleBoxFlat.new()
	item_hover.bg_color = Color(0.3, 0.42, 0.68)
	item_hover.set_corner_radius_all(4)
	th.set_stylebox("hover", "PopupMenu", item_hover)
	th.set_color("font_color", "PopupMenu", Color(0.9, 0.9, 0.93))
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	th.set_constant("v_separation", "PopupMenu", 6)
	th.set_constant("item_start_padding", "PopupMenu", 10)
	th.set_constant("item_end_padding", "PopupMenu", 14)
	return th
