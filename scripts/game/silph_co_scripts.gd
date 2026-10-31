## Silph Co. (scripts/SilphCo1F.asm ... SilphCo11F.asm, SilphCoElevator.asm): the CARD KEY
## doors (engine/events/card_key.asm PrintCardKeyText and each floor's gate callback), the
## rival on 7F, Giovanni on 11F and Team Rocket leaving, the workers' texts before and
## after, LAPRAS, the MASTER BALL, the 9F nurse and the elevator.
class_name SilphCoScripts
extends RefCounted

const ELEVATOR_FLOORS := ["FLOOR_1F", "FLOOR_2F", "FLOOR_3F", "FLOOR_4F", "FLOOR_5F", "FLOOR_6F",
	"FLOOR_7F", "FLOOR_8F", "FLOOR_9F", "FLOOR_10F", "FLOOR_11F"]
## SilphCoElevatorWarpMaps (destination warp 0-based, map)
const ELEVATOR_WARPS := [[2, "SILPH_CO_1F"], [1, "SILPH_CO_2F"], [1, "SILPH_CO_3F"], [1, "SILPH_CO_4F"],
	[1, "SILPH_CO_5F"], [1, "SILPH_CO_6F"], [1, "SILPH_CO_7F"], [1, "SILPH_CO_8F"], [1, "SILPH_CO_9F"],
	[1, "SILPH_CO_10F"], [0, "SILPH_CO_11F"]]
## The CARD KEY doors of each floor (SilphCoXFGateCallbackScript .GateCoordinates and its
## ReplaceTileBlock calls): block (x, y), the "unlocked" event, the closed door block. The
## map data has every door open; the callback closes the ones not unlocked yet.
const DOORS := {
	"SILPH_CO_2F": [[Vector2i(2, 2), "EVENT_SILPH_CO_2_UNLOCKED_DOOR1", 0x54], [Vector2i(2, 5), "EVENT_SILPH_CO_2_UNLOCKED_DOOR2", 0x54]],
	"SILPH_CO_3F": [[Vector2i(4, 4), "EVENT_SILPH_CO_3_UNLOCKED_DOOR1", 0x5f], [Vector2i(8, 4), "EVENT_SILPH_CO_3_UNLOCKED_DOOR2", 0x5f]],
	"SILPH_CO_4F": [[Vector2i(2, 6), "EVENT_SILPH_CO_4_UNLOCKED_DOOR1", 0x54], [Vector2i(6, 4), "EVENT_SILPH_CO_4_UNLOCKED_DOOR2", 0x54]],
	"SILPH_CO_5F": [[Vector2i(3, 2), "EVENT_SILPH_CO_5_UNLOCKED_DOOR1", 0x5f], [Vector2i(3, 6), "EVENT_SILPH_CO_5_UNLOCKED_DOOR2", 0x5f],
		[Vector2i(7, 5), "EVENT_SILPH_CO_5_UNLOCKED_DOOR3", 0x5f]],
	"SILPH_CO_6F": [[Vector2i(2, 6), "EVENT_SILPH_CO_6_UNLOCKED_DOOR", 0x5f]],
	"SILPH_CO_7F": [[Vector2i(5, 3), "EVENT_SILPH_CO_7_UNLOCKED_DOOR1", 0x54], [Vector2i(10, 2), "EVENT_SILPH_CO_7_UNLOCKED_DOOR2", 0x54],
		[Vector2i(10, 6), "EVENT_SILPH_CO_7_UNLOCKED_DOOR3", 0x54]],
	"SILPH_CO_8F": [[Vector2i(3, 4), "EVENT_SILPH_CO_8_UNLOCKED_DOOR", 0x5f]],
	"SILPH_CO_9F": [[Vector2i(1, 4), "EVENT_SILPH_CO_9_UNLOCKED_DOOR1", 0x5f], [Vector2i(9, 2), "EVENT_SILPH_CO_9_UNLOCKED_DOOR2", 0x54],
		[Vector2i(9, 5), "EVENT_SILPH_CO_9_UNLOCKED_DOOR3", 0x54], [Vector2i(5, 6), "EVENT_SILPH_CO_9_UNLOCKED_DOOR4", 0x5f]],
	"SILPH_CO_10F": [[Vector2i(5, 4), "EVENT_SILPH_CO_10_UNLOCKED_DOOR", 0x54]],
	"SILPH_CO_11F": [[Vector2i(3, 6), "EVENT_SILPH_CO_11_UNLOCKED_DOOR", 0x20]],
}
## SilphCo11FTeamRocketLeavesScript: the objects hidden (Team Rocket and the Saffron
## Rockets) and shown (Saffron's townspeople) once Giovanni is beaten, by map and index.
const ROCKET_LEAVES_HIDE := {
	"SAFFRON_CITY": [0, 1, 2, 3, 4, 5, 6, 13, 14],
	"SILPH_CO_2F": [1, 2, 3, 4], "SILPH_CO_3F": [1, 2], "SILPH_CO_4F": [1, 2, 3], "SILPH_CO_5F": [1, 2, 3, 4],
	"SILPH_CO_6F": [5, 6, 7], "SILPH_CO_7F": [4, 5, 6, 7], "SILPH_CO_8F": [1, 2, 3], "SILPH_CO_9F": [1, 2, 3],
	"SILPH_CO_10F": [0, 1], "SILPH_CO_11F": [2, 3, 4],
}
const ROCKET_LEAVES_SHOW := {"SAFFRON_CITY": [7, 8, 9, 10, 11, 12]}
const RIVAL := 8         # SILPHCO7F_RIVAL
const GIOVANNI := 2      # SILPHCO11F_GIOVANNI
const GOT_LAPRAS := "GOT_LAPRAS"   # wStatusFlags4 BIT_GOT_LAPRAS, kept with the events

var chapter: Chapter9Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState
var elevator := Elevator.new()
var card_key_door := Vector2i(0, 0)   # wCardKeyDoorY/X: the block the CARD KEY just opened
var gate_reload := false              # BIT_CUR_MAP_LOADED_1 set again by PrintCardKeyText
var saved_coord_index := 0            # wSavedCoordIndex (1-based, like wCoordIndex)
var seen_load := -1                   # the map load the gate callback last ran for


func _init(c: Chapter9Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script() -> bool:
	if not ow.map_id.begins_with("SILPH_CO_"):
		return false
	# the gate callbacks run on every map load (a warp inside the floor included)
	var loaded := seen_load != ow.load_count
	seen_load = ow.load_count
	match ow.map_id:
		"SILPH_CO_1F":
			_receptionist()
		"SILPH_CO_7F":
			if loaded or gate_reload:
				_gate_callback()
			match ms._script_index():
				0: await _7f_default()
				3: await _7f_rival_start_battle()
				4: await _7f_rival_after_battle()
				5: await _7f_rival_exit()
				_: await _trainer_scripts()
		"SILPH_CO_11F":
			if loaded or gate_reload:
				_gate_callback()
			match ms._script_index():
				0: await _11f_default()
				3: await _11f_giovanni_facing()
				4: _11f_giovanni_start_battle()
				5: await _11f_giovanni_after_battle()
				_: await _trainer_scripts()
		"SILPH_CO_ELEVATOR":
			await elevator.run_map_script(ow, loaded, true)
		_:
			if loaded or gate_reload:
				_gate_callback()
			await _trainer_scripts()
	return true


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, _npc_index: int) -> bool:
	match text_id:
		"TEXT_SILPHCO2F_SILPH_WORKER_F": await _tm36()
		"TEXT_SILPHCO3F_SILPH_WORKER_M":
			await _before_after("_SilphCo3FSilphWorkerMWhatShouldIDoText", "_SilphCo3FSilphWorkerMYouSavedUsText")
		"TEXT_SILPHCO4F_SILPH_WORKER_M":
			await _before_after("_SilphCo4FSilphWorkerMImHidingText", "_SilphCo4FSilphWorkerMTeamRocketIsGoneText")
		"TEXT_SILPHCO5F_SILPH_WORKER_M":
			await _before_after("_SilphCo5FSilphWorkerMThatsYouRightText", "_SilphCo5FSilphWorkerMYoureOurHeroText")
		"TEXT_SILPHCO6F_SILPH_WORKER_M1":
			await _before_after("_SilphCo6FSilphWorkerM1TookOverTheBuildingText", "_SilphCo6FSilphWorkerM1BackToWorkText")
		"TEXT_SILPHCO6F_SILPH_WORKER_M2":
			await _before_after("_SilphCo6FSilphWorkerMHelpMePleaseText", "_SilphCo6FSilphWorkerMWeGotEngagedText")
		"TEXT_SILPHCO6F_SILPH_WORKER_F1":
			await _before_after("_SilphCo6FSilphWorkerF1SuchACowardText", "_SilphCo6FSilphWorkerF1HaveToMarryHimText")
		"TEXT_SILPHCO6F_SILPH_WORKER_F2":
			await _before_after("_SilphCo6FSilphWorkerF2TeamRocketConquerWorldText", "_SilphCo6FSilphWorkerF2TeamRocketRanText")
		"TEXT_SILPHCO6F_SILPH_WORKER_M3":
			await _before_after("_SilphCo6FSilphWorkerM3TargetedSilphText", "_SilphCo6FSilphWorkerM3WorkForSilphText")
		"TEXT_SILPHCO7F_SILPH_WORKER_M1": await _lapras_guy()
		"TEXT_SILPHCO7F_SILPH_WORKER_M2":
			await _before_after("_SilphCo7FSilphWorkerM2AfterTheMasterBallText", "_SilphCo7FSilphWorkerM2CancelledMasterBallText")
		"TEXT_SILPHCO7F_SILPH_WORKER_M3":
			await _before_after("_SilphCo7FSilphWorkerM3ItWouldBeBadText", "_SilphCo7FSilphWorkerM3YouChasedOffTeamRocketText")
		"TEXT_SILPHCO7F_SILPH_WORKER_M4":
			await _before_after("_SilphCo7FSilphWorkerM4ItsReallyDangerousHereText", "_SilphCo7FSilphWorkerM4SafeAtLastText")
		"TEXT_SILPHCO7F_RIVAL": await ow.print_text("_SilphCo7FRivalText")
		"TEXT_SILPHCO8F_SILPH_WORKER_M":
			await _before_after("_SilphCo8FSilphWorkerMSilphIsFinishedText", "_SilphCo8FSilphWorkerMThanksForSavingUsText")
		"TEXT_SILPHCO9F_NURSE": await _nurse()
		"TEXT_SILPHCO10F_SILPH_WORKER_F":
			await _before_after("_SilphCo10FSilphWorkerFImScaredText", "_SilphCo10FSilphWorkerFQuietAboutMyCryingText")
		"TEXT_SILPHCO11F_SILPH_PRESIDENT": await _president()
		"TEXT_SILPHCOELEVATOR_ELEVATOR":
			await elevator.floor_menu(ow, ELEVATOR_FLOORS, ELEVATOR_WARPS)
		_:
			return false
	return true


## CheckFightingMapTrainers / DisplayEnemyTrainerTextAndStartBattle / EndTrainerBattle.
func _trainer_scripts() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()


## SilphCo6FBeatGiovanniPrintDEOrPrintHLScript: `before` until Giovanni is beaten.
func _before_after(before: String, after: String) -> void:
	await ow.print_text(after if state.has_event("EVENT_BEAT_SILPH_CO_GIOVANNI") else before)


# --- the CARD KEY doors ----------------------------------------------------------------------

## SilphCoXFGateCallbackScript (BIT_CUR_MAP_LOADED_1): the door the CARD KEY just opened
## becomes unlocked for good (SilphCoXF_SetCardKeyDoorYScript + the UnlockedDoorEvent
## script), then every door of the floor that is still locked is drawn closed.
func _gate_callback() -> void:
	gate_reload = false
	var doors: Array = DOORS.get(ow.map_id, [])
	var unlocked := 0   # hUnlockedSilphCoDoors (1-based)
	for i in doors.size():
		if doors[i][0] == card_key_door:
			unlocked = i + 1
			card_key_door = Vector2i(0, 0)
			break
	if unlocked > 0:
		state.set_event(str(doors[unlocked - 1][1]))
		chapter.trace("CARD_KEY_DOOR_UNLOCKED %s %d" % [ow.map_id, unlocked])
	for d in doors:
		if not state.has_event(str(d[1])):
			_replace_block(d[0].x, d[0].y, int(d[2]))


## PrintCardKeyText: on Silph Co. 2F-11F, A in front of a closed door (tiles $18/$24 of the
## FACILITY tileset, $5E on 11F) opens it with the CARD KEY: "Bingo!", the block becomes
## floor ($0E, $03 on 11F) and the gate callback runs again; without the key "Darn!".
## Returns true when a door was in front.
func card_key() -> bool:
	if not DOORS.has(ow.map_id):   # SilphCoMapList
		return false
	var d: Vector2i = ow._facing_delta()
	var tx: int = ow.player.x + d.x
	var ty: int = ow.player.y + d.y
	var tile: int = ow._tile_id_under(tx, ty)
	if not (tile in [0x18, 0x24] or (ow.map_id == "SILPH_CO_11F" and tile == 0x5e)):
		return false
	if state.item_count("CARD_KEY") == 0:
		chapter.trace("CARD_KEY_MISSING %s tile=%02x" % [ow.map_id, tile])
		await ow._show_overworld_text("_CardKeyFailText", true)
		return true
	# CardKeySuccessText (PrintPredefTextID): the two parts around SFX_GET_ITEM_1
	ow.in_text = true
	Menu.message_box()
	await GB.delay3()
	await Text.print_text_no_box("_CardKeySuccessText1")
	await Sound.text_sound("sound_get_item_1")
	await Text.print_text_no_box("_CardKeySuccessText2")
	await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	ow.in_text = false
	card_key_door = Vector2i(tx >> 1, ty >> 1)
	_replace_block(card_key_door.x, card_key_door.y, 0x03 if ow.map_id == "SILPH_CO_11F" else 0x0e)
	gate_reload = true
	Sound.play_sfx("SFX_GO_INSIDE")
	ow._render()
	chapter.trace("CARD_KEY_USED %s block=(%d,%d)" % [ow.map_id, card_key_door.x, card_key_door.y])
	return true


## ReplaceTileBlock on the loaded map (kept across redraws like the Cut blocks).
func _replace_block(bx: int, by: int, block: int) -> void:
	ow.cut_blocks[Vector2i(bx, by)] = block
	ow._put_block(bx, by, block, ow.tileset)


# --- 1F --------------------------------------------------------------------------------------

## SilphCo1F_Script: once Giovanni is beaten the receptionist is back at her desk.
func _receptionist() -> void:
	if not state.has_event("EVENT_BEAT_SILPH_CO_GIOVANNI") or state.has_event("EVENT_SILPH_CO_RECEPTIONIST_AT_DESK"):
		return
	state.set_event("EVENT_SILPH_CO_RECEPTIONIST_AT_DESK")
	ow.show_object(0)   # TOGGLE_SILPH_CO_1F_RECEPTIONIST


# --- 7F: the rival ---------------------------------------------------------------------------

## SilphCo7FDefaultScript: on (3,2) or (3,3) the rival music plays and he walks up.
func _7f_default() -> void:
	var idx := [Vector2i(3, 2), Vector2i(3, 3)].find(Vector2i(ow.player.x, ow.player.y)) + 1   # wCoordIndex
	if state.has_event("EVENT_BEAT_SILPH_CO_RIVAL") or idx == 0:
		await ms.trainers.check_fighting_map_trainers()
		return
	ow.joy_ignore = GB.CTRL_PAD
	ow.player.facing = Overworld.FACE_DOWN
	Sound.stop_all_music()
	Sound.play_music("MUSIC_MEET_RIVAL")
	await ow.display_text_id("TEXT_SILPHCO7F_RIVAL", RIVAL)
	saved_coord_index = idx
	var moves: Array = []
	for i in (4 if idx == 1 else 3):   # .RivalMovementUp, one step less from the lower tile
		moves.append(Overworld.NPC_UP)
	ow.move_sprite(RIVAL, moves)
	ms._set_script(3)
	chapter.trace("SILPH_RIVAL idx=%d" % idx)


## SilphCo7FRivalStartBattleScript.
func _7f_rival_start_battle() -> void:
	if ow.npc_moving(RIVAL):
		return
	ow.joy_ignore = 0
	await ow.display_text_id("TEXT_SILPHCO7F_RIVAL_WAITED_HERE", -1)
	await GB.delay3()
	var team: int = {"SQUIRTLE": 7, "BULBASAUR": 8, "CHARMANDER": 9}.get(state.rival_starter, 9)
	ow.battle_request = {"trainer": "RIVAL2", "team": team, "name": state.rival_name,
		"win_text": "_SilphCo7FRivalDefeatedText", "lose_text": "_SilphCo7FRivalVictoryText"}
	ms._set_script(4)


## SilphCo7FRivalAfterBattleScript: "good luck", then the rival walks out (around the player
## from the lower tile, straight right from the upper one).
func _7f_rival_after_battle() -> void:
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # SilphCo7FSetDefaultScript
		ms._set_script(0)
		return
	ow.joy_ignore = GB.CTRL_PAD
	state.set_event("EVENT_BEAT_SILPH_CO_RIVAL")
	ow.player.facing = Overworld.FACE_DOWN
	ow.set_npc_facing(RIVAL, Overworld.FACE_UP)
	await GB.delay3()
	await ow.display_text_id("TEXT_SILPHCO7F_RIVAL_GOOD_LUCK_TO_YOU", -1)
	Sound.stop_all_music()
	Sound.rival_alternate_start()
	var moves: Array
	if saved_coord_index == 1:
		moves = [Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]   # .RivalExitRightMovement
	else:
		moves = [Overworld.NPC_LEFT, Overworld.NPC_UP, Overworld.NPC_UP, Overworld.NPC_RIGHT,
			Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_DOWN]   # .RivalWalkAroundPlayerMovement
	ow.move_sprite(RIVAL, moves)
	ms._set_script(5)


## SilphCo7FRivalExitScript.
func _7f_rival_exit() -> void:
	if ow.npc_moving(RIVAL):
		return
	ow.hide_object(RIVAL)   # TOGGLE_SILPH_CO_7F_RIVAL
	await Sound.play_default_music()
	ow.joy_ignore = 0
	ms._set_script(0)
	chapter.trace("SILPH_RIVAL_LEFT")


# --- 11F: Giovanni ---------------------------------------------------------------------------

## SilphCo11FDefaultScript: on (6,13) or (7,12) Giovanni speaks and walks three steps down.
func _11f_default() -> void:
	if state.has_event("EVENT_BEAT_SILPH_CO_GIOVANNI"):
		return
	var idx := [Vector2i(6, 13), Vector2i(7, 12)].find(Vector2i(ow.player.x, ow.player.y)) + 1
	if idx == 0:
		await ms.trainers.check_fighting_map_trainers()
		return
	saved_coord_index = idx
	ow.joy_ignore = GB.CTRL_PAD
	await ow.display_text_id("TEXT_SILPHCO11F_GIOVANNI", GIOVANNI)
	ow.move_sprite(GIOVANNI, [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
	ms._set_script(3)
	chapter.trace("SILPH_GIOVANNI idx=%d" % idx)


## SilphCo11FSetPlayerAndSpriteFacingDirectionScript: face each other (up/down from the
## first tile, left/right from the second) with Delay3.
func _face_giovanni() -> void:
	if saved_coord_index == 1:
		ow.player.facing = Overworld.FACE_UP
		ow.set_npc_facing(GIOVANNI, Overworld.FACE_DOWN)
	else:
		ow.player.facing = Overworld.FACE_LEFT
		ow.set_npc_facing(GIOVANNI, Overworld.FACE_RIGHT)
	await GB.delay3()


## SilphCo11FGiovanniBattleFacingScript.
func _11f_giovanni_facing() -> void:
	if ow.npc_moving(GIOVANNI):
		return
	await _face_giovanni()
	await GB.delay3()
	ms._set_script(4)


## SilphCo11FGiovanniStartBattleScript.
func _11f_giovanni_start_battle() -> void:
	chapter.event_battle(GIOVANNI, 5, "_SilphCo11FGiovanniILostAgainText")
	ow.joy_ignore = 0


## SilphCo11FGiovanniAfterBattleScript: "you ruined our plans", a black fade while Team
## Rocket leaves the building and the city.
func _11f_giovanni_after_battle() -> void:
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # SilphCo11FResetCurScript
		ms._set_script(0)
		return
	await _face_giovanni()
	ow.joy_ignore = GB.CTRL_PAD
	await ow.display_text_id("TEXT_SILPHCO11F_GIOVANNI_YOU_RUINED_OUR_PLANS", -1)
	await Intro.fade_out_to_black()
	_team_rocket_leaves()
	await GB.delay3()
	await Intro.fade_in_from_black()
	state.set_event("EVENT_BEAT_SILPH_CO_GIOVANNI")
	ow.joy_ignore = 0
	ms._set_script(0)
	chapter.trace("SILPH_GIOVANNI_BEATEN")


## SilphCo11FTeamRocketLeavesScript.
func _team_rocket_leaves() -> void:
	for map in ROCKET_LEAVES_HIDE:
		for i in ROCKET_LEAVES_HIDE[map]:
			if map == ow.map_id:
				ow.hide_object(i)
			else:
				ms.ch8._show(map, i, false)
	for map in ROCKET_LEAVES_SHOW:
		for i in ROCKET_LEAVES_SHOW[map]:
			ms.ch8._show(map, i, true)


# --- texts -----------------------------------------------------------------------------------

## SilphCo2FSilphWorkerFText: TM36 (SELFDESTRUCT) once.
func _tm36() -> void:
	if state.has_event("EVENT_GOT_TM36"):
		await ow.print_text("_SilphCo2FSilphWorkerFTM36ExplanationText")
		return
	await ow.print_text("SilphCo2FSilphWorkerFPleaseTakeThisText")
	if state.give_item("TM36", 1):
		state.set_event("EVENT_GOT_TM36")
		Text.ram["wStringBuffer"] = GameData.item_name("TM36")
		await ow.print_text("_SilphCo2FSilphWorkerFReceivedTM36Text")
		await Sound.text_sound("sound_get_item_1")
		chapter.trace("GOT_TM36")
	else:
		await ow.print_text("_SilphCo2FSilphWorkerFTM36NoRoomText")


## SilphCo7FSilphWorkerM1Text: LAPRAS (level 15) once (wStatusFlags4 BIT_GOT_LAPRAS); when
## it went to a box the description waits for a button first.
func _lapras_guy() -> void:
	if state.has_event(GOT_LAPRAS):
		await _before_after("_SilphCo7FSilphWorkerM1IsOurPresidentOkText", "_SilphCo7FSilphWorkerM1SavedText")
		return
	await ow.print_text("_SilphCo7FSilphWorkerM1HaveThisPokemonText")
	var before := state.party.size()
	if not await GivePokemon.give(ow, "LAPRAS", 15):
		return
	if state.party.size() == before:   # wAddedToParty = 0
		await Text.wait_scroll_button(false)
	await ow.print_text("_SilphCo7FSilphWorkerM1LaprasDescriptionText")
	state.set_event(GOT_LAPRAS)
	chapter.trace("GOT_LAPRAS party=%d" % state.party.size())


## SilphCo9FNurseText: a heal with a white fade until Giovanni is beaten.
func _nurse() -> void:
	if state.has_event("EVENT_BEAT_SILPH_CO_GIOVANNI"):
		await ow.print_text("SilphCo9FNurseThankYouText")
		return
	await ow.print_text("SilphCo9FNurseYouLookTiredText")
	Battle.heal_party(state)
	await Intro.fade_out_to_white()
	await GB.delay3()
	await Intro.fade_in_from_white()
	await ow.print_text("SilphCo9FNurseDontGiveUpText")
	chapter.trace("SILPH_NURSE_HEALED")


## SilphCo11FSilphPresidentText: the MASTER BALL once.
func _president() -> void:
	if state.has_event("EVENT_GOT_MASTER_BALL"):
		await ow.print_text("_SilphCo11FSilphPresidentMasterBallDescriptionText")
		return
	await ow.print_text("_SilphCo11FSilphPresidentText")
	if state.give_item("MASTER_BALL", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("MASTER_BALL")
		await ow.print_text("_SilphCo11FSilphPresidentReceivedMasterBallText")
		await Sound.text_sound("sound_get_key_item")
		state.set_event("EVENT_GOT_MASTER_BALL")
		chapter.trace("GOT_MASTER_BALL")
	else:
		await ow.print_text("_SilphCo11FSilphPresidentNoRoomText")
