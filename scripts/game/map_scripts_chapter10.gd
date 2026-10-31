## Chapter 10 map scripts and text handlers: Routes 13-18 around Fuchsia City
## (scripts/Route13.asm ... Route18.asm are only the trainer engine), the Cycling Road gates
## (Route16Gate1F.asm, Route18Gate1F.asm: no way in without a BICYCLE), the gates' upper
## floors (Route15Gate2F.asm: Oak's aide and the EXP.ALL, Route16Gate2F.asm, Route18Gate2F.asm:
## the trade for a LICKITUNG), the second SNORLAX (Route16.asm) and the HM02 house
## (Route16FlyHouse.asm). The Cycling Road itself (forced riding, the slope) is in Overworld.
class_name Chapter10Scripts
extends RefCounted

const SNORLAX := 6   # ROUTE16_SNORLAX

var ms: MapScripts
var ow: Overworld
var state: GameState


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script (see MtMoonScripts.run_map_script for the contract).
func run_map_script() -> bool:
	match ow.map_id:
		"ROUTE_16":
			match ms._script_index():
				0: await _route16_default()
				3: await _snorlax_post_battle()
				_: await _trainer_scripts()
		"ROUTE_16_GATE_1F":
			state.always_on_bike = false   # res BIT_ALWAYS_ON_BIKE
			await _cycling_road_gate([Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10)],
				"TEXT_ROUTE16GATE1F_GUARD_WAIT_UP", "TEXT_ROUTE16GATE1F_GUARD")
		"ROUTE_18_GATE_1F":
			state.always_on_bike = false
			await _cycling_road_gate([Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6)],
				"TEXT_ROUTE18GATE1F_GUARD_EXCUSE_ME", "TEXT_ROUTE18GATE1F_GUARD")
		"ROUTE_15_GATE_2F", "ROUTE_16_GATE_2F", "ROUTE_18_GATE_2F":
			ow.no_auto_text_box = true   # DisableAutoTextBoxDrawing
		"ROUTE_15_GATE_1F", "ROUTE_16_FLY_HOUSE":
			pass   # EnableAutoTextBoxDrawing only
		_:
			return false
	return true


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, _npc_index: int) -> bool:
	match text_id:
		"TEXT_ROUTE16GATE1F_GUARD":
			await ow.print_text("_Route16Gate1FGuardCyclingRoadExplanationText" if _has_bicycle() else "_Route16Gate1FGuardNoPedestriansAllowedText")
		"TEXT_ROUTE18GATE1F_GUARD":
			await ow.print_text("_Route18Gate1FGuardCyclingRoadUphillText" if _has_bicycle() else "_Route18Gate1FGuardYouNeedABicycleText")
		"TEXT_ROUTE15GATE2F_OAKS_AIDE":
			await ms.ch6._oaks_aide(50, "EXP_ALL", "EVENT_GOT_EXP_ALL", "_Route15Gate2FOaksAideExpAllText")
		"TEXT_ROUTE15GATE2F_BINOCULARS": await ms.ch6._print_if_facing_up("_Route15Gate2FBinocularsText")
		"TEXT_ROUTE16GATE2F_LEFT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route16Gate2FLeftBinocularsText")
		"TEXT_ROUTE16GATE2F_RIGHT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route16Gate2FRightBinocularsText")
		"TEXT_ROUTE18GATE2F_LEFT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route18Gate2FLeftBinocularsText")
		"TEXT_ROUTE18GATE2F_RIGHT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route18Gate2FRightBinocularsText")
		"TEXT_ROUTE18GATE2F_YOUNGSTER": await InGameTrade.dialogue(ow, state, InGameTrade.TRADE_FOR_MARC)
		"TEXT_ROUTE16FLYHOUSE_BRUNETTE_GIRL": await _hm02()
		"TEXT_ROUTE16FLYHOUSE_FEAROW":
			await ow.print_text("_Route16FlyHouseFearowText")
			Sound.play_cry("FEAROW")
			await Sound.wait_for_sfx()   # WaitForSoundToFinish
		_:
			return false
	return true


## CheckFightingMapTrainers / DisplayEnemyTrainerTextAndStartBattle / EndTrainerBattle.
func _trainer_scripts() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()


## Route16Gate1FIsBicycleInBagScript.
func _has_bicycle() -> bool:
	return state.item_count("BICYCLE") > 0


# --- the Cycling Road gates --------------------------------------------------------------

## Route16Gate1FDefaultScript / Route18Gate1FDefaultScript and the moving scripts: without a
## BICYCLE the guard stops the player on the column in front of the counter ("wait up"),
## walks them up to the counter, speaks and pushes them one step right.
func _cycling_road_gate(stops: Array, stop_text: String, guard_text: String) -> void:
	match ms._script_index():
		0:
			if _has_bicycle():
				return
			var idx := stops.find(Vector2i(ow.player.x, ow.player.y)) + 1   # wCoordIndex
			if idx == 0:
				return
			await ow.display_text_id(stop_text, -1)
			trace("GATE_STOP %s idx=%d" % [ow.map_id, idx])
			if idx == 1:
				ms._set_script(2)
				return
			var ups: Array = []
			for i in idx - 1:
				ups.append(GB.UP)
			ow.simulate(ups)
			ms._set_script(1)
		1:
			# Route16Gate1FPlayerMovingUpScript
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _gate_guard(guard_text)
		2:
			await _gate_guard(guard_text)
		3:
			# Route16Gate1FPlayerMovingRightScript
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = 0
			ms._set_script(0)
			trace("GATE_PUSHED %s (%d,%d)" % [ow.map_id, ow.player.x, ow.player.y])


## Route16Gate1FGuardScript.
func _gate_guard(guard_text: String) -> void:
	await ow.display_text_id(guard_text, -1)
	ow.simulate([GB.RIGHT])
	ms._set_script(3)


# --- Route 16 ----------------------------------------------------------------------------

## Route16DefaultScript: the POKé FLUTE flag wakes the second SNORLAX for a level 30 wild
## battle; the sleeping sprite goes away.
func _route16_default() -> void:
	if state.has_event("EVENT_BEAT_ROUTE16_SNORLAX") or not state.has_event("EVENT_FIGHT_ROUTE16_SNORLAX"):
		await ms.trainers.check_fighting_map_trainers()
		return
	state.events.erase("EVENT_FIGHT_ROUTE16_SNORLAX")
	await ow.display_text_id("TEXT_ROUTE16_SNORLAX_WOKE_UP", -1)
	ow.battle_request = {"wild": true, "species": "SNORLAX", "level": 30}
	ow.hide_object(SNORLAX)   # TOGGLE_ROUTE_16_SNORLAX
	ms._set_script(3)
	trace("SNORLAX_BATTLE")


## Route16SnorlaxPostBattleScript: "SNORLAX returned to the mountains" unless it was caught
## or the player ran (wBattleResult 2, like Route 12); either way it is gone.
func _snorlax_post_battle() -> void:
	if ow.last_battle_result in ["lost", "blackout"]:
		ow.joy_ignore = 0   # Route16ResetScripts
		ms._set_script(0)
		return
	if ow.last_battle_result == "won":
		await ow.display_text_id("TEXT_ROUTE16_SNORLAX_RETURNED_TO_MOUNTAINS", -1)
	state.set_event("EVENT_BEAT_ROUTE16_SNORLAX")
	await GB.delay3()
	ms._set_script(0)
	trace("SNORLAX_DONE result=%s" % ow.last_battle_result)


## Route16FlyHouseBrunetteGirlText: HM02 (FLY) once.
func _hm02() -> void:
	if state.has_event("EVENT_GOT_HM02"):
		await ow.print_text("_Route16FlyHouseBrunetteGirlHM02ExplanationText")
		return
	await ow.print_text("_Route16FlyHouseBrunetteGirlText")
	if not state.give_item("HM02", 1):
		await ow.print_text("_Route16FlyHouseBrunetteGirlHM02NoRoomText")
		return
	state.set_event("EVENT_GOT_HM02")
	Text.ram["wStringBuffer"] = GameData.item_name("HM02")
	await ow.print_text("_Route16FlyHouseBrunetteGirlReceivedHM02Text")
	await Sound.text_sound("sound_get_key_item")
	trace("GOT_HM02")


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER10 %s frame=%d" % [message, GB.frame_count])
