## The trainer card: StartMenu_TrainerInfo / DrawTrainerInfo (engine/menus/start_sub_menus.asm)
## and DrawBadges (engine/menus/draw_badges.asm).
class_name TrainerCard
extends RefCounted


## TrainerInfoTextBoxTileGraphics replaces vChars2 $77-$7E: tile 0 bottom edge, 1 right
## edge, 2 upper left, 3 top edge, 4 upper right, 5 left edge, 6 lower left, 7 lower
## right; tile 8 is the background pattern ($d7).
static func _t(i: int) -> int:
	return GB.screen.tile("trainer_info", i)


static func show(state: GameState) -> void:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	S.white_out()   # GBPalWhiteOut
	Text.clear_screen()
	S.clear_sprites()
	# DisplayPicCenteredOrUpperRight ($01): the player's pic at (15, 1); the columns that
	# wrap past the screen edge are blanked by the two ' ' vertical lines at (0, 2) and (1, 2)
	Title.draw_pic(S, "pic_red", 15, 1)
	for y in range(2, 10):
		Text.put(0, y, Text.SPACE)
		Text.put(1, y, Text.SPACE)
	_text_box(0, 0, 18)
	_text_box(1, 10, 16)
	for y in range(10, 18):
		S.set_bg(0, y, _t(8))
		S.set_bg(19, y, _t(8))
	# $76 BADGES $76 at (6, 9)
	var circle := S.tile("circle_tile", 0)
	S.set_bg(6, 9, circle)
	var end := Text.place_string(7, 9, "배지" if ko else "BADGES")
	S.set_bg(end.x, 9, circle)
	# NAME/ MONEY/ TIME/ at (2, 2), (2, 4), (2, 6)
	Text.place_string(2, 2, "이름/" if ko else "NAME/")
	Text.place_string(2, 4, "소지금/" if ko else "MONEY/")
	Text.place_string(2, 6, "시간/" if ko else "TIME/")
	Text.place_string(7, 2, state.player_name)
	# PrintBCDNumber 3 | LEADING_ZEROES | LEFT_ALIGN | MONEY_SIGN: ¥ then the digits
	# (the Korean label "소지금/" reaches column 8, so the amount starts one column later)
	var mx := 9 if ko else 8
	Text.put(mx, 4, ListMenu.MONEY_SIGN)
	Text.place_string(mx + 1, 4, str(state.money))
	# play time: hours (LEFT_ALIGN, up to 3 digits), the colon tile, minutes with leading zeros
	var tend := Text.place_string(9, 6, str(GB.play_time_hours))
	S.set_bg(tend.x, 6, S.tile("font_extra", 13))   # TextBoxGraphics tile 13 ($d6)
	Text.place_string(tend.x + 1, 6, "%02d" % GB.play_time_minutes)
	_draw_badges(state)
	SGB.run("TRAINER_CARD")
	S.normal_pals()
	await Text.wait_scroll_button(false)
	# GBPalWhiteOut; the caller restores the screen (LoadScreenTilesFromBuffer2, ReloadMapData, LoadGBPal)
	S.white_out()
	Text.clear_screen()


## TrainerInfo_DrawTextBox: a box of inner width `w`, always 6 rows high.
static func _text_box(x: int, y: int, w: int) -> void:
	var S: GBScreen = GB.screen
	S.set_bg(x, y, _t(2))
	for i in w:
		S.set_bg(x + 1 + i, y, _t(3))
	S.set_bg(x + w + 1, y, _t(4))
	for r in 6:
		S.set_bg(x, y + 1 + r, _t(5))
		S.set_bg(x + w + 1, y + 1 + r, _t(1))
	S.set_bg(x, y + 7, _t(6))
	for i in w:
		S.set_bg(x + 1 + i, y + 7, _t(0))
	S.set_bg(x + w + 1, y + 7, _t(7))


## DrawBadges: two rows of four gym leaders at (2, 11) and (2, 14) — the badge number,
## the (blank) leader name tiles when the badge is not owned, then the 2x2 face, or the
## badge in place of the face once it is owned.
static func _draw_badges(state: GameState) -> void:
	var S: GBScreen = GB.screen
	for k in 8:
		var x := 2 + 4 * (k % 4)
		var y := 11 if k < 4 else 14
		var owned := (state.badges >> k) & 1 == 1
		S.set_bg(x, y, S.tile("badge_numbers", k))
		if not owned:
			S.set_bg(x + 1, y, S.tile("blank_leader_names", 2 * k))
			S.set_bg(x + 2, y, S.tile("blank_leader_names", 2 * k + 1))
		var base := 8 * k + (4 if owned else 0)
		S.set_bg(x + 1, y + 1, S.tile("badges", base))
		S.set_bg(x + 2, y + 1, S.tile("badges", base + 1))
		S.set_bg(x + 1, y + 2, S.tile("badges", base + 2))
		S.set_bg(x + 2, y + 2, S.tile("badges", base + 3))
