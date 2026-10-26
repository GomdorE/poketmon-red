## The Pokémon Center PC (engine/menus/pc.asm ActivatePC / PCMainMenu / LogOff and
## engine/pokemon/bills_pc.asm DisplayPCMainMenu, engine/menus/oaks_pc.asm OpenOaksPC).
class_name PokemonCenterPC
extends RefCounted


## ActivatePC: turn on, then the main menu until LOG OFF.
static func activate(ow) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var buffer2 := S.snapshot_bg()   # SaveScreenTilesToBuffer2 (the map, no text box)
	Sound.play_sfx("SFX_TURN_ON_PC")
	await Text.print_text("_TurnedOnPC1Text")
	await Sound.wait_for_sfx()
	S.restore_bg(buffer2)
	await GB.delay3()
	# PCMainMenu
	while true:
		var log_off := _display_main_menu(state)
		Menu.no_button_sound = true
		var keys := await Menu.handle_input(1, 2, log_off + 1, GB.A | GB.B)
		var cur := Menu.current
		Menu.erase_cursor()
		if HiddenEvents.TRACE:
			print("PC_MAIN frame=%d choice=%d keys=%d" % [GB.frame_count, cur, keys])
		if keys & GB.B or cur == log_off:
			break
		match cur:
			0:
				# BillsPC
				Sound.play_sfx("SFX_ENTER_PC")
				await Sound.wait_for_sfx()
				await Text.print_text("_AccessedBillsPCText" if state.has_event("EVENT_MET_BILL") else "_AccessedSomeonesPCText")
				await BillsPC.run(ow, true, buffer2)
			1:
				# .playersPC
				Menu.no_button_sound = false
				Sound.play_sfx("SFX_ENTER_PC")
				await Sound.wait_for_sfx()
				await Text.print_text("_AccessedMyPCText")
				await PlayerPC.run(ow, true, buffer2)
			2:
				# OaksPC
				Sound.play_sfx("SFX_ENTER_PC")
				await Sound.wait_for_sfx()
				await _open_oaks_pc(state, buffer2)
		# ReloadMainMenu: ReloadMapData + UpdateSprites
		ow.do_not_wait_after_text = false
		S.restore_bg(buffer2)
		SGB.run("DEFAULT")
		S.normal_pals()
		ow.reload_map_view()
	# LogOff
	Sound.play_sfx("SFX_TURN_OFF_PC")
	await Sound.wait_for_sfx()
	Menu.no_button_sound = false
	S.restore_bg(buffer2)


## DisplayPCMainMenu: the box with SOMEONE's/BILL's PC, <PLAYER>'s PC, (PROF.OAK's PC), LOG OFF.
## Returns the index of LOG OFF.
static func _display_main_menu(state: GameState) -> int:
	var ko := GameData.lang == "ko"
	var has_oak := state.has_event("EVENT_GOT_POKEDEX")
	Menu.draw_box(0, 0, 14, 8 if has_oak else 6)
	if state.has_event("EVENT_MET_BILL"):
		Text.place_string(2, 2, "이수재의 컴퓨터" if ko else "BILL's PC")
	else:
		Text.place_string(2, 2, "누군가의 컴퓨터" if ko else "SOMEONE's PC")
	var end := Text.place_string(2, 4, state.player_name)
	Text.place_string(end.x, 4, "의 컴퓨터" if ko else "'s PC")
	var log_off_text := "접속 종료" if ko else "LOG OFF"
	if has_oak:
		Text.place_string(2, 6, "오박사의 컴퓨터" if ko else "PROF.OAK's PC")
		Text.place_string(2, 8, log_off_text)
		return 3
	Text.place_string(2, 6, log_off_text)
	return 2


## OpenOaksPC: the Pokédex rating.
static func _open_oaks_pc(state: GameState, buffer2: PackedInt32Array) -> void:
	var S: GBScreen = GB.screen
	await Text.print_text("_AccessedOaksPCText")
	await Text.print_text("_GetDexRatedText")
	if await Menu.yes_no(14, 7):
		await DexRating.display(state)
	await Text.print_text("_ClosedOaksPCText")
	await Text.wait_scroll_button(true)   # text_waitbutton
	S.restore_bg(buffer2)
