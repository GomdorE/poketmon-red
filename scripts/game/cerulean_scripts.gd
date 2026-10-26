## Chapter 4 city and indoor scripts (original scripts/Cerulean*.asm).
class_name CeruleanScripts
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
		"CERULEAN_CITY":
			await _city()
			return true
		"CERULEAN_GYM":
			if entered:
				Text.ram["wGymCityName"] = "블루시티" if GameData.lang == "ko" else "CERULEAN CITY"
				Text.ram["wGymLeaderName"] = "이슬" if GameData.lang == "ko" else "MISTY"
			# Map-local bridge for the original up-facing hidden event.
			_register_hidden_text("GymStatues", "TEXT_CERULEANGYM_STATUE")
			await _gym()
			return true
		"CERULEAN_BADGE_HOUSE":
			ow.no_auto_text_box = true
			ow.do_not_wait_after_text = false
	return false


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_CERULEANCITY_RIVAL":
			await ow.print_text("_CeruleanCityRivalIWentToBillsText" if state.has_event("EVENT_BEAT_CERULEAN_RIVAL") else "_CeruleanCityRivalPreBattleText")
		"TEXT_CERULEANCITY_ROCKET": await _rocket(npc_index)
		"TEXT_CERULEANCITY_COOLTRAINER_F1":
			var r := ow.rng.randi_range(0, 255)
			var suffix := "SlowbroUseSonicboomText" if r >= 180 else ("SlowbroPunchText" if r >= 100 else "SlowbroWithdrawText")
			await ow.print_text("_CeruleanCityCooltrainerF1" + suffix)
		"TEXT_CERULEANCITY_SLOWBRO":
			var r := ow.rng.randi_range(0, 255)
			var suffix := "TookASnoozeText" if r >= 180 else ("IsLoafingAroundText" if r >= 120 else ("TurnedAwayText" if r >= 60 else "IgnoredOrdersText"))
			await ow.print_text("_CeruleanCitySlowbro" + suffix)
		"TEXT_CERULEANCITY_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_CERULEANCITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		"TEXT_CERULEANCITY_BIKESHOP_SIGN": await ms._far("_CeruleanCityBikeShopSign")
		"TEXT_CERULEANCITY_GYM_SIGN": await ms._far("_CeruleanCityGymSign")
		"TEXT_CERULEANCITY_GUARD1", "TEXT_CERULEANCITY_GUARD2": await ms._far("_CeruleanCityGuardText")
		"TEXT_CERULEANPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_CERULEANPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_CERULEANMART_CLERK": await Pokemart.dialogue(ow, "CERULEAN_MART")
		"TEXT_CERULEANTRASHEDHOUSE_FISHING_GURU":
			await ow.print_text("_CeruleanTrashedHouseFishingGuruWhatsLostIsLostText" if state.item_count("TM28") > 0 else "_CeruleanTrashedHouseFishingGuruTheyStoleATMText")
		"TEXT_CERULEANGYM_MISTY": await _misty(npc_index)
		"TEXT_CERULEANGYM_GYM_GUIDE":
			await ow.print_text("_CeruleanGymGymGuideBeatMistyText" if state.has_event("EVENT_BEAT_MISTY") else "_CeruleanGymGymGuideChampInMakingText")
		"TEXT_CERULEANGYM_MISTY_CASCADE_BADGE_INFO": await ms._far("_CeruleanGymMistyCascadeBadgeInfoText")
		"TEXT_CERULEANGYM_MISTY_RECEIVED_TM11":
			await ms._far("_CeruleanGymMistyReceivedTM11Text")
			await Sound.text_sound("sound_get_item_1")
		"TEXT_CERULEANGYM_MISTY_TM11_NO_ROOM": await ms._far("_CeruleanGymMistyTM11NoRoomText")
		"TEXT_CERULEANGYM_STATUE": await _gym_statue()
		"TEXT_BIKESHOP_CLERK": await _bike_clerk()
		"TEXT_BIKESHOP_MIDDLE_AGED_WOMAN": await ms._far("_BikeShopMiddleAgedWomanText")
		"TEXT_BIKESHOP_YOUNGSTER":
			await ow.print_text("_BikeShopYoungsterCoolBikeText" if state.has_event("EVENT_GOT_BICYCLE") else "_BikeShopYoungsterTheseBikesAreExpensiveText")
		"TEXT_CERULEANBADGEHOUSE_MIDDLE_AGED_MAN": await _badge_house()
		_:
			return false
	return true


func _city() -> void:
	match ms._script_index():
		0:
			if not state.has_event("EVENT_BEAT_CERULEAN_ROCKET_THIEF") and ow.player.x == 30 and ow.player.y in [7, 9]:
				ow.set_npc_facing(1, Overworld.FACE_UP if ow.player.y == 7 else Overworld.FACE_DOWN)
				await GB.delay3()
				await ow.display_text_id("TEXT_CERULEANCITY_ROCKET", 1)
				return
			if state.has_event("EVENT_BEAT_CERULEAN_RIVAL") or ow.player.y != 6 or not ow.player.x in [20, 21]:
				return
			Sound.play_music("MUSIC_MEET_RIVAL")
			ow.joy_ignore = GB.CTRL_PAD
			if ow.player.x == 21:
				ow.set_npc_position(0, 21, ow.npcs[0].y)
			ow.show_object(0)
			ow.move_sprite(0, [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
			ms._set_script(1)
		1:
			if ow.npc_moving(0):
				return
			ow.joy_ignore = 0
			await ow.display_text_id("TEXT_CERULEANCITY_RIVAL", 0)
			await _face_rival()
			var team: int = {"SQUIRTLE": 7, "BULBASAUR": 8, "CHARMANDER": 9}.get(state.rival_starter, 9)
			ow.battle_request = {"trainer": "RIVAL1", "team": team, "name": state.rival_name,
				"win_text": "CeruleanCityRivalDefeatedText", "lose_text": "CeruleanCityRivalVictoryText"}
			ms._set_script(2)
		2:
			if not ow.last_battle_won:
				ow.hide_object(0)
				chapter.reset_script()
				return
			await _face_rival()
			ow.joy_ignore = GB.CTRL_PAD
			state.set_event("EVENT_BEAT_CERULEAN_RIVAL")
			await ow.display_text_id("TEXT_CERULEANCITY_RIVAL", 0)
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			var moves: Array = [Overworld.NPC_RIGHT if ow.player.x == 20 else Overworld.NPC_LEFT]
			for i in 6:
				moves.append(Overworld.NPC_DOWN)
			ow.move_sprite(0, moves)
			ms._set_script(3)
		3:
			if ow.npc_moving(0):
				return
			ow.hide_object(0)
			await Sound.play_default_music()
			chapter.reset_script()
		4:
			if ow.last_battle_won:
				ow.joy_ignore = GB.CTRL_PAD
				state.set_event("EVENT_BEAT_CERULEAN_ROCKET_THIEF")
				await ow.display_text_id("TEXT_CERULEANCITY_ROCKET", 1)
			chapter.reset_script()


func _face_rival() -> void:
	ow.set_npc_facing(0, Overworld.FACE_DOWN)
	await GB.frames(6)


func _rocket(npc_index: int) -> void:
	if not state.has_event("EVENT_BEAT_CERULEAN_ROCKET_THIEF"):
		await ow.print_text("_CeruleanCityRocketText")
		chapter.event_battle(npc_index, 4, "_CeruleanCityRocketIGiveUpText")
		return
	await ow.print_text("_CeruleanCityRocketIllReturnTheTMText")
	if not state.give_item("TM28", 1):
		await ow.print_text("_CeruleanCityRocketTM28NoRoomText")
		return
	ow.do_not_wait_after_text = true
	await ow.print_text("_CeruleanCityRocketReceivedTM28Text")
	await Sound.text_sound("sound_get_item_1")
	await ow.print_text("_CeruleanCityRocketIBetterGetMovingText")
	await Text.wait_scroll_button(false)
	await Intro.fade_out_to_black()
	ow.show_object(5)
	ow.hide_object(10)
	ow.hide_object(1)
	ow.reload_map_view()
	await Intro.fade_in_from_black()
	chapter.trace("CERULEAN_TM28 item=%d rocket_hidden=%s" % [state.item_count("TM28"), str(ow.npcs[1].hidden)])


func _gym() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			if not ow.last_battle_won:
				chapter.reset_script()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _receive_tm11()


func _receive_tm11() -> void:
	await ow.display_text_id("TEXT_CERULEANGYM_MISTY_CASCADE_BADGE_INFO", -1)
	state.set_event("EVENT_BEAT_MISTY")
	if state.give_item("TM11", 1):
		await ow.display_text_id("TEXT_CERULEANGYM_MISTY_RECEIVED_TM11", -1)
		state.set_event("EVENT_GOT_TM11")
	else:
		await ow.display_text_id("TEXT_CERULEANGYM_MISTY_TM11_NO_ROOM", -1)
	state.badges |= 2
	state.beat_gym_flags |= 2
	state.set_event("EVENT_BEAT_CERULEAN_GYM_TRAINER_0")
	state.set_event("EVENT_BEAT_CERULEAN_GYM_TRAINER_1")
	chapter.reset_script()
	chapter.trace("MISTY_VICTORY badges=%d tm11=%d" % [state.badges, state.item_count("TM11")])


func _misty(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_MISTY"):
		if state.has_event("EVENT_GOT_TM11"):
			await ow.print_text("_CeruleanGymMistyTM11ExplanationText")
		else:
			await _receive_tm11()
			ow.do_not_wait_after_text = true
		return
	await ow.print_text("_CeruleanGymMistyPreBattleText")
	chapter.event_battle(npc_index, 3, "CeruleanGymMistyReceivedCascadeBadgeText", "", 2)


func _register_hidden_text(function_name: String, text_id: String) -> void:
	if ow.player.facing != Overworld.FACE_UP:
		# Hidden events check facing before opening a text box. Do not create a
		# side-facing background event that would flash an empty message box.
		ow.map.bg_events = ow.map.bg_events.filter(func(b: Dictionary) -> bool: return str(b.text) != text_id)
		return
	for e in ow.map.get("hidden_events", []):
		if e.func != function_name:
			continue
		var exists := false
		for b in ow.map.bg_events:
			if b.x == e.x and b.y == e.y:
				exists = true
		if not exists:
			ow.map.bg_events.append({"x": e.x, "y": e.y, "text": text_id})


func _gym_statue() -> void:
	if ow.player.facing != Overworld.FACE_UP:
		ow.do_not_wait_after_text = true
		return
	# scripts/CeruleanGym.asm .CityName/.LeaderName, including the Korean source.
	Text.ram["wGymCityName"] = "블루시티" if GameData.lang == "ko" else "CERULEAN CITY"
	Text.ram["wGymLeaderName"] = "이슬" if GameData.lang == "ko" else "MISTY"
	await ow.print_text("_GymStatueText2" if state.badges & 2 else "_GymStatueText1")


func _bike_clerk() -> void:
	if state.has_event("EVENT_GOT_BICYCLE"):
		await ow.print_text("_BikeShopClerkHowDoYouLikeYourBicycleText")
		return
	if state.item_count("BIKE_VOUCHER") > 0:
		await ow.print_text("_BikeShopClerkOhThatsAVoucherText")
		if not state.give_item("BICYCLE", 1):
			await ow.print_text("_BikeShopBagFullText")
			return
		state.remove_item("BIKE_VOUCHER")
		state.set_event("EVENT_GOT_BICYCLE")
		await ow.print_text("_BikeShopExchangedVoucherText")
		await Sound.text_sound("sound_get_key_item")
		chapter.trace("BIKE_EXCHANGED voucher=%d bicycle=%d" % [state.item_count("BIKE_VOUCHER"), state.item_count("BICYCLE")])
		return
	await ow.print_text("_BikeShopClerkWelcomeText")
	Menu.draw_box(0, 0, 15, 4)
	Text.place_string(2, 2, GameData.item_name("BICYCLE"))
	Text.place_string(2, 4 if GameData.lang == "ko" else 3, "취소" if GameData.lang == "ko" else "CANCEL")
	Text.place_string(8, 3, "¥1000000")
	await ow.print_text("_BikeShopClerkDoYouLikeItText")
	var key := await Menu.handle_input(1, 2, 2, GB.A | GB.B, 2 if GameData.lang == "ko" else 1)
	Menu.erase_cursor()
	if key & GB.A and Menu.current == 0:
		await ow.print_text("_BikeShopCantAffordText")
	await ow.print_text("_BikeShopComeAgainText")


func _badge_house() -> void:
	await ow.print_text("_CeruleanBadgeHouseMiddleAgedManText")
	var names: Array = ["BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE", "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE"]
	var labels := ["Boulder", "Cascade", "Thunder", "Rainbow", "Soul", "Marsh", "Volcano", "Earth"]
	var offset := 0
	var cursor := 0
	while true:
		await ow.print_text("_CeruleanBadgeHouseMiddleAgedManWhichBadgeText")
		var chosen := await ListMenu.show_items(names, false, false, null, offset, cursor)
		offset = ListMenu.last_offset
		cursor = ListMenu.last_cursor
		if chosen < 0:
			break
		await ow.print_text("_CeruleanBadgeHouse%sBadgeText" % labels[chosen])
	await ow.print_text("_CeruleanBadgeHouseMiddleAgedManVisitAnyTimeText")
