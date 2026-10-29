## DisplayDiploma (engine/events/diploma.asm): the Pokédex diploma from the GAME FREAK
## game designer. A cable-club style border (TrainerInfoTextBoxTileGraphics) with the
## title between two circles, "Player <name>", the congratulations and GAME FREAK, and the
## title-screen player picture as sprites behind the background (OAM priority).
class_name Diploma
extends RefCounted


static func show(ow: Overworld) -> void:
	var state: GameState = ow.state
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	var saved := S.snapshot_bg()   # SaveScreenTilesToBuffer2
	ow.update_sprites = false      # wUpdateSpritesEnabled = 0: the OAM shows the player picture
	S.white_out()                  # GBPalWhiteOutWithDelay3
	await GB.delay3()
	Text.clear_screen()
	S.clear_sprites()
	_border(0, 0, 18, 16)          # Diploma_TextBoxBorder: 16 rows, 18 columns
	var circle := S.tile("circle_tile", 0)
	S.set_bg(5, 2, circle)
	var end := Text.place_string(6, 2, "도감완성증서" if ko else "Diploma")
	S.set_bg(end.x, 2, circle)
	Text.place_string(3, 4, "플레이어" if ko else "Player")
	Text.place_string(10, 4, state.player_name)
	if ko:
		var lines := ["축하합니다!", "포켓몬도감을", "완성했음을", "이 증서로", "인정합니다."]
		for i in lines.size():
			Text.place_string(2, 6 + i * 2, lines[i])
	else:
		var lines := ["Congrats! This", "diploma certifies", "that you have", "completed your", "#DEX."]
		for i in lines.size():
			Text.place_string(2, 6 + i, lines[i])
	Text.place_string(9, 16, "게임프리크" if ko else "GAME FREAK")
	# DrawPlayerCharacter: 7 rows of 5 sprites from (Y $60, X $5a), then 33 pixels to the
	# right with the priority bit set (behind the background)
	var t := 0
	for row in 7:
		for col in 5:
			S.set_sprite(t, 0x5A + 33 + col * 8 - 8, 0x60 + row * 8 - 16, S.tile("title_player", t), 0, false, false, true)
			t += 1
	SGB.run("GENERIC")
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("DIPLOMA shown frame=%d" % GB.frame_count)
	await GB.delay3()
	S.normal_pals()
	S.obp0 = S.pal(2, 1, 0, 0)   # rOBP0 = $90
	await Text.wait_scroll_button()
	S.white_out()
	await GB.delay3()
	# RestoreScreenTilesAndReloadTilePatterns
	S.clear_sprites()
	S.restore_bg(saved)
	await GB.delay3()
	S.normal_pals()
	ow.update_sprites = true


## CableClub_TextBoxBorder with the TrainerInfoTextBoxTileGraphics tiles ($76-$7d):
## inner width `w`, inner height `h`.
static func _border(x: int, y: int, w: int, h: int) -> void:
	var S: GBScreen = GB.screen
	S.set_bg(x, y, TrainerCard._t(2))
	for i in w:
		S.set_bg(x + 1 + i, y, TrainerCard._t(3))
	S.set_bg(x + w + 1, y, TrainerCard._t(4))
	for r in h:
		S.set_bg(x, y + 1 + r, TrainerCard._t(5))
		for i in w:
			Text.put(x + 1 + i, y + 1 + r, Text.SPACE)
		S.set_bg(x + w + 1, y + 1 + r, TrainerCard._t(1))
	S.set_bg(x, y + h + 1, TrainerCard._t(6))
	for i in w:
		S.set_bg(x + 1 + i, y + h + 1, TrainerCard._t(0))
	S.set_bg(x + w + 1, y + h + 1, TrainerCard._t(7))
