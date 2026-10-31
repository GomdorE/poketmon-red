## Chapter 11 map scripts and text handlers: Fuchsia City and its buildings
## (scripts/FuchsiaCity.asm, FuchsiaGym.asm, WardensHouse.asm, FuchsiaGoodRodHouse.asm,
## FuchsiaBillsGrandpasHouse.asm, FuchsiaMeetingRoom.asm, FuchsiaMart.asm,
## FuchsiaPokecenter.asm) and the Safari Zone (SafariZoneGate.asm, the four areas, the rest
## houses, SafariZoneSecretHouse.asm). The Safari Game's steps and game over are in Overworld,
## its battles in Battle.
class_name Chapter11Scripts
extends RefCounted

const GOT_GOOD_ROD := "GOT_GOOD_ROD"   # wStatusFlags1 BIT_GOT_GOOD_ROD, kept with the events
const SAFARI_ENTRY := [Vector2i(3, 2), Vector2i(4, 2)]   # .PlayerNextToSafariZoneWorker1CoordsArray

var ms: MapScripts
var ow: Overworld
var state: GameState
var next_gate_script := 0   # wNextSafariZoneGateScript


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script (see MtMoonScripts.run_map_script for the contract).
func run_map_script() -> bool:
	match ow.map_id:
		"FUCHSIA_CITY", "FUCHSIA_MART", "FUCHSIA_BILLS_GRANDPAS_HOUSE", "FUCHSIA_POKECENTER", "WARDENS_HOUSE", \
				"FUCHSIA_MEETING_ROOM", "FUCHSIA_GOOD_ROD_HOUSE", "SAFARI_ZONE_EAST", "SAFARI_ZONE_NORTH", \
				"SAFARI_ZONE_WEST", "SAFARI_ZONE_CENTER", "SAFARI_ZONE_CENTER_REST_HOUSE", "SAFARI_ZONE_SECRET_HOUSE", \
				"SAFARI_ZONE_WEST_REST_HOUSE", "SAFARI_ZONE_EAST_REST_HOUSE", "SAFARI_ZONE_NORTH_REST_HOUSE":
			pass   # EnableAutoTextBoxDrawing only
		"FUCHSIA_GYM":
			await _gym()
		"SAFARI_ZONE_GATE":
			await _safari_gate()
		_:
			return false
	return true


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_SAFARI_GAME_OVER": await _safari_game_over_text()
		# Fuchsia City
		"TEXT_FUCHSIACITY_CHANSEY_SIGN": await _sign_with_dex("_FuchsiaCityChanseySignText", "CHANSEY")
		"TEXT_FUCHSIACITY_VOLTORB_SIGN": await _sign_with_dex("_FuchsiaCityVoltorbSignText", "VOLTORB")
		"TEXT_FUCHSIACITY_KANGASKHAN_SIGN": await _sign_with_dex("_FuchsiaCityKangaskhanSignText", "KANGASKHAN")
		"TEXT_FUCHSIACITY_SLOWPOKE_SIGN": await _sign_with_dex("_FuchsiaCitySlowpokeSignText", "SLOWPOKE")
		"TEXT_FUCHSIACITY_LAPRAS_SIGN": await _sign_with_dex("_FuchsiaCityLaprasSignText", "LAPRAS")
		"TEXT_FUCHSIACITY_FOSSIL_SIGN":
			# FuchsiaCityFossilSignText: the fossil the player did not take
			if state.has_event("EVENT_GOT_DOME_FOSSIL"):
				await _sign_with_dex("_FuchsiaCityFossilSignOmanyteText", "OMANYTE")
			elif state.has_event("EVENT_GOT_HELIX_FOSSIL"):
				await _sign_with_dex("_FuchsiaCityFossilSignKabutoText", "KABUTO")
			else:
				await ow.print_text("_FuchsiaCityFossilSignUndeterminedText")
		"TEXT_FUCHSIACITY_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_FUCHSIACITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		"TEXT_FUCHSIAPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_FUCHSIAPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_FUCHSIAMART_CLERK": await Pokemart.dialogue(ow, "FUCHSIA_MART")
		"TEXT_FUCHSIAGOODRODHOUSE_FISHING_GURU": await _good_rod()
		"TEXT_WARDENSHOUSE_WARDEN": await _warden()
		"TEXT_WARDENSHOUSE_DISPLAY_LEFT": await ow.print_text("_WardensHouseDisplayPhotosAndFossilsText")
		"TEXT_WARDENSHOUSE_DISPLAY_RIGHT": await ow.print_text("_WardensHouseDisplayMerchandiseText")
		# the gym
		"TEXT_FUCHSIAGYM_KOGA": await _koga_text(npc_index)
		"TEXT_FUCHSIAGYM_GYM_GUIDE":
			await ow.print_text("_FuchsiaGymGymGuideBeatKogaText" if state.has_event("EVENT_BEAT_KOGA") else "_FuchsiaGymGymGuideChampInMakingText")
		"TEXT_FUCHSIAGYM_KOGA_RECEIVED_TM06":
			await ow.print_text("_FuchsiaGymKogaReceivedTM06Text")
			await Sound.text_sound("sound_get_key_item")
			await ow.print_text("_FuchsiaGymKogaTM06ExplanationText")
		# the Safari Zone
		"TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1", "TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_1":
			await ow.print_text("_SafariZoneGateSafariZoneWorker1Text")
		"TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_WOULD_YOU_LIKE_TO_JOIN": await _would_you_like_to_join()
		"TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_LEAVING_EARLY": await _leaving_early()
		"TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_GOOD_HAUL_COME_AGAIN":
			await ow.print_text("_SafariZoneGateSafariZoneWorker1GoodHaulComeAgainText")
		"TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER2":
			await ow.print_text("_SafariZoneGateSafariZoneWorker2FirstTimeHereText")
			var yes := await Menu.yes_no()
			await ow.print_text("_SafariZoneGateSafariZoneWorker2SafariZoneExplanationText" if yes else "_SafariZoneGateSafariZoneWorker2YoureARegularHereText")
		"TEXT_SAFARIZONESECRETHOUSE_FISHING_GURU": await _hm03()
		_:
			return false
	return true


## A sign followed by the Pokédex page (DisplayPokedex), then back to the map.
func _sign_with_dex(label: String, species: String) -> void:
	var saved: PackedInt32Array = GB.screen.snapshot_bg()
	await ow.print_text(label)
	GB.screen.restore_bg(saved)
	Text.no_delay = true
	await PokedexPage.new().show(species)
	SGB.run("DEFAULT")
	Text.no_delay = false
	ow.reload_map_view()


# --- Fuchsia City's houses -------------------------------------------------------------------

## FuchsiaGoodRodHouseFishingGuruText: the GOOD ROD once (wStatusFlags1 BIT_GOT_GOOD_ROD).
func _good_rod() -> void:
	if state.has_event(GOT_GOOD_ROD):
		await ow.print_text("_FuchsiaGoodRodHouseFishingGuruHowAreTheFishText")
		return
	await ow.print_text("_FuchsiaGoodRodHouseFishingGuruText")
	if not await Menu.yes_no():
		await ow.print_text("_FuchsiaGoodRodHouseFishingGuruThatsSoDisappointingText")
		return
	if not state.give_item("GOOD_ROD", 1):
		await ow.print_text("_FuchsiaGoodRodHouseFishingGuruNoRoomText")
		return
	state.set_event(GOT_GOOD_ROD)
	Text.ram["wStringBuffer"] = GameData.item_name("GOOD_ROD")
	await ow.print_text("_FuchsiaGoodRodHouseFishingGuruReceivedGoodRodText")
	await Sound.text_sound("sound_get_item_1")
	trace("GOT_GOOD_ROD")


## WardensHouseWardenText: without his GOLD TEETH the warden only mumbles (yes/no); with
## them he takes the teeth and gives HM04 (STRENGTH).
func _warden() -> void:
	if state.has_event("EVENT_GOT_HM04"):
		await ow.print_text("_WardensHouseWardenHM04ExplanationText")
		return
	if state.item_count("GOLD_TEETH") > 0:
		await ow.print_text("_WardensHouseWardenGaveTheGoldTeethText")
		await Sound.text_sound("sound_get_item_1")
		state.remove_item("GOLD_TEETH", 1)
		state.set_event("EVENT_GAVE_GOLD_TEETH")
	elif not state.has_event("EVENT_GAVE_GOLD_TEETH"):
		await ow.print_text("_WardensHouseWardenGibberish1Text")
		var yes := await Menu.yes_no()
		await ow.print_text("_WardensHouseWardenGibberish2Text" if yes else "_WardensHouseWardenGibberish3Text")
		return
	await ow.print_text("_WardensHouseWardenThanksText")
	if not state.give_item("HM04", 1):
		await ow.print_text("_WardensHouseWardenHM04NoRoomText")
		return
	Text.ram["wStringBuffer"] = GameData.item_name("HM04")
	await ow.print_text("_WardensHouseWardenReceivedHM04Text")
	await Sound.text_sound("sound_get_item_1")
	state.set_event("EVENT_GOT_HM04")
	trace("GOT_HM04")


## SafariZoneSecretHouseFishingGuruText: HM03 (SURF) once.
func _hm03() -> void:
	if state.has_event("EVENT_GOT_HM03"):
		await ow.print_text("_SafariZoneSecretHouseFishingGuruHM03ExplanationText")
		return
	await ow.print_text("_SafariZoneSecretHouseFishingGuruYouHaveWonText")
	if not state.give_item("HM03", 1):
		await ow.print_text("_SafariZoneSecretHouseFishingGuruHM03NoRoomText")
		return
	Text.ram["wStringBuffer"] = GameData.item_name("HM03")
	await ow.print_text("_SafariZoneSecretHouseFishingGuruReceivedHM03Text")
	await Sound.text_sound("sound_get_item_1")
	state.set_event("EVENT_GOT_HM03")
	trace("GOT_HM03")


# --- the gym -------------------------------------------------------------------------------

## FuchsiaGym_Script.
func _gym() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			# FuchsiaGymKogaPostBattleScript
			if not ow.last_battle_won:
				_gym_reset_scripts()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _koga_receive_tm06()
			_gym_reset_scripts()


## FuchsiaGymResetScripts.
func _gym_reset_scripts() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## FuchsiaGymReceiveTM06 (+ .gymVictory): the badge info, TM06 (TOXIC), the SOULBADGE and
## the gym trainers deactivated.
func _koga_receive_tm06() -> void:
	await ow.display_text_id("TEXT_FUCHSIAGYM_KOGA_SOUL_BADGE_INFO", -1)
	state.set_event("EVENT_BEAT_KOGA")
	if state.give_item("TM06", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM06")
		await ow.display_text_id("TEXT_FUCHSIAGYM_KOGA_RECEIVED_TM06", -1)
		state.set_event("EVENT_GOT_TM06")
	else:
		await ow.display_text_id("TEXT_FUCHSIAGYM_KOGA_TM06_NO_ROOM", -1)
	state.badges |= 1 << 4         # BIT_SOULBADGE
	state.beat_gym_flags |= 1 << 4
	for i in 6:                    # deactivate the gym trainers
		state.set_event("EVENT_BEAT_FUCHSIA_GYM_TRAINER_%d" % i)
	trace("KOGA_VICTORY badges=%d tm06=%d" % [state.badges, state.item_count("TM06")])


## FuchsiaGymKogaText.
func _koga_text(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_KOGA"):
		if state.has_event("EVENT_GOT_TM06"):
			await ow.print_text("_FuchsiaGymKogaPostBattleAdviceText")
		else:
			await _koga_receive_tm06()
			_gym_reset_scripts()
			ow.do_not_wait_after_text = true   # DisableWaitingAfterTextDisplay
		return
	await ow.print_text("_FuchsiaGymKogaBeforeBattleText")
	ms.ch9.event_battle(npc_index, 3, "_FuchsiaGymKogaReceivedSoulBadgeText", "", 5)


# --- the Safari Zone gate --------------------------------------------------------------------

## SafariZoneGate_Script (CallFunctionInTable).
func _safari_gate() -> void:
	match ms._script_index():
		0:
			# SafariZoneGateDefaultScript: in front of the counter the worker greets the player
			var idx := SAFARI_ENTRY.find(Vector2i(ow.player.x, ow.player.y)) + 1   # wCoordIndex
			if idx == 0:
				return
			await ow.display_text_id("TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_1", -1)
			ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
			ow.player.facing = Overworld.FACE_RIGHT
			if idx == 1:   # one step left of the counter: walk right first
				_auto_walk(GB.RIGHT, 1)
				ow.joy_ignore = GB.CTRL_PAD
				ms._set_script(1)
			else:
				ms._set_script(2)
		1:
			# SafariZoneGatePlayerMovingRightScript
			if not ow.sim_queue.is_empty():
				return
			await _would_you_like_to_join_script()
		2:
			await _would_you_like_to_join_script()
		3:
			# SafariZoneGatePlayerMovingUpScript
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = 0
			ms._set_script(5)
		4:
			# SafariZoneGatePlayerMovingDownScript
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = 0
			ms._set_script(0)
		5:
			await _leaving_safari()
		6:
			# SafariZoneGateSetScriptAfterMoveScript
			if not ow.sim_queue.is_empty():
				return
			await GB.delay3()
			ms._set_script(next_gate_script)


## SafariZoneEntranceAutoWalk: `count` simulated presses of `dir`.
func _auto_walk(dir: int, count: int) -> void:
	var presses: Array = []
	for i in count:
		presses.append(dir)
	ow.simulate(presses)


## SafariZoneGateWouldYouLikeToJoinScript.
func _would_you_like_to_join_script() -> void:
	ow.joy_ignore = 0
	await ow.display_text_id("TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_WOULD_YOU_LIKE_TO_JOIN", -1)
	ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD


## SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText: ¥500 for 30 SAFARI BALLs and 502
## steps (the counter shows 500), then three steps up into the zone.
func _would_you_like_to_join() -> void:
	await ow.print_text("_SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText")
	Pokemart._money_box(state)
	if not await Menu.yes_no():
		await ow.print_text("_SafariZoneGateSafariZoneWorker1PleaseComeAgainText")
		_auto_walk(GB.DOWN, 1)
		ms._set_script(4)
		return
	if state.money < 500:
		await ow.print_text("_SafariZoneGateSafariZoneWorker1NotEnoughMoneyText")
		_auto_walk(GB.DOWN, 1)
		ms._set_script(4)
		return
	state.money -= 500
	Pokemart._money_box(state)
	await ow.print_text("_SafariZoneGateSafariZoneWorker1ThatllBe500PleaseText")
	await Sound.text_sound("sound_get_item_1")
	await ow.print_text("_SafariZoneGateSafariZoneWorker1CallYouOnThePAText")
	state.safari_balls = 30
	state.safari_steps = 502
	_auto_walk(GB.UP, 3)
	state.set_event("EVENT_IN_SAFARI_ZONE")
	state.events.erase("EVENT_SAFARI_GAME_OVER")
	ms._set_script(3)
	trace("SAFARI_ENTERED money=%d" % state.money)


## SafariZoneGateLeavingSafariScript: back from the zone, after a game over the worker sees
## the player out; otherwise he asks whether to leave early.
func _leaving_safari() -> void:
	ow.player.facing = Overworld.FACE_DOWN   # wPlayerMovingDirection = PLAYER_DIR_DOWN
	if not state.has_event("EVENT_SAFARI_GAME_OVER"):
		await ow.display_text_id("TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_LEAVING_EARLY", -1)
		return
	state.events.erase("EVENT_SAFARI_GAME_OVER")
	state.events.erase("EVENT_IN_SAFARI_ZONE")
	ow.joy_ignore = GB.CTRL_PAD
	await ow.display_text_id("TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1_GOOD_HAUL_COME_AGAIN", -1)
	state.safari_balls = 0
	_auto_walk(GB.DOWN, 3)
	ms._set_script(4)
	trace("SAFARI_LEFT game_over")


## SafariZoneGateSafariZoneWorker1LeavingEarlyText: yes returns the balls and walks the
## player out; no walks them back up into the zone.
func _leaving_early() -> void:
	await ow.print_text("_SafariZoneGateSafariZoneWorker1LeavingEarlyText")
	if await Menu.yes_no():
		await ow.print_text("_SafariZoneGateSafariZoneWorker1ReturnSafariBallsText")
		ow.player.facing = Overworld.FACE_DOWN
		_auto_walk(GB.DOWN, 3)
		state.events.erase("EVENT_SAFARI_GAME_OVER")
		state.events.erase("EVENT_IN_SAFARI_ZONE")
		next_gate_script = 0
		trace("SAFARI_LEFT early")
	else:
		await ow.print_text("_SafariZoneGateSafariZoneWorker1GoodLuckText")
		ow.player.facing = Overworld.FACE_UP
		_auto_walk(GB.UP, 1)
		next_gate_script = 5
	ms._set_script(6)


## PrintSafariGameOverText: "time's up" when balls are left, then "game over".
func _safari_game_over_text() -> void:
	ow.joy_ignore = 0
	if state.safari_balls > 0:
		await ow.print_text("_TimesUpText")
	await ow.print_text("_GameOverText")


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER11 %s frame=%d" % [message, GB.frame_count])
