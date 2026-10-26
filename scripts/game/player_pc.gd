## The player's PC: the Item Storage System (engine/menus/players_pc.asm PlayerPC,
## PlayerPCMenu, Withdraw / Deposit / Toss). Stored items live in GameState.pc_items.
class_name PlayerPC
extends RefCounted

const PC_ITEM_CAPACITY := 50
const UNFILLED_CURSOR := 0xEC


## PlayerPC. `generic`: reached through the Pokémon Center PC (no switch-on sound);
## `buffer2` is the screen restored between menus (SaveScreenTilesToBuffer2).
static func run(ow, generic: bool, buffer2: PackedInt32Array) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var ko := GameData.lang == "ko"
	Text.no_delay = true
	var parent := 0
	if not generic:
		Sound.play_sfx("SFX_TURN_ON_PC")
		await Text.print_text("_TurnedOnPC2Text")
	while true:
		# PlayerPCMenu
		Menu.no_button_sound = true
		S.restore_bg(buffer2)
		Menu.draw_box(0, 0, 14, 8)
		var lines := ["도구 꺼내기", "도구 맡기기", "도구 버리기", "종료"] if ko else ["WITHDRAW ITEM", "DEPOSIT ITEM", "TOSS ITEM", "LOG OFF"]
		for i in 4:
			Text.place_string(2, 2 + i * 2, lines[i])
		await Text.print_text("_WhatDoYouWantText")
		var keys := await Menu.handle_input(1, 2, 4, GB.A | GB.B, 2, parent)
		var cur := Menu.current
		Menu.erase_cursor()
		if keys & GB.B:
			break
		Text.put(1, 2 + cur * 2, UNFILLED_CURSOR)
		parent = cur
		if HiddenEvents.TRACE:
			print("PC_PLAYER frame=%d choice=%d bag=%s pc=%s" % [GB.frame_count, cur, str(state.items), str(state.pc_items)])
		match cur:
			0:
				await _withdraw(state)
			1:
				await _deposit(state)
			2:
				await _toss(state)
			_:
				break
	# ExitPlayerPC
	if not generic:
		Sound.play_sfx("SFX_TURN_OFF_PC")
		await Sound.wait_for_sfx()
	Menu.no_button_sound = false
	S.restore_bg(buffer2)
	Text.no_delay = false
	ow.do_not_wait_after_text = false


## A GameState whose bag is the PC's item list, for ListMenu's quantity column.
static func _pc_view(state: GameState) -> GameState:
	var view := GameState.new()
	view.items = state.pc_items
	return view


static func _names(items: Array) -> Array:
	var names: Array = []
	for it in items:
		names.append(str(it["item"]))
	return names


static func _is_key(item: String) -> bool:
	return GameData.items.has(item) and bool(GameData.items[item]["key"])


## AddItemToInventory on the PC list (PC_ITEM_CAPACITY kinds, stacks of 99).
static func _add_pc_item(state: GameState, item: String, qty: int) -> bool:
	for it in state.pc_items:
		if str(it["item"]) == item and int(it["qty"]) + qty <= 99:
			it["qty"] = int(it["qty"]) + qty
			return true
	if state.pc_items.size() >= PC_ITEM_CAPACITY:
		return false
	state.pc_items.append({"item": item, "qty": qty})
	return true


static func _remove_pc_item(state: GameState, item: String, qty: int) -> void:
	for i in state.pc_items.size():
		if str(state.pc_items[i]["item"]) == item:
			state.pc_items[i]["qty"] = int(state.pc_items[i]["qty"]) - qty
			if int(state.pc_items[i]["qty"]) <= 0:
				state.pc_items.remove_at(i)
			return


## PlayerPCDeposit.
static func _deposit(state: GameState) -> void:
	if state.items.is_empty():
		await Text.print_text("_NothingToDepositText")
		return
	while true:
		await Text.print_text("_WhatToDepositText")
		var names := _names(state.items)
		var pick := await ListMenu.show_items(names, false, true, state)
		if pick < 0:
			return
		var item: String = names[pick]
		var qty := 1
		if not _is_key(item):
			await Text.print_text("_DepositHowManyText")
			qty = await ListMenu.choose_quantity(-1, state.item_count(item))
			if qty <= 0:
				continue
		if not _add_pc_item(state, item, qty):
			await Text.print_text("_NoRoomToStoreText")
			continue
		state.remove_item(item, qty)
		await Sound.wait_for_sfx()
		Sound.play_sfx("SFX_WITHDRAW_DEPOSIT")
		await Sound.wait_for_sfx()
		Text.ram["wNameBuffer"] = GameData.item_name(item)
		await Text.print_text("_ItemWasStoredText")


## PlayerPCWithdraw.
static func _withdraw(state: GameState) -> void:
	if state.pc_items.is_empty():
		await Text.print_text("_NothingStoredText")
		return
	while true:
		await Text.print_text("_WhatToWithdrawText")
		var names := _names(state.pc_items)
		var pick := await ListMenu.show_items(names, false, true, _pc_view(state))
		if pick < 0:
			return
		var item: String = names[pick]
		var qty := 1
		if not _is_key(item):
			await Text.print_text("_WithdrawHowManyText")
			qty = await ListMenu.choose_quantity(-1, int(state.pc_items[pick]["qty"]))
			if qty <= 0:
				continue
		if not state.give_item(item, qty):
			await Text.print_text("_CantCarryMoreText")
			continue
		_remove_pc_item(state, item, qty)
		await Sound.wait_for_sfx()
		Sound.play_sfx("SFX_WITHDRAW_DEPOSIT")
		await Sound.wait_for_sfx()
		Text.ram["wNameBuffer"] = GameData.item_name(item)
		await Text.print_text("_WithdrewItemText")


## PlayerPCToss: TossItem on the PC list (key items and HMs cannot be tossed).
static func _toss(state: GameState) -> void:
	if state.pc_items.is_empty():
		await Text.print_text("_NothingStoredText")
		return
	while true:
		await Text.print_text("_WhatToTossText")
		var names := _names(state.pc_items)
		var pick := await ListMenu.show_items(names, false, true, _pc_view(state))
		if pick < 0:
			return
		var item: String = names[pick]
		var qty := 1
		if _is_key(item) or item.begins_with("HM"):
			# TossItem_: too important
			await Text.print_text("_TooImportantToTossText")
			continue
		await Text.print_text("_TossHowManyText")
		qty = await ListMenu.choose_quantity(-1, int(state.pc_items[pick]["qty"]))
		if qty <= 0:
			continue
		Text.ram["wStringBuffer"] = GameData.item_name(item)
		Text.ram["wNameBuffer"] = GameData.item_name(item)
		await Text.print_text("_IsItOKToTossItemText")
		if not await Menu.yes_no(14, 7):
			continue
		_remove_pc_item(state, item, qty)
		await Text.print_text("_ThrewAwayItemText")
