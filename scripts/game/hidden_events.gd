## Hidden events (home/hidden_events.asm CheckForHiddenEventOrBookshelfOrCardKeyDoor,
## engine/overworld/hidden_events.asm CheckForHiddenEvent, engine/events/hidden_events/*.asm)
## and bookshelves (engine/events/hidden_events/bookshelves.asm, data/tilesets/bookshelf_tile_ids.asm):
## what happens when A is pressed in front of a PC, bookshelf, poster, notebook...
## The map's `hidden_events` list comes from data/events/hidden_events.asm.
class_name HiddenEvents
extends RefCounted

## bookshelf_tile: tileset -> {tile id: predef text} (only the tilesets this port has)
const BOOKSHELVES := {
	"HOUSE": {0x3D: "TOWN_MAP", 0x1E: "_PokemonBooksText"},
	"REDS_HOUSE_1": {0x32: "_PokemonBooksText"},
	"DOJO": {0x1D: "_PokemonBooksText"},
	"GYM": {0x1D: "_PokemonBooksText"},
	"GATE": {0x22: "_PokemonBooksText"},
	"MART": {0x54: "_PokemonStuffText", 0x55: "_PokemonStuffText"},
	"POKECENTER": {0x54: "_PokemonStuffText", 0x55: "_PokemonStuffText"},
	"LOBBY": {0x16: "_ElevatorText", 0x50: "_PokemonStuffText", 0x52: "_PokemonStuffText"},
	"MANSION": {0x32: "_PokemonBooksText"},
}

const FACINGS := {"SPRITE_FACING_UP": 4, "SPRITE_FACING_DOWN": 0, "SPRITE_FACING_LEFT": 8, "SPRITE_FACING_RIGHT": 12}

## BenchGuyTextPointers (data/events/bench_guys.asm): map -> text
const BENCH_GUYS := {
	"VIRIDIAN_POKECENTER": "_ViridianCityPokecenterGuyText",
	"PEWTER_POKECENTER": "_PewterCityPokecenterGuyText",
	"CERULEAN_POKECENTER": "_CeruleanPokecenterGuyText",
	"LAVENDER_POKECENTER": "_LavenderPokecenterGuyText",
	"VERMILION_POKECENTER": "_VermilionPokecenterGuyText",
	"CELADON_POKECENTER": "_CeladonCityPokecenterGuyText",
	"FUCHSIA_POKECENTER": "_FuchsiaCityPokecenterGuyText",
	"CINNABAR_POKECENTER": "_CinnabarPokecenterGuyText",
	"MT_MOON_POKECENTER": "_MtMoonPokecenterBenchGuyText",
	"ROCK_TUNNEL_POKECENTER": "_RockTunnelPokecenterGuyText",
}

## MapBadgeFlags (data/maps/badge_maps.asm) and the gym names the gym scripts put in
## wGymCityName / wGymLeaderName.
const GYMS := {
	"VIRIDIAN_GYM": {"bit": 7, "city_en": "VIRIDIAN CITY", "leader_en": "GIOVANNI", "city_ko": "상록시티", "leader_ko": "비주기"},
	"PEWTER_GYM": {"bit": 0, "city_en": "PEWTER CITY", "leader_en": "BROCK", "city_ko": "회색시티", "leader_ko": "웅"},
	"CERULEAN_GYM": {"bit": 1, "city_en": "CERULEAN CITY", "leader_en": "MISTY", "city_ko": "블루시티", "leader_ko": "이슬"},
	"VERMILION_GYM": {"bit": 2, "city_en": "VERMILION CITY", "leader_en": "LT.SURGE", "city_ko": "갈색시티", "leader_ko": "마티스"},
	"CELADON_GYM": {"bit": 3, "city_en": "CELADON CITY", "leader_en": "ERIKA", "city_ko": "무지개시티", "leader_ko": "민화"},
}

static var TRACE := "--trace-pc" in OS.get_cmdline_user_args()   # test log

const BLACKBOARD_TEXTS := ["_ViridianBlackboardSleepText", "_ViridianBlackboardPoisonText", "_ViridianBlackboardPrlzText",
	"_ViridianBlackboardBurnText", "_ViridianBlackboardFrozenText"]


## Called from Overworld._interact when no NPC or sign was in front of the player.
## Returns true when a hidden event or a bookshelf was in front (whether or not it printed).
static func check(ow) -> bool:
	var d: Vector2i = ow._facing_delta()
	var tx: int = ow.player.x + d.x
	var ty: int = ow.player.y + d.y
	var events: Array = ow.map.get("hidden_events", [])
	for i in events.size():
		var e: Dictionary = events[i]
		if int(e["x"]) == tx and int(e["y"]) == ty:
			if TRACE:
				print("HIDDEN_EVENT frame=%d %s %s facing=%d" % [GB.frame_count, e["func"], e["arg"], ow.player.facing])
			await _run(ow, str(e["func"]), str(e["arg"]), i)
			return true
	# PrintBookshelfText: facing up, the tile in front against the tileset's bookshelf tiles
	if ow.player.facing != Overworld.FACE_UP:
		return false
	var table: Dictionary = BOOKSHELVES.get(str(ow.map["tileset"]), {})
	var tile: int = ow._tile_id_under(tx, ty)
	if not table.has(tile):
		return false
	var label: String = table[tile]
	if TRACE:
		print("BOOKSHELF frame=%d tile=%02x %s" % [GB.frame_count, tile, label])
	if label == "TOWN_MAP":
		await _town_map_text(ow)
	else:
		await ow._show_overworld_text(label, true)
	return true


static func _run(ow, func_name: String, arg: String, index: int = -1) -> void:
	var state: GameState = ow.state
	var facing: int = ow.player.facing
	match func_name:
		"StartSlotMachine":
			await ow.scripts.ch7.game_corner.start_slot_machine(arg, index)
		"HiddenCoins":
			await _hidden_coins(ow, arg)
		"PrintBenchGuyText":
			if facing == int(FACINGS.get(arg, -1)) and BENCH_GUYS.has(ow.map_id):
				await ow._show_overworld_text(BENCH_GUYS[ow.map_id], true)
		"PrintBookcaseText":
			await ow._show_overworld_text("_BookcaseText", true)
		"PrintRedSNESText":
			await ow._show_overworld_text("_RedBedroomSNESText", true)
		"OpenRedsPC":
			await _players_pc_script(ow)
		"DisplayOakLabLeftPoster":
			await ow._show_overworld_text("_PushStartText", true)
		"DisplayOakLabRightPoster":
			var owned := 0
			for sp in state.pokedex_owned:
				if state.pokedex_owned[sp]:
					owned += 1
			await ow._show_overworld_text("_SaveOptionText" if owned < 2 else "_StrengthsAndWeaknessesText", true)
		"DisplayOakLabEmailText":
			if facing == Overworld.FACE_UP:
				await ow._show_overworld_text("_OakLabEmailText", true)
		"OpenPokemonCenterPC":
			if facing == Overworld.FACE_UP:
				await _pokecenter_pc_script(ow)
		"PrintNotebookText":
			if arg == "ViridianSchoolNotebook":
				await _school_notebook(ow)
			elif arg == "TMNotebook":
				await ow._show_overworld_text("TMNotebookText", true)
		"PrintBlackboardLinkCableText":
			if arg == "ViridianSchoolBlackboard":
				await _school_blackboard(ow)
			elif arg == "LinkCableHelp":
				await _link_cable_help(ow)
		"GymStatues":
			if facing == Overworld.FACE_UP and GYMS.has(ow.map_id):
				var g: Dictionary = GYMS[ow.map_id]
				var ko := GameData.lang == "ko"
				Text.ram["wGymCityName"] = g["city_ko"] if ko else g["city_en"]
				Text.ram["wGymLeaderName"] = g["leader_ko"] if ko else g["leader_en"]
				var have: bool = (state.badges & (1 << int(g["bit"]))) != 0
				await ow._show_overworld_text("_GymStatueText2" if have else "_GymStatueText1", true)
		"HiddenItems":
			await _hidden_item(ow, arg)
		"PrintTrashText":
			await ow._show_overworld_text("_VermilionGymTrashText", true)
		"GymTrashScript":
			await ow.scripts.ch5.vermilion.gym_trash(int(arg))
		"BillsHousePC":
			# BillsHousePC: only facing up; the text script runs with the auto text box
			if facing == Overworld.FACE_UP:
				await ow.display_text_id("TEXT_BILLSHOUSE_ACTIVATE_PC", -1)
		"AerodactylFossil":
			await _fossil(ow, "mon_fossilaerodactyl", "_AerodactylFossilText")
		"KabutopsFossil":
			await _fossil(ow, "mon_fossilkabutops", "_KabutopsFossilText")
		_:
			pass


## HiddenItems (engine/events/hidden_items.asm): a hidden item is found once
## (wObtainedHiddenItemsFlags, kept as a per-coordinate event). The text does not wait
## for a button after SFX_GET_ITEM_2; a full bag waits, then prints HiddenItemBagFullText.
static func _hidden_item(ow, item: String) -> void:
	var state: GameState = ow.state
	var d: Vector2i = ow._facing_delta()
	var flag := "HIDDEN_ITEM_%s_%d_%d" % [ow.map_id, ow.player.x + d.x, ow.player.y + d.y]
	if state.has_event(flag):
		return
	ow.in_text = true
	Menu.message_box()
	await GB.delay3()
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	Text.ram["wNameBuffer"] = GameData.item_name(item)
	await Text.print_text_no_box("_FoundHiddenItemText")
	if state.give_item(item, 1):
		state.set_event(flag)
		Sound.play_sfx("SFX_GET_ITEM_2")
		await Sound.wait_for_sfx()
	else:
		await Text.wait_scroll_button(false)
		await Text.print_text("_HiddenItemBagFullText")
		await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


## HiddenCoins (engine/events/hidden_items.asm): coins for the COIN CASE, once per spot
## (wObtainedHiddenCoinsFlags, kept as a per-coordinate event). 40 coins give 20 (the
## original's typo), 100 give 100; a case at 9999 "drops" them.
static func _hidden_coins(ow, arg: String) -> void:
	var state: GameState = ow.state
	if state.item_count("COIN_CASE") == 0:
		return
	var d: Vector2i = ow._facing_delta()
	var flag := "HIDDEN_COIN_%s_%d_%d" % [ow.map_id, ow.player.x + d.x, ow.player.y + d.y]
	if state.has_event(flag):
		return
	var n := int(arg.get_slice("+", 1))
	var amount := n
	if n == 40:
		amount = 20
	elif n != 10 and n != 20:
		amount = 100
	state.coins = mini(state.coins + amount, 9999)
	state.set_event(flag)
	Text.ram["hCoins"] = str(amount)
	var dropped := state.coins == 9999
	if TRACE:
		print("HiddenCoins %d coins=%d dropped=%s" % [amount, state.coins, str(dropped)])
	ow.in_text = true
	Menu.message_box()
	await GB.delay3()
	await Text.print_text_no_box("_DroppedHiddenCoinsText" if dropped else "_FoundHiddenCoinsText")
	if not dropped:
		await Sound.text_sound("sound_get_item_2")
	await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


## AerodactylFossil / KabutopsFossil: DisplayMonFrontSpriteInBox (the MON_SPRITE_POPUP
## box (6,4)-(14,13), the 7x7 pic at (7,5), a button press, the screen restored),
## then the fossil text with the auto text box.
static func _fossil(ow, pic: String, label: String) -> void:
	var S: GBScreen = GB.screen
	ow.in_text = true
	await GB.delay3()
	var saved := S.snapshot_bg()
	Menu.draw_box(6, 4, 7, 8)
	Title.draw_pic(S, pic, 7, 5)
	await Text.wait_scroll_button(false)
	S.restore_bg(saved)
	ow.in_text = false
	ow._render()   # the player sprite comes back once (8, 9) is a map tile again
	await GB.delay3()
	await ow._show_overworld_text(label, true)


## TextScript_PokemonCenterPC: no auto text box; ActivatePC, then HoldTextDisplayOpen / CloseTextDisplay.
static func _pokecenter_pc_script(ow) -> void:
	ow.in_text = true
	await PokemonCenterPC.activate(ow)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


## TextScript_ItemStoragePC (Red's room PC): the auto text box is drawn, the screen saved
## to buffer 2 with it, then PlayerPC runs.
static func _players_pc_script(ow) -> void:
	var S: GBScreen = GB.screen
	ow.in_text = true
	Menu.message_box()
	var buffer2 := S.snapshot_bg()
	await PlayerPC.run(ow, false, buffer2)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


## TownMapText: "A TOWN MAP." then the map itself (DisplayTownMap), closing the text display.
static func _town_map_text(ow) -> void:
	var S: GBScreen = GB.screen
	ow.in_text = true
	Menu.message_box()
	await GB.delay3()
	await Text.print_text_no_box("_TownMapText")
	await Text.wait_scroll_button(true)
	Text.no_delay = true
	S.white_out()
	await GB.delay3()
	await TownMap.show(ow.state, ow)
	Text.no_delay = false
	# CloseTextDisplay
	ow.reload_map_view()
	SGB.run("DEFAULT")
	S.normal_pals()
	ow.in_text = false
	await GB.frame


## ViridianSchoolNotebook: five pages with "Turn the page?" between them.
static func _school_notebook(ow) -> void:
	ow.in_text = true
	Menu.message_box()
	await Text.print_text("_ViridianSchoolNotebookText1")
	if await _turn_page():
		await Text.print_text("_ViridianSchoolNotebookText2")
		if await _turn_page():
			await Text.print_text("_ViridianSchoolNotebookText3")
			if await _turn_page():
				await Text.print_text("_ViridianSchoolNotebookText4")
				await Text.print_text("_ViridianSchoolNotebookText5")
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


static func _turn_page() -> bool:
	await Text.print_text("_TurnPageText")
	return await Menu.yes_no(14, 7)


## ViridianSchoolBlackboard: two columns of status conditions; LEFT/RIGHT switch columns.
static func _school_blackboard(ow) -> void:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	ow.in_text = true
	Menu.message_box()
	var saved := S.snapshot_bg()
	await Text.print_text("_ViridianSchoolBlackboardText1")
	var cur := 0
	var col := 0
	while true:
		Text.no_delay = true
		Menu.draw_box(0, 0, 10, 6)
		var left := [" 잠듦", " 독", " 마비"] if ko else [" SLP", " PSN", " PAR"]
		var right := [" 화상", " 얼음", " 종료"] if ko else [" BRN", " FRZ", " QUIT"]
		for i in 3:
			Text.place_string(1, 2 + i * 2, left[i])
			Text.place_string(6, 2 + i * 2, right[i])
		await Text.print_text("_ViridianSchoolBlackboardText2")
		var keys := await Menu.handle_input(1 if col == 0 else 6, 2, 3, GB.LEFT | GB.RIGHT | GB.A | GB.B, 2, cur)
		cur = Menu.current
		Menu.erase_cursor()
		if keys & GB.B:
			break
		if keys & GB.RIGHT:
			col = 1
			continue
		if keys & GB.LEFT:
			col = 0
			continue
		var idx := cur + 3 * col
		if idx == 5:
			break
		Text.no_delay = false
		await Text.print_text(BLACKBOARD_TEXTS[idx])
	Text.no_delay = false
	S.restore_bg(saved)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame


## LinkCableHelp: the Game Link Cable help menu (the other blackboard script).
static func _link_cable_help(ow) -> void:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	ow.in_text = true
	Menu.message_box()
	var saved := S.snapshot_bg()
	await Text.print_text("_LinkCableHelpText1")
	var cur := 0
	while true:
		Text.no_delay = true
		Menu.draw_box(0, 0, 13, 8)
		var lines := ["통신 방법", "콜로세움", "교환센터", "그만 읽기"] if ko else ["HOW TO LINK", "COLOSSEUM", "TRADE CENTER", "STOP READING"]
		for i in 4:
			Text.place_string(2, 2 + i * 2, lines[i])
		await Text.print_text("_LinkCableHelpText2")
		var keys := await Menu.handle_input(1, 2, 4, GB.A | GB.B, 2, cur)
		cur = Menu.current
		Menu.erase_cursor()
		if keys & GB.B or cur == 3:
			break
		Text.no_delay = false
		await Text.print_text(["_LinkCableInfoText1", "_LinkCableInfoText2", "_LinkCableInfoText3"][cur])
	Text.no_delay = false
	S.restore_bg(saved)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()
	await GB.frame
