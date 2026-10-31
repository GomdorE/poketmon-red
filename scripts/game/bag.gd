## The Start menu ITEM screen (engine/menus/start_sub_menus.asm StartMenu_Item /
## ItemMenuLoop): the bag list, USE / TOSS, medicines through the party menu,
## the TOWN MAP and tossing (engine/items/item_effects.asm TossItem_).
class_name Bag
extends RefCounted

static var saved_item := 0     # wBagSavedMenuItem
static var saved_offset := 0


## Returns true when the Start menu must close after the item (UsableItems_CloseMenu),
## false when the caller redisplays the Start menu (the list was left with B).
## The overworld is redrawn through `ow.reload_map_view()` between items (ItemMenuLoop).
static func show(state: GameState, ow) -> bool:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	var first := true
	while true:
		if not first:
			# ItemMenuLoop: LoadScreenTilesFromBuffer2, RunDefaultPaletteCommand
			ow.reload_map_view()
			SGB.run("DEFAULT")
			S.normal_pals()
		first = false
		var names: Array = []
		for it in state.items:
			names.append(it.item)
		var pick := await ListMenu.show_items(names, false, true, state, saved_offset, saved_item)
		saved_item = ListMenu.last_cursor
		saved_offset = ListMenu.last_offset
		if pick < 0:
			return false
		# .choseItem: blank the cursor column, ▷ on the chosen item
		for y in [4, 6, 8, 10]:
			Text.put(5, y, Text.SPACE)
		Text.put(5, 4 + ListMenu.last_cursor * 2, 0xEC)
		var item: String = state.items[pick].item
		var qty: int = state.items[pick].qty
		# USE_TOSS_MENU_TEMPLATE at (13,10)-(19,14)
		Menu.draw_box(13, 10, 5, 3)
		Text.place_string(15, 11, "사용" if ko else "USE")
		Text.place_string(15, 13, "버리기" if ko else "TOSS")
		var keys := await Menu.handle_input(14, 11, 2, GB.A | GB.B)
		var sel := Menu.current
		Menu.cursor_pos = Vector2i(-1, -1)
		Text.put(14, 11 + sel * 2, 0xEC)
		if keys & GB.B:
			continue
		Text.ram["wStringBuffer"] = GameData.item_name(item)
		Text.ram["wNameBuffer"] = GameData.item_name(item)
		if sel == 0:
			if await _use(state, ow, item):
				return true
		else:
			await _toss(state, item, qty)
	return false


const REPEL_STEPS := {"REPEL": 100, "SUPER_REPEL": 200, "MAX_REPEL": 250}


## PrintItemUseTextAndRemoveItem: ItemUseText00 ("<PLAYER> used <item>!"),
## SFX_HEAL_AILMENT, a button press, then one of the item is removed.
static func _print_item_use_text_and_remove(state: GameState, item: String) -> void:
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ItemUseText001"))
	Text.cursor = Vector2i(1, 16)
	await Text.run_commands(GameData.text("_ItemUseText002"))
	Sound.play_sfx("SFX_HEAL_AILMENT")
	await Text.wait_scroll_button(false)
	state.remove_item(item, 1)


## UseItem outside of battle for the items of the first chapters.
static func _use(state: GameState, ow, item: String) -> bool:
	var S: GBScreen = GB.screen
	if ItemUse.is_medicine(item):
		await _use_medicine(state, item)
		# .useItem_partyMenu: GBPalWhiteOutWithDelay3, RestoreScreenTilesAndReloadTilePatterns
		S.white_out()
		await GB.delay3()
		S.clear_sprites()
		ow.reload_map_view()
		S.normal_pals()
		return false
	if item == "TOWN_MAP":
		await TownMap.show(state, ow)
		return false
	# ItemUseRepel / ItemUseRepelCommon: steps for REPEL, SUPER_REPEL, MAX_REPEL
	if item in REPEL_STEPS:
		state.repel_steps = int(REPEL_STEPS[item])
		await _print_item_use_text_and_remove(state, item)
		return false
	# the Bicycle and UsableItems_CloseMenu (rods, Escape Rope) close the start menu when used
	if item == "BICYCLE":
		if state.always_on_bike:   # StartMenu_Item: CannotGetOffHereText, back to the item list
			if "--trace-scripts" in OS.get_cmdline_user_args():
				print("BICYCLE cannot_get_off")
			await Text.print_text("_CannotGetOffHereText")
			return false
		return await FieldMoves.use_bicycle(state, ow)
	if item in ["OLD_ROD", "GOOD_ROD", "SUPER_ROD"]:
		return await Fishing.use_rod(state, ow, item)
	if item == "ESCAPE_ROPE":
		return await FieldMoves.escape_rope(state, ow)
	if item == "OAKS_PARCEL":
		await Text.print_text("_ItemUseNotYoursToUseText")
		return false
	if item == "ITEMFINDER":   # UsableItems_CloseMenu: the ITEMFINDER and the POKé FLUTE close the menu
		await _use_itemfinder(state, ow)
		return true
	if item == "POKE_FLUTE":   # ItemUsePokeFlute outside battle: only next to a sleeping SNORLAX
		# Route12SnorlaxFluteCoords / Route16SnorlaxFluteCoords
		var spots: Array = {"ROUTE_12": [Vector2i(9, 62), Vector2i(10, 61), Vector2i(10, 63), Vector2i(11, 62)],
			"ROUTE_16": [Vector2i(27, 10), Vector2i(25, 10)]}.get(ow.map_id, [])
		var route := "ROUTE12" if ow.map_id == "ROUTE_12" else "ROUTE16"
		var effect: bool = not state.has_event("EVENT_BEAT_%s_SNORLAX" % route) and Vector2i(ow.player.x, ow.player.y) in spots
		if "--trace-scripts" in OS.get_cmdline_user_args():
			print("POKE_FLUTE effect=%s" % str(effect))
		if effect:
			await Text.print_text("_PlayedFluteHadEffectText")
			state.set_event("EVENT_FIGHT_%s_SNORLAX" % route)
		else:
			await Text.print_text("_PlayedFluteNoEffectText")
		return true
	if item == "COIN_CASE":   # ItemUseCoinCase
		Text.ram["wPlayerCoins"] = str(state.coins)
		if "--trace-scripts" in OS.get_cmdline_user_args():
			print("COIN_CASE coins=%d" % state.coins)
		await Text.print_text("_CoinCaseNumCoinsText")
		return false
	if GameData.items.has(item) and GameData.items[item].has("move"):
		await _use_tm(state, ow, item)
		return false
	# Poké Balls outside of battle and the items of later chapters: ItemUseNotTime
	await Text.print_text("_ItemUseNotTimeText")
	return false


## ItemUseItemfinder: HiddenItemNear looks for an unobtained hidden item within 4 tiles
## above/below and 4 left / 5 right of the player; found, the machine beeps four times.
static func _use_itemfinder(state: GameState, ow) -> void:
	var found := false
	for e in ow.map.get("hidden_events", []):
		if str(e["func"]) != "HiddenItems":
			continue
		var ex := int(e["x"])
		var ey := int(e["y"])
		if state.has_event("HIDDEN_ITEM_%s_%d_%d" % [ow.map_id, ex, ey]):
			continue
		if ey > maxi(ow.player.y - 5, 0) and ey <= ow.player.y + 4 and ex > maxi(ow.player.x - 5, 0) and ex <= ow.player.x + 5:
			found = true
			break
	if found:
		for i in 4:
			await Sound.play_sfx_wait_for_current("SFX_HEALING_MACHINE")
			await Sound.play_sfx_wait_for_current("SFX_PURCHASE")
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("ITEMFINDER found=%s map=%s" % [str(found), ow.map_id])
	await Text.print_text("_ItemfinderFoundItemText" if found else "_ItemfinderFoundNothingText")


## ItemUseTMHM: "Booted up a TM/HM! It contained X! Teach X to a POKéMON?", the party menu
## with ABLE / NOT ABLE, CanLearnTM, CheckIfMoveIsKnown, LearnMove; a TM is used up.
static func _use_tm(state: GameState, ow, item: String) -> void:
	var S: GBScreen = GB.screen
	var is_hm := item.begins_with("HM")
	var move: String = str(GameData.items[item]["move"])
	Text.ram["wStringBuffer"] = GameData.move_name(move)
	await Text.print_text("_BootedUpHMText" if is_hm else "_BootedUpTMText")
	await Text.print_text("_TeachMachineMoveText")
	if not await Menu.yes_no(14, 7):
		return   # item not used: back to the item menu
	while true:
		PartyMenu.tm_move = move
		var idx := await PartyMenu.show(state, "tmhm")
		if idx < 0:
			break
		var mon: PartyMon = state.party[idx]
		Text.ram["wNameBuffer"] = mon.nickname
		Text.ram["wStringBuffer"] = GameData.move_name(move)
		var tmhm: Array = GameData.pokemon[mon.species]["tmhm"]
		if not (move in tmhm):
			await Sound.play_sfx_wait_for_current("SFX_DENIED")
			await Sound.wait_for_sfx()
			await Text.print_text("_MonCannotLearnMachineMoveText")
			continue
		if mon.has_move(move):
			await Text.print_text("_AlreadyKnowsText")
			continue
		var learned := await LearnMove.learn(mon, idx, move, false)
		if learned and not is_hm:
			state.remove_item(item, 1)
		break
	# GBPalWhiteOutWithDelay3, ClearSprites, RunDefaultPaletteCommand, the saved screen
	S.white_out()
	await GB.delay3()
	S.clear_sprites()
	ow.reload_map_view()
	SGB.run("DEFAULT")
	S.normal_pals()


## ItemUseMedicine: pick a mon, heal it with the sound and the HP bar animation,
## then redraw the party menu with the item message.
static func _use_medicine(state: GameState, item: String) -> void:
	var S: GBScreen = GB.screen
	var idx := await PartyMenu.show(state, "item")
	if idx < 0:
		return
	var mon: PartyMon = state.party[idx]
	var r := ItemUse.apply_medicine(mon, item)
	if not r.ok:
		await Text.print_text("_ItemUseNoEffectText")
		S.white_out()
		return
	state.remove_item(item, 1)
	if r.cured:
		await Sound.play_sfx_wait_for_current("SFX_HEAL_AILMENT")
	else:
		await Sound.play_sfx_wait_for_current("SFX_HEAL_HP")
		await PartyMenu.animate_hp(state, idx, int(r.old_hp), int(r.new_hp))
	Text.ram["wNameBuffer"] = mon.nickname
	Text.clear_screen()
	S.clear_sprites()
	await PartyMenu.redraw(state, str(r.message), idx)
	await GB.frames(50)
	await Text.wait_scroll_button(false)
	S.white_out()


## TossItem_: key items and HMs cannot be tossed; otherwise ask the quantity, confirm, remove.
static func _toss(state: GameState, item: String, qty: int) -> void:
	var key: bool = GameData.items.has(item) and GameData.items[item]["key"]
	if key or item.begins_with("HM"):
		await Text.print_text("_TooImportantToTossText")
		return
	var n := await ListMenu.choose_quantity(-1, qty)
	if n <= 0:
		return
	await Text.print_text("_IsItOKToTossItemText")
	if not await Menu.yes_no(14, 7):
		return
	state.remove_item(item, n)
	await Text.print_text("_ThrewAwayItemText")
