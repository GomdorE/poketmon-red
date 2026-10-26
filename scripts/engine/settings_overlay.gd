## The engine settings overlay (Esc): window scale, fullscreen, palette, volume,
## key bindings and quitting. It is not part of the original game, so it is a plain
## Godot UI drawn at native resolution over the Game Boy screen instead of tiles.
class_name SettingsOverlay
extends CanvasLayer

const KO := {
	"title": "설정", "display": "화면", "scale": "창 배율", "fullscreen": "전체화면", "palette": "팔레트",
	"gray": "회색", "dmg": "초록 (게임보이)", "sgb": "SGB 컬러 (슈퍼 게임보이)", "audio": "소리", "volume": "볼륨", "mute": "음소거",
	"input": "조작", "gb_a": "A", "gb_b": "B", "gb_start": "Start", "gb_select": "Select",
	"gb_up": "위", "gb_down": "아래", "gb_left": "왼쪽", "gb_right": "오른쪽",
	"press": "키를 누르세요…", "reset": "기본값 복원", "close": "닫기", "quit": "게임 종료",
	"hint": "문자 속도·전투 애니메이션·전투 방식은 게임 안의 ‘설정’ 메뉴(타이틀, Start 메뉴)에서 바꿉니다. 상단 메뉴 바에서도 배율·팔레트·볼륨·일시정지를 바꿀 수 있습니다.  P: 팔레트  F: 배속 토글  Esc: 닫기",
}
const EN := {
	"title": "Settings", "display": "Display", "scale": "Window scale", "fullscreen": "Fullscreen", "palette": "Palette",
	"gray": "Gray", "dmg": "Green (Game Boy)", "sgb": "SGB colour (Super Game Boy)", "audio": "Audio", "volume": "Volume", "mute": "Mute",
	"input": "Controls", "gb_a": "A", "gb_b": "B", "gb_start": "Start", "gb_select": "Select",
	"gb_up": "Up", "gb_down": "Down", "gb_left": "Left", "gb_right": "Right",
	"press": "Press a key…", "reset": "Restore defaults", "close": "Close", "quit": "Quit game",
	"hint": "Text speed, battle animation and battle style live in the game's own OPTION menu (title screen, Start menu). The menu bar at the top also has scale, palette, volume and pause.  P: palette  F: speed toggle  Esc: close",
}

var _t: Dictionary = KO
var _capture := ""
var _key_buttons := {}
var _scale_btn: OptionButton
var _full_btn: CheckButton
var _pal_btn: OptionButton
var _vol: HSlider
var _mute_btn: CheckButton
var _close_btn: Button
var _refreshing := false


func _init() -> void:
	layer = 100
	visible = false


func _ready() -> void:
	_t = KO if GameData.lang == "ko" else EN
	_build()
	Settings.changed.connect(_refresh)


func open() -> void:
	_refresh()
	visible = true
	GB.paused = true
	_close_btn.grab_focus()


func close() -> void:
	_capture = ""
	visible = false
	GB.paused = false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capture != "":
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode != KEY_ESCAPE:
				Settings.bind(_capture, event)
			_capture = ""
			_refresh()
			get_viewport().set_input_as_handled()
		elif event is InputEventJoypadButton and event.pressed:
			Settings.bind(_capture, event)
			_capture = ""
			_refresh()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# --- UI -----------------------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = _theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = _t["title"]
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)

	# display
	box.add_child(_section(_t["display"]))
	var grid := _grid()
	box.add_child(grid)
	_scale_btn = OptionButton.new()
	for k in range(Settings.MIN_SCALE, Settings.MAX_SCALE + 1):
		_scale_btn.add_item("×%d  (%d×%d)" % [k, GBScreen.W * k, GBScreen.H * k], k)
	_scale_btn.item_selected.connect(func(i: int) -> void:
		if not _refreshing:
			Settings.set_scale(_scale_btn.get_item_id(i)))
	_row(grid, _t["scale"], _scale_btn)
	_full_btn = CheckButton.new()
	_full_btn.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			Settings.set_fullscreen(on))
	_row(grid, _t["fullscreen"], _full_btn)
	_pal_btn = OptionButton.new()
	_pal_btn.add_item(_t["gray"], 0)
	_pal_btn.add_item(_t["dmg"], 1)
	_pal_btn.add_item(_t["sgb"], 2)
	_pal_btn.item_selected.connect(func(i: int) -> void:
		if not _refreshing:
			Settings.set_palette(GB.PALETTE_ORDER[i]))
	_row(grid, _t["palette"], _pal_btn)

	# audio
	box.add_child(_section(_t["audio"]))
	grid = _grid()
	box.add_child(grid)
	_vol = HSlider.new()
	_vol.min_value = 0
	_vol.max_value = 100
	_vol.step = 1
	_vol.custom_minimum_size = Vector2(260, 0)
	_vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vol.value_changed.connect(func(v: float) -> void:
		if not _refreshing:
			Settings.set_volume(v / 100.0))
	_row(grid, _t["volume"], _vol)
	_mute_btn = CheckButton.new()
	_mute_btn.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			Settings.set_muted(on))
	_row(grid, _t["mute"], _mute_btn)

	# input
	box.add_child(_section(_t["input"]))
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for action in Settings.ACTIONS:
		var lab := Label.new()
		lab.text = _t[action]
		lab.custom_minimum_size = Vector2(70, 0)
		grid.add_child(lab)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 0)
		btn.pressed.connect(func() -> void:
			_capture = action
			_refresh())
		grid.add_child(btn)
		_key_buttons[action] = btn
	var reset := Button.new()
	reset.text = _t["reset"]
	reset.pressed.connect(func() -> void:
		Settings.reset_bindings()
		_refresh())
	box.add_child(reset)

	var hint := Label.new()
	hint.text = _t["hint"]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78))
	box.add_child(hint)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(buttons)
	var quit := Button.new()
	quit.text = _t["quit"]
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)
	_close_btn = Button.new()
	_close_btn.text = _t["close"]
	_close_btn.pressed.connect(close)
	buttons.add_child(_close_btn)


func _refresh() -> void:
	if _scale_btn == null:
		return
	_refreshing = true
	_scale_btn.select(_scale_btn.get_item_index(Settings.scale))
	_full_btn.button_pressed = Settings.fullscreen
	_pal_btn.select(maxi(GB.PALETTE_ORDER.find(Settings.palette), 0))
	_vol.value = roundf(Settings.volume * 100.0)
	_mute_btn.button_pressed = Settings.muted
	for action in Settings.ACTIONS:
		var btn: Button = _key_buttons[action]
		btn.text = _t["press"] if _capture == action else Settings.key_label(action)
	_refreshing = false


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.62, 0.78))
	l.uppercase = true
	return l


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(130, 0)
	grid.add_child(l)
	grid.add_child(control)


func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 15
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.115, 0.14, 0.97)
	panel.set_corner_radius_all(12)
	panel.set_content_margin_all(26)
	panel.border_color = Color(0.25, 0.26, 0.32)
	panel.set_border_width_all(1)
	th.set_stylebox("panel", "PanelContainer", panel)
	for cls in ["Button", "OptionButton", "CheckButton"]:
		th.set_stylebox("normal", cls, _button_box(Color(0.19, 0.2, 0.25)))
		th.set_stylebox("hover", cls, _button_box(Color(0.25, 0.27, 0.34)))
		th.set_stylebox("pressed", cls, _button_box(Color(0.33, 0.45, 0.72)))
		th.set_stylebox("focus", cls, _button_box(Color(0.22, 0.24, 0.3), Color(0.5, 0.65, 1.0)))
	return th


func _button_box(bg: Color, border: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.border_color = border
	sb.set_border_width_all(1 if border.a > 0 else 0)
	return sb
