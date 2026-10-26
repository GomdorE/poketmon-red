## The original OPTION screen (engine/menus/main_menu.asm DisplayOptionMenu):
## text speed, battle animation and battle style, with the ▷ markers on every
## row and the ▶ cursor on the active one. Options are applied live
## (SetOptionsFromCursorPositions runs each time the cursor is placed).
class_name OptionMenu
extends RefCounted

const ARROW_UNFILLED := 0xEC   # '▷'
# TextSpeedOptionData: cursor X -> delay
const SPEED_BY_X := {1: Settings.TEXT_DELAY_FAST, 7: Settings.TEXT_DELAY_MEDIUM, 14: Settings.TEXT_DELAY_SLOW}


static func run() -> void:
	var ko := GameData.lang == "ko"
	Text.clear_screen()
	Menu.draw_box(0, 0, 18, 3)
	Menu.draw_box(0, 5, 18, 3)
	Menu.draw_box(0, 10, 18, 3)
	Text.place_string(1, 1, "문자 속도" if ko else "TEXT SPEED")
	Text.place_string(1, 3, " 빠름    보통     느림" if ko else " FAST  MEDIUM SLOW")
	Text.place_string(1, 6, "전투 애니메이션" if ko else "BATTLE ANIMATION")
	Text.place_string(1, 8, " 켬        끔" if ko else " ON       OFF")
	Text.place_string(1, 11, "전투 방식" if ko else "BATTLE STYLE")
	Text.place_string(1, 13, " 교체       유지" if ko else " SHIFT    SET")
	Text.place_string(2, 16, "취소" if ko else "CANCEL")
	# SetCursorPositionsFromOptions
	var speed_x := 7
	for x in SPEED_BY_X:
		if SPEED_BY_X[x] == Settings.text_delay():
			speed_x = x
	var anim_x := 1 if Settings.battle_animation_on() else 10
	var style_x := 1 if Settings.battle_style_shift() else 10
	Text.put(speed_x, 3, ARROW_UNFILLED)
	Text.put(anim_x, 8, ARROW_UNFILLED)
	Text.put(style_x, 13, ARROW_UNFILLED)
	Text.put(1, 16, ARROW_UNFILLED)
	var x := speed_x
	var y := 3
	await GB.delay3()
	while true:
		Text.put(x, y, Text.CURSOR)
		_set_options(speed_x, anim_x, style_x)
		var keys := 0
		while keys == 0:
			await GB.frame
			keys = GB.joy5 & ~GB.SELECT
		if keys & (GB.B | GB.START):
			break
		if keys & GB.A:
			if y == 16:
				break
			continue
		if keys & GB.DOWN:
			Text.put(x, y, ARROW_UNFILLED)
			match y:
				16: y = 3; x = speed_x
				3: y = 8; x = anim_x
				8: y = 13; x = style_x
				_: y = 16; x = 1
			continue
		if keys & GB.UP:
			Text.put(x, y, ARROW_UNFILLED)
			match y:
				8: y = 3; x = speed_x
				13: y = 8; x = anim_x
				16: y = 13; x = style_x
				_: y = 16; x = 1
			continue
		# left / right
		match y:
			8:
				Text.put(x, y, Menu.SPACE)
				anim_x = 11 - anim_x
				x = anim_x
			13:
				Text.put(x, y, Menu.SPACE)
				style_x = 11 - style_x
				x = style_x
			3:
				Text.put(x, y, Menu.SPACE)
				if keys & GB.LEFT:
					if speed_x == 7:
						speed_x = 1
					elif speed_x == 14:
						speed_x = 7
				else:
					if speed_x == 1:
						speed_x = 7
					elif speed_x == 7:
						speed_x = 14
				x = speed_x
			_:
				pass
	Sound.play_sfx("SFX_PRESS_AB")


static func _set_options(speed_x: int, anim_x: int, style_x: int) -> void:
	var v: int = SPEED_BY_X[speed_x]
	if anim_x == 10:
		v |= Settings.BIT_BATTLE_ANIMATION
	if style_x == 10:
		v |= Settings.BIT_BATTLE_SHIFT
	Settings.set_options(v)
