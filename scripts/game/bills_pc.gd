## Bill's / someone's PC: the Pokémon Storage System (engine/pokemon/bills_pc.asm BillsPC_,
## BillsPCMenu, Withdraw / Deposit / Release, DisplayMonListMenu (home/list_menu.asm
## PCPOKEMONLISTMENU), DisplayDepositWithdrawMenu) and CHANGE BOX (engine/menus/save.asm
## ChangeBox / DisplayChangeBoxMenu). Boxes live in GameState.boxes (12 × MONS_PER_BOX).
class_name BillsPC
extends RefCounted

const MONS_PER_BOX := 20
const NUM_BOXES := 12
const UNFILLED_CURSOR := 0xEC

static var saved_menu_item := 0   # wPartyAndBillsPCSavedMenuItem (the list cursor)


## BillsPC_. `generic`: reached through the Pokémon Center PC main menu (no switch-on sound);
## `buffer2` is the screen to restore between menus (SaveScreenTilesToBuffer2).
static func run(ow, generic: bool, buffer2: PackedInt32Array) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var ko := GameData.lang == "ko"
	Text.no_delay = true
	var parent := 0   # wParentMenuItem
	if not generic:
		Sound.play_sfx("SFX_TURN_ON_PC")
		await Text.print_text("_SwitchOnText")
	while true:
		# BillsPCMenu
		S.restore_bg(buffer2)
		Menu.draw_box(0, 0, 12, 10)
		var lines := ["포켓몬 꺼내기", "포켓몬 맡기기", "포켓몬 놓아주기", "박스 변경", "종료"] if ko \
			else ["WITHDRAW <PKMN>", "DEPOSIT <PKMN>", "RELEASE <PKMN>", "CHANGE BOX", "SEE YA!"]
		for i in 5:
			Text.place_string(2, 2 + i * 2, lines[i])
		saved_menu_item = 0
		await Text.print_text("_WhatText")
		Menu.draw_box(9, 14, 9, 2)
		_place_box_number(17, 16, state.current_box)
		Text.place_string(10, 16, "박스 번호" if ko else "BOX No.")
		await GB.delay3()
		var keys := await Menu.handle_input(1, 2, 5, GB.A | GB.B, 2, parent)
		var cur := Menu.current
		Menu.erase_cursor()
		if keys & GB.B:
			break
		Text.put(1, 2 + cur * 2, UNFILLED_CURSOR)   # PlaceUnfilledArrowMenuCursor
		parent = cur
		if HiddenEvents.TRACE:
			print("PC_BILLS frame=%d choice=%d party=%d box=%d current_box=%d" % [GB.frame_count, cur, state.party.size(), state.box.size(), state.current_box])
		match cur:
			0:
				await _withdraw(ow)
			1:
				await _deposit(ow)
			2:
				await _release(ow)
			3:
				await _change_box(ow)
			_:
				break
	# ExitBillsPC
	if not generic:
		Sound.play_sfx("SFX_TURN_OFF_PC")
		await Sound.wait_for_sfx()
	Menu.no_button_sound = false
	S.restore_bg(buffer2)
	Text.no_delay = false


## The box number: "1".."9" at (x+1, y), "10".."12" as '1' at (x, y) and the digit at (x+1, y).
static func _place_box_number(x: int, y: int, box_index: int) -> void:
	var n := box_index + 1
	if n >= 10:
		Text.place_string(x, y, "1")
		Text.place_string(x + 1, y, str(n - 10))
	else:
		Text.place_string(x + 1, y, str(n))


static func _box_num_string(box_index: int) -> String:
	return str(box_index + 1)


## BillsPCDeposit.
static func _deposit(ow) -> void:
	var state: GameState = ow.state
	if state.party.size() <= 1:
		await Text.print_text("_CantDepositLastMonText")
		return
	if state.box.size() >= MONS_PER_BOX:
		await Text.print_text("_BoxFullText")
		return
	var idx := await _mon_list(state.party)
	if idx < 0:
		return
	var mon: PartyMon = state.party[idx]
	if not await _deposit_withdraw_menu(ow, mon, true):
		return
	await Sound.wait_for_sfx()   # PlaySoundWaitForCurrent with the cry
	Sound.play_cry(mon.species)
	# MoveMon PARTY_TO_BOX + RemovePokemon
	state.box.append(mon)
	state.party.remove_at(idx)
	await Sound.wait_for_sfx()
	Text.ram["wStringBuffer"] = mon.nickname
	Text.ram["wBoxNumString"] = _box_num_string(state.current_box)
	await Text.print_text("_MonWasStoredText")


## BillsPCWithdraw.
static func _withdraw(ow) -> void:
	var state: GameState = ow.state
	if state.box.is_empty():
		await Text.print_text("_NoMonText")
		return
	if state.party.size() >= 6:
		await Text.print_text("_CantTakeMonText")
		return
	var idx := await _mon_list(state.box)
	if idx < 0:
		return
	var mon: PartyMon = state.box[idx]
	if not await _deposit_withdraw_menu(ow, mon, false):
		return
	Text.ram["wStringBuffer"] = mon.nickname
	await Sound.wait_for_sfx()
	Sound.play_cry(mon.species)
	# MoveMon BOX_TO_PARTY + RemovePokemon
	state.party.append(mon)
	state.box.remove_at(idx)
	await Sound.wait_for_sfx()
	await Text.print_text("_MonIsTakenOutText")


## BillsPCRelease.
static func _release(ow) -> void:
	var state: GameState = ow.state
	if state.box.is_empty():
		await Text.print_text("_NoMonText")
		return
	while true:
		var idx := await _mon_list(state.box)
		if idx < 0:
			return
		var mon: PartyMon = state.box[idx]
		Text.ram["wStringBuffer"] = mon.nickname
		await Text.print_text("_OnceReleasedText")
		if not await Menu.yes_no(14, 7):
			continue
		state.box.remove_at(idx)
		await Sound.wait_for_sfx()
		Sound.play_cry(mon.species)
		await Sound.wait_for_sfx()
		await Text.print_text("_MonWasReleasedText")
		return


## DisplayMonListMenu / DisplayListMenuID (PCPOKEMONLISTMENU): names at (6, 4 + 2i) with the
## level under them at (14, 5 + 2i), CANCEL last, four entries per page. Returns the index or -1.
static func _mon_list(mons: Array) -> int:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	Menu.draw_box(4, 2, 14, 9)
	var count := mons.size()
	var max_item := 1 if count < 2 else 2
	var offset := 0
	var cur := clampi(saved_menu_item, 0, max_item)
	await GB.frames(10)
	while true:
		# PrintListMenuEntries
		Text.clear_area(5, 3, 14, 9)
		var printed := 0
		for i in 4:
			var idx := offset + i
			var y := 4 + i * 2
			if idx == count:
				Text.place_string(6, y, "취소" if ko else "CANCEL")
				break
			if idx > count:
				break
			var m: PartyMon = mons[idx]
			Text.place_string(6, y, m.nickname)
			MonHud.draw_level(14, y + 1, m.level)
			printed += 1
		if printed == 4:
			Text.put(18, 11, Text.ARROW_DOWN)
		await GB.delay3()
		Menu.place_cursor(5, 4 + cur * 2)
		var keys := 0
		while keys == 0:
			await GB.frame
			keys = GB.joy5
		if keys & GB.A:
			Sound.play_sfx("SFX_PRESS_AB")
			Menu.erase_cursor()
			saved_menu_item = cur
			var chosen := offset + cur
			if chosen >= count:
				return -1
			return chosen
		if keys & GB.B:
			Sound.play_sfx("SFX_PRESS_AB")
			Menu.erase_cursor()
			saved_menu_item = cur
			return -1
		if keys & GB.DOWN:
			if cur < max_item:
				Menu.erase_cursor()
				cur += 1
			elif offset + 3 < count:
				offset += 1
		elif keys & GB.UP:
			if cur > 0:
				Menu.erase_cursor()
				cur -= 1
			elif offset > 0:
				offset -= 1
	return -1


## DisplayDepositWithdrawMenu: DEPOSIT/WITHDRAW, STATS, CANCEL at (9, 10). STATS shows the
## status screen and comes back; returns true when DEPOSIT/WITHDRAW was chosen.
static func _deposit_withdraw_menu(ow, mon: PartyMon, deposit: bool) -> bool:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var ko := GameData.lang == "ko"
	while true:
		Menu.draw_box(9, 10, 9, 6)
		if deposit:
			Text.place_string(11, 12, "맡기기" if ko else "DEPOSIT")
		else:
			Text.place_string(11, 12, "꺼내기" if ko else "WITHDRAW")
		Text.place_string(11, 14, "상태" if ko else "STATS")
		Text.place_string(11, 16, "취소" if ko else "CANCEL")
		var keys := await Menu.handle_input(10, 12, 3, GB.A | GB.B)
		var cur := Menu.current
		Menu.erase_cursor()
		if keys & GB.B:
			return false
		if cur == 0:
			return true
		if cur != 1:
			return false
		# .viewStats: StatusScreen on the chosen mon (party or box), then the saved screen
		var saved := S.snapshot_bg()
		var view := GameState.new()
		view.party = [mon]
		view.player_name = state.player_name
		view.player_id = state.player_id
		await StatusScreen.show(view, 0)
		S.restore_bg(saved)
		SGB.run("DEFAULT")
		S.normal_pals()
	return false


## ChangeBox: confirm (the game is saved), then DisplayChangeBoxMenu.
static func _change_box(ow) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var ko := GameData.lang == "ko"
	await Text.print_text("_WhenYouChangeBoxText")
	if not await Menu.yes_no(14, 7):
		return
	# DisplayChangeBoxMenu
	Menu.draw_box(0, 0, 9, 2)
	await Text.print_text("_ChooseABoxText")
	Menu.draw_box(11, 0, 7, 12)
	for i in NUM_BOXES:
		# BoxNames: "BOX 1".."BOX12" on consecutive rows (the 8x16 Hangul "박스" would overlap)
		Text.place_string(13, 1 + i, "BOX%2d" % (i + 1))
		if not state.boxes[i].is_empty():
			S.set_bg(18, 1 + i, S.tile("balls", 0))   # the Poké Ball tile beside a used box
	_place_box_number(8, 2, state.current_box)
	Text.place_string(1, 2, "박스 번호" if ko else "BOX No.")
	var keys := await Menu.handle_input(12, 1, NUM_BOXES, GB.A | GB.B, 1, state.current_box)
	var cur := Menu.current
	Menu.erase_cursor()
	if keys & GB.B:
		return
	state.current_box = cur
	# SaveGameData, then SFX_SAVE
	state.x = ow.player.x
	state.y = ow.player.y
	state.facing = ow.player.facing
	SaveGame.write(state)
	await Sound.play_sfx_wait_for_current("SFX_SAVE")
	await Sound.wait_for_sfx()
