## Chapter 4 Nugget Bridge and Bill scripts (scripts/Route24, Route25, BillsHouse).
class_name CeruleanCapeScripts
extends RefCounted

var chapter: MtMoonScripts
var ms: MapScripts
var ow: Overworld
var state: GameState

func _init(c: MtMoonScripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state

func run_map_script(entered: bool) -> bool:
	match ow.map_id:
		"ROUTE_24":
			await _route24()
			return true
		"ROUTE_25":
			if entered:
				_toggle_bill()
		"BILLS_HOUSE":
			if entered:
				# Bridge the original hidden BillsHousePC coordinate through the
				# map-local text dispatcher; no shared engine files are modified.
				chapter.cerulean._register_hidden_text("BillsHousePC", "TEXT_BILLSHOUSE_ACTIVATE_PC")
			await _bills_house()
			return true
	return false


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_ROUTE24_COOLTRAINER_M1": await _bridge_rocket(npc_index)
		"TEXT_BILLSHOUSE_BILL_POKEMON":
			await ow.print_text("_BillsHouseBillImNotAPokemonText")
			if not await Menu.yes_no():
				await ow.print_text("_BillsHouseBillNoYouGottaHelpText")
			await ow.print_text("_BillsHouseBillUseSeparationSystemText")
			ms._set_script(1)
		"TEXT_BILLSHOUSE_BILL_SS_TICKET": await _ticket()
		"TEXT_BILLSHOUSE_BILL_CHECK_OUT_MY_RARE_POKEMON": await ow.print_text("_BillsHouseBillCheckOutMyRarePokemonText")
		"TEXT_BILLSHOUSE_ACTIVATE_PC": await _bills_pc()
		_:
			return false
	return true


func _route24() -> void:
	match ms._script_index():
		0:
			if not state.has_event("EVENT_GOT_NUGGET") and ow.player.x == 10 and ow.player.y == 15:
				await ow.display_text_id("TEXT_ROUTE24_COOLTRAINER_M1", 0)
				if state.has_event("EVENT_NUGGET_REWARD_AVAILABLE"):
					state.events.erase("EVENT_NUGGET_REWARD_AVAILABLE")
					ow.simulate([GB.DOWN])
					ms._set_script(4)
			else:
				await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			if ow.last_battle_won:
				ow.joy_ignore = GB.CTRL_PAD
				state.set_event("EVENT_BEAT_ROUTE24_ROCKET")
				await ow.display_text_id("TEXT_ROUTE24_COOLTRAINER_M1", 0)
			chapter.reset_script()
		4:
			if not ow.sim_queue.is_empty():
				return
			await GB.delay3()
			chapter.reset_script()


func _bridge_rocket(npc_index: int) -> void:
	state.events.erase("EVENT_NUGGET_REWARD_AVAILABLE")
	if state.has_event("EVENT_GOT_NUGGET"):
		await ow.print_text("_Route24CooltrainerM1YouCouldBecomeATopLeaderText")
		return
	await ow.print_text("_Route24CooltrainerM1YouBeatOurContestText")
	await Sound.text_sound("sound_get_item_1")
	await ow.print_text("_Route24CooltrainerM1YouJustEarnedAPrizeText")
	if not state.give_item("NUGGET", 1):
		await ow.print_text("_Route24CooltrainerM1NoRoomText")
		state.set_event("EVENT_NUGGET_REWARD_AVAILABLE")
		return
	state.set_event("EVENT_GOT_NUGGET")
	await ow.print_text("_Route24CooltrainerM1ReceivedNuggetText")
	await Sound.text_sound("sound_get_item_1")
	await Text.wait_scroll_button(false)
	await ow.print_text("_Route24CooltrainerM1JoinTeamRocketText")
	chapter.event_battle(npc_index, 3, "_Route24CooltrainerM1DefeatedText")
	chapter.trace("NUGGET_RECEIVED qty=%d" % state.item_count("NUGGET"))


func _toggle_bill() -> void:
	if state.has_event("EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING"):
		return
	if not state.has_event("EVENT_MET_BILL_2"):
		state.events.erase("EVENT_BILL_SAID_USE_CELL_SEPARATOR")
		ms._show_remote_object("BILLS_HOUSE", 0)
	elif state.has_event("EVENT_GOT_SS_TICKET"):
		state.set_event("EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING")
		ms._hide_remote_object("ROUTE_24", 0)
		ms._hide_remote_object("BILLS_HOUSE", 1)
		ms._show_remote_object("BILLS_HOUSE", 2)


func _bills_house() -> void:
	match ms._script_index():
		1:
			var moves: Array = [Overworld.NPC_UP, Overworld.NPC_UP, Overworld.NPC_UP]
			if ow.player.facing == Overworld.FACE_DOWN:
				moves = [Overworld.NPC_RIGHT, Overworld.NPC_UP, Overworld.NPC_UP, Overworld.NPC_LEFT, Overworld.NPC_UP]
			ow.move_sprite(0, moves)
			ms._set_script(2)
		2:
			if ow.npc_moving(0):
				return
			ow.hide_object(0)
			state.set_event("EVENT_BILL_SAID_USE_CELL_SEPARATOR")
			ow.joy_ignore = 0
			ms._set_script(3)
		3:
			if not state.has_event("EVENT_USED_CELL_SEPARATOR_ON_BILL"):
				return
			ow.joy_ignore = GB.CTRL_PAD
			ow.set_npc_position(1, 1, 2)
			ow.npcs[1].px = ow.player.px
			ow.npcs[1].py = ow.player.py - 48
			ow.show_object(1)
			await GB.frames(8)
			ow.move_sprite(1, [Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_DOWN])
			ms._set_script(4)
		4:
			if ow.npc_moving(1):
				return
			state.set_event("EVENT_MET_BILL_2")
			state.set_event("EVENT_MET_BILL")
			chapter.reset_script()
			chapter.trace("BILL_RESTORED")
		5:
			await ow.display_text_id("TEXT_BILLSHOUSE_ACTIVATE_PC", -1)
			ms._set_script(0)


func _ticket() -> void:
	if not state.has_event("EVENT_GOT_SS_TICKET"):
		await ow.print_text("_BillsHouseBillThankYouText")
		if not state.give_item("S_S_TICKET", 1):
			await ow.print_text("_SSTicketNoRoomText")
			return
		await ow.print_text("_SSTicketReceivedText")
		await Sound.text_sound("sound_get_key_item")
		await Text.wait_scroll_button(false)
		state.set_event("EVENT_GOT_SS_TICKET")
		ms._show_remote_object("CERULEAN_CITY", 5)
		ms._hide_remote_object("CERULEAN_CITY", 10)
		chapter.trace("SS_TICKET_RECEIVED qty=%d" % state.item_count("S_S_TICKET"))
	await ow.print_text("_BillsHouseBillWhyDontYouGoInsteadOfMeText")


## engine/events/hidden_events/bills_house_pc.asm.
func _bills_pc() -> void:
	if ow.player.facing != Overworld.FACE_UP:
		ow.do_not_wait_after_text = true
		return
	if state.has_event("EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING"):
		await _pokemon_list()
	elif state.has_event("EVENT_USED_CELL_SEPARATOR_ON_BILL") or not state.has_event("EVENT_BILL_SAID_USE_CELL_SEPARATOR"):
		await ow.print_text("_BillsHouseMonitorText")
	else:
		ow.do_not_wait_after_text = true
		await ow.print_text("_BillsHouseInitiatedText")
		await Text.wait_scroll_button(false)
		Sound.stop_all_music()
		await GB.frames(16)
		await _sound_and_wait("SFX_SWITCH")
		await GB.frames(60)
		await GB.frames(32)
		await _sound_and_wait("SFX_TINK")
		await GB.frames(80)
		await _sound_and_wait("SFX_SHRINK")
		await GB.frames(48)
		await _sound_and_wait("SFX_TINK")
		await GB.frames(32)
		await _sound_and_wait("SFX_GET_ITEM_1")
		await Sound.play_default_music()
		state.set_event("EVENT_USED_CELL_SEPARATOR_ON_BILL")
		chapter.trace("CELL_SEPARATOR_USED")


func _sound_and_wait(sfx: String) -> void:
	Sound.play_sfx(sfx)
	await Sound.wait_for_sfx()


func _pokemon_list() -> void:
	ow.do_not_wait_after_text = true
	await ow.print_text("_BillsHousePokemonListText1")
	var species := ["EEVEE", "FLAREON", "JOLTEON", "VAPOREON"]
	var chosen := 0
	while true:
		# Original menu (0,0), inner 9x10; Korean names occupy two rows.
		Menu.draw_box(0, 0, 9, 10)
		for i in 4:
			Text.place_string(2, 2 + i * 2, GameData.mon_name(species[i]))
		Text.place_string(2, 10, "취소" if GameData.lang == "ko" else "CANCEL")
		await ow.print_text("_BillsHousePokemonListText2")
		var key := await Menu.handle_input(1, 2, 5, GB.A | GB.B, 2, chosen)
		chosen = Menu.current
		Menu.erase_cursor()
		if key & GB.B or chosen == 4:
			return
		var saved: PackedInt32Array = GB.screen.snapshot_bg()
		await PokedexPage.new().show(species[chosen])
		GB.screen.restore_bg(saved)
		SGB.run("OVERWORLD", {"map": ow.map_id, "last_map": state.last_map})
		GB.screen.normal_pals()
